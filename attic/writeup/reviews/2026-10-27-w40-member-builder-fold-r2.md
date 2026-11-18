# Review 2: W-40 design note, revision 2 (`writeup/plans/2026-10-26-w40-member-builder-fold.md`)

Reviewer: fresh eyes, source read only, nothing run (2026-10-27). Sources: julia-1.13 at 0c589fd385, TraitWorld at aac1694 (W-50 landed during the review; its new supertrait loops, `implement.jl:900-904` and `entry.jl:1191-1195`, add more `witness` calls to the member check).

## Verdict

1. **Build after fixes.** Direction 0 is workable in 1.13. The four first-review blockers are resolved on paper, each with gaps listed below.
2. One new blocker: a folded builder larger than 256 bytes is not removed by the optimizer. The call then runs and returns `nothing` into code typed as the builder. That is a trap or memory corruption.
3. TraitWorld's check cannot keep the "no user code" rule as written. Re-entrancy can still poison the caches and the global code cache. The gate, the load pass and the `Dynamic` split are under-specified. Fix these in §4.1, §4.2 and §9 before building.

---

## Answers in brief

### 1. The four blockers

| | Resolved? | Remaining |
|---|---|---|
| **B1 deadlock** | Yes in principle. No W-40-specific ABBA remains: a thread holding `_LOCK` that waits for `jl_typeinf_lock` finds `g` failing its `trylock` and returning. | (a) `trylock` on a `ReentrantLock` succeeds when the current task already holds `_LOCK`, so the nested call runs inside the outer critical section (S1 below; the first review's S3 is still open). (b) "Never blocks" is not literally true: `g`'s nested inference can wait on an engine reservation (`src/engine.cpp:60-104`), exactly as ordinary inference does. The note should say so. (c) The discipline needs code changes the note only names (§2 below). |
| **B2 edge walkers** | Yes for `ForwardToBackedgeIterator`, `verify_method` and `rests_on_facts`. I checked the C side: `staticdata.c` serialises `ci->edges` as a plain svec (`:1759-1764` touches only world bounds). `jl_promote_cis_to_current` skips anything that is not a CodeInstance (`gf.c:2024-2030`). `staticdata_utils.c` walks MI backedges only. So no C change is needed. | (a) Semi-concrete evaluation drops edges (`abstractinterpretation.jl:1315`, `const_edge = nothing # TODO`), so a fold in irinterp has no record (S4). (b) The `_jl_debug_method_invalidation` entry for a record is still undecided (`reinfer.jl:279-282`). (c) The pre-pass must find records inside the dummy CodeInstances that constant propagation creates (`codeinst_as_edge`, `typeinfer.jl:1025-1048`). They are not in `internal_methods`. |
| **B3 world** | Yes on paper: `g` fixes only when the inference world is the latest, and `_DECISION_WORLD` is reset. | (a) The check is time-of-check to time-of-use: a definition on another thread between the world check and publishing is accepted (S6). (b) About fifteen world reads in the check still go to the latest world or the task's world (§2). They agree only while nothing is defined concurrently. (c) An unfolded result from an older world is cached for every world after it (S2). |
| **B4 load order** | Yes for an operation override in an extension, by decision 63. That decision is still awaiting confirmation (open issues §1, item 63). | A member's own declaration (`@implement X S{MyT}`) from another package or an extension is still accepted before first use (T-28, `implement.jl:795-800`). Fixing L-23 alone makes its acceptance depend on whether an image that folds `S{MyT}` was validated first. Extensions load after the dependent image's validation (`base/loading.jl:2196-2229`). So the load-order failure remains for declarations until T-28 is retired (S7). |

### 2. Can direction 0's discipline be kept in today's check?

Mostly, with small changes. Hold `_LOCK` (taken by `trylock`) for all of `g`, so every inner `@lock _LOCK` is reentrant. With that, nothing in the call tree waits on another lock, except logging and engine reservations. What breaks the discipline:

**Yield / I/O** (each needs a "queue the warning" mode; small change):
- `@warn` in `_member_problems` (`implement.jl:907-908`);
- `@warn` in `_witness` (`implement.jl:414`);
- `@warn` in `_generic_concrete_check` (`entry.jl:178`);
- `Core.println` under `_FACTS_DEBUG` (`entry.jl:153`), debug only.

**User code** (not fixable by a flag alone):
- The generic predicate `g.pred` (`implement.jl:402`). It is reached through `witness` from `_param_bound_problems` (`:713`, a trait bound on a parameter), from `_result_conforms` → `conforms` (`:290`, `entry.jl:1189-1194`), from `_super_param_problem!` (`:744`), and from W-50's supertrait loop (`:900-904`). Detecting it needs an abort mode in `_witness` that does not store into `_WITNESS`. A medium change.
- Methods generated from the trait's own declarations run user-written expressions:
  - `op_args`/`op_ret` (`:204-205`, e.g. `eltype(R)`);
  - `param` (`:712`; `_instance`, `core.jl:379-383`);
  - `field_type` (`:621`);
  - `supertrait_args(Y, S)(vY...)` (`:749`);
  - `param_bound` (`:712`);
  - `trait_concreteness` (`:92`, `:114`).

  These cannot be avoided: the check is defined by them.
- `show` methods, user-defined or TraitWorld's type printers, run when problem strings are built: `conformance_problems` `:261`, `:266`, `:272-274`, and every `push!(out, "…$T…")`. Strings go to an `IOBuffer`, so they do not yield, but they are user code.

**Fix:** restate the rule. `g` runs the trait declarations' type expressions, which must be pure, as a generator's body must be. It runs no predicate and no `show`. In `g`, collect problems as a count or a Bool, and leave the messages to the run-time path.

**Wrong world.** Small, mechanical change: pass `w` explicitly everywhere.
- `_latest` (`Base.invokelatest`) in `_conf_family_slow` (`implement.jl:865`) and `_check_member` (`:922`).
- `_in_decision_world`/`_decision_world` when `_DECISION_WORLD` is 0 (`compiler.jl:105-107`).
- `_check_kw_at`'s default world (`compiler.jl:66`), used at `implement.jl:269` and `:641`; `_check_kw()` at `:428`.
- `methods(op_args, …)` (`:194`), `methods(generic_rec, …)` (`:233`) and `methods(conformance)` (`:786`, a walk over every `conformance` method per member check).
- `hasmethod(param_bound, …)` (`:708`) and `hasmethod(supertrait_args, …)` (`:743`), without a `world`.
- `Base._which` in `_declared_for` (`:797`) and `_has_conformance_method` (`:810`).
- `Base.invokelatest(trait_uses_self/trait_field_params)` (`entry.jl:687-688`).
- `Base.tls_world_age()` in `_conformance_slow` (`entry.jl:147`). Inside `g` this is the inference world, but the result is stored in `_SLOW` under it.
- `invokelatest` in `_family_records`/`_index_declared!` (`hooks.jl:127`, `:72`).

**Shared state written without a lock** (small change, copy-on-write):
- `_index_builder!` mutates `_OVR_INDEX` (`hooks.jl:113-118`). It is called outside `_LOCK` (`implement.jl:874`). The definition hook reads and rebuilds the same `IdDict` on another thread (`hooks.jl:84-96`, `:149`).
- `_FAMILY_WARNED` (`entry.jl:177`, `implement.jl:412`).

**Last writer wins:** `_conf_family_slow` overwrites the registry unconditionally (`implement.jl:867-871`). The note says "atomic replace". It must also be first-writer-wins, returning the entry that won.

### 3. Is calling arbitrary code from `abstract_call_known` safe in 1.13?

- **The lock is recursive per task, not per thread.** `jl_mutex_t` compares `owner == self`, where `self` is a `jl_task_t*` (`threading.c:945-948`). Nested JIT inference inside `g` re-enters it. A task switch inside `g` is fatal: another task on the same thread spins forever in `_jl_mutex_wait` (`threading.c:963-990`). Engine reservations are keyed by thread id (`engine.cpp:60-104`), which is a second reason not to switch tasks.
- **Nested inference has a precedent; JIT inside inference has another.**
  - `facts_plain_return_type` runs `typeinf_ext_toplevel` from inside `return_type`'s tfunc (`facts.jl:483`, `tfuncs.jl:3184`). That runs compiler code only, with no JIT and no library code.
  - JIT under the inference lock happens today when a generator's code is compiled (`jl_code_for_staged`), but inside a pure callback.
  - The combination `g` needs (library code, not pure, with reflection, nested inference and JIT) has no single precedent. Each part has one.
- **JIT of `g`'s own code.** `jl_type_infer` raises the depth counter. Beyond depth 3 it returns NULL and the code is interpreted (`gf.c:453-454`). If this thread holds the reservation of the requested MethodInstance, it also returns NULL (`gf.c:458`). Codegen's locks are leaves relative to inference (`jitlayers.cpp:357-369`), so there is no deadlock.
- **GC.** A collection is fine. Finalizers do not run inside `g`: `jl_gc_run_pending_finalizers` requires `locks.len == 0` and `engine_nqueued == 0` (`gc-common.c:328`). The inference lock and the reservations both block it.
- **Other locks held at that point:**
  - only `jl_typeinf_lock`, plus the SIGINT deferral of `JL_LOCK`, so a long check cannot be interrupted;
  - the thread's engine reservations for the frames on the stack;
  - not codegen's locks, and not `world_counter_lock`. The method-definition hooks run outside it (`gf.c:2267-2300`).
- **The caller's reservation has a real consequence (S2).** Suppose `g`'s nested `infer_return_type` reaches the reserved `conformance` MethodInstance (the re-entrancy case of §7). `jl_engine_reserve` sees its own thread and returns without a reservation (`engine.cpp:80-84`). The member is then inferred a second time. The inner, unfolded result is cached globally. The outer, folded one finds it `is_already_cached` and becomes volatile (`typeinfer.jl:700-706`). Every other caller then gets the unfolded CodeInstance for the rest of the session, and images keep it.
- **`Core._call_in_world` is `invoke_in_world`** (`boot.jl:1082`). Inside a pure callback it ignores the requested world (`builtins.c:903-907`), so `g` would run in the compiler's world. Inference resets `in_pure_callback` on its C entry (`gf.c:481-482`), so this is safe there. Assert it anyway (C2).

### 4. The load pre-pass

- **Feasible.**
  - `insert_backedges` runs via `jl_call_in_typeinf_world` (`reinfer.jl:657-660`). It holds `require_lock` (`loading.jl:1335-1344`), but neither the inference lock nor `world_counter_lock`.
  - The image's methods are active, because activation precedes it (`staticdata.c:4461-4474`).
  - It runs before `register_restored_modules` and `__init__` (`loading.jl:1346`).
  - Library code can run there, JIT included. A CodeInstance of this image that `g` needs is still pending (sentinel `max_world`), so a fresh copy is compiled. That costs time but is harmless.
- **Propagation is correct.**
  - A record that fails sets `maxworld = 0` in the CodeInstance's non-CodeInstance phase (`reinfer.jl:222-280`).
  - Tarjan carries it to the image's callers (`:363-381`).
  - A later image naming that CodeInstance sees `max_world = 0` and fails (`:177-183`).
  - Nothing in the session depends on it yet.
- **But** see S3: a `trylock` failure or a moved world at load turns "undecided" into "invalid", so which code is kept depends on thread timing. Also, `g` must define no method or binding: a world bump during the walk stops `jl_promote_cis_to_current` (`gf.c:2011-2012`), and every root validated after it stays capped at its validation world.

### 5. Missed things

See N1 (blocker) and S2–S9.

---

## Blocker

### N1. A folded builder over 256 bytes stays a call that returns `nothing`

- **Where:** §4.1 line 49, "the call is `Const(v)` with total effects, and the optimizer removes it"; §4.2 lines 70-71.
- **What is wrong.**
  - The optimizer replaces a statement by its constant only if `is_inlineable_constant(v)` holds, i.e. `count_const_size(v) <= 256` (`Compiler/src/utilities.jl:30-74`; `ssair/inlining.jl:1768-1775`; `ssair/ir.jl:1576-1579`).
  - Otherwise the `fold_call` statement stays, and its SSA value keeps the type `Const(v)`.
  - At run time, `fold_call` returns `nothing`. Downstream code reads `getfield(%b, :specs)` from a value typed `Builder{S}`. Codegen either traps on the type mismatch or reinterprets the boxed `nothing` as a builder. A builder's `Slot` offsets then drive `_parts`' loads from the user's object: memory corruption.
  - **Real builders exceed 256 bytes.** A `Slot` is 16 bytes (`core.jl:38-41`), and a `VSpec` is 16 + 16·N bytes (`entry.jl:40-44`). A trait of 8 fields with two supertraits of 4 fields each gives 144 + 2·80 = 304 bytes.
  - `known_type` (a `Bool`) and `facts_plain_return_type` (a `Type`) never hit this. A declared type's builder does not either, because `getfield(c, :b)` still yields the builder at run time.
- **Fix** (either, plus a compiler assertion):
  - In the compiler, always replace a statement whose info is `FoldCallInfo` with `quoted(v)`, whatever its size, and root `v` as a method root.
  - Or in TraitWorld, fold a singleton: `g` returns `Val{v}()` (a builder is isbits, so it is a valid type parameter), and the method does `b isa Val && return typeof(b).parameters[1](u)`. The run-time path then also computes `v`.
  - Either way, add a rule to §4.1: a folded value must be reproduced by the run-time statement, or the statement must be replaced unconditionally.
  - Add a §7 check with a trait whose builder exceeds 256 bytes.

---

## Should fix

### S1. `trylock` lets `g` run inside the slow path's own critical section

- **Where:** §4.1 line 58; §4.2 line 79.
- **What is wrong.**
  - `_LOCK` is a `ReentrantLock` (`entry.jl:90`). `trylock` succeeds when the current task holds it.
  - `witness` holds `_LOCK` across `_witness` (`implement.jl:324-334`). That runs predicates and record methods (`:392`, `:402`), whose first call is JIT-compiled. That inference folds, and `g` then runs in the middle of the outer critical section.
  - `g` calls `witness` → `_flush_if_stale!` (`:309-316`). That empties `_WITNESS` and retags it with the latest world. The outer call then stores its old-world witness under the new tag. This is the first review's S3, unchanged.
  - The note does not say what the re-entrancy guard is keyed on.
- **Fix.**
  - In `g`, return "undecided" when `_LOCK.locked_by === current_task()`, before any `trylock`.
  - Key the guard per task and per `(X, U)`.
  - A nested evaluation commits nothing.

### S2. "Not folded" results are cached globally and win

- **Where:** §4.1 line 49 ("returns nothing or throws: the constant nothing"), §2 line 23, §10 S2.
- **What is wrong.**
  - An unfolded result is an ordinary cacheable CodeInstance. It is produced when the lock is taken, on re-entrancy, in an older world, or through the check's own `_check_kw_at` interpreter (`compiler.jl:66-68`, the plain cache on purpose).
  - Re-entrancy is worse than "returns nothing". It replaces the folded CodeInstance in the cache (§3 above, `typeinfer.jl:701-707`).
  - An older world's unfolded CodeInstance is valid in the latest world too.
  - So "its typed calls then cost what a declared type's do" fails for good in these cases. §10's answer to S2 (a memo of refusals) addresses S8, not S2.
- **Fix.**
  - Give `g` a third outcome, `Compiler.FoldUndecided`. Do not memoise it.
  - In inference, drop `CACHE_MODE_GLOBAL` for that frame (as `finishinfer!` does for limited results, `typeinfer.jl:632-645`). Or narrow the frame's worlds to `[w, w]` with `update_valid_age!`.
  - Let the check's interpreter fold registry hits.
  - Or record the gap as a deviation in §8.

### S3. At load, "undecided" must not mean "invalid"

- **Where:** §4.1 line 52.
- **What is wrong.**
  - At load, `trylock` can fail because another thread is on a slow path. The validation world can also lag behind `get_world_counter()` because of a concurrent definition.
  - In both cases `g` returns `nothing`, and the CodeInstance is discarded.
  - Correct, but which code an image keeps then depends on thread timing. That contradicts facts G2 and §11.
- **Fix.**
  - At load, take `_LOCK` blocking. It is not under the inference lock there; the lock order is `require_lock` → `_LOCK`, and nothing takes them in reverse.
  - If the world moved, rerun the pre-pass in the latest world.
  - Walk the pending CodeInstances recursively, including the constant-propagation dummies, to collect records.
  - State that `g` defines nothing.

### S4. A fold during semi-concrete evaluation loses its record

- **Where:** §4.1 line 51 ("also when the fold happens during constant propagation").
- **What is wrong.**
  - Constant propagation keeps its edges in 1.13 (`codeinst_as_edge`, `typeinfer.jl:1025-1048`; `abstractinterpretation.jl:1404`), so that part holds.
  - Semi-concrete evaluation drops them (`abstractinterpretation.jl:1315`). `abstract_call_known` is reached from `IRInterpretationState` too.
  - A fold that first succeeds there is kept in an image unchecked.
- **Fix.** Fold only when `sv isa InferenceState`. Produce the record through a `FoldCallInfo` with `add_edges_impl`, since `compute_edges!` rebuilds edges from `stmt_info` (`typeinfer.jl:806-815`).

### S5. The gate has no mechanism, and §4.1 contradicts §4.2 on the split

- **Where:** §4.1 line 49, §4.2 line 92, §9 line 160.
- **What is wrong.**
  - The JIT's `NativeInterpreter` is built exactly like reflection's (`typeinfer.jl:1655-1660`, `types.jl:401-419`), and so is TraitWorld's check interpreter (`compiler.jl:59-68`). Nothing distinguishes "compilation".
  - `facts_interp`, `plain_interp` and `interp_for_owner` rebuild interpreters positionally (`facts.jl:43-58`, `:61-63`).
  - §4.1 says the split's candidate inference does not fold. §4.2 says each branch folds and covers E-156 P13. The candidates are inferred by the same interpreter as ordinary frames (`facts.jl:689-714`), so excluding them needs a flag on those frames.
- **Fix.**
  - Add a field (e.g. `fold::UInt8`: none, hits only, fix). Set it to "fix" only in `typeinf_ext_toplevel(mi, world, …)` and the precompile and trim queue (`typeinfer.jl:1748`). Carry it through the three positional constructors.
  - Decide the split: hits only, or fix. With hits only, P13 is not covered; say so in §7.

### S6. A concurrent definition can slip between the check and the publish

- **Where:** §4.1 line 59; §4.2 line 79.
- **What is wrong.**
  - The definition hook runs before insertion and outside `world_counter_lock` (`gf.c:2267-2300`). It checks `_OVR_INDEX` without a lock.
  - On thread B, an owner's override is checked against an index that does not yet hold the member. Thread A, in `g`, fixed the member at world w and indexes it afterwards.
  - The override is accepted after the fix, and is caught only at the next `check_overrides` checkpoint.
  - It predates W-40, but W-40 moves fixing into compilation on any thread.
- **Fix.**
  - Make `_OVR_INDEX` copy-on-write.
  - Count definitions in progress between the hook's `after = false` and `after = true` calls, under `_LOCK`, taken blocking on the hook's side.
  - In `g`, publish only if that count is 0 and `get_world_counter()` is still `w` after publishing; otherwise retract (CAS) and return "undecided".

### S7. T-28 keeps the load-order failure for a member's own declaration

- **Where:** §4.2 line 84 ("L-23 is fixed with it"); §6 question 3.
- **What is wrong.**
  - Decision 63 (traits §4.7, `traits.md:463`) is not built. A member's own declaration is accepted from any package allowed to implement the trait for the type, and from an extension (`traits.md:1514`; `_declared_for`, `implement.jl:795-800`; traits `:1193-1194` allow an implementation in an extension).
  - With L-23 fixed, D's extension on `MyTPkg` declaring `@implement X S{MyT}` is refused when an image folding `S{MyT}` was validated first. Otherwise it is accepted. Extensions load after that validation (`loading.jl:2226-2229`).
- **Fix.** Make retiring T-28 (only the parameter type's owner, in that package) a prerequisite of W-40, with L-23. Or name the gap in §8 as a deviation.

### S8. §4.2's "what does not change" contradicts its own one-function rule

- **Where:** §4.2 lines 86-90 against line 79 and §9 line 163.
- **What is wrong.**
  - The list says the run-time path and the untyped table do not change. But `_conf_family_slow` must return the registry's entry rather than `_conformance_slow`'s world-`w` builder (`implement.jl:864-865`, `entry.jl:144-163`). And `_umiss` must use the one function (`untyped.jl:70-80`).
  - In an older world, the run-time path today returns a builder decided in `w` while storing one decided in the latest world.
- **Fix.**
  - Strike the two items.
  - State that the run-time path in any world fixes from the latest world and builds with the registry's entry.

### S9. §8 lacks the deviations the note itself creates

- **Where:** §8, §10 lines 194-195.
- **What is wrong.**
  - Question 2 (abstract declared arguments, `_has_op_method`, `implement.jl:336-349`) becomes a G2 deviation once W-40 is built. §10 says so; §8 lists no F- row.
  - S2's residual gap, if it is kept, needs an L- row.
- **Fix.** Add both rows to §8.

---

## Consider

- **C1. `--strip-ir` empties edges** (`staticdata.c:2606-2607`). Records are lost, and the folded code is kept unchecked. Refuse folds while generating output with `strip_ir`, or keep the records. Still open from the first review (C1).
- **C2. Assert `!in_pure_callback` before calling `g`.** `invoke_in_world` ignores the world there (`builtins.c:903-907`).
- **C3. Precompile `g`'s call tree in TraitWorld's image.** At nested depth 3 it is interpreted (`gf.c:453-454`), and the member check interpreted inside inference is slow. Still open from the first review (C4).
- **C4. `rests_on_facts` never sees a record.** `PlainRTInterp` is not a `NativeInterpreter`, so it never folds and its CodeInstances hold no records. The case is harmless, but §4.1 should not present it as needed.
- **C5. §4.1 still says "`Type{X}` of a concrete `X`".** Traits are abstract types. Write `Const` or `isconstType` (first review C6).
- **C6. Memo semantics.** Name which outcomes are memoised: non-conformance per world, as the first review's S8 asked; "cannot fold" per session; "undecided" never.
- **C7. Stack depth.** Deep inference plus `g` plus nested inference plus JIT runs on the caller's task stack. A `StackOverflowError` caught in `g` is fine; one in nested C codegen may not be. Test on a spawned task.
- **C8. §7 gaps:**
  - a builder over 256 bytes (N1);
  - the re-entrancy test must assert which CodeInstance the global cache holds afterwards (S2);
  - load with a concurrent slow path on another thread (S3);
  - an override defined on thread B while thread A compiles (S6);
  - a member declaration in D's extension before and after P's image (S7);
  - `@snoop_invalidations` with a failing record;
  - `--strip-ir`;
  - a debug build for the task-switch assertion (`task.c:438`).

---

**Addendum (2026-10-27, filing).** Reviewed by an Opus agent, fresh eyes, source only. N1 checked: `MAX_INLINE_CONST_SIZE = 256` (`julia-1.13/Compiler/src/utilities.jl:30`). Acted on: the note's §11, revision 3.
