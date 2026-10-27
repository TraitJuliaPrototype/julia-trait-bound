# The parameters in the outermost layer only

Status: **proposal** (2026-10-27, mine, after the user's direction; W-63). Not normative. Built first in TraitDifferentialEquations (branch `partial-p`), measured as E-181.

Serves: [W-63](../record/todo.md); W-60's memo (its pushback 2, its experiment X6); [open issue 72](../open-issues.md#2-design) (the cache recurs only where keys recur).

## 1. The direction

The user (2026-10-27): "The outermost layer has to depend on parameter type, but inside the solver we only need to see the right hand side that is partially evaluated on the parameters. This way we can keep the part that depends on parameter type very lean." Recorded in the [decision log](../record/decisions.md) §8.

Today the parameters' type `P` is a key of the whole solver (E-168: a new parameter type compiles TDE's solver again, +1.35 s; E-178: no cache recurs across it). It enters the solver in four places:
- the problem trait: `ODEProblemTrait{T, P}`, with `@const p::P`;
- the functions' signatures: `RHSSig{P, T} = Tuple{Vector{T}, Vector{T}, P, Float64}`, and the dual and Jacobian signatures;
- the integrators (`Tsit5Integrator{T, P}`, `Rodas5Integrator{P, …}`, `DualJacobian{P, …}`);
- the callbacks' view of the integrator, `IntegratorView{U, T, P}`, where a callback reads `integ.p` at its type.

## 2. The shape

**Two layers.**
- **The outer layer, keyed on `P`:** `solve`'s entry. It holds the user's problem and parameters. It makes the solver's problem by partial evaluation, and adapts the callbacks. Its code is small: a few constructors and closures per parameter type.
- **The solver core, keyed on the state's element type `T` (and the problem type, where a problem implements the trait itself):** it never sees `P`.

**The right-hand side, partially evaluated.** The outer layer makes `PartialRHS(f, p)`, a callable record with `(du, u, t) -> f(du, u, p, t)`. The core keeps it at `Callable{Tuple{Vector{T}, Vector{T}, Float64}, Nothing}`, by the function's attribute as today: a `Dynamic` callable by default, so the core is compiled once per `T`; under `compiled_for(f)`, the record itself, so the core is compiled for it. The same for the duals' signature, the given Jacobian, and the function Rodas5 enters at its own chunk (`rhs_function`). One dynamic call per evaluation, as today: the parameters move from an argument into the record.

**The callbacks.** A callback still reads `integ.p` at the parameters' type. The core's view is `IntegratorView{U, T}`, without `p`. The outer layer enters each user callback at the core's signature with a closure that hands the user's function a `ParamIntegrator{U, T, P}`: the core's view and `p`, reading and writing through to the view. The user's functions are compiled at `ParamIntegrator{U, T, P}`, a concrete type; the core calls the closures dynamically, as today.
- **A callback writes the parameters' contents** (`i.p[1] = 12.0`): the record and the closures share the same `p`, so the right-hand side sees it.
- **A callback replaces the parameters** (`i.p = q`): not supported, as today (`p` is a `@const` field of the view).
- **A callback type** that implements `Callback{U, T, P}` keeps its declaration; the outer layer adapts it the same way.

**A problem type of the user's own** (`@implement ODEProblemTrait{T} MyProblem`): the core is compiled for that type, as any receiver type is. Its parameters are its own business; its callbacks see `integ.p` if the type has a field `p`.

**What it needs from the design:** nothing new. `Callable` keeps a function at a signature (traits §7.4); a record that closes over the parameters is a plain callable. No checked downcast is needed (open issue §2 item 16): the parameters never cross into the core, so they never come back out.

## 3. What it costs, and what it buys

- **Buys:** the core's code recurs across parameter types, so a cache recorded with one parameter type serves another; a parameter struct defined in the user's script compiles only the outer layer and the user's own functions.
- **Costs:** a closure per function and per callback, compiled per `P` (small); the callbacks' view one indirection further (a `ParamIntegrator` around a `Dynamic` view).
- **Unchanged:** the dynamic call per evaluation of the right-hand side (today's `Dynamic{Callable{…}}` call), the solver's steady state.

## 4. The experiment (E-181, minutes)

TDE on branch `partial-p` against `w34`, setting D:
1. **Recurrence:** a cache (E-180's mechanism) recorded from a session with `Vector{Float64}` parameters; sessions with a `Tuple`, a `NamedTuple` and a struct defined in `Main`. The first solve's compile time, against `w34`.
2. **Steady state:** the workload's solves (Lorenz with Tsit5, Robertson with Rodas5), against `w34`.
3. **Callbacks:** `integ.p` inferred at the parameters' type (the test of `w34_move2.jl`); a write to `p`'s contents reaching the solve.
4. TDE's suite.

**Would change the direction:** a steady state measurably slower than `w34`, or an outer layer whose compilation per new `P` is a large share of the solver's.
