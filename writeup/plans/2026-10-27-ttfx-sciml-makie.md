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

## 3. The target

- **The baseline:** the Python session, warm (the font cache built): 1.55 s start to exit (load 0.46, first simulation 0.07, first plot 0.51, a second model 0.24, again 0.17; one run, `experiments/ttfx/logs/try/`).
- **The target for a trait world of SciML and Makie:** the whole session within twice Python's, about 3 s, with a second model under 0.3 s. A first milestone, not the end: the claim is that nothing in the trait design forces it above Python's.

## 4. The settings

- **Python:** SciPy and matplotlib (`experiments/ttfx/pyenv`, versions in the log).
- **S:** stock Julia 1.13.2, upstream OrdinaryDiffEq (`OrdinaryDiffEqTsit5`, `OrdinaryDiffEqRosenbrock`) and CairoMakie, with their own precompile workloads.
- **U:** the same packages on the patched build, product setting.
- **A:** the same under `all` (needs the facts system image rebuilt; added when it is).
- **C:** the SciML core as it stands in the port (P6's trees, wrapped inside out), upstream CairoMakie; without NetworkDynamics.
- **D:** the two demonstrators, TraitDifferentialEquations and TraitMakie: a small trait core written as idiomatic trait code. The workload's nearest form (Rodas5 for Rodas5P; no log axis).
- Later: the settings each phase below builds.

## 5. The plan

Every experiment runs in minutes: one fresh session per setting first, three only where a decision hangs on a difference. Nothing runs for hours. Each phase ends with a decision written into this note.

**Phase 1, where the time goes (E-168).** The workload in every setting, per step: wall, compile and GC time.
- *Decides:* whether load, compilation in the session or run time dominates, per step, and how far D (small, idiomatic) is from Python. If D is near Python and S/U/C are far, the question is scale: what a large core must keep to stay like D.

**Phase 2, what is compiled in the session (E-169).** One attribution run per setting: `--trace-compile` with timing (each method instance compiled, and how long), grouped by package and owner; `@time_imports` for the load; the package images loaded or rejected.
- *Decides:* which compilation repeats in every session for the same code (a caching failure: the code is not in an image, or an image's code is not used), and which is keyed on the user's model or data (a design question for the core).

**Phase 3, the ceiling of caching today (E-170).** The compiled statements of phase 2 put into a precompile workload of a small package loaded with the stack; the session measured again.
- *Decides:* how much of the session caching can remove with today's mechanisms, and what remains (loading itself, the second model's own code). If load dominates what remains, the next work is load time (image size, the facts edges' validation), not compilation.

**Phase 4, the design note: a trait core amenable to caching across sessions.** From phases 1–3: which code the core's images keep and at which keys (the model `Dynamic`, as in TDE; the solver compiled per state and parameter type); what a user's model and data compile anew; what the facts rule adds at load. A fresh-eye review.

**Phase 5, the porting architecture for Makie.** Scoped by phase 2's attribution of the plot steps: which of Makie's layers (the conversion pipeline, `ComputePipeline`, recipes, attributes, the Cairo backend) become trait code, at which keys, what stays plain; TraitMakie's lessons. A fresh-eye review.

**Phase 6, the smallest prototype that tests phases 4–5 at scale.** Chosen after phase 2: the workload's path through the SciML core with the model `Dynamic` (W-34's forms), and the slice of Makie the plots use (`Figure`, `Axis`, `lines!`, a PNG), as trait code, measured in the same workload.

**Pushback** found on the way (the design or the user's direction meeting the code) goes to `open-issues.md` with the evidence, and is listed in this note.

## 6. What is left out

- NetworkDynamics (no Python analogue).
- The detailed performance issues found so far (open issues 66, 71, W-57's sweep): pursued only where (1) shows them on this path.
- Upstream proposals (the user, 2026-10-27: "We are not proposing anything upstream yet.").
