# poc/world — the new design on stock Julia (TraitWorld)

The proof of concept of the design note "Traits for better Julia" (rev 101),
planned in `writeup/poc2-plan.md`. The machinery is the package
`TraitWorld/`; the packages here use it.

    julia --project=poc/world/env -e 'using Pkg; Pkg.instantiate()'
    julia --startup-file=no --project=poc/world/env poc/world/m1run.jl
    julia --startup-file=no --project=poc/world/env poc/world/bench_m1.jl
    julia --startup-file=no --project=poc/world/env poc/world/spike4.jl
    julia --project=TraitWorld -e 'using Pkg; Pkg.test()'

## How TraitWorld works

- **Operations are functions, implementations are methods.** `@trait ColTable{R}`
  defines `ncols` and `col` as functions of the trait's module (or names an
  existing one, `Base.length`). An implementation is a method of them at the
  representation.
- **A trait object is a `TObj`** inside library code: a tuple of views, one per
  trait (with supertraits), each a witness and a representation. The only
  methods for `TObj` are the traits' operations, `ncols(t::TObj{T}) where
  {T >: ColTable}`, so library code calls operations with ordinary syntax and
  can do nothing else with `t`. The check of rule 3 reads the typed code once
  per worker signature and names each violation with its line.
- **A trait module** (`@trait_module begin … end` inside a package's module,
  or `@trait_module module M … end` in a script) has every top-level statement
  expanded after the ones before it ran. A function with trait-bounded
  arguments becomes workers (`TObj{T} where T >: Union{traits}`, compiled per
  representation) and an entry at `Any` that projects, erases functions, and
  calls the worker through a generated `checked_call`.
- **Witnesses** say where an operation comes from: `Impl{defaults}` (the
  representation's methods), `Generic{X, k, …}` (a generic implementation over
  other traits), `Dyn{table}` (a type's own operations, erased function
  pointers). Workers specialize on them, so the choice folds.

## M0: spikes (October 2026, Julia 1.12.2)

| Spike | Result |
|---|---|
| per-statement expansion in a trait module | works in a package image and at the REPL; `include(mapexpr, …)` carries it into included files. The package form must be `module M; using TraitWorld; @trait_module begin … end; end`: precompilation forbids `using` outside a module |
| the trait-object wrapper costs nothing | 0.96–1.03× plain Julia per element |
| erased functions through `@cfunction` | 4.6 ns per call for bits arguments in the spike; in TraitWorld 7.1 ns with a non-bits representation, once the callee declares concrete types (`Ref{T}`), the caller passes boxes (`Any`) and the wrapper has fixed arity. Untyped callees cost 27–74 ns, `Ref` on both sides allocates |
| definitions elsewhere do not invalidate trait-world code | after loading Columns and UserTypes, a new trait module over `Base.size`, a projection of a new type, a new representation and loading Printf and Statistics invalidated **no** Columns code (1 instance of TraitWorld's own registry lookup) |
| conformance by inference | catches a missing method behind a fallback that throws (`getindex` of an `AbstractVector` subtype without one infers `Union{}`), but not `iterate`, which then infers `Nothing`. `Int`, `Dict` and `String` have `length` and `getindex`: structural conformance would accept them |

Spike 4 also found a hole in rule 5: an implementation of an operation that is
someone else's function (`Base.size`) for someone else's type was accepted
because the implementer owns the trait. It is now rejected before anything is
defined; the trait's owner declares existing methods instead
(`@implement Sized{Matrix{Float64}}` without a block).

## M1: core

The note's example runs verbatim from package images: 1.5, 1.5, 4.0, 0.0.
39 tests (`TraitWorld/test`): the example; rule 3 and escapes with lines
(`firstrow(t)` with a ColTable object, `sum(t)`, `t.field`, `typeof(t)`, a
violation reached through a helper, a closure capturing `t`); ownership
(a stranger's implementation, `Base.size` for `Vector{Float32}`, a piratical
method, a `Union` with a foreign type); layering (a trait module importing an
ordinary module); conformance at definition (wrong result type, not deeply
concrete, a projection that does not infer, a missing operation).

Steady state, `total(t, len)` over 4 columns, one operation call per element,
two runs:

| len | plain | the representation | a projection | dynamic operations |
|---|---|---|---|---|
| 16 | 35.5–35.9 ns | 101 ns (2.8×) | 105–107 ns (2.9–3.0×) | 497 ns (14×) |
| 4096 | 14.5–14.6 µs | 1.00–1.01× | 1.00–1.01× | 7.0–7.3× (6.3–6.4 ns per element) |

TraitRegions (poc/reprparam): 1.02–1.03× at 4096, 2.3–2.5× at 16, a seal's own
operations 24–35× (19–23 ns per element). The entry costs about 65 ns.

A fresh session, `using Columns`, define a type, implement, first calls of
`colmean`, `colrange`, `total` (ms):

| way | implement | first calls | of which compiling |
|---|---|---|---|
| projection onto the library's representation | 123–128 | 9–10 | 129–133 |
| dynamic operations at the library's representation | 241–259 | 118–127 | 354–377 |
| own representation with an implementation | 204–209 | 104–107 | 305–310 |

TraitRegions: 113 + 3, 120 + 11, 240 + 103. Most of `implement` is Julia
inferring the projection and the conformance checks in a fresh session; the
dynamic case compiles a `@cfunction` per operation at first use.

Check results live where rule 7 places the code: `checked_call` is a
generated function whose per-signature flag is embedded in the compiled code,
so it is saved with whichever package image compiled that signature.
