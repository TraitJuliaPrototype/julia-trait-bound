# Gate M2 (review W1-F1, the BLOCKER): §6's world bounding must cover EVERY
# signature shape a membership match can pass through — Vararg-vs-fixed positions,
# varargs consumed by longer queries, and union sig positions — not just the
# fixed-arity non-union case. A pre-declare world calling THROUGH a cache primed
# post-declare must keep the old answer (I5).
using Traits
include("util.jl")

# (A) vararg set method, member primed post-declare
@trait S6
struct Mem6 end
g6(::S6...) = :set
g6(::Any)   = :any
w6 = curworld()
@implement Mem6 S6
@assert g6(Mem6()) === :set "new world, 1-arg through vararg sig"
@assert Base.invoke_in_world(w6, g6, Mem6()) === :any "old world, 1-arg (W1 probe A1)"
@assert g6(Mem6(), Mem6()) === :set "new world, 2-arg length-mismatch shape"
# (coordinator re-adjudication after fix round: the old world has NO 2-arg match
# at all pre-declare — the bounding contract is that the :set answer cannot
# appear there, which a MethodError satisfies exactly; vanilla throws likewise)
let r = try
    Base.invoke_in_world(w6, g6, Mem6(), Mem6())
catch e
    e
end
    @assert r isa MethodError "old world cannot match the 2-arg call — :set is invisible there (W1 probe A2 bounding)"
end

# (B) union sig position Union{Other, Set}
@trait S7
struct Mem7 end
struct Oth7 end
u7(::Union{Oth7, S7}) = :set
u7(::Any)             = :any
w7 = curworld()
@implement Mem7 S7
@assert u7(Mem7()) === :set "new world through the union arm"
@assert Base.invoke_in_world(w7, u7, Mem7()) === :any "old world keeps the catch-all (W1 probe B1)"
@assert u7(Oth7()) === :set "the closed union arm still answers"

# (D) composed (through-chain) control must stay bounded too
@trait S9c
@trait M9c <: S9c
struct Late9c end
f9c(::S9c) = :set
f9c(::Any) = :any
w9 = curworld()
@implement Late9c M9c
@assert f9c(Late9c()) === :set "composed chain dispatch in the new world"
@assert Base.invoke_in_world(w9, f9c, Late9c()) === :any "composed chain bounded in the old world"

# (E) the W2-F1 class: §7 must SEE a method whose only open-set occurrence is
# under Vararg — a caller compiled pre-declare through it must pick the set
# method in the NEW world (§7 replay), not persist the stale answer.
@trait VD2
struct MD2 end
vd(::VD2...) = :set
vd(::Any)    = :any
caller2(x::MD2) = vd(x)          # compiled through the catch-all, pre-declare
@assert caller2(MD2()) === :any "pre-declare value"
w2 = curworld()
@implement MD2 VD2
@assert caller2(MD2()) === :set "new world through the vararg method (replay reaches it)"
@assert Base.invoke_in_world(w2, caller2, MD2()) === :any "old world still bounded"

println("m2_vararg_union_worlds: OK")
