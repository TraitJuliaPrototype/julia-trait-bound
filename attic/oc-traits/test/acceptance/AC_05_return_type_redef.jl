# AC-5 (old G1.9): `return_type` follows a redefinition — when plain Julia's
# return type moves, the marked code's answer moves with it (eltype of an empty
# map is inference's `return_type` of the closure; the closure reads a binding).
include("ac_util.jl")

k5(x) = 1
km5(c::Int) = map(x -> k5(x), Int[])        # empty: the element type is return_type's
kmp(c::Int) = map(x -> k5(x), Int[])
mark!(km5)

@assert eltype(km5(1)) == Int "before: Int"
k5(x) = 1.5
r1 = eltype(km5(1))
p9 = eltype(kmp(1))
@assert r1 == p9 == Float64 "G1.9: the marked answer moved with plain's: $r1 vs $p9"

ac_finish(@__FILE__)
