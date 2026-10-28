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
