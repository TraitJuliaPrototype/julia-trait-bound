# The evidence: what is measured, and what is not

A chapter of [The implementation in detail](implementation.md): the current measurements behind the design, for core developers, as of 2026-10-19 (final build: julia-1.13 61852d8fb1, TraitWorld 375a930; a89a91629a adds only `tw-build.sh`). [`implementation.md` §8](implementation.md#8-what-the-evidence-shows-and-what-it-does-not) summarizes this chapter; [`performance.md`](performance.md) says where the costs come from. The raw numbers, with every intermediate build, are in the session note `../../session-notes/2026-10-18-29-reviews-and-decisions.md`. Numbers of earlier builds and prototypes: [`../record/design-history.md`](../record/design-history.md), [`../design-findings.md`](../design-findings.md) and the demonstrators' READMEs. A number marked "previous prototype" was measured on the package prototype, before the facts mode moved into Julia's compiler, and has no current counterpart yet.

**How to read the numbers.**
- One machine, shared with other jobs: one Julia process at a time, niced.
- Fresh processes, unless a row says "at the REPL".
- Runs per cell: 1–3. Rows marked *n = 1* are single runs. Repeated runs varied by about 5% on a busy machine; treat differences under 10% as noise.
- "Plain" is the same code without traits, on the patched build in plain mode. The two inliner changes apply to all code, so patched-plain is not stock: stock numbers use the stock 1.13.2 binary and say so.

## 1. The guarantee

| Claim | Evidence | Where |
|---|---|---|
| Step 1: fully typed code is invalidated only by stakeholders and pirates | a stakeholder's method (S4), a winning pirate (S5) and a redefined `const` (S7) invalidate code at concrete signatures; a losing pirate (S6) never does; on 1.13.2 and with the in-tree facts mode | `experiments/facts/framing/`, `../reviews/2026-10-18-framing-and-motivation.md` §0; proofs in `../explorations/wrapping-by-facts.md` |
| Step 2: strict mode refuses winning pirates and nothing else | 65,318 methods of CSV, DataFrames and CairoMakie checked; 837 pirates by the letter; none winning, none refused; 0.54 s extra on a 4.1 s load (previous prototype) | `experiments/facts/g2strict` |
| Step 3: the facts rule keeps all code valid | the four cases that are not fully typed (S1–S3, S8) invalidate on 1.13.2 and not in facts mode; acceptance 19/19 | `experiments/facts/acceptance_compiler.jl` |
| Identical or error (G1) | acceptance G1.1–G1.19, including the review cases (a `Dynamic` of a known type, an assertion over a run-time site) | as above |

**The control: whose property is load protection.** The same work, then nine unrelated packages loaded (OffsetArrays, StatsBase, Unitful, IntervalArithmetic, Distributions, Interpolations, StaticArrays, CairoMakie, REPL), plain mode against `all`:

| | plain mode | `all` |
|---|---|---|
| PlainTables + TraitMakie: CodeInstances lost | 14 of 218 | **0 of 206** |
| their work after the loads (repeated: 27.5 / 27.8 ms) | 96.1 ms | 29.4 ms |
| upstream CSV + DataFrames: CodeInstances lost (own modules only; Base not counted) | 570 of 4,712 | **2 of 3,340** |
| their first work / repeated / after the loads | 3,627 / 0.6 / 4,009 ms | 722 / 0.8 / **992** ms |

- Load protection is the facts rule's property, for any code, not traits'.
- **Diagnosed:** upstream pays ~990 ms after the loads under `all` (plain: 4.0 s) for the plain inference behind run-time `return_type`. Its cached answers rest on plain edges at abstract signatures (an `isapprox(::Integer, ::Integer)`, a `quantile!(::AbstractVector, …)`); the loads invalidate them (Unitful's `Colon(::Any, ::Any, ::Quantity)` alone 733 entries); `CSV.read` and `describe` ask again, and plain inference, optimizer included, runs again (70% of the profile). This is by design: the answers are plain Julia's, so a load that changes plain inference changes them. The optimizer cannot be skipped: without it the answers get wider (CairoMakie's workload then fails) ([`performance.md`](performance.md)). Another residue of this kind is diagnosed (§3, TraitReport): StatsBase loads SparseArrays, a standard library, whose `vcat` for Base's `Number` and `Vector` wins at a fact signature inside `CSV._parse`. The design counts the standard libraries as Julia's own code ([`implementation.md`](implementation.md#1-terms) §1), so this is a stakeholder's change: not a pirate, not refused by strict mode (`TraitWorld/src/strict.jl:125`). Whether standard libraries should be separate owners is open ([`../open-issues.md`](../open-issues.md) §1.19).

**The cost of the facts rule on plain code** (`all`, on an earlier build, before parts B–D): BaseBenchmarks geometric mean 1.016, 1.064 without `scalar`; concrete groups 1.00–1.09; `io` 1.32; tails up to about 80× on containers of `Any`, abstract element types and small-union broadcasts. One run, `--pkgimages=no`. **To rerun** on the current compiler: the inliner changes apply under `all` too.

## 2. Run time

| What | Trait form | Baseline | Notes |
|---|---|---|---|
| sum over a vector of `Dynamic{Shape}` (2,000 elements, cache-resident) | 0.92–1.40 ns per element | plain, 2 types: 0.87–0.91; plain, 4 types: 29.5–33.0 | held views |
| the same, 10⁶ elements | 4.5–5.7 ns | plain, 2 types: 3.9–4.0; 4 types: 33.6–36.2 | memory-bound |
| raytrace over `Dynamic{Scene}` (BaseBenchmarks' raytracer, open set of primitives, `perf_raytrace(5, 256, 4)`) | 300–336 ms (2 or 4 implementations) | plain with 2 types: 246–259; with 4: 827–882 | the 4-type baseline is a `max_methods = 3` effect; the split stops at four candidates too |
| raytrace, small case (`perf_raytrace(5, 64, 2)`) | 4.7–5.3 ms, 3.8 MB | 3.9–4.7 ms, 3.3 MB | |
| a typed call `total(x, 16)` | 36–38 ns | the same loop with `len` an argument: 33.8–34.5 ns; with a literal 16: 29.3 | the literal unrolls the loop; the fair baseline is the argument |
| an untyped call (`Any` argument) | 115–129 ns | about 55 ns for a plain untyped call | two dynamic dispatches and a boxed trait object |
| a `Callable` in `DynamicCall` mode, per call | 4.0–4.4 ns | | an earlier prototype on stock Julia, not remeasured (`../design-findings.md` §12) |
| a varargs wrapper in a plain recursion (the review's probe) | patched, plain code: 0.36–0.44 ms, 0 bytes | stock 1.13.2: 21.9–23.3 ms, 16.8 MB | the inliner changes, for all code |
| TDE, per solver step, Lorenz (n = 3) | model type 158–160 ns; plain function 190–199 | OrdinaryDiffEq 338–355 ns | |
| TDE, per step, a diffusion chain (n = 1,000) | 7.5–7.9 µs | OrdinaryDiffEq 6.1 µs | OrdinaryDiffEq's stage loops are fused with `@muladd` |

## 3. First calls and sessions

**TraitDifferentialEquations** (`scripts/rows.jl`; big loads = CSV, DataFrames, CairoMakie; *n = 1* per order):

| Row | No loads | Loads before | Loads after |
|---|---|---|---|
| `using TraitDifferentialEquations` | 0.47 s | 7.28 s (one run; 1.29–1.39 s in other runs: a cache rebuilt once, stacked environments) | 0.47 s |
| first Tsit5 solve, a plain function | 10.0 ms | 27.8 ms | 9.9 ms |
| a second model function | 9.8 ms | 11.2 ms | 27.6 ms |
| a new model type: `@implement` / first solve | 142 / 82 ms | 164 / 133 ms | 149 / 89 ms |
| first Rodas5 solve | 16.6 ms | 17.0 ms | 16.8 ms |
| a new callback closure / a second | 12.4 / 5.2 ms | 24.0 / 5.4 ms | **170.7** / 5.2 ms |
| first gradient / second loss / third loss | 29 / 17 / 62 ms | 34 / 18 / 63 ms | 34 / 17 / 62 ms |
| ForwardDiff's own tag, for comparison | 0.70 s | 0.73 s | 0.72 s |
| a `Float32` state, first solve | 0.46 s | 0.45 s | 0.45 s |

- On the previous prototype, a new model type took 0.16–0.23 s to declare and 33–44 ms to solve first. The first solve has not reached 33–44 ms on the compiler yet.
- Row 4 (a new callback closure) after the loads: 171 ms against 12 ms without (24 ms in an earlier run): not diagnosed.

**TraitMakie** (`scripts/rows.jl`, *n = 1* per order):

| Row | No loads | Loads before | Loads after |
|---|---|---|---|
| `using TraitMakie` | 476 ms | 538 ms | 474 ms |
| first PNG | 20.5 ms | 20.9 ms | 20.8 ms |
| a new data type (forwarding): `@implement` / first PNG | 77 / 107 ms | 97 / 89 ms | 96 / 161 ms |
| a new colour type: `@implement` / first PNG | 171 / 96 ms | 311 / 98 ms | 159 / 101 ms |
| render / recolour to a vector / to `:purple` / to a gradient | 8.8 / 102 / 9.0 / 18 ms | 8.8 / 84 / 9.0 / 18 ms | 9.0 / 231 / 8.6 / 19 ms |

- **A clean-case regression:** on an earlier build of the compiler, before TraitWorld's machinery was compiled by facts, the forwarding `@implement` took 36 ms and its PNG 40 ms. The likely cause is the cost of compiling the machinery by facts, not yet measured by owner.

**TraitReport** (fresh processes, 3 runs):

| Form | Imports | Read | Plot + PNG | Wall |
|---|---|---|---|---|
| (t) TraitCSV, TraitTables, TraitMakie | 0.53–0.54 s | 6–7 ms | 60 ms | **0.76 s** |
| (pt) the same without traits | 0.49–0.50 s | 4 ms | 60 ms | **0.72 s** |
| Python, pandas + matplotlib (measured earlier; not rerun) | | | | 0.58–0.69 s |

Under loads (form (b) against its plain twin (a′), `scripts/loads.sh`): the trait form's work 41 ms (none, REPL), 333–410 ms with StatsBase or Distributions loaded (SparseArrays' `vcat`, a standard library's method, §1), 338–342 ms with all nine; the plain form 237–3,086 ms. The trait form's `using` is 0.18–0.20 s above the plain form's.

**The forks** (CSV, DataFrames and Tables ported to traits; `scripts/session.jl` at a REPL on a pty, 3 runs each):

| | Forks | Upstream |
|---|---|---|
| imports | 1.70–2.09 s | 1.33–1.42 s |
| read / show / describe | 0.075 / 0.17 / 0.14–0.19 s | 3.4 / 0.97 / 1.0 s |
| sort / groupby-combine / join | 0.006 / 0.021 / 0.21 s | 1.15 / 0.77 / 1.24 s |
| `String15` read and show | 1.56–1.67 s (before the `String15` fixes; not rerun) | 0.19 s |
| the session without imports | **2.85 s** | **10.40 s** |

The forks' first `String15` read alone (a script) takes 0.04 s with the `String15` fixes (a workload extension and the first-call check by facts; their contributions were not separated), against 1.74 s without them. The session harness has not been rerun with them.

## 4. Builds and binaries

- A trimmed TraitMakie binary: 4.07 MB (previous prototype, under the package policy, `--trim=unsafe-warn`). Not rebuilt on the current compiler.
- The system image with the two inliner changes: 200.0 MB against 199.2 MB without them.

## 5. Not shown

- **Diagnosis:** TDE row 4 after loads; the clean-case `@implement` regression.
- **Reruns:** Python's baseline; TraitReport's form (t) under loads (like for like with the previous prototype's form (t)); the forks' session harness after the `String15` fixes; BaseBenchmarks under `all` on the current compiler; Base's test suite under the facts mode.
- **Untested:** strict mode under `all`; threads; Revise-style edits; composition beyond libraries of a few hundred lines; binaries of TraitDifferentialEquations with ForwardDiff, and of CSV and DataFrames (`--trim=safe`).
- **The "explosion" of compiled code** per type is structural (32 specializations against 1 in a small experiment), unmeasured on a real library.
