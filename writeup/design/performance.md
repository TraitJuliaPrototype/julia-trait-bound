# Performance on the facts+traits compiler: what we found, what it teaches

Session 29's performance phase (2026-10-19), on julia-1.13 with parts (A)–(D). The detailed log, with every number, is `../../session-notes/2026-10-18-29-reviews-and-decisions.md`. The Fable review of this phase, `../reviews/2026-10-19-performance-phase.md`, corrected three of the four themes as first written; this version includes its corrections.

## Where things stand

The final runs are one process per load order (n = 1). Earlier runs were two.

| What | Before the phase | After | Baseline |
|---|---|---|---|
| raytrace over `Dynamic{Scene}` (rtopen) | 3,281 ms | 300–336 ms (held views, julia 61852d8fb1) | plain closed by accident 246–259 ms; plain with four `Scene` types 827–882 ms (a `max_methods = 3` effect: four types are one over plain inference's split limit, and the trait split stops at four too) |
| raytrace, small case | 54 ms, 72.6 MB | 4.7–5.3 ms, 3.8 MB | plain 3.9–4.7 ms, 3.3 MB |
| sum over `Dynamic{Shape}` (cache-resident) | | 0.92–1.40 ns per element (1.45–1.61 before held views) | plain closed 0.87–0.91, plain with four methods 29.5–33 ns |
| the same over 10⁶ elements | | 4.5–5.7 ns | plain closed 3.9–4.0 ns |
| typed call `total(x, 16)` | | 36–38 ns | the same loop with `len` an argument: 33.8–34.5 ns |
| a varargs wrapper in a plain recursion (the review's probe) | stock 1.13.2: 21.9–23.3 ms, 16.8 MB | 0.36–0.44 ms, 0 bytes (patched, plain code) | |
| TDE: a new model type, after CSV + DataFrames + CairoMakie | `@implement` 2.0 s, first solve 2.1 s | 148–164 ms, 89–133 ms | without loads: 142 / 82 ms (session 27: 0.16–0.23 s / 33–44 ms) |
| TraitMakie: a new data type (forwarding), after the loads | 5.5 s + 2.1 s | 97 ms + 89–161 ms | without loads: 77 / 107 ms |
| TraitMakie: the same, **without loads** | 36 ms + 40 ms | 77 ms + 89–107 ms | **a regression of the clean case** (probably `@machinery`'s cost, below) |
| TraitReport form (t), fresh process | 1.11–1.13 s | 0.76 s | the same without traits (pt) 0.72 s; Python 0.58–0.69 s (session 27) |
| TraitReport form (b), work, nine packages loaded first | 620 ms | 338–342 ms (41 ms without loads) | form (a′), plain: 3,086 ms. `using`: trait 1.09–1.18 s against plain 0.91–0.99 s |
| forks: interactive session without imports | | 2.85 s | upstream CSV + DataFrames 10.40 s; imports 1.70–2.09 s against upstream's 1.33–1.42 s |
| forks: first `stringtype = String15` read (a script: the read alone) | 1.74 s | 0.041–0.046 s | not separated: the extension and the check by facts. The session harness's step (read and display) was 1.56–1.67 s before the fixes and has not been rerun |
| TDE run time per step, Lorenz | | model type 158 ns | OrdinaryDiffEq 346 ns |

## The themes

### 1. Every piece of code has an owner, and its performance follows from the owner (the main lesson)

The facts mode makes "who compiles this code, under which rules" a property of each method. Code in the wrong owner caused most of the large regressions:

| Code | Owner it had | What that cost | Owner it needs |
|---|---|---|---|
| The compiler, called from facts code (TraitWorld's checks) | `:facts`: everything a facts frame calls was compiled by facts | the abstract interpreter ran as type-unstable facts code, 6× slower | plain, whoever calls it (module flag "never by facts" on Compiler) |
| TraitWorld's machinery (checks, finding builders, hooks) | plain | invalidated by every big load, then re-inferred in a larger method table: 2 s per new conformance | facts (`@machinery`, the per-method mode) |
| The compiler's code for the checks' custom interpreter | plain, run at the latest world | invalidated by loads, JIT-compiled again: 3.7 s | the compiler's own world (a `NativeInterpreter` with its own cache owner; Base reflection runs it in the typeinf world) |
| The first-call check's inference of a worker's call graph | a private cache (`_CheckOwner`) | 3,100 CodeInstances per new key, shared with nothing and never in an image | the code that runs (reflection by facts: shared with the worker's compilation and kept in images) |

Facts code is load-proof but slow where it is type-unstable, and plain code is fast to infer but invalidatable. The compiler must run in a frozen world. Placing each component is part of the design, and design.md §6 claimed "the compiler's own code stays plain" before the implementation did it.

**The choices have costs, which the first version of this note left out:**
- **`@machinery`'s clean-case cost.** The machinery is type-unstable by nature, so as facts code its run-time sites compile facts copies of Base methods in each session, unless TraitWorld's image holds them. This is the likely cause of TraitMakie's clean regression (36 → 77 ms). It is not yet measured by owner. The completion is a precompile workload for the machinery under its new owner.
- **A hole in "protected as trait code" (review B1).** `@machinery` code that calls compiler functions directly (`argextype`, `sptypes_from_meth_instance`, the `NativeInterpreter` constructor, `register_dynamic_candidate!`) now holds edges to *plain* compiler CodeInstances. Those are valid only as long as plain Julia keeps them valid. Calls through Base reflection run in the typeinf world and are safe; direct calls are not.
- **`dynamic_call` is a compiler method,** so the module flag marks it plain too. That is safe only because inference intercepts it.

### 2. Two Julia inliner habits that cost recursions through wrappers, found here and not specific to facts (corrected)

The first version said these were harmless in plain Julia and needed only a facts version. That is wrong (review A1, verified on stock 1.13.2). A varargs `@inline` wrapper inside a two-type recursion runs 56× slower in plain Julia too (22.5 ms against 0.40 ms, 16.8 MB against 0 bytes), with the same `Vararg{Any}` specializations.
- **Compileable signatures.** A call the inliner cannot inline is invoked at the compileable signature, which widens a varargs tail to `Vararg{Any}`; the widened specialization boxes every argument. Fix (gated on facts today): keep the signature the call was inferred at. The general form for upstream: prefer an existing exact specialization. As written it overrides `@nospecialize` for non-inlined calls from facts code and misses concrete-`Vararg` facts.
- **Cycle members never inline each other.** Julia optimizes a cycle caller first and caches nobody's source until the cycle is finished. Fix (gated on facts today): callees first, each offered to the inliner of the later members.

The facts build exposes these every time, because (D) makes every recursion through `Dynamic` an inference cycle with four wrappers on its path. Both are improvements for stock Julia. They are gated on facts only so that the plain baselines stay stock (a decision for the user, below). The "calls per visit" counts read from `code_typed` after execution are optimistic: reflection shows freshly inferred code, not necessarily the code that ran.

### 3. Work in a session should be work an image could have held (principle right, mechanism partly a workaround)

Several costs were session-time work that no image kept: the checks' private cache, the compiler's code for a custom interpreter, and `_return_type`'s missing code in the system image (stock Julia too: 75–93 ms on the first unfoldable run-time `return_type` in every session). The fixes for these three are principled.

The forks' `String15` workload extension (`CSVDataFramesInlineStringsExt`) is a workaround (review D3):
- The need is partly self-made: upstream CSV has InlineStrings as a hard dependency, and the forks made it a weak one.
- Workload extensions per package combination are hand-written and combinatorial; nothing in the design derives one from a declaration.
- The design's own answer is §4.8 ("AOT follows from declared targets"): a conformance declared in `CSVInlineStringsExt` should compile the reader's declared workers for the new key at precompile time. DataFrames' kernels over a `String15` column belong in a DataFrames image.

The `String15` read without the three-way extension (after the check-by-facts change alone) has not been measured.

### 4. The thesis, measured: what loads still cost (direction supported, residue not fully diagnosed)

After the fixes, a new conformance after big loads costs about what it costs without them (TDE 148–164 / 89–133 ms against 142 / 82 ms; TraitMakie 97 / 89–161 ms against 77 / 107 ms). That is not yet "the only load-dependent cost". Other rows still differ after loads: TDE's row 4 after loads 171 ms against 12; row 1 with the loads before 27.8 against 10.0 ms; TraitMakie's recolour 231 against 102 ms (n = 1).

One residue is diagnosed. TraitReport's work after StatsBase or Distributions (333–410 ms against 41) comes from SparseArrays, a standard library, which those packages load. Its `vcat` for Base's `Number` and `Vector` wins at a fact signature inside `CSV._parse`. The facts mode follows it (rule P) and recompiles that function. The design counts the standard libraries as Julia's own code ([`../design.md`](../design.md) §1), so this is a stakeholder's change: not a pirate, not refused by strict mode (`TraitWorld/src/strict.jl:125`). It falls under "code it depends on changes". Whether standard libraries should be separate owners is open ([`../open-issues.md`](../open-issues.md) §1.19).

## The control: whose property is load protection?

The same work and the same nine unrelated loads (OffsetArrays, StatsBase, Unitful, IntervalArithmetic, Distributions, Interpolations, StaticArrays, CairoMakie, REPL), loaded after the work, on the patched build, plain mode against `all` (everything compiled by facts, the test bed's system image):

| | plain mode | `all` |
|---|---|---|
| PlainTables + TraitMakie: CodeInstances lost to the loads | 14 of 218 | **0 of 206** |
| their work after the loads (repeated: 27.5 / 27.8 ms) | 96.1 ms | **29.4 ms** |
| upstream CSV + DataFrames: CodeInstances lost (their own modules only; Base is not counted) | 570 of 4,712 | **2 of 3,340** |
| their first work / repeated / after the loads | 3,627 / 0.6 / 4,009 ms | **722 / 0.8 / 992 ms** |

Under `all`, the counted packages keep their code, and PlainTables' work is unaffected by the loads. Load protection is the facts rule's property, for any code: framing step 3. Upstream CSV + DataFrames still pay **~990 ms** after the loads under `all` (repeated work is 0.8 ms). The counted CodeInstances do not explain it, and the count leaves out Base code compiled by facts. Pirate-following like TraitReport's is the hypothesis, not a diagnosis. The next step is a full list of what is lost or compiled, naming the winning methods. (The control had first failed in the harness: in 1.13 a trailing `:` in `JULIA_DEPOT_PATH` adds only the bundled depots, not `~/.julia`.)

## Detail work

- A closure in `return_type_tfunc` captured type values (our own facts addition), so it was specialized and compiled again for every query (about 70 ms each). The class of bug to watch for: compiler code whose closure types carry user types.
- `_return_type(::NativeInterpreter, ::DataType)` missing from the system image: an upstream gap; a small PR, ready.
- `Dynamic` operations called through a varargs wrapper: replaced by fixed-arity calls.
- Benchmark hygiene:
  - The "typed call 36 ns against plain 30" gap was mostly the plain loop's literal `16` (unrolled); a fair baseline gives 2.3 ns (7%).
  - A dependency resolved differently in stacked environments made a 7 s `using` (a cache rebuilt once).
  - First runs after a rebuild include precompilation.

## Costs that remain, and why

- **The trait object's layout: done.** A `Dynamic` of an immutable value that is its own implementing value was a trait object pointing to a boxed copy of the value (two pointer chases), with an `o === nothing` branch per read. The held view (the user's decision; TraitWorld 375a930) holds the value whole: 0.92–0.96 ns against plain-closed 0.87–0.91 cache-resident, 4.5–5.7 against 3.9–4.0 ns at 10⁶ elements. Immutable values forwarding to a field, and mutable values, keep the read-through view.
- **Recursion through `Dynamic`:** 1.26–1.31× plain-closed (rtopen), from 1.65×.
- **Untyped calls:** two dynamic dispatches (the conformance, the worker) and a boxed trait object, 116 ns against about 55 for a plain untyped call. Type-unstable code was never claimed fast.
- **`@implement` of a new model type**, 142–164 ms in every load order: the conformance checks' plain-rule inference.
- **Platform load cost:** the trait forms' `using` is 0.04–0.20 s above the plain forms' (TraitReport's two pairs).

## The two inliner fixes, ungated (the user's decision)

They now apply to all code (julia 61852d8fb1). A first general form, "keep any exact specialization inference made", crashed the system image build: an exact specialization at a non-concrete signature is not code to call. Restricted to dispatch tuples, it then also overrode Julia's widening of kinds (a `Type{Float64}` passed to a `::DataType` argument), the review's B2. That changed what the certificate sees and grew the system image by 2.2%. The final rule keeps the exact specialization only when the compileable signature merely widens a varargs tail; the system image grows 0.4%. The plain baselines in this note are therefore patched-plain from here on; stock comparisons use the stock binary.

## Upstream candidates

- **Ready as they are:**
  - 40512f64c2 (`_return_type` in the image).
  - bb82a82bbf (reflection runs an explicit `NativeInterpreter` in the typeinf world): a one-line generalization upstream.
- **After broader measurement in plain Julia** (now ungated in the patched build):
  - the cycle-inlining change;
  - the compileable-signature change (`only_vararg_widened`).
- **Needed only because of the facts mode:**
  - the Compiler's "never by facts" flag and `leaves_to` both ways;
  - `@machinery`;
  - the checks on a `NativeInterpreter` with their own cache owner;
  - the first-call check by facts. This one weakens the static check's coverage (results of run-time sites are `Any`; run-time guards still hold).

## Not done

- Python's baseline was not rerun: its venv is gone from `/tmp`.
- Like-for-like TraitReport forms under loads (form (t) against session 27's form (t)); the session harness after the `String15` fixes; the BaseBenchmarks row of design.md §3.3 on the current compiler.
- Acceptance checks for this phase's changes (cycle inlining, compileable signatures, compiler-plain edges).
