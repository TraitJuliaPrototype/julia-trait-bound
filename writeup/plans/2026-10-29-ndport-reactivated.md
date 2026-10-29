# The NetworkDynamics port reactivated, on the ports (W-32, phase 3)

Status: **adopted** (2026-10-29, the base by the user; the rest mine). A part plan of the [W-32 meta plan](2026-10-21-networkdynamics-port.md). Not normative: the references hold. Written by an agent of the main session; the base question was decided by the user while it was written.

**The base, decided by the user** (2026-10-29, relayed by the coordinator): "Nd definitely sits on the ports." NetworkDynamics builds on the trait SciML port (TraitDifferentialEquations, branch `w34`, its split packages) and on TraitMakie (main, with MakieCompat), not on upstream SciML and GraphMakie compiled by facts.

The rules for this work (the user, 2026-10-29, [the work queue's plan](../record/todo.md#the-plan)):
- no tweaks or workarounds that unification (W-83) would make obsolete: the simplest form that works, and the case listed for W-83 (§8);
- fix inference rather than add annotations;
- where the design blocks a principled solution, a candidate open issue (§7), not a design around it;
- W-32's rule: the references are not changed by the port; pushback is recorded;
- measure, do not optimise ("if we are beating Python already we don't really need much performance work"). NetworkDynamics has no Python analogue (the user, 2026-10-27); it is measured against upstream on the same build.

## 1. What was done, and what "almost done" left

Done (2026-10-21 to 2026-10-22; details in the meta plan's state and `ndport/README.md`):
- **P0:** the porting guideline brought up to date ([`../intro/porting.md`](../intro/porting.md)).
- **P1 (E-151):** the clones, the environments, the workload (tier S: swing equations on 20 vertices, the fixed point, a cascade of line trips by component callbacks, Tsit5 and Rodas5P, symbolic access, a GraphMakie PNG, a figure driven by Observables, new equations), its harness and digests; the baselines.
- **P3 (E-153):** NetworkDynamics wrapped whole as a trait module; Static.jl's promotion fixed.
- **P6 (E-155):** the SciML core under NetworkDynamics wrapped inside out under strict mode, upstream code with the wrap's lines only.
- **P4 step 1 (E-152):** `ComponentDynamics`; the batches erased; the network's type independent of the equations. New equations compile 0.45 s instead of 15 s.
- **P4 step 2 (E-154):** `GraphInterface{V}` in Graphs; a network builds on any `AbstractGraph`.
- **The merge (E-165):** P4 on P6's core, setting M (`ndport/env_merged`), results bit-equal to upstream, strict mode refusing nothing in the port's code.
- **P4 step 3, part 3a (E-166):** W-49 in TraitWorld; `VertexDynamics`/`EdgeDynamics` as subtraits; a crossing 36–48 ns; the steady state 29.5 ms.

What "almost done" left:
- part 3b: a user's own component types (`VertexModel(dynamics = x)`, the `usertype` pass; [the step-3 plan](2026-10-22-ndport-step3.md) §3.3, S3-4);
- P5: the measurement round at the finish, and the write-up;
- the traits plan's steps 4–7 into SciML (`ODERHS`, `IndexProvider`, `Trajectory`, the integrator and callbacks). W-34 built them since, as TraitDifferentialEquations' split packages. On the decided base they are not built into upstream SciML; NetworkDynamics uses TDE's.

## 2. The revival (E-235, done)

The merged port (setting M) on the current builds, julia-1.13 bfca89decc and TraitWorld main ca92f22 (ndport c0346ed, 51ced7c; `ndport/logs/revive*/`):
- `env_merged` resolved offline with TraitWorld from main: the manifest's only change. The stack precompiles under strict mode (370 packages, 388 s); no `OwnershipError`, no `PirateError`.
- **The 25 digests are exactly equal** to upstream's (E-151) and to E-166's, strict mode off and on.
- Strict mode on refuses nothing; the refusal of OffsetArrays' `reshape` (pushback P6-2) no longer occurs (not attributed).
- Step d's steady state 29.1–29.6 ms, as in E-166. E-162's 267.7 ms (open issue 66) does not recur.
- The session 59.6 s strict off, 62.0 s strict on (E-166: 65.2–66.1 and 83.8 s).

Nothing broke. Setting M stays as the control: upstream SciML and GraphMakie compiled by facts under the port's NetworkDynamics.

## 3. What carries over to the new base

| Work | On the ports |
|---|---|
| P0, the guideline | carries over; the lessons of this plan are added there |
| P1, the workload and harness | the harness carries over; the workload gets a variant for the ports' API (R5), and a new results reference (§5) |
| P3, NetworkDynamics as a trait module | carries over (choice 7 of the meta plan) |
| P4 steps 1, 2, 3a: `ComponentDynamics`, `VertexDynamics`/`EdgeDynamics`, the erased batches, `GraphInterface` | carry over unchanged: they do not touch SciML or Makie |
| P4 step 3b | still to do, on the new base (R6) |
| P6, the SciML core wrapped, and the merge | not on the new base. Setting M stays as the control (§2); its findings stay in the pushback log |
| Static.jl's fix | carries over while NetworkDynamics depends on Static |

What is redone: NetworkDynamics' SciML seam (about 280 lines touch SciML, in `symbolicindexing*.jl`, `callbacks.jl`, `initialization.jl`, `post_utils.jl`, `linear_analysis.jl`, `NetworkDynamics.jl`), and GraphMakie's base (Makie → TraitMakie with MakieCompat).

## 4. What NetworkDynamics needs that the ports lack

Read from TDE `w34` 3a51d95 and TraitMakie 2c70583 against the workload and NetworkDynamics' sources; R1 confirms each by running. Not built by this plan's agent: TDE and TraitMakie items go to the main session.

**SciML side (TDE `w34`):**

| # | Need | The ports today | Proposed |
|---|---|---|---|
| S1 | `ODEProblem` from a `Network` and an `NWState` | `ODEProblem(f, u0, tspan, p)`, `f` kept as a `Callable` at the right-hand side's signature | NetworkDynamics builds TDE's problem from the network as the function (R3a). Confirm that the network, a callable struct, enters as one |
| S2 | Rodas5P | Rodas5 only (`TraitRodas`) | the ported workload and its reference use Rodas5 (choice C2). No TDE work |
| S3 | values between steps (`sol(TIMES; idxs)`, `NWState(sol, t)`) | the solution keeps no interpolant; `at` is linear (`lib/ODECore/src/core.jl:562`) | the workload samples by `saveat = TIMES` (C3); dense output is candidate open issue A |
| S4 | symbolic access by `VIndex`/`EIndex`, ranges, observed values (`getu`, `sol(t; idxs)`) | `TraitIndexing`: names are `Symbol`s, no observed values | NetworkDynamics' own indexing over `NWState` stays NetworkDynamics' (C7); the solution's forms with `idxs` leave the workload; candidate open issue B |
| S5 | component callbacks: one `VectorContinuousCallback` and `PresetTimeCallback`s (DiffEqCallbacks) | `EventCallback{U, T, P}` with a scalar condition, located by bisection; `Callback`; `add_tstop!` | one `EventCallback` per component callback, a preset time by `add_tstop!` and a `Callback` (R3b). A vector condition is a TDE item only if R1 finds the per-component form wrong |
| S6 | the integrator from user code: `init`, `step!(integ, dt, true)`, `NWState(integ)` (step g) | integrators are internal; no public `init`/`step!` | **TDE item** |
| S7 | `remake(prob; p)` | none | the workload builds a new problem (C2's variant); `remake` a TDE item only if R3 needs it |
| S8 | the fixed point: `find_fixpoint` by `SteadyStateProblem` and NonlinearSolve | nonlinear solvers only inside implicit methods (`TraitNLSolvers`) | **TDE item:** a nonlinear problem with its solvers an open set (as the linear and nonlinear solvers of stages C and D) |
| S9 | linear stability (`jacobian_eigenvals`) | — | plain code (ForwardDiff, LinearAlgebra); no gap |
| S10 | mass matrices (algebraic components) | refused (pushback W34-9) | not in tier S; NetworkDynamics' tests that need them are expected failures until a TDE item |
| S11 | the MTK and CUDA extensions | depend on SciMLBase | out of scope |

**Plotting side (TraitMakie main, MakieCompat):** GraphMakie's `graphplot` recipe, unchanged, over MakieCompat (C5). What it uses beyond MakieCompat's slices 1–4:
- M1: `@recipe` with a graph argument and an edge-plot recipe child (`edgeplot`); `linesegments`; `scatter` with numeric colours, `colormap` and `colorrange`; `text` (labels, off in the workload); `lift` and `on` of a plot's attributes (MakieCompat: "not yet"); `Point2f` arithmetic and `BezierPath` (curved edges, off in the workload).
- M2: `hidedecorations!`, `limits!`, `Figure(size = …)`, `Axis(…; xlabel, ylabel)`, `fig[1, 2]`.
- M3: an `Observable` colour vector into `graphplot!`, a `lift`ed line into `lines!` (step g).
- M4: PNGs cannot equal CairoMakie's: the digests of steps f and g compare positions, colours and line data, not bytes.
- **TraitMakie items:** whatever of M1–M3 R1's census finds missing.

## 5. The finish line

**Must run:** tier S of the workload in a setting **PT** (NetworkDynamics on TDE `w34`'s split packages and TraitMakie with MakieCompat; GraphMakie's recipe over MakieCompat), the passes `first`, `again`, `params`, `changed`, `graphtype` and `usertype`, in fresh sessions, product setting, strict mode off and on.

**Checked:**
- results against **U′**, upstream's stack on the same build with the ported workload's choices (Rodas5, values by `saveat`), within the meta plan's choice 3 tolerances (states `rtol = 1e-5`, `atol = 1e-7`; trips closer than 0.05 as unordered groups). A failure is decided by a run of both at tight tolerances: which is nearer;
- PT's own runs exactly equal across its revisions; `usertype` and `graphtype` exactly equal to `first`;
- the network's type the same for both equations;
- strict mode refuses nothing in the port's code; the census counts no pirate in NetworkDynamics beyond L-38's registry methods;
- no reads of TraitWorld's internals (as W-34's finish);
- NetworkDynamics' test subset as far as the ports carry it; the rest listed as expected failures with the gap of §4 that causes each.

**Measured** (one round, a warm-up and 2 runs each, the same build): PT against U and stock S, with M as the control: the session (process start to exit), the loads, the first simulation (a–e), the first plot (f), new equations (`changed` b–e), the steady state (d). Reported, not optimised. Interop where NetworkDynamics' bounded functions call the user's plain functions; idiomatic trait code from the batches down into TDE's core.

## 6. The steps

| Step | What | Who | Size |
|---|---|---|---|
| R0 | the revival (E-235) | done | — |
| R1 | **the census of the gaps, by running:** NetworkDynamics' SciML calls listed per file against TDE's API; GraphMakie's recipe loaded over MakieCompat in a scratch environment, the workload's two plots attempted. Confirms or corrects §4; the list of TDE and TraitMakie items | this port | half a day |
| R2 | the TDE items (S6, S8; S5, S7 if R1 needs them) and the TraitMakie items (M1–M3) | the main session | by R1's list |
| R3 | **NetworkDynamics on TDE, a function at a time,** in a worktree `pkgs/NetworkDynamics-ports` (branch `ports` from `port` 4e5f5a2), `env_ports`, `depot-ports`: (a) dependencies and the problem; (b) callbacks; (c) the solution's access by `at` and `state`; (d) the fixed point; (e) linear analysis. Each sub-step keeps tier S running | this port | 1–2 days |
| R4 | GraphMakie on TraitMakie: a branch `ports` with Makie replaced by TraitMakie and MakieCompat; the recipe unchanged; `AbstractGraph` dispatch kept (C6) | this port | after R2's TraitMakie items |
| R5 | the workload's variant for the ports (`NDW_API=ports`: Rodas5, `saveat`, `NWState` from the solution, the integrator's `init`/`step!`); U′ by the same flag upstream; `compare_digests.py` by tolerance | this port | half a day |
| R6 | part 3b: a user's own component types ([the step-3 plan](2026-10-22-ndport-step3.md) §3.3) on the new base | this port | 1 day |
| R7 | the finish round (a registry row before it), `ndport/README.md`, the evidence row, the meta plan's state; pushback entries; the guideline's lessons | this port, the coordinator | half a day |

R1 comes first: it fixes R2's list for the main session. R3 and R5 can run while R2's items are built, against stand-ins only where an item is missing; each stand-in is removed when the item lands.

## 7. Candidate open issues

**A. Dense output for an open set of solvers.**
- Case: the workload reads the solution between steps (`sol(TIMES; idxs = …)`, `NWState(sol, t)`); upstream answers with each solver's own interpolant.
- The rule: move 5's `ODESolution{T, P}` has no axis for the solver, and `Trajectory`'s `at` is linear: "the solution keeps no interpolant" (`lib/ODECore/src/core.jl:562`; E-229).
- Proposal: the solution keeps the solver's interpolant as `Kept{Interpolant{U, T}}`, a trait each solver's step record implements (an open set, as the solvers are), and `at` calls it. No type parameter is added.

**B. Symbolic access by structured indices and observed values.**
- Case: NetworkDynamics' indices are `VIndex(i, :ω)`, `EIndex(i, :P)` and ranges (`vidxs(nw, :, :ω)`); edge outputs are observed, computed from the state; the workload reads them through `getu`, `observed` and `sol(t; idxs)` (about 130 lines of NetworkDynamics' two symbolic-indexing files touch SymbolicIndexingInterface).
- The rule: `TraitIndexing.IndexProvider` maps `sym::Symbol` to `Union{Nothing, Int}` (move 4, E-160); there is no observed value.
- Proposal: `IndexProvider{I}` with the provider's index type as a parameter, and an operation `observed(ip, idx)` returning a `Callable` at `(U, P, T)`. Or: symbolic access stays the library's, and the solution offers `state` and `at` only. The second is C7, the simplest form for now.

## 8. Cases for W-83

- **`GraphInterface{V}`:** a trait in Graphs declared as a family over the abstract type `AbstractGraph`, beside it, for Graphs' informal interface (E-154). With abstract types as traits, `AbstractGraph` would be the trait and the family would go. Kept as it is: no further graph operations are ported, and GraphMakie keeps its `AbstractGraph` dispatch (C6).
- **`VertexModel`/`EdgeModel` beside `VertexDynamics`/`EdgeDynamics`:** NetworkDynamics' records, subtypes of the abstract `ComponentModel`, and the traits per kind (3a), with a record keyword `dynamics = x` for a user's type (3b): two ways for a user to bring a component.
- **NetworkDynamics' problem beside SciML's abstract problem types:** the network as a TDE problem's function (S1), where upstream dispatches on `AbstractODEFunction` and `AbstractODEProblem`; the same case as `ODEProblemTrait` beside `AbstractODEProblem` (E-229).

## 9. Choices (mine, 2026-10-29)

- **C1.** P4's steps 1, 2 and 3a carry over unchanged.
- **C2.** The ported workload and its reference U′ use Rodas5, and build a new problem where the workload used `remake`.
- **C3.** Values at `TIMES` by `saveat`, until open issue A is decided.
- **C4.** U′ is the results reference, compared by tolerance; M stays as the control, rerun only for the finish round.
- **C5.** GraphMakie's recipe unchanged over MakieCompat (X3's waist test at a third-party package's scale), not a graph plot of TraitMakie's own.
- **C6.** GraphMakie keeps its `AbstractGraph` dispatch (W-83).
- **C7.** NetworkDynamics' symbolic indexing stays its own over `NWState`; the solution's `idxs` forms leave the ported workload, until open issue B is decided.
- **C8.** P6's trees and `env_merged` are kept, not developed further.
