# The state of the prototype (2026-10-19)

The prototype works end to end. Traits run at plain Julia's speed for typed calls, and the facts compiler stops invalidation. On the compiler side, the work reduces to four mechanisms, plus hooks for the library and fixes.

For core developers. The changes by principle, with what is planned and optional, and the inventory with commits are [`design/julia-changes.md`](design/julia-changes.md); the measurements with builds and baselines are [`design/evidence.md`](design/evidence.md).

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
| 2 | **Each method is compiled in its own mode, under a cache owner of its own, whoever calls it** | Code compiled by facts and plain code live side by side, with separate caches, edges and images. | Parts (B) and (C); `leaves_to`; the compiler's never-by-facts flag; inlining from the other owner's cache (piece 10, c7f1eae); edges and image copies for the second owner (pieces 9 and 5, 9892bfc) | As per-method inference modes |
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

Which mode and owner a method's code gets is decided in about five places:
- the single-request entry, `typeinf_ext_toplevel`;
- `interp_for_owner`, for compile queues;
- `leaves_to`, for calls between the modes;
- the runtime's `jl_method_is_plain`, for dispatch;
- `interp_for_mi`, added today for the image builder's queue.

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

- **The measurement round:** the full BaseBenchmarks and all demonstrator rows, on a quiet machine. Several numbers in the documents change only after it.
- **Threads:** the new caches add lock-free readers; threads are untested.
- **Base's test suite under the facts mode:** started once, not completed.
- **Targeted checks** for the inliner changes and for the compiler-plain edges.
- **The TraitMakie image flake:** a 3.3e-5 pixel difference, once in five runs, not reproduced.
