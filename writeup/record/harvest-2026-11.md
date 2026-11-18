# The harvest's notebook (W-162, part 1)

The notebook of the documentation clean-up's reading ([the plan](../plans/2026-11-18-documentation-cleanup.md) part 1 and §9). For agents. One entry per document that goes to the attic, written right after the document is read, in the main session. It carries what the session cannot hold in its context. When the harvest is done it becomes the attic's digest (`attic/README.md`) and the source of `record/context.md`, `design/lessons.md` and the alternatives' chapters.

**An entry holds:**
- *What it was:* the kind of document, who wrote it, on which build, what it answered.
- *Found:* its findings that mattered, as they stood then.
- *Became:* what was done with them: a rule of today's references, an alternative not taken, a mechanism that is gone.
- *Not yet in a current document:* an insight that holds today and has no home yet. Empty for most.
- *For the lessons, for the alternatives:* candidates, marked **L** and **A**, each with the era it comes from.

**The order:** by date, oldest first. Paths are those before the move; after it, the same path under `attic/`.

**Reading the eras.** The mechanisms of the first era (keys, entries and workers, views, trait objects, the package's facts policy) are gone. Its insights that survive are about the problem, the facts rule, ownership, measuring and working. An entry says so where a finding is about a mechanism that no longer exists.

**The running lists** at the end collect the candidates across entries: lessons (L-list), alternatives missing from `design/alternatives.md` (A-list), findings to check against today's documents (C-list).

## Progress

| Batch | Documents | Read |
|---|---|---|
| 1 | reviews and plans of 2026-10-16 and 2026-10-17 (7 documents, 180 KB) | 2026-11-18, in full |
| 2a | the five reviews of 2026-10-18 (255 KB) | 2026-11-18, in full |
| 2b | the seven reviews and five plans of 2026-10-19 (255 KB) | 2026-11-18, in full |
| 3 | the three plans and two reviews of 2026-10-20 (142 KB; the implementation plan by its opening sections and outline) | 2026-11-18 |
| 4 | 2026-10-21 and 2026-10-22: values-carry, what-follows-the-split, tonights-code, porting-guideline, pickup, the two reviews of the traits reference, w34; the NetworkDynamics port (the meta plan and the two explorations in full; the six part-plans and six reviews by summary and verdict) | 2026-11-18 |
| 5 | 2026-10-26 to 2026-10-28: the four fresh-eye reviews of the references; W-40, W-56, W-57; the first-use cluster (ten plans, eight reviews); the ports' design round (eight plans, three reviews). By heads, summaries and every finding's opening; the audit's conclusions and the High findings in full | 2026-11-18 |
| 6 | 2026-10-29 to 2026-11-14: the ports' finish (eleven plans); the turn to unification (eight documents, summaries and High findings in full); the unified build's first week (fifteen plans, sixteen reviews, by summary and findings' openings; dispositions audited apart); the schedule and its end (eight documents) | 2026-11-18 |
| 7 | The explorations and `design-findings.md`: `wrapping-by-facts`, `dataframes-port-lessons`, `ndport-pushback`, `ndport-principled-traits` in full; the others by summaries and section openings | 2026-11-18 |

## Entries

### `reviews/2026-10-16-wrapping-under-keys.md`

- *What it was:* an agent's review of the note on code written without traits (layering: trait wrappers, sealing, calls upward, the invalidation filter in `gf.c`), after keys had replaced representations. TraitWorld `main` 8407e1c, julia-1.13. Three experiments; each claim marked "verified" (a source quote or a run) or "reasoning".
- *Found:*
  - **F1, critical:** the filter skipped invalidations of trait-module code on the premise "no value of an outside type reaches it". Under keys the library is compiled for the user's own type, so the premise was false. The owner redefined its own method and trait code kept the old result (4.0 where plain Julia gave 40.0): a silent wrong result. The 346 tests passed because none redefined an implementation.
  - F2: an implementation written in an ordinary module had no place in the layering.
  - F3: a family conformance over one of Base's abstract types with a default ignored a member owner's later method (trait code "size 3", plain Julia "mine").
  - F4: pirates of Base behind "calls upward" (OffsetArrays' 12 methods and one of StatsBase in Makie's tree) made the promised zero invalidations unreachable.
  - F5: for foreign data only conversion in the library's ordinary layer worked; wrappers that declare conformances are an N×M dependency problem.
  - F7: values a library stores and hands back but never operates on (SciML's `p`) had no category.
  - F10: a package's numbers (`Dual`, `Measurement`) needed wrappers; a ForwardDiff wrapper would seal StaticArraysCore and ChainRulesCore with it.
- *Became:* the filter, layering, wrappers and sealing were all removed days later by the facts rule (nothing is skipped; a stakeholder's definition invalidates). In the alternatives: "Layering and its workarounds", "The invalidation filter", "Sealing, rejected". F3's correction (a default is a method at the family's bound, and Julia's dispatch picks an owner's more specific method) is today's rule for a default ([traits §4.2](../reference/traits.md)). F7 needs no category today: an argument no trait types is the value's type. F10: a membership at several values of an input.
- *Not yet in a current document:* nothing of the design. The method is below.
- **L (the design, era 1):** a mechanism that skips invalidation is sound only as long as its premise holds, and it fails silently. The facts rule skips nothing and needs no premise.
- **L (testing, era 1):** the defect lived in the workflow no test exercised. A suite for this design redefines an implementation at the prompt.
- **L (reviews):** mark each claim verified or reasoned, and say what was run.

### `reviews/2026-10-17-consistency-fresh-eye.md`

- *What it was:* a fresh-eye review of the notes, the decision register and the prototype against each other, after wrapping by facts (session 26; TraitWorld 6bcca9f; code read, not run).
- *Found:* the core was coherent (concrete facts, nothing skipped, pirates followed, a build compiles the plain call). Four things did not fit:
  1. **Concreteness** was opt-in in every text and unconditional in the prototype, stricter than any text said. A decision's rationale ("a `DataFrame` cannot conform") rested on the prototype's behaviour. The argument that holds: a `Vector{AbstractVector}` column is a run-time site into native code that loads invalidate; `Vector{Dynamic{Column}}` dispatches into code compiled by facts per type.
  2. **Ownership** is of the method as written, so an abstract type's owner is no pirate at a subtype. Then "an unrelated load never changes compiled code" has one exception: that owner's package extension, triggered by an unrelated package.
  3. **Facts at non-public functions** (session 26) contradicted the rule on pirates: extending another package's non-public function with one's own type is legal Julia. Resolution offered: make such a method a pirate unless the definer owns the function, and leave Julia's own modules out.
  4. **A late override** was both refused (keys) and a fact that recompiles (facts).
  - Also: the register contradicted itself in four rows; numbers disagreed between documents; an experiment on native code (E2) was presented as evidence about code compiled by facts.
- *Became:* (1) concreteness per parameter ([traits §14](../reference/traits.md)). (2) the stakeholder rule of today; the exception is to check (C-1). (3) dropped then (alternatives: "Facts at non-public functions, dropped"), and back in November as owner-only functions (the next iteration's D-9, GT-23) in just the form of the review's resolution: declared by the owner, the default for trait modules only, Julia's internals outside. (4) decided as refusal then; gone with keys: today a later method is followed and invalidates, as any method.
- *Not yet in a current document:* that D-9 is the return of an idea dropped for want of an ownership rule (C-2: the alternatives' entry should say so).
- **L (the record, era 1):** "Prototype: yes" in a register is a claim to check against the code. The Deviations tables exist because of this finding.
- **L (decisions):** a decision is recorded with the argument that holds, not the one at hand when it was taken.
- **L (evidence):** a number says which code it measured (now rule 5 of `CLAUDE.md`).

### `reviews/2026-10-17-decisions-1-and-4.md`

- *What it was:* a review of what two decisions the user leaned to would break: concreteness opt-in and narrowed to the key; a late override refused. Probes on the patched 1.13.2.
- *Found:*
  - The prototype's concreteness rule matched no text (four different behaviours for four forms of declaration).
  - **The grain per trait is too coarse:** the ODE port needs "the state's type concrete, the parameters' type free" in one trait. Per parameter is the natural grain.
  - An abstract key is sound but moves hot code silently into run-time sites; it must be reported.
  - **Probe v:** a family conformance with a default, then a method for one member: trait code returned the default (4), plain Julia 100. The same defect as F3 of the review a day earlier, still there.
  - Refusing a late override was coherent only because the design fixed things at the declaration (a witness, a shared worker, values already kept). Its price: a supertype owner's legitimate method is refused or not by load order; no path at the prompt or under Revise, as with a struct's fields.
- *Became:* concreteness per parameter and for `Self` (W-28; [traits §14](../reference/traits.md)). The refusal went with keys and workers. Under traits as abstract types a later method is Julia's dispatch, and it invalidates as a method does ([compiler §5.5](../reference/compiler.md)); the load-order dependence and the missing interactive path went with it.
- *Not yet in a current document:* nothing.
- **L (the design, era 1 to 2):** what a design fixes at a declaration it must then defend by refusals, and the refusals depend on load order and end interactive work. A decision kept as a fact that a later definition invalidates composes. Unification removed three such fixed points (the witness, the key, the kept view).
- **L (the record):** one defect found by two reviews in two days was fixed by neither. A finding needs an ID and a home the day it is made.

### `reviews/2026-10-17-demonstrators-fresh-eye.md`

- *What it was:* a fresh-eye review of the three demonstrators' claims, baselines and methods (session 27), with a small experiment on which CodeInstances the plain baselines lose.
- *Found:*
  - **B1:** no row measured a session at the REPL, the interactive case. With REPL loaded first, the first new key cost 5.9 s.
  - **B2, the attribution:** the plain baselines lost only abstract-signature specializations below `@nospecialize` or `Any` entries. A plain baseline hardened at those barriers (`invokelatest`) was never run, so the gain could not be told apart from where the barrier sits. "The honest claim would then be that traits place the barrier systematically and check it, where plain Julia needs the programmer to know each site."
  - S2: a per-user "view cache" stood in for "code stored with the package that owns it".
  - S3: workloads had been extended until they covered the measured calls; a 300 to 700 line library with an exact workload was compared with SciML, Makie and pandas.
  - S4: a comparison not like for like (`describe` against a hand-written summary).
  - S5: claims with no row behind them (compiling ahead, cliffs reported, threads, edits, composition at scale).
  - S6: READMEs naming modules that did not exist, "about 2,500 lines" for 691.
  - S7: single runs; the same session 21.2 s one day and 15.7 s another, 30 % of noise.
- *Became:* the sessions at a REPL (E-390), the edits (E-379, E-391), twenty packages each adding a member in five orders (E-377, E-378), upstream's full packages as the baseline (the forks; E-392). The user's rule on workloads (2026-11-08) and rule 5 on what a number says are in `CLAUDE.md`. The attribution question was answered by taking the two apart: the facts rule is the barrier placed systematically, measured on a package compiled by facts as it is (E-392), and traits are what makes it cheap.
- *Not yet in a current document:* whether a plain baseline hardened by hand was ever measured (C-3). If not, "not shown" should say so, or the row is cheap to run.
- **L (measuring, era 1; each still holds):**
  - measure the case the claim is about (a REPL session, not a script);
  - run the control that isolates the claimed cause;
  - a workload fitted to the measured calls proves nothing;
  - compare like with like, in scope and in task;
  - every headline carries its build; a number below the noise floor is not a difference;
  - a README's scope is checked against the tree.

### `reviews/2026-10-17-demonstrators-under-facts.md`

- *What it was:* the demonstrators' rows checked one by one after wrapping by facts (session 26), each marked valid, restate, remeasure or done; then an order of work.
- *Found:*
  - The metric for loads changed from "invalidations skipped by the filter" to "instances compiled by facts that a load ends, 0 expected".
  - **TraitWorld's own `show(::IO, ::Type{…})` methods invalidated CSV's read path and Base's exit hooks: 1.0 s.** "A trait-world package must not invalidate the plain world."
  - The slow load of patched images was the library's own hooks, not the Julia piece suspected.
  - **The user's principle (session 26):** prefer features and patches in Julia, and fixes in TraitWorld, over workarounds (a combination cache, a workload added to another's package, a cache standing in for a missing Julia piece). "About 1 s from process start to PNG is the bar against Python's 0.6 s."
- *Became:* the metric is today's (E-376). The `show` methods became a registry of type printers. The principle is `CLAUDE.md`'s "principled solutions".
- *Not yet in a current document:* the pattern below.
- **L (the design, eras 1 and 3):** a trait library's own methods on Base's functions are the first thing that ends plain code. `show` methods in October; operations as methods at sets in November (GT-11, 208 plain instances). Both times the fix took the method out (a registry; an entry of the contract, E-498). A new library method on one of Base's functions is checked with the late-load count before it stays.
- **L (measuring):** profile before attributing a cost to a mechanism.
- *For `record/context.md`:* the user's principle of session 26, and the bar against Python, in the user's words.

### `plans/2026-10-17-policy-in-compiler-plan.md`

- *What it was:* the plan (session 28, on the user's direction) to move the facts policy from TraitWorld's own interpreter into Julia's compiler behind a switch. Three parts: (A) facts as a mode of Julia's inference; (B) a second cache owner; (C) dispatch from facts code to facts code. A go/no-go measurement with its threshold stated first. The results and the user's answers are in it.
- *Found:*
  - (A) was first built as a forked `Compiler` package: no rebuild of Julia.
  - **Its cost under `all`:** BaseBenchmarks, 4,342 benchmarks, geometric mean 1.016 (1.064 without `scalar`); `io` 1.32; 81 benchmarks more than 2× slower. The tails were three patterns: containers of `Any`; abstract element types whose methods share a result type (raytrace 3.5×); small-union broadcasts (229×, then 1.09× once `return_type` answered over concrete splits).
  - Recovery by redesign: a closed set written as a `Union` equal to plain; a trait with `Dynamic` 3× plain's `isa` branches in a hot recursion. Hence the split at the call site.
  - The user dropped sealed functions and sealed abstract types: "A closed contract is a trait, not a sealed abstract type."
  - The user's answers: a slowdown is tolerated if a redesign with traits recovers it; stock Julia is dropped; `all` is a test bed, not a user setting. So (B) and (C) were built: a module option, an owner `:facts`, the runtime's entries for facts code.
- *Became:* the facts mode of [compiler §1 and §2](../reference/compiler.md): the policy per method, the module option, the test bed. On the unified line the owner `:facts` became a policy bit on the CodeInstance. `design.md` still quotes the julia-1.13 numbers for `all` (1.037, tails to 27.8×): to measure on this build or take out (C-4).
- *Not yet in a current document:* sealed abstract types and sealed functions as an alternative dropped, with the user's sentence (C-5: the alternatives have "Sealing, rejected" for packages; check for this one).
- **L (method):** try a mechanism in the cheapest vehicle that can answer the question (a forked package before a patched build), and write the threshold before the run.
- **L (the design):** under facts the cost is concentrated in three shapes of code, and each has a rewrite that recovers it. The claim "tolerated if a redesign recovers it" came from this measurement.

### `plans/2026-10-17-dataframes-traits-plan.md`

- *What it was:* the plan for the fourth demonstrator (session 27, on the user's request): forks of Tables, DataFrames and CSV at their exact released versions, with traits; a falsifiable claim; a session of twelve steps against pandas; milestones M0 to M12. Written as the answer to the fresh-eye review's B1, B2 and S3.
- *Found:*
  - **Where upstream compiles per schema or loses code, with file and line** (its §3). This is about plain Julia and still holds:
    1. a package extension that adds methods to another package's internal functions (CSV's extension for InlineStrings; DataFrames loads InlineStrings; `CSV.File` 0.19 s alone, 2.46 to 2.53 s with DataFrames loaded);
    2. types passed as values and dispatched on at run time into native code;
    3. `Vector{AbstractVector}` storage with a function barrier per column;
    4. specializations per tuple of column types (group, sort, join);
    5. types per schema (`Schema{names, types}`, generated functions);
    6. `@nospecialize` barriers as the cure: they bound compile time, and every call behind one is a run-time site into native code that loads invalidate;
    7. printing through a generic table printer at abstract types.
  - **The shape of the port:** forks, not rewrites, with upstream's names and UUIDs, so upstream's suites are the bar ("a port that fails the upstream test suites is not a port"); adoption one function at a time; storage typed by the trait; an extension becomes a membership; a user's closure never becomes a key (a `Callable` per signature).
  - **The falsifiers,** stated first: a step above 1 s; any instance lost to the load matrix; and "upstream on the same patched build within 1.5× of the forks: then the gain is the Julia patch, not the traits".
- *Became:* the forks (`forks-unified`), their session of 26 steps with digests equal to upstream's, upstream's suites as the bar (E-302, E-305, E-373). The third falsifier became the round's strongest result: upstream compiled by facts as it is does its first work in 1.9 s against 4.1 s plain, and after unrelated loads is ahead of the port (1.7 s against 2.2 s; E-392, GT-8).
- *Not yet in a current document:* the seven shapes as a checklist of what to look for in a package before porting it (C-6: compare with `intro/porting.md`). How the claim of "the session in 1 s" stands against today's 2.6 s is to be said plainly somewhere (C-7).
- **L (method):** state the claim so that it can fail, and name the control that would show the gain is not the design's. Here the control carried the result.
- **L (the ports):** upstream's own test suites are the bar of a port; same names and UUIDs make them run unchanged.
- **L (the problem):** the seven shapes above.

### `reviews/2026-10-18-decisions-revisited.md`

- *What it was:* an independent review of all 87 rows of the decision register (session 29), on the user's question: "look at every recorded decision and see if they recommend to change any of them given what we know now, and in the name of conceptual simplicity." TraitWorld 47e4274. One experiment (redefining a struct on 1.13).
- *Found:*
  - **The core is right and small:** a trait is an abstract type with a declared, checked contract; membership is declared; compiled code depends on the method table only through facts; ownership names who can change a fact; a pirate that would win is refused (strict) or followed (default).
  - **What had grown around it was of three kinds:** mechanisms that existed only because the policy lived in a package on stock Julia as a foreign cache owner (view caches, a frozen compiler world at 29 call sites, a system-image prototype, trampolines, 13 environment switches); concepts with a second spelling or a half nobody used (`Callable` with two modes, four spellings of concrete mode, named implementations); a rule that only restated Julia's behaviour (rule 4).
  - **The method:** `grep` over every demonstrator and fork for each concept. No port used a `Callable` bound, the compiled mode, `conforms`, `Like{t}` beyond `Self`.
  - **Ten changes,** among them: three rules instead of four; one `Callable` with one mode; strict mode as one decision in two tiers; "`Dynamic{X}` holds the user's object… the package's spelling of 'a value of abstract type `X`'… Once membership is subtyping, `Vector{Plot}` holds exactly that without a wrapper"; a fact signature defined once; a late override answered by redeclaration in a new world, as Julia 1.13 redefines a struct (verified).
  - **Decisions that jointly imply something unrecorded,** for instance: a trimmed build switches the facts mode off; `all` as a test bed gives strict mode its object back.
- *Became:* the references of 2026-10-19 took this shape. A fact signature has one definition ([facts §3](../reference/facts.md)). `Callable` is one contract (and since 2026-11-15 a contract at the box). The sentence on `Dynamic{X}` became literal with traits as abstract types on 2026-11-06. The register's history rows went to a "Superseded" section.
- *Not yet in a current document:* nothing of the design.
- **L (simplifying):** a concept that no port uses is found by `grep` and is a candidate to remove. Used again for the prune list of 2026-11-15 (four of 148 memberships share a key, E-263).
- **L (the design, era 1):** a mechanism that exists because of where the prototype had to live is not part of the design. When the vehicle changed (into Julia's compiler), sixteen decisions went with it.
- **L (method):** after a pivot, every recorded decision is read again against it. The joint implications are found only that way.

### `reviews/2026-10-18-design-and-fixes.md`

- *What it was:* an independent review of the design after session 28's pivot to the compiler (design repository 0683e27, TraitWorld 47e4274). Three experiments on the patched build. Session 28 has no session note; the review read the git logs of nine repositories.
- *Found:*
  1. **The facts mode as a global setting changes values:** `map(f, Real[])` gave `Vector{Any}` where Julia gives `Vector{Float64}`. The go/no-go benchmark had run in that setting, and no correctness run was made beside it.
  2. **Witness tables broke world age:** an operation on a `Dynamic` through a `@cfunction` pointer ran in the latest world. In a task pinned to an older world it returned 510.0 where plain Julia returned 15.0. A C entry point stores the newest world.
  3. Strict mode had no object under one cache owner; and Julia's compiler exempted TraitWorld by module name (`sealed_call`): a sealed function under another name.
  4. **The four members that got a branch at a `Dynamic` call depended on what was declared before the caller compiled:** "the `max_methods` cliff… in new clothes" (2 ns against 6.6 ns).
  5. Three rule changes lived in the prototype only, flagged "needs soundness review".
  6. The design existed in three layers, each current as of a different session: the notes (26), the register (27), the plan (28).
  - A table gives the status of every earlier finding: the four significant ones fixed, most minor ones not.
- *Became:* (1) `all` is a test bed, and `return_type` at run time has one answer, plain inference's ([compiler §1.4](../reference/compiler.md)). (2) the call-site split in the compiler, and worlds on everything that caches a dispatch answer; memberships have worlds today ([compiler §4.3](../reference/compiler.md)). (3) the product setting: facts code beside plain code; the library compiled by facts. (6) the four references with Deviations tables, written the next day.
- *Not yet in a current document:* whether the split's members today depend on the order of declarations or loads (C-8). GT-7 records that a member joining after a loop is compiled goes through a pointer; the order dependence itself is to check in [compiler §7.2](../reference/compiler.md).
- **L (measuring):** a go/no-go on speed needs a correctness run in the same setting. The mode that passed the benchmark changed what Base returns.
- **L (the design):** whatever caches a dispatch answer carries its world. A pointer through a C entry runs in the newest one.
- **L (the record):** three descriptions, each current as of a different day, is what "one source of truth with a Deviations table" replaced. And a session without a note left its design changes to be reconstructed from git.

### `reviews/2026-10-18-framing-and-motivation.md`

- *What it was:* an independent critical review of the overview's framing and of the user's proposed reframing in two goals. Two experiments. §5 revises it "strict mode first", on the user's direction the same day.
- *Found:*
  - **The experiment `inval.jl`,** eight situations, each on stock 1.13.2 and in facts mode: after a definition, is the compiled caller still valid?

    | What is defined after the caller compiled | Pirate | Stock | Facts mode |
    |---|---|---|---|
    | S1: another package's type and its method of the library's function; the caller calls it on an element of a `Vector{Any}` | no | invalidated | kept (result `Any`) |
    | S2: a third subtype with its method; the caller loops over a `Vector{Shape}` with two methods | no | invalidated | kept (result `Any`) |
    | S3: a new `Real` with its method; the caller maps over a `Vector{Real}` | no | invalidated | kept (the value differs before any load) |
    | S4: the library adds a more specific method of its own | no, a stakeholder | invalidated | invalidated |
    | S5: a pirate that wins at the caller's signature | yes | invalidated | invalidated |
    | S6: a pirate that loses there | yes | kept | kept |
    | S7: a `const` the caller read is redefined | a binding | invalidated | invalidated |
    | S8: another package's type passed as a `DataType` value | no | invalidated | kept (result `Any`) |
  - **"The principal way code gets invalidated is piracy" is false for Julia as it is.** Four of five situations without a pirate invalidate. On 1.12, `using CairoMakie` invalidated 769 method-table signatures, none concrete; 216 of 217 roots were abstract. Invalidation in plain Julia is an open-world problem: an edge at an abstract signature depends on every method that matches, and any owner may add one for its own type. Piracy is what is left once compiled code depends on the method table at concrete signatures only.
  - **So the derivation runs from the guarantee down,** each step forced by the one before: facts at concrete signatures (at an abstract edge there is nobody to refuse); then only a stakeholder or a pirate can change dispatch; then the winning pirate is refused. The default leaves the last step off.
  - **Two tiers, and they differ in kind:** strict is a theorem about every environment that loads; the default is a measurement about the environments tried (837 pirates by the letter in the CSV, DataFrames and CairoMakie stack, none won).
  - **"Never" must name its exceptions:** a stakeholder's edit; a stakeholder's package extension triggered by an unrelated load; a binding redefined; a pirate loaded before the code was compiled.
  - Compiling ahead does not follow from non-invalidation (nothing loads into a binary). It follows from targets that can be listed.
  - Caching needs placement beside validity: the code for a combination must exist in some image.
  - "Compiled once for any type" is Swift's model. Ours: a type that only holds the data shares the library's code; a type that supplies behaviour gets its own copy, once.
  - The first goal has no counterpart in Rust, Swift or C++: none has a JIT with a cache across packages that an open method table can invalidate. The second goal is where their traits live.
  - **What is new over discipline** belongs on the first screen: in a fresh session the plain baselines match; the trait form wins under loads and in checking.
  - The user (2026-10-18): "I am thinking we should work the argument from strict mode first. The fact that it will not be the default comes later. This is a change."
- *Became:* the spine of [`design.md`](../design.md) §2, the argument in four steps and the default after them. Bindings as a dependency class are in the record of compiled code and in the deep class of 2026-11-15. The extension case is G2's stated exception.
- *Not yet in a current document:* the table S1 to S8 itself, the smallest demonstration of the whole argument, plain Julia against the facts mode (C-9: is it in the rationale or the evidence, and does `inval.jl` exist in `experiments`? The review ran it from `/tmp`).
- **L (the problem):** the sentence on the open world above. It is the project's first insight and the reason the facts rule comes before traits.
- **L (claims):** say which tier a guarantee is, a theorem or a measurement; and with "never", its exceptions.
- **L (framing):** lead with what is new over discipline, and with the cost next to the step that incurs it.
- **L (the record):** an experiment run from `/tmp` is lost with the session. (Three of this week's reviews did so.)
- *For `record/context.md`:* the user's words on strict mode first.

### `reviews/2026-10-18-examples-and-demonstrators.md`

- *What it was:* an independent review of every example, acceptance case, recovery case, rewrite and port (session 29), as a catalogue by claim, read against the four-step framing. It applies the user's criterion for the demonstrators: performance goals are not read literally; an import may take seconds if the work after it is instant; badly written code may be slower if the compiler says how to make it fast. No Julia was run.
- *Found:*
  - **The catalogue was broad at the small end and thin where the design rests:** no example of strict mode refusing a real pirate in a demonstrator, none of the fully typed certificate, none of a warning that teaches on badly written code.
  - **The evidence for the framing lived in `/tmp`:** `design.md` cited `inval.jl` (S1 to S8), which no repository held.
  - **Under the user's criterion the demonstrators mostly passed, for another reason than their READMEs gave.** The right rows are the work after `using`, first calls of new closures and types, and work under loads. The rows that chase Python's wall time in a fresh process are the wrong headline.
  - **The millisecond closures are a design idea, not a property of traits:** a declared signature cuts the closure, and the AD tag is labelled by the primal signature. A plain baseline with function wrappers matched them in a fresh session. The trait form adds the check and makes the idea the library's default.
  - About a third of the catalogue was history shown beside current numbers.
  - Ten examples to build first, among them: the plain baselines under `all`; S1 to S10 and the "before"-order pirate as acceptance files; a REPL row per demonstrator with a new type, a new closure and an edit; two workers and the message of the fully typed certificate; strict mode on a real pirate; the extension exception; heterogeneous collections at 2, 4, 16, 64 members.
- *Became:* `experiments/facts/framing/` (S1 to S10, a pirate in each order under both tiers) and `experiments/examples/` (strict mode on real pirates and split-core pairs, a glue extension, heterogeneous collections, errors at definition, warnings that teach, redefinition at the prompt), both of the earlier build. On the unified line: fully typed mode and `fully_typed` ([traits §14](../reference/traits.md)); the fifteen mistakes in both forms (E-362, E-385); twenty packages each adding a member (E-377); edits at the prompt (E-379, E-391).
- *Not yet in a current document:* which of these example sets run on today's build (C-10). The framing cases are the natural first gate of the facts mode.
- **L (evidence):** a catalogue of examples by claim shows the claims with none. A lead claim needs one worked example a reader can run.
- **L (the design):** what looks like a gain of traits can be a gain of one idea that traits make checkable and default (a declared signature at a closure). Say which.
- *For `record/context.md`:* the user's criterion for the demonstrators (workflow over wall time; slower is acceptable when the compiler says how to fix it).

### `reviews/2026-10-18-implementation-shape.md`

- *What it was:* a critical review of the implementation after the pivot (TraitWorld 47e4274, 8,707 lines; the Julia patch; the forked `Compiler`; the forks), asking where "keep it a package" bent the implementation, the measurements or the design. Verified by `wc`, `git`, `grep`, `nm` and one run.
- *Found:*
  - **An inventory of every mechanism by class:** (a) the design needs it, about 5,500 lines; (b) it imitates what the compiler should do, 770; (c) it works around being a package on stock Julia, 2,200; (d) left over from an abandoned design, 250. The facts rules in the compiler were 269 lines; as a package 850, plus caches, warm-ups, a system image and four patch pieces.
  - **P1, the foreign cache owner:** site caches, trampolines, a generator, a frozen compiler world. "The package form… earned its keep by finding the rules… It has now done its job."
  - **P2, the attribution:** "The policy's benefit is trait-independent, and the demonstrators credit it to traits." Plain CSV code reached from trait code kept 661 instances through a load that ended 300 of its native ones. What traits add is the residue: compiled for what the bound sees and not per full type; checked boundaries; readable types; a declared membership in place of an extension on internal functions; targets a build can list.
  - **P3:** `Dynamic` in the package needed an effects assertion that was false in form, and an exemption by module name in Julia's compiler. The split belongs in the inliner; the value should hold the user's object.
  - **P4:** traits as macros, registries and entries at `Any` imitated traits in the type system. It included a reflective re-implementation of method selection ("types first, then traits"), "a soundness surface the compiler form would not have". The review left the type system "for last".
  - **P6:** `all` is a good test bed and a poor user setting; the thesis never needed Base compiled by facts.
  - **P7:** the DataFrames fork's kernels never called the trait's operations (0 uses of `cell`, 7 of `vector(c)`): "The forks validate a function barrier, not a trait."
  - Three copies of the fact rules existed, already diverging.
  - The target: (A) facts as an inference mode, about 300 lines; (B) a flag per method; (C) dispatch from facts code to facts code; (D) the split in the inliner; the library about 5,500 lines.
- *Became:* (A) to (D) were built on julia-1.13 in session 29 and carried to the unified line as the policy per method ([compiler §1, §2](../reference/compiler.md)). P4's "last" came three weeks later as traits as abstract types, which removed the entries, the registries and the imitation of method selection. P2 is the structure of the rationale: the guarantee is the facts rule's, traits make it cheap ([`design.md`](../design.md) §2.3, §2.4), and E-392 measures the first alone.
- *Not yet in a current document:* that a port's kernels must use the trait's operations, or it shows only a barrier (C-11: `intro/porting.md`).
- **L (method):** classify every mechanism of a prototype: needed by the design, imitating the platform, working around the vehicle, left over. When the last three outweigh what they taught, change the vehicle.
- **L (the design, the central one):** the guarantee is the facts rule's and holds for plain code; traits are what makes living under it cheap and checked. Every claim is attributed to one of the two.
- **L (the ports):** a port whose kernels unwrap at once validates a barrier, not a trait.
- **L (code):** a rule kept in three copies diverges; one source of truth holds for code as for documents.

### `reviews/2026-10-19-compiler-implementation.md`

- *What it was:* an independent review of the facts and traits compiler as first built in Julia (session 29; julia-1.13 to f6838f96fc, parts A to D: the facts mode, the owner `:facts`, dispatch from facts code to facts code, the `Dynamic` split). Seven experiments, among them packages through images and trimmed binaries.
- *Found:* the architecture right and mostly sound (one interpreter with a mode; the owner chosen by the method's module; facts code in package images, verified there for the first time). Three things wrong:
  1. **The split compiled wrong code** when inference knew the dynamic value's type and the callee took varargs, which every generated forwarder did. The inliner mapped the callee's arguments onto the split primitive's own. By construction memory-unsafe. The tests missed it because they looked at the code for `(Any,)` only.
  2. **A fold over one of Base's asserted effects broke "identical or error":** the reference said "the same exposure plain Julia has". Plain Julia records the edge under the fold; facts inference recorded none. Fix: fold only where the callee's code itself rests on facts.
  3. `--trim` switched the facts mode off in the build process and not in the binary.
  - Also: dispatch from facts code reached facts code only through codegen's call sites (a splat of a vector, the `invoke` builtin ran plain code). The split's result was typed `Any`: one box per call. The split used the candidates known when the caller compiled, with no edge, so speed depended on compile order; the review offered the alternative "record an edge to the candidate list… invalidation at a conformance: the sanctioned extension point".
  - One rule lived in three pieces of code; the same split was implemented twice.
- *Became:* the split carries the declared result ([compiler §7](../reference/compiler.md)). "Rests on facts" became the G2 predicate and, on 2026-11-15, the deep class ([compiler §3.2](../reference/compiler.md)). One function decides a method's mode and owner. The alternative on the candidate list is what was chosen three weeks later: a membership invalidates as a method does (2026-11-11, GT-1).
- *Not yet in a current document:* nothing of the design. The gates' practice below is for the playbook.
- **L (testing):** a compiler change is tested at the concrete argument types too, and by what the runtime compiled, not by what reflection shows for the abstract signature.
- **L (claims):** "the same exposure as plain Julia" is a claim about edges. Check it by redefinition: plain followed (1 → 2), facts did not (1 → 1).
- **L (the design, eras 2 to 3):** a split without an edge to its members makes speed depend on what was loaded first. The edge was proposed here and adopted with "a membership behaves as a method".

### `reviews/2026-10-19-performance-phase.md`

- *What it was:* an independent review of session 29's performance phase (the note on performance, six Julia commits, the demonstrators' rows before and after). Its own probes on the patched build and on stock 1.13.2.
- *Found:*
  - **A1:** the note's lesson "the optimizer's heuristics assumed the dynamic case" was wrong. The two habits (an invoke widened to the compileable signature; no inlining within an inference cycle) cost plain Julia the same: a varargs wrapper in a recursion through an abstract type, 22.5 ms and 16.8 MB against 0.40 ms and nothing, on stock too. The trait runtime's wrappers made every `Dynamic` recursion hit it. Both fixes are improvements to Julia, "found by the facts build, worth having in stock".
  - A caveat on diagnosis: `code_typed` after the code ran shows the callee inlined, because by then it is cached. It does not show what the runtime compiled in the cycle. Allocation counts do.
  - **A2:** the control's arithmetic was wrong. What the loads cost is the work after them minus the repeated work (992 − 0.8 ms), not minus the first work (992 − 722). And the count of lost code covered eight packages, not Base, where the facts copies lived.
  - **A3:** "the one load-dependent cost left" was overclaimed; four other rows still depended on loads.
  - **A4:** a 2 to 4× regression in the clean case was invisible, because the table's columns never showed the case without loads before the phase.
  - **B1:** facts code that calls the compiler directly holds edges to plain code; the guarantee has that exception.
  - **C:** a headline differenced two harnesses; the platform's load cost (+0.2 s of `using`) was left out beside the work times; single runs; the "plain, open set" baseline was an artifact of `max_methods = 3`: four subtypes is one over the limit, and the trait split stopped at four too.
  - **D3:** a workload extension per combination of three packages is combinatorial and written by hand. The design's own answer: a membership's declaration compiles the declared code for the member when its package precompiles.
  - **Theme 4:** what loads still cost was one standard-library method, SparseArrays' `vcat` winning at `vcat(::Int64, ::Vector{Int64})`. "In strict mode that stdlib method would be *refused*… which makes the case against strict mode as a default as much as for it."
- *Became:* the two optimizer fixes and the other general ones are the first commits of the stack, "changes useful without traits" ([compiler §11](../reference/compiler.md)). D3's answer is measured as E-375: a membership declared in a package puts the code in that image with no workload. The same `vcat` method is still the first of the callees by which a port's code is lost (GT-8), and G2 names a standard library's method as its exception. The sessions' tables count the imports.
- *Not yet in a current document:* the measuring rules below, for the playbook.
- **L (measuring):** a before-and-after table shows the clean case in both columns. A count of lost code covers every module. A difference is taken within one harness. A baseline that sits exactly at a heuristic's threshold is an artifact. The cost of loading the platform stands beside the work it speeds up.
- **L (diagnosis):** what reflection shows after a run is not what ran. Confirm with allocations or the compiled instance.
- **L (the design):** one method of a standard library has been the largest single cause of lost code from October to November. A guarantee's exception can be one method wide and still decide a headline.
- **L (upstream):** what the facts build found wrong in plain Julia is proposed as an improvement to plain Julia, first and apart.

### `plans/2026-10-19-inline-caches-plan.md` and `reviews/2026-10-19-inline-caches-review.md`

- *What they were:* the user asked whether one principled mechanism binds the cache at the `Dynamic` split's fallback and the untyped trait call. The plan proposed world-checked polymorphic inline caches for three problems. The review read the runtime's source and the benchmark's log; the plan was revised the same day, after a profile.
- *Found:*
  - **The plan's diagnosis was unsupported.** The largest tail was one monomorphic site at 270 ns, where the plan assumed 15 to 20 ns for a dynamic call. Nobody had profiled it.
  - **The profile found a gap in Julia's own per-site cache:** it holds leaf signatures only, so a call that dispatches to a method with a `@nospecialize` argument (`push!(a::Vector{Any}, @nospecialize x)`) did a full method lookup each time. Exact-type entries fixed it: 276 → 14 ns; the `collection` group 0.60 of the morning's; plain unchanged.
  - The review's own suspect, a slow path it had verified in the source, was "measured: not reached".
  - "No edges" in the plan conflated inference edges, which the facts rule refuses, with the maintenance of a dispatch cache, which Julia's runtime does itself.
  - The third problem was no cache of dispatch results but a hook by which a package substitutes a call's target: a separate decision, not taken.
  - Precedents corrected: Self's and Smalltalk's gains came mostly from type feedback feeding inlining; V8's megamorphic cache is the design of Julia's; HotSpot has no polymorphic state; CPython's adaptive interpreter (PEP 659) is the closest, with version tags per type.
  - The order of work put a speculative gain of nanoseconds ahead of measured costs of milliseconds and seconds.
- *Became:* the exact-type entries are a change to Julia's own cache, general for Julia. Whether they are in today's stack is to check (C-12). The inline caches were not built (alternatives; PE-4).
- *Not yet in a current document:* nothing of the design.
- **L (method):** profile one case before designing a mechanism for the class. The mechanism was sound and beside the point; the cause was a small gap in Julia's own cache. Even a path verified by reading was not the one that ran.
- **L (ordering):** measured costs per session come before speculative gains per call.

### `plans/2026-10-19-notes-cleanup-plan.md`

- *What it was:* the proposal for the first clean-up of the writeup (the user asked for one "without deleting anything"). It set the layout for three audiences: `intro/` for programmers, `design.md` with `design/` for core developers, `record/INDEX.md` for agents.
- *Found:* four notes of 1,647 lines contradicted the design and each carried two banners saying so; the front doors were stale; nothing existed for programmers; the numbers were spread over six places. Its rule: move only the stale notes, leave a stub at each old path, index everything else in place, because "session notes, reviews, memories and other repositories cite their paths more than a hundred times".
- *Became:* today's layout. The index grew from that rule to 402 lines, and the stubs to sixteen. The clean-up of 2026-11-18 (W-162) reverses the rule on stubs and keeps the three audiences.
- **L (the documents):** an index of everything in place keeps links alive and grows without bound; a move with a path rule keeps them alive too. Both were tried.

### `reviews/2026-10-19-references-consistency.md`

- *What it was:* a fresh-eye consistency review of the four references on the day they were written, with the documents around them. A link checker ran over about 750 links (and was probed with a bad anchor). 6 high, 16 medium, 16 low findings.
- *Found:*
  - One item carried four statuses in four references (Planned, Open, Optional, "Planned as an option"); "Optional" was in use and not in the conventions.
  - One deviation was recorded in two references with opposite content (F-2, C-2).
  - A deviation row existed for a rule not yet decided.
  - Documents still gave precedence to pages already retired.
  - **History inside the references on day one:** piece numbers of an exploration, commits in body text, a fixed bug in a deviation row, dated documents, a label from the old notes ("assumption A3"). "Name the thing, not the piece… move commits to julia-changes.md."
  - Terms with several meanings: mode, entry, owner, boundary.
  - Workarounds written into the reference as advice ("until it is built, write…").
- *Became:* "Optional" is a status; the conventions of `reference/README.md`. The finding on history was not held: by 2026-11-18 the four references carry 727 commit hashes and 294 work items in their status lines (W-162's first count).
- **L (the documents):** a reference drifts back into a build log unless the shape of the status line forbids it. The rule was stated on the first day and lost within a month, because each build added "one more commit" to a line that allowed it.
- **L (the documents):** one deviation has one row in one reference; the other links it.

### `reviews/2026-10-19-writeup-review.md`

- *What it was:* an independent review of the reorganized writeup for its three audiences. The worked example was run; links and counts checked.
- *Found:*
  1. **SparseArrays' `vcat` was called a pirate that strict mode would refuse. By the design's definition it is neither:** Julia (Core, Base, the standard libraries) is one owner, so the method is a stakeholder's. The one diagnosed residue after loads is then "code it depends on changes". The design question behind it: are the standard libraries owners of their own?
  2. **The headline motivating number was misfiled:** CSV's first read at 2.5 s against 0.19 s is not an unrelated package's method. DataFrames loads InlineStrings, which activates CSV's own extension. The facts rule does not prevent it; a membership in place of the extension does.
  - "In every load order" over a row that was 171 ms in one order. Evidence of an earlier build presented as today's. Rounding in the design's favour (0.92 to 1.40 ns as "about 1 ns"). "Proposed for upstream" where nothing was proposed. Two names for one switch. Sixteen `[[TBD]]` markers on pages for programmers. A guide for porters routed to programmers in core developers' terms.
  - The index's table of latest commits "was stale within hours".
- *Became:* the rationale files the CSV number as a package's own extension ([`design.md`](../design.md) §1). G2 names a standard library's method as its exception. The intro's rules (no core developers' terms; current state only) are in `CLAUDE.md`.
- *Not yet in a current document:* where the question "are the standard libraries owners of their own" stands today (C-13).
- **L (claims):** file a motivating number under the mechanism that causes it. The best-known number of the project illustrated the wrong step for a day.
- **L (the documents):** do not copy into a document what one command reports (a head, a count of commits). The copy was stale within hours.
- **L (claims):** round against yourself; "in every order" needs every order.

### `reviews/2026-10-19-references-facts-compiler-vs-code.md` and `reviews/2026-10-19-references-traits-lowering-vs-code.md`

- *What they were:* two audits of the new references against the code (julia-1.13 f13117cd74, TraitWorld 227781a), by reading. The method: every interface named in the compiler reference located by name in the diff against v1.13.2; every rule marked Implemented traced to the code that enforces it; every deviation row checked at its cited line; a list of what was verified as stated. 4 high, 9 medium, 10 low; and 6 high, 12 medium, 11 low.
- *Found, of lasting interest:*
  - **`return_type` had two answers:** the compile-time fold asked plain inference, the run-time route in the product setting asked facts inference.
  - **G2's evidence was not what the references cited.** The control counted only code of the default owner, so it counted no trait-module code. The script that had counted it named an owner type that no longer existed. A cited file did not exist. "G2 is the design's central promise."
  - `invoke` at a declared signature, and `hasmethod`, record edges at signatures that are no fact signatures. Sound by the criterion, and missing from the closed list.
  - The form "a closure's call at kinds" rested on a practice (nobody names a closure's type), not on the lemma.
  - **A method compiled ahead for a member, `f(::T, …)`, was a new method of the library's function and invalidated the untyped entry and every plain caller with an edge to it:** "Declaring one discards nothing" was false in the product setting.
  - Families were not checked at their declaration; a failed `@implement` left methods and records behind.
- *Became:* one answer for `return_type` (2026-10-28; [compiler §1.4](../reference/compiler.md)). The check of G2 across loads counts the facts code (W-15; today E-376). A refused declaration defines nothing. Everything about entries, `conformance` methods and projections went with the earlier library.
- *Not yet in a current document:* whether [facts §3](../reference/facts.md) lists `invoke` at a declared signature among the forms, and states the assumption under the closure form (C-14).
- **L (evidence):** the check of a guarantee counts the code the guarantee is about, and a reference cites only checks that exist and run. The central promise was for some days supported by a count of other code.
- **L (the design):** the third instance of L3 in one week: a method added to a library function for one member ends the function's plain callers. On the unified line this is the rule itself (a membership replays the trait's methods and invalidates as a method does), stated and measured instead of denied.
- **L (method, for the build notes):** an audit of a reference against code has three passes (interfaces by name, rules to enforcing code, deviation rows at their lines) and ends with what was verified as stated.

### `plans/2026-10-19-principled-speed-plan.md` and `plans/2026-10-19-remaining-performance-work.md`

- *What they were:* the order of performance work of session 29 and its status list a day later. The user (2026-10-19): "the focus now should continue to be on principled ways to make everything fast, and as close as possible to established and battle proven designs of other languages."
- *Found:*
  - Each step named its precedent: inline caches (Self, V8); guarded devirtualization (HotSpot's class-hierarchy analysis, .NET); compiling ahead from declared implementations (Rust's monomorphization in the crate that sees both the generic code and the type; C++'s explicit instantiation).
  - **Guarded devirtualization at run-time sites was postponed by the user:** code bounded by traits never reaches those sites; it serves untyped plain code under `all`, which "slower is fine if traits can easily recover it" covers. And "a failed guard is a cliff: that site turns dynamic for good, silently".
  - Built: a `cfunction` that runs in the caller's world; facts code inlined into plain callers (a typed trait call 2.6 → 0.8 ns); a declared implementation's code compiled with the declaring package's image (the first untyped call with a new type 90 → 3 to 4 ms).
  - **"Correctness ranks above every performance item."** Two cases: an image whose output differed once in five runs; and a `const` holding a function pointer in a package image, which crashed in the next session, because the image writer resets pointers only in mutable structs.
  - The measurement round of 2026-10-20 on julia-1.13: BaseBenchmarks under `all` 1.037 with tails to 27.8×; upstream CSV and DataFrames by facts lose 2 of 3,337 instances to nine loads, plain 561 of 4,684.
- *Became:* compiling a member's code where the membership is declared is today's rule for an image (E-375). The numbers of 2026-10-20 are the earlier build's; the unified line's are E-376 and E-392. The inline caches and guarded devirtualization: alternatives (C-15).
- **L (the design):** each mechanism was taken from a named precedent, and the precedent's known failure came with it (a failed guard is a cliff). Naming the precedent is how the failure was seen before building.
- **L (the playbook):** a raw pointer in an immutable struct is saved into a package image as the old session's address.
- *For `record/context.md`:* the user's words on principled and proven designs.

### `plans/2026-10-19-return-type-after-loads-plan.md`

- *What it was:* a plan, by reading the code and profiles, for the 990 ms that upstream CSV and DataFrames compiled by facts still paid after nine loads. It implemented nothing.
- *Found:*
  - **700 ms were plain inference behind `return_type`:** 509 cached answers invalidated by the loads and computed again. The rest was `CSV._parse` compiled again because SparseArrays' `vcat` wins inside it.
  - **`return_type` is unspecified upstream and yet observable** through four of Base's mechanisms: `collect` of a generator (the element type of an empty result and where widening starts), broadcasting, `promote_op`, `flatten`. The design's promise is narrower and exact: in one world, the facts mode's answer is plain Julia's.
  - The invalidation that ended the answers is precise per edge, not per answer. One tree: Unitful's `Colon(::Any, ::Any, ::Quantity)` with 10 roots and 733 nodes, most above depth 35, climbing through functions whose result could not change (`isapprox` returns `Bool`).
  - The winning methods: Unitful's `Colon`, FilePathsBase's `write`, IntervalArithmetic's `promote_rule`, GeometryBasics' `convert`, SparseArrays' `vcat`.
  - **Candidate A, revalidate instead of re-infer** ("red-green", as rustc's incremental compilation and Salsa's early cutoff; Julia's own image loading already checks edges): recompute a stale answer only up to the first node whose result is unchanged. Estimated to save 400 to 600 of the 700 ms. Not built.
  - **Candidate F, the traits route:** every costly site is a `collect` or a broadcast whose element type the library knows and does not write. "Rust and Swift have no `return_type`."
  - Rejected: freezing answers (they would depend on load history); skipping the optimizer for the answer cache (tried: it widens answers); a guarded fold.
  - A differential test was specified first: a corpus of queries, stock Julia as the oracle, before and after the loads.
- *Became:* one answer for `return_type` ([compiler §1.4](../reference/compiler.md)); revalidating cached answers is Optional there (PE-5). Four of the five winning methods are still on GT-8's list of the Base callees by which a port's code is lost.
- *Not yet in a current document:* "declare the element type" as a porting rule with its reason (C-16). The differential test's existence on today's build (C-17).
- **L (the design):** a value decided by inference is the one place where "identical" needs plain inference kept alive beside the facts mode; its cost after loads is plain Julia's own recomputation.
- **L (the ports):** a typed comprehension or a declared element type removes a `return_type` query, in a port as in a plain package.
- **L (evidence):** the same handful of over-broad methods in a few packages ends most code, in October's profile and in November's count (extends L30).
- **L (alternatives):** early cutoff on unchanged results, for answers as for code.

### `plans/2026-10-20-dynamic-and-compiled.md`

- *What it was:* the proposal for one language of trait positions, from the user's words (2026-10-20): "I think all of this points to a unifying language. f(x::Dynamic{X}) for an erased position, and the new f2(x::Compiled{X}) for a static one. Then f(compiled_for(x)) and f2(with_dynamic(x)) override. Importantly these rules can be given without talking about receiver types at all." Its §0 is the rule as the user refined it the same day.
- *Found:*
  - **The rule:** every value in trait code is `Dynamic` or `Compiled`. It gets the attribute where it is first seen through a trait: concretely typed there, `Compiled`; abstractly typed, `Dynamic`. A trait's default overrides (`Callable` declares `Dynamic`); a boundary's annotation overrides that; a caller's `compiled_for(x)` or `with_dynamic(x)` always wins. Inside trait code a value keeps its attribute, "library to library: Values carry. Not redecided."
  - **The precedent, in its §1b:** "Neither language has a mode per bound. The value's own type decides: a concrete value runs generic code compiled for its type; a `dyn` (Rust) or an `any` (Swift) value runs it erased, once. Neither turns an erased value back into per-type code."
  - What the rule absorbed: `Callable`'s two modes, `dynamic by`, the solvers' model mode, "a type that supplies its own behaviour gets its own copy".
  - The user on the REPL: a call on an ordinary global is `Dynamic`; "Repl might bear revisiting later as a special case".
- *Became:* built as W-4 the same day, then values that carry through storage (W-18), then on the unified line "the attribute" with five steps deciding it. On 2026-11-15 the next iteration replaced it by one way to erase: two kept forms, and the value's type decides (D-1; [traits §7.4](../reference/traits.md)). That is the precedent of §1b.
- *Not yet in a current document:* that the rule of 2026-11-15 is the Rust and Swift rule the plan of 2026-10-20 cited beside the rule it then built (C-20: the alternatives' entry "One way to erase: the attribute, replaced").
- **L (the design, eras 2 to 3):** the rule with one decider (the value's own type) was on the page as the precedent while a rule with several deciders was designed around it. It took three and a half weeks, a measurement round and a review of the whole design to come back. A named precedent is tried as the design before a richer rule is built.
- *For `record/context.md`:* the user's words on the unifying language, and on values that carry.

### `plans/2026-10-20-dynamic-compiled-implementation.md` and `reviews/2026-10-20-dynamic-compiled-plan.md`

- *What they were:* the implementation plan of W-4 (375 lines, seven phases; read: its status, phases, scope and outline) and its review (read in full; nothing run). The user (2026-10-20): "Make a detailed implementation plan first. This implementation plan needs to include updating all documents on the website to the intended design. References first, then everything else."
- *Found:*
  - **The order the project has kept since:** the references first, with "Planned" and deviation rows for what is not built; then the other design documents; then the library; then the demonstrators; then one short check; then the documents that state the current state (the teaching pages last, because their examples must run).
  - **The scope, in the user's words:** "Right now we want to implement new semantics, not do performance work… Where you make a choice that you judge performance relevant, record it as a possible performance issue to revisit. Proper measurements will have to wait until we have code idiomatically written to the new semantics".
  - The review: the plan deleted a fast path in phase 3 and measured whether it was needed in phase 5 ("the deletion precedes its measurement").
  - **An erased function compiled into a library's image splits over the library's own members only; every user type takes the fallback.** So what follows the split is no option but a prerequisite for a library that compiles ahead.
  - **`known_type` is false in every interpreted top-level call,** so at the prompt every literal call was `Dynamic`, while the demonstrators' rows wrapped their calls in closures and measured `Compiled`: "E-149 would report no change where the prompt gets a different path."
  - Two representations of one dynamic value met at seams the plan had not listed.
- *Became:* the order of phases is `CLAUDE.md`'s "a decision: first the reference". The scope sentence is the root of recording a slowdown as a tension. The split's members and the table past them: [compiler §7.2](../reference/compiler.md), GT-7.
- *Not yet in a current document:* nothing of the design.
- **L (ordering):** the references first, the teaching pages last; semantics before performance; a choice that may cost speed is recorded, not tuned.
- **L (measuring):** a harness that wraps the timed call in a compiled closure does not measure what a line at the prompt runs (extends L9).
- **L (the design):** what a library's image can split over is the library's own members. A user's type is by construction past the split (see GT-7).
- *For `record/context.md`:* both passages of the user's words.

### `reviews/2026-10-20-heterogeneous-collections.md`

- *What it was:* a fresh-eye review, with seven experiments, of `Vector{Any}`, `Vector{Union{…}}`, `Dict{K, Any}`, `Vector{AbstractFoo}` and `Vector{Dynamic{X}}` under the facts rule, in the product setting and under `all` (julia-1.13). An addendum records the user's reading.
- *Found:*
  - **Trait code pays the `Any` tails in the product setting too,** because every Base method reached from trait code is compiled by facts: Base's `filter!` on a `Vector{Any}` 36.8 ns per element against 1.1 in plain code; a loop over a `Dict{String, Any}` 242 ns and 100 bytes against 2.2 ns.
  - **The cost is not the dispatch.** A run-time site costs what plain Julia's dynamic dispatch costs (17.3 against 16.9 ns). The tails are two things plain inference gives at an abstract call and the facts rule withholds: inlining a callee whose one method is declared at `Any`, and a typed result. One constructor call at `Any` turned `Dict{Any, Any}` iteration from 7 ns into 112 ns: "the cascade of `Any`".
  - Only a fact brings a site back: an `invoke` at the declared signature (0.7 ns), or a guarded direct call at a concrete signature.
  - **"At most four" was not Julia's rule.** Julia bounds a cost that counts the largest union as 2: one union argument of eight types splits into eight facts; two union arguments of three types each do not split (44 ns and 64 bytes, a 45× tail with no `Any` anywhere).
  - `Dynamic` kept its promise for four members, and for an arbitrary four: the candidates came in the method table's order after a load, another order than the image was compiled under. Making a `Dynamic` cost 157 ns.
  - For a user's heterogeneous data the remedy was a copy, and the copy needed a trait.
  - A table of ten options with their precedents (Rust's `Vec<Box<dyn Trait>>` and `enum_dispatch`, Swift's `[any P]` and witness tables, HotSpot's guarded class-hierarchy analysis, Self and V8's type feedback, CPython's version tags).
  - **The user (the addendum):** "we should remember that the facts compiler was for smoothly calling into ordinary code, idiomatic trait code as it would look in Swift and Rust probably would see things differently", and: "TraitWorld needing collections sounds right to me. Vector{AbstractType} is a poor substitute for an Iterable trait and this should be an argument for why we need Traits with facts mode."
- *Became:* BaseTraits, the library's traits for Base's interfaces ([traits §10.1](../reference/traits.md)). Rule 5 of `CLAUDE.md`: a number says whether it measures interop or idiomatic trait code. The split over the first members with a table past them. On the unified line an element of a `Vector{Shape}` costs 2.87 ns against 2.70 for a vector of an abstract type (E-374).
- *Not yet in a current document:* what trait code pays today when it calls Base's generic algorithms on a container of `Any`, the interop number on this build (C-18). The two causes of the tails, as an explanation, belong in the rationale or the lessons.
- **L (the design):** under facts a run-time site costs a dynamic dispatch, as in plain Julia. What is lost is inlining of one-method callees declared at `Any` and the type of the result, and the loss cascades. This is the precise form of "the price of the facts rule".
- **L (measuring):** say whether a number measures interop or idiomatic trait code. The same review reads as an indictment or as the argument for collection traits, depending on that.
- **L (claims):** a limit quoted from Julia ("four") is checked in Julia's code.
- *For `record/context.md`:* the user's two sentences of the addendum.

### `plans/2026-10-20-proving-the-references.md`

- *What it was:* a proposal, on the user's request, for what the demonstrators and checks should do next to prove the design that the references define.
- *Found:*
  - **A conformance suite per reference:** one check per rule marked Implemented, named by its section; one check per deviation, written for the intended shape and expected to fail. "A fix flips it, and the table row is retired in the same commit. A deviation without such a check is a claim nobody re-verifies."
  - The guarantees in realistic stacks: G2 across loads for every demonstrator in three load orders; strict mode in a real stack; upstream's test suites as the strongest evidence for "identical".
  - **What would count against the design,** written down first: a loss under G2 that no named exception explains; a difference on an upstream suite outside the named exceptions; a rule a real port cannot follow without a workaround; a cost that traits cannot recover.
- *Became:* rule 1 of `CLAUDE.md` (a fix retires the row, flips its check, updates the state). The gates of `experiments/unification/` and the examples of `experiments/docs-examples/`. The list of what counts against the design is the ancestor of the goals' "weakest point" column.
- *Not yet in a current document:* whether each open deviation row of today has its expected-failure check (C-19); the build notes can carry the check's name per row.
- **L (evidence):** a deviation without an expected-failure check is a claim nobody re-verifies. Write down what would count against the design before the results come.

### `plans/2026-10-21-values-carry-through-storage.md` and `reviews/2026-10-21-values-carry-through-storage.md`

- *What they were:* the plan of W-18 (done 2026-10-21, revision 2) and its review (read: the three major findings and the outline). The rule is the user's.
- *Found:*
  - **The user on storage:** "I thought of Values carry as just that: It persists through storage… The type ODEProblem has to store the function and if compiled_for(f) is lost on storage this forces us back into the library provided switch (that already exists in SciML). We have just turned today's @nospecialize around rather than having a principled design."
  - **The user on the demonstrators:** "Remember that the Demonstrators follow the design. […] the Demonstrators already built never constrain the design."
  - **The rule as the user closed it:** "Values carry. Annotations provide defaults when a plain value enters trait code. Explicit casts always win."
  - Why Julia can do what Rust and Swift do not: they compile ahead, so a value stored at an abstract type runs shared code through a table. Julia compiles when code first runs, and a function barrier is idiomatic, so a stored value can still select the code compiled for its type at the next bound.
  - The review's F1: a field typed `Dynamic{X}` that converts on assignment silently erases the caller's `compiled_for`: "the library switch the user objects to, moved from a function to a field… One spelling, two meanings." Hence "types never cast".
  - The mechanisms: `Kept{X}`, one concrete type holding the attribute as data; a struct parameter bounded by a trait in place of `stored`.
- *Became:* on the unified line the attribute with `keep` and `Kept{X}`; all replaced on 2026-11-15 by one way to erase, where the wrapper `compiled_for(x)` is a value and passes storage as any value does ([traits §7.6](../reference/traits.md)). The principle survived the mechanism: who decides what is compiled for a value is the caller or a declaration one can read, never a switch inside a library. The sentence on the demonstrators is in `CLAUDE.md`.
- **L (the design):** whether code is compiled for a caller's value is the caller's to say, in the language. A switch the library provides is `@nospecialize` turned around. This held through three mechanisms (the attribute's casts, `Kept`, the wrapper as a value).
- **L (the design):** an annotation that means "a default for values first seen here" on an argument must not mean "convert" on a field.
- *For `record/context.md`:* the three passages of the user's words.

### `plans/2026-10-21-what-follows-the-split.md`, `reviews/2026-10-21-what-follows-the-split.md`, `reviews/2026-10-21-tonights-code-and-w2.md`

- *What they were:* the design of what an operation does for a member past the split's first four (E-145; built on julia-1.13 the same night), its review, and a review of the night's code. The user (2026-10-21): "try to come up with principled thoroughly reasoned proposals, rather than asking me to approve dozens of detailed points. Go ahead and implement things when you reached a satisfactory proposal and flag for later review. Finally the principle of this whole project is: Principled clean solutions that stick to establish best practices and experiences from decades of prior work, adapted to Julia's specifics. No workarounds or hacks."
- *Found:*
  - **Every mature implementation layers three pieces:** a guess compiled inline (inline caches, guarded devirtualization); a constant-cost path for every other type, through a table (vtables, V8's megamorphic cache, witness tables); optionally feedback from the types seen. "Today we have the first piece only."
  - Measured (E-145): the dynamic fallback 40 to 90 ns and an allocation per element at 16 to 64 types; a table 6 to 15 ns in the cache, no allocation, no dependence on order. A longer split is fastest for one multiply and costs 190 KB of code at 64 types: rejected on code size and compile time. A split over the observed hot types pays only for skewed mixes.
  - **The design:** keep the split in front; its last branch is a table of the call's targets, keyed by the value's type, emitted by the compiler. "The type is the index": a Julia object carries its type in its header, as C++ and JVM objects reach their vtables; Rust, Swift and Go carry a witness because their values need not be boxed.
  - **Pointer tables had been rejected (session 22), built (28) and deleted (29).** Each objection is answered by name: world age (each pointer runs in the caller's world), serialization (a session stamp, checked at the probe), races (copy-on-write).
  - The first version composed a "default case" in the library with a compiler predicate. It conflicted with the facts rule (a call at an abstract type is no fact); the author and the reviewer found it independently.
  - **The ABI defect, found by reading:** a typed call through a pointer passes a concrete struct by value in Julia's C ABI. A mutable struct past the split arrived as a copy: identity lost, a mutation not seen by the caller, silently. No check exercised it. Fixed: only isbits values by value.
  - The first use of a type at a call signature cost about 8 ms (the pointer's making).
- *Became:* "a split over the first members, a table past them" ([compiler §7.2](../reference/compiler.md)). The pointer's making per member in each session is GT-7 (18 ms for two operations on today's build).
- *Not yet in a current document:* the alternatives' entry on pointer and witness tables should carry the three objections and their answers (C-22).
- **L (the design):** a mechanism rejected for stated reasons returns when each reason is answered by name. Keep the reasons with the rejection.
- **L (the playbook):** through a typed pointer only isbits values go by value; a struct by value is a copy.
- *For `record/context.md`:* the user's principle, in full; and the mandate to implement a reasoned proposal and flag it.

### `reviews/2026-10-21-porting-guideline.md`

- *What it was:* a fresh-eye review of the porting guideline as rewritten for the NetworkDynamics port. Every example checked against the file it quotes.
- *Found:*
  - "Upstream's methods and the port's can stand side by side" was false for an untyped upstream method (the earlier library's entries).
  - **"Keep plain" does not keep code plain:** code that trait code reaches is compiled by facts, whoever owns it. "Plain means: not in a trait module."
  - **How to make an unchanged package a trait module was missing,** with what it will refuse. Split packages meet it at once: DiffEqBase defines `solve` for SciMLBase's problem types, a function and a type it does not own.
  - **The highest-value, lowest-change pattern was missing:** an informal interface written as generic functions that types extend (Graphs' `nv`, `ne`, `outneighbors`; SymbolicIndexingInterface; RecursiveArrayTools) becomes a trait over the existing functions, and existing types join by their existing methods, as a family over the abstract type.
  - Stored user functions; generated functions with a type per body; keyword-heavy entry points (the ordinary layer builds a concrete options struct, the bounded function takes it positionally); observables of `Any`.
  - Where the facts mode inlines differently, fused arithmetic (`@muladd`) can differ in the last bit without a bug.
  - The guideline stated several rules three times, and copied numbers from a review. Its own governance: a rule becomes guidance once a second port confirms it.
- *Became:* [`intro/porting.md`](../intro/porting.md) in five steps, the first being a package compiled by facts as it is, by one line per module (E-392). Joint owners for split packages.
- *Not yet in a current document:* whether today's guideline has the informal-interface pattern, the options struct for keyword entry points, and the rule of the second port (C-21).
- **L (the ports):** the first trait of a port is an interface the ecosystem already has informally; it costs a declaration and changes no method.
- **L (the ports):** a split package is a pirate by the letter; the design needs an answer for it before the first big port (joint owners).
- **L (the documents):** a porting rule is guidance when a second port confirms it; until then it is one port's experience.

### `plans/2026-10-21-pickup-sciml-validation.md`

- *What it was:* the pick-up note of session 33 (superseded 2026-10-28 by the state page and the work queue).
- *Found, for the playbook:* a job started from the sandboxed shell died with the command, so long builds were started by the user outside it; in the daytime every run was pinned to two cores at the lowest priority.
- *Became:* `env.sh`, `tools-local/build.sh` and the rules on cores by load.

### `reviews/2026-10-21-traits-reference-structure.md` and `reviews/2026-10-21-traits-reference-restructured.md`

- *What they were:* two reviews of the traits reference's level and structure (W-20), on the user's two questions: where does it describe mechanism instead of meaning; and can it be simpler, with a section "how plain values enter the trait world"? Read: the scope, the major findings, the proposed outline and both verdicts. By reading only.
- *Found:*
  - **One spelling, `Dynamic{X}`, had five meanings by position** (a bound with a default; a concrete type that refuses; a kept slot that widens silently; a default for items; a plain type), and no table showed them. "Types never cast" was applied as refuse in two and as widen in one.
  - **The attribute rule the user had stated in three sentences stood in thirteen places,** two of them disagreeing with the fuller statement. The cause was structural: chapters cut by syntactic category (bounds, storage, functions, items) each restate the rule for their case.
  - The body described entries, workers, erased keys, views, pointers and tables, which the lowering reference already held. `Self` was defined through a mechanism.
  - The outline adopted: chapters by rule for everything about values; one table of where a plain value enters; one table of what each spelling means by position; the cost model in one subsection; everything "how" out.
  - After the restructure: a programmer "can now read chapters 5 to 7 in order and meet each rule once"; the reference was 84 lines longer.
- *Became:* the shape of today's [traits reference](../reference/traits.md) chapter 7. The five meanings went with the user's decision of that day and, for good, with one way to erase.
- **L (the documents):** a reference's chapters are cut by rule, not by syntactic category; where one spelling has several readings, one table shows them; the reference says what a user observes and the lowering says how.
- **L (the design):** a spelling that needs a table of five readings is a finding about the design, not about the document (see L40).

### `plans/2026-10-21-w34-sciml-prerequisites.md` and `reviews/2026-10-21-w34-sciml-prerequisites.md`

- *What they were:* the plan of W-34, what the library and the facts mode needed to validate the restructuring of SciML as traits, and its review (21 findings, accepted). Read: the plan's summary and its inventory by move; the review's verdict, findings 2 and 5, and its order. The user (2026-10-21): "Tackle anything that is needed in TraitWorld/Facts to validate the Fable strategy."
- *Found:*
  - **The standing rules for a port:** the port does not change the design; agents may add highly orthogonal features; a change to an existing design goes to the user as an open issue; a Planned part the work really needs is implemented first, and the work pauses for it.
  - **The route, in six moves:** 0, compile by facts as it is; 1, the right-hand side at a declared signature, the problem as a trait; 2, callbacks and the integrator's view as traits, callbacks out of the integrator's type; 3, the algorithms as an open set that each solver package joins, the front end's body in its owner; 4, symbolic access as traits, the `getproperty` sugar plain; 5, the solution as a trajectory.
  - **The method:** an inventory, move by move, of every capability against the references' statuses (Implemented; Implemented and unprobed; Planned; a deviation; not in the design), then one experiment of probes (minutes), then one prototype per move in small packages outside SciML.
  - "Most of what the route needs is Implemented." One gap was outside the design: an algorithm trait cannot name its integrator's type per problem; decided as a driver bounded by both traits at shared parameters.
  - CommonSolve owns `solve`, `init` and `solve!`: a split-package fact that put a deviation on the main path.
  - **The review:** "The central decision of the plan rests on a wrong premise": the form the plan made a prerequisite was already running in the demonstrator, and the plan used it as its own control. And the principled form for a function is `Callable`, checked at every call; a trait method generic in its buffers behind an erased value gives the check up ("which Rust refuses as not object-safe").
- *Became:* the rules for a port are `CLAUDE.md`'s ("the ports find the design's weak points"). The six moves are the plan of the ODE port (`TraitDifferentialEquations-unified`) and the case study of the porting guideline. `Callable` changed on 2026-11-15 to a contract at the box, which keeps "checked where it enters".
- *Not yet in a current document:* the inventory-then-probes method as the first step of a port (C-23: `intro/porting.md`).
- **L (the ports):** before a port, list what it needs against the references' statuses and probe the unprobed forms in minutes; validate an architecture's moves in small packages before the big one.
- **L (plans):** a plan's central decision is checked against what already runs. Here the prerequisite was the control.
- *For `record/context.md`:* the four rules for a port, as the user set them.

### The NetworkDynamics port (W-32): `plans/2026-10-21-networkdynamics-port.md` (the meta plan), `explorations/ndport-principled-traits.md`, `explorations/ndport-pushback.md`, the six part-plans and their six reviews

Read: the meta plan, the two explorations in full. The part-plans (`plans/2026-10-21-ndport-{workload,facts-first,traits,graph,inside-out}.md`, `plans/2026-10-22-ndport-step3.md`) and their reviews (`reviews/2026-10-21-ndport-*-plan.md`, `reviews/2026-10-22-ndport-step3-plan.md`) by status, summary, outline and verdict: about 460 KB of implementation detail on the library of that time.

- **What it was.** The first port of a real stack: NetworkDynamics on SciML, Graphs, GraphMakie with Makie, Observables. The user's goal: "reap the biggest possible benefits of Trait and Facts mode with minimal changes to the code". One workload fixed first (define equations, build, simulate, plot, change the equations, run again), with digests for equality of results and four settings. Then two tracks: outside-in (traits where they pay: the component dynamics behind a trait, the graph trait, the traits per kind) and inside-out (the SciML core wrapped as trait modules from the bottom up, each step free of pirates under strict mode).
- **The ground rules,** which became the project's standing method:
  - the port does not change the design; a Planned part the port needs pauses it and becomes a work item;
  - "make a choice, record the pushback" (the user, 2026-10-22: "The idea is to make a choice and record where the design pushes back against it and then maybe revisit either the choice or the design later. Not to get all choices right from the start.");
  - a function at a time, results equal to upstream at every step;
  - orthogonal features may be added by the agent (the user: "For things like split packages I think you can decide yourself to add features that are highly orthogonal. Don't make changes to existing designs and features though").
- **Found.**
  - **The one change that pays is in the library on top, not in SciML.** The user's component functions reached the `Network`'s type, and through it the problem, the integrator, the solution and every symbolic getter. Keeping the model as a held value of a trait, opened once per batch, makes the network's type the same for every set of equations. New equations then compiled 0.45 to 1.1 s against upstream's 15 s (E-152, E-250).
  - **Wrapping a package as a trait module is three lines, and its hazards are silent.** NetworkDynamics wrapped needed one method in Static.jl: its promotion leaned on Base folding `typejoin`; under the facts rule every `Int * StaticInt` dispatched at run time, 1,500 times slower, the results equal, nothing warned (P3-1).
  - **A plain caller's constant propagation into a wrapped package's `getproperty`** was lost (P6-1): twice the steady state, silently. The user decided that constant propagation crosses from plain code into facts code.
  - **Inside-out under strict mode works as a porting method.** Seven steps up the SciML core; a census of pirates after each load; joint owners (approved and built for it) take the methods that packages split from one core define on each other's types. One true pirate (OrdinaryDiffEqDifferentiation) stays plain.
  - **The per-batch crossing was the steady state's price** (P4-1): 0.8 µs and 13 allocations at first, 36 to 48 ns after two rounds of work in the library; the steady state ended at about twice upstream's, then at 35 times upstream's over the whole session's gain (E-249/E-250: the session 31 s against 73 to 80 s).
  - **An informal interface becomes a trait over its existing functions** (Graphs' `AbstractGraph`, with throwing fallbacks): one family line. Functions that return open iterators need a second function with a declared result (P4-3). The trait's name must not collide with an exported alias (`Graph` is `SimpleGraph`).
  - **What stays plain, and why that is fine:** closed library families (an abstract tree is right), construction-time and metadata code, code dynamic by design (Observables, Makie's compute graph), keyword front ends behind a function barrier.
  - **The reviews of the part-plans** found, again and again, the same kinds of defect: settings sharing one working tree or depot (Julia keeps ten cache files per package, so one setting evicts another's); a check without a control; a timer that reads zero unless switched on; a workload whose second solve starts from the first's mutated parameters; a criterion that cannot be decided; plans stale against results that arrived while they were written.
- **Became.** `intro/porting.md` (0.1a the wrap, 0.2 informal interfaces, A12, B5, B6 "the solvers are an open set"); joint owners (traits §10); constant propagation across the modes (facts §6.3); the table for family members (open issue 48); W-49; the open-set link (open issue 51, option a+); the parametric subtrait (open issue 55); `ndport/` with its README and logs; evidence §3's NetworkDynamics rows. The pushback log is the model for today's "tensions between the goals".
- **Not yet in a current document.** To check (C-24 to C-28): whether today's porting guideline carries the silent hazards with their tool (the dispatch profiler after a wrap); whether the "what stays plain" list is there; whether each pushback entry that is still true on today's build is an open issue, a tension or a guideline entry, and each that is not is in the attic's digest only; whether the port's numbers in the evidence are of today's build or the earlier one (R3); whether P6-2 to P6-5 (strict mode refusing OffsetArrays' `reshape`; extensions rewriting a wrapped core's facts at every load; packages' own `@inferred` tests failing by design; run-time `return_type` answers as a large share of new code) are each recorded as a tension or an open issue today.
- **L:** L53 to L61. **A:** A5 (per-value membership; a trait with input parameters beside `Self`; optional bounded parameters; a witness carried in the held value). **For `record/context.md`:** the port's ground rules in the user's words; the two tracks and why (the user's "inside-out under strict mode" idea); that the user did not review choices 1 to 47 one by one ("I trust the reviewed plan"), the origin of today's rule that the agent's choices are not reviewed one by one.

### The four fresh-eye reviews of the references: `reviews/2026-10-26-{traits,facts,lowering,compiler}-fresh-eye.md`

Read: the traits review nearly in full; the facts review's High findings and M1, M5 in full; the others by their findings' titles.

- **What it was.** Four agents, one per reference, each reading its reference as an outsider against the code, with probes of seconds. Counts for traits: High 3, Medium 17, Low 16.
- **Found, of lasting substance** (all on the facts rule, which today's design keeps):
  - **Lemma O was false for a `Vararg` tail.** `Lib.g(x::Int, y::MyT...)` is its owner's method, and applies at `g(::Int)`, where the owner is no stakeholder. Fix: stakeholders judged at every signature a method applies to.
  - **The asserted-effects rule was per frame.** A frame without run-time sites that calls one with a run-time site kept its `:foldable`; the fold went stale. G1 failed one frame up. Fix: at any depth.
  - **A call that Julia's method matching gives up on** (more matches than `max_methods`) was dispatched at run time with no edge, yet was no run-time site by the definition. Found twice, independently.
  - **`@eval Owner` launders a pirate:** ownership follows the module a method is evaluated in.
  - **A facts answer can be wider than plain inference's** where plain's is `Union{}`.
- **Found, of the references as documents:** sections contradicting each other (who may add a bounded method; where the first-seen rule applies); "Implemented" on things that failed with an internal error; a deviation written into the design text; status lines carrying rules; 94 of 108 code citations by line stale within 40 commits; measurements in deviation rows; "Implemented" not saying whether the source or the build; terms used before their definition; claims about other languages without a source.
- **Became.** Checked today: facts §1 judges stakeholders at every signature and names `Vararg`; facts §8 says "at any depth"; facts §4 makes the `max_methods` case a run-time site; facts §1 and traits §10 say "a method belongs to the module it is evaluated in". The traits findings concern the attribute design, which one way to erase replaced.
- **Not yet in a current document.** The document lessons are the plan's part 5 (status lines, no line citations, no measurements in the references).
- **L:** L62 to L64. **For `record/playbook.md`:** how a fresh-eye review of a reference is commissioned (read as an outsider, check "Implemented" against code, probes of seconds, severity by "a false statement about what is built").

### The first-use cluster of 2026-10-27 (W-58 to W-66): `plans/2026-10-27-{ttfx-sciml-makie,port-architecture-ttfx,parameters-outer-layer,session-cache,facts-keyed-cache,remembered-validation,lean-core-old-apis,facts-first-julia-work,cleanup-issues-and-queue}.md`, `plans/2026-10-28-facts-cache-store.md`, `reviews/2026-10-27-{ttfx-plan,cache-and-port-notes,cache-design,facts-keyed-cache,remembered-validation,lean-core-memo,w58-direction}.md`, `reviews/2026-10-28-facts-cache-store.md`

Read: heads, summaries, every finding's title and opening, the "as built" and results sections.

- **What it was.** The user's question (2026-10-27): "With a large solid trait core that is amenable to cross session caching, there should be no reason that loading+running first simulation+plot should be slow. We could take SciPy + matplotlib as [the baseline]". One day of measurements (E-168 to E-198), three cache designs, an architect's memo for the ports, and eight reviews.
- **Found.**
  - **The baseline.** Python's session 1.45 s; stock SciML with CairoMakie 9.2 s; the trait demonstrators 0.96 s.
  - **A cache recurs only where its keys recur.** Compilation is of three kinds: what repeats in every session; what is keyed on the user's model or data; what is keyed on the call's shape (keyword tuples, a range against a vector). No type of the user's script may sit in a library's keys. Normalize at the entry.
  - **The parameters in the outermost layer only** (the user: "The outermost layer has to depend on parameter type, but inside the solver we only need to see the right hand side that is partially evaluated on the parameters."). Built in TraitDifferentialEquations (E-181).
  - **With a cache, the work after the load is about Python's; the load is what remains,** and the load follows the dependency tree (E-176, E-179). Validation of edges about 34 % of a stock load, activating methods about 27 % (E-185).
  - **Three caches.** Keyed on the environment: built, paid (off-workload sessions 2.4 to 1.07 s and 19.4 to 6.1 s, E-180), retired by the user for one "keyed on facts and their origins". That one: identity by fingerprints, validity by Julia's own validation of edges; its store paused (the vehicle is machine code, open issue 95). Remembered validation: unsound as first written, then set aside.
  - **What is trait-specific and what is packaging.** Lean trees, loading stubs, normalizing at the entry, erasing the user's function: plain code can do all of it. What only the facts rule gives: code that may load early and stays valid through later loads; a narrow declared interface that is checked. A review's blocker: "The direction has no trait-specific hypothesis, and the data so far favour plain code."
  - **Old APIs above a lean core** (the user: keep the user API; "not necessarily the solver and algorithm developer API. Though a compatibility shim would be great"): four layers; old recipes run as upstream's plain code above the core; extensions for keys, loading stubs for functions, entries through `invokelatest` (code loaded at first use is invisible to the rest of the calling function: world age, for plain code alike, E-182).
  - **"Facts first":** rely on what the facts rule guarantees for facts code, instead of making a mechanism work for all of Julia's code. Strict mode then protects code of the facts owner.
  - **The reviews' recurring catches:** a harness that precompiles inside a measured session; `--compiled-modules=existing` loads from source silently when an image is stale; a cache measured on the session that recorded it; the settings differing in five things at once; a registered decision rule whose outcome pointed the other way and was read past; an emulation that recorded compile roots only.
- **Became.** `design/alternatives.md` "Caches across sessions"; `record/performance-explorations.md` (begun here, PE-1 to PE-8); the user's rules for open issues and for performance work (decisions §5, §8); the ports' architecture (TraitDifferentialEquations' two layers, TraitMakie's compat layer); strict mode on facts code (facts §11). The cache across sessions is not built (the user, 2026-11-14); the measurement round carries its workloads.
- **Not yet in a current document.** To check (C-29 to C-32): the three kinds of compilation and "keys recur" in the porting guideline; "trait-specific or packaging" in the goals or the rationale, as the honest form of the first-use claim; the harness's traps in the playbook; that the Python baseline and its workload are in today's registry (R3 makes it the baseline).
- **L:** L65 to L72. **A:** A6 (the three caches, remembered validation, recorded concrete evaluation, the member's builder folded by the compiler).

### `plans/2026-10-26-w40-member-builder-fold.md` with `reviews/2026-10-27-w40-member-builder-fold{,-r2}.md`; `plans/2026-10-27-w56-recorded-concrete-evaluation.md` with its review; `plans/2026-10-27-w57-type-introspection-layer.md`

- **What it was.** Three attempts to recover folds that the facts rule had rightly stopped.
  - W-40: a compiler primitive that runs the library's member check inside inference and fixes the result in the caller's code. Two reviews: a deadlock under the inference lock, records that crash edge walkers, the wrong world, load order, a constant over 256 bytes not folded.
  - W-56: concrete evaluation over run-time sites with the dispatches it performs recorded as edges. Unsound: static dispatch decisions inside the code that runs escape the recorder.
  - W-57, an architect's memo, adopted: the cause is that **Base's type-introspection layer is written as generic calls on values of a kind** (`t.name` is `getproperty(::DataType, ::Symbol)`). A kind is never a fact, rightly: any type's owner may add `f(::Type{MyT})`. So the layer goes onto builtins and `invoke`, with a tool that finds the sites.
- **Became.** The Julia changes to Base's introspection helpers (`design/julia-changes.md`); membership as a subtype relation removed W-40's need at the root.
- **Not yet in a current document.** To check (C-33): the rationale for the introspection layer on builtins, and its tool, in `julia-changes.md` or the build notes.
- **L:** L73, L74.

### The ports' design round of 2026-10-28: `plans/2026-10-28-{dataframes-lean-core,fresh-ideas-sciml,fresh-ideas-makie,fresh-ideas-dataframes,annotation-audit-decisions,sciml-move3-today,x3-waist-slice1,strict-mode-on-facts-code}.md`, `reviews/2026-10-28-{dataframes-lean-core,ports-annotation-workarounds,strict-mode-on-facts-code}.md`

Read: summaries, every weak point's case and rule, the audit's conclusions in full.

- **What it was.** The user (2026-10-28): "Remember that one purpose of the ports is to identify weak points in the design." and "The guiding principle should be principled solutions. If a tweak in the trait design can enable a principled solution in the port architecture, that's the most valuable finding we can have." Three fresh-eye agents proposed an architecture per ecosystem and listed the design's weak points. An audit counted annotations used as workarounds in the ports.
- **Found: the weak points, most of which the later design answers.**
  - **A stored value is seen through one trait only** (open issue 82): a legend, an inspector, a pooled column's fast path cannot ask a stored plot or column for a capability. Proposed: "a kept value is seen through every trait its object conforms to". Today: a value has its type, and every membership of that type holds.
  - **A function at several signatures** (plain, duals of a chunk chosen at `init`): one `Callable` per signature. Proposed: a generic `Callable`. Today: the contract at the box (D-2).
  - **A type conforming at several values of a parameter** (a callback type for every problem): input parameters.
  - **Attributes as a cost model in the wrong hands:** 26 `compiled_for` sites at callers of kernels; a caller that forgets pays twice. Proposed: "open here" at the bound. Today: one way to erase; the callee's signature says what is compiled.
  - **A kept `Compiled` function slower than a `Dynamic` one** (270 against 13 ns).
  - **Types as values** (CSV's cell types), **operations valid only when another says so**, **predicate-based interfaces** (`Tables.istable`), **the member check per view type**.
- **Found: architecture.**
  - DataFrames: compile per cell type, not per column type; layouts are a closed set, so types; capabilities as operations with defaults.
  - SciML: the model is the trait, the problem is a record; inputs vary at three rates (per ecosystem, per model, per call) and the key follows the slowest.
  - Makie: marks are a closed set; a recipe is a stat plus marks; capabilities belong to whoever asks; backends are a minimum plus defaults.
- **Found: the audit.** The user: "Often in Julia code the more principled solution is to fix the inference rather than hard code an annotation. Likewise, marking something nospecialize should be an escape hatch in my opinion." 43 occurrences: 15 fixable in the port, 12 a weak point of the design or the library, 15 a real dynamic boundary, 1 Julia's. What fully typed checks catch early, and what they cannot (compile-time cost, the cost of `Dynamic`).
- **Became.** Open issues 82, 96 to 108; the Planned parts that the unified design then replaced; the next iteration's D-1, D-2 and the input parameters (C-32 of 2026-11-08).
- **Not yet in a current document.** To check (C-34 to C-36): the audit's advice for port authors in `intro/porting.md`; each weak point above against today's reference (answered, open issue, or alternative); the three architectures' one-line principles in the porting guideline's case studies.
- **L:** L75 to L80. **A:** A7. **For `record/context.md`:** the two sentences of the user that became CLAUDE.md's "the ports find the design's weak points"; the user's rule for open issues (2026-10-27): "Is there a principled choice? A choice that simplifies the architecture at little cost? If so adopt that. … Only keep the choices with a well articulated trade-off for me to review."

### The ports' finish on the earlier library, 2026-10-29: `plans/2026-10-29-{makie-finish,sciml-finish,tde-nonlinear-problems,ndport-reactivated,ndport-r1-census,x3-slice4,w84-member-checks-at-load,w88-102-kept-function,w91-callable-entries-cacheable,w92-forks-invalidation,w94-facts-rejected-by-implementation}.md`

Read: heads, results sections, each plan's "Cases for W-83".

- **What it was.** The user's finish lines for the three ports and NetworkDynamics on them ("Nd definitely sits on the ports"), and five small library fixes found on the way. Rules for the work (the user, 2026-10-29): no tweak that unification would make obsolete; fix inference rather than add annotations; where the design blocks a principled solution, a candidate open issue; "if we are beating Python already we don't really need much performance work".
- **Found.**
  - Upstream's user API runs unchanged over a trait core, for Makie's workload (the PNGs equal byte for byte to the core's own drawing) and for SciML's (the session's results identical).
  - An upstream recipe, source unchanged, runs above the core through a hand-over (`stairs`, `stephist` with a recipe child).
  - NetworkDynamics on the ports: a census of the gaps by running (17 items), nonlinear problems with an open set of solvers, then the finish: the session 31 s against upstream's 73 to 80 s.
  - **Every plan ends with "cases for W-83":** where a trait stood beside an abstract type (`Trajectory` beside `AbstractDiffEqArray`, `GraphInterface` beside `AbstractGraph`, `Block` and `Layoutable`, `Scale` on `typeof(log10)`). The ports' code was the evidence for unification.
  - W-94: code "rejected" at load that was not rejected. The log named a fold as a failed edge.
- **Became.** The demonstrators as they are; the porting guideline's case studies; the list of cases that the unification's evidence plan replayed.
- **Not yet in a current document.** Nothing of its own; the numbers are the earlier build's (C-27).
- **L:** L81.

### The turn to unification: `plans/2026-10-29-unification-evidence.md`, `reviews/2026-10-29-unified-build-review.md`, `plans/2026-11-05-unification-synthesis.md`, `reviews/2026-11-06-oc-build-audit.md`, `plans/2026-11-06-traits-are-abstract-types.md`, `reviews/2026-11-06-unified-reference-prototypes.md`, `reviews/2026-11-06-unification-tradeoffs.md`, `plans/2026-11-06-work-plan-under-the-draft-reference.md`

Read: summaries and decision tables in full; the reviews' High findings in full; the rest by their openings.

- **What it was.** Eight documents in nine days that replaced the library-on-a-patched-Julia with traits in Julia's type system.
  1. **The evidence plan** (2026-10-29): unification as three levels (membership in subtyping; one dispatch; one surface), quick runs without a build (E-252 to E-259), gate A. The user: "Okay, given the evidence, we pursue (e). The exploratory note had an everything from 4 components framing. I think the evidence backs this up now. Sealed AbstractTypes make sense but are an optimisation for later".
  2. **A critical review of the build exploration:** High 4, Medium 11. Result edges that revalidate are unsound against Julia's direct-call binding (so: a slot the call loads through); an over-approximating `typeintersect` is the wrong layer for "never fold a negative"; the negative-fold exclusion must be structural (sets inside tuples and unions); membership in subtyping alone is unsound for dispatch until dispatch follows.
  3. **The synthesis plan** (2026-11-05): four sources (the plan, the exploration, the review, an earlier attempt's branch and notes) into stages W-97 to W-104 with thirteen decisions. The user reversed one the same day: "It must be transitive. So A <: B <: C has to imply A <: C."
  4. **The audit of the earlier attempt's branch,** by probes: a type's membership made its type value a member; `Dynamic{X} <: X` held while dispatch disagreed; a member pattern of more than eight variables accepted and never matched.
  5. **"Traits are abstract types"** (2026-11-06). The user: "Unification states "Traits are AbstractTypes" From this it follows that Traits can occur everywhere AbstractTypes can, and that they are parametrized the way AbstractTypes are parametrized, including Trait{<:T} and the like. This explicitly contradicts a number of things that are currently in the reference design. It also should eliminate a lot of the reference design." And: "If the ports have to be substantially changed that is fine. They were built under old assumptions and should be considred informative rather than limitative." The analysis: a trait differs from a closed abstract type in two things only (members may join after their definition; a contract checked at each membership); 18 consequences that need no decision; what goes (trait objects, views, entries, workers, `Kept`, `Compiled`, the first-seen rule, trait modules as the only place for bounded functions); eight choices. The user chose a new reference written from the ground up.
  6. **The draft against the prototypes:** the ports' mechanical changes are small; two High findings (`Callable` by derived memberships needs inference inside subtyping; "bounded by default" refuses the ports' library layer).
  7. **The trade-offs review.** The user: "The original implementation made a lot of progress to our main goal of cutting load times, recompiles, session times, and enabling caching and better type signatures and error messages. … The unification offers substantial conceptual simplifications. The question is what the trade off is and whether they can be recovered later". Found: the guarantee machinery survives nearly unchanged (G1, G2, fact signatures, strict mode rest on the facts rule, not on trait objects); the real loss is the second cache owner's facts copies of Base's code, measured at 0.2 to 0.3 s a session with the slot (E-265).
  8. **The work plan under the draft:** "the premise first, speed later"; keys Optional. The user: "A general thought: Simplifying the design by delaying performance optimizations like keys and guards sounds good. The trade off is ecosystem. If certain performance characteristics are guaranteed that enables to build around them".
- **Became.** Today's four references (written from the ground up on 2026-11-06); `design/julia-changes.md`'s stack; decisions §5 and §9; `design/alternatives.md` (level 2's options, sealing, the unified build's options); the audit tool `experiments/unification/audit/`.
- **Not yet in a current document.** To check (C-37 to C-39): the two-sentence premise ("an abstract type that members may join later, with a contract checked at each membership") as the opening of the intro and the rationale; the trade-offs review's finding (what the guarantees rest on) in the rationale; the Swift, Rust and Mojo lessons per trade-off in `other-languages.md`.
- **L:** L82 to L88. **A:** A9. **For `record/context.md`:** this is the project's second turn, with the user's words above; the earlier attempt's workflow (coordinator, planner, plan reviewer, author, implementation reviewer) and what went wrong in it, for the playbook.

### The unified build's first week, 2026-11-07 to 2026-11-10: `plans/2026-11-07-{w101-the-code-slot,w104-ports}.md`, `plans/2026-11-08-{c32-input-parameters,w121-profiling-campaign,python-speed}.md`, `plans/2026-11-09-{171-declared-results-without-conversion,c57-c81-small-deviations,c82-unmet-match-lookup,compiled-once-equations,io-alternatives}.md`, `plans/2026-11-10-{c78-report-at-declared-supertypes,recheck-at-redefinition,t98-strict-membership-ambiguity,w130-records-at-load,w131-declared-subtype-entry}.md`, `reviews/2026-11-07-{all-representation,basetraits-choices,implementation-day,machine-code-cache-design}.md`, `reviews/2026-11-08-{issue-158-guarantee,unification-review}.md`, `reviews/2026-11-09-{documentation-consistency,io-porting-lessons,performance-day,plan-review-171,plan-review-c57-c81,plan-review-c82}.md`, `reviews/2026-11-10-plan-review-{c78,recheck,t98,w130,w131}.md`

Read: the reviews of 2026-11-07 to 2026-11-09 by summary and every finding's opening; the two `IO` plans by summary and recommendation; the small plans by status. What was done with each finding of the sixteen reviews without a closing table is audited apart (`record/harvest-dispositions-2026-11.md`, by an agent, checked here).

- **What it was.** The unified stack built in days, the ports brought onto it, and each night's work reviewed the next day by a Fable agent at the user's word.
- **Found.**
  - **`All{X, Y}` as an ordinary abstract type** is wrong wherever the code does not special-case it: the typemap, the negative-fold gate and the diagonal rule read `name`, `super` and `parameters` and get a confident wrong answer. A form whose default is "unknown shape" is safer than one whose default is a wrong answer.
  - **The first speed comparison** (E-289): the unified build 7 to 11 times slower, from one cost bug in the walk at activation, not from the design. Its "rare shapes only" path was the normal shape of a parametric trait.
  - **The guarantee "a membership invalidates nothing"** (open issue 158) was paid in plain code's inference: guards whose slow branch widens the result, effects lost at every guarded call. The review's options; the user later chose that a membership invalidates as a method does, and that a membership by neither owner is piracy (2026-11-11).
  - **The speed plan** to Python + 1 s, adopted 2026-11-08, superseded 2026-11-09. The user: "Okay the speed plan goals were too ambitious. We hereby retire all strict speed gain gates we have been working under. We still care about speed but there is no concrete goal to try to achieve, and we are more interested in principled holistic/broad gains enabled by facts and traits rather than in patching details here and there."
  - **The `IO` episode** (2026-11-09). One package's display compiled per stream type at a REPL. A ten-line eraser at the port's display entry fixed it and was set aside as "a step around the design". `IO` was made an open set compiled once by default instead: correct, 2 to 24 times slower per call, a day and six builds. Two Fable plans then: equations type results but only a rule about edges stops the fan-in; a closed abstract type may declare a contract, and erasure is the author's choice at the boundary. Lessons written into the porting guideline the same day.
  - **The night of unsound rules** (the user: "For tonight, Focus on fixing unsound rules and deviations. For each come up with a plan, have a Fable agent review it, and act on the review."): eight small plans, each reviewed, each built with the review's changes.
  - **The documentation review** found status copied across four references and disagreeing, build heads stale in four places, a rule waiting for the user stated as decided.
- **Became.** Compiler §3.3 (the slot), §4 and §5 as they are; traits §9b (`IO`, a closed type with a contract); facts §10 (memberships); `intro/porting.md` 0.4 and the `IO` lessons; `design/alternatives.md` (`IO` as a set, guards, BaseTraits' rejected forms); the retirement of the speed work (CLAUDE.md; decisions §5).
- **Not yet in a current document.** The dispositions audit says which findings have no record. To check (C-40, C-41): the `IO` episode's lesson L6 of its review ("a port's change that follows a rule of the references is the port following the design, not a workaround") in CLAUDE.md's rule for ports or the playbook; the cost bug's pattern (a "rare" conservative path that is the normal case) in the playbook.
- **L:** L89 to L96. **A:** A10.

### The schedule and its end, 2026-11-11 to 2026-11-14: `plans/2026-11-11-{complete-prototype,membership-as-method,membership-as-method-build,membership-piracy}.md`, `reviews/2026-11-11-intro-and-rationale.md`, `reviews/2026-11-12-w141-membership-as-method.md`, `plans/2026-11-14-{cache-across-sessions,measurement-round}.md`

- **What it was.** The user's schedule (2026-11-11): "The strategy should be to build the complete prototype. Then thoroughly measure it, and then do some performance work as long as it doesn't increase the code complexity too much." Three bins for every open question (A before the measurement round; B to the synthesis; C small). Bin A emptied, the cache stopped, the round run, the synthesis written.
- **Found.**
  - **A membership by neither owner is piracy, and a membership invalidates as a method does** (the user, 2026-11-11: "on reflection it is reasonable to say that declaring membership of a type in a trait if you own neither the type or the trait is piracy. Forbidden in strict mode, causes recompiles in default."). It removed guards, cells' special role and the shadow query, and put memberships inside G2 as it stood.
  - **"A membership is a method"** as a definition: built through two stages, reviewed, not adopted. The user: "Conceptual parsimony for the user only requires implementation to behave like a method. The implementation can be whatever is simplest/cleanest/fastest."
  - **The cache across sessions, measured before built** (E-372): on the table and ODE sessions no library code is left for a cache to hold; the images hold it. The user: "We don't build the cross session cache now."
  - **The measurement round** on a frozen build with tags; a fault found during the round is recorded, not fixed.
- **Became.** CLAUDE.md's schedule and rules; facts §10; `goals.md`; `plans/2026-11-14-synthesis.md` (live); evidence §1 to §4c.
- **Not yet in a current document.** CLAUDE.md links the schedule's plan, which moves to the attic: the link follows (part 2).
- **L:** L97 to L99. **For `record/context.md`:** the third turn (the schedule, the retirement of speed, the bins), in the user's words.

### `explorations/wrapping-by-facts.md` (2026-10-16, validated 2026-10-17)

Read in full.

- **What it was.** The first turn of the project. The user: "Try to come up with a much cleaner and simpler design for wrapping Julia code that is provably correct. Don't work on the basis of the current design, but do take some of the learnings on board." A brief with four goals, ten lessons and four test cases, and none of the then-current mechanisms. Three agents designed from it alone, from three angles (proof first; per-package method visibility; a minimal trusted base). All three arrived at the same core.
- **Found.**
  - **One rule and one prohibition.** R: compiled code depends on the method table only through facts "at concrete signature `s`, dispatch selects `r`"; a call whose argument types are not concrete records nothing and dispatches at run time. P: no invalidation that the facts call for is ever suppressed.
  - **Three theorems with their model and assumptions.** G1 by an invariant (every valid CodeInstance has all its facts true) kept by every event. G2 by Lemma D (a method that does not win leaves dispatch unchanged, in any order) and Lemma O (a non-pirate that applies at a concrete signature is a stakeholder's). **Necessity:** an abstract fact ("the methods matching `S` are exactly these") is broken by any package that defines a new subtype with a method, a package that is no pirate and no stakeholder. So concrete facts are necessary and sufficient for this form of G2. G3: what a program can reach is finite and listable.
  - **Evidence on stock Julia:** Julia's own invalidation is exact at concrete signatures (nine cases); the chains that had invalidated the demonstrators started at abstract edges only; 0 of 3,043 concrete facts selected a pirate.
  - **What went:** wrappers, delegates, sealing regions, doors, declared calls, the invalidation filter, the layering rule ("the trait world uses only itself").
  - **Rules the implementation needed, each found in validation:** a bare edge belongs to its owner; `return_type` is plain Julia's question; no compile-time evaluation over a run-time site; kinds are facts for closures only.
- **Became.** `reference/facts.md` (the facts rule, G1, G2, the terms, the lemmas); `design.md`'s argument. The proofs are in no current document in this form.
- **Not yet in a current document.** The decision at adoption (Q7): checked against today's facts reference and kept as `design/proofs.md`, in today's terms: the model, the assumptions, the three theorems with the corrected Lemma O, the necessity argument.
- **L:** L100, L101. **For `record/context.md`:** the first turn, with the user's words and the method (a brief without mechanisms, three independent designs).

### `explorations/dataframes-port-lessons.md` (2026-10-17, sessions 27 and 28)

Read in full.

- **What it was.** The first contact of the facts rule with real packages (Tables, DataFrames, CSV), item by item: design issue, porting guideline or tooling issue.
- **Found.**
  - **A run-time site's result is `Any`, and everything after it is a run-time site too.** Real packages are full of such sites: union-typed options, `Vector{Any}` of columns, types passed as values, keyword splats. Each got an answer: fold where Julia itself asserts the effects; a fact at a tuple whose elements are small unions (iteration over `Union{Missing, T}`); results asserted at the boundaries of large stages; types carried as `Val`.
  - **Code reached through a run-time site must be compiled by facts too,** or a load invalidates it. And a hot run-time site must cost what dynamic dispatch costs (it cost 6.5 µs, then a cache per site).
  - **Machinery reached from every run-time site must not specialize on what the site passes** (process start took 46 s).
  - **A tool that lists run-time sites** found in minutes what took most of the porting time.
  - **Keys from one package, functions from another:** compiled code for the pair lives in no image unless a glue extension's workload makes it.
  - **A first-call time is not all compilation.** Time the step a second time in the same session.
  - **Three settings of one switch** (off; all code; trait code beside plain code) and what the compiler needs for each: the origin of the policy in the compiler and of the test bed `all`.
- **Became.** Facts §3 (the fact forms), §8; `intro/porting.md`; the dispatch profiler and `fully_typed`; the move of the policy into Julia's compiler.
- **Not yet in a current document.** To check (C-42): the porting guideline's list of what makes a run-time site in ordinary code, with the answer for each.
- **L:** L102 to L105.

### The other explorations: `strict-mode.md`, `aot-under-facts.md`, `fast-loads.md`, `load-on-demand.md`, `facts-keyed-cache.md`, `keys-plan.md`, `sciml-as-traits.md`, `solvers.md`, `makie-rewrite.md`, `associated-types.md`, `runtime.md`, `julia-support.md`, `abstract-types-as-traits.md`, `unified-build-from-vanilla-julia.md`; and `design-findings.md`

Read: summaries and section openings; `abstract-types-as-traits.md` §1 to §5 and §11 by their openings.

- **`strict-mode.md`** (2026-10-17). The user: "I want to keep the option open to have strict mode, so trait code is never invalidated. If it rarely happens anyway it's cheap in terms of user friction but powerful as a guarantee." And: "I would love a mode that makes defining a winning pirate an error. If pirates never win then we never error." The mode first assessed (a call that would select a pirate raises) was a misreading, and costlier. Became facts §11 and traits §12.
- **`aot-under-facts.md`** (2026-10-17). A closed build compiles plainly: in a closed world plain inference is Julia, and nothing loads. What the traits add for a closed build is a list: the members behind an erased value, the signature of a `Callable`. The user: "In my mind AOT means no LLVM in the binary." Became facts §13.3 and traits §16. To check (C-43): the annotations A to E and the three risks against today's AOT standing (G-7).
- **`keys-plan.md`, `associated-types.md`** (2026-10-16). Keys replaced representations and projections (the user: "Every other language doesn't tackle representations … Do we really need this"); associated types adopted in first-order form only, after the finding that symbolic reasoning about associated types is where the other languages' cost lies. Today: parameters with equations (traits §3.2).
- **`solvers.md`, `makie-rewrite.md`, `sciml-as-traits.md`** (2026-10-16 to 2026-10-21). What a rewrite of SciML and Makie around a few traits would be. SciML's architecture read as twelve goals with their mechanisms and costs, then the same goals in Rust and Swift, then "the shortest route" in moves. The demonstrators and the ports' case studies came from these.
- **`runtime.md`, `julia-support.md`** (2026-10-16). What the design needs from Julia, as numbered pieces; the move to Julia 1.13.2. The pieces' numbering lives on in `design/julia-changes.md`.
- **`fast-loads.md`, `load-on-demand.md`, `facts-keyed-cache.md`** (2026-10-22 to 2026-10-27). Merged into the first-use cluster (above).
- **`abstract-types-as-traits.md`** (2026-10-28, 133 KB). The user: "Right now Julia has two more or less distinct ways to write generic code: Multiple Dispatch on functions written for abstract types (in the case of no type annotations at all Any), and traits with the compiled/dynamic switch. I wonder whether a unified perspective is possible, where we have one way to write generics. This would probably mean that abstract types are just traits." Found: strip the mechanism away and two differences remain (a declared contract or an open one; membership at the definition or later). Seven rules of a unified model. The one hard point: a late membership can change dispatch at a concrete signature that compiled code holds. Eight candidates (C1 to C8) from "members belong to the member" to "membership epochs", with Rust's coherence as precedent; then candidates for sound subtyping under late memberships.
- **`unified-build-from-vanilla-julia.md`** (2026-10-29, 85 KB). The user: "This is not an incremental change but a fundamental reframing." Each feature as an extension of a mechanism upstream Julia has, with the upstream place named line by line. Its review corrected four load-bearing claims (above). Its inventory of upstream places is, by the review, "the best map of the upstream surface the project has".
- **`design-findings.md`** (to 2026-10-16). The evidence log of the first era, in the order of the work: the August prototype (TraitRegions, nine packages), the measurements behind the motivation, `verify_main`, concrete mode, "between nested types and `Any`", where unreadable errors come from (three ingredients: the failure is detected deep; the message names the library's internals; the types are long), lenses, keys.
- **Became.** As named per item.
- **Not yet in a current document.** To check (C-44 to C-46): the anatomy of an unreadable error (three ingredients) in the rationale for the messages axis (G-5); "between nested types and `Any`" as the rationale's statement of the problem; the inventory of upstream places kept for the build notes (`record/build-notes/compiler.md`), since the exploration moves to the attic.
- **L:** L106 to L110. **A:** A11 (the eight candidates for late membership; strict mode as a raise at the call; representations and projections; trait wrappers, sealing, doors; lenses).

## The running lists

### L-list: candidates for the lessons

| # | Lesson | From | Kind |
|---|---|---|---|
| L1 | A mechanism that skips invalidation holds only while its premise holds, and fails silently. The facts rule skips nothing. | wrapping-under-keys F1 | the design |
| L2 | What a design fixes at a declaration it defends by refusals that depend on load order and end interactive work; a fact that a later definition invalidates composes. | decisions-1-and-4; consistency 4 | the design |
| L3 | A trait library's own methods on Base's functions end plain code: `show` in October, operations at sets in November. Take the method out; count the late load. | demonstrators-under-facts; GT-11 | the design |
| L4 | Under facts the cost sits in three shapes of code (containers of `Any`, abstract elements with one result type, small unions), each with a rewrite that recovers it. | policy-in-compiler | the design |
| L5 | The control set up to falsify the port, upstream compiled by facts as it is, carried the strongest result. | dataframes-traits-plan; E-392 | the design, method |
| L6 | An idea dropped for want of a rule returns when the rule exists: facts at non-public functions, then owner-only functions. | consistency 3; D-9 | the design |
| L7 | Seven shapes in which a plain package compiles per schema or loses its code. | dataframes-traits-plan §3 | the problem, the ports |
| L8 | Upstream's own suites, run unchanged, are the bar of a port. | dataframes-traits-plan | the ports |
| L9 | Measuring: the case the claim is about; the control that isolates the cause; no fitted workload; like with like; the build on every headline; the noise floor; profile before attributing. | demonstrators-fresh-eye; -under-facts | measuring |
| L10 | A cheap vehicle first, and the threshold before the run. | policy-in-compiler | method |
| L11 | The record: a register's "built" is checked against the code; a finding gets an ID and a home the day it is made; a decision is recorded with the argument that holds. | consistency; decisions-1-and-4 | the record |
| L12 | A suite redefines an implementation at the prompt; a review marks each claim verified or reasoned. | wrapping-under-keys | testing, reviews |
| L13 | A concept no port uses is found by `grep` and is a candidate to remove. | decisions-revisited; E-263 | simplifying |
| L14 | A mechanism that exists because of where the prototype had to live is not the design; it goes when the vehicle changes. | decisions-revisited | the design |
| L15 | A go/no-go on speed needs a correctness run in the same setting. | design-and-fixes 1 | measuring |
| L16 | Whatever caches a dispatch answer carries its world. | design-and-fixes 2 | the design |
| L17 | In plain Julia invalidation is an open-world problem, not a piracy problem: an abstract edge depends on every matching method, and any owner may add one. Piracy is the residue under the facts rule. (S1 to S8; 769 signatures, none concrete.) | framing-and-motivation | the problem |
| L18 | Say which tier a guarantee is (theorem or measurement), and name the exceptions of "never". | framing-and-motivation | claims |
| L19 | Lead with what is new over discipline; put a cost next to the step that incurs it. | framing-and-motivation | framing |
| L20 | One source of truth with deviations replaced three descriptions current as of three days. A session without a note, and an experiment in `/tmp`, are lost. | design-and-fixes 6; framing | the record |
| L21 | A catalogue of examples by claim shows the claims with none; a lead claim needs one example a reader can run. | examples-and-demonstrators | evidence |
| L22 | A gain can belong to one idea that traits make checkable and default (a declared signature at a closure), not to traits as such. Say which. | examples-and-demonstrators §2.1 | the design, claims |
| L23 | Classify a prototype's mechanisms: needed, imitating the platform, working around the vehicle, left over. | implementation-shape §2 | method |
| L24 | **The guarantee is the facts rule's and holds for plain code; traits make living under it cheap and checked.** Attribute every claim to one of the two. | implementation-shape P2; demonstrators-fresh-eye B2; E-392 | the design |
| L25 | A port whose kernels unwrap at once validates a barrier, not a trait. | implementation-shape P7 | the ports |
| L26 | A compiler change is tested at concrete argument types and by what the runtime compiled; reflection on the abstract signature, or after a run, shows something else. | compiler-implementation 2.1; performance-phase A1 | testing, diagnosis |
| L27 | A claim of "the same as plain Julia" is checked by a redefinition, in both modes. | compiler-implementation 2.2 | claims |
| L28 | A split with no edge to its members makes speed depend on load order; the edge (a membership invalidates as a method) is the principled form. | compiler-implementation 2.6; GT-1 | the design |
| L29 | Tables: the clean case in both columns; counts over every module; one harness per difference; no baseline at a heuristic's threshold; the platform's load cost beside the work. | performance-phase A2 to C4 | measuring |
| L30 | One standard-library method (SparseArrays' `vcat`) has been the largest cause of lost code from October to November. | performance-phase theme 4; GT-8 | the design, evidence |
| L31 | What the facts build finds wrong in plain Julia goes upstream as an improvement to plain Julia. | performance-phase A1, D1 | upstream |
| L32 | Profile one case before designing a mechanism for the class; measured costs per session come before speculative gains per call. | inline-caches review and plan | method |
| L33 | A reference drifts back into a build log unless the status line's shape forbids it: stated 2026-10-19, lost by 2026-11-18. One deviation, one row. | references-consistency L2, H2 | the documents |
| L34 | Do not copy into a document what one command reports; an index of everything in place grows without bound. | writeup-review 32; notes-cleanup-plan | the documents |
| L35 | File a motivating number under the mechanism that causes it; round against yourself. | writeup-review 2, 8 | claims |
| L36 | A guarantee's check counts the code the guarantee is about; a reference cites checks that exist and run. | references-facts-compiler-vs-code H2 | evidence |
| L37 | Take a mechanism from a named precedent; its known failure comes with the name. | principled-speed-plan | the design |
| L38 | A value decided by inference (`return_type`) is where "identical" needs plain inference kept beside the facts mode; a declared element type removes the query. | return-type-after-loads | the design, the ports |
| L39 | Correctness ranks above every performance item. A raw pointer in an immutable struct survives into a package image. | remaining-performance-work | ordering, the playbook |
| L40 | The rule with one decider (the value's own type, as in Rust and Swift) was cited as the precedent on 2026-10-20 and adopted on 2026-11-15, after a rule with several deciders. Try the named precedent as the design first. | dynamic-and-compiled §1b; D-1 | the design |
| L41 | The references first, the teaching last; semantics before performance; a choice that may cost speed is recorded, not tuned. | dynamic-compiled-implementation; the user | ordering |
| L42 | A library's image splits over the library's own members; a user's type is past the split by construction. | dynamic-compiled-plan review 2; GT-7 | the design |
| L43 | Under facts a run-time site costs a dynamic dispatch as in plain Julia; the loss is inlining of one-method callees at `Any` and the result's type, and it cascades. | heterogeneous-collections F2 | the design |
| L44 | A number says whether it measures interop or idiomatic trait code. | heterogeneous-collections, addendum | measuring |
| L45 | A deviation without an expected-failure check is a claim nobody re-verifies; write what would count against the design before the results. | proving-the-references | evidence |
| L46 | Whether code is compiled for a caller's value is the caller's to say, in the language; a switch inside a library is `@nospecialize` turned around. Held through three mechanisms. | values-carry; the user | the design |
| L47 | A mechanism rejected for stated reasons returns when each reason is answered by name (pointer tables: world age, serialization, races). | what-follows-the-split §4.3 | the design, alternatives |
| L48 | A guess inline, a constant-cost table behind it, optionally feedback: the three pieces of every mature implementation of dynamic dispatch. | what-follows-the-split §2 | the design |
| L49 | The first trait of a port is an interface the ecosystem already has informally. A split package is a pirate by the letter. A porting rule needs a second port. | porting-guideline review 11, 12, 20 | the ports |
| L50 | Through a typed pointer a struct by value is a copy: identity lost silently. | tonights-code 1 | the playbook |
| L51 | A reference is cut by rule, not by syntactic category; one table per spelling with several readings; what a user observes in the reference, how in the lowering. A spelling with five readings is a finding about the design. | traits-reference-structure F2 to F4 | the documents, the design |
| L52 | Before a port: an inventory of what it needs against the references' statuses, probes in minutes, each move validated in a small package. A plan's central decision is checked against what already runs. | w34 plan and review | the ports, plans |
| L53 | The change that pays is where a user's types enter a library's types. Erase there (a held value of a trait, opened once per batch) and everything above keeps its type. SciML had built that erasure by hand (function wrappers); the leak was one field. | ndport-principled-traits §1, §3; E-152 | the ports, the design's case |
| L54 | A package correct in plain Julia can lean on Base folding a type computation. Under the facts rule it is then correct and slow, and nothing warns. After wrapping a package, run the dispatch profiler on the steady state. | pushback P3-1 | the ports, messages |
| L55 | The same silent kind: a plain caller's constant propagation into a wrapped package's `getproperty` switch. Costs across the boundary between the modes are found by a tool, not by a failure. | pushback P6-1 | the ports, the design |
| L56 | "Make a choice, record the pushback." A port never bends the design at the case; the log of where the design pushed back is the port's main product. | the meta plan's ground rules | the method |
| L57 | Inside-out under strict mode is a porting method for core packages: bottom-up, a census of pirates after each load, joint owners for packages split from one core. Each step is free of pirates, whatever the final setting. | the inside-out plan; the user, 2026-10-21 | the ports |
| L58 | An informal interface with throwing fallbacks is a trait over its existing functions: one family line, members checked at first use. Results of an open iterator type need a function with a declared result. Check the trait's name against exported aliases. | the graph plan; pushback P4-3 | the ports |
| L59 | Closed library families stay abstract types; construction-time code, keyword front ends and code dynamic by design stay plain. A port that says what it leaves alone is shorter and more honest. | ndport-principled-traits §8 | the ports |
| L60 | Membership is per type; real packages decide per value (`f.jac === nothing`). The answer within the design is a branch in the implementation or two record types. An optional capability is the same question. | ndport-principled-traits §10.5; W34-8 | the design, alternatives |
| L61 | Measurement plans fail in the same few ways: settings that share a tree or a depot, a check without a control, a timer not switched on, state carried from one run to the next, a criterion that cannot be decided. A review that reads the harness's code before the first run pays for itself. | the six plan reviews | the playbook |
| L62 | A lemma about ownership must be checked at every signature a method applies to: `Vararg` tails and `Union` members make a method apply where its owner is no stakeholder. | facts-fresh-eye H1 | the design |
| L63 | A rule whose reason is transitive must be transitive. The asserted-effects rule was per frame; the fold went stale one frame up. | facts-fresh-eye H2 | the design |
| L64 | A fresh reader with probes of seconds finds what the authors cannot: sections that contradict, "Implemented" that fails, code citations by line that are stale in days. Cite code by name, never by line. | the four fresh-eye reviews | the documents |
| L65 | A cache recurs only where its keys recur. Compilation is keyed on the library, on the user's model or data, or on the call's shape; only the first is kept across sessions. Keep the user's types out of the library's keys; normalize at the entry. | ttfx-plan review M5; port-architecture §2 | the ports, first use |
| L66 | The part that depends on the user's parameter type is the outermost layer only; inside, the right-hand side partially evaluated. | the user, 2026-10-27; E-181 | the ports |
| L67 | Once compiled code is kept, the load is what remains, and the load follows the dependency tree and Julia's validation of edges, not the traits. | E-176, E-179, E-185 | first use |
| L68 | Say what is trait-specific and what is packaging. Lean trees, stubs, normalization and erasure are open to plain code. The facts rule adds code that loads early and stays valid, and interfaces that are checked. | w58-direction 1; lean-core memo §2.5 | the goals |
| L69 | "Facts first": use the guarantee the facts rule gives for facts code, instead of making a mechanism work for all of Julia's code. | facts-first-julia-work | the method, the compiler |
| L70 | Code loaded at first use is invisible to the rest of the calling function (world age), for plain code alike. Entries that may load code go through `invokelatest`. | lean-core review B1; E-182 | the ports |
| L71 | A harness must prove its images valid: `--compiled-modules=existing` loads from source without a word; one depot per setting; no cache measured on the session that recorded it. | ttfx-plan B1; w58-direction 3, 4 | the playbook |
| L72 | A decision rule registered before the run binds: when the outcome takes the other branch, the plan changes, or the row says why not. | w58-direction 6 | the playbook |
| L73 | Running library code inside inference to fix a fact is a deep hole: locks, worlds, edge records, load order. Make the fact a relation the type system knows. | the W-40 plan and reviews | the design, alternatives |
| L74 | Where the facts rule makes Julia's own code slow, look for the structural cause before a mechanism. Base's introspection layer called generic functions on kinds; the fix was builtins, not a recorder. | the W-57 memo; the W-56 review | the compiler |
| L75 | A tweak in the trait design that gives a port a principled architecture is the most valuable finding. A workaround that every caller must write (26 `compiled_for` sites) is such a finding. | the user, 2026-10-28; the audit's item 1 | the method |
| L76 | An annotation that fixes a time hides a cause. Run the fully typed report first; declare the callee's result before asserting at the call; `@nospecialize` is an escape hatch. | the user, 2026-10-28; the audit | the ports |
| L77 | A stored value must offer every capability its type has, to whoever asks. Seeing it through the one trait it was stored under blocked legends, inspectors and pooled columns alike. | fresh-ideas-makie D1; open issue 82 | the design |
| L78 | The key holds what the hot code must know and no more: the cell type, not the column's container type; the numerical key, not the user's model. | fresh-ideas-dataframes §1.1; fresh-ideas-sciml §1.1 | the ports |
| L79 | Closed sets are types; open sets are traits. Layouts, marks, caches and tableaus are closed. Columns, recipes, data, backends, algorithms are open. | the three fresh-ideas plans | the ports |
| L80 | A capability belongs to whoever asks for it (the legend owns the legend's trait), and has a default that takes what it needs. | fresh-ideas-makie §2.3; fresh-ideas-sciml §1.4 | the ports |
| L81 | Where a port puts a trait beside an abstract type of the same meaning, the design is telling you the two are one thing. Every port's plan listed such cases before unification was decided. | the finish plans' "cases for W-83" | the design's history |
| L82 | A trait is an abstract type that members may join later, with a contract checked at each membership. Stating a design as one premise and deriving its consequences removed more rules than any review found. | traits-are-abstract-types | the design, teaching |
| L83 | The guarantees rest on the facts rule, not on the trait machinery. That is why the machinery could be replaced whole. Know what each claim rests on before changing the design. | unification-tradeoffs, summary | the rationale |
| L84 | Before a large change, a review of what it trades against what was achieved, goal by goal, with the experiment that measures each loss and the stage it must precede. | unification-tradeoffs; the work plan §8 | the method |
| L85 | Evidence before the build: unification passed its first gate on eight quick runs on the build of the day, none longer than minutes. | unification-evidence §2.2, §6 | the method |
| L86 | A design's claim about Julia's internals is checked against the code at the cited line by a second reader. Four load-bearing claims of the build exploration did not hold; all four were plausible. | unified-build-review | the playbook |
| L87 | A caller that holds only the callee's result can survive the callee's replacement, but only if the call loads its target through a slot: Julia binds calls by address. | unified-build-review H1; W-101 | the compiler |
| L88 | Audit inherited code by probes, not by reading its gates: gates pin the defects their author believed in. | oc-build-audit | the playbook |
| L89 | A form that ordinary code reads as an ordinary type must be right wherever it is not special-cased. Prefer a representation whose default is "unknown" over one whose default is a confident wrong answer. | all-representation | the compiler |
| L90 | A "rare shapes only" path needs a counter. The unified build's tenfold loss was one conservative pass taken for the normal shape. Profile before judging a design by a first number. | unification-review H1; E-290 | the playbook |
| L91 | A guarantee has a payer. "A membership invalidates nothing" was paid by plain code's inference at every call a later membership could change. Ask who pays before adopting a guarantee. | issue-158-guarantee; unification-review M1 | the goals, tensions |
| L92 | Speed gates with numbers drew the work into patches at cases. The claim that lasts is no regression where types are known, and broad gains that follow from a rule. | the user, 2026-11-09 | the goals |
| L93 | Erasure belongs at the boundary where large code serves many value types, not at the kernels. Erasing at Base's kernels cost every call everywhere. | io-porting-lessons L1; E-330 | the ports, the design |
| L94 | A port's change that follows a rule of the references is the port following the design. "Do not design around a weak point" does not forbid the idiom the design teaches. The misreading cost a day and a change to Base. | io-porting-lessons L6 | the method |
| L95 | A change that touches Base is checked against the guarantees for plain code before it is built, and measured on a proxy that can see what would break. | io-porting-lessons L4; performance-day M3 | the playbook |
| L96 | A plan, a hostile review, the review's changes, then the build: eight unsound rules fixed in one night with no rework. | the plans and reviews of 2026-11-09/10 | the playbook |
| L97 | Conceptual parsimony is owed to the user, not to the implementation: a membership behaves as a method does; what implements it is whatever is simplest. | the user, 2026-11-12 | the design |
| L98 | Measure what a mechanism would hold before building it. The cache across sessions had nothing left to hold on the sessions measured; the images held it. | cache-across-sessions; E-372 | the method |
| L99 | Sort every open question into bins by what it blocks. "Conceptually complete" got a definition, and measuring began the day the first bin was empty. | complete-prototype | the method |
| L100 | To get a simpler design, state the goals and the lessons, withhold the mechanisms, and let independent designers start from the brief. Three arrived at one core; that agreement was the evidence. | wrapping-by-facts, Method | the method |
| L101 | A guarantee worth having can be proved from a short model. G1 and G2 follow from one rule and one prohibition, and the proof also says what is necessary: only concrete facts survive unrelated loads. | wrapping-by-facts, theorems | the design, proofs |
| L102 | Under the facts rule a call at abstract types returns `Any`, and the loss spreads. Ordinary packages are full of such calls: keyword splats, types as values, union-typed options, untyped containers. Each kind needs a rule of the design or a line in the porting guideline. | dataframes-port-lessons §1 | the ports, the design |
| L103 | Build the tool that shows the mechanism's cost sites before porting with it. Listing run-time sites turned days into minutes. | dataframes-port-lessons 1.7 | tools |
| L104 | Machinery that every call site reaches must not specialize on what the site passes. | dataframes-port-lessons 1.9 | the compiler, the playbook |
| L105 | A first-call time is compilation plus run time. Time the step again in the same session before attributing. | dataframes-port-lessons §4 | the playbook |
| L106 | A guarantee that rarely costs is cheap to offer and strong to hold: if pirates never win, strict mode never raises. | the user, 2026-10-17; strict-mode | the design |
| L107 | A closed build compiles plainly. What traits add to AOT is a list of what an erased value can be, not another compiler mode. | aot-under-facts | AOT |
| L108 | Associated types in first-order form only. Symbolic reasoning about them is where the other languages paid. | associated-types §2 | the design, other languages |
| L109 | An unreadable error needs three ingredients: detected deep, named in the library's internals, with long types. A bound removes the first at the call; a short type signature removes the third. | design-findings §17 | messages |
| L110 | Frame a change to Julia as an extension of a mechanism upstream has, with the place named. The frame survived its review; four of its claims did not. | unified-build-from-vanilla-julia; its review | the compiler, upstream |

### A-list: alternatives to add or complete

| # | Alternative | From | State in `design/alternatives.md` |
|---|---|---|---|
| A1 | Sealed abstract types and sealed functions, dropped by the user ("A closed contract is a trait, not a sealed abstract type.") | policy-in-compiler | to check (C-5) |
| A2 | Owner-only functions as the return of facts at non-public functions | consistency 3 | the two entries exist apart; link them (C-2) |
| A3 | Guarded devirtualization at run-time sites, postponed by the user (a failed guard is a cliff; traits recover the cost); polymorphic inline caches, not built | principled-speed-plan; inline-caches-plan | to check (C-15) |
| A4 | For `return_type` after loads: freezing answers; no optimizer for the answer cache (tried, widens answers); a guarded fold; red-green revalidation (not built, Optional) | return-type-after-loads | partly there ("`return_type` at run time…, replaced"); to complete |
| A5 | From the first port: membership per value; a trait with input parameters beside `Self` (Rust's `Algorithm<P>`), answered by the driver bounded by both traits; an optional bounded parameter; a witness carried in the held value for a cheaper crossing; erasing the graph's type | the ndport cluster; pushback W34-1, W34-8 | to check by topic |
| A6 | Caches across sessions: keyed on the environment (built, retired); keyed on facts and their origins (identity by fingerprints; store paused); remembered validation (set aside); a store of optimized IR against machine code | the first-use cluster | "Caches across sessions" exists; to check it has all four with reasons |
| A7 | From the ports' design round: "open here" at a bound; a kept function without a signature; a generic `Callable`; trait casts; a wider-but-not-disjoint result accepted by the member check; `rewrap`; `where` variables on an operation | the audit's candidates; the fresh-ideas plans | to check by topic against D-1, D-2 |
| A8 | Folds recovered by mechanism: the member's builder folded by a compiler primitive (W-40); concrete evaluation with recorded dispatches (W-56); kinds inferred plainly; assertions as the asserter's promise | W-40, W-56, the W-57 memo's options B to H | to check |
| A9 | Unification's own alternatives: memberships explicit (no transitivity), reversed the same day; over-approximating `typeintersect`; result edges without a slot; keys as `Keyed{X, R, F}`; `Callable` by derived memberships; "bounded" on by default; `All` as an ordinary abstract type | the documents of 2026-10-29 to 2026-11-07 | partly there (level 2's options, the unified build's options); to check each |
| A10 | Of the unified build's first week: guards and "a membership invalidates nothing"; `IO` as an open set compiled once; `Dynamic{IO}` as a box; "a membership is a method" as the definition; the speed plan's gates; reserved cast names | the reviews of 2026-11-08 to 2026-11-12 | to check each |
| A11 | From the explorations: the eight candidates for late membership (C1 to C8) and those for sound subtyping; strict mode as a raise at the call (the views design); representations and projections; trait wrappers, sealing regions, doors, declared calls, the invalidation filter; lenses and the held layout; associated types beyond first order | the explorations; design-findings | most are in the alternatives; to check each by topic |

### C-list: to check against today's documents

| # | Check | From |
|---|---|---|
| C-1 | Does the facts reference state the exception to "an unrelated load ends nothing": a package extension of an abstract type's owner, triggered by an unrelated package? | consistency 2 |
| C-2 | Do the alternatives say that D-9 takes up what was dropped in October? | consistency 3 |
| C-3 | Was a plain baseline hardened by hand at its barriers ever measured? If not: "not shown", or a row for stage 7. | demonstrators-fresh-eye B2 |
| C-4 | `design.md` quotes the test bed's cost from julia-1.13 (1.037, tails to 27.8×). Measured on this build? | policy-in-compiler |
| C-5 | Sealed abstract types and functions in the alternatives? | policy-in-compiler |
| C-6 | Does `intro/porting.md` carry the seven shapes? | dataframes-traits-plan |
| C-7 | The October claim "the session in 1 s, imports excluded" against today's sessions: where is it said how it stands? | dataframes-traits-plan |
| C-8 | Do the split's members depend on the order of declarations or loads today, and does compiler §7.2 say so? | design-and-fixes 4 |
| C-9 | Is the table S1 to S8 (plain Julia against the facts mode) in the rationale or the evidence? Does `inval.jl` exist in `experiments`? | framing-and-motivation §0 |
| C-10 | Which of `experiments/facts/framing/` and `experiments/examples/` run on today's build? (C-9 is answered in part: the framing cases were added to the repository in session 29.) | examples-and-demonstrators |
| C-11 | Does `intro/porting.md` say that a port's kernels use the trait's operations? | implementation-shape P7 |
| C-12 | Are the exact-type entries of Julia's per-site cache (`call_cache_exact`) in today's stack, and listed among the changes useful without traits? | inline-caches-plan §2 |
| C-13 | Where does "are the standard libraries owners of their own" stand today? | writeup-review 1 |
| C-14 | Does facts §3 list `invoke` at a declared signature, and state the assumption under "a closure's call at kinds"? | references-facts-compiler-vs-code H4, M2 |
| C-15 | Are guarded devirtualization and inline caches in the alternatives, with the user's reason? | principled-speed-plan |
| C-16 | Does `intro/porting.md` say "declare the element type" with its reason? | return-type-after-loads F |
| C-17 | Does the differential test of `return_type` answers (stock Julia as oracle) exist for today's build? | return-type-after-loads §3 |
| C-18 | Where is today's interop number: trait code calling Base's generic algorithms on a container of `Any`? | heterogeneous-collections F1 |
| C-19 | Does each open deviation row have an expected-failure check? (For the build notes.) | proving-the-references §1 |
| C-20 | Do the alternatives say that one way to erase is the Rust and Swift rule cited on 2026-10-20? | dynamic-and-compiled §1b |
| C-21 | Does `intro/porting.md` have the informal-interface pattern, the options struct for keyword entry points, and the rule of the second port? | porting-guideline review |
| C-22 | Do the alternatives carry the three objections to pointer tables and their answers? | what-follows-the-split §4.3 |
| C-23 | Does `intro/porting.md` give the inventory and the probes as a port's first step, and SciML's six moves as its case study? | w34-sciml-prerequisites |
| C-24 | Does `intro/porting.md` carry the silent hazards of a wrap (folding of type computations, constant propagation into `getproperty`) with the tool that finds them? | pushback P3-1, P6-1 |
| C-25 | Does `intro/porting.md` say what stays plain in a port, and why? | ndport-principled-traits §8 |
| C-26 | Each pushback entry of the NetworkDynamics port: still true on today's build? Then an open issue, a tension or a guideline entry holds it. | ndport-pushback |
| C-27 | The NetworkDynamics numbers in the evidence: of which build? (R3) | the meta plan's state table |
| C-28 | P6-2 to P6-5 (strict mode and OffsetArrays' `reshape`; extensions rewriting a core's facts at each load; `@inferred` tests failing by design; run-time `return_type` answers' share): each a tension or an open issue today? | ndport-pushback |
| C-29 | Does `intro/porting.md` give the three kinds of compilation and "a cache recurs only where its keys recur", with normalization at the entry and the parameters in the outer layer? | the first-use cluster |
| C-30 | Do the goals or the rationale say what of the first-use claim is trait-specific and what is packaging? | w58-direction 1 |
| C-31 | Is the Python workload (SciPy with matplotlib) in today's registry with a current run? It is the baseline by R3. | ttfx-sciml-makie §3 |
| C-32 | The harness's traps (stale images loaded from source, shared depots, self-replay): in the playbook, and does today's harness check them? | the first-use reviews |
| C-33 | Is the reason for Base's introspection layer on builtins, with its tool, in `julia-changes.md` or the build notes? | the W-57 memo |
| C-34 | The audit's advice for port authors: in `intro/porting.md` in today's terms? | ports-annotation-workarounds |
| C-35 | Each weak point of the ports' design round against today's references: answered, an open issue, or an alternative. | the fresh-ideas plans |
| C-36 | The three architectures' principles (cell type as key; the model is the trait; marks closed, recipes open) in the porting guideline's case studies? | the fresh-ideas plans |
| C-37 | Do the intro and `design.md` open with the premise in two sentences (an abstract type that members may join later; a contract checked at each membership)? | traits-are-abstract-types §0 |
| C-38 | Does the rationale say what the guarantees rest on (the facts rule, not the trait machinery)? | unification-tradeoffs |
| C-39 | Are the Swift, Rust and Mojo lessons per trade-off in `other-languages.md`? | unification-tradeoffs §3 |
| C-40 | Is "a port's change that follows a rule of the references is not a workaround" in CLAUDE.md's rule for ports (the diff for the user) or the playbook? | io-porting-lessons L6 |
| C-41 | The playbook: a counter on every "rare" path; profile before judging a first number. | unification-review H1 |
| C-42 | Does `intro/porting.md` list what makes a run-time site in ordinary code (keyword splats, types as values, union-typed options, untyped containers), with the answer for each? | dataframes-port-lessons §1 |
| C-43 | AOT: the annotations and the three risks of the exploration against G-7's standing and the open issues. | aot-under-facts §3, §6 |
| C-44 | The anatomy of an unreadable error (three ingredients) in the rationale for G-5? | design-findings §17 |
| C-45 | "Between nested types and `Any`" as the rationale's statement of the problem? | design-findings §16 |
| C-46 | The inventory of upstream places (the build exploration's §1 and its sources) kept for `record/build-notes/compiler.md`. | unified-build-from-vanilla-julia; its review |

## The record's passes

What each pass over a ledger did, with the choices (mine).

### The registry of experiments

- **How:** two agents drafted the rows (E-1 to E-393; E-394 to E-501) in a fixed format. The main session merged them by script and checked: every ID of the old registry is in the registry or in the ledger's first table, once; every number of a kept outcome stands in that experiment's old row.
- **The result:** 106 rows in [the registry](experiments.md), by goal; 329 IDs in [the ledger](../../attic/writeup/record/experiments-archive.md) only, each with its reason. The ledger holds every old row unchanged.
- **Kept though measured on an earlier build of the line:** the rows on plain Julia alone (the problem, §1); the gates that the references' rules cite (E-311, E-315, E-320, E-321, E-332, E-335, E-336, E-342, E-344, E-352, E-353, E-366); E-395, whose count of the types kept under the facts rule (74 %) no later run repeats.
- **Kept, cut down to the part that stands:** E-168 and E-230 and E-289 (the plain and Python numbers), E-374 and E-375 (known types, plain code, images), E-386 (upstream's session), E-364 (the builds).
- **To the ledger though a current document cited it:** E-369 and E-376 (repeated by E-384 and E-392), E-401, E-402, E-404 and E-442 (repeated on `next` by E-440, E-437, E-439 and E-501), E-330 and E-331 (E-341 is the kept row), E-31 and E-176 (a stock number beside an earlier build's). The documents that cite them are changed in their own passes; the history's documents (the alternatives, the lessons, the decision log, the build notes) may cite a ledger row.
- **E-418** was registered and not run; it is in the ledger, since its rule (a call that only throws as a run-time site) is not in the references.
- **A control's row** (E-405, E-436 to E-439, E-441) compares `next` with the tag. E-436 and E-441 also state a property of `next` alone.

### The open issues

- **How:** an agent rewrote the page as what is open, each item as it stands now. The main session checked: every numbered item and every tension of the old page is on the new page or in the ledger's list of what the pass closed; the lint.
- **The result:** no question waits for the user; 12 tensions (GT-2, 3, 5, 7, 8, 9, 12, 14, 16, 21, 31, 32); 74 choices of the agent, one line each; 35 design items; 4 on the implementation and measurements; 1 on the documents. 12 tensions and 6 items closed, each with its reason in [the ledger](../../attic/writeup/record/issues-closed.md).
- **The old anchors** `#1-decisions-waiting-for-the-user`, `#2-design`, `#4-runtime-and-measurements` and `#5-documents` are kept above the sections that hold their content now.

**Where the reading was in doubt** (the agent's list; the choices stand, mine):

- **GT-2 kept.** Decided by D-3, but the old text says it closes once built (traits T-129). The entry's cost is the implementation's deviation.
- **GT-12 kept.** Decided by D-3 and built on `next`, but the old text says it closes only with E-391's edit timed again once TraitTables follows the design.
- **GT-11 closed.** A default's method at a set on one of Base's functions stays; E-394 found none among what the late load ends.
- **GT-24 closed.** Its residue is stated in §3's `Callable` line, not as a tension.
- **166 kept.** Its counts (E-331) are of Base's methods compiled once at `IO`, which Base does not do; the case stands for code an author erases with `IOContext{IO}`. Proposal (c) leans on declared results that GT-5's rule leaves `Any`.
- **170 kept.** With the display erasing, what is left is a candidate's target invalidated and compiled again (E-338) and C-39, which is also a deviation row.
- **112 kept.** Measured only on an earlier build (E-226); MakieCompat still has the recipe children.
- **110 kept** under the ports. The design answers it (traits §10.1); only the port's change is left.
- **179 kept.** Its plan's parts are done (E-368, E-476 to E-478); what is open is the build's verdict per signature, P3's demand rule for upstream by facts and P6.
- **125 closed.** By compiler §2.4 (a callee inferred under its own policy). If the main session reads 125 as the pressure "Base by facts in the product setting", that is GT-3 and GT-8.
- **19 and 65** are in §4 (Facts and ownership), not §1: they wait for E-189 (proposed, not run), not for the user. §1 holds no question.

### The decision log

- **How:** an agent classified each of the log's 491 rows as in force (with the part of the design it sets) or for the ledger (with a reason). The main session built both files by script, each row unchanged, and checked that every row is in one of them.
- **The result:** 282 rows in [the log](decisions.md), in 21 groups by reference chapter; 209 in [the ledger](../../attic/writeup/record/decisions-superseded.md): the old section of superseded rows (85), and 124 whose mechanism is gone, that a later row decides differently, or that are finished plans.
- **Anchors:** the log's old section anchors (`#5-the-compiler-and-julia` and the like) are gone. A link "decisions §5" in a row or a note of its day means the old log's section.
- **Kept in doubt** (in force, with a clause of its day; mine): each is a row to restate when its subject is next decided.

| The row | What is of its day |
|---|---|
| The receiver type: the type whose own methods serve at least one operation (th (T4) | the receiver type: "none when defaults serve every operation" is not stated today |
| Declared fields are stored fields of the conforming type, by name or mapped (` (T4) | declared fields are stored fields; "or mapped" is gone |
| Built W-46 (mine, the agent building it, 2026-10-22): (T4) | a supertrait's parameter taken only where written bare: not clearly stated in traits §4.5 |
| Built T-64 (mine, 2026-10-22): (T5) | a result typed by a trait checked by its inferred type; "kept value" is gone |
| TraitDifferentialEquations around a problem trait: (P-ports) | the ODE library around `ODEProblemTrait`: the other details not checked |
| No sealing (T3) | "no sealing": not in the references; sealed sets deferred |
| Slowdowns are tolerated if redesigning the code with traits recovers them. (P-goals) | slowdowns tolerated if a redesign with traits recovers them: of the time before the speed work was retired |
| What the check before a pirate's membership misses is reported, not undone: (T12) | the miss of a pirate's membership is reported, not undone: partly overtaken by taking a membership back |
| The key's form: (X) | the key's form, of the time before keys became optional |
| The owner of code compiled by facts beside plain code is the symbol `:facts` (C) | the owner symbol `:facts`: the references speak of a policy |
| In a closed build the split holds the box `Dynamic{X}` as a member, splits over at most 64 members, and code i (T16) | the closed build's split holds the box; its clause on the attribute's call is gone |
| A user's own component types in NetworkDynamics on the ports (R6): (P-ports) | NetworkDynamics' component adaptors through bounded helpers: not found in the port |
| Symbolic access as a protocol (open issue 118, R5): (P-ports) | `HasSystem` holds; `observed` returning `Kept{Callable}` is gone |
| Image validation gives a fold that holds the bound `typemax`, (C) | image validation of a fold, with the folds of that time |
| A large library keeps its API by package extensions for keys and loading stubs for functions (P-ports) | lean libraries by package extensions for keys |
| Workspace: the design repository with separate repositories inside it (`julia/ (P-docs) | the workspace layout; its "no remotes" is stale |
| Cleaning up the open issues and the work queue: (P-method) | the clean-up of 2026-10-27: finished; its rule for open questions stands |
| At an intersection argument: (T3) | intersection arguments; the clause on the attribute's fallback is gone |
| An image's memberships, activated at load, run the stopgap's walk and the ambiguity report as a declaration do (C) | an image's memberships run the walk at load; "stopgap" is stale |
| A membership's check, at a further argument declared abstract, asks for a method that meets the signature (T5) | the check at abstract further arguments holds; one clause contradicts a contract's entries |
| Sets in Base's build: (C) | sets in Base's build; its "final negatives" are of that time |
| Dispatch's lookup at an open set keeps a match met only at an intersection no type is in (C) | dispatch keeps a match at an empty intersection; negatives fold with an edge now |
