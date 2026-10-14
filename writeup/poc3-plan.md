# Plan: a proof of concept of interface packages, around DataFrames and Makie

Status: proposal for review, 2026-10-14. It implements the design note "Traits
for better Julia" at rev 1010 on stock Julia 1.12, by extending TraitWorld.
TraitWorld as it stands (`TraitWorld/`, `poc/world/`) is the base; nothing in
it is thrown away. TraitRegions and the ecosystem packages stay as references,
and their harnesses are reused.

## 1. The two demonstrations

The proof of concept exists to show two things a reader can run. The
packages are the real ones: DataFrames.jl 1.x and CairoMakie from the
registry, not the toy library the note uses for exposition; Columns and
Stats, our own trait modules, are the trait side they are connected to.

**Demo 1, the interactive session** (`poc/interfaces/demo_session.jl`, run
line by line in a REPL, and as a script that prints the measurements):

1. `using Columns, Stats, DataFramesInterface, MakieInterface`. The trait
   stack and both interfaces load; Base, the standard libraries used, Columns,
   Stats, DataFrames' tree and CairoMakie's tree are sealed.
2. A `DataFrame` read from CSV is analysed by a trait module and plotted,
   without the trait module importing DataFrames or Makie. `--trace-compile`
   shows no trait-world compilation: the workers are in the images.
3. A new user type is declared at the REPL with the one-line form,
   `@implement ColTable Measurements`, and goes through the same pipeline.
   Time to first result and first plot for the new type are measured and
   compared with the ecosystem PoC's X1 and X8 (`attic/ecosystem/scripts`) (18 ms per type, flat).
4. Churn: `using CairoMakie` happened already; now `using ChurnStorm` (100
   types, Base methods, 20 redefinitions). `@snoop_invalidations` reports
   zero trees touching the trait stack, as X4 did, and the next call compiles
   nothing.
5. A worker in Stats is redefined at the REPL. Only its dependents recompile,
   measured; DataFrames' and Makie's caches are untouched.
6. `using Pirate` (a method on `Base.sum` for `Vector{Int8}`) is refused with
   an error that names the method and Base, and the pirate method is gone;
   in the other order, `using Pirate` first, the trait stack's load is the
   one refused, naming the pirate (note rev 1019: a seal checks the session
   as it stands);
   the next call of the affected worker gives Base's answer. In a second
   process, with `Pirate` tolerated in the project file, the same `using`
   loads it with a warning, and the affected worker runs plain Julia's
   answer. Two processes, because a deleted method comes back only with a
   restart (section 3.3).
7. A worker that reaches an undeclared inward door (`eval`, `deserialize`,
   `task_local_storage`) is refused at its build with the worker and line
   named; the same code through a declared call with a checked result is
   accepted. `@warn` inside a worker is accepted as an outward door and
   reported by concrete mode as a dynamic call.

**Demo 2, ahead-of-time compilation** (`poc/interfaces/App/`, built by
`poc/interfaces/build.sh`):

1. `verify_main(App.main)` on the full application, DataFrames and CairoMakie
   included: the trait world is closed, every declared call is listed as a
   target, every outward door is bound to the application's declared sinks,
   and the report names each dynamic site with its targets.
2. A `juliac` executable of the full application, without trimming. Started
   fresh, `--trace-compile` shows zero trait-world compilation; DataFrames
   and Makie behave as they do today behind their interfaces.
3. A `juliac --trim` executable of the trait-world pipeline alone: the same
   analysis fed by a standard-library reader (`DelimitedFiles.readdlm`) and
   writing text, no DataFrames, no Makie in the binary. Size and trim
   verifier warnings are reported as M7 did (2.09 MB, 47 warnings, all on
   enumerated entry steps or error paths).

The honest line, stated in advance: the design does not make Makie or
DataFrames trimmable; it quarantines them behind declared calls so that the
trait-world part of a program is trimmable and verifiable on its own. Demo 2
shows exactly that split.

## 2. Scope

**In scope**, everything the note has added since rev 105 that stock Julia
can express:

- Interface packages as a category: `@interface_package`, declared calls,
  handles, tolerations in the project file, BaseInterface implicit.
- BaseInterface: the door list with a direction, the check of globals, the
  walk into Base and standard libraries on typed code.
- Sealing: refusal of a pirate at load, the opt-out, the interim mode.
- `Callable{A, S, M}` with `CompiledCall` and `DynamicCall`, the wrappers
  `compiled_call(f)` and `dynamic_call(f)`.
- Keyword, default and variable arguments in trait-bounded functions.
- The one-line conformance `@implement Trait T` (a field named `data` or the
  one conforming field; methods win).
- `verify_main` extended to declared calls, outward doors and sinks.

**Out of scope**, what needs the patched runtime, as before:

- Rule 6 as compiled: specializations compiled against their closure only.
  The audit stands in for it. The old `binary/` universe-filter patch is not
  needed by this design and is not revived: refusal at load needs no change
  to dispatch.
- Reuse of a package's precompiled specializations after the audit instead
  of recompiling. On stock Julia there is one method table and one cache, so
  the question does not arise.
- Immunity of trait-world code against own-type methods at Base's abstract
  call sites. Stock Julia's invalidation does not know layering; the
  ecosystem PoC measured zero trees anyway (X4) and this PoC measures it
  again.
- Parametric user types as families (`@implement ColTable Series{T} where
  T`), unless time allows; DataFrames needs none.
- Refusal at a pirate's precompile. On stock Julia the refusal is a package
  callback after the load (section 3.5).

## 3. Architecture, as deltas on TraitWorld

TraitWorld keeps its architecture: operations are functions, implementations
are methods, trait objects are `TObj` views, trait modules expand statement
by statement, entries project and call workers through `checked_call`, whose
per-signature flag is saved with the image (rule 7), `verify_main` closes the
world. The deltas:

### 3.1 Interface packages, declared calls, handles

- `@interface_package Makie` at the top of an interface package's module
  records the package it wraps, reads the tolerations from the package's
  `Project.toml` (`[traits] tolerate = ["FixedPointNumbers"]`), and seals
  the wrapped package's dependency closure (3.5). A trait package needs no
  declaration: `@trait_module` seals its own package.
- `@handle Figure` defines `struct Figure <: TraitWorld.Handle; ref::Any; end`
  in the interface's trait module. The rule 3 checker treats a `Handle` as
  it treats a `TObj`: it may be passed to declared calls and to the module's
  own functions, and nothing else; `getfield` on it is reported.
- `@call Makie.scatter!(f, xs, ys; color)::Nothing` inside a trait module is
  a dynamic call with no inference edge: lowered to `invokelatest` with the
  result asserted to the declared type. Handles are unwrapped before the
  call and a result of a handle type is wrapped after it. The layering
  check accepts a call into a package outside the trait world only through
  `@call`, and only from the interface package that wraps it. A declared
  call is registered, so `verify_main` lists it as a target.
- The layering check's new error for an undeclared reach into a package
  nobody admits: "no interface admits X".

### 3.2 BaseInterface: the door list and the check of globals

BaseInterface is a module of TraitWorld, imported implicitly by every trait
module. It holds:

- the inward doors, a list of functions: `eval`, `include`, `require`,
  `invokelatest` outside `@call`, `Serialization.deserialize`, reflection
  (`methods`, `which`, `hasmethod`, `methodswith`, `Core.Compiler` queries),
  `getglobal`/`getproperty` on a `Module`, `task_local_storage`,
  `unsafe_pointer_to_objref`, `unsafe_load` of object pointers;
- the outward doors: the logging macros' functions, `display`, `print`,
  `println` and `show` without an explicit IO (they read `stdout`), `redirect_*`;
- the traits over Base's informal interfaces, moved here from
  `poc/world/BaseTraits` (`HasLength`, `Iterable`, `Indexable`, with their
  family conformances).

The layering walk (`checks.jl`, `_layering!`) today stops at Base and trusts
it. It is extended to walk into Base and the standard libraries, memoized per
method instance with a per-process cache and a budget, and to report, for a
worker signature:

- a read of a global whose binding type is not deeply concrete, or is not a
  constant and not typed (`stdout`, `Base.CoreLogging.global_logger`'s state,
  `Base.Multimedia.displays`, `Main`), unless the read is inside an outward
  door's own code;
- a call to an inward door outside a declared call;
- a call to an outward door, accepted, recorded as a dynamic site for
  concrete mode and `verify_main`.

Admission at the entry follows the note at rev 1019: a type that decides
(deeply concrete) is admitted by its type; a type that does not (a field
declared `Real`, a `Vector{Any}`) has its abstract parts walked by the
entry, at a cost concrete mode reports; representations must decide by
type. Values denoting code are caught by the existing deep-concreteness check at
the boundary (`Module`, `Type` of a non-trait-world type, `Method`, bare
functions without a `Callable` bound are refused as arguments and results).

### 3.3 Sealing, refusal, tolerations

- A registry of sealed packages: every loaded trait package (itself) and, for
  every loaded interface package, the wrapped package's dependency closure
  (from the manifest, through `Base.loaded_modules` and `Base.pkgorigins`).
  BaseInterface seals Base, Core and the loaded standard libraries.
- Refusal, the stock-Julia approximation. Julia has no hook on method
  definition, and a package's precompile process runs none of our code, so
  the earliest moment a pirate can be seen is after its image is loaded: a
  `Base.package_callbacks` entry runs after each package load, walks that
  package's methods (`Base.visit` over its module and submodules, against
  the methods seen at the previous callback), and runs the ownership check
  of `ownership.jl` against the sealed set. Every pirate that is not
  tolerated is deleted with `Base.delete_method`, as Revise does, and then
  `PiracyError` is thrown from the callback, so `using X` fails naming the
  method and the owner it would need. Right: no call ever sees the pirate,
  and the error is at the load. Wrong, and said so in the README: the
  package stays loaded and broken at those methods rather than absent; the
  insertion and the deletion invalidate as plain Julia does, so workers the
  pirate touched recompile once; the pirate's own precompile succeeds. Exact
  refusal at the definition and at precompile needs a hook on method
  insertion in the runtime, a far smaller change than the old universe
  filter, listed as the step after this proof of concept.
- Definitions at the REPL or by `eval`: the existing audit path on the next
  entry call, kept as the interim's warning mode in sessions.
- Tolerations: the union of the `[traits] tolerate` lists of the loaded
  interface packages and of the active project, read before any package
  loads. A tolerated pirate is never deleted; it loads with a warning, and
  the workers it touches run on it, as plain Julia does; the `GuardState`
  machinery of `audit.jl` stays as it is for that path. Refuse-then-tolerate
  is therefore two processes, never one session.
- Precompile-time refusal, for now: `TraitWorld.check_no_piracy()` run by a
  package's own tests, as Aqua's piracy test is, so a pirate's author sees
  the failure in CI. Self-policing, not enforcement.
- Modes: `TraitWorld.piracy_mode!(:refuse | :warn)`; `:warn` is the interim.
- Both load orders: the sealed registry is checked against the session's
  method tables when a trait or interface package loads, so a pirate that
  loaded first refuses the sealing load in `:refuse` mode and is tolerated
  with a warning in `:warn` mode.
- The dispatch check stays as `audit.jl` has it, ownership-based: a dynamic
  site accepts a method owned by a trait-world package that owns the
  function or an argument type (note rev 1019, rule 6).

### 3.4 Callable modes

`Callable{A, S, M}` with `M` one of `CompiledCall`, `DynamicCall`; a bound
without `M` is the UnionAll and supplies `DynamicCall`. The entry reads `M`
off the value's type when it is a `compiled_call(f)` or `dynamic_call(f)`
wrapper, else off the bound, strips the wrapper and translates: `Erased{A,S}`
(the existing `@cfunction` pointer) or the function itself (the existing
`@specialize` path). `@specialize` is removed. The long form
`Callable{A, S, DynamicCall}(f)` constructs the wrapper with the signature
fixed. Result bounds that are `Callable` or a trait use the same path.

### 3.5 Keyword, default and variable arguments

- The transform in `trait_module.jl` accepts `Expr(:parameters, …)`,
  `Expr(:kw, …)` and `Vararg`. Positional defaults are what Julia makes of
  them: the shorter methods become exported methods of their own.
- The entry is also the keyword sorter: it projects every bounded argument,
  positional or keyword, asserts declared keyword types, and passes the
  supplied keywords on as a named tuple; the worker fills the defaults.
  Workers are compiled per set of supplied keywords by name and type, which
  Julia does by itself once the worker takes `kws::NamedTuple`.
- Varargs: a bounded vararg is projected per element; the worker's key is the
  tuple of representations.

### 3.6 The one-line conformance

`@implement ColTable T` with no body: if `T` has methods for every operation,
or for every operation without a default, it is its own representation
(the existing `@implement ColTable{T}` path). Else the field named `data`, or
the one field whose type conforms, is the projection; a field whose type
conforms through a projection composes. Several conforming fields without
`data`, an abstract field type, or partial methods are errors at the
declaration, naming the field or operation. Methods win over a field.

### 3.7 `verify_main`

Extended to classify declared calls as targets with their declared
signatures, outward doors as dynamic sites bound to the application's sinks
(`App.sinks()` declares a logger and an IO of concrete types; a session has
none and the doors stay dynamic), and inward doors as holes unless declared.

## 4. Packages (`poc/interfaces/`)

| Package | Kind | Content |
|---|---|---|
| `BaseInterface` | module of TraitWorld | door lists, global check, the capability traits from `poc/world/BaseTraits` |
| `Columns`, `Stats`, `UserTypes` | trait packages, from `poc/world` | unchanged except keyword arguments where the demo wants them |
| `Reports` | trait package, new | composes Columns and Stats; `summary(t::ColTable; cols = 1:ncols(t))`, `zscores(t, i; baseline::ColTable = t)`; the worker that is redefined in demo 1 |
| `DataFramesInterface` | interface package, new | `@implement ColTable DataFrame project(df) = Tables.columntable(df)`, shares (the column vectors themselves); conformance refused for a `DataFrame` whose columns are not concretely typed, at the boundary, which demo 1 shows; declared calls `DataFrame(nt)::Handle` and `nrow`; tolerations for DataFrames' tree as the audit finds them |
| `MakieInterface` | interface package, new | `@trait PointSeries{R}`; `@handle Figure`, `@handle Axis`; declared calls `figure`, `axis!`, `scatter!`, `hist!`, `lines!`, `save`, `display`; keyword arguments for the attributes used; Makie's globals behind the calls; CairoMakie as the backend; tolerations for Makie's tree as the audit finds them; `ColPlots`' `histcounts` reduction moves into `Reports` |
| `Pirate` | adversary, from `poc/world` | a method on `Base.sum(::Vector{Int8})` |
| `ChurnStorm` | adversary, from `attic/ecosystem` | ported to the TraitWorld environment |
| `App` | application | `main(args)`: CSV to DataFrame, `Reports.summary`, a plot through MakieInterface; `sinks()`; the trim variant `App.pipeline` with `readdlm` and text output |
| `env` | environment | Julia 1.12.2 pinned (TraitWorld's and `poc/world`'s version; 1.12.3 smoke-tested at M9), DataFrames, CSV, CairoMakie, PrecompileTools, SnoopCompileCore |

## 5. Milestones

Each milestone ends with its tests in `TraitWorld/test`, a script under
`poc/interfaces/`, and a section in `poc/interfaces/README.md`.

| | Milestone | Shows | Size |
|---|---|---|---|
| M0 | Environment and baselines. A fresh environment with pinned versions; the plain twin of demo 1 (DataFrames and CairoMakie without traits) measured for time to first result, first plot, and `using CairoMakie` invalidations; the harnesses `observe.jl`, `x4_churn.jl`, `x8_makie_scaling.jl` ported from `attic/`. | the numbers to beat | S |
| M1 | Keyword, default and variable arguments (3.5). | `summary(t; cols = …)` through an entry | M |
| M2 | Callable modes (3.4); `@specialize` retired; the Stats example of the note. | the caller's override, measured against the library's default | S |
| M3 | Declared calls, handles, `@interface_package` (3.1); MakieInterface and DataFramesInterface; `Reports`. First end-to-end run of demo 1, steps 1 and 2. | DataFrame in, plot out, no import of either in a trait module | L |
| M4 | The one-line conformance (3.6); demo 1 step 3; marginal cost per new type against M0's twin and X8. | a type conforms in one line at the REPL | M |
| M5 | BaseInterface (3.2): the door lists, the global check, the walk into Base with memoization and a budget; demo 1 step 7; the audit's cost per worker signature, and the list of Base functions that fall out of typical workers. | which part of Base passes, found automatically | L |
| M6 | Sealing (3.3): the sealed registry, the package callback, tolerations, modes; demo 1 step 6; the audit of DataFrames' and CairoMakie's trees, with the pirates found written into the two interfaces' tolerations. | a pirate refused at load, then tolerated | M |
| M7 | Demo 1 complete: steps 4 and 5, the churn and redefinition measurements, the script that prints the table. | interactivity, with numbers | M |
| M8 | Demo 2: `verify_main` on `App.main` (3.7); the `juliac` executable of the full application; the `--trim` executable of the pipeline; sizes, warnings, `--trace-compile` of each. | AOT, with the quarantine made visible | M |
| M9 | Write-up: README with all results, findings into `writeup/design-findings.md` and the note, a session note, a Fable review of the code and the claims, and the fixes it asks for. | | M |

Order: M0, M1, M2 are independent and can be interleaved; M3 needs M1; M4
needs M3; M5 and M6 need M3 and are independent of each other; M7 needs M4
to M6; M8 needs M5 and M6; M9 last. Sizes: S is a session, M two or three,
L a week of sessions.

## 6. What carries over

| From | What | How |
|---|---|---|
| `TraitWorld/` | everything: `core`, `trait`, `implement`, `trait_module`, `entry`, `checks`, `audit`, `ownership`, `concrete`, `verify` | extended in place; the test suite (117 tests) must keep passing after every milestone |
| `poc/world` | Columns, Stats, UserTypes, Pirate, BaseTraits, `env`, `trim/build.sh`, the M7 scripts | BaseTraits becomes BaseInterface's traits; `build.sh` gains the untrimmed build |
| `attic/ecosystem/ColPlots` | design B, the worker reduces and Makie is called at the boundary; `@recompile_invalidations` around CairoMakie | the reduction moves into `Reports`; the boundary call becomes a declared call; the precompile trick stays in MakieInterface's ordinary half |
| `attic/ecosystem/ChurnStorm`, `attic/ecosystem/scripts/x1, x4, x6, x7, x8` | the adversary and the measurement harnesses | ported to the new environment; the tables of demo 1 use their formats, so the numbers are comparable with August's |
| `attic/poc/verifymain/observe.jl` | `--trace-compile` and `@snoop_invalidations` harness | reused as in TraitWorld |
| `attic/binary/` | the universe-filter patch | not used; the design no longer needs sealed resolution. The README of `poc/interfaces` says why |

## 7. Risks

| Risk | Fallback |
|---|---|
| A `DataFrame`'s columns are `AbstractVector`s in a `Vector{AbstractVector}`, so the projection's result type depends on the data | `Tables.columntable` gives a `NamedTuple` whose field types are the actual column types; the deep-concreteness check at the boundary refuses columns of abstract element type, which is the right answer and part of demo 1. Workers compile per column-type tuple, which the measurements show. |
| The walk into Base is too slow or too large for the audit's budget | memoize per method instance across signatures and save the flags with the image, as `checked_call` does; cap the walk and report "unchecked beyond the budget" rather than silently admitting; as a last resort admit a listed set of Base functions for the PoC and say so |
| Keyword support interacts badly with the entry's `@nospecialize` and with `verify_main` | entries take `kws::NamedTuple` explicitly; `verify_main` analyzes entries at call sites, where the named tuple type is known |
| `package_callbacks` sees a pirate only after its load; `delete_method` leaves the package loaded and broken, and the insert-then-delete recompiles the workers it touched | documented as the stock-Julia approximation; the demo's refuse and tolerate steps run in two processes; the precompile-time refusal is `TraitWorld.check_no_piracy()` in a package's tests for now; exact refusal is a method-insertion hook in the runtime, the step after this PoC |
| DataFrames' or CairoMakie's trees contain pirates against Base | expected; they go into the interfaces' tolerations with the audit's list, which is itself a finding worth reporting |
| `juliac` without `--trim` cannot build an executable with CairoMakie, or the executable's startup compiles | fall back to a sysimage (`PackageCompiler.create_sysimage`) started with `--sysimage`, which shows the same `--trace-compile` fact; report which one was needed |
| Makie's own first-plot cost dominates every plotting number | state it, as X7 did; the trait-world numbers are measured on the reduction, the per-type marginal cost on X8's scale |
| Julia 1.12.3 differs from 1.12.2 in trim or precompilation behaviour | pin one, record it, and smoke-test the other at M9 |

## 8. Decisions for review

1. Names: `BaseInterface` inside TraitWorld, `DataFramesInterface`,
   `MakieInterface`; packages under `poc/interfaces/`.
2. Backend: CairoMakie, as in August, so the demo runs headless and saves
   PNGs; GLMakie later if wanted.
3. The DataFrame projection shares the column vectors (no copy), so a trait
   with mutating operations may accept it (rule 4); results come back as a
   `DataFrame` only through a declared constructor call.
4. Demo 2's full executable is `juliac` without trimming, the trimmed one is
   the pipeline without DataFrames and Makie. No attempt to trim Makie.
5. The capability traits move from `poc/world/BaseTraits` into
   BaseInterface, which makes them implicit everywhere.
6. Parametric families stay out unless M4 finishes early.
