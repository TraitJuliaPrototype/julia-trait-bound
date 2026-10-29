# Nonlinear problems with an open set of solvers in TDE (W-32 R2, census item 11)

Status: **adopted** (2026-10-29, mine: built by the agent of W-32's steps R3–R5, E-242; the amendments from building are in §7). Not normative: the references hold. Written by the agent of W-32's step R2 (E-239), in the spirit of [the R1 census](2026-10-29-ndport-r1-census.md). The choices marked "mine" are for the main session to confirm.

## 1. The case

- **NetworkDynamics' `find_fixpoint`** (`src/initialization.jl:82`) wraps the network at a fixed time (`NetworkFixedT`, which keeps `sys` and `jac_prototype` by SciML's duck-typed hooks) and solves `SteadyStateProblem(nw_fixed_t, x0, p)` with `SSRootfind()` (NonlinearSolve's default polyalgorithm), or, when the network has a sparsity pattern, `FastShortcutNonlinearPolyalg(; must_use_jacobian = Val(true))`. It reads `sol.u`, `sol.resid`, `sol.retcode` and `SciMLBase.successful_retcode`; a `Stalled` solve with a small residual is accepted.
- **NetworkDynamics' component initialization** (`initialize_component`, `initialization.jl:600–670`) builds a `NonlinearLeastSquaresProblem` from a `NonlinearFunction` and solves it with `FastShortcutNLLSPolyalg` (QR inside); a DAE's consistent initialization (`BrownFullBasicInit`) is a nonlinear solve too.
- Tier S needs only the first: step c of every pass. The census stands in for it by relaxation (Rodas5 over (0, 400) from zero); the cascade that follows is upstream's.

## 2. SciML's architecture, the parts that matter

- **Problems** (SciMLBase): `NonlinearProblem(f, u0, p)` with `f(du, u, p)`; `SteadyStateProblem(f, u0, p)` with an ODE right-hand side `f(du, u, p, t)` at `t = Inf`; `NonlinearLeastSquaresProblem` (a residual of another length than the state). The function record `NonlinearFunction(f; jac, jac_prototype, sys)`.
- **Solvers, an open set** (NonlinearSolve and its sub-packages): Newton–Raphson, trust region, Levenberg–Marquardt, Broyden, Klement, and polyalgorithms that try several in turn. Each takes a linear solver (LinearSolve's open set) and a way to get the Jacobian (automatic differentiation, sparse with colouring from `jac_prototype`).
- **SteadyStateDiffEq** turns a steady-state problem into a nonlinear one (`SSRootfind`) or integrates to the steady state (`DynamicSS`).
- **One front end:** `solve(prob, alg)` for every kind of problem and algorithm.

## 3. The trait form

By [the exploration's principles](../explorations/sciml-as-traits.md#3-the-principles-for-the-design-as-it-stands): traits for the open sets, types for the library's own enumerations; capabilities per type; the parameters' type in the outer layer (W-63).

- **`NonlinearProblemTrait{T, P}`:** declared fields `u0::Vector{T}`, `p::P`; operations `residual!(prob, r::Vector{T}, u::Vector{T})::Nothing` and `nl_jacobian!(prob, J::Matrix{T}, u::Vector{T})::Nothing`, with the default by the library's duals (the core's `_ad_jacobian!` at a signature without `t`). A problem type of the user's implements it, as `ODEProblemTrait` today.
- **TDE's `NonlinearProblem{T, P, F, J}`,** the canonical implementation, from `NonlinearProblem(f, u0, p)` or `NonlinearProblem(NonlinearFunction(f; jac, jac_prototype, sys), u0, p)`: the function partially evaluated on the parameters and kept at a parameter bounded by `Callable{Tuple{Vector{T}, Vector{T}}, Nothing}` (traits §7.4), so the solvers compile once per state type, whatever the function and the parameters. The function's optional properties are read at the front end through the traits R2 built for open issue 119 (`HasSystem`, `HasJacobianPrototype`), so `NetworkFixedT` declares them instead of SciML's hooks.
- **`SteadyStateProblem(f, u0, p; t = Inf)`:** a nonlinear problem from an ODE right-hand side at a fixed time; also `SteadyStateProblem(prob::ODEProblemTrait)`. It forwards `residual!` to the right-hand side.
- **`NonlinearAlgorithm`, an open set:** `solve_nl(a, m, opts)::NLCoreSolution`, on the core's problem (the parameters partially evaluated). TDE's package implements `NewtonRaphson(; linsolve, linesearch)` and a trust region; both take any `LinearSolver` (stage C's open set) and reuse `newton_stage!`'s pattern. A polyalgorithm is an algorithm whose members are kept values (`Vector{Kept{NonlinearAlgorithm}}`): its type has no axis for its members, as the integrator has none for its callbacks.
- **The solution:** `u`, `resid`, `retcode` (`:Success`, `:MaxIters`, `:Stalled`), `stats`, the problem kept (`Kept{NonlinearProblemTrait{T, P}}`), the system object (`HasSystem`); `successful_retcode`.
- **The front end:** the umbrella's `solve(prob, alg)` selects by the algorithm's trait: `ODEAlgorithm` to `solve_ode`, `NonlinearAlgorithm` to `solve_nl` (two bounded methods of one internal function; an algorithm of both traits would need a joint method, traits §5.5). `solve(prob)` without an algorithm by the problem's trait.
- **A new package beside TraitNLSolvers** (`lib/TraitNonlinearSolve`): the problem trait, the record, the algorithm trait, Newton–Raphson and the trust region. NetworkDynamics depends on it for step c.

## 4. What NetworkDynamics would change

- `NetworkFixedT` implements `HasSystem` and `HasJacobianPrototype` (as `Network` does since R2); the hooks `SciMLBase.__has_sys`, `__has_jac_prototype` and its `getproperty` switch go.
- `find_fixpoint` builds TDE's `SteadyStateProblem(nw_fixed_t, x0, p)` and solves it with `NewtonRaphson()` by default (tier S: 40 states, dense); the stand-in leaves the workload.
- `initialize_component` (least squares) stays on its stubs until a second step.

## 5. Open questions for the main session

1. **Where the shared pieces live.** The optional traits (`HasSystem`, `HasMassMatrix`, `HasJacobianPrototype`), the library's dual tag and `LinearSolver` are ODECore's today. The nonlinear package can depend on ODECore (SciMLBase holds every problem type), or the shared pieces move to a base package below both. Proposal (mine): depend on ODECore for the first step; move them when a third problem kind needs them.
2. **Sparse Jacobians.** `HasJacobianPrototype` is read but no solver uses it: `LinearSolver.linfactor` takes `Matrix{Float64}`. A sparse path needs the linear solver's matrix type as an axis (`linfactor(ls, W::SparseMatrixCSC)`), and sparse differentiation by colouring. Not needed for tier S; needed for NetworkDynamics' large networks.
3. **Least-squares problems** (`initialize_component`, a DAE's initialization): in the first step or later. Proposal (mine): later, with mass matrices, which need consistent initialization anyway.

## 6. Size, and cases for W-83

- About 1–2 days: the problem trait, the record and the front end (½ day); Newton–Raphson with a line search and a trust region (½ day); the polyalgorithm (¼ day); tests and NetworkDynamics' step c (½ day).
- **W-83:** `NonlinearProblemTrait` beside SciML's `AbstractNonlinearProblem` and `SteadyStateProblem` (the census §5); `NonlinearAlgorithm` beside `AbstractNonlinearAlgorithm`.

## 7. Amendments from building (E-242, 2026-10-29, mine)

Built in TDE `w34` e4eeed9 and 388cb33 (`lib/TraitNonlinearSolve`, `test/nonlinear.jl`); NetworkDynamics' `find_fixpoint` on it (branch `ports` e0f5664). Where building changed §3:
- **The trait's default Jacobian is by finite differences,** not by the library's duals: a trait default sees the residual only at `Vector{T}`. TDE's record differentiates by the duals, as `ODEProblemTrait`'s default and TDE's `ODEProblem` do.
- **`SteadyStateProblem` is a constructor of `NonlinearProblem`,** not a record of its own: the residual is the right-hand side at the time, partially evaluated. From any `ODEProblemTrait` it takes `rhs!` and `jacobian!` at the time.
- **The front end** is TraitNonlinearSolve's own `solve`, not exported. The umbrella's `solve` forwards a `NonlinearAlgorithm`, and `solve(prob)` a `NonlinearProblemTrait`, chosen by trait dispatch (`is_nonlinear_algorithm`, `is_nonlinear_problem`: bounded methods with an untyped fallback). Not by `conforms`: a caller that infers `solve` then infers TraitWorld's membership lookup (E-242: 0.43 s in E-168's session). NetworkDynamics calls `TraitNonlinearSolve.solve`. One `solve` shared by packages that do not know each other is CommonSolve's role, which lowering L-3 blocks (W-36): a case for the main session.
- **Newton–Raphson's line search** is a flag (the step halved under Armijo's condition on `‖r‖²`), not an open set of line searches.
- **Return codes:** `:Success`, `:MaxIters`, `:Stalled` (no progress possible, the residual above `abstol`), `:ConvergenceFailure` (a singular Jacobian). Defaults `abstol = reltol = eps()^(4/5)`, NonlinearSolve's.
- **The default polyalgorithm** is Newton, Newton with the line search, then the trust region. NetworkDynamics' `default_fixpoint_alg` returns it with or without a sparsity pattern: the solvers take dense Jacobians (§5, question 2, unchanged).
- The polyalgorithm's constructor takes its members as a plain vararg: `@nospecialize` on a vararg is refused (lowering L-46).
- Not built: least-squares problems (§5, question 3), sparse Jacobians (§5, question 2).
