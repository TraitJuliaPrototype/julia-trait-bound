# Lowering: the reference

**Draft** (W-105; [the folder's README](README.md)). This page defines what the trait library's macros expand to on Julia's interfaces ([`compiler.md`](compiler.md)), within the facts mode's contract ([`facts.md`](facts.md)). It decides nothing the other three references decide; where it seems to, they win.

The language puts most of the work in Julia: a trait is an abstract type, a membership is an entry of the type system, a method at a trait is a Julia method, code per key is a compilation signature. What remains for the library is to declare, to check, and to report.

## Contents

1. [Summary](#1-summary)
2. [`@trait`](#2-trait)
3. [`@implement`](#3-implement)
4. [Members checked at their first use](#4-members-checked-at-their-first-use)
5. [Methods at traits](#5-methods-at-traits)
6. [Scopes](#6-scopes)
7. [`Dynamic{X}`, `keep`, casts](#7-dynamicx-keep-casts)
8. [`like` and `withfields`](#8-like-and-withfields)
9. [`Callable`](#9-callable)
10. [BaseTraits](#10-basetraits)
11. [Checks, errors, and what images keep](#11-checks-errors-and-what-images-keep)
12. [Compiling ahead](#12-compiling-ahead)
13. [Strict mode](#13-strict-mode)
14. [Deviations](#14-deviations)

---

## 1. Summary

| Construct | Becomes | Made |
|---|---|---|
| `@trait X …` | an open abstract type; its supertraits' memberships; the operation functions; the trait's method per operation; the contract on the type's `TypeName`; `Dynamic{X}`'s membership | at the declaration |
| `@implement X S …` | the block's methods; the checks; a membership entry with its receiver; the override records | at the declaration |
| a family, an abstract type or a trait as a member | a membership entry with a pattern; each member's check | the entry at the declaration; each member's check at its first use |
| `struct S <: X` | Julia's struct, whose supertype is `X`; the `@implement X S` that must follow | Julia's definition; the check at the `@implement` |
| a method at a trait | nothing: a Julia method; the compiler classifies it | — |
| `@trait_module` | module option bits | before the module's first method |
| `Dynamic{X}`, `keep`, casts | a struct of `Core` with the library's memberships and methods; a compiler-resolved call; a form of the call | — |

**Status:** Planned (W-102, W-103).

---

## 2. `@trait`

`@trait X{P…} <: (A, …) begin … end` runs in the declaring module, at the declaration. It defines, in this order:

- **The abstract type** `X{P…}`, created open ([compiler §4.1](compiler.md#41-sets)), its declared supertype `Any`. Bounds on parameters are the type's bounds.
- **Its supertraits' memberships:** for each supertrait `A{q…}`, `jl_declare_membership(X{P…} where {P…}, A{q…}, nothing, mod, nothing)` ([compiler §4.2](compiler.md#42-memberships)).
- **The operation functions:** a plain name makes a new generic function in the module; a qualified name uses the existing one.
- **The trait's method for each operation and arity:** a method at `X` with the operation's declared signature and result, flagged as covering every member ([compiler §6.8](compiler.md#68-a-declared-result-on-method)). Its body:
  - for a member that forwards, the operation called on `Core.trait_receiver(t, X)`, which inference resolves to the forwarding field at a member and to the receiver's part at a key ([compiler §6.5](compiler.md#65-the-calling-convention)); a declared field through `Core.trait_field(t, X, name)`;
  - for a member that a default serves, the default's body;
  - otherwise unreachable: such a member was refused at its check.
- **The contract** on `X`'s `TypeName` ([compiler §4.1](compiler.md#41-sets)):
  - the operations, each with its trait's method;
  - the declared fields, with their types and whether `@const`;
  - each parameter's definition: a field's pattern, an equation (a function of `Self`), or stated;
  - the input parameters;
  - which operations have defaults;
  - the default attribute bit;
  - the concreteness declarations.

  It is fixed at the declaration and saved with the `TypeName` in images.
- **`Dynamic{X}`'s membership:** the family `Dynamic{Z} where {P…, Z <: X{P…}}` in `X{P…}`, forwarding by its field `object` (§7). So `Dynamic{Sub}` for a subtrait `Sub` and `Dynamic{All{X, Y}}` are members of `X` too.
- `Expr(:latestworld)`.

A trait's declaration changes no compiled code: its methods are at a set with no members yet.

**Status:** Planned (W-102, W-103).

---

## 3. `@implement`

`@implement X{p…} S how` runs at the top level of the declaring module:
1. **Ownership** (§11): the module's package owns `X` or `S`, or is a joint owner; an extension names its triggers.
2. **The block's methods,** where there is a block: each a method of the operation's function, the receiver typed `S`, unannotated arguments typed as declared.
3. **The checks** ([traits §5.10](traits.md#510-checks)), by plain inference of each serving method at `S` and the declared argument types, in a cache of the checks' own:
   - completeness;
   - results;
   - fields;
   - parameters: matched from fields, equations evaluated at `Self`, stated values, bounds;
   - agreement with `S`'s memberships of supertraits;
   - concreteness.
4. **A refusal** deletes the block's methods and raises `ImplementError`. Nothing is declared.
5. **The receiver** ([traits §7.2](traits.md#72-the-key)): `S` where it serves an operation by its own method, the forwarding field where it forwards, none where defaults serve every operation. The runtime computes the key from it ([compiler §6.1](compiler.md#61-the-key-as-a-type)).
6. **The membership:** `jl_declare_membership(S, X{p…}, mod, by, receiver)`, then `Expr(:latestworld)`. The runtime refuses a second instance of `X` for `S` ([compiler §4.6](compiler.md#46-one-instance-per-member)); the library then deletes the block's methods and raises `ImplementError`.
7. **The override records:** for each operation a default serves at `S`, a record that the definition hook reads (§11).
8. **While the package is precompiled:** compiling ahead (§12).

`@implement (X, Y) S …` repeats steps 3 to 8 per trait, with step 2 once.

**`struct S <: X`** is Julia's struct definition; `X` is its supertype. The library requires `@implement X S` in the same module, after `S`'s methods. That declaration runs steps 1 to 5 and 7 to 8, and records the receiver on `S`'s `TypeName` in place of step 6. A module that ends with a `struct S <: X` and no `@implement X S` is refused at its end ([compiler §10.1](compiler.md#101-definition-and-image-hooks)'s module-end hook). A use of `S` through `X` before the declaration raises `ImplementError` naming it (§4); the declaration replaces that kept failure.

**A family variable bounded by a `Union`** (`@implement BoundedText I where {I <: Base.BitInteger}`) declares one membership per type of the union.

**Status:** Planned (W-102, W-103); `struct S <: X` decided (the user, 2026-11-06, Q8 (c)).

---

## 4. Members checked at their first use

A membership with a pattern (a family `S{P} where P`, a closed abstract type, a trait) makes members whose checks are not run at the declaration. Their keys are the runtime's, from the entry ([compiler §6.1](compiler.md#61-the-key-as-a-type)).

- **The pattern states the trait's instance** with the family's variables, constants and type constructors: `@implement Iterable{T} Wrapped{T} where {T}`. Where an equation defines a parameter (`T = eltype(Self)`), the pattern states it too, and each member's check compares the equation's value with the pattern's. A family whose instance cannot be written so is refused at its declaration, naming the parameter.
- **The member hook** ([compiler §10.4](compiler.md#104-the-member-hook)): the runtime calls the library at a member's first use, at dispatch or before code that relies on the member is published. The library runs the member's checks (§3, step 3), or raises `ImplementError`. The answer is kept per (member type, trait) on the member's `TypeName`, and every later use reads it; a failure is kept too, and raised at every use.
- Inference never calls the hook, and no runtime lock is held while it runs. A check that reaches its own member again raises.
- Members checked while a package image is built are kept in the image with the methods each check relied on. At load, a member whose relied-on methods dispatch the same is not checked again.

**Status:** Planned (W-102). The pattern rule for equations is mine (2026-11-06; [the README](README.md#the-choices-in-this-draft)).

---

## 5. Methods at traits

- **A method at a trait is defined by Julia** with nothing around it. The compiler classifies it per trait argument ([compiler §6.7](compiler.md#67-the-definition-time-check)) and compiles it per key, per type or once.
- `@nospecialize t::X` and `@specialize t::X` set the method's attribute bits at the argument ([compiler §6.3](compiler.md#63-the-attribute-at-a-call)). They are Julia's macros.
- **Per-method options:** `@bounded f(…) = …`, `@open f(…) = …` and `@facts f(…) = …` put `Expr(:meta, :bounded)`, `Expr(:meta, :bounded, false)` and `Expr(:meta, :facts_always)` first in the body.

**Status:** Planned (W-102).

---

## 6. Scopes

`@trait_module opts…`, before the module's first method, emits:
- `Base.Experimental.@compiler_options facts=true bounded=true no_pirates=true first_seen=true`, with the options as written, and `dynamic=true` where written ([compiler §2.1](compiler.md#21-the-module-option));
- `using` of the library's names.

The module's statements are Julia's; nothing is rewritten. At the module's end (the module-end hook, [compiler §10.1](compiler.md#101-definition-and-image-hooks)), methods whose classification waited are classified, and `struct S <: X` without its `@implement` is refused.

**Status:** Planned (W-103); the options decided (the user, 2026-11-06, Q2 (a)).

---

## 7. `Dynamic{X}`, `keep`, casts

```julia
struct Dynamic{X}                                   # in Core
    object::X
    function Dynamic{X}(@nospecialize(x)) where {X}
        X isa UnionAll && throw(ArgumentError("Dynamic{$X} needs the trait's parameters"))
        x isa Dynamic && (x = getfield(x, :object))
        x isa X || throw(TypeError(:Dynamic, "", X, x))
        new{X}(x)
    end
end
```

- **`Core` defines the struct,** so that the compiler can make one for `keep` ([compiler §6.9](compiler.md#69-casts-and-keep)). It has no rule of subtyping; the library declares its memberships and defines its methods.
- **Its membership** in each trait `X` is declared by `@trait X`, forwarding by `object` (§2). The forwarding field's type is `X`, abstract, so the member's key is the erased key: code for a `Dynamic{X}` is compiled once. The constructor compiles nothing per value type.
- **Its operations** are the trait's methods, which forward to `object`, an operation on a value typed by its trait ([compiler §7.1](compiler.md#71-the-rule)).
- **Its declared fields:** `getproperty(d::Dynamic{X}, s::Symbol)` and `setproperty!` at a declared name read and write `object`'s field, asserted to the declared type. They are the library's methods on its own type.
- `unwrap(d) = getfield(d, :object)`; `==`, `isequal` and `hash` by the objects' `===`; `show` prints `Dynamic{Shape}(Circle(1.0))`.
- **`Dynamic` of a value that is already a `Dynamic`** holds its object.
- **`keep(x)`** is `Core.keep`, resolved by the compiler ([compiler §6.9](compiler.md#69-casts-and-keep)).
- **Casts** `compiled_for` and `with_dynamic` are `Core.compiled_for` and `Core.with_dynamic`, names Julia's front end reserves as it reserves `ccall`, recognized in a call's arguments and lowered to `Core.attributed_call` ([compiler §6.9](compiler.md#69-casts-and-keep)). The library re-exports them and defines `detect_unused_casts(mod)`.

**Status:** Planned (W-102).

---

## 8. `like` and `withfields`

- `like(t, x)` reads `t`'s membership in the trait the calling method names for `t`:
  - served by its own methods: checks that `x` is of `t`'s type family and returns it;
  - forwarding by a field: calls `t`'s type's positional constructor with every field of `t`, the forwarding field replaced by `x`;
  - a `Dynamic{X}`: a `Dynamic{X}` of the rebuilt object.
- `withfields(t; name = v, …)` calls the positional constructor with the declared fields replaced.
- A type without a positional constructor that takes every field in order cannot be rebuilt: `MethodError`, with a hint naming the constructor needed.

**Status:** Planned (W-103).

---

## 9. `Callable`

- `Core.Callable{A, S}` is a set of Julia's whose memberships a function's methods decide ([compiler §7.4](compiler.md#74-callables-call)). Its default attribute bit is `Dynamic`.
- **The library declares one membership for it:** the family `Dynamic{Z} where {A, S, Z <: Callable{A, S}}` in `Callable{A, S}`, as `@trait` does for a trait (§2). `Dynamic{Callable{A, S}}`'s call method asserts the arguments to `A` and the result to `S`.
- It adds the error hints of [traits §9](traits.md#9-functions-callable): where a function is not a member, the hint names its methods near `A`; where a result fails its check, the hint names `S`.

**Status:** Planned (W-102).

---

## 10. BaseTraits

- BaseTraits' traits are ordinary `@trait` declarations of the library.
- Base's types join by memberships of Base's abstract types, declared in BaseTraits, which owns the traits: `@implement Indexable{T} AbstractVector{T} where {T}`, `@implement Keyed{K, V} AbstractDict{K, V} where {K, V}`. LinearAlgebra and Dates are dependencies of the library, so their types' memberships hold in every load order.
- `@open asvector(x::Indexable{T}) = IndexableVector{T, typeof(keep(x))}(keep(x))`, a struct `<: AbstractVector{T}` whose `getindex` and `size` call `Indexable`'s operations.
- `HasProperty{N, R}`'s operation is `getproperty` at the constant name `N`. A member's own `getproperty` serves it; on a value typed by the trait, the compiler's rule for operations gives `x.N` the declared type `R` ([compiler §7.1](compiler.md#71-the-rule)).
- `retain!` is a method of the library at `All{MutableIndexable{T}, Resizable}`.

**Status:** Planned (W-103).

---

## 11. Checks, errors, and what images keep

| When | What runs | Where |
|---|---|---|
| `@trait` | the body's form | the macro |
| `@implement` | ownership; the checks of §3 | the expansion's top-level code |
| a member's first use | the checks of §3, for that member | the member hook (§4) |
| a method's definition, before it is visible | an override of an operation a default serves at a member (the override records); a pirate in a `no_pirates` module; an open method not marked `@open` in a `bounded` module (the compiler's classification) | the definition hook ([compiler §10.1](compiler.md#101-definition-and-image-hooks)) |
| a module's end | the classification of methods that waited; a `struct S <: X` without its `@implement` | the module-end hook ([compiler §10.1](compiler.md#101-definition-and-image-hooks)) |
| an image's activation | overrides and, in strict mode, winning pirates left inactive | the image hook |
| a membership | the ambiguity report | the runtime ([compiler §5.4](compiler.md#54-the-ambiguity-report-at-a-membership)) |
| a `MethodError` at a method at a trait | the hints of [traits §11.4](traits.md#114-hints) | `Base.Experimental.register_error_hint` |

**Errors** are the library's types `ImplementError`, `OwnershipError`, `TraitUseError` and `PirateError`, each with the message of [traits §11.3](traits.md#113-errors-and-their-messages). `MethodError` and `TypeError` are Julia's.

**What a package image keeps:**
- its traits' contracts, with their `TypeName`s;
- its memberships, in the image's list ([compiler §9](compiler.md#9-images-and-the-machine-code-cache));
- the members checked while it was built, with the methods each check relied on;
- the override records;
- code compiled ahead.

**Status:** Planned (W-103).

---

## 12. Compiling ahead

While a package that declares `@implement X S` is precompiled:
- for each method at `X` or a supertrait in the set-to-methods index ([compiler §5.1](compiler.md#51-the-method-table)), with one trait argument, fully bounded there, and concrete other arguments, a compile request at `S`'s key;
- for a method with `Dynamic` trait arguments, at the erased keys;
- the targets of the table of a call's targets for `S` ([compiler §7.3](compiler.md#73-the-table-of-a-calls-targets)).

`JULIA_TW_AHEAD=0` turns it off. A workload is PrecompileTools' `@compile_workload`.

**Status:** Planned (W-103).

---

## 13. Strict mode

- **Turned on** by `TraitWorld.strict!(true)` or `JULIA_TW_STRICT=1`.
- **At a method's definition, before it is visible,** the definition hook finds the facts the method would win at:
  - from the backedges of the specializations it could take over and of the method table;
  - from each, the callers' backedges, transitively, through the plain code that code compiled by facts rests on, to code compiled by facts.

  It refuses a pirate that wins there (`PirateError`). After the definition, validation's log is checked: a hit the walk missed deletes the method and raises.
- **At an image's activation,** the image hook does the same for the image's methods.
- **After an image's load,** the report of edges that failed validation names a pirate loaded earlier.
- **Deletions and bindings redefined from other modules** are refused through their hooks ([compiler §10.2](compiler.md#102-hooks-for-strict-mode)).

**Status:** Planned (W-103).

---

## 14. Deviations

The library on the unified build is not begun; nothing is recorded.

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
