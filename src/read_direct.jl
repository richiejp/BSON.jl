struct ParseCtx
  refindx::Vector{Pair{BSONType, Int}}
  refs::Vector{Any}
end

ParseCtx() = ParseCtx([], [])

function skip_over(io::IO, tag::BSONType)
  len = if tag == document || tag == array || tag == string | tag == binary
    read(io, Int32) - 4
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
        skip_over(io, tag)
      end
    else
      @info "Skipping $(String(name))"
      skip_over(io, tag)
    end
  end

  seek(io, 0)
end

function parse_doc(io::IO, ctx::ParseCtx)
end
