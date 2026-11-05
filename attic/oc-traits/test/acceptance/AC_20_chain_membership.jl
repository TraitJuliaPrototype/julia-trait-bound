# AC-20 (R-14, B-F8; §8 + W2-1 ruling): the COMPOSED-CHAIN membership edge —
# S20 ∈ Z20 and Z20 ∈ X20; a marked caller at S20 calling a method written at
# X20 resolves through the chain, and the emitted MembershipEdge carries the
# TOP-OF-CHAIN entry (the one naming X20, per W2-1 — consumers read its world
# fields). The composed query holds at the top entry's world and fails below
# it, so the edge's bound is the right bound. `jl_membership_entry_for`
# (plan §8, XX-registered) answers the same entry.
include("ac_util.jl")
using Traits

@trait X20
@trait Z20
struct S20 end
ez20 = @implement S20 Z20             # S -> Z
ex20 = @implement Z20 X20             # Z -> X  (declared later: the chain's top)
hh20(::X20) = :via
mc20(s::S20) = hh20(s)
mark!(mc20)

@assert mc20(S20()) === :via "the chain answers"

ci = only([c for c in all_cis(mc20) if c.min_world > 0])
fes = [e for e in ci.edges if isa(e, Compiler.MembershipEdge)]
@assert length(fes) == 1 "exactly one MembershipEdge: $(collect(ci.edges))"
edg = only(fes)
@assert edg.entry === ex20 "the edge carries the TOP-OF-CHAIN entry (W2-1): got $(edg.entry)"
@assert edg.entry.set === X20 && edg.entry.member === Z20 "the top entry names (Z20, X20)"
@assert ci.min_world >= ex20.min_world "bound: CI $(ci.min_world) >= top entry $(ex20.min_world)"

haspair = any(1:length(ci.edges)-1) do i
    s = ci.edges[i]
    s isa DataType && s === Tuple{typeof(hh20), S20} &&
        (ci.edges[i+1] isa Core.MethodInstance || ci.edges[i+1] isa Core.CodeInstance)
end
@assert haspair "dispatch pair at the concrete member sig: $(collect(ci.edges))"

# the composed query world-semantics: holds at the top entry's min_world, fails below
@assert Base.invoke_in_world(ex20.min_world, s -> s isa X20, S20()) === true "chain holds at its top's min_world"
@assert Base.invoke_in_world(ex20.min_world - 1, s -> s isa X20, S20()) === false "below it, no chain"

# the §8 recheck function, same answer (XX-registered per plan §8)
ent = ccall(:jl_membership_entry_for, Any, (Any, Any, Csize_t), S20(), X20, curworld())
@assert ent === ex20 "jl_membership_entry_for answers the top entry: got $ent"
ent_below = ccall(:jl_membership_entry_for, Any, (Any, Any, Csize_t), S20(), X20, ex20.min_world - 1)
@assert ent_below === nothing "below the top entry's world: nothing"

ac_finish(@__FILE__)
