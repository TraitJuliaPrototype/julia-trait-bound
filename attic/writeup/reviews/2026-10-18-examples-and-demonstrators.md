# Review: the examples and demonstrators of the trait-bound Julia design

2026-10-18 (session 29). An independent critical review of every example, snippet, acceptance case, recovery case, rewrite and port in the design repository and its sub-repositories, read against the current design (`writeup/design.md`, the four-step framing), the register and the open issues.

**The user's criterion for this review.** Performance goals are not to be read literally. What matters is the user's workflow: an import may take seconds if the work after it is instantaneous; badly written code may run slower if the compiler says how to make it fast. Every appraisal below uses that criterion.

**Marks.** *Verified* means read in the source at the cited line, or seen in a recorded measurement. *Reasoning* means my inference. No Julia was run: the shared lock was busy with test runs, and nothing below needed a run to settle. No repository file was changed. Scratch: `/tmp/claude-1000/review-examples/`.

**Terms** as in `design.md` §1: fact, run-time site, key, worker, entry, `Dynamic{X}`, fully typed, strict mode, facts mode (`all`, `traits`).

---

## 0. Summary verdict

1. **The catalogue is broad at the small end and thin at the two ends the design now rests on.** There are about 60 small tests, 16 acceptance cases, 48 adversarial cases, four recovery variants, three rewrites with baselines and one paused port. There is **no example of the strict tier refusing a real pirate in a demonstrator** (TDE row 8's second half, `TraitDifferentialEquations/README.md:55`: "Strict mode's refusal: deferred"), **no example of the fully-typed certificate** (decided, not built, `design.md:311`), and **no example of a warning that teaches** on badly written plain code (the one concrete-mode example is a four-package toy from the TraitRegions era, `experiments/world/concrete/`). These are the three claims the four-step framing leads with.
2. **The evidence for steps 1 and 3 of the framing lives outside the repository.** `design.md:78` and `:333` cite `inval.jl` (S1–S8). That file exists only at `/tmp/claude-1000/review-framing/inval.jl` (*Verified*: `find` over the repository finds no `inval*.jl` but Julia's own `Compiler/test/invalidation.jl` and two unrelated scripts; the framing review names `/tmp/…` as its scratch, `reviews/2026-10-18-framing-and-motivation.md:5, :373`). `/tmp` is a tmpfs. The eight cases should become an acceptance file today.
3. **Under the user's criterion the demonstrators mostly pass, and for a different reason than their READMEs say.** Imports of 0.3–3 s followed by work in tens of milliseconds is exactly what the user accepts. The rows that measure this (work after `using`, first calls of new closures and types, work under loads) are the right rows. The rows that chase Python's wall time in a fresh process (TraitReport row 1, forks "start" and "imports") are the wrong headline and the READMEs lean on them. The attribution problem found by the two earlier reviews stands: every "survives loads" number is the facts mode's until the plain baselines run under `all` (`design.md:352`).
4. **The REPL case, the user's actual workflow, is measured only for the paused port.** The three demonstrators run scripts with `--startup-file=no` (fresh-eye B1, still true: `TraitDifferentialEquations/scripts/rows.jl`, `TraitMakie/scripts/rows.jl`, `TraitReport/scripts/measure.sh`). The one REPL-driven harness is `forks/scripts/measure_session.sh`. The known REPL cost (5.9 s for a first new key without the system image) is an artefact of the package form, expected to vanish with (B), and not yet shown to vanish.
5. **About a third of the catalogue is history** and still presented beside current numbers: everything in `experiments/interfaces` and `experiments/world` (projections, wrappers, sealing, doors, the filter), the system-image rows, the view-cache rows, the witness-table and key-branch numbers, the `sealed_call`-dependent trait raytrace, and both rewrite explorations' sketches. Section 3 lists them.
6. **The ten examples I would build first** are in section 4. The first three cost a day each and remove most of the uncertainty: the plain baselines under `all`; S1–S8 and the "before"-order pirate as acceptance files, with the strict tier on; and a REPL row for each demonstrator with a new type, a new closure and a Revise-style edit.

---

## 1. The catalogue

Status codes: **idea** (prose only), **sketch** (code in a note, not run), **test** (in a test suite), **script** (a measurement script with recorded numbers), **row** (a demonstrator row with a measured cell), **history** (built for a superseded design; numbers no longer current).

### 1.1 Small snippets and unit examples (TraitWorld tests, notes)

| Example | Shows | Where | Status | What the evidence shows today |
|---|---|---|---|---|
| The library and its user: `Columns`, `Measurements` (forwarding), `Ramp` (own methods), `meandiff` over two keys | keys; forwarding shares code; a type that implements gets its own copy | `notes/1-overview.md:112–158`; `TraitWorld/test/runtests.jl:63` ("M1: the note's example") | test | runs verbatim from images (`experiments/world/README.md:70`); typed calls 33 ns against 30 plain (`design.md:173`) *Verified* |
| Rule 2 escapes: `size(t)`, `typeof(t)`, `t.field`, a closure capturing `t`, reported with lines | definition checking; "code must not depend on the user's type" | `runtests.jl:78, :209, :831`; `experiments/world/defcheck_demo.jl` | test, script | errors at the library's build before any type conforms; "under 200 ms" for five functions (`notes/2-design-choices.md:191–194`) |
| Ownership: a stranger's implementation, `Base.size` for `Vector{Float32}`, a `Union` with a foreign type | rule 2 (ownership), pirates refused in trait modules | `runtests.jl:119, :729` | test | the lookups follow the method's own signature (`notes/4-details.md:38–40`) |
| Types first, then traits; adopting a trait method keeps existing calls (a differential test over 13 values) | dispatch tier; "adopt one function at a time" | `runtests.jl:191, :329, :380` | test | holds; the tier is imitated by reflection (`_plain_method`), a soundness surface the implementation review flagged (`reviews/2026-10-18-implementation-shape.md` P4) |
| `Callable` at two signatures; modes `CompiledCall`/`DynamicCall`, caller override | functions from above; the two modes the user kept | `runtests.jl:199, :398, :655`; `notes/4-details.md:476–491` | test | 4 ns per dynamic call (`experiments/world/README.md`, M5). **No demonstrator uses `CompiledCall`** (*Verified*: grep over the four demonstrators' `src` finds `DynamicFn`/`dynamic_fn` only) |
| A winning pirate is followed; a pirate behind a `catch` | rule P, G1 | `runtests.jl:422, :581`; `acceptance.jl` G1.4 | test | followed, result equals plain Julia's |
| Strict mode: `abs2(::Float64)` refused; a gap-filling pirate refused; the owner (`@eval SU …`) accepted; a delegate accepted | step 2 of the framing | `TraitWorld/test/strict.jl:42` (32 checks); `explorations/strict-mode.md` §2a | test | all pass; the safety net never fired. Every refused case is synthetic |
| An override after a conformance is refused; family members fixed at first use | §4.4 | `test/runtime.jl:154`; `test/keys_syntax.jl:123` | test | holds; the message still says "or in its block" (`open-issues.md` §1.17) |
| Concreteness opt-in per trait (`@concrete_only`, `@warn_on_abstract`) | §4.3 | `test/keys_syntax.jl:174` | test | tested in the two-macro spelling; the one-declaration form is not built |
| Fields and lenses; writable fields; `@const` | reference layout | `test/fields.jl:65`; `experiments/lens/layout.md` | test, script | loops at plain speed with alias metadata; without it 5× (`layout.md:21–22`) |
| Trait parameters (associated types) defined by fields | §4.1 | `test/params.jl:55`; `test/runtime.jl:134` | test | holds |
| Results like the input (`Like{t}`, `withfields`, `Self` constructors) | §4.7 | `test/like.jl:81` | test | only `Self` reaches a demonstrator (`TraitCSV/src/CSVCore.jl:20`); `Like{t}` and `withfields` are tests only (`design.md:214`) |
| `Dynamic` values; containers in functions; supertrait views | §4.5 | `test/dynamic.jl:78, :133` | test | witness tables now off by default; the world-age defect verified in `reviews/2026-10-18-design-and-fixes.md` A1 |
| Printing by bound and key; hidden machinery frames; `conforms(T, X)` | readable types | `test/printing.jl:33–64` | test | type printers through Julia piece 17; `conforms` used by no demonstrator |
| Keyword, default and vararg arguments (`colzscore`) | boundary principle | `runtests.jl:629`; `notes/4-details.md:513–527` | test | holds |
| Facts at tuples with unions of concrete elements (iteration with missing values) | rule 1's fact signature | `runtests.jl:775`; `explorations/dataframes-port-lessons.md` §1.8 | test | `describe` on a column with missing values 0.3 ms instead of 0.13 s |
| `return_type` from CodeInstances; a predicate's conditional is no constant | A3 | `runtests.jl:765` | test | holds |
| Capability traits over Base (`Indexable`, `Iterable`, `HasLength`); accidental conformance table | conformance declared, never derived | `runtests.jl:270`; `experiments/world/README.md` M2 table | test, history (spelling) | `Int`, `Char`, `Pair`, `String`, `Dict`, `Matrix` would conform structurally: the argument for declaration |
| `verify_main` on keyword entries and on `Dynamic` targets | AOT target lists | `runtests.jl:463, :717`; `test/verify_dynamic.jl:36` | test | in a session it cannot see workers behind the policy's `invoke` (`open-issues.md` §3, "Session 27, prototype gap") |
| Typed and untyped trait calls (`typedbench.jl`) | the entry's cost | `experiments/facts/typedbench.jl`; `open-issues.md` §3.9 | script | 33 ns typed, 105–117 ns and 64 bytes untyped |
| The keys prototype (conformances as methods, lean entry) | the runtime as methods | `experiments/keys-proto/README.md` | script | 25.8–33.6 ns against 25–29 plain at 16 elements; the basis of the s23 rewrite |

### 1.2 Acceptance-style cases (the guarantee)

| Example | Shows | Where | Status | Evidence today |
|---|---|---|---|---|
| G1.1–G1.15: redefinitions by owners, a winning pirate followed, calls into Base/LinearAlgebra/Printf, recursion through an entry, `return_type` at abstract types and after a redefinition, a fold over a run-time site with asserted effects, an older world not seeing a later conformance, a cycle's callee redefined | G1 "identical or error" | `experiments/facts/acceptance.jl:53–277` | test | 16/16 on TraitWorld 47e4274 (`reviews/2026-10-18-design-and-fixes.md` A3) *Verified* |
| G2.1: an unrelated module extending a function called on type values invalidates nothing | G2; the case decision 3 (s27) fixed | `acceptance.jl:297` | test | passes with facts at non-public functions off |
| The hunt: 48 adversarial cases, two failure classes found and fixed; C16 (`promote_op` at `Type{Int}`) the G1 carve-out | G1 under redefinition, deletion, added methods | `experiments/facts/hunt/batch1–6.jl`; `facts/README.md:61–67` | test | all pass but C16 (inference-dependent) and C24b (harness bug) |
| E3: stock invalidation is exact at concrete signatures (nine cases) | rule P needs no predicate | `facts/e3_exact.jl`; `facts/README.md:5–21` | script | exact in all nine |
| E1/E2: the demonstrators' closure, 3,533 CodeInstances, 207 abstract facts, 0 winning pirates | hot loops are concrete facts; no pirate wins | `facts/e12_closure.jl`; `facts/README.md:23–40` | script, partly history | the one sampled abstract site was the declared-call path to Cairo, since removed |
| `g2all`: twelve loads in any order, 0 facts-owned CodeInstances lost | G2 default tier | `facts/g2all.jl` | script | 0 lost (s24, s27) *Verified* in READMEs |
| `g2strict`: the same with strict mode on | step 2: strict refuses nothing in a real stack | `facts/g2strict.jl` | script | 65,318 methods checked, 837 pirates by the letter, none refused; +0.54 s on a 4.1 s load |
| `twolibs`: a second trait library loaded after TDE | the machinery's registries under two libraries | `facts/twolibs.jl` | script, not in the suite | 0 of 7,461 lost, measured once (`strict-mode.md` §2b item 2′) |
| `pirate_before`: `Base.abs2(::Float64)` defined before or after TDE's image loads | the "before" order; the image-validation case (piece 15) | `facts/pirate_before.jl` | script, **no recorded result** (*Verified*: `facts/README.md` has no mention) | unknown; this is the case strict mode first depends on |
| `newmod`: a new trait module after big loads | new trait code after loads | `facts/newmod.jl` | script | 2.7 s against 1.0 s (s25); a P1 artefact |
| `owners`: owner-aware G2 diagnosis of what loads invalidate | tooling | `facts/owners.jl` | script | — |
| `general`: a DataFrames/CSV workload under `_facts_call` | the facts mode's cost on real code no image holds | `facts/general.jl`; `notes/3-wrapping.md:199–201` | script | first call 0.60 s against 0.45 s; steady state within 10% |
| `rtperf`: broadcast, `map(sin)`, comprehension, empty `map` under the policy | run-time sites' cost | `facts/rtperf.jl` | script | broadcast 15.0 against 14.7 ns, `map(sin)` 27.5 against 24.1 |
| S1–S8: an owned method at an abstract call, a new subtype under union splitting, a `return_type`-dependent `map`, a stakeholder's method, a winning pirate, a losing pirate, a redefined `const`, a new type at a kind; stock against facts mode | **steps 1 and 3 of the framing** | `/tmp/claude-1000/review-framing/inval.jl` (**not in the repository**); `design.md:78, :105, :333` | script, scratch | S1–S3, S8 invalidate on stock and not in facts mode; S4, S5, S7 invalidate in both; S6 in neither *Verified* in the review's table. **The repository has no copy of the experiment the design's §3 cites** |
| `explosion.jl`: 30 wrappers sharing `data::Vector{Float64}`, 32 specializations against 1 | the "explosion" is structural | `/tmp/claude-1000/review-framing/explosion.jl` (not in the repository) | script, scratch | 0.2 ms per type for a 25-line body; volume unmeasured on a real library (`design.md:355`) |
| The witness-table world-age case (`dyn_world.jl`) | G1 for `Dynamic` in an older world | `/tmp/claude-1000/review-design/dyn_world.jl` (not in the repository) | script, scratch | 510.0 where plain gives 15.0; the design asks for acceptance case G1.16 (`reviews/2026-10-18-design-and-fixes.md` finding 2), **not added** |

### 1.3 Recovery cases (the facts rule's cost, and traits recovering it)

| Example | Shows | Where | Status | Evidence today |
|---|---|---|---|---|
| BaseBenchmarks under (A), 17 groups, 4,342 benchmarks | step 3's cost on plain code | `experiments/factscompiler/README.md:19–59` | script | geomean 1.016; 1.064 without `scalar`; `io` 1.32; tails on containers of `Any` (17–82×), abstract element types with a common result (raytrace 3.5×), small-union broadcasts (fixed to 1.09× by `return_type` step 2). One run, `--pkgimages=no`, Base plain *Verified* |
| raytrace: original, `::Hit` assertions, a written-out `Union`, `Scene` as a trait | the slowdown principle: a tail recovered by a trait redesign | `recovery/recovery.jl`, `RTTrait.jl` | script | plain 249 ms; facts 881; assertions 586; `Union` 273; trait 776–801 → 669 (witness) → 498–505 (key branches). **The trait version needed `sealed_call`**, a notion the user removed (`factscompiler/README.md:88–91`); witness tables and key branches are superseded by (D). So the current trait number is 776–801 ms, 3× plain, until (D) |
| raytrace with an open set of primitives (`rtopen.jl`, `RTBucket.jl`) | plain's fast path depends on how many types exist; `Dynamic` does not | `recovery/rtopen.jl` | script | plain 240 (2 types) → 693 ms (4 types); `Dynamic` 470 → 484; bucketed 395 *Verified* |
| `parse_json`: original, concrete wrapper, `local pos::Int` | a captured-variable tail recovered by plain Julia's own fix | `recovery/recovery.jl` | script | 1394 µs facts; 178 µs with the fix against 152 plain (1.17×) |
| `dynmicro`: sum of `area` over 10⁶ shapes | `Dynamic` against `isa` branches and dynamic dispatch | `recovery/dynmicro.jl` | script, partly history | plain 2 methods 3.8 ns; plain 4 methods 32–35; `Dynamic` 23–26; witness 14–17; branches 10.9 (`factscompiler/README.md:96–128`). Witness and branch rows are history since s29 |
| The one-method call at `Any` (`one_method(v[1])`) | lesson 1.5 at its worst | `factscompiler/README.md:15–17` | script | 0.99 ms off, 26 ms on |

**Not measured** of the plan's §3 list (*Verified* by absence in `factscompiler/README.md`): a SciML `Tsit5`/`Rodas5` solve, JuliaSyntax parsing Base, CairoMakie's PNG in steady state, DataFrames+CSV's session steps ten times, all under `all`. Base's tests in facts mode: never run before session 29; a run started (`design.md:354`).

### 1.4 The full-scale rewrites

**TraitDifferentialEquations** (691 lines: `src/ODECore.jl` 545, `src/TraitDifferentialEquations.jl` 146; *Verified*), baselines stock SciML and PlainODE (272 lines).

| Row | Goal | Status | Evidence today (`TraitDifferentialEquations/README.md:46–72`) |
|---|---|---|---|
| 1 | first solve, precompiled key, in every load order | row | 6.4–8.0 ms in every order; PlainODE 9.9 / **54** / 10.1 (none / loads before / after) |
| 2 | a new model function; a new model type at the prompt | row | a second function 6–8 ms; `@implement` 0.16–0.23 s, first solve 33–44 ms; PlainODE 5 ms. Not at a REPL |
| 3 | first Rodas5 solve | row | 22–26 ms after a Tsit5 solve, every order |
| 4 | a new callback closure | row | 13–15 ms (25–31 with loads); PlainODE 5.1 / 15 / **144** |
| 5 | first gradient; a second loss closure | row | 34–55 ms, then 17–21 ms (SciML 1.97–2.73 s, then 2.48 s); ForwardDiff's own tag 0.67–0.87 s; PlainODE with the same tag 20–22 ms |
| 6 | `Vector{Float32}` state | row, view cache | 0.59 s first session, 0.105 s later through a view cache (to be deleted) |
| 7 | rows 1–5 after loads, all orders | row | identical; `g2all` 0 lost |
| 8 | the `+(::Dual)` pirate | half a row | followed: 373 ms recompile, 2,192 calls, gradient unchanged (`scripts/pirate.jl`). **Strict half deferred** |
| 9 | the three error cases | row | 12 / 30 / 25 frames against 29 / 44 / 22; **none caught at a conformance, since the model is a plain function** (`README.md:56`) |
| 10 | `typeof(integrator)` | row | `Tsit5Integrator{Float64, Vector{Float64}}` against 3,553–24,426 characters |
| 11 | run time per step | row | 1.19× at n = 3 (model type faster than the function route); within 1% at n = 1,000; 15% slower than OrdinaryDiffEq's fused loops |
| 12 | trimmed binary | **not built** | — |
| 13 | precompile time, image size, load time | row | 8.2 s / 9.9 MB / `using` 0.29 s patched |

Design elements exercised: keys (`IntegratorView{T, P}` fields only), `Dynamic{Callback}` and `Dynamic{IntegratorView}`, `DynamicFn` at declared signatures, AD tags labelled by the primal signature, readable types, frame hiding. Not exercised: `CompiledCall` (the user's stated reason to keep it is "an ODE RHS that has the right type signature", `decisions.md:150`; the demonstrator's compiled route is a model type instead), `@concrete_only`, route A's conformance-time error, the pinned dynamic model mode (open-issues §2.15), strict mode, AOT.

**TraitMakie** (395 lines: `src/PlotCore.jl` 307, `src/TraitMakie.jl` 88), baselines Makie 0.24.16, PlainPlots (281 lines), matplotlib.

| Row | Goal | Status | Evidence today (`TraitMakie/README.md:50–61`) |
|---|---|---|---|
| 1 | first PNG, fresh process | row | 18–22 ms in every order; `using` 0.24–0.28 s |
| 2 | load-order independence against PlainPlots | row | 18.7–19.3 ms against 99.5–101 ms with CSV, DataFrames, CairoMakie first; equal without |
| 3 | CodeInstances lost | row | 0 over twelve loads |
| 4 | a new data type, colour, recipe | row | `@implement` 0.10–0.23 s, first PNG 52–134 ms; PlainPlots one method 0.6–0.8 ms then 39–119 ms; **6.4 s after loads without the system image** |
| 5 | dispatch targets (phases A–G) | **not measured** | `verify_main` cannot see workers in a session |
| 6 | colour shape change `:red` → vector → `Gradient` | row | works: 9, 87–112, 27–31, 9 ms; Makie 0.24 fails |
| 7 | `verify_main`, trimmed binary | row (s25) | 4.07 MB, 0.05 s, byte-identical PNG, no normal-path holes; `--trim=unsafe-warn`; `safe` reports 26 machinery errors |
| 8 | errors: bad data, wrong colour result, undeclared operation in a recipe | row | caught at the entry (hint names the bound), at `@implement`, at definition (a warning at the prompt); candidate lists show machinery types |
| 9 | run-time cost of `Dynamic` positions | row | equal within 5%; measures Cairo's stroke (fresh-eye M2) |
| 10 | precompile, image size, load | row | 4.6 s / 5.0 MB / 0.28 s |

Design elements exercised: `Vector{Dynamic{Plot}}`, `Dynamic{ColorSpec}` and `Dynamic{Positions}` in fields (`PlotCore.jl:135–136, :234`), `Positions{2}` families, definition checking on a user recipe, `verify_main` with `Dynamic` targets, the binary. Not exercised: a recipe with children (the exploration's `Stairs`), `Source`/live data, `Transform`, `Layoutable`, `AxisValues`, a user recipe from a package image, the per-recipe REPL compile cost (`makie-rewrite.md` §8.8).

**TraitReport with TraitTables and TraitCSV** (TraitTables 210 lines, TraitCSV 171, ReportCore 125), baselines PlainReport, PlainTables (198), pandas/matplotlib.

| Row | Goal | Status | Evidence today (`TraitReport/README.md:54–137`) |
|---|---|---|---|
| 1, 2 | process start to exit; phases | row | (t) 0.52–0.56 s, (pt) 0.50–0.52 s, Python 0.58–0.69 s; imports 0.29–0.33 s, work 0.07 s |
| 3 | CSV's first read with DataFrames before or after | row | CSV.jl 0.19 s alone, 2.46–2.53 s with DataFrames; form (b) 0.057 s with nothing recompiled |
| 4–6 | TraitWorld's own invalidations, import time, exit time | row, fixed | type printers through piece 17; hooks under the policy; exit hook only when new |
| 7, 8 | work under nine loads in either order; code lost | row | (t) 66–80 ms in every order, 0 lost; (pt) 102–147 ms, 17 of 49 methods lost |
| 9 | the binary | **not built** | — |
| 10 | a 10⁶-row file | row | 0.35 s against pandas 0.23 s (1.5×) |
| 11 | a strings column: `String15` as a conformance in an extension | row, view cache | 0.69–0.71 s first session, 44 ms later; CSV.jl 3.9–5.0 s every session (not like for like, fresh-eye S4) |

Design elements exercised: `Column{T}` with `T = eltype(Self)`, a family conformance over `Vector`, `Vector{Dynamic{Column}}` as table storage, `CSVColumn{T} <: Column` as a subtrait, a conformance declared from a package extension (`TraitCSV/ext/TraitCSVInlineStringsExt.jl:10–13`), a refused conformance by a non-owner (`TraitCSV/test/runtests.jl:17–21`), `Self` constructors (`emptylike`), definition checking at a package's build (`sizehint!` refused, `TraitCSV/README.md:8`). TraitTables uses the operations in its kernels (17 uses of `cell`/`nrows`, implementation review appendix), unlike the forks.

### 1.5 The port (demonstrator 4, paused)

| Example | Shows | Where | Status | Evidence today |
|---|---|---|---|---|
| M0: a 21-step REPL session over upstream Tables, DataFrames, CSV against pandas | the interactive baseline, with a real REPL on a pseudo-terminal | `forks/README.md:13–45`; `forks/scripts/session.jl`, `session.py`, `measure_session.sh` | script | pandas 0.32 s; upstream 12.16 s stock, 10.92 s patched (imports excluded); first read 3.6 s, mostly CSV recompiling after InlineStrings |
| M1: the three upstream test suites unchanged | the correctness bar | `forks/README.md:47–57` | script | 466,365 / 330,549 / 16,515,336 tests pass at M1 |
| M2–M5: `Column{T}`, `DataFrame.columns::Vector{Dynamic{Column}}` behind a `ColumnVectors` adapter, `ColumnKernels`, `CSVSource` | the storage proposal on real code | `forks/` (`git diff upstream`); `explorations/dataframes-port-lessons.md` | script | session 1.19 s imports excluded (upstream 10.9); imports 3.0 s (from 1.9, uninvestigated); per step 0.02–0.21 s at first call (`lessons.md:83–96`). **Kernels use `vector(c)`, never `cell`/`nrows`** (0 uses; implementation review P7) |
| Lessons 1.1–1.9, 2.1–2.5: run-time sites running native code, keyword splats, types as values, union-typed options, `Any` results, `parentmodule` calls, hot run-time sites at 6.5 µs, workers in no image | what real plain code does under the facts rule | `dataframes-port-lessons.md` | prose with measurements | three rule changes came from here (folds on Base's asserted effects, tuple splits, run-time sites run facts code) |
| `runtime_sites.jl`: every dynamic call in facts-compiled code from a worker, with inferred argument types | **the seed of the fully-typed certificate** | `forks/scripts/runtime_sites.jl` | script, tooling | "found every item above within minutes" (`lessons.md` §1.7) |

### 1.6 AOT examples

| Example | Where | Status | Evidence today |
|---|---|---|---|
| `plot_app.jl`: TraitMakie lines and scatter to a PNG, Cairo direct | `experiments/aot/plot_app.jl` | script (s25) | 4.07 MB, 0.05 s, PNG byte-identical; two `entrypoint`s by hand for JLLWrappers' `unique!` (`plot_app.jl:17–18`) |
| `hello_app.jl` | `experiments/aot/hello_app.jl` | script | the size floor |
| The old `App.main` choosing its table type at run time (2.09 MB) and `Pipeline` (3.53 MB) | `experiments/world/trim`, `experiments/interfaces/build` | history | before keys and facts; the only binaries that dispatched over conformances at run time |
| TDE row 12, TraitReport form (c), `--trim=safe` | — | **not built** | — |

### 1.7 Earlier phases, kept as history (do not count as current evidence)

- `experiments/interfaces/` (x1–x16): trait wrappers, calls upward (`@call`, `@handle`), sealing audits (1,091 pirates in Makie's tree; 20 with wrappers), doors, ComboCache (the ad-hoc session 21.2 s → 7.5 s), view caches (3.1 ms first calls), Makie's dispatch tracing (1,940 targets; 35–84 per new shape), `x13` Makie protected (15.7 → 8.5 s), the 1.17 GB untrimmed binary, the Python baseline. Pinned to TraitWorld before keys (`experiments/interfaces/README.md:13–18`). *Still useful as motivation numbers:* x8 (297 ms per table type), x15/x16, the Python baseline.
- `experiments/world/` (M0–M7): projections, `{R}` spelling, the audit (`PiracyError` modes), delegation (`ColsDGridExt` accepted, `ColsDBadExt` refused: the extension-trigger rule of the *old* design), concrete mode on CBottom–CTop, the first `verify_main` and the 2.09 MB binary. 19 test traits still in the `{R}` spelling.
- `attic/` (TraitRegions, the nine-package ecosystem, the 1.12 universe filter, the frozen note rev 1146): the error split, poisoning, `precompile_seal`.
- `experiments/sysimage/`: the policy in the platform (REPL first: 0.22 s instead of 5.9 s); to be deleted (`design.md:390`).
- `experiments/runtime-injection/`, `explorations/runtime_load_filter_1.13.2.patch`: the filter.

---

## 2. The demonstrators' goals, appraised under the user's criterion

The criterion: user-perceived interactivity and the quality of the workflow. An import of seconds is fine if the work after it is instantaneous. Slower code is fine if a message says how to make it fast. Winning a row is not the goal.

### 2.1 TraitDifferentialEquations: "a new loss function or callback in milliseconds"

**The right metric.** At a REPL, after `using`, the time from pressing enter on a new closure (a callback, a loss, a model function) to the result, and the same for a new model type. Not the first solve of a precompiled key; not the fresh-process wall time.

**Do the rows measure it?** Rows 2, 4 and 5 measure exactly this, in script mode. *Verified*: second closures (`experiments/solvers/ttfs_repeat.jl:17, :21` for the SciML side). What is missing is the REPL driver (REPL loaded first), which the forks have and the three demonstrators do not.

**What the evidence supports (Verified in the README).**
- A second loss closure: 17–21 ms. SciML: 2.48 s. This is the headline, and it holds under the criterion with room to spare.
- A new callback closure: 13–15 ms (25–31 with loads). SciML: 0.84–0.96 s.
- A new model type at the prompt: `@implement` 0.16–0.23 s, first solve 33–44 ms. Fine under the criterion (sub-second).
- A `Float32` state: 0.59 s in the first session. Fine under the criterion; the "0.105 s later" rests on a view cache that will be deleted, so the honest number is 0.59 s per session until an image holds the key (lesson 2.2's placement question).

**What traits add, and what the control is missing.**
- PlainODE with FunctionWrappers and the same signature-labelled tag matches rows 2 and 5 in a fresh session (`README.md:62–72`). So the millisecond closures are a *design idea* (cut the closure by a declared signature; label the tag by the primal signature) that plain Julia can carry by discipline. The trait form adds the check at the boundary and that the idea is the library's default rather than each author's care. That is a real but smaller claim than "callbacks and loss closures cost milliseconds" attributed to traits.
- PlainODE's loss under loads (54 ms, 144 ms) is the facts mode's protection, not traits'. Under `all` PlainODE would keep its code (Reasoning, agreed with `reviews/2026-10-18-implementation-shape.md` P2). The control (PlainODE under `all`) has not run. It is step 2 of the order of work (`design.md:396`).

**Verdict:** the goal is met under the criterion. The README should present rows 2, 4, 5 as "a declared signature cuts the closure; PlainODE shows plain Julia can do the same by hand; the trait form checks it", and keep the SciML numbers as motivation.

### 2.2 TraitDifferentialEquations: "errors at the model's conformance" and "readable types"

**The right metric.** Where the user's mistake is reported (at `@implement`, at the entry, at run time), how many lines until the cause, and whether the message names the fix.

**Do the rows measure it?** Row 9 measures lines, frames and longest line for three cases. Row 10 measures the type's length.

**What the evidence supports.** Row 10 holds outright (`Tsit5Integrator{Float64, Vector{Float64}}`). Row 9: 12 frames and a 289-character line against 29 and 3,789 for case 1; but (i) "none is caught at a conformance, since the model is a plain function" (`README.md:56`), so the design's claim ("errors at the model's conformance", `README.md:20`) has **no measured example**: route A (a `Lorenz` type conforming to `ODEModel`, with a `Float64` cache, checked at the dual signature) is in `explorations/solvers.md` §8 as a prediction only; (ii) cases 2 and 3 keep 12 frames of Base's broadcasting inside the user's function, so the frame bound is missed; (iii) frame hiding (`JULIA_TW_ALL_FRAMES`) accounts for 9–12 of the removed frames (fresh-eye M4). The quality-of-workflow claim that matters, "the message names the requirement", is partly shown by TraitMakie row 8 case 1 ("argument 2 of `add_lines!` is bounded by Positions; a String conforms to none of them") and not at all by TDE.

**Verdict:** half met. The missing half (a conformance-time error for a model written as trait code) is cheap to add (section 4, example 5).

### 2.3 TraitMakie: "interactivity like Python" for plots, and attribute shapes

**The right metric.** After `using`, the time to the first plot, to a plot of a new user type, to a changed attribute, and to a new recipe defined at the prompt, in a REPL, after other packages loaded.

**Do the rows measure it?** Rows 1, 2, 4 and 6 do, in script mode. Row 5 (dispatch targets) is not measured.

**What the evidence supports.** First PNG 18–22 ms in every order; `using` 0.24–0.28 s: under the criterion this is instantaneous after a cheap import. A new type costs a 0.1–0.2 s conformance plus 50–130 ms for the first PNG: fine. A colour shape change works where Makie 0.24 fails (row 6; `makie-rewrite.md` §1 for Makie's failure): a real design point (`Dynamic` at the input) and the one row where the trait form does something the baseline cannot. The 6.4 s for a new key after loads without the system image is the P1 artefact (REPL's interpreter breaking the image's compiler code) and it is the user's actual case; (B) is expected to remove it, and nothing has shown that yet.

**What the control is missing.** PlainPlots matches the first PNG without loads (21–23 ms) and loses 15 of 102 CodeInstances under loads (fresh-eye B2). Under `all` it would not. The 15.7–16.2 s Makie figure is not a like-for-like comparison with a 300-line library; it is motivation.

**Verdict:** met under the criterion for precompiled keys and for attribute shapes; not shown at the REPL; the AOT row (7) is from session 25 with `unsafe-warn` and has not been rebuilt under the current design.

### 2.4 TraitReport: "interactivity like Python" for a data report

**The right metric.** Not the fresh-process wall time against Python (row 1), which the user explicitly discounts. The right rows are: the work after imports (row 2's "work" column, 0.07 s), the work under loads in either order (rows 7, 8), a column type no image holds (row 11, first session), and the throughput row (10).

**Do the rows measure it?** Yes: rows 2, 7, 8, 10, 11. The README's status line leads with row 1 (`TraitReport/README.md:5`), which is the wrong lead under the criterion.

**What the evidence supports (Verified).**
- Work 66–80 ms in every order with nine packages loaded; the plain libraries 102–147 ms and 17 of 49 methods lost. Both are "instantaneous" to a user; the difference shows only as a mechanism.
- Imports 0.29–0.33 s for the trait libraries, 0.71 s for CSV+DataFrames: both acceptable under the criterion.
- `String15` through an extension's conformance: 0.69–0.71 s in the first session, 44 ms later (view cache). CSV.jl: 3.9–5.0 s every session, but that number includes `describe` and the DataFrame conversion (fresh-eye S4). The design point, "a package extension becomes a conformance, which invalidates nothing", is the best ecosystem example in the repository and is shown (0 of TraitCSV's code lost when InlineStrings loads).
- 10⁶ rows: 1.5× pandas, with a `tryparse`-per-cell reader against a C parser. Fine.

**Verdict:** met under the criterion. Form (a)'s 3.8–5 s (CSV.jl + DataFrames + the extension's invalidations) is the motivating failure, and form (t) removes it by design (conformances) rather than by workload. The claim to keep is row 11's mechanism, not row 1's wall time.

### 2.5 The forks: "interactive work at Python speeds for the full stack"

**The right metric.** The per-step first-call time in a real REPL after `using`, for image-held column types and for a new one, and the steps' steady-state time. The plan's §0 states this correctly (≤ 100 ms per step for image-held types, ≤ 1 s for a new column type in the first session).

**Do the rows measure it?** M0 and the lessons table do, with a REPL driver, medians and load logging (the only harness that answers fresh-eye B1 and S7).

**What the evidence supports.** After the port: read 0.13 s, describe 0.14, select_filter 0.15, user_function 0.21, a second schema's describe 0.03, a `String15` describe 0.02; the session 1.19 s excluding imports against upstream 10.9 s and pandas 0.32 s (`dataframes-port-lessons.md:83–96`). Under the criterion that is "interactivity like Python": every step under a quarter second at first call, most well under. Imports 3.0 s, up from 1.9 s, uninvestigated; acceptable under the criterion, but the rise should be understood.

**What the control is missing, and what the port does not show.**
- Upstream under `all` with the forks' workloads applied has not run (plan §0's falsification clause names upstream on the patched build within 1.5× as failure, but that control has piece 5 only).
- The kernels unwrap at once (`vector(c)`), so the port validates a per-column function barrier compiled by facts, plus workloads (`CSVDataFramesExt`), plus one real design point: per-column kernels combined in integer code replacing per-tuple specializations (sort 0.025 s, groupby 0.023 s, join 0.056 s at first call against 1.2, 0.8, 1.3 s). Only the last is a key result.
- `CSVColumn{T}` (the principled fix for `CSVInlineStringsExt`) was not written in the fork; `CSVSource` with one operation `rawsource(s)::Any` was, and the InlineStrings extension got a workload, the workaround the project said it would not make (`TraitReport/README.md:154`).

**Verdict:** the user-facing goal is met for the ported steps; the attribution is not. Paused, correctly, until the control exists.

### 2.6 Across all demonstrators: four things the rows do not measure and the criterion asks for

1. **The REPL** (REPL loaded first, `julia -i`), for the three small demonstrators. The forks did it; the small ones did not.
2. **Revise-style edits**: edit a worker, time the next call. `experiments/interfaces` x5 did this for the old design (0.86–1.07 s next call, mostly the check code recompiling); nothing current. `design.md:411` lists "no Revise" under what is not claimed.
3. **Steady-state time beside the first call** (lesson 4's point: "a first-call time is not all compilation"). TDE row 11 and TraitMakie row 9 have steady state; TraitReport's rows and the forks' table report first calls only, except lesson 1.8.
4. **A warning that teaches.** No row shows the compiler telling a user why code is slow under the facts rule and what to change. The recovery cases were redesigned by hand after reading profiles (`factscompiler/README.md`), not after a report.

---

## 3. Gaps

### 3.1 Design elements and claims with no example

| Element or claim | Where claimed | What exists | Gap |
|---|---|---|---|
| **Strict mode refusing a real pirate** in a demonstrator; the error naming the method and the code | `design.md:83`; TDE row 8 | 32 synthetic tests (`strict.jl`); `g2strict` refusing nothing | the strict half of TDE row 8 is "deferred"; no example of what a user sees |
| **A pirate loaded before the image** (piece 15: an error instead of a recompile) | `design.md:93` | `facts/pirate_before.jl` exists; no recorded result | unknown behaviour of the "before" order on the current prototype |
| **The extension exception** (Theorem 2 case c) | `design.md:91`; `open-issues.md` §1.10 | `experiments/world/delegation/ColsDBadExt` for the *old* rule (triggers confer nothing) | no acceptance case under the current design |
| **Bindings redefined from another module** | `design.md:92` | S7 in scratch | nothing in the repository |
| **Fully typed code pays nothing for facts** | `design.md:336` ("not measured directly") | BaseBenchmarks' concrete groups 1.00–1.09 | no benchmark of fully typed code comparing the compiled code itself |
| **The fully-typed certificate** (per worker: run-time sites or none; `error` level refuses) | `design.md:311` | `forks/scripts/runtime_sites.jl` (tooling); `TraitWorld/src/concrete.jl` (`_has_runtime_sites` is internal) | no example of the message a user gets for a worker that is fully typed and one that is not |
| **Concreteness enforced (`error` level) on a real trait** | `design.md:115, :179` | `test/keys_syntax.jl:174`; the plan's `@concrete_only` on `CSVColumn` (not written) | **no demonstrator uses `@concrete_only` or `@warn_on_abstract`** (*Verified* by grep) |
| **Warnings that teach on badly written code** | the user's criterion; `design.md:119` (the slowdown principle) | `experiments/world/concrete/` (CTop/CBottom, one abstract field, 74×, a root-cause chain) | one toy from 2026-10-13; nothing on a real library; nothing for the facts rule's tails |
| **`CompiledCall` for an ODE right-hand side with a checked signature** | `decisions.md:150` (the user's reason to keep the mode) | `runtests.jl:655` | no demonstrator; TDE's compiled route is a model type |
| **`Dynamic` as a call-site split (D)** | `design.md:194` | witness tables (off), key branches (superseded) | the hot-loop number after (D) does not exist; today's trait raytrace is 3× plain |
| **Threads** (`Dynamic` across tasks; workers compiled concurrently) | `design.md:357, :411` | nothing (*Verified*: no `Threads.`/`@spawn` in any demonstrator or test) | A4 was an artefact of P1; under (B) the question is Julia's own, and untested |
| **Revise-style edits; struct redefinition; conformance redeclaration** | `design.md:188, :411` | x5 (old design); `runtime.jl:154` (override refused) | no current example of editing a worker, redefining a conforming struct, or redeclaring a conformance |
| **Composition across many packages; deep hierarchies; two libraries composed by a third** | `design.md:357` | TraitCSV → TraitTables → TraitMakie (~600 lines, one supertrait); `twolibs.jl` once | nothing with many trait packages or a (key owner, function owner) pair no package owns, except `String15` (view cache) |
| **Results like the input** beyond `Self` | `design.md:214` | `test/like.jl` | no demonstrator rebuilds a user's type |
| **Named implementations; value-level wrappers (`Via{Fast}(x)`)** | `design.md:219` | prose | deferred; fine, but the "foreign trait, foreign type" case has no worked example at all |
| **Numeric traits, promotion across implementing types** | `open-issues.md` §2.8 | prose | nothing |
| **Live bounds, multi-argument bounds, recipes with children, `Source`** | `makie-rewrite.md` §8 | prose | TraitMakie converts `lines(x, y)` explicitly and has no recipe with children |
| **AOT dispatching over conformances at run time; `--trim=safe`; the TDE and CSV binaries** | `design.md:224–226, :356` | `plot_app` (fixed types, `unsafe-warn`); the old `App.main` (history) | the current design has no binary that chooses a conformance at run time |
| **The volume of the "explosion"** | `design.md:355` | `explosion.jl` (scratch) | no CodeInstance or image-byte count per added type on a real library |
| **The facts rule's cost on real code that is not fully typed** | `design.md:110` | BaseBenchmarks (one run, `--pkgimages=no`, Base plain); `general.jl` | the plan's package list (SciML, JuliaSyntax, Makie, DataFrames steps under `all`) not run; Base's tests started, no result |
| **A `late_check`-like inconsistency** (prediction 3) | `notes/2-design-choices.md:415` | "an example and a test are still to write" | still to write |

### 3.2 Examples that no longer match the current design

- **Written for representations and projections:** `explorations/solvers.md` and `makie-rewrite.md` (banners say so); `experiments/world/*` (`project(t) = …`, `{R}`); `experiments/interfaces/*`; TraitWorld's `_PC` precompile module and 19 test traits in the `{R}` spelling (`reviews/2026-10-18-implementation-shape.md` P5).
- **Written for wrappers, sealing, doors, the filter:** `experiments/interfaces` x4, x6, x7, x11, x13, x14 (the sealing audits, `PiracyError` by deletion, the `JULIA_TW_PROTECT` experiment); `experiments/world` M6 (layering, the audit); `experiments/runtime-injection`; the delegation example (`ColsDBadExt`). The numbers from x13 (Makie protected: 15.7 → 8.5 s) are still quoted as motivation in `makie-rewrite.md` §5 and are a property of the old filter.
- **Written for the external interpreter and the foreign owner:** the system-image rows in all three READMEs; the view-cache rows (TDE row 6, TraitReport row 11's 44 ms); `newmod.jl` (2.7 s after loads); TraitMakie row 4's 6.4 s; `facts/general.jl` and `rtperf.jl` (`_facts_call`). All measure P1 and go with (B).
- **Written for witness tables and key branches:** `dynmicro.jl`'s middle rows; the raytrace's 669 and 498–505 ms; `RTTrait.jl`'s `sealed_call` dependence. Superseded by (D) and by "no sealing".
- **Stale scopes:** `TraitDifferentialEquations/README.md:25–36` names `ODETsit5`, `ODERodas`, `LorenzModels`, `Bounce`, `RaiseSigma`; the tree has `ODECore.jl` and `TraitDifferentialEquations.jl` (*Verified*). `TraitMakie/README.md:27–41` names `CairoBackend`, `Plotting`, `UserPlots`, traits `Coords`, `Source`, `Backend`, `Transform`, `Layoutable`; the tree has `PlotCore.jl` and `TraitMakie.jl` (*Verified*). Fresh-eye S6 is still open.
- **Stale numbers in the notes:** `notes/1-overview.md:200–203` (55–60 ms, 87–97 ms, 37–39 ns, "strict mode, not built"); `:180` (a new loss "compiles the step again") against row 5 (`open-issues.md` §5.4).

### 3.3 Examples that exist only as prose

- The strict-first narrative's own example: "a hook on your own type (`Base.show(io, ::MyType)`) invalidates plain callers in stock Julia and nothing under facts" (`design.md:54, :97`). S1 in scratch; no test.
- `design.md:98`: "65,318 methods checked, 837 pirates by the letter, none refused" is measured; "what is refused is exactly a method of a function you do not own, for types you do not own, that would change what compiled code computes" has no example that is not `abs2`.
- `notes/4-details.md:682–690`: `main` over `read_tables(args)` dispatching over conformances in a binary. The old `App.main` did this; nothing current.
- `notes/4-details.md:362–369`: `via(Fast, m)`.
- `notes/4-details.md:600–607`: `TableLike` and `materialize` (types that only convert). TraitReport form (b) converts a `DataFrame` explicitly (`src/ReportCore.jl`), so a small example exists; it is not presented as this pattern.
- `explorations/solvers.md` §8: the three SciML error cases *predicted* for route A; §11's eleven gaps; `makie-rewrite.md` §3's typed compute graph (`Node{T}`, `Derived{T}`, `@derive`), §4's user code (`Trajectory`, `Gradient`, an `Observable` source, `stairs!`).
- `design.md:116–117`: declared result types at abstract positions "give back exactly what the facts rule took away". Shown only indirectly (the trait raytrace's result type is declared; `TraitTables`' `cell(c, i)::T`). No small case that shows plain Julia's inference losing a result type under facts and a trait declaration restoring it in the same program.

---

## 4. Proposed further examples, ranked

Ranking by how much each reduces uncertainty about the design or shows its value, divided by the cost to build. "Cost" is my estimate in sittings for one agent on the shared machine (one Julia job at a time, niced). The expected outcome is what the design predicts; an outcome against it is listed where it would matter.

### Tier 1: decide what the demonstrators may claim (build first)

**1. The plain baselines under `all`** (the decisive control; `design.md:396` step 2).
- *Tests:* whether "survives loads" is traits' or the facts mode's; what the trait residue is.
- *How:* PlainODE, PlainPlots, PlainTables and upstream DataFrames+CSV (with the forks' workloads) under `--compile-by-facts=all` on the in-tree (A); the existing load matrices (`experiments/demos/rows.sh`, `TraitReport/scripts/loads.sh`); `invalidated.jl`'s lost-CodeInstance counts by name; first-call and steady-state times. Before (A) is in-tree, a weaker form with `Compiler.activate!` and `--pkgimages=no` gives the counts (times are meaningless without images).
- *Expected:* the baselines lose nothing; TDE rows 1/7, TraitMakie 1–3, TraitReport 7/8 become controls; the residue is compile per key (rows 2/4/5 with the FunctionWrappers caveat), definition-time errors, readable types, declared conformance (row 11), `Dynamic` against `isa`, AOT target lists.
- *Cost:* 1 sitting once (A) builds; the counts-only form 0.5 sitting today.

**2. S1–S8 and the "before" order as acceptance files, under both tiers.**
- *Tests:* steps 1–3 of the framing, in the repository, on the in-tree facts mode; and the one case strict mode first depends on: a pirate loaded before the image (piece 15).
- *How:* move `inval.jl` into `experiments/facts/` as `framing_cases.jl`; add S9 (a stakeholder's package extension activated by an unrelated trigger with a method at a fact without the trigger's types) and S10 (`Core.eval(Other, :(const K = …))`); run `pirate_before.jl` in both orders with `JULIA_TW_STRICT=0|1` and record what happens (recompile, error, or silent follow) in `facts/README.md`; add G1.16 (`dyn_world.jl`, a `Dynamic` operation in an older world).
- *Expected:* S1–S3, S8 invalidate on stock and not in facts mode; S4, S5, S7 in both; S6 in neither; S9 invalidates in both (the named exception); S10 invalidates in both and no hook sees it; the "before" pirate is followed and, with strict on, cannot be refused today (piece 15 missing). An outcome against: any of S1–S3/S8 invalidating in the in-tree mode.
- *Cost:* 0.5 sitting. This also rescues evidence that `design.md` cites from a tmpfs.

**3. One REPL row per demonstrator: a new type, a new closure, an edit.**
- *Tests:* the user's actual workflow (fresh-eye B1); whether the 5.9 s first-new-key cost is gone after (B); Revise-style edits.
- *How:* `julia -i` (or `using REPL` first), patched build, no system image, for each demonstrator: a precompiled key's first call; a new type at the prompt (`struct Mine …; @implement …`); a new closure; then an edit of one worker (`Core.eval(ODECore, :(…))` or Revise on a path package) and the next call; with and without CSV, DataFrames, CairoMakie loaded first; 5 runs, medians, load logged (the forks' harness, `measure_session.sh`, adapted).
- *Expected (after (B)):* every step under 0.3 s but the edit, which recompiles the worker and its dependents (the stated exception); no step depends on the load order. Before (B): the 5.9 s reproduces, which is the measurement that justifies (B).
- *Cost:* 1 sitting; repeat after (B) (0.5).

### Tier 2: the claims of the framing that have no example

**4. The fully-typed certificate: a worker that is fully typed against one that is not, and the message.**
- *Tests:* the decided-but-unbuilt certificate (`design.md:311`); "fully typed code pays nothing for facts"; the warning that teaches.
- *How:* two versions of one small trait module: `summarize(c::Column)` over `Vector{Float64}` (fully typed) and the same over a `Vector{Any}` column, or with a `Dict{Symbol, Any}` of options read in the loop (not fully typed). Turn `forks/scripts/runtime_sites.jl` into `TraitWorld.runtime_sites(f)` and a per-worker report at the module's end: "worker `summarize` at `Vector{Any}`: 3 run-time sites; the first at `TableCore.jl:107`, `Float64(::Any)`; the key's cell type is `Any`". Measure both workers' steady state under `no`, `all` and `traits`, and the compiled code's size (`code_native` lines or `CodeInstance` count).
- *Expected:* the fully typed worker's code is identical under `no` and `traits` (the same `:invoke`s), and its time equal; the untyped one is slower under facts by the tail factor, and the report names the site and the fix (a concrete column type, or a declared result). An outcome against: measurable cost on the fully typed worker.
- *Cost:* 1 sitting for the report, 0.5 for the measurement. This is the single most valuable example for the user's criterion ("I get better compiler warnings for how to make it fast").

**5. Errors at definition against deep traces: route A for the solver.**
- *Tests:* "errors at the model's conformance" (TDE README:20), the unmeasured half of row 9; definition checking at a dual signature.
- *How:* `struct Lorenz{T}; σ::T; ρ::T; β::T; end` conforming to `ODEModel` with (a) a `Float64` cache in `rhs!`, (b) a missing operation, (c) a wrong result type; run `@implement` and record where each is caught, the message, lines and frames; then the same mistakes in a plain function through the `FunctionModel` route (today's row 9) beside them.
- *Expected:* (b) and (c) at `@implement`, one or two lines, naming the operation and the declared type; (a) at the conformance's check at the solver's dual signature if inference reaches `Float64(::Dual)` through `materialize!`, otherwise at run time with frames by bound. An outcome against: (a) escapes the check and the trace is as long as SciML's.
- *Cost:* 0.5 sitting.

**6. Strict mode on a real pirate, in a demonstrator, with the message.**
- *Tests:* step 2 as a user sees it; the second half of TDE row 8; the symmetric lint.
- *How:* `scripts/pirate.jl` with `JULIA_TW_STRICT=1`: the `+(::D3, ::D3)` pirate defined after the first gradient. Record the `PirateError` text. Then the "before" order (the pirate defined, then the gradient): record that it is followed and what `verify_main`'s lint would report. Then a split-core case: StaticArrays loaded after a worker compiled at `SArray` types, without and with the delegate.
- *Expected:* refused after, naming the method and the solver's worker; followed before; the split-core case refused without the delegate and accepted with it. An outcome against: a refusal of a stakeholder's method (a false positive), or the safety net firing.
- *Cost:* 0.5 sitting.

**7. The extension exception and a glue extension, as acceptance cases.**
- *Tests:* Theorem 2 case c (`design.md:91`); lesson 2.2 (workers for a (key owner, function owner) pair no package owns).
- *How:* package A with a trait and a conformance for `Vector{Float64}`; package B with an extension triggered by C whose method applies at A's fact without mentioning C's types; load C after A's worker ran and count lost CodeInstances; then a glue extension of A on B with a workload for the pair, and the first-session against later-session cost of the pair's worker.
- *Expected:* the extension invalidates A's worker in both modes (the named exception; strict mode has no rule yet); the glue extension's image holds the pair and the second session compiles nothing. This decides `open-issues.md` §1.10 item 3 with a case in hand.
- *Cost:* 0.5 sitting.

### Tier 3: `Dynamic`, heterogeneous collections and the facts rule's tails at scale

**8. Heterogeneous collections at scale: a `Vector{Dynamic{Shape}}` with 2, 4, 16 and 64 conformances, from images and from the prompt.**
- *Tests:* `Dynamic` against plain Julia's `isa` branches and dynamic dispatch as the set grows; the call-site split (D) once built; images holding the conformances; the "explosion" as volume.
- *How:* extend `dynmicro.jl`/`rtopen.jl`: N conformances in a package with a workload, M more defined at the prompt; per element time at 10³ and 10⁶; CodeInstances and image bytes per added conformance (the volume measurement `design.md:355` lacks); lost CodeInstances when a conformance is added at the prompt.
- *Expected:* plain Julia's time jumps at `max_methods` and its compiled callers are invalidated by each new subtype (S2); `Dynamic`'s time is flat in N, within 2× of the two-method `isa` path after (D), and no caller is invalidated by a new conformance. An outcome against: per-element cost above plain's dynamic dispatch (32–35 ns).
- *Cost:* 0.5 sitting now; 0.5 after (D).

**9. The facts rule's cost on real code that is not fully typed, and the recovery by a trait, on one package.**
- *Tests:* step 3's cost beyond BaseBenchmarks; the slowdown principle on code someone else wrote.
- *How:* the plan's §3 list that was never run: a SciML `Tsit5` and `Rodas5` solve, JuliaSyntax parsing Base, CairoMakie's PNG in steady state, DataFrames' session steps ten times, under `no` and `all` with images in facts mode (after (A) in-tree); report per-package geomean and the worst five functions with their run-time sites. Then take the worst one and write its trait form (as TraitTables did for `Vector{AbstractVector}`), and measure the recovery.
- *Expected:* most packages within 1.1×; a few tails on `Any` containers (Makie's attributes are the likely one); the trait form recovers the tail. An outcome against: a tail that no trait redesign recovers, which by the user's rule counts against the design.
- *Cost:* 1–2 sittings (precompiling these stacks in facts mode is slow; one job at a time).

**10. `CompiledCall` for an ODE right-hand side, against `DynamicCall` and the model type.**
- *Tests:* the user's reason to keep `CompiledCall` ("an ODE RHS with the right type signature"); what the compiled mode costs in cached code.
- *How:* TDE's function route with `compiled_call(lorenz!)`: run time per step at n = 3 and n = 1,000 beside row 11's two columns; compile time for a second function; what the worker's image holds; the error when a function of the wrong signature is passed in each mode.
- *Expected:* compiled call at the model type's speed (173 ns per step), a per-function compile (tens of ms), the signature error at the entry in both modes. An outcome against: no speed gain over `DynamicFn` at n = 3, which would weaken the case for keeping the mode.
- *Cost:* 0.5 sitting.

### Tier 4: breadth, when the compiler parts exist

**11. Threads.** `Threads.@threads` over a `Vector{Dynamic{Column}}` with workers compiled concurrently in the first call, under (B); a `Dynamic` shared between tasks; a method defined on one thread while another compiles trait code. Expected: correct results, no hangs; this was A4 and becomes Julia's own invariant. Cost 0.5 sitting after (B).

**12. Composition across many packages.** Twenty small trait packages with conformances across them (the fresh-eye review's proposal 4), loaded in random orders: `using`, `@implement`, first call, lost CodeInstances, the first new key's cost. Expected: order-independent numbers; no lost code; the pair problem (lesson 2.2) where no package depends on both. Cost 1 sitting.

**13. AOT under the current design: three binaries with `--trim=safe`.** TDE with ForwardDiff (row 12); TraitReport form (c) with TraitCSV (holes expected and named by `verify_main`); a program choosing a conformance at run time (the old `App.main`'s shape). Expected: TDE closed; the report open at CSV-like sites with a list; the run-time choice closed by the conformance list; `safe` passes once the machinery's slow paths are constant-folded in a closed build. Cost 2 sittings, each build alone under the memory guard.

**14. Struct redefinition and conformance redeclaration at the prompt.** Redefine a conforming `struct` (Julia 1.13 allows it), then redeclare its conformance; check old values keep the old type and old worlds answer as before (`design.md:188`); measure what recompiles. Expected: the redeclaration mechanism works as a struct redefinition does; until it is built, a clear error asking for a restart. Cost 0.5 sitting; the mechanism itself is a TraitWorld feature to build first.

**15. A recipe with children and a live source in TraitMakie** (`makie-rewrite.md` §3–4: `Stairs`, `Observable` as a `Source`). Tests the typed compute graph, `Callable{Tuple{}, T}` edges and the live-bound gap (§8.3). Cost 1–2 sittings; a design question (live bounds) must be settled first.

### The top ten, in order

1. The plain baselines under `all` (tier 1, example 1).
2. S1–S8, S9–S10, the "before" pirate and G1.16 as acceptance files (example 2).
3. A REPL row per demonstrator with a new type, a new closure and an edit (example 3).
4. The fully-typed certificate: two workers and the message (example 4).
5. Route A errors at the conformance for the solver (example 5).
6. Strict mode refusing the `+(::Dual)` pirate, with the message, both orders (example 6).
7. The extension exception and a glue extension as acceptance cases (example 7).
8. Heterogeneous collections at scale, with the volume measurement (example 8).
9. The facts rule on one real package with a trait recovery (example 9).
10. `CompiledCall` for an ODE right-hand side (example 10).

---

## 5. What is solid, so that this is not read as a teardown

- **The order-of-magnitude rows are real and well measured:** a second loss closure 17–21 ms against 2.48 s, a second callback 13–29 ms against 0.96 s, with the SciML numbers taken as second closures (`experiments/solvers/ttfs_repeat.jl`). Under the user's criterion these are the rows that matter, and they hold.
- **The baselines are candid.** PlainODE, PlainPlots and PlainTables exist, carry the same workloads, and the READMEs print where they match or win (`TraitDifferentialEquations/README.md:62–76`, `TraitReport/README.md:95–98`). Few projects build the baseline that weakens their headline.
- **The conformance-as-extension example (TraitCSV + InlineStrings) is the best single illustration of the ecosystem the design wants**, and it is measured, tested (a non-owner's conformance refused) and small enough to read in ten minutes.
- **The colour-shape-change row** shows `Dynamic` doing what the baseline cannot; the open-primitives raytrace shows `Dynamic`'s flat cost in the number of types where plain Julia's fast path collapses.
- **The acceptance suite and the hunt** are the right kind of evidence for G1, and E3's nine cases settle rule P's exactness.
- **The forks' harness** (a real REPL on a pseudo-terminal, medians, load logging, upstream suites unchanged) is the model every other demonstrator's harness should follow.
- **The concrete-mode root-cause report** (`notes/4-details.md:745–753`) is already the shape of the warning the user wants; it needs to be pointed at real code and at the facts rule's run-time sites.

---

## 6. Files

- This review: `/tmp/claude-1000/review-examples/2026-10-18-examples-and-demonstrators.md`.
- Sources most relied on: `/home/hellmann/Repos/julia-trait-bound/writeup/design.md` (§3, §4.3, §4.5, §8, §9.3), `writeup/decisions.md`, `writeup/open-issues.md`, `writeup/notes/1-overview.md`, `2-design-choices.md`, `3-wrapping.md`, `4-details.md`, `writeup/design-findings.md` (§1, §5, §6, §13, §15–§19), `writeup/explorations/solvers.md`, `makie-rewrite.md`, `strict-mode.md`, `aot-under-facts.md`, `dataframes-port-lessons.md`, `writeup/plans/2026-10-17-dataframes-traits-plan.md`, `2026-10-17-policy-in-compiler-plan.md`, the four reviews of 2026-10-17/18, `TraitDifferentialEquations/README.md` and `scripts/{errors,pirate}.jl`, `TraitMakie/README.md` and `scripts/errors.jl`, `TraitReport/README.md`, `TraitTables/{README.md,src/TableCore.jl,test/runtests.jl}`, `TraitCSV/{README.md,src/CSVCore.jl,ext/TraitCSVInlineStringsExt.jl,test/runtests.jl}`, `forks/README.md`, `experiments/{README.md,facts/README.md,facts/acceptance.jl,factscompiler/README.md,keys-proto/README.md,lens/layout.md,errors/README.md,sysimage/README.md,world/README.md,interfaces/README.md,aot/plot_app.jl}`, `TraitWorld/test/*.jl` (testset names), `TraitWorld/src/concrete.jl` (header), `attic/README.md`, `session-notes/2026-10-18-29-reviews-and-decisions.md`.
- Verification by shell: `grep`/`find` for `inval*.jl`, `@concrete_only|@warn_on_abstract|check_concrete`, `CompiledCall|DynamicFn`, `Threads\.|@spawn`, `verify_main`, `Like\{|::Self|withfields`, `pirate_before` in `facts/README.md`, `JuliaSyntax|SciML|Makie` in `factscompiler/README.md`; `ls` of every demonstrator's `src`, `test`, `scripts` and `baselines`; `wc -l` of the sources.
