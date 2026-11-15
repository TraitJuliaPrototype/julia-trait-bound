# The next iteration: one plan from the synthesis and the review

**Status:** proposal (2026-11-15), for the user. Written in the main session, with no subagent. Not normative: nothing here is in force until it is decided and written into a reference.

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

**The first action.** If the user has adopted the plan (its status line says so): stage 0. If not: nothing is built; §2's table waits for the user's word.

## 2. What is decided, and what the plan takes

Adopting the plan takes every row marked *to confirm* as recommended, unless the user names an exception. Rows marked *mine* are choices of the agent: they stand as recorded and are input to the next synthesis (`CLAUDE.md`).

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

- Tag every head of §1's table `prototype-2026-11`, and push the tags. The round's numbers (E-374 to E-393) and the probes' (E-394 to E-400) are that state's.
- Work goes on on the same branches. Each change to Julia is a self-contained commit, as the stack's are.

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
