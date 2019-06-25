# BSONqs

This is a fork of [BSON.jl](https://github.com/MikeInnes/BSON.jl), with much
better performance for loading composite data types in particular. The 'qs'
stands for "quick structs".

BSONqs appears to be between 2-4x faster than BSON in read
[benchmarks](https://github.com/richiejp/serbench).

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
parse(x::Union{IO, String}, ctx::ParseCtx)
```

The later provides the best performance in most circumstances and is the least
compatible. It should be noted that `load(x) = parse(x, ParseCtx())`, but that
`parse(x)` is not the same as `load_compat(x)`.
