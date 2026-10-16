# Associated types in the trait-bound design

Exploration of 2026-10-16, written for the question: "I think we need the associated types if traits are going to work in Julia land." It reads the four notes (`writeup/notes/`), `writeup/other-languages.md`, `writeup/proposal-definition-checking.md` and the prototype (`TraitWorld/src/trait.jl`, `implement.jl`, `defcheck.jl`), plus the primary sources listed at the end. One short Julia script was run (Julia 1.12, niced); its results are quoted where used.

## Conclusions

1. **The design already has associated types, and Julia already has them too.** Every operation declared `::eltype(R)` uses an associated type function, and `AbstractArray{T, N}` is an associated type carrier: a concrete type has one supertype chain, so `MyArr{Float64, 2} <: AbstractArray{T, N}` holds for exactly one `T` and `N`. That is Rust's "output parameter" discipline, enforced by single inheritance. What the design lacks is a declared, checked form of it.
2. **Rust's and Swift's complexity did not come from having associated types.** It came from reasoning about them symbolically: type-checking a generic body once, against where-clauses, with projections like `<T as Iterator>::Item` as unknown types that must be normalized, equated and solved. Recursion among associated types, higher-ranked bounds, lifetimes and inference made that reasoning undecidable or unsound in corners. Our workers are compiled per concrete representation, where `eltype(Vector{Float64})` is a function call that folds. That part of their experience does not apply to us.
3. **It applies at three places only:** definition checking at archetypes, deciding overlap and family coverage at declaration, and `Dynamic` values with open parameters. At each place a first-order restriction keeps us out of Rust's and Swift's trouble:
   - parameters are variables with trait bounds;
   - equality only through a shared variable;
   - no recursion in trait declarations;
   - no free-form type equations.
4. **Joint parametrization** (`@implement ArrayLike{T, 1} Series{T} where {T}`) is the right form for families. It makes the parameter an output parameter by construction, matches `struct MyArr{T, N} <: AbstractArray{T, N}`, is decidable by subtyping, and supplies what "Results like the input" lacks for `similar(x, Float32)`: a sibling in the same family.
5. **A bound on the representation** (`@trait MyTrait{R <: Hashable}`) is a supertrait with the identity representation map, and the prototype already treats a supertrait that way. A bound on another parameter (`ArrayLike{T <: NumberLike}`) is Swift's `associatedtype Element: Hashable`. Such a bound is what lets definition checking reach code that computes with the parameter.
6. **Recommendation:** adopt output parameters (associated types) now, in first-order form. Defer input parameters (several values per type), associated type constructors beyond "same family, other parameters", and operations whose result is bounded by their own trait outside one family. Forbid recursive parameter bounds, equations between type functions, and free-form predicates in generic implementations. The sentence "every step toward associated types should be weighed against" the complexity table should become "associated types are adopted; symbolic reasoning about them is not."

## 1. What associated types are in our design

### Three kinds of trait parameter

| Kind | Determined by | Rust / Swift / Haskell | In Julia today | In our design today |
|---|---|---|---|---|
| Input parameter | the user of the trait; a type may conform at several values | `From<T>`, `Add<Rhs>`; multi-parameter type classes | multiple dispatch on several arguments | `Callable{A, S}` (a function conforms at several signatures) |
| Output parameter (associated type) | the conformance; one value per type | `Iterator::Item`; Swift `associatedtype`; Haskell associated type families | `AbstractArray{T, N}`'s `T`, `N` through the single supertype | `ArrayLike{T, N}`, `Source{T}`: "the conformance declares them" (design only) |
| Associated type function of `R` | a method on the representation's type | `<R as Trait>::Assoc` as a function; type families | `eltype`, `ndims`, `keytype`, `IndexStyle`, `similar_type` | `Base.getindex(r::R, i::Int)::eltype(R)`, generic predicates `eltype(R) == …` (prototype) |

RFC 195 draws the line between the first two: an input parameter "is used to *determine* which `impl` to use", an output parameter "is uniquely determined *by* the `impl`, but plays no role in selecting the `impl`". `Iterator<A>` was the RFC's example of a parameter that was really an output, which is the source of the notes' "one value per type". The RFC also says associated types "do not increase the expressiveness of traits per se". They are engineering: clients name them through the type (`G::N`) instead of threading them as parameters.

The second and third kinds are one thing in two spellings. An output parameter is a function of the conforming type. `eltype(R)` is a function of the representation that Julia already defines. In our design the conformance maps a user type to one representation, so a parameter is a function of the representation: `Measurements` has `T = Float64` because its projection is a `Vector{Vector{Float64}}`. With named implementations a type can project differently, so precisely the parameter is a function of (type, implementation). That pair travels with the value, as the witness does. "One value per type" therefore becomes **one value per conformance**: per type for membership (`isa`, unnamed), per witness inside workers.

### What the prototype has

- `@trait` accepts only `Name{R}` (`_parse_trait_header`). Parameters besides `R` are design.
- Declared result types are functions of `R`, stored as `op_ret(X, Val(op), R, Val(N))` and evaluated at a concrete `R` (`BaseTraits`: `Base.getindex(r::R, i::Int)::eltype(R)`).
- Generic implementations take an arbitrary predicate, `eltype(R) == Vector{Float64}`, run at each concrete `R` in `_witness`. Two matches throw `_ambiguous_generic` there, at the representation, not at the declaration.
- **At an archetype, these functions fall back.** `eltype(Archetype{X})` is Base's fallback, `Any` (checked: `eltype(Arch) = Any`). So the definition check sees every element as `Any`. Whatever library code does with an element becomes a dynamic call at the archetype, and whether the element supports it is established only per signature. The check is silently weaker exactly where associated types are used.

So the prototype already has associated type functions. It evaluates them correctly at concrete types and erases them at archetypes.

### What Julia land needs them for

- **Arrays.** `T` to allocate `Vector{T}` and accumulate from `zero(T)`; `N` to choose code by dimension (`size(r)::NTuple{N, Int}`). The manual calls the two parameters of `AbstractArray` "very important": "the first defines the eltype, and the second defines the ndims".
- **Iterators.** The item type, for `collect` and for preallocation. Julia's iteration interface defaults `eltype` to `Any`, and `map` over an empty collection takes its element type from inference: the design's one semantic exception. A declared item type, with a declared `Callable` result, gives `map(f::Callable{Tuple{T}, S}, x)` the element type `S` without inference. That narrows the exception.
- **Tables.** The column types, Tables.jl's `schema`: a worker compiled per schema is a worker whose parameter is a `NamedTuple` type.
- **Makie.** Position families `Point{N, Float64}` / `Point{N, Float32}` (`design-findings.md`): `N` chooses 2D or 3D code, and `F` keeps precision until the backend. `PointsLike{N, F}` states exactly that.
- **ODE solvers with automatic differentiation.** `proposal-stored-values.md` §8 names forward-mode differentiation as excluded because it "needs traits with an element-type parameter". The solver must allocate caches of the state's element type, which is `Dual{…}` under ForwardDiff. That needs the parameter `T`, a bound saying what `T` must support, and a constructor at another `T`: `similar(u, T)`.
- **GPU arrays.** The element type (`Float32`), and that `similar` stays on the device. The second is the family, not the element: a constructor that returns a sibling of the same family.
- **Results like the input.** `4-details.md` ends that section with this case: `similar(x, Float32)` turns a `Series{Float64}` into a `Series{Float32}`, which "needs the conformance to cover a family, with the trait's parameters tied to the type's".

The user's claim holds. Without output parameters the design cannot state Base's own interfaces (`AbstractArray`, iteration, `AbstractDict{K, V}`) as contracts. The prototype's `BaseTraits` already reaches for them through `eltype(R)`.

## 2. Does Rust's and Swift's experience apply?

### What caused the complexity there

| Cause | Where | Evidence |
|---|---|---|
| Generic bodies type-checked once, with projections as unknown ("rigid") types that must be normalized | Rust | rustc-dev-guide: an alias is rigid when it "can never be normalized further", and it is rigid or not depending on the caller's where-clauses. In the old solver, "it was a frequent occurrence that normalization calls would be missing", leading to spurious errors. Normalization needs a normalized parameter environment, which itself needs normalizing. |
| Inference variables inside projections (ambiguous aliases) | Rust | normalizing an ambiguous alias yields a fresh inference variable, resolved later (rustc-dev-guide) |
| Equations among associated types and recursion (`SubSequence: Collection`) | Swift | the GenericSignatureBuilder was "slow, with exponential time and memory usage" and dropped requirements. The Requirement Machine is Knuth-Bendix completion, which "terminates with a correct solution or runs forever", cut off by rule-count limits (Pestov 2022). |
| Associated types with parameters plus lifetimes and higher-ranked bounds | Rust GATs | "over six and a half years after the original RFC"; `for<'a> I::Item<'a>: Debug` implies `'static`; not object-safe (GAT stabilization post) |
| Coherence and projections | Rust | relating projections in coherence was "a soundness bug before the new solver"; disjointness by associated types (`Expression<SqlType=VarChar>` vs `SqlType=Text`, RFC PR 1672) postponed "when chalk is up and running" |
| Specialization changing associated types | Rust | Turon: do not specialize associated types (cited in the notes) |
| Existentials of traits with associated types | Rust, Swift | `dyn Iterator<Item = u32>` must fix them; Swift could not use such protocols as types until 2022 |
| Type families in inference | Haskell | non-injectivity makes variables under a family ambiguous; termination conditions or "type-checking may unpredictably diverge" (GHC guide) |

### What applies to us, and why

**Does not apply: compiling and running code.** A worker is compiled per concrete representation. Normalization there is calling `eltype` on a concrete type, which Julia's inference folds to a constant. There is no where-clause environment to normalize, no rigid projection, no inference variable (Julia's types flow forward only), and no unification. A Julia user has always written `eltype(A)` and `similar(A, T)` without a type checker trying to prove anything about them. The cost there was inference-dependent element types, not checker complexity.

**Does not apply: lifetimes, higher-ranked bounds, object safety by vtables.** Julia has no lifetimes. A `Dynamic` dispatches rather than using a table. Most of the GAT story (LendingIterator, implied `'static`, Polonius) is lifetimes.

**Does not apply: inference from parameters.** Rust's input parameters hurt inference (`into()`, `collect::<Vec<_>>`); RFC 195 notes inference cannot find input parameters even from a single impl. We do not infer types backwards. The one-line `@implement` computes parameters from the representation, which is evaluation, not unification. (Swift also infers associated types from the signatures of witnesses, a known source of compiler complexity; that is from memory, unverified here. We should not do it: parameters come from defining equations or are stated.)

**Applies, in miniature: definition checking.** At an archetype a parameter is exactly a rigid projection: an unknown type with only the properties its bound states. Today the prototype answers `Any`. Doing better means building archetypes for parameters, and that is Rust's and Swift's problem in small. It stays small if:
- parameters are named variables, so `a::ArrayLike{T}, b::ArrayLike{T}` shares one archetype and `a::ArrayLike, b::ArrayLike` gets two. Equality is a partition of named variables, union-find on a finite set.
- there are no equations between type functions (`eltype(A) == keytype(B)`) and no nested projections in constraints. Swift's undecidability came from equations closed under recursion (`SubSequence.SubSequence == SubSequence`), which make the set of type terms infinite.
- the graph of parameter bounds among trait declarations is acyclic. `ArrayLike{T <: ArrayLike}` in a trait's declaration is Swift's recursive constraint. `x::ArrayLike{<:ArrayLike{Float64}}` at a use is finite and fine.

Under these restrictions archetype construction is one opaque type per variable, terminates, and needs no solver. A function the checker cannot express this way is checked per signature, as open parameters already are.

**Applies: overlap and family coverage at declaration.** The prototype's predicates (`eltype(R) == Vector{Float64}`) are arbitrary Julia code. Their overlap cannot be decided when a generic implementation is declared, so it surfaces per representation. Restricted to patterns on output parameters (`R <: Indexable{Vector{Float64}}`), disjointness is decidable by type intersection on the parameters, because a parameter is a function of `R`. So `Indexable{Vector{Float64}}` and `Indexable{Vector{Float32}}` never overlap. That is exactly Rust's postponed disjointness-by-associated-types, and we get it because our parameters are functions by construction. Family coverage has the same shape. Checked with Julia 1.12's inference, `getindex` on `MyVec{T} where T` infers `Any`, while at an archetype instance `MyVec{ArchT}` it infers `ArchT`. So families should be checked at archetype instances, not at the `UnionAll`.

**Applies: specialization.** The notes already require a more specific implementation to declare the same parameter values: Turon's fix. With defining equations (`T = eltype(R)`) it holds by construction, since the parameter is a function of `R`, not of the implementation.

**Applies: `Dynamic` with open parameters.** A `Dynamic{ArrayLike}` whose `getindex` returns `eltype(R)` has no declared result type. Rust requires `dyn Iterator<Item = u32>`; Swift added constrained existentials (`any Collection<Int>`, SE-0346/0353). For us: a `Dynamic` fixes every parameter that occurs in a result type of an operation used on it.

**Applies, if adopted: input parameters.** Several values per type bring back coherence on parameters, ambiguity at bounds (`x::Convertible{T}` with `T` open: which?), and Rust's input-parameter pain. Julia rarely needs them, because multiple dispatch already relates several types in one function. Promotion is the canonical case, and it is already open.

## 3. Joint parametrization

```julia
@trait ArrayLike{T, N, R} begin                 # R last, so ArrayLike{Float64} leaves N and R open
    T = eltype(R)                               # defining equations: parameters are functions of R
    N = ndims(R)
    Base.size(r::R)::NTuple{N, Int}
    Base.getindex(r::R, i::Int)::T
end

@implement ArrayLike{T, 1} Vector{T} where {T}           # Base's family, existing methods
struct Series{T}; data::Vector{T}; end
@implement ArrayLike{T, 1} Series{T} where {T}           # one declaration for the family
@implement PointsLike{N, F} Points{N, F} where {N, F <: AbstractFloat}
```

**Semantics.** A family conformance declares, for every instance, one conformance whose parameters are given by the type's parameters. `Series{Float64}` conforms at `ArrayLike{Float64, 1}` and nowhere else, so `T` is an output parameter by construction. The required rule is Rust's E0207 turned into our terms: every variable in the trait's parameters must occur in the conforming type, or be bound through another trait's output parameter (`where {T, R <: ArrayLike{T}}`). `@implement MyTrait{N} MyType where {N}` is refused: `N` would be an input parameter.

**Relation to Rust, Swift and Julia:**
- **Rust.** `impl<const N: usize> MyTrait<N> for MyType<N>` looks the same, but `MyTrait<N>` is an input parameter there, so `impl MyTrait<4> for MyType<3>` could be added beside it. Our equivalent of Rust's output form is `trait MyTrait { const N: usize; }` with `impl<const N: usize> MyTrait for MyType<N> { const N: usize = N; }`. The joint form is that, spelled in the header.
- **Swift.** SE-0346's primary associated types are the closest: `protocol Sequence<Element>` keeps `Element` an associated type and lets `some Sequence<String>` desugar to a same-type requirement. Swift chose this over generic protocols because those lack "a functional dependency between the type parameters like there is with associated types". `ArrayLike{Float64}` in a bound is that sugar.
- **Julia.** `struct MyArr{T, N} <: AbstractArray{T, N}` is the same declaration, made at definition. Joint parametrization is the retroactive version with the same parameter mapping.

**Membership is subtyping, with the mapping.** `Series{Float64} <: ArrayLike{Float64, 1}` is true, `Series{Float64} <: ArrayLike{Float32}` false, and `(Series{T} where T) <: ArrayLike` true. This is what Julia's subtyping already computes for a declared supertype with shared variables. The runtime support the design needs for conformance as an added supertype therefore needs the mapping and nothing more.

**What it buys:**
- one declaration per family, checked once;
- parameters usable in bounds and dispatch: `draw(p::PointsLike{2})`, `draw(p::PointsLike{3})`. Since a parameter is a function of the representation, a worker sees it as a constant;
- the type-changing constructor that "Results like the input" lacks. A constructor operation may return a sibling, a member of the same family at other parameters, and the family's field projection inverts there:

```julia
@trait ArrayLike{T, N, R} begin
    …
    Base.similar(r::R, ::Type{S})::Sibling{R; T = S} where {S}   # a sketch: the same family, element type S
end
halfprec(x::ArrayLike{Float64, 1})::Like{x; T = Float32} = (y = similar(x, Float32); …; y)   # a sketch
halfprec(Series([1.0, 2.0]))     # the worker builds a Vector{Float32}; the entry inverts it to a Series{Float32}
```

  The closure check is one subtyping question: the result at the archetype instance, `similar(::Vector{ArchT}, ::Type{ArchS})`, must be `Vector{ArchS}`, a member of the declared family. That is how a ForwardDiff-capable solver allocates `Dual` caches in the user's array family, and how GPU code stays on the device.

**Pitfalls:**
- **Overlap.** A specific `@implement ArrayLike{Float64, 1} Series{Float64}` beside the family is allowed if it declares the same values, and a different value is refused: two values for one type. Two families overlap where their `UnionAll`s intersect (`typeintersect`), and there their mappings must agree.
- **Parameter expressions.** Allow only the type's variables, constants and type constructors (`ArrayLike{T, 1}`, `Source{Vector{T}}`), never function calls (`ArrayLike{promote_type(T, Float32), 1}`). Then coverage and overlap stay decidable by subtyping.
- **Generic implementations.** A generic implementation's parameters must be bound through its constraints' parameters (`@implement Iterable{T, R} where {T, R <: ArrayLike{T}}`). A generic implementation and a family can both cover `Vector{Float64}`; the existing rule (more specific beats generic, same values) decides.
- **Open parameters at definition checking.** A type parameter with a trait bound gets an archetype. A value parameter (`N::Int`) has no archetype in Julia's type system. Code that only fixes it (`ArrayLike{T, 2}`) is checked at that value; code that leaves it open is checked per signature, as now.
- **The family's own structure.** `struct Weird{T}; data::Vector{Float64}; end` with `@implement ArrayLike{T, 1} Weird{T} where {T}` is refused at the archetype instance: `getindex` returns `Float64`, not `ArchT`. A method specific to one instance (`getindex(::MyVec{Float64}, …)`) is not seen by the archetype check. Every call asserts its result, so "identical or error" still holds.

## 4. Bounding the representation, and other parameters

### `@trait MyTrait{R <: Hashable}`

**Meaning.** Every representation of `MyTrait` conforms to `Hashable`, so library code may call `Hashable`'s operations on a `MyTrait` trait object. In Swift that is `protocol MyTrait: Hashable`; in Rust `trait MyTrait: Hash`, which Rust defines as sugar for `where Self: Hash`. `R` plays `Self`. It is a **supertrait with the identity representation map**, not an associated-type bound.

**The prototype already does this.** `_check_implementation` refuses "`R` implements `X` but not its supertrait `S`", and the views of a supertrait share the representation. The header bound is therefore syntax for what `@trait MyTrait{R} <: Hashable` means today. It names the representation map, an open point of the notes, for its commonest case: the identity.

**The difference that remains.** A user type may also conform to `Hashable` by its own, different projection. Then `x isa Hashable` is true by its own conformance, and at a `Hashable` bound the caller projects by that one (rule 2, two views). Inside a `MyTrait` worker, `hash(t)` uses the representation's `Hashable`. Both are as the notes already state for supertraits.

**Julian reading.** `abstract type MyTrait{R <: Hashable}` is Julia's syntax for a bounded type parameter, and with traits as abstract types, `R <: Hashable` reads as conformance. Julia checks the bound when the type is formed (checked: `MyTrait{Int}` raises "expected R<:Hashable"). So a conformance to `Hashable` must exist before `MyTrait{R}` is named for that `R`. Declaration order already requires that.

**Archetypes.** `archetype_tobj` already gives a bound's supertraits views of the same archetype (`_arch_traits`), so the archetype of `MyTrait` is an archetype of `Hashable` without change.

**Dynamic values.** `Dynamic{MyTrait}` dispatches `Hashable`'s operations too, and converts to `Dynamic{Hashable}` through the identity map. Its `hash` and `==` can come from `Hashable` (the notes' "the trait's declared `==` decides"), so `Dynamic{MyTrait}` keys a `Dict`.

**Generic implementations.** A generic implementation of `MyTrait` must entail `Hashable` from its constraints. Decide this syntactically, through the constraints' supertrait closure, and never by searching generic implementations: that search is Horn-clause resolution, Rust's trait solver. Concrete representations are still checked as now.

### Bounds on the other parameters

`ArrayLike{T <: NumberLike, N}`, or at a use `x::ArrayLike{T} where {T <: NumberLike}`, is Swift's `associatedtype Element: Hashable` and Rust's `where T::Item: Num`. It is what makes code that computes with a parameter checkable at its definition:

```julia
@trait NumberLike{T} begin                       # homogeneous in T: no promotion across representations
    Base.zero(::Type{T})::T
    Base.:+(a::T, b::T)::T
    Base.:*(a::Float64, b::T)::T
end

function total(x::ArrayLike{T, 1}) where {T <: NumberLike}
    s = zero(T)
    for i in 1:length(x); s += x[i]; end        # checked at archetypes: x[i]::ArchT, + and zero from NumberLike
    s
end
```

- **Numbers are their own representations.** `NumberLike` is a bound on an element type, which is never projected. Its operations are homogeneous in `T`, with fixed concrete partners like `Float64`. So it does not touch the open question of numeric traits across representations (promotion), and "numbers need no trait" stays true for values. Base's numbers conform through the Base wrapper, and `Dual{…}` through ForwardDiff's wrapper as a family.
- **Abstract-type bounds** (`T <: Real`) cannot have archetypes: an archetype `ArchT <: Real` reaches Base's `promote` fallbacks and fails spuriously. Such methods stay checked per signature. That is the precise sense in which abstract types are not traits.
- **Unbounded parameters** could get an archetype with no operations, which would check parametric code (store, pass, compare by `===`) and report "`+` has no method for the open parameter `T`; add a bound". The user adopted deferral for open parameters ("pragmatic and sensible"), so this is offered as an opt-in strictness, not a change.

## 5. Recommendation

### Adopt now

1. **Parameters are output parameters (associated types).** A trait's parameters other than `R` are functions of the representation, one value per conformance. Write them `@trait ArrayLike{T, N, R}`, `R` last as in `Source{T, R}`, so that Julia's partial application makes `ArrayLike{Float64}` leave `N` and `R` open.
2. **Defining equations.** A trait may define a parameter by an existing type function, `T = eltype(R)`. A conformance then states it or not; if stated, it is checked against the equation. Without an equation the conformance must state it. Operation declarations use the parameter names (`::T`), and a type function in a result type that is not a declared parameter is refused, so archetypes always know what to answer.
3. **Bounds on parameters** by traits (`T <: NumberLike`) or by Julia types (`T <: Real`), checked at the conformance at the concrete value.
4. **Bounds on `R`** as the header form of a supertrait with the identity map.
5. **Joint parametrization for families**, with every variable of the trait's parameters occurring in the type or bound through a constraint's parameter, and parameter expressions limited to variables, constants and type constructors.
6. **Generic implementation predicates as parameter patterns.** `@implement ColTable{R} where {R <: Indexable{Vector{Float64}}}` replaces `eltype(R) == Vector{Float64}`, so overlap between generic implementations is decided at their declaration.
7. **Constructor operations returning a sibling** in the same family at other parameters, closure checked at archetype instances. This is the "changing the representation's type" case of "Results like the input".
8. **`Dynamic` of a parametric trait** fixes every parameter that occurs in a result type of its operations.

### Defer

- **Input parameters** (a type conforming at several values). `Callable` stays the only such trait; promotion stays open.
- **Associated type constructors** beyond "the same family at other parameters", such as `similar` returning another family. These are GATs; the family form covers `similar`, ForwardDiff and GPU arrays.
- **An operation whose result is bounded by its own trait outside one family** (Swift's `SubSequence`, Julia's `view`). Base's views reach a fixpoint after one step, so a conformance for `SubArray` can be declared separately; the general rule waits.
- **Erasing open parameters of a `Dynamic` to their bounds** (Swift's covariant erasure).
- **Strict mode for unbounded parameters** (archetypes with no operations).

### Forbid

- Recursive parameter bounds in trait declarations: the graph of traits named in parameter bounds is acyclic.
- Equations between type functions and nested projections in constraints. Equality is only by a shared variable or a fixed value.
- A more specific implementation declaring other parameter values (already a rule).
- Function calls in the parameters of a family conformance or a generic implementation's patterns.

### How definition checking extends

- **The archetype carries its parameters.** `Archetype{X, P}` with `P` a named tuple of parameter archetypes or fixed values. Each defining equation gets a method on the archetype: `eltype(::Type{Archetype{ArrayLike, P}}) = P.T`. This replaces today's silent `Any`.
- **One parameter archetype per variable** of the method's signature, shared where the signature shares the variable. A parameter bounded by a trait gets an archetype that is a representation archetype of that trait. It is its own representation, so `+(a::ArchT, b::ArchT)::ArchT` comes from `NumberLike`.
- **Checked per signature, as today:** fixed values are used as they are. Value parameters left open, parameters bounded only by abstract types, and unbounded parameters are checked per signature.
- **Families at declaration** are checked at an archetype instance (`Series{ArchT}`), which inference handles precisely where the `UnionAll` gives `Any`.

## Proposed text changes

For `4-details.md`, "Declaring a trait", replacing the paragraph **Parameters**:

> **Parameters.** A trait may take parameters besides the representation, as `AbstractArray{T, N}` does: `@trait ArrayLike{T, N, R}`, the representation last.
> - **They are associated types:** functions of the representation, one value per conformance. A type conforms at one value of each, as a Julia type has one `AbstractArray` supertype.
> - **A trait may define them** by a type function, `T = eltype(R)`. The conformance then states them or not, and a stated value is checked against the definition. Without a definition the conformance states them, `@implement ArrayLike{Float64, 1} MyVector`.
> - **Operations name them,** `Base.getindex(r::R, i::Int)::T`.
> - **A parameter may be bounded** by a trait or a type, `ArrayLike{T <: NumberLike, N}`, checked at the conformance.
> - **A bound may fix them or leave them open,** `x::ArrayLike{Float64}`. A shared variable, `f(a::ArrayLike{T}, b::ArrayLike{T}) where {T}`, requires equal values.
> - **A bound on the representation,** `@trait MyTrait{R <: Hashable}`, is a supertrait whose representation map is the identity.
> - **Not offered:** a type conforming at several values of a parameter, equations between type functions, a trait's parameter bound that names the trait again.

"Generic implementations": replace the predicate example by `where {R <: Indexable{Vector{Float64}}}`, and add: "Predicates are patterns on the constraints' parameters, so overlap between generic implementations is decided when they are declared."

"Parametric user types": add the joint form, `@implement ArrayLike{T, 1} Series{T} where {T}`, with these rules:
- every variable of the trait's parameters occurs in the type;
- parameter expressions are variables, constants and type constructors;
- the family is checked at an archetype instance.

"Results like the input": replace "It is being explored" with the sibling constructor and a pointer to "Parametric user types".

"Definition checking": the archetype carries archetypes for its parameters, one per variable, built from the parameters' trait bounds. The deferred list gets "a parameter left open whose bound is not a trait".

"Dynamic values": add "a `Dynamic` of a parametric trait fixes the parameters its operations' result types use".

"Open points": replace "Whether a type may conform at several values of a trait parameter" with "Input parameters (several values per type), associated type constructors beyond a family, and results bounded by their own trait (`view`)".

For `2-design-choices.md` §10, replace the last two sentences:

> Associated types are not the expensive part; reasoning about them symbolically is. Rust and Swift check a generic body once against its where-clauses, so an associated type is an unknown to normalize, equate and solve for, and recursion among them makes that undecidable. Our workers compile per concrete representation, where an associated type is a type function evaluated on a concrete type. Only definition checking reasons about them symbolically, and there they are first order: named variables with trait bounds, equal only through a shared variable, never recursive. Parameters are associated types, one value per conformance, as Rust's RFC 195 argued.

And in the predictions table, row 12: "kept out: symbolic reasoning about associated types; associated types themselves adopted in first-order form."

## Sources opened

- Rust RFC 195, associated items: https://rust-lang.github.io/rfcs/0195-associated-items.html
- rustc-dev-guide, aliases and normalization: https://rustc-dev-guide.rust-lang.org/normalization.html
- Trait system refactor initiative (2023): https://blog.rust-lang.org/inside-rust/2023/07/17/trait-system-refactor-initiative/
- GAT stabilization (2022): https://blog.rust-lang.org/2022/10/28/gats-stabilization/
- Rust RFC PR 1672, disjointness based on associated types: https://github.com/rust-lang/rfcs/pull/1672
- Rust error E0207, unconstrained impl parameters: https://doc.rust-lang.org/error_codes/E0207.html
- Swift, the Requirement Machine (Pestov 2022): https://forums.swift.org/t/the-requirement-machine-a-new-generics-implementation-based-on-term-rewriting/55601
- Swift Generics Manifesto: https://github.com/swiftlang/swift/blob/main/docs/GenericsManifesto.md
- Swift SE-0346, primary associated types: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0346-light-weight-same-type-syntax.md
- GHC user's guide, type families: https://ghc.gitlab.haskell.org/ghc/doc/users_guide/exts/type_families.html
- Julia manual, interfaces: https://docs.julialang.org/en/v1/manual/interfaces/
- Turon on specialization, SE-0309/0353: cited via `writeup/other-languages.md`, not reopened.
