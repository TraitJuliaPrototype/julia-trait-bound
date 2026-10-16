# Stored values: `Dynamic{X}`, and fields declared by a bound

Proposal, revision 2 of 2026-10-16 (session 22), for the note "Traits for better Julia".

**Outcome (the user, 2026-10-16).**
- **D2 adopted:** `Dynamic{X}`, with the stored-value semantics of §2 that it needs (D1). It is in the note at rev 1125, as the Finer points subsection "Dynamic values".
- **D3 rejected:** "Hidden type parameters seem antithetical to Julia." Fields declared by a bound are not pursued. Stored state with a fixed representation uses explicit type parameters, as today.
- **D4 postponed:** solvers.

Revision 1 was reviewed by the fable-critic agent running on Opus; the Fable model's limit was reached. The review ran experiments on Julia 1.12.2 and on the prototype; its scripts are in the session scratchpad and its numbers are quoted below. What changed is listed in §9.

Two additions let trait-world code keep users' values beyond a call:
- **`Dynamic{X}`:** a value of any type conforming to `X`, reached through `X`'s operations, storable anywhere a trait-world value is.
- **Fields declared by a bound:** the stored counterpart of a bounded argument. The field's type is guaranteed concrete, and nobody writes it.

Both rest on one semantic rule for stored values (§2), which the note needs anyway: its returned closures already store trait objects.

## 1. Why

The note forbids storing a trait object: the row of "What code in a trait module may do" that begins "a trait object anywhere else, as a bare value", and trade-off 4. A library can keep only representations it has projected or copied. Three needs run into this:

1. **Values whose representation differs per element or changes over time.** A scene holds plots of different types. A Makie attribute changes from `:red` to a vector of colors. Every other language with dynamic dispatch has a storable dynamic value: C++ type erasure, Rust's `Box<dyn Trait>`, Swift's `any P` (other-languages §7). Mojo lists it as missing.
2. **User-defined behaviour kept alive.** A user's observable or recipe kept in a scene must stay itself, not a snapshot of its data.
3. **State that outlives a call,** whose field types should be guaranteed concrete without being written: an integrator's state and parameters.

Revision 1 also claimed that bounded fields would shorten the 3,553-character integrator type of findings §17. That claim was wrong. That type contains no user type: `u` and `p` are already `Vector{Float64}`, and `f` is already a dynamic call. Its length is library structure: the solution 51%, the options 16%, the `ODEFunction` 14%. Bounded fields for `u`, `p` and `f` remove nothing from it (§8, item 1).

## 2. What a stored value means

**A bound translates when a value crosses it, and storing a value through a bound is a crossing.**
- A value stored in a field declared by a bound is projected once, when it is stored.
- So is a value made into a `Dynamic{X}`.
- Later changes to the user's object are seen exactly as far as the projection shares data:
  - a projection that reads a field and shares its array sees in-place changes to that array;
  - it does not see the user rebinding the field to a new array;
  - a copying projection sees neither.

This is the semantics of Julia's typed fields, which convert at construction. `S(x)` with a field `x::Vector{Float64}` and an argument `Vector{Int}` stores a copy. And it is the semantics the note's returned closures already have: `colfun(t, i) = x -> x * colmean(t, i)` captures the projected `t`.

**"Identical or error" is unaffected.**
- The projection is code the conformer wrote, and it runs in both modes.
- Opting out tolerates pirates; it does not remove projections.
- The comparison the review made, a stored view against a struct holding the user's object, compares two different programs.

What the rule does change is what a user may expect. Documentation and concrete mode must say "stored through a bound: translated once, when stored", as Julia's manual says that typed fields convert.

**One safety obligation.** A view stored from a sharing projection keeps the user's object alive. The review measured the alternative: a projection sharing `unsafe_wrap`ped memory, freed by the user's finalizer after the call, returned 6987.0 from freed and reused memory where plain Julia returned 1000.0.
- So a stored view of a sharing projection holds the user's value as a root: a reference that is never read.
- Own representations and copying projections need no root.
- The same holds for trait objects captured by closures, which the note already allows.

**Rejected:** keeping the user's object and projecting again at every use. It would see every change. But anything holding the object would be compiled per user type, which is the growth the design exists to stop. A library that needs live data declares it in the trait, as an operation that reads the current value (§6, `Source`).

## 3. `Dynamic{X}`

```julia
struct Scene
    plots::Vector{Dynamic{Plot}}         # plots of any conforming type
    background::Dynamic{ColorSpec}       # :white now, an image later
end
```

1. **What it is.** A concrete trait-world type, the same for every conforming type. It holds one value, a trait object of `X` (with its root when the projection shares), boxed.
2. **Made only at a bound or from a trait object.**
   - At a bound: a `Dynamic{X}` argument or field projects from above.
   - From a trait object of `X`, inside: `Dynamic{X}(t)`.
   - Never from a bare value.

   Because nothing else can make one, its type decides it: `Dynamic{X}` is a leaf the entry admits by type. Inward doors, such as deserialization, re-validate the content.
3. **Operations dispatch on the boxed trait object.**
   - An operation of `X` on a `Dynamic{X}` is an ordinary dynamic call on the trait object inside, with the declared result type asserted. The code after it infers concretely.
   - It runs in the caller's world, as any dispatch does.
   - It serializes as its content. Its behaviour is fixed by the type of what it holds, never by a stored pointer.
   - The review measured this against pointer tables:
     - 22 ns per call with one representation, 78 ns with eight interleaved;
     - 9 ns for a pointer;
     - first call from a package image 18–34 µs, with no compilation.
   - Pointers are not used. Revision 1's pointer tables broke under world age, serialization and racing writes, as the review measured.
4. **Targets are listed.** The targets of an operation on a `Dynamic{X}` are the methods for the trait objects of `X`'s conformances, which come only from owners and delegates (rule 3).
   - A build lists the conformances whose representations reach a place where a `Dynamic{X}` is made.
   - `verify_main` counts each operation call on a `Dynamic` as a bounded call.
   - No load from outside adds a target.
5. **Opening.** Passing a `Dynamic{X}` to a function bounded by `X` opens it: one dispatch on the content selects the worker for its representation, which runs compiled. A loop over a dynamic value's data belongs in such a function, so the dispatch happens per call, not per element. Swift calls this implicit opening (SE-0352). Two `Dynamic` arguments opened by one function select a worker per pair of representations: a product, by the caller's choice.
6. **Equality** follows Swift's `AnyHashable`:
   - two `Dynamic{X}` values of different representation types are unequal;
   - otherwise equality is the trait's declared `==` operation if it has one;
   - without one, equality is `===` of the stored trait objects, so isbits representations like `:red` compare by value and arrays by identity.

   `hash` agrees.
7. **Several traits and supertraits.**
   - `Dynamic{(ColTable, RowTable)}` holds a trait object with one view per trait.
   - It converts to `Dynamic{ColTable}` by dropping a view.
   - `Dynamic{Sub}` converts to `Dynamic{Super}` through the supertrait's declared representation map.

   None of these conversions is implicit subtyping. All are explicit and checked.
8. **Which operations a `Dynamic{X}` has.** Any operation of `X` whose other arguments and result are declared types qualifies; dispatch handles the rest. A `Callable` argument fixed to `DynamicCall` counts as declared. Operations generic over another bound qualify too, opening that argument as an entry would. Operations returning the representation itself (constructors) return a `Dynamic{X}` instead.

**Relation to dynamic operations (form 6).** Form 6 decides at the conformance that a type's own operations run indirectly at a shared representation. `Dynamic{X}` decides at the use that the representation is hidden. Form 6's per-session pointers should move to the same mechanism (findings §16.6, item 3).

## 4. Fields declared by a bound

```julia
mutable struct Integrator            # in a trait module; a sketch
    u::StateVector                   # a field declared by a bound
    p::Parameters
    t::Float64
end
```

What this adds over `struct Integrator{U, P}` is smaller than revision 1 claimed:
- **projection at construction** (§2);
- **concreteness checked at the conformance;**
- **nobody writing the parameters.**

Julia already lets signatures omit parameters (`f(i::Integrator)`), and its REPL already abbreviates them in stack traces. That is why it is a separate decision (§10, D3).

1. **Hidden parameters.** A struct in a trait module may declare a field by a bound, which makes it parametric in the trait objects those fields hold: `Integrator{V₁, V₂}`.
   - The parameters are not written.
   - They cannot be named in a method signature; the definition is refused.
   - They confer no ownership. The prototype's ownership check counts type parameters, so it must skip them.
2. **The guarantee.** Each field holds a deeply concrete representation, checked at the conformance. So `Integrator{V₁, V₂}` is concrete, and code taking one is compiled per tuple of its fields' representations.
3. **The bare name in other type positions.**
   - `Integrator` alone is a `UnionAll`: `isconcretetype(Integrator)` is false, and `Vector{Integrator}` is abstract.
   - So in a trait module the bare name is allowed in argument position, and as a field type it is itself a field declared by a bound. That nests the hidden parameters.
   - Elsewhere, in a container, a `Ref` or a global, it is refused with the fix named: a field, or a `Dynamic` of a trait the struct conforms to.
   - Printing keeps Julia's distinction: a concrete type prints with its abbreviated parameters, the `UnionAll` without them.
4. **Construction and assignment from above are crossings.** The constructor, and `setproperty!` on a bounded field, project through the field's bound.
   - SciML callbacks set `integ.p`; Makie users set `plot.color`.
   - Assigning a representation other than the stored one is a type error. A field whose representation changes is declared `Dynamic{X}`.
5. **Field access.** Inside, `integ.u` is the trait object with the bound's operations. From above, nothing more is promised than for any trait-world value: ordinary code may hold it and pass it back down. Revision 1 called it "opaque"; the review showed that from above `getfield` reaches the trait object and its representation, so the safety argument (§5) does not rely on opacity.
6. **Functions in fields.** A field declared by a `Callable` bound stores the function in the field's mode. For an argument, a caller's `compiled_call(f)` wins. In a field it would turn every method of the library's struct into ordinary code compiled above, for the life of the value, so a stored function is converted to the field's mode.
7. **Compiled code.** Every method taking the struct is compiled per full tuple of its fields' representations, even `current_time(integ) = integ.t`, and a struct that stores it inherits the tuple. So within stored state the product is per struct, and across layers code adds up only where a layer projects or stores a `Dynamic`. Code lives where rule 4 puts a worker's.

## 5. The rule change, and why it is safe

**Proposed:**
- A trait object may be stored in a field declared by its bound, made into a `Dynamic{X}`, or captured by a closure. Each is a crossing, translated once (§2).
- Stored values may go up inside trait-world values, and a `Dynamic{X}` also bare.
- Still refused:
  - passing a trait object to an ordinary function;
  - `typeof(t)` and `t.field` inside the trait world;
  - storing a trait object where no bound is declared: an `Any` field, a `Vector{Any}`.

**Why it is safe.** Opacity is not the reason.
- **Rule 1.** Code above may hold, inspect and pass stored values, as ordinary code using the trait world. It cannot add a method that trait-world code reaches:
  - hidden parameters cannot be named and confer no ownership;
  - everything else is sealed as before.
- **Rule 2.** A stored value was translated by its bound when it crossed. Inside it is its trait's representation, opened only through the trait's operations.
- **Rules 3 and 4.** A `Dynamic`'s targets and a field's per-representation code come from conformances and live where workers live. A `Dynamic` made in one package and opened in another sees the same implementation, because the delegates load with the representation's package (checked by the review).
- **Sessions.** A value stored before a more specific implementation is defined at the prompt keeps the conformance it was stored with. Values stored afterwards use the new one. Package loads are not affected.

## 6. Makie with both: a rewrite of Makie, beside trade-off 1

This sketches a trait-world Makie, which trade-off 1 says Makie as written is not. It supersedes the note's current Makie paragraph in "Between nested types and `Any`", which has attributes as unions of Makie's own representations and recipes as downstream methods.

```julia
@trait_module module MakieCore                     # a sketch; names and signatures illustrative
@trait ColorSpec{R} begin                          # anything that yields colors
    colors(r::R, n::Int, cm::ColorMap)::Vector{RGBAf}
end
@trait Source{T, R} begin                          # live data: an observable of values of type T
    value(r::R)::T
    subscribe!(r::R, f::Callable{Tuple{T}, Nothing, DynamicCall})::Nothing
end
@trait Plot{R} begin                               # anything that draws itself
    primitives(r::R, s::SceneState)::Vector{Dynamic{Primitive}}
end

struct Lines
    points::Dynamic{Source{Vector{Point2d}}}       # position families as in note rev 1116
    color::Dynamic{ColorSpec}
    linewidth::Float32
end
struct Scene
    plots::Vector{Dynamic{Plot}}
end
end
```

**What users define.** Rule 3 admits all three, because Makie owns the traits and the user owns the type:
- **Their own attributes:** `@implement ColorSpec Gradient`.
- **Their own observables:** a type conforming to `Source{Vector{Point2d}}`.
  - Live data is an operation (`value`), not a snapshot. That is how a stored observable stays live under §2.
  - Its effects, reading a sensor or a file, are declared calls upward, with handles for what comes back. Conformance methods are trait-world code.
- **Their own recipes:** a type conforming to `Plot`, stored as a `Dynamic{Plot}`.

**Rendering and compiled code:**
- The backend walks the plots, one dispatch per plot, and runs each plot's work in code compiled per representation.
- Each compute edge is a function bounded by its inputs. Code adds up over edges, but within an edge it multiplies over the inputs it opens.
- Wide edges therefore call coarse operations on `Dynamic` inputs, `colors(r, n, cm)::Vector{RGBAf}`, instead of opening eight attributes.
- ComputePipeline already compiles per edge, so the gain is declared results, listed targets and user extensibility.

**Not covered.** Makie's recipes are reactive (`lift`, attribute passthrough, theming, `convert_arguments`, data limits, legends). That machinery, where most of Makie's `Any` lives today, would itself have to become trait-world code. The sketch shows only how users' values are kept.

## 7. Costs

- **`Dynamic{X}`:**
  - one allocation when made;
  - a dispatch per operation (22–78 ns), not inlined;
  - first calls from images without compilation.

  Concrete mode reports operations on a `Dynamic` inside a loop and names the fix: pass it to a bounded function.
- **Fields declared by a bound:** compiled per tuple of representations, for every method on the struct.
- **Printing:** a `show` override for types must be one method on an abstract supertype in TraitWorld. The review measured 2,848–3,321 method instances invalidated by the first such override in a session.

## 8. Limits, stated

1. **Solvers.** The stored-value design does not make a SciML-style solver fit the trait world.
   - The user's right-hand side is a function from above. It expects the user's own type, while the solver holds a trait object, and trait objects are not passed up.
   - It works only through an operation that returns the representation (for example `Vector{Float64}`) for the function to work on. That shares memory only for array-backed representations; otherwise it copies in and out at every stage, seven times per `Tsit5` step.
   - Also excluded or degraded:
     - callbacks from above that read and write `integ.u`;
     - `sol.u` in the user's type (needs constructor operations, trade-off 4);
     - forward-mode differentiation through the solver (needs traits with an element-type parameter, compiled per type);
     - GPU arrays;
     - out-of-place static arrays.
   - The route that fits is the other direction: the user's model conforms as trait-world code. `@implement ODEModel Lorenz` with `rhs!(m, du::StateVector, u::StateVector, p, t)` is compiled per representation in the user's package, with callbacks the same way. That asks users to write their model as trait-world code, which is a real restriction. It should be designed and measured before solvers are claimed.
2. **Type length.** Bounded fields shorten a type only where user types sat in its parameters. The SciML integrator's length is the library's own nesting; shortening it means making the solution, options and caches bounded or `Dynamic` themselves, a library redesign.
3. **Traits with extra parameters** (`Source{T, R}`) are not in the note. `T` must be concrete.

## 9. Changes from revision 1, after the review

| Review finding | Change |
|---|---|
| H1: stored projections diverge from a struct holding the user's object; freed memory read through `unsafe_wrap` | §2: storing is a crossing with convert-at-store semantics; sharing views keep the user's value as a root; covers closures |
| H2: the 3,553-character type has no user type | §1 and §8.2: claim withdrawn; findings §17.4 corrected |
| H3: the solver case is worse than stated | §8.1: a stated limitation, with the trait-world model route |
| H4: the bare struct name is abstract in containers, and printing hid it | §4.3 |
| H5: opacity is false from above; hidden parameters can be dispatched on and counted for ownership | §4.1, §4.5, §5: no opacity claim; hidden parameters cannot be named and confer no ownership |
| M1–M3: pointer tables and world age, serialization, racing writes | §3.3: dispatch on the boxed trait object, no pointers |
| M4: `Dynamic` failed the concreteness check | §3.2: a leaf, decided by its type, made only at bounds |
| M5: closures already store trait objects | §2, §5 |
| M6: compile-cost claims overstated | §4.7, §6 |
| M7: assignment from above, call mode of stored functions | §4.4, §4.6 |
| M8: Makie sketch gaps | §6: labelled a rewrite; position families; `Callable` argument fixed to `DynamicCall`; effects as declared calls; reactive machinery named as not covered |
| M9: stored values keep the conformance they were stored with | §5, Sessions |
| equality vs dynamic compatibility; invariance; printing invalidations | §3.6, §3.7, §3.8, §7 |
| terminology | no "erasure site", no "opaque"; the prototype's internal `Dyn` to be renamed |

## 10. Decisions

- **D1.** Stored values are translated once, when stored, like Julia's typed fields, and sharing views root the user's object (§2). The alternative, re-projecting at every use, compiles per user type. Recommended: adopt.
- **D2.** `Dynamic{X}` by dispatch on a boxed trait object, made only at bounds (§3). Recommended: adopt.
- **D3.** Fields declared by a bound (§4). Over explicit parameters they add projection at construction, the concreteness check and not writing parameters. Recommended: adopt, as the stored counterpart of a bounded argument. Drop if explicit parameters with a checked constructor are judged enough.
- **D4.** Solvers: user models as trait-world conformances (§8.1). Recommended: design and measure separately before the note says anything about solvers.

**Note edits, if D1–D3 are adopted:**
- **Rules:** rule 1's list of what crosses down; rule 2's sentence on what a trait object is inside.
- **"What code in a trait module may do":**
  - "a trait object is a view of the user's data, not a value";
  - the row beginning "a trait object anywhere else, as a bare value", which becomes stored through a bound or a `Dynamic`;
  - a new row for `Dynamic{X}`.
- **The conformance cost table:** form 6, "as pointers".
- **"Between nested types and `Any`":**
  - the Makie paragraph, replaced by §6 in short;
  - "A trait object cannot be stored";
  - "a dynamic operation's pointer is created at the first call in a session";
  - two rows in its table.
- **"Functions that cross the boundary":** "Functions returned up" (captured trait objects are stored values, §2) and "Trait objects never go up".
- **"Calls upward":** the handle paragraph keeps its own rules; the analogy to stored values is dropped.
- **Trade-offs:** 3 (`Dynamic` admitted by type), 4 (trait objects go out stored), 7 (dispatch cost of `Dynamic`).
- **"Simple AOT":** `Dynamic` targets listed.
- **A new subsection "Stored values"** in "Finer points", with §2–§5.
- **Findings:** §16.5's "Erased value storable: no"; §16.6, items 1 and 3; §17.5, item 2.
