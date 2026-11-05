# Gate M3 G2-count (plan §5.M3's second clause; D9 bands, R-0/R-15): a scripted
# trait session compiled under `all` should be ≥99 % G2-clean, and a CHURN of
# pure definitions (non-stakeholders) must lose ZERO of its G2-bit CIs — the
# property the old g2all rows measured (E-28: 0 of 12,368; E-29: 0 of 15,030
# product; `all`-row: 12 of 68,162, all stakeholder `Base._cat`). Stakeholder
# redefinitions may lose; those are reported with attribution.
if get(ENV, "JULIA_FACTS", "0") != "1"      # the count is only meaningful under `all`
    julia = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) $(Base.expanduser(@__FILE__))`
    rc = success(addenv(julia, ["JULIA_FACTS" => "1"]))
    exit(rc ? 0 : 1)
end

using LinearAlgebra, InteractiveUtils
using Traits
import Compiler

include("util.jl")
const G2BIT = 0b00010000

# ---------------- work A: a scripted trait session ----------------
@trait Col3c
struct Mem3c end
@implement Mem3c Col3c
w3a(m::Mem3c) = "member"
wdet(x::Matrix{Float64}) = det(x)
wmap(a::Vector{Int}) = map(x -> x + 1, a)
wbcs(a::Vector{Int}) = a .* 2
wsort(a::Vector{Int}) = sort(a)
wwork(m::Mem3c, a::Vector{Int}) = (w3a(m), wdet([1.0 0.5; 0.5 1.0]), wmap(a), wbcs(a), wsort([3, 1, 2]))

for m in (wwork,)            # single warmup driver + the singles below
    m(Mem3c(), [1, 2, 3])
end
w3a(Mem3c()); wdet([1.0 0.5; 0.5 1.0]); wmap([1, 2]); wbcs([1, 2]); wsort([3, 1, 2])

const SCOPE = Any[w3a, wdet, wmap, wbcs, wsort, wwork]

function snapshot_g2()
    out = Tuple{Any, Core.CodeInstance}[]     # (fn, ci) of live G2-bit CIs
    total = 0; g2 = 0
    for f in SCOPE
        for c in all_cis(f)
            total += 1
            if getfield(c, :flags) & G2BIT != 0
                g2 += 1
                push!(out, (f, c))
            end
        end
    end
    return total, g2, out
end

total, g2, g2set = snapshot_g2()
share = total == 0 ? 0.0 : g2 / total
println("G2COUNTS phaseA total=$total g2=$g2 share=$(round(share, digits=4))")
@assert total >= 20 "work A must produce a meaningful CI population (got $total)"
@assert share >= 0.99 "G2-bit share below the 99 % band: $g2 / $total"

lost_after(p::Symbol, before) = begin
    lost = Any[]
    for (f, c) in before
        if c.max_world != typemax(UInt)
            push!(lost, (typeof(f).name.mt.name, c.max_world))
        end
    end
    return lost
end

# ---------------- churn phase 1: NON-stakeholders (pure additions) ----------
# 100 types + their own functions + new methods of Base functions work A never
# calls — the shape of "a load that brings neither" (G2's phrase).
mod = Module(Main, :ChurnA1)
eval(mod, quote
    using LinearAlgebra
end)
for n in 1:100
    Tn = Symbol("CT", n)
    fn = Symbol("cf", n)
    eval(mod, :(struct $(Tn) end))
    eval(mod, :($(fn)(x) = x + $n))
end
eval(mod, quote
    Base.trunc(x::CT1) = 0
    Base.rmul(x::CT2, y) = 1
    Base.first(x::CT3) = 2
end)
for n in 1:10                # force some churn-code compilation too
    fn = Symbol("cf", n)
    Core.eval(mod, :($fn(1)))
end
lost1 = lost_after(:phase1, g2set)
println("G2COUNTS phase1 nonstakeholder_lost=$(length(lost1))")
@assert isempty(lost1) "NON-stakeholder definitions lost G2 CIs: $lost1"

# ---------------- churn phase 2: stakeholders (redefinitions) ---------------
# allowed to lose — reported with attribution (the old G2_DIAG's role).
before2 = snapshot_g2()[3]
wmap(a::Vector{Int}) = map(x -> x + 2, a)           # redefined: a stakeholder change
w3a(m::Mem3c) = "member2"
r2 = wwork(Mem3c(), [1, 2, 3])
@assert r2[1] == "member2" && r2[3] == [3, 4, 5] "stakeholder redefinition is followed"
lost2 = lost_after(:phase2, before2)
println("G2COUNTS phase2 stakeholder_lost=$(length(lost2)) names=$(unique(first.(lost2)))")

println("m3_g2_counts: OK   (rows into numbers.md)")
