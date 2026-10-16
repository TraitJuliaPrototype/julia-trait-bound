# Traits for better Julia: the design in detail

The rules and mechanisms of the design, in Julia's terms. The [overview](1-overview.md) explains why; [design choices](2-design-choices.md) explains why these choices and not others; [code written without traits](3-wrapping.md) covers wrappers, calls upward and sealing.

The macros below stand for syntax a language feature would provide. The prototype, TraitWorld (`poc/world`), runs what is not marked as a sketch.

## Terms

- **Trait.** An abstract type with behaviour: operations, optionally fields, declared by `@trait ColTable{R} begin … end`. `R` is the *representation*, the data the operations work on.
- **Trait module.** A module whose code is written against traits, declared `@trait_module module M … end`. Its code is *trait-bound*. Its exported functions take arguments bounded by traits; its internal functions need no bounds.
- **Trait world.** Every trait module and every wrapped package, Base included. *Ordinary code* is everything else: all of Julia today.
- **Conformance.** The declaration `@implement ColTable T` that a type joins a trait. An *implementation* defines the trait's operations for a representation. A *projection* maps a value of the type to its representation.
- **Trait object.** What library code receives for a bounded argument: the value's representation, with a *witness* that says where its operations come from. A trait object has methods for its traits' operations and nothing else.
- **Entry and worker.** A bounded function has an *entry*: ordinary code that translates each argument by its bound and does nothing else. It also has a body compiled per representation, the *worker*.
- **View.** A package's view is what its compiled code is compiled against (rule 4).

## Ownership

Julia has the idea already, under its negative name. The manual calls *type piracy* "extending or redefining methods in Base or other packages on types that you have not defined", and Aqua.jl checks for it. The design turns the convention into a rule, because a method defined by the wrong package is the one way a load could change what compiled code computes.

**Owners are packages.**
- A package owns everything in its top-level module and its submodules.
- A package extension belongs to its parent package.
- Julia (Core, Base and the standard libraries of the system image) is one owner.
- The session owns what is defined at the prompt.

**Functions and types have one owner each.**
- A generic function belongs to the package that creates it: the package where `function f end`, or its first method, defines the name. `Base.show` is Julia's, whichever packages add `show` methods. A trait's operations belong to the trait's package.
- A type belongs to the package that defines it. A type counts wherever it appears in a signature, also as a parameter: in `Base.sum(v::Vector{MyType})`, `MyType` is MyPackage's.

**A method has no single owner; it has stakeholders.** They are the owner of its function plus the owners of every type in its signature. A package may define a method only if it is a stakeholder, or a delegate of one, in every signature the method applies to.

Take a function owned by package A, with argument types owned by B, C and D, and a method defined in package E:
- If E is A, B, C or D, or a delegate of one of them, the method is allowed.
- Otherwise it is piracy, refused once the stakeholders are sealed.
- The definer is the method's author. It does not take over the function or the types: A still owns the function, and B, C and D their types.

| Method, defined in MyPackage | Allowed? | Why |
|---|---|---|
| `MyPackage.f(x::Vector{Float64})` | yes | MyPackage owns the function |
| `Base.show(io::IO, x::MyType)` | yes | MyPackage owns `MyType`, a stakeholder |
| `Base.sum(v::Vector{MyType})` | yes | `MyType` appears in the signature |
| `Base.length(x::Tuple{Int, Int})` | no | Julia owns the function and all the types: piracy |
| `Base.convert(::Type{RGB}, x::Unsigned)` | no | ColorTypes owns `RGB` and Julia the rest: piracy (PlotUtils does this) |
| `Base.length(x::Union{MyType, Int})` | no | it also applies to `length(::Int)`, where MyPackage has no stake |

**Why stakeholders, and why every signature.** A call is compiled against the owners of its function and of its argument types (rule 4), which are exactly the stakeholders of any method that could apply to it.
- A method defined by a stakeholder is therefore in the view of every call it can change.
- A method defined by anyone else is in the view of none of them. It could change what a call selects without that call's compiled code ever having seen it: piracy, and the invalidation that comes with it.

**Two stakeholders defining the same signature conflict.** If A and B both define `f(::BType, ::CType)`, that is a conflict. Julia already refuses to overwrite another module's method during precompilation; the design reports it at load.

**Ownership is delegated, never claimed.** An owner may name packages that add methods on its behalf:
- **Package extensions.** An extension owns what its parent owns. Its triggers confer nothing; otherwise two parents' extensions with the same trigger could both implement one method. An extension is loaded whenever a call could use it, because its triggers are the packages its methods mention.
- **Implementation packages of a split core,** named by the core's wrapper ([code written without traits](3-wrapping.md#trait-wrappers)). StaticArraysCore defines `SArray`; StaticArrays defines `Base.size(::SArray)`, and owns neither the function nor the type. That method is a pirate unless the core's owner, or its wrapper, names StaticArrays as a delegate.

**Implementations are methods.** So the same rule says who may implement a trait for a type: a stakeholder (the trait's owner or the type's owner) or a delegate of either. A *named* implementation is the exception: used only where a caller names it, it may be written by anyone (Named implementations).

**What ownership buys.** With layering, a load can do only two things:
1. **Add methods for its own functions and types.** Code compiled elsewhere does not reach them, unless it depends on the package, in which case the package is in its view and its changes recompile it, as an upgrade does.
2. **Pirate.** That is refused where traits are in effect ([sealing](3-wrapping.md#sealing)).

So loading a package can never change what code in the trait world computes. Today, nothing enforces piracy rules; here they are enforced over everything trait-world code compiles against.

## The four rules

Rule 1 is layering; rule 2 says how a value crosses into the trait world and what it is there; rules 3 and 4 say who may change code in the trait world, what a call sees, and where compiled code lives.

1. **Layering.** Ordinary code may use the trait world; the trait world uses only itself.
   - **What trait modules call:** trait modules and wrapped packages, checked on the compiled code. They accept only values of trait-world types.
   - **Code outside** runs for the trait world only as a call upward: at a declared signature, through a pointer, with no inference edge, its result translated by its bound. Calls upward are:
     - a function handed down from above as a `Callable` argument, unless it is compiled with the caller, above the trait world's cache;
     - a declared call to a named outside function, `@call Makie.scatter!(…)::Nothing`;
     - Base's doors.

     What comes back without operations is a handle.
   - **Code from above** reaches the trait world only as values handed down: values translated by a bound, functions bounded by `Callable`, and `Dynamic` values.
   - A package can pair a trait module with an ordinary module that uses both.
2. **The boundary translates, once per bound.** A value enters the trait world where ordinary code calls in, at a bound, translated by it:
   - a trait bound projects the value through its type's projection for that trait;
   - a declared type asserts;
   - a `Callable` bound makes a function a call upward.

   **Inside**, a trait object is its trait's representation and nothing else. It is passed to functions without a bound, which are compiled for it like any argument. It is passed to a bounded argument only where its own trait is expected, or a supertrait whose declared representation map derives the other view.

   **Two traits, two views.** A function that uses a value under two traits, itself or through what it calls, declares both bounds at its boundary. The ordinary caller's one value is then projected once per bound: two views, which share data only where both projections share the user's data, or where the type declares one projection for both.
3. **One ownership rule.**
   - A package may add a method to the trait world only where it owns the function, or one of the types, in every signature the method applies to (Ownership). A `Union` with a foreign type is no way around this.
   - Implementations and projections are methods too. An operation that is someone else's function, such as `Base.size`, is implemented for someone else's type only by an owner of one of them, while the trait's owner declares the existing methods instead.
   - Ownership can be delegated by its owner, never claimed.
   - A package written without traits is owned in the trait world by its trait wrapper, at most one per package, which delegates to the implementation packages it names. Julia is one such package, owned by the Base wrapper.
   - A named implementation may be written by anyone.
4. **What a call sees, and where its code lives.**
   - **A call sees** the owners of its function and of the representations involved, with their trait-world dependencies: trait packages, wrappers with the packages and implementations they bring in and the dependencies of those, and Julia always. A package reached only by calls upward is in no view.
   - **Its code is compiled against exactly the methods it sees.** For an implementation written in the session, the view is the trait package's view plus the implementation's own methods, not the session's imports. What is redefined at the prompt recompiles as today.
   - **At a dynamic site,** the method selected at run time must come from an owner or a delegate of the function or of one of the argument types. A downstream trait module's method for its own type is accepted; a method from above or a pirate raises.
   - **Where compiled code lives.** Compiled code for a combination of packages lives in a package that depends on all of them:
     - the trait module, for its own representations;
     - a conformer, for the representations it brings;
     - a package extension or the application, when packages meet only there;
     - the session, when nothing depends on all of them.

**The central guarantee.** Together, rules 1, 3 and 4 give it: loading a package can never change what code in the trait world computes. It can only add code for new types, or be an error.

## The boundary principle

Rules 1 and 2 read operationally:
- **Only values cross the boundary,** each where a bound stands, and the bound says how the value is translated.
- **Code never crosses into the trait world's cache.** No cached worker is compiled against code from above, and a compiled call's worker is compiled above, outside that cache.

The rest follows:
- **A bound is a translation.**
  - A trait bound projects.
  - A declared type asserts.
  - A `Callable` bound makes a function a dynamic call (a pointer at a declared signature) or a compiled call (a worker compiled above on the function's type), as the mode in the bound or on the value says.
  - No bound means a trait-world value.

  The translation is the same wherever the bound stands: a positional argument, a keyword, an element of a vararg, a field, the result of a call upward.
- **Everything in a call that is not a value stays inside.** Defaults, keyword sorting, splatting and dispatch are plain Julia, run in the worker after translation. The entry translates and does nothing else.
- **A bound is a crossing point and has an entry,** on a named function or a closure alike.
- **Keeping a value is a crossing.** A value stored in a dynamic value, or captured by a closure that is returned, follows the user's field where it was projected from one that can be rebound, and is translated once, when kept, otherwise (Dynamic values).

## What code in a trait module may do

A trait object is a view of the user's data. Code reaches that data only through the trait's operations and fields, and reaches a function from above only by calling it as a `Callable`. Every other value is an ordinary Julia value of a trait-world type.

**Exported functions are the boundary.** Their trait-object arguments carry bounds, which say what an ordinary caller's value must conform to and what the entry projects.

**Internal functions need no bounds.**
- A trait object passed to one is inferred like any other argument, and the function is compiled for it as part of the worker that calls it.
- Helpers of an implementation take the representation itself, `r::R`.
- Unexported types are ordinary trait-world types.
- The trait object still admits only its traits' operations, so an internal use that the exported bounds do not cover is reported at its line, with the bound to add (Definition checking).
- A bound no path uses can be warned.
- Bounds on internal functions remain allowed, for dispatch and as documentation.

An exported function's argument without a bound takes trait-world values only, so a user type passed there runs as ordinary code (rule 1).

| In a trait module | Allowed | Why |
|---|---|---|
| the trait's operations on a trait object: `col(t, i)`, `ncols(t)` | yes | the way to reach the user's data |
| a field the trait declares: `t.name`, and `t.name = x` unless it is `const` | yes | a declared field is a pair of operations, `getproperty` and `setproperty!` (Declaring a trait) |
| several trait objects in one function, of one trait or several | yes | compiled once per tuple of representations |
| an argument with several bounds, `t::(ColTable, RowTable)` | yes | one projection per bound (rule 2) |
| passing a trait object to the module's own functions, or on where its own trait is expected | yes | statically within the module, through the entry otherwise (rule 2) |
| methods with type annotations beside trait-bounded ones: `f(m::AbstractMatrix)`, `f(t::ColTable)` | yes | types first, then traits |
| a call upward: a `Callable` argument, a declared call into a package that stays outside, an outward door such as printing to `stdout` | yes | through a pointer at a declared signature, no inference edge, the result checked, handles for what comes back |
| any code on values of trait-world types: loops, arrays, closures, `try`, the module's other functions | yes | ordinary Julia, compiled per representation |
| importing and calling Base, a standard library, a trait module or a wrapped package | yes | checked on the compiled code: globals of trait-world types, no undeclared door |
| methods of functions or for types the package owns, implementations and projections among them | yes | ownership (rule 3) |
| a trait object kept beyond the call: made into a `Dynamic{X}` and stored, returned or put in a collection | yes | translated once, when made; operations dispatch, with declared results (Dynamic values) |
| passing a trait object where a different trait is expected | no | declare both bounds, so the caller projects each (rule 2) |
| a trait object anywhere else, as a bare value: passed to an ordinary function, stored or returned bare, `typeof(t)`, a field the trait does not declare | no | code must not depend on the user's type |
| two methods with unrelated trait bounds on one position and no method for both | no | ambiguous for a type with both; checked when the function is defined |
| calling a package written without traits directly, unwrapped | no | rule 1: wrap it, or declare the calls |
| a method whose function and types the package does not own | no | piracy, rejected when the module is built (rule 3) |
| inward doors: eval, invokelatest, deserialization, reflection, getglobal by name | only as a declared call | a value denoting code from above has no admitting bound |
| arguments of open types from ordinary callers: `Any`, `Vector{Any}` | after a walk | the entry checks their parts, at a cost proportional to them; a part that is no trait-world value makes the call run as ordinary code |
| abstract types, under concrete mode | no | opt-in: a warning or an error that names the root cause |

**When the prototype checks:**
- rule 2 and the escapes: on typed code, once per method at archetypes when the module is built (Definition checking), and per signature for what that defers, reported with their lines;
- ownership and imports: when the module is defined;
- ambiguous bounds: when it is complete;
- doors and declared calls: on the typed code too;
- loading a pirate of a sealed package: on the prototype, a warning, or a deletion after the load in its refuse mode.

## Declaring a trait

```julia
@trait ColTable{R} begin
    ncols(r::R)::Int                                  # an operation: argument types and a result type
    col(r::R, i::Int)::Vector{Float64}
    firstcol(r::R)::Vector{Float64} = col(r, 1)       # a default, written in terms of the others
    name::String                                      # a field (a sketch of the syntax)
end
```

**Operations.**
- An operation is a function with declared argument and result types, the representation first.
- Calls to it are checked: the arguments against the declaration, the result asserted to the declared type.
- An operation may be an existing generic function, such as `Base.length` ([code written without traits](3-wrapping.md#traits-over-existing-functions)).
- A default is written in terms of the other operations, and an implementation may override it. A default never throws "not implemented": a missing operation is an error when the conformance is declared, not when it is called.
- An operation that mutates its representation is marked, and such a trait accepts only projections that share the user's data.

**Fields.** A trait may declare fields as well as operations, as a struct declares them. A field is a property:
- `t.name` is `getproperty(t, :name)` and `t.name = x` is `setproperty!(t, :name, x)`, as everywhere in Julia;
- a trait field requires both to work with the declared type;
- following `mutable struct`, a field is writable unless declared `const`.

```julia
@trait HasData{R} begin
    data::R                  # the representation lives in the field `data`: a lens, readable and writable
end
@trait Named{R} begin
    const name::String       # read-only: every representation has a property `name` of type String
    count::Int               # readable and writable
    ncols(r::R)::Int
end
```

- **A field is a pair of operations.** Reading is `getproperty(r, :name)::String` on the representation, writing `setproperty!(r, :name, x::String)`. Scala desugars a trait's `var` the same way, and Swift's protocols require properties `{ get set }`.
  - A stored field satisfies them, and so does a computed property: a `getproperty` method defined by the representation's owner.
  - At a known representation, a stored field compiles to the field load or store.
- **Field access is narrowed, not opened.** `t.name` is allowed for fields its traits declare, and any other field access is refused, as before. A `Dynamic` value reads and writes its declared fields by dispatch.
- **Writes are seen as in Julia.** Julia passes arguments by sharing, so `t.count = 6` on a mutable argument is seen by the caller. Through a trait, a write is seen when the representation is the user's object or shares its data: a type that is its own representation, or a sharing projection.
  - A trait with writable fields therefore refuses copying projections, as a trait with mutating operations does. A write into a copy would silently miss the user's object.
  - A conforming representation must be mutable, with those fields of exactly the declared types, so that a write never changes a type that compiled code relies on.
- **Other fields are fields of the representation.**
  - For a type that is its own representation, they are the type's own fields.
  - A type that projects needs a representation that has them.
  - Their declared types are checked at the conformance as an operation's result types are, and must be concrete if the trait requires concreteness.
- **A field of type `R` names the projection, and is a lens.** `data::R` says that a conforming type holds its representation in its field `data`. `@implement HasData T` then needs nothing more, and the one-line form's convention (the field named `data`, or the one conforming field) becomes something a trait states.
  - **Reading** `t.data` is the trait object's representation.
  - **Writing** `t.data = v` rebinds the user's field, as `t.data = v` does in plain Julia. So the trait object cannot just hold the field's value: it holds a reference to the field, the user's object and the field's index, and reads the representation through it. Every copy of the trait object, and every `Dynamic` made from it, then sees the new value, as every holder of a mutable object does.
  - The field must be declared with exactly the type `R`, so that rebinding never changes the representation's type. A `const data::R` is an ordinary read-only projection.
  - Workers stay compiled per representation, because the reference carries the field's index, not the user's type.
  - The reference keeps the user's object alive, so shared data cannot be freed under it.
- **Definition checking covers them.** A trait's archetype has its declared fields with their declared types: readable, and writable unless `const`.
- **New over Julia.** Julia's abstract types cannot require fields, a long-standing request. A trait can, because conformance is declared and checked.

**Parameters.** A trait may take parameters besides the representation, as `AbstractArray{T, N}` does: `ArrayLike{T, N}`, `Source{T}`.
- The conformance declares them, `@implement ArrayLike{Float64, 1} MyVector`.
- A bound may fix them or leave them open, `x::ArrayLike{Float64}`.
- A more specific implementation declares the same values as a generic one.
- Whether a type may conform at several values of a parameter, as a function conforms to `Callable` at several signatures, is open. Rust's experience with associated types argues for one value per type.

**Supertraits and bundles.**
- `@trait B{R} <: A{R}` makes `A`'s operations part of `B`'s; the views of a supertrait travel with every view of the trait. The syntax of the representation map, by which `B`'s operations call `A`'s statically, is open.
- A bundle trait names a combination on the library side, `@trait Table{R} <: (ColTable{R}, RowTable{R})`, so that `summary(t::Table)` needs one bound.

**Concreteness.** A trait may require that its representations be deeply concrete, guaranteeing that whatever conforms becomes concrete with respect to the behaviour the trait carries. It is opt-in, and a trait decides it when it is published: requiring it later breaks conformers whose representation is abstract, as adding an operation without a default does.

## How a type conforms to a trait

The one-line form covers a type that holds a representation or is one. The written-out forms:
- name the projection;
- give a type operations of its own at a shared representation;
- join several traits;
- implement a trait for a representation the author does not own.

Every form defines methods, so ownership says who may write it, and the methods are trait-bound code wherever they are written. The prototype runs every form for concrete types; parametric families are design.

```julia
# 1. A field, inferred: the field the trait declares for its representation (data::R), else the
#    field named data, else the one field whose type conforms
struct Measurements; data::Vector{Vector{Float64}}; end
@implement ColTable Measurements

# 2. Methods, inferred: the type is its own representation
import Columns: ncols, col
ncols(r::Ramp) = r.n
col(r::Ramp, i::Int) = r.base .* i
@implement ColTable Ramp

# 3. A projection written out: when two fields conform, when the representation is computed,
#    or when it must be copied
struct Halves; left::Vector{Vector{Float64}}; right::Vector{Vector{Float64}}; end
@implement ColTable Halves project(t) = t.left
struct Window; v::Vector{Float64}; lo::Int; hi::Int; end
@implement ColTable Window copies project(t) = [t.v[t.lo:t.hi]]   # refused by a trait with mutating operations

# 4. The operations in one block: for the author's own type, the same as 2; for a representation
#    the author does not own, only the trait's owner or a delegate (rule 3)
@implement ColTable{Ramp} begin
    ncols(r) = r.n
    col(r, i) = r.base .* i
end
@implement ColTable{Matrix{Float64}} begin      # in Columns, or in an extension Columns names
    ncols(r) = size(r, 2)
    col(r, i) = r[:, i]
end

# 5. One projection for several traits; a bundle trait names the combination on the library side
struct Grid; data::Matrix{Float64}; end         # Matrix{Float64} implements ColTable and RowTable
@implement (ColTable, RowTable) Grid
@implement Table Grid

# 6. Operations of the type's own at a shared representation: the library's compiled worker,
#    calling these operations indirectly
struct Reversed; data::Vector{Vector{Float64}}; end
@implement ColTable Reversed dynamic begin
    project(t) = t.data
    ncols(r) = length(r)
    col(r, i) = r[end - i + 1]
end

# 7. Existing methods declared for a family, by the trait's owner or Julia: no body
@implement Indexable{A} where {A <: AbstractVector}
```

Form 4 may be generic over a family of representations (Generic implementations). What each form compiles:

| Form | Compiled anew | Operation calls |
|---|---|---|
| a field or a written projection (1, 3, 5) | the projection | static, the representation's implementation |
| an own representation (2, 4) | the library's functions, once for the type | static, direct |
| dynamic operations (6) | the type's own operations | indirect, 7× plain Julia per element on the prototype |
| a family declaration (7) | nothing | the existing methods, static |

**Every check runs at the declaration, never at a call:**
- **Ownership:** the author owns the type or the trait, or is a delegate one of them names (rule 3).
- **Concreteness,** for a trait that requires it: the representation is deeply concrete, whether it is the field's type, the projection's result, or the type itself. A field declared `AbstractVector` is refused with the field named; the fix is a concrete field, or a projection that materializes.
- **Completeness:** every operation has a method or a default, and every declared field exists, with the declared types; writable fields on a mutable representation, with exactly the declared types.
- **Sharing:** a projection declares whether it shares the user's data or copies it, and a trait with mutating operations or writable fields accepts only projections that share.
- **Layering:** the methods' code stays in the trait world (rule 1).
- **Precedence:** methods win over a field when a type has both, so writing operations is always deliberate. Several conforming fields need the trait's declared field, the name `data`, or a written projection.

## Generic implementations

An implementation may cover a family of representations, or every representation that implements other traits. Workers are still compiled per concrete representation, so calls stay static.

```julia
# every Indexable representation whose elements are Vector{Float64} (a sketch of the syntax)
@implement ColTable{R} where {R: Indexable, eltype(R) == Vector{Float64}} begin
    ncols(r) = length(r)
    col(r, i) = r[i]
end
```

With this, `Vector{Vector{Float64}}` is a `ColTable` because it is `Indexable`, and so is any representation a user implements `Indexable` for. ColTable follows from the capability traits, through declarations.

**Overlap.**
- A more specific implementation beats a generic one.
- The overlap is checked when the specific one is defined: its package depends on the trait's package, so it sees every generic implementation there was.
- Two generic implementations that overlap without one being more specific are rejected.
- A more specific implementation declares the same parameter values as the generic one, so the choice never changes a type.
- An overlap the later package cannot see, as when a trait's owner adds a generic implementation in a later version, is not refused at the load. It surfaces where a call meets both (Named implementations).

## Named implementations

An implementation may be named by its module and used only where a caller names it, and anyone may write one. A package that owns neither the trait nor the type, and is no delegate, can thus make `Measurements` a `ColTable` for those who ask:

```julia
module Fast                                          # owns neither ColTable nor Measurements
@implement named ColTable Measurements begin … end   # a sketch of the syntax
end
colmean(via(Fast, m), 1)                             # this call uses Fast's implementation
```

- **The choice travels with the value.** A trait object carries its witness, so the implementation is chosen once, at the crossing, the entry stripping `via` as it strips `compiled_call`.
  - Workers are compiled per representation and witness.
  - A `Dynamic` keeps the implementation it was made with.
  - A value is never built with one implementation and queried with another, the problem that makes Rust allow one implementation per trait and type.
- **It is not piracy.** A named implementation changes no code that does not name it. Its methods are keyed by a witness type its module owns, and its compiled code lives in its own package, which depends on the trait's and the type's.
- **Unnamed implementations are as before:** written by an owner or a delegate, the more specific beating the generic. A type is a member of the trait, `x isa ColTable`, through them only.
- **Ambiguity surfaces where it matters.**
  - Two unnamed implementations that apply without one being more specific are reported when the later is defined, if it sees the earlier.
  - Otherwise an unnamed call that meets both raises an error naming both modules and the fix, `via(A, x)`, as Julia asks for `A.f` when two modules export `f`.
  - Code where the earlier choice is more specific keeps working.
- **Equality and printing name the choice.** Two `Dynamic` values of one representation with different implementations are unequal, and they print as `ColTable via Fast`.
- **No selection by scope.** A module-wide preference is not offered: an entry is compiled once and does not know its caller's module.

## Several traits, one projection

A representation can implement several traits, and a type can be projected once for several of them:

```julia
@implement (ColTable, RowTable) Measurements     # one projection for both
```

A function bounded by both then receives one value:
- one projection instead of two;
- views that share data by construction;
- workers compiled per representation instead of per pair;
- a static call when the value is passed on to a function with either bound.

Rule 2 remains the general case for types projected separately.

## Parametric user types

A parametric type conforms as a family, declared with `where` as Base's families are in form 7, or per instantiation. On a parametric type, the one-line form means the whole family.

```julia
struct Series{T}; data::Vector{Vector{T}}; end
@implement ColTable Series{Float64}                 # one instantiation
@implement ColTable Series{T} where {T <: Real}     # a family: refused here, Columns implements Vector{Vector{Float64}} only; the message names Series{Float64}
@implement ColTable Series                          # the whole family, Series{T} where {T}: the same check
```

The ownership and method checks run at the declaration, for the family as a whole:
- **A field:** the family of field types must be covered by one implementation's or projection's family, which subtyping decides. A generic implementation's predicate must be decidable on the family's structure, else the declaration is refused.
- **Methods:** the operations' methods must cover the family, with results that infer to the declared types at the family's signature.
- **Concreteness:** field types may depend on the parameters but are abstract in no other way, so every instantiation with concrete parameters is a concrete representation. An instantiation with an abstract parameter, `Series{Real}`, is refused at the entry by its type.
- **A refusal names the instantiations that would conform.**

Workers compile per instantiation, and `verify_main` enumerates the instantiations a program passes.

## Traits as abstract types

A trait reads like an abstract type wherever it is used. Why that is the right choice is in [design choices](2-design-choices.md#1-a-trait-is-an-abstract-type-with-behaviour).

- **In an argument,** `t::ColTable` is a bound: projected at the entry, compiled per representation.
- **In a field or a container,** a trait's name means its dynamic value, as an abstract type's name there means a boxed value: `plots::Vector{Plot}` is a `Vector{Dynamic{Plot}}`, and `background::ColorSpec` is a `Dynamic{ColorSpec}`.
- **`Vector{<:ColTable}`** in an argument is a vector whose elements share one representation, compiled per representation. How a user's vector is projected (element by element into a new vector, or as a whole) is open.
- **Membership is subtyping.**
  - `x isa ColTable` is true when the type of `x` conforms through an unnamed implementation.
  - `T <: ColTable` in a `where` clause or a type parameter constrains `T` to conforming types.
  - A conformance thus adds a supertype after the type is defined, which Julia does not allow for abstract types of the other kind. It is sound because only an owner or a delegate declares it, loaded with the type's or the trait's package. A conformance written at the prompt changes subtyping in the session, as a redefinition there recompiles.
- **Numbers need no trait.** Base's tower of `Number`, `Real` and `Integer` stays. Numbers are trait-world values by their types, trait-world code annotates with the tower as today, and promotion runs on concrete types in Base.

## Dispatch: types first, then traits

**A trait bound ranks above `Any` and below every type** of the other kind (concrete or abstract). A value without a conformance reaches the most specific ordinary method that applies; a value of a type caught by a type-annotated method takes that method and is not projected. How this lets a library adopt traits one function at a time is in [code written without traits](3-wrapping.md#adopting-traits-one-function-at-a-time).

**Among trait bounds:**
- A subtrait beats its supertrait, and more bounds beat fewer.
- Two methods with unrelated bounds on one position, such as `f(t::ColTable)` and `f(t::RowTable)`, need a method for both, `f(t::(ColTable, RowTable))`. This is checked when the function is defined: the check needs only the function's own methods, so no later load can create an ambiguity.

**Where the entry sits.** The entry sits at `Any` in Julia's method table and chooses among the bounds from the registered conformances. That folds for a known type, so caching and AOT are unchanged.

**Code that declares only traits** ranks concrete types first, then traits by refinement. A concrete type is always more specific than a trait, so the two never conflict.

## Definition checking

Library code is checked once, where it is defined, for every representation at once.

**Why one check suffices.** A trait object has no methods but its traits' operations and fields, and every operation declares its result type. So a worker's code is the same for every representation, except for the operations' implementations, which are checked at their conformance.

**How it checks.** The check infers each bounded method once at archetypes: a stand-in representation per bound, whose operations return values of their declared types and nothing more. Rule 2, the escapes, layering, globals and doors are checked on that code at the library's build. A mistake is reported at its line before any representation exists:

```julia
spread(t::ColTable) = size(t)    # at the library's build: `size` has no method for a trait object carrying ColTable
leak(t::ColTable) = typeof(t)    # `typeof(t)`: code must not depend on the user's type
```

**Checked per signature instead,** at a worker's first call or while an image is built:
- a bound whose parameters are left open, `x::ArrayLike{T}` with `T` free, since code computing with `T` would need a bound on it;
- a function from above whose result type is open;
- concrete mode's findings for a trait that does not require concreteness, which depend on its implementations.

**On the prototype** (`TraitWorld/src/defcheck.jl`), the check reuses the worker checks unchanged.
- It finds such mistakes with no representation present.
- It checks a library of five functions in under 200 ms in a cold session.
- It takes 3–4 ms off a new representation's first call; most of a first call is compilation.
- It still defers keyword, vararg and every `Callable` worker, which the design defers only for open result types.

## Function arguments: Callable

**Why a trait for functions.** Julia has no type for "a function from `Float64` to `Float64`": `Function` says nothing about arguments or results, and a closure's type belongs to the code that creates it, above the trait world. A function handed down from ordinary code is therefore a call upward. The built-in trait `Callable{A, S}` makes it a declared one: arguments of the tuple type `A`, and a result of type `S` (a `Tuple` when there are several).

```julia
@trait_module module Stats
using Columns
export colmap, colsum

# the default, a dynamic call: the worker compiled once per signature, an indirect call per element
colmap(f::Callable{Tuple{Float64}, Float64}, t::ColTable, i::Int) = map(f, col(t, i))

# the library's default is a compiled call: a worker per function type, a direct call the compiler may inline
colsum(f::Callable{Tuple{Float64}, Float64, CompiledCall}, t::ColTable, i::Int) = sum(f, col(t, i))
end

colmap(x -> 2x, Measurements([[1.0, 2.0]]), 1)                 # [2.0, 4.0], a dynamic call: the library's default
colmap(compiled_call(x -> 2x), Measurements([[1.0, 2.0]]), 1)  # the caller overrides: a worker compiled for this closure
colsum(dynamic_call(x -> 2x), Measurements([[1.0, 2.0]]), 1)   # the caller overrides the other way
colsum(abs2, Measurements([[1.0, 2.0]]), 1)                    # 5.0: abs2 is Base's, a compiled call whatever the default
```

- **Anything callable conforms:** closures, callable structs, generic functions. `Callable` is the one trait whose conformance is not declared, which is sound because its only operation is checked at every call:
  - the arguments have the declared types;
  - a result of another type is an error where plain Julia would widen;
  - a function without a method for `A` raises a `MethodError` when called, as in plain Julia.
- **The library sets a default, the caller decides.** `Callable{A, S, M}` carries the mode `M`.
  - **`DynamicCall`**, the default, makes the function a pointer to its code compiled for `A` in ordinary code at the call site. The worker is compiled once per signature, in the trait module's image, and each call through the pointer is indirect.
  - **`CompiledCall`** compiles the worker per function type instead, with the function's body inferred into it, as ordinary code in the caller's image: a direct call the compiler may inline, with plain Julia's speed and plain Julia's invalidation for that piece. Such a worker is the library's code compiled outside the library's cache, so a library that makes `CompiledCall` the default gives up cached code for that function by choice. That is why the system default is `DynamicCall`.
  - **The caller overrides** per value with `compiled_call(f)` or `dynamic_call(f)`, wrappers whose type fixes the mode and which the entry strips. The value's type wins, because the library's cache has no stake either way; its users do, which is what the default is for.
- **Layering holds for the cache either way.** No cached worker imports, infers into or compiles the code above.
- **An open result type,** `Callable{Tuple{Float64}, S} where S`, is inferred at the boundary, in ordinary code. It becomes part of the worker's key and is checked at every call.
- **Functions from the trait world are always compiled calls.** Base's `abs2`, a trait module's own functions, and closures created inside a trait module are trait-world values, called directly. `map`, `filter` and `sum(f, …)` work inside the trait world as today.
- **AOT.** A `Callable` argument names its signature, so a build compiles each function passed at it, and `verify_main` lists them.
- **Several signatures.** A function called at two signatures carries two bounds, `f::(Callable{Tuple{Float64}, Float64}, Callable{Tuple{Int}, Int})`.
- **Cost.** A dynamic call costs about 4 ns per call on the prototype.

## Keyword, default and variable arguments

Keyword, default and variable arguments work as in plain Julia, with one placement rule: a default is trait-world code, evaluated in the worker after projection, never at the entry. The prototype runs keyword and optional arguments in trait-bounded functions.

```julia
@trait_module module Columns
export colmean, colzscore

colmean(t::ColTable, i::Int = 1) = sum(col(t, i)) / length(col(t, i))   # colmean(t) calls colmean(t, 1) inside

# a bounded keyword that defaults to a trait object the worker holds, and a typed keyword with a constant default
colzscore(t::ColTable, i::Int; baseline::ColTable = t, tol::Float64 = eps()) =
    (col(t, i) .- colmean(baseline, i)) ./ max(colstd(baseline, i), tol)
end

colzscore(m, 1)                     # one worker: baseline is t, tol is eps(), both filled inside
colzscore(m, 1; baseline = r)       # r is projected for ColTable at the entry, as a positional argument would be
colzscore(m, 1; tol = 1)            # an error at the entry: tol is declared Float64, as in plain Julia
```

- **Defaults are evaluated inside,** in the worker, after projection. So `baseline = t` sees the trait object, and `i = ncols(t)` may call an operation. A positional default is what Julia makes of it: a shorter exported method whose body calls the full one with its own trait object.
- **The entry projects, the worker sorts.** The entry projects every bounded argument, positional or keyword, and passes the supplied keywords on as a named tuple. The worker fills the defaults and calls the body. The sorter is compiled per set of supplied keywords, by name and type, and the body once per full signature, as Julia does it.
- **A keyword is typed like a positional argument:** by a trait bound, a declared type, or the value supplied. A bounded keyword without a default is required.
- **No dispatch on keywords,** as in plain Julia. A trait bound on a keyword projects and restricts; it chooses no method.
- **A default for a bounded parameter** is a trait object of that trait, or a value of a representation the trait is implemented for. Its type is inferred when the worker is compiled.
- **Functions from above with keywords.** `Callable{A, S, M, K}` names them in a fourth parameter, a named tuple type: `Callable{Tuple{Float64}, Float64, DynamicCall, @NamedTuple{tol::Float64}}`.
- **AOT.** Each set of supplied keywords is a signature, so `verify_main` lists the sets a program passes.
- **Varargs.** A vararg is several crossing points with one bound, read per element as plain Julia reads `xs::Int...`. A vararg of trait objects is compiled per tuple of representations.

## Functions that cross the boundary

A function is code, and code never crosses. A function from above enters only as a `Callable`. The remaining cases follow from the direction of the crossing.

```julia
colfun(t::ColTable, i::Int) = x -> x * colmean(t, i)      # returned up: a trait-world closure, called from above on Float64
scaler(t::ColTable) = (u::ColTable) -> meandiff(t, u, 1)   # a bounded closure: it has an entry, so the caller passes its own objects
colmaker(f::Callable{Tuple{Int}, Callable{Tuple{Float64}, Float64}}, t::ColTable)   # a function from above that returns a function
tables(f::Callable{Tuple{Int}, ColTable}, n::Int)          # a function from above that returns tables: each result projected
```

- **Functions returned up** are trait-world values and go up as themselves. A closure keeps the trait objects it captured as a `Dynamic` keeps them: a field projection of a mutable user type as a lens, any other translated once, when captured, and keeping the user's object alive where the projection shares. To take the caller's own objects it needs a bound in its signature, and a bounded signature has an entry.
- **Results of a function from above** are values crossing downward, so the result bound translates them as an argument's bound would.
- **Trait objects never go up bare.** What goes up is what operations return, trait-world values, and a trait object only inside a `Dynamic` value.
- **AOT.** A returned closure is a trait-world type, so calls to it from ordinary code are calls into the trait world that `verify_main` lists.

## Dynamic values

A trait object lives for one call. A value that must outlive the call, or an element of a collection whose elements have different representations, or a field whose representation changes, is a `Dynamic{X}`: a value of any type conforming to `X`, reached through `X`'s operations and fields. A trait's name in a field or a container means its `Dynamic` (Traits as abstract types).

```julia
struct Scene
    plots::Vector{Plot}                        # Vector{Dynamic{Plot}}: plots of any conforming type
    background::ColorSpec                      # Dynamic{ColorSpec}: :white now, an image later
end
add!(s::Scene, p::Plot) = push!(s.plots, p)    # an argument: a bound; stored, it becomes a Dynamic{Plot}
render(s::Scene) = foreach(draw, s.plots)      # draw(p::Plot): one dispatch per plot, then compiled per representation
```

- **Made at a bound or by storing.**
  - A bound in a field, a container or a result projects the value and keeps the trait object.
  - Inside, storing a trait object of `X` where an `X` is declared keeps it, as Julia converts a value stored in a typed field; `Dynamic{X}(t)` does so explicitly.
  - Nothing else makes one, so its type decides it: the entry admits it by type, and inward doors such as deserialization check its content.
- **Kept values follow the user's fields.** Keeping a value is a crossing, and what is kept depends on the projection.
  - **A field projection is kept as a lens** when the user's type is mutable and the field can be rebound: not `const`, and declared with exactly the representation's type. This holds whether or not the trait writes the field. The kept value sees the user rebind the field, as every holder of the object does in plain Julia; within a call, the entry still projects once (rule 2).
  - **A field of an immutable type, or a `const` field,** cannot be rebound, so holding its value is the same as following it.
  - **Any other projection is translated once, when made:** a computed projection, a copying one, or a field declared with an abstract type. A later change to the user's object is then seen as far as the projection shares data, as a typed field in Julia converts at construction.
  - **The user's object stays alive.** A lens, and a `Dynamic` made from a sharing projection, keep the user's object alive, so shared data cannot be freed under them.
- **A kept lens:**
  - **Writes reach the user.** Writes through a lens, where the trait declares the field writable, reach the user's object.
  - **No reopening.** The field is declared with exactly the type `R`, so the stored value's representation type never changes, and the dispatch that opens it never needs to be redone.
  - **Equality.** A lens compares and hashes by the user's object and the field, so a rebinding never changes its hash, as for a mutable object in Julia.
  - **Serialization.** It serializes the user's object and the field's index, and inward doors re-check both.
  - **Compiled code.** A worker can receive a lens view or a held view of the same representation, so it is compiled once for each kind that occurs.
- **Operations dispatch.** An operation of `X` on a `Dynamic{X}` dispatches on the trait object inside, in the caller's world, and asserts the declared result type, so code after the call infers. Its targets are the conformances of `X` whose representations reach a place where a `Dynamic{X}` is made: rule 3 closes them, a build lists them, and `verify_main` counts the calls as bounded.
- **Opened by a bound.** Passed to a function bounded by `X`, a `Dynamic{X}` selects the worker for its representation once, and the worker runs compiled.
  - A loop over its data belongs in such a function; concrete mode reports operations on a `Dynamic` inside a loop and names that fix.
  - Two `Dynamic` arguments select a worker per pair of representations.
- **Equality.** Values of different representation types, or different implementations, are unequal. Otherwise the trait's declared `==` decides, or, without one, `===` of the trait objects, so `:red` equals `:red` and arrays compare by identity. `hash` agrees.
- **Several traits.** `Dynamic{(ColTable, RowTable)}` holds a trait object with both views and converts explicitly to `Dynamic{ColTable}`. `Dynamic{Sub}` converts to `Dynamic{Super}` through the declared representation map. A `Callable` in `DynamicCall` mode is already the dynamic value of a function.
- **Up and down.** A `Dynamic` is a trait-world value: it goes up as one, inside other values or bare, and comes back down admitted by its type. Code above may hold and pass it, and defines nothing that trait-world code reaches through it.

A `Dynamic` costs an allocation when made, and a dispatch per operation: about 20–80 ns in a measurement of Julia's dispatch on boxed values. First calls from package images need no compilation.

**Several views of one object.** A value that carries a lens view and another view computed from the same field goes wrong on a write: the write through the lens leaves the computed view stale. So a type whose writable projection field also feeds another trait's projection must project both from the field, one lens shared by both views, or the conformance is refused.

**What a lens costs** (measured on Julia 1.12, per access, a worker reading its representation once per operation call; `writeup/design-findings.md` §18):
- **Reads:**
  - a held value: 1.0 ns, as a direct field read;
  - a lens through Julia's builtin `getfield` on an untyped object: 4.6 ns;
  - a lens as a load at the field's byte offset, which a runtime can emit: 1.15 ns.
- **Writes:**
  - through the builtin `setfield!`: 13.6 ns;
  - direct: 0.6 ns.

Loops over the representation's contents pay nothing extra, and an operation called per element pays the read each time.

## Caching: compiled once, reused everywhere

Cached code is reusable because it is compiled per representation, not per type, and it survives because of layering: only the packages it depends on can change it.

```julia
using Columns                                   # Columns' workers come from its package image
struct Mine; data::Vector{Vector{Float64}}; end
@implement ColTable Mine                        # conforms through its field: the projection is the only new code
colmean(Mine([[1.0, 2.0]]), 1)                  # runs the compiled worker
using CairoMakie                                # outside the trait world Columns depends on: changes none of its code
```

- **Per representation.** `Mine` shares its representation with every type that projects onto it, so `colmean` runs code that Columns compiled when it was built. On the prototype, the first calls of a new own representation take 10–60 ms, mostly compilation. Caches per representation reduce them to about 3 ms in every load order (`poc/interfaces/README.md`, view caches).
- **Compiled against what it sees.** Each specialization is compiled against the methods of the packages it depends on only (rule 4), so inference, union splitting and return-type queries see nothing else.
  - A later definition by one of those packages recompiles it.
  - A definition elsewhere, for the definer's own types, can never apply.
  - A definition that would apply is piracy, and the load that brings it is refused.
- **Every combination has an owner image.**
  - The entry lives in the trait module's package image; the projection and a worker at a new representation live in the conformer's.
  - Code for packages that meet only in an application lives in a package extension or the application, and the session comes last.
  - Each piece is compiled where it lives, because a downstream image cannot add native code to an upstream one.
- **Leaks become errors.** Layering holds only if no value of an outside type leaks in. Dynamic dispatch from trait-bound code therefore checks that the selected method comes from what the call sees, and raises an error otherwise: a leak becomes an error, never a wrong result.

## AOT: the reachable code is declared

Because of layering, a trait-bound program's calls stay inside the trait world, and dispatch over runtime types goes through conformances, whose targets are listed. A build can therefore compile exactly what the program can reach.

```julia
function main(args::Vector{String})
    acc = 0.0
    for t in read_tables(args)        # element types chosen at run time
        acc += report(t)::Float64      # dispatch over the conformances: finitely many targets
    end
    println(Core.stdout, acc)
end

verify_main(main, (Vector{String},); entrypoints = true)   # lists every target for juliac --trim
```

**In plain Julia,** a generic function called on a value of unknown type has no list of targets. It compiles at first use in a session, and fails a trimmed build, or crashes a binary built with the unsafe option.

**Here the list exists:**
- a function passed as a `Callable` argument adds one target at its declared signature;
- a `Dynamic` value adds the conformances whose representations reach the place it is made.

On the prototype, `verify_main` enumerates the entries' targets from the types the program can pass (here 8 targets), and the program compiles to a 2.09 MB trimmed executable. Without the list, the binary dies at its first trait call.

## Performance: no cliffs

Four cliffs disappear by construction, and the fifth becomes a report at build time.

- **Loads cannot change speed.** The methods at an abstract call site change only with their owners (rule 4), so an unrelated load cannot push inference over `max_methods` and turn a fast call dynamic. Return-type queries fold at compile time.
- **Types cannot multiply compile cost.** Code compiles per representation, not per user type. A type that conforms by projection adds no compiled code; a type that is its own representation compiles the library once for itself, by its own choice.
- **Nothing recompiles under you.** No unrelated load invalidates the trait world's cache. A compiled-call worker, which lives in the caller's image, and code redefined at the prompt recompile as today.
- **Trait operations cost nothing.**
  - Implemented per representation, they are direct calls that the compiler may inline. On the prototype, library code making one operation call per element ran at 1.00–1.01× plain Julia at 4096 elements, and through a generic implementation at 1.00–1.03×.
  - The entry adds a fixed cost of about 110 ns per call on the prototype: 2.8–3× at 16 elements and nothing at 4096.
  - Only dynamic operations, dynamic calls and operations on `Dynamic` values are indirect.
- **Abstract types in hot loops are found at their root cause.** Code in a trait module sees only representations (deeply concrete where its traits require it) and operation results asserted to their declared types. An abstract value in a hot loop can therefore only come from a trait that does not require concreteness, from the module's own code, or from the code it calls. Concrete mode traces it there, through any number of layers.

```julia
@warn_on_abstract @trait_module module CTop
using CBottom: Config                  # a trait module too (rule 1); Config has a field declared Real
using CMid2: factor                    # factor reaches that field through two packages

@trait Series{R} begin
    vals(r::R)::Vector{Float64}
end

function scaled_sum(t::Series, c::Config)
    s = 0.0
    for x in vals(t)
        s += x * factor(c)
    end
    s
end
end
```

On the prototype, with CBottom, CMid1 and CMid2 as trait modules too, this module prints while it is built:

```
Warning: @warn_on_abstract: `scaled_sum` at Series at Vector{Float64} uses abstract types on its normal path; 1 root cause:
  1. field `scale` of `CBottom.Config` is declared `Real` (CBottom.jl:8)
       3 uses, 2 in loops; first in a loop: CTop.jl:18  *(::Float64, ::Any)
       ← CMid2.factor(::CBottom.Config) returns Any (CTop.jl:18)
       ← dynamic call +(::Any, ::Int64) returns Any (CMid2.jl:6)
       ← CMid1.gain(::CBottom.Config) returns Any (CMid2.jl:6)
       ← dynamic call *(::Real, ::Int64) returns Any (CMid1.jl:6)
```

In this example that one field makes the loop 74× slower. `@error_on_abstract` turns the warning into an error, and `check_concrete` gives the same report in tests.

## Identical or error

Under layering, a load can affect code in the trait world only through a method from outside what that code sees, which would change it: piracy.
- Every package in a view is sealed by the load that brings it there ([sealing](3-wrapping.md#sealing)).
- A load that seals checks what is already loaded as well as what comes later.
- A pirate of a sealed package is a conflict whichever side loaded first: refused in strict mode, tolerated with a warning and a recompile otherwise.

So no call sees a pirate that was not tolerated, and no call errors on one. The opt-out restores plain Julia.

```julia
using MyTable                         # projects MyTab; Stats' worker calls weight(::Float32); Stats and Base are sealed
using Pirate                          # defines Stats.weight(::Float32), owning neither: refused, naming the method and Stats
tolerate!(:Pirate)                    # opt out for this session (a sketch): plain Julia, the pirate applies
using Pirate                          # loads; Stats' worker for Float32 recompiles against it, with a warning
colsum(MyTab(Float32[1, 2, 3]))       # what plain Julia computes
```

**Two exceptions:**
- Element types that Julia derives from inference, such as that of `map` over an empty collection, are answered within the trait world. They can differ from plain Julia's where Julia documents them as inference-dependent.
- An open `Callable` result type, inferred at the boundary in ordinary code, depends on what is loaded there. It is part of the worker's key and checked at every call.

**Kept values.** A value kept in a dynamic value follows the user's field where it was projected from one that can be rebound, as plain Julia's holders of a mutable object do. Otherwise it is translated once, when kept: that is the semantics of the projection, which runs in both modes, like the conversion of a typed field.

## Possible extensions

- **Constructor operations.** A trait may declare how to build a value of the user's type from a representation, so trait modules can return values like their inputs.
- **Representation maps for supertraits.** `@trait B <: A` is relied on by rule 2, by dispatch and by bundle traits; the syntax of the map by which `B`'s operations call `A`'s statically is open.
- **Inline entries.** Callers that already know the type inline the projection lookup and call the worker directly.
- **Concrete mode by default.** Warnings for every worker, so the cliff is caught before anyone opts in.

## Open points

- How `Vector{<:ColTable}` projects a user's vector: element by element into a new vector, or as a whole.
- Whether a type may conform at several values of a trait parameter.
- Numeric traits: numbers that conform after the fact or project, and promotion across representations.
- Indexes for the load-time checks (sealing, the dispatch check), so they never scan all methods.
- An example and a test that a value crossing upward behaves as it does inside (C++0x's `late_check` problem).
- A kept value projected from a mutable field declared with an abstract type is translated once. A lens there would need to dispatch again when the user rebinds the field to another type; whether that is worth its cost is open.
- Computed properties (a `getproperty` method) as projections: a lens needs a field; a computed projection stays translated once.
- Prototype work: lenses (a field reference); named implementations; `Dynamic{X}`; trait fields; archetype checks for keyword, vararg and `Callable` workers with declared results; printing frames by bound and representation.
