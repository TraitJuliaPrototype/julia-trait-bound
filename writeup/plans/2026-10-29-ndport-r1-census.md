# The NetworkDynamics port on the ports: the census of the gaps (R1)

Status: **done** (2026-10-29). Step R1 of [the reactivation plan](2026-10-29-ndport-reactivated.md) (W-32). Not normative: the references hold. The items for R2 are proposals; the main session decides which are built. Written by the port's agent; the choices in §6 are mine.

Experiments: E-236 (the SciML side) and E-237 (the plotting side), in [the registry](../record/experiments.md). Builds: julia-1.13 bfca89decc, TraitWorld main ca92f22, TraitDifferentialEquations (TDE) `w34` 3a51d95, TraitMakie main 2c70583. Product setting. Not a measurement.

## 1. How the census was taken

- **Setting PT** (`ndport/env_ports`, `depot-ports`): NetworkDynamics from a worktree `ndport/pkgs/NetworkDynamics-ports`, branch `ports` from `port` 4e5f5a2. Its upstream SciML dependencies (SciMLBase, DiffEqBase, DiffEqCallbacks, NonlinearSolve, SteadyStateDiffEq, LinearSolve, RecursiveArrayTools) are replaced by TDE's `ODECore`, `TraitArrayTools` and `TraitIndexing`. SymbolicIndexingInterface stays (choice R1-a, §6).
- **Stubs:** every upstream name NetworkDynamics still uses is a stub in `src/r1_stubs.jl`. A stub throws `R1Gap(name)` when a run reaches it. Places adapted for the census are marked `# R1:` (branch `ports`, commits 068dcc9, 5fc02b4).
- **The workload** in the ports' form (`ndport/scripts/r1_workload.jl`): the plan's choices C2, C3 and C7. Each upstream call is tried first. Where it fails, the failure is printed, and a marked stand-in carries the step on. Passes `first`, `again`, `params`, `changed`, `graphtype`. The pass `usertype` does not exist yet (part 3b, R6).
- **The test subset** (`ndport/scripts/r1_nd_tests.jl`): massmatrix, doctor, diffusion, inhomogeneous, with the test files' `using OrdinaryDiffEq*` read as TDE. Stand-ins print `R1T STANDIN`.
- **The plotting side** (`ndport/env_r1plot`): GraphMakie 0.6.6 in a scratch worktree `ndport/pkgs/GraphMakie-r1` (branch `r1-scratch`), with `Makie` replaced by MakieCompat. Three scripts: the names GraphMakie uses against MakieCompat (`r1_gm_names.jl`, `r1_gm_check.jl`); the workload's two `graphplot` calls (`r1_gm_run.jl`); the workload's other plotting calls against TraitMakie's API (`r1_plot_probe.jl`).
- Logs: `ndport/logs/r1/` (ndport 0c0ab07, 748567a, 3410af6). Strict mode on gives the same lines and refuses nothing (`run-strict-1.log`).

## 2. How far NetworkDynamics runs

**SciML side.** NetworkDynamics loads on the ports with stubs for the 32 upstream names it still uses. Steps a, b, c, d and e run in every pass, with stand-ins where marked:
- **The network is a TDE problem's function** (the plan's S1): `ODEProblem(nw, u0, tspan, p)` takes the network as it is. Tsit5 and Rodas5 solve it; Rodas5's Jacobian calls the network at ForwardDiff's duals.
- **The cascade is upstream's.** With one TDE `ContinuousCallback` per component callback (the per-component form, S5), Tsit5 trips the same 16 lines in the same order as upstream, at the same times to four digits (`changed`: the same 15). So the vector condition is not needed for results.
- `jacobian_eigenvals`, `isfixpoint` and the observed edge outputs run unchanged (S9).
- What does not run: `find_fixpoint` (stand-in: relaxation by Rodas5); Rodas5 with continuous callbacks; the solution's indexed and interpolated forms, `NWState(sol, t)` and `SII.getu(sol, …)` (stand-in: values at the `saveat` times through NetworkDynamics' own `NWState`); step g's integrator (`init`, `step!`): no stand-in.
- The run log of one session: `logs/r1/run-4.log` (52 failures listed, all of the kinds in §3).

**Plotting side.** GraphMakie over MakieCompat loads only with stand-ins (15 loads, `gm-load-*`). `graphplot` then runs through the recipe's compute graph and the edge plot's `lines!` leaf, and stops at its first `scatter!` leaf (`logs/r1/gm-run-9.log`). No PNG of step f or g is drawn.

## 3. The items, ordered by what they unblock

Repo: where the item belongs. Size: a rough estimate of the work. W-83: whether unification (abstract types as traits) would make the item obsolete. None of the items is a workaround that W-83 would remove; the cases for W-83 are in §5.

| # | Item | Found by | Repo | Size | Unblocks | W-83 | R2 | Status |
|---|---|---|---|---|---|---|---|---|
| 1 | **Rodas5 with continuous callbacks:** "continuous callbacks: Tsit5 only" (`rodas5.jl:222`). Event location by bisection on Rodas5's interpolant, as Tsit5 does | `run-4` d | TDE (TraitRodas) | ½ day | step d's Rodas5 solve, all passes; no stand-in | no | **done** (TDE ede32e3, E-239) |
| 2 | **The integrator in user code** (S6): `init(prob, alg; kw)`, `step!(integ, dt, stop_at_tdt)`, the integrator's `u`, `t`, `p`. TDE has no public `init` | `run-4` g | TDE (ODECore, umbrella) | 1 day | step g, all passes; no stand-in | no | **done** (TDE ede32e3, E-239): `init`, `step!`, `solve!`; `ODEStepper` |
| 3 | **MakieCompat's namespace for a third-party recipe:** `@recipe`, `Plot`, `plot!`, `Lines`, `lines!`, `Attributes` are not exported. `@recipe` defines `argnames` and `documented_attributes` in the caller's module (`esc`), so a recipe outside MakieCompat gets functions of its own that MakieCompat does not read ("has no input or node :graph") | `gm-load-5`–`7`, `gm-run-5`, `8` | MakieCompat | ⅛ day | GraphMakie's load and recipe | no | — | done (E-240): the old API's names exported, the user API re-exported, `Makie` names MakieCompat; `@recipe` defines its methods in MakieCompat |
| 4 | **The compute graph on `p.attributes`** (ComputePipeline's author API as Makie 0.24 has it): `map!(f, p.attributes, ins, out)`, `add_input!`, `add_constant!`, `map!` with several outputs, `p[:name]`, `Computed`. MakieCompat has `map!(f, p, ins, out)` and `p.name` only | `gm-run-2`–`6` | MakieCompat | ½ day | GraphMakie's recipe | no | — | done (E-240) |
| 5 | **The do-block `@recipe(Name, args) do scene … Attributes(…) end`** with a theme function, and `default_theme(scene, PlotType)` (GraphPlot's defaults come from `Scatter`'s, `LineSegments`' and `Text`'s themes) | `gm-load-4`, `gm-run-1` | MakieCompat | ½ day | GraphMakie's load | no | — | done (E-240): `default_theme` per plot type; a do-block theme's values as `Observable`s, as upstream's |
| 6 | **GeometryBasics' points:** MakieCompat defines its own `Point2`, which clashes with GeometryBasics' (NetworkLayout returns and re-exports those; the load stops with an ambiguous `Point2`). TraitMakie's `Positions` takes no vector of points (`scatter!(ax, ::Vector{Point{2, Float64}})`: `MethodError`) | `gm-load-1`, `plot-probe-1` | MakieCompat, TraitMakie | ¼ day | GraphMakie's load; NetworkLayout's layouts | case (§5) | — | done (E-240): GeometryBasics' types in MakieCompat; `Positions` for any vector of 2-vectors (PlotCore) |
| 7 | **Old-API leaves beyond `lines!`:** `scatter!` (marker, markersize, color, colormap, colorrange, strokewidth, rotation, markerspace, visible), `linesegments!`, `text!`. GraphMakie's arrow and node plots are `scatter!` children | `gm-run-9` | MakieCompat (on item 8) | 1 day | step f and g's graph plots | no | — | done (E-240); not on the ports: glyph and polygon markers, marker rotation, a text leaf's offset |
| 8 | **Per-point colour by number in the core:** `color = numbers` with `colormap` and `colorrange` for `Scatter` and `Lines`, a colour vector per point (`ColorSpec` is one colour) | `plot-probe-1` | TraitMakie (PlotCore) | 1 day | step f's node and edge colours, g's node colours | no | — | done (E-240): a `Colormap` trait and `MappedColors` (PlotCore); `Lines` with a colour per point |
| 9 | **Observables in the core API:** `lines!(ax, ::Observable)`, `scatter!(…; color = ::Observable)`, `lift`. MakieCompat follows an `Observable` only inside old recipes; Observables' `map` and `on` work | `plot-probe-1` | TraitMakie, MakieCompat | ½–1 day | step g's live figure | no | — | done (E-240): `lift`; an `Observable` in the user API mirrored into the core's `Live` (MakieCompat) |
| 10 | `hidedecorations!`, `limits!`; `graphplot(…)` returning `(fig, ax, plot)` (MakieCompat's returns the figure); `Lines`' attributes `linestyle`, `colormap`, `colorrange` | `plot-probe-1`, `gm-run-7` | TraitMakie, MakieCompat | ¼ day | steps f and g | no | — | done (E-240); a linestyle other than solid refused |
| 11 | **Nonlinear problems with an open set of solvers** (S8): `find_fixpoint` builds a `SteadyStateProblem` (NonlinearSolve's polyalgorithm, a sparse Jacobian prototype when the network has one) | `run-4` c | TDE (a new package beside TraitNLSolvers) | 1–2 days | step c, all passes (stand-in: relaxation by Rodas5 gives the same cascade) | case (§5) | design note: [plans/2026-10-29-tde-nonlinear-problems.md](2026-10-29-tde-nonlinear-problems.md); not built |
| 12 | **The system object back** from a problem, a solution, an integrator (SciML's `prob.f`, `sol.prob.f.sys`, `integ.f.sys`): NetworkDynamics' `extract_nw` behind `NWState(sol, t)`, `NWState(integ)`, `SII.getu(sol, …)`, callbacks' context, and the tests' `prob.f.f`. `ODEFunction(nw; sys = nw)` is refused (`TraitBoundError`: `IndexProvider` names are `Symbol`s), and a `Dynamic{IndexProvider}` gives no way back to the network | `run-4` e, `ndtest-2` | TDE (ODECore), with open issue 118 | ½ day | step e's upstream forms, g's `NWState(integ)` | no | **done** (TDE ede32e3, ND 756c09e): `getsystem`, `HasSystem`; `extract_nw(sol)`, `NWState(sol, t)`, `NWState(integ)`; not a callback's view (E-239) |
| 13 | **Parameters changed by callbacks, saved** (SciML's `save_discretes!`; NetworkDynamics' `save_parameters!`): the solution keeps no parameter series, so `NWState(sol, 3.0)` cannot give the line constants `K` at t = 3 (step e's `K3`). Stand-in: a no-op | `run-4` d, e | TDE (ODECore) | ½ day | step e's `K3`; `NWState(sol, t)` | no | **done** (TDE ede32e3): `save_discretes!`, `parameters_at` |
| 14 | **Callbacks a problem keeps** (SciML's `ODEProblem(…; callback)`, which `solve` picks up). NetworkDynamics' `ODEProblem(nw, …)` attaches the network's callbacks; TDE's problem keeps none, so the user passes `callback = get_callbacks(nw)` to `solve` | `run-1` d | TDE (ODECore) | ¼ day | the workload's API as upstream's | no | **done** (TDE ede32e3) |
| 15 | **Times to stop at, per solve:** a `tstops` option, or a callback's initialization at each solve (DiffEqCallbacks' `PresetTimeCallback` adds its times at `initialize`). TDE has `add_tstop!` from inside a callback only. The stand-in adds them at the condition's first call; it keeps state, so callbacks must be rebuilt for each solve | `run-3` d | TDE (ODECore) | ¼ day | step d's preset trip, callbacks reused across solves | no | **done** (TDE ede32e3): `tstops`, callbacks' `initialize` |
| 16 | `auto_dt_reset!` after a callback changes `u` or `p` (stand-in: `u_modified = true`); the crossing's sign for `affect!` against `affect_neg!` (TDE's `EventCallback` has one affect) | `run-2` d | TDE (ODECore) | ¼ day | fidelity of the cascade; `ContinuousComponentCallback` with a separate `affect_neg` | no | **done** (TDE ede32e3): `auto_dt_reset!`; `ContinuousCallback(cond, affect!, affect_neg!)` |
| 17 | `ODEFunction` callable (SciML's is); `Rodas4`; `copy(prob.p)` with no parameters (TDE: `nothing`) | `ndtest-1`–`3` | TDE | ¼ day | the test subset | no | part (TDE ede32e3): `ODEFunction` callable; `Rodas4` and `copy` of absent parameters not done |
| 18 | A vector condition (`VectorContinuousCallback`): not needed for results (item 1 of §2). Each of the 40 per-component callbacks evaluates the whole batch's observed outputs, so the cost grows with the square of the callbacks. A suspicion, not measured: taken up only if R7's round shows it | `run-2` d | TDE | — | — | no | — |

**NetworkDynamics' own items** (R3, this port; not TDE's):
- the problem from a network (done for the census: `ODECore.ODEProblem(nw, s0::NWState, tspan)`);
- the callbacks in TDE's form (`get_callbacks_ports` for the census) and the network passed to a callback's context by its wrapper (done);
- the mass matrix passed on: `ODEProblem(ODEFunction(nw; mass_matrix = nw.mass_matrix), …)` is accepted for tier S's identity, so TDE refuses a DAE instead of solving it as an ODE (§4, C);
- the SciMLBase hooks (`__has_sys`, `create_parameter_timeseries_collection`, …) removed.

## 4. NetworkDynamics' test subset on the ports

`logs/r1/ndtest-4.log` (stand-ins on) against E-166's subset (`logs/p4s3/ndtest-s3.log`). Without stand-ins (`ndtest-1.log`), diffusion and inhomogeneous stop at their first solve (an error each, no test run).

| File | Ports | E-166 | The difference, by gap |
|---|---|---|---|
| massmatrix | 6 pass | 6 pass | none |
| doctor | 26 pass | 26 pass | none |
| diffusion | 110 pass, 2 fail, 24 broken | 111, 1, 24 | `:129` **fails: a network with a mass matrix, passed to `ODEProblem` as the function, is solved as if it had none** (error 1.6 against 1e-6). Item C (§5). `:111` (allocations) fails as in E-166. Stand-ins: item 17 (callable `ODEFunction`), item 12 (`prob.f.f`), candidate D (a closure returning its array) |
| inhomogeneous | 43 pass, 2 fail, 12 broken | 43, 2, 12 | the same counts; `:59` and `:93` (allocations) as in E-166. Stand-ins: item 17 (`Rodas4` as Rodas5), item 12 (`NWState(sol, u)`), open issue 118 (`sol(t; idxs)`) |

## 5. Candidate open issues and cases for W-83

**Confirmed by running:**
- **A (open issue 117), dense output:** `sol(TIMES; idxs = …)` fails; values at `TIMES` by `saveat` stand in (C3).
- **B (open issue 118), structured indices:** `sol(t; idxs = VIndex(…))`, `SII.getu(sol, …)` fail. Running adds a case: a library needs its own system object back from the solution and the integrator (item 12). `IndexProvider` refuses the network (`Symbol` names), and a kept `Dynamic{IndexProvider}` gives no way back to it.

**New:**
- **C. Optional properties of a problem's function.**
  - Case: diffusion_test `:129`. A network with a mass matrix enters TDE's `ODEProblem` as the function and is solved as an ODE: a wrong result, no error. SciML reads the function's optional properties by duck typing (`__has_mass_matrix(f)`, `__has_sys`, `__has_jac_prototype`); NetworkDynamics implements those hooks.
  - The rule: TDE's front end takes a mass matrix, a system and a Jacobian only from an `ODEFunction` record; a callable is a `Callable` at the right-hand side's signature, and nothing else of it is seen.
  - Proposal: optional traits of the function's type (a mass matrix, a system, a Jacobian prototype) that the front end checks at the problem's construction, and a refusal where a property is present that the solver cannot take. Until then NetworkDynamics passes its mass matrix in an `ODEFunction` (§3).
- **D. In-place functions whose result is discarded.**
  - Case: diffusion_test's `ODEFunction((dx, x, p, t) -> dx .= -L * x)` returns the array. SciML ignores an in-place function's result; TDE enters the function at `Callable{…, Nothing}` and the result's check fails (`TypeError` in TraitWorld's call wrapper).
  - The rule: every call of a `Callable` is checked, and a result of another type than the declared one is a `TypeError` ([traits §5.8](../reference/traits.md#58-callable-functions-at-a-declared-signature)).
  - Proposal: the in-place signatures declare no result to check (a result the caller discards), or TDE's front end documents `nothing` as the contract and refuses with a message that names it. The second is the simplest; the first needs the design's word on a discarded result.

**Cases for W-83** (listed, nothing built around them):
- **SciML's abstract dispatch types in NetworkDynamics:** `NWState(int::DEIntegrator)`, `NWState(sol::AbstractODESolution, t)`, `extract_nw(::AbstractSolution)`. On the ports these become methods bounded by `IntegratorView` and `Trajectory`. With abstract types as traits, the signatures could stay.
- **Nonlinear problems (item 11):** a `NonlinearProblemTrait` beside SciML's `AbstractNonlinearProblem` and `SteadyStateProblem`, the same case as `ODEProblemTrait` beside `AbstractODEProblem`.
- **Points (item 6):** GeometryBasics' `Point <: StaticVector <: AbstractVector`. `Positions` for a vector of points would be one implementation for `AbstractVector{<:AbstractVector{<:Real}}` if abstract types were traits.

## 6. Choices (mine, 2026-10-29)

- **R1-a.** SymbolicIndexingInterface stays NetworkDynamics' plain dependency in setting PT. NetworkDynamics' own indexing uses its generic functions (about 150 lines), and it brings no solver. Whether TraitIndexing replaces it waits for open issue 118 (C7).
- **R1-b.** The census stands in for `find_fixpoint` by a relaxation (Rodas5 over (0, 400) from zero). It ends at the same fixed point for the workload's purposes: the cascade that follows is upstream's.
- **R1-c.** GraphMakie's interaction file (hover, drag, `pick`, events) is left out of the scratch branch: it is for interactive backends, outside tier S.
- **R1-d.** The plotting census stops at the first old-API leaf beyond `lines!` (item 7). Past it, stand-ins would be the TraitMakie items themselves (R2).
