# Performance: where the costs come from

A chapter of the [rationale](../design.md): what the facts+traits compiler costs, where the costs come from, and what it teaches about placing code, on julia-1.13 with parts (A)–(D). The numbers are from the measurement round of 2026-10-20 (julia-1.13 3b8085c222, TraitWorld bed3782) unless a row names another build; rows marked 61852d8fb1 are from the build of 2026-10-19 (TraitWorld 375a930) and were not in the round. The tables with builds and run counts are in [`evidence.md`](evidence.md); the detailed log, with every number, is `../../session-notes/2026-10-18-29-reviews-and-decisions.md`; the review of this work is `../reviews/2026-10-19-performance-phase.md`. How the numbers got here, from earlier builds, is in [`../record/design-history.md`](../record/design-history.md#the-performance-phase).

## Where things stand

The demonstrators' rows are two processes per load order (n = 2); TraitReport's three.

| What | Now | Baseline |
|---|---|---|
| raytrace over `Dynamic{Scene}` (rtopen; julia 61852d8fb1) | 300–336 ms (held views) | plain closed by accident 246–259 ms; plain with four `Scene` types 827–882 ms (a `max_methods = 3` effect: four types are one over plain inference's split limit, and the trait split stops at four too) |
| raytrace, small case (julia 61852d8fb1) | 4.7–5.3 ms, 3.8 MB | plain 3.9–4.7 ms, 3.3 MB |
| sum over `Dynamic{Shape}` (cache-resident; julia 61852d8fb1) | 0.92–1.40 ns per element | plain closed 0.87–0.91, plain with four methods 29.5–33 ns |
| the same over 10⁶ elements (julia 61852d8fb1) | 4.5–5.7 ns | plain closed 3.9–4.0 ns |
| a typed trait call, per call | 0.8 ns (product setting and `all`) | plain 0.8 ns. Before, on julia 61852d8fb1 without inlining across owners: a loop of 16 inside the call, 36–38 ns against 33.8–34.5 ns |
| an untyped trait call, per call | 28.8 ns (product setting), 30.8 ns (`all`), 16 bytes | plain 18.9 ns, 17.6 ns under `all` |
| a varargs wrapper in a plain recursion (the review's probe; julia 61852d8fb1) | 0.36–0.44 ms, 0 bytes (patched, plain code) | stock 1.13.2: 21.9–23.3 ms, 16.8 MB |
| TDE: a new problem type (then a model type), `@implement` / first solve (timed whole), with CSV + DataFrames + CairoMakie loaded before / after | 69–70 / 335–338 ms; 70–74 / 338–350 ms | without loads: 66 / 340–371 ms (E-146; the first solve is mostly the solver compiled for the new key). Before the fixes of E-146, `@implement` with the loads before: 254–259 ms. Previous prototype: `@implement` 0.16–0.23 s |
| TraitMakie: a new data type (forwarding), `@implement` + first PNG, loads before / after | 45–47 + 81–84 ms; 39–40 + 73–76 ms | without loads: 22 + 72–74 ms (the PNG timed inside `@elapsed`, without the call's own compilation) |
| TraitMakie: the same, **without loads** | 22 ms + 72–74 ms | before, on julia 61852d8fb1: 77 + 107 ms (the clean-case regression, now gone); an earlier build of the compiler: 36 + 40 ms |
| TraitReport form (t), fresh process | 0.794–0.805 s | the same without traits (pt) 0.771–0.775 s; Python (pandas 3.0.6, matplotlib 3.11.2) 0.578–0.589 s |
| TraitReport form (b), work, nine packages loaded first | 344 ms (41 ms without loads) | form (a′), plain: 3,106 ms (248 ms without loads). `using`: trait 1.15–1.20 s against plain 0.95–1.01 s |
| forks: interactive session without imports (indicative: load average 3.4–5.2) | 1.35–1.37 s; wall 3.7–4.0 s | upstream CSV + DataFrames 10.7–11.2 s; wall 12.0–12.8 s. Imports 1.89–1.92 s against upstream's 0.69–1.19 s |
| forks: `stringtype = String15` read and show, in the session | 0.060–0.062 s | upstream 0.21–1.03 s. Before the `String15` fixes (julia 61852d8fb1): 1.56–1.67 s. Not separated: the extension and the check by facts |
| TDE run time per step, Lorenz (julia 61852d8fb1) | problem type (then a model type) 158 ns | OrdinaryDiffEq 346 ns |

## The themes

### 1. Every piece of code has an owner, and its performance follows from the owner

The facts mode makes "who compiles this code, under which rules" a property of each method. Facts code is load-proof but slow where it is type-unstable, and plain code is fast to infer but invalidatable. The compiler must run in a frozen world. Placing each component is part of the design:

| Code | Owner it needs | What another owner costs |
|---|---|---|
| The compiler, called from facts code (TraitWorld's checks) | plain, whoever calls it (module flag "never by facts" on Compiler) | compiled by facts, as everything a facts frame calls would be, the abstract interpreter runs as type-unstable facts code, 6× slower |
| TraitWorld's machinery (checks, finding builders, hooks) | facts (`@machinery`, the per-method mode) | plain, it is invalidated by every big load, then re-inferred in a larger method table: 2 s per new implementation |
| The compiler's code for the checks' interpreter | the compiler's own world (a `NativeInterpreter` with its own cache owner; Base reflection runs it in the typeinf world) | plain and run at the latest world, it is invalidated by loads and JIT-compiled again: 3.7 s |
| The first-call check's inference of a worker's call graph | the code that runs (reflection by facts: shared with the worker's compilation and kept in images) | a private cache (`_CheckOwner`): 3,100 CodeInstances per new key, shared with nothing and never in an image |

**The choices have costs:**
- **`@machinery`'s clean-case cost.** The machinery is type-unstable by nature, so as facts code its run-time sites compile facts copies of Base methods in each session, unless TraitWorld's image holds them. That caused TraitMakie's clean regression on the build of 2026-10-19 (36 → 77 ms). TraitWorld's image now holds the machinery's code (f7aea19), and the forwarding `@implement` takes 22 ms (round of 2026-10-20). Its first PNG, 72–74 ms, is still above the earlier build's 40 ms.
- **A hole in "protected as trait code" (review B1).** `@machinery` code that calls compiler functions directly (`argextype`, `sptypes_from_meth_instance`, the `NativeInterpreter` constructor, `register_dynamic_candidate!`) holds edges to *plain* compiler CodeInstances. Those are valid only as long as plain Julia keeps them valid. Calls through Base reflection run in the typeinf world and are safe; direct calls are not.
- **`split_call` is a compiler method,** so the module flag marks it plain too. That is safe only because inference intercepts it.

### 2. Two Julia inliner habits that cost recursions through wrappers, not specific to facts

A varargs `@inline` wrapper inside a two-type recursion runs 56× slower in plain Julia (22.5 ms against 0.40 ms, 16.8 MB against 0 bytes, verified on stock 1.13.2, review A1), with `Vararg{Any}` specializations.
- **Compileable signatures.** A call the inliner cannot inline is invoked at the compileable signature, which widens a varargs tail to `Vararg{Any}`; the widened specialization boxes every argument. The change: keep the exact specialization inference made, when the compileable signature merely widens a varargs tail.
- **Cycle members never inline each other.** Julia optimizes a cycle caller first and caches nobody's source until the cycle is finished. The change: callees first, each offered to the inliner of the later members.

The facts build exposes these every time, because (D) makes every recursion through `Dynamic` an inference cycle with four wrappers on its path. Both are improvements for stock Julia, and both apply to all code (julia 61852d8fb1; [`julia-changes.md` §2](julia-changes.md#2-the-inliner-and-how-the-compilers-own-code-is-compiled)). The system image grows 0.4%. The plain baselines in this chapter are therefore patched-plain; stock comparisons use the stock binary. The "calls per visit" counts read from `code_typed` after execution are optimistic: reflection shows freshly inferred code, not necessarily the code that ran.

### 3. Work in a session should be work an image could have held (principle right, mechanism partly a workaround)

Several costs were session-time work that no image kept: the checks' private cache, the compiler's code for a custom interpreter, and `_return_type`'s missing code in the system image (stock Julia too: 75–93 ms on the first unfoldable run-time `return_type` in every session). The fixes for these three are principled.

The forks' `String15` workload extension (`CSVDataFramesInlineStringsExt`) is a workaround (review D3):
- The need is partly self-made: upstream CSV has InlineStrings as a hard dependency, and the forks made it a weak one.
- Workload extensions per package combination are hand-written and combinatorial; nothing in the design derives one from a declaration.
- The design's own answer is [traits §13](../reference/traits.md#13-compiling-ahead) ("AOT follows from declared targets"): an implementation declared in `CSVInlineStringsExt` should compile the reader's declared workers for the new key at precompile time. DataFrames' kernels over a `String15` column belong in a DataFrames image.

The `String15` read without the three-way extension (with the check by facts alone) has not been measured.

### 4. The thesis, measured: what loads still cost (direction supported, residue not fully diagnosed)

A new implementation costs the same with or without big loads (E-146, 2026-10-20, first calls timed whole, the garbage collector's time subtracted):
- TDE, `@implement` / first solve: 69–70 / 335–338 ms with the loads before, 70–74 / 338–350 ms after, against 66 / 340–371 ms. The first solve is mostly the solver compiled for the new key;
- TraitMakie, a new data type (round of 2026-10-20, the PNG timed inside `@elapsed`): 45–47 / 81–84 ms before, 39–40 / 73–76 ms after, against 22 / 72–74 ms.

The other TDE rows are the same in every load order too, except the first gradient (82–89 against 68–70 ms). Until E-146, four rows differed: plain helpers of TraitWorld (`_tw_type`) and of the demonstrator (`solve`'s front end) compiled again after the loads, and a generator's code in TraitWorld's image made invalid by a package loaded before it; the fixes are in TraitWorld 226db6a and TraitDifferentialEquations 99393b9 (`experiments/loadcosts/README.md`).

One residue is diagnosed. TraitReport's work after StatsBase or Distributions (344–417 ms against 41, round of 2026-10-20) comes from SparseArrays, a standard library, which those packages load. Its `vcat` for Base's `Number` and `Vector` wins at a fact signature inside `CSV._parse`. The facts mode follows it (rule P) and recompiles that function. The design counts the standard libraries as Julia's own code ([glossary](../glossary.md) §1), so this is a stakeholder's change: not a pirate, not refused by strict mode (`TraitWorld/src/strict.jl:125`). It falls under "code it depends on changes". Whether standard libraries should be separate owners is open ([`../open-issues.md`](../open-issues.md) §1.19).

## The control: whose property is load protection?

The same work and the same nine unrelated loads (OffsetArrays, StatsBase, Unitful, IntervalArithmetic, Distributions, Interpolations, StaticArrays, CairoMakie, REPL), loaded after the work, on the patched build of the round of 2026-10-20, plain mode against `all` (everything compiled by facts, the test bed's system image):

| | plain mode | `all` |
|---|---|---|
| PlainTables + TraitMakie: CodeInstances lost to the loads | 14 of 256 | **0 of 244** |
| PlainTables' work: first / repeated / after the loads | 104 / 28.6 / 96 ms | **80 / 28.8 / 28 ms** |
| upstream CSV + DataFrames: CodeInstances lost (their own modules only; Base is not counted) | 561 of 4,684 | **2 of 3,337** |
| their first work / repeated / after the loads | 3,308 / 0.6 / 4,021 ms | **516 / 0.9 / 435 ms** |

Under `all`, the counted packages keep their code, and PlainTables' work is unaffected by the loads. Load protection is the facts rule's property, for any code: framing step 3. Upstream CSV + DataFrames pay **435 ms** after the loads under `all` (repeated work is 0.9 ms; plain Julia pays 4.0 s). On the build of 2026-10-19 they paid ~990 ms (first work 722 ms), and the diagnosis below was made then; the 435 ms has not been profiled again. The cost is the plain inference behind run-time `return_type`. Its cached answers rest on plain edges at abstract signatures (an `isapprox(::Integer, ::Integer)`, a `quantile!(::AbstractVector, …)`); the loads invalidate them (Unitful's `Colon(::Any, ::Any, ::Quantity)` alone 733 entries); `CSV.read` and `describe` ask again, and plain inference, optimizer included, runs again (70% of the profile). This is by design: the answers are plain Julia's, so a load that changes plain inference changes them. The optimizer cannot be skipped: without it the answers get wider (CairoMakie's workload then fails) (`experiments/factscompiler/step0/`). The compiler's own code, invalidated by REPL's interpreter methods, costs nothing here: REPL alone left the work at 2 ms (build of 2026-10-19). The harness needs `~/.julia` named in `JULIA_DEPOT_PATH`: in 1.13 a trailing `:` adds only the bundled depots.

## Detail work

- A closure in `return_type_tfunc` captured type values (our own facts addition), so it was specialized and compiled again for every query (about 70 ms each). The class of bug to watch for: compiler code whose closure types carry user types.
- `_return_type(::NativeInterpreter, ::DataType)` missing from the system image: an upstream gap; a small PR, ready.
- `Dynamic` operations are fixed-arity calls, not calls through a varargs wrapper.
- Benchmark hygiene:
  - A plain loop with a literal `16` unrolls, which made the gap of typed calls look larger (36 ns against plain 30); a fair baseline, with the length an argument, gives 2.3 ns (7%).
  - A dependency resolved differently in stacked environments made a 7 s `using` (a cache rebuilt once).
  - First runs after a rebuild include precompilation.

## Costs that remain, and why

- **The trait object's layout.** A `Dynamic` of an immutable value that is itself the receiver is a held view (TraitWorld 375a930), which holds the value whole: 0.92–0.96 ns against plain-closed 0.87–0.91 cache-resident, 4.5–5.7 against 3.9–4.0 ns at 10⁶ elements. Immutable values forwarding to a field, and mutable values, keep the read-through view.
- **Recursion through `Dynamic`:** 1.26–1.31× plain-closed (rtopen).
- **Untyped calls:** measured through the table of declared implementations (TraitWorld bed3782), 28.8 ns per call against 18.9 ns for a plain untyped call (product setting), 30.8 against 17.6 ns under `all`, 16 bytes per call (round of 2026-10-20). Before, with two dynamic dispatches (the `conformance` lookup, the worker) and a boxed trait object: 116 ns against about 55 ns (julia 61852d8fb1, TraitWorld 375a930). Type-unstable code was never claimed fast. An untyped caller passes a `Dynamic` value ([traits §6](../reference/traits.md#6-values-in-trait-code-compiled-and-dynamic)); the table serves a value it converts with `compiled_for` ([lowering §9.3](../reference/lowering.md#93-untyped-callers-of-compiled-values-the-table)). The `Dynamic` path's costs are open issues item 35, measured in W-17.
- **`@implement` of a new problem type** (measured as a model type, before W-2; W-2's quick check: 97 ms, three declared fields more), 66–74 ms in every load order (E-146; 142–164 ms on the build of 2026-10-19): the implementation checks' plain-rule inference.
- **A new problem type's first solve**, 335–371 ms timed whole: the solver compiled for the new key, about 330 ms of it (E-146). Each new receiver type compiles the library's code once; this is that once.
- **Platform load cost:** the trait forms' `using` is above the plain forms' (round of 2026-10-20): TraitReport's (t) imports 0.02–0.03 s above (pt)'s, its form (b) 0.18–0.20 s above (a′)'s.

## Upstream candidates

- **Ready as they are:**
  - 40512f64c2 (`_return_type` in the image).
  - bb82a82bbf (reflection runs an explicit `NativeInterpreter` in the typeinf world): a one-line generalization upstream.
- **After broader measurement in plain Julia** (they apply to all code in the patched build):
  - the cycle-inlining change;
  - the compileable-signature change (`only_vararg_widened`).
- **Needed only because of the facts mode:**
  - the Compiler's "never by facts" flag and `leaves_to` both ways;
  - `@machinery`;
  - the checks on a `NativeInterpreter` with their own cache owner;
  - the first-call check by facts. This one weakens the static check's coverage (results of run-time sites are `Any`; run-time guards still hold).

## Not done

- Like-for-like TraitReport forms under loads (form (t) against the previous prototype's form (t)).
- A profile of the 435 ms after the loads; the forks' session on a quiet machine; the run-time rows on the round's build.
- Acceptance checks for the inliner changes (cycle inlining, compileable signatures) and the compiler-plain edges.
