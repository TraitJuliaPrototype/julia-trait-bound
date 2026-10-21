# Glossary

The project's terms, in plain words first. Each entry gives:
- **Here:** what the term means in this project;
- **Origin:** where the word comes from, what other languages call the same thing, and whether Julia already has it;
- **Defined in:** where the precise definition is.

The precedents come from the research in [`record/other-languages-research-2026-10-16.md`](record/other-languages-research-2026-10-16.md) and [`design/other-languages.md`](design/other-languages.md). A precedent marked *(not in the research)* is added from general knowledge of the language. Julia's own terms are marked as such.

The terms changed on 2026-10-19. Documents before that date say "conformance" for an implementation and "implementing type" for the receiver type (see [Retired terms](#retired-terms)).

## Index

[Associated type](#associated-type) ·
[Boundary and boundary method](#boundary-and-boundary-method) ·
[Bundle](#supertrait-and-bundle) ·
[Bound and bounded function](#bound-and-bounded-function) ·
[Call-site split](#call-site-split) ·
[`Callable`](#callable) ·
[Cast](#cast) ·
[CodeInstance](#codeinstance) ·
[`Compiled` and `Dynamic`](#compiled-and-dynamic) ·
[`compiled_for`, `with_dynamic`](#compiled-and-dynamic) ·
[Concrete mode](#concrete-mode-and-fully-typed) ·
[Conforms to](#conforms-to) ·
[Declared field](#declared-field) ·
[Default](#default) ·
[Definition checking and archetype](#definition-checking-and-archetype) ·
[Dispatch](#method-table-and-dispatch) ·
[`Dynamic{X}`](#dynamicx) ·
[`@default_with_dynamic_self`, `@default_compiled_for_self`](#compiled-and-dynamic) ·
[Erased key](#compiled-and-dynamic) ·
[First seen through a trait](#compiled-and-dynamic) ·
[Item position](#compiled-and-dynamic) ·
[Joint family](#family) ·
[Kept value: `Dynamic{X}`, `Compiled{X}`, `Kept{X}`](#dynamicx) ·
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
[Of the trait world](#of-the-trait-world) ·
[Operation](#operation) ·
[Owner](#owner) ·
[Package extension](#package-extension) ·
[Pirate and piracy](#pirate-and-piracy) ·
[Plain value](#compiled-and-dynamic) ·
[Receiver type](#receiver-type) ·
[Results like the input](#results-like-the-input-self-like-withfields) ·
[Run-time site](#run-time-site) ·
[`Self`](#results-like-the-input-self-like-withfields) ·
[Sibling](#results-like-the-input-self-like-withfields) ·
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

- **Here:** a kind of abstract type with a declared, checked contract. It declares operations with argument and result types, fields with types, and associated types as its parameters. It follows other rules than an abstract type: a type joins it by an [implementation](#implementation), after the type is defined, and may join several; a supertrait is a requirement, not a place in a tree; in dispatch a bound ranks below every type. Abstract types stay in Julia. The comparison, rule by rule: [traits §14](reference/traits.md#14-membership).
- **Origin:**
  - Rust and Mojo say "trait"; Swift says "protocol"; C++20 says "concept".
  - A C++20 concept is a predicate on types. A Rust trait is not a type, except as `dyn Trait`. A Swift protocol is also a type (`any P`). Ours is an abstract type, and reads like one by position ([`design/other-languages.md` §1](design/other-languages.md#1-a-trait-is-an-abstract-type-with-behaviour)).
  - In Julia: abstract types play part of this role, without a checked contract. Base also uses "traits" for a dispatch pattern (`IndexStyle`, `IteratorSize`), known as "Holy traits": a value computed from a type, not a checked contract *(not in the research)*.
- **Defined in:** [traits §3](reference/traits.md#3-trait-declarations); against abstract types: [§14](reference/traits.md#14-membership).

### Supertrait and bundle

- **Here:** `@trait B <: A` makes `A` a supertrait of `B`: a type implementing `B` implements `A` too, and a `B` bound sees `A`'s operations. A **bundle** is a trait without a body that names a combination of traits: `@trait Table <: (ColTable, RowTable)`.
- **Origin:** Rust's supertraits and Swift's protocol inheritance and composition (`P & Q`).
- **Defined in:** [traits §3.6](reference/traits.md#36-supertraits-and-bundles).

### Operation

- **Here:** a generic function declared at the trait, with argument and result types: `ncols(t::ColTable)::Int`. Every call on a trait object is checked against the declaration. An operation may be an existing function, such as `Base.length`.
- **Origin:** a Rust trait's methods, a Swift protocol's requirements *(wording: not in the research)*. In Julia: a generic function whose methods are declared at an abstract type, as `length(x::AbstractArray)`.
- **Defined in:** [traits §3.1](reference/traits.md#31-operations).

### Bound and bounded function

- **Here:** a bound is a trait named at an argument: `colmean(t::ColTable, i::Int)`. A function with such an argument is a bounded function. It reaches the argument only through the trait's operations and fields. It is compiled per [key](#key).
- **Origin:**
  - Rust calls `T: Trait` a trait bound. Rust and Swift check generic code against its bounds ([`record/other-languages-research-2026-10-16.md` §2](record/other-languages-research-2026-10-16.md#2-checking-generic-code-where-it-is-written)).
  - In Julia: an argument annotated with an abstract type, `f(x::AbstractArray)`, plays the same role. A bound is written the same way ([`design/other-languages.md` §1](design/other-languages.md#1-a-trait-is-an-abstract-type-with-behaviour)).
- **Defined in:** [traits §5](reference/traits.md#5-bounded-functions) (rule 3, the boundary), [§6.7](reference/traits.md#67-what-compiled-code-is-compiled-for); dispatch: [traits §5.5](reference/traits.md#55-dispatch-types-first-then-traits).

### Conforms to

- **Here:** type `T` conforms to trait `X` when an [implementation](#implementation) of `X` for `T` is declared. A "conforming type" is such a type. TraitWorld answers the question with `conforms(T, X)`, which stands in for `T <: X` until traits are in the type system. `Callable` is the exception: anything callable conforms to it.
- **Origin:** Swift's wording: "a type conforms to a protocol". Mojo uses the same word ([`record/other-languages-research-2026-10-16.md` §1](record/other-languages-research-2026-10-16.md#1-conformance-declared-or-structural)). Rust says "a type implements a trait".
- **Defined in:** [traits §4](reference/traits.md#4-implementations), [§14](reference/traits.md#14-membership).

### Implementation

- **Here:** the declaration `@implement X T` that type `T` joins trait `X`: "an implementation of `X` for `T`".
  - It is one line. Its operations are served by the type's own methods, by a field it forwards to (`by f`), or by the trait's defaults.
  - It is checked when it is declared: every operation and field exists, with the declared types.
  - It is never derived from the methods that exist. Base's throwing fallbacks would make such matching unsound.
  - It is a method of a registry (`conformance` in TraitWorld's code), declared so that it applies at no existing fact. So declaring one invalidates no compiled code.
- **Origin:**
  - Rust's `impl Trait for Type`; Java's and C#'s "implements" ([`decisions.md`](record/decisions.md), the row on terms of 2026-10-19). Go also says that a type "implements" an interface, but Go infers it from the methods *(not in the research)*.
  - Swift and Mojo call the declaration a "conformance". C++0x called it a "concept map", and C++20 dropped the declaration: its concepts match structurally ([`design/other-languages.md` §2](design/other-languages.md#2-implementations-are-declared)).
  - Declared implementations won in Rust, Swift and Mojo. Mojo added structural matching in 2024 and removed it in 2025 ([`record/other-languages-research-2026-10-16.md` §1](record/other-languages-research-2026-10-16.md#1-conformance-declared-or-structural)).
- **Defined in:** [traits §4](reference/traits.md#4-implementations); how it is recorded: [lowering §4](reference/lowering.md#4-implementations).

### Generic implementation

- **Here:** one implementation that covers every type that meets other traits: `@implement GTable R where {R: Indexable, eltype(R) == Vector{Float64}}`. Workers are still compiled per concrete key. A more specific implementation beats a generic one. That it must declare the same parameter values is Planned ([traits §4.8](reference/traits.md#48-generic-implementations)).
- **Origin:**
  - Rust's blanket impls. Rust made adding a blanket impl a breaking change; Rust's specialization, which orders overlapping impls, has been unstable since 2016 ([`record/other-languages-research-2026-10-16.md` §5](record/other-languages-research-2026-10-16.md#5-overlap-more-specific-beats-generic)).
  - In Julia: a method at an abstract type, or with a `where` clause, serves every type it covers ([`design/other-languages.md` §1](design/other-languages.md#1-a-trait-is-an-abstract-type-with-behaviour), the table).
- **Defined in:** [traits §4.8](reference/traits.md#48-generic-implementations); overlap: [`design/other-languages.md` §5](design/other-languages.md#5-who-may-implement-ownership-and-stakeholders).

### Named implementation

- **Here:** an implementation used only where a caller names it, which anyone could write. It is deferred until traits are in the type system. The form then is a value-level wrapper that conforms, a newtype: `Via{Fast}(x)`.
- **Origin:**
  - Jordan Rose lists "named conformances" among the options Swift should have had, beside owner-only conformances and wrapper types ([`record/other-languages-research-2026-10-16.md` §4](record/other-languages-research-2026-10-16.md#4-who-may-add-a-conformance-or-a-method)). Named impls are being proposed for Rust ([`design/other-languages.md` §5](design/other-languages.md#5-who-may-implement-ownership-and-stakeholders)).
  - Scala's implicits select an instance by imported scope; the design rejected that ([`design/other-languages.md`](design/other-languages.md), "Other options considered").
  - Haskell allows one instance of a class per type and uses newtypes for the others *(not in the research)*. That is the newtype form preferred here.
- **Defined in:** [traits §15](reference/traits.md#15-named-implementations).

### Family

- **Here:** one implementation for all instances of a parametric type, declared with `where`: `@implement Fam2 S2{P} where {P}`. Each member is fixed at its first use. Code is compiled per member.
  - A **joint family** ties the trait's parameters to the type's: `@implement StateVector{T} Series{T} where {T}`.
- **Origin:** C++0x's templated concept maps ([`record/other-languages-research-2026-10-16.md` §1](record/other-languages-research-2026-10-16.md#1-conformance-declared-or-structural)). In Julia: a method with a `where` clause over a type's parameters.
- **Defined in:** [traits §4.7](reference/traits.md#47-families).

### Default

- **Here:** an operation's body written in the trait, in terms of the other operations and the declared fields. An implementation may override it, but only when it is declared: which operations defaults serve is fixed then. A missing operation is an error at the implementation, never "not implemented" at a call.
- **Origin:**
  - Rust's default methods in a trait; Swift's protocol extensions *(not in the research)*.
  - In Julia: a fallback method at an abstract type, which subtypes override ([`design/other-languages.md` §1](design/other-languages.md#1-a-trait-is-an-abstract-type-with-behaviour)). Base's fallbacks may throw; a default never does.
- **Defined in:** [traits §3.2](reference/traits.md#32-defaults).

### Declared field

- **Here:** a field the trait requires, with a type: `u::U`, `@const p::P`. It is a stored field of the conforming type. It has the same name unless the implementation maps it (`name => label`). It is read at its byte offset. It is writable unless `@const`.
- **Origin:** Scala desugars a trait's `var` into a getter and a setter; Swift's protocols require properties `{ get set }` ([traits §3](reference/traits.md#3-trait-declarations)). New over Julia: abstract types cannot require fields today.
- **Defined in:** [traits §3.3](reference/traits.md#33-fields); how it is read: [lowering §6](reference/lowering.md#6-trait-objects-layout-fields-writes).

### Associated type

- **Here:** a trait's parameter, with one value per implementation, set by what the conforming type holds. `T` in `KVec{T}` is defined by a field's type, by an equation of `Self` (`T = eltype(Self)`), or stated in the implementation. They are first order: no input parameters, no equations between type functions.
- **Origin:**
  - Rust's associated types; Rust's RFC 195 argued for one value per implementation. Swift's protocols have them too ([`design/other-languages.md` §7](design/other-languages.md#7-the-complexity-budget)). Reasoning about them symbolically made Rust's and Swift's checking hard.
  - In Julia: a type parameter of an abstract type, as `T` and `N` in `AbstractArray{T, N}`. A type has one `AbstractArray` supertype, so one value of each.
- **Defined in:** [traits §3.4](reference/traits.md#34-parameters-and-associated-types).

### Forwarding (`by`)

- **Here:** an implementation that serves the operations through one field: `@implement ColTable Measurements by data`. The field's type is then the [receiver type](#receiver-type). So every type that forwards to a field of that type shares the library's code for it. Without `by`, the one-line form means the type implements the operations itself; it never picks a field, not one named `data`, not the only conforming one ([traits §4.2](reference/traits.md#42-one-line)). Forwarding does not chain.
- **Origin:** Kotlin's `by` forwards an interface's methods to a field. Go's struct embedding satisfies an interface through the embedded field's methods. Rust writes it by hand or uses `Deref` ([`design/other-languages.md` §3](design/other-languages.md#3-compiled-for-what-the-bound-can-see), "At a glance"). None of them makes the forwarded field the compile key.
- **Defined in:** [traits §4.3](reference/traits.md#43-forwarding-with-by).

### Receiver type

- **Here:** the type of the value the operations are called on.
  - It is the conforming type when the type's own methods serve an operation.
  - It is the field's type when the implementation forwards to a field.
  - There is none when the trait's defaults serve every operation.
  - The value itself is the receiver.
- **Origin:** the receiver of a method call in Go, Kotlin and Swift ([`decisions.md`](record/decisions.md), the row on terms of 2026-10-19). Rust's reference also calls `self` the receiver ([`record/other-languages-research-2026-10-16.md` §7](record/other-languages-research-2026-10-16.md#7-static-and-dynamic-positions), "`Self` only as receiver").
- **Defined in:** [traits §4.3](reference/traits.md#43-forwarding-with-by), [§6.7](reference/traits.md#67-what-compiled-code-is-compiled-for); [lowering §5](reference/lowering.md#5-keys-and-views).

### Key

- **Here:** what a bound can see of a value: the receiver type, if any, and the declared fields' types. A bounded function is compiled once per key, not per the argument's own type. A [`Dynamic`](#compiled-and-dynamic) value has the erased key, one per trait. Types that differ only in what the trait cannot see share compiled code.
- **Origin:** the project's term.
  - Go 1.18 compiles one generic instance per "GC shape", grouping types the generated code does not distinguish. .NET shares generic code among reference types ([`design/other-languages.md` §3](design/other-languages.md#3-compiled-for-what-the-bound-can-see), from memory and a review).
  - Julia compiles per concrete argument type. Its function-barrier idiom, passing only the fields an inner function needs, reaches the same shape by discipline.
- **Defined in:** [traits §6.7](reference/traits.md#67-what-compiled-code-is-compiled-for); how it is represented: [lowering §5](reference/lowering.md#5-keys-and-views).

---

## What library code sees

### Trait object

- **Here:** what library code receives for a bounded argument: the user's own object, seen through the bound. It is [`Compiled` or `Dynamic`](#compiled-and-dynamic). It lives for one call. It is never passed bare to plain code; to keep it, the code stores it as a [kept value](#dynamicx), with its attribute.
- **Origin:** Rust's "trait object" is a `dyn Trait` value, called through a table of pointers ([`record/other-languages-research-2026-10-16.md` §7](record/other-languages-research-2026-10-16.md#7-static-and-dynamic-positions)). Ours is static: one call, compiled per key. The counterpart of Rust's trait object here is `Dynamic{X}`, or a `Kept{X}` holding `Dynamic`.
- **Defined in:** [traits §5.2](reference/traits.md#52-what-a-bounded-function-receives); [lowering §6](reference/lowering.md#6-trait-objects-layout-fields-writes).

### View and held view

- **Here:**
  - A view is the part of a trait object for one trait: where the receiver and the declared fields are. A value bounded by several traits gets one view per trait, and all of them read the same object.
  - A held view holds an immutable value whole, when the value is itself the receiver. There is no object or offset to read through, so a `Dynamic` of it is one box.
- **Origin:** the project's terms. A view reads the user's object in place, as Julia's `view` reads an array without copying *(an analogy, not in the research)*.
- **Defined in:** [lowering §5](reference/lowering.md#5-keys-and-views), [§6](reference/lowering.md#6-trait-objects-layout-fields-writes).

### Entry and worker

- **Here:** a bounded function has two parts.
  - The **entry** is an ordinary method. It decides a plain value's attribute, [`Compiled` or `Dynamic`](#compiled-and-dynamic), and sees each argument through its bound, once. It is small and is inlined into typed callers.
  - The **worker** is the body, compiled per tuple of keys; a `Dynamic` value's key is erased, so one worker serves every type.
- **Origin:** the project's terms. The shape is Julia's function barrier: a small outer function and a typed inner kernel (Julia's performance tips; *not in the research*). Rust's "generic hotpath, concrete coldpath" is a thin generic wrapper around a shared inner function ([`record/other-languages-research-2026-10-16.md`](record/other-languages-research-2026-10-16.md#what-is-new-in-our-design), "What is new in our design", item 1).
- **Defined in:** lowering's terms, not the language's: [lowering §8](reference/lowering.md#8-bounded-functions-workers-and-entries).

### Trait module

- **Here:** a module declared `@trait_module`, whose code is written against traits. Its code is *trait code*; everything else is *plain code*. Its methods are compiled by facts.
- **Origin:** the project's term. It uses Julia's per-module compiler options, `Base.Experimental.@compiler_options`, which exist today for settings such as `optimize` and `infer` *(not in the research)*. The patched build adds `facts=true`.
- **Defined in:** [traits §2](reference/traits.md#2-trait-modules); the module option: [compiler §2.1](reference/compiler.md#21-the-module-option).

### Definition checking and archetype

- **Here:** library code is checked once, where it is defined, for every type that will ever conform. Each bounded method is inferred at **archetypes**: a stand-in key per bound, whose operations and fields return values of their declared types and nothing more. A mistake is reported at its line, before any user type exists.
- **Origin:**
  - "Archetype" is C++0x's term. C++0x checked definitions through archetypes, and concepts were removed in 2009. C++20 checks only uses.
  - Rust, Swift and Mojo check generic bodies before instantiation ([`record/other-languages-research-2026-10-16.md` §2](record/other-languages-research-2026-10-16.md#2-checking-generic-code-where-it-is-written); [`design/other-languages.md` §4](design/other-languages.md#4-generic-code-is-checked-at-its-definition)).
  - Julia has no definition checking: such a mistake appears at run time, as a `MethodError`.
- **Defined in:** [traits §9](reference/traits.md#9-checks-and-when-they-run); where it runs: [lowering §14](reference/lowering.md#14-checks-and-where-their-results-live).

### Concrete mode and fully typed

- **Here:**
  - Code is **fully typed** when every call in it is at a [fact signature](#fact-and-fact-signature), and so is every call in the code compiled into it. Such code pays nothing for the facts rule.
  - **Concrete mode** reports the calls that are not, per worker, with their root cause. `fully_typed(f, argtypes)` gives the report: the **fully-typed certificate**.
  - **Concrete:** a concrete type with concrete type parameters, all the way down. A trait may require its parameters and `Self` to be concrete, a bounded function the parts of its arguments (`@enforce_concrete_only`, `@warn_on_abstract`). Concrete mode is asked for with `@enforce_fully_typed` or `@warn_not_fully_typed`.
- **Origin:** close to Julia's "type stability", which `@code_warntype` shows for one call *(not in the research)*. Swift's lesson, "make the slow path visible from day one", is what explicit modes and concrete mode do ([`record/other-languages-research-2026-10-16.md` §7](record/other-languages-research-2026-10-16.md#7-static-and-dynamic-positions)). "Fully typed" is the project's term.
- **Defined in:** [traits §11](reference/traits.md#11-concreteness-and-concrete-mode); fully typed: [facts §1](reference/facts.md#term-fully-typed).

---

## Values and functions of mixed types

### `Compiled` and `Dynamic`

- **Here:** every value in trait code has one of two attributes. They choose speed, never results.
  - **`Compiled`:** the value runs code compiled for its [key](#key).
  - **`Dynamic`:** the value runs code compiled once, at the **erased key**; each operation on it dispatches when it runs, through a [call-site split](#call-site-split).
  - **Values carry. Annotations give defaults where a plain value enters trait code. Explicit casts always win.**
  - A **plain value** is one that carries no attribute yet: it gets one where it is first seen through a trait.
  - A value gets its attribute where it is **first seen through a trait**: at a bound; at an **item position**, a bound's parameter that names a trait (`Iterable{Shape}`), when an item is read; at a struct parameter bounded by a trait; at an operation's result declared with a trait. There it is `Compiled` if the code that sees it knows its concrete type, `Dynamic` if not. At the prompt, Julia compiles nothing, so every call there passes `Dynamic` values.
  - **Overrides:** a trait's default, `@default_with_dynamic_self` or `@default_compiled_for_self` (`Callable`'s default is `Dynamic`); an attribute on a bound or an item parameter, `x::Compiled{X}`, `ms::Iterable{Dynamic{Mark}}`; the **casts** `compiled_for(x)` and `with_dynamic(x)`, which always win, the later one of two.
  - A value keeps its attribute in the trait world, through calls, bounds and storage, also from library to library. Only the casts change it; constructors and types never do. A `Dynamic` is opened only by `compiled_for`: a function barrier written where it is wanted.
- **Origin:** Rust's generics (compiled per type) and `dyn Trait` (one copy, dynamic calls); Swift's `some P` and `any P`. In both languages the type the code knows decides, as here; the caller cannot change it ([`design/other-languages.md` §6](design/other-languages.md#6-static-and-dynamic-positions-and-their-defaults)). Julia compiles every call for the argument's type at run time; `compiled_for` is that behaviour, asked for.
- **Defined in:** [traits §6](reference/traits.md#6-values-in-trait-code-compiled-and-dynamic), [§6.2](reference/traits.md#62-how-plain-values-enter-the-trait-world), [§6.3](reference/traits.md#63-defaults-a-traits-default-and-annotations), [§6.7](reference/traits.md#67-what-compiled-code-is-compiled-for); how it is built: [lowering §5](reference/lowering.md#5-keys-and-views), [§8.2](reference/lowering.md#82-the-entry).

### Cast

- **Here:** `compiled_for(x)` and `with_dynamic(x)`, the only two ways to change a value's attribute. A cast always wins over defaults and annotations; of two casts, the later wins. Constructors and types never cast.
- **Origin:** the project's term, from a cast between types; here between attributes. Julia's `@nospecialize` is a library's choice made in its own code; a cast is the caller's, per value.
- **Defined in:** [traits §6.4](reference/traits.md#64-casts).

### Of the trait world

- **Here:** a type is *of the trait world* when it is defined in Julia itself (Core, Base, the standard libraries), in TraitWorld or in a trait module, and so are its fields' types, all the way down. A trait's `Dynamic` default (`@default_with_dynamic_self`) does not apply to such a value: it is the trait world's own.
- **Origin:** the project's term.
- **Defined in:** [traits §6.3](reference/traits.md#63-defaults-a-traits-default-and-annotations).

### `Dynamic{X}`

`Compiled{X}`, `Kept{X}`: the *kept values*.

- **Here:** a value of abstract type `X`: any value that conforms to `X`, reached through `X`'s operations and fields, kept where the code does not know its type. Three forms, the stored forms of trait objects:
  - `Dynamic{X}`, with the attribute [`Dynamic`](#compiled-and-dynamic); `Compiled{X}`, with `Compiled`;
  - `Kept{X}`, with either as data: one concrete type, for storage where values of both sit side by side.
  - They are for a value that outlives a call, an element of a collection of mixed keys, or a field whose key changes.
  - Their operations have declared result types, so the code after them stays typed.
  - They hold the user's object.
  - Inside a trait module, a trait's name in a field or container means `Kept{X}`: `hooks::Vector{Hook}`.
- **Origin:**
  - Rust's `dyn Trait` and `Box<dyn Trait>`; Swift's existential `any P` ([`record/other-languages-research-2026-10-16.md` §7](record/other-languages-research-2026-10-16.md#7-static-and-dynamic-positions)). Both call through a table of pointers. Ours splits at the call site ([`design/other-languages.md` §6](design/other-languages.md#6-static-and-dynamic-positions-and-their-defaults)).
  - In Julia: a field typed with an abstract type, which holds a boxed value. `Kept{X}` is the package's spelling, until traits are in the type system; a struct parameter bounded by a trait is Julia's parametric field, with the attribute choosing the parameter.
- **Defined in:** [traits §7](reference/traits.md#7-kept-values-dynamicx-compiledx-keptx), [§7.4](reference/traits.md#74-a-struct-parameter-bounded-by-a-trait); how it is built: [lowering §13](reference/lowering.md#13-dynamicx).

### Call-site split

- **Here:** how an operation on a `Dynamic` value runs.
  - `isa` branches over the declared implementations, at most four, each a direct call that can inline;
  - then, as the fallback, a call through a table of the call's targets keyed by the value's type ([compiler §4.3](reference/compiler.md#43-what-follows-the-split-the-table-of-a-calls-targets));
  - the result asserted to the declared type.

  It dispatches in the caller's world. A later implementation reaches the table and invalidates nothing.
- **Origin:** Julia's union splitting, which branches over the members of a small `Union`, applied to a trait's implementations ([`design/other-languages.md` §6](design/other-languages.md#6-static-and-dynamic-positions-and-their-defaults)). It is built into Julia's compiler as `Compiler.split_call`, part (D).
- **Defined in:** [facts §9](reference/facts.md#dynamic-split); the primitive: [compiler §4.2](reference/compiler.md#42-compilersplit_call-the-call-site-split).

### World-checked call-site cache

- **Here:** a cache that skips a dispatch at run time and is checked against the caller's world.
  - Each cache entry holds a type, the entry point of the code compiled for it, and the world range in which that code is valid.
  - A call compares the type and the current world against a cache entry, then calls directly. A miss dispatches as Julia does and adds a cache entry.
  - It is built for a `Dynamic` `Callable`'s pointers, which run in the caller's world through it, and for every dynamic call site (Julia's per-call-site cache).
  - Behind the `Dynamic` split a table keyed by the value's type serves instead ([compiler §4.3](reference/compiler.md#43-what-follows-the-split-the-table-of-a-calls-targets)).
- **Origin:** the polymorphic inline cache of Self and of JavaScript and Java virtual machines, made aware of Julia's worlds. The world range is a [CodeInstance](#codeinstance)'s `min_world` and `max_world`, which invalidation shortens.
- **Defined in:** [compiler §3](reference/compiler.md#3-world-checked-caches-at-dynamic-boundaries).

### `Callable`

- **Here:** a function argument at a declared signature: `Callable{A, S}`, with arguments `A` and result `S`. Its one operation is checked at every call. Anything callable conforms; no implementation is declared. Its default is `Dynamic` (`@default_with_dynamic_self`), so a plain function is [`Dynamic`](#compiled-and-dynamic):
  - `Dynamic`, the default: the library's code is compiled once per signature.
  - `Compiled`: the library's code is compiled per function, with the function inferred into it. The signature is still checked.

  The library may write `Compiled{Callable{A, S}}`. The caller casts per value: `compiled_for(f)`, `with_dynamic(f)`. A function kept in a field is a kept value: `Callable{A, S}` in a trait module's field means `Kept{Callable{A, S}}`, with the function's attribute. Functions of the trait world (Base's, a trait module's) are not affected by the `Dynamic` default.
- **Origin:**
  - Julia has no type for "a function from `Float64` to `Float64`". FunctionWrappers.jl provides one by hand.
  - C++'s `std::function` erases the type. Rust chooses `impl Fn` (per closure) or `&dyn Fn` (dynamic) in the callee's signature. Here the caller can override the library's choice, which Rust and Swift do not offer ([`design/other-languages.md` §6](design/other-languages.md#6-static-and-dynamic-positions-and-their-defaults); [`record/other-languages-research-2026-10-16.md`](record/other-languages-research-2026-10-16.md#what-is-new-in-our-design), "What is new in our design", item 2).
- **Defined in:** [traits §5.8](reference/traits.md#58-callable-functions-at-a-declared-signature); how it is built: [lowering §12](reference/lowering.md#12-callable-and-dynamiccallable).

### Results like the input: `Self`, `Like`, `withfields`

- **Here:** how a library returns "a table like the input" without seeing the user's type.
  - A **constructor operation** declared to return `Self` makes a new value like the one seen through the trait.
  - A **sibling:** the same type family at another parameter, rebuilt as the result (`LSeries{Float64}` in, `LSeries{Float32}` out).
  - `::Like{t}` declares that the result is like argument `t`. The entry rebuilds a value of the caller's type.
  - `withfields(t; u = …)` replaces declared fields.
- **Origin:** Rust's `-> Self` and Swift's `init` requirements. In Julia: Base's `similar`, Tables.jl's `materializer`, ConstructionBase.jl's `setproperties` and Accessors.jl ([traits §5.6](reference/traits.md#56-results-declared-types-like-withfields)).
- **Defined in:** [traits §3.5](reference/traits.md#35-self), [§5.6](reference/traits.md#56-results-declared-types-like-withfields); how the result is rebuilt: [lowering §11](reference/lowering.md#11-results-like-the-input).

---

## Ownership

### Owner

- **Here:** a package owns its functions and types. Julia (Core, Base, the standard libraries) is one owner. A package extension belongs to its parent. At the prompt, `Main` is one owner, and each module defined directly under it is an owner of its own ([traits §10.1](reference/traits.md#101-who-may-implement)).
- **Origin:** Rust's crate, the unit of its orphan rule ([`record/other-languages-research-2026-10-16.md` §4](record/other-languages-research-2026-10-16.md#4-who-may-add-a-conformance-or-a-method)). Julia's piracy convention uses the same idea of "your own" functions and types.
- **Defined in:** [facts §1](reference/facts.md#term-owner); who may implement: [traits §10.1](reference/traits.md#101-who-may-implement).

### Stakeholder

- **Here:**
  - The stakeholders of a **method** are the owner of its function and the owners of every type in its own signature, a `Union`'s members taken one by one.
  - The stakeholders of a **concrete signature** are the owner of its function and the owners of every type in it, of their supertypes, and of the types bounding their parameters.
  - Only a stakeholder or a pirate can change a fact (Lemma O).
  - A stakeholder may declare an implementation: the trait's owner or the type's owner.
- **Origin:** the project's term. It is Rust's orphan rule ("either the trait must be local or the self-type must be local") generalized to multiple dispatch ([`design/other-languages.md` §5](design/other-languages.md#5-who-may-implement-ownership-and-stakeholders)).
- **Defined in:** [facts §1](reference/facts.md#term-stakeholder); the argument: [rationale §2.1](design.md#21-step-1-fully-typed-code-is-already-invalidated-only-by-stakeholders-and-pirates).

### Pirate and piracy

- **Here:** a pirate is a method defined by none of its stakeholders: a method of a function you do not own, for types you do not own. A pirate changes compiled code only if it wins at a fact.
- **Origin:** Julia's own "type piracy", which Julia's style guide advises against and Aqua.jl checks. Here it is made strict for unions. Rust refuses such impls at compile time; Swift warns on retroactive conformances since Swift 6 ([`design/other-languages.md` §5](design/other-languages.md#5-who-may-implement-ownership-and-stakeholders)).
- **Defined in:** [facts §1](reference/facts.md#term-pirate), [§10](reference/facts.md#pirates); the errors: [traits §10.2](reference/traits.md#102-pirates); the argument: [rationale §2.2](design.md#22-step-2-refuse-the-pirates-that-would-win-and-fully-typed-code-is-never-invalidated).

### Strict mode

- **Here:** a switch that applies to trait code. It secures one property: trait code is never invalidated, except by a stakeholder's change. It refuses a pirate that would win at a fact of trait code, where the pirate is defined: at the prompt, by `include`, or as a package image's methods activate. The error names the method and the code it would have changed. The refused method then does not exist, for plain code either. The default session leaves it off: it follows the pirate, and the code with that fact recompiles once.
- **Origin:** the project's. Rust refuses every orphan impl at compile time. Strict mode refuses a pirate only where it would change compiled code ([`design/other-languages.md` §5](design/other-languages.md#5-who-may-implement-ownership-and-stakeholders)). It uses the definition hooks of the patched Julia ([compiler §5.1](reference/compiler.md#51-method-definition-and-image-activation-hooks)).
- **Defined in:** [traits §10.3](reference/traits.md#103-strict-mode); [facts §10.2](reference/facts.md#strict-mode), [§10.3](reference/facts.md#strict-intended); the argument: [rationale §2.2](design.md#22-step-2-refuse-the-pirates-that-would-win-and-fully-typed-code-is-never-invalidated), [§2.5](design.md#25-the-default-following-pirates-and-what-it-gives-up).

### Package extension

- **Here:** Julia's code that loads when its parent package and a trigger package are both loaded. For ownership it belongs to its parent: its winning methods are its parent's changes, followed (with a warning in strict mode, [facts §10.3](reference/facts.md#strict-intended)). In the trait world an extension declares implementations, which invalidate no trait code, instead of adding methods to a library's internal functions. Example: TraitCSV's extension for InlineStrings' `String15`.
- **Origin:** Julia's own: package extensions, with `[weakdeps]` and `[extensions]` in `Project.toml`, since Julia 1.9 *(the version: not in the research)*. Before them, Requires.jl did the same.
- **Defined in:** [facts §1](reference/facts.md#term-owner) (owners); [traits §10.1](reference/traits.md#101-who-may-implement); [`intro/porting.md`](intro/porting.md), rule 4.

---

## The compiler

### Fact and fact signature

- **Here:**
  - A **fact** is "at concrete signature `s`, dispatch selects `r`", where `r` is a method, "no method" or "ambiguous".
  - A **fact signature** is a signature at which only a stakeholder or a pirate can change dispatch. Its forms are listed in [facts §3](reference/facts.md#facts-and-fact-signatures): a tuple of concrete types, its union splits, unions inside tuple arguments, a closure's call at kinds, a concrete `Vararg` tail, and `invoke` at a declared signature.
  - Under the facts rule, compiled code depends on the method table only through facts.
- **Origin:** the project's terms. A fact is the kind of edge Julia's compiled code already records to the dispatch it assumed, restricted to concrete signatures. In fully typed code every edge is a fact ([the rationale §2.1](design.md#21-step-1-fully-typed-code-is-already-invalidated-only-by-stakeholders-and-pirates)).
- **Defined in:** [facts §1](reference/facts.md#term-fact), [§3](reference/facts.md#facts-and-fact-signatures); the argument: [rationale §2](design.md#2-the-argument-in-four-steps).

### Run-time site

- **Here:** a call in compiled code whose argument types are not a fact signature. It dispatches at run time and records nothing. Its result is `Any`.
- **Origin:** the project's term. It behaves as Julia's dynamic dispatch does. Plain Julia instead infers such a call from the methods that exist today and records an edge that a new method can break.
- **Defined in:** [facts §5](reference/facts.md#run-time-sites), [§4.2](reference/facts.md#inferred-across-a-call); the argument: [rationale §2.3](design.md#23-step-3-the-facts-rule-extends-the-guarantee-to-code-that-is-not-fully-typed).

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

- **Here:** without a qualifier, the *inference mode* a CodeInstance is compiled under: *facts* (the facts rule) or *plain* (Julia's own inference). Each mode's code has its own cache owner. Two other modes are always named in full:
  - **strict mode**, a switch for refusing winning pirates;
  - **concrete mode**, a report on calls that are not fully typed.
  A value's attribute, [`Compiled` or `Dynamic`](#compiled-and-dynamic), is not a mode: code for both is compiled in the facts mode.
- **Origin:** the project's. The facts mode is selected per module through Julia's `@compiler_options`, beside options such as `optimize` and `infer`.
- **Defined in:** [facts §1](reference/facts.md#term-mode), [§6](reference/facts.md#which-code-is-compiled-how).

### Boundary and boundary method

- **Here:** two related things.
  - **The boundary** (rule 3 of [the design](design.md#3-the-design-in-brief)): only values cross into trait code, each translated once by its bound.
  - **A boundary method** carries the boundary flag (`Expr(:meta, :facts_boundary)` in its body) and is compiled in its caller's mode, wherever it is defined: TraitWorld's entries, which do that translation, and `conformance` methods. The crossing between the modes then happens at the call the boundary method makes.
- **Origin:** the project's terms.
- **Defined in:** [traits §5](reference/traits.md#5-bounded-functions) (the boundary); [facts §6.1](reference/facts.md#kinds-of-methods) (boundary methods); the flag: [compiler §2.2](reference/compiler.md#22-the-method-flag-boundaries-and-always-facts-methods).

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
- **Defined in:** [facts §4.3](reference/facts.md#edges-and-invalidation); the problem: [rationale §1](design.md#1-the-problem).

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
