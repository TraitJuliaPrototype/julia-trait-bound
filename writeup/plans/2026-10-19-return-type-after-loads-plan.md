# Run-time `return_type` after loads: a plan (proposal, 2026-10-19)

The user's standing rules apply: principled fixes over workarounds, as close as possible to established designs; Julia patches over hacks; "identical or error"; slowdowns that traits recover are acceptable. This plan implements nothing. It reads the code and the step-0 logs (`experiments/factscompiler/step0/`) and says what to do, in which order, and how to prove that answers stay identical.

## 1. The problem, precisely

### 1.1 The cost and where it goes

The work is `CSV.read(csv, DataFrame); describe(df); sort(df, c); combine(groupby(df, last), c => sum)` on upstream CSV.jl and DataFrames, everything compiled by facts (the `all` setting, the facts system image). First run 768 ms, repeated 0.8 ms. After `using` OffsetArrays, StatsBase, Unitful, IntervalArithmetic, Distributions, Interpolations, StaticArrays, CairoMakie and REPL: **982 ms**, of which the runtime counts 994 ms of compilation and 683 ms of "recompile" (`logs/afterloads.log`). Plain Julia pays 4,044 ms for the same.

The profile (`logs/afterloads-prof-all.log`, flat, about 1,950 samples at 0.5 ms) splits the 982 ms in two, and both halves are consistent with the compile trace (`logs/afterloads-all.trace`):

| Where | Samples | Share | What it is |
|---|---|---|---|
| `describe` → `_describe` (abstractdataframe.jl:741) → `map` → `collect(::Generator{DataFrameColumns{DataFrame}, closure})` (array.jl:815) → `Compiler.return_type` → `_return_type(::PlainRTInterp)` → `typeinf_type` → `typeinf_ext` | 673–675 | 35 % (≈ 340 ms) | **one run-time query**, `return_type(_iterator_upper_bound, Tuple{Generator{DataFrameColumns{DataFrame}, var"#_describe##12"{…}}})`, whose answer is `Dict{Symbol, Any}` (`logs/rtanswers-noopt0.txt`); plain inference re-infers the closure at `AbstractVector`, `get_stats(::AbstractVector, ::Vector{Symbol})`, `quantile!(::AbstractVector, …)`, `isapprox(::Integer, ::Integer)` and everything the loads touched below them |
| `CSV._parseprepared` → `jl_compile_method_internal_owner` → `typeinf_ext_toplevel(mi, world, …, owner)` (typeinfer.jl:1658) | 740 | 38 % (≈ 370 ms) | the **recompile of `CSV._parse`** (core.jl:3711–3985; the trace: `precompile(Tuple{typeof(CSV._parse), …}) # recompile`, 683 ms inclusive); 713 of the 740 samples are `typeinf_ext(::PlainRTInterp)`: the compile-time route, `return_type_tfunc` → `facts_plain_return_type` (tfuncs.jl:3184, facts.jl:329–356), for the comprehensions and the `Symbol.(header)` broadcast in `_parse` (about ten sites, e.g. core.jl `[k for k in 1:nchall if !indexed[k]]`, `[d.parsetype !== nothing for d in plan.columns]`); the facts inference of `_parse` itself is the remainder, about 27 samples |
| the same `_parseprepared` subtree, below `jl_compile_codeinst_now` (jitlayers.cpp:681) | ≈ 530 of 592 | 27 % (≈ 265 ms) | **LLVM codegen of `_parse`**, a very large method |
| `typeinf_ext(::PlainRTInterp)` in total | 1,386 | 71 % (≈ 695 ms) | plain inference for `return_type`, both routes; `optimize(::PlainRTInterp)` is 700 of them (half), `semi_concrete_eval_call` 71 |

So the ≈ 990 ms are **≈ 700 ms of plain inference for `return_type`** (the brief's diagnosis), plus **≈ 280 ms that are not `return_type` at all**: the facts inference and LLVM codegen of `CSV._parse`, which is recompiled because SparseArrays' `vcat` for Base's `Number`/`Vector` (loaded by StatsBase) wins at a fact signature inside it, a stakeholder's change under the design's rules (open-issues §1.19; `design/performance.md` theme 4). The two are entangled only in that the recompile re-runs the compile-time route for `_parse`'s sites; had `_parse` kept its code, the same ten sites would have re-run plain inference at run time when reached, since their cached answers are stale either way.

Concrete evaluation inside plain inference does not compile callees natively in a measurable amount here: no `_call_in_world_total` or `concrete_eval_call` frame reaches the profile's 60-sample cutoff.

### 1.2 The two routes and the one cache

Under the facts mode, `return_type` has two routes into plain inference, and one cache:

- **Compile time** (tfuncs.jl:3124–3200, facts.jl:211–356). `return_type_tfunc` first infers the query by facts; an answer that cannot be wider than plain inference's (a constant, a concrete type, `Union{}`) is folded as plain Julia folds it. Otherwise `facts_plain_return_type` splits the signature into at most four concrete signatures (`concrete_splits`), runs plain inference on each in `PlainRTInterp` (`typeinf_ext_toplevel(PlainRTInterp(world), mi, SOURCE_MODE_NOT_REQUIRED)`, facts.jl:343), and folds the merged answer only if every edge of every answer is at a fact signature (`rests_on_facts`, facts.jl:293–326), with a `PlainRTInfo` edge from the facts code to the plain answer (facts.jl:232–241). Else the site compiles to a run-time call (`UNKNOWN`).
- **Run time** (typeinfer.jl:1782–1819). `Compiler.return_type(f, t)` calls `_return_type(return_type_interp(world), tt)` in the typeinf world; `return_type_interp` is `PlainRTInterp(world)` under facts (facts.jl:247); `_return_type` merges `typeinf_type` over the matches; `typeinf_type` is `typeinf_ext(interp, mi, SOURCE_MODE_NOT_REQUIRED)` (typeinfer.jl:1441–1445).
- **The cache.** Both routes use the cache owner `:facts_plain_return_type` (facts.jl:230; the lookup is `code_cache(interp)` → `jl_rettype_inferred(owner, mi, world, world)`, types.jl:507–511, cicache.jl:70–76). No code is ever generated from it. Its CodeInstances carry the inferred IR unless the result is a constant (`finish!`, typeinfer.jl:123–147; `jl_finalize_precompile_inferred` leaves foreign owners' IR alone, staticdata_utils.c:135). The session holds 32,124 such answers, 8,266 of them constants, 1,642 `Any`, 167 top-level `@default_eltype` queries (`rtanswers-noopt0.txt`); most come from the system image.

### 1.3 What the loads do to the cache

The nine loads invalidate 1,616 valid CodeInstances in all modules: 1,107 of owner `nothing` (773 of the compiler's own, by REPL's `REPLInterpreter` methods, and Base code the compiler uses) and **509 of owner `:facts_plain_return_type`**. The compiler's own are free: it runs in its frozen world (REPL alone invalidates 562 and the work takes 2 ms, `logs/afterloads-variants.log`). The 509 are the cost.

They are invalidated by the runtime's eager, transitive walk: a new method is activated (`jl_method_table_activate`, gf.c:3082–3260), each existing specialization whose signature intersects it is checked with `is_replacing` (gf.c:2426), and its backedges are invalidated (`invalidate_code_instance` sets `max_world` and recurses through `_invalidate_backedges`, gf.c:2290–2395); a site that recorded a method-table edge (a signature with all its matches) is invalidated through `_typename_invalidate_backedges` (gf.c:2616–2665). The precision is per edge, by signature intersection and specificity, not by whether the answer would change.

The winning methods (`afterloads.log`): Unitful's `Colon(::Any, ::Any, ::Quantity)` 733 entries, DelaunayTriangulation's `==(::CatmullRomSpline, ::CatmullRomSpline)` 418, FilePathsBase's `write(::FileBuffer, ::String)` 338, IntervalArithmetic's `promote_rule(::Type{T}, ::Type{ExactReal{S}})` 210, GeometryBasics' `convert(::Type{IT}, ::OffsetInteger)` 164, and 61 more. The tree for Unitful alone (`logs/invtree-unitful-all.log`, histogram by `invalidate_code_instance`'s depth) has a telling shape: `Colon(::Any, ::Any, ::Quantity)` has **10 roots at depth 0** (method-table edges), a chain of 1–10 nodes per level up to depth 34, and **more than 600 of its 733 nodes at depth 35–57**. The `describe` chain is explicit at lines 1–40: Unitful's `rtoldefault(::Type{<:AbstractQuantity})` intersects the edge `rtoldefault(::Type{Union{}})` (a `Type{Union{}}` edge, a known class of spurious intersections), and the invalidation climbs `rtoldefault(::Integer, ::Integer, ::Int64)` → `isapprox(::Integer, ::Integer)` → `_quantile` → `quantile!(::AbstractVector, ::Float64)` → `get_stats(::AbstractVector, ::Vector{Symbol})` → the `_describe` closure → `iterate(::Generator{…})` → `_iterator_upper_bound(::Generator{…})`, ten levels, although `get_stats` returns `Dict{Symbol, Any}` by construction and `isapprox` returns `Bool` whatever `rtoldefault` does.

### 1.4 What the ≈ 700 ms buy: the guarantee and the semantics

**The guarantee.** "Identical or error" (design.md §4; `implementation.md` §5, G1) has one exception: values Julia decides by inference. The facts mode closes that exception for `return_type`: under facts, a run-time `return_type` is answered by plain inference in its own cache owner, so `map(f, Real[])` is `Vector{Float64}` as in plain Julia (decisions.md, the `PlainRTInterp` row; `alternatives.md`:215 records that the earlier Compiler copy gave `Vector{Any}`). The property bought is: **in the same world, the facts mode's answer is plain Julia's answer.** After a load changes plain inference's premises, plain Julia recomputes its answers; so does the facts mode. The ≈ 700 ms are that recomputation.

**The semantics.** `return_type` is explicitly unspecified. Base's own docstring (promotion.jl:519–529): "the type `R` obtained from `promote_op` is merely an upper bound … the exact type `R` … depends on various factors … should not be relied upon". Upstream's position in the threads (sources below): inference is part of the implementation, not the language, and its results may change between versions. Yet the answer is observable, through four Base mechanisms:

- `collect(::Generator)` and `_collect` (array.jl:820–858): `et = @default_eltype(itr)` (array.jl:808–818: `promote_typejoin_union(_return_type(_iterator_upper_bound, Tuple{typeof(itr)}))`) is the element type of an **empty** result and the **starting type of widening** for a non-empty one (`collect_to!`, array.jl:876–893, widens by `promote_typejoin` only when an element is not `isa` the current type). So `et = Any` gives `Vector{Any}`, `et = Float64` gives `Vector{Float64}`; `eltype(map(f, xs))` depends on it.
- broadcasting: `combine_eltypes` is `promote_typejoin_union(_return_type(f, argT))` (broadcast.jl:755).
- `promote_op` (promotion.jl:617–621), used by `reducedim` destinations (reducedim.jl:1151, 1224) and LinearAlgebra.
- `Iterators.approx_iter_type` (iterators.jl:1547–1559) for `flatten`.

The design promises identity to plain Julia in the current world, not stability of the answer across worlds: plain Julia's own answer moves when a load changes what inference can see, and that movement is exactly what invalidation tracks. Any approach below must keep: **for every query, the facts mode's answer in world `w` equals plain Julia's answer in world `w`.**

## 2. Candidate approaches

Each with mechanism, precedent, what it would save (from the logs), risk to "identical", effort, and the files it touches. A is the recommendation; the letters are used in §3.

### A. Revalidate stale answers instead of re-inferring them (red-green)

**Mechanism.** Keep the runtime's eager invalidation as it is. When a query (either route) misses the cache because the answer CI for `mi` is stale (`max_world < world`), do not re-infer at once. Walk the stale CI's edges (`ci.edges`, the same list `rests_on_facts` walks) and decide, bottom-up:

1. *Edge check* (the leaf test). For each edge, re-run the method lookup at its signature in the current world and compare with the recorded matches: exactly what the compiler already does when a package image is loaded (`verify_call`, reinfer.jl:469: "verify that these edges intersect with the same methods as before"; `verify_method`, reinfer.jl:162, walks the callee graph with Tarjan's algorithm and computes a world range). An edge whose match set changed makes the holder **red**. A method-table edge (`Core.MethodTable` or `Int` count) is checked the same way.
2. *Result comparison* (the firewall; rustc's addition to edge checking). A red node is re-inferred in the current world. Its new result is compared with its stale CI: `rettype`, `exctype`, `rettype_const`, `ipo_effects`, `analysis_results`, and the inferred IR (both decompressed; byte-equal compressed strings are a fast path; any doubt is "different"). If equal, the node's parents are not red on its account: they see the same callee.
3. *Clone forward.* A node that is not red (all edges verified, all red callees equal) gets a new CodeInstance with the stale one's result, IR and edges, `min_world` = the current world, `max_world` = ∞, registered as the stale one was: `engine_reserve` (types.jl:429), `jl_fill_codeinst` and `jl_update_codeinst` as `finishinfer!`/`finish!` call them (typeinfer.jl:684–700, 148–152), `store_backedges` (typeinfer.jl:776), `cache_result!` (typeinfer.jl:189). No code, so nothing else to clone.

Why the comparison must include the IR and the effects: a parent's inference consumed its callee's IR through inlining and semi-concrete evaluation (`semi_concrete_eval_call` reads the callee's CodeInstance from the cache and runs `IRInterpretationState` on it, abstractinterpretation.jl:1283–1300) and its effects through concrete evaluation (`is_foldable`, abstractinterpretation.jl:971); the reverted `may_optimize = false` experiment showed that the optimizer's refinement of effects and IR changes answers (`noopt-built.log`: CairoMakie's `Vector{Tuple{Any, Point2f}}`). Const-propagated callee frames are not cached globally, so their contribution is already folded into the parent's own result and edges; a parent whose const-prop path changed is red by its edges.

**Precedent.** rustc's incremental compilation ("red-green": a query is re-executed only if an input changed, and a re-executed query whose result hash is unchanged keeps its dependents green); Salsa's early cutoff (rust-analyzer); "Build systems à la carte" (Mokhov, Mitchell, Peyton Jones 2018) names it early cutoff; Bazel's change pruning. In Julia itself: package-image loading already revalidates CodeInstances by their edges instead of re-inferring them (`reinfer.jl`: `insert_backedges`, `verify_method_graph`; images mark CIs with `WORLD_AGE_REVALIDATION_SENTINEL`, reinfer.jl:10), so step 1 is the in-session use of an existing mechanism; step 2 is new.

**What it saves.** The upper bound is the ≈ 700 ms of plain inference; what remains is the re-inference of red nodes up to the first node whose result is unchanged. The `describe` chain firewalls at `isapprox` (`Bool`) or at the latest at `get_stats`/`get_stats!` (`Dict{Symbol, Any}`, `const nothing`), so almost all of its ≈ 340 ms go. The Unitful tree's shape (10 roots, a thin chain, 600 nodes above depth 35) says the same for the rest, since a red chain stops at the first predicate, mutator or container-typed function. The compile-time route benefits equally, because `facts_plain_return_type` reaches the same cache through `typeinf_ext`. The honest estimate before measuring: **400–600 ms of the 700**. The floor after A is the `_parse` codegen (≈ 280 ms, approach G) plus the leaves.

**Risk to "identical".** None by construction *if* the comparison is complete, which is the whole risk: a missed input (a field of the CodeInstance a parent's inference read) would make a green parent differ from fresh plain inference. Mitigations: a self-check mode that re-infers anyway and asserts equality with the clone (§3, RT-5); treating any unknown field as "different"; starting with the answer owner only (no code depends on these CIs, so a bug cannot miscompile anything, only mis-type a `collect`).

**Effort.** Measurement prototype one day; implementation one to two weeks including the self-check mode and tests. Compiler only.

**Files.** `Compiler/src/typeinfer.jl` (`typeinf_ext`:1373 and `typeinf_edge`:1051, the cache-miss hook, for `PlainRTInterp` only), a new `Compiler/src/revalidate.jl` (the walk, the comparison, the clone) reusing `reinfer.jl`'s `verify_call`/`verify_invokesig`, `Compiler/src/facts.jl` (`PlainRTInterp`), possibly `src/gf.c` for a `jl_rettype_inferred`-like lookup that returns the latest *stale* CI of an owner (the `mi.cache` chain walk `afterloads_noopt.jl` does in Julia).

### B. Fewer run-time queries: fold more answers at compile time, provably

**Mechanism.** `return_type_tfunc` under facts folds a constant, a concrete type or `Union{}` from facts inference, and plain inference's answer when it rests on facts (facts.jl:211–216). Two more cases are provable:

- **`Any` is a fixpoint under non-stakeholder loads.** A load that is neither a stakeholder's change nor a winning pirate can only add matches at abstract sites or push a site over `max_methods`; both widen. An answer that is already `Any` cannot widen. In strict mode, where winning pirates are refused, folding `Any` without an edge is sound; by default it is "measured". But `Any` answers are the cheap ones to recompute and not the ones in the profile (the `describe` answer is `Dict{Symbol, Any}`). Small gain.
- **The split answer equals the facts answer.** When facts inference's own answer at the split is a non-concrete type and plain inference's answer is the same type, folding still needs plain's edges to be right, so this is not sound without an edge. Rejected.

**Precedent.** Monotone dataflow fixpoints. **Saves** little here (1,642 of 32,124 cached answers are `Any`, and none of the costly ones). **Risk:** strict-mode only. **Effort:** a day. **Files:** `Compiler/src/tfuncs.jl`:3170–3200, `facts.jl`. Keep as a footnote to A.

### C. Cache plain answers across sessions (images)

**C0, the first run.** Package images already keep foreign-owner CodeInstances: `queue_external_cis` (staticdata_utils.c) keeps any inferred CI of an image module's method that has a backedge path to the package's own methods (`has_backedge_to_worklist`), with no owner test, and piece 5 keeps native code the workload compiled (`jl_image_keep_compiled`). A run-time query's *root* (`_iterator_upper_bound(::Generator{…})`, `iterate(::Generator{…})`: Base methods with no caller edge) has no such path and is dropped, so every session re-infers the top two or three levels at its first `describe`. Keeping roots that a run-time `return_type` created during the workload (the answer-cache twin of piece 5) would shave the first run. It does not touch the after-load cost. Effort one to two days; `src/staticdata_utils.c` (`queue_external_cis`), a flag like piece 5's.

**C1, an environment cache.** The after-load answers depend on the whole set of loaded packages, so only a cache keyed by the environment (Manifest hash plus the loaded set) can hold them across sessions: answers computed once with everything loaded, saved, and on the next session verified by edges (reinfer.jl's `verify_method_graph`, which exists for exactly this) instead of re-inferred. Precedent: .NET's ReadyToRun "version bubbles" (code precompiled across assemblies is valid only for the set compiled together; the facts rule is the stakeholder version of that), PackageCompiler sysimages, Rust's final-crate monomorphization. Julia has no serialization of CodeInstances outside images, so this is weeks of work in `src/staticdata.c` and `base/loading.jl`, and helps only sessions that repeat the same environment. After A, and only if the measured residue warrants it.

### D. Narrower plain edges

Plain inference's edges are its own; narrowing them changes which loads change the answer, hence the answer. **Rejected as a change.** What remains is *edge hygiene*, upstream work that the facts mode inherits: the `Type{Union{}}` intersections of the `describe` chain (`rtoldefault(::Type{Union{}})`, `eps(::Type{Union{}})`, invtree lines 37 and 55) are spurious in the sense that no caller passes `Union{}`; and the over-broad winning signatures (`Colon(::Any, ::Any, ::Quantity)`, `vcat(::Union{Number, AbstractVecOrMat{<:Number}}, …)`) are the kind the 2020–2021 invalidation campaign (SnoopCompile's `@snoop_invalidations`) narrowed in Base and packages. **Measure** how many of the 509 come through `Type{Union{}}` edges (from the full invalidation log, which `afterloads.jl` already collects); if many, that is an upstream issue report with our logs attached. No change in our tree.

### E. A cheaper optimizer for the answer cache, without changing answers

Half of plain inference's time is `optimize(::PlainRTInterp)` (700 of 1,386 samples; `ssa_inlining_pass!` ≈ 400 of them, `compact!` ≈ 200). The optimizer cannot be skipped (`noopt-built.log`): its passes feed `ipo_dataflow_analysis!` (optimize.jl:1005) and the IR that parents inline and interpret. Passes that are only for codegen (`cfg_simplify!` is the candidate) could be dropped for a cache no code is generated from, but inlining heuristics in the parent read the callee's statement count, so even a cosmetic change can move an answer. **Expectation low; measure only with the differential test (§3) in place; a day; `Compiler/src/optimize.jl`:1062 `run_passes_ipo_safe` gated on the interpreter.** After A, the optimizer runs only for red nodes, which makes E mostly moot.

### F. Move the query out of hot library code: declare the element type (the traits route)

**Mechanism.** Every one of the costly sites is `collect` over a generator, or a broadcast, whose element type the library knows and does not say. In the trait form the type is declared and no inference is asked: TraitTables' `describe` is `ColSummary[summarize(…)::ColSummary for k in …]` (TableCore.jl:169), a typed comprehension that never calls `@default_eltype`; TraitWorld's certificate already names such sites in trait code ("a result decided by inference (`return_type`): declare the type", certificate.jl:60). The same pattern is available to plain libraries: `Symbol[…]` instead of `[…]`, `map!` into a typed vector, `Dict{Symbol, Any}[…]` in `_describe`. This is what "traits recover it" means here, and it is why TraitReport's work after the loads is 41 ms (none, REPL) while form (a′) pays 237–3,086 ms (`TraitReport/README.md`:112).

**Precedent.** Rust and Swift have no `return_type`: a collection's element type is written or is the monomorphized type; Julia's own guidance is the `promote_op` docstring's "avoid it".

**Saves.** For the trait forms, all of the ≈ 700 ms (already measured). For the control (upstream CSV + DataFrames) nothing by definition: the control is the test bed for plain code, and its cost is the design's stated price. For the *forks* of CSV and DataFrames, every untyped comprehension in `_parse` and `_describe` is a one-line change that removes a run-time query and is also an upstream-acceptable PR (it is what Base recommends).

**Risk.** A declared type that is narrower than plain's inferred `et` changes the value of plain Julia's program (the forks are then not identical to upstream at that line); so declare the type plain inference gives today, or the element type the library documents. **Effort:** a day in the forks; an afternoon to add a certificate check to TraitCSV/TraitTables' tests that no run-time `return_type` site remains in their trait modules. **Files:** `forks/CSV/src/core.jl` (`_parse`), `forks/DataFrames/src/abstractdataframe/abstractdataframe.jl` (`_describe`), TraitCSV/TraitTables tests.

### G. The other 280 ms: `CSV._parse` is recompiled because a standard library wins

Not a `return_type` cost. StatsBase loads SparseArrays, whose `vcat(::Union{Number, AbstractVecOrMat{<:Number}}, Vararg{…})` (sparsevector.jl:1275 in the plain log; `_cat` with 11 entries in the `all` log) wins at a fact signature inside `_parse`; the facts mode follows it (rule P) because the standard libraries are Julia, one owner (open-issues §1.19; `TraitWorld/src/ownership.jl`). The recompile of the whole of `_parse` (inference ≈ 15 ms, codegen ≈ 265 ms, plus the ten sites' plain inference at compile time) is what it costs. Options, none of them in this plan's scope:

- Upstream: these SparseArrays methods are a recognized invalidation source in stock Julia too (72 entries in our plain log); narrowing them or dispatching `cat` through a style trait is the principled fix. An issue with our log is cheap.
- Design: standard libraries as owners of their own types only (§1.19) would make this a pirate; in strict mode `using StatsBase` would then be refused, which is unacceptable; by default it changes nothing. So the design's choice stands and the cost is real.
- Mitigation: the LLVM half is the size of `_parse`; nothing principled shrinks it short of splitting the method, which is CSV's business (and what TraitCSV does).

### H. Re-infer in the background after `using`

Julia 1.12+ can run inference concurrently (the engine's reservations; `engine_reserve`/`engine_reject`). A session could re-run stale queries on a worker thread right after a load, hiding latency in interactive use. Precedent: HotSpot's background compilation, V8's concurrent recompilation. It changes no answer (the same inference, earlier) but saves nothing in scripts, and it would re-infer answers nobody asks for. After A, and only for the REPL.

### Rejected

- **Freezing answers** (never invalidating the answer cache): answers become a function of load history, which plain Julia's are not; breaks identity after loads. The design's §7 forbids it.
- **`may_optimize(::PlainRTInterp) = false`**: tried, widens answers (`noopt-built.log`).
- **`@max_methods 1` on the libraries' modules**: changes plain Julia's answers for that library (a source change, acceptable only in the forks, and then it is F in disguise with a bigger blast radius).
- **A guarded fold** (fold the facts answer, check plain's at run time): computing plain's answer is the cost.

### What upstream has said about `return_type` at run time

- The in-tree docstring (promotion.jl:519–600) is the authoritative statement: `promote_op` is fragile, its result an upper bound that depends on inference, to be avoided except for empty containers, and it spells out two "invalid use-cases".
- The Discourse record: `Core.Compiler.return_type` is internal; a docstring PR and an RFC for a public API guarantee were made and the guarantee was not given (the thread cites PRs #36834 and #44340; numbers as quoted there, to verify); inference "is part of the implementation, not the language"; users rely on it for performance anyway. `eltype` of a generator deliberately returns `Any` because an inference-dependent `eltype` "can't be predicted or relied on from one version of Julia to the next". `map(f, T[])` giving `Any[]` on an empty input is traced to `@default_eltype` in the type-unstable-`map` thread.
- Sources: [Sniffing the return type](https://discourse.julialang.org/t/sniffing-the-return-type/83666?page=2), [Obtaining a function's output type](https://discourse.julialang.org/t/obtaining-a-functions-output-type/11313), [`eltype` could be smarter](https://discourse.julialang.org/t/eltype-could-be-smarter/80485.md), [Type-unstable application of `map`](https://discourse.julialang.org/t/type-unstable-application-of-map/102771), [Inferring return type of a method](https://discourse.julialang.org/t/inferring-return-type-of-a-method/29698.md).
- Consequence for us: there is no upstream semantics to conform to beyond "whatever plain inference says now"; the facts mode's promise of identity is stronger than anything upstream promises, which is why A (keep plain's answers, recompute less) is the right shape and B/D (change what is computed) are not.

## 3. Recommended order, acceptance checks first

**Step 0: the differential test (write first; two days).** Proves "identical" for every step after it, and would have caught the `may_optimize` regression before a system-image build.

- RT-1, *the corpus*: every run-time `return_type` query made by the control's work, the four demonstrators' suites, TraitWorld's examples and CairoMakie's precompile workload, logged by a hook on `Compiler.return_type` (typeinfer.jl:1782) under `all`; plus the 167 `_iterator_upper_bound` queries of `rtanswers-noopt0.txt`. A few thousand `(f, Tuple)` pairs, stored as text in `experiments/factscompiler/step0/corpus/`.
- RT-2, *the oracle*: the stock 1.13.2 binary answers each query with `Core.Compiler.return_type(tt)`, in a fresh process, (a) with CSV and DataFrames loaded, (b) after the nine loads in the control's order. Both answer sets are saved.
- RT-3, *the subject*: the facts image answers the same corpus the same two ways; pass = every answer `===` the oracle's, before and after the loads. Also the patched binary in plain mode (to separate the inliner changes from the facts mode).
- RT-4, *folds*: for each site folded at compile time under `all` (a facts CodeInstance with `PlainRTInfo` edges, facts.jl:232), the folded constant equals the run-time answer in the same world; walk the facts CIs of the control's work.
- RT-5, *self-check for A*: a mode (`JULIA_FACTS_RT_CHECK=1`) in which a green clone is also re-inferred and the two compared; the whole corpus, the demonstrators and the quick BaseBenchmarks subset run under it, zero differences.
- Numbers to keep: the control's after-load time by its three parts (§1.1), `work after the loads`, and `lost by owner`.

**Step 1: measure A's ceiling (one day).** In `typeinf_ext` for `PlainRTInterp`, before re-inferring `mi`, read the latest stale answer CI from `mi.cache`; after inference, compare (rettype, exct, const, effects, IR) and log equal/different with the node's depth in the invalidation tree (from the log `afterloads.jl` already collects). Run the control. Output: the fraction of re-inferred nodes whose result is unchanged, and the samples that would be saved. If under half, stop and reconsider C1/F only.

**Step 2: implement A (one to two weeks).** The edge check first (reusing `reinfer.jl`), then the comparison and the clone, then the self-check mode; `PlainRTInterp` only. Acceptance: RT-1–RT-5 green, acceptance 21/21, the demonstrators, the quick BaseBenchmarks subset unchanged (it never hits this path), and the control's after-load time.

**Step 3: F in the forks and the trait libraries (two days).** Typed comprehensions where upstream's are untyped and the type is documented; a certificate check in TraitCSV/TraitTables that no run-time `return_type` site remains in trait modules. RT-3 run on the forks' queries. This is independent of step 2 and can run while the build for step 2 is pending.

**Step 4: G, a decision, not code.** Record in open-issues §1.19 the measured price (≈ 280 ms of a recompiled `_parse`), file the upstream issue on SparseArrays' `vcat` with the two logs, and leave the ownership rule.

**Step 5: later.** C0 (roots in package images; first-run only), B's `Any` fold (strict mode), E (measure once, under RT-3), H (REPL only), C1 (only if sessions repeat environments and the residue after A matters). D's measurement (how many of the 509 are `Type{Union{}}` edges) can be done from the existing log at any time and may become an upstream issue.

## 4. Where each piece lives

| Piece | Compiler (julia-1.13) | Base / runtime | TraitWorld / libraries |
|---|---|---|---|
| A, revalidation | `typeinfer.jl` hooks; new `revalidate.jl` reusing `reinfer.jl`; `facts.jl` | possibly a stale-CI lookup in `src/gf.c` | — |
| RT-1–RT-5 | a logging hook on `return_type` behind a flag | — | the corpus, oracle and runner scripts in `experiments/factscompiler/step0/`; the certificate check |
| B, `Any` fold | `tfuncs.jl`, `facts.jl` (strict mode only) | — | — |
| C0 | — | `src/staticdata_utils.c` `queue_external_cis` | — |
| C1 | — | `src/staticdata.c`, `base/loading.jl` (weeks) | — |
| D, edge hygiene | — | upstream issues with our logs | — |
| E | `optimize.jl` gated on `PlainRTInterp` | — | — |
| F | — | upstream PRs: typed comprehensions in CSV and DataFrames | the forks' `_parse` and `_describe`; TraitCSV/TraitTables tests |
| G | — | upstream issue on SparseArrays' `vcat`; §1.19 stays | TraitCSV's split parser already avoids one giant method |
| H | the engine (`engine_reserve`) on a worker thread | — | the REPL hook |

**Why this order.** The differential test is the precondition for touching anything that answers `return_type`; step 1 costs a day and decides whether A is worth two weeks; A is compiler-only, changes no answer by construction, and attacks the ≈ 700 ms directly; F costs nothing in the compiler and is what the design says anyway; G is a decision already made whose price is now known; the rest is cheap only once A has removed the bulk.
