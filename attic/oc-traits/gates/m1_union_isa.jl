# Gate for review finding M3: the type VALUE S answers `isa U` when some arm of
# the union U contains the set (L10's Type{S} rule must descend union arms —
# otherwise isa disagrees with dispatch, review p16 G2/G8).
using Traits
include("util.jl")

@trait Z9
struct Mem9 end
@implement Mem9 Z9

@assert (Mem9 isa Z9) "bare set (baseline)"
@assert (Mem9 isa Union{Z9, Int}) "type value answers through a union containing the set"
@assert !(Mem9 isa Union{String, Int}) "unrelated union stays false (exact)"

h(::Union{Z9, Int}) = :hit
h(::Any) = :miss
@assert h(Mem9) === :hit "dispatch matches the arm"
@assert (Mem9() isa Union{Z9, Float64}) "value isa through the union arm too"

println("m1_union_isa: OK")
