# Pick up here: validating the SciML strategy (W-34)

Status: **current; the pick-up note for the next session** (written 2026-10-21, end of session 32). The next thing to work on is W-34's validation of the SciML strategy. Read this note, then the documents it names.

## Where things stand

- **W-32, the NetworkDynamics port** ([the meta plan](2026-10-21-networkdynamics-port.md); its state table and its "Choices for the user to review", 1–37):
  - **P0** done: the porting guideline ([`../intro/porting.md`](../intro/porting.md)) holds the principles (Part 0), the measured lessons of the port (B5) and the SciML case study (B6).
  - **P1** done (E-151): the workload, its harness (`ndport/scripts/run_workload.sh`), and the baselines.
  - **P3** done (E-153): NetworkDynamics wrapped whole; Static.jl's promotion fixed.
  - **P4** steps 1 (E-152: `ComponentDynamics`; new equations compile 0.45 s instead of 15 s) and 2 (E-154: `GraphInterface` in Graphs) done. Step 2's G3 (the feed-forward check in a bounded function) waits: its blocker, traits T-59, is fixed (TraitWorld f06b82d), so G3 can be redone.
  - **P6** done (E-155): the SciML core wrapped bottom-up under strict mode, bit-equal at every step.
  - **Not done:** the merge of P4 and P6 into one environment (the P6 plan §4; meta plan choice 35); P4's next steps (`VertexDynamics`/`EdgeDynamics`, then `ODERHS`).
- **W-33,** constant propagation from plain code into code compiled by facts (facts §6.3, F-17): see "W-33" below.
- **W-34,** the SciML strategy: the exploration [`../explorations/sciml-as-traits.md`](../explorations/sciml-as-traits.md) (with the user's correction: DiffEq.jl's solvers are an open set; the corrected route is in the guideline's B6) and the inventory plan [`2026-10-21-w34-sciml-prerequisites.md`](2026-10-21-w34-sciml-prerequisites.md), reviewed ([`../reviews/2026-10-21-w34-sciml-prerequisites.md`](../reviews/2026-10-21-w34-sciml-prerequisites.md), 21 findings, three blockers), **not yet revised**.
- **W-35,** porting strategies for Makie and DataFrames (Fable agents, as for SciML): queued.

## W-33

- **Done** (julia-1.13 2943086604, `facts_const_prop_call`): a plain caller propagates constants into a facts method; the callee is inferred again by facts rules in a call stack of its own; the result is local and the caller's edges stay on the constant's path. Facts §6.3 Implemented, F-17 retired.
- Acceptance G1.27–G1.29 (29 of 29, product and `all`); every suite passes (`experiments/checks/logs/w33/`; under `all` the known F-8 hole).
- SciMLBase's `getproperty` reads from plain code: 0 of 17 wider than `getfield` (17 of 17 before; `ndport/logs/p6-diag/constprop-w33.log`). The S2 steady state was not timed again.
- **The build changed:** every package image is rebuilt at its first use. `env_p6` is precompiled again (433 s); the other environments are not yet.
- Open issue 52 (mine): concrete evaluation does not cross the modes.

## Overnight (W-39)

- **Running on the idle machine** (started 2026-10-21 21:52, `experiments/overnight-2026-10-21/run.sh`, detached): the environments re-precompiled on the new build; E-162 (the NetworkDynamics workload, five runs per setting U, P0, N, P4, I, A0, and order B); E-163 (the round of 2026-10-20 again: calls, the quick subset, the demonstrators' rows, the full BaseBenchmarks); E-164 (W-16's heterogeneous rows).
- **First thing next session:** read `experiments/overnight-2026-10-21/logs/driver.log` (a line per part, with the load), then the summaries (`e162-summary.txt`, `e162-orderB-summary.txt`, `e162-digests.txt`, `compare-full.log`, `compare-*-vs-round.log`, `logs/demos/`, `hetero-idiomatic/logs/night1-*`); write the outcomes into the registry (E-162–E-164), the evidence and `ndport/README.md`; commit the logs (experiments, ndport).

## Also reopened

- **Open issue 54, hidden type parameters** (the user reopened it, 2026-10-21): the points where they came up are listed there; options to be worked out when the user takes it up.

## The next session: what to do, in order

1. **The W-34 plan is adopted** (revised after its review at the end of session 32): form B for move 1 (the right-hand side at bounded `Callable` parameters, TraitDifferentialEquations' form); open issue 51 with options (a)–(e); work items W-36 (L-3), W-37 (the block forms of a family), W-38 (waiting for E-156); experiments E-156–E-161 registered as proposed; its choices 38–47 in the meta plan.
2. **Put open issues 49, 51, 52 and 54 to the user** (54: hidden type parameters, reopened by the user) (49: a typed call of a family member builds its trait object at run time; 51: as revised).
3. **Run E-156** (the TraitWorld probes P1a–P13, predictions written in), then E-157 (move 1, form B, with move 5's check), E-158 (move 2), E-159 (move 3: Rodas5 moved out of TraitDifferentialEquations, a CommonSolve stand-in, the census's negative control), E-160 (move 4): the rows are in the registry; set each to running when it starts. W-36's study beside E-159.
4. **On the port, in parallel where the lock allows:** G3 again; the P4/P6 merge on the current build; P4 step 3.

## Before starting

- `CLAUDE.md` (the rules for the documents), [`../record/todo.md`](../record/todo.md) (W-32…W-35), [`../open-issues.md`](../open-issues.md) §1 (46, 47, 49 for the user; 51 to come), the meta plan's choices list (1–37, for the user to review), the latest session note [`../../session-notes/2026-10-21-32-values-carry-through-storage.md`](../../session-notes/2026-10-21-32-values-carry-through-storage.md).
- The machine's rules: one Julia job at a time through the lock; quick checks; full builds alone (`julia-1.13/tw-build.sh`); [`../record/INDEX.md`](../record/INDEX.md), "Standing constraints".
- The user's standing rules for this work: the design is not changed by the port; agents may add highly orthogonal features for port needs; changes to existing designs or features go to the user; a Planned reference part the work needs is implemented first.
- The workspace: `ndport/README.md` (settings U, P0, A0, S, N, W, P4, I; environments and depots per track; never touch another track's worktree or environment).
