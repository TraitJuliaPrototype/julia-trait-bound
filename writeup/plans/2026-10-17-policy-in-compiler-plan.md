# Plan: the facts policy in Julia's compiler

Written 2026-10-17 (session 28), on the user's direction: pivot from the policy as an external interpreter (TraitWorld's `FactsInterp`) to the policy in Julia's compiler, behind a switch. "Measure how much performance (A) loses in plain Julia before committing to (B). If the cost is a few percent on typical code, we can defer (B) and reasonably test policy+Traits vs plain Julia. If this work enables it, also back out previous changes to Julia that are currently in the patch."

Background: `../explorations/dataframes-port-lessons.md` §5 (what the compiler would remove), `../explorations/julia-support.md` (the patch, pieces 1–17), `../notes/3-wrapping.md` (rule R, rule P, G1, G2).

## 0. The three parts and the switch

| part | what it is | needed for |
|---|---|---|
| **(A)** | facts as a mode of Julia's own inference: a call is inferred, with edges, only at a fact signature (a dispatch tuple, its union splits, and since session 28 the splits of unions of concrete elements in tuple arguments, `_fact_splits`); every other call is plain dynamic dispatch, typed `Any`; compile-time evaluation only where facts or Julia's own asserted effects allow it (lesson 1.2); `return_type` answered as TraitWorld answers it now (plain inference's answer when it rests on concrete facts, else at run time) | both settings |
| **(B)** | a second cache owner in the runtime: the same method instance compiled by facts and plainly, side by side | policy for trait-bound code only |
| **(C)** | owner-aware dynamic dispatch: a run-time site in fact code selects fact code (what `_call_under_policy` and the per-site caches imitate) | policy for trait-bound code only |

The switch: `--compile-by-facts=no|all` with (A) alone; `traits` added only if (B) and (C) are built. With (A) and `all`, there is one owner: no `FactsOwner`, no trampolines, no per-site caches. TraitWorld keeps the trait language (`@trait`, `@implement`, definition checking, rule 3, `Dynamic`, strict mode) and compiles workers natively, as it does today for a closed world (`FACTS[] = false`).

## 1. Stage 0: wrap up the DataFrames port (session 28)

- Done: the session measured on the image after TraitWorld 5b50482 and 9ddd4a0: 1.19 s excluding imports (upstream 10.9 s, pandas 0.32 s), imports 3.0 s (lessons 1.9).
- The lessons file updated with the measurement; forks, TraitWorld and the lessons committed.
- The forks stay as they are: the regression benchmark for every later stage (upstream packages unmodified in `env_upstream`, the forks in `env_forks`).

## 2. Stage 1: (A) as a forked `Compiler` package (no Julia rebuild)

Julia 1.13 ships the compiler as a package (`julia-1.13/Compiler`, uuid `807dbc54…`); `Compiler.activate!(codegen = true)` bootstraps a loaded copy and makes it the compiler for all new compilation in the session (`Compiler/src/bootstrap.jl:83`).

1. **`FactsCompiler`:** `Pkg.develop` a copy of `julia-1.13/Compiler` (same name and uuid, in `experiments/factscompiler/`), with a mode flag in `InferenceParams` (`facts::Bool`, from an environment variable for the prototype).
2. **Port the rules from `TraitWorld/src/facts.jl`** as edits of the native interpreter, gated by the flag:
   - `find_method_matches`: `_fact_sig` and `_fact_splits` (the union-split path checks every split; a non-fact signature gives the failed match that makes the call a dynamic one);
   - `concrete_eval_eligible`: no evaluation over callees with dynamic calls, except methods of Base and Core whose effects Julia asserts foldable;
   - `return_type_tfunc`: own answer when concrete; else plain inference's answer at the signature (inference with the flag off, no code generated) when its edges are concrete facts (`_concrete_deps`); else at run time;
   - nothing else: no IR rewriting, no owner, no trampolines.
3. **The compiler's own code** stays compiled as it is (it runs in `jl_typeinf_world`; the bootstrap infers the compiler with the flag off).
4. **Correctness:** Julia's own test suite in facts mode (`Base.runtests` for core, compiler, arrays, strings, iterators, broadcast, dict, reduce, sorting, missing, dates, show), compared with the flag off; differences are allowed only where values depend on inference precision (A3: `return_type` of empty collections, `Union{}` results); each difference listed. Then the upstream suites of Tables, CSV and DataFrames (from M1, logs in `forks/logs`).
5. **Limitation of this stage:** code already in the system image and in package images was compiled plainly and is used as it is. Every measurement of the cost of (A) is therefore run with `--pkgimages=no` (packages compiled fresh, in facts mode), and the result for Base's own code waits for stage 2.

## 3. The go/no-go measurement for (B)

What (A) costs, in steady state (after compilation), against the same build with the flag off; each a fresh process, `--pkgimages=no` in both columns, one job at a time, niced, five runs, medians, load logged.

- **BaseBenchmarks** (fetched from the registry, as M1 fetched test dependencies): the groups `array`, `broadcast`, `collection`, `dates`, `find`, `io`, `misc`, `problem`, `scalar`, `shootout`, `simd`, `sort`, `sparse`, `string`, `tuple`, `union`. Report: geometric mean ratio per group and overall, and every benchmark slower by more than 20%.
- **Typical package code,** upstream and unmodified:
  - DataFrames + CSV: the demonstrator's session steps run ten times in one process (steady state), and `big.csv` (10⁶ rows): read, groupby-combine, join, write;
  - a SciML ODE solve (as TraitDifferentialEquations' baseline: `OrdinaryDiffEq` `Tsit5` on Lorenz, and a stiff `Rodas5` case);
  - JuliaSyntax: parsing Base's sources;
  - Makie: CairoMakie's PNG of TraitReport (steady state).
- **What (A) gains,** in the same runs: compiled code lost per load over the load matrix of TraitReport (`scripts/invalidated.jl`), and first-call times after loads.
- **Where time goes when slower:** counts of dynamic calls typed `Any` that plain inference typed (a report from the flag: the number of non-fact signatures with a single match, per method).

**Decision rule** (the user's): geometric mean within a few percent (≤ 5%) and no group above 20% → defer (B) and (C), compare policy+traits against plain Julia with the switch at `all`. Otherwise → (B) and (C) (stage 4), or the guarded speculation of lesson 1.5 / §5 first, if the report shows the cost is concentrated in results of abstract calls that plain inference types.

**Result (session 28, `experiments/factscompiler/README.md`):** BaseBenchmarks, 4,342 benchmarks: geometric mean 1.016 overall, 1.064 without `scalar`, 1.060 over benchmarks of 1 µs or more. By group: `io` 1.32 (above the 20% bound), `collection`, `union`, `problem` 1.16, `sort` 1.12, the others within 1.09. 81 benchmarks are more than 2× slower, 14 more than 10×. The tails are three patterns:
- containers of `Any` (calls with an `Any` argument are no facts, though one method matches);
- abstract element types whose methods share a result type (raytrace 3.5×: lesson 1.5);
- small-union broadcasts (5–12×; probably `return_type` left to run time, step 2 of §2.2 not ported yet).

By the rule above, the overall mean passes and one group fails. **Next, before the decision on (B):**
- port `return_type`'s step 2;
- recover `raytrace` and `parse_json` with traits, sealed unions and assertions, and measure each against plain Julia;
- look at the `array/index` range sums (3 → 25 ns).

**Next steps done (session 28, `experiments/factscompiler/README.md`):**
- **`return_type` step 2**, merged over concrete splits: the small-union broadcast goes from 229× to 1.09× plain.
- **The range sums** are harness overhead: the kernel itself is equal in both modes.
- **Recovery:**
  - raytrace with the sealed set written as a `Union`: equal to plain;
  - raytrace with assertions: 2.3×, because the open set of methods prevents the `isa` branches plain Julia emits;
  - raytrace with a trait: no cost from facts, but `Dynamic` dispatch, at about 15–20 ns per call, makes it 3× plain's `isa` branches in a hot recursion;
  - `parse_json` with plain Julia's fix for captured variables: 1.17× the fixed plain code, and faster than the original plain code.

Design consequences for the compiler version:
- ~~Sealed functions and sealed abstract types~~: dropped on the user's direction (open-issues §2.26). A closed contract is a trait, not a sealed abstract type. The prototype's exemption of TraitWorld's machinery (`sealed_call`) is to be replaced.
- **`Dynamic` needs witness tables** (compiled entries per key, carried with the value) before hot loops bounded by traits are competitive. This is the next step (user, session 28).

## 4. Stage 2: (A) in the system image, and the switch

Only after stage 1's measurement supports it.

- (A) moves in-tree (`julia-1.13/Compiler/src`), the flag from `jl_options` (`--compile-by-facts=no|all`, `src/jloptions.c`), and into the package-image cache flags (`Base.CacheFlags`, `loading.jl`), so that images of the two modes never mix.
- A second system image built with the flag on: Base and the standard libraries compiled by facts. Built alone, under the memory watchdog (`experiments/sysimage/build.sh` as the model; a full sysimage build needs more memory than TraitWorld's image).
- The measurement of §3 repeated without `--pkgimages=no` (images in facts mode), and for Base's own code.

## 5. Backing out the patch

With the switch at `all` there is no foreign owner, so the pieces that serve one become unnecessary. Each is reverted in its own commit once TraitWorld no longer needs it, and the TraitWorld tests, the acceptance checks and the forks' session must still pass.

| piece | commits (julia-1.13) | with (A) at `all` |
|---|---|---|
| 2 invalidation policy hook, trait-world filter (insertion and load halves) | 4d8eeebc19, fc29488177, 28d71bf9cb, f1cf1efa1c, b058af111e, 280612ed2f, fac46840b8, ed4a6adb34, c255d80b24 | **revert:** rule P already skips nothing; opt-in today |
| 4 post-inference hook | 87dcf22015 | **revert:** the native compiler is the policy |
| 5 machine code for upstream and foreign CodeInstances in images | 9af2f27786 | **revert the foreign half;** check whether plain images already keep native code for upstream instances compiled by a downstream package's workload, and keep the upstream half only if not |
| 9 owner-aware bare MethodInstance edges | 5b5b98758f | **revert** from our build; stays an upstream bug report (other foreign owners: GPUCompiler) |
| 10 the inliner uses the CodeInstance it is given | f72f7368f0 | **revert** from our build; upstream bug report as above |
| 11, 12, 13 | not in the patch | no longer needed |
| 1 method-definition hooks | dda21fe511 | **keep:** strict mode refuses pirates through it |
| 3 field-offset intrinsics | 3133c31c5f | **keep:** independent |
| 17 type printers | db82407fa6 | **keep:** independent |

The patch then is (A), the switch, and pieces 1, 3 and 17. TraitWorld drops `FactsInterp`, `_policy_sites!`, `_call_under_policy`, the site caches, `_invoke_under_policy`, `_owner_invokes!`, the compiler-world machinery and the system-image prototype (`experiments/sysimage`), keeping them only as long as TraitWorld must also run on stock Julia (decision P-b).

If (B) and (C) are built (stage 4), pieces 5, 9 and 10 return in the form the runtime needs for a second owner, and are re-measured then.

## 6. Stage 4 (conditional): (B) and (C)

Sketch only; planned when §3's rule says so. A second owner known to the runtime (a sentinel in Core); the native interpreter compiles in facts mode for that owner when a trait entry asks for it (piece 11's `CompilerPlugins.typeinf` form, now resolvable since one interpreter serves both owners); codegen emits owner-aware dynamic dispatch at run-time sites of owner code (a method-cache lookup as `jl_apply_generic`, then the owner's CodeInstance); the switch gains `traits`.

## 7. Risks

- **R1. The cost of (A)** is the open question, and the reason for §3. Lesson 1.5: results of abstract calls become `Any` where plain inference typed them, and code downstream turns dynamic; keyword calls with union-typed values stay run-time sites (lesson 1.4).
- **R2. Bootstrap.** The compiler compiles itself; with the flag on during the bootstrap it would compile its own code by facts (slower inference). The flag stays off for the compiler's own code; checked by timing inference itself.
- **R3. `return_type` and the A3 differences** are wider for all code than for trait code: Base's `map`, `collect` and broadcast take element types from inference. The tests of §2.4 list them; a difference that changes a printed or returned value in Base's tests is a blocker for `all` as a user setting (it may stay a test bed).
- **R4. Stage 1 sees fresh code only.** The system image's plain code hides part of the cost until stage 2.
- **R5. Memory.** A full system image build in facts mode; one job at a time, under the watchdog; `/tmp` is a tmpfs (clean up killed builds' archives).

## 8. Decisions for the user

- **P-a.** The threshold of §3 (≤ 5% geometric mean, no group above 20%) and the benchmark set.
- **P-b.** Whether TraitWorld keeps its own interpreter for stock Julia after the switch exists, or requires the patched build with the switch.
- **P-c.** Whether `all` is meant as a user setting or as the test bed for the trait setting, should R3 find value differences in Base's tests.

**Answered (session 29, the user; `decisions.md` "Session 29"):**
- P-a: slowdowns are tolerated if redesigning the code with traits recovers them (the application to the threshold is open-issues §1.9).
- P-b: stock-Julia support is dropped; TraitWorld requires the patched build.
- P-c: `all` is a test bed, not a user setting. The user setting is therefore the trait setting, which needs (B) and (C).
- Also: `Dynamic` moves to the compiler directly; the forks are paused.
