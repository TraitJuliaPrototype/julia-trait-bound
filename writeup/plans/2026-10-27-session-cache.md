# A cache that builds up across sessions

Status: **proposal** (2026-10-27, mine; W-58 phase 4, [open issue 72](../open-issues.md#2-design)). Not normative.

Serves: W-58 ([the plan](2026-10-27-ttfx-sciml-makie.md) §5, phase 4); open issue 72; E-172, E-173.

## 1. The question

The user (2026-10-27): "traits gradually built up cache that lasts from session to session is exactly what should help here. The fact that all slowness can be fixed by the right precompilation doesn't really matter."

Code compiled in a session is lost at exit. Package images keep only what precompilation ran. A large library cannot run its users' call shapes in its workload: stock SciML compiles 1.1 s for `solve`'s keywords alone, because its workload calls `solve` without them (E-169). The question is a mechanism that keeps what sessions compile, so that trait code gets faster with use, whatever the workloads covered.

## 2. What is known

- **The key decides what can be kept** (E-172, an emulation by hand). A kept compilation is useful only if the next session asks for the same signature.
  - Stock SciML's solver code carries the user's function type (`ODEFunction{true, AutoSpecialize, typeof(Main.robertson!), …}`). A new session defines a new `Main.robertson!`, so none of the solver's 7.5 s could be kept.
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

## 5. Questions for review

- Is "names only types of packages with images" the right rule for what is kept, or should it be "no type defined in the session"? A package without an image (dev'd, not precompiled) breaks the first.
- Does a cache package depending on many packages force loads the session did not ask for? (The design says it is loaded only when all its dependencies are.)
- What does validating a large cache image cost at load, against compiling its code again?
- Is the facts owner's code enough? Code a trait module calls at run-time sites runs plain code, compiled plainly; is the share large on the workload's path?
