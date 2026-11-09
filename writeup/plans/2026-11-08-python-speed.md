# Reaching Python's speed on the goal's task

Status: **superseded** (2026-11-09, the user: "Okay the speed plan goals were too ambitious. We hereby retire all strict speed gain gates we have been working under. We still care about speed but there is no concrete goal to try to achieve, and we are more interested in principled holistic/broad gains enabled by facts and traits rather than in patching details here and there."); adopted 2026-11-08 (the user: "Go for the plan."), with stage 4 restricted to broad workloads (below). Not normative. Written in the main session (no subagents on the shared host). The stages are W-123 to W-127 in [the work queue](../record/todo.md).

**The goal.**
- The user (2026-11-07): "The overarching performance goal is Makie + DataFrames first workload as fast as Python equivalent."
- The user (2026-11-08): "If we are within Python + 1s that would be also fantastic. Python is aspirational rather than a strict goal."

So the target is the goal's task (TraitReport's form (f): the forks' `CSV.read` into a `DataFrame`, a summary, TraitMakie's histogram to a PNG) within **Python + 1 s, about 1.65 s**, with Python's 0.64 s as the aspiration. The forks' REPL session (pandas 0.69–0.75 s) and the ODE session, setting D (SciPy 1.43–1.46 s), are the secondary gates.

## 1. Where things stand

All on the shared host, 2026-11-08 (E-289, E-291; [evidence §3](../design/evidence.md#3-first-calls-and-sessions)).

The goal's task by phase:

| Phase | Python | Earlier build | Unified build | At Python + 1 s (a budget) |
|---|---|---|---|---|
| start and exit | 0.04 s | 0.35 s | 0.37 s | 0.35 s (Julia's floor) |
| imports | 0.46–0.47 s | 1.78–1.80 s | 26.2–26.4 s | **1.0 s** |
| read, summary, plot + PNG | 0.08 s | 0.35–0.36 s | 0.58–0.62 s | 0.3 s |
| **wall** | **0.63–0.65 s** | **2.46–2.49 s** | **27.1–27.4 s** | **1.65 s** |

- **The unified build's loss is a cost bug,** not the design: 92 % of DataFrames' load is the dispatch walk at activation, 96 % of the walk its conservative pass (E-290, [compiler C-72](../reference/compiler.md#deviations)).
- **The earlier build is 1.8 s above Python,** 0.8 s above the target: the imports (CSV 0.63 s, DataFrames 0.45 s, TraitWorld 0.17 s, CSV's extensions 0.15 s, PrettyTables 0.08 s by `@time_imports`) and 0.36 s of first calls.
- **Julia's floor:** a bare process takes 0.15–0.18 s, a session's start and exit 0.35 s; Python's 0.02–0.04 s (E-291). Python's own task is mostly its imports (0.56–0.58 s for pandas and matplotlib alone).
- **The secondary sessions:** the forks' session 38.0–38.5 s on the unified build, 5.06–5.07 s on the earlier one (imports 1.55 s, steps 2.80 s, a REPL's start 0.58 s). Setting D 11.6–11.8 s on the unified build (load 7.4–7.6 s, first solve 2.80 s, second model 0.79 s), 1.34–1.35 s on the earlier one (E-242, the project's machine).
- **TraitReport's form (t) met Python on the earlier build** (0.63 s, E-233): small trait cores with a workload in their images and a small tree. The forks never did: the earlier build's goal's task is 3.8× Python.

## 2. The stages

Each stage has a gate on the goal's task and on the secondary sessions, measured as E-289 measures them. A stage ends when its gate is met, or when the reason it is not is measured and recorded. Each change follows the rule for performance work ([decisions](../record/decisions.md) §5).

### Stage 1: the walk (C-72)

**Gate:** the goal's task ≤ 2.5 s, the forks' session ≤ 5.1 s, TraitReport (t) ≤ 0.8 s; the battery and the ports' digests unchanged.

1. **Scope the conservative visit to the replayed method's own function.** A method of `f` decides only calls of `f`, so only `f`'s specializations and cache entries can change their winner. Visit `mt->defs` and the method cache by intersection with the method's first parameter (the function's type), not every method of every function. This is exact, not an approximation.
2. **Substitute the member at a parametric set with free variables.** `f(c::TextColumn{T}) where T` replayed at `Vector{String1}` becomes `f(c::Vector{String1})` with `T` bound by the member's instance `TextColumn{String1}`. The substituted path, with its precise cache tail, becomes the common one; the conservative pass becomes the rare one its comment says it is.
3. **Profile every load again** (E-286's `load_profile.jl`) to name the next terms: validation, TraitWorld's own load, CSV's package callbacks (a third of CSV's load in E-287).
4. **C-40, moved here from stage 3** (2026-11-08, by the profile after items 1–2): CSV's load was then 75 % inference and compilation, 0.9 s of it compiling the native interpreter's code again. Loading TraitWorld invalidated 1,585 of the compiler's own instances through `ClassifyInterp`'s methods of the compiler's functions. The check's interpreter becomes the compiler's own (`Compiler.DefinitionCheckInterpreter`), with the library's hook.

- A bug fix of the implementation against its reference with an obvious fix, so it is inside W-121's own rule ([the campaign's plan](2026-11-08-w121-profiling-campaign.md) §4) and can start without a decision.
- Cost: a runtime change in `src/gf.c`, its gates (`m2_dispatch_worlds`, `m2_stale_caller`, `n7_guards`), a gate case for a parametric set replayed at a member, the battery, the ports' digests. One to two days.
- Expected: DataFrames' 19 s walk under 0.2 s; the imports at the earlier build's 1.6–1.8 s; setting D's load near its earlier 0.6 s.
- **Only if activation stays visible in the profiles:** precise lowering by cells, a design change for the user. A dispatch-cache entry at a member type that a shadow could change registers with that shadow's cell, as compiled code does with its guard. A membership then lowers only the entries its cells hold, and the walk goes. Changes compiler §5.5 and §9.

### Stage 2: first calls, at least the earlier build's

**Gate:** the goal's task after the imports ≤ 0.36 s; setting D's first solve ≤ 0.2 s and its second model ≤ 0.06 s; NetworkDynamics' new equations ≤ 1.2 s.

1. **C-54, by probe first, then built.** The probe: setting D with a `with_dynamic` cast at `ODEProblem` (minutes). If the first solve and the second model fall to E-242's, C-54 is the cause. Then build §6.2 as written: at an argument typed `X{T}` with `T` a method's variable, the instance compiled once is at the member's erased instance `X{T₀}`. TDE's default `Dynamic` returns, and with it the solver compiled once per state type instead of per function. This is the design's headline win for SciML (E-250: new equations 1.1 s against upstream's 15.7 s); the unified build loses it (9.0 s).
2. **The goal's `CSV.read`** (0.34–0.36 against 0.095 s): what compiles (`--trace-compile`, the invalidation log, the slot's counters). Candidates: facts callers of CSV's plain methods (E-265), guards that widen a result (open issue 158), image code rejected at load.
3. **NetworkDynamics' recompilation in the session** (1.5 s within the new equations, 1.7 s within the first pass; none on the earlier build): the invalidation log names what is invalidated after the loads. Candidates: memberships declared in the session (C-72 lowers the whole dispatch cache and clears instances' dispatch bits), `Callable`'s memberships begun by method definitions (compiler §4.3).
4. **Guards counted.** No counter exists: add one (guarded calls compiled, and negative folds refused by §4.8, per session). Then open issue 158's proposal (a) with C-36 (lowering records `f(…)::RT`), so that plain code keeps its inference when BaseTraits loads.

### Stage 3: the imports at 1.0 s

**Gate:** the goal's task ≤ 1.65 s (**Python + 1 s**).

The earlier build's imports are the starting point, 1.78 s; the target asks for 0.8 s less.
1. **What the forks' CSV and DataFrames do at load beyond upstream's.** Upstream CSV and DataFrames import in 0.63–0.68 s on the unified build (E-285); the forks took 1.08 s on the earlier build. `@time_imports` shows recompilation at load ("100 % recompilation" for DataFrames' 10 %). Measure on the unified build after stage 1: member checks, code compiled at load, image code rejected, validation.
2. **Validation by the G2 bit** ([the cache review](../reviews/2026-11-07-machine-code-cache-design.md) H5). Validation was about 0.6 s of the earlier forks' load. G2 code would skip the edge walk unless a method inserted since the image's build intersects one of its facts. Enabled by facts, so inside the rule for performance work. Needs C-46 closed. Measure first: validation's time split by the bit.
3. **C-40** (moved to stage 1 on 2026-11-08): the classification by the compiler's own check interpreter. It removes TraitWorld's own interpreter, and with it about 1,070 invalidations of the compiler's code at each load (E-281) and their recompilation in the session (0.12–0.14 s, E-234, E-238).
4. **The script's dependency tree.** PrettyTables (0.08 s, and about 450 image CodeInstances rejected at load on the earlier build, E-238) is loaded only to display. CSV's InlineStrings extension declares one membership per string width (20). If stage 1 leaves the extensions visible, the case goes to an open issue: a pattern membership as one entry.
5. **TraitWorld's own load** (0.17 s on the earlier build; BaseTraits' 51 memberships at activation): profiled again after stage 1.

### Stage 4: first calls without compiling

**Gate:** the goal's task after the imports ≤ 0.2 s; the forks' steps ≤ 1 s.

The user (2026-11-08): "Specific precompile workloads, unless they genuinely cover broad typical cases (String, Int Columns) are cheating. The traits+facts mode should enable us to work with Compiled code like with precompiled libraries. That's where the expectation of speed comes from."
1. **What a session still compiles, and why the images do not hold it.** With facts, a trait core's code is compiled per type or once and kept in its package's image; a session should compile only code at its own new types. Each CodeInstance the goal's session compiles after the imports is classified: plain code (whose code no image may keep), facts code at a new type, facts code an image could have kept but did not (a type value, compiler §9's rule; code rejected at load; a key not reached ahead). The last class is the target: fixed in the design or the implementation, not by a workload.
2. **Broad workloads only:** a port's image may compile its operations at the typical cell types (`String`, `Int`, `Float64`, `Missing` unions) as a library's own precompilation would, never the goal's specific call shapes.
3. **The environment-keyed session cache admitting code by the G2 bit** (W-120's revised order, item 6, with C-65 fixed first), only if 1 and 2 leave more than 0.1 s.

### Stage 5: toward Python itself (aspirational)

What remains after stage 4 is Julia's floor (0.35 s of a session's start and exit against Python's 0.04 s) and loading images. Each option is upstream work or a choice about how the task is shipped, so the user decides whether it is in scope:
- an application image: a system image that holds the session's packages;
- Julia's exit in a session with packages loaded (0.17 s, against 0.02 s for a bare `-e nothing`'s share);
- Julia's start (0.15 s on stock 1.13.2 on this host).

## 3. Expected trajectory

Estimates, each to be replaced by its gate's measurement.

| After | The goal's task | The forks' session | Setting D |
|---|---|---|---|
| today | 27.1 s | 38.0 s | 11.7 s |
| stage 1 | about 2.5 s | about 5 s | about 4.8 s |
| stage 2 | about 2.3 s | about 4.5 s | about 1.4 s |
| stage 3 | about 1.4–1.6 s (Python + 1 s met) | about 3 s | about 1.2 s |
| stage 4 | about 1.1–1.3 s, without workloads made for the task | about 1.5–2 s (a REPL's start 0.6 s remains) | about 1.0 s (below SciPy's) |
| stage 5 | toward 0.65 s | toward 0.7 s | |

## 4. Decisions

Adopted (the user, 2026-11-08, "Go for the plan."; [decisions](../record/decisions.md) §5). Still open for the user: open issue 160, and stage 5's scope when it comes.

The questions as they were put:

1. The target and the order: Python + 1 s for the goal's task, stages 1 to 4 in this order, stage 5 later.
2. Stage 1 starts now, as a bug fix under W-121's rule (C-72).
3. C-54 (stage 2.1) before open issue 158: it carries SciML's and NetworkDynamics' headline result.
4. Stage 3.2 (a loader change, validation by the G2 bit) and 3.3 (C-40): both principled, both enabled by facts.
5. Stage 5's scope: application images and Julia's own start and exit.
