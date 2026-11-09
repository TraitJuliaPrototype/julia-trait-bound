# Glossary

The project's terms, in plain words first. Each entry gives:
- **Here:** what the term means in this project;
- **Origin:** where the word comes from, what other languages call the same thing, and whether Julia already has it;
- **Defined in:** where the precise definition is, in [the references](reference/README.md).

The precedents come from the research in [`record/other-languages-research-2026-10-16.md`](record/other-languages-research-2026-10-16.md) and [`design/other-languages.md`](design/other-languages.md). Terms of the earlier design, which documents before 2026-11-06 use, are under [Retired terms](#retired-terms).

## Index

[`All{X, Y}`](#intersection-allx-y) ·
[Attribute: `Compiled` and `Dynamic`](#compiled-and-dynamic) ·
[`BaseTraits`](#basetraits) ·
[Boundary method](#boundary-method) ·
[`bounded` and `@open`](#fully-bounded-and-open) ·
[`Callable`](#callable) ·
[Candidates](#split) ·
[Cast](#cast) ·
[Cell](#guard-and-cell) ·
[Code slot](#code-slot) ·
[CodeInstance](#codeinstance) ·
[Concrete parts](#concrete-parts) ·
[Contract](#trait) ·
[Contract of a closed type](#open-and-closed) ·
[Declared field](#declared-field) ·
[Declared result](#declared-result) ·
[Default](#default) ·
[Definition checking](#definition-checking) ·
[`Dynamic{X}`](#dynamicx) ·
[Edge](#edge) ·
[Entry](#membership-and-entry) ·
[Erased key](#key) ·
[Eraser `IOContext{IO}`](#eraser-iocontextio) ·
[Fact and fact signature](#fact-and-fact-signature) ·
[Facts policy](#policy-facts-and-plain) ·
[Family](#family) ·
[Forwarding (`by`)](#forwarding-by) ·
[Fully bounded and open](#fully-bounded-and-open) ·
[Fully typed, fully typed mode](#fully-typed-and-fully-typed-mode) ·
[G1: identical or error](#g1-identical-or-error) ·
[G2: stable caches, the G2 bit](#g2-stable-caches-and-the-g2-bit) ·
[Guard](#guard-and-cell) ·
[Hints](#hints) ·
[Input parameter](#parameters-and-input-parameters) ·
[Instance (one per member)](#parameters-and-input-parameters) ·
[Invalidation](#invalidation) ·
[`keep`](#keep) ·
[Key](#key) ·
[`like`, `withfields`](#like-and-withfields) ·
[Member](#membership-and-entry) ·
[Member check](#member-check) ·
[Membership](#membership-and-entry) ·
[Method at a trait](#method-at-a-trait) ·
[Method table and dispatch](#method-table-and-dispatch) ·
[Named implementation](#named-implementation) ·
[Open and closed](#open-and-closed) ·
[Operation](#operation) ·
[Owner, joint owners](#owner) ·
[Package extension](#package-extension) ·
[Package image](#package-image) ·
[Parameters](#parameters-and-input-parameters) ·
[Pattern member](#pattern-member) ·
[Pirate and piracy](#pirate-and-piracy) ·
[Plain policy](#policy-facts-and-plain) ·
[Policy](#policy-facts-and-plain) ·
[Run-time site](#run-time-site) ·
[`Self`](#self) ·
[Set](#trait) ·
[Setting: product, test bed `all`](#setting) ·
[Split](#split) ·
[Stakeholder](#stakeholder) ·
[Strict mode](#strict-mode) ·
[Supertrait](#supertrait) ·
[Trait](#trait) ·
[Trait code and plain code](#trait-module) ·
[Trait module](#trait-module) ·
[Type value as a member](#type-value-as-a-member) ·
[World and world age](#world-and-world-age)

---

## Traits and memberships

### Trait

- **Here:** an abstract type with two additions.
  - **Open membership:** a type may become a member after its own definition, by a declaration.
  - **A contract:** operations with argument and result types, stored fields, and the values of the trait's parameters. Each membership is checked against it.
  - Everything else is Julia's: a trait is written wherever a type is written, parametrized as an abstract type is, and a member's value is a value of the trait, unwrapped.
  - In the compiler's terms a trait is an **open set**: a `TypeName` with the open-set bit and its contract.
- **Origin:**
  - Rust and Mojo say "trait"; Swift says "protocol"; C++20 says "concept". A C++20 concept is a predicate on types; a Rust trait is not a type, except as `dyn Trait`; a Swift protocol is also a type (`any P`). Ours is an abstract type ([`design/other-languages.md` §1](design/other-languages.md#1-a-trait-is-an-abstract-type-with-behaviour)).
  - In Julia, abstract types play part of this role, without a checked contract. Base also says "traits" for a dispatch pattern (`IndexStyle`, `IteratorSize`), the "Holy traits": a value computed from a type, not a checked contract.
- **Defined in:** [traits §1](reference/traits.md#1-overview), [§3](reference/traits.md#3-traits-are-abstract-types), [§4](reference/traits.md#4-declaring-a-trait); sets: [compiler §4.1](reference/compiler.md#41-sets).

### Membership and entry

- **Here:**
  - `S <: X` holds when `S` is a **member** of the trait `X`. A type becomes a member with its definition (`struct S <: X`, checked by an `@implement X S` after its methods), after its definition (`@implement X S`, by a [stakeholder](#stakeholder)), or through another membership: membership is transitive.
  - **Memberships only grow.** A membership holds from the world in which it is declared; a task in an older world does not see it. It is never withdrawn; it may be redeclared.
  - The runtime keeps each membership as an **entry** (`Core.MembershipEntry`) on the member's `TypeName`: the set, the member pattern, the instance, and the worlds in which it holds.
  - A membership is never derived from the methods that exist; Base's throwing fallbacks would make such matching unsound. [`Callable`](#callable) is the one set whose memberships are its members' methods.
- **Origin:** Rust's `impl Trait for Type`, Swift's and Mojo's conformance, C++0x's concept map; declared memberships won in Rust, Swift and Mojo ([`record/other-languages-research-2026-10-16.md` §1](record/other-languages-research-2026-10-16.md#1-conformance-declared-or-structural)). In Julia: `struct S <: A`, a declared supertype, which only the type's definition can give.
- **Defined in:** [traits §3.1](reference/traits.md#31-membership), [§5](reference/traits.md#5-joining-a-trait); entries: [compiler §4.2](reference/compiler.md#42-memberships); what a membership does to compiled code: [facts §10](reference/facts.md#10-memberships).

### Parameters and input parameters

- **Here:**
  - A trait's parameters are associated types: a member has exactly one value for each, defined by a field's type, by an equation of `Self` (`T = eltype(Self)`), or stated at the membership. They are invariant, as Julia's are.
  - **One instance per member:** every path by which a type reaches a trait gives the same parameter values. A declaration that would give a second instance is refused.
  - An **input parameter** (`@input N`) is the exception: a type may be a member at several values of it, as at `HasProperty{:ps, PView}` and `HasProperty{:u, Vector{Float64}}`. The trait at fixed input values is a trait of its own for every other rule.
- **Origin:** Rust's associated types (one value per impl, RFC 195) and its generic trait parameters for inputs; Swift's associated types. In Julia: a type parameter of an abstract type, as `T` and `N` in `AbstractArray{T, N}`.
- **Defined in:** [traits §3.2](reference/traits.md#32-parameters); the runtime's check: [compiler §4.6](reference/compiler.md#46-one-instance-per-member).

### Open and closed

- **Here:** a trait is open: members may join after their definition. An abstract type is closed: it has members only through `struct S <: A`. Compiled code relies on a membership that holds, never on one that does not, for an open trait; for a closed type Julia's rules apply. A closed abstract type may declare a **contract**: operations with declared results, and the split's candidates; at a value typed by it, the operations split as at a trait. Base's `IO` declares one. A trait whose author opts in with `@closed_after_load` is **closed after load**: a type's non-membership is final once the trait's and the type's packages have loaded.
- **Origin:** Scala's and Kotlin's sealed types are closed sets; Rust's traits are open to impls in the trait's or the type's crate.
- **Defined in:** [traits §3.4](reference/traits.md#34-open-and-closed); [facts §10](reference/facts.md#10-memberships); a closed type's contract: [compiler §7.1](reference/compiler.md#71-the-rule).

### Intersection `All{X, Y}`

- **Here:** the type of the values that are members of each of `X`, `Y`, …. It stands wherever a type stands: `f(t::All{ColTable, RowTable})`, `Dynamic{All{Shape, Placed}}`. A `const` names one, as a bundle of traits.
- **Origin:** Swift's protocol composition `P & Q`; Rust's `T: A + B`. Julia has unions but no intersection type.
- **Defined in:** [traits §3.6](reference/traits.md#36-intersections); [compiler §4.9](reference/compiler.md#49-intersections).

### Pattern member

- **Here:** a member that is not one concrete type: a family of types (`S{P} where P`), a closed abstract type (`AbstractVector{T} where T`), or another trait. Every type the pattern covers is a member.
- **Origin:** Rust's blanket impls (`impl<T: Display> ToString for T`) and generic impls; Swift's conditional conformances. In Julia: a method with a `where` clause serves every type it covers.
- **Defined in:** [traits §5.8](reference/traits.md#58-families), [§5.9](reference/traits.md#59-abstract-types-and-traits-as-members); [compiler §4.2](reference/compiler.md#42-memberships), [§4.6](reference/compiler.md#46-one-instance-per-member).

### Family

- **Here:** one membership for all instances of a parametric type, declared with `where`: `@implement StateVector{T} Series{T} where {T}`. The family states its instance as a pattern, and each member is checked against the trait's equations at its first use.
- **Origin:** C++0x's templated concept maps; Rust's generic impls (`impl<T> Trait for S<T>`). In Julia: a method with a `where` clause over a type's parameters.
- **Defined in:** [traits §5.8](reference/traits.md#58-families).

### Type value as a member

- **Here:** a type value is a member only by its own membership: `@implement CellParser Type{Int64}` makes `Int64 isa CellParser` true. `S <: X` and `S isa X` stay different questions, as in Julia.
- **Origin:** Julia's own `Type{T}` singletons, which dispatch on a type as a value.
- **Defined in:** [traits §3.1](reference/traits.md#31-membership); [compiler §4.10](reference/compiler.md#410-type-values).

### Operation

- **Here:** a generic function declared in the trait with argument and result types: `area(s::Shape)::Float64`. A member serves it by its own method, by a field it forwards to, or by the trait's default. An operation may be an existing function, such as `Base.length`.
- **Origin:** a Rust trait's methods, a Swift protocol's requirements. In Julia: a generic function whose methods are declared at an abstract type, as `length(x::AbstractArray)`.
- **Defined in:** [traits §4.1](reference/traits.md#41-operations).

### Default

- **Here:** an operation's body written in the trait, in terms of the other operations and the declared fields. It is the trait's own method for the operation, so every caller reaches it, as a fallback at an abstract type is reached. A member's own method is more specific and wins.
- **Origin:** Rust's default methods; Swift's protocol extensions. In Julia: a fallback method at an abstract type. Base's fallbacks may throw; a default never does.
- **Defined in:** [traits §4.2](reference/traits.md#42-defaults).

### Declared field

- **Here:** a stored field the trait requires, with a type: `u::U`, `@const p::P`. A member has a field of that name; `t.u` reads it. A field's declared type can define a parameter.
- **Origin:** Swift's protocols require properties (`{ get set }`); Scala's traits may declare `var`s. New over Julia: abstract types cannot require fields today.
- **Defined in:** [traits §4.3](reference/traits.md#43-fields).

### `Self`

- **Here:** in a trait's declarations, the member's own type: in equations (`T = eltype(Self)`) and in signatures that return a value of the member's type.
- **Origin:** Rust's and Swift's `Self`.
- **Defined in:** [traits §4.4](reference/traits.md#44-self).

### Supertrait

- **Here:** `@trait B <: A` makes `A` a supertrait of `B`: every member of `B` is a member of `A`, and `B`'s methods may use `A`'s operations. A trait's declared supertype is `Any` or a trait.
- **Origin:** Rust's supertraits; Swift's protocol inheritance.
- **Defined in:** [traits §4.5](reference/traits.md#45-supertraits).

### Forwarding (`by`)

- **Here:** a membership that serves the operations through one field: `@implement ColTable Measurements by data`. The field's type is then the [key](#key)'s receiver type, so every type that forwards to a field of that type can share compiled code. Forwarding is served by the trait's methods; it does not chain.
- **Origin:** Kotlin's `by`; Go's struct embedding. Rust writes it by hand or through `Deref`.
- **Defined in:** [traits §5.5](reference/traits.md#55-forwarding-with-by).

### Named implementation

- **Here:** a second way for a type to join a trait, used only where a caller names it: a wrapper type that joins it, `Via{Fast}(x)`, a newtype. Planned (deferred).
- **Origin:** Haskell's newtypes for a second instance; "named conformances" among the options Jordan Rose lists for Swift; named impls proposed for Rust ([`design/other-languages.md` §5](design/other-languages.md#5-who-may-implement-ownership-and-stakeholders)).
- **Defined in:** [traits §17](reference/traits.md#17-named-implementations).

---

## Methods, compiling and values

### Method at a trait

- **Here:** a method whose signature names a trait, `f(t::ColTable)`, in any module. It is a method: dispatch is Julia's, with one rule for ties: a type's own supertypes rank before a trait. Its **declared result** (`f(…)::RT`) is part of its contract with callers.
- **Origin:** Rust's and Swift's generic functions with trait bounds (`fn f<T: ColTable>(t: T)`). In Julia: a method at an abstract type.
- **Defined in:** [traits §6](reference/traits.md#6-methods-at-traits); specificity: [§6.2](reference/traits.md#62-specificity), [compiler §5.2](reference/compiler.md#52-specificity).

### Declared result

- **Here:** the result type a method or an operation declares, `f(…)::RT`. Compiled code that calls an operation on a value it knows only by its trait relies on the declared result, not on inference of whichever method runs.
- **Origin:** a Rust or Swift function's return type, which callers type-check against. In Julia, `f(x)::T = …` converts and asserts the result.
- **Defined in:** [traits §6.5](reference/traits.md#65-results); [compiler §6.8](reference/compiler.md#68-a-declared-result-on-method).

### Key

- **Here:** what a trait's contract sees of a member's type: the receiver type (the member, the forwarding field's type, or none), the declared fields' types and the parameter values. Members with equal keys could share one compiled copy of a method. The **erased key** `X{p…}` is the trait at its parameter values: code compiled once. Keys are Optional, built late; until then a method compiled per key is compiled per type.
- **Origin:** the project's term. Go 1.18 compiles one generic instance per "GC shape"; .NET shares generic code among reference types. Julia compiles per concrete argument type.
- **Defined in:** [traits §7.2](reference/traits.md#72-the-key); [compiler §6.1](reference/compiler.md#61-the-key-as-a-type).

### Fully bounded and open

- **Here:** a method is **fully bounded** at a trait argument when its body reaches the argument only through the contract: operations, declared fields, passing it on to an argument typed by the trait. Any other use makes it **open** there (`typeof(t)`, a call of another function with it, a closure that captures it). A scope that declares `bounded` refuses an open method with `TraitUseError`; `@open` marks one open on purpose.
- **Origin:** Rust and Swift check generic code against its bounds wherever it is written ([`record/other-languages-research-2026-10-16.md` §2](record/other-languages-research-2026-10-16.md#2-checking-generic-code-where-it-is-written)). Julia checks nothing of the kind; a method at an abstract type may do anything with its argument.
- **Defined in:** [traits §7.3](reference/traits.md#73-fully-bounded-methods); the check: [compiler §6.7](reference/compiler.md#67-the-definition-time-check).

### `Compiled` and `Dynamic`

- **Here:** the **attribute** of each trait argument at each call.
  - **`Compiled`:** the code compiled for the value's type (or key) runs. A caller that does not know the value's type dispatches on it once: a function barrier.
  - **`Dynamic`:** the code compiled once, at the trait, runs. Each operation on the value dispatches when it runs, and its result has the declared type.
  - Both run the same methods and give the same results. What decides, strongest first: a cast at the call, an attribute the value carries, the method's own marks, the trait's default, the module's fallback.
- **Origin:** the project's terms. Rust chooses per type between `impl Trait` (monomorphized) and `dyn Trait` (one copy); Swift between generics and `any P`. Julia has `@nospecialize`, a hint per argument with no say for the caller.
- **Defined in:** [traits §7.4](reference/traits.md#74-the-attribute-compiled-and-dynamic), [§7.5](reference/traits.md#75-what-decides); a trait's default: [§4.6](reference/traits.md#46-the-traits-default-attribute); [compiler §6.3](reference/compiler.md#63-the-attribute-at-a-call).

### Cast

- **Here:** `compiled_for(x)` or `with_dynamic(x)` written at a call's argument: the caller chooses the attribute there. A cast decides only at an argument typed by a trait.
- **Origin:** the project's term. Closest in Rust: choosing `&dyn Trait` or a generic at the call by the value passed.
- **Defined in:** [traits §7.6](reference/traits.md#76-casts); [compiler §6.9](reference/compiler.md#69-casts-and-keep).

### `Dynamic{X}`

- **Here:** a struct of Julia's `Core` that holds a member of `X` and is itself a member of `X` (and of `X`'s supertraits) whose code is compiled once: `Dynamic{Shape}(Circle(1.0))`. Its operations dispatch on the held object when they run; `unwrap(d)` is the object. It keeps the attribute through storage: a `Vector{Dynamic{Shape}}`.
- **Origin:** Rust's `dyn X` and Swift's `any X` are such boxes, usable through their own trait only; `Dynamic{All{X, Y}}` is Swift's `any X & Y`.
- **Defined in:** [traits §7.7](reference/traits.md#77-dynamicx).

### `keep`

- **Here:** `keep(x)` stores a trait argument with the attribute it has in the current code: as itself where it is `Compiled`, as a `Dynamic{X}` where it is `Dynamic`. A field or container then hands the attribute on.
- **Origin:** the project's term.
- **Defined in:** [traits §7.8](reference/traits.md#78-keeping-an-argument-with-its-attribute); [compiler §6.9](reference/compiler.md#69-casts-and-keep).

### Split

- **Here:** an operation called on a value the code knows only by its trait, or by a closed type with a contract. The compiled code tests the value's type against the **candidates** (the trait's first four members; a closed type's declared ones), calls each one's method directly, and calls through a table for the rest. Its result is the declared result: a member's result is converted to it.
- **Origin:** Julia's union splitting, which tests a value against each member of a small `Union`. Rust and Swift call through a witness or vtable instead.
- **Defined in:** [traits §7.9](reference/traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait); [compiler §7.2](reference/compiler.md#72-the-split), [§7.3](reference/compiler.md#73-the-table-of-a-calls-targets).

### Eraser `IOContext{IO}`

- **Here:** `IOContext{IO}(io)` holds any stream as an `IO`, so code typed `io::IO` that receives it is compiled once for every stream. Its operations on the stream it holds split over `IO`'s candidates; the stream's properties (`:limit`, `:color`) pass through. An author erases at a display entry where large code serves many streams, by `@nospecialize(io::IO)` and `IOContext{IO}(io)`.
- **Origin:** the project's term. Julia's `IOContext{IO_t}` with its parameter at the abstract type; Rust's `&mut dyn Write` erases a writer the same way.
- **Defined in:** [traits §9b](reference/traits.md#9b-streams-io); [compiler §7.5](reference/compiler.md#75-io).

### `Callable`

- **Here:** `Callable{A, S}`, the set of the functions and callable values that a call at the argument types `A` reaches, with result `S` checked on return. Its memberships are the members' methods: defining a method declares one, deleting it ends it. Dispatch picks among methods by a function argument's signature.
- **Origin:** Rust's `Fn` traits, Swift's function types matched by signature. In Julia: `Function`, which says nothing about signatures.
- **Defined in:** [traits §9](reference/traits.md#9-functions-callable); [compiler §7.4](reference/compiler.md#74-callables-call).

### `like` and `withfields`

- **Here:** results like the input. `like(t, data)` builds a value of the input's kind from new data; `withfields(t; f = …)` copies a member with some declared fields changed. A method that uses them is open at that argument.
- **Origin:** the project's terms; Base's `similar` is the closest Julia idiom.
- **Defined in:** [traits §6.5](reference/traits.md#65-results); [lowering §8](reference/lowering.md#8-like-and-withfields).

### `BaseTraits`

- **Here:** the library's traits for Base's interfaces: `HasLength`, `Iterable{T}`, `Indexable{T}`, `MutableIndexable{T}`, `Resizable{T}`, `Keyed{K, V}`, `Solvable{T}`, `LinearOp{T}`, `BoundedText`, `HasProperty{N, R}`. Base's types are their members.
- **Origin:** the project's. Base's informal interfaces (iteration, indexing) documented in the manual, which no declaration checks.
- **Defined in:** [traits §10.1](reference/traits.md#101-basetraits); [lowering §10](reference/lowering.md#10-basetraits).

### Concrete parts

- **Here:** a trait may require that its members' declared fields and parameters are concrete types, so that code compiled for them never sees an abstract field. Opt-in per trait.
- **Origin:** the project's term; Julia's performance tips advise concrete field types.
- **Defined in:** [traits §14](reference/traits.md#14-concreteness-and-fully-typed-mode).

---

## Checks and errors

### Member check

- **Here:** the check of a member that no declaration checked: a member of a [pattern](#pattern-member), checked against the trait's contract at its first use. A failing check raises `ImplementError`.
- **Origin:** Rust checks a generic impl's bounds where each type is used; Swift checks a conditional conformance's requirements.
- **Defined in:** [traits §11.1](reference/traits.md#111-when-checks-run); [lowering §4](reference/lowering.md#4-members-checked-at-their-first-use); the runtime's hook: [compiler §10.4](reference/compiler.md#104-the-member-hook).

### Definition checking

- **Here:** the check of a method at a trait where it is defined: one inference at the trait that records each use of the argument beyond the contract. It classifies the method as [fully bounded or open](#fully-bounded-and-open), and `bounded` refuses an open one.
- **Origin:** Rust and Swift type-check generic code against its bounds; C++20 concepts check only at instantiation.
- **Defined in:** [traits §11.2](reference/traits.md#112-definition-checking); [compiler §6.7](reference/compiler.md#67-the-definition-time-check).

### Hints

- **Here:** messages the library adds to Julia's `MethodError` and the trait's errors: the missing operation, the trait a type would need, the membership to declare.
- **Origin:** Julia's `Base.Experimental.register_error_hint`.
- **Defined in:** [traits §11.4](reference/traits.md#114-hints).

---

## Ownership

### Owner

- **Here:** a package owns the functions, types (traits included) and bindings it defines. A method belongs to the module it is evaluated in. Julia (Core, Base, the standard libraries) is one owner. A package extension belongs to its parent. At the prompt, `Main` is one owner, and each module defined directly under it is an owner of its own.
- **Joint owners:** packages a package names (`@joint_owners`) to own its functions and types with it, for split packages such as SciMLBase and DiffEqBase.
- **Origin:** Rust's crate, the unit of its orphan rule. Julia's piracy convention uses the same idea of "your own" functions and types.
- **Defined in:** [facts §1](reference/facts.md#term-owner); [traits §12.1](reference/traits.md#121-who-may-declare-a-membership).

### Stakeholder

- **Here:** the stakeholders of a method are the owner of its function and the owners of the types in its signature. The stakeholders of a concrete call signature are the owner of its function and the owners of every type in it, at any depth, and of their supertypes, traits included. Only a stakeholder or a pirate can change which method a call at a concrete signature selects. A stakeholder may declare a membership: the trait's owner or the type's.
- **Origin:** the project's term: Rust's orphan rule ("either the trait or the type must be local") generalized to multiple dispatch ([`design/other-languages.md` §5](design/other-languages.md#5-who-may-implement-ownership-and-stakeholders)).
- **Defined in:** [facts §1](reference/facts.md#term-stakeholder); [traits §12.1](reference/traits.md#121-who-may-declare-a-membership).

### Pirate and piracy

- **Here:** a pirate is a method defined by none of its stakeholders: a method of a function you do not own, for types you do not own. A pirate changes compiled code only where it wins.
- **Origin:** Julia's own "type piracy", which its style guide advises against and Aqua.jl checks; here strict for unions. Rust refuses such impls at compile time; Swift warns on retroactive conformances since Swift 6.
- **Defined in:** [facts §1](reference/facts.md#term-pirate), [§11](reference/facts.md#11-pirates-and-strict-mode); [traits §12.2](reference/traits.md#122-pirates).

### Strict mode

- **Here:** a switch that keeps code compiled by facts free of others' changes: it refuses a pirate that would win at a fact signature of such code, where the pirate is defined, and names what it would have changed. Off by default: the session then follows the pirate.
- **Origin:** the project's. Rust refuses every orphan impl at compile time; strict mode refuses a pirate only where it would change compiled code.
- **Defined in:** [traits §12.3](reference/traits.md#123-strict-mode); [facts §11.2](reference/facts.md#112-strict-mode).

### Trait module

- **Here:** a module declared `@trait_module`: its methods are compiled by facts, it refuses open methods at traits (`bounded`) and pirates of its own. Its code is **trait code**; code compiled under Julia's own rules is **plain code**.
- **Origin:** the project's term, on Julia's per-module compiler options (`Base.Experimental.@compiler_options`), which exist for settings such as `optimize` and `infer`.
- **Defined in:** [traits §13](reference/traits.md#13-scopes-trait-modules); the module option: [compiler §2.1](reference/compiler.md#21-the-module-option).

### Package extension

- **Here:** Julia's code that loads when its parent package and a trigger package are both loaded. For ownership it belongs to its parent. In trait code, an extension declares memberships rather than adding methods to a library's internal functions.
- **Origin:** Julia's own, with `[weakdeps]` and `[extensions]` in `Project.toml`, since Julia 1.9.
- **Defined in:** [facts §1](reference/facts.md#term-owner).

---

## The facts mode

### Fact and fact signature

- **Here:**
  - A **fact** is "at the concrete signature `s`, in the worlds `w₁` to `w₂`, dispatch selects `r`", where `r` is a method, "no method" or "ambiguous".
  - A **fact signature** is a call signature at which only a stakeholder or a pirate can change dispatch: a tuple of concrete types, and the forms that reduce to such tuples.
  - Code compiled by facts depends on the method table only through facts.
- **Origin:** the project's terms. A fact is the kind of dependency Julia's compiled code already records on the dispatch it assumed, restricted to concrete signatures.
- **Defined in:** [facts §1](reference/facts.md#term-fact), [§3](reference/facts.md#3-fact-signatures).

### Edge

- **Here:** a dependency a CodeInstance records: a dispatch edge (a fact), a result edge (a callee's result used as a type), a code edge (a callee's code inlined or evaluated), a binding edge, a membership cell. Julia invalidates a CodeInstance when an edge breaks.
- **Origin:** Julia's own term: the backedges between CodeInstances that invalidation follows.
- **Defined in:** [facts §1](reference/facts.md#term-edge); the record: [compiler §3.1](reference/compiler.md#31-the-record).

### Run-time site

- **Here:** a call in code compiled by facts whose argument types are not a fact signature. It dispatches when it runs, records no edge, and its result is `Any` unless declared results type it.
- **Origin:** the project's term. It behaves as Julia's dynamic dispatch does. Plain Julia instead infers such a call from the methods that exist today and records an edge that a new method can break.
- **Defined in:** [facts §1](reference/facts.md#term-run-time-site), [§5](reference/facts.md#5-run-time-sites).

### Policy: facts and plain

- **Here:** whether a method's code is compiled **by facts** (the rules of the facts mode) or **plainly** (Julia's own inference). A method instance has one CodeInstance per policy. A trait module's methods are facts methods; Julia's compiler is plain; everything else is neutral, and the [setting](#setting) gives its policy.
- **Origin:** the project's. Selected per module through Julia's `@compiler_options`.
- **Defined in:** [facts §6](reference/facts.md#6-which-code-is-compiled-how); [compiler §2](reference/compiler.md#2-the-policy-per-method).

### Boundary method

- **Here:** a method compiled in its caller's policy, wherever it is defined: it carries the method flag `:facts_boundary`. No method of Base carries it.
- **Origin:** the project's term.
- **Defined in:** [facts §6.1](reference/facts.md#61-kinds-of-methods); [compiler §2.2](reference/compiler.md#22-the-method-flag).

### Setting

- **Here:** which policy the neutral methods (Base, packages, code at the prompt) have.
  - The **product setting:** neutral methods are compiled plainly; trait modules by facts.
  - The **test bed `all`:** every method is compiled by facts, to test the rules on all of Julia.
  - `--trim` compiles a closed program plainly.
- **Origin:** the project's.
- **Defined in:** [facts §13](reference/facts.md#13-the-settings); [compiler §2.5](reference/compiler.md#25-the-test-bed).

### Fully typed and fully typed mode

- **Here:** code is **fully typed** when every call in it, and in the code compiled into it, is at a fact signature. **Fully typed mode** is a check, per function or module, that raises where a call's argument types are not known.
- **Origin:** the project's terms; Julia's `@inferred` and JET check related properties after the fact.
- **Defined in:** [facts §1](reference/facts.md#term-fully-typed); [traits §14](reference/traits.md#14-concreteness-and-fully-typed-mode); [compiler §2.7](reference/compiler.md#27-fully-typed-mode).

### G1: identical or error

- **Here:** the first guarantee. A call in code compiled by facts computes what plain Julia computes in the current world, with the same effects, or raises.
- **Origin:** the project's.
- **Defined in:** [facts §2.1](reference/facts.md#21-g1-identical-or-error).

### G2: stable caches and the G2 bit

- **Here:** the second guarantee. Code compiled by facts is invalidated only by a stakeholder's change or a winning pirate, so a package's compiled code stays valid when unrelated packages load. A CodeInstance whose record meets the rule carries the **G2 bit**; a package image keeps the code a session reaches dynamically only where the bit is set.
- **Origin:** the project's.
- **Defined in:** [facts §2.2](reference/facts.md#22-g2-stable-caches); the bit: [compiler §3.2](reference/compiler.md#32-g2-as-a-predicate).

### Guard and cell

- **Here:** compiled code that relies on a set's not having a member yet (a call whose method a later membership could change) holds a **guard**: it tests a **cell** (`Core.MembershipCell`) for the member and the set, and takes the dynamic call once the cell opens. So a membership invalidates no compiled code.
- **Origin:** the project's terms. Julia's binding partitions play the same role for global bindings.
- **Defined in:** [compiler §5.6](reference/compiler.md#56-guards-and-cells); the guarantee: [facts §10](reference/facts.md#10-memberships).

### Code slot

- **Here:** a static call that relies only on its callee's result goes through a slot: a pointer per call site, checked against the task's world. A change to the callee's code is then picked up through the slot without invalidating the caller.
- **Origin:** the project's term; Julia's `invoke` pointers and the per-call-site caches of dynamic languages.
- **Defined in:** [compiler §3.3](reference/compiler.md#33-the-code-slot).

---

## Julia's own terms

### Method table and dispatch

- **Here and in Julia:** the methods of Julia's generic functions, and the choice of a method for a call's argument types. Here a method at a trait is in the same table, and dispatch reads memberships through subtyping.
- **Defined in:** Julia's manual, "Methods"; [compiler §5](reference/compiler.md#5-dispatch).

### CodeInstance

- **Here and in Julia:** one compiled specialization of a method, with the assumptions inference made. It is valid for a range of worlds, from `min_world` to `max_world`. Here it also carries its policy and its G2 bit.
- **Defined in:** Julia's compiler (`Core.CodeInstance`); [compiler §2.3](reference/compiler.md#23-one-codeinstance-per-methodinstance-and-policy), [§3.2](reference/compiler.md#32-g2-as-a-predicate).

### Invalidation

- **Here and in Julia:** discarding a CodeInstance because a new method changes the result of a dispatch it assumed. Julia compiles the code again at the next call. Loading a package that adds a method for its own type can invalidate code in other packages, with no piracy involved.
- **Origin:** Julia's own term; Tim Holy's blog post on [method invalidations](https://julialang.org/blog/2020/08/invalidations/) (2020) explains it.
- **Defined in:** [facts §4.3](reference/facts.md#43-edges-and-invalidation).

### World and world age

- **Here and in Julia:** Julia numbers the states of its method table. Each method definition starts a new world; here each membership does too. Running code sees one world, its world age; `invokelatest` calls in the latest world.
- **Origin:** Julia's own; the manual explains it under "Redefining Methods".
- **Defined in:** [traits §3.1](reference/traits.md#31-membership) (memberships' worlds); [compiler §4.3](reference/compiler.md#43-worlds).

### Package image

- **Here and in Julia:** the compiled code a package's precompilation stores and a later session loads. Here an image also holds the package's memberships, activated at load, and keeps the code a session reaches dynamically only where it carries the G2 bit.
- **Defined in:** [facts §12](reference/facts.md#12-package-images); [compiler §9](reference/compiler.md#9-images-and-the-machine-code-cache).

---

## Retired terms

These appear in documents before 2026-11-06, in the record ([`record/INDEX.md`](record/INDEX.md)) and in [the earlier references](../attic/writeup/reference/README.md). The options behind them are in [`design/alternatives.md`](design/alternatives.md).

| Old term | Now | Changed |
|---|---|---|
| implementation, conformance (the noun) | [membership](#membership-and-entry), declared by `@implement` | 2026-11-06 (conformance: 2026-10-19) |
| conforms to, `conforms(T, X)` | `T <: X`: a [member](#membership-and-entry) | 2026-11-06 |
| generic implementation | [pattern member](#pattern-member) | 2026-11-06 |
| bound, bounded function | a [method at a trait](#method-at-a-trait); fully bounded is a [classification](#fully-bounded-and-open) | 2026-11-06 |
| receiver type, receiver | part of the [key](#key) | 2026-11-06 |
| trait object, view, held view | the member's own value, passed unwrapped ([traits §3.5](reference/traits.md#35-values)) | 2026-11-06 |
| entry and worker (of a bounded function) | gone: one method, compiled per type, per key or once. "Entry" now means a [membership entry](#membership-and-entry) | 2026-11-06 |
| kept value: `Compiled{X}`, `Kept{X}` | a member's own value, a field typed by the trait, [`keep`](#keep) | 2026-11-06 |
| trait cast, of the trait world, first seen through a trait | [casts](#cast) and the [attribute](#compiled-and-dynamic)'s order; `first_seen` is a module's fallback ([compiler §6.3](reference/compiler.md#63-the-attribute-at-a-call)) | 2026-11-06 |
| bundle, tuple of traits | an [intersection](#intersection-allx-y), named by a `const` | 2026-11-06 |
| associated type | a trait's [parameter](#parameters-and-input-parameters) | 2026-11-06 |
| call-site split | the [split](#split) | 2026-11-06 |
| world-checked call-site cache | [compiler §8](reference/compiler.md#8-world-checked-caches-at-dynamic-boundaries) | 2026-11-06 |
| mode (inference mode), facts mode and the setting `all` | [policy](#policy-facts-and-plain), [setting](#setting) | 2026-11-06 |
| boundary (rule 3 of the earlier design) | gone; a [boundary method](#boundary-method) is a method flag | 2026-11-06 |
| identical or error | [G1](#g1-identical-or-error) | 2026-11-06 |
| definition checking and archetype | [definition checking](#definition-checking) | 2026-11-06 |
| results like the input (`Like`) | [`like` and `withfields`](#like-and-withfields) | 2026-11-06 |
| item position, plain value, sibling | gone with the earlier lowering | 2026-11-06 |
| `@default_with_dynamic_self`, `@default_compiled_for_self` | a trait's [default attribute](#compiled-and-dynamic) | 2026-11-06 |
| representation, projection | [key](#key) | session 22 |
| layering, trait wrappers, calls upward, sealing | the facts rule: trait code may call any Julia code | sessions 23–29 |

The earlier headings, so that links to them still land:

### Implementation
See [membership](#membership-and-entry).
### Conforms to
See [membership](#membership-and-entry).
### Generic implementation
See [pattern member](#pattern-member).
### Bound and bounded function
See [method at a trait](#method-at-a-trait).
### Receiver type
See [key](#key).
### Trait object
See the table above.
### View and held view
See the table above.
### Entry and worker
See the table above.
### Kept value: `Dynamic{X}`, `Compiled{X}`, `Kept{X}`
See [`Dynamic{X}`](#dynamicx) and [`keep`](#keep).
### Trait cast
See [cast](#cast).
### Of the trait world
See [`Compiled` and `Dynamic`](#compiled-and-dynamic).
### Call-site split
See [split](#split).
### World-checked call-site cache
See [compiler §8](reference/compiler.md#8-world-checked-caches-at-dynamic-boundaries).
### Supertrait, bundle and tuple of traits
See [supertrait](#supertrait) and [intersection](#intersection-allx-y).
### Associated type
See [parameters](#parameters-and-input-parameters).
### Facts mode and the setting `all`
See [policy](#policy-facts-and-plain) and [setting](#setting).
### Mode
See [policy](#policy-facts-and-plain).
### Boundary and boundary method
See [boundary method](#boundary-method).
### Identical or error
See [G1](#g1-identical-or-error).
### Definition checking and archetype
See [definition checking](#definition-checking).
### Results like the input: `Self`, `Like`, `withfields`
See [`Self`](#self) and [`like` and `withfields`](#like-and-withfields).
### Fully typed, fully typed mode, the certificate
See [fully typed](#fully-typed-and-fully-typed-mode).
