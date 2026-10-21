# The state of the prototype (2026-10-20)

The prototype works end to end. Traits run at plain Julia's speed for typed calls, and the facts compiler stops invalidation. On the compiler side, the work reduces to four mechanisms, plus hooks for the library and fixes.

For core developers. The design itself is the four [references](reference/README.md), each with a Deviations table; this page summarizes them. The changes to Julia by principle are the [compiler reference](reference/compiler.md), with the inventory in [`design/julia-changes.md`](design/julia-changes.md); the measurements are in [`design/evidence.md`](design/evidence.md).

## 1. Where the project stands

### Traits

The library, TraitWorld, works end to end:
- **The design:** three rules, keys instead of representations, and every value in trait code `Compiled` or `Dynamic` ([traits §6](reference/traits.md#6-values-in-trait-code-compiled-and-dynamic)).
- **`Compiled` and `Dynamic`** (TraitWorld 7fc229c, 2026-10-20; W-4): a value is `Compiled` where the code that passes it knows its type, `Dynamic` where it does not, overridden by attributes on bounds and item parameters and by the casts `compiled_for`, `with_dynamic`, the later cast winning; `Dynamic` is a trait object at an erased key, one worker per key; values carry their attribute through storage (TraitWorld 1d09112, 2026-10-21; W-18): a trait's name in a field or container means `Kept{X}`, one concrete type holding the user's object and its attribute, `Compiled{X}` is a value beside `Dynamic{X}`, constructors never cast, and a struct parameter bounded by a trait keeps the value itself or a `Dynamic{X}` ([traits §7](reference/traits.md#7-kept-values-dynamicx-compiledx-keptx), [§7.4](reference/traits.md#74-a-struct-parameter-bounded-by-a-trait)); `Callable{A, S}` defaults to `Dynamic`; items of collections cross as `CompiledItems` or `DynamicItems`. The demonstrators run on it, `compiled_for` where they loop over a value compiled for its type. Deviations: [traits T-47 to T-50](reference/traits.md#17-deviations), [lowering L-31, L-35](reference/lowering.md#18-deviations); performance issues to revisit: [open issues §4](open-issues.md#4-runtime-and-measurements), item 35.
- **Beyond the `Dynamic` split, a table** (julia-1.13 711484a23e, the C ABI rule 6d480d0753, 2026-10-21; E-145): a value of a type outside the split's four is called through a table of the call's targets keyed by its type, one probe and an indirect call, no allocation (18 ns per element at 64 implementations, 77 before) ([compiler §4.3](reference/compiler.md#43-what-follows-the-split-the-table-of-a-calls-targets)); `compiled_for` from an untyped caller goes through the table of declared implementations (TraitWorld a747d4a).
- **TraitDifferentialEquations around `ODEProblemTrait`** (e37829f, 2026-10-21; W-2): a problem is any type that implements the trait, TDE's `ODEProblem` the canonical one, its function kept at two struct parameters bounded by `Callable` (W-18); `solve(prob, alg)` the one entry point.
- **BaseTraits** (TraitWorld 9fd18db, 2026-10-20): collection traits for Base's concepts, Base's containers conforming; `Dynamic` holds the user's object (5 ns to make one), the split's candidates in declaration order; a container with untyped items crosses implicitly, by the bound ([traits §7](reference/traits.md#7-kept-values-dynamicx-compiledx-keptx)).
- **The demonstrators** pass their suites: TraitDifferentialEquations, TraitMakie, and TraitReport with its packages TraitTables and TraitCSV. The ports of CSV.jl and DataFrames.jl pass their upstream suites (§6.1).

Measured in the round of 2026-10-20 (julia-1.13 3b8085c222, TraitWorld bed3782) unless a row says otherwise:

| Measure | Traits | Plain Julia |
|---|---|---|
| Typed trait call, per call | 0.8 ns | 0.8 ns |
| Untyped trait call of a `Compiled` value (`compiled_for`), through the table of declared implementations (measured at TraitWorld bed3782, when every untyped call took the table; an untyped call of a `Dynamic` value is not measured: W-17), per call | 28.8 ns (product setting); 30.8 ns (`all`); 16 bytes | 18.9 ns; 17.6 ns (`all`) |
| `Callable`, `Dynamic` (its default), per call | 3.95 ns | a direct call 0.87 ns; a dynamic call at `Any` 20.3 ns |
| `@implement` of a new type, no other packages loaded | TraitMakie 22–48 ms; TraitDifferentialEquations 66 ms | the same with big loads before or after (E-146) |
| a new problem type's first solve in TraitDifferentialEquations, timed whole | 335–371 ms in every load order: the solver compiled for the new key | — |
| TraitReport, CSV to PNG in a fresh process | 0.79–0.81 s | without traits 0.77 s; Python 0.58–0.59 s |

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

## 4. The caveat: mechanism 2 is not yet one rule in the code

Which mode and owner a method's code gets is decided in six places ([compiler C-1](reference/compiler.md#deviations)):
- the single-request entry, `typeinf_ext_toplevel`;
- `interp_for_owner` and `interp_for_mi`, for compile queues;
- `leaves_to`, for calls between the modes;
- the runtime's `jl_default_owner` and `facts_callee_owner`, for dispatch.

They use two predicates for "compiler code": a module flag in the runtime and a module walk in the Compiler.

Today's bug came from exactly this. The image builder's compile queue did not apply the rule, so under `all` part of the compiler was compiled by facts. Its `@nospecialize` helpers became run-time sites.

Measured on the CSV+DataFrames work under `all`, after the fix:

| | Before the fix | After the fix | Plain |
|---|---|---|---|
| Work time | 666 ms | about 505 ms | 3,264–3,357 ms |
| Dynamic calls (top 40 callees) | 2.05 M | 0.13 M | 0.81 M |

**The next step:** one function, "the mode and owner of a MethodInstance's code", called from every place above. With it, "four mechanisms plus fixes" is literally true of the code.

**A second gap in mechanism 2:** under `all`, plain results and results compiled by facts share the default owner's cache. A Base method called by the compiler can therefore reuse a result compiled by facts. Results stay correct; such calls are only slower. The planned fix puts code compiled by facts under the facts owner `:facts` under `all` too, as in the product setting, so the default owner holds plain code only ([compiler C-2](reference/compiler.md#deviations), [facts F-2](reference/facts.md#deviations)).

## 5. Not yet established

The deviations of the implementation from the design are listed per reference, with IDs: [traits](reference/traits.md#17-deviations) (T-), [facts](reference/facts.md#deviations) (F-), [compiler](reference/compiler.md#deviations) (C-), [lowering](reference/lowering.md#18-deviations) (L-). Beyond them:

- **Threads:** the new caches add lock-free readers; threads are untested.
- **Base's test suite under the facts mode:** started once, not completed.
- **Targeted checks** for the inliner changes and for the compiler-plain edges.
- **G2 across package loads under `all`:** the check counts code compiled by facts and passes in the product setting (2026-10-20); it is not yet run under `all`, nor cited in the reference ([facts F-11](reference/facts.md#deviations)).
- **What the measurement round left open** (done 2026-10-20; [evidence §5](design/evidence.md)):
  - the 435 ms upstream CSV+DataFrames pay after the loads under `all`, not profiled on this build;
  - rows that differed by load order in TraitDifferentialEquations: diagnosed (E-141) and fixed (E-146), except the first gradient (+15 ms with loads);
  - the forks' session on a quiet machine (the round's had a load average of 3.4–5.2);
  - the run-time rows (`Dynamic` sums, raytrace, the solver per step) on the round's build.
- **The TraitMakie image flake:** a 3.3e-5 pixel difference, once in five runs, not reproduced.

## 6. The software: today, the target, the order of work

### 6.1 Today (2026-10-19)

- **Julia** (`julia-1.13/`): parts (A)–(D), the compiler staying plain, the inliner changes (and inlining from another owner's cache), `known_type`, exact-type entries in the per-call-site dispatch cache, with the patch pieces 1, 3, 5 (keeping facts copies without source), 9, 10, 17, 18 (`:caller_world` cfunctions). Inventory: [`julia-changes.md`](design/julia-changes.md).
- **TraitWorld** (requires the patched build): the trait language, ownership, implementations as methods, entries (boundaries) and workers, keys and layout (held views for immutable values), `Callable`, `Like`, definition checking (the rule check by the default interpreter's reflection, facts inference for workers; the keep analysis and the result-type checks on a plain `NativeInterpreter`: at archetypes with their own cache owner, at real signatures in the plain cache), entries for untyped callers ([lowering §9.2](reference/lowering.md#92-untyped-callers-the-erased-worker)), compiling ahead from declarations ([lowering §15.1](reference/lowering.md#151-compiling-ahead-from-declarations)), concrete mode with the fully-typed certificate, `verify_main`, strict mode (scoped to trait code; it also protects all `:facts` code and some plain code, [facts §10.2](reference/facts.md#strict-mode), the note), printing. Its slow paths are compiled by facts (`@machinery`). `Dynamic` operations are `Compiler.split_call` sites.
- **Tests:** TraitWorld's 48 sets; acceptance 25/25; the demonstrators' suites (TraitTables, TraitCSV, TraitMakie, TraitDifferentialEquations); the forks' upstream suites (Tables, CSV, DataFrames) and their scripted session (digests equal to upstream); the examples (`experiments/examples/run_all.sh`).
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
  concrete mode, verify_main, strict mode, printing
  Dynamic{X}: holds the user's object; the candidate list for (D)

Not in the target
  TraitWorld's facts.jl (the external interpreter), view caches, warm-ups, site caches, trampolines,
  stock-only paths, witness tables and key branches, sealed_call, ten of thirteen JULIA_TW_* switches,
  the {R} spelling and projection names, the system-image prototype, pieces 2 and 4,
  the three old worktrees at the repository root
```

Of the last group, the `{R}` spelling and `project(t) = …` remain in TraitWorld's precompile workload and many tests ([open issues](open-issues.md) §2, "the design and the code disagree", item 7), and the three old worktrees are still at the repository root. What each of these was, and why it went: [`alternatives.md`](design/alternatives.md).

### 6.3 The order of work

The work queue, with every agreed item, its source and status, is [`record/todo.md`](record/todo.md) (since 2026-10-20). In brief: BaseTraits is merged (W-1, done 2026-10-20); the language of `Compiled` and `Dynamic` is built (W-4, done 2026-10-20; its performance issues, [open issues §4](open-issues.md#4-runtime-and-measurements) item 35, are measured in W-17); what follows the `Dynamic` split is built (W-6, E-145, done 2026-10-21); TraitDifferentialEquations is built around a problem trait (W-2, done 2026-10-21); the differences between abstract types and traits are written out (W-3, done 2026-10-21, [traits §14](reference/traits.md#14-membership)); values carry their attribute through storage (W-18, done 2026-10-21); the traits reference is restructured (W-20, done 2026-10-21); a bound may name a `where` variable (W-24, done 2026-10-21); the checks at the declaration (W-23, 2026-10-21: but for the family-wide check, open issue 42). The seven groups of deviations are W-21 to W-27. The order below is the one of 2026-10-19, carried into the queue as W-9 to W-14.

Steps 0, 1, 3, 4 and 5 of the speed plan ([the principled speed plan](plans/2026-10-19-principled-speed-plan.md)) are built (2026-10-19); step 2 (guarded devirtualization) is postponed, since traits recover the costs it targets and a failed guard is a silent cliff. The order in force is [the remaining performance work](plans/2026-10-19-remaining-performance-work.md):
1. **Correctness first:**
   - the TraitMakie image flake;
   - threads beyond the tables (checked 2026-10-21: the split's tables and the untyped callers' table under 4 threads, `experiments/examples/threads/`);
   - a check of G2 across package loads that counts code compiled by facts.
2. **Done (2026-10-20): the measurement round** ([evidence](design/evidence.md)).
3. **The rest of the machinery's startup:** the compiler's reflection code compiled again after loads.
4. **The ~990 ms after the loads:** a differential test, then red-green revalidation of the `return_type` answers.
5. **The next call-site cache steps:**
   - entries with an open `max_world`;
   - the `call_cache` size;
   - the split tables' pointers compiled ahead (compiler C-14), and their miss after each method definition (C-3).
6. **Upstream proposals** (julia-changes §4).
7. **The forks resumed,** with `CSVColumn{T}` and kernels that use the declared operations.

What was done, in order, is in [the design history](record/design-history.md) and the session notes.
