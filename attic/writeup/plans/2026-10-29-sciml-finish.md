# Finishing the SciML port: move 5 and the workload on the split packages

Status: **done** (2026-10-29; adopted the same day, mine; W-34; results: E-229, E-230 in the registry). Not normative. W-34's finish line (the user, 2026-10-29: "I agree with your finish lines"): move 5 (the solution as a trajectory) and the workload on the split packages, with no reads of TraitWorld's internals. The last part is done (TDE 98c7e2a, 44b4d14). Experiments E-229 and E-230.

## 1. Where TDE is

- Branch `w34` at 44b4d14. The umbrella `TraitDifferentialEquations` over packages of their own in `lib/`: the core (`ODECore`: problems, Tsit5, the traits of algorithms, callbacks, linear and nonlinear solvers), `TraitRodas`, `TraitLinSolvers`, `TraitNLSolvers`, `TraitImplicit`, `TraitIndexing` (SymbolicIndexingInterface's stand-in).
- `Trajectory{U, T}` (`times`, `state`, `at`) is declared in the core; `ODESolution{T, P}` conforms. A helper over it is compiled once per key (E-157, check 6).
- The solution keeps its problem's parameters and names (move 4), not its problem. The solvers build `ODESolution{T}` without parameters; the outer layer adds them (`with_problem`, W-63).
- E-168's session (setting D) ran on TDE 669cd9b, before the split (move 3).

## 2. Move 5: what it builds

The exploration's move 5 (`explorations/sciml-as-traits.md` §4): `Trajectory{U, T}`; `ODESolution` and `DiffEqArray` conform; the solution keeps its problem as a kept value, so its type has no axis for the function.

- **`lib/TraitArrayTools`, RecursiveArrayTools' stand-in:** it owns `Trajectory{U, T}`, `DiffEqArray` (states at times, interpolated linearly) and `plotpoints(s::Trajectory, i)::Matrix{Float64}`, the points `(t, u[i])` a plotting library takes. In SciML, `DiffEqArray` and the plot recipes of solutions sit in RecursiveArrayTools, below SciMLBase. So code over trajectories, a plotting package's included, needs no solver. The core depends on it and implements `Trajectory` for its solution.
- **The solver's result and the user's solution are two types.** A solver returns the core's `CoreSolution{T}` (times, states, return code, counts). It has no problem, because the core never sees the parameters (W-63). The outer layer makes `ODESolution{T, P}` from it: the same data, the problem kept as `prob::Kept{ODEProblemTrait{T, P}}`, and the names. `with_problem` is a bounded function on the problem.
- **`sol.prob`** reads the problem's declared fields (`u0`, `tspan`, `p`) and calls its operations. `sol(τ)` is `at(sol, τ)`, plain sugar on the concrete type.
- **The solver packages return `CoreSolution`** (TraitRodas, TraitImplicit): the core's API for solvers changes by one name.
- **The plotting in the workload goes through `Trajectory`:** `lines(plotpoints(sol, i))` in place of vectors built from `state` in the script.

## 3. The workload on the split packages

E-168's session in setting D, on the umbrella as it is now: load, a non-stiff solve (Lorenz, Tsit5) and a stiff one (Robertson, Rodas5), a PNG of both, a second model (Van der Pol, Rodas5) solved and plotted, both again.
- What changes against E-168: the solvers come from the split packages (the core, Rodas5, the indexing and array-tools packages as packages of their own); the plots take `plotpoints` of the solutions; TraitWorld c39fedc and julia-1.13 bfca89decc; TraitMakie as it stands (80a16fc).
- The harness is E-168's (`experiments/ttfx/run.sh`): a discarded warm-up and two sessions per setting, two cores, niced, through the shared lock. `env_d` re-resolved for the split packages.
- Settings: D; and as same-day controls, Python, Dp (the plain twins, which did not change) and D/p (the perturbed shapes). Minutes, not a benchmark campaign.

## 4. The checks

**E-229 (move 5):**
1. TDE's session (`scripts/session.jl trait`): the 9 `RESULT` lines identical to `experiments/w81/x1/session-x1-one-function.log`.
2. TDE's `Pkg.test()` passes (the product setting, stock image).
3. One solution type for a plain function, the same under `compiled_for`, a callable model, a problem type of the user's, and Tsit5 and Rodas5.
4. `sol.prob`'s declared fields equal the problem's; its `rhs!` gives the problem's derivative.
5. `DiffEqArray` conforms; `plotpoints` of a solution equals that of a `DiffEqArray` of its states.
6. `plotpoints` compiled once per solution type, not per model or solver; once for every trajectory as `Dynamic{Trajectory}`.

**Would change the design:** a solution that cannot keep its problem without an axis for its function or its type; a helper over trajectories compiled per model.

**E-230 (the workload):** the session's steps and total in D, against E-168 (D 0.94–0.99 s after TraitWorld 04095fe; Python 1.45 s) and the same-day controls. **Would change the plan:** D's session more than about 0.1 s above E-168's on the split packages, or above Python's. Then the split costs at load (more packages and images), which phase 2 of the plan takes up (W-7).

## 5. Out

- **Dense interpolation.** `at` stays linear between the saved states. Keeping a solver's interpolant in the solution, as a kept value, is the next step for `sol(τ)` to match SciML's.
- **`remake`, ensembles, `sol[i, :]` indexing, plotting by name.** Not on the workload's path.
- **A view of a trajectory that conforms to TraitMakie's `Positions` without a copy.** It belongs in a package extension of TDE (or TraitMakie). `plotpoints` copies 2 × n numbers, which the workload does not notice.

## 6. Cases for W-83 (unification)

- `Trajectory` stands beside SciML's tree `AbstractDiffEqArray` (RecursiveArrayTools) and `AbstractTimeseriesSolution` (SciMLBase). With abstract types as traits, the abstract type would be the trait. TraitArrayTools is that type's owner, so the placement holds either way.
- `ODEProblemTrait` beside `AbstractODEProblem` (already listed with move 1).
