# Fresh-eye review of the proposal "Strict mode on facts code, and its error at an image's load" (2026-10-28)

**Reviewed:** `writeup/plans/2026-10-28-strict-mode-on-facts-code.md` at design repository bebae18, with the working tree's uncommitted reference edits. TraitWorld 5589f4c, with the uncommitted `src/compiler.jl` edit. julia-1.13 41d199c557, with the uncommitted W-22 edits (`Compiler/src/facts.jl`, `typeinfer.jl`, `types.jl`, `base/Base.jl`, `src/gf.c`).

**Method.** I read the proposal, its source (`plans/2026-10-27-facts-first-julia-work.md` §2.1, §2.2, §4), W-66's note §2–§3, facts §1, §2, §6, §7.1, §9, §10, §11, §12 and §15, compiler §4.3, §4.4, §5.1, §5.4, PE-1 and PE-8, and decisions §4 and §5. Against the code I read `TraitWorld/src/strict.jl` (all), `hooks.jl` (all), `TraitWorld.jl` (the callback), `compiler.jl` (the checks' interpreters), `trait_module.jl` (`is_trait_world`); in julia-1.13 `Compiler/src/reinfer.jl` (all of validation), `Compiler/src/facts.jl` (`interp_for_owner`, `leaves_to`, `PlainRTInterp`, `rests_on_facts`, `facts_plain_return_type`), `Compiler/src/typeinfer.jl` (`finish!`, `compute_edges!`), `base/loading.jl` (the restore, validation, `register_restored_modules`, the callbacks, the dependency loop), `src/staticdata.c` (`jl_restore_package_image_from_stream`), `src/gf.c` (`jl_debug_method_invalidation`, `jl_run_image_methods_hook`, `_invalidate_backedges`, `jl_default_owner`), `src/method.c` (cached generator output). Nothing was run: a build is running.

**Counts.** Blocking 2, Major 6, minor 8.

---

## Answers in brief

1. **Part A is not sound as argued.** Code of the facts owner reaches plain code through the compiler's code, and the compiler's code rests on plain Base code of owner `nothing`, whose methods are not the compiler's. A pirate that wins there invalidates facts code, and the narrowed walk drops it (B1). The other paths asked about add no class: `return_type`'s answers are `:facts_plain_return_type` all the way down; the split's fallback and run-time sites record no edge; facts code propagates no constants into plain callees; opaque closures are fixed to a world; the checks' `_CheckOwner` results are values, not edges. Pre-existing gaps the soundness claim should name: generator-reported edges and invoke edges at non-fact signatures (m1); constant-propagated results kept in plain callers (m2). Under `all` after W-22, Part A protects every package's code (M4).
2. **Part B as written finds nothing.** Validation writes its entries to the compiler's own log (`Compiler.ReinferUtils._jl_debug_method_invalidation`), not to the runtime's `jl_debug_method_invalidation`, which the proposal turns on (B2). The hook does run in the same load before validation. But the log's lifetime across nested loads, skipped hooks and other users needs a different shape (M1), the entries need careful reading (M2), and `@error` is a report, not the reference's error (M3). The smallest sound alternative: the compiler's validation log on for the whole session in strict mode, read and emptied in every package callback; no dependence on the image hook (B2, M1).
3. **PE-8's conclusion is defensible; its argument is not.** The index is an architectural improvement that facts enable, rule (1), which carries no 20% bar. What sets it aside is the rule's other clause: a minor speedup for a change in Julia's loader. And the index was the adopted mechanism of strict mode at load (decision "Strict mode's intended design is built with the cache…", the user's); replacing it by the log is a change to record and flag, and PE-8's own text contradicts the proposal (M5).
4. **Missed:** §12.2, §11's status, traits §10.3, `state.md`, `intro/porting.md` and F-6's text; compiler §5.4 must name the internal interface Part B relies on (M6).

---

## Blocking

### B1. The compiler's code rests on plain Base code that is not the compiler's; Part A drops pirates that win there, and facts code is invalidated

- **Location:** the proposal §3, "Why it is sound" and the walk's rule; source §2.1, "The guarantee that allows narrowing it".
- **The claim:** facts code holds edges to plain code in two classes only, `:facts_plain_return_type` and the compiler's own methods (`jl_method_is_plain`), "so a pirate invalidates trait code only at a fact a `:facts` CodeInstance records, or at a fact inside those two classes".
- **Why it is false:**
  - Facts code that calls compiler functions directly holds edges to the compiler's CodeInstances in the current world (facts §6.4, `reference/facts.md:330`; §2.2's exception, `:156`; decision "Code compiled by facts that calls compiler functions directly holds edges…", decisions §5). TraitWorld's `@machinery` code does this.
  - The compiler's code calls Base: `push!`, `getindex`, `iterate`, `==`, `hash` on Julia's own types. A plain interpreter infers those callees under owner `nothing` (`Compiler/src/facts.jl:74`, `leaves_to`: an interpreter of owner `nothing` leaves only for facts methods). Their methods are Base's, not `jl_method_is_plain`.
  - Only a pirate can win at a signature of a Base function over Julia's types. Invalidation then runs Base CodeInstance → compiler CodeInstance → facts CodeInstance, each step through an edge that names the callee's CodeInstance (`src/gf.c:2446`–`2451`).
  - Under Part A, `check` meets the Base CodeInstance as the first caller (`TraitWorld/src/strict.jl:160`–`168`), and drops it: owner `nothing`, not the compiler's method.
- **Today it is refused:** `_trait_world_code` counts owner-`nothing` code of Julia's methods as protected (`strict.jl:89`–`91`, `trait_module.jl:40`). `intro/porting.md:403` reports such a refusal as expected: OffsetArrays' `reshape` pirate "(Base's own code is protected)".
- **What catches it after Part A:** at a definition, the safety net (`strict.jl:265`–`296`) sees the facts CodeInstance invalidated, deletes the method and raises: a miss, counted. At an image's activation there is no safety net (`hooks.jl:273`–`297`), and Part B reads past activation's invalidations (the proposal §4, "Limits"). So an image's pirate invalidates TraitWorld's machinery code silently.
- **The same under `all` after W-22:** the compiler's Base callees stay plain, owner `nothing` (W-22's `leaves_to`; the facts-first review §2.2, "only the compiler's code and the Base code it calls").
- **Fix, one of:**
  - (a) In TraitWorld: walk up through owner-`nothing` CodeInstances of Julia's own methods (Core, Base, the standard libraries) as well as the two classes; stop only at `:facts`. Sound. Its cost is the walk up from Base callers, which today stops there; measure it in E-197 (a).
  - (b) Principled, a small Julia change: in the facts mode a call to the compiler's own code records no edge (a run-time site). Then facts code holds edges to plain code in one class only, `return_type`'s answers. Part A needs no compiler class, and G2 loses its exception for direct calls into the compiler (facts §2.2). It touches the decision that keeps those edges (decisions §5): to flag for W-71.
  - (c) Accept the gap: a deviation row naming the chain, and the safety net as its only guard at definitions, none at loads.
- Whichever is taken, the soundness sentence names the class as "the compiler's code and the plain code of Julia it calls". E-197 needs a case: a pirate on a Base function at a signature the compiler's code calls, after TraitWorld's machinery has run.

### B2. Validation writes its entries to the compiler's own log, not to the one Part B turns on

- **Location:** the proposal §4, "How, with Julia's own record", first bullet.
- **The code:**
  - The runtime's log is `_jl_debug_method_invalidation` in `src/gf.c:2259`, switched by `jl_debug_method_invalidation` (`gf.c:2260`–`2272`). The safety net uses it (`strict.jl:253`–`258`).
  - Validation writes to a separate Julia-side log: `const _jl_debug_method_invalidation = RefValue{Union{Nothing,Vector{Any}}}(nothing)` in `Compiler/src/reinfer.jl:11`, switched by `debug_method_invalidation(onoff)` (`:12`–`13`). Every validation entry reads it: `method_globalref` (`:210`–`213`), `insert_backedges_callee` (`:284`–`287`), `verify_methods` (`:343`–`346`). No line in `src/*.c` touches it.
- **So:** turning on `jl_debug_method_invalidation` in the image hook records activation's invalidations (plain and facts code, the proposal's "Limits", second bullet) and no `insert_backedges_callee` entry. Part B would report nothing.
- **Worse, with the runtime's log:** it is on through `register_restored_modules`, which runs the image's `__init__` (`base/loading.jl:1453`–`1462`) before the callback. A method defined there runs the definition hook. Its `_strict_log_start!` returns the same array (`gf.c:2266`); its `_strict_after!` stops the log (Part B loses it) and reads activation's entries as if the definition made them. With a non-stakeholder signature among them and a facts CodeInstance invalidated by activation, the safety net deletes the method defined in `__init__` and raises a `PirateError` against it (`strict.jl:273`–`293`).
- **Fix:** use `Base.Compiler.ReinferUtils.debug_method_invalidation(true)` (the module `loading.jl:1344` calls), and leave the runtime's log to the safety net. The two then never meet. This also resolves the misattribution above. See M1 for its lifetime.

---

## Major

### M1. The log's lifetime: nested loads, a skipped hook, and other users

- **Location:** the proposal §4, "How", bullets 1 and 3; "Limits", first bullet; "Why the log": "only for the span of one image's load".
- **The hook does run in the same load, before validation:** `jl_run_image_methods_hook` (`src/staticdata.c:4461`), then activation (`:4468`), then the return to Julia and `insert_backedges_typeinf` (`base/loading.jl:1343`–`1345`).
- **It is skipped when:**
  - the image extends no other module's function (`gf.c:2340`–`2342`): common for leaf packages, and under `all` for many packages whose code is all facts code;
  - a load happens inside a hook (`gf.c:2338`, `jl_in_method_hook`);
  - no hook is set: `JULIA_TW_HOOKS=0` (`hooks.jl:33`), or images loaded before TraitWorld's `__init__`.
- **Nested loads:** one `using` restores and validates every missing dependency first, each with its own hook (`loading.jl:2196`), then the package (`:2209`); the dependencies' callbacks run after the package's restore, in a `finally` (`:2226`–`2229`); the package's callback later (`:2630`, `:2888`). A dependency found by build id runs its callback at once (`:2043`). An extension loads inside `run_package_callbacks`, before the parent's callbacks (`:1487`).
  - `debug_method_invalidation(true)` replaces the array (`reinfer.jl:13`). A second hook in one `using` would discard the first image's entries.
  - The first callback to stop the log ends it for every image validated after it in the same `using`.
- **Other users:** a tool recording invalidations (SnoopCompile's `@snoop_invalidations` switches both logs) loses its record when TraitWorld replaces or stops the log. The safety net already stops the runtime's log after every definition in strict mode (`strict.jl:257`): the same problem today, worth a line.
- **The proposal's own remedy** for the gap ("start the log in the package callback of the previous load as well") makes the log permanent, and contradicts "only for the span of one image's load".
- **The smallest sound form, no Julia change:**
  - In strict mode, the compiler's validation log is on for the session: at `strict!(true)` and at TraitWorld's init with `JULIA_TW_STRICT=1`.
  - Every package callback reads the entries and empties the array in place. It turns the log on again if another tool switched it off, and never replaces an array it did not make.
  - The image hook plays no part. Images without methods, nested loads and extensions are covered.
  - Its cost: with the log on, validation does not stop at a CodeInstance's first failed edge (`reinfer.jl:288`–`290`), matches without a limit (`:577`), and skips the fast return for a deleted method (`:486`–`489`). All three apply only to failing edges. Measure it in E-197 on C's load in order B.
- **Cleaner, a few lines in Julia (piece 15 proper):** `_include_from_serialized` turns the log on around `insert_backedges_typeinf` when a flag is set, and passes the entries with the `PkgId` to a callback. Exact per image, nothing shared. Worth stating as the alternative, since §5.4 lists piece 15.

### M2. Reading the entries: fields, splits, non-call edges, and failures inside `return_type`'s answers

- **Location:** the proposal §4, "How", bullets 2 and 3.
- **What an `insert_backedges_callee` entry holds:** `(edge, "insert_backedges_callee", codeinst, matches)`, four items (`reinfer.jl:286`).
  - `edge` is a `MethodInstance` for a CodeInstance or instance edge (converted at `:218`–`221`); the call's signature for a counted edge (`:240`); the `invoke` signature (`:255`–`256`); a `FoldRecord` (`:242`–`246`); a `Core.Binding` (`:247`–`261`).
  - `codeinst` is the CodeInstance whose own edge failed. Its callers in the image get three-item `verify_methods` entries `(child, "verify_methods", cause)` (`:345`).
  - `matches` is, for a call edge, the methods that match now and were not expected (`:598`–`616`); for an `invoke`, the `_findsup` result (`:648`). For a `FoldRecord` or `Binding` edge it is not reset: it holds the previous failed edge's methods.
- **Consequences for the reader:**
  - Skip non-call edges. Otherwise a fold that no longer holds, or a binding redefined, is reported as a `PirateError` against an unrelated method.
  - For a counted edge at a fact signature with splits, a listed method may apply without winning. Judge each split: the method is the one dispatch selects there now (or the call is ambiguous), and its definer is no stakeholder of that split (`_fact_splits`, `_stakeholder`).
  - A broken fact inside an image's `:facts_plain_return_type` CodeInstance is logged against that CodeInstance, not a `:facts` one. Follow the `verify_methods` entries to the facts caller, or accept that owner too, as Part A does.
  - A stakeholder's package extension loaded before the image is facts §10.3's third row: a warning, not an error. The proposal names stakeholders and delegates only.
- **The test** (the proposal §5, Part B) should add: a fact signature with two splits; a fold failing beside a call edge in one CodeInstance; an answer of `return_type` folded in the image; an extension.

### M3. `@error` after the load is a report, not the error facts §10.3 states, and the strict tier's property then fails silently

- **Location:** the proposal §4, "The error"; facts §10.3 (`reference/facts.md:463`, `:467`), §2.3 (`:172`).
- **The difference from the refusals it copies:** a refused image method stays inactive (`hooks.jl:289`–`292`), so the property holds and the `@error` reports a correction. In Part B the pirate stays active and the image's facts code is compiled again with it. Trait code computes the pirate's result; only a log line says so. A script continues.
- **Why no exception is possible without Julia:** the callback's exceptions are caught and logged (`loading.jl:1494`–`1497`); the image's methods are active before validation (`staticdata.c:4468`).
- **What the proposal must do:**
  - Say in facts §10.3 row 1 that the error is reported at the load, not raised, and why. Say in §2.3 what "loads without a `PirateError`" means for a reported one.
  - Flag this reading for the user (W-71). It weakens what §10.3 states.
  - Or name a stronger form: the affected trait module's entries raise the recorded `PirateError` when called. That is new machinery; at least list it in `design/alternatives.md` if not taken.

### M4. Under `all` after W-22 Part A protects every package's code, and nothing says or tests it

- **Location:** the proposal §3, "What it gives up", "Depends on W-22"; facts §12.2 (`reference/facts.md:523`).
- **The code:** after W-22, `jl_default_owner` returns `:facts` for every method but the compiler's under `all` (`src/gf.c:438`, the uncommitted edit). So `ci.owner === :facts` is all code but the compiler's and its plain Base callees.
- **So:** under `all`, strict mode refuses any pirate that wins at a fact of any package's compiled code. That is wider than the product setting, and wider than today under `all` (owner `nothing` was "not protected", §10.2's note). "What it gives up" describes the product setting only.
- **Also in the product setting,** "code of the facts owner" is more than "trait code" (§10.2, `:445`): TraitWorld's `@machinery` code, the split's `_SplitTargetFacts` thunks, Base methods compiled by facts. Most of it is code trait code depends on; the machinery is not. §10.2's "What it protects" should say "code of the facts owner" and name the difference, or keep the term and say it protects more.
- **Fix:** state the `all` behaviour in §10.2 and §12.2; add a strict session under `all` to E-197, or record it as untested under E-82 (which decision "Strict mode's intended design is built with the cache…" puts in W-66's scope).

### M5. PE-8 applies the wrong clause of the rule, and the proposal changes the adopted mechanism of strict mode at load without flagging it

- **Location:** the proposal §2; `record/performance-explorations.md` PE-8; decisions §4, "Strict mode's intended design is built with the cache keyed on facts and their origins" (the user's, 2026-10-27); W-66's note §2, "Strict mode is policy, not validity".
- **The rule** (decisions §5) pursues (1) principled architectural improvements that facts and traits enable, and (2) severe bugs at 20% or more. The index is a clear case of (1). The proposal's reason, "a minor speedup (a few per cent of the load)", is a (2)-style threshold. The clause that does apply: "tweaks that give minor speedups at a considerable increase in complexity are not pursued"; the index is a change to Julia's loader. Say that, and say that its natural time is with the store (step 4), which needs it anyway.
- **The bound** is rough but on the safe side: E-185's 1.4 s is stock's validation (S), the 11% is a share of C's loaded code (E-169), not of validation time. Facts edges at concrete signatures often take `verify_call`'s fast path (`reinfer.jl:490`–`512`), so the facts share of validation time may be smaller still. State it as an upper bound with both builds.
- **The contradiction:** PE-8 says "The index stays the design's tool … for strict mode at load, where its gain is not the question". The proposal makes the log that tool. The user adopted "images of facts code validated against a session index of candidate methods … strict mode is the policy for a winning candidate (an error for a package image…)". Moving row 1 from the index to the log is a change to that decision's mechanism.
- **Fix:** record it in the decision log as mine, list it for W-71, put "strict mode at load by the index" in `design/alternatives.md` with the reason, and correct PE-8's sentence.

### M6. Copies and reference sections the proposal's §6 does not list

- `reference/facts.md`:
  - §12.2 (`:523`): strict mode under `all` (M4).
  - §11's status (`:481`): "Planned: the strict tier's error" becomes Implemented, in the reading M3 fixes.
  - §10.2, "How it finds the facts" (the walk "to trait code") and "What it protects" (`:445`), not only rule 2 and the note.
  - F-6: today it names a pirate before an image and a deletion; a binding redefined from another module is a §2.2 exception, not in F-6. "F-6 keeps rows 4 and 5" needs F-6 restated, or a new row for row 4. Its "Where" column (`hooks.jl:230`, `strict.jl:123`) points at lines that do not hold the cause.
- `reference/traits.md:1242` and `:1251`: the status says "refusal of pirates loaded before the code they change"; a pirate already loaded cannot be refused, only reported. And "Strict mode also protects some code that is not trait code" goes or changes.
- `state.md:114`: "it also protects all `:facts` code and some plain code".
- `intro/porting.md:403`: OffsetArrays' `reshape` pirate refused "(Base's own code is protected)". Under Part A this refusal may go. E-197 (a) must check this case, which is the proposal's own "would change the plan" criterion: a refusal the user's examples show, coming only from plain code.
- `reference/compiler.md` §5.4: piece 15 is not "not needed". Part B depends on an internal interface: `Compiler.ReinferUtils.debug_method_invalidation` and the entry format above. Name it as the interface TraitWorld uses, with the risk that it changes with Julia, or keep piece 15 as the Julia form (M1's last bullet). `design/julia-changes.md` §3 with it.

---

## minor

### m1. Edges from a generator, and `invoke` at a non-fact signature, are facts code's edges that `check` never tests

- A generated function's reported edges are appended to the frame's edges as they are (`Compiler/src/typeinfer.jl:820`–`823`), and can be `MethodInstance`s at signatures that are not facts. An `invoke` edge at a method's own abstract signature is accepted as resting on facts (`Compiler/src/facts.jl`, `rests_on_facts`).
- For a `:facts` caller, `check` requires `_fact_sig(s)` (`strict.jl:163`). A pirate that wins there, or replaces the invoked method, is not refused.
- Not introduced by Part A. The soundness sentence should name these edges, or the walk should test a `:facts` caller's non-fact edges by `_would_win` as it does for plain callers.
- Checked and harmless: a generator's cached output (owner `:uninferred`) is invalidated by any owner's change (`gf.c:2446`–`2447`), but only callers of owner `:uninferred` follow it.

### m2. Results of constant propagation from plain code into facts code live in the plain caller

- Facts §6.3 (`reference/facts.md:309`): "The result stays the caller's", with the caller's edges on the constants' path. Facts the generic facts CodeInstance does not hold can be among them.
- After Part A a pirate that wins only on that path is not refused. A trait module's function, called with constants from plain code, then gives the pirate's result without an error.
- Allowed by the property (no facts CodeInstance is invalidated), but "What it gives up" should name it.

### m3. Folds and the checks' results are outside strict mode, before and after

- A `FoldRecord` has no backedge in a session (compiler §4.4). The definition checks' inference under `_CheckOwner` and under owner `nothing` (`TraitWorld/src/compiler.jl:57`, `:68`) gives verdicts kept as values. A pirate can change either without invalidating facts code. Neither is a change from Part A. One sentence in §10.2's "Not refused" would close the question; the facts-first review §2.4 is the fix for the checks.

### m4. Run-time sites and the split's fallback

- They record no edge, so a pirate changes what they call without invalidating anything (facts §9; compiler §4.3, "The fallback stays a run-time site"). The split's targets are `:facts` code and are protected as such. Strict mode never covered the dispatch itself. The soundness sentence speaks of invalidation; keep it so, and do not widen it to "what the code computes".

### m5. Numbers without their builds

- §2's numbers name experiments but not builds (CLAUDE.md, rule 5): E-185 stock 1.13.2; E-186 julia-1.13 f1866b9d4e; C's 4.3 s load, which run. PE-8 has them; the proposal should cite PE-8 instead of copying.

### m6. The checks

- Part A: add B1's chain case and the OffsetArrays case (M6).
- Part B: add a pirate in a dependency loaded by the same `using`; an image that extends no other module's function; an extension; SnoopCompile's recording on during a load (M1, M2).
- `twolibs` is in the adopted intended design as an acceptance check (decisions §4, "The intended design of strict mode"). Name it, or say why not.

### m7. Precompile workers inherit `JULIA_TW_STRICT`

- Workers validate the images they load. Part B would report there, into the precompile log, and the report would be lost. Say what strict mode does when `jl_generating_output()` is set.

### m8. Two hooks may run at once

- The require lock is released while an image is restored (`loading.jl:1324`–`1335`). Two tasks loading different packages can run the image hook concurrently. With a session-wide validation log (M1) this does not matter, since validation runs under the lock. With the proposal's per-hook start and stop it does.

---

## What holds

- The image hook runs before activation and before validation, in the same `_include_from_serialized` (`staticdata.c:4461`, `loading.jl:1344`).
- Validation, with its log on, writes for each rejected edge the CodeInstance and the methods that match now, as the proposal says, once the right log is used (B2).
- `return_type`'s plain answers are self-contained: `PlainRTInterp` caches every callee under `:facts_plain_return_type` (`Compiler/src/facts.jl:350`), and the fold's edge per split is a `(signature, CodeInstance)` pair that `_trait_dependent` already follows (`strict.jl:237`–`243`).
- Invalidation follows owners: a caller is invalidated only through an edge naming the callee's CodeInstance, or a bare instance edge of the same owner (`gf.c:2446`–`2451`). So plain code of owner `nothing` that facts code does not name never reaches it, except through the compiler (B1).
- W-22 removes the shared default owner under `all` (`gf.c:438`), as Part A's dependency says.
