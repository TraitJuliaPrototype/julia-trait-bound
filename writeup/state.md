# The state of the prototype (2026-10-27)

The prototype works end to end. Traits run at plain Julia's speed for typed calls, and the facts compiler stops invalidation. On the compiler side, the work reduces to four mechanisms, plus hooks for the library and fixes.

For core developers. The design itself is the four [references](reference/README.md), each with a Deviations table; this page summarizes them. The changes to Julia by principle are the [compiler reference](reference/compiler.md), with the inventory in [`design/julia-changes.md`](design/julia-changes.md); the measurements are in [`design/evidence.md`](design/evidence.md).

## 1. Where the project stands

### Traits

The library, TraitWorld, works end to end:
- **The design:** three rules, keys instead of representations, and every value in trait code `Compiled` or `Dynamic` ([traits §6](reference/traits.md#6-values-in-trait-code-compiled-and-dynamic)).
- **`Compiled` and `Dynamic`** (TraitWorld 7fc229c, 2026-10-20; W-4): a value is `Compiled` where the code that passes it knows its type, `Dynamic` where it does not, overridden by attributes on bounds and item parameters and by the casts `compiled_for`, `with_dynamic`, the later cast winning; `Dynamic` is a trait object at an erased key, one worker per key; values carry their attribute through storage (TraitWorld 1d09112, 2026-10-21; W-18): a trait's name in a field or container means `Kept{X}`, one concrete type holding the user's object and its attribute, `Compiled{X}` is a value beside `Dynamic{X}`, constructors never cast, and a struct parameter bounded by a trait keeps the value itself or a `Dynamic{X}` ([traits §7](reference/traits.md#7-kept-values-dynamicx-compiledx-keptx), [§7.4](reference/traits.md#74-a-struct-parameter-bounded-by-a-trait)); `Callable{A, S}` defaults to `Dynamic`; items of collections cross as `CompiledItems` or `DynamicItems`. The demonstrators run on it, `compiled_for` where they loop over a value compiled for its type. Deviations: [traits T-47 to T-50](reference/traits.md#17-deviations), [lowering L-31, L-35](reference/lowering.md#18-deviations); performance gaps where trait code should be as fast as plain code: [W-17](record/todo.md).
- **Beyond the `Dynamic` split, a table** (julia-1.13 711484a23e, the C ABI rule 6d480d0753, 2026-10-21; E-145): a value of a type outside the split's four is called through a table of the call's targets keyed by its type, one probe and an indirect call, no allocation (18 ns per element at 64 implementations, 77 before) ([compiler §4.3](reference/compiler.md#43-what-follows-the-split-the-table-of-a-calls-targets)); `compiled_for` from an untyped caller goes through the table of declared implementations (TraitWorld a747d4a).
- **TraitDifferentialEquations around `ODEProblemTrait`** (e37829f, 2026-10-21; W-2): a problem is any type that implements the trait, TDE's `ODEProblem` the canonical one, its function kept at two struct parameters bounded by `Callable` (W-18); `solve(prob, alg)` the one entry point.
- **BaseTraits** (TraitWorld 9fd18db, 2026-10-20): collection traits for Base's concepts, Base's containers conforming; `Dynamic` holds the user's object (5 ns to make one), the split's candidates in declaration order; a container with untyped items crosses implicitly, by the bound ([traits §7](reference/traits.md#7-kept-values-dynamicx-compiledx-keptx)).
- **Load and first use** (W-58, 2026-10-27; [the plan](plans/2026-10-27-ttfx-sciml-makie.md), [evidence §3](design/evidence.md#3-first-calls-and-sessions)): the trait demonstrators' whole session (load, a non-stiff and a stiff solve, a plot, a second model) takes 0.96 s against Python's 1.45 s; a generated trait world of 4,000 workers loads in 0.30 s and takes a new type in 0.08 s (E-171); compiled by facts, Makie's code survives a later `using DataFrames` (0.02 s recompiled against 6.1 s plain, E-177). Fixed on the way: TraitWorld's hooks compiled at every session's first load (04095fe), `@implement` growing with the library (003ce8f), the facts images' load (julia-1.13 6800be7839, W-59).
- **The demonstrators** pass their suites: TraitDifferentialEquations, TraitMakie, and TraitReport with its packages TraitTables and TraitCSV. The ports of CSV.jl and DataFrames.jl pass their upstream suites (§6.1).

Measured in the round of 2026-10-20 (julia-1.13 3b8085c222, TraitWorld bed3782) unless a row says otherwise:

| Measure | Traits | Plain Julia |
|---|---|---|
| Typed trait call, per call | 0.8 ns | 0.8 ns |
| Untyped trait call, an argument from a `Vector{Any}` (the erased worker's path; E-163, julia-1.13 26a407d988, TraitWorld bbfc130; W-17), per call | 59.9 ns (product setting); 106.2 ns (`all`); 80 bytes | 17.6 ns; 19.6 ns (`all`) |
| `Callable`, `Dynamic` (its default), per call (E-163) | 3.68 ns | a direct call 0.87 ns; a dynamic call at `Any` 21.9 ns |
| `@implement` of a new type, no other packages loaded (E-163) | TraitMakie 46–47 ms; TraitDifferentialEquations 123–125 ms | about the same with big loads before or after; slower than on earlier builds (open issue 71) |
| a new problem type's first solve in TraitDifferentialEquations, timed whole (E-163) | 324–336 ms in every load order: the solver compiled for the new key | — |
| TraitReport, CSV to PNG in a fresh process (E-163) | 0.83–0.86 s | without traits 0.74–0.76 s; Python 0.58–0.59 s |

### Facts

The facts compiler is built, with two settings:
- **The product setting:** only trait modules are compiled by facts.
- **`all`:** everything is compiled by facts. It is the test bed.

Measured in the round of 2026-10-20:
- **Correctness:** the acceptance checks pass, 23 of 23, in both settings.
- **G2 across package loads** (product setting): 0 of 12,368 CodeInstances of the facts owner lost after each of ten loads (`experiments/facts/g2all.jl`).
- **The payoff under `all`:** upstream CSV+DataFrames lose 2 of 3,337 CodeInstances to nine unrelated loads (plain: 561 of 4,684). Their first work takes 516 ms (plain 3,308 ms), and 435 ms after the loads (plain 4,021 ms).
- **The cost under `all`:** the full BaseBenchmarks (4,342) run at a geometric mean of 1.037 against plain, with tails up to 27.8× on containers of `Any`. The quick subset (148, chosen to include the tails) gives 1.710; it is not the average cost.

The details, with every row: [`design/evidence.md`](design/evidence.md).

## 2. The compiler changes as four mechanisms

The patched Julia adds about 1,750 lines in 36 files, in 40 commits on v1.13.2 (with build scripts and the dispatch profiler). Underneath them are four mechanisms.

| # | Mechanism | What it does | What it covers | General for Julia? |
|---|---|---|---|---|
| 1 | **Infer across a call only where a fact holds** | A call is inferred, with an edge, only at a signature that only its stakeholders or a pirate can change. Every other call is a run-time site. | Part (A), `is_fact_sig` | As "a facts mode for the native compiler" |
| 2 | **Each method's code is compiled in a mode decided by the method and the mode that reaches it** | Code compiled by facts and plain code live side by side, with separate caches, edges and images. A trait module's methods are compiled by facts and the compiler's own code plainly, whoever calls them; other methods get one copy per mode that reaches them. | Parts (B) and (C); `leaves_to`; the compiler's never-by-facts flag; inlining from the other owner's cache (piece 10, c7f1eae); edges and image copies for the second owner (pieces 9 and 5, 9892bfc) | As per-method inference modes |
| 3 | **Caches at dynamic boundaries are checked against the caller's world** | A cached dynamic call or `cfunction` pointer runs in the caller's world, as Julia's own caches already do. | The `:caller_world` cfunction convention (piece 18); exact-type and wildcard entries in the per-call-site dispatch cache | Yes |
| 4 | **Two primitives for a specialized path beside a general one** | `known_type` folds to whether inference knows a value's concrete type (GCC's `__builtin_constant_p`, for types). `split_call` splits a call site over registered candidates. | `known_type` (b5bb9ab); part (D) | `known_type`: yes |

Mechanisms 1 and 2 are the facts compiler. Mechanisms 3 and 4 are general improvements that the facts mode made necessary.

## 3. Besides the four mechanisms

- **Hooks for the library:**
  - method-definition hooks (piece 1), for strict mode;
  - field-offset intrinsics (piece 3), for trait objects;
  - a registry of type printers (piece 17).
- **General fixes, useful without traits:**
  - two inliner changes: exact specializations over a widened varargs tail, and cycle members inlining each other;
  - the run-time `return_type` entry compiled into the system image;
  - reflection running in the compiler's world for an explicit `NativeInterpreter`.
- **Bug fixes of our own:**
  - `return_type_tfunc` captured type values in a closure;
  - the compile queue that builds images compiled the compiler's own code by facts (§4).
- **A tool:** the dispatch profiler (`JULIA_FACTS_DISPATCH_PROFILE=1`): dynamic calls per callee and per call site, with a reset to profile one region.

## 4. Mechanism 2 is one rule in the code

Which mode and owner a method's code gets is decided by one function, `jl_code_owner` ([compiler §2.3](reference/compiler.md#23-the-owners-and-the-mode-and-owner-of-a-methodinstances-code)), given what reaches the code: the runtime or the top level, plain code, or code of the facts owner. The runtime's default owner, its dispatch from facts code, the calls between the modes in inference and the compile queues all ask it. It has one predicate for "compiler code", the module flag. The setting decides only what code reached from the runtime gets, and the mode is the owner.

## 5. Not yet established

The deviations of the implementation from the design are listed per reference, with IDs: [traits](reference/traits.md#17-deviations) (T-), [facts](reference/facts.md#deviations) (F-), [compiler](reference/compiler.md#deviations) (C-), [lowering](reference/lowering.md#18-deviations) (L-). Beyond them:

- **Base's test suite under the facts mode:** 43 groups run (E-42): a finalizer inhibition left behind by one group (facts F-22, W-77); otherwise the differences are inference assertions at abstract signatures, by design, and issue 47476's cases, which raised under the facts mode until W-76 fixed it; the other groups are not run.
- **What the measurement round left open** (done 2026-10-20; [evidence §5](design/evidence.md)):
  - the 435 ms upstream CSV+DataFrames pay after the loads under `all`, not profiled on this build; by design, not pursued now ([PE-5](record/performance-explorations.md));
  - rows that differed by load order in TraitDifferentialEquations: diagnosed (E-141) and fixed (E-146), except the first gradient (+15 ms with loads; W-7);
  - the forks' session on a quiet machine (the round's had a load average of 3.4–5.2); the forked CSV does not precompile on TraitWorld bbfc130 (W-14);
  - the raytrace rows on a current build (the solver per step and the `Dynamic` sums are measured again: E-163, E-164).

## 6. The software: today, the target, the order of work

### 6.1 Today (2026-10-27)

- **Julia** (`julia-1.13/`): parts (A)–(D), the compiler staying plain, the inliner changes (and inlining from another owner's cache), `known_type`, exact-type entries in the per-call-site dispatch cache, with the patch pieces 1, 3, 5 (keeping facts copies without source), 9, 10, 17, 18 (`:caller_world` cfunctions). Inventory: [`julia-changes.md`](design/julia-changes.md).
- **TraitWorld** (requires the patched build): the trait language, ownership, implementations as methods, entries (boundaries) and workers, keys and layout (held views for immutable values), `Callable`, `Like`, definition checking (the rule check by the default interpreter's reflection, facts inference for workers; the keep analysis and the result-type checks on a plain `NativeInterpreter`: at archetypes with their own cache owner, at real signatures in the plain cache), entries for untyped callers ([lowering §9.2](reference/lowering.md#92-untyped-callers-the-erased-worker)), compiling ahead from declarations ([lowering §15.1](reference/lowering.md#151-compiling-ahead-from-declarations)), fully typed mode with the fully-typed certificate, `verify_main`, strict mode (scoped to trait code; it protects code of the facts owner and the plain code it rests on, [facts §10.2](reference/facts.md#strict-mode), the note), printing. Its slow paths are compiled by facts (`@machinery`). `Dynamic` operations are `Compiler.split_call` sites.
- **The builds:** julia-1.13 1c2e98b58e (W-41, W-43, W-52, W-40, part of W-57, W-59, W-22: mode is owner, one rule, one answer for `return_type`, machine code only for running owners) with its facts system image; TraitWorld main 399b512 (T-51 retired; strict mode on code of the facts owner; checks' records kept with the images; strict mode's load halved), and its branch `session-cache` (the environment-keyed cache across sessions, W-62, E-180: retired, not merged; the direction is the facts-keyed cache, W-66); TraitDifferentialEquations w34 6234487 (W-63: the parameters partially evaluated at the surface, E-181; every suite passes, `experiments/checks/logs/w63/`).
- **Tests** (2026-10-28, on those builds; `experiments/checks/logs/w76/`): TraitWorld's suite in both settings; acceptance 34/34 in both settings; the demonstrators' suites (TraitTables, TraitCSV, TraitMakie, TraitDifferentialEquations); the documentation's examples (79, 5 and 58 checks). The forks do not precompile on the current TraitWorld (W-14).
- **Measured:** [`evidence.md`](design/evidence.md).

### 6.2 The target

```
Julia (patched, then upstream proposals)
  (A) facts mode in the native interpreter
  (B) method flag "compiled by facts" + owner sentinel; native code in images
  (C) owner-aware dynamic dispatch
  (D) Dynamic call-site split in the inliner
  pieces 1, 1', 14, 15 (strict), 3, 9, 10, 17; piece 5's upstream half
  --compile-by-facts=no|all|traits (the target spelling, not built; today JULIA_COMPILE_BY_FACTS=1 is all); --trim implies no

TraitWorld (package)
  @trait, @implement, @trait_module (sets the (B) flag), ownership, implementations as methods,
  entries and workers, keys and layout, Callable (two modes), Like, definition checking,
  fully typed mode, verify_main, strict mode, printing
  Dynamic{X}: holds the user's object; the candidate list for (D)

Not in the target
  TraitWorld's facts.jl (the external interpreter), view caches, warm-ups, site caches, trampolines,
  stock-only paths, witness tables and key branches, sealed_call, ten of thirteen JULIA_TW_* switches,
  the {R} spelling and projection names, the system-image prototype, pieces 2 and 4,
  the three old worktrees at the repository root
```

Of the last group, the `{R}` spelling and `project(t) = …` remain in TraitWorld's precompile workload and many tests (W-68), and the three old worktrees are still at the repository root. What each of these was, and why it went: [`alternatives.md`](design/alternatives.md).

### 6.3 The order of work

**Performance work** (the user, 2026-10-27; [decisions](record/decisions.md) §5) pursues principled architectural improvements that facts and traits enable (caching across sessions, for one), and bugs that facts and traits reveal with an impact of 20% or more, or slowdowns where trait or facts code should conceptually be as fast or faster, fixed without a significant increase in complexity. Tweaks with minor speedups at a considerable increase in complexity are not pursued.

The work queue, with every agreed item, its source and status, is [`record/todo.md`](record/todo.md). Performance work that the rule does not take up now is in [the performance explorations log](record/performance-explorations.md). The order (the clean-up, W-65, 2026-10-27):
1. **Wrap up before the large ports** (W-61): the evidence, this page, the references' statuses, the demonstrators' claims and READMEs.
2. **Small TraitWorld fixes,** one run of the suites: W-67 (the choices the clean-up adopted); then W-68 (the second spelling removed).
3. **Correctness checks** (W-9): the rest of Base's tests under the facts mode (E-42).
4. **Performance worth investigating:**
   - the folds of Base's type-introspection helpers (W-57, E-167 (2); open issue 66);
   - first calls and sessions slower than they should be (W-7, E-191);
   - calls slower than plain where trait code should be as fast (W-17, E-192).
5. **The cache keyed on facts and their origins** (W-66): done are the fingerprints (E-195), strict mode on facts code with its report at an image's load (E-198, E-204), images keeping machine code only for running owners (E-201) and the checks' records (E-203); the store waits for open issue 80 (its validity check).
6. **The large ports:** SciML (W-34) and Makie (W-70).
7. **The language:** tuples of traits everywhere a trait stands (W-29), TraitDifferentialEquations' right-hand side as one (W-30), a value seen through the traits it entered with (W-31); then traits in Julia's type system (W-27).

Waiting for the user: the Julia changes as small patches, and upstream proposals (W-19); a review session of eight choices the clean-up adopted (W-71). Paused by the user: NetworkDynamics (W-32), the forks (W-14).

What was done, in order, is in [the design history](record/design-history.md) and the session notes.
