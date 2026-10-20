# `Dynamic` and `Compiled`: the implementation plan (W-4)

**Status:** proposal, revision 2 (2026-10-20): revised after the Fable review ([`../reviews/2026-10-20-dynamic-compiled-plan.md`](../reviews/2026-10-20-dynamic-compiled-plan.md); what was done with each finding: [§12](#12-the-reviews-findings-and-what-was-done)) and the user's answers (C1–C7 confirmed; Q2, Q3, Q4 answered). Open questions: [§11](#11-questions-for-the-user). Not normative: the rule is [the proposal §0](2026-10-20-dynamic-and-compiled.md#0-the-rule-the-user-2026-10-20-this-section-supersedes-sections-1-and-1b-where-they-differ); the references become its home in phase 1. Work item W-4 (`../record/todo.md`), open issues 33 and 34.

The user (2026-10-20): "Make a detailed implementation plan first. This implementation plan needs to include updating all documents on the website to the intended design. References first, then everything else." On the first revision: "C1-C7 look good."

## Contents

- [0. The rule in one paragraph](#0-the-rule-in-one-paragraph)
- [1. Phases and order](#1-phases-and-order)
- [2. Design choices (C1–C8)](#2-design-choices-c1c8)
- [3. Phase 1: the references](#3-phase-1-the-references)
- [4. Phase 2: the other design documents](#4-phase-2-the-other-design-documents)
- [5. Phase 3: TraitWorld](#5-phase-3-traitworld)
- [6. Phase 4: the demonstrators, examples and experiments](#6-phase-4-the-demonstrators-examples-and-experiments)
- [7. Phase 5: the measurements](#7-phase-5-the-measurements)
- [8. Phase 6: documents that state the current state](#8-phase-6-documents-that-state-the-current-state)
- [9. Phase 7: close](#9-phase-7-close)
- [10. Risks and checkpoints](#10-risks-and-checkpoints)
- [11. Questions for the user](#11-questions-for-the-user)
- [12. The review's findings and what was done](#12-the-reviews-findings-and-what-was-done)
- [Appendix A. Every document on the website](#appendix-a-every-document-on-the-website)
- [Appendix B. Code inventory](#appendix-b-code-inventory)

## 0. The rule in one paragraph

Every value in trait code is `Dynamic` or `Compiled`. It gets the attribute where it is first seen through a trait `X` (an argument's bound; an item parameter of a bound, when the item is read; a field or an operation's result declared with a trait): `Compiled{X}` if the code that sees it knows its concrete type, `Dynamic{X}` if its type is abstract there. A trait may declare `@dynamic` (`Callable` does). An annotation overrides the trait's default, on an argument (`f(x::Compiled{X})`, `f(x::Dynamic{X})`) or on an item parameter (`Iterable{Compiled{Mark}}`), without a warning. `compiled_for(x)` and `with_dynamic(x)` always win. A value keeps its attribute inside the trait world, also from library to library; an annotation decides only for values first seen there. An annotation on a function that is neither exported nor public warns. At the REPL, code Julia does not compile knows no types, so its calls are `Dynamic` (to revisit; Q6). No synonyms for `Callable`'s old modes. A mode chooses speed, never results.

## 1. Phases and order

| Phase | What | Repositories | Done when |
|---|---|---|---|
| 1 | **The references** written to the intended design: statuses Planned where not built, deviation rows where the code does something else; each design choice's decision-log row in the commit of the reference that states it | design | the references describe the rule, every changed section has a status line, `mkdocs build` passes its link validation |
| 2 | **The other design documents** (glossary, rationale, comparison, alternatives, open issues, the record's current documents; `intro/traits-by-example.md` §20, planned syntax) | design | the grep of §4.3 clean, with the phase-6 documents as expected hits |
| 3 | **TraitWorld** on a branch `dynamic-compiled` (worktree `TraitWorld-dyncomp/`), from a spike on main (step 3.0) | TraitWorld | its tests and the acceptance suite pass in both settings |
| 4 | **The demonstrators, the documentation's examples, the experiments** moved to the new spelling and the new rule | TDE, TraitMakie, TraitTables, TraitCSV, TraitReport, experiments | `run_all.sh` passes with every repository checked out at `dynamic-compiled` |
| 5 | **The measurements**, registry rows first, on a quiet machine; then the decision on the untyped table (step 3.8) | experiments, TraitWorld | the rows in `record/experiments.md` and `design/evidence.md` |
| 6 | **The documents that state the current state** (`intro/`, results, state, README, evidence, performance, the demonstrators' READMEs) | design, demonstrators | the intro examples run in `experiments/docs-examples/` |
| 7 | **Close:** merge, statuses flipped, deviations retired, W-4 done, session note | all | the grep of §9 clean |

**Why phases 1–2 come before the code** (the user's order): the references are the source of truth and state the intended shape; a Planned status and a deviation row say what is not built. **Why `intro/` comes after the code:** `intro/` states the current state only (CLAUDE.md, "Teaching"), and its examples must run in `experiments/docs-examples/`. Its §20 ("Planned syntax", checked by `reference.jl` as planned) shows the new forms in phase 2.

**Commits:** each phase one or a few commits in each repository; phase 1 one commit per reference, with the decision-log rows for the choices that reference states (CLAUDE.md rule 1). At phase 7 the fix that closes a deviation retires its row, flips its check and updates `state.md` in one commit.

**The machine:** one Julia job at a time through `flock /tmp/claude-1000/julia-review.lock nice -n 19`; precompile tasks 4; the measurements of phase 5 only on a quiet machine, asked of the user.

## 2. Design choices (C1–C8)

C1–C7 confirmed by the user (2026-10-20: "C1-C7 look good"), with the changes the review asked for marked *(rev. 2)*. C8 is new in revision 2 and waits for Q8.

**C1. The attribute is the value's representation.** `Compiled{X}` is a trait object (`TObj`) keyed as today; `Dynamic{X}` is an **erased trait object**: a `TObj` whose views have an erased key and an erased witness, holding the user's object as `Any`.
- Values carry by their type: a trait object passed on reaches the worker of its key, erased or not. Rules 7 and 9 need no machinery.
- **One worker per bounded function, as today.** The erased key is one more key: the worker compiled for it is the "compiled once per position" code.
- Operations on an erased view: the call-site split over the candidates, as an operation on a `Dynamic{X}` value is today (`Compiler.split_call`, the declared result type asserted).
- Declared fields on an erased view: read through the split as well, each branch reading the candidate's slot, the result asserted to the declared type (or the parameter value the bound fixes). Today `getproperty(::Dynamic, s)` dispatches at run time and returns `Any` (`core.jl:687`).
- Supertraits: an erased view per trait of the closure. Several bounds at one position, `(X, Y)`: an erased view per trait; the stored value `Dynamic{(X, Y)}` stays Planned.
- **Fixed parameters** *(rev. 2)*: the bound's tags (`PTag{F, i, v}`, `trait_module.jl:495–499`) are attached to an erased trait object only after the entry checks the parameter's value, per candidate and dynamically in the fallback.
- **The seams** *(rev. 2)*: `Dynamic{X}` stays the stored value's type. Where a slot is typed `Dynamic{X}`, an erased trait object of `X` is converted to a `Dynamic{X}` on the way in (it keeps the user's object); at a bound a `Dynamic{X}` becomes the erased trait object. The slots: an operation's declared argument (`opcall`'s `args isa op_args`, `core.jl:797`; TDE's `condition`, `affect!`), a `Callable`'s argument types `A` (`CObj`'s `args isa A`, `core.jl:902`; the `Erased` pointer's declared types, `_cdecl`, `core.jl:860`), a field, a container's item, a `Like` result (`_like_out`, `entry.jl:827`). Written into lowering §13 as one rule with this list.

**C2. The entry decides, once, for plain values only.** For each trait position, in this order:
1. a trait object (erased or not) never reaches an entry from a worker (it takes the worker directly); from plain code it raises as today (`_rule3_error`);
2. a `Dynamic{X}`: the erased trait object of its held object (rule 7: carried, never opened);
3. a wrapper `compiled_for(x)`: opened by `x`'s type at run time, the worker for its key reached by one dispatch; `with_dynamic(x)`: erased;
4. a plain value: the annotation if any, else the trait's default if any, else `Compiler.known_type(x)` (`true`: compiled, the views assembled as today; `false`: erased).
- **Every entry's trait positions become `@nospecialize`**, also entries with keywords, varargs or `Callable` positions (today specialized per type, lowering §9.4), so that `known_type` is `false` exactly where the caller did not know the type. A typed caller inlines the entry and folds `known_type` to `true` (the spike of step 3.0 checks every entry shape first).
- **An untyped caller reaches the erased worker by a static call:** the entry knows `X` from the bound. The conformance check of a value of unknown type is `@dynamic_of`'s split over the candidates, a dynamic call beyond them.
- *(rev. 2)* **The untyped callers' table stays, as the lowering of `compiled_for(x)` for a value of unknown type** (and of `Compiled` items in `Compiled` mode), until E-148 and E-150 decide: it is the one-dispatch path (`_pentry`, `untyped.jl:252`) that the rule's guidance needs ("`draw(m)` dispatches once per item"). Without it, `compiled_for` from an untyped caller costs two run-time dispatches and an allocation (`_assemble`, `entry.jl:374`; `checked_call`). The entries compiled ahead (`_ahead_entry!`, `ahead.jl:168`) stay for the same reason; their per-type entry for shapes the table does not serve (`ahead.jl:146–153`) goes, since `@nospecialize` makes it `f(::Any, …)`. Retiring the table is step 3.8, after phase 5, by the criterion in E-148's row. Open issue §2 item 29 (their invalidation of plain code) is narrowed, not closed.

**C3. The wrappers.** `compiled_for(x)` and `with_dynamic(x)` are values of their own types (`CompiledFor{T}`, `WithDynamic{T}`), resolved by the next entry, as `CallAs` is today.
- Inside trait code, `with_dynamic(t)` on a trait object erases it directly (every view erased); `compiled_for(t)` on an erased trait object or a `Dynamic` opens it, typed `Any`, so the next call dispatches once to the worker of its key (a function barrier). On a plain value of abstract type it is the wrapper, resolved by the next entry through the table (C2).
- `with_dynamic` makes a value that keeps the user's object: the keep analysis (lowering §8.4) counts it as keeping.

**C4. Items.** A bound's item parameter that names a trait (`Iterable{Mark}`, `Keyed{String, Mark}`, `Iterable{Pair{K, Mark}}`) is an *item position* with a mode: default, `Compiled`, `Dynamic`.
- The container crosses through a view of BaseTraits, decided per (position, container type) as the crossing is today: `CompiledItems{Y}(v)`, whose reads give a trait object of the item, or `DynamicItems{Y}(v)`, whose reads give an erased one.
- Default mode: a concrete element type that conforms gives `CompiledItems` (a `Vector{Circle}`; the worker compiled per container type, the item's views folded); an abstract element type gives `DynamicItems`. `Compiled` mode with an abstract element type: `CompiledItems`, each read opening the item by its type through the table (typed `Any` in the loop). `Dynamic` mode: always `DynamicItems`.
- *(rev. 2)* **A `Vector{Dynamic{X}}` crosses into `DynamicItems{X}` in every mode** (its items are already `Dynamic`, rule 7); it no longer meets the bound as it is.
- *(rev. 2)* **The item type the worker sees** (`T = eltype(Self)`, `BaseTraits.jl:45`; the archetype's `iterate` at definition checking, `defcheck.jl:64–77`) is the view's item trait object: the erased view type of `Y` for `DynamicItems`, the item's keyed view type for `CompiledItems`. Both carry `Y`'s operations and are accepted by `Y`'s bounds. The bound's tag for the item parameter (today `PTag{F, i, Dynamic{Y}}`) becomes a tag "seen through `Y`" (`Through{Y}`), carried by both views. Written as a row of lowering §17.
- Writes store the user's object, as today.

**C5. `Callable`.** `Callable{A, S}` (no mode parameter) is a trait whose default is `@dynamic`; it keeps its own lowering (lowering §12), not a `@trait` declaration.
- A worker's `Callable` argument stays `CObj{A, S, F}`: `F = Erased{A, S}` when `Dynamic`, the function's type when `Compiled`.
- `Dynamic{Callable{A, S}}` is the stored type (was `DynamicFn{A, S}`): a `Dynamic` holding the `CObj{A, S, Erased{A, S}}`; a call reads the field at that asserted type. *(rev. 2)* This adds a heap object and a load with a type assertion per call against today's inline `DynamicFn`; E-147 measures it on a row of its own.
- `compiled_for(f)`, `with_dynamic(f)` replace `compiled_call(f)`, `dynamic_call(f)`; `Compiled{Callable{A, S}}` replaces `Callable{A, S, CompiledCall}`; `Dynamic{Callable{A, S}}(f)` replaces `dynamic_fn(A, S, f)`. `CallAs`, `CallMode`, `DynamicCall`, `CompiledCall` are removed. *(rev. 2)* `Callable{A, S, M}(f)`, which also fixed the signature, is removed without a `Compiled` counterpart: a wrapper takes the signature of the position it reaches.
- **Functions of the trait world** (Base's `abs2`, a trait module's functions and closures): Q1.

**C6. Declarations.** `@dynamic` in a trait's body sets the trait's default (`default_mode(::Type{F})`, a method per trait, folded; lowering §3). Rule 8's warning runs at the trait module's end, where `export` and `public` are known: an annotated position of a function that is neither exported nor public in its owner module (`Base.ispublic`) warns once, naming the explicit conversion as the fix. Bounded functions exist only in trait modules, so a definition at the prompt is in a module too.

**C7. Abstract parts of a key** (traits §3.7): a trait object whose key has an abstract part is `Compiled` at that key, as now; the automatic opening of the part at the next bound goes: a field value of abstract type passed to a bound is a plain value of abstract type there, so `Dynamic` (rule 2).

**C8. Which candidates an erased worker splits over** *(rev. 2, new; waits for Q8)*. A caller splits over the candidates registered when it is compiled (compiler §4.2; `trait.jl:318–320`), registered in declaration order, the library's at its load and the user's later (`_note_conformances!`, `core.jl:532`). So:
- an erased worker compiled into a package image splits over that package's and its dependencies' implementations; a user's type takes the fallback at every operation;
- an erased worker compiled in the session splits over the first four declared, which are the library's own when it declares four or more.
- The fallback's price was measured in idiomatic code: 1.0–2.0 ns per item inside the split, 8.4–9.3 ns at five types, 160–180 ns at 64 (E-144). For a solver at a `Dynamic` position the fallback may be the common case, which makes open issue 32 (what follows the split; E-145) part of W-4's value, not Optional.
- Stated in traits §6.6 (the cost paragraph) and lowering §13, §15. E-147 measures both placements of the worker (Q8).

## 3. Phase 1: the references

Written to the intended design (`reference/README.md`: "A Planned or Open item is written as the design intends it"). Each changed section gets a status line; where TraitWorld does something else today, a deviation row with a new ID. IDs are never renumbered: retired rows stay.

### 3.1 `reference/traits.md` (first)

| Section | Change |
|---|---|
| §1 Syntax summary | `Compiled{X}`, `Dynamic{X}` on arguments and item parameters; `compiled_for`, `with_dynamic`; `@dynamic`; `Callable{A, S}` without a mode |
| §3.1 Operations | an operation's argument declared `Dynamic{Y}` keeps the type's meaning: a trait object passed there is converted to a `Dynamic{Y}` (Q9) |
| new §3.8 "A trait's default: `@dynamic`" | the declaration; `Callable` as the instance; a new subsection rather than a renumbering, so links hold |
| §3.7 Concreteness | the second bullet rewritten (C7); `@concrete_only` traits allowed at `Dynamic` positions (the user's answer to Q4); what concrete mode reports for them (§13) |
| §4 Keys | rewritten around the two attributes: `Compiled{X}` is compiled per key, `Dynamic{X}` once; the erased key's lowering in lowering §5. The refinement "only operations the function reaches count" stays out of W-4 |
| §5.9 `dynamic by` | removed (the user's answer to Q2): a retired section with a pointer to `Dynamic` positions; its status line says so; the deviation row for TraitWorld still accepting the form until phase 3 |
| §6.1 Bounds | annotations on arguments and item parameters; in a bounded function, `Dynamic{X}` in an argument annotation is a bound with a mode (it accepts a plain conforming value too); a `Dynamic` position whose trait has parameters its results use must fix them (decision row 81; Q10) |
| §6.2 What a bounded function receives | a trait object, `Compiled` or `Dynamic`; what each costs |
| **new §6.6 "`Compiled` and `Dynamic`: how values enter"** | the rule (§0) as the reference's text: first seen through a trait, concretely or abstractly typed, the overrides in order, values carry, library to library; the REPL stated precisely: "code that Julia does not compile (a top-level statement without a loop) knows no type: its calls are `Dynamic`; `compiled_for(x)` or a function gives `Compiled`" (Q6); the three spellings of items; the guidance for libraries; the cost paragraph with C8 |
| §6.3 What trait code may do | `compiled_for`, `with_dynamic` inside trait code; the table's `Dynamic` row |
| §6.5 Dispatch | inside trait modules a `Dynamic{X}` argument from plain code reaches the bounded method; outside trait modules `Dynamic{X}` stays a concrete Julia type with Julia's dispatch (TraitMakie's `convert` method, `TraitMakie.jl:73`) |
| §7 Results | `Like` and `withfields` at a `Dynamic` position: the result made at run time (R5) |
| §8 Keywords, defaults, varargs | bounded keywords and varargs take the attribute by the same rule |
| §9 `Callable` | rewritten (C5): `Callable{A, S}`, its `@dynamic` default, `Compiled{Callable{A, S}}`, `compiled_for(f)`, `with_dynamic(f)`, `Dynamic{Callable{A, S}}` as the stored type; functions of the trait world (Q1); every example changes |
| §10 `Dynamic{X}` | "Opened at a bound" removed: a `Dynamic` stays `Dynamic`; `compiled_for` opens it. "The trait's name as a type": in a bound's parameters it means items seen through the trait; in fields and containers it still means its `Dynamic`. "Limit" rewritten |
| §10.2 | retitled ("Collections bounded by their items' trait"), the three spellings, `Vector{Circle}` compiled per item type; T-16's line narrowed: the item case no longer needs `where` variables |
| §10.3 A user's container | `CompiledItems` beside `DynamicItems`; which containers cross in which mode; `Vector{Dynamic{X}}` crosses |
| §10.4 Algorithms | `retain!`'s `f::Callable{Tuple{Dynamic{Cell}}, Bool}` in the new spelling |
| §11 Checks | rule 8's warning; the refusal of a `Dynamic` position with open result parameters (Q10) |
| §13 Concrete mode | the user's definition (Q3): "concrete mode reports if a parameter of a trait that is marked `@concrete_only` is ever an abstract type at compile time of a trait-bound function"; whether an implicit `Dynamic` of such a trait is reported (Q3b) |
| §14 Printing | `Callable{…} at DynamicCall` (`traits.md:971`; `_show_cobj_type`, `core.jl:915`) replaced; how an erased trait object prints (`Dynamic{X} at <type>`) |
| §15 Compiling ahead | workers ahead per key; the erased worker ahead (Q8); entries ahead kept for `compiled_for` until step 3.8 |
| §16 Membership | `conforms` on an erased trait object |
| §18 Status index | rows for every new item |
| §19 Deviations | new T- rows for what TraitWorld does otherwise until phase 3 (one per behaviour: a `Dynamic` opened at a bound; untyped callers compiled per key; `Iterable{Shape}` meaning `Iterable{Dynamic{Shape}}`; `Callable`'s mode parameter; `DynamicFn`; no `@dynamic`; no rule 8 warning; untyped field reads on a `Dynamic`; `dynamic by` accepted; concrete mode's old reports). T-16 narrowed |

### 3.2 `reference/lowering.md`

| Section | Change |
|---|---|
| §1 Summary | the erased key and the entry's decision |
| §3 Trait declarations | `@dynamic`'s lowering (`default_mode`); the operation methods on `Dynamic{X}` values (`trait.jl:301–320`), which plain code keeps calling |
| §4.8 Dynamic operations | removed with `dynamic by` (Q2) |
| §5 Keys and views | the erased key and erased witness (C1); one worker per key, the erased key included; tags attached after the check (C1) |
| §6 Layout | the erased view, a fourth layout |
| §7 Operations on a trait object | dispatch on an erased witness: the split; field reads through the split |
| §8.1 The rewrite | annotations parsed (`Compiled{X}`, `Dynamic{X}`, on arguments, keywords and item parameters); `@nospecialize` on every trait position |
| §8.2 The entry | the decision of C2, step by step |
| §8.4 Keeping | `with_dynamic` keeps |
| §9 Callers | §9.1 unchanged; §9.2 rewritten: untyped callers reach the erased worker; the table serves `compiled_for`; §9.3 entries ahead for `compiled_for`; §9.4 replaced (no per-type entries) |
| §10 Keywords | the decision for bounded keywords |
| §11 Results like the input | R5 |
| §12 `Callable` | C5; `Callable` keeps its own lowering |
| §13 `Dynamic{X}` | no opening at a bound; the seams (C1, one rule with its list); field reads through the split; the candidates an erased worker splits over (C8) |
| §13.1 Crossing | generalized to item positions with a mode (C4) |
| §14 Checks | definition checking and the keep analysis at the erased key |
| §15 Closed builds | the erased worker's fallback and the entry's conformance split (`_ConformsTo`, `core.jl:514`) list every declared implementation as targets; `close_world!` fills the crossing flags (L-27 stays until done); the erased worker compiled ahead (C8) |
| §16 Sessions | unchanged while the table stays; its stamps (`_SESSION`, `untyped.jl:40`) go if step 3.8 retires it |
| §17 Encodings | the annotation types, `CompiledFor`, `WithDynamic`, the item tag `Through{Y}` |
| §18 Deviations | new L- rows as for traits §19 |

### 3.3 `reference/compiler.md` and `reference/facts.md`

- compiler §4.1 `known_type`: TraitWorld's use is the choice between `Compiled` and `Dynamic` at the entry; its Rules bullet that names the table (`compiler.md:547`) rewritten. §4.2 `split_call`: also field reads on erased views; the candidates fixed when the caller is compiled (C8). §3.3: its status reconsidered after E-147 (C8).
- facts: the guarantees for code at a `Dynamic` position (no edge to the set of implementations; the split's branches are facts), where `DynamicCall` and the split are stated today; every sentence naming `DynamicCall`/`CompiledCall`.

### 3.4 Order inside phase 1

traits → lowering → compiler → facts, each one commit with the decision-log rows for what it states; then `mkdocs build` with its validation.

## 4. Phase 2: the other design documents

### 4.1 The documents

| Document | Change |
|---|---|
| `glossary.md` | new: *Compiled*, *Dynamic* (as attribute), *first seen through a trait*, `compiled_for`, `with_dynamic`, `@dynamic`, *erased trait object*, *item position*; changed: `Callable`, `Dynamic{X}`, *function barrier*, *untyped caller*. `DynamicCall`, `CompiledCall`, `DynamicFn` keep their entries until phase 7, each marked "the prototype's spelling until W-4 lands; intended: …" (`intro/` and the glossary's index link them) |
| `design.md` (the rationale) | where it argues `Callable`'s modes and `Dynamic` (6 places): one language, the Rust/Swift precedent (the static type decides); no rules of its own |
| `design/other-languages.md` | `dyn`/`any` against `Dynamic`, generics against `Compiled`; the collections paragraph gets the three spellings |
| `design/alternatives.md` | new entries: `Dynamic` opened at every bound; the default by run-time type (proposal §0 first form); `Callable`'s mode parameter; the disagreement warning; synonyms; the second worker (C1's alternative); `dynamic by` |
| `open-issues.md` | item 33: the references written (closed at phase 7); item 34 (new, §1): the questions of §11; items touched: 16 (opening at the object's concrete type: `compiled_for` plus an assertion), 26 (the crossing's finer rules: `Vector{Circle}` now `Compiled`), 29 (narrowed: entries ahead serve `compiled_for` only), 32 (raised by C8), §2.15 (the solvers' model mode: absorbed), the "design and code disagree" item 3 on `dynamic by` (closed: removed) |
| `design/julia-changes.md` | `known_type`'s use |
| `state.md` | §6 (the order of work): W-4 in progress |
| `record/decisions.md` | rows for C1–C8 and the user's answers, each in the commit of the reference that states it |
| `record/experiments.md` | rows E-147 to E-150 before any run (§7) |
| `record/todo.md` | W-4's status and steps; W-2 in the new spelling; E-145 (W-6) raised if Q8 asks for it |
| `record/INDEX.md` | this plan and its review listed |
| `record/design-history.md` | one entry: the two modes of `Callable` and the opening at every bound, replaced by the rule |
| `intro/traits-by-example.md` §20 | "Planned syntax": `Compiled{X}`, `Dynamic{X}` positions, `compiled_for`, `with_dynamic`, `@dynamic`, checked as planned by `reference.jl` |

`design/performance.md` changes in phase 6 only: the intended cost model is in traits §6.6 and the rationale; numbers come with the measurements (CLAUDE.md rule 5).

### 4.2 Not changed (history)

Reviews, plans, session notes, `record/other-languages-research-2026-10-16.md`, `design-findings.md`, `explorations/*`, `design/implementation.md` and `design/mechanisms.md` (retired pointers), `attic/`. CLAUDE.md rule 2: they are history.

### 4.3 The grep at the end of phase 2

`DynamicCall|CompiledCall|compiled_call|dynamic_call|DynamicFn|dynamic_fn|opened at a bound|Callable\{[^}]*, *(Dynamic|Compiled)Call`, and "a trait's name in a bound's parameters means its `Dynamic`", over every current document of Appendix A. Expected hits: deviation rows, alternatives, history, the glossary's marked entries, and the phase-6 documents (`intro/` but §20, `state.md` outside §6, `design/evidence.md`, `design/performance.md`, `intro/results.md`, `README.md`), counted in the commit message.

## 5. Phase 3: TraitWorld

Branch `dynamic-compiled` from main (5b172e1), worktree `TraitWorld-dyncomp/`. Baseline before the first change: the full suite and the acceptance suite in both settings, logged (`experiments/checks/logs/before-dyncomp/`). Steps, each a commit with its tests:

| Step | What | Files |
|---|---|---|
| 3.0 | **The spike, on main, before any erased code** (R1): one test per entry shape (positional, keyword, vararg, `Callable`, several trait positions) that a typed caller, in plain code and in code compiled by facts, folds `known_type` to `true` and compiles the key's worker; and that the plain interpreter reaches `abstract_split_call` for the entry's conformance split. If a shape fails, the entry for it is changed before step 3.3 | `test/` (a new `test/known_type.jl`) |
| 3.1 | **The erased key and witness** (C1): `View` with an erased key and witness; `_dispatch` on it through `Compiler.split_call`; typed field reads through the split; the erased trait object of a `Dynamic` and of a value of unknown type (`@dynamic_of`'s check); the seams: `opcall`, `CObj`'s call, `_cdecl`, `_like_out` convert an erased trait object to `Dynamic{X}`; printing; equality as `Dynamic`'s | `core.jl`, `trait.jl`, `compiler.jl`, `entry.jl` |
| 3.2 | **The worker accepts the erased trait object:** the worker's signature (`tobj_bound`) admits the erased views' trait set; the parameter tags attached after the entry's check; definition checking (one body); the keep analysis at the erased key; `Like` results at the erased key (R5) | `trait_module.jl`, `defcheck.jl`, `entry.jl` |
| 3.3 | **The entry's decision** (C2): `@nospecialize` on every trait position; `known_type`; a `Dynamic` erased, not opened; the table routed to serve `compiled_for` only. **The tests that call from the top level** reviewed in the same step (R2): each test whose check depends on a compiled specialization, an allocation count, `@inferred` or a timing either calls inside a function or states that it tests the `Dynamic` path | `entry.jl`, `trait_module.jl`, `untyped.jl`, `test/` |
| 3.4 | **Annotations and the trait default** (C6): `_classify` reads `Compiled{X}`, `Dynamic{X}` on arguments and keywords; `@dynamic` in `@trait`; rule 8's warning at the module's end; the refusal of a `Dynamic` position with open result parameters (Q10) | `trait_module.jl`, `trait.jl` |
| 3.5 | **The wrappers** (C3): `compiled_for`, `with_dynamic`, outside and inside trait code; the keep analysis counts `with_dynamic` | `core.jl`, `entry.jl`, `defcheck.jl`, `untyped.jl` |
| 3.6 | **`Callable`** (C5): `Callable{A, S}`, `@dynamic`, `Dynamic{Callable{A, S}}`; `CallAs`, `CallMode`, `DynamicCall`, `CompiledCall`, `DynamicFn`, `dynamic_fn`, `compiled_call`, `dynamic_call` removed; the exports; functions of the trait world by Q1 | `core.jl`, `entry.jl`, `TraitWorld.jl`, `implement.jl` |
| 3.7 | **Items** (C4): item positions with a mode in `_classify`; `CompiledItems` beside `DynamicItems`; the crossing per (position, container type, mode); `Vector{Dynamic{X}}` crossing; the item tag `Through{Y}`; the archetype's item type at definition checking | `BaseTraits.jl`, `entry.jl`, `trait_module.jl`, `defcheck.jl` |
| 3.8 | *(after phase 5)* **The untyped table and the entries ahead:** retired if E-148 and E-150 meet their criterion; otherwise kept and stated as the lowering of `compiled_for` | `untyped.jl`, `ahead.jl`, `trait_module.jl`, `hooks.jl` |
| 3.9 | **Abstract key parts** (C7): the automatic opening removed; **`dynamic by` removed** (Q2): the form refused with a message naming `Dynamic` positions | `entry.jl`, `implement.jl` (`Dyn`, `core.jl:737`) |
| 3.10 | **Concrete mode** (Q3): reports a `@concrete_only` trait's parameter that is abstract at a bounded function's compile time, and nothing else | `concrete.jl` |
| 3.11 | **Closed builds and `verify_main`:** the erased worker's fallback and the entry's conformance split complete over the declared implementations; the machinery list updated; a trimmed build of a small example | `verify.jl`, `certificate.jl` |
| 3.12 | **The tests per rule:** §0 rules 1–9, each with a positive and a negative case; the seams of C1; C8's split order after an image load | `test/` |

Each step runs the TraitWorld suite in the product setting; steps 3.3, 3.7 and 3.12 also under `all` and the acceptance suite (`experiments/facts/acceptance_compiler.jl`, 23 checks), with new G2 cases: a new implementation loaded after code at a `Dynamic` position was compiled discards nothing.

## 6. Phase 4: the demonstrators, examples and experiments

Each repository on a branch `dynamic-compiled`. `run_all.sh` takes only a log tag and runs the current checkouts, so every repository is checked out at `dynamic-compiled` first (a line added to its header).

- **Finding the sites that relied on opening:** a temporary counter in the entry's `Dynamic` branch on main (not committed), run over every demonstrator's suite, lists each call site where a `Dynamic` was opened at a bound. Each site is decided: `compiled_for` (the work per value is large or a loop), or left `Dynamic`.
- **TraitDifferentialEquations** (6 files, 40 lines with the old spelling): `DynamicFn` fields become `Dynamic{Callable{…}}`; `ODEProblem(compiled_call(f), …)` becomes `compiled_for(f)`; `solve_rhs`'s bounds; callbacks (`Dynamic{Callback}`, `Dynamic{IntegratorView}`, the seams of C1 as the test); the README. W-2 (the problem trait) stays after W-4.
- **TraitTables:** `summarize(t.cols[k], …)`, `cellstring`, `take`, `nrows`: `compiled_for` where a column's loop runs.
- **TraitMakie** (47 `Dynamic{` uses): the drawing loops (`for p in ax.plots`, `PlotCore.jl:545`, `:573`) with `compiled_for(p)` (the items are stored `Dynamic`, rule 7); `setcolor!(p, c::Dynamic{ColorSpec})` now a bound in `Dynamic` mode.
- **TraitCSV, TraitReport:** follow TraitTables; TraitCSV's `Dynamic{Column}` results.
- **`experiments/docs-examples/`** (`tutorial.jl`, `reference.jl`; 14 lines with the old spelling): the new spelling; examples for each rule, used by phase 6's `intro/`.
- **Experiments with the old spelling** (`factscompiler` 4 files, `examples` 2, `world`, `hetero-idiomatic`, `facts`): scripts that are rerun get the new spelling; the others keep their logs and a line in their README: "written for the spelling before W-4 (TraitWorld ≤ 5b172e1)".
- **`forks/`** (1 file, 2 lines): the new spelling when the forks resume (W-14); a line in its README now.
- **The full check:** `run_all.sh dyncomp`.

## 7. Phase 5: the measurements

Registry rows first (`record/experiments.md`), each with its question and the result that would change the design. Product setting and `all`; three runs; rows timed whole, the garbage collector's time reported (`rows.jl`'s `@first`); the build (TraitWorld commit, julia-1.13 commit); a quiet machine. **Every row says how it calls:** from a compiled closure (`rows.jl`'s `@first`, `scripts/rows.jl:24–34`: a `Compiled` measurement) or from an interpreted top-level statement (`Dynamic`, rule 2).

| ID | Question | Would change the design if |
|---|---|---|
| E-147 | TDE: a new model type (`ODEModel{Float64}`) at a `Dynamic` position against `Compiled`. Spellings: declared by TDE (`solve_ode(m::Dynamic{…})`), by the caller (`with_dynamic(m)`), from the prompt. The erased worker compiled into TDE's image against compiled at the session's first call (C8), the user's type inside and beyond the split. First solve in a fresh session; run time per step. Baselines: today's new-type row (335–371 ms, E-146) and today's `FunctionModel` with a `DynamicFn` (25–26 ms). Separate rows: the right-hand side through `Dynamic{Callable}` against today's `DynamicFn` (C5), and the model's operations through the split | the per-step cost through the fallback is large enough that a solver cannot choose `Dynamic` (then E-145 comes before W-4 closes) |
| E-148 | Untyped callers: the erased worker against the table (TraitWorld 5b172e1). A worker with one operation and a worker that loops over n operations (per call and per operation); one and several trait positions; from code typed `Any` and from the prompt; `compiled_for(x)` from an untyped caller through the table and through the entry's two dispatches; the erased worker's compile latency and code size on realistic workers (TraitMakie's `draw!`, TraitTables' `summarize`) | **criterion for step 3.8:** the table retires only if `compiled_for` through the entry's two dispatches is within noise of the table's path for a worker that loops; otherwise it stays as the lowering of `compiled_for` |
| E-149 | The demonstrators before and after (TDE, TraitMakie, TraitTables, TraitReport rows; `experiments/hetero-idiomatic` r-rows): every row in the product setting, three load orders, from compiled closures; one row per demonstrator from the prompt, labelled | a row gets slower by more than its noise, and no `compiled_for` site recovers it |
| E-150 | Items: `Iterable{Mark}` over `Vector{Circle}` (compiled per item type) against `Vector{Any}` (`Dynamic`); `Iterable{Compiled{Mark}}` and `draw(compiled_for(m))` in the loop, with work per item through a call and through direct operations; `with_dynamic(x)` on an isbits value from a typed caller (a box per call) | the guidance's claim ("`Compiled` items pay off when the work per item is a call") fails; then the reference's guidance changes |

Evidence rows (`design/evidence.md`) with each finished row, in the same commit. Then step 3.8.

## 8. Phase 6: documents that state the current state

After phases 3–5:
- `intro/traits-for-julia.md` ("What you write", the worked example, "What it costs"), `intro/traits-by-example.md` (§4 bounded functions: the attribute; §12 `Dynamic` rewritten; §14 `Callable` rewritten; §9 keywords; §17 concrete mode; §20 planned syntax trimmed to what is still planned), `intro/porting.md` (the `Callable` and `Dynamic` lessons), `intro/results.md` (numbers by link to the evidence): every example run in `experiments/docs-examples/`.
- `README.md` (the home page), `state.md` (what is built), `design/evidence.md` and `design/performance.md` (numbers and the cost model), the demonstrators' READMEs (dated tables of their own; current numbers by link), TraitWorld's README.

## 9. Phase 7: close

- Merge `dynamic-compiled` into each repository's main, after `run_all.sh` passes on the merged mains.
- The references' statuses flipped to Implemented; the T- and L- rows of phase 1 retired with their commits; L-11, L-12, L-13, L-24 retired or kept by step 3.8's outcome; T-16 narrowed. One commit per reference with `state.md` (CLAUDE.md rule 1).
- The glossary's marked entries (`DynamicCall`, `CompiledCall`, `DynamicFn`) become pointers to their replacements.
- Open issues 33 and 34 closed; W-4 done; the decision log's rows marked built.
- The grep of §4.3 over every repository, now without expected hits outside history, deviation rows and alternatives; the session note; the resume memory.

## 10. Risks and checkpoints

- **R1. `known_type` in typed callers.** The keyword sorter gets the `inline`, facts and positional `nospecialize` metas (`ast.scm:529–536`, `julia-syntax.scm:582–593`, verified by the review), so a typed keyword caller folds where the inliner honours `@inline`; the risk is where it declines (cost or recursion limits, `kws...` splats). Step 3.0 checks every shape before any erased code exists.
- **R2. Tests that call from the top level** run `Dynamic`: reviewed in step 3.3, where the suite would otherwise break (14 files, 443 tests at 5b172e1).
- **R3. Performance where `Dynamic` replaces the opening:** TraitTables' and TraitMakie's loops; TDE's callbacks. The counter of phase 4 finds the sites; E-149 is the check.
- **R4. The erased worker's cost per operation**, not per call: a split, or the fallback, at every operation. E-148's looping worker and C8.
- **R5. `Like` and `withfields` at a `Dynamic` position:** the result's type is the user's, unknown to the erased worker; made at run time (`_like_out` after an inference barrier). Step 3.2.
- **R6. Closed builds:** the erased worker and the entry's conformance split in a `--trim` build. Step 3.11.
- **R7. Guarantees:** the facts mode's G2 at `Dynamic` positions (the acceptance suite's new cases).
- **R8. The meaning of `x::Dynamic{X}` in existing bounded functions changes** (a typed argument becomes a bound in `Dynamic` mode). The demonstrators' uses are found in phase 4.
- **R9. The split's coverage** (C8): an erased worker in an image never splits over a user's types. E-147; Q8.
- **R10. The prompt** (Q6): every example in `intro/` run at the prompt gets the `Dynamic` path. Results are the same; any timing shown there is labelled.

## 11. Questions for the user

**Answered** (2026-10-20): "Q2: Yes please. Q3: Concrete mode reports if a parameter of a trait that is marked @concrete_only is ever an abstract type at compile time of a trait bound function. Q4: Yes I think. Any reasons not to allow this? C1-C7 look good."
- Q2: `dynamic by` (traits §5.9) is removed; `Dynamic` positions replace it, and the solvers' model mode (open issue §2.15) with it.
- Q3: concrete mode reports a parameter of a `@concrete_only` trait that is abstract when a bounded function is compiled.
- Q4: `@concrete_only` traits are allowed at `Dynamic` positions. The reason for care, not refusal: an implicit `Dynamic` of such a trait (from an abstract type at the caller) pays a dispatch per operation that nobody chose (Q3b).
- C1–C7 confirmed.

**Open:**
- **Q1. Functions of the trait world under `Callable`'s `@dynamic`** (Base's `abs2`, a trait module's functions and closures). Today they are passed as themselves, the library compiled per such function, even when the caller asks for `dynamic_call` (`entry.jl:749`). Options: (a) they are already trait-world values, concretely typed, so `Compiled` by rules 7 and 9, while `with_dynamic(f)` still wins (recommended: `@dynamic` exists for the unbounded set of user closures; the trait world's own functions are a bounded set, and erasing them runs trait code as plain code through a `cfunction`); (b) no special case: the library writes `compiled_for`; (c) only the library's own closures are `Compiled`, Base's functions from plain code are erased.
- **Q3b.** Should concrete mode also report an implicit `Dynamic` of a `@concrete_only` trait (a value whose type was abstract at the caller)?
- **Q6. The prompt, now rather than later** (review finding 3). `known_type` is `false` in every interpreted top-level call, so `f(Circle(1.0))` typed at the prompt is `Dynamic` too, not only a call on an ordinary global; a top-level statement with a loop is compiled, and there a `const` global is `Compiled`. Options: (a) accept for W-4 and state it precisely (recommended; the user's "revisit later as a special case"); (b) special-case interpreted callers, which needs a second compiler primitive (`known_type` cannot tell the interpreter from compiled code at `Any`; entries per declared type would also catch compiled callers at `Any`).
- **Q8. Erased workers compiled ahead?** (C8) (a) compile them into the library's image: a new type compiles nothing, and every user type takes the fallback until open issue 32 is solved (E-145 raised into W-4's order); (b) compile them at the session's first call, after the user's declarations: user types inside the split, at one compile per session. Recommendation: (a) with E-145 raised, decided after E-147 measures both.
- **Q9. An operation's argument declared `Dynamic{Y}`** (TDE's `condition(…, integ::Dynamic{IntegratorView})`) keeps the type's meaning: a trait object passed there is converted to a `Dynamic{Y}` (C1's seams). Recommended: yes; the alternative is to read it as a bound in `Dynamic` mode, which an operation's declaration does not have.
- **Q10. A `Dynamic` position whose trait has a parameter its results use, left open** (`s::Dynamic{StateVector}`; decision row 81: a `Dynamic` position fixes every such parameter). Options: (a) refused at the definition, naming the fix (fix the parameter, or a `where` variable when T-16 lands) (recommended for annotations); (b) for an implicit `Dynamic` at a bare bound with the parameter open, the erased key carries the parameter's value, so the erased worker is compiled once per value (recommended: the parameter is known from the value, and results stay typed).

These go to `../open-issues.md` §1 as item 34.

## 12. The review's findings and what was done

[`../reviews/2026-10-20-dynamic-compiled-plan.md`](../reviews/2026-10-20-dynamic-compiled-plan.md) (Fable 5.1, plan revision 1, f2bec03).

| Finding | Done |
|---|---|
| 1 (high): C2 retires the table before E-148 | C2 keeps the table and the entries ahead as the lowering of `compiled_for`; step 3.8 after phase 5 with E-148's criterion; E-148 measures looping workers; issue 29 narrowed |
| 2 (high): an erased worker in an image never splits over user types | C8; E-147's placements; Q8; issue 32 raised |
| 3 (high): every interpreted top-level call is `Dynamic` | §0 and traits §6.6 state it precisely; Q6 now; every measurement row says how it calls; E-149 rows from the prompt |
| 4 (medium-high): the seams between the two representations | C1's seams rule and tags; step 3.1, 3.2; lowering §13 |
| 5 (medium): `Dynamic{Callable}` adds an indirection; signature fixing | C5 states it; E-147's separate row; `Callable{A, S, M}(f)` removed without counterpart |
| 6 (medium): the item encoding | C4's item type and `Through{Y}`; `Vector{Dynamic{X}}` crosses; `defcheck.jl` in step 3.7; lowering §17 |
| 7 (medium): the phase-2 grep against phase 6 | the glossary keeps marked entries until phase 7; the grep lists expected hits; `performance.md` to phase 6 |
| 8 (medium): missing sections | traits §3.1, §5.9, §14, §16; lowering §3, §4.8, §6, §11, §14, §16; compiler §4.1's Rules |
| 9 (medium): ordering, R1's spike | step 3.0; test review in step 3.3; step 3.8 after phase 5; `run_all.sh` needs checkouts |
| 10 (medium): hidden decisions | Q6, Q9, Q10; the table's retirement now measured, not assumed |
| 11 (low-medium): measurements | E-147 spellings, placements, baselines, separate rows; E-148 looping workers, compile latency and code size; E-150 `compiled_for` in the loop, `with_dynamic` on isbits |
| 12 (low): stale line numbers | Appendix B at 5b172e1 |
| 13 (low): closed builds | the per-type entry ahead goes (C2); `_ConformsTo` in step 3.11; the plain interpreter's split in step 3.0 |
| 14 (low): faithfulness table | no change needed: rule 6's lowering (`Vector{Circle}` crossing into `CompiledItems` rather than meeting the bound as it is) gives the same result |
| 15 (low): smaller points | decision-log rows per reference commit (§1, §3.4); intro §20 in phase 2; C6 on definitions at the prompt; traits §6.5 row for `Dynamic{X}` outside trait modules |

## Appendix A. Every document on the website

From `mkdocs.yml`'s navigation, with the phase that changes it (— for history, left as it is).

| Section | Document | Phase |
|---|---|---|
| Home | `README.md` | 6 |
| For programmers | `intro/traits-for-julia.md`, `intro/porting.md`, `intro/results.md` | 6 |
| | `intro/traits-by-example.md` | 2 (§20), 6 |
| | `glossary.md` | 2, 7 (the marked entries) |
| For core developers | `state.md` | 2 (order of work), 6 (what is built) |
| | `design.md` | 2 |
| | `design/evidence.md` | 5–6 (numbers) |
| | `design/performance.md` | 6 |
| | `design/julia-changes.md`, `design/other-languages.md`, `design/alternatives.md`, `open-issues.md` | 2 |
| The references | `reference/README.md` (conventions: unchanged unless the annotation types need a convention), `traits.md`, `facts.md`, `compiler.md`, `lowering.md` | 1, 7 |
| The record | `record/INDEX.md`, `record/decisions.md`, `record/experiments.md`, `record/todo.md` | 1, 2, 5, 7 |
| | `record/design-history.md` | 2 (one entry) |
| | `record/other-languages-research-2026-10-16.md`, `writeup/README.md`, `explorations/wrapping-by-facts.md`, `explorations/strict-mode.md`, `design-findings.md`, `design/implementation.md`, `design/mechanisms.md`, `session-notes/00-environment-and-workflow.md` | — |

Lines matching `Dynamic|DynamicCall|CompiledCall|compiled_call|dynamic_call|DynamicFn|dynamic_fn|Callable|function barrier|opened|known_type|untyped caller` per current document (2026-10-20): traits 112, lowering 71, open-issues 47, other-languages 39, traits-by-example 26, porting 23, glossary 22, traits-for-julia 21, alternatives 18, state 15, facts 11, compiler 9, evidence 8, results 7, design 6, performance 6, julia-changes 5, README 3, INDEX 7.

## Appendix B. Code inventory

TraitWorld main 5b172e1 (8,994 lines in `src/`):
- `core.jl` (933): `Trait` (:13), `CallMode`/`DynamicCall`/`CompiledCall` (:30–:32), `Callable{A, S, M}` (:33), views and keys (:50–:101), `TObj` (:214), `Dynamic` (:351), `_narrow` (:408), `opened` (:438), `_DynOp` (:448), `_dyn_identity` (:475), `DynamicOf` (:489), `@dynamic_of` (:500), `_ConformsTo` (:514), `_note_conformances!` (:532), field access on `Dynamic` (:687), `Dyn` (:737), `opcall`'s check (:797), `_dispatch` (:812), `Erased` (:841), `_cdecl` (:860), `CObj` (:897), its call's check (:902), `_show_cobj_type` (:915), `CMulti` (:924).
- `entry.jl` (905): `_conformance_slow` (:144), `enter` (:193), `Crossing` (:223), `_assemble` (:374), `_rule3_error` (:416), `fallback` (:633), `_from_trait_world` (:680), `enter_callable` (:720), `_wrap_callable`'s mode test (:749), `enter_callables` (:754), `DynamicFn` (:768), `dynamic_fn` (:776), `_like_out` (:827).
- `trait_module.jl` (955): `_dynamic_fields` (:143), `_dynamic_containers` (:179), `_rewrite_fdef` (:425), `tobj_bound` (:482), the parameter tags (:495–:499), the entry's generation (:560–:715; the tabled path from :652), `_fix_crossing!` (:773), `_fix_needed!` (:803), `_finish_module` (:822).
- `untyped.jl` (257): the table, the session stamp (:40), the pattern methods, `_pentry` (:252), `_UWrap`.
- `ahead.jl` (195): the per-type entry for untyped shapes (:146–:153), `_ahead_entry!` (:168).
- `BaseTraits.jl` (218): the traits (`Iterable`'s `T = eltype(Self)`, :45), `DynamicItems`, `DynamicValues`, `crossed` (:174), `retain!`.
- `trait.jl` (341): operations on `Dynamic` (:301–:320).
- `defcheck.jl` (305): the archetypes' checks (:64–:77), `_analyze_keeps` (:277).
- `concrete.jl` (584), `verify.jl` (1,108), `certificate.jl` (97), `hooks.jl` (267), `implement.jl` (1,472; `Erased`, `Dyn` uses), `TraitWorld.jl` (196; exports).
- Tests: 14 files, 2,360 lines, 443 tests.

Old spelling in code (`compiled_call|dynamic_call|DynamicCall|CompiledCall|DynamicFn|dynamic_fn`): TraitWorld `src` 26 lines in 4 files, `test` 11 lines in 2; TraitDifferentialEquations 40 lines in 6; `experiments/docs-examples` 14 lines in 2; other experiments 9 files; `forks` 2 lines.
