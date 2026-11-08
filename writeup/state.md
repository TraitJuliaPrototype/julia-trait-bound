# The state of the prototype (2026-11-08)

Traits are abstract types on Julia's unified build: memberships live in the type system, dispatch picks methods at traits, and the ports run on it with upstream's results. The unified build loses to the earlier build by 7–11× in the measured sessions, in loading above all, through a cost bug in the membership walk at an image's activation (C-72); after the imports it is faster in the forks' session and slower in the first calls of the ODE session and of NetworkDynamics' new equations.

For core developers. The design is the four [references](reference/README.md), each with a Deviations table; this page summarizes what is built. The changes to Julia are the [compiler reference](reference/compiler.md), with the inventory in [`design/julia-changes.md`](design/julia-changes.md); the measurements are in [`design/evidence.md`](design/evidence.md). The earlier build (julia-1.13 with TraitWorld `main`) still runs, and most numbers in the evidence are its; its state on 2026-10-29 is [a dated snapshot](../attic/writeup/state-2026-10-29.md).

## 1. Where the project stands

- **The design:** the references for "traits are abstract types", adopted by the user on 2026-11-06. The choices marked mine since then wait for the user's confirmation ([open issues](open-issues.md) §1).
- **Julia** (`julia-unified`, branch `unified`): a stack of self-contained commits on v1.13.2, the changes useful without traits first ([julia-changes §7.1](design/julia-changes.md#71-the-stack)). The stages of [the work plan](plans/2026-11-06-work-plan-under-the-draft-reference.md) are built: W-98, W-99, W-107, W-108, W-109, W-100, W-111, W-112, W-113, W-114, W-101. Latest: `unified` 350c5b1c59.
- **The library** (`TraitWorld-unified`, branch `unified`): a library on the new type system, e967ca0.
- **The ports** (W-104): every port runs on the unified build: slices 1 and 2 (the DataFrames side and the plotting core) and slice 3 (TraitDifferentialEquations, NetworkDynamics) (§4).
- **Performance:** the profiling campaign (W-121) comes once the ports run. Its first item is named: the load path (§5).

## 2. What the unified build changes in Julia

By the compiler reference's sections:
- **Memberships in the type system** ([§4](reference/compiler.md#4-sets-and-memberships)): a trait is an open abstract type; `jl_declare_membership` publishes an entry in a new world; subtyping, intersection and the type cache read the entries; negatives never fold; intersections `All{X, Y, …}`; a set's inputs (C-32 retired).
- **Dispatch at traits** ([§5](reference/compiler.md#5-dispatch)): specificity with a closed type above a trait; the ambiguity report at a membership; guards on membership cells, so a membership invalidates no code.
- **The facts mode** ([§1](reference/compiler.md#1-the-facts-inference), [§2](reference/compiler.md#2-the-policy-per-method)): a trait module's calls are inferred only at fact signatures, with run-time sites elsewhere; one CodeInstance per method and policy; images keep code by the G2 bit.
- **The attribute** ([§6](reference/compiler.md#6-keys-and-the-attribute)): a trait argument compiled for the value's type or once, decided by a cast, the value, the method or module, the trait's default or the scope; `Core.Dynamic`, `keep`, the casts.
- **Operations on a value known by its trait** ([§7](reference/compiler.md#7-operations-on-a-value-typed-by-its-trait)): the declared result, a split over the first members, a table past them; `Callable` by the function's own methods.
- **The code slot** ([§3.3](reference/compiler.md#33-the-code-slot)): a call that holds only a result edge goes through a slot; a callee recompiled to an equal result keeps its callers; a miss with no code to make gets a dispatching entry.
- **Images and hooks** ([§9](reference/compiler.md#9-images-and-the-machine-code-cache), [§10](reference/compiler.md#10-hooks-for-the-library)): an image keeps and activates its memberships; the member hook, the definition, module-end, deletion and fully-typed hooks.

The inventory, one row per commit: [julia-changes](design/julia-changes.md), rows 1–53.

## 3. The library

TraitWorld `unified`: `@trait` (operations, defaults, fields, inputs, supertraits), `@implement` (forms, families with their variables in the block, forwarding), the checks at a declaration and at a member's first use, the classification of methods as fully bounded or open with `bounded` and `@open`, `@trait_module`, `Dynamic{X}`'s memberships and methods, `Callable`, strict mode and ownership, fully typed mode, compiling ahead, hints, and BaseTraits (`HasLength`, `Iterable`, `Indexable`, `MutableIndexable`, `Resizable`, `Keyed`, `HasProperty`, `Solvable`, `LinearOp`, `BoundedText`). Its deviations: [traits](reference/traits.md#19-deviations) (T-) and [lowering](reference/lowering.md#15-deviations) (L-).

## 4. The ports (W-104)

Each port lives on a branch `unified` in a sibling worktree, `<Repo>-unified` ([the plan](plans/2026-11-07-w104-ports.md)).

| Slice | Port | On the unified build (2026-11-08, `unified` 350c5b1c59, TraitWorld d897223 or bd9a721) |
|---|---|---|
| 1 | TraitTables, TraitCSV, TraitMakie | their suites pass |
| 1 | TraitReport, trait form | its summary and PNG equal the plain form's on three datasets |
| 2 | the forks of Tables, CSV, DataFrames | the session's digests equal upstream's at 26 steps; Tables' suite passes; CSV's fails 6 of 330,545 (open issue 158); DataFrames' fails 4 at `tables.jl:86` (open issue 158's second case, C-36) |
| 3 | TraitDifferentialEquations | every package loads; 32 testsets pass, 3 checks broken (C-54) |
| 3 | NetworkDynamics (with Graphs' port, GraphMakie's over MakieCompat) | its test subset and its workload's 32 digests give the earlier build's results |

The ports found the design's open questions [157](open-issues.md#2-design) (a function barrier in facts code loses its callee's declared result), [158](open-issues.md#2-design) (a guarded call at a type with no method takes the trait's declared result) and [159](open-issues.md#2-design) (a function stored before its signature is known keeps no attribute), and fixes in the runtime and the library (W-104's row in [the work queue](record/todo.md)).

The tests of the build itself (2026-11-08, the battery `w104e`, `experiments/unification/stack/logs/`): the gates 45 of 45; Base's `core`, `subtype`, `worlds`, `ambiguous`, `reflection`, `Compiler/inline`, `Compiler/inference` and `precompile`; the 21 acceptance cases; TraitWorld's suite (50 sets); both workloads; compiling ahead in two packages; the code slot's gate.

## 5. Not yet established

The deviations of the implementation from the design are listed per reference: [traits](reference/traits.md#19-deviations) (T-), [facts](reference/facts.md#16-deviations) (F-), [compiler](reference/compiler.md#deviations) (C-), [lowering](reference/lowering.md#15-deviations) (L-). Beyond them:

- **The unified build against the earlier build, on the same host** (E-289, 2026-11-08; [evidence §3](design/evidence.md#3-first-calls-and-sessions)):

  | Session | Python | Earlier build | Unified build |
  |---|---|---|---|
  | the goal's task, DataFrames + Makie (TraitReport's form (f)) | 0.63–0.65 s | 2.46–2.49 s | 27.1–27.4 s, of it imports 26.2–26.4 s |
  | the forks' DataFrames session at a REPL | 0.69–0.75 s | 5.06–5.07 s | 38.0–38.5 s, of it imports 34.9–35.4 s |
  | TDE + TraitMakie, setting D | 1.43–1.46 s (E-230) | 1.34–1.35 s (E-242) | 11.59–11.77 s, of it load 7.4–7.6 s |
  | TraitReport (t), recorded | 0.64–0.68 s | 0.63 s (E-233) | 3.18–3.20 s (E-286) |
  | NetworkDynamics' workload, recorded | — | 31.3 s (E-250) | 100.4 s, one run with an extra pass (W-104's log, `ndport/logs/unified/`) |

  - **Loading:** 92 % of DataFrames' 21 s load is the dispatch walk at activation, and 96 % of the walk its conservative pass, taken for every method at a parametric set and visiting every method of every function ([compiler C-72](reference/compiler.md#deviations); E-287, E-290). The package callback compiled at every first load is fixed (TraitWorld e967ca0, E-286).
  - **After the imports:** the forks' steps take 2.24–2.25 s against the earlier build's 2.80–2.81 s. Slower: the goal's read (0.34–0.36 against 0.095 s), setting D's first solve (2.80 against 0.19 s) and second model (0.79 against 0.06 s), NetworkDynamics' new equations (9.0 against 1.1 s, 1.5 s of it compiled again). C-54 below is the likely cause for the last three, not yet shown.
  - **The floor** (E-291): a bare Julia process takes 0.15–0.18 s on every build, Python 0.02 s.
- **The default `Dynamic` at an argument whose trait names a method's variables** is `Compiled` (C-54), so TraitDifferentialEquations' `ODEProblem(f, …)` compiles the solver per function by default.
- **Keys** are Optional, built late (W-110).

## 6. The software: today, the target, the order of work

<a id="today"></a>
### 6.1 Today (2026-11-08)

- **Julia:** `julia-unified` `unified` 350c5b1c59 (with 49ab4294b6, the slot's last resort). The earlier build: `julia-1.13` 00dcc9994c.
- **TraitWorld:** `TraitWorld-unified` `unified` e967ca0. The earlier library: `TraitWorld` `main` 33dd55e.
- **The ports on the unified build:** TraitTables `unified` d964a98, TraitCSV 90e7330, TraitMakie 499af5d, TraitReport a4bcf33, forks 128ef6b, TraitDifferentialEquations 41837ed, NetworkDynamics `unified` fc25b89, Graphs dbcb7c70 and GraphMakie `unified` (in `ndport`, 5ae8421). On the earlier build: their branches `main` (TraitDifferentialEquations `w34`, `w96`), NetworkDynamics' port in `ndport`.
- **Tests:** §4. **Measured:** [`evidence.md`](design/evidence.md).

### 6.2 The target

The design of the references, built on Julia as a stack of self-contained commits, proposed upstream where they are useful without traits (W-19), with TraitWorld as a package. Keys (Optional) come late; the machine-code cache (W-120) is decided after the profiling campaign.

### 6.3 The order of work

The work queue, with every agreed item, its source and status, is [`record/todo.md`](record/todo.md). The order:
1. **The ports** (W-104): every port runs; slice 3's sessions against the evidence remain (E-284, E-285 done for slices 1 and 2).
2. **The profiling campaign** (W-121; the user, 2026-11-07): where the time goes in the goal's session, a first Makie + DataFrames workload against Python; its first item is the load path (§5), whose cause is C-72 (E-290). Performance work is prioritised from it, the machine-code cache (W-120) and reworking the ports included: [the plan to reach Python's speed](plans/2026-11-08-python-speed.md), adopted (the user, 2026-11-08; target: within Python + 1 s; no workloads made for the task): W-123 (the walk, C-72) first, then W-124 to W-127.
3. Queued: W-119 (the slot's share in the ports), W-115 to W-118.

**Performance work** follows the rule of 2026-10-27 ([decisions](record/decisions.md) §5): principled architectural improvements, and bugs with an impact of 20 % or more or slowdowns where trait code should be as fast as plain code, without a significant increase in complexity.

Waiting for the user: the choices marked mine ([open issues](open-issues.md) §1), among them the recommendations of open issues 158 and 159; upstream proposals (W-19).

What was done, in order, is in [the design history](record/design-history.md) and the session notes.
