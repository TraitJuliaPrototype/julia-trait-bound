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

### A-list: alternatives to add or complete

| # | Alternative | From | State in `design/alternatives.md` |
|---|---|---|---|
| A1 | Sealed abstract types and sealed functions, dropped by the user ("A closed contract is a trait, not a sealed abstract type.") | policy-in-compiler | to check (C-5) |
| A2 | Owner-only functions as the return of facts at non-public functions | consistency 3 | the two entries exist apart; link them (C-2) |
| A3 | Guarded devirtualization at run-time sites, postponed by the user (a failed guard is a cliff; traits recover the cost); polymorphic inline caches, not built | principled-speed-plan; inline-caches-plan | to check (C-15) |
| A4 | For `return_type` after loads: freezing answers; no optimizer for the answer cache (tried, widens answers); a guarded fold; red-green revalidation (not built, Optional) | return-type-after-loads | partly there ("`return_type` at run time…, replaced"); to complete |

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
