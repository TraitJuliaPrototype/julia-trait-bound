# Gate M2 item 6 (§6, named gate): a late membership flips dispatch AT THE MEMBER
# in the new world while the OLD world keeps the pre-membership answer — through
# the same hot call site (the leaf dispatch-cache entry is bounded, not clobbered:
# call at the member, then the same call in the old world → old method).
using Traits
include("util.jl")

@trait DW
struct MDW end
d(::DW) = :set
d(::Any) = 0
dc(x::MDW) = d(x)                 # one hot call site

w_pre = curworld()
r0 = dc(MDW())
@assert r0 === 0 "pre-membership: the Any method answers (Int)"

@implement MDW DW

r1 = d(MDW())
@assert r1 === :set "new world: the set method answers"
r2 = Base.invoke_in_world(w_pre, d, MDW())
@assert r2 === 0 "old world, same call: the old method still answers (§6 bounds)"
r3 = dc(MDW())                    # the compiled call site after the flip
@assert r3 === :set "the hot site recompiles through the entry"
r4 = Base.invoke_in_world(w_pre, dc, MDW())
@assert r4 === 0 "and the old-world call through it is bounded (leaf entry bump)"

# the compiled ranges themselves: some live CI answers :set now, and the old CI
# was bounded below the declaring world rather than deleted
cis = all_cis(d)
@assert any(c -> c.rettype === Symbol && c.min_world <= curworld() <= c.max_world, cis) "a live CI answers Symbol"
@assert any(c -> c.rettype === Int && c.max_world < typemax(Int), cis) "the pre-membership Int CI was lowered (§7's cache walk)"

@assert !(Int isa DW) "no unrelated widening (I1)"
println("m2_dispatch_worlds: OK")
