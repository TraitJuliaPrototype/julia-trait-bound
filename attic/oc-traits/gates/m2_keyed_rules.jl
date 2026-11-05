# Gate M2 item 3 (Keyed y-side key match) — type-level pins only, no values
# (plan gates table): an erased query matches erased members exactly; a
# non-erased Keyed never matches in M2; Dynamic erasure stays; the Compiler's
# could_join refuses negative folds at a Keyed y so a pre-declaration compile
# cannot freeze `false` while erased entries arrive.
using Traits
include("util.jl")

@trait X9
struct K9 end
g9(v) = v isa Core.Keyed{X9, Nothing, Nothing}      # compiled NOW, pre-declaration
r9 = g9(K9())                                        # force a specialization
@assert r9 === false "not a member yet (exact)"

@implement K9 X9                                     # the erased key (nothing)

@assert (K9 isa Core.Keyed{X9, Nothing, Nothing}) "erased member answers the erased query"
@assert !(K9 isa Core.Keyed{X9, Int, Nothing}) "non-erased Keyed never matches in M2 (§3 conservative false)"
@assert !(K9 isa Core.Keyed{X9, Nothing, String}) "…on either key component"
@assert (Core.Dynamic{X9}(K9()) isa X9) "Dynamic erasure unchanged (§2 pin here for the arm's reuse)"
@assert !(K9 isa Core.Keyed{Union{}, Nothing, Nothing}) "a wrong set name never matches"

# could_join: the pre-declaration specialization must not be a frozen false —
# the same compiled call answers true now (the fold was refused, the runtime
# check consults the entry). If the negative had folded Const(false), this line
# would keep returning false.
@assert (g9(K9()) === true) "negative fold refused at a Keyed y (could_join wrapper arm)"

println("m2_keyed_rules: OK")
