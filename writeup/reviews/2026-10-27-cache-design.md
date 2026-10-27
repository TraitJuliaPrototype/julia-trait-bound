# Review: the cache across sessions, its design and its build (W-62)

Reviewer: fresh eyes (Opus 5.5), 2026-10-27. Files and git history read; nothing run. Reviewed:
- the cache note `writeup/plans/2026-10-27-session-cache.md`, revision 2 with §7 "As built", at design commit 91aa0d1 (the last commit to touch it);
- TraitWorld branch `session-cache` at 25419a7 (the mechanism in 031932a, its test in 25419a7): `src/cache.jl`; in `src/TraitWorld.jl` `__init__`, `_on_package_load_callback` and the workload's cache block; `test/cache.jl`; for the checks `src/checks.jl` (`_check_once`), `src/ahead.jl`, `src/concrete.jl`;
- `experiments/ttfx/README.md` (E-175, E-177, E-178, E-180) at experiments 03c222e, with `cache/probe_parts.jl` and `logs/e180c/parts.log` (the per-part measurement), the caches on disk (`cache/tw-cache-{C,D}/`) and the part images (`depot-C/compiled/v1.13/TWC_*`);
- evidence §3; open issues 72 and 73; facts §2, §10, §11; compiler §2.9; lowering §14–§16; alternatives, "Caches across sessions"; the architect's memo (`plans/2026-10-27-lean-core-old-apis.md`) §1.5 and §2.1; the reviews `2026-10-27-cache-and-port-notes.md` and `2026-10-27-w58-direction.md`;
- julia-1.13 6800be7839: `src/staticdata_utils.c` (the newly-inferred list), `Compiler/src/cicache.jl`, `src/julia.h` (CodeInstance timing fields), `base/loading.jl` (`isprecompiled`, `MAX_NUM_PRECOMPILE_FILES`).

The user's question: "Is it the final shape we want? Does it operate at the right level of granularity? I don't necessarily want changes to the cache right now, but i want to understand its tradeoffs." So this is an analysis, not a change list. Where something is a defect of the prototype, it says so; §8 lists those apart from the user's decisions.

---

## Summary for the user

- **It works and it pays.** Off-workload sessions: D 2.4 → 1.07 s, C 19.4 → 6.1 s (E-180). What it keeps is the right content: every CodeInstance of both owners that names no type of the session, and the first-call checks.
- **Grouping by dependency set is the right key, but a package image is too costly a unit to load.** Each part costs about 8 ms whatever it holds; its content costs about 16 µs per entry. In C, the fixed cost is about 87% of the parts' 0.41 s. The 24 parts with fewer than 10 entries hold 2% of the entries and take 44% of the time.
- **Its lifetime is too short and unbounded at once.** The key is the whole environment: any project or manifest change starts an empty cache. The old cache stays on disk (C: 87 MB of images, 9 MB of store), and nothing evicts it.
- **Correctness rests on Julia's validation of images,** as for any package image (G1). A session with the cache can still differ from one without in three places: strict mode's refusals (M1, open), first-call check warnings (shown once, then silent), and values decided by inference (G1's standing exception, which now depends on earlier sessions).
- **Trait-specific:** facts code can load early and survives later loads (E-177: 0.02 s against 6.1 s recompiled). Plain code is better loaded late. On the other side, facts code needs extra machinery (two owners, the checks, exact types). In the small pairs, plain code with a cache was as fast or faster.
- **Not yet the final shape.** Close to final: what is kept, and how it is validated. Prototype-shaped: one generated package per dependency set, the per-environment key, and the builder's triggers. Seven decisions for the user are in §8.

---

## 1. Granularity of grouping

### As built

- An entry's packages: its method's module, its signature's types and its edges' methods' modules (M3), without Core and Base (`cache.jl:129–170`).
- These are reduced to the packages no other in the set depends on (the antichain, from the images' headers, `cache.jl:304–338`). Each antichain gets one part.
- A part loads in TraitWorld's package callback once all its antichain packages are loaded (`cache.jl:78–114`).
- A part's name hashes its antichain and its entry set (`cache.jl:384`). So a new entry makes a new part, which is built whole.

### What the measurement says

C: 45 parts, 3,418 entries (`logs/e180c/parts.log`; the workload's packages loaded first, then each part in turn):

| | Parts | Entries | Freshness check | Load |
|---|---|---|---|---|
| all | 45 | 3,418 | 75 ms | 340 ms |
| fewer than 10 entries | 24 | 78 (2%) | 40 ms | 142 ms |
| 100 entries or more | 10 | 2,988 (87%) | about 17 ms | 124 ms |

- A least-squares line over the 45 parts gives a load of about 6.3 ms plus 16 µs per entry. With the freshness check (median about 1.6 ms), that is **about 8 ms fixed per part**. At C's size the fixed part is about 0.36 s of 0.41 s.
- The per-entry cost follows the edges to validate, not the entry count. LinearSolve's 105 entries take 24 ms; the Base-only part's 700 entries take 9 ms. At load Julia validates about 1.3 µs per edge (E-169: about a million edges in 1.3 s).
- The fixed cost probably grows with the part's dependency closure. Each image's header lists every module loaded while it was built, and loading checks each one: {LazyArtifacts} with 1 entry loads in 3.7 ms, {OrdinaryDiffEqCore, ForwardDiff} with 1 entry in 8.2 ms. This is not measured apart.
- **Against compiling** (rough: C's off-workload session less its load, about 15 s, over 3,418 entries): about 4 ms per entry compiled, against about 16 µs per entry loaded. A part's fixed cost equals compiling about two entries.
- D: 5 parts in 0.15 s, about 30 ms a part, three times C's per-part cost. Not diagnosed.

### The options

| Grouping | Parts at C's size; load (from the fit) | Laziness | One package changes | Builder | Load order | Extensions |
|---|---|---|---|---|---|---|
| **Per dependency set** (built) | 45; 0.41 s | exact: a part waits for its set | the parts whose closure holds it go stale | one process per part, each loading its closure: 174 s first | independent by construction | the part waits for the extension module itself |
| Per environment | 1; about 0.06 s | none: it must import every package any session used, so loading it loads them | everything | one process | fixed | all at once |
| Per top-level package of the project, plus pairs | a handful | at `using` granularity | as now, coarser | few processes | independent | pairs and extensions stay separate parts |
| Per load step (what one `using` brought) | 2–3 | by step | as now | few | **order-dependent timing**: a part recorded as {Tsit5, Rosenbrock, CairoMakie} waits for CairoMakie in order B, so the first solve compiles | as now |
| Merge small parts into a covering part | 5–10; about 0.1–0.15 s | entries move up the dependency order and arrive later, or never if the covering set never loads | as now | fewer processes, larger rebuilds | independent; the timing of moved entries changes | as now |
| A threshold on value | fewer | as now | as now | as now | independent | as now |

Notes on the rows:
- **Per environment** is not acceptable as a unit that is loaded. Loading it changes the session's world: other packages' `__init__`s, extensions, pirates. It survives only as a system image (§3).
- **Per top-level package** converges to the covering merge. Entries for a dependency used alone (`using ForwardDiff`), and for packages loaded at first use (the memo's stubs, §1.4), need parts of their own anyway.
- **Per load step** brings back the combination caches' load-order dependence, for timing only; correctness is unaffected.
- **Covering merge:** the best cover is the set that co-occurred with the part's packages in the recorded sessions. The records do not keep which packages a session loaded; they would have to. Example: {OrdinaryDiffEqCore, ForwardDiff} (1 entry) into {OrdinaryDiffEqRosenbrock} (571 entries), whose closure holds both.
- **A threshold on entry count** is the wrong measure, because entries are not equal: one entry can be a 1-second keyword path. A threshold on value is better. CodeInstances carry their inference and LLVM times (`time_infer_total`, `time_compile`; `julia.h:497–500`). The builder can keep a part when the time it saves exceeds its cost, about 8 ms.

### The considerations

- **Load per part against per entry:** at C's size the parts' count decides, not their content (above). A store ten times larger would add about 0.5 s at 16 µs per entry. At that size eviction matters too (§4).
- **Laziness:** a session pays for every entry of every part whose set it loads. A session that loads CairoMakie and draws one line loads every Makie entry ever recorded. That is cheap while the store is small.
- **Staleness:** the key already holds the manifest, so a package update resets the whole cache (§4). Fine grouping contains staleness only for dev'd packages and TraitWorld's own edits. A part's image depends on every module of its closure, not only on its antichain: a part under CairoMakie goes stale when any of about 260 packages changes.
- **The builder's time:** one process per part, each loading its closure: 174 s for 45 parts in C (about 4 s each), against about 15 s compiled in the session. Fewer parts mean fewer processes. But the names hash the entry set, so with bigger parts each new entry rebuilds more. D's increments: 2.5–5.2 s for 1–3 parts.
  - The usual answer to this conflict: new entries go to small delta parts, and a compaction merges them into large parts when enough have accumulated (a log-structured merge). It trades a few more parts at load for cheap builds.
- **Order independence:** it holds by construction (E-180: D/pkb 1.05–1.11 s against D/pk 1.06–1.08 s). For timing it is approximate: an entry's dependency set comes from its edges, and those depend on the method table at the time it was compiled. An entry recorded in order A with an edge into a Makie method waits for Makie in order B. D/pkb's first solve takes 0.13–0.18 s against 0.093–0.097 s.
- **Plain against facts entries:** for plain code, the time of loading matters.
  - Loaded early, plain code is exposed to every later load's invalidation. Loaded late, it is validated against the fuller method table and survives.
  - Facts code does not care (G2).
  - The Base-only part (700 entries, no packages) loads at TraitWorld's own load, the earliest possible point, so its plain entries are the most exposed.
  - E-180's "220–280 signatures compiled again in each session" fit this in part; they are not diagnosed.
  - So the best grouping differs by owner: facts code by its dependency set, as early as possible; plain code by its context (the packages loaded when it was compiled), as late as needed. That is the combination caches' idea without their order key.
- **Extensions:** handled. A part's set may hold an extension module; the part imports the parent and the triggers and waits for the extension itself. The remaining issue is variants of one signature (§5, item 4).
- **Entries that cannot arrive in time:** code compiled during the load itself waits in a part for packages that are still loading: a package's `__init__`, or TraitWorld's callback before its own part loads (E-180 names the latter). Such entries cost build and load time and save nothing. Their place is the package's workload. The recorder could report them instead of keeping them.
- **Demand loading** is a further option, and it needs a Julia change. A hook at a compile miss would look the MethodInstance up in an index on disk and load its part. Only the parts a session uses would be paid for. Parts define no methods, so loading one mid-session is benign; loading inside the compiler's locks is the risk.

**Assessment.**
- The dependency set is the right grouping key for facts code.
- A package image is the wrong loading unit for small groups. There are two ways out:
  - merge parts by a cost model (covering parts, a threshold on value, compaction), with no Julia change;
  - a cheaper unit: one image with a section per set, or demand loading, both Julia changes (§3).
- Merging C's parts into 5–10 would bring them to about 0.1–0.15 s (from the fit; not measured).

---

## 2. Granularity of entries

**(a) CodeInstances of every owner, compiled again in the part's build from their owner and signature (built).**
- What it gets right:
  - It is complete: callees keyed on library types are kept even when their root names `Main` (the earlier review's B1).
  - The session's content cannot leak into an image. The builder's world has no `Main`, so the earlier review's m1 is solved by construction.
  - The parts are validated as any image is.
- What it costs:
  - **Inference and code generation run again in the builder:** 174 s against the session's 15 s for C.
  - **Not every signature compiles as written.** In E-175 `precompile` refused 10–25% (D 997 of 1,226 accepted; S 2,808 of 3,349). The facts replay needs exactly one matching method (`cache.jl:446`). A refused entry is dropped silently and compiled in every session.
  - **The builder's code is not the session's code.** It is inferred in another world: fewer packages loaded, no `Main`. Validation keeps this safe, but values decided by inference may differ (§5, item 3).
  - **An entry's identity is (owner kind, signature)** (`cache.jl:172`, `:181`). Its dependency set is not part of that identity, so two variants of one signature share one hash (§5, item 4).

**(b) Compile roots only** (E-172; failed, the earlier review's B1).
- A root that names `Main` takes every callee below it, even callees keyed on library types.
- A corrected form keeps the frontier: the CodeInstances that name no session type but whose caller does. Inferring the frontier again derives the callees.
- It gives fewer entries for the same coverage, but nothing at load, because the parts hold the same callees and edges. The store is small anyway (C: 3.9 MB). Not worth it.

**(c) The session's own code written out (a Julia change).**
- What it gets right: no inference again, no refused signatures, every owner native, exactly the code the session ran.
- What it needs:
  - inferred IR kept in sessions (memory), or object code emitted at exit;
  - an image writer in a process that does not generate output;
  - m1's filter over the whole CodeInstance: IR, constants, fold records, edges into `Main`.
- Exit gets slower unless the work is handed to another process.
- Fidelity to the session cuts both ways. The session's code was compiled in a world with `Main`'s methods; validation at load discards what depended on them.

**(d) Method-level or module-level units.**
- Both collapse to dependency sets. Where code can be loaded is decided by the types in its signature and the methods its edges name, not by its method's module.
- They are useful as a reporting unit: which package's workload misses what.

**Shapes** (E-178).
- Entries are exact types. SciML's solver is keyed on the call's shape, so a cache from `Tuple` parameters does not serve vectors (3.7–4.5 s compiled).
- The granularity a user sees is the library's key granularity. Recurrence is the library's job (entry normalization; W-63's parameters in the outermost layer), not the cache's.

**Assessment.**
- The CodeInstance level is right.
- Two refinements:
  - put the dependency set into an entry's identity;
  - keep each CodeInstance's measured inference and compile time with it, so that the builder can weigh entries and parts.
- (c) is a question about the vehicle (§3), not about the entries.

---

## 3. The vehicle

| Vehicle | Build cost | Validated at load | Needs from Julia | Laziness |
|---|---|---|---|---|
| **Generated packages and a background builder** (built) | per part, a process that loads the part's closure, infers again and generates code: C 174 s the first time, D 27 s; D's increments 2–5 s | image staleness (the header: every module of the closure by build id, flags, preferences, `entries.jls` by modification time); edges; fold records (compiler §4.4); TraitWorld's hook and `__tw_checked__` | the facts owner and `typeinf_ext_toplevel` with an owner (patched); keep-compiled (patched, compiler §2.9), since all of a part's code is external; otherwise stock loading, through internals (`LOADING_CACHE`, `EXT_PRIMED`, `parse_cache_header`, `pkgorigins`, `compilecache`) | per dependency set |
| **Julia writes the session's CodeInstances into an image at exit** | code generation only, or none if object code is kept | the same | a new writer path, IR kept in sessions, m1's filter | one image per session, so it must be split per set too |
| **An incremental system image** | a full build per environment change; E-170: more than 38 GB, not buildable here for the stack | none: no activation and no validation, the two thirds of the load (E-169) | PackageCompiler, or a background environment image (open issue 73) | none: everything loads at startup, which changes the world of sessions that would not load Makie; dev'd packages cannot be in it |
| **Julia's package images extended** | putting session code into a package's own image changes its build id, and every dependent image goes stale: a cascade of rebuilds | the same as images | so it must be a sidecar per package or per trigger set: what the parts are | per sidecar |

- **The generated package is the right first form** (the note's §5 question). It uses validation that already exists, and it was built in a day.
- **The probable final form is a sidecar image managed by Julia:** images per dependency set, loaded by `require` itself, possibly several sets per file.
  - It would remove most of the per-part overhead (up to about 0.36 s at C's size) and the use of loader internals.
  - Writing the session's own code (row 2) is a separate, later gain in build time and fidelity. The load does not need it.
- **The system image** is the only vehicle that also attacks open issue 73. It fits a fixed deployment (a lab's environment), not a user's changing one.
- **A small gain within the prototype:** a part's freshness is checked twice. `isprecompiled` (`loading.jl:1975`) runs the full search for a fresh image, and `require` runs it again (`cache.jl:95–97`). Loading the path found the first time would save about 0.075 s at C's size.

---

## 4. The key and its lifetime

**As built** (`cache.jl:28–41`): a hash of the Julia commit, the system image's path and modification time, and every load-path environment's `Project.toml`, manifest and `LocalPreferences.toml`.

**Covered:** preferences and stacked environments (the earlier review's m2), and the setting (through the system image).

**When an environment changes slightly:**
- Any byte change in any project or manifest of the load path makes a new key with an empty cache. That includes `Pkg.add` of an unrelated package, an update of one leaf, or adding Revise to `@v1.13`; the last resets every project's cache.
- **Nothing is rebuilt from the records.** Records and the store live under the old key, and the new key does not inherit them. Everything is lost, not rebuilt.
- **The old key's files stay:**
  - The images live in `<depot>/compiled/v1.13/TWC_*`, outside the key's directory, so deleting a key's directory orphans them.
  - C's cache: 87 MB of images (45 parts; the smallest image about 0.42 MB, so the 24 tiny parts take about 10 MB) and 8.6 MB of store and sources.
  - Growth is linear in what sessions compile, about 25 KB per entry.
  - Neither the cap nor the least-recent eviction of the note's §3 is built; §7 does not say so.

**Two ways to survive a change:**
1. **Seed a new key from the previous key of the same project, and replay.** Entries that no longer apply fail at replay and are dropped; the replay already handles that. Cost: one full build after each change (C: about 3 minutes in the background). Each package update triggers rebuilds of Julia's own images downstream anyway.
2. **Address parts by their closure's build ids**, which is what Julia's staleness check already compares, with a store per Julia build.
   - A part survives an update that does not touch its closure.
   - Parts are shared across environments with the same subtree, as package images are.
   - It needs more machinery, and eviction must then be global.

**Not in the key:** command-line flags (`--check-bounds`, `-O`) and TraitWorld's environment variables. Images catch these as staleness, not as wrong code. But a stale part is not rebuilt (next item).

**Defect: a stale part is not rebuilt until a new entry appears.**
- `_cache_at_exit` starts the builder only when there are new entries (`cache.jl:251`).
- A session that skipped stale parts compiles their code again, but those entries are already known, so nothing is new.
- After an edit to a dev'd package, or a rebuild of TraitWorld, the cache stays stale until some new shape is recorded. The session counts stale parts (`:stale`), but the count starts nothing.

**The project:** the key is computed at TraitWorld's init, and the builder runs with the active project at exit (`cache.jl:265`). A session that activates another environment after loading TraitWorld records under the first key and builds with the second project. This is rare today; it is common once TraitWorld loads from a startup file.

**Eviction needs a signal.**
- Julia records no hits for loaded code, so per-entry recency is not observable.
- Per part, "loaded in the last k sessions" is observable: each session knows which parts it loaded.
- Per key, the time of the last load of its index is observable.

**Builder triggers:**
- Any new entry starts a build at exit. D's build log shows four builds as its store grew (1,270, 1,281, 1,297, 1,328 entries).
- The note's "only when enough new signatures have accumulated" is not built.
- A background build overlaps the next session. E-180 measured with synchronous builds, so the contention a user would meet is unmeasured.

---

## 5. Correctness and the design's guarantees

### What holds

- **G1.**
  - Parts are package images, and their code is used only after Julia's validation: edges against the session's method table, and fold records (compiler §4.4).
  - Parts define no methods: only `COUNTS` and `__tw_checked__`. So loading one adds no dispatch and invalidates nothing.
  - Normally a part loads no package: it waits for its whole antichain, and it imports those packages or, for an extension, its parent and triggers.
- **Order independence of facts code:** as for any image (facts §11, "When it stays valid"). Shown in E-177 (the split emulation) and in E-180 (D/pkb).
- **Code naming a session's types:** dropped when recorded (`cache.jl:194`). The builder infers again in a world without `Main`, so no session content enters an image.
- **M2:** the cache is off in a process that generates output (`cache.jl:44`). The builder runs with `JULIA_TW_CACHE=0`. Each part is compiled in its own process, which loads only the part's imports.

### Where a session with the cache can differ from one without

1. **Strict mode (M1, open).**
   - The prototype refuses a pirate that would win at a fact of loaded trait code. With a cache, more facts code is loaded before the pirate arrives, so the refusals depend on earlier sessions.
   - E-180 checked one example: the same 5 of 5 checks.
   - Under the intended design (facts §10.3: an error at an image's validation, naming the pirate), a pirate loaded before a part would raise when the part loads. The cache would turn a clean session into an error.
   - The earlier review's rule ("cached code is evidence, not a contract": a pirate that breaks only cached facts discards that code, with no error) needs a sentence in the reference. Strict mode must then tell cache images from package images.
2. **First-call checks.**
   - `_check_once` records a signature once the fully-typed check returns, including when it only warned (`checks.jl:394`; `concrete.jl:531–550`). The builder keeps that signature as checked ahead.
   - Later sessions skip the whole check (`checks.jl:383`). So a `@warn_not_fully_typed` warning appears once per environment, then never again.
   - Also skipped:
     - a stricter level set in a later session (`fully_typed_level`);
     - the scan for overrides that every first-call check runs (`_refuse_overrides`).
   - A check carries no edges, so unlike code it is not validated again at load.
   - Package images keep checks with the same meaning, but only for their workloads' signatures, which their authors chose. The cache extends this to every signature any session ran.
3. **Values decided by inference** (G1's exception: `return_type`, `promote_op`, the element types of empty containers).
   - A cached CodeInstance carries the answer inferred in the builder, in another world and another order of inference.
   - Plain Julia already varies here. The cache makes the answer depend on what earlier sessions compiled.
   - E-180's outputs were identical in every D setting; no test targets this case.
4. **Variants of one signature.** The first recording decides:
   - Recorded with an extension loaded (DiffEqBaseForwardDiffExt, M3): the part waits for the extension, and sessions that make the call before the extension loads compile it every time.
   - Recorded without: the code is invalidated when the extension loads (a stakeholder's change), compiled again, and never recorded, since it is known.
   - Either way one variant is cached and the other compiled in every session. It is never wrong; it is a steady miss.
5. **Visible side effects.**
   - `TWC_*` modules appear in `Base.loaded_modules`. That shows in tools that walk the loaded modules: Revise, Aqua, `Test.detect_ambiguities`.
   - One TraitWorld package callback runs per part. `_bump!` moves the generation each time, and `_report_refused_at_load` runs.

### Where it can make a session slower

- **The parts' load:** paid when their packages load, whether or not the session uses the code. C 0.45 s, D 0.15 s. The memo's §2.1 budgets 0.10–0.15 s for the parts, a figure stale against E-180.
- **Plain entries loaded early** (the Base-only part, at TraitWorld's load) and invalidated by later loads.
- **Recording at exit** (0.09–0.13 s).
  - It grows with the session's compiled volume: `_cache_entries` walks every CodeInstance inferred since init.
  - A session that does not exit cleanly, such as a killed notebook kernel, records nothing.
- **The background builder** competing with the next session (unmeasured; §4).
- **Stale parts:** their freshness check is paid and nothing loads, until a rebuild that is not triggered (§4).
- **Prototype defects, small:**
  - `test/cache.jl` deletes its cache directory but not the part images it leaves in the user's depot (`<depot>/compiled/v1.13/TWC_*`).
  - Part names are content hashes, so they can coincide across environments, and the builder's clean-up deletes `compiled/v1.13/<name>` whole (`cache.jl:430`). It could delete another environment's image of the same name.
  - The lock is broken after an hour (`cache.jl:295`). A first build longer than an hour would run twice, and a dead builder blocks builds for an hour.
  - `known.txt` is written in place rather than renamed (`cache.jl:424`), so a session may read it half-written. The effect is harmless duplicates.

---

## 6. Trait-specific against plain

**What the trait world makes better:**
- **Early and durable at once.** Facts code may load as soon as its packages are loaded, and it stays valid through later loads (G2). That makes one cache per environment, with no order key and early loading, consistent.
  - Plain code is valid at load, but later loads invalidate it. At scale (E-177), the plot after a late DataFrames load recompiles 6.1 s with Makie plain, with or without a cache, and 0.02 s with Makie compiled by facts.
  - This is the cache's trait-specific value: the code it brings stays.
- **Keys free of the user's types.** `Dynamic` positions and declared implementations keep the user's types out of deep keys, so more of a session's code is cacheable and recurs (D's second model). Plain code does this by hand: Dp's FunctionWrappers, SciML's `AutoSpecialize` (E-175).
- **A possible gain at load (open issue 73's lever, not built).** Facts parts could skip edge validation under strict mode. Their facts break only by stakeholders, who are fixed by the key, or by winning pirates, which are refused. That would take most of their per-entry load away. One exception stays: a stakeholder's extension activated by another package (facts §2.2).

**What it makes worse:**
- **Two owners.** Base methods reached from both modes are cached twice (C: 2,485 facts and 1,496 plain CodeInstances, E-178): larger parts and longer builds.
- **Machinery just to reach parity:**
  - the facts owner's replay;
  - exact types (trait objects print by bound and key);
  - the checks kept as checked ahead. Without these, trait code pays inference per signature in every session (M5), and the cache helps plain code more.
- **Questions plain Julia does not have:** strict mode (M1) and the checks' meaning (§5).
- **A TraitWorld callback per part.**

**What is measured:**
- With a cache, the plain twins are faster: Dp 0.64 s against D 0.97 s (E-175). The traits' second-model advantage vanishes with a cache (Dp 0.04–0.05 s).
- The trait-specific gain under late loads is shown at scale (E-177, `all`) and at small scale (E-177: after a late load the plain twins recompile 0.04 s, the trait code nothing).
- There is no Dp measurement with the mechanism, only with the emulation. The mechanism lives in TraitWorld, so a plain stack without TraitWorld gets nothing from it.

**The mechanism itself is not trait-specific.** It records the plain code of every package. Its trait-specific parts are four:
- the facts replay;
- the checks;
- the absence of an order key, which G2 justifies for facts code only;
- strict mode.

So it is either a trait mechanism with plain code as a guest, or a general mechanism with trait hooks (§8, decision 6).

---

## 7. Is this the final shape?

**Close to final; could go into a reference as stated:**
- **What is kept:** CodeInstances of both owners whose method and signature name no type of the session, compiled again in a clean build; and the first-call checks that passed.
- **How it is used:** as package images, validated at load as any image is; never loaded while generating output; never compiled in a session.
- **When facts code loads:** when its dependency set is loaded.

**Expected to change before it is the design:**
1. **The loading unit.** A cost model: a part's value, from its CodeInstances' own timing fields, against about 8 ms per part. Covering merges, delta parts and compaction; or a multi-set image.
2. **An entry's identity:** with its dependency set.
3. **The lifetime:**
   - a store that survives environment changes (seeded and replayed, or parts addressed by their closure);
   - eviction per part and per key;
   - images removed with their key.
4. **The builder's triggers:** a threshold of new entries, stale parts, idle time; and a rule for overlap with the next session.
5. **The checks:** which are kept (clean passes only?), and which session settings run them again.
6. **Strict mode's rule for cache images** (M1).
7. **Where plain entries load:** late, by their context; or the exposure is accepted and stated.
8. **What is skipped is reported,** not kept: entries needed during loads, replays refused. They are candidates for workloads.

**Incidental to the prototype:**
- generated packages in an implicit environment pushed onto `LOAD_PATH`;
- the reset of `LOADING_CACHE`;
- `isprecompiled` before `require`;
- `TWC_` names by hash;
- the one-hour lock;
- the serialization formats;
- the `JULIA_TW_CACHE*` variables;
- the builder detached by `run(detach(…))`.

**The references it would change** (the note's §3; with each, a status of Planned and a deviation table for the generated-package form):
- lowering §15 (a third source of code compiled ahead: from sessions);
- lowering §16 (recording at exit; loading in the callback);
- lowering §14 (checks kept from sessions);
- facts §11 (cache images; "When it stays valid" applies to them);
- facts §10.3 (M1's rule);
- compiler §2.9 (images of external code for another owner, from a list).

---

## 8. Decisions for the user

1. **Adopt it into the design now, or keep it an experiment** until open issue 73 (the load) has a lever? It adds to the load by construction: C 0.45 s today, about 0.1–0.15 s merged (estimated).
2. **Lifetime:**
   - reset at every environment change, as now: simple, and everything is lost at `Pkg.update`;
   - or survive changes: replay the store into the new environment; or key parts by their own dependency closure, shared across environments.
3. **Strict mode with a cache (M1):**
   - cached code as evidence: a pirate that breaks only cached facts discards that code, with no error, so refusals are as without the cache;
   - or as a contract: refusals depend on what earlier sessions compiled.
4. **Checks:**
   - May a check that warned be kept, so that its warning shows once per environment, or must warnings repeat in every session?
   - Does a stricter fully-typed setting in a later session check cached signatures again?
5. **Budgets and default:**
   - the cache's load (C 0.45 s);
   - disk per environment (C 96 MB);
   - background CPU (C 174 s for the first build) on a user's machine;
   - on by default, or opt-in.
6. **Where it lives:**
   - in TraitWorld, which then caches every package's plain code too;
   - or as a general mechanism (in Julia, or a package of its own) with trait hooks: the facts replay, the checks, strict mode.
7. **The vehicle's future:** whether to invest in a Julia change: sidecar images loaded by `require`, several dependency sets per file, later the session's own code written out. It shares work with open issue 73's loader levers.

**Choices an agent can make and record as its own** (CLAUDE.md, "a choice an agent made while building"):
- the merge policy and its threshold;
- eviction's parameters;
- the builder's triggers;
- the stale-part trigger (§4);
- the double freshness check;
- the variant identity (§5, item 4);
- the test's leaked images.

**Stale copies seen** (CLAUDE.md, rule 2), for whoever applies this review:
- the memo's §2.1 row "the cache's parts 0.10–0.15 s" against E-180's 0.45 s for C;
- the note's §3 "only when enough new signatures have accumulated, with a cap and least-recent eviction", which §7 does not mark as not built.
