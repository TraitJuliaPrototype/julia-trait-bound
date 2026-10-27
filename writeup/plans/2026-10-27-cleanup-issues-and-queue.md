# Cleaning up the open issues and the work queue

Status: **proposal (an agent's, for the user's review)**. Nothing in it is applied. Serves [W-65](../record/todo.md).

The user (2026-10-27), the rule for the open issues: "Is there a principled choice? A choice that simplifies the architecture at little cost? If so adopt that. Is it unclear what the repercussions of either choice are, but working with trait code could provide insight either way? Flag it as "revisit once experience with large scale ports is at hand". Is there other evidence/experiments that could settle the choice? Record it as such. If not just accept it as is. Only keep the choices with a well articulated trade-off for me to review."

The rule for performance work ([decisions](../record/decisions.md) §5), with the user's refinement of the same day: "Orders of magnitude was a bit excessive. Let's say changes of 20% or more. And slow downs where conceptually trait/facts code should be the same/faster also get to stick around as worth investigating." So performance work stays in the queue when it is:
- a principled architectural improvement that facts and traits enable;
- a defect revealed by facts or traits that changes a time by 20% or more;
- a slowdown where trait or facts code should conceptually be as fast as plain code, or faster.

Everything else goes to the further performance explorations log (part 4).

Settled before this proposal and only pointed to here (the coordinator's edits of 2026-10-27, the user: "Let's retire the experimental cache and add this cache to the Todo list"): the experimental cache retired (W-62 dropped), the facts-keyed cache as W-66, open issues 72 and 76 closed.

Read with: [`../open-issues.md`](../open-issues.md), [`../record/todo.md`](../record/todo.md), the references' Deviations tables, [`../state.md`](../state.md), [`../record/experiments.md`](../record/experiments.md).

---

## 1. Summary

**Open issues: 109 rows** (every numbered item and every unnumbered bullet in §1–§5):

| Disposition | Rows |
|---|---|
| (A) adopt | 20 |
| (R) revisit once experience with large-scale ports is at hand | 8 |
| (E) settled by evidence or an experiment | 6 |
| (K) accept as is | 13 |
| (U) keep for the user | 1 |
| (C) already resolved, close | 28 |
| (M) merge into an item, a work item, an experiment, a deviation row or the performance log | 33 |

What would remain in `open-issues.md`:
- §1: the one (U) item, and the deferred AOT annotations as a pointer;
- a new section, "To revisit with the ports": the eight (R) items and two sub-items of item 31;
- the (E) items, each naming its experiment, until it runs.

**The one choice for the user (U): strict mode's intended design, deferred since session 25.** The facts-keyed cache (W-66) makes it a question of when:
- **Take it up with W-66:**
  - W-66 validates a cached entry by comparing its facts' origins, a table lookup with no edge walk (the exploration §3, "Under strict mode: sufficient");
  - strict mode's check at load (6.6 s for the facts-compiled SciML core, E-168) moves into image validation, which W-66 shares;
  - Julia pieces 15, 14 and 1′ join the next full build;
  - the two ownership questions (items 19, 65) are settled by their census then.
- **Keep it deferred:**
  - W-66 still works, but validates its entries' facts edges, fewer than all edges, so it gains less at load;
  - strict mode stays a prototype, with a 6.6 s load for a large core;
  - no Julia work on strict mode.

**For the user to confirm, beyond the rule:** a new work item for the Makie port (W-70, part 3). It follows W-61's "then the ports with W-60's memo" and W-58's "the porting architecture for Makie", but no item names it.

**Adopted items** are choices of mine under the user's rule. Each is written into its reference and gets a decision-log row marked "mine, adopted by the cleanup rule (§8)". The user may overturn any.

**What I could not judge without running code** (each is a cheap check, listed as such):
- 3.bn6: whether fully typed mode traces keys' field types as root causes (a probe);
- 3.bn7: whether every result through an opened `Dynamic` is asserted (read as resolved by lowering §13 and C-8; to confirm by reading `split_call`);
- 3.do2c: a parameter-bounded constructor at an archetype (a probe);
- W-10: whether the machinery's reflection code is still compiled again after loads (folded into W-7's bisect).

**The work queue: 33 rows** (W-items not done or dropped, with W-66):

| Disposition | Rows |
|---|---|
| keep | 18 |
| merge | 8 |
| done (W-25, W-58, W-60; W-65 when applied) | 4 |
| to the performance explorations log | 3 |

New work items proposed: W-67 to W-70. New experiments: four, named E-new-a to E-new-d here, numbered when applied. The log of further performance explorations starts with seven entries, PE-1 to PE-7.

---

## 2. Open issues, item by item

Legend:
- **(A)** adopt; **(R)** revisit with the ports; **(E)** settled by evidence or an experiment; **(K)** accept as is; **(U)** for the user; **(C)** resolved, close; **(M)** merge into another item, a work item, an experiment, a deviation row or a performance-log entry.
- Rows are named by section and number (`1.75`, `2.11`), as the file numbers them. Unnumbered bullets get a short label (`1.D1`, `2.R-a`, `3.bn2`).
- "Decisions" means [`../record/decisions.md`](../record/decisions.md). A row there for an (A) item is marked "mine, adopted by the cleanup rule (§8)".
- Where a choice needs building, the work item is named. E-new-a to E-new-d are new registry rows.

### §1. Decisions waiting for the user

| Item | Disp. | The choice, and why | Recorded in |
|---|---|---|---|
| 1.75 A lean tree against upstream's API | A | W-60's answer (memo §3.4, pushback 1): <br>- heavy features go behind package extensions for keys, and behind loading stubs for functions; <br>- `hist(x)` stays as upstream calls it; <br>- each lean measurement names what it drops (option (i), which the user agreed to); <br>- on-demand loading of implementations (option (ii)) stays an exploration. <br>Principled: it uses Julia's extensions as they are and adds no mechanism. E-182: a stub's load invalidates none of the core's 689 CodeInstances. | decisions §8; `intro/porting.md` (large libraries); `explorations/load-on-demand.md` status line |
| 1.76 The cache's shape | C | Closed by the user: the experimental cache retired; its questions moot or carried into W-66. | the coordinator's edit |
| 1.77 World age at loads on demand | E | E-182 (done) settled it: option (a) works, at no measurable cost per `save`, and world age hits plain code alike. So it is Julia's rule, not a trait question. Adopt (a): user-facing entries that can reach code loaded on demand (render, `save`, `display`) call the core through `invokelatest`. | decisions §8; porting guide; alternatives: (b), an error naming the `using`, not taken |
| 1.D1 Strict mode's intended design (deferred, s25) | U | Part 1. Absorbs: <br>- the censuses of 1.19 and 1.65 (E-new-a); <br>- 2.23 (indexes for attribution); <br>- 2.73's "strict mode's check at load"; <br>- 3.s25-c's remainder (dependence through native code); <br>- W-21 (F-6). <br>Its own sub-questions: <br>- bindings redefined from another module: K, G2's named exception until a hook exists (facts §2.2 as is); <br>- the session as owner at the prompt: K, a prompt definition is `Main`'s, strict mode is a per-session switch, the friction is a stated cost (framing review, item 7: "documentation"); <br>- strict mode under `all`: E-82, run with it. | open issues §1; decisions §4, "the intended design of strict mode" |
| 1.D2 AOT annotations (deferred, s25) | K | Stays deferred, as decisions §6 records ("recorded, deferred"); the entry becomes a pointer. Absorbs 3.s25-a, 3.s25-b, 4.4 and E-118. | decisions §6; `explorations/aot-under-facts.md` §6 |
| 1.13 Base's tests in facts mode | M | E-42, in W-9 (correctness). | registry E-42 |
| 1.16 The demonstrators' claims after the control | M | W-61: <br>- each README's "what it demonstrates" re-pointed; <br>- PlainODE and PlainPlots under `all` as the control (minutes). | W-61; evidence §1 |
| 1.17 The refusal message for a late override | A | The message says what holds today: define the method before `@implement`, and restart. "Or in its block" goes, since it is not available after the fact; `TraitWorld/src/hooks.jl:166` still says it. The message names redeclaration once that exists (traits §4.9, Planned). | W-67; T-11 extended |
| 1.19 The standard libraries as owners | E | E-new-a, a census (one script, minutes, no build): the standard-library methods that are pirates by the letter if each library is its own owner, and which of them win at a fact of trait code in the demonstrators and the port's core. <br>Outside strict mode the choice changes nothing, since a winning pirate is followed by default. So it runs with 1.D1. <br>Would decide: <br>- only late-loaded libraries win (SparseArrays' `vcat`): each library its own owner (ownership by package, uniform); <br>- a library in the system image wins (LinearAlgebra's methods of Base's functions): Julia stays one owner. | registry; facts §2.2 and traits §10.1 keep "Open", linked to 1.D1 |
| 1.20 Pirates in trait modules | A | Keep refusing every pirate defined in a trait module, as built, beside strict mode's refusal of winning pirates in plain code. <br>Principled: Rust's orphan rule for new code; checked at the definition, independent of load order. <br>The port's core, wrapped bottom-up, stayed free of pirates (E-155): split packages used joint owners, and packages holding pirates stayed plain. <br>Merges 2.c1. | traits §10.2 status and the status index (Open removed); `design.md` §2.2 (one sentence); T-56 stays; decisions §4 |
| 1.26 The implicit crossing's finer rules | A | Confirm as built (traits §8.2–8.3). Each follows a rule in force: <br>- values carry; <br>- refusal at the call where the type rules a value out; <br>- an exact match before a conversion; <br>- the first-seen rule. <br>The keyword case is T-39: the reference already says keywords cross. | decisions §3 |
| 1.38 What follows the split | A | The table with `:caller_world` pointers stays (compiler §4.3, Implemented). Within it: <br>- C-14 and C-3 go to PE-4; <br>- a witness carried in the value goes to PE-3. | decisions §5; PE-3, PE-4 |
| 1.56 The choices of W-45 and W-46 | A | They follow Julia's own name resolution and the supertrait rules. Confirm. | decisions §2 |
| 1.57 `Kept{X}(x)` and stores take the trait's default | A | A store has no caller whose knowledge could decide: inside `convert` every type is concrete. So the trait's default is the one rule that does not depend on how `convert` is compiled. As built. | decisions §3 |
| 1.58 `@implement` of a bundle | A | Follows from "a bundle and its tuple are the same trait". Built (W-54). | decisions §1 |
| 1.59 A key's field type is the declared type | A | It is the user's decision "keys replace representations": compiled for what the bound can see. The reference states it; the code deviates (L-42). <br>Unblocks W-55. Its cost, an abstract declared field read abstractly, is 2.1's stated cost. | decisions §1; W-55 ready |
| 1.60 Stakeholders per number of arguments | A | Keeps Lemma O true. Built (W-53). | decisions §4 |
| 1.61 A run-time site's mark carried through calls | A | Restores G1 as written. Built (W-52, julia-1.13 0c589fd385; F-12, C-13, C-15 retired); the item's "Not built" is stale. Its cost is 4.66, which W-57 addresses. | decisions §5 |
| 1.62 W-40's mechanism | A | Built and reviewed twice (W-40 done). | decisions §2 |
| 1.63 A member's override only in its parameter type's owner's own package | A | Principled by load order: whoever names `S{MyT}` depends on that package, and an extension loads after its triggers. T-28 is the gap. | decisions §2; T-28 stays |
| 1.64 The member check at abstract declared arguments | A | Count only the stakeholders' methods: the owners of the operation, of the type and of its parameters' types. <br>Principled: it is the facts rule's own notion, and it makes a member's implementation independent of load order. <br>Merges 4b.F3, with its acceptance case (a family over Base's abstract types, later methods by members' owners). | traits §4.7, §4.9; a new T- row until built; W-67 |
| 1.65 Who owns a method defined by `@eval Owner …` | E | E-new-a also counts the methods in package images whose module is neither the image's package nor a joint owner of it. <br>Would decide: <br>- few, all between split packages: a method in an image belongs to the image's package (principled: ownership cannot be borrowed by evaluating into another module), and the module rule at run time becomes a named exception; <br>- common and legitimate: the module rule stays, named in facts §2.2's exceptions. <br>Runs with 1.D1: only strict mode and Lemma O read this. | facts §1 and traits §10.3 keep "Open", linked |

### §2. Design

| Item | Disp. | The choice, and why | Recorded in |
|---|---|---|---|
| 2.73 The load of a large trait world | M | Not a choice. Each option goes to its home: <br>- facts images without edge validation → W-66 (the same mechanism: origins compared, cheap under strict mode); <br>- a smaller tree → W-60's memo and the ports (W-34, W-70); <br>- strict mode's check at load → 1.D1; <br>- remembered validation → PE-1; <br>- an environment image → PE-2; <br>- the facts images' own load: done (W-59). | W-66; PE-1, PE-2; 1.D1 |
| 2.72 A cache that builds up across sessions | C | Its direction is W-66. | the coordinator's edit |
| 2.R-a The setting as part of an image's key (F-7) | A | The setting (product or `all`) is part of a package image's key, as Julia keys images by its code-generation flags (check-bounds, inlining, optimization level). <br>Principled: code compiled under one setting is not code of the other. Small: one flag in the key. <br>`--trim` builds compile plainly and need no key. | facts §11 (Open → Planned); F-7 reworded; W-69 |
| 2.R-b `verify_main` under `all` (F-8) | K | As is, stated as the rule: `verify_main` reports the run-time sites of the code as it runs in the session, so under `all` the facts mode's sites in Base count. It is conservative: a trimmed build compiles plainly and can only have fewer. <br>The check that fails under `all` is marked as expected there, so the suites stop reporting "the known F-8". | facts §12.3 (Open removed); F-8 retired; test in W-67 |
| 2.1 An abstract declared field gives an abstract key | K | The stated cost of declaring a field abstractly (with 1.59). `@enforce_concrete_only` makes it an error where wanted. | traits §3.3 (one sentence) |
| 2.2 Inline fields that are not isbits | K | Read through `getfield`, as built. C-7 stays. | — |
| 2.3 A copying layout for isbits-only targets | K | Not in the design until a port targets isbits-only devices. Merges 2.21. | lowering §6 (Open → Optional) |
| 2.4 Forwarding for a whole family | C | A duplicate of traits §4.7 (Planned) and T-7. Built when a port needs it (the port's ground rule). Merges the matching bullet of 2.c5, 3.bn4, 3.do2a. | T-7 |
| 2.5 Mutable and immutable state families | A | Two traits, the mutable one a subtrait of the immutable one, as BaseTraits' `Indexable` and `MutableIndexable`. No constness that depends on the family. <br>Principled: Rust's `Index` and `IndexMut`. Simpler: no new rule. | traits §3.3 (one sentence); porting guide; alternatives (constness per family, not taken) |
| 2.6 Input parameters, associated type constructors, results bounded by their own trait | R | The SciML and Makie ports show whether conformance at every value of a parameter (`ODERHS{P}`) or `view`-like results are needed. Form B avoids the first. | §6 of open issues (new) |
| 2.38 Associated constants | K | Values fixed per implementation are operations with declared results, which fold. Per-instance values lifted into the type are explicit parameters, as in Julia. | traits §3.1 (one sentence) |
| 2.7 A small `Union` as an operation's result | C | BaseTraits' `iterate` declares `Union{Nothing, Tuple{T, Any}}` (traits §8.1). The reporting half is closed item 18. | — |
| 2.8 Numeric traits | R | The SciML port (dual numbers, element types) shows which numeric traits and archetypes definition checking needs. | §6 (new) |
| 2.9 AD tags in a key; units | R | AD tags are decided (labelled by the primal signature; decisions). Units: the ports show whether they need more than a parameter. | §6 (new) |
| 2.10 `Callable` bounds whose argument types the callee chooses | R | The SciML port's algorithm packages (W-34, X4) show whether partial evaluation at the entry (W-63) leaves any. | §6 (new) |
| 2.11 How `Vector{<:ColTable}` takes a user's vector | A | A trait inside a Base container's type in an argument annotation is refused at the definition. The message names the collection bound (`Indexable{X}`, `Iterable{X}`), through which a user's vector crosses as it is (traits §8.3, the user's choice of 2026-10-20). <br>One spelling; no copy. | traits §5.1 status and the status index; a T- row until built; W-67; alternatives (copying element by element, not taken) |
| 2.12 Bounds over several arguments | R | The Makie port (`lines(x, y)`). | §6 (new) |
| 2.13 "Live" bounds | R | The Makie port (Observables). | §6 (new) |
| 2.14 The joint-method rule for wide families | R | The Makie port (`plot(x)` over data traits). | §6 (new) |
| 2.16 Opening a `Dynamic` at its concrete type | K | A plain assertion on the held object (`m = integ.p::Lorenz{Float64}`), as traits §7.1 says. No new form. | traits §7.1 status and the status index (Open removed) |
| 2.17 A closure from a trait module stored as a dynamic function | C | By pointer: `Erased{A, S}` holds a `:caller_world` `cfunction` for any function, closures included (lowering §12). | — |
| 2.18 Assignment from above into a trait-named field | C | Traits §7.3 (closed items 40 and 47). | — |
| 2.19 Tasks and concurrency | M | E-63, in W-9. | registry |
| 2.20 Reporting a function that always throws | K | As traits §5.8 says: anything callable conforms, and a function without a method at `A` raises `MethodError` when called. The misleading warning in compiled mode ("always throws: a fallback") is a message fix. Merges 3.sa4. | T-11; W-67 |
| 2.21 Checking held parts after each call upward | M | 2.3. | — |
| 2.22 A value crossing upward behaves as inside | M | E-47, the conformance suite: a kept value passed to plain code is the user's object. | registry |
| 2.23 Indexes for strict mode's attribution | M | 1.D1. | — |
| 2.24 Inference-dependent element types | C | Facts §2.1, "The exception: values decided by inference". Trait code declares its results. | — |
| 2.25 Recipes and models defined at the prompt | M | E-110, a REPL row per demonstrator. The views part is moot: views are deleted. | registry |
| 2.27 Facts code calling compiler functions (B1) | K | As is: the edges go to plain code, consistent with the decision "the compiler's own code is plain whoever calls it". The loss is cacheability only, measured at 0. Facts §6.4 and §2.2 state it instead of "Open"; L-17 retires. | facts §6.4, §2.2, the status index; lowering L-17 retired; alternatives (calls in the compiler's world: they would break packages that extend the compiler) |
| 2.28 AOT from declared targets: the forks' workload extensions | M | W-14 for the forks' extensions; L-15 for the gaps. Item 29 is closed. | — |
| 2.30 The exception for `return_type` in the product setting | E | E-new-b, in W-22: the run-time query routed through `PlainRTInterp` in both settings; every answer checked `===` the folded one (E-44's corpus); the second cache's inference time measured in the demonstrators' sessions and in E-168's session. <br>Would decide: <br>- no measurable cost: adopt (one answer, one rule; F-20 and C-10 retire, the exception goes); <br>- a cost of 20% or more on a session: keep the exception, stated with its cost. | facts §7.1, compiler §1.4; W-22 |
| 2.31 Collection traits | C | Decided (closed items 21–25), built, measured (E-164). Its open sub-items: <br>- which traits and algorithms come next: R; <br>- two traits declaring one function at one arity: R; <br>- a generic algorithm's function: K, an ordinary argument as `retain!` takes it (Julia's `filter!` does the same; a `Callable` needs a constant `A`); <br>- items of one concrete conforming type: W-27 (`where T` conforming needs traits in the type system); <br>- a `Dynamic` argument boxed in a `Dynamic` `Callable` (14–18 ns against 3.68): W-17, since trait code should be as fast; <br>- `Dynamic{X}(x)` at a run-time site in plain code: PE-6. | traits §8 status rows; §6 (new) |
| 2.37 Recompiling in the background with the observed types | M | PE-3. Beyond the split trait code beats plain (E-164: 17.6–18.8 against 96–101 ns at 64 types), so no gap motivates a tiered compiler. | compiler §1.6, §3.3 (Optional, unchanged) |
| 2.36 A trait-typed assertion in a body | M | W-27: once `x isa X` means conformance, `v::X` in a body is where the value is first seen through `X`. Until then, the constructors of traits §6.2 (`Dynamic{X}(v)`, `Compiled{X}(v)`). | W-27; traits §14 |
| 2.c1 Pirates in trait modules (the design and the code disagree) | M | 1.20. | — |
| 2.c2 Generic implementations' predicates | A | Patterns on the constraints' parameters only, never computed conditions. That keeps overlap decidable (T-9's check). The test with `eltype(R) == Vector{Float64}` changes. <br>Principled: Rust's `where` clauses are bounds, not predicates. | traits §4.8, lowering §4.8 (Open → the rule); a T- row until refused; W-67 |
| 2.c4 `Dynamic{X}` contents | C | It holds the user's object (closed item 25; L-8 retired). | — |
| 2.c5 In the design, not built | C | Each is a Planned status with its deviation row: T-7, T-20, T-34, T-51; `Callable` with keywords and bounded closures (traits §5.7–5.8); `==` and serialization (§7.1). | — |
| 2.c7 The `{R}` spelling and `project(t) = …` | M | W-68. | T-12, L-7 |
| 2.c8 TraitWorld has no README | M | W-61: a short README that points at the references and the tests. | — |
| 2.c9 The demonstrators' READMEs say `JULIA_TW_VIEWCACHE=0` | M | W-61. TraitMakie's and TraitReport's READMEs still say it. | — |
| 2.c10 TraitDifferentialEquations' `RESULT` lines | M | W-61. The README (line 126) still says 10. | — |

### §3. TraitWorld

| Item | Disp. | The choice, and why | Recorded in |
|---|---|---|---|
| 3.s25-a Trim's own verifier | M | 1.D2. | — |
| 3.s25-b `verify_main` walks from `main` only | M | 1.D2. When taken up: walk every entry that runs in the binary, `__init__` included (principled, mine). | — |
| 3.s25-c Strict mode's prototype checks direct callers only | C | F-5 retired: the walk follows callers transitively (TraitWorld 2341fce, W-21). Dependence through native code goes with 1.D1. | — |
| 3.s25-d Threads | M | E-63, in W-9. | — |
| 3.s25-e The hunt's C24b | C | A harness bug; no design question. | — |
| 3.bn2 Which functions keep, decided at the module's end | K | As decided in s27: interactive changes need a restart, and the error is the safety net. The 900 ns `keepsum` predates W-18; W-17 measures it again. | — |
| 3.bn3 A subtrait's implementation against the supertrait's | C | W-23 (T-3 retired; the supertrait agreement check is Implemented). | — |
| 3.bn4 Family forwarding, named implementations, archetype checks | C | T-7; named implementations deferred (alternatives); T-19, L-10. | — |
| 3.bn5 AOT inverses for results like the input | C | T-20. | — |
| 3.bn6 Fully typed mode and keys' field types | M | W-67: a probe. A T- row if it fails, since traits §11.3 says root causes are traced through any number of layers. | — |
| 3.bn7 Results through an opened `Dynamic` | C | The split asserts the declared result (`RT`, lowering §13; compiler §4.2). C-8 lists where it does not. To confirm by reading `split_call`. | — |
| 3.bn8 Family implementations through the slow path | C | W-40 (`fold_call`; L-23 and L-37 retired; L-44 the remainder). | — |
| 3.dc12 Experiments in the old spelling | K | Pinned experiments stay pinned; W-68 leaves them. | — |
| 3.dc13 The `{R}` spelling still accepted | M | W-68. | — |
| 3.sa1 A bound with a `where` variable | C | W-24 (T-16 retired). | — |
| 3.sa2 A trait's parameter in a default's body | C | T-2, built when the SciML port needs it (W-34). | — |
| 3.sa4 A `Callable` entry's check | M | 2.20. | — |
| 3.sa6 `@implement` in the struct's block | C | Closed item 74 (TraitWorld 5589f4c). | — |
| 3.B `verify_main` scans an instance in the first mode met | C | F-9. | — |
| 3.do1 A precompile workload for the machinery | C | The regression it was for is gone (closed 2026-10-20; the machinery's code in TraitWorld's image, f7aea19). | — |
| 3.do2a Forwarding for a whole family | C | T-7 (2.4). | — |
| 3.do2b A bound error that lists the declared implementations | A | `TraitBoundError` lists the declared implementations, as Rust lists "the following types implement trait". A message; cheap. | W-67; a T- row beside T-22 |
| 3.do2c A parameter-bounded constructor at an archetype | E | A probe in W-67's tests (minutes): `SimpleEdge{T<:Integer}` at an open parameter. A T- row if it fails. | W-67 |

### §4. Runtime and measurements

| Item | Disp. | The choice, and why | Recorded in |
|---|---|---|---|
| 4.71 First calls slower on the build of 2026-10-27 | M | W-7, re-scoped, with E-new-c: a bisect, TraitWorld's commits first on one Julia build (no build needed), then the Julia commits. <br>Every listed row moved by 20% or more, and trait code should be as fast as on the build before. W-57's part 1 restored the padding folds, so the bisect can start. | W-7; registry |
| 4.69 W-56's cost trigger | M | PE-7. | — |
| 4.70 The type-introspection sweep upstream? | M | W-19: upstream proposals wait for the user ("We are not proposing anything upstream yet"). The framing is recorded in `julia-changes.md` §4. | — |
| 4.68 A conforming value stored untranslated | A | A type conforms only where each of its values meets the trait's contract. <br>- Not every `Symbol` names a colour, so `Symbol` does not implement `ColorSpec` or `MarkerShape`. <br>- TraitMakie implements them for validated name types. <br>- `convert(ColorSpec, ::Symbol)` translates at the store and refuses an unknown name there, by decision 47's existing path. <br>No new hook. | porting guide; TraitMakie (W-67); alternatives (a validation hook at stores, not taken) |
| 4.67 Readable stack traces against inlining | R | The user: "note this as a revisit". The ports show how often debugging needs the trait in an inlined frame. | §6 (new) |
| 4.66 W-52 costs the folds of Base's helpers | E | E-167 (2): E-162's step d after W-57's part 1. <br>- Back near 33–47 ms: close 66; parts 2–3 continue only where the withdrawn-assertion log finds a gap of 20% or more. <br>- Still far: part 3 by the log's list. | W-57 |
| 4.3 Not yet measured on 1.13 | C | Plain time to the first PNG is measured (E-168, setting S). ComboCache is removed. A 1.12.2 control is moot: stock support is dropped. | — |
| 4.4 The `experiments/world` binary | M | 1.D2 (E-118). | — |
| 4.10 Upstream CSV + DataFrames after nine loads under `all` | M | PE-5. By design: SparseArrays' `vcat` wins a fact, and is followed under either ownership rule outside strict mode; the plain answers behind `return_type` change as plain Julia's do. The remedy is upstream. | — |
| 4.13 Reruns on the current compiler | M | E-103 (TraitReport (t) under loads); E-106 (the forks, after W-14); E-42 (W-9); W-5 → W-61. | registry |
| 4.14 Acceptance checks for the session-29 changes | M | E-62, in W-9. | — |
| 4.35 Performance issues after W-4 | M | W-17, re-scoped: <br>- P1 regressed (28.8 → 59.9 ns); <br>- E-157's boxing: about 7 ns per call and 6 boxes per Tsit5 step of 169 ns, roughly 25% (check whether W-63 removes it); <br>- P3–P12 measured where they lie on the demonstrators' paths. <br>Each is a gap where trait code should be as fast; each of 20% or more stays. | W-17 |
| 4.43 A `Callable` argument entered by an untyped call (L-36) | M | W-17, with E-new-d: the crossing in a loop against plain. The reference promises plain speed (lowering §8.2, §12), so a gap is a defect. The fix is named there: a typed entry decision, as the trait positions' `enter` has. | W-17; L-36 |
| 4.78 Facts inference through a `Dynamic{Callable}`'s target | M | W-7: +32% at the first render (262–269 against 199–201 ms), worth investigating under the refined rule. | W-7 |

### §4b. The review of session 23

| Item | Disp. | The choice, and why | Recorded in |
|---|---|---|---|
| 4b.F3 Family implementations over Base's abstract types | M | 1.64, with its acceptance case. | — |
| 4b.F9 The walk of abstract parts at the entry | C | The review itself says it no longer has a meaning (keys take the user's object). | — |
| 4b.F11 Stale statements in the notes | C | The notes are in the attic. | — |
| 4b.dec4 Who declares an implementation for a foreign type | C | Traits §10.1 (who may implement). | — |

### §5. Documents

| Item | Disp. | The choice, and why | Recorded in |
|---|---|---|---|
| 5.1 `makie-rewrite.md` and `solvers.md` in the old terms | K | Their banners say how to read them; W-60's memo replaces them where they disagree. | — |
| 5.2 `design-findings.md` | K | A history document in session order, listed in the record index. | — |
| 5.3 The live Claude Doc frozen at revision 1146 | C | A fact for the record index, not an open item. | — |

---

## 3. The work queue, item by item

Every W-item that is not done or dropped, with W-66 (W-62 is dropped by the coordinator's edit).

| W | Disposition | Why, and what it becomes |
|---|---|---|
| W-5 TraitMakie's rows timed whole | merge into W-61 | The claims need rows timed whole (minutes). |
| W-7 The first gradient with loads | keep, re-scoped (order 5) | **First calls and sessions slower than they should be** (the refined rule). It covers: <br>- open issue 71's rows, bisected by E-new-c; <br>- the first gradient with loads, 82–89 against 68–70 ms, a load-order difference that facts code should not have; <br>- TraitReport's trait plot, 96–98 against 60 ms; <br>- form (t) against (pt), 0.83–0.86 against 0.74–0.76 s; <br>- open issue 78 (+32%); <br>- W-10. |
| W-8 A problem type in a package of its own | merge into W-34 | X4 (an algorithm package against a trait core) measures the first solve from a package's image, with and without its workload. The memo's pushback 3 says compile ahead does not reach the solver's driver. |
| W-9 Correctness | keep, re-scoped (order 4) | The correctness checks: <br>- E-29 (G2 under `all`); <br>- E-42 (Base's tests); <br>- E-62 (the inliner changes and the compiler-plain edges); <br>- E-63 (threads); <br>- E-95 (the TraitMakie image flake). <br>Base's tests run overnight, alone. |
| W-10 The machinery's startup after loads | merge into W-7 | Same rows (`@implement` after loads). |
| W-11 `return_type` after loads | split | The differential test (E-44) is correctness: into W-22. Red-green revalidation goes to PE-5. |
| W-12 The next call-site cache steps | to PE-4 | No first call or session is shown slower by them. |
| W-13 Upstream proposals | merge into W-19 | The split patches are the proposals' form; both wait for the user. |
| W-14 The forks resumed | keep, paused (last) | The user paused the forks. Absorbs W-35's DataFrames half and 2.28's workload extensions. |
| W-17 Measure `Dynamic` and `Compiled` | keep, re-scoped (order 5) | **Calls slower than plain where trait code should be as fast**, measured by E-new-d: <br>- P1's regression (28.8 → 59.9 ns); <br>- W1's copy (E-164: 4.6 against 1.5–1.8 ns before); <br>- `retain!` within four, 2.8–3.1 against plain's 2.1 ns; <br>- the `Dict` loop, 4.4–4.5 against plain's 2.3 ns; <br>- the boxings of 2.31 and E-157; <br>- L-36 (4.43); <br>- `keepsum`; <br>- P3–P12 on the demonstrators' paths. <br>A gap of 20% or more is a defect to fix; a smaller one is recorded. |
| W-19 Julia changes as small patches | keep, waiting (the user) | The user: "Just add it for now, this is not a suggestion to start working on it." Absorbs W-13 and 4.70. |
| W-21 Strict mode's guarantee in full | keep, waiting (1.D1) | F-6 is strict mode's intended design. |
| W-22 One answer, one rule | keep (order 7, in the next full build) | C-1/F-1, one function for a MethodInstance's mode and owner: six places become one (state §4's "next step"), less code. 2.30 by E-new-b. Absorbs E-44 from W-11. |
| W-25 The performance model's gaps | done | L-20 retired and L-16 narrowed (TraitWorld 8ff6ca1). C-14 and C-3 go to PE-4. |
| W-27 Traits in Julia's type system | keep (last on the language) | Absorbs 2.36 and 2.31's item on `where` variables that conform. |
| W-29 Tuples of traits everywhere | keep (order 9) | The user's language work. |
| W-30 TDE's right-hand side as a tuple | keep (after W-29) | — |
| W-31 A value seen through the traits it entered with | keep (after W-30) | — |
| W-32 NetworkDynamics port | keep, paused | The user (2026-10-27): "Leave ND.jl out for now". |
| W-34 SciML restructured as traits | keep (order 8): the SciML port | Absorbs W-8, W-36, W-37 (each built when a move needs it, by the port's ground rule), E-159 to E-161, and X4. |
| W-35 Porting strategies for Makie and DataFrames | merge (split) | Makie's half into W-70: W-60's memo §1.2 is its architecture. DataFrames' half waits with W-14. |
| W-36 A bounded method of a new shape on another package's function | merge into W-34 | Move 3's prerequisite (L-3). |
| W-37 Block forms of a family; a trait's parameter in a default | merge into W-34 | T-57 and T-2, built when a move needs them. |
| W-38 The ownership check of a family without a block | keep (order 3) | Correctness of ownership (T-62), small; with W-67. |
| W-51 The fresh-eye reviews' text fixes | merge into W-61 | Document work. |
| W-55 A key's field type is the declared type | keep (order 3) | Unblocked by 1.59; with W-67, one run of the suites. |
| W-56 Concrete evaluation recording its dispatches | to PE-7 | Deferred already. Considerable runtime complexity; W-57 is the principled route. |
| W-57 Base's type-introspection layer | keep (order 5) | E-167 (2) first (minutes): it decides whether parts 2–3 continue (4.66). |
| W-58 Load and first use of a large trait world | done | E-168 to E-186 done. The findings go to W-61; the directions are W-60, W-66 and the ports. Its status line still names E-177 as next, which is done. |
| W-60 A lean trait core that keeps the old APIs | done | The memo's revision 2, and X7, X1, X5 (E-182 to E-184). X4 goes to W-34, X3 to W-70. |
| W-61 Wrap up before the large ports | keep (order 1) | Absorbs W-5, W-51, 1.16, 2.c8 to 2.c10, and the close of W-58. |
| W-65 This cleanup | done when applied (order 2) | — |
| W-66 The facts-keyed cache | keep (order 6, then the build of order 7) | Its smallest experiment (origins recorded for the trait demonstrators, no Julia change) first. The Julia change goes in the next full build. Its cheap validation needs 1.D1. It absorbs 2.73's facts images without edge validation. |

**New work items** (the next free numbers when applied; W-66 is taken):

| W | Work | Source |
|---|---|---|
| W-67 | **TraitWorld fixes adopted by this cleanup**, with tests: <br>- the member check counts stakeholders' methods only (1.64, 4b.F3's acceptance case); <br>- the late-override message (1.17); <br>- `Vector{<:X}` refused with a message naming the collection bound (2.11); <br>- generic predicates as patterns only, and the test that computes one (2.c2); <br>- `TraitBoundError` listing the declared implementations (3.do2b); <br>- the compiled-mode warning for a `Callable` without a method (2.20); <br>- F-8's check marked as expected under `all` (2.R-b); <br>- probes for 3.bn6 and 3.do2c; <br>- TraitMakie's validated colour and marker names (4.68). | this proposal, under the user's rule |
| W-68 | **The second spelling removed:** `@trait X{R}`, `project(t) = …` and the messages that name them (T-11, T-12, T-15, L-7); TraitWorld's precompile workload; the 23 traits in its tests. It removes code. | 2.c7, 3.dc13; state §6.2 lists it for deletion |
| W-69 | **The setting in a package image's key** (F-7), in the next full build. | 2.R-a |
| W-70 | **The Makie port** (W-60's memo §1.2): X3 first, the waist test with an unchanged upstream recipe; then a `PlotCore` slice for the workload (E-183: 6.1% of Makie's lines). For the user to confirm. | W-61 ("then the ports with W-60's memo"); W-58 ("the porting architecture for Makie"); W-35's Makie half |

**The proposed order:**
1. **W-61:** the wrap-up, documents and claims (absorbs W-5, W-51).
2. **W-65:** this cleanup applied.
3. **Small TraitWorld fixes, one run of the suites:** W-67, W-55, W-38; then W-68.
4. **W-9:** the correctness checks (Base's tests overnight, alone).
5. **Performance worth investigating:**
   - W-57's E-167 (2) (minutes);
   - W-7's bisect (E-new-c);
   - W-17's calls (E-new-d).
6. **W-66's smallest experiment** (no Julia change).
7. **One full Julia build:** W-69, W-22 (with E-new-b), W-66's origin records; with 1.D1's pieces if the user takes it up.
8. **The ports:** W-34 (SciML) and W-70 (Makie).
9. **The language:** W-29, then W-30, then W-31; then W-27.

Waiting for the user: W-21 (1.D1), W-19 (with W-13), W-32, W-14.

Steps 5 to 7 can run beside the ports' work on paper (X4's design).

---

## 4. The further performance explorations log

A proposed new file, `writeup/record/performance-explorations.md`. Its text follows.

> # Further performance explorations
>
> Performance work that the rule for performance work does not take up now ([decisions](decisions.md) §5). Each entry says what it is, what was measured, why it is not pursued, and what would make it worth pursuing. The work queue ([`todo.md`](todo.md)) holds the performance work that is pursued.
>
> **The rule** (the user, 2026-10-27; in full in decisions §5): pursue principled architectural improvements that facts and traits enable, and defects that facts and traits reveal with an impact of 20% or more, fixed without a significant increase in complexity. Slowdowns where trait or facts code should conceptually be as fast as plain code, or faster, stay in the queue as worth investigating. Tweaks that give minor speedups at a considerable increase in complexity are not pursued.
>
> **How to use it:**
> - Each entry has an ID, `PE-n`, stable and never reused.
> - An entry returns to the queue as a W-item when its trigger is met. Its row then says so, with the W-item; it stays.
> - Numbers cite their experiment (E-n) and build; the current numbers are in [`../design/evidence.md`](../design/evidence.md).
> - An alternative that was built and then set aside is also in [`../design/alternatives.md`](../design/alternatives.md), with the reason.

| ID | What | Measured | Why not now | Worth pursuing when |
|---|---|---|---|---|
| PE-1 | **Validation remembered for an unchanged environment:** a chain key in the runtime; validation's outcome per image recorded and reused when the same images load after the same predecessors (W-64; [the note](../plans/2026-10-27-remembered-validation.md); julia-1.13 branch `w64-remembered-validation`). | E-185: validation about 1.4 s of stock's load. E-186: the load in U 3.74–3.90 → 3.11–3.13 s, in C 4.31–4.34 → 3.53–3.54 s; the session about 0.5 s shorter (julia-1.13 f1866b9d4e). | Not enabled by facts or traits: it is plain Julia's loader. A runtime change for a moderate gain; set aside by the user ([alternatives](../design/alternatives.md), "Validation remembered"). | W-66's origin check is built, and the validation of plain code is still the largest term of a trait world's load after the ports. Or as an upstream proposal, on Julia's own priorities. |
| PE-2 | **An environment image of the whole stack** (SciML and CairoMakie in one system image, needing neither activation nor validation; open issue 73). | E-170: could not be built on this machine (more than 38 GB of memory and swap). | Deployment, not trait-enabled; infeasible here. | A machine with the memory, or a system-image builder that fits, to measure the ceiling it sets. |
| PE-3 | **Beyond the `Dynamic` split, other than the table:** <br>- recompiling the caller in the background with the observed types (compiler §1.6, §3.3, Optional; the user, 2026-10-20); <br>- a witness carried in the value; <br>- a longer split; <br>- an 8- or 16-way per-site cache; <br>- the split over the method table at plain run-time sites; <br>- type feedback. | E-145: a split over the observed hot types is 3× faster only for one multiply on data in the cache, in skewed mixes; 1.4–2.1× for a heavier body; 0.8–1.8× on large data. E-164: with the table, at 64 types, the copy 8.8–8.9 ns and the view 17.6–18.8 against plain's 96–101 ns. Proposed and parked: E-128, E-129, E-132, E-133. | Beyond the split, trait code already beats plain code. Each option adds a tier or a cache: considerable complexity for gains in narrow mixes. | A port's hot site beyond the four implementations whose table call is 20% or more of its loop; or plain run-time sites on a port's hot path that trait code cannot remove. |
| PE-4 | **The split tables and the per-site cache:** <br>- the table's pointers compiled ahead into the declaring package's image (compiler C-14); <br>- entries kept valid across unrelated method definitions (C-3); <br>- the per-site cache's entries with an open `max_world`, and its size (W-12). | C-14: about 8 ms per signature and type at its first use (E-145). C-3: one miss per cached site after any method definition (not timed). | No first call or session is shown slower by 20% from them. | A port's first-use profile where the table's pointers are 20% of a first call. W-66 may cover C-14, since a facts-keyed cache keeps the targets. |
| PE-5 | **`return_type` after loads, and upstream's residue under `all`:** <br>- red-green revalidation of cached `return_type` answers after loads (compiler §1, the second half of W-11; E-45 its ceiling); <br>- upstream CSV + DataFrames after nine loads under `all`, 369–386 ms (open issue §4.10): `CSV._parse` compiled again because SparseArrays' `vcat` wins at `vcat(::Int64, ::Vector{Int64})` (320–334 ms), and the plain inference behind run-time `return_type` (45–63 ms). | E-142 (julia-1.13 3b8085c222); E-163 (502 and 431 ms under `all`, 26a407d988). | Both are plain Julia's behaviour by design. `return_type`'s answers are plain inference's. A winning method is followed under either ownership rule outside strict mode. `all` is a test bed. The remedy for the `vcat` is upstream: SparseArrays' concatenation methods for sparse arguments only. | The same residue in the product setting on a port's path, at 20% or more of a session. E-182 notes that a full `PlotCore` may reach SparseArrays' `vcat`. The differential test of the answers (E-44) is correctness and stays in W-22. |
| PE-6 | **`Dynamic{X}(x)` at a run-time site in plain code** (a comprehension over a `Vector{Any}`): Julia's per-site cache refuses calls whose function is a type (`src/gf.c`, `call_cache_exact`). | 102–108 ns per call (open issue 31; E-144). The trait way, `collect(DynamicItems{X}(v))`, costs 2 ns per element. | Plain Julia's cost for any type constructor at a run-time site, not trait code's. | A port whose hot loop must build `Dynamic` values from plain code. Then a per-site cache matched on the function object is a general Julia improvement. |
| PE-7 | **Concrete evaluation recording its dispatches** (W-56): a call with asserted effects over run-time sites evaluated concretely, while the runtime records each dispatch it makes as an edge (a recorder in `gf.c`, a full build). | Its review found it unsound as drafted: static calls and plain code escape the recorder ([the review](../reviews/2026-10-27-w56-recorded-concrete-evaluation.md)). The regression it targeted is E-162, which W-57 addresses. | Considerable runtime complexity. W-57, Base's helpers on builtins and `invoke`, is the principled route. | W-57's withdrawn-assertion log finds a hot asserted helper with a real method-table dependency at non-constant types, costing 20% or more (open issue 69's trigger). |

---

## 5. What applying the proposal would change

### Files and sections

- **`writeup/open-issues.md`:**
  - §1 holds 1.D1 (U) and 1.D2's pointer. The (E) items 1.19 and 1.65 move to 1.D1's paragraph.
  - Every (A), (C), (K) and (M) item moves to "Closed items", under its number, with the resolution and its link. The (E) item 1.77 closes with E-182; 2.30, 3.do2c and 4.66 stay until their experiments run.
  - A new §6, "To revisit with the ports": 2.6, 2.8, 2.9 (units), 2.10, 2.12, 2.13, 2.14, 4.67, and 2.31's two sub-items.
  - Empty headings go: §1 "From the compiler as built"; §2 "From the acceptance suite and the design of `Dynamic`".
  - Stale text fixed:
    - the header's "as of 2026-10-20";
    - item 61's "Not built";
    - §3's "State (2026-10-19): TraitWorld 227781a, 48 test sets";
    - closed item 74, which sits above the closed items' introduction.
- **`writeup/record/todo.md`:**
  - the statuses of part 3;
  - rows W-67 to W-70;
  - W-7 and W-17 re-scoped, with their sources;
  - W-25, W-58 and W-60 marked done;
  - W-10, W-11, W-12 and W-56 pointing to W-7, W-22 or PE-n;
  - the "Carried over" table's statuses.
- **`writeup/record/performance-explorations.md`:** new (part 4).
- **`writeup/record/INDEX.md`:** the new log under "Where to look for…". CLAUDE.md's table of homes could gain a row ("Performance work not pursued now: `writeup/record/performance-explorations.md`"); that is the user's edit.
- **`writeup/record/decisions.md`:**
  - a row per (A) item, marked "mine, adopted by the cleanup rule (§8)": §1 (1.58, 1.59), §2 (1.56, 1.62, 1.63, 1.64, 2.5, 2.c2), §3 (1.26, 1.57, 2.11), §4 (1.20, 1.60), §5 (1.38, 1.61, 2.R-a), §8 (1.75, 1.77, 4.68);
  - the (K) items that change a reference's text: 2.R-b, 2.27, 2.16;
  - the "Pending" row on small unions retired to history (resolved by closed item 18).
- **The references:**
  - `traits.md`:
    - §3.1 (associated constants);
    - §3.3 (2.1's cost; 2.5);
    - §4.7 and §4.9 (1.64);
    - §4.8 (2.c2);
    - §5.1's status (2.11);
    - §7.1's status (2.16);
    - §10.2's status (1.20);
    - the status index rows "what a generic predicate may say", "`Vector{<:X}` arguments", "opening a kept value at its concrete type" and "no pirates in trait modules";
    - new T- rows for 1.64, 2.11, 2.c2 and 3.do2b until built; T-11 for 1.17 and 2.20.
  - `facts.md`:
    - §2.2's exceptions (2.27 no longer "Open");
    - §6.4 and the status index (2.27);
    - §11 and F-7 (2.R-a);
    - §12.3 and F-8, retired (2.R-b);
    - §2.1, whose last bullet links the retired F-10 where F-20 holds the case.
  - `compiler.md`: the §1 table's "Revalidating cached `return_type` answers after loads" from Planned to Optional (PE-5).
  - `lowering.md`:
    - L-17 retired (2.27);
    - §6's copying layout from Open to Optional (2.3);
    - §4.8's predicate rule (2.c2).
- **`writeup/state.md` §6.3:**
  - the order of work from part 3;
  - "W-57 … not yet built": its part 1 is built (julia-1.13 252edca933);
  - the brief "carried into the queue as W-9 to W-14".
- **`writeup/design/evidence.md` §5:** the diagnosis bullets point to W-7 and W-17.
- **`writeup/design/alternatives.md`:** the options not taken:
  - for 1.20: only winning pirates refused in trait modules;
  - for 1.77: (b), an error naming the `using`;
  - for 2.5: constness per family;
  - for 2.11: copying element by element;
  - for 2.c2: computed predicates;
  - for 2.27: calls in the compiler's world;
  - for 4.68: a validation hook at stores.
- **`writeup/record/experiments.md`:**
  - rows E-new-a to E-new-d;
  - E-128, E-129, E-132 and E-133 marked "parked: PE-3";
  - E-45 and E-58 marked "parked: PE-5".
- **`writeup/intro/porting.md`:**
  - 1.75 (extensions for keys, loading stubs);
  - 1.77 (`invokelatest` at user-facing entries);
  - 4.68 (a type conforms only where each value meets the contract);
  - 2.5 (two traits for mutable and immutable state).
- **`writeup/design.md` §2.2:** one sentence for 1.20.
- **Repositories** (by W-61 and W-67, not by the cleanup itself):
  - TraitMakie and TraitReport READMEs (`JULIA_TW_VIEWCACHE=0`);
  - TraitDifferentialEquations README (the `RESULT` count);
  - a TraitWorld README.

### Stale copies to grep for

Every repository: the design repository, TraitWorld, the demonstrators and `experiments/`. Reviews, plans and session notes are history and stay.

- **Open-issue numbers that close or move:**
  - §1: 13, 16, 17, 19, 20, 26, 38, 56–65, 75, 77;
  - §2: 1–14, 16–25, 27, 28, 30, 31, 36, 37, 38, 72, 73, and "the design and the code disagree", items 1–10;
  - §4: 3, 4, 10, 13, 14, 35, 43, 66–71, 78.
  
  Spellings to search: "open issues §1.19", "§1.20", "item 11", "item 27", "item 30", "item 31", "item 35", "§4.10", "§4.13", "§1.13", "§1.1" (facts §2.2 links bindings there), "§2 item 4".
- **Known citing files:**
  - the references: traits §5.1, §7.1, §10.1–§10.3 and the status index; facts §2.2, §6.4, §7.1, §11, §12.3 and the status index; compiler §1.4, §2.x ("standard libraries as owners"), §5.4; lowering §4.8 (line 217), §6 (line 274), §12 (line 504);
  - `state.md` §1 and §6.3;
  - `design/evidence.md` (§2, §5 and its summary);
  - `design/performance.md` (item 35);
  - `design.md` §2.2;
  - `intro/porting.md` (lines 273, 275, 513);
  - `design/julia-changes.md` §4;
  - `explorations/load-on-demand.md`, `explorations/facts-keyed-cache.md`, `explorations/fast-loads.md`;
  - `record/experiments.md` (the links of E-42, E-62, E-63, E-82, E-103, E-110);
  - the READMEs of `experiments/overnight-2026-10-21`, `experiments/hetero-idiomatic`, `experiments/ttfx`, `experiments/fallback`, `experiments/loadcosts`, and of TraitDifferentialEquations, TraitMakie and TraitReport.
- **Work items that change:** W-5, W-7, W-8, W-10, W-11, W-12, W-13, W-17, W-25, W-35, W-36, W-37, W-51, W-56, W-58, W-60, in `state.md` §6.3, the plans' status lines (W-58's plan, W-60's memo) and the experiments' READMEs.
- **Deviation rows that change:** F-7, F-8, L-17 (retired or reworded); the new T- rows; facts §2.1's link to F-10.
- **The decision log's "Pending" row** on small unions.
