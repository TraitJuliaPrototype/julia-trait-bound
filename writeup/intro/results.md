# What the demonstrators show

This page is for Julia programmers. It says what the measurements show, each against a fair baseline, with its caveats. The words used here are explained in [`traits-for-julia.md`](traits-for-julia.md). The precise numbers, with builds and dates, are in [`../design/evidence.md`](../design/evidence.md).

**How to read the numbers.**
- The unified build `unified` 23022b0ec7 with TraitWorld 1745fc6 and the ports' `unified` branches, on a shared host (load 2–8 of 128 cores), one job at a time, a warm-up and 3 runs (E-324), unless a row says otherwise.
- Treat differences under 10 % as noise. Numbers are rounded. "Fresh process" means a new Julia process, timed from its start to its exit.
- **The baselines:**
  - **Python:** the same task with pandas 3.0.6 and matplotlib 3.11.2 (Python 3.12.10), on the same host.
  - **Plain twins:** the same code written without traits (PlainTables), on the same build.

## In short

- **Four sessions a user would run, each in a fresh process,** beside Python's time for the same task:

  | Session | Julia, unified build | Python |
  |---|---|---|
  | Read a CSV file into a `DataFrame`, summarize, plot a histogram (the goal's task) | **1.59–1.63 s** | 0.63–0.65 s |
  | The same with the project's own reader and table library (TraitReport (t)) | **0.74–0.78 s** | 0.63–0.65 s |
  | An ODE solve and a plot, then a second model (setting D) | **2.00–2.04 s** | 1.43–1.46 s (another machine) |
  | A scripted DataFrames session at a REPL: read, show, describe, filter, sort, group, join, write, a second file | **3.01–3.34 s** | 0.69–0.75 s |

- **The facts mode keeps compiled code valid when unrelated packages load,** for any code it compiles. The ports' code compiled by facts carries the G2 bit in all but 68 of 3,468 instances, so their images keep the code a session reaches.
- **Traits** let code say what it needs: checked memberships, methods compiled per member's type or once, declared results where types are open.

## The four sessions

### The goal's task: CSV, DataFrames, a histogram

TraitReport's form (f): the CSV and DataFrames ports read a file into a `DataFrame`, summarize its columns, and TraitMakie draws a histogram to a PNG.

| Step | Time |
|---|---|
| Start | 0.19–0.20 s |
| Imports | 1.02–1.04 s |
| Read | 0.03 s |
| Summarize | 0.13–0.15 s |
| Plot and PNG | 0.10 s |
| Exit | 0.11 s |
| **Start to exit** | **1.59–1.63 s** |

Python takes 0.63–0.65 s, of it 0.47–0.50 s importing pandas and matplotlib (E-289).

What this shows:
- The task takes about 1 s longer than Python's.
- Most of the time is the imports: loading the ports' package images and activating their memberships.

### TraitReport (t): the project's own reader and table library

The same report with TraitCSV, TraitTables and TraitMakie.

| Step | Julia | Python |
|---|---|---|
| Start | 0.19 s | |
| Imports | 0.32–0.36 s | 0.46–0.47 s |
| Read | 0.009 s | 0.001 s |
| Plot and PNG | 0.11 s | 0.08 s |
| Exit | 0.10 s | |
| **Start to exit** | **0.74–0.78 s** | **0.63–0.65 s** |

Python's column is the goal's Python app, which does the same report (E-289).

What this shows: small libraries written with traits come within about 0.15 s of Python, start to exit.

### Setting D: an ODE solve and a plot

TraitDifferentialEquations and TraitMakie: load, solve a model with Tsit5, plot it, then solve a second model and plot again.

| Step | Time |
|---|---|
| Start | 0.22 s |
| Load | 0.50–0.51 s |
| First solve | 0.33–0.35 s |
| First plot | 0.31–0.32 s |
| A second model | 0.05 s |
| **The session** | **2.00–2.04 s** |

Python, with the same task, takes 1.43–1.46 s on another machine (E-230).

What this shows:
- A second model costs 0.05 s: the solver is not compiled again for a new right-hand side.
- The first solve is mostly compiling (0.32–0.33 s of it): the script's own code, the user's right-hand side at dual numbers, and the library's checks.

### The forks' REPL session

The CSV, DataFrames and Tables ports (forks of CSV 1.1.0, DataFrames 1.8.2, Tables 1.14.0) in a scripted session at a REPL. Per step, first calls:

| Step | Time |
|---|---|
| The REPL's start | 0.64–0.71 s |
| Imports | 0.90–1.22 s |
| Read | 0.05 s |
| Show / describe | 0.17 / 0.04 s |
| Select and filter / sort / group and combine | 0.12 / 0.06–0.08 / 0.03 s |
| A user's function / join | 0.12 / 0.08 s |
| Write | 0.49–0.55 s |
| A second file: read and show, describe, sort, group | 0.01–0.08 s each |
| **Start to exit** | **3.01–3.34 s** |

pandas takes 0.69–0.75 s for the same session (E-289).

What this shows:
- After the imports, each step's first call takes tens of milliseconds, the write and the display aside.
- The write's time is mostly the REPL's display of the returned path, compiled again because a package the session loads invalidates Base's printing ([evidence §3](../design/evidence.md#3-first-calls-and-sessions), E-318).

Caveats:
- The forks pass their upstream suites but for E-315's four known failures in DataFrames (three `@inferred` tests that see `Any` through run-time sites, [open issue 157](../open-issues.md#2-design), and one in Tables' integration).

## The facts mode: compiled code that survives package loads

- **The G2 bit.** Each CodeInstance compiled by facts carries a bit that says whether only a stakeholder's change or a winning pirate can invalidate it. Under the test bed, which compiles all code by facts, 99.8–99.9 % of the code carries it (E-278). In the ports' images, 68 of 3,468 facts instances do not (E-320).
- **What it buys a port.** Plain packages loaded after the CSV port invalidated 752 of its and TraitMakie's image instances while its reader was plain code; compiled by facts, the reader's image code stays valid, and the goal's read takes 0.03 s against 0.27 s (E-302).
- **A membership invalidates nothing.** The sessions above hold one guarded call or none (E-319): compiled code never relies on a type's not being a member.

The facts mode's cost on code that is not type-stable: Julia's benchmark suite (4,342 benchmarks), with all code compiled by facts, against Julia's usual mode, measured on the julia-1.13 build of 2026-10-21 ([evidence §1](../design/evidence.md#1-the-guarantee)):
- geometric mean: 3.7 % slower;
- the worst cases, on containers of `Any`: up to 28× slower (`filter!` on a `Vector{Any}`).

## NetworkDynamics

A port of NetworkDynamics.jl to the unified build, its models' components as members of traits:
- new equations in a running session: 0.57 s, against 1.10 s on the earlier build (E-327, `unified` 6767b03893 with TraitWorld c9f701e);
- its workload's steady state: 237–241 ms, against 776–780 ms on the earlier build (E-327).

## What is not shown yet

- **On the unified build:** the run-time micro-benchmarks (a call on a value known only by its trait, `Callable` calls, mixed collections), the ODE solver's run time per step, the plain twins PlainODE and PlainPlots, the facts mode's benchmark suite. The evidence has them on the julia-1.13 builds ([evidence §2](../design/evidence.md#2-run-time)).
- **Upstream CSV.jl and DataFrames on the unified build** in the forks' scripted session.
- **Strict mode** on a stack of ports.
- **Threads; Revise;** ahead-of-time binaries on the unified build.
