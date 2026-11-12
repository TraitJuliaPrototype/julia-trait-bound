# The state of the prototype (2026-11-09)

Traits are abstract types on Julia's unified build: memberships live in the type system, dispatch picks methods at traits, and the ports run on it with upstream's results. Against Python, in a fresh process (§5): the goal's task (DataFrames + Makie) 1.76–1.80 s against 0.63–0.65 s, the ODE session (setting D) 1.96–1.98 s against 1.43–1.46 s, TraitReport's trait form 0.79–0.83 s against 0.63–0.65 s, the forks' REPL session 2.95–3.56 s against pandas' 0.69–0.75 s. The goals and where each stands: [`goals.md`](goals.md). Speed work is stopped; the claim is no regression where types are known.

For core developers. The design is the four [references](reference/README.md), each with a Deviations table; this page summarizes what is built. The changes to Julia are the [compiler reference](reference/compiler.md), with the inventory in [`design/julia-changes.md`](design/julia-changes.md); the measurements are in [`design/evidence.md`](design/evidence.md). The earlier build (julia-1.13 with TraitWorld `main`) still runs, and most numbers in the evidence are its; its state on 2026-10-29 is [a dated snapshot](../attic/writeup/state-2026-10-29.md).

## 1. Where the project stands

- **The design:** the references for "traits are abstract types", adopted by the user on 2026-11-06. The choices marked mine since then stand, as input to the synthesis ([the goals](goals.md) §4; [open issues](open-issues.md) §1).
- **Julia** (`julia-unified`, branch `unified`): a stack of self-contained commits on v1.13.2, the changes useful without traits first ([julia-changes §7.1](design/julia-changes.md#71-the-stack)). The stages of [the work plan](plans/2026-11-06-work-plan-under-the-draft-reference.md) are built: W-98, W-99, W-107, W-108, W-109, W-100, W-111, W-112, W-113, W-114, W-101, and W-129. Latest: `unified` b05ae361e0.
- **The library** (`TraitWorld-unified`, branch `unified`): a library on the new type system, 4443d2c.
- **The ports** (W-104): every port runs on the unified build: slices 1 and 2 (the DataFrames side and the plotting core) and slice 3 (TraitDifferentialEquations, NetworkDynamics) (§4).
- **Performance:** speed work is stopped; the claim is no regression where types are known, and full speed by opting in ([the goals](goals.md) G-2; [decisions](record/decisions.md) §5). The numbers are in §5.

## 2. What the unified build changes in Julia

By the compiler reference's sections:
- **Memberships in the type system** ([§4](reference/compiler.md#4-sets-and-memberships)): a trait is an open abstract type; `jl_declare_membership` publishes an entry in a new world; subtyping, intersection and the type cache read the entries; negatives fold with an absence edge at the pair; intersections `All{X, Y, …}`; a set's inputs (C-32 retired).
- **Dispatch at traits** ([§5](reference/compiler.md#5-dispatch)): specificity with a closed type above a trait; the ambiguity report at a membership; a membership replays the trait's methods at its member and invalidates the callers whose selection changes, as a method does (W-140).
- **The facts mode** ([§1](reference/compiler.md#1-the-facts-inference), [§2](reference/compiler.md#2-the-policy-per-method)): a trait module's calls are inferred only at fact signatures, with run-time sites elsewhere; one CodeInstance per method and policy; images keep code by the G2 bit.
- **The attribute** ([§6](reference/compiler.md#6-keys-and-the-attribute)): a trait argument compiled for the value's type or once, decided by a cast, the value, the method or module, the trait's default or the scope; `Core.Dynamic`, `keep`, the casts.
- **Operations on a value known by its trait** ([§7](reference/compiler.md#7-operations-on-a-value-typed-by-its-trait)): the declared result, a split over the first members, a table past them; `Callable` by the function's own methods.
- **The code slot** ([§3.3](reference/compiler.md#33-the-code-slot)): a call that holds only a result edge goes through a slot; a callee recompiled to an equal result keeps its callers; a miss with no code to make gets a dispatching entry.
- **Non-memberships relied on** ([§4.8](reference/compiler.md#48-negatives-fold-with-an-edge-positives-through-entries)): at every trait, wherever the code is compiled; `isa` folds with an absence edge at the pair, and a later membership's method invalidates the code ([§5.6](reference/compiler.md#56-the-memberships-method-and-the-edges); W-129 (a), W-140, W-141; C-77, C-79, C-88). What the mechanism leaves: open issue 180.
- **`IO`'s contract** ([§7.5](reference/compiler.md#75-io); [traits §9b](reference/traits.md#9b-streams-io)): `IO` is Julia's closed abstract type, and Base's methods typed `io::IO` are compiled per stream type; its contract's operations split over `IOBuffer`, `IOStream`, `TTY` and `PipeEndpoint` at a value typed `IO`, their results `Any` and nothing converted (open issue 171, E-340), the candidates kept with the contract by any image (C-81); the eraser `IOContext{IO}`; the REPL's display and `TextDisplay` erase the stream (E-339). The split's targets at a stream past the candidates are compiled at the first call (open issue 170).
- **Images and hooks** ([§9](reference/compiler.md#9-images-and-the-machine-code-cache), [§10](reference/compiler.md#10-hooks-for-the-library)): an image keeps and activates its memberships; the member hook, the definition, module-end, deletion and fully-typed hooks.

The inventory, one row per commit: [julia-changes](design/julia-changes.md), rows 1–84.

## 3. The library

TraitWorld `unified`: `@trait` (operations, defaults, fields, inputs, supertraits), `@implement` (forms, families with their variables in the block, forwarding), the checks at a declaration and at a member's first use, the classification of methods as fully bounded or open with `bounded` and `@open`, `@trait_module`, `Dynamic{X}`'s memberships and methods, `Callable`, strict mode and ownership, fully typed mode, compiling ahead, hints, and BaseTraits (`HasLength`, `Iterable`, `Indexable`, `MutableIndexable`, `Resizable`, `Keyed`, `HasProperty`, `Solvable`, `LinearOp`, `BoundedText`). Its deviations: [traits](reference/traits.md#19-deviations) (T-) and [lowering](reference/lowering.md#15-deviations) (L-).

## 4. The ports (W-104)

Each port lives on a branch `unified` in a sibling worktree, `<Repo>-unified` ([the plan](plans/2026-11-07-w104-ports.md)).

| Slice | Port | On the unified build | Checked on (2026-11-08) |
|---|---|---|---|
| 1 | TraitTables, TraitCSV, TraitMakie | their suites pass | `unified` 350c5b1c59, TraitWorld d897223 or bd9a721 |
| 1 | TraitReport, trait form | its summary and PNG equal the plain form's on three datasets; forms (t) and (pt) agree | (t), (pt): `unified` e9b9261808, TraitWorld 24a5fcd (E-307) |
| 2 | the forks of Tables, CSV, DataFrames, with CSV's reader and DataFrames' module compiled by facts | the session's digests equal upstream's at 26 steps (E-308); Tables' suite passes; CSV's passes in full, 330,545 (E-302); DataFrames' failed 7 (E-305): `tables.jl:86` (open issue 158's second case) passes since C-36 (E-315); `Tables.subset` (`tables.jl:326`), reached after it, and 3 `@inferred` see `Any`: run-time sites in facts code (open issue 157 (a)) | digests: `unified` 24c8d4db60, forks 27d4baa; suites: `unified` d04256a442 (CSV), e9b9261808 (DataFrames); DataFrames' four files: 523214899f (E-315) |
| 3 | TraitDifferentialEquations | every package loads; its suite passes, 32 testsets, none broken | `unified` e9b9261808, TDE fcee973, TraitWorld 24a5fcd (E-307) |
| 3 | NetworkDynamics (with Graphs' port, GraphMakie's over MakieCompat) | its test subset and its workload's 32 digests give the earlier build's results; a batch keeps its model with the trait's default, and the kernel types the model by the trait | subset: `unified` 23022b0ec7 (E-324); digests: `unified` 523214899f, NetworkDynamics 7e8997d, TraitWorld 6b342e9 (E-314) |

The ports found the design's open questions [157](open-issues.md#2-design) (a function barrier in facts code loses its callee's declared result), [159](open-issues.md#2-design) (a function stored before its signature is known keeps no attribute), [161](open-issues.md#2-design) (a library's own type that wraps a user's function) and [162](open-issues.md#2-design) (a cast at a parameter no trait types has no effect, silently), and fixes in the runtime and the library (W-104's row in [the work queue](record/todo.md)).

The tests of the build itself (2026-11-09, the battery `w337` on `unified` b05ae361e0 with TraitWorld 4443d2c, `experiments/unification/stack/logs/`, E-337): the gates 57 of 57; Base's `core`, `subtype`, `worlds`, `ambiguous`, `reflection`, `Compiler/inline` and `Compiler/inference`; `precompile` 457 of 457; the 21 acceptance cases; TraitWorld's suite; both workloads.

## 5. Not yet established

The deviations of the implementation from the design are listed per reference: [traits](reference/traits.md#19-deviations) (T-), [facts](reference/facts.md#16-deviations) (F-), [compiler](reference/compiler.md#deviations) (C-), [lowering](reference/lowering.md#15-deviations) (L-). Beyond them:

- **The unified build against the earlier build, on the same host** (E-289, 2026-11-08; [evidence §3](design/evidence.md#3-first-calls-and-sessions)):

  | Session | Python | Earlier build | Unified build |
  |---|---|---|---|
  | the goal's task, DataFrames + Makie (TraitReport's form (f)) | 0.63–0.65 s | 2.46–2.49 s | 27.1–27.4 s; 7.62–7.75 s (E-292); 4.98–5.11 s (E-295); 3.62–3.70 s (E-296); 3.37–3.45 s (E-298); 2.37–2.40 s (E-300); 2.21–2.28 s (E-301); 1.91–1.95 s (E-302: the forks' CSV by facts); 1.81–1.83 s (E-303); 1.56–1.61 s (E-305: DataFrames by facts); 1.54–1.61 s (E-307); 1.60–1.65 s (E-316); 1.59–1.63 s (E-324); 1.62–1.63 s (E-326: TraitWorld by facts); **1.76–1.80 s** (E-337: the imports +0.15 s, not explained, PE-31) |
  | the forks' DataFrames session at a REPL | 0.69–0.75 s | 5.06–5.07 s | 38.0–38.5 s; 6.48–6.51 s (E-292); 9.86–10.42 s (E-296: §5.6's pruned arms at a REPL); 4.76–5.17 s (E-298); 4.08–4.44 s (E-300); 3.98–4.42 s (E-301); 3.89–4.04 s (E-302); 3.67–3.70 s (E-303); 3.82–4.01 s (E-305); 3.75–3.98 s (E-307); 3.11–3.24 s (E-308); 3.25–3.53 s (E-313, the harness's `TERM=dumb`); 3.00–3.28 s (E-316); 3.01–3.34 s (E-324); 2.85–3.14 s (E-326); **2.95–3.56 s** (E-337); 2.56–2.68 s on branch `b-display` (E-338) |
  | TDE + TraitMakie, setting D | 1.43–1.46 s (E-230) | 1.34–1.35 s (E-242) | 11.59–11.77 s; 9.19–9.28 s (E-295); 6.35–6.56 s (E-296); 3.42 s (E-298); 2.82–2.84 s (E-300); 2.75–2.82 s (E-301); 2.52–2.54 s (E-303); 2.04–2.05 s (E-307); 1.98–2.01 s (E-316); 2.00–2.04 s (E-324); 2.00–2.01 s (E-326); **1.96–1.98 s** (E-337) |
  | TraitReport (t) | 0.63–0.65 s (the goal's Python app, E-289) | 0.63 s (E-233) | 3.18–3.20 s (E-286); 0.99–1.04 s (E-292); 1.02–1.07 s (E-296); 0.97–0.99 s (E-298); 0.89–0.91 s (E-300); 0.775–0.821 s (E-301); 0.73–0.76 s (E-303); 0.72–0.75 s (E-307); 0.75–0.78 s (E-316); 0.74–0.78 s (E-324); 0.73–0.78 s (E-326); **0.79–0.83 s** (E-337) |
  | NetworkDynamics' new equations (`changed` b–e) | — | 1.10 s (E-250) | 9.0 s (W-104); 6.6–6.7 s (E-309); 0.59–0.62 s (E-310 (a)); 0.59–0.66 s (E-314); **0.57 s** (E-327) |
  | NetworkDynamics' steady state (`again` d) | — | 776–780 ms (E-250) | 189–230 ms (E-309); 182–213 ms (E-310 (a)); 451–475 ms (E-310 (b)); 228–257 ms (E-314); 224–240 ms (E-324); **237–241 ms** (E-327) |

  - **With `IO`'s contract on the closed type** (`unified` b05ae361e0, E-337, load 5.9–7.2, the early build's forms interleaved as the control): the goal's task 1.76–1.80 s against 2.46–2.57 s; the forks' session 2.95–3.56 s against 5.19–5.58 s, its `show` step 0.081–0.110 s against 0.204–0.217 s; E-328's workloads on an `IOBuffer` vanilla's within the runs' noise ([evidence](design/evidence.md)). Against the build of the morning (E-326, 1.62–1.63 s) the goal's task is 0.15 s slower, all of it in the imports ([PE-31](record/performance-explorations.md)); the extra time is not code compiled at load (the same 28 compiles; [the performance review](reviews/2026-11-09-performance-day.md) H1, M1).
  - **Loading:** the dispatch walk at activation (C-72) and the library's interpreter invalidating the compiler (C-40) are fixed (W-123, E-292). What remains is compiling at load: plain packages' methods invalidate ten times as much of the compiler's own code as on vanilla (2,049 against 193 instances for upstream CSV and DataFrames), through untyped narrowings in the stack's own compiler code: fixed (28d2334164, E-295: 195 instances against vanilla's 193). TraitWorld's load hooks invalidated by plain packages: fixed in the library (e6eaa85, E-296). At a REPL, TraitWorld's methods at sets for required operations invalidated the system image's code with a pruned `Nothing` arm (compiler §5.6; E-296); open issue 158 (a) makes them no shadow (B2 and TraitWorld c4f9f99): the forks' session 4.8–5.2 s (E-298). Validation's walk of the memberships at each match is gone (89b3bcff81, E-300: the goal's task 2.4 s); what the loads still spend is Julia's own validation, scaled by the images' size, and image restore.
  - **The imports:** the goal's task 0.98–1.03 s against Python's 0.47 s (E-307), the forks' session 0.86–0.96 s (E-308). What the loads spend is Julia's validation of the images' edges and image restore (E-303, E-304).
  - **After the imports:** the goal's read, summary and plot 0.27 s against the earlier build's 0.36 s and Python's 0.08 s (E-307); the forks' steps 1.55 s against 2.80 s and pandas' 0.41 s (E-308). What the forks' steps still compile: DataFrames' `show` at the REPL's stream; CSV's task closures come from its image (E-311). Slower than the earlier build: setting D's first solve 0.34 s against 0.19 s (E-307). Faster: NetworkDynamics' new equations 0.59–0.66 s against 1.1 s, its steady state 228–257 ms against 776–780 ms (E-314). Setting D's second model 0.05–0.06 s, as on the earlier build.
  - **The REPL in a capable terminal** (`TERM=screen`, `xterm-256color`): the first line after `using` compiles the hint code again, 0.6 s on either build, because DataStrings' `print(io::IO, ::DataString)` invalidates it at load (E-313, [PE-25](record/performance-explorations.md)). The session harnesses fix `TERM=dumb`.
  - **The floor** (E-291): a bare Julia process takes 0.15–0.18 s on every build, Python 0.02 s.
- **An argument typed by a set, or by a `where` variable bounded by one** (`x::C`, `C <: X`), takes its attribute; the variable is the value's type under either (W-148). One typed by a set that names the method's variables (`X{T}`) is compiled once at its instance: TraitDifferentialEquations' `ODEProblem(f, …)` compiles the solver once per state type (E-298).
- **Keys** are Optional, built late (W-110).

## 6. The software: today, the target, the order of work

<a id="today"></a>
### 6.1 Today (2026-11-10)

- **Julia:** `julia-unified` `unified` b1c0b50f4c. The earlier build: `julia-1.13` 00dcc9994c.
- **TraitWorld:** `TraitWorld-unified` `unified` 347176a, compiled by facts (E-326). The earlier library: `TraitWorld` `main` 33dd55e.
- **The ports on the unified build:** TraitTables `unified` 160639e, TraitCSV 92c46d0, TraitMakie c9e294b, TraitReport a4bcf33, forks ddc20f6, TraitDifferentialEquations 6658c65, NetworkDynamics `unified` d8c9c49, Graphs dbcb7c7 and GraphMakie `unified` 498be7c (in `ndport`, 1e024b5). On the earlier build: their branches `main` (TraitDifferentialEquations `w34`, `w96`), NetworkDynamics' port in `ndport`.
- **Tests:** §4. **Measured:** [`evidence.md`](design/evidence.md).

### 6.2 The target

The design of the references, built on Julia as a stack of self-contained commits, proposed upstream where they are useful without traits (W-19), with TraitWorld as a package. Keys (Optional) are purely a performance optimization and deferred (PE-33); the machine-code cache across sessions (W-120) is being revisited.

### 6.3 The order of work

The work follows [the schedule to the synthesis](plans/2026-11-11-complete-prototype.md). The work queue, with every item, its source and status, is [`record/todo.md`](record/todo.md). The phases:
1. Triage: every open question and deviation in a bin (A before the measurement round, B to the synthesis, C accepted). Done. Three of bin A's decisions are made (the `where` variable, kept values, the abstract result). The membership as a method (W-141) is decided: a membership behaves as a method does, and its method of the runtime's function is the implementation of its edges (compiler §5.6, open issue 180).
2. Bin A: the design questions that change the mechanism, then the deviations (W-142, W-143's tool, W-128).
3. The cache across sessions, bounded (W-120; G-3).
4. The ports brought to the head (W-104).
5. Freeze, then the measurement round (W-145).
6. Low-hanging performance work (W-146).
7. The ports' lessons and tensions, checked (W-147).
8. The synthesis (W-138); then the upstream patches (W-19).

The prototype is conceptually complete when bin A is empty and the cache is built or stopped. The speed work is retired; its log is an archive. Deferred: keys (W-110), purely a performance optimization.

Nothing waits for the user. The choices marked mine and the flagged tensions are input to the synthesis ([open issues](open-issues.md) §1).

What was done, in order, is in [the design history](record/design-history.md) and the session notes.
