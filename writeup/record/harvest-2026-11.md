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

### A-list: alternatives to add or complete

| # | Alternative | From | State in `design/alternatives.md` |
|---|---|---|---|
| A1 | Sealed abstract types and sealed functions, dropped by the user ("A closed contract is a trait, not a sealed abstract type.") | policy-in-compiler | to check (C-5) |
| A2 | Owner-only functions as the return of facts at non-public functions | consistency 3 | the two entries exist apart; link them (C-2) |

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
