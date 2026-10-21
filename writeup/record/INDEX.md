# The record: an index for agents

This is the map of everything on record: findings, experiments, decisions, reviews and session logs. It is written for agents (future Claude sessions) who need to find a fact, a number or the history of a decision. Nothing here is the design itself.

Written 2026-10-19 (session 29, the writeup cleanup: [`../plans/2026-10-19-notes-cleanup-plan.md`](../plans/2026-10-19-notes-cleanup-plan.md)).

## The three-audience layout

- **Programmers** (Julia users, no compiler terms): [`../intro/`](../intro/)
  - `traits-for-julia.md`: what you write, what you get, one worked example;
  - `results.md`: what the demonstrators show, in plain words;
  - `porting.md`: how to port a package (was `writeup/porting-to-traits.md`).
- **Core developers** (the precise rules and the major implementation choices):
  - [`../reference/`](../reference/README.md): **the source of truth** for the intended shape (since 2026-10-19): `traits.md`, `facts.md`, `compiler.md`, `lowering.md`, each with a Deviations table (IDs T-, F-, C-, L-). [`../design.md`](../design.md) is the rationale; [`../design/implementation.md`](../design/implementation.md) and `mechanisms.md` were retired into the references (older documents cite their section numbers);
  - [`../design/`](../design/), the chapters of the details:
    - `julia-changes.md`: every change to Julia as built (parts A–D, optimizer changes, pieces kept and reverted);
    - `evidence.md`: the current measurements, one table per demonstrator and experiment;
    - `performance.md`: the performance phase of session 29, its themes and learnings;
    - `mechanisms.md`: the detail `design.md` compresses (keywords, varargs, functions that cross, several traits, parametric types, types that only convert);
    - `other-languages.md`: the choices against C++, Rust, Swift and Mojo, and their costs;
    - `alternatives.md`: designs tried, rejected or replaced, by topic, with the reasons.
- **Agents:** this index, and the files it lists.
- **Rules for agents on the documents** (what goes where, what changes together): [`../../CLAUDE.md`](../../CLAUDE.md).
- **The work queue:** [`todo.md`](todo.md), agreed work items (`W-n`) with their source, status and links.
- **Experiments:** [`experiments.md`](experiments.md), the registry of experiments (proposed, running, done, superseded), each with an ID `E-n`, the question, where its scripts and logs are, and its outcome. A new experiment gets a row before it is run.

**Rules for reading the record:**
- `design.md` wins wherever a record document disagrees with it.
- A record document is either history (a design or mechanism since replaced) or detail (true, but too fine for `design.md`). The tables below say which.
- The record files stay at their paths: session notes, reviews and other repositories cite them more than a hundred times. Only the four old notes moved (to the attic), and `porting-to-traits.md` (to `intro/porting.md`), each with a stub at its old path.

## How to resume work

Read, in this order:
1. [`../../CLAUDE.md`](../../CLAUDE.md): the rules for the documents.
2. **The pick-up note** [`../plans/2026-10-21-pickup-sciml-validation.md`](../plans/2026-10-21-pickup-sciml-validation.md): where the work stands and what to do next (W-34, validating the SciML strategy).
3. [`todo.md`](todo.md): the work queue. The next item is marked **next** (since 2026-10-21: W-34). The latest session note, [`../../session-notes/2026-10-21-32-values-carry-through-storage.md`](../../session-notes/2026-10-21-32-values-carry-through-storage.md): "To resume", then what was done.
4. [`../state.md`](../state.md), then the references in [`../reference/`](../reference/README.md), each with its Deviations table; [`decisions.md`](decisions.md) for the origin of a decision.
5. [`../open-issues.md`](../open-issues.md) §1: the decisions waiting for the user.

**"Session 30" is session 29.** The demonstrators' READMEs and commit messages (and `intro/porting.md` until the writeup review of 2026-10-19) call session 29's autonomous run "session 30"; there is no note 30.

On 2026-10-19 the terms changed: the noun 'conformance' became 'implementation', 'implementing type' became 'receiver type'; documents before that date use the old terms (the terms and their origins: [`../glossary.md`](../glossary.md)).

**Standing constraints** (root [`README.md`](../../README.md) "Conventions", [`00-environment-and-workflow.md`](../../session-notes/00-environment-and-workflow.md) "Basic workflow"):
- The machine is shared with other simulations (30 GB, 16 cores). **One Julia job at a time,** never parallel chains. A parallel chain crashed the machine on 2026-10-15 (session note 20).
- Run Julia niced and serialized through the shared lock: `flock /tmp/claude-1000/julia-review.lock nice -n 19 …`, with `JULIA_NUM_PRECOMPILE_TASKS=4`. (The lock is used by the reviews of 2026-10-18; the workflow note itself says `nice -n 10` and does not name the lock.)
- **Full builds of Julia alone,** through `julia-1.13/tw-build.sh`: `make -j4`, niced, killed below 4 GB available memory. `TW_TARGET=julia-sysimg-release` rebuilds only the system image. Check `BUILD EXIT` at the end of `tw-build.log` after every build: two builds failed in session 29.
- **Principled fixes over workarounds:** fixes that a future trait-world ecosystem would have (a trait-world CSV reader, a Julia patch), not local tricks. Slowdowns are acceptable if traits can recover them (session 29, decision 6).
- Do not edit TraitWorld while another job loads it from source against an older Julia (session 29).
- Scratch files go in the session scratchpad. `/tmp` is a tmpfs: it does not survive a reboot.

## Where to look for…

- **A decision's history:** [`decisions.md`](decisions.md), the decision log (moved into the record on 2026-10-19).
  - Rows in force are grouped by topic; the rows marked **history**, superseded, withdrawn or retired, are in its last section, with the status column saying by what.
  - The reasons, by topic: [`../design/alternatives.md`](../design/alternatives.md); the order of events: [`design-history.md`](design-history.md).
  - The user's own words are quoted in the status column, and in full in the session note of that session.
- **A measurement's numbers:**
  - current numbers: [`../design/evidence.md`](../design/evidence.md) and [`../design/performance.md`](../design/performance.md);
  - every number as measured, with build and commit: the session notes (session 29's "Autonomous run" log for the compiler era; sessions 23–27 for the package-policy era);
  - per demonstrator: each repository's README (history tables from sessions 23–27);
  - older evidence: [`../design-findings.md`](../design-findings.md) and `experiments/*/README.md`.
- **A measurement's raw log:** the session notes quote the logs. The logs themselves are under `/tmp/claude-1000/` and are **not durable**:
  - `/tmp/claude-1000/demos/m/*.log`: session 29's final runs (`final-rows`, `final-rf`, `control`, `control-all`, `remeasure`, `forks-session`, …);
  - `/tmp/claude-1000/demos/*.sh`: the harness that produced them (`measure_all.sh`, `remeasure.sh`, `final_checks.sh`). **It is in no repository.**
  - `/tmp/claude-1000/review-*/`: the reviewers' scratch scripts and outputs.
- **An experiment's scripts:** [`../../experiments/`](../../experiments/) (its own repository; table below), and each demonstrator's `scripts/`.
- **A review's findings and what was done about them:** the review table below; then the session note named there, and [`../open-issues.md`](../open-issues.md) §1 and §4b.
- **The proofs:** [`../explorations/wrapping-by-facts.md`](../explorations/wrapping-by-facts.md):
  - "What is guaranteed, and why": rule R (concrete facts), rule P (nothing skipped), Theorems 1–3 (G1 identical or error, G2 stable cache, G3 closed for AOT), Lemma D (dominance), Lemma O (ownership, corrected in session 27);
  - "Validation" (session 24): assumptions A3–A5 and the implementation rules 1–7;
  - strict mode's rule and its use of Lemma O: [`../explorations/strict-mode.md`](../explorations/strict-mode.md) §1.
- **The acceptance suite:** `experiments/facts/acceptance_compiler.jl` (23 checks, G1.x and G2.x cases; 23 of 23 on the compiler in both settings, 2026-10-20); the package-era suite is `experiments/facts/acceptance.jl` (16/16 in session 24).
- **The Julia patch:**
  - `julia-1.13/` is a worktree of `julia/`, branch `trait-world-1.13` (v1.13.2 plus the patch). Its `TRAITWORLD.md` lists the pieces that remain, and the build notes.
  - `git -C julia-1.13 log --oneline v1.13.2..HEAD` lists every commit; sessions 28–29 are in the table at the end of this file.
  - `julia/` itself is on branch `trait-universe`: the 1.12 invalidation filter (history).
  - The 1.12 filter's patches, v1 to v7: `attic/binary/`.
- **The demonstrators:** each repository's README (table at the end). TraitWorld has no README: its design is `design.md`, its tests are `TraitWorld/test/`.

## Reviews (`writeup/reviews/`)

All by Fable 5.1 unless noted. "Acted on" says what the session notes record.

| Path | Date | Status | What it reviewed; verdict | Acted on |
|---|---|---|---|---|
| [`2026-10-16-wrapping-under-keys.md`](../reviews/2026-10-16-wrapping-under-keys.md) | 2026-10-16 | history (filter, sealing, wrappers are gone) | code written without traits, under keys. Layering not refuted, but the notes still assume representations; F1 (critical, verified): the patched filter kept a worker stale when its key's type owner redefined a method; F1–F11 | F1 fixed (julia 280612ed2f, session 23). After wrapping by facts: F2, F4–F8, F10 dissolved; F3, F9, F11 open (open-issues §4b) |
| [`2026-10-17-demonstrators-under-facts.md`](../reviews/2026-10-17-demonstrators-under-facts.md) | 2026-10-17 | history (rows re-measured in session 29) | every demonstrator row against wrapping by facts: valid, restate, remeasure or done; adds TraitReport; sets the order of work | the order of sessions 26–27 (Julia pieces and TraitWorld fixes over workarounds) |
| [`2026-10-17-consistency-fresh-eye.md`](../reviews/2026-10-17-consistency-fresh-eye.md) | 2026-10-17 | history (all four decided) | the design's consistency after the churn. The core is coherent; four significant inconsistencies: concreteness, Lemma O and stakeholders, facts at non-public functions, overrides after a conformance; 13 findings | open-issues §1.5–1.8, decided by the user in session 27 (decisions.md "Session 27"); minor findings in open-issues §5.5 |
| [`2026-10-17-decisions-1-and-4.md`](../reviews/2026-10-17-decisions-1-and-4.md) | 2026-10-17 | history | what decision 1 (concreteness opt-in, the check narrowed to the key) and decision 4 (a late override refused) break; six probes on the prototype | both adopted (design repo c86bf25; TraitWorld 87c1fc1) |
| [`2026-10-17-demonstrators-fresh-eye.md`](../reviews/2026-10-17-demonstrators-fresh-eye.md) | 2026-10-17 | history | claims, baselines and methods of three demonstrators. Survival of loads robustly shown; REPL, AOT, stock Julia not shown; traits not separated from an inference barrier (B2) | led to the DataFrames plan (demonstrator 4); B2 became the decisive control, run in session 29: load protection is the facts rule's, for any code |
| [`2026-10-18-design-and-fixes.md`](../reviews/2026-10-18-design-and-fixes.md) | 2026-10-18 | history | the design and the fixes of sessions 27–28. Session 27's fixes hold (acceptance 16/16); the pivot is not in the notes; 7 ranked findings (the global facts mode changes values; witness tables break world age; strict mode under one owner undefined; …) | the user's session-29 decisions; witness tables off, then removed with (D); (A) built in-tree (880ae49dad); Julia's tests in facts mode run in part; register gained session 28 |
| [`2026-10-18-framing-and-motivation.md`](../reviews/2026-10-18-framing-and-motivation.md) | 2026-10-18 | current as reasoning; wording superseded by design.md §2 | the framing and the user's two-goal reframing. "Piracy is the principal cause of invalidation" is false for stock Julia (S1–S8); rule R is the hidden premise; §5: strict mode first | adopted as the framing; design.md §2–3 rewritten on the user's four steps; `inval.jl` now in `experiments/facts/invalidation/` |
| [`2026-10-18-implementation-shape.md`](../reviews/2026-10-18-implementation-shape.md) | 2026-10-18 | history (its migration is done) | TraitWorld and the patch after the pivot. The foreign cache owner is the largest path dependency; the protection is trait-independent (the control is missing); `Dynamic` belongs in the compiler; the forks validate a barrier | its migration order became the order of work: (A), (B)+(C), (D), TraitWorld's policy deleted (8,718 → 7,321 lines), the control; forks re-ported on `cell`/`nrows` and `CSVColumn{T}` |
| [`2026-10-18-examples-and-demonstrators.md`](../reviews/2026-10-18-examples-and-demonstrators.md) | 2026-10-18 | current for its gaps list; partly done | every example and demonstrator under the user's criterion (work after an import should be instant). No strict refusal in a demonstrator, no certificate, no teaching warning; the framing's evidence only in `/tmp`; ranked new examples | `experiments/examples/` and `experiments/facts/framing/` written; the fully-typed certificate built (TraitWorld 1098fab) |
| [`2026-10-18-decisions-revisited.md`](../reviews/2026-10-18-decisions-revisited.md) | 2026-10-18 | history (applied in design.md) | every register row for conceptual simplicity: of 87 rows, 51 keep, 5 simplify, 2 change, 16 retire, 9 merge; ten ranked changes; a simplified core | changes 1 and 3–10 adopted, 2 rejected (`Callable` keeps both modes); `design.md` written; retired rows marked history |
| [`2026-10-19-compiler-implementation.md`](../reviews/2026-10-19-compiler-implementation.md) | 2026-10-19 | history (findings fixed or stated) | the compiler as built (julia db82407fa6..f6838f96fc). Architecture sound, images work; (D) compiled wrong code for a known receiver type (critical); the assertion exemption broke G1; `--trim` left facts flags; (C) covers codegen's call sites only; the split boxes | (1) fixed, G1.18; (2) replaced by "no asserted effect applies to a frame with a run-time site", G1.19; (3) fixed; (4) stated in design.md §5 rule 1 and §6 (C), and in `design/julia-changes.md` (writeup review of 2026-10-19, finding 5); (5) the typed split (bc26aa9255); (6) stated as a trade. julia 67f5c0bcc8, acceptance 19/19 |
| [`2026-10-19-performance-phase.md`](../reviews/2026-10-19-performance-phase.md) | 2026-10-19 | current (its next steps are the next work) | the performance phase. Theme 2 wrong (the inliner habits cost stock Julia 56×); the control's arithmetic wrong (~990 ms after loads under `all`, undiagnosed); a clean-case regression omitted; B1: machinery calling the compiler holds plain edges; the three-way extension is a workaround | the notes rewritten (now `design/performance.md`); the user: inliner fixes for all code (61852d8fb1), diagnose then fix, a lean held view (TraitWorld 375a930); B1 documented in design.md §6 |
| [`2026-10-20-dynamic-compiled-plan.md`](../reviews/2026-10-20-dynamic-compiled-plan.md) | 2026-10-20 | history (applied in the plan's revision 2) | the implementation plan for `Dynamic` and `Compiled` (W-4), revision 1. Faithful to the rule; three high findings: the untyped table retired before it is measured, an erased worker in an image never splitting over user types, every interpreted call `Dynamic` | the plan's revision 2, its §12 (finding by finding); open issues item 34 |
| [`2026-10-21-what-follows-the-split.md`](../reviews/2026-10-21-what-follows-the-split.md) | 2026-10-21 | current | the proposal for what follows the `Dynamic` split (E-145) and its measurements. Direction sound; the "default case" conflicts with the facts rule; the table should be emitted by the compiler; pointer creation ahead, C-3, the s22 objections, overstated numbers | the plan's revision 2 (the compiler emits the table; julia-1.13 711484a23e); the rest in the review's last section |
| [`2026-10-21-tonights-code-and-w2.md`](../reviews/2026-10-21-tonights-code-and-w2.md) | 2026-10-21 | current | the split table's code and W-2. High: the typed call copied mutable arguments and failed on results with references; W-2's `fn::Any` workaround-shaped; `stored`'s scope to state | the C ABI rule and G1.26 (julia-1.13 `split-table-abi`); `ODEProblem{T, P, R, D}` with a fixed chunk; traits §5.8; the rest in the review's last section |
| [`2026-10-21-values-carry-through-storage.md`](../reviews/2026-10-21-values-carry-through-storage.md) | 2026-10-21 | current | the plan for W-18 (values carry their attribute through storage). Principle right; a slot that converts contradicts "the caller's cast wins"; `Callable` needs its own forms; struct parameters bounded by a trait under-specified; the union boxes; writes, equality and seven places assuming `Dynamic` | the plan's revision 2 (casts only by `compiled_for`/`with_dynamic`, types never cast, `Kept{X}` one concrete type); TraitWorld 1d09112 and after; `design/alternatives.md`; open issues 39, 40 |
| [`2026-10-21-traits-reference-structure.md`](../reviews/2026-10-21-traits-reference-structure.md) | 2026-10-21 | current | `reference/traits.md`'s level and structure after W-18: mechanism in the reference (receiver types, keys, erased keys, workers), the attribute rule stated in thirteen places, `Dynamic{X}`'s five readings by position, `Self` as the receiver type; a proposed outline with a chapter "Values in trait code" | the user decided the reading of `Dynamic{X}` in storage (the plain type); the outline adopted in W-20; T-25 retired |
| [`2026-10-21-traits-reference-restructured.md`](../reviews/2026-10-21-traits-reference-restructured.md) | 2026-10-21 | current | the restructured `reference/traits.md` (W-20): the defaults' table by position incomplete, `Kept{X}(x)` and the trait-world exemption, `Iterable{Kept{X}}`, a wrong warning, stale anchors, terms (R1–R20) | applied in `reference/traits.md` and TraitWorld 53625c0, but for R12 (one home for items) and some long sentences; open issues 39, 41 |
| [`2026-10-21-ndport-workload-plan.md`](../reviews/2026-10-21-ndport-workload-plan.md) | 2026-10-21 | current | the P1 plan of W-32 (the NetworkDynamics workload and its baselines). Blockers: the solves alias one parameter vector (later solves start with tripped lines); the compile counters are never switched on. Should fix: the trace cannot attribute the core loop; exact equality across compilers; the registry row before the `all` precompile; Julia's ten-cache cap per package. Stock baseline kept in its own depot; the `all` depot on disk | not yet acted on |
| [`2026-10-21-porting-guideline.md`](../reviews/2026-10-21-porting-guideline.md) | 2026-10-21 | current | `intro/porting.md` as rewritten for W-32 (P0). Wrong: bounded beside untyped methods (L-3), an unsourced 100 ns, a dangling open-issue link, `AbstractVector` attributed to §14. Missing for the port: an unchanged package as a trait module (split packages' pirates, extensions, compiler options), informal interfaces as traits over existing functions, stored functions and RGFs (T-51), keyword APIs, Observables. Rules stated three times; numbers copied from reviews | not yet acted on |
| [`2026-10-21-ndport-facts-first-plan.md`](../reviews/2026-10-21-ndport-facts-first-plan.md) | 2026-10-21 | current | (Opus 5.5) the P3 plan of W-32 (the facts mode first, E-153). The three-line wrap of NetworkDynamics is realistic; DiffEqBase's and OrdinaryDiffEqCore's pirates confirmed, none found in NetworkDynamics. Blockers: setting N shares the working tree and environment of P0, A0 and W; the strict-mode check has no control (strict mode also protects Base's plain code). Should fix: E-151 already answers the cost of `all`; about 11 sessions instead of 18; compare like with like and classify losses by facts §2.2; N's and W's first passes without images; the wrap's ownership gap needs a T- row; harness for strict mode and W's plot part; last-bit differences are not exempt from G1 | not yet acted on |
| [`2026-10-21-ndport-traits-plan.md`](../reviews/2026-10-21-ndport-traits-plan.md) | 2026-10-21 | current | (Opus 5.5) the traits plan of W-32 (P2, and P4's first step: `ComponentDynamics`, the batch barrier, E-152). The claim holds for the workload: every SciML path derives from the `Network`'s type, which erasing the batches fixes (scope: functions and dimensions, not mass matrices, loopback edges or external inputs); the trait is correct in today's spelling. Blocker: one working tree and environment shared with P0 and P3's N. Should fix: the barrier allocates about four times per crossing (three removable in ND with upstream's `Ref`); `sametype` and SciML's CodeInstance counts as criteria, step b in the gate; one trait submodule suffices (PB-3 not forced); the checks miss feed-forward kinds, external inputs and `@set` | not yet acted on |
| [`2026-10-21-ndport-inside-out-plan.md`](../reviews/2026-10-21-ndport-inside-out-plan.md) | 2026-10-21 | current | (Opus 5.5) the inside-out plan of W-32 (P6, the SciML core wrapped bottom-up under strict mode, E-155). Sound approach; the census arithmetic and rebuild counts reproduce. Blocker: check T looks at step d only and `p3_hot.jl` profiles only ND's right-hand side, so a regression of P3-1's kind in the wrapped code of steps c and e would pass. Should fix: SciMLJacobianOperators is below NonlinearSolveBase; the precompile estimates are low; joint owners missing (BracketingNonlinearSolve, NonlinearSolveFirstOrder, LinearSolve, SteadyStateDiffEq); OrdinaryDiffEqCore must name OrdinaryDiffEqDifferentiation from S6; DiffEqBase's five moves are already held by joint ownership and the `interp_summary` narrowing breaks SDE solutions; Tsit5's per-step `@fold` tableau and `promote_op` on callback conditions as named hazards; the packages' quick tests; a positive control for strict mode; check J at S4; branch and tag clashes in the monorepo; the merge needs a pinned TraitWorld, a strict-off run and P4's steady state as reference | not yet acted on |
| [`2026-10-21-ndport-graph-plan.md`](../reviews/2026-10-21-ndport-graph-plan.md) | 2026-10-21 | current | (Opus 5.5) the graph plan of W-32 (P4 step 2: `GraphInterface` in Graphs, E-154). The declaration, the family over `AbstractGraph` and the refusal of Graphs' throwing fallbacks are correct and run in today's spelling; Graphs as plain code is sound; the upstream failures on `GenericGraph` are real. Blocker: criterion 1's broken type (no `ne`) is refused by Graphs' `NotImplementedError` in ND's plain reads before any bounded call. Should fix: PB-12 misreads where `Any` comes from (the erased key carries `V`; a negative is a deviation, not for the user), so no dynamic default; `GraphKernels` buys neither time nor correctness and reaches Makie's compute graph, marker geometry and projection (defer G5–G6 unless G0 (d) fails upstream); P4-1's per-call cost does not bite (few crossings); G3's `Int` index at `v::V`; per-type references in C; G0 (d) mandatory; four passes compared with three; G7 in the shared harness; name clashes (settings P4-1/P4-2, PB numbers, choices 15–16); the stale gate (choice 16). PB-13 real, answered by a split package, not for the user now. Timing: go now, trimmed; not behind P6 or open issue 48 | not yet acted on |
| [`2026-10-21-pickup-sciml-validation.md`](../plans/2026-10-21-pickup-sciml-validation.md) | 2026-10-21 | current: the pick-up note | where W-32, W-33, W-34 stand at the end of session 32, and what the next session does first |
| [`2026-10-21-w34-sciml-prerequisites.md`](../reviews/2026-10-21-w34-sciml-prerequisites.md) | 2026-10-21 | current | (Opus 5.5) the W-34 plan (what TraitWorld and the facts mode need for the SciML restructure, E-156–E-161, open issues 51–52). The inventory is careful. Blockers: W-35 is taken; form B needs no W-29 (TDE's two bounded `Callable` parameters run Rosenbrock today, the plan's own control); form A's `ODERHS{P}` cannot be declared for `ODEFunction` (no `P` in its type). Should fix: form A on a family member pays open issue 49's path per call (`_conf_family` in the split's target), so 49 is on its path and form B is the principled form; T-5 against T-57 answered by reading (the current-spelling block form is not lowered as a family in any module; the precheck evaluates the receiver without its `where`); the no-block family is a route around T-57, so moves 2–3 need no TraitWorld work first; L-3 lies on move 3's path in SciML's ownership (CommonSolve owns `solve!`); `MethodError`, not `TraitBoundError`, for a non-conforming integrator; open issue 51 misses a shared-`where` driver, `init` on the problem trait, and a configured-algorithm joint family; callback records under §7.4's free-parameter rule; E-160 needs no W-33 in move 4's layout; W-37 not needed | not yet acted on |

Earlier reviews, elsewhere:
- [`../../session-notes/2026-10-14-17-fable-review-of-note-rev1010.md`](../../session-notes/2026-10-14-17-fable-review-of-note-rev1010.md): the note at rev 1010 (16 findings, folded in at rev 1019). History.
- Reviews inside session notes 08 (August, critical review of TraitRegions), 18, 19, 20 (M9) and 24 (subagent reviews of the facts rules). History.
- `attic/reviews/`: the August architect memo and the binary review. History.

## Explorations (`writeup/explorations/`)

| Path | Date | Status | What it holds |
|---|---|---|---|
| [`sciml-as-traits.md`](../explorations/sciml-as-traits.md) | 2026-10-21 | exploration (Fable), the user's question on SciML's architecture as traits | the twelve goals SciML's overloading architecture serves; how Rust and Swift reach them; eleven principles for the design as it stands; the shortest route (wrap by facts, the right-hand side as `ODERHS`, callbacks and the integrator view, the front end's ownership, symbolic indexing as traits, the trajectory); pushback PB-A to PB-J |
| [`ndport-pushback.md`](../explorations/ndport-pushback.md) | 2026-10-21 | current: the W-32 pushback log | where the NetworkDynamics port meets a rule of the references and pays for it; P3-1: type computations that rely on Base's folding (facts §8; Static.jl's promotion) |
| [`ndport-principled-traits.md`](../explorations/ndport-principled-traits.md) | 2026-10-21 | input to the W-32 traits plan (P2); written by a Fable agent | the principled traits of Graphs, NetworkDynamics, SciML, Makie/GraphMakie and Observables for the NetworkDynamics port; why changing the equations recompiles everything (the component functions reach the `Network`'s type and SciML's `sys`); the ranking; thirteen pushback points |
| [`wrapping-by-facts.md`](../explorations/wrapping-by-facts.md) | 2026-10-17 | **current for the proofs**; its mechanisms (TraitWorld's `FactsInterp`) are now Julia's compiler | the design for using code written without traits: rule R, rule P, Theorems 1–3, Lemmas D and O; evidence on stock 1.13.2; validation (session 24, A3–A5, implementation rules 1–7); synthesis of three fresh designs |
| [`wrapping-designs/`](../explorations/wrapping-designs/) (`brief.md`, `proof-first.md`, `views.md`, `trusted-base-ffi.md`) | 2026-10-16 | history (inputs to the synthesis) | the brief given to three agents, and their three independent designs |
| [`strict-mode.md`](../explorations/strict-mode.md) | 2026-10-17 | current as detail; the guarantee is design.md §2.2; §2b deferred | rule S (defining a winning pirate is an error), the prototype (§2a), the intended design with Julia pieces 1′, 14, 15 (§2b, open-issues §1.1), split-core packages, the mode first assessed and not pursued |
| [`aot-under-facts.md`](../explorations/aot-under-facts.md) | 2026-10-17 | detail; summarized by `reference/traits.md` §15; written for the package policy | builds compile plain Julia; what traits still give AOT; three risks; annotations A–E (§6, deferred: open-issues §1.2); the first binary (§7, 4.07 MB) |
| [`julia-support.md`](../explorations/julia-support.md) | 2026-10-17 | superseded by `design/julia-changes.md` and `reference/compiler.md` | what TraitWorld needed from Julia: pieces 1–17 as of session 25, the order, what was implemented in sessions 23–24; piece 11 deferred (session 27). Knows nothing of (A)–(D) |
| [`dataframes-port-lessons.md`](../explorations/dataframes-port-lessons.md) | 2026-10-17 | detail; its TraitWorld mechanisms are history (site caches, trampolines removed in session 29); lesson 1.2 superseded by the assertion rule | lessons of the Tables/DataFrames/CSV port: run-time sites, keyword splats, types as values, where compiled code lives, porting guidelines; §5 what the compiler would remove |
| [`keys-plan.md`](../explorations/keys-plan.md) | 2026-10-16 | history (implemented, session 23) | how TraitWorld implements keys: decisions on two reviews, phases, the reference layout, the runtime as methods (§6) |
| [`runtime.md`](../explorations/runtime.md) | 2026-10-16 | history (the move to 1.13.2 done; the load filter removed) | the runtime the design needs; the recommendation to move to Julia 1.13.2 |
| [`runtime_load_filter_1.13.2.patch`](../explorations/runtime_load_filter_1.13.2.patch) | 2026-10-16 | history | the load half of the invalidation filter, ported to 1.13.2 |
| [`associated-types.md`](../explorations/associated-types.md) | 2026-10-16 | adopted in first-order form; written before keys (banner) | whether Rust's and Swift's associated types apply; joint parametrization; bounds |
| [`solvers.md`](../explorations/solvers.md) | 2026-10-16 | demonstrator design; written before keys (banner) | the design of TraitDifferentialEquations; the SciML baseline |
| [`makie-rewrite.md`](../explorations/makie-rewrite.md) | 2026-10-16 | demonstrator design; written before keys (banner) | the design of TraitMakie: fundamental traits, a typed compute graph, the minimal demonstrator |

## Plans (`writeup/plans/`)

| Path | Date | Status | What it holds |
|---|---|---|---|
| [`2026-10-17-dataframes-traits-plan.md`](../plans/2026-10-17-dataframes-traits-plan.md) | 2026-10-17 | paused (session 29, decision 5); the forks pass the upstream suites on the compiler (forks 8c6366a) | demonstrator 4: forks of Tables, DataFrames, CSV with traits; the falsifiable claim, the traits, the session workload, milestones M0–M6 |
| [`2026-10-17-policy-in-compiler-plan.md`](../plans/2026-10-17-policy-in-compiler-plan.md) | 2026-10-18 | history (done in session 29); superseded by `reference/compiler.md` and `design/julia-changes.md` | the pivot: (A) a facts mode of inference, (B) a second cache owner, (C) owner-aware dispatch; the go/no-go measurement; §6b (B)+(C) as built |
| [`2026-10-19-notes-cleanup-plan.md`](../plans/2026-10-19-notes-cleanup-plan.md) | 2026-10-19 | current (approved: attic, write now, own index file) | this cleanup: what is stale, the three-audience layout, the work file by file |
| [`2026-10-20-dynamic-compiled-implementation.md`](../plans/2026-10-20-dynamic-compiled-implementation.md) | 2026-10-20 | done (revision 3; semantics only, §1a) | W-4: the references first, the other documents, TraitWorld, the demonstrators, the measurements (E-147 to E-150), the current-state documents; design choices C1–C7 (mine) and questions Q1–Q5 |
| [`2026-10-21-networkdynamics-port.md`](../plans/2026-10-21-networkdynamics-port.md) | 2026-10-21 | adopted, in progress (W-32) | the meta plan of the large-scale test: NetworkDynamics, SciML, GraphMakie and Observables ported to the trait world; the ground rules, the parts P0–P5 and their plans, the pushback log, the state |
| [`2026-10-21-ndport-workload.md`](../plans/2026-10-21-ndport-workload.md) | 2026-10-21 | done (E-151) | W-32 P1: the clones and environments, the workload (tier S) and its harness, the settings U, P0, A0, S, equality of results, E-151 |
| [`2026-10-21-ndport-facts-first.md`](../plans/2026-10-21-ndport-facts-first.md) | 2026-10-21 | done (E-153) | W-32 P3: what the unchanged stack gains from the facts mode; the workload as a trait module, NetworkDynamics wrapped; load-order protection, strict mode, the cost of `all`; E-153 |
| [`2026-10-21-ndport-traits.md`](../plans/2026-10-21-ndport-traits.md) | 2026-10-21 | adopted | W-32 P2 and P4's first step: the traits of this round (`ComponentDynamics` now; Graph, VertexDynamics/EdgeDynamics, ODERHS and the others later), NetworkDynamics' component dynamics behind it in steps S0–S9, the criteria, E-152, the expected pushback |
| [`2026-10-21-ndport-graph.md`](../plans/2026-10-21-ndport-graph.md) | 2026-10-21 | done (E-154) but G3 | W-32 P4 step 2: a graph trait (`GraphInterface`; `Graph` is Graphs' alias of `SimpleGraph`) in Graphs as plain code, a family over `AbstractGraph`; consumers in NetworkDynamics and GraphMakie; correctness more than time; E-154 |
| [`2026-10-21-ndport-inside-out.md`](../plans/2026-10-21-ndport-inside-out.md) | 2026-10-21 | done (E-155) | W-32 P6: the SciML core made trait modules bottom-up under strict mode (S0–S7), the 63 pirates classified, joint owners (SciMLBase, OrdinaryDiffEqCore), the checks per step, the merge with P4; E-155 |
| [`2026-10-21-w34-sciml-prerequisites.md`](../plans/2026-10-21-w34-sciml-prerequisites.md) | 2026-10-21 | adopted (revised after its review) | W-34: what TraitWorld and the facts mode need to validate the SciML strategy, move by move; the prototypes E-156…E-161; draft work items and open issues 51–52 |

## `design-findings.md`, by section

[`../design-findings.md`](../design-findings.md), 2026-10-16 (session 22): the evidence log in the order the work happened. Its header classifies the sections. Even the "current evidence" predates wrapping by facts and the compiler: read its numbers as measured then, on the build named.

| § | Title | Status (its header) |
|---|---|---|
| 1 | Measurements behind the motivation | current evidence |
| 2 | Findings from the prototypes | not classified; reads as history (TraitRegions, the error split) |
| 3 | Design details | history (layering, seven rules) |
| 4 | Stage 1 proof of concept: the error split on stock Julia | not classified; reads as history |
| 5 | Verified programs and AOT (`verify_main`) | current evidence |
| 6 | Concrete mode | current evidence |
| 7 | Representations as trait parameters | history |
| 8 | Trade-offs in full | not classified; reads as history (the closed trait world) |
| 9–12 | Open issues; staging; other options; TraitWorld at rev 101 | history |
| 13 | Interface packages around DataFrames and Makie | current evidence (measured before keys; wrappers since removed) |
| 14 | Earlier forms of the design | history (by its nature) |
| 15 | Caching per representation, and Makie (session 21) | current evidence (measured before keys) |
| 16 | Between nested types and `Any` | current evidence |
| 17 | Where unreadable errors come from, and what bounds change | current evidence |
| 18 | Writable fields and lenses | current evidence |
| 19 | Keys replace representations, the reviews, the reference layout | current evidence |

## Other writeup documents

| Path | Date | Status | What it holds |
|---|---|---|---|
| [`decisions.md`](decisions.md) | 2026-10-19 | current as the decision log, in the record for agents; the design itself is in the references | every decision in force by topic, with status, origin, where it is written, and whether the prototype runs it; the superseded rows at the end |
| [`../open-issues.md`](../open-issues.md) | 2026-10-19 | current | everything open: §1 decisions for the user, §2 design, §3 TraitWorld, §4 runtime and measurements, §4b the session-23 review's triage, §5 documents; closed items at the end, under their numbers |
| [`../design/implementation.md`](../design/implementation.md) | 2026-10-19 | retired: a pointer page; the references are the source of truth | "The implementation in detail": its headings, each pointing at where its content is now (the references, the rationale, `state.md`) |
| [`../design/alternatives.md`](../design/alternatives.md) | 2026-10-19 | current as history | designs tried, rejected or replaced, by topic: each with the reason and what replaced it |
| [`design-history.md`](design-history.md) | 2026-10-19 | history | where the current documents came from, the order of work as done, the performance phase's before-and-after numbers, earlier numbers of the demonstrators |
| [`other-languages-research-2026-10-16.md`](other-languages-research-2026-10-16.md) | 2026-10-16 | current as research; describes our design as of session 22 (layering, projections) | how C++, Rust, Swift and Mojo arrived at their trait designs, with sources; twelve predictions for our design. The research behind `design/other-languages.md` |
| [`../porting-to-traits.md`](../porting-to-traits.md), moving to [`../intro/porting.md`](../intro/porting.md) | 2026-10-19 | in progress; superseded by `intro/porting.md` once moved | the porting guideline: part A, rules every port confirms; part B, what each port teaches; proposals for part A |
| [`../design/performance.md`](../design/performance.md) | 2026-10-19 | current | was `notes/5-performance.md`: where the costs come from, the themes (which owner code needs, the inliner, work an image could hold, what loads still cost), the control, remaining costs, upstream candidates; the phase's before-and-after numbers are in `design-history.md` |
| [`../design/evidence.md`](../design/evidence.md) | 2026-10-19 | current (2026-10-19); a chapter of the rationale; the references win where they disagree | the measurements behind the design, with builds, baselines and run counts; what is not shown |
| [`../design/julia-changes.md`](../design/julia-changes.md) | 2026-10-19 | current (2026-10-19); the references win where they disagree | every change to Julia, as built: parts (A)–(D), the performance-phase changes, the pieces, with commits and upstream status |
| [`../design/mechanisms.md`](../design/mechanisms.md) | 2026-10-19 | retired: a pointer page; the references are the source of truth | its headings, each pointing at the traits, lowering or facts reference section that holds its content now: declaring and conforming, generic implementations, `Callable`, keywords, results like the input, `Dynamic`, caching, AOT |
| [`../design/other-languages.md`](../design/other-languages.md) | 2026-10-19 | current (2026-10-19); a chapter of the rationale; the references win where they disagree | the design's choices against C++, Rust, Swift and Mojo; the twelve predictions of `other-languages.md` checked |

## The old notes (`attic/writeup/notes-2026-10-18/`)

History, superseded by `design.md` and its companions. Each left a stub at its old path `writeup/notes/`. They describe four rules, layering, sealing and representations in parts, and carry two banners saying so. Date: the last edit before the move.

| Path | Date | Superseded by | What it holds that is still useful |
|---|---|---|---|
| [`1-overview.md`](../../attic/writeup/notes-2026-10-18/1-overview.md) | 2026-10-18 | `intro/traits-for-julia.md`, design.md §2–3 | the worked example "a library and its user"; the pay-offs in plain words |
| [`2-design-choices.md`](../../attic/writeup/notes-2026-10-18/2-design-choices.md) | 2026-10-18 | `design/other-languages.md` | §1–4, 8–10, the costs, other options considered, predictions from other languages; §5–7 are history (layering, sealing) |
| [`3-wrapping.md`](../../attic/writeup/notes-2026-10-18/3-wrapping.md) | 2026-10-18 | `intro/porting.md`, design.md §3 | adopting traits one function at a time; traits over Base's functions; the four cases (Base, Cairo, ForwardDiff, Makie/CSV/DataFrames) |
| [`4-details.md`](../../attic/writeup/notes-2026-10-18/4-details.md) | 2026-10-18 | `design/mechanisms.md` | the terms; keywords, defaults, varargs; functions that cross; generic and named implementations; several traits; parametric user types; types that only convert; results like the input; identical or error |

Also in the attic ([`../../attic/README.md`](../../attic/README.md)): TraitRegions and the August ecosystem, the 1.12 filter patches (`attic/binary/`), the frozen live note at rev 1146 (`attic/writeup/traits-for-better-julia.md`), the proposals for stored values and definition checking, the poc2 and poc3 plans. All history.

## Session notes (`session-notes/`)

One note per working session. "Date" is the last commit to the note. Session 28 left no note; it is reconstructed in note 29.

| Note | Date | Main outcome |
|---|---|---|
| [`00-environment-and-workflow.md`](../../session-notes/00-environment-and-workflow.md) | 2026-10-19 | standing reference, rewritten in session 29: environment (the patched build, the facts image and its depot path), workflow rules (the lock, builds, checks after a Julia change, durable logs). The version of 2026-10-14, with the table of notes 01–20, is [`attic/session-notes/00-environment-and-workflow-2026-10-14.md`](../../attic/session-notes/00-environment-and-workflow-2026-10-14.md) |
| [`2026-08-09-01-setup.md`](../../session-notes/2026-08-09-01-setup.md) | 2026-08-09 | sandbox verified; the TraitRegions plan (Rung 1) read; the session-note convention |
| [`2026-08-09-02-plan.md`](../../session-notes/2026-08-09-02-plan.md) | 2026-08-09 | the user's mandate: reduce compilation dramatically, approach Python's feel, start a community discussion; the plan assessed |
| [`2026-08-09-03-m0-results.md`](../../session-notes/2026-08-09-03-m0-results.md) | 2026-08-09 | M0 spike: four lowerings, all gates pass (dyn tables 14 ms against 71 ms direct); go for M1 |
| [`2026-08-09-04-m1-traitregions.md`](../../session-notes/2026-08-09-04-m1-traitregions.md) | 2026-08-09 | TraitRegions.jl: `@trait`, `@seal`, `@region` macros (~330 lines) |
| [`2026-08-09-05-ecosystem-poc-sketch.md`](../../session-notes/2026-08-09-05-ecosystem-poc-sketch.md) | 2026-08-09 | proposal: a nine-package table ecosystem, each with a plain twin |
| [`2026-08-09-06-ecosystem-results.md`](../../session-notes/2026-08-09-06-ecosystem-results.md) | 2026-08-09 | the ecosystem built, X1–X7, X10, X11: region first calls flat at 14 ms against 25 ms plain; a sealed interpreter |
| [`2026-08-09-07-scaling-up-assessment.md`](../../session-notes/2026-08-09-07-scaling-up-assessment.md) | 2026-08-09 | DiffEq the best candidate, Makie at its ingestion boundary; Rung-3 stages A–C |
| [`2026-08-09-08-critical-review.md`](../../session-notes/2026-08-09-08-critical-review.md) | 2026-08-09 | review: sharing and first calls survive; immunity and sealed resolution as shown do not (A1, A2, B1, B2); seals as methods |
| [`2026-08-09-09-rung3-binary-sketch.md`](../../session-notes/2026-08-09-09-rung3-binary-sketch.md) | 2026-08-09 | a patched 1.12 binary (branch `trait-universe`): sealed resolution, universe-scoped invalidation (456 ms → 0) |
| [`2026-10-13-10-poc-error-split.md`](../../session-notes/2026-10-13-10-poc-error-split.md) | 2026-10-13 | the design rewritten around "identical or error", the edge-level rule and ownership; Stage 1 on stock 1.12.2 |
| [`2026-10-13-11-verify-main.md`](../../session-notes/2026-10-13-11-verify-main.md) | 2026-10-13 | `verify_main` and `isclosed`: a main whose whole reachable code is closed |
| [`2026-10-13-12-concrete-mode.md`](../../session-notes/2026-10-13-12-concrete-mode.md) | 2026-10-13 | design reset to the closure rule; concrete mode built (`@warn_on_abstract`) |
| [`2026-10-13-13-representation-parameter.md`](../../session-notes/2026-10-13-13-representation-parameter.md) | 2026-10-13 | the representation as a trait parameter, `@trait Name{R}`; the term "trait world" |
| [`2026-10-13-14-layering-and-existing-julia.md`](../../session-notes/2026-10-13-14-layering-and-existing-julia.md) | 2026-10-13 | design only: trait modules, layering as the core principle, seven rules |
| [`2026-10-13-15-traitworld.md`](../../session-notes/2026-10-13-15-traitworld.md) | 2026-10-13 | TraitWorld, the proof of concept of the new design: M0–M8, 117 tests |
| [`2026-10-14-16-adherence-and-module-structure.md`](../../session-notes/2026-10-14-16-adherence-and-module-structure.md) | 2026-10-14 | design only (rev 953–1019): conformance by field or methods, internal functions, parametric types, keywords |
| [`2026-10-14-17-fable-review-of-note-rev1010.md`](../../session-notes/2026-10-14-17-fable-review-of-note-rev1010.md) | 2026-10-14 | a Fable review of the note at rev 1010: sealing specified for one load order only; 16 findings |
| [`2026-10-14-18-poc3-review-and-m1-m4.md`](../../session-notes/2026-10-14-18-poc3-review-and-m1-m4.md) | 2026-10-15 | review of the note and the poc3 plan (no blockers); keyword/default/vararg arguments, `Callable` modes, the one-line conformance; 159 tests |
| [`2026-10-14-19-poc3-m3-packages.md`](../../session-notes/2026-10-14-19-poc3-m3-packages.md) | 2026-10-15 | the M3 packages; an error path gave every entry an edge that `using DataFrames` invalidated (fixed with barriers) |
| [`2026-10-15-20-crash-recovery-and-m8.md`](../../session-notes/2026-10-15-20-crash-recovery-and-m8.md) | 2026-10-15 | the machine crashed from parallel jobs (hence one job at a time); the trimmed pipeline (3.53 MB); M9 review |
| [`2026-10-15-21-view-caches-and-makie.md`](../../session-notes/2026-10-15-21-view-caches-and-makie.md) | 2026-10-15 | view caches per representation (first calls 3.1–3.3 ms); the load-time filter in patched Julia; Makie's tree protected by the filter: first PNG 8.5–8.9 s against 15.7–16.2 s (x13) |
| [`2026-10-16-22-other-languages-and-errors.md`](../../session-notes/2026-10-16-22-other-languages-and-errors.md) | 2026-10-16 | `other-languages.md`; error messages (findings §17); stored values; keys replace representations; `writeup/` reorganized (README, decisions, open issues) |
| [`2026-10-16-23-runtime-as-methods-and-demonstrators.md`](../../session-notes/2026-10-16-23-runtime-as-methods-and-demonstrators.md) | 2026-10-16 | D1–D9 accepted; patched 1.13.2 built; the runtime as methods (typed calls 33 ns against 30); TDE and TraitMakie step 1; wrapping by facts prototyped |
| [`2026-10-17-24-validating-wrapping-by-facts.md`](../../session-notes/2026-10-17-24-validating-wrapping-by-facts.md) | 2026-10-17 | wrapping by facts validated: acceptance 16/16, `g2all` 0 lost after 12 loads in every order; assumptions A3–A5 |
| [`2026-10-17-25-strict-mode-aot-and-julia-work.md`](../../session-notes/2026-10-17-25-strict-mode-aot-and-julia-work.md) | 2026-10-17 | strict mode and AOT explored; the Julia list reviewed (pieces 2, 4, 6 dropped); wrapping machinery removed; strict-mode prototype; first trimmed binary 4.07 MB |
| [`2026-10-17-26-demonstrators-and-traitreport.md`](../../session-notes/2026-10-17-26-demonstrators-and-traitreport.md) | 2026-10-17 | Python measured (0.60 s); TraitReport as demonstrator 3; the policy in a system image (prototype); the rows reviewed; TraitTables and TraitCSV decided |
| [`2026-10-17-27-traittables-traitcsv.md`](../../session-notes/2026-10-17-27-traittables-traitcsv.md) | 2026-10-17 | TraitTables and TraitCSV; the fresh-eye review and decisions 1–4; TraitReport (t) 0.52–0.56 s against Python 0.58–0.69 s; TDE gradients |
| (session 28: no note) | — | reconstructed in note 29: the DataFrames port M0–M5; the pivot to the compiler; (A) as a forked Compiler package (BaseBenchmarks geometric mean 1.016); sealing dropped; witness tables; key branches |
| [`2026-10-18-29-reviews-and-decisions.md`](../../session-notes/2026-10-18-29-reviews-and-decisions.md) | 2026-10-19 | four reviews; the user's decisions (strict mode first, `all` a test bed, stock dropped, `Dynamic` to the compiler, forks paused); then the autonomous run: (A)–(D) in Julia, TraitWorld's policy deleted, the certificate, the implementation review, the performance phase, the control, the performance review, this cleanup |

## Experiments (`experiments/`, its own repository)

The table in [`../../experiments/README.md`](../../experiments/README.md) lists only some directories. All of them:

| Directory | What |
|---|---|
| `factscompiler/` | the facts mode as a forked `Compiler` package (session 28) and the work after it: `results/` (BaseBenchmarks runs), `recovery/` (raytrace `rtopen.jl`, `rtvariants.jl`, `dynmicro.jl`), `control/` (the decisive control: `prep.sh`, `run.sh`, `lost.jl`), `scripts/` (the facts system image). README |
| `facts/` | evidence for wrapping by facts: E3, E4, E12; `acceptance.jl` and `acceptance_compiler.jl`; `g2all.jl`, `g2strict.jl`, `typedbench.jl`, `twolibs.jl`; `hunt/` (adversarial batches); `invalidation/` (`inval.jl`, S1–S8, stock and facts logs); `framing/` (S1–S10, Vararg splat, pirate tiers, G1.16). README |
| `examples/` | small cases for claims that had no example (session 29): strict mode on real pirates, a glue extension, heterogeneous collections, errors at definition, warnings that teach, redefinition; `run_all.sh`. README |
| `sysimage/` | the policy in the platform: TraitWorld in the system image (session 26; history since the compiler). README |
| `aot/` | trimmed binaries on 1.13 (`hello_app`, `plot_app`, `build.sh`) |
| `demos/` | the demonstrators' rows (`rows.sh`) and image sizes (`images.jl`) |
| `keys-proto/` | conformances as methods, a lean entry, one layout per key (session 22). README |
| `lens/` | the cost of a field reference against a held value; `layout.md` (findings §18) |
| `errors/` | where unreadable error messages come from: C++ templates and concepts, SciML (findings §17). README |
| `solvers/` | stock SciML baselines: time to first solve, callbacks, AD (`ttfs_*.jl`) |
| `runtime-injection/` | the load filter injected into stock 1.12.2 and 1.13.2 (history). README |
| `interfaces/` | the poc3 prototype around DataFrames and Makie (trait wrappers, sealing, view caches, x1–x16, the Python baseline `python/app.py`; history). README |
| `world/` | TraitWorld's first libraries, benchmarks, the first trimmed binary (history). README |
| `review-s23/` | scripts of the session-23 review (filter and override probes) |
| `baseline-1.13/`, `baseline-1.13.md` | the re-baseline on Julia 1.13 asked for by `runtime.md` |

## Repositories in the workspace

Each is its own repository, ignored by the design repository. The root [`README.md`](../../README.md) has a table; it is partly stale (TraitWorld no longer supports stock Julia; the invalidation filter is removed; patch pieces 2 and 4 are reverted). Latest commits as of 2026-10-19:

| Directory | What | Branch | Latest commit (as of 2026-10-19; `git -C <dir> log -1` for the current one) |
|---|---|---|---|
| `.` | the design repository: `writeup/`, `session-notes/`, `attic/` | `poc-error-split` | 82b8aeb Session note: the writeup cleanup |
| `julia-1.13/` | worktree of `julia/`: v1.13.2 with parts (A)–(D) and the remaining pieces | `trait-world-1.13` | a89a91629a tw-build.sh: the workspace's niced build under a memory watchdog |
| `julia/` | the clone; the 1.12 filter (history) | `trait-universe` | 0bf9125577 trait-world load filter: image validation keeps trait-world code … |
| `TraitWorld/` | the prototype package; requires the patched build | `main` | 375a930 A held view for immutable values that are their own implementing value |
| `TraitDifferentialEquations/` | demonstrator 1, ODE solvers | `main` | 65ca602 README: session 29's status and measurements on the facts compiler … |
| `TraitMakie/` | demonstrator 2, plotting | `direct-cairo` | 52f8591 README: session 29's status and measurements on the facts compiler … |
| `TraitReport/` | demonstrator 3, a data report against pandas | `main` | 9749baa README: session 29's status and measurements on the facts compiler … |
| `TraitTables/` | demonstrator 3's table library | `main` | 549d384 cellstring returns a String … |
| `TraitCSV/` | demonstrator 3's CSV reader | `main` | 6450ae7 Test: a table with a String15 column prints … |
| `forks/` | demonstrator 4: forks of Tables, DataFrames, CSV (paused) | `main` | 254ace8 README: session 29's status and measurements on the facts compiler … |
| `ndport/` | the large-scale test (W-32): the NetworkDynamics workload, its environments and logs; the clones under `ndport/pkgs/`, each its own repository on branch `trait-port` from the tag `upstream` | `main` | see `git -C ndport log -1` |
| `experiments/` | the smaller prototypes and measurements | `main` | e23ced3 README: the directories added since session 23, the design's current location |
| `TraitWorld-hooks/`, `TraitWorld-dynkeep/`, `TraitWorld-untyped/` | untracked old branches of TraitWorld (2026-10-16); they call removed Julia symbols and will not load. Superseded, not ported | various | c62efbf, 52cbca3, 5efbb4c |

### The Julia patch in sessions 28–29

Session 28 built (A) only as a forked package (`experiments/factscompiler`). Everything below is session 29, on `trait-world-1.13`. Older commits (sessions 23–27): the 1.12 filter's port (4d8eeebc19 … 280612ed2f), the hooks and pieces 1–5, 9, 10, 17 (dda21fe511 … db82407fa6).

| Commit | What |
|---|---|
| 880ae49dad | (A): a facts mode for the native interpreter |
| c3415abde6 | (B)+(C): code compiled by facts beside plain code |
| 25c630dd34 | boundaries in every lowered method; facts code found where plain code calls it |
| feaad9e45c | assertions trusted only in Julia's own methods under facts (later replaced); `--trim` compiles plainly |
| f6838f96fc | (D): a call on a dynamic value is split at the call site |
| 67f5c0bcc8 | the implementation review's fixes (critical: (D) with a known receiver type) |
| bc26aa9255 | the typed split: `dynamic_call` (renamed `split_call` on 2026-10-20) takes the declared result type |
| da4726c5cc | an invoke keeps the fact signature |
| 4102b7a7a7 | a cycle's members inline each other |
| c4f7e76a2f | compiler code is plain whoever calls it; pieces 2 and 4 removed |
| bb82a82bbf | reflection runs the native compiler in its world for an explicit `NativeInterpreter` |
| e4db37bb48 | `return_type_tfunc`'s facts signature is boxed (no closure per query type) |
| 40512f64c2 | the run-time `return_type` entry compiled into the image |
| 61852d8fb1 | the two inliner fixes apply to all code (narrowed to a widened varargs tail) |
