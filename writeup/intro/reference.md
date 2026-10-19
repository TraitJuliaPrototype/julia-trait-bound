# Traits: the reference

This page defines the trait language: its syntax, what each form means, what is checked and when, and the rules. It describes the language as designed, including the parts not built yet. Each construct says how far it is built.

- For a tutorial that builds one example step by step, read [Traits by example](traits-by-example.md).
- For why traits, and what they buy, read [Traits for Julia](traits-for-julia.md).
- The terms (trait, implementation, receiver type, key, trait object, entry, worker, stakeholder, pirate) are explained in the [glossary](../glossary.md).
- The mechanisms behind each rule are in [The mechanisms in detail](../design/mechanisms.md).

**Status labels.** Every section, and every form inside it that differs, carries one:
- **Implemented:** TraitWorld accepts it today, on the patched Julia 1.13.2 it needs.
- **Planned:** decided, not built. Each says what happens if you write it today.
- **Open:** not decided. The link names the question.

A rule stated under an Implemented heading is enforced, unless it says otherwise.

## Contents

1. [Syntax summary](#1-syntax-summary)
2. [Trait modules](#2-trait-modules)
3. [Trait declarations](#3-trait-declarations)
4. [Keys: what code is compiled for](#4-keys-what-code-is-compiled-for)
5. [Implementations](#5-implementations)
6. [Bounded functions](#6-bounded-functions)
7. [Results: declared types, `Like`, `withfields`](#7-results-declared-types-like-withfields)
8. [Keywords, defaults and varargs](#8-keywords-defaults-and-varargs)
9. [`Callable`: functions at a declared signature](#9-callable-functions-at-a-declared-signature)
10. [`Dynamic{X}`: values of any conforming type](#10-dynamicx-values-of-any-conforming-type)
11. [Checks, and when they run](#11-checks-and-when-they-run)
12. [Who may implement; pirates; strict mode](#12-who-may-implement-pirates-strict-mode)
13. [Concrete mode](#13-concrete-mode)
14. [Printing](#14-printing)
15. [Compiling ahead](#15-compiling-ahead)
16. [Membership](#16-membership)
17. [Named implementations](#17-named-implementations)
18. [Status index](#18-status-index)

---

## 1. Syntax summary

The grammar below is the language as designed. `X?` is optional, `X*` repeats zero or more times, `|` separates alternatives, quoted text is literal. `Name`, `Type` and `Expr` are Julia names, type expressions and expressions. Forms marked `(* planned *)` or `(* open *)` are not accepted today.

```ebnf
(* where trait code lives *)
TraitModule    ::= Level? "@trait_module" "module" Name Statement* "end"
                 | "@trait_module" "begin" Statement* "end"
Level          ::= "@warn_on_abstract" | "@error_on_abstract"

(* declaring a trait *)
Trait          ::= "@trait" Name Params? ( "<:" Supertraits )? ( "begin" TraitItem* "end" )?
Params         ::= "{" Param ( "," Param )* "}"
Param          ::= Name ( "<:" Type )?
Supertraits    ::= TraitRef | "(" TraitRef ( "," TraitRef )* ")"
TraitItem      ::= Operation | Operation "=" Expr          (* an operation; a default *)
                 | "@const"? Name "::" Type                 (* a declared field *)
                 | Name "=" Expr                            (* an equation: a parameter as a function of Self *)
                 | "@concrete_only" | "@warn_on_abstract"   (* concreteness *)
Operation      ::= OpName "(" Name "::" Receiver ( "," OpArg )* ")" "::" Type
OpName         ::= Name | Module "." Name
Receiver       ::= TraitName | TraitName "{" Type ( "," Type )* "}" | "Self"
OpArg          ::= Name "::" Type | "::" Type | Name
TraitRef       ::= TraitName ( "{" Type ( "," Type )* "}" )?

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
                 | "dynamic" "by" FieldName "begin" MethodDef* "end"  (* open *)
FieldMap       ::= FieldName "=>" FieldName

(* using a trait, inside a trait module *)
Method         ::= Name "(" Arg* ( ";" KwArg* )? ")" ( "::" Result )? ( "where" TypeVars )? "=" Expr
Arg            ::= Name "::" Bound | Name "::" Type | Name
                 | Arg "=" Expr                                      (* a positional default *)
                 | Name "::" TraitBound "..."                        (* a vararg of trait objects *)
KwArg          ::= ( Name "::" Bound | Name "::" Type | Name ) ( "=" Expr )?
Bound          ::= TraitBound | CallableBound | "(" CallableBound ( "," CallableBound )* ")"
TraitBound     ::= TraitRef | "(" TraitRef ( "," TraitRef )* ")"
CallableBound  ::= "Callable" "{" TupleType "," Type ( "," Mode )? "}"
Mode           ::= "DynamicCall" | "CompiledCall"
Result         ::= Type | "Like" "{" ArgName "}"

(* values *)
DynamicType    ::= "Dynamic" "{" TraitRef "}"
CallerMode     ::= "compiled_call" "(" Expr ")" | "dynamic_call" "(" Expr ")"
                 | "Callable" "{" TupleType "," Type "," Mode "}" "(" Expr ")"
StoredFunction ::= "dynamic_fn" "(" TupleType "," Type "," Expr ")"

(* planned *)
SharedParam    ::= Name "(" Name "::" TraitName "{" Name "}" "," Name "::" TraitName "{" Name "}" ")" "where" "{" Name "}"
FamilyForward  ::= "@implement" Traits Type ( "by" FieldName )? "where" "{" TypeVar* "}"
KwCallable     ::= "Callable" "{" TupleType "," Type "," Mode "," NamedTupleType "}"
OpenResult     ::= Name "::" "Callable" "{" TupleType "," Name "}" "where" Name
DynamicMulti   ::= "Dynamic" "{" "(" TraitRef ( "," TraitRef )* ")" "}"
BoundedClosure ::= "(" Name "::" TraitBound ")" "->" Expr
Membership     ::= Expr "isa" TraitRef | Type "<:" TraitRef
NamedImpl      ::= "Via" "{" Name "}" "(" Expr ")"
```

The concreteness declaration with one level argument is planned too; its spelling is open ([§3.7](#37-concreteness)).

TraitWorld also accepts an older spelling, with the receiver type as the trait's last parameter (`@trait ColTable{R}`, `ncols(r::R)::Int`, `@implement ColTable{MyType} begin … end`). It will be removed. Do not use it.

---

## 2. Trait modules

**Status: Implemented.**

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
- Julia compiles a trait module's methods in a separate mode, whoever calls them. In that mode, a call whose argument types are not all known is dispatched when it runs, never guessed at. So loading another package cannot discard the module's compiled code.
- Submodules of a trait module are trait modules.
- `@trait_module` runs each top-level statement after the ones before it. So a trait is known when a later function definition mentions it. `include` passes the same treatment on to the included file.

**Rules.**
- Bounded functions ([§6](#6-bounded-functions)) exist only inside trait modules. Outside, a trait in an argument annotation is an ordinary abstract type that no value has, so the method never applies.
- `@trait` and `@implement` work in any module. A user's types usually conform in plain code.
- A trait module may use and call any Julia code: Base, CSV, Cairo, ForwardDiff.
- At the end of a trait module, its bounded functions are checked ([§11](#11-checks-and-when-they-run)).
- A trait module may not define a pirate ([§12](#12-who-may-implement-pirates-strict-mode)). **Open** whether this stays: [open issues §1.20](../open-issues.md#1-decisions-waiting-for-the-user).
- A package is an ordinary module around its trait module. The package's own `module` line cannot carry `@trait_module`, since TraitWorld is not loaded yet there. Write `include("Core.jl")` with a `@trait_module module Core … end` inside, or a `@trait_module begin … end` block after `using TraitWorld`.

A prefix sets concrete mode for every function in the module ([§13](#13-concrete-mode)): `@warn_on_abstract @trait_module module M … end`, or `@error_on_abstract`.

---

## 3. Trait declarations

**Status: Implemented**, except where marked.

```julia
@trait Shape begin
    area(s::Shape)::Float64
    perimeter(s::Shape)::Float64
    summary(s::Shape)::String = "a shape of area $(area(s))"     # a default
end
```

**Meaning.**
- `@trait X` declares `X` as an abstract type, a subtype of `TraitWorld.Trait`.
- The body declares what a value must provide to conform: operations, fields, and the values of the trait's parameters.
- A trait without a body bundles other traits ([§3.6](#36-supertraits-and-bundles)).
- Declaring a trait defines no method on any user type and changes no compiled code.

### 3.1 Operations

```julia
ncols(t::ColTable)::Int
col(t::ColTable, i::Int)::Vector{Float64}
Base.length(t::HasLength)::Int                     # an existing function
Base.iterate(t::Iterable)::Union{Nothing, Tuple{eltype(Self), Any}}
Base.iterate(t::Iterable, state)::Union{Nothing, Tuple{eltype(Self), Any}}
```

- An operation is a generic function with declared argument and result types.
- **The first argument is the receiver.** Type it with the trait's name (`t::ColTable`), the trait with parameters (`v::KVec{T}`), or `Self`.
- **Every operation declares its result type.** A declaration without one is an error.
- Further arguments are typed as in a method: `i::Int`, `::Int` (no name), or untyped (`state`, which means `Any`).
- A plain name (`ncols`) creates a new function in the trait's module. A qualified name (`Base.length`) uses that existing function.
- One operation may be declared at several arities (`iterate` above), not twice at the same arity.
- The declared types may name the trait's parameters and `Self` ([§3.4](#34-parameters-and-associated-types), [§3.5](#35-self)).

**What is checked.**
- At each implementation: every operation has a method, or a default, for the receiver type, and the method's result infers to the declared type ([§5.10](#510-checks-at-the-declaration)).
- At every call on a trait object: the arguments against the declaration; the result is asserted to the declared type.
- An operation may mutate its arguments. A trait object refers to the user's object, so the change is visible to the user, as in plain Julia.

### 3.2 Defaults

```julia
firstcol(t::ColTable)::Vector{Float64} = col(t, 1)
```

- A default is an operation with a body, written in terms of the trait's other operations and fields.
- An implementation keeps it, or overrides it with its own method. Which one is fixed when the implementation is declared ([§5.10](#510-checks-at-the-declaration)).
- A default never throws "not implemented". An operation without a default must be implemented, and its absence is an error at `@implement`.
- A default serves trait objects and `Dynamic` values. It is not a method of the conforming type, so plain code calling the operation on the type directly finds no method ([§5](#5-implementations)).
- **Limit (Implemented as stated):** the trait's parameters are not in scope in a default's body. `state(m::M{T}, u0)::Vector{T} = Vector{T}(u0)` raises `UndefVarError: T` ([open issues §3](../open-issues.md#3-traitworld-the-prototype), "Found by the solvers agent", item 2).

### 3.3 Fields

```julia
@trait Integrator{U, P} begin
    u::U              # writable
    @const p::P       # read-only
    t::Float64        # writable, of a fixed type
end
```

- A declared field is a stored field the conforming type must have: same name (unless mapped, [§5.4](#54-field-mappings)), and the declared type.
- `t.name` reads it and `t.name = x` writes it, inside bounded code. Code may read and write only the fields its traits declare.
- `@const` makes a field read-only. It is the macro form of a struct's `const`.
- **A writable field needs** a mutable conforming type, a stored field that is not `const`, and a stored type exactly equal to the one the key records. So a write never changes a type compiled code relies on.
- A type with its own `getproperty` conforms only if it maps every declared field explicitly.
- Computed properties are not declared fields. A type whose data must be computed is converted by the library instead ([§5.2](#52-one-line)).
- Field types are part of the key ([§4](#4-keys-what-code-is-compiled-for)).

### 3.4 Parameters and associated types

```julia
@trait KVec{T} begin
    T = eltype(Self)                  # defined by an equation of the receiver type
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
  - **by the implementation**, when neither defines it: `@implement ArrayLike{Float32, 1} MyVec` ([§5.6](#56-stating-parameters)).
- A parameter defined by a field and by an equation is an error ("defined by the field").
- Operations and fields name the parameters: `kget(v::KVec{T}, i::Int)::T`.
- **Bounds on parameters,** `@trait ArrayLike{T <: Real, N}`: the syntax is accepted. Checking the bound at the implementation is **Planned**: today the bound is recorded and not checked.
- **Not offered:** a type conforming at several values of a parameter, equations between type functions, a parameter bound that names its own trait. `Callable` ([§9](#9-callable-functions-at-a-declared-signature)) is the one trait with several values per type.

### 3.5 `Self`

- In a trait's body, `Self` is the receiver type of the implementation at hand.
- It appears as the receiver's type (`f(t::Self)`), in result types, and in equations (`T = eltype(Self)`).
- **A constructor operation** declares `Self` as its result: `kwith(t::KTable, cs::Vector{Vector{Float64}})::Self`. Each implementation returns a new value of its receiver type. With `::Like{t}` ([§7](#7-results-declared-types-like-withfields)), this is how a library returns "a value like the input".
- On a `Dynamic` value, a constructor operation returns a `Dynamic` of the same implementation.

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
- A **bundle** names a combination of traits. A bound `t::Table` means `t::(ColTable, RowTable)`.
- **Planned:** a type's implementation of `B` must agree with its implementation of `A` (the same forwarding field, fields mapped alike). Today this is not checked ([decisions §1](../decisions.md#1-traits-implementations-and-keys)).

### 3.7 Concreteness

```julia
@trait Hot begin
    @concrete_only                     # an abstract key is refused
    hval(h::Hot)::Float64
end
```

- By default, a key may be abstract, silently. An abstract part of a key behaves like a dynamic value: the worker reads it and dispatches on what it finds.
- `@warn_on_abstract` in the body: an implementation with an abstract key warns.
- `@concrete_only` in the body: such an implementation is refused (`ImplementError`), and so is a family member at an abstract parameter, at the call (`TraitBoundError`).
- *Concrete* means a concrete type with concrete parameters, all the way down. Fields the trait does not declare are not looked at.
- Decide this when the trait is published. Adding it later breaks conforming types whose key is abstract.
- **Planned:** one declaration with a level (silent, warn, error), for a trait and for a module, replacing `@concrete_only`, `@warn_on_abstract` and `@error_on_abstract` ([decisions §1](../decisions.md#1-traits-implementations-and-keys)). Its spelling is **Open** ([open issues §1.15](../open-issues.md#1-decisions-waiting-for-the-user)).

---

## 4. Keys: what code is compiled for

**Status: Implemented.** There is no syntax for keys. They follow from the declarations.

- A bounded function reaches its argument only through the trait's operations and fields. So it is compiled per **key**, not per the argument's type.
- The key is:
  - the **receiver type**, if any: the type whose own methods serve at least one operation. That is the conforming type when it implements the operations, or the field's type when the implementation forwards to a field;
  - plus the declared fields' types.
- An implementation whose operations are all served by defaults has no receiver type. Its key is the declared fields' types alone.
- **Types with equal keys share compiled code.** Every type that forwards `ColTable` to a `Vector{Vector{Float64}}` field runs the code compiled for that field type, including code in the library's package image. Fields the trait does not declare never cause a recompile.
- **A type that supplies its own behaviour gets its own copy.** It implements an operation, or overrides a default, so it is the receiver type. Its code is compiled once, not "once for any type".
- A function with several bounded arguments is compiled per tuple of keys.

---

## 5. Implementations

`@implement` declares that a type conforms to a trait: an *implementation of `X` for `T`*. It is never inferred from the methods that happen to exist.

All forms share these properties:
- It may come after the type's definition, in another package.
- Its operations are served by the type's own methods, by a field it forwards to, or by the trait's defaults.
- It is checked when it is declared ([§5.10](#510-checks-at-the-declaration)).
- It changes no compiled code. Declaring one discards nothing.
- **Defaults and forwarding serve trait code only.** An implementation adds no methods to the type for the operations a default or a field serves. Called from plain code, `describe(c)` or `area(tile)` then has no method (`MethodError`). Plain code reaches them through a bounded function or a `Dynamic` value.

### 5.1 With a block of methods

**Status: Implemented.**

```julia
@implement ColTable Vector{Vector{Float64}} begin
    ncols(t) = length(t)
    col(t, i) = t[i]
end
```

- The block defines the operations' methods for the type and declares the implementation, in one step.
- Method names are the operations' names, unqualified. Each must be an operation of the trait, at a declared arity.
- The first argument is the receiver, typed as the conforming type. Unannotated arguments get the operation's declared types.
- `function name(args…) … end` works too.
- Operations the block leaves out are served by their defaults. One without a default is an error.

### 5.2 One line

**Status: Implemented.**

```julia
@implement ColTable Ramp           # Ramp has methods of ncols and col
@implement ColTable Measurements   # Measurements has a field that conforms
@implement Placed Sprite           # a trait of fields only: Sprite has the fields
```

`@implement X T` without a block decides how `T` conforms:
1. **`T`'s own methods,** if it has methods for every operation without a default. Define them before the declaration.
2. **Otherwise, forwarding to a field:** the field named `data`, if its type conforms, else the one field whose type conforms.
3. **A trait with fields only** conforms by the type's stored fields.

Errors, each naming the operations or fields:
- methods for some operations and not for others;
- several conforming fields and none named `data`: name one with `by` ([§5.3](#53-forwarding-with-by));
- no conforming field and no methods.

The one-line form needs a concrete type. A parametric type conforms as a family ([§5.7](#57-families)).

A type whose data needs a computation (a lazily derived table, a foreign layout) does not conform by a field. An implementation that computes a value is refused ("computes a value"). The library converts such a type explicitly, through a trait that reads it ([mechanisms §14](../design/mechanisms.md#14-types-that-only-convert)).

### 5.3 Forwarding with `by`

**Status: Implemented.**

```julia
@implement ColTable Halves by right
```

- The implementation forwards every operation to the field `right`. The field's type is the receiver type, so `Halves` shares the code compiled for that type.
- The field's type must implement the operations itself. **Forwarding does not chain:** a field whose type itself forwards is refused.
- Methods win over a field: if `T` implements the operations, write `@implement X T`, not `by`.
- Write `by` when several fields conform, or to make the choice explicit.

### 5.4 Field mappings

**Status: Implemented.**

```julia
@implement Named Book name => title            # Named declares `@const name::String`
@implement Stepper Clock by data, t => time    # with forwarding
```

- A declared field may be stored under another name: `declared => stored`.
- Several mappings are separated by commas.
- A type with its own `getproperty` must map every declared field.

### 5.5 Several traits at once

**Status: Implemented.**

```julia
@implement (ColTable, RowTable) Grid by data
@implement (ColTable, RowTable) Grid             # one line, the field inferred
```

- One declaration, one implementation per trait, all forwarding to the same field (or all served by `Grid`'s own methods).
- Each trait may also be implemented in its own declaration, through its own field: `@implement ColTable Sep by cols` and `@implement RowTable Sep by rows`.

### 5.6 Stating parameters

**Status: Implemented.**

```julia
@implement ArrayLike{Float32, 1} MyVec
@implement ODEModel{Float64} Lorenz
```

- An implementation states the values of parameters that no field and no equation defines.
- A stated value takes the place of the equation's value for that implementation.

### 5.7 Families

**Status: Implemented**, except forwarding for a family (Planned).

```julia
@implement Fam S{P} where {P}                            # every S{P}, by S's own methods
@implement Indexable A where {A <: AbstractVector}       # every subtype, by its existing methods
@implement KVec A where {A <: Vector{<:Real}} begin      # every member, with methods written here
    klen(v) = length(v)
    kget(v, i) = v[i]
end
@implement StateVector{T} Series{T} where {T}            # joint: the trait's T tied to the type's T
@implement IntegratorView Tsit5Integrator{T, P} where {T, P}   # a trait of fields: parameters from the fields
```

- A family implementation covers every instance of a parametric type, or every subtype of a type, declared with `where`.
- **A member's implementation is fixed at its first use,** not at the family's declaration. The package that owns a member's parameter type (`MyT` in `S{MyT}`) may define an override for that member until then, and not after.
- Workers compile per member.
- **Joint families:** each member conforms at one value of each trait parameter. Every variable of the trait's parameters must occur in the type.
- With `@concrete_only`, a member at an abstract parameter (`S{Any}`) is refused at the call.
- **Planned: forwarding for a whole family.** Write one declaration per member today: `@implement SVec LSeries{Float64} by data`, `@implement SVec LSeries{Float32} by data` ([open issues §2](../open-issues.md#2-design), "Keys and fields", item 4). The planned form is `@implement X Series{T} where {T}`, with the field inferred; where `by f` goes in that form is not written down ([§18](#18-status-index)).

### 5.8 Generic implementations

**Status: Implemented** (the form, more specific beats generic). **Planned:** the overlap rules. **Open:** what a predicate may say.

```julia
@implement GTable R where {R: Indexable, eltype(R) == Vector{Float64}} begin
    gn(r) = length(r)
    gcol(r, i) = r[i]
end
```

- One implementation covers every type that conforms to other traits. `R: Indexable` reads "`R` conforms to `Indexable`".
- Constraints are `R: Trait`, `R <: Type`, or a condition on `R`.
- Workers are still compiled per concrete key.
- A generic implementation makes types members only for a trait without declared fields. A trait with fields needs each type's own declaration, which maps them.
- **A more specific implementation beats a generic one** (`@implement GTable Matrix{Float64} begin … end`).
- **Planned:** a more specific implementation must declare the same parameter values; two overlapping generic implementations with neither more specific are rejected. Today there is no overlap check ([mechanisms §3](../design/mechanisms.md#3-generic-implementations)).
- **Open:** the design wants predicates to be patterns on the constraints' parameters, so that overlap is decidable. The example above uses a computed condition, `eltype(R) == …` ([open issues §2](../open-issues.md#2-design), "the design and the code disagree", item 2).

### 5.9 Dynamic operations

**Status: Open** ([open issues §2](../open-issues.md#2-design), "the design and the code disagree", item 3).

```julia
@implement ColTable Reversed dynamic by cols begin
    ncols(r) = length(r)
    col(r, i) = r[end - i + 1]
end
```

- TraitWorld accepts this form. The type gets operations of its own on its field, called through pointers, so the library's code for the field's type serves it.
- Its pointers belong to one session, so it does not work in a closed (`--trim`) build. Whether it stays is open. Prefer `@implement X T begin … end`.

### 5.10 Checks at the declaration

**Status: Implemented.** All of these run at `@implement`, never at a call. A failure raises `ImplementError` (an `ErrorException` for an operation without method or default in a block).

- **Who:** the declaring package owns the trait or the type ([§12](#12-who-may-implement-pirates-strict-mode)).
- **Completeness:** every operation has a method or a default for the receiver type. Every declared field exists, with the declared type.
- **Results:** each method's result infers to the operation's declared type. The message names the operation, the signature, and both types:

  ```
  `col` at Tuple{Counts, Int64} returns `Vector{Int64}`, declared `Vector{Float64}`
  ```
- **Writable fields** follow [§3.3](#33-fields).
- **Concreteness,** for a trait that asks for it ([§3.7](#37-concreteness)).
- **Overrides belong to the implementation.** Which operations are served by defaults is fixed now. A later method of such an operation for the type is refused when it is defined, naming the fix: define the method before `@implement`, or in its block, and restart Julia. A package image that brings such an override is refused when it loads.
- **No redeclaration.** Declaring an implementation again in a session is refused. To change one, change the declaration and restart Julia. **Planned:** redeclaration, using Julia 1.13's struct redefinition ([decisions §1](../decisions.md#1-traits-implementations-and-keys)).

Not everything is caught here: a conversion that fails at run time (a `Float64` buffer receiving dual numbers) is not proved by the check.

---

## 6. Bounded functions

**Status: Implemented**, except where marked. Bounded functions exist only inside trait modules ([§2](#2-trait-modules)).

```julia
colmean(t::ColTable, i::Int) = (c = col(t, i); sum(c) / length(c))
```

### 6.1 Bounds

- **A trait in an argument annotation is a bound.** `t::ColTable` accepts a value of any type that conforms to `ColTable`.
- **Several bounds on one argument:** `t::(ColTable, RowTable)`. The value must conform to each. A bundle trait is the same thing named.
- **A bound may fix parameters:** `s::StateVector{Float64}`. A value conforming at another value is refused at the call with `TraitBoundError`.
- Other arguments are ordinary: `i::Int`, `v::AbstractVector`, untyped. Ordinary `where` variables on ordinary arguments work as in Julia.
- **Planned: a parameter shared between bounds,** `f(a::ArrayLike{T}, b::ArrayLike{T}) where {T}`, requiring equal values, and reading `T` in the body. **Today such an annotation is read as a plain type, and the method never applies.** To get an associated type in the body, declare an operation that returns it in a container (`emptycells(c::Column{T}, n::Int)::Vector{T}`) and write `T = eltype(emptycells(c, 0))` ([open issues §3](../open-issues.md#3-traitworld-the-prototype), "Behind the notes", item 7).
- **Open:** how `Vector{<:ColTable}` in an argument takes a user's vector ([open issues §2](../open-issues.md#2-design), item 11).

### 6.2 What a bounded function receives

- It receives a **trait object**: the user's own object, seen through the bound. Nothing is copied. A write through a declared field reaches the user's object.
- It is compiled per key ([§4](#4-keys-what-code-is-compiled-for)).
- Technically a bounded function has two parts. Its **entry**, an ordinary method, translates each argument by its bound once; typed callers inline it. Its **worker** is the body, compiled per tuple of keys. You never write either part separately.

### 6.3 What trait code may do with a trait object

| In a trait module | Allowed |
|---|---|
| call the trait's operations on it; read its declared fields; write them unless `@const` | yes |
| pass it to another function with a bound it carries, or to an internal function without bounds | yes |
| use several trait objects in one function, of one trait or several | yes |
| capture it in a closure passed to Base (`sort!(p; lt = (i, j) -> …)`) | yes: the closure is checked like the function |
| keep it beyond the call as a `Dynamic{X}` ([§10](#10-dynamicx-values-of-any-conforming-type)) | yes |
| call any Julia code on ordinary values, such as the column `col` returns | yes |
| pass it where a different trait is expected | no: declare both bounds |
| pass it bare to an ordinary function (`sum(t)`), store it bare, return it bare, `typeof(t)`, a field no trait declares | no: code must not depend on the user's type |

A forbidden use is a `TraitUseError` ([§11](#11-checks-and-when-they-run)).

### 6.4 Internal functions

- Functions without bounds may take trait objects from bounded functions in the same module. They are compiled as part of the worker that calls them.
- Definition checking follows the trait object into them.
- Only bounded functions accept values from plain code as trait objects. A plain caller passing a value to an unbounded function passes the value itself, as in plain Julia.

### 6.5 Dispatch: types first, then traits

```julia
describe(v::Vector{Float64}) = "a vector"
describe(m::AbstractMatrix) = "a matrix"
describe(t::ColTable) = "a table with $(ncols(t)) columns"
describe(x) = "something else"                 # the entry's fallback
```

- **A trait bound ranks above `Any` and below every type,** concrete or abstract. `describe([1.0 2.0])` takes the `AbstractMatrix` method, although `Matrix{Float64}` is a `ColTable`. So a library adopts traits one function at a time.
- **Among bounds:** a subtrait beats its supertrait; more bounds beat fewer.
- **Unrelated bounds at one position need a joint method.** `f(t::ColTable)` and `f(t::RowTable)` need `f(t::(ColTable, RowTable))`. The trait module's end raises `TraitBoundError` otherwise. Only the function's own methods are involved, so no later load can create the ambiguity.
- A bounded method and a typed method that are ambiguous in another position are reported when defined.
- **The fallback:** an untyped method of the same shape, defined after the bounded ones, answers values that conform to none of the bounds. Without one, such a value raises `MethodError`, with a hint naming the bound.
- Only the package that defines a function ([§12.1](#121-who-may-implement)) may add a bounded method to it where it has no entry of that shape.

---

## 7. Results: declared types, `Like`, `withfields`

**Status: Implemented.**

```julia
total(t::ColTable)::Float64 = sum(sum(col(t, i)) for i in 1:ncols(t))       # an ordinary result type
kscaled(t::KTable, a::Float64)::Like{t} = kwith(t, [a .* kcol(t, i) for i in 1:kncols(t)])
shifted(r::LRec{Vector{Float64}})::Like{r} = withfields(r; u = r.u .+ 1.0)
```

- An ordinary result annotation works as in Julia.
- **`::Like{t}`** declares that the result is like argument `t`, which must be a bounded argument. The body returns a value of the receiver type (from a constructor operation) or a `withfields` result. The caller gets a value of its own type:
  - a type that implements the operations: the new receiver value, which must be of the same type;
  - a type that forwards: the user's object rebuilt by its constructor with the forwarded field replaced; other fields, such as labels, are kept.
- **A sibling:** the result may be the same family at another parameter, and the user's type is rebuilt there (`LSeries{Float64}` in, `LSeries{Float32}` out).
- **`withfields(t; name = value, …)`** replaces declared fields, for a trait with fields.
- `return x` inside a `Like` body works.
- Called with a `Dynamic`, a `Like` function returns a `Dynamic` of the same implementation.
- **Trait objects never go up bare.** A function that returns its trait object without `Like` raises `TraitUseError`.
- **Planned:** `verify_main` lists the rebuilding step for compiled-ahead builds ([§15](#15-compiling-ahead)).

---

## 8. Keywords, defaults and varargs

**Status: Implemented**, except `Callable` with keywords (Planned).

```julia
colz(t::ColTable, i::Int; baseline::ColTable = t, tol::Float64 = eps()) =
    (col(t, i) .- colmean(baseline, i)) ./ max(colrange(baseline, i), tol)
colmean_or(t::ColTable, i::Int = 1) = colmean(t, i)
ncols_sum(ts::ColTable...) = sum(ncols(t) for t in ts; init = 0)
```

- **Defaults are trait code.** They are evaluated inside, after the arguments are translated: `baseline = t` sees the trait object, `cols = 1:ncols(t)` may call an operation.
- **A positional default** makes two methods, as Julia does; each is bounded.
- **A keyword is typed like a positional argument:** by a trait bound, a `Callable` bound, a declared type, or the value supplied. A bounded keyword without a default is required.
- **No dispatch on keywords,** as in Julia. A bound on a keyword translates and refuses (`TraitBoundError`); it selects no method.
- A keyword's declared type is checked as in Julia: `tol = 1` for `tol::Float64` is a `TypeError`.
- **A vararg of trait objects,** `ts::ColTable...`, must be last. Its elements may have different keys; the worker compiles per tuple of keys.
- A vararg of `Callable` is refused. A vararg keyword (`kws...`) of a bounded function passes on unchanged.
- **Planned:** a function passed down with keywords, `Callable{A, S, M, K}` with `K` a named-tuple type ([mechanisms §11](../design/mechanisms.md#11-keyword-default-and-variable-arguments)). Today `Callable` has three parameters.

---

## 9. `Callable`: functions at a declared signature

**Status: Implemented**, except where marked.

```julia
colmap(f::Callable{Tuple{Float64}, Float64}, t::ColTable, i::Int) = map(f, col(t, i))                # default mode: DynamicCall
colsum(f::Callable{Tuple{Float64}, Float64, CompiledCall}, t::ColTable, i::Int) = sum(f, col(t, i))  # default mode: CompiledCall
both(f::(Callable{Tuple{Float64}, Float64}, Callable{Tuple{Int}, Int}), x::Float64, n::Int) = (f(x), f(n))

colmap(x -> 2x, m, 1)                    # the library's default
colmap(compiled_call(x -> 2x), m, 1)     # the caller asks for a compiled call
colsum(dynamic_call(x -> 2x), m, 1)      # the caller asks for a dynamic call
colsum(abs2, m, 1)                       # a function from Base or a trait module: called directly
```

**Meaning.**
- `Callable{A, S, M}` is a bound for a function argument: called with arguments of the tuple type `A`, it returns an `S`. `M` is the library's default mode.
- **Anything callable conforms:** closures, callable structs, generic functions. No implementation is declared.
- **Every call is checked:** the arguments against `A`; a result of another type than `S` is a `TypeError`, where plain Julia would widen. A function without a method for `A` raises `MethodError` when called.
- **Two modes, a choice of speed only, never of results:**
  - `DynamicCall` (the default when `M` is left out): the function is called through a pointer to its code compiled for `A`. The library's code is compiled once per signature, not per function. Each call is an indirect call. After a method of the function is redefined, a call computes what a plain call would compute at that point.
  - `CompiledCall`: the library's code is compiled per function, with the function inferred into it, at plain Julia's speed. The signature is still checked.
- **The library sets the default; the caller decides per value:** `compiled_call(f)`, `dynamic_call(f)`. `Callable{A, S, M}(f)` also fixes the signature. A bound without `M` accepts either mode.
- **Several signatures:** `f::(Callable{…}, Callable{…})`. A call picks the signature its arguments match; a call at an undeclared signature raises `MethodError`.
- **Functions from trait code** (Base's `abs2`, a trait module's own functions and closures) are called directly, whatever the mode.

**Stored functions.**

```julia
struct FunctionCallback
    cond::DynamicFn{Tuple{Vector{Float64}, Float64}, Bool}
end
callback(f) = FunctionCallback(dynamic_fn(Tuple{Vector{Float64}, Float64}, Bool, f))   # in plain code
```

- `DynamicFn{A, S}` is a function in `DynamicCall` mode as a value of fixed type, for a library's model or callback types. `dynamic_fn(A, S, f)` makes one, in plain code.

**Rules and limits.**
- **A `Callable` bound's signature must be constant.** `f::Callable{RHSSig{P, T}, Nothing}` with `P`, `T` a method's `where` variables is silently a plain argument today. Write one method per signature ([open issues §3](../open-issues.md#3-traitworld-the-prototype), "Found by the solvers agent", item 5).
- A dynamic call takes at most six arguments.
- **Planned: an open result type,** `f::Callable{Tuple{Float64}, S} where S`, inferred at the call and checked at every call ([mechanisms §10](../design/mechanisms.md#10-callable-and-its-two-modes)). Today it is not a bound.
- **Planned:** bounded closures `(u::ColTable) -> …`, and a `Callable` whose result is a `Callable` or a trait ([mechanisms §12](../design/mechanisms.md#12-functions-that-cross-the-boundary)).
- Closures returned from trait code to plain code are ordinary closures of the trait module. A closure that captured a trait object keeps the user's object.

---

## 10. `Dynamic{X}`: values of any conforming type

**Status: Implemented**, except where marked.

```julia
mutable struct State                 # in a trait module
    const u::Vector{Float64}
    model::Model                     # means Dynamic{Model}
    hooks::Vector{Hook}              # means Vector{Dynamic{Hook}}
end
start(m::Model, u0::Vector{Float64}) = State(copy(u0), Dynamic{Model}(m), Dynamic{Hook}[])

hooks = Dynamic{Hook}[Dynamic{Hook}(Below(0.9)), Dynamic{Hook}(Always())]   # in plain code
```

**Meaning.**
- `Dynamic{X}` is a value of any type that conforms to `X`, reached through `X`'s operations and fields. Use it for a value that outlives a call, a collection of mixed types, or a field whose type changes.
- **It holds the user's object.** It sees the user rebind a field, and writes through it reach the user's object.
- **An operation on it** tests for the declared implementations first, with direct calls that can inline, and falls back to a dynamic call. The result is asserted to the declared type, so code after it stays typed. The fast path covers up to four implementations.
- **Opened at a bound:** passed to a function bounded by `X`, it selects the code compiled for its key once, and that code runs compiled. Put loops over its data in such a function.
- A new implementation, declared later, works at once through the dynamic fallback, and discards no compiled code.

**Making one.**
- Inside a trait module: `Dynamic{X}(t)` from a trait object, or by storing a trait object where a `Dynamic{X}` is declared (`push!(s.hooks, h)`).
- In plain code: `Dynamic{X}(x)` for any value that conforms to `X`.
- A trait object carrying another trait cannot become a `Dynamic{X}` (`ArgumentError`).

**The trait's name as a type.**
- **Inside a trait module,** a trait's name in a struct field, a container's element type, or a container in an argument means its `Dynamic`: `model::Model`, `Vector{Hook}`, `Column[]`, `cs::Vector{Column}`.
- A trait's name directly in an argument stays a bound.
- **Outside trait modules,** write `Dynamic{X}` out.

**Equality and printing.** Two `Dynamic{X}` are equal when they hold the same trait object (`===`): a mutable object by identity, an immutable one by value. `hash` agrees. It prints as `Dynamic{X} at` its key: `Dynamic{Shape} at Circle`.

**Assigning from plain code.** A field declared `Dynamic{X}` converts on assignment only from a trait object. For `obj.field = value` from plain code, define `Base.convert(::Type{Dynamic{X}}, x) = Dynamic{X}(x)` for your trait. **Planned:** that conversion for every trait, built in ([open issues §3](../open-issues.md#3-traitworld-the-prototype), "From the demonstrators", item 2).

**Planned.**
- `Dynamic{(ColTable, RowTable)}`, a value seen through several traits.
- A trait's own declared `==`; serialization of a `Dynamic` with its implementation.
- A faster path beyond four implementations ([open issues §2](../open-issues.md#2-design)).

**Open.** Opening a `Dynamic` at the conforming value's own concrete type, a checked downcast ([open issues §2](../open-issues.md#2-design), item 16). Today, assert it in plain Julia: `m = integ.p::Lorenz{Float64}`.

**Limit.** A result through an opened `Dynamic` is not inferred. Assert it: `asdcol(g)::Dynamic{DCol}`.

---

## 11. Checks, and when they run

**Status: Implemented.**

| When | What is checked | Error |
|---|---|---|
| `@trait` | the body's form: result types present, the receiver typed by the trait, no parameter defined twice | `ErrorException` |
| `@implement` | ownership, completeness, result types, fields, concreteness ([§5.10](#510-checks-at-the-declaration)) | `ImplementError` |
| a method definition after `@implement` | an override of an operation a default serves | `ImplementError` |
| a definition in a trait module | the module owns the method's function or a type in it | `OwnershipError` |
| the end of a trait module | every bounded function, once, for every type that will ever conform; ambiguous bounds | `TraitUseError`, `TraitBoundError` |
| a call, at the entry | the value conforms; fixed parameters; bounded keywords; concreteness of a family member | `MethodError` (with a hint), `TraitBoundError` |
| a call to a `Callable` | the arguments and the result | `TypeError`, `MethodError` |
| a worker's first call | what the end of the module could not check: open parameters, `Callable` workers, keyword and vararg workers | `TraitUseError` |

**Definition checking** at the end of a trait module infers each bounded function once at an *archetype*: a stand-in value whose operations and fields return values of their declared types and nothing more. A mistake is reported at its line before any type conforms:

```julia
spread(t::ColTable) = size(t)    # `size` is not an operation of ColTable
leak(t::ColTable) = typeof(t)    # code must not depend on the user's type
```

- While a package is precompiled, the report is an error, and the build fails.
- For a trait module defined at the prompt or in a script, it is a warning. The call then raises the `TraitUseError`.
- `check_definitions(M)` runs the check on demand: it returns an empty list, or raises `TraitUseError` listing the problems.

---

## 12. Who may implement; pirates; strict mode

### 12.1 Who may implement

**Status: Implemented.**

- A package *owns* the functions and types it defines. Julia (Core, Base, the standard libraries) is one owner. A package extension counts as its parent package. Code at the prompt is owned by the session.
- An implementation is a method, so ordinary ownership decides who may write it: **the trait's owner or the type's owner.** A third package may not.
- An implementation for a foreign trait and a foreign type belongs in the trait owner's package extension.
- Operations that are existing functions (`Base.size`) may be implemented only for types the declaring package owns. Otherwise declare the existing methods: `@implement Sized Vector{Float32}` without a block, by Base's own methods.

### 12.2 Pirates

- A **pirate** is a method of a function you do not own, for types you do not own: Julia's "type piracy".
- **A trait module may not define one:** `OwnershipError` at the definition. A `Union` with one of your own types is no way around it, nor a lower-bounded type variable. **Open** whether this check stays, or only winning pirates are refused under strict mode ([open issues §1.20](../open-issues.md#1-decisions-waiting-for-the-user)).
- In plain code, a pirate is followed by default, as in plain Julia. Trait code it changes is compiled again once.
- Methods for your own types are never pirates: `Base.show(io::IO, x::MyType)` is fine everywhere.

### 12.3 Strict mode

**Status: Implemented** as a prototype; its full design is **Planned** ([decisions §4](../decisions.md#4-ownership-strict-mode-and-the-guarantee)).

```julia
TraitWorld.strict!(true)        # or start Julia with JULIA_TW_STRICT=1
```

- Strict mode refuses a pirate when it would win at a call that compiled trait code makes. The error, `TraitWorld.PirateError`, names the method and the call in trait code it would change. The method then does not exist, for plain code either.
- Nothing else is refused: a pirate that wins nowhere in trait code is accepted.
- A definition by a stakeholder is followed. A *stakeholder* of a method is the owner of its function or of a type in its signature. Define as the owner with `@eval Owner f(…) = …`.
- `TraitWorld.delegate!(Core => Impl)` lets an implementation package count as the owner of the core package it implements (for split packages such as StaticArraysCore and StaticArrays).
- **Planned:** errors for pirates loaded before the code they change, and for package extensions; a lint in `verify_main` for calls that select a pirate ([open issues §1.10](../open-issues.md#1-decisions-waiting-for-the-user)).

### 12.4 No sealing

**Status: Implemented** (a decision, [decisions §4](../decisions.md#4-ownership-strict-mode-and-the-guarantee)).

- Abstract types and functions are not sealed. Anyone may add a subtype or a method, as in Julia today.
- A closed contract is a trait: its operations, their declared result types, and the check at every implementation.

---

## 13. Concrete mode

**Status: Implemented** (today's spellings; one declaration with a level is Planned, [§3.7](#37-concreteness)).

```julia
@error_on_abstract @trait_module module Hot … end       # every function of the module
@warn_on_abstract cold(t::ColTable, k::Vector{Any}) = …  # one function, inside a trait module
fully_typed(Columns.colmean, (Vector{Vector{Float64}}, Int))   # a report, anywhere
```

- Code is **fully typed** when every call in it, and in what it calls, has known argument types. Such code pays nothing for the trait modules' compiler mode.
- `fully_typed(f, argtypes)` reports the calls that are not, with their root cause through any number of layers ("field `scale` of `Config` is declared `Real`"). `isfullytyped(report)` answers yes or no. Operations on `Dynamic` values count as declared, not as faults.
- `@warn_on_abstract` warns at a worker's first run; `@error_on_abstract` raises `AbstractTypeError` (an abstract value used) or `NotFullyTypedError` (a call with unknown types).
- **Open:** whether a variable of a small `Union` should warn ([open issues §1.18](../open-issues.md#1-decisions-waiting-for-the-user)). Today it does not: its splits have known types.

---

## 14. Printing

**Status: Implemented** (needs the patched Julia's type printers).

- A trait object's type prints by bound and key: `ColTable at Vector{Vector{Float64}}`, `PVec{Float64} at Vector{Float64}`. The user's other fields never appear.
- A function bound prints as `Callable{Tuple{Float64}, Float64} at DynamicCall`, or at the function's type in `CompiledCall` mode.
- A `Dynamic` prints as its trait and key: `Dynamic{Shape} at Circle`.
- Stack traces hide TraitWorld's own frames. `JULIA_TW_ALL_FRAMES=1` shows them.

---

## 15. Compiling ahead

**Status: Implemented.** No syntax: it follows from `@implement` in a package.

- While a package that declares `@implement X T` is precompiled, the trait code that `T` needs is compiled into that package's image:
  - the workers of every bounded function whose bound includes `X`, at `T`'s key, where the other arguments are concrete;
  - an entry method for `T` itself, for callers that do not know the type;
  - the first-call checks, whose results the image keeps. A failing check fails the build.
- A caller that does not know the argument's type, of a type not compiled ahead, goes through a table of declared implementations. Nothing is compiled per type.
- `TraitWorld.@workload begin … end` is a precompile workload for a trait module (PrecompileTools' `@compile_workload`, reached through TraitWorld).
- `verify_main(main, (Vector{String},); entrypoints = true)` lists every target a program can reach through trait code, for `juliac --trim`. Plain code reached from trait code keeps plain Julia's properties, and its open dynamic calls are reported. A `--trim` build compiles plain code: nothing loads in a binary, so nothing needs protecting.
- `JULIA_TW_AHEAD=0` turns compiling ahead off, for measurement.

---

## 16. Membership

- **Implemented:** `conforms(T, X)` answers whether type `T` conforms to trait `X`. With fixed parameters, `conforms(Vector{Int}, PVec{Float64})` is `false`. `conforms(Dynamic{X}, X)` is `true`.
- **Planned:** `x isa X` and `T <: X`, when traits are in Julia's type system. An implementation then adds a supertype after the type is defined. Until then `x isa ColTable` is `false` for every `x` ([mechanisms §7](../design/mechanisms.md#7-traits-as-abstract-types-and-dispatch)).
- Numbers need no trait. `Number`, `Real` and `Integer` stay as they are.

---

## 17. Named implementations

**Status: Planned** (deferred until traits are in the type system; [decisions §3](../decisions.md#3-dynamic-values-and-functions)).

- A second implementation of a trait for a type, used only where a caller names it.
- The preferred form is a wrapper value that conforms, a newtype: `Via{Fast}(x)`.
- Until then, a foreign trait for a foreign type needs the trait's owner, the type's owner, or your own wrapper type: `struct FastM; m::M; end` with its own implementation.

---

## 18. Status index

| Construct | Status | Where decided or open |
|---|---|---|
| `@trait_module`, the module and block forms | Implemented | [decisions §5](../decisions.md#5-the-compiler-and-julia) |
| `@trait`: operations, result types, `Self` | Implemented | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| defaults | Implemented | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| declared fields, `@const` | Implemented | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| parameters by field, by equation, stated | Implemented | [decisions §2](../decisions.md#2-parameters-checking-and-results) |
| bounds on parameters, checked | Planned (syntax accepted, not checked) | [mechanisms §1](../design/mechanisms.md#associated-types) |
| a trait's parameter in a default's body | Planned (today `UndefVarError`) | [open issues §3](../open-issues.md#3-traitworld-the-prototype) |
| supertraits, bundles | Implemented | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| supertrait agreement check | Planned | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| `@concrete_only`, `@warn_on_abstract`, `@error_on_abstract` | Implemented | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| one concreteness declaration with a level | Planned; spelling Open | [open issues §1.15](../open-issues.md#1-decisions-waiting-for-the-user) |
| keys | Implemented | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| `@implement X T begin … end` | Implemented | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| `@implement X T` (one line) | Implemented | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| `by f` | Implemented | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| field mappings `name => stored` | Implemented | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| several traits at once | Implemented | [mechanisms §5](../design/mechanisms.md#5-several-traits-on-one-object) |
| stated parameters `X{P…} T` | Implemented | [decisions §2](../decisions.md#2-parameters-checking-and-results) |
| families, joint families | Implemented | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| forwarding for a whole family | Planned | [open issues §2](../open-issues.md#2-design) |
| generic implementations | Implemented | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| overlap rules for generic implementations | Planned | [mechanisms §3](../design/mechanisms.md#3-generic-implementations) |
| what a generic predicate may say | Open | [open issues §2](../open-issues.md#2-design) |
| `dynamic by f` | Open | [open issues §2](../open-issues.md#2-design) |
| overrides fixed at the declaration; family members at first use | Implemented | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| redeclaring an implementation | Planned (today: restart) | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| bounds on arguments, several bounds, fixed parameters | Implemented | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| shared `where` parameters in bounds | Planned (today: never applies) | [open issues §3](../open-issues.md#3-traitworld-the-prototype) |
| `Vector{<:X}` arguments | Open | [open issues §2](../open-issues.md#2-design) |
| internal functions without bounds | Implemented | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| types first, then traits; joint-method rule; fallback | Implemented | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| result types, `Like{t}`, `withfields`, siblings | Implemented | [decisions §2](../decisions.md#2-parameters-checking-and-results) |
| keywords, defaults, varargs at entries | Implemented | [mechanisms §11](../design/mechanisms.md#11-keyword-default-and-variable-arguments) |
| `Callable{A, S, M}`, both modes, caller override | Implemented | [decisions §3](../decisions.md#3-dynamic-values-and-functions) |
| `DynamicFn`, `dynamic_fn` | Implemented | [decisions §3](../decisions.md#3-dynamic-values-and-functions) |
| `Callable{A, S, M, K}` with keywords | Planned | [open issues §2](../open-issues.md#2-design) |
| open `Callable` result types | Planned | [mechanisms §10](../design/mechanisms.md#10-callable-and-its-two-modes) |
| bounded closures | Planned | [open issues §2](../open-issues.md#2-design) |
| `Dynamic{X}`, the trait name as `Dynamic` inside trait modules | Implemented | [decisions §3](../decisions.md#3-dynamic-values-and-functions) |
| `convert` to `Dynamic{X}` for every trait | Planned | [open issues §3](../open-issues.md#3-traitworld-the-prototype) |
| `Dynamic{(X, Y)}`, a trait's `==`, serialization | Planned | [open issues §2](../open-issues.md#2-design) |
| opening a `Dynamic` at its concrete type | Open | [open issues §2](../open-issues.md#2-design) |
| definition checking | Implemented | [decisions §2](../decisions.md#2-parameters-checking-and-results) |
| who may implement | Implemented | [decisions §4](../decisions.md#4-ownership-strict-mode-and-the-guarantee) |
| no pirates in trait modules | Implemented; whether it stays is Open | [open issues §1.20](../open-issues.md#1-decisions-waiting-for-the-user) |
| strict mode (prototype) | Implemented; full design Planned | [decisions §4](../decisions.md#4-ownership-strict-mode-and-the-guarantee) |
| no sealing | Implemented (decided) | [decisions §4](../decisions.md#4-ownership-strict-mode-and-the-guarantee) |
| concrete mode, `fully_typed` | Implemented | [decisions §2](../decisions.md#2-parameters-checking-and-results) |
| warning on small unions | Open | [open issues §1.18](../open-issues.md#1-decisions-waiting-for-the-user) |
| printing by bound and key | Implemented | [decisions §2](../decisions.md#2-parameters-checking-and-results) |
| compiling ahead from `@implement` | Implemented | [decisions §6](../decisions.md#6-aot) |
| `verify_main`, `@workload` | Implemented | [decisions §6](../decisions.md#6-aot) |
| `conforms(T, X)` | Implemented | [decisions §1](../decisions.md#1-traits-implementations-and-keys) |
| `x isa X`, `T <: X` | Planned | [mechanisms §7](../design/mechanisms.md#7-traits-as-abstract-types-and-dispatch) |
| named implementations, `Via{Fast}(x)` | Planned (deferred) | [decisions §3](../decisions.md#3-dynamic-values-and-functions) |
