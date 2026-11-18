# Lessons from porting Tables, DataFrames and CSV (demonstrator 4)

Session 27 (2026-10-17), recorded while following `../plans/2026-10-17-dataframes-traits-plan.md`. The forks are in `forks/` (`git diff upstream`). Each item says what happened, whether it is a **design issue**, a **porting guideline** or a **tooling issue**, and what was done. Items marked **⟳** reintroduce recompilation in trait-bound code, or leave code the trait world should protect open to invalidation.

## 1. Wrapping by facts on real code

### 1.1 ⟳ Run-time sites ran native code, which loads invalidate (design issue; changed)

Under the policy, a call at abstract argument types is a run-time site. Until this session such a site dispatched into *plain Julia's native code*. Real packages are full of these sites: union-typed options, `Vector{Any}` of columns, types passed as values, keyword splats. So a worker protected only its own frame. Everything behind the first run-time site was native code: compiled again in every session, and invalidated by unrelated loads. Measured: `CSV._parse` was recompiled (`# recompile`) after `using DataFrames` although the reader was a worker.

**Done (TraitWorld 1d93677, decision pending):** a run-time site now dispatches at run time, in the caller's world, as before, and then runs the *policy's* CodeInstance of the method it found: `_call_under_policy`, compiled under the policy at the first call and kept in images. The dispatch semantics do not change, since no fact is recorded at the site; only the compiled code that runs does. `JULIA_TW_RUNTIME_SITES=native` restores the old behaviour. After the change, CSV keeps 661 policy CodeInstances, and loading DataFrames discards none of them (native CSV code: about 300 lost).

Open points:
- **Cost at hot run-time sites:** measured in session 28 and fixed, see 1.9.
- **Review needed:** G1 should hold, because dispatch is unchanged. G2 should improve. Theorem 2's statement ("code reached through run-time sites is native") needs restating.
- **Pitfalls met on the way:**
  - A builtin passed as a value (`tuple`, `===`) reached the trampoline, and the policy tried to compile its generic fallback at every call. Builtins are now called directly.
  - Instances the policy cannot compile were retried at every call; a negative cache fixes that.
  - Binding reads during IR rewriting ran in the compiler's world, which is older than the packages being compiled (world-age warnings). They now read in the inference world.

### 1.2 ⟳ Keyword splats were run-time sites (design issue; changed)

Every `f(x; kw...)` that forwards keywords made the keyword-body call a run-time site. `pairs(::NamedTuple)` computes its element type with `eltype(Tuple{…})`, which calls `promote_typejoin` on types held as `DataType` values. Plain Julia folds this through Base's own effect assertion (`@_total_meta`). The policy refused compile-time evaluation over any callee with a run-time site, so the element type stayed unknown, the keyword body was called at abstract types, and everything after it ran natively. Most of the ecosystem forwards keywords.

**Done (TraitWorld c62e23e):** the policy folds where plain Julia folds by effects that *Julia itself asserts* (methods of Base or Core asserted foldable). The code is then exactly as fresh as plain Julia's precompiled code, so "identical or error" still compares against plain Julia. Only a pirate of Base's functions at Base's types can make either stale; strict mode refuses those. Tests and the 16 acceptance checks pass. **Needs a soundness review** (G1 under pirates).

### 1.3 Types passed as values are run-time sites (design rule; porting guideline)

By design a call with a kind (`DataType`, `Type{X}` widened) as an argument is a fact only for closures. CSV passes types as values everywhere (`stringtype::Type`, `allocatecolumn(T, …)`, `finalizecolumn(T, …)`). Julia's specialization heuristic also widens `x::Type` arguments to `Type`, so even `stringtype::Type{S}` did not help at the worker's call.

**Porting guideline:** carry a type across a policy boundary as an instance of a concrete type (`Val(stringtype)`, unwrapped where the type is needed), or as the column builder itself (a trait value), never as a `DataType`.

### 1.4 Union-typed values in keyword calls (porting guideline; possible design improvement)

`settlecolumns(p; select, drop, types, available, validate)` with a `Union{Nothing, Vector{ValueOpts}}` value builds `NamedTuple{names}(::Tuple{…, Union{…}, …})`. That is not a dispatch tuple, so the call is a run-time site. Settings structs with union-typed fields (`typemap`, `nsample`, `colopts`) do the same to positional calls once more than `max_union_splitting` unions meet.

**Guideline:** at policy boundaries, normalize options to concrete types; assert union-typed fields where they are read.
**Possible design improvement:** union-split tuple *elements* of an argument in the policy's fact check, which gives several facts at concrete signatures and is sound for the same reason as Julia's top-level union splitting. **Done for tuples in session 28 (1.8);** keyword `NamedTuple`s with union-typed values (`std(x; mean = m)`, `m::Union{Nothing, Float64}`) are still run-time sites: a `NamedTuple` is not covariant, so its splits would include the union-typed instance itself.

### 1.5 A run-time site's result is `Any` (porting guideline)

Under the policy a run-time site returns `Any` (no fact, so no inferred type), and everything downstream becomes a run-time site too. Plain inference would still have inferred a concrete type through the abstract call. CSV: `p = _prepare(buf; kw...)` gave `Any`, and the whole read after it was native.

**Guideline:** assert results at the boundaries of large internal stages (`::Prepared`, `::IndexedSource`, `::ColumnPlan`, `::ParsedTable`): one line each, and the rest of the path is facts. This is open-issues item 7 (results through an opened `Dynamic` are not inferred) seen from the other side.

### 1.6 `parentmodule(@__MODULE__).f` is a run-time site (porting guideline)

A trait module calling its parent package's internals through `parentmodule(@__MODULE__)._file(…)` made the call dynamic. **Guideline:** `const _CSV = parentmodule(@__MODULE__)`, then `_CSV._file(…)`.

### 1.7 A tool is needed to see run-time sites (tooling; nice to have)

Finding these took most of the porting time. `forks/scripts/runtime_sites.jl` walks the policy's CodeInstances from a worker and lists every dynamic call with its inferred argument types. It found every item above within minutes.
**Nice to have in TraitWorld:**
- `TraitWorld.runtime_sites(f)`;
- a precompile-time report: "worker `readfile` reaches N run-time sites; the first at `_prepareindexed`, keyword pairs with abstract element type".

### 1.8 Iteration over data with missing values was a run-time site per element (design issue; changed)

Session 28. After the first call, `describe` still took 0.24–0.31 s on 10 000 rows; upstream's second call takes 0.9 ms. The time was run time, not compilation: 0.13 s in each of the two columns with missing values, and 0.1 ms in the others. Base's `iterate(::SkipMissing)` destructures `item, state = y` with `y::Tuple{Union{Missing, Int64}, Int64}`. That tuple type is not a dispatch tuple, and the call has no top-level union, so the policy never split it: `indexed_iterate` became a run-time site, the state widened to `Any`, and every call after it in the loop went through the trampoline. `colstats` for one such column reached 58 run-time sites.

This is not a porting issue. Every element type `Union{Missing, T}` (most real data) iterates this way, in Base, Statistics, and anything a worker calls.

**Done (TraitWorld 5b50482):** a fact may stand at a signature whose tuple-typed arguments have unions of concrete element types (`_fact_splits`), up to Julia's `max_union_splitting` (4) splits. A tuple value's type is always concrete, so `Tuple{Union{Missing, Int}, Int}` admits exactly the values of `Tuple{Missing, Int}` and `Tuple{Int, Int}`: the fact is the facts at its splits, as with top-level union splitting. Strict mode checks a pirate against each split. Tests (with a new testset) and 16/16 acceptance pass.

After the fix: a column with missing values takes 0.3 ms, `describe` 1.3 ms at its second call (upstream 0.9 ms), and `colstats` reaches 8 run-time sites, all cold (`Dict{Symbol, Any}` writes, the keyword call of 1.4). **Needs the soundness review** with 1.1 and 1.2 (G1 and G2 under splits).

### 1.9 A hot run-time site cost 6.5 µs (design issue; changed)

Measured in session 28, with `mean` over a `Vector{Any}` column (one run-time site or more per element): 6.4–6.8 µs per element under the policy, against 26–29 ns for plain Julia's dynamic dispatch, about 230× slower. Profile:
- 40% in `Core.invoke(f, ci, args...)` with its splat;
- 24% in building `Tuple{…}` from the argument types;
- the rest in varargs boxing, `jl_method_lookup_by_tt` and the walk of the instance's cache.

**Done (TraitWorld 5b50482):** each run-time site of up to four arguments keeps its own cache (`_CallSite`, a constant in the IR), as Julia keeps one for its own dynamic dispatch:
- the cache holds the last dispatch: the world, the arguments' `Core.Typeof` and the CodeInstance;
- a call in the same world with the same keys calls `Core.invoke` directly. Dispatch is a function of the world and these keys, and a CodeInstance valid in a world stays valid in it;
- each entry carries a token of the process, so a cache stored in an image never hits with another process's world numbers.

**Pitfall met:** the first version keyed type values by the type itself (`Int64`), which collided with a *value* of type `Int64`. `Core.invoke` then raised "argument type error" inside TraitWorld's own ambiguity check. The key must be exactly the lookup's (`Core.Typeof`: `Type{Int64}`).

**Second pitfall:** the miss path (`_site_miss`, `_policy_ci`) took the arguments as `args::Tuple` without `@nospecialize`, so Julia compiled one specialization per combination of argument types, 60–90 ms each. Process start took 46 s, `using CSV, DataFrames` 170 s (TraitWorld 9ddd4a0 fixes it). Machinery reached from every run-time site must not specialize on what the site passes.

**Measured after both fixes** (image, REPL driver, median of 3 runs, 2 dropped for load; session 28):

| step | before (session 27, 1 run) | after |
|---|---|---|
| imports | 1.89 | 3.00 |
| read | 0.97 | 0.13 |
| describe | 0.50 | 0.14 |
| select_filter | 0.17 | 0.15 |
| user_function | 0.26 | 0.21 |
| 2_describe | 0.99 | 0.03 |
| 3_describe | 0.30 | 0.02 |
| **session (no imports)** | about 3.7 | **1.19** |

Upstream on the same patched build: 10.9 s; pandas: 0.32 s (`forks/README.md`, M0). The rise of `using` from 1.9 to 3.0 s was not investigated: the per-site caches are what the pivot removes (`../plans/2026-10-17-policy-in-compiler-plan.md`).

Remaining: the site is monomorphic (a site that alternates between types misses every time), and still pays a generic dispatch into `_call_site` and `Core.invoke`'s two subtype checks. The full remedy is owner-aware dynamic dispatch in the runtime (§5).

## 2. Where compiled code lives

### 2.1 ⟳ A package's entry points stay native unless they are trait-bound (design gap; porting guideline)

Only functions with a trait-bound argument become workers and are compiled under the policy. A DataFrames entry point such as `innerjoin(df, df2; on = :id)` is plain code. Its keyword body was in DataFrames' image and was invalidated by a later load (`# recompile`, 1.0 s). So was CSV's reader before it was given a bound.

**Guideline:** give a package's entry points a trait-bound argument the package's own types conform to. CSV got `CSVSource` (a path, an `IO`, bytes), and `File` calls the worker `readfile(src::CSVSource, …)`. This is natural for a reader; for DataFrames (`innerjoin`, `combine`, `show`) it means a trait that `DataFrame` and `GroupedDataFrame` conform to.
**Design question:** should a trait module be able to declare a plain-typed function "compiled under the policy" (a policy entry) without inventing a trait? It would make adoption by entry point direct.

### 2.2 ⟳ Keys from one package, functions from another (design question; porting guideline)

CSV produces column types DataFrames does not know: `DataStringVector` (CSV 1.1's default strings), `Durations.Timestamp` columns, pooled strings. DataFrames' workers for those keys exist in no image unless something compiles them. They cost 0.4–0.5 s per worker at first use: `colstats`, `refine!`, `refcodes`.

**Done:** `CSVDataFramesExt`, an extension of CSV on DataFrames that holds only a workload over CSV's column types. Its image exists exactly when both packages are loaded. After it: sort 0.025 s, groupby-combine 0.023 s, join 0.056 s at first call (upstream 1.2, 0.8, 1.3 s).
**Design question:** the design says workers for a key live "in the image of the package that declared the conformance". Here the conformance is Tables' family for every `AbstractVector`, and neither the key's owner nor the function's owner sees the other. A glue extension per (key owner, function owner) pair is plain Julia's remedy; the trait world makes it safe (policy code, not invalidated) but not automatic. The view cache is the automatic remedy, after the first session.

### 2.3 Workloads must cover keyword combinations and IO types (porting guideline)

Two first-call costs were plain Julia's, not trait-world issues:
- `innerjoin`'s keyword body is compiled per keyword set (`on` alone vs `on, makeunique`);
- PrettyTables' body is compiled per IO type (the REPL's `IOContext{LimitIO{TTY}}` vs the workload's `IOBuffer`).

**Done:** DataFrames renders into an `IOContext{IOBuffer}` carrying the terminal's properties, then writes once (a plain fix, worth upstreaming); the workload covers `on = :c` alone. These count against "traits" in the comparison: the README must list them as plain fixes.

### 2.4 ⟳ Every TraitWorld change means a new system image and recompiling everything (tooling)

With the policy in the system image (open-issues §1.3), each change to TraitWorld needs the image rebuilt (about 100 s) and every dependent package recompiled for it (about 3 min for the three forks). A stale image silently runs the old TraitWorld: the builtin fix above showed no effect until the rebuild.
**Nice to have:**
- a check that the image's TraitWorld matches the source;
- the policy in Julia's own compiler, which is the real fix (piece 11, deferred).

### 2.5 ⟳ REPL first (known, open-issues §1.3)

With the REPL loaded first and no system image, a session compiles the policy's compiler code again: the first read took 9.4 s. With the image it took 0.3 s. REPL's *own* code (`complete_line`, `add_history`) is also invalidated by package loads (0.5–0.7 s). This hits upstream and the forks alike, and belongs in the imports row.

## 3. Porting guidelines that worked

- **Storage change behind an adapter.** `DataFrame.columns::Vector{Dynamic{Column}}`, with `_columns(df)` returning a view (`ColumnVectors <: AbstractVector{AbstractVector}`) that reads and writes through the dynamic values. DataFrames' 46 storage sites and its full test suite ran unchanged; one test line was adapted.
- **`vector(c)` as a `Column` operation** returns the stored vector itself. So `df.a === v` holds, and a worker can run upstream's own code at the key's concrete type (`colstats`, `refine!`, `innerrows` are upstream bodies called on `vector(c)`).
- **Per-column codes replace per-tuple specialization.** groupby's two algorithms (reference pools; first appearance) are reproduced per column in workers and combined in integer code. A random equivalence test against `row_group_slots!` gave 0 mismatches in 2,368 cases. Multi-column sort is a stable refinement per column, last to first.
- **`Column` without `@concrete_only`** (decision 1): `Vector{Any}` and `SubArray` columns needed nothing special.
- **Pull more into the trait world.** Each boundary moved inward (the reader's entry, then its run-time sites) removed recompilation that no workload could prevent. The rule of thumb: whatever a user calls should enter the trait world at once, and stay in it.

## 4. Tooling notes

- Pkg did not refresh a path package's `weakdeps`/`extensions` in the manifest after its `Project.toml` changed (`Pkg.resolve` reported no change), so the new extension silently never loaded; the manifest was edited by hand.
- `--trace-compile=stderr --trace-compile-timing` inside the REPL session, plus marks per step, was the most useful measurement; `# recompile` flags invalidated native code.
- **A first-call time is not all compilation** (session 28). `describe` at 0.45 s compiled for 0.17 s; the rest was run time (1.8). Timing the step a second time in the same session separates the two at once, and should be part of every per-step table.
- **The image build was killed silently** (session 28). The memory watchdog's message was overwritten, because Julia wrote `build.log` through a truncating redirect at its own offset; the log is now appended to (`experiments/sysimage/build.sh`). `/tmp` is a tmpfs, so the archives of killed juliac builds (`jl_*/img.a`, 5.2 GB from 2026-10-15) held memory until removed.

## 5. What the compiler would remove (session 28)

Prompted by the user's question: which of these issues would be easier, or disappear, with the policy in Julia's compiler? Three settings of one switch were discussed: policy off, policy for trait-bound code, policy for all code.

| | setting | what the compiler needs |
|---|---|---|
| off | today's Julia | nothing |
| all code | one interpreter, one cache, ordinary dispatch | (A) facts as an inference mode: the fact check, folding, `return_type` |
| trait-bound code | fact code and plain code side by side | (A), plus (B) a second cache owner (the same `sum` compiled both ways), plus (C) owner-aware dynamic dispatch (a run-time site in fact code selects fact code) |

(A) is the core of both; "all code" is the simpler step towards the middle setting.

**Gone with (B) and (C) in the runtime:**
- 1.1 and 1.9: a run-time site would be plain dynamic dispatch selecting the caller owner's code, at plain dispatch's cost, with no trampoline, negative cache, site cache or builtin special case;
- 2.4 and 2.5: the policy's compiler code would be protected as Julia protects its own compiler;
- patch pieces 5, 9, 10, 12 and 13, which exist because the owner is foreign;
- piece 11's two obstacles and assumption A4 (threads).

**Gone only with the policy for all code:**
- 2.1: there is no plain "outside" left to protect;
- REPL's own invalidations.

**Not changed by where the policy lives:** these are rules of the design:
- 1.2: folding by Julia's asserted effects;
- 1.3: types as values;
- 1.4 and 1.8: what counts as a fact;
- 2.2: where compiled code for (key owner, function owner) pairs is stored, which only an environment-level cache would make automatic.

**A design option for 1.5:** at a run-time site, take plain inference's result type and check it at run time, instead of widening to `Any`:
- in trait code a failed check raises an error ("identical or error");
- under the policy for all code, an error after a load is not acceptable, so a failed check needs a dynamic fallback branch (deoptimization), which costs code size.

Whether results of abstract calls typed `Any` cost too much when all code compiles by facts is the open question for the "all code" setting.

**A prototype path without rebuilding Julia:** 1.13's `Compiler.activate!(codegen = true)` replaces the native compiler with a loaded `Compiler` package for all new compilation, so (A) can be developed as a fork of that package. Base's system image stays as built until the setting is real.
