# Review: the store of the facts-keyed cache, and its vehicle (W-66, step 4)

Reviewer: fresh eyes (Opus 5.5), 2026-10-28. Files read; nothing run. Reviewed:
- the proposal `writeup/plans/2026-10-28-facts-cache-store.md`, at design commit 8ffa476;
- the cache's note `writeup/plans/2026-10-27-facts-keyed-cache.md` (revision 2, §5b) and its review `writeup/reviews/2026-10-27-facts-keyed-cache.md`;
- `experiments/w66/README.md` (E-193, E-195 parts 1–4, E-199, E-201, E-202, E-203), `experiments/w66/Fingerprints.jl`, `experiments/w66/fp_scale.jl`; `experiments/ttfx/README.md` (E-180, E-188, E-194);
- `writeup/record/incremental-precedents-research-2026-10-27.md`;
- `writeup/reference/facts.md` §2, §4, §6.4, §7.1, §9–§12; `writeup/reference/compiler.md` §1.4, §2.3–§2.10, §4.3, §4.4, §5.3, §6.2;
- julia-1.13 3e3da4e584: `Compiler/src/typeinfer.jl`, `Compiler/src/reinfer.jl`, `Compiler/src/facts.jl`, `Compiler/src/cicache.jl`, `Compiler/src/utilities.jl`, `Compiler/src/ssair/inlining.jl`, `src/gf.c`, `base/loading.jl`, `stdlib/Serialization/src/Serialization.jl`;
- `writeup/record/performance-explorations.md`; `writeup/record/decisions.md` §5.

---

## Summary

- **The direction holds.** Code compiled by facts is the only code whose validity can be stated per CodeInstance across environments. Storing its inferred code is the right first layer, and the proposal's §4 names the right risks.
- **The store cannot be built as specified.** Three things block it:
  - **`Serialization` is not a vehicle for compiled code** (B1). It writes a Method by content with a number local to the writing process. When it reads one back in a fresh session, it makes a new Method, and inserts it into the method table if no method has that signature. MethodInstances and CodeInstances come back as copies that no cache knows. Julia's JIT queue then caches such a copy without validation.
  - **The fingerprints do not fix what optimized IR embeds** (B2). Values of `const` bindings are folded into the code: compile-time preferences, values computed from a dependency, artifact paths. F1–F3 hash names and layouts, not values. "Bindings as today" checks a binding's partition, which fixes the value only within one image's build id. Objects with identity (constants, `rettype_const`, split tables) lose it in a copy.
  - **There is nothing to write at exit** (B3). A facts CodeInstance's inferred code is discarded once it is compiled, unless it can be inlined. E-195 found the same.
- **Julia already has the lookup's hard half** (M1). `verify_method` in `reinfer.jl` validates a graph of CodeInstances loaded from elsewhere:
  - recursive groups as strongly connected components;
  - world ranges, bindings, folds, `invoke` signatures, deleted methods;
  - insertion into the cache and the backedges.
  
  It is exact for dispatch at every edge, plain edges included, and cheap on facts edges. With it, fingerprints are needed only for content, and F2's walk over all stakeholders' methods and the candidate index are not needed for validity. That changes the decided form of F2, so it is for the user.
- **The hook inside `typeinf_edge` is the riskiest place** (M2). Folds evaluated with `AtLoad()` inside inference break compiler §4.4's rule. An eager insertion after each package load needs no hook in inference: it is what image loading does. E-c already does it, so E-c can decide whether a hook is needed.
- **The criterion for soundness is G1's, not syntactic equality** (M3). Inference itself depends on history. Optimized IR is what must be stored, with every object it names relinked.
- **The gain bound is not established** (M6). 7.29 s is a sum of overlapping per-CodeInstance times over all facts code of C/p. It includes code that names the session. The store's own costs are not subtracted. The machine-code vehicle reached C/p 6.1 s (E-180); an inferred-code store keeps code generation, so its ceiling is lower. That comparison belongs in the proposal.
- **The plan needs a soundness step by construction before E-c** (M6), with B2's cases.

---

## Findings

### B1. `Serialization` cannot carry the stored code (blocking)

**The proposal** (§3.1, line 27): "the inferred code, uncompressed (`CodeInfo`), with its edges as signatures and method references by path, as `Serialization` writes them."

**What `Serialization` writes:**
- **A Method by content, not by path.** It writes `object_number(s, meth)`, a counter local to the writing process (`Serialization.jl:410–421`, `:436–439`), and then the whole method: module, name, signature, source, generator.
- **Reading it in another session makes a new Method** (`:1041–1048`, `jl_new_method_uninit`). The number is unknown there. If no method with that signature exists in the world, the copy **is inserted into the method table** (`:1132–1133`, `jl_method_table_insert`; the code's own comment says "quite sketchy?"). So reading an entry whose method was deleted or renamed in this session defines a method. That is a definition by the store, before any validation, and it breaks G1.
- **A MethodInstance comes back uninterned** (`:1147–1148`, `jl_new_method_instance_uninit`). It is not the session's specialization, so no cache or backedge finds it.
- **A CodeInstance and a `Core.Binding` have no handler.** They go through `serialize_any` (`:694`), field by field. A detached binding then passes validation: `verify_method` treats a binding that is not invalidated and has no partitions as valid in every world (`reinfer.jl:247–260`).

**Why it matters beyond the edges.** Optimized IR names CodeInstances in its statements, not only in its edges:
- `:invoke` statements carry a `CodeInstance` (`inlining.jl:40–41`, `:629`), also one of another owner (compiler §2.7).
- The JIT queue follows them (`collectinvokes!`, `typeinfer.jl:1533` ff.). A callee that is not in its MethodInstance's cache is put there without validation (`add_codeinsts_to_jit!`, `typeinfer.jl:1640–1644`). A copied CodeInstance carries its recorded world range and no backedges. It would then run in every later world, and nothing would invalidate it.

**Fix.** A writer and reader of the store's own, with a table of external references by stable name, as the research's take from rustc says (`incremental-precedents-research-2026-10-27.md:47`, `:62`):
- a method by module path, name and signature, checked against its F1;
- a MethodInstance interned in this session (`specialize_method`);
- a CodeInstance by its MethodInstance and owner, resolved to a CodeInstance of this session (a store entry, or one already valid);
- a binding by module and name (`convert(Core.Binding, GlobalRef(…))`);
- a type by path;
- constants only where they have no identity (B2).

Anything else makes the entry not storable. Reading must have no side effect before validation: the note's "the store holds evidence only" (note line 115).

### B2. The fingerprints do not fix the values and objects that optimized IR embeds (blocking)

**The proposal** (§1, line 11): "Folds and bindings are checked as today". The note's §5b says the same (line 106).

**Values of `const` bindings.**
- Inference folds a constant binding's value into the code: an `isbits` value inline, a branch on it removed.
- F1 hashes the lowered code with global references by name (`Fingerprints.jl:23–29`). F3 hashes the layouts of the types a reference names (`:114–118`). Neither hashes a value.
- "As today" means the binding's partition (`reinfer.jl:247–260`). Inside one package image the value is fixed by the image's build id. Across rebuilds and environments, which is what the fingerprints are for, nothing fixes it.
- Cases where the source, the lowered code and the layouts are the same and the value differs:
  - **compile-time preferences** (`@load_preference` in a `const`). Julia keys each package image on its preferences (`base/loading.jl:3334–3351`, `compilecache_path`). A store shared across environments would take another environment's preference;
  - `const X = f(Dep)`, `pkgversion(Dep)`, `isdefined(Dep, :x)`: the cases the first review's B2 listed, which the closure's build ids covered and the fingerprints no longer cover;
  - artifact and library paths computed at precompile time, which differ per depot.
- E-195 did not test this: its cases change macros, layouts, methods and callees.

**Objects with identity.**
- A mutable type whose fields are all `const` counts as an inlineable constant (`utilities.jl:43–52`). Concrete evaluation can return a global's object as `rettype_const`. `Const` types in `ssavaluetypes` are materialized by codegen.
- The split's fallback embeds its `SplitTable` in the code (`inlining.jl:493`, `:509–511`). Compiler §4.3: "Sites with the same signature share one."
- A copy breaks identity: a write goes to the copy, and a `===` test fails. For folds this fails safe: `fold_holds` compares by `===` (`facts.jl:568–575`), so a fold of an object with identity never holds and the entry misses. For constants in the code it does not fail safe.

**Fix.**
- The entry records every constant binding its code reads, with a hash of its value. A value with identity is relinked through its binding, or the entry is not stored.
- Embedded objects: only values without identity are stored as values. A `SplitTable` is made again at relocation by `split_table(f, args, rt, facts)`. Other objects make the entry not storable.
- Test by construction (M6): a preference, a `const` computed from a dependency, and a constant of a mutable type used for identity only.

### B3. Nothing to write at a session's exit (blocking for §3.2)

**The proposal** (§3.2, line 35): "Written at a session's exit … the session's new facts CodeInstances."

**Why there is nothing.**
- `maybe_compress_codeinfo` returns `nothing` for code that cannot be inlined (`typeinfer.jl:452–465`). Only the precompile mode keeps it (`precompile_keep_ir`).
- The uncompressed code lives in the interpreter's `codegen` dictionary (`typeinfer.jl:175`), which belongs to one compile request.
- E-195 hit the same: "the code witness read facts CodeInstances' inferred code, which is not kept" (`experiments/w66/README.md:61`).

**Fix.** Capture the code when it is made, in `finish!`, beside `jl_push_newly_inferred`, or keep it for the facts owner in a recording session. The memory cost goes into E-a.

### M1. Julia's load-time validation already does the lookup's hard half (major)

**The proposal** (§3.3, §4 items 2 and 3) specifies a new lookup: fingerprints, candidates, folds, edges resolved, cycles inserted together, world bounds. It says "nothing new is needed after insertion" (line 42). It does not say how world ranges are computed or where the backedges are stored.

**What Julia has** (`Compiler/src/reinfer.jl`):
- `verify_method` (`:162`) validates a CodeInstance and, recursively, every CodeInstance it names. It uses Tarjan's algorithm, so a recursive group passes or fails as one (`:160`, `:323–350`). That answers §4 item 2: GHC's #18733 is solved in Julia's own loader.
- Per edge: dispatch at a signature (`verify_call`, `:474`, with fast paths), `invoke` signatures (`verify_invokesig`, `:630`), deleted methods, `Core.Binding` partitions, and `FoldRecord`s (`:242–260`).
- World ranges: it computes them from the matched methods, bounded below by the require world (`:202`).
- On success it inserts the cache entry (`jl_mi_cache_insert`, `:335`) and stores the backedges (`store_backedges`, `:340`). `jl_promote_ci_to_current` then hands the code to ordinary invalidation (`:91`; `src/gf.c:2084`).

**What follows for the design.**
- **Dispatch is checked exactly** for any edge, facts or plain, by comparing the methods that match now with the recorded ones. A new method from outside the stakeholders that changes dispatch fails `verify_call`. So for validity, the candidate index and F2's hash of every stakeholder method are not needed. They become what Lemma O explains: why this check rarely fails.
- **The research already says this:** "Julia is a deep trace for code content (build ids, transitively) and a verifying trace for dispatch" (`incremental-precedents-research-2026-10-27.md:170`). The fingerprints should replace the deep trace for content only.
- **Content then needs:** F1 of the entry's method and of each method its edges name, which is the note's "narrow F2" (note line 111); F3; and B2's values.
- **Cost:** facts edges at concrete signatures mostly take `verify_call`'s fast path (PE-8). F2 as prototyped hashes every Base method of a Base function, because Base is always a stakeholder (`Fingerprints.jl:35`, `:52`), although the store's key already fixes Base. At the least, leave out the system image's methods: the research's "durability classes" (`:100`).

**Fix.** Build the reader so that the relocated CodeInstances, with `max_world` set to the revalidation sentinel, go through `verify_method_graph` and `jl_promote_ci_to_current`. Keep the fingerprints for content. Replacing F2's dispatch half by Julia's check changes the form decided on 2026-10-27 (`decisions.md` §5), so it goes to the user (open issues §1).

### M2. The hook's place: inside `typeinf_edge`, or after each load (major)

**The proposal** (§3.3, line 40) puts the lookup at a cache miss in `typeinf_ext` and `typeinf_edge`. §4 item 3 asks whether that is safe.

**What breaks inside an inference:**
- **Folds.** Compiler §4.4: "Called from inference, `g` waits for no lock, does not yield or write" (`compiler.md:636`). At load, `g(AtLoad(), …)` is called precisely because there "it may wait for a lock" (`facts.jl:516`). A lookup inside `typeinf_edge` evaluates folds at load inside inference.
- **The stack and the engine.** The lookup must come after `resolve_call_cycle!` returns `false` and after `engine_reserve` (`typeinfer.jl:1088–1110`). It must fill or reject that reservation. A stored closure that contains a MethodInstance on the current stack, or one reserved by another thread, must miss.
- **The world.** `verify_method` validates in the latest world (`reinfer.jl:91`, `get_world_counter()`). An inference in an older world must not take an entry checked only in the latest.
- **Re-entry.** The JIT queue calls `typeinf_ext` for a callee without source (`typeinfer.jl:1625`). The hook would run there too.

**The alternative E-c already contains.** Insert eagerly after each package load: every stored entry whose methods are now all loaded and whose content checks pass, through `verify_method_graph`. This is what image loading does: outside inference, in the latest world, with folds at load as §4.4 intends. It needs no hook in inference. Most of what it needs is Compiler code that exists.
- Its cost is the entries a session does not use. E-180's parts loaded 3,418 entries in 0.45 s, by Julia's native loader.
- A hook is needed only if that cost is too high. Then the lazy index of §3.2 serves the hook.

### M3. What to store, and what "the same" means (major)

**Optimized IR, not unoptimized.**
- Unoptimized inferred code lacks the call information (`stmt_info`) the optimizer needs. Optimizing it again means running abstract interpretation again, which saves little.
- Optimized IR is what `ci.inferred` holds and codegen consumes (`ci_has_source`, `typeinfer.jl:1346–1364`).
- Optimized IR names objects: `:invoke` targets, also of another owner (compiler §2.7); inlined frames in its debug info; split tables; constants (B1, B2). Every one is relinked or the entry is not stored.

**The criterion.** "The same as inference would make in this world" (§4 item 1) is not well defined. Inference depends on history:
- a cached callee whose source was discarded is not inlined unless forced (`typeinfer.jl:1068–1077`);
- a callee just inferred is inlined from its volatile result;
- an inference cycle's members inline each other (compiler §6.2).

G1 is the criterion: the code computes the same, with the same effects. Stored IR meets it when:
- every edge verifies in this world (M1);
- every CodeInstance the IR names is relinked to a valid one of this session with the recorded result (return and exception type, effects, constant result);
- every method whose code was inlined is unchanged (F1);
- every embedded value is the same (B2);
- the flags and the optimizer's parameters are the same (m1).

**Early cutoff.** "A callee that misses makes the caller miss" (line 43) is right for inlined callees and cycles. For a callee called through `:invoke`, the caller depends only on its result. Inferring the callee again and keeping the caller when the result is equal is the early cutoff the note cites as the reason for fingerprints. It is a later refinement; the proposal should say it gives it up for now.

### M4. Entries that name another owner's code (major)

- **The note** keeps an entry only if its callees were compiled by facts, or validates it by the walk (note line 17, the first review's M3). The proposal's §1 drops this condition.
- **Such edges:**
  - edges to `return_type`'s plain answers (owner `:facts_plain_return_type`, facts §7.1 rule 2);
  - edges to plain compiler code (facts §6.4);
  - `:invoke` of a plain CodeInstance (compiler §2.7).
- **The store holds only `:facts`.** So under "no partial insertion" these entries always miss. The alternative is a lookup that infers plainly: `PlainRTInterp` and the `rests_on_facts` walk, unmemoized (C-9). The proposal should say which.
- **E-194 found none in C** (`experiments/ttfx/README.md:436`) and 7 answers in the whole session. Excluding them costs nothing measured.
- **The prototype treats a plain callee's edge as a fact** (`Fingerprints.jl:98–99`). A plain result depends on dispatch at abstract signatures, so its fingerprint is not sound. With M1's check it would be exact.

### M5. E-195's witness is weaker than the proposal's §1 reads (major)

- **The witness** is `Base.code_typed_by_type(mi.specTypes; optimize = true)` (`Fingerprints.jl:131–135`). From the top level, `typeinf_frame` hands only facts methods to the facts interpreter (`typeinfer.jl:1278–1281`). A copy of a Base method compiled by facts is witnessed by **plain** inference in the product setting (compiler §2.3's table).
- Such copies are a large share of entries: half in E-188 (an invalid run), 173 of 1,835 on the system image alone in E-194.
- **Printed text:**
  - the witness and the fingerprints compare `string()` of code and types (`Fingerprints.jl:29`, `:58–59`, `:68`);
  - type printers (compiler §5.3) can print distinct types alike: TraitWorld prints trait objects by bound and key;
  - `show` truncates large literals.
- So "none unsound" holds for what was compared. §4 item 1 rightly says insertion is untested.

**Fix.** Witness with the facts interpreter explicitly (`Compiler.facts_interp`, `cache_mode = :no`). Compare the result by `===` and the IR by a structural hash. Hash fingerprints structurally, with `show_type_plain` where a name is needed.

### M6. The gain's bound, and the experiments' order (major)

**The bound** (§2, lines 18–19):
- 7.29 s is a sum of per-CodeInstance self-times that overlap. E-194 itself says: "C's sum exceeds its session's 11.3 s of compilation, so they give proportions, not totals" (`experiments/ttfx/README.md:442`).
- It covers all 2,506 facts CodeInstances of C/p, including the 671 that name the session and can never be stored.
- C/p is the off-workload session (about 19 s). In C on its workload (10.6 s, E-203) the images already hold most of the code.
- The store's own costs are not subtracted: reading with relocation, fingerprints, validation, compressing for the inliner.
- **The vehicles' ceilings are not compared.** The machine-code vehicle (E-180, environment-keyed, retired) took C/p from 19.4 to 6.1 s (`experiments/ttfx/README.md:319`). An inferred-code store keeps code generation (6.32 s, overlapping), so its ceiling is lower, perhaps half the compile time. The trade, a lower ceiling for reuse across environments, is the user's direction (decisions §5), but the proposal should state it with these numbers. The note's other vehicle, "sections of one image" (note line 49), should get a line in the alternatives with its reason.
- **D gains little** (0.08 s of facts inference), as §2 says. The gain is in facts code over upstream packages (interop), not in idiomatic trait code.

**Cheaper options looked at:**
- **Only `return_type`'s results:** not worth it. C made 7 answers (E-194).
- **Copies of Base methods compiled by facts in an image keyed by the Julia build:** keep-compiled exists (compiler §2.9), and the image never goes stale within a build. But only 173 entries in C (E-194). Worth a line, not a step.
- **Julia's verifying trace for dispatch** (M1): cheaper than F2 and exact.

**The order.** E-a first is right: it is cheap and can stop the work. Changes:
- **E-a:** time inference and optimization of the admitted entries as exclusive wall-clock time. Report what keeping their IR costs in memory (B3). Count the entries that B2 and M4 exclude.
- **E-0, new, before E-c: soundness of insertion by construction** (minutes, toy packages, as E-193). Record in one environment, insert in another, and compare each entry with a fresh facts inference (M5). Cases:
  - B2's three (a preference, a `const` from a dependency, a mutable constant used for identity);
  - a closure renumbered in a callee's module;
  - a generator changed with the same stub;
  - a recursive pair;
  - a pirate loaded before insertion;
  - an inference in an older world.
  
  **Would change the plan:** a case kept whose code differs.
- **E-b:** include the facts on Base functions, and time M1's alternative (relocation and `verify_method_graph`) beside the fingerprints.
- **E-c:** insert through `verify_method_graph` after the loads (M2), and time its parts: reading, relocation, checks, validation, and the code generation that remains. "The results equal" for the workload is too weak a test of soundness: compare per entry, as in E-0.

### m1. The store's key (minor)

- **Flags that change optimized IR:** Julia's `CacheFlags` (check-bounds, inline, optimization level, debug level; `base/loading.jl:1721–1728`). The note's m3 had them; §3.2 has only "build and setting".
- **Coverage and allocation logging:** the stored IR has no instrumentation. `needs_instrumentation` returns early for any owner but `nothing` (`reinfer.jl:128`), so facts code from images is not refused under `--code-coverage` either. That is a gap of today's loader.
- **Module options** read by inference (`infer`, `typeinfer.jl:1084`) are not in the lowered code, so F1 misses them.
- **The setting:** facts §11 and the decision of 2026-10-28 say a facts CodeInstance means the same in both settings, so the setting is not part of an image's key. Keying the store by setting needs its own reason, or the setting goes.

### m2. Precompilation and trimmed builds (minor)

- While a package image is built, inserted entries would enter it. `setindex!` on the cache pushes them to the newly-inferred list (`cicache.jl:14–22`), and an image's code names them. Facts §11 says an image holds code "compiled while the package's image was built". Turn the hook, or the eager insertion, off while generating output, or amend §11.
- A `--trim` build has no facts code (compiler §2.10), so the store is inert there. Say so.

### m3. Generated functions and opaque closures (minor)

- F1 of a generated method hashes `string(m.generator)` (`Fingerprints.jl:27`), the stub's printed form, not the generator's code. A generator's output can depend on more than its own code.
- An opaque closure's Method is in no method table, so it cannot be found by path.
- For the first vehicle: exclude entries whose method, or a callee inlined into them, is generated or makes an opaque closure.

### m4. Names made by lowering (minor)

Closures and keyword bodies are named `#f#12`, numbered per module. Found by name, they are right only if the lowered code that names them is fingerprinted. That holds for the entry's own method (F1) and for inlined callees (F2). State it as an invariant the writer checks: every generated name in the stored IR occurs in the lowered code of a method whose fingerprint the entry records. Methods of anonymous modules are not storable.

### m5. A shared depot (minor)

- Several sessions exit and write at once. E-195's run 3 failed because "a cache file of the shared depot was replaced in between" (`experiments/w66/README.md:82`). Write by atomic rename, one file per entry or under a lock.
- Variants of one key with different fingerprints accumulate. Say how the store is bounded and pruned.

### m6. Inferred code kept uncompressed (minor)

An inserted entry with uncompressed `ci.inferred` keeps every IR alive for the session. Julia discards code that cannot be inlined after codegen. Compress the code that can be inlined against this session's method roots (`jl_compress_ir`), and drop the rest after codegen.

### m7. References the proposal's §6 misses (minor)

- **G1's "why it holds"** (facts §2.1) lists where valid code comes from: compilation, invalidation, images, run-time sites. The store is a new source and needs its line.
- **Facts §10.3's table:** a pirate that breaks a store entry. Silent discard is the note's M5 ("evidence, not contract"). In strict mode an image's broken fact is reported; the table should say whether a store entry's is.
- **Compiler §4.4:** where folds of store entries are evaluated (M2).
- **Facts §11:** what an image may hold (m2).

### m8. A citation (minor)

§1 (line 10) puts "none unsound in 30 small checks" after "E-195 part 4". The 30 checks are parts 1 and 2 (`experiments/w66/README.md:59`). Part 4 compares candidates at scale, with a weak witness (`:81`).

---

## Answers to the four questions

1. **Soundness.** Not as specified (B1, B2). With relocation, B2's values and Julia's validation (M1), it is sound by G1's criterion (M3). What can differ, item by item:
   - **world ranges:** from validation, never from the record (M1); in the inference's world (M2);
   - **effects and constant results:** the same when the edges verify and the callees' results are equal. A constant with identity is not stored (B2);
   - **inlining decisions:** history-dependent but sound if every inlined method is unchanged and the flags are equal (M3, m1);
   - **`invoke` targets and `:invoke` statements:** relinked to valid CodeInstances of this session, or the JIT caches a copy (B1);
   - **folds over plain answers and edges to `:facts_plain_return_type`:** not in the store; exclude (M4);
   - **generated functions and opaque closures:** exclude for now (m3);
   - **bindings:** relinked by name, values hashed (B1, B2);
   - **`Const` of mutable objects:** identity lost (B2).
2. **Feasibility.** Insertion inside `typeinf_edge` can be made safe only after `engine_reserve`, outside cycles, in the inference's world, with folds not evaluated there (M2). Store optimized IR (M3). Use `verify_method_graph`, `jl_promote_ci_to_current`, `jl_mi_cache_insert` through them, the `CodeInstance` constructor (`typeinfer.jl:1049`), `codeinfo_for_const` for constant results (`:1206`), `specialize_method` and `jl_compress_ir`. Not `Serialization` (B1).
3. **The gain.** The bound is not established (M6). The order is right, with E-0 added before E-c. Cheaper and principled: Julia's verifying trace instead of F2 and the index (M1); eager insertion instead of a hook (M2).
4. **The references.** G1's sources of valid code, §10.3's table, §4.4's folds, §11 and precompilation, the store's key (flags, coverage, module options, the setting), trimmed builds inert (m1, m2, m7).

---

## Recommendation

1. **Do not change Julia yet.** Revise the proposal for B1–B3:
   - a reader and writer with a table of references by stable name;
   - values of constant bindings hashed, objects with identity relinked or refused;
   - the code captured when it is made.
2. **Put to the user** (open issues §1): validity by Julia's verifying trace for dispatch plus fingerprints for content (M1), in place of F2's stakeholder walk and the candidate index. It is exact, cheaper, and uses Julia's own handling of cycles and worlds.
3. **Register E-a, E-0, E-b and E-c with M6's changes.** E-c inserts eagerly after loads through `verify_method_graph`. If its cost on unused entries is acceptable, that is the vehicle and no hook in inference is needed (M2).
4. **State the vehicles' trade in the proposal** with E-180's numbers. Record the image vehicle in the alternatives with its reason (M6).

---

## Stale copies seen (CLAUDE.md, rule 2), for whoever applies this review

- The cache's note, line 106 ("Bindings and folds: as today") and line 118 ("The fingerprints are computed in the session … with no Julia change"): true for the fingerprints, but bindings "as today" do not fix values across builds (B2).
- The cache's note, line 17 (the exclusion of entries reaching plain code) is not carried into the proposal's §1 (M4).
- `decisions.md` §5, the row on fingerprints: its F2 form would change if M1 is adopted. The user's words stand; the form is the user's to revise.
