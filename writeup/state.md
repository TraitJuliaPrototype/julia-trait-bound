# The state of the prototype (2026-10-19)

The prototype works end to end. Traits run at plain Julia's speed for typed calls, and the facts compiler stops invalidation. On the compiler side, the work reduces to four mechanisms, plus hooks for the library and fixes.

For core developers. The design itself is the four [references](reference/README.md), each with a Deviations table; this page summarizes them. The changes to Julia by principle are the [compiler reference](reference/compiler.md), with the inventory in [`design/julia-changes.md`](design/julia-changes.md); the measurements are in [`design/evidence.md`](design/evidence.md).

## 1. Where the project stands

### Traits

The library, TraitWorld, works end to end:
- **The design:** four rules, keys instead of representations, and `Callable` with `CompiledCall` and `DynamicCall`.
- **The demonstrators** pass their suites: TraitTables, TraitCSV, TraitMakie, TraitDifferentialEquations and TraitReport.

| Measure | Traits | Plain Julia |
|---|---|---|
| Typed trait call | 0.8 ns | 0.8 ns |
| Untyped trait call, through the table of declared implementations | about 29 ns | 17 ns |
| Untyped trait call, type compiled ahead | about 14 ns | 15–17 ns |
| `@implement` of a new type (TraitMakie) | 22–49 ms | — |
| TraitReport, CSV to PNG in a fresh session | 0.82 s | Python: 0.6 s |

### Facts

The facts compiler is built, with two settings:
- **The product setting:** only trait modules are compiled by facts.
- **`all`:** everything is compiled by facts. It is the test bed.

Under `all`:
- **Correctness:** the acceptance checks pass, 23 of 23.
- **The payoff:** CSV+DataFrames work after big loads takes 684 ms, against 3,917 ms plain, because nothing is invalidated.
- **The cost:** a geomean of 1.73 against plain on the quick BaseBenchmarks subset. The subset was picked to include the slow cases (containers of `Any`, sort), so 1.73 is not the average cost.

## 2. The compiler changes as four mechanisms

The patched Julia adds about 1,750 lines in 36 files, in 40 commits on v1.13.2 (with build scripts and the dispatch profiler). Underneath them are four mechanisms.

| # | Mechanism | What it does | What it covers | General for Julia? |
|---|---|---|---|---|
| 1 | **Infer across a call only where a fact holds** | A call is inferred, with an edge, only at a signature that only its stakeholders or a pirate can change. Every other call is a run-time site. | Part (A), `is_fact_sig` | As "a facts mode for the native compiler" |
| 2 | **Each method's code is compiled in a mode decided by the method and the mode that reaches it** | Code compiled by facts and plain code live side by side, with separate caches, edges and images. A trait module's methods are compiled by facts and the compiler's own code plainly, whoever calls them; other methods get one copy per mode that reaches them. | Parts (B) and (C); `leaves_to`; the compiler's never-by-facts flag; inlining from the other owner's cache (piece 10, c7f1eae); edges and image copies for the second owner (pieces 9 and 5, 9892bfc) | As per-method inference modes |
| 3 | **Caches at dynamic boundaries are checked against the caller's world** | A cached dynamic call or `cfunction` pointer runs in the caller's world, as Julia's own caches already do. | The `:caller_world` cfunction convention (piece 18); exact-type and wildcard entries in the per-call-site dispatch cache | Yes |
| 4 | **Two primitives for a specialized path beside a general one** | `known_type` folds to whether inference knows a value's concrete type (GCC's `__builtin_constant_p`, for types). `dynamic_call` splits a call site over registered candidates. | `known_type` (b5bb9ab); part (D) | `known_type`: yes |

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

**A second gap in mechanism 2:** under `all`, plain results and results compiled by facts share the default owner's cache. A Base method called by the compiler can therefore reuse a result compiled by facts. Results stay correct; such calls are only slower. A clean version gives the test bed an owner of its own.

## 5. Not yet established

The deviations of the implementation from the design are listed per reference, with IDs: [traits](reference/traits.md#19-deviations) (T-), [facts](reference/facts.md#deviations) (F-), [compiler](reference/compiler.md#deviations) (C-), [lowering](reference/lowering.md#18-deviations) (L-). Beyond them:

- **The measurement round:** the full BaseBenchmarks and all demonstrator rows, on a quiet machine. Several numbers in the documents change only after it.
- **Threads:** the new caches add lock-free readers; threads are untested.
- **Base's test suite under the facts mode:** started once, not completed.
- **Targeted checks** for the inliner changes and for the compiler-plain edges.
- **The TraitMakie image flake:** a 3.3e-5 pixel difference, once in five runs, not reproduced.

## 6. The software: today, the target, the order of work

### 6.1 Today (2026-10-19)

- **Julia** (`julia-1.13/`): parts (A)–(D), the compiler staying plain, the inliner changes (and inlining from another owner's cache), `known_type`, exact-type entries in the per-call-site dispatch cache, with the patch pieces 1, 3, 5 (keeping facts copies without source), 9, 10, 17, 18 (`:caller_world` cfunctions). Inventory: [`julia-changes.md`](design/julia-changes.md).
- **TraitWorld** (requires the patched build): the trait language, ownership, implementations as methods, entries (boundaries) and workers, keys and layout (held views for immutable values), `Callable`, `Like`, definition checking (the checks on a `NativeInterpreter`: at archetypes with their own cache owner, at real signatures in the plain cache), entries for untyped callers (4.9), compiling ahead from declarations (4.8), concrete mode with the fully-typed certificate, `verify_main`, strict mode (protecting `:facts` code), printing. Its slow paths are compiled by facts (`@machinery`). `Dynamic` operations are `Compiler.dynamic_call` sites.
- **Tests:** TraitWorld's 48 sets; acceptance 22/22; the demonstrators' suites (TraitTables, TraitCSV, TraitMakie, TraitDifferentialEquations); the forks' upstream suites (Tables, CSV, DataFrames) and their scripted session (digests equal to upstream); the examples (`experiments/examples/run_all.sh`).
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

Of the last group, the `{R}` spelling and `project(t) = …` remain in TraitWorld's precompile workload and many tests ([`../open-issues.md`](open-issues.md) §2, "the design and the code disagree", item 7), and the three old worktrees are still at the repository root. What each of these was, and why it went: [`alternatives.md`](design/alternatives.md).

### 6.3 The order of work

Steps 0, 1, 3, 4 and 5 of the speed plan ([`../plans/2026-10-19-principled-speed-plan.md`](plans/2026-10-19-principled-speed-plan.md)) are built (2026-10-19); step 2 (guarded devirtualization) is postponed, since traits recover the costs it targets and a failed guard is a silent cliff. The order in force is [`../plans/2026-10-19-remaining-performance-work.md`](plans/2026-10-19-remaining-performance-work.md):
1. **Correctness first:**
   - the TraitMakie image flake;
   - a `const DynamicFn` in a package image (a stale pointer);
   - acceptance checks for the untyped calls' table and its world ranges;
   - threads.
2. **A measurement round on a quiet machine,** before any number in the documents changes.
3. **The rest of the machinery's startup:** the compiler's reflection code compiled again after loads.
4. **The ~990 ms after the loads:** a differential test, then red-green revalidation of the `return_type` answers.
5. **The next call-site cache steps:**
   - entries with an open `max_world`;
   - the `call_cache` size;
   - `Dynamic` beyond four implementations when a demonstrator needs it.
6. **Upstream proposals** (julia-changes §4).
7. **The forks resumed,** with `CSVColumn{T}` and kernels that use the declared operations.

What was done, in order, is in [`../record/design-history.md`](record/design-history.md) and the session notes.
