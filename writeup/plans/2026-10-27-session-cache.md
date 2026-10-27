# A cache that builds up across sessions

Status: **proposal, revision needed** (2026-10-27, mine; W-58 phase 4, [open issue 72](../open-issues.md#2-design)): [the fresh-eye review](../reviews/2026-10-27-cache-and-port-notes.md) found two blockers (§6). Not normative.

Serves: W-58 ([the plan](2026-10-27-ttfx-sciml-makie.md) §5, phase 4); open issue 72; E-172, E-173.

## 1. The question

The user (2026-10-27): "traits gradually built up cache that lasts from session to session is exactly what should help here. The fact that all slowness can be fixed by the right precompilation doesn't really matter."

Code compiled in a session is lost at exit. Package images keep only what precompilation ran. A large library cannot run its users' call shapes in its workload: stock SciML compiles 1.1 s for `solve`'s keywords alone, because its workload calls `solve` without them (E-169). The question is a mechanism that keeps what sessions compile, so that trait code gets faster with use, whatever the workloads covered.

## 2. What is known

- **The key decides what can be kept** (E-172, an emulation by hand). A kept compilation is useful only if the next session asks for the same signature.
  - Stock SciML's solver code carries the user's function type (`ODEFunction{true, AutoSpecialize, typeof(Main.robertson!), …}`). A new session defines a new `Main.robertson!`, so an emulation that kept compile roots kept none of the solver's 7.5 s; recorded at the level of CodeInstances (E-175), the code below `solve`'s entry, where `AutoSpecialize` already erases the function, is kept, and the perturbed session falls from 12.9 to 4.9 s.
  - Code behind an erased boundary is keyed on library types and can be kept whole. The plain twins, with `FunctionWrapper`s, fell from 1.83 to 0.70 s; the trait demonstrators from 2.63 to 1.52 s.
- **Plain code's validity depends on the load order** (the combination caches, session 20; [alternatives](../design/alternatives.md#caches-across-sessions-combination-caches-and-view-caches-removed)). Built in one order, a replay kept nothing of Makie's code for a session in another; those caches were keyed by the load order.
- **Code compiled by facts depends only on its stakeholders' methods** ([facts §11](../reference/facts.md#11-package-images), "When it stays valid"). A kept CodeInstance is valid in any load order of unrelated packages, and checked at load like any image's code.
- **Images already keep foreign and facts code** that a package's precompilation compiled, with machine code under keep-compiled ([compiler §2.9](../reference/compiler.md#29-what-package-images-keep)).

## 3. The design

**What is kept.** The CodeInstances a session compiled for owner `:facts` whose signature names only types of packages with images in the environment (and Base). That is:
- no type of `Main` or of a module defined in the session (class (e) of the plan: it cannot recur);
- the code those CodeInstances call, compiled in the same session, under the same rule.

Trait keys put most of a trait library's code in this set: a `Dynamic` model, a `Callable` at a declared signature, a bound's key (the receiver type and declared field types; [traits §6](../reference/traits.md#6-values-in-trait-code-compiled-and-dynamic)). Plain code compiled in the session is not kept: its validity depends on the load order.

**The key of the cache.** The environment (its manifest's packages and versions), the Julia build, and the setting. Not the load order: facts make it irrelevant. A session that loads a subset of the environment uses the part of the cache whose types it has loaded.

**Where it lives.** One package per environment and dependency set, generated in the depot (`<depot>/tw-cache/<environment hash>/`). Its image holds the kept code, compiled by facts.
- It depends on the packages whose types its code names.
- It is loaded by TraitWorld's package callback as soon as all its dependencies are loaded, in whatever order they came.
- A cache whose dependencies never all load in a session is not loaded; partitioning by dependency set keeps the useful parts usable.

**When it is written.** At the session's exit:
- the qualifying signatures are recorded (the session's compile log, filtered);
- a background builder, niced and alone, regenerates the cache package with the union of the earlier signatures and the new ones, and precompiles it;
- the next session loads the new image. A session that starts during a build loads the previous one.
- **First:** replay by precompile statements, as the combination caches did, needing no Julia change.
- **Later:** a Julia change that serializes the session's own CodeInstances into an incremental image, without compiling them again (a session image).

**Validation at load.** The cache's image goes through the same checks as any image: its facts edges against the session's method table, its folds against their libraries ([compiler §4.4](../reference/compiler.md#44-compilerfold_call)), TraitWorld's image hook (overrides; strict mode's refusals). Code whose facts broke is discarded and compiled again in the session, then kept at the next exit.

**Limits.**
- Strict mode's check at load costs seconds today (E-168: 6.6 s for the facts-compiled SciML core). It applies to the cache's image as to any; its intended design at image validation ([facts §10.3](../reference/facts.md#strict-intended)) is a prerequisite for strict mode with a large cache.
- The cache grows. A cap with least-recent eviction, by signature, at rebuild.
- A trimmed build uses no code compiled by facts ([facts §11](../reference/facts.md#11-package-images)); the cache is for interactive sessions.

## 4. The checks before building it (E-173)

Minutes each, on the harness of E-168 (`experiments/ttfx/`):
1. **Order independence:** the emulated caches of E-172, built from sessions in order A (plotting loaded first), used in order B (plotting loaded after the first solve). D's cache should keep its effect; Dp's and S's may lose the part of their code that order B invalidates.
2. **Recurrence:** a cache built from the perturbed session used by the matched one, and the reverse. What carries over is what is keyed on library types only.

**Results (2026-10-27, E-173):** order independence is not tested yet: the emulated caches each depend on the plotting library, so loading one loads it early; the split by dependency set (§3) is needed first. Recurrence: stock SciML's solver is keyed on the call's shape (a cache from `Tuple` parameters leaves a session with vectors compiling 6.3 s); the core's entry should normalize shapes, so that a cache's keys recur.

## 5. Questions for review

- Is "names only types of packages with images" the right rule for what is kept, or should it be "no type defined in the session"? A package without an image (dev'd, not precompiled) breaks the first.
- Does a cache package depending on many packages force loads the session did not ask for? (The design says it is loaded only when all its dependencies are.)
- What does validating a large cache image cost at load, against compiling its code again?
- Is the facts owner's code enough? Code a trait module calls at run-time sites runs plain code, compiled plainly; is the share large on the workload's path?

## 5b. What the emulation taught (E-175)

A cache of trait code must keep three things, each found missing in turn (`experiments/ttfx/README.md`, E-175):
1. **The facts owner's code, compiled for that owner:** replaying a signature by `precompile` compiles plain copies of the Base methods trait code calls; the session needs the facts copies.
2. **The exact types:** trait objects' types print by bound and key, so a cache must keep types, not printed statements.
3. **The first-call checks' results:** a worker kept without its check is checked again, by inference, in every session; the cache keeps the checks as checked ahead, as package images do.

With all three, D's off-workload session with its cache equals its on-workload session (0.97 against 0.96 s).

## 6. The review, and what is done with it

[The review](../reviews/2026-10-27-cache-and-port-notes.md) (fresh eyes, Opus, 2026-10-27):
- **B1** (the emulation kept compile roots only): accepted. §2's first bullet is provisional; E-175 repeats the emulation at the level of CodeInstances, with every owner.
- **B2** (the cache keeps only facts code, while the gains measured are plain code's): accepted. The cache keeps plain code too: Julia validates an image's plain code at load, so G1 holds; only order independence is lost for it, as the combination caches found. Facts code is kept the same way and also stays valid in any load order. §3's rule changes at the next revision.
- **M1** (strict mode's refusals depend on what earlier sessions compiled): open; strict mode's check of a cache image must give the same refusals as without the cache (its intended design at image validation, facts §10.3).
- **M2** (an image records every module loaded while it was built, so a cache loaded during another package's precompilation makes it stale at every rebuild): accepted: the cache is never loaded in a process that generates output.
- **M3** (partitions by signature types miss extensions): accepted: a partition's dependencies are the modules its code's edges name, not only its signature's.
- **M4** (the cache's own load cost, measured and ignored: D's cache adds 0.15 s): accepted; the next quick experiment measures load against cache size.
- **M5** (each cached worker runs TraitWorld's first-call check in every session): to count in E-175.
- **M8** (the background builder's races and churn): accepted: one builder per environment under a lock file, an atomic rename of the finished image, a rebuild only when enough new signatures have accumulated.
- **Minor:** m1 (the whole CodeInstance, not its signature, decides), m2 (preferences, stacked environments, dev'd edits in the key), m3 ("only its stakeholders' methods" too strong: facts §11's own wording), m6 (the references the note changes): accepted for the next revision.

