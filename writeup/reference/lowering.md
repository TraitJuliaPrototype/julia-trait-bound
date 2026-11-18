# Lowering: the reference

This page defines what the trait library's macros expand to on Julia's interfaces ([`compiler.md`](compiler.md)), within the facts mode's contract ([`facts.md`](facts.md)). It decides nothing the other three references decide; where it seems to, they win. Each section ends with a status line (Implemented, Planned, Optional, Open), as [the README](README.md#conventions-for-every-reference) defines them. The [Deviations](#15-deviations) table lists where the implementation falls short of this page.

The language puts most of the work in Julia: a trait is an abstract type, a membership is an entry of the type system, a method at a trait is a Julia method, compiled as Julia compiles one; the box and the wrapper are two structs. What remains for the library is to declare, to check, and to report.

## Contents

1. [Summary](#1-summary)
2. [`@trait`](#2-trait)
3. [`@implement`](#3-implement)
4. [Members checked at their first use](#4-members-checked-at-their-first-use)
5. [Methods at traits](#5-methods-at-traits)
6. [Scopes](#6-scopes)
7. [`Dynamic{X}` and `Compiled{T}`](#7-dynamicx-and-compiledt)
8. [`like` and `withfields`](#8-like-and-withfields)
9. [`Callable`](#9-callable)
10. [BaseTraits](#10-basetraits)
11. [Checks, errors, and what images keep](#11-checks-errors-and-what-images-keep)
12. [Compiling ahead](#12-compiling-ahead)
13. [Strict mode](#13-strict-mode)
14. [Fully typed mode, concrete parts, closed programs](#14-fully-typed-mode-concrete-parts-closed-programs)
15. [Deviations](#15-deviations)

---

## 1. Summary

| Construct | Becomes | Made |
|---|---|---|
| `@trait X …` | an open abstract type; its supertraits' memberships; the operation functions; a method at the trait per default; the contract on the type's `TypeName`, its operations as entries, whether it erases by default; the memberships and forwarding methods of the two kept forms, `Dynamic{X}` and `Compiled{T}` | at the declaration |
| `@implement X S …` | the block's methods; the checks; a membership entry with its receiver; the override records | at the declaration |
| a family, an abstract type or a trait as a member | a membership entry with a pattern; each member's check | the entry at the declaration; each member's check at its first use |
| `struct S <: X` | Julia's struct, whose supertype is `X`; the `@implement X S` that must follow | Julia's definition; the check at the `@implement` |
| a method at a trait | nothing: a Julia method; where the trait erases by default, Julia adds its forwarder ([compiler §6.3](compiler.md#63-the-forwarders)) | Julia's definition |
| `@trait_module` | module option bits | before the module's first method |
| `Dynamic{X}`, `Compiled{T}`, `compiled_for` | two structs of `Core` with the library's memberships and methods; a function of the library | — |

**Status:** Implemented, but for [traits T-125](traits.md#19-deviations).

---

## 2. `@trait`

`@trait X{P…} <: (A, …) begin … end` runs in the declaring module, at the declaration. It defines, in this order:

- **The abstract type** `X{P…}`, created open ([compiler §4.1](compiler.md#41-sets)), its declared supertype `Any`. Bounds on parameters are the type's bounds.
- **Its supertraits' memberships:** for each supertrait `A{q…}`, `jl_declare_membership(X{P…} where {P…}, A{q…}, nothing, mod, nothing)` ([compiler §4.2](compiler.md#42-memberships)).
- **The operation functions:** a plain name makes a new generic function in the module; a qualified name uses the existing one.
- **A method at the trait for each default,** at each arity it is declared at ([traits §4.2](traits.md#42-defaults)): a method at `X`, its result annotated with the operation's declared result, marked `Expr(:meta, :no_forwarder)` so that Julia makes no forwarder for it ([compiler §6.3](compiler.md#63-the-forwarders)). Its receiver is typed by `X`. A further argument keeps its declared type only where it binds one of the trait's input parameters or one of the operation's own `where` variables, or where two declarations of the operation at one arity differ; the others are untyped. A parameter the receiver fixes (an equation of `Self`, or the instance a membership states) is bound by the receiver, not by a further argument. So a member's own method, written at its type, is more specific however it types its further arguments, and wins (traits §4.2). A `where` written after the operation's result is the operation's own. The checks use the declared types (§3). Its body:
  - for a member that forwards, the operation called on its forwarding field, through the library's `_fwd(t, X)`, a method per forwarding member and trait that inference resolves at a member's type to the field's `getfield`; a declared field the same way. With keys, an optional extension, `Core.trait_receiver` and `Core.trait_field` ([extensions §1.4](extensions.md#14-the-calling-convention));
  - otherwise the default's body.
- **No method for an operation without a default.** It is an entry of the contract (below) and nothing else: each member serves it by a method of its own type (§3, steps 2 and 6).
- **`Dynamic{X}`'s forwarding methods:** for each operation without a default and each arity, a method at `Dynamic{<:X}` that calls the operation on its object, `getfield(d, :object)`, a value typed by the set: an operation's call ([compiler §7.1](compiler.md#71-the-rule)). A further argument keeps its declared type where that type names none of the trait's parameters, `Self` or the operation's own variables (`io::IO`, `i::Int`), so that the method is more specific than one of the function that types those arguments and takes any receiver (Base's `show(io::IO, x)`). The others are untyped, but where two declarations of the operation at one arity differ in them. An operation with a default reaches `Dynamic{X}` through the default's method, which forwards.
- **The wrapper's forwarding methods:** the same at `Compiled{<:X}`, on `getfield(w, :object)`, whose type is the object's: a static call of the object's own method.
- **The kept forms' methods of each equation's function:** for an equation `P = f(Self)`, a method of `f` at the types of `Dynamic{<:X{P…}}` and of `Compiled{<:X{P…}}` that returns the parameter's value ([traits §7.4](traits.md#74-the-two-kept-forms-the-box-and-the-wrapper)): `eltype` of a box of `Iterable{Float64}` is `Float64`.
- The kept forms' methods are marked `Expr(:meta, :no_forwarder)` too.
- **The contract** on `X`'s `TypeName` ([compiler §4.1](compiler.md#41-sets)):
  - the operations, each an entry: the function, the declared signature and the declared result as types, and the default's method where it has one ([compiler §4.1](compiler.md#41-sets));
  - the declared fields, with their types and whether `@const`;
  - each parameter's definition: a field's pattern, an equation (a function of `Self`), or stated;
  - the input parameters;
  - which operations have defaults;
  - whether the trait erases by default (`@default_dynamic`), as the bit the method definition reads ([compiler §4.1](compiler.md#41-sets), [§6.3](compiler.md#63-the-forwarders));
  - the concreteness declarations.

  It is fixed at the declaration and saved with the `TypeName` in images.
- **`Dynamic{X}`'s membership:** the family `Dynamic{Z} where {P…, Z <: X{P…}}` in `X{P…}`, forwarding by its field `object` (§7). So `Dynamic{Sub}` for a subtrait `Sub` and `Dynamic{All{X, Y}}` are members of `X` too.
- **The wrapper's membership:** the family `Compiled{Z} where {P…, Z <: X{P…}}` in `X{P…}`, forwarding by its field `object`. So a wrapper is a member of every trait its object is a member of.
- `Expr(:latestworld)`.

A trait's declaration changes no compiled code: its methods are at a set with no members yet, and at `Dynamic{<:X}` and `Compiled{<:X}`, of which no value exists yet.

**Status:** Implemented, but for L-67.

---

## 3. `@implement`

`@implement X{p…} S how` runs at the top level of the declaring module:
1. **Ownership** (§11): the module's package owns `X` or `S`, or is a joint owner; an extension names its triggers.
2. **The block's methods,** where there is a block: each a method of the operation's function, the receiver typed `S`, unannotated arguments typed as declared.
3. **The checks** ([traits §5.10](traits.md#510-checks)), by Julia's inference of each serving method's instance at `S` and the declared argument types, cached as code is, with its edges ([compiler §6.7](compiler.md#67-the-definition-time-check)):
   - completeness;
   - results;
   - fields;
   - parameters: matched from fields, equations evaluated at `Self`, stated values, bounds;
   - agreement with `S`'s memberships of supertraits;
   - concreteness.
4. **A refusal** deletes the block's methods and raises `ImplementError`. Nothing is declared.
5. **The receiver** (what keys would read, [extensions §1.1](extensions.md#11-the-key)): `S` where it serves an operation by its own method, the forwarding field where it forwards, none where defaults serve every operation.
6. **The membership:** `jl_declare_membership(S, X{p…}, mod, by, receiver)`, then `Expr(:latestworld)`. The runtime refuses a second instance of `X` for `S` ([compiler §4.6](compiler.md#46-one-instance-per-member)); the library then deletes the block's methods and raises `ImplementError`.
   - Before it, **forwarding's methods,** where `S` forwards by a field `f`: for each required operation of `X` and arity, a method at `S` that calls the operation on `t.f`, its further arguments untyped. They are the membership's, as its declaration is: no block's owner rule. A refusal deletes them.
7. **The records the definition hook reads** (§11; [traits §5.10](traits.md#510-checks), [§5.11](traits.md#511-overrides-and-redeclaration)) are the check's instances of step 3, with their edges:
   - a call a default serves at `S`, and each forwarding method of step 6, is fixed: a definition that would end its instance is refused;
   - a call whose result the check inferred within the declared result is checked: a definition that would end its instance is judged by inferring the call again with it.
   - A redeclaration ends the member's instances for the trait before its block is defined. A member checked at its first use (§4) gets its instances then.
   - An image keeps them as code; a membership an image activated has them by validation.
8. **While the package is precompiled:** compiling ahead (§12).

`@implement (X, Y) S …` repeats steps 3 to 8 per trait, with step 2 once.

**`struct S <: X`** is Julia's struct definition; `X` is its supertype. The library requires `@implement X S` in the same module, after `S`'s methods. That declaration runs steps 1 to 8: its entry (step 6) records the receiver. The parameters come from the declared supertype; a stated value or a field's type that differs is refused at step 3. A module that ends with a `struct S <: X` and no `@implement X S` is refused at its end ([compiler §10.1](compiler.md#101-definition-and-image-hooks)'s module-end hook). A use of `S` through `X` before the declaration raises `ImplementError` naming it (§4); the declaration replaces that kept failure.

**A family variable bounded by a `Union`** (`@implement BoundedText I where {I <: Base.BitInteger}`) declares one membership per type of the union.

**Taking it back** ([traits §5.13](traits.md#513-taking-a-membership-back)): `delete_membership(X, S)`, at the top level or at the prompt:
1. ownership, as at step 1; a member by its definition, a supertrait's membership and `Dynamic{X}`'s are refused;
2. in strict mode, the check of a method's deletion (§13);
3. `jl_delete_membership(S, X{p…}, mod)` ([compiler §4.3](compiler.md#43-worlds)), then `Expr(:latestworld)`;
4. the member's records of step 7 and its kept check are forgotten, for each member a pattern made.

**Revise.** The library's extension for Revise tells Revise which memberships an expression declared, as Revise knows which methods it defined. An `@implement` that a revised file no longer has is taken back with `delete_membership`, as a method no longer defined is deleted; one that changed is declared again (a redeclaration, [traits §5.11](traits.md#511-overrides-and-redeclaration)).

**Status:** Implemented, but for L-64 (Revise); the check's instances as the records (steps 3, 7): Planned, with [traits T-129](traits.md#19-deviations).

---

## 4. Members checked at their first use

A membership with a pattern (a family `S{P} where P`, a closed abstract type, a trait) makes members whose checks are not run at the declaration.

- **The pattern states the trait's instance** with the family's variables, constants and type constructors: `@implement Iterable{T} Wrapped{T} where {T}`. Where an equation defines a parameter (`T = eltype(Self)`), the pattern states it too, and each member's check compares the equation's value with the pattern's. A family whose instance cannot be written so is refused at its declaration, naming the parameter.
- **The member hook** ([compiler §10.4](compiler.md#104-the-member-hook)): the runtime calls the library at a member's first use, at dispatch or before code that relies on the member is published. The library runs the member's checks (§3, step 3), or raises `ImplementError`. The answer is kept per (member type, trait) on the member's `TypeName`, and every later use reads it; a failure is kept too, and raised at every use.
- Inference never calls the hook, and no runtime lock is held while it runs. A check that reaches its own member again raises.
- Members checked while a package image is built are kept in the image with the methods each check relied on. At load, a member whose relied-on methods dispatch the same is not checked again.

**Status:** Implemented, but for [compiler C-30, C-31](compiler.md#deviations).

---

## 5. Methods at traits

- **A method at a trait is defined by Julia** with nothing around it. The definition-time check reads its instance at the box ([compiler §6.7](compiler.md#67-the-definition-time-check)) and compiles it for the types it is given ([compiler §6.2](compiler.md#62-how-an-argument-is-compiled)).
- **Where its trait erases by default,** Julia enters it at the kept forms and adds its forwarder where it is defined ([compiler §6.3](compiler.md#63-the-forwarders)), the trait's parameters given or left open ([traits §7.8](traits.md#78-erasing-by-default-the-forwarder)). The library writes nothing.
- `@nospecialize t::X` and `@specialize t::X` are Julia's, as at any argument.
- **Per-method options:** `@bounded f(…) = …`, `@unbounded f(…) = …` and `@facts f(…) = …` put `Expr(:meta, :bounded)`, `Expr(:meta, :bounded, false)` and `Expr(:meta, :facts_always)` first in the body.

**Status:** Implemented, but for [traits T-125](traits.md#19-deviations) and [compiler C-112](compiler.md#deviations) (`@nospecialize` at a trait argument).

---

## 6. Scopes

`@trait_module opts…`, before the module's first method, emits:
- `Base.Experimental.@compiler_options facts=true bounded=true no_pirates=true`, with the options as written ([compiler §2.1](compiler.md#21-the-module-option));
- `using` of the library's names.

The module's statements are Julia's; nothing is rewritten. At the module's end (the module-end hook, [compiler §10.1](compiler.md#101-definition-and-image-hooks)), methods whose check waited are checked, and `struct S <: X` without its `@implement` is refused.

**Status:** Implemented.

---

## 7. `Dynamic{X}` and `Compiled{T}`
<a id="7-dynamicx-keep-casts"></a>

```julia
struct Dynamic{X}; object::X; end       # in Core: the box
struct Compiled{T}; object::T; end      # in Core: the wrapper
compiled_for(x) = Compiled(x)           # the library's
```

- **`Core` defines both structs,** so that a forwarder made where a method is defined names them ([compiler §6.9](compiler.md#69-the-kept-forms-in-core)). Neither has a rule of subtyping; the library declares their memberships and defines their methods.
- **Their memberships** in each trait `X` are declared by `@trait X`, forwarding by `object` (§2). A box's forwarding field is typed `X`, abstract, so code for a `Dynamic{X}` is compiled once per trait instance. A wrapper's is typed by its object's type, so code for it is compiled per type.
- **Their operations** are their forwarding methods (§2): at `Dynamic{<:X}`, an operation on a value typed by its trait ([compiler §7.1](compiler.md#71-the-rule)); at `Compiled{<:X}`, a static call of the object's method.
- **Their declared fields:** `getproperty` and `setproperty!` at a declared name read and write `object`'s field; at a box, asserted to the declared type. A wrapper forwards every property to its object. They are the library's methods on these types.
- **The box's constructor:** `Dynamic{X}(d::Dynamic{X})` is `d`; a box of a subtrait, or a wrapper, gives its object boxed at `X`; a value that is not a member raises `TypeError`.
- **The wrapper's constructor:** `Compiled(d)` of a box is the wrapper of its object; `Compiled(w)` of a wrapper is `w`.
- **A wrapper's call** forwards any arguments to its object, so a wrapped function is called as the function is (traits §9).
- **Storage:** `Base.convert(::Type{Dynamic{X}}, x)` boxes, and is the identity at a box of `X` ([traits §8.1](traits.md#81-fields-and-containers-typed-by-a-trait)).
- `unwrap(t)` is `getfield(t, :object)` for both; `==`, `isequal` and `hash` by the objects' `===`; `show` prints `Dynamic{Shape}(Circle(1.0))` and `Compiled(Circle(1.0))`.
- **`compiled_for(x)`** is the library's function. The library exports it, as any name.

**Status:** Implemented, but for [compiler C-113](compiler.md#deviations) (the wrapper the library's type).

---

## 8. `like` and `withfields`

`like`, `withfields` and forwarding with `by` (§3, step 6) are the library's conveniences, outside the language's core description ([traits §5.5](traits.md#55-forwarding-with-by), [§6.5](traits.md#65-results)): each is written with the core's forms, a membership and methods.

- `like(t, x)` calls the library's rebuilding function at `t`'s type:
  - a member that forwards by a field has a method of its own there, defined in the declaring module by its `@implement … by f`, with the member's forwarding methods: the type's positional constructor called with every field of `t` in order, the forwarding field replaced by `x`. Where a type forwards by several fields, the first declared is the one rebuilt;
  - any other type serves its trait by its own methods: the general method checks that `x` is of `t`'s type family and returns it;
  - a box `Dynamic{X}`: a `Dynamic{X}` of `x`; a wrapper: the wrapper of `like` of its object.
- `withfields(t; name = v, …)` calls the positional constructor with the named fields replaced. The call is made from `t`'s type and the names when the method is compiled.
- Nothing is looked up when either runs. Both are fully typed where the constructor's call is, and a package's image keeps a member's rebuilding method as it keeps its forwarding methods.
- A type without a positional constructor that takes every field in order cannot be rebuilt. The call raises Julia's `MethodError` at the constructor, with the library's hint: the constructor to define.

**Status:** Implemented (test `core.jl`; gate `like_precompiled`).

---

## 9. `Callable`

- `Core.Callable{A, S}` is a set of Julia's. Core's build declares `Function` a member of every instance, and that it erases by default ([compiler §7.4](compiler.md#74-callables-call), [§6.3](compiler.md#63-the-forwarders)).
- **`@implement Callable T`** declares a callable type that is no `Function` a member of every instance: one entry, its inputs free.
- **The library declares the kept forms' memberships:** the families `Dynamic{Z} where {A, S, Z <: Callable{A, S}}` and `Compiled{Z} where {A, S, Z <: Callable{A, S}}` in `Callable{A, S}`, as `@trait` does for a trait (§2).
- **`Dynamic{Callable{A, S}}`'s constructor** tests `hasmethod(f, A)` and raises the `MethodError` a call at `A` would; its call method asserts the arguments to `A` and the result to `S`. A wrapper's call method forwards any arguments to its object (§7).
- It adds the error hints of [traits §9](traits.md#9-functions-callable): where a function has no method at `A`, the hint names the declaration and the function's methods near `A`; where a result fails its check, the hint names `S`.

**Status:** Implemented, but for L-58 and [compiler C-146](compiler.md#deviations).

---

## 10. BaseTraits

- BaseTraits is a module of the library (`TraitWorld.BaseTraits`, a trait module), its names exported with the library's. Its traits are ordinary `@trait` declarations.
- Base's types join by memberships of Base's abstract types, declared in BaseTraits, which owns the traits: `@implement Indexable{T} AbstractVector{T} where {T}`, `@implement Keyed{K, V} AbstractDict{K, V} where {K, V}`. A view joins where its parent does: `@implement MutableIndexable{T} SubArray{T, 1, P} where {T, P <: MutableIndexable{T}}`. LinearAlgebra and Dates are dependencies of the library, so their types' memberships hold in every load order.
- `Solvable`'s operation is LinearAlgebra's `ldiv!`; each factorization that solves, and each matrix type `factorize` returns, joins by its own `ldiv!`. `LinearOp`'s operation is BaseTraits' `apply!`; `AbstractMatrix` joins with the block `apply!(y, A, x) = mul!(y, A, x)`.
- `textbound(T::Type)` is a method of `textbound` beside the operation: `nothing` by default, a constant for the types of fixed width.
- `@unbounded asvector(x::Indexable{T})` builds `IndexableVector{T, typeof(x)}(x)`, a struct `<: AbstractVector{T}` with linear indexing whose `getindex` calls `Indexable`'s operations with the member's own bounds checks.
- `HasProperty{N, R}`'s operation is `getproperty` at the constant name `N`. A member's own `getproperty` serves it; on a value typed by the trait, the compiler's rule for operations gives `x.N` the declared type `R` ([compiler §7.1](compiler.md#71-the-rule)).
- `retain!` is a method of the library at `All{MutableIndexable{T}, Resizable{T}}`.

**Status:** Implemented, but for L-66 (`asvector`).

---

## 11. Checks, errors, and what images keep

| When | What runs | Where |
|---|---|---|
| `@trait` | the body's form | the macro |
| `@implement` | ownership; the checks of §3 | the expansion's top-level code |
| a member's first use | the checks of §3, for that member | the member hook (§4) |
| a method's definition, before it is visible | a pirate in a `no_pirates` module; strict mode's walk; the same walk over the check's instances (§3, step 7): a method that would end a fixed call's instance, or a checked call's, and there make the operation ambiguous at the member or serve it with a result outside the declared one, inferred before the method exists; a method that is not bounded and not marked `@unbounded`, in a `bounded` module (its instance at the box, [compiler §6.7](compiler.md#67-the-definition-time-check)) | the definition hook ([compiler §10.1](compiler.md#101-definition-and-image-hooks)) |
| a module's end | the check of methods that waited; a `struct S <: X` without its `@implement` | the module-end hook ([compiler §10.1](compiler.md#101-definition-and-image-hooks)) |
| an image's activation | the methods the records refuse and, in strict mode, winning pirates, left inactive with a warning | the image hook |
| a membership | the ambiguity report | the runtime ([compiler §5.4](compiler.md#54-the-ambiguity-report-at-a-membership)) |
| a `MethodError` at a method at a trait, or at an operation's function | the hints of [traits §11.4](traits.md#114-hints), the declared signature read from the contract | `Base.Experimental.register_error_hint` |

**Errors** are the library's types `ImplementError`, `OwnershipError`, `TraitUseError` and `PirateError`, each with the message of [traits §11.3](traits.md#113-errors-and-their-messages). `MethodError` and `TypeError` are Julia's.

**What a package image keeps:**
- its traits' contracts, with their `TypeName`s;
- its memberships, in the image's list ([compiler §9](compiler.md#9-images-and-the-machine-code-cache));
- the members of patterns checked while it was built: the pairs (member type, trait) whose check passed. A session that loads the image does not check them again;
- the check's instances (§3, step 7), with their edges, as code;
- code compiled ahead.

**The check's instances for an image's memberships** are validated with the image at its load. A method of the session that ends one fails its validation: that instance alone is inferred again, and a result outside the declared one is reported ([traits §12.3](traits.md#123-strict-mode)).

**Status:** Implemented; the check's instances as the records, kept and validated with an image: Planned, with [traits T-129](traits.md#19-deviations) and [compiler C-115](compiler.md#deviations).

---

## 12. Compiling ahead

While a package that declares `@implement X S` is precompiled:
- for each method at `X` or a supertrait in the set-to-methods index ([compiler §5.1](compiler.md#51-the-method-table)), with one trait argument, bounded there, and concrete other arguments, a compile request at `S`'s type;
- for a method at a trait that erases by default, nothing: its instance at the box is compiled where the method is defined, by its definition-time check, in the method's own package (§11);
- the targets of the table of a call's targets for `S` ([compiler §7.3](compiler.md#73-the-table-of-a-calls-targets)).

`JULIA_TW_AHEAD=0` turns it off. A workload is PrecompileTools' `@compile_workload`.

- The compile request at a method at the set is Julia's `precompile` of the signature at `S`'s type: the instance a call at `S` runs ([compiler §6.2](compiler.md#62-how-an-argument-is-compiled)).
- The set-to-methods index is read with `jl_open_set_methods_of(X)`; `ahead_requests(X, S)` lists the requests.

**Status:** Implemented, but for L-66 (gate `ahead_two_packages`).

---

## 13. Strict mode

- **Turned on** by `TraitWorld.strict!(true)` or `JULIA_TW_STRICT=1`.
- **At a method's definition, before it is visible,** the definition hook finds the facts the method would win at:
  - from the backedges of the specializations it could take over and of the method table;
  - from each, the callers' backedges, transitively, through the plain code that code compiled by facts rests on, to code compiled by facts.

  It refuses a pirate that wins there (`PirateError`). After the definition, validation's log is checked: a hit the walk missed deletes the method and raises.
- **At a pirate's membership** ([traits §12.2](traits.md#122-pirates)), before it is declared, the library finds the facts it would change:
  - the absence edges its method would meet ([compiler §5.6](compiler.md#56-the-memberships-method-and-the-edges)), from the method table's backedges;
  - for each method at the trait or a trait it joins, the facts that method would win at, by the walk above, at the method's signature with the member in the trait's place ([compiler §10.2](compiler.md#102-hooks-for-strict-mode)).

  It refuses a membership that changes one (`PirateError`). After the declaration the log is checked as after a definition.
- **At an image's activation,** the image hook does the same for the image's methods and memberships. A refused membership's method stays inactive, and the runtime refuses its entry ([compiler §9](compiler.md#9-images-and-the-machine-code-cache)).
- **At a membership** (`@implement`, a trait's supertraits, `Dynamic{X}`'s membership), the runtime refuses one that makes methods ambiguous ([compiler §4.3](compiler.md#43-worlds)); the library raises `ImplementError`.
- **After an image's load,** the report of edges that failed validation names a pirate loaded earlier.
- **Deletions and bindings redefined from other modules** are refused through their hooks ([compiler §10.2](compiler.md#102-hooks-for-strict-mode)).

**Status:** Implemented, but for [traits T-96, T-112](traits.md#19-deviations).

---

## 14. Fully typed mode, concrete parts, closed programs

- **`@enforce_fully_typed f(…) = …`** and **`@warn_not_fully_typed`** add `Expr(:meta, :fully_typed_enforce)` or `:fully_typed_warn` to the method ([compiler §2.7](compiler.md#27-fully-typed-mode)). Before `@trait_module` they add the option `fully_typed = enforce` or `warn` to its `@compiler_options`.
- **The hook** (`jl_set_fully_typed_hook`) receives the compiler's site: it builds `fully_typed`'s report at the instance's signature, once per instance. Where the report lists a call, it raises `NotFullyTypedError` or warns; where it lists none, it does nothing.
- **`fully_typed(f, argtypes)`** has two parts:
  - **the calls** are the build's own check's ([compiler §2.7](compiler.md#27-fully-typed-mode)): `Compiler.closed_check` at the signature's method instance, with the build's replacements of Base as its overlay (below);
  - **the root causes** come from a walk of the session's own inference from the signature. Each signature it reaches is inferred by facts, to the IR before inlining. A call is a run-time site there by its call info: no info at a generic function, an unknown function value, a splat left to run time, a call in the latest world, an argument compiled for a type the caller does not know. A site's root cause is traced in the code: an argument, a field's declared type, a container's element type, a call's result through up to three callees, a variable whose type differs between paths, a global. The walk stops after 400 signatures;
  - **each call the check lists is reported at the walk's site for it:** the same call, or the nearest call above it in the check's chain of callers that the walk reported. That site is in the user's code and has the root cause. A call with no such site is reported as the build names it, with the chain of callers.
- **The build's Base** ([traits §16](traits.md#16-compiling-ahead-closed-programs)): an overlay method table of the library (`Base.Experimental.@MethodTable`), filled once a session, at the first check, from the files beside Julia's build script (`juliac-trim-base.jl`, `juliac-trim-stdlib.jl`):
  - each file is included into a module of its own whose `@eval` hands every statement to the library;
  - a method's definition is evaluated in the module the file names, under `Base.Experimental.@overlay` with the library's table. It replaces nothing in the session;
  - a definition of a function that does not exist yet is evaluated as written: it adds a function, and replaces nothing;
  - any other statement (a binding, a setting of a function's type) is left out and listed (`build_base_report()`);
  - nothing is read while a package is precompiled or in a build's own process.
- **Concrete parts:** in a trait's body, `@enforce_concrete_only` and `@warn_on_abstract` name parameters and `Self` in the contract; `check_member` checks them for each contract, a supertrait's included, at a concrete member. Before a method, the macro puts a check per named part at the top of its body: a `where` variable's type, and an argument's `Self` from the argument's type, a constant where the call is compiled (a generated predicate); a box is not checked, a wrapper's `Self` is its object's type.
- **`verify_main(main, argtypes)`** is the same walk from `main`: its targets are the signatures the code resolves, a function passed at a `Callable{A, S}` argument at `A`, and each declared member (the set's candidates) of an operation on a value known by its trait; its holes are the calls the build's check lists.

**Status:** Implemented, but for [traits T-109](traits.md#19-deviations) (tests `fullytyped.jl`, `verify.jl`).

---

## 15. Deviations

The rows below are where the implementation falls short of this page; the heads are in [the state](../state.md).

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| L-58 | [§9](#9-callable) | Where a `Callable`'s result fails its check, a hint names `S`. | Julia's `TypeError` names the expected type, without the hint. | TraitWorld `src/callable.jl` |
| L-64 | [§3](#3-implement) | The library's extension for Revise lists the memberships an expression declared and takes back, with `delete_membership`, those a revised file no longer has. | No extension for Revise: Revise re-evaluates a changed `@implement` (a redeclaration) and leaves a deleted one in force. `delete_membership` itself is built ([traits §5.13](traits.md#513-taking-a-membership-back)). Revise is not in the workspace's depot, so the extension is neither built nor tested. | TraitWorld `src/delete.jl`; `Project.toml` (no `[weakdeps]` entry for Revise) |
| L-66 | [§12](#12-compiling-ahead), [§10](#10-basetraits) | Compiling ahead asks Julia's `precompile` of the signature at `S`'s type, and nothing per member for a method that erases; `asvector` stores its argument. | `ahead.jl` asks the attribute's instance (`jl_attribute_dynamic_bits`, `jl_attributed_mi`), the set's instance where the method's attribute is `Dynamic`. BaseTraits' `asvector` stores `keep(x)`, which is `x` there. | TraitWorld `src/ahead.jl` (`ahead_requests`, the request loop), `src/BaseTraits.jl` (`asvector`) |
| L-67 | [§2](#2-trait) | `@trait` defines, at each kept form, a method of each equation's function that returns the parameter's value. | It defines none: `eltype` of a box or a wrapper is Base's fallback, `Any` ([traits T-130](traits.md#19-deviations)). | TraitWorld `src/trait.jl` (the expansion) |

**Retired IDs** (their rows are in [the ledger](../../attic/writeup/record/deviations-retired.md)): L-1 to L-57, L-59, L-63, L-65, L-68.
