# Performance on the facts+traits compiler: what we found, what it teaches

Session 29's performance phase (2026-10-19), on julia-1.13 with parts (A)–(D). The detailed log, with every number, is `session-notes/2026-10-18-29-reviews-and-decisions.md`; this note keeps the results and the themes.

## Where things stand

| What | Before the phase | After | Baseline |
|---|---|---|---|
| raytrace over `Dynamic{Scene}` (rtopen) | 3,281 ms | 384–419 ms | plain closed by accident 232–250 ms; plain with an open set (4 types) 799–881 ms |
| raytrace, small case | 54 ms, 72.6 MB | 6.1 ms, 3.8 MB | plain 3.8 ms, 3.3 MB |
| sum over `Dynamic{Shape}` (cache-resident) | | 1.45–1.61 ns per element | plain closed 0.87, plain open 29 ns |
| typed call `total(x, 16)` | | 36 ns | the same loop with `len` an argument: 33.7 ns |
| TDE: a new model type, after CSV + DataFrames + CairoMakie | `@implement` 2.0 s, first solve 2.1 s | 148–164 ms, 89–133 ms | without loads: 142 / 82 ms (session 27: 0.16–0.23 s / 33–44 ms) |
| TraitMakie: a new data type (forwarding), after the loads | 5.5 s + 2.1 s | 97 ms + 89–161 ms | without loads: 77 / 107 ms |
| TraitReport form (t), fresh process | 1.11–1.13 s | 0.76 s | the same without traits (pt) 0.72 s; Python 0.58–0.69 s |
| TraitReport's work, nine packages loaded first | 620 ms | 338–342 ms (41 ms without loads) | plain 3,086 ms |
| forks: interactive session without imports | | 2.85 s | upstream CSV + DataFrames 10.40 s |
| forks: first `stringtype = String15` read | 1.6 s | 0.046 s | upstream 0.19 s |
| TDE run time per step, Lorenz | | model type 158 ns | OrdinaryDiffEq 346 ns |

## The themes

Most of the work was not detail work. Three themes cover nearly every fix, and one result tests the thesis.

### 1. Every piece of code has an owner, and its performance follows from the owner

The facts mode makes "who compiles this code, under which rules" a property of each method. Code in the wrong owner caused nearly every large regression:

| Code | Owner it had | What that cost | Owner it needs |
|---|---|---|---|
| The compiler, called from facts code (TraitWorld's checks) | `:facts`: everything a facts frame calls was compiled by facts | the abstract interpreter ran as type-unstable facts code, 6× slower | plain, whoever calls it (module flag "never by facts" on Compiler) |
| TraitWorld's machinery (checks, finding builders, hooks) | plain | invalidated by every big load, then re-inferred in a larger method table: 2 s per new conformance | facts (`@machinery`, the per-method mode) |
| The compiler's code for the checks' custom interpreter | plain, run at the latest world | invalidated by loads, JIT-compiled again: 3.7 s | the compiler's own world (a `NativeInterpreter` with its own cache owner; Base reflection runs it in the typeinf world) |
| The first-call check's inference of a worker's call graph | a private cache (`_CheckOwner`) | 3,100 CodeInstances per new key, shared with nothing and never in an image: 1.6 s | the code that runs (reflection by facts: shared with the worker's compilation and kept in images) |

The lesson: facts code is load-proof but slow where it is type-unstable, and plain code is fast to infer but invalidatable. The compiler must sit in a frozen world. Placing each component explicitly is part of the design. It was not an implementation detail. design.md §6 had said "the compiler's own code stays plain", but only the test bed did so.

### 2. The facts mode turns dynamic call graphs into static ones, and the optimizer's heuristics assumed the dynamic case

(D) makes a recursion through `Dynamic` values (a scene graph, a tree) an inference cycle. Plain Julia met that recursion at run time and never saw the cycle. Two optimizer habits that are harmless in plain Julia cost 10× here:
- **Compileable signatures.** A call the inliner cannot inline is invoked at the method's compileable signature, which widens a varargs tail to `Vararg{Any}`. Plain Julia dispatches at run time anyway. Under facts it threw away the fact signature the call was inferred at, and the widened specialization boxed every argument: 72 MB per raytrace. Fix: under facts an invoke keeps the fact signature.
- **Cycle members never inline each other.** Julia optimizes a cycle caller first and caches nobody's source until the whole cycle finishes. Every wrapper on the recursion's path (the `Dynamic` operation, the trait object's method, `opcall`, `_dispatch`) made one call per turn. Fix: under facts, callees are optimized first and offered to the inliner of the later members.

The lesson: each place where Julia relies on "this will be dispatched dynamically anyway" needs a facts version. These two were found by measuring. There may be more of the same kind; type-stable recursion is where to look.

### 3. Work in a session should be work an image could have held, and the design gives it a place

Several costs were session-time work that no image kept. The checks' private cache, the compiler's code for a custom interpreter, and `_return_type`'s missing code in the system image (stock Julia too: 80–90 ms on the first run-time `return_type` of every session) were three cases. The fourth was the forks' `String15` read: the code existed only once CSV, DataFrames and InlineStrings were all loaded. The design answers that with extensions: an extension's image exists exactly when its packages are loaded, so an extension over all three (`CSVDataFramesInlineStringsExt`) carries the workload. The same principle produced `CSVDataFramesExt` earlier.

### 4. The thesis, measured: after the fixes, what loads still cost is piracy

After the fixes, a new conformance after big loads costs what it costs without them. The one load-dependent cost left is TraitReport's work after StatsBase or Distributions (333–410 ms against 41). Its cause is precise: those packages load SparseArrays, which defines `vcat` for Base's `Number` and `Vector`. That method wins at a fact signature inside `CSV._parse`, and the facts mode follows it by design (rule P) and recompiles that function. In other words, the residue is exactly what the thesis says can change fully typed code: a pirate, here a standard library. Strict mode would refuse it, which makes a concrete case for that discussion.

## What is detail work

- A closure in `return_type_tfunc` captured type values (our facts addition), so it was specialized and compiled again for every query (70 ms each). The class of bug to watch for: compiler code whose closure types carry user types.
- `_return_type(::NativeInterpreter, ::DataType)` missing from the system image: an upstream gap worth a small PR.
- `Dynamic` operations called through a varargs wrapper: replaced by fixed-arity calls.
- Benchmark hygiene. The "typed call 36 ns against plain 30" gap was mostly the plain loop's literal `16` (unrolled); a fair baseline gives 2.3 ns (7%). A dependency resolved differently in stacked environments made a 7 s `using` (a cache rebuilt once). First runs after a rebuild include precompilation.

## Costs that remain, and why

- **The trait object's layout.** A `Dynamic` read is one `o === nothing` branch, plus a `TObj` with its view of ~48 bytes against a 16-byte box: 1.7× plain-closed in a cache-resident sum, 2× at 10⁶ elements. That follows from one worker per key, serving held and read-through values alike. A view variant for held immutable values would remove both, at one more worker per key used both ways: a design question for the user.
- **Recursion through `Dynamic`:** three calls per Group visit against plain's one (1.65× plain-closed, 2× faster than plain-open).
- **Untyped calls:** two dynamic dispatches (the conformance, the worker) and a boxed trait object, 116 ns against about 55 for a plain untyped call. Type-unstable code was never claimed fast.
- **`@implement` of a new model type**, 142–164 ms: the conformance checks' plain-rule inference, in every load order.

## The control: whose property is load protection?

The same work and the same nine unrelated loads (OffsetArrays, StatsBase, Unitful, IntervalArithmetic, Distributions, Interpolations, StaticArrays, CairoMakie, REPL), loaded after the work, on the patched build, plain mode against `all` (everything compiled by facts, the test bed's system image):

| | plain mode | `all` |
|---|---|---|
| PlainTables + TraitMakie: CodeInstances lost to the loads | 14 of 218 | **0 of 206** |
| their work after the loads (27.5–27.8 ms when repeated) | 96.1 ms | **29.4 ms** |
| upstream CSV + DataFrames: lost | 570 of 4,712 | **2 of 3,340** (CSV) |
| their first work / after the loads | 3,627 / 4,009 ms | **722 / 992 ms** |

Load protection is the facts rule's property, and it extends to any code, traits or not: framing step 3. Traits contribute steps 2 and 4. They outlaw or follow pirates, and they make the facts rule cheap by saying what code needs (the run-time rows above). The 270 ms left after the loads under `all` is the same pirate-following as TraitReport's. (The control had first failed in the harness: in 1.13 a trailing `:` in `JULIA_DEPOT_PATH` adds only the bundled depots, not `~/.julia`.)

## Not done

- Python's baseline was not rerun: its venv is gone from `/tmp`.
