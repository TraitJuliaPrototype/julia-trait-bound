# Glossary

The project's terms, in plain words first. Each entry gives:
- **Here:** what the term means in this project;
- **Origin:** where the word comes from, what other languages call the same thing, and whether Julia already has it;
- **Defined in:** where the precise definition is.

The precedents come from the research in [`other-languages.md`](other-languages.md) and [`design/comparison.md`](design/comparison.md). A precedent marked *(not in the research)* is added from general knowledge of the language. Julia's own terms are marked as such.

The terms changed on 2026-10-19. Documents before that date say "conformance" for an implementation and "implementing type" for the receiver type (see [Retired terms](#retired-terms)).

## Index

[Associated type](#associated-type) ·
[Boundary and boundary method](#boundary-and-boundary-method) ·
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
[Mode](#mode) ·
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
[World-checked call-site cache](#world-checked-call-site-cache)

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
- **Defined in:** [traits §3](reference/traits.md#3-trait-declarations).

### Operation

- **Here:** a generic function declared at the trait, with argument and result types: `ncols(t::ColTable)::Int`. Every call on a trait object is checked against the declaration. An operation may be an existing function, such as `Base.length`.
- **Origin:** a Rust trait's methods, a Swift protocol's requirements *(wording: not in the research)*. In Julia: a generic function whose methods are declared at an abstract type, as `length(x::AbstractArray)`.
- **Defined in:** [traits §3.1](reference/traits.md#31-operations).

### Bound and bounded function

- **Here:** a bound is a trait named at an argument: `colmean(t::ColTable, i::Int)`. A function with such an argument is a bounded function. It reaches the argument only through the trait's operations and fields. It is compiled per [key](#key).
- **Origin:**
  - Rust calls `T: Trait` a trait bound. Rust and Swift check generic code against its bounds ([`other-languages.md` §2](other-languages.md#2-checking-generic-code-where-it-is-written)).
  - In Julia: an argument annotated with an abstract type, `f(x::AbstractArray)`, plays the same role. A bound is written the same way ([`comparison.md` §1](design/comparison.md#1-a-trait-is-an-abstract-type-with-behaviour)).
- **Defined in:** [traits §6](reference/traits.md#6-bounded-functions) (rule 3, the boundary), [§4](reference/traits.md#4-keys-what-code-is-compiled-for); dispatch: [traits §6.5](reference/traits.md#65-dispatch-types-first-then-traits).

### Conforms to

- **Here:** type `T` conforms to trait `X` when an [implementation](#implementation) of `X` for `T` is declared. A "conforming type" is such a type. TraitWorld answers the question with `conforms(T, X)`, which stands in for `T <: X` until traits are in the type system. `Callable` is the exception: anything callable conforms to it.
- **Origin:** Swift's wording: "a type conforms to a protocol". Mojo uses the same word ([`other-languages.md` §1](other-languages.md#1-conformance-declared-or-structural)). Rust says "a type implements a trait".
- **Defined in:** [traits §5](reference/traits.md#5-implementations), [§16](reference/traits.md#16-membership).

### Implementation

- **Here:** the declaration `@implement X T` that type `T` joins trait `X`: "an implementation of `X` for `T`".
  - It is one line. Its operations are served by the type's own methods, by a field it forwards to (`by f`), or by the trait's defaults.
  - It is checked when it is declared: every operation and field exists, with the declared types.
  - It is never derived from the methods that exist. Base's throwing fallbacks would make such matching unsound.
  - It is a method of a registry (`conformance` in TraitWorld's code), declared so that it applies at no existing fact. So declaring one invalidates no compiled code.
- **Origin:**
  - Rust's `impl Trait for Type`; Java's and C#'s "implements" ([`decisions.md`](record/decisions.md), the row on terms of 2026-10-19). Go also says that a type "implements" an interface, but Go infers it from the methods *(not in the research)*.
  - Swift and Mojo call the declaration a "conformance". C++0x called it a "concept map", and C++20 dropped the declaration: its concepts match structurally ([`comparison.md` §2](design/comparison.md#2-implementations-are-declared)).
  - Declared implementations won in Rust, Swift and Mojo. Mojo added structural matching in 2024 and removed it in 2025 ([`other-languages.md` §1](other-languages.md#1-conformance-declared-or-structural)).
- **Defined in:** [traits §5](reference/traits.md#5-implementations); how it is recorded: [lowering §4](reference/lowering.md#4-implementations).

### Generic implementation

- **Here:** one implementation that covers every type that meets other traits: `@implement GTable R where {R: Indexable, eltype(R) == Vector{Float64}}`. Workers are still compiled per concrete key. A more specific implementation beats a generic one. That it must declare the same parameter values is Planned ([traits §5.8](reference/traits.md#58-generic-implementations)).
- **Origin:**
  - Rust's blanket impls. Rust made adding a blanket impl a breaking change; Rust's specialization, which orders overlapping impls, has been unstable since 2016 ([`other-languages.md` §5](other-languages.md#5-overlap-more-specific-beats-generic)).
  - In Julia: a method at an abstract type, or with a `where` clause, serves every type it covers ([`comparison.md` §1](design/comparison.md#1-a-trait-is-an-abstract-type-with-behaviour), the table).
- **Defined in:** [traits §5.8](reference/traits.md#58-generic-implementations); overlap: [`comparison.md` §5](design/comparison.md#5-who-may-implement-ownership-and-stakeholders).

### Named implementation

- **Here:** an implementation used only where a caller names it, which anyone could write. It is deferred until traits are in the type system. The form then is a value-level wrapper that conforms, a newtype: `Via{Fast}(x)`.
- **Origin:**
  - Jordan Rose lists "named conformances" among the options Swift should have had, beside owner-only conformances and wrapper types ([`other-languages.md` §4](other-languages.md#4-who-may-add-a-conformance-or-a-method)). Named impls are being proposed for Rust ([`comparison.md` §5](design/comparison.md#5-who-may-implement-ownership-and-stakeholders)).
  - Scala's implicits select an instance by imported scope; the design rejected that ([`comparison.md`](design/comparison.md), "Other options considered").
  - Haskell allows one instance of a class per type and uses newtypes for the others *(not in the research)*. That is the newtype form preferred here.
- **Defined in:** [traits §17](reference/traits.md#17-named-implementations).

### Family

- **Here:** one implementation for all instances of a parametric type, declared with `where`: `@implement Fam2 S2{P} where {P}`. Each member is fixed at its first use. Workers compile per instance.
- **Origin:** C++0x's templated concept maps ([`other-languages.md` §1](other-languages.md#1-conformance-declared-or-structural)). In Julia: a method with a `where` clause over a type's parameters.
- **Defined in:** [traits §5.7](reference/traits.md#57-families).

### Default

- **Here:** an operation's body written in the trait, in terms of the other operations and the declared fields. An implementation may override it, but only when it is declared: which operations defaults serve is fixed then. A missing operation is an error at the implementation, never "not implemented" at a call.
- **Origin:**
  - Rust's default methods in a trait; Swift's protocol extensions *(not in the research)*.
  - In Julia: a fallback method at an abstract type, which subtypes override ([`comparison.md` §1](design/comparison.md#1-a-trait-is-an-abstract-type-with-behaviour)). Base's fallbacks may throw; a default never does.
- **Defined in:** [traits §3.2](reference/traits.md#32-defaults).

### Declared field

- **Here:** a field the trait requires, with a type: `u::U`, `@const p::P`. It is a stored field of the conforming type. It has the same name unless the implementation maps it (`name => label`). It is read at its byte offset. It is writable unless `@const`.
- **Origin:** Scala desugars a trait's `var` into a getter and a setter; Swift's protocols require properties `{ get set }` ([traits §3](reference/traits.md#3-trait-declarations)). New over Julia: abstract types cannot require fields today.
- **Defined in:** [traits §3.3](reference/traits.md#33-fields); how it is read: [lowering §6](reference/lowering.md#6-trait-objects-layout-fields-writes).

### Associated type

- **Here:** a trait's parameter, with one value per implementation, set by what the conforming type holds. `T` in `KVec{T}` is defined by a field's type, by an equation of `Self` (`T = eltype(Self)`), or stated in the implementation. They are first order: no input parameters, no equations between type functions.
- **Origin:**
  - Rust's associated types; Rust's RFC 195 argued for one value per implementation. Swift's protocols have them too ([`comparison.md` §7](design/comparison.md#7-the-complexity-budget)). Reasoning about them symbolically made Rust's and Swift's checking hard.
  - In Julia: a type parameter of an abstract type, as `T` and `N` in `AbstractArray{T, N}`. A type has one `AbstractArray` supertype, so one value of each.
- **Defined in:** [traits §3.4](reference/traits.md#34-parameters-and-associated-types).

### Forwarding (`by`)

- **Here:** an implementation that serves the operations through one field: `@implement ColTable Measurements by data`. The field's type is then the [receiver type](#receiver-type). So every type that forwards to a field of that type shares the library's code for it. Without `by`, the one-line form means the type implements the operations itself; it never picks a field, not one named `data`, not the only conforming one ([traits §5.2](reference/traits.md#52-one-line)). Forwarding does not chain.
- **Origin:** Kotlin's `by` forwards an interface's methods to a field. Go's struct embedding satisfies an interface through the embedded field's methods. Rust writes it by hand or uses `Deref` ([`comparison.md` §3](design/comparison.md#3-compiled-for-what-the-bound-can-see), "At a glance"). None of them makes the forwarded field the compile key.
- **Defined in:** [traits §5.3](reference/traits.md#53-forwarding-with-by).

### Receiver type

- **Here:** the type of the value the operations are called on.
  - It is the conforming type when the type's own methods serve an operation.
  - It is the field's type when the implementation forwards to a field.
  - There is none when the trait's defaults serve every operation.
  - The value itself is the receiver.
- **Origin:** the receiver of a method call in Go, Kotlin and Swift ([`decisions.md`](record/decisions.md), the row on terms of 2026-10-19). Rust's reference also calls `self` the receiver ([`other-languages.md` §7](other-languages.md#7-static-and-dynamic-positions), "`Self` only as receiver").
- **Defined in:** [traits §4](reference/traits.md#4-keys-what-code-is-compiled-for); [lowering §5](reference/lowering.md#5-keys-and-views).

### Key

- **Here:** what a bound can see of a value: the receiver type, if any, and the declared fields' types. A bounded function is compiled once per key, not per the argument's own type. Types that differ only in what the trait cannot see share compiled code.
- **Origin:** the project's term.
  - Go 1.18 compiles one generic instance per "GC shape", grouping types the generated code does not distinguish. .NET shares generic code among reference types ([`comparison.md` §3](design/comparison.md#3-compiled-for-what-the-bound-can-see), from memory and a review).
  - Julia compiles per concrete argument type. Its function-barrier idiom, passing only the fields an inner function needs, reaches the same shape by discipline.
- **Defined in:** [traits §4](reference/traits.md#4-keys-what-code-is-compiled-for); how it is represented: [lowering §5](reference/lowering.md#5-keys-and-views).

---

## What library code sees

### Trait object

- **Here:** what library code receives for a bounded argument: the user's object, seen through the offsets of what the bound can see. It lives for one call. It is never passed bare to plain code; to keep it, the code stores it as a [`Dynamic{X}`](#dynamicx).
- **Origin:** Rust's "trait object" is a `dyn Trait` value, called through a table of pointers ([`other-languages.md` §7](other-languages.md#7-static-and-dynamic-positions)). Ours is static: one call, compiled per key. The counterpart of Rust's trait object here is `Dynamic{X}`.
- **Defined in:** [traits §6.2](reference/traits.md#62-what-a-bounded-function-receives); [lowering §6](reference/lowering.md#6-trait-objects-layout-fields-writes).

### View and held view

- **Here:**
  - A view is the part of a trait object for one trait: where the receiver and the declared fields are. A value bounded by several traits gets one view per trait, and all of them read the same object.
  - A held view holds an immutable value whole, when the value is itself the receiver. There is no object or offset to read through, so a `Dynamic` of it is one box.
- **Origin:** the project's terms. A view reads the user's object in place, as Julia's `view` reads an array without copying *(an analogy, not in the research)*.
- **Defined in:** [lowering §5](reference/lowering.md#5-keys-and-views), [§6](reference/lowering.md#6-trait-objects-layout-fields-writes).

### Entry and worker

- **Here:** a bounded function has two parts.
  - The **entry** is an ordinary method. It translates each argument by its bound, once. It is small and is inlined into typed callers.
  - The **worker** is the body, compiled per tuple of keys.
- **Origin:** the project's terms. The shape is Julia's function barrier: a small outer function and a typed inner kernel (Julia's performance tips; *not in the research*). Rust's "generic hotpath, concrete coldpath" is a thin generic wrapper around a shared inner function ([`other-languages.md`](other-languages.md#what-is-new-in-our-design), "What is new in our design", item 1).
- **Defined in:** [traits §6.2](reference/traits.md#62-what-a-bounded-function-receives); [lowering §8](reference/lowering.md#8-bounded-functions-workers-and-entries).

### Trait module

- **Here:** a module declared `@trait_module`, whose code is written against traits. Its code is *trait code*; everything else is *plain code*. Its methods are compiled by facts.
- **Origin:** the project's term. It uses Julia's per-module compiler options, `Base.Experimental.@compiler_options`, which exist today for settings such as `optimize` and `infer` *(not in the research)*. The patched build adds `facts=true`.
- **Defined in:** [traits §2](reference/traits.md#2-trait-modules); the module option: [compiler §2.1](reference/compiler.md#21-the-module-option).

### Definition checking and archetype

- **Here:** library code is checked once, where it is defined, for every type that will ever conform. Each bounded method is inferred at **archetypes**: a stand-in key per bound, whose operations and fields return values of their declared types and nothing more. A mistake is reported at its line, before any user type exists.
- **Origin:**
  - "Archetype" is C++0x's term. C++0x checked definitions through archetypes, and concepts were removed in 2009. C++20 checks only uses.
  - Rust, Swift and Mojo check generic bodies before instantiation ([`other-languages.md` §2](other-languages.md#2-checking-generic-code-where-it-is-written); [`comparison.md` §4](design/comparison.md#4-generic-code-is-checked-at-its-definition)).
  - Julia has no definition checking: such a mistake appears at run time, as a `MethodError`.
- **Defined in:** [traits §11](reference/traits.md#11-checks-and-when-they-run); where it runs: [lowering §14](reference/lowering.md#14-checks-and-where-their-results-live).

### Concrete mode and fully typed

- **Here:**
  - Code is **fully typed** when every call in it is at a [fact signature](#fact-and-fact-signature), and so is every call in the code compiled into it. Such code pays nothing for the facts rule.
  - **Concrete mode** reports the calls that are not, per worker, with their root cause. `fully_typed(f, argtypes)` gives the report: the **fully-typed certificate**.
  - A trait or a module may ask for concreteness at a level: silent (the default), warn, or error.
- **Origin:** close to Julia's "type stability", which `@code_warntype` shows for one call *(not in the research)*. Swift's lesson, "make the slow path visible from day one", is what explicit modes and concrete mode do ([`other-languages.md` §7](other-languages.md#7-static-and-dynamic-positions)). "Fully typed" is the project's term.
- **Defined in:** [traits §13](reference/traits.md#13-concrete-mode), [§3.7](reference/traits.md#37-concreteness); fully typed: [facts §1](reference/facts.md#term-fully-typed).

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
- **Defined in:** [traits §10](reference/traits.md#10-dynamicx-values-of-any-conforming-type); how it is built: [lowering §13](reference/lowering.md#13-dynamicx).

### Call-site split

- **Here:** how an operation on a `Dynamic` value runs.
  - `isa` branches over the declared implementations, at most four, each a direct call that can inline;
  - then a dynamic call, as the fallback;
  - the result asserted to the declared type.

  It dispatches in the caller's world. A later implementation reaches the fallback and invalidates nothing.
- **Origin:** Julia's union splitting, which branches over the members of a small `Union`, applied to a trait's implementations ([`comparison.md` §6](design/comparison.md#6-static-and-dynamic-positions-and-their-defaults)). It is built into Julia's compiler as `Compiler.dynamic_call`, part (D).
- **Defined in:** [facts §9](reference/facts.md#dynamic-split); the primitive: [compiler §4.2](reference/compiler.md#42-compilerdynamic_call-the-call-site-split).

### World-checked call-site cache

- **Here:** a cache that skips a dispatch at run time and is checked against the caller's world.
  - Each cache entry holds a type, the entry point of the code compiled for it, and the world range in which that code is valid.
  - A call compares the type and the current world against a cache entry, then calls directly. A miss dispatches as Julia does and adds a cache entry.
  - It is built for `DynamicCall`'s pointers, which run in the caller's world through it, and for every dynamic call site (Julia's per-call-site cache).
  - Its use for `Dynamic` values beyond four implementations is Optional.
- **Origin:** the polymorphic inline cache of Self and of JavaScript and Java virtual machines, made aware of Julia's worlds. The world range is a [CodeInstance](#codeinstance)'s `min_world` and `max_world`, which invalidation shortens.
- **Defined in:** [compiler §3](reference/compiler.md#3-world-checked-caches-at-dynamic-boundaries).

### `Callable`: `DynamicCall` and `CompiledCall`

- **Here:** a function argument at a declared signature: `Callable{A, S, M}`, with arguments `A`, result `S` and mode `M`. Its one operation is checked at every call. Anything callable conforms; no implementation is declared. Two modes:
  - `DynamicCall`, the default: the worker is compiled once per signature, and each call is an indirect call.
  - `CompiledCall`: the worker is compiled per function type, with the function inferred into it. The signature is still checked.

  The library sets the default. The caller overrides it per value: `compiled_call(f)`, `dynamic_call(f)`. `DynamicFn{A, S}` is a `DynamicCall` value of fixed type, for storing in a field.
- **Origin:**
  - Julia has no type for "a function from `Float64` to `Float64`". FunctionWrappers.jl provides one by hand.
  - C++'s `std::function` erases the type. Rust chooses `impl Fn` (per closure) or `&dyn Fn` (dynamic) in the callee's signature. Here the caller can override the library's choice, which Rust and Swift do not offer ([`comparison.md` §6](design/comparison.md#6-static-and-dynamic-positions-and-their-defaults); [`other-languages.md`](other-languages.md#what-is-new-in-our-design), "What is new in our design", item 2).
- **Defined in:** [traits §9](reference/traits.md#9-callable-functions-at-a-declared-signature); how it is built: [lowering §12](reference/lowering.md#12-callable-and-dynamicfn).

### Results like the input: `Self`, `Like`, `withfields`

- **Here:** how a library returns "a table like the input" without seeing the user's type.
  - A **constructor operation** declared to return `Self` makes a new value of the receiver type.
  - `::Like{t}` declares that the result is like argument `t`. The entry rebuilds a value of the caller's type.
  - `withfields(t; u = …)` replaces declared fields.
- **Origin:** Rust's `-> Self` and Swift's `init` requirements. In Julia: Base's `similar`, Tables.jl's `materializer`, ConstructionBase.jl's `setproperties` and Accessors.jl ([traits §7](reference/traits.md#7-results-declared-types-like-withfields)).
- **Defined in:** [traits §3.5](reference/traits.md#35-self), [§7](reference/traits.md#7-results-declared-types-like-withfields); how the result is rebuilt: [lowering §11](reference/lowering.md#11-results-like-the-input).

---

## Ownership

### Owner

- **Here:** a package owns its functions and types. Julia (Core, Base, the standard libraries) is one owner. A package extension belongs to its parent. The session owns what is defined at the prompt.
- **Origin:** Rust's crate, the unit of its orphan rule ([`other-languages.md` §4](other-languages.md#4-who-may-add-a-conformance-or-a-method)). Julia's piracy convention uses the same idea of "your own" functions and types.
- **Defined in:** [facts §1](reference/facts.md#term-owner); who may implement: [traits §12.1](reference/traits.md#121-who-may-implement).

### Stakeholder

- **Here:**
  - The stakeholders of a **method** are the owner of its function and the owners of every type in its own signature, a `Union`'s members taken one by one.
  - The stakeholders of a **concrete signature** are the owner of its function and the owners of every type in it, of their supertypes, and of the types bounding their parameters.
  - Only a stakeholder or a pirate can change a fact (Lemma O).
  - A stakeholder may declare an implementation: the trait's owner or the type's owner.
- **Origin:** the project's term. It is Rust's orphan rule ("either the trait must be local or the self-type must be local") generalized to multiple dispatch ([`comparison.md` §5](design/comparison.md#5-who-may-implement-ownership-and-stakeholders)).
- **Defined in:** [facts §1](reference/facts.md#term-stakeholder); the argument: [argument §3.1](design/argument.md#31-step-1-fully-typed-code-is-already-invalidated-only-by-stakeholders-and-pirates).

### Pirate and piracy

- **Here:** a pirate is a method defined by none of its stakeholders: a method of a function you do not own, for types you do not own. A pirate changes compiled code only if it wins at a fact.
- **Origin:** Julia's own "type piracy", which Julia's style guide advises against and Aqua.jl checks. Here it is made strict for unions. Rust refuses such impls at compile time; Swift warns on retroactive conformances since Swift 6 ([`comparison.md` §5](design/comparison.md#5-who-may-implement-ownership-and-stakeholders)).
- **Defined in:** [facts §1](reference/facts.md#term-pirate), [§10](reference/facts.md#pirates); the errors: [traits §12.2](reference/traits.md#122-pirates); the argument: [argument §3.2](design/argument.md#32-step-2-outlaw-pirates-and-fully-typed-code-is-always-valid-and-can-be-cached).

### Strict mode

- **Here:** a switch. It refuses a pirate that would win at a fact of compiled code, where the pirate is defined: at the prompt, by `include`, or as a package image's methods activate. The error names the method and the code it would have changed. The refused method then does not exist, for plain code either. The default session leaves it off: it follows the pirate, and the code with that fact recompiles once.
- **Origin:** the project's. Rust refuses every orphan impl at compile time. Strict mode refuses a pirate only where it would change compiled code ([`comparison.md` §5](design/comparison.md#5-who-may-implement-ownership-and-stakeholders)). It uses the definition hooks of the patched Julia ([compiler §5.1](reference/compiler.md#51-method-definition-and-image-activation-hooks)).
- **Defined in:** [traits §12.3](reference/traits.md#123-strict-mode); [facts §10.2](reference/facts.md#strict-mode), [§10.3](reference/facts.md#strict-intended); the argument: [argument §3.2](design/argument.md#32-step-2-outlaw-pirates-and-fully-typed-code-is-always-valid-and-can-be-cached), [§3.5](design/argument.md#35-the-default-following-pirates-rule-p-and-what-it-gives-up).

### Package extension

- **Here:** Julia's code that loads when its parent package and a trigger package are both loaded. For ownership it belongs to its parent. In the trait world an extension declares implementations, which invalidate nothing, instead of adding methods to a library's internal functions. Example: TraitCSV's extension for InlineStrings' `String15`.
- **Origin:** Julia's own: package extensions, with `[weakdeps]` and `[extensions]` in `Project.toml`, since Julia 1.9 *(the version: not in the research)*. Before them, Requires.jl did the same.
- **Defined in:** [facts §1](reference/facts.md#term-owner) (owners); [traits §12.1](reference/traits.md#121-who-may-implement); [`intro/porting.md`](intro/porting.md), rule 4.

---

## The compiler

### Fact and fact signature

- **Here:**
  - A **fact** is "at concrete signature `s`, dispatch selects `r`", where `r` is a method, "no method" or "ambiguous".
  - A **fact signature** is a signature at which only a stakeholder or a pirate can change dispatch. Its forms are listed in [facts §3](reference/facts.md#facts-and-fact-signatures): a tuple of concrete types, its union splits, unions inside tuple arguments, a closure's call at kinds, and a concrete `Vararg` tail.
  - Under the facts rule, compiled code depends on the method table only through facts.
- **Origin:** the project's terms. A fact is the kind of edge Julia's compiled code already records to the dispatch it assumed, restricted to concrete signatures. In fully typed code every edge is a fact ([the argument §3.1](design/argument.md#31-step-1-fully-typed-code-is-already-invalidated-only-by-stakeholders-and-pirates)).
- **Defined in:** [facts §1](reference/facts.md#term-fact), [§3](reference/facts.md#facts-and-fact-signatures); the argument: [argument §3](design/argument.md#3-the-argument-in-four-steps).

### Run-time site

- **Here:** a call in compiled code whose argument types are not a fact signature. It dispatches at run time and records nothing. Its result is `Any`.
- **Origin:** the project's term. It behaves as Julia's dynamic dispatch does. Plain Julia instead infers such a call from the methods that exist today and records an edge that a new method can break.
- **Defined in:** [facts §5](reference/facts.md#run-time-sites), [§4.2](reference/facts.md#inferred-across-a-call); the argument: [argument §3.3](design/argument.md#33-step-3-the-facts-rule-extends-the-guarantee-to-all-code-at-a-cost-where-code-is-not-fully-typed).

### Facts mode and the setting `all`

- **Here:**
  - The **facts mode** compiles code so that it depends on the method table only through facts (the facts rule).
  - A trait module's methods are compiled this way. This is the product setting.
  - The test setting **`all`** compiles all code by facts: `JULIA_COMPILE_BY_FACTS=1` today, `--compile-by-facts=all` as the target spelling.
  - `--trim` turns the facts mode off: a closed world compiles plain code.
  - Its cost: Julia's heuristics for code that is not type-stable are lost at run-time sites.
- **Origin:** the project's. It is a mode of Julia's own inference in the patched build, part (A).
- **Defined in:** [facts §12](reference/facts.md#settings); the interpreter and the switch: [compiler §1.1](reference/compiler.md#11-the-interpreter).

### Mode

- **Here:** without a qualifier, the *inference mode* a CodeInstance is compiled under: *facts* (the facts rule) or *plain* (Julia's own inference). Each mode's code has its own cache owner. Three other modes are always named in full:
  - **strict mode**, a switch for refusing winning pirates;
  - **concrete mode**, a report on calls that are not fully typed;
  - a **`Callable`'s mode**, `DynamicCall` or `CompiledCall`.
- **Origin:** the project's. The facts mode is selected per module through Julia's `@compiler_options`, beside options such as `optimize` and `infer`.
- **Defined in:** [facts §1](reference/facts.md#term-mode), [§6](reference/facts.md#which-code-is-compiled-how).

### Boundary and boundary method

- **Here:** two related things.
  - **The boundary** (rule 3 of [the design](design.md#4-the-rules)): only values cross into trait code, each translated once by its bound.
  - **A boundary method** carries the boundary flag and is compiled in its caller's mode, wherever it is defined: TraitWorld's entries, which do that translation, and `conformance` methods. The crossing between the modes then happens at the call the boundary method makes.
- **Origin:** the project's terms.
- **Defined in:** [traits §6](reference/traits.md#6-bounded-functions) (the boundary); [facts §6.1](reference/facts.md#kinds-of-methods) (boundary methods); the flag: [compiler §2.2](reference/compiler.md#22-the-method-flag-boundaries-and-always-facts-methods).

### Identical or error

- **Here:** the first guarantee (G1). A call in trait code computes what plain Julia computes in the current world, with the same effects, or raises. The exception is values that inference decides (`return_type` of empty collections, `Union{}` results).
- **Origin:** the project's.
- **Defined in:** [facts §2.1](reference/facts.md#g1).

---

## Julia's own terms

### Method table and dispatch

- **Here and in Julia:** the methods of Julia's generic functions, and the choice of a method for a call's argument types.
- **Defined in:** Julia's manual, "Methods".

### CodeInstance

- **Here and in Julia:** one compiled specialization of a method, with the assumptions inference made. It is valid for a range of worlds, from `min_world` to `max_world`.
- **Defined in:** Julia's compiler (`Core.CodeInstance`); its cache owners: [compiler §2.3](reference/compiler.md#23-the-owners-and-the-mode-and-owner-of-a-methodinstances-code).

### Invalidation

- **Here and in Julia:** discarding a CodeInstance because a new method changes the result of a dispatch it assumed. Julia compiles the code again at the next call. Loading a package that adds a method for its own type can invalidate code in other packages, with no piracy involved.
- **Origin:** Julia's own term; Tim Holy's blog post on [method invalidations](https://julialang.org/blog/2020/08/invalidations/) (2020) explains it.
- **Defined in:** [facts §4.3](reference/facts.md#edges-and-invalidation); the problem: [argument §2](design/argument.md#2-the-problem).

### World and world age

- **Here and in Julia:** Julia numbers the states of its method table. Each method definition starts a new world. Running code sees the methods of one world, its world age. A call in an older world sees the old methods; `invokelatest` calls in the latest world.
- **Here:** every trait call dispatches in the caller's world, as every Julia call does; "identical or error" is stated for the current world. Pointer tables ran in the latest world, which gave a wrong result. `DynamicCall`'s pointer runs in the caller's world, through a world-checked cache.
- **Origin:** Julia's own, since Julia 0.6; the manual explains it under "Redefining Methods" *(not in the research)*.
- **Defined in:** [facts §2.1](reference/facts.md#g1); the caches: [compiler §3](reference/compiler.md#3-world-checked-caches-at-dynamic-boundaries).

---

## Retired terms

These appear in documents before the dates given, and in the record ([`record/INDEX.md`](record/INDEX.md)).

| Old term | Now | Changed |
|---|---|---|
| conformance (the noun) | [implementation](#implementation) | 2026-10-19 |
| implementing type, implementing value | [receiver type](#receiver-type), receiver | 2026-10-19 |
| representation, projection | [key](#key): code compiled for what the bound can see | session 22 |
| layering, trait wrappers, calls upward, sealing | the facts rule: trait code may call any Julia code | sessions 23–29 ([`design/alternatives.md`](design/alternatives.md)) |

The verb stays: a type still *conforms to* a trait, and the query is still `conforms(T, X)`.
