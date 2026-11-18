# W-121: the profiling campaign on the unified build

Status: **adopted** (2026-11-08, mine, under the user's rule for the night's gates; for the user to review). Not normative. The request: the user (2026-11-07) asked for "a very thorough profiling campaign to precisely figure out where time is going in the new design. Then we can prioritise performance work."

## 1. Why now, and what is known

- **Every port runs on the unified build** (W-104, 2026-11-08): TraitTables, TraitCSV, TraitMakie, TraitReport, the forks of Tables, CSV and DataFrames, TraitDifferentialEquations, NetworkDynamics. Their results equal the plain forms', upstream's or the earlier build's.
- **The gates of slices 1 and 2 name the first item: loading** (E-284, E-285; [evidence §3](../design/evidence.md#3-first-calls-and-sessions)):

  | Session | Unified build | Of it, imports | Python |
  |---|---|---|---|
  | TraitReport (t) | 4.91–4.93 s | 4.08–4.10 s | 0.64–0.68 s |
  | the forks' DataFrames session | 38.7–39.6 s | 35.6–36.5 s (at a REPL) | 0.70–0.75 s |
  | NetworkDynamics' workload (one run) | 100.4 s | 13.0 s for Graphs and NetworkDynamics | — |

  The earlier build: 0.63 s, 4.71–4.83 s and 31 s. After the imports the unified build is fast (the forks' read 0.36–0.40 s against upstream's 3.1 s on the same build).
- **Pointers so far** (one profile each, not measurements): `using TraitWorld` 0.8 s by `@time_imports` and 1.8 s timed whole; in its profile about 40 % is the stopgap's dispatch walk at the activation of its memberships (`jl_memberships_activated` → `jl_membership_dispatch_walk`), about 54 % inference under `run_package_callbacks`. TraitTables' load is 82 % compilation; CSV's InlineStrings extension takes 5.4 s.

## 2. The sessions

- **G, the goal's session:** a first Makie + DataFrames workload (read a CSV into a DataFrame, group and aggregate, plot, write a PNG), `goal.jl` against `goal.py` (pandas + matplotlib), as the machine-code cache's review proposed (open issues §1, W-120, item 2). Written and registered first.
- TraitReport (t) and (pt); the forks' REPL session; TraitDifferentialEquations' session (E-230's harness); NetworkDynamics' workload (R7's `r7_time.sh`, adapted to the unified paths).
- Python's baselines in one environment (uv: Python 3.12, pandas 3.0.6, matplotlib 3.11.2, SciPy), on the same machine.

## 3. The phases

Each phase's experiments are registered before they run, each with the result that would change the plan.

1. **Loading** (the first item). Per package (`@time_imports`, timed whole), and within a package's load:
   - restoring the image; activating its memberships (the stopgap's walk, the ambiguity report, the cells); validating its code (edges, the G2 bit); the library's callbacks and hooks (strict mode at load, the image-methods hook, member records); extensions.
   - Means: Julia's profiler with C frames; counters in the runtime where none exist (memberships activated, the walk's visits, cells made, hook calls, validations by outcome); the invalidation log.
   - First, why `@time_imports` and the whole `using` differ (1.8 against 0.8 s for TraitWorld), and why the forks' imports are 36 s at a REPL and about 10 s outside it.
2. **First calls in the session:** compile time per step (Julia's counter, `--trace-compile`), what is compiled again and why (the invalidation log), the code slot's misses, marks and last resorts (`jl_code_slot_stat`), the guards' share.
3. **The steady state:** each step against upstream or the plain form on the same build, and against the earlier build.
4. **The synthesis:** a table of session by phase, the gap to Python per phase, and the candidates with their estimated savings: fixes in the load path, the machine-code cache (W-120), keys (W-110), reworking a port. The user prioritises from it.

## 4. Rules

- The rule for performance work stands (decisions §5): principled improvements, bugs with an impact of 20 % or more, slowdowns where trait code should be as fast as plain code; no tweaks at a large cost in complexity.
- The campaign measures and explains; it fixes nothing on its own, unless a finding is a bug of the implementation against its reference with an obvious fix, recorded as any deviation.
- Numbers name the build, the setting, the load order, the runs and the machine's load; the machine is shared (setup.md).

## 5. Order and size

Phase 1 for TraitReport (t) and TraitWorld alone first (a morning), then the forks and G; phases 2 and 3 per session after; the synthesis last. A few days in all.
