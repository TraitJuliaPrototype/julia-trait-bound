# Gate for review finding B2: types interned BEFORE a set opens must not carry
# a stale has_open_set=false memo — a runtime query through the pre-interned
# type would then answer 0 even after the membership arrives (reviewer
# p10/p11 repro, distilled; epoch design: workflow/notes 2026-10-30).
# n.b. the COMPILED-fold variant of this scenario is a NAMED later gap: a
# function compiled while the set was closed may keep its folded answer until
# declaration-time invalidation lands (M2 §8 machinery; the dispatch-layer
# sibling is the M6 item from the D7 ruling). The library path (@trait opens at
# declaration, every dependent code compiles after) cannot reach that gap; the
# runtime contract below is what M1b must guarantee.
using Traits
include("util.jl")

abstract type Xs end                 # a plain abstract type, not open yet
const TI = Tuple{Xs, Int}            # its has_open_set memo is computed NOW (false)

struct LateS end                     # unrelated to Xs (no chain relation)
struct NotM end

g = (LateS(), 1)
h = (NotM(), 1)
@assert !(g isa TI) "not a member yet"

@trait Xs                            # opens a set that types were built against
@implement LateS Xs

# fresh runtime queries must see the membership through the pre-interned TI:
# the memoized has_open_set bit may not pin yesterday's answer
@assert (g isa TI) "membership must be visible through types interned
before the set opened — the memoized has_open_set flag needs invalidation"
@assert !(h isa TI) "non-members stay exactly false (I1)"

println("m1_late_open_stale: OK")
