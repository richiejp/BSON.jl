struct ParseCtx
  refindx::Vector{Pair{BSONType, Int}}
  refs::Vector{Any}
  cur_ref::Int
end

ParseCtx() = ParseCtx([], [], -1)

struct ParseArrayIter{T <: IO}
  io::T
  ctx::ParseCtx
end

function Base.iterate(itr::ParseArrayIter)
  len = read(itr.io, Int32)

  iterate(itr, 0)
end

function Base.iterate(itr::ParseArrayIter, ::Int)
  tag = read(itr.io, BSONType)
  tag == eof && return nothing

  while read(itr.io, UInt8) != 0x00 end

  (parse_tag(itr.io, tag, itr.ctx), 0)
end

function skip_over(io::IO, tag::BSONType)
  len = if tag == document || tag == array
    read(io, Int32) - 4
  elseif tag == string
    read(io, Int32)
  elseif tag == binary
    read(io, Int32) + 1
  elseif tag == null
    0
  else
    sizeof(jtype(tag))
  end

  seek(io, position(io) + len)
  @info "Skipped" tag len position(io)
end

"Create an index into the _backrefs entry in the root document"
function build_refs_indx!(io::IO, ctx::ParseCtx)
  # read the length of the root document
  len = read(io, Int32)
  @info "BSON document is $len bytes"

  while (tag = read(io, BSONType)) ≠ eof
    name = parse_cstr_unsafe(io)
    @info "Element head" String(name) tag position(io)

    if name == b"_backrefs"
      if tag != array
        error("_backrefs is not an array; tag = $tag")
      end

      len = read(io, Int32)
      @info "Processing _backrefs" position(io) len

      while (tag = read(io, BSONType)) ≠ eof
        while read(io, UInt8) ≠ 0x00 end

        push!(ctx.refindx, tag => position(io))
        push!(ctx.refs, nothing)
        skip_over(io, tag)
      end
    else
      @info "Skipping $(String(name))"
      skip_over(io, tag)
    end
  end

  seek(io, 0)
end

function parse_tag(io::IO, tag::BSONType, ctx::ParseCtx)
  if tag == null
    nothing
  elseif tag == document
    parse_doc(io, ctx)
  elseif tag == array
    parse_any_array(io, ctx)
  elseif tag == string
    len = read(io, Int32)-1
    s = String(read(io, len))
    eof = read(io, 1)
    s
  elseif tag == binary
    len = read(io, Int32)
    subtype = read(io, 1)
    read(io, len)
  else
    read(io, jtype(tag))
  end
end

function parse_any_array(io::IO, ctx::ParseCtx)::BSONArray
  len = read(io, Int32)
  ps = BSONArray()

  while (tag = read(io, BSONType)) ≠ eof
    # Note that arrays are dicts with the index as the key
    while read(io, UInt8) != 0x00
      nothing
    end
    push!(ps, parse_tag(io, tag, ctx))
  end

  ps
end

function parse_symbol(io::IO, name_pos::Int, ctx::ParseCtx)::Symbol
  endpos = position(io)

  seek(io, name_pos)
  len = read(io, Int32)-1
  s = Symbol(read(io, len))

  seek(io, endpos)
  s
end

function parse_tuple(io::IO, data_pos::Int, ctx::ParseCtx)::Tuple
  endpos = position(io)
  seek(io, data_pos)
  res = (ParseArrayIter(io, ctx)...,)
  seek(io, endpos)
  res
end

function parse_svec(io::IO, data_pos::Int, ctx::ParseCtx)::Core.SimpleVector
  endpos = position(io)
  seek(io, data_pos)
  res = Core.svec(ParseArrayIter(io, ctx)...)
  seek(io, endpos)
  res
end

function parse_any_doc(io::IO, ctx::ParseCtx)::BSONDict
  len = read(io, Int32)
  dic = BSONDict()

  while (tag = read(io, BSONType)) ≠ eof
    k = Symbol(parse_cstr(io))
    dic[k] = parse_tag(io, tag, ctx)
  end

  dic
end

function parse_doc(io::IO, ctx::ParseCtx)
  start = position(io)
  len = read(io, Int32)

  seen::Int64 = 0
  see(it::Int64) = seen = seen | it
  saw(it::Int64)::Bool = seen & it != 0
  only_saw(it::Int64)::Bool = seen == it

  # First decide if this document is tagged with a Julia type. Saving the BSON tag types
  local tref, tdata, ttype, ttypename, ttag, tname, tparams, tpath, tsize, tvar, tbody
  local k::AbstractVector{UInt8}

  for _ in 1:6
    if (tag = read(io, BSONType)) == eof
      break
    end
    k = parse_cstr_unsafe(io)
    @info "Read key" String(k)

    if k == b"tag"
      see(SEEN_TAG)
      if tag == string && (dtag = parse_doc_tag(io)) isa Int64
        @info "Read tag" dtag
        see(dtag)
        continue
      else
        break
      end
    end

    if k == b"ref"
      see(SEEN_REF)
      tref = (tag, position(io))
    elseif k == b"data"
      see(SEEN_DATA)
      tdata = (tag, position(io))
    elseif k == b"type"
      see(SEEN_TYPE)
      ttype = (tag, position(io))
    elseif k == b"typename"
      see(SEEN_TYPENAME)
      ttypename = (tag, position(io))
    elseif k == b"name"
      see(SEEN_NAME)
      tname = (tag, position(io))
    elseif k == b"params"
      see(SEEN_PARAMS)
      tparams = (tag, position(io))
    elseif k == b"path"
      see(SEEN_PATH)
      tpath = (tag, position(io))
    elseif k == b"size"
      see(SEEN_SIZE)
      tsize = (tag, position(io))
    elseif k == b"var"
      see(SEEN_VAR)
      tvar = (tag, position(io))
    elseif k == b"body"
      see(SEEN_BODY)
      tbody = (tag, position(io))
    elseif k == b"_backrefs"
      nothing
    else
      see(SEEN_OTHER)
      break
    end

    skip_over(io, tag)
  end

  ret = if only_saw(SEEN_TAG | SEEN_REF | SEEN_TAG_BACKREF)
    @info "Found backref" tref
    (:backref, tref)
  elseif only_saw(SEEN_TAG | SEEN_TYPE | SEEN_DATA | SEEN_TAG_STRUCT)
    @info "Found Struct" ttype tdata
    (:struct, ttype, tdata)
  elseif only_saw(SEEN_TAG | SEEN_NAME | SEEN_PARAMS | SEEN_TAG_DATATYPE)
    @info "Found Type" tname tparams
    (:type, tname, tparams)
  elseif only_saw(SEEN_TAG | SEEN_NAME | SEEN_TAG_SYMBOL)
    @info "Found Symbol" tname
    parse_symbol(io, tname[2], ctx)
  elseif only_saw(SEEN_TAG | SEEN_DATA | SEEN_TAG_TUPLE)
    @info "Found Tuple" tdata
    parse_tuple(io, tdata[2], ctx)
  elseif only_saw(SEEN_TAG | SEEN_DATA | SEEN_TAG_SVEC)
    @info "Found svec" tdata
    parse_svec(io, tdata[2], ctx)
  elseif only_saw(SEEN_TAG | SEEN_TAG_UNION)
    Union{}
  elseif only_saw(SEEN_TAG | SEEN_TYPENAME | SEEN_PARAMS | SEEN_TAG_ANON)
    (:anonymous, ttypename, tparams)
  elseif only_saw(SEEN_TAG | SEEN_PATH | SEEN_TAG_REF)
    (:ref, tpath)
  elseif only_saw(SEEN_TAG | SEEN_TYPE | SEEN_SIZE | SEEN_DATA | SEEN_TAG_ARRAY)
    (:array, ttype, tsize, tdata)
  elseif only_saw(SEEN_TAG | SEEN_VAR | SEEN_BODY | SEEN_TAG_UNIONALL)
    (:unionall, tvar, tbody)
  else
    # This doc doesn't appear to have any Julia type information
    @info "Found plain dictionary"
    seek(io, start)
    parse_any_doc(io, ctx)
  end
end

function directtrip(ting::T) where {T}
  io = IOBuffer()
  bson(io, Dict(:stuff => ting))
  seek(io, 0)
  parse_doc(io, ParseCtx())[:stuff]
end
