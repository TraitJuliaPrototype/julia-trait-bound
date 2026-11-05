# AC-4 (old G1.8): `return_type` at an abstract-typed query inside marked code
# answers plain's (the A3 carve-out, §7 steps 1+3): the empty map over an
# abstractly typed array gets the SAME result type as plainly compiled code —
# the facts gate must not widen the eltype to Any.
include("ac_util.jl")

ones4(c::Int) = map(x -> 1, Integer[])      # an empty map over an abstract element type
plain4(c::Int) = map(x -> 1, Integer[])
mark!(ones4)

e4 = ones4(3)
p4 = plain4(3)
@assert typeof(e4) === typeof(p4) === Vector{Int} "G1.8: empty map's eltype stays Int: $(typeof(e4)) vs $(typeof(p4))"
@assert e4 == p4

# and the same at a marked frame with a value (non-empty, same return_type path)
tw4(c::Int) = map(x -> Int64(x), Integer[])
@assert typeof(tw4(1)) === typeof(map(x -> Int64(x), Integer[]))

ac_finish(@__FILE__)
