# The choices against C++, Rust, Swift and Mojo

How the design's main choices compare with the same choices in C++, Rust, Swift and Mojo, what the design pays for them, and what the other languages' experience predicts, for core developers, as of 2026-10-19 (session 29).
Where this document and [`../design.md`](../design.md) disagree, `design.md` wins.

**Sources.** This document is taken from `notes/2-design-choices.md` (moving to `attic/writeup/notes-2026-10-18/`), §1–4, 8–10 and its closing sections, refreshed against `design.md`. The research behind it is [`../other-languages.md`](../other-languages.md) (session 22, from primary sources: Stroustrup's HOPL papers and WG21 papers, Rust RFCs, Swift Evolution proposals, Mojo's changelogs and proposals). Claims about other languages point there or carry a link; this document does not repeat that research. The "Ours" column of `other-languages.md` is of session 22 and partly superseded; this document's is current.

**Terms** are defined in [`design.md` §1](../design.md#1-terms). Two used here: a *worker* is a bounded function's body compiled per key; *plain code* is code outside trait modules.

## Contents

- At a glance
1. A trait is an abstract type with behaviour
2. Conformance is declared
3. Compiled for what the bound can see
4. Generic code is checked at its definition
5. Who may implement: ownership and stakeholders
6. Static and dynamic positions, and their defaults
7. The complexity budget
8. Error messages
9. What is new since session 22: the facts rule in the compiler, strict mode as a switch
- What the choices cost
- Other options considered
- Predictions from other languages, and their status

---

## At a glance

| Decision | C++ | Rust | Swift | Mojo | Ours |
|---|---|---|---|---|---|
| What a trait is | concept: a predicate on types (C++20) | trait: not a type, except as `dyn Trait` | protocol: also a type (`any P`) | trait: not a type | an abstract type with behaviour |
| Conformance | structural (C++20); C++0x had declared concept maps, then dropped them | declared `impl` | declared, global, retroactive allowed | declared (structural added 2024, removed 2025) | declared `@implement`, never derived from methods |
| Generic code checked | at instantiation only | at definition, against bounds | at definition | before instantiation | at definition, at archetypes; open parameters per signature |
| Code generated | per type (templates) | per type (monomorphization) | once, dictionary passing; specialization an optimization | per type, whole program | per key: what a bound can see; per type only for a type that supplies its own behaviour |
| Conformance through a field | — | by hand, or `Deref` | by hand | — | forwarding (`by field`), compiled per the field's type |
| Dynamic position | virtual functions, type erasure | `dyn Trait`, chosen by the callee | `any P`, existentials | none (roadmap) | `Dynamic{X}`; `Callable` in `DynamicCall` mode, the caller overrides |
| Storable dynamic value | yes | `Box<dyn Trait>` | `any P` | `Variant`, `PythonObject` | `Dynamic{X}`: a call-site split in the compiler, then dispatch |
| Who may add a conformance | anyone (structural) | owner of trait or type (orphan rule) | anyone, warned since Swift 6 | the struct's author; extensions proposed | a stakeholder: the trait's or the type's owner; named implementations deferred |
| Overlap | partial specialization | specialization unstable since 2016 | overlapping conformances banned | — | more specific beats generic (built); unordered overlap rejected (design) |
| What keeps compiled generic code valid | recompiled per translation unit | recompiled per crate | resilience: dictionary passing across modules | closed world, no invalidation | compiled code depends on the method table only through facts; invalidated only by a stakeholder or a winning pirate; strict mode refuses the pirate |
| Calls into code without traits | unconstrained templates; C++0x forbade it | — | — | Python via `PythonObject` | direct: trait code may call any Julia code |

## 1. A trait is an abstract type with behaviour

**The choice** ([`design.md` §4.1](../design.md#41-traits-and-conformance)). A trait is an abstract type whose behaviour is declared: operations with argument and result types, fields with types, associated types as parameters. Traits are a kind of abstract type, not a separate concept. By position a trait reads as an abstract type reads:
- in an argument it is compiled for what its bound can see, as an abstract-typed argument is compiled per type;
- in a field or container it holds any conforming value behind the trait's operations (`Dynamic{X}`), as an abstract-typed field holds a boxed value.

**How the others place it:**
- **Rust's traits are not types,** except as `dyn Trait`.
- **C++20's concepts are predicates on types.**
- **Swift's protocols are types,** and that cost it most. The bare protocol name as an existential "had risen to the level of active harm" ([SE-0335](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0335-existential-any.md)), because it hid boxing and dispatch behind a name that looked like a generic constraint. Rust made `dyn` explicit for the same reason ([RFC 2113](https://rust-lang.github.io/rfcs/2113-dyn-trait-syntax.html)). See `other-languages.md` §7.

**Why ours differs.** Julia types already serve both roles. An abstract type in an argument is specialized, in a field it is boxed, and Julia's performance tips teach both. A trait that reads like an abstract type by position follows a convention Julia users know.
- **The cost the position hides is smaller than Swift's.** A `Dynamic` operation has a declared result type and splits over the declared conformances (section 6), not an open `Any`.
- **Concrete mode reports it** in a hot loop ([`design.md` §4.3](../design.md#43-concreteness-opt-in-per-trait)).
- **Inside trait modules only.** A trait's name in a field means its `Dynamic` there; the explicit spelling `Dynamic{X}` always works. Membership as subtyping waits for traits in the type system (Julia piece 7).

**What traits add over abstract types** is in the declaration, not the use:
- a type joins a trait after it is defined, and joins several (Julia fixes a type's supertypes at its definition);
- the contract is checked at the conformance and at the library's build;
- code is compiled for what the bound can see, so types that forward to fields of one type share compiled code (section 3);
- fields can be required, which Julia's abstract types cannot do.

| Use of an abstract type today | Trait form |
|---|---|
| dispatch on a family, `f(x::AbstractArray)` | a bound, `f(x::ArrayLike)`: compiled per implementing type, or per field type for one that forwards |
| fallback methods for subtypes that define a few | defaults and generic implementations |
| a field or container of mixed types, `Vector{Number}` | `Vector{Dynamic{NumberLike}}`: results declared, split over declared conformances |
| a constraint on a type parameter, `struct S{T <: Real}` | a type parameter constrained to conforming types (piece 7) |
| required fields (not expressible) | fields declared by the trait, typed by its associated types |
| documentation of intent | operations with declared result types, checked |

**Numbers need no trait.** Base's numeric tower stays, and promotion runs on concrete types in Base. A numeric trait, for numbers that conform after the fact, would need operations across two implementing types, which is promotion; that is open.

**Rejected:** hidden type parameters, a struct implicitly parametric in the types of fields declared by bounds. "Hidden type parameters seem antithetical to Julia" (the user, 2026-10-16). Stored state of a fixed type uses explicit parameters; of a changing type, `Dynamic{X}`.

## 2. Conformance is declared

**The choice.** A type conforms because someone declared it, `@implement ColTable T`, never because the methods happen to exist. The one-line form keeps declaration cheap; the checks run at the declaration.

**The others** (`other-languages.md` §1):
- **C++.** This was the central fight of the C++0x concepts effort.
  - Indiana (Gregor, Siek, Lumsdaine) wanted declared concept maps. Their example: `istream_iterator` structurally satisfies Forward Iterator, so the faster two-pass algorithm is chosen and fails at run time ([Gregor et al. 2006](https://www.cs.kent.edu/~jmaletic/cs69995-PC/papers/gregor-06.pdf)).
  - Texas A&M (Stroustrup) wanted implicit matching. Accidental matches are "not in the top 100 problems", and explicit maps make library writers "push resolution of even the most obvious choices onto their users" ([N2906](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2009/n2906.pdf)).
  - C++20 ended up structural, with "satisfied but not modeled" ill-formed, no diagnostic required.
- **Mojo** added structural conformance in 2024 and removed it in 2025.
- **Rust and Swift** declare conformance from the start. **Carbon** chose declared `impl` plus coherence.

**Why.** In Julia, structural matching proves even less than in C++, where Stroustrup's argument rested on names *and* types matching:
- Base's fallbacks exist and throw, so `getindex` has a method for every `AbstractArray`, and `hasmethod` is true almost everywhere;
- types conform by accident: a `Number` iterates and indexes, a `String` indexes by byte;
- whether a call infers changes with what is loaded.

The prototype refuses an accidental conformance: `Int` has `getindex(::Int, ::Int)`, and is still not `Indexable` (`TraitWorld/test/runtests.jl`, "generic implementations").

**The cost, and the answer.** The C++ debate predicts that explicit conformance is called "viral". The answers:
- the one-line `@implement T`, which infers forwarding or methods;
- family declarations through Base's abstract types, `@implement Indexable A where {A <: AbstractVector}`: C++0x's templated concept maps.

## 3. Compiled for what the bound can see

**The choice** ([`design.md` §4.2](../design.md#42-compiled-for-what-the-bound-can-see)). Julia compiles a method for the full concrete type of each argument. A bounded function is compiled per **key** instead: the implementing type, if any, and the declared fields' types. Library code reaches a value only through its bound, so this is all it can depend on. Types that differ elsewhere share compiled code.

**Between nested types and `Any`.** Julia code today chooses, field by field, between types that carry the types of all their parts and `Any`. Traits make that choice per conformance and per call mode instead, and the code above a bound keeps the trait's contract whichever way it goes.

| Position | Compiled | A call on the value | Compiled for |
|---|---|---|---|
| Julia: a type parameter | per nested type | direct | the whole type |
| Julia: an `Any` field | the caller once; each target per run-time type when reached | dynamic, result `Any` unless asserted | nothing |
| the type implements the operations | the library per type, in the conformer's image | direct | the type, reached through its operations |
| forwarding to a field | the library per field type | direct | the field's type |
| declared fields | the library per tuple of field types | a load at the field's offset | the fields' types |
| `Callable`, dynamic call | the library once per signature | indirect, about 4 ns, result declared | the signature |
| `Callable`, compiled call | per function type | direct | the function's type |
| `Dynamic{X}` | each operation split over the declared conformances; the library per key where it is opened | a split branch, else a dispatch; result declared | the operations, until opened |

**Loads.** In plain Julia, the first two rows can be invalidated by any owner's method at an abstract signature. Under the facts rule every row, trait code or plain, is invalidated only by a stakeholder or a winning pirate ([`design.md` §3](../design.md#3-the-argument-in-four-steps)). The control of session 29 shows that this protection is the facts rule's, for any code, not the traits' ([`evidence.md`](evidence.md) §1). What traits add is that the facts rule costs nothing for them (section 9).

**Growth ends where it is chosen to.** Forwarding, declared fields and dynamic positions end the multiplication of compiled code there: code above compiles per tuple of the keys at its own bounds, whatever was built below.
- Within one function, compiled code still multiplies over that function's bounds.
- It continues only by choice, in the chooser's image: a type that implements the operations itself, a parametric family, a generic implementation, a compiled call, a `Callable` with an open result type.
- The argument is structural. It is not measured on a stack of trait modules ([`design.md` §8](../design.md#8-what-the-evidence-shows-and-what-it-does-not), "not shown").

**This is not "compiled once for any type".** A type that supplies its own behaviour gets its own copy, once, in its own image. Swift's model, one copy for every conforming type through a witness table, was considered and not chosen: it buys sharing with an indirect call per operation and the cliffs of section 6.

**Precedents** (from memory and the review of the keys plan; not in `other-languages.md`):
- **Haskell's** newtype deriving and `DerivingVia` give a type the instance of a type with the same run-time representation. That is closer to the abandoned representations than to forwarding one field of a record with other fields.
- **Go's** struct embedding satisfies an interface through methods the compiler generates per outer type. Go 1.18 compiles one generic instance per "GC shape", grouping types by underlying type: a key that ignores what the generated code does not distinguish.
- **Kotlin's** `by` forwards an interface's methods to a field.
- **.NET** shares generic code among reference types.
- **Julia's own** function-barrier idiom, passing only the fields an inner function needs, and SciML's AutoSpecialize, which wraps the user's function to stop specialization.

None of them makes a forwarded field the compile key, because none specializes generic code per type the way Julia does.

**What is new over discipline.** Plain Julia can reach the same shape by discipline: convert to a few concrete types first, pass only the fields a function needs, assert results after dynamic calls. Two things are new:
1. **The bound is enforced.** Nothing in library code specializes on the user's type or on fields its bound does not declare.
2. **The targets of the dynamic positions are declared:** the conformances and the `Callable` signatures. A build can list them ([`design.md` §4.8](../design.md#48-aot-follows-from-declared-targets)).

Rust's evidence for the pay-off of sharing (`other-languages.md`, "What is new in our design" item 1): up to 30% of LLVM definitions are duplicate instantiations, and retrofitting sharing into the compiler failed (polymorphization removed, `share-generics` off in optimized builds). That argues for putting it in the language.

**What stays** is the trade-off at each position, as in every language with both generics and dynamic dispatch:
- more keys cost compiled code;
- a conversion the library writes costs a copy, and loses what its target cannot hold (dual numbers through a `Float32` pipeline);
- a dynamic position costs a branch, an indirect call or a dispatch.

## 4. Generic code is checked at its definition

**The choice.** Library code is checked once, where it is defined, against its bounds alone, at archetypes: stand-in keys whose operations and fields return values of their declared types and nothing more ([`mechanisms.md`](mechanisms.md) §9). Open parameters and `Callable` result types are checked per signature at the first call.

**The others** (`other-languages.md` §2):
- **C++0x** checked definitions through archetypes. The concepts compiler was "more than 10 times slower", constrained code sometimes compiled worse, and the specification ran to 91 pages. Concepts were removed in July 2009 ([HOPL4](https://www.stroustrup.com/hopl20main-p5-p-bfc9cd4--final.pdf) §6.2).
- **C++20** checks only use: "Template constraints are applied to enforce the correctness of template use, not the correctness of template definitions" ([N3580](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2013/n3580.pdf)).
- **Doug Gregor's prediction** came true: without definition checking at the start "we will never get separate type checking" ([P0240R0](https://open-std.org/JTC1/SC22/WG21/docs/papers/2016/p0240r0.html)).
- **Rust, Swift and Mojo** check generic bodies before instantiation.

**Why it is cheap here.** Two facts make a worker's code the same for every key:
1. a trait object has no methods but its traits' operations and fields;
2. every operation declares its result type.

The C++0x obstacles do not arise:
- **Name lookup inside constrained code** is settled by dispatch on the trait object.
- **Calls into unconstrained code** are allowed and need no check. The rule C++0x had, "a constrained template cannot call an unconstrained one" (HOPL4 §6.2.5; `other-languages.md` §3), is not ours. Trait code may call any Julia code directly, with ordinary values. Only the trait object is confined: passed bare to plain code, it is refused at its line. So the check covers everything the trait object reaches, and plain values go where they like.
- **Implicit conversions** happen on declared concrete result types.

**The two objections that ended C++0x's definition checking** ([P0557](https://www.stroustrup.com/good_concepts.pdf) §8.2) therefore do not bind:
- **Gradual adoption** ("a library with the concepts cannot use an older library before that library has been modernized"): trait code calls the older library directly. A library adopts traits one function at a time, because types come first in dispatch ([`design.md` §4.7](../design.md#47-the-rest-of-the-trait-language)).
- **Scaffolding** ("we would be unable to insert debug aids, logging code, telemetry code … without affecting its interface"): logging and printing are plain calls on ordinary values, such as the results of operations. Adding them changes no bound.

The design held C++0x's rule ("layering") until session 23, and answered these objections then with wrappers and calls upward. The facts rule made both unnecessary (section 9).

**Measured** (the prototype, before session 29): the check finds `size(t)`, `typeof(t)` and `sum(t)` in a library before any type conforms; it checks a library of five functions in under 200 ms in a cold session. The gain is errors at the library's build, independent of conforming types, not latency.

## 5. Who may implement: ownership and stakeholders

**The choice** ([`design.md` §1, §5](../design.md#5-the-three-rules), rule 2).
- A method's **stakeholders** are the owner of its function and the owners of every type in its own signature, a `Union`'s members taken one by one. Anyone else's method is a **pirate**: Julia's "type piracy", as Aqua.jl checks it, made strict for unions.
- Implementations are methods, so the same rule says who may implement a trait for a type: the trait's owner or the type's owner.
- Ownership is never claimed. A package extension belongs to its parent.
- **Nothing is sealed, and no pirate is refused at load by default.** Strict mode, a switch, refuses a pirate only if it would win at a fact of compiled code (section 9).
- Named implementations, which anyone could write, are deferred ([`mechanisms.md`](mechanisms.md) §4).

**The others** (`other-languages.md` §4):
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
- **The rule is the orphan rule generalized to multiple dispatch,** and it is used for a different purpose: Lemma O says only a stakeholder or a pirate can change a fact, so ownership says who can invalidate compiled code ([`design.md` §3.1](../design.md#31-step-1-fully-typed-code-is-already-invalidated-only-by-stakeholders-and-pirates)).
- **It is enforced only where it matters.** Rust refuses every orphan impl at compile time. Strict mode refuses a pirate only where it would change compiled code. Measured on CSV, DataFrames and CairoMakie: 837 pirates by the letter among 65,318 methods, none refused (session 25).
- **The package boundary is not the optimization boundary,** unlike Rust's crate.
- **Split-core packages** (StaticArrays implementing StaticArraysCore's types) are pirates by the letter. A curated list of delegates covers them, marked transitional.

**Overlap and specialization** (`other-languages.md` §5):
- **Rust.** Specialization ([RFC 1210](https://rust-lang.github.io/rfcs/1210-impl-specialization.html)) has been unstable since 2016, because type checking and code generation could pick different impls once lifetimes were erased ([Turon 2017](https://aturon.github.io/blog/2017/07/08/lifetime-dispatch/)). Turon's fix: a more specific impl must not change associated types. Rust made adding a blanket impl a breaking change.
- **Ours:**
  - Julia has no lifetimes. Its analogue, inference and dispatch disagreeing, is settled by the facts rule: a fact is invalidated exactly when dispatch at its signature changes.
  - A more specific implementation must declare the same parameter values as the generic one: Turon's fix.
  - A generic implementation added later that overlaps a downstream specific one should surface where a call meets both. *Design:* the prototype has no overlap check yet.

**Costs to expect:**
- newtypes for the foreign-trait, foreign-type case, until named implementations;
- the social cost of asking owners for conformances;
- pressure for convenience, as Swift kept retroactive conformance behind `@retroactive`.

## 6. Static and dynamic positions, and their defaults

**The choice.**
- **Data** is compiled per key, statically.
- **Functions from plain code** are dynamic calls by default (`DynamicCall`). The library sets the default and the caller overrides it per value, with `compiled_call(f)` or `dynamic_call(f)` ([`design.md` §4.6](../design.md#46-functions-as-arguments-callable-two-modes)).
- **Data made dynamic** is chosen explicitly: `Dynamic{X}`, or a trait's name in a field or container.

**Defaults in other languages** (`other-languages.md` §7):

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
- **But both modes stay.** An ODE right-hand side needs a compiled call with a declared, checked signature, which Julia's type system cannot express otherwise (the user, session 29).
- **Data static per key.** Operations are direct calls, with no dictionary at run time.
- **Dynamic data is explicit.** It follows Swift's lesson to spell the slow path where it is used, and to decide it before the ecosystem grows.

**How `Dynamic{X}` dispatches: a call-site split, not a table.**
- An operation on a `Dynamic` value is split at the call site over the declared conformances (at most four), with direct calls that inline, and a dynamic call as the last branch (part D; [`mechanisms.md`](mechanisms.md) §15). This is Julia's union splitting applied to a trait's conformances.
- Rust's `dyn` and Swift's `any` call through a table of function pointers. The design rejected pointer tables in session 22: they break under world age and serialization. The package built them anyway in session 28, as witness tables, and a review found a wrong result: a witness pointer ran in the latest world, not the caller's. They are deleted.
- The split dispatches in the caller's world, as every Julia call does. Candidates are registered without an edge, so a new conformance reaches the fallback and invalidates nothing.
- Measured ([`evidence.md`](evidence.md) §2): a sum over `Dynamic{Shape}` costs 0.92–1.40 ns per element against plain Julia's 0.87–0.91 with two types and 29.5–33 with four.

**Dynamic compatibility.** Rust restricts `dyn Trait` to traits without generic methods, `Self` results or `async fn`. Our operations have concrete declared signatures, and a `Self` result on a `Dynamic` returns a `Dynamic` of the same conformance (built). These restrictions would bind only if operations became generic over other bounds.

## 7. The complexity budget

| | What grew out of control | Cost |
|---|---|---|
| C++0x | the concepts specification, archetypes, `late_check` | 91 pages, compiler 10 times slower, removed |
| Rust | trait solver, generic associated types, specialization | solver rewrite since 2023; generic associated types took 6.5 years; specialization unstable for 10 |
| Swift | recursive associated-type constraints, overloading in the type checker | generic signatures undecidable; "unable to type-check this expression in reasonable time" |
| Mojo | (avoided by design) | no inference from result types: "don't do it again" (Lattner) |

Sources: `other-languages.md` §8.

- **The expensive features were type-level computation in traits:** associated types, recursion among them, higher-ranked bounds, overlap and negative reasoning.
- **Associated types are not the expensive part; reasoning about them symbolically is.** Rust and Swift check a generic body once against its where-clauses, so an associated type is an unknown to normalize, equate and solve for. Recursion among them makes that undecidable.
- **Ours stays out of most of that space.**
  - Workers compile per concrete key, where an associated type is a field's type or a type function evaluated on a concrete type.
  - Only definition checking reasons about them symbolically, and there they are first order: named variables with trait bounds, equal only through a shared variable, never recursive.
  - Parameters are associated types, one value per conformance, as Rust's RFC 195 argued (`explorations/associated-types.md`).
  - Not offered: input parameters, equations between type functions, self-referential bounds ([`mechanisms.md`](mechanisms.md) §1).

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
- **Detection moves earlier:** to the conformance (missing operations, wrong result types, unmapped fields) and to the library's build (definition checking).
- **Types print by bound and key:** `ColTable at Vector{Vector{Float64}}`, not the trait object's machinery type (Julia piece 17, type printers). Stack frames inherit it.
- **The machinery's own frames are hidden** from stack traces (`JULIA_TW_ALL_FRAMES=1` shows them).
- **A `MethodError` at an entry names the bound the argument fails,** through Julia's error hints.
- **The limit:** bugs in user code outside trait modules, as in all three SciML cases, are still found at run time. Traces get shorter, and a requirement like "`f` is called with dual numbers" becomes part of a signature, as a second `Callable` bound.
- *Not measured:* the SciML cases have not been rerun against the trait forms.

## 9. What is new since session 22: the facts rule in the compiler, strict mode as a switch

Two changes since the comparison was first written bear on it.

**The facts rule in Julia's compiler** ([`design.md` §3.3, §6](../design.md#33-step-3-the-facts-rule-extends-the-guarantee-to-all-code-at-a-cost-where-code-is-not-fully-typed); [`julia-changes.md`](julia-changes.md)).
- Compiled code depends on the method table only through facts. A call at a signature that is not a fact signature dispatches at run time and records nothing.
- **Against the others:** none of C++, Rust, Swift or Mojo caches specialized code per package with a guarantee that loads cannot change it (`other-languages.md`, "What is new in our design" item 4).
  - C++ and Rust recompile per translation unit or crate. C++'s `export` failed because a cached instantiation's meaning depended on where it was instantiated ([N1426](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2003/n1426.pdf)).
  - Swift keeps code valid across modules by dictionary passing, and pays in performance cliffs ([SE-0460](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0460-specialized.md)).
  - Mojo has a closed world and no invalidation.
  - Ours keeps Julia's specialization and a session's open world. Compiled code is valid unless a stakeholder of one of its facts changes, or a pirate wins at one ([`design.md` §3.5](../design.md#35-the-default-following-pirates-rule-p-and-what-it-gives-up), two tiers).
- **The guarantee is the compiler's, not the traits'.** The control of session 29: under the test-bed setting, nine unrelated loads cost plain CSV and DataFrames 2 of 3,340 CodeInstances, against 570 of 4,712 in plain mode ([`evidence.md`](evidence.md) §1). So the comparison of cache validity is a comparison of the facts rule, which applies to any Julia code.
- **What traits add to it:** the facts rule costs nothing for fully typed code, and traits make code fully typed where plain Julia loses its types: concrete keys, declared result types at `Dynamic` and `Callable`, declared conformances that the call-site split uses ([`design.md` §3.4](../design.md#34-step-4-traits-say-what-code-needs-which-makes-the-facts-rule-cheap-and-can-enforce-concreteness)). Where code is not fully typed, the facts rule removes Julia's heuristics, and the code pays at its run-time sites (BaseBenchmarks under the test bed: geometric mean 1.016, tails up to about 80× on containers of `Any`).
- **What it removed from the comparison:** layering (C++0x's rule), trait wrappers, calls upward, doors and sealing. Trait code calls any Julia code directly, which is what C++ wanted and could not have with definition checking (section 4).
- **AOT.** A `--trim` build compiles the plain call in a closed world, as Mojo does for every program. What traits add is the list of targets: declared conformances and `Callable` signatures ([`design.md` §4.8](../design.md#48-aot-follows-from-declared-targets)).

**Strict mode as a switch** ([`design.md` §3.2, §3.5](../design.md#32-step-2-outlaw-pirates-and-fully-typed-code-is-always-valid-and-can-be-cached)).
- It refuses a pirate that would win at a fact of compiled code, where it is defined, naming the method and the code it would change. Off by default; the default follows the pirate, as plain Julia does.
- **Against the others:** it sits between Rust and Swift. Rust refuses every orphan at compile time. Swift warns and leaves the winner "indeterminate". Strict mode refuses exactly the pirate that would change compiled code, and nothing else, at the moment it is defined.
- **A load-order effect the others do not have:** under strict mode, which pirate is refused depends on the order of loads, unless the symmetric check runs as a build lint. Static languages decide coherence for the whole program at once.
- **Its cost:** 0.54 s on a 4.1 s load of CSV, DataFrames and CairoMakie (session 25). Swift's launch-time conformance scans, over 100 ms in large apps (`other-languages.md` §4), are the warning that such checks need indexes.

---

## What the choices cost

The design restricts what trait code may do, and only there. The list of session 22 is refreshed: items that described layering, sealing and wrappers are replaced.

1. **Code that is not fully typed pays the facts rule** ([`design.md` §3.3](../design.md#33-step-3-the-facts-rule-extends-the-guarantee-to-all-code-at-a-cost-where-code-is-not-fully-typed)). In trait code and the plain code it reaches, Julia's speculation over abstract calls is gone: such a call is a run-time site with result `Any`. The principle: a slowdown is tolerated if redesigning the code with traits recovers it (the raytrace, `parse_json` so far).
2. **Values crossing in must be values a bound can translate:**
   - values whose type conforms to the bound;
   - functions, as `Callable`;
   - `Dynamic` values;
   - values of declared types, asserted.
3. **Trait objects see only their keys.**
   - Code in a trait module never sees the user's type. It builds a value like its input through constructor operations and the conformance's inverse ([`mechanisms.md`](mechanisms.md) §13).
   - A type whose data needs computing is converted explicitly, at the cost of a copy and no write-through ([`mechanisms.md`](mechanisms.md) §14).
4. **Types come first.** A type caught by a type-annotated method takes it, even when it also conforms to a bound of the same function. Reaching the trait method needs a type no type method catches, or a newtype.
5. **Capability traits for Base's families are declared by hand:** `@implement Indexable A where {A <: AbstractVector}`.
6. **Dynamic positions are indirect.**
   - About 4 ns for a dynamic call.
   - A `Dynamic` operation: a split branch within four conformances, a dispatch beyond.
   - An untyped call into trait code: 115–129 ns against about 55 for a plain untyped call ([`evidence.md`](evidence.md) §2).
7. **Each new implementing type compiles the library once,** in its own image, and the conformance checks cost time: `@implement` of a new model type 142–164 ms in every load order ([`evidence.md`](evidence.md) §3).
8. **The design needs a patched Julia.** Parts (A)–(D) and the kept pieces ([`julia-changes.md`](julia-changes.md)) are built in a patched 1.13.2, not upstream. Stock-Julia support is dropped. The trait forms' `using` is 0.18–0.20 s above the plain forms'.
9. **Overrides are fixed at the conformance.** A later method of an operation a default serves is refused, and changing it needs a restart until redeclaration is built ([`design.md` §4.4](../design.md#44-overrides-belong-to-the-conformance)). Plain Julia would follow the method.
10. **Smaller restrictions.**
    - Offering traits is per module (`@trait_module`) and bottom-up.
    - One semantic exception: values Julia decides by inference (A3).
    - The orphan case: a foreign trait for a foreign type needs an owner or a newtype, until named implementations.

## Other options considered

- **One forwarding field per type,** for every trait it joins. Rejected: what a type means differs between traits.
- **Representations reached by any projection,** computed or copied, with a written inverse (the design until session 22). Replaced by keys: computed projections copied, needed inverses and stale views, and packed several fields into one type.
- **Layering:** trait code calls only trait code (C++0x's rule; the design until session 23). Superseded by the facts rule: trait code calls any Julia code (section 4).
- **The edge-level rule:** compile only concrete calls against the current methods and make abstract ones dynamic. Rejected in session 22 for its cliff at abstract calls and for having no closed world for AOT. **Adopted later in substance** as the facts rule (sessions 23, 28): the cliff is accepted as run-time sites, recovered by traits, and AOT is restated through declared targets.
- **Trait wrappers, calls upward, sealing over views** (sessions 20–22). Superseded by the facts rule (session 23). No sealing, of abstract types or functions: a closed contract is a trait (session 28).
- **The facts policy as an external interpreter** (`FactsInterp`, its own cache, a frozen compiler world, view caches). Superseded by the facts mode in Julia's compiler (session 28; built in session 29).
- **Absorbing dependencies:** each package brings its ordinary dependencies into its own world. Rejected: two packages that absorb Makie conflict as soon as one defines a recipe.
- **Deriving conformance from the methods that exist.** Rejected (section 2).
- **Trait bounds that compete with types,** ranked like abstract types. Rejected: the conflict would surface only in an application that loads both packages.
- **Explicit wrapping at the call,** `f(ColTable(x))`. Rejected: adopting traits would change every caller.
- **Function types in the type system,** `Float64 -> Float64`. A far larger change to Julia than one trait whose only operation is checked at every call.
- **Better invalidation precision** alone. Largely upstream in Julia 1.12, and not enough on its own.
- **A global invalidation filter,** ignoring later definitions. Unsound for ordinary code. The prototype's filter (Julia pieces 2 and 4) is reverted.
- **Hidden type parameters** for fields declared by bounds. Rejected as un-Julian (section 1).
- **Shared code through witnesses,** Swift's model: one copy for every conforming type. Not chosen (section 3).
- **`Dynamic` through pointer tables.** Rejected in session 22 (world age, serialization, races); built in session 28 as witness tables, found to give a wrong result across worlds, deleted (section 6).
- **Selecting implementations by imported scope,** as Scala's implicits do. Rejected: an entry is compiled once and does not know its caller's module.
- **Strict mode as the default.** Not chosen for now: the default session follows pirates, and strict mode is the stated guarantee's switch ([`design.md` §3.5](../design.md#35-the-default-following-pirates-rule-p-and-what-it-gives-up)).

## Predictions from other languages, and their status

The predictions are those of `other-languages.md`, "What their experience predicts for us". Statuses as of session 29.

| # | Prediction | Source | Status |
|---|---|---|---|
| 1 | "Explicit conformance is viral" | C++0x | **answered in the design:** the one-line `@implement`, family declarations. Not tested at ecosystem scale; the forks of CSV and DataFrames are the first case |
| 2 | Layering attacked for gradual adoption and scaffolding | C++0x | **dissolved:** no layering since session 23; trait code calls any Julia code, and types first in dispatch lets a library adopt traits one function at a time (section 4) |
| 3 | A `late_check`-like inconsistency where values cross upward | C++0x | **ruled out by the boundary:** a trait object never goes up bare (refused, `test/like.jl`); a `Dynamic` dispatches by its conformance wherever it is used. A test of the C++0x case itself is still to write |
| 4 | Pressure for retroactive conformance | Swift, Rust | **open:** named implementations deferred to piece 7; a newtype until then |
| 5 | A later generic implementation overlapping a specific one | Rust | **open:** the design surfaces it at the call; the prototype has no overlap check |
| 6 | A more specific implementation changing types | Rust | **in the design:** same parameter values required; not covered by a test |
| 7 | Load-time checks scanning all methods | Swift | **measured:** strict mode's check, 0.54 s on a 4.1 s load; indexing by function and type is open |
| 8 | Demand for a storable dynamic value | Swift, Rust | **answered and built:** `Dynamic{X}`, an operation a call-site split in the compiler (part D) |
| 9 | Shared code not inlined across packages | Rust | **dissolved as a rule** (rule 4 retired): compiled code lives where Julia puts it; not measured |
| 10 | Early binding misses a more specific method | C++0x | **dissolved for methods:** a stakeholder's later method breaks the fact and recompiles, as in plain Julia. **Kept for one case:** an override of a default after the conformance is refused (cost 9) |
| 11 | Implicit defaults added later break things | Swift | **decided:** concreteness opt-in per trait, one declaration with a level, chosen when a trait is published |
| 12 | Type-level computation in traits | all four | **kept out:** symbolic reasoning about associated types; associated types themselves in first-order form |
| 13 | Dictionary or witness dispatch for dynamic values | Swift, Rust | **rejected, then confirmed by failure:** witness tables ran in the wrong world (section 6) |

Row 13 is new: it is not a prediction of `other-languages.md`, but the other languages' standard mechanism, tried and dropped.
