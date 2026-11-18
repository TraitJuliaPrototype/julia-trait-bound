# Making loads fast

Status: **current thinking, W-47, merged into W-58 on 2026-10-27** ([its plan](../plans/2026-10-27-ttfx-sciml-makie.md)) (started 2026-10-22). An exploration, not normative: it collects what is known about the time from starting Julia to the first result in trait code, where that time goes, and the ways to make it shorter. Numbers are copied from [the evidence](../design/evidence.md) with their experiments; the evidence is their home.

The user (2026-10-22): "Register a larger work item: Make loads fast. This should cover profiling loads and finding ways to make them as fast as possible. Refer to an exploration document that keeps our current thinking on making loads fast. … This work is not urgent for now."

## 1. What a load costs today

"Load" here means everything before the first result: `using`, the checks at load, and the first calls that compile code in the session.

**The NetworkDynamics workload** (tier S; evidence §3, E-151, E-153, E-155, E-165):

| Setting | Loads | First simulation (a–e) | Session |
|---|---|---|---|
| upstream, all plain | 5.4–5.6 s | 21.5 s | 70 s |
| only NetworkDynamics wrapped (N) | — | 37.8 s | 87 s |
| everything compiled by facts, with a facts system image (`all`) | 11.9 s | 23.6 s | 73 s |
| the merged port (E-165), strict mode off | Graphs + ND 2.9 s | 31.0 s | 65.9 s |
| the merged port, strict mode on | Graphs + ND 7.9–8.1 s | 31.0–32.7 s | — |

The merged port wins where a session repeats work: new equations recompile in 0.56 s (upstream 15.6–16.0 s), and the plotting load discards none of the simulation's code (upstream recompiles 4.7 s). It loses on the first simulation, by about 10 s.

**Elsewhere** (evidence §3):
- TraitReport, CSV → PNG in a fresh process: 0.80 s; without traits 0.77 s; Python 0.58 s. The trait form's `using` is 0.18–0.20 s above the plain form's.
- The CSV and DataFrames forks: imports 1.89–1.92 s against upstream's 0.69–1.19 s; the whole session 3.7–4.0 s against 12.0–12.8 s, since the work after the imports is fast.
- An upstream plotting session under `all`: loading CairoMakie 4.9 against 1.9 s (not diagnosed).
- Strict mode's image check at load: about 5 s for the NetworkDynamics stack (E-155, E-165).

## 2. Why code is compiled in the session

**A package image holds the code compiled while that package was precompiled:** its own methods, and what its precompile workload ran, each stored under its owner (plain or `:facts`; [compiler §2.9](../../attic/writeup/reference/compiler.md#29-what-package-images-keep)). Facts code cannot use plain code from an image: whatever facts code reaches is compiled by facts. So the question for each method the workload reaches is whether any image holds a facts version of it, at the workload's types.

- **Under `all`, facts code costs almost nothing extra** (23.6 against 21.5 s): every image, the system image included, holds facts code. The cost is where facts code is cached, not compiling by facts.
- **With only NetworkDynamics wrapped,** its facts code calls SciML, whose images hold plain code only: all of SciML on that path is compiled by facts in the session.
- **The merged port is in between.** The wrapped SciML packages' images hold facts code for their own workloads. Not in any image:
  - **Base and the standard libraries.** In the product setting the system image is plain, so every Base method facts code reaches is compiled by facts in the session. Probably the largest share; not measured apart.
  - **Code specialized on the workload's own types** (NetworkDynamics' network, the user's equations). Upstream has the same gap; its workloads cover more of it through SciML's function wrappers.
  - **`return_type` answers computed at run time** (pushback P6-5): 2,000–2,900 new CodeInstances per step of the first simulation.

**A session's code is not kept.** Stock Julia never saves code compiled in a session: package images are written only by precompilation, are fixed, and are checksummed with their dependencies. Today's ways to keep session code are a precompile workload (often in a small local package that runs the user's workflow) or a custom system image (PackageCompiler).

## 3. Ways to make loads faster, by effort

1. **A facts system image for the product setting.** The image for `all` exists (`julia-1.13/usr/lib/julia/facts/sys.so`). Question: should the product setting ship Base and the standard libraries compiled by facts as well, so that facts code finds them in the image? Measure first (§4).
2. **Precompile workloads that run under facts, in the right package.** NetworkDynamics' workload would cache its SciML-by-facts specializations in NetworkDynamics' image. Ordinary Julia practice, applied to the wrapped stack.
3. **Fewer run-time `return_type` answers** (P6-5): more of them folded by facts §7.1's rules 1 and 2, or kept in images.
4. **Strict mode's image check** (about 5 s): what it checks at load, and whether it can be done when the image is built.
5. **A cache that outlives the session** (now [open issue 72](../open-issues.md#2-design), W-58's phase 4; emulated in E-172, which shows that what can be kept is decided by the code's key; built before for plain code as combination caches, [alternatives](../design/alternatives.md#caches-across-sessions-combination-caches-and-view-caches-removed)). As a Julia change: Facts code is a much better candidate for this than plain code: its validity rests only on facts a stakeholder or a pirate can change, so a saved CodeInstance could be checked against those facts at load and reused. A research-size piece of work; it fits the design's guarantee unusually well.
6. **The cost of `using` itself** for trait packages (TraitReport +0.2 s, the forks' imports +0.7–1.2 s): what TraitWorld does at load.

## 4. Profiling: the first measurements to make

- **Split the merged port's first simulation** into Base by facts, workload-specific code and `return_type` answers: run it once with the facts system image and once without, and count the CodeInstances made in the session by owner and by package.
- **Profile `using`** for TraitReport and the forks: the time in TraitWorld's load hooks, in the image's validation, in strict mode's check.
- **CairoMakie's load under `all`** (4.9 against 1.9 s).

## 5. Open questions

- Does the product setting ship facts code for Base? It changes what "the product setting" means (facts §6; the setting is part of the image's key, open issues §2, F-7).
- A cache across sessions: the cache keyed on facts and their origins, W-66 (closed open issue 72); nothing goes upstream for now (the user, 2026-10-27).
