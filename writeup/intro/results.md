# What the measurements show

This page is for Julia programmers. It says what the measurements show, each against a fair baseline, with its caveats. The words used here are explained in [`traits-for-julia.md`](traits-for-julia.md). The precise numbers, with builds, run counts and logs, are in [`../design/evidence.md`](../design/evidence.md); each result below names its experiment there (`E-n`). What the project sets out to show, and which claims are not yet supported, is in [`../goals.md`](../goals.md).

**How to read the numbers.**
- Everything is measured on the unified build, on a shared host of 128 cores at a load of 2–15, one job at a time, a warm-up and 2 or 3 runs. Treat differences under 10 % as noise. Numbers are rounded.
- **The loads, the members, the REPL and the plain-code control** (E-355 to E-360): `unified` 36b653bb3b with TraitWorld 048c44e.
- **The sessions against Python:** the totals on `unified` b05ae361e0 with TraitWorld 4443d2c (E-337); the steps on `unified` 23022b0ec7 with TraitWorld 1745fc6 (E-324).
- "Fresh process" means a new Julia process, timed from its start to its exit.
- A *compiled instance* is one compiled copy of a method, for one combination of argument types. A package image holds a package's compiled instances.
- **The baselines:**
  - **Plain Julia:** the same packages compiled as Julia compiles them, on the same build.
  - **Plain twins:** the demonstrators' code written without traits (PlainTables, PlainPlots), on the same build.
  - **Python:** the same task with pandas 3.0.6 and matplotlib 3.11.2 (Python 3.12.10), on the same host.

## In short

- **Loading unrelated packages discards little or none of the compiled code.** With nine unrelated packages loaded after the work:

  | Code | Compiled instances discarded | The same work again |
  |---|---|---|
  | CSV.jl and DataFrames, plain Julia | 9.2 % | 4.2 s |
  | CSV.jl and DataFrames as they are, compiled in the facts mode by one line per module | **0.4 %** | **0.48–0.66 s** |
  | The ports of CSV.jl and DataFrames to traits | **1.0 %** | 0.96–0.98 s (0.063 s before the loads) |
  | Small libraries written with traits: a reader, a table, a plot | **none** | **30 ms**, as before the loads |
  | The same small libraries without traits | 28 instances | 0.48 s |

- **A new member, a new type, a new closure compile little, and discard nothing.** Twenty packages that each add a member to one trait discard none of each other's code, in any load order. A member's package image holds 0.29× the compiled instances of a plain twin's.
- **The costs are stated below:** no faster steady state is claimed; first-run sessions take 1.2–4.5× Python's time; code that uses no trait is up to 8–18 % slower on small repeated operations; an edit of a method at a trait takes 0.4 s.
- **Mistakes are reported where they are made.** Of thirteen mistakes made against one small library, written with traits and in plain Julia, the trait form reports five at the line that makes them, where plain Julia reports at a later call inside the library, or not at all.
- **Not shown yet:** error messages in a large port, a trait program as a trimmed binary, the speed of trait calls on the current build.

## Unrelated packages loaded after the work

The work: read a CSV file into a `DataFrame`, describe, sort, group and combine. Then nine packages the work does not use are loaded (OffsetArrays, StatsBase, Unitful, IntervalArithmetic, Distributions, Interpolations, StaticArrays, CairoMakie, REPL), and the work runs again (E-355).

| | Plain Julia | The one line | The ports |
|---|---|---|---|
| Compiled instances of the packages' own code discarded | 433 of 4,706 | 14 of 3,487 | 48 of 4,796 |
| The work: first run | 3.03–3.06 s | 0.67–0.70 s | 0.063 s |
| The work after the loads | 4.18–4.20 s | 0.48–0.66 s | 0.96–0.98 s |
| Instances compiled after the loads | 900 | 43 | 69 |

- **"The one line"** is upstream CSV.jl, DataFrames and five of their dependencies, each module compiled in the facts mode by one added line and otherwise unchanged. No trait is written.
- **The ports** are the forks of CSV 1.1.0, DataFrames 1.8.2 and Tables 1.14.0 with their generic code written at traits.
- The results are equal in the three columns, before and after the loads.
- **What is still discarded is reached through Base.** Code compiled in the facts mode builds on the plain functions of Base that it calls. A loaded package's method can invalidate one of those (`vcat`, `open`, `promote_rule`, `getindex`, `convert`), and its callers are then compiled again.
- **The ports lose few instances, but the wrong ones:** the reader's entry functions. So their work after the loads costs fifteen times its first run. This is an open tension in the design ([open issues](../open-issues.md) §1, GT-8), not a property a port can fix.

**Small libraries written with traits, under the same loads** (E-357):

| | Written with traits | Plain twin |
|---|---|---|
| A read, a summary and a histogram: instances of the libraries discarded | 0 of 3,728 | 28 |
| The work after the loads | 30 ms, as repeated | 476–483 ms, against 29 ms repeated |
| Two ODE solves and their plot: instances of the libraries discarded | 0 | no twin |
| The work after the loads | 77 ms, against 17 ms repeated; 58 ms of it the script's own two functions, which are plain code | |

- A plain dependency of a trait package is discarded as plain code is: 6 instances of Colors, 13 of ForwardDiff and CommonSubexpressions.
- A module of a trait package that is compiled plainly is discarded as plain code is. A package's entry functions belong in a trait module ([`porting.md`](porting.md), 0.5).

## New members, new types, edits

**Twenty packages each add a member to one trait** (E-358), against a plain twin where each adds a subtype and methods:
- no member's load discards an instance of the twenty-one packages, in any of five load orders; the plain twin loses 9;
- the compiled instances at the end are the same in every load order;
- after a member's load, its first use takes 8.3–8.6 ms, not growing with the number of members. The plain twin takes 18–39 ms at each of the first four members and 6.8–7.2 ms after;
- that 8–9 ms is paid again in each session: a member that joined after its caller was compiled is reached through a table, and no package image holds the table's entry.

**What a member's package image holds** (E-360): a package that adds a column type to the table library, with a table of it summarized, sorted and cut:
- written with traits: 42 compiled instances and 97 kB of image;
- the plain twin: 146 instances and 240 kB, 123 of the instances Base's methods compiled again for the new type;
- the declaration alone compiles nothing in either form.

**At the REPL** (E-359), the demonstrators against their plain twins:

| Step | Written with traits | Plain twin |
|---|---|---|
| A table with columns of new cell types, summarized, sorted and plotted | 518–544 ms | 565–573 ms |
| The same with a column of a new struct type | 148–151 ms | 166–177 ms |
| An ODE solve with a new right-hand side | 55–57 ms | no twin |
| An ODE solve with a new parameter struct | 191–202 ms | no twin |
| The work after an edit of a method that is called through a cast | 116–118 ms, no caller compiled again | 124–127 ms, its callers compiled again |
| Evaluating an edited method at a trait | 0.40–0.42 s; 2.82 s the first time in a session | 8–9 ms; 82–94 ms the first time |

- None of the new types or closures discards compiled code.
- The last row is a cost: a method at a trait is checked when it is defined, so each edit runs the check.

**NetworkDynamics:** new equations in a running session take 0.57 s, with the models kept by their trait. With the models stored as themselves, the network's type names each model, and new equations take 6.6 s (E-309, E-327).

## Sessions against Python

Four sessions a user would run, each in a fresh process (E-337):

| Session | Julia, unified build | Python |
|---|---|---|
| Read a CSV file into a `DataFrame`, summarize, plot a histogram | **1.76–1.80 s** | 0.63–0.65 s |
| The same with the project's own small reader and table library | **0.79–0.83 s** | 0.63–0.65 s |
| An ODE solve and a plot, then a second model | **1.96–1.98 s** | 1.43–1.46 s (measured on another machine) |
| A scripted DataFrames session at a REPL: read, show, describe, filter, sort, group, join, write, a second file | **2.95–3.56 s** | 0.69–0.75 s |

Julia is slower than Python on every row. Where the time goes, by step, on the build of E-324, where the totals were within 0.2 s of those above:

| Step | CSV, DataFrames, histogram | Own reader and tables | ODE solve and plot |
|---|---|---|---|
| Start | 0.19–0.20 s | 0.19 s | 0.22 s |
| Imports | 1.02–1.04 s | 0.32–0.36 s | 0.50–0.51 s |
| The work | read 0.03 s, summary 0.13–0.15 s, plot 0.10 s | read 0.009 s, plot 0.11 s | first solve 0.33–0.35 s, first plot 0.31–0.32 s, a second model 0.05 s |
| Exit | 0.11 s | 0.10 s | |

- **Most of the time is the start and the imports:** loading the package images and activating their memberships. Python imports pandas and matplotlib in 0.47–0.50 s.
- **A second ODE model costs 0.05 s:** the solver is not compiled again for a new right-hand side.
- **In the REPL session,** after the imports each step's first call takes tens of milliseconds, the display and the write aside.
- The ports pass their upstream test suites but for four known failures in DataFrames: three tests that assert an inferred type and see `Any` ([open issue 157](../open-issues.md#2-design)), and one in Tables' integration (E-315).

## What it costs

**No faster steady state.** The claim is no regression where types are known. The calls through a trait have not been timed against plain calls on the current build; on the earlier build a typed trait call cost what a plain call costs ([evidence §2](../design/evidence.md#2-run-time)).

**Code that is not type-stable, compiled in the facts mode.** Julia's benchmark suite (4,342 benchmarks) with all code compiled in the facts mode, against Julia's usual mode, measured on the earlier julia-1.13 build of 2026-10-21 ([evidence §1](../design/evidence.md#1-the-guarantee)):
- geometric mean: 3.7 % slower;
- the worst cases, on containers of `Any`: up to 28× slower (`filter!` on a `Vector{Any}`).

**Code that uses no trait** (E-356): upstream CSV.jl and DataFrames compiled plainly, on the unified build against stock Julia 1.13.2:
- the first run is not slower: 3.02–3.04 s against 3.24 s;
- DataFrames' repeated steps on a small table are 8–18 % slower (`describe` 19.2 against 17.6 µs, `sort` 8.0 against 6.9 µs);
- TraitWorld loaded after the work discards 197 of 123,269 plain compiled instances, and the work after it takes 0.25 s. Loaded first, it discards nothing.

**Editing and members:** the two costs in the section above: 0.4 s to evaluate an edited method at a trait, and 8–9 ms per session for a member that joined after its caller was compiled.

## What is not shown yet

- **Error messages in a large port,** where plain Julia's are longest. The comparison is measured on a small library (E-362); the pages [`traits-for-julia.md`](traits-for-julia.md) and [`traits-by-example.md`](traits-by-example.md) show the messages.
- **Ahead-of-time binaries:** no demonstrator builds as a trimmed binary, written with traits or as its plain twin (E-361).
- **Run time on the current build:** a call on a value known only by its trait, `Callable` calls, mixed collections, the ODE solver's time per step. The evidence has them on the earlier build.
- **Strict mode** on a stack of ports.
- **Threads; Revise.**
