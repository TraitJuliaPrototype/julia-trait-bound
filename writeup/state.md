# The state of the prototype (2026-11-14)

Traits are abstract types on Julia's unified build: memberships live in the type system, dispatch picks methods at traits, and the ports run on it with upstream's results. Against Python, in a fresh process (§5): the goal's task (DataFrames + Makie) 1.77–1.83 s against 0.63–0.65 s, the ODE session (setting D) 1.89–1.91 s against 1.43–1.46 s, TraitReport's trait form 0.78–0.80 s against 0.63–0.65 s, the forks' REPL session 2.61–2.62 s against pandas' 0.69–0.75 s. The goals and where each stands: [`goals.md`](goals.md). Speed work is stopped; the claim is no regression where types are known.

For core developers. The design is the four [references](reference/README.md), each with a Deviations table; this page summarizes what is built. The changes to Julia are the [compiler reference](reference/compiler.md), with the inventory in [`design/julia-changes.md`](design/julia-changes.md); the measurements are in [`design/evidence.md`](design/evidence.md). The earlier build (julia-1.13 with TraitWorld `main`) still runs, and most numbers in the evidence are its; its state on 2026-10-29 is [a dated snapshot](../attic/writeup/state-2026-10-29.md).

## 1. Where the project stands

- **The design:** the references for "traits are abstract types", adopted by the user on 2026-11-06. The choices marked mine since then stand, as input to the synthesis ([the goals](goals.md) §4; [open issues](open-issues.md) §1).
- **Julia** (`julia-unified`, branch `unified`): a stack of self-contained commits on v1.13.2, the changes useful without traits first ([julia-changes §7.1](design/julia-changes.md#71-the-stack)). The stages of [the work plan](plans/2026-11-06-work-plan-under-the-draft-reference.md) are built: W-98, W-99, W-107, W-108, W-109, W-100, W-111, W-112, W-113, W-114, W-101, and W-129. Latest: `unified` 7b374f39ce.
- **The library** (`TraitWorld-unified`, branch `unified`): a library on the new type system, with the next iteration's D-1 and D-3 (W-151), its forwarders made where a method is defined on `julia-next` (W-160; traits T-125, compiler C-111), a trait's parameters left open erasing too (open issue 204), and D-9, D-12, D-13 (merged from `s3`). The library at the tag `prototype-2026-11` is e11c7cc (`TraitWorld-base`).
- **The ports** (W-104): every port runs on the unified build: slices 1 and 2 (the DataFrames side and the plotting core) and slice 3 (TraitDifferentialEquations, NetworkDynamics) (§4).
- **Performance:** speed work is stopped; the claim is no regression where types are known, and full speed by opting in ([the goals](goals.md) G-2; [decisions](record/decisions.md) §5). The numbers are in §5.

## 2. What the unified build changes in Julia

By the compiler reference's sections:
- **Memberships in the type system** ([§4](reference/compiler.md#4-sets-and-memberships)): a trait is an open abstract type; `jl_declare_membership` publishes an entry in a new world; subtyping, intersection and the type cache read the entries; negatives fold with an absence edge at the pair; intersections `All{X, Y, …}`; a set's inputs (C-32 retired).
- **Dispatch at traits** ([§5](reference/compiler.md#5-dispatch)): specificity with a closed type above a trait; the ambiguity report at a membership; a membership replays the trait's methods at its member and invalidates the callers whose selection changes, as a method does (W-140).
- **The facts mode** ([§1](reference/compiler.md#1-the-facts-inference), [§2](reference/compiler.md#2-the-policy-per-method)): a trait module's calls are inferred only at fact signatures, with run-time sites elsewhere; one CodeInstance per method and policy; images keep code by the G2 bit.
- **The attribute** ([§6](reference/compiler.md#6-keys-and-the-attribute)): a trait argument compiled for the value's type or once, decided by a cast, the value, the method or module, the trait's default or the scope; `Core.Dynamic`, `keep`, the casts, whose names are bound and not reserved.
- **Operations on a value known by its trait** ([§7](reference/compiler.md#7-operations-on-a-value-typed-by-its-trait)): the declared result, a split over the first members, a table past them. `Callable` on `next` (W-161, D-2; eaa19da272, TraitWorld `unified` c14d2e4): every function a member by Core's entry, a callable struct by `@implement Callable T`; subtyping reads no method; the signature checked where a function is boxed or a wrapper enters (E-500; compiler C-146, traits T-156). On `next` (W-161, D-4; 5448a8b7bf, TraitWorld `unified` c838f76): an operation without a default is an entry of the contract (`TypeName.operations`), which inference reads; no method at the set carries it, and the kept forms forward by methods of their own. The library's late load ends no plain instance (E-498).
- **G2 as the deep class** ([§3.2](reference/compiler.md#32-g2-as-a-predicate)): on `next` 7063158f42 the G2 bit marks code that rests on facts, bindings and memberships at any depth, decided at a CodeInstance's finish; the image's keep rule reads it, and the library's strict mode (TraitWorld `unified` bb4ad00). An operation's split names an inlined branch by its CodeInstance (3037289af6). The code slot is removed on `next` (9b6dacf5c5). `unified` keeps the one-level bit and the slot.
- **One way to erase, the compiler's part, on `next`** (W-160; [julia-changes §7.2](design/julia-changes.md#72-branch-next-the-next-iteration)): a method at a trait that erases by default is made at the kept forms with its forwarder where it is defined, by the library's expansion hook (8b1ec88a56; [§6.3](reference/compiler.md#63-the-forwarders)); a positive membership at `new`, a store into storage typed by the trait and a `typeassert` is decided where the code is compiled, the entry recorded with an edge (8c2d3a5457, 5b1900641f; [§4.8](reference/compiler.md#48-negatives-fold-with-an-edge-positives-through-entries)); a membership's edge counts in the deep class (76ae6b0ee7); a membership replays a method at a bound the signature sets, as at the kept forms, at the method's own signature and keeps its instances (75a7f1795b; [§5.5](reference/compiler.md#55-a-membership-invalidates-as-a-method-does)). The definition-time check reads the method's instance at the box from Julia's cache (TraitWorld 9c0912b; [§6.7](reference/compiler.md#67-the-definition-time-check), C-115). Measured: [the evidence](design/evidence.md#one-way-to-erase-the-compilers-part-w-160-e-436-to-e-444).
- **The third wave, merged into `next`** (W-155, continued, on `next-s3`; [julia-changes §7.3](design/julia-changes.md#73-branch-next-s3-the-third-wave); merged at `next` f8c2bf5f95 with TraitWorld `unified` 23717c1, W-161, E-496): a membership adds no type equality inside an invariant parameter (e967266d9e; [§4.5](reference/compiler.md#45-subtyping)); a positive membership's edge keeps code in the deep class (e7681dfc54; open issue 211); a pirate is reported by default where it ends deep code (5d2ec7ff85, TraitWorld `s3` 2770c10; [traits §12.2](reference/traits.md#122-pirates)); owner-only functions: a trait module's internal functions and those declared `@owner_only` take methods from their owner only, and a call of one is a fact at any signature (e483299622, TraitWorld `s3` 4210852; [facts §3](reference/facts.md#3-fact-signatures)); TraitMakie's asserted barriers removed (`unified` d905a0b); the membership walk's rooting (c31fce89d7; open issue 189 closed); a membership taken back, as a method is deleted, `delete_membership` (213c759370, TraitWorld `s3` 9e0e3f4; [traits §5.13](reference/traits.md#513-taking-a-membership-back)); Revise's part not built (lowering L-64).
- **Base's surface, stage 5** (W-157, on `next-s3` to bc844be7c0; [julia-changes §7.3](design/julia-changes.md#73-branch-next-s3-the-third-wave); [compiler §11](reference/compiler.md#11-changes-useful-without-traits)): Base's error paths build their exception at a concrete signature (297d19aca1); the type joins read type fields with `getfield` and call each other through `invoke` (ab96564f36); `yieldto` writes with `setfield!` (396cd65a48); `Val(x)` builds with `new` (024755ee89); `IOContext` stores a property by `invoke` (bc844be7c0); an edge names the callee's code where it exists when the caller finishes (0a07a715ca; [§3.2](reference/compiler.md#32-g2-as-a-predicate)); `!==`'s edge keeps the call's signature (6b3175dc9c; [§3.1](reference/compiler.md#31-the-record)). The deep class holds 63 % of the forks' own facts instances and 79 % of upstream's by facts (E-478); the work after unrelated loads and plain code's first work are unchanged (E-478's control, E-479). The commits to 396cd65a48 are in `next`; 024755ee89 and bc844be7c0 are not yet.
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
- **Julia, the next iteration:** `julia-next` `next` eaa19da272: D-2 (eaa19da272) and D-4 (5448a8b7bf) on W-155's deep class, split's branch edge and code slot removed (9b6dacf5c5); W-160's compiler for one way to erase (to 75a7f1795b); the third wave of `next-s3` merged (D-11, open issue 211, D-12, D-9, open issue 189, D-13, and W-157's first commits to 396cd65a48; W-161, E-496). W-157's last commits (`Val`, `IOContext`) are on `next-s3` bc844be7c0 only, to merge.
- **TraitWorld:** `TraitWorld-unified` `unified` d1febca: W-151's prototype, W-160's expansion hook and check, the third wave's `s3` merged (23717c1), open issue 204's rule (fb67ac1), D-4's operations as contract entries (c838f76, 4b6c1d6), D-2's `Callable` at the box (c14d2e4, d1febca); compiled by facts (E-326); e11c7cc at the tag. The earlier library: `TraitWorld` `main` 33dd55e.
- **The ports on the unified build:** TraitTables `unified` c339175, TraitCSV 92c46d0, TraitMakie d905a0b, TraitReport a4bcf33, forks bf6799b, TraitDifferentialEquations ae1a966, NetworkDynamics `unified` 6d311a3, Graphs dbcb7c7 and GraphMakie `unified` 498be7c (in `ndport`). On the earlier build: their branches `main` (TraitDifferentialEquations `w34`, `w96`), NetworkDynamics' port in `ndport`.
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

The synthesis waits for the user: its seven decisions ([§7](plans/2026-11-14-synthesis.md#7-decisions-for-the-user)). [A review of the conceptual design](reviews/2026-11-15-conceptual-design.md) stands beside it. Both are consolidated in [one plan for the next iteration](plans/2026-11-15-next-iteration.md), adopted by the user (2026-11-15): its table holds the synthesis' decisions and the review's proposals, each marked decided, to confirm or mine; its stages are W-151 and W-153 to W-159 in [the work queue](record/todo.md). The baseline is the tag `prototype-2026-11` on every repository; Julia's work goes on in `julia-next`.

What was done, in order, is in [the design history](record/design-history.md) and the session notes.
