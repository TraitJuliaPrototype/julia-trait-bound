# The measurement round (phase 5, W-145): what is run, on what, in which order

**Status:** adopted (2026-11-14), mine, under the user's schedule (2026-11-11: "Then thoroughly measure it") and words on the cache (2026-11-14: "The measurement campaign should contain workloads that would exercise it and break down times in such a way that we can make a clear judgment."). Written in the main session. Not normative: each run has a row in [the registry](../record/experiments.md), written before the run; the numbers go to [the evidence](../design/evidence.md).

## The frozen build

Every run of the round is on these commits. A fault found during the round is recorded, not fixed, unless a run cannot proceed; a fix then restarts the parts it touches, and the row says so.

| Repository | Branch | Commit |
|---|---|---|
| `julia-unified` | `unified` | 86deee2f98 |
| `julia-vanilla` (the control: v1.13.2's source built the same way) | | 45b6d15e34 |
| `TraitWorld-unified` | `unified` | baadf9f |
| `TraitTables-unified`, `TraitCSV-unified`, `TraitMakie-unified`, `TraitReport-unified` | `unified` | c339175, 92c46d0, c862914, a4bcf33 |
| `TraitDifferentialEquations-unified` | `unified` | f8c6765 |
| `forks-unified` (Tables, CSV, DataFrames) | `unified` | 439bae7 |
| `ndport` | `main` | ef6fe3d; the clones' `unified`: NetworkDynamics 6310040, Graphs dbcb7c70, GraphMakie 498be7c |

Frozen 2026-11-14, after phase 4 (E-373). Each repository carries the tag `round-2026-11` at its frozen commit.

## Rules of the round

- The machine's rules hold ([CLAUDE.md](../../CLAUDE.md)): the load is read before each part; one Julia job at a time for timed runs; 4 cores a job.
- A timed run states its build, setting, load order, number of runs and the load. Times are the minimum and the range of fresh processes after a warm-up, as in each script's README.
- Speed is measured as a control only (G-2: no regression where types are known; G-4: what a rule costs). No row asks whether trait code is faster.
- Each part ends with: its registry rows done, its evidence rows, the standing in [the goals](../goals.md) where it changes, and a tension's cost where it prices one.
- What the round shows as a loss against an earlier build or plain Julia goes to the list for phase 6 (W-146), not into a fix.

## The parts, in order

The order follows the weakest axes first ([the goals](../goals.md) §2).

| Part | Axis | The question | What is run | Scripts |
|---|---|---|---|---|
| 1 | G-2 | Does a call through a trait cost what a plain call costs where types are known; what do `compiled_for`, a value known by its trait and a `Dynamic` cost | a typed trait call, a cast call, a call on a `Vector{X}`'s element, a `Dynamic{X}` call and a `Callable` in each form, each beside its plain twin (W-17, as a control) | `experiments/unification/w145/calls/` (new) |
| 2 | G-3 | What would a cache across sessions hold | two independent trait packages first combined in `Main`: the membership declared by the type's package, by a third package, in the session; the plain twin; each compile's time given to the package whose method it is; the second session of an unchanged script | `experiments/unification/w145/cache/` (new), with `w120/classify_trace.py` |
| 3 | G-1 | Is compiled code kept through unrelated loads, in composition and at the prompt | E-355, E-357, E-358, E-359, E-360 again; the code slot's share (W-119) | `w134/` (`run.sh`, `run_demo.sh`, `run_repl.sh`, `comp/`, `member/`) |
| 4 | G-4 | What does code that uses no trait pay; what does a membership's walk cost at a load | E-356 again; the library's load at a prompt; W-140's rounds (`load_invalidations.jl` with its control) on the ports' loads | `w134/plain.sh`, `w140/`, `w120/load_invalidations.jl` |
| 5 | G-6 | Which programs build, how large, and does the session's check agree | every demonstrator's program under `--trim=safe` and `unsafe-warn`, beside its plain twin and on vanilla; the small programs; the check against the build | `w135/` (`run_warn.sh`, `run_safe.sh`, `run_rest.sh`), `w139/run.sh`, `w142/agree.sh` |
| 6 | G-5 | Are the messages better than plain Julia's on the frozen build | the fixed list of mistakes in both forms; SciML's three cases | `w136/run.sh`, `w136/sciml/` |
| 7 | G-7 | The ports against upstream: first work, repeated work, sessions | the forks' session against upstream's; the ODE port against its plain twin; NetworkDynamics' workload; the report's forms | `forks-unified/scripts/measure_session.sh`, `w120/sessions.sh`, `ndport/scripts/u_workload.sh`, `TraitReport-unified/scripts/measure.sh` |
| 8 | the tensions | What does each rule behind a tension cost on the frozen build | the entries of [open issues](../open-issues.md) §1 whose cost is a number: each measured by the tool its entry names, or marked "not measurable here" with the reason | the tools named in the entries |

## What the round does not do

- It builds no cache across sessions and fixes no loss.
- It does not rerun the earlier build's rounds: where a number exists only for the earlier build, the evidence says so.
- It does not measure a port that phase 4 left failing beyond its known failures; those are listed with the round's results.
