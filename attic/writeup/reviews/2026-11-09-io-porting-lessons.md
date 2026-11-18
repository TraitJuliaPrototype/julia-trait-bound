# Review: the porting lessons of the `IO` episode (2026-11-09)

The user (2026-11-09): "Send another agent out to document the porting lessons from this."

Written by a Fable agent sent out at the user's explicit request (the standing rule against subagents on the shared host set aside by the user's words). Nothing was run; nothing was committed. Three files changed: [`intro/porting.md`](../intro/porting.md) (the lessons for porters, current state only), this review, and the row in [`record/INDEX.md`](../record/INDEX.md). The targets proposed below were not edited.

**What was read:** [CLAUDE.md](../../CLAUDE.md); [the Fable plan on alternatives to `IO` as a set](../plans/2026-11-09-io-alternatives.md) and [the plan on equations and the firewall](../plans/2026-11-09-compiled-once-equations.md); [open issues](../open-issues.md) 164 (closed), 166, 167, 168, 169 (closed) and §1; [the day's session note](../../session-notes/2026-11-09-day-io-trait.md); [experiments](../record/experiments.md) E-318, E-323, E-326, E-328 to E-336 and [the evidence](../design/evidence.md) §2–§3; [traits §3.4, §7.5, §7.7, §7.9, §7.10, §9b](../reference/traits.md) and [compiler §7.5](../reference/compiler.md#75-io) as rewritten for option B (uncommitted); [facts §13.1](../reference/facts.md#131-the-product-setting); [alternatives](../design/alternatives.md), "Open issue 164 and finality"; the forks' branch `e323` (`forks-unified`, `unified..e323`: 10 lines in DataFrames); `experiments/unification/e328/erase_io.jl` and its README; `experiments/unification/audit/README.md`; `julia-vanilla/base/show.jl:309-341` (`IOContext`'s constructors).

## Summary

- **The episode.** One package's display compiled per stream type at a REPL (E-318). A port-side eraser at its display entry fixed it in ten lines, 0.081 s against 0.175 s (E-323), and was set aside as a step around the design. The design was changed instead: `Core.IO` an open set compiled once by default, Base's own streams included (164 (d), W-129 (b)). The build was correct and far slower (E-330: per call 2–24× vanilla, the sessions 3–5×). Repairing it took the rest of the day and found six general faults (E-331 to E-336), each with an audit tool. A Fable plan then recommended option B, which the user took: `IO` stays Julia's closed abstract type with a contract; Base's `IOContext{IO}` is the eraser; erasing is the author's choice, at a display entry. B is Planned.
- **The one lesson under the others:** the design's own rule already placed erasure at the entry where large code serves many value types ([traits §7.10](../reference/traits.md#710-costs-and-choosing)), and the port-side fix followed that rule. The day was spent applying erasure at the other end, the kernels, and then restoring the kernels one exception at a time.
- **Fourteen lessons** below, in three groups: the design (L1–L5), the ports (L6–L9), the way of working (L10–L14). Each says what is done and where the rest should go. Proposed texts for documents outside this review's three files are in §5.

## 1. The episode, in order

| Step | What happened | Where |
|---|---|---|
| 1 | The forks' `show` step at a REPL compiles DataFrames' keyword body and PrettyTables' code at `IOContext{REPL.LimitIO{TTYTerminal}}`, 0.12 s of 0.18 s; the image's workload displayed at an `IOBuffer`. | E-318; open issue 164 |
| 2 | The port-side eraser: `@nospecialize(io::IO)` at DataFrames' two display entries, the stream passed on as `IOContext{IO}`, one workload line. The step 0.081 s against 0.175 s; the display's run time within 10 %; the digests equal; the suite as before. "Not adopted in the forks' `unified`: the eraser is a step around the design's gap." | E-323; forks `e323` 5c43492 |
| 3 | The user: "The real point here is that Base should support and default to Dynamic{IO} right?" Read as: every method typed `io::IO`, Base's included, compiled once. Then "Finality should be opt in. Everything else is approved." | session note §4–§5; decisions §9 |
| 4 | A proxy on vanilla predicts the split's cost: formatted output 0.85–1.19×, a byte or a short string per call 1.6–2.2×. | E-328 |
| 5 | Built: traits closed after load (W-129 (a), E-329; the sessions 2–3× slower at load 26–30, resolved only by running the control, which was slowed by the same factor), then `IO` as a set (W-129 (b)). | E-329, E-330 |
| 6 | E-330: correct, and the goal's task 15.8–16.1 s against the control's 4.1–4.3 s; the `show` step 2.0 s against 0.19 s; per call 2–24× vanilla. Two reports find the causes. | E-330; audit README |
| 7 | Six fixes, each general: the lookup at an unmet intersection (E-331), the firewall at a split's branches (E-332), the conversion of a member's result (E-333), the final negative at an unmet intersection (E-334), the typemap's listing at the set's position (E-335), backedges that keep the call's signature (E-336). Ten `@specialize` annotations in Base. The goal's task 3.46–3.63 s against the control's 2.49–2.56 s at the same load. | E-331 to E-336; evidence §3 |
| 8 | The user: "Ask Fable if another approach to IO rather than turning it into a trait would be more sensible/principled." The plan recommends B. The user: "Go with the Fable plans recommendations." | the plan; open issue 164 closed |

## 2. Lessons about the design

### L1. Erasure belongs at the boundary where large code serves many value types, not at the kernels

- *Evidence.* [Traits §7.10](../reference/traits.md#710-costs-and-choosing): "`Dynamic` suits large code with many members behind it … `Compiled` suits kernels." 164's case was one missing instance of large code (a display path) in one image. The decision erased at Base's kernels (`write` of a byte, `print` of a short string) and paid per call everywhere (E-330, E-333), then restored the kernels one `@specialize` at a time: ten in Base, the list open-ended (the plan §2.2). The port-side fix (E-323) erased at the display entry and cost 0.92–1.0× on the display (E-328's `split`, E-323's run time).
- *Done.* Option B: [traits §9b](../reference/traits.md#9b-streams-io) "Erasing is the author's choice, where large code serves many streams (§7.10)"; the porting guide's 0.4 and rule A10.
- *Proposed.* Nothing beyond B in the references. One sentence for CLAUDE.md's "Flag a design decision that makes speed hard" (§5.1): a default that erases a library's own abstract type is such a decision, flagged before it is built.

### L2. A plain abstract type's eraser is the type's own wrapper; a hand-written box leaks

- *Evidence.* `Dynamic{IO}` forwarded twelve operations; `displaysize(io::IO)` reads `ENV` where `displaysize(io::TTY)` asks the terminal, and `mark(io::IO)` reads a field, so `show(Dynamic{IO}(stdout), x)` with `:limit` sized its output wrongly and `mark` failed (the plan §2.4, verified in Base). Gate `n19_io_trait` tested an `IOContext`'s property through the box, not these. Base's `IOContext` is an `AbstractPipe` and forwards the whole interface.
- *Done.* B names `IOContext{IO}` as the eraser (traits §9b, compiler §7.5); the porting guide's 0.4 and rule A11 say "never a box of the port's".
- *Proposed.* Gate cases, when B is built (§5.2): `displaysize(IOContext{IO}(stdout)) == displaysize(stdout)`; `mark`, `ismarked`, `reset` through the eraser on an `IOBuffer`; `get(IOContext{IO}(IOContext(io, :compact => true)), :compact, false)`. The pattern is general: any eraser the design offers for a plain abstract type is tested against the type's whole interface, not the contract's operations alone.

### L3. A contract on a closed abstract type is a category of its own, and it reaches beyond `IO`

- *Evidence.* B's rule 1: a closed abstract type may declare operations with declared results and the split's candidates, with no cell, guard or finality, since nothing joins later ([traits §3.4](../reference/traits.md#34-open-and-closed)). The plan (§4.2, "Against B") names `AbstractArray` and `AbstractString` as the natural next cases: values in a `Vector{AbstractArray}` would gain typed results and the split.
- *Done.* Traits §3.4 states the rule; `IO` is its first case (W-129 (c)).
- *Proposed.* An open issue (§5.3): which of Base's closed abstract types declare contracts, by what evidence, and who owns the declaration (Base, or BaseTraits for the library's needs). Decided case by case, by a measured port need, as `IO`'s was.

### L4. A decision that touches Base checks the guarantees before it is built

- *Evidence.* [Facts §13.1](../reference/facts.md#131-the-product-setting): "Plain code keeps all of Julia's behaviour: its inference, its speed, its invalidation." Under the decision, plain code that knew its stream ran 1.2–3.4× slower (E-333) and was invalidated through an instance shared with every stream (E-336's chain). Nothing exempted `IO`, and the contradiction was found by the plan (§2.3), after the build.
- *Done.* B restores §13.1 as written (the decision row, uncommitted, cites it).
- *Proposed.* A line in CLAUDE.md's table row "A decision" (§5.4): the decision row names the guarantees of facts §2 and §13 it touches, or says none.

### L5. Equations type the results; only a rule about edges stops the fan-in

- *Evidence.* The equations plan (§3): the first-order form (`read(io, ::Type{T})::T`) is already in the design and the code; it types the value after the call but removes no edge, since the split's call info adds none and the fan-in's edges are the inliner's. The firewall (proposal 1) is the rule about edges; E-332 built its mechanism. Open issue 167 keeps the holes (a split with no table; a constant-folded branch).
- *Done.* Open issue 167 records the rule and the holes; compiler §7.5 says the split at `IO` includes the firewall.
- *Proposed.* Nothing new; 167's recommendation stands. For a porter the lesson is in the guide's 0.4: a declared result is for the code after the call, and an erased entry's cost is the split's, not inference's.

## 3. Lessons about the ports

### L6. A port's change that follows a rule of the references is the port following the design, not a workaround

- *Evidence.* E-323's row: "Not adopted in the forks' `unified`: the eraser is a step around the design's gap (open issue 164)." The ten lines applied §7.10's rule at the author's entry, which B now states as the idiom. CLAUDE.md's "Do not design a port around such a point" was read as forbidding it. The reading cost a day and a Base-wide change. The distinction that was missing: a workaround bypasses a rule; this change applied one.
- *Done.* The forks' branch `e323` is the measured form; B's idiom is its few lines with `_erased_stream` replaced by Base's `IOContext{IO}(io)`.
- *Proposed.* CLAUDE.md, under "Principled solutions; the ports find the design's weak points" (§5.5): the distinction, and the order of work: a port-side change that follows a rule is measured and merged first; a design change for the same case is weighed against it on the same build at the same load.

### L7. The workload runs each erased entry once, by the path the REPL takes

- *Evidence.* `e323` added `show(IOBuffer(), MIME"text/plain"(), df)` to DataFrames' workload: the REPL displays through the MIME entry, and the existing `show(IOBuffer(), df)` did not reach it. Under B-display (the plan §4.3) every package's workload would need the same line; today's workloads display at an `IOBuffer` without a MIME.
- *Done.* The porting guide's 0.4 ("The workload displays at the erased type, by the path the REPL takes") and B1 item 8.
- *Proposed.* When `e323` is rebased onto B and merged: its workload line stays; TraitReport's and TraitMakie's workloads get the same line where they erase (§5.6, with L8).

### L8. Under B each port decides where it erases; most erase nowhere

- *Evidence.* The plan §4.2, "The ports": DataFrames' fork erases at its display entries (`e323`); TraitReport's `report(input, output; io::IO = stdout)` (`TraitReport-unified/src/TraitReport.jl:16`) erases at its entry where it wants an image's coverage, else stays per type; CSV's reader keeps vanilla's instances at `IOStream`; Makie's `show(io, ::MIME"image/png", fig)` does bulk writes and changes nothing. A plain package that never erases keeps vanilla's behaviour.
- *Done.* The porting guide's 0.4 states the choice and its costs.
- *Proposed.* W-129 (c) lists the ports' lines (§5.6): DataFrames (`e323` rebased), TraitReport (decide by one traced run of form (t): what its `report` step compiles at the REPL's stream), CSV and Makie (nothing). Each port's README records what it erased and the measured step.

### L9. An erasure fixes the port's share; the rest of a step belongs to other levers

- *Evidence.* After `e323`, the `show` step's remaining 0.08 s is the REPL's own display path at its stream (about 30 ms) and Base's code at the cells' types reached by dynamic calls (about 50 ms): the flagged item "Base's code is compiled plainly" (open issues §1), not the port's. E-318 found the step "mostly upstream's" before the erasure too.
- *Done.* The porting guide's 0.4 ("What the erasure fixes, and what it leaves") and 0.6.
- *Proposed.* Nothing new; the flagged item has its proposals.

## 4. Lessons about the way of working

### L10. On the shared host, a session's number without a control at its load compares with nothing

- *Evidence.* E-329 at load 26–30: the sessions 2–3× E-326's; the unchanged build's form (f), run at the same load, was slowed by the same factor, so the 5 % criterion was "not resolved". E-330 ran the control (4.08–4.28 s) and the 3.8× was real. E-331 to E-335 measured the goal's task without a control at their loads; the plan (§2.1) had to infer "about 2× the build before `IO` was a set" from the loads alone. E-336 ran the control just after (2.49–2.56 s against 3.46–3.63 s), and the comparison stood.
- *Done.* The session runner (`experiments/unification/e289/`) runs form (f) on the early build as the control; the porting guide's 0.6 states the rule for a port's measurement.
- *Proposed.* CLAUDE.md, rule 5 of "Rules across documents" (§5.7): a session number compared across builds is run beside its control, interleaved, at the same load; a row without one says "no control".

### L11. The step a change was made for is measured on every build that carries the change

- *Evidence.* 164's case is the forks' `show` step. It was measured on E-330's build (2.0 s against 0.19 s) and on no later build: E-332 to E-336 measured the goal's task only. So the benefit the decision was taken for was never verified on the build that carried it (the plan §2.1), and the decision's reversal rests on cost alone.
- *Done.* The parent's `state.md` names E-337 as the measurement of B. The porting guide's 0.6 states the rule for a port.
- *Proposed.* E-337's row (§5.8) measures the forks' session with its `show` step, a warm-up and 3 runs, the control interleaved, on B's build with `e323` rebased; and CLAUDE.md's "No excessive benchmarking" gains the clause "and the step the change was made for".

### L12. A proxy's number is a lower bound; a Base-wide decision waits for the build

- *Evidence.* E-328's proxy on vanilla predicted the split at 0.85–2.2×; the build gave 2–24× (E-330). The proxy modelled the split's branches and the asserted result, not dispatch's lookup flagging an ambiguity at `All{AbstractString, IO}` (E-331), the inliner's edges through a branch (E-332), or Base's wrappers built abstract in code compiled once (166 (d)). The registered threshold was right in shape ("several times slower: not recommended before the split's direct calls are measured") and the decision was taken before the build measured it.
- *Done.* E-328's README says what each way models; E-330's row records the gap.
- *Proposed.* A convention for experiment rows (§5.9): a proxy's row names what of the build it does not model, and a decision that rests on a proxy's "small" is marked provisional until the build's own number is in the row.

### L13. The user's words with two readings: record both, build the cheaper, list the other

- *Evidence.* "Base should support and default to Dynamic{IO}" (the plan §1): *support* (an erased stream is an `IO`, so plain code takes it) or *default to* (every method typed `io::IO` compiled once). The session took the second, the costlier by a day's work; the user's later question ("another approach to IO rather than turning it into a trait") shows the first was in reach. "Everything else is approved" was read as approving the reading too.
- *Done.* The decision log's superseded rows quote the words; the plan records both readings.
- *Proposed.* CLAUDE.md, under "Gates do not stop the work" (§5.10): where the user's words admit two readings whose costs differ by much, the decision row quotes both, the agent builds the one the design's own rules favour, and lists the other in open issues §1 for the user to confirm.

### L14. A failure names a pattern: the tools are the lasting yield of the day

- *Evidence.* Eight reports in `experiments/unification/audit/` (the erasure report, the load report, the declared-result report, the unmet-instance report, the typemap report, the set-root report, the chain report, the load profile), each built at a failure and each counting every instance of its pattern; six general rules found by them (E-331 to E-336), which `Callable`, Base's other set, would have met later. Three build failures named implementation patterns (session note §9): compiler code must not read a Base binding in its own world; a `:caller_world` target must exist in every world a caller can run in; a runtime change must rebuild the system image (`tools-local/build.sh` now does). Making `IO` a set exercised the machinery at Base scale: a thousand of Base's methods at a set, Base's own image, Base's test suite.
- *Done.* The audit README with its dated tables; CLAUDE.md's rule "A failure names a pattern"; the rules in the references with their gates (n19, n20, n21).
- *Proposed.* Under B, `IO` is not a set, and gate n19's set cases (a late `@implement IO S`; a thousand methods at one set in the system image; `All{AbstractString, IO}`) lose their subject. A test set at Base scale (§5.11): a gate or a battery stage that declares a set over many of Base's methods (a set with four candidates and a hundred members, built in the test's own module, or `IO` as a set on a branch kept for the battery), so that E-331, E-334, E-335 and E-336 stay exercised where they were found.

## 5. Proposed texts for documents outside this review's files

Each is a proposal; the owner of the document decides. None was edited.

### 5.1 CLAUDE.md, "Flag a design decision that makes speed hard"

> A default that erases a library's own abstract type (every method typed by it compiled once) is such a decision: it costs every call of plain code that knows the value's type. Flag it before it is built, with the port-side erasure at an entry measured as the alternative.

### 5.2 Gate `n19_io_trait` (or its successor under B), new cases

> `displaysize(IOContext{IO}(stdout)) == displaysize(stdout)`; `mark`, `ismarked` and `reset` through `IOContext{IO}(IOBuffer())`; `get(IOContext{IO}(IOContext(IOBuffer(), :compact => true)), :compact, false) === true`; `IOContext{IO}(io)` of an `IOContext` holds the inner stream, not the context.

### 5.3 Open issues §2, a new item

> **Which of Base's closed abstract types declare a contract** (traits §3.4; found by the `IO` episode, [the plan](../plans/2026-11-09-io-alternatives.md) §4.2). `IO` declares one for its display paths. `AbstractArray` and `AbstractString` are the next candidates: values in a `Vector{AbstractArray}` would gain typed results and the split. *Proposal:* one at a time, each by a measured port need (a traced step that compiles per element type at a container typed by the abstract type), declared in Base beside `iotrait.jl`, with the declared-result report run before the declaration.

### 5.4 CLAUDE.md, the table row "A decision"

> The log row also names the guarantees of facts §2 and §13 the decision touches, or says "guarantees: none".

### 5.5 CLAUDE.md, "Principled solutions; the ports find the design's weak points"

> A change in a port that applies a rule of the references (an erasure at a display entry, by traits §7.10 and §9b) is the port following the design, not a workaround; a workaround bypasses a rule. Where a port-side change and a design change answer the same case, the port-side change is measured and merged first, and the design change is weighed against it on the same build at the same load.

### 5.6 W-129 (c), the ports' lines

> DataFrames: the forks' branch `e323` rebased, `_erased_stream` replaced by `IOContext{IO}(io)`, its workload line kept. TraitReport: one traced run of form (t) decides whether `report`'s step compiles at the REPL's stream; if so, `@nospecialize(io::IO)` and `IOContext{IO}(io)` at its entry, and a workload line through it. CSV and TraitMakie: nothing. Each port's README records what it erased and the measured step.

### 5.7 CLAUDE.md, rule 5 of "Rules across documents"

> On the shared host, a session's number compared across builds is run beside its control (the unchanged build's form of the same session), interleaved, at the same load. A row without a control says "no control at this load" and draws no comparison.

### 5.8 E-337's row

> The forks' session with its `show` step (a warm-up and 3 runs, the control interleaved) on B's build with `e323` rebased, beside the goal's task; E-328's `raw` workloads against vanilla at the same load, which under B should be 1.0×.

### 5.9 `record/experiments.md`, the conventions at its head

> A proxy's row names what of the build it does not model. A decision that rests on a proxy's small cost is marked provisional in the decision log until the build's own number is in the row.

### 5.10 CLAUDE.md, "Gates do not stop the work"

> Where the user's words admit two readings whose costs differ by much, the decision row quotes both. The agent builds the one the design's own rules favour, and lists the other in open issues §1 for the user to confirm.

### 5.11 `record/todo.md`, a new item

> **A test set at Base scale.** Under B no set of Base's has a thousand methods, so E-331, E-334, E-335 and E-336 lose the case that found them. A gate (or a battery stage) declares a set with four candidates and about a hundred members over many of Base's methods, in the test's own module, and runs the lookup's, the final negative's, the typemap's and the backedge's cases there. Alternatively, `IO` as a set on a branch kept for the battery.

## 6. What was verified, and what was not

- *Verified by reading:* every ID and number above against its row in the registry, the evidence or the open issue; the `e323` diff (10 lines: two `@nospecialize` entries, `_erased_stream`, one workload line); `IOContext{IO_t}(io::IO)` exists in vanilla (`show.jl:341`) and wraps an `IOContext` whole, which is why `e323` unwraps it; the plan's reading of `displaysize` and `mark` in Base (`stream.jl:563-574`, `io.jl:1427,1467`, as the plan cites them; not re-read here).
- *Not verified (no run):* the 30 ms and 50 ms shares of the `show` step after `e323` are E-323's attribution from one traced session; B's cost on the display path is E-328's `split` proxy, not B's build; TraitReport's step at the REPL's stream has not been traced.
