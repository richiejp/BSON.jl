# BSONqs

This is a fork of [BSON.jl](https://github.com/MikeInnes/BSON.jl), with much
better performance for loading composite data types in particular. The 'qs'
stands for "quick structs".

BSONqs appears to be between 2-4x faster than BSON in read
[benchmarks](https://github.com/richiejp/serbench). See the performance
section below for more info.

## Usage

Usage is mostly the same as the original package. You should be able to use
this as a drop in replacement, except that you may need to alias the package
name.

```julia
using BSONqs

const BSON = BSONqs
```

Currently the `load` function does not support some of the more exotic data
types, however you may use `load_compat` instead. There are also now two forms
of the `parse` function.

```julia
parse(x::Union{IO, String})
parse(x::Union{IO, String}, ctx::ParseCtx; mmap=false)
```

The later provides the best performance in most circumstances and is the least
compatible. It should be noted that `load(x; args...) = parse(x, ParseCtx();
args...)`, but that `parse(x)` is not the same as `load_compat(x)`.

On Linux atleast you can set `mmap=true` for better perfomance when loading
from a file.

## Performance hints

This library works best with large, repetitive datasets with concrete
types. You should always try to use concrete types in structs in Julia (see
the official docs).

This library makes heavy use of `@generated` and type specific functions, so
the compilation time is longer than the original. This means that (in theory)
for smaller or highly irregular datasets, the original library may be faster
for the first call to `load` where the dataset is small and contains one or
more uncached data types.

Also for generic BSON documents, without any Julia type data, this library may
or may not be faster.

If your platform supports it, use `mmap`. It is generally faster anyway, but
in this case it also allows us to avoid unecessary copies and
allocations. Below is a comparison of the original library and BSONqs with and
without mmap on a common dataset (on the second pass).

```julia
julia> @time BSON.load("vgg19.bson");
  0.626661 seconds (1.97 k allocations: 1.071 GiB, 33.95% gc time)

julia> @time BSONqs.load("vgg19.bson");
  0.482821 seconds (1.82 k allocations: 1.071 GiB, 42.69% gc time)

julia> @time BSONqs.load("vgg19.bson"; mmap=true);
  0.237986 seconds (1.82 k allocations: 548.121 MiB, 26.12% gc time)
```

In any case, if performance is important to you, you should create a benchmark
with your data. Finally note that this library mainly uses the same
serialization code as the original, so write performance should be the same
(although at the time of writing the original has a bug which makes it much
worse). If you are interested in write performance then please let me know.
