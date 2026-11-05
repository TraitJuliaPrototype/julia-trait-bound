# Gate §0 (query-world override — the reviewer's BLOCKER): inference runs C
# subtyping under the FROZEN jl_typeinf_world, which sits below every runtime
# entry's min_world. Without the override, a caller compiled AFTER @implement
# cannot see the set method at all: code_typed answers pre-membership. Both
# shapes pinned: explicit code_typed, and normal call then read-CI.
using Traits
include("util.jl")

@trait P9
struct PM9 end

f9(::P9) = :set
f9(::Any) = 0
g9(x) = f9(x)

@implement PM9 P9

# shape 1: explicit code_typed at the member type — inference must resolve the
# call THROUGH the membership (f9(::P9) wins → Symbol), not fall to the Any
# method (Int) or Bottom
tt = code_typed(g9, (PM9,); world = curworld())
@assert length(tt) == 1 "one specialization"
ci = first(tt)                          # Pair{CodeInfo, DataType} in this version
@assert ci.second === Symbol "inference sees the set method (frozen typeinf world must not shadow entries)"
# (if inference missed the membership it would answer via the Any method, rettype Int)

# shape 2: normal call, then read the CodeInstance the dispatch used
r = g9(PM9())
@assert r === :set "the compiled-then-called path selects the set method"
cis = [c for c in all_cis(g9) if c.min_world <= curworld() <= c.max_world]
@assert any(c -> c.rettype === Symbol, cis) "a live CI answers :set at the member"

# world anchoring: the compiled decision must not be pinned to pre-membership
# worlds — the fresh CI's min_world is past image world 1
let c = only([c for c in all_cis(g9) if c.rettype === Symbol &&
              c.min_world <= curworld() <= c.max_world])
    @assert c.min_world > 1 "fresh CI, not an old pre-membership one"
end

# negative control (I1): a non-member still infers the Any method
@assert code_typed(g9, (Int,); world = curworld())[1].second === Int "unrelated queries keep vanilla inference"
@assert g9(3) === 0

println("m2_post_declare_infer: OK")
