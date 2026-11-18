# W-162, the harvest: what was done with the findings of the reviews of 2026-11-07 to 2026-11-10

Produced by an agent on 2026-11-18, for the main session's check. Read only: nothing else was changed, no Julia was run.

Method:
- Each review was read in full. For a plan review, the reviewed plan's own closing section ("After the review") was read first and its claims checked against the record.
- The current record was searched for the review's file name, the IDs a finding names (C-, T-, L-, W-, E-, PE-, GT-, open issues) and its key terms: the four references and their Deviations tables, `open-issues.md`, `record/decisions.md`, `record/todo.md`, `record/experiments.md`, `record/performance-explorations.md`, `design/julia-changes.md`, `design/alternatives.md`, `design/evidence.md`, `state.md`, `record/INDEX.md`.
- Where the documents left doubt, the code was read: TraitWorld branch `unified` (by `git show`/`git grep`; the `TraitWorld` worktree itself is on `main`, the old library), `julia-next`, the ports' `-unified` worktrees, `experiments/unification/`. "Done (spot check)" means a look at the current text or code, not a full re-verification.

Classes: **done**, **open, recorded**, **superseded**, **declined, recorded**, **not found**. "Done, in part" counts as done; its remainder without a record is listed in §3.

## 1. `2026-11-07-basetraits-choices.md`

| Finding | Severity | In one line | Disposition | Where |
|---|---|---|---|---|
| H1 | High | `BoundedText` per value undoes the per-type constants; bound unsound for non-UTF-8 strings; `textbound(T)` | done | traits §10.1 (table, bullet on `BoundedText`); TraitWorld `unified` `src/BaseTraits.jl` (`textbound(::Type)`, `Period`, `CompoundPeriod`); alternatives (BaseTraits choices) |
| H2 | High | `solve!` collides with the SciML port; `ldiv!` is the operation; `Factorization` over-promises | done | traits §10.1 (`Solvable` by `ldiv!`, the solving factorizations listed); decisions §9 row "`Solvable`'s operation is `ldiv!`"; alternatives |
| H3 | High | the test's matrix-free member defines no `eltype` | done | `test/basetraits.jl:26`; traits §10.1 "A matrix-free member defines `eltype`" |
| H4 | High | methods at sets on Base's hot functions unmeasured (PE-21's trigger) | done | E-282 (Base's `arrayops`, `dict`: no cost above noise); evidence §4c; traits §10.1 status |
| M1 | Medium | the eight choices not in the decision log; deferrals not open issues; `HasProperty` | done | decisions §9 rows (collection contracts, `Solvable`, `LinearOp`); open issues 151–155; `HasProperty` built (traits §10.1 status) |
| M2 | Medium | `get(d, k, default::V)` invites sentinels | done | traits §10.1 `get(...)::Union{V, D} where {D}`; alternatives |
| M3 | Medium | `MutableIndexable`'s members: views, `BitVector`, partitions | done, in part | `BitVector` and `SubArray{T,1,P} where P <: MutableIndexable{T}` in traits §10.1 and the code, tested (`test/basetraits.jl:48–55`). `ReshapedArray`, `MVector`, `ArrayPartition`: not added, no record (§3) |
| M4 | Medium | `IndexableVector` propagates `@inbounds`; no `IndexLinear`; `keep` twice | done (spot check) | `src/BaseTraits.jl` on `unified`: no `@propagate_inbounds` on `getindex`, `IndexLinear()`, one `keep` |
| M5 | Medium | `Solvable`'s contract overclaims offset and device vectors | done | traits §10.1 bullet "A contract states what a membership's check cannot verify" |
| M6 | Medium | `Resizable` shrinking only; `push!` needed | done | traits §10.1 (`push!` in `Resizable{T}`); alternatives |
| M7 | Medium | members missing: sets, strings, tuples; `IterableOnce` | done, in part | `AbstractSet`, `AbstractString` (items `Char`, not `HasLength`) in §10.1; `IterableOnce` is open issue 155. `NTuple` in `Iterable`/`Indexable`: not added, no record (§3) |
| M8 | Medium | choice 2 answers open issue 110; a test of a trait as member of a parametric trait | open, recorded | open issue 110 ("now answerable", to take when the DataFrames port is rebuilt, W-104) |
| L1 | Low | `Iterable`'s `Any` state boxes per step | open, recorded | open issue 156 |
| L2 | Low | `mul!` declared `::Any` | done | `apply!(...)::AbstractVector{T}` (traits §10.1) |
| L3 | Low | names: `LinearOperator`, `HasLength` vs `Base.HasLength` | done | `LinearOp`; §10.1 "`HasLength` is not `Base.HasLength`" |
| L4 | Low | specificity of set methods against Base's | done | the tests pass; E-282 |
| L5 | Low | `retain!` at an intersection untested | done (spot check) | `test/basetraits.jl:69–71` |
| L6 | Low | "per function", result types in the table, "constant time", mixed precision | done, in part | "expected in constant time" in §10.1; mixed precision open issue 152; §10.3 rewritten. The table still gives `setindex!`, `push!`, `resize!` no result type (§3) |

## 2. `2026-11-07-implementation-day.md`

| Finding | Severity | In one line | Disposition | Where |
|---|---|---|---|---|
| H1 | High | the code slot's miss raises where Julia runs | superseded | the code slot retired (decisions row "The code slot is retired", the plan's D-7); C-64–C-69, C-93 retired; compiler §3.3. Earlier fixed: julia-changes row 52 |
| H2 | High | revalidation re-enters inference without cycle detection | superseded | as H1; earlier fixed: julia-changes row 50 |
| M1 | Medium | `JULIA_CODE_SLOT=0` no safety valve | superseded | as H1 |
| M2 | Medium | inlined callees excluded by debug-info edges | superseded | as H1 |
| M3 | Medium | revalidation's commit does not re-check callees | superseded | as H1; earlier fixed: julia-changes row 50 |
| M4 | Medium | `state.md` and the Deviations header a stage behind | done | W-122 (done); compiler's Deviations header current |
| M5 | Medium | slice 1 of the ports without a committed log or dated README rows | done, in part | the suites' logs and dated rows in `experiments/unification/w104/` (E-373). Ports' READMEs and `check.sh`: §3 |
| M6 | Medium | the crash fix uncommitted, without log, gate or row | done, in part | julia-changes rows 48 (67ba8105fb) and 49 (fb0c7ba75a) state the causes. No crash log, no gate case (§3) |
| M7 | Medium | fully typed mode's check missing for a plain caller that inlines | open, recorded | traits T-104 |
| L1 | Low | slot counters not atomic | superseded | slot retired (D-7); earlier fixed in f90d152208 |
| L2 | Low | the record matched by struct name | superseded | as L1 |
| L3 | Low | an image write drops a marked caller | superseded | slot retired (D-7) |
| L4 | Low | the copy for `mi2 != mi` carries no record | superseded | slot retired (D-7) |
| L5 | Low | `method_in_interferences` verified safe | done (nothing asked) | — |
| L6 | Low | W-121's numbers without an experiment | superseded | W-121 retired (speed work retired, 2026-11-11) |
| L7 | Low | core dumps in the workspace | done (spot check) | none at the root, in `TraitWorld-unified`, in `forks-unified` |
| L8 | Low | E-283's wording | superseded | E-283 is the slot's; slot retired |

## 3. `2026-11-07-machine-code-cache-design.md`

All of it concerns the cache across sessions toward the speed goal. The user stopped the cache on 2026-11-14 (W-120 stopped; open issues, closed item "the cache across sessions is not built now"; judged from W-145) and retired speed work on 2026-11-10/11 (decisions §5).

| Finding | Severity | In one line | Disposition | Where |
|---|---|---|---|---|
| H1 | High | a perfect cache leaves 5.5–6× pandas | superseded | speed claim retired (decisions §5); cache stopped (W-120) |
| H2 | High | admit code of either policy by the G2 bit | superseded | cache stopped (W-120; open issues closed item of 2026-11-14) |
| H3 | High | step 3 is the environment-keyed cache | superseded | as H2 |
| H4 | High | C-52 first and SciML first contradict the goal | superseded | as H2; the ports done (W-104 phase 4, E-373); C-52 stays an open row for the cache |
| H5 | High | the load is the largest term; C-40; validation by G2 | superseded | speed retired; C-40 retired (2026-11-15, the check reads the instance at the box; C-115) |
| M1 | Medium | the record lacks embedded values, flags, the build | superseded | cache paused (compiler §9, C-52). Note in §3: compiler §9's list and facts §12 still disagree on embedded values |
| M2 | Medium | keep the code slot; rerun its cost; fix C-65 | superseded | slot retired (D-7); C-65 retired |
| M3 | Medium | a goal gate `goal.jl`/`goal.py` | superseded | speed gates dropped (2026-11-09) and speed retired |
| M4 | Medium | step 4 is a new linker | superseded | cache stopped |
| M5 | Medium | E-265's cost and the compiler's recompilation | superseded | slot retired; speed retired |
| L1 | Low | package-image workloads for the goal's shapes | declined, recorded | the workload rule (decisions §5, 2026-11-08: a workload counts only for broad typical cases) |
| L2 | Low | "a store, about a week" needs the writer stated | superseded | cache stopped |
| L3 | Low | stale copies on the cache's status | done (spot check) | compiler §9 "paused", state §6.3 "not built now", W-120 "stopped" |

## 4. `2026-11-08-issue-158-guarantee.md`

| Finding | Severity | In one line | Disposition | Where |
|---|---|---|---|---|
| H1 | High | a pruned `MethodError` arm never re-guarded when a method at a set arrives | done | compiler C-73 retired (gate `n11_late_shadow`); now compiler §5.5 |
| H2 | High | the widened result is intrinsic to a guard | superseded | no call carries a guard (open issue 158 closed 2026-11-11, W-140; compiler §5.5; GT-1) |
| H3 | High | a guarded call loses effects and exception type | superseded | as H2 (C-58, C-59 retired) |
| H4 | High | (d) finality by ownership | superseded | decided opt-in (decisions §9, 2026-11-09), then replaced by the user's rule of 2026-11-11: a non-membership is relied on everywhere, a late membership invalidates (traits §3.4, compiler §4.8, §5.5; GT-1) |
| M1 | Medium | which shapes guard; count first | done | W-124's count from the edges (E-319) |
| M2 | Medium | a membership making two methods ambiguous across arguments is not guarded | done | compiler §5.4 (the report asks every method made applicable, ties with a closed supertype or `Any` included; W-132, C-78 retired); §5.5 |
| M3 | Medium | an unfolded negative is a run-time subtype query | superseded | negatives fold with an edge (compiler §4.8) |
| M4 | Medium | `Keyed`'s untyped key widens the shadows | superseded | no method at a trait for a required operation (the plan's D-4; open issue 178 closed) |
| L1 | Low | the probes are not in the record | done (spot check) | no current document cites the probes' numbers; W-124 measured instead (E-319) |

## 5. `2026-11-08-unification-review.md`

| Finding | Severity | In one line | Disposition | Where |
|---|---|---|---|---|
| H1 | High | the walk's conservative pass costs 7–11× | done | compiler C-72 retired (`unified` aa997b2180, gate `m2_parametric_replay`, E-292); §5.5 status states the cost bound |
| H2 | High | setting D and NetworkDynamics' new equations recompile | done | C-54 retired; W-124's results (E-298, E-310, E-327) |
| H3 | High | the cast names are reserved words | done | open issue 160 closed (names bound, gate `n6_attribute`) |
| M1 | Medium | the guarantee's cost uncounted | done | E-319; 158 (a) and C-36 built; later no guards (W-140) |
| M2 | Medium | the slot's commits not folded; a binary named the wrong commit | superseded | the slot retired (D-7); the binary's own commit printed by `e289/run.sh` (performance review H3) |
| M3 | Medium | the walk runs under the world counter's lock | done | the remedy named was stage 1 (C-72), built; the lock is compiler §4.3's rule |
| M4 | Medium | harnesses: E-288 loop, missing data check, depot | done, in part | form (f) in E-289's `run.sh`; data check `forks/scripts/measure_session.sh:31`. The script still unsets `JULIA_DEPOT_PATH` (line 63): §3 |
| M5 | Medium | the record: registry cells, heads, untracked logs, `.gitignore`, core files, C-18 comments | done, in part | fixed with the review; `.gitignore` lists the worktrees; core files gone. C-18 still named in `julia-next/src/datatype.c:788, 1394` (§3) |
| L1 | Low | setting D differs from E-242 in the fifth digit | open, recorded | `experiments/unification/e289/README.md` (attributed to TDE e9e07ed, unchecked); no open issue |
| L2 | Low | the slot has kept nothing | superseded | slot retired (D-7) |

## 6. `2026-11-09-documentation-consistency.md`

| Finding | Severity | In one line | Disposition | Where |
|---|---|---|---|---|
| H1 | High | `design.md` calls `IO` a trait closed after load | done (spot check) | `design.md` |
| H2 | High | strict mode Planned in facts, Implemented elsewhere | done (spot check) | facts.md has no "Planned (W-114)" |
| H3 | High | the split Planned in facts §9; its rule differs | done | facts §9; traits §7.9 |
| H4 | High | the contract changes plain code's results at `IO` | done | open issue 171 closed (asserted, never converted; a closed type's contract promises no result; E-340) |
| M1 | Medium | build heads copied into the references | done | reference README links `state.md` §6.1 |
| M2 | Medium | bare W-items as statuses | done | reference README convention (line 28) |
| M3 | Medium | W-129's commits not folded | open, recorded | W-19 (waiting, after the synthesis); W-129's status: "the fold with W-19" |
| M4 | Medium | open issue 160 not linked; reservation stated | done | open issue 160 closed; traits §7.6 |
| M5 | Medium | dead citations and anchors | done | `experiments/docs-checks/check_links.py` with README |
| M6 | Medium | the glossary lacks contract, candidates, eraser | done (spot check) | glossary "Eraser `IOContext{IO}`", "Candidates" |
| L1 | Low | references call themselves drafts | done (spot check) | no "**Draft**" in the references |
| L2 | Low | "stages W-98 to W-114" | done (spot check) | compiler.md:7, julia-changes.md:116 name the later items |
| L3 | Low | status index omits C-79, C-81 | done | the INDEX row says fixed 2026-11-09 |
| L4 | Low | code comments name the retired C-18 | not found | INDEX: "W-129's last step"; W-129 retired; comments remain in `julia-next/src/datatype.c:788, 1394` |
| L5 | Low | stale "as of" headers | done, in part | evidence and open issues headers fixed; `design/julia-changes.md` still "as of 2026-10…", "Size (00dcc9994c): 65 commits" (§3) |
| L6 | Low | W-129's row points at a gone flag | done | W-129's status rewritten |
| L7 | Low | "at `T`'s key" where keys are Optional | done (spot check) | no such phrase in the references |
| L8 | Low | the contract slot holds two kinds | done | compiler §4.1 "The same slot holds a closed abstract type's contract" |

## 7. `2026-11-09-io-porting-lessons.md`

The lessons have no severity. Each "Done" part was done by the review itself (`intro/porting.md` 0.4, 0.6, A10, A11, B1.8). The disposition is of each lesson's "Proposed" part (§5 of the review). The INDEX row says only "§5's proposals for the user"; nothing in open issues §1 lists them.

| Finding | Severity | In one line | Disposition | Where |
|---|---|---|---|---|
| L1 | lesson | erase at the entry, not the kernels; flag a default that erases a library's type (5.1) | not found | proposed text not in CLAUDE.md; no open issue |
| L2 | lesson | the eraser is the type's own wrapper; gate its whole interface (5.2) | done | gate `n19_io_trait.jl:129–132` (`displaysize`, `mark` through `IOContext{IO}`) |
| L3 | lesson | which of Base's closed types declare a contract: an open issue (5.3) | not found | no open issue |
| L4 | lesson | a decision row names the guarantees it touches (5.4) | not found | not in CLAUDE.md |
| L5 | lesson | equations type results; the firewall stops edges | done (nothing new) | open issue 167 |
| L6 | lesson | a port change that applies a rule is no workaround (5.5) | not found | not in CLAUDE.md |
| L7 | lesson | the workload runs each erased entry by the REPL's path | done | `forks-unified/DataFrames/src/other/precompile.jl:30` (E-338); TraitReport, TraitMakie retired with W-129 |
| L8 | lesson | each port decides where it erases (5.6) | done | DataFrames (E-337); the rest retired with W-129 |
| L9 | lesson | an erasure fixes the port's share only | done (nothing new) | — |
| L10 | lesson | a control at the same load (5.7) | done, in part | registry convention "a session's row names its baseline … beside the load's control" (`record/experiments.md` head); CLAUDE.md rule 5 not amended |
| L11 | lesson | measure the motivating step on every build (5.8) | done, in part | E-337 measured the `show` step; the CLAUDE.md clause not added |
| L12 | lesson | a proxy's number is a lower bound (5.9) | not found | registry has the census rule (performance review M3), not the proxy rule |
| L13 | lesson | two readings of the user's words (5.10) | not found | not in CLAUDE.md |
| L14 | lesson | a test set at Base scale (5.11) | not found | no W-item, no gate |

## 8. `2026-11-09-performance-day.md`

| Finding | Severity | In one line | Disposition | Where |
|---|---|---|---|---|
| H1 | High | the goal's task misses its gate on the head; the record says met | done | evidence §3 (E-337 bullet), W-125 (dropped), PE-31 |
| H2 | High | dispatch's unmet-match drop unsound at `Callable`, unguarded at open sets | done | C-82 retired; open issue 172; compiler §5.4; alternatives |
| H3 | High | rows committed with their outcome; logs name the wrong build | done | registry conventions (`record/experiments.md` head); `e289/run.sh:23` prints the binary's commit |
| M1 | Medium | where the +0.15 s went | declined, recorded | PE-31 (below the rule's 20 %; speed work retired) |
| M2 | Medium | B-display's `write` step unreported | done | E-338 row; evidence §3; PE-25 |
| M3 | Medium | the route: a criterion crossed by 4× did not stop the work | done | registry convention "A criterion crossed by more than its own margin ends the line of work" |
| M4 | Medium | which general rules earn their keep | done | the drop restricted (C-82); open issue 173; the firewall's cost is GT-7 (open); the sysimg walk behind a flag (C-82 plan, M5) |
| M5 | Medium | flagged list misses the attribute rule and the firewall | done | GT-6 (decided, D-1), GT-7 |
| M6 | Medium | E-338's one claim is reasoning | done (spot check) | E-338 row says "reasoning … no arm ran it" |
| L1 | Low | `IO`'s declared results change plain inference | done | open issue 171 closed |
| L2 | Low | small points (no Python control; (t) at its gate's edge; …) | superseded | speed gates dropped (2026-11-09), speed retired |

## 9. `2026-11-09-plan-review-171.md`

Plan: `plans/2026-11-09-171-declared-results-without-conversion.md` §7.

| Finding | Severity | In one line | Disposition | Where |
|---|---|---|---|---|
| H1 | High | the head miscompiles a `UInt` count through the eraser | done | `unified` ef1233e79e (const result joined); gates `n19`, `n22` |
| H2 | High | `_SplitTarget` still converts | done | ef1233e79e; docstrings |
| M1 | Medium | the set gate raises `ImplementError`, not `TypeError` | done | `n22` (method redefined after its check) |
| M2 | Medium | (d) can be dropped | done | plan §7; alternatives |
| M3 | Medium | `--compile=min` gate needs its own runner | done | `n19` spawns the process |
| M4 | Medium | state the rule at sets: invariant plus backstop | done | traits §7.9 ("asserted, never converted … only catches what the check does not reach … the interpreter return the member's own result"); facts §2.1 |
| M5 | Medium | re-check a serving method redefined after the check | done | the recheck plan (TraitWorld 5b3c427, E-342); to be replaced by D-3 (T-129) |
| L1 | Low | forgotten records | done | plan §7 |
| L2 | Low | the closure facet | done | `n19` |

## 10. `2026-11-09-plan-review-c57-c81.md`

Plan: `plans/2026-11-09-c57-c81-small-deviations.md` §4.

| Finding | Severity | In one line | Disposition | Where |
|---|---|---|---|---|
| 1 | — | C-57's fix sound at every path | done (nothing asked) | C-57 retired (`unified` 0ee9e4f8a6) |
| 2 | Medium | the backedge also carries the callee's own invalidation | done | compiler §3.1 "The callee's own invalidation reaches the caller as through any backedge"; the slot half superseded (D-7) |
| 3 | Medium | more plain code in images: a registry row | done | E-340 |
| 4 | Low | the gate must test the dispatch edge | done | `n21_callsig_backedge` |
| 5 | Low | C-57's record | done | plan §4 ("10–12") |
| 6 | Medium | a contract on another image's type is lost | done | `jl_declare_contract` refuses it; compiler §7.1, traits §3.4 |
| 7 | Medium | the write-once contract fixes the candidates | done | plan §4; open issue 170 notes `LimitIO` |
| 8 | Medium | the package gate must cover the split | done | gate `n23_contract_image` |
| 9 | Low | C-side checks of candidates | done | plan §4 |
| 10 | Low | C-81's record | done | C-81 retired (18bbbf0841) |
| 11 | Low | the same pattern for a pattern member's candidates | not found | no sentence in C-30 or §7.2's status |
| 12 | Low | the build's order | done | commits ordered 171, C-57, C-81 |

## 11. `2026-11-09-plan-review-c82.md`

Plan: `plans/2026-11-09-c82-unmet-match-lookup.md` §7. Built in E-341; C-82 retired.

| Finding | Severity | In one line | Disposition | Where |
|---|---|---|---|---|
| H1 | High | lookup sites drop the cells; one home on `MethodLookupResult` | done | plan §7 |
| H2 | High | `Callable`'s rule decides only reflection; contradicts §5.4 | done | compiler §5.4 "met"; decision row; open issue 172 |
| M1 | Medium | an unbounded `Vararg` tail judged unmet | done | §5.4 "A `Vararg` tail … is met by its empty tail"; gate |
| M2 | Medium | gate (2) expects the wrong shape | done | plan §7 |
| M3 | Medium | the lone unmet match at a final pair | done | plan §7 |
| M4 | Medium | a taken experiment ID; stale copies | done | E-341; plan §7 |
| M5 | Medium | the sysimg walk's counter has two writers | done | `jl_any_closed_after_load` |
| L1 | Low | alternative (e)'s reason | done | alternatives |
| L2 | Low | one allocation per lookup | done | plan §7 |

## 12. `2026-11-10-plan-review-c78.md`

Plan: `plans/2026-11-10-c78-report-at-declared-supertypes.md` §7. M1 in `unified` 2ee5569252 (E-346); the rest W-132, `unified` 53d28eea68 (E-347); C-78 retired.

| Finding | Severity | In one line | Disposition | Where |
|---|---|---|---|---|
| H1 | High | the search at an abstract member reports ties through sets it is not in | done | W-132; compiler §5.4 "Through the member only" |
| H2 | High | the gate asserts a warning where there is no ambiguity | done | C-78's row; gate `m2_ambiguity_declared_super` |
| H3 | High | the substitution skips `All{X, Y}`, unions, bounds | done | W-132; compiler §5.4 "The call types" |
| M1 | Medium | "created by the membership" not in the rule | done | compiler §5.4; gate `m2_ambiguity_predates` |
| M2 | Medium | a tie with a method at `Any` | done | decided: reported and refused like any other (open issues §1 item on the report; alternatives) |
| M3 | Medium | the joint of several tied methods | done | W-132; §5.4 "One warning per method asked" |
| M4 | Medium | gates and records forgotten | done | W-132, E-347 |
| L1 | Low | cost | done (nothing asked) | — |
| L2 | Low | the ambiguity flag is not the criterion | done | W-132 |
| L3 | Low | today's suppression over-suppresses | done | W-132 |
| L4 | Low | activation reports a batch tie twice | done | W-132 |

## 13. `2026-11-10-plan-review-recheck.md`

Plan: `plans/2026-11-10-recheck-at-redefinition.md` §7; TraitWorld `unified` 5b3c427, E-342. The mechanism (records in the library) is to be replaced by the plan's D-3 (traits T-129, open; GT-2).

| Finding | Severity | In one line | Disposition | Where |
|---|---|---|---|---|
| H1 | High | refuse before insertion, inferring the new method | done | plan §7 |
| H2 | High | `Union{}` passes the test: ambiguity accepted | done | plan §7 |
| H3 | High | what the records cover, stated | done | traits §5.10 status; L-55 (since retired); W-130 |
| M1 | Medium | forwarding members unguarded | done | traits §5.11 |
| M2 | Medium | records on the first-use path | done | plan §7 |
| M3 | Medium | a record goes stale at a trait's redeclaration | done | plan §7 |
| M4 | Medium | forget records before a redeclaration's block | done | plan §7 |
| M5 | Medium | strict mode's log left on when the before branch throws | done | plan §7 |
| L1 | Low | names | done | plan §7 |
| L2 | Low | records forgotten | done | plan §7 |
| L3 | Low | cost | done | traits §5.10 status |
| L4 | Low | a deleted serving method | done | traits §5.10 |
| L5 | Low | the message for a definer who does not know the trait | done | plan §7 |

## 14. `2026-11-10-plan-review-t98.md`

Plan: `plans/2026-11-10-t98-strict-membership-ambiguity.md` §6; `unified` 0bb8f38830, TraitWorld 960b99e, E-343. T-98 since retired.

| Finding | Severity | In one line | Disposition | Where |
|---|---|---|---|---|
| H1 | High | the search before the counter advances finds nothing | done | plan §6 |
| H2 | High | the search reads the caches that hide the ambiguity | done | plan §6; gate `m2_ambiguity_called_before` |
| H3 | High | rollback by restoring lists is unsafe; retire the entry | done | plan §6; compiler §4.3 |
| M1 | Medium | the window invisible to other tasks | done | plan §6 |
| M2 | Medium | the same answer before and after the advance | done | plan §6 |
| M3 | Medium | the error; one path not wrapped | done | `_declare_checked!` |
| M4 | Medium | the image half reported, not refused | done | T-98 narrowed, then retired (TraitWorld 0aff625, E-349) |
| L1 | Low | gates | done | `test/strict_membership.jl`; case (e), a supertrait refused at `@trait Z <: Y`: declined, recorded in plan §6 ("no small case found") |
| L2 | Low | the record | done | plan §6 |
| L3 | Low | minor | done | plan §6 |

## 15. `2026-11-10-plan-review-w130.md`

Plan: `plans/2026-11-10-w130-records-at-load.md` §8; `unified` e42047dba2, TraitWorld 6871ea9, E-344.

| Finding | Severity | In one line | Disposition | Where |
|---|---|---|---|---|
| H1 | High | the entries index misses an image's own types | done | C-83 retired; gate `n12_image_instances` |
| H2 | High | `struct S <: X` members are not in the source | done | W-131 (below) |
| H3 | High | the gate's case 3 flips to a precompile failure | done | `stack/recheck_packages.jl` |
| M1 | Medium | `check_member(…; infer = false)` the wrong tool | done | `_records_at` |
| M2 | Medium | idempotence; the cursor | done | plan §8 |
| M3 | Medium | two images leave two live entries | done | C-84 retired (9f8d7d7c48, E-348) |
| M4 | Medium | the rebuilt record is the build's claim | done | traits §5.10; strict mode's check at load became GT-2, decided by D-3 (T-129 open) |
| M5 | Medium | the list's design | done | plan §8 |
| L1 | Low | `_fwd`'s skip is dead | done | `_fwd_sigs` |
| L2 | Low | §5's reasons | done | alternatives |
| L3 | Low | cost | done (nothing asked) | — |
| L4 | Low | records forgotten | done | plan §8 |
| L5 | Low | one list (optional) | done (nothing asked) | — |
| L6 | Low | entries the sync skips | done | plan §8 |

## 16. `2026-11-10-plan-review-w131.md`

Plan: `plans/2026-11-10-w131-declared-subtype-entry.md` §7; TraitWorld `unified` e8554d9, E-345.

| Finding | Severity | In one line | Disposition | Where |
|---|---|---|---|---|
| H1 | High | the abstract form's members never checked | done | C-85 retired; `test/declared.jl`; gate case 7 |
| H2 | High | a disagreeing instance at an input parameter accepted dead | done | `_params_at` reads the declared supertype |
| M1 | Medium | strict mode cannot make the form's membership not exist | done | traits §6.3; C-78 then built (W-132) |
| M2 | Medium | the hook runs for the concrete form | done | compiler §4.2 |
| M3 | Medium | wrong sentences on edges and the walk | done | compiler §4.2 |
| M4 | Medium | records and gates forgotten | done | W-131's row, E-345, alternatives |
| L1 | Low | the gate copy passes | done (nothing asked) | — |
| L2 | Low | the runtime path made exact | done (nothing asked) | — |
| L3 | Low | the report at the form | done | C-78 (W-132) |
| L4 | Low | alternatives | done | alternatives |
| L5 | Low | what the plan does not change | done | L-52 retired (TraitWorld 0aff625, 048c44e); the rest is compiler C-31 |

## Not found, or open without a record

No High finding is open without an open issue, a deviation row or a work item. The open High findings are none; the open Medium one (implementation day M7) is traits T-104.

**Not found** (9):

1. *Documentation review, L4 (also unification review M5, last part).* Code comments name the retired compiler C-18: `julia-next/src/datatype.c:788` and `:1394` ("compiler C-18", "the stopgap (compiler C-18)"). The INDEX gave it to "W-129's last step"; W-129 is retired. *Settles it:* rewrite the two comments to name compiler §5.5 (or §5.4) in the next `next` commit, or a W-item for code comments naming retired IDs (a grep over `julia-next/src` and TraitWorld `src` for retired IDs would find every instance).
2. *IO porting lessons, L1 (§5.1).* Flag before building a default that erases a library's own abstract type. Not in CLAUDE.md, not in open issues. *Settles it:* the user's answer, or a line under CLAUDE.md's tensions rule, or a recorded decline.
3. *IO porting lessons, L3 (§5.3).* An open issue: which of Base's closed abstract types declare a contract (`AbstractArray`, `AbstractString` next). *Settles it:* an open issue in §2, or a decline in alternatives.
4. *IO porting lessons, L4 (§5.4).* A decision row names the guarantees of facts §2 and §13 it touches. *Settles it:* the user's answer on the CLAUDE.md row "A decision".
5. *IO porting lessons, L6 (§5.5).* A port change that applies a rule of the references is not a workaround; measure and merge it first. *Settles it:* the user's answer on CLAUDE.md's "Principled solutions" paragraph.
6. *IO porting lessons, L12 (§5.9).* A proxy's row names what it does not model; a decision on a proxy's small cost is provisional. *Settles it:* a line in the registry's conventions, or a decline.
7. *IO porting lessons, L13 (§5.10).* Where the user's words have two readings of very different cost, the row quotes both and the other goes to open issues §1. *Settles it:* the user's answer on CLAUDE.md's "Gates do not stop the work".
8. *IO porting lessons, L14 (§5.11).* A test set at Base scale (a set over many of Base's methods) so that E-331, E-334, E-335, E-336 stay exercised. *Settles it:* a W-item or gate, or a decline (several of those rules changed with W-140; check which still need it).
9. *Plan review C-57/C-81, finding 11 (Low).* A pattern member's candidates are registered at its first use; once the hook's answers are kept in images, those candidates could vanish at load as C-81's did. No sentence in C-30's row or compiler §7.2. *Settles it:* check whether an image now keeps the candidate registered at a pattern member's first use (C-30 says an image keeps the passed answers); a sentence in C-30 or §7.2's status, or a gate.

**Done in part; the remainder has no record** (Low or Medium; for the main session's judgement):

- *BaseTraits review, M3:* `ReshapedArray`, StaticArrays' `MVector`, `ArrayPartition` are not `MutableIndexable` members. Settles it: add them, or a line in traits §10.1 or alternatives on why not.
- *BaseTraits review, M7:* `NTuple{N, T}` is not in `Iterable{T}`/`Indexable{T}`. Settles it: as above.
- *BaseTraits review, L6:* traits §10.1's table gives `c[i] = x`, `push!`, `resize!` no result type, though §4.1 requires one (the code declares `::Any`). Settles it: `::Any` in the table.
- *Implementation-day review, M5:* the ports' READMEs keep no dated result rows (they live in `experiments/unification/w104/`); `TraitReport-unified/README.md` and `TraitMakie-unified/README.md` still describe `Kept{X}` sections of the earlier design; `TraitReport-unified/scripts/check.sh:12` defaults to `julia-1.13`. Settles it: a pass over the ports' READMEs (W-162 scope?), the default `JULIA` changed.
- *Implementation-day review, M6:* no crash log and no gate case for `applicable` at `Union{}` (julia-changes row 49, fb0c7ba75a, an upstream fix). Settles it: a gate case, or accept the row as the record.
- *Unification review, M4:* `forks/scripts/measure_session.sh:63` still unsets `JULIA_DEPOT_PATH` (the home depot, against setup.md). Settles it: point it at the workspace depot.
- *Unification review, L1:* setting D's fifth-digit difference from E-242 is recorded only in `experiments/unification/e289/README.md`, unchecked. Settles it: accept as recorded, or one run of the earlier build at TDE e9e07ed.
- *Documentation review, L5:* `design/julia-changes.md`'s header still says "as of 2026-10…" and "Size (00dcc9994c): 65 commits". Settles it: link `state.md` §6.1 for the build, as the references do.
- *Cache review, M1:* compiler §9's list of what the record names omits the values the code embeds, the optimizer's flags and the Julia build, while facts §12 names embedded values. The cache is paused, so it waits, but the two references disagree (rule 3 of CLAUDE.md). Settles it: one clause in compiler §9 or in C-52's row.
- *IO porting lessons, L10, L11:* the CLAUDE.md clauses (a control at the same load; measure the step a change was made for) were not added; the registry convention covers the control in part.

## Counts

199 findings in 16 reviews; every review was finished.

| Class | Count |
|---|---|
| done (including "done, in part" and "nothing asked") | 153 |
| open, recorded | 5 |
| superseded | 30 |
| declined, recorded | 2 |
| not found | 9 |

By review (done / open / superseded / declined / not found): basetraits-choices 16/2/0/0/0; implementation-day 5/1/11/0/0; machine-code-cache-design 1/0/11/1/0; issue-158-guarantee 4/0/5/0/0; unification-review 7/1/2/0/0; documentation-consistency 16/1/0/0/1; io-porting-lessons 7/0/0/0/7; performance-day 9/0/1/1/0; plan-review-171 9/0/0/0/0; plan-review-c57-c81 11/0/0/0/1; plan-review-c82 9/0/0/0/0; plan-review-c78 11/0/0/0/0; plan-review-recheck 13/0/0/0/0; plan-review-t98 10/0/0/0/0; plan-review-w130 14/0/0/0/0; plan-review-w131 11/0/0/0/0.

## Addendum (2026-11-18, the main session): checked, and what is done with section 3

**Checked** by five spot checks against the tree (the two comments that name C-18; the forks' script and its depot; T-104's row; the BaseTraits table; the library's branch). Each held.

| Finding | Done |
|---|---|
| Not found 1 (comments naming C-18) | [open issue 233](../open-issues.md#5-documents) |
| Not found 2, 4, 5, 6, 7 and the lessons L10, L11 of the `IO` episode (proposed rules for `CLAUDE.md`) | in the changes to `CLAUDE.md` proposed to the user with the clean-up's report; the know-how is in [the playbook](playbook.md) §4 to §6 and [the lessons](../design/lessons.md) §5 |
| Not found 3 (contracts on Base's closed abstract types) | [open issue 229](../open-issues.md#2-design) |
| Not found 8 (a test at Base's scale) | [open issue 232](../open-issues.md#4-runtime-and-measurements) |
| Not found 9 (a pattern member's candidates and images) | [open issue 231](../open-issues.md#2-design) |
| BaseTraits M3, M7 | [open issue 230](../open-issues.md#2-design) |
| BaseTraits L6; the cache review's M1; the documentation review's L5 | the references' pass of the clean-up (part 5) |
| Implementation-day M5; the unification review's M4 | the demonstrators' pass of the clean-up (parts 6 and 7) |
| Implementation-day M6; the unification review's L1 | accepted as recorded: the row of `julia-changes.md`, and E-289's README |

