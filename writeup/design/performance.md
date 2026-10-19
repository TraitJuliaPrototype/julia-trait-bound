# Performance: where the costs come from

A chapter of [The implementation in detail](implementation.md): what the facts+traits compiler costs, where the costs come from, and what it teaches about placing code, on julia-1.13 with parts (A)–(D), as of 2026-10-19. The tables with builds and run counts are in [`evidence.md`](evidence.md); the detailed log, with every number, is `../../session-notes/2026-10-18-29-reviews-and-decisions.md`; the review of this work is `../reviews/2026-10-19-performance-phase.md`. How the numbers got here, from earlier builds, is in [`../record/design-history.md`](../record/design-history.md#the-performance-phase).

## Where things stand

The runs are one process per load order (n = 1).

| What | Now | Baseline |
|---|---|---|
| raytrace over `Dynamic{Scene}` (rtopen) | 300–336 ms (held views, julia 61852d8fb1) | plain closed by accident 246–259 ms; plain with four `Scene` types 827–882 ms (a `max_methods = 3` effect: four types are one over plain inference's split limit, and the trait split stops at four too) |
| raytrace, small case | 4.7–5.3 ms, 3.8 MB | plain 3.9–4.7 ms, 3.3 MB |
| sum over `Dynamic{Shape}` (cache-resident) | 0.92–1.40 ns per element | plain closed 0.87–0.91, plain with four methods 29.5–33 ns |
| the same over 10⁶ elements | 4.5–5.7 ns | plain closed 3.9–4.0 ns |
| typed call `total(x, 16)` | 36–38 ns | the same loop with `len` an argument: 33.8–34.5 ns |
| a varargs wrapper in a plain recursion (the review's probe) | 0.36–0.44 ms, 0 bytes (patched, plain code) | stock 1.13.2: 21.9–23.3 ms, 16.8 MB |
| TDE: a new model type, after CSV + DataFrames + CairoMakie | 148–164 ms, 89–133 ms | without loads: 142 / 82 ms (previous prototype: 0.16–0.23 s / 33–44 ms) |
| TraitMakie: a new data type (forwarding), after the loads | 97 ms + 89–161 ms | without loads: 77 / 107 ms |
| TraitMakie: the same, **without loads** | 77 ms + 89–107 ms | an earlier build of the compiler: 36 ms + 40 ms: **a regression of the clean case** (probably `@machinery`'s cost, below) |
| TraitReport form (t), fresh process | 0.76 s | the same without traits (pt) 0.72 s; Python 0.58–0.69 s (measured earlier, not rerun) |
| TraitReport form (b), work, nine packages loaded first | 338–342 ms (41 ms without loads) | form (a′), plain: 3,086 ms. `using`: trait 1.09–1.18 s against plain 0.91–0.99 s |
| forks: interactive session without imports | 2.85 s | upstream CSV + DataFrames 10.40 s; imports 1.70–2.09 s against upstream's 1.33–1.42 s |
| forks: first `stringtype = String15` read (a script: the read alone) | 0.041–0.046 s | without the fixes 1.74 s. Not separated: the extension and the check by facts. The session harness's step (read and display), 1.56–1.67 s, predates the fixes and has not been rerun |
| TDE run time per step, Lorenz | model type 158 ns | OrdinaryDiffEq 346 ns |

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
- **`@machinery`'s clean-case cost.** The machinery is type-unstable by nature, so as facts code its run-time sites compile facts copies of Base methods in each session, unless TraitWorld's image holds them. This is the likely cause of TraitMakie's clean regression (36 → 77 ms). It is not yet measured by owner. The completion is a precompile workload for the machinery under its owner.
- **A hole in "protected as trait code" (review B1).** `@machinery` code that calls compiler functions directly (`argextype`, `sptypes_from_meth_instance`, the `NativeInterpreter` constructor, `register_dynamic_candidate!`) holds edges to *plain* compiler CodeInstances. Those are valid only as long as plain Julia keeps them valid. Calls through Base reflection run in the typeinf world and are safe; direct calls are not.
- **`dynamic_call` is a compiler method,** so the module flag marks it plain too. That is safe only because inference intercepts it.

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
- The design's own answer is [`implementation.md` §4.8](implementation.md#48-aot-follows-from-declared-targets) ("AOT follows from declared targets"): an implementation declared in `CSVInlineStringsExt` should compile the reader's declared workers for the new key at precompile time. DataFrames' kernels over a `String15` column belong in a DataFrames image.

The `String15` read without the three-way extension (with the check by facts alone) has not been measured.

### 4. The thesis, measured: what loads still cost (direction supported, residue not fully diagnosed)

A new implementation after big loads costs about what it costs without them (TDE 148–164 / 89–133 ms against 142 / 82 ms; TraitMakie 97 / 89–161 ms against 77 / 107 ms). That is not yet "the only load-dependent cost". Other rows still differ after loads: TDE's row 4 after loads 171 ms against 12; row 1 with the loads before 27.8 against 10.0 ms; TraitMakie's recolour 231 against 102 ms (n = 1).

One residue is diagnosed. TraitReport's work after StatsBase or Distributions (333–410 ms against 41) comes from SparseArrays, a standard library, which those packages load. Its `vcat` for Base's `Number` and `Vector` wins at a fact signature inside `CSV._parse`. The facts mode follows it (rule P) and recompiles that function. The design counts the standard libraries as Julia's own code ([`implementation.md`](implementation.md#1-terms) §1), so this is a stakeholder's change: not a pirate, not refused by strict mode (`TraitWorld/src/strict.jl:125`). It falls under "code it depends on changes". Whether standard libraries should be separate owners is open ([`../open-issues.md`](../open-issues.md) §1.19).

## The control: whose property is load protection?

The same work and the same nine unrelated loads (OffsetArrays, StatsBase, Unitful, IntervalArithmetic, Distributions, Interpolations, StaticArrays, CairoMakie, REPL), loaded after the work, on the patched build, plain mode against `all` (everything compiled by facts, the test bed's system image):

| | plain mode | `all` |
|---|---|---|
| PlainTables + TraitMakie: CodeInstances lost to the loads | 14 of 218 | **0 of 206** |
| their work after the loads (repeated: 27.5 / 27.8 ms) | 96.1 ms | **29.4 ms** |
| upstream CSV + DataFrames: CodeInstances lost (their own modules only; Base is not counted) | 570 of 4,712 | **2 of 3,340** |
| their first work / repeated / after the loads | 3,627 / 0.6 / 4,009 ms | **722 / 0.8 / 992 ms** |

Under `all`, the counted packages keep their code, and PlainTables' work is unaffected by the loads. Load protection is the facts rule's property, for any code: framing step 3. Upstream CSV + DataFrames still pay **~990 ms** after the loads under `all` (repeated work is 0.8 ms). The counted CodeInstances do not explain it, and the count leaves out Base code compiled by facts. Pirate-following like TraitReport's is the hypothesis, not a diagnosis. The next step is a full list of what is lost or compiled, naming the winning methods. The harness needs `~/.julia` named in `JULIA_DEPOT_PATH`: in 1.13 a trailing `:` adds only the bundled depots.

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
- **Untyped calls:** two dynamic dispatches (the `conformance` lookup, the worker) and a boxed trait object, 116 ns against about 55 for a plain untyped call. Type-unstable code was never claimed fast.
- **`@implement` of a new model type**, 142–164 ms in every load order: the implementation checks' plain-rule inference.
- **Platform load cost:** the trait forms' `using` is 0.04–0.20 s above the plain forms' (TraitReport's two pairs).

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

- Python's baseline was not rerun: its venv is gone from `/tmp`.
- Like-for-like TraitReport forms under loads (form (t) against the previous prototype's form (t)); the session harness after the `String15` fixes; the BaseBenchmarks row of [`implementation.md` §3.3](implementation.md#33-step-3-the-facts-rule-extends-the-guarantee-to-all-code-at-a-cost-where-code-is-not-fully-typed) on the current compiler.
- Acceptance checks for the inliner changes (cycle inlining, compileable signatures) and the compiler-plain edges.
