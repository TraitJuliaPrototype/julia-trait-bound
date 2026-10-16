# Keys in TraitWorld: the adjusted plan

Session 22, 2026-10-16. The design notes were rewritten from representations to keys (commit 6c7f088). A critical review found three blocking problems and several significant ones. This plan says how each is decided, how the notes change, and how TraitWorld implements the result. Nothing here is implemented yet.

## 1. Decisions on the review's findings

**B1. One layout per trait and key; snapshots within a call; lenses only for writable fields.**
- **Within a call** a trait object's view holds:
  - the implementing value (the value itself, or its forwarding field), held;
  - every declared field the trait does not declare writable, held;
  - the user's object `o::Any` when the type is mutable, `nothing` otherwise;
  - for each writable declared field, its field index, as a runtime `Int`, because two user types with one key may place the field differently.
- **Writable declared fields are always lenses,** read and written through `o` and the index. The conformance already requires a mutable type with the field not `const` and declared with exactly its key type, so the layout depends on the trait, not on the user type.
- **One view type,** `View{X, W, K}`, replaces `View`, `FieldView` and `LiveView`. A key compiles one worker, whether the user type is mutable or not and whether the value is fresh or kept, so `mutable struct Mine` runs the worker Columns cached.
- **Kept values re-enter.** A `Dynamic` made from a mutable user type keeps `o` and the conformance's builder, and rebuilds the view from `o` at each use. This is what an entry does, so it costs about one entry per operation on a `Dynamic`. That is to be measured; today an operation on a `Dynamic` costs 20–80 ns. A `Dynamic` of an immutable type keeps its view.
- **What this gives up, listed as an exception to "identical or error":** within one call, a read-only part of the user's object that is rebound by code running during the call (a call upward, another task) is not seen until the next call. A write by the library itself goes through a lens and is seen.
- **Cost on stock Julia:** a lens read is 4.6 ns and a write 13.6 ns (findings §18); held parts cost what a field load costs. The cost now depends on the trait's choice (writable fields), never on the user's type.
- **The "calling convention" sentence (findings §19)** is corrected: the entry is a calling convention; lenses at full speed need runtime-emitted offset loads and stores with a write barrier.
- **GPU kernels:** a view carrying `o::Any` is not isbits. A kernel bound is opened on a held layout without `o`, which is valid only for traits without writable fields. Record this as an open point.

**B2. The motivation uses the callback measurement, honestly.**
- The overview's example becomes the measured case: in SciML a new callback closure recompiles the solver, 0.84–0.96 s, because the callback's type enters the integrator's type, although the step never reads it. A step bounded by `Integrator` declaring state, parameters, time, step size, cache and options compiles per those types; callbacks and the solution are not in the key.
- It also states what keys do not help: a `Float32` state and a new AD loss change the state's type (`U`, and the dual tag carries the loss's type), so they recompile as today.
- The withdrawn "3,553 characters, mostly the solver's own" argument is removed from the motivation; findings §17.4 stays the reference.

**B3. Implementation and conformance are separate.**
- **An implementation** gives the trait's operations for an implementing type: `@implement ColTable Vector{Vector{Float64}} begin … end`, or existing methods. It says nothing about fields.
- **A conformance** says how a user type joins: the implementing value (itself, or `by` a field) and the declared fields, each mapped to a stored field of the user type: by name by default, or written, `@implement ColTable Measurements by data, name => label`.
- A type without the trait's declared fields does not conform, but may implement the operations, so it can be the forwarding field of a type that conforms. The overview's `Vector{Vector{Float64}}` implements `ColTable`. If `ColTable` declared `name`, a bare vector would not conform, and a `Measurements` with a `label` would.

**S1. Declared fields are stored fields.** A declared field maps to a stored field of the user type, read by `getfield`. A user type with a `getproperty` method of its own conforms only with every declared field mapped explicitly; the conformance's message says why. Computed properties as declared fields are not offered; a conversion is the way (S3).

**S2. Forwarding carries through generic implementations.** A generic implementation is an implementation: it gives operations for implementing types that match its pattern. A user type that forwards `Indexable` to a field forwards `ColTable` to the same field when the field's type has a `ColTable` implementation, generic or not, so the key stays the field's type. A user type that implements `Indexable` itself matches the generic implementation as an implementing type, and the key is the user type.

**S3. Explicit conversion, shown with its costs.** 4-details gets the pattern:

```julia
@trait TableLike begin                              # what a converter reads: any table, by operations
    columnnames(t::TableLike)::Vector{Symbol}
    column(t::TableLike, n::Symbol)::AbstractVector  # not concrete: a conversion bound
end
materialize(t::TableLike)::Vector{Vector{Float64}} = [Float64.(column(t, n)) for n in columnnames(t)]
colmean_any(t::TableLike, i::Int) = colmean(materialize(t), i)   # the library's cached worker after the copy
```

The costs: a copy, no `Like{t}` (the result is the library's type), no write-through, and the conversion itself compiled per foreign type. Foreign families typed by their schema get one conversion per schema, not one library per schema.

**S4. `Like{t}` with declared fields.** A result like the input is built from the input's trait object by:
- a constructor operation returning `Self`, which replaces the implementing value;
- `withfields(t; u = …)`, which replaces declared fields; it works for traits with fields only, such as `Integrator`.

The entry inverts both by replacing the mapped fields of the user's object, through its constructor, as today. The worker returns `like(t, self)`, `withfields(t; …)`, or both, `withfields(like(t, self); …)`.

**S5, S6, the minor findings and the precedents:**
- 4-details:5 marks what the prototype runs; "direct field access" becomes "a held value or a lens"; "per key, not per user type" adds "unless the type implements the operations".
- "once per field type" for dynamic operations becomes "once per conformer".
- A subtrait's conformance must agree with the supertrait's, not be the same declaration.
- The leftovers ("fixed representation", "by bound and representation", the printing claim against findings §17) are fixed. TraitWorld prints `ColTable at R` for trait object types since feature 5; frames show it once that feature is run.
- A parameter defined both by an equation and by a field is refused (an equation between type functions).
- **Precedents:**
  - newtype deriving / `DerivingVia` rest on identical runtime representations, and the shared code comes from dictionary passing;
  - Go 1.18 groups types by underlying type, all pointers in one shape, and embedding uses generated wrapper methods per outer type, the analogue of the entry;
  - .NET shares generic code for reference types;
  - Julia's own function-barrier idiom and SciML's AutoSpecialize are the closest relatives.

## 2. TraitWorld, in phases

Each phase ends with the full suite passing on stock Julia 1.13.2, run alone and niced, and a commit.

1. **Notes first.** Apply section 1 to the four notes and findings §19.
2. **Trait syntax.**
   - `@trait Name{P...} begin … end` with operations declared at the trait, `f(t::Name, …)`.
   - `Self` in equations and results.
   - Fields typed by parameters define them; a field and an equation for one parameter is refused.
   - This lowers to the existing internal form with a hidden implementing-type parameter, so dispatch, archetypes and existential worker signatures are unchanged.
   - The old `{R}` spelling is removed from the public surface.
3. **Implementation versus conformance.**
   - `@implement X T begin … end` implements for `T`, with no `project`.
   - `@implement X T` (one line) uses `T`'s own methods, or the one field whose type implements `X`, else the field named `data`.
   - `@implement X T by f, name => g` forwards and maps fields.
   - `@implement X A where {A <: …}` covers families and generic implementations.
   - `dynamic by f begin … end` gives a type's own operations on its field.
   - Computed and copying projections (`project(t) = …`, `copies`, `unproject`) are removed, with an error that names explicit conversion.
   - The checks: ownership; completeness of operations for the implementing type and of fields for the user type, with types and mutability; concreteness of the key; `getproperty` overloads (S1).
4. **One view layout.**
   - `View{X, W, K}`, where `K` is the key type: the implementing type, or `Keyed{I, F}` with `F` the held fields' types.
   - The view holds `o` and the lens indices.
   - Field get and set go through held slots or lenses.
   - `Dynamic` re-enters for mutable types, and its measured cost per operation goes in findings §18.
   - `Like{t}` with `like` and `withfields`.
   - Associated types are read from `K`.
5. **Tests.**
   - Convert `runtests.jl` and the feature tests to the new syntax.
   - Tests of joint projections running once, and of copying projections, are deleted with their feature.
   - New acceptance tests:
     - a record trait `Integrator{U, P}` keyed on two fields;
     - mutable and immutable user types sharing one worker (`Base.specializations` count);
     - field mapping;
     - forwarding through a generic implementation;
     - `withfields`;
     - a kept `Dynamic` following a rebound field;
     - the within-call snapshot exception.
6. **Printing and membership.** Run the printing feature (bound and key) and `conforms(T, X)`, with the new key types.
7. **Out of scope, recorded.**
   - `experiments/interfaces` (DataFrames and Makie wrappers) uses computed projections and stops working against this TraitWorld; it stays pinned to the TraitWorld commit before phase 3, as a historical experiment.
   - Wrapping and sealing are not reworked now.

## 3. Risks

- **The re-entering `Dynamic`** may cost more than 20–80 ns per operation. The fallback is to keep the view and re-read only the rebindable held parts through a per-conformance refresher.
- **Phase 4 touches every place that builds or reads views** (entry, defcheck archetypes, viewcache signatures, verify_main). It is the largest step, about a third of TraitWorld's view code.
- **Removing the `{R}` spelling** rewrites most of the 971-line `runtests.jl`. Each test keeps its intent, or is deleted with its feature, named in the commit.

## 4. Second review, and the decisions on it

The reviewer read this plan (findings ranked, two blocking). Decisions:

1. **The snapshot is checked, not trusted (blocking).**
   - At the entry's exit, every held part of a mutable user type is compared with `getfield(o, i)` by `===`. A mismatch raises, naming the field and the fix: declare the field writable in the trait, so it becomes a lens.
   - In a solver, a callback that rebinds `integrator.p` therefore raises at the end of `solve`, unless the trait declares `p` writable. "Identical or error" holds. The cost is one load and one compare per held part per call.
   - Checks after each call upward would raise earlier. They are deferred, because they need the live trait objects at every call upward.
2. **Isbits lenses use the field's offset (blocking for the cost claims).** A lens over an isbits field reads and writes with `unsafe_load` and `unsafe_store!` at `fieldoffset`, under `GC.@preserve`; no write barrier is needed. Boxed fields use the builtins. The isbits case is measured in phase 4.
3. **The forwarding field may not be a writable declared field.** The conformance refuses the combination.
4. **`like` and `withfields` give a pending result.** A `Like` value carries the input's conformance and the new parts. Nothing operates on it; only the entry inverts it, rebuilding the user type through its constructor (`typename(T).wrapper`, or a written constructor for types with inner constructors), and raising if that fails.
5. **Membership.**
   - Every `@implement X T` is an explicit declaration for `T`; fields are mapped by name unless written.
   - A generic implementation confers membership only for traits without declared fields.
   - The block form `@implement X T begin … end` is both an implementation for `T` and its declaration.
   - A subtrait's conformance must agree with the supertrait's, field mappings included; a disagreeing later declaration is refused at its load.
6. **The key holds every declared field's type,** writable ones included: `Keyed{I, F}` with `F` all of them. Associated types are read from it.
7. **Phase order, revised.**
   1. Notes.
   2. The new trait syntax, accepted beside `{R}` and lowered to the same internal form. Old tests pass; new-syntax tests are added.
   3. Keys in one step: `Keyed` views, fields read from the user type, lenses (isbits by offset), the exit check, a re-entering `Dynamic` (identity of `o` and conformance for `==` and `hash`), implementation separate from conformance, field mappings, `withfields` and `Like`, parameters defined by fields, removal of computed projections. Also:
      - defcheck archetypes over `Keyed`;
      - viewcache keyed by `K`;
      - `verify_main` over conformances, not projection methods (verify.jl `_projected_types`), with the `Dynamic` builder listed as a target;
      - concrete mode tracing field types.

      Tests are converted in the same step.
   4. Remove the `{R}` spelling; convert the remaining tests.
   5. Printing, `conforms`, and the trimmed-binary acceptance build (alone, under a memory guard).
8. **Smaller items.**
   - A re-entering `Dynamic` is expected to cost 100–200 ns per operation, with the refresher as the fallback.
   - An explicit mapping reads by `getfield`, so the conformance message says that plain `x.name` may differ when `getproperty` is overloaded.
   - Measurements cited from `experiments/interfaces` (sealing audits, 3 ms view caches, binaries) are marked as taken before keys.

## 5. The reference layout replaces the held layout (the user's question, measured)

- **The question** (the user): "f(t::Trait{U,T}) … could just desugar to f{U,T}(t::Any) t.data::U + t.data2::T". Measured in `experiments/lens/layout.md`: with Julia's alias metadata on the loads (through `llvmcall` on stock Julia), the reference layout matches plain Julia in every loop measured, at about 2 ns per call. The user: "measure and if everything works go for it."
- **What the trait object is now.** A trait object is the user's object; each view holds the witness and the byte offsets of the implementing value and of the declared fields. Every access is a load or store at an offset.
- **Withdrawn** from sections 1 and 4: held parts; the exit check; lens indices; the re-entering `Dynamic` (a `Dynamic` keeps the trait object); the rule that the forwarding field may not be writable.
- **Phase 3, revised.** One view type, `View{X, W, K}`, holding the witness and the offsets, beside the user's object in the trait object:
  - isbits fields by offset, with TBAA through `llvmcall`;
  - reference fields by offset, as a pointer, with a type check;
  - writes to reference fields through `setfield!`;
  - fields stored inline that are not isbits through `getfield`;
  - a type that implements the operations itself is the implementing value, read as the object.
