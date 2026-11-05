# Gate M2 item 4 (typemap placement, probe 2 flipped): a method whose signature
# names an open set lives in the level's `linear` array, never under name1 by
# the set's name — so a member (whose chain does NOT contain the set) reaches it
# in a POPULATED table. Then the lookup-cost shape: ~200-method function with a
# bounded method present, member lookups within 2x of the no-set control.
using Traits
include("util.jl")

@trait SetL
struct MemL end
struct BigL end

# populate: 30 unrelated typed methods + a catch-all, THEN the set method
for i in 1:30
    sym = Symbol("Pad", i)
    @eval struct $sym end
    T = Core.eval(@__MODULE__, sym)      # the definition evaluates to nothing here
    @eval w(x::$T) = :pad
end
w(x::BigL) = :big
w(x) = :any                       # catch-all (the trap of probe 2)
w(x::SetL) = :set
@implement MemL SetL

@assert (w(MemL()) === :set) "member reaches the set method in the populated table (probe 2)"
@assert (w(BigL()) === :big) "chain-matched query unaffected"
@assert (w("s") === :any) "catch-all still serves unrelated values (I1)"

# the lookup-cost shape (E-253-ish): a wide table where the MEMBER side needs
# the linear+bounded placement (open set, no chain) and the control side is a
# plain chain lookup through the same 200-method table (closed supertype —
# vanilla name1 placement, no membership involved). Same call loop both sides.
@trait WideS
struct WideMem end                # unrelated; joins WideS via @implement
abstract type ClosedW end
struct ChainMem <: ClosedW end    # control: reaches its method by plain subtype chain
v(x) = :base
for i in 1:200
    sym = Symbol("WPad", i)
    @eval struct $sym end
    T = Core.eval(@__MODULE__, sym)
    @eval v(x::$T) = :pad
    @eval v2(x::$T) = :pad
end
v(x::WideS) = :set
v2(x::ClosedW) = :set2
@implement WideMem WideS

using Printf
probe(m) = Base.inferencebarrier(v)(m)      # keep the dispatch loop real (no const-fold)
probe2(m) = Base.inferencebarrier(v2)(m)
probe(WideMem()); probe2(ChainMem())        # warm both specializations
let reps = 5, n = 20_000
    t_mem = typemax(Float64); t_ctl = typemax(Float64)
    for _ in 1:reps
        t_mem = min(t_mem, @elapsed begin for _ in 1:n; probe(WideMem()); end end)
        t_ctl = min(t_ctl, @elapsed begin for _ in 1:n; probe2(ChainMem()); end end)
    end
    @printf("m2_typemap_linear: member %.3f s vs chain-control %.3f s (ratio %.2f)\n",
            t_mem, t_ctl, t_mem / t_ctl)
    @assert t_mem < 2.0 * t_ctl "member lookup within 2x of the chain control"
end

println("m2_typemap_linear: OK")
