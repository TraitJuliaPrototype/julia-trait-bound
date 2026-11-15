# The state of the prototype (2026-11-14)

Traits are abstract types on Julia's unified build: memberships live in the type system, dispatch picks methods at traits, and the ports run on it with upstream's results. Against Python, in a fresh process (§5): the goal's task (DataFrames + Makie) 1.77–1.83 s against 0.63–0.65 s, the ODE session (setting D) 1.89–1.91 s against 1.43–1.46 s, TraitReport's trait form 0.78–0.80 s against 0.63–0.65 s, the forks' REPL session 2.61–2.62 s against pandas' 0.69–0.75 s. The goals and where each stands: [`goals.md`](goals.md). Speed work is stopped; the claim is no regression where types are known.

For core developers. The design is the four [references](reference/README.md), each with a Deviations table; this page summarizes what is built. The changes to Julia are the [compiler reference](reference/compiler.md), with the inventory in [`design/julia-changes.md`](design/julia-changes.md); the measurements are in [`design/evidence.md`](design/evidence.md). The earlier build (julia-1.13 with TraitWorld `main`) still runs, and most numbers in the evidence are its; its state on 2026-10-29 is [a dated snapshot](../attic/writeup/state-2026-10-29.md).

## 1. Where the project stands

- **The design:** the references for "traits are abstract types", adopted by the user on 2026-11-06. The choices marked mine since then stand, as input to the synthesis ([the goals](goals.md) §4; [open issues](open-issues.md) §1).
- **Julia** (`julia-unified`, branch `unified`): a stack of self-contained commits on v1.13.2, the changes useful without traits first ([julia-changes §7.1](design/julia-changes.md#71-the-stack)). The stages of [the work plan](plans/2026-11-06-work-plan-under-the-draft-reference.md) are built: W-98, W-99, W-107, W-108, W-109, W-100, W-111, W-112, W-113, W-114, W-101, and W-129. Latest: `unified` 7b374f39ce.
- **The library** (`TraitWorld-unified`, branch `unified`): a library on the new type system, e11c7cc.
- **The ports** (W-104): every port runs on the unified build: slices 1 and 2 (the DataFrames side and the plotting core) and slice 3 (TraitDifferentialEquations, NetworkDynamics) (§4).
- **Performance:** speed work is stopped; the claim is no regression where types are known, and full speed by opting in ([the goals](goals.md) G-2; [decisions](record/decisions.md) §5). The numbers are in §5.

## 2. What the unified build changes in Julia

By the compiler reference's sections:
- **Memberships in the type system** ([§4](reference/compiler.md#4-sets-and-memberships)): a trait is an open abstract type; `jl_declare_membership` publishes an entry in a new world; subtyping, intersection and the type cache read the entries; negatives fold with an absence edge at the pair; intersections `All{X, Y, …}`; a set's inputs (C-32 retired).
- **Dispatch at traits** ([§5](reference/compiler.md#5-dispatch)): specificity with a closed type above a trait; the ambiguity report at a membership; a membership replays the trait's methods at its member and invalidates the callers whose selection changes, as a method does (W-140).
- **The facts mode** ([§1](reference/compiler.md#1-the-facts-inference), [§2](reference/compiler.md#2-the-policy-per-method)): a trait module's calls are inferred only at fact signatures, with run-time sites elsewhere; one CodeInstance per method and policy; images keep code by the G2 bit.
- **The attribute** ([§6](reference/compiler.md#6-keys-and-the-attribute)): a trait argument compiled for the value's type or once, decided by a cast, the value, the method or module, the trait's default or the scope; `Core.Dynamic`, `keep`, the casts, whose names are bound and not reserved.
- **Operations on a value known by its trait** ([§7](reference/compiler.md#7-operations-on-a-value-typed-by-its-trait)): the declared result, a split over the first members, a table past them; `Callable` by the function's own methods.
- **The code slot** ([§3.3](reference/compiler.md#33-the-code-slot)): a call that holds only a result edge goes through a slot; a callee recompiled to an equal result keeps its callers; a miss with no code to make gets a dispatching entry.
- **Non-memberships relied on** ([§4.8](reference/compiler.md#48-negatives-fold-with-an-edge-positives-through-entries)): at every trait, wherever the code is compiled; `isa` folds with an absence edge at the pair, and a later membership's method invalidates the code ([§5.6](reference/compiler.md#56-the-memberships-method-and-the-edges); W-129 (a), W-140, W-141; C-77, C-79, C-88). What the mechanism leaves: open issue 180.
- **`IO`'s contract** ([§7.5](reference/compiler.md#75-io); [traits §9b](reference/traits.md#9b-streams-io)): `IO` is Julia's closed abstract type, and Base's methods typed `io::IO` are compiled per stream type; its contract's operations split over `IOBuffer`, `IOStream`, `TTY` and `PipeEndpoint` at a value typed `IO`, their results `Any` and nothing converted (open issue 171, E-340), the candidates kept with the contract by any image (C-81); the eraser `IOContext{IO}`; the REPL's display and `TextDisplay` erase the stream (E-339). The split's targets at a stream past the candidates are compiled at the first call (open issue 170).
- **Images and hooks** ([§9](reference/compiler.md#9-images-and-the-machine-code-cache), [§10](reference/compiler.md#10-hooks-for-the-library)): an image keeps and activates its memberships; the member hook, the definition, module-end, deletion and fully-typed hooks.

The inventory, one row per commit: [julia-changes](design/julia-changes.md), the unified build's rows.

## 3. The library

TraitWorld `unified`: `@trait` (operations, defaults, fields, inputs, supertraits), `@implement` (forms, families with their variables in the block, forwarding), the checks at a declaration and at a member's first use, the classification of methods as fully bounded or unbounded with `bounded` and `@unbounded`, `@trait_module`, `Dynamic{X}`'s memberships and methods, `Callable`, strict mode and ownership, fully typed mode with `fully_typed` as the closed build's check, compiling ahead (`make_executable`, `make_library`), hints, and BaseTraits (`HasLength`, `Iterable`, `Indexable`, `MutableIndexable`, `Resizable`, `Keyed`, `HasProperty`, `Solvable`, `LinearOp`, `BoundedText`). Its deviations: [traits](reference/traits.md#19-deviations) (T-) and [lowering](reference/lowering.md#15-deviations) (L-).

## 4. The ports (W-104)

Each port lives on a branch `unified` in a sibling worktree, `<Repo>-unified` ([the plan](plans/2026-11-07-w104-ports.md)).

| Slice | Port | On the unified build | Checked on (2026-11-08) |
|---|---|---|---|
| 1 | TraitTables, TraitCSV, TraitMakie | their suites pass | `unified` 350c5b1c59, TraitWorld d897223 or bd9a721 |
| 1 | TraitReport, trait form | its summary and PNG equal the plain form's on three datasets; forms (t) and (pt) agree | (t), (pt): `unified` e9b9261808, TraitWorld 24a5fcd (E-307) |
| 2 | the forks of Tables, CSV, DataFrames, with CSV's reader and DataFrames' module compiled by facts | the session's digests equal upstream's at 26 steps (E-308); Tables' suite passes; CSV's passes in full, 330,545 (E-302); DataFrames' failed 7 (E-305): `tables.jl:86` (open issue 158's second case) passes since C-36 (E-315); `Tables.subset` (`tables.jl:326`), reached after it, and 3 `@inferred` see `Any`: run-time sites in facts code (open issue 157 (a)) | digests: `unified` 24c8d4db60, forks 27d4baa; suites: `unified` d04256a442 (CSV), e9b9261808 (DataFrames); DataFrames' four files: 523214899f (E-315) |
| 3 | TraitDifferentialEquations | every package loads; its suite passes, 32 testsets, none broken | `unified` e9b9261808, TDE fcee973, TraitWorld 24a5fcd (E-307) |
| 3 | NetworkDynamics (with Graphs' port, GraphMakie's over MakieCompat) | its test subset and its workload's 32 digests give the earlier build's results; a batch keeps its model with the trait's default, and the kernel types the model by the trait | subset: `unified` 23022b0ec7 (E-324); digests: `unified` 523214899f, NetworkDynamics 7e8997d, TraitWorld 6b342e9 (E-314) |

**On the head** (2026-11-14, E-373; `unified` 86deee2f98, TraitWorld baadf9f; `experiments/unification/w104/`): every demonstrator's suite ran, one at a time.
- TraitTables, TraitCSV, TraitMakie and TraitDifferentialEquations pass; TraitReport's two forms agree on three datasets.
- The forks: the session's digests equal upstream's at 26 steps and the REPL session's 20 marks print; Tables' and CSV's upstream suites pass (CSV 330,546); DataFrames' has the 4 errors of open issue 157 (a), as before.
- NetworkDynamics' subset gives the results of 2026-11-08.
- The ports follow the current rules: `@unbounded`; the casts' names imported; no `keep` into storage typed by a trait (`detect_kept_storage`, checked in the suites of TraitDifferentialEquations and TraitMakie).
- Found: a result annotation at a trait was inferred as `Any` (fixed at its rule, compiler §4.8).
- **On `unified` 7b374f39ce with TraitWorld e11c7cc** (E-392): the same suites give the same results.
- **The ODE port's front end is typed** (E-387; TraitDifferentialEquations 0483ac0 on `unified` 21c9b33e39): `ODEProblem`, `solve` and `init` return types their callers know, and the attribute decides what is compiled once. The suite passes; the session costs 6 % more. Its program does not build yet: 50 errors where there were 122, in the solver core's callbacks, Rodas5 and a sort ([open issue 184](open-issues.md#2-design)).

The ports found the design's open questions [157](open-issues.md#2-design) (a function barrier in facts code loses its callee's declared result), [159](open-issues.md#2-design) (a function stored before its signature is known keeps no attribute), [161](open-issues.md#2-design) (a library's own type that wraps a user's function) and [162](open-issues.md#2-design) (a cast at a parameter no trait types has no effect, silently), and fixes in the runtime and the library (W-104's row in [the work queue](record/todo.md)).

The tests of the build itself (2026-11-09, the battery `w337` on `unified` b05ae361e0 with TraitWorld 4443d2c, `experiments/unification/stack/logs/`, E-337): the gates 57 of 57; Base's `core`, `subtype`, `worlds`, `ambiguous`, `reflection`, `Compiler/inline` and `Compiler/inference`; `precompile` 457 of 457; the 21 acceptance cases; TraitWorld's suite; both workloads.

## 5. Not yet established

The deviations of the implementation from the design are listed per reference: [traits](reference/traits.md#19-deviations) (T-), [facts](reference/facts.md#16-deviations) (F-), [compiler](reference/compiler.md#deviations) (C-), [lowering](reference/lowering.md#15-deviations) (L-). Beyond them:

- **The sessions against Python, on the same host** ([evidence §3](design/evidence.md#3-first-calls-and-sessions); fresh processes after a warm-up; Python's numbers of E-289 and E-230):

  | Session | Python | The unified build |
  |---|---|---|
  | the goal's task, DataFrames + Makie (TraitReport's form (f)) | 0.63–0.65 s | 1.77–1.83 s (E-390) |
  | the forks' DataFrames session at a REPL | 0.69–0.75 s | 2.61–2.62 s (E-390) |
  | TDE + TraitMakie, setting D | 1.43–1.46 s | 1.89–1.91 s (E-389) |
  | TraitReport (t) | 0.63–0.65 s | 0.78–0.80 s (E-389) |
  | NetworkDynamics' workload, five passes | — | 43.4–43.7 s, the earlier build's digests (E-389) |

  - **Where a session's time goes** (E-388): a load is the images' validation and restore; after it, code generation and inference. The membership machinery is below a tenth of every phase.
  - **The imports** are the larger part of each session: 1.22–1.27 s of the goal's task, 0.37–0.39 s of TraitReport (t).
  - **The REPL in a capable terminal** (`TERM=screen`, `xterm-256color`): the first line after `using` compiles the hint code again, 0.6 s, because DataStrings' `print(io::IO, ::DataString)` invalidates it at load (E-313, [PE-25](record/performance-explorations.md)). The session harnesses fix `TERM=dumb`.
  - **The floor** (E-291): a bare Julia process takes 0.15–0.18 s on every build, Python 0.02 s.
- **An argument typed by a set, or by a `where` variable bounded by one** (`x::C`, `C <: X`), takes its attribute; the variable is the value's type under either (W-148). One typed by a set that names the method's variables (`X{T}`) is compiled once at its instance: TraitDifferentialEquations' `ODEProblem(f, …)` compiles the solver once per state type (E-298).
- **Keys** are Optional, built late (W-110).

## 6. The software: today, the target, the order of work

<a id="today"></a>
### 6.1 Today (2026-11-14)

- **Julia:** `julia-unified` `unified` 7b374f39ce. The earlier build: `julia-1.13` 00dcc9994c.
- **TraitWorld:** `TraitWorld-unified` `unified` e11c7cc, compiled by facts (E-326). The earlier library: `TraitWorld` `main` 33dd55e.
- **The ports on the unified build:** TraitTables `unified` c339175, TraitCSV 92c46d0, TraitMakie c862914, TraitReport a4bcf33, forks 439bae7, TraitDifferentialEquations b730628, NetworkDynamics `unified` 6310040, Graphs dbcb7c7 and GraphMakie `unified` 498be7c (in `ndport`). On the earlier build: their branches `main` (TraitDifferentialEquations `w34`, `w96`), NetworkDynamics' port in `ndport`.
- **Tests:** §4. **Measured:** [`evidence.md`](design/evidence.md).

### 6.2 The target

The design of the references, built on Julia as a stack of self-contained commits, proposed upstream where they are useful without traits (W-19), with TraitWorld as a package. Keys (Optional) are purely a performance optimization and deferred (PE-33); the machine-code cache across sessions (W-120) is not built now, and is judged from the measurement round.

### 6.3 The order of work

The work follows [the schedule to the synthesis](plans/2026-11-11-complete-prototype.md). The work queue, with every item, its source and status, is [`record/todo.md`](record/todo.md). The phases:
1. Triage: every open question and deviation in a bin (A before the measurement round, B to the synthesis, C accepted). Done. Three of bin A's decisions are made (the `where` variable, kept values, the abstract result). The membership as a method (W-141) is decided: a membership behaves as a method does, and its method of the runtime's function is the implementation of its edges (compiler §5.6, open issue 180).
2. Bin A: the design questions that change the mechanism, then the deviations (W-142, W-143's tool, W-128). W-142 is built: `fully_typed` in a session is the closed build's own check, and it agrees with the build on 17 of 18 programs (E-369; traits T-109). Bin A is empty: the prototype is conceptually complete.
3. The cache across sessions, bounded (W-120; G-3). Its first step is done (E-372): on the table and the ODE sessions the images hold the libraries' code, and a session compiles its own code and Julia's. The cache is not built now (the user, 2026-11-14); the measurement round carries the workloads that would exercise it ([the proposal](plans/2026-11-14-cache-across-sessions.md), with its addendum).
4. The ports brought to the head (W-104). Done (E-373): every suite passes or has its known failures; §4.
5. Freeze, then the measurement round (W-145). Done (E-374 to E-386) on `unified` 21c9b33e39, tag `round-2026-11-b`: [evidence](design/evidence.md) §1 to §4, each tension's cost in §4c.
6. Low-hanging performance work (W-146). Done on `unified` 7b374f39ce, TraitWorld e11c7cc (E-389 to E-391): an instance's code compiled once per result; the membership walk's substitution below a position's top; the definition-time check in inference's world.
7. The ports' lessons and tensions, checked (W-147). Done (E-392, E-393): the standings in [the goals](goals.md) §2.
8. The synthesis (W-138): written, [a proposal](plans/2026-11-14-synthesis.md) with seven decisions for the user. Then the upstream patches (W-19).

The speed work is retired; its log is an archive. Deferred: keys (W-110), purely a performance optimization.

The synthesis waits for the user: its seven decisions ([§7](plans/2026-11-14-synthesis.md#7-decisions-for-the-user)). [A review of the conceptual design](reviews/2026-11-15-conceptual-design.md) stands beside it. Both are consolidated in [one plan for the next iteration](plans/2026-11-15-next-iteration.md), a proposal: its table holds the synthesis' decisions and the review's proposals, each marked decided, to confirm or mine; its stages are W-151 and W-153 to W-159 in [the work queue](record/todo.md).

What was done, in order, is in [the design history](record/design-history.md) and the session notes.
