# AC-9 (old G1.32): an assertion ONE FRAME ABOVE a run-time site does not fold
# over it — `h9b` asserts :foldable and calls `h9`, which holds the run-time
# site; the nortsite mark rides through the call, so the marked caller does not
# fold `h9b(1)` and follows `g9`'s redefinition as plain code does.
include("ac_util.jl")

g9(x) = 1
h9(x::Int) = g9(Base.inferencebarrier(x))
Base.@assume_effects :foldable h9b(x::Int) = h9(x)
k9() = h9b(1)
k9p() = h9b(1)
mark!(k9)

u0 = (k9p(), k9())
g9(x) = 2
u1 = (k9p(), k9())
@assert u0 == (1, 1) "before: $u0"
@assert u1 == (2, 2) "G1.32: the assertion above the site does not fold over it: $u1"

ac_finish(@__FILE__)
