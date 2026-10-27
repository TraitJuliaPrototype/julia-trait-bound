# A cache that builds up across sessions

Status: **proposal, revision 2, built** (2026-10-27, mine; W-58 phase 4, W-62, [open issue 72](../open-issues.md#2-design)): after [the fresh-eye review](../reviews/2026-10-27-cache-and-port-notes.md) (§6) and E-175 (§5b); built in TraitWorld (branch `session-cache`) and measured (E-180, §7). Not normative: the references change when the user adopts it.

Serves: W-58 ([the plan](2026-10-27-ttfx-sciml-makie.md) §5, phase 4); open issue 72; E-172 to E-175.

## 1. The question

The user (2026-10-27): "traits gradually built up cache that lasts from session to session is exactly what should help here. The fact that all slowness can be fixed by the right precompilation doesn't really matter."

Code compiled in a session is lost at exit. Package images keep only what precompilation ran. A large library cannot run its users' call shapes in its workload: stock SciML compiles 1.1 s for `solve`'s keywords alone, because its workload calls `solve` without them (E-169). The question is a mechanism that keeps what sessions compile, so that trait code gets faster with use, whatever the workloads covered.

## 2. What is known

- **Code keyed on library types can be kept** (E-175, an emulation recorded at the level of CodeInstances). A cache from one off-workload session takes the next one: stock SciML and CairoMakie 12.9 → 4.9 s (SciML's `AutoSpecialize` erases the function below `solve`'s entry); the trait demonstrators 2.63 → 0.97 s; their plain twins 1.83 → 0.64 s. What names a type of the user's script cannot recur, and is not kept.
- **A new call shape costs its compilation once** (E-173): a cache from `Tuple` parameters leaves a session with vectors compiling 6.3 s in stock SciML's first solve. Keys recur only where the entry normalizes shapes.
- **Plain code's validity depends on the load order** (the combination caches, session 20; [alternatives](../design/alternatives.md#caches-across-sessions-combination-caches-and-view-caches-removed)): kept, it is validated at load like any image's code, and discarded where another order invalidated it. Code compiled by facts stays valid in any load order of unrelated packages ([facts §11](../reference/facts.md#11-package-images), "When it stays valid"): the design's claim, not yet tested on this path (E-177).
- **Trait code needs three things kept** (§5b): the facts owner's code compiled for that owner, the exact types, and the first-call checks' results.
- **The load remains** (open issue 73): with a cache, every setting's work after the load is about a second or less; the load is 3.7 s for stock. A cache adds to it (D: 0.11–0.13 s).

## 3. The design (revision 2)

**What is kept.** Every CodeInstance a session created after its load, of either owner, whose MethodInstance names no type defined in the session (`Main`, or a module not in an image), together with its owner and its exact types:
- **facts code** is compiled again for the facts owner, so its copies of Base methods are the ones trait code uses;
- **plain code** is kept too: Julia validates it at load, so G1 holds; only its order independence is lost, and a session in another order recompiles what its loads invalidated;
- **the first-call checks** that passed in the session are kept as checks done ahead (`__tw_checked__` in the cache's image), as a package image keeps those its workload ran.
A CodeInstance's validity is its own and its edges': one whose code reaches the user's own methods fails validation at load and is discarded.

**The key.** The environment (the manifest's packages and versions, the preferences that reach them, a stacked environment's layers), the Julia build and the setting. Not the load order. Dev'd packages are keyed by their image's build id: an edit makes a new image and the cache's dependent part stale.

**Where it lives.** Generated packages in the depot, one per environment and dependency set (`<depot>/tw-cache/<key>/<deps>/`):
- the dependency set of a CodeInstance is the set of packages its signature and its edges name, so extensions' code is filed with the extension's triggers;
- each part is loaded by TraitWorld's package callback as soon as all its dependencies are, in whatever order they came;
- **never in a process that generates output:** a package image records every module loaded while it is built, so a cache loaded during another package's precompilation would make that package stale at every rebuild.

**When it is written.** At exit, the session's new CodeInstances and checks are recorded; a builder, one per environment under a lock file, merges them with the earlier records and precompiles the parts that changed, then publishes each image by an atomic rename. A session that starts during a build loads the previous images. The builder runs only when enough new signatures have accumulated, with a cap and least-recent eviction.

**Validation at load.** As any image's: edges against the session's method table, folds against their libraries ([compiler §4.4](../reference/compiler.md#44-compilerfold_call)), TraitWorld's image hook. **Strict mode** must give the same refusals with and without a cache; its prototype reads backedges at each load (traits §10.3), and its intended design at image validation ([facts §10.3](../reference/facts.md#strict-intended)) applies to a cache's images as to any.

**What it would change in the references.** [lowering §15](../reference/lowering.md#15-compiling-ahead-workloads-closed-builds) (a third source of code compiled ahead, beside declarations and workloads), §16 (the session's work: recording, the cache's load), [facts §11](../reference/facts.md#11-package-images) (cache images), [compiler §2.9](../reference/compiler.md#29-what-package-images-keep) (an image of code compiled for another owner from a list, not a workload). Status: Planned when adopted.

## 4. The checks

Done: recurrence and the three requirements (E-173, E-175). Still to run, minutes each:
1. **Order independence**, with the cache split by dependency set: a solver part and a plotting part, the plotting library loaded after the first solve (order B).
2. **The cache's load against its size:** D's cache adds 0.11–0.13 s for about 1,200 signatures; a cache of 10 and 100 times that (E-171's packages, several sessions).
3. **Strict mode with a cache:** the same refusals, and its load cost.
4. **Order independence and a late load, plain against trait code** (E-177; [the direction review](../reviews/2026-10-27-w58-direction.md) 1): the trait-specific test.
5. From the previous review's M9: an owner-aware record for C; the module list of an image built while a cache was loaded (M2).
6. **Reuse across sessions with other shapes** (E-178, done): SciML's solver code is not reused across call shapes (a cache from `Tuple` parameters leaves a session with vectors compiling 3.7–4.5 s), Makie's plotting code is. The cache pays once per shape; the core's entry must normalize shapes (class (f)) for it to recur.

## 5. Questions for review

- Is "names no type defined in the session" enough to make kept code recur, with call shapes normalized only where the core's entries do it?
- What does a large cache cost at load, against compiling its code again?
- Is a generated package the right first form, before a Julia change that writes a session's own CodeInstances into an image without compiling them again?

## 5b. What the emulation taught (E-175)

A cache of trait code must keep three things, each found missing in turn (`experiments/ttfx/README.md`, E-175):
1. **The facts owner's code, compiled for that owner:** replaying a signature by `precompile` compiles plain copies of the Base methods trait code calls; the session needs the facts copies.
2. **The exact types:** trait objects' types print by bound and key, so a cache must keep types, not printed statements.
3. **The first-call checks' results:** a worker kept without its check is checked again, by inference, in every session; the cache keeps the checks as checked ahead, as package images do.

With all three, D's off-workload session with its cache equals its on-workload session (0.97 against 0.96 s).

## 6. The review, and what is done with it

[The review](../reviews/2026-10-27-cache-and-port-notes.md) (fresh eyes, Opus, 2026-10-27):
- **B1** (the emulation kept compile roots only): accepted. §2's first bullet is provisional; E-175 repeats the emulation at the level of CodeInstances, with every owner.
- **B2** (the cache keeps only facts code, while the gains measured are plain code's): accepted, §3 (revision 2).
- **M1** (strict mode's refusals depend on what earlier sessions compiled): open; strict mode's check of a cache image must give the same refusals as without the cache (its intended design at image validation, facts §10.3).
- **M2** (an image records every module loaded while it was built, so a cache loaded during another package's precompilation makes it stale at every rebuild): accepted: the cache is never loaded in a process that generates output.
- **M3** (partitions by signature types miss extensions): accepted: a partition's dependencies are the modules its code's edges name, not only its signature's.
- **M4** (the cache's own load cost, measured and ignored: D's cache adds 0.15 s): accepted; the next quick experiment measures load against cache size.
- **M5** (each cached worker runs TraitWorld's first-call check in every session): confirmed and solved (E-175; §5b): the cache keeps the checks.
- **M8** (the background builder's races and churn): accepted: one builder per environment under a lock file, an atomic rename of the finished image, a rebuild only when enough new signatures have accumulated.
- **Minor:** m1 (the whole CodeInstance, not its signature, decides), m2 (preferences, stacked environments, dev'd edits in the key), m3 ("only its stakeholders' methods" too strong: facts §11's own wording), m6 (the references the note changes): done in revision 2 (§2, §3).


## 7. As built (W-62, E-180)

TraitWorld's `src/cache.jl` (branch `session-cache`), on with `JULIA_TW_CACHE=1`:
- **Recording:** TraitWorld's init switches on the runtime's newly-inferred list (`jl_set_newly_inferred`), which precompilation uses; every CodeInstance cached after it is listed, of every owner. At exit, those still valid, of the default and the facts owner, whose method and signature name no module of the session, are kept with the packages their signature and edges name; with the session's first-call checks.
- **The builder:** started at exit, detached (or synchronously, or not at all); one per environment under a lock file. It merges the records into a store, groups the entries by their packages reduced to those no other depends on (from the images' headers), writes one generated package per group, named by its content, and precompiles each with native code. The index is replaced by a rename; parts no longer listed are removed.
- **Loading:** TraitWorld's package callback loads a part once all its packages are loaded, only if its image is fresh (`Base.isprecompiled`); never in a process that generates output.
- **The key:** the load path's projects, manifests and preferences, the Julia commit and the system image.

What E-180 measured: §2's emulation reproduced (D 2.4 → 1.07 s, C 19.4 → 6.1 s off-workload); order B with a cache recorded in order A; strict mode's refusals unchanged on one example. Not built from §3: the build threshold (the builder runs at every exit that recorded something new) and eviction (nothing is removed but parts no longer listed). Found by [the cache's design review](../reviews/2026-10-27-cache-design.md): a stale part is rebuilt only when a session records something new; an entry's identity leaves out its dependency set, so two variants of one signature (with and without an extension loaded) share one slot. Open: the parts' load (45 parts, 0.45 s for C; about 8 ms a part whatever its size), so coarser grouping; §4's checks 2 (the load against the cache's size) and 5 (an owner-aware record for C: done by recording every owner); the general form of M1 (strict mode's refusals with a cache of more facts code than the session compiled).
