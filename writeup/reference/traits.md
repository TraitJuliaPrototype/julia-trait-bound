# Traits: the reference

This page defines the trait language: its syntax, what each form means, what is checked and when, and the rules, as user code sees them. It describes the language as designed, including the parts not built yet. Where TraitWorld, the prototype, does something else today, the [Deviations](#19-deviations) table at the end says so.

- For a tutorial that builds one example step by step, read [Traits by example](../intro/traits-by-example.md).
- For why traits, and what they buy, read [Traits for Julia](../intro/traits-for-julia.md).
- The terms (trait, implementation, receiver type, key, trait object, entry, worker, stakeholder, pirate) are explained in the [glossary](../glossary.md).
- The other references: what compiled code may assume, in [`facts.md`](facts.md); how each construct is built on Julia, in [`lowering.md`](lowering.md); the Julia interfaces both rely on, in [`compiler.md`](compiler.md).

**Status labels.** Every section ends with one:
- **Implemented:** TraitWorld accepts it today, on the patched Julia 1.13.2 it needs.
- **Planned:** decided, not built.
- **Open:** not decided. The link names the question in [`../open-issues.md`](../open-issues.md).

A rule in an Implemented section is enforced, unless the Deviations table lists it. A Planned form is written as it will be. Writing it today is refused, unless the Deviations table says otherwise.

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
19. [Deviations](#19-deviations)

---

## 1. Syntax summary

The grammar below is the language as designed. `X?` is optional, `X*` repeats zero or more times, `|` separates alternatives, quoted text is literal. `Name`, `Type` and `Expr` are Julia names, type expressions and expressions.

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
FamilyForward  ::= "@implement" Traits Type "by" FieldName "where" "{" TypeVar* "}"
KwCallable     ::= "Callable" "{" TupleType "," Type "," Mode "," NamedTupleType "}"
OpenResult     ::= Name "::" "Callable" "{" TupleType "," Name "}" "where" Name
DynamicMulti   ::= "Dynamic" "{" "(" TraitRef ( "," TraitRef )* ")" "}"
BoundedClosure ::= "(" Name "::" TraitBound ")" "->" Expr
Membership     ::= Expr "isa" TraitRef | Type "<:" TraitRef
NamedImpl      ::= "Via" "{" Name "}" "(" Expr ")"
```

The concreteness declaration with one level argument is planned too; its spelling is open ([§3.7](#37-concreteness)).

**Status:** Implemented, except the forms under `(* planned *)` (Planned) and `dynamic by` (Open). TraitWorld also accepts forms that are not in this grammar: [T-12](#19-deviations) to [T-15](#19-deviations).

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
- Julia compiles a trait module's methods in its *facts mode*, whoever calls them. In that mode, a call whose argument types are not all known is dispatched when it runs, never guessed at. So loading another package cannot discard the module's compiled code. What compiled code may assume, and why: [`facts.md`](facts.md#the-facts-mode).
- Submodules of a trait module are trait modules.
- `@trait_module` runs each top-level statement after the ones before it. So a trait is known when a later function definition mentions it. `include` passes the same treatment on to the included file.

**Rules.**
- Bounded functions ([§6](#6-bounded-functions)) exist only inside trait modules. Outside, a trait in an argument annotation is an ordinary abstract type that no value has, so the method never applies.
- `@trait` and `@implement` work in any module. A user's types usually conform in plain code.
- A trait module may use and call any Julia code: Base, CSV, Cairo, ForwardDiff.
- At the end of a trait module, its bounded functions are checked ([§11](#11-checks-and-when-they-run)).
- A trait module may not define a pirate ([§12.2](#122-pirates)).
- A package is an ordinary module around its trait module. The package's own `module` line cannot carry `@trait_module`, since TraitWorld is not loaded yet there. Write `include("Core.jl")` with a `@trait_module module Core … end` inside, or a `@trait_module begin … end` block after `using TraitWorld`.

A prefix sets concrete mode for every function in the module ([§13](#13-concrete-mode)): `@warn_on_abstract @trait_module module M … end`, or `@error_on_abstract`.

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
- `@trait X` declares `X` as an abstract type, a subtype of `TraitWorld.Trait`.
- The body declares what a value must provide to conform: operations, fields, and the values of the trait's parameters.
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
- **The first argument is the receiver.** Type it with the trait's name (`t::ColTable`), the trait with parameters (`v::KVec{T}`), or `Self`.
- **Every operation declares its result type.** A declaration without one is an error.
- Further arguments are typed as in a method: `i::Int`, `::Int` (no name), or untyped (`state`, which means `Any`).
- A plain name (`ncols`) creates a new function in the trait's module. A qualified name (`Base.length`) uses that existing function.
- One operation may be declared at several arities (`iterate` above), not twice at the same arity.
- The declared types may name the trait's parameters and `Self` ([§3.4](#34-parameters-and-associated-types), [§3.5](#35-self)).
- An operation may mutate its arguments. A trait object refers to the user's object, so the change is visible to the user, as in plain Julia. No annotation marks such an operation.

**What is checked.**
- At each implementation: every operation has a method, or a default, for the receiver type, and the method's result infers to the declared type ([§5.10](#510-checks-at-the-declaration)).
- At every call on a trait object: the arguments against the declaration; the result is asserted to the declared type.

**Status:** Implemented.

### 3.2 Defaults

```julia
firstcol(t::ColTable)::Vector{Float64} = col(t, 1)
```

- A default is an operation with a body, written in terms of the trait's other operations and fields.
- The trait's parameters are in scope in the body: `state(m::M{T}, u0)::Vector{T} = Vector{T}(u0)`.
- An implementation keeps it, or overrides it with its own method. Which one is fixed when the implementation is declared ([§5.10](#510-checks-at-the-declaration)).
- A default never throws "not implemented". An operation without a default must be implemented, and its absence is an error at `@implement`.
- A default serves trait objects and `Dynamic` values. It is not a method of the conforming type, so plain code calling the operation on the type directly finds no method ([§5](#5-implementations)).

**Status:** Implemented, except the trait's parameters in a default's body (Planned; [T-2](#19-deviations)).

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
- A declared field is read from the stored field, never through `getproperty`. So a type with its own `getproperty` conforms only if it maps every declared field explicitly: the mapping says that plain `x.name` may differ from `t.name`.
- Computed properties are not declared fields. A type whose data must be computed is converted by the library instead ([§5.11](#511-types-that-only-convert)).
- Field types are part of the key ([§4](#4-keys-what-code-is-compiled-for)).

**Status:** Implemented.

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
- **Bounds on parameters,** `@trait ArrayLike{T <: Real, N}` or `T <: NumberLike` with a trait. The bound is checked at every implementation: a value outside it is refused with `ImplementError`. A trait bound also lets definition checking ([§11](#11-checks-and-when-they-run)) cover code that computes with the parameter.
- **Not offered:** a type conforming at several values of a parameter, equations between type functions, a parameter bound that names its own trait. `Callable` ([§9](#9-callable-functions-at-a-declared-signature)) is the one trait with several values per type.

**Status:** Implemented, except bounds on parameters (Planned; the syntax is accepted, [T-1](#19-deviations)).

### 3.5 `Self`

- In a trait's body, `Self` is the receiver type of the implementation at hand.
- It appears as the receiver's type (`f(t::Self)`), in result types, and in equations (`T = eltype(Self)`).
- **A constructor operation** declares `Self` as its result: `kwith(t::KTable, cs::Vector{Vector{Float64}})::Self`. Each implementation returns a new value of its receiver type. With `::Like{t}` ([§7](#7-results-declared-types-like-withfields)), this is how a library returns "a value like the input".
- On a `Dynamic` value, a constructor operation returns a `Dynamic` of the same implementation.

**Status:** Implemented.

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

**Status:** Implemented, except the agreement check (Planned; [T-3](#19-deviations)).

### 3.7 Concreteness

```julia
@trait Hot begin
    @concrete_only                     # an abstract key is refused
    hval(h::Hot)::Float64
end
```

- By default, a key may be abstract, silently.
- **An abstract part of a key behaves like a dynamic value.** A type that forwards to a field declared `AbstractVector{Float64}` gets one compiled copy for that key, whatever the field holds. Operations on that part dispatch when they run. Passed on to another bounded function, the part is opened there by its run-time type, and that function runs compiled for it: a function barrier the author need not write.
- `@warn_on_abstract` in the body: an implementation with an abstract key warns.
- `@concrete_only` in the body: such an implementation is refused (`ImplementError`), and so is a family member at an abstract parameter, at the call (`TraitBoundError`).
- *Concrete* means a concrete type with concrete parameters, all the way down. Fields the trait does not declare are not looked at.
- Decide this when the trait is published. Adding it later breaks conforming types whose key is abstract.
- The design has **one declaration with a level** (silent, warn, error), for a trait and for a module. It replaces `@concrete_only`, `@warn_on_abstract` and `@error_on_abstract`.

**Status:** Implemented with today's three spellings. The one declaration with a level is Planned; its spelling is Open ([open issues §1.15](../open-issues.md#1-decisions-waiting-for-the-user)).

---

## 4. Keys: what code is compiled for

There is no syntax for keys. They follow from the declarations.

- A bounded function reaches its argument only through the trait's operations and fields. So it is compiled per **key**, not per the argument's type.
- The key is:
  - the **receiver type**, if any: the type whose own methods serve at least one operation. That is the conforming type when it implements the operations, or the field's type when the implementation forwards to a field;
  - plus the declared fields' types.
- An implementation whose operations are all served by defaults has no receiver type. Its key is the declared fields' types alone.
- **Types with equal keys share compiled code.** Every type that forwards `ColTable` to a `Vector{Vector{Float64}}` field runs the code compiled for that field type, including code in the library's package image. Fields the trait does not declare never cause a recompile.
- **A type that supplies its own behaviour gets its own copy.** It implements an operation, or overrides a default, so it is the receiver type. Its code is compiled once, not "once for any type".
- A function with several bounded arguments is compiled per tuple of keys.

How a key is represented in compiled code: [`lowering.md`](lowering.md#5-keys-and-views).

**Status:** Implemented.

---

## 5. Implementations

`@implement` declares that a type conforms to a trait: an *implementation of `X` for `T`*. It is never inferred from the methods that happen to exist.

All forms share these properties:
- It may come after the type's definition, in another package.
- Its operations are served by the type's own methods, by a field it forwards to, or by the trait's defaults.
- It is checked when it is declared ([§5.10](#510-checks-at-the-declaration)).
- It changes no compiled code. Declaring one discards nothing.
- **Defaults and forwarding serve trait code only.** An implementation adds no methods to the type for the operations a default or a field serves. Called from plain code, `describe(c)` or `area(tile)` then has no method (`MethodError`). Plain code reaches them through a bounded function or a `Dynamic` value.

**The operations' methods and the implementation are separate.**
- The *methods* serve the operations for a type.
- The *implementation* says how a type joins the trait, fields included.
- A type that implements the operations need not have the declared fields. It then does not conform, but it can be the field another type forwards to. `Vector{Vector{Float64}}` implements `ColTable`'s operations. If `ColTable` declared a field `name`, a bare vector would not conform, and a `Measurements` holding one and a name would.

How an implementation is recorded, so that declaring one invalidates nothing: [`lowering.md`](lowering.md#4-implementations).

**Status:** Implemented.

### 5.1 With a block of methods

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

**Status:** Implemented.

### 5.2 One line

```julia
@implement ColTable Ramp           # Ramp has methods of ncols and col
@implement Placed Sprite           # a trait of fields only: Sprite has the fields
```

`@implement X T` without a block or `by` says that `T` implements the trait itself:
1. **`T`'s own methods** serve every operation without a default. Define them before the declaration.
2. **A trait with fields only** is served by the type's stored fields.

**No field is special.** The one-line form never forwards to a field: not one named `data`, not the only field whose type conforms. Forwarding is always written with `by` ([§5.3](#53-forwarding-with-by)).

Errors, each naming the operations:
- methods for some operations and not for others;
- no methods. The message lists the fields whose type conforms, each with its `by` line.

The one-line form needs a concrete type. A parametric type conforms as a family ([§5.7](#57-families)).

No form computes a value from the type. A type whose data needs a computation (a lazily derived table, a foreign layout) does not conform by a field: the library converts it explicitly ([§5.11](#511-types-that-only-convert)).

**Status:** Implemented.

### 5.3 Forwarding with `by`

```julia
@implement ColTable Halves by right
```

- The implementation forwards every operation to the field `right`. The field's type is the receiver type, so `Halves` shares the code compiled for that type.
- The field's type must implement the operations itself. **Forwarding does not chain:** a field whose type itself forwards is refused.
- `by` is the only way to forward: `@implement X T` without it never picks a field ([§5.2](#52-one-line)).
- The forwarding field may not also be a writable declared field: a write through the trait would replace the receiver.
- A trait with `@concrete_only` refuses a forwarding field of an abstract type, naming the field.

**Status:** Implemented, except the check on a writable forwarding field (Planned; [T-4](#19-deviations)).

### 5.4 Field mappings

```julia
@implement Named Book name => title            # Named declares `@const name::String`
@implement Stepper Clock by data, t => time    # with forwarding
```

- A declared field may be stored under another name: `declared => stored`.
- Several mappings are separated by commas.
- A type with its own `getproperty` must map every declared field.

**Status:** Implemented.

### 5.5 Several traits at once

```julia
@implement (ColTable, RowTable) Grid by data
```

- One declaration, one implementation per trait, all forwarding to the same field (or all served by `Grid`'s own methods).
- Each trait may also be implemented in its own declaration, through its own field: `@implement ColTable Sep by cols` and `@implement RowTable Sep by rows`.

**Status:** Implemented.

### 5.6 Stating parameters

```julia
@implement ArrayLike{Float32, 1} MyVec
@implement ODEModel{Float64} Lorenz
```

- An implementation states the values of parameters that no field and no equation defines.
- A stated value takes the place of the equation's value for that implementation.

**Status:** Implemented.

### 5.7 Families

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
- It is checked for the family as a whole: the methods must cover the family, with results that infer to the declared types.
- **A member's implementation is fixed at its first use,** not at the family's declaration. The package that owns a member's parameter type (`MyT` in `S{MyT}`) may define an override for that member until then, and not after.
- Code is compiled per member.
- **Joint families:**
  - each member conforms at one value of each trait parameter, so the parameters stay associated types;
  - every variable of the trait's parameters must occur in the type;
  - the trait's parameters are written with variables, constants and type constructors, never function calls.
- A joint family may come with a block of methods, as a family of one type does.
- With `@concrete_only`, a member at an abstract parameter (`S{Any}`) is refused at the call.
- **Forwarding for a whole family,** `@implement X Series{T} by f where {T}`: as for one type, the field is named with `by`. The family of field types must be covered by one implementation's family. Until it is built, write one declaration per member: `@implement SVec LSeries{Float64} by data`, `@implement SVec LSeries{Float32} by data`.

**Status:** Implemented, except forwarding for a whole family (Planned; [open issues §2](../open-issues.md#2-design), "Keys and fields", item 4; [T-7](#19-deviations)), a joint family with a block ([T-5](#19-deviations)), and the check on parameter expressions ([T-6](#19-deviations)).

### 5.8 Generic implementations

```julia
@implement GTable R where {R: Indexable, eltype(R) == Vector{Float64}} begin
    gn(r) = length(r)
    gcol(r, i) = r[i]
end
```

- One implementation covers every type that conforms to other traits. `R: Indexable` reads "`R` conforms to `Indexable`".
- Constraints are `R: Trait`, `R <: Type`, or a condition on `R`.
- It applies to a trait with parameters as to one without.
- Code is still compiled per concrete key.
- A generic implementation makes types members only for a trait without declared fields. A trait with fields needs each type's own declaration, which maps them.
- **Forwarding carries through.** A type that forwards `Indexable` to a field forwards `GTable` to the same field. The key stays the field's type, so the library's code for it is shared.
- **Overlap:**
  - a more specific implementation beats a generic one (`@implement GTable Matrix{Float64} begin … end`);
  - a more specific implementation must declare the same parameter values as the generic one, so the choice never changes a type;
  - two overlapping generic implementations with neither more specific are refused;
  - an overlap the later package cannot see, as when a trait's owner adds a generic implementation in a later version, is reported where a call meets both.
- **Predicates** are to be patterns on the constraints' parameters, so that overlap is decidable at the declaration. The example above uses a computed condition, `eltype(R) == …`.

**Status:** Implemented: the form, for a trait without parameters, and "more specific beats generic". Planned: the other overlap rules ([T-9](#19-deviations)). For a trait with parameters, see [T-8](#19-deviations). Forwarding through a generic implementation is not covered by a test. Open: what a predicate may say ([open issues §2](../open-issues.md#2-design), "the design and the code disagree", item 2).

### 5.9 Dynamic operations

```julia
@implement ColTable Reversed dynamic by cols begin
    ncols(r) = length(r)
    col(r, i) = r[end - i + 1]
end
```

- The type gets operations of its own on its field, called through pointers, so the library's code for the field's type serves it.
- Its pointers belong to one session, so it does not work in a closed (`--trim`) build. Prefer `@implement X T begin … end`.

**Status:** Open: TraitWorld accepts this form; whether it stays is not decided ([open issues §2](../open-issues.md#2-design), "the design and the code disagree", item 3).

### 5.10 Checks at the declaration

All of these run at `@implement`, never at a call. A failure raises `ImplementError`.

- **Who:** the declaring package owns the trait or the type ([§12](#12-who-may-implement-pirates-strict-mode)).
- **Completeness:** every operation has a method or a default for the receiver type. Every declared field exists, with the declared type.
- **Results:** each method's result infers to the operation's declared type. The message names the operation, the signature, and both types:

  ```
  `col` at Tuple{Counts, Int64} returns `Vector{Int64}`, declared `Vector{Float64}`
  ```
- **Writable fields** follow [§3.3](#33-fields).
- **Parameters:** values that fields define match; values within their bounds ([§3.4](#34-parameters-and-associated-types)).
- **Concreteness,** for a trait that asks for it ([§3.7](#37-concreteness)).
- **Overrides belong to the implementation.** Which operations are served by defaults is fixed now. A later method of such an operation for the type is refused when it is defined, naming the fix: define the method before `@implement`, or in its block, and restart Julia. A package image that brings such an override is refused when it loads. So the order matters where plain Julia's does not: a supertype owner's method (`op(::AbstractSample)`) is part of an implementation declared after it, and refused for one declared before it.
- **Redeclaration.** Declaring an implementation again changes it, as Julia 1.13 redefines a struct.

Not everything is caught here: a conversion that fails at run time (a `Float64` buffer receiving dual numbers) is not proved by the check.

**Status:** Implemented, except redeclaration (Planned: today a second declaration in a session is refused, naming the reason; change the declaration and restart Julia). Error types: [T-10](#19-deviations). Messages: [T-11](#19-deviations).

### 5.11 Types that only convert

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

## 6. Bounded functions

```julia
colmean(t::ColTable, i::Int) = (c = col(t, i); sum(c) / length(c))
```

Bounded functions exist only inside trait modules ([§2](#2-trait-modules)).

**Status:** Implemented. Each subsection has its own status.

### 6.1 Bounds

- **A trait in an argument annotation is a bound.** `t::ColTable` accepts a value of any type that conforms to `ColTable`.
- **Several bounds on one argument:** `t::(ColTable, RowTable)`. The value must conform to each. A bundle trait is the same thing named.
- **A bound may fix parameters:** `s::StateVector{Float64}`. A value conforming at another value is refused at the call with `TraitBoundError`.
- **A bound may leave a parameter open** with a `where` variable: `f(m::ODEModel{T}, u0::Vector{Float64}) where {T}`. The body reads `T`. A variable shared between bounds, `f(a::ArrayLike{T}, b::ArrayLike{T}) where {T}`, requires equal values.
- Other arguments are ordinary: `i::Int`, `v::AbstractVector`, untyped. Ordinary `where` variables on ordinary arguments work as in Julia.

Until `where` variables in bounds are built, get an associated type in the body from an operation that returns it in a container: declare `emptycells(c::Column{T}, n::Int)::Vector{T}` and write `T = eltype(emptycells(c, 0))`.

**Status:** Implemented, except `where` variables in bounds (Planned; [open issues §3](../open-issues.md#3-traitworld-the-prototype), "Behind the notes", item 7; [T-16](#19-deviations)). Open: how `Vector{<:ColTable}` in an argument takes a user's vector ([open issues §2](../open-issues.md#2-design), item 11).

### 6.2 What a bounded function receives

- It receives a **trait object**: the user's own object, seen through the bound. Nothing is copied. A write through a declared field reaches the user's object.
- With several bounds, each trait sees the same user's object. A write through one is seen through the others.
- It is compiled per key ([§4](#4-keys-what-code-is-compiled-for)).
- A bounded function has two parts, which you never write separately. Its **entry** receives the caller's values and translates each by its bound, once. Its **worker** is the body, compiled per tuple of keys. How both are built: [`lowering.md`](lowering.md#8-bounded-functions-workers-and-entries).

**Status:** Implemented.

### 6.3 What trait code may do with a trait object

| In a trait module | Allowed |
|---|---|
| call the trait's operations on it; read its declared fields; write them unless `@const` | yes |
| pass it to another function with a bound it carries, or to an internal function without bounds | yes |
| use several trait objects in one function, of one trait or several | yes |
| capture it in a closure passed to Base (`sort!(p; lt = (i, j) -> …)`) | yes: the closure is checked like the function |
| keep it beyond the call as a `Dynamic{X}` ([§10](#10-dynamicx-values-of-any-conforming-type)) | yes |
| call any Julia code on ordinary values, such as the column `col` returns | yes |
| take arguments of abstract types from plain callers (`Any`, `Vector{Any}`) | yes: their uses dispatch when they run; concrete mode reports them ([§13](#13-concrete-mode)) |
| pass it where a different trait is expected | no: declare both bounds |
| pass it bare to an ordinary function (`sum(t)`), store it bare, return it bare, `typeof(t)`, a field no trait declares | no: code must not depend on the user's type |

A forbidden use is a `TraitUseError` ([§11](#11-checks-and-when-they-run)).

**Status:** Implemented.

### 6.4 Internal functions

- Functions without bounds may take trait objects from bounded functions in the same module. They are compiled together with the bounded function that calls them.
- Definition checking follows the trait object into them.
- Only bounded functions accept values from plain code as trait objects. A plain caller passing a value to an unbounded function passes the value itself, as in plain Julia.

**Status:** Implemented.

### 6.5 Dispatch: types first, then traits

```julia
describe(v::Vector{Float64}) = "a vector"
describe(m::AbstractMatrix) = "a matrix"
describe(t::ColTable) = "a table with $(ncols(t)) columns"
describe(x) = "something else"                 # the fallback
```

- **A trait bound ranks above `Any` and below every type,** concrete or abstract. `describe([1.0 2.0])` takes the `AbstractMatrix` method, although `Matrix{Float64}` is a `ColTable`. A value caught by a typed method is not translated. So a library adopts traits one function at a time.
- **Among bounds:** a subtrait beats its supertrait; more bounds beat fewer.
- **Unrelated bounds at one position need a joint method.** `f(t::ColTable)` and `f(t::RowTable)` need `f(t::(ColTable, RowTable))`. The trait module's end raises `TraitBoundError` otherwise. Only the function's own methods are involved, so no later load can create the ambiguity.
- A bounded method and a typed method that are ambiguous in another position are reported when defined.
- **The fallback:** a value that conforms to none of the bounds reaches the most specific ordinary method that applies, as in plain Julia. An untyped method of the same shape, defined after the bounded ones, serves as such a fallback. Without any, the call raises `MethodError`, with a hint naming the bound.
- Only the package that defines a function ([§12.1](#121-who-may-implement)) may add a bounded method to it where it has no entry of that shape.

**Status:** Implemented. The hint's text: [T-22](#19-deviations).

---

## 7. Results: declared types, `Like`, `withfields`

```julia
total(t::ColTable)::Float64 = sum(sum(col(t, i)) for i in 1:ncols(t))       # an ordinary result type
kscaled(t::KTable, a::Float64)::Like{t} = kwith(t, [a .* kcol(t, i) for i in 1:kncols(t)])
shifted(r::LRec{Vector{Float64}})::Like{r} = withfields(r; u = r.u .+ 1.0)
```

- An ordinary result annotation works as in Julia.
- **`::Like{t}`** declares that the result is like argument `t`, which must be a bounded argument. The body returns a value of the receiver type (from a constructor operation) or a `withfields` result. The caller gets a value of its own type:
  - a type that implements the operations: the new receiver value, which must be of the same type;
  - otherwise: the user's object rebuilt by its constructor, with the forwarded or mapped fields replaced, for immutable and mutable types alike. Other fields, such as labels, are kept.
- **A sibling:** the result may be the same family at another parameter, and the user's type is rebuilt there (`LSeries{Float64}` in, `LSeries{Float32}` out).
- **`withfields(t; name = value, …)`** replaces declared fields, for a trait with fields.
- `return x` inside a `Like` body works.
- Called with a `Dynamic`, a `Like` function returns a `Dynamic` of the same implementation.
- **Trait objects never go up bare.** A function that returns its trait object without `Like` raises `TraitUseError`.
- `verify_main` lists the rebuilding step of each implementation a program reaches ([§15](#15-compiling-ahead)).

**Status:** Implemented, except the listing for `verify_main` (Planned; [T-20](#19-deviations)).

---

## 8. Keywords, defaults and varargs

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
- **A vararg of trait objects,** `ts::ColTable...`, must be last. Its elements may have different keys; the code is compiled per tuple of keys.
- A vararg of `Callable` is refused. A vararg keyword (`kws...`) of a bounded function passes on unchanged.
- **A function passed down with keywords** names them in a fourth parameter: `Callable{A, S, M, K}`, with `K` a named-tuple type.

**Status:** Implemented, except `Callable` with keywords (Planned: today `Callable` takes three parameters).

---

## 9. `Callable`: functions at a declared signature

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
  - `DynamicCall` (the default when `M` is left out): the library's code is compiled once per signature, not per function. Each call is an indirect call to the function's code compiled for `A`. After a method of the function is redefined, a call computes what a plain call would compute at that point.
  - `CompiledCall`: the library's code is compiled per function, with the function inferred into it, at plain Julia's speed. The signature is still checked.
- **The library sets the default; the caller decides per value:** `compiled_call(f)`, `dynamic_call(f)`. `Callable{A, S, M}(f)` also fixes the signature. A bound without `M` accepts either mode.
- **Several signatures:** `f::(Callable{…}, Callable{…})`. A call picks the signature its arguments match; a call at an undeclared signature raises `MethodError`.
- **Functions from trait code** (Base's `abs2`, a trait module's own functions and closures) are called directly, whatever the mode.
- How a dynamic call is made: [`lowering.md`](lowering.md#12-callable-and-dynamicfn).

**Stored functions.**

```julia
struct FunctionCallback
    cond::DynamicFn{Tuple{Vector{Float64}, Float64}, Bool}
end
callback(f) = FunctionCallback(dynamic_fn(Tuple{Vector{Float64}, Float64}, Bool, f))   # in plain code
```

- `DynamicFn{A, S}` is a function in `DynamicCall` mode as a value of fixed type, for a library's model or callback types. `dynamic_fn(A, S, f)` makes one, in plain code.

**Rules.**
- **The argument types `A` are a constant type.** A bound whose `A` names a method's `where` variables (`f::Callable{RHSSig{P, T}, Nothing}`) is refused when the method is defined. Write one method per signature.
- **An open result type,** `f::Callable{Tuple{Float64}, S} where S`, is inferred at the call, in plain code. It becomes part of the key, and every call is checked against it.
- A dynamic call takes at most six arguments.
- **Functions returned to plain code** are ordinary closures of the trait module. A closure that captured a trait object keeps the user's object.
- **Bounded closures,** `(u::ColTable) -> …`, have an entry of their own, as a bounded function does.
- **A `Callable` whose result is a trait or a `Callable`** (`f::Callable{Tuple{Int}, ColTable}`) translates the function's results by that bound, as an argument's bound would.

**Status:** Implemented, except: open result types (Planned; [T-18](#19-deviations)); bounded closures and results that are traits or `Callable`s (Planned); the refusal of a non-constant `A` ([T-17](#19-deviations); [open issues §3](../open-issues.md#3-traitworld-the-prototype), "Found by the solvers agent", item 5).

---

## 10. `Dynamic{X}`: values of any conforming type

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
- **It holds the user's object.** It sees the user rebind a field, and writes through it reach the user's object. It keeps the user's object alive.
- **An operation on it** runs the method of the implementation it holds. The result is asserted to the declared type, so code after it stays typed. A fast path covers up to four implementations; how the call is dispatched: [`lowering.md`](lowering.md#13-dynamicx).
- **A parametric trait's `Dynamic` fixes the parameters** its operations' result types use, `Dynamic{StateVector{Float64}}`, so code after a call infers.
- **Opened at a bound:** passed to a function bounded by `X`, it selects the code compiled for its key once, and that code runs compiled. Put loops over its data in such a function. Two `Dynamic` arguments select the code for their pair of keys.
- A new implementation, declared later, works at once, and discards no compiled code.
- **Up and down.** A `Dynamic` is a value of its own type. It goes to plain code as one, bare or inside other values, and comes back admitted by its type.

**Making one.**
- Inside a trait module: `Dynamic{X}(t)` from a trait object, or by storing a trait object where a `Dynamic{X}` is declared (`push!(s.hooks, h)`).
- In plain code: `Dynamic{X}(x)` for any value that conforms to `X`.
- A trait object carrying another trait cannot become a `Dynamic{X}` (`ArgumentError`).

**The trait's name as a type.**
- **Inside a trait module,** a trait's name in a struct field, a container's element type, or a container in an argument means its `Dynamic`: `model::Model`, `Vector{Hook}`, `Column[]`, `cs::Vector{Column}`.
- A trait's name directly in an argument stays a bound.
- **Outside trait modules,** write `Dynamic{X}` out.

**Equality and printing.** Two `Dynamic{X}` are equal when they hold the same trait object (`===`): a mutable object by identity, an immutable one by value. `hash` agrees. It prints as `Dynamic{X} at` its key: `Dynamic{Shape} at Circle`.

**Assigning from plain code.** A field declared `Dynamic{X}` converts on assignment from any value that conforms to `X`, so `obj.field = value` works from plain code.

**Limit.** A result through an opened `Dynamic` is not inferred. Assert it: `asdcol(g)::Dynamic{DCol}`.

**Status:** Implemented, except:
- Planned: the conversion on assignment for every trait. Today it exists only from a trait object; define `Base.convert(::Type{Dynamic{X}}, x) = Dynamic{X}(x)` for your trait ([open issues §3](../open-issues.md#3-traitworld-the-prototype), "From the demonstrators", item 2).
- Planned: `Dynamic{(ColTable, RowTable)}`, a value seen through several traits; a trait's own declared `==`; serialization of a `Dynamic` with its implementation; a faster path beyond four implementations ([open issues §2](../open-issues.md#2-design)).
- Open: opening a `Dynamic` at the conforming value's own concrete type, a checked downcast ([open issues §2](../open-issues.md#2-design), item 16). Today, assert it in plain Julia: `m = integ.p::Lorenz{Float64}`.

---

## 11. Checks, and when they run

| When | What is checked | Error |
|---|---|---|
| `@trait` | the body's form: result types present, the receiver typed by the trait, no parameter defined twice | `ErrorException` |
| `@implement` | ownership, completeness, result types, fields, parameters, concreteness ([§5.10](#510-checks-at-the-declaration)) | `ImplementError` |
| a method definition after `@implement` | an override of an operation a default serves | `ImplementError` |
| a definition in a trait module | the module owns the method's function or a type in it | `OwnershipError` |
| the end of a trait module | every bounded function, once, for every type that will ever conform; ambiguous bounds | `TraitUseError`, `TraitBoundError` |
| a call, at the entry | the value conforms; fixed parameters; bounded keywords; concreteness of a family member | `MethodError` (with a hint), `TraitBoundError` |
| a call to a `Callable` | the arguments and the result | `TypeError`, `MethodError` |
| a worker's first call | what the end of the module cannot check: a parameter left open whose bound is not a trait, a `Callable`'s open result type | `TraitUseError` |

**Definition checking** at the end of a trait module infers each bounded function once at an *archetype*: a stand-in value whose operations and fields return values of their declared types and nothing more. A trait object has no methods but its traits' operations and fields, and every operation declares its result type. So one check covers every type that will ever conform. A mistake is reported at its line before any type conforms:

```julia
spread(t::ColTable) = size(t)    # `size` is not an operation of ColTable
leak(t::ColTable) = typeof(t)    # code must not depend on the user's type
```

- While a package is precompiled, the report is an error, and the build fails.
- For a trait module defined at the prompt or in a script, it is a warning. The call then raises the `TraitUseError`.
- `check_definitions(M)` runs the check on demand: it returns an empty list, or raises `TraitUseError` listing the problems.
- Keyword, vararg and `Callable` functions with declared result types are checked at the module's end like any other.

**Status:** Implemented, except that keyword, vararg and every `Callable` function are checked at their first call ([T-19](#19-deviations)).

---

## 12. Who may implement; pirates; strict mode

### 12.1 Who may implement

- A package *owns* the functions and types it defines. Julia (Core, Base, the standard libraries) is one owner. A package extension counts as its parent package. Code at the prompt is owned by the session.
- An implementation is a method, so ordinary ownership decides who may write it: **the trait's owner or the type's owner.** A third package may not.
- An implementation for a foreign trait and a foreign type belongs in the trait owner's package extension.
- Operations that are existing functions (`Base.size`) may be implemented only for types the declaring package owns. Otherwise declare the existing methods: `@implement Sized Vector{Float32}` without a block, by Base's own methods.

**Status:** Implemented.

### 12.2 Pirates

- A **pirate** is a method of a function you do not own, for types you do not own: Julia's "type piracy".
- **A trait module may not define one:** `OwnershipError` at the definition. A `Union` with one of your own types is no way around it, nor a lower-bounded type variable.
- In plain code, a pirate is followed by default, as in plain Julia. Trait code it changes is compiled again once ([`facts.md`](facts.md#pirates)).
- Methods for your own types are never pirates: `Base.show(io::IO, x::MyType)` is fine everywhere.

**Status:** Implemented. Open: whether the refusal in trait modules stays, or only pirates that win are refused, under strict mode ([open issues §1.20](../open-issues.md#1-decisions-waiting-for-the-user)).

### 12.3 Strict mode

```julia
TraitWorld.strict!(true)        # or start Julia with JULIA_TW_STRICT=1
```

- Strict mode refuses a pirate when it would win at a call that compiled trait code makes. The error, `TraitWorld.PirateError`, names the method and the trait code it would change. The method then does not exist, for plain code either.
- Nothing else is refused: a pirate that wins nowhere in trait code is accepted.
- A definition by a stakeholder is followed. A *stakeholder* of a method is the owner of its function or of a type in its signature. Define as the owner with `@eval Owner f(…) = …`.
- `TraitWorld.delegate!(Core => Impl)` lets an implementation package count as the owner of the core package it implements (for split packages such as StaticArraysCore and StaticArrays).
- A pirate loaded before the code it changes, or brought by a package extension, is refused too.
- `verify_main` lists the calls reached from trait code that select a pirate.

**Status:** Implemented as a prototype: refusal when the pirate is defined, or when an image that brings it loads, after the trait code. Planned: refusal of pirates loaded before the code they change and of those in package extensions, and the listing in `verify_main` ([open issues §1.10](../open-issues.md#1-decisions-waiting-for-the-user)). The error's text: [T-21](#19-deviations).

### 12.4 No sealing

- Abstract types and functions are not sealed. Anyone may add a subtype or a method, as in Julia today.
- A closed contract is a trait: its operations, their declared result types, and the check at every implementation.

**Status:** Implemented.

---

## 13. Concrete mode

```julia
@error_on_abstract @trait_module module Hot … end       # every function of the module
@warn_on_abstract cold(t::ColTable, k::Vector{Any}) = …  # one function, inside a trait module
fully_typed(Columns.colmean, (Vector{Vector{Float64}}, Int))   # a report, anywhere
```

- Code is **fully typed** when every call in it, and in what it calls, has known argument types. Such code pays nothing for the trait modules' compiler mode.
- `fully_typed(f, argtypes)` reports the calls that are not, with their root cause through any number of layers ("field `scale` of `Config` is declared `Real`"). `isfullytyped(report)` answers yes or no. Operations on `Dynamic` values count as declared, not as faults.
- `@warn_on_abstract` warns at a worker's first run; `@error_on_abstract` raises `AbstractTypeError` (an abstract value used) or `NotFullyTypedError` (a call with unknown types).

**Status:** Implemented, with today's spellings; one declaration with a level is Planned ([§3.7](#37-concreteness)). Open: whether a variable of a small `Union` should warn ([open issues §1.18](../open-issues.md#1-decisions-waiting-for-the-user)). Today it does not: its splits have known types.

---

## 14. Printing

- A trait object's type prints by bound and key: `ColTable at Vector{Vector{Float64}}`, `PVec{Float64} at Vector{Float64}`. The user's other fields never appear.
- A function bound prints as `Callable{Tuple{Float64}, Float64} at DynamicCall`, or at the function's type in `CompiledCall` mode.
- A `Dynamic` prints as its trait and key: `Dynamic{Shape} at Circle`.
- Stack traces hide TraitWorld's own frames. `JULIA_TW_ALL_FRAMES=1` shows them.

**Status:** Implemented. It needs the patched Julia's type printers ([`compiler.md`](compiler.md#53-type-printers)).

---

## 15. Compiling ahead

No syntax: it follows from `@implement` in a package.

- While a package that declares `@implement X T` is precompiled, the trait code that `T` needs is compiled into that package's image. This covers every bounded function whose bound includes `X`, at `T`'s key, where the other arguments are concrete.
- The checks a first call would run are run then, and the image keeps their results. A failing check fails the build.
- A caller that does not know the argument's type reaches the code for any declared implementation without compiling anything per type.
- What exactly is compiled, and how untyped callers find it: [`lowering.md`](lowering.md#151-compiling-ahead-from-declarations).
- `TraitWorld.@workload begin … end` is a precompile workload for a trait module (PrecompileTools' `@compile_workload`, reached through TraitWorld).
- `JULIA_TW_AHEAD=0` turns compiling ahead off.

**Closed programs.** `verify_main(main, (Vector{String},); entrypoints = true)` lists every target a program can reach through trait code, for `juliac --trim`:
- a function passed as a `Callable` adds one target at its declared signature;
- a `Dynamic` value adds the implementations whose types reach the place it is made;
- each set of supplied keywords is a signature;
- a closure returned from trait code has a type of the trait module, so calls to it from plain code are calls into trait code, listed too.

Plain code reached from trait code keeps plain Julia's properties, and its open dynamic calls are reported. A `--trim` build compiles plain code: nothing loads in a binary, so nothing needs protecting ([`facts.md`](facts.md#closed-builds)).

**Status:** Implemented. The rebuilding step of `Like{t}` is not listed yet ([T-20](#19-deviations)).

---

## 16. Membership

- `conforms(T, X)` answers whether type `T` conforms to trait `X`. With fixed parameters, `conforms(Vector{Int}, PVec{Float64})` is `false`. `conforms(Dynamic{X}, X)` is `true`.
- `x isa X` and `T <: X` answer the same, when traits are in Julia's type system. An implementation then adds a supertype after the type is defined. That is sound because only a stakeholder declares it.
- Numbers need no trait. `Number`, `Real` and `Integer` stay as they are.

**Status:** `conforms` is Implemented. `x isa X` and `T <: X` are Planned: until then `x isa ColTable` is `false` for every `x`.

---

## 17. Named implementations

- A second implementation of a trait for a type, used only where a caller names it.
- The preferred form is a wrapper value that conforms, a newtype: `Via{Fast}(x)`.
- Until then, a foreign trait for a foreign type needs the trait's owner, the type's owner, or your own wrapper type: `struct FastM; m::M; end` with its own implementation.

**Status:** Planned, deferred until traits are in the type system.

---

## 18. Status index

| Construct | Status | Section |
|---|---|---|
| `@trait_module`, the module and block forms | Implemented | [§2](#2-trait-modules) |
| `@trait`: operations, result types, `Self` | Implemented | [§3.1](#31-operations), [§3.5](#35-self) |
| defaults | Implemented | [§3.2](#32-defaults) |
| a trait's parameter in a default's body | Planned | [§3.2](#32-defaults), T-2 |
| declared fields, `@const` | Implemented | [§3.3](#33-fields) |
| parameters by field, by equation, stated | Implemented | [§3.4](#34-parameters-and-associated-types) |
| bounds on parameters, checked | Planned | [§3.4](#34-parameters-and-associated-types), T-1 |
| supertraits, bundles | Implemented | [§3.6](#36-supertraits-and-bundles) |
| supertrait agreement check | Planned | [§3.6](#36-supertraits-and-bundles), T-3 |
| `@concrete_only`, `@warn_on_abstract`, `@error_on_abstract` | Implemented | [§3.7](#37-concreteness) |
| one concreteness declaration with a level | Planned; spelling Open | [open issues §1.15](../open-issues.md#1-decisions-waiting-for-the-user) |
| keys | Implemented | [§4](#4-keys-what-code-is-compiled-for) |
| `@implement X T begin … end` | Implemented | [§5.1](#51-with-a-block-of-methods) |
| `@implement X T` (one line) | Implemented | [§5.2](#52-one-line) |
| `by f` | Implemented | [§5.3](#53-forwarding-with-by) |
| the forwarding field not a writable declared field | Planned | [§5.3](#53-forwarding-with-by), T-4 |
| field mappings `name => stored` | Implemented | [§5.4](#54-field-mappings) |
| several traits at once | Implemented | [§5.5](#55-several-traits-at-once) |
| stated parameters `X{P…} T` | Implemented | [§5.6](#56-stating-parameters) |
| families, joint families | Implemented | [§5.7](#57-families), T-5, T-6 |
| forwarding for a whole family | Planned | [§5.7](#57-families), T-7 |
| generic implementations | Implemented | [§5.8](#58-generic-implementations), T-8 |
| overlap rules for generic implementations | Planned | [§5.8](#58-generic-implementations), T-9 |
| what a generic predicate may say | Open | [open issues §2](../open-issues.md#2-design) |
| `dynamic by f` | Open | [open issues §2](../open-issues.md#2-design) |
| overrides fixed at the declaration; family members at first use | Implemented | [§5.10](#510-checks-at-the-declaration) |
| redeclaring an implementation | Planned (today: restart) | [§5.10](#510-checks-at-the-declaration) |
| types that only convert | Implemented (a pattern) | [§5.11](#511-types-that-only-convert) |
| bounds on arguments, several bounds, fixed parameters | Implemented | [§6.1](#61-bounds) |
| `where` variables in bounds, shared or not | Planned | [§6.1](#61-bounds), T-16 |
| `Vector{<:X}` arguments | Open | [open issues §2](../open-issues.md#2-design) |
| internal functions without bounds | Implemented | [§6.4](#64-internal-functions) |
| types first, then traits; joint-method rule; fallback | Implemented | [§6.5](#65-dispatch-types-first-then-traits) |
| result types, `Like{t}`, `withfields`, siblings | Implemented | [§7](#7-results-declared-types-like-withfields) |
| keywords, defaults, varargs | Implemented | [§8](#8-keywords-defaults-and-varargs) |
| `Callable{A, S, M}`, both modes, caller override | Implemented | [§9](#9-callable-functions-at-a-declared-signature) |
| `DynamicFn`, `dynamic_fn` | Implemented | [§9](#9-callable-functions-at-a-declared-signature) |
| `Callable{A, S, M, K}` with keywords | Planned | [§8](#8-keywords-defaults-and-varargs) |
| a constant `A`, refused otherwise | Planned | [§9](#9-callable-functions-at-a-declared-signature), T-17 |
| open `Callable` result types | Planned | [§9](#9-callable-functions-at-a-declared-signature), T-18 |
| bounded closures; `Callable` results that are traits | Planned | [§9](#9-callable-functions-at-a-declared-signature) |
| `Dynamic{X}`, the trait name as `Dynamic` inside trait modules | Implemented | [§10](#10-dynamicx-values-of-any-conforming-type) |
| `convert` to `Dynamic{X}` for every trait | Planned | [§10](#10-dynamicx-values-of-any-conforming-type) |
| `Dynamic{(X, Y)}`, a trait's `==`, serialization | Planned | [§10](#10-dynamicx-values-of-any-conforming-type) |
| opening a `Dynamic` at its concrete type | Open | [open issues §2](../open-issues.md#2-design) |
| definition checking | Implemented | [§11](#11-checks-and-when-they-run), T-19 |
| who may implement | Implemented | [§12.1](#121-who-may-implement) |
| no pirates in trait modules | Implemented; whether it stays is Open | [open issues §1.20](../open-issues.md#1-decisions-waiting-for-the-user) |
| strict mode | Implemented as a prototype; the rest Planned | [§12.3](#123-strict-mode) |
| no sealing | Implemented | [§12.4](#124-no-sealing) |
| concrete mode, `fully_typed` | Implemented | [§13](#13-concrete-mode) |
| warning on small unions | Open | [open issues §1.18](../open-issues.md#1-decisions-waiting-for-the-user) |
| printing by bound and key | Implemented | [§14](#14-printing) |
| compiling ahead from `@implement` | Implemented | [§15](#15-compiling-ahead) |
| `verify_main`, `@workload` | Implemented | [§15](#15-compiling-ahead), T-20 |
| `conforms(T, X)` | Implemented | [§16](#16-membership) |
| `x isa X`, `T <: X` | Planned | [§16](#16-membership) |
| named implementations, `Via{Fast}(x)` | Planned (deferred) | [§17](#17-named-implementations) |

---

## 19. Deviations

Where TraitWorld differs from this reference. File paths are in the repository; line numbers are those of TraitWorld at 227781a. Checks named "reference.jl" are in [`experiments/docs-examples/reference.jl`](../../experiments/docs-examples/reference.jl).

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| T-1 | [§3.4](#34-parameters-and-associated-types) | A parameter's bound (`T <: Real`) is checked at every implementation; a trait bound serves definition checking. | The bound is recorded and read by nothing. `@implement ArrayLike{String, 1} StrVec` is accepted for `T <: Real`. | `TraitWorld/src/trait.jl:206` (`param_bound`); reference.jl, "T-1" |
| T-2 | [§3.2](#32-defaults) | The trait's parameters are in scope in a default's body. | `UndefVarError: T` when the default runs. | reference.jl, "T-2" |
| T-3 | [§3.6](#36-supertraits-and-bundles) | A type's implementation of a subtrait agrees with its implementation of the supertrait. | Not checked: only that the receiver implements each supertrait. | `TraitWorld/src/implement.jl:526` (`_check_projection_now`) |
| T-4 | [§5.3](#53-forwarding-with-by) | The forwarding field may not also be a writable declared field. | Not checked. | `TraitWorld/src/implement.jl:526`, `:562` (`_field_problems`) |
| T-5 | [§5.7](#57-families) | A joint family takes a block of methods: `@implement StateVector{T} Series{T} where {T} begin … end`. | Not lowered as a family: `Series{T} where {T}` is taken as one type, so the members get no implementation. Only the earlier spelling (T-12) handles this. Found by reading the code. | `TraitWorld/src/implement.jl:896`, `:900` |
| T-6 | [§5.7](#57-families) | A joint family's trait parameters are variables, constants and type constructors, never function calls. | Any expression is accepted and evaluated per member. | `TraitWorld/src/implement.jl:1008` (`_param_methods`) |
| T-7 | [§5.7](#57-families) | Forwarding for a whole family is planned as `@implement X Series{T} by f where {T}`. | Refused with "expected `project(t) = …` or a begin … end block after the type", which names a form the design does not have. Found by reading the code. | `TraitWorld/src/implement.jl:909`, `:1280` |
| T-8 | [§5.8](#58-generic-implementations) | A generic implementation applies to a trait with parameters as to one without. | For a trait with parameters, the form is taken as a family, and the constraints (`R: Indexable`) are read as `where` bounds. Found by reading the code. | `TraitWorld/src/implement.jl:1063` |
| T-9 | [§5.8](#58-generic-implementations) | Overlapping generic implementations are refused; a more specific one declares the same parameter values. | No overlap check. | `TraitWorld/src/implement.jl:1109` |
| T-10 | [§5.10](#510-checks-at-the-declaration) | Every failure at `@implement` raises `ImplementError`. | An operation without a method or a default in a block raises an `ErrorException`. Syntax errors in `@implement` are `ErrorException`s too. | `TraitWorld/src/implement.jl:841` |
| T-11 | [§5](#5-implementations) | Messages use the reference's terms: receiver type, implementation, forwarding. | Several messages still say "representation" or "projection", or suggest the earlier spelling: "owns neither the trait nor the representation", "the projection of T returns …", "cannot infer a concrete representation … `@implement Trait{R} T …`", "takes … the representation, last", "a projection needs exactly one `project(t) = …`", `TraitArgumentError`'s "at representation". | `TraitWorld/src/implement.jl:501`, `:611`, `:618`, `:968`, `:1034`, `:1250`, `:1280`, `:1286`, `:1334`; `src/trait.jl:49`, `:80`; `src/core.jl:652` |
| T-12 | [§1](#1-syntax-summary) | The grammar has one spelling of traits and implementations. | The earlier spelling, with the receiver type as the trait's last parameter, is still accepted: `@trait ColTable{R}`, `ncols(r::R)::Int`, `@implement ColTable{MyType} begin … end`, `@implement X{R} where {…}`. Tests and the precompile workload still use it. | `TraitWorld/src/trait.jl:111`; `src/implement.jl:873`, `:963`; [open issues §3](../open-issues.md#3-traitworld-the-prototype), "Dependent code", item 13 |
| T-13 | [§3.1](#31-operations) | No annotation marks a mutating operation. | `@mutating` in a `@trait` body is accepted and recorded; nothing reads it. | `TraitWorld/src/trait.jl:35`, `:284`; `src/implement.jl:132` (`_mutating`, never called) |
| T-14 | [§5.3](#53-forwarding-with-by) | `by f` takes no block. | `@implement X T by f begin … end` is accepted: the block's methods become the implementation for the field's type. | `TraitWorld/src/implement.jl:912`, `:1347` |
| T-15 | [§5.2](#52-one-line) | No form computes a value from the type. | The internal form `@implement X T project(t) = …` is accepted: a body that reads a field as is forwards to it; any other body is refused with "computes a value". The flags `copies` and `unproject(t, r) = …` are refused with messages about retired features. | `TraitWorld/src/implement.jl:1280`–`1305`; reference.jl, "T-15" |
| T-16 | [§6.1](#61-bounds) | A bound may name a method's `where` variable (`m::ODEModel{T}`, `a::KVec{T}, b::KVec{T}`), read in the body. | The annotation is read as a plain type, and the method never applies (`MethodError`). | `TraitWorld/src/trait_module.jl:290`–`297` (`_classify`); reference.jl, "T-16" |
| T-17 | [§9](#9-callable-functions-at-a-declared-signature) | A `Callable` bound whose argument types name a `where` variable is refused when the method is defined. | It is silently a plain argument; the method never applies to a function. | `TraitWorld/src/trait_module.jl:249` (`_callable_params`), `:290` |
| T-18 | [§9](#9-callable-functions-at-a-declared-signature) | An open result type, `Callable{Tuple{Float64}, S} where S`, is a bound. | It is a plain argument; the call is a `MethodError`. | `TraitWorld/src/trait_module.jl:249`, `:290`; reference.jl, "T-18" |
| T-19 | [§11](#11-checks-and-when-they-run) | Definition checking at the module's end covers keyword, vararg and `Callable` functions; a first call checks only open parameters and open `Callable` results. | Keyword, vararg and every `Callable` function are checked at their first call. | `TraitWorld/src/defcheck.jl:85`–`92` (`archetype_sig`) |
| T-20 | [§7](#7-results-declared-types-like-withfields), [§15](#15-compiling-ahead) | `verify_main` lists the rebuilding step of `Like{t}` results. | It reports them as holes (`:inverse`). | `TraitWorld/src/verify.jl:746`, `:813` |
| T-21 | [§12.3](#123-strict-mode) | `PirateError` names the trait code the pirate would change. | It names the call signature (`Tuple{typeof(abs2), Float64}`); the trait-module function only when a walk up the callers finds it, which the tutorial's example does not. | `TraitWorld/src/strict.jl:74`, `:48` (`_trait_root`); [tutorial §18](../intro/traits-by-example.md) |
| T-22 | [§6.5](#65-dispatch-types-first-then-traits) | A value that conforms to no bound raises `MethodError` with a hint naming the bound. | The hint says "a Int64". Julia also prints "This error has been manually thrown", since the entry exists and throws. | `TraitWorld/src/frames.jl:75`; `src/entry.jl:499` |
