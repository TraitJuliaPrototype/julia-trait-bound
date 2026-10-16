# Plan: a fresh proof of concept of the new design (TraitWorld)

Status: proposal for review, 2026-10-13. It implements the design note
"Traits for better Julia" at rev 101 on stock Julia 1.12.2. TraitRegions stays
as it is, as the reference for the earlier design and its measurements.

## 1. Scope

**In scope:** everything in the note that stock Julia can express.

- Trait modules.
- Traits over new and existing functions, with defaults.
- Implementations: per representation, per family, and generic over other
  traits.
- Projections: single, joint and dynamic.
- Trait-bounded functions (entry plus workers) with several bounds per
  argument.
- Dispatch with types first.
- `Callable`.
- Base capability traits (`HasLength`, `Iterable`, `Indexable`) with
  conformances for Base's families.
- Build-time checks for rules 1, 3 and 5 and for conformance.
- Concrete mode, `verify_main`, and caching per rule 7.
- The piracy audit (warn mode, error mode as the design).

**Out of scope:** what needs the patched runtime (Stage 2/3 in the findings
file).

- Compiling a specialization against only what its call sees (rule 6).
  Stock Julia compiles against the whole method table; as in TraitRegions,
  the audit stands in for it.
- Separate trait-mode CodeInstances.
- The dynamic import, constructor operations and inline entries.

## 2. Architecture

The main simplification over TraitRegions: **operations are functions,
implementations are plain methods, and a trait object inside library code is
a small wrapper type whose only methods are the trait's operations.** Library
code then calls operations with ordinary syntax. No body rewriting is needed,
and dispatch itself enforces the contract.

1. **Traits are types.** `@trait ColTable{R} begin … end` defines
   `abstract type ColTable{R} <: TraitWorld.Trait end`. Its declarations are
   stored as methods: operations with argument and result types as
   functions of R, defaults, supertraits, and which operations mutate.
2. **Operations are functions.**
   - A new operation is a function owned by the trait's module
     (`function ncols end`). An existing one is referenced (`Base.length`).
   - Implementations are plain methods of those functions at R, plus a
     marker method `implements(::Type{ColTable}, ::Type{R})`. Rule 5
     ("implementations are methods") then holds literally, and ownership is
     Julia's own.
   - This replaces TraitRegions' `impl_op(Trait, Val(op), …)`.
3. **Trait objects inside workers are `TObj{Trait, W, R}`,** an immutable
   pair of a witness and a representation.
   - `@trait` defines one method per operation on `TObj{ColTable}`. It
     forwards to one of four places, chosen by the witness type W, so the
     choice folds in compiled code:
     - the implementation's method (static);
     - a generic implementation;
     - the trait's default;
     - a dynamic table (indirect).
   - Results are asserted to the declared type.
   - Anything else applied to `t` (`sum(t)`, `t.field`, a function bounded by
     another trait) finds no method. The build-time checker reports it, which
     covers rule 3 and the "may do" table.
   - Several bounds become `TViews{(ColTable, RowTable)}`, one `TObj` per
     bound. Methods of trait-module functions pick the matching view
     statically.
4. **Trait modules.** `@trait_module module M … end` wraps each top-level
   statement in `TraitWorld.@stmt`.
   - Each statement therefore expands after the earlier ones have run, so
     traits and imports are known when a function definition is processed.
     `include(file)` becomes `include(TraitWorld.transform, file)`.
   - A definition with trait-bounded arguments becomes two kinds of method:
     - **workers:** the user's body as methods on `TObj`/`TViews`, compiled
       per representation. Calls between functions with matching bounds go
       straight to them.
     - **the entry:** a method at `Any` in each trait position. It looks up
       projections, guards and calls the worker. It is merged with the
       module's untyped fallback, if there is one.
   - The module is recorded in the trait-world registry.
5. **Projections are registered as methods,**
   `projection(::Type{ColTable}, ::Type{T})`.
   - Each record holds the projection function, the witness, and whether
     the projection shares or copies the user's data.
   - Entries read them through `invokelatest` with a per-entry cache, so
     there are no edges and no invalidation (the fix found in session 13).
   - A joint projection is one record shared by several traits.
   - The witness is computed when the projection is registered:
     - `Impl{defaults}`: methods at R, plus the operations that fall back to
       defaults;
     - `Generic{k}`;
     - `Dyn{table}`.
6. **`Callable{A, S}`** is a built-in trait. Inside workers a function is a
   `CObj{A, S, F}`, whose call method checks the arguments against `A` and
   asserts the result to `S`. The entry chooses F:
   - **a trait-world function** (its type's module is owned by Julia or a
     trait module): the function itself, always specialized;
   - **a function from above:** `Erased{A, S}`, a `@cfunction` pointer plus a
     reference, the FunctionWrappers.jl technique without the `convert`;
   - **a function from above at an argument the library marked
     `@specialize`:** the function itself.
7. **Dispatch, types first.**
   - Type-annotated methods stay as they are, and trait positions are lowered
     to the entry at `Any`.
   - The entry resolves among bound sets: a subtrait beats its supertrait,
     and a superset of bounds beats a subset.
   - Unrelated bounds with no resolving method are an error at definition:
     the macro checks within a module, and a later module checks against
     methods already defined.
   - Ambiguities between entries and type methods with other positions are
     reported with `Test.detect_ambiguities` on the lowered methods.
8. **Build-time checks.** These run while the package image is built, or at
   definition in a session.
   - **Layering (rule 1):**
     - every `using`/`import` target is in the trait world;
     - every call reachable from a worker at a representation resolves to a
       trait-world method, a `TObj` operation or a `CObj` call. This walk is
       built on verify.jl's scanner.
   - **Ownership (rule 5):** every method a trait module, implementation or
     projection defines, checked per applicable signature with `Union`
     members expanded. A delegation must name an extension whose triggers
     are packages its methods mention.
   - **Conformance:** at each concrete R, every operation needs an applicable
     method whose inferred result is the declared type. A result inferred as
     `Union{}`, which is a fallback that throws, is rejected at registration.
   - **Concrete mode:** ported from concrete.jl.
9. **Runtime guard:** the piracy audit from audit.jl, attached to entries;
   warn mode on stock Julia, error mode available. `catch` inside trait
   modules rethrows `PiracyError`, ported from `_rethrow_piracy`.
10. **Caching (rule 7):** compile workloads go where rule 7 says.
    - A trait module compiles workers for its own representations.
    - `@implement` in a conformer package compiles entries and workers for
      the representations it brings.
    - A package extension compiles for packages that meet only there.

## 3. Packages

| Package | Role |
|---|---|
| `TraitWorld/` | the machinery: traits, implement, project, trait_module, entry, dispatch, callable, ownership, layering, audit, concrete, verify; tests |
| `experiments/world/BaseTraits` | capability traits `HasLength`, `Iterable`, `Indexable` over Base's functions; conformances for `AbstractVector`, `Tuple`, `AbstractRange`, `AbstractString` (Iterable only), `AbstractDict` (Iterable only) |
| `experiments/world/Columns` | `ColTable{R}`: `ncols`, `col`, default `firstcol`; a generic implementation over `Indexable`; a specific one for `Matrix{Float64}`; `colmean`, `colrange`, `meandiff`; `describe` with types-first methods |
| `experiments/world/Rows` | `RowTable{R}`, `firstrow`; the bundle trait `Table{R} <: (ColTable{R}, RowTable{R})` |
| `experiments/world/Stats` | uses Columns; `colmap` (erased `Callable`), `colsum` (`@specialize`), `summary(t::(ColTable, RowTable))` |
| `experiments/world/Grid` | a trait module with its own representation type; Columns delegates `ColTable{GridRep}` to the extension `ColumnsGridExt` |
| `experiments/world/UserTypes` | an ordinary conformer: `Measurements` (projection), `Ramp` (own representation), `Reversed` (dynamic), `MyRows` (own `Indexable` representation, hence a ColTable through the generic implementation), `Both` (joint projection), `Broken <: AbstractVector` (breaks the contract) |
| `experiments/world/BadLayer`, `experiments/world/Plain` | a trait module that imports an ordinary package: must be rejected |
| `experiments/world/Pirate` | pirates a Base method that Columns' workers call |
| `experiments/world/App` | an ordinary application with `main`, for `verify_main` and a `juliac --trim` build |

## 4. Milestones

Each milestone ends with its tests passing and its numbers written into a
README.

**M0. Spikes** (small, first, since the plan depends on them):
1. Per-statement expansion in `@trait_module`, including
   `include(mapexpr, file)`, under precompilation.
2. `TObj` forwarding inlines to the plain call: check `code_typed`, and
   per-element cost against plain Julia.
3. An erased `Callable` through `@cfunction` on 1.12: a captured closure, the
   result assert, cost per call at 16 and 4096 elements. Fallback:
   FunctionWrappers.jl.
4. Witness types fold in workers, and defining traits or projections
   elsewhere invalidates nothing (`--trace-compile` and invalidation
   logging).
5. Inference-based conformance: catch Base's fallbacks that throw (a
   `Union{}` result), with few false alarms over Base's concrete types.

*Gate:* all five work, or the plan is adjusted before M1.

**M1. Core.** Traits, implementations, projections, trait modules,
entries and workers with one bound per argument; ownership checks for
`@implement`.
- The note's example runs verbatim and prints 1.5, 1.5, 4.0 and 0.0.
- A rule-3 violation is reported at build.
- Measure: one operation call per element against plain Julia (target ≤ 1.05×
  at 4096 elements), and dynamic operations against TraitRegions' 24–35×.

**M2. Base capability traits and generic implementations.**
- BaseTraits with family conformances; defaults; the generic ColTable over
  `Indexable`; specific beats generic; the overlap check.
- A survey script: which concrete Base types meet which capability trait at
  the declared types.
- Counterexamples for derivation: `Number` and `String` have the methods but
  are not declared.
- `Broken` raises the same error as in plain Julia, and concrete mode reports
  it at build.
- Measure: generic against specific speed (target: equal), and the cost of a
  conformance check.

**M3. Several bounds and joint projections.**
- `TViews`; `summary(t::(ColTable, RowTable))`.
- Count projections: two separate, one joint.
- A joint projection passes one argument, and workers compile per
  representation, not per pair.
- Projections declare shares or copies; a mutating trait rejects a copying
  projection.
- The bundle trait `Table`.

**M4. Dispatch, types first.**
- The `describe` example; merging the untyped fallback into the entry.
- Unrelated bounds without a resolving method are an error at definition;
  ambiguities are detected.
- A differential test over a corpus of values: adding the trait method leaves
  every call that worked before with the same result.

**M5. `Callable`.**
- Erased, `@specialize`d and trait-world functions; a result of another type
  is an error where plain Julia widens; two signatures through two bounds.
- Measure:
  - `map` with erased, specialized and plain closures at 16 and 4096
    elements;
  - first-call latency for a new closure, where an erased one should compile
    only the closure body.

**M6. Layering, ownership and the audit.**
- BadLayer is rejected at both levels (import and reachability).
- Delegation through Grid's extension; an extension triggered by an unrelated
  package is rejected.
- Pirate gives a warning, or `PiracyError` in error mode; `catch` inside trait
  modules rethrows it.

**M7. Caching and AOT (rule 7).**
- Precompile placement for the trait module, the conformer and the
  extension.
- Fresh-session costs: a new projected type, a new representation, a new
  closure. Compare with experiments/reprparam: 113 + 3, 240 + 103 and 120 + 11 ms.
- `verify_main` ported, with `Callable` targets; App built with
  `juliac --trim`.
- Concrete mode ported.

**M8. Write-up.**
- READMEs for the packages.
- A section in design-findings.md.
- A session note.
- The note's mentions of the prototype updated.

Sizes, relative: M0 S, M1 L, M2 M, M3 M, M4 M, M5 M, M6 M, M7 M, M8 S.

## 5. What carries over from TraitRegions

| TraitRegions | In TraitWorld |
|---|---|
| `ownership.jl` (Julia as one owner, extension parents) | ported; `Union` members per signature, delegation |
| `audit.jl` (GuardState, piracy audit, modes) | ported, guards on entries |
| `verify.jl` (`verify_main`, error-path analysis) | ported; projections instead of seals, `Callable` targets; scanner reused for the layering walk |
| `concrete.jl` (root-cause traces) | ported, aware of `TObj` |
| registry lookups through `invokelatest`, `deep_concrete` by index | kept |
| harnesses: `observe.jl`, the benchmarks that consume their results | reused |
| `@region`, `@seal`, `impl_op`, `_wcall` body rewriting, `sealed`/universe world | dropped |

## 6. Risks

| Risk | Fallback |
|---|---|
| per-statement expansion breaks under precompilation or with `include` | require traits to be defined or imported before the module, and expand in two phases |
| an erased call costs too much, or `@cfunction` closures are limited | FunctionWrappers.jl; report the cost either way |
| folded witness or marker lookups cause invalidation, as in session 13 | compute everything at the boundary through `invokelatest`, and give workers only types |
| methods on Base functions for `TObj{Trait}` look like piracy by Aqua's rule | define `TObj{Trait}` as owned by the trait's owner, documented |
| entries at `Any` collide with user methods that have `Any` in other positions | report at definition; resolving methods as in M4 |
| the conformance check has false alarms from inference | warn instead of error for families; error for specific implementations |
| rule 6 cannot be shown on stock Julia | as in Stage 1: the audit finds the conflicts; Gate A stays a separate measurement |

## 7. Decisions for review

1. Names and places: package `TraitWorld/`, packages under `experiments/world/`.
2. Traits as abstract types `ColTable{R}`, so `t::ColTable` and
   `TObj{ColTable}` read naturally.
3. Operations are functions. Two traits that share an operation function
   (`Base.length` in `HasLength` and `Indexable`) share its meaning and its
   implementation.
4. The first set of capability traits: `HasLength`, `Iterable`, `Indexable`.
   `ArrayLike{N}` comes later.
5. Errors for layering, ownership and conformance of specific
   implementations; warnings for the piracy audit and for family
   conformance on stock Julia.
