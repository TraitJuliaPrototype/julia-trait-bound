# AC-7 (old G1.10): compile-time evaluation of a callee with ASSERTED effects
# over a run-time site follows a redefinition — `nortsite` withdraws the
# assertion in frames that reach an unrecorded dispatch (the §2 readers), and in
# plain-run the value moves through the recorded edge chain. Either way the
# policy value equals plain's before AND after the redefinition.
include("ac_util.jl")

g7(x) = 1
Base.@assume_effects :foldable h7(x::Int) = g7(Base.inferencebarrier(x))
k7() = h7(1)
k7p() = h7(1)
mark!(k7)

f0 = (k7p(), k7())                       # plain, policy
g7(x) = 2
f1 = (k7p(), k7())
@assert f0 == (1, 1) "before: (plain, policy) = $f0"
@assert f1 == (2, 2) "G1.10: the fold over a run-time site follows the redefinition: $f1"

ac_finish(@__FILE__)
