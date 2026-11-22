# The choices against C++, Rust, Swift and Mojo

A chapter of the [rationale](../design.md): how the design's main choices compare with the same choices in C++, Rust, Swift and Mojo, what the design pays for them, and what the other languages' experience predicts. It is written for core developers. Where this chapter and the [references](../reference/README.md) disagree, the references win.

**Sources.**
- The research behind it is [`../record/other-languages-research-2026-10-16.md`](../record/other-languages-research-2026-10-16.md), from primary sources: Stroustrup's HOPL papers and WG21 papers, Rust RFCs, Swift Evolution proposals, Mojo's changelogs and proposals. A claim about another language points there or carries a link. This chapter does not repeat that research.
- Sections 10 and 11 cite primary sources directly: the Swift repository's documents and standard library, the Rust reference and the Rust book. Section 12 rests on [`../record/incremental-precedents-research-2026-10-27.md`](../record/incremental-precedents-research-2026-10-27.md).
- The research's "Ours" column describes the design of its own date. This chapter's column is the design of the references ([`alternatives.md`](alternatives.md#claims-withdrawn)).
- A number about this design is from [the evidence](evidence.md), cited by its experiment (E-n).

**Terms** are the [glossary](../glossary.md)'s. The ones used most here:
- a type that joins a trait is a **member**; its **membership** is declared, `@implement X S`;
- a member is passed as itself or in one of two **kept forms**: the **box** `Dynamic{X}(x)`, whose code is compiled once per trait instance, and the **wrapper** `compiled_for(x)`, whose code is compiled for the object's type;
- **trait code** is the code of a trait module, compiled by facts; **plain code** is code compiled under Julia's own rules.

## Contents

- At a glance
1. A trait is an abstract type with behaviour
2. Memberships are declared
3. What code is compiled for: the value's type
4. Generic code is checked at its definition
5. Who may declare a membership: ownership and stakeholders
6. Erasing and code per type: the box and the wrapper
7. The complexity budget
8. Error messages
9. The facts rule in the compiler, and strict mode as a switch
10. Calling into ordinary code
11. Heterogeneous collections
12. Compiled code kept across sessions: what a stored entry rests on
- What the choices cost
- Other options considered (on the alternatives page)
- Predictions from other languages, and their status

---

## At a glance

| Decision | C++ | Rust | Swift | Mojo | Ours |
|---|---|---|---|---|---|
| What a trait is | concept: a predicate on types (C++20) | trait: not a type, except as `dyn Trait` | protocol: also a type (`any P`) | trait: not a type | an abstract type with open membership and a contract |
| Membership | structural (C++20); C++0x had declared concept maps, then dropped them | declared `impl` | declared, global, retroactive allowed | declared (structural added 2024, removed 2025) | declared `@implement`, never inferred from the methods that exist |
| Generic code checked | at instantiation only | at definition, against bounds | at definition | before instantiation | at definition: the method's instance at the box, a real type as the archetype |
| Code generated | per type (templates) | per type (monomorphization) | once, dictionary passing; specialization an optimization | per type, whole program | per value's type: a plain member's or a wrapper's object's type; once per trait instance for a box |
| Membership through a field | — | by hand, or `Deref` | by hand | — | forwarding, `by field`, a convenience of the library |
| Dynamic position | virtual functions, type erasure | `dyn Trait`, chosen by the callee | `any P`, existentials | none (roadmap) | the box `Dynamic{X}(x)`, a member of `X`; a trait that erases by default boxes a plain member, `Callable` among them; the caller passes the wrapper `compiled_for(x)` for code per type |
| Storable dynamic value | yes | `Box<dyn Trait>` | `any P` | `Variant`, `PythonObject` | `Dynamic{X}`; a field typed by the trait holds any member |
| How a dynamic call finds the method | a vtable | a vtable, carried with the pointer | a witness table, carried in the existential | witness tables at compile time only | a branch over the first four members declared, then a table of the call's targets keyed by the value's type |
| Heterogeneous collection | a vector of pointers to a base class, or of `std::variant` *(from memory)* | `Vec<Box<dyn Trait>>`; lazily `impl Iterator<Item = &dyn Trait>` | `[any P]`; lazily `some Sequence<any P>` | `Variant`, `PythonObject` | `Vector{Shape}` or `Vector{Dynamic{Shape}}`; code bounded on the items, `Iterable{<:Shape}`; a `Vector{Any}` converted with a copy |
| Who may add a membership | anyone (structural) | owner of trait or type (orphan rule) | anyone, warned since Swift 6 | the struct's author; extensions proposed | a stakeholder: the trait's owner or the type's; another's is a pirate's, followed with a warning; named implementations Planned |
| Overlap | partial specialization | specialization unstable since 2016 | overlapping conformances banned | — | more specific beats generic, as in Julia; an unordered overlap is Julia's ambiguity, reported at the membership; one instance per member |
| What keeps compiled generic code valid | recompiled per translation unit | recompiled per crate | resilience: dictionary passing across modules | closed world, no invalidation | compiled code depends on the method table only through facts; invalidated only by a stakeholder's change or a winning pirate; strict mode refuses the pirate |
| Calls into code without traits (interop) | unconstrained templates; C++0x forbade it | no untyped code: C through FFI (`unsafe extern`), `dyn Any` with checked downcasts | Objective-C through bridging | Python via `PythonObject` | direct: trait code may call any Julia code; the facts mode makes the call correct and keeps it valid, at a cost where types are not known |

## 1. A trait is an abstract type with behaviour

**The choice** ([traits §1](../reference/traits.md#1-overview), [§3](../reference/traits.md#3-traits-are-abstract-types)). A trait is an abstract type with two additions:
- **open membership:** a type may join after its own definition, by a declaration;
- **a contract:** operations with argument and result types, declared fields, and the values of the trait's parameters, checked at each membership.

Everything else is Julia's. A trait is written wherever a type is written, and dispatch is Julia's. By position a trait reads as an abstract type reads:
- in an argument, a method is compiled for the type of the value it is given, as at an abstract-typed argument ([traits §7.1](../reference/traits.md#71-how-an-argument-is-compiled));
- in a field or a container, it holds any member, each by its own type, as an abstract-typed field does ([traits §8.1](../reference/traits.md#81-fields-and-containers-typed-by-a-trait)).

**How the others place it:**
- **Rust's traits are not types,** except as `dyn Trait`.
- **C++20's concepts are predicates on types.**
- **Swift's protocols are types,** and that cost it most. The bare protocol name as an existential "had risen to the level of active harm" ([SE-0335](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0335-existential-any.md)), because it hid boxing and dispatch behind a name that looked like a generic constraint. Rust made `dyn` explicit for the same reason ([RFC 2113](https://rust-lang.github.io/rfcs/2113-dyn-trait-syntax.html)). See `other-languages-research-2026-10-16.md` §7.

**Why ours differs.** Julia types already serve both roles. An abstract type in an argument is specialized, in a field it is boxed, and Julia's performance tips teach both. A trait that reads like an abstract type by position follows a convention Julia users know.
- **The cost the position hides is smaller than Swift's.** An operation on a value the code knows only by its trait has a declared result, and branches over the trait's first four members (section 6), not a call at `Any` ([traits §7.9](../reference/traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait)).
- **Fully typed mode reports** where code loses its types ([traits §14](../reference/traits.md#14-concreteness-and-fully-typed-mode)).
- **The cost is spelled where it is chosen.** A field typed by the trait holds each member by its own type. The box `Dynamic{X}(x)` is written where code wants the value erased, and a trait that erases by default says so in its declaration, `@default_dynamic` ([traits §4.6](../reference/traits.md#46-erasing-by-default), [§7.5](../reference/traits.md#75-what-decides)).

**What traits add over abstract types** is in the declaration, not the use:
- a type joins a trait after it is defined, and joins several (Julia fixes a type's supertypes at its definition);
- the contract is checked at each membership, and a method at a trait is checked where it is defined (section 4);
- fields can be required, which Julia's abstract types cannot do.

| Use of an abstract type today | Trait form |
|---|---|
| dispatch on a family, `f(x::AbstractArray)` | a method at a trait, `f(x::Indexable)`: compiled for the value's type |
| fallback methods for subtypes that define a few | defaults, the trait's methods ([traits §4.2](../reference/traits.md#42-defaults)) |
| a field or container of mixed types, `Vector{Number}` | `Vector{Shape}`: each item its own value, an operation on it a branch with a declared result; `Vector{Dynamic{Shape}}`: each item boxed (section 11) |
| a constraint on a type parameter, `struct S{T <: Real}` | a struct parameter bounded by a trait, `struct Problem{F <: Model}`, which records the form it is given ([traits §8.2](../reference/traits.md#82-a-struct-parameter-bounded-by-a-trait)) |
| required fields (not expressible) | fields declared by the trait, typed by its parameters ([traits §4.3](../reference/traits.md#43-fields)) |
| documentation of intent | operations with declared result types, checked |

**Numbers need no trait.** Base's numeric tower stays, and promotion runs on concrete types in Base. A numeric trait, for numbers that join after the fact, would need operations across two receiver types, which is promotion. That is open ([open issues §4](../open-issues.md#4-design), item 8).

**No hidden type parameters:** a struct is never implicitly parametric in the types of fields declared by bounds ([`alternatives.md`](alternatives.md#further-options-not-taken)). Stored state of a fixed type uses an explicit parameter bounded by the trait ([traits §8.2](../reference/traits.md#82-a-struct-parameter-bounded-by-a-trait)); of a changing type, a field typed by the trait or `Dynamic{X}`.

<a id="2-implementations-are-declared"></a>

## 2. Memberships are declared

**The choice** ([traits §5.1](../reference/traits.md#51-the-forms)). A type is a member because someone declared it, `@implement ColTable T`, never because the methods happen to exist. The one-line form keeps the declaration cheap; the checks run at the declaration, or at a pattern member's first use ([traits §5.10](../reference/traits.md#510-checks)).

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

So a type is a member only where declared: a `Number` iterates in Base and is not `Iterable` ([traits §10.1](../reference/traits.md#101-basetraits)). `Callable` follows the same rule: every `Function` is a member by Julia's own declaration, and a callable struct that is no `Function` joins by its owner's `@implement Callable T`; subtyping reads no method ([traits §9](../reference/traits.md#9-functions-callable)).

**The cost, and the answer.** The C++ debate predicts that declaring memberships explicitly is called "viral". The answers:
- the one-line `@implement X T`, served by the type's own methods, and `by field` for forwarding ([traits §5.3](../reference/traits.md#53-one-line), [§5.5](../reference/traits.md#55-forwarding-with-by));
- families and abstract types as members, C++0x's templated concept maps: `@implement Indexable{T} AbstractVector{T} where {T}` ([traits §5.8](../reference/traits.md#58-families), [§5.9](../reference/traits.md#59-abstract-types-and-traits-as-members));
- where the cost shows: 134 of 174 callable types in the forks' session are no `Function`, so each needs its owner's declaration to be a `Callable` (E-500; [GT-32](../open-issues.md#gt-32-a-callable-struct-that-is-no-function-is-no-member-of-callable-until-its-owner-declares-it)).

<a id="3-compiled-for-what-the-bound-can-see"></a>

## 3. What code is compiled for: the value's type

**The choice** ([traits §7.1](../reference/traits.md#71-how-an-argument-is-compiled), [§7.5](../reference/traits.md#75-what-decides)). A method at a trait is compiled as Julia compiles any method: for the types of the values it is given. A trait adds two kept forms of a member, each a concrete type and a member of the trait ([traits §7.4](../reference/traits.md#74-the-two-kept-forms-the-box-and-the-wrapper)):
- **a plain member:** code for its type, one copy per concrete type, as in Julia;
- **the box `Dynamic{X}(x)`:** code compiled once per trait instance, one copy for every member;
- **the wrapper `compiled_for(x)`:** code compiled for the type of the object it holds.

The value's type decides. Nothing beside the values decides: not the call's site, not the method's module. Rust's pair is the same: `dyn X` and a generic `T: X`. Swift's is `any X` and a generic. Here both kept forms are members of `X`, so one method at `X` takes either.

| Position | Compiled | A call on the value | Compiled for |
|---|---|---|---|
| Julia: a type parameter | per nested type | direct | the whole type |
| Julia: an `Any` field | the caller once; each target per run-time type when reached | dynamic, result `Any` unless asserted | nothing |
| a plain member at a trait argument | per member type, in the image of the package that declares the membership ([traits §16](../reference/traits.md#16-compiling-ahead-closed-programs)) | direct | the member's type |
| the wrapper `compiled_for(x)` | per object type | direct: 0.79 ns, as plain Julia (E-443) | the object's type |
| the box `Dynamic{X}(x)` | once per trait instance | a branch over the first four members, else the table: 5.56 ns and 9.14 ns (E-443); result declared | the contract's operations |
| `Callable`, boxed | once per signature | a dynamic call with the result asserted: 25.19–25.31 ns (E-513) | the signature |
| `Callable`, the wrapper | per function type | the function's own call: 0.79 ns (E-513) | the function's type |
| `@nospecialize(t::X)` | once at the declared type | as for the box, on the object itself | the trait instance |

**Loads.** In plain Julia, the first two rows can be invalidated by any owner's method at an abstract signature. Under the facts rule, code compiled by facts in the deep class (trait code, and plain code compiled by facts) is invalidated only by a stakeholder's change or a winning pirate ([facts §2.2](../reference/facts.md#22-g2-stable-caches); [the rationale §2.3](../design.md#23-step-3-the-facts-rule-extends-the-guarantee-to-code-that-is-not-fully-typed)). That protection is the facts rule's, for any code, not the traits' ([the evidence, G-1](evidence.md#1-the-guarantee)). What traits add is that the facts rule costs nothing for them (section 9).

**This is not "compiled once for any type".** Code compiled once for a box still calls each member's own methods, each compiled for its type, in its own image ([the rationale §4](../design.md#4-what-is-not-claimed)). Swift's model, one copy for every conforming type through a witness table, is the box here: chosen per value, or per trait by `@default_dynamic`, and not the default. Swift buys sharing with an indirect call per operation and the cliffs of section 6.

**Keys, an optional extension.** Members that the contract sees alike (a type that forwards to a field of a type another member has) could share one compiled copy of a bounded method, per **key** ([extensions §1](../reference/extensions.md#1-keys-code-shared-among-members-the-contract-sees-alike)). No rule of the references depends on it. Precedents (from memory, not in `other-languages-research-2026-10-16.md`):
- **Go 1.18** compiles one generic instance per "GC shape", grouping types by underlying type: a key that ignores what the generated code does not distinguish.
- **.NET** shares generic code among reference types.
- **Kotlin's** `by` forwards an interface's methods to a field; Go's struct embedding does it per outer type.
- **Julia's own** function-barrier idiom, passing only the fields an inner function needs, and SciML's AutoSpecialize, which wraps the user's function to stop specialization.

Rust's evidence for the pay-off of sharing (`other-languages-research-2026-10-16.md`, "What is new in our design" item 1): up to 30% of LLVM definitions are duplicate instantiations, and retrofitting sharing into the compiler failed (polymorphization removed, `share-generics` off in optimized builds). That argues for putting sharing in the language. Here it is in the language as the box, a value's choice.

**What is new over discipline.** Plain Julia can reach the same shape by discipline: a function barrier, `@nospecialize`, results asserted after dynamic calls. Three things are new:
1. **The caller chooses with a value.** The box and the wrapper are types, so storage, an untyped parameter and a closed build keep the choice ([traits §7.4](../reference/traits.md#74-the-two-kept-forms-the-box-and-the-wrapper)). `@nospecialize` is a hint per argument with no say for the caller.
2. **The erased code is checked:** a bounded method works, erased, for every member that will ever join (section 4).
3. **The targets of the dynamic positions are declared:** the memberships and the `Callable` signatures. A build lists them ([traits §16](../reference/traits.md#16-compiling-ahead-closed-programs)).

**What stays** is the trade-off at each position, as in every language with both generics and dynamic dispatch:
- code per type costs compiled code;
- a conversion the library writes costs a copy, and loses what its target cannot hold (dual numbers through a `Float32` pipeline; [traits §5.12](../reference/traits.md#512-types-that-only-convert));
- erased code costs a branch, an indirect call or a dispatch per operation.

## 4. Generic code is checked at its definition

**The choice** ([traits §7.3](../reference/traits.md#73-bounded-methods), [§11.2](../reference/traits.md#112-definition-checking)). A method at a trait is checked once, where it is defined, for every member that will ever join. The check reads the method's instance at the box `Dynamic{X}`: Julia's own inference of the code a box runs. The method is **bounded** where that code makes no call, with a value at the box, that finds no method or only throws. The archetype is a real type, the box: behind it only the contract's operations reach the member. A variable the signature leaves free is read at a stand-in: the first of `Float64`, `Int`, `Symbol`, `String` its bounds allow.
- A scope that declares `bounded` refuses a method that is not bounded, with `TraitUseError` naming each fault and its line. `@trait_module` declares it.
- `@unbounded` marks a method that hands its argument to plain code on purpose.

**The others** (`other-languages-research-2026-10-16.md` §2):
- **C++0x** checked definitions through archetypes. The concepts compiler was "more than 10 times slower", constrained code sometimes compiled worse, and the specification ran to 91 pages. Concepts were removed in July 2009 ([HOPL4](https://www.stroustrup.com/hopl20main-p5-p-bfc9cd4--final.pdf) §6.2).
- **C++20** checks only use: "Template constraints are applied to enforce the correctness of template use, not the correctness of template definitions" ([N3580](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2013/n3580.pdf)).
- **Doug Gregor's prediction** came true: without definition checking at the start "we will never get separate type checking" ([P0240R0](https://open-std.org/JTC1/SC22/WG21/docs/papers/2016/p0240r0.html)).
- **Rust, Swift and Mojo** check generic bodies before instantiation.

**Why it is cheap here.** Two facts make the box's code the same for every member:
1. a box has no methods but its trait's operations and fields: it is a member of its trait and its supertraits only ([traits §7.7](../reference/traits.md#77-dynamicx));
2. every operation declares its result type ([traits §4.1](../reference/traits.md#41-operations)).

So the check is the compile the box's first call needs, done once ([compiler §6.7](../reference/compiler.md#67-the-definition-time-check)). An edit of a method at a trait, with the library alone: 4.5–4.6 ms to define, 10.4 ms to the box's first call, which then infers nothing (E-440).

The C++0x obstacles do not arise:
- **Name lookup inside constrained code** is settled by dispatch on the box.
- **Calls into unconstrained code** are allowed. The rule C++0x had, "a constrained template cannot call an unconstrained one" (HOPL4 §6.2.5; `other-languages-research-2026-10-16.md` §3), is not ours. C++0x needed it because it did not know what an unconstrained template uses. Here inference reads the unconstrained code at the box's type: `sum(t)` at a box of `ColTable` reaches `iterate(::Dynamic{ColTable})`, which has no method, and the report names `iterate`, reached from `sum`. At a box of `Iterable{Float64}` the same call is bounded. A call left to run time that finds a method when it runs is Julia's function barrier, no fault.
- **Implicit conversions** happen on declared concrete result types.

**The two objections that ended C++0x's definition checking** ([P0557](https://www.stroustrup.com/good_concepts.pdf) §8.2) therefore do not bind:
- **Gradual adoption** ("a library with the concepts cannot use an older library before that library has been modernized"): trait code calls the older library directly. A library adopts traits one function at a time, because a type's own supertypes come first in dispatch ([traits §6.2](../reference/traits.md#62-specificity)).
- **Scaffolding** ("we would be unable to insert debug aids, logging code, telemetry code … without affecting its interface"): logging is a plain call on ordinary values, such as the results of operations. A box prints as itself, `Dynamic{Shape}(Circle(1.0))` ([traits §15](../reference/traits.md#15-printing)). Adding a log line changes no bound.

The design restricts no call from trait code: the facts rule keeps caches valid without it (section 9). The layering that once held C++0x's rule, and what replaced it: [`alternatives.md`](alternatives.md#layering-and-its-workarounds-interface-packages-trait-wrappers-calls-upward-doors-replaced-by-the-facts-rule).

**The cost at an edit.** The check runs at each definition. An edit of TraitTables' `summarize` is defined in 0.235 s the first time and in 9.3 ms the second, against 70.5 ms and 6.7 ms for the plain twin (E-512; [GT-12](../open-issues.md#gt-12-the-definition-time-check-runs-at-each-edit)). The gain is errors at the library's build, independent of members, not latency.

<a id="5-who-may-implement-ownership-and-stakeholders"></a>

## 5. Who may declare a membership: ownership and stakeholders

**The choice** ([facts §1](../reference/facts.md#1-terms), [traits §12](../reference/traits.md#12-ownership-pirates-strict-mode)).
- A method's **stakeholders** are the owner of its function and the owners of every type in its own signature, a `Union`'s members taken one by one. Anyone else's method is a **pirate**: Julia's "type piracy", as Aqua.jl checks it, made strict for unions ([facts §1](../reference/facts.md#term-stakeholder)).
- **A membership behaves as a method does.** It is declared by the trait's owner or the type's owner; one by neither is a pirate's ([traits §12.1](../reference/traits.md#121-who-may-declare-a-membership), [§12.2](../reference/traits.md#122-pirates)).
- **A pirate's membership is followed,** with a warning that names the owners, and the code that relied on its absence is compiled again. Strict mode refuses it where it would change code compiled by facts ([traits §12.3](../reference/traits.md#123-strict-mode)).
- **Ownership is never claimed.** A package extension belongs to its parent. A membership in an extension names each of the extension's triggers, so whether a type is a member does not depend on which packages happen to be loaded ([traits §12.1](../reference/traits.md#121-who-may-declare-a-membership)).
- **Owner-only functions.** A function of a trait module that the module neither exports nor declares `public` takes methods from its owner only; another's method of it is a pirate's, whatever types it names ([facts §1](../reference/facts.md#term-owner-only), [traits §12.2](../reference/traits.md#122-pirates)).
- **A trait module refuses a pirate of its own** at its definition (`no_pirates`, on by `@trait_module`; [traits §13](../reference/traits.md#13-scopes-trait-modules)). Elsewhere nothing is sealed, and no pirate is refused by default.
- **Named implementations,** which anyone could write, are Planned ([traits §17](../reference/traits.md#17-named-implementations)).

**The others** (`other-languages-research-2026-10-16.md` §4):
- **Rust.** The orphan rule is the same idea for single dispatch: "either the trait must be local or the self-type must be local" ([Matsakis 2015](https://smallcultfollowing.com/babysteps/blog/2015/01/14/little-orphan-impls/)).
  - *Its reasons:* the "hashtable problem" (a value built with one `Hash` impl and queried with another), that any two crates must combine, and semver.
  - *Its pain:* newtype boilerplate; adapter impls with "no obvious home" ([RFC 2451](https://rust-lang.github.io/rfcs/2451-re-rebalancing-coherence.html)); "a kind of chilling effect", with Matsakis concluding the rule "will have to be weakened" ([2022](https://smallcultfollowing.com/babysteps/blog/2022/04/17/coherence-and-crate-level-where-clauses/)); a crate is compilation unit, optimization boundary and coherence boundary at once.
  - Named impls are being proposed ([BoxyUwU 2026](https://www.boxyuwu.blog/posts/an-incoherent-rust/)).
- **Swift** allows retroactive conformances, and its ABI lead regrets it: "Swift should never have allowed arbitrary retroactive conformances" ([Rose 2021](https://belkadan.com/blog/2021/11/Swift-Regret-Retroactive-Conformances/)). His preferred options are owner-only conformances, wrapper types, or named conformances. Since Swift 6 a retroactive conformance warns, and which of two wins "is indeterminate" ([SE-0364](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0364-retroactive-conformance-warning.md)).
- **Mojo** has no extensions yet; its draft proposes an orphan-like rule.
- **Julia** has the rule as a convention: piracy is discouraged, and Aqua.jl checks it.

**How ours compares.**
- **Rose's first option, owner-only conformances, is ours.** His second, wrapper types, is the planned named implementation's form (`Via{Fast}(x)`, a newtype).
- **A pirate's membership is treated as Swift 6 treats a retroactive conformance, a warning, and not as Rust treats an orphan impl, a refusal.** The difference from Swift: a membership is global, as a method is, so "which of two wins" never arises.
- **Rust's hashtable problem cannot arise:** a membership is in the method table's world, and a value meets the same memberships wherever it goes. A type has one instance of a trait ([traits §3.2](../reference/traits.md#32-parameters)).
- **The rule is the orphan rule generalized to multiple dispatch,** and it is used for a different purpose: Lemma O says only a stakeholder or a pirate can change a fact, so ownership says who can invalidate compiled code ([the rationale §2.1](../design.md#21-step-1-fully-typed-code-is-already-invalidated-only-by-stakeholders-and-pirates)).
- **It is enforced only where it matters.** Rust refuses every orphan impl at compile time. Strict mode refuses a pirate only where it would change code compiled by facts. How many of an environment's methods it would refuse is not measured on this implementation.
- **The package boundary is not the optimization boundary,** unlike Rust's crate.
- **Split packages** name each other as joint owners, `@joint_owners DiffEqBase OrdinaryDiffEqCore` ([traits §12.1](../reference/traits.md#121-who-may-declare-a-membership)). That answers Rust's complaint that splitting a crate for build speed triggers orphan errors.

**Overlap and specialization** (`other-languages-research-2026-10-16.md` §5):
- **Rust.** Specialization ([RFC 1210](https://rust-lang.github.io/rfcs/1210-impl-specialization.html)) has been unstable since 2016, because type checking and code generation could pick different impls once lifetimes were erased ([Turon 2017](https://aturon.github.io/blog/2017/07/08/lifetime-dispatch/)). Turon's fix: a more specific impl must not change associated types. Rust made adding a blanket impl a breaking change.
- **Ours:**
  - Julia has no lifetimes. Its analogue, inference and dispatch disagreeing, is settled by the facts rule: a fact is invalidated exactly when dispatch at its signature changes.
  - **One instance per member** ([traits §3.2](../reference/traits.md#32-parameters)). A type that reaches a trait by several paths gets the same parameter values on each, or the declaration is refused. An equation in a trait always holds (`T = eltype(Self)`); a stated value is checked against it and never replaces it ([traits §5.7](../reference/traits.md#57-stating-parameters), [§5.8](../reference/traits.md#58-families)). That is Turon's fix: no membership overrides an associated type the trait defines.
  - **More specific beats generic,** as in Julia, with a type's own supertypes before a trait ([traits §6.2](../reference/traits.md#62-specificity)).
  - **An unordered overlap is Julia's ambiguity,** reported at the membership that creates it, with the joint method to define. That holds in either order: a trait owner's later generic membership is reported as a downstream type's later one is. Under strict mode it is an error ([traits §6.3](../reference/traits.md#63-ambiguity); [compiler §5.4](../reference/compiler.md#54-the-ambiguity-report-at-a-membership)).

**Costs to expect:**
- newtypes for the foreign-trait, foreign-type case, until named implementations;
- the social cost of asking owners for memberships;
- pressure for convenience, as Swift kept retroactive conformance behind `@retroactive`.

<a id="6-static-and-dynamic-positions-and-their-defaults"></a>

## 6. Erasing and code per type: the box and the wrapper

**The choice** ([traits §7.4 to §7.8](../reference/traits.md#74-the-two-kept-forms-the-box-and-the-wrapper)).
- **A member is passed as itself or in one of two kept forms,** both concrete types and members of the trait: the box `Dynamic{X}(x)`, whose code is compiled once per trait instance, and the wrapper `compiled_for(x)`, whose code is compiled for the object's type. As in Rust and Swift, the value's type decides: the choice is in the value's type, and travels with it.
- **A trait may erase by default** (`@default_dynamic`): a method at it takes a plain member boxed, by a forwarder Julia makes where the method is defined, and a kept form as it is ([traits §7.8](../reference/traits.md#78-erasing-by-default-the-forwarder)). `Callable` erases by default, so a function from plain code is boxed. A caller who wants code per type passes the wrapper.
- **Storage keeps the form given.** A field or container typed by the trait holds each form by its own type; one typed `Dynamic{X}` boxes what is stored; a struct parameter bounded by the trait records the form in the struct's type ([traits §8](../reference/traits.md#8-storage)). Rust and Swift store a value at an abstract type only behind a table (`Box<dyn P>`, `any P`); here the box is that table's place, and the wrapper the generic's.

**Defaults in other languages** (`other-languages-research-2026-10-16.md` §7):

| Language | Generic code over types | Function arguments | The other mode |
|---|---|---|---|
| C++ | compiled per type | per function type; `std::function` dynamic | `virtual`, type erasure, explicit |
| Rust | compiled per type | `impl Fn` per closure; `&dyn Fn` dynamic | `dyn Trait`, explicit, in the callee's signature |
| Swift | compiled once, witness tables; specialization an optimization | indirect unless inlined | `@inlinable`, cross-module optimization, `@specialized` |
| Mojo | compiled per type | compiled per closure type | none inside Mojo |
| Julia today | compiled per concrete type | compiled per function type if called in the body | `@nospecialize`, `Any` fields, FunctionWrappers |
| Ours | per type; once per trait instance for a box | boxed by default (`Callable` erases); the caller passes the wrapper | the box `Dynamic{X}(x)`, a trait that erases by default |

**Why.**
- **The value's type decides, as in Rust and Swift.** Julia compiles every call for the argument's type at run time, a function barrier at every call. Here the box and the wrapper are types too, so the choice is a value's, kept by storage and passed by any parameter ([traits §7.5](../reference/traits.md#75-what-decides)).
- **Functions boxed by default.** That is what Swift chose by design and Rust's practitioners recommend by experience ("prefer `&dyn Fn()` over `impl Fn()`", [matklad](https://matklad.github.io/2021/09/04/fast-rust-builds.html)): compiling per closure costs much and rarely pays. Unlike Rust, the caller can pass the wrapper, so the choice does not leak into the library's API.
- **Both forms stay.** An ODE right-hand side needs code compiled for the function with a declared, checked signature, which Julia's type system cannot express otherwise: `compiled_for(lorenz!)` at a `Callable{A, S}` argument ([traits §9](../reference/traits.md#9-functions-callable)).
- **Code per type is the default for a trait that does not erase.** Operations are direct calls, with no dictionary at run time: 0.79 ns, as plain Julia (E-443).
- **Erasing is spelled.** It follows Swift's lesson to spell the slow path where it is used, and to settle it before the ecosystem grows. A trait that erases by default costs a caller that knows the type: 8.66 ns compiled once against 2.38 ns with `compiled_for`, as plain Julia (E-513).

**How an operation on a box dispatches: a branch, then a table** ([traits §7.9](../reference/traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait); [compiler §7.2](../reference/compiler.md#72-the-split), [§7.3](../reference/compiler.md#73-the-table-of-a-calls-targets)).
- The call branches on the value's type over the first four members declared, with direct calls. This is Julia's union splitting applied to a trait's members.
- Any other member is called through a table of the call's targets keyed by the value's type. Rust's `dyn` and Swift's `any` carry their table with the value; ours is reached through the type in the object's header, as C++'s and the JVM's vtables are.
- Both dispatch in the caller's world, as every Julia call does: the table's pointers run there ([compiler §8.1](../reference/compiler.md#81-the-cfunction-calling-convention-caller_world)). Candidates are read without an edge, so a new member reaches the table and invalidates nothing ([facts §9](../reference/facts.md#9-operations-on-a-value-typed-by-its-trait)).
- Measured (E-443): a box of the first member, a branch, 5.56 ns; of the sixth, through the table's pointer, 9.14 ns; Julia's dynamic call of a value held as `Any` 18.4 ns; with the type known 0.79 ns.
- **The cost against Rust's and Swift's table:** which four are branched on, the probe by type, and a pointer per member made in each session. Section 11.

**Dynamic compatibility.** Rust restricts `dyn Trait` to traits without generic methods, `Self` results or `async fn`, because a vtable holds one entry per method. Here the box dispatches on the held object when the call runs, through a table per call signature, so an operation with `where` variables fixed by its arguments works on a box as on a member ([traits §4.1](../reference/traits.md#41-operations)). A result like the input is `like(t, x)`, which on a box gives a box of the same trait ([traits §6.5](../reference/traits.md#65-results)).

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
- **Ours stays out of most of that space** ([traits §3.2](../reference/traits.md#32-parameters)).
  - A trait's parameters are associated types, one value per member, as Rust's [RFC 195](https://rust-lang.github.io/rfcs/0195-associated-items.html) argued. A parameter is defined by a field's type, by an equation of `Self` (`T = eltype(Self)`), or stated at the membership.
  - Input parameters (`@input N`) are offered, as Rust's generic trait parameters are: the trait at fixed input values is a trait of its own.
  - Not offered: equations between type functions; a parameter bound that names its own trait.
  - Code is compiled for a value's concrete type, where an associated type is a field's type or a function evaluated on a concrete type.
  - Definition checking is inference at the box, with the trait's parameters given or a stand-in (section 4): no solver. Two traits linked by their parameters are linked by a method's shared `where` variables, which Julia's subtyping already handles.
- **What the design adds to Julia's own type system** is memberships in subtyping and dispatch ([compiler §4](../reference/compiler.md#4-sets-and-memberships)). Its cost to code that uses no trait: a non-member's `<:` against a trait takes 1.7–1.8× an unrelated pair's on vanilla (E-270; [GT-9](../open-issues.md#gt-9-the-membership-machinery-costs-code-that-uses-no-trait)).

## 8. Error messages

**Where unreadable errors come from.** Three ingredients, all needed ([the rationale §2.7](../design.md#27-the-argument-and-the-goals); [the problem in plain Julia](evidence.md#the-problem-in-plain-julia), E-5):
1. **The failure is detected deep inside the library,** because the library never states what it requires.
2. **The whole path is printed:** 22–44 frames in the SciML cases.
3. **Every step is printed at its full concrete type,** because concreteness at the bottom forces the concrete type into every signature above. A SciML integrator's type is 3,553 characters.

**The others:**
- **C++20 concepts** move detection to the call and name the failed requirement. But types still print in full, incomplete constraints still fail deep inside, and in E-5 the messages with templates and with concepts both run to 28–33 lines.
- **Rust's errors are short,** except where nested types are printed; one Diesel error names a "30 page long type" ([RFC 2397](https://rust-lang.github.io/rfcs/2397-do-not-recommend.html)).
- **SciML** writes guidance messages by hand. Each states a requirement after the fact.

**Ours** ([traits §11](../reference/traits.md#11-checks-and-errors)):
- **Detection moves earlier:** to the membership (missing operations, results wider than declared, missing fields) and to the method's definition (a method that is not bounded).
- **A check's error is raised at the user's line.** The first frame is the `@implement`, or the definition the check refused; the library's frames are not above it ([traits §11.3](../reference/traits.md#113-errors-and-their-messages)). Over fifteen mistakes, 2 library frames remain, both at a use before the `@implement` (E-370).
- **A failed call names the contract:** a `MethodError` at an operation's function outside its declared signature carries the declared signature and its trait as a hint ([traits §11.4](../reference/traits.md#114-hints)).
- **Erased code prints short types:** a signature at a box prints the box's type, `colmean(::Dynamic{ColTable}, ::Int64)`, not the member's nested type ([traits §15](../reference/traits.md#15-printing)).
- **Measured against the same mistakes in plain Julia** (E-362): of thirteen mistakes, five are reported at the line that makes them, and two more by a warning at the membership; plain Julia reports four at a later call and one not at all. The messages run 2 to 5 lines, against 1 to 11.
- **The limit:** a bug in the user's code outside a contract is found at run time, as in plain Julia. On SciML's three cases the port is no better than its plain twin, and upstream's hand-written explanations say more in two of them (E-363; [the evidence, G-5](evidence.md#4d-error-messages-against-plain-julias)).

## 9. The facts rule in the compiler, and strict mode as a switch

**The facts rule in Julia's compiler** ([facts §3](../reference/facts.md#3-fact-signatures), [§5](../reference/facts.md#5-run-time-sites); [the rationale §2.3](../design.md#23-step-3-the-facts-rule-extends-the-guarantee-to-code-that-is-not-fully-typed); [`julia-changes.md`](julia-changes.md)).
- Compiled code depends on the method table only through facts. A call that is not at a fact signature is a run-time site: it dispatches when it runs and records nothing.
- **Against the others:** none of C++, Rust, Swift or Mojo caches specialized code per package with a guarantee that loads cannot change it (`other-languages-research-2026-10-16.md`, "What is new in our design" item 4).
  - C++ and Rust recompile per translation unit or crate. C++'s `export` failed because a cached instantiation's meaning depended on where it was instantiated ([N1426](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2003/n1426.pdf)).
  - Swift keeps code valid across modules by dictionary passing, and pays in performance cliffs ([SE-0460](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0460-specialized.md)).
  - Mojo has a closed world and no invalidation.
  - Ours keeps Julia's specialization and a session's open world. Code compiled by facts in the deep class is invalidated only by a stakeholder's change, or a pirate that wins at one of its facts ([facts §2.2](../reference/facts.md#22-g2-stable-caches), [§2.3](../reference/facts.md#23-two-tiers)).
- **The guarantee is the compiler's, not the traits'.** Upstream CSV and DataFrames, compiled by facts by one line per module, lose 14 of 3,490 (0.4 %) of their own image instances to nine unrelated loads; plainly compiled, 426 of 4,688 (9.1 %). The work after the loads takes 1.45–1.46 s against 5.19–5.32 s (E-511; [the evidence, G-1](evidence.md#1-the-guarantee)). So the comparison of cache validity is a comparison of the facts rule, which applies to any Julia code.
- **What traits add to it:** the facts rule costs nothing for fully typed code, and traits make code fully typed where plain Julia loses its types: code per member's type, declared results on a box and at `Callable`, and declared memberships that the branches use ([the rationale §2.4](../design.md#24-step-4-traits-say-what-code-needs-which-makes-the-facts-rule-cheap)). Where code is not fully typed, the facts rule removes Julia's heuristics, and the code pays at its run-time sites. How much over a broad benchmark suite is not measured on this implementation ([the evidence, G-4](evidence.md#g-4-downsides)). Where trait code meets such code, that is an interop cost (section 10).
- **The reach of G2 is the deep class:** code compiled by facts whose every callee, at any depth, rests on facts. Of the forks' own facts instances 63.1 % are in it, of upstream's compiled by facts 79.0 % (E-478). The rest rests on Base's plain code where types are not known ([GT-8](../open-issues.md#gt-8-g2-covers-the-deep-class-a-ports-code-outside-it-is-lost-through-plain-callees)).
- **The policy is chosen per module and per method** ([facts §6](../reference/facts.md#6-which-code-is-compiled-how); [compiler §2.1](../reference/compiler.md#21-the-module-option), [§2.2](../reference/compiler.md#22-the-method-flag)): `@compiler_options facts=true`, which `@trait_module` declares and submodules inherit; in a method, `Expr(:meta, :facts_boundary)` (compiled in the policy of the code that reaches it) or `Expr(:meta, :facts_always)`. A module's other compiler options apply under either policy.
- **A call of an owner-only function is a fact at any signature** ([facts §3](../reference/facts.md#3-fact-signatures)): only its owner, or a pirate, adds methods to it. That is Rust's position for a crate's private functions, carried to a language where any function may take methods from anyone.
- **No layering:** trait code calls any Julia code directly, which is what C++ wanted and could not have with definition checking (section 4).
- **Compiling ahead.** A `--trim` build is the facts rule with everything final: every set's members and every function's methods are known, so plain inference's assumption holds ([facts §13.3](../reference/facts.md#133-trimmed-binaries)). It does what Rust and Mojo do with a trait bound. An operation on a value known only by its trait branches over every member the program uses as one, as Rust's `dyn Column` has a table for each type the program coerces ([compiler §7.6](../reference/compiler.md#76-a-closed-build)). What traits add is the list of targets: the memberships and the `Callable` signatures ([traits §16](../reference/traits.md#16-compiling-ahead-closed-programs)). A loop over a vector typed by a trait builds under `--trim=safe` with 0 errors; its plain twin over an abstract type with 2 (E-364).

**Strict mode as a switch** ([facts §11.2](../reference/facts.md#112-strict-mode), [traits §12.3](../reference/traits.md#123-strict-mode); [the rationale §2.2](../design.md#22-step-2-refuse-the-pirates-that-would-win-and-fully-typed-code-is-never-invalidated)).
- **It applies to code compiled by facts.** The property it secures: code in the deep class is never invalidated, except by a stakeholder's change.
- It refuses a pirate, a method or a membership, where it would win at a fact of that code, where it is defined, naming the method and the code it would change. Off by default; the default follows the pirate, as plain Julia does, and reports it where it ends deep-G2 code ([traits §12.2](../reference/traits.md#122-pirates)).
- **A package extension's winning method is followed, with a warning,** as its parent's change ([facts §11.3](../reference/facts.md#113-strict-modes-errors-at-their-sources)).
- **Against the others:** it sits between Rust and Swift. Rust refuses every orphan at compile time. Swift warns and leaves the winner "indeterminate". Strict mode refuses exactly the pirate that would change protected code, and nothing else, at the moment it is defined.
- **A load-order effect the others do not have:** a pirate defined before the code it changes is compiled is in the method table, and the code selects it from the start. Strict mode reports a pirate loaded before a package image at the image's load, and `verify_main` reports the case in a session as a lint ([facts §11.3](../reference/facts.md#113-strict-modes-errors-at-their-sources)). Static languages settle coherence for the whole program at once.
- **Its scope is the deep class.** A pirate at Base's plain `uppercasefirst(::String)`, which code compiled by facts calls, is refused at the user's line (E-518). A pirate that ends only plain code outside the class is followed, as plain Julia follows it.
- **Its cost at a load:** TraitTables with TraitCSV load in 215 ms under strict mode, 153 ms without (E-516; [GT-2](../open-issues.md#gt-2-strict-mode-infers-an-images-memberships-at-its-load)). Swift's launch-time conformance scans, over 100 ms in large apps (`other-languages-research-2026-10-16.md` §4), are the warning that such checks need indexes: the membership walk finds a trait's methods through a set-to-methods index ([compiler §5.1](../reference/compiler.md#51-the-method-table)).

## 10. Calling into ordinary code

**The choice** ([facts §6](../reference/facts.md#6-which-code-is-compiled-how); [traits §7.3](../reference/traits.md#73-bounded-methods)). Trait code may call any Julia code: Base, upstream packages, code written without traits. The facts mode exists to make that call smooth and correct:
- **smooth:** no wrapper, annotation or layer; it is an ordinary Julia call;
- **correct:** the plain code it reaches keeps G1 (identical or error), and code compiled by facts keeps G2 where it is in the deep class ([facts §2](../reference/facts.md#2-the-guarantees)).

A box may be passed to plain code too. It is a value of its own type that answers its contract: plain code that asks it something outside the contract finds no method, and the definition-time check names that call (section 4). `unwrap(t)` is the object ([traits §7.4](../reference/traits.md#74-the-two-kept-forms-the-box-and-the-wrapper)).

So two cases are judged apart. **Interop** is trait code calling plain code on plain data. **Idiomatic trait code** is code written against bounds, as it would be written in Rust or Swift. A cost measured in the first case is an interop cost and is labelled so ([the rationale §2.4](../design.md#24-step-4-traits-say-what-code-needs-which-makes-the-facts-rule-cheap)).

**How the others reach code without their bounds:**
- **C++0x** forbade a constrained template to call an unconstrained one (section 4). C++20 allows it, because it checks no definitions.
- **Rust** has no untyped code to call. Its ways out of the type system:
  - C through FFI. Its declarations go in `unsafe extern` blocks, and "a function declared in an extern block is implicitly `unsafe` unless the `safe` function qualifier is present" ([the Rust reference, external blocks](https://doc.rust-lang.org/reference/items/external-blocks.html));
  - `dyn Any`, whose downcasts are checked and return an `Option` ([`std::any`](https://doc.rust-lang.org/std/any/index.html)).
- **Swift's** dynamic world is Objective-C (`other-languages-research-2026-10-16.md`, "At a glance"), reached by bridging. An `NSArray` becomes a `[T]` in one of two ways:
  - **for a class or `@objc` protocol `T`, lazily.** The `NSArray` is kept without a pass, and each element's type is checked when it is read. A mismatch traps with "NSArray element failed to match the Swift Array Element type" ([`ArrayBuffer.swift`](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/ArrayBuffer.swift), `_typeCheckSlowPath`; its comment: "NSArray's need an element typecheck when the element type isn't AnyObject"). The same deferral applies to a forced downcast of a Swift array of class elements: "the trap may be deferred to the point where an offending element is accessed" ([`docs/Arrays.md`](https://github.com/swiftlang/swift/blob/main/docs/Arrays.md); `_arrayForceCast` in [`ArrayCast.swift`](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/ArrayCast.swift)).
  - **for a bridged value type** (`String` from `NSString`, numbers from `NSNumber`), eagerly: "forced bridging back converts `[AnyObject]` to `[X]` in O(N)" ([`docs/Arrays.md`](https://github.com/swiftlang/swift/blob/main/docs/Arrays.md), a design document of the Swift repository, partly marked outdated).
- **Mojo** calls Python through `PythonObject`.

**Ours against them.** Rust and Swift meet untyped code at the edge of another language, with a conversion or a check at that edge. Ours meets it inside Julia: the ordinary code is called directly, with its own values. The price is that ordinary code compiled by facts runs under the facts rule.

**What the call costs.** These numbers measure interop, not idiomatic trait code.
- **Where types are known: nothing.** For fully typed code, facts inference is plain inference. An operation at a known type takes 0.79 ns, as plain Julia (E-443; [the evidence, G-2](evidence.md#2-run-time)).
- **Where they are not:** a call at an abstract signature is a run-time site, typed `Any` ([facts §4.2](../reference/facts.md#42-at-a-run-time-site)). The dispatch itself costs what plain Julia's costs. What is lost is the inlining of one-method callees declared at `Any`, and the types after the call: the `Any` cascades through the results. What this costs trait code that calls Base's generic algorithms on containers of `Any` is not measured on this implementation.
- **Upstream code compiled by facts, with no trait code** (E-511: CSV and DataFrames, one line per module, against plain code on the build). It measures the facts mode on ordinary code, which is what trait code meets when it calls into it.
  - First work: 1.75–1.83 s by facts, 4.45–4.46 s plainly.
  - After nine unrelated loads: 1.45–1.46 s by facts, 5.19–5.32 s plainly.

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

**Ours: the bound on the items, and storage that keeps each member's form** ([traits §8.1](../reference/traits.md#81-fields-and-containers-typed-by-a-trait), [§10.2](../reference/traits.md#102-element-types)).
- **Code states the bound on the items:** `total(shapes::Iterable{<:Shape})`. It takes a `Vector{Circle}`, a `Vector{Shape}`, a `Vector{Dynamic{Shape}}` and a `Vector{Union{Circle, Square}}` as they are, with no copy, and the caller's vector stays the one that is read and written. This is Rust's and Swift's lazy shape: the code states the bound, and the producer keeps its representation.
- **A container typed by the trait** (`Vector{Shape}`) holds each member's own value. An operation on an item takes the branch over the first four members, with a declared result, not a call at `Any`. A `Vector{Dynamic{Shape}}` holds each item boxed, and code over it is fully typed.
- **Measured** (E-513): an element of a `Vector{Shape}` with two member types, 2.86–2.87 ns; of a `Vector` of the abstract type, 2.70 ns; of the union, 3.19 ns.
- **A `Vector{Any}` is not an `Iterable{<:Shape}`.** It is converted first, `convert(Vector{Shape}, v)`, which checks each item and raises at the first that is no member. That is Rust's and Swift's eager conversion, and it loses aliasing, which Rust's conversion (it consumes or borrows the original) and Swift's value arrays rule out, and Julia's shared arrays do not.
- **A view without a copy** needs a view type, as Swift's bridged `NSArray` is one: Julia has no borrowed reference into an array's element ([traits §8.1](../reference/traits.md#81-fields-and-containers-typed-by-a-trait)). The references build none.
- **An array literal's element type is Julia's join,** which reads declared supertypes only: `[Circle(1.0), Square(2.0)]` is a `Vector{Any}` where both joined by `@implement` alone, and a `Vector{Shape}` where both are defined `<: Shape` ([traits §10.2](../reference/traits.md#102-element-types)).

**The dynamic call: a branch, then a table.**
- **Rust's `dyn` and Swift's existentials call through a table of the type's methods**, a vtable or a witness table, carried with the value. Every implementation costs the same indirect call. There is no limit on their number, and no dependence on order.
- **Ours branches at the call site** over the first four members declared, with direct calls, and calls any other member through a table keyed by the value's type (section 6; [compiler §7.2](../reference/compiler.md#72-the-split), [§7.3](../reference/compiler.md#73-the-table-of-a-calls-targets)).
  - **Which four:** the first four declared, by file and line. A trait's package declares its common members first ([traits §7.9](../reference/traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait)).
  - **A branch is inlined only where its body is a leaf;** every other branch calls its member's target through a pointer made when the caller is compiled. So an invalidation below a member's operation stops at the member.
  - **Beyond the four:** one lookup and one indirect call, 9.14 ns for the sixth member against 5.56 ns for the first (E-443).
  - **The pointers are made per member in each session:** 18 ms a session for the pointers of a member's two operations (E-375; [GT-7](../open-issues.md#gt-7-the-splits-pointer-per-call-and-its-making-per-member-in-each-session)). Swift emits its witness tables with the conformance, statically; GT-7's proposal is to make them at a member's image build.
  - Rust and Swift inline none through `dyn` or `any`, unless the compiler proves the type.
- **Optional:** a witness carried with the value, Rust's and Swift's form, and recompiling with the observed types ([compiler §8.3](../reference/compiler.md#83-further-work)).

<a id="12-compiled-code-kept-across-builds-fingerprints-of-what-it-used"></a>

## 12. Compiled code kept across sessions: what a stored entry rests on

How other compilers decide that code compiled earlier is still valid, against the store across sessions that the design leaves Optional ([facts §12](../reference/facts.md#12-package-images); [compiler §9](../reference/compiler.md#9-images-and-the-machine-code-cache)). No cache across sessions is built. The sources are in [the research record](../record/incremental-precedents-research-2026-10-27.md).

- **GHC** records, in each interface file, the entities a module used and their fingerprints, and recompiles only when one changed. A function's body enters its fingerprint only when exposed for inlining. A non-orphan instance is hashed with its class or its type; orphan modules are listed apart. Across packages it tracks the module's ABI hash.
- **rustc** fingerprints each query's result and cuts off early (the red-green algorithm). Across crates, queries depend on the crate's hash (SVH), and early cutoff on each upstream item read recovers the grain.
- **Swift** tracks per-declaration dependencies with type-body fingerprints. **Salsa** backdates unchanged results and classes inputs by durability. **Unison** names definitions by their hash. **Nix** (content-addressed derivations) and **Bazel** cut off on identical outputs.
- **Julia** keys a package image by the build ids of its dependencies, transitively, and checks dispatch per edge at load.
- **Here:**
  - a stored entry would be used when its edges verify in the session, by Julia's own validation of loaded code, and its content is the same: the lowered code of its method and of each method its code edges name, the layouts it reads, the values it embeds;
  - the record names its targets by identities stable across sessions: a method by module path, name, signature and a digest of its lowered code; a type by path and layout; a membership by member, trait and declarer;
  - what facts add: a fact is a dispatch at a concrete signature, so the usages are exact rather than approximated by names, and its stakeholders bound who can change it ([facts §2.2](../reference/facts.md#22-g2-stable-caches)). GHC's instance hashing with class or type, and its orphan list, are the nearest precedent for that bound.
- **What a store would serve** is measured, not built: a membership declared in the session, 139 to 144 ms; the pointers of code compiled once, 18 ms (E-375; [the evidence, Not shown](evidence.md#not-shown)).

## What the choices cost

The design restricts what trait code may do, and only there. Each tension between the goals is in [the open issues §2](../open-issues.md#2-tensions-between-the-goals), with its cost in [the evidence](evidence.md#what-each-tension-costs).

1. **Code that is not fully typed pays the facts rule** ([facts §14](../reference/facts.md#14-what-the-facts-mode-does-not-promise); [the rationale §2.3](../design.md#23-step-3-the-facts-rule-extends-the-guarantee-to-code-that-is-not-fully-typed)). In code compiled by facts, Julia's speculation over abstract calls is gone: such a call is a run-time site with result `Any`. The principle: a slowdown is tolerated if redesigning the code with traits recovers it. Where trait code calls plain code on plain data, this is an interop cost (section 10).
2. **A kept form is not the object** ([traits §7.4](../reference/traits.md#74-the-two-kept-forms-the-box-and-the-wrapper)).
   - `typeof(t)`, `t === x` and `t isa Circle` answer for the kept form; `unwrap(t)` is the object.
   - In a method at a trait that erases by default, the argument is always a kept form ([traits §7.8](../reference/traits.md#78-erasing-by-default-the-forwarder)).
   - A wrapper can meet an ambiguity that a box does not: a function with methods at two unrelated traits of its object.
3. **Erased code sees only the contract.**
   - A box is a member of its trait and its supertraits only. A function outside the contract with a method at the object's own type is reached through `unwrap(t)` ([traits §7.7](../reference/traits.md#77-dynamicx)).
   - A box that entered through a supertrait stays at its methods: erased code can be slower by algorithm, not only by dispatch. That is Siek's `merge`/`copy` case of C++0x (prediction 10).
   - A type whose data needs computing is converted explicitly, at the cost of a copy and no write-through ([traits §5.12](../reference/traits.md#512-types-that-only-convert)).
4. **Types come first.** A type caught by a method at its own supertype takes it, even when it also is a member of a trait of the same function ([traits §6.2](../reference/traits.md#62-specificity)). Reaching the method at the trait needs a type no type method catches, or a newtype.
5. **Base's types are members only where declared.** BaseTraits declares Base's abstract types as members, `@implement Indexable{T} AbstractVector{T} where {T}`. A `Number` iterates in Base and is not `Iterable`; a string is `Iterable` and not `HasLength` ([traits §10.1](../reference/traits.md#101-basetraits)).
6. **Erased positions are indirect** ([the evidence, G-2](evidence.md#2-run-time)).
   - A `Callable` called through the box: 25.19–25.31 ns, against 0.79 ns for the wrapper and for a plain argument (E-513).
   - An operation on a box: 5.56 ns for a member among the first four, 9.14 ns through the table, against 0.79 ns with the type known (E-443).
   - A trait that erases by default, at a member the caller knows: 8.66 ns compiled once, 2.38 ns with `compiled_for`, as plain Julia (E-513).
7. **Each new member type compiles the library's methods for it,** in the image of the package that declares the membership ([traits §16](../reference/traits.md#16-compiling-ahead-closed-programs)).
   - A membership declared in a session: 139 to 144 ms (E-375).
   - At the table's prompt, a new cell type 523 ms and a new column struct 145 ms; the plain twin 535 ms and 144 ms (E-512).
   - A member's image on a real library: a column member 42 instances, 127,640 bytes; the plain twin's column 146 instances, 266,448 bytes (E-380).
8. **The design needs a changed Julia** ([`julia-changes.md`](julia-changes.md)). It costs code that uses no trait ([GT-9](../open-issues.md#gt-9-the-membership-machinery-costs-code-that-uses-no-trait)): plain code's repeated work 0.18–0.19 ms against vanilla's 0.18 ms; its first work 3.316–3.342 s against 3.252–3.281 s (E-515). The library loads in 58.7–60.5 ms (E-516).
9. **Overrides are fixed at the membership** ([traits §5.11](../reference/traits.md#511-overrides-and-redeclaration)). A later method that would take a call a default serves is refused; redeclaring the membership replaces it. A later method that would break a member's checked result is refused too ([traits §5.10](../reference/traits.md#510-checks)). Plain Julia would follow the method.
10. **Smaller restrictions.**
    - One semantic exception: values Julia decides by inference ([facts §2.1](../reference/facts.md#21-g1-identical-or-error)).
    - The orphan case: a foreign trait for a foreign type needs an owner, a joint owner, or a newtype, until named implementations.
    - A membership is seen from the world of its declaration, as a method is: code running in an older world does not see it ([GT-14](../open-issues.md#gt-14-a-membership-is-seen-from-the-world-of-its-declaration)).
    - A callable struct that is no `Function` is a `Callable` only by its owner's declaration ([GT-32](../open-issues.md#gt-32-a-callable-struct-that-is-no-function-is-no-member-of-callable-until-its-owner-declares-it)).
11. **Heterogeneous data from plain code:** a `Vector{Any}` passed where items are bounded by a trait is converted with a copy, which loses aliasing; a view without a copy needs a view type (section 11).

## Other options considered

The options considered and not taken, with the reason for each, are on [the alternatives page](alternatives.md). Those this chapter's comparisons touch:
- [representations and projections, replaced by keys](alternatives.md#representations-and-projections-replaced-by-keys), and [keys in the language's core, moved to the optional extensions](alternatives.md#keys-in-the-languages-core-moved-to-the-optional-extensions-2026-11-15);
- [layering and its workarounds, replaced by the facts rule](alternatives.md#layering-and-its-workarounds-interface-packages-trait-wrappers-calls-upward-doors-replaced-by-the-facts-rule), and [sealing](alternatives.md#sealing-rejected);
- [an attribute at each call, replaced by one way to erase](alternatives.md#one-way-to-erase-the-attribute-replaced-2026-11-15);
- [`Callable` by its methods, replaced by a contract checked at the box](alternatives.md#callable-by-its-methods-replaced-2026-11-15);
- [a membership that invalidates nothing, replaced by a membership that behaves as a method](alternatives.md#a-membership-invalidates-nothing-replaced-2026-11-11);
- [pointer tables and witness tables for dynamic values, replaced by the branch and the table](alternatives.md#dynamic-values-pointer-tables-and-witness-tables-replaced-by-the-call-site-split);
- [strict mode's variants](alternatives.md#strict-mode-variants-not-chosen);
- [caches across sessions](alternatives.md#caches-across-sessions-combination-caches-and-view-caches-removed), and [validity by fingerprints of the stakeholders' methods](alternatives.md#validity-of-a-stored-entry-by-fingerprints-of-the-stakeholders-methods-and-a-candidate-index-replaced).

## Predictions from other languages, and their status

The predictions are those of `other-languages-research-2026-10-16.md`, "What their experience predicts for us". Each status is the design of the references, with today's evidence and [open issues](../open-issues.md).

| # | Prediction | Source | Status |
|---|---|---|---|
| 1 | "Explicit conformance is viral" | C++0x | **answered in the design, not tested at scale:** the one-line `@implement`, families, abstract types as members. Every port is the project's own ([the evidence, G-7](evidence.md#g-7-transition)). Where it shows: 134 of 174 callable types in the forks' session are no `Function`, and need their owner's declaration to be a `Callable` (E-500; GT-32) |
| 2 | Layering attacked for gradual adoption and scaffolding | C++0x | **dissolved:** there is no layering; trait code calls any Julia code, and a type's own supertypes first in dispatch let a library adopt traits one function at a time (section 4) |
| 3 | A `late_check`-like inconsistency where values cross upward | C++0x | **bounded:** a kept form is a value of its own type, the same wherever it goes. It differs from its object only where code asks what only the object can answer (`typeof`, `===`, a function outside the contract); the definition-time check names such a call at a box (section 4; [traits §7.4](../reference/traits.md#74-the-two-kept-forms-the-box-and-the-wrapper)) |
| 4 | Pressure for retroactive conformance | Swift, Rust | **open, and seen:** named implementations Planned ([traits §17](../reference/traits.md#17-named-implementations)); until then a newtype, or a pirate's membership, followed with a warning. A plain package's callable object is the first case ([open issues §4](../open-issues.md#4-design), item 227) |
| 5 | A later generic implementation overlapping a specific one | Rust | **answered and built:** an unordered overlap is Julia's ambiguity, reported at the membership that creates it in either order; an error under strict mode ([traits §6.3](../reference/traits.md#63-ambiguity)) |
| 6 | A more specific implementation changing types | Rust | **answered and built:** one instance per member; an equation always holds, and a stated value is checked against it ([traits §3.2](../reference/traits.md#32-parameters)) |
| 7 | Load-time checks scanning all methods | Swift | **measured:** strict mode at a load, TraitTables with TraitCSV 215 ms against 153 ms without (E-516; GT-2), because the implementation infers every membership's check again at the load (traits T-129). The membership walk reads a set-to-methods index |
| 8 | Demand for a storable dynamic value | Swift, Rust | **answered and built:** `Dynamic{X}`, a member of `X`; a field or container typed by the trait holds any member. An operation on it: 5.56 ns within the first four members, 9.14 ns past them, against 18.4 ns for Julia's dynamic call of a value held as `Any` (E-443) |
| 9 | Shared code not inlined across packages | Rust | **confirmed for code compiled once:** a branch of the split inlines its member's method only where the body is a leaf, and calls through a pointer otherwise ([compiler §7.2](../reference/compiler.md#72-the-split); GT-7). Code per type, a plain member's or a wrapper's, calls directly; where it is compiled is the image of the package that declares the membership |
| 10 | Early binding misses a more specific method | C++0x | **dissolved for methods:** a stakeholder's later method breaks the fact and recompiles, as in plain Julia. **Kept in two cases:** an override of a default after the membership is refused ([traits §5.11](../reference/traits.md#511-overrides-and-redeclaration)); a box runs the methods at the trait it was erased at, not a subtrait's, Siek's `merge`/`copy` case (cost 3) |
| 11 | Implicit defaults added later break things | Swift | **chosen per trait, in its declaration:** concreteness is opt-in per trait and per method ([traits §14](../reference/traits.md#14-concreteness-and-fully-typed-mode)); erasing by default is opt-in per trait, `@default_dynamic`, and changes speed, never a result ([traits §4.6](../reference/traits.md#46-erasing-by-default)). Adding either to a published trait changes its members' code: not tested |
| 12 | Type-level computation in traits | all four | **kept out:** associated types in first-order form, input parameters, no equations between type functions; definition checking is inference at the box, with no solver (section 7) |
| 13 | Dictionary or witness dispatch for dynamic values | Swift, Rust | **in Julia's form:** behind the branches, a table of the call's targets keyed by the value's type, whose pointers run in the caller's world ([compiler §7.3](../reference/compiler.md#73-the-table-of-a-calls-targets), [§8.1](../reference/compiler.md#81-the-cfunction-calling-convention-caller_world)). A witness carried with the value is Optional ([compiler §8.3](../reference/compiler.md#83-further-work)), and GT-7 proposes it |
| 14 | A collection of mixed types is converted where it is made, or seen through a lazy adaptor | Rust, Swift | **partly answered:** code bounded on the items takes every container whose element type is under the trait as it is, as Rust's and Swift's lazy adaptors do. A `Vector{Any}` is converted with a copy, which loses aliasing; a view needs a view type, not built (section 11) |

Rows 13 and 14 are not predictions of `other-languages-research-2026-10-16.md`. Row 13 is the other languages' standard mechanism ([`alternatives.md`](alternatives.md#dynamic-values-pointer-tables-and-witness-tables-replaced-by-the-call-site-split)). Row 14 is their idiom for heterogeneous data (section 11).

**Each trade-off, and what the others chose and paid:**

| The design's trade-off | What the others chose, and what it cost them |
|---|---|
| Memberships declared, not inferred (section 2) | C++20 chose structural matching and lives with "satisfied but not modeled", no diagnostic required; Mojo added structural conformance and removed it a year later |
| Generic code checked at its definition, at the box (section 4) | C++0x checked at archetypes and lost concepts over a tenfold slower compiler and 91 pages; Rust and Swift check at definition and pay in a solver (Rust's rewrite since 2023, Swift's undecidable signatures) |
| The value's type decides: the box or the wrapper (sections 3, 6) | Rust makes the callee choose `dyn` or `impl` in its signature, and the choice leaks into APIs; Swift compiles generic code once by default and pays in performance cliffs, up to "about 2 orders of magnitude" unspecialized |
| `Callable` erases by default; the caller passes the wrapper (section 6) | Swift calls functions indirectly unless inlined; Rust's practitioners recommend `&dyn Fn` for build times, at the cost of a fixed choice in the library's API |
| A branch over four members, then a table (sections 6, 11) | Rust and Swift carry a vtable or witness table with every value: one indirect call for every implementation, no inlining through `dyn` or `any`, no dependence on declaration order |
| Ownership: a stakeholder declares; a pirate is followed, or refused in strict mode (sections 5, 9) | Rust refuses every orphan and pays in newtypes and adapter crates with "no obvious home"; Swift allowed retroactive conformances and its ABI lead regrets it, with a warning and an indeterminate winner since Swift 6 |
| The facts rule: code kept through loads, in an open world (section 9) | C++'s `export` failed on context-dependent meaning; Rust recompiles per crate; Swift keeps code valid by dictionary passing and pays in cliffs; Mojo closes the world |
| Associated types in first-order form (section 7) | Rust's generic associated types took 6.5 years; Swift's recursive constraints made signatures undecidable; Mojo avoided inference from result types by design |
| Heterogeneous data bounded on items, a `Vector{Any}` copied (section 11) | Rust and Swift convert where the collection is built, with no loss of aliasing (borrows, value arrays), or read through a lazy adaptor |
| Compiling ahead lists the members a program uses (section 9) | Rust and Mojo compile per type for the whole program; Swift's Embedded mode needs full specialization and emits metadata only for types placed in an existential |
