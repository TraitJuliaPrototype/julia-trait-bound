# Traits for better Julia: the design in detail

The rules and mechanisms of the design, in Julia's terms. The [overview](1-overview.md) explains why; [design choices](2-design-choices.md) explains why these choices and not others; [code written without traits](3-wrapping.md) covers calling packages written without traits, pirates and strict mode.

The macros below stand for syntax a language feature would provide. The prototype, TraitWorld, runs most of this design on stock Julia 1.13.2 (status in `writeup/decisions.md`, column "Prototype"). It still accepts the earlier spelling with the implementing type as the trait's last parameter `R` (`@trait ColTable{R}`, operations `ncols(r::R)`), and examples of its tests use it.

## Terms

- **Trait.** An abstract type with behaviour: operations and fields, declared by `@trait ColTable begin … end`. A trait's parameters are its *associated types*, `@trait Integrator{U, P}`.
- **Trait module.** A module whose code is written against traits, declared `@trait_module module M … end`. Its code is *trait-bound*. Its exported functions take arguments bounded by traits; its internal functions need no bounds.
- **Trait world.** Every trait module, and the code compiled for it: its workers and every callee they reach, Base's or any package's, compiled under the trait world's compiler policy (rule 1). *Ordinary code* is everything else: all of Julia today, compiled as today.
- **Compiler policy.** The compiler of the trait world, with its own cache (TraitWorld's `FactsInterp`). It records facts at concrete signatures and compiles every other call as a run-time site (rule 1).
- **Fact.** What compiled trait-world code knows about the method table: "at concrete signature `s`, dispatch selects `r`", where `r` is a method, "no method" or "ambiguous".
- **Run-time site.** A call in compiled trait-world code whose argument types are not concrete. It records nothing and dispatches at run time, in the current world.
- **Implementation.** The methods of a trait's operations for a type: `@implement ColTable Vector{Vector{Float64}} begin … end`, or existing methods declared. It may be generic, one implementation for a family of types. It says nothing about fields.
- **Conformance.** The declaration `@implement ColTable T` that a type joins a trait. The operations come from `T` itself, which then must have an implementation, or `T` *forwards* them to one of its fields whose type has one; operations neither provides are served by the trait's defaults. The trait's declared fields map to stored fields of `T`, by name or as written. `T` is the *conforming type*.
- **Implementing type.** The type whose own methods serve at least one of the trait's operations for a conformance: the conforming type, or the field it forwards to. A trait declaration spells it `Self`. When every operation is served by a default written over declared fields and other operations, or the trait has no operations, there is no implementing type. Many conforming types share one implementing type by forwarding to a field of that type, and so share compiled code; it is close to `Self` in Rust and Swift, which have no forwarding, so there the two coincide.
- **Key.** What a bound can see, and what a worker is compiled for: the implementing type, if there is one, and the types of the fields the trait declares. Workers are compiled per tuple of their bounds' keys. The conforming type is in a key only when it is the implementing type.
- **Trait object.** What library code receives for a bounded argument: the user's object itself, with one *view* per trait that gives the byte offsets of the implementing value and of the declared fields in the user's type, and a *witness* that says where the operations come from. Every access reads the user's object, so a trait object sees exactly what plain Julia sees. Its layout depends on the trait and the key, never on the user's type. A trait object has methods for its traits' operations and fields and nothing else.
- **Entry and worker.** A bounded function has an *entry*: ordinary code that translates each argument by its bound and does nothing else. It also has a body compiled per key, the *worker*.
- **View.** The part of a trait object for one trait: the offsets of what that trait can see.
- **Stakeholder, pirate.** A method's stakeholders are the owner of its function and the owners of the types in its signature; a method defined by anyone else is a pirate (Ownership).

## Ownership

Julia has the idea already, under its negative name. The manual calls *type piracy* "extending or redefining methods in Base or other packages on types that you have not defined", and Aqua.jl checks for it. The design uses it to say who can change compiled trait-world code: only a stakeholder of one of its facts, or a pirate that wins at one (rule 3).

**Owners are packages.**
- A package owns everything in its top-level module and its submodules.
- A package extension belongs to its parent package.
- Julia (Core, Base and the standard libraries of the system image) is one owner.
- The session owns what is defined at the prompt.

**Functions and types have one owner each.**
- A generic function belongs to the package that creates it: the package where `function f end`, or its first method, defines the name. `Base.show` is Julia's, whichever packages add `show` methods. A trait's operations belong to the trait's package.
- A type belongs to the package that defines it. A type counts wherever it appears in a signature, also as a parameter: in `Base.sum(v::Vector{MyType})`, `MyType` is MyPackage's.

**A method has no single owner; it has stakeholders.** They are the owner of its function plus the owners of every type in its signature. A method defined by a package that is not a stakeholder in every signature the method applies to is a *pirate*.

Take a function owned by package A, with argument types owned by B, C and D, and a method defined in package E:
- If E is A, B, C or D, or an extension of one of them, the method is no pirate.
- Otherwise it is a pirate: refused in a trait module, followed as in plain Julia elsewhere.
- The definer is the method's author. It does not take over the function or the types: A still owns the function, and B, C and D their types.

| Method, defined in MyPackage | Allowed in a trait module? | Why |
|---|---|---|
| `MyPackage.f(x::Vector{Float64})` | yes | MyPackage owns the function |
| `Base.show(io::IO, x::MyType)` | yes | MyPackage owns `MyType`, a stakeholder |
| `Base.sum(v::Vector{MyType})` | yes | `MyType` appears in the signature |
| `Base.length(x::Tuple{Int, Int})` | no | Julia owns the function and all the types: piracy |
| `Base.convert(::Type{RGB}, x::Unsigned)` | no | ColorTypes owns `RGB` and Julia the rest: piracy (PlotUtils does this) |
| `Base.length(x::Union{MyType, Int})` | no | it also applies to `length(::Int)`, where MyPackage has no stake |

**Why stakeholders, and why every signature** (Lemma O in `writeup/explorations/wrapping-by-facts.md`). Compiled trait-world code depends on the method table only through facts at concrete signatures (rule 1).
- A method that is no pirate and applies at a concrete signature `s` is defined by a stakeholder of `s`: the owner of the function or of a type in `s`.
- Those packages are loaded wherever `s` is compiled, since `s` names their function and types. So a later change at `s` is a definition by one of them, an extension of one of them, or a pirate.
- A pirate changes dispatch at `s` only if it wins there.

**Two stakeholders defining the same signature conflict.** If A and B both define `f(::BType, ::CType)`, that is a conflict. Julia already refuses to overwrite another module's method during precompilation, and trait-world code follows whichever method plain Julia selects.

**Ownership is never claimed.**
- **Package extensions.** An extension owns what its parent owns. Its triggers confer nothing; otherwise two parents' extensions with the same trigger could both implement one method. An extension is loaded whenever a call could use it, because its triggers are the packages its methods mention.
- **Implementation packages of a split core.** StaticArraysCore defines `SArray`; StaticArrays defines `Base.size(::SArray)`, and owns neither the function nor the type. That method is a pirate by the letter, followed like any other. It matters only for the optional strict mode, and there only if StaticArrays is loaded after trait code was compiled at `SArray` types and its method wins at one of that code's facts.

**Implementations are methods.** So the same rule says who may implement a trait for a type: a stakeholder, the trait's owner or the type's owner. A *named* implementation is the exception: used only where a caller names it, it may be written by anyone (Named implementations).

**What ownership buys.** A load can do three things to code compiled for the trait world:
1. **Add methods for its own functions and types.** They apply at no fact of code compiled before, so nothing changes.
2. **Change dispatch as a stakeholder** of a fact's signature: a redefinition, an extension, an upgrade. The code recompiles, as plain Julia's does.
3. **Bring a pirate.** If it wins at a fact, the code recompiles to follow it, as plain Julia does. If it loses, nothing changes, in whichever order the packages load.

So an unrelated load never changes or discards trait-world code (Theorem 2, rule 3). Today nothing enforces piracy rules. Here trait modules may not define pirates, and pirates elsewhere are followed. An optional strict mode, off by default, refuses the definition of a pirate that would win at a fact of compiled trait-world code ([code written without traits: strict mode](3-wrapping.md#strict-mode-an-option)).

## The four rules

Rule 1 says what compiled trait-world code depends on; rule 2 says how a value crosses into the trait world and what it is there; rules 3 and 4 say who can change compiled trait-world code, what a call sees, and where compiled code lives.

1. **Concrete facts.** Code compiled for the trait world, and every callee compiled for it, depends on the method table only through facts: "at concrete signature `s`, dispatch selects `r`" (rule R in `writeup/explorations/wrapping-by-facts.md`).
   - `r` may be a method, "no method" or "ambiguous". Union splitting gives several facts.
   - Decisions the trait world makes from the method table are facts too: "type `T` uses the trait's default for `length`" is the fact `D(length, Tuple{T}) = default`.
   - A call whose argument types are not concrete records nothing and dispatches at run time, in the current world: a run-time site.
   - **Nothing is skipped** (rule P). A fact is invalidated exactly when a definition changes dispatch at its signature. That is Julia's own invalidation for edges at concrete signatures.
   - **What trait modules call:** any Julia code, directly: Base, Cairo, ForwardDiff, CSV. A callee is compiled under the policy, or called through a pointer into plain Julia's code, a choice of speed only ([code written without traits](3-wrapping.md#calling-code-written-without-traits)).
   - **Ordinary code may use the trait world.** Pairing a trait module with an ordinary module that converts explicitly is a style, not a rule.

   (Until session 23, rule 1 was layering: the trait world used only itself.)
2. **The boundary translates, once per bound.** A value enters the trait world where ordinary code calls in, at a bound, translated by it:
   - a trait bound takes the user's object, and the offsets of what the bound can see in it;
   - a declared type asserts;
   - a `Callable` bound makes a function a dynamic or a compiled call, checked at every call (Function arguments: Callable).

   **Inside**, a trait object is what its bound can see and nothing else. It is passed to functions without a bound, which are compiled for it like any argument. It is passed to a bounded argument only where its own trait is expected, or a supertrait.

   **Two traits, two views.** A function that uses a value under two traits, itself or through what it calls, declares both bounds at its boundary. The ordinary caller's one value is then translated once per bound: two views of the same object, which agree because nothing is copied.
3. **One ownership rule.**
   - A method's stakeholders are the owner of its function and the owners of the types in every signature it applies to; a method defined by anyone else is a pirate (Ownership). A `Union` with a foreign type is no way around this.
   - **A trait module may not define a pirate,** checked when the module is defined.
   - Implementations are methods too. An operation that is someone else's function, such as `Base.size`, is implemented for someone else's type only by an owner of one of them, while the trait's owner declares the existing methods instead.
   - **Pirates elsewhere are followed,** as in plain Julia. An optional strict mode refuses the definition of a pirate that would win at a fact of compiled trait-world code ([code written without traits](3-wrapping.md#strict-mode-an-option)).
   - Ownership is never claimed. A package extension belongs to its parent.
   - A named implementation may be written by anyone.
   - **Why it matters** (Lemma O): a method that is no pirate and applies at a concrete signature is defined by a stakeholder of it. So only a stakeholder, or a pirate that wins there, can change a fact.
4. **What a call sees, and where its code lives.**
   - **A call sees the current world,** as a plain Julia call does. Its compiled code holds facts only at concrete signatures, and a run-time site dispatches in the world current at the call. What is redefined at the prompt recompiles as today.
   - **Where compiled code lives.** Compiled code for a combination of packages lives in a package that depends on all of them:
     - the trait module, for the types it implements its traits for;
     - a conformer, for its own types;
     - a package extension or the application, when packages meet only there;
     - the session, when nothing depends on all of them.

**The central guarantees.**
- **Identical or error (G1).** A trait-world call computes exactly what plain Julia computes in the current world, with the same effects, or raises (Theorem 1 of `wrapping-by-facts.md`). Every valid compiled fact is true in the current method table, and a run-time site dispatches as plain Julia does. It rests on three assumptions, listed in [Identical or error](#identical-or-error): values decided by inference precision (A3), no method definition concurrent with compiling trait code (A4), and the generator's behaviour (A5).
- **Stable caches (G2).** A load invalidates trait-world code only if it is a stakeholder of one of the code's fact signatures, or brings a pirate that wins there, in any load order (Theorem 2; rules 1 and 3). Measured on the prototype: of the CodeInstances compiled under the policy, 0 were lost across twelve package loads, before or after the trait code.

## The boundary principle

Rule 2 reads operationally:
- **Only values cross the boundary,** each where a bound stands, and the bound says how the value is translated.
- **Code never crosses into a library's cache.** No worker cached in the library's image is compiled for a function from above; a compiled call's worker lives in the caller's image (rule 4).

The rest follows:
- **A bound is a translation.**
  - A trait bound takes what it can see.
  - A declared type asserts.
  - A `Callable` bound makes a function a dynamic call (a pointer at a declared signature) or a compiled call (a worker compiled above on the function's type), as the mode in the bound or on the value says.
  - No bound takes the value as it is, at its own type; a function from above enters only as a `Callable`.

  The translation is the same wherever the bound stands: a positional argument, a keyword, an element of a vararg, a field, the result of a function from above.
- **Everything in a call that is not a value stays inside.** Defaults, keyword sorting, splatting and dispatch are plain Julia, run in the worker after translation. The entry translates and does nothing else.
- **A bound is a crossing point and has an entry,** on a named function or a closure alike.
- **Keeping a value is a crossing.** A value stored in a dynamic value, or captured by a closure that is returned, keeps the user's object, so it follows the user's fields (Dynamic values).

## What code in a trait module may do

A trait object is a view of the user's data. Code reaches that data only through the trait's operations and fields, and reaches a function from above only by calling it as a `Callable`. Every other value is an ordinary Julia value.

**Exported functions are the boundary.** Their trait-object arguments carry bounds, which say what an ordinary caller's value must conform to and what the entry takes from it.

**Internal functions need no bounds.**
- A trait object passed to one is inferred like any other argument, and the function is compiled for it as part of the worker that calls it.
- Helpers of an implementation take the implementing type itself.
- Unexported types are ordinary types.
- The trait object still admits only its traits' operations, so an internal use that the exported bounds do not cover is reported at its line, with the bound to add (Definition checking).
- A bound no path uses can be warned.
- Bounds on internal functions remain allowed, for dispatch and as documentation.

An exported function's argument without a bound takes the value at its own type, and the worker is compiled for that type, as plain Julia compiles a method.

| In a trait module | Allowed | Why |
|---|---|---|
| the trait's operations on a trait object: `col(t, i)`, `ncols(t)` | yes | the way to reach the user's data |
| a field the trait declares: `t.name`, and `t.name = x` unless it is `@const` | yes | a declared field is a pair of operations, `getproperty` and `setproperty!` (Declaring a trait) |
| several trait objects in one function, of one trait or several | yes | compiled once per tuple of keys |
| an argument with several bounds, `t::(ColTable, RowTable)` | yes | one view per bound (rule 2) |
| passing a trait object to the module's own functions, or on where its own trait is expected | yes | statically within the module, through the entry otherwise (rule 2) |
| methods with type annotations beside trait-bounded ones: `f(m::AbstractMatrix)`, `f(t::ColTable)` | yes | types first, then traits |
| calling a `Callable` argument | yes | a dynamic or a compiled call, its arguments and result checked at every call |
| any code on ordinary values: loops, arrays, closures, `try`, the module's other functions | yes | ordinary Julia, compiled per key |
| importing and calling any Julia code: Base, a trait module, any package (CSV, Cairo, ForwardDiff, Makie), printing, logging | yes | compiled under the policy: facts at concrete signatures, run-time dispatch elsewhere (rule 1) |
| methods of functions or for types the package owns, implementations among them | yes | ownership (rule 3) |
| a trait object kept beyond the call: made into a `Dynamic{X}` and stored, returned or put in a collection | yes | follows the user's fields; operations dispatch, with declared results (Dynamic values) |
| passing a trait object where a different trait is expected | no | declare both bounds, so the entry translates for each (rule 2) |
| a trait object anywhere else, as a bare value: passed to an ordinary function, stored or returned bare, `typeof(t)`, a field the trait does not declare | no | code must not depend on the user's type |
| two methods with unrelated trait bounds on one position and no method for both | no | ambiguous for a type with both; checked when the function is defined |
| a method whose function and types the package does not own | no | piracy, rejected when the module is defined (rule 3) |
| arguments of abstract types from ordinary callers: `Any`, `Vector{Any}` | yes | calls on their parts are run-time sites (rule 1); concrete mode reports them |
| abstract types, under concrete mode | no | opt-in: a warning or an error that names the root cause |

**When the prototype checks:**
- rule 2 and the escapes: on typed code, once per method at archetypes when the module is built (Definition checking), and per signature for what that defers, reported with their lines;
- ownership: when the module is defined;
- ambiguous bounds: when it is complete;

## Declaring a trait

```julia
@trait ColTable begin
    ncols(t::ColTable)::Int                                  # an operation: argument types and a result type
    col(t::ColTable, i::Int)::Vector{Float64}
    firstcol(t::ColTable)::Vector{Float64} = col(t, 1)       # a default, written in terms of the others
end
```

**Operations.**
- An operation is a generic function declared at the trait, its first argument the trait itself, as `length(x::AbstractArray)` is declared at an abstract type. A conformance implements it with methods at the implementing type.
- Calls to it are checked: the arguments against the declaration, the result asserted to the declared type.
- An operation may be an existing generic function, such as `Base.length` ([code written without traits](3-wrapping.md#traits-over-existing-functions)).
- A default is written in terms of the other operations and the declared fields, and an implementation may override it. A default never throws "not implemented": a missing operation is an error when the conformance is declared, not when it is called.
- **Defaults over fields are how record-like traits share code.** A conformance that keeps every default has no implementing type, so its key is its declared fields' types: every conforming type with fields of those types runs one worker, compiled in the library's image. A type that overrides an operation becomes the implementing type, and that code compiles once for it, in its own image.

  ```julia
  @trait HDAM{T} begin
      data::Vector{T}                          # a field; its type defines T (T = Float64 for a Vector{Float64})
      mean_data(s::HDAM)::T = mean(s.data)     # a default over the field
  end
  @implement HDAM Sample                       # keeps the default: key (data::Vector{Float64},), shared
  HDAM.mean_data(s::Sorted) = …                # an override by Sorted's owner, a stakeholder
  @implement HDAM Sorted                       # implementing type Sorted: key (Sorted; data::Vector{Float64})
  ```
- **An override belongs to the conformance.** Which operations a conformance serves by defaults is decided when it is declared, and compiled code relies on it. A method of a trait's operation for a type whose conformance already serves that operation by a default is refused when it is defined, naming the fix: define the override before the `@implement`, or inside its block. Plain Julia would call the later method, so accepting it would break "identical or error".
- An operation may mutate its argument. The trait object refers to the user's object, so the user sees the change, as in plain Julia.

**Fields.** A trait may declare fields as well as operations, as a struct declares them. A field is a property:
- `t.name` is `getproperty(t, :name)` and `t.name = x` is `setproperty!(t, :name, x)`, as everywhere in Julia;
- a trait field requires both to work with the declared type;
- following `mutable struct`, a field is writable unless declared `@const` (the macro form of a struct's `const`, which Julia parses only inside a struct).

```julia
@trait Integrator{U, P} begin
    u::U                     # the state: readable and writable, its type an associated type
    @const p::P              # the parameters: read-only
    t::Float64               # the time: writable, a fixed type
end
```

- **Fields are stored fields of the conforming type.** A declared field maps to a stored field of the conforming type, of the same name unless the conformance writes another (`name => label`), also when the type forwards its operations to a field. It is read with `getfield`. A type with a `getproperty` method of its own conforms only with every declared field mapped explicitly, and the conformance says that plain `x.name` may then differ from `t.name`. Computed properties are not declared fields; a conversion is the way (Types that only convert).
- **Field types are part of the key.** A field's type in the conforming type is part of the key, so a worker compiles per state type, whatever else the conforming type holds.
- **A field is a pair of operations.** Reading is `getproperty(t, :name)::String`, writing `setproperty!(t, :name, v::String)`. Scala desugars a trait's `var` the same way, and Swift's protocols require properties `{ get set }`.
- **Field access is narrowed, not opened.** `t.name` is allowed for fields its traits declare, and any other field access is refused. A `Dynamic` value reads and writes its declared fields by dispatch.
- **Every access reads the user's object.** `t.u` is a load at the field's byte offset in the user's object, the offset a value in the view, so a worker compiled per key serves every user type whatever its field order, mutable or immutable. Writing `i.u = v` stores there, as `u.u = v` does in plain Julia. So a read always sees the current value, as every holder of the object does: nothing is held, nothing goes stale, and nothing needs checking.
  - A writable field needs a mutable conforming type, with the field not `const` and declared with exactly the field's type in the key, so that a write never changes a type compiled code relies on.
  - The loads carry the alias information Julia's own field loads carry, so a loop that reads `t.data[i]` while storing into another array vectorizes as in plain Julia (`experiments/lens/layout.md`).
  - An isbits field is stored at its offset; a reference field goes through Julia's `setfield!`, which applies the write barrier.
  - The trait object keeps the user's object alive, so its data cannot be freed under it.
  - The forwarding field is read the same way, so an operation called after the library rebinds a field sees the new value. A forwarding field may also be declared writable.
- **Definition checking covers them.** A trait's archetype has its declared fields with their declared types: readable, and writable unless `@const`.
- **New over Julia.** Julia's abstract types cannot require fields, a long-standing request. A trait can, because conformance is declared and checked.

**Parameters: associated types.** A trait may take parameters, as `AbstractArray{T, N}` does: `@trait ArrayLike{T, N}`, `@trait Integrator{U, P}`.
- **They are associated types:** one value per conformance, functions of what the conforming type holds. A type conforms at one value of each, as a Julia type has one `AbstractArray` supertype.
- **A field defines the parameters its declared type mentions,** by matching the declared type against the conforming type's field type, as Julia matches a `where` clause: `u::U` makes `U` the field's type, and `data::Vector{T}` against a `Vector{Float64}` field gives `T = Float64`. A field type that does not match is refused at the conformance. A parameter is defined by a field or by an equation, never both, which would be an equation between type functions.
- **A trait may define them by a type function** of the implementing type, written `Self` in the declaration: `T = eltype(Self)`. The conformance then need not state them, and a stated value is checked against the definition. Without a definition, the conformance states them: `@implement ArrayLike{Float64, 1} MyVector`.
- **Operations name them:** `Base.getindex(a::ArrayLike{T}, i::Int)::T`.
- **A parameter may be bounded** by a trait or a type, `ArrayLike{T <: NumberLike, N}`, `Integrator{U <: StateVector, P}`, checked at the conformance. A trait bound on a parameter is what lets definition checking cover code that computes with it, and lets library code call the bound's operations on `i.u`.
- **A bound may fix them or leave them open,** `x::ArrayLike{Float64}`. A shared variable, `f(a::ArrayLike{T}, b::ArrayLike{T}) where {T}`, requires equal values.
- **A more specific implementation declares the same values** as a generic one.
- **Not offered:**
  - a type conforming at several values of a parameter (input parameters; `Callable` is the one trait that has them);
  - equations between type functions;
  - a parameter bound that names its own trait.

  These are what made Rust's and Swift's checking hard or undecidable ([design choices §10](2-design-choices.md#10-the-complexity-budget)).

**Supertraits and bundles.**
- `@trait B <: A` makes `A`'s operations and fields part of `B`'s. A type's conformance to `B` must agree with its conformance to `A`, forwarding to the same field or implementing both and mapping the fields alike, so `B`'s operations call `A`'s statically. A later declaration that disagrees is refused at its load.
- A bundle trait names a combination on the library side, `@trait Table <: (ColTable, RowTable)`, so that `summary(t::Table)` needs one bound.

**Concreteness.** A trait may require that its key be deeply concrete: the implementing type and the associated types. That guarantees that whatever conforms becomes concrete with respect to the behaviour the trait carries, and it constrains only what library code sees: the conforming type may hold abstract fields the trait does not declare. It is opt-in, and a trait decides it when it is published: requiring it later breaks conformers whose key is abstract, as adding an operation without a default does.

## How a type conforms to a trait

Every form is an explicit declaration for the type it names. The one-line form covers a type that implements the operations or holds one field that does, with the trait's declared fields under their own names. The written-out forms:
- name the forwarding field, and map declared fields to stored fields of other names;
- give a type operations of its own, called indirectly, at a field's type;
- join several traits;
- implement a trait for a type the author does not own.

Every form defines methods, so ownership says who may write it, and the methods are trait-bound code wherever they are written. The prototype runs the forms for concrete types in an earlier spelling, with the implementing type as the trait's last parameter; parametric families are design.

```julia
# 1. Forwarding, inferred: the one field whose type implements the trait, else the field named data
struct Measurements; label::String; data::Vector{Vector{Float64}}; end
@implement ColTable Measurements

# 2. Methods, inferred: the type implements the operations itself
import Columns: ncols, col
ncols(r::Ramp) = r.n
col(r::Ramp, i::Int) = r.base .* i
@implement ColTable Ramp

# 3. Forwarding written out, when two fields conform; declared fields mapped
struct Halves; left::Vector{Vector{Float64}}; right::Vector{Vector{Float64}}; title::String; end
@implement ColTable Halves by left
@implement Named Halves name => title          # Named declares `@const name::String`

# 4. The operations in one block: an implementation for the type and its declaration. For the
#    author's own type, the same as 2; for a type the author does not own, only the trait's owner
#    (rule 3)
@implement ColTable Ramp begin
    ncols(r) = r.n
    col(r, i) = r.base .* i
end
@implement ColTable Matrix{Float64} begin       # in Columns, or in an extension Columns names
    ncols(m) = size(m, 2)
    col(m, i) = m[:, i]
end

# 5. Several traits at once, each forwarded to the same field
struct Grid; data::Matrix{Float64}; end         # Matrix{Float64} implements ColTable and RowTable
@implement (ColTable, RowTable) Grid

# 6. Operations of the type's own, called indirectly, on its field: the library's worker for the
#    field's type, compiled once
struct Reversed; data::Vector{Vector{Float64}}; end
@implement ColTable Reversed dynamic by data begin
    ncols(d) = length(d)
    col(d, i) = d[end - i + 1]
end

# 7. Existing methods declared for a family, by the trait's owner or Julia: no body
@implement Indexable A where {A <: AbstractVector}
```

Form 4 may be generic over a family of types (Generic implementations). What each form compiles:

| Form | Compiled anew | Operation calls |
|---|---|---|
| forwarding (1, 3, 5) | the field read; the library's code for the field's type exists | static, the field type's implementation |
| the type implements the operations (2, 4) | the library's functions, once for the type | static, direct |
| dynamic operations (6) | the type's own operations | indirect, 7× plain Julia per element on the prototype |
| a family declaration (7) | nothing | the existing methods, static |

**Every check runs at the declaration, never at a call:**
- **Ownership:** the author owns the type or the trait, or is an extension of its owner (rule 3).
- **Concreteness,** for a trait that requires it: the key is deeply concrete, whether it is the type itself, the forwarding field's type, or a declared field's type. A field declared `AbstractVector` is refused with the field named; the fix is a concrete field.
- **Completeness:** every operation has a method or a default for the implementing type, and every declared field maps to a stored field of the conforming type, with the declared types; writable fields on a mutable type, not `const`, with exactly the declared types; the forwarding field not a writable declared field.
- **Fields read as declared:** a type with a `getproperty` method of its own maps every declared field explicitly (Declaring a trait).
- **Precedence:** methods win over a field when a type has both, so writing operations is always deliberate. Several conforming fields need the field named `data` or `by`.

**Implementation and conformance are separate.** A type that implements a trait's operations need not have the trait's declared fields. It then does not conform, but it can be the forwarding field of a type that does: `Vector{Vector{Float64}}` implements `ColTable`, and if `ColTable` declared a field `name`, a bare vector would not conform while a `Measurements` holding one and a name would.

## Generic implementations

An implementation may cover a family of types, or every type that implements other traits. Workers are still compiled per concrete key, so calls stay static.

```julia
# every Indexable type whose elements are Vector{Float64}: a pattern on Indexable's parameter (a sketch)
@implement ColTable A where {A <: Indexable{Vector{Float64}}} begin
    ncols(a) = length(a)
    col(a, i) = a[i]
end
```

With this, `Vector{Vector{Float64}}` implements `ColTable` because it is `Indexable`, and so does any type a user implements `Indexable` for. ColTable follows from the capability traits, through declarations.
- **Membership.** A generic implementation makes its implementing types members, `x isa ColTable`, only for a trait without declared fields; a trait with fields needs each type's own declaration, which maps them.
- **Forwarding carries through.** A user type that forwards `Indexable` to a field forwards `ColTable` to the same field, because the field's type has a `ColTable` implementation, generic or not. The key stays the field's type, and the library's code for it is shared. A user type that implements `Indexable` itself is an implementing type of the generic implementation, and the key is the user type. Predicates are patterns on the constraints' parameters, never conditions computed by functions, so overlap between generic implementations is decided when they are declared.

**Overlap.**
- A more specific implementation beats a generic one.
- The overlap is checked when the specific one is defined: its package depends on the trait's package, so it sees every generic implementation there was.
- Two generic implementations that overlap without one being more specific are rejected.
- A more specific implementation declares the same parameter values as the generic one, so the choice never changes a type.
- An overlap the later package cannot see, as when a trait's owner adds a generic implementation in a later version, is not refused at the load. It surfaces where a call meets both (Named implementations).

## Named implementations

An implementation may be named by its module and used only where a caller names it, and anyone may write one. A package that owns neither the trait nor the type can thus make `Measurements` a `ColTable` for those who ask:

```julia
module Fast                                          # owns neither ColTable nor Measurements
@implement named ColTable Measurements begin … end   # a sketch of the syntax
end
colmean(via(Fast, m), 1)                             # this call uses Fast's implementation
```

- **The choice travels with the value.** A trait object carries its witness, so the implementation is chosen once, at the crossing, the entry stripping `via` as it strips `compiled_call`.
  - Workers are compiled per key and witness.
  - A `Dynamic` keeps the implementation it was made with.
  - A value is never built with one implementation and queried with another, the problem that makes Rust allow one implementation per trait and type.
- **It is not piracy.** A named implementation changes no code that does not name it. Its methods are keyed by a witness type its module owns, and its compiled code lives in its own package, which depends on the trait's and the type's.
- **Unnamed implementations are as before:** written by an owner, the more specific beating the generic. A type is a member of the trait, `x isa ColTable`, through them only.
- **Ambiguity surfaces where it matters.**
  - Two unnamed implementations that apply without one being more specific are reported when the later is defined, if it sees the earlier.
  - Otherwise an unnamed call that meets both raises an error naming both modules and the fix, `via(A, x)`, as Julia asks for `A.f` when two modules export `f`.
  - Code where the earlier choice is more specific keeps working.
- **Equality and printing name the choice.** Two `Dynamic` values of one key with different implementations are unequal, and they print as `ColTable via Fast`.
- **No selection by scope.** A module-wide preference is not offered: an entry is compiled once and does not know its caller's module.

## Several traits, one object

A type can conform to several traits, each through its own field or by its own methods, and a function bounded by several receives one trait object with a view per trait:
- every view reads the same user's object, so the views always agree, and a write through one is seen by the others;
- workers compile per tuple of the views' keys;
- a view is passed on statically to a function with any of the bounds.

`@implement (ColTable, RowTable) Grid` declares both conformances at once. A bundle trait, `@trait Table <: (ColTable, RowTable)`, names the combination on the library side.

## Parametric user types

A parametric type conforms as a family, declared with `where` as Base's families are in form 7, or per instantiation. On a parametric type, the one-line form means the whole family.

```julia
struct Series{T}; data::Vector{Vector{T}}; end
@implement ColTable Series{Float64}                 # one instantiation
@implement ColTable Series{T} where {T <: Real}     # a family forwarding to data: refused here, Columns implements Vector{Vector{Float64}} only; the message names Series{Float64}
@implement ColTable Series                          # the whole family, Series{T} where {T}: the same check
```

The ownership and method checks run at the declaration, for the family as a whole:
- **Forwarding:** the family of field types must be covered by one implementation's family, which subtyping decides. A generic implementation's predicate must be decidable on the family's structure, else the declaration is refused.
- **Methods:** the operations' methods must cover the family, with results that infer to the declared types at the family's signature.
- **Concreteness:** field types may depend on the parameters but are abstract in no other way, so every instantiation with concrete parameters has a concrete key. An instantiation with an abstract parameter, `Series{Real}`, is refused at the entry by its type.
- **A refusal names the instantiations that would conform.**

**Families with associated types.** A family conforms jointly, the trait's parameters tied to the type's: `@implement ArrayLike{T, 1} Series{T} where {T}`.
- **Each member conforms at one value,** so the parameters stay associated types.
- **Membership is subtyping:** `Series{Float32} <: ArrayLike{Float32, 1}`, as `struct MyArr{T, N} <: AbstractArray{T, N}` reads today.
- **Every variable of the trait's parameters occurs in the type,** which is Rust's rule E0207.
- **Parameter expressions are variables, constants and type constructors,** never function calls.
- **The family is checked at an archetype instance,** `Series{ArchT}`, because inference at the family's `UnionAll` gives `Any`.

Workers compile per instantiation, and `verify_main` enumerates the instantiations a program passes.

## Traits as abstract types

A trait reads like an abstract type wherever it is used. Why that is the right choice is in [design choices](2-design-choices.md#1-a-trait-is-an-abstract-type-with-behaviour).

- **In an argument,** `t::ColTable` is a bound: translated at the entry, compiled per key.
- **In a field or a container,** a trait's name means its dynamic value, as an abstract type's name there means a boxed value: `plots::Vector{Plot}` is a `Vector{Dynamic{Plot}}`, and `background::ColorSpec` is a `Dynamic{ColorSpec}`.
- **`Vector{<:ColTable}`** in an argument is a vector whose elements share one key, compiled per key. How a user's vector is passed (element by element into a new vector of trait objects, or as a whole) is open.
- **Membership is subtyping.**
  - `x isa ColTable` is true when the type of `x` conforms through an unnamed implementation.
  - `T <: ColTable` in a `where` clause or a type parameter constrains `T` to conforming types.
  - A conformance thus adds a supertype after the type is defined, which Julia does not allow for abstract types of the other kind. It is sound because only an owner declares it, loaded with the type's or the trait's package. A conformance written at the prompt changes subtyping in the session, as a redefinition there recompiles.
- **Numbers need no trait.** Base's tower of `Number`, `Real` and `Integer` stays. Numbers are ordinary values, trait-world code annotates with the tower as today, and promotion runs on concrete types in Base.

## Dispatch: types first, then traits

**A trait bound ranks above `Any` and below every type** of the other kind (concrete or abstract). A value without a conformance reaches the most specific ordinary method that applies; a value of a type caught by a type-annotated method takes that method and is not translated. How this lets a library adopt traits one function at a time is in [code written without traits](3-wrapping.md#adopting-traits-one-function-at-a-time).

**Among trait bounds:**
- A subtrait beats its supertrait, and more bounds beat fewer.
- Two methods with unrelated bounds on one position, such as `f(t::ColTable)` and `f(t::RowTable)`, need a method for both, `f(t::(ColTable, RowTable))`. This is checked when the function is defined: the check needs only the function's own methods, so no later load can create an ambiguity.

**Where the entry sits.** The entry sits at `Any` in Julia's method table and chooses among the bounds from the registered conformances. That folds for a known type, so caching and AOT are unchanged.

**Code that declares only traits** ranks concrete types first, then traits by refinement. A concrete type is always more specific than a trait, so the two never conflict.

## Definition checking

Library code is checked once, where it is defined, for every conforming type at once.

**Why one check suffices.** A trait object has no methods but its traits' operations and fields, and every operation declares its result type. So a worker's code is the same for every key, except for the operations' implementations, which are checked at their conformance.

**How it checks.** The check infers each bounded method once at archetypes: a stand-in key per bound, whose operations and fields return values of their declared types and nothing more. Rule 2 and the escapes are checked on that code at the library's build. A mistake is reported at its line before any type conforms:

```julia
spread(t::ColTable) = size(t)    # at the library's build: `size` has no method for a trait object carrying ColTable
leak(t::ColTable) = typeof(t)    # `typeof(t)`: code must not depend on the user's type
```

**Parameters have archetypes too.**
- The archetype carries one archetype per parameter variable, built from the parameter's trait bounds.
- A trait's defining equations (`T = eltype(Self)`) get archetype methods, so `eltype` of an archetype is the parameter's archetype, not `Any`.

**Checked per signature instead,** at a worker's first call or while an image is built:
- a parameter left open whose bound is not a trait, `x::ArrayLike{T}` with `T` free or `T <: Real`. With a trait bound, `T <: NumberLike`, the code is checked once, at the parameter's archetype;
- a function from above whose result type is open;
- concrete mode's findings for a trait that does not require concreteness, which depend on its implementations.

**On the prototype** (`TraitWorld/src/defcheck.jl`), the check reuses the worker checks unchanged.
- It finds such mistakes with no conforming type present.
- It checks a library of five functions in under 200 ms in a cold session.
- It takes 3–4 ms off a new key's first call; most of a first call is compilation.
- It still defers keyword, vararg and every `Callable` worker, which the design defers only for open result types.

## Function arguments: Callable

**Why a trait for functions.** Julia has no type for "a function from `Float64` to `Float64`": `Function` says nothing about arguments or results, and a closure's type belongs to the code that creates it, above the trait world. A function handed down from ordinary code therefore enters only at a declared signature: the built-in trait `Callable{A, S}`, with arguments of the tuple type `A` and a result of type `S` (a `Tuple` when there are several).

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
  - **`CompiledCall`** compiles the worker per function type instead, with the function's body inferred into it, in the caller's image: a direct call the compiler may inline, with plain Julia's speed. Such a worker is the library's code compiled outside the library's cache, so a library that makes `CompiledCall` the default gives up cached code for that function by choice. That is why the system default is `DynamicCall`.
  - **The caller overrides** per value with `compiled_call(f)` or `dynamic_call(f)`, wrappers whose type fixes the mode and which the entry strips. The value's type wins, because the library's cache has no stake either way; its users do, which is what the default is for.
- **The mode is a choice of speed, never of correctness.** Both compute what plain Julia computes (rule 1). The library's cache holds nothing compiled for the function in either mode. `DynamicFn{A, S}`, a `Callable` in `DynamicCall` mode as a value of fixed type, made by `dynamic_fn` in ordinary code, is the same choice for a function stored in a library's model or callback types.
- **An open result type,** `Callable{Tuple{Float64}, S} where S`, is inferred at the boundary, in ordinary code. It becomes part of the worker's key and is checked at every call.
- **Functions from the trait world are always compiled calls.** Base's `abs2`, any package's functions, a trait module's own functions, and closures created inside a trait module are called directly. `map`, `filter` and `sum(f, …)` work inside the trait world as today.
- **AOT.** A `Callable` argument names its signature, so a build compiles each function passed at it, and `verify_main` lists them.
- **Several signatures.** A function called at two signatures carries two bounds, `f::(Callable{Tuple{Float64}, Float64}, Callable{Tuple{Int}, Int})`.
- **Cost.** A dynamic call costs about 4 ns per call on the prototype.

## Keyword, default and variable arguments

Keyword, default and variable arguments work as in plain Julia, with one placement rule: a default is trait-world code, evaluated in the worker after translation, never at the entry. The prototype runs keyword and optional arguments in trait-bounded functions.

```julia
@trait_module module Columns
export colmean, colzscore

colmean(t::ColTable, i::Int = 1) = sum(col(t, i)) / length(col(t, i))   # colmean(t) calls colmean(t, 1) inside

# a bounded keyword that defaults to a trait object the worker holds, and a typed keyword with a constant default
colzscore(t::ColTable, i::Int; baseline::ColTable = t, tol::Float64 = eps()) =
    (col(t, i) .- colmean(baseline, i)) ./ max(colstd(baseline, i), tol)
end

colzscore(m, 1)                     # one worker: baseline is t, tol is eps(), both filled inside
colzscore(m, 1; baseline = r)       # r is translated for ColTable at the entry, as a positional argument would be
colzscore(m, 1; tol = 1)            # an error at the entry: tol is declared Float64, as in plain Julia
```

- **Defaults are evaluated inside,** in the worker, after translation. So `baseline = t` sees the trait object, and `i = ncols(t)` may call an operation. A positional default is what Julia makes of it: a shorter exported method whose body calls the full one with its own trait object.
- **The entry translates, the worker sorts.** The entry translates every bounded argument, positional or keyword, and passes the supplied keywords on as a named tuple. The worker fills the defaults and calls the body. The sorter is compiled per set of supplied keywords, by name and type, and the body once per full signature, as Julia does it.
- **A keyword is typed like a positional argument:** by a trait bound, a declared type, or the value supplied. A bounded keyword without a default is required.
- **No dispatch on keywords,** as in plain Julia. A trait bound on a keyword translates and restricts; it chooses no method.
- **A default for a bounded parameter** is a trait object of that trait, or a value of a type that conforms. Its type is inferred when the worker is compiled.
- **Functions from above with keywords.** `Callable{A, S, M, K}` names them in a fourth parameter, a named tuple type: `Callable{Tuple{Float64}, Float64, DynamicCall, @NamedTuple{tol::Float64}}`.
- **AOT.** Each set of supplied keywords is a signature, so `verify_main` lists the sets a program passes.
- **Varargs.** A vararg is several crossing points with one bound, read per element as plain Julia reads `xs::Int...`. A vararg of trait objects is compiled per tuple of keys.

## Functions that cross the boundary

A function is code, and code never crosses. A function from above enters only as a `Callable`. The remaining cases follow from the direction of the crossing.

```julia
colfun(t::ColTable, i::Int) = x -> x * colmean(t, i)      # returned up: a trait-world closure, called from above on Float64
scaler(t::ColTable) = (u::ColTable) -> meandiff(t, u, 1)   # a bounded closure: it has an entry, so the caller passes its own objects
colmaker(f::Callable{Tuple{Int}, Callable{Tuple{Float64}, Float64}}, t::ColTable)   # a function from above that returns a function
tables(f::Callable{Tuple{Int}, ColTable}, n::Int)          # a function from above that returns tables: each result translated
```

- **Functions returned up** are closures of the trait module and go up as themselves. A closure keeps the trait objects it captured as a `Dynamic` keeps them: following the user's fields where they can be rebound, holding them where they cannot, and keeping the user's object alive. To take the caller's own objects it needs a bound in its signature, and a bounded signature has an entry.
- **Results of a function from above** are values crossing downward, so the result bound translates them as an argument's bound would.
- **Trait objects never go up bare.** What goes up is what operations return, ordinary values, and a trait object only inside a `Dynamic` value.
- **AOT.** A returned closure has a type of the trait module, so calls to it from ordinary code are calls into the trait world that `verify_main` lists.

## Results like the input

A function that returns "a table like the input", such as `similar(x)` or `map` over a user's container, needs two things the trait world does not have by itself:
- **a new value of the implementing type,** which is a constructor operation in the trait;
- **the way back to the user's type,** which is the conformance's inverse.

So the boundary translates in both directions.

```julia
@trait ColTable begin
    ncols(t::ColTable)::Int
    col(t::ColTable, i::Int)::Vector{Float64}
    withcols(t::ColTable, cs::Vector{Vector{Float64}})::Self     # a table of the same kind, holding these columns
end

colmap(f::Callable{Tuple{Float64}, Float64}, t::ColTable)::Like{t} =        # a sketch of the syntax
    withcols(t, [map(f, col(t, i)) for i in 1:ncols(t)])

colmap(x -> 2x, Measurements("run 1", [[1.0, 2.0]]))      # a Measurements, label kept, data replaced
```

- **Constructor operations return `Self`,** a new value of the implementing type.
  - It is implemented per implementing type and checked at the conformance like any other operation.
  - At an archetype it returns the archetype, so definition checking covers code that uses it.
  - This is Rust's `-> Self` and Swift's `init` requirements in protocols. Rust excludes such methods from `dyn Trait`; here an operation on a `Dynamic` value that returns `Self` returns a `Dynamic` value of the same conformance.
- **A result like the input is a pending value.** Inside, `like(t, x)` replaces the implementing value with `x`, and `withfields(t; u = …)` replaces declared fields; both together for a trait with operations and fields, and `withfields` alone for a trait with fields only, such as `Integrator`. Nothing operates on the result; it carries the input's conformance and the new parts, and only the entry inverts it. A body declared `::Like{t}` returns `Self`, which is read as `like(t, x)`.
- **The conformance inverts itself.** Only the conformance knows the user's type:
  - **A type that implements the operations:** the new implementing value is the result, and it must be of the same type: a `Series{T}` that implements a trait itself cannot come back as a `Vector{Float32}`.
  - **Otherwise** the result is the user's object rebuilt with the mapped fields replaced, for immutable and mutable types alike, as ConstructionBase.jl's `setproperties` and Accessors.jl's `@set` do today. The type's constructor rebuilds it, so its parameters follow the new fields; a type whose inner constructors take other arguments writes the constructor the inverse calls, and the declaration says so.
- **The entry translates on the way out.** A result declared `Like{t}` must be built from `t`; the check runs at the definition, at archetypes.
  - The worker, compiled per key, computes the new parts.
  - The entry applies `t`'s inverse and returns a value of the caller's type.
  - The inverse is compiled per user type, in the conformer's image, so library code still never depends on the user's type.
  - Called with a `Dynamic` value, the function returns a `Dynamic` value of the same conformance.
- **Copying needs no trait of its own.** `copy(t)` is a constructor operation that copies the implementing value, followed by the inverse.
- **AOT.** The inverses are listed with the conformances, one per conformance a program passes.
- **Changing the key's type** is the hard case: `similar(x, Float32)`, or a `map` whose result has another element type. A constructor operation may return a sibling of the implementing type, the same family at another parameter value, and the inverse rebuilds the user's type at that value: a `Series{Float32}` from a `Vector{Vector{Float32}}` in its field. A family conformance (Parametric user types) makes the sibling conform too. The same mechanism makes dual-number caches for automatic differentiation and keeps GPU arrays on the device.

**Precedents in Julia:**
- Tables.jl's `materializer(table)` returns a function that builds a table of the input's type from columns.
- Base's `similar` is the implementing type's half.
- ConstructionBase.jl and Accessors.jl provide the inverse of a forwarding field.

## Types that only convert

A type whose data a library can use only after a conversion (a lazily derived table, a foreign table in another layout, a table typed by its schema) does not conform by a field. The library converts it explicitly, through a trait that reads any table, and then runs its cached code on the result:

```julia
@trait TableLike begin                                  # what a converter reads
    columnnames(t::TableLike)::Vector{Symbol}
    column(t::TableLike, n::Symbol)::AbstractVector      # not concrete: this bound only converts
end
materialize(t::TableLike)::Vector{Vector{Float64}} = [Float64.(column(t, n)) for n in columnnames(t)]
colmean_any(t::TableLike, i::Int) = colmean(materialize(t), i)   # the conversion, then the library's cached worker
```

- **What it costs:** a copy; the conversion compiled per key of `TableLike` (one per foreign type, or per schema for tables typed by their schema), but the library behind it compiled once; no `Like{t}`, because the result is the library's own type; no write-through.
- **What it replaces:** the computed projections of the earlier design, which did the same implicitly at the boundary, and so hid the copy and needed a written inverse.

## Dynamic values

A trait object lives for one call. A value that must outlive the call, or an element of a collection whose elements have different keys, or a field whose key changes, is a `Dynamic{X}`: a value of any type conforming to `X`, reached through `X`'s operations and fields. A trait's name in a field or a container means its `Dynamic` (Traits as abstract types).

```julia
struct Scene
    plots::Vector{Plot}                        # Vector{Dynamic{Plot}}: plots of any conforming type
    background::ColorSpec                      # Dynamic{ColorSpec}: :white now, an image later
end
add!(s::Scene, p::Plot) = push!(s.plots, p)    # an argument: a bound; stored, it becomes a Dynamic{Plot}
render(s::Scene) = foreach(draw, s.plots)      # draw(p::Plot): one dispatch per plot, then compiled per key
```

- **Made at a bound or by storing.**
  - A bound in a field, a container or a result translates the value and keeps the trait object.
  - Inside, storing a trait object of `X` where an `X` is declared keeps it, as Julia converts a value stored in a typed field; `Dynamic{X}(t)` does so explicitly.
  - Nothing else makes one, so its type decides it: the entry admits it by its type.
- **Which functions receive the whole object.** A function whose code may keep a trait object (make it a `Dynamic`, store it where a `Dynamic` is declared, or return a closure that captured it) receives the whole user's object at its entry. Every other function receives only what its bounds see, held for an immutable type. Which functions keep is decided where they are defined, from their code at archetypes, as definition checking decides the rest; when the analysis cannot tell, the function keeps, which costs only a box. (On the prototype: typed calls of functions that do not keep are unchanged, 33 ns against 30 ns plain; a keeping function pays about 55 ns and 32 bytes per call for an immutable type.)
- **Kept values follow the user's fields.** A `Dynamic` keeps the trait object, which is the user's object with its views, so it sees the user rebind any field, as every holder of the object does in plain Julia, and writes through it reach the user's object. It runs the same workers as a fresh call, because the layout is the same.
  - **The user's object stays alive** as long as the kept value.
  - **Equality.** A kept value compares and hashes by the identity of the user's object for a mutable type and by its value otherwise, with the conformance, as Julia compares the objects themselves.
  - **Serialization.** It serializes the user's object with its conformance.
- **Operations dispatch.** An operation of `X` on a `Dynamic{X}` dispatches on the trait object inside, in the caller's world, and asserts the declared result type, so code after the call infers. Its targets are the conformances of `X` whose types reach a place where a `Dynamic{X}` is made: rule 3 closes them, a build lists them, and `verify_main` counts the calls as bounded.
- **Opened by a bound.** Passed to a function bounded by `X`, a `Dynamic{X}` selects the worker for its key once, and the worker runs compiled.
  - A loop over its data belongs in such a function; concrete mode reports operations on a `Dynamic` inside a loop and names that fix.
  - Two `Dynamic` arguments select a worker per pair of keys.
- **Parameters.** A `Dynamic` of a parametric trait fixes the parameters its operations' result types use, `Dynamic{ArrayLike{Float64, 1}}`, so code after a call infers.
- **Equality.** Values of different keys, or different implementations, are unequal. Otherwise the trait's declared `==` decides, or, without one, `===` of the user's objects, so `:red` equals `:red` and arrays compare by identity. `hash` agrees.
- **Several traits.** `Dynamic{(ColTable, RowTable)}` holds a trait object with both views and converts explicitly to `Dynamic{ColTable}`. `Dynamic{Sub}` converts to `Dynamic{Super}`, whose view comes with the subtrait's conformance. A `Callable` in `DynamicCall` mode is already the dynamic value of a function.
- **Up and down.** A `Dynamic` is a value of its own type: it goes up as one, inside other values or bare, and comes back down admitted by its type. Code above may hold and pass it, and defines nothing that trait-world code reaches through it.

A `Dynamic` costs an allocation when made, and a dispatch per operation: about 20–80 ns in a measurement of Julia's dispatch on boxed values. First calls from package images need no compilation.

**What a field access costs** (`experiments/lens/layout.md`, stock Julia 1.13.2; loads and stores with Julia's alias metadata through `llvmcall`, as a runtime would emit them):
- **Loops:** the same as plain Julia, per element, for reductions, loops storing into another array, and field writes per iteration.
- **Per call:** about 2 ns more than plain Julia for a short call reading three fields and writing one (2.9 against 0.9 ns), against a fixed entry cost of about 215 ns.
- **Without the alias metadata** a loop that stores into another array loses vectorization, 5× (0.64 against 0.13 ns per element), so the metadata is part of the design, not an optimization.
- **A reference field written** goes through `setfield!` and its write barrier, about 10.7 ns.

A field stored inline that is not isbits, an immutable struct holding references, is read through Julia's `getfield` and costs more; GPU kernels cannot take the user's object and need a layout that copies the fields, opt-in per trait and valid only for traits without writable fields.

## Caching: compiled once, reused everywhere

Cached code is reusable because it is compiled per key, for what a bound can see, not per type. It survives because it holds only concrete facts: only a stakeholder of one of them, or a pirate that wins there, can change it (rules 1 and 3).

```julia
using Columns                                   # Columns' workers come from its package image
struct Mine; data::Vector{Vector{Float64}}; end
@implement ColTable Mine                        # forwards to its field: no new library code
colmean(Mine([[1.0, 2.0]]), 1)                  # runs the compiled worker
using CairoMakie                                # a stakeholder of none of Columns' facts: changes none of its code
```

- **Per key.** `Mine` shares its key with every type that forwards to a `Vector{Vector{Float64}}`, so `colmean` runs code that Columns compiled when it was built. On the prototype, the first calls at a new key take 10–60 ms, mostly compilation. Caches per key reduce them to about 3 ms in every load order (`experiments/interfaces/README.md`, view caches).
- **Compiled against facts.** Each specialization holds facts at concrete signatures only (rule 1).
  - A later definition by a stakeholder of a fact recompiles it, as in plain Julia.
  - A definition elsewhere, for the definer's own types, never applies at a fact (Lemma O).
  - A pirate that wins at a fact recompiles it to follow the pirate, as plain Julia does; one that loses changes nothing, in any load order.
- **Every combination has an owner image.**
  - The entry lives in the trait module's package image; the field read and a worker at a new key live in the conformer's.
  - Code for packages that meet only in an application lives in a package extension or the application, and the session comes last.
  - Each piece is compiled where it lives, because a downstream image cannot add native code to an upstream one.
- **Abstract calls dispatch at run time.** A call in compiled trait-world code whose argument types are not concrete records nothing and dispatches in the current world, as plain Julia's dynamic dispatch does. It computes what plain Julia computes, and no load can invalidate it.

## AOT: the reachable code is declared

Dispatch between trait-world code, and over the types a program meets at run time, goes through conformances, whose targets are listed. A build can therefore compile exactly the trait-world code the program can reach.

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

**Here the list exists** for what trait-world code dispatches over:
- a function passed as a `Callable` argument adds one target at its declared signature;
- a `Dynamic` value adds the conformances whose types reach the place it is made.

**Plain code reached from trait code** (CSV, Cairo, ForwardDiff, Base's printing) has plain Julia's AOT properties. `verify_main` walks into it and reports its open dynamic sites as holes. A package whose normal path dispatches openly is as hard to trim from trait code as from plain Julia. Cairo, mostly `ccall`, should be closed; CSV and DataFrames are the hard case.

**What a build compiles.** A `--trim` build compiles the plain call: native inference in the closed world, not the policy's code.
- Native inference in the closed world is plain Julia, so "identical or error" holds by definition, and nothing loads in a binary, so there is no cache to protect.
- Native inference may use abstract facts over the build's methods, which closes sites the policy would leave dynamic.
- The binary's baseline is plain juliac. Values decided by inference (A3) can differ between the session, which runs under the policy, and the binary.
- A pirate lint is planned: `verify_main` lists the calls reached from trait code that select a pirate, and can fail the build.

**On the prototype,** `verify_main` enumerated the entries' targets from the types a program can pass (8 targets), and the program compiled to a 2.09 MB trimmed executable; without the list, the binary died at its first trait call. That binary predates keys and wrapping by facts, and is to be rebuilt. One risk is untested: `--trim` is not among the flags that key package images, so an image built without it could carry entries generated for the policy into a trimmed build.

## Performance: no cliffs

Four cliffs disappear by construction, and the fifth becomes a report at build time.

- **Loads do not change speed.** Compiled trait-world code holds concrete facts only, so an unrelated load changes none of them (Theorem 2). A call at abstract types is a run-time dispatch from the start, so no load can push inference over `max_methods` and turn a fast call dynamic.
  - The price: a call that plain Julia infers through at an abstract signature is a run-time dispatch here. In the demonstrators such calls lie on cold paths.
  - `return_type` is plain Julia's question. It folds at compile time when the answer rests on concrete facts, and is answered at run time otherwise.
- **Types cannot multiply compile cost.** Code compiles per key, not per user type, unless the type implements the operations itself. A type that forwards to a field of a known type adds no compiled code; a type that implements the operations compiles the library once for itself, by its own choice.
- **Nothing recompiles under you.** Only a stakeholder of one of its facts, or a pirate that wins at one, invalidates trait-world code (Theorem 2). On the prototype, twelve package loads, before or after the trait code, invalidated none of it. A compiled-call worker, which lives in the caller's image, and code redefined at the prompt recompile as today.
- **Trait operations cost nothing.**
  - Implemented per type, they are direct calls that the compiler may inline. On the prototype, library code making one operation call per element ran at 1.00–1.01× plain Julia at 4096 elements, and through a generic implementation at 1.00–1.03×.
  - The entry adds a fixed cost per call: on the prototype, a typed trait call takes 37–39 ns against 30 ns plain.
  - Only dynamic operations, dynamic calls and operations on `Dynamic` values are indirect.
- **Abstract types in hot loops are found at their root cause.** Code in a trait module sees only its keys (deeply concrete where its traits require it), declared fields and operation results asserted to their declared types. An abstract value in a hot loop can therefore only come from a trait that does not require concreteness, from the module's own code, or from the code it calls. Concrete mode traces it there, through any number of layers.

```julia
@warn_on_abstract @trait_module module CTop
using CBottom: Config                  # a trait module; Config has a field declared Real
using CMid2: factor                    # factor reaches that field through two packages

@trait Series begin
    vals(s::Series)::Vector{Float64}
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

> **A trait-world call computes exactly what plain Julia computes in the current world, with the same effects, or raises.**

**Why it holds** (Theorem 1 of `writeup/explorations/wrapping-by-facts.md`). Every valid compiled trait-world CodeInstance has all its facts true in the current method table:
- compilation records only true facts;
- a definition, deletion or redefinition changes dispatch only where it applies and wins, and Julia's invalidation removes exactly the code with a fact there (nothing is skipped);
- a package image's code is admitted only if its facts hold at load;
- run-time sites and pointer calls record nothing and run plain Julia's dispatch or plain Julia's code.

It depends on no declaration: a wrong performance setting, such as a `Callable`'s mode, can make code slow, never wrong.

**Pirates are followed.** A pirate defined before or after the trait code is compiled gives what plain Julia gives:

```julia
using MyTable                         # MyTab conforms; Stats' worker calls weight(::Float32); Stats has weight(::Real)
colsum(MyTab(Float32[1, 2, 3]))       # the worker holds the fact: weight(::Float32) selects Stats' weight(::Real)
using Pirate                          # defines Stats.weight(::Float32), owning neither: a pirate that wins there
colsum(MyTab(Float32[1, 2, 3]))       # the fact is broken, the worker recompiles: what plain Julia computes, with the pirate
```

Loaded before `MyTable`, the pirate is in the method table when the worker compiles, and the first call follows it. In the optional strict mode, loading `Pirate` after the first call is refused, naming its method and Stats' worker; loaded before, it is followed as here ([code written without traits: strict mode](3-wrapping.md#strict-mode-an-option)).

**Assumptions** (beside Julia's compiler being sound for the facts it records, and never under-invalidating):
- **A3: values decided by inference precision.** `return_type`, `promote_op`, and the element types of empty `map`s, broadcasts, comprehensions and LinearAlgebra destinations are answered by inference. Plain Julia itself answers them differently in different contexts: `return_type(pass, Tuple{Type{Int}})` is `Type{Int64}` at run time and `DataType` once folded. The policy matches plain Julia wherever it can do so without invalidating more code. It can differ through what inference decides: `Union{}` where every method at a run-time site throws, or a nested `return_type` in a callee.
- **A4: no concurrent definitions.** No method is defined on another thread while trait code is being compiled. Julia piece 11 removes this assumption.
- **A5: the generator.** The entry relies on Julia caching nothing when a generator throws, on re-entry and beyond 8 nested generations.

**An open `Callable` result type,** inferred at the boundary in ordinary code, depends on what is loaded there. It is part of the worker's key and checked at every call.

**Kept values.** A value kept in a dynamic value keeps the user's object, which is what a plain-Julia holder of the object sees.

## Possible extensions

- **Inline entries.** Callers that already know the type inline the conformance lookup and call the worker directly.
- **Concrete mode by default.** Warnings for every worker, so the cliff is caught before anyone opts in.

## Open points

Collected with the prototype's and the runtime's open items in [`writeup/open-issues.md`](../open-issues.md); the decisions taken are in [`writeup/decisions.md`](../decisions.md).
