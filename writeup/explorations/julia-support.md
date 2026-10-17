# What TraitWorld needs from Julia, and in which order

Exploration of 2026-10-16 (session 23), for the user's question: "There are a number of things that need patches to Julia to cleanly resolve. Mostly a hook that runs on method definition, right? Look what else we need from Julia to support TraitWorld and suggest an order in which to implement things in Julia proper."

**Short answer.** A hook at method definition is the largest single piece, but not the only one. Seven pieces are needed, plus syntax:
- two hooks that every check and filter hangs on: method definition, including a package image's methods, and invalidation;
- three performance pieces;
- two semantic pieces: the dispatch check at dynamic sites, and traits in the type system and dispatch.

Everything else stays in a package: definition checking, keep detection, concrete mode, `verify_main`, `Dynamic` and the entries.

> **Superseded order (session 25, 2026-10-17).** The order below was written for trait wrappers and sealing. With wrapping by facts adopted and validated, and strict mode kept as an option (`strict-mode.md`), the list is reviewed in the next section. The old text is kept for the record.

## Review for wrapping by facts and strict mode (session 25)

The user: "Finally review the proposed Julia work and go ahead in any order you like. Make the decisions that need to be made."

**What changed.**
- Under wrapping by facts, the trait world's correctness rests on Julia's own invalidation at concrete signatures (rule P). Nothing is skipped, nothing is refused at load, and no dynamic call needs a view check unless strict mode is on.
- So the pieces that served sealing and the filter drop out.
- The weight moves to making an `AbstractInterpreter` with its own cache owner a first-class citizen of the runtime. GPUCompiler, Enzyme and Cassette-like tools need the same pieces.

**Each piece, judged again:**

| # | Piece | Verdict | Why |
|---|---|---|---|
| 1 | Method-definition hook | **keep** | Strict mode (`strict-mode.md`: defining a winning pirate is an error) refuses through it, at the prompt and for an image's methods at load. It also gives exact attribution to the loading package, late-override refusal, and keep flags that follow definitions. Not needed for the core's correctness. |
| 2 | Invalidation policy hook | **drop** from the upstream list | Rule P: nothing is skipped. Strict mode installs its traps through Julia's exact invalidation, so it does not need the hook either. It stays in the patched build, opt-in (`JULIA_TW_FILTER=1`), until TraitWorld's filter is removed. |
| 3 | Field-offset intrinsics | **keep**, independent | Performance of trait fields. Unaffected by the facts design. |
| 4 | Post-inference hook | **drop** | It audited *native* trait-world code for pirates. Under the policy, trait code is compiled by TraitWorld's own interpreter, which is the compile-time hook, and the piracy audit is off on the policy's path. |
| 5 | Native code for upstream and foreign CodeInstances in images | **keep: the deep piece** | Without it every session compiles the policy's code (stock Julia: first solve 0.44 s instead of 50 ms). |
| 6 | Dispatch check at dynamic sites | **drop as a Julia piece** | Strict mode acts at method definition (`strict-mode.md`), not at calls. |
| 7, 8 | Traits in the type system, syntax | **keep, last** | Unchanged. The definition-time checks in the compiler, part of 7, are also the full cure for new trait code after big loads. |
| 9 | Owner-aware bare MethodInstance edges | **keep, upstream soon** | It is a bug for every foreign owner. Done in the patched build. |
| 10 | The inliner uses the CodeInstance it is given | **keep, upstream first** | A stale-code hole for any `invoke(f, ci, …)` of a foreign CodeInstance from native code. Small. Fixing it lets TraitWorld drop the call-site `@noinline` (about 5 ns per typed call). |
| 11 | Compile a call under owner X from inference | **keep; form changed** | 1.13 already *declares* the API: `Core.OptimizedGenerics.CompilerPlugins.typeinf(owner, mi, mode)`, which "the optimizer has license to" replace by `typeinf_edge(owner, mi, parent_frame, world, mode)` at compile time. The compiler never makes that replacement. Implementing that half *is* piece 11: the entry calls `typeinf`, inference resolves it with the caller's frame and world validation, and the generator and its purity problem (A4) go away. |
| 12 | A frozen world for an external interpreter's compiler | **keep** | About 0.5 s once per session after big loads, otherwise. |
| 14 | **New:** a read-only "which CodeInstances would this definition invalidate" query | **add**, small | The exact check for strict mode, asked from piece 1's hook before the method becomes visible. It is `jl_method_table_insert`'s invalidation walk without the stores, and useful to tooling too. |
| 13 | **New:** instrumentation of foreign CodeInstances | **add**, small | `needs_instrumentation` (`Compiler/src/reinfer.jl`) skips foreign owners, so coverage and allocation tracking miss trait code under the policy. |
| — | **Not needed:** trimming of foreign CodeInstances | **decided** | A `--trim` build compiles the plain call with native inference in the closed world. That is plain Julia, so G1 holds, and nothing loads later, so there is no G2 to protect (`aot-under-facts.md`). `runtime.md`'s concern about foreign instances in trimmed builds no longer applies. |

**The new order, and why:**
1. **Piece 10,** the inliner bug. It is a few lines and a clear bug, so it is the easiest first contribution.
2. **Piece 9,** owner-aware bare edges. It is small, a bug for any foreign owner, and already written.
3. **Piece 11,** through the `CompilerPlugins` hook Julia already declares. It is medium-sized, all in `Compiler/src`, and removes assumption A4 and the generator's re-entry guard.
4. **Piece 12,** the frozen compiler world. It is small to medium.
5. **Piece 5,** native code for foreign CodeInstances in images. This is the deep one, and pieces 9–12 make it easier to argue for.
6. **Piece 13,** instrumentation. It is small.
7. **Pieces 1 and 14,** the definition hook and the "would invalidate" query. They are what strict mode needs, and useful upstream (piracy tools, Revise, invalidation tools).
8. **Piece 3,** the intrinsics.
9. **Pieces 7 and 8,** when the demonstrators' numbers are in.

**The upstream story.** Pieces 5 and 9–13 make up one proposal: "first-class foreign cache owners". It is useful far beyond traits, and it is the first proposal to make. Piece 1 is a second, small one. Traits in the language come last.

## What TraitWorld works around today

| # | Need | Workaround in TraitWorld or the patched build today | Cost of the workaround |
|---|---|---|---|
| 1 | **A hook when a method is defined**, before it becomes visible, that may refuse it. For a package image, called once with all the image's new methods, before `jl_activate_methods`. | **Late overrides:** refused only at checkpoints (`check_overrides`: at declarations, at a module's end, at first calls). **Pirates of sealed packages:** found by scanning the method table after each top-level `using`, then warned about or deleted (order-dependent; the deleted method's invalidations already happened). **`needed` and keep flags** are fixed at a module's end and do not follow a method added later at the prompt. **Ownership (rule 3)** is checked only for methods defined inside trait modules. | wrong-until-checked windows; delete-after-load sealing; an error instead of a correct recompile in the late-callee case |
| 2 | **An invalidation policy hook:** a predicate, consulted at method insertion and at image validation, saying whether a definition can change a given CodeInstance. The view of rule 4: the owners of the function and of every type in the signature, with their trait-world dependencies. | The patched build hard-codes the policy in C (`gf.c`, insertion half) and in `Compiler/src/reinfer.jl` (load half, reworked three times for the bootstrap). It protects trait modules and TraitWorld's machinery. The load half keeps a Base callee for its trait-world caller; the insertion half has no such callee rule, which is part of row 7's residue. Review F1 found the policy wrong under keys and it was fixed (280612ed2f): the owner of a type the code was compiled for is in its view. | a fork of Julia; the policy is duplicated in C and in Julia; Base methods compiled for trait-world callers are still invalidated at insertion |
| 3 | **Field loads and stores at an offset, with Julia's alias metadata and write barrier,** as intrinsics. | `llvmcall` with hand-written TBAA metadata for isbits and pointer fields; `setfield!` by index for reference fields (10.7 ns); `getfield` for inline non-isbits fields. | fragile IR strings; inline non-isbits fields are not loaded inline |
| 4 | **Machine code for upstream CodeInstances in downstream images** (findings §15): a worker for a new key compiled in a conformer's or a view cache's image keeps its native code. | view caches and ComboCache rebuild in separate processes; a build-time replay for binaries. | first calls of a new key compile in each session unless a view cache exists |
| 5 | **Checks at compile time instead of at first call:** run the rule-2 and piracy checks when a worker's code is inferred, not in `checked_call` at its first call and after every world change. | `checked_call` carries a flag and a guard per signature, with a world-counter test on every call. `_check_once` and the audit run at the first call, and again after any load. | 3 ns per call (33 against 30 ns); tens to hundreds of milliseconds on first calls after large loads (session note 23, rows 1 and 7) |
| 6 | **The dispatch check at dynamic sites** (rule 4, "Leaks become errors"): a method selected at run time from trait-world code must come from the call's view. | not implemented; static checks only; entries check their own dispatch. | a leak would compute a wrong result instead of raising |
| 7 | **Traits in the type system and dispatch.** Membership as subtyping (`x isa ColTable`, `T <: ColTable` after the type is defined, by declaration); a trait bound as a dispatch tier above `Any` and below every type; entries generated by the compiler. | `conforms(T, X)`; an entry method at `Any` per bounded shape; trait sets encoded as families plus `PTag`s so that workers have no free static parameter; `@max_methods 1` and sentinel methods on every registry; untyped calls at 95 ns against 33 ns typed. | the machinery's complexity; ambiguity checks by hand; bounds cannot use a method's `where` variables |
| 8 | **Syntax:** `trait`, `implement`, `Self`, a trait's name in a field meaning its `Dynamic`, bounds in `where` clauses. | macros; the `@trait_module` rewrite. | macros and error messages in machinery terms |

## The order to implement them in Julia

Each step is useful upstream on its own, and each removes a workaround above.

1. **The method-definition hook (#1).** It is small:
   - in `jl_method_table_insert`, a callback that may throw before the method is activated;
   - in image loading, a callback with the list of new external methods before `jl_activate_methods`.

   It is the most general piece. Aqua-style piracy enforcement, Revise and tooling can use it too. It settles, cleanly:
   - late overrides;
   - pirates refused at load, whatever the order;
   - `needed` and keep flags that follow definitions at the prompt;
   - rule 3 for every package, not only trait modules.

   The patched build can carry it at once.
2. **The invalidation policy hook (#2),** replacing our hard-coded filter. An API: a registered predicate `(::CodeInstance, ::Method) -> Bool`, consulted in `invalidate_code_instance` and in `verify_call`, with a callee rule at insertion as at load. It turns our fork into a policy in a package. With #1 it gives row 7's claim: an unrelated load invalidates no trait-world code, and a pirate is refused before it can. Upstream interest is plausible (selective invalidation is a known request), but the policy's soundness argument is ours to make.
3. **Field-offset intrinsics (#3).** A small codegen change (`Core.Intrinsics.getfield_at_offset`, a store with a write barrier). It removes the `llvmcall` strings and makes inline non-isbits fields cheap.
4. **Compile-time checks (#5).** A hook when a CodeInstance is inferred: an `AbstractInterpreter` callback or a post-inference pass registered per module. It lets the checks run once, where code is compiled, and drops the per-call guard. It depends on #1 and #2: once pirates are refused at load, the per-signature audit after world changes has nothing left to find.
5. **Native code for upstream instances in downstream images (#4).** Medium, in `staticdata.c` and `precompile.jl`. It makes view caches and conformers' images complete, the placement half of rule 4.
6. **The dispatch check at dynamic sites (#6).** Codegen emits a checked dynamic call at call sites in trait-world code, and `jl_apply_generic` is unchanged for ordinary code. Deep but contained. It makes "identical or error" hold for leaks.
7. **Traits in the type system and dispatch (#7), then syntax (#8).** The deep part:
   - conformance adds a supertype after definition, by declaration;
   - a trait bound is a dispatch tier;
   - the compiler generates the entries and the workers per key.

   It comes last, once the demonstrators have shown the pay-offs, so that the upstream proposal (README plan step 5) rests on numbers. It removes the encodings TraitWorld needs today (entries at `Any`, `PTag`s, sentinels, `conforms`).

**What not to ask of Julia:**
- definition checking at archetypes;
- keep detection;
- concrete mode;
- `verify_main` and its target lists. JuliaC could accept the list, a small change, if trimming needs it.
- `Dynamic` values;
- `DynamicFn`.

These are package code on top of the hooks.

## Relation to earlier documents

`explorations/runtime.md` §1 lists the runtime pieces as of session 22. This document adds:
- the method-definition hook as a piece of its own (#1), which session 23 found most of the remaining checkpoint workarounds wait on;
- the compile-time checks (#5);
- the policy correction of review F1.

## Implemented (2026-10-16, session 23): pieces 1–5 and the compiler policy of wrapping by facts

Branches: Julia `trait-world-1.13-hooks` (worktree `julia-1.13/`, details in its `TRAITWORLD.md`); TraitWorld `julia-hooks` (worktree `TraitWorld-hooks/`). Piece 6 was drafted and then dropped, because the user adopted wrapping by facts (`wrapping-by-facts.md`), which does not need it.

| Piece | Julia | TraitWorld | What it gives |
|---|---|---|---|
| 1. Definition hooks | dda21fe511 | cd4b960 | Overrides after a conformance and pirates of sealed packages are refused when they are defined. An image's pirates are left inactive at load, in either load order. |
| 2. Invalidation policy hook | fac46840b8, 87dcf22015 | 8bbea71, 7c3fcdc | The policy is TraitWorld's: the package whose types a signature requires. Skipped code keeps its backedges, which fixes a stale-code bug. TraitWorld's own image is now protected at load. With CSV, DataFrames and CairoMakie loaded after TraitDifferentialEquations, nothing is invalidated and the first solve takes 53 ms. Not needed under wrapping by facts. |
| 3. Field-offset intrinsics | 3133c31c5f | 6f33a02 | No `llvmcall`. Loops still vectorize: 0.121 ns per element against 0.120 plain. |
| 4. Post-inference hook | 87dcf22015 | 7c3fcdc | Audits run where code is compiled. Each guard is a single stamp compare: a typed call takes 31.4 ns, against 33.3 ns before and 29.9 ns plain. |
| 5. Native code for upstream and foreign CodeInstances | 9af2f27786 | c62efbf | A package image keeps machine code compiled during its precompilation for upstream code it reaches dynamically, and for an AbstractInterpreter's own cache. Test package: first call 0.33 ms instead of 21.5 ms; the interpreter's code 0.39 ms instead of 11.1 s. |

**The compiler policy (rule R)** is TraitWorld's `facts.jl` (d74df76, c62efbf):
- **The interpreter.** `FactsInterp` has its own owner, `FactsOwner`. Calls at concrete signatures, including union-split ones, record edges. Any other call records nothing and dispatches at run time, typed `Any`.
- **The one exception: TraitWorld's own functions.** A view's object is held as `Any`, so their calls have abstract argument types. Inferring them as usual keeps their edges. Making them run-time dispatches cost 12 µs per call.
- **How entries reach the worker.** An entry calls the worker's CodeInstance through its machine code. After 1000 calls of a signature, it switches to an opaque closure built from the same IR. `invoke(f, ci, …)` costs about 440 ns because of its checks and boxing.
- **Rule 1 is off.** It is back only with `JULIA_TW_LAYERING=1`.
- **Two pitfalls found on the way:**
  - The interpreter must keep its IR (`may_discard_trees = false`). Otherwise images hold CodeInstances that cannot be compiled.
  - A closure must never reach an image. Closures stored in generated code segfaulted after load.

Measured on 1.13.2 (fresh sessions):

| | patched, policy on | stock, policy on | stock, policy off |
|---|---|---|---|
| `experiments/facts/acceptance.jl` | 5/5 | 5/5 | (4/5 on main) |
| TraitWorld suite | 353 + 1 broken | 347 + 1 broken | |
| TDE and TraitMakie tests | pass | pass | pass |
| typed `total(t,16)` (plain 29.9 ns) | 42.0 ns (32.7 ns with the policy off) | 41.8 ns | 33.6 ns |
| untyped | 105 ns | 99 ns | 98 ns |
| TDE row 1, row 2, row 4 | 49–51, 14, 13/12 ms | 441, 14, 19/14 ms | 103, 14, 13 ms |
| Rodas5, first solve and second function | 69–70, 49 ms | 577, 49 ms | 130, 50 ms |
| row 7, loads after: first solve; code invalidated | 53 ms; none | 2.9 s; 8 ODECore, 631 machinery | 1.06 s; 8, 728 |
| row 7, loads before: first solve | 0.56 s | 2.9 s | 1.07 s |
| TraitMakie first PNG: alone, after, before | 83, 83, 141 ms | 222, 462, 456 ms | 78, 306, 303 ms |

What the numbers mean:
- **On stock**, images hold the policy's IR but no machine code, so a session compiles it: row 1 takes 0.44 s.
- **Row 7 on stock** shows the machinery's own abstract edges being invalidated. These are the E0 chains in TraitWorld's printing and promotion paths. The patched filter still protects them. Under the adopted design, the cure is to make those paths concrete, not to keep the filter.

**Still open:**
- Row 7 in the "before" order on the patched build: 0.56 s.
- The machinery's abstract paths (above).
- Rodas5 with ForwardDiff's own `Dual` (not done).
- Removing the invalidation filter and sealing, which the new design no longer needs.
- Trimmed binaries: the policy is off in a closed world.

## Found while validating wrapping by facts (session 24, 2026-10-17)

Three more pieces. Each is small and upstream-shaped, since any `AbstractInterpreter` with its own cache owner (GPU compilers, Enzyme, Cassette-like tools) meets the same issues.

| # | Need | What happens without it | State |
|---|---|---|---|
| 9 | **Owner-aware bare MethodInstance edges.** When one CodeInstance is invalidated, a caller whose edge names only the MethodInstance is invalidated only if it has the same owner (or is a generator's cached output). | A facts-owned caller with a bare edge (a cycle partner, or a callee whose result was not cached) is invalidated whenever the *native* code of the same instance is. TDE after CSV, DataFrames and CairoMakie lost 3 facts-owned instances that way. | In the patched build (`gf.c`, `_invalidate_backedges`); with it, 0 are lost |
| 10 | **The inliner uses the CodeInstance it is given.** `handle_invoke_expr!` resolves `:invoke ci` through `get_ci_mi(ci)` in the caller's own cache. | A native caller of `invoke(f, facts_ci, …)` inlines the *native* code of the same instance. `add_inlining_edge!` then drops that code's edge as a duplicate of `ci`'s (it compares `.def`, ignoring the owner), a stale-code hole. TraitWorld marks the call `@noinline`, which costs about 5 ns per typed call (35 against 30). | Worked around |
| 11 | **"Call this signature compiled under owner X" as a runtime entry point,** with the same world validation as ordinary inference. Codegen would emit a direct call, and the edges would be `(sig, ci)`. | TraitWorld uses a generated function whose generator runs the policy's inference. That inference runs in a pure callback, where `jl_get_world_counter()` is `~0`, so the lock-checked validation of world ranges is bypassed: a method inserted on another thread at the same moment could leave a stale CodeInstance. The generator must also guard against re-entry (recursion through an entry). | Worked around; sound single-threaded |

| # | Need | What happens without it | State |
|---|---|---|---|
| 12 | **A frozen world for an external interpreter's compiler,** as Julia's own compiler has (`jl_typeinf_world`). | TraitWorld's image holds the compiler's native code specialized for `FactsInterp`. Packages loaded before TraitWorld make it fail verification at load, and packages loaded after invalidate it in the latest world. TraitWorld runs the compiler in a world fixed at its `__init__`, and answers cache hits without the compiler. A new key after big loaded-before packages still recompiles about 600 instances of the compiler's code, about 0.5 s once per session. | Worked around in part |
