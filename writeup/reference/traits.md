# Traits: the reference

**Draft** (W-105; [the folder's README](README.md)). This page defines the trait language: what a trait is, how a type joins one, how methods at traits dispatch and are compiled, what is checked, and which errors a user sees. It describes the language as designed. The status line of each section says how far it is built.

- What compiled code may assume: [`facts.md`](facts.md).
- The Julia interfaces the language rests on: [`compiler.md`](compiler.md).
- What the library's macros expand to: [`lowering.md`](lowering.md).
- Terms are defined where they first matter; the [glossary](../glossary.md) links here.

**Status labels:** Implemented, Planned, Proposed, Optional, Open, as [the README](README.md#conventions-for-every-reference) defines them.

## Contents

1. [Overview](#1-overview)
2. [Syntax summary](#2-syntax-summary)
3. [Traits are abstract types](#3-traits-are-abstract-types)
4. [Declaring a trait](#4-declaring-a-trait)
5. [Joining a trait](#5-joining-a-trait)
6. [Methods at traits](#6-methods-at-traits)
7. [Compiling: keys and the attribute](#7-compiling-keys-and-the-attribute)
8. [Storage](#8-storage)
9. [Functions: `Callable`](#9-functions-callable)
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

On top of that, the compiler offers two choices of speed, never of results:
- **Code shared per key:** members that the contract sees alike run one compiled copy of a method (§7.2).
- **The attribute:** a trait argument is compiled per key (`Compiled`) or once for every member (`Dynamic`). The trait, the library and the caller each have a say (§7.4).

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
                 | "@default_dynamic" | "@default_compiled"          (* the trait's default attribute *)
Operation      ::= FName "(" OpArg ( "," OpArg )* ")" "::" Type ( "where" TypeVars )?
FName          ::= Name | Module "." Name
OpArg          ::= Name "::" Type | "::" Type | Name                 (* one argument typed by the trait or Self: the receiver *)

Implementation ::= "@implement" Traits Member How?
Traits         ::= Type | "(" Type ( "," Type )* ")"
Member         ::= Type | Type "where" "{" TypeVar ( "," TypeVar )* "}"
How            ::= "begin" MethodDef* "end" | "by" FieldName

Scope          ::= "@trait_module" Option*                           (* before the module's first method *)
Option         ::= "facts" | "bounded" | "no_pirates" | "dynamic" | "first_seen" | Name "=" Expr
Concrete       ::= ( "@enforce_concrete_only" | "@warn_on_abstract" ) Name*
FullyTyped     ::= "@enforce_fully_typed" | "@warn_not_fully_typed"
Cast           ::= "compiled_for" "(" Expr ")" | "with_dynamic" "(" Expr ")"   (* only as an argument of a call *)
```

**Status:** Implemented in TraitWorld `unified` e7ff8e2 for `@trait` and `@implement` (W-106); `@trait_module`, `@default_dynamic` and casts W-111, concreteness W-114.

---

## 3. Traits are abstract types

### 3.1 Membership

- `S <: X` holds when `S` is a member of the trait `X`, and `s isa X` when `s`'s type is.
- A type becomes a member:
  - **with its definition:** `struct S <: X … end`, declared and checked by an `@implement X S` after its methods (§5.2);
  - **after its definition:** `@implement X S` (§5.3 to §5.9), by a stakeholder (§12.1);
  - **through another membership:** membership is transitive. `S <: B` and `B <: A` give `S <: A`, whether each link is a declared supertype, a membership, or a trait's membership in another trait.
- **Memberships only grow.** A membership holds from the world in which it is declared. A task running in an older world does not see it. Once declared, a membership is never withdrawn; it may be redeclared (§5.11). `Callable`'s memberships are derived from the method table and follow it (§9).
- **What may be a member:** a concrete type; a family of types (`S{P} where P`); a closed abstract type (`AbstractVector{T}`); another trait. A trait is never a member of a closed abstract type. A trait's declared supertype is `Any` or a trait.
- **A type value** is a member only by its own membership: `@implement CellParser Type{Int64}` makes `Int64 isa CellParser` true. `S <: X` and `S isa X` are different questions, as in Julia.
- **Never members:** Core's kinds (`DataType`, `UnionAll`, `Union`, `TypeVar`, `Module`), the builtins' types, opaque closures, the memory types.

**Status:** Implemented in Julia's type system on branch `unified` 62016706d0 ([compiler §4](compiler.md#4-sets-and-memberships), with its deviations); `@trait` and `@implement` in TraitWorld `unified` e7ff8e2.

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

**Status:** Implemented on `unified` 62016706d0 (subtyping) and in TraitWorld `unified` e7ff8e2 (the checks), but for a member at several values of an input, which the runtime refuses as a second instance (compiler C-32). A family states its instance as a pattern, an equation's parameter included (§5.8): mine (2026-11-06; open issue 140).

### 3.3 Where a trait stands

A trait is written wherever a type is written:
- in any method's signature, in any module: `f(t::ColTable)`, `f(v::AbstractVector{<:Shape})`, `f(x::T) where {T <: Shape}`;
- as a field's type, a type parameter, an element type: `model::Model`, `Vector{Shape}`, `Dict{String, Shape}`, `Ref{Shape}`, `Union{Nothing, Shape}`;
- as a struct parameter's bound: `struct Problem{F <: Model}`;
- in `isa`, `<:`, `typeassert`, `convert(X, x)`, `Type{<:X}`;
- as a declared supertype: `struct S <: X`, `abstract type A <: X`.

**Status:** Planned (W-98, W-99).

### 3.4 Open and closed

- **A trait is open:** members may join after their definition.
- **An abstract type is closed:** `abstract type A end` has members only through `struct S <: A`. Base's and Core's abstract types are closed.
- A closed abstract type may be a member of a trait (`@implement Indexable{T} AbstractVector{T} where {T}`); then every subtype of it is a member.
- Compiled code relies on a membership that holds, never on one that does not, for an open trait: a later membership must find the code right (§6.2, [facts §10](facts.md#10-memberships)). For a closed type, Julia's rules apply unchanged.
- **Sealed traits,** whose members all join with their definition or in the member's own package, may rely on non-membership too: Optional ([PE-19](../record/performance-explorations.md)).

**Status:** Planned.

### 3.5 Values

- **A member's value is a value of the trait.** Passing it to `f(t::X)` passes it; nothing converts or wraps it. In the body, `t` is the caller's object: `typeof(t)` is its own type, and `t === x` holds for the `x` passed.
- A field or container typed by a trait holds its members' values, as one typed by an abstract type does (§8).

| | A closed abstract type | A trait |
|---|---|---|
| How a type joins | in its own definition, `struct S <: A` | in its definition, or later by `@implement X S` |
| Who may make it join | the type's author | a stakeholder: the type's owner or the trait's |
| How many | one supertype, so one chain | any number of traits |
| What joining promises | nothing that is checked | the trait's contract, checked |
| Parameters | invariant; fixed by the subtype's definition | invariant; one value per member, by field, equation or statement |
| Dispatch | by subtyping | by subtyping, with a type's own supertypes before a trait (§6.2) |
| What code is compiled for | the argument's type | the member's key where the method is fully bounded (§7) |

**Status:** Planned.

### 3.6 Intersections

```julia
f(t::All{ColTable, RowTable}) = …                  # a member of both
const Table = All{ColTable, RowTable}              # a bundle: a name for the intersection
Dynamic{All{Shape, Placed}}(x)                     # kept with both traits
```

- `All{X, Y, Z, …}` is the type of the values that are members of each, for any number of components. `S <: All{X, Y}` holds when `S <: X` and `S <: Y`.
- It is a subtype of whatever one of its components is a subtype of, and more specific than each component. An intersection with a closed component ranks as a closed type against an open set (§6.2).
- Components are flattened, sorted and deduplicated. A component that is a subtype of another by declared supertypes absorbs it; a membership never does, so an intersection's form does not depend on the world. Two closed types with no common subtype give `Union{}`.
- At an argument typed by an intersection, the key is the member's keys for each component (§7.2), and an operation's split takes the first component's members that are members of every component (§7.9).
- A bundle is a `const` alias of an intersection. Its members are every type that is a member of all of its components, whoever declared them.
- `@implement (X, Y) S` declares both memberships (§5.6).

**Status:** Planned (W-107; the user, 2026-11-06: Q5 (a), "spelled All{X,Y,Z,...}").

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

**What is checked.**
- At each membership: a method applies at the member and the declared further argument types, or a default or a forwarding field serves the operation; its result infers to a subtype of the declared result.
- At a call on a value whose type the code knows only as the trait: the result is asserted to the declared type (§7.9).

**Status:** Implemented in TraitWorld `unified` e7ff8e2 at each membership; the result's assertion at a call through the trait: W-109.

### 4.2 Defaults

```julia
describe(s::Shape)::String = "a shape of area $(area(s))"
```

- A default is an operation with a body, written with the trait's other operations and fields. The trait's parameters are in scope.
- **It is the trait's method for that operation**, a method at the trait. A member's own method is more specific and wins (§6.2).
- **Every caller reaches it:** plain code that calls `describe(c)` on a member without its own method gets the default.
- Which operations a default serves for a member is fixed at its membership (§5.11).
- Rust's and Swift's default methods are reached by every caller in the same way, as a method on an abstract type is in Julia.

**Status:** Implemented in TraitWorld `unified` e7ff8e2; mine (2026-11-06).

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
- A computed property is not a declared field. It is the operation of `HasProperty{N, R}` (§10.1).
- The declared fields' types are part of the key (§7.2). A field declared at an abstract type is read at that type, and operations on it dispatch when they run.
- **State some members write and others only read** is two traits: one that declares the field `@const`, and a subtrait that adds the operations that change it.

**Status:** Implemented in TraitWorld `unified` e7ff8e2 (the user, 2026-11-06, Q7 (a)). Swift's protocol properties are the conforming type's own properties in the same way.

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

### 4.6 The trait's default attribute

`@default_dynamic` or `@default_compiled` in the body sets how the trait's arguments are compiled where nothing stronger decides (§7.5).

**Status:** Planned (W-111); mine (2026-11-06).

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
- **It invalidates no compiled code:** a call that the new membership could change is guarded ([facts §10](facts.md#10-memberships)).

**Status:** Implemented in TraitWorld `unified` e7ff8e2, but as lowering L-52 says.

### 5.2 With the type's definition

```julia
struct Circle <: Shape; r::Float64; end
area(c::Circle) = π * c.r^2
perimeter(c::Circle) = 2π * c.r
@implement Shape Circle                    # declares and checks the membership
```

- `struct S <: X` makes the trait `X` the supertype of `S`, as for any abstract type: `S <: X` holds from the definition.
- **The membership is declared by `@implement X S`,** in the same module, after `S`'s methods. It checks the contract (§5.10) and fixes the key. A membership is always declared, and checked where it is declared.
- **A use of `S` through `X` before the `@implement`** (a call that needs `S`'s key) raises `ImplementError` naming the missing declaration. The `@implement` then replaces that failure. A module that ends with a `struct S <: X` and no `@implement X S` is refused at its end.
- `struct S <: X{Float32, 1}` states parameters; the `@implement` may repeat them.
- `abstract type A <: X end` likewise needs `@implement X A`; every subtype of `A` is then a member, each checked at its first use (§5.9).

**Status:** Implemented in TraitWorld `unified` e7ff8e2 for the declaration and its check; the use before it and the module's end: W-108 (lowering L-52) ( the user, 2026-11-06, Q8 (c): "declared membership stays as a design goal"). The refusal at a module's end uses Julia's module-end hook ([compiler §10.1](compiler.md#101-definition-and-image-hooks), Planned).

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

- Every operation is served by the field `right`. The field's type is the **receiver type** and `Self`.
- The field's type must be a member by its own methods or defaults. **Forwarding does not chain.**
- The forwarding field may not also be a writable declared field.
- **The trait's method for each operation** serves a forwarding member: it calls the operation on the field. Every caller reaches it, as for a default (§4.2).
- A trait that requires a concrete `Self` (§14) refuses a forwarding field of an abstract type.

**Status:** Implemented in TraitWorld `unified` e7ff8e2; the trait's method serving a forwarding member is mine (2026-11-06).

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
- **Where an equation defines a parameter** (`T = eltype(Self)`), the family states it as a type expression of its variables: `@implement Iterable{T} Wrapped{T} where {T}`. Each member's check compares the equation's value with it. A family whose instance cannot be written so is refused, naming the parameter. Rust writes an associated type in a generic `impl` the same way.

**Status:** Implemented in TraitWorld `unified` e7ff8e2, each member checked at its first use at dispatch (compiler C-31); a variable bounded by a `Union` declared per type in dd72b10.

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
- For a member of a family, of an abstract type or of a trait: at the member's **first use**, the first time a call needs its key when the program runs: a method at the trait, or an operation through the trait's method ([lowering §4](lowering.md#4-members-checked-at-their-first-use)).
- The result is kept with the member; a package image keeps it, and a later session does not check again while the methods that serve the member are the same.

**What.**
- **Who:** the declaring package owns the trait or the type (§12.1).
- **Completeness:** every operation is served at the member; every declared field exists with the declared type.
- **Results:** each serving method's result infers to a subtype of the declared result. A result that infers wider is refused; the fix is the member's inference (a concrete field type, a type parameter), not an assertion.
- **Fields:** §4.3.
- **Parameters:** fields define them consistently; equations agree with stated values; values within their bounds; one instance per member (§3.2).
- **Supertraits:** §4.5.
- **Concreteness:** where the trait asks for it (§14).

**A failure** raises `ImplementError` (§11.3).
- At a declaration, the declaration then declares nothing: no membership and no methods.
- At a first use, the member stays a member (memberships only grow), and every use of it through the trait raises the same `ImplementError`.

Not everything is caught: a conversion that fails at run time is not proved by the check.

**Status:** Implemented in TraitWorld `unified` e7ff8e2 at a declaration and at a first use at dispatch; images keeping the answers: W-108.

### 5.11 Overrides and redeclaration

- **Which operations defaults serve for a member is fixed at its membership.** A later method of such an operation for the member is refused when it is defined (`ImplementError`). The message names the fix: define the method before the membership, or in its block. A package image that brings such a method is refused when it loads.
- **Redeclaring a membership** replaces it. The new one holds from its world; the old one ends there; code compiled for the old one is invalidated. It is a stakeholder's change ([facts §2.2](facts.md#22-g2-stable-caches)).

**Status:** Planned (W-108, the definition hook); a redeclaration's new entry on `unified` 62016706d0.

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
- Its body may do with the argument what any body may do with an abstract-typed argument. What the body does decides how the method is compiled (§7.3), never what it means.

**Status:** Implemented in Julia's dispatch on `unified` 29035cab11 ([compiler §5](compiler.md#5-dispatch)); how a method is compiled (§7.3): W-109.

### 6.2 Specificity

- **At each argument: a closed type other than `Any` is more specific than a trait.** `describe([1.0 2.0])` takes the `AbstractMatrix` method, although `Matrix{Float64}` is a `ColTable`. So a later membership never takes a call from a method on the type's own supertypes, and a library adopts traits one function at a time.
- **Between traits:** by subtyping. A subtrait is more specific than its supertrait; an intersection than each of its components. Unrelated traits are unordered.
- `Any` is the least specific, as always.

**Status:** Implemented on `unified` 62016706d0 ([compiler §5.2](compiler.md#52-specificity)), but for intersections (W-107).

### 6.3 Ambiguity

- **As in Julia:** a call where two methods apply and neither is more specific raises `MethodError` (ambiguous).
- **Reported earlier, at a membership:** where a membership makes a type a member of two traits, and a function has methods at both with no more specific method for the type, a warning names the function, the two methods and the joint method to define (`f(::All{ColTable, RowTable})`). Under strict mode it is an error (§12.3). A method that dominates every common member suppresses the report.

**Status:** Implemented on `unified` 0d529d33a9 for a concrete member ([compiler §5.4](compiler.md#54-the-ambiguity-report-at-a-membership); C-29 for a pattern): the warning names the function, the two traits and the joint method's signature at the member; `f(::All{…})` with intersections (W-107); the error under strict mode with W-114.

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
  - on a `Dynamic{X}`: a `Dynamic{X}` of that value.
- **`withfields(t; name = v, …)`** is `t` rebuilt with declared fields replaced.
- **A method whose result is built by `like(t, …)` or `withfields(t; …)` is compiled per type at `t`:** its result's type is `t`'s family.

**Status:** Implemented in TraitWorld `unified` e7ff8e2; the compilation per type is mine (2026-11-06), as Rust and Swift compile a function that returns `Self` per type.

### 6.6 Keywords, defaults, varargs

- As in Julia. A positional default makes two methods; a keyword typed by a trait raises `TypeError` for a value that is not a member; there is no dispatch on keywords.
- **A vararg of members,** `ts::ColTable...`: elements may be different members; code is compiled per tuple of keys (§7.2).

**Status:** Planned.

### 6.7 Constructors

A type's constructor may have methods at traits: `NWState(int::All{IntegratorView, HasSystem}) = NWState(sysnet(int), ustate(int))`. The type's other constructors stay, its default ones included.

**Status:** Planned.

### 6.8 Who may add a method

As for any method (§12.2): a package may add a method to a function it owns, or to another package's function where a type in the signature is its own. A trait it owns counts.

**Status:** Planned.

---

## 7. Compiling: keys and the attribute

Everything in this chapter is a choice of speed. Results never depend on it.

### 7.1 Three ways to compile an argument

At each argument typed by a trait, a method is compiled:
- **per type,** as Julia compiles: one copy per concrete type;
- **per key:** one copy per key (§7.2), shared by every member with that key. Optional: until keys are built, a method compiled per key is compiled per type;
- **once:** one copy for every member, at the trait's parameter values.

Which one: §7.3 and §7.5.

**Status:** Implemented: per type, Julia's; once for a `Dynamic{X}` (TraitWorld e7ff8e2); W-111: the attribute that chooses. Per key: Optional, to be built late (W-110; the user, 2026-11-06: "keys as optional is approved", and "Keep them optional and build them late"). A use case to investigate, traits with operations only: [open issue 147](../open-issues.md#2-design).

### 7.2 The key

- **The key of a member** is what the contract sees of its type:
  - the **receiver type**: the member when it serves at least one operation by its own methods, or when the trait's declarations name `Self` or a parameter that no field defines; the forwarding field's type when it forwards (§5.5); none when defaults serve every operation;
  - the declared fields' types;
  - the trait's parameter values.
- **Members with equal keys share compiled code.** Every type that forwards `ColTable` to a `Vector{Vector{Float64}}` field runs the code compiled for that key, including code in the library's package image. Fields the trait does not declare never cause a compile.
- **A member that serves an operation by its own method has its own key,** since it is its own receiver type.
- **A field or forwarding field of an abstract type** is part of the key as it is: one copy for it, whatever it holds; operations on that part dispatch when they run.
- With several trait arguments, a method is compiled per tuple of keys.
- **At an argument typed by an intersection** `All{X, Y}`, the key is the member's key for each component; members with equal keys for every component share code.
- A key prints as `ColTable at Vector{Vector{Float64}}` (§15).

**Status:** Optional (W-110; the user, 2026-11-06: "keys as optional is approved"; [compiler §6](compiler.md#6-keys-and-the-attribute)). What keys need is Planned in the stages before them: the classification (§7.3, W-109), the contract on the trait's `TypeName` and the receiver each membership records ([compiler §4.1](compiler.md#41-sets), [§4.2](compiler.md#42-memberships); W-98, W-106). Built late; a use case to investigate, traits with operations only: [open issue 147](../open-issues.md#2-design).

### 7.3 Fully bounded methods

A method is **fully bounded** at a trait argument when its body reaches the argument only through the contract:
- an operation of the trait or of a supertrait, with the argument as receiver or as a further argument;
- a declared field, read or written;
- passing it on to an argument typed by the trait or a supertrait, or to an unannotated function of the same module that is itself fully bounded at that argument;
- storing it in a slot typed by the trait or a supertype;
- returning it;
- `===` and `isa` against the trait or a supertrait;
- a function of `Self` that one of the trait's equations names, called on it: `eltype(t)` where the trait defines `T = eltype(Self)` (its value is the key's).

Wrapping it as `Dynamic{X}(t)` or `keep(t)` (§7.7, §7.8) stores it in a slot typed by the trait, so it keeps a method fully bounded.

Any other use makes the method **open** at that argument: `typeof(t)`, `isa` against another trait, a call of another function with it, a field the trait does not declare, `like(t, …)` (§6.5). Two common idioms are open:
- **storing it in a struct whose parameter takes its type:** `Problem{typeof(k)}(k, u0)`, or a constructor that sets a parameter bounded by the trait (`CellVector(c)`, §8.2). The struct's type names the member's type, which the key does not fix;
- **capturing it in a closure:** the closure's field takes its type.

- A fully bounded method is compiled per key at that argument where keys are built (§7.2, Optional), per type until then. An open one is compiled per type, or once where the attribute is `Dynamic` (§7.4), its uses beyond the contract then dispatched when they run.
- The compiler classifies each method where it is defined, or at the end of its module or its first call where it calls functions not yet defined. The classification follows the unannotated functions it reaches: a later definition of one classifies the method again.
- **A scope that declares `bounded`** (§13) refuses an open method at a trait argument with `TraitUseError`, naming the use and its line.
- **`@open f(…) = …` marks a method open on purpose:** `bounded` does not refuse it. A library's adapters, which store their argument with its type, are written so; its kernels stay fully bounded.
- **A constructor of a struct whose parameter is bounded by a trait,** where it sets that parameter from its argument, is open by design (§8.2) and never refused: Julia's default constructor, and a library's own. The parameter records the value's type.

```julia
colmean(t::ColTable, i::Int) = sum(col(t, i)) / length(col(t, i))   # fully bounded: per key
colsum(t::ColTable) = sum(t)                    # open: `sum(t)` is not in the contract; per type
@open wrap(t::ColTable) = Wrapped(t)            # open on purpose: Wrapped{typeof(t)}; accepted under `bounded`
```

**Status:** Planned (W-109; the user, 2026-11-06, Q2 (a)). Equations' functions as part of the contract: mine (2026-11-06; open issue 137). `@open`, and the open idioms named: mine (2026-11-06, [the prototypes' review](../reviews/2026-11-06-unified-reference-prototypes.md) H2). Constructors that set a bounded parameter never refused: mine (2026-11-06, E-264).

### 7.4 The attribute: `Compiled` and `Dynamic`

At each call, each trait argument has an **attribute**:
- **`Compiled`:** the code compiled for the value's key (per type for an open method) runs for it. A call whose caller does not know the value's type dispatches on it once, then runs that code: a function barrier.
- **`Dynamic`:** the code compiled once runs for it. Each operation on it dispatches when it runs, and its result has the declared type, so the code after it is typed (§7.9).

Both run the same methods and give the same results, or raise the same error.

**Status:** Planned (W-111).

### 7.5 What decides

For each trait argument of a call, the first that applies, strongest first:
1. **A cast at the call** (§7.6): the caller's override.
2. **An attribute the value carries:**
   - an argument inside code compiled for it keeps its attribute when that code passes it on: code per key passes `Compiled`, code compiled once passes `Dynamic`;
   - a `Dynamic{X}` is `Dynamic` (§7.7);
   - a value read from a field whose declared type is a struct parameter bounded by a trait carries what the parameter records: `Compiled` when the parameter is the value's own type, `Dynamic` when it is a `Dynamic{X}` (§8.2).
3. **The library's default:**
   - at the argument: `@nospecialize t::X` gives `Dynamic`, `@specialize t::X` gives `Compiled`;
   - for the module: the scope's option `dynamic` (§13) gives `Dynamic` to every trait argument of its methods.
4. **The trait's default** (§4.6): `@default_dynamic` or `@default_compiled`. With several traits at one argument (an intersection), it applies where their defaults agree; where they disagree, step 5 decides. **`@default_dynamic` does not apply to a value whose type Julia itself or the trait's own package defines:** those types are few and fixed, so code per type for them is bounded.
5. **Otherwise, the scope's fallback:**
   - in a trait module (§13), **what the caller knows:** a caller compiled with the value's type passes `Compiled`; a call made when the program runs, from code that does not know the type (the prompt, a `Vector{Any}`'s item), passes `Dynamic`;
   - elsewhere, **`Compiled`,** Julia's rule for an abstract type.

Every value not covered by 2 is **plain**: a value in code not compiled at a trait argument, a value at the prompt, a value read from a field or container typed by a trait or by `Any`. Defaults (3, 4, 5) decide only for plain values. The scope of step 5 is the method's module.

```julia
@trait Model begin
    @default_dynamic                          # a solver's models: compiled once by default
    rhs!(m::Model, du::Vector{Float64}, u::Vector{Float64}, t::Float64)::Nothing
end
solve(m::Model, u0) = …                       # Dynamic for a user's model: the trait's default
@specialize step!(m::Model, u) = …            # this argument Compiled: the library's default
solve(compiled_for(MyModel()), u0)            # Compiled at this call: the caller's cast
```

**Status:** Planned (W-111). The order is mine (2026-11-06), on the user's "Dynamic or not as a trait and library default, that the user can override". The fallback by scope: the user (2026-11-06, "falling back to first seen is better for trait modules, falling back to compiled is better for plain Julia").

### 7.6 Casts

- **`compiled_for(x)` and `with_dynamic(x)` are written as an argument of the call they decide:** `paint(io, compiled_for(m))`. They decide that argument at that call, over every default and over what the value carries.
- Anywhere else they are refused when the code is lowered: a cast is a statement about a call.
- **The names are reserved,** as `ccall` is: in a call's arguments they are always the casts, and a local variable or a function of either name is refused when the code is lowered.
- **On a `Dynamic{X}`,** `compiled_for(d)` passes the object it holds, `Compiled`; `with_dynamic(d)` passes `d`.
- **At an argument that the selected method does not type by a trait,** a cast has no effect, as a call-site `@inline` that cannot inline has none. `detect_unused_casts(mod)` lists such casts where the compiler knows the method a call selects.
- **A plain function that stores its argument** (a front end typed `@nospecialize(f)`) passes no cast on. The caller keeps its choice by what it passes: the value itself is compiled per type where the struct records its type, a `Dynamic{X}` once (§8.2).
- Julia's call-site `@inline` is the precedent: a statement about one call, written at the call.

**Status:** Planned (W-111); mine (2026-11-06). Reserved names, unused casts listed: mine (2026-11-06, the reviews of the draft).

### 7.7 `Dynamic{X}`

```julia
d = Dynamic{Shape}(Circle(1.0))     # a Shape, compiled once wherever it goes
area(d)                             # 3.141592653589793, the call dispatched when it runs
hooks = Dynamic{Hook}[Dynamic{Hook}(Below(0.9)), Dynamic{Hook}(Always())]
```

- **`Dynamic{X}` is a struct of Julia's `Core`** that holds a member of `X`; the library declares its memberships and defines its methods. It is itself a member of `X` and of `X`'s supertraits, and its key is the trait's erased key: code for it is compiled once.
- `Dynamic{X}(x)` makes one. A value that is not a member raises `TypeError`. Making one compiles nothing per value type.
- **`X` is a trait with its parameters, or an intersection of such:** `Dynamic{StateVector{Float64}}`, `Dynamic{All{Shape, Placed}}`. `Dynamic{Column}`, with `Column`'s parameter left open, is refused when made (`ArgumentError`, naming `Dynamic{Column{T}}`), as Rust's `dyn Iterator` must name its `Item`. Members whose parameters differ share a container typed by the trait, `Vector{Column}`, where they are plain.
- Its operations dispatch on the held object when they run, with the declared results. Its declared fields are read and written on the held object.
- `unwrap(d)` is the held object.
- **It is a member of `X` and `X`'s supertraits only,** not of the other traits its object belongs to. To pass it where another trait is required, unwrap it, or keep it as `Dynamic{All{X, Y}}`, a member of both.
- **A `Dynamic{Callable{A, S}}` is called at `A` only.** To call its function at another signature, wrap it again, `Dynamic{Callable{B, S}}(unwrap(d))`, or keep it as `Dynamic{All{Callable{A, S}, Callable{B, S}}}` where both signatures are known when it is stored.
- **It keeps the attribute through storage:** a `Vector{Dynamic{Shape}}`, a field of type `Dynamic{Shape}` or `Shape`.
- A result declared `::T` is asserted at the parameter's value: at `Float64` for a `Dynamic{StateVector{Float64}}`.
- Rust's `dyn X` and Swift's `any X` are such boxes: usable through their own trait only. `Dynamic{All{X, Y}}` is Swift's `any X & Y`.

**Status:** Implemented in TraitWorld `unified` e7ff8e2, a struct of the library's until W-111 (lowering L-51); mine (2026-11-06). In `Core`, members of intersections, parameters required, the second signature: mine (2026-11-06, the reviews of the draft).

### 7.8 Keeping an argument with its attribute

`keep(x)`, for an argument `x` of a method at a trait `X`, is `x` where the code is compiled per key or per type, and `Dynamic{X}(x)` where it is compiled once. A library stores an argument with it so that its attribute survives:

```julia
struct Problem{F <: Callable{RHSSig, Nothing}}; f::F; u0::Vector{Float64}; end
Problem(f::Callable{RHSSig, Nothing}, u0) = (k = keep(f); Problem{typeof(k)}(k, u0))
```

Elsewhere `keep(x)` is `x`. Such a constructor is open at `f`, since the struct's parameter takes the type of `k`; as a constructor that sets a parameter bounded by the trait, `bounded` does not refuse it (§7.3).

**Status:** Planned (W-111); mine (2026-11-06).

### 7.9 Operations on a value the code knows only by its trait

Where the code holds a value at the trait's type (code compiled once, a field or element typed by the trait, an operation's result declared with the trait):
- **an operation's result is its declared result,** asserted (`TypeError` otherwise), so the code after the call is typed;
- **the call branches on the first four members declared** of the trait, each a direct call that may be inlined. Any other member is called through a table keyed by its type: one lookup and one indirect call, whatever the number of members. The order is the declarations': a trait's package declares its common members first. At an intersection, the branches take the first component's members that are members of every component;
- a member declared later takes the table and invalidates nothing; code compiled after its declaration may branch on it if it is among the first four;
- a declared field read there works the same way.

**Status:** Planned (W-109; [compiler §7](compiler.md#7-operations-on-a-value-typed-by-its-trait)).

### 7.10 Costs, and choosing

- **An operation on a value whose key the code knows** is a direct call of the member's method.
- **An operation on a value the code knows only by its trait** costs the same for both attributes: a branch among the first four members, else one lookup and an indirect call.
- **At a call from code that does not know the value's type:** `Dynamic` runs the code compiled once; `Compiled` dispatches once on the type, then runs the code per key.
- **Choosing:**
  - `Dynamic` suits large code with many members behind it (a solver's models, a plot's marks): a member from outside compiles nothing in the library. A caller's `compiled_for` still compiles it per key where speed matters.
  - `Compiled` suits kernels, where the work per call pays for code per key.
  - A loop over a `Vector{Shape}` runs once; each item's type is unknown in it. Passing items to a `Compiled` method pays a dispatch per item, then code per key.
  - **A trait whose operation is a hot inner call** (a model's right-hand side) declares `@default_compiled`. Otherwise, in a trait module, a value from the prompt is `Dynamic` by step 5, and each call of the operation dispatches.
- **Only `Dynamic{X}` keeps an attribute through storage.** A member stored as itself is plain where it is read back (§7.5), and an operation on it takes the branches of §7.9.
- The numbers: [`../design/evidence.md`](../design/evidence.md) §2.

**Status:** Planned.

---

## 8. Storage

### 8.1 Fields and containers typed by a trait

```julia
mutable struct State
    const u::Vector{Float64}
    model::Model                     # any member, or a Dynamic{Model}
    hooks::Vector{Hook}
end
```

- A field, element or `Ref` typed by a trait holds any member, boxed, as one typed by an abstract type does. It holds a `Dynamic{X}` too, which is a member.
- **Assignment converts as Julia's does:** `convert(X, x)`, which is `x` for a member. A library that translates values defines `Base.convert(::Type{ColorSpec}, s::Symbol) = named_colour(s)`.
- **A value read back is what was stored:** a member, or a `Dynamic{X}`. A member read back is plain (§7.5); a `Dynamic{X}` stays `Dynamic`.
- An operation on a value read back follows §7.9.

**Status:** Implemented: Julia's storage, with TraitWorld `unified` e7ff8e2's members.

### 8.2 A struct parameter bounded by a trait

```julia
struct ODEProblem{T, P, F <: Callable{RHSSig{P, T}, Nothing}}
    f::F
    u0::Vector{T}
    tspan::Tuple{Float64, Float64}
    p::P
end
ODEProblem(lorenz!, u0, tspan, p)                          # F = typeof(lorenz!)
ODEProblem(Dynamic{Callable{RHSSig{P, T}, Nothing}}(lorenz!), u0, tspan, p)   # F = Dynamic{…}
```

- The bound is Julia's: the constructor checks it (`TypeError`), and the default constructor sets the parameter to the value's type.
- **The parameter records the attribute:** the value's own type is `Compiled`, so code over the struct is compiled per type of the value; a `Dynamic{X}` is `Dynamic`, so code over the struct is compiled once. A value read from the field carries that attribute (§7.5).
- A library that wants its trait's default at construction writes a constructor with a trait argument and `keep` (§7.8).
- **A parameter named only in a bound** is matched through the membership, as a `where` clause matches: in `struct CellVector{T, C <: Column{T}} <: AbstractVector{T}; c::C; end`, the constructor `CellVector(c::C) where {T, C <: Column{T}} = CellVector{T, C}(c)` reads `T` from the column's membership.
- **A constructor that sets the parameter from its trait argument is open there** (§7.3): the struct's type names the member's type. It is open by design, so `bounded` does not refuse it, Julia's default constructor included.

**Status:** Implemented: Julia's bound and default constructor, with TraitWorld `unified` e7ff8e2's members.

### 8.3 Equality

`Dynamic{X}(a) == Dynamic{Y}(b)` when `a === b`, for a mutable object by identity, for an immutable one by value; `hash` agrees. `===` compares the wrappers.

**Status:** Implemented in TraitWorld `unified` e7ff8e2; mine (2026-11-06).

---

## 9. Functions: `Callable`

```julia
colmap(f::Callable{Tuple{Float64}, Float64}, t::ColTable, i::Int) = map(f, col(t, i))
apply(f::Callable{Tuple{Int}, Int}, x) = "an integer map"
apply(f::Callable{Tuple{String}, <:AbstractString}, x) = "a string map"     # dispatch picks by signature
both(f::All{Callable{Tuple{Float64}, Float64}, Callable{Tuple{Int}, Int}}, x::Float64, n::Int) = (f(x), f(n))
byrow(f::Callable{Tuple{T}}, c::Column{T}) where {T} = …     # result type, where needed: Base.promote_op(f, T)

colmap(x -> 2x, m, 1)                     # Dynamic: Callable's default
colmap(compiled_for(x -> 2x), m, 1)       # Compiled at this call
colmap(abs2, m, 1)                        # Compiled: a function Julia defines
```

**`Callable{A, S}` is the trait of functions called with arguments of the tuple type `A` and returning an `S`.** It has rules of its own, as Rust's `Fn` traits are the compiler's own:
- **A function is a member of `Callable{A, S}` where it has a method for a call at `A`** (Julia's `hasmethod`), whatever `S` is. Its own methods decide it: nothing is declared, and inference plays no part. A method of the function defined later can begin or end a membership; that is the one kind of membership that can end ([facts §10](facts.md#10-memberships)).
- **So dispatch picks by the arguments' signature:** `apply(uppercase)` takes the second method above, since `uppercase` has a method at `String` and none at `Int`.
- **`S` is checked on return.** A call through a value the code knows as a `Callable{A, S}` (an argument, a field or element declared so, a `Dynamic{Callable{A, S}}`) has the result type `S`, asserted: `TypeError`, naming the declared and the returned type; where `S` is `Nothing`, the message adds: end the function with `nothing`. Where it is compiled once, the call goes through a pointer that follows the caller's world.
- **`S` takes no part in which method is chosen.** Between two methods that differ only in `S`, the one with the more specific `S` is taken, and its check may fail. `Callable{A}`, with `S` left open, checks nothing on return.
- **A `where` variable that appears only in `S` is not bound by a call,** as Julia's `detect_unbound_args` reports. Code that needs the result type computes it as a value, `Base.promote_op(f, T)`, as `map` does ([facts §7](facts.md#7-return_type-and-reflection)).
- **Where the code knows the function by its own type** (a struct parameter `F`), the call is the function's own call.
- **Its default is `Dynamic`:** code is compiled once per signature, not per function. A function Julia defines, or one of the trait's own package, is `Compiled` (§7.5).
- **Several signatures** are an intersection: a call picks the signature its argument types match.
- **Argument types may follow other arguments:** `retain!(f::Callable{Tuple{T}, Bool}, xs::Iterable{T}) where {T}`.
- `Callable` without parameters takes any function, kept before its signature is known.
- **Keywords:** `Callable{A, S, K}`, `K` a named-tuple type (Planned).
- A closure with a trait argument, `(u::ColTable) -> …`, is a method at the trait.

**Status:** Planned (W-113). Dispatch by signature: the user (2026-11-06, "I think we need dispatch to pick by signature"); `S` checked on return: the user (2026-11-06, "For Callable S go with checked on return. Keep it simple."). Keywords Planned.

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
| `HasLength` | `length(c)::Int` | — | `AbstractArray`, `AbstractDict` |
| `Iterable{T}` | `iterate(c)`, `iterate(c, state)`, each `::Union{Nothing, Tuple{T, Any}}` | `T = eltype(Self)` | `AbstractArray`, `AbstractDict` (items `Pair{K, V}`) |
| `Indexable{T} <: HasLength` | `c[i::Int]::T` | `T = eltype(Self)` | `AbstractVector` |
| `MutableIndexable{T} <: Indexable{T}` | `c[i::Int] = x::T` | `T = eltype(Self)` | `Vector` |
| `Resizable <: HasLength` | `resize!(c, n::Int)` | — | `Vector` |
| `Keyed{K, V} <: HasLength` | `d[k::K]::V`, `haskey(d, k::K)::Bool` | `K = keytype(Self)`, `V = valtype(Self)` | `AbstractDict` |
| `HasProperty{N, R}` (`N` an input) | `x.N`, of type `R`: `getproperty` at the constant name `N`, served by the member's own `getproperty`; on a value known only by its trait, `x.N` has the declared type, as a declared field's read (§7.9) | — | none; a type joins at each name |
| `Solvable{T}` | `solve!(F, x::Vector{T}, b::Vector{T})::Nothing` | `T = eltype(Self)` | LinearAlgebra's `Factorization` |
| `BoundedText` | `textbound(x)::Int`, an upper bound on the bytes `print(io, x)` writes | — | numbers, `Bool`, `Char`, strings, `Symbol`, Dates' types |

- **Base's types join as Base's abstract types,** declared in BaseTraits, which owns the traits: `@implement Indexable{T} AbstractVector{T} where {T}`. A type is a member only where declared: a `Number` iterates in Base but is not `Iterable`.
- `asvector(x::Indexable{T})` is the collection as a read-only `AbstractVector{T}` for plain code, without a copy: `IndexableVector{T, C <: Indexable{T}}`. It is an open method (§7.3).
- A module that uses BaseTraits and another module exporting the same name gets Julia's usual ambiguity of names.

**Status:** Planned (W-114).

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

**Status:** Planned.

### 10.3 Algorithms

- `retain!(f::Callable{Tuple{T}, Bool}, xs::All{MutableIndexable{T}, Resizable}) where {T}` keeps the items for which `f` is `true`, in place, in order. It is Base's `filter!` for trait code. It is compiled once per item type, not per function.
- BaseTraits' algorithms have names of their own: a method of Base's `filter!` at a trait would rank below Base's own methods (§6.2) and never run for Base's containers.

**Status:** Planned.

---

## 11. Checks and errors

### 11.1 When checks run

| When | What is checked | Error |
|---|---|---|
| `@trait` | the body's form: result types present, one receiver per operation, no parameter defined twice | an error at the macro, naming the line |
| `@implement` for one type | ownership, completeness, results, fields, parameters, concreteness, supertraits (§5.10) | `ImplementError`; ownership `OwnershipError` |
| a member's first use (a family's, an abstract type's or a trait's member) | as at `@implement` | `ImplementError`, at that use and every later one |
| a use before, or a module's end | a `struct S <: X` without `@implement X S` | `ImplementError` |
| a method's definition | an override of an operation a default serves (§5.11); a pirate in a scope that refuses them (§12.2); an open method in a scope that declares `bounded` (§7.3) | `ImplementError`, `OwnershipError`, `TraitUseError` |
| a method's definition, strict mode | a pirate that would win at a fact of code compiled by facts (§12.3) | `PirateError` |
| a membership | a type made a member of two traits whose methods are ambiguous for it (§6.3) | a warning; under strict mode an error |
| a method's first call at a signature | what definition checking could not see: a `where` variable that only a trait's open parameter fixes, a `Callable`'s open result | `TraitUseError` |
| a call | Julia's dispatch: no method, or ambiguous | `MethodError` |
| a call through the trait | an operation's result against its declared type (§7.9); a `Callable`'s arguments and result (§9) | `TypeError`, `MethodError` |
| a keyword typed by a trait | membership | `TypeError` |

**Status:** Implemented in TraitWorld `unified` e7ff8e2 at `@trait`, at `@implement` and at a member's first use at dispatch; at a module's end and a method's definition: W-108, W-109, W-114.

### 11.2 Definition checking

- Each method at a trait is checked once for every member that will ever join, by inferring it at the trait itself: every operation and field there returns its declared type and nothing more. This is the classification of §7.3. In a scope that declares `bounded` it is a check.
- **While a package is precompiled,** a `TraitUseError` fails the build. **At the prompt or in a script** it is raised at the definition.
- `check_definitions(M)` runs it on demand: an empty list, or `TraitUseError` listing every problem of every method.
- It reports each use outside the contract, not only the first: inference continues past an unresolved use at `Any`.

```julia
spread(t::ColTable) = size(t)    # `size` is not an operation of ColTable: open
leak(t::ColTable) = typeof(t)    # open: the code depends on the type
```

**Status:** Planned (W-109; [compiler §6.7](compiler.md#67-the-definition-time-check)).

### 11.3 Errors and their messages

Each message names the trait, the type, and the declared signature where one is involved. A key in a signature prints as the key (§15).

| Error | Raised for | The message names |
|---|---|---|
| `ImplementError` | a membership that fails its check | each missing operation with its declared signature at the type, and the type's methods of that function that do not cover it, with the argument that differs; each result that infers wider, with both types; each field missing, mistyped or not writable; each parameter that disagrees, with its source; an override; the path that gives a second instance |
| `OwnershipError` | a membership or method by a package that owns none of what it names | the method or membership, its owners, and who may declare it |
| `TraitUseError` | an open method in a `bounded` scope; a check at a first call | each use outside the contract, its line, and the contract's operations of that name |
| `PirateError` | strict mode | the method and the code compiled by facts it would change |
| `MethodError` | a call no method takes, or two take ambiguously | Julia's message, with hints (§11.4) |
| `TypeError` | an operation's or a `Callable`'s result that is not its declared type; a keyword that is not a member; a struct parameter outside its bound | the operation or function, the declared and the returned type |

**Status:** `ImplementError` and `TraitUseError` in TraitWorld `unified` e7ff8e2; `OwnershipError` and `PirateError` with W-114.

### 11.4 Hints

The library adds hints to Julia's `MethodError` where a trait is involved:
- **a value that is not a member** of a trait a method takes: "`Circle` is not a member of `ColTable`; `@implement ColTable Circle` declares it", with the trait's declared members where few;
- **a member at other parameter values:** "`v` is a member of `StateVector{Float32}`; the method takes `StateVector{Float64}`";
- **a broken shared variable:** "`T` is `Float64` for `a` and `Float32` for `b`";
- **a call at an operation's function outside its declared signature:** the declared signature, "`col` is declared `col(t::ColTable, i::Int)::Vector{Float64}`";
- **an ambiguity between two traits:** the joint method to define, `f(::All{ColTable, RowTable})`.

**Status:** Planned (W-114).

---

## 12. Ownership, pirates, strict mode

### 12.1 Who may declare a membership

- A package **owns** the functions and types it defines, traits included. Julia (Core, Base, the standard libraries) is one owner. A package extension counts as its parent.
- **At the prompt,** `Main` is one owner, and each module defined directly under `Main` is an owner of its own.
- **A membership is declared by the trait's owner or the type's owner.** A third package may not (`OwnershipError`).
- A membership for a foreign trait and a foreign type belongs in the trait owner's package extension. **A membership in a package extension names each of the extension's triggers** (each owns the trait or a type the declaration names); otherwise whether a type is a member would depend on which packages happen to be loaded. It is refused with `ImplementError`.
- **An operation that is an existing function** (`Base.size`) may be served by methods in a block only for types the declaring package owns. Otherwise declare the type's existing methods: `@implement Sized Vector{Float32}`.
- **Joint owners:** a package may name packages that own its functions and types with it (`@joint_owners DiffEqBase OrdinaryDiffEqCore`, at the top level of its own module). They are owners wherever the declaring package is one: memberships, pirates, strict mode's stakeholders. Not symmetric, not transitive; a joint owner's extension is a joint owner too. A joint owner's change is a stakeholder's change ([facts §2.2](facts.md#22-g2-stable-caches)).

**Status:** Planned (W-114). Open: whether the standard libraries are owners of their own ([open issues §1.19](../open-issues.md#1-decisions-waiting-for-the-user)).

### 12.2 Pirates

- A **pirate** is a method of a function you do not own, for types you do not own: Julia's type piracy. A trait you own is a type you own; a `Union` with your own type or a lower-bounded type variable is no way around it.
- **A scope that declares `no_pirates`** refuses one at its definition (`OwnershipError`).
- Elsewhere a pirate is followed, as in Julia; code compiled by facts that it changes is compiled again once ([facts §11](facts.md#11-pirates-and-strict-mode)).

**Status:** Planned (W-114).

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
- An ambiguity at a membership (§6.3) is an error.

**Status:** Planned (W-114).

---

## 13. Scopes: trait modules

```julia
module Geometry
using TraitWorld
@trait_module                     # facts, bounded, no_pirates, first_seen
@trait Shape begin … end
area_sum(shapes::Iterable{<:Shape}) = …
end
```

- **`@trait_module`, before the module's first method,** declares options for every method of the module, its submodules included:
  - **`facts`:** its methods are compiled by facts ([facts §6](facts.md#6-which-code-is-compiled-how));
  - **`bounded`:** an open method at a trait argument is refused (§7.3);
  - **`no_pirates`:** a pirate is refused (§12.2);
  - **`dynamic`:** the library's default for every trait argument of its methods is `Dynamic` (§7.5). Off unless written;
  - **`first_seen`:** where nothing else decides, a trait argument's attribute is what the caller knows (§7.5, step 5).
- All but `dynamic` are on unless written otherwise (`@trait_module bounded = false`).
- A method may set an option for itself: `@bounded f(…) = …`, `@facts f(…) = …`; `@open f(…) = …` exempts it from `bounded` (§7.3).
- The module's statements are Julia's; nothing is rewritten. Revise and other tools that read a module by its statements see an ordinary module.
- At the module's end, methods whose classification waited for later definitions are classified (§7.3).
- Concreteness and fully typed mode (§14) take the same places: before `@trait_module`, for the module; before a method, for it.
- Traits, memberships and methods at traits work in any module; a scope decides only these options.

**Status:** Planned (W-111; the user, 2026-11-06, Q2 (a)).

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
- **Per method:** `@enforce_concrete_only names…` before a method refuses a call where a named part is not concrete; `@warn_on_abstract` warns once per method and type. The names are the method's `where` variables that traits fix, and trait arguments, each standing for its `Self`. For a `Compiled` value the answer is decided where the call is compiled; for a `Dynamic` one, `Self` is not checked.

**Fully typed code** is a property of a method at the signature it runs at: every call in it, and in what it calls, has known argument types. Such code pays nothing for the facts mode.
- `@warn_not_fully_typed` warns at a method's first run at a signature; `@enforce_fully_typed` raises `AbstractTypeError` where the code uses a value of an abstract type there, or `NotFullyTypedError` at a call it cannot resolve when compiled.
- `fully_typed(f, argtypes)` reports the calls that are not, with their root cause through any number of layers, in the trait's terms ("field `data` of `HasData` is declared `AbstractVector`"). `isfullytyped(report)` answers yes or no.
- **Operations on a value the code knows only by its trait count as declared,** not as faults (§7.9).
- **An argument the scope's fallback made `Dynamic`** (§7.5, the last step) is reported, not counted as declared: `detect_dynamic_fallbacks(mod)` lists each such argument per method, with its line, beside `detect_unused_casts` (§7.6).

**They differ.** Concrete parts do not make code fully typed (a `Vector{Any}` argument, an abstract declared result can each leave a call unresolved). Fully typed code is checked at the signatures it ran at; concrete parts are promised for every member.

**Status:** Planned (W-114). A trait as a concrete parameter value is mine (2026-11-06), as Rust's `Vec<Box<dyn Trait>>` and Swift's `[any P]` are concrete. The report of the fallback's arguments: mine (2026-11-06, [the trade-offs review](../reviews/2026-11-06-unification-tradeoffs.md) M9), adopted with the work plan by the user.

---

## 15. Printing

- **A key prints as the key** where keys are built (§7.2), wherever a signature appears: `colmean(::ColTable at Vector{Vector{Float64}}, ::Int64)` in a stack trace, a `MethodError`, `code_typed` and the list of a method's compiled copies. Code compiled once prints its argument as the trait: `colmean(::ColTable, ::Int64)`.
- **A `Dynamic{X}`** prints as `Dynamic{Shape}(Circle(1.0))`.
- A trait prints as the type it is.

**Status:** Planned (W-114); a key's printing with keys (W-110, Optional).

---

## 16. Compiling ahead, closed programs

- **While a package that declares `@implement X T` is precompiled,** the code that `T` needs is compiled into that package's image. That covers every method at `X` and its supertraits with one trait argument, fully bounded there, at `T`'s key, where the other arguments are concrete. Their checks run then; a failing check fails the build.
- A key that some member already has compiles nothing new.
- A method with several trait arguments is compiled at its first call. Arguments whose attribute is `Dynamic` have a known key, the erased one, so such methods are compiled ahead too.
- Compiling ahead adds no method, so it invalidates nothing.
- **Closed programs:** `verify_main(main, (Vector{String},); entrypoints = true)` lists every target a program can reach, for `juliac --trim`:
  - a function passed at a `Callable` adds one target at its signature;
  - code compiled once lists every declared member as a target of its operations;
  - a `like` result lists the member's rebuilding;
  - each set of supplied keywords is a signature.
- A trimmed binary compiles everything plainly ([facts §13.3](facts.md#133-trimmed-binaries)).

**Status:** Planned (W-114).

---

## 17. Named implementations

A second way for a type to join a trait, used only where a caller names it, is a wrapper type that joins it: `Via{Fast}(x)`, a newtype. A foreign trait for a foreign type is joined through the user's own wrapper type: `struct FastM; m::M; end` with its own membership.

**Status:** Planned (deferred).

---

## 18. Status index

| Construct | Status | Section |
|---|---|---|
| a trait is an abstract type; membership, transitivity, worlds | Implemented (`unified` 62016706d0) | §3.1 |
| parameters as associated types; invariance, `X{<:T}`; one instance per member | Implemented (`unified` 62016706d0, TraitWorld e7ff8e2); inputs: compiler C-32 | §3.2 |
| a family states its instance as a pattern, equations included | Implemented (TraitWorld e7ff8e2) | §3.2, §5.8 |
| a trait wherever a type stands | Implemented (`unified` 29035cab11) | §3.3 |
| sealed traits | Optional (PE-19) | §3.4 |
| intersections `All{X, Y, Z, …}`; bundles as aliases | Planned (W-107) | §3.6 |
| operations, `where` on operations, the receiver at any position | Implemented (TraitWorld e7ff8e2) | §4.1 |
| defaults as the trait's methods, reached by every caller | Implemented (TraitWorld e7ff8e2) | §4.2 |
| declared fields as stored fields | Implemented (TraitWorld e7ff8e2) | §4.3 |
| `Self`; supertraits | Implemented (TraitWorld e7ff8e2) | §4.4, §4.5 |
| `struct S <: X`, declared and checked by `@implement X S` | Implemented (TraitWorld e7ff8e2); the use before and the module's end W-108 (L-52) | §5.2 |
| one line, block, several traits, stated parameters | Implemented (TraitWorld e7ff8e2) | §5.3–§5.7 |
| forwarding by the trait's method | Implemented (TraitWorld e7ff8e2) | §5.5 |
| families; abstract types and traits as members | Implemented (TraitWorld e7ff8e2, dd72b10) | §5.8, §5.9 |
| checks at the declaration and at first use | Implemented (TraitWorld e7ff8e2, `unified` ec4f9a8714), at dispatch (C-31); in images W-108 | §5.10 |
| overrides fixed; redeclaration | Planned (W-108); a redeclaration's entry implemented (`unified` 62016706d0) | §5.11 |
| dispatch: specificity, ambiguity reported at a membership, fallback | Implemented (`unified` 62016706d0, 0d529d33a9), but for intersections (W-107) | §6.2–§6.4 |
| `like`, `withfields`; their compilation per type | Implemented (TraitWorld e7ff8e2) | §6.5 |
| keys and shared code | Optional, built late (W-110; open issue 147) | §7.2 |
| fully bounded and open methods | Planned (W-109) | §7.3 |
| the attribute and what decides it | Planned (W-111) | §7.4, §7.5 |
| casts at the call | Planned (W-111) | §7.6 |
| `Dynamic{X}`, `keep` | `Dynamic{X}` implemented (TraitWorld e7ff8e2; L-51); `keep` W-111 | §7.7, §7.8 |
| operations on a value known only by its trait | Planned (W-109) | §7.9 |
| storage typed by a trait; struct parameters | Implemented (Julia's, with TraitWorld e7ff8e2) | §8 |
| `Callable`: dispatch by signature, the result checked on return | Planned (W-113) | §9 |
| BaseTraits; element types by variance; `retain!` | Planned | §10 |
| checks, errors, hints | Checks at declarations and first uses, `ImplementError` implemented (TraitWorld e7ff8e2); definition checking W-109; hints W-114 | §11 |
| ownership, joint owners, pirates, strict mode | Planned (W-114) | §12 |
| the standard libraries as owners | Open | §12.1 |
| scopes: `@trait_module` and its options | Planned (W-111) | §13 |
| concreteness and fully typed mode | Planned (W-114) | §14 |
| printing | Planned | §15 |
| compiling ahead, `verify_main` | Planned | §16 |
| named implementations | Planned (deferred) | §17 |

---

## 19. Deviations

The trait library on the unified build is not begun; nothing is recorded. The type system's and dispatch's deviations on branch `unified` are [compiler.md's](compiler.md#deviations).

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| T-1 to T-95 | — | *Retired* (2026-11-06): the rows of the reference these replaced, in `attic/writeup/reference/traits.md` | — | — |
