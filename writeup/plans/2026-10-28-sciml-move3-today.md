# SciML move 3 on today's TraitDifferentialEquations: the solvers as an open set

Status: **adopted** (2026-10-28, mine; W-34, E-159). Not normative. It adapts [the W-34 plan](2026-10-21-w34-sciml-prerequisites.md) §1.4 and §2.4 (written 2026-10-21) to TraitDifferentialEquations as it is on branch `w34` (59571a2). The user (2026-10-28): "Go for it and continue with the other ports afterwards."

## 1. Where TDE is

- The solver cores are typed methods of ODECore's own function: `core_solve(m::CoreProblem, ::Tsit5, …)` and `core_solve(m::CoreProblem, ::Rodas5, …)`.
- The entries are closed: `solve_ode(prob, alg::Union{Tsit5, Rodas5}, …)` in the core, and `solve(prob, alg::Union{Tsit5, Rodas5})` in the ordinary layer.
- Rodas5's code (its Jacobian by duals, its integrator, `StepView` for it, its step, interpolant and driver) lives in `ODECore.jl` beside Tsit5's.

## 2. The move

- **`ODEAlgorithm`, a trait of the core,** with one operation, the solver's own driver: `solve_core(a::ODEAlgorithm, m::CoreProblem, callbacks::Vector{Any}, opts::SolverOptions)::ODESolution`. Bounded code then hands the core's problem to any algorithm through an operation. It never passes a trait object bare to plain code (traits §5.3).
- **`solve_ode(prob, alg::ODEAlgorithm, …)` and the umbrella's `solve(prob, alg)`** take any implementing algorithm.
- **Tsit5 stays in the core,** implementing `ODEAlgorithm` there.
- **Rodas5 moves to `examples/TraitRodas`,** a package of its own. It owns `Rodas5`, its integrator and its Jacobian type, and implements `ODEAlgorithm` and `StepView` for them. No edit in the core is made for it.
- **What the package imports from the core is the solver API:** the traits, `CoreProblem` and its calls (`core_rhs!`, the Jacobian's entry), the step-callback machinery, the tstop helpers, `ODESolution`, `SolverOptions`. That list is itself a result: what a solver package needs from a core.
- **The negative control,** `examples/FrontEndElsewhere`: a package that defines the front end's body for the core's types on the stand-in's `solve`, as DiffEqBase does. Strict mode should report it.
- **The plain stand-in of CommonSolve,** `examples/MiniCommonSolve`, owns `solve`, `init` and `solve!`. The umbrella's methods on it are typed methods on the umbrella's own types (the §1.4 route); a bounded method on it by the core is L-3's case.

## 3. Checks (E-159, revised)

1. TDE's `RESULT` lines unchanged, Rodas5 included, from its own package.
2. Strict mode on, no `@joint_owners`: no pirate reported in `ODECore`, TDE, `TraitRodas` or the umbrella; the negative control's front-end methods reported.
3. An algorithm type that does not implement `ODEAlgorithm` met at `solve` by an error naming the bound.
4. The default algorithm, `solve(prob)` without an algorithm, by the umbrella's own method.
5. The Tsit5 steady state per step and Rodas5's first solve unchanged by the split (E-210's numbers).

**Would change the design:** a solver package that needs a rule the references refuse (a pirate, an implementation it may not declare), or a core whose API for solvers cannot be stated as traits and operations.

## 4. Stage C: the linear solver an open set inside the solver

The user (2026-10-28): "One note on Solvers. One of the especially important aspects in DE.jl is that it is possible to use various linear/nonlinear solvers within Rodas/etc..."

In DifferentialEquations.jl an implicit method takes a linear solver (`Rodas5(linsolve = KrylovJL_GMRES())`, any LinearSolve.jl algorithm) and, for the fully implicit methods, a nonlinear solver: open sets inside an open set. TDE's Rodas5 hard-codes dense LU.

- **`LinearSolver`, a trait of the core** (LinearSolve's interface in brief): `linfactor!(ls, W::Matrix{Float64})` keeps what the solve needs, `linsolve!(ls, x::Vector{Float64}, b::Vector{Float64})` solves with it. `DenseLU` implements it in the core.
- **`Rodas5{L}` keeps its linear solver** in a field whose parameter is bounded by `LinearSolver` (traits §7.4): `Rodas5(linsolve = DenseLU())`, `Dynamic` by default, `compiled_for` per solver.
- **A second linear solver in a package of its own** (`lib/TraitLinSolvers`: dense QR with column pivoting; an iteration would converge only for diagonally dominant systems, testing the iteration rather than the composition), and a user's own at the prompt: neither known to TraitRodas.

Checks (E-220): results with `DenseLU` identical to stage B's; the other solvers' results within their tolerance; TraitRodas unchanged when a linear solver is added; the solver code compiled once for every `Dynamic` linear solver, and per solver under `compiled_for`; the time per Rodas5 step against stage B's. **Would change the design:** a solver package that cannot take another package's linear solver without editing either, or a nested open set that compiles per combination where the attribute says it should not.

## 5. Stage D: nonlinear solvers taking linear solvers

The same note's second half. `NonlinearSolver` and `NLCache` in the core (the stage `x = z + γdt f(x, t)`, as OrdinaryDiffEq's NLsolve takes it) with `Newton{L <: LinearSolver}` as the default; `ImplicitEuler{N <: NonlinearSolver}`, a fully implicit method, in `lib/TraitImplicit`; a simplified Newton in `lib/TraitNLSolvers`. Checks (E-221): implicit Euler against its exact discrete solution for every combination; a stiff problem; what a new nonlinear solver and a new linear solver inside it compile under `Dynamic`.
