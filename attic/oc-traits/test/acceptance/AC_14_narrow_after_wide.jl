# AC-14 (old G1.34): a narrow instance reached after a wider one runs with its
# OWN static parameters — in marked code. The old case pinned the facts-owner
# cache key (P1's second owner — deliberately not ported); the regression here
# is that both specializations of the marked caller answer correctly, each with
# its own sparams, and keep separate CIs.
include("ac_util.jl")

v14(::Type{T}) where {T} = T
m14(x) = v14(x)
p14(x) = v14(x)
mark!(m14)

a = m14(Type{Type{Type{Int32}}})          # the wide one first
@assert a === Type{Type{Type{Int32}}} "wide instance: $a"
b = m14(Type{Type{Int32}})                # then a narrower one
@assert b === Type{Type{Int32}} "G1.34: the narrow instance keeps its own sparams: $b"
@assert m14(Int) === Int === p14(Int)
@assert length([c for c in all_cis(m14) if c.min_world > 0]) >= 2 "two specializations cached"

ac_finish(@__FILE__)
