# The evidence: what is measured, and what is not

A chapter of the [rationale](../design.md): the measurements behind the design, for core developers, as of 2026-10-20.

**The builds.**
- **The measurement round of 2026-10-20:** julia-1.13 3b8085c222 (branch `trait-world-1.13`), TraitWorld bed3782. Every number in this chapter is from it unless its row names another build.
- **Rows not in the round** keep their build: mostly julia-1.13 61852d8fb1 with TraitWorld 375a930 (2026-10-19), called "the build of 2026-10-19" below.
- **Before/after:** where an older number for the same quantity is kept, it is marked "before" with its build.

[evidence: Summary: what the evidence shows, and what it does not](evidence.md#summary-what-the-evidence-shows-and-what-it-does-not) summarizes this chapter; [`performance.md`](performance.md) says where the costs come from. The round's raw logs are in `experiments/factscompiler/round/logs/` (`run.log`, `callbench.log`, `untyped-{plain,all}.log`, `sites-{plain,all}.log`, `quick.log`, `bench.log`, `compare-full.log`, `compare-plain-vs-s28.log`, `demonstrators.log`, `g2all-{interleaved,before}.log`). TraitMakie's and TraitDifferentialEquations' rows were rerun after two fixes (the round's TraitMakie rows failed on an implicit forward, since fixed; the stated parameter's check is compiled into TraitWorld's image), and this chapter uses the reruns: `experiments/factscompiler/round/logs/makie-rerun.log` and `experiments/factscompiler/round/logs/tde-rerun.log`. Numbers of earlier builds and prototypes: the session note `../../session-notes/2026-10-18-29-reviews-and-decisions.md`, [`../record/design-history.md`](../record/design-history.md), [`../design-findings.md`](../design-findings.md) and the demonstrators' READMEs. A number marked "previous prototype" was measured on the package prototype, before the facts mode moved into Julia's compiler, and has no current counterpart yet.

**How to read the numbers.**
- One machine, mostly quiet during the round: one Julia process at a time.
- The forks' runs had a load average of 3.4–5.2: treat their times as indicative.
- Fresh processes, unless a row says "at the REPL".
- Runs per cell: 2 per load order for the demonstrators' rows, 3 for TraitReport, 2–3 for the forks. Ranges are over the runs. Treat differences under 10% as noise.
- "Plain" is the same code without traits, on the patched build in plain mode. The two inliner changes apply to all code, so patched-plain is not stock: stock numbers use the stock 1.13.2 binary and say so.

## 1. The guarantee

| Claim | Evidence | Where |
|---|---|---|
| Step 1: fully typed code is invalidated only by stakeholders and pirates | a stakeholder's method (S4), a winning pirate (S5) and a redefined `const` (S7) invalidate code at concrete signatures; a losing pirate (S6) never does; on 1.13.2 and with the in-tree facts mode | `experiments/facts/framing/`, `../reviews/2026-10-18-framing-and-motivation.md` §0; proofs in `../explorations/wrapping-by-facts.md` |
| Step 2: strict mode refuses winning pirates and nothing else | 65,318 methods of CSV, DataFrames and CairoMakie checked; 837 pirates by the letter; none winning, none refused; 0.54 s extra on a 4.1 s load (previous prototype) | `experiments/facts/g2strict.jl` |
| Step 3: the facts rule keeps all code valid | the four cases that are not fully typed (S1–S3, S8) invalidate on 1.13.2 and not in facts mode; acceptance 23 of 23, in the product setting and under `all` | `experiments/facts/acceptance_compiler.jl` |
| G2 across package loads, for code compiled by facts (product setting) | after TraitDifferentialEquations' and TraitMakie's work, 12,368 valid CodeInstances of the facts owner; **0 lost** after each of ten loads (again on julia-1.13 711484a23e, TDE e37829f, 2026-10-21: 0 of 12,835; `experiments/checks/logs/w9/g2all-interleaved.log`) (CSV, DataFrames, CairoMakie, OffsetArrays, StatsBase, Unitful, IntervalArithmetic, Distributions, Interpolations, StaticArrays); the work takes 9.0–10.7 ms after each load; first work 130 ms with the loads interleaved, 95.6 ms with the loads before | `experiments/facts/g2all.jl`; `g2all-{interleaved,before}.log` |
| Identical or error (G1) | acceptance G1.1–G1.15, G1.17–G1.23 and G2.1, including the review cases (a `Dynamic` of a known type, an assertion over a run-time site) | `experiments/facts/acceptance_compiler.jl` |

**The control: whose property is load protection.** The same work, then nine unrelated packages loaded (OffsetArrays, StatsBase, Unitful, IntervalArithmetic, Distributions, Interpolations, StaticArrays, CairoMakie, REPL), plain mode against `all` (`demonstrators.log`, the control):

| | plain mode | `all` |
|---|---|---|
| PlainTables + TraitMakie: CodeInstances lost | 14 of 256 (all PlainTables') | **0 of 244** |
| PlainTables' work: first / repeated / after the loads | 104 / 28.6 / 96 ms | 80 / 28.8 / **28** ms |
| upstream CSV + DataFrames: CodeInstances lost (own modules only; Base not counted) | 561 of 4,684 | **2 of 3,337** |
| their work: first / repeated / after the loads | 3,308 / 0.6 / 4,021 ms | 516 / 0.9 / **435** ms |

- Load protection is the facts rule's property, for any code, not traits'.
- **Before** (the build of 2026-10-19), upstream's work under `all` took 722 ms first and 992 ms after the loads. The compiler's own code compiled plainly in every compile queue (julia-1.13 f13117cd74) is the main change in between ([state](../state.md) §4).
- **Diagnosed on the build of 2026-10-19,** when it was ~990 ms: what upstream pays after the loads under `all` (now 435 ms, against 0.9 ms repeated; plain: 4.0 s) is the plain inference behind run-time `return_type`. Its cached answers rest on plain edges at abstract signatures (an `isapprox(::Integer, ::Integer)`, a `quantile!(::AbstractVector, …)`); the loads invalidate them (Unitful's `Colon(::Any, ::Any, ::Quantity)` alone 733 entries); `CSV.read` and `describe` ask again, and plain inference, optimizer included, runs again (70% of the profile then). This is by design: the answers are plain Julia's, so a load that changes plain inference changes them. The optimizer cannot be skipped: without it the answers get wider (CairoMakie's workload then fails) ([`performance.md`](performance.md)). The 435 ms has not been profiled again.
- **A second residue is diagnosed** (§3, TraitReport): StatsBase loads SparseArrays, a standard library, whose `vcat` for Base's `Number` and `Vector` wins at a fact signature inside `CSV._parse`. The design counts the standard libraries as Julia's own code ([glossary](../glossary.md) §1), so this is a stakeholder's change: not a pirate, not refused by strict mode (`TraitWorld/src/strict.jl:125`). Whether standard libraries should be separate owners is open ([`../open-issues.md`](../open-issues.md) §1.19).

**The cost of the facts rule on plain code.** The full BaseBenchmarks (4,342 benchmarks), `all` against plain, one run each (`compare-full.log`):
- **Geometric mean 1.037.**
- By group: array 1.043, collection 1.123, sort 1.056, union 1.060, scalar 1.027, simd 1.002, sparse 1.001; io 1.231 (10 benchmarks), problem 1.167, find 1.104.
- **The tails:** at most 27.8× (`filter!` on a `Vector{Any}`). The largest are on containers of `Any` (`filter`, `iterate` on `Dict{Any}` and `IdDict{Any}`: 16–20×), views over ranges (`sumrange_view`: 11×), `issorted` in reverse (8–9×); BaseBenchmarks' raytracer 4.4×, `parse_json` 3.1×.
- **Plain against the earlier plain baseline** (session 28's run, `full0`): 0.943. Plain Julia got faster with this build's general changes, so the 1.037 is against a faster plain.
- **Before** (an earlier build, before parts B–D, `--pkgimages=no`): geometric mean 1.016, 1.064 without `scalar`; tails up to about 80×.
- **The quick subset** (148 benchmarks, chosen to include the tails): geometric mean 1.710 (`quick.log`). It is a selection of tails and controls, not the facts mode's cost.

## 2. Run time

Rows marked "2026-10-19" are from the build of 2026-10-19 and were not in the round.

| What | Trait form | Baseline | Notes |
|---|---|---|---|
| a typed trait call (`untyped.jl`, per call) | 0.8 ns, in the product setting and under `all` | plain: 0.8 ns | inlining across owners. **Before** (julia 61852d8fb1, a loop of 16 inside the call): 36–38 ns against 33.8–34.5 ns |
| an untyped trait call (an argument from a `Vector{Any}`, per call), through the table of declared implementations: the path of `compiled_for` from an untyped caller (measured at TraitWorld bed3782, when every untyped call took the table; since W-4 an untyped call of a `Dynamic` value runs the worker at the erased key: not measured, W-17) | product setting 28.8 ns; `all` 30.8 ns; 16 bytes per call | plain: 18.9 ns; under `all` 17.6 ns | through the table of declared implementations. **Before** (julia 61852d8fb1, TraitWorld 375a930): 115–129 ns against about 55 ns |
| an untyped call, the type compiled ahead (2026-10-19) | about 14 ns | 15–17 ns | one dispatch to the type's own entry method |
| a `Callable` in `DynamicCall` mode, per call (`callbench.log`) | 3.95 ns; 4.46 ns with worlds alternating (`invoke_in_world` included) | a direct call 0.87 ns; a dynamic call at `Any` 20.3 ns | runs in the caller's world (`:caller_world`) |
| dynamic call sites in plain code (`sites.jl`, per call) | plain mode / `all`: monomorphic, result asserted 14.2 / 14.2 ns; 4 types, asserted 17.5 / 17.2 ns; 4 types, result untyped 34.7 / 34.8 ns; `push!(::Vector{Any}, x)` 1.6 / **13.6** ns | | the facts tail on containers of `Any` |
| sum over a vector of `Dynamic{Shape}` (2,000 elements, cache-resident; 2026-10-19) | 0.92–1.40 ns per element | plain, 2 types: 0.87–0.91; plain, 4 types: 29.5–33.0 | held views |
| the same, 10⁶ elements (2026-10-19) | 4.5–5.7 ns | plain, 2 types: 3.9–4.0; 4 types: 33.6–36.2 | memory-bound |
| raytrace over `Dynamic{Scene}` (BaseBenchmarks' raytracer, open set of primitives, `perf_raytrace(5, 256, 4)`; 2026-10-19) | 300–336 ms (2 or 4 implementations) | plain with 2 types: 246–259; with 4: 827–882 | the 4-type baseline is a `max_methods = 3` effect; the split stops at four candidates too |
| raytrace, small case (`perf_raytrace(5, 64, 2)`; 2026-10-19) | 4.7–5.3 ms, 3.8 MB | 3.9–4.7 ms, 3.3 MB | |
| a varargs wrapper in a plain recursion (the review's probe; 2026-10-19) | patched, plain code: 0.36–0.44 ms, 0 bytes | stock 1.13.2: 21.9–23.3 ms, 16.8 MB | the inliner changes, for all code |
| TDE, per solver step, Lorenz (n = 3; 2026-10-19) | problem type (then a model type) 158–160 ns; plain function 190–199 | OrdinaryDiffEq 338–355 ns | the round's run-time script did not load OrdinaryDiffEq (`scripts/runtime.jl:6`) |
| TDE, per step, a diffusion chain (n = 1,000; 2026-10-19) | 7.5–7.9 µs | OrdinaryDiffEq 6.1 µs | OrdinaryDiffEq's stage loops are fused with `@muladd` |
| idiomatic loops over heterogeneous containers, per element (`experiments/hetero-idiomatic/`; TraitWorld branch `basetraits`, medians, 2 runs, product setting and `all`) | within the split's four implementations: `filter!` in place over the user's `Vector{Any}` 3.3–3.8 ns; a `Dict{String,Any}` loop 4–5 ns; a sum over `Dynamic{X}` items 1.0–2.0 ns | trait code calling Base on the same containers (interop): 38–43 and 274–276 ns; plain: 2.2–2.4 and 2.4 ns; the sum in plain Julia with 4 types: 39–43 ns | beyond four implementations the view over the user's container costs about twice a copy into `Vector{Dynamic{X}}` (64 types: 162–181 against 78–84 ns; plain 99–106); E-134, E-143, E-144 |
| a `Dynamic` operation beyond the split's four implementations, per element (E-145, `experiments/fallback/`; julia-1.13 711484a23e, TraitWorld 1c45999, product setting, medians, one run, load 1.5–2.1; idiomatic trait code) | a sum over `Vector{Dynamic{S}}`, uniform mixes: 2.5 ns (5 implementations), 5.1 (8), 9.2 (16), 18.5 (64), no allocation; `collect(DynamicItems{S}(v))` from a `Vector{Any}` of 64 types 19.4 ns | the same before the table (julia-1.13 f13117cd74, E-145 r2): 4.5, 11.8, 46.8, 77.0 ns, 3–15 B per element; 72 ns. Again on 6d480d0753 (the C ABI rule, r5): 2.9, 5.0, 10.2, 18.1 ns, 0 B; 19.0 ns | the first use of a type outside the split 9.9–10.6 ms per call signature (compiler C-14); emulated alternatives: a witness carried in the value up to 1.5× faster on 131072 values of 16–64 types, a longer split 190 KB of code per loop at 64 types |
| values kept with their attribute, `Kept{X}`, against `Dynamic{X}`, per element (E-149, `experiments/carry/`; julia-1.13 6d480d0753, TraitWorld after 1d09112, product setting, minimum of 20 runs, one session; idiomatic trait code) | a sum of one operation over `Vector{Kept{S}}`: 1.25 ns (4 types), 4.39 ns (8 types), no allocation; a bounded function over a `Vector{Any}` through the view, items read as `Kept{S}`: 3.04 / 9.58 ns, 80 B per call, none per item | over `Vector{Dynamic{S}}`: 0.96 / 4.19 ns | an operation on a kept value costs 0.2–0.3 ns more; the union of the two forms, tried first, allocated 16 B per item read |

## 3. First calls and sessions

**TraitDifferentialEquations** (`scripts/rows.jl`, each first call timed whole, the garbage collector's time subtracted; big loads = CSV, DataFrames, CairoMakie; 2 runs per order; TraitWorld 226db6a, TraitDifferentialEquations 99393b9; load average 1.1; E-146, `experiments/loadcosts/logs/rowswhole-after-fixes4-gc.log`):

| Row | No loads | Loads before | Loads after |
|---|---|---|---|
| `using TraitDifferentialEquations` | 0.52–0.53 s | 0.68 s | 0.52–0.54 s |
| first Tsit5 solve, a plain function | 25–26 ms | 25–26 ms | 24–26 ms |
| a second model function | 19–21 ms | 19 ms | 23–25 ms |
| a new problem type (then a model type): `@implement` / first solve | 66 / 340–371 ms | 69–70 / 335–338 ms | 70–74 / 338–350 ms |
| first Rodas5 solve | 27–28 ms | 30–32 ms | 29–32 ms |
| a new callback closure / a second | 21 / 9–10 ms | 21–23 / 10 ms | 22–23 / 10–11 ms |
| first gradient / second loss / third loss (another model function) | 68–70 / 45–48 / 89–94 ms | 82–89 / 44–48 / 97 ms | 85–88 / 41–43 / 91–92 ms |
| ForwardDiff's own tag, for comparison | 671–678 ms | 696–703 ms | 686–689 ms |
| a `Float32` state, first solve | 439–441 ms | 446–448 ms | 449–461 ms |

- In the "loads after" column, row 1 runs before the loads; every later row runs after them.
- **Timed whole.** Each first call is timed from before its statement is compiled. Until 2026-10-20 `rows.jl` used `@elapsed`, which compiles its statement before it starts the clock, so the compilation of the call itself was not counted: a new model type's first solve was 44–46 ms inside that window and is 335–371 ms whole. Most of it is the solver compiled for the new key (the worker, about 330 ms; `experiments/loadcosts/logs/rows-none-1-*.log`). `@implement` was timed whole before too (`@eval`).
- **The garbage collector** is subtracted: after the big loads, the first full collection over the larger heap (90–190 ms) falls into whichever row triggers it.
- **The same in every load order,** within the runs' spread, except the first gradient (82–89 ms with loads, 68–70 without; not diagnosed). Before the fixes of E-146, `@implement` took 254–259 ms with the loads before, and four rows differed by load order: plain helpers of TraitWorld and of the demonstrator compiled again after the loads, and a generator's code in TraitWorld's image made invalid by a package loaded before it (E-141, `experiments/loadcosts/README.md`).
- On the previous prototype, a new model type took 0.16–0.23 s to declare.

**TraitMakie** (`scripts/rows.jl`, the rerun; 2 runs per order):

| Row | No loads | Loads before | Loads after |
|---|---|---|---|
| `using TraitMakie` | 486–491 ms | 559–573 ms | 496–509 ms |
| first PNG | 20.0–20.7 ms | 20.4–21.2 ms | 20.8–21.3 ms |
| a new data type (forwarding): `@implement` / first PNG | 22 / 72–74 ms | 45–47 / 81–84 ms | 39–40 / 73–76 ms |
| a new colour type: `@implement` / first PNG | 48 / 57 ms | 88–89 / 55–58 ms | 51 / 57–59 ms |
| render / recolour to a vector / to `:purple` / to a gradient | 8.8 / 81 / 8.6 / 17 ms | 8.5–8.8 / 82–85 / 8.7–8.8 / 16 ms | 8.5–8.8 / 81–82 / 8.5–8.9 / 16 ms |

- **The clean-case regression is gone.** Before (the build of 2026-10-19, n = 1): the forwarding `@implement` took 77 ms and its PNG 107 ms; a colour type's `@implement` 159–311 ms. On an earlier build, before TraitWorld's machinery was compiled by facts: 36 ms and 40 ms. The change in between: the machinery's code in TraitWorld's image (TraitWorld f7aea19). The forwarding type's first PNG (72–74 ms) is still above that earlier build's 40 ms.
- **Before,** the recolour to a vector after the loads took 231 ms (n = 1); now 81–82 ms, as without loads.

**TraitReport** (fresh processes, CSV → PNG, 3 runs; `scripts/measure.sh`):

| Form | Imports | Read | Plot + PNG | Wall |
|---|---|---|---|---|
| (t) TraitCSV, TraitTables, TraitMakie | 0.537–0.545 s | 6–7 ms | 91–92 ms | **0.794–0.805 s** |
| (pt) the same without traits | 0.515–0.519 s | 4 ms | 61–62 ms | **0.771–0.775 s** |
| Python: pandas 3.0.6, matplotlib 3.11.2 (a newly built environment) | 0.393–0.405 s | 1 ms | 95–99 ms | **0.578–0.589 s** |

- **Before** (the build of 2026-10-19): (t) 0.76 s, with plot + PNG 60 ms; (pt) 0.72 s; Python 0.58–0.69 s (an older environment). The trait form's plot + PNG is 30 ms slower in the round: not diagnosed.

Under loads (form (b), a trait module calling upstream CSV.jl and DataFrames, against its plain twin (a′); `scripts/loads.sh`):

| Loaded first | Plain (a′): work | Trait (b): work |
|---|---|---|
| nothing | 248 ms | 41 ms |
| REPL | 247 ms | 41.5 ms |
| OffsetArrays, StatsBase, Unitful | 2,575 ms | 417 ms |
| IntervalArithmetic, Distributions, Interpolations, StaticArrays | 2,560 ms | 344 ms |
| all nine | 3,106 ms | 344 ms |
| `using` (every row) | 0.95–1.01 s | 1.15–1.20 s |

- The trait form's work with StatsBase or Distributions loaded (344–417 ms) is SparseArrays' `vcat`, a standard library's method (§1).
- The trait form's `using` is 0.18–0.20 s above the plain form's.

**The forks** (CSV, DataFrames and Tables ported to traits; `scripts/session.jl` at a REPL on a pty; forks 2 runs, upstream 3; load average 3.4–5.2, so indicative):

| | Forks | Upstream |
|---|---|---|
| imports | 1.89–1.92 s | 0.69–1.19 s |
| read / show / describe | 0.077–0.082 / 0.170–0.175 / 0.144–0.147 s | 3.46–3.95 / 0.98–1.02 / 1.05–1.07 s |
| sort / groupby-combine / join | 0.007 / 0.022–0.023 / 0.224–0.233 s | 1.13–1.20 / 0.74–0.77 / 1.25–1.30 s |
| `String15` read and show | 0.060–0.062 s | 0.21–1.03 s |
| the session without imports | **1.35–1.37 s** | **10.7–11.2 s** |
| wall, start to exit | **3.7–4.0 s** | **12.0–12.8 s** |

- **Before** (the build of 2026-10-19): the session without imports 2.85 s against 10.40 s. The `String15` step then took 1.56–1.67 s, before the `String15` fixes (a workload extension and the first-call check by facts; their contributions were not separated). It now takes 0.06 s.

**A plotting session with upstream packages only** (no trait code; CSV, DataFrames, CairoMakie and seven analysis packages; read, four-axis figure, PNG, edits; plain against the test bed `all`; 3 fresh sessions per cell; `experiments/plotwork/`):

| Load order, rows | `all` saves once | A round under `all` | Break-even |
|---|---|---|---|
| interleaved (as a user works), 10k | 10.0 s (session 35.0 against 43.6 s) | +169 ms (568 against 399 ms) | 59 rounds |
| interleaved, 200k | 10.2 s | +159 ms (4.94 against 4.78 s) | 64 rounds |
| together (plain's best case), 10k | 6.1 s | +148 ms | 42 rounds |
| together, 200k | 6.1 s | +91 ms | 67 rounds |

- What `all` saves is recompilation: 7.8–11.8 s under plain against 0.4–0.5 s. Loading everything first does not avoid it.
- What `all` pays once: loading CairoMakie takes 4.9 against 1.9 s (not diagnosed).
- What `all` pays per round is Makie's machinery, not the data: a figure takes 2.4× as long to build (+95–100 ms), an edit about 2×, a render +30 ms at 10k rows and within 1 % at 200k. The loss per round does not grow with the rows.
- Break-even comes after about a minute of session time at 10k rows, six minutes at 200k. Each package loaded during the session moves it further out.

**The NetworkDynamics workload, upstream code** (no trait code; tier S of [the P1 plan](../plans/2026-10-21-ndport-workload.md): swing equations on 20 vertices, the fixed point, a cascade of 16 line trips, Tsit5 and Rodas5P, symbolic indexing, a GraphMakie PNG, a figure driven by Observables; one fresh session each; julia-1.13 6d480d0753, TraitWorld e9f4bfe, the clones at `upstream`; strict mode off; load average 1–3; U and P0 2 runs, `all` and stock 1 run; E-151, `ndport/logs/p1/`):

| Setting | Loads | First pass | Again | New parameters | New equations (of which compiling) | Session |
|---|---|---|---|---|---|---|
| upstream, patched build | 5.4–5.6 s | 39.7–40.4 s | 0.2 s | 0.7 s | 15.9–16.3 s (15.6–16.0 s) | 69.9–70.7 s |
| the clones, TraitWorld loaded (product setting) | 6.2–6.3 s | 39.9–40.0 s | 0.2 s | 0.7–0.8 s | 16.0–16.2 s (15.8–15.9 s) | 71.1–71.3 s |
| `all` | 11.9 s | 34.5 s | 0.3 s | 0.6 s | 15.1 s (14.8 s) | 72.7 s |
| stock 1.13.2 | 5.7 s | 39.0 s | 0.2 s | 0.6 s | 16.1 s (15.8 s) | 69.6 s |

- **The same results in every setting:** all 25 digests equal, bit for bit (`ndport/scripts/compare_digests.py`).
- **New equations compile the stack again:** a new component function creates 6,810 CodeInstances. About 2,700 are for the fixed point (NonlinearSolve, SciMLBase, NetworkDynamics), 2,700 for the solves (OrdinaryDiffEqCore 545, SciMLBase 461, DiffEqBase 171) and 1,070 for symbolic access. Makie creates almost none: the plotting steps' 0.6 s is NetworkDynamics' and SymbolicIndexingInterface's code reading the state (the attribution run, `ndport/logs/p1-diag/`; its times are not measurements). The component function reaches the network's type, which SciML carries into the problem, the integrator and the solution ([the exploration](../explorations/ndport-principled-traits.md) §1).
- **Under `all`,** the loads take twice as long, and the first pass is 5 s shorter (the first GraphMakie figure 9.7 against 14.6 s). One run: indicative.

## 4. Builds and binaries

- A trimmed TraitMakie binary: 4.07 MB (previous prototype, under the package policy, `--trim=unsafe-warn`). Not rebuilt on the current compiler.
- The system image with the two inliner changes: 200.0 MB against 199.2 MB without them (the build of 2026-10-19).

## 5. Not shown

- **Diagnosis:**
  - the 435 ms upstream CSV + DataFrames pay after the loads under `all` (profiled at ~990 ms on the build of 2026-10-19);
  - what still differs by load order in TraitDifferentialEquations (§3);
  - the trait form's plot + PNG in TraitReport, 91–92 ms against 60 ms on the build of 2026-10-19.
- **Reruns:** TraitReport's form (t) under loads (like for like with the previous prototype's form (t)); the forks' session on a quiet machine; the run-time rows of §2 on the round's build (TDE's script failed to load OrdinaryDiffEq); upstream's full session under `all`; Base's test suite under the facts mode.
- **Untested:** strict mode under `all`; threads; Revise-style edits; composition beyond libraries of a few hundred lines; binaries of TraitDifferentialEquations with ForwardDiff, and of CSV and DataFrames (`--trim=safe`).
- **The "explosion" of compiled code** per type is structural (32 specializations against 1 in a small experiment), unmeasured on a real library.

## Summary: what the evidence shows, and what it does not

The measurements, with builds, baselines and run counts, are in [`evidence.md`](evidence.md); where the costs come from, in [`performance.md`](performance.md). All numbers are from the patched Julia 1.13.2, on one machine, from the measurement round of 2026-10-20 (julia-1.13 3b8085c222, TraitWorld bed3782) unless stated.

**The four steps of section 3:**
- *Step 1, verified* in small cases (S4–S7), with the in-tree facts mode; proved in `../explorations/wrapping-by-facts.md`.
- *Step 2, verified* as a prototype: strict mode refuses winning pirates and nothing else in a real stack (837 pirates by the letter among 65,318 methods, none winning; measured on the previous prototype). Its intended design (pieces 1′, 14, 15, the extension rule, bindings) is not built.
- *Step 3, verified:*
  - the cases that are not fully typed (S1–S3, S8) invalidate on 1.13.2 and not in facts mode; acceptance 23 of 23 in both settings;
  - G2 across package loads, product setting: 0 of 12,368 CodeInstances of the facts owner lost after each of ten loads;
  - **the control:** under `all`, nine unrelated loads cost PlainTables 0 of 244 CodeInstances (plain mode: 14 of 256) and upstream CSV + DataFrames 2 of 3,337 (plain: 561 of 4,684). Load protection is the facts rule's property, for any code.
- *Step 3's cost:* the full BaseBenchmarks under `all`: geometric mean 1.037 against plain; tails up to 27.8×, on containers of `Any`. Before (an earlier build, before parts B–D): 1.016, tails up to about 80×.
- *Step 4:* traits recover the tail tried: the raytrace through `Dynamic` (below; the build of 2026-10-19). `parse_json`'s tail is recovered by typed captures, 1.17× the fixed plain code (an earlier build), a fix plain Julia makes too (`local pos::Int`), so it is no evidence for traits. The fully-typed certificate is built (`fully_typed`, fully typed mode).

**Shown:**
- **The facts mode by itself, on the packages people use.** Upstream CSV.jl and DataFrames compiled in the facts mode (`all`) lose 2 of 3,337 CodeInstances to nine unrelated loads, against 561 of 4,684 in plain mode. Their first work takes 516 ms instead of 3,308 ms, and 435 ms after the loads instead of 4,021 ms. No trait is involved: the guarantee of step 3, and a first-call gain, for code as it is written today.
- **Traits on top, against upstream:** the trait-based ports of CSV.jl and DataFrames run a scripted session in 3.7–4.0 s wall against upstream's 12.0–12.8 s; without imports, 1.35–1.37 s against 10.7–11.2 s (indicative: the machine was loaded). Upstream's full session under `all` is not measured, so the share of each contribution is open.
- **Calls cost what plain calls cost, where types are known.** A typed trait call: 0.8 ns, as plain Julia, in both settings. A `Callable` in `DynamicCall` mode: 3.95 ns, against 0.87 ns for a direct call and 20.3 ns for a dynamic call at `Any`.
- **Untyped trait calls cost about 1.5–1.75× a plain untyped call:** 28.8 ns against 18.9 ns (product setting), 30.8 against 17.6 ns (`all`), 16 bytes per call. Before (julia 61852d8fb1): 115–129 ns against about 55 ns.
- **`Dynamic` values at near plain speed** (the build of 2026-10-19). A sum over `Dynamic{Shape}`: 0.92–1.40 ns per element against plain's 0.87–0.91 with two types and 29.5–33 with four. The raytrace over an open set of primitives: 300–336 ms against plain's 246–259 with two types and 827–882 with four (a `max_methods` effect at four).
- **Traits bring load stability where the facts rule cannot: a package's own extension.** CSV.jl's extension for InlineStrings adds methods to CSV's internal functions. Loaded with DataFrames, it discarded the reader's code: the first read took 2.5 s against 0.19 s. That is a stakeholder's change (3.2), which the facts rule follows. TraitCSV declares an implementation for `String15` in its extension instead, and loading InlineStrings discards none of the reader's code. Measured on the package prototype; not rerun on the compiler. The coding pattern traits bring (extension by implementations, never by methods on a library's internals) is what protects even well-trodden parts of the ecosystem.
- **New trait code costs the same in every load order.** A new problem type in TraitDifferentialEquations (measured as a model type, before W-2): `@implement` 66–74 ms, its first solve 335–371 ms, most of it the solver compiled for the new key (E-146; the first gradient still differs by 15 ms), with CSV, DataFrames and CairoMakie loaded before, after or not at all. A new data type in TraitMakie: `@implement` 22–47 ms, first PNG 72–84 ms (timed inside `@elapsed`, without the call's own compilation). Before (the build of 2026-10-19): 142–164 / 82–133 ms and 77–97 / 89–161 ms.
- **Compiling per key, not per closure.** A new callback closure 12.6–12.8 ms with no loads, 24–25 ms with loads before or after; a second loss closure 18–20 ms in every order; ForwardDiff's own tag 609–791 ms.
- **Sessions.** TraitReport in a fresh process: 0.794–0.805 s; without traits 0.771–0.775 s; Python (pandas 3.0.6, matplotlib 3.11.2) 0.578–0.589 s. Under nine loads, the trait module's work over upstream CSV.jl takes 344 ms against its plain twin's 3,106 ms.
- **The solver's run time** (the build of 2026-10-19). 158 ns per step for Lorenz against OrdinaryDiffEq's 346 ns; 7.5–7.9 µs against 6.1 µs at n = 1,000.
- **AOT:** a trimmed TraitMakie binary of 4.07 MB (built under the previous prototype's policy; not rebuilt on the compiler).

**Not shown, or not yet diagnosed:**
- Upstream CSV + DataFrames still pay 435 ms after the loads under `all` (0.9 ms repeated; plain 4,021 ms). On the build of 2026-10-19, at ~990 ms, it was diagnosed as the plain inference behind run-time `return_type`: its cached answers rest on plain edges at abstract signatures, the loads invalidate them, and plain inference, optimizer included, runs again. This is by design: the answers are plain Julia's, so a load that changes plain inference changes them ([`performance.md`](performance.md)). The 435 ms has not been profiled again.
- A second residue is diagnosed: TraitReport's work after StatsBase or Distributions (344–417 ms against 41 ms). StatsBase loads SparseArrays, a standard library, whose `vcat` for Base's `Number` and `Vector` wins at a fact signature inside `CSV._parse`. The design counts the standard libraries as Julia's own code (§1), so this is a stakeholder's change: not a pirate, not refused by strict mode (`TraitWorld/src/strict.jl:125`). Whether standard libraries should be separate owners is open (`open-issues.md` §1.19).
- TraitDifferentialEquations' first gradient with loads (82–89 against 68–70 ms; E-146); TraitReport's trait plot + PNG (91–92 ms, 60 ms on the build of 2026-10-19). TraitMakie's rows are timed inside `@elapsed`, which leaves out each call's own compilation (E-146): to measure again whole.
- Reruns: TraitReport form (t) under loads; the forks' session on a quiet machine; the run-time rows on the round's build; upstream's full session under `all`; Base's tests under `all`.
- Strict mode under `all`; threads; Revise-style edits; composition beyond libraries of a few hundred lines; binaries of TraitDifferentialEquations with ForwardDiff, and of CSV and DataFrames; the volume of the "explosion" of compiled code on a real library.
