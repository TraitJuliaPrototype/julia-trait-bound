# The state of the prototype (2026-11-08)

Traits are abstract types on Julia's unified build: memberships live in the type system, dispatch picks methods at traits, and the ports run on it with upstream's results. The goal's task (DataFrames + Makie), the ODE session (setting D) and TraitReport's trait form run within Python + 1 s; the forks' REPL session is 2.4 s above pandas (§5).

For core developers. The design is the four [references](reference/README.md), each with a Deviations table; this page summarizes what is built. The changes to Julia are the [compiler reference](reference/compiler.md), with the inventory in [`design/julia-changes.md`](design/julia-changes.md); the measurements are in [`design/evidence.md`](design/evidence.md). The earlier build (julia-1.13 with TraitWorld `main`) still runs, and most numbers in the evidence are its; its state on 2026-10-29 is [a dated snapshot](../attic/writeup/state-2026-10-29.md).

## 1. Where the project stands

- **The design:** the references for "traits are abstract types", adopted by the user on 2026-11-06. The choices marked mine since then wait for the user's confirmation ([open issues](open-issues.md) §1).
- **Julia** (`julia-unified`, branch `unified`): a stack of self-contained commits on v1.13.2, the changes useful without traits first ([julia-changes §7.1](design/julia-changes.md#71-the-stack)). The stages of [the work plan](plans/2026-11-06-work-plan-under-the-draft-reference.md) are built: W-98, W-99, W-107, W-108, W-109, W-100, W-111, W-112, W-113, W-114, W-101. Latest: `unified` 24c8d4db60.
- **The library** (`TraitWorld-unified`, branch `unified`): a library on the new type system, 24a5fcd.
- **The ports** (W-104): every port runs on the unified build: slices 1 and 2 (the DataFrames side and the plotting core) and slice 3 (TraitDifferentialEquations, NetworkDynamics) (§4).
- **Performance:** [the plan to reach Python's speed](plans/2026-11-08-python-speed.md) (W-123 to W-127). Stage 1's gate (loading) and stage 3's (the goal's task within Python + 1 s) are met; stages 2 and 4 (first calls) are under way (§5).

## 2. What the unified build changes in Julia

By the compiler reference's sections:
- **Memberships in the type system** ([§4](reference/compiler.md#4-sets-and-memberships)): a trait is an open abstract type; `jl_declare_membership` publishes an entry in a new world; subtyping, intersection and the type cache read the entries; negatives never fold; intersections `All{X, Y, …}`; a set's inputs (C-32 retired).
- **Dispatch at traits** ([§5](reference/compiler.md#5-dispatch)): specificity with a closed type above a trait; the ambiguity report at a membership; guards on membership cells, so a membership invalidates no code.
- **The facts mode** ([§1](reference/compiler.md#1-the-facts-inference), [§2](reference/compiler.md#2-the-policy-per-method)): a trait module's calls are inferred only at fact signatures, with run-time sites elsewhere; one CodeInstance per method and policy; images keep code by the G2 bit.
- **The attribute** ([§6](reference/compiler.md#6-keys-and-the-attribute)): a trait argument compiled for the value's type or once, decided by a cast, the value, the method or module, the trait's default or the scope; `Core.Dynamic`, `keep`, the casts.
- **Operations on a value known by its trait** ([§7](reference/compiler.md#7-operations-on-a-value-typed-by-its-trait)): the declared result, a split over the first members, a table past them; `Callable` by the function's own methods.
- **The code slot** ([§3.3](reference/compiler.md#33-the-code-slot)): a call that holds only a result edge goes through a slot; a callee recompiled to an equal result keeps its callers; a miss with no code to make gets a dispatching entry.
- **Images and hooks** ([§9](reference/compiler.md#9-images-and-the-machine-code-cache), [§10](reference/compiler.md#10-hooks-for-the-library)): an image keeps and activates its memberships; the member hook, the definition, module-end, deletion and fully-typed hooks.

The inventory, one row per commit: [julia-changes](design/julia-changes.md), rows 1–59.

## 3. The library

TraitWorld `unified`: `@trait` (operations, defaults, fields, inputs, supertraits), `@implement` (forms, families with their variables in the block, forwarding), the checks at a declaration and at a member's first use, the classification of methods as fully bounded or open with `bounded` and `@open`, `@trait_module`, `Dynamic{X}`'s memberships and methods, `Callable`, strict mode and ownership, fully typed mode, compiling ahead, hints, and BaseTraits (`HasLength`, `Iterable`, `Indexable`, `MutableIndexable`, `Resizable`, `Keyed`, `HasProperty`, `Solvable`, `LinearOp`, `BoundedText`). Its deviations: [traits](reference/traits.md#19-deviations) (T-) and [lowering](reference/lowering.md#15-deviations) (L-).

## 4. The ports (W-104)

Each port lives on a branch `unified` in a sibling worktree, `<Repo>-unified` ([the plan](plans/2026-11-07-w104-ports.md)).

| Slice | Port | On the unified build | Checked on (2026-11-08) |
|---|---|---|---|
| 1 | TraitTables, TraitCSV, TraitMakie | their suites pass | `unified` 350c5b1c59, TraitWorld d897223 or bd9a721 |
| 1 | TraitReport, trait form | its summary and PNG equal the plain form's on three datasets; forms (t) and (pt) agree | (t), (pt): `unified` e9b9261808, TraitWorld 24a5fcd (E-307) |
| 2 | the forks of Tables, CSV, DataFrames, with CSV's reader and DataFrames' module compiled by facts | the session's digests equal upstream's at 26 steps (E-308); Tables' suite passes; CSV's passes in full, 330,545 (E-302); DataFrames' fails 7: 4 at `tables.jl:86` (open issue 158's second case) and 3 `@inferred` that see `Any` where C-36 would give `DataFrame` (E-305) | digests: `unified` 24c8d4db60, forks 27d4baa; suites: `unified` d04256a442 (CSV), e9b9261808 (DataFrames) |
| 3 | TraitDifferentialEquations | every package loads; its suite passes, 32 testsets, none broken | `unified` e9b9261808, TDE fcee973, TraitWorld 24a5fcd (E-307) |
| 3 | NetworkDynamics (with Graphs' port, GraphMakie's over MakieCompat) | its test subset and its workload's 32 digests give the earlier build's results | `unified` 350c5b1c59 (W-104) |

The ports found the design's open questions [157](open-issues.md#2-design) (a function barrier in facts code loses its callee's declared result), [158](open-issues.md#2-design) (a guarded call at a type with no method takes the trait's declared result) and [159](open-issues.md#2-design) (a function stored before its signature is known keeps no attribute), and fixes in the runtime and the library (W-104's row in [the work queue](record/todo.md)).

The tests of the build itself (2026-11-08, the battery `w125c` on `unified` e9b9261808 with TraitWorld 24a5fcd, `experiments/unification/stack/logs/`): the gates 50 of 50; Base's `core`, `subtype`, `worlds`, `ambiguous`, `reflection`, `Compiler/inline`, `Compiler/inference` and `precompile`; the 21 acceptance cases; TraitWorld's suite; both workloads.

## 5. Not yet established

The deviations of the implementation from the design are listed per reference: [traits](reference/traits.md#19-deviations) (T-), [facts](reference/facts.md#16-deviations) (F-), [compiler](reference/compiler.md#deviations) (C-), [lowering](reference/lowering.md#15-deviations) (L-). Beyond them:

- **The unified build against the earlier build, on the same host** (E-289, 2026-11-08; [evidence §3](design/evidence.md#3-first-calls-and-sessions)):

  | Session | Python | Earlier build | Unified build |
  |---|---|---|---|
  | the goal's task, DataFrames + Makie (TraitReport's form (f)) | 0.63–0.65 s | 2.46–2.49 s | 27.1–27.4 s; 7.62–7.75 s (E-292); 4.98–5.11 s (E-295); 3.62–3.70 s (E-296); 3.37–3.45 s (E-298); 2.37–2.40 s (E-300); 2.21–2.28 s (E-301); 1.91–1.95 s (E-302: the forks' CSV by facts); 1.81–1.83 s (E-303); 1.56–1.61 s (E-305: DataFrames by facts); **1.54–1.61 s** (E-307) |
  | the forks' DataFrames session at a REPL | 0.69–0.75 s | 5.06–5.07 s | 38.0–38.5 s; 6.48–6.51 s (E-292); 9.86–10.42 s (E-296: §5.6's pruned arms at a REPL); 4.76–5.17 s (E-298); 4.08–4.44 s (E-300); 3.98–4.42 s (E-301); 3.89–4.04 s (E-302); 3.67–3.70 s (E-303); 3.82–4.01 s (E-305); 3.75–3.98 s (E-307); **3.11–3.24 s** (E-308) |
  | TDE + TraitMakie, setting D | 1.43–1.46 s (E-230) | 1.34–1.35 s (E-242) | 11.59–11.77 s; 9.19–9.28 s (E-295); 6.35–6.56 s (E-296); 3.42 s (E-298); 2.82–2.84 s (E-300); 2.75–2.82 s (E-301); 2.52–2.54 s (E-303); **2.04–2.05 s** (E-307) |
  | TraitReport (t) | 0.64–0.68 s | 0.63 s (E-233) | 3.18–3.20 s (E-286); 0.99–1.04 s (E-292); 1.02–1.07 s (E-296); 0.97–0.99 s (E-298); 0.89–0.91 s (E-300); 0.775–0.821 s (E-301); 0.73–0.76 s (E-303); **0.72–0.75 s** (E-307) |
  | NetworkDynamics' workload, recorded | — | 31.3 s (E-250) | 100.4 s, one run with an extra pass (W-104's log, `ndport/logs/unified/`) |

  - **Loading:** the dispatch walk at activation (C-72) and the library's interpreter invalidating the compiler (C-40) are fixed (W-123, E-292). What remains is compiling at load: plain packages' methods invalidate ten times as much of the compiler's own code as on vanilla (2,049 against 193 instances for upstream CSV and DataFrames), through untyped narrowings in the stack's own compiler code: fixed (28d2334164, E-295: 195 instances against vanilla's 193). TraitWorld's load hooks invalidated by plain packages: fixed in the library (e6eaa85, E-296). At a REPL, TraitWorld's methods at sets for required operations invalidated the system image's code with a pruned `Nothing` arm (compiler §5.6; E-296); open issue 158 (a) makes them no shadow (B2 and TraitWorld c4f9f99): the forks' session 4.8–5.2 s (E-298). Validation's walk of the memberships at each match is gone (89b3bcff81, E-300: the goal's task 2.4 s); what the loads still spend is Julia's own validation, scaled by the images' size, and image restore.
  - **The imports:** the goal's task 0.98–1.03 s against Python's 0.47 s (E-307), the forks' session 0.86–0.96 s (E-308). What the loads spend is Julia's validation of the images' edges and image restore (E-303, E-304).
  - **After the imports:** the goal's read, summary and plot 0.27 s against the earlier build's 0.36 s and Python's 0.08 s (E-307); the forks' steps 1.55 s against 2.80 s and pandas' 0.41 s (E-308). What the forks' steps still compile: DataFrames' `show` at the REPL's stream, CSV's parallel reader's task closures for a file large enough to split (C-74). Slower than the earlier build: setting D's first solve 0.34 s against 0.19 s (E-307); NetworkDynamics' new equations 9.0 against 1.1 s, measured before C-54 was built. Setting D's second model 0.05–0.06 s, as on the earlier build.
  - **The floor** (E-291): a bare Julia process takes 0.15–0.18 s on every build, Python 0.02 s.
- **An argument typed by a bare `where` variable bounded by a set** (`x::C`, `C <: X`) is compiled for the value's type whatever its attribute (C-54). One typed by a set that names the method's variables (`X{T}`) takes its attribute: TraitDifferentialEquations' `ODEProblem(f, …)` compiles the solver once per state type (E-298).
- **Keys** are Optional, built late (W-110).

## 6. The software: today, the target, the order of work

<a id="today"></a>
### 6.1 Today (2026-11-08)

- **Julia:** `julia-unified` `unified` 24c8d4db60 (e9b9261808 with a diagnostic, `JULIA_DEBUG_EXTERNAL_CIS=1`). The earlier build: `julia-1.13` 00dcc9994c.
- **TraitWorld:** `TraitWorld-unified` `unified` 24a5fcd. The earlier library: `TraitWorld` `main` 33dd55e.
- **The ports on the unified build:** TraitTables `unified` d964a98, TraitCSV 90e7330, TraitMakie 499af5d, TraitReport a4bcf33, forks 27d4baa, TraitDifferentialEquations fcee973, NetworkDynamics `unified` fc25b89, Graphs dbcb7c70 and GraphMakie `unified` (in `ndport`, 5ae8421). On the earlier build: their branches `main` (TraitDifferentialEquations `w34`, `w96`), NetworkDynamics' port in `ndport`.
- **Tests:** §4. **Measured:** [`evidence.md`](design/evidence.md).

### 6.2 The target

The design of the references, built on Julia as a stack of self-contained commits, proposed upstream where they are useful without traits (W-19), with TraitWorld as a package. Keys (Optional) come late; the machine-code cache (W-120) is decided after the profiling campaign.

### 6.3 The order of work

The work queue, with every agreed item, its source and status, is [`record/todo.md`](record/todo.md). The order:
1. **The ports** (W-104): every port runs; NetworkDynamics' session against the evidence remains.
2. **[The plan to reach Python's speed](plans/2026-11-08-python-speed.md)** (the user, 2026-11-08; target: the goal's task within Python + 1 s; workloads only at broad typical cases), from the profiling campaign (W-121): W-123 (stage 1) done; W-125's gate met; W-124 (stage 2's rest: setting D's first solve, NetworkDynamics' new equations) and W-126 (stage 4: what the sessions still compile) under way; W-127 (stage 5) waits for the user's scope.
3. **The deviations that matter for correctness or the plan** (W-128), beside it.
4. Queued: W-119 (the slot's share in the ports), W-115 to W-118.

**Performance work** follows the rule of 2026-10-27 ([decisions](record/decisions.md) §5): principled architectural improvements, and bugs with an impact of 20 % or more or slowdowns where trait code should be as fast as plain code, without a significant increase in complexity.

Waiting for the user: the choices marked mine ([open issues](open-issues.md) §1), among them the recommendations of open issues 158 and 159; upstream proposals (W-19).

What was done, in order, is in [the design history](record/design-history.md) and the session notes.
