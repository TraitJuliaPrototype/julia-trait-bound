# Load and first-use time of a large trait world: SciML and Makie

Status: **adopted** (2026-10-27, mine, under the user's direction below). Not normative.

Serves: [W-58](../record/todo.md); E-168.

## 1. The goal

The user (2026-10-27): "I would like to get back to looking at load and TTFX times as a whole in a large port setting say (SciML+Makie). With a large solid trait core that is amenable to cross session caching, there should be no reason that loading+running first simulation+plot should be slow. We could take SciPy + matplotlib as a baseline for this, too. […] We need the porting strategy architecture for Makie. But I would now focus on things that directly contribute to this as a next step. Leave ND.jl out for now as it doesn't have a Python analogue."

So the measure is one fresh session, start to exit: load the solver and the plotting library, solve, plot to a file, then change the model and do it again. The baseline is the same session in Python.

## 2. The workload

One script per language, the same steps, the same numbers out:

1. **Load:** the solver and the plotting library.
2. **First simulation:** a non-stiff problem (Lorenz, an explicit Runge–Kutta method: `Tsit5`; SciPy `RK45`) and a stiff one (Robertson, a Rosenbrock method: `Rodas5P`; SciPy `Radau`), at the same tolerances, saving at fixed times.
3. **First plot:** the two solutions as lines on two axes, saved to a PNG (CairoMakie; matplotlib's Agg backend).
4. **A second model:** a new right-hand side (Van der Pol, stiff), solved and plotted again.
5. **Again:** steps 2–3 repeated, the steady state.
6. **Exit.**

The values at the saving times are printed as digests, and compared across settings to a tolerance (the methods differ between the languages).

## 3. The settings

- **Python:** SciPy and matplotlib, a fresh environment, versions recorded.
- **S:** stock Julia 1.13.2, upstream OrdinaryDiffEq (`OrdinaryDiffEqTsit5`, `OrdinaryDiffEqRosenbrock`) and CairoMakie, with their own precompile workloads.
- **U:** the same packages on the patched build, product setting.
- **A:** the same under `all`.
- **C:** the SciML core as it stands in the port (P6's trees: SciMLBase, DiffEqBase, OrdinaryDiffEq, RecursiveArrayTools, SymbolicIndexingInterface, NonlinearSolve wrapped inside out), upstream CairoMakie; without NetworkDynamics.

Later settings, when they exist: the SciML core written as idiomatic trait code; Makie ported by the architecture of §5.

## 4. What is measured

- **Per step:** wall time, and the part that compiles (`Base.cumulative_compile_time_ns`), the garbage collector's time.
- **Per step, attribution** (a separate run, not timed): the CodeInstances created, by owner (`:facts` or plain) and by package; for the load, `@time_imports`.
- **What the session loads:** package images loaded, rejected or compiled; time spent validating them.
- Runs: three fresh sessions per setting on a quiet machine, two cores (`taskset -c 0-1`), one Julia job at a time.

## 5. The questions, in order

1. **Where the time goes** (E-168): load, compilation in the session, or run time, per step and setting. The decision criterion: whatever dominates is the next work item.
   - Compilation in the session that is the same in every session is a caching failure: code that could sit in a package image does not, or is not used from it.
   - Compilation that depends on the user's own code (the model's function type in the solver's types) is a design question: what the trait core keys its code on ([traits §6](../reference/traits.md#6-values-in-trait-code-compiled-and-dynamic), `Dynamic` models).
   - Load time is image size and validation (the facts rule's edges included).
2. **What a trait core amenable to caching across sessions requires.** A design note from (1): which code a package image of the core keeps, which keys it is compiled for, what a user's model and data compile anew, and what the facts rule adds at load.
3. **The porting architecture for Makie,** scoped by (1)'s attribution of the plot steps: which of Makie's layers become trait code, where its recipes and attribute conversions are keyed, what stays plain.

## 6. What is left out

- NetworkDynamics (no Python analogue).
- The detailed performance issues found so far (open issues 66, 71, W-57's sweep): pursued only where (1) shows them on this path.
- Upstream proposals (the user, 2026-10-27: "We are not proposing anything upstream yet.").
