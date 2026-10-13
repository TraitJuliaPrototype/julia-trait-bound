# poc/world — the new design on stock Julia (TraitWorld)

The proof of concept of the design note "Traits for better Julia" (rev 101),
planned in `writeup/poc2-plan.md`. The machinery is the package
`TraitWorld/`; the packages here use it.

    julia --project=poc/world/env -e 'using Pkg; Pkg.instantiate()'
    julia --startup-file=no --project=poc/world/env poc/world/m1run.jl
    julia --startup-file=no --project=poc/world/env poc/world/bench_m1.jl
    julia --startup-file=no --project=poc/world/env poc/world/spike4.jl
    julia --project=TraitWorld -e 'using Pkg; Pkg.test()'

## Packages

| package | kind | role |
|---|---|---|
| `TraitWorld/` (repo root) | the machinery | traits, implementations, projections, trait modules, entries, `Callable`, checks (rules 1, 3, 5), the audit, concrete mode, `verify_main`; 97 tests |
| `BaseTraits` | trait module | `HasLength`, `Iterable`, `Indexable` over Base's functions; conformance for Base's families |
| `Columns` | trait module | `ColTable`: generic over `Indexable`, specific for `Vector{Vector{Float64}}` and `Matrix{Float64}`; `describe` with types first |
| `Rows` | trait module | `RowTable`, the bundle `Table` |
| `Stats` | trait module | functions over two bounds, `Callable`, `ColStore` (mutating), `weighted` (the piracy target) |
| `UserTypes` | ordinary | a conformer: projection, own representation, dynamic operations |
| `Pirate` | ordinary | defines `Stats.weight(::Float64)` |
| `App` | ordinary | an application depending on Stats and UserTypes; `main` for verify_main and trim |
| `delegation/` | GridLib, OtherD, ColsD | extensions: a delegate, and one with an unrelated trigger |
| `concrete/` | CBottom, CMid1, CMid2, CTop | the abstract field three trait modules below a hot loop |
| `trim/` | | `juliac --trim` builds of `App.main` |

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

## M2: Base capability traits and generic implementations

`BaseTraits` declares `HasLength` (`Base.length`), `Iterable` (`Base.iterate`
at two arities) and `Indexable <: HasLength` (`Base.getindex`), with
conformance declared for Base's families: `AbstractArray`, `Tuple`,
`AbstractString`, `AbstractDict`, `AbstractSet` (Iterable, HasLength);
`AbstractVector` and `Tuple` (Indexable). Columns implements `ColTable`
generically for every `Indexable` representation whose elements are
`Vector{Float64}`, and specifically for `Vector{Vector{Float64}}` and
`Matrix{Float64}`. `poc/world/m2_basetraits.jl`:

| representation | HasLength | Iterable | Indexable |
|---|---|---|---|
| `Vector{Float64}`, ranges, `BitVector`, a `SubArray`, tuples | declared | declared | declared |
| `Matrix{Float64}` | declared | declared | accidental |
| `String`, `SubString{String}`, `Dict{Int,Float64}` | declared | declared | accidental |
| `Set{Int}` | declared | declared | – |
| `Int`, `Float64`, `Char`, `Pair`, a `NamedTuple` | accidental | accidental | accidental |

"Declared" means declared and confirmed by inference at the declared types;
"accidental" means the methods exist without a declaration, so structural
conformance would accept it. Every declared Base family conforms. The check
treats an abstract declared argument (the iteration state) by existence only:
inference there says little, and every call asserts the result anyway.

- **A subtype that breaks AbstractVector's contract** (`Broken`, no
  `getindex`): inference finds the fallback that throws, TraitWorld warns once,
  and a trait module calling `t[1]` raises the identical `CanonicalIndexError`
  as plain Julia.
- **ColTable follows from the capability traits:** `Vector{Vector{Float64}}`
  takes Columns' specific implementation, a tuple of vectors, a `SubArray` of
  vectors and a user's own `Indexable` representation take the generic one; `Int`
  has `length` and `getindex` but is not a ColTable.
- **Generic against specific,** `total` over 4 columns: 1.00–1.03× at 4096
  elements, 1.09–1.22× at 16.
- **A conformance check** of `Indexable` costs 120–260 µs the first time and
  17–25 µs warm.

## M3: several bounds, joint projections, rule 4

`Rows` (RowTable, the bundle `Table`) and `Stats` (functions over two
bounds, `Callable`, a trait with a mutating operation). `poc/world/m3_views.jl`:

- **Projections run:** two for a type projected once per trait, one for a
  joint projection, `@implement (ColTable, RowTable) Joint project(t) = t.m`.
- **Workers:** with a joint projection the worker receives two views of one
  representation, and it is the representation's own worker (the one
  Stats' workload compiled for `Matrix{Float64}`). Separate projections need a
  worker for their pair of representations.
- **The bundle trait** `overview2(t::Table)` gives the same result as
  `overview(t::(ColTable, RowTable))`.
- **Rule 4:**
  - a mutation through a sharing projection reaches the user's data;
  - `@implement ColStore Frozen copies project(t) = deepcopy(t.cols)` is
    rejected, because ColStore has the mutating operation `setcol!`;
  - the same copying projection is accepted for ColTable.

## M4: dispatch, types first, then traits

Tested in `TraitWorld/test`:

- Unrelated bounds on one position (`f(t::ColTable)`, `f(t::RowTable)`) are
  rejected when the module is defined; adding `f(t::(ColTable, RowTable))`
  resolves them, and a value with both projections takes that method.
- A subtrait beats its supertrait (`Indexable` over `HasLength`): the worker's
  bound includes the supertraits, so Julia's own specificity agrees.
- An entry and a type method that differ in another position
  (`h(t::ColTable, x::Int)`, `h(v::AbstractVector, x::Integer)`) are reported
  as ambiguous at definition.
- `Matrix{Float64}` has a ColTable implementation, but `describe(m::AbstractMatrix)`
  still wins for it.
- A differential test over 13 values compares a library before and after it
  adopts a trait method. Only the three calls that used to reach the untyped
  fallback and have a projection change.

## M5: Callable

Library's choice per argument: `f::Callable{A, S}` erases a function from
above; `@specialize f::Callable{A, S}` compiles per function type. Functions of
the trait world (Base's `abs2`) are always passed as themselves. A function
called at two signatures carries two bounds, `f::(Callable{…}, Callable{…})`:
one erased pointer per signature. Results of another type are errors, where
plain Julia would widen. `poc/world/bench_m5.jl`:

| | 16 elements | 4096 elements |
|---|---|---|
| `colmap(h, t, 1)`, erased, against `map(h, v)` | 220 ns against 29 | 4.0–4.4 ns per element of overhead |
| `colsum(h, t, 1)`, specialized, against `sum(h, v)` | 120 ns against 7.7 | 1.31× |
| `colsum(abs2, t, 1)`, Base's function | 125 ns against 6.6 | 1.47× |

The fixed cost per call is about 110 ns: the entry, the function's wrapper
(cached per type for functions that capture nothing) and the checked call.
A fresh session's first call with a new closure:

| call | ms |
|---|---|
| `colmap(f, t, 1)`, erased | 7.3–8.4 |
| `map(f, v)`, plain Julia | 19–20 |
| `colsum(f, t, 1)`, specialized | 35–36 |

Erasure compiles only the closure's body.

## M6: layering, ownership and the audit

- **Rule 1 at two levels.**
  - A trait module's imports must be in the trait world.
  - Every call its library code makes is resolved on typed code, once per
    worker signature, following calls into helpers of trait modules. A
    trait module that reaches ordinary code without importing it
    (`Main.Plain.f(...)`) is reported with its line.
  - `poc/world/m6_rules.jl`, and tests.
- **Rule 5, delegation** (`poc/world/delegation/`).
  - ColsD declares the extension `ColsDGridExt`, triggered by GridLib, to
    implement its trait for GridLib's representation: it loads and works.
  - `ColsDBadExt` is triggered by GridLib and OtherD, but its method mentions
    only GridLib's type, so it is rejected when it loads. Whether a call saw
    its methods would otherwise depend on whether OtherD happened to be loaded.
  - While an extension is precompiled, Base has not recorded its parent
    yet. TraitWorld reads the relation from the parent's Project.toml, next to
    the extension's file.
- **The piracy audit**, ported from TraitRegions.
  - It runs in `checked_call`, once per worker signature and world. Each
    signature carries its own guard state in its compiled code.
  - A piratical method is one whose package owns neither the function nor the
    types in every signature it applies to.
  - The Pirate package defines `Stats.weight(::Float64)`:
    - warn mode (the default on stock Julia) names it once and then
      computes what plain Julia computes (8.0);
    - error mode raises `PiracyError`;
    - `mode!(:recompile)` is plain Julia.
  - Steady state is unchanged by the guard: 1.01× at 4096 elements, 2.9× at 16.
- **Ownership is attributed per module under `Main`.** A module defined in a
  script counts as its own package; `Main` itself is the session's.

## M7: caching (rule 7), concrete mode, verify_main and a trimmed binary

**Where compiled code lives.** `poc/world/m7_placement.jl`, a fresh process
with `--trace-compile`, first calls:

| first call | compiled in the session, with App loaded | without App |
|---|---|---|
| `colmean(v, 1)`, Columns' representation | 0 | 0 |
| `colmean(Measurements(…), 1)`, a conformer's projection | 0 | 0 |
| `colmean(Ramp(…), 1)`, a conformer's own representation | 0 | 0 |
| `weighted(v, 1)`, Stats at Columns' representation | 0 | 0 |
| `weighted(Ramp(…), 1)`, Stats at UserTypes' representation | 0 | 9 |

The last combination is in no package's image unless an application that
depends on both, App, compiles it: rule 7, the session last. The delegated
extension `ColsDGridExt` has a workload of its own. Two fixes were needed:
TraitWorld's own workload did not cover the audit (its `Iterators.product`
compiled per arity at the first call; now a loop), and Stats' workload did not
cover `weighted` at Columns' representation.

**Concrete mode** (`poc/world/concrete/`), ported. CBottom, CMid1 and CMid2
are trait modules now (rule 1); CTop is `@warn_on_abstract @trait_module`:

- The warning appears while CTop is built and names
  `field scale of CBottom.Config is declared Real (CBottom.jl:8)` with the
  chain through CMid2 and CMid1.
- A new session is not warned again: the check runs in `checked_call`'s first
  call of a signature, whose flag is saved in the image.
- The cliff: 66.0 against 0.89 ns per element, 74×.
- `check_concrete(sig)` gives the same report on demand, in 91 ms.

`@error_on_abstract` raises `AbstractTypeError`; either macro also applies to
one function inside a trait module.

**verify_main**, ported. TraitWorld's own dynamic calls are classified as
trait sites with enumerated targets: the builder per user type (`enter`), the
worker per signature (`checked_call`), a function argument's wrapper. Entries
are analyzed at their call site's argument types, so only the user types the
program can pass are enumerated, while native code is required of the real,
`@nospecialize` entry. Every enumerated worker gets the build-time checks
(rules 1 and 3) and the piracy audit. `App.main` chooses its table type at
run time:

    CLOSED: every call on a normal path reaches enumerated, compiled code
    closure: 147 method instances (56 on normal paths), 521 static calls
    dynamic calls: 1 bounded; 12 trait dispatch sites -> 8 targets (2 enter, 6 worker)
    holes on normal paths: 0

**A trimmed binary** (`poc/world/trim/build.sh`, `juliac --trim=unsafe-warn`).
`verify_main(…; entrypoints = true)` registers the targets and closes the
world. It fills the entry caches, and the binary runs no checks, no guard, no
erasure and no reflection. The binary is 2.09 MB and prints what the session
prints for both table types. Without verify_main the binary dies at the first
entry (the reflection path was trimmed). Trim reports 47 verifier warnings;
all are at the enumerated entry steps or on error paths. Routing the check
through a dynamic call took the reflection out of the binary (2.46 to 2.09 MB,
139 to 47 warnings).

Limit: dynamic operations (`@implement … dynamic`) hold erased function
pointers created at run time, so a closed world should use implementations.

## Findings

What the proof of concept taught about the design, beyond confirming it:

1. **Rule 5 must apply to an implementation's methods, not only to the
   trait.** Implementing an existing function (`Base.size`) for a foreign
   representation is piracy even when the trait is one's own. TraitWorld
   rejects it before defining anything. The trait's owner declares the
   existing methods instead, and conformance is checked.
2. **A type's own operations replace the representation's, never mix with
   them.** Operations a dynamic implementation leaves out come from the
   trait's defaults, calling its own operations. Falling back to the
   representation's implementation gave `Reversed` columns in the wrong
   order.
3. **Inference can confirm declared conformance only at concrete argument
   types.**
   - At an abstract declared argument (an iteration state) it says nothing.
   - It catches fallbacks that always throw (`Union{}`), but not ones that
     throw on some paths (`iterate` of a broken AbstractVector infers
     `Nothing`).
   - Every call asserts its result, so "identical or error" holds anyway.
4. **Structural conformance would accept `Int`, `Char`, `Pair` and
   `NamedTuple` for all three capability traits.** It would also accept
   `String`, `Dict` and `Matrix` as `Indexable`, against their meaning.
5. **Erased calls are cheap only if the callee is concrete.** The callee
   must declare concrete types, the caller pass boxes, and the wrapper have
   a fixed arity: 7 ns. Otherwise they cost 27–74 ns, or allocate.
6. **Check results belong where rule 7 puts the code.** A per-signature flag
   embedded in a generated function's code is saved with whichever image
   compiled it, for the rule 3 check, the audit's first run and concrete
   mode alike.
7. **The machinery must obey the design.** Registry lookups go through
   `invokelatest`, reflection paths through dynamic calls, and TraitWorld's
   own workload covers them. Otherwise loads invalidate it, sessions
   recompile it, and trimmed binaries carry it.
8. **Entries must be analyzed at their call sites.** Inside a `@nospecialize`
   entry every registered type looks possible; at the call site, only the
   program's own.

## Limits of the proof of concept

- **Rules 6 and 3 are approximations on stock Julia.**
  - Rule 6: Julia compiles against the whole method table, so the audit
    stands in for "compiled against what a call sees".
  - Rule 3: checked on typed code at first use, or at build time; not by the
    compiler.
- **Ownership checks for ordinary methods in a trait module** run right after
  the definition. A package that fails them does not build, but in a session
  the method stays defined.
- **Not supported:** keyword arguments, varargs and optional arguments in
  trait-bounded functions. An untyped fallback must come after the
  trait-bounded methods it falls back from.
- **Generic implementations' bodies** are not walked by the rule 3 check.
- **Dynamic operations in a closed world:** their erased pointers are created
  at run time, so a trimmed build should use implementations.
- **Fresh-session costs** of implementing a type at the REPL: 123–128 ms for
  a projection, 241–259 ms for dynamic operations. Most of it is inference
  in the checks.
