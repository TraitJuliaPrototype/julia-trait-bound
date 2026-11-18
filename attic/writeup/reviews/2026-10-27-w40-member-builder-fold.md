# Review: W-40 design note (`writeup/plans/2026-10-26-w40-member-builder-fold.md`)

Reviewer: fresh eyes, source read only, nothing run (2026-10-27). Sources: julia-1.13 at fa4e7f5798, TraitWorld `src/` as checked out.

## Verdict

1. The goal can be met, and §5's main argument holds: across sessions something has to fix the member at load, and edges cannot do that. But the mechanism as written is not safe to build.
2. Running library code inside inference while holding 1.13's global inference lock, with locks and I/O allowed, can deadlock. The fold record would crash two edge walkers the note does not list. And the check reads the wrong world.
3. G2 "in every load order" fails for an override placed in a package extension, and question 3's remedy does not fix it. Fix the four blockers and the should-fix list before building.

---

## Blockers

### B1. `g` runs under the global inference lock, with blocking locks and I/O: deadlock

- **Where:** §4.1 "Inference calls `g(args...)` in the inference world, outside a pure callback, as concrete evaluation calls a function"; §4.2 `_member_fold`.
- **What is wrong.**
  - Concrete evaluation does run inside a pure callback. `Core._call_in_world_total` sets `in_pure_callback = 1` (`src/builtins.c:922`). The note's comparison is false, and so is its premise that this path is proven.
  - In 1.13 every JIT inference holds `jl_typeinf_lock` (`src/gf.c:496`, reintroduced upstream as "temporary", julia-1.13 c0565dfbda, #60689).
  - The member check takes TraitWorld's `_LOCK`, a `ReentrantLock`. `witness` holds it across `_witness`, which runs inference, JIT compilation of `generic_rec`/predicate methods, and `@warn` (`implement.jl:324-334`, `377-410`).
  - **Counterexample (two threads).** Thread A JIT-compiles a typed caller. It holds `jl_typeinf_lock`, enters `g`, reaches `witness`, and waits on `_LOCK`. Thread B is on the run-time slow path. It holds `_LOCK` inside `witness` and makes a first call of a generic implementation's `generic_rec` method. That call is JIT-compiled, so B waits on `jl_typeinf_lock`. This is an ABBA deadlock.
  - **Counterexample (one thread).** Waiting on a contended `ReentrantLock`, or a `@warn` write to a TTY, switches task while `jl_typeinf_lock` is held. Debug builds assert against this (`src/task.c:438`, "none of these locks should be held across a task switch"). In release builds, another task on the same thread that needs inference spins in `_jl_mutex_wait` (`src/threading.c:964-990`) and never yields.
  - User code runs there too. `_member_problems` → `_param_bound_problems` → `witness` evaluates generic implementations' predicates (`implement.jl:399`), which can do I/O, yield, or `eval`.
- **Fix.**
  - `g` must never block or yield while called from inference.
  - The registry and the check's caches (`_WITNESS`, `_MEMBERS_CHECKED`, `_PWITNESS`) move to copy-on-write with `@atomicreplace`, as `DYNAMIC_CANDIDATES` does (`facts.jl:520-542`).
  - Any remaining lock is taken with `trylock`. On failure, `g` returns "not folded" and caches nothing.
  - Warnings are queued and printed later, on the run-time path.
  - Generic predicates are not evaluated from inside inference: there, a member whose bound check needs one is not folded.
  - State in §4.1 that `fold_call` is not concrete evaluation, and list what `g` may do.

### B2. The fold record crashes edge walkers that §9 does not list

- **Where:** §4.1 "adds a record `(g, args, v)` to the frame's edges"; §9 names only `reinfer.jl` and `rests_on_facts`.
- **What is wrong.**
  - `ForwardToBackedgeIterator` (`Compiler/src/typeinfer.jl:732-766`) reads any item that is not `Int`/`Method`/`Binding`/`CodeInstance`/`MethodInstance` as an invoke signature. It then takes `edges[i+1]` as the callee and asserts `callee::MethodInstance`.
  - `store_backedges` (`typeinfer.jl:777-804`) runs this for every new CodeInstance. A record at the end of `edges` raises a `BoundsError`. A record followed by a CodeInstance becomes a corrupt backedge, with the record as `invokesig`. Either way, every fold fails inside inference ("Internal error during type inference").
  - `verify_method` has the same misparse (`Compiler/src/reinfer.jl:254-266`, `meth = callee::Method`). So every image holding a fold fails to load.
  - `rests_on_facts` returns `false` on unknown items (`facts.jl:459`). That is safe but must be changed deliberately.
  - The C walkers tolerate the record, because they skip anything that is not a CodeInstance or compare identity: `gf.c:2025-2032`, `gf.c:2434-2438`, `codegen.cpp:3359`, `staticdata.c`. So no C change is needed.
- **Fix.**
  - Define a dedicated record type in `Compiler`, e.g. `struct FoldEdge; g; args::SimpleVector; v; end`.
  - Add a skip (`i += 1`) in `ForwardToBackedgeIterator`, a case in `verify_method`'s non-CodeInstance loop, and a case in `rests_on_facts`.
  - Decide what `_jl_debug_method_invalidation` logs for it (`reinfer.jl:279-282`), because SnoopCompile parses that log.
  - Add `typeinfer.jl` to §9.

### B3. The world: the check reads the latest world, and an older inference world may fix the member

- **Where:** §4.2 "The world … The check takes the world from the task (`Base.tls_world_age()`)".
- **What is wrong.**
  - Inside inference the task's world is `jl_typeinf_world`, the compiler's (`gf.c:487`), not the inference world. `g` must be called with `Core._call_in_world(get_inference_world(interp), g, args...)`; the note does not say so.
  - Even then, the check reads the latest world in many places:
    - `_check_member` → `_latest` (`implement.jl:917`);
    - `_check_kw_at`'s default `world = Base.get_world_counter()`, used by `conformance_problems` and `_rep_of` (`compiler.jl:66`, `implement.jl:269`, `641`);
    - `methods(conformance)` in `_declared_traits`;
    - `Base._which` in `_declared_for`/`_has_conformance_method`;
    - `invokelatest` in `_family_records` (`hooks.jl:127`).
  - `_DECISION_WORLD` is a `ScopedValue`, so `g` inherits the scope of whatever code triggered the JIT compile. That code may be a run-time slow path in another world (`compiler.jl:103-111`).
  - **Counterexample (older world).**
    1. `MyT`'s owner defines an override `op(::S{MyT})` at world w2, before any use. traits §4.7 allows this.
    2. A task pinned at w1 < w2 (`invoke_in_world`, or a task still running in its spawn world) compiles a typed caller of `S{MyT}`.
    3. If the check runs in w1 as §4.2 asks, it sees no override and fixes a builder with `op` served by the default. The registry is world-independent, so latest-world code then uses that builder.
    4. `_index_builder!` indexes `op` as default-served. The next `check_overrides` checkpoint raises `ImplementError` against an override that came before the first use.
  - Today's slow path fixes from the latest world (`_latest(_family_builder)`, `implement.jl:865`). The note's change makes this worse.
- **Fix.**
  - Fix a member only when the inference world equals `get_world_counter()`, or at load in the validation world, which is the latest.
  - In any other world, fold registry hits only.
  - Inside `g`, set `with(_DECISION_WORLD => w)` explicitly.
  - Before building, audit every world read in the check; list them in the note.

### B4. G2 "in every load order" fails; question 3's remedy misses package extensions and image-free loads

- **Where:** §4.3 "fixed in every session where code with its builder can run"; §6 question 3.
- **What is wrong.**
  - Order of loading in 1.13 (`base/loading.jl`):
    - The dependent image is validated, and its folds would be evaluated, inside `_include_from_serialized` (line 1344).
    - Its modules' `__init__` runs after that (lines 1453-1460).
    - Package callbacks and extension loading for its newly loaded dependencies run later still, in the `finally` block after `_include_from_serialized(pkg, …)` (lines 2226-2229).
  - **Counterexample.**
    1. `MyTPkg` puts its override for member `S{MyT}` in an extension on `D`. This is the common Julia pattern, and the owner's code.
    2. Loading `P`, which compiled code for `S{MyT}`, loads `D` and `MyTPkg`, then validates `P`. Validation fixes the member. Then the extension loads, and its override is left inactive by the image hook.
    3. Without `P`, or with `--compiled-modules=no` or `--pkgimages=no`, the override is accepted.
    - So the member's implementation depends on whether an unrelated package's image exists.
  - Question 3's claim "the override is always loaded first, in every load order" is false for extensions.
- **Fix.**
  - Either count the owner's extensions as part of its package and run fold evaluation after extension callbacks, which needs a deferred, post-load pass rather than evaluation inside `verify_method`;
  - or restate G2 with this exception and put it to the user in question 3.
  - Add a load-order test with an extension (§7).

---

## Should fix

### S1. Folds made during constant propagation lose their record

- **Where:** §4.1 "adds a record to the frame's edges".
- **What is wrong.**
  - `ConstCallInfo` adds only the generic call's edges (`stmtinfo.jl:211`). A const-prop frame's own edges are not merged into the caller. The same holds for semi-concrete results (`SemiConcreteResult`).
  - Suppose `fold_call` folds only in a const-prop frame, because the generic specialization does not know an argument. Then the caller inlines `Const(v)` with no record. The image keeps it with no check at load.
  - TraitWorld's planned use folds in the generic `conformance(As{X}, S{MyT})` instance, so it is covered transitively through the CodeInstance edge. `fold_call` is a general primitive, though.
- **Fix.** Fold only in frames whose edges are kept: a cached `InferenceState`, not const-prop, not irinterp, not volatile. In other frames return "not folded". State this as a rule of the primitive.

### S2. "Not folded" outcomes are not recorded, so code stays slow for good

- **Where:** §4.1 (a record only for a value `v`); §5 "edges are not needed in a session".
- **What is wrong.** Code compiled when `g` returned `nothing` holds the run-time path for good, in the session and in images. That happens:
  - when the call is re-entrant;
  - when the member does not conform at compile time and conforms later, e.g. a method defined in the REPL before the call;
  - when the inference world is old (B3's fix);
  - when the check's own nested inference fills the plain cache. `_check_kw_at` uses the plain cache on purpose (`compiler.jl:66-69`), so those CodeInstances serve program code.
  
  §5 is right that edges are not needed for correctness. It is wrong that the decided cost ("its typed calls then cost what a declared type's do") follows.
- **Fix.**
  - Record every outcome, `nothing` included, and evaluate it again at load: an image's unfolded code is discarded once the member is fixed.
  - In a session, accept the gap and name it as a deviation, or give a `nothing` fold a revalidation trigger. A dedicated binding that the slow path redefines is one option, though it is a top-level effect.

### S3. Re-entrancy can poison TraitWorld's caches, not only return `nothing`

- **Where:** §4.1 rules ("a re-entrant call returns `nothing`").
- **What is wrong.**
  - The note does not say what the guard is keyed on. A global per-member flag also returns `nothing` to another thread's inference, which leaves that caller slow for good.
  - `_LOCK` is reentrant. Suppose JIT compilation is triggered inside `witness`'s critical section (`implement.jl:324-334`), for example by a predicate's first call in an older decision world. Then a nested `g` can call `witness` → `_flush_if_stale!` (`implement.jl:309-316`) with the inference world. That empties `_WITNESS` and retags it. The outer call then stores its old-world witness under the new world's tag. Latest-world run-time paths read the wrong witness, which breaks G1 in a session.
  - `_witness` for a family member depends on inference (`implement.jl:386-387` → `conformance_problems` → `infer_return_type`). A nested inference that degrades precision under the guard can cache `nothing` (non-conforming) in `_WITNESS`. Every path then sees `NOTRAIT`.
- **Fix.**
  - Key the guard per task and per `(X, U)`.
  - A nested evaluation, or any evaluation that observed a guard, commits nothing: not `_WITNESS`, not `_MEMBERS_CHECKED`, not the registry.
  - Compute outside locks and publish by CAS (B1).
  - Add a test where an operation's default calls a bounded function on the same member, and assert the witness cache afterwards.

### S4. "One function, one registry" is not today's code: three builders, and the last writer wins

- **Where:** §3 item 2, §4.2, §5 "by construction".
- **What is wrong.**
  - A family member's builder is computed in three places, possibly in three worlds:
    - `_conf_family_slow` returns `_conformance_slow(X, u)`'s builder: the caller's world, `_SLOW` cache (`entry.jl:144-163`, `implement.jl:864`);
    - it stores `_latest(_family_builder, X, U)` in the registry: latest world (`implement.jl:865`);
    - the untyped table builds its own with `_builder_for` in world `w`, and neither reads nor writes the registry (`untyped.jl:70-71`).
  - The registry insert overwrites unconditionally (`implement.jl:867-871`). With folds, a racing run-time path in another world can replace the builder already folded into code.
  - The untyped table's first use fixes nothing in the registry and indexes nothing. An override after an untyped-only use is accepted, while folded callers later fix another builder.
  - §4.2's "What does not change: the untyped callers' table" is therefore wrong.
- **Fix.**
  - One function, `_member_fold`, used by the fold, by `_conf_family_slow`, which returns `reg[][U](u)`, and by `_umiss`.
  - Insert first-writer-wins, and return the entry that won.

### S5. §5 relies on refusals that L-23 says do not happen

- **Where:** §5 "A later definition … is either refused … or does not change the member's builder".
- **What is wrong.**
  - A member's own declaration after its first use is not refused (lowering L-23, `lowering.md:760`; `_declared_for` is false for the family method, `implement.jl:795-800`).
  - Callers' edges on the family method then recompile them against the declared builder. Values built with the folded builder stay live. So one session holds two implementations of one member.
  - Under W-40 the window grows, because compiling and loading are now uses.
- **Fix.** Make retiring L-23 (refusing a member's declaration once the member is in the registry, in the definition hook and the image hook) a prerequisite of W-40, and say so in §5.

### S6. Evaluation at load: placement, locks and state are unspecified

- **Where:** §4.1 "At load"; §5 costs.
- **Facts (1.13).**
  - `insert_backedges` runs in the compiler's world through `jl_call_in_typeinf_world` (`gf.c:584-595`; `reinfer.jl:657-660`), with `require_lock` held (`loading.jl:1322-1345`). It holds neither the inference lock nor `world_counter_lock`.
  - The image's methods are already active (`staticdata.c:4461-4474`).
  - `validation_world` is read per root CodeInstance (`reinfer.jl:85`).
  - The restored modules' `__init__`, TraitWorld's package callback (`_bump!`, `_report_refused_at_load`, `TraitWorld.jl:46-54`) and extensions all run after it.
  - So library code and inference may run there. `g` must be called with `Core._call_in_world(validation_world, …)` inside `try`/`catch`.
- **What is wrong or missing.**
  - Evaluating mid-walk (Tarjan, `reinfer.jl:162-390`) runs code whose CodeInstances in the image are still pending (`max_world` sentinel, `staticdata.c:1759-1764`). The runtime ignores them and compiles fresh copies, which is load-time cost.
  - The same record is evaluated once per CodeInstance, not once per member.
  - `g` sees TraitWorld's state before the image's `__init__` and before the package callback. The note must say this is enough.
- **Dependents.** These are handled if the record sets `maxworld = 0` in the CodeInstance's own (non-CodeInstance) edge phase:
  - Tarjan propagates it to the image's callers through CodeInstance edges (`reinfer.jl:350-381`);
  - later images that name the CodeInstance see `max_world = 0` and fail;
  - earlier images cannot depend on it.
- **Fix.**
  - Add a pre-pass in `insert_backedges`: collect the image's distinct fold records, evaluate each once, and keep the results in an `IdDict`. The walk then only reads that table.
  - State the TraitWorld state `g` relies on.

### S7. Who folds: reflection, tools, `return_type` and the `Dynamic` split become uses

- **Where:** §4.1 "in either mode"; §4.2 "At a `Dynamic` family member … each branch folds".
- **What is wrong.**
  - Every `AbstractInterpreter` reaches `abstract_call_known`: `code_typed`, `@code_warntype`, Cthulhu, JET, GPUCompiler, Enzyme, TraitWorld's `_CheckOwner` checks, and `PlainRTInterp` behind `return_type`/`promote_op`/empty `map`s.
  - Each would fix members, and so refuse owners' later overrides. Reflection gains a semantic side effect.
  - `abstract_split_call` infers each registered candidate (`facts.jl:686-714`). Compiling one `Dynamic` call site would fix every candidate member, chosen by registration order and up to `MAX_FACT_SPLITS`.
  - Archetype members, from definition checks at archetype keys, could land in a declaring package's registry and its image.
- **Fix.**
  - Add `may_fold(interp)`: true for the native JIT and the facts owner only. Elsewhere, fold registry hits without fixing.
  - Split branches: hits only.
  - Decide explicitly whether reflection is a use, and put it to the user if it is.

### S8. A non-conforming member is checked again at every inference

- **Where:** §4.2 "A member that does not conform is not folded".
- **What is wrong.**
  - `_MEMBERS_CHECKED` keeps successes only (`implement.jl:907-920`). Every caller specialization, every owner and every split branch reruns the full check inside inference: method lookups plus `infer_return_type` per operation.
  - It also reruns at every load, and it prints `@warn` for abstract parts (`implement.jl:902-903`) during inference and during image validation.
- **Fix.**
  - Cache failures per world, so a later definition can still make the member conform at its call.
  - Defer warnings to the run-time path.

### S9. Question 2 is a G2 deviation the moment W-40 is built

- **Where:** §5 "G2 under evaluation at load"; §6 question 2.
- **What is wrong.**
  - With `_has_op_method` at abstract declared arguments (`implement.jl:336-348`, `conformance_problems` `256-262`), a non-stakeholder's method changes the member's builder. Folded image code is then discarded at load by an unrelated package.
  - That contradicts facts §11 ("which code is kept … depends on the method table, not on the order of unrelated loads") and G2.
  - Deferring question 2 is fine, but the note's §8 does not add the deviation.
- **Fix.** Add an F- row (G2 across images for folds at abstract declared arguments) to §8's list, and link question 2's open issue to it.

---

## Consider

- **C1. `--strip-ir` drops the records.** `staticdata.c:2606-2607` empties `edges`. An image built with stripped IR keeps folded code that is never checked at load. Refuse folds when `jl_options.strip_ir` is set while generating output, or keep `FoldEdge`s when stripping.
- **C2. System images skip validation** (PackageCompiler, non-trimmed juliac). This is acceptable, because the whole heap, registries included, is saved. Say so in compiler §2.9.
- **C3. Do not rely on the global inference lock.** It is "temporary" upstream. B1's fix must hold with concurrent inference too: several threads in `g` at once.
- **C4. Nested-inference depth.** C-entered inference returns `NULL` beyond depth 3 (`gf.c:454`). `g`'s own first compile inside inference may then be interpreted. Precompile `_member_fold`'s call tree in TraitWorld's image.
- **C5. Egality of `v`.** Load-time validity rests on `Builder` being an immutable tree of bits and singletons (`Slot`, `Impl{D}`, `Generic{…}` with a gensym `k` fixed by D's image). Assert this in `_member_fold`: return `nothing` for anything else. Otherwise a stray mutable field makes every load discard the code silently.
- **C6. The folding rule names the wrong kind of type.** Traits are abstract types (`trait.jl:259`). "`Type{X}` of a concrete `X`" excludes them. Write `Const` or `isconstType`.
- **C7. Backdating.** A fold adds no world bound, so a folded CodeInstance may be valid before the world in which the member was fixed. This is harmless while the registry is world-independent, but state it. Or bound it with `update_valid_age!(sv, WorldRange(world, typemax(UInt)))`, as `facts_plain_return_type` does with its bounds (`facts.jl:494`).
- **C8. Load-time cost.** The 34 ms per member noted in `_family_conformance_methods`'s docstring would now be paid per member per load, for every member any loaded image compiled for, whether or not it is ever called. Measure the worst case, many members missing from the registry, not only "several".
- **C9. The build.** No C change is needed (B2). A system image rebuild suffices, and then every package image is rebuilt. State that existing images become invalid.

---

## Answers to the five questions, in brief

1. **Soundness.**
   - In a session, G1 holds once S4 (one builder, first writer wins), S5 (L-23) and B3 (the world) are fixed.
   - Across sessions it holds, except for const-prop folds (S1) and stripped IR (C1).
   - It fails in every load order (B4), in an older world (B3), with threads (B1 deadlock, S4 race) and under re-entrancy (S3 cache poisoning; S2 slow code for good).
   - Speculative inference has a semantic side effect (S7).
   - A non-conforming member is correct but costly (S8).
   - A builder holding session pointers is correct: not folded, not recorded.
   - Precompiling a package that does not declare the family is correct. The registry change is lost, as intended, so the member is checked again at load.
2. **§5.** Edges are not needed for correctness in a session, given S5; they are needed for the cost outcome (S2). Edges are not enough across sessions: right. "Edges would weaken G2" is true only for the abstract-argument reads of question 2. Load-time evaluation is feasible in 1.13 under S6's conditions. Dependents are discarded correctly through Tarjan.
3. **Feasibility.**
   - Running library code in `abstract_call_known` is possible: `facts_plain_return_type` already runs nested inference there (`facts.jl:483`). It is unsafe as specified (B1, B3, S7).
   - A record in `CodeInstance.edges` is tolerated by C. In Julia it needs a dedicated type and changes in `typeinfer.jl` (`ForwardToBackedgeIterator`), `reinfer.jl` (`verify_method`, `insert_backedges` pre-pass) and `facts.jl` (`rests_on_facts`), besides the new case in `abstractinterpretation.jl`, a `FoldCallInfo` in `stmtinfo.jl`/`facts.jl` with `add_edges_impl`, and frame filtering (S1).
   - No C change.
4. **A simpler design.**
   - None reaches the decided outcome ("compiling a caller is a use"). Hit-only folding, a pure registry lookup that even concrete evaluation could do, needs no record for entries kept in the declaring package's image: that registry is identical in every session that loads the image. But it leaves callers compiled before the first call slow, which is move 2's case.
   - The note's design is the minimum. Make `g` lock-free, non-yielding and latest-world only, rather than looking for another mechanism.
5. **§7 gaps.** See below.

## Gaps in §7

- **Threads.** Under 1.13's lock, "two tasks compiling callers at once" runs serially and proves nothing. Instead, test thread A compiling callers of a member while thread B runs the run-time slow path for a member with a generic predicate's first call. Run under a debug build, so `task.c:438` fires on a task switch while the inference lock is held.
- **An older world.** `invoke_in_world(old, f, ::S{MyT})` with an override defined in between (B3).
- **Load order.** P (folding) before and after: R (a method at an abstract declared argument, question 2), and `MyTPkg`'s extension override (B4). Compare semantics with `--pkgimages=no` and `--compiled-modules=no`.
- **Re-entrancy.** Assert the state of `_WITNESS`/`_MEMBERS_CHECKED` afterwards, and that the operation's plain-cache CodeInstances are not left unfolded (S2, S3).
- **Reflection and tools.** `code_typed`, `Base.return_types` and `return_type` on an empty `map` of members: is the member fixed? (S7) A `Dynamic` split with several registered candidates: which are fixed?
- **Conforming later.** Compile before the member conforms, define the method, call: is the code ever folded? (S2)
- **Const-prop.** A `fold_call` reachable only through constant propagation: no folded constant without a record (S1).
- **Image mechanics.** A record that fails at load with `jl_debug_method_invalidation` on (SnoopCompile's `@snoop_invalidations`), and an image built with `--strip-ir` (C1).
- **Costs.** Inference time for a non-conforming member compiled by many callers (S8). Load time with many registry misses, not "several" (C8).
- **G1 race.** A first call on thread A and compilation on thread B at once: one builder in the registry, egal to the folded one (S4).
- **The experiment row.** E-167 is free. Its row should also name the result that would stop W-40: any deadlock or task-switch assertion in the thread test.

---

**Addendum (2026-10-27, filing).** Reviewed by an Opus agent, fresh eyes, source only. B1 checked by the session that commissioned it: inference holds `jl_typeinf_lock` and runs in the compiler world (`julia-1.13/src/gf.c:480`–`496`), and concrete evaluation runs as a pure callback (`src/builtins.c:912`–`935`). Acted on: the note is set to "revision needed" with the blockers and the directions (its §10); decision 63 excludes package extensions (B4); W-40 is not built.
