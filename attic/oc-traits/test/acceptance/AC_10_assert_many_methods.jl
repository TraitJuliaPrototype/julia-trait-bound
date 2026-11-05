# AC-10 (old G1.33): an assertion over a call with MORE MATCHING METHODS THAN
# MAX_METHODS records no edge (plain records none there either), so it is a
# run-time site as well: in marked code the assertion does not apply, and the
# value follows the redefinition. Plain's value is SHOWN, not checked (old
# suite's precedent: the lying assertion is programmer error in plain — facts
# simply refuses to exploit it).
include("ac_util.jl")

gm() = 0
gm(a::Int) = 1
gm(a::Int, b::Int) = 2
gm(a::Int, b::Int, c::Int) = 3
gm(a::Int, b::Int, c::Int, d::Int) = 4
Base.@assume_effects :foldable hm(n::Int) = gm((Base.inferencebarrier((1, 1))::Tuple{Vararg{Int}})...)
k10() = hm(1)
k10p() = hm(1)
mark!(k10)

m0p, m0 = k10p(), k10()
gm(a::Int, b::Int) = 20
m1p, m1 = k10p(), k10()
println("OBSERVED plain: $m0p -> $m1p (shown, not checked)")
@assert m0 == 2 && m1 == 20 "G1.33: the marked value follows the redefinition: $m0 -> $m1"

ac_finish(@__FILE__)
