# The next iteration: one plan from the synthesis and the review

**Status:** adopted (2026-11-15, the user: "Have Opus agents implement the plan"). Written in the main session as a proposal the same day. Not normative: nothing here is in force until it is written into a reference. How it is run: §6.

The user (2026-11-15): "What would be the best way to act on the Synthesis+Review? Would it make sense to write a consolidated implementation plan that a new session can pick up?"

**What it consolidates.**
- [The synthesis](2026-11-14-synthesis.md) (W-138): the prototype against each goal, seven decisions for the user.
- [The review of the conceptual design](../reviews/2026-11-15-conceptual-design.md): four roots of the tensions, proposals P1 to P7, three addenda (P1 as accepted; the probes; `Callable`).
- The probes (W-152, E-394 to E-400): [evidence §1](../design/evidence.md#the-reviews-probes-w-152-e-394-to-e-400).
- The user's decisions of 2026-11-15: [the decision log](../record/decisions.md#pending), Pending.

**The answer in brief.** Yes: one plan, in stages, each with a gate that an existing experiment gives.
- The prototype is kept and changed. Most of the changes remove code.
- The measured state is tagged first, so every number of the round stays reproducible.
- The library comes before Julia, the references before the build, the ports after both.
- One short round at the end measures only what the changes claim to move.

## 1. To pick this up in a new session

**Read, in this order.**
1. `CLAUDE.md`: the rules for the documents and for the machine.
2. This plan.
3. [The review](../reviews/2026-11-15-conceptual-design.md): §1, §3, §4, then the three addenda. The addenda correct §4.1 and §4.3.
4. [The synthesis](2026-11-14-synthesis.md) §1, §3 and §7; [the goals](../goals.md) §2 and §3.
5. [The session note of 2026-11-15](../../session-notes/2026-11-15-review-and-p1.md): the user's words in full.

**The heads this plan was written on.**

| Repository | Branch | Head |
|---|---|---|
| the design repository | `w141-record` | this commit |
| `julia-unified` | `unified-w141` | 7b374f39ce |
| `TraitWorld-unified` | `unified` | e11c7cc |
| `forks-unified` (Tables, CSV, DataFrames) | `unified` | 439bae7 |
| `TraitTables-unified`, `TraitCSV-unified`, `TraitMakie-unified`, `TraitReport-unified` | `unified` | c339175, 92c46d0, c862914, a4bcf33 |
| `TraitDifferentialEquations-unified` | `unified` | b730628 |
| `ndport` (NetworkDynamics: `pkgs/NetworkDynamics-unified`) | `main` | 163d60e |
| `experiments` | `main` | 1e39190 |

**Where the status is.** Each stage is an item of [the work queue](../record/todo.md) (W-151, W-153 to W-159, W-19). The item's row holds the status. This plan is not updated as the work goes, but for its status line.

**How to work.**
- `source env.sh` first. Check `/proc/loadavg` before a compile. Build Julia with `tools-local/build.sh <tree>`.
- No subagents. No search outside the workspace. No campaign: a gate is a run of minutes.
- An experiment's registry row comes before its run. Scripts and logs go to `experiments/unification/<w-item>/` with a README.
- A decision goes into its reference first, then the decision log. A change to a rule and its deviation rows go in one commit.
- A gate that fails does not stop the stage. Record the choice (the reference, the decision log marked "mine", open issues §1) and go on. A failure names a pattern: look for the rule, and keep the tool that finds every instance.
- The run pattern of the probes: `experiments/unification/w152/README.md`.

**The first action.** Stage 0 is done (the tags). Read §6 for who works where, then the work queue for each stage's status.

## 2. What is decided, and what the plan takes

Adopting the plan takes every row marked *to confirm* as recommended, unless the user names an exception. The user adopted it on 2026-11-15 and named none: the rows marked *to confirm* are confirmed. Rows marked *mine* are choices of the agent: they stand as recorded and are input to the next synthesis (`CLAUDE.md`).

| | The change | From | Whose | Evidence | Stage |
|---|---|---|---|---|---|
| D-1 | **One way to erase: values carry, by type.** The box `Dynamic{X}` and the wrapper that `compiled_for(x)` returns, both members; the wrapper a member of every trait its object is in; a trait's default a generated forwarding method; in a method at such a trait the argument is the kept form | P1, the first addendum | the user: provisionally accepted ("So provisionally I would accept P1 with the addendum.") | to give: stage 1's gate | 1, 2, 4 |
| D-2 | **`Callable` is a contract at the box.** Every function is a member of every `Callable{A, S}`; the signature is checked where the function is boxed or enters, the result on return; subtyping reads no method table | P7 (c), the third addendum | the user: accepted ("Okay, accept the change.") | E-398 | 2, 3 |
| D-3 | **Bounded means fully typed at the box.** The definition-time check reads the instance compiled for `Dynamic{X}`; a member's check is its serving instances, kept and validated with the image | P2; replaces the synthesis' decision 4 | to confirm | E-397: 157 of 165 agree | 1, 2 |
| D-4 | **A required operation is an entry of the contract and no method at the set.** The box's forwarding is a method at `Dynamic{<:X}`; a default stays a method | P4 | to confirm | E-394: 201 ended, all through such methods; 0 at the box | 2, 3 |
| D-5 | **G2 is the deep class.** The bit on instances that rest on bindings alone; the claim, an image's keep rule, strict mode's walk and the counts read the deep class | P3's predicate; open issue 187 | to confirm | E-395: 0 of some 50,000 deep instances ended | 2, 3 |
| D-6 | **A call that only throws is a run-time site for code compiled by facts** | the second addendum | mine | E-395: 41 % to 61 % deep (the forks), 40 % to 63 % (upstream by facts) | 2, 3 |
| D-7 | **The code slot is retired** | P7 (e); the synthesis' decision 5 | to confirm | E-393; E-283: 8.5 % of an image build's test, 15 % more machine code | 2, 3 |
| D-8 | **Base's surface as the design's object, by the census's list:** each entry a patch to Base that stands without traits, or a boundary. The gate: the share of a port's facts instances that are deep G2 | the synthesis' decision 1; the second addendum | to confirm | E-395's culprits; E-368 | 5 |
| D-9 | **Owner-only functions:** a function whose methods only its owner may define; a call of it is a fact at any signature. By default: the functions of a module compiled by facts that are neither exported nor `public`. It reverses decision 3 of session 27 | P5 (b) | to confirm | E-396: 14.7 % of the forks' run-time sites, 21.7 % and 41.4 % in trait packages | 2, 3 |
| D-10 | **One statement of what is final,** from which a closed build's rules follow; one definition of fully typed with the setting as its parameter | P5 (a) | mine | reasoned; open issues 181 (b), 184 (a), GT-17 | 2 |
| D-11 | **A membership adds no type equality** inside an invariant parameter | P7 (b) | to confirm | E-400; needs a build | 2, 3 |
| D-12 | **A pirate is reported by default** when it ends deep-G2 code; refused in strict mode; silent by choice | P7 (d); open issue 177 (c) | to confirm | — | 2, 3 |
| D-13 | **A membership can be taken back,** so that Revise works on memberships | the synthesis' decision 6 | to confirm | open issue 180 (c) | 2, 3 |
| D-14 | **The prune list.** Keys to a page of optional extensions; `like`, `withfields` and forwarding with `by` as the library's conveniences; `@trait_module` with `facts`, `bounded`, `no_pirates` | P7 (e); the synthesis' decision 2, first part | to confirm | E-263: four of 148 memberships share a key | 2, 6 |
| D-15 | **The next demonstrators:** the ODE program without callbacks through a build; a reader from outside for `intro/`, on the reduced design. No new port | the synthesis' decision 7 | to confirm | — | 6 |

**Settled by D-1, with nothing left to decide:** the synthesis' decision 2 (the attribute's rules) and decision 3 (a build compiles for the type, a session once).

**Not taken now.**
- **P3's demand rule** (a facts copy of each callee that is not deep G2): too wide today (E-395). Looked at again after stage 5, by its gate's number.
- **P6** (an image's deep-G2 code validated by ownership): ended by its criterion (E-399). Looked at again when the deep class holds most of an image.
- **P7 (a)** (a witness in the box): optional; GT-7 stands with its cost.
- The cache across sessions (stopped, 2026-11-14), speed work (retired), new ports.

## 3. The stages

Sizes are relative: S a session's part, M a session, L several.

| Stage | What | Where | Size | Item |
|---|---|---|---|---|
| 0 | The baseline tagged; the plan's items opened | every repository | S | W-154 |
| 1 | D-1 and D-3 as a prototype, with two pieces of the ports | the library, no change to Julia | M | W-151 |
| 2 | The references of the iteration; what is not built as deviation rows | `writeup/` | M | W-154 |
| 3 | Julia and the library: the facts side, then the type system | `julia-unified`, `TraitWorld-unified` | L | W-155, W-153 |
| 4 | The ports brought to the head; then the attribute's machinery removed | the demonstrators, `julia-unified` | L | W-156 |
| 5 | Base's surface by the census | `julia-unified`, W-19's stack | M | W-157 |
| 6 | Daily use: a build, the teaching, the pruning | the demonstrators, `intro/` | M | W-158 |
| 7 | Freeze; a short round; the goals' standings; the iteration assessed | every repository | M | W-159 |
| 8 | Upstream: two proposals that stand apart | W-19's stack | — | W-19 |

### Stage 0: the baseline

- Every head of §1's table is tagged `prototype-2026-11`, and the tags are pushed (done 2026-11-15; NetworkDynamics' clone in `ndport/pkgs/` is tagged locally, its remote is upstream's). The round's numbers (E-374 to E-393) and the probes' (E-394 to E-400) are that state's.
- **Julia's work goes on in a new tree, `julia-next`** (branch `next` of the julia repository, from the tag). `julia-unified` stays at the baseline, built, so that a gate can run the baseline beside the head on the same day.
- The library and the demonstrators go on on their branches `unified`, in place. `TraitWorld-base` is the library at the tag, for a gate that needs the baseline library while the library changes.
- Each change to Julia is a self-contained commit, as the stack's are.

### Stage 1: one way to erase, in the library (W-151, parts 1 and 2)

**What.** No change to Julia. The names are bound, not reserved ([traits §7.6](../reference/traits.md#76-casts)), so a module can bind its own `compiled_for`.
- The wrapper type, and `compiled_for(x)` as a function that returns it. Its operations forward by its field, statically.
- `@trait` declares the wrapper's family as a member, as it declares `Dynamic{Z}`'s ([lowering §2](../reference/lowering.md#2-trait)).
- For a trait with `@default_dynamic`: a method at the trait is defined at the two kept forms, and one forwarder takes a plain member and boxes it.
- `convert` into storage typed `Dynamic{X}`; `unwrap` on both forms.
- The check (D-3): `check_definitions` as a reading of the method's instance at `Dynamic{X}`. Start from `experiments/unification/w152/p2/agree.jl`.

**The two pieces.**
- TraitDifferentialEquations' front end: `lib/ODECore/src/frontend.jl` 60 to 82 (`ODEProblem` with `keep(f)`, the fallback with `Erased(f)`), the callbacks at `core.jl` 548 to 575. The target is the review's snippet: `ODEProblem(lorenz!, …)` gives the box, `ODEProblem(compiled_for(lorenz!), …)` the wrapper, with no `keep`.
- NetworkDynamics' kernel: `ndport/pkgs/NetworkDynamics-unified/src/coreloop.jl` 147 to 155 (`compiled_for(batch.model)` at `_run_batch!`).
- The other casts in library code, for the count: `TraitTables-unified/src/TableCore.jl` 75, 90, 188, `TraitTables.jl` 52; `TraitCSV-unified/src/CSVCore.jl` 123; `forks-unified/Tables/src/ColumnCore.jl` 98 to 118.

**The gate.**
- E-310's row (a new model: what NetworkDynamics compiles again), E-314's, and E-374's calls (an operation at a known type, a method compiled once, `compiled_for`, an element of a `Vector{Shape}`): not worse than the baseline beyond the runs' spread.
- The two packages' suites pass.
- The annotations in library code (`keep`, casts, `Erased`, `@nospecialize` at a trait argument), counted before and after: fewer.
- The mistakes of E-397's control: found, and reported at the line that passes the value.
- What the `convert` method and the forwarders end at a late load of the library: `w152/p4/late.jl` again.

**What would change D-1.** A forwarder that cannot be generated for a form the ports use (a keyword method, a `where` variable bound by the plain member's type, two trait arguments); an ambiguity the forwarders create; a row of the gate that is lost with no fix in the library. Then: record the case in open issue 186, and put the choice to the user. D-1 is the one decision the user made provisionally.

### Stage 2: the references (W-154; W-151's part 3)

**What.** Each row of §2's table is written into its reference as the intended state. What is not built gets a deviation row. The deviation rows are then the build's list.

| Row | The references | What it retires or closes |
|---|---|---|
| D-1 | traits §3.5, §4.6, §7.4 to §7.10, §8, §13; compiler §6.3, §6.9, §7.6; lowering §2, §6, §7 | the five steps; `keep`, `Kept{X}` as a concept; the fallback by scope; GT-4, GT-6; open issues 159, 161, 162, 165, 184 (e), 185, 186 |
| D-2 | traits §9; compiler §7.4; lowering §9 | C-61, C-62, C-90; open issues 182, 184 (d) |
| D-3 | traits §5.10, §7.3, §11.2; compiler §6.7; lowering §11; facts §11.2 | C-40, C-41; GT-2, GT-12; open issues 115, 184 (b), (c) |
| D-4 | traits §4.1, §4.2; facts §9; compiler §4.1, §6.8, §7.2, §7.3; lowering §2 | `OperationError`; GT-11; open issues 150, 178 (a) |
| D-5, D-6, D-7 | facts §2.2, §5, §11.2, §12; compiler §1.3, §3.2, §3.3 | C-64 to C-69; open issue 187; GT-8 restated by the deep class |
| D-9, D-10 | facts §3, §13.3; compiler §1.2, §2.7, §7.6; traits §12.2, §14 | GT-17; open issues 99, 157 (for a package's own functions), 181 (b), 184 (a) |
| D-11 | compiler §4.5, §4.9; C-88 (e) | GT-18 |
| D-12, D-13 | traits §12.2; facts §10, §11.1; compiler §5.5, §5.6 | open issues 177 (c), 180 (c) |
| D-14 | traits §7.1 to §7.3, §13; compiler §6.1, §6.4 to §6.6, §10.3; lowering §6, §8; a page of optional extensions | open issue 147 |

**With it, in the same commits.**
- The decision log: D-1 and D-2 out of Pending, each row with the user's words; the others as confirmed or "mine".
- [Alternatives](../design/alternatives.md): what each row replaces, with the reason and the experiment.
- [The goals](../goals.md) §3: each tension's row, restated or closed. [The glossary](../glossary.md). `design.md` where it cites a changed rule.
- `intro/` waits for stage 6: its examples must run.

**The gate.** No reference states two rules for one thing: one way to erase, one home for a required operation, one predicate for G2, one statement of what is final. A grep for the retired terms finds them only in history.

### Stage 3: Julia and the library (W-155, W-153)

Each item is one commit with its gate script, and the suites after it (Julia's `subtype` and `core` tests, the library's, the forks' session digests of E-308).

**The facts side.**

| Item | The gate |
|---|---|
| D-5: the bit on binding-only instances; the deep class computed and read by the keep rule, strict mode's walk and the counting tool | `w152/p3/deep.jl`: the deep class without the tool's correction; the nine loads end 0 deep instances |
| D-6: the throw-only rule | the deep share, 41 % to about 61 % (the forks); `fully_typed` on the forks' two entries unchanged |
| D-7: the code slot removed | E-393's control again; an image build's test and TraitWorld's image size against E-283 |
| D-9: owner-only functions | `w152/p5/sites.jl`: the own owner-only sites to 0; TraitMakie's asserted barriers of open issue 157 removed, its suite passes; a method by another package is a pirate's, refused in strict mode |
| D-12: the pirate's report | one case in the library's suite: the report names the method, its definer and the code ended |

**The type system.**

| Item | The gate |
|---|---|
| D-4: inference reads a required operation's declared result from the contract; no method at the set; the split's fallback without it | `w152/p4/late.jl`: 201 to 0; E-381's late load again; the fifteen mistakes of E-385 still reported at their lines; a call outside the declared signature gives `MethodError` with the contract's hint |
| D-2: every function a member; the check at the box and at a wrapper's entry; the method-table reading removed from subtyping | `w152/p7c/census.jl`'s seven pairs written as one method each; E-371's control; E-372's sessions not slower |
| D-11: the equality test for an invariant parameter | `w152/p7b/case.jl`: `isa`, `<:` and dispatch agree, fresh and compiled before |
| D-13: a membership taken back | a membership edited under Revise in the library's suite; the edges end what rested on it |

**Not checked before the build,** and so the first things to look at: that the split and the table need no method at the set (D-4); that a wrapper's entry test of `hasmethod` folds (D-2).

### Stage 4: the ports follow (W-156)

- Every demonstrator on the head: D-1's forms in place of casts and `keep`; D-2's guards; D-4's operations. E-373's table of suites again.
- The count of annotations per port, against stage 1's baseline.
- The porting guideline: a specialization belongs at a subtrait or in an operation; a library erases by its trait's default; `unwrap` is the barrier.
- A port's case that the new rules block is an open issue with the case, the rule and a proposal. The port is not built around it.
- **Then** the attribute's machinery leaves Julia: `Core.attributed_call`, the bits, step 4's exception (C-55, C-56, L-56), the closed build's attribute rule. The gate: the suites, and E-387's program builds by what is written.

### Stage 5: Base's surface (W-157, with W-19)

- The list is E-395's culprits by method name: error paths that take a `Type`, `DomainError(::Any, ::Any)`, type joins at `Any`, the task code under a lock, `push!(::Vector{Any}, ::Any)`; then E-368's holes.
- Each entry: a patch to Base that stands without traits (into W-19's stack), or a boundary.
- **The gate:** the deep share of the forks' and of upstream's facts instances, counted by `deep.jl`. The registry row states the share at which P3's demand rule and P6 are looked at again.
- Open issue 179 becomes this gate.

### Stage 6: daily use (W-158)

- The ODE program without callbacks through a build (open issue 184's rest).
- D-14 in the library and the references.
- `intro/` on the reduced design: a fact, an owner, a trait, the box, the wrapper. Its examples run in `experiments/docs-examples/`.
- `operations(x)` at the REPL (W-150), if it is small then.
- The reader from outside: the user finds one; the plan prepares `intro/` and a short task list.

### Stage 7: freeze, and a short round (W-159)

- A freeze tag, as `round-2026-11-b` was.
- Only the rows a change claims to move, each against the baseline:
  - G-1: E-376 and E-392 (the nine loads, the work after them), E-391 (an edit).
  - G-2: E-374's calls; NetworkDynamics' workload.
  - G-4: E-381 (plain code, the late load), E-382 (strict mode at a load), an image's size and build time.
  - G-5: E-385's fifteen mistakes. G-6: E-383, E-384, E-387. G-7: the annotations per port; E-373.
- [The goals](../goals.md) §2 and §3 updated; [the evidence](../design/evidence.md) with the new rows.
- **The iteration assessed:** a dated addendum to the synthesis. Each tension: closed, smaller, or standing with its cost. Each decision of §2: what it gave and what it cost.

### Stage 8: upstream (W-19)

Two proposals that stand apart:
- the facts rule with ownership, which changes nothing in the type system and carries the round's strongest result alone (E-392);
- traits: sets, memberships, contracts, the box and the wrapper.

## 4. What each stage should move

| Axis | The weakest point today ([goals §2](../goals.md#2-where-each-axis-stands)) | Moved by |
|---|---|---|
| G-1 | a port's entry chain lost to unrelated loads (GT-8); the check at each edit (GT-12) | stages 3 (D-5, D-6) and 5; stage 1 (D-3) |
| G-2 | a cast call that is not inlined (GT-4, GT-6) | stages 1 and 4 |
| G-3 | no cache across sessions | not in this plan |
| G-4 | the library's late load (GT-11); strict mode at a load (GT-2); the slot's machine code | stage 3 (D-4, D-7); stage 1 (D-3) |
| G-5 | a port's run-time failures | stage 3 (D-12); stage 1's check names what a call reaches |
| G-6 | one demonstrator's program | stages 4 and 6 |
| G-7 | the annotations a port needs; six of the ports' questions | stages 1 and 4 |
| G-8 | untested; five steps for the attribute | stages 2 and 6 |

## 5. Risks

- **D-1 is provisional.** Stage 1 is its test, and it comes before any reference changes.
- **The forwarders add methods at sets.** They are at the package's own functions for the most part. Stage 1's gate counts what they end at a late load.
- **D-2 loses three things** the user accepted: dispatch by a function's signature, the check of a struct parameter's bound, a variable bound only by the function's methods. None is in use among the census's 20 methods; the last was not checked mechanically. Stage 3's gate does.
- **D-4's cost is a plainer error** for a call outside an operation's declared signature. E-385's set is the control.
- **D-9 changes who is a pirate.** A package that extends another's internal function is refused in strict mode. The count of such methods in the round's environment belongs in the registry row before the build.
- **Stage 3 is large.** Its two halves are independent, and each item has its own gate; the order inside a half is free.

## 6. How it is run

The user (2026-11-15): "Have Opus agents implement the plan". The main session directs; agents on Opus do the stages. This is the user's exception to "no subagents" for this plan (`CLAUDE.md`). An agent starts no agent of its own.

**One agent per piece of work that can stand alone.** Each gets the plan, its rows and its gate. It records as the main session would: the registry row before a run, the reference before the build, its own session note, the work queue's row.

**Who works where,** so that two agents never change one tree:

| Tree | Changed by |
|---|---|
| `julia-next` (branch `next`) | one agent at a time: the Julia work of stages 3 to 5 |
| `julia-unified`, `TraitWorld-base` | nobody: the baseline |
| `TraitWorld-unified` and the demonstrators' `-unified` trees, `ndport` | one agent at a time: stages 1, 3 (the library's part), 4, 6 |
| `experiments` | every agent, each in its own directory `unification/w<item>/`; a commit names its paths |
| the design repository | every agent in its own worktree `wt/design-w<item>` on a branch `iter-w<item>`; it merges `origin/w141-record` into its branch and pushes to `w141-record` |

**The first wave** (2026-11-15), three agents side by side:
- **W-151:** stage 1, in the library and the two ports' pieces, on the baseline Julia.
- **W-155, the facts side without the library:** D-5, D-6 and D-7. Their references first, then `julia-next`. Its gates load the library from `TraitWorld-base`.
- **W-154, the references that do not rest on D-1:** D-4, D-9 to D-13. No code. D-14 goes with D-1's references: it changes the same chapter.

**After it,** in order: the references for D-1, D-2, D-3 and D-14 (when W-151's gate is in); the rest of stage 3 (D-9 and D-12 with the library, then the type system: D-4, D-2, D-11, D-13); stages 4 to 7.

**The second wave** (2026-11-15). W-151's gate is in: every row at parity or better but one, a plain member boxed at each call (GT-19; E-402, E-407). The user: "Yes please. Build the compiler for P1 and be cogniszent of finding principled ways of making the design fast." So D-1 stands.
- **W-154, continued:** the references for D-1, D-2, D-3 and D-14.
- **W-160, the compiler for one way to erase,** in `julia-next` after W-155's agent, with the library: a positive membership decided at `new`'s field test and at `isa` with an edge (GT-19's fix); the forwarders made where a method is defined, in place of the prototype's macro; the check's instance at the box kept with its edges (D-3); and, on the way, the principled ways of making the design fast that it finds (`CLAUDE.md`).

**The third wave** (2026-11-15). W-155's agent is done: D-5 and D-7 built on `next` (9b6dacf5c5), the library's part merged (TraitWorld `unified` bb4ad00); D-6 not built (open issue 194, GT-21). Two builders side by side, each with a Julia tree and a library tree of its own:
- **W-160** in `julia-next` (branch `next`) with `TraitWorld-unified`, `TraitDifferentialEquations-unified` and NetworkDynamics.
- **W-155, continued: D-9, D-11, D-12, D-13** in `julia-s3` (branch `next-s3`, from `next`) with `TraitWorld-s3` (branch `s3`, from `unified`). Open issue 195 (a) if it is little code.
- **Then,** in `julia-next` after both are merged: D-4 and D-2 (they change `@trait` and the box, which W-160 changes), and stage 4.

**The fourth wave** (2026-11-15). Stage 2 is done (W-154). D-9, D-11, D-12 and D-13 are built on `next-s3` with TraitWorld `s3` (W-155's second agent); W-160's agent is still in `julia-next`.
- **W-157, stage 5,** in `julia-s3` (branch `next-s3`, continued) with `TraitWorld-s3`: Base's surface by the census, with open issue 194's throwing helpers and open issue 195 (a). It needs nothing of W-160's.
- **Then one merge:** `next-s3` into `next`, TraitWorld `s3` into `unified`. To watch: W-160's edges for a positive membership need open issue 211's rule in the G2 predicate; the ODE port needs open issue 212's `public` line.
- **After the merge,** in `julia-next`: D-4 and D-2, then stage 4.

**IDs are given out in ranges,** so that agents side by side take none twice. A range's unused numbers stay unused.

| Agent | Experiments | Open issues | Deviations | Tensions |
|---|---|---|---|---|
| W-151 | E-401 to E-415 | 189 to 193 | T-113 to T-119, L-59 to L-62 | GT-19, GT-20 |
| W-155 (facts side) | E-416 to E-430 | 194 to 198 | C-91 to C-99, F-25 to F-29 | GT-21, GT-22 |
| W-154 (references) | E-431 to E-435 | 199 to 203 | T-120 to T-129, C-100 to C-109, F-30 to F-34, L-63 to L-66 | GT-23, GT-24 |
| W-154, continued (D-1, D-2, D-3, D-14) | E-432 to E-435 | 199 to 203 | T-125 to T-145, C-110 to C-119, F-30 to F-34, L-65 to L-75 | GT-24 |
| W-160 (the compiler for D-1) | E-436 to E-455 | 204 to 210 | C-120 to C-129, T-146 to T-149, L-76 to L-79 | GT-25, GT-26 |
| W-155, continued (D-9, D-11, D-12, D-13) | E-456 to E-475 | 211 to 217 | C-130 to C-139, T-150 to T-155, F-35 to F-39, L-80 to L-83 | GT-27, GT-28 |
| W-157 (Base's surface) | E-476 to E-495 | 218 to 224 | C-140 to C-145, F-40 to F-42 | GT-29, GT-30 |

**The machine.** Three agents at 4 cores each is within the rule for sustained use (16 cores in all). A build of `julia-next` goes through `tools-local/build.sh`, which keeps the rule for a spike. Above half load: one Julia job at a time, and the main session stops agents down to one.
