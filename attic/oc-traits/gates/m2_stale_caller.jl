# Gate M2 item 7 (§7, H4): a caller compiled BEFORE the membership at a
# concrete S — after @implement the declaration-time walk must lower that CI's
# max_world (the stat counters move), the new-world call hits the set method,
# the pinned old-world call hits the old method. Both values correct.
using Traits
include("util.jl")

stat(w) = ccall(:jl_membership_stat, Csize_t, (Cint,), w)

@trait ST
struct SSt end
s(::ST) = :set
s(::Any) = 0
caller(x::SSt) = s(x)             # compiled NOW, pre-membership

r0 = caller(SSt())
@assert r0 === 0 "pre-membership value"
w_pre = curworld()
ci0 = [c for c in all_cis(caller) if c.min_world <= w_pre <= c.max_world]
@assert length(ci0) >= 1 "a live pre-membership CI exists"
@assert all(c -> c.max_world == typemax(UInt), ci0) "not bounded yet (fresh CIs carry the UInt64 ceiling)"

before = (stat(1), stat(2), stat(4), stat(5))
@implement SSt ST
after = (stat(1), stat(2), stat(4), stat(5))
println("m2_stale_caller stats (replays, visits, spec-invalidations, cache-lowerings): ",
        before, " -> ", after)
@assert after[2] > before[2] "the walk visited the caller's method"
@assert after[3] > before[3] || after[4] > before[4] "the compiled decision was lowered"

r1 = caller(SSt())
@assert r1 === :set "new-world call through the stale caller"
r2 = Base.invoke_in_world(w_pre, caller, SSt())
@assert r2 === 0 "old-world call keeps the old answer"

@assert any(c -> c.max_world < typemax(Int) && c.rettype === Int, all_cis(caller)) "the old CI shows the lowering"
@assert !(SSt isa ST && Int isa ST) "sanity (I1)"

println("m2_stale_caller: OK")
