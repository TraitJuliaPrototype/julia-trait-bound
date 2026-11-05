# Gate M2 item 1 (transitive set-in-set answers, probe 4 flipped): a late member
# of B reaches A when B is itself a member of A — through subtype, isa,
# Type{Late}, and dispatch at f(::A), in the declaring world and pinned old ones.
# Cycle refusal is datatype.c's, exercised through the library surface.
using Traits
include("util.jl")

@trait A2                                 # A2 open
@trait B2 <: A2                           # B2 open, and a member of A2 (entry)
struct Late2 end                          # unrelated by any declaration chain
w_pre = curworld()
@implement Late2 B2                       # late: Late2 joins B2

# isa / Type{Late2}: both questions must compose the chain (there is no <: link,
# so `Late2 <: A2` itself must stay FALSE — membership is not subtype)
@assert (Late2() isa A2) "member of B2 answers the set A2 transitively"
@assert (Late2 isa A2) "Type{Late2}: the induced membership composes too (§2.8)"
@assert (B2 isa A2) "the direct set-in-set link answers (type-object side, induced rule)"
@assert !(Late2 <: A2) "membership composition is not subtype (I1 exactness)"
@assert !(Late2() isa Union{String, Int}) "no widening while we're here (I1)"

# dispatch at f(::A): a set method on A2 picks up the transitive member
g2(::A2) = :a
g2(::Int) = :int
@assert (g2(Late2()) === :a) "dispatch through the composed chain"
@assert (g2(1) === :int) "unrelated queries keep their answer (I1)"

# worlds: before the @implement statement, nothing composed (entry min_world
# is w_pre+1 per m1_worlds_minworld; pass the function, never a too-new lambda)
@assert !Base.invoke_in_world(w_pre, Base.isa, Late2(), A2) "old world: no transitive answer"
@assert Base.invoke_in_world(curworld(), Base.isa, Late2(), A2) "current world: transitive answer"

# the entry-middle shape (probe 6): B5 joins A5 by @implement, no <: link either
@trait A5
@trait B5
@implement B5 A5
struct Late5 end
@implement Late5 B5
@assert (Late5() isa A5) "entry-based middle link composes too"

# the transitive parametric shape: B3{T} ∈ A3{T}, member S3{T} ∈ B3{T}
@trait A3{T}
@trait B3{T} <: A3{T}
struct S3{T} end
@implement S3{T} B3{T}
@assert (S3{Int}() isa A3{Int}) "parametric chain composes narrow"
@assert !(S3{Int}() isa A3{String}) "…and stays narrow (no family leak)"
@assert (S3{Int}() isa A3) "bare-family query answers the whole-family chain"

# cycle refusal through the public surface: C4 ∈ D4 and D4 ∈ C4 cannot both live
@trait C4
@trait D4 <: C4
let err = false
    try
        Traits.declare_membership(C4, D4, nothing, @__MODULE__, nothing)
    catch e
        err = true
        e isa ErrorException || rethrow()
    end
    @assert err "a set-in-set cycle must be refused at declaration"
end
@assert !(Int isa A2) "still no unrelated memberships (I1)"

println("m2_set_in_set: OK")
