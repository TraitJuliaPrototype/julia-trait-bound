# Traits: the reference

This page defines the trait language: what a trait is, how a type joins one, how methods at traits dispatch and are compiled, what is checked, and which errors a user sees. Each section ends with a status line (Implemented, Planned, Optional, Open), as [the README](README.md#conventions-for-every-reference) defines them. The [Deviations](#19-deviations) table lists where the implementation falls short of this page.

- What compiled code may assume: [`facts.md`](facts.md).
- The Julia interfaces the language rests on: [`compiler.md`](compiler.md).
- What the library's macros expand to: [`lowering.md`](lowering.md).
- Terms are defined where they first matter; the [glossary](../glossary.md) links here.

## Contents

1. [Overview](#1-overview)
2. [Syntax summary](#2-syntax-summary)
3. [Traits are abstract types](#3-traits-are-abstract-types)
4. [Declaring a trait](#4-declaring-a-trait)
5. [Joining a trait](#5-joining-a-trait)
6. [Methods at traits](#6-methods-at-traits)
7. [Compiling: the box and the wrapper](#7-compiling-the-box-and-the-wrapper)
8. [Storage](#8-storage)
9. [Functions: `Callable`](#9-functions-callable)
   - [9b. Streams: `IO`](#9b-streams-io)
10. [Collections](#10-collections)
11. [Checks and errors](#11-checks-and-errors)
12. [Ownership, pirates, strict mode](#12-ownership-pirates-strict-mode)
13. [Scopes: trait modules](#13-scopes-trait-modules)
14. [Concreteness and fully typed mode](#14-concreteness-and-fully-typed-mode)
15. [Printing](#15-printing)
16. [Compiling ahead, closed programs](#16-compiling-ahead-closed-programs)
17. [Named implementations](#17-named-implementations)
18. [Status index](#18-status-index)
19. [Deviations](#19-deviations)

---

## 1. Overview

A **trait** is an abstract type with two additions:
- **Open membership.** A type may become a member after its own definition, by a declaration: `@implement X S`.
- **A contract.** The trait declares operations with argument and result types, stored fields, and the values of its parameters. Each membership is checked against it.

Everything else is Julia's. A trait is written wherever a type is written. It is parametrized as an abstract type is. A member's value is a value of the trait. Dispatch is Julia's, with one rule for ties between a type's own supertypes and a trait.

On top of that, a choice of speed, never of results:
- **Two kept forms of a member,** both members of the trait (§7.4): the box `Dynamic{X}(x)`, whose code is compiled once per trait instance, and the wrapper `compiled_for(x)`, whose code is compiled for `x`'s type. The choice is in the value's type, so it travels with the value. A trait that declares `@default_dynamic` boxes a plain member at its methods (§7.8).

```julia
@trait Shape begin
    area(s::Shape)::Float64
    perimeter(s::Shape)::Float64
    describe(s::Shape)::String = "a shape of area $(area(s))"    # a default
end

struct Circle; r::Float64; end
area(c::Circle) = π * c.r^2
perimeter(c::Circle) = 2π * c.r
@implement Shape Circle                    # Circle joins Shape: checked here

Circle(1.0) isa Shape                      # true
total(shapes::AbstractVector{<:Shape}) = sum(area, shapes; init = 0.0)
total([Circle(1.0), Circle(2.0)])          # 15.707963267948966
describe(Circle(1.0))                      # "a shape of area 3.141592653589793"
```

---

## 2. Syntax summary

The library's forms, in EBNF. `X?` is optional, `X*` repeats, `|` separates alternatives, quoted text is literal. `Name`, `Type` and `Expr` are Julia's. Everything not listed here (methods, types, structs, fields, `where`, `<:`, `Union`, `All`) is Julia's syntax with Julia's meaning.

```ebnf
Trait          ::= "@trait" Name Params? ( "<:" Supers )? ( "begin" TraitItem* "end" )?
Params         ::= "{" Param ( "," Param )* "}"
Param          ::= Name ( "<:" Type )?
Supers         ::= Type | "(" Type ( "," Type )* ")"
TraitItem      ::= Operation | Operation "=" Expr                    (* an operation; a default *)
                 | "@const"? Name "::" Type                          (* a declared field *)
                 | Name "=" Expr                                     (* an equation: a parameter as a function of Self *)
                 | "@input" Name+                                    (* input parameters *)
                 | Concrete
                 | "@default_dynamic"                                (* the trait erases by default *)
Operation      ::= FName "(" OpArg ( "," OpArg )* ")" "::" Type ( "where" TypeVars )?
FName          ::= Name | Module "." Name
OpArg          ::= Name "::" Type | "::" Type | Name                 (* one argument typed by the trait or Self: the receiver *)

Implementation ::= "@implement" Traits Member How?
Traits         ::= Type | "(" Type ( "," Type )* ")"
Member         ::= Type | Type "where" "{" TypeVar ( "," TypeVar )* "}"
How            ::= "begin" MethodDef* "end" | "by" FieldName

Scope          ::= "@trait_module" Option*                           (* before the module's first method *)
Option         ::= "facts" | "bounded" | "no_pirates" | "owner_only" | Name "=" Expr
Concrete       ::= ( "@enforce_concrete_only" | "@warn_on_abstract" ) Name*
FullyTyped     ::= "@enforce_fully_typed" | "@warn_not_fully_typed"
```

The kept forms are values, made by ordinary calls: `Dynamic{X}(x)` and `compiled_for(x)` (§7.4). They have no syntax of their own.

**Status:** Implemented.

---

## 3. Traits are abstract types

### 3.1 Membership

- `S <: X` holds when `S` is a member of the trait `X`, and `s isa X` when `s`'s type is.
- A type becomes a member:
  - **with its definition:** `struct S <: X … end`, declared and checked by an `@implement X S` after its methods (§5.2);
  - **after its definition:** `@implement X S` (§5.3 to §5.9), by a stakeholder (§12.1);
  - **through another membership:** membership is transitive. `S <: B` and `B <: A` give `S <: A`, whether each link is a declared supertype, a membership, or a trait's membership in another trait.
- **A membership has worlds, as a method has.** It holds from the world in which it is declared. A task running in an older world does not see it. It may be redeclared (§5.11) and taken back (§5.13), as a method may be redefined and deleted. Every function is a member of every `Callable` (§9).
- **What may be a member:** a concrete type; a family of types (`S{P} where P`); a closed abstract type (`AbstractVector{T}`); another trait. A trait is never a member of a closed abstract type. A trait's declared supertype is `Any` or a trait.
- **A type value** is a member only by its own membership: `@implement CellParser Type{Int64}` makes `Int64 isa CellParser` true. `S <: X` and `S isa X` are different questions, as in Julia.
- **Never members:** Core's kinds (`DataType`, `UnionAll`, `Union`, `TypeVar`, `Module`), the builtins' types, opaque closures, the memory types.

**Status:** Implemented ([compiler §4](compiler.md#4-sets-and-memberships), with its deviations); a membership taken back: Implemented, but for [lowering L-64](lowering.md#15-deviations) (§5.13).

### 3.2 Parameters

```julia
@trait KVec{T} begin
    T = eltype(Self)                       # defined by an equation of Self
    klen(v::KVec)::Int
    kget(v::KVec{T}, i::Int)::T
end
@trait Integrator{U, P} begin              # defined by the fields' types
    u::U
    @const p::P
end
@trait ArrayLike{T, N} begin               # stated by each membership
    alen(a::ArrayLike)::Int
end
```

- **A trait's parameters are associated types.** A member has exactly one value for each, as a Julia type has one `AbstractArray` supertype.
- A parameter is defined in one of three ways:
  - **by a field:** the field's declared type is matched against the stored field's type, as a `where` clause matches. `data::Vector{T}` against a `Vector{Float64}` field gives `T = Float64`;
  - **by an equation of `Self`:** `T = eltype(Self)`. An equation always holds; a stated value is checked against it;
  - **stated at the membership:** `@implement ArrayLike{Float32, 1} MyVec`, or `struct MyVec <: ArrayLike{Float32, 1}`.
- **Parameters are invariant,** as Julia's are. `KVec{Real}` is the trait at exactly `Real`. `KVec{<:Real}` takes every member whose parameter is a subtype of `Real`, and `KVec{>:Int}` every member whose parameter is a supertype of `Int`.
- **The bare name is the union over all parameters:** `KVec` is `KVec{T} where T`, as `AbstractVector` is `AbstractVector{T} where T`.
- **One instance per member.** A type may reach a trait by several paths (its own membership, a supertype's, a supertrait's). Every path must give the same parameter values. A declaration that would give a second instance is refused (`ImplementError`).
- **Bounds on parameters:** `@trait ArrayLike{T <: Real, N}`, also a trait as the bound. A value outside the bound is refused at the membership.
- **Input parameters:** `@input N` in the body marks `N` as an input. A type may be a member at several values of an input (`HasProperty{:ps, PView}` and `HasProperty{:u, Vector{Float64}}`). The trait at fixed input values is a trait of its own for every other rule. Two such traits are not disjoint: a type may be a member of both, and two methods at different values of an input are ambiguous for it (§6.3). A method's `where` variable or a stated value fixes an input; it is never left open where an operation's result needs it.
- **Not offered:** equations between type functions; a parameter bound that names its own trait.
- **Two traits linked by their parameters** are linked by a method's shared `where` variables, as in Julia: `solve!(integ::Integrator{U, T, P}, prob::ODEProblemTrait{U, T, P}) where {U, T, P}`.

**Status:** Implemented, but for T-105 (gate `n10_inputs`).

### 3.3 Where a trait stands

A trait is written wherever a type is written:
- in any method's signature, in any module: `f(t::ColTable)`, `f(v::AbstractVector{<:Shape})`, `f(x::T) where {T <: Shape}`;
- as a field's type, a type parameter, an element type: `model::Model`, `Vector{Shape}`, `Dict{String, Shape}`, `Ref{Shape}`, `Union{Nothing, Shape}`;
- as a struct parameter's bound: `struct Problem{F <: Model}`;
- in `isa`, `<:`, `typeassert`, `convert(X, x)`, `Type{<:X}`;
- as a declared supertype: `struct S <: X`, `abstract type A <: X`.

**Status:** Implemented.

### 3.4 Open and closed

- **A trait is open:** members may join after their definition.
- **An abstract type is closed:** `abstract type A end` has members only through `struct S <: A`. Base's and Core's abstract types are closed, but `Callable` (§9), which is a trait.
- A closed abstract type may be a member of a trait (`@implement Indexable{T} AbstractVector{T} where {T}`); then every subtype of it is a member.
- **A closed abstract type may declare a contract:** its operations and the split's candidates, named once, in the image that defines the type. Its members stay Julia's and no check reaches them, so the contract promises no result: an operation's result is `Any`, Julia's own answer at such a receiver. At a value typed by it, an operation's call branches over the candidates (§7.9) and returns what the member's method returns. Otherwise Julia's rules apply: code typed by it is compiled per type. Base's `IO` declares one (§9b).
- **Compiled code may rely on a non-membership.** Only the trait's owner or the type's may declare a membership without piracy (§12.1), so "`S` is not a `Shape`" is theirs to change. `isa` and `<:` fold, and a call selects its method without a guard. The code records what it relied on: the pair for a fold, its dispatch edge for a call.
  - A membership of that pair declared later invalidates the code that relied on its absence, as a method definition invalidates its callers: by an owner (a package extension that loads late, a declaration at the prompt, Revise), or by a pirate (§12.2).
  - A new type that joins invalidates nothing: no earlier code asked about it.
  - A membership that holds is relied on through its entry, from the entry's world ([facts §10](facts.md#10-memberships)).
- For a closed type, Julia's rules apply; its contract's operations only branch (above).

**Status:** Implemented, but for [compiler C-88](compiler.md#deviations) (gates `n18_closed_after_load`, `n7_guards`, `n16_declared_result`, `n25_image_before_set_method`).

### 3.5 Values

- **A member's value is a value of the trait.** Passing it to `f(t::X)` passes it. In the body, `t` is the caller's object: `typeof(t)` is its own type, and `t === x` holds for the `x` passed.
- **Where `X` erases by default** (`@default_dynamic`, §7.8), the method's argument is a kept form (§7.4): the box its forwarder made from a plain member, or the box or wrapper the caller passed. `typeof(t)`, `t === x` and `t isa Circle` answer for the kept form, not for the object. `unwrap(t)` is the object.
- A field or container typed by a trait holds its members' values, a kept form among them, each by its own type, as one typed by an abstract type does (§8).

| | A closed abstract type | A trait |
|---|---|---|
| How a type joins | in its own definition, `struct S <: A` | in its definition, or later by `@implement X S` |
| Who may make it join | the type's author | a stakeholder: the type's owner or the trait's |
| How many | one supertype, so one chain | any number of traits |
| What joining promises | nothing that is checked | the trait's contract, checked |
| Parameters | invariant; fixed by the subtype's definition | invariant; one value per member, by field, equation or statement |
| Dispatch | by subtyping | by subtyping, with a type's own supertypes before a trait (§6.2) |
| What code is compiled for | the argument's type | the argument's type: a member's own, a box's once per trait instance, a wrapper's per type of its object (§7.1) |

**Status:** Implemented, but for T-125.

### 3.6 Intersections

```julia
f(t::All{ColTable, RowTable}) = …                  # a member of both
const Table = All{ColTable, RowTable}              # a bundle: a name for the intersection
Dynamic{All{Shape, Placed}}(x)                     # boxed at both traits
```

- `All{X, Y, Z, …}` is the type of the values that are members of each, for any number of components. `S <: All{X, Y}` holds when `S <: X` and `S <: Y`.
- It is a subtype of whatever one of its components is a subtype of, and more specific than each component. An intersection with a closed component ranks as a closed type against an open set (§6.2).
- Components are flattened, sorted and deduplicated. A component that is a subtype of another by declared supertypes absorbs it; a membership never does, so an intersection's form does not depend on the world. Two closed types with no common subtype give `Union{}`.
- At an argument typed by an intersection, an operation's split takes the first component's members that are members of every component (§7.9).
- A bundle is a `const` alias of an intersection. Its members are every type that is a member of all of its components, whoever declared them.
- `@implement (X, Y) S` declares both memberships (§5.6).
- **The name comes from the library:** TraitWorld exports `All`, which is `Core.All`; `Core` does not export it. A module that also uses DataAPI's `All` (DataFrames' column selector) qualifies one of them.

**Status:** Implemented.

---

## 4. Declaring a trait

```julia
@trait ColTable begin
    ncols(t::ColTable)::Int
    col(t::ColTable, i::Int)::Vector{Float64}
    firstcol(t::ColTable)::Vector{Float64} = col(t, 1)
end
```

`@trait X` declares the abstract type `X`, open, with the contract its body states. It changes no compiled code: its methods are at a trait with no members yet.

### 4.1 Operations

- **An operation is a generic function with declared argument and result types.** A plain name creates a function in the declaring module; a qualified name (`Base.length`) names an existing one.
- **The receiver** is the one argument typed by the trait or `Self`, at any position: `Base.print(io::IO, x::Printable)::Nothing`. Where several arguments are typed by the trait, the first is the receiver; the others take any member.
- **Every operation declares its result type.** A declaration without one is an error.
- One operation may be declared at several arities, and at one arity several times where the further arguments' types are disjoint.
- **`where` variables** on an operation are fixed by its arguments and checked at each membership as the trait's parameters are: `solve_core(a::ODEAlgorithm, m::CoreProblem{T}, cbs::Vector{StepCallback{Vector{T}}})::Nothing where {T}`.
- An operation may mutate its arguments.
- **A value fixed per member** (an algorithm's order) is an operation with a declared result: `alg_order(a::ODEAlgorithm)::Int`. A call on a known type folds to the constant.

**An operation is an entry of the trait's contract, not a method at the trait.**
- The entry holds the function, the declared argument types and the declared result ([compiler §4.1](compiler.md#41-sets)).
- Declaring a trait defines no method for an operation without a default. Each member serves it by a method of its own type: its own method (§5.3, §5.4), or the method its forwarding membership defines (§5.5). `Dynamic{X}` serves it by a forwarding method of its own (§7.7).
- So a call of the operation is a call of its function, dispatched as any call: to the member's own method. A method that takes any receiver (a function's untyped fallback, `mul!(C, A, B)`) serves too: no method at the trait hides it.
- An operation with a default is the one with a method at the trait: the default (§4.2).

**What is checked.**
- At each membership: a method applies at the member and the declared further argument types, or a default or a forwarding field serves the operation; its result infers to a subtype of the declared result.
- At a call on a value whose type the code knows only as the trait: the result is asserted to the declared type (§7.9).
- At a call outside the declared signature that no method of the member takes (`scale(c, 2)` for `scale(s::Scalable, k::Float64)`): Julia raises its `MethodError`, with a hint that names the operation's declared signature and its trait (§11.4).

**Status:** Implemented.

### 4.2 Defaults

```julia
describe(s::Shape)::String = "a shape of area $(area(s))"
```

- A default is an operation with a body, written with the trait's other operations and fields. The trait's parameters are in scope.
- **It is the trait's method for that operation**, a method at the trait. A member's own method is more specific and wins (§6.2).
- **Only a default is a method at the trait.** An operation without one is an entry of the contract alone (§4.1).
- **Every caller reaches it:** plain code that calls `describe(c)` on a member without its own method gets the default. So a default at the trait hides a member's method that takes any receiver: the member defines the operation at its own type to serve it otherwise (§5.10).
- Which operations a default serves for a member is fixed at its membership (§5.11).
- Rust's and Swift's default methods are reached by every caller in the same way, as a method on an abstract type is in Julia.

**Status:** Implemented.

### 4.3 Fields

```julia
@trait Integrator{U, P} begin
    u::U              # writable
    @const p::P       # read-only
    t::Float64        # writable, of a fixed type
end
```

- **A declared field is the member's stored field of that name.** Code reads it as `t.u` and writes it as `t.u = x`, as for any value.
- `@const` makes it read-only through the trait.
- **A read-only field** may be stored at a subtype of its declared type.
- **A writable field** needs a mutable member, a stored field that is not `const`, and a stored type equal to the declared type at the member's parameters. So a write never changes a type compiled code relies on.
- **A member with its own `getproperty` or `setproperty!`** conforms only where they give the stored field at each declared name. The membership's check infers them at each name and refuses another result type.
- A computed property is not a declared field. It is **a field named by an input parameter:** `@const N::R` with `@input N` declares `x.N`, of type `R`, at each value of `N` a member joins at. A stored field of that name or the member's own `getproperty` serves it; the check infers `getproperty` at the constant name. BaseTraits declares `HasProperty{N, R}` so (§10.1). Only an input names a field.
- A field declared at an abstract type is read at that type, and operations on it dispatch when they run.
- **State some members write and others only read** is two traits: one that declares the field `@const`, and a subtrait that adds the operations that change it.

**Status:** Implemented.

### 4.4 `Self`

- In a trait's body, **`Self` is the receiver type**: the member when it serves an operation by its own methods or defaults, the field's type when the member forwards (§5.5).
- It appears as an argument's type, in result types and in equations (`T = eltype(Self)`).
- **A constructor operation** returns `Self`: `kwith(t::KTable, cs::Vector{Vector{Float64}})::Self`. With `like(t, x)` (§6.5) it returns "a value like the input".

**Status:** Implemented.

### 4.5 Supertraits

```julia
@trait DGrow{T} <: DCol begin
    T = eltype(Self)
    dpush!(c::DGrow, x::Float64)::Nothing
end
@trait Integrator{U, T, P} <: IntegratorView{U, T, P}
```

- `@trait B <: A` makes `B` a subtype of `A`. A member of `B` is a member of `A`.
- **`B`'s contract includes `A`'s.** `@implement B S` checks `A`'s operations and fields at `S` too, and makes `S` a member of `A`.
- **A member that also joins `A` by a membership of its own** must serve `A`'s operations the same way through both: by its own methods, or forwarding to the same field. A disagreement is refused (`ImplementError`).
- **Several supertraits:** `@trait C <: (A, B)`. `C`'s members must join `C`, and are then members of `A` and of `B`. A name for "a member of both" is an intersection (§3.6).
- **Parameters:** a supertrait is written with the subtrait's parameters, constants and type constructors. Every member of `B{U, T, P}` is a member of `A{U, T, P}`.

**Status:** Implemented.

### 4.6 Erasing by default
<a id="46-the-traits-default-attribute"></a>

`@default_dynamic` in the body makes the trait **erase by default:** a method at the trait takes a plain member boxed, as `Dynamic{X}(t)`, and a kept form as it is (§7.8). The contract records it ([compiler §4.1](compiler.md#41-sets)).
- A trait without it takes a plain member as it is, as Julia takes a value at an abstract type.
- A caller chooses otherwise by what it passes: `compiled_for(x)` for code per type, `Dynamic{X}(x)` at a trait that does not erase (§7.5).
- `Callable` erases by default (§9).

**Status:** Implemented, but for T-125.

---

## 5. Joining a trait

### 5.1 The forms

| Form | Joins | Served by |
|---|---|---|
| `struct S <: X … end`, then `@implement X S` | with the type's definition; declared and checked by the `@implement` | `S`'s own methods and the defaults |
| `@implement X S` | after | `S`'s own methods, the defaults, `S`'s fields |
| `@implement X S begin … end` | after | the methods in the block, and the defaults |
| `@implement X S by f` | after | the field `f`'s type, a member by its own methods |
| `@implement (X, Y) S …` | after | as above, for each trait |
| `@implement X{p…} S` | after | as above, with stated parameters |
| `@implement X S{P} where {P}` | every instance, after | per instance, as above |
| `@implement X A` for a closed abstract type or a trait `A` | every member of `A`, after | methods at `A`, or each member's own |

All forms share these rules:
- **A membership is declared, never inferred** from the methods that happen to exist.
- It may come after the type's definition, in another package, by a stakeholder (§12.1).
- It is checked against the contract (§5.10).
- **It invalidates as a method definition does:** the compiled code that relied on its absence, and no other. A new type that joins invalidates nothing ([facts §10](facts.md#10-memberships)).

**Status:** Implemented.

### 5.2 With the type's definition

```julia
struct Circle <: Shape; r::Float64; end
area(c::Circle) = π * c.r^2
perimeter(c::Circle) = 2π * c.r
@implement Shape Circle                    # declares and checks the membership
```

- `struct S <: X` makes the trait `X` the supertype of `S`, as for any abstract type: `S <: X` holds from the definition.
- **The membership is declared by `@implement X S`,** in the same module, after `S`'s methods. It checks the contract (§5.10). A membership is always declared, and checked where it is declared: like any membership, it is kept in the package's image and seen by the ambiguity report (§6.3).
- **A use of `S` through `X` before the `@implement`** (a call that needs `S`'s membership checked) raises `ImplementError` naming the missing declaration. The `@implement` then replaces that failure. A module that ends with a `struct S <: X` and no `@implement X S` is refused at its end.
- `struct S <: X{Float32, 1}` states parameters: the parameters come from the definition. The `@implement` may repeat them; a stated value, or a field's type, that differs is refused.
- `abstract type A <: X end` likewise needs `@implement X A`; every subtype of `A` is then a member, each checked at its first use (§5.9).

**Status:** Implemented.

### 5.3 One line

```julia
@implement ColTable Ramp           # Ramp has methods of ncols and col
@implement Placed Sprite           # a trait of fields only: Sprite has the fields
```

- `S`'s own methods serve every operation without a default; define them before the declaration.
- A trait of fields only is served by `S`'s stored fields.
- **No field is special:** the one-line form never forwards. Forwarding is written with `by` (§5.5).
- Errors name the operations: methods for some operations and not for others; no methods (listing the fields whose type is a member, each with its `by` line).

**Status:** Implemented.

### 5.4 With a block of methods

```julia
@implement ColTable Vector{Vector{Float64}} begin
    ncols(t) = length(t)
    col(t, i) = t[i]
end
```

- The block defines the operations' methods for the type and declares the membership, in one step.
- Names are the operations' names. Each must be an operation of the trait, at a declared arity.
- The receiver is typed by the member; unannotated arguments take the operation's declared types.
- The methods are ordinary methods of the type; every caller finds them.

**Status:** Implemented.

### 5.5 Forwarding with `by`

```julia
@implement ColTable Halves by right
```

- **A convenience of the library,** outside the language's core: the membership (§5.3) with a method per operation that calls it on the field.
- Every operation is served by the field `right`. The field's type is the **receiver type** and `Self`.
- The field's type must be a member by its own methods or defaults. **Forwarding does not chain.**
- The forwarding field may not also be a writable declared field.
- **A forwarding member has a method of its own for each required operation,** defined with the membership: it calls the operation on the field. An operation with a default is served by the trait's method, which calls it on the field. Every caller reaches them, as for a default (§4.2).
- A trait that requires a concrete `Self` (§14) refuses a forwarding field of an abstract type.

**Status:** Implemented.

### 5.6 Several traits at once

```julia
@implement (ColTable, RowTable) Grid by data
```

One declaration, one membership per trait, all served the same way. Each may also be declared on its own.

**Status:** Implemented.

### 5.7 Stating parameters

```julia
@implement ArrayLike{Float32, 1} MyVec
```

- A membership states the parameters that no field and no equation defines.
- A stated value for a parameter an equation defines is checked against the equation at the member. If they differ, the membership is refused (`ImplementError`).

**Status:** Implemented.

### 5.8 Families

```julia
@implement Fam S{P} where {P}                            # every S{P}, by S's own methods
@implement KVec{T} Vector{T} where {T <: Real} begin     # every member, with methods written here
    klen(v) = length(v)
    kget(v, i) = v[i]
end
@implement StateVector{T} Series{T} where {T}            # the trait's T tied to the type's T
@implement SVec LSeries{T} by data where {T}             # forwarding, for every instance
```

- A family covers every instance of a parametric type that its `where` clause admits. Each instance is a member from the declaration.
- **Each member is checked at its first use** (§5.10). The family's declaration checks ownership and the form.
- **The trait's parameters** are written with the family's variables, constants and type constructors, never with function calls. Every variable of the trait's parameters occurs in the type.
- **An override of one member** is declared by the package that owns the member's parameter type (`MyT` in `S{MyT}`), in that package itself.
- Where an operation's declared argument type is abstract, a member's check counts only the methods of its stakeholders there. So a member's check does not depend on which packages loaded before its first use.
- **The family's variables are in scope in its block's methods,** as their static parameters: `@implement Holds{T} Box{T} where {T} begin elt(h) = T end`. Rust's generic `impl<T>` scopes them the same way.
- **Where an equation defines a parameter** (`T = eltype(Self)`), the family states it as a type expression of its variables: `@implement Iterable{T} Wrapped{T} where {T}`. Each member's check compares the equation's value with it. A family whose instance cannot be written so is refused, naming the parameter. Rust writes an associated type in a generic `impl` the same way.

**Status:** Implemented, but for [compiler C-31](compiler.md#deviations).

### 5.9 Abstract types and traits as members

```julia
@implement Indexable{T} AbstractVector{T} where {T}        # every AbstractVector, by its own methods
@implement GTable Indexable{Vector{Float64}} begin         # every member of a trait, by methods written here
    gn(r) = length(r)
    gcol(r, i) = r[i]
end
```

- A closed abstract type or a trait may be a member of a trait. Every member of it is then a member, transitively.
- A block's methods are methods at that type: `gn(r::Indexable{Vector{Float64}}) = length(r)`.
- **Overlaps are Julia's ambiguities.** A type that is a member through two paths with unrelated methods for one operation needs a joint method (§6.3).
- A membership of a trait in a trait applies only to a trait without declared fields; a trait with fields needs each type's own membership, which locates them.
- Each member reached this way is checked at its first use.

**Status:** Implemented.

### 5.10 Checks

**When.**
- At `@implement X S` for one type: at the declaration.
- For `struct S <: X`: at the `@implement X S` that follows it (§5.2).
- For a member of a family, of an abstract type or of a trait: at the member's **first use**, the first time a call needs its membership when the program runs: a method at the trait, or an operation's call through the trait (§7.9; [lowering §4](lowering.md#4-members-checked-at-their-first-use)).
- **The check is its serving instances:** each serving method's instance at the member and the declared argument types, compiled by Julia's inference and kept with its edges, as code is. A package image keeps them with its code. A later session validates them with the image, as it validates any code, and infers nothing again while they hold.

**What.**
- **Who:** the declaring package owns the trait or the type (§12.1).
- **Completeness:** every operation is served at the member; every declared field exists with the declared type. An operation without a default is served by the method dispatch selects at the member and the declared further argument types, a method that takes any receiver included (LinearAlgebra's `mul!(C, A, B)`): no method at the trait hides it (§4.1). An operation with a default is served by the member's own method where one is more specific than the default, else by the default (§4.2).
- **Results:** each serving method's result infers to a subtype of the declared result. A result that infers wider than the declared one, or outside it, is refused; the fix is the member's inference (a concrete field type, a type parameter), not an assertion. Where a further argument is declared abstract (an iteration state, `x::AbstractVector{T}`), a method that meets the declared signature serves and its result is not inferred there: each call through the trait asserts it (§7.9).
- **Fields:** §4.3.
- **Parameters:** fields define them consistently; equations agree with stated values; values within their bounds; one instance per member (§3.2).
- **Supertraits:** §4.5.
- **Concreteness:** where the trait asks for it (§14).

**A failure** raises `ImplementError` (§11.3).
- At a declaration, the declaration then declares nothing: no membership and no methods.
- At a first use, the member stays a member (a failed check takes no membership back), and every use of it through the trait raises the same `ImplementError`.

Not everything is caught: a conversion that fails at run time is not proved by the check.

**While it is a member.** A member's check holds while it is a member. A method defined after the check is refused when it is defined (`ImplementError`), and does not exist, where it would end one of the member's check instances through their edges, and at that call it would:
- serve the call with a result that infers outside the declared result;
- or make the operation ambiguous at the member.
- A method whose result infers within the declared result is accepted.
- **A method below an operation's body** that would widen a serving instance's result ends that instance through its edge, and is judged the same way.
- Finding the instances a definition would end is the walk strict mode runs for code compiled by facts ([facts §11.2](facts.md#112-strict-mode)), run over check instances. One mechanism refuses both.
- The new method itself is inferred at the call, before it exists. A call it makes to its own function sees the methods in force, so a self-recursive method's recursion is inferred at the method it replaces.
- The message names the member, the operation, the trait, the declared and the inferred result, and the two fixes: return within the declared result, or do not define the method at this member.
- An operation whose result the check did not infer (an abstract further argument) has nothing to keep: each call through the trait asserts the result (§7.9).
- A serving method deleted leaves the member without one until a method serves it again; its calls raise `MethodError`. The method that serves it again is checked against the member's check, not against the state after the deletion.
- A package image's method that the rule refuses is left inactive when the image loads, with a warning. A package that defines one after its own `@implement` fails to precompile.
- A trait redeclared as a new type has no members of its own: the old type's members keep no check.
- The declared result is read from the trait's contract when the method is defined.
- A membership loaded from a package's image keeps its check too: its instances are validated with the image. A method already in the session that ends one is found by that validation; the instance is inferred again, and a result outside the declared one is reported at the load (§12.3).

**Status:** Implemented; the check as its serving instances, kept with their edges and validated with an image: Planned, with T-129.

### 5.11 Overrides and redeclaration

- **Which operations defaults serve for a member is fixed at its membership.** A later method that would take a call a default serves at the member is refused when it is defined (`ImplementError`). The message names the fix: define the method before the membership, or in its block. A package image's such method is left inactive when it loads, with a warning.
- **A forwarding member's methods are fixed at its membership, like the defaults:** a later method that would take a call one of them serves at the member is refused the same way (§5.5).
- **Redeclaring a membership** replaces it. The new one holds from its world; the old one ends there; code compiled for the old one is invalidated. It is a stakeholder's change ([facts §2.2](facts.md#22-g2-stable-caches)).

**Status:** Implemented, but for T-129.

### 5.12 Types that only convert

```julia
@trait TableLike begin
    columnnames(t::TableLike)::Vector{Symbol}
    column(t::TableLike, n::Symbol)::AbstractVector
end
materialize(t::TableLike)::Vector{Vector{Float64}} = [Float64.(column(t, n)) for n in columnnames(t)]
```

A type whose data a library can use only after a conversion (a lazily derived table, a foreign layout) does not join by a field. The library converts it through a trait that reads any such type, and runs its own code on the result: a copy, no write-through. A pattern, nothing to build.

**Status:** Planned.

### 5.13 Taking a membership back

```julia
delete_membership(Shape, Circle)       # Circle is no Shape from the next world on
```

- **`delete_membership(X, S)` takes back the membership of `S` in `X`** that an `@implement` declared, as `Base.delete_method(m)` deletes a method. `S` is the member as declared: a type, a family `S{T} where T`, an abstract type or a trait. `X` names the trait, at the input values that select the membership where the trait has inputs.
- **It behaves as a method's deletion:**
  - it holds from the next world on; a task in an older world keeps the membership;
  - the code that relied on the membership is compiled again: a call at the member that selected a method at the trait, an `isa` or `<:` that folded true, code compiled at the member for the trait;
  - no other code is: a call that dispatched to the member's own method keeps it.
- **Who may:** whoever may declare it (§12.1), the trait's owner or the type's. One by neither is a pirate's, as a pirate's membership is (§12.2). In strict mode it is refused where code compiled by facts relies on it, as a method's deletion is ([facts §11.3](facts.md#113-strict-modes-errors-at-their-sources)).
- **What goes with it:**
  - the member's check, and the records of §5.10 and §5.11: a later method at the member is not judged by them;
  - the member's place among the trait's candidates (§7.9);
  - for a family, an abstract type or a trait as member, every member it made, with their checks.
- **Values stored before stay where they are.** An item of a `Vector{Shape}` whose type is no member any more is called by its type, as plain code's call is; an operation's call through the trait still asserts the declared result (§7.9). So every call computes what plain code computes, or raises.
- **What cannot be taken back alone:**
  - a member by its definition (`struct S <: X`): its supertype is its definition's, and only a new definition of `S` changes it;
  - a trait's membership in its supertraits, and `Dynamic{X}`'s: they are part of the trait's declaration.
- **A membership declared again** after it was taken back is a new declaration, checked as any (§5.10).
- **Revise:** an `@implement` line deleted from a file takes its membership back, as a deleted method definition deletes its method ([lowering §3](lowering.md#3-implement)).
- **Package images:** an image holds the memberships in force when it is written. Taking one back in a session changes no image. An image loaded afterwards whose code relied on it has that code compiled again: its edge to the membership fails validation.

**Status:** Implemented, but for [lowering L-64](lowering.md#15-deviations) (Revise).

---

## 6. Methods at traits

### 6.1 A method at a trait is a method

```julia
colmean(t::ColTable, i::Int) = (c = col(t, i); sum(c) / length(c))
describe(v::Vector{Float64}) = "a vector"
describe(m::AbstractMatrix) = "a matrix"
describe(t::ColTable) = "a table with $(ncols(t)) columns"
describe(x) = "something else"
```

- Any method in any module may name a trait in its signature. It is a method of its generic function, dispatched by Julia.
- Its body may do with the argument what any body may do with an abstract-typed argument. What the body does decides whether the method is bounded (§7.3), never what it means.

**Status:** Implemented; how a method is compiled: §7.3.

### 6.2 Specificity

- **At each argument: a closed type other than `Any` is more specific than a trait.** `describe([1.0 2.0])` takes the `AbstractMatrix` method, although `Matrix{Float64}` is a `ColTable`. So a later membership never takes a call from a method on the type's own supertypes, and a library adopts traits one function at a time.
- **Between traits:** by subtyping. A subtrait is more specific than its supertrait; an intersection than each of its components. Unrelated traits are unordered.
- `Any` is the least specific, as always.

**Status:** Implemented.

### 6.3 Ambiguity

- **As in Julia:** a call where two methods apply and neither is more specific raises `MethodError` (ambiguous).
- **Reported earlier, at a membership:** where a membership makes a method apply to a type, and another method of the function is tied with it there with no more specific method for the type, a warning names the function, the methods and the joint method to define (`f(::All{ColTable, RowTable})`). The other method may be at a second trait of the type, at a trait or abstract type the type is under by its definition, or at `Any` with a narrower type at another argument. Under strict mode it is an error (§12.3): the membership that creates the ambiguity raises `ImplementError` and does not exist; a later membership, a redeclaration among them, is not refused for an ambiguity it did not create. For a member by its definition (`struct S <: X`), `X`'s methods apply by the definition, so a second trait's `@implement Y S` is the membership that creates the ambiguity, whether it comes before or after `@implement X S`. A method that dominates every common member suppresses the report.

**Status:** Implemented.

### 6.4 The fallback

A value that matches no method at a trait reaches the most specific method that applies, as in Julia, or raises `MethodError`. A member at other parameter values than a method states, or a broken shared variable, is such a value.

**Status:** Implemented.

### 6.5 Results

```julia
total(t::ColTable)::Float64 = sum(sum(col(t, i)) for i in 1:ncols(t))
kscaled(t::KTable, a::Float64) = like(t, kwith(t, [a .* kcol(t, i) for i in 1:kncols(t)]))
shifted(r::LRec{Vector{Float64}}) = withfields(r; u = r.u .+ 1.0)
```

- A result annotation is Julia's: `f(…)::T` converts, then asserts.
- **`like(t, x)`** is a value like `t`, built from `x`:
  - where `t`'s membership serves the trait by its own methods: `x`, which must be of `t`'s type, or the same type at other parameters;
  - where it forwards by a field: `t`'s type rebuilt by its positional constructor, the forwarding field replaced by `x`, the other fields kept; the constructor recomputes the parameters, so a sibling at other parameters comes out where `x` has them;
  - on a box `Dynamic{X}`: a `Dynamic{X}` of that value; on a wrapper: the wrapper of `like` of its object.
- **`withfields(t; name = v, …)`** is `t` rebuilt with declared fields replaced:
  - on a member: its type's positional constructor called with the named fields replaced;
  - on a box `Dynamic{X}`: the object it holds rebuilt, boxed at `X`; the box is made as any box is, so a rebuilt object that is no member of `X` is refused there. Only the fields `X` declares are named at a box (`ArgumentError` otherwise): behind the box only the contract reaches the object;
  - on a wrapper: the wrapper of the rebuilt object.
- So a method that rebuilds its argument with `like` or `withfields` is bounded ([§7.3](#73-bounded-methods)): at the box its result is a box.
- **`like` and `withfields` are conveniences of the library,** outside the language's core: functions that rebuild a member from its declaration ([lowering §8](lowering.md#8-like-and-withfields)).

**Status:** Implemented.

### 6.6 Keywords, defaults, varargs

- As in Julia. A positional default makes two methods; a keyword typed by a trait raises `TypeError` for a value that is not a member; there is no dispatch on keywords.
- **A vararg of members,** `ts::ColTable...`: elements may be different members; code is compiled per tuple of their types.

**Status:** Implemented.

### 6.7 Constructors

A type's constructor may have methods at traits: `NWState(int::All{IntegratorView, HasSystem}) = NWState(sysnet(int), ustate(int))`. The type's other constructors stay, its default ones included.

**Status:** Planned.

### 6.8 Who may add a method

As for any method (§12.2): a package may add a method to a function it owns, or to another package's function where a type in the signature is its own. A trait it owns counts. Another package's owner-only function takes methods from its owner only (§12.2).

**Status:** Implemented.

---

## 7. Compiling: the box and the wrapper
<a id="7-compiling-keys-and-the-attribute"></a>

Everything in this chapter is a choice of speed. A method gives the same results for a member and for its kept forms, but where it asks a kept form what only the object can answer: its type, its identity, a function outside the contract (§7.4).

### 7.1 How an argument is compiled
<a id="71-three-ways-to-compile-an-argument"></a>

A method is compiled as Julia compiles any method: for the types of the values it is given. A trait adds two kept forms of a member, each a concrete type and a member (§7.4). So at an argument typed by a trait the method's code is:
- **for a plain member:** compiled for its type, one copy per concrete type, as in Julia;
- **for a box, `Dynamic{X}(x)`:** compiled once per trait instance, one copy for every member (§7.7);
- **for a wrapper, `compiled_for(x)`:** compiled for the type of the object it holds (§7.6);
- **at an argument declared `@nospecialize(t::X)`:** compiled once at the declared type, as Julia compiles such an argument; the object is passed as itself, and its operations take the branches of §7.9.

Which form a value has is in its type. Nothing beside the call decides (§7.5). A trait that erases by default boxes a plain member at its methods (§7.8).

Per key, one copy shared by every member with that key, is an optional extension (§7.2).

**Status:** Implemented; per key: Optional (§7.2).

### 7.2 The key

Code shared per key, among members the contract sees alike, is an optional extension: [extensions §1](extensions.md#1-keys-code-shared-among-members-the-contract-sees-alike). No rule of this reference depends on it.

**Status:** Optional.

### 7.3 Bounded methods
<a id="73-fully-bounded-methods"></a>

```julia
colmean(t::ColTable, i::Int) = sum(col(t, i)) / length(col(t, i))   # bounded
leak(t::ColTable) = typeof(t)          # bounded: at a box, the box's type
wrap(t::ColTable) = Wrapped(t)         # bounded: at a box, a Wrapped{Dynamic{ColTable}}
colsum(t::ColTable) = sum(t)           # not bounded: at a box, sum reaches iterate(::Dynamic{ColTable}), which has no method
```

A method is **bounded** at a trait argument when its code for the box does what it says for every member: **its instance at `Dynamic{X}` makes no call, with a value at the box, that finds no method or only throws.** A value at the box is the box itself, or a value the code knows only by a trait (an operation's result declared with one), or a tuple that holds one (a vararg of members).
- **That instance is ordinary code at a concrete type,** compiled by Julia's own inference, with its edges. It is the code a box runs at the method (§7.7), and, for a trait that erases by default, the code every plain member runs through the forwarder (§7.8).
- **What it certifies:** behind the box only the contract's operations reach the member (§7.7). So a bounded method works, erased, for every member that will ever join. Rust checks a generic body against its bounds with an archetype; here the archetype is a real type, the box.

**A fault** is a call in that instance, with a value at the box:
- that finds no method at the types the code knows: directly; below a call that only throws, the chain of calls named; or left to run time. A call is read as written: where Julia compiles a call at an abstract argument as the methods that cover a part of it and a `MethodError` for the rest, the call has a method at the types the code knows, and is no fault;
- that only throws: an undeclared field read at the box is named as such. A call left to run time that inference gives as never returning only throws.
- A call left to run time that finds a method when it runs is Julia's function barrier, no fault.

**What the body does decides,** not a list of forms.
- `typeof(t)`, `Wrapped(t)`, a closure that captures `t`, `like(t, …)`, `withfields(t; …)`, a constructor that stores `t` at a struct parameter: each acts on the box, and is bounded.
- `sum(t)` at a box of `ColTable` reaches `iterate(::Dynamic{ColTable})`, which has no method: not bounded. The report names `iterate`, reached from `sum`. At a box of `Iterable{Float64}` the same call is bounded, and Base's `sum` is compiled once for the box.
- A function of `Self` that an equation names (`eltype(t)` where the trait defines `T = eltype(Self)`) answers at the box as for the object: its value is the trait's parameter (§7.4).

**The report** names the line of the method that passes the value, and what the call reaches, at any depth; at a vararg of boxes, what a call that passes one box reaches.

**Where the instance is read.**
- Each argument at a trait, an intersection, a kept form, or a `where` variable bounded by one, at the box of that trait.
- A vararg of members, `ts::X...`, with each element in a box, at least one: the instance a call that passes boxes there runs.
- A variable the signature leaves free, at a stand-in: the first of `Float64`, `Int`, `Symbol`, `String` its bounds allow, else its bound where that is concrete.
- A keyword method's body is read, not its sorter. The forwarders (§7.8) are not read.
- A method whose box cannot be formed (a trait whose parameters the signature leaves open, where no stand-in fits) is not read.

**When.** Where the method is defined (§11.2). At its module's end a call of a name the module never defines is a fault. A method whose body names a global not yet defined, or whose only faults are calls of its module's own functions with no method yet, waits for those names, and at last for its module's end. The instance is kept with its edges, as any code: a later definition that changes what it relied on ends it, and the check reads it again when it is inferred again.

- **A scope that declares `bounded`** (§13) refuses a method that is not bounded, with `TraitUseError` naming each fault and its line.
- **`@unbounded f(…) = …` marks a method unbounded on purpose:** `bounded` does not refuse it. A library's adapter that hands its argument to plain code is written so.
- With keys, an optional extension (§7.2), a bounded method would share its code per key.

**Status:** Implemented, but for [compiler C-115](compiler.md#deviations).

### 7.4 The two kept forms: the box and the wrapper
<a id="74-the-attribute-compiled-and-dynamic"></a>

```julia
d = Dynamic{Shape}(Circle(1.0))     # the box: code for it is compiled once per trait instance
w = compiled_for(Circle(1.0))       # the wrapper: code for it is compiled for Circle
area(d), area(w)                    # (3.141592653589793, 3.141592653589793)
```

A member of a trait `X` is passed as itself, or in one of two **kept forms**. Each kept form is a concrete type and a member of `X`:
- **the box `Dynamic{X}(x)`** holds `x` erased. Its type is one for every member of `X` at the trait's parameters, so code for it is compiled once per trait instance (§7.7);
- **the wrapper `compiled_for(x)`** holds `x` with its type, `Compiled{typeof(x)}`. Code for it is compiled for the object's type, and its operations call the object's own methods, statically (§7.6).

**A kept form is a value.** The choice is in its type, so it travels wherever a value goes: through storage (§8), an untyped parameter, a record made before a signature is known, a closure, a closed build.

**What each form runs.**
- **An operation is reached through both forms,** and through both it is the member's own method, a method specialized for the member's type included (§4.1, §7.9).
- **A function of `Self` that an equation names answers through both forms as for the object:** `eltype(d)` for a box of `Iterable{Float64}` is `Float64`, the trait's parameter (§3.2).
- **The box runs the methods at the trait it was erased at; the wrapper runs the most specific methods of its object's traits.** The wrapper is a member of every trait its object is in, so a subtrait's method is taken for it as for its object. A box of `X` is a member of `X` and its supertraits only (§7.7). The results are equal where a subtrait's method refines its supertrait's, as Julia assumes of every more specific method. Two boxes of one object, at a trait and at its subtrait, differ the same way.
- **The wrapper can meet an ambiguity that the box does not:** a function with methods at two unrelated traits of its object. It is the ambiguity the report at a membership names (§6.3).
- **Erased code can be slower by algorithm, not only by dispatch.** A box that entered through `Iterable` stays at `Iterable`'s method. A library that wants the subtrait's method under erasure writes a barrier: `total(unwrap(t))`.
- **Neither form is the object.** `typeof(t)`, `t === x` and `t isa Circle` answer for the kept form. A function outside the contract with a method at the object's own type is reached through neither: `unwrap(t)` is the object, statically for a wrapper, by one dispatch for a box. So in trait code what varies by member is an operation, or a method at a subtrait.

| A member of `X` passed | Its type | Code compiled for it | An operation on it |
|---|---|---|---|
| as itself | its own | per type | the member's method, called statically |
| as a box `Dynamic{X}(x)` | one per trait instance | once per trait instance | the member's method, found when it runs; the declared result (§7.9) |
| as a wrapper `compiled_for(x)` | `Compiled{typeof(x)}` | per type of the object | the member's method, called statically |

Rust's pair is the same: `dyn X`, and a generic `T: X`. Here both are members of `X`, so one method at `X` takes either.

**Status:** Implemented.

### 7.5 What decides

**The value's type decides, as in Julia.** A call runs the method's code for the types of the values it is given: a plain member's, a box's or a wrapper's. Nothing beside the values decides: neither the call's site nor the method's module. So a call gives the same code at the prompt, in compiled code, through an untyped parameter, from a record and in a closed build.

A choice is made in three places:
- **by the caller, with a value:** `compiled_for(x)` for code per type, `Dynamic{X}(x)` for code compiled once. The caller writes it where the value is made, in plain code too. Storage and parameters keep it (§8).
- **by the trait, for a plain member:** a trait that declares `@default_dynamic` erases by default. Its methods box a plain member and take a kept form as it is (§7.8). A trait without it takes a plain member as it is.
- **by a library, at its doors:** a library erases where it chooses, `solve(m::Model, u0) = _solve(Dynamic{Model}(m), u0)`. `unwrap(t)` at a call is the barrier back to code per type.

```julia
@trait Model begin
    @default_dynamic                          # a solver's models: erased by default
    rhs!(m::Model, du::Vector{Float64}, u::Vector{Float64}, t::Float64)::Nothing
end
solve(m::Model, u0) = …                       # m is a kept form
solve(MyModel(), u0)                          # boxed by the forwarder: the code compiled once runs
solve(compiled_for(MyModel()), u0)            # the wrapper: the code compiled for MyModel runs
```

- **A `where` variable bounded by a trait is the type of what the method is given:** in `f(x::C) where {C <: X}`, `C` is `typeof(x)`, a member's, a box's or a wrapper's type. Where `X` erases by default, `C` is the kept form's type.
- **`@nospecialize` and `@specialize` are Julia's,** at a trait argument as at any other (§7.1).

**Status:** Implemented, but for T-125.

### 7.6 `compiled_for(x)`
<a id="76-casts"></a>

```julia
w = compiled_for(lorenz!)                     # Compiled{typeof(lorenz!)}
prob = ODEProblem(w, u0, tspan, p)            # the solver compiled for lorenz!
```

- **`compiled_for(x)` is a function. It returns the wrapper of `x`,** `Compiled{typeof(x)}`. It is made in plain code, before any trait is known. Storage keeps it, a record made before a signature is known keeps it, an untyped parameter passes it.
- **The wrapper is a member of every trait its object is a member of,** at the object's parameters: each `@trait` declares the wrapper's family as a member ([lowering §2](lowering.md#2-trait)).
- **Its operations call the object's own methods, statically:** the call is compiled for the object's type. Its declared fields are the object's, read and written through it. A wrapped function is called as the function is (§9).
- **It is not the object:** `typeof(w)` is `Compiled{…}`, and `w === x` is false. `unwrap(w)` is the object.
- `compiled_for(d)` of a box is the wrapper of the box's object. `compiled_for(w)` of a wrapper is `w`.
- **The name is the library's,** exported as any function is. A module that binds its own `compiled_for` has its own.
- Equality: §8.3. Printing: §15.

**Status:** Implemented.

### 7.7 `Dynamic{X}`

```julia
d = Dynamic{Shape}(Circle(1.0))     # a Shape, compiled once wherever it goes
area(d)                             # 3.141592653589793, the call dispatched when it runs
hooks = Dynamic{Hook}[Dynamic{Hook}(Below(0.9)), Dynamic{Hook}(Always())]
```

- **`Dynamic{X}` is a struct of Julia's `Core`** that holds a member of `X`: the box. The library declares its memberships and defines its methods. It is itself a member of `X` and of `X`'s supertraits, and code for it is compiled once per trait instance.
- **`Dynamic{X}(x)` makes one.** A value that is not a member raises `TypeError`. Making one compiles nothing per value type. Where the code knows `x`'s type, the membership is decided when the code is compiled, so the box tests nothing when it runs ([compiler §4.8](compiler.md#48-negatives-fold-with-an-edge-positives-through-entries)).
  - A box of `X` given a box of `X` is that box. Given a box of a subtrait, it holds that box's object at `X`.
  - Given a wrapper, it holds the wrapper's object: the wrapper's choice is erased there.
  - A member of a bits type is allocated when it is boxed.
- **`X` is a trait with its parameters, or an intersection of such:** `Dynamic{StateVector{Float64}}`, `Dynamic{All{Shape, Placed}}`. `Dynamic{Column}`, with `Column`'s parameter left open, is refused when made (`ArgumentError`, naming `Dynamic{Column{T}}`), as Rust's `dyn Iterator` must name its `Item`. So a box is made where the parameters are known: a method written `c::Column` boxes at the instance the member is in (§7.8); a box at a second signature (a function seen at the duals too) is made again where that signature is known. Members whose parameters differ share a container typed by the trait, `Vector{Column}`.
- **Its operations** dispatch on the held object when they run, with the declared results. They are forwarding methods of its own, at `Dynamic{<:X}` ([lowering §2](lowering.md#2-trait)). Its declared fields are read and written on the held object.
- `unwrap(d)` is the held object.
- **It is a member of `X` and `X`'s supertraits only,** not of the other traits its object belongs to. To pass it where another trait is required, unwrap it, or box it as `Dynamic{All{X, Y}}`, a member of both.
- **It is under none of its object's declared supertypes:** a boxed function is no `Function`, a boxed vector no `AbstractVector`. For a closed abstract type the eraser is a subtype of it, as `IOContext{IO}` is (§9b).
- **A question outside the contract is asked before the value is boxed:** a function's arity by reflection, a field the trait does not declare.
- **A `Dynamic{Callable{A, S}}` is called at `A` only.** To call its function at another signature, box it again, `Dynamic{Callable{B, S}}(unwrap(d))`, or as `Dynamic{All{Callable{A, S}, Callable{B, S}}}` where both signatures are known when it is made.
- **It keeps its form through storage:** a `Vector{Dynamic{Shape}}`, a field of type `Dynamic{Shape}` or `Shape` (§8).
- A result declared `::T` is asserted at the parameter's value: at `Float64` for a `Dynamic{StateVector{Float64}}`.
- Rust's `dyn X` and Swift's `any X` are such boxes: usable through their own trait only. `Dynamic{All{X, Y}}` is Swift's `any X & Y`.

**Status:** Implemented.

### 7.8 Erasing by default: the forwarder
<a id="78-keeping-an-argument-with-its-attribute"></a>

```julia
@trait RHS{T, P} begin
    @default_dynamic
    rhs!(f::RHS{T, P}, du::Vector{T}, u::Vector{T}, p::P, t::Float64)::Nothing
end
solve(f::RHS{T, P}, u0::Vector{T}, p::P) where {T, P} = …
# Julia defines, where the method is defined:
#   solve(f::Union{Dynamic{<:RHS{T, P}}, Compiled{<:RHS{T, P}}}, u0::Vector{T}, p::P) where {T, P} = …       the method as written
#   solve(@nospecialize(f::RHS{T, P}), u0::Vector{T}, p::P) where {T, P} = solve(Dynamic{RHS{T, P}}(f), u0, p)   its forwarder
```

A trait **erases by default** when it declares `@default_dynamic` (§4.6). `Callable` erases by default (§9).

**A method at such a trait is defined at the two kept forms, and one forwarder takes a plain member and boxes it.** Julia makes both where the method is defined, as a positional default makes a second method:
- **the method as written** takes the argument at `Union{Dynamic{<:X}, Compiled{<:X}}`: a box and a wrapper reach it as they are;
- **its forwarder** takes a plain member at `X`, boxes it at `X`, and calls the method: `f(@nospecialize(t::X), …) = f(Dynamic{X}(t), …)`. It is less specific than the method as written, so a kept form never reaches it.
- So **in such a method the argument is a kept form, never the object** (§3.5). A method that asks a question of the object asks it of `unwrap(t)`, or before the value is boxed.
- Dispatch and the runtime are Julia's: the two are ordinary methods.

**Which arguments erase.**
- An argument typed by a trait that erases by default: `m::Model`, `f::Callable{Tuple{Float64}, Float64}`, `c::Column{T}` with `T` a variable of the method.
- **An argument whose trait the signature leaves open erases too** (`c::Column`, `c::Column{<:Real}`): the trait's default applies to anyone who writes a method. A member is in one instance of the trait (§3.2), so its membership fixes the open parameters. The forwarder takes them as variables of its own and boxes at the instance the member is in: a member of `Column{Float64}` is boxed as `Dynamic{Column{Float64}}` (§7.7). The method as written is compiled once per trait instance.
- An argument typed by an intersection with such a component. It is boxed at the intersection.
- An argument typed by a `where` variable bounded by such a trait: `x::C` with `C <: X`. `C` is then the kept form's type.
- **Not** a vararg of members (`ts::X...`, `ts::Vararg{X, 2}`): its elements are passed as they are, and the method is compiled per tuple of their types (§6.6).
- **Not** an argument whose open parameter is an input (§3.2): the member does not fix it, as a function's type fixes no signature (`f::Callable` written bare). There the argument takes a plain member as it is.
- **Not** an argument typed by a `where` variable that another argument names (a struct's own constructor, `T{F}(f::F)`): the call fixes the variable to the member's type, which the box is not. Nor a `Callable{A, S}` whose variables only that argument would bind: a function's type fixes none of them.

**The forwarder's shape.**
- One forwarder per positional arity that holds an argument that erases. Positional defaults make their arities, as in Julia.
- It is compiled once where one argument erases and the other arguments fix its trait's parameters; per member type where only the member fixes one (`ip::IndexProvider{I}`, `c::Column`), or where several arguments erase.
- Keyword arguments are passed on whole. A keyword typed by such a trait is boxed by the forwarder of the keyword method's body, whose positional arguments are the keywords.
- With several arguments that erase, the one forwarder boxes each plain one and passes a kept form as it is.
- The forwarders belong to the method: they are defined after it, and redefining or deleting the method redefines or deletes them. Reflection shows the method as written.
- **The trait's own methods are not forwarded:** a default (§4.2) is a method at the trait for every member. A plain member served by a default runs it as itself; a kept form reaches it as a member.
- **Julia's default constructors are methods like any:** a struct whose parameter is bounded by a trait that erases by default boxes a plain member at its default outer constructor (§8.2).
- **No type is exempt:** Julia's own types are boxed as a package's are (`abs2` given at a `Callable` argument).

**What it costs.** The forwarder makes a box at each call that passes a plain member. The box's membership test is decided when the code is compiled: the forwarder runs only where its signature matched, and the compiler decides a member's membership with an edge ([compiler §4.8](compiler.md#48-negatives-fold-with-an-edge-positives-through-entries), [§6.3](compiler.md#63-the-forwarders)). Where the box does not escape, it needs no heap of its own. A box made once and held costs less: a library that calls its trait's methods many times erases at its door, once (§7.10).

**Status:** Implemented, but for T-125 and [compiler C-111](compiler.md#deviations).

### 7.9 Operations on a value the code knows only by its trait

Where the code holds a value at the trait's type (a box's object, an argument declared `@nospecialize`, a field or element typed by the trait, an operation's result declared with the trait):
- **an operation's result is its declared result,** so the code after the call is typed. It is asserted, never converted: a member's result of another type raises a `TypeError`, as facts §2.1's "or raises" allows. A member checked at its membership (§5.10) returns it already, and keeps its check while it is a member, so the assertion only catches what the check does not reach: a result at an abstract further argument, a method already in the session when an image's membership loads, and inference's own limits. A dynamic call of the same operation, and the interpreter, return the member's own result;
- **the call branches on the first four members declared** of the trait, each a direct call that may be inlined. Any other member is called through a table keyed by its type: one lookup and one indirect call, whatever the number of members. The order is the declarations': a trait's package declares its common members first. At an intersection, the branches take the first component's members that are members of every component;
- a member declared later takes the table and invalidates nothing; code compiled after its declaration may branch on it if it is among the first four;
- a declared field read there works the same way.

**Status:** Implemented (gate `n22_declared_assert`).

### 7.10 Costs, and choosing

- **An operation on a member, or on a wrapper,** is a direct call of the member's method.
- **An operation on a box,** or on any value the code knows only by its trait, is a branch among the first four members, else one lookup and an indirect call (§7.9).
- **A call whose caller does not know the value's type** dispatches once on it, then runs the code for its type: a member's, a box's or a wrapper's. That is Julia's function barrier.
- **A plain member passed to a method of a trait that erases by default** is boxed at each call (§7.8). The box tests nothing when it runs, and where it does not escape it needs no heap of its own. A box made once and held costs nothing more per call.
- **Choosing:**
  - **Erase** for large code with many members behind it: a solver's models, a plot's marks. A member from outside compiles nothing in the library. Such a trait declares `@default_dynamic`, so a caller who knows nothing of it gets the box.
  - **Compile per type** for kernels, where the work per call pays for code per type: a trait without the default, or the wrapper. A caller of an erasing library who wants code for its type passes `compiled_for(x)`.
  - **A trait whose operation is a hot inner call** (a model's right-hand side) is erased once, at the library's door, and its operations are called on the held box; or the caller passes the wrapper.
  - A loop over a `Vector{Shape}` runs once; each item's type is unknown in it. An operation on an item takes §7.9's branches. Passing items to a method compiled per type pays a dispatch per item.
  - **A specialization belongs at a subtrait or in an operation,** where both forms reach it, not at a member's own type, which only `unwrap(t)` reaches (§7.4).
- The numbers: [the evidence, G-2](../design/evidence.md#2-run-time).

**Status:** Planned.

---

## 8. Storage

### 8.1 Fields and containers typed by a trait

```julia
mutable struct State
    const u::Vector{Float64}
    model::Model                     # any member: a plain one, a box or a wrapper
    hooks::Vector{Dynamic{Hook}}     # boxes: a plain member is boxed when stored
end
```

**Storage keeps the form it is given.** The choice is in the value's type, so storage needs no rule of its own:

| Storage | Holds | Read back |
|---|---|---|
| a struct parameter `F <: X` (§8.2) | the form it was given | that form, statically |
| `Vector{X}`, a field `::X`, a `Ref{X}` | each form by its own type: a plain member, a box, a wrapper | what was stored; a call on it dispatches by its type |
| `Vector{Dynamic{X}}`, a field `::Dynamic{X}` | boxes: a plain member, or a wrapper's object, is boxed when stored | a box, statically: code over it is fully typed; a wrapper's choice is erased there |
| the user's own `Vector{Circle}` | its members | erased by a copy, a lazy view, or a library type that names it |

- A field, element or `Ref` typed by a trait holds any member, boxed, as one typed by an abstract type does.
- **Assignment converts as Julia's does:** `convert(T, x)`, which is `x` for a member at a slot typed by the trait. At a slot typed `Dynamic{X}`, the library's `convert(::Type{Dynamic{X}}, x)` makes the box (§7.7): a box of `X` stays itself. A library that translates values defines `Base.convert(::Type{ColorSpec}, s::Symbol) = named_colour(s)`.
- **Julia converts no argument,** only what is assigned to a field or an element: hence the forwarder for arguments (§7.8), and `convert` for storage.
- **Erasing a user's container without a copy needs a view type:** Julia has no borrowed reference into an array's element.
- An operation on a value read back follows §7.9.

**Status:** Implemented.

### 8.2 A struct parameter bounded by a trait

```julia
struct ODEProblem{T, P, F <: Callable{RHSSig{P, T}, Nothing}}
    f::F
    u0::Vector{T}
    tspan::Tuple{Float64, Float64}
    p::P
end
ODEProblem(lorenz!, u0, tspan, p)                  # F = Dynamic{Callable{…}}: Callable erases by default
ODEProblem(compiled_for(lorenz!), u0, tspan, p)    # F = Compiled{typeof(lorenz!)}: code per function
```

- The bound is Julia's: a constructor checks it (`TypeError`), and the default constructor sets the parameter to the type of what it is given.
- **The parameter records the form:** a box's type, so code over the struct is compiled once per trait instance; a wrapper's or a plain member's, so it is compiled per type. A value read from the field has that type.
- **A trait that erases by default boxes a plain member at a constructor with an argument at the trait,** Julia's default outer constructor included (§7.8). The constructor with the type's parameters written (`ODEProblem{T, P, F}(…)`) stores what it is given, converted to `F`.
- **A record made before a signature is known keeps each value in the form given:** `ODEFunction(f; jac = compiled_for(j))` holds a plain `f` and a wrapped `j`. The constructor that knows the signature boxes `f` and keeps `j`.
- **A parameter named only in a bound** is matched through the membership, as a `where` clause matches: in `struct CellVector{T, C <: Column{T}} <: AbstractVector{T}; c::C; end`, the constructor `CellVector(c::C) where {T, C <: Column{T}} = CellVector{T, C}(c)` reads `T` from the column's membership.
- **A constructor that sets the parameter from its trait argument is bounded** (§7.3): at a box it stores the box, and the struct's type names the box's type.

**Status:** Implemented, but for T-125.

### 8.3 Equality

`Dynamic{X}(a) == Dynamic{Y}(b)` when `a === b`, for a mutable object by identity, for an immutable one by value; `compiled_for(a) == compiled_for(b)` likewise; `hash` agrees. `===` compares the kept forms.

**Status:** Implemented.

---

## 9. Functions: `Callable`

```julia
colmap(f::Callable{Tuple{Float64}, Float64}, t::ColTable, i::Int) = map(f, col(t, i))
both(f::All{Callable{Tuple{Float64}, Float64}, Callable{Tuple{Int}, Int}}, x::Float64, n::Int) = (f(x), f(n))
byrow(f::Callable{Tuple{T}}, c::Column{T}) where {T} = …     # result type, where needed: Base.promote_op(f, T)
retain!(f::Callable{Tuple{T}, Bool}, xs::Iterable{T}) where {T} = …   # T bound by xs

colmap(x -> 2x, m, 1)                     # boxed: Dynamic{Callable{Tuple{Float64}, Float64}}, compiled once
colmap(compiled_for(x -> 2x), m, 1)       # the wrapper: compiled for the function
colmap(uppercase, m, 1)                   # MethodError where the function is boxed: no method of uppercase at (Float64,)
```

**`Callable{A, S}` is the trait of functions called with arguments of the tuple type `A` and returning an `S`.** It is Julia's own, as Rust's `Fn` traits are the compiler's own. Its contract is checked at the box, not in the type system:
- **Every function is a member of every `Callable{A, S}`:** a value of a subtype of `Function`, and a value of a callable type declared a member (`@implement Callable MyCallable`, for a callable struct that is no `Function`). Julia's builtins (`getfield`, `isa`) are the exception: their types are members of no set ([compiler §4.1](compiler.md#41-sets)). Subtyping reads no method: membership is declared, as for any trait.
- **The signature is checked where the function is boxed or enters.** A plain function given at `Callable{A, S}` is boxed (`Callable` erases by default, §7.8), and the box is made only for a function with a method at `A`: otherwise it raises the `MethodError` a call at `A` would, with a hint that names the declaration and the function's methods near `A`. So the error is at the call that passes the function. A wrapper is checked at the entry of the method that takes it, by the same test.
- **The result is asserted to `S` on return,** at every call of a box, however it is called: its own argument, a copy, a capture, a splat. A call at arguments outside `A` raises `MethodError`; a result outside `S` raises `TypeError`, naming the declared and the returned type; where `S` is `Nothing`, the message adds: end the function with `nothing`.
- **A function kept as itself and known only by the signature** (an element of a `Vector{Callable{A, S}}`, which holds each function in the form given) is called as a box is: arguments outside `A` raise `MethodError`, and the result is asserted to `S`. Passed on to a function compiled for its own type (`all(t -> t(x), tests)`), it is that function's argument and called as its own; the call that passes it is asserted to the result inferred at the signature. Where the declared result is `Bool`, Julia prints the `TypeError` as "non-boolean (T) used in boolean context".
- **A wrapper is the function:** passed with `compiled_for(f)`, it is checked at entry: a method at `A`, and a result inferred at `A` that can be an `S` (else the `TypeError` a call would raise). Its calls are the function's own, compiled for its type; their results are not asserted to `S` ([GT-24](../goals.md#3-tensions-between-the-goals)).
- **Neither `A` nor `S` selects a method.** Two methods at `Callable` instances that differ only there are ambiguous for every function: dispatch does not pick by a function's signature. A method that branches on it tests `hasmethod(f, A)` in its body.
- **A struct parameter bounded by `Callable{A, S}` holds every function:** the bound checks no signature. The constructor with a `Callable` argument checks it, by its box or its entry (§8.2).
- **A `where` variable that only `A` or `S` names is not bound by a call,** as Julia's `detect_unbound_args` reports. Another argument binds it (`retain!`, `byrow` above), or code computes the result type as a value, `Base.promote_op(f, T)`, as `map` does ([facts §7](facts.md#7-return_type-and-reflection)).
- **Its default erases:** a plain function is boxed, so code is compiled once per signature, not per function, Julia's own functions included (§7.8). `compiled_for(f)` compiles it for the function.
  - Where the method leaves `A` or `S` open (`byrow` above, `f::Callable` written bare), there is no signature to box at: the function is taken as it is, and the method is compiled per function (§7.8). A method that should be compiled once writes both.
- **Several signatures** are an intersection: a box of `All{Callable{A, S}, Callable{B, R}}` is made for a function with methods at both, and a call picks the signature its argument types match.
- **Argument types may follow other arguments:** `retain!(f::Callable{Tuple{T}, Bool}, xs::Iterable{T}) where {T}`; the box is made at the signature the other arguments give.
- `Callable` without parameters is every function; a box needs a signature (§7.7).
- **Keywords:** `Callable{A, S, K}`, `K` a named-tuple type (Planned).
- A closure with a trait argument, `(u::ColTable) -> …`, is a method at the trait.
- **Passing `f` on to a higher-order function,** `map(f, xs)`, passes the box: a call at a concrete signature, whose code is compiled once for the box. `colmap` above is bounded (§7.3).

**Status:** Implemented, but for T-156, [compiler C-146](compiler.md#deviations) and [lowering L-58](lowering.md#15-deviations); keywords (`Callable{A, S, K}`): Planned.

---

## 9b. Streams: `IO`

```julia
report(io::IO, t::ColTable) = for c in columns(t); println(io, name(c), ": ", mean(c)); end
report(stdout, t)                         # compiled for the REPL's stream type, as in Julia

function Base.show(@nospecialize(io::IO), t::Table)    # a display entry that serves every stream
    io = IOContext{IO}(io)                # one compiled body, whatever the stream
    render(io, t)
end
```

**`IO` is Julia's closed abstract type, with a contract** (§3.4).
- **Its members are Julia's streams and every `struct S <: IO`,** as in Julia. Code typed `io::IO` is compiled per stream type, as in Julia.
- **The contract's operations,** each Base's method at `::IO`: `write(io, ::UInt8)`, `unsafe_write(io, ::Ptr{UInt8}, ::UInt)`, `read(io, ::Type{UInt8})`, `unsafe_read(io, ::Ptr{UInt8}, ::UInt)`, `flush(io)`, `lock(io)`, `unlock(io)`, `get(io, key, default)`, `haskey(io, key)`. Each result is `Any` (§3.4). `eof`, `isopen` and `close` have no method at `::IO` and are not operations.
- **The split's candidates:** `IOBuffer`, `IOStream`, `TTY`, `PipeEndpoint`.
- **At a value typed `IO`** (a field typed `IO`, an element of a `Vector{IO}`, an argument declared `@nospecialize`), an operation's call branches over the candidates with direct calls, and goes through the table past them (§7.9; [compiler §7.5](compiler.md#75-io)). It returns what the stream's own method returns, as a dynamic call and the interpreter do: Core's streams and `Filesystem.File` return a `UInt` count, `IOBuffer` an `Int`.
- **The erased stream is `IOContext{IO}`:** `IOContext{IO}(io)` and `IOContext{IO}(io, key => value, …)` hold any stream as an `IO`. It is an `IO`, so code typed `io::IO` takes it. It forwards every stream function, as any `IOContext` does, and its operations on the stream it holds branch over the candidates. An `IOContext`'s properties (`:compact`, `:limit`, `:color`) reach `show` through it. `IOContext(io, …)` keeps the stream's type, for code per type.
- **The display erases the stream:** the REPL's display (`show_limited`) and Base's `TextDisplay` pass `IOContext{IO}(io)` to `show`, so every value's display at the REPL or a text display runs at one stream type. A package's display methods stay plain code, and its image's workload covers that display by displaying once at `IOContext{IO}(IOBuffer())`. A method of `show` there sees `IOContext{IO}`, not the REPL's stream type; the stream's properties (`:limit`, `:color`, `:displaysize`) pass through.
- **Erasing elsewhere is the author's choice,** where large code serves many streams outside a display (§7.10): the entry declares `@nospecialize(io::IO)` and passes `IOContext{IO}(io)` on, so one compiled body serves every stream, and a workload at the erased type covers them all. Small code that writes a byte or a short string per call stays per type.

**Status:** Implemented.

---

## 10. Collections

### 10.1 BaseTraits

```julia
mean(xs::All{Iterable{Float64}, HasLength}) = (s = 0.0; for x in xs; s += x; end; s / length(xs))
mean([1.0, 2.0, 6.0])
```

BaseTraits is the library's standard set of traits for the concepts Base defines informally, each with its item types as associated types. Its traits are ordinary traits; the language depends on none.

| Trait | Operations | Associated types | Base's members |
|---|---|---|---|
| `HasLength` | `length(c)::Int`, expected in constant time | — | `AbstractArray`, `AbstractDict`, `AbstractSet` |
| `Iterable{T}` | `iterate(c)`, `iterate(c, state)`, each `::Union{Nothing, Tuple{T, Any}}`; iteration repeats and leaves `c` unchanged | `T = eltype(Self)` | `AbstractArray`, `AbstractDict` (items `Pair{K, V}`), `AbstractSet`, `AbstractString` (items `Char`) |
| `Indexable{T} <: HasLength` | `c[i::Int]::T`, `firstindex(c)::Int`; positions `firstindex(c)` to `firstindex(c) + length(c) - 1` | `T = eltype(Self)` | `AbstractVector` |
| `MutableIndexable{T} <: Indexable{T}` | `setindex!(c, x::T, i::Int)::Any`, written `c[i] = x`, which keeps the length and reads back `x` at `i` | `T = eltype(Self)` | `Vector`, `BitVector`, a view of a member (`SubArray{T, 1, P} where {P <: MutableIndexable{T}}`) |
| `Resizable{T} <: HasLength` | `push!(c, x::T)::Any`, an item at the end; `resize!(c, n::Int)::Any` for `n ≤ length(c)`, the first `n` kept | `T = eltype(Self)` | `Vector`, `BitVector` |
| `Keyed{K, V} <: HasLength` | `d[k::K]::V`, `haskey(d, k::K)::Bool`, `get(d, k::K, default::D)::Union{V, D} where {D}` | `K = keytype(Self)`, `V = valtype(Self)` | `AbstractDict` |
| `HasProperty{N, R}` (`N` an input) | `x.N`, of type `R`: `getproperty` at the constant name `N`, served by a stored field or the member's own `getproperty`; on a value known only by its trait, `x.N` has the declared type, as a declared field's read (§7.9). Declared as a field named by its input, `@const N::R` (§4.3) | — | none; a type joins at each name |
| `Solvable{T}` | `ldiv!(x::AbstractVector{T}, F, b::AbstractVector{T})::AbstractVector{T}`: `x` solves `F x = b` | `T = eltype(Self)` | LinearAlgebra's factorizations that solve (`LU`, `Cholesky`, `CholeskyPivoted`, the `QR`s, `LQ`, `BunchKaufman`, `LDLt`, `SVD`), and `Diagonal`, `UpperTriangular`, `LowerTriangular`, `Bidiagonal` |
| `LinearOp{T}` | `size(A)::Tuple{Int, Int}`, `apply!(y::AbstractVector{T}, A, x::AbstractVector{T})::AbstractVector{T}`: `y` becomes `A x` | `T = eltype(Self)` | `AbstractMatrix`, by `mul!` |
| `BoundedText` | `textbound(x)::Int`, an upper bound on the bytes `print(io, x)` writes; `textbound(T)` for a type, an `Int` or `nothing` | — | `Number`, `AbstractChar`, `AbstractString`, `Symbol`, Dates' `TimeType`, `Period`, `CompoundPeriod` |

- **Base's types join as Base's abstract types,** declared in BaseTraits, which owns the traits: `@implement Indexable{T} AbstractVector{T} where {T}`. A type is a member only where declared: a `Number` iterates in Base but is not `Iterable`, and a string is `Iterable` but not `HasLength` (its `length` is not constant time).
- **A contract states what a membership's check cannot verify:** `length`'s value, that iteration repeats, that a write reads back, the vectors a solver accepts (LinearAlgebra's factorizations take one-based vectors in host memory, views included). The check verifies the operations and their result types. Trait code does not index without bounds checks on a member's `length` alone, and code that preallocates by `textbound` still checks what `print` wrote.
- **Positions start at the member's `firstindex`:** a vector with offset axes is an `Indexable`.
- **The operations use Base's and LinearAlgebra's functions** (`length`, `iterate`, `getindex`, `ldiv!`) where a member's own methods serve them and no untyped method of the function would be hidden (§5.10). `LinearOp`'s `apply!` is BaseTraits' own: a method of `mul!` at the trait would hide `mul!`'s untyped fallback for every matrix. A member with its own `mul!` joins with a block: `apply!(y, A, x) = mul!(y, A, x)`. A matrix-free member defines `eltype`.
- **`BoundedText` is a constant per type where the width is fixed** (machine integers, `Bool`, the IEEE floats, characters, dates, `Rational` and `Complex` of those) and a value's own bound otherwise (a `BigInt`, a string's code units, a `Symbol`'s bytes; four bytes a character for a string other than `String`). `textbound(T)` lets a writer size a column without visiting its cells.
- `asvector(x::Indexable{T})` is the collection as a read-only `AbstractVector{T}` for plain code, positions `1:length(x)`, without a copy, each read's bounds checked by the member: `IndexableVector{T, C}`. It is an unbounded method (§7.3).
- `HasLength` is not `Base.HasLength`, the value of `Base.IteratorSize`.
- A module that uses BaseTraits and another module exporting the same name gets Julia's usual ambiguity of names.

**Status:** Implemented (tests `basetraits.jl`).

### 10.2 Element types

- **A collection's item type is its trait parameter, invariant:**
  - `Iterable{Shape}` is an iterable whose item type is exactly `Shape`: a `Vector{Shape}`;
  - `Iterable{<:Shape}` is one whose item type is any subtype of `Shape`: a `Vector{Circle}`, a `Vector{Shape}`, a `Vector{Dynamic{Shape}}`, a `Vector{Union{Circle, Square}}`.
- **A `Vector{Any}` is not an `Iterable{<:Shape}`.** Convert it first: `convert(Vector{Shape}, v)` checks each item and raises at the first that is not a member.
- **Items:** a `Vector{Circle}`'s items are of a known type, so calls on them are compiled for it. A `Vector{Shape}`'s items are plain values the code knows only by the trait: §7.9 for operations, §7.5 for calls.
- **Writes** store the value, as `setindex!` does; a value of the wrong type fails as in Julia.
- **An array literal's element type** is Julia's join, which reads declared supertypes only. `[Circle(1.0), Square(2.0)]` is a `Vector{Shape}` where both types are defined `<: Shape` (§5.2), and a `Vector{Any}` where they joined by `@implement` alone.

```julia
total(shapes::Iterable{<:Shape}) = (s = 0.0; for x in shapes; s += area(x); end; s)
total([Circle(1.0), Square(2.0)])         # members by @implement alone: a Vector{Any}, MethodError
total(Shape[Circle(1.0), Square(2.0)])    # a Vector{Shape}
```

**Status:** Implemented (tests `basetraits.jl`).

### 10.3 Algorithms

- `retain!(f::Callable{Tuple{T}, Bool}, xs::All{MutableIndexable{T}, Resizable{T}}) where {T}` keeps the items for which `f` is `true`, in place, in order. It is Base's `filter!` for trait code. `Callable` erases by default, so a plain function is boxed: `retain!` is compiled once per item type for every function, Julia's included (§7.8). `retain!(compiled_for(f), xs)` compiles it for the function.
- BaseTraits' algorithms have names of their own: a method of Base's `filter!` at a trait would rank below Base's own methods (§6.2) and never run for Base's containers.

**Status:** Implemented.

---

## 11. Checks and errors

### 11.1 When checks run

| When | What is checked | Error |
|---|---|---|
| `@trait` | the body's form: result types present, one receiver per operation, no parameter defined twice | an error at the macro, naming the line |
| `@implement` for one type | ownership, completeness, results, fields, parameters, concreteness, supertraits (§5.10) | `ImplementError`; ownership `OwnershipError` |
| a member's first use (a family's, an abstract type's or a trait's member) | as at `@implement` | `ImplementError`, at that use and every later one |
| a use before, or a module's end | a `struct S <: X` without `@implement X S` | `ImplementError` |
| a method's definition | a method that would take a call a default or the forwarding serves at a member (§5.11); one that would serve a member's checked call with a result outside the declared one, or make the operation ambiguous at the member (§5.10); a pirate in a scope that refuses them (§12.2); a method that is not bounded, in a scope that declares `bounded` (§7.3) | `ImplementError`, `OwnershipError`, `TraitUseError` |
| an image's load | an image's method that the rules of a method's definition (§5.10, §5.11) refuse | a warning; the method is left inactive |
| a method's definition, strict mode | a pirate that would win at a fact of code compiled by facts (§12.3) | `PirateError` |
| a membership, strict mode | a pirate's membership that would change code compiled by facts (§12.3) | `PirateError` |
| a membership | a type made a member of two traits whose methods are ambiguous for it (§6.3) | a warning; under strict mode `ImplementError`, and the membership does not exist |
| a call | Julia's dispatch: no method, or ambiguous | `MethodError` |
| a member's call of an operation | a call that no method of the member takes, outside the operation's declared signature | `MethodError`, with the declared signature as a hint (§11.4) |
| a call through the trait | an operation's result against its declared type (§7.9); a box of a `Callable`: its arguments and result (§9) | `TypeError`, `MethodError` (a `Callable`'s arguments) |
| a keyword typed by a trait | membership | `TypeError` |

**Status:** Implemented.

### 11.2 Definition checking

- **Each method at a trait is checked once for every member that will ever join,** by reading its instance at the box (§7.3). That instance is Julia's own inference of the code a box runs, done where the method is defined: the check costs the compile the box's first call needs. In a scope that declares `bounded` a fault refuses the method.
- **While a package is precompiled,** a `TraitUseError` fails the build. **At the prompt or in a script** it is raised at the definition.
- `check_definitions(M)` runs it on demand: an empty list, or `TraitUseError` listing every fault of every method.
- It reports each fault, not only the first.
- **An edit defines the method again:** its instance at the box is inferred once, as its next call would infer it. Nothing else is inferred again.

```julia
spread(t::ColTable) = size(t)    # size(::Dynamic{ColTable}) has no method: not bounded
leak(t::ColTable) = typeof(t)    # bounded: the box's type
```

**Status:** Implemented, but for [compiler C-115](compiler.md#deviations).

### 11.3 Errors and their messages

Each message names the trait, the type, and the declared signature where one is involved.

| Error | Raised for | The message names |
|---|---|---|
| `ImplementError` | a membership that fails its check, or that strict mode refuses for an ambiguity (§6.3); a method that would break a member's check (§5.10, §5.11) | each missing operation with its declared signature at the type, and the type's methods of that function that do not cover it, with the argument that differs; each result that infers wider than the declared one or outside it, with both types; each field missing, mistyped or not writable; each parameter that disagrees, with its source; an override; the path that gives a second instance. For a method refused at its definition (§5.10, §5.11): the method, the member, the operation, the declared and the inferred result or the method it would be ambiguous with, and the fixes |
| `OwnershipError` | a method, or a membership, by a package that owns none of what it names, in a scope that declares `no_pirates`; a block's method for a foreign function and type | the method or membership, its owners, and who may declare it |
| `TraitUseError` | a method that is not bounded, in a `bounded` scope | each fault: the call, what it reaches, and the line of the method that passes the value |
| `PirateError` | strict mode | the method, or the pirate's membership, and the code compiled by facts it would change |
| `MethodError` | a call no method takes, or two take ambiguously; a member's call of an operation outside its declared signature (`scale(c, 2)` for `scale(s::Scalable, k::Float64)`) | Julia's message: the call at its argument types and the member's own methods of the function; with hints (§11.4): for an operation, its declared signature and its trait |
| `TypeError` | an operation's result that is not its declared type (§7.9), or a `Callable`'s result that is not its declared type; a keyword that is not a member; a struct parameter outside its bound | the operation or function, the declared and the returned type |
| `NotFullyTypedError` | code under `@enforce_fully_typed` with a call it cannot resolve when compiled (§14) | each such call, at the types inference knows, and its root cause |
| `AbstractTypeError` | a method under `@enforce_concrete_only result` whose result is not concrete (§14) | the result's type and its root cause |

**The form of a message.**
- A signature prints as a call, `tag(::Named)`. The compiler's tuple type, `Tuple{typeof(tag), Named}`, appears in no message.
- A method refused at its definition is headed as a refused method. It says that the type stays a member, and gives the fix last.
- A fault names what is used: a field by its name, a call by what it reaches.
- The code a declaration makes lies at the declaration: the place of a candidate and a stack frame name the user's `@trait`, not the library's source.
- **A check's error is raised at the user's line.** The first frame of its backtrace is the `@implement`, or the method's definition that a check refused. The library's own frames are not above it.

**Status:** Implemented (`test/messages.jl`).

### 11.4 Hints

The library adds hints to Julia's `MethodError` where a trait is involved:
- **a value that is not a member** of a trait a method takes: "`Circle` is not a member of `ColTable`; `@implement ColTable Circle` declares it", with the trait's declared members where few;
- **a member at other parameter values:** "`v` is a member of `StateVector{Float32}`; the method takes `StateVector{Float64}`";
- **a broken shared variable:** "`T` is `Float64` for `a` and `Float32` for `b`";
- **a call at an operation's function outside its declared signature:** the declared signature and its trait, read from the contract, "`col` is declared `col(t::ColTable, i::Int)::Vector{Float64}` by `ColTable`". It is given where an argument at the operation's receiver position is a member of the trait, so a failed call names the contract it missed;
- **an ambiguity between two traits:** the joint method to define, `f(::All{ColTable, RowTable})`.

**No hint at an operation that is another owner's function.** `Indexable` declares Base's `getindex` as its operation. A failed call of `getindex` says nothing of `Indexable`: the hint is given at an operation whose function the trait's owner owns.

**Status:** Implemented, but for T-99.

---

## 12. Ownership, pirates, strict mode

### 12.1 Who may declare a membership

- A package **owns** the functions and types it defines, traits included. Julia (Core, Base, the standard libraries) is one owner. A package extension counts as its parent.
- **At the prompt,** `Main` is one owner, and each module defined directly under `Main` is an owner of its own.
- **A membership is declared by the trait's owner or the type's owner.** A membership by a package that owns neither is a pirate's (§12.2).
- A membership for a foreign trait and a foreign type belongs in the trait owner's package extension. **A membership in a package extension names each of the extension's triggers** (each owns the trait or a type the declaration names); otherwise whether a type is a member would depend on which packages happen to be loaded. It is refused with `ImplementError`.
- **An operation that is an existing function** (`Base.size`) may be served by methods in a block only for types the declaring package owns. Otherwise declare the type's existing methods: `@implement Sized Vector{Float32}`.
- **Joint owners:** a package may name packages that own its functions and types with it (`@joint_owners DiffEqBase OrdinaryDiffEqCore`, at the top level of its own module). They are owners wherever the declaring package is one: memberships, pirates, strict mode's stakeholders. Not symmetric, not transitive; a joint owner's extension is a joint owner too. A joint owner's change is a stakeholder's change ([facts §2.2](facts.md#22-g2-stable-caches)).

**Status:** Implemented (tests `ownership.jl`); whether the standard libraries are owners of their own: Open ([open issue 19](../open-issues.md)).

### 12.2 Pirates

- **A membership of a trait you do not own, for a type you do not own, is a pirate's too, and behaves as a pirate's method.** It is followed, with a warning that names the owners, and the code that relied on its absence is compiled again. A scope that declares `no_pirates` refuses it (`OwnershipError`). Under strict mode it is refused where it would change code compiled by facts (§12.3). At the prompt, `@implement` of a package's trait for a package's type is such a membership.
- A **pirate** is a method of a function you do not own, for types you do not own: Julia's type piracy. A trait you own is a type you own; a `Union` with your own type or a lower-bounded type variable is no way around it.
- **A method of another package's owner-only function is a pirate's, whatever types it names.** An owner-only function's methods are its owner's ([facts §1](facts.md#term-owner-only)):
  - by default, each function of a trait module that the module neither exports nor declares `public`: `@trait_module` turns on the module's option `owner_only` (`@trait_module owner_only = false` turns it off); a module that declares only `facts` has it off;
  - by declaration, any function of the owner's module, exported or not: `@owner_only f g`, at the module's top level.
  - So code compiled by facts infers every call of such a function as plain Julia does ([facts §3](facts.md#3-fact-signatures)): its owner is the only one who changes where the call goes.
  - To let other packages extend a function, its owner declares it `public` or exports it, or names them as joint owners (§12.1). Base's internal functions are not owner-only, nor those of a module that declares only `facts`: packages extend them.
- **A scope that declares `no_pirates`** refuses one at its definition (`OwnershipError`).
- Elsewhere a pirate is followed, as in Julia; code compiled by facts that it changes is compiled again once ([facts §11](facts.md#11-pirates-and-strict-mode)).
- **A pirate is reported where it ends deep-G2 code** ([facts §1](facts.md#term-deep-g2), [§2.2](facts.md#22-g2-stable-caches); [compiler §3.2](compiler.md#32-g2-as-a-predicate)): code that nothing but a stakeholder's change or a pirate can end. A warning names the method, its definer, who owns neither the function nor a type in it, and the code compiled by facts it ended. So every pirate that costs such code is told, and no other:
  - **reported**, by default: when its definition ends such code, and when an image's code that its method makes invalid at the image's load is such code;
  - **refused**, in strict mode (§12.3), where it would win at a fact;
  - **silent** only by choice: `TraitWorld.report_pirates!(false)`, or `JULIA_TW_PIRATES=0` at start.
  - The report costs nothing where no such code ends: the invalidation that ends the code holds the method already. A pirate's membership is reported the same way, beside its warning at the declaration.

**Status:** Implemented.

### 12.3 Strict mode

```julia
TraitWorld.strict!(true)        # or start Julia with JULIA_TW_STRICT=1
```

- **It applies to code compiled by facts.** The property it secures: such code is invalidated only by a change of code it depends on, a stakeholder's ([facts §11](facts.md#11-pirates-and-strict-mode)).
- It refuses a pirate when it would win at a call that code compiled by facts makes, with `PirateError`, naming the method and the code. The method then does not exist, for any code.
- A pirate that wins nowhere in code compiled by facts is accepted. A stakeholder's definition is followed.
- A method belongs to the module it is evaluated in.
- A pirate loaded before the code it changes is reported when that code's image loads.
- A package extension's method that wins at a fact without naming its triggers' types is followed, as its parent's change, with a warning.
- **A pirate's membership (§12.2) is refused where it would change code compiled by facts,** with `PirateError`, naming the membership and the code. That is where such code folded that the type is no member, or calls a function at the type where a method at the trait would be selected. The membership then does not exist.
  - One that changes no such code is accepted, with the warning.
  - In a package image it is refused at the image's load, with a report at error level.
- An ambiguity at a membership (§6.3) is an error: the membership raises `ImplementError` and does not exist. An image's membership activated at load that meets an ambiguity with code loaded earlier is reported, as a pirate loaded earlier is.
- A method loaded before an image that breaks the check of one of the image's memberships (§5.10) is reported when the image loads, as a pirate loaded earlier is: the check instance it ends fails validation and is inferred again. Only such instances are inferred.

**Status:** Implemented, but for T-96 and T-112; only the check instances that fail validation inferred again at a load: Planned, with T-129.

---

## 13. Scopes: trait modules

```julia
module Geometry
using TraitWorld
@trait_module                     # facts, bounded, no_pirates, owner_only
@trait Shape begin … end
area_sum(shapes::Iterable{<:Shape}) = …
end
```

- **`@trait_module`, before the module's first method,** declares options for every method of the module, its submodules included:
  - **`facts`:** its methods are compiled by facts ([facts §6](facts.md#6-which-code-is-compiled-how));
  - **`bounded`:** an unbounded method at a trait argument is refused (§7.3);
  - **`no_pirates`:** a pirate is refused (§12.2);
  - **`owner_only`:** each function of the module that it neither exports nor declares `public` is owner-only (§12.2).
- Each is on unless written otherwise (`@trait_module bounded = false`).
- **No option decides how a trait argument is compiled:** the value's type does (§7.5).
- A method may set an option for itself: `@bounded f(…) = …`, `@facts f(…) = …`; `@unbounded f(…) = …` exempts it from `bounded` (§7.3).
- The module's statements are Julia's; nothing is rewritten. Revise and other tools that read a module by its statements see an ordinary module.
- At the module's end, methods whose check waited for later definitions are checked (§7.3).
- Concreteness and fully typed mode (§14) take the same places: before `@trait_module`, for the module; before a method, for it.
- Traits, memberships and methods at traits work in any module; a scope decides only these options.

**Status:** Implemented.

---

## 14. Concreteness and fully typed mode

```julia
@trait KVec{T} begin
    @enforce_concrete_only T Self
    T = eltype(Self)
    klen(v::KVec)::Int
    kget(v::KVec{T}, i::Int)::T
end
@enforce_concrete_only T v total(v::KVec{T}) where {T} = …
@enforce_fully_typed @trait_module
fully_typed(colmean, (Vector{Vector{Float64}}, Int))
```

Two guarantees, asked for separately.

**Concrete parts** are a property of a membership or a call: the receiver type and the named parameters are concrete. Then the member's compiled code reads the receiver and calls on values typed by those parameters directly, never dispatching when it runs.
- **Concrete** means a concrete type, or a `Union` of at most four concrete types, whose parameters are concrete in the same sense. A parameter value that is not a type is concrete. A `Dynamic{X}` is concrete. A trait with a contract as a parameter's value counts as concrete: its operations have declared results, so code over it is typed.
- **Per trait:** `@enforce_concrete_only names…` refuses a membership where a named part is not concrete (`ImplementError`); `@warn_on_abstract names…` warns. The names are the trait's parameters and `Self`; without names, all of them. A trait's declaration applies at every membership of it and of its subtraits. Checked at the declaration, or at the member's first use.
- **Per method:** `@enforce_concrete_only names…` before a method refuses a call where a named part is not concrete; `@warn_on_abstract` warns once per method and type. The names are the method's `where` variables that traits fix, and trait arguments, each standing for its `Self`. For a plain member and a wrapper the answer is decided where the call is compiled; for a box, `Self` is not checked.

**Fully typed code** is a property of a method at the signature it runs at, in a setting: every call in it, and in what it calls, is **settled** there. A settled call is one whose target no later definition can change, but a stakeholder's or a pirate's ([facts §3](facts.md#3-fact-signatures), "What is final").
- **Fully typed when closed:** every call is one a closed build resolves, by the argument types or by the traits' members. This is what the modes and a build ask (below).
- **Fully typed in a session:** every call is at a fact signature, so nothing is dispatched when it runs. Code fully typed in a session is fully typed when closed.
- A call that only a build resolves (a value typed `Any` passed to a function with one method that is not owner-only) is fully typed when closed, and is dispatched when it runs in a session. So is an operation called at a value typed `Any` (an element of a `Vector{Any}`): a build branches over the operation's methods, the members' and the kept forms'; a session leaves the call, or the kept forms' part of it, to dispatch when it runs.
- Code whose calls all have known argument types pays nothing for the facts mode.
- `@warn_not_fully_typed` warns at a method's first run at a signature; `@enforce_fully_typed` raises there, at every run, `NotFullyTypedError`: the code has a call it cannot resolve when compiled, in it or in what it calls. A method in either mode is compiled by facts. Fully typed code pays nothing for either.
- `fully_typed(f, argtypes)` reports the calls that are not fully typed when closed, with their root cause through any number of layers, in the trait's terms ("field `data` of `HasData` is declared `AbstractVector`"). It lists apart the calls a build resolves and a session leaves to run time. `isfullytyped(report)` answers for a closed build; `isfullytyped(report; session = true)` for a session too.
- **The report is the closed build's own check,** run in the session ([compiler §2.7](compiler.md#27-fully-typed-mode)): the calls it lists are those a build from that signature refuses. It counts the members a build counts (§16): a value known only by its trait that is passed to a method at the trait, or wrapped with `compiled_for`, is resolved by the members and is no fault. A call inside Base that the build refuses is listed at the call in the user's code that leads to it, with the root cause there.
- **Operations on a value the code knows only by its trait count as declared,** not as faults (§7.9).
- **A result of an abstract type is no fault.** A type is a fault where it is used: a call on such a result is a call the caller cannot resolve, and the report of the caller names the result as its root cause. A method that wants a concrete result asks for it: `@enforce_concrete_only result` before the method raises `AbstractTypeError` at a signature whose result is not concrete.
- **Fully typed code is exactly the code that compiles ahead** (§16). A method that is fully typed at a signature builds in a closed build from that signature, with no call left to run time. A method that is not is refused by the build, at the calls `fully_typed` reports. So the check in a session answers for the build, and the build's report is `fully_typed`'s.
- **The modes raise where a build would refuse.** `@enforce_fully_typed` and `@warn_not_fully_typed` ask the same check: code with a call that a session leaves to run time and a build resolves by the members runs without a fault.

**They differ.** Concrete parts do not make code fully typed (a `Vector{Any}` argument, an abstract declared result can each leave a call unresolved). Fully typed code is checked at the signatures it ran at; concrete parts are promised for every member.

**Status:** Implemented, but for T-100, T-101, T-104, T-109 and T-122 (gate `n9_fully_typed`).

---

## 15. Printing

- **A box** prints as `Dynamic{Shape}(Circle(1.0))`, **a wrapper** as `Compiled(Circle(1.0))`. A signature prints the kept form's type, as Julia prints any type: `colmean(::Dynamic{ColTable}, ::Int64)`.
- A trait prints as the type it is.

**Status:** Implemented.

---

## 16. Compiling ahead, closed programs

- **While a package that declares `@implement X T` is precompiled,** the code that `T` needs is compiled into that package's image. That covers every method at `X` and its supertraits with one trait argument that does not erase, bounded there, at `T`'s type, where the other arguments are concrete. Their checks run then; a failing check fails the build.
- A method with several trait arguments is compiled at its first call.
- **A method at a trait that erases by default** runs one instance for every member, at the box. It is compiled where the method is defined, by its definition-time check (§11.2), and kept in that package's image. A member's package compiles nothing of it.
- Compiling ahead adds no method, so it invalidates nothing.
- **A closed build compiles generic code for the members it has,** as Rust and Mojo do with a trait bound. A session keeps the set of members open, so code compiled once for a box reaches a member through a call that is resolved when it runs (§7.9). A build under `juliac --trim` has every member, and every method: nothing joins or is defined later ([compiler §7.6](compiler.md#76-a-closed-build)). So:
  - **A build compiles what is written,** as a session does: a plain member at a method of a trait that erases by default is boxed, a box's code is compiled once per trait instance, a wrapper's for its object's type.
  - **An operation on a value known only by its trait** (an item of a `Vector{Shape}`, a `Dynamic{Shape}`) branches over every member the program uses, not the first four, each branch a direct call. Past them it raises `MethodError`.
  - **An operation on a trait with no member** raises `MethodError`, as a call no method takes. So a library's code that calls a trait's operations builds in a program that has no member of the trait.
  - **A call at an abstract type that one method takes** runs that method, as Julia infers such a call: the methods are final.
  - **A call in the latest world is the call:** `invokelatest(f, args…)` is `f(args…)` (Planned, below).
- **The members a program uses.** A build counts the members it compiles for:
  - a type declared a member by its own membership is a member;
  - the members of a family (`@implement Column{T} Vector{T} where {T}`) and of an abstract type (`@implement Sequence AbstractVector{Float64}`) are the types the program hands to the trait: those it stores, passes, returns or asserts where only the trait is known, or keeps at a place typed by an abstract type or a family and then passes on to such a place;
  - a type that one declaration makes a member of every instance (`@implement Callable T`, and every function at `Callable`) is counted at each instance the same way;
  - a box is counted where the program keeps one at a place typed by the trait;
  - a place typed by a type that merely is a member counts for no trait. Every function is a member of every `Callable{A, S}`, so a field `f::Function` counts for a signature once the code passes its value on to a place typed by that signature. A trait's members in a build are the types the program hands to it, not every member the program has.
  - `JULIA_CLOSED_BUILD_REPORT=1` makes the build list each trait's members and where each was counted.
  - **A value of a type the build did not count** raises `MethodError` at the branch: the answer is Julia's or an error. Which values a build does not count: [compiler C-86](compiler.md#deviations).
- **Calls at a value known only by its trait.** A build leaves none of them to dispatch when the program runs:
  - **`compiled_for(x)`** branches, each branch the wrapper of the member. **A call that takes such a wrapper** branches over the members' wrappers, so a loop that hands each item over as `compiled_for(x)` runs each member's own code in a build, as in a session.
  - **A call where the member's type chooses the method** (a method at a struct, a family, a kept form, or a union with one, beside a method at the trait: `f(x::ODEFunction)` beside `f(x)`) branches over the members, each branch the call at the member's type.
  - **Several such arguments** branch over each: the branches are the product of their members, up to 64. Past that bound, where the method reached erases by default (§7.8), each argument is boxed apart over its own members, and the method as written is called once at the boxes: the sum of their members, not the product.
  - **The call of a function known only as `Callable{A, S}`** (an element of a `Vector{Callable{A, S}}`) branches over the signature's members, each the function's own call; the box's test (§9) is answered at each member when the program is built. **A function known only as bare `Callable`** (an element of a `Vector{Callable}`) branches over `Callable`'s members, and the result is the join of the branches'.
  - **A call that one method at the trait takes** runs that method's code compiled at the trait, once; its operations branch over the members.
  - **Past 64 members** a branch is not made: the call stays dynamic, and the build refuses it.
- **So a program whose calls outside the traits are typed builds without a call left to run time,** and its binary has no compiler in it.
- **`make_executable(main, path)`** writes an executable of `main(args::Vector{String})` at `path`. **`make_library([f => (R, (A...)), …], path)`** writes a shared library that exports each `f` under its name, with C's calling convention; `R` and each `A` is a type C can pass (a bits type, a pointer, `Cstring`, `Nothing`).

  ```julia
  make_executable(shapes_main, "shapes")
  make_library([total_area => (Cdouble, (Cint,))], "libshapes.so")
  ```

  - The build is a closed build, in a process of its own. That process loads the program: the file a function of `Main` is written in, or the function's package. The file's top-level statements run there.
  - A program builds exactly where its `main` is fully typed (§14). The two functions run the check first, in the session; where `main` is not fully typed they raise `BuildError` with `fully_typed`'s report, and start no build.
  - **The build's Base.** Julia's build script replaces some of Base's and the standard libraries' methods by forms a closed build can compile: printing a type, `sprint`, logging and deprecation warnings (off), some packages' `__init__`. The check infers against the same replacements, read from the build script's files, so a program that prints a type's name is fully typed where it builds. The session's own methods are not changed. `build_base_report()` lists the replacements.
  - **A function written at the prompt** is built from the prompt's inputs. The build replays the definitions the function depends on, in the session's order: its own, and by name those of every function, type, constant and trait it mentions, and so on; the memberships of the types reached; the imports. Nothing else of the session is replayed: no call, no assignment to a global. A global the function reads is therefore a `const`.
  - A function the build's process cannot name is refused: an anonymous function, a closure.
  - Inside a build's own process the two functions do nothing.
- **Closed programs:** `verify_main(main, (Vector{String},); entrypoints = true)` lists every target a program can reach, for `juliac --trim`:
  - a function passed at a `Callable` adds one target at its signature;
  - a box's code lists a target of its operations at every member the session has: each concrete member declared, and each member of a family or an abstract type the session has used. These can be more than a build's members (above); a target past them is compiled and never called;
  - the wrapper of a value known only by its trait lists, at the same members, the instances its calls run;
  - a `like` result lists the member's rebuilding;
  - each set of supplied keywords is a signature.
- **The report:**
  - `targets`: every signature the program reaches;
  - `entrypoints`: the targets that no call in the code names (the members', the wrappers' and the `Callable`s'). A build is told these: `add_entrypoints(report)`, called while `juliac` builds, registers them;
  - `holes`: the calls a build refuses, as `fully_typed` lists them: the build's own check, with the members a build counts;
  - `complete`: false where the walk stopped at its bound (`bound = 100_000` signatures).
- A trimmed binary compiles everything plainly ([facts §13.3](facts.md#133-trimmed-binaries)).

**Status:** Implemented, but for T-108, T-109 and [compiler C-86, C-87 and C-156](compiler.md#deviations) (a value the build does not count; the branch's cost; several choosing arguments past the bound); a call in the latest world: Planned, with [compiler C-103](compiler.md#deviations); a method that erases compiled ahead at the box: Planned, with [lowering L-66](lowering.md#15-deviations).

---

## 17. Named implementations

A second way for a type to join a trait, used only where a caller names it, is a wrapper type that joins it: `Via{Fast}(x)`, a newtype. A foreign trait for a foreign type is joined through the user's own wrapper type: `struct FastM; m::M; end` with its own membership.

**Status:** Planned.

---

## 18. Status index

| Construct | Status | Section |
|---|---|---|
| a trait is an abstract type; membership, transitivity, worlds | Implemented | §3.1 |
| parameters as associated types; invariance, `X{<:T}`; one instance per member | Implemented, but for T-105 | §3.2 |
| a family states its instance as a pattern, equations included | Implemented | §3.2, §5.8 |
| a trait wherever a type stands | Implemented | §3.3 |
| a non-membership relied on, with its edge; a pirate's membership | Implemented, but for compiler C-77, C-88 and T-112 | §3.4, §12.2 |
| intersections `All{X, Y, Z, …}`; bundles as aliases | Implemented | §3.6 |
| operations, `where` on operations, the receiver at any position | Implemented | §4.1 |
| an operation as an entry of the contract: no method at the trait for one without a default; `MethodError` with the contract's hint outside the declared signature | Implemented | §4.1, §4.2, §11 |
| defaults as the trait's methods, reached by every caller | Implemented | §4.2 |
| declared fields as stored fields | Implemented | §4.3 |
| `Self`; supertraits | Implemented | §4.4, §4.5 |
| `struct S <: X`, declared and checked by `@implement X S` | Implemented | §5.2 |
| one line, block, several traits, stated parameters | Implemented | §5.3–§5.7 |
| forwarding: the member's own methods; a default through the trait's method | Implemented | §5.5 |
| families; abstract types and traits as members | Implemented, but for compiler C-31 | §5.8, §5.9 |
| checks at the declaration and at first use | Implemented, but for compiler C-31; the check as kept instances with edges: Planned, with T-129 | §5.10 |
| overrides fixed; redeclaration | Implemented | §5.11 |
| a membership taken back, `delete_membership`; Revise on memberships | Implemented, but for lowering L-64 (Revise) | §5.13 |
| dispatch: specificity, ambiguity reported at a membership, fallback | Implemented | §6.2–§6.4 |
| `like`, `withfields`: the library's conveniences | Implemented | §6.5 |
| keywords, defaults, varargs at traits | Implemented | §6.6 |
| keys and shared code: an optional extension | Optional ([open issue 147](../open-issues.md)) | §7.2; [extensions §1](extensions.md#1-keys-code-shared-among-members-the-contract-sees-alike) |
| bounded methods: the instance at the box, read where a method is defined | Implemented, but for compiler C-115 | §7.3, §11.2 |
| the two kept forms, the box and the wrapper; the value's type decides | Implemented | §7.4–§7.6 |
| `Dynamic{X}`, the box | Implemented | §7.7 |
| erasing by default: the forwarder made where a method is defined | Implemented, but for T-125 and compiler C-111 | §4.6, §7.8 |
| operations on a value known only by its trait | Implemented | §7.9 |
| storage typed by a trait; struct parameters; storage keeps the form given | Implemented | §8 |
| `Callable`: every function a member; the signature checked at the box and at a wrapper's entry, the result on return | Implemented, but for T-156, compiler C-146 and lowering L-58 | §9 |
| A closed abstract type with a contract; `IO`'s contract; the eraser `IOContext{IO}` | Implemented | §3.4, §9b |
| BaseTraits; element types by variance; `retain!` | Implemented | §10 |
| checks, errors, hints | Implemented, but for T-99 and compiler C-115 | §11 |
| ownership, joint owners, pirates, strict mode | Implemented, but for T-96 and T-112; the check instances that fail validation inferred again at a load: Planned, with T-129 | §12 |
| owner-only functions, `@owner_only` | Implemented, but for compiler C-130 | §6.8, §12.2 |
| a pirate reported where it ends deep-G2 code; `report_pirates!` | Implemented | §12.2 |
| the standard libraries as owners | Open ([open issue 19](../open-issues.md)) | §12.1 |
| scopes: `@trait_module` and its options `facts`, `bounded`, `no_pirates`, `owner_only` | Implemented | §13 |
| concreteness and fully typed mode | Implemented, but for T-100, T-101, T-109 and T-122 | §14 |
| printing | Implemented | §15 |
| compiling ahead; a closed build's members and branches; `verify_main` | Implemented, but for T-108, T-109 and compiler C-86, C-87, C-156; a call in the latest world: Planned, with compiler C-103; a method that erases compiled ahead at the box: Planned, with lowering L-66 | §16 |
| named implementations | Planned | §17 |

---

## 19. Deviations

The rows below are where the implementation falls short of this page; the heads are in [the state](../state.md). The lowering's deviations are [lowering.md's](lowering.md#15-deviations), the type system's and dispatch's [compiler.md's](compiler.md#deviations).

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| T-96 | [§12.3](#123-strict-mode) | Strict mode refuses a binding redefined from another module, through its hook ([compiler §10.2](compiler.md#102-hooks-for-strict-mode)). | No such hook exists: a binding redefined from another module is followed. | Julia (no hook); TraitWorld `src/strict.jl` |
| T-99 | [§11.4](#114-hints) | The hints are gated on the SciML error cases. | The hints are tested on the library's own cases (`test/hints.jl`, `test/messages.jl`). The SciML cases run on the port and reach no hint: each is a run-time failure in the user's function, not a call of a method at a trait. They are a measurement, not a gate. | TraitWorld `test/hints.jl` |
| T-100 | [§14](#14-concreteness-and-fully-typed-mode) | `@enforce_fully_typed` raises for every call that a build from the signature refuses, in the code or in anything it calls. | The compiled code asks the check only where the session's inference found a run-time site in the code or in a callee compiled by facts. A call that only the build refuses, inside plain code the method calls (Base's, in the product setting), is reported by `fully_typed` and not raised. | Julia's `Compiler/src/facts.jl` (`fully_typed_fault`); TraitWorld `src/fullytyped.jl` (`_fully_typed_hook`) |
| T-101 | [§14](#14-concreteness-and-fully-typed-mode) | Concreteness, like fully typed mode, can be declared for a module before `@trait_module`. | Concreteness is declared per trait and per method only. | TraitWorld `src/fullytyped.jl` |
| T-104 | [§14](#14-concreteness-and-fully-typed-mode) | `@enforce_fully_typed` raises at every run of a fault. | The check is in the method's code compiled by facts. A plain caller that inlines the method, or propagates constants into it (compiler C-45), runs it without the check. The warning's once-only flag is written into the code's literal. | Julia's `Compiler/src/optimize.jl`, `base/experimental.jl` |
| T-105 | [§3.2](#32-parameters) | An input is never left open where an operation's result needs it: a method whose `where` variable or stated value does not fix it is refused at its definition. | Not checked: such a trait's method is accepted, and the call's result names the open input. | TraitWorld `src/trait.jl` (`_trait_method`) |
| T-108 | [§16](#16-compiling-ahead-closed-programs) | `add_entrypoints(report)` gives an instance at a member to the build through Julia's interface for entry points. | Julia's `Base.Experimental.entrypoint` takes a signature, which names the instance compiled once. The instance at a member is pushed into the compiler's internal list `Base.Compiler._entrypoint_mis`. | TraitWorld `src/fullytyped.jl` (`add_entrypoints`) |
| T-109 | [§14](#14-concreteness-and-fully-typed-mode), [§16](#16-compiling-ahead-closed-programs) | Fully typed code is exactly the code a closed build compiles, and the report's calls are the build's. | The check and the build can give different verdicts. What differs: (1) what the build script changes in Base that is no method is not read by the check: the binding `Base.invokelatest`, which the build makes a direct call (the check reports the call, the build builds; the closed rule that removes it is compiler C-103), and eleven functions' `max_args`. (2) Three functions the build script adds are defined in the session's Base as written (`show_typeish`, `invokelatest_trimmed`, `unwrap_val`). (3) The lists of calls are not compared one by one: the report names the call in the user's code above a refused call, the build the call it stopped at. (4) A build's process that loads a package from source, not from its image, runs the package's own workload under the closed rules, and can fail there. (5) At a member of a family that no image has checked, the check in a session leaves calls at the trait unresolved that the build's process resolves, since its queue runs the member's check ([open issue 184](../open-issues.md#4-design) (b)). | TraitWorld `src/fullytyped.jl`, `src/buildbase.jl`; [open issue 181](../open-issues.md#4-design) |
| T-112 | [§12.3](#123-strict-mode) | Strict mode refuses a pirate's membership that would change code compiled by facts, before it exists. | The check before the declaration walks the edges a method's check walks. The declaration's invalidation log is read after it, as a method's is; code compiled by facts that the walk missed is undone as a method's is: the membership is taken back (§5.13) and refused. At an image's load, a family's or an abstract member's membership is checked for the folded answers only, not for the calls. | TraitWorld `src/strict.jl` (`_declare_pirate!`, `_membership_violation`, `_image_membership`) |
| T-122 | [§14](#14-concreteness-and-fully-typed-mode) | `fully_typed`'s report lists apart the calls a build resolves and a session leaves to run time; `isfullytyped(report; session = true)` answers for a session. | The report lists the calls the build's check refuses (`Compiler.closed_check`) and the walk's root causes; a call a build resolves and a session dispatches is in neither list, and nothing answers whether code is fully typed in a session. | TraitWorld `src/fullytyped.jl` (`fully_typed`, `isfullytyped`, the report's type) |
| T-125 | [§7.8](#78-erasing-by-default-the-forwarder) | The forwarders belong to the method: reflection shows the method as written, and redefining or deleting the method takes its forwarders with it. | `methods(f)` lists the method at the kept forms and its forwarder as two methods, both at the definition's line; a forwarder is found by a mark in its code (`TraitWorld._is_forwarder`). Deleting the method at the kept forms leaves its forwarder (Revise). `@erasing` is kept as the definition itself. | TraitWorld `src/erasing.jl` (`_expand_definition`, `_is_forwarder`, `@erasing`); compiler C-111 |
| T-129 | [§5.10](#510-checks), [§5.11](#511-overrides-and-redeclaration), [§12.3](#123-strict-mode) | A member's check is its serving instances, kept with their edges and validated with an image; a definition that would end one, an operation's own method or one below its body, is judged by inferring that call again with it, found by the walk strict mode runs; at a load only the instances that fail validation are inferred again. | The library infers each serving method's result apart (`check_member`, `_check_contract!`: `Base.infer_return_type`) and keeps the answers as its own records (`_CHECKED`, `_FIXED_CALLS`, `_CHECKED_RESULTS`), made again at a load by a walk without inference (`_sync_image_records!`, `_records_from_entry!`). A definition is judged against the records by one intersection per kept call (`_definition_checks`, `_check_membership_calls`), so a method below an operation's body is not seen. Under strict mode every checked call of an image's membership is inferred again at its load (`_LOAD_MEMBERSHIPS`; [GT-2](../goals.md#3-tensions-between-the-goals)). | TraitWorld `src/check.jl`, `src/implement.jl` (the records, `_definition_checks`, `_infer_new_method`), `src/strict.jl` (the load's inference) |
| T-156 | [§9](#9-functions-callable) | A function with no method at `A`, given where it is boxed, raises the `MethodError` a call at `A` would, with the hint naming the declaration. | At a forwarder the refusal is the `MethodError` of the method's own call (`colmap(::typeof(uppercase), ::Float64)`), with the hint naming the declaration and the function's methods; Julia's message adds its line "This error has been manually thrown, explicitly, so the method may exist but be intentionally marked as unimplemented", since a method matches the call's types. The box written out (`Dynamic{Callable{A, S}}(f)`) raises the call's own. | TraitWorld `src/callable.jl` (`_callable_box_check`) |
| T-161 | [§7.3](#73-bounded-methods) | At its module's end a call of a name the module never defines is a fault. | The call is read as one left to run time, and the method is accepted (`f(a::UShape) = nothere(a)` in a `bounded` scope); called, it raises `UndefVarError`. | TraitWorld `src/classify.jl` (`_decide_bounded` with `final = true`); `experiments/implementation/w158/i-probes/undefined.jl` |

**Retired IDs** (their rows are in [the ledger](../../attic/writeup/record/deviations-retired.md)): T-1 to T-95, T-97, T-98, T-102, T-103, T-106, T-107, T-110, T-111, T-113, T-114, T-120, T-121, T-123, T-124, T-126 to T-128, T-130, T-157 to T-160.
