# Gate M3 §2 (+ R-14's cycle case, A-F16): the `nortsite` effect bit — inverted
# encoding at bit 15 (zeroed words read "no run-time site"), round-trips,
# propagates IPO through marked chains, plain frames never clear it, and a cycle
# re-narrows the stored word at cycle finish.
include("util.jl")
import Compiler

# (A) encoding round-trip, both values, and the inverted zero word
@assert Compiler.decode_effects(UInt32(0)).nortsite "a zeroed word reads nortsite=true (inverted)"
for want in (true, false)
    e = Compiler.Effects(; nortsite=want)
    rt = Compiler.decode_effects(Compiler.encode_effects(e))
    @assert rt.nortsite == want "nortsite=$want round-trips through bit 15"
end

# (B) IPO propagation through a marked chain: the rtsite at the root's reach
# makes every frame above it nortsite-false
sink_any(a) = a
rts_deep(x::Vector{Any}) = sink_any(x[1])
mid_deep(x::Vector{Any}) = rts_deep(x)
top_deep(x::Vector{Any}) = mid_deep(x)
for f in (rts_deep, mid_deep, top_deep)
    Compiler.mark_facts!(f)
    f(Any[1])
end
for f in (top_deep, mid_deep)
    ci = only(all_cis(f))
    @assert !Compiler.decode_effects(ci.ipo_purity_bits).nortsite "nortsite propagates to $(typeof(f).name.mt.name)"
end

# (C) a plain (unmarked) frame never clears nortsite — I3
plain_deep(x::Vector{Any}) = sink_any(x[1])
plain_deep(Any[1])
@assert Compiler.decode_effects(only(all_cis(plain_deep)).ipo_purity_bits).nortsite "plain frames keep nortsite"

# (D) the cycle case (R-14/A-F16): marked mutually recursive pair whose one
# frame holds a run-time site; after the cycle FINISHES (finish_cycle re-narrows
# the stored words), both CIs must read nortsite=false.
ev_c(x::Any, d::Int) = iszero(d) ? true : od_c(x, d - 1)
od_c(x::Any, d::Int) = iszero(d) ? true : ev_c(x, d - 1)
Compiler.mark_facts!(ev_c)
Compiler.mark_facts!(od_c)
@assert ev_c("s", 2) == true && od_c("s", 3) == true
for f in (ev_c, od_c)
    cis = all_cis(f)
    @assert all(c -> !Compiler.decode_effects(c.ipo_purity_bits).nortsite, cis)
        "cycle-finish re-narrows $(typeof(f).name.mt.name): every stored CI reads nortsite-false"
end

println("m3_rtsite_effects: OK")
