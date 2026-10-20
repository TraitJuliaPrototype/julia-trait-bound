# The choices against C++, Rust, Swift and Mojo

A chapter of the [rationale](../design.md): how the design's main choices compare with the same choices in C++, Rust, Swift and Mojo, what the design pays for them, and what the other languages' experience predicts, for core developers, as of 2026-10-20.
Where this chapter and the [references](../reference/README.md) disagree, the references win.

**Sources.** The research behind it is [`../record/other-languages-research-2026-10-16.md`](../record/other-languages-research-2026-10-16.md) (2026-10-16, from primary sources: Stroustrup's HOPL papers and WG21 papers, Rust RFCs, Swift Evolution proposals, Mojo's changelogs and proposals). Claims about other languages point there or carry a link; this chapter does not repeat that research. Sections 10 and 11 cite primary sources directly: the Swift repository's documents and standard library, the Rust reference and the Rust book. The "Ours" column of `other-languages-research-2026-10-16.md` describes the design of its date; this chapter's is current ([`alternatives.md`](alternatives.md#claims-withdrawn)).

**Terms** are defined in [glossary](../glossary.md). Two used here: a *worker* is a bounded function's body compiled per key; *plain code* is code outside trait modules.

## Contents

- At a glance
1. A trait is an abstract type with behaviour
2. Implementations are declared
3. Compiled for what the bound can see
4. Generic code is checked at its definition
5. Who may implement: ownership and stakeholders
6. Static and dynamic positions, and their defaults
7. The complexity budget
8. Error messages
9. The facts rule in the compiler, and strict mode as a switch
10. Calling into ordinary code
11. Heterogeneous collections
- What the choices cost
- Other options considered (on the alternatives page)
- Predictions from other languages, and their status

---

## At a glance

| Decision | C++ | Rust | Swift | Mojo | Ours |
|---|---|---|---|---|---|
| What a trait is | concept: a predicate on types (C++20) | trait: not a type, except as `dyn Trait` | protocol: also a type (`any P`) | trait: not a type | an abstract type with behaviour |
| Implementation | structural (C++20); C++0x had declared concept maps, then dropped them | declared `impl` | declared, global, retroactive allowed | declared (structural added 2024, removed 2025) | declared `@implement`, never derived from methods |
| Generic code checked | at instantiation only | at definition, against bounds | at definition | before instantiation | at definition, at archetypes; open parameters per signature |
| Code generated | per type (templates) | per type (monomorphization) | once, dictionary passing; specialization an optimization | per type, whole program | per key: what a bound can see; per type only for a type that supplies its own behaviour |
| Implementation through a field | — | by hand, or `Deref` | by hand | — | forwarding (`by field`), compiled per the field's type |
| Dynamic position | virtual functions, type erasure | `dyn Trait`, chosen by the callee | `any P`, existentials | none (roadmap) | `Dynamic{X}`; `Callable` in `DynamicCall` mode, the caller overrides |
| Storable dynamic value | yes | `Box<dyn Trait>` | `any P` | `Variant`, `PythonObject` | `Dynamic{X}` |
| How a dynamic call finds the method | a vtable | a vtable, carried with the pointer | a witness table, carried in the existential | witness tables at compile time only | a call-site split over at most four registered implementations, then dispatch; beyond four, which four is split depends on load order |
| Heterogeneous collection | a vector of pointers to a base class, or of `std::variant` *(from memory)* | `Vec<Box<dyn Trait>>`; lazily `impl Iterator<Item = &dyn Trait>` | `[any P]`; lazily `some Sequence<any P>` | `Variant`, `PythonObject` | a copy into `Vector{Dynamic{X}}` today; collection traits with a view planned |
| Who may add an implementation | anyone (structural) | owner of trait or type (orphan rule) | anyone, warned since Swift 6 | the struct's author; extensions proposed | a stakeholder: the trait's or the type's owner; named implementations deferred |
| Overlap | partial specialization | specialization unstable since 2016 | overlapping conformances banned | — | more specific beats generic (built); unordered overlap rejected (design) |
| What keeps compiled generic code valid | recompiled per translation unit | recompiled per crate | resilience: dictionary passing across modules | closed world, no invalidation | compiled code depends on the method table only through facts; invalidated only by a stakeholder or a winning pirate; strict mode refuses the pirate, so trait code is never invalidated but by a stakeholder |
| Calls into code without traits (interop) | unconstrained templates; C++0x forbade it | no untyped code: C through FFI (`unsafe extern`), `dyn Any` with checked downcasts | Objective-C through bridging | Python via `PythonObject` | direct: trait code may call any Julia code; the facts mode makes the call correct and keeps it valid, at a cost where types are not known |

## 1. A trait is an abstract type with behaviour

**The choice** ([traits §5](../reference/traits.md#5-implementations)). A trait is an abstract type whose behaviour is declared: operations with argument and result types, fields with types, associated types as parameters. Traits are a kind of abstract type, not a separate concept. By position a trait reads as an abstract type reads:
- in an argument it is compiled for what its bound can see, as an abstract-typed argument is compiled per type;
- in a field or container it holds any conforming value behind the trait's operations (`Dynamic{X}`), as an abstract-typed field holds a boxed value.

**How the others place it:**
- **Rust's traits are not types,** except as `dyn Trait`.
- **C++20's concepts are predicates on types.**
- **Swift's protocols are types,** and that cost it most. The bare protocol name as an existential "had risen to the level of active harm" ([SE-0335](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0335-existential-any.md)), because it hid boxing and dispatch behind a name that looked like a generic constraint. Rust made `dyn` explicit for the same reason ([RFC 2113](https://rust-lang.github.io/rfcs/2113-dyn-trait-syntax.html)). See `other-languages-research-2026-10-16.md` §7.

**Why ours differs.** Julia types already serve both roles. An abstract type in an argument is specialized, in a field it is boxed, and Julia's performance tips teach both. A trait that reads like an abstract type by position follows a convention Julia users know.
- **The cost the position hides is smaller than Swift's.** A `Dynamic` operation has a declared result type and splits over the declared implementations (section 6), not an open `Any`.
- **Concrete mode reports it** in a hot loop ([traits §3.7](../reference/traits.md#37-concreteness)).
- **Inside trait modules only.** A trait's name in a field means its `Dynamic` there; the explicit spelling `Dynamic{X}` always works. Membership as subtyping waits for traits in the type system (Julia piece 7).

**What traits add over abstract types** is in the declaration, not the use:
- a type joins a trait after it is defined, and joins several (Julia fixes a type's supertypes at its definition);
- the contract is checked at the implementation and at the library's build;
- code is compiled for what the bound can see, so types that forward to fields of one type share compiled code (section 3);
- fields can be required, which Julia's abstract types cannot do.

| Use of an abstract type today | Trait form |
|---|---|
| dispatch on a family, `f(x::AbstractArray)` | a bound, `f(x::ArrayLike)`: compiled per receiver type, or per field type for one that forwards |
| fallback methods for subtypes that define a few | defaults and generic implementations |
| a field or container of mixed types, `Vector{Number}` | `Vector{Dynamic{NumberLike}}`: results declared, split over declared implementations; for a loop over a user's collection, a collection trait (planned, section 11) |
| a constraint on a type parameter, `struct S{T <: Real}` | a type parameter constrained to conforming types (piece 7) |
| required fields (not expressible) | fields declared by the trait, typed by its associated types |
| documentation of intent | operations with declared result types, checked |

**Numbers need no trait.** Base's numeric tower stays, and promotion runs on concrete types in Base. A numeric trait, for numbers that conform after the fact, would need operations across two receiver types, which is promotion; that is open.

**No hidden type parameters:** a struct is never implicitly parametric in the types of fields declared by bounds ([`alternatives.md`](alternatives.md#other-options-considered-and-not-taken)). Stored state of a fixed type uses explicit parameters; of a changing type, `Dynamic{X}`.

## 2. Implementations are declared

**The choice.** A type conforms because someone declared it, `@implement ColTable T`, never because the methods happen to exist. The one-line form keeps declaration cheap; the checks run at the declaration.

**The others** (`other-languages-research-2026-10-16.md` §1):
- **C++.** This was the central fight of the C++0x concepts effort.
  - Indiana (Gregor, Siek, Lumsdaine) wanted declared concept maps. Their example: `istream_iterator` structurally satisfies Forward Iterator, so the faster two-pass algorithm is chosen and fails at run time ([Gregor et al. 2006](https://www.cs.kent.edu/~jmaletic/cs69995-PC/papers/gregor-06.pdf)).
  - Texas A&M (Stroustrup) wanted implicit matching. Accidental matches are "not in the top 100 problems", and explicit maps make library writers "push resolution of even the most obvious choices onto their users" ([N2906](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2009/n2906.pdf)).
  - C++20 ended up structural, with "satisfied but not modeled" ill-formed, no diagnostic required.
- **Mojo** added structural conformance in 2024 and removed it in 2025.
- **Rust and Swift** require the declaration from the start: Rust's `impl`, Swift's conformance. **Carbon** chose declared `impl` plus coherence.

**Why.** In Julia, structural matching proves even less than in C++, where Stroustrup's argument rested on names *and* types matching:
- Base's fallbacks exist and throw, so `getindex` has a method for every `AbstractArray`, and `hasmethod` is true almost everywhere;
- types conform by accident: a `Number` iterates and indexes, a `String` indexes by byte;
- whether a call infers changes with what is loaded.

The prototype refuses an accidental implementation: `Int` has `getindex(::Int, ::Int)`, and is still not `Indexable` (`TraitWorld/test/runtests.jl`, "generic implementations").

**The cost, and the answer.** The C++ debate predicts that declaring implementations explicitly is called "viral". The answers:
- the one-line `@implement T`, which infers forwarding or methods;
- family declarations through Base's abstract types, `@implement Indexable A where {A <: AbstractVector}`: C++0x's templated concept maps.

## 3. Compiled for what the bound can see

**The choice** ([traits §4](../reference/traits.md#4-keys-what-code-is-compiled-for)). Julia compiles a method for the full concrete type of each argument. A bounded function is compiled per **key** instead: the receiver type, if any, and the declared fields' types. Library code reaches a value only through its bound, so this is all it can depend on. Types that differ elsewhere share compiled code.

**Between nested types and `Any`.** Julia code today chooses, field by field, between types that carry the types of all their parts and `Any`. Traits make that choice per implementation and per call mode instead, and the code above a bound keeps the trait's contract whichever way it goes.

| Position | Compiled | A call on the value | Compiled for |
|---|---|---|---|
| Julia: a type parameter | per nested type | direct | the whole type |
| Julia: an `Any` field | the caller once; each target per run-time type when reached | dynamic, result `Any` unless asserted | nothing |
| the type implements the operations | the library per type, in the image that declares the implementation | direct | the type, reached through its operations |
| forwarding to a field | the library per field type | direct | the field's type |
| declared fields | the library per tuple of field types | a load at the field's offset | the fields' types |
| `Callable`, dynamic call | the library once per signature | indirect, 3.95 ns ([evidence §2](evidence.md#2-run-time)), result declared | the signature |
| `Callable`, compiled call | per function type | direct | the function's type |
| `Dynamic{X}` | each operation split over the first four registered implementations; the library per key where it is opened | a split branch, else a dispatch; result declared | the operations, until opened |

**Loads.** In plain Julia, the first two rows can be invalidated by any owner's method at an abstract signature. Under the facts rule every row compiled by facts (trait code and the plain code it reaches; under the test bed `all`, all code) is invalidated only by a stakeholder or a winning pirate ([the rationale §2](../design.md#2-the-argument-in-four-steps)). The control shows that this protection is the facts rule's, for any code, not the traits' ([`evidence.md`](evidence.md) §1). What traits add is that the facts rule costs nothing for them (section 9).

**Growth ends where it is chosen to.** Forwarding, declared fields and dynamic positions end the multiplication of compiled code there: code above compiles per tuple of the keys at its own bounds, whatever was built below.
- Within one function, compiled code still multiplies over that function's bounds.
- It continues only by choice, in the chooser's image: a type that implements the operations itself, a parametric family, a generic implementation, a compiled call, a `Callable` with an open result type.
- The argument is structural. It is not measured on a stack of trait modules ([evidence: Summary: what the evidence shows, and what it does not](evidence.md#summary-what-the-evidence-shows-and-what-it-does-not), "not shown").

**This is not "compiled once for any type".** A type that supplies its own behaviour gets its own copy, once, in its own image. Swift's model, one copy for every conforming type through a witness table, is not chosen: it buys sharing with an indirect call per operation and the cliffs of section 6.

**Precedents** (from memory and the review of the keys plan; not in `other-languages-research-2026-10-16.md`):
- **Haskell's** newtype deriving and `DerivingVia` give a type the instance of a type with the same run-time representation. That is closer to a representation design ([`alternatives.md`](alternatives.md#representations-and-projections-replaced-by-keys)) than to forwarding one field of a record with other fields.
- **Go's** struct embedding satisfies an interface through methods the compiler generates per outer type. Go 1.18 compiles one generic instance per "GC shape", grouping types by underlying type: a key that ignores what the generated code does not distinguish.
- **Kotlin's** `by` forwards an interface's methods to a field.
- **.NET** shares generic code among reference types.
- **Julia's own** function-barrier idiom, passing only the fields an inner function needs, and SciML's AutoSpecialize, which wraps the user's function to stop specialization.

None of them makes a forwarded field the compile key, because none specializes generic code per type the way Julia does.

**What is new over discipline.** Plain Julia can reach the same shape by discipline: convert to a few concrete types first, pass only the fields a function needs, assert results after dynamic calls. Two things are new:
1. **The bound is enforced.** Nothing in library code specializes on the user's type or on fields its bound does not declare.
2. **The targets of the dynamic positions are declared:** the implementations and the `Callable` signatures. A build can list them ([traits §15](../reference/traits.md#15-compiling-ahead)).

Rust's evidence for the pay-off of sharing (`other-languages-research-2026-10-16.md`, "What is new in our design" item 1): up to 30% of LLVM definitions are duplicate instantiations, and retrofitting sharing into the compiler failed (polymorphization removed, `share-generics` off in optimized builds). That argues for putting it in the language.

**What stays** is the trade-off at each position, as in every language with both generics and dynamic dispatch:
- more keys cost compiled code;
- a conversion the library writes costs a copy, and loses what its target cannot hold (dual numbers through a `Float32` pipeline);
- a dynamic position costs a branch, an indirect call or a dispatch.

## 4. Generic code is checked at its definition

**The choice.** Library code is checked once, where it is defined, against its bounds alone, at archetypes: stand-in keys whose operations and fields return values of their declared types and nothing more ([traits §11](../reference/traits.md#11-checks-and-when-they-run)). Open parameters and `Callable` result types are checked per signature at the first call.

**The others** (`other-languages-research-2026-10-16.md` §2):
- **C++0x** checked definitions through archetypes. The concepts compiler was "more than 10 times slower", constrained code sometimes compiled worse, and the specification ran to 91 pages. Concepts were removed in July 2009 ([HOPL4](https://www.stroustrup.com/hopl20main-p5-p-bfc9cd4--final.pdf) §6.2).
- **C++20** checks only use: "Template constraints are applied to enforce the correctness of template use, not the correctness of template definitions" ([N3580](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2013/n3580.pdf)).
- **Doug Gregor's prediction** came true: without definition checking at the start "we will never get separate type checking" ([P0240R0](https://open-std.org/JTC1/SC22/WG21/docs/papers/2016/p0240r0.html)).
- **Rust, Swift and Mojo** check generic bodies before instantiation.

**Why it is cheap here.** Two facts make a worker's code the same for every key:
1. a trait object has no methods but its traits' operations and fields;
2. every operation declares its result type.

The C++0x obstacles do not arise:
- **Name lookup inside constrained code** is settled by dispatch on the trait object.
- **Calls into unconstrained code** are allowed and need no check. The rule C++0x had, "a constrained template cannot call an unconstrained one" (HOPL4 §6.2.5; `other-languages-research-2026-10-16.md` §3), is not ours. Trait code may call any Julia code directly, with ordinary values. Only the trait object is confined: passed bare to plain code, it is refused at its line. So the check covers everything the trait object reaches, and plain values go where they like. What such a call costs, and how Rust and Swift reach untyped code: section 10.
- **Implicit conversions** happen on declared concrete result types.

**The two objections that ended C++0x's definition checking** ([P0557](https://www.stroustrup.com/good_concepts.pdf) §8.2) therefore do not bind:
- **Gradual adoption** ("a library with the concepts cannot use an older library before that library has been modernized"): trait code calls the older library directly. A library adopts traits one function at a time, because types come first in dispatch ([the traits reference](../reference/traits.md)).
- **Scaffolding** ("we would be unable to insert debug aids, logging code, telemetry code … without affecting its interface"): logging and printing are plain calls on ordinary values, such as the results of operations. Adding them changes no bound.

The design does not restrict calls from trait code at all: the facts rule keeps caches valid without it (section 9). How it once held C++0x's rule, and worked around it: [`alternatives.md`](alternatives.md#layering-and-its-workarounds-interface-packages-trait-wrappers-calls-upward-doors-replaced-by-the-facts-rule).

**Measured** (on the previous prototype): the check finds `size(t)`, `typeof(t)` and `sum(t)` in a library before any type conforms; it checks a library of five functions in under 200 ms in a cold session. The gain is errors at the library's build, independent of conforming types, not latency.

## 5. Who may implement: ownership and stakeholders

**The choice** ([the facts mode reference](../reference/facts.md), rule 2).
- A method's **stakeholders** are the owner of its function and the owners of every type in its own signature, a `Union`'s members taken one by one. Anyone else's method is a **pirate**: Julia's "type piracy", as Aqua.jl checks it, made strict for unions.
- Implementations are methods, so the same rule says who may implement a trait for a type: the trait's owner or the type's owner.
- Ownership is never claimed. A package extension belongs to its parent. So an extension's method that wins at a fact of trait code is its parent's change, a stakeholder's: it is followed, and in strict mode with a warning naming the method and the trait code it affects ([traits §12.3](../reference/traits.md#123-strict-mode)).
- **A trait module may not define a pirate** (`OwnershipError` at the definition). Whether that refusal stays, or only winning pirates are refused under strict mode, is open ([traits §12.2](../reference/traits.md#122-pirates); [open issues §1](../open-issues.md#1-decisions-waiting-for-the-user), item 20).
- **Nothing is sealed, and no pirate is refused at load by default.** Strict mode, a switch, refuses a pirate only if it would win at a fact of trait code (section 9).
- Named implementations, which anyone could write, are deferred ([traits §17](../reference/traits.md#17-named-implementations)).

**The others** (`other-languages-research-2026-10-16.md` §4):
- **Rust.** The orphan rule is the same idea for single dispatch: "either the trait must be local or the self-type must be local" ([Matsakis 2015](https://smallcultfollowing.com/babysteps/blog/2015/01/14/little-orphan-impls/)).
  - *Its reasons:* the "hashtable problem" (a value built with one `Hash` impl and queried with another), that any two crates must combine, and semver.
  - *Its pain:* newtype boilerplate; adapter impls with "no obvious home" ([RFC 2451](https://rust-lang.github.io/rfcs/2451-re-rebalancing-coherence.html)); "a kind of chilling effect", with Matsakis concluding the rule "will have to be weakened" ([2022](https://smallcultfollowing.com/babysteps/blog/2022/04/17/coherence-and-crate-level-where-clauses/)); a crate is compilation unit, optimization boundary and coherence boundary at once.
  - Named impls are being proposed ([BoxyUwU 2026](https://www.boxyuwu.blog/posts/an-incoherent-rust/)).
- **Swift** allows retroactive conformances, and its ABI lead regrets it: "Swift should never have allowed arbitrary retroactive conformances" ([Rose 2021](https://belkadan.com/blog/2021/11/Swift-Regret-Retroactive-Conformances/)). His preferred options are owner-only conformances, wrapper types, or named conformances. Since Swift 6 a retroactive conformance warns, and which of two wins "is indeterminate" ([SE-0364](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0364-retroactive-conformance-warning.md)).
- **Mojo** has no extensions yet; its draft proposes an orphan-like rule.
- **Julia** has the rule as a convention: piracy is discouraged, and Aqua.jl checks it.

**How ours compares.**
- **Rose's first option, owner-only conformances, is ours.** His second, wrapper types, is the deferred named implementation's preferred form (`Via{Fast}(x)`, a newtype).
- **Rust's hashtable problem cannot arise:** an implementation is a method, and a value meets the same method table wherever it goes.
- **The rule is the orphan rule generalized to multiple dispatch,** and it is used for a different purpose: Lemma O says only a stakeholder or a pirate can change a fact, so ownership says who can invalidate compiled code ([the rationale §2.1](../design.md#21-step-1-fully-typed-code-is-already-invalidated-only-by-stakeholders-and-pirates)).
- **It is enforced only where it matters.** Rust refuses every orphan impl at compile time. Strict mode refuses a pirate only where it would change trait code. Measured on CSV, DataFrames and CairoMakie: 837 pirates by the letter among 65,318 methods, none refused (previous prototype).
- **The package boundary is not the optimization boundary,** unlike Rust's crate.
- **Split-core packages** (StaticArrays implementing StaticArraysCore's types) are pirates by the letter. A curated list of delegates covers them, marked transitional.

**Overlap and specialization** (`other-languages-research-2026-10-16.md` §5):
- **Rust.** Specialization ([RFC 1210](https://rust-lang.github.io/rfcs/1210-impl-specialization.html)) has been unstable since 2016, because type checking and code generation could pick different impls once lifetimes were erased ([Turon 2017](https://aturon.github.io/blog/2017/07/08/lifetime-dispatch/)). Turon's fix: a more specific impl must not change associated types. Rust made adding a blanket impl a breaking change.
- **Ours:**
  - Julia has no lifetimes. Its analogue, inference and dispatch disagreeing, is settled by the facts rule: a fact is invalidated exactly when dispatch at its signature changes.
  - A more specific implementation must declare the same parameter values as the generic one: Turon's fix.
  - **An equation in a trait always holds** (`T = eltype(Self)`). An implementation that states a value for such a parameter is checked against the equation and refused if they disagree; the stated value never replaces it ([traits §3.4](../reference/traits.md#34-parameters-and-associated-types), [§5.6](../reference/traits.md#56-stating-parameters)). This is the research's lesson from Turon's fix: no implementation overrides an associated type the trait defines (`other-languages-research-2026-10-16.md` §5). Checked for an implementation of one type; for a family the stated value still replaces the equation's (traits T-37).
  - A generic implementation added later that overlaps a downstream specific one should surface where a call meets both. *Design:* the prototype has no overlap check yet.

**Costs to expect:**
- newtypes for the foreign-trait, foreign-type case, until named implementations;
- the social cost of asking owners for implementations;
- pressure for convenience, as Swift kept retroactive conformance behind `@retroactive`.

## 6. Static and dynamic positions, and their defaults

**The choice.**
- **Data** is compiled per key, statically.
- **Functions from plain code** are dynamic calls by default (`DynamicCall`). The library sets the default and the caller overrides it per value, with `compiled_call(f)` or `dynamic_call(f)` ([traits §9](../reference/traits.md#9-callable-functions-at-a-declared-signature)).
- **Data made dynamic** is chosen explicitly: `Dynamic{X}`, or a trait's name in a field or container.

**Defaults in other languages** (`other-languages-research-2026-10-16.md` §7):

| Language | Generic code over types | Function arguments | The other mode |
|---|---|---|---|
| C++ | compiled per type | per function type; `std::function` dynamic | `virtual`, type erasure, explicit |
| Rust | compiled per type | `impl Fn` per closure; `&dyn Fn` dynamic | `dyn Trait`, explicit, in the callee's signature |
| Swift | compiled once, witness tables; specialization an optimization | indirect unless inlined | `@inlinable`, cross-module optimization, `@specialized` |
| Mojo | compiled per type | compiled per closure type | none inside Mojo |
| Julia today | compiled per concrete type | compiled per function type if called in the body | `@nospecialize`, `Any` fields, FunctionWrappers |
| Ours | per key: what a bound can see | dynamic by default; the caller overrides | `Dynamic{X}` |

**Why.**
- **Functions dynamic by default.** That is what Swift chose by design and Rust's practitioners recommend by experience ("prefer `&dyn Fn()` over `impl Fn()`", [matklad](https://matklad.github.io/2021/09/04/fast-rust-builds.html)): compiling per closure costs much and rarely pays. Unlike Rust, the caller can override, so the choice does not leak into the library's API.
- **But both modes stay.** An ODE right-hand side needs a compiled call with a declared, checked signature, which Julia's type system cannot express otherwise.
- **Data static per key.** Operations are direct calls, with no dictionary at run time.
- **Dynamic data is explicit.** It follows Swift's lesson to spell the slow path where it is used, and to decide it before the ecosystem grows.

**How `Dynamic{X}` dispatches: a call-site split, not a table.**
- An operation on a `Dynamic` value is split at the call site over the implementations registered for the trait, the first four, with direct calls, and a dynamic call as the last branch (`Compiler.split_call`, part D; [traits §10](../reference/traits.md#10-dynamicx-values-of-any-conforming-type), [compiler §4.2](../reference/compiler.md#42-compilersplit_call-the-call-site-split)). This is Julia's union splitting applied to a trait's implementations.
- Rust's `dyn` and Swift's `any` call through a table of function pointers. The design does not: pointer tables break under world age and serialization, and a pointer runs in the latest world, not the caller's, which gave a wrong result when the package tried them ([`alternatives.md`](alternatives.md#dynamic-values-pointer-tables-and-witness-tables-replaced-by-the-call-site-split)).
- The split dispatches in the caller's world, as every Julia call does. Candidates are registered without an edge, so a new implementation reaches the fallback and invalidates nothing.
- Measured ([`evidence.md`](evidence.md) §2, the build of 2026-10-19): a sum over `Dynamic{Shape}` costs 0.92–1.40 ns per element against plain Julia's 0.87–0.91 with two types and 29.5–33 with four.
- **The cost against a table:** beyond four implementations, and in which four are split. Section 11.

**Dynamic compatibility.** Rust restricts `dyn Trait` to traits without generic methods, `Self` results or `async fn`. Our operations have concrete declared signatures, and a `Self` result on a `Dynamic` returns a `Dynamic` of the same implementation (built). These restrictions would bind only if operations became generic over other bounds.

## 7. The complexity budget

| | What grew out of control | Cost |
|---|---|---|
| C++0x | the concepts specification, archetypes, `late_check` | 91 pages, compiler 10 times slower, removed |
| Rust | trait solver, generic associated types, specialization | solver rewrite since 2023; generic associated types took 6.5 years; specialization unstable for 10 |
| Swift | recursive associated-type constraints, overloading in the type checker | generic signatures undecidable; "unable to type-check this expression in reasonable time" |
| Mojo | (avoided by design) | no inference from result types: "don't do it again" (Lattner) |

Sources: `other-languages-research-2026-10-16.md` §8.

- **The expensive features were type-level computation in traits:** associated types, recursion among them, higher-ranked bounds, overlap and negative reasoning.
- **Associated types are not the expensive part; reasoning about them symbolically is.** Rust and Swift check a generic body once against its where-clauses, so an associated type is an unknown to normalize, equate and solve for. Recursion among them makes that undecidable.
- **Ours stays out of most of that space.**
  - Workers compile per concrete key, where an associated type is a field's type or a type function evaluated on a concrete type.
  - Only definition checking reasons about them symbolically, and there they are first order: named variables with trait bounds, equal only through a shared variable, never recursive.
  - Parameters are associated types, one value per implementation, as Rust's RFC 195 argued (`explorations/associated-types.md`).
  - Not offered: input parameters, equations between type functions, self-referential bounds ([traits §3.4](../reference/traits.md#34-parameters-and-associated-types)).

## 8. Error messages

**Where unreadable errors come from.** Three ingredients, all needed (`design-findings.md` §17, `experiments/errors/`):
1. **The failure is detected deep inside the library,** because the library never states what it requires.
2. **The whole path is printed:** 22–44 stack frames in the SciML cases.
3. **Every step is printed at its full concrete type,** because concreteness at the bottom forces the concrete type into every signature above. A SciML integrator's type is 3,553 characters.

**The others:**
- **C++20 concepts** move detection to the call and name the failed requirement. But GCC 14's explanation of `std::ranges::sort` on a list is as long as the unconstrained one (29 lines against 28), types still print in full, and incomplete constraints still fail deep inside.
- **Rust's errors are short,** except where nested types are printed; one Diesel error names a "30 page long type" ([RFC 2397](https://rust-lang.github.io/rfcs/2397-do-not-recommend.html)).
- **SciML** writes guidance messages by hand. Each states a requirement after the fact.

**Ours, as built:**
- **Detection moves earlier:** to the implementation (missing operations, wrong result types, unmapped fields) and to the library's build (definition checking).
- **Types print by bound and key:** `ColTable at Vector{Vector{Float64}}`, not the trait object's machinery type (Julia piece 17, type printers). Stack frames inherit it.
- **The machinery's own frames are hidden** from stack traces (`JULIA_TW_ALL_FRAMES=1` shows them).
- **A `MethodError` at an entry names the bound the argument fails,** through Julia's error hints.
- **The limit:** bugs in user code outside trait modules, as in all three SciML cases, are still found at run time. Traces get shorter, and a requirement like "`f` is called with dual numbers" becomes part of a signature, as a second `Callable` bound.
- *Not measured:* the SciML cases have not been rerun against the trait forms.

## 9. The facts rule in the compiler, and strict mode as a switch

**The facts rule in Julia's compiler** ([the rationale §2.3](../design.md#23-step-3-the-facts-rule-extends-the-guarantee-to-code-that-is-not-fully-typed); [`julia-changes.md`](julia-changes.md)).
- Compiled code depends on the method table only through facts. A call at a signature that is not a fact signature dispatches at run time and records nothing.
- **Against the others:** none of C++, Rust, Swift or Mojo caches specialized code per package with a guarantee that loads cannot change it (`other-languages-research-2026-10-16.md`, "What is new in our design" item 4).
  - C++ and Rust recompile per translation unit or crate. C++'s `export` failed because a cached instantiation's meaning depended on where it was instantiated ([N1426](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2003/n1426.pdf)).
  - Swift keeps code valid across modules by dictionary passing, and pays in performance cliffs ([SE-0460](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0460-specialized.md)).
  - Mojo has a closed world and no invalidation.
  - Ours keeps Julia's specialization and a session's open world. Compiled code is valid unless a stakeholder of one of its facts changes, or a pirate wins at one ([the rationale §2.5](../design.md#25-the-default-following-pirates-and-what-it-gives-up), two tiers).
- **The guarantee is the compiler's, not the traits'.** The control: under the test bed `all`, nine unrelated loads cost upstream CSV and DataFrames 2 of 3,337 CodeInstances, against 561 of 4,684 in plain mode ([`evidence.md`](evidence.md) §1, the measurement round of 2026-10-20). So the comparison of cache validity is a comparison of the facts rule, which applies to any Julia code.
- **What traits add to it:** the facts rule costs nothing for fully typed code, and traits make code fully typed where plain Julia loses its types: concrete keys, declared result types at `Dynamic` and `Callable`, declared implementations that the call-site split uses ([the rationale §2.4](../design.md#24-step-4-traits-say-what-code-needs-which-makes-the-facts-rule-cheap)). Where code is not fully typed, the facts rule removes Julia's heuristics, and the code pays at its run-time sites (BaseBenchmarks under the test bed `all`: geometric mean 1.037, tails up to 27.8× on containers of `Any`; [`evidence.md`](evidence.md) §1). Where trait code meets such code, that is an interop cost (section 10).
- **The mode is chosen per module and per method** ([compiler §2.1–2.2](../reference/compiler.md#2-mode-and-owner-per-method)): `@compiler_options facts=true`, which `@trait_module` declares and submodules inherit; in a method body, `Expr(:meta, :facts_boundary)` (compiled in its caller's mode: TraitWorld's entries) or `Expr(:meta, :facts_always)`. A module's other compiler options (`optimize`, `compile`, `infer`, `max_methods`) are to apply in both modes (Planned; today `compile` is ignored for code compiled by facts, compiler C-6).
- **No layering:** trait code calls any Julia code directly, which is what C++ wanted and could not have with definition checking (section 4). Layering, trait wrappers, calls upward, doors and sealing are not part of the design ([`alternatives.md`](alternatives.md#layering-and-its-workarounds-interface-packages-trait-wrappers-calls-upward-doors-replaced-by-the-facts-rule)).
- **AOT.** A `--trim` build compiles the plain call in a closed world, as Mojo does for every program. What traits add is the list of targets: declared implementations and `Callable` signatures ([traits §15](../reference/traits.md#15-compiling-ahead)).

**Strict mode as a switch** ([facts §10.2](../reference/facts.md#strict-mode), [traits §12.3](../reference/traits.md#123-strict-mode); [the rationale §2.2](../design.md#22-step-2-refuse-the-pirates-that-would-win-and-trait-code-is-never-invalidated)).
- **It applies to trait code:** the code of trait modules, compiled by facts. The property it secures is that trait code is never invalidated, except by a stakeholder's change. Plain code is not protected by it. (Today the prototype protects more than trait code, facts F-4.)
- It refuses a pirate that would win at a fact of trait code, or of code compiled by facts that trait code depends on, where it is defined, naming the method and the trait code it would change. Off by default; the default follows the pirate, as plain Julia does.
- **A package extension's winning method is followed, with a warning,** as its parent's change: a stakeholder's extension activated by an unrelated package is not refused ([facts §10.3](../reference/facts.md#strict-intended)).
- **Against the others:** it sits between Rust and Swift. Rust refuses every orphan at compile time. Swift warns and leaves the winner "indeterminate". Strict mode refuses exactly the pirate that would change trait code, and nothing else, at the moment it is defined.
- **A load-order effect the others do not have:** a pirate defined before the trait code it changes is compiled is in the method table, and the code selects it from the start. The intended design refuses a pirate loaded before a package image at the image's validation, and reports the in-session case through `verify_main` as a lint (both Planned, [facts §10.3](../reference/facts.md#strict-intended)). Static languages decide coherence for the whole program at once.
- **Its cost:** 0.54 s on a 4.1 s load of CSV, DataFrames and CairoMakie (previous prototype). Swift's launch-time conformance scans, over 100 ms in large apps (`other-languages-research-2026-10-16.md` §4), are the warning that such checks need indexes.

## 10. Calling into ordinary code

**The choice** ([traits §6.3](../reference/traits.md#63-what-trait-code-may-do-with-a-trait-object); [facts §6](../reference/facts.md#which-code-is-compiled-how)). Trait code may call any Julia code with ordinary values: Base, upstream packages, code written without traits. The facts mode exists to make that call smooth and correct:
- **smooth:** no wrapper, annotation or layer; it is an ordinary Julia call;
- **correct:** the plain code it reaches is compiled by facts too, so G1 (identical or error) and G2 (no unrelated load invalidates it) hold there as well.

So two cases are judged apart. **Interop** is trait code calling plain code on plain data. **Idiomatic trait code** is code written against bounds, as it would be written in Rust or Swift. A cost measured in the first case is an interop cost and is labelled so ([the design](../design.md); [the review's addendum](../reviews/2026-10-20-heterogeneous-collections.md#5-addendum-2026-10-20-after-the-user-read-the-review-interop-and-idiomatic-code)).

**How the others reach code without their bounds:**
- **C++0x** forbade a constrained template to call an unconstrained one (section 4). C++20 allows it, because it checks no definitions.
- **Rust** has no untyped code to call. Its ways out of the type system:
  - C through FFI. Its declarations go in `unsafe extern` blocks, and "a function declared in an extern block is implicitly `unsafe` unless the `safe` function qualifier is present" ([the Rust reference, external blocks](https://doc.rust-lang.org/reference/items/external-blocks.html));
  - `dyn Any`, whose downcasts are checked and return an `Option` ([`std::any`](https://doc.rust-lang.org/std/any/index.html)).
- **Swift's** dynamic world is Objective-C (`other-languages-research-2026-10-16.md`, "At a glance"), reached by bridging. An `NSArray` becomes a `[T]` in one of two ways:
  - **for a class or `@objc` protocol `T`, lazily.** The `NSArray` is kept without a pass, and each element's type is checked when it is read. A mismatch traps with "NSArray element failed to match the Swift Array Element type" ([`ArrayBuffer.swift`](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/ArrayBuffer.swift), `_typeCheckSlowPath`; its comment: "NSArray's need an element typecheck when the element type isn't AnyObject"). The same deferral applies to a forced downcast of a Swift array of class elements: "the trap may be deferred to the point where an offending element is accessed" ([`docs/Arrays.md`](https://github.com/swiftlang/swift/blob/main/docs/Arrays.md); `_arrayForceCast` in [`ArrayCast.swift`](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/ArrayCast.swift)).
  - **for a bridged value type** (`String` from `NSString`, numbers from `NSNumber`), eagerly: "forced bridging back converts `[AnyObject]` to `[X]` in O(N)" ([`docs/Arrays.md`](https://github.com/swiftlang/swift/blob/main/docs/Arrays.md), a design document of the Swift repository, partly marked outdated).
- **Mojo** calls Python through `PythonObject`.

**Ours against them.** Rust and Swift meet untyped code at the edge of another language, with a conversion or a check at that edge. Ours meets it inside Julia: the ordinary code is called directly, with its own values, and only the trait object is confined (section 4). The price is that the ordinary code runs under the facts rule wherever trait code reaches it.

**What the call costs.** These numbers measure interop, not idiomatic trait code.
- **Where types are known: nothing.** For fully typed code, facts inference is plain inference. A typed trait call costs 0.8 ns, as plain Julia does, in both settings ([evidence §2](evidence.md#2-run-time)).
- **Where they are not:** a call at an abstract signature is a run-time site, typed `Any`. The dispatch itself costs what plain Julia's costs. What is lost is the inlining of one-method callees declared at `Any`, and the types after the call: the `Any` cascades through the results ([review F2](../reviews/2026-10-20-heterogeneous-collections.md), E-122, E-123).
  - In the product setting, trait code pays this whenever it calls Base's generic algorithms on containers of `Any`. `filter!` on a `Vector{Any}` takes 36.8 ns per element from a trait module, 1.1 ns from plain code (review F1, E-121, julia-1.13 of 2026-10-20, BenchmarkTools minima).
  - On Base's own benchmarks, under the test bed `all`: geometric mean 1.037, tails up to 27.8× on containers of `Any` ([evidence §1](evidence.md#1-the-guarantee)).
- **A session of upstream code** (E-140: CSV, DataFrames, CairoMakie and seven analysis packages, no trait code; the test bed `all` against plain; julia-1.13 3b8085c222; three fresh sessions per cell, two load orders; [evidence §3](evidence.md#3-first-calls-and-sessions), [`experiments/plotwork/README.md`](../../experiments/plotwork/README.md)). It measures the facts mode on ordinary code, which is what trait code meets when it calls into it.
  - `all` saves 6–10 s per session: recompilation falls from 7.8–11.8 s to 0.4–0.5 s, less about 3 s of slower loading.
  - A round of plotting work (read, build a figure, render, edit) costs 91–169 ms more. The cost is Makie's dictionaries of `Any`, observables and compute graphs: the containers of section 11.
  - Break-even after 42–67 rounds: about one minute of session at 10k rows, six minutes at 200k.

Neither Rust nor Swift has a number to set beside these: their untyped code is in another language, and the cost is paid at the edge, once per conversion or per checked element.

## 11. Heterogeneous collections

**The question:** a loop over values of different types, such as shapes, columns, or the values of a parsed JSON file.

**The others: the producer chooses the representation when the collection is built.**
- **Rust's `Vec<Box<dyn Trait>>`** boxes each element with its vtable as it is pushed ([the Rust reference, trait objects](https://doc.rust-lang.org/reference/types/trait-object.html)).
- **Swift's `[any P]`** holds each element in an existential container with its witness tables ([`docs/ABI/TypeLayout.rst`](https://github.com/swiftlang/swift/blob/main/docs/ABI/TypeLayout.rst), "Existential Container Layout").
- **Converting an untyped collection costs a pass in both, but loses no aliasing:**
  - in Rust the conversion consumes the original, or borrows it, and a borrow forbids writes to the original while it lives ("either one mutable reference or any number of immutable references", [the Rust book §4.2](https://doc.rust-lang.org/book/ch04-02-references-and-borrowing.html));
  - in Swift arrays are values ([the Swift book, "Structures and Enumerations Are Value Types"](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/classesandstructures/)), so a converted array is a new value, and no one expects writes to reach the old one.
- **The idiomatic shape for code that reads is lazy:** an adaptor whose type states the bound on the items, `impl Iterator<Item = &dyn Shape>` in Rust, `some Sequence<any Shape>` in Swift ([SE-0346](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0346-light-weight-same-type-syntax.md), primary associated types). The code states the bound, and the producer keeps its representation.
- **Swift's own view over a foreign collection checks on read:** an `NSArray` bridged to an array of class elements is checked element by element when read, not when converted (section 10).

**Plain Julia: a container with an abstract element type.** `Vector{AbstractShape}`, `Vector{Any}`, `Dict{String,Any}`.
- The element type says only that each element is some subtype. It says neither which operations the loop needs nor what they return.
- Plain Julia makes such loops tolerable by heuristics: speculation over the methods that exist today, and inlining at abstract types. The facts rule removes exactly these, so these containers are its tails (section 10).
- Julia's arrays are shared and mutable: a function that receives a vector may write to it, and the caller sees the writes.

**Ours today: a copy.** Trait code that wants the `Dynamic` split converts the user's collection to `Vector{Dynamic{X}}`, one `Dynamic` per element ([traits §10](../reference/traits.md#10-dynamicx-values-of-any-conforming-type)).
- It costs a pass. Making a `Dynamic` costs 157 ns and 32 bytes today, a scan of the candidate registry (review F4, E-125). That is an implementation cost.
- It loses aliasing: writes to the new vector no longer reach the user's ([open issues §2](../open-issues.md#2-design), item 11).
- In Rust and Swift the language rules that problem out. In Julia it does not, which is why the copy costs more here.

**Ours planned: collection traits and a view** ([open issues §2](../open-issues.md#2-design), item 31; [the design](../design.md)).
- Trait code over heterogeneous data is bounded by a collection trait with a declared item bound, an iterable whose items are `Dynamic{X}`, not by a container type.
- The item type is known from the bound, and each operation on an item is the `Dynamic` split, not a call at `Any`.
- A user's existing vector crosses through a view that wraps each element when it is read: no copy, and the user's vector stays the one that is read and written. This is Rust's and Swift's lazy shape.
- The user's reading: "Vector{AbstractType} is a poor substitute for an Iterable trait and this should be an argument for why we need Traits with facts mode."
- **Open:** which traits (iterable, indexable, mutable indexable, keyed); whether an element that does not conform fails when the view is made or when it is read (Swift's bridging checks on read); who provides the view; what wrapping on read costs. Not built, not measured.

**The dynamic call: a table against a split.**
- **Rust's `dyn` and Swift's existentials call through a table of the type's methods**, a vtable or a witness table, carried with the value. Every implementation costs the same indirect call. There is no limit on the number of implementations, and no dependence on order.
- **Ours splits at the call site** over the implementations registered for the trait, at most four, with direct calls and a dynamic call as the fallback (section 6; [compiler §4.2](../reference/compiler.md#42-compilersplit_call-the-call-site-split)). Within the four, a sum over `Dynamic{Shape}` runs at about plain speed with two types ([evidence §2](evidence.md#2-run-time), the build of 2026-10-19).
- **The cost, beyond four.** These numbers are from HShapes, 64 implementations, product setting (review F4, E-125, julia-1.13 of 2026-10-20, BenchmarkTools minima per element over 1,000 elements):
  - a fifth implementation reaches the fallback, Julia's megamorphic dispatch: an element of another implementation costs 18–68 ns, against about 1 ns for the four;
  - **which four are split depends on load order.** Candidates are registered in declaration order while a package image is built, and in the method table's order after a load. So an image's code and code compiled in the session can split over different fours: H1–H4 in the image, H10, H42, H64 and H14 in the session. The author cannot choose the four today.
  - Rust and Swift have neither the cliff nor the order.
- **Why not a table:** pointer tables break under world age and serialization ([`alternatives.md`](alternatives.md#dynamic-values-pointer-tables-and-witness-tables-replaced-by-the-call-site-split)).
- **What could remove the cost:** the four is a constant of the facts compiler, not Julia's limit on union splitting (review F3). Raising it, or a world-checked table at the fallback, is Optional ([compiler §3.3](../reference/compiler.md#33-further-work-on-mechanism-3)). Deterministic candidates are a proposed experiment (review §3, experiment 4).

---

## What the choices cost

The design restricts what trait code may do, and only there.

1. **Code that is not fully typed pays the facts rule** ([the rationale §2.3](../design.md#23-step-3-the-facts-rule-extends-the-guarantee-to-code-that-is-not-fully-typed)). In trait code and the plain code it reaches, Julia's speculation over abstract calls is gone: such a call is a run-time site with result `Any`. The principle: a slowdown is tolerated if redesigning the code with traits recovers it (the raytrace, `parse_json` so far). Where trait code calls plain code on plain data, this is an interop cost (section 10).
2. **Values crossing in must be values a bound can translate:**
   - values whose type conforms to the bound;
   - functions, as `Callable`;
   - `Dynamic` values;
   - values of declared types, asserted.
3. **Trait objects see only their keys.**
   - Code in a trait module never sees the user's type. It builds a value like its input through constructor operations and the implementation's inverse ([traits §7](../reference/traits.md#7-results-declared-types-like-withfields)).
   - A type whose data needs computing is converted explicitly, at the cost of a copy and no write-through ([traits §5.11](../reference/traits.md#511-types-that-only-convert)).
4. **Types come first.** A type caught by a type-annotated method takes it, even when it also conforms to a bound of the same function. Reaching the trait method needs a type no type method catches, or a newtype.
5. **Capability traits for Base's families are declared by hand:** `@implement Indexable A where {A <: AbstractVector}`.
6. **Dynamic positions are indirect.**
   - 3.95 ns for a `Callable` in `DynamicCall` mode, against 0.87 ns for a direct call ([`evidence.md`](evidence.md) §2).
   - A `Dynamic` operation: a split branch within four registered implementations, Julia's megamorphic dispatch beyond (18–68 ns per element in the review's test), and which four are split depends on load order (section 11).
   - An untyped call into trait code: 28.8 ns per call against 18.9 ns for a plain untyped call in the product setting, 30.8 against 17.6 ns under `all`, 16 bytes per call ([`evidence.md`](evidence.md) §2, the measurement round of 2026-10-20).
7. **Each new receiver type compiles the library once,** in its own image, and the implementation checks cost time: `@implement` of a new model type 66–74 ms in every load order, and its first solve 335–371 ms, mostly the solver compiled for the new key ([`evidence.md`](evidence.md) §3, E-146).
   - **An entry compiled ahead may invalidate plain code.** It is a new method of the library's function, so plain callers of the entry at abstract argument types, and the entry's untyped specialization, may be invalidated at the declaring package's precompilation and at each load of its image. No trait code is discarded, and results stay the same. Accepted for now and flagged for review ([traits §15](../reference/traits.md#15-compiling-ahead); [open issues §2](../open-issues.md#2-design), item 29).
8. **The design needs a patched Julia.** Parts (A)–(D) and the kept pieces ([`julia-changes.md`](julia-changes.md)) are built in a patched 1.13.2, not upstream. Stock-Julia support is dropped. The trait forms' `using` is 0.02–0.20 s above the plain forms' (TraitReport's two pairs, [`evidence.md`](evidence.md) §3).
9. **Overrides are fixed at the implementation.** A later method of an operation a default serves is refused, and changing it needs a restart until redeclaration is built ([traits §3.2](../reference/traits.md#32-defaults)). Plain Julia would follow the method.
10. **Smaller restrictions.**
    - Offering traits is per module (`@trait_module`) and bottom-up.
    - One semantic exception: values Julia decides by inference (A3).
    - The orphan case: a foreign trait for a foreign type needs an owner or a newtype, until named implementations.
11. **Heterogeneous data from plain code is copied.** Until collection traits exist, trait code that wants the `Dynamic` split converts a user's `Vector{Any}` or `Vector{AbstractFoo}` to `Vector{Dynamic{X}}`: a pass, 157 ns and 32 bytes per element today, and writes no longer reach the user's vector (section 11).

## Other options considered

The options considered and not taken, with the reason for each, are on [the alternatives page](alternatives.md#other-options-considered-and-not-taken) and its other topics: one forwarding field per type, representations, layering, the edge-level rule, trait wrappers and sealing, the facts policy as an external interpreter, absorbing dependencies, derived implementations, bounds that compete with types, explicit wrapping at the call, function types, invalidation precision alone, a global invalidation filter, hidden type parameters, shared code through witnesses, `Dynamic` through pointer tables, selecting implementations by imported scope, and strict mode as the default.

## Predictions from other languages, and their status

The predictions are those of `other-languages-research-2026-10-16.md`, "What their experience predicts for us". Statuses as of 2026-10-20.

| # | Prediction | Source | Status |
|---|---|---|---|
| 1 | "Explicit conformance is viral" | C++0x | **answered in the design:** the one-line `@implement`, family declarations. Not tested at ecosystem scale; the forks of CSV and DataFrames are the first case |
| 2 | Layering attacked for gradual adoption and scaffolding | C++0x | **dissolved:** there is no layering; trait code calls any Julia code, and types first in dispatch lets a library adopt traits one function at a time (section 4) |
| 3 | A `late_check`-like inconsistency where values cross upward | C++0x | **ruled out by the boundary:** a trait object never goes up bare (refused, `test/like.jl`); a `Dynamic` dispatches by its implementation wherever it is used. A test of the C++0x case itself is still to write |
| 4 | Pressure for retroactive conformance | Swift, Rust | **open:** named implementations deferred to piece 7; a newtype until then |
| 5 | A later generic implementation overlapping a specific one | Rust | **open:** the design surfaces it at the call; the prototype has no overlap check |
| 6 | A more specific implementation changing types | Rust | **in the design:** same parameter values required; not covered by a test |
| 7 | Load-time checks scanning all methods | Swift | **measured:** strict mode's check, 0.54 s on a 4.1 s load (previous prototype, under the package policy; not rerun on the compiler); indexing by function and type is open |
| 8 | Demand for a storable dynamic value | Swift, Rust | **answered and built:** `Dynamic{X}`, an operation a call-site split in the compiler (part D). Fast for at most four registered implementations; beyond four, which four are split depends on load order (section 11) |
| 9 | Shared code not inlined across packages | Rust | **dissolved as a rule:** compiled code lives where Julia puts it; not measured |
| 10 | Early binding misses a more specific method | C++0x | **dissolved for methods:** a stakeholder's later method breaks the fact and recompiles, as in plain Julia. **Kept for one case:** an override of a default after the implementation is refused (cost 9) |
| 11 | Implicit defaults added later break things | Swift | **decided:** concreteness opt-in per trait, one declaration with a level, chosen when a trait is published |
| 12 | Type-level computation in traits | all four | **kept out:** symbolic reasoning about associated types; associated types themselves in first-order form |
| 13 | Dictionary or witness dispatch for dynamic values | Swift, Rust | **rejected, and confirmed by a failure:** a witness pointer runs in the wrong world (section 6). What the split costs instead: the limit of four and its order (section 11) |
| 14 | A collection of mixed types is converted where it is made, or seen through a lazy adaptor | Rust, Swift | **open:** a copy into `Vector{Dynamic{X}}` today, which loses aliasing; collection traits with a view planned, not built (section 11) |

Rows 13 and 14 are not predictions of `other-languages-research-2026-10-16.md`. Row 13 is the other languages' standard mechanism, tried and dropped ([`alternatives.md`](alternatives.md#dynamic-values-pointer-tables-and-witness-tables-replaced-by-the-call-site-split)). Row 14 is their idiom for heterogeneous data, set against ours in [the review of 2026-10-20](../reviews/2026-10-20-heterogeneous-collections.md) §5.
