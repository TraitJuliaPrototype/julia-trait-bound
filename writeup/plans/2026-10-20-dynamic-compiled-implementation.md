# `Dynamic` and `Compiled`: the implementation plan (W-4)

**Status:** proposal (2026-10-20), for review before work starts. Not normative: the rule is [the proposal §0](2026-10-20-dynamic-and-compiled.md#0-the-rule-the-user-2026-10-20-this-section-supersedes-sections-1-and-1b-where-they-differ) (adopted and refined 2026-10-20); the references become its home in phase 1. Work item W-4 (`../record/todo.md`), open issue 33.

The user (2026-10-20): "Make a detailed implementation plan first. This implementation plan needs to include updating all documents on the website to the intended design. References first, then everything else."

## Contents

- [0. The rule in one paragraph](#0-the-rule-in-one-paragraph)
- [1. Phases and order](#1-phases-and-order)
- [2. Design choices the plan makes (mine, to confirm)](#2-design-choices-the-plan-makes-mine-to-confirm)
- [3. Phase 1: the references](#3-phase-1-the-references)
- [4. Phase 2: the other design documents](#4-phase-2-the-other-design-documents)
- [5. Phase 3: TraitWorld](#5-phase-3-traitworld)
- [6. Phase 4: the demonstrators, examples and experiments](#6-phase-4-the-demonstrators-examples-and-experiments)
- [7. Phase 5: the measurements](#7-phase-5-the-measurements)
- [8. Phase 6: documents that state the current state](#8-phase-6-documents-that-state-the-current-state)
- [9. Phase 7: close](#9-phase-7-close)
- [10. Risks and checkpoints](#10-risks-and-checkpoints)
- [11. Questions for the user](#11-questions-for-the-user)
- [Appendix A. Every document on the website](#appendix-a-every-document-on-the-website)
- [Appendix B. Code inventory](#appendix-b-code-inventory)

## 0. The rule in one paragraph

Every value in trait code is `Dynamic` or `Compiled`. It gets the attribute where it is first seen through a trait `X` (an argument's bound; an item parameter of a bound, when the item is read; a field or an operation's result declared with a trait): `Compiled{X}` if the code that sees it knows its concrete type, `Dynamic{X}` if its type is abstract there. A trait may declare `@dynamic` (`Callable` does). An annotation overrides the trait's default, on an argument (`f(x::Compiled{X})`, `f(x::Dynamic{X})`) or on an item parameter (`Iterable{Compiled{Mark}}`), without a warning. `compiled_for(x)` and `with_dynamic(x)` always win. A value keeps its attribute inside the trait world, also from library to library; an annotation decides only for values first seen there. An annotation on a function that is neither exported nor public warns. At the REPL, a call on an ordinary global is `Dynamic` (to revisit). No synonyms for `Callable`'s old modes. A mode chooses speed, never results.

## 1. Phases and order

| Phase | What | Repositories | Done when |
|---|---|---|---|
| 1 | **The references** written to the intended design: statuses Planned where not built, deviation rows where the code does something else | design | the references describe the rule, every changed section has a status line, `mkdocs build` passes its link validation |
| 2 | **The other design documents** (glossary, rationale, comparison, alternatives, open issues, the record's current documents) | design | no current document contradicts the references (grep list of §4.3 clean) |
| 3 | **TraitWorld** on a branch `dynamic-compiled` (worktree `TraitWorld-dyncomp/`) | TraitWorld | its tests and the acceptance suite pass in both settings |
| 4 | **The demonstrators, the documentation's examples, the experiments** moved to the new spelling and the new rule | TDE, TraitMakie, TraitTables, TraitCSV, TraitReport, experiments | `experiments/checks/run_all.sh` passes against the branches |
| 5 | **The measurements**, registry rows first, on a quiet machine | experiments | the rows in `record/experiments.md` and `design/evidence.md` |
| 6 | **The documents that state the current state** (`intro/`, results, state, README, evidence, performance, the demonstrators' READMEs) | design, demonstrators | the intro examples run in `experiments/docs-examples/` |
| 7 | **Close:** merge, statuses flipped, deviations retired, W-4 done, session note | all | the grep of §9 clean |

**Why phases 1–2 come before the code** (the user's order): the references are the source of truth and state the intended shape; a Planned status and a deviation row say what is not built. **Why `intro/` comes after the code:** `intro/` states the current state only (CLAUDE.md, "Teaching"), and its examples must run in `experiments/docs-examples/`. Phase 2 writes the rationale and the comparison to the intended design now; phase 6 rewrites what teaches and what measures.

**Commits:** each phase one or a few commits in each repository; phase 1 one commit per reference. Rule 1 of CLAUDE.md applies at phase 7: the fix that closes a deviation retires its row, flips its check and updates `state.md` in one commit.

**The machine:** one Julia job at a time through `flock /tmp/claude-1000/julia-review.lock nice -n 19`; precompile tasks 4; the measurements of phase 5 only on a quiet machine, asked of the user.

## 2. Design choices the plan makes (mine, to confirm)

These go to `../open-issues.md` §1 as "mine, to confirm" when phase 1 starts, and are written into the references as Planned.

**C1. The attribute is the value's representation.** `Compiled{X}` is a trait object (`TObj`) keyed as today; `Dynamic{X}` is an **erased trait object**: a `TObj` whose views have an erased key and an erased witness, holding the user's object as `Any`.
- Values carry by their type: a trait object passed on reaches the worker of its key, erased or not. Rules 7 and 9 need no machinery.
- **One worker per bounded function, as today.** The erased key is one more key: the worker compiled for it is the "compiled once per position" code. No second worker method, no second definition check.
- Operations on an erased view: the call-site split over the candidates, as an operation on a `Dynamic{X}` value is today (`Compiler.split_call`, the declared result type asserted).
- Declared fields on an erased view: read through the split as well, each branch reading the candidate's slot, the result asserted to the declared type (or the parameter value the bound fixes). Today `getproperty(::Dynamic, s)` dispatches at run time and returns `Any` (`core.jl:687`).
- Supertraits: the erased trait object has an erased view per trait of the closure, so a bound on a supertrait accepts it.
- Several bounds at one position, `(X, Y)`: an erased view per trait. The position works; the stored value `Dynamic{(X, Y)}` stays Planned.
- `Dynamic{X}` stays the stored value's type (fields, containers, plain code). At a bound it becomes the erased trait object (no opening); `Dynamic{X}(t)` from an erased trait object holds its user's object.
- *Alternative considered:* a second worker per bounded function whose argument is typed `Dynamic{<:X}` (the review's sketch). Simpler to start, but every bounded function gets two methods, definition checking must cover both, several bounds need `Dynamic{(X, Y)}` first, and the body sees two representations. Recorded in `design/alternatives.md` if C1 holds.

**C2. The entry decides, once, for plain values only.** For each trait position, in this order:
1. a trait object (erased or not) never reaches an entry from a worker (it takes the worker directly); from plain code it raises as today (`_rule3_error`);
2. a `Dynamic{X}`: the erased trait object of its held object (rule 7: carried, never opened);
3. a wrapper `compiled_for(x)`: opened by `x`'s type at run time, the worker for its key reached by one dispatch; `with_dynamic(x)`: erased;
4. a plain value: the annotation if any, else the trait's default if any, else `Compiler.known_type(x)` (`true`: compiled, the views assembled as today; `false`: erased).
- **Every entry's trait positions become `@nospecialize`**, also entries with keywords, varargs or `Callable` positions (today specialized per type, lowering §9.4), so that `known_type` is `false` exactly where the caller did not know the type. A typed caller inlines the entry and folds `known_type` to `true`.
- **The untyped callers' table retires** (lowering §9.2: `UTable`, the pattern method, `_pentry`, `XAny`, `untyped.jl`). An untyped caller now reaches the erased worker by a static call: the entry knows `X` from the bound. The conformance check of a value of unknown type is `@dynamic_of`'s split over the candidates (5 ns in the BaseTraits round), a dynamic call beyond them.
- **The entries compiled ahead for untyped callers retire** (lowering §9.3, `_ahead_entry!`): untyped callers no longer need code per declared type. The invalidation of plain code they caused (open issue §2 item 29) goes with them. Workers compiled ahead per declared key stay.

**C3. The wrappers.** `compiled_for(x)` and `with_dynamic(x)` are values of their own types (`CompiledFor{T}`, `WithDynamic{T}`), resolved by the next entry, as `CallAs` is today.
- Inside trait code, `with_dynamic(t)` on a trait object erases it directly (no trait needed: every view is erased); `compiled_for(t)` on an erased trait object or a `Dynamic` opens it, typed `Any`, so the next call dispatches once to the worker of its key (a function barrier). On a plain value of abstract type it is the wrapper, resolved by the next entry.
- `with_dynamic` makes a value that keeps the user's object: the keep analysis (lowering §8.4) counts it as keeping.

**C4. Items.** A bound's item parameter that names a trait (`Iterable{Mark}`, `Keyed{String, Mark}`, `Iterable{Pair{K, Mark}}`) is an *item position* with a mode: default, `Compiled`, `Dynamic`.
- The container always crosses through a view of BaseTraits, decided per (position, container type) as the crossing is today: `CompiledItems{Y}(v)`, whose reads build a trait object for the item, or `DynamicItems{Y}(v)`, whose reads build an erased one.
- Default mode: an element type that is concrete and conforms gives `CompiledItems` (a `Vector{Circle}`; the worker compiled per container type, the item's views folded); an abstract element type gives `DynamicItems`.
- `Compiled` mode with an abstract element type: `CompiledItems`, each read opening the item by its type (typed `Any` in the loop). `Dynamic` mode: always `DynamicItems`.
- Items already `Dynamic` (a `Vector{Dynamic{Plot}}`) are read as erased trait objects in every mode (rule 7).
- The bound's tag for the item parameter (today `PTag{F, i, Dynamic{Y}}`) becomes a tag "seen through `Y`" that both views carry; a container that is not one of the crossing types (`AbstractVector`, `AbstractDict`) and does not meet the bound is refused at the entry, as now.
- Writes store the user's object, as today.

**C5. `Callable`.** `Callable{A, S}` (no mode parameter) is a trait whose default is `@dynamic`.
- A worker's `Callable` argument stays `CObj{A, S, F}`: `F = Erased{A, S}` when `Dynamic`, the function's type when `Compiled`.
- `Dynamic{Callable{A, S}}` is the stored type (was `DynamicFn{A, S}`): it holds the `CObj{A, S, Erased{A, S}}`, and calling it reads the field at that asserted type, so the call stays typed. `Dynamic{Callable{A, S}}(f)` replaces `dynamic_fn(A, S, f)`.
- `compiled_for(f)`, `with_dynamic(f)` replace `compiled_call(f)`, `dynamic_call(f)`; `Compiled{Callable{A, S}}` replaces `Callable{A, S, CompiledCall}`. `CallAs`, `CallMode`, `DynamicCall`, `CompiledCall` are removed, and with them `Callable{A, S, M}(f)`.
- **Functions of the trait world** (Base's `abs2`, a trait module's functions and closures) are called directly whatever the mode, as today (`_from_trait_world`). Under the rule this needs a sentence: they are code the library already compiles against, not a user's value. Question Q1.

**C6. Declarations.** `@dynamic` in a trait's body sets the trait's default (`default_mode(::Type{F})`, folded). Rule 8's warning runs at the trait module's end: an annotated position of a function that is neither exported nor public in its owner module (`Base.ispublic`) warns once, naming the explicit conversion as the fix.

**C7. Abstract parts of a key** (traits §3.7): a trait object whose key has an abstract part is `Compiled` at that key, as now; the automatic opening of the part at the next bound goes: a field value of abstract type passed to a bound is a plain value of abstract type there, so `Dynamic` (rule 2).

## 3. Phase 1: the references

Written to the intended design (`reference/README.md`: "A Planned or Open item is written as the design intends it"). Each changed section gets a status line; where TraitWorld does something else today, a deviation row with a new ID. IDs are never renumbered: retired rows stay.

### 3.1 `reference/traits.md` (first)

| Section | Change |
|---|---|
| §1 Syntax summary | `Compiled{X}`, `Dynamic{X}` on arguments and item parameters; `compiled_for`, `with_dynamic`; `@dynamic`; `Callable{A, S}` without a mode |
| §3 (new §3.8, "A trait's default: `@dynamic`") | the declaration; `Callable` as the instance; a new subsection rather than a renumbering, so links hold |
| §3.7 Concreteness | the second bullet rewritten (C7): an abstract part of a key is compiled at that key; its field values are plain values of abstract type, `Dynamic` at the next bound. Interaction with `@concrete_only` at a `Dynamic` position: Q4 |
| §4 Keys | rewritten around the two attributes: `Compiled{X}` is compiled per key, `Dynamic{X}` once; receiver types stay here as what makes keys, the lowering of the erased key in lowering §5. The plan §3's refinement (only operations the function reaches count) stays out of W-4 (a separate item) |
| §6.1 Bounds | annotations on arguments and item parameters; `Dynamic{X}` in an argument annotation is a bound with a mode, no longer a typed argument (TDE's and TraitMakie's `c::Dynamic{ColorSpec}` methods change meaning; they accept a plain conforming value too) |
| §6.2 What a bounded function receives | a trait object, `Compiled` or `Dynamic`; what each costs |
| **new §6.6 "`Compiled` and `Dynamic`: how values enter"** | the rule (§0 above) as the reference's text: first seen through a trait, concretely or abstractly typed, the overrides in order, values carry, library to library, the REPL, the guidance for libraries (`Compiled` items pay off through calls). The proposal's table of three spellings |
| §6.3 What trait code may do | `compiled_for`, `with_dynamic` inside trait code; the table's `Dynamic` row |
| §6.5 Dispatch | a `Dynamic{X}` argument from plain code reaches the bounded method (it is not a typed method any more) |
| §7 Results | `Like` and `withfields` at a `Dynamic` position (the result made at run time; checkpoint R5) |
| §8 Keywords, defaults, varargs | bounded keywords and varargs take the attribute by the same rule |
| §9 `Callable` | rewritten: `Callable{A, S}`, its `@dynamic` default, `Compiled{Callable{A, S}}`, `compiled_for(f)`, `with_dynamic(f)`, `Dynamic{Callable{A, S}}` as the stored type (was `DynamicFn`), functions of the trait world (Q1). Every example changes |
| §10 `Dynamic{X}` | "Opened at a bound" removed: a `Dynamic` stays `Dynamic`; `compiled_for` opens it. "The trait's name as a type": in a bound's parameters it means items seen through the trait (rule 6), no longer its `Dynamic`; in fields and containers it still means its `Dynamic`. "Limit" (results through an opened `Dynamic`) rewritten |
| §10.2 Collections whose items are dynamic values | retitled ("Collections bounded by their items' trait"), the three spellings, `Vector{Circle}` compiled per item type; the line on `where` variables (T-16) narrowed: the item case no longer needs them |
| §10.3 A user's container | `CompiledItems` beside `DynamicItems`; which containers cross in which mode |
| §10.4 Algorithms | `retain!`'s `f::Callable{Tuple{Dynamic{Cell}}, Bool}` example in the new spelling |
| §11 Checks | rule 8's warning |
| §13 Concrete mode | what it reports now that an abstract value becomes `Dynamic` implicitly: Q3 |
| §15 Compiling ahead | entries ahead for untyped callers removed; workers ahead per key and for the erased key |
| §18 Status index | rows for every new item |
| §19 Deviations | new T- rows for what TraitWorld does otherwise until phase 3 lands (one row per behaviour: a `Dynamic` opened at a bound; the bare default by run-time type for untyped callers; `Iterable{Shape}` meaning `Iterable{Dynamic{Shape}}`; `Callable`'s mode parameter; `DynamicFn`; no `@dynamic`; no rule 8 warning; untyped field reads on a `Dynamic`). T-16's text narrowed |

### 3.2 `reference/lowering.md`

| Section | Change |
|---|---|
| §1 Summary | the erased key and the entry's decision |
| §5 Keys and views | the erased key and erased witness (C1); one worker per key, the erased key included |
| §7 Operations on a trait object | dispatch on an erased witness: the split; field reads through the split |
| §8.1 The rewrite | annotations parsed (`Compiled{X}`, `Dynamic{X}`, on item parameters); `@nospecialize` on every trait position |
| §8.2 The entry | the decision of C2, step by step |
| §8.4 Keeping | `with_dynamic` keeps |
| §9.2, §9.3, §9.4 | §9.2 and §9.4 replaced by "Untyped callers: the erased worker"; §9.3 reduced to workers ahead. The old text goes to `design/alternatives.md` and the record (L-11, L-12, L-13, L-24 retired at phase 7) |
| §10 Keywords | the decision for bounded keywords |
| §12 `Callable` | C5 |
| §13 `Dynamic{X}` | no opening at a bound; a `Dynamic` at an entry becomes the erased trait object; `getproperty` through the split |
| §13.1 Crossing | generalized to item positions with a mode (C4) |
| §15 Closed builds | the erased worker's split lists every declared implementation; `close_world!` fills the crossing flags (L-27 stays until done) |
| §17 Encodings | the annotation types as encodings until traits are in the type system |
| §18 Deviations | new L- rows as for traits §19 |

### 3.3 `reference/compiler.md` and `reference/facts.md`

- compiler §4.1 `known_type`: TraitWorld's use is now the choice between `Compiled` and `Dynamic` at the entry (the rule "only between paths that compute the same result" holds: a mode never changes results). §4.2 `split_call`: also for field reads on erased views. §3.3: unchanged, cited by the guidance.
- facts: the guarantees for code at a `Dynamic` position (no edge to the set of implementations; the split's branches are facts), stated where `DynamicCall` and the split are stated today; any sentence naming `DynamicCall`/`CompiledCall`.

### 3.4 Order inside phase 1

traits → lowering → compiler → facts; then the decision log row that links the reference sections (rule 1 of CLAUDE.md: a decision is in force once it is in a reference); then `mkdocs build` with its validation.

## 4. Phase 2: the other design documents

### 4.1 The documents

| Document | Change |
|---|---|
| `glossary.md` | new: *Compiled*, *Dynamic* (as attribute), *first seen through a trait*, `compiled_for`, `with_dynamic`, `@dynamic`, *erased trait object*, *item position*; changed: `Callable`, `Dynamic{X}`, *function barrier*, *untyped caller*; removed: `DynamicCall`, `CompiledCall`, `DynamicFn` (each pointing to its replacement) |
| `design.md` (the rationale) | where it argues `Callable`'s modes and `Dynamic` (6 places): one language, the Rust/Swift precedent (the static type decides), the cost model; no rules of its own |
| `design/other-languages.md` | `dyn`/`any` against `Dynamic`, generics against `Compiled`: the comparison now matches the rule; the collections paragraph (`impl Iterator<Item = &dyn Shape>`) gets the three spellings |
| `design/alternatives.md` | new entries: `Dynamic` opened at every bound; the default by run-time type (proposal §0 first form); `Callable`'s mode parameter; the disagreement warning; synonyms; the second worker (C1's alternative); the untyped callers' table and the entries ahead (retired by C2) |
| `open-issues.md` | item 33 closed by the references (phase 1) and the code (phase 7); items touched: 16 (opening at the object's concrete type: now `compiled_for` plus an assertion), 29 (entries ahead invalidating plain code: closed with C2), 32 (the split's fallback: unchanged, now on more paths), §2.15 (the solvers' model mode: absorbed), traits §5.9 `dynamic by` (absorbed? Q2); §1 gets C1–C7 as "mine, to confirm" and Q1–Q5 |
| `design/julia-changes.md` | `known_type`'s use |
| `design/performance.md` | the cost model of the two attributes (the measured numbers come in phase 6) |
| `state.md` | §6 (the order of work): W-4 in progress; the target software |
| `record/decisions.md` | rows for C1–C7 (mine), for the user's answers to Q1–Q5 |
| `record/experiments.md` | rows E-147 to E-150 before any run (§7) |
| `record/todo.md` | W-4's status and steps; W-2 written in the new spelling |
| `record/INDEX.md` | this plan and its review listed |
| `record/design-history.md` | one entry: the two modes of `Callable` and the opening at every bound, replaced by the rule |

### 4.2 Not changed (history)

Reviews, plans, session notes, `record/other-languages-research-2026-10-16.md`, `design-findings.md`, `explorations/*`, `design/implementation.md` and `design/mechanisms.md` (retired pointers), `attic/`. CLAUDE.md rule 2: they are history.

### 4.3 The grep at the end of phase 2

`DynamicCall|CompiledCall|compiled_call|dynamic_call|DynamicFn|dynamic_fn|opened at a bound|Callable\{[^}]*, *(Dynamic|Compiled)Call`, and "a trait's name in a bound's parameters means its `Dynamic`", over every current document of Appendix A. Remaining hits only in deviation rows, alternatives and history.

## 5. Phase 3: TraitWorld

Branch `dynamic-compiled` from main (5b172e1), worktree `TraitWorld-dyncomp/`. Baseline before the first change: the full suite and the acceptance suite in both settings, logged (`experiments/checks/logs/before-dyncomp/`). Steps, each a commit with its tests:

| Step | What | Files |
|---|---|---|
| 3.1 | **The erased key and witness** (C1): `View` with an erased key and witness; `_dispatch` on it through `Compiler.split_call`; typed field reads through the split; the erased trait object of a `Dynamic` and of a value of unknown type (`@dynamic_of`'s check); printing (`Dynamic{X} at <type>`); equality as `Dynamic`'s | `core.jl`, `trait.jl`, `compiler.jl` |
| 3.2 | **The worker accepts the erased trait object:** the worker's signature (`tobj_bound`) admits the erased views' trait set; definition checking unchanged (one body); the keep analysis at the erased key | `trait_module.jl`, `defcheck.jl` |
| 3.3 | **The entry's decision** (C2): `@nospecialize` on every trait position; `known_type`; a `Dynamic` erased, not opened; tests that a typed caller compiles per key and an untyped one compiles the erased worker once | `entry.jl`, `trait_module.jl` |
| 3.4 | **Annotations and the trait default** (C6): `_classify` reads `Compiled{X}`, `Dynamic{X}` on arguments and keywords; `@dynamic` in `@trait`; rule 8's warning at the module's end | `trait_module.jl`, `trait.jl` |
| 3.5 | **The wrappers** (C3): `compiled_for`, `with_dynamic`, outside and inside trait code; the keep analysis counts `with_dynamic` | `core.jl`, `entry.jl`, `defcheck.jl` |
| 3.6 | **`Callable`** (C5): `Callable{A, S}`, `@dynamic`, `Dynamic{Callable{A, S}}`; `CallAs`, `CallMode`, `DynamicCall`, `CompiledCall`, `DynamicFn`, `dynamic_fn`, `compiled_call`, `dynamic_call` removed; the exports | `core.jl`, `entry.jl`, `TraitWorld.jl`, `implement.jl` (`Erased` uses) |
| 3.7 | **Items** (C4): item positions with a mode in `_classify`; `CompiledItems` beside `DynamicItems`; the crossing decided per (position, container type, mode); the tag "seen through `Y`" | `BaseTraits.jl`, `entry.jl`, `trait_module.jl` |
| 3.8 | **Retire the untyped table and the entries ahead** (C2): `untyped.jl`, the pattern methods, `_pentry`; `_ahead_entry!`; their tests rewritten as tests of the erased path | `untyped.jl`, `ahead.jl`, `trait_module.jl`, `hooks.jl` |
| 3.9 | **Abstract key parts** (C7): the automatic opening removed | `entry.jl` |
| 3.10 | **Closed builds and `verify_main`:** the erased worker's split complete over the declared implementations; the machinery list updated; a trimmed build of a small example (`experiments/sysimage` or the existing trim script) | `verify.jl`, `certificate.jl` |
| 3.11 | **The tests:** every file of `test/` reviewed for top-level calls whose behaviour changes (a top-level call is now `Dynamic`; results do not change, but checks on compiled specializations, allocations and `@inferred` do); new tests per rule (§0 rules 1–9, each with a positive and a negative case) | `test/` |

Each step runs the TraitWorld suite in the product setting; steps 3.3, 3.8 and 3.11 also under `all` and the acceptance suite (`experiments/facts/acceptance_compiler.jl`, 23 checks), with new G2 cases: a new implementation loaded after code at a `Dynamic` position was compiled discards nothing.

## 6. Phase 4: the demonstrators, examples and experiments

Each on a branch `dynamic-compiled`.

- **Finding the sites that relied on opening:** a temporary counter in the entry's `Dynamic` branch on main (not committed to the branch), run over every demonstrator's suite, lists each call site where a `Dynamic` was opened at a bound. Each such site is decided: `compiled_for` (the work per value is large or a loop), or left `Dynamic`.
- **TraitDifferentialEquations** (6 files, 40 lines with the old spelling): `DynamicFn` fields become `Dynamic{Callable{…}}`; `ODEProblem(compiled_call(f), …)` becomes `compiled_for(f)`; `solve_rhs`'s bounds; callbacks (`Dynamic{Callback}`, `Dynamic{IntegratorView}`); the README. W-2 (the problem trait) stays after W-4.
- **TraitTables:** `summarize(t.cols[k], …)`, `cellstring`, `take`, `nrows`: `compiled_for` where a column's loop runs (the module comment says each column's code runs compiled per column type: kept true by `compiled_for`).
- **TraitMakie** (47 `Dynamic{` uses): the drawing loops (`for p in ax.plots`, PlotCore.jl:545, :573) with `compiled_for(p)` or `Iterable{Compiled{Plot}}` where items are first seen there (they are not: stored `Dynamic`, rule 7, so `compiled_for`); `setcolor!(p, c::Dynamic{ColorSpec})` now a bound in `Dynamic` mode.
- **TraitCSV, TraitReport:** follow TraitTables; TraitCSV's `Dynamic{Column}` results.
- **`experiments/docs-examples/`** (`tutorial.jl`, `reference.jl`; 14 lines with the old spelling): the new spelling; examples for each rule, used by phase 6's `intro/`.
- **Experiments with the old spelling** (`factscompiler` 4 files, `examples` 2, `world`, `hetero-idiomatic`, `facts`): scripts that are rerun get the new spelling; the others keep their logs and a line in their README: "written for the spelling before W-4 (TraitWorld ≤ 5b172e1)".
- **`forks/`** (1 file, 2 lines): the new spelling when the forks resume (W-14); a line in its README now.
- **The full check:** `experiments/checks/run_all.sh dyncomp` against the branches.

## 7. Phase 5: the measurements

Registry rows first (`record/experiments.md`), each with its question and the result that would change the design. Product setting and `all`; three runs; rows timed whole, the garbage collector's time reported (`rows.jl`'s `@first`); the build (TraitWorld commit, julia-1.13 commit); a quiet machine.

| ID | Question | Would change the design if |
|---|---|---|
| E-147 | TDE: a new model type (`ODEModel{Float64}`) at a `Dynamic` position against `Compiled`: first solve in a fresh session, run time per step; the new type among the split's first four declared implementations and beyond them | the per-step cost at `Dynamic` beyond four is large enough that a library cannot choose `Dynamic` for a solver (E-145's question becomes urgent) |
| E-148 | Untyped callers: the erased worker against the retired table (TraitWorld 5b172e1): ns per call, bytes, first-call latency, for one and several trait positions, at the REPL and from code typed `Any` | the erased path is slower than the table by more than its saving in code (then keep the table as a lowering of `Dynamic`) |
| E-149 | The demonstrators before and after (TDE, TraitMakie, TraitTables, TraitReport rows; `experiments/hetero-idiomatic` r-rows): every row in the product setting, three load orders | a row gets slower by more than its noise, and no `compiled_for` site recovers it |
| E-150 | Items: `Iterable{Mark}` over `Vector{Circle}` (compiled per item type) against `Vector{Any}` (dynamic), `Iterable{Compiled{Mark}}` with work per item through a call and through direct operations (the guidance's claim) | the guidance's claim fails (then the reference's guidance changes) |

Evidence rows (`design/evidence.md`) with each finished row, in the same commit.

## 8. Phase 6: documents that state the current state

After phases 3–5:
- `intro/traits-for-julia.md` ("What you write", the worked example, "What it costs"), `intro/traits-by-example.md` (§4 bounded functions: the attribute; §12 `Dynamic` rewritten; §14 `Callable` rewritten; §9 keywords; §17 concrete mode; §20 planned syntax), `intro/porting.md` (the `Callable` and `Dynamic` lessons), `intro/results.md` (numbers by link to the evidence): every example run in `experiments/docs-examples/`.
- `README.md` (the home page), `state.md` (what is built), `design/evidence.md` and `design/performance.md` (numbers), the demonstrators' READMEs (dated tables of their own; current numbers by link), TraitWorld's README.

## 9. Phase 7: close

- Merge `dynamic-compiled` into each repository's main, after `run_all.sh` passes on the merged mains.
- The references' statuses flipped to Implemented; the T- and L- rows of phase 1 retired with their commits; L-11, L-12, L-13, L-24 retired (their mechanism removed); T-16 narrowed. One commit per reference with `state.md` (CLAUDE.md rule 1).
- Open issue 33 closed; W-4 done; the decision log's rows marked built.
- The grep of §4.3 over every repository; the session note; the resume memory.

## 10. Risks and checkpoints

- **R1. `known_type` through keyword calls and varargs.** A typed caller's call with keywords goes through `Core.kwcall`; if the entry is not inlined there, `known_type` is `false` and a typed caller would get `Dynamic`. Checkpoint at step 3.3: a test per entry shape (positional, keywords, vararg, `Callable`) that a typed caller gets the compiled worker.
- **R2. Tests that call from the top level.** They now run `Dynamic`. Results do not change; checks on specializations, allocation counts and timing do. Step 3.11 reviews every test file (14 files, 443 tests at 5b172e1).
- **R3. Performance where `Dynamic` replaces the opening.** TraitTables' and TraitMakie's loops; TDE's callbacks. E-149 is the check; the counter of phase 4 finds the sites.
- **R4. The untyped table's retirement** removes an optimized path (105–117 ns per untyped call, open issues §4 item 9). E-148 decides; if the erased path loses, the table stays as the lowering of an untyped caller's `Dynamic`.
- **R5. `Like` and `withfields` at a `Dynamic` position:** the result's type is the user's, unknown to the erased worker; made at run time (`_like_out` after an inference barrier). Checkpoint at step 3.2.
- **R6. Closed builds:** the erased worker in a `--trim` build. Checkpoint at step 3.10.
- **R7. Guarantees:** the facts mode's G2 at `Dynamic` positions (the acceptance suite's new cases).
- **R8. The meaning of `x::Dynamic{X}` in existing bounded functions changes** (a typed argument becomes a bound in `Dynamic` mode). The demonstrators' uses are listed in phase 4; operations declared with a `Dynamic{X}` argument inside `@trait` keep the type's meaning (an operation's arguments are typed as in a method), to be stated in traits §3.1.

## 11. Questions for the user

- **Q1. Functions of the trait world under `Callable`'s `@dynamic`:** keep calling them directly (compiled per function, today's `_from_trait_world`), stated as part of the rule ("a function the library's own code already knows is not a user's value"), or erase them too?
- **Q2. `dynamic by` (traits §5.9)** and the solvers' model mode (open issue §2.15): absorbed by `Dynamic` positions (plan §2). Remove `dynamic by`?
- **Q3. Concrete mode** (traits §13) reports abstract types in trait code. A value of abstract type is now `Dynamic` by rule: does concrete mode report the implicit `Dynamic` (it is still an abstract type in the caller), or only abstract types that reach plain code?
- **Q4. `@concrete_only` traits** (traits §3.7) at a `Dynamic` position: refuse the position, or accept it (the key is not abstract, it is erased by choice)?
- **Q5. C1–C7** as above.

## Appendix A. Every document on the website

From `mkdocs.yml`'s navigation, with the phase that changes it (— for history, left as it is).

| Section | Document | Phase |
|---|---|---|
| Home | `README.md` | 6 |
| For programmers | `intro/traits-for-julia.md`, `intro/traits-by-example.md`, `intro/porting.md`, `intro/results.md` | 6 |
| | `glossary.md` | 2 |
| For core developers | `state.md` | 2 (order of work), 6 (what is built) |
| | `design.md` | 2 |
| | `design/evidence.md`, `design/performance.md` | 2 (cost model), 5–6 (numbers) |
| | `design/julia-changes.md`, `design/other-languages.md`, `design/alternatives.md`, `open-issues.md` | 2 |
| The references | `reference/README.md` (conventions: unchanged unless the annotation types need a convention), `traits.md`, `facts.md`, `compiler.md`, `lowering.md` | 1 |
| The record | `record/INDEX.md`, `record/decisions.md`, `record/experiments.md`, `record/todo.md` | 2, 5, 7 |
| | `record/other-languages-research-2026-10-16.md`, `writeup/README.md`, `explorations/wrapping-by-facts.md`, `explorations/strict-mode.md`, `design-findings.md`, `record/design-history.md` (one entry), `design/implementation.md`, `design/mechanisms.md`, `session-notes/00-environment-and-workflow.md` | — |

Lines matching `Dynamic|DynamicCall|CompiledCall|compiled_call|dynamic_call|DynamicFn|dynamic_fn|Callable|function barrier|opened|known_type|untyped caller` per current document (2026-10-20): traits 112, lowering 71, open-issues 47, other-languages 39, traits-by-example 26, porting 23, glossary 22, traits-for-julia 21, alternatives 18, state 15, facts 11, compiler 9, evidence 8, results 7, design 6, performance 6, julia-changes 5, README 3, INDEX 7.

## Appendix B. Code inventory

TraitWorld (main 5b172e1, 8,994 lines in `src/`):
- `core.jl` (933): `Trait`, `CallMode`/`DynamicCall`/`CompiledCall` (:30), `Callable{A, S, M}` (:33), views and keys (:50–:101), `TObj` (:214), `Dynamic` (:351), `_narrow` (:408), `opened` (:438), `_DynOp` (:448), `_dyn_identity` (:475), `DynamicOf`/`@dynamic_of` (:489–:500), candidates (:532), field access on `Dynamic` (:687), `_PtrCell`, `Erased` (:697–:737), `Dyn` (:737), `_dispatch` (:812), `CObj` (:763), `CMulti` (:790).
- `entry.jl` (905): `enter` (:193), `Crossing`/`crossing`/`crossed` (:215–:250), `_crosses` (:249), `_rule3_error` (:267), `_assemble` (:225), `_conformance_slow` (:144), `fallback` (:484), `_from_trait_world` (:531), `enter_callable` (:569), `dynamic_fn` (:617).
- `trait_module.jl` (955): `_dynamic_fields` (:143), `_dynamic_containers` (:179), `_rewrite_fdef` (:426), `tobj_bound` (:470), the entry's generation (:540–:713, the tabled path :640–:700), `_fix_needed!`/`_fix_crossing!` (:773–:776), `_finish_module` (:794).
- `untyped.jl` (257): the table, the pattern methods, `_pentry`, `_UWrap`: retired at step 3.8.
- `ahead.jl` (195): `_ahead_entry!` (:168): reduced at step 3.8.
- `BaseTraits.jl` (218): the traits, `DynamicItems`, `DynamicValues`, `crossed` (:174), `retain!`.
- `trait.jl` (341): operations on `Dynamic` (:320).
- `defcheck.jl` (305): definition checking, `_analyze_keeps` (:277).
- `verify.jl` (1,108), `certificate.jl` (97), `hooks.jl` (267), `implement.jl` (1,472; `Erased` uses), `TraitWorld.jl` (196; exports).
- Tests: 14 files, 2,360 lines, 443 tests.

Old spelling in code (`compiled_call|dynamic_call|DynamicCall|CompiledCall|DynamicFn|dynamic_fn`): TraitWorld `src` 26 lines in 4 files, `test` 11 lines in 2; TraitDifferentialEquations 40 lines in 6; `experiments/docs-examples` 14 lines in 2; other experiments 9 files; `forks` 2 lines.
