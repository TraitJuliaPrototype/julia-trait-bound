# Session 24: validating "wrapping by facts" (running notes)

The user (end of session 23): "Go ahead. Push forward without coming back to me until you have completely validated the design, or until you have proven that it can not be made to work. Call out to subagents to generate ideas if stuck. Once you have convinced yourself of something subtle/complex have a subagent review it." And: "keep frequent running notes on this work in a sensible location" (this file).

**Design:** `writeup/explorations/wrapping-by-facts.md`.

**State at the start:**
- TraitWorld `main` c62efbf: `FactsInterp`, the compiler policy, in `src/facts.jl`.
- julia-1.13 `trait-world-1.13` 9af2f27786: pieces 1–5.
- Acceptance 5/5 on both builds.

## What "completely validated" means here

1. **G1 (identical or error):** the acceptance checks plus the demonstrators, under redefinitions, pirates, and calls into code written without traits (ForwardDiff, Cairo used directly). No skip predicate may be active (rule P).
2. **G2 (stable cache):** with CSV, DataFrames, CairoMakie and others loaded before or after, in any order, no trait-world code is invalidated except by stakeholders or winning pirates. TraitWorld's machinery should not be invalidated either, or should not matter.
3. **Speed:** typed calls near plain Julia; first calls fast from images; hot loops of the demonstrators at plain speed.
4. **The subtle points reviewed by a subagent:** the soundness of the implementation (exemptions, return types, opaque closures, images), and the proof's assumptions.

## Open points found at the start (reading `src/facts.jl` and the agent's notes)

- **Machinery exemption.** Calls to TraitWorld's own functions are inferred under Julia's own policy (abstract edges). This is sound, since edges are recorded and not skipped, but it costs G2 (machinery invalidated by loads: 631 instances on stock in row 7) unless the machinery's paths are concrete.
- **The patched build still registers the skip predicate** (the policy hook of piece 2, rule 4 by required package). Rule P says nothing is skipped. Measure with the predicate off; remove it if the facts alone suffice.
- **Typed calls cost 42 ns** under the policy (32.7 ns without, 29.9 ns plain): `_facts_call` is not inlined, plus a world check and an opaque-closure call.
- **Row 7 "before" costs 0.56 s** on the patched build: to diagnose.
- **On stock Julia** (no piece 5) every session compiles the policy's cache: inherent, so stock is not the target for speed.

## Log

- (start) Phase A: the demonstrators use ForwardDiff and Cairo directly. Rule 1 is off by default (`LAYERING[]`), so trait modules may import Cairo.
- **A1: TraitMakie calls Cairo directly** (branch `direct-cairo`, uncommitted). The declared calls (`@call`), the `Surface` handle and the Cairo helpers in the ordinary module are gone; `PlotCore` does `using Cairo` and calls it. Patched build, filter on:
  - tests pass;
  - first PNG 83 ms alone, 143 ms with CSV and DataFrames loaded before, 84 ms with them loaded after;
  - invalidated after the loads: PlotCore 0, TraitWorld 0.
- **Key test: the skip predicate off** (`JULIA_TW_FILTER=0`, so nothing is skipped, as rule P demands). Patched build:

  | | none | loaded before | loaded after |
  |---|---|---|---|
  | TraitMakie first PNG | 145 ms | 252 ms | 303 ms |
  | TraitMakie invalidations | | | PlotCore 0, TraitWorld machinery 312 |
  | TDE row 1, first solve | 52 ms | 2.49 s | 2.72 s |
  | TDE row 2, second model function | 15 ms | 15.6 ms | 15 ms |
  | TDE row 4, new callback | 22 ms | 123 ms | 4.5 s |

  TDE "after": ODECore 8 invalidated (`keep_callback`, `solve_ode`), the ordinary layer 13, machinery 751.

  **So the facts policy alone does not yet give G2.** The filter (a skip predicate) was carrying it. Suspects:
  - **(a)** entries and the ordinary layer are compiled natively, with abstract edges;
  - **(b)** the machinery's exemption from the policy;
  - **(c)** native CodeInstances of trait-module methods next to the facts ones.

  Next: attribute the chains (trigger, root edge, holder).

- **Chains attributed, by cache owner** (`$TMPDIR/g2/owners.jl`, filter off, loads after). Invalidated by the loads:

  | | facts-owned | native |
  |---|---|---|
  | ODECore | 1 (`keep_callback`) | 7 (`solve_ode` ×5, `keep_callback` ×2) |
  | TDE (ordinary layer) | 0 | 5 |
  | TraitWorld | 2 | 292 |

  The first solve after the loads (2.58 s) creates **only native CodeInstances**: Base 243, other 638, TraitWorld 43, ODECore 1. So the policy's own code survives the loads; the time goes into *native* re-inference.
  - **Cause:** `_facts_call` computed its result type with `Core.Compiler.return_type(f, A)` in the generated body. That makes native inference of the worker (`solve_ode` natively, with all its abstract edges) a dependency of every entry. The loads invalidate the native worker; then the entry, and the first call re-infers the whole worker natively, only to learn a return type.
  - **Hypothesis 2 is refuted** (shared MethodInstance backedges). `_invalidate_backedges(mi, ci)` invalidates only callers whose edges name that CodeInstance or the bare MethodInstance (`gf.c` 2470–2530). A facts caller holds an edge to the facts callee CodeInstance, so native invalidation of the same MethodInstance does not reach it. A whole-MethodInstance invalidation (method replaced or deleted) reaches all owners, which is correct.
- **Fix under test: the entry invokes the facts CodeInstance directly.**
  - **How:** a custom generator (not a `CachedGenerator`) is given the `world`. It compiles the facts CodeInstance in that world and emits `Core.invoke(f, ci, args...)` with `ci` a constant.
  - **What inference makes of it:** an `InvokeCICallInfo`. The result type is `ci.rettype`, the edge is `(method sig, ci)` (exact: only `ci`'s own invalidation or the method's replacement reaches it), and the call becomes `:invoke ci`.
  - **Results** (`$TMPDIR/gi/t3.jl`): correct values; the entry stays valid when the native code of the same MethodInstance is invalidated; the entry is invalidated by a redefinition of a fact.
  - **Pitfall, a Julia inliner bug:** `handle_invoke_expr!` resolves `:invoke ci` by `get_ci_mi(ci)` in the *interpreter's own* cache. A native caller therefore inlines the *native* code of the same MethodInstance if it exists, ignoring `ci`'s owner. This is sound (the edge then goes to the native CodeInstance and plain Julia's code runs), but it brings back abstract edges, so it costs G2, and it depends on order. Work-around: call-site `@noinline` on the invoke (the statement flag stops the inliner). Julia piece to propose: the inliner uses the source of the CodeInstance it is given.
- **Implemented in TraitWorld** (ea781b4, b477dfd):
  - `_facts_call` is generated by `_FactsCallGen` for the world it is inferred in, and emits `@noinline Core.invoke(f, ci, args...)`. Removed: `FactsEntry`, the opaque closures, the jlcall-pointer path, `FACTS_HOT`.
  - `_facts_call` is **inlined** into the entry. As a frame of its own it copied the view, built on the entry's stack, into an argument tuple, and typed calls took 69 ns.
  - `checked_call` and `checked_kwcall` choose the worker call when they are generated. Under the policy the plain call is not in the code at all: inferring it compiled the worker natively and tied every entry to that code's abstract edges.
    - **Keyword workers now run under the policy too.** Before, `checked_kwcall` called them natively: a rule R gap.
    - `FACTS` is now a switch at generation time (diagnosis only).
    - A `--trim` build generates the plain call.
  - **The piracy guard is off on the policy's path.** It audited *native* code (`_latest_ci` takes owner `nothing`) after every world change, and under G1 a winning pirate is followed. Two tests now check G1's behaviour when the policy is on.
  - `verify_main` skips an `:invoke` of a facts-owned CodeInstance, as it skipped the `_facts_call` call.
- **Measured** (patched build, filter off):
  - typed `total(t,16)`: **39–40 ns**. Plain is 29.7; the opaque-closure path was 42–45. Prebuilt view, worker not inlined: 35 ns.
  - TDE row 1 after the loads: **535–545 ms** (was 2.5–2.7 s); row 4 after the loads: 244–1458 ms (noisy: shared machine); "before": 554–566 ms; no loads: 57 ms.
  - TraitWorld suite, TDE and TraitMakie tests: pass; acceptance 5/5.
- **What remains after the loads** (by owner):
  - The policy's own code loses 3 instances: `keep_callback`, `Dynamic{Callback}(…)` and `_carries(Type{Callback},Type{Callback})`.
  - **Cause:** `_carries` holds a *bare MethodInstance edge*, `(Tuple{typeof(_decode_traits),Any}, MI)`, recorded because inference had no cached result for the callee (cycle, or result not cached).
  - **Why that hurts:** `_invalidate_backedges(mi, ci)` matches a bare MethodInstance edge against **any owner's** CodeInstance. The native `_decode_traits(::Any)` is invalidated through a Base closure (trigger: Unitful's `Colon`), and the facts code goes with it.
  - **Fix: owner-aware bare MethodInstance edges** (`gf.c`). When a specific CodeInstance is invalidated, a bare MethodInstance edge matches only callers of the same owner.
    - **Why sound:** an interpreter consults only its own cache, and a bare edge stands for the caller's own interpreter's result (a cycle partner, or an uncached result). Method replacement still reaches every owner, since it calls `_invalidate_backedges(mi, NULL)`.
    - **Other cross-owner reads are exact:** `InvokeCICallInfo` records the CodeInstance; the inliner bug records the native CodeInstance it inlined; concrete evaluation needs foldable effects, which a run-time site rules out.
    - **Status:** building now; to be reviewed by a subagent.
  - **The rest is native machinery.** First calls after loads re-infer TraitWorld's reflective slow paths (`witness`, `proj_lookup`, `_field_problems`, `_builder_for`, `Dynamic{…}`, printing of a `MethodError` inside `which`). The loads invalidate their native code (about 250 instances); the "before" order drops it at load. These are plain Julia's invalidations of TraitWorld's own abstractly typed implementation code. Cure options: type-level computations as generated functions (no edges, constant results); concrete slow paths; or slow-path results kept in images.
- **Owner-aware bare edges: measured.** With the patch built, facts-owned code lost to the loads: **0** (was 3). TDE row 4 after the loads is 23 ms (was 244–1458 ms).
- **Review of the entry and the edge patch** (subagent, code reading). It confirmed the edge patch and found four G1 problems in the entry, each now reproduced and fixed:

  | Problem | Reproduced as | Fix |
  |---|---|---|
  | **A1, dispatch at the call signature not tracked.** `InvokeCICallInfo` records `(method sig, ci)`, which only the method's replacement breaks. | G1.6 (on `_facts_call` directly): stayed 1, plain 2 | The generator adds `(sig, ci)` (the dispatch fact at the concrete signature, as native code records) and the lookup's world bounds |
  | **Recursion through an entry.** The generator infers the worker while it is being inferred. | G1.7: passed only after stack overflows | A per-task "generating" list; on re-entry the call is left to run time |
  | **`return_type` folded under the policy gives `Any`**, even at a concrete signature: `_iterator_upper_bound(::Generator{Vector{Integer},…})` has an abstract site inside. | G1.8: `map(x -> c, Integer[])` gave `Vector{Any}`, plain `Vector{Int}` | Plain Julia's answer: at a concrete signature folded from *native* inference, with the edge `(sig, native ci)` (`_NativeRT`); at an abstract one left to run time. G1.9: the fold follows a redefinition |
  | **The skip filter was on by default** (rule P) | — | Opt-in with `JULIA_TW_FILTER=1`, in TraitWorld and `reinfer.jl` (rebuild running) |

  Acceptance: **9/9**.
  - **Correction to my note above.** Without the call-site `@noinline`, a native caller inlining the native code would **not** be sound. `add_inlining_edge!` drops the native CodeInstance as a duplicate of `ci`, since it compares `.def` and ignores the owner. That would be a stale-code hole, so `@noinline` is required.
  - **Edge patch, corner case.** A `CachedGenerator`'s cached output (owner `:uninferred`) may depend on any owner's result, so it matches every owner (in the rebuild).
  - **Open (threads only).** The generator runs inference in a pure callback, where `jl_get_world_counter()` is `~0`. That defeats the lock-checked world validation, so a method inserted concurrently on another thread could leave a stale facts CodeInstance. Single-threaded it is sound. The clean cure is a runtime entry point for "compile this call under owner X", not a generator: a Julia piece to add to `julia-support.md`.
  - **Latent.** `CompilerPlugins.typeinf_edge(::FactsOwner)` is never called by 1.13; if it were, a facts frame could join a native call stack, and the edge patch's argument would need revisiting.
- **Rebuild** (julia 5b5b98758f): the filter is opt-in (`JULIA_TW_FILTER=1`); `:uninferred` callers match every owner.
- **The machinery's slow paths, wrapped by facts** (TraitWorld f073de0).
  - `_check_once`, `_builder_for`, `worker_problems` and `_check_concrete` run through `_latest_under_policy`: `invokelatest(_facts_call, f, args...)`. Their facts CodeInstances are compiled into TraitWorld's own image; without that, TraitMakie paid 830–1700 ms on first use.
  - `Dynamic{X}(::TObj)` checks the traits it carries through a generated constant (`_carries_static`). This is a pure computation on types, so the code holds no edge to the reflective code.
  - **Lesson, `return_type` × G2.** Folding native inference into facts code brings plain Julia's *abstract* dependence with it. Here: an error path's `collect` over a generator of strings depended on `string(::Any)`, and InlineStrings' new `string` method invalidated `_check_once`. So the fold now happens only when the native answer rests on concrete facts (`_concrete_deps`: no method-table edge within 2000 CodeInstances); otherwise the call runs at run time, which is plain Julia's answer in the current world. G1 holds either way; G2 holds for the fold.
- **Results** (patched build, no filter; every number below is a rerun after the images were rebuilt):

  | | no loads | CSV, DataFrames, CairoMakie after | before |
  |---|---|---|---|
  | TDE first solve | 57 ms | 59 ms | 59 ms |
  | TDE second model function / new callback | 15 / 22 ms | 15 / 22 ms | 15 / 23 ms |
  | TraitMakie first PNG (CSV, DataFrames) | 87 ms | 89–93 ms | 90–93 ms |

  - **Invalidated by the loads:** facts-owned 0, ODECore 0, the ordinary layer 0, PlotCore 0. What remains is TraitWorld's *definition-time* machinery (`_analyze_keeps`, `seal!`, …; 440–655 instances), on no call path.
  - Typed calls 37–39 ns (plain 30); untyped 109–119 ns. Acceptance 9/9. The TraitWorld suite, TDE and TraitMakie tests pass.
  - **G2 holds for both demonstrators, with no skip predicate (rule P).** Load order no longer matters for first calls.
- **Still to do for "completely validated":**
  - a review of the slow-path wrapping and of the `return_type` rule;
  - broader G1 adversarial cases (other tfuncs that read the method table: `hasmethod`, `applicable`; `invoke`; generated functions; keyword workers);
  - the cost of defining a trait module after big loads (definition-time machinery);
  - larger code and other stacks;
  - the policy's compile cost when no image holds its code.
- **New trait code defined after big loads** (`$TMPDIR/g2/newmod.jl`):
  - defining a small trait module takes 0.96 s without loads and 2.7 s with them; its first call 89 ms and 790 ms.
  - **The policy's compiler.** It ran in the latest world, so the loads invalidated its native code specialized for `FactsInterp` (670 instances, 7 s). Now it runs in a world fixed at TraitWorld's `__init__`, as Julia's own compiler does (`_in_compiler_world`).
  - **The rest is the machinery's checks** (rule 2, doors, concrete mode), still native. The facts-compiled checks reach them through run-time dispatch: inference limits the mutual recursion `_worker_problems` → `_layering!` → `worker_problems` at abstract types, so the calls stay dynamic, and a run-time call runs native code, which the loads invalidated.
  - Pointing the checks at the facts code broke rule 2's error-path recognition (the facts code types `kwerr` `Any`, not `Union{}`) and gained little, so it was reverted.
  - **Verdict:** an implementation cost of TraitWorld's reflective checks, outside the design's claims (G2 is about trait-world code, and that is not invalidated). The cure is the checks in the compiler (Julia piece 7) or a non-recursive walk.
- **Adversarial G1 hunt** (subagent, 48 cases, ~125 checks; suite in `experiments/facts/hunt/`). It covered `hasmethod`, `applicable`, `which`, `invoke`, generated functions, keyword calls, varargs, `Type{T}`, union splitting, concrete and semi-concrete evaluation, closures, `invokelatest`, `eval`, rebound globals, struct redefinition, ambiguities, `delete_method`, and Base methods for new types. It found **two failure classes**:
  1. **Asserted effects over a run-time site.** `@assume_effects :foldable` (or `Base.@pure`) let compile-time evaluation fold a value whose run-time site the policy's code holds no fact for. It went stale after a redefinition, both inside facts code and in the native entry caller. Fix:
     - FactsInterp refuses concrete and semi-concrete evaluation of a callee whose facts code has a run-time call (`_has_runtime_sites`, an IR scan);
     - the entry passes such a worker's result through `compilerbarrier(:const)`.
  2. **`return_type` folded at the compilation signature** (widened for `@nospecialize`, `Function`, `Type`, long Vararg). Fix: infer at `specialize_method(match)`.
- **Second review** (subagent):
  - **C4 (`_carries_static` pure) and C5 (`:uninferred`): hold.**
  - **C2 failed on G2.** `_concrete_deps` missed abstract dispatch recorded as bare edges with abstract `specTypes`, or as match groups. Now it rejects those, and bare MethodInstances too.
  - **C1:** recursion with growing types nested generators without bound; and output emitted on re-entry could be cached for the native owner. Now the generator throws on re-entry and beyond depth 8, so inference gives up without caching.
  - **C3:** the machinery exemption's docstring was too strong (trait modules extend `param` and `implementation`): sound, but a G2 cost for the machinery when a trait library loads. Docstring corrected.
  - `_NativeRT` is now wrapped in `MethodResultPure`.
- **A G1 carve-out found:** plain Julia itself gives different answers for the same inference query. `return_type(pass, Tuple{Type{Int}})` is `Type{Int64}` at run time and `DataType` folded in compiled code. Values that depend on inference precision (`return_type`, `promote_op`, element types of empty collections and broadcasts) have no single plain answer. The policy matches them where practical (G1.8, G1.9, G1.11); the design should say so.
- **State** (TraitWorld f558180, experiments 9a35d14):
  - acceptance **12/12**;
  - the hunt suite passes but for C16 (the carve-out) and C24b (a harness bug);
  - the suite, TDE and TraitMakie pass;
  - TDE first solve 59–60 ms in every load order; TraitMakie first PNG 93–96 ms; typed 37 ns.
