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
