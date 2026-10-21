# Traits: the reference

This page defines the trait language: its syntax, what each form means, what is checked and when, and the rules, as user code sees them. It describes the language as designed, including the parts not built yet. Where TraitWorld, the prototype, does something else today, the [Deviations](#17-deviations) table at the end says so.

- For a tutorial that builds one example step by step, read [Traits by example](../intro/traits-by-example.md).
- For why traits, and what they buy, read [Traits for Julia](../intro/traits-for-julia.md).
- The terms (trait, implementation, trait object, kept value, `Compiled`, `Dynamic`, key, stakeholder, pirate) are explained in the [glossary](../glossary.md).
- The other references: what compiled code may assume, in [`facts.md`](facts.md); how each construct is built on Julia, in [`lowering.md`](lowering.md); the Julia interfaces both rely on, in [`compiler.md`](compiler.md).

**Status labels.** Every section ends with one:
- **Implemented:** TraitWorld accepts it today, on the patched Julia 1.13.2 it needs.
- **Planned:** decided, not built.
- **Optional:** built only if a measurement or a demonstrator asks for it.
- **Open:** not decided. The link names the question in [`../open-issues.md`](../open-issues.md).

A rule in an Implemented section is enforced, unless the Deviations table lists it. A Planned form is written as it will be. Writing it today is refused, unless the Deviations table says otherwise.

## Contents

1. [Syntax summary](#1-syntax-summary)
2. [Trait modules](#2-trait-modules)
3. [Trait declarations](#3-trait-declarations)
4. [Implementations](#4-implementations)
5. [Bounded functions](#5-bounded-functions)
6. [Values in trait code: `Compiled` and `Dynamic`](#6-values-in-trait-code-compiled-and-dynamic)
    1. [The attribute](#61-the-attribute)
    2. [How plain values enter the trait world](#62-how-plain-values-enter-the-trait-world)
    3. [Defaults: a trait's default, and annotations](#63-defaults-a-traits-default-and-annotations)
    4. [Casts](#64-casts)
    5. [Values carry](#65-values-carry)
    6. [Items of a user's container](#66-items-of-a-users-container)
    7. [What `Compiled` code is compiled for](#67-what-compiled-code-is-compiled-for)
    8. [Costs, and choosing](#68-costs-and-choosing)
7. [Kept values: `Dynamic{X}`, `Compiled{X}`, `Kept{X}`](#7-kept-values-dynamicx-compiledx-keptx)
8. [Collections](#8-collections)
9. [Checks, and when they run](#9-checks-and-when-they-run)
10. [Who may implement; pirates; strict mode](#10-who-may-implement-pirates-strict-mode)
11. [Concreteness and concrete mode](#11-concreteness-and-concrete-mode)
12. [Printing](#12-printing)
13. [Compiling ahead](#13-compiling-ahead)
14. [Membership](#14-membership)
15. [Named implementations](#15-named-implementations)
16. [Status index](#16-status-index)
17. [Deviations](#17-deviations)

---

## 1. Syntax summary

The grammar below is the language as designed. `X?` is optional, `X*` repeats zero or more times, `|` separates alternatives, quoted text is literal. `Name`, `Type` and `Expr` are Julia names, type expressions and expressions.

```ebnf
(* where trait code lives *)
TraitModule    ::= FullyTyped? "@trait_module" "module" Name Statement* "end"
                 | "@trait_module" "begin" Statement* "end"
FullyTyped     ::= "@warn_not_fully_typed" | "@enforce_fully_typed"      (* concrete mode *)
Concrete       ::= ( "@enforce_concrete_only" | "@warn_on_abstract" ) Name*   (* names: parameters, Self, bounded arguments *)

(* declaring a trait *)
Trait          ::= "@trait" Name Params? ( "<:" Supertraits )? ( "begin" TraitItem* "end" )?
Params         ::= "{" Param ( "," Param )* "}"
Param          ::= Name ( "<:" ( Type | TraitExpr ) )?
Supertraits    ::= TraitExpr
TraitItem      ::= Operation | Operation "=" Expr          (* an operation; a default *)
                 | "@const"? Name "::" Type                 (* a declared field *)
                 | Name "=" Expr                            (* an equation: a parameter as a function of Self *)
                 | Concrete                                 (* concreteness of parameters and Self *)
                 | "@default_with_dynamic_self" | "@default_compiled_for_self"   (* the trait's default attribute *)
Operation      ::= OpName "(" Name "::" Receiver ( "," OpArg )* ")" "::" Type
OpName         ::= Name | Module "." Name
Receiver       ::= TraitName | TraitName "{" Type ( "," Type )* "}" | "Self"
OpArg          ::= Name "::" Type | "::" Type | Name
TraitRef       ::= TraitName ( "{" Type ( "," Type )* "}" )?
TraitExpr      ::= TraitRef | CallableRef | "(" TraitExpr ( "," TraitExpr )* ")"   (* a trait; a tuple of traits is one (§3.7) *)
CallableRef    ::= "Callable" "{" TupleType "," Type "}"

(* joining a trait *)
Implementation ::= "@implement" Traits Target How?
Traits         ::= TraitRef | "(" TraitRef ( "," TraitRef )* ")"
Target         ::= Type                                              (* one type *)
                 | Type "where" "{" TypeVar ( "," TypeVar )* "}"      (* a family *)
                 | Name "where" "{" Constraint ( "," Constraint )* "}" (* a generic implementation *)
Constraint     ::= Name ":" TraitRef | Name "<:" Type | Expr
How            ::= "begin" MethodDef* "end"                          (* the operations' methods *)
                 | "by" FieldName ( "," FieldMap )*                  (* forwarding *)
                 | FieldMap ( "," FieldMap )*                        (* fields under other names *)
FieldMap       ::= FieldName "=>" FieldName

(* using a trait, inside a trait module *)
Method         ::= FullyTyped? Concrete? Name "(" Arg* ( ";" KwArg* )? ")" ( "::" Result )? ( "where" TypeVars )? "=" Expr
Arg            ::= Name "::" Bound | Name "::" Type | Name
                 | Arg "=" Expr                                      (* a positional default *)
                 | Name "::" TraitExpr "..."                         (* a vararg of trait objects *)
KwArg          ::= ( Name "::" Bound | Name "::" Type | Name ) ( "=" Expr )?
Bound          ::= TraitExpr | Attribute "{" TraitExpr "}"
Attribute      ::= "Compiled" | "Dynamic"
ItemParam      ::= TraitExpr | Attribute "{" TraitExpr "}"     (* a bound's parameter naming a trait: an item position *)
Result         ::= Type | "Like" "{" ArgName "}"
Struct         ::= "mutable"? "struct" Name ( "{" StructParam ( "," StructParam )* "}" )? StructBody "end"   (* StructBody: Julia's fields *)
StructParam    ::= Name | Name "<:" Type | Name "<:" TraitExpr     (* the last: bounded by a trait *)

(* values *)
KeptType       ::= KeptForm "{" TraitExpr "}"
KeptForm       ::= "Dynamic" | "Compiled" | "Kept"
Cast           ::= "compiled_for" "(" Expr ")" | "with_dynamic" "(" Expr ")"

(* planned *)
FamilyForward  ::= "@implement" Traits Type "by" FieldName "where" "{" TypeVar* "}"
KwCallable     ::= "Callable" "{" TupleType "," Type "," NamedTupleType "}"
OpenResult     ::= Name "::" "Callable" "{" TupleType "," Name "}" "where" Name
BoundedClosure ::= "(" Name "::" TraitExpr ")" "->" Expr
Membership     ::= Expr "isa" TraitExpr | Type "<:" TraitExpr
NamedImpl      ::= "Via" "{" Name "}" "(" Expr ")"
```

A tuple of traits is in the grammar wherever a trait is (`TraitExpr`); where it is built yet: [§3.7](#37-tuples-of-traits).

**Status:** Implemented, except the forms under `(* planned *)` (Planned). TraitWorld also accepts forms that are not in this grammar: [T-12](#17-deviations) to [T-15](#17-deviations), and an unnamed receiver ([T-36](#17-deviations)).

---

## 2. Trait modules

```julia
@trait_module module Geometry
using TraitWorld
# traits, implementations, bounded functions, ordinary code
end
```

Inside an existing module, such as a package's own module file:

```julia
module MyPackage
using TraitWorld
@trait_module begin
    # …
end
end
```

**Meaning.**
- A trait module is a module whose code is written against traits. Its code is *trait code*. All other code is *plain code*.
- **Loading another package does not discard a trait module's compiled code,** except a change by a stakeholder of code it depends on, or a pirate that wins there; strict mode refuses the pirate ([§10.3](#103-strict-mode)). Julia compiles trait code in its *facts mode*: a call whose argument types are not all known is dispatched when it runs, never guessed at. What compiled code may assume, and why: [`facts.md`](facts.md#the-facts-mode).
- Submodules of a trait module are trait modules.
- `@trait_module` runs each top-level statement after the ones before it. So a trait is known when a later function definition mentions it. `include` passes the same treatment on to the included file.

**Rules.**
- Bounded functions ([§5](#5-bounded-functions)) exist only inside trait modules. Outside, a method with a trait's name as an argument's type is refused when it is defined (`TraitUseError`), now and with traits in the type system. Outside trait modules a value is taken as a kept value (`Kept{X}`) or by a type.
- `@trait` and `@implement` work in any module. A user's types usually conform in plain code.
- A trait module may use and call any Julia code: Base, CSV, Cairo, ForwardDiff.
- At the end of a trait module, its bounded functions are checked ([§9](#9-checks-and-when-they-run)).
- A trait module may not define a pirate ([§10.2](#102-pirates)).
- A package is an ordinary module around its trait module. The package's own `module` line cannot carry `@trait_module`, since TraitWorld is not loaded yet there. Write `include("Core.jl")` with a `@trait_module module Core … end` inside, or a `@trait_module begin … end` block after `using TraitWorld`.

A prefix sets concrete mode for every function in the module ([§11](#11-concreteness-and-concrete-mode)): `@warn_not_fully_typed @trait_module module M … end`, or `@enforce_fully_typed`.

**Status:** Implemented. Whether a trait module keeps refusing every pirate is Open ([open issues §1.20](../open-issues.md#1-decisions-waiting-for-the-user)).

---

## 3. Trait declarations

```julia
@trait Shape begin
    area(s::Shape)::Float64
    perimeter(s::Shape)::Float64
    summary(s::Shape)::String = "a shape of area $(area(s))"     # a default
end
```

**Meaning.**
- `@trait X` declares the trait `X`, a kind of abstract type with its own rules: a type joins it by an implementation, after the fact, and may join several ([§14](#14-membership) compares it with an abstract type).
- The body declares what a value must provide to conform: operations, fields, and the values of the trait's parameters. It may also declare the trait's default attribute (`@default_with_dynamic_self` or `@default_compiled_for_self`, [§6.3](#63-defaults-a-traits-default-and-annotations)) and its concreteness ([§11](#11-concreteness-and-concrete-mode)).
- A trait without a body bundles other traits ([§3.6](#36-supertraits-and-bundles)).
- Declaring a trait defines no method on any user type and changes no compiled code.

**Status:** Implemented. Each subsection has its own status.

### 3.1 Operations

```julia
ncols(t::ColTable)::Int
col(t::ColTable, i::Int)::Vector{Float64}
Base.length(t::HasLength)::Int                     # an existing function
Base.iterate(t::Iterable)::Union{Nothing, Tuple{eltype(Self), Any}}
Base.iterate(t::Iterable, state)::Union{Nothing, Tuple{eltype(Self), Any}}
```

- An operation is a generic function with declared argument and result types.
- **The first argument is the value seen through the trait.** Type it with the trait's name (`t::ColTable`), the trait with parameters (`v::KVec{T}`), or `Self`.
- **Every operation declares its result type.** A declaration without one is an error.
- Further arguments are typed as in a method: `i::Int`, `::Int` (no name), or untyped (`state`, which means `Any`).
- A plain name (`ncols`) creates a new function in the trait's module. A qualified name (`Base.length`) uses that existing function.
- One operation may be declared at several arities (`iterate` above), not twice at the same arity.
- The declared types may name the trait's parameters and `Self` ([§3.4](#34-parameters-and-associated-types), [§3.5](#35-self)).
- An operation may mutate its arguments. A trait object refers to the user's object, so the change is visible to the user, as in plain Julia. No annotation marks such an operation.
- **An argument declared `Dynamic{Y}`, `Compiled{Y}` or `Kept{Y}` is a type, as in a method:** the operation receives such a kept value ([§7](#7-kept-values-dynamicx-compiledx-keptx)), for example `condition(cb::Callback, …, integ::Dynamic{IntegratorView})::Bool`. What a value passed there becomes is the table of [§6.3](#63-defaults-a-traits-default-and-annotations). Only a bounded function's own arguments are bounds ([§5.1](#51-bounds)).

**What is checked.**
- At each implementation: every operation has a method, or a default, for the type it is called on, and the method's result infers to the declared type ([§4.9](#49-checks-at-the-declaration)).
- At every call on a trait object or a kept value: the arguments against the declaration; the result is asserted to the declared type.

**Status:** Implemented.

### 3.2 Defaults

```julia
firstcol(t::ColTable)::Vector{Float64} = col(t, 1)
```

- A default is an operation with a body, written in terms of the trait's other operations and fields.
- The trait's parameters are in scope in the body: `state(m::M{T}, u0)::Vector{T} = Vector{T}(u0)`.
- An implementation keeps it, or overrides it with its own method. Which one is fixed when the implementation is declared ([§4.9](#49-checks-at-the-declaration)).
- A default never throws "not implemented". An operation without a default must be implemented, and its absence is an error at `@implement`.
- A default serves trait objects and kept values. It is not a method of the conforming type, so plain code calling the operation on the type directly finds no method ([§4](#4-implementations)).

**Status:** Implemented, except the trait's parameters in a default's body (Planned; [T-2](#17-deviations)), and an existing method of the type for an operation that a block leaves out ([T-32](#17-deviations)).

### 3.3 Fields

```julia
@trait Integrator{U, P} begin
    u::U              # writable
    @const p::P       # read-only
    t::Float64        # writable, of a fixed type
end
```

- A declared field is a stored field the conforming type must have: same name (unless mapped, [§4.4](#44-field-mappings)), and the declared type.
- `t.name` reads it and `t.name = x` writes it, inside bounded code. Code may read and write only the fields its traits declare.
- `@const` makes a field read-only. It is the macro form of a struct's `const`.
- **A writable field needs** a mutable conforming type, a stored field that is not `const`, and a stored type exactly equal to the declared type as the implementation matched it. So a write never changes a type compiled code relies on.
- A declared field is read from the stored field, never through `getproperty`. So a type with its own `getproperty` conforms only if it maps every declared field explicitly: the mapping says that plain `x.name` may differ from `t.name`.
- Computed properties are not declared fields. A type whose data must be computed is converted by the library instead ([§4.10](#410-types-that-only-convert)).
- The declared fields' types decide which types share compiled code ([§6.7](#67-what-compiled-code-is-compiled-for)).

**Status:** Implemented.

### 3.4 Parameters and associated types

```julia
@trait KVec{T} begin
    T = eltype(Self)                  # defined by an equation of Self
    klen(v::KVec)::Int
    kget(v::KVec{T}, i::Int)::T
end

@trait Integrator{U, P} begin         # defined by the fields' types
    u::U
    @const p::P
end

@trait ArrayLike{T, N} begin          # stated by each implementation
    alen(a::ArrayLike)::Int
    firstof(a::ArrayLike{T})::T
end
```

- A trait's parameters are its **associated types.** Each implementation has exactly one value for each, as a Julia type has one `AbstractArray` supertype.
- A parameter is defined in one of three ways:
  - **by a field:** the field's declared type is matched against the stored field's type, as Julia matches a `where` clause. `data::Vector{T}` against a `Vector{Float64}` field gives `T = Float64`. A stored type that does not match is refused at the implementation.
  - **by an equation** of `Self`: `T = eltype(Self)`.
  - **by the implementation**, when neither defines it: `@implement ArrayLike{Float32, 1} MyVec` ([§4.6](#46-stating-parameters)).
- A parameter defined by a field and by an equation is an error ("defined by the field").
- **An equation always holds.** A parameter defined by an equation is never replaced. An implementation may state its value too; the stated value is checked against the equation's ([§4.6](#46-stating-parameters)).
- Operations and fields name the parameters: `kget(v::KVec{T}, i::Int)::T`.
- **Bounds on parameters,** `@trait ArrayLike{T <: Real, N}` or `T <: NumberLike` with a trait. The bound is checked at every implementation: a value outside it is refused with `ImplementError`. A trait bound also lets definition checking ([§9](#9-checks-and-when-they-run)) cover code that computes with the parameter.
- **A parameter may be required to be concrete** at every implementation: `@enforce_concrete_only T` ([§11](#11-concreteness-and-concrete-mode)).
- **Not offered:** a type conforming at several values of a parameter, equations between type functions, a parameter bound that names its own trait. `Callable` ([§5.8](#58-callable-functions-at-a-declared-signature)) is the one trait with several values per type.

**Status:** Implemented, except the check of a stated value against an equation ([T-37](#17-deviations)).

### 3.5 `Self`

- **In a trait's body, `Self` is the type of the value seen through the trait.** For a type that implements the operations with its own methods, or whose operations are all served by defaults, that is the conforming type; for one that forwards with `by f`, the field's type ([§4.3](#43-forwarding-with-by)).
- It appears as the first argument's type (`f(t::Self)`), in result types, and in equations (`T = eltype(Self)`).
- **A constructor operation** declares `Self` as its result: `kwith(t::KTable, cs::Vector{Vector{Float64}})::Self`. It returns a new value like the one seen. With `::Like{t}` ([§5.6](#56-results-declared-types-like-withfields)), this is how a library returns "a value like the input".
- The new value comes back in the caller's form: on a trait object, the new value seen through the trait; on a kept value, a kept value of the same form and attribute ([§7](#7-kept-values-dynamicx-compiledx-keptx)).

**Status:** Implemented, except a constructor operation on a kept value of a trait with fields ([T-35](#17-deviations)).

### 3.6 Supertraits and bundles

```julia
@trait DGrow{T} <: DCol begin          # DGrow's operations, plus DCol's
    T = eltype(Self)
    dpush!(c::DGrow, x::Float64)::Nothing
end
@trait Table <: (ColTable, RowTable)   # a bundle: no body
```

- `@trait B <: A` makes `A`'s operations and fields available through a `B` bound.
- `@implement B T` implements `B`'s own operations. `T` must conform to `A` too, by its own implementation.
- **A type's implementation of `B` must agree with its implementation of `A`:** the same forwarding field, or both served by the type's own methods, with the fields mapped alike. A disagreement is refused.
- A **bundle** names a combination of traits. A bound `t::Table` means `t::(ColTable, RowTable)`.

**Status:** Implemented. The agreement is checked against the type's own implementations; one by a family or a generic implementation is not the type's own.

### 3.7 Tuples of traits

```julia
t::(ColTable, RowTable)                                         # a bound
both(f::(Callable{Tuple{Float64}, Float64}, Callable{Tuple{Int}, Int}), …)   # a function at two signatures
struct ODEProblem{T, P, F <: (Callable{RHSSig{P, T}, Nothing}, Callable{DualSig{P, T}, Nothing})}   # a struct parameter
    f::F
    …
end
marks::Vector{(Shape, Placed)}                                  # in a trait module: each item Kept{(Shape, Placed)}
Dynamic{(Shape, Placed)}(x)                                     # a kept value
```

- **A tuple of traits is a trait.** `(X, Y, …)` is the trait of the values that conform to each member: their intersection, not a union. Its operations and fields are its members'.
- **It stands wherever a trait stands:** a bound, and an attribute on one; an item parameter; a parameter's trait bound; a supertrait list; a struct parameter's bound; a field's or an element type in a trait module; the kept forms; `@implement`, which implements each member ([§4.5](#45-several-traits-at-once)).
- **`Callable` is a trait.** A tuple of `Callable`s is a function at several signatures: a call picks the signature its arguments match ([§5.8](#58-callable-functions-at-a-declared-signature)). A tuple may mix `Callable`s and other traits.
- **A bundle names a tuple:** after `@trait Table <: (ColTable, RowTable)`, `Table` and `(ColTable, RowTable)` are the same trait ([§3.6](#36-supertraits-and-bundles)).
- **One trait, whatever the order:** members are flattened (a tuple or a bundle inside a tuple), duplicates dropped, and the order does not matter.
- **A value enters a tuple once,** and is seen through every member from then on. It has one attribute, decided as for one trait. Members' defaults that disagree cancel ([§6.3](#63-defaults-a-traits-default-and-annotations)).
- **Parameters** stay each member's. A `Dynamic` form fixes the parameters each member's results use ([§5.1](#51-bounds)).
- **A value seen through some members is not seen through the others** later: enter it through the tuple ([§6.5](#65-values-carry)).

**Status:** Implemented for bounds and attributes on them, supertrait lists, bundles and `@implement`. Planned everywhere else a trait stands (struct parameters, kept forms, item parameters, fields and element types, parameters' trait bounds): [W-29](../record/todo.md).

---

## 4. Implementations

`@implement` declares that a type conforms to a trait: an *implementation of `X` for `T`*. It is never inferred from the methods that happen to exist.

All forms share these properties:
- It may come after the type's definition, in another package.
- Its operations are served by the type's own methods, by a field it forwards to, or by the trait's defaults.
- It is checked when it is declared ([§4.9](#49-checks-at-the-declaration)).
- It discards no trait code.
- **Defaults and forwarding serve trait code only.** An implementation adds no methods to the type for the operations a default or a field serves. Called from plain code, `describe(c)` or `area(tile)` then has no method (`MethodError`). Plain code reaches them through a bounded function or a kept value.

**The operations' methods and the implementation are separate.**
- The *methods* serve the operations for a type.
- The *implementation* says how a type joins the trait, fields included.
- A type that implements the operations need not have the declared fields. It then does not conform, but it can be the field another type forwards to. `Vector{Vector{Float64}}` implements `ColTable`'s operations. If `ColTable` declared a field `name`, a bare vector would not conform, and a `Measurements` holding one and a name would.

How an implementation is recorded, so that declaring one invalidates no trait code: [`lowering.md`](lowering.md#4-implementations).

**Status:** Implemented.

### 4.1 With a block of methods

```julia
@implement ColTable Vector{Vector{Float64}} begin
    ncols(t) = length(t)
    col(t, i) = t[i]
end
```

- The block defines the operations' methods for the type and declares the implementation, in one step.
- Method names are the operations' names, unqualified. Each must be an operation of the trait, at a declared arity.
- The first argument is the value seen through the trait, typed as the conforming type. Unannotated arguments get the operation's declared types.
- `function name(args…) … end` works too.
- Operations the block leaves out are served by their defaults. One without a default is an error.

**Status:** Implemented.

### 4.2 One line

```julia
@implement ColTable Ramp           # Ramp has methods of ncols and col
@implement Placed Sprite           # a trait of fields only: Sprite has the fields
```

`@implement X T` without a block or `by` says that `T` implements the trait itself:
1. **`T`'s own methods** serve every operation without a default. Define them before the declaration.
2. **A trait with fields only** is served by the type's stored fields.

**No field is special.** The one-line form never forwards to a field: not one named `data`, not the only field whose type conforms. Forwarding is always written with `by` ([§4.3](#43-forwarding-with-by)).

Errors, each naming the operations:
- methods for some operations and not for others;
- no methods. The message lists the fields whose type conforms, each with its `by` line.

The one-line form needs a concrete type. A parametric type conforms as a family ([§4.7](#47-families)).

No form computes a value from the type. A type whose data needs a computation (a lazily derived table, a foreign layout) does not conform by a field: the library converts it explicitly ([§4.10](#410-types-that-only-convert)).

**Status:** Implemented.

### 4.3 Forwarding with `by`

```julia
@implement ColTable Halves by right
```

- The implementation forwards every operation to the field `right`. The operations are those of the field's type, and `Self` is that type ([§3.5](#35-self)). That type is the *receiver type*: `Halves` shares the code compiled for it ([§6.7](#67-what-compiled-code-is-compiled-for)).
- The field's type must implement the operations itself. **Forwarding does not chain:** a field whose type itself forwards is refused.
- `by` is the only way to forward: `@implement X T` without it never picks a field ([§4.2](#42-one-line)).
- The forwarding field may not also be a writable declared field: a write through the trait would replace the value the operations are called on.
- A trait that requires a concrete `Self` ([§11](#11-concreteness-and-concrete-mode)) refuses a forwarding field of an abstract type, naming the field.

**Status:** Implemented, except the check on a writable forwarding field (Planned; [T-4](#17-deviations)).

### 4.4 Field mappings

```julia
@implement Named Book name => title            # Named declares `@const name::String`
@implement Stepper Clock by data, t => time    # with forwarding
```

- A declared field may be stored under another name: `declared => stored`.
- Several mappings are separated by commas.
- A type with its own `getproperty` must map every declared field.

**Status:** Implemented, except a mapping in a declaration of several traits at once ([T-31](#17-deviations)).

### 4.5 Several traits at once

```julia
@implement (ColTable, RowTable) Grid by data
```

- One declaration, one implementation per trait, all forwarding to the same field (or all served by `Grid`'s own methods).
- Each trait may also be implemented in its own declaration, through its own field: `@implement ColTable Sep by cols` and `@implement RowTable Sep by rows`.

**Status:** Implemented, except with a field mapping, `(X, Y) T name => stored` or `(X, Y) T by f, name => stored` ([T-31](#17-deviations)).

### 4.6 Stating parameters

```julia
@implement ArrayLike{Float32, 1} MyVec
```

- An implementation states the values of parameters that no field and no equation defines.
- **A stated value never replaces an equation.** An implementation may also state a parameter that an equation defines. The stated value is then checked against the equation's value for the type. If they disagree, the implementation is refused with `ImplementError`. For `KVec` (`T = eltype(Self)`, [§3.4](#34-parameters-and-associated-types)) and a type `Wrapped{T}` with no `eltype` method, `@implement KVec{T} Wrapped{T} where {T}` is refused: `eltype(Wrapped{Float64})` is `Any`, not `Float64`. With `Base.eltype(::Type{Wrapped{T}}) where {T} = T` defined first, it is accepted.

**Status:** Implemented, except the check against an equation: today a stated value replaces the equation's value ([T-37](#17-deviations)).

### 4.7 Families

```julia
@implement Fam S{P} where {P}                            # every S{P}, by S's own methods
@implement Indexable A where {A <: AbstractVector}       # every subtype, by its existing methods
@implement KVec A where {A <: Vector{<:Real}} begin      # every member, with methods written here
    klen(v) = length(v)
    kget(v, i) = v[i]
end
@implement StateVector{T} Series{T} where {T}            # joint: the trait's T tied to the type's T
@implement IntegratorView Tsit5Integrator{T, P} where {T, P}   # a trait of fields: parameters from the fields
@implement SVec LSeries{T} by data where {T}             # planned: forwarding, for every member
```

- A family implementation covers every instance of a parametric type, or every subtype of a type, declared with `where`.
- **Each member is checked at its first use,** not at the family's declaration, which checks ownership. Its methods are checked as a single type's implementation is at its declaration: they exist, and their results infer to the declared types. Its parameters are checked against their bounds. A family over an abstract type cannot be checked as a whole: the abstract type's interface is implemented by each subtype (Base has no `length(::AbstractDict)`).
- **A member that does not conform is refused** at its first use, with `ImplementError`.
- **A member's implementation is fixed at its first use,** not at the family's declaration. The package that owns a member's parameter type (`MyT` in `S{MyT}`) may define an override for that member until then, and not after.
- Code is compiled per member.
- **Joint families** tie the trait's parameters to the type's:
  - each member conforms at one value of each trait parameter, so the parameters stay associated types;
  - every variable of the trait's parameters must occur in the type;
  - the trait's parameters are written with variables, constants and type constructors, never function calls.
- A joint family may come with a block of methods, as a family of one type does.
- A member that a trait's concreteness declaration refuses (`S{Any}`, [§11](#11-concreteness-and-concrete-mode)) is refused at its first use, as a member that does not conform.
- **Forwarding for a whole family,** `@implement X Series{T} by f where {T}`: as for one type, the field is named with `by`. The family of field types must be covered by one implementation's family.

**Status:** Implemented, except:
- Planned: forwarding for a whole family (today one declaration per member, `@implement SVec LSeries{Float64} by data`; [open issues §2](../open-issues.md#2-design), "Keys and fields", item 4; [T-7](#17-deviations));
- Planned: a member's override by its parameter type's owner ([T-28](#17-deviations));
- a family with a block whose target is a parametric type expression ([T-5](#17-deviations));
- the check on parameter expressions ([T-6](#17-deviations)).

### 4.8 Generic implementations

```julia
@implement GTable R where {R: Indexable, eltype(R) == Vector{Float64}} begin
    gn(r) = length(r)
    gcol(r, i) = r[i]
end
```

- One implementation covers every type that conforms to other traits. `R: Indexable` reads "`R` conforms to `Indexable`".
- Constraints are `R: Trait`, `R <: Type`, or a condition on `R`.
- It applies to a trait with parameters as to one without.
- Code is still compiled per key ([§6.7](#67-what-compiled-code-is-compiled-for)).
- A generic implementation makes types members only for a trait without declared fields. A trait with fields needs each type's own declaration, which maps them.
- **Forwarding carries through.** A type that forwards `Indexable` to a field forwards `GTable` to the same field, and shares the code compiled for the field's type.
- **Overlap:**
  - a more specific implementation beats a generic one (`@implement GTable Matrix{Float64} begin … end`);
  - a more specific implementation must declare the same parameter values as the generic one, so the choice never changes a type;
  - two overlapping generic implementations with neither more specific are refused;
  - an overlap the later package cannot see, as when a trait's owner adds a generic implementation in a later version, is reported where a call meets both.
- **Predicates** are to be patterns on the constraints' parameters, so that overlap is decidable at the declaration. The example above uses a computed condition, `eltype(R) == …`.
- **A type that conforms through a generic implementation is checked at its first use,** as a family member is ([§4.7](#47-families)): the operations' results, the parameters' bounds, the parts the concreteness declarations name ([§11.1](#111-per-trait-concrete-parameters-and-self)). One that does not conform is refused (`ImplementError`).

**Status:** Implemented: the form, for a trait without parameters, and "more specific beats generic". Planned: the other overlap rules ([T-9](#17-deviations)); forwarding carrying through ([T-30](#17-deviations)); the refusal of a type whose operations do not conform ([T-52](#17-deviations)). For a trait with parameters, see [T-8](#17-deviations). Open: what a predicate may say ([open issues §2](../open-issues.md#2-design), "the design and the code disagree", item 2).

### 4.9 Checks at the declaration

All of these run at `@implement`, never at a call; for a member of a family or a generic implementation, at the member's first use ([§4.7](#47-families), [§4.8](#48-generic-implementations)). A failure raises `ImplementError`. A refused declaration defines nothing: no method and no record.

- **Who:** the declaring package owns the trait or the type ([§10](#10-who-may-implement-pirates-strict-mode)).
- **Completeness:** every operation has a method or a default for the type it is called on (`Self`). Every declared field exists, with the declared type.
- **Results:** each method's result infers to the operation's declared type. The message names the operation, the signature, and both types:

  ```
  `col` at Tuple{Counts, Int64} returns `Vector{Int64}`, declared `Vector{Float64}`
  ```
- **Writable fields** follow [§3.3](#33-fields).
- **Parameters:** values that fields define match; values within their bounds ([§3.4](#34-parameters-and-associated-types)).
- **Concreteness,** for a trait that asks for it ([§11](#11-concreteness-and-concrete-mode)).
- **Overrides belong to the implementation.** Which operations are served by defaults is fixed now. A later method of such an operation for the type is refused when it is defined, naming the fix: define the method before `@implement`, or in its block, and restart Julia. A package image that brings such an override is refused when it loads. So the order matters where plain Julia's does not: a supertype owner's method (`op(::AbstractSample)`) is part of an implementation declared after it, and refused for one declared before it.
- **Redeclaration.** Declaring an implementation again changes it, as Julia 1.13 redefines a struct.

Not everything is caught here: a conversion that fails at run time (a `Float64` buffer receiving dual numbers) is not proved by the check.

**Status:** Implemented, except:
- redeclaration (Planned). Today a second declaration is refused in a session, in every form, naming the reason: change the declaration and restart Julia;
- with a block, the type's existing methods for operations the block leaves out ([T-32](#17-deviations)).

Error types: [T-10](#17-deviations). Messages: [T-11](#17-deviations).

### 4.10 Types that only convert

```julia
@trait TableLike begin
    columnnames(t::TableLike)::Vector{Symbol}
    column(t::TableLike, n::Symbol)::AbstractVector          # not concrete: this bound only converts
end
materialize(t::TableLike)::Vector{Vector{Float64}} = [Float64.(column(t, n)) for n in columnnames(t)]
colmean_any(t::TableLike, i::Int) = colmean(materialize(t), i)   # convert, then the library's code
```

- A type whose data a library can use only after a conversion (a lazily derived table, a foreign layout, a table typed by its schema) does not conform by a field.
- The library converts it explicitly, through a trait that reads any such type, and runs its code compiled for its own type on the result.
- What this costs: a copy; the conversion, compiled per key of the reading trait; no `Like{t}` result, since the result is the library's own type; no write-through.
- This is ordinary trait code, not a separate construct.

**Status:** Implemented (a pattern; nothing to build).

---

## 5. Bounded functions

```julia
colmean(t::ColTable, i::Int) = (c = col(t, i); sum(c) / length(c))
```

Bounded functions exist only inside trait modules ([§2](#2-trait-modules)).

**Status:** Implemented. Each subsection has its own status.

### 5.1 Bounds

- **A trait in an argument annotation is a bound.** `t::ColTable` accepts a value of any type that conforms to `ColTable`.
- **Several bounds on one argument:** `t::(ColTable, RowTable)`, a tuple of traits ([§3.7](#37-tuples-of-traits)). The value must conform to each. A bundle trait is the same thing named. Where the traits declare different defaults, neither applies ([§6.3](#63-defaults-a-traits-default-and-annotations)).
- **A bound may fix parameters:** `s::StateVector{Float64}`. A value conforming at another value is refused at the call with `TraitBoundError`.
- **A bound may leave a parameter open** with a `where` variable: `f(prob::ODEProblemTrait{T}, u0::Vector{Float64}) where {T}`. The body reads `T`, the parameter's value for the value passed.
  - A variable shared between bounds, `f(a::ArrayLike{T}, b::ArrayLike{T}) where {T}`, or with an ordinary argument, `f(v::KVec{T}, w::Vector{T}) where {T}`, requires equal values: `TraitBoundError` at the call otherwise.
  - A bound on the variable, `where {T <: Integer}`, is checked at the call (`TraitBoundError`).
  - The variable stands for a whole parameter (`KVec{T}`), not for a part of one (`KVec{Vector{T}}`), which is refused when the method is defined.
- Other arguments are ordinary: `i::Int`, `v::AbstractVector`, untyped. Ordinary `where` variables on ordinary arguments work as in Julia.
- **An attribute on a bound,** `x::Compiled{Shape}`, `x::Dynamic{Shape}`, `t::Dynamic{(ColTable, RowTable)}`, is the default for a plain value entering there ([§6.3](#63-defaults-a-traits-default-and-annotations)). Such a bound accepts any value that conforms to `X`, not only kept values of that form.
- **An attribute on a bound's item parameter,** `ms::Iterable{Compiled{Mark}}`, `d::Keyed{String, Dynamic{Shape}}`, is the default for plain items ([§6.6](#66-items-of-a-users-container), [§8.2](#82-item-positions)).
- **A `Dynamic` annotation fixes every parameter its operations' result types use:** `s::Dynamic{StateVector{Float64}}`. `s::Dynamic{StateVector}` with `T` in a result type is refused when the method is defined (`TraitBoundError`), so that code after an operation stays typed.

**Status:** Implemented. Open: how `Vector{<:ColTable}` in an argument takes a user's vector ([open issues §2](../open-issues.md#2-design), item 11).

### 5.2 What a bounded function receives

- It receives a **trait object**: the user's own object, seen through the bound. Nothing is copied. A write through a declared field reaches the user's object.
- A trait object is `Compiled` or `Dynamic` ([§6](#6-values-in-trait-code-compiled-and-dynamic)). Both offer the same operations and fields, with the same results.
- With several bounds, each trait sees the same user's object. A write through one is seen through the others.
- How a bounded function is built: [`lowering.md`](lowering.md#8-bounded-functions-workers-and-entries).

**Status:** Implemented.

### 5.3 What trait code may do with a trait object

| In a trait module | Allowed |
|---|---|
| call the trait's operations on it; read its declared fields; write them unless `@const` | yes |
| pass it to another function with a bound it carries, or to an internal function without bounds | yes |
| use several trait objects in one function, of one trait or several | yes |
| capture it in a closure passed to Base (`sort!(p; lt = (i, j) -> …)`) | yes: the closure is checked like the function |
| keep it beyond the call, where a trait's name or a kept form is declared ([§7](#7-kept-values-dynamicx-compiledx-keptx)); it keeps its attribute | yes |
| cast it: `compiled_for(t)`, `with_dynamic(t)` ([§6.4](#64-casts)) | yes |
| call any Julia code on ordinary values, such as the column `col` returns | yes |
| take arguments of abstract types from plain callers (`Any`, `Vector{Any}`) | yes: their uses dispatch when they run; concrete mode reports them ([§11](#11-concreteness-and-concrete-mode)) |
| pass it where a different trait is expected | no: declare both bounds |
| pass it bare to an ordinary function (`sum(t)`), store it bare, return it bare, `typeof(t)`, a field no trait declares | no: code must not depend on the user's type |

A forbidden use is a `TraitUseError` ([§9](#9-checks-and-when-they-run)). Where the check did not see it, a trait object that reaches a function bounded by another trait raises `TraitBoundError` at the call.

**Status:** Implemented.

### 5.4 Internal functions

- Functions without bounds may take trait objects from bounded functions in the same module. They are compiled together with the bounded function that calls them.
- Definition checking follows the trait object into them.
- Only bounded functions accept values from plain code as trait objects. A plain caller passing a value to an unbounded function passes the value itself, as in plain Julia.

**Status:** Implemented.

### 5.5 Dispatch: types first, then traits

```julia
describe(v::Vector{Float64}) = "a vector"
describe(m::AbstractMatrix) = "a matrix"
describe(t::ColTable) = "a table with $(ncols(t)) columns"
describe(x) = "something else"                 # the fallback
```

- **A trait bound ranks above `Any` and below every type,** concrete or abstract ([§14](#14-membership) compares traits and abstract types). `describe([1.0 2.0])` takes the `AbstractMatrix` method, although `Matrix{Float64}` is a `ColTable`. A value caught by a typed method is not seen through a trait. So a library adopts traits one function at a time.
- **Among bounds:** a subtrait beats its supertrait; more bounds beat fewer.
- **Unrelated bounds at one position need a joint method.** `f(t::ColTable)` and `f(t::RowTable)` need `f(t::(ColTable, RowTable))`. The trait module's end raises `TraitBoundError` otherwise. Only the function's own methods are involved, so no later load can create the ambiguity.
- A bounded method and a typed method that are ambiguous in another position are reported at the trait module's end, as missing joint methods are.
- **The fallback:** a value that conforms to none of the bounds reaches the most specific ordinary method that applies, as in plain Julia. Without any, the call raises `MethodError`, with a hint naming the bound.
- **Who may add a bounded method:** a package may add one to a function it owns ([§10.1](#101-who-may-implement)), or to another package's function where the package owns a trait the bound names.
- **A kept value** passed from plain code reaches the bounded method for its trait, with its attribute ([§6.5](#65-values-carry)). Outside trait modules, `Dynamic{X}`, `Compiled{X}` and `Kept{X}` are ordinary concrete types with Julia's dispatch: a plain method `g(d::Dynamic{Shape})` takes a `Dynamic{Shape}` as any type does.

**Status:** Implemented, except that TraitWorld's encoding requires an untyped fallback of a bounded method's shape to be defined after it, and lets only the function's owner add a bounded method of a shape the function has no bounded method of yet ([lowering L-3](lowering.md#18-deviations)). The hint's text: [T-22](#17-deviations). Error types of refused definitions: [T-34](#17-deviations).

### 5.6 Results: declared types, `Like`, `withfields`

```julia
total(t::ColTable)::Float64 = sum(sum(col(t, i)) for i in 1:ncols(t))       # an ordinary result type
kscaled(t::KTable, a::Float64)::Like{t} = kwith(t, [a .* kcol(t, i) for i in 1:kncols(t)])
shifted(r::LRec{Vector{Float64}})::Like{r} = withfields(r; u = r.u .+ 1.0)
```

- An ordinary result annotation works as in Julia.
- **`::Like{t}`** declares that the result is like argument `t`, which must be a bounded argument. The body returns a new value like the one seen (from a constructor operation, [§3.5](#35-self)) or a `withfields` result. The caller gets a value of its own type:
  - a type that implements the operations: the new value, which must be of the same type family (the same type, or a sibling: below);
  - otherwise: the user's object rebuilt by its constructor, with the forwarded or mapped fields replaced, for immutable and mutable types alike. Other fields, such as labels, are kept. The constructor is the type's positional one, taking every field in order; a type without one cannot be rebuilt (`TraitBoundError` at the call).
- **A sibling:** the result may be the same family at another parameter, and the user's type is rebuilt there (`LSeries{Float64}` in, `LSeries{Float32}` out).
- **`withfields(t; name = value, …)`** replaces declared fields, for a trait with fields.
- `return x` inside a `Like` body works.
- Called with a kept value, a `Like` function returns a kept value of the same form and attribute.
- **Trait objects never go up bare.** A function that returns its trait object without `Like` raises `TraitUseError`.
- `verify_main` lists the rebuilding step of each implementation a program reaches ([§13](#13-compiling-ahead)).

**Status:** Implemented, except the listing for `verify_main` (Planned; [T-20](#17-deviations)), and a `Like` result from a kept value of an immutable value kept by its parts ([T-35](#17-deviations)).

### 5.7 Keywords, defaults and varargs

```julia
colz(t::ColTable, i::Int; baseline::ColTable = t, tol::Float64 = eps()) =
    (col(t, i) .- colmean(baseline, i)) ./ max(colrange(baseline, i), tol)
colmean_or(t::ColTable, i::Int = 1) = colmean(t, i)
ncols_sum(ts::ColTable...) = sum(ncols(t) for t in ts; init = 0)
```

- **Defaults are trait code.** They are evaluated inside, after each value is seen through its bound: `baseline = t` sees the trait object, `cols = 1:ncols(t)` may call an operation.
- **A positional default** makes two methods, as Julia does; each is bounded.
- **A keyword is typed like a positional argument:** by a trait bound, a `Callable` bound, a declared type, or the value supplied. A bounded keyword without a default is required.
- **No dispatch on keywords,** as in Julia. A bound on a keyword sees the value through the trait and refuses one that does not conform (`TraitBoundError`); it selects no method.
- A keyword's declared type is checked as in Julia: `tol = 1` for `tol::Float64` is a `TypeError`.
- **A vararg of trait objects,** `ts::ColTable...`, must be last. Its elements may have different keys; the code is compiled per tuple of keys ([§6.7](#67-what-compiled-code-is-compiled-for)).
- **Bounded keywords and vararg elements** get their attribute as positional arguments do ([§6.2](#62-how-plain-values-enter-the-trait-world)).
- A vararg of `Callable` is refused. A vararg keyword (`kws...`) of a bounded function passes on unchanged.
- **A function passed down with keywords** names them in a third parameter: `Callable{A, S, K}`, with `K` a named-tuple type.

**Status:** Implemented, except `Callable` with keywords (Planned) and a function whose only bounded arguments are keywords ([T-48](#17-deviations)). A keyword with several `Callable` bounds is refused ([T-36](#17-deviations)).

### 5.8 `Callable`: functions at a declared signature

```julia
colmap(f::Callable{Tuple{Float64}, Float64}, t::ColTable, i::Int) = map(f, col(t, i))                # Callable's default: Dynamic
colsum(f::Compiled{Callable{Tuple{Float64}, Float64}}, t::ColTable, i::Int) = sum(f, col(t, i))     # compiled per function
both(f::(Callable{Tuple{Float64}, Float64}, Callable{Tuple{Int}, Int}), x::Float64, n::Int) = (f(x), f(n))
squares(t::ColTable, i::Int) = colmap(abs2, t, i)        # a function of the trait world: Compiled

colmap(x -> 2x, m, 1)                    # the library's default: Dynamic
colmap(compiled_for(x -> 2x), m, 1)      # the caller casts it: Compiled
colsum(with_dynamic(x -> 2x), m, 1)      # the caller casts it: Dynamic
colsum(abs2, m, 1)                       # Compiled at colsum's position
```

**Meaning.**
- `Callable{A, S}` is a bound for a function argument: called with arguments of the tuple type `A`, it returns an `S`.
- **Anything callable conforms:** closures, callable structs, generic functions. No implementation is declared.
- **Every call is checked:** the arguments against `A`; a result of another type than `S` is a `TypeError`, where plain Julia would widen. A function without a method for `A` raises `MethodError` when called.
- **`Callable`'s default is `Dynamic`,** as `@default_with_dynamic_self` declares it ([§6.3](#63-defaults-a-traits-default-and-annotations)), so a plain function is `Dynamic` at a bare `Callable` bound, whatever its caller knew. The attributes keep their meaning, a choice of speed only, never of results:
  - `Dynamic`: the library's code is compiled once per signature, not per function. After a method of the function is redefined, a call computes what a plain call would compute at that point.
  - `Compiled`: the library's code is compiled per function, with the function inferred into it, at plain Julia's speed. The signature is still checked.
- A cast takes the signature of the position it reaches. `with_dynamic(abs2)` makes Base's function `Dynamic` too.
- **Several signatures:** `f::(Callable{…}, Callable{…})`, a tuple of traits ([§3.7](#37-tuples-of-traits)). A call picks the signature its arguments match; a call at an undeclared signature raises `MethodError`.
- Functions kept beyond a call: [§7.5](#75-functions-kept). How a call is made: [`lowering.md`](lowering.md#12-callable-and-dynamiccallable).

**Rules.**
- **The argument types `A` are a constant type.** A bound whose `A` names a method's `where` variables (`f::Callable{RHSSig{P, T}, Nothing}`) is refused when the method is defined. Write one method per signature. A struct parameter's bound may name the struct's other parameters: it only keeps the function ([§7.4](#74-a-struct-parameter-bounded-by-a-trait)).
- **An open result type,** `f::Callable{Tuple{Float64}, S} where S`, is inferred at the call, in plain code. It becomes part of what the code is compiled for, and every call is checked against it.
- **Functions returned to plain code** are ordinary closures of the trait module. A closure that captured a trait object keeps the user's object.
- **Bounded closures,** `(u::ColTable) -> …`, are bounded functions.
- **A `Callable` whose result is a trait or a `Callable`** (`f::Callable{Tuple{Int}, ColTable}`) sees the function's results through that bound, as an argument's bound would.

**Status:** Implemented. Planned: open result types ([T-18](#17-deviations)); bounded closures and results that are traits or `Callable`s. A `Dynamic` function takes at most six arguments ([T-51](#17-deviations)). A trait object passed to a `Callable`'s argument declared `Dynamic{X}` is refused ([lowering L-31](lowering.md#18-deviations)).

---

## 6. Values in trait code: `Compiled` and `Dynamic`

**The rule, in three sentences. Values carry. Annotations give defaults where a plain value enters trait code. Explicit casts always win.** This chapter is the one home of that rule: the attribute (§6.1), where plain values enter (§6.2), the defaults (§6.3), the casts (§6.4), carrying (§6.5), items of a user's container (§6.6), what `Compiled` code is compiled for (§6.7), and what each costs (§6.8).

### 6.1 The attribute

- **Every value seen through a trait is `Compiled` or `Dynamic`:** a trait object a bounded function receives, an item read from a container, a kept value ([§7](#7-kept-values-dynamicx-compiledx-keptx)).
- **`Compiled`:** code compiled for what the trait sees of the value's type runs for it ([§6.7](#67-what-compiled-code-is-compiled-for)).
- **`Dynamic`:** code compiled once runs for it, and each operation on it is dispatched when it runs.
- **It is a choice of speed, never of results.** Both run the operations' methods of the value's type, or raise the same error.

**Status:** Implemented.

### 6.2 How plain values enter the trait world

```julia
@trait_module module Plots
using TraitWorld
public render, render_each, render_all, paint, paint_once
@trait Mark begin
    draw(m::Mark, io::IO)::Nothing
end
render(io::IO, ms::Iterable{Mark}) = (for m in ms; paint(io, m); end)              # each item by its type in the code
render_each(io::IO, ms::Iterable{Mark}) = (for m in ms; paint(io, compiled_for(m)); end)
render_all(io::IO, ms::Iterable{Compiled{Mark}}) = (for m in ms; paint(io, m); end)
paint(io::IO, m::Mark) = draw(m, io)
paint_once(io::IO, m::Dynamic{Mark}) = draw(m, io)                                  # compiled once
end

dots(io, ds::Vector{Dot}) = Plots.render(io, ds)     # each item Compiled
mixed(io, xs::Vector{Any}) = Plots.render(io, xs)    # items of abstract type: Dynamic
single(io, d::Dot) = Plots.paint(io, d)              # the caller knows the type: Compiled
Plots.paint(io, Dot())                               # typed at the prompt: Dynamic (the prompt knows no types)
```

**Where a plain value meets a trait.** A *plain value* is one that does not carry an attribute yet. It gets one where it is first seen through a trait:

| Where | When |
|---|---|
| a bound of a bounded function: a positional argument, a keyword, a vararg element, a `Callable` ([§5.1](#51-bounds), [§5.8](#58-callable-functions-at-a-declared-signature)) | at the call |
| an item position of a bound (`Iterable{Shape}`, [§8.2](#82-item-positions)) | when the item is read |
| a struct parameter bounded by a trait ([§7.4](#74-a-struct-parameter-bounded-by-a-trait)) | at the struct's constructor |
| a field or a container of a trait's name, `Kept{X}` ([§7.3](#73-assigning-from-plain-code)) | when the value is stored |
| a constructor of a kept value, `Dynamic{X}(x)`, `Compiled{X}(x)`, `Kept{X}(x)` ([§7.1](#71-the-three-forms)) | when it is called |
| an operation's result declared with a trait | when the operation returns |

**The first-seen rule.** There, a plain value is **`Compiled` if the code that sees it knows its concrete type, and `Dynamic` if not.** The type is the one the code knows when it is compiled, not the value's type when it runs: every value has a concrete type when it runs.
- A caller compiled with the value's concrete type passes a `Compiled` value. A caller that holds the value at an abstract type (`Any`, `AbstractShape`) passes a `Dynamic` one.
- A call that is dispatched at run time passes `Dynamic` values, whatever the types of its arguments: a call through a function value the code does not know (`m.f(x)` with `m` a variable, `invoke_in_world`, a harness such as Julia's `@allocated f(x)`, which calls through `Base.allocated(f, x)`).
- Items of a `Vector{Dot}` are `Compiled`; items of a `Vector{Any}` or a `Vector{AbstractMark}`, values of a `Dict{String, Any}`, are `Dynamic`.
- **At the prompt,** Julia does not compile a statement without a loop, so it knows no types: every call typed at the prompt passes `Dynamic` values. `compiled_for(x)`, or the call inside a function, gives `Compiled`.
- **`Kept{X}(x)`, and a store into a field or container of a trait's name,** take the trait's default, whoever calls: `Compiled`, unless the trait declares `@default_with_dynamic_self` ([§6.3](#63-defaults-a-traits-default-and-annotations)). `Dynamic{X}(x)` and `Compiled{X}(x)` say the attribute themselves.
- **A struct parameter bounded by a trait is a bound:** its constructor applies the first-seen rule as a bounded function does ([§7.4](#74-a-struct-parameter-bounded-by-a-trait)).
- An operation's result declared with a trait is `Dynamic`: its declared type is the trait.

Defaults and casts decide otherwise (§6.3, §6.4). A value that already carries an attribute keeps it (§6.5).

**Status:** Implemented.

### 6.3 Defaults: a trait's default, and annotations

```julia
@trait Model begin
    @default_with_dynamic_self     # plain values of other types enter as Dynamic
    rhs!(m::Model, du::Vector{Float64}, u::Vector{Float64}, t::Float64)::Nothing
end
@trait Kernel begin
    @default_compiled_for_self     # plain values enter as Compiled, whatever the caller knew
    apply!(k::Kernel, out::Vector{Float64}, x::Vector{Float64})::Nothing
end
```

**A trait's default.** A trait may declare one of two defaults in its body. Without one, the first-seen rule decides.
- **`@default_with_dynamic_self`:** a plain value first seen through the trait is `Dynamic`, even where the code that sees it knows its concrete type.
  - It applies to values whose type is not of the trait world. A type is *of the trait world* when it is defined in Julia itself (Core, Base, the standard libraries), in TraitWorld or in a trait module, and so are its fields' types, all the way down. Such a value is the trait world's own, and this default does not apply to it. So a library's own implementation of the trait, and Base's functions and the library's own closures under `Callable`, run compiled where the code knows their type.
  - Use it for a trait with many implementations from outside and a large library behind it: a solver's model, a plot's mark.
  - `Callable`'s default is this one ([§5.8](#58-callable-functions-at-a-declared-signature)).
- **`@default_compiled_for_self`:** a plain value first seen through the trait is `Compiled`, also where the code that sees it does not know its type. Its code is then selected by its type once per call, a function barrier ([§6.8](#68-costs-and-choosing)).
  - It applies to every plain value.
  - Use it for a trait whose implementations do much work per call, where code compiled for each type pays for the selection: a numerical kernel.
- **Several bounds at one position** (`t::(ColTable, RowTable)`, [§5.1](#51-bounds)): where the traits that declare a default agree, it applies; where they declare different defaults, neither applies, and the first-seen rule decides.
- **A trait's default applies wherever a plain value is first seen through the trait** (§6.2): at a bound, at an item read, at a struct parameter bounded by the trait, and when the value is kept as a `Kept{X}`.

**An annotation at a position** is a default for plain values entering there: `x::Compiled{X}` and `x::Dynamic{X}` on a bounded function's argument, `ms::Iterable{Compiled{Mark}}` on an item parameter. `Compiled` on a value whose type the code does not know selects the code for its type once, by its type when it runs; `Dynamic` on a value of known type gives it the code compiled once.

**The order,** from weakest to strongest:
1. the first-seen rule (§6.2);
2. the trait's default, `@default_with_dynamic_self` or `@default_compiled_for_self`;
3. an annotation at the position;
4. a cast (§6.4), which always wins.

Each decides only for a plain value. A value that carries an attribute keeps it at every position (§6.5).

A tuple of traits stands wherever a trait's name stands in the table below, with the same meaning ([§3.7](#37-tuples-of-traits)).

**What each spelling means, by position.**

| Spelling | on a bounded function's argument | on a bound's item parameter | on an operation's argument | as a parameter of an argument's type (`cs::Vector{…}`) | as a field's or element type, inside a trait module | as a struct parameter's bound | outside trait modules |
|---|---|---|---|---|---|---|---|
| `X` (the trait's name) | a bound | an item position | the first argument: the value seen through the trait ([§3.1](#31-operations)) | any kept form | `Kept{X}` | a bounded parameter ([§7.4](#74-a-struct-parameter-bounded-by-a-trait)) | in a field or container, `Kept{X}` (Planned, [§7.2](#72-a-traits-name-as-a-storage-type)); in an argument, refused ([§2](#2-trait-modules)) |
| `Compiled{X}`, `Dynamic{X}` | a bound, with that default | an item position, with that default for plain items | the type, converting | the type | the type, converting | Julia's bound, as written | the type |
| `Kept{X}` | the type | refused | the type, converting | the type | the type, converting | Julia's bound, as written | the type |

- **A bound** accepts any value that conforms to `X`. Its default applies to plain values only; a value that carries an attribute keeps it.
- **The type** is Julia's: a kept value of that form ([§7](#7-kept-values-dynamicx-compiledx-keptx)). On a bounded function's argument, a value of another type raises `MethodError`, as in Julia; the bound `k::X` is the way to take any form.
- **Converting** means that a trait object, or a kept value of the same trait, is converted to the type, keeping its attribute. `Kept{X}` takes either attribute; `Dynamic{X}` and `Compiled{X}` refuse the other one with `TraitBoundError` naming the cast, since a type never casts. On an operation's argument, any other value goes by the argument check (`TraitArgumentError`).
- **A plain value** stored as a `Kept{X}` is first seen there and takes the trait's default ([§7.3](#73-assigning-from-plain-code)). One stored where `Dynamic{X}` or `Compiled{X}` is declared is not converted: write `Dynamic{X}(x)` or `Compiled{X}(x)`.
- **Refused** when the method is defined: an item parameter is a trait's name, `Compiled{X}` or `Dynamic{X}`.

**Rules.**
- **An annotation on a bound of a function that is neither exported nor declared `public` warns** at the trait module's end. Plain values are expected from plain callers, at public functions; elsewhere an annotation is easily mistaken for a cast, which it is not. The fix is a cast at the call (`compiled_for(x)`, `with_dynamic(x)`). An annotation on an item parameter does not warn.
- A `Dynamic` annotation fixes the parameters the trait's operations' result types use ([§5.1](#51-bounds)).

**Status:** Implemented.

### 6.4 Casts

```julia
paint(io, compiled_for(m))                  # in trait code: the next bound runs the code compiled for m's type
Plots.paint_once(io, compiled_for(Dot()))   # in plain code: Compiled, over the position's Dynamic default
Plots.paint(io, with_dynamic(d))            # Dynamic, though the caller knows d's type
```

- **`compiled_for(x)` and `with_dynamic(x)` are the only casts.** They make a value `Compiled` or `Dynamic`, in plain code at the call into a library, and in trait code.
- **A cast always wins,** over the first-seen rule, a trait's default and an annotation. **Of two casts, the later wins:** a library's cast overrides the caller's.
- A cast of a value that has the attribute already returns it unchanged.
- **A cast on a plain value** in plain code marks it until it is first seen through a trait. **On a trait object** in trait code, `compiled_for(t)` opens a `Dynamic` one: the next call selects the code compiled for its type once, a function barrier. **On a kept value:** of a `Dynamic{X}` a `Compiled{X}`, and the reverse; of a `Kept{X}` a `Kept{X}` with the other attribute.
- **Constructors never cast.** `Dynamic{X}(v)`, `Compiled{X}(v)` and `Kept{X}(v)` make a kept value from a plain one, or keep the attribute of one that has it. Asked to change it, they refuse with `TraitBoundError` naming the cast: `Dynamic{X}(t)` for a `Compiled` trait object, `Dynamic{Callable{A, S}}(compiled_for(f))`.
- **Types never cast** (§6.3, the table).
- **A `Dynamic` value is never opened implicitly.** `compiled_for(d)` opens it where the code asks.

**Status:** Implemented.

### 6.5 Values carry

- **A value keeps its attribute** through every call, bound, annotation and storage, until a cast changes it.
- **Storage keeps it.** A value read back from a field or a container has the attribute it was stored with ([§7](#7-kept-values-dynamicx-compiledx-keptx)). The items of a stored `Vector{Dynamic{Plot}}` are `Dynamic` at `Iterable{Compiled{Plot}}` too.
- **Library to library:** a value one library passes to another's bounded function is already a trait-world value; the second library's defaults and annotations do not decide it again.
- **Up and down:** a kept value that plain code holds and passes back keeps its attribute.
- **A value is seen through the traits it entered with.** A kept value of `X` passed to a bound of another trait `Y`, or a function kept at one signature passed to a bound of another, is refused (`TraitBoundError`). Enter it through every trait it will be seen through, as a tuple ([§3.7](#37-tuples-of-traits)). Seeing a value through another trait later would be a *trait cast* ([§6.9](#69-trait-casts)).

**Status:** Implemented, except the refusal at a bound of another trait ([T-53](#17-deviations)).

### 6.6 Items of a user's container

A bound's item parameter (`Iterable{Shape}`, [§8.2](#82-item-positions)) sees each item of a user's container through the trait when it is read. A plain item is first seen there; an item that carries an attribute keeps it. The table is for a trait without a default; a trait's default applies to a plain item as at a bound ([§6.3](#63-defaults-a-traits-default-and-annotations)):

| Bound | items of a `Vector{Circle}` | plain items of a `Vector{Any}`, `Vector{AbstractShape}`, a `Dict{String, Any}`'s values | items that carry (`Dynamic{Shape}`, `Compiled{Shape}`, `Kept{Shape}`, `compiled_for(c)`, `with_dynamic(c)`), in any container |
|---|---|---|---|
| `Iterable{Shape}` | `Compiled` | `Dynamic` | their own |
| `Iterable{Compiled{Shape}}` | `Compiled` | `Compiled`: each item's code selected when it is passed on | their own |
| `Iterable{Dynamic{Shape}}` | `Dynamic` | `Dynamic` | their own |

- **No copy:** the user's container is the one that is read and written. Seeing an item costs a check, not a copy, and allocates nothing.
- **A write stores what reads back as the same value with the same attribute,** in plain code's own forms.
  - Where a plain item of the container reads with that attribute, the write stores the user's object.
  - Otherwise it stores `compiled_for(o)` or `with_dynamic(o)`.
  - After `retain!(isnum, v)` on a `Vector{Any}`, `v` holds the user's numbers, the same objects as before, and a `compiled_for` item stays one.
- A value whose attribute the container cannot hold (a `Compiled` value written to a `Vector{AbstractShape}`, whose plain items read `Dynamic`) raises `TraitBoundError` naming the cast ([§6.4](#64-casts)).
- Which containers and item types are taken: [§8.3](#83-a-users-container-taken-as-it-is).

**Status:** Implemented.

### 6.7 What `Compiled` code is compiled for

There is no syntax for this. It follows from the declarations.

- A bounded function reaches its argument only through the trait's operations and fields. So `Compiled` code is compiled per **key**: what the trait sees of the value's type, not the type itself.
- **The key of a `Compiled` value** is:
  - the **receiver type**, if any: the type whose own methods serve at least one operation. That is the conforming type when it implements the operations, or the field's type when the implementation forwards to a field ([§4.3](#43-forwarding-with-by));
  - plus the declared fields' types.
- An implementation whose operations are all served by defaults has no receiver type. Its key is the declared fields' types alone.
- **Types with equal keys share compiled code.** Every type that forwards `ColTable` to a `Vector{Vector{Float64}}` field runs the code compiled for that field type, including code in the library's package image. Fields the trait does not declare never cause a recompile.
- **A type that supplies its own behaviour gets its own copy.** It implements an operation, or overrides a default, so it is the receiver type. Its code is compiled once, not "once for any type".
- **An abstract declared field's type** (or an abstract field forwarded to) is part of the key as it is: one compiled copy for it, whatever the field holds, and operations on that part dispatch when they run. A value read from that part has an abstract type in the code, so it is `Dynamic` at the next bound; `compiled_for(x)` runs that bound compiled for its type.
- **`Dynamic` values of one trait share one compiled copy** per position, with the parameter values the position fixes, whatever the values' types.
- A function with several bounded arguments is compiled per tuple of keys. A `Dynamic` argument adds nothing per type, so with mixed attributes the function is compiled per the keys of its `Compiled` arguments only.
- Printed types show the key ([§12](#12-printing)): `ColTable at Vector{Vector{Float64}}`.

How a key is represented: [`lowering.md`](lowering.md#5-keys-and-views).

**Status:** Implemented, except that TraitWorld gives an implementation served by defaults alone a receiver type in two more cases ([lowering L-21](lowering.md#18-deviations)).

### 6.8 Costs, and choosing

- **An operation on a value whose type the code knows** (a `Compiled` trait object) is a direct call of the implementation's method.
- **An operation on a value whose type the code does not know** (a `Dynamic` one, or a kept `Compiled` one) costs the same for both attributes. The first four implementations declared take the fastest path. Any other costs one lookup by the value's type and an indirect call, whatever the number of implementations. Which four is fixed when the calling code is compiled: code compiled into a package image knows that package's and its dependencies' implementations. How: [`lowering.md`](lowering.md#13-dynamicx).
- **At a bound:** a `Dynamic` value runs the code compiled once for the position; a `Compiled` value whose type the code does not know selects the code compiled for its key once per call, a function barrier.
- **Choosing, for library authors:**
  - With items of abstract type, a loop is compiled once, so a `Compiled` item's type is unknown inside it. `Compiled` items pay off when the work per item is a call to a bounded function (`paint(io, m)` selects the code for each item's key).
  - `Dynamic` positions suit large code with many implementations behind them (a solver's model): a plain value from outside compiles nothing in the library. A caller's `compiled_for`, or a value of the trait world whose type the caller knows, still compiles the library for its key there.
- The numbers: [`../design/evidence.md`](../design/evidence.md) §2. The performance of both attributes is to be revisited ([open issues §4](../open-issues.md#4-runtime-and-measurements), item 35).

**Status:** Implemented. Optional: a witness carried in the value, and recompiling with the observed types ([compiler §3.3](compiler.md#33-further-work-on-mechanism-3)).

### 6.9 Trait casts

- **A trait cast** would see a value through another trait than it entered with, or a function at another signature, keeping its attribute. A cast ([§6.4](#64-casts)) changes the attribute; a trait cast would change the traits.
- **It is not part of the language.** A value is seen through the traits it entered with ([§6.5](#65-values-carry)); a tuple of traits enters it through all it needs ([§3.7](#37-tuples-of-traits)).
- **As a possible direction,** it would be:
  - explicit, by a kept form's constructor from a kept value of another trait, `Kept{B}(d)`, with the attribute kept;
  - checked at the cast: the held object conforms to `B` (`TraitBoundError` otherwise); for a function, a method at the new signature whose inferred result is not disjoint from the declared one;
  - for kept values that hold the user's whole object only. A trait object inside bounded code may hold only the parts its traits see, and the code compiled for it covers only those traits.

**Status:** Optional.

---

## 7. Kept values: `Dynamic{X}`, `Compiled{X}`, `Kept{X}`

```julia
mutable struct State                 # in a trait module
    const u::Vector{Float64}
    model::Model                     # means Kept{Model}: each value with its attribute
    hooks::Vector{Hook}              # means Vector{Kept{Hook}}
end
start(m::Model, u0::Vector{Float64}) = State(copy(u0), m, Hook[])   # the model kept as it came: Compiled or Dynamic

hooks = Dynamic{Hook}[Dynamic{Hook}(Below(0.9)), Dynamic{Hook}(Always())]   # in plain code
```

**Status:** Implemented. Each subsection has its own status.

### 7.1 The three forms

- **A *kept value* is a value of any type that conforms to `X`, kept where the code does not know its type.** It has one of three forms:
  - `Dynamic{X}`, a value whose attribute is `Dynamic`;
  - `Compiled{X}`, a value whose attribute is `Compiled`;
  - `Kept{X}`, a value with either attribute, as data: what a trait's name means where values of both sit side by side (§7.2).
- Use them for a value that outlives a call, a collection of mixed types, or a field whose type changes.
- **They hold the user's object.** They see the user rebind a field, and writes through them reach the user's object. They keep the user's object alive.
- **An operation on one** runs the method of the implementation it holds, whatever the form. The result is asserted to the declared type, so code after it stays typed. What it costs: [§6.8](#68-costs-and-choosing).
- **A declared field** read on one has its declared type, or the parameter value the form fixes.
- **A parametric trait's form fixes the parameters** its operations' result types use, `Dynamic{StateVector{Float64}}`. A result declared with a parameter (`::T`) is asserted at the fixed value (`Float64`), so code after a call infers.
- **At a bound the attribute decides** ([§6.8](#68-costs-and-choosing)). Put loops over a kept value's data in a bounded function.
- A new implementation, declared later, works at once, and discards no compiled code.
- **Up and down.** Each form is a value of its own type. It goes to plain code as one, bare or inside other values, and comes back with its attribute.

**Making one.**
- From a plain value, in plain code or trait code: `Dynamic{X}(x)`, `Compiled{X}(x)`, or `Kept{X}(x)` (by the first-seen rule and the trait's default, [§6.2](#62-how-plain-values-enter-the-trait-world)).
- By storing a trait object or a kept value where a trait's name is declared (`push!(s.hooks, h)`, `State(u, m, …)`): it keeps its attribute.
- From a value that has an attribute, a constructor keeps it ([§6.4](#64-casts)).
- For each item of a user's container, as it is read ([§6.6](#66-items-of-a-users-container)).
- A trait object carrying another trait cannot become a kept value of `X` (`ArgumentError`).

**Status:** Implemented. Planned: the kept forms of a tuple of traits, `Dynamic{(ColTable, RowTable)}` ([§3.7](#37-tuples-of-traits); refused today: no such value can be made); a trait's own declared `==`; serialization of a kept value with its implementation ([open issues §2](../open-issues.md#2-design)). Open: opening a kept value at the conforming value's own concrete type, a checked downcast ([open issues §2](../open-issues.md#2-design), item 16). Today, assert it in plain Julia: `m = integ.p::Lorenz{Float64}`.

### 7.2 A trait's name as a storage type

- **Inside a trait module,** a trait's name in a struct field or as a container's element type means `Kept{X}`: `model::Model`, `Vector{Hook}`, `Column[]`. It is the one spelling for a value kept with its attribute. So does `Callable{A, S}` in a field.
- **`Dynamic{X}` and `Compiled{X}` written there are the plain types,** as outside: they hold values of that attribute, and refuse the other ([§6.3](#63-defaults-a-traits-default-and-annotations)).
- **In an argument's type,** a trait's name as a parameter (`cs::Vector{Column}`) takes a container of any of the three forms.
- **A trait's name directly in an argument stays a bound.** In a bound's parameters it names an item position ([§8.2](#82-item-positions)). In a struct parameter's bound, it bounds the parameter (§7.4).
- **Outside trait modules,** write the form out: `Kept{X}` for values of both attributes.
- **With traits in the type system** ([§14](#14-membership)), a trait's name in any field or container means `Kept{X}`, outside trait modules too.

**Status:** Implemented. Planned, with traits in the type system: a trait's name as `Kept{X}` outside trait modules ([lowering L-6](lowering.md#18-deviations)).

### 7.3 Assigning from plain code

- A field declared with a trait's name takes any kept value of `X`, a trait object, and a plain value that conforms to `X`.
- A plain value is first seen there and takes the trait's default: `Compiled`, or `Dynamic` under `@default_with_dynamic_self` for a value not of the trait world ([§6.3](#63-defaults-a-traits-default-and-annotations)). A cast decides otherwise: `obj.field = with_dynamic(x)`.
- A library that translates a value before it is stored (a symbol to a colour) defines `Base.convert` to `Kept{X}` for its trait.

**Status:** Implemented.

### 7.4 A struct parameter bounded by a trait

```julia
@trait_module module ODECore
…
struct ODEProblem{T, P, F <: Callable{RHSSig{P, T}, Nothing}}
    f::F
    u0::Vector{T}
    tspan::Tuple{Float64, Float64}
    p::P
end
end

ODEProblem(lorenz!, u0, tspan, p)                 # F = Dynamic{Callable{…}}: Callable's default
ODEProblem(compiled_for(lorenz!), u0, tspan, p)   # F = typeof(lorenz!): code over the problem compiled per function
```

**Meaning.**
- **Inside a trait module, a struct parameter whose upper bound is a trait, a `Callable`, or a tuple of them** ([§3.7](#37-tuples-of-traits)), or an instance of one, is bounded by it. Its field keeps a value of that trait, as its bound gives it.
- **The parameter becomes the stored form's type:**
  - for a `Compiled` value, the user's object itself, whose type is the parameter; code over the struct is compiled per type, at plain Julia's speed. A `Compiled{X}` or a `Kept{X}` holding `Compiled` is opened by its type there;
  - for a `Dynamic` value, `Dynamic{X}`; code over the struct is compiled once.
- **The struct's constructor without parameters is the bound:** each field typed by a bounded parameter is a position where a cast, the value's carried attribute, or the first-seen rule decides ([§6.2](#62-how-plain-values-enter-the-trait-world)). Called from trait code with a trait object, its attribute decides.
- **The constructor with explicit parameters** (`ODEProblem{T, P, F}(…)`) stores what it is given, unchecked, as an explicitly parameterized constructor does in Julia.
- **The bound may name the struct's other parameters** (`RHSSig{P, T}`). They are determined by the other fields' types, as Julia's default constructor determines them.
- The struct's own methods (an implementation's) read the field as a plain value of its type. Bounded trait code reaches only the fields a trait declares.
- This is Rust's `struct S<F: Fn(…)>` and Swift's `struct S<F: P>`, and Julia's advice to make a field's type a parameter, with the attribute choosing the parameter.

**Rules.**
- A bounded parameter types exactly one field, the field itself (`f::F`); a field that uses it inside another type (`fs::Vector{F}`) is refused when the struct is defined.
- Every other parameter is named by a field outside a bound.
- A struct with a bounded parameter has no inner constructor of its own; write an outer constructor that calls the bounded one.

**Status:** Implemented. Planned: a tuple of traits as the bound ([§3.7](#37-tuples-of-traits)). Refused for now, until needed: inner constructors and fields that use a bounded parameter inside another type.

### 7.5 Functions kept

```julia
struct FunctionCallback                                       # in a trait module
    cond::Callable{Tuple{Vector{Float64}, Float64}, Bool}     # means Kept{Callable{…}}: kept with its attribute
end
callback(f) = FunctionCallback(Kept{Callable{Tuple{Vector{Float64}, Float64}, Bool}}(f))   # in plain code
```

- A function kept where the code does not know its type takes the three forms, at a signature:
  - `Dynamic{Callable{A, S}}`: code that calls it is compiled once per signature, whatever the function;
  - `Compiled{Callable{A, S}}`: the function itself; a call selects its code by its type;
  - `Kept{Callable{A, S}}`: either, with its attribute.
- Each call is the checked call: the arguments against `A`, the result asserted to `S`.
- **A function is kept at the signatures it entered with.** To keep it at several, keep it as a tuple: `Dynamic{(Callable{A1, S1}, Callable{A2, S2})}`, or a struct parameter bounded by the tuple (§7.4). Passed to a bound of another signature, it is refused (`TraitBoundError`, [§6.5](#65-values-carry)).
- **Kept at a struct parameter bounded by `Callable`, a function is the field itself** (§7.4): the function under `Compiled`, so the code that reads it is compiled per function; a `Dynamic{Callable{A, S}}` under `Dynamic`. TraitDifferentialEquations' `ODEProblem` keeps its right-hand side so.

**Status:** Implemented, except: a function at a bound of another signature is accepted ([T-54](#17-deviations)); keeping a function as a tuple is Planned ([§3.7](#37-tuples-of-traits)).

### 7.6 Equality and inference

- **Equality:** two kept values of `X` are equal when they hold the same user's object (`===`), whatever their form and attribute: a mutable object by identity, an immutable one by value. `hash` agrees; `===` differs by form.
- **A result through a call that opens a `Dynamic`** (`f(compiled_for(d))`) is not inferred. Assert it: `asdcol(compiled_for(g))::Dynamic{DCol}`.
- Printing: [§12](#12-printing).

**Status:** Implemented.

---

## 8. Collections

### 8.1 BaseTraits: traits for Base's concepts

```julia
@trait_module module Stats
using TraitWorld                        # brings BaseTraits' names: Iterable, Indexable, Keyed, …
mean(xs::(Iterable{Float64}, HasLength)) = (s = 0.0; for x in xs; s += x; end; s / length(xs))
end
Stats.mean([1.0, 2.0, 6.0])             # a Vector{Float64} is Iterable{Float64} and HasLength
```

**Meaning.**
- BaseTraits is the trait world's standard library: traits for the concepts Base defines informally (iteration, indexing, keyed access), each with its item types as associated types ([§3.4](#34-parameters-and-associated-types)). Rust's `core::iter` and Swift's `Sequence` play this part in their languages.
- It is loaded with TraitWorld. `using TraitWorld` brings its names into scope; a package declares no dependency for it.
- Its traits are ordinary traits. The language depends on none of them.
- It grows with what trait code needs. Version 0 has the collection traits:

| Trait | Operations | Associated types | Base's types that conform |
|---|---|---|---|
| `HasLength` | `length(c)::Int` | — | `AbstractArray`, `AbstractDict` |
| `Iterable{T}` | `iterate(c)`, `iterate(c, state)`, each `::Union{Nothing, Tuple{T, Any}}` | `T = eltype(Self)` | `AbstractArray`; `AbstractDict`, whose items are `Pair{K, V}` |
| `Indexable{T} <: HasLength` | `c[i::Int]::T` | `T = eltype(Self)` | `AbstractVector` |
| `MutableIndexable{T} <: Indexable` | `c[i::Int] = x::T` | `T = eltype(Self)` | `Vector` |
| `Resizable <: HasLength` | `resize!(c, n::Int)` | — | `Vector` |
| `Keyed{K, V} <: HasLength` | `d[k::K]::V`, `haskey(d, k::K)::Bool` | `K = keytype(Self)`, `V = valtype(Self)` | `AbstractDict` |

**Rules.**
- **Base's types conform by Base's own methods,** declared in BaseTraits for families through Base's abstract types ([§4.7](#47-families)). A type conforms only where it is declared: a `Number` can be iterated in Base, but it is not `Iterable`.
- **Who owns them:** BaseTraits is part of TraitWorld, and TraitWorld owns its traits. As their owner it declares Base's types' conformance ([§10.1](#101-who-may-implement)). A package's own type conforms by that package's declaration. Another package's type (a `DataFrame`) conforms by its owner's declaration, or through a wrapper type ([§15](#15-named-implementations)).
- **Names:** a module that uses TraitWorld and another module exporting the same name (`Iterable`) gets Julia's usual ambiguity, and imports the one it means: `using Other: Iterable`.

**Status:** Implemented (version 0). Open: which traits come next, and their names; a value carrying two traits that declare the same function at the same arity (`Indexable` and `Keyed` both declare `getindex`) ([open issues, item 31](../open-issues.md#2-design)).

### 8.2 Item positions

```julia
@trait_module module Geometry
using TraitWorld
@trait Shape begin
    area(s::Shape)::Float64
end
total(shapes::Iterable{Shape}) = (s = 0.0; for x in shapes; s += area(x); end; s)
area_of(d::Keyed{String, Shape}, k::String) = area(d[k])
weighted(s::Shape) = 2 * area(s)
total_each(shapes::Iterable{Compiled{Shape}}) = (s = 0.0; for x in shapes; s += weighted(x); end; s)   # each call compiled for the item's key
end
```

- **A trait's name as a bound's parameter names an item position:** `shapes::Iterable{Shape}` is "something to iterate whose items are seen through `Shape`". Rust writes `impl Iterator<Item = impl Shape>` or `impl Iterator<Item = &dyn Shape>`, Swift `some Sequence<some Shape>` or `some Sequence<any Shape>`; here the item type in the caller's code chooses.
- `Iterable{Compiled{Shape}}` and `Iterable{Dynamic{Shape}}` set the default for plain items. Each item's attribute: [§6.6](#66-items-of-a-users-container).
- A tuple of traits names an item position too: `Iterable{(Shape, Placed)}` ([§3.7](#37-tuples-of-traits), Planned).
- `total` is compiled per key of the collection. Over a `Vector{Circle}` it is compiled for `Circle` items. Over a `Vector{Any}`, each item is a `Kept{Shape}`, so each operation on it has a declared result type, not an argument and a result of type `Any`.

**Status:** Implemented.

### 8.3 A user's container, taken as it is

```julia
v = Any[Circle(1.0), Square(2.0)]          # the user's vector, in plain code
Geometry.total(v)                           # taken as it is: its items are seen through Shape
d = Dict{String, Any}("a" => Circle(1.0))
Geometry.area_of(d, "a")                    # area_of(d::Keyed{String, Shape}, k::String)
w = collect(DynamicItems{Geometry.Shape}(v))   # a copy: a Vector{Kept{Shape}}
```

**Meaning.**
- **A function bounded by its items' trait takes the user's container as it is.** Where a bound names an item position (`Iterable{Shape}`, `Indexable{Shape}`, `MutableIndexable{Shape}`, `Keyed{K, Shape}`, `Iterable{Pair{K, Shape}}`, each with or without an attribute), the container is seen through its bound, as every argument is ([§5.2](#52-what-a-bounded-function-receives)). Its items are seen through `Shape` when they are read ([§6.6](#66-items-of-a-users-container)).
- **Explicit wrappers,** for a copy or for code that is not bounded: `DynamicItems{X}(v)` for a vector, `DynamicValues{X}(d)` for a dictionary's values, each item a `Kept{X}`, a plain item `Dynamic`. `collect` of one is a copy.

**Rules.**
- **Which containers are taken:** an `AbstractVector` and an `AbstractDict` (its values), where the position's bounds name item positions of one trait `X`, and the container does not meet any of the position's bounds as it is. A bound met as it is wins: with `f(xs::Iterable{Int})` and `f(xs::Iterable{Shape})`, a `Vector{Int}` takes the first, a `Vector{Any}` is taken by the second.
- **Which item types are taken:** `Any`, an abstract type, a `Union` with a member that is abstract or conforms, and a concrete type that conforms to `X` (a `Vector{Circle}` for `Iterable{Shape}`). A container of `Dynamic{X}`, `Compiled{X}` or `Kept{X}` meets the bound as it is. A `Vector{Float64}` for `Iterable{Shape}` is refused at the call, as a value conforming at other parameters is ([§5.1](#51-bounds)). So is a container of kept values of another trait.
- **An item that does not conform raises `TraitBoundError` when it is read,** after the items before it were processed, and, in a loop that writes, written. Code that must check every item before it starts copies first: `collect(DynamicItems{X}(v))` reads every item.
- **A write must fit the user's container:** storing an object of another type into a `Vector{Circle}` fails as `setindex!` does in Julia ([§6.6](#66-items-of-a-users-container) for attributes).
- **The copy is a new container:** writes to `collect(DynamicItems{X}(v))` do not reach `v`.
- With several bounds at one position (`xs::(MutableIndexable{Cell}, Resizable)`), the container is taken once, for all of them. Bounds that fix item positions of different traits at one position do not take it.

**Status:** Implemented, except a container passed as a bounded keyword ([T-39](#17-deviations)) and closed builds ([lowering L-27](lowering.md#18-deviations)).

### 8.4 Algorithms over collection traits

```julia
retain!(isnum, v)                         # keep the numbers of the user's vector, in place
```

- `retain!(f, xs)` keeps the items for which `f(x)` is `true`, in order, for `xs::(MutableIndexable, Resizable)`. It returns `nothing`. It is Base's `filter!` for trait code (Rust's `Vec::retain`).
- **A generic algorithm takes the function as an ordinary argument,** compiled per function, as Base does. A `Callable`'s argument types are constant ([§5.8](#58-callable-functions-at-a-declared-signature)), so `f::Callable{Tuple{T}, Bool}` for the item type `T` of any collection cannot be written. A function for one item type writes the `Callable` bound: `f::Callable{Tuple{Kept{Cell}}, Bool}`.
- BaseTraits' algorithms have names of their own: only Base may add bounded methods to Base's functions ([§5.5](#55-dispatch-types-first-then-traits)).

**Status:** Implemented (`retain!`). Open: which algorithms BaseTraits provides, and their names ([open issues, item 31](../open-issues.md#2-design)).

---

## 9. Checks, and when they run

| When | What is checked | Error |
|---|---|---|
| `@trait` | the body's form: result types present, the first argument typed by the trait, no parameter defined twice | `ErrorException` |
| `@implement` | ownership, completeness, result types, fields, parameters, concreteness ([§4.9](#49-checks-at-the-declaration)) | `ImplementError` |
| a method definition after `@implement` | an override of an operation a default serves | `ImplementError` |
| a definition in a trait module | the module owns the method's function or a type in it | `OwnershipError` |
| a bounded function's definition | a `Dynamic` annotation fixes the parameters its operations' result types use ([§5.1](#51-bounds)) | `TraitBoundError` |
| the end of a trait module | every bounded function, once, for every type that will ever conform; ambiguous bounds; an annotation on a function neither exported nor public ([§6.3](#63-defaults-a-traits-default-and-annotations)) | `TraitUseError`, `TraitBoundError`; a warning |
| a call of a bounded function | the value conforms; fixed parameters; bounded keywords; concreteness of a family member | `MethodError` (with a hint), `TraitBoundError` |
| a call of an operation on a trait object or a kept value | the arguments against the declaration; the result | `TraitArgumentError`, `TypeError` |
| a call to a `Callable` | the arguments and the result | `TypeError`, `MethodError` |
| a bounded function's first call at a signature | what the end of the module cannot check: a parameter left open whose bound is not a trait, a `Callable`'s open result type | `TraitUseError` |
| a cast that a constructor or a type would make | refused ([§6.4](#64-casts)) | `TraitBoundError` |

**Definition checking** at the end of a trait module infers each bounded function once at an *archetype*: a stand-in value whose operations and fields return values of their declared types and nothing more. A trait object has no methods but its traits' operations and fields, and every operation declares its result type. So one check covers every type that will ever conform. A mistake is reported at its line before any type conforms:

```julia
spread(t::ColTable) = size(t)    # `size` is not an operation of ColTable
leak(t::ColTable) = typeof(t)    # code must not depend on the user's type
```

- While a package is precompiled, the report is an error, and the build fails.
- For a trait module defined at the prompt or in a script, it is a warning. The call then raises the `TraitUseError`.
- `check_definitions(M)` runs the check on demand: it returns an empty list, or raises `TraitUseError` listing the problems.
- Keyword, vararg and `Callable` functions with declared result types are checked at the module's end like any other.

**Status:** Implemented, except that keyword, vararg and every `Callable` function are checked at their first call ([T-19](#17-deviations)), and that several definitions in a trait module are refused with `ErrorException` ([T-34](#17-deviations)).

---

## 10. Who may implement; pirates; strict mode

### 10.1 Who may implement

- A package *owns* the functions and types it defines. Julia (Core, Base, the standard libraries) is one owner. A package extension counts as its parent package.
- **At the prompt,** `Main` is one owner, and each module defined directly under `Main` (at the prompt or in a script) is an owner of its own, as a package is. So a trait module defined at the prompt does not own the prompt's types: an implementation of its trait for `Vector{Int}`, written at the prompt, is refused.
- An implementation is a method, so ordinary ownership decides who may write it: **the trait's owner or the type's owner.** A third package may not.
- An implementation for a foreign trait and a foreign type belongs in the trait owner's package extension.
- **An implementation in a package extension mentions each of the extension's triggers:** each trigger package owns the trait or a type the declaration names. Otherwise whether a call sees it would depend on whether that package happens to be loaded. It is refused with `ImplementError`.
- Operations that are existing functions (`Base.size`) may be implemented only for types the declaring package owns. Otherwise declare the existing methods: `@implement Sized Vector{Float32}` without a block, by Base's own methods.

**Status:** Implemented. Open: whether the standard libraries are owners of their own ([open issues §1.19](../open-issues.md#1-decisions-waiting-for-the-user)).

### 10.2 Pirates

- A **pirate** is a method of a function you do not own, for types you do not own: Julia's "type piracy".
- **A trait module may not define one:** `OwnershipError` at the definition. A `Union` with one of your own types is no way around it, nor a lower-bounded type variable.
- In plain code, a pirate is followed by default, as in plain Julia. Trait code it changes is compiled again once ([`facts.md`](facts.md#pirates)).
- Methods for your own types are never pirates: `Base.show(io::IO, x::MyType)` is fine everywhere.

**Status:** Implemented. Open: whether the refusal in trait modules stays, or only pirates that win are refused, under strict mode ([open issues §1.20](../open-issues.md#1-decisions-waiting-for-the-user)).

### 10.3 Strict mode

```julia
TraitWorld.strict!(true)        # or start Julia with JULIA_TW_STRICT=1
```

- **It applies to trait code:** the code of trait modules, compiled by facts.
- **The property it secures: trait code is never invalidated,** except by a change of code it depends on, a stakeholder's ([facts §10.2](facts.md#strict-mode)).
- Strict mode refuses a pirate when it would win at a call that compiled trait code makes. The error, `TraitWorld.PirateError`, names the method and the trait code it would change. The method then does not exist, for plain code either.
- Nothing else is refused: a pirate that wins nowhere in trait code is accepted.
- A definition by a stakeholder is followed. A *stakeholder* of a method is the owner of its function or of a type in its signature. Define as the owner with `@eval Owner f(…) = …`.
- `TraitWorld.delegate!(Core => Impl)` lets an implementation package count as the owner of the core package it implements (for split packages such as StaticArraysCore and StaticArrays).
- A pirate loaded before the code it changes is refused too.
- **A package extension's method** that wins at a fact of trait code without mentioning its triggers' types is followed, as its parent package's change, a stakeholder's. It is not refused. A warning names the method and the trait code it affects.
- `verify_main` lists the calls reached from trait code that select a pirate.

**Status:** Implemented as a prototype: refusal when the pirate is defined, or when an image that brings it loads, after the trait code. The warning for a package extension's winning method is Implemented. Planned: refusal of pirates loaded before the code they change, and the listing in `verify_main`. Strict mode also protects some code that is not trait code ([facts §10.2](facts.md#strict-mode), the note). The error's text: [T-21](#17-deviations).

### 10.4 No sealing

- Abstract types and functions are not sealed. Anyone may add a subtype or a method, as in Julia today.
- A closed contract is a trait: its operations, their declared result types, and the check at every implementation.

**Status:** Implemented.

---

## 11. Concreteness and concrete mode

```julia
@trait KVec{T} begin
    @enforce_concrete_only T Self      # T and the type seen through KVec: concrete
    T = eltype(Self)
    klen(v::KVec)::Int
    kget(v::KVec{T}, i::Int)::T
end
@trait Integrator{U, P} begin
    @warn_on_abstract P                # an abstract P warns
    u::U
    @const p::P
end
@enforce_concrete_only T v total(v::KVec{T}) where {T} = …     # one function's calls, inside a trait module
@enforce_fully_typed @trait_module module Fast … end            # concrete mode, every function of the module
@warn_not_fully_typed cold(t::ColTable, k::Vector{Any}) = …    # concrete mode, one function
fully_typed(Columns.colmean, (Vector{Vector{Float64}}, Int))    # a report, anywhere
```

**Concrete** means a concrete type, or a `Union` of at most four concrete types, whose type parameters are concrete in the same sense, all the way down: `Vector{Float64}` and `Vector{Union{Missing, Int}}`, not `Vector{Real}`, `Real` or a union of five types. Four is Julia's limit on union splitting: a call on a small union splits into one compiled call per member, each a fact ([facts §3](facts.md#facts-and-fact-signatures)), so the code is fully typed. The type's fields are not looked at: trait code reads only the fields its traits declare. A parameter value that is not a type (the `1` in `ArrayLike{Float32, 1}`) is concrete.

### 11.1 Per trait: concrete parameters and `Self`

- `@enforce_concrete_only names…` in a trait's body: a type conforms only if each named part is concrete at its implementation. Otherwise the implementation is refused (`ImplementError`).
- `@warn_on_abstract names…`: the implementation is accepted, with a warning naming the part.
- **The names** are the trait's parameters, and `Self`: the type of the value seen through the trait, the conforming type itself or the field it forwards to ([§3.5](#35-self)).
- **Without names,** a declaration names `Self` and every parameter.
- Each declaration appears at most once in a body, and a name in at most one of them.
- **A declared field** is constrained through a parameter: declare it `x::X`, with `X` a parameter (bounded, `X <: Real`, where needed), and name `X`. A declared field whose type names no parameter is not checked.
- **Supertraits:** a trait's declaration applies to its own parameters, at every implementation of the trait and of its subtraits. `Self` is shared: the strictest level among a trait and its supertraits applies.
- **When:** at the declaration. A member of a family at its first use ([§4.7](#47-families)), and a type conforming through a generic implementation at its first use ([§4.8](#48-generic-implementations)), refused as a member that does not conform.
- Where an implementation has no receiver type (every operation served by a default, a trait of fields only), the code compiled for the trait does not depend on the conforming type, and `Self` is not checked.
- Decide this when the trait is published. Adding it later breaks conforming types whose parts are abstract.
- **A `Dynamic` value** of such a trait is fine: its object's type is unknown by choice, not abstract, and its implementation was checked when it was declared.

### 11.2 Per function: concrete parameters of the bounds

- In a trait module, `@enforce_concrete_only names…` before a bounded function's definition refuses a call where a named part is not concrete (`TraitBoundError`). `@warn_on_abstract names…` warns instead, once per function and type.
- **The names** are the method's `where` variables that its bounds name (`T` in `v::KVec{T}`, [§5.1](#51-bounds)), and bounded arguments, each standing for its `Self`.
- The names are required: a function has no default list.
- A function may require more than its traits do.
- **Cost:** for a `Compiled` value, the answer is decided where the call is compiled, and nothing runs. For a `Dynamic` value, `Self` is unknown by choice and not checked; a parameter its type leaves open is checked at the call.

### 11.3 Concrete mode: fully typed code

- Code is **fully typed** when every call in it, and in what it calls, has known argument types. Such code pays nothing for the trait modules' compiler mode.
- `fully_typed(f, argtypes)` reports the calls that are not, with their root cause through any number of layers ("field `scale` of `Config` is declared `Real`"). `isfullytyped(report)` answers yes or no. Operations on `Dynamic` values, trait objects and kept values count as declared, not as faults.
- `@warn_not_fully_typed` warns at a bounded function's first run; `@enforce_fully_typed` raises `AbstractTypeError` (an abstract value used) or `NotFullyTypedError` (a call with unknown types). Before `@trait_module`, it applies to every function of the module.

**Status:** Implemented. The spelling of concrete mode's two macros is Open ([open issues §1](../open-issues.md#1-decisions-waiting-for-the-user), item 45).

---

## 12. Printing

- A trait object's type prints by bound and key: `ColTable at Vector{Vector{Float64}}`, `PVec{Float64} at Vector{Float64}`. The user's other fields never appear. A `Dynamic` trait object's type prints as `ColTable at Dynamic`.
- A kept value prints with its trait and its object's key: `Dynamic{Shape} at Circle`, `Compiled{Shape} at Circle`, `Kept{Shape}: Compiled at Circle`.
- A function bound prints as `Callable{Tuple{Float64}, Float64} at Dynamic`, or at the function's type when `Compiled`.
- Stack traces hide TraitWorld's own frames. `JULIA_TW_ALL_FRAMES=1` shows them.

**Status:** Implemented. It needs the patched Julia's type printers ([`compiler.md`](compiler.md#53-type-printers)).

---

## 13. Compiling ahead

No syntax: it follows from `@implement` in a package.

- While a package that declares `@implement X T` is precompiled, the trait code that `T` needs is compiled into that package's image. This covers every bounded function with one trait position whose bound includes `X`, at `T`'s key, where the other arguments are concrete.
- Another trait position is not a concrete argument: its key is not known. So a bounded function with several trait positions (`meandiff(a::ColTable, b::ColTable)`) is compiled at its first call, not ahead.
- The checks a first call would run are run then, and the image keeps their results. A failing check fails the build.
- A caller that does not know the argument's type passes a `Dynamic` value ([§6.2](#62-how-plain-values-enter-the-trait-world)), unless the trait's default or an annotation says `Compiled`: it runs the code compiled once for the position, and compiles nothing per type. That code is compiled ahead where a workload or a declaration of the library reaches it.
- **Compiling ahead adds no method to the library's functions,** so it discards no trait code and invalidates no plain code.
- What exactly is compiled: [`lowering.md`](lowering.md#151-compiling-ahead-from-declarations).
- `TraitWorld.@workload begin … end` is a precompile workload for a trait module (PrecompileTools' `@compile_workload`, reached through TraitWorld).
- `JULIA_TW_AHEAD=0` turns compiling ahead off.

**Closed programs.** `verify_main(main, (Vector{String},); entrypoints = true)` lists every target a program can reach through trait code, for `juliac --trim`:
- a function passed as a `Callable` adds one target at its declared signature;
- a kept value adds the implementations whose types reach the place it is made; code at a `Dynamic` position lists every declared implementation;
- each set of supplied keywords is a signature;
- a closure returned from trait code has a type of the trait module, so calls to it from plain code are calls into trait code, listed too.

Plain code reached from trait code keeps plain Julia's properties, and its open dynamic calls are reported. A `--trim` build compiles plain code: nothing loads in a binary, so nothing needs protecting ([`facts.md`](facts.md#closed-builds)).

**Status:** Implemented, except:
- what is compiled ahead is narrower ([lowering L-15](lowering.md#18-deviations)); code at a `Dynamic` position is not listed as `verify_main`'s targets ([lowering L-35](lowering.md#18-deviations));
- the rebuilding step of `Like{t}` is not listed yet ([T-20](#17-deviations)).

---

## 14. Membership

A trait is a kind of abstract type: it names a set of types, and it is written where an abstract type is written (an argument, a field, a type parameter). It follows other rules for membership, subtyping and dispatch:

| | An abstract type | A trait |
|---|---|---|
| **How a type joins** | in its own definition, `struct S <: A` | by an implementation, `@implement X S`, written after the type and apart from it ([§4](#4-implementations)) |
| **Who may make it join** | the type's author | a stakeholder: the package that owns the type or the one that owns the trait ([§10.1](#101-who-may-implement)) |
| **How many** | one supertype, so one chain of ancestors | any number of traits |
| **What joining promises** | nothing that is checked: the methods a library expects are a convention | the trait's operations and fields, with their types, checked at the implementation ([§4.9](#49-checks-at-the-declaration)) |
| **Above it** | a tree: `abstract type A <: B` places `A` under `B` | requirements: `@trait B <: A` means a type implementing `B` implements `A` too, by an implementation of its own, and a `B` bound sees `A`'s operations; a bundle combines traits without a body ([§3.6](#36-supertraits-and-bundles)) |
| **Parameters** | fixed by the subtype's definition, and invariant: `Vector{Int} <: AbstractVector{Int}`, but not `<: AbstractVector{Real}` | set per implementation, by the conforming type's field types, the trait's equations, or stated values (associated types, [§3.4](#34-parameters-and-associated-types)): `conforms(Vector{Int}, PVec{Float64})` is `false` |
| **Values** | each value has a concrete type, which `isa` every supertype | each value has a concrete type, which conforms; library code sees the value through the trait, `Compiled` or `Dynamic`, and a field or a container of the trait keeps it as a `Kept{X}`, with its attribute ([§7](#7-kept-values-dynamicx-compiledx-keptx)) |
| **Dispatch** | by subtyping: the most specific type wins | a bound ranks above `Any` and below every type, concrete or abstract; among bounds a subtrait beats its supertrait ([§5.5](#55-dispatch-types-first-then-traits)) |
| **What code is compiled for** | the argument's concrete type, at each call | the key: what the trait sees of the value's type ([§6.7](#67-what-compiled-code-is-compiled-for)) |
| **Joining later** | no: a type's supertype is fixed where it is defined | yes: a later package may declare an implementation, if it is a stakeholder |

- **`T <: X` and `x isa X`** mean "`T` conforms to `X`" and "`x`'s type conforms to `X`". An implementation adds the trait to the type's supertypes after the type is defined. That is sound because only a stakeholder declares it, and a pirate's implementation is refused.
- **Between traits, `B <: A`** means `A` is a supertrait of `B`: every type that conforms to `B` conforms to `A`, by its own implementation of `A`.
- **`conforms(T, X)`** answers the same question as `T <: X`. With fixed parameters, `conforms(Vector{Int}, PVec{Float64})` is `false`. `conforms(Dynamic{X}, X)` is `true`.
- **Abstract types stay.** Where a tree of types is right, a library declares one, and its methods take abstract types as Julia's do. Numbers need no trait: `Number`, `Real` and `Integer` stay as they are. A type may subtype an abstract type and implement traits, and dispatch takes a typed method first.

**Status:** `conforms` is Implemented. `T <: X` and `x isa X` for traits are Planned: today a trait is encoded as an abstract type that no conforming type subtypes, so both are accepted and `false` for every conforming value and type, and `B <: A` between traits is `false` too ([T-23](#17-deviations); [`lowering.md` §17](lowering.md#17-encodings-until-traits-are-in-the-type-system)).

---

## 15. Named implementations

- A second implementation of a trait for a type, used only where a caller names it.
- The preferred form is a wrapper value that conforms, a newtype: `Via{Fast}(x)`.
- Until then, a foreign trait for a foreign type needs the trait's owner, the type's owner, or your own wrapper type: `struct FastM; m::M; end` with its own implementation.

**Status:** Planned, deferred until traits are in the type system.

---

## 16. Status index

| Construct | Status | Section |
|---|---|---|
| `@trait_module`, the module and block forms | Implemented | [§2](#2-trait-modules) |
| `@trait`: operations, result types, `Self` | Implemented | [§3.1](#31-operations), [§3.5](#35-self), T-35, T-49 |
| defaults | Implemented | [§3.2](#32-defaults) |
| a trait's parameter in a default's body | Planned | [§3.2](#32-defaults), T-2 |
| declared fields, `@const` | Implemented | [§3.3](#33-fields) |
| parameters by field, by equation, stated | Implemented | [§3.4](#34-parameters-and-associated-types) |
| a stated value checked against an equation | Planned | [§4.6](#46-stating-parameters), T-37 |
| bounds on parameters, checked | Implemented | [§3.4](#34-parameters-and-associated-types) |
| supertraits, bundles | Implemented | [§3.6](#36-supertraits-and-bundles) |
| tuples of traits: bounds, attributes on bounds, supertrait lists, `@implement` | Implemented | [§3.7](#37-tuples-of-traits) |
| tuples of traits everywhere else a trait stands | Planned | [§3.7](#37-tuples-of-traits), W-29 |
| a value seen through the traits it entered with | Implemented, except T-53, T-54 | [§6.5](#65-values-carry) |
| trait casts | Optional | [§6.9](#69-trait-casts) |
| supertrait agreement check | Implemented | [§3.6](#36-supertraits-and-bundles) |
| an operation's argument declared `Dynamic{Y}`, `Compiled{Y}`, `Kept{Y}`: a type | Implemented | [§3.1](#31-operations), [§6.3](#63-defaults-a-traits-default-and-annotations) |
| `@implement X T begin … end` | Implemented | [§4.1](#41-with-a-block-of-methods) |
| `@implement X T` (one line) | Implemented | [§4.2](#42-one-line) |
| `by f` | Implemented | [§4.3](#43-forwarding-with-by) |
| the forwarding field not a writable declared field | Planned | [§4.3](#43-forwarding-with-by), T-4 |
| field mappings `name => stored` | Implemented | [§4.4](#44-field-mappings) |
| several traits at once | Implemented | [§4.5](#45-several-traits-at-once) |
| stated parameters `X{P…} T` | Implemented | [§4.6](#46-stating-parameters) |
| families, joint families | Implemented | [§4.7](#47-families), T-5, T-6 |
| a family member refused at its first use | Implemented | [§4.7](#47-families) |
| the family-wide check at the declaration; a member's override | Planned | [§4.7](#47-families), T-26, T-28 |
| forwarding for a whole family | Planned | [§4.7](#47-families), T-7 |
| generic implementations | Implemented | [§4.8](#48-generic-implementations), T-8 |
| forwarding through a generic implementation | Planned | [§4.8](#48-generic-implementations), T-30 |
| overlap rules for generic implementations | Planned | [§4.8](#48-generic-implementations), T-9 |
| what a generic predicate may say | Open | [open issues §2](../open-issues.md#2-design) |
| overrides fixed at the declaration; family members at first use | Implemented | [§4.9](#49-checks-at-the-declaration) |
| redeclaring an implementation | Planned (today: restart) | [§4.9](#49-checks-at-the-declaration) |
| a refused declaration defines nothing | Implemented | [§4.9](#49-checks-at-the-declaration) |
| types that only convert | Implemented (a pattern) | [§4.10](#410-types-that-only-convert) |
| bounds on arguments, several bounds, fixed parameters | Implemented | [§5.1](#51-bounds) |
| `where` variables in bounds, shared or not | Implemented | [§5.1](#51-bounds) |
| `Vector{<:X}` arguments | Open | [open issues §2](../open-issues.md#2-design) |
| internal functions without bounds | Implemented | [§5.4](#54-internal-functions) |
| types first, then traits; joint-method rule; fallback | Implemented | [§5.5](#55-dispatch-types-first-then-traits), L-3 |
| result types, `Like{t}`, `withfields`, siblings | Implemented | [§5.6](#56-results-declared-types-like-withfields) |
| keywords, defaults, varargs | Implemented | [§5.7](#57-keywords-defaults-and-varargs), T-48 |
| `Callable{A, S}`, its `Dynamic` default, `Compiled{Callable{A, S}}`, casts | Implemented | [§5.8](#58-callable-functions-at-a-declared-signature), T-51 |
| `Callable{A, S, K}` with keywords | Planned | [§5.7](#57-keywords-defaults-and-varargs) |
| a constant `A`, refused otherwise | Implemented | [§5.8](#58-callable-functions-at-a-declared-signature) |
| open `Callable` result types | Planned | [§5.8](#58-callable-functions-at-a-declared-signature), T-18 |
| bounded closures; `Callable` results that are traits | Planned | [§5.8](#58-callable-functions-at-a-declared-signature) |
| `Compiled` and `Dynamic`: where plain values enter, the first-seen rule | Implemented | [§6.2](#62-how-plain-values-enter-the-trait-world) |
| a trait's default, `@default_with_dynamic_self` or `@default_compiled_for_self`; annotations as defaults; the table by position | Implemented | [§6.3](#63-defaults-a-traits-default-and-annotations) |
| the warning on an annotation of a function neither exported nor public | Implemented | [§6.3](#63-defaults-a-traits-default-and-annotations) |
| casts `compiled_for(x)`, `with_dynamic(x)`; constructors and types never cast | Implemented | [§6.4](#64-casts) |
| values carry through calls, bounds and storage; library to library | Implemented | [§6.5](#65-values-carry) |
| items of a user's container with their attribute; writes that read back the same | Implemented | [§6.6](#66-items-of-a-users-container) |
| keys: what `Compiled` code is compiled for | Implemented | [§6.7](#67-what-compiled-code-is-compiled-for), L-21 |
| beyond four implementations: a constant cost | Implemented | [§6.8](#68-costs-and-choosing) |
| a witness carried in a kept value; recompiling with the observed types | Optional | [§6.8](#68-costs-and-choosing) |
| kept values `Dynamic{X}`, `Compiled{X}`, `Kept{X}`; their operations and fields | Implemented | [§7.1](#71-the-three-forms) |
| `Dynamic{(X, Y)}`, a trait's `==`, serialization | Planned | [§7.1](#71-the-three-forms) |
| opening a kept value at its concrete type | Open | [§7.1](#71-the-three-forms) |
| a trait's name in storage as `Kept{X}` inside trait modules | Implemented | [§7.2](#72-a-traits-name-as-a-storage-type), L-6 |
| a plain value assigned to a field of a trait's name: the first-seen rule | Implemented | [§7.3](#73-assigning-from-plain-code) |
| a struct parameter bounded by a trait | Implemented | [§7.4](#74-a-struct-parameter-bounded-by-a-trait) |
| functions kept; one function at several signatures | Implemented | [§7.5](#75-functions-kept) |
| BaseTraits version 0: `HasLength`, `Iterable{T}`, `Indexable{T}`, `MutableIndexable{T}`, `Resizable`, `Keyed{K, V}`; Base's containers' conformance | Implemented | [§8.1](#81-basetraits-traits-for-bases-concepts) |
| a trait's name in a bound's parameters as an item position | Implemented | [§8.2](#82-item-positions) |
| a user's container taken as it is; `DynamicItems{X}(v)`, `DynamicValues{X}(d)` | Implemented | [§8.3](#83-a-users-container-taken-as-it-is), T-39 |
| `retain!` | Implemented | [§8.4](#84-algorithms-over-collection-traits) |
| BaseTraits' next traits and algorithms; two traits declaring one function at one arity | Open | [open issues, item 31](../open-issues.md#2-design) |
| definition checking | Implemented | [§9](#9-checks-and-when-they-run), T-19 |
| who may implement | Implemented | [§10.1](#101-who-may-implement) |
| the standard libraries as owners of their own | Open | [open issues §1.19](../open-issues.md#1-decisions-waiting-for-the-user) |
| no pirates in trait modules | Implemented; whether it stays is Open | [open issues §1.20](../open-issues.md#1-decisions-waiting-for-the-user) |
| strict mode | Implemented as a prototype; the rest Planned, with the warning for package extensions | [§10.3](#103-strict-mode) |
| no sealing | Implemented | [§10.4](#104-no-sealing) |
| concrete parameters and `Self`, per trait: `@enforce_concrete_only`, `@warn_on_abstract` | Implemented | [§11.1](#111-per-trait-concrete-parameters-and-self) |
| concrete parameters of the bounds, per function | Implemented | [§11.2](#112-per-function-concrete-parameters-of-the-bounds) |
| concrete mode: `@enforce_fully_typed`, `@warn_not_fully_typed`, `fully_typed` | Implemented | [§11.3](#113-concrete-mode-fully-typed-code) |
| a small union: concrete, and fully typed (concrete mode is silent about it) | Implemented | [§11](#11-concreteness-and-concrete-mode) |
| printing by bound and key | Implemented | [§12](#12-printing) |
| compiling ahead from `@implement` | Implemented | [§13](#13-compiling-ahead) |
| `verify_main`, `@workload` | Implemented | [§13](#13-compiling-ahead), T-20 |
| `conforms(T, X)` | Implemented | [§14](#14-membership) |
| `x isa X`, `T <: X` | Planned | [§14](#14-membership), T-23 |
| named implementations, `Via{Fast}(x)` | Planned (deferred) | [§15](#15-named-implementations) |

---

## 17. Deviations

Where TraitWorld differs from this reference. File paths are in the repository; a row's line numbers are those of TraitWorld at 227781a, and rows without them name functions. Checks named "reference.jl" are in [`experiments/docs-examples/reference.jl`](../../experiments/docs-examples/reference.jl).

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| T-1 | — | *Retired*: see [§3.4](#34-parameters-and-associated-types). | — | — |
| T-2 | [§3.2](#32-defaults) | The trait's parameters are in scope in a default's body. | `UndefVarError: T` when the default runs. | reference.jl, "T-2" |
| T-3 | — | *Retired*: see [§3.6](#36-supertraits-and-bundles). | — | — |
| T-4 | [§4.3](#43-forwarding-with-by) | The forwarding field may not also be a writable declared field. | Not checked. | `TraitWorld/src/implement.jl:526`, `:560` (`_field_problems`) |
| T-5 | [§4.7](#47-families) | A family takes a block of methods, also when its target is a parametric type expression: `@implement Fam S{P} where {P} begin … end`, the joint `@implement StateVector{T} Series{T} where {T} begin … end`. | Not lowered as a family whenever the target is not a bare variable (`A where {A <: …}`), with trait parameters or without: `S{P} where {P}` is taken as one type, the `UnionAll`, which no member matches. The block's `conformance` method has no builder, the members get no implementation, and a call raises `MethodError` with the hint. Only the earlier spelling (T-12) handles the joint form. Found by reading the code. | `TraitWorld/src/implement.jl:896`, `:900`–`902` |
| T-6 | [§4.7](#47-families) | A joint family's trait parameters are variables, constants and type constructors, never function calls. | Any expression is accepted and evaluated per member. | `TraitWorld/src/implement.jl:1008` (`_param_methods`) |
| T-7 | [§4.7](#47-families) | Forwarding for a whole family is planned as `@implement X Series{T} by f where {T}`. | Refused with "expected `project(t) = …` or a begin … end block after the type", which names a form the design does not have. Found by reading the code. | `TraitWorld/src/implement.jl:909`, `:1280` |
| T-8 | [§4.8](#48-generic-implementations) | A generic implementation applies to a trait with parameters as to one without. | For a trait with parameters, the form is taken as a family, and the constraints (`R: Indexable`) are read as `where` bounds. Found by reading the code. | `TraitWorld/src/implement.jl:1063` |
| T-9 | [§4.8](#48-generic-implementations) | Overlapping generic implementations are refused; a more specific one declares the same parameter values. | Nothing is checked at the declaration. At a call, a type matching two generic implementations raises `ImplementError` ("none more specific: add a specific implementation"). Specificity among generic implementations is not computed: every match counts. The parameter-value rule is not checked. | `TraitWorld/src/implement.jl:332`–`335`, `:368`, `:1110`–`1132` |
| T-10 | [§4.9](#49-checks-at-the-declaration) | Every failure at `@implement` raises `ImplementError`. | An operation without a method or a default in a block raises an `ErrorException`. Syntax errors in `@implement` are `ErrorException`s too. | `TraitWorld/src/implement.jl:841` |
| T-11 | [§4](#4-implementations) | Messages use the reference's terms: receiver type, implementation, forwarding. | Several messages still say "representation" or "projection", or suggest the earlier spelling: "owns neither the trait nor the representation", "the projection of T returns …", "cannot infer a concrete representation … `@implement Trait{R} T …`", "takes … the representation, last", "a projection needs exactly one `project(t) = …`", `TraitArgumentError`'s "at representation"; the one-line form's refusal of a parametric type, "the prototype does not declare parametric families this way", which does not name the `where` form. | `TraitWorld/src/implement.jl:501`, `:611`, `:618`, `:968`, `:1034`, `:1250`, `:1280`, `:1286`, `:1334`, `:1152`; `src/trait.jl:49`, `:80`; `src/core.jl:652` |
| T-12 | [§1](#1-syntax-summary) | The grammar has one spelling of traits and implementations. | The earlier spelling, with the receiver type as the trait's last parameter, is still accepted: `@trait ColTable{R}`, `ncols(r::R)::Int`, `@implement ColTable{MyType} begin … end`, `@implement X{R} where {…}`. Tests and the precompile workload still use it. | `TraitWorld/src/trait.jl:111`; `src/implement.jl:873`, `:963`; [open issues §3](../open-issues.md#3-traitworld-the-prototype), "Dependent code", item 13 |
| T-13 | [§3.1](#31-operations) | No annotation marks a mutating operation. | `@mutating` in a `@trait` body is accepted and recorded; nothing reads it. | `TraitWorld/src/trait.jl:35`, `:284`; `src/implement.jl:132` (`_mutating`, never called) |
| T-14 | [§4.3](#43-forwarding-with-by) | `by f` takes no block. | `@implement X T by f begin … end` is accepted: the block's methods become the implementation for the field's type. | `TraitWorld/src/implement.jl:912`, `:1347` |
| T-15 | [§4.2](#42-one-line) | No form computes a value from the type. | The internal form `@implement X T project(t) = …` is accepted: a body that reads a field as is forwards to it; any other body is refused with "computes a value". The flags `copies` and `unproject(t, r) = …` are refused with messages about retired features. | `TraitWorld/src/implement.jl:1280`–`1305`; reference.jl, "T-15" |
| T-16 | — | *Retired*: see [§5.1](#51-bounds). | — | — |
| T-17 | — | *Retired*: see [§5.8](#58-callable-functions-at-a-declared-signature). | — | — |
| T-18 | [§5.8](#58-callable-functions-at-a-declared-signature) | An open result type, `Callable{Tuple{Float64}, S} where S`, is a bound. | It is a plain argument; the call is a `MethodError`. | `TraitWorld/src/trait_module.jl:249`, `:290`; reference.jl, "T-18" |
| T-19 | [§9](#9-checks-and-when-they-run) | Definition checking at the module's end covers keyword, vararg and `Callable` functions; a first call checks only open parameters and open `Callable` results. | Keyword, vararg and every `Callable` function are checked at their first call. | `TraitWorld/src/defcheck.jl:85`–`92` (`archetype_sig`) |
| T-20 | [§5.6](#56-results-declared-types-like-withfields), [§13](#13-compiling-ahead) | `verify_main` lists the rebuilding step of `Like{t}` results. | It reports them as holes (`:inverse`). | `TraitWorld/src/verify.jl:746`, `:813` |
| T-21 | [§10.3](#103-strict-mode) | `PirateError` names the trait code the pirate would change. | It names the call signature (`Tuple{typeof(abs2), Float64}`); the trait-module function only when a walk up the callers finds it, which the tutorial's example does not. | `TraitWorld/src/strict.jl:74`, `:48` (`_trait_root`); [tutorial §18](../intro/traits-by-example.md) |
| T-22 | [§5.5](#55-dispatch-types-first-then-traits) | A value that conforms to no bound raises `MethodError` with a hint naming the bound. | The hint says "a Int64". Julia also prints "This error has been manually thrown", since the entry exists and throws. | `TraitWorld/src/frames.jl:75`; `src/entry.jl:499` |
| T-23 | [§14](#14-membership) | `x isa X` and `T <: X` answer whether a value or a type conforms, and `B <: A` whether `A` is a supertrait of `B`, once traits are in the type system. | Both are accepted today with Julia's meaning: a trait is an abstract type that no conforming type subtypes, so both are `false` for every conforming value and type. Between traits, `B <: A` is `false` too: every trait is a direct subtype of `Trait`, and supertraits are declarations the trait records (`supertype(B) === Trait` for `@trait B <: A`). | `TraitWorld/src/trait.jl:198` (`abstract type X{…} <: Trait`) |
| T-24 | — | *Retired*: see [§13](#13-compiling-ahead). | — | — |
| T-25 | — | *Retired*: see [§5.5](#55-dispatch-types-first-then-traits). | — | — |
| T-26 | — | *Retired*: see [§4.7](#47-families). | — | — |
| T-27 | — | *Retired*: see [§4.7](#47-families). | — | — |
| T-28 | [§4.7](#47-families) | The owner of a member's parameter type may declare an override for that member until its first use. | A member's own declaration is accepted and gets its own `conformance` method (`_declared_for` looks at the member itself, not the family's method), but a declaration after the member's first use is not refused: nothing records the first use against later declarations. Unchecked by a test. As [lowering L-23](lowering.md#18-deviations). | `TraitWorld/src/implement.jl` (`_declared_for`) |
| T-29 | — | *Retired*: see [§4.9](#49-checks-at-the-declaration). | — | — |
| T-30 | [§4.8](#48-generic-implementations) | Forwarding carries through a generic implementation: a type that forwards `Indexable` to a field forwards `GTable` to the same field. | A `by` declaration makes a `projection` record and no `implementation` record, so the generic implementation's constraint finds no witness for the forwarding type: it does not conform to `GTable`, and a call raises `MethodError`. Only an explicit `@implement GTable U by data` works. | `TraitWorld/src/implement.jl:337`–`367`, `:414`–`424`, `:1363`–`1366` |
| T-31 | [§4.4](#44-field-mappings), [§4.5](#45-several-traits-at-once) | Any traits take any form of implementation, field mappings included. | Several traits at once are handled only as `(X, Y) T by f`. `(X, Y) T name => stored` is refused with "a projection needs exactly one `project(t) = …`", and `(X, Y) T by f, name => stored` with "expected `project(t) = …` or a begin … end block after the type": both name forms the design does not have. | `TraitWorld/src/implement.jl:863`–`866`, `:1280`, `:1286` |
| T-32 | [§3.2](#32-defaults), [§4.9](#49-checks-at-the-declaration) | An implementation keeps a default or overrides it with the type's own method; a supertype owner's method defined before the declaration is part of it. | With a block, every operation the block leaves out is served by its default, whether or not the type has a method for it, and the override records leave such operations out: the existing method is not used, and a later redefinition of it is not refused. The one-line form follows the reference. | `TraitWorld/src/implement.jl:837`–`845`, `:648`; `src/core.jl:671`–`674` |
| T-33 | — | *Retired*: see [§4.9](#49-checks-at-the-declaration). | — | — |
| T-34 | [§5.5](#55-dispatch-types-first-then-traits), [§9](#9-checks-and-when-they-run) | A definition in a trait module that fails ownership raises `OwnershipError`; refused definitions raise the errors of the checks table. | These are `ErrorException`s: a bounded method added to another module's function where it has no entry of that shape; a vararg of `Callable`; `@specialize`; a vararg that is not last; `::Like{x}` naming no bounded argument; a keyword with several `Callable` bounds ([T-36](#17-deviations)). | `TraitWorld/src/trait_module.jl:537`–`539`, `:268`, `:260`, `:466`, `:522`, `:341` |
| T-35 | [§3.5](#35-self), [§5.6](#56-results-declared-types-like-withfields) | On a kept value, a constructor operation and a `Like` function return a kept value of the same form and attribute. | A constructor operation on a kept value of a trait with fields raises `TraitBoundError` ("declares fields"). A kept value of an immutable value kept by its parts, not whole, gives no `Like` result: `TraitBoundError`, "pass the value itself". | `TraitWorld/src/entry.jl` (`_dyn_like`, `_like_out`) |
| T-36 | [§1](#1-syntax-summary), [§5.7](#57-keywords-defaults-and-varargs) | An operation names its receiver (`t::Shape`); a keyword takes any bound, several `Callable`s included. | An unnamed receiver, `area(::Shape)::Float64`, is accepted. A keyword with several `Callable` bounds is refused with an `ErrorException`. | `TraitWorld/src/trait.jl:156`; `src/trait_module.jl:341` |
| T-37 | [§3.4](#34-parameters-and-associated-types), [§4.6](#46-stating-parameters) | An equation always holds: a stated value for a parameter an equation defines is checked against the equation, and an implementation where they disagree is refused with `ImplementError`. | Checked for an implementation of one type (`_param_agrees` in `TraitWorld/src/implement.jl`; `test/params.jl`). For a family (`@implement X{T} S{T} where {T}`) the stated value still replaces the equation's, unchecked: the equation is not evaluated at the family's free parameters. As [lowering L-26](lowering.md#18-deviations). | `implement.jl` (`_param_methods`) |
| T-38 | [§4.7](#47-families) | A family is declared as `@implement X S{P} where {P}`, also for a trait whose parameters are defined by equations (`@implement Iterable DynamicItems{X, V} where {X, V}`). | Refused with "a family `…` needs the trait's parameters": the form is taken as a joint family conforming by its fields, which requires every parameter to be defined by a field. The variable form works: `@implement Iterable D where {D <: DynamicItems}` (BaseTraits uses it). Found while writing BaseTraits. | `TraitWorld/src/implement.jl` (`_implement_expand`, the joint family branch) |
| T-39 | [§8.3](#83-a-users-container-taken-as-it-is), [§5.7](#57-keywords-defaults-and-varargs) | A container is taken at a bounded keyword as at a positional argument. | A bounded keyword is handled by `enter_kw`, which does not take a container through its item positions. A keyword bound that fixes a parameter (`shapes::Iterable{Shape}`) fails before that, for any value: `MethodError` from `trait_ops` at the trait instance (`Iterable{Dynamic{Shape}}`) instead of its family. Found while checking §10.3. | `TraitWorld/src/entry.jl` (`enter_kw`), `src/trait_module.jl` (the keyword's trait list); `experiments/hetero-idiomatic/reference_examples.jl` |
| T-40 | — | *Retired*: see [§6](#6-values-in-trait-code-compiled-and-dynamic). | — | — |
| T-41 | — | *Retired*: see [§6](#6-values-in-trait-code-compiled-and-dynamic). | — | — |
| T-42 | — | *Retired*: see [§5.1](#51-bounds). | — | — |
| T-43 | — | *Retired*: see [§5.8](#58-callable-functions-at-a-declared-signature). | — | — |
| T-44 | — | *Retired*: see [§8.2](#82-item-positions). | — | — |
| T-45 | — | *Retired*: see [§7](#7-kept-values-dynamicx-compiledx-keptx). | — | — |
| T-46 | — | *Retired*: see [§4](#4-implementations). | — | — |
| T-47 | — | *Retired*: see [§6.2](#62-how-plain-values-enter-the-trait-world). | — | — |
| T-48 | [§5](#5-bounded-functions), [§5.7](#57-keywords-defaults-and-varargs) | A bounded function may bound only keyword arguments (`f(; s::Shape)`, `f(n::Int; s::Shape)`). | Its entry and its worker have the same positional signature, so the later definition replaces the earlier: a call raises `TraitBoundError` ("no trait-bounded method … accepts trait objects of"). A bounded positional argument avoids it. Found while building W-4; the same on main (TraitWorld 5b172e1). | `TraitWorld/src/trait_module.jl` (`_rewrite_fdef`) |
| T-49 | [§3.1](#31-operations), [§6](#6-values-in-trait-code-compiled-and-dynamic) | An operation with an argument declared `Self` works on a `Dynamic` value. | At the erased key the argument's declared type is unknown, and the call raises `TraitArgumentError`. Found while building W-4 (by reading). | `TraitWorld/src/core.jl` (`opcall`), `src/attributes.jl` (`ErasedSelf`) |
| T-50 | — | *Retired*: see [§5.1](#51-bounds). | — | — |
| T-51 | [§5.8](#58-callable-functions-at-a-declared-signature) | A `Callable` takes any number of arguments, in either attribute. | A `Dynamic` function takes at most six: the erased call has fixed arities up to six. | `TraitWorld/src/core.jl` (`_CallWrap`, `Erased`'s call) |
| T-52 | [§4.8](#48-generic-implementations) | A type that conforms through a generic implementation and whose operations do not conform is refused at its first use (`ImplementError`). | It is accepted with a warning naming the problems (`_generic_problems`); the call then fails where the problem is, or returns a value of another type behind the result's assertion. Its concreteness and bounds are checked as designed. | `TraitWorld/src/implement.jl` (`_witness`, generic branch); `test/runtests.jl`, "M2" |
| T-53 | [§6.5](#65-values-carry) | A kept value of `X` passed to a bound of another trait `Y` is refused (`TraitBoundError`). | It is accepted when its object conforms to `Y`: the entry assembles `Y`'s view from the held object, a trait cast. One whose object does not conform raises `MethodError`. | `TraitWorld/src/entry.jl` (`enter`, `_dyn_held`) |
| T-54 | [§7.5](#75-functions-kept), [§6.5](#65-values-carry) | A function kept at one signature, passed to a bound of another signature, is refused (`TraitBoundError`). | It is accepted and seen there with its attribute: a `Dynamic` one through a new pointer (`_erased_at`), unchecked until its first call. TraitDifferentialEquations relies on it until its problem keeps the function as a tuple ([W-30](../record/todo.md)). | `TraitWorld/src/entry.jl` (`enter_callable`, `_erased_at`); `TraitDifferentialEquations/test/compiledcall.jl` |
