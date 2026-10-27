# The evidence: what is measured, and what is not

A chapter of the [rationale](../design.md): the measurements behind the design, for core developers, as of 2026-10-27.

**The builds.**
- **The measurement round of 2026-10-20:** julia-1.13 3b8085c222 (branch `trait-world-1.13`), TraitWorld bed3782. Every number in this chapter is from it unless its row names another build.
- **The run of 2026-10-27** (E-163, E-164): the round again, on julia-1.13 26a407d988 with TraitWorld main bbfc130 (the heterogeneous rows on TraitWorld 9fd18db, branch `basetraits`); logs in `experiments/overnight-2026-10-21/logs/`, write-up in its README. Where it agrees with the round within the runs' spread, the round's numbers stand and the run is noted; where it does not, its numbers replace the round's, marked with its date, and the round's are kept as "before".
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
| Identical or error (G1) | acceptance G1.1–G1.15, G1.17–G1.29 and G2.1, including the review cases (a `Dynamic` of a known type, an assertion over a run-time site) | `experiments/facts/acceptance_compiler.jl` |

**The control: whose property is load protection.** The same work, then nine unrelated packages loaded (OffsetArrays, StatsBase, Unitful, IntervalArithmetic, Distributions, Interpolations, StaticArrays, CairoMakie, REPL), plain mode against `all` (`demonstrators.log`, the control):

| | plain mode | `all` |
|---|---|---|
| PlainTables + TraitMakie: CodeInstances lost | 14 of 256 (all PlainTables') | **0 of 244** |
| PlainTables' work: first / repeated / after the loads | 104 / 28.6 / 96 ms | 80 / 28.8 / **28** ms |
| upstream CSV + DataFrames: CodeInstances lost (own modules only; Base not counted) | 561 of 4,684 | **2 of 3,337** |
| their work: first / repeated / after the loads | 3,308 / 0.6 / 4,021 ms | 516 / 0.9 / **435** ms |

- Load protection is the facts rule's property, for any code, not traits'.
- **Again on the run of 2026-10-27** (E-163, `control.log`): the same. Plain: 14 of 212 and 562 of 4,694 lost; `all`: 0 of 200 and 2 of 3,337; upstream's work under `all` 502 ms first, 431 ms after the loads.
- **Before** (the build of 2026-10-19), upstream's work under `all` took 722 ms first and 992 ms after the loads. The compiler's own code compiled plainly in every compile queue (julia-1.13 f13117cd74) is the main change in between ([state](../state.md) §4).
- **Diagnosed on the build of 2026-10-19,** when it was ~990 ms: what upstream pays after the loads under `all` (now 435 ms, against 0.9 ms repeated; plain: 4.0 s) is the plain inference behind run-time `return_type`. Its cached answers rest on plain edges at abstract signatures (an `isapprox(::Integer, ::Integer)`, a `quantile!(::AbstractVector, …)`); the loads invalidate them (Unitful's `Colon(::Any, ::Any, ::Quantity)` alone 733 entries); `CSV.read` and `describe` ask again, and plain inference, optimizer included, runs again (70% of the profile then). This is by design: the answers are plain Julia's, so a load that changes plain inference changes them. The optimizer cannot be skipped: without it the answers get wider (CairoMakie's workload then fails) ([`performance.md`](performance.md)). The 435 ms has not been profiled again.
- **A second residue is diagnosed** (§3, TraitReport): StatsBase loads SparseArrays, a standard library, whose `vcat` for Base's `Number` and `Vector` wins at a fact signature inside `CSV._parse`. The design counts the standard libraries as Julia's own code ([glossary](../glossary.md) §1), so this is a stakeholder's change: not a pirate, not refused by strict mode (`TraitWorld/src/strict.jl:125`). Whether standard libraries should be separate owners is open ([`../open-issues.md`](../open-issues.md) §1.19).

**Load protection in the product setting for a wrapped package** (E-153; NetworkDynamics 1.3.0 wrapped whole in `@trait_module`, with Static.jl's promotion fixed; the workload of evidence §3 in order B: CairoMakie, GraphMakie and Observables, 186 packages with their extensions, loaded after the first simulation; one run each; julia-1.13 6d480d0753, TraitWorld e9f4bfe; `ndport/logs/p3-orderB/`):

| Setting | Lost to the load (CodeInstances) | The next simulation pass recompiles |
|---|---|---|
| the unchanged stack (product setting) | 4,062 of 280,083, owner `nothing` (NetworkDynamics 386, NonlinearSolveBase 209, SciMLBase 61) | 4.7 s |
| NetworkDynamics a trait module | 2,884, none of the facts owner | 0.04 s |
| `all` | 1,198 (NetworkDynamics 54; not classified) | none |

- **Strict mode on a wrapped package:** a pirate `sin` on ForwardDiff's duals, defined after the first Rodas5P solve, is followed with strict mode off (84 CodeInstances lost, 75 of the facts owner) and refused with it on (`PirateError`, none lost). The control, the unchanged stack with strict mode on, accepts it (81 lost): the refusal is the trait module's (`ndport/logs/p3-pirate/`).
- Results equal to upstream's bit for bit in every setting.

**The cost of the facts rule on plain code.** The full BaseBenchmarks (4,342 benchmarks), `all` against plain, one run each (`compare-full.log`):
- **Geometric mean 1.037.** Again on the run of 2026-10-27 (E-163): 1.030, with the same tails; that build against the round, plain 1.004 and `all` 0.998, so the build changed neither mode (`experiments/overnight-2026-10-21/logs/compare-*.log`; `micro/randmatmul` there ran with one BLAS thread).
- By group: array 1.043, collection 1.123, sort 1.056, union 1.060, scalar 1.027, simd 1.002, sparse 1.001; io 1.231 (10 benchmarks), problem 1.167, find 1.104.
- **The tails:** at most 27.8× (`filter!` on a `Vector{Any}`). The largest are on containers of `Any` (`filter`, `iterate` on `Dict{Any}` and `IdDict{Any}`: 16–20×), views over ranges (`sumrange_view`: 11×), `issorted` in reverse (8–9×); BaseBenchmarks' raytracer 4.4×, `parse_json` 3.1×.
- **Plain against the earlier plain baseline** (session 28's run, `full0`): 0.943. Plain Julia got faster with this build's general changes, so the 1.037 is against a faster plain.
- **Before** (an earlier build, before parts B–D, `--pkgimages=no`): geometric mean 1.016, 1.064 without `scalar`; tails up to about 80×.
- **The quick subset** (148 benchmarks, chosen to include the tails): geometric mean 1.710 (`quick.log`); 1.641 on the run of 2026-10-27. It is a selection of tails and controls, not the facts mode's cost.

## 2. Run time

Rows marked "2026-10-19" are from the build of 2026-10-19 and were not in the round.

| What | Trait form | Baseline | Notes |
|---|---|---|---|
| a typed trait call (`untyped.jl`, per call) | 0.8 ns, in the product setting and under `all` | plain: 0.8 ns | inlining across owners. **Before** (julia 61852d8fb1, a loop of 16 inside the call): 36–38 ns against 33.8–34.5 ns |
| an untyped trait call (an argument from a `Vector{Any}`, per call; `factscompiler/step3/untyped.jl`): the erased worker's path for an untyped caller (E-163, the run of 2026-10-27; open issues §4 items 35 (P1) and 71) | product setting 59.9 ns; `all` 106.2 ns; 80 bytes per call | plain: 17.6 ns; under `all` 19.6 ns | **Before** (the round, TraitWorld bed3782, through the table of declared implementations): 28.8 / 30.8 ns, 16 bytes; (julia 61852d8fb1, TraitWorld 375a930): 115–129 ns against about 55 ns |
| an untyped call, the type compiled ahead (2026-10-19) | about 14 ns | 15–17 ns | one dispatch to the type's own entry method |
| a `Callable` in `DynamicCall` mode, per call (`callbench.log`) | 3.95 ns; 4.46 ns with worlds alternating (`invoke_in_world` included) | a direct call 0.87 ns; a dynamic call at `Any` 20.3 ns | runs in the caller's world (`:caller_world`). Again on the run of 2026-10-27: 3.68 ns, 4.09 ns alternating; direct 0.87 ns, at `Any` 21.9 ns |
| dynamic call sites in plain code (`sites.jl`, per call) | plain mode / `all`: monomorphic, result asserted 14.2 / 14.2 ns; 4 types, asserted 17.5 / 17.2 ns; 4 types, result untyped 34.7 / 34.8 ns; `push!(::Vector{Any}, x)` 1.6 / **13.6** ns | | the facts tail on containers of `Any`. Again on the run of 2026-10-27: the same within 0.6 ns |
| sum over a vector of `Dynamic{Shape}` (2,000 elements, cache-resident; 2026-10-19) | 0.92–1.40 ns per element | plain, 2 types: 0.87–0.91; plain, 4 types: 29.5–33.0 | held views |
| the same, 10⁶ elements (2026-10-19) | 4.5–5.7 ns | plain, 2 types: 3.9–4.0; 4 types: 33.6–36.2 | memory-bound |
| raytrace over `Dynamic{Scene}` (BaseBenchmarks' raytracer, open set of primitives, `perf_raytrace(5, 256, 4)`; 2026-10-19) | 300–336 ms (2 or 4 implementations) | plain with 2 types: 246–259; with 4: 827–882 | the 4-type baseline is a `max_methods = 3` effect; the split stops at four candidates too |
| raytrace, small case (`perf_raytrace(5, 64, 2)`; 2026-10-19) | 4.7–5.3 ms, 3.8 MB | 3.9–4.7 ms, 3.3 MB | |
| a varargs wrapper in a plain recursion (the review's probe; 2026-10-19) | patched, plain code: 0.36–0.44 ms, 0 bytes | stock 1.13.2: 21.9–23.3 ms, 16.8 MB | the inliner changes, for all code |
| TDE, per solver step, Lorenz (n = 3; E-163, the run of 2026-10-27, one run, `logs/demos/tde-runtime.log`) | problem type 169 ns; plain function 190 ns | OrdinaryDiffEq 336 ns | **before** (2026-10-19): 158–160 / 190–199 / 338–355 ns |
| TDE, per step, a diffusion chain (n = 1,000; E-163) | problem type 7.82 µs; plain function 7.86 µs | OrdinaryDiffEq 6.15 µs | OrdinaryDiffEq's stage loops are fused with `@muladd`; before (2026-10-19): 7.5–7.9 against 6.1 µs |
| idiomatic loops over heterogeneous containers, per element (`experiments/hetero-idiomatic/`, night1; julia-1.13 26a407d988, TraitWorld 9fd18db (branch `basetraits`), medians, one run per setting on a quiet machine, product setting and `all`; E-164) | within the split's four implementations: `filter!` in place over the user's `Vector{Any}` 2.8–3.1 ns; a `Dict{String,Any}` loop 4.4–4.5 ns; a sum over `Dynamic{X}` items, four types, 1.4–2.4 ns | trait code calling Base on the same containers (interop): 40 and 246–285 ns; plain: 2.1 and 2.3 ns (under `all` 33 and 240 ns); the sum in plain Julia with 4 types: 35 ns | the user's container passed as it is costs what the explicit view costs (within 0.4 ns); beyond four implementations the view costs about twice a copy into `Vector{Dynamic{X}}` (64 types: 17.6–18.8 against 8.8–8.9 ns; plain 96–101 ns). **Before** (julia-1.13 3b8085c222, a noisy machine; E-134, E-143, E-144): 64 types 162–181 against 78–84 ns |
| a `Dynamic` operation beyond the split's four implementations, per element (E-145, `experiments/fallback/`; julia-1.13 711484a23e, TraitWorld 1c45999, product setting, medians, one run, load 1.5–2.1; idiomatic trait code) | a sum over `Vector{Dynamic{S}}`, uniform mixes: 2.5 ns (5 implementations), 5.1 (8), 9.2 (16), 18.5 (64), no allocation; `collect(DynamicItems{S}(v))` from a `Vector{Any}` of 64 types 19.4 ns | the same before the table (julia-1.13 f13117cd74, E-145 r2): 4.5, 11.8, 46.8, 77.0 ns, 3–15 B per element; 72 ns. Again on 6d480d0753 (the C ABI rule, r5): 2.9, 5.0, 10.2, 18.1 ns, 0 B; 19.0 ns | the first use of a type outside the split 9.9–10.6 ms per call signature (compiler C-14); emulated alternatives: a witness carried in the value up to 1.5× faster on 131072 values of 16–64 types, a longer split 190 KB of code per loop at 64 types |
| values kept with their attribute, `Kept{X}`, against `Dynamic{X}`, per element (E-149, `experiments/carry/`; julia-1.13 6d480d0753, TraitWorld after 1d09112, product setting, minimum of 20 runs, one session; idiomatic trait code) | a sum of one operation over `Vector{Kept{S}}`: 1.25 ns (4 types), 4.39 ns (8 types), no allocation; a bounded function over a `Vector{Any}` through the view, items read as `Kept{S}`: 3.04 / 9.58 ns, 80 B per call, none per item | over `Vector{Dynamic{S}}`: 0.96 / 4.19 ns | an operation on a kept value costs 0.2–0.3 ns more; the union of the two forms, tried first, allocated 16 B per item read |
| a family member against a member declared on its own, per call (E-156 P13, P15, `experiments/w34-sciml/`; julia-1.13 26a407d988 (W-40), TraitWorld main bbfc130, product setting, strict mode off, hand loop of 10⁶ calls, best of 5, one run, load 1.4–1.7; idiomatic trait code) | a bounded function from a typed plain loop: a family member 0.88 ns, 0 bytes; declared on its own 0.87 ns, 0 bytes. An operation on a `Dynamic` value (form A's `rhs!`): a concrete declared model 2.97 ns (duals 4.32), 0 bytes; a family member 3.01 ns (duals 4.26), 0 bytes | a plain call 2.97 ns (duals 4.34) | before W-40 (julia-1.13 2943086604, TraitWorld f06b82d): a family member 384–456 ns and 208 bytes from a typed loop, 241 ns and 80 bytes on a `Dynamic` value ([lowering §4.6](../reference/lowering.md#46-families)) |
| TDE, move 1 in form B: an `rhs!` call through the problem's bounded `Callable` parameter, per call (E-157, `experiments/w34-sciml/m1/`; julia-1.13 2943086604, TraitWorld c655dde, TDE 29f0641 (branch `w34`), product setting, strict mode off, two runs, load 0.6–1.1; interop) | `Dynamic`: 7.6–7.8 ns, 0 B (`Vector` `p`); 8.4–8.8 ns, 0 B (bits `NamedTuple` `p`); 14.8–15.8 ns, 32 B (a `NamedTuple` holding a vector: boxed). `compiled_for`: 1.5 ns; 3.2–3.3 ns, 0 B (the `NamedTuple` holding a vector) | a direct call 1.5 ns | Tsit5 per step, 40 states: 0 B in both modes except the boxed `p`; a new model compiles no solver code under `Dynamic` |
| TDE, move 2: two callbacks on an integrator, per step above the solve without them (E-158, `experiments/w34-sciml/m2/`; julia-1.13 2943086604, TraitWorld 2e9ed68, TDE cccc517 (branch `w34`), product setting, strict mode off, two runs, load 2.1–2.6 (the user working), two cores; idiomatic trait code) | callbacks and integrators as families: +1,353–1,359 ns, 1,024 B; with the hot members declared on their own: +32–41 ns, 32 B | typed control +2–7 ns, 0 B; a `Vector{Any}` of callbacks +94–100 ns, 32 B | two family members on each callback call (lowering L-37, W-40); the view boxed per call (open issues §4 item 35) |

## 3. First calls and sessions

**TraitDifferentialEquations** (`scripts/rows.jl`, each first call timed whole, the garbage collector's time subtracted; big loads = CSV, DataFrames, CairoMakie; 2 runs per order; E-163, the run of 2026-10-27: julia-1.13 26a407d988, TraitWorld main bbfc130, TraitDifferentialEquations main; load average about 1; `experiments/overnight-2026-10-21/logs/demos/tde-rows.log`):

| Row | No loads | Loads before | Loads after |
|---|---|---|---|
| `using TraitDifferentialEquations` | 0.52–0.54 s | 0.69 s (7.3 s once) | 0.52 s |
| first Tsit5 solve, a plain function | 16.1–16.6 ms | 29.6–31.3 ms | 16.1–16.2 ms |
| a second model function | 16.7–17.1 ms | 17.5–18.9 ms | 35.4–37.0 ms |
| a new problem type: `@implement` / first solve | 123–125 / 324–336 ms | 130–165 / 334–335 ms | 129–130 / 326–330 ms |
| first Rodas5 solve | 25.2–25.3 ms | 31.3–31.8 ms | 30.4–30.7 ms |
| a new callback closure / a second | 23.8–24.0 / 30.1–30.8 ms | 24.3–24.7 / 31.6–32.3 ms | 24.2–24.3 / 30.5–31.7 ms |
| first gradient / second loss / third loss (another model function) | 80.5–80.9 / 49.4–49.9 / 94.0–95.7 ms | 94.1–95.6 / 48.9–50.3 / 95.1–98.1 ms | 92.4 / 48.5–48.7 / 94.3–95.8 ms |
| ForwardDiff's own tag, for comparison | 773–795 ms | 792–810 ms | 785–786 ms |
| a `Float32` state, first solve | 594–598 ms | 602–610 ms | 593 ms |

- **Before** (E-146: TraitWorld 226db6a, TraitDifferentialEquations 99393b9; `experiments/loadcosts/logs/rowswhole-after-fixes4-gc.log`), without loads: `@implement` 66 ms, a second callback closure 9–10 ms, the first gradient 68–70 ms, ForwardDiff's own tag 671–678 ms, a `Float32` state's first solve 439–441 ms, the first Tsit5 solve 25–26 ms; the other rows within the runs' spread. Every order: [the run's README](../../experiments/overnight-2026-10-21/README.md#results-of-e-163-2026-10-27). The rows beyond the spread are [open issue 71](../open-issues.md#4-runtime-and-measurements).
- In the "loads after" column, row 1 runs before the loads; every later row runs after them.
- **Timed whole.** Each first call is timed from before its statement is compiled. Until 2026-10-20 `rows.jl` used `@elapsed`, which compiles its statement before it starts the clock, so the compilation of the call itself was not counted: a new model type's first solve was 44–46 ms inside that window and is 335–371 ms whole. Most of it is the solver compiled for the new key (the worker, about 330 ms; `experiments/loadcosts/logs/rows-none-1-*.log`). `@implement` was timed whole before too (`@eval`).
- **The garbage collector** is subtracted: after the big loads, the first full collection over the larger heap (90–190 ms) falls into whichever row triggers it.
- **The same in every load order,** within the runs' spread, except the first Tsit5 solve with the loads before (30–31 against 16 ms), a second model function after them (35–37 against 17 ms) and the first gradient with loads (92–96 against 81 ms); not diagnosed. Before the fixes of E-146, `@implement` took 254–259 ms with the loads before, and four rows differed by load order: plain helpers of TraitWorld and of the demonstrator compiled again after the loads, and a generator's code in TraitWorld's image made invalid by a package loaded before it (E-141, `experiments/loadcosts/README.md`).
- On the previous prototype, a new model type took 0.16–0.23 s to declare.

**TraitMakie** (`scripts/rows.jl`, each row inside `@elapsed`, so without the call's own compilation; 2 runs per order; E-163, the run of 2026-10-27, julia-1.13 26a407d988, TraitWorld main bbfc130, TraitMakie 9436157; `experiments/overnight-2026-10-21/logs/demos/makie-rows.log`):

| Row | No loads | Loads before | Loads after |
|---|---|---|---|
| `using TraitMakie` | 516–521 ms | 606–619 ms | 518–521 ms |
| first PNG | 21.1–21.2 ms | 21.3–22.0 ms | 20.8–21.6 ms |
| a new data type (forwarding): `@implement` / first PNG | 47 / 109–110 ms | 67 / 76–78 ms | 66 / 78–79 ms |
| a new colour type: `@implement` / first PNG | 46–47 / 76–77 ms | 47–48 / 89–90 ms | 47–48 / 78–80 ms |
| render / recolour to a vector / to `:purple` / to a gradient | 8.7–8.9 / 79–80 / 8.8–9.0 / 19.8–19.9 ms | 8.7–9.2 / 80–82 / 8.8–9.0 / 186–188 ms | 8.7–8.8 / 162–166 / 8.7–8.8 / 20.1–20.2 ms |

- **Before** (the round's rerun, julia-1.13 3b8085c222, TraitWorld bed3782; `experiments/factscompiler/round/logs/makie-rerun.log`): `using` 486–573 ms; the forwarding `@implement` 22 ms without loads and 39–47 ms with them, its first PNG 72–84 ms; a colour type's `@implement` 48–89 ms, its first PNG 55–59 ms; the recolour to a gradient 16–17 ms and to a vector 81–85 ms in every order. The rows beyond the spread are [open issue 71](../open-issues.md#4-runtime-and-measurements).

**TraitReport** (fresh processes, CSV → PNG, 3 runs; `scripts/measure.sh`; the Julia forms on the run of 2026-10-27 (E-163, `logs/demos/report-measure.log`), Python in the round):

| Form | Imports | Read | Plot + PNG | Wall |
|---|---|---|---|---|
| (t) TraitCSV, TraitTables, TraitMakie | 0.564–0.572 s | 7 ms | 96–98 ms | **0.834–0.861 s** |
| (pt) the same without traits | 0.523–0.532 s | 4 ms | 70 ms | **0.740–0.757 s** |
| Python: pandas 3.0.6, matplotlib 3.11.2 (a newly built environment) | 0.393–0.405 s | 1 ms | 95–99 ms | **0.578–0.589 s** |

- **Before:** the round, (t) 0.794–0.805 s with plot + PNG 91–92 ms, (pt) 0.771–0.775 s; the build of 2026-10-19, (t) 0.76 s with plot + PNG 60 ms, (pt) 0.72 s, Python 0.58–0.69 s (an older environment). The trait form's plot + PNG is 26–38 ms above the plain form's: not diagnosed.

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
- Again on the run of 2026-10-27 (E-163, `logs/demos/report-loads.log`): the same within 5% (trait 40.6, 41.2, 400, 343, 333 ms; plain 242, 237, 2,507, 2,528, 2,991 ms).

**The forks** (CSV, DataFrames and Tables ported to traits; `scripts/session.jl` at a REPL on a pty; forks 2 runs, upstream 3; load average 3.4–5.2, so indicative):

| | Forks | Upstream |
|---|---|---|
| imports | 1.89–1.92 s | 0.69–1.19 s |
| read / show / describe | 0.077–0.082 / 0.170–0.175 / 0.144–0.147 s | 3.46–3.95 / 0.98–1.02 / 1.05–1.07 s |
| sort / groupby-combine / join | 0.007 / 0.022–0.023 / 0.224–0.233 s | 1.13–1.20 / 0.74–0.77 / 1.25–1.30 s |
| `String15` read and show | 0.060–0.062 s | 0.21–1.03 s |
| the session without imports | **1.35–1.37 s** | **10.7–11.2 s** |
| wall, start to exit | **3.7–4.0 s** | **12.0–12.8 s** |

- **Not measured on the run of 2026-10-27:** the forked CSV does not precompile on TraitWorld bbfc130 (its column family's member check refuses `Vector{Int64}`; [todo W-14](../record/todo.md)).
- **Before** (the build of 2026-10-19): the session without imports 2.85 s against 10.40 s. The `String15` step then took 1.56–1.67 s, before the `String15` fixes (a workload extension and the first-call check by facts; their contributions were not separated). It now takes 0.06 s.

**Load and first use, SciML and Makie against SciPy and matplotlib** (E-168; one fresh session, from before the process starts to the end of the last step: load, a non-stiff and a stiff solve, a PNG of both, a second model solved and plotted, both again; a bare exit adds about 0.05 s; julia-1.13 252edca933, TraitWorld main bbfc130, strict mode off unless stated; a warm-up and two sessions per setting, agreeing within 1%; two cores; [`experiments/ttfx/README.md`](../../experiments/ttfx/README.md)):

| Setting | Load | First solve | First plot | Second model | **Session** |
|---|---|---|---|---|---|
| Python: SciPy 1.18.1, matplotlib 3.11.2 | 0.45 s | 0.07 s | 0.51 s | 0.24 s | **1.45–1.46 s** |
| stock 1.13.2: OrdinaryDiffEq, CairoMakie (plain code) | 3.54–3.56 s | 3.75–3.76 s | 1.51 s | 0.19 s | **9.16–9.17 s** |
| upstream SciML compiled by facts as trait modules (P6's trees; no trait code) | 4.52–4.53 s | 4.56–4.57 s | 1.47–1.48 s | 0.22 s | **10.92–10.93 s** (strict mode on: 17.6 s) |
| TraitDifferentialEquations and TraitMakie (idiomatic trait code) | 0.81 s | 0.14 s | 0.15 s | 0.056–0.057 s | **1.29–1.30 s** |
| their plain twins, PlainODE and PlainPlots | 0.19 s | 0.22 s | 0.25 s | 0.33 s | **1.13–1.14 s** |

- A small trait core meets Python's session; so does its plain twin. The demonstrators are not ports: they have their own APIs and a fraction of SciML's and Makie's features, and a different, smaller workload (Rodas5, two linear-axis PNGs). The traits' contribution is the second model: 0.056 against 0.33 s. Off the workloads' keys the trait core loses (2.63 against 1.82 s): its solver is compiled for the new key in every session.
- Upstream SciML and Makie take six times Python's session: load (3.5 s, 381 packages) and compilation in the session, which their own workloads do not cover (the first solve's keyword path; E-169).
- With the plotting library loaded after the first solve, the facts-compiled core recompiles nothing (0.04 s); stock Julia recompiles 0.44 s.
- Not yet met: TDE's solver is keyed on the parameters' type, so `Tuple` parameters compile it again in the session (+1.35 s); strict mode adds 6.6 s to the facts-compiled core's load.

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
- **NetworkDynamics' component dynamics behind a trait** (E-152; `ComponentDynamics`, the batches erased; two runs; NetworkDynamics trait-port c9339fd, TraitWorld a373e30): the network's type is the same for both equations; the new equations' steps b–e compile 0.43–0.49 s against 15.0 s, and create no CodeInstance in SciML or SymbolicIndexingInterface (upstream ~2,300). The cost: a Tsit5 + Rodas5P solve in steady state 46.8 against 15.3 ms, a right-hand side 32 allocations and 3.1 µs against 0 and 0.5 µs: each crossing into a family member from trait code ~13 allocations and 0.8 µs. After open issue 48's TraitWorld work (TraitWorld 3bebf13; two runs): the steady-state solve 33.1–41.2 ms, a right-hand side 5 allocations and 208 bytes, a crossing ~390 ns and 1 allocation; changed b–e still 0.49 s. Results bit-equal to upstream.
- **A graph trait** (E-154; `GraphInterface` in Graphs, read by NetworkDynamics' index manager; TraitWorld 3bebf13; three runs): networks on `GenericGraph`, `GenericDiGraph`, `SimpleGraph{Int32}` and four more graph types build and give `SimpleGraph`'s results, where upstream raises `MethodError`; the steady state unchanged (d 33.1 against 33.4 ms); a new graph type still compiles 17.7 s, since the graph's type stays in the network's.
- **The SciML core wrapped inside out** (E-155; seven steps, strict mode on, TraitWorld 3bebf13; one run each): results bit-equal to upstream at every step. The steady-state solve doubles while SciMLBase is wrapped and its hot callers are plain (29.2 against 15.0 ms; facts §6.3, F-17) and returns once DiffEqBase is wrapped (16.0–16.2 ms). The first simulation 28.9 against 36.4 s with NetworkDynamics wrapped alone (upstream 21.5 s). Order B: no code of the facts owner lost; the next pass recompiles nothing (upstream 4.7 s).
- **The two tracks merged** (E-165; P4's NetworkDynamics with G3 on P6's SciML core; julia-1.13 2943086604, TraitWorld c655dde (pinned, `TraitWorld-port`), P1's load order, one run per check (two for the reference), load 1.2–3.3): results bit-equal, strict mode on and off; new equations recompile 0.56 s (P6's core alone 15.7 s); the first simulation 31.0–32.7 s (P4 alone 39.1 s, upstream 21.5 s); the session 65.9 s (upstream 70); the steady-state solve P4's, 34.7 ms (35.9–37.8 with strict mode on), against P6 alone 16.8 ms and upstream 15.3 ms: the batches' crossings (P4-1) stay.
- **The batches' crossings made cheap** (E-166, P4 step 3a; W-49 in TraitWorld, `VertexDynamics`/`EdgeDynamics`; julia-1.13 2943086604, TraitWorld w49 (3ae361c, c655dde plus W-49), setting M, P1's load order, two cores, two runs strict off, two strict on): results exactly equal; a crossing into a batch 36–48 ns (before 165–182); a right-hand side 1,238–1,312 ns (before 1,834; typed batches 623); the steady-state solve 29.5 ms (before 34.7; P6 alone 16.8; upstream 15.3); new equations 0.55 s.
- **Threads in the facts mode** (E-152, S0, the wrapped package without traits): `ThreadedExecution` 43.8 µs and 5.2 kB per right-hand side against 9.2 µs and 2.8 kB upstream. One measurement; not diagnosed.
- **NetworkDynamics wrapped as a trait module** (E-153, one run; Static.jl's promotion fixed): the steady state is faster (a Tsit5 and a Rodas5P solve with the cascade, 15.3 against 19.7 ms); the first simulation slower (steps a–e 37.8 against 21.5 s: the code it reaches is compiled by facts in the session, the first fixed point 21.9 against 6.5 s); the new equations the same (15 s). With the workload's own module a trait module too, the first plot takes 48.5 against 16.0 s (Makie compiled by facts in the session).

## 4. Builds and binaries

- A trimmed TraitMakie binary: 4.07 MB (previous prototype, under the package policy, `--trim=unsafe-warn`). Not rebuilt on the current compiler.
- The system image with the two inliner changes: 200.0 MB against 199.2 MB without them (the build of 2026-10-19).

## 5. Not shown

- **Diagnosis:**
  - the 435 ms upstream CSV + DataFrames pay after the loads under `all` (profiled at ~990 ms on the build of 2026-10-19);
  - what still differs by load order in TraitDifferentialEquations (§3);
  - the trait form's plot + PNG in TraitReport, 96–98 ms on the run of 2026-10-27 against 60 ms on the build of 2026-10-19;
  - the first calls slower in the demonstrators on the run of 2026-10-27 ([open issue 71](../open-issues.md#4-runtime-and-measurements)).
- **Reruns:** TraitReport's form (t) under loads (like for like with the previous prototype's form (t)); the forks' session on a quiet machine (once the forks load on the current TraitWorld); the raytrace rows of §2 on a current build; upstream's full session under `all`; Base's test suite under the facts mode.
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
- *Step 3's cost:* the full BaseBenchmarks under `all`: geometric mean 1.037 against plain (1.030 on the run of 2026-10-27); tails up to 27.8×, on containers of `Any`. Before (an earlier build, before parts B–D): 1.016, tails up to about 80×.
- *Step 4:* traits recover the tail tried: the raytrace through `Dynamic` (below; the build of 2026-10-19). `parse_json`'s tail is recovered by typed captures, 1.17× the fixed plain code (an earlier build), a fix plain Julia makes too (`local pos::Int`), so it is no evidence for traits. The fully-typed certificate is built (`fully_typed`, fully typed mode).

**Shown:**
- **The facts mode by itself, on the packages people use.** Upstream CSV.jl and DataFrames compiled in the facts mode (`all`) lose 2 of 3,337 CodeInstances to nine unrelated loads, against 561 of 4,684 in plain mode. Their first work takes 516 ms instead of 3,308 ms, and 435 ms after the loads instead of 4,021 ms. No trait is involved: the guarantee of step 3, and a first-call gain, for code as it is written today.
- **Traits on top, against upstream:** the trait-based ports of CSV.jl and DataFrames run a scripted session in 3.7–4.0 s wall against upstream's 12.0–12.8 s; without imports, 1.35–1.37 s against 10.7–11.2 s (indicative: the machine was loaded). Upstream's full session under `all` is not measured, so the share of each contribution is open.
- **Calls cost what plain calls cost, where types are known.** A typed trait call: 0.8 ns, as plain Julia, in both settings. A `Callable` in `DynamicCall` mode: 3.95 ns, against 0.87 ns for a direct call and 20.3 ns for a dynamic call at `Any`.
- **Untyped trait calls cost 3.4–5.4× a plain untyped call on the erased worker's path:** 59.9 ns against 17.6 ns (product setting), 106.2 against 19.6 ns (`all`), 80 bytes per call (the run of 2026-10-27; open issue 71). Before, through the table of declared implementations (the round): 28.8 and 30.8 ns, 16 bytes.
- **`Dynamic` values at near plain speed** (the build of 2026-10-19). A sum over `Dynamic{Shape}`: 0.92–1.40 ns per element against plain's 0.87–0.91 with two types and 29.5–33 with four. The raytrace over an open set of primitives: 300–336 ms against plain's 246–259 with two types and 827–882 with four (a `max_methods` effect at four).
- **Traits bring load stability where the facts rule cannot: a package's own extension.** CSV.jl's extension for InlineStrings adds methods to CSV's internal functions. Loaded with DataFrames, it discarded the reader's code: the first read took 2.5 s against 0.19 s. That is a stakeholder's change (3.2), which the facts rule follows. TraitCSV declares an implementation for `String15` in its extension instead, and loading InlineStrings discards none of the reader's code. Measured on the package prototype; not rerun on the compiler. The coding pattern traits bring (extension by implementations, never by methods on a library's internals) is what protects even well-trodden parts of the ecosystem.
- **New trait code costs about the same in every load order.** A new problem type in TraitDifferentialEquations: `@implement` 123–165 ms, its first solve 324–336 ms, most of it the solver compiled for the new key, with CSV, DataFrames and CairoMakie loaded before, after or not at all (the run of 2026-10-27; three rows differ by load order, §3). A new data type in TraitMakie: `@implement` 47–67 ms, first PNG 76–110 ms (timed inside `@elapsed`, without the call's own compilation). Slower than on the round's builds (`@implement` 66–74 and 22–47 ms; open issue 71).
- **Compiling per key, not per closure.** A new callback closure 24–25 ms, a second 30–32 ms; a second loss closure 49–50 ms; ForwardDiff's own tag 773–810 ms; in every load order (the run of 2026-10-27).
- **Sessions.** TraitReport in a fresh process: 0.834–0.861 s; without traits 0.740–0.757 s (the run of 2026-10-27); Python (pandas 3.0.6, matplotlib 3.11.2) 0.578–0.589 s (the round). Under nine loads, the trait module's work over upstream CSV.jl takes 333–344 ms against its plain twin's 2,991–3,106 ms.
- **The solver's run time** (the run of 2026-10-27). 169 ns per step for Lorenz against OrdinaryDiffEq's 336 ns; 7.8 µs against 6.15 µs at n = 1,000.
- **AOT:** a trimmed TraitMakie binary of 4.07 MB (built under the previous prototype's policy; not rebuilt on the compiler).

**Not shown, or not yet diagnosed:**
- Upstream CSV + DataFrames still pay 435 ms after the loads under `all` (0.9 ms repeated; plain 4,021 ms). On the build of 2026-10-19, at ~990 ms, it was diagnosed as the plain inference behind run-time `return_type`: its cached answers rest on plain edges at abstract signatures, the loads invalidate them, and plain inference, optimizer included, runs again. This is by design: the answers are plain Julia's, so a load that changes plain inference changes them ([`performance.md`](performance.md)). The 435 ms has not been profiled again.
- A second residue is diagnosed: TraitReport's work after StatsBase or Distributions (344–417 ms against 41 ms). StatsBase loads SparseArrays, a standard library, whose `vcat` for Base's `Number` and `Vector` wins at a fact signature inside `CSV._parse`. The design counts the standard libraries as Julia's own code (§1), so this is a stakeholder's change: not a pirate, not refused by strict mode (`TraitWorld/src/strict.jl:125`). Whether standard libraries should be separate owners is open (`open-issues.md` §1.19).
- TraitDifferentialEquations' first gradient with loads (92–96 against 81 ms), and the first calls slower on the run of 2026-10-27 (open issue 71); TraitReport's trait plot + PNG (96–98 ms, 60 ms on the build of 2026-10-19). TraitMakie's rows are timed inside `@elapsed`, which leaves out each call's own compilation (E-146): to measure again whole.
- Reruns: TraitReport form (t) under loads; the forks' session on a quiet machine; the raytrace rows on a current build; upstream's full session under `all`; Base's tests under `all`.
- Strict mode under `all`; threads; Revise-style edits; composition beyond libraries of a few hundred lines; binaries of TraitDifferentialEquations with ForwardDiff, and of CSV and DataFrames; the volume of the "explosion" of compiled code on a real library.
