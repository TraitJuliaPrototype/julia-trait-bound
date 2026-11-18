# What the measurements show

This page is for Julia programmers. It says what the measurements show, each against plain Julia or Python, with its caveats. The words used here are explained in [`traits-for-julia.md`](traits-for-julia.md). The precise numbers, with builds, run counts and logs, are in [the evidence](../design/evidence.md); each result below names its experiment there (`E-n`). What the project sets out to show, and which claims are not yet supported, is in [the goals](../goals.md).

**How to read the numbers.**
- Everything is measured on a shared host of 128 cores, one job at a time, a warm-up and 2 or 3 runs. Treat differences under 10 % as noise. Numbers are rounded.
- "Fresh process" means a new Julia process, timed from its start to its exit.
- A *compiled instance* is one compiled copy of a method, for one combination of argument types. A package image holds a package's compiled instances.
- **The baselines:**
  - **Plain Julia:** the same packages compiled as Julia compiles them. On released Julia 1.13.2 where the row says so; otherwise on the Julia with the design's changes, so that only the way of compiling differs.
  - **Plain twins:** the demonstrators' code written without traits, on the same Julia.
  - **Python:** the same task with pandas and matplotlib, or SciPy and matplotlib, on the same host.

## In short

- **Loading unrelated packages discards little or none of the compiled code.** With nine unrelated packages loaded after the work:

  | Code | Compiled instances discarded | The same work again |
  |---|---|---|
  | CSV.jl and DataFrames, plain Julia | 9.0 % | 5.2–5.3 s |
  | CSV.jl and DataFrames as they are, compiled in the facts mode by one line per module | **0.4 %** | **1.7 s** |
  | The ports of CSV.jl and DataFrames to traits | **1.0 %** | 2.2 s (0.19 s before the loads) |
  | Small libraries written with traits: a reader, a table, a plot | **none** | nothing compiled again |
  | The same small libraries without traits | 28 instances | 0.33 s |

- **A new member, a new type, a new closure compile little, and discard nothing.** Twenty packages that each add a member to one trait discard none of each other's code, in any load order. A member's package image holds 42 compiled instances where a plain twin's holds 146.
- **The costs are stated below:** no faster steady state is claimed; first-run sessions take longer than Python's; code that uses no trait pays a little; an edit of a method at a trait takes about half a second in a session.
- **Mistakes are reported where they are made.** Of thirteen mistakes made against one small library, written with traits and in plain Julia, the trait form reports five at the line that makes them, where plain Julia reports four at a later call inside the library and one not at all.
- **Not shown yet:** better messages for failures inside a user's own function at run time, a library-sized trait program as a trimmed binary, a port by someone outside the project.

## Unrelated packages loaded after the work

The work: read a CSV file into a `DataFrame`, describe, sort, group and combine. Then nine packages the work does not use are loaded, and the work runs again (E-392).

| | Plain Julia | The one line | The ports |
|---|---|---|---|
| Compiled instances of the packages' own code discarded | 424 of 4,693 | 14 of 3,490 | 48 of 4,799 |
| The work: first run | 4.13–4.26 s | 1.88–1.89 s | 0.18–0.19 s |
| The work after the loads | 5.17–5.29 s | 1.71–1.73 s | 2.22–2.25 s |

- **"The one line"** is upstream CSV.jl and DataFrames, each module compiled in the facts mode by one added line and otherwise unchanged. No trait is written.
- **The ports** are the forks of CSV 1.1.0, DataFrames 1.8.2 and Tables 1.14.0 with their generic code written at traits.
- **What is still discarded is reached through Base.** Code compiled in the facts mode builds on the plain functions of Base that it calls. A loaded package's method can invalidate one of those, and its callers are then compiled again.
- **The ports lose few instances, but the wrong ones:** the reader's entry functions. So their work after the loads costs many times its first run. This is an open tension in the design ([GT-8](../open-issues.md#2-tensions-between-the-goals)), not a property a port can fix.

**Small libraries written with traits, under the same loads** (E-377):

| | Written with traits | Plain twin |
|---|---|---|
| A read, a summary and a histogram: instances of the trait libraries discarded | 0 of 3,757 | 28 |
| The work after the loads | nothing compiled again | 330–331 ms |
| Two ODE solves and their plot: instances of the trait libraries discarded | 0 of 4,806 | no twin |
| The work after the loads | 81 ms | |

- A plain dependency of a trait package is discarded as plain code is: 6 instances of Colors, 13 of ForwardDiff and CommonSubexpressions.
- A module of a trait package that is compiled plainly is discarded as plain code is. A package's entry functions belong in a trait module ([`porting.md`](porting.md), 0.5).

## New members, new types, edits

**Twenty packages each add a member to one trait** (E-378), against a plain twin where each adds a subtype and methods:
- no member's load discards an instance, in any of five load orders; the plain twin loses 9;
- nothing is compiled again after a load;
- a member costs 8.2 ms of compiling.

**What a member's package image holds** (E-380): a package that adds a column type to the table library:
- written with traits: 42 compiled instances, 128 kB;
- the plain twin: 146 instances, 266 kB.

**At the REPL** (E-379, E-391), the demonstrators against their plain twins:

| Step | Written with traits | Plain twin |
|---|---|---|
| A table with columns of new cell types, summarized, sorted and plotted | 522–527 ms | 560 ms |
| The same with a column of a new struct type | 147–150 ms | 189 ms |
| An ODE solve with a new right-hand side | 59 ms | no twin |
| An ODE solve with a new parameter struct | 223 ms | no twin |
| Evaluating an edited method at a trait | 0.65–0.70 s the first time in a session, then 0.48–0.50 s | 88 ms the first time, then 9 ms |

- None of the new types or closures discards compiled code.
- The last row is a cost: a method at a trait is checked when it is defined, so each edit runs the check.

## Sessions against Python

Sessions a user would run, each in a fresh process:

| Session | With traits | Plain Julia | Python |
|---|---|---|---|
| Read a CSV file with the project's own small reader and table library, summarize, plot a histogram (E-389, E-289) | 0.78–0.80 s | | 0.63–0.65 s |
| An ODE solve and a plot, then a second model (E-389, E-168) | 1.89–1.91 s | upstream OrdinaryDiffEq and CairoMakie on Julia 1.13.2: 9.2 s | 1.45 s |
| A scripted DataFrames session at a REPL: read, show, describe, filter, sort, group, join, write, a second file (E-390, E-386, E-289) | the ports: 2.61–2.62 s | upstream: 13.5–13.6 s on Julia 1.13.2 | 0.69–0.75 s |

- **Julia is slower than Python on every row,** and several times faster than plain Julia on the two rows that have it.
- **The ODE row is not like for like:** the demonstrators have a fraction of SciML's and Makie's features.
- **Most of a short session's time is the start and the imports:** loading the package images. After that, code generation and inference of the session's own code ([the evidence](../design/evidence.md#where-a-sessions-time-goes), E-388).
- The ports pass their upstream test suites but for four tests in DataFrames that assert an inferred type and see `Any` ([open issue 157](../open-issues.md#2-design); E-373).

## What it costs

**No faster steady state.** The claim is no regression where types are known. A trait operation at a known type costs what a plain call costs, 0.79 ns (E-443). Erased code pays for being compiled once: an operation on a boxed value takes 5.6–9.1 ns, where Julia's own dynamic call takes 18 ns (E-443).

**Code that is not type-stable, compiled in the facts mode,** gets slower at each call whose argument types are unknown. How much, over a broad benchmark suite, is not measured on this implementation ([the evidence](../design/evidence.md), G-4).

**Code that uses no trait** runs on the same Julia, where dispatch and subtyping also look at memberships (E-499, E-386):
- upstream CSV.jl and DataFrames compiled plainly: the first run takes 3.3–3.5 s against 3.3 s on Julia 1.13.2; repeated small operations 0.18–0.19 ms against 0.17–0.18 ms;
- a long scripted session of plain code takes 14.1–14.4 s against 13.5–13.6 s;
- loading the trait library after plain work discards none of the plain code.

**Editing:** about half a second to evaluate an edited method at a trait in a session (the table above).

**Erasing a stream on purpose:** code that writes a byte or a character per call through an erased stream is 3.6 to 5 times slower than with the stream's type known; formatted output within 10 to 20 % (E-340). [`porting.md`](porting.md) says where to erase.

## What is not shown yet

- **Better messages for failures at run time inside a user's own function.** On three classic failures of a differential equation solver, the trait port's messages are shorter than the upstream package's and no shorter than those of the same small solver written without traits: no contract is broken, so no check reports earlier (E-363).
- **Ahead-of-time binaries of a library's size.** Small trait programs build as trimmed binaries (`juliac --trim`) and run, 2.5 MB with no compiler in them, also where they loop over a vector typed by a trait; the same loop over an abstract type is refused in plain Julia (E-384). One demonstrator's program built this way too on the build the numbers are from: a CSV read with a summary, 3.1 MB, with the session's output (E-383). On the current build it does not: its loops must hand each column over as `compiled_for(c)` for a build to compile them per column type ([open issue 242](../open-issues.md#2-design)). The ODE program and the plot's do not build.
- **A port by someone outside the project.**
- **Scale:** the ports are parts of three ecosystems.
- **A cache across sessions.**
- **Threads; Revise.**
