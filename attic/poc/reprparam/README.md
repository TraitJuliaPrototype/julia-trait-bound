# poc/reprparam — the representation as a trait parameter

A trait now names its representation, `@trait ColTable{R}`, so declarations
may depend on it (`firstel(r::R)::eltype(R)`). The trait's operations can be
implemented once per representation, as ordinary methods that workers call
statically:

```julia
@implement ColTable{Vector{Vector{Float64}}} begin   # explicit representation
    ncols(r) = length(r)
    col(r, i) = r[i]
end
@implement ColTable begin ncols(r::MyRep) = …; … end  # R from the annotation
@implement ColTable Ramp begin … end                  # a user type that is its own representation (sealed too)
@implement ColTable Grid begin project(t) = GridRep(t.m); … end   # R from the projection
```

A seal is then a projection: `@seal ColTable T project(t) = …` (R inferred,
or declared as `@seal ColTable{R} T …`). A seal may still bring operations of
its own, which it then calls indirectly through the erased table; both kinds
coexist at the same representation, because workers specialize on which one
they get (`TraitRegions.Impl{Trait}` or the erased table). Only the owner of
the trait or of `R` (or an extension of one) may implement.

## Files

| path | role |
|---|---|
| `Columns/` | the library: trait `ColTable{R}`, an implementation for `Vector{Vector{Float64}}`, ops `colmean`, `colrange`, `total` (one `value` call per element) |
| `analysis.jl` | a user: three types sealed in the three ways (projection onto the library's representation, own representation, own operations) |
| `bench.jl` | steady state with a fine-grained operation; the cost of making a new type usable in a fresh session |

    julia --project=poc/reprparam/env -e 'using Pkg; Pkg.instantiate()'
    julia --startup-file=no --project=poc/reprparam/env poc/reprparam/analysis.jl
    julia --startup-file=no --project=poc/reprparam/env poc/reprparam/bench.jl

## Results (stock 1.12.2, October 2026, two runs)

Steady state, `total(t, len)` over 4 columns, one `value` call per element:

| len | plain Julia | implementation | the seal's own operations |
|---|---|---|---|
| 16 | 37–40 ns | 92–93 ns (2.3–2.5×) | 1,207–1,312 ns (30–35×) |
| 4096 | 14.6–15.0 µs | 14.9–15.5 µs (1.02–1.03×) | 357–376 µs (24–25×) |

Per element: plain 0.9 ns, implementation 0.9 ns, own operations 19–23 ns
(an indirect call each). At 16 elements the difference is the entry (seal
lookup, projection, dynamic call to the worker). The first run compared
against a plain loop whose unused result let the compiler drop the work; the
benchmark now consumes every result.

A fresh session, `using Columns`, then define a type, seal it, and make the
first calls of `colmean`, `colrange` and `total` (ms):

| way | seal | first calls | of which compiling |
|---|---|---|---|
| projection onto the library's representation | 113 | 3 | 111 |
| operations of its own at the library's representation | 120 | 11 | 125 |
| own representation with an implementation | 240 | 103 | 337 |

The seal itself costs 85 ms (traced). Two fixes found on the way:

- TraitRegions' own sealing code looked up `trait_info`, `seal_info` and
  `op_info` with static calls; every package that declares a trait or seals a
  type invalidated it (134 ms recompiled at the first seal of a session). The
  lookups now go through `invokelatest`, without edges: the machinery obeys
  the design's rule itself.
- `deep_concrete` used `fieldtypes(T)`, which compiles a closure for every
  type visited (about 70 ms). It now reads field types by index.

Before both fixes the first seal of a session cost 314–350 ms.

## Limits

Implementations for a Base-typed representation can only come from the
trait's owner (centralization, as in Tables.jl), unless a package extension
is allowed to provide them. A new representation compiles every worker it
uses once (about 30 ms per op here). Projections are still compiled per type.
