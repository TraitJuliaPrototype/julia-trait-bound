# Review: world-checked inline caches, and the order of the remaining work (2026-10-19)

Reviewed: `writeup/plans/2026-10-19-inline-caches-plan.md` and `writeup/plans/2026-10-19-remaining-performance-work.md`, against `design.md`, `design/implementation.md` §4.5–4.6, the speed plan, today's session notes, and the code: `julia-1.13/src/gf.c` (`jl_lookup_generic_`, `jl_apply_generic_facts`, `_jl_invoke_owner`, `jl_compile_method_internal_owner`), `src/codegen.cpp` (`emit_abi_call`), `src/runtime_ccall.cpp` (`jl_get_abi_converter_caller_world`), `Compiler/src/facts.jl`, `TraitWorld/src/untyped.jl`, `ahead.jl`, `trait_module.jl`; the benchmark definitions in BaseBenchmarks and BenchmarkTools; `experiments/factscompiler/step0/logs/quick.log`.

No Julia was run (the machine is shared). Statements marked **verified** were checked against the sources named; statements marked **reasoning** are inferences from those sources and from the session's own measurements, and should be measured before anything is built on them.

Findings are ranked by how much they damage the plan's thesis.

## 1. The plan's diagnosis of the tails is unsupported, and the quick log contradicts it

The plan's premise: a run-time site costs a dynamic call (15–20 ns) where a static call costs 1 ns, so a cache that turns the lookup into a compare and a direct call recovers most of the tails. The quick log says otherwise.

**Verified**, from `quick.log` and the BaseBenchmarks sources:

- `collection/queries & updates/("Vector", "Any", "pop!", "unspecified")` is `push!(d, pop!(d))` on a `Vector{Any}` of 1,000 elements (`CollectionBenchmarks.jl:193`). It pops the last element and pushes it back: **one run-time site** (`push!` with an `Any` argument), **one argument type every time**. Plain 3 ns (`push!` inlined at the abstract signature), `all` 276 ns. A monomorphic dynamic call that the design measures at 15–20 ns costs about 270 ns here.
- The method that site dispatches to is `push!(a::Vector{Any}, @nospecialize x)` (`base/array.jl:1354`). Its specialization for the run-time type, `(Vector{Any}, Int)`, is not its compileable instance, `(Vector{Any}, Any)`. Section 2 shows what the facts runtime does per call in that case.
- The other `Vector{Any}` tails (the two `loop` initializations at 126× and 81×, `filter` and `filter!` at 63× and 85×) write their elements through the same method or through `setindex!(A::Array{Any}, @nospecialize(x), i::Int)` (`base/essentials.jl:978`): the same case. The per-element costs agree: about 100–170 µs for 1,000 pushes (`quick.log`), 100–170 ns per `push!`.
- `anys` holds only `Int` and `String` (`CollectionBenchmarks.jl:17`), so every "container of `Any`" site is monomorphic or bimorphic: Julia's existing 4-way per-site cache (`call_cache`, `gf.c:4409`) should hit at all of them. The tails are **not** the polymorphic-miss case the inline cache targets.
- `collection/iteration/("Dict", "Any", "iterate")`: 7 → 115 ns. One run-time site; I could not identify its target by reading (`Pair`'s constructor has no `@nospecialize` slot). To profile.

So the largest tails are not "a dynamic call at 15–20 ns where plain inlines": they run a path in the facts runtime that costs 100–270 ns per call (section 2, verified as a path; the magnitude is reasoning until measured), and no one has profiled them. The plan estimates "15–20 ns down to 3–6 ns" from the step-1 thunk's numbers, which were measured on a different path (concrete arguments, plain code). Until one tail is profiled (`perf record` on the `pop!` benchmark under `all`, attributing cycles to `jl_lookup_generic_`, `_jl_invoke_owner`, `jl_compile_method_internal_owner`, `jl_normalize_to_compilable_mi`, the jlcall wrapper, allocation, and the callee), nothing can be said about what a cache buys. Two consequences:

- Stage 1 may show a large gain for the wrong reason. A per-site cache that holds the CodeInstance's entry point bypasses `_jl_invoke_owner` and everything behind it; if the 270 ns are there (section 2 names one such path), the cache hides a defect, the plan records the gain as its own, and the defect stays for every path the cache does not cover (`invoke`, `cfunction`, `invokelatest`).
- Or stage 1 shows nothing, if the cost is in the callee, and the plan concludes that the lookup is cheap.

The right first experiment is the profile, then the one-line checks: a site with 1, 4 and 16 types in *plain* Julia (what the existing cache costs when it hits and when it misses), and the same from facts code. The plan's stage 0 lists the micro-benchmarks but not the profile, and stage 1 is proposed as the measurement.

## 2. A verified per-call slow path in the facts runtime, which a cache would hide

**Verified** (`gf.c`, `jl_compile_method_internal_owner`, lines 3719–3731):

```c
    jl_method_instance_t *mi2 = jl_normalize_to_compilable_mi(mi);
    if (mi2 != mi) {
        jl_code_instance_t *codeinst2 = jl_compile_method_internal_owner(mi2, world, owner);
        if (owner != jl_nothing)
            return codeinst2; // code compiled by facts: the wider instance's code serves
        jl_code_instance_t *codeinst = jl_get_method_inferred(mi, ...);   // plain: a forwarding CI cached on mi
```

For the plain owner, a forwarding CodeInstance is cached on `mi`, so the next call's `jl_method_compiled_callptr_owner(mi, …)` (`gf.c:3497`) hits: plain Julia pays the normalization once per site and type. For the facts owner, nothing is cached on `mi`. Every dynamic call from facts code (`jl_apply_generic_facts` → `_jl_invoke_owner`, `gf.c:4341`) whose target's compileable instance differs from its specialization therefore runs, per call: the walk of `mi->cache` (miss), `jl_normalize_to_compilable_mi` (`jl_compilation_sig`, `jl_apply_tuple_type` with hash-consing, `jl_isa_compileable_sig`, possibly `jl_type_intersection_env`, then `jl_specializations_get_linfo` under the method's lock; `gf.c:4034`), and the walk of `mi2->cache`. This is the case for every target with a `@nospecialize` slot, a `Function` or `Type` slot that is only passed through, or a widened `Vararg` tail: a large part of Base, including the `Vector{Any}` methods that section 1's tails dispatch to. It matches the session's "dispatch to a `@nospecialize` method from facts code costs about 30 ns more" (measured on a small signature; the cost grows with the signature's normalization work). The fix is a few lines (cache a forwarding CodeInstance with the facts owner on `mi`, as the plain branch does), and it belongs before any cache, because stage 1 would mask exactly this path.

What is verified is the chain: the benchmark's site dispatches to a `@nospecialize` method, and the facts runtime runs this path on every such call. That the path accounts for the 270 ns is reasoning; the profile of section 1 settles it. If the profile shows something else as well (a facts CodeInstance that `jl_method_compiled_callptr_owner` does not find on each call, so that `jl_type_infer_owner` runs per call and returns the cached result; or cost inside the facts-compiled callee), the same rule applies: fix the runtime path, then measure, then decide about a cache.

## 3. The unification is two-thirds real

**Problems 1 and 2 share a mechanism.** Both are `jl_apply_generic_facts` sites keyed by the run-time types of the open arguments; both want a type compare and a call in the caller's world. Problem 2 adds what problem 1 lacks: the other arguments' types and the result type (the `Dynamic` split's `RT`, asserted at the fallback, `facts.jl:367`) are known at the site, so a direct specsig call with an unboxed result is possible.

**Problem 1 gets less than the plan says.** At a run-time site the arguments' types are not known (that is what makes it a run-time site) and the result is `Any` (`FACTS_ABSTRACT_SITE`, `facts.jl`). So "a direct call with the argument types known at the site" and "a result that is not boxed when the site knows its type" do not apply there. What the cache can call is the callee's jlcall wrapper with boxed arguments and a boxed result, which the session measured at **12 ns** through the `:caller_world` thunk ("the pointer call with boxed arguments (12 ns, against 4.5 for concrete ones)"). Against 15–20 ns for the dynamic call today, the realistic gain at problem 1's sites is 3–8 ns per call, not 15–20 down to 3–6, and it does nothing for the 100–270 ns of section 1 unless those are in the lookup.

**Problem 3 is a different problem.** At an untyped call `f(x)`, dispatch finds the entry method at `Any`. The plan's cache entry calls something else: the method specialized on the builder, with the builder as environment, chosen by TraitWorld's resolver (`_umiss`, `_pmiss` in `untyped.jl`). The plan says so: "TraitWorld provides the miss handler for its entries". That is not a cache of dispatch results; it is a per-method hook in the runtime by which a package substitutes the target of a call for a type, with a world range it computes itself. Three consequences:

- "Identical by construction" does not cover it. A hit for problem 3 computes what the entry would have computed only if TraitWorld's resolver is correct (its ranges come from `conformance`'s dispatch, `_umiss`); that needs acceptance checks of its own (an implementation redefined, a family member, a generic implementation, an `@implement` after the site was used, an older world through `invoke_in_world`), none of which exist today for the (c) path.
- The "environment word" is not a new ABI. It is Julia's function object: `_UCall{G,B}` holds the builder and is the cfunction's first argument (`untyped.jl`, `_ufptr`). An entry's target is a `(function object, code)` pair, which ordinary methods satisfy with a singleton. The plan should say this, because it means stage 3's gain over today's (c) is only the inline compare in place of `_plookup` (about 5 ns) and one fewer thunk layer (`_UWrap` → `_UCall` → the tagged method): a few nanoseconds on a 29 ns call, against 14 ns for an entry compiled ahead and 15–17 ns for plain Julia.
- Upstream would have to accept a pluggable miss handler in `jl_apply_generic`. Nothing in Julia resembles it; stages 1–2 are "general Julia improvements" only if stage 3 is dropped from the mechanism.

So the honest statement is: one cache mechanism for the two run-time-site problems, with problem 3 served by the same mechanism only if the runtime grows a custom-dispatch hook, which is a design decision, not an instance of the general mechanism.

## 4. "No edges" costs more than Julia's own cache design, and "the world check is new" is wrong

**Verified**: Julia's `call_cache` entries are checked against `[min_world, max_world]` at every hit (`gf.c:4475`), and their `max_world` is open (`~0`) until a method definition that intersects the entry lowers it (`invalidate_mt_cache`, `gf.c:2696`). So an entry survives every unrelated world bump. The same holds for the CodeInstance found by `jl_method_compiled_callptr_owner`.

The plan's rule (and step 1's thunk, **verified** in `jl_get_abi_converter_caller_world`: `hi = max_valid < latest ? max_valid : latest`) caps every entry at the latest world at the time of the lookup. After any method definition anywhere in the session, the next call at every cached site in the new world misses, takes `cfun_lock`, runs `jl_matching_methods` (`jl_get_specialization1_worlds`, microseconds for functions with many methods) and `jl_type_infer`, and extends the range. This is sound (invalidation only ever affects worlds after the definition, so a capped range stays valid), and it is not a cliff. But it is a per-bump cost per site that Julia's own cache does not pay, and in programs that define methods while running (`eval`-based code generation, RuntimeGeneratedFunctions, Symbolics, the REPL in a loop) it is paid at every bump at every hot site. The plan presents "no edges" as a virtue; here it conflates inference edges (which decide compiled code's validity, and which the facts rule refuses) with dispatch-cache maintenance (which Julia's runtime does for its typemap cache and which the facts rule does not forbid, or `call_cache` would be a violation).

The sound and simpler form: an entry holds the typemap entry (as `call_cache` does) and the CodeInstance, both with open `max_world` maintained by Julia; a hit compares the world against both ranges (two compares, as now). No per-bump miss, no new invalidation code, and still "in the caller's world". That applies to the step-1 thunk as well.

Also: "What is new is the world check" is not right. Julia's cache checks worlds; the stock cfunction thunk checks the world counter. What is new is keying by the caller's world rather than the latest, and the per-site placement in code.

## 5. The semantics claim, point by point

- **A hit calls what dispatch would call in that world.** Sound for problems 1 and 2 by the argument above (range = intersection of the match's range and the CodeInstance's range, capped; invalidation only shortens future worlds). **Reasoning**, not tested beyond G1.20/G1.21 for the thunk. For problem 3, see section 3.
- **Threads.** The step-1 thunk's readers are lock-free (acquire load of the entry, monotonic loads of the range; ranges only grow, so a torn read sees less), writers under `cfun_lock` (global). The Julia-side tables (`UTable`, `PTable`) publish copy-on-write under `_LOCK` with the session word stored after the entries. Plausible; untested, as `evidence.md` says of threads generally. A codegen-emitted cache with in-place entry updates would need the same discipline; the plan should state that entries are immutable once published.
- **GC rooting.** The thunk holds raw `jl_code_instance_t*` in malloc'd entries, rooted "by their MethodInstances' caches" (comment in `runtime_ccall.cpp`). That holds as long as CodeInstances are never removed from `mi->cache` and the MethodInstance stays in `m->specializations`; it is an assumption of the kind a GC reviewer will ask about. The plan lists it under stage 5; it is a stage-1 requirement.
- **Megamorphic transition.** "A site that sees many types becomes megamorphic, which is today's cost" is true only if the transition is to the global cache with the per-site entries still replaced (as Self and V8 do). A sticky megamorphic state with the per-site entries frozen would be worse than today for a site cycling through N+1 types, since today's `call_cache` replaces randomly. State it as "never worse than today" and design the replacement policy.
- **Images.** A codegen-emitted cache is a fresh global in the image's object code, so no session identity is needed, unlike (c)'s Julia-level tables. Harmless, but the sentence "they carry a session identity … as (c)'s tables are" describes the wrong mechanism.
- **"Identical or error" through `return_type`-decided values** is unaffected.

## 6. Precedents

- Self (Hölzle, Chambers, Ungar, ECOOP 1991), Smalltalk-80 (Deutsch and Schiffman, POPL 1984): correct. Note that the reported speedups in that line of work came largely from type feedback feeding inlining (Hölzle and Ungar 1994), which §5 of the plan excludes. The PIC alone bought a modest fraction.
- V8 and JavaScriptCore: correct on states. V8's megamorphic state is a global hashed stub cache keyed by (map, name); Julia's `call_cache` is already that design, so Julia's dynamic dispatch is V8's *megamorphic* path today. The plan's gain is the monomorphic and polymorphic states on top.
- HotSpot: its compiled inline caches have no polymorphic state (clean, monomorphic, megamorphic through vtable/itable stubs); polymorphism is handled by C2's profile-guided bimorphic inlining with guards. "Monomorphic, polymorphic, megamorphic, as in V8 and HotSpot" is wrong for HotSpot.
- Swift: witness tables are per (type, protocol), with a fixed layout, no cache and no miss handler; every existential call is an indirect call, which `comparison.md` elsewhere counts among Swift's cliffs. The analogy covers the environment word only, and loosely: Swift shares code per protocol, the plan per key.
- Missing precedent: CPython's specializing adaptive interpreter (PEP 659, 3.11) is the closest to "a per-site cache checked against a version at every execution, no deoptimization, respecialize after a backoff". It also shows why version tags are per type (`tp_version_tag`), not one global counter: a global counter deoptimizes everything on every change, which is section 4's cost under Julia's world counter.
- Missing precedent at home: Julia's `call_cache` and the cfunction thunk, which the plan mentions in passing; the proposal is best framed upstream as "make the existing per-site cache associative and inline", not as a new mechanism.

## 7. The order of the remaining work

**Item 1 before items 2–4 is the wrong order under the user's rules.**

- Item 1's problem 1 (the BaseBenchmarks tails under `all`) is the case the user's rule covers: untyped plain code, which traits recover. Step 2 was postponed today for exactly that reason, and the remaining-work list now reintroduces the same target as item 1 ("the answer to step 2's goal"). The same argument postpones it.
- Item 1's problems 2 and 3 are nanosecond gains on paths already within 2× of plain Julia: the `Dynamic` fallback beyond four implementations (no demonstrator has five), and untyped trait calls at 29 ns against 15–17 (entries compiled ahead already give 14).
- Items 2 and 3 are measured costs every session pays: 77–97 ms per clean `@implement`, about 1 s after large loads. Item 4 is the measurement round without which no number in the documents can change.
- Stage 2 of item 1 is a codegen change "of the size of step 1 or larger", with the open questions of sections 4 and 5.

Recommended order: (i) the profile of one tail and the owner-path fix (section 2), a day, because they decide whether a cache is worth anything; (ii) item 4, the measurement round, since the documents' numbers depend on it and the machine must be quiet anyway; (iii) items 2 and 3; (iv) item 1's stage 1 **as a change to `call_cache`** (associativity, size, a per-site miss counter under `JL_GF_PROFILE`), measured on the quick subset; (v) stage 2 only if (iv) shows that lookup, not the ABI or the callee, is where the time goes; (vi) stage 3 (problem 3) only as a separate decision about a custom-dispatch hook, with its own acceptance checks.

**Missing or misfiled:**

- The TraitMakie image flake is a correctness item ("identical" broken once) filed under "smaller items". It ranks above every performance item.
- Acceptance checks for today's (c) path and for `_umiss`'s world ranges (section 3), and for the compiler-plain edges, held views and the inliner changes (`implementation.md` §9.3 item 3) are absent from the list.
- The facts-owner caching defect of section 2.
- Threads: the caches add lock-free readers to a design whose evidence page lists threads as untested.
- The `const DynamicFn` pointer folded into package images is listed; it is a potential crash, not a "smaller item".
- Item 5's "`Callable` with abstract argument types … about 30 ns" is section 2's defect, not something item 1 "may subsume".

## 8. Simpler alternatives for most of the gain

- **Problem 1:** fix section 2; then try `N_CALL_CACHE` and the number of ways (`options.h:13`, `gf.c:4456`), which is a two-line experiment, before any new structure. Accept the rest: the plan's own §5 concedes the cache cannot inline, and plain Julia's advantage on these benchmarks is inlining at abstract signatures (3 ns for `push!`), which no cache reaches.
- **Problem 2:** two options that need no codegen. Raise `MAX_FACT_SPLITS` for `dynamic_call` only (the candidates are registered without edges, so a longer split costs code size, not validity); or put today's (c) machinery at the fallback: a per-site table of `(type, :caller_world pointer)`, about 5 ns lookup plus 4.5 ns call with concrete arguments, against about 20 ns now. Either serves 5–16 types at roughly half today's cost, with step 1's mechanism and no new runtime concept.
- **Problem 3:** keep (c) and compile entries ahead (14 ns); do not build a custom-dispatch hook for 10 ns on a path the design already calls "type-unstable code was never claimed fast".

## 9. Smaller points

- `remaining-performance-work.md` says the ~990 ms are "about 700 ms of plain `return_type` inference … and about 280 ms of `CSV._parse` compiled again"; the step-0 diagnosis attributes 700 of ~1,950 profile samples to the optimizer inside `typeinf_ext`, which is a share of the inference, not a separate 700 ms. State the split with its provenance.
- The plan's "What it lacks: for the facts mode, the same fast path at all" is not accurate as written: `jl_apply_generic_facts` uses the same `jl_lookup_generic_` and `call_cache`; what differs is the owner-aware invoke path of section 2.
- The quick subset's geometric mean (1.967) is over a selection of tails and controls; it must not be quoted as the facts mode's cost.
- "Threads. Entries are appended copy-on-write" is true of the Julia-side tables and not of the step-1 thunk, whose entries are extended in place (monotonically).

## Summary

The plan's mechanism is sound for the two run-time-site problems and its semantics argument holds there, but the plan builds on an undiagnosed cost. The quick log shows a monomorphic run-time site at 270 ns against the 15–20 ns the plan assumes; that site dispatches to a `@nospecialize` method, for which the facts runtime has a verified per-call slow path that a cache would hide; and the realistic gain at the facts mode's sites is a few nanoseconds per call once the boxed ABI is counted. The third problem is not an instance of the mechanism but a custom-dispatch hook. The ordering puts a speculative nanosecond gain ahead of measured millisecond and second costs. Profile first, fix the owner path, measure the existing cache, and keep item 1's codegen stage behind items 2–4.
