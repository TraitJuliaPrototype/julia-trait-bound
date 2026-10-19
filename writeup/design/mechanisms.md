# The mechanisms in detail

The rules and mechanisms of the trait language, in more detail than [`../design.md`](../design.md) gives them, for core developers, as of 2026-10-19 (session 29).
Where this document and `design.md` disagree, `design.md` wins.

**Sources.** This document is taken from `notes/4-details.md` (moving to `attic/writeup/notes-2026-10-18/`), checked against `design.md` and the prototype (TraitWorld 375a930). Each section says what the prototype runs. "Design" means decided and not built. The register with history is [`../decisions.md`](../decisions.md).

**Terms.** The glossary is [`design.md` §1](../design.md#1-terms): owner, stakeholder, pirate, fact, run-time site, trait, conformance, implementing type, key, trait object, entry and worker, trait module. Terms used only here are defined where they first appear.

**Syntax.** The examples use the syntax of the design, which TraitWorld accepts (`TraitWorld/test/keys_syntax.jl`). Some of the prototype's older tests still use an earlier spelling, with the implementing type as the trait's last parameter (`@trait ColTable{R}`, `ncols(r::R)`). That spelling is to be deleted (`design.md` §9.2).

## Contents

1. Declaring a trait
2. How a type conforms
3. Generic implementations
4. Named implementations (deferred)
5. Several traits on one object
6. Parametric user types and families
7. Traits as abstract types, and dispatch
8. Inside a trait module
9. Definition checking at archetypes
10. `Callable` and its two modes
11. Keyword, default and variable arguments
12. Functions that cross the boundary
13. Results like the input
14. Types that only convert
15. `Dynamic` values, as built
16. The trait object's layout
17. Caching per key
18. AOT
19. Identical or error

---

## 1. Declaring a trait

```julia
@trait ColTable begin
    ncols(t::ColTable)::Int                              # an operation: argument types, a result type
    col(t::ColTable, i::Int)::Vector{Float64}
    firstcol(t::ColTable)::Vector{Float64} = col(t, 1)   # a default, written over the other operations
end
```

### Operations

- An **operation** is a generic function declared at the trait. Its first argument is the trait itself, as `length(x::AbstractArray)` is declared at an abstract type.
- A conformance implements it with methods for the implementing type.
- Every call on a trait object is checked:
  - the arguments against the declaration;
  - the result asserted to the declared type.
- An operation may be an existing generic function, such as `Base.length` or `Base.iterate`. The prototype's capability traits do this (`HasLength`, `Iterable`, `Indexable` in `TraitWorld/test/runtests.jl`).
- An operation may mutate its argument. The trait object refers to the user's object, so the user sees the change, as in plain Julia.

### Defaults

- A **default** is an operation's body written in the trait, in terms of the other operations and the declared fields.
- A conformance may override it with its own method.
- A default never throws "not implemented". A missing operation is an error at the conformance, not at a call.
- **Defaults over fields are how record-like traits share code.** A conformance that keeps every default has no implementing type. Its key is then its declared fields' types alone. Every conforming type with fields of those types runs one worker, compiled in the library's image.
- A type that overrides an operation becomes the implementing type. That code compiles once for it, in its own image ([`design.md` §4.2](../design.md#42-compiled-for-what-the-bound-can-see): not "once for any type").
- **An override belongs to the conformance** ([`design.md` §4.4](../design.md#44-overrides-belong-to-the-conformance)). Which operations a default serves is fixed at the declaration. A later method that would change it is refused, naming the fix: define the method before `@implement`, or inside its block, and restart.
  - *Why refused, not followed.* The override would change the key, since a type that keeps every default shares a worker with every type of the same field types. Values already kept as `Dynamic` hold trait objects of the old key. Recompiling cannot repair either. This is why Julia long refused to redefine a struct.
  - *At load.* An image that brings such an override for an active conformance is refused too. So the order matters where plain Julia's does not: a supertype owner's method (`op(::AbstractSample)`, no pirate) is part of a conformance declared after it and refused for one declared before it.
  - *Interactively:* a restart until conformance redeclaration is built.
  - *Prototype:* refused at the definition, through Julia piece 1's definition hook (`TraitWorld/test/keys_syntax.jl`, "late overrides for family members").

### Fields

A trait may declare fields, as a struct does.

```julia
@trait Integrator{U, P} begin
    u::U              # the state: readable and writable; its type defines U
    @const p::P       # the parameters: read-only
    t::Float64        # the time: writable, a fixed type
end
```

- **A field is a pair of operations.** `t.name` is `getproperty(t, :name)` and `t.name = x` is `setproperty!(t, :name, x)`, as everywhere in Julia. Scala desugars a trait's `var` the same way; Swift's protocols require properties `{ get set }`.
- **Writable unless `@const`.** `@const` is the macro form of a struct's `const`, which Julia parses only inside a struct.
- **A declared field is a stored field of the conforming type.** It has the same name unless the conformance maps it (`name => label`). It is read at its byte offset, never through `getproperty`.
- **A type with its own `getproperty`** conforms only with every declared field mapped explicitly. The mapping says that plain `x.name` may differ from `t.name`.
- **Computed properties are not declared fields.** A type whose data needs computing converts (section 14).
- **A writable field needs:**
  - a mutable conforming type;
  - the stored field not `const`;
  - the stored field typed exactly as in the key, so a write never changes a type compiled code relies on.
- **Field types are part of the key.** A worker compiles per state type, whatever else the conforming type holds.
- **Field access is narrowed, not opened.** Code may read and write the fields its traits declare and no others.
- **New over Julia.** Abstract types cannot require fields today. A trait can, because conformance is declared and checked.
- *Prototype:* all of the above (`test/fields.jl`, `test/keys_syntax.jl`). A refused field names itself: `KFrozen`, an immutable type conforming to `KInteg` with a writable `t`, fails with "cannot be written".

### Associated types

A trait's parameters are its **associated types**: one value per conformance, a function of what the conforming type holds. A type conforms at one value of each, as a Julia type has one `AbstractArray` supertype.

```julia
@trait KVec{T} begin
    T = eltype(Self)                 # defined by an equation of the implementing type
    klen(v::KVec)::Int
    kget(v::KVec{T}, i::Int)::T      # operations name the parameter
end
```

- **Defined by a field:** the field's declared type is matched against the stored field's type, as Julia matches a `where` clause. `data::Vector{T}` against a `Vector{Float64}` field gives `T = Float64`. A stored type that does not match is refused at the conformance.
- **Defined by an equation** of `Self`, the implementing type: `T = eltype(Self)`. The conformance then need not state the value; a stated value is checked.
- **Stated by the conformance** when neither defines it: `@implement ArrayLike{Float32, 1} MyVec`.
- **Never both a field and an equation.** That would be an equation between type functions. The prototype refuses it ("defined by the field").
- **Bounded** by a trait or a type: `ArrayLike{T <: NumberLike, N}`, checked at the conformance. A trait bound lets definition checking cover code that computes with the parameter.
- **A bound may fix them or leave them open:** `x::ArrayLike{Float64}`. A shared variable, `f(a::ArrayLike{T}, b::ArrayLike{T}) where {T}`, requires equal values.
- **Not offered** (these made Rust's and Swift's checking hard or undecidable; [`comparison.md`](comparison.md) §7):
  - a type conforming at several values of a parameter ("input parameters"; `Callable` is the one trait that has them);
  - equations between type functions;
  - a parameter bound that names its own trait.

### Supertraits and bundles

- `@trait B <: A` makes `A`'s operations and fields part of `B`'s. Example: `@trait DGrow{T} <: DCol` in `test/dynamic.jl`.
- A type's conformance to `B` must agree with its conformance to `A`: the same forwarding field, or both implemented, with the fields mapped alike. *Design:* the prototype does not check agreement (`decisions.md`, Keys).
- A **bundle** names a combination on the library side, `@trait Table <: (ColTable, RowTable)`, so that `summary(t::Table)` needs one bound. *Prototype:* yes (`Table2` in `runtests.jl`).

### Concreteness

- By default a key may be abstract, silently ([`design.md` §4.3](../design.md#43-concreteness-opt-in-per-trait)).
- A trait asks for more in its body. The design has **one declaration with three levels:** silent, warn, error. *Prototype spelling, today:*
  - `@warn_on_abstract` in a trait's body: a conformance with an abstract key warns;
  - `@concrete_only` in a trait's body: such a conformance is refused, and so is a family member at an abstract parameter, at the entry;
  - `@warn_on_abstract` or `@error_on_abstract` before `@trait_module`: concrete mode for the module's workers (section 9).
- *Concrete* means a concrete type with concrete parameters all the way down. Fields the trait does not declare are not looked at, since the code compiled for the key never reads them.
- A trait decides this when it is published. Requiring it later breaks conformers whose key is abstract, as adding an operation without a default does.
- **An abstract part of a key behaves like a dynamic value.** A type that forwards to a field declared `AbstractVector{Float64}` gets one worker for that key, whatever the field holds. Operations on that part dispatch at run time inside it. Passed on to another bounded function, the part is opened there by its run-time type, and that function runs compiled for it: a function barrier the author need not write.

## 2. How a type conforms

Every form is an explicit declaration for the type it names. Every form defines methods, so ownership ([`design.md` §5](../design.md#5-the-three-rules), rule 2) says who may write it: a stakeholder, the trait's owner or the type's owner.

```julia
# 1. Forwarding, inferred: the one field whose type implements the trait, else the field named `data`
struct KMeas; label::String; data::Vector{Vector{Float64}}; end
@implement KTable KMeas

# 2. The type implements the operations itself (methods defined before the declaration)
kncols(r::KRamp) = r.n
kcol(r::KRamp, i::Int) = r.base .* i
@implement KTable KRamp

# 3. Forwarding written out (two fields conform); a declared field mapped to another name
@implement KTable KHalves by right
@implement Named Halves name => title          # Named declares `@const name::String`

# 4. The operations in one block: an implementation and its declaration together
@implement KTable Vector{Vector{Float64}} begin
    kncols(t) = length(t)
    kcol(t, i) = t[i]
    kwith(t, cs) = cs
end

# 5. Several traits at once, forwarded to one field
@implement (ColTable, RowTable) Grid by data

# 6. Existing methods declared for a family: no body
@implement Indexable A where {A <: AbstractVector}
```

| Form | Compiled anew | Operation calls |
|---|---|---|
| forwarding (1, 3, 5) | the field read; the library's code for the field's type already exists | static: the field type's implementation |
| the type implements the operations (2, 4) | the library's functions, once for the type | static, direct |
| a family declaration (6) | nothing | the existing methods, static |

**Checks, all at the declaration, never at a call:**
- **Ownership:** the author is a stakeholder, or an extension of one.
- **Completeness:** every operation has a method or a default for the implementing type. Every declared field maps to a stored field with the declared type. Writable fields obey the rules of section 1. The forwarding field is not a writable declared field.
- **Concreteness,** for a trait that asks for it: the key is concrete, whether it is the type itself, the forwarding field's type, or a declared field's type. An abstract field is refused with its name.
- **Precedence:** methods win over a field when a type has both, so writing operations is always deliberate. Several conforming fields need the field named `data`, or `by`.
- **Forwarding does not chain.** A field whose type itself forwards is not an implementing type (prototype: refused, `runtests.jl` "the one-line conformance").
- **No computed projections.** A conformance that computes a value from the type (`project(r) = …`) is refused with "computes a value" (`test/like.jl`). This is the removed representation design; see section 14 for its replacement.
- **Redeclaration** in a session is refused, naming the reason (section 1, overrides).

**Implementation and conformance are separate.**
- An *implementation* gives the operations for a type.
- A *conformance* says how a type joins the trait, fields included.
- A type that implements the operations need not have the declared fields. It then does not conform, but it can be the forwarding field of a type that does. `Vector{Vector{Float64}}` implements `ColTable`; if `ColTable` declared a field `name`, a bare vector would not conform, and a `Measurements` holding one and a name would.

**Dynamic operations, a form the prototype still has.** `@implement X T dynamic by f begin … end` gives a type operations of its own on its field, called through pointers, so the library's worker for the field's type serves it. On the prototype it cost 6.3 ns per operation, 7× plain Julia per element (`design-findings.md`, before session 29). `design.md` does not mention this form. Its pointers belong to a session, so it is not in a closed world (section 18). Whether it stays is open.

## 3. Generic implementations

An implementation may cover every type that implements other traits. Workers are still compiled per concrete key, so calls stay static.

```julia
# every Indexable type whose elements are Vector{Float64} (prototype: GTable in runtests.jl, earlier spelling)
@implement GTable R where {R: Indexable, eltype(R) == Vector{Float64}} begin
    gn(r) = length(r)
    gcol(r, i) = r[i]
end
```

With this, `Vector{Vector{Float64}}` is a `GTable` because it is `Indexable`, and so is any type a user makes `Indexable`.

- **Membership.** A generic implementation makes its types members only for a trait without declared fields. A trait with fields needs each type's own declaration, which maps them.
- **Forwarding carries through.** A user type that forwards `Indexable` to a field forwards `GTable` to the same field. The key stays the field's type, so the library's code for it is shared. *Untested in the prototype.*
- **Overlap:**
  - a more specific implementation beats a generic one (*prototype:* yes, `GTable` at `Matrix{Float64}`);
  - a more specific implementation must declare the same parameter values as the generic one, so the choice never changes a type;
  - two generic implementations that overlap with neither more specific are rejected;
  - an overlap the later package cannot see, as when a trait's owner adds a generic implementation in a later version, surfaces where a call meets both.
  - *The last three are design; the prototype has no overlap check.*
- **Predicates.** The notes required predicates to be patterns on the constraints' parameters, never conditions computed by functions, so that overlap is decidable at the declaration. The prototype's test uses `eltype(R) == Vector{Float64}`, a computed condition. This is a disagreement to settle when the overlap check is built.

## 4. Named implementations (deferred)

- A named implementation would be used only where a caller names it (`via(Fast, m)`), and anyone could write one.
- **Deferred** until traits are in the type system (Julia piece 7; [`design.md` §4.7](../design.md#47-the-rest-of-the-trait-language), decision of session 29). The simplest `Dynamic`, and membership as subtyping, have no place for a witness inside the value.
- **The preferred form, when it comes,** is a value-level wrapper that conforms, a newtype: `Via{Fast}(x)`.
- **Until then,** a foreign trait for a foreign type needs its owner, the type's owner, or a newtype.
- *Prototype:* none.

## 5. Several traits on one object

A type can conform to several traits, each through its own field or its own methods. A function bounded by several receives one trait object with a **view** per trait. A view is the part of a trait object for one trait: where the implementing value and the declared fields are (section 16).

```julia
normalize!(t::(ColTable, ColStore), i::Int) = (c = col(t, i); setcol!(t, i, c ./ sum(c)); nothing)
@implement ColTable Sep3 by cols                 # each trait through its own field
@implement RowTable Sep3 by rows
@implement (ColTable, ColStore) Live3 by cols    # both through one field
```

- Every view reads the same user's object. The views always agree, and a write through one is seen by the others.
- Workers compile per tuple of the views' keys.
- A trait object is passed on statically to a function with any of its bounds.
- A function that uses a value under two traits, itself or through what it calls, declares both bounds at its boundary. The entry then translates the caller's one value once per bound.
- *Prototype:* yes (`runtests.jl`, "views and joint projections").

## 6. Parametric user types and families

A parametric type conforms as a **family** (all its instances, declared with `where`) or per instance.

```julia
struct S2{P}; p::P; k::Int; end
nf2(s::S2) = s.k
@implement Fam2 S2{P} where {P}                    # the family

@implement StateVector{T} Series{T} where {T}      # joint: the trait's parameter tied to the type's
@implement KVec A where {A <: Vector{<:Real}} begin … end   # a family with an implementation block
```

- **Checks, at the declaration, for the family as a whole:**
  - forwarding: the family of field types must be covered by one implementation's family, which subtyping decides;
  - methods: they must cover the family, with results that infer to the declared types;
  - concreteness, for a trait that asks for it: field types may depend on the parameters but are abstract in no other way. An instance at an abstract parameter, `S2{Any}`, is refused at the entry (*prototype:* `TraitBoundError`, `keys_syntax.jl` "Concreteness");
  - a refusal names the instances that would conform.
- **Joint families with associated types:**
  - each member conforms at one value, so the parameters stay associated types;
  - every variable of the trait's parameters occurs in the type (Rust's rule E0207);
  - parameter expressions are variables, constants and type constructors, never function calls;
  - the family is checked at an archetype instance, `Series{ArchT}`, because inference at the family's `UnionAll` gives `Any`.
- **A member's conformance is fixed at its first use,** not at the family's declaration ([`design.md` §4.4](../design.md#44-overrides-belong-to-the-conformance)). The owner of a member's parameter type is a stakeholder of the member's methods and may define them after the family was declared upstream. A method defined before the member's first use is the member's own; one defined after is refused. *Prototype:* yes (`keys_syntax.jl`, "late overrides for family members").
- Workers compile per instance. `verify_main` enumerates the instances a program passes.
- **A family member's builder** (what makes its trait object) is kept in a registry of the declaring module and saved with its image (decision of session 27).
- *Prototype limit:* forwarding for a whole family is not built. `test/like.jl` declares `LSeries{Float64}` and `LSeries{Float32}` one by one ("forwarding for the whole family: not yet").

## 7. Traits as abstract types, and dispatch

### Where a trait's name stands

- **In an argument,** `t::ColTable` is a bound: translated at the entry, compiled per key.
- **In a field or a container,** a trait's name means its `Dynamic`, as an abstract type's name there means a boxed value. `hooks::Vector{Hook}` is a `Vector{Dynamic{Hook}}` (*prototype:* inside trait modules, in fields, function bodies and argument types; `test/dynamic.jl`).
- **`Vector{<:ColTable}`** in an argument would be a vector whose elements share one key. How a user's vector is passed is open.
- **Membership is subtyping, later.** `x isa ColTable` and `T <: ColTable` need traits in the type system (piece 7). A conformance then adds a supertype after the type is defined. That is sound because only a stakeholder declares it. *Prototype:* `conforms(T, X)` stands in.
- **Numbers need no trait.** Base's `Number`, `Real` and `Integer` stay. Numbers are ordinary values, and promotion runs on concrete types in Base.

### Dispatch: types first, then traits

- **A trait bound ranks above `Any` and below every type** of the other kind, concrete or abstract.
  - A value of a type caught by a type-annotated method takes that method and is not translated.
  - A value that conforms to none of the bounds reaches the most specific ordinary method that applies.
  - This lets a library adopt traits one function at a time.
- **Among bounds:**
  - a subtrait beats its supertrait, and more bounds beat fewer;
  - two methods with unrelated bounds on one position (`f(t::ColTable)`, `f(t::RowTable)`) need a method for both, `f(t::(ColTable, RowTable))`. This is checked when the function is defined. It needs only the function's own methods, so no later load can create the ambiguity.
- **How the prototype does it.**
  - The **entry** is an ordinary method with its bounded positions untyped and `@nospecialize`. It is inlined into typed callers.
  - It finds the trait object through `conformance(As{X}(), u)`, a method per conforming type, declared `@max_methods 1` with a fallback that finds generic implementations and families. A new conformance therefore invalidates no compiled entry.
  - An untyped method of the same shape becomes the entry's **fallback**, called when the argument conforms to none of the bounds.
  - An entry is a method at `Any`, so only the function's owner may add one.
  - An entry is a **boundary**: compiled in its caller's mode, plain or facts (`Expr(:meta, :facts, 0)`; [`julia-changes.md`](julia-changes.md) §1). So a plain caller inlines the entry plainly, and the worker it calls is compiled by facts.
  - *Tests:* `runtests.jl`, "dispatch: types first, then traits" (`describe([1.0 2.0])` takes the `AbstractMatrix` method although `Matrix{Float64}` is a `ColTable`), and "M4: dispatch".

## 8. Inside a trait module

A **trait module** is declared `@trait_module module M … end`. It sets Julia's facts option for its methods (part B). Its code reaches a trait object only through the trait's operations and fields.

- **Exported functions are the boundary.** Their bounds say what a caller's value must conform to.
- **Internal functions need no bounds.** A trait object passed to one is inferred like any argument and compiled as part of the worker that calls it. Definition checking follows it through (section 9).
- An exported argument without a bound takes the value at its own type, as plain Julia does.

| In a trait module | Allowed | Why |
|---|---|---|
| the trait's operations on a trait object; its declared fields, written unless `@const` | yes | the way to reach the user's data |
| several trait objects in one function, of one trait or several | yes | compiled per tuple of keys |
| an argument with several bounds, `t::(ColTable, RowTable)` | yes | one view per bound |
| type-annotated methods beside bounded ones | yes | types first, then traits |
| calling a `Callable` argument | yes | checked at every call (section 10) |
| any code on ordinary values; calling any Julia code: Base, CSV, Cairo, ForwardDiff | yes | rule 1: facts at fact signatures, run-time sites elsewhere |
| a trait object kept beyond the call, as a `Dynamic{X}` | yes | section 15 |
| a trait object passed where a different trait is expected | no | declare both bounds |
| a trait object as a bare value: to an ordinary function, stored or returned bare, `typeof(t)`, an undeclared field | no | code must not depend on the user's type |
| two methods with unrelated bounds on one position and no method for both | no | ambiguous for a type with both |
| arguments of abstract types from plain callers (`Any`, `Vector{Any}`) | yes | their uses are run-time sites; concrete mode reports them |

**A disagreement on pirates.** The prototype refuses any pirate defined in a trait module when the module is defined (`OwnershipError`, `runtests.jl` "ownership"). `design.md` (session 29) states the rule as strict mode's refusal of a *winning* pirate, plus a lint ([`decisions.md`](../decisions.md), "Three rules, not four"). The prototype's check is stricter than the design.

## 9. Definition checking at archetypes

Library code is checked once, where it is defined, for every type that will ever conform.

- **Why one check suffices.** A trait object has no methods but its traits' operations and fields, and every operation declares its result type. So a worker's code is the same for every key, except for the operations' implementations, which are checked at their conformance.
- **How.** Each bounded method is inferred once at **archetypes**: a stand-in key per bound, whose operations and fields return values of their declared types and nothing more (C++0x's term). Parameters get archetypes too, built from their bounds; a defining equation (`T = eltype(Self)`) gets archetype methods.
- **A mistake is reported at its line before any type conforms:**

  ```julia
  spread(t::ColTable) = size(t)    # `size` has no method for a trait object carrying ColTable
  leak(t::ColTable) = typeof(t)    # code must not depend on the user's type
  ```
- **When:** at the trait module's end, an error at the package's build. For trait code defined at the prompt, a warning; the call raises it again (decision of session 27).
- **Checked per signature instead,** at a worker's first call:
  - a parameter left open whose bound is not a trait (`x::ArrayLike{T}` with `T` free);
  - a `Callable` with an open result type;
  - concrete mode's findings for a trait that does not require concreteness.
- **Concrete mode and the fully-typed certificate.** `fully_typed(f, argtypes)` walks what the code runs and reports run-time sites on normal paths, with hints. Operations on `Dynamic` values count as declared sites. A module under `@warn_on_abstract` warns at a worker's first run; under `@error_on_abstract` it raises `AbstractTypeError` (an abstract value used) or `NotFullyTypedError` (a run-time site) ([`design.md` §3.4](../design.md#34-step-4-traits-say-what-code-needs-which-makes-the-facts-rule-cheap-and-can-enforce-concreteness)). A report names the root cause through any number of layers, for example "field `scale` of `CBottom.Config` is declared `Real`".
- *Prototype:* `src/defcheck.jl`, `src/certificate.jl`. The checks run on Julia's native interpreter with a cache owner of their own (session 29). The prototype still defers keyword, vararg and every `Callable` worker to the first call, where the design defers only open result types. The cold-session cost measured before session 29 was under 200 ms for a library of five functions.

## 10. `Callable` and its two modes

Julia has no type for "a function from `Float64` to `Float64`". A function handed down from plain code enters only at a declared signature: `Callable{A, S, M}`, arguments of the tuple type `A`, a result of type `S`, mode `M` ([`design.md` §4.6](../design.md#46-functions-as-arguments-callable-two-modes)).

```julia
# the library's default: a dynamic call, the worker compiled once per signature
colmap(f::Callable{Tuple{Float64}, Float64}, t::ColTable, i::Int) = map(f, col(t, i))
# the library's default: a compiled call, a worker per function type
colsum(f::Callable{Tuple{Float64}, Float64, CompiledCall}, t::ColTable, i::Int) = sum(f, col(t, i))

colmap(x -> 2x, m, 1)                  # dynamic: the library's default
colmap(compiled_call(x -> 2x), m, 1)   # the caller overrides
colsum(dynamic_call(x -> 2x), m, 1)    # the caller overrides the other way
colsum(abs2, m, 1)                     # Base's function: called directly whatever the default
```

- **Anything callable conforms:** closures, callable structs, generic functions. `Callable` is the one trait whose conformance is not declared. That is sound because its one operation is checked at every call:
  - the arguments have the declared types;
  - a result of another type is an error where plain Julia would widen (prototype: `TypeError`);
  - a function without a method for `A` raises `MethodError` when called, as in plain Julia.
- **`DynamicCall`,** the default: the function becomes a pointer to its code compiled for `A` (FunctionWrappers' technique). The worker is compiled once per signature, in the library's image. Each call is indirect, about 4 ns.
- **`CompiledCall`:** the worker is compiled per function type, with the function inferred into it, and the signature still checked. This is what an ODE right-hand side needs: plain Julia's speed with a typed contract. An unbounded argument would specialize but check nothing.
- **The library sets the default, the caller decides per value.** `compiled_call(f)` and `dynamic_call(f)` are wrappers whose type fixes the mode; the entry strips them. `Callable{A, S, M}(f)` also fixes the signature. A bound without `M` accepts either and supplies `DynamicCall`.
- **The mode is a choice of speed, never of correctness.**
- **Functions from trait code are called directly:** Base's `abs2`, a trait module's own functions and closures.
- **Several signatures:** `f::(Callable{Tuple{Float64}, Float64}, Callable{Tuple{Int}, Int})`. A call picks the signature its arguments match.
- **Stored functions:** `DynamicFn{A, S}`, made by `dynamic_fn(A, S, f)` in plain code, is a `Callable` in `DynamicCall` mode as a value of fixed type, for a library's model or callback types.
- **An open result type,** `Callable{Tuple{Float64}, S} where S`, is inferred at the boundary, in plain code. It becomes part of the worker's key and is checked at every call.
- **AD tags** are labelled by a `Callable`'s primal signature, `Tag{Sig{A, S}, V}`, so loss closures of one signature share the solver's code (TraitDifferentialEquations).
- *Prototype limits:* a dynamic call takes at most six arguments; a vararg of `Callable` is refused.

## 11. Keyword, default and variable arguments

They work as in plain Julia, with one placement rule: **a default is trait code, evaluated in the worker after translation, never at the entry.**

```julia
colz(t::ColTable, i::Int; baseline::ColTable = t, tol::Float64 = eps()) =
    (col(t, i) .- colmean(baseline, i)) ./ max(colrange(baseline, i), tol)
colmean_or(t::ColTable, i::Int = 1) = colmean(t, i)    # two methods, as Julia makes them
ncols_sum(ts::ColTable...) = sum(ncols(t) for t in ts; init = 0)

colz(m, 1)                     # baseline is t, tol is eps(): both filled in the worker
colz(m, 1; baseline = r)       # r is translated for ColTable at the entry
colz(m, 1; tol = 1)            # TypeError: tol is declared Float64, as in plain Julia
colz(m, 1; baseline = 42)      # TraitBoundError: 42 conforms to nothing
```

- **Defaults are evaluated inside.** `baseline = t` sees the trait object; `cols = 1:ncols(t)` may call an operation.
- **A positional default** is what Julia makes of it: a shorter method whose body calls the full one.
- **The entry translates, the worker sorts.** The entry translates every bounded argument, positional or keyword, and passes the supplied keywords on as a named tuple. The worker fills the defaults and runs the body.
- **A keyword is typed like a positional argument:** by a trait bound, a `Callable` bound, a declared type, or the value supplied. A bounded keyword without a default is required.
- **No dispatch on keywords,** as in plain Julia. A bound on a keyword translates and restricts; it chooses no method.
- **Varargs.** A vararg of trait objects is several crossing points with one bound, read per element. It compiles per tuple of keys; the elements may have different keys.
- **AOT.** Each set of supplied keywords is a signature; `verify_main` lists the sets a program passes.
- *Prototype:* all of the above (`runtests.jl`, "keyword, default and variable arguments", "verify_main, keyword entries").
- *Design, not built:* functions from above with keywords, named in a fourth parameter, `Callable{A, S, M, K}` with `K` a named-tuple type. The prototype's `Callable` has three parameters.

## 12. Functions that cross the boundary

A function is code, and code never crosses ([`design.md` §5](../design.md#5-the-three-rules), rule 3). A function from plain code enters only as a `Callable`. The other cases follow from the direction of the crossing.

```julia
colfun(t::ColTable, i::Int) = x -> x * colmean(t, i)       # returned to plain code: a trait module's closure
tables(f::Callable{Tuple{Int}, ColTable}, n::Int)           # results of a function from above: translated
```

- **Functions returned up** are closures of the trait module and go up as themselves. A closure that captured a trait object keeps the user's object, as a `Dynamic` does (section 15). A function that returns such a closure is a *keeping* function (section 15).
- **A closure's body is checked** like any trait code: a closure that uses a trait object outside its operations is refused (`runtests.jl`, "closures capturing a trait object are checked").
- **Results of a function from above** are values crossing downward. The result bound translates them as an argument's bound would.
- **Trait objects never go up bare.** What goes up is what operations return, ordinary values, and a trait object only inside a `Dynamic`. *Prototype:* a function returning its trait object raises `TraitUseError` (`test/like.jl`, `leak`).
- **A bounded closure,** `(u::ColTable) -> …`, would have an entry of its own. *Design:* not found in the prototype's tests, nor a `Callable` whose result is a `Callable` or a trait.
- **AOT.** A returned closure has a type of the trait module, so calls to it from plain code are calls into trait code that `verify_main` lists.

## 13. Results like the input

A function that returns "a table like the input" needs two things trait code does not have by itself:
- a new value of the implementing type: a **constructor operation**, whose declared result is `Self`;
- the way back to the user's type: the conformance's inverse.

```julia
@trait KTable begin
    kncols(t::KTable)::Int
    kcol(t::KTable, i::Int)::Vector{Float64}
    kwith(t::KTable, cs::Vector{Vector{Float64}})::Self      # a constructor operation
end
kscaled(t::KTable, a::Float64)::Like{t} = kwith(t, [a .* kcol(t, i) for i in 1:kncols(t)])

@trait LRec{U} begin
    @const u::U
    @const label::String
end
shifted(r::LRec{Vector{Float64}})::Like{r} = withfields(r; u = r.u .+ 1.0)
```

- **A constructor operation** is implemented per implementing type and checked at the conformance. At an archetype it returns the archetype, so definition checking covers code that uses it. This is Rust's `-> Self` and Swift's `init` requirements.
- **`::Like{t}`** declares that the result is like argument `t`. The worker, compiled per key, computes the new parts. The entry applies `t`'s inverse and returns a value of the caller's type.
- **`withfields(t; u = …)`** replaces declared fields, for a trait with fields.
- **The inverse:**
  - *a type that implements the operations:* the new implementing value is the result, and it must be of the same type;
  - *otherwise:* the user's object rebuilt with the forwarded or mapped fields replaced, by the type's constructor, for immutable and mutable types alike (as ConstructionBase.jl's `setproperties` does). Labels and other fields are kept.
- **A sibling:** a constructor may return the same family at another parameter value, and the inverse rebuilds the user's type there. `tof32` turns an `LSeries{Float64}` into an `LSeries{Float32}` (`test/like.jl`). The same mechanism is meant for dual-number caches and GPU arrays.
- **On a `Dynamic`:** called with a `Dynamic`, a `Like` function returns a `Dynamic` of the same conformance. A constructor operation on a `Dynamic` does too.
- **AOT:** the inverses are listed with the conformances. *Not built:* `verify_main` does not list them yet.
- *Prototype:* `Self`, `Like{t}`, `withfields`, siblings and `Dynamic` in and out all pass `test/like.jl`. `design.md` §4.7 says only `Self` constructors are exercised so far: that is true of the demonstrators (TraitCSV), not of the prototype's tests.
- *Precedents:* Tables.jl's `materializer`, Base's `similar` (the implementing type's half), ConstructionBase.jl and Accessors.jl (the inverse of a forwarding field).

## 14. Types that only convert

A type whose data a library can use only after a conversion (a lazily derived table, a foreign layout, a table typed by its schema) does not conform by a field. The library converts it explicitly, through a trait that reads any table, and runs its cached code on the result.

```julia
@trait TableLike begin
    columnnames(t::TableLike)::Vector{Symbol}
    column(t::TableLike, n::Symbol)::AbstractVector          # not concrete: this bound only converts
end
materialize(t::TableLike)::Vector{Vector{Float64}} = [Float64.(column(t, n)) for n in columnnames(t)]
colmean_any(t::TableLike, i::Int) = colmean(materialize(t), i)   # convert, then the library's worker
```

- **What it costs:** a copy; the conversion compiled per key of `TableLike`; the library behind it compiled once; no `Like{t}`, since the result is the library's own type; no write-through.
- **What it replaces:** the computed projections of the representation design, which did the same implicitly at the boundary and so hid the copy and needed a written inverse.
- *Prototype:* this is a pattern of ordinary trait code, not a mechanism. A computed projection is refused at the conformance (section 2).

## 15. `Dynamic` values, as built

A trait object lives for one call. A value that must outlive the call, an element of a collection with different keys, or a field whose key changes, is a `Dynamic{X}`: a value of any type conforming to `X`, reached through `X`'s operations and fields ([`design.md` §4.5](../design.md#45-dynamicx-a-value-of-abstract-type-x)).

```julia
mutable struct State
    const u::Vector{Float64}
    t::Float64
    model::Model                  # Dynamic{Model}
    hooks::Vector{Hook}           # Vector{Dynamic{Hook}}
end
function step!(s::State, dt::Float64)      # compiled once, whatever the model and the hooks
    du = similar(s.u)
    rhs!(s.model, du, s.u, s.t)            # an operation on a Dynamic: a call-site split
    s.u .+= dt .* du
    count(h -> fire!(h, s.u, s.t), s.hooks)
end
start(m::Model, u0::Vector{Float64}) = State(copy(u0), 0.0, Dynamic{Model}(m), Dynamic{Hook}[])
```

**Made.**
- Inside a trait module, from a trait object: `Dynamic{X}(t)`, or by storing a trait object where a `Dynamic{X}` is declared (as Julia converts a value stored in a typed field).
- From a trait-world value that is no trait object, such as a library's own integrator: `Dynamic{X}(x)`.
- A trait object carrying another trait cannot be kept as a `Dynamic{X}` (prototype: `ArgumentError`).

**What it holds.**
- A trait object of `X`, narrowed to the views of `X` and its supertraits.
- That trait object holds the user's object: read through for a mutable value; held whole for an immutable value that is its own implementing value (a held view, section 16); for an immutable value that forwards, the whole object, because the function that keeps it receives it (below).
- So a `Dynamic` sees the user rebind any field, and writes through it reach the user's object. It keeps the user's object alive.
- `design.md` §4.5 says "it holds the user's object" and that the view for (X, the object's type) is a constant per pair. The prototype's field is a narrowed trait object (`Dynamic{X}.t`). The two agree on what a reader sees; the s27 narrowing, which design.md's session-29 decisions say "dissolves", is still in the code (`_narrow` in `src/core.jl`).

**Which functions receive the whole object (keeping is detected).**
- A function whose code may keep a trait object (make it a `Dynamic`, store it where a `Dynamic` is declared, or return a closure that captured it) receives the whole user's object at its entry.
- Every other function receives what its bounds see, held for an immutable type.
- Which functions keep is decided where they are defined, from their code. When the analysis cannot tell, the function keeps, which costs only a box (`keeps(KeepOf{F}())`, default `true`).

**An operation on it is a call-site split (part D).**
- Each operation `op` of `X` gets a method on `Dynamic{X}` that calls `Compiler.dynamic_call(K, RT, op, x, args...)`:
  - `K` is `X`'s trait family;
  - `RT` is the declared result type, or `Any` where the declared type depends on the key;
  - `x` is the kept trait object.
- Inference treats the call as `op` at the union of `K`'s registered **candidates** (at most four trait-object types), plus a dynamic fallback. The inliner splits it as it splits a union: `isa` branches, direct calls that inline, the dynamic call last. The fallback is asserted to `RT`, and the join is typed `RT`.
- **Candidates are registered without an edge:**
  - conformances, when declared and when a package loads (the inferred trait-object type of each concrete conformance);
  - values, when a `Dynamic` is made.
  - A later conformance reaches the fallback and invalidates nothing. An edge would let an unrelated package's conformance invalidate trait code.
- The method is `@constprop :aggressive @inline`, so each caller is inferred again and splits over the candidates known when it is compiled.
- It dispatches in the caller's world. Witness tables, the package form before (D), ran in the latest world and gave a wrong result; they are deleted.
- A constructor operation (result `Self`) on a `Dynamic` returns a `Dynamic` of the same conformance.
- *Measured* ([`evidence.md`](evidence.md) §2): a sum over `Dynamic{Shape}`, 0.92–1.40 ns per element against plain's 0.87–0.91 with two types and 29.5–33.0 with four. The split stops at four candidates, as plain inference's does at three methods.

**Opened at a bound.** Passed to a function bounded by `X`, a `Dynamic{X}` selects the worker for its key once, by dispatch, and the worker runs compiled. A loop over its data belongs in such a function. Two `Dynamic` arguments select a worker per pair of keys.

**Equality and printing.**
- Two `Dynamic{X}` are equal when they keep the same trait object (`===`): the same key, the same implementation, egal data. So a mutable object compares by identity and an immutable one by value. `hash` agrees.
- It prints as `Dynamic{X} at <key>`.
- *Design, not built:* a trait's declared `==`; serialization with the conformance.

**Parameters and several traits.**
- A `Dynamic` of a parametric trait fixes the parameters its operations' result types use, `Dynamic{StateVector{Float64}}`, so code after a call infers.
- `Dynamic{Sub}` converts to `Dynamic{Super}`. *Design:* `Dynamic{(ColTable, RowTable)}`.

**Up and down.** A `Dynamic` is a value of its own type. It goes up as one, inside other values or bare, and comes back down admitted by its type.

## 16. The trait object's layout

A trait object is `TObj{T, V}` (`src/core.jl`):
- `T` is the set of traits it carries: trait families plus tags for the parameters they fix (`PTag{F, i, v}`), so a worker's signature has no static parameter its argument does not determine;
- `V` is the tuple of its views, one per trait.

A view's type depends on the trait and the key, never on the user's type. So one worker per key serves every conforming type. There are three layouts:

| The user's value | View | What it holds | How a read works |
|---|---|---|---|
| mutable | `View{X, W, K, N, P}` | the user's object; the slots (byte offset and field index) of the implementing value and of each declared field | a load at the offset, every time |
| immutable, forwarding to a field or keyed by declared fields | `View`, with no object | the parts: the implementing value and the declared fields' values, typed by the key | a field load from the view |
| immutable, its own implementing value | `Held{X, W, K, N, P}` (a **held view**, session 29) | the whole value | a field load; no object, no slot, no branch |

- `W` is the view's **witness**: a type that says where the operations come from (the type's own methods with a list of those served by defaults, a generic implementation, or dynamic operations). It is a type parameter, not a table of pointers.
- **Reads of a mutable object** carry Julia's own alias metadata, so a loop that reads `t.data[i]` while storing into another array vectorizes as in plain Julia. Without the metadata such a loop is 5× slower (`experiments/lens/layout.md`). The patched build provides the loads as intrinsics (piece 3, `getfield_at_offset`).
- **Writes:** an isbits field is stored at its offset; a reference field goes through `setfield!` and its write barrier.
- **Why holding is equivalent for immutable values:** none of their fields can be rebound, so a held copy always equals what a read would see.
- **A held view's cost:** a key used both held and read through has one worker per view type.
- *Measured* ([`evidence.md`](evidence.md) §2): a typed trait call 36–38 ns against 33.8–34.5 ns for the same loop in plain Julia; an untyped call 115–129 ns against about 55 ns.
- *Limits:* a field stored inline that is not isbits is read through `getfield` and costs more. GPU kernels cannot take the user's object and would need a copying layout, opt-in per trait and only for traits without writable fields (design, not built).

## 17. Caching per key

Cached code is reusable because it is compiled per key. It stays valid because it holds only facts (rule 1), which only a stakeholder or a winning pirate can change (rule 2; [`design.md` §3](../design.md#3-the-argument-in-four-steps)).

```julia
using Columns                                 # Columns' workers come from its package image
struct Mine; data::Vector{Vector{Float64}}; end
@implement ColTable Mine                      # forwards to its field: no new library code
colmean(Mine([[1.0, 2.0]]), 1)                # runs the worker Columns compiled for Vector{Vector{Float64}}
using CairoMakie                              # a stakeholder of none of Columns' facts: its code stays
```

- **Shared per key.** `Mine` shares its key with every type that forwards to a `Vector{Vector{Float64}}`.
- **Not shared:** a type that implements the operations or overrides a default gets its own workers, compiled once, in its own image.
- **A conformance invalidates nothing.** It is a method of a registry declared `@max_methods 1` with a fallback, so it applies at no existing fact. `Dynamic` candidates are registered without an edge (section 15).
- **Where compiled code lives** is Julia's own behaviour (the former rule 4 is retired, [`design.md` §5](../design.md#5-the-three-rules)):
  - code compiled while a package's image is built is kept in that image, `:facts` code included (part B);
  - a downstream image cannot add native code to an upstream one, so a worker at a new key lives in the image whose workload compiles it, or is compiled in the session;
  - a worker for a pair (key owner, function owner) that no package owns needs a glue extension or a first-session compile (`decisions.md`, session 29). The forks' `String15` workload extension is such a glue, written by hand ([`performance.md`](performance.md) theme 3).
- **What a new key costs today** ([`evidence.md`](evidence.md) §3): a new model type in TraitDifferentialEquations, `@implement` 142–164 ms and a first solve 82–133 ms, in every load order. Most of the `@implement` cost is the conformance checks' inference.
- **The next step** (`design.md` §9.3, item 4): a conformance declared in a package compiles the declared workers for its key at precompile time, replacing hand-written workload extensions.
- **Superseded:** the prototype's view caches per key, and its warm-ups. They belonged to the external interpreter and are deleted.

## 18. AOT

Dispatch between trait code, and over the types a program meets at run time, goes through declared conformances ([`design.md` §4.8](../design.md#48-aot-follows-from-declared-targets)). A build can therefore list the trait code a program can reach.

```julia
function main(args::Vector{String})
    acc = 0.0
    for t in read_tables(args)       # key chosen at run time
        acc += report(t)::Float64     # dispatch over declared conformances: finitely many targets
    end
    println(Core.stdout, acc)
end
verify_main(main, (Vector{String},); entrypoints = true)   # lists every target for juliac --trim
```

- **The targets:**
  - a function passed as a `Callable` adds one target at its declared signature;
  - a `Dynamic` value adds the conformances whose types reach the place it is made;
  - each set of supplied keywords is a signature.
- **Plain code reached from trait code** (CSV, Cairo, ForwardDiff, Base's printing) keeps plain Julia's AOT properties. `verify_main` walks into it and reports its open dynamic sites as holes. Cairo, mostly `ccall`, should close; CSV and DataFrames are the hard case.
- **A `--trim` build compiles the plain call.** Under `--trim` Julia has no facts mode and no facts methods: the world is closed. Nothing loads in a binary, so there is no cache to protect, and "identical or error" holds by definition. The binary's baseline is plain juliac; values decided by inference (A3) can differ between the session and the binary.
- **In a closed build** (`verify_main(…; entrypoints = true)` under `--trim`), the conformance caches are filled from the listed targets, a miss is an error, and `Callable` arguments are not turned into pointers, since every function is known.
- **Not closed:** dynamic operations (section 2) hold pointers made in a session.
- *Measured:* a trimmed TraitMakie binary of 4.07 MB (session 25, under the prototype's former policy, `--trim=unsafe-warn`). Not rebuilt on the current compiler.
- *Untested risk:* `--trim` is not among the flags that key package images, so an image built without it could carry facts code into a trimmed build ([`../explorations/aot-under-facts.md`](../explorations/aot-under-facts.md)).
- *Design:* a pirate lint, listing calls reached from trait code that select a pirate (`verify_main`, the symmetric check of `design.md` §3.5).

## 19. Identical or error

> **G1.** A call in trait code computes what plain Julia computes in the current world, with the same effects, or raises.

**Why it holds** (Theorem 1 of [`../explorations/wrapping-by-facts.md`](../explorations/wrapping-by-facts.md)). Every valid compiled CodeInstance has all its facts true in the current method table:
- compilation records only true facts;
- a definition, deletion or redefinition changes dispatch only where it applies and wins, and Julia's invalidation removes exactly the code with a fact there (nothing is skipped, rule P);
- a package image's code is admitted only if its facts hold at load;
- a run-time site records nothing and runs plain dispatch;
- no asserted effect applies to a frame with a run-time site, so no fold rests on a call no edge records ([`design.md` §5](../design.md#5-the-three-rules), rule 1; acceptance G1.10 and G1.19);
- a definition that would change a conformance's defaults is refused, so that decision stays true (section 1).

It depends on no declaration. A wrong performance setting, such as a `Callable`'s mode, can make code slow, never wrong.

**Pirates are followed by default.** A pirate defined before or after the trait code gives what plain Julia gives:

```julia
using MyTable                         # MyTab conforms; Stats' worker calls weight(::Float32), served by Stats' weight(::Real)
colsum(MyTab(Float32[1, 2, 3]))       # the worker holds the fact: weight(::Float32) selects weight(::Real)
using Pirate                          # defines Stats.weight(::Float32), owning neither: a pirate that wins there
colsum(MyTab(Float32[1, 2, 3]))       # the fact is broken, the worker recompiles: plain Julia's answer, with the pirate
```

- Loaded before the trait code compiles, the pirate is in the method table, and the first call follows it.
- **In strict mode,** loading `Pirate` after the first call is refused, naming its method and the worker it would change. Loaded before, it is followed; with piece 15, an image's facts broken by a pirate become an error ([`design.md` §3.2](../design.md#32-step-2-outlaw-pirates-and-fully-typed-code-is-always-valid-and-can-be-cached)).
- A real case: SparseArrays' `vcat` for Base's `Number` and `Vector` wins at a fact inside `CSV._parse`, and the default mode follows it ([`performance.md`](performance.md) theme 4).

**The assumption that remains: A3, values decided by inference.**
- `return_type`, `promote_op`, and the element types of empty `map`s, broadcasts, comprehensions and LinearAlgebra destinations are answered by inference.
- Plain Julia itself answers them differently in different contexts: `return_type(pass, Tuple{Type{Int}})` is `Type{Int64}` at run time and `DataType` once folded.
- Part (A) folds `return_type` only to an answer that cannot be wider than plain inference's, else to plain inference's answer when it rests on facts. Otherwise it is answered at run time by plain inference in its own cache owner, so `map(f, Real[])` is `Vector{Float64}`, as in plain Julia.
- It can still differ where inference decides: `Union{}` where every method at a run-time site throws, or a nested `return_type` in a callee.
- **A4** (no method defined concurrently with compiling trait code) and **A5** (the generator's behaviour) were assumptions of the package's own interpreter. `design.md` §5 says part (B) removes them; that interpreter is deleted.

**An open `Callable` result type,** inferred at the boundary in plain code, depends on what is loaded there. It is part of the worker's key and checked at every call.

**Kept values** keep the user's object, which is what a plain holder of the object sees.

---

## Dropped from `notes/4-details.md` as superseded

- The four rules, the "trait world" and "ordinary code" as worlds, the compiler policy with its own cache (`FactsInterp`), and pointer calls into plain Julia's code: replaced by the three rules and parts (A)–(D) (`design.md` §5, §6).
- The ownership section's long form: [`design.md` §1, §3, §5](../design.md#1-terms) state it; Lemma O is in `explorations/wrapping-by-facts.md`.
- Where compiled code lives as a rule (rule 4): Julia's own behaviour (section 17).
- Named implementations as adopted (by module, `via(M, x)`, witnesses carried by the value, "ColTable via Fast"): deferred (section 4).
- View caches per key ("about 3 ms in every load order"), first-call numbers from before session 29, and the 2.09 MB trimmed binary that predates keys.
- "Performance: no cliffs" as a section: its claims are restated by [`design.md` §3](../design.md#3-the-argument-in-four-steps) and measured in [`evidence.md`](evidence.md). The claim "loads do not change speed" belongs to the facts rule for any code (the control), not to traits.
- Dispatch on a `Dynamic` by run-time dispatch alone (20–80 ns): replaced by the call-site split (section 15).
