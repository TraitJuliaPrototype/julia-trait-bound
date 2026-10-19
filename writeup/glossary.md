# Glossary

The project's terms, in plain words first. Each entry gives:
- **Here:** what the term means in this project;
- **Origin:** where the word comes from, what other languages call the same thing, and whether Julia already has it;
- **Defined in:** where the precise definition is.

The precedents come from the research in [`other-languages.md`](other-languages.md) and [`design/comparison.md`](design/comparison.md). A precedent marked *(not in the research)* is added from general knowledge of the language. Julia's own terms are marked as such.

The terms changed on 2026-10-19. Documents before that date say "conformance" for an implementation and "implementing type" for the receiver type (see [Retired terms](#retired-terms)).

## Index

[Associated type](#associated-type) ·
[Bound and bounded function](#bound-and-bounded-function) ·
[Call-site split](#call-site-split) ·
[`Callable`](#callable-dynamiccall-and-compiledcall) ·
[CodeInstance](#codeinstance) ·
[`CompiledCall`](#callable-dynamiccall-and-compiledcall) ·
[Concrete mode](#concrete-mode-and-fully-typed) ·
[Conforms to](#conforms-to) ·
[Declared field](#declared-field) ·
[Default](#default) ·
[Definition checking and archetype](#definition-checking-and-archetype) ·
[Dispatch](#method-table-and-dispatch) ·
[`Dynamic{X}`](#dynamicx) ·
[`DynamicCall`](#callable-dynamiccall-and-compiledcall) ·
[Entry and worker](#entry-and-worker) ·
[Fact and fact signature](#fact-and-fact-signature) ·
[Facts mode and the setting `all`](#facts-mode-and-the-setting-all) ·
[Family](#family) ·
[Forwarding (`by`)](#forwarding-by) ·
[Fully typed, the certificate](#concrete-mode-and-fully-typed) ·
[Generic implementation](#generic-implementation) ·
[Held view](#view-and-held-view) ·
[Identical or error](#identical-or-error) ·
[Implementation](#implementation) ·
[Invalidation](#invalidation) ·
[Key](#key) ·
[`Like`](#results-like-the-input-self-like-withfields) ·
[Method table](#method-table-and-dispatch) ·
[Named implementation](#named-implementation) ·
[Operation](#operation) ·
[Owner](#owner) ·
[Package extension](#package-extension) ·
[Pirate and piracy](#pirate-and-piracy) ·
[Receiver type](#receiver-type) ·
[Results like the input](#results-like-the-input-self-like-withfields) ·
[Run-time site](#run-time-site) ·
[`Self`](#results-like-the-input-self-like-withfields) ·
[Stakeholder](#stakeholder) ·
[Strict mode](#strict-mode) ·
[Trait](#trait) ·
[Trait module, trait code, plain code](#trait-module) ·
[Trait object](#trait-object) ·
[View](#view-and-held-view) ·
[`withfields`](#results-like-the-input-self-like-withfields) ·
[World and world age](#world-and-world-age) ·
[World-checked call-site cache](#world-checked-call-site-cache-proposed)

The entries are grouped by theme:
1. [Traits and their implementations](#traits-and-their-implementations)
2. [What library code sees](#what-library-code-sees)
3. [Values and functions of mixed types](#values-and-functions-of-mixed-types)
4. [Ownership](#ownership)
5. [The compiler](#the-compiler)
6. [Julia's own terms](#julias-own-terms)
7. [Retired terms](#retired-terms)

---

## Traits and their implementations

### Trait

- **Here:** an abstract type with a declared, checked contract. It declares operations with argument and result types, fields with types, and associated types as its parameters. Abstract types stay in Julia; traits are a kind of them.
- **Origin:**
  - Rust and Mojo say "trait"; Swift says "protocol"; C++20 says "concept".
  - A C++20 concept is a predicate on types. A Rust trait is not a type, except as `dyn Trait`. A Swift protocol is also a type (`any P`). Ours is an abstract type, and reads like one by position ([`comparison.md` §1](design/comparison.md#1-a-trait-is-an-abstract-type-with-behaviour)).
  - In Julia: abstract types play part of this role, without a checked contract. Base also uses "traits" for a dispatch pattern (`IndexStyle`, `IteratorSize`), known as "Holy traits": a value computed from a type, not a checked contract *(not in the research)*.
- **Defined in:** [`design.md` §1](design.md#1-terms), [§4.1](design.md#41-traits-and-implementations); [`mechanisms.md` §1](design/mechanisms.md#1-declaring-a-trait).

### Operation

- **Here:** a generic function declared at the trait, with argument and result types: `ncols(t::ColTable)::Int`. Every call on a trait object is checked against the declaration. An operation may be an existing function, such as `Base.length`.
- **Origin:** a Rust trait's methods, a Swift protocol's requirements *(wording: not in the research)*. In Julia: a generic function whose methods are declared at an abstract type, as `length(x::AbstractArray)`.
- **Defined in:** [`mechanisms.md` §1, "Operations"](design/mechanisms.md#operations).

### Bound and bounded function

- **Here:** a bound is a trait named at an argument: `colmean(t::ColTable, i::Int)`. A function with such an argument is a bounded function. It reaches the argument only through the trait's operations and fields. It is compiled per [key](#key).
- **Origin:**
  - Rust calls `T: Trait` a trait bound. Rust and Swift check generic code against its bounds ([`other-languages.md` §2](other-languages.md#2-checking-generic-code-where-it-is-written)).
  - In Julia: an argument annotated with an abstract type, `f(x::AbstractArray)`, plays the same role. A bound is written the same way ([`comparison.md` §1](design/comparison.md#1-a-trait-is-an-abstract-type-with-behaviour)).
- **Defined in:** [`design.md` §4.2](design.md#42-compiled-for-what-the-bound-can-see), [§5](design.md#5-the-three-rules) rule 3; [`mechanisms.md` §7](design/mechanisms.md#7-traits-as-abstract-types-and-dispatch).

### Conforms to

- **Here:** type `T` conforms to trait `X` when an [implementation](#implementation) of `X` for `T` is declared. A "conforming type" is such a type. TraitWorld answers the question with `conforms(T, X)`, which stands in for `T <: X` until traits are in the type system. `Callable` is the exception: anything callable conforms to it.
- **Origin:** Swift's wording: "a type conforms to a protocol". Mojo uses the same word ([`other-languages.md` §1](other-languages.md#1-conformance-declared-or-structural)). Rust says "a type implements a trait".
- **Defined in:** [`design.md` §4.1](design.md#41-traits-and-implementations); [`mechanisms.md` §2](design/mechanisms.md#2-how-a-type-conforms), §7.

### Implementation

- **Here:** the declaration `@implement X T` that type `T` joins trait `X`: "an implementation of `X` for `T`".
  - It is one line. Its operations are served by the type's own methods, by a field it forwards to (`by f`), or by the trait's defaults.
  - It is checked when it is declared: every operation and field exists, with the declared types.
  - It is never derived from the methods that exist. Base's throwing fallbacks would make such matching unsound.
  - It is a method of a registry (`conformance` in TraitWorld's code), declared so that it applies at no existing fact. So declaring one invalidates no compiled code.
- **Origin:**
  - Rust's `impl Trait for Type`; Java's and C#'s "implements" ([`decisions.md`](decisions.md), the row on terms of 2026-10-19). Go also says that a type "implements" an interface, but Go infers it from the methods *(not in the research)*.
  - Swift and Mojo call the declaration a "conformance". C++0x called it a "concept map", and C++20 dropped the declaration: its concepts match structurally ([`comparison.md` §2](design/comparison.md#2-implementations-are-declared)).
  - Declared implementations won in Rust, Swift and Mojo. Mojo added structural matching in 2024 and removed it in 2025 ([`other-languages.md` §1](other-languages.md#1-conformance-declared-or-structural)).
- **Defined in:** [`design.md` §1](design.md#1-terms), [§4.1](design.md#41-traits-and-implementations), [§4.4](design.md#44-overrides-belong-to-the-implementation); [`mechanisms.md` §2](design/mechanisms.md#2-how-a-type-conforms).

### Generic implementation

- **Here:** one implementation that covers every type that meets other traits: `@implement GTable R where {R: Indexable, eltype(R) == Vector{Float64}}`. Workers are still compiled per concrete key. A more specific implementation beats a generic one, and must declare the same parameter values.
- **Origin:**
  - Rust's blanket impls. Rust made adding a blanket impl a breaking change; Rust's specialization, which orders overlapping impls, has been unstable since 2016 ([`other-languages.md` §5](other-languages.md#5-overlap-more-specific-beats-generic)).
  - In Julia: a method at an abstract type, or with a `where` clause, serves every type it covers ([`comparison.md` §1](design/comparison.md#1-a-trait-is-an-abstract-type-with-behaviour), the table).
- **Defined in:** [`mechanisms.md` §3](design/mechanisms.md#3-generic-implementations); overlap: [`comparison.md` §5](design/comparison.md#5-who-may-implement-ownership-and-stakeholders).

### Named implementation

- **Here:** an implementation used only where a caller names it (`via(Fast, m)`), which anyone could write. It is deferred until traits are in the type system. The preferred form then is a value-level wrapper that conforms, a newtype: `Via{Fast}(x)`.
- **Origin:**
  - Jordan Rose lists "named conformances" among the options Swift should have had, beside owner-only conformances and wrapper types ([`other-languages.md` §4](other-languages.md#4-who-may-add-a-conformance-or-a-method)). Named impls are being proposed for Rust ([`comparison.md` §5](design/comparison.md#5-who-may-implement-ownership-and-stakeholders)).
  - Scala's implicits select an instance by imported scope; the design rejected that ([`comparison.md`](design/comparison.md), "Other options considered").
  - Haskell allows one instance of a class per type and uses newtypes for the others *(not in the research)*. That is the newtype form preferred here.
- **Defined in:** [`design.md` §4.7](design.md#47-the-rest-of-the-trait-language); [`mechanisms.md` §4](design/mechanisms.md#4-named-implementations-deferred).

### Family

- **Here:** one implementation for all instances of a parametric type, declared with `where`: `@implement Fam2 S2{P} where {P}`. Each member is fixed at its first use. Workers compile per instance.
- **Origin:** C++0x's templated concept maps ([`other-languages.md` §1](other-languages.md#1-conformance-declared-or-structural)). In Julia: a method with a `where` clause over a type's parameters.
- **Defined in:** [`mechanisms.md` §6](design/mechanisms.md#6-parametric-user-types-and-families); [`design.md` §4.4](design.md#44-overrides-belong-to-the-implementation).

### Default

- **Here:** an operation's body written in the trait, in terms of the other operations and the declared fields. An implementation may override it, but only when it is declared: which operations defaults serve is fixed then. A missing operation is an error at the implementation, never "not implemented" at a call.
- **Origin:**
  - Rust's default methods in a trait; Swift's protocol extensions *(not in the research)*.
  - In Julia: a fallback method at an abstract type, which subtypes override ([`comparison.md` §1](design/comparison.md#1-a-trait-is-an-abstract-type-with-behaviour)). Base's fallbacks may throw; a default never does.
- **Defined in:** [`mechanisms.md` §1, "Defaults"](design/mechanisms.md#defaults); [`design.md` §4.4](design.md#44-overrides-belong-to-the-implementation).

### Declared field

- **Here:** a field the trait requires, with a type: `u::U`, `@const p::P`. It is a stored field of the conforming type. It has the same name unless the implementation maps it (`name => label`). It is read at its byte offset. It is writable unless `@const`.
- **Origin:** Scala desugars a trait's `var` into a getter and a setter; Swift's protocols require properties `{ get set }` ([`mechanisms.md` §1](design/mechanisms.md#fields)). New over Julia: abstract types cannot require fields today.
- **Defined in:** [`mechanisms.md` §1, "Fields"](design/mechanisms.md#fields); [`design.md` §4.1](design.md#41-traits-and-implementations).

### Associated type

- **Here:** a trait's parameter, with one value per implementation, set by what the conforming type holds. `T` in `KVec{T}` is defined by a field's type, by an equation of `Self` (`T = eltype(Self)`), or stated in the implementation. They are first order: no input parameters, no equations between type functions.
- **Origin:**
  - Rust's associated types; Rust's RFC 195 argued for one value per implementation. Swift's protocols have them too ([`comparison.md` §7](design/comparison.md#7-the-complexity-budget)). Reasoning about them symbolically made Rust's and Swift's checking hard.
  - In Julia: a type parameter of an abstract type, as `T` and `N` in `AbstractArray{T, N}`. A type has one `AbstractArray` supertype, so one value of each.
- **Defined in:** [`mechanisms.md` §1, "Associated types"](design/mechanisms.md#associated-types); [`design.md` §4.1](design.md#41-traits-and-implementations).

### Forwarding (`by`)

- **Here:** an implementation that serves the operations through one field: `@implement ColTable Measurements by data`. The field's type is then the [receiver type](#receiver-type). So every type that forwards to a field of that type shares the library's code for it. Without `by`, `@implement` infers the field: the one field whose type implements the trait, else the field named `data`. Forwarding does not chain.
- **Origin:** Kotlin's `by` forwards an interface's methods to a field. Go's struct embedding satisfies an interface through the embedded field's methods. Rust writes it by hand or uses `Deref` ([`comparison.md` §3](design/comparison.md#3-compiled-for-what-the-bound-can-see), "At a glance"). None of them makes the forwarded field the compile key.
- **Defined in:** [`mechanisms.md` §2](design/mechanisms.md#2-how-a-type-conforms); [`design.md` §4.1](design.md#41-traits-and-implementations).

### Receiver type

- **Here:** the type of the value the operations are called on.
  - It is the conforming type when the type's own methods serve an operation.
  - It is the field's type when the implementation forwards to a field.
  - There is none when the trait's defaults serve every operation.
  - The value itself is the receiver.
- **Origin:** the receiver of a method call in Go, Kotlin and Swift ([`decisions.md`](decisions.md), the row on terms of 2026-10-19). Rust's reference also calls `self` the receiver ([`other-languages.md` §7](other-languages.md#7-static-and-dynamic-positions), "`Self` only as receiver").
- **Defined in:** [`design.md` §1](design.md#1-terms); [`mechanisms.md` §1, "Defaults"](design/mechanisms.md#defaults), [§16](design/mechanisms.md#16-the-trait-objects-layout).

### Key

- **Here:** what a bound can see of a value: the receiver type, if any, and the declared fields' types. A bounded function is compiled once per key, not per the argument's own type. Types that differ only in what the trait cannot see share compiled code.
- **Origin:** the project's term.
  - Go 1.18 compiles one generic instance per "GC shape", grouping types the generated code does not distinguish. .NET shares generic code among reference types ([`comparison.md` §3](design/comparison.md#3-compiled-for-what-the-bound-can-see), from memory and a review).
  - Julia compiles per concrete argument type. Its function-barrier idiom, passing only the fields an inner function needs, reaches the same shape by discipline.
- **Defined in:** [`design.md` §1](design.md#1-terms), [§4.2](design.md#42-compiled-for-what-the-bound-can-see); [`mechanisms.md` §17](design/mechanisms.md#17-caching-per-key).

---

## What library code sees

### Trait object

- **Here:** what library code receives for a bounded argument: the user's object, seen through the offsets of what the bound can see. It lives for one call. It is never passed bare to plain code; to keep it, the code stores it as a [`Dynamic{X}`](#dynamicx).
- **Origin:** Rust's "trait object" is a `dyn Trait` value, called through a table of pointers ([`other-languages.md` §7](other-languages.md#7-static-and-dynamic-positions)). Ours is static: one call, compiled per key. The counterpart of Rust's trait object here is `Dynamic{X}`.
- **Defined in:** [`design.md` §1](design.md#1-terms), [§4.2](design.md#42-compiled-for-what-the-bound-can-see); [`mechanisms.md` §16](design/mechanisms.md#16-the-trait-objects-layout).

### View and held view

- **Here:**
  - A view is the part of a trait object for one trait: where the receiver and the declared fields are. A value bounded by several traits gets one view per trait, and all of them read the same object.
  - A held view holds an immutable value whole, when the value is itself the receiver. There is no object or offset to read through, so a `Dynamic` of it is one box.
- **Origin:** the project's terms. A view reads the user's object in place, as Julia's `view` reads an array without copying *(an analogy, not in the research)*.
- **Defined in:** [`mechanisms.md` §5](design/mechanisms.md#5-several-traits-on-one-object), [§16](design/mechanisms.md#16-the-trait-objects-layout); [`design.md` §4.2](design.md#42-compiled-for-what-the-bound-can-see).

### Entry and worker

- **Here:** a bounded function has two parts.
  - The **entry** is an ordinary method. It translates each argument by its bound, once. It is small and is inlined into typed callers.
  - The **worker** is the body, compiled per tuple of keys.
- **Origin:** the project's terms. The shape is Julia's function barrier: a small outer function and a typed inner kernel (Julia's performance tips; *not in the research*). Rust's "generic hotpath, concrete coldpath" is a thin generic wrapper around a shared inner function ([`other-languages.md`](other-languages.md#what-is-new-in-our-design), "What is new in our design", item 1).
- **Defined in:** [`design.md` §1](design.md#1-terms); [`mechanisms.md` §7](design/mechanisms.md#7-traits-as-abstract-types-and-dispatch), "How the prototype does it".

### Trait module

- **Here:** a module declared `@trait_module`, whose code is written against traits. Its code is *trait code*; everything else is *plain code*. Its methods are compiled by facts.
- **Origin:** the project's term. It uses Julia's per-module compiler options, `Base.Experimental.@compiler_options`, which exist today for settings such as `optimize` and `infer` *(not in the research)*. The patched build adds `facts=true`.
- **Defined in:** [`design.md` §1](design.md#1-terms), [§6](design.md#6-what-julia-provides) part (B); [`mechanisms.md` §8](design/mechanisms.md#8-inside-a-trait-module).

### Definition checking and archetype

- **Here:** library code is checked once, where it is defined, for every type that will ever conform. Each bounded method is inferred at **archetypes**: a stand-in key per bound, whose operations and fields return values of their declared types and nothing more. A mistake is reported at its line, before any user type exists.
- **Origin:**
  - "Archetype" is C++0x's term. C++0x checked definitions through archetypes, and concepts were removed in 2009. C++20 checks only uses.
  - Rust, Swift and Mojo check generic bodies before instantiation ([`other-languages.md` §2](other-languages.md#2-checking-generic-code-where-it-is-written); [`comparison.md` §4](design/comparison.md#4-generic-code-is-checked-at-its-definition)).
  - Julia has no definition checking: such a mistake appears at run time, as a `MethodError`.
- **Defined in:** [`design.md` §4.7](design.md#47-the-rest-of-the-trait-language); [`mechanisms.md` §9](design/mechanisms.md#9-definition-checking-at-archetypes).

### Concrete mode and fully typed

- **Here:**
  - Code is **fully typed** when every call in it is at a [fact signature](#fact-and-fact-signature), and so is every call in the code compiled into it. Such code pays nothing for the facts rule.
  - **Concrete mode** reports the calls that are not, per worker, with their root cause. `fully_typed(f, argtypes)` gives the report: the **fully-typed certificate**.
  - A trait or a module may ask for concreteness at a level: silent (the default), warn, or error.
- **Origin:** close to Julia's "type stability", which `@code_warntype` shows for one call *(not in the research)*. Swift's lesson, "make the slow path visible from day one", is what explicit modes and concrete mode do ([`other-languages.md` §7](other-languages.md#7-static-and-dynamic-positions)). "Fully typed" is the project's term.
- **Defined in:** [`design.md` §3](design.md#3-the-argument-in-four-steps) (its first paragraph), [§4.3](design.md#43-concreteness-opt-in-per-trait); [`mechanisms.md` §9](design/mechanisms.md#9-definition-checking-at-archetypes), [§1, "Concreteness"](design/mechanisms.md#concreteness).

---

## Values and functions of mixed types

### `Dynamic{X}`

- **Here:** a value of abstract type `X`: any value that conforms to `X`, reached through `X`'s operations and fields.
  - It is for a value that outlives a call, an element of a collection of mixed keys, or a field whose key changes.
  - Its operations have declared result types, so the code after them stays typed.
  - It holds the user's object.
  - Inside a trait module, a trait's name in a field or container means its `Dynamic`: `hooks::Vector{Hook}`.
- **Origin:**
  - Rust's `dyn Trait` and `Box<dyn Trait>`; Swift's existential `any P` ([`other-languages.md` §7](other-languages.md#7-static-and-dynamic-positions)). Both call through a table of pointers. Ours splits at the call site ([`comparison.md` §6](design/comparison.md#6-static-and-dynamic-positions-and-their-defaults)).
  - In Julia: a field typed with an abstract type, which holds a boxed value. `Dynamic{X}` is the package's spelling, until traits are in the type system.
- **Defined in:** [`design.md` §4.5](design.md#45-dynamicx-a-value-of-abstract-type-x); [`mechanisms.md` §15](design/mechanisms.md#15-dynamic-values-as-built).

### Call-site split

- **Here:** how an operation on a `Dynamic` value runs.
  - `isa` branches over the declared implementations, at most four, each a direct call that can inline;
  - then a dynamic call, as the fallback;
  - the result asserted to the declared type.

  It dispatches in the caller's world. A later implementation reaches the fallback and invalidates nothing.
- **Origin:** Julia's union splitting, which branches over the members of a small `Union`, applied to a trait's implementations ([`comparison.md` §6](design/comparison.md#6-static-and-dynamic-positions-and-their-defaults)). It is built into Julia's compiler as `Compiler.dynamic_call`, part (D).
- **Defined in:** [`design.md` §4.5](design.md#45-dynamicx-a-value-of-abstract-type-x), [§6](design.md#6-what-julia-provides) part (D); [`mechanisms.md` §15](design/mechanisms.md#15-dynamic-values-as-built); [`julia-changes.md` §1](design/julia-changes.md#1-the-facts-compiler-parts-ad).

### World-checked call-site cache (proposed)

- **Here:** a cache proposed between the split and the fallback. Not built.
  - Each entry holds a type, the entry point of the code compiled for it, and the world range in which that code is valid.
  - A call compares the type and the current world against an entry, then calls indirectly. A miss dispatches as now and adds an entry.
  - It would serve more than four implementations at a few nanoseconds per call. It would also fix `DynamicCall`'s defect: running in the latest world.
- **Origin:** the polymorphic inline cache of Self and of JavaScript and Java virtual machines, made aware of Julia's worlds ([`design.md` §4.5](design.md#45-dynamicx-a-value-of-abstract-type-x)). The world range is a [CodeInstance](#codeinstance)'s `min_world` and `max_world`, which invalidation shortens.
- **Defined in:** [`design.md` §4.5](design.md#45-dynamicx-a-value-of-abstract-type-x); the plan [`plans/2026-10-19-principled-speed-plan.md`](plans/2026-10-19-principled-speed-plan.md).

### `Callable`: `DynamicCall` and `CompiledCall`

- **Here:** a function argument at a declared signature: `Callable{A, S, M}`, with arguments `A`, result `S` and mode `M`. Its one operation is checked at every call. Anything callable conforms; no implementation is declared. Two modes:
  - `DynamicCall`, the default: the worker is compiled once per signature, and each call is an indirect call (about 4 ns, measured on the earlier prototype).
  - `CompiledCall`: the worker is compiled per function type, with the function inferred into it. The signature is still checked.

  The library sets the default. The caller overrides it per value: `compiled_call(f)`, `dynamic_call(f)`. `DynamicFn{A, S}` is a `DynamicCall` value of fixed type, for storing in a field.
- **Origin:**
  - Julia has no type for "a function from `Float64` to `Float64`". FunctionWrappers.jl provides one by hand.
  - C++'s `std::function` erases the type. Rust chooses `impl Fn` (per closure) or `&dyn Fn` (dynamic) in the callee's signature. Here the caller can override the library's choice, which Rust and Swift do not offer ([`comparison.md` §6](design/comparison.md#6-static-and-dynamic-positions-and-their-defaults); [`other-languages.md`](other-languages.md#what-is-new-in-our-design), "What is new in our design", item 2).
- **Defined in:** [`design.md` §4.6](design.md#46-functions-as-arguments-callable-two-modes); [`mechanisms.md` §10](design/mechanisms.md#10-callable-and-its-two-modes).

### Results like the input: `Self`, `Like`, `withfields`

- **Here:** how a library returns "a table like the input" without seeing the user's type.
  - A **constructor operation** declared to return `Self` makes a new value of the receiver type.
  - `::Like{t}` declares that the result is like argument `t`. The entry rebuilds a value of the caller's type.
  - `withfields(t; u = …)` replaces declared fields.
- **Origin:** Rust's `-> Self` and Swift's `init` requirements. In Julia: Base's `similar`, Tables.jl's `materializer`, ConstructionBase.jl's `setproperties` and Accessors.jl ([`mechanisms.md` §13](design/mechanisms.md#13-results-like-the-input)).
- **Defined in:** [`design.md` §4.7](design.md#47-the-rest-of-the-trait-language); [`mechanisms.md` §13](design/mechanisms.md#13-results-like-the-input).

---

## Ownership

### Owner

- **Here:** a package owns its functions and types. Julia (Core, Base, the standard libraries) is one owner. A package extension belongs to its parent. The session owns what is defined at the prompt.
- **Origin:** Rust's crate, the unit of its orphan rule ([`other-languages.md` §4](other-languages.md#4-who-may-add-a-conformance-or-a-method)). Julia's piracy convention uses the same idea of "your own" functions and types.
- **Defined in:** [`design.md` §1](design.md#1-terms).

### Stakeholder

- **Here:**
  - The stakeholders of a **method** are the owner of its function and the owners of every type in its own signature, a `Union`'s members taken one by one.
  - The stakeholders of a **concrete signature** are the owner of its function and the owners of every type in it, of their supertypes, and of the types bounding their parameters.
  - Only a stakeholder or a pirate can change a fact (Lemma O).
  - A stakeholder may declare an implementation: the trait's owner or the type's owner.
- **Origin:** the project's term. It is Rust's orphan rule ("either the trait must be local or the self-type must be local") generalized to multiple dispatch ([`comparison.md` §5](design/comparison.md#5-who-may-implement-ownership-and-stakeholders)).
- **Defined in:** [`design.md` §1](design.md#1-terms), [§3.1](design.md#31-step-1-fully-typed-code-is-already-invalidated-only-by-stakeholders-and-pirates), [§5](design.md#5-the-three-rules) rule 2.

### Pirate and piracy

- **Here:** a pirate is a method defined by none of its stakeholders: a method of a function you do not own, for types you do not own. A pirate changes compiled code only if it wins at a fact.
- **Origin:** Julia's own "type piracy", which Julia's style guide advises against and Aqua.jl checks. Here it is made strict for unions. Rust refuses such impls at compile time; Swift warns on retroactive conformances since Swift 6 ([`comparison.md` §5](design/comparison.md#5-who-may-implement-ownership-and-stakeholders)).
- **Defined in:** [`design.md` §1](design.md#1-terms), [§3.2](design.md#32-step-2-outlaw-pirates-and-fully-typed-code-is-always-valid-and-can-be-cached), [§5](design.md#5-the-three-rules) rule 2.

### Strict mode

- **Here:** a switch. It refuses a pirate that would win at a fact of compiled code, where the pirate is defined: at the prompt, by `include`, or as a package image's methods activate. The error names the method and the code it would have changed. The refused method then does not exist, for plain code either. The default session leaves it off: it follows the pirate, and the code with that fact recompiles once.
- **Origin:** the project's. Rust refuses every orphan impl at compile time. Strict mode refuses a pirate only where it would change compiled code ([`comparison.md` §5](design/comparison.md#5-who-may-implement-ownership-and-stakeholders)). It uses a definition hook in the patched Julia (piece 1).
- **Defined in:** [`design.md` §3.2](design.md#32-step-2-outlaw-pirates-and-fully-typed-code-is-always-valid-and-can-be-cached), [§3.5](design.md#35-the-default-following-pirates-rule-p-and-what-it-gives-up); [`explorations/strict-mode.md`](explorations/strict-mode.md).

### Package extension

- **Here:** Julia's code that loads when its parent package and a trigger package are both loaded. For ownership it belongs to its parent. In the trait world an extension declares implementations, which invalidate nothing, instead of adding methods to a library's internal functions. Example: TraitCSV's extension for InlineStrings' `String15`.
- **Origin:** Julia's own: package extensions, with `[weakdeps]` and `[extensions]` in `Project.toml`, since Julia 1.9 *(the version: not in the research)*. Before them, Requires.jl did the same.
- **Defined in:** [`design.md` §1](design.md#1-terms) (Owner), [§3.2](design.md#32-step-2-outlaw-pirates-and-fully-typed-code-is-always-valid-and-can-be-cached); [`intro/porting.md`](intro/porting.md), rule 4.

---

## The compiler

### Fact and fact signature

- **Here:**
  - A **fact** is "at concrete signature `s`, dispatch selects `r`", where `r` is a method, "no method" or "ambiguous".
  - A **fact signature** is a tuple of concrete types; its union splits; the splits of unions of concrete element types inside tuple arguments (up to four); or a closure's call at kinds.
  - Under the facts rule, compiled code depends on the method table only through facts.
- **Origin:** the project's terms. A fact is the kind of edge Julia's compiled code already records to the dispatch it assumed, restricted to concrete signatures. In fully typed code every edge is a fact ([`design.md` §3.1](design.md#31-step-1-fully-typed-code-is-already-invalidated-only-by-stakeholders-and-pirates)).
- **Defined in:** [`design.md` §1](design.md#1-terms), [§3](design.md#3-the-argument-in-four-steps) (its first paragraph), [§5](design.md#5-the-three-rules) rule 1.

### Run-time site

- **Here:** a call in compiled code whose argument types are not a fact signature. It dispatches at run time and records nothing. Its result is `Any`.
- **Origin:** the project's term. It behaves as Julia's dynamic dispatch does. Plain Julia instead infers such a call from the methods that exist today and records an edge that a new method can break.
- **Defined in:** [`design.md` §1](design.md#1-terms), [§3.3](design.md#33-step-3-the-facts-rule-extends-the-guarantee-to-all-code-at-a-cost-where-code-is-not-fully-typed), [§5](design.md#5-the-three-rules) rule 1.

### Facts mode and the setting `all`

- **Here:**
  - The **facts mode** compiles code so that it depends on the method table only through facts (the facts rule).
  - A trait module's methods are compiled this way. This is the product setting.
  - The test setting **`all`** compiles all code by facts: `JULIA_COMPILE_BY_FACTS=1` today, `--compile-by-facts=all` as the target spelling.
  - `--trim` turns the facts mode off: a closed world compiles plain code.
  - Its cost: Julia's heuristics for code that is not type-stable are lost at run-time sites.
- **Origin:** the project's. It is a mode of Julia's own inference in the patched build, part (A).
- **Defined in:** [`design.md` §1](design.md#1-terms), [§3.3](design.md#33-step-3-the-facts-rule-extends-the-guarantee-to-all-code-at-a-cost-where-code-is-not-fully-typed), [§6](design.md#6-what-julia-provides); [`julia-changes.md` §1](design/julia-changes.md#1-the-facts-compiler-parts-ad).

### Identical or error

- **Here:** the first guarantee (G1). A call in trait code computes what plain Julia computes in the current world, with the same effects, or raises. It rests on one assumption about values that inference decides (A3: `return_type` of empty collections, `Union{}` results).
- **Origin:** the project's.
- **Defined in:** [`design.md` §5](design.md#5-the-three-rules), "The central guarantees"; [`mechanisms.md` §19](design/mechanisms.md#19-identical-or-error).

---

## Julia's own terms

### Method table and dispatch

- **Here and in Julia:** the methods of Julia's generic functions, and the choice of a method for a call's argument types.
- **Defined in:** [`design.md` §1](design.md#1-terms).

### CodeInstance

- **Here and in Julia:** one compiled specialization of a method, with the assumptions inference made. It is valid for a range of worlds, from `min_world` to `max_world`.
- **Defined in:** [`design.md` §1](design.md#1-terms).

### Invalidation

- **Here and in Julia:** discarding a CodeInstance because a new method changes the result of a dispatch it assumed. Julia compiles the code again at the next call. Loading a package that adds a method for its own type can invalidate code in other packages, with no piracy involved.
- **Origin:** Julia's own term; Tim Holy's blog post on [method invalidations](https://julialang.org/blog/2020/08/invalidations/) (2020) explains it.
- **Defined in:** [`design.md` §1](design.md#1-terms), [§2](design.md#2-the-problem).

### World and world age

- **Here and in Julia:** Julia numbers the states of its method table. Each method definition starts a new world. Running code sees the methods of one world, its world age. A call in an older world sees the old methods; `invokelatest` calls in the latest world.
- **Here:** every trait call dispatches in the caller's world, as every Julia call does; "identical or error" is stated for the current world. Pointer tables ran in the latest world, which gave a wrong result. `DynamicCall`'s pointer still runs in the latest world (a known defect).
- **Origin:** Julia's own, since Julia 0.6; the manual explains it under "Redefining Methods" *(not in the research)*.
- **Defined in:** [`design.md` §4.5](design.md#45-dynamicx-a-value-of-abstract-type-x), [§4.6](design.md#46-functions-as-arguments-callable-two-modes); [`mechanisms.md` §19](design/mechanisms.md#19-identical-or-error).

---

## Retired terms

These appear in documents before the dates given, and in the record ([`record/INDEX.md`](record/INDEX.md)).

| Old term | Now | Changed |
|---|---|---|
| conformance (the noun) | [implementation](#implementation) | 2026-10-19 |
| implementing type, implementing value | [receiver type](#receiver-type), receiver | 2026-10-19 |
| representation, projection | [key](#key): code compiled for what the bound can see | session 22 |
| layering, trait wrappers, calls upward, sealing | the facts rule: trait code may call any Julia code | sessions 23–29 ([`decisions.md`](decisions.md), rows marked history) |

The verb stays: a type still *conforms to* a trait, and the query is still `conforms(T, X)`.
