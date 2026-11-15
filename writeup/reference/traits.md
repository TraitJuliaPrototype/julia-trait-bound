# Traits: the reference

**Adopted** (the user, 2026-11-06; W-105; [the folder's README](README.md)). This page defines the trait language: what a trait is, how a type joins one, how methods at traits dispatch and are compiled, what is checked, and which errors a user sees. It describes the language as designed. The status line of each section says how far it is built.

- What compiled code may assume: [`facts.md`](facts.md).
- The Julia interfaces the language rests on: [`compiler.md`](compiler.md).
- What the library's macros expand to: [`lowering.md`](lowering.md).
- Terms are defined where they first matter; the [glossary](../glossary.md) links here.

**Status labels:** Implemented, Planned, Optional, Open, and "mine" for a choice an agent made, as [the README](README.md#conventions-for-every-reference) defines them.

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
Option         ::= "facts" | "bounded" | "no_pirates" | Name "=" Expr
Concrete       ::= ( "@enforce_concrete_only" | "@warn_on_abstract" ) Name*
FullyTyped     ::= "@enforce_fully_typed" | "@warn_not_fully_typed"
```

The kept forms are values, made by ordinary calls: `Dynamic{X}(x)` and `compiled_for(x)` (§7.4). They have no syntax of their own.

**Status:** Implemented in TraitWorld `unified` e7ff8e2 for `@trait` and `@implement` (W-106); `@trait_module` and `@default_dynamic` bb78d02 (W-111); concreteness W-114. The library still accepts `@default_compiled`, the options `dynamic` and `first_seen`, and the casts: T-127.

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

**Status:** Implemented in Julia's type system on branch `unified` 62016706d0 ([compiler §4](compiler.md#4-sets-and-memberships), with its deviations); `@trait` and `@implement` in TraitWorld `unified` e7ff8e2. A membership taken back: Planned (§5.13).

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
- **Input parameters:** `@input N` in the body marks `N` as an input. A type may be a member at several values of an input (`HasProperty{:ps, PView}` and `HasProperty{:u, Vector{Float64}}`). The trait at fixed input values is a trait of its own for every other rule. A method's `where` variable or a stated value fixes an input; it is never left open where an operation's result needs it.
- **Not offered:** equations between type functions; a parameter bound that names its own trait.
- **Two traits linked by their parameters** are linked by a method's shared `where` variables, as in Julia: `solve!(integ::Integrator{U, T, P}, prob::ODEProblemTrait{U, T, P}) where {U, T, P}`.

**Status:** Implemented on `unified` 62016706d0 (subtyping) and in TraitWorld `unified` e7ff8e2 (the checks); a member at several values of an input on `unified` 350c5b1c59 and in TraitWorld `unified` a658203 (gate `n10_inputs`), but for the refusal of an input left open (T-105). A family states its instance as a pattern, an equation's parameter included (§5.8): mine (2026-11-06; open issue 140).

### 3.3 Where a trait stands

A trait is written wherever a type is written:
- in any method's signature, in any module: `f(t::ColTable)`, `f(v::AbstractVector{<:Shape})`, `f(x::T) where {T <: Shape}`;
- as a field's type, a type parameter, an element type: `model::Model`, `Vector{Shape}`, `Dict{String, Shape}`, `Ref{Shape}`, `Union{Nothing, Shape}`;
- as a struct parameter's bound: `struct Problem{F <: Model}`;
- in `isa`, `<:`, `typeassert`, `convert(X, x)`, `Type{<:X}`;
- as a declared supertype: `struct S <: X`, `abstract type A <: X`.

**Status:** Implemented on `unified` 62016706d0 and 29035cab11 (W-98, W-99): a set is an abstract type wherever a type stands.

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

**Status:** Implemented on `unified` 62016706d0 (W-98). A non-membership relied on: Implemented on `unified` a19d937eaa (W-140; [compiler §4.8](compiler.md#48-negatives-fold-with-an-edge-positives-through-entries), [§5.5](compiler.md#55-a-membership-invalidates-as-a-method-does); gates `n18_closed_after_load`, `n7_guards`, `n16_declared_result`, `n25_image_before_set_method`), with compiler C-88. The rule: the user (2026-11-11, "declaring membership of a type in a trait if you own neither the type or the trait is piracy").

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

**Status:** Implemented on `unified` 62016706d0 (W-98): a member's value is a value of the trait, unwrapped. The argument at a trait that erases by default as a kept form: Planned (the plan's D-1, 2026-11-15; [decisions](../record/decisions.md) §3); in TraitWorld `unified` 362f08b where the method is written with the library's `@erasing` (T-125). A view that is not the object: the user (2026-11-15, "1 is acceptable").

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

**Status:** Implemented (W-107; the user, 2026-11-06: Q5 (a), "spelled All{X,Y,Z,...}") on `unified` 8a9144928e with TraitWorld `unified` ae4d250, but for the split's members (W-109). The name from the library: mine (2026-11-07; [open issue 148](../open-issues.md#2-design), its recommendation (b)).

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

**Status:** Implemented in TraitWorld `unified` e7ff8e2 at each membership; the result asserted at a call through the trait: Implemented (§7.9). An operation as an entry of the contract, with no method at the trait for an operation without a default, and Julia's `MethodError` with the contract's hint outside the declared signature: Planned (the plan's D-4, 2026-11-15; [decisions](../record/decisions.md) §1), with T-120, [lowering L-63](lowering.md#15-deviations), [compiler C-100](compiler.md#deviations).

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

**Status:** Implemented in TraitWorld `unified` e7ff8e2; mine (2026-11-06). Only a default as a method at the trait: Planned (D-4), with T-120 and [lowering L-63](lowering.md#15-deviations).

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

**Status:** Implemented in TraitWorld `unified` e7ff8e2 (the user, 2026-11-06, Q7 (a)); a field named by an input in TraitWorld `unified` a658203, mine (2026-11-08). Swift's protocol properties are the conforming type's own properties in the same way.

### 4.4 `Self`

- In a trait's body, **`Self` is the receiver type**: the member when it serves an operation by its own methods or defaults, the field's type when the member forwards (§5.5).
- It appears as an argument's type, in result types and in equations (`T = eltype(Self)`).
- **A constructor operation** returns `Self`: `kwith(t::KTable, cs::Vector{Vector{Float64}})::Self`. With `like(t, x)` (§6.5) it returns "a value like the input".

**Status:** Implemented in TraitWorld `unified` e7ff8e2.

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

**Status:** Implemented on `unified` 62016706d0 and in TraitWorld `unified` e7ff8e2.

### 4.6 Erasing by default
<a id="46-the-traits-default-attribute"></a>

`@default_dynamic` in the body makes the trait **erase by default:** a method at the trait takes a plain member boxed, as `Dynamic{X}(t)`, and a kept form as it is (§7.8). The contract records it ([compiler §4.1](compiler.md#41-sets)).
- A trait without it takes a plain member as it is, as Julia takes a value at an abstract type.
- A caller chooses otherwise by what it passes: `compiled_for(x)` for code per type, `Dynamic{X}(x)` at a trait that does not erase (§7.5).
- `Callable` erases by default (§9).

**Status:** Planned (the plan's D-1, 2026-11-15; [decisions](../record/decisions.md) §3). In TraitWorld `unified` 5e2ef71 (W-151) the library records it on its contract and its macro `@erasing` reads it (T-125, [lowering L-65](lowering.md#15-deviations)). The trait's say over a plain member: the user (2026-11-06: "Dynamic or not as a trait and library default, that the user can override"); as forwarders made at each method: the user (2026-11-15: "if Callable wants it anyway that's how it should be").

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

**Status:** Implemented in TraitWorld `unified` e7ff8e2.

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

**Status:** Implemented in TraitWorld `unified` e7ff8e2 for the declaration and its check, and 701aaab for the refusal at a module's end, by Julia's module-end hook ([compiler §10.1](compiler.md#101-definition-and-image-hooks), `unified` 28c401eb0c); the use before it raised at a use dispatched at run time in TraitWorld 0aff625 with `unified` 352b916899 (E-350), mine (2026-11-10); a use compiled with the type known on `unified` fcdfd0da36 (E-352; the user, 2026-11-06, Q8 (c): "declared membership stays as a design goal"). The membership's entry, and the parameters from the definition: TraitWorld e8554d9, mine (2026-11-10, W-131, E-345).

### 5.3 One line

```julia
@implement ColTable Ramp           # Ramp has methods of ncols and col
@implement Placed Sprite           # a trait of fields only: Sprite has the fields
```

- `S`'s own methods serve every operation without a default; define them before the declaration.
- A trait of fields only is served by `S`'s stored fields.
- **No field is special:** the one-line form never forwards. Forwarding is written with `by` (§5.5).
- Errors name the operations: methods for some operations and not for others; no methods (listing the fields whose type is a member, each with its `by` line).

**Status:** Implemented in TraitWorld `unified` e7ff8e2.

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

**Status:** Implemented in TraitWorld `unified` e7ff8e2.

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

**Status:** Implemented in TraitWorld `unified` e7ff8e2; the trait's method serving a forwarding member is mine (2026-11-06). The member's own methods for required operations: TraitWorld (W-128), mine (open issue 158 (a), 2026-11-08).

### 5.6 Several traits at once

```julia
@implement (ColTable, RowTable) Grid by data
```

One declaration, one membership per trait, all served the same way. Each may also be declared on its own.

**Status:** Implemented in TraitWorld `unified` e7ff8e2.

### 5.7 Stating parameters

```julia
@implement ArrayLike{Float32, 1} MyVec
```

- A membership states the parameters that no field and no equation defines.
- A stated value for a parameter an equation defines is checked against the equation at the member. If they differ, the membership is refused (`ImplementError`).

**Status:** Implemented in TraitWorld `unified` e7ff8e2.

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

**Status:** Implemented in TraitWorld `unified` e7ff8e2, each member checked at its first use, at dispatch and before compiled code runs (`unified` fcdfd0da36, E-352; compiler C-31); a variable bounded by a `Union` declared per type in dd72b10; the variables in the block's methods in 401c7b4, mine (2026-11-08).

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

**Status:** Implemented on `unified` 62016706d0 and in TraitWorld `unified` e7ff8e2.

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

**Status:** Implemented in TraitWorld `unified` e7ff8e2 at a declaration and at a first use at dispatch; an image keeps the answers that passed while it was built ([lowering §11](lowering.md#11-checks-errors-and-what-images-keep); `unified` b1c0b50f4c, TraitWorld 347176a). The rule at an abstract further argument: TraitWorld 4be0097, mine (2026-11-07). A method that takes any receiver serving an operation without a default: Planned (D-4), with T-120. The check kept while a member: TraitWorld `unified` 5b3c427, mine (2026-11-10), for memberships declared in the session and members of a family, an abstract type or a trait checked in it; for a membership loaded from a package's image, TraitWorld 6871ea9 with `unified` e42047dba2 (E-344). A member by its definition, from an image too: TraitWorld e8554d9 (W-131, E-345). Cost: one dictionary lookup per method definition; for a definition of an operation's function, one intersection per kept call under the function, and one inference per call the method would take. The check as its serving instances, kept with edges and validated with an image; a method below an operation's body judged through them; the walk shared with strict mode: Planned (the plan's D-3, 2026-11-15), with T-129.

### 5.11 Overrides and redeclaration

- **Which operations defaults serve for a member is fixed at its membership.** A later method that would take a call a default serves at the member is refused when it is defined (`ImplementError`). The message names the fix: define the method before the membership, or in its block. A package image's such method is left inactive when it loads, with a warning.
- **A forwarding member's methods are fixed at its membership, like the defaults:** a later method that would take a call one of them serves at the member is refused the same way (§5.5).
- **Redeclaring a membership** replaces it. The new one holds from its world; the old one ends there; code compiled for the old one is invalidated. It is a stakeholder's change ([facts §2.2](facts.md#22-g2-stable-caches)).

**Status:** Implemented in TraitWorld `unified` 701aaab by the definition and image hooks ([compiler §10.1](compiler.md#101-definition-and-image-hooks)), for memberships declared in the session; for one loaded from an image, TraitWorld 6871ea9 (E-344). A redeclaration's new entry on `unified` 62016706d0. The forwarding's methods, members checked at their first use, and the call a method would take (it applies there and no method in force beats it): TraitWorld `unified` 5b3c427, mine (2026-11-10).

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
  - the member's check, and the records of §5.10 and §5.11: a later method at the member is judged by them no longer;
  - the member's place among the trait's candidates (§7.9);
  - for a family, an abstract type or a trait as member, every member it made, with their checks.
- **Values stored before stay where they are.** An item of a `Vector{Shape}` whose type is no member any more is called by its type, as plain code's call is; an operation's call through the trait still asserts the declared result (§7.9). So every call computes what plain code computes, or raises.
- **What cannot be taken back alone:**
  - a member by its definition (`struct S <: X`): its supertype is its definition's, and only a new definition of `S` changes it;
  - a trait's membership in its supertraits, and `Dynamic{X}`'s: they are part of the trait's declaration.
- **A membership declared again** after it was taken back is a new declaration, checked as any (§5.10).
- **Revise:** an `@implement` line deleted from a file takes its membership back, as a deleted method definition deletes its method ([lowering §3](lowering.md#3-implement)).
- **Package images:** an image holds the memberships in force when it is written. Taking one back in a session changes no image. An image loaded afterwards whose code relied on it has that code compiled again: its edge to the membership fails validation.

**Status:** Planned (the plan's D-13, 2026-11-15; the user, by adopting the plan), with T-124, [lowering L-64](lowering.md#15-deviations), [compiler C-106](compiler.md#deviations). The mechanism (the membership's method deleted, the walk run for the removal), the name `delete_membership`, and what cannot be taken back alone: mine (2026-11-15).

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

**Status:** Implemented in Julia's dispatch on `unified` 29035cab11 ([compiler §5](compiler.md#5-dispatch)); how a method is compiled: §7.3's status.

### 6.2 Specificity

- **At each argument: a closed type other than `Any` is more specific than a trait.** `describe([1.0 2.0])` takes the `AbstractMatrix` method, although `Matrix{Float64}` is a `ColTable`. So a later membership never takes a call from a method on the type's own supertypes, and a library adopts traits one function at a time.
- **Between traits:** by subtyping. A subtrait is more specific than its supertrait; an intersection than each of its components. Unrelated traits are unordered.
- `Any` is the least specific, as always.

**Status:** Implemented on `unified` 62016706d0 ([compiler §5.2](compiler.md#52-specificity)); intersections 8a9144928e (W-107).

### 6.3 Ambiguity

- **As in Julia:** a call where two methods apply and neither is more specific raises `MethodError` (ambiguous).
- **Reported earlier, at a membership:** where a membership makes a method apply to a type, and another method of the function is tied with it there with no more specific method for the type, a warning names the function, the methods and the joint method to define (`f(::All{ColTable, RowTable})`). The other method may be at a second trait of the type, at a trait or abstract type the type is under by its definition, or at `Any` with a narrower type at another argument. Under strict mode it is an error (§12.3): the membership that creates the ambiguity raises `ImplementError` and does not exist; a later membership, a redeclaration among them, is not refused for an ambiguity it did not create. For a member by its definition (`struct S <: X`), `X`'s methods apply by the definition, so a second trait's `@implement Y S` is the membership that creates the ambiguity, whether it comes before or after `@implement X S`. A method that dominates every common member suppresses the report.

**Status:** Implemented on `unified` 0d529d33a9 for a concrete member, 264b7f959f for a pattern ([compiler §5.4](compiler.md#54-the-ambiguity-report-at-a-membership)): the warning names the function, the two traits and the joint method's signature, `f(::All{…})` (8a9144928e, W-107); the error under strict mode on `unified` 0bb8f38830 with TraitWorld 960b99e (E-343), for the membership that creates the ambiguity on `unified` 2ee5569252 (E-346); a tie with a method at a declared supertype, a superset or `Any` on `unified` 53d28eea68 with TraitWorld 9383843 (`test/declared.jl`, E-347); at an image's activation reported after the load on `unified` 9f8d7d7c48 with TraitWorld 0aff625 (E-349, [§12.3](#123-strict-mode)).

### 6.4 The fallback

A value that matches no method at a trait reaches the most specific method that applies, as in Julia, or raises `MethodError`. A member at other parameter values than a method states, or a broken shared variable, is such a value.

**Status:** Implemented on `unified` 29035cab11: Julia's dispatch.

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
- **`withfields(t; name = v, …)`** is `t` rebuilt with declared fields replaced.
- **`like` and `withfields` are conveniences of the library,** outside the language's core: functions that rebuild a member from its declaration ([lowering §8](lowering.md#8-like-and-withfields)).

**Status:** Implemented in TraitWorld `unified` e7ff8e2. As the library's conveniences: the plan's D-14 (2026-11-15).

### 6.6 Keywords, defaults, varargs

- As in Julia. A positional default makes two methods; a keyword typed by a trait raises `TypeError` for a value that is not a member; there is no dispatch on keywords.
- **A vararg of members,** `ts::ColTable...`: elements may be different members; code is compiled per tuple of their types.

**Status:** Implemented as Julia's: a positional default's two methods, a keyword typed by a trait (`TypeError` for a value that is no member) and a vararg of different members run in `experiments/docs-examples/tutorial.jl` (§9 there; TraitWorld c9f701e, where under `bounded` the default's short method waits for the method it calls, §7.3).

### 6.7 Constructors

A type's constructor may have methods at traits: `NWState(int::All{IntegratorView, HasSystem}) = NWState(sysnet(int), ustate(int))`. The type's other constructors stay, its default ones included.

**Status:** Planned.

### 6.8 Who may add a method

As for any method (§12.2): a package may add a method to a function it owns, or to another package's function where a type in the signature is its own. A trait it owns counts. Another package's owner-only function takes methods from its owner only (§12.2).

**Status:** Implemented: Julia's rule, with the refusal in a scope that declares `no_pirates` (TraitWorld `unified` 7adcc94, W-114; §12.2). Owner-only functions: Planned (D-9), with T-121.

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

**Status:** Per type and `@nospecialize`: Julia's. The two kept forms: TraitWorld `unified` 5e2ef71 (W-151), with T-126. On the build, `@nospecialize` at a trait argument still takes the attribute's path ([compiler C-112](compiler.md#deviations)). Per key: Optional, to be built late (W-110; the user, 2026-11-06: "keys as optional is approved", and "Keep them optional and build them late"). A use case to investigate, traits with operations only: [open issue 147](../open-issues.md#2-design).

### 7.2 The key

Code shared per key, among members the contract sees alike, is an optional extension: [extensions §1](extensions.md#1-keys-code-shared-among-members-the-contract-sees-alike). No rule of this reference depends on it.

**Status:** Optional (W-110; the plan's D-14, 2026-11-15).

### 7.3 Bounded methods
<a id="73-fully-bounded-methods"></a>

```julia
colmean(t::ColTable, i::Int) = sum(col(t, i)) / length(col(t, i))   # bounded
leak(t::ColTable) = typeof(t)          # bounded: at a box, the box's type
wrap(t::ColTable) = Wrapped(t)         # bounded: at a box, a Wrapped{Dynamic{ColTable}}
colsum(t::ColTable) = sum(t)           # not bounded: at a box, sum reaches iterate(::Dynamic{ColTable}), which has no method
```

A method is **bounded** at a trait argument when its code for the box does what it says for every member: **its instance at `Dynamic{X}` makes no call, with a value at the box, that finds no method or only throws.** A value at the box is the box itself, or a value the code knows only by a trait (an operation's result declared with one).
- **That instance is ordinary code at a concrete type,** compiled by Julia's own inference, with its edges. It is the code a box runs at the method (§7.7), and, for a trait that erases by default, the code every plain member runs through the forwarder (§7.8).
- **What it certifies:** behind the box only the contract's operations reach the member (§7.7). So a bounded method works, erased, for every member that will ever join. Rust checks a generic body against its bounds with an archetype; here the archetype is a real type, the box.

**A fault** is a call in that instance, with a value at the box:
- that finds no method: directly; below a call that only throws, the chain of calls named; or left to run time with no method at the types the code knows;
- that only throws: an undeclared field read at the box is named as such.
- A call left to run time that finds a method when it runs is Julia's function barrier, no fault.

**What the body does decides,** not a list of forms.
- `typeof(t)`, `Wrapped(t)`, a closure that captures `t`, `like(t, …)`, a constructor that stores `t` at a struct parameter: each acts on the box, and is bounded.
- `sum(t)` at a box of `ColTable` reaches `iterate(::Dynamic{ColTable})`, which has no method: not bounded. The report names `iterate`, reached from `sum`. At a box of `Iterable{Float64}` the same call is bounded, and Base's `sum` is compiled once for the box.
- A function of `Self` that an equation names (`eltype(t)` where the trait defines `T = eltype(Self)`) answers at the box as for the object: its value is the trait's parameter (§7.4).

**The report** names the line of the method that passes the value, and what the call reaches.

**Where the instance is read.**
- Each argument at a trait, an intersection, a kept form, or a `where` variable bounded by one, at the box of that trait.
- A variable the signature leaves free, at a stand-in: the first of `Float64`, `Int`, `Symbol`, `String` its bounds allow, else its bound where that is concrete.
- A keyword method's body is read, not its sorter. The forwarders (§7.8) are not read.
- A method whose box cannot be formed (a trait whose parameters the signature leaves open, where no stand-in fits) is not read.

**When.** Where the method is defined (§11.2). A method whose body names a global not yet defined, or whose only faults are calls of its module's own functions with no method yet, waits for those names, and at last for its module's end. The instance is kept with its edges, as any code: a later definition that changes what it relied on ends it, and the check reads it again when it is inferred again.

- **A scope that declares `bounded`** (§13) refuses a method that is not bounded, with `TraitUseError` naming each fault and its line.
- **`@unbounded f(…) = …` marks a method unbounded on purpose:** `bounded` does not refuse it. A library's adapter that hands its argument to plain code is written so.
- With keys, an optional extension (§7.2), a bounded method would share its code per key.

**Status:** Planned (the plan's D-3, 2026-11-15, confirmed by the user's adoption of the plan; [decisions](../record/decisions.md) §2). Built in TraitWorld `unified` 6f86b4e (W-151; `src/atbox.jl`; E-401, E-406: E-397's mistakes found at their lines, no fault in the ports' 249 methods), with [compiler C-115](compiler.md#deviations): the instance is inferred apart, at stand-ins, and dropped at a load; an equation's function at the box: T-130. The fault classes, the stand-ins and what is not read: mine (2026-11-15, the prototype's). `bounded` on in trait modules with a switch: the user (2026-11-06, Q2 (a)); `@unbounded`: mine (2026-11-06).

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

**Status:** Planned (the plan's D-1, 2026-11-15; [decisions](../record/decisions.md) §3). Built in TraitWorld `unified` 5e2ef71 to 6f86b4e (W-151; E-401 to E-406): the box `Core.Dynamic`, the wrapper `Compiled{T}` as the library's type (T-126). The forms as values: the user (2026-11-15, "So provisionally I would accept P1 with the addendum.", then "Yes please. Build the compiler for P1 …"). The wrapper's reach: the user (2026-11-15, "I would say that we want wide reach. If a subtrait provides a higher performance specialisation we don't want to miss that."). The name `Compiled{T}`: mine (2026-11-15).

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

**Status:** Planned (the plan's D-1, 2026-11-15; [decisions](../record/decisions.md) §3). Built in TraitWorld `unified` 6f86b4e (W-151), with the library's `@erasing` in place of Julia's forwarders (T-125); Julia still resolves an attribute at each trait argument ([compiler C-112](compiler.md#deviations)), and the library still offers its surface (T-127). The principle: the user (2026-10-21, "Values carry"); the choice in the value's type: the user (2026-11-15, D-1).

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

**Status:** Planned (the plan's D-1, 2026-11-15). Built in TraitWorld `unified` 5e2ef71 (W-151; `test/bytype.jl`), with T-126: the library's exported `compiled_for` is still the cast of Julia's, and a module binds the wrapper's function as `TraitWorld.ByType.compiled_for`. The wrapper's name and its reach of every `Callable` by its call method: mine (2026-11-15, the prototype's).

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
- **`X` is a trait with its parameters, or an intersection of such:** `Dynamic{StateVector{Float64}}`, `Dynamic{All{Shape, Placed}}`. `Dynamic{Column}`, with `Column`'s parameter left open, is refused when made (`ArgumentError`, naming `Dynamic{Column{T}}`), as Rust's `dyn Iterator` must name its `Item`. So a box is made where the parameters are known; a box at a second signature (a function seen at the duals too) is made again where that signature is known. Members whose parameters differ share a container typed by the trait, `Vector{Column}`.
- **Its operations** dispatch on the held object when they run, with the declared results. They are forwarding methods of its own, at `Dynamic{<:X}` ([lowering §2](lowering.md#2-trait)). Its declared fields are read and written on the held object.
- `unwrap(d)` is the held object.
- **It is a member of `X` and `X`'s supertraits only,** not of the other traits its object belongs to. To pass it where another trait is required, unwrap it, or box it as `Dynamic{All{X, Y}}`, a member of both.
- **It is under none of its object's declared supertypes:** a boxed function is no `Function`, a boxed vector no `AbstractVector`. For a closed abstract type the eraser is a subtype of it, as `IOContext{IO}` is (§9b).
- **A question outside the contract is asked before the value is boxed:** a function's arity by reflection, a field the trait does not declare.
- **A `Dynamic{Callable{A, S}}` is called at `A` only.** To call its function at another signature, box it again, `Dynamic{Callable{B, S}}(unwrap(d))`, or as `Dynamic{All{Callable{A, S}, Callable{B, S}}}` where both signatures are known when it is made.
- **It keeps its form through storage:** a `Vector{Dynamic{Shape}}`, a field of type `Dynamic{Shape}` or `Shape` (§8).
- A result declared `::T` is asserted at the parameter's value: at `Float64` for a `Dynamic{StateVector{Float64}}`.
- Rust's `dyn X` and Swift's `any X` are such boxes: usable through their own trait only. `Dynamic{All{X, Y}}` is Swift's `any X & Y`.

**Status:** Implemented: the struct is Julia's `Core.Dynamic` (`unified` e692e57ab7, W-111); its memberships and methods are the library's (TraitWorld `unified` bb78d02); a `Dynamic{All{Callable…}}` called at either signature in 401c7b4. A box of the same trait as itself, of a subtrait and of a wrapper as their object's box: TraitWorld 5a9d19d (W-151), in place of `Core.Dynamic`'s own constructor ([compiler C-113](compiler.md#deviations)); the membership decided when compiled: Planned, with [compiler C-110](compiler.md#deviations). Mine (2026-11-06). In `Core`, members of intersections, parameters required, the second signature: mine (2026-11-06, the reviews of the draft). A box of the same trait as itself: mine (2026-11-15, the prototype's).

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
- An argument typed by a trait that erases by default, with the trait's parameters given there: `m::Model`, `f::Callable{Tuple{Float64}, Float64}`, `c::Column{T}` with `T` a variable of the method.
- An argument typed by an intersection with such a component. It is boxed at the intersection.
- An argument typed by a `where` variable bounded by such a trait: `x::C` with `C <: X`. `C` is then the kept form's type.
- **Not** an argument whose trait the signature leaves open (`t::Column`, `t::Column{<:Real}`): a box needs the trait's parameters (§7.7). There the argument takes a plain member as it is.

**The forwarder's shape.**
- One forwarder per positional arity that holds an argument that erases. Positional defaults make their arities, as in Julia.
- Keyword arguments are passed on whole.
- With several arguments that erase, the one forwarder boxes each plain one and passes a kept form as it is.
- The forwarders belong to the method: they are defined after it, and redefining or deleting the method redefines or deletes them. Reflection shows the method as written.
- **The trait's own methods are not forwarded:** a default (§4.2) is a method at the trait for every member. A plain member served by a default runs it as itself; a kept form reaches it as a member.
- **Julia's default constructors are methods like any:** a struct whose parameter is bounded by a trait that erases by default boxes a plain member at its default outer constructor (§8.2).
- **No type is exempt:** Julia's own types are boxed as a package's are (`abs2` given at a `Callable` argument).

**What it costs.** The forwarder makes a box at each call that passes a plain member. The box's membership test is decided when the code is compiled: the forwarder runs only where its signature matched, and the compiler decides a member's membership with an edge ([compiler §4.8](compiler.md#48-negatives-fold-with-an-edge-positives-through-entries), [§6.3](compiler.md#63-the-forwarders)). Where the box does not escape, it needs no heap of its own. A box made once and held costs less: a library that calls its trait's methods many times erases at its door, once (§7.10).

**Status:** Planned (the plan's D-1, 2026-11-15; [decisions](../record/decisions.md) §3), with [compiler C-110, C-111](compiler.md#deviations). Built in TraitWorld `unified` 362f08b (W-151) as a macro of the library, `@erasing`, written at each method definition (T-125). The forwarder's shape, which arguments erase, the trait's own methods not forwarded, and no type exempt: mine (2026-11-15, the prototype's). The default constructors forwarded: mine (2026-11-15).

### 7.9 Operations on a value the code knows only by its trait

Where the code holds a value at the trait's type (a box's object, an argument declared `@nospecialize`, a field or element typed by the trait, an operation's result declared with the trait):
- **an operation's result is its declared result,** so the code after the call is typed. It is asserted, never converted: a member's result of another type raises a `TypeError`, as facts §2.1's "or raises" allows. A member checked at its membership (§5.10) returns it already, and keeps its check while it is a member, so the assertion only catches what the check does not reach: a result at an abstract further argument, a method already in the session when an image's membership loads, and inference's own limits. A dynamic call of the same operation, and the interpreter, return the member's own result;
- **the call branches on the first four members declared** of the trait, each a direct call that may be inlined. Any other member is called through a table keyed by its type: one lookup and one indirect call, whatever the number of members. The order is the declarations': a trait's package declares its common members first. At an intersection, the branches take the first component's members that are members of every component;
- a member declared later takes the table and invalidates nothing; code compiled after its declaration may branch on it if it is among the first four;
- a declared field read there works the same way.

**Status:** The declared result, asserted, and the branches on the first four members implemented on `unified` e70675a606 with TraitWorld e9a63f7 ([compiler §7](compiler.md#7-operations-on-a-value-typed-by-its-trait)); and the table past them; declared fields: W-109. Asserted, never converted, on `unified` ef1233e79e (open issue 171, gate `n22_declared_assert`, E-340): mine (2026-11-10).

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
- The numbers: [`../design/evidence.md`](../design/evidence.md) §2, and §1 for the kept forms (E-401 to E-407).

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

**Status:** Julia's storage, with TraitWorld `unified` e7ff8e2's members: Implemented. The conversion into storage typed `Dynamic{X}`: TraitWorld `unified` 5e2ef71 (W-151; a late load of it ends nothing, E-404). Storage that keeps the form given: the plan's D-1 (2026-11-15; [decisions](../record/decisions.md) §3), the storage table of [the review's addendum](../reviews/2026-11-15-conceptual-design.md#addendum-2026-11-15-the-main-session-p1-corrected-in-discussion-and-provisionally-accepted).

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

**Status:** Julia's bound and default constructor, with TraitWorld `unified` e7ff8e2's members: Implemented. The parameter recording the form, and a plain member boxed at an erasing trait: the plan's D-1 (2026-11-15); built in TraitDifferentialEquations `unified` 813808a with the library's `@erasing` (T-125), where the default outer constructor makes no forwarder.

### 8.3 Equality

`Dynamic{X}(a) == Dynamic{Y}(b)` when `a === b`, for a mutable object by identity, for an immutable one by value; `compiled_for(a) == compiled_for(b)` likewise; `hash` agrees. `===` compares the kept forms.

**Status:** Implemented in TraitWorld `unified` e7ff8e2 for the box, 5e2ef71 for the wrapper; mine (2026-11-06), the wrapper's mine (2026-11-15).

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
- **Every function is a member of every `Callable{A, S}`:** a value of a subtype of `Function`, and a value of a callable type declared a member (`@implement Callable MyCallable`, for a callable struct that is no `Function`). Subtyping reads no method: membership is declared, as for any trait.
- **The signature is checked where the function is boxed or enters.** A plain function given at `Callable{A, S}` is boxed (`Callable` erases by default, §7.8), and the box is made only for a function with a method at `A`: otherwise it raises the `MethodError` a call at `A` would, with a hint that names the declaration and the function's methods near `A`. So the error is at the call that passes the function. A wrapper is checked at the entry of the method that takes it, by the same test.
- **The result is asserted to `S` on return,** at every call of a box, however it is called: its own argument, a copy, a capture, a splat. A call at arguments outside `A` raises `MethodError`; a result outside `S` raises `TypeError`, naming the declared and the returned type; where `S` is `Nothing`, the message adds: end the function with `nothing`.
- **A wrapper is the function:** passed with `compiled_for(f)`, it is checked at entry, and its calls are the function's own, compiled for its type.
- **Neither `A` nor `S` selects a method.** Two methods at `Callable` instances that differ only there are ambiguous for every function: dispatch does not pick by a function's signature. A method that branches on it tests `hasmethod(f, A)` in its body.
- **A struct parameter bounded by `Callable{A, S}` holds every function:** the bound checks no signature. The constructor with a `Callable` argument checks it, by its box or its entry (§8.2).
- **A `where` variable that only `A` or `S` names is not bound by a call,** as Julia's `detect_unbound_args` reports. Another argument binds it (`retain!`, `byrow` above), or code computes the result type as a value, `Base.promote_op(f, T)`, as `map` does ([facts §7](facts.md#7-return_type-and-reflection)).
- **Its default erases:** a plain function is boxed, so code is compiled once per signature, not per function, Julia's own functions included (§7.8). `compiled_for(f)` compiles it for the function.
- **Several signatures** are an intersection: a box of `All{Callable{A, S}, Callable{B, R}}` is made for a function with methods at both, and a call picks the signature its argument types match.
- **Argument types may follow other arguments:** `retain!(f::Callable{Tuple{T}, Bool}, xs::Iterable{T}) where {T}`; the box is made at the signature the other arguments give.
- `Callable` without parameters is every function; a box needs a signature (§7.7).
- **Keywords:** `Callable{A, S, K}`, `K` a named-tuple type (Planned).
- A closure with a trait argument, `(u::ColTable) -> …`, is a method at the trait.
- **Passing `f` on to a higher-order function,** `map(f, xs)`, passes the box: a call at a concrete signature, whose code is compiled once for the box. `colmap` above is bounded (§7.3).

**Status:** Planned (the plan's D-2, 2026-11-15, the user: "Okay, accept the change."; [decisions](../record/decisions.md) §3), with [compiler C-116](compiler.md#deviations), [lowering L-68](lowering.md#15-deviations). Built as the earlier rule on `unified` 5f0a8ffd50 and in TraitWorld `unified` 5d52f0d (W-113): a function a member where it has a method at `A`. The box's call, checked at both ends: TraitWorld 5d52f0d; the hint for a function with no method at `A`: TraitWorld e572379 (W-114), the hint at a failed result L-58. `S` checked on return: the user (2026-11-06, "For Callable S go with checked on return. Keep it simple."). A callable struct declared a member, and a wrapper's calls as the function's own: mine (2026-11-15). Keywords Planned.

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

**Status:** Implemented on `unified` b05ae361e0 (E-337); the display erasing on `unified` 8c4b93f867 with the forks' DataFrames plain and its workload line (forks ddc20f6; E-339), adopted (the user, 2026-11-09: "That said, b-display is adopted."; E-338; `TextDisplay` mine); the counts `Int`, converted at the call, on 0c836f3ef6 (E-333). The user (2026-11-09: "Go with the Fable plans recommendations", [the plan](../plans/2026-11-09-io-alternatives.md) §4.2, option B). `eof`, `isopen` and `close` out of the contract: mine (2026-11-09).

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
| `MutableIndexable{T} <: Indexable{T}` | `c[i::Int] = x::T`, which keeps the length and reads back `x` at `i` | `T = eltype(Self)` | `Vector`, `BitVector`, a view of a member (`SubArray{T, 1, P} where {P <: MutableIndexable{T}}`) |
| `Resizable{T} <: HasLength` | `push!(c, x::T)`, an item at the end; `resize!(c, n::Int)` for `n ≤ length(c)`, the first `n` kept | `T = eltype(Self)` | `Vector`, `BitVector` |
| `Keyed{K, V} <: HasLength` | `d[k::K]::V`, `haskey(d, k::K)::Bool`, `get(d, k::K, default::D)::Union{V, D} where {D}` | `K = keytype(Self)`, `V = valtype(Self)` | `AbstractDict` |
| `HasProperty{N, R}` (`N` an input) | `x.N`, of type `R`: `getproperty` at the constant name `N`, served by a stored field or the member's own `getproperty`; on a value known only by its trait, `x.N` has the declared type, as a declared field's read (§7.9). Declared as a field named by its input, `@const N::R` (§4.3) | — | none; a type joins at each name |
| `Solvable{T}` | `ldiv!(x::AbstractVector{T}, F, b::AbstractVector{T})::AbstractVector{T}`: `x` solves `F x = b` | `T = eltype(Self)` | LinearAlgebra's factorizations that solve (`LU`, `Cholesky`, `CholeskyPivoted`, the `QR`s, `LQ`, `BunchKaufman`, `LDLt`, `SVD`), and `Diagonal`, `UpperTriangular`, `LowerTriangular`, `Bidiagonal` |
| `LinearOp{T}` | `size(A)::Tuple{Int, Int}`, `apply!(y::AbstractVector{T}, A, x::AbstractVector{T})::AbstractVector{T}`: `y` becomes `A x` | `T = eltype(Self)` | `AbstractMatrix`, by `mul!` |
| `BoundedText` | `textbound(x)::Int`, an upper bound on the bytes `print(io, x)` writes; `textbound(T)` for a type, an `Int` or `nothing` | — | `Number`, `AbstractChar`, `AbstractString`, `Symbol`, Dates' `TimeType`, `Period`, `CompoundPeriod` |

- **Base's types join as Base's abstract types,** declared in BaseTraits, which owns the traits: `@implement Indexable{T} AbstractVector{T} where {T}`. A type is a member only where declared: a `Number` iterates in Base but is not `Iterable`, and a string is `Iterable` but not `HasLength` (its `length` is not constant time).
- **A contract states what a membership's check cannot verify:** `length`'s value, that iteration repeats, that a write reads back, the vectors a solver accepts (LinearAlgebra's factorizations take one-based vectors in host memory, views included). The check verifies the operations and their result types. Trait code does not index without bounds checks on a member's `length` alone, and code that preallocates by `textbound` still checks what `print` wrote.
- **Positions start at the member's `firstindex`:** a vector with offset axes is an `Indexable`.
- **The operations use Base's and LinearAlgebra's functions** (`length`, `iterate`, `getindex`, `ldiv!`) where a member's own methods serve them and no untyped method of the function would be hidden (§5.10). `LinearOp`'s `apply!` is BaseTraits' own: a method of `mul!` at the trait would hide `mul!`'s untyped fallback for every matrix (E-281). A member with its own `mul!` joins with a block: `apply!(y, A, x) = mul!(y, A, x)`. A matrix-free member defines `eltype`.
- **`BoundedText` is a constant per type where the width is fixed** (machine integers, `Bool`, the IEEE floats, characters, dates, `Rational` and `Complex` of those) and a value's own bound otherwise (a `BigInt`, a string's code units, a `Symbol`'s bytes; four bytes a character for a string other than `String`). `textbound(T)` lets a writer size a column without visiting its cells.
- `asvector(x::Indexable{T})` is the collection as a read-only `AbstractVector{T}` for plain code, positions `1:length(x)`, without a copy, each read's bounds checked by the member: `IndexableVector{T, C}`. It is an unbounded method (§7.3).
- `HasLength` is not `Base.HasLength`, the value of `Base.IteratorSize`.
- A module that uses BaseTraits and another module exporting the same name gets Julia's usual ambiguity of names.

**Status:** Implemented in TraitWorld `unified` 4be0097 with `unified` 0ce5b7f752 (W-114); `HasProperty` in TraitWorld `unified` a658203 with `unified` 350c5b1c59; tests `basetraits.jl`. The table's contracts follow the prior art of Rust, Swift and Mojo ([the research](../record/collection-and-linalg-traits-research-2026-11-07.md); the user, 2026-11-07: "When it comes to Base Traits and Lin Alg Traits, send out an agent that collects prior art from Rust, Swift, Mojo") and [the review of the choices](../reviews/2026-11-07-basetraits-choices.md); each choice is mine (2026-11-07), listed in [open issues §1](../open-issues.md#1-decisions-waiting-for-the-user). Base's own tests pass with BaseTraits loaded, at their times without it (E-282).

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

**Status:** Implemented: Julia's variance with BaseTraits' memberships (TraitWorld `unified` 4be0097); tests `basetraits.jl`.

### 10.3 Algorithms

- `retain!(f::Callable{Tuple{T}, Bool}, xs::All{MutableIndexable{T}, Resizable{T}}) where {T}` keeps the items for which `f` is `true`, in place, in order. It is Base's `filter!` for trait code. `Callable` erases by default, so a plain function is boxed: `retain!` is compiled once per item type for every function, Julia's included (§7.8). `retain!(compiled_for(f), xs)` compiles it for the function.
- BaseTraits' algorithms have names of their own: a method of Base's `filter!` at a trait would rank below Base's own methods (§6.2) and never run for Base's containers.

**Status:** Implemented in TraitWorld `unified` 4be0097 (W-114).

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

**Status:** Implemented in TraitWorld `unified` e7ff8e2 at `@trait`, at `@implement` and at a member's first use at dispatch; at a module's end and at a method's definition (an override) in TraitWorld 701aaab; a member's check kept at a method's definition and an image's load in 5b3c427 (§5.10); `bounded` in bb78d02 (W-111); ownership, pirates and strict mode in 7adcc94 (W-114). The ambiguity at a membership an error under strict mode on `unified` 0bb8f38830 (E-343); at an image's activation reported at error level after the load on 9f8d7d7c48 with TraitWorld 0aff625 (E-349).

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

**Status:** Planned (the plan's D-3, 2026-11-15; [decisions](../record/decisions.md) §2). Built in TraitWorld `unified` 6f86b4e (W-151; `check_definitions` and the `bounded` refusal read the box), with [compiler C-115](compiler.md#deviations); the failure at the definition in a trait module, and so while a package is precompiled (TraitWorld `unified` bb78d02, W-111).

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

**Status:** `ImplementError` and `TraitUseError` in TraitWorld `unified` e7ff8e2; `OwnershipError`, `PirateError`, `NotFullyTypedError` and `AbstractTypeError` in 7adcc94 (W-114). A concrete part refused at a call (§14) raises `TraitUseError`: mine (2026-11-07). The form of a message: TraitWorld 6a8ee7f and 158d000 with `unified` dd3f6d839b (`test/messages.jl`; E-362), mine (2026-11-11); the messages against plain Julia's for the same mistakes: [evidence §4d](../design/evidence.md#4d-error-messages-against-plain-julias). A check's error raised at the user's line: TraitWorld 399f389 with `unified` 8f42ba7ed7 (`test/messages.jl`), mine (2026-11-12; [decisions](../record/decisions.md) §2). An operation called outside its declared signature as Julia's `MethodError` with the contract's hint: Planned (D-4), with T-120. A pirate reported where it ends deep-G2 code: §12.2. A port's run-time failures: [open issue 177](../open-issues.md#2-design).

### 11.4 Hints

The library adds hints to Julia's `MethodError` where a trait is involved:
- **a value that is not a member** of a trait a method takes: "`Circle` is not a member of `ColTable`; `@implement ColTable Circle` declares it", with the trait's declared members where few;
- **a member at other parameter values:** "`v` is a member of `StateVector{Float32}`; the method takes `StateVector{Float64}`";
- **a broken shared variable:** "`T` is `Float64` for `a` and `Float32` for `b`";
- **a call at an operation's function outside its declared signature:** the declared signature and its trait, read from the contract, "`col` is declared `col(t::ColTable, i::Int)::Vector{Float64}` by `ColTable`". It is given where an argument at the operation's receiver position is a member of the trait, so a failed call names the contract it missed;
- **an ambiguity between two traits:** the joint method to define, `f(::All{ColTable, RowTable})`.

**No hint at an operation that is another owner's function.** `Indexable` declares Base's `getindex` as its operation. A failed call of `getindex` says nothing of `Indexable`: the hint is given at an operation whose function the trait's owner owns.

**Status:** Implemented in TraitWorld `unified` 7adcc94 (W-114), as hints on Julia's `MethodError`; the ambiguity's joint method is Julia's own message on `unified` (`f(::All{X, Y})`), so the library adds none. No hint at another owner's function: TraitWorld 99c4934, mine (2026-11-11; E-363). The declared signature read from the contract, where no method at the trait takes the call: Planned (D-4), with T-120. The SciML error cases' gate: T-99.

---

## 12. Ownership, pirates, strict mode

### 12.1 Who may declare a membership

- A package **owns** the functions and types it defines, traits included. Julia (Core, Base, the standard libraries) is one owner. A package extension counts as its parent.
- **At the prompt,** `Main` is one owner, and each module defined directly under `Main` is an owner of its own.
- **A membership is declared by the trait's owner or the type's owner.** A membership by a package that owns neither is a pirate's (§12.2).
- A membership for a foreign trait and a foreign type belongs in the trait owner's package extension. **A membership in a package extension names each of the extension's triggers** (each owns the trait or a type the declaration names); otherwise whether a type is a member would depend on which packages happen to be loaded. It is refused with `ImplementError`.
- **An operation that is an existing function** (`Base.size`) may be served by methods in a block only for types the declaring package owns. Otherwise declare the type's existing methods: `@implement Sized Vector{Float32}`.
- **Joint owners:** a package may name packages that own its functions and types with it (`@joint_owners DiffEqBase OrdinaryDiffEqCore`, at the top level of its own module). They are owners wherever the declaring package is one: memberships, pirates, strict mode's stakeholders. Not symmetric, not transitive; a joint owner's extension is a joint owner too. A joint owner's change is a stakeholder's change ([facts §2.2](facts.md#22-g2-stable-caches)).

**Status:** Implemented in TraitWorld `unified` 7adcc94 (W-114): `owner`, `@joint_owners`, `OwnershipError` at `@implement` and for a block's methods, an extension's triggers; tests `ownership.jl`. Open: whether the standard libraries are owners of their own ([open issues §1.19](../open-issues.md#1-decisions-waiting-for-the-user)).

### 12.2 Pirates

- **A membership of a trait you do not own, for a type you do not own, is a pirate's too, and behaves as a pirate's method.** It is followed, with a warning that names the owners, and the code that relied on its absence is compiled again. A scope that declares `no_pirates` refuses it (`OwnershipError`). Under strict mode it is refused where it would change code compiled by facts (§12.3). At the prompt, `@implement` of a package's trait for a package's type is such a membership.
- A **pirate** is a method of a function you do not own, for types you do not own: Julia's type piracy. A trait you own is a type you own; a `Union` with your own type or a lower-bounded type variable is no way around it.
- **A method of another package's owner-only function is a pirate's, whatever types it names.** An owner-only function's methods are its owner's ([facts §1](facts.md#term-owner-only)):
  - by default, each function of a trait module, or of any module that declares `facts`, that the module neither exports nor declares `public`;
  - by declaration, any function of the owner's module, exported or not: `@owner_only f g`, at the module's top level.
  - So code compiled by facts infers every call of such a function as plain Julia does ([facts §3](facts.md#3-fact-signatures)): its owner is the only one who changes where the call goes.
  - To let other packages extend a function, its owner declares it `public` or exports it, or names them as joint owners (§12.1). Base's internal functions are not owner-only: packages extend them.
- **A scope that declares `no_pirates`** refuses one at its definition (`OwnershipError`).
- Elsewhere a pirate is followed, as in Julia; code compiled by facts that it changes is compiled again once ([facts §11](facts.md#11-pirates-and-strict-mode)).
- **A pirate is reported where it ends deep-G2 code** ([facts §1](facts.md#term-deep-g2), [§2.2](facts.md#22-g2-stable-caches); [compiler §3.2](compiler.md#32-g2-as-a-predicate)): code that nothing but a stakeholder's change or a pirate can end. A warning names the method, its definer, who owns neither the function nor a type in it, and the code compiled by facts it ended. So every pirate that costs such code is told, and no other:
  - **reported**, by default: when its definition ends such code, and when an image's code that its method makes invalid at the image's load is such code;
  - **refused**, in strict mode (§12.3), where it would win at a fact;
  - **silent** only by choice: `TraitWorld.report_pirates!(false)`, or `JULIA_TW_PIRATES=0` at start.
  - The report costs nothing where no such code ends: the invalidation that ends the code holds the method already. A pirate's membership is reported the same way, beside its warning at the declaration.

**Status:** Implemented in TraitWorld `unified` 7adcc94 (W-114): the definition hook refuses a pirate in a `no_pirates` scope. A method of another's owner-only function as a pirate's, and `@owner_only`: Planned (the plan's D-9, 2026-11-15), with T-121; the form `@owner_only` is mine (2026-11-15). A pirate's membership: TraitWorld dbfb488 (W-140, stage 1; `test/ownership.jl`); by the method's rule, in a `no_pirates` scope and under strict mode: TraitWorld a2ca7be with `unified` 7fee959383 (`test/ownership.jl`, `test/strict.jl`): the user (2026-11-12; [decisions](../record/decisions.md) §4). A pirate reported by default where it ends deep-G2 code: Planned (the plan's D-12, 2026-11-15), with T-123 and [compiler C-105](compiler.md#deviations); the switch's name and spelling are mine (2026-11-15).

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

**Status:** Implemented in TraitWorld `unified` 7adcc94 with `unified` 5f2373b2d5 (W-114): the refusal before the definition, the check after it, the image hook, the report after a load, the deletion hook; the earlier library's strict-mode cases pass (`test/strict.jl`). An ambiguity at a membership refused on `unified` 0bb8f38830 with TraitWorld 960b99e (`test/strict_membership.jl`, E-343). An ambiguity at an image's activated membership reported at error level after the load and kept (`TraitWorld._LOAD_AMBIGUITIES`) in TraitWorld 0aff625 with `unified` 9f8d7d7c48 (gate `stack/strict_activation.jl`, E-349): mine (2026-11-10). The report at error level, kept (`TraitWorld._LOAD_MEMBERSHIPS`), in TraitWorld 048c44e (gate `stack/strict_load_membership.jl`, E-353): mine (2026-11-10); only the check instances that fail validation inferred again: Planned (D-3), with T-129. A pirate's membership by the method's rule: TraitWorld a2ca7be with `unified` 7fee959383 (`test/strict.jl`; gate `stack/strict_pirate_membership.jl`): the user (2026-11-12). With T-96, T-97, T-112. The warning at an extension's method: TraitWorld 12b8b31 (stack gate `strict_extension_method`).

---

## 13. Scopes: trait modules

```julia
module Geometry
using TraitWorld
@trait_module                     # facts, bounded, no_pirates
@trait Shape begin … end
area_sum(shapes::Iterable{<:Shape}) = …
end
```

- **`@trait_module`, before the module's first method,** declares options for every method of the module, its submodules included:
  - **`facts`:** its methods are compiled by facts ([facts §6](facts.md#6-which-code-is-compiled-how));
  - **`bounded`:** an unbounded method at a trait argument is refused (§7.3);
  - **`no_pirates`:** a pirate is refused (§12.2).
- Each is on unless written otherwise (`@trait_module bounded = false`).
- **No option decides how a trait argument is compiled:** the value's type does (§7.5).
- A method may set an option for itself: `@bounded f(…) = …`, `@facts f(…) = …`; `@unbounded f(…) = …` exempts it from `bounded` (§7.3).
- The module's statements are Julia's; nothing is rewritten. Revise and other tools that read a module by its statements see an ordinary module.
- At the module's end, methods whose check waited for later definitions are checked (§7.3).
- Concreteness and fully typed mode (§14) take the same places: before `@trait_module`, for the module; before a method, for it.
- Traits, memberships and methods at traits work in any module; a scope decides only these options.

**Status:** Implemented in TraitWorld `unified` bb78d02 (`@trait_module`; W-111; the user, 2026-11-06, Q2 (a)). The three options and no other: the plan's D-1 and D-14 (2026-11-15); the library still accepts `dynamic` and `first_seen` (T-127).

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
- A call that only a build resolves (a value typed `Any` passed to a function with one method that is not owner-only) is fully typed when closed, and is dispatched when it runs in a session.
- Code whose calls all have known argument types pays nothing for the facts mode.
- `@warn_not_fully_typed` warns at a method's first run at a signature; `@enforce_fully_typed` raises there, at every run, `NotFullyTypedError`: the code has a call it cannot resolve when compiled, in it or in what it calls. A method in either mode is compiled by facts. Fully typed code pays nothing for either.
- `fully_typed(f, argtypes)` reports the calls that are not fully typed when closed, with their root cause through any number of layers, in the trait's terms ("field `data` of `HasData` is declared `AbstractVector`"). It lists apart the calls a build resolves and a session leaves to run time. `isfullytyped(report)` answers for a closed build; `isfullytyped(report; session = true)` for a session too.
- **The report is the closed build's own check,** run in the session ([compiler §2.7](compiler.md#27-fully-typed-mode)): the calls it lists are those a build from that signature refuses. It has every member the session has: a value known only by its trait that is passed to a method at the trait, or wrapped with `compiled_for`, is resolved by the members and is no fault. A call inside Base that the build refuses is listed at the call in the user's code that leads to it, with the root cause there.
- **Operations on a value the code knows only by its trait count as declared,** not as faults (§7.9).
- **A result of an abstract type is no fault.** A type is a fault where it is used: a call on such a result is a call the caller cannot resolve, and the report of the caller names the result as its root cause. A method that wants a concrete result asks for it: `@enforce_concrete_only result` before the method raises `AbstractTypeError` at a signature whose result is not concrete.
- **Fully typed code is exactly the code that compiles ahead** (§16). A method that is fully typed at a signature builds in a closed build from that signature, with no call left to run time. A method that is not is refused by the build, at the calls `fully_typed` reports. So the check in a session answers for the build, and the build's report is `fully_typed`'s.
- **The modes raise where a build would refuse.** `@enforce_fully_typed` and `@warn_not_fully_typed` ask the same check: code with a call that a session leaves to run time and a build resolves by the members runs without a fault.

**They differ.** Concrete parts do not make code fully typed (a `Vector{Any}` argument, an abstract declared result can each leave a call unresolved). Fully typed code is checked at the signatures it ran at; concrete parts are promised for every member.

**Status:** Implemented in TraitWorld `unified` 7adcc94 with `unified` 5f2373b2d5 (W-114; [compiler §2.7](compiler.md#27-fully-typed-mode)); tests `fullytyped.jl`, acceptance case `AC_16`, gate `n9_fully_typed`. With T-100, T-101. Fully typed as exactly what compiles ahead, the report as the build's own check: Implemented on `unified` 381cc8b953 with TraitWorld `unified` 78a78af (W-142; E-369: the check and the build agree on 17 of 18 programs), with T-109; the check as the build's code run in the session, and the modes raising only where it refuses: mine (2026-11-12; [decisions](../record/decisions.md) §6). The abstract result as no fault, and `@enforce_concrete_only result`: Implemented on `unified` 22db66e23c with TraitWorld `unified` d804c78 (W-142; gate `n9_fully_typed`, test `fullytyped.jl`); the user (2026-11-11): "I meant 2 not 1. So 2, 3, 4 with Kept is agreed. We can think about syntax sugar for this later.". The name `result`: mine (2026-11-11). The modes' check in the compiler: mine (2026-11-07). A trait as a concrete parameter value is mine (2026-11-06), as Rust's `Vec<Box<dyn Trait>>` and Swift's `[any P]` are concrete. Fully typed with the setting as its parameter, in a session and when closed, and the report's two lists: mine (2026-11-15; the plan's D-10), with T-122.

---

## 15. Printing

- **A box** prints as `Dynamic{Shape}(Circle(1.0))`, **a wrapper** as `Compiled(Circle(1.0))`. A signature prints the kept form's type, as Julia prints any type: `colmean(::Dynamic{ColTable}, ::Int64)`.
- A trait prints as the type it is.

**Status:** Implemented: `Dynamic{X}`'s printing in TraitWorld `unified` 745056c (W-111), the wrapper's in 5e2ef71 (W-151).

---

## 16. Compiling ahead, closed programs

- **While a package that declares `@implement X T` is precompiled,** the code that `T` needs is compiled into that package's image. That covers every method at `X` and its supertraits with one trait argument that does not erase, bounded there, at `T`'s type, where the other arguments are concrete. Their checks run then; a failing check fails the build.
- A method with several trait arguments is compiled at its first call.
- **A method at a trait that erases by default** runs one instance for every member, at the box. It is compiled where the method is defined, by its definition-time check (§11.2), and kept in that package's image. A member's package compiles nothing of it.
- Compiling ahead adds no method, so it invalidates nothing.
- **A closed build compiles generic code for the members it has,** as Rust and Mojo do with a trait bound. A session keeps the set of members open, so code compiled once for a box reaches a member through a call that is resolved when it runs (§7.9). A build under `juliac --trim` has every member:
  - a build compiles what is written, as a session does: a plain member at a method of a trait that erases by default is boxed, a box's code is compiled once per trait instance, a wrapper's for its object's type;
  - an operation on a value known only by its trait (an item of a `Vector{Shape}`, a `Dynamic{Shape}`) branches over every member, each branch a direct call. Past the members it raises `MethodError`;
  - `compiled_for(x)` of such a value branches the same way, each branch the wrapper of the member;
  - the members of a family (`@implement Column{T} Vector{T} where {T}`) are the types the program uses as members: those it stores, passes or returns where only the trait is known ([compiler §7.6](compiler.md#76-a-closed-build)). `JULIA_CLOSED_BUILD_REPORT=1` makes the build list them;
  - so a program whose calls outside the traits are typed builds without a call left to run time, and its binary has no compiler in it.
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
  - a box's code lists every declared member as a target of its operations;
  - the wrapper of a value known only by its trait lists, at every declared member, the instances its calls run;
  - a `like` result lists the member's rebuilding;
  - each set of supplied keywords is a signature.
- **The report:**
  - `targets`: every signature the program reaches;
  - `entrypoints`: the targets that no call in the code names (the members', the wrappers' and the `Callable`s'). A build is told these: `add_entrypoints(report)`, called while `juliac` builds, registers them;
  - `holes`: the calls a build refuses, as `fully_typed` lists them;
  - `complete`: false where the walk stopped at its bound (`bound = 100_000` signatures).
- A trimmed binary compiles everything plainly ([facts §13.3](facts.md#133-trimmed-binaries)).

**Status:** `make_executable` and `make_library`: Implemented in TraitWorld `unified` 19862aa (W-139; `test/build.jl`, E-364's `make.jl`): mine in their form (2026-11-11), asked for by the user. A function written at the prompt: Implemented in TraitWorld `unified` 633d6c0 (E-364: entered at a real prompt, built, run); the selection by name from the prompt's history is mine (2026-11-11). The fully typed report as the build's, the check before a build, and the build's Base read by the check: Implemented in TraitWorld `unified` 78a78af with `unified` 381cc8b953 (W-142; E-369: TraitTables' table program is fully typed, builds and runs; `experiments/unification/w139/make.jl`), with T-109; the replacements as an overlay method table read from the build script's files: mine (2026-11-14; [decisions](../record/decisions.md) §6). A closed build compiling generic code for its members: Implemented on `unified` 97861c6b31 ([compiler §7.6](compiler.md#76-a-closed-build); W-139, E-364), for a set whose members are declared at concrete types, at families (`S{T} where T`) or at subtraits; not at an abstract type (compiler C-86). The rest: Implemented in TraitWorld `unified` 05991fc with `unified` 5f2373b2d5 and e81cd49a67 (W-114, W-135): compiling ahead, gate `ahead_two_packages.jl`; `verify_main`, tests `verify.jl`, with T-108. The targets at a value known only by its trait, the entry points and the bound: mine (2026-11-10); a wrapper's in place of a cast's: the plan's D-1 (2026-11-15), with T-127. A build that compiles what is written, and a method that erases compiled ahead at the box: Planned (D-1, D-3), with [compiler C-112, C-114](compiler.md#deviations) and [lowering L-66](lowering.md#15-deviations). Trimmed binaries: E-361 ([evidence §4](../design/evidence.md#4-builds-and-binaries)).

---

## 17. Named implementations

A second way for a type to join a trait, used only where a caller names it, is a wrapper type that joins it: `Via{Fast}(x)`, a newtype. A foreign trait for a foreign type is joined through the user's own wrapper type: `struct FastM; m::M; end` with its own membership.

**Status:** Planned (deferred).

---

## 18. Status index

| Construct | Status | Section |
|---|---|---|
| a trait is an abstract type; membership, transitivity, worlds | Implemented (`unified` 62016706d0) | §3.1 |
| parameters as associated types; invariance, `X{<:T}`; one instance per member | Implemented (`unified` 62016706d0, TraitWorld e7ff8e2); inputs `unified` 350c5b1c59, TraitWorld a658203, but T-105 | §3.2 |
| a family states its instance as a pattern, equations included | Implemented (TraitWorld e7ff8e2) | §3.2, §5.8 |
| a trait wherever a type stands | Implemented (`unified` 29035cab11) | §3.3 |
| a non-membership relied on, with its edge; a pirate's membership | Implemented (`unified` bf447db25e, 80aa919bed, 7fee959383; TraitWorld dbfb488, a2ca7be), with C-76, C-77, C-88, T-112 | §3.4, §12.2 |
| intersections `All{X, Y, Z, …}`; bundles as aliases | Implemented (`unified` 8a9144928e, TraitWorld ae4d250) | §3.6 |
| operations, `where` on operations, the receiver at any position | Implemented (TraitWorld e7ff8e2) | §4.1 |
| an operation as an entry of the contract: no method at the trait for one without a default; `MethodError` with the contract's hint outside the declared signature | Planned (D-4), with T-120, L-63, compiler C-100 | §4.1, §4.2, §11 |
| defaults as the trait's methods, reached by every caller | Implemented (TraitWorld e7ff8e2) | §4.2 |
| declared fields as stored fields | Implemented (TraitWorld e7ff8e2) | §4.3 |
| `Self`; supertraits | Implemented (TraitWorld e7ff8e2) | §4.4, §4.5 |
| `struct S <: X`, declared and checked by `@implement X S` | Implemented (TraitWorld e7ff8e2, 701aaab: the module's end; 0aff625 with `unified` fcdfd0da36: the use before it) | §5.2 |
| one line, block, several traits, stated parameters | Implemented (TraitWorld e7ff8e2) | §5.3–§5.7 |
| forwarding: the member's own methods; a default through the trait's method | Implemented (TraitWorld e7ff8e2; the member's methods W-128) | §5.5 |
| families; abstract types and traits as members | Implemented (TraitWorld e7ff8e2, dd72b10) | §5.8, §5.9 |
| checks at the declaration and at first use | Implemented (TraitWorld e7ff8e2, `unified` ec4f9a8714, fcdfd0da36: at dispatch and before compiled code runs; C-31); kept while a member, also from an image (TraitWorld 6871ea9, E-344); pattern answers in images L-55; the check as kept instances with edges: Planned (D-3, T-129) | §5.10 |
| overrides fixed; redeclaration | Implemented (TraitWorld 701aaab; from images TraitWorld 6871ea9, E-344); a redeclaration's entry (`unified` 62016706d0) | §5.11 |
| a membership taken back, `delete_membership`; Revise on memberships | Planned (D-13), with T-124, L-64, compiler C-106 | §5.13 |
| dispatch: specificity, ambiguity reported at a membership, fallback | Implemented (`unified` 62016706d0, 0d529d33a9, 8a9144928e) | §6.2–§6.4 |
| `like`, `withfields`: the library's conveniences | Implemented (TraitWorld e7ff8e2) | §6.5 |
| keywords, defaults, varargs at traits | Implemented as Julia's (TraitWorld c9f701e under `bounded`) | §6.6 |
| keys and shared code: an optional extension | Optional, built late (W-110; open issue 147) | §7.2; [extensions §1](extensions.md#1-keys-code-shared-among-members-the-contract-sees-alike) |
| bounded methods: the instance at the box, read where a method is defined | Planned (D-3); built in TraitWorld 6f86b4e (W-151), with compiler C-115, T-130; `bounded` and `@unbounded` TraitWorld bb78d02 (W-111) | §7.3, §11.2 |
| the two kept forms, the box and the wrapper; the value's type decides | Planned (D-1); built in TraitWorld 5e2ef71 to 6f86b4e (W-151), with T-126, T-127, compiler C-112, C-113 | §7.4–§7.6 |
| `Dynamic{X}`, the box | Implemented (`unified` e692e57ab7, W-111; TraitWorld 5a9d19d), with compiler C-110, C-113 | §7.7 |
| erasing by default: the forwarder made where a method is defined | Planned (D-1), with T-125, compiler C-110, C-111; the library's `@erasing` (TraitWorld 362f08b) | §4.6, §7.8 |
| operations on a value known only by its trait | Implemented (`unified` e70675a606, W-109) | §7.9 |
| storage typed by a trait; struct parameters; storage keeps the form given | Implemented (Julia's, with TraitWorld e7ff8e2; the conversion into `Dynamic{X}` 5e2ef71) | §8 |
| `Callable`: every function a member; the signature checked at the box and at a wrapper's entry, the result on return | Planned (D-2, W-153), with compiler C-116, L-68; built as the earlier rule (`unified` 5f0a8ffd50, TraitWorld 5d52f0d, W-113) | §9 |
| A closed abstract type with a contract; `IO`'s contract; the eraser `IOContext{IO}` | Implemented (`unified` b05ae361e0) | §3.4, §9b |
| BaseTraits; element types by variance; `retain!` | Implemented (TraitWorld 4be0097, `unified` 0ce5b7f752; W-114; `HasProperty` TraitWorld a658203, `unified` 350c5b1c59) | §10 |
| checks, errors, hints | Implemented (TraitWorld e7ff8e2; definition checking 59134ef, bb78d02; hints and the errors of §12, §14 7adcc94; errors at the user's line 399f389); an operation outside its signature: Planned (T-120) | §11 |
| ownership, joint owners, pirates, strict mode | Implemented (TraitWorld 7adcc94, `unified` 5f2373b2d5; W-114; an ambiguity at a membership refused, E-343, and reported at an image's activation, E-349), with T-96, T-97 | §12 |
| owner-only functions, `@owner_only` | Planned (D-9), with T-121, compiler C-101 | §6.8, §12.2 |
| a pirate reported where it ends deep-G2 code; `report_pirates!` | Planned (D-12), with T-123, compiler C-105 | §12.2 |
| the standard libraries as owners | Open | §12.1 |
| scopes: `@trait_module` and its options `facts`, `bounded`, `no_pirates` | Implemented (TraitWorld bb78d02, W-111), with T-127 | §13 |
| concreteness and fully typed mode | Implemented (TraitWorld 7adcc94, `unified` 5f2373b2d5; W-114; the report as the build's check: TraitWorld 78a78af, `unified` 381cc8b953, W-142), with T-100, T-101, T-109; fully typed in a session listed apart: Planned (D-10, T-122) | §14 |
| printing | Implemented | §15 |
| compiling ahead, `verify_main` | Implemented (TraitWorld 05991fc, `unified` 5f2373b2d5, e81cd49a67; W-114, W-135; the check before a build: TraitWorld 78a78af, W-142), with T-108, T-109 | §16 |
| named implementations | Planned (deferred) | §17 |

---

## 19. Deviations

The library on the unified build is TraitWorld `unified` (its head: [state.md §6.1](../state.md#today)); the lowering's deviations are [lowering.md's](lowering.md#15-deviations), the type system's and dispatch's [compiler.md's](compiler.md#deviations). The rows below are where the library falls short of this reference's guarantees.

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| T-1 to T-95 | — | *Retired* (2026-11-06): the rows of the reference these replaced, in `attic/writeup/reference/traits.md` | — | — |
| T-96 | [§12.3](#123-strict-mode) | Strict mode refuses a binding redefined from another module, through its hook ([compiler §10.2](compiler.md#102-hooks-for-strict-mode)). | No such hook exists: a binding redefined from another module is followed. | `julia-unified` (no hook); TraitWorld `src/strict.jl` |
| T-97 | — | *Retired* (2026-11-14): the warning at an extension's method, at its definition and at its image's load ([§12.3](#123-strict-mode)); stack gate `strict_extension_method` | — | — |
| T-98 | — | *Retired* (2026-11-10): under strict mode an ambiguity at an image's membership activated at load is reported after the load, at error level, in TraitWorld 0aff625 with `unified` 9f8d7d7c48 ([§12.3](#123-strict-mode), [compiler §9](compiler.md#9-images-and-the-machine-code-cache)); gate `stack/strict_activation.jl` (E-349) | — | — |
| T-99 | [§11.4](#114-hints) | The hints are gated on the SciML error cases (the work plan's M8). | The hints are tested on the library's own cases (`test/hints.jl`, `test/messages.jl`). The SciML cases run on the port (E-363) and reach no hint: each is a run-time failure in the user's function, not a call of a method at a trait. They are a measurement, not a gate. | TraitWorld `test/hints.jl`; `experiments/unification/w136/sciml/` |
| T-100 | [§14](#14-concreteness-and-fully-typed-mode) | `@enforce_fully_typed` raises for every call that a build from the signature refuses, in the code or in anything it calls. | The compiled code asks the check only where the session's inference found a run-time site in the code or in a callee compiled by facts. A call that only the build refuses, inside plain code the method calls (Base's, in the product setting), is reported by `fully_typed` and not raised. | `julia-unified` `Compiler/src/facts.jl` (`fully_typed_fault`); TraitWorld `src/fullytyped.jl` (`_fully_typed_hook`) |
| T-101 | [§14](#14-concreteness-and-fully-typed-mode) | Concreteness, like fully typed mode, can be declared for a module before `@trait_module`. | Concreteness is declared per trait and per method only. | TraitWorld `src/fullytyped.jl` |
| T-102 | — | *Retired* (2026-11-14): `like` and `withfields` call the constructor by position, with nothing looked up when they run ([lowering §8](lowering.md#8-like-and-withfields)); `test/core.jl`, stack gate `like_precompiled` | — | — |
| T-103 | — | *Retired* (2026-11-08): `HasProperty` in TraitWorld `unified` a658203 with `unified` 350c5b1c59 ([§10.1](#101-basetraits), [§3.2](#32-parameters)); tests `basetraits.jl`, gate `n10_inputs` | — | — |
| T-104 | [§14](#14-concreteness-and-fully-typed-mode) | `@enforce_fully_typed` raises at every run of a fault. | The check is in the method's code compiled by facts. A plain caller that inlines the method, or propagates constants into it (compiler C-45), runs it without the check. The warning's once-only flag is written into the code's literal. | `Compiler/src/optimize.jl`, `base/experimental.jl`; [the review](../reviews/2026-11-07-implementation-day.md) M7 |
| T-105 | [§3.2](#32-parameters) | An input is never left open where an operation's result needs it: a method whose `where` variable or stated value does not fix it is refused at its definition. | Not checked: such a trait's method is accepted, and the call's result names the open input. | TraitWorld `src/trait.jl` (`_trait_method`) |
| T-106 | — | *Retired* (2026-11-09): `IO`'s contract is Base's, on a closed type ([§9b](#9b-streams-io)) | — | — |
| T-107 | — | *Retired* (2026-11-14): the report's holes are the build's own check's ([§16](#16-compiling-ahead-closed-programs)); what is left is in T-109 | — | — |
| T-108 | [§16](#16-compiling-ahead-closed-programs) | `add_entrypoints(report)` gives an instance at a member to the build through Julia's interface for entry points. | Julia's `Base.Experimental.entrypoint` takes a signature, which names the instance compiled once. The instance at a member is pushed into the compiler's internal list `Base.Compiler._entrypoint_mis`. | TraitWorld `src/fullytyped.jl` (`add_entrypoints`) |
| T-109 | [§14](#14-concreteness-and-fully-typed-mode), [§16](#16-compiling-ahead-closed-programs) | Fully typed code is exactly the code a closed build compiles, and the report's calls are the build's. | The verdicts agree on 17 of 18 programs (E-369). What differs: (1) what the build script changes in Base that is no method is not read by the check: the binding `Base.invokelatest`, which the build makes a direct call (the check reports the call, the build builds: `bb_invokelatest`; the closed rule that removes it is compiler C-103), and eleven functions' `max_args`. (2) Three functions the build script adds are defined in the session's Base as written (`show_typeish`, `invokelatest_trimmed`, `unwrap_val`). (3) The lists of calls are not compared one by one: the report names the call in the user's code above a refused call, the build the call it stopped at. (4) A build's process that loads a package from source, not from its image, runs the package's own workload under the closed rules, and can fail there. (5) At a member of a family that no image has checked, the check in a session leaves calls at the trait unresolved that the build's process resolves, since its queue runs the member's check ([open issue 184](../open-issues.md#2-design) (b)). | TraitWorld `src/fullytyped.jl`, `src/buildbase.jl`; `experiments/unification/w142/` (`agree.sh`, the apps `bb_*`); [open issue 181](../open-issues.md#2-design) |
| T-110 | — | *Retired* (2026-11-12): [§14](#14-concreteness-and-fully-typed-mode) holds the rule, built. | | |
| T-111 | — | *Retired* (2026-11-14): `detect_kept_storage` reports such stores ([§7.8](#78-keeping-an-argument-with-its-attribute)); test `kept.jl`. TraitDifferentialEquations' six sites are the port's (W-104) | — | — |
| T-112 | [§12.3](#123-strict-mode) | Strict mode refuses a pirate's membership that would change code compiled by facts, before it exists. | The check before the declaration walks the edges a method's check walks. The declaration's invalidation log is read after it, as a method's is; code compiled by facts that the walk missed is reported at error level and kept (`TraitWorld._STRICT_MISSES`), and the membership stays: a membership is not taken back yet (§5.13, T-124); once it can be, the miss is undone as a method's is. At an image's load, a family's or an abstract member's membership is checked for the folded answers only, not for the calls. | TraitWorld `src/strict.jl` (`_declare_pirate!`, `_membership_violation`, `_image_membership`) |
| T-113 | — | *Retired* (2026-11-15): [§4.6](#46-erasing-by-default) and [§7.8](#78-erasing-by-default-the-forwarder) state what the library records; what stands in for Julia's forwarders is T-125 | — | — |
| T-114 | — | *Retired* (2026-11-15): [§7.3](#73-bounded-methods) and [§11.2](#112-definition-checking) state what the library reads; how it infers that instance: [compiler C-115](compiler.md#deviations) | — | — |
| T-120 | [§4.1](#41-operations), [§4.2](#42-defaults), [§5.10](#510-checks), [§11](#11-checks-and-errors) | An operation without a default is an entry of the contract and no method at the trait: a call dispatches to the member's own method; a call outside the declared signature raises Julia's `MethodError` with the contract's hint; a method that takes any receiver serves such an operation. | `@trait` defines the trait's method for every operation and arity (lowering L-63): it forwards for `Dynamic{X}`, holds a default's body, and otherwise raises `OperationError`, the library's error type. The member check refuses a serving method that takes any receiver, since the trait's method would hide it (`_hidden_method`). The hints read the trait's methods to find the declared signature (`_trait_hints!` with `_is_trait_method`). The classifier and compiling ahead skip the trait's method as the contract's own (`_is_trait_method` in `classify.jl`, `ahead.jl`). | TraitWorld `src/trait.jl` (`_trait_method`), `src/check.jl` (`_hidden_method`, `_first_serving`, `_is_trait_method`), `src/hints.jl` (`_trait_hints!`), `src/errors.jl` (`OperationError`), `src/classify.jl`, `src/ahead.jl` |
| T-121 | [§6.8](#68-who-may-add-a-method), [§12.2](#122-pirates) | A method of another package's owner-only function is a pirate's, whatever types it names: `no_pirates` refuses it, strict mode refuses it where it wins at a fact, and its owner is the one stakeholder of every call of it. `@owner_only f g` declares such functions. | `owned_method` counts a method as no pirate where its package owns the function or a type in each alternative of its signature, whatever the function; strict mode's stakeholders are the owners of the signature's parts (`_stakeholder`, `sig_owners`). There is no `@owner_only`, and no reading of a module's `public` and export lists. A method of another package's internal function at the definer's own type is followed silently and never refused. | TraitWorld `src/ownership.jl` (`owned_method`, `sig_owners`, `_check_pirate`), `src/strict.jl` (`_stakeholder`, `_strict_violation`) |
| T-122 | [§14](#14-concreteness-and-fully-typed-mode) | `fully_typed`'s report lists apart the calls a build resolves and a session leaves to run time; `isfullytyped(report; session = true)` answers for a session. | The report lists the calls the build's check refuses (`Compiler.closed_check`) and the walk's root causes; a call a build resolves and a session dispatches is in neither list, and nothing answers whether code is fully typed in a session. | TraitWorld `src/fullytyped.jl` (`fully_typed`, `isfullytyped`, the report's type) |
| T-123 | [§12.2](#122-pirates) | By default a pirate whose definition, or whose method at an image's load, ends deep-G2 code is reported: the method, its definer, the code ended; `report_pirates!(false)` silences it. | Outside strict mode a pirate is followed silently. The library reads Julia's invalidation log only under strict mode, around a definition or a declaration (`_strict_log_start!`, `_strict_log_hit`), and validation's log at a load only under strict mode (`_validation_log_on!`, `_load_pirates`). There is no `report_pirates!`, and the runtime keeps no list of what a definition ended by class (compiler C-105). | TraitWorld `src/strict.jl` (`_strict_after!`, `_strict_log_hit`, `_validation_log_on!`, `_load_pirates`, `strict!`) |
| T-124 | [§5.13](#513-taking-a-membership-back) | `delete_membership(X, S)` takes a membership back: ownership checked as for a declaration, strict mode's refusal as for a method's deletion, the member's check records forgotten, a pattern's members ended with it; a member by its definition, a supertrait's and `Dynamic{X}`'s memberships are refused. | No such function. The library forgets a member's records only at a redeclaration (`@implement` again), and its kept check answers (`_CHECKED`) never; the runtime offers no way to end an entry (compiler C-106). | TraitWorld `src/implement.jl` (`_CHECKED`, the records of lowering §3, step 7), `src/ownership.jl`, `src/strict.jl` (`_deletion_hook`) |
| T-125 | [§3.5](#35-values), [§4.6](#46-erasing-by-default), [§7.8](#78-erasing-by-default-the-forwarder), [§8.2](#82-a-struct-parameter-bounded-by-a-trait) | Julia makes, where a method at a trait that erases by default is defined, the method at the two kept forms and its forwarder, with nothing written; the forwarder is `@nospecialize` at the argument; Julia's default outer constructors get one too; `Callable`'s methods erase by the same rule. | The library's macro `@erasing`, written at each method definition, stands in: it reads the traits' declarations when the definition is expanded and writes the kept-form method and the forwarders. A method written without it takes a plain member as it is; a method at `Callable` without it still takes Julia's attribute (compiler C-112). Julia's default outer constructors get no forwarder. The forwarder is compiled per member type (`@specialize`) and boxes by the runtime's `jl_new_struct` without the membership test (`_box`, `_new_box`, `_box_plain`), since on this build `@nospecialize` at a trait argument takes the attribute's run-time path (829 ns a call) and `new` tests the membership when it runs (compiler C-110). A forwarder is found by a `:meta` mark in its body (`_is_forwarder`); it is not recorded with the method it forwards to. | TraitWorld `src/erasing.jl` (`@erasing`, `_erasing_def`, `_box`, `_new_box`, `_box_plain`, `erases`, `_is_forwarder`); the ports' methods written with `@erasing` (TraitDifferentialEquations 813808a, NetworkDynamics 946c0dc); E-402, E-407 |
| T-126 | [§7.4](#74-the-two-kept-forms-the-box-and-the-wrapper), [§7.6](#76-compiled_forx) | The wrapper is `Core.Compiled{T}`; `compiled_for(x)`, exported by the library, returns it. | The wrapper is the library's type, `TraitWorld.Compiled{T}`. The library's exported `compiled_for` is still Julia's cast (`import Core: compiled_for`), and the wrapper's function is `TraitWorld.ByType.compiled_for`, which a module binds explicitly (`using TraitWorld.ByType: compiled_for`). | TraitWorld `src/compiled.jl`, `src/TraitWorld.jl` (`module ByType`, the exports); compiler C-113 |
| T-127 | [§2](#2-syntax-summary), [§4.6](#46-erasing-by-default), [§7.5](#75-what-decides), [§8.1](#81-fields-and-containers-typed-by-a-trait), [§13](#13-scopes-trait-modules), [§14](#14-concreteness-and-fully-typed-mode), [§16](#16-compiling-ahead-closed-programs) | Nothing beside a call decides how an argument is compiled: no cast, no `keep`, no `Kept{X}`, no module option `dynamic` or `first_seen`, no `@default_compiled`; storage keeps the form given; `verify_main` and `fully_typed` read wrappers. | The library still offers the attribute's surface, beside the kept forms: it exports the casts `compiled_for` and `with_dynamic` and `keep` (Julia's, compiler C-112), `Kept`, `kept_call`, `isdynamic`, `detect_unused_casts`, `detect_kept_storage`, `detect_dynamic_fallbacks`; `@trait_module` accepts `dynamic` and `first_seen`, and `first_seen` is on unless written (the ports write `first_seen = false`); `@default_compiled` sets the compiler's attribute bit (`jl_set_default_attribute`); `verify_main` lists a cast's targets, and `fully_typed` reads a cast's operand. | TraitWorld `src/TraitWorld.jl` (the exports), `src/kept.jl`, `src/scope.jl` (`@trait_module`, the three `detect_` functions), `src/trait.jl` (`@default_compiled`), `src/fullytyped.jl` (the casts' targets) |
| T-128 | [§7.4](#74-the-two-kept-forms-the-box-and-the-wrapper) to [§7.8](#78-erasing-by-default-the-forwarder), [§8](#8-storage) | The demonstrators follow the design: their code erases by the trait's default or at a door, and chooses code per type with `compiled_for(x)`, a value. | Not converted: TraitTables' four casts (`src/TableCore.jl` 75, 90, 188; `src/TraitTables.jl` 52), TraitCSV's one (`src/CSVCore.jl` 123), the forks' Tables (`src/ColumnCore.jl` 98 to 118), TraitMakie, TraitReport, which import the casts and `keep`. TraitDifferentialEquations' `kept_interpolant` keeps a `keep`, and its README and docstrings outside the front end and the callbacks describe casts (TraitRodas' `with_dynamic(ls)`). Converted: TraitDifferentialEquations' front end and callbacks (813808a), NetworkDynamics' kernel (946c0dc). | the demonstrators' `-unified` trees, `forks-unified`; stage 4 of [the plan](../plans/2026-11-15-next-iteration.md) (W-156) |
| T-129 | [§5.10](#510-checks), [§5.11](#511-overrides-and-redeclaration), [§12.3](#123-strict-mode) | A member's check is its serving instances, kept with their edges and validated with an image; a definition that would end one, an operation's own method or one below its body, is judged by inferring that call again with it, found by the walk strict mode runs; at a load only the instances that fail validation are inferred again. | The library infers each serving method's result apart (`check_member`, `_check_contract!`: `Base.infer_return_type`) and keeps the answers as its own records (`_CHECKED`, `_FIXED_CALLS`, `_CHECKED_RESULTS`), made again at a load by a walk without inference (`_sync_image_records!`, `_records_from_entry!`). A definition is judged against the records by one intersection per kept call (`_definition_checks`, `_check_membership_calls`), so a method below an operation's body is not seen ([open issue 115](../open-issues.md#closed-items), closed by rule). Under strict mode every checked call of an image's membership is inferred again at its load (`_LOAD_MEMBERSHIPS`; E-353, E-382: GT-2). | TraitWorld `src/check.jl`, `src/implement.jl` (the records, `_definition_checks`, `_infer_new_method`), `src/strict.jl` (the load's inference) |
| T-130 | [§7.3](#73-bounded-methods), [§7.4](#74-the-two-kept-forms-the-box-and-the-wrapper) | A function of `Self` that an equation names answers through a kept form as for its object: `eltype(d)` of a box of `Iterable{Float64}` is `Float64`. | No such method at the kept forms: `eltype` of a box is Base's fallback, `Any`, so a method that computes with `eltype(t)` gives another type at the box than at the member, and a call made with it (`zero(eltype(t))`) can find no method there. | TraitWorld `src/trait.jl` (no methods of the equations' functions at `Dynamic{<:X}`, `Compiled{<:X}`), `src/dynamic.jl`; [lowering L-67](lowering.md#15-deviations) |
