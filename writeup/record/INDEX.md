# The record: an index for agents

This is the map of everything on record: findings, experiments, decisions, reviews and session logs. It is written for agents (future Claude sessions) who need to find a fact, a number or the history of a decision. Nothing here is the design itself.

Written 2026-10-19 (session 29, the writeup cleanup: [`../plans/2026-10-19-notes-cleanup-plan.md`](../plans/2026-10-19-notes-cleanup-plan.md)).

## The three-audience layout

- **Programmers** (Julia users, no compiler terms): [`../intro/`](../intro/)
  - `traits-for-julia.md`: what you write, what you get, one worked example;
  - `results.md`: what the demonstrators show, in plain words;
  - `porting.md`: how to port a package (was `writeup/porting-to-traits.md`).
- **Core developers** (the precise rules and the major implementation choices):
  - [`../design.md`](../design.md): **the source of truth**;
  - [`../design/`](../design/), its companions:
    - `julia-changes.md`: every change to Julia as built (parts A–D, optimizer changes, pieces kept and reverted);
    - `evidence.md`: the current measurements, one table per demonstrator and experiment;
    - `performance.md`: the performance phase of session 29, its themes and learnings;
    - `mechanisms.md`: the detail `design.md` compresses (keywords, varargs, functions that cross, several traits, parametric types, types that only convert);
    - `comparison.md`: the choices against C++, Rust, Swift and Mojo, and their costs.
- **Agents:** this index, and the files it lists.

**Rules for reading the record:**
- `design.md` wins wherever a record document disagrees with it.
- A record document is either history (a design or mechanism since replaced) or detail (true, but too fine for `design.md`). The tables below say which.
- The record files stay at their paths: session notes, reviews and other repositories cite them more than a hundred times. Only the four old notes moved (to the attic), and `porting-to-traits.md` (to `intro/porting.md`), each with a stub at its old path.

## How to resume work

Read, in this order:
1. [`../design.md`](../design.md): the design, the decisions in force (§7), the evidence (§8), the implementation and the next steps (§9).
2. [`../open-issues.md`](../open-issues.md) §1: the decisions waiting for the user.
3. The latest session note, [`../../session-notes/2026-10-18-29-reviews-and-decisions.md`](../../session-notes/2026-10-18-29-reviews-and-decisions.md):
   - its "Next" section is from the start of session 29 and is done;
   - read instead the last bullets of "Autonomous run": the user's decisions on the performance review (2026-10-19: the inliner fixes for all code; next, diagnose and fix the remaining load costs, the compiler-edge hole B1 and a machinery workload; a lean held view) and the approval of the cleanup plan.

**Standing constraints** (root [`README.md`](../../README.md) "Conventions", [`00-environment-and-workflow.md`](../../session-notes/00-environment-and-workflow.md) "Basic workflow", item 6):
- The machine is shared with other simulations (30 GB, 16 cores). **One Julia job at a time,** never parallel chains. A parallel chain crashed the machine on 2026-10-15 (session note 20).
- Run Julia niced and serialized through the shared lock: `flock /tmp/claude-1000/julia-review.lock nice -n 19 …`, with `JULIA_NUM_PRECOMPILE_TASKS=4`. (The lock is used by the reviews of 2026-10-18; the workflow note itself says `nice -n 10` and does not name the lock.)
- **Full builds of Julia alone,** through `julia-1.13/tw-build.sh`: `make -j4`, niced, killed below 4 GB available memory. `TW_TARGET=julia-sysimg-release` rebuilds only the system image. Check `BUILD EXIT` at the end of `tw-build.log` after every build: two builds failed in session 29.
- **Principled fixes over workarounds:** fixes that a future trait-world ecosystem would have (a trait-world CSV reader, a Julia patch), not local tricks. Slowdowns are acceptable if traits can recover them (session 29, decision 6).
- Do not edit TraitWorld while another job loads it from source against an older Julia (session 29).
- Scratch files go in the session scratchpad. `/tmp` is a tmpfs: it does not survive a reboot.

## Where to look for…

- **A decision's history:** [`../decisions.md`](../decisions.md).
  - Rows are grouped by session (the core, keys, parameters, code written without traits, runtime; then sessions 27, 28, 29 and three "Session 29" groups).
  - Rows marked **history** were superseded, withdrawn or retired; the status column says by what.
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
- **The acceptance suite:** `experiments/facts/acceptance_compiler.jl` (19/19 on the compiler, G1.x and G2.x cases); the package-era suite is `experiments/facts/acceptance.jl` (16/16 in session 24).
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
| [`2026-10-18-framing-and-motivation.md`](../reviews/2026-10-18-framing-and-motivation.md) | 2026-10-18 | current as reasoning; wording superseded by design.md §2–3 | the framing and the user's two-goal reframing. "Piracy is the principal cause of invalidation" is false for stock Julia (S1–S8); rule R is the hidden premise; §5: strict mode first | adopted as the framing; design.md §2–3 rewritten on the user's four steps; `inval.jl` now in `experiments/facts/invalidation/` |
| [`2026-10-18-implementation-shape.md`](../reviews/2026-10-18-implementation-shape.md) | 2026-10-18 | history (its migration is done) | TraitWorld and the patch after the pivot. The foreign cache owner is the largest path dependency; the protection is trait-independent (the control is missing); `Dynamic` belongs in the compiler; the forks validate a barrier | its migration order became the order of work: (A), (B)+(C), (D), TraitWorld's policy deleted (8,718 → 7,321 lines), the control; forks re-ported on `cell`/`nrows` and `CSVColumn{T}` |
| [`2026-10-18-examples-and-demonstrators.md`](../reviews/2026-10-18-examples-and-demonstrators.md) | 2026-10-18 | current for its gaps list; partly done | every example and demonstrator under the user's criterion (work after an import should be instant). No strict refusal in a demonstrator, no certificate, no teaching warning; the framing's evidence only in `/tmp`; ranked new examples | `experiments/examples/` and `experiments/facts/framing/` written; the fully-typed certificate built (TraitWorld 1098fab) |
| [`2026-10-18-decisions-revisited.md`](../reviews/2026-10-18-decisions-revisited.md) | 2026-10-18 | history (applied in design.md) | every register row for conceptual simplicity: of 87 rows, 51 keep, 5 simplify, 2 change, 16 retire, 9 merge; ten ranked changes; a simplified core | changes 1 and 3–10 adopted, 2 rejected (`Callable` keeps both modes); `design.md` written; retired rows marked history |
| [`2026-10-19-compiler-implementation.md`](../reviews/2026-10-19-compiler-implementation.md) | 2026-10-19 | history (findings fixed or stated) | the compiler as built (julia db82407fa6..f6838f96fc). Architecture sound, images work; (D) compiled wrong code for a known receiver type (critical); the assertion exemption broke G1; `--trim` left facts flags; (C) covers codegen's call sites only; the split boxes | (1) fixed, G1.18; (2) replaced by "no asserted effect applies to a frame with a run-time site", G1.19; (3) fixed; (4) to state in design.md; (5) the typed split (bc26aa9255); (6) stated as a trade. julia 67f5c0bcc8, acceptance 19/19 |
| [`2026-10-19-performance-phase.md`](../reviews/2026-10-19-performance-phase.md) | 2026-10-19 | current (its next steps are the next work) | the performance phase. Theme 2 wrong (the inliner habits cost stock Julia 56×); the control's arithmetic wrong (~990 ms after loads under `all`, undiagnosed); a clean-case regression omitted; B1: machinery calling the compiler holds plain edges; the three-way extension is a workaround | the notes rewritten (now `design/performance.md`); the user: inliner fixes for all code (61852d8fb1), diagnose then fix, a lean held view (TraitWorld 375a930); B1 documented in design.md §6 |

Earlier reviews, elsewhere:
- [`../../session-notes/2026-10-14-17-fable-review-of-note-rev1010.md`](../../session-notes/2026-10-14-17-fable-review-of-note-rev1010.md): the note at rev 1010 (16 findings, folded in at rev 1019). History.
- Reviews inside session notes 08 (August, critical review of TraitRegions), 18, 19, 20 (M9) and 24 (subagent reviews of the facts rules). History.
- `attic/reviews/`: the August architect memo and the binary review. History.

## Explorations (`writeup/explorations/`)

| Path | Date | Status | What it holds |
|---|---|---|---|
| [`wrapping-by-facts.md`](../explorations/wrapping-by-facts.md) | 2026-10-17 | **current for the proofs**; its mechanisms (TraitWorld's `FactsInterp`) are now Julia's compiler | the design for using code written without traits: rule R, rule P, Theorems 1–3, Lemmas D and O; evidence on stock 1.13.2; validation (session 24, A3–A5, implementation rules 1–7); synthesis of three fresh designs |
| [`wrapping-designs/`](../explorations/wrapping-designs/) (`brief.md`, `proof-first.md`, `views.md`, `trusted-base-ffi.md`) | 2026-10-16 | history (inputs to the synthesis) | the brief given to three agents, and their three independent designs |
| [`strict-mode.md`](../explorations/strict-mode.md) | 2026-10-17 | current as detail; the guarantee is design.md §3.2; §2b deferred | rule S (defining a winning pirate is an error), the prototype (§2a), the intended design with Julia pieces 1′, 14, 15 (§2b, open-issues §1.1), split-core packages, the mode first assessed and not pursued |
| [`aot-under-facts.md`](../explorations/aot-under-facts.md) | 2026-10-17 | detail; summarized by design.md §4.8; written for the package policy | builds compile plain Julia; what traits still give AOT; three risks; annotations A–E (§6, deferred: open-issues §1.2); the first binary (§7, 4.07 MB) |
| [`julia-support.md`](../explorations/julia-support.md) | 2026-10-17 | superseded by `design/julia-changes.md` and design.md §6 | what TraitWorld needed from Julia: pieces 1–17 as of session 25, the order, what was implemented in sessions 23–24; piece 11 deferred (session 27). Knows nothing of (A)–(D) |
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
| [`2026-10-17-policy-in-compiler-plan.md`](../plans/2026-10-17-policy-in-compiler-plan.md) | 2026-10-18 | history (done in session 29); superseded by design.md §6 and `design/julia-changes.md` | the pivot: (A) a facts mode of inference, (B) a second cache owner, (C) owner-aware dispatch; the go/no-go measurement; §6b (B)+(C) as built |
| [`2026-10-19-notes-cleanup-plan.md`](../plans/2026-10-19-notes-cleanup-plan.md) | 2026-10-19 | current (approved: attic, write now, own index file) | this cleanup: what is stale, the three-audience layout, the work file by file |

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
| [`../decisions.md`](../decisions.md) | 2026-10-19 | current as the register; the state in force is design.md §7 | every decision with status, where it is written, and whether the prototype runs it; history rows kept |
| [`../open-issues.md`](../open-issues.md) | 2026-10-18 | current; items closed in session 29 not yet all marked (plan step 5) | everything open: §1 decisions for the user, §2 design, §3 TraitWorld, §4 runtime and measurements, §4b the session-23 review's triage, §5 documents |
| [`../other-languages.md`](../other-languages.md) | 2026-10-16 | current as research; describes our design as of session 22 (layering, projections) | how C++, Rust, Swift and Mojo arrived at their trait designs, with sources; twelve predictions for our design. The research behind `design/comparison.md` |
| [`../porting-to-traits.md`](../porting-to-traits.md), moving to [`../intro/porting.md`](../intro/porting.md) | 2026-10-19 | in progress; superseded by `intro/porting.md` once moved | the porting guideline: part A, rules every port confirms; part B, what each port teaches; proposals for part A |
| [`../design/performance.md`](../design/performance.md) | 2026-10-19 | current | was `notes/5-performance.md`: results of the performance phase, the themes (corrected by the review), the control, remaining costs, upstream candidates |

## The old notes (`attic/writeup/notes-2026-10-18/`)

History, superseded by `design.md` and its companions. Each left a stub at its old path `writeup/notes/`. They describe four rules, layering, sealing and representations in parts, and carry two banners saying so. Date: the last edit before the move.

| Path | Date | Superseded by | What it holds that is still useful |
|---|---|---|---|
| [`1-overview.md`](../../attic/writeup/notes-2026-10-18/1-overview.md) | 2026-10-18 | `intro/traits-for-julia.md`, design.md §2–3 | the worked example "a library and its user"; the pay-offs in plain words |
| [`2-design-choices.md`](../../attic/writeup/notes-2026-10-18/2-design-choices.md) | 2026-10-18 | `design/comparison.md` | §1–4, 8–10, the costs, other options considered, predictions from other languages; §5–7 are history (layering, sealing) |
| [`3-wrapping.md`](../../attic/writeup/notes-2026-10-18/3-wrapping.md) | 2026-10-18 | `intro/porting.md`, design.md §3 | adopting traits one function at a time; traits over Base's functions; the four cases (Base, Cairo, ForwardDiff, Makie/CSV/DataFrames) |
| [`4-details.md`](../../attic/writeup/notes-2026-10-18/4-details.md) | 2026-10-18 | `design/mechanisms.md` | the terms; keywords, defaults, varargs; functions that cross; generic and named implementations; several traits; parametric user types; types that only convert; results like the input; identical or error |

Also in the attic ([`../../attic/README.md`](../../attic/README.md)): TraitRegions and the August ecosystem, the 1.12 filter patches (`attic/binary/`), the frozen live note at rev 1146 (`attic/writeup/traits-for-better-julia.md`), the proposals for stored values and definition checking, the poc2 and poc3 plans. All history.

## Session notes (`session-notes/`)

One note per working session. "Date" is the last commit to the note. Session 28 left no note; it is reconstructed in note 29.

| Note | Date | Main outcome |
|---|---|---|
| [`00-environment-and-workflow.md`](../../session-notes/00-environment-and-workflow.md) | 2026-10-15 | standing reference: environment, workflow rules, a table of notes 01–20. Partly stale: Julia 1.12.2, `poc/` paths (now `experiments/`), reading order through the frozen note |
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

| Directory | What | Branch | Latest commit |
|---|---|---|---|
| `.` | the design repository: `writeup/`, `session-notes/`, `attic/` | `poc-error-split` | 0cd8694 Writeup cleanup begins: notes/5-performance.md becomes design/performance.md |
| `julia-1.13/` | worktree of `julia/`: v1.13.2 with parts (A)–(D) and the remaining pieces | `trait-world-1.13` | 61852d8fb1 Compiler: the two inliner fixes apply to all code |
| `julia/` | the clone; the 1.12 filter (history) | `trait-universe` | 0bf9125577 trait-world load filter: image validation keeps trait-world code … |
| `TraitWorld/` | the prototype package; requires the patched build | `main` | 375a930 A held view for immutable values that are their own implementing value |
| `TraitDifferentialEquations/` | demonstrator 1, ODE solvers | `main` | c571ff8 routea tests: comments |
| `TraitMakie/` | demonstrator 2, plotting | `direct-cairo` | 63103d8 README: how the session-30 runs ran (TraitWorld's own policy) … |
| `TraitReport/` | demonstrator 3, a data report against pandas | `main` | 6eb107c README: how the session-30 runs ran (TraitWorld's own policy) … |
| `TraitTables/` | demonstrator 3's table library | `main` | 549d384 cellstring returns a String … |
| `TraitCSV/` | demonstrator 3's CSV reader | `main` | 6450ae7 Test: a table with a String15 column prints … |
| `forks/` | demonstrator 4: forks of Tables, DataFrames, CSV (paused) | `main` | 9d512a1 CSV: an extension over DataFrames and InlineStrings carries the String15 workload |
| `experiments/` | the smaller prototypes and measurements | `main` | a0432d2 control: the facts depot path includes ~/.julia … |
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
| bc26aa9255 | the typed split: `dynamic_call` takes the declared result type |
| da4726c5cc | an invoke keeps the fact signature |
| 4102b7a7a7 | a cycle's members inline each other |
| c4f7e76a2f | compiler code is plain whoever calls it; pieces 2 and 4 removed |
| bb82a82bbf | reflection runs the native compiler in its world for an explicit `NativeInterpreter` |
| e4db37bb48 | `return_type_tfunc`'s facts signature is boxed (no closure per query type) |
| 40512f64c2 | the run-time `return_type` entry compiled into the image |
| 61852d8fb1 | the two inliner fixes apply to all code (narrowed to a widened varargs tail) |
