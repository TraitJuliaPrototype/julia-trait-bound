# The changes to Julia, as built

A chapter of [The implementation in detail](implementation.md): what the patched Julia (`julia-1.13/`, branch `trait-world-1.13`, on v1.13.2) adds, as of 2026-10-19. For core developers. [`implementation.md` §6](implementation.md#6-what-julia-provides) states what the design needs from Julia; this chapter gives the changes by principle, with what is planned and optional, then the inventory of what is built, with commits and upstream status. Where they disagree, `implementation.md` wins. The pieces are numbered 1–17 as in [`../explorations/julia-support.md`](../explorations/julia-support.md), which predates parts (A)–(D); pieces no longer part of the design are in [`alternatives.md`](alternatives.md#the-invalidation-filter-and-other-julia-pieces-reverted-or-moot).

Size: 40 commits on v1.13.2 (with build scripts and the dispatch profiler), 36 files, about 1,750 lines added. The largest file is `Compiler/src/facts.jl` (469 lines), which holds the facts mode's rules.

## The changes by principle

The changes follow four mechanisms. Mechanisms 1 and 2 are the facts compiler. Mechanisms 3 and 4 are general improvements that the facts mode made necessary. Around them are hooks the library needs, fixes useful without traits, and one planned last step: traits in the type system.

Status words:
- **Built:** in the patched Julia today (the sections after this one list the commits).
- **Planned:** decided, not built.
- **Optional:** built only if a measurement or a demonstrator asks for it.
- **Open:** not decided.

| Mechanism | Built | Planned | Optional or open |
|---|---|---|---|
| 1. Infer across a call only where a fact holds | Part (A) | Revalidating cached `return_type` answers after loads | Guarded devirtualization (optional); standard libraries as owners of their own (open) |
| 2. Each method is compiled in its own mode, whoever calls it | Parts (B), (C); calls and inlining between the modes; edges and images for the second owner | One rule in one function; an owner of its own for the test bed | The facts owner's normalization memo (optional); facts code behind `jl_apply` (open) |
| 3. Caches at dynamic boundaries are checked against the caller's world | Caller-world `cfunction`s; exact-type and wildcard entries in the per-site cache | Entries with an open `max_world` | `Dynamic` beyond four implementations; a codegen-emitted cache (both optional) |
| 4. Primitives for a specialized path beside a general one | `known_type`; `dynamic_call`, part (D) | — | — |
| Hooks for the library | Definition hooks, field-offset intrinsics, type printers | Pieces 1′, 14, 15 for strict mode | — |
| Fixes useful without traits | Two inliner changes; the run-time `return_type` entry; reflection in the compiler's world; the dispatch profiler | Upstream proposals (§4) | — |
| Traits in the type system | — | Pieces 7 and 8, last | — |

### Mechanism 1: infer across a call only where a fact holds

**The principle.** A call is inferred, with an edge, only at a signature that only its stakeholders or a pirate can change: a *fact*. Every other call is a run-time site, dispatched when it runs. Code inferred this way is invalidated only by stakeholders and pirates ([`../design.md`](../design.md), the argument).

- **Built: part (A)** (§1).
  - `is_fact_sig`: a dispatch tuple; its union splits, up to four; unions of concrete elements in tuple arguments; a closure's call at kinds; a concrete `Vararg` tail.
  - `return_type` folds only an answer that cannot be wider than plain inference's.
  - No asserted effect applies to a frame with a run-time site (G1.10).
- **Planned: revalidate cached `return_type` answers after loads.** A differential test against stock Julia first, then red-green revalidation of the cached answers instead of inferring again ([`../plans/2026-10-19-return-type-after-loads-plan.md`](../plans/2026-10-19-return-type-after-loads-plan.md)).
- **Optional: guarded devirtualization at run-time sites** (step 2 of the speed plan). Postponed: only if untyped code under `all` still matters after the other items.
- **Open: standard libraries as owners of their own** ([`../open-issues.md`](../open-issues.md) §1.19). Today they count as Julia's own code, so a load of SparseArrays that wins a call inside CSV is a stakeholder's change.

### Mechanism 2: each method is compiled in its own mode, whoever calls it

**The principle.** A method's mode (facts or plain) and its cache owner follow from the method alone, never from its caller. Code of both modes lives side by side, with its own caches, edges and images. A call from one mode into the other crosses explicitly.

- **Built:**
  - **The modes** (part B): the module option `facts=true`; `Method.facts` marks a boundary (compiled in the caller's mode) or always-facts code.
  - **Dispatch** (part C): run-time sites in facts code run the callee's facts code (`jl_apply_generic_facts`, `jl_invoke_facts`).
  - **Calls between the modes:** `leaves_to`. The compiler's own code is never compiled by facts (module flag 2), also in the compile queue that builds images (`interp_for_mi`).
  - **Inlining between the modes:** piece 10, and inlining from the other owner's cache (c7f1eae1c0).
  - **Edges and images for the second owner:** piece 9; piece 5; facts copies kept without source (9892bfc288).
  - `--trim` turns the facts mode off.
- **Planned: one rule in one function.** Which mode and owner a method's code gets is decided in five places today, with two predicates for "compiler code": the single-request entry, `interp_for_owner`, `leaves_to`, the runtime's `jl_method_is_plain`, `interp_for_mi`. One function, "the mode and owner of a MethodInstance's code", replaces them. A queue that missed the rule compiled the compiler by facts under `all`: the CSV+DataFrames work took 666 ms, about 505 ms with the rule applied.
- **Planned: an owner of its own for the test bed.** Under `all`, plain results and results compiled by facts share the default owner's cache. A Base method called by the compiler can reuse a result compiled by facts: correct, but slower.
- **Optional: a memo for the facts owner's per-call normalization.** A call that arrives with a narrow MethodInstance normalizes again on every call. No measured workload reaches it.
- **Open: facts code behind `jl_apply`.** Dispatch through the runtime's `jl_apply` (splats of unknown length, `jl_call`, `@cfunction`, finalizers, task entry) runs plain code.

### Mechanism 3: caches at dynamic boundaries are checked against the caller's world

**The principle.** Every cache that skips a dispatch at run time holds world ranges and is checked against the caller's world, as Julia's method cache already is. A cache never decides which method runs; it only remembers what dispatch decided, for the worlds where that holds.

- **Built:**
  - the `cfunction` calling convention `:caller_world` (piece 18), for `Callable`'s `DynamicCall`;
  - exact-type entries in the per-call-site dispatch cache, for calls whose cache entry is not a leaf signature (a9d3dcb345);
  - wildcard entries for cache entries with only concrete or `Any` parameters (333bc61b01).
- **Planned: entries with an open `max_world`.** Today a cached entry is capped at the latest world when it is made, so every cached site misses once after any method definition. The entry would refer to the typemap entry and the CodeInstance, whose `max_world` invalidation lowers. The same applies to the `cfunction` thunk.
- **Optional:**
  - **`Dynamic` beyond four implementations:** raise the split limit for `dynamic_call` only, or a per-site table of types and caller-world pointers. When a demonstrator has five implementations.
  - **A codegen-emitted cache with direct calls:** only if profiles show lookup, not the call or the callee, dominating. The realistic gain is 3–8 ns per call.
- **Not planned:** a hook by which a package substitutes the target of a call (for untyped trait calls). It would buy a few nanoseconds against today's table.

### Mechanism 4: primitives for a specialized path beside a general one

**The principle.** Library code can write two paths that compute the same result, and the compiler picks one from what inference knows. The choice changes speed, never the result.

- **Built:**
  - `Compiler.known_type(x)`: folds to whether inference knows `x`'s concrete type, `false` where it does not fold (GCC's `__builtin_constant_p`, for types). TraitWorld's entries take the inlined path for typed callers and the table of declared implementations for untyped ones.
  - `Compiler.dynamic_call` (part D): a call site split over a trait's registered implementations, with a fallback, and no edge to the registry.

### Hooks for the library

- **Built:** method-definition and image-activation hooks (piece 1, strict mode); field-offset intrinsics (piece 3, trait objects); a registry of type printers (piece 17).
- **Planned, for strict mode's intended design:** a deletion hook (1′); a read-only "what would this definition invalidate" query (14); image validation that reports the winning method (15).

### Fixes useful without traits

- **Built:**
  - an invoke keeps the exact specialization over a widened varargs tail;
  - an inference cycle's members inline each other;
  - the run-time `return_type` entry compiled into the system image;
  - reflection runs the native compiler in the compiler's world for an explicit `NativeInterpreter`;
  - the dispatch profiler (`JULIA_FACTS_DISPATCH_PROFILE=1`): dynamic calls per callee and per call site, with a reset to profile one region.
- **Planned:** propose them upstream (§4), the inliner changes after broader measurement in plain Julia.

### Last: traits in the type system

- **Planned, last: piece 7, then syntax (piece 8)** ([`../explorations/julia-support.md`](../explorations/julia-support.md)):
  - membership as subtyping, by declaration after the type is defined (`T <: ColTable`, `x isa ColTable`);
  - a trait bound as a dispatch tier above `Any` and below every type;
  - entries and workers generated by the compiler.

  It removes the encodings TraitWorld needs today: entry methods at `Any`, tags for trait sets, sentinel methods, `conforms`. It changes the type system, so it comes last, once the demonstrators' numbers support the proposal.

## 1. The facts compiler: parts (A)–(D)

| Part | What | Main files | Commits |
|---|---|---|---|
| **(A)** a facts mode of the native interpreter | `NativeInterpreter` has `facts::Bool` and `owner`. Under facts, a call is inferred, with its edges, only at a fact signature (`is_fact_sig`: a dispatch tuple, its union splits, unions of concrete elements in tuple arguments up to four, a closure's call at kinds, a concrete `Vararg` tail). Any other call is a run-time site (`FACTS_ABSTRACT_SITE`). `return_type` folds only an answer that cannot be wider than plain inference's, else plain inference's answer when it rests on facts, else at run time (`PlainRTInterp`, its own cache owner). No asserted effect applies to a frame with a run-time site (`InferenceState.facts_rtsite`). | `Compiler/src/facts.jl`, `abstractinterpretation.jl`, `typeinfer.jl`, `tfuncs.jl`, `inferencestate.jl` | 880ae49dad, feaad9e45c, 67f5c0bcc8 |
| **(B)** code compiled by facts beside plain code | A module option `Base.Experimental.@compiler_options facts=true` (inherited by submodules) makes a module's methods *facts methods*, compiled by facts under the cache owner `:facts` whoever calls them. `Method.facts`: 0 as the module says, 1 a boundary (`Expr(:meta, :facts, 0)`: compiled in the caller's mode), 2 always (`Expr(:meta, :facts, 1)`). Lowering carries the meta into every method a definition lowers to (keyword sorter, positional forwarders), also when merged with `@inline`'s meta. A plain caller of a facts method gets a separate facts inference (`facts_edge`) and names that CodeInstance. Reflection of a facts method is facts inference. Package images keep `:facts` code. | `facts.jl`, `typeinfer.jl`, `src/method.c`, `src/module.c`, `src/ast.scm`, `src/julia-syntax.scm`, `src/staticdata*.c`, `base/experimental.jl` | c3415abde6, 25c630dd34 |
| **(C)** dispatch from facts code | Code of owner `:facts` calls `jl_apply_generic_facts` and `jl_invoke_facts` at run-time sites: the same method lookup, then the callee's facts code, compiled on a miss. This covers the calls codegen emits (direct calls, `invoke`, `_apply_iterate` with known tuples, `invokelatest`). Dispatch that goes through the runtime's `jl_apply` (splats of unknown length, `jl_call`, `@cfunction`, finalizers, task entry) runs plain code (`../reviews/2026-10-19-compiler-implementation.md` §2.4). | `src/gf.c`, `src/codegen.cpp` | c3415abde6 |
| **(D)** the `Dynamic` call-site split | `Compiler.dynamic_call(K, RT, f, x, args...)`: inferred as `f` at the union of `K`'s registered candidates (at most four, each split a fact, `register_dynamic_candidate!`, no edge), plus a fallback. The inliner union-splits it with the dynamic call last, never "fully covered" (`DynamicSplitInfo`); it asserts the fallback, and any case not known to be an `RT`; the join is typed `RT`. A later implementation reaches the fallback and invalidates nothing. | `facts.jl`, `ssair/inlining.jl`, `stmtinfo.jl` | f6838f96fc, 67f5c0bcc8, bc26aa9255 |

**The switch.** `JULIA_COMPILE_BY_FACTS=1`, or a system image built with it (`experiments/factscompiler/scripts/build_facts_sysimage.sh`), compiles all code by facts under owner `nothing`: the test bed. Without it, only facts methods are compiled by facts: the product setting. `--trim` turns the facts mode off: a trimmed image writes no facts flags (`jl_method_is_facts` is false under trim).

## 2. The inliner, and how the compiler's own code is compiled

| Change | Why | Applies to | Commit |
|---|---|---|---|
| An invoke keeps the exact specialization inference made at concrete argument types when the compileable signature only widens a varargs tail (`only_vararg_widened`) | Without it, the widened specialization (`…, Vararg{Any}`) is inferred again at `Any` and boxes every argument: 72 MB per raytrace; a plain recursion through a varargs wrapper takes 21.9 ms on stock 1.13.2 and 0.36 ms with the change. Julia's other widenings (types and functions passed to arguments that do not specialize on them) stay. Broader forms are not safe ([`alternatives.md`](alternatives.md#the-inliner-changes-a-facts-only-form-then-a-narrower-general-form)). | all code | da4726c5cc, 61852d8fb1 |
| An inference cycle's members are optimized callees first, each offered to the inliner of the members after it (`InliningState.cycle_results`) | Julia does not otherwise inline one member of a cycle into another, so a recursion through wrappers makes one call per wrapper per turn (rtopen 542 ms without the change, 384 ms with it) | all code | 4102b7a7a7, 61852d8fb1 |
| The Compiler module is *never by facts* (module flag 2, inherited by submodules); `leaves_to(interp, method)` leaves a facts method to facts inference and a compiler method to plain inference; facts dispatch runs plain code for compiler methods (`jl_method_is_plain`) | Otherwise a facts caller of `Compiler.typeinf_frame` compiles the abstract interpreter by facts, and TraitWorld's checks run 6× slower. Boundary: direct calls into compiler functions from facts code hold plain edges (`implementation.md` §6). Under the facts image, also every compile queue (`interp_for_mi`; the image builder's queue had compiled part of the compiler by facts: CSV+DataFrames work under `all` 666 → about 505 ms) | facts code | c4f7e76a2f, f13117cd74 |
| Base reflection runs the native compiler in the compiler's world also for an explicit `NativeInterpreter`; `leaves_to` leaves to facts only from the plain owner | Otherwise, with an explicit interpreter, the compiler runs at the latest world, on code later definitions invalidate: 3.7 s per forwarding implementation after big loads | all code | bb82a82bbf |
| `return_type_tfunc`'s facts signature is boxed | The facts addition captured type values in the tfunc's closure, so the closure was compiled again for every query (about 70 ms each) | all code (a fix of our own bug) | e4db37bb48 |
| `_return_type(::NativeInterpreter, ::DataType)` compiled into the image (a compiler bootstrap entry) | Without it the run-time `return_type` entry has no code in the system image: 75–93 ms at its first call in every session, stock 1.13.2 too | all code | 40512f64c2 |
| The inliner inlines the code of a method that belongs to the other owner (`leaves_to`) from that owner's cache: both `resolve_todo(mi, …)` | A plain caller of a facts method found nothing in its own cache and emitted an `invoke`, never inlined, which also blocked hoisting out of loops: a typed trait call 2.6 ns, 0.8 ns with the change (plain 0.8). Inlining does not re-infer: the inlined code stays the other owner's, with an edge to its CodeInstance only | all code | c7f1eae1c0 |
| `Compiler.known_type(x)`: folded to whether inference knows `x`'s concrete type, `false` where not folded (GCC's `__builtin_constant_p`, for types) | TraitWorld's entry takes the folded path for typed callers and the table of declared implementations where the type is not known (`implementation.md` §4.6); plain Julia cannot express the switch | code that branches on it between paths computing the same result | b5bb9ab881 |
| The per-call-site dispatch cache gets an entry for the exact argument types when the method cache's entry is not a leaf signature (`call_cache_exact`, `gf.c`), valid up to the latest world at insertion | Such calls (a `@nospecialize` method, guard signatures, `Any` in the signature) did the full method-cache lookup on every call: `push!(d, pop!(d))` on a `Vector{Any}` under `all`, 61.7 → 12.9 ns, profile all lookup with the change off; the quick BaseBenchmarks subset under `all`, geomean 0.93, containers of `Any` 0.60. Acceptance G1.22 (`../plans/2026-10-19-inline-caches-plan.md`) | all code | a9d3dcb345 |
| With keep-compiled (piece 5), a package image keeps code compiled by facts whose inferred source was discarded (`staticdata_utils.c`); the compile queue infers it again by facts | The facts copies of Base code that TraitWorld's machinery reaches through run-time sites (no backedges) were in no image, so every session compiled them: the first `@implement` of a session inferred 188 ms, 17 ms with the change (TraitWorld also switches piece 5 on while its own image is built) | images built with keep-compiled | 9892bfc288 |

## 3. The supporting pieces

Numbering of [`../explorations/julia-support.md`](../explorations/julia-support.md).

| Piece | What | Used by | Commit |
|---|---|---|---|
| 1 | Method-definition hooks: before and after a definition (may refuse), and for a package image's methods before activation (may leave some inactive) | strict mode (`TraitWorld/src/hooks.jl`) | dda21fe511 |
| 3 | Field-offset intrinsics `getfield_at_offset`, `setfield_at_offset`, with Julia's alias metadata and the write barrier | trait objects reading the user's object (`TraitWorld/src/core.jl`) | 3133c31c5f |
| 5 | Package images keep machine code for upstream and foreign CodeInstances their precompilation compiled | trait code compiled into a package's image | 9af2f27786 |
| 9 | Owner-aware bare MethodInstance edges | invalidation of a second owner's code | 5b5b98758f |
| 10 | The inliner inlines exactly the foreign CodeInstance named by `:invoke` | (B) | f72f7368f0 |
| 17 | A registry of type printers, `Base.Experimental.register_type_printer` | printing by bound and key (`ColTable at Vector{Vector{Float64}}`) | db82407fa6 |
| 18 | The `cfunction` calling convention `:caller_world`: the pointer's call runs in the caller's world, through a world-checked call-site cache in its thunk (one entry per target, with the worlds where the dispatch and the CodeInstance hold; `jl_get_specialization1_worlds`). A plain `@cfunction` keeps the latest world | `Callable`'s `DynamicCall` (`TraitWorld/src/core.jl`) | 80e8bf79c5 |

**Not in the build:** pieces 2 and 4, reverted in c4f7e76a2f (`Compiler/src/reinfer.jl` is upstream's; [`alternatives.md`](alternatives.md#the-invalidation-filter-and-other-julia-pieces-reverted-or-moot)).

**Wanted for strict mode's intended design, not built:** 1′ (a deletion hook), 14 (a read-only "what would this definition invalidate" query), 15 (image validation reports the winning method). See `../explorations/strict-mode.md`.

## 4. Upstream status

- **Ready as they are** (general fixes, small):
  - 40512f64c2 (the run-time `return_type` entry in the image);
  - bb82a82bbf (reflection in the compiler's world for an explicit `NativeInterpreter`; upstream has no `owner` field, so there it is one line);
  - pieces 10, 9 and 17.
- **After broader measurement in plain Julia:** the two inliner changes of §2 (exact specializations over a widened varargs tail; cycle members inlining each other). The system image grows 0.4% with both.
- **General improvements of 2026-10-19, to measure in plain Julia and propose:**
  - exact-type entries in the per-call-site dispatch cache (a9d3dcb345), which speeds up dynamic calls to `@nospecialize` methods in any code;
  - the `cfunction` calling convention `:caller_world` (piece 18);
  - `known_type` (b5bb9ab881).

  The cross-owner inlining (c7f1eae1c0) and keeping facts copies in images (9892bfc288) matter only with a second cache owner, so they go with the proposals for (B) and (C).
- **Proposals:**
  - (A) as "a facts mode for the native compiler", with the benchmark table (`implementation.md` §3.3);
  - pieces 1, 1′, 14, 15 with strict mode;
  - (B) and (C) as per-method inference modes;
  - traits in the type system (piece 7) last.
- **Not for upstream:** the facts-only parts of §2 (the Compiler's never-by-facts flag, `leaves_to`).

## 5. Tests

- **Acceptance:** `experiments/facts/acceptance_compiler.jl`, 23 checks:
  - G1, identical or error;
  - G2, stable caches;
  - the cases found by the reviews, G1.15–G1.19;
  - `DynamicCall` in older and alternating worlds, G1.20 and G1.21;
  - a call site cached for exact types through a redefinition, G1.22;
  - a site cached for every type at an `Any` position, then a more specific method, G1.23.

  23/23 on the current build, plain and under `all`.
- **TraitWorld's suite** (48 test sets, with the untyped calls' table) and the demonstrators' suites, on every build; the examples, including the check of code compiled ahead (`experiments/examples/ahead/`).
- **Missing** (review of 2026-10-19): targeted checks for the inliner changes (a varargs wrapper in a recursion; cycle inlining) and for the compiler-plain edges; Base's test suite under the facts mode (started once, not completed).

## 6. Building

- `julia-1.13/tw-build.sh`: a cold build of the patched 1.13.2, niced, `-j4`, with a memory watchdog; check `BUILD EXIT 0` at the end of `tw-build.log` (a Julia-level error during the system image build ends with a nonzero exit, not a crash message).
- The facts system image: `experiments/factscompiler/scripts/build_facts_sysimage.sh` (about 5 minutes), rebuilt after every change to Base or the compiler; used with its own depot first and `~/.julia` second (`JULIA_DEPOT_PATH=<dir>:$HOME/.julia:`: a trailing colon alone adds only the bundled depots).
- Every package image is rebuilt after a build: the first runs include precompilation.
