# The schedule to the synthesis, and what "conceptually complete" means

**Status:** adopted (2026-11-11, the user: "Sounds good. […] Go ahead with your suggestions."). Written in the main session. The schedule is the user's with five adjustments of mine that the user accepted. The triage (which item is in which bin) is mine, input to the synthesis; only the first bin is put to the user. Not normative: the work queue ([`../record/todo.md`](../record/todo.md)) holds the items and their status.

## The user's words

> "Housekeeping means cleaning up and properly structuring the remaining work. The Todo list and the design most of all. […] The speed work and performance things that are on hold probably should all be retired permanently. The strategy should be to build the complete prototype. Then thoroughly measure it, and then do some performance work as long as it doesn't increase the code complexity too much. I think at the highest level we should fix the design questions that are open, fix the deviations build the cross session cache/store, do an intense measurement round, do some "low hanging performance work" especially where we already had faster results previously. Then we should double check the ports and the lessons and tensions they suggest. And THEN we have all the information for a synthesis assessment that can thoroughly analyse the prototyped design and suggest changes and adjustments and thinks that need to be fundamentally revisited."

> "Sounds good. I would clarify that we retire the speed items, but of course we can later look into the attic to get inspiration for other things that could be done. Go ahead with your suggestions."

## The schedule

| Phase | What | Items | Ends when |
|---|---|---|---|
| 1 | **Triage and the decisions that shape the rest.** Every open question and deviation in one of three bins (below). The membership as a method decided first: it removes code that other deviations live in. | this document; W-141 | bin A is fixed; W-141's three decisions are made |
| 2 | **Bin A: the design questions that change the mechanism, then the deviations.** | W-141 (if adopted), W-142, W-143 (1), W-128 | bin A is empty: each entry built, closed, or moved to another bin with its reason |
| 3 | **The cache across sessions, bounded.** First what a session still compiles that no image holds (minutes); then a proposal with the smallest vehicle and the result that would stop it; then the build. | W-120 | the cache is built, or stopped by its own criterion |
| 4 | **The ports brought to the head.** The demonstrators follow the design: each builds, passes its tests and uses the current rules. No new port work. | W-104 | every demonstrator's suite passes on the head |
| 5 | **Freeze, then the measurement round.** No change to Julia or the library during it. Every axis of the goals, every round that waits. | W-145 (with W-17, W-119) | the evidence is on one build |
| 6 | **Low-hanging performance work.** Only where the round shows a loss against an earlier build or against plain Julia, and the fix adds little code. The retired speed work is read for inspiration. | W-146 | the list from the round is worked or dropped, each with its reason |
| 7 | **The ports' lessons and tensions, checked.** Each port's questions and each tension read against the head and the round's numbers. | W-147 | open issues §1 and §6 are current |
| 8 | **The synthesis.** | W-138 | the document is with the user |

After the synthesis: the upstream patches (W-19), since the synthesis may change what is worth proposing.

## Conceptually complete

**The prototype is conceptually complete when bin A is empty and the cache of phase 3 is built or stopped.** From then on a measurement campaign is in order (phase 5).

## The three bins

- **A, before the measurement round:** the entry changes the mechanism or a rule that the round measures, or the rule is unsound, or a goal's claim does not hold without it.
- **B, to the synthesis:** a tension between goals, a port's question, or a design direction. Deciding it now would pre-empt the evidence. It stays recorded where it is.
- **C, accepted for the prototype:** it touches no goal's claim. The row or issue stays as it is.

### Bin A

**Decisions for the user.**

| Entry | The question |
|---|---|
| W-141 | A membership is a method: adopt the definition; step 1 as an experiment now; strict mode's rule for a third party's membership ([the proposal](2026-11-11-membership-as-method.md)) |
| Open issue 163, C-54 | A `where` variable bounded by a set and used by the body: compiled once or per type |
| Open issue 175 | What `keep` stores is visible beyond the trait, so a program's answers depend on the attribute |
| W-142 (3) | A result of an abstract type that is not a trait: a fault of fully typed code and of the build, or of neither |

**To build or close.**

| Entry | Why A | With |
|---|---|---|
| T-109, T-107, T-100, T-104, T-102; C-86, C-87 | G-6's claim: fully typed is exactly what compiles ahead | W-142 |
| Open issue 179, step (1) and the holes under the demonstrators' programs | G-6: a hole in Base fails a trait program's build | W-143 |
| Open issue 2 (§1; AOT annotations for calls into ordinary code) | To re-read against the closed build and W-142: closed or restated | W-142 |
| C-88; open issue 178 | W-140's rest: an edge missed where the IR interpreter infers a call is a missed invalidation | W-141 or W-128 |
| Open issue 167 | Invalidation passes through a split's branches (G-1) | W-128 |
| Open issue 168 | Members by a nominal supertype are not checked against declared results: unsound | W-128 |
| Open issues 173, 115, 116 | Written against rules that W-140 and the unified build changed: re-read, then closed or restated | W-128 |
| Open issue 160 | The cast names are reserved for all code: a plain package that uses them does not load (G-4, G-7) | W-128 |
| Open issue 176 | "Open" names three things (G-8): the terms | the references |
| Open issue 177; T-99, L-57, L-58 | G-5: where the trait form's messages fall short of plain Julia's | W-128 |
| C-30 (rest), C-31 | The member hook's state and its run in the compile queue: a check that can be skipped (G-1, G-3) | W-128 |
| C-45, C-49, C-50, C-56 | Code that runs under another policy or attribute than the rule says: G1 | W-128 |
| C-41, F-24, T-105 | The definition-time check: stale, inferred under the wrong policy, or not made | W-128 |
| C-55 | A set's default at a standard library's type differs from the rule | W-128 |
| T-96, T-97 | Strict mode's hook for a redefined binding; the warning for an extension's method | W-128 |
| L-56 | A cast in a call with keyword or splatted arguments is refused | W-128 |

**With the cache (phase 3).** C-52 (the record), C-39 (targets in the member's image), C-65, C-66, C-69 (what validation at load keeps), open issue 170 (a table's targets at a type no image saw). The cache's proposal says which of these it needs.

### Bin B

- **The tensions:** GT-2 to GT-12 and GT-14 (open issues §1), with C-67 and open issue 125 under GT-3.
- **The ports' questions:** open issues 157, 159, 161, 162, 165 (W-104); 150; 99; 148.
- **Design directions:** open issues 8, 9, 10, 12, 110, 112, 122, 129, 134, 151 to 156; 19 and 65 (owners); the ports' fresh-ideas round; W-143 (2) beyond the demonstrators' programs and (3).
- **Keys:** W-110, open issue 147 (deferred; PE-33).

### Bin C

- **Folds not made everywhere** (precision only): C-47, C-51, C-62, C-77, C-79.
- **Cost only:** C-40, C-61 (retired with the speed work); open issues 66, 166.
- **Order, tools, forms:** C-38, C-64, T-101, T-108, L-54.

## What is retired

The speed work, for good (the user, above). W-121 and what is left of W-129 are retired. [The performance explorations log](../record/performance-explorations.md) is closed: an archive, read for inspiration in phase 6 and later. Performance work is phase 6 alone, under its rule.

## Addendum, 2026-11-11 (night): bin A's decisions

- **Made** (the user: "I meant 2 not 1. So 2, 3, 4 with Kept is agreed. We can think about syntax sugar for this later."): the `where` variable is the value's type under either attribute (W-148); the storage's type decides what is stored, with `Kept{X}` (W-149); an abstract result is no fault (W-142).
- **W-141** (the user: "It is a conceptual simplification so I heavily lean towards adopting it. But I want to be sure the trade offs are manageable. So make a plan that builds it, but keep attention to managing and flagging where it might make problems."): built step by step under [its build plan](2026-11-11-membership-as-method-build.md), each step with a check that can stop it and a place where its problems are flagged.

## Addendum, 2026-11-12: bin A after the night

| Entry | State |
|---|---|
| W-141 | built through stage 2 (compiler C-89; E-367); waits for the user's decision; what it left is open issue 180 |
| The `where` variable (W-148; C-54) | done; C-54 retired |
| Kept values (W-149) | `Kept{X}` built in the library; the teaching stores without `keep`. Left: T-111 (a report of a `keep` into storage typed by the trait; the ODE port's six sites) |
| The abstract result (W-142 (3)) | done; T-110 retired. It showed that gate `n9`'s plain-callee case had passed through it (T-100) |
| The Base surface (W-143 (1)) | the tool is written and run (E-368) |
| The rest of bin A | open: W-142 (1), (2), (4), (5); W-128's rows |

## Addendum, 2026-11-12: W-141 decided

The user: "Conceptual parsimony for the user only requires implementation to behave like a method. The implementation can be whatever is simplest/cleanest/fastest." W-141 leaves bin A: a membership behaves as a method does, its method of the runtime's function is the implementation of the edges (compiler §5.6), and the method as the only record is not built. To bin B: open issue 180 (a), (c), (d), (f), (j), and strict mode's rule for a third party's membership (open issues §1). Bin A now holds W-142, W-143's tool and W-128.
