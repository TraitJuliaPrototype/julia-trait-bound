# Facts first: the Julia work and TraitWorld's runtime against the facts rule's guarantees

Status: **proposal** (an agent's, for the user's review), 2026-10-27. Not normative. Nothing here is decided. Each opportunity names the reference sections, deviation rows and work items it would change.

The user (2026-10-27): "Send out an agent to look at the Julia work done so far. Look for opportunities that match the cache design: are there things that could be simpler and cleaner if they leverage facts and traits guarantees rather than try to improve all code (including plain)."

**The principle**, as [W-66's note](2026-10-27-facts-keyed-cache.md) (revision 2) applies it: rely on what the facts rule guarantees for code compiled by facts, instead of making a mechanism work for all of Julia's code. The guarantees used below:
- **G2 and Lemma O** ([facts §1](../reference/facts.md#terms), [§2.2](../reference/facts.md#g2)): code compiled by facts depends on the method table only through facts at concrete signatures. Only a stakeholder's change or a winning pirate changes one.
- **The mode rule** ([facts §6.2](../reference/facts.md#the-mode-rule)): code compiled by facts reaches plain code in two places only, the compiler's own code ([§6.4](../reference/facts.md#the-compilers-own-code)) and the plain answers that `return_type` folds ([§7.1](../reference/facts.md#return-type)), whose edges rest on facts by rule 2.
- **Rule 2 of traits** ([traits §5.3](../reference/traits.md#53-what-trait-code-may-do-with-a-trait-object)): a trait object reaches only declared operations and workers, at concrete types. So every call with a trait object is at a fact signature.

**Read:** julia-1.13 41d199c557 against v1.13.2 (the diffs of `Compiler/src/facts.jl`, `typeinfer.jl`, `abstractinterpretation.jl`, `effects.jl`, `ssair/inlining.jl`, `precompile.jl`, `reinfer.jl`, `src/gf.c`, `src/staticdata*.c`, `src/module.c`); TraitWorld 5589f4c (`strict.jl`, `hooks.jl`, `checks.jl`, `ahead.jl`, `defcheck.jl`, `untyped.jl`, `core.jl`, `entry.jl`, `certificate.jl`, `TraitWorld.jl`); the four references, `design/julia-changes.md`, `state.md`, open issues §2–§4, `record/todo.md`, `design/alternatives.md`, decisions §5, the performance explorations log, `experiments/ttfx/README.md`, `explorations/strict-mode.md`. Nothing was run or built.

---

## 1. Summary

Ranked by expected gain and confidence. Time gains are estimates until the quick check of each section runs.

1. **Strict mode on code of the facts owner** (§2.1).
   - Now: the prototype walks every backedge of every method a pirate overlaps, plain callers included, and protects plain code of Julia, TraitWorld and trait modules' entries.
   - Facts first: code of the facts owner reaches plain code only through `return_type`'s answers and the compiler. The walk can stop at the facts owner and follow only those two.
   - *Time:* the largest single cost found. Strict mode adds 6.6 s to C's load (E-168); most of it should go (to measure).
   - *Simplicity:* the general transitive walk and the plain branch go. Pieces 14 and 15, planned as general Julia features, are not needed.
2. **The setting as the default owner: mode ≡ owner** (§2.2).
   - Now: under `all` the default owner compiles by facts; a second "compiler code" predicate and four readers of the switch follow from it; an image's plain-owner code means different things per setting.
   - Facts first: code compiled by facts always lives under `:facts`; the setting decides only the default owner of neutral and boundary methods.
   - *Simplicity:* C-2, F-2, F-7 retire; W-69 (the setting in an image's key) is not needed; C-1 loses a predicate and two of its places.
   - *Time:* none for users; the test bed's numbers change.
3. **Images keep only the code of owners that run** (§2.3).
   - Now: images get machine code for `return_type`'s answers and TraitWorld's check results, which nothing calls (C-12); keep-compiled keeps plain upstream code too.
   - Facts first: beyond stock Julia, images keep code of the facts owner, which unrelated loads cannot invalidate.
   - *Simplicity:* `add_foreign_codeinfos!` goes; keep-compiled has one rule.
   - *Time:* precompile time and image size of every trait package; unmeasured, likely small for the demonstrators.
4. **A check's result kept with the facts code it read** (§2.4).
   - Now: four records of "checked", one of them collected by a walk over every name of every loaded package after each load; definition checks forgotten in a later session (L-9).
   - Facts first: the verdict is a function of facts code that an image keeps and G2 protects; keep it with that code.
   - *Simplicity:* one record instead of four; L-9 retires; it is what W-66 keeps (M4).
   - *Time:* small (the walk at each load; checks repeated in sessions).
5. **`rests_on_facts` once per answer** (§2.5). A transitive walk at every fold (limit 2,000, not memoized) becomes one record per plain answer. C-9 and F-13 retire. *Time:* small, unmeasured.
6. **Smaller ones in TraitWorld** (§2.6): the certificate's pass case from W-52's bit; the keep analysis on facts inference; generic implementations kept for their facts' worlds; the registries' `@max_methods 1`; and, not a facts guarantee but the hook's, the override checkpoint at every first call.

Everything else looked at is facts-scoped already or right as it is (§3). The interactions with W-66, open issue 73 and strict mode's intended design are §4.

**A suggested order:**
- §2.1 (a), the measurement, then (b), the narrowing: TraitWorld only, no Julia build, before W-66's Phase B.
- §2.3 and §2.5 in the next full build with W-22 and W-69's slot.
- §2.2 as the form of W-22's fix of C-2.
- §2.4 with W-67's TraitWorld fixes, or with W-66.

---

## 2. The opportunities

### 2.1 Strict mode on code of the facts owner

**What it does now** (`TraitWorld/src/strict.jl`; [facts §10.2](../reference/facts.md#strict-mode)):
- At a definition, and for each image's methods at activation, a method that is no stakeholder's is walked by `_winning_fact` (`strict.jl:155`):
  - every method it overlaps (`_methods_by_ftype(m.sig, -1)`), and every specialization's backedges;
  - the method table's backedges for its function;
  - per candidate fact, a method lookup (`_would_win`).
- Each backedge's caller is tested by `_trait_world_code` (`strict.jl:87`): code of owner `:facts`, **or plain code whose method is in Base, Core, a standard library, TraitWorld or a trait module** (`is_trait_world`).
- For any other plain caller, `_trait_dependent` (`strict.jl:223`) walks its callers' backedges transitively until it meets such code.
- After the definition, a safety net reads Julia's invalidation log with the same predicate (`_strict_after!`).
- **Scope:** all code. It protects plain code beyond the property ([facts §10.2](../reference/facts.md#strict-mode), the note). The user, 2026-10-21 (decisions §5): "Strict mode protecting more is a subtlty that might be tolerable. As written we say trait code never recompiles, that doesn't imply that we are not also protecting other code, so its not strictly a deviation (though it should be noted)."
- **Cost:**
  - E-168 (julia-1.13 252edca933, TraitWorld bbfc130, order A, two sessions, two cores, load 0.6–1.3): with strict mode on, C's load is 11.2 s (2.85 s compiling) against 4.5 s off. C is upstream SciML compiled by facts as trait modules: the facts mode calling into ordinary code, not idiomatic trait code (`experiments/ttfx/README.md`).
  - E-180 (julia-1.13 6800be7839, D with the cache, perturbed shapes): the session 1.22–1.33 s with strict mode against 1.06–1.08 s.
  - E-171 (generated trait packages without pirates): 0.01–0.04 s.
  - Session 25 (CSV, DataFrames, CairoMakie; TraitWorld 7b328a5): +0.54 s on a 4.1 s load, 0.49 s of it walking 837 pirates by the letter (`explorations/strict-mode.md` §2a).

**The guarantee that allows narrowing it:**
- By the mode rule, code of the facts owner holds edges to plain code in two classes only:
  - the plain answers `return_type` folds (owner `:facts_plain_return_type`), which rest on facts (rule 2 of [facts §7.1](../reference/facts.md#return-type));
  - the compiler's own code (methods with `jl_method_is_plain`).
- Under `all` today, a third: the shared cache of C-2 (§2.2 removes it).
- So a pirate invalidates trait code only at a fact that a `:facts` CodeInstance records, or at a fact inside those two classes, through their callers. These are exactly the cases the intended design's second row names ([facts §10.3](../reference/facts.md#strict-intended): "a folded `return_type`, the compiler").
- The property strict mode secures is about trait code ([facts §2.3](../reference/facts.md#two-tiers), §10.2).

**The simpler form:**
- `_trait_world_code(ci)` is `ci.owner === :facts`.
- The walk up through plain callers follows only CodeInstances of owner `:facts_plain_return_type` and of the compiler's methods. Any other plain caller is dropped at once, before `typeintersect` and `_would_win`.
- The safety net uses the same predicate.
- **Second step, with W-66's Phase B:** the load-time direction becomes the candidate index (§4). Then:
  - **piece 14** ("what would this definition invalidate", read-only, for all code) is not needed: for facts code a fact is a backedge at a concrete signature, and Lemma D decides whether the method wins there;
  - **piece 15** (image validation reports the winning method) is not needed: the index's hit names the method;
  - **piece 1′** (a deletion hook) remains, and a hook for a binding redefined from another module, which no planned piece names.

**What it costs or loses:**
- A pirate that wins only in plain code of Julia, TraitWorld or a trait module's entries is no longer refused. That code is compiled again, as in plain Julia. Trait code is not affected.
- TraitWorld's strict tests and `experiments/docs-examples/strict.jl` may contain such a case. They follow the design.
- The measurements of strict mode change (E-168's C/s, E-180's D/pks): measure again.

**How sure, and the quickest check:**
- Soundness: high. It is facts §10.2's property with the two plain classes of §10.3's second row.
- The gain: medium. What the 6.6 s consists of is not measured.
- **Check** (an experiment to register before it runs; minutes; no Julia build):
  - (a) One C/s session in E-168's shape, with a sampling profile of the load. Then `TraitWorld._STRICT_STATS` (methods seen, pirates walked, seconds owning, seconds walking), and the walk's backedges counted by the caller's owner.
  - (b) The narrowed predicate on a TraitWorld branch: C/s and D/s again; TraitWorld's suite; the docs example; the refusals listed before and after (`_REFUSED_PIRATES`).
  - **Refuted** if walking is a small part of the 6.6 s. Then the cost is ownership (`_strict_owned`) or compiling TraitWorld's strict code at the load, and the fix is an owner memo across images or the code in TraitWorld's image, not this narrowing. Also refuted, as a choice, if a refusal the user wants comes only from plain code.

**Where it would be recorded:**
- [facts §10.2](../reference/facts.md#strict-mode): rule 2 reads "at a fact of code compiled by facts, or of the plain answers and compiler code it rests on"; the note on protecting other code removed.
- [facts §10.3](../reference/facts.md#strict-intended): rows 1–2 by the index and the narrowed walk; F-6's text.
- [compiler §5.4](../reference/compiler.md#54-planned-hooks-for-strict-modes-intended-design) and `design/julia-changes.md` §3: pieces 14 and 15 dropped; 1′ and a binding hook.
- The decision log, marked mine, and W-71's review session (the user tolerated protecting more; this narrows it).
- `design/alternatives.md`: strict mode protecting plain code of Julia, TraitWorld and trait modules' entries.
- W-66's Phase B; the experiment's row.

### 2.2 The setting as the default owner: mode ≡ owner

**What it does now:**
- `NativeInterpreter` has two independent fields, `facts` and `owner` ([compiler §1.1](../reference/compiler.md#11-the-interpreter)). Under `all`, the default owner `nothing` compiles neutral methods by facts (C-2, F-2).
- Hence a second predicate for "compiler code", a module walk (`is_compiler_code`, `facts.jl:195`), beside the module flag (`jl_method_is_plain`). It is read by the single-request entry (`typeinfer.jl:1667`) and the compile queues (`interp_for_mi`, `facts.jl:88`).
- `leaves_to` has a branch for the facts image (`facts.jl:77`). `facts_default()` is read in four places (`facts.jl:56`, `:387`, `types.jl:404`, `typeinfer.jl:1667`), the interpreter's `facts` field in `facts_mode` and `leaves_to`.
- An image's code under owner `nothing` is plain code in one setting and facts code in the other. Hence F-7 and W-69 (the setting in an image's key), and the test bed's own depot.
- F-16 (a Base method asserted `:foldable` over run-time sites still folds under `all`) is "probably the shared cache".
- **Scope:** under `all`, all code shares the default owner. C-2's fix is planned (W-22).

**The guarantee:**
- The mode rule already says that plain results and results compiled by facts never share a cache; the product setting implements it by owner.
- A CodeInstance of owner `:facts` is compiled by the same rules in either setting: its callees are facts code, its run-time sites run facts code.
- Only one row of the mode rule's table depends on the setting: a neutral or boundary method reached from the default owner.

**The simpler form:**
- The setting decides one thing: the default owner of a neutral or boundary method reached from the runtime or the top level (`jl_default_owner`, and the owner a fresh `NativeInterpreter` gets). `:facts` under `all`, `nothing` in the product setting.
- The mode is the owner: `facts_mode(interp)` is `interp.owner === :facts`. An interpreter of owner `nothing` is plain in both settings. Under `all`, only the compiler's code and the Base code it calls get it, as C-2's planned property says.
- `interp_for_mi` and `is_compiler_code` go. `typeinf_ext_toplevel`, `interp_for_owner` and `leaves_to` lose their facts-image branches. `return_type_interp` follows E-190.
- **An image's CodeInstances mean the same in both settings.** An image built under one setting is correct under the other: the other setting misses its own owner's code and compiles it. So the setting in an image's key (W-69) is not needed for correctness or G2. A depot of its own stays the test bed's practice, for speed.

**What it costs or loses:**
- Under `all`, the default system image's plain Base code is not used. The facts system image holds Base under `:facts`. That image run with the switch off compiles plain Base anew: it is the test bed's image only.
- The keyword `NativeInterpreter(world; facts = …)` becomes `owner = …`. TraitWorld's `_check_interp` and `_check_kw_at` pass the owner explicitly.
- The test bed's numbers change: the CSV+DataFrames work under `all`, BaseBenchmarks under `all`. Measure again.

**How sure, and the quickest check:**
- Medium. It is W-22's planned fix of C-2, stated so that the setting has one reader. Two points need care: the facts image's default (`FACTS_IMAGE`) moves into the runtime's default-owner decision; reflection under `all` must start from the setting's default owner, so that it shows the code that runs.
- **Check:** none of minutes; it needs a build. Before it, a reading of each reader of `facts_default()`, `interp.facts` and `is_compiler_code` (seven) against the rule above. After the build: acceptance 33/33 in both settings; E-29 (G2 across loads under `all`); F-16's case; E-163's CSV+DataFrames row under `all`.
- **Refuted** if the compiler's plain code needs facts-compiled Base callees under `all` (its work 20% slower or more), or if an image built in one setting fails a check in the other.

**Where it would be recorded:**
- [compiler §1.1, §2.3, §2.4](../reference/compiler.md#23-the-owners-and-the-mode-and-owner-of-a-methodinstances-code); C-1, C-2.
- [facts §6.2](../reference/facts.md#the-mode-rule), [§11](../reference/facts.md#package-images) ("the setting is part of an image's key" replaced by "an image's code means the same in both settings"), [§12.2](../reference/facts.md#the-test-bed); F-1, F-2, F-7, F-16.
- The decision log's row "The setting is part of a package image's key" (mine, adopted by the clean-up) replaced, for W-71.
- W-22 (the form of its fix); W-69 dropped; `design/julia-changes.md` §1, "The switch".

### 2.3 Images keep only the code of owners that run

**What it does now** (piece 5; [compiler §2.9](../reference/compiler.md#29-what-package-images-keep)):
- `add_foreign_codeinfos!` (`Compiler/src/precompile.jl:470`) emits machine code for every CodeInstance of an owner other than `nothing` and `:facts` in a package's image: `return_type`'s answers (`:facts_plain_return_type`) and TraitWorld's check results (`_CheckOwner`). Nothing calls that code (C-12). It was made for TraitWorld's external interpreter, whose code ran through `invoke` of its CodeInstances; that interpreter is gone.
- With keep-compiled, `queue_external_cis` (`src/staticdata_utils.c:573`) keeps a CodeInstance of any owner for an upstream method that the workload compiled and no static call reaches: plain code too.
- Its measured value is facts code: the first `@implement` of a session 188 → 17 ms (9892bfc288). TraitWorld's own comment names its purpose: "workers at upstream keys, code under the trait world's own cache owner" (`hooks.jl:20`).
- **Scope:** every image (the foreign machine code); every package built in a process that loads TraitWorld (keep-compiled).

**The guarantee:**
- Code of the facts owner stays valid across unrelated loads (G2). An image that keeps it keeps code that a later session uses whatever loads first.
- Plain upstream code that a workload reached only dynamically depends on the whole method table. Stock Julia drops it, and a later load may invalidate it anyway.

**The simpler form:**
- Delete `add_foreign_codeinfos!` and the non-facts half of `collect_foreign_cis!`. Images get machine code for `nothing` and `:facts` only, the latter through the compile queue as now. The answers stay serialized, since facts code holds edges to them; they get no machine code.
- Keep-compiled keeps only `:facts` CodeInstances: the `found == 0` branch tests `ci->owner == :facts`, as `keep_without_source` already does.
- Optional, with §2.4: the definition checks' CodeInstances at archetypes never run ([lowering §2](../reference/lowering.md#2-modes-owners-and-images): "An archetype never runs"). Those of `_CheckOwner` get machine code today (C-12); those the rule check infers by facts sit in the facts cache, so the compile queue gives them machine code too, and the image validates them at load. Julia cannot tell an archetype; TraitWorld would infer them in a cache it drops before the image is written. To size by check (a) first.

**What it costs or loses:**
- Plain upstream code that a workload compiles and reaches only dynamically (a workload's printing or IO at top level) is compiled again in a session, as in stock Julia.
- Images get smaller; precompile emits less machine code.

**How sure, and the quickest check:**
- High for the first half (code nothing calls). Medium for keep-compiled's plain half: how much of it a demonstrator's session uses is not known.
- **Check:**
  - (a) Minutes, no build: after loading D's and C's packages, count per image the CodeInstances of owners `_CheckOwner()` and `:facts_plain_return_type` that carry machine code; the `:facts` CodeInstances at signatures that name an archetype; and the external CodeInstances of owner `nothing` with machine code that no method of the package reaches by a backedge.
  - (b) With the change (a system image rebuild for `precompile.jl`, a runtime rebuild for `staticdata_utils.c`): image sizes, precompile times, E-168's D and C sessions.
  - **Refuted** if a session's first calls slow by 20% or more without the plain half. Then plain upstream code reached dynamically matters: keep it, and say why in compiler §2.9.

**Where it would be recorded:**
- [compiler §2.9](../reference/compiler.md#29-what-package-images-keep): keep-compiled keeps code of the facts owner; machine code for the owners whose code runs. C-12 retired.
- [facts §11](../reference/facts.md#package-images), "What an image may hold".
- [lowering §2](../reference/lowering.md#2-modes-owners-and-images), "Where code lives".
- `design/julia-changes.md` §3 (piece 5) and §2 (9892bfc288); the decision log, marked mine.

### 2.4 A check's result kept with the facts code it read

**What it does now** ([lowering §14](../reference/lowering.md#14-checks-and-where-their-results-live); `checks.jl`, `ahead.jl`, `defcheck.jl`):
- The rule check reads the worker's facts inference: the code that runs, kept in images.
- Its result is recorded four ways:
  - a `Ref` flag per entry signature, embedded in the generated code of `checked_call`;
  - `_DEF_CHECKED`, a session's set of methods checked at archetypes, empty in a session that loads the package from its image (L-9);
  - `__tw_checked__`, signature lists evaluated into user modules while an image is built, collected after **every** package load by a walk over every name of the package's modules (`_note_checked_ahead!`, `ahead.jl:29`, called from `TraitWorld.jl:54`; 381 images in C);
  - `_CHECKED_IN_SESSION`, the list W-66's cache keeps (E-175 (3)).
- A flag stays set after an edit that recompiles the worker (a stakeholder's change), so the edited worker is not checked again. Read from the code, not verified by a run.

**The guarantee:**
- A check's verdict is a function of code compiled by facts: the worker's CodeInstance at the signature and what it calls (for a definition check, at the archetypes).
- That code is valid until a stakeholder's change or a winning pirate (G2), and the image that compiled it keeps it.

**The simpler form:**
- One record: "this facts CodeInstance passed the check", kept in the image that holds the CodeInstance. A definition check: the trait module's image. A check at a key: the declaring package's image.
- Looked up lazily from the signature at the first call (the worker's method and the key's module are known there), not collected at each load.
- Valid while the CodeInstance is. After an edit the worker's CodeInstance is new, so the check runs again. The entry's flag stays the fast path; the definition hook resets the flags of a trait-module function whose method is redefined.
- W-66's "first-call checks kept" (M4) is then this record.

**What it costs or loses:** a lookup of the worker's current facts CodeInstance in `_check_once`; the reset of flags at an edit.

**How sure, and the quickest check:**
- Medium-low on the gain. L-9 is a measured gap (E-175 (3): the checks ran again in every session).
- **Check** (minutes): time `_note_checked_ahead!` over C's load; count the first-call checks a D session runs for workers its images hold (`JULIA_TW_DEBUG=1`); a script that redefines a checked worker so that it breaks rule 2, and calls it again.
- **Refuted** if the walk costs under 10 ms, no check repeats and the edit is caught. Then only W-66's alignment remains.

**Where it would be recorded:** [lowering §14](../reference/lowering.md#14-checks-and-where-their-results-live) (what is kept), L-9 retired; a T- row if the edit case fails; W-66's note §2; W-67 or W-66 as the work item.

### 2.5 `rests_on_facts` once per answer

**What it does now:** rule 2 of [facts §7.1](../reference/facts.md#return-type) folds plain inference's answer only if it rests on facts. `rests_on_facts` (`Compiler/src/facts.jl:433`) walks every edge transitively, at every fold, up to 2,000 CodeInstances, unmemoized (C-9, F-13). **Scope:** folds in facts frames.

**The guarantee:** whether an answer rests on facts is a property of its CodeInstance, fixed when its edges are stored, and of its callees' same property.

**The simpler form:**
- `PlainRTInterp` records it once per CodeInstance, at the end of its inference, as an analysis result (`stack_analysis_result!`): from its own edges and its callees' records.
- A fold reads one record per split. An image keeps the record with the answer. The limit goes.

**What it costs or loses:** a few lines in `PlainRTInterp`. A cycle's members get their record after the cycle.

**How sure, and the quickest check:**
- Medium. The time gain is unknown; no profile so far names `rests_on_facts`.
- **Check** (minutes): a sampling profile of D's and C's first solve in E-168's shape, the share in `rests_on_facts`, and how many folds give up at the limit.
- **Refuted** if the share is under 1% and no fold gives up.

**Where it would be recorded:** [compiler §1.4](../reference/compiler.md#14-return_type), C-9 retired; facts F-13 retired; W-22.

### 2.6 Smaller ones in TraitWorld

Each is a small change with a small gain. Each check takes minutes.
- **(a) The fully-typed certificate's pass case.** `_check_fully_typed` runs `verify_main`'s walk when fully typed mode is on. A worker whose facts CodeInstance has W-52's `nortsite` set has no run-time site anywhere, error paths included: it is fully typed without the walk. The walk stays for the report when the bit is clear (a `Dynamic` split or an error path clears it). *Check:* in TraitWorld's suite, the share of certificates whose worker has the bit set.
- **(b) The keep analysis on facts inference.** `_keeps_sig` (`defcheck.jl:233`) infers plainly at archetypes in `_CheckOwner`. By rule 2 every call with a trait object is at a fact signature, so facts inference sees there what plain inference sees; the definition check has inferred the same archetypes by facts already. The result-type checks stay plain, by design. *Check:* `keeps` for every function of the demonstrators' trait modules, under both. *Refuted* by any difference.
- **(c) Generic implementations kept for their facts' worlds.** `_SLOW` (`entry.jl:141`), the builders of generic implementations on the slow path, is dropped at every new world, so after every load. The builder rests on dispatch at the user's concrete type. Holding it for that dispatch's world range, as `_umiss` does for declared implementations (`jl_gf_invoke_lookup_worlds`), keeps it across unrelated loads. *Check:* slow-path re-derivations after a `using` in D (`JULIA_TW_DEBUG=1`).
- **(d) The registries' `@max_methods 1` and sentinel methods** (about 30 registries) keep plain code compiled at abstract types from holding edges to them. Code compiled by facts holds none there. Where no plain TraitWorld code calls a registry at an abstract type, both can go (decisions §5: "kept until piece 7"). *Check:* a search of TraitWorld's neutral code (not `@machinery`) for registry calls at abstract types.
- **(e) Not a facts guarantee, the hook's: the override checkpoint.** `check_overrides()` (`implement.jl:1063`) runs at every first-call check (`checks.jl:388`), declaration and trait module's end, over every declaration of the session. The definition and image hooks refuse overrides at their source, except an image's new declarations against overrides already loaded, which `_on_image_methods` does not check. Checking those in the image hook makes the checkpoint unnecessary. *Check:* `check_overrides()` per call in ScaleL (E-171's 4,000 workers).

---

## 3. Looked at: facts-scoped already, or right as they are

**Julia:**
- **(A), the facts mode** (`is_fact_sig`, run-time sites, `FACTS_ABSTRACT_SITE`): facts frames only, by construction.
- **W-43, union splitting by Julia's cost:** it defines the fact forms, at Julia's cost exactly (the user, open issue 46). Facts only.
- **W-52, the run-time site's mark:** only the facts mode clears `nortsite`, and only facts frames withdraw an assertion (`adjust_effects`, `merge_override_effects!` test `facts_mode`). Plain frames keep upstream behaviour; the bit costs plain code nothing.
- **`return_type`'s rules and its exception:** facts frames only. E-190's route (`PlainRTInterp` at run time in both settings) is already the facts-first form: one cache that never runs, plain inference's answers. Sending only facts methods to `PlainRTInterp` and leaving plain queries in plain Julia's cache would put plain CodeInstances that name a facts method's plain answer, instead of its facts CodeInstance, into the cache whose code runs: not recommended. Rule 2's walk: §2.5.
- **(B), the mode per method** (the module option, `Method.facts`, owner `:facts`, `facts_edge`, reflection of a facts method by facts): facts code and its boundary. Its one setting-dependent part is §2.2.
- **W-33 and W-41,** constants and concrete evaluation from plain callers into code compiled by facts: the boundary's price for plain callers of trait code, resting on G2 (the user, open issue 52: "trait code is never (rarely) invalidated, right? So the trade-off is actually mild?").
- **Inlining across owners** (c7f1eae1c0), **pieces 9 and 10:** general in form, inert without a second owner.
- **(C), dispatch from facts code** (`jl_apply_generic_facts`, `jl_invoke_facts`, codegen): facts code only.
- **(D), `split_call` and the table of a call's targets:** trait code and entries. The fallback is a run-time site, outside every fact, so no facts guarantee simplifies the table; session stamps replace invalidation.
- **The two inliner changes:** all code, by the user's decision ("Apply to all code"). A facts-only form was built first and left plain recursions through varargs wrappers 56× slower ([alternatives](../design/alternatives.md#the-inliner-changes-a-facts-only-form-then-a-narrower-general-form)). Not revisited.
- **The per-call-site cache's wildcard and exact-type entries:** they serve run-time sites, which no fact covers by definition. Confining them to facts dispatch would add a branch and drop an improvement for upstream. C-3's open `max_world` (PE-4) is the same for both owners.
- **`:caller_world` (piece 18):** a pointer call in the caller's world is a correctness property of any pointer call. Nothing in it is specific to facts.
- **`known_type`:** a general primitive, a few lines.
- **`fold_call` (W-40):** scoped to the code that calls it. Its records are evaluated at load, which W-66 keeps (M4).
- **W-57, Base's type-introspection layer on builtins and `invoke`:** it changes Base for all code, as a fix by Julia's own contract for asserted effects. A call at a kind has no fact form (any type's owner may add `f(::Type{X})`), and the facts-only routes (trusting Julia's assertions; recording dispatches, PE-7) were unsound. Its parts 2–3 already wait for the withdrawn-assertion log, a facts-scoped trigger.
- **W-59, which images keep:** a filter on any image's external code; it changes no result. Narrowing it to facts code would add a condition and keep a cost that stock-like images pay too.
- **40512f64c2, bb82a82bbf, e4db37bb48:** general fixes. With E-190, the bootstrap entry to compile is `PlainRTInterp`'s in both settings.
- **The compiler plain whoever calls it** (flag 2, `leaves_to`, `facts_callee_owner`): facts code's boundary to the compiler. C-1's single function stays the plan; §2.2 removes one predicate.
- **`--trim` plain:** right as it is.
- **Pieces 1, 3 and 17, the dispatch profiler, the withdrawn-assertion log:** hooks and tools, general by nature.
- **W-64 (set aside) and W-62 (retired):** consistent with this note's principle.

**TraitWorld:**
- **`@machinery`:** already the facts-first form for the slow paths.
- **The untyped calls' table** (`untyped.jl`): its entries hold the world range of the dispatch they rest on. §2.6 (c) extends that to generic implementations.
- **`Erased` and `_UWrap` pointers:** `:caller_world`, right as it is.
- **Compiling ahead** (`ahead.jl`): facts code into the declaring package's image, right as it is.
- **The definition hook's checks** (an override, a trait's name on an argument outside a trait module): an index lookup per method. See §2.6 (e) for the checkpoint beside it.

---

## 4. Interactions

### With W-66

- **The identity's form does not matter here.** W-66 now identifies an entry by fingerprints scoped by the facts rule ([the note](2026-10-27-facts-keyed-cache.md) §5b; the user's decision; E-195). Every point below holds for that identity and for the closure's build ids alike.
- **One check in two directions.** The candidate index of W-66 (an image's facts against the methods its closure did not define, at validation) and §2.1 (a new method against existing facts, at a definition or an image's activation) are the two directions of one check over facts code. §2.1 (b) is the second direction, in TraitWorld, with no Julia build. W-66's step 3 is the first, in Julia.
- **The share to state before the build.** §2.1 (a) measures how much of strict mode's cost lies in facts code. W-66's step 3 must state its gain as the facts share of validation before its build; the two numbers come from the same profile.
- **§2.2:** the store is one per Julia build and setting (m3). The setting can drop from it, since a `:facts` CodeInstance means the same in both settings. An entry's first condition, "in the product setting", becomes "of owner `:facts`".
- **§2.3:** the store keeps facts code only, and so do images beyond stock. The vehicle "sections of one image" builds on piece 5, which then has one rule for both.
- **§2.4:** the kept first-call check (M4) is the record on the CodeInstance.
- **§2.5:** M3 excludes entries that reach plain code. E-194 found none of C's 1,835 cacheable entries reaching another owner (julia-1.13 41d199c557, TraitWorld 5589f4c, one session), so the exclusion costs nothing today. Should a port fold plain answers in cached code, the record would let those entries be kept, since answers that rest on facts validate like facts code; only entries that reach the compiler's code (TraitWorld's machinery) would stay excluded.

### With open issue 73

- Closed by W-65, each option with its home. Its bullet "strict mode's check at load (6.6 s for C, E-168)" is §2.1, which can come before W-66's build.
- Its lever, facts images without edge validation, is W-66's step 3. Nothing here changes it.
- **The same principle at activation (Optional, after W-66, with the ports' numbers).** Method activation (0.8–0.9 s of S's 3.3 s load, E-169) searches what each new method invalidates, in all code. For code of the facts owner, an image's own methods on its new functions and types cannot win at a fact that existed before it: no such fact names them (Lemma O). Only its candidates can. Skipping facts callers in that search for an image's owned methods saves only the facts share today (11% of C's loaded code, E-169), and nearly all of the search in a whole trait world. The runtime would need TraitWorld's notion of an owned method (the union and `Vararg` rules), so it is a Julia change in the load's hottest path.

### With strict mode's intended design

Row by row ([facts §10.3](../reference/facts.md#strict-intended), F-6):
- **A pirate loaded before an image:** W-66's index at the image's validation. The hit names the method, so piece 15 is not needed.
- **A pirate inside plain code that trait code depends on:** the narrowed walk of §2.1, through `return_type`'s answers and the compiler's code. Piece 14 is not needed.
- **A package extension's winning method:** unchanged (followed, with a warning).
- **A binding redefined from another module:** needs a hook at a binding's redefinition, which compiler §5.4 does not name. Name it beside 1′.
- **A deletion:** piece 1′.

Beyond the rows:
- The note of §10.2 ("it also protects other code") goes with §2.1.
- "Strict mode is policy, not validity" (W-66 §2) holds unchanged: the narrowed check decides only whether to raise.
- **For W-71's review session:** whether strict mode should keep protecting plain code of Julia, TraitWorld and trait modules' entries (§2.1), and the image key without the setting (§2.2), which replaces a choice the clean-up adopted.
