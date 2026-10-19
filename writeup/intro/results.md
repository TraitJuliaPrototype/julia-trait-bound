# What the demonstrators show

This page is for Julia programmers. It says what the measurements show, each against a fair baseline, with its caveats. The words used here are explained in [`traits-for-julia.md`](traits-for-julia.md). The precise numbers, with builds and dates, are in [`../design/evidence.md`](../design/evidence.md).

**How to read the numbers.**
- One machine, shared with other jobs; the patched Julia 1.13.2 of 2026-10-19.
- Each number is from 1 to 3 runs. Repeated runs vary by about 5% on a busy machine; treat differences under 10% as noise.
- Numbers are rounded. "Fresh session" means a new Julia process.
- **The baselines:**
  - **Stock Julia and the packages people use:** upstream CSV.jl and DataFrames, SciML's OrdinaryDiffEq, pandas.
  - **Plain twins:** the same code written without traits, run on the same patched Julia. They separate what traits add from what the patched compiler adds.
- "Big loads": CSV, DataFrames and CairoMakie, loaded before or after the work. "Nine loads": OffsetArrays, StatsBase, Unitful, IntervalArithmetic, Distributions, Interpolations, StaticArrays, CairoMakie and REPL.
- Where no current number exists, the page says "measured on the previous prototype": the earlier version of TraitWorld, which ran the same rules as a package instead of in Julia's compiler.

## In short

The project brings two things, and both pay off on their own.
- **The facts mode of Julia's compiler** keeps compiled code valid when unrelated packages load.
  - It works for any code, traits or not.
  - Upstream CSV.jl and DataFrames, compiled in it, lose 2 of 3,340 pieces of compiled code to nine unrelated loads, against 570 of 4,712 in Julia's usual mode.
  - Their first work takes 0.7 s instead of 3.6 s.
- **Traits** let code say what it needs.
  - Library code is compiled for what its traits can see, checked where it is written, and stable under its own extensions.
  - In a scripted DataFrames session, the trait-based ports take 2.9 s for their first calls, against 10.4 s for upstream CSV.jl and DataFrames.
  - In the ODE solver, a new callback or loss closure costs milliseconds, against about a second in SciML.
  - Mixed collections run close to plain Julia's best case, and stay fast when the set of types is open.
- **In a fresh process,** a small report with traits takes 0.76 s, about as long as without them, and close to Python's 0.6–0.7 s.
- **Open:** some first calls cost more after big loads than without them. The causes are under investigation.

## The facts mode: compiled code that survives package loads

The patched compiler can compile all code in its facts mode, as a test setting. The control runs the same work, then the nine loads, then the work again, in Julia's usual mode and in the facts mode.

| What was measured | Julia's usual mode | Facts mode |
|---|---|---|
| Upstream CSV.jl and DataFrames: compiled code lost to the loads (their own modules) | 570 of 4,712 pieces | **2 of 3,340** |
| Their first work / after the loads | 3.6 s / 4.0 s | **0.7 s / 1.0 s** |
| A plain table library (PlainTables) with TraitMakie: compiled code lost | 14 of 218 (all PlainTables') | **0 of 206** |
| Its work after the loads (repeated work: 28 ms in both modes) | 96 ms | **29 ms** |

A piece of compiled code is one method compiled for one set of argument types. The counts leave out Base's code.

What this shows:
- **Unrelated loads no longer discard compiled code,** for code written without traits too. Upstream CSV.jl and DataFrames keep their code through nine loads.
- **The first work is also faster:** 0.7 s against 3.6 s for upstream CSV.jl and DataFrames.
- The facts mode makes Julia stop guessing at calls whose argument types it cannot know, so code that is not type-stable can get slower. That is where traits come in (below).

Open: upstream CSV.jl and DataFrames still spend about 1 s after the loads in the facts mode, against under 1 ms for repeated work. The lost-code count does not explain it; the cause is under investigation.

## Traits: what they add on top

### Stable load times under a package's own extensions: CSV.jl

The facts mode protects compiled code from other packages' methods. It does not protect a package from its own extensions, which are common in well-trodden parts of the ecosystem.
- **CSV.jl** has an extension for InlineStrings that adds methods to CSV.jl's internal functions. DataFrames loads InlineStrings, so with DataFrames loaded, the extension discards the reader's compiled code: CSV.jl's first read takes 2.5 s instead of 0.19 s. The facts mode keeps this behaviour, because it is the package changing its own code.
- **TraitCSV** brings InlineStrings' `String15` into the reader with one implementation, declared in its extension. An implementation adds no method to the reader's functions, so loading InlineStrings discards none of the reader's compiled code. Measured on the previous prototype.

This is the coding pattern traits bring: a package is extended by declaring an implementation, never by adding methods to a library's internals. The trait-based ports of CSV.jl follow the same pattern.

### Micro-benchmarks

| What | Trait form | Baselines |
|---|---|---|
| A bounded function called with known argument types | 36–38 ns | the same loop in plain Julia: 34–35 ns |
| A bounded function called with an argument of unknown type | about 120 ns | a plain dynamic call: about 55 ns |
| Sum of areas over 2,000 shapes kept as `Dynamic{Shape}` | 0.9–1.4 ns per element | plain Julia: 0.9 ns with two shape types, 30–33 ns with four |
| The same over 10⁶ shapes (limited by memory) | 4.5–5.7 ns | plain Julia: 3.9–4.0 ns with two types, 34–36 ns with four |
| A ray tracer over an open set of shape types | 300–340 ms, with two or with four types | plain Julia: 250 ms with two types, 830–880 ms with four |

What this shows:
- A typed call into trait code costs 5–12% more than the plain loop.
- A mixed collection through `Dynamic` runs at 1.0–1.6× plain Julia's best case, and keeps that speed when more types join.
- Plain Julia's best case holds only while it sees at most three matching methods. With four shape types the trait form is 2.5–3× faster in the ray tracer and 6–35× faster in the sums.
- With two shape types, plain Julia is faster: 250 against 300–340 ms in the ray tracer.

Caveats:
- `Dynamic`'s fast path covers up to four conforming types; the cost with more is not measured.
- Calling trait code from code that does not know its argument types costs about twice a plain dynamic call.

**The facts mode's cost on code that is not type-stable.** Measured on the previous prototype of the compiler, with all code in the facts mode, on Julia's benchmark suite:
- geometric mean: 1.6% slower;
- the groups over concrete types: 0–9% slower;
- the worst cases, on containers of `Any`, abstract element types and broadcasts over small unions: up to about 80× slower.

A JSON parser was 4.6× slower in the facts mode on the previous prototype, because a closure captures a reassigned variable. Julia's standard fix (`local pos::Int = 1`) recovers it: 178 µs, against 152 µs for the fixed plain code. This fix is plain Julia, not traits.

**For plain Julia too.** The patched build fixes two habits of Julia's inliner that slow down a recursion through a varargs wrapper: 22 ms on stock Julia 1.13.2, 0.4 ms on the patched build, for all code. They are candidates for upstream Julia.

## TraitDifferentialEquations: ODE solvers

**What it is.** The Tsit5 and Rodas5 solvers, discrete callbacks, and gradients through the solver with ForwardDiff. A model is a plain function or a type that implements the `ODEModel` trait.

**Baselines.**
- **SciML's OrdinaryDiffEq**, measured on stock Julia 1.12.2.
- **PlainODE:** the same solver without traits. It uses FunctionWrappers.jl for functions, untyped callbacks, and the same labelling of gradient tags.

**First calls, in a fresh session:**

| What | Trait form, no other packages loaded | Trait form, with big loads | SciML |
|---|---|---|---|
| `using` | 0.47 s | 0.47 s (loads after); 1.3–1.4 s (loads before) | |
| First Tsit5 solve, a plain function as the model | 10 ms | 10 ms (loads after); 28 ms (loads before) | 0.16 s |
| A new model type at the prompt: `@implement`, then first solve | 0.14 s + 0.08 s | 0.15–0.16 s + 0.09–0.13 s | 0.16 s for the solve |
| A new callback closure | 12 ms | 24 ms (loads before); 171 ms (loads after) | 0.84–0.96 s |
| First gradient, then a second loss closure | 29 ms, then 17 ms | 34 ms, then 17–18 ms | 2.0–2.7 s, then 2.5 s |
| A `Float32` state, first solve | 0.45 s | 0.45 s | 2.1 s |

What this shows:
- A new callback or a new loss closure costs milliseconds, against about a second in SciML. Callbacks are kept as `Dynamic` values. Gradient tags are labelled by the loss's signature, not by the closure's type.
- With ForwardDiff's usual tag (the closure's type), the same gradient costs 0.7 s in this solver.
- A first gradient costs 30 ms, against 2–2.7 s in SciML.

**Run time per solver step:**
- Lorenz system (3 equations): model type 160 ns, plain function 190–200 ns, OrdinaryDiffEq 340–355 ns.
- A diffusion chain (1,000 equations): 7.5–7.9 µs, OrdinaryDiffEq 6.1 µs. OrdinaryDiffEq's inner loops are fused; this solver's are not.

**Types and errors:**
- The integrator's type is `Tsit5Integrator{Float64, Vector{Float64}}`, with or without callbacks. SciML's is 3,553 characters for Tsit5 and 24,426 for Rodas5.
- An error from parameters used but never passed: 12 stack frames, longest line 289 characters. SciML: 29 frames, 3,789 characters. Measured on the previous prototype.
- Two other error cases (a `Float64` cache under a gradient, and under Rodas5) are about as deep as SciML's: 25–30 frames against 22–44. Their longest lines are 300–870 characters, against SciML's 5,600–33,700.

Caveats:
- **PlainODE makes the same design choices without traits.** On the previous prototype, PlainODE matched the trait form on a second model function and on gradients in a fresh session, and was faster for a first callback (5 against 17 ms). The trait form was ahead after big loads: a first callback 29 against 144 ms.
- A new model type costs 0.22 s in all, against SciML's 0.16 s for the solve.
- A new callback closure with big loads loaded after the first solve costs 171 ms, against 12 ms without loads (one run; under investigation).
- SciML's numbers are from Julia 1.12.2, not 1.13.2.

## TraitMakie: a plotting library

**What it is.** A plotting library with Makie's shape at a small fraction of its size. It has nine plot types and recipes made of other recipes. Attributes can change shape after a plot is made: a colour becomes a vector of colours, or a user's type. It shows live data. Cairo draws the PNGs.

**Baselines.**
- PlainPlots: the same features without traits. It draws the same pixels for all five reference figures.
- Makie itself is much larger, so its times are not a fair comparison. Its behaviour is: changing a colour's shape after the plot is made works here, and fails in Makie 0.24.16.

**First calls, in a fresh session, in each of three load orders (no loads, big loads before, big loads after):**
- `using TraitMakie`: 0.47–0.54 s.
- The first PNG: 21 ms in every order.
- A new data type at the prompt: `@implement` 77–97 ms, then its first PNG 89–161 ms.
- A new colour type: `@implement` 0.16–0.31 s, then its first PNG about 100 ms.
- Drawing again: 9 ms. Recolouring to a vector of colours: 84–231 ms.

What this shows:
- After a cheap import, plots appear in tens of milliseconds, whatever was loaded before or after.
- A new type of the user's own costs a fraction of a second, in every load order.

Caveats:
- PlainPlots' first PNG took about 100 ms after big loads, measured on the previous prototype.

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
| Python, pandas and matplotlib (measured earlier on the same machine) | | | 0.58–0.69 s |

What this shows:
- Small precompiled libraries get close to Python's time, with or without traits.

**The work after imports, under the nine loads** (the trait module calling upstream CSV.jl, against its plain twin):
- Trait form: 41 ms with no loads, 340 ms with all nine.
- Plain form: 0.24 s with no loads, 3.1 s with all nine.
- With StatsBase or Distributions loaded, the trait form takes 330–410 ms. StatsBase loads SparseArrays, a standard library, whose `vcat` for Base's `Number` and `Vector` wins at a call inside CSV.jl. The compiler follows it, as plain Julia does, and compiles that CSV.jl function again. The design counts the standard libraries as part of Julia itself, so this is Julia's own method, not piracy. Whether standard libraries should count separately is an open question.

Caveats:
- The trait form's `using` is 0.04–0.2 s slower than the plain form's.
- The report with TraitCSV and TraitTables under loads is measured on the previous prototype only.

## The CSV.jl and DataFrames.jl ports

**What it is.** Forks of Tables 1.14, DataFrames 1.8.2 and CSV 1.1.0, with traits brought in where they fit:
- a `Column` trait for every column, with the kernels of `describe`, `sort`, `groupby`, the joins and the common aggregates written against it;
- the CSV parse loop, with the column types it parses into declared as implementations;
- InlineStrings' string types declared as implementations in a package extension.

All three forks pass their upstream test suites.

**Baselines.** Upstream CSV.jl and DataFrames, and pandas 3.0, on the same scripted interactive session: read, show, describe, filter, sort, group and combine, join, add a column, write; then a second file; then strings read as `String15`.

**The session, at a REPL, 3 runs:**

| Step | Forks | Upstream | pandas |
|---|---|---|---|
| Imports | 1.7–2.1 s | 1.3–1.4 s | 0.19 s |
| Read | 0.08 s | 3.4 s | 0.01 s |
| Show / describe | 0.17 / 0.14–0.19 s | 1.0 / 1.0 s | 0.01 / 0.01 s |
| Sort / group and combine / join | 0.006 / 0.02 / 0.21 s | 1.15 / 0.77 / 1.24 s | 0.005 / 0.005 / 0.04 s |
| The whole session, without imports | **2.9 s** | **10.4 s** | **0.32 s** |

pandas' numbers were measured earlier on the same machine and workload.

What this shows:
- The first calls of a DataFrames session take 2.9 s with the forks, against 10.4 s with upstream CSV.jl and DataFrames: 3.6× faster.
- It is still about 9× pandas.
- A first `String15` read takes 0.04 s with the forks (a script), against 0.19 s with upstream.

Caveats:
- **Both contributions are in the 3.6×.** The facts mode alone cuts upstream's first work from 3.6 s to 0.7 s (the control, above). Upstream's full session in the facts mode is not measured yet, so the share of each is open.
- The forks' imports are 0.3–0.7 s slower than upstream's.
- The fast `String15` read relies on a hand-written workload extension. The design aims to replace such extensions with code compiled ahead of time from the declared implementations.
- The port is partial. Not done: user functions as `Callable`s, joins on several key columns, the writer.

## What is not shown yet

- **The causes of the remaining cost after big loads:** about 1 s for upstream CSV.jl and DataFrames in the facts mode; a callback closure in the ODE solver; TraitMakie's recolouring.
- **On the current compiler:** Python's baseline; PlainODE and PlainPlots; the report with TraitCSV under loads; the forks' full session with the `String15` step; Julia's benchmark suite in the facts mode.
- **Upstream's full scripted session in the facts mode,** to separate its gain from the forks'.
- **Strict mode** with all code in the facts mode.
- **Threads; Revise;** libraries larger than a few thousand lines.
- **Ahead-of-time binaries** on the current compiler. A trimmed TraitMakie binary was 4.07 MB, measured on the previous prototype.
