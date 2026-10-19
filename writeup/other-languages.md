# Our design among C++, Rust, Swift and Mojo

> **Research of its date.** This page records what the research found on 2026-10-16. Its findings about C++, Rust, Swift and Mojo stand. Its statements about our design (the "Ours" column, "What is new in our design", the "What to do" column) describe the design of that date: representations and projections, layering, wrappers, rule 4. The current comparison is [`design/comparison.md`](design/comparison.md), which checks every prediction against the design of today; what changed, and why, is in [`design/alternatives.md`](design/alternatives.md). The page says "conformance" where the current documents say "implementation".

Research of 2026-10-16 (session 22). Four research agents read primary sources:
- **C++:** Stroustrup's HOPL papers, WG21 papers, the 2009 decision to remove concepts.
- **Rust:** RFCs, Matsakis' and matklad's posts, rustc pull requests.
- **Swift:** Evolution proposals, the Generics Manifesto, LLVM talks, forum threads.
- **Mojo:** changelogs, proposals and compiler docs in modular/modular, Lattner's interviews.

Every link below was opened by an agent. Claims marked *(uncertain)* rest on a secondary source or could not be checked.

**In one paragraph.** Every decision our design makes has been made, and often regretted, somewhere else:
- Declared conformance won in all four languages; C++ is the exception and the cautionary tale.
- Checking generic code when it is defined is standard in Rust, Swift and Mojo. C++ tried it, gave up, and now believes it can never add it.
- An ownership rule is Rust's orphan rule. Swift's lead ABI designer says Swift should have had one.
- Our layering rule is, word for word, the C++0x rule that helped kill definition checking. The objections that killed it are ones we answer with wrappers and calls upward.
- Where compiled generic code lives is the question C++ "export" failed on. Rust and Swift answered it opposite ways and both pay for it.

Three things in our design have no counterpart in these languages:
1. Projection onto a representation as an enforced position. The others leave it to convention.
2. A static-or-dynamic choice that the caller can override.
3. Dispatch checked against ownership at run time in a language that compiles at run time.

The biggest gap the others predict for us is a storable dynamic value. All of them except Mojo have one, and Mojo has it on its roadmap.

## At a glance

| Decision | C++ | Rust | Swift | Mojo | Ours |
|---|---|---|---|---|---|
| Conformance | structural (C++20 concepts); C++0x had declared concept maps, then dropped them | declared `impl` | declared, global, retroactive allowed | declared (structural added 2024, removed 2025) | declared `@implement`, never derived from methods |
| Generic code checked | at instantiation only | at definition, against bounds | at definition | before instantiation | on each worker's typed code, against the bounds |
| Code generated | per type (templates) | per type (monomorphization) | once, dictionary passing; specialization as optimization | per type, whole program | per representation; per type only by choice |
| Dynamic position | virtual functions, type erasure (`std::function`) | `dyn Trait` (callee chooses) | `any P`, existentials | none (on the roadmap) | dynamic operations, dynamic call (per conformance; caller overrides) |
| Storable dynamic value | yes | `Box<dyn Trait>` | `any P` | `Variant`, `PythonObject` | no |
| Who may add a conformance | anyone (structural) | owner of trait or type (orphan rule) | anyone (retroactive), warned since 6.0 | the struct's author; extensions proposed | owner, or a delegate the owner names (rule 3) |
| Overlap | partial specialization | specialization unstable since 2016 | overlapping conformances banned | — | more specific beats generic, a chain; unordered overlap rejected |
| Where compiled generic code lives | every translation unit; `export` removed | the instantiating crate, duplicated per crate | the library (unspecialized), or the client via `@inlinable` | the final program | the image of the package that chose the type (rule 4) |
| Dynamic world | — | — | Objective-C runtime | Python (CPython) via `PythonObject` | dynamic Julia, above the trait world |

## 1. Conformance: declared or structural

**C++.** This was the central fight of the C++0x concepts effort:
- **Indiana (Gregor, Siek, Lumsdaine)** wanted declared concept maps. Their 2006 paper gives `istream_iterator` as the example: it structurally satisfies Forward Iterator, so the faster two-pass algorithm is chosen, and it fails at run time. ([Gregor et al. 2006](https://www.cs.kent.edu/~jmaletic/cs69995-PC/papers/gregor-06.pdf))
- **Texas A&M (Stroustrup, Dos Reis)** wanted implicit matching. Stroustrup's arguments: "'Accidental match' is a minor problem / Not in the top 100 problems". Explicit concept maps were turning into "an essential function by some people, rather than an unfortunate rare necessity". Library writers "push resolution of even the most obvious choices onto their users". ([N2906](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2009/n2906.pdf); [Dr. Dobb's 2009, mirror](https://jacobfilipp.com/DrDobbs/articles/DDJ/2009/0908/0908bs01/0908bs01.html))
- **The outcome:** C++20 concepts are structural. "Satisfied but not modeled" is ill-formed, no diagnostic required. ([res.on.requirements](https://eel.is/c++draft/res.on.requirements))

**Mojo** ran the experiment: structural conformance was added in 24.2 (2024-03) and removed in 25.5 (2025-08). Today, "Conformance is explicit … Traits don't use duck typing." ([traits manual](https://mojolang.org/docs/manual/traits), [v25.4](https://github.com/modular/modular/blob/main/Mojo/docs/site/releases/v0.25.4.md))

**Rust and Swift** have declared conformance from the start.

**Carbon**, the successor Google proposed for C++, chose declared `impl` plus coherence. ([Carbon generics](https://github.com/carbon-language/carbon-lang/blob/trunk/docs/design/generics/overview.md))

**For us.** The note already rejects deriving conformance from existing methods. Our argument is stronger than Indiana's: in Julia, Base's throwing fallbacks make `hasmethod` true almost everywhere. Structural matching therefore proves even less than in C++, where Stroustrup's "accidental match is rare" rested on names *and* types matching. The C++ debate predicts the counterargument we will meet, that explicit conformance is "viral". Our answers:
- the one-line `@implement`;
- family declarations (C++0x's templated concept maps);
- trait wrappers that declare conformance for a whole package.

## 2. Checking generic code where it is written

**C++0x** checked definitions through *archetypes* (placeholder types with only the stated operations). The costs:
- a concepts compiler "more than 10 times slower", where vendors opposed anything over 20% slower;
- constrained code that sometimes compiled to worse machine code than unconstrained templates;
- a specification of 91 pages, with 125 concepts in the library.

Concepts were removed in Frankfurt in July 2009 ([HOPL4](https://www.stroustrup.com/hopl20main-p5-p-bfc9cd4--final.pdf) §6.2). Concepts Lite stated it outright: "Template constraints are applied to enforce the correctness of template use, not the correctness of template definitions" ([N3580](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2013/n3580.pdf)).

Doug Gregor's prediction came true: without definition checking at the start "we will never get separate type checking", because every constrained template written before then has incomplete requirements ([P0240R0](https://open-std.org/JTC1/SC22/WG21/docs/papers/2016/p0240r0.html)). Arthur O'Dwyer (2020): Concepts Lite "do not, and fundamentally cannot, support definition checking".

**Rust and Swift** check generic bodies against their bounds once, at definition ([Turon 2015](https://blog.rust-lang.org/2015/05/11/traits/); [Gregor](https://www.douggregor.net/posts/swift-for-cxx-practitioners-generics/)). **Mojo** type-checks its parametric templates symbolically before instantiation ([compiler walkthrough](https://github.com/modular/modular/blob/main/Mojo/docs/compiler/MojoCompilerWalkthrough.md)).

**For us:**
- **How our check works.** It runs on inferred typed code per worker, not on archetypes. That avoids C++0x's front-end restructuring.
- **Where it sits.** Closer to C++'s post-instantiation checking than to Rust's. For projections, the instantiations are the library's own representations and show up in its own tests. For own representations they are the user's, and an error appears at the user's conformance.
- **What we inherit.** Julia's version of the problem C++0x struggled with most: implicit conversions and mixed-type arithmetic (`promote`).
- **Timing.** Gregor's prediction argues for keeping the check from day one.

## 3. Layering: bound code calls only bound code

This is the strongest finding of the C++ research. HOPL4 §6.2.5 states the C++0x rule:

> A constrained template cannot call an unconstrained one because it is not known what operations an unconstrained template uses. An unconstrained template can call a constrained one, but checking must be postponed until instantiation time.

That is our rule 1. C++ treated it as a defect, and two objections ended definition checking ([P0557](https://www.stroustrup.com/good_concepts.pdf) §8.2):
1. **Gradual adoption.** "Unless a template using concepts can call a template from a library that does not, a library with the concepts cannot use an older library before that library has been modernized."
   - **Our answer:** trait wrappers, which bring a package written without traits into the trait world unchanged, and declared calls upward to code that stays outside.
2. **Scaffolding.** "We would be unable to insert debug aids, logging code, telemetry code … without affecting its interface". N2906's example is `cerr << t` inside a constrained template. Ville Voutilainen, chair of the committee's evolution working group, said: "I cannot support any proposal for concepts that includes definition checking."
   - **Our answer:** outward doors. Logging, display and printing are dynamic calls upward with no inference edge.

C++0x's escape, `late_check`, broke consistency: "an object could be used in exactly the same way in two places in a program with different semantics". The concept map did not apply inside the unconstrained code. Our analogue: a projected value passed upward, then dispatched on by dynamic code. The boundary principle (values cross, translated by their bound; code never crosses) should rule this out. It deserves an explicit example and a test.

**Mojo** runs layering the other way:
- Static Mojo is the host; Python is a value (`PythonObject`) that static code calls freely.
- Python calls in only through declared exports ([mojo-from-python](https://mojolang.org/docs/manual/python/mojo-from-python)).
- The shared idea is ours: the dynamic side is one opaque representation at the boundary, and crossing is explicit.
- Mojo's planned in-language gradual typing never shipped. That was `def` versus `fn` and "four levels of dynamism" ([Mojo and Dynamism](https://github.com/modular/modular/blob/main/Mojo/proposals/mojo-and-dynamism.md)). `fn` was removed in 1.1 and `def` became the strict form ([fn-to-def-migration](https://github.com/modular/modular/blob/main/Mojo/proposals/fn-to-def-migration.md)).
- Lesson: the clean boundary is the part that works. For us dynamic Julia already exists, so the boundary is all we must build.

## 4. Who may add a conformance or a method

**Rust's orphan rule** is our rule 3: "either the trait must be local or the self-type must be local" ([Matsakis 2015](https://smallcultfollowing.com/babysteps/blog/2015/01/14/little-orphan-impls/)).
- **Why it exists:**
  - the "hashtable problem": `HashMap` calls your `Hash`, so a call site cannot pick among impls;
  - any two crates must combine;
  - adding an impl must not break a downstream crate ([orphan-rules FAQ](https://github.com/Ixrec/rust-orphan-rules)).
- **History.** Rebalanced before 1.0 ([RFC 1023](https://rust-lang.github.io/rfcs/1023-rebalancing-coherence.html)). Loosened in 2018 for Diesel, whose `diesel-chrono` adapter crate was impossible ([RFC 2451](https://rust-lang.github.io/rfcs/2451-re-rebalancing-coherence.html)).
- **Criticism.** Newtype boilerplate; adapter impls with "no obvious home"; "a kind of chilling effect" on interoperation (async runtimes have no shared trait). Matsakis concludes the rule "will have to be weakened" ([2022](https://smallcultfollowing.com/babysteps/blog/2022/04/17/coherence-and-crate-level-where-clauses/)).
  - The crate is at once compilation unit, optimization boundary and coherence boundary, so splitting a project for build speed triggers orphan errors ([internals 2023](https://internals.rust-lang.org/t/exploring-options-for-orphan-rule-bypass-between-multiple-local-crates/19243)).
  - Ecosystem lock-in: a serde replacement needs every crate to add impls ([BoxyUwU 2026](https://www.boxyuwu.blog/posts/an-incoherent-rust/)).

**Swift** allowed retroactive conformances, and its designers regret it.
- Jordan Rose, ABI lead: "Swift should never have allowed arbitrary retroactive conformances". The problem is "what if two people do this?": dynamic casts need a global registry that "can't have duplicate entries". His preferred alternatives are owner-only conformances, wrapper types, or named conformances ([Swift Regret 2021](https://belkadan.com/blog/2021/11/Swift-Regret-Retroactive-Conformances/)).
- Since Swift 6.0, a retroactive conformance warns unless marked `@retroactive`; if two modules declare one, "it is indeterminate which definition … will 'win'" ([SE-0364](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0364-retroactive-conformance-warning.md)).
- Conformance lookup scans every record on a cache miss: over 100 ms of launch time in large apps ([Emerge Tools](https://www.emergetools.com/blog/posts/SwiftProtocolConformance)).

**Mojo** has no extensions officially. The draft proposal offers an orphan-like placement rule and reports conflicts as "ambiguous call" at the use site ([struct-extensions](https://github.com/modular/modular/blob/main/Mojo/proposals/struct-extensions.md)). The compiler has an internal `__extension` already used retroactively, and its import-scoped visibility has had name-collision bugs *(uncertain: internal, undocumented)*.

**For us:**
- **Rule 3 is what Swift wishes it had.** Delegates (implementation packages an owner names) are what Rust's adapter-crate discussions ask for. Our package boundary is not also the optimization boundary.
- **Residual pain to expect:**
  1. Newtypes for the foreign-trait, foreign-type case. The note already says so.
  2. Delegation only helps if owners name delegates. That is a social cost, like Rust's "send a PR upstream".
  3. Convenience pressure: Swift kept retroactive conformance behind `@retroactive` because users wanted it.
- **Load-time checks need indexes.** Sealing and the dispatch check at dynamic sites must look up per function or type, not scan. Swift's launch-time scans are the warning.

## 5. Overlap: more specific beats generic

**Rust's specialization** ([RFC 1210](https://rust-lang.github.io/rfcs/1210-impl-specialization.html), 2015–16) allows overlapping impls in a chain of "more specific". It has been unstable since 2016.
- **Why it is stuck.** Lifetimes are erased before code generation, so type checking and codegen can pick different impls ([Turon 2017](https://aturon.github.io/blog/2017/07/08/lifetime-dispatch/)).
- **Turon's proposed fix:** do not specialize associated types.
- **Today.** Even the `min_specialization` subset used by std may not be sound. A 2026 project goal aims at a minimal version ([goals 2026](https://goals.rust-lang.org/2026/specialization.html)).

**Swift** bans overlapping conformances, partly for runtime casting ([SE-0143](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0143-conditional-conformances.md)).

**For us:**
- **What does not apply.** Julia has no lifetimes, so the cause does not carry over.
- **What does.** "Type checking assumed A, codegen picked B" is Julia's inference-versus-dispatch disagreement. Julia resolves it by invalidation; rule 4 resolves it by compiling against a fixed view.
- **Lesson 1, from Turon's fix.** A more specific implementation must never change a declared result type or a representation. Our declared result types already ensure that for operations; any future associated type in a trait should not be overridable.
- **Lesson 2, a semver hazard.** Rust made adding a blanket impl a breaking change. In our design, a trait owner who later adds a generic implementation can create an unordered overlap with an existing downstream specific one. The note checks overlap "when the specific one is defined", which misses this order. To verify.

## 6. Where compiled generic code lives

**C++ export** (1996–2010) tried to compile templates separately and failed.
- **Cost.** EDG needed three person-years, "more work to implement than any three other C++ language features combined". Implementing all of Java took the same team two ([N1426](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2003/n1426.pdf)).
- **Why it failed.** An instantiation's meaning depended on its context: name lookup across translation units made it "effectively unpredictable". Consistency across units (the ODR) had to be diagnosed for the first time.
- **Outcome.** Export was removed in 2010. Neither extern templates nor C++20 modules compile templates separately ([P1304R0](https://open-std.org/JTC1/SC22/WG21/docs/papers/2018/p1304r0.html), [Clang modules](https://clang.llvm.org/docs/StandardCPlusPlusModules.html)).
- **The road not taken.** CWG 820 had hoped exported constrained templates could be "checked once in the exported definition" ([CWG 820](https://cplusplus.github.io/CWG/issues/820.html)).

**Rust** compiles generics in the instantiating crate, so siblings duplicate them ([matklad, Fast Rust Builds](https://matklad.github.io/2021/09/04/fast-rust-builds.html)).
- **Sharing upstream instantiations** (`share-generics`) is off in optimized builds because it "will impede optimization somewhat" ([#48611](https://github.com/rust-lang/rust/pull/48611)).
- **Polymorphization** was removed in 2024 ([MCP 810](https://github.com/rust-lang/compiler-team/issues/810)).
- **Compile times** are the standing complaint: monomorphization, per-crate codegen, and "trait coherence, which makes it harder to split code into parallelizable units" ([Anderson 2020](https://www.pingcap.com/blog/rust-compilation-model-calamity/)).
- **Graydon Hoare** wanted crates with "stable entrypoints to the outside", calling the lack of them "a big part of Rust's terrible compile times and lack of a stable ABI" *(uncertain: read via [a quote](https://mjtsai.com/blog/2023/06/08/the-rust-i-wanted-had-no-future))*.

**Swift** chose the opposite in 2012: generic code compiled once with dictionary passing, "important for scalability of builds", specialization only as an optimization ([Generics.rst](https://raw.githubusercontent.com/swiftlang/swift/main/docs/archive/Generics.rst)). ABI stability (2019) then let the OS ship the standard library ([ABI manifesto](https://github.com/swiftlang/swift/blob/main/docs/ABIStabilityManifesto.md)).
- **The price is performance cliffs:**
  - moving code into a package made a benchmark 20 times slower ([forum](https://forums.swift.org/t/how-do-you-mitigate-the-performance-impact-of-using-packages/52307));
  - unspecialized code is "about 2 orders of magnitude slower" ([SE-0460](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0460-specialized.md));
  - users call it "Swift's unpredictable efficiency" ([forum 2018](https://forums.swift.org/t/swifts-unpredictable-efficiency/13506)).
- **The fixes:**
  - `@inlinable` (part of the ABI, regretted);
  - cross-module optimization (limited by code size);
  - most recently `@specialized`: specializations the library chooses, with run-time redispatch. That is the nearest Swift feature to compiling per representation.
- **Embedded Swift** requires full specialization. Its 2026 revision allows existentials, emitting metadata only for types placed in one ([vision](https://github.com/swiftlang/swift-evolution/blob/main/visions/embedded-swift.md)).

**Mojo** caches parsed, type-checked, unelaborated code per package (`.mojoc`, tied to the compiler version) and generates machine code per final program ([packages](https://github.com/modular/modular/blob/main/Mojo/docs/site/manual/packages.md)). It is a closed world with no invalidation, driven by GPU targets.

**For us:**
- **Export's failure explained.** It failed because a cached instantiation's meaning depended on where it was instantiated. Rule 4 removes that dependence: compiled code means what its owners' methods say, and a load that would change it is a refused pirate. That is a *diagnosed* ODR, which C++ never required.
- **Placement.** Code lives where the type was chosen, once, not per sibling as in Rust.
- **Specialization by construction.** Projection gives per-representation specialization by construction, not by heuristic. That avoids Swift's cliffs, since there is no slow fallback path.
- **The trade-off.** Rust's `share-generics` names it: shared compiled code cannot be inlined into its callers across packages. Our caching has the same cost and should state it.
- **What we leave out.** Swift's resilience: compiled code is cached, but a package upgrade recompiles.

## 7. Static and dynamic positions

**C++.** Virtual functions are intrusive (inherit from a base). Non-intrusive type erasure is an idiom, not a language feature:
- `std::function`;
- Sean Parent's value-semantic polymorphism ([talks](https://sean-parent.stlab.cc/papers-and-presentations/));
- Louis Dionne's Dyno, with declared or structural "dynamic concept maps" ([dyno](https://github.com/ldionne/dyno)).

**Rust.**
- **The two positions.** `impl Trait` (static) and `dyn Trait` (a vtable), chosen by the callee and part of its API. matklad advises "by default, prefer `&dyn Fn()` over `impl Fn()`" for compile times.
- **Dyn compatibility.** No generic methods, `Self` only as receiver, no `async fn`. It still blocks `async fn` in `dyn` traits ([Reference](https://doc.rust-lang.org/reference/items/traits.html), [async fn 2023](https://blog.rust-lang.org/2023/12/21/async-fn-rpit-in-traits/)).
- **Making `dyn` explicit** ([RFC 2113](https://rust-lang.github.io/rfcs/2113-dyn-trait-syntax.html)) separated the two positions in syntax.
- **`impl Trait`** came from nesting: closure and iterator types cannot be named, and chains like `Rev<Splits<'a, u8>>` leak ([RFC 1522](https://rust-lang.github.io/rfcs/1522-conservative-impl-trait.html)). Through it, auto traits like `Send` leak too ([RFC 1951](https://rust-lang.github.io/rfcs/1951-expand-impl-trait.html)).
- **Error messages** can name a "30 page long type" ([RFC 2397](https://rust-lang.github.io/rfcs/2397-do-not-recommend.html)).

**Swift.**
- **`any P` made explicit.** The bare existential spelling had "risen to the level of active harm"; existentials allocate unless the value fits three words, "the cost of using existential types should not be hidden" ([SE-0335](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0335-existential-any.md)).
- **Not finished.** Making `any` mandatory was deferred in 2023 over migration concerns ([steering group](https://forums.swift.org/t/progress-toward-the-swift-6-language-mode/68315)).
- **"Protocols with associated types"** could not be used as types until 2022: SE-0309, 0346, 0352, 0353.
- **Apple's advice:** "write 'some' by default, and change 'some' to 'any' when you know you need to store arbitrary values" ([WWDC22](https://developer.apple.com/videos/play/wwdc2022/110352/)).

**Mojo** has no dynamic position inside the static world. Witness tables exist at compile time only, and "Existentials / dynamic traits" is not started ([roadmap](https://mojolang.org/docs/roadmap)). Lattner: "the ability to make a runtime trait is missing in Mojo" ([Signals & Threads](https://signalsandthreads.com/why-ml-needs-a-new-programming-language/)). For heterogeneous data there are `Variant`, pointers and `PythonObject`. The 2025 LLVM talk frames Mojo's answer to nesting as each data structure's author choosing what is a parameter ([slides](https://llvm.org/devmtg/2025-10/slides/technical_talks/lattner_zhu.pdf)): Julia's per-field choice, minus `Any`.

**For us:**
- **Who chooses.** Our positions are chosen per conformance and per call mode, and the caller overrides a library's default. Rust's callee-chosen `impl`/`dyn` leaks into APIs; Swift's implicit specialization made the slow path invisible. Swift's lesson, "make the slow path visible from day one", is what explicit modes and concrete mode do.
- **Dyn compatibility.** Our dynamic operations have concrete declared signatures on a representation, so they are dyn-compatible by construction. Rust's dyn rules predict trouble only if trait operations become generic, return `Self`, or return opaque types.
- **The gap.** Every other language with dynamic positions has a storable dynamic value, and Swift names storage as the reason to use `any`. Demand will come (findings §16.6, item 1).
- **Dynamic operations in an image.** Swift emits witness tables statically with the conformance. That supports compiling our dynamic operations with their conformance instead of making pointers per session (§16.6, item 3).

## 8. The complexity budget

| | What grew out of control | Cost |
|---|---|---|
| C++0x | concepts specification, archetypes, `late_check` | 91 pages, compiler 10 times slower, removed |
| Rust | trait solver (order-dependent, unsound corners), generic associated types, specialization | solver rewrite since 2023 ([blog](https://blog.rust-lang.org/inside-rust/2023/07/17/trait-system-refactor-initiative/)); generic associated types took 6.5 years; specialization unstable for 10 |
| Swift | recursive associated-type constraints, type-checker overloading | generic signatures undecidable, Requirement Machine a semi-decision procedure ([Pestov 2022](https://forums.swift.org/t/the-requirement-machine-a-new-generics-implementation-based-on-term-rewriting/55601)); "unable to type-check this expression in reasonable time" ([roadmap 2025](https://forums.swift.org/t/roadmap-for-improving-the-type-checker/82952)) |
| Mojo | (avoided by design) | Lattner: Swift's type system was "slow and overly complex … 'don't do it again'"; no inference from result types ([HN 2023](https://news.ycombinator.com/item?id=35811426)) |

Across the four, the expensive features are type-level computation in traits: associated types, recursion among them, higher-ranked bounds, overlap and negative reasoning. Traits as "operations on a representation, with declared concrete signatures" stay out of most of that space. Every step toward associated types should be weighed against this table.

## What is new in our design

1. **Projection as an enforced position.** Every language reaches it by convention:
   - Rust's thin generic wrapper around a non-generic inner function (`fs::read`), matklad's "generic hotpath, concrete coldpath";
   - Swift's wrapper types;
   - Makie's `convert_arguments`.

   Rust's evidence for the payoff: up to 30% of LLVM definitions are duplicate instantiations (#48779), and Servo's largest crate got 28% faster by cutting instantiations ([Nethercote 2020](https://blog.mozilla.org/nnethercote/2020/08/05/how-to-speed-up-the-rust-compiler-some-more-in-2020/)). Retrofitting sharing into the compiler failed (polymorphization removed, `share-generics` off at -O). That argues for putting it in the language.
2. **Caller-overridable modes** for function arguments. Rust and Swift fix the choice in the callee's signature.
3. **Ownership-checked dynamic dispatch.** The method selected at run time must come from an owner or a delegate. Swift's global conformance registry enforces uniqueness; ours enforces ownership.
4. **Compiled code cached by owner in a language that compiles at run time.** Rust and Mojo are whole-program and static, Swift is resilient and dictionary-passing, C++ duplicates per translation unit. None caches specialized code per package with a guarantee that loads cannot change it.

## What their experience predicts for us

| # | Prediction | Source | What to do |
|---|---|---|---|
| 1 | "Explicit conformance is viral" | C++0x, Stroustrup | keep `@implement` one line; wrappers declare for whole packages |
| 2 | Layering will be attacked for gradual adoption and scaffolding | C++0x, P0557 | say in the note that wrappers and calls upward answer the first, outward doors the second |
| 3 | A `late_check`-like inconsistency where values cross upward | C++0x | example and test: a projected value dispatched on above |
| 4 | Pressure for retroactive conformance | Swift `@retroactive`, Rust adapters | make delegates easy; consider named conformances |
| 5 | A later generic implementation overlapping an existing specific one | Rust RFC 2451 | check overlap on both orders, at load |
| 6 | A more specific implementation changing result types | Rust specialization | forbid it; never make associated types overridable |
| 7 | Load-time checks scanning all methods | Swift conformance scans | index by function and type |
| 8 | Demand for a storable dynamic value | Swift `any`, Rust `Box<dyn>` | design it (§16.6.1) |
| 9 | Shared compiled code not inlined across packages | Rust share-generics | state the trade-off; own representation is the escape |
| 10 | Early binding misses a more specific downstream method | C++0x `merge`/`copy` (Siek) | the note should present rule 4's early binding as a deliberate choice, with own representations as the answer |
| 11 | Implicit defaults added later break things | Swift `Copyable` (SE-0427) | decide now whether representations must be concrete, isbits, … |
| 12 | Type-level computation in traits | all four | keep traits to operations with declared concrete signatures |

Item 10, from Siek ([The C++0x "Concepts" Effort](https://arxiv.org/pdf/1201.0027) §3.5, §4): checked once against its constraints, `merge` calls the slow `copy` even for random-access iterators. C++ chose late binding and so lost separate compilation. Rule 4 chooses early binding, which is how we get cacheable code, and pays this price.

## Uncertain or unchecked

- Aria Desires' claim that early Rust tried a Swift-like polymorphic design ([faultlore](https://faultlore.com/blah/swift-abi/)), unconfirmed by a 2012 source.
- Graydon Hoare's quote, read only via a blog that quotes it.
- The ISO number and year of the Concepts TS.
- Authorship of Swift's Generics.rst (likely Gregor).
- The iOS 16 dyld conformance cache, seen in search snippets only.
- The exact date of the Embedded Swift revision (commit metadata, August 2026).
- Mojo's internal `__extension` and whether an orphan restriction is enforced.
- Mojo's history in 2026: 1.0 on 2026-08-11, Qualcomm acquisition on 2026-07-29, compiler open-sourced on 2026-08-18. These come from Modular's blog and changelogs, as the agent read them.
