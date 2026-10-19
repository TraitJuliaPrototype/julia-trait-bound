# What the demonstrators show

This page is for Julia programmers. It says what the measurements show, each against a fair baseline, and with its caveats. The words used here are explained in [`traits-for-julia.md`](traits-for-julia.md). The precise numbers, with builds and dates, are in [`../design/evidence.md`](../design/evidence.md).

**How to read the numbers.**
- One machine, shared with other jobs. The patched Julia 1.13.2, as of 2026-10-19.
- Each number is from 1 to 3 runs. Repeated runs varied by about 5% on a busy machine; treat differences under 10% as noise.
- "Fresh session" means a new Julia process.
- "Plain" means the same code written without traits, run on the same patched Julia.
- "Big loads" means CSV, DataFrames and CairoMakie, loaded before or after the work.
- "Nine loads" means OffsetArrays, StatsBase, Unitful, IntervalArithmetic, Distributions, Interpolations, StaticArrays, CairoMakie and REPL.
- Numbers are rounded.

## In short

- **Protection from package loads comes from the compiler mode, not from traits.** Plain code compiled in the same mode keeps its compiled code too.
- **What traits add:** type-stable bounded code that pays nothing for that mode, conformances checked where they are written, readable types, and mixed collections close to plain speed.
- **Against the libraries people use today:** against SciML, a new callback or loss closure costs milliseconds instead of seconds; against upstream CSV.jl and DataFrames, a scripted session's first calls take 2.9 s instead of 10.4 s. Part of that comes from design choices a plain package can also make, and part from the compiler mode.
- **In a fresh process,** the small report with traits takes about as long as without them.
- **Not settled yet:** some first calls are still slower after big loads, and the cause is under investigation.

## The control: what protects compiled code from loads

The patched compiler can compile *all* code in its new mode, as a test setting. The control uses it to ask: is the protection from loads a property of traits, or of the mode?

The same work ran, then the nine loads, then the work again.

| What was measured | Normal setting (plain code compiled as usual) | All code in the new mode |
|---|---|---|
| A plain table library (PlainTables) together with TraitMakie: compiled code lost to the loads | 14 of 218 pieces (all of them PlainTables') | 0 of 206 |
| Its work after the loads (repeated work: 28 ms in both settings) | 96 ms | 29 ms |
| Upstream CSV.jl and DataFrames: compiled code lost (their own modules) | 570 of 4,712 pieces | 2 of 3,340 |
| Their first work / after the loads | 3.6 s / 4.0 s | 0.7 s / 1.0 s |

A piece of compiled code is one method compiled for one set of argument types. The counts leave out Base's code.

What this shows:
- In the new mode, plain code keeps its compiled code through unrelated loads. So the protection belongs to the compiler mode, for any code.
- Traits make the mode cheap. A bounded function is compiled for the types its trait sees; if those are concrete and the code is type-stable, the mode compiles it as plain Julia would. This follows from how the mode works, and has not been measured directly. Plain code that is not type-stable does lose speed in the mode (below).

What it leaves open:
- Upstream CSV.jl and DataFrames still pay about 1 s after the loads in the new mode, against under 1 ms for the repeated work. The count of lost code does not explain it. The cause is under investigation.

## Micro-benchmarks

| What | Trait form | Plain baseline |
|---|---|---|
| A bounded function called with known argument types | 36–38 ns | the same loop in plain Julia: 34–35 ns |
| A bounded function called with an argument of unknown type | about 120 ns | a plain dynamic call: about 55 ns |
| Sum of areas over 2,000 shapes kept as `Dynamic{Shape}` | 0.9–1.4 ns per element | 0.9 ns with two shape types; 30–33 ns with four |
| The same over 10⁶ shapes (limited by memory) | 4.5–5.7 ns | 3.9–4.0 ns with two types; 34–36 ns with four |
| A ray tracer over an open set of shape types | 300–340 ms, with two or with four types | 250 ms with two types; 830–880 ms with four |

What this shows:
- A typed call into trait code costs 5–12% more than the plain loop.
- A mixed collection through `Dynamic` takes 1.2–1.6× the time of plain Julia's best case.
- Plain Julia's best case holds only while it sees at most three matching methods. With four shape types, plain Julia is slower than the trait form: 2.5–3× in the ray tracer, 6–35× in the sums.
- With two shape types, plain Julia is faster than the trait form: 250 against 300–340 ms in the ray tracer.

Caveats:
- `Dynamic`'s fast path covers up to four conforming types. The cost with more than four is not measured.
- Calling trait code from code that does not know its argument types costs about twice a plain dynamic call.

**The cost of the new mode on plain code.** Measured earlier, with all code compiled in the new mode, on Julia's benchmark suite:
- geometric mean: 1.6% slower;
- the groups over concrete types: 0–9% slower;
- the worst cases, on containers of `Any`, abstract element types and broadcasts over small unions: up to about 80× slower.

These numbers predate the current compiler. They have not been rerun on it.

A JSON parser became 4.6× slower in the new mode, because a closure captures a reassigned variable. Julia's standard fix for that (`local pos::Int = 1`) recovers it: 178 µs, against 152 µs for the fixed plain code and 303 µs for the original. This fix is plain Julia, not traits. Not rerun on the current compiler.

**Found on the way, for plain Julia.** Two habits of Julia's inliner made a small recursion through a varargs wrapper 50× slower, on stock Julia too: 22 ms against 0.4 ms after the fix. The fixes apply to all code in the patched build and are candidates for upstream Julia after broader measurement.

## TraitDifferentialEquations: ODE solvers

**What it is.** The Tsit5 and Rodas5 solvers, discrete callbacks, and gradients through the solver with ForwardDiff. A model is a plain function or a type that implements the `ODEModel` trait.

**Baselines.**
- Stock SciML (OrdinaryDiffEq), measured earlier on stock Julia 1.12.2.
- PlainODE: the same solver without traits. It uses FunctionWrappers.jl for functions, untyped callbacks, and the same labelling of gradient tags.

**First calls, in a fresh session:**

| What | Trait form, no other packages loaded | Trait form, with big loads | Stock SciML |
|---|---|---|---|
| `using` | 0.47 s | 0.47 s (loads after); 1.3–1.4 s (loads before); one run took 7.3 s, when a cache was rebuilt (not rechecked) | |
| First Tsit5 solve, a plain function as the model | 10 ms | 28 ms (loads before) | 0.16 s |
| A new model type at the prompt: `@implement`, then first solve | 0.14 s + 0.08 s | 0.15–0.16 s + 0.09–0.13 s | 0.16 s for the solve |
| A new callback closure | 12 ms | 24 ms (loads before); **171 ms (loads after)** | 0.84–0.96 s |
| First gradient, then a second loss closure | 29 ms, then 17 ms | 34 ms, then 17–18 ms | 2.0–2.7 s, then 2.5 s |
| A `Float32` state, first solve | 0.45 s | 0.45 s | 2.1 s |

What this shows:
- A new callback or a new loss closure costs milliseconds, not seconds. Callbacks are kept as `Dynamic` values. Gradient tags are labelled by the loss's signature, not by the closure's type.
- With ForwardDiff's usual tag (the closure's type), the same gradient costs 0.7 s in this solver.
- A new model type costs 0.22–0.30 s in each load order.

**Run time per solver step:**
- Lorenz system (3 equations): model type 160 ns, plain function 190–200 ns, OrdinaryDiffEq 340–355 ns.
- A diffusion chain (1,000 equations): 7.5–7.9 µs, OrdinaryDiffEq 6.1 µs. OrdinaryDiffEq's inner loops are fused; this solver's are not.

**Types and errors:**
- The integrator's type is `Tsit5Integrator{Float64, Vector{Float64}}`, with or without callbacks. SciML's is 3,553 characters for Tsit5 and 24,426 for Rodas5.
- An error from parameters used but never passed: 12 stack frames, longest line 289 characters. SciML: 29 frames, 3,789 characters. Measured before the current compiler; not rechecked.
- Two other error cases (a `Float64` cache under a gradient, and under Rodas5) stay about as deep as SciML's: 25–30 frames against 22–44. Their longest lines are 300–870 characters, against SciML's 5,600–33,700.

Caveats:
- **Stock SciML is not the fair baseline for speed.** PlainODE makes the same design choices without traits. Measured before the current compiler, PlainODE matched the trait form on a second model function and on gradients in a fresh session, and was faster for a first callback (5 against 17 ms). The trait form was ahead after big loads (a first callback 29 against 144 ms). PlainODE is not measured on the current compiler.
- A new model type is slower than in SciML: 0.22 s in all, against SciML's 0.16 s.
- A new callback closure with big loads loaded after the first solve costs 171 ms instead of 12 ms. Not diagnosed.
- The first solve with big loads loaded before costs 28 ms instead of 10 ms. The cause is under investigation.
- SciML's numbers are from Julia 1.12.2, not 1.13.2.

## TraitMakie: a plotting library

**What it is.** A plotting library with Makie's shape at a small fraction of its size: nine plot types, recipes made of other recipes, attributes that change shape after a plot is made (a colour becomes a vector of colours, or a user's type), live data. Cairo draws the PNGs.

**Baselines.**
- PlainPlots: the same features without traits. It draws the same pixels for all five reference figures.
- Makie itself is much larger, so its times are not a fair comparison. Behaviour is: changing a colour's shape after the plot is made works here, and fails in Makie 0.24.16.

**First calls, in a fresh session, in each of three load orders (no loads, big loads before, big loads after):**
- `using TraitMakie`: 0.47–0.54 s.
- The first PNG: 21 ms in every order.
- A new data type at the prompt: `@implement` 77–97 ms, then its first PNG 89–161 ms.
- A new colour type: `@implement` 0.16–0.31 s, then its first PNG about 100 ms.
- Drawing again: 9 ms. Recolouring to a vector of colours: 84–231 ms.

What this shows:
- After a cheap import, plots appear in tens of milliseconds, whatever was loaded before or after.
- Before this round of work, a new data type after big loads took 5.5 s plus 2.1 s. That came from TraitWorld's own checks being recompiled after loads, and is fixed.

Caveats:
- **A regression without loads.** A new data type took 36 ms plus 40 ms before this round; now 77 ms plus 107 ms. The likely cause is TraitWorld's own machinery, now compiled in the new mode. Not diagnosed yet.
- PlainPlots' first calls were not measured on the current compiler. Before it, PlainPlots' first PNG took about 100 ms after big loads.
- The protection from loads is the compiler mode's (see the control).

## TraitReport: a data report against Python

**What it is.** Read a CSV file into a table, summarize its columns, plot a histogram to a PNG: the task where Julia users feel the time to first plot most. The libraries under it are TraitCSV and TraitTables (a reader and a table written with traits) and TraitMakie.

**Baselines.**
- The same report in Python, with pandas and matplotlib.
- The same libraries without traits (PlainTables), with the same precompile workloads.
- For the run under loads: a small trait module calling upstream CSV.jl and DataFrames, against the same code as a plain package.

**A fresh process, start to exit:**

| Form | Imports | Work | Total |
|---|---|---|---|
| With traits | 0.53 s | 0.07 s | 0.76 s |
| Without traits | 0.49 s | 0.06 s | 0.72 s |
| Python | | | 0.58–0.69 s (from an earlier session, not rerun) |

What this shows:
- Small precompiled libraries get close to Python's time, with or without traits. Traits do not make a fresh process faster here.

**The work after imports, under the nine loads** (the trait module calling upstream CSV.jl, against its plain twin):
- Trait form: 41 ms with no loads. 330–410 ms when StatsBase or Distributions is loaded. 340 ms with all nine.
- Plain form: 0.24–3.1 s.
- The 330–410 ms are diagnosed. StatsBase loads SparseArrays, a standard library, whose `vcat` for Base's `Number` and `Vector` wins at a call inside CSV.jl. The compiler follows it, as plain Julia does, and compiles that CSV.jl function again.
- The design counts the standard libraries as part of Julia itself. So this method is Julia's own: it is not piracy, and strict mode does not refuse it. Whether standard libraries should count separately is an open question.

**A package extension becomes a conformance.** InlineStrings' `String15` joins the reader by one `@implement` in a package extension. CSV.jl's own extension adds methods to CSV.jl's internal functions instead.

Caveats:
- The trait form's `using` is 0.04–0.2 s slower than the plain form's.
- The report with TraitCSV and TraitTables was not measured under loads on the current compiler.

## The CSV.jl and DataFrames.jl ports

**What it is.** Forks of Tables 1.14, DataFrames 1.8.2 and CSV 1.1.0, with traits brought in where they fit:
- a `Column` trait for every column, with the kernels of `describe`, `sort`, `groupby`, the joins and the common aggregates written against it;
- the CSV parse loop, with the column types it parses into as conformances;
- InlineStrings' string types as conformances in a package extension.

All three forks passed their upstream test suites on the new compiler, during this round of work.

**Baselines.** Upstream CSV.jl and DataFrames, and pandas 3.0, on the same scripted interactive session: read, show, describe, filter, sort, group and combine, join, add a column, write; then a second file; then strings read as `String15`.

**The session, at a REPL, 3 runs:**

| Step | Forks | Upstream | pandas |
|---|---|---|---|
| Imports | 1.7–2.1 s | 1.3–1.4 s | 0.19 s |
| Read | 0.08 s | 3.4 s | 0.01 s |
| Show / describe | 0.17 / 0.14–0.19 s | 1.0 / 1.0 s | 0.01 / 0.01 s |
| Sort / group and combine / join | 0.006 / 0.02 / 0.21 s | 1.15 / 0.77 / 1.24 s | 0.005 / 0.005 / 0.04 s |
| The whole session, without imports | **2.9 s** | **10.4 s** | **0.32 s** |

pandas' numbers are from an earlier session, on the same workload.

What this shows:
- The first calls of a DataFrames session got 3–4× faster, from 10.4 s to 2.9 s.
- It is still about 9× pandas.

Caveats:
- **The fair baseline is upstream compiled in the new mode,** with the same workloads. In the control, the new mode alone cut upstream's first work from 3.6 s to 0.7 s. So a large part of the gain may come from the compiler mode, not from traits. Upstream's session with all code in the new mode is not measured yet.
- The forks' imports are 0.3–0.7 s slower than upstream's.
- **The `String15` step** took 1.6–1.7 s in the session before this round's fixes, against upstream's 0.19 s. After the fixes, a script reading `String15` alone took 0.04 s. One of the two fixes is a hand-written workload extension, a workaround the design should replace. The forks' session has not been rerun after the fix.
- The port is partial, and paused. Not done: user functions as `Callable`s, joins on several key columns, the writer.

## What is not shown yet

- **The cause of the remaining cost after big loads:** about 1 s for upstream CSV.jl and DataFrames in the new mode; a callback closure in the ODE solver; TraitMakie's recolouring. Under investigation.
- **Reruns:** Python's baseline; PlainODE and PlainPlots; the report with TraitCSV under loads; the forks' session after the `String15` fix; Julia's benchmark suite in the new mode.
- **The fair baseline for the ports:** upstream's scripted session with all code in the new mode.
- **Strict mode** with all code in the new mode.
- **Threads; Revise;** libraries larger than a few thousand lines.
- **Ahead-of-time binaries** on the current compiler. An early TraitMakie compiled to a trimmed binary of 4.07 MB, before the current compiler.
