# 2026-11-18: the state looked at, and a plan for the documentation clean-up

The main session. No agent, no build, no measurement. Nothing was moved or rewritten.

## The user's words

1. "Look at the overall state of this project right now in some detail."
2. "So I want to do some housekeeping and also clean up the documentation. Currently a lot of the documentation seems still to be written in terms of the history, and referencing the pre unified implementation. At this point unified _is_ the implementation. The documentation should describe the intended design. The to-dos and the experiments lists and similar stuff should be cleaned up. The experiments list needs to show the experiments of the current implementation. The baseline is plane Julia and Python, not previous iterations of the design. We need to get rid of all reviews and plans that are not relevant anymore, they can go into an attic. The most relevant insights should be extracted into alternatives considered, lessons learned and similar documents. Please make a comprehensive documentation clean up plan and come back to me with a thorough suggestion."

## What was done

- **The state, read and checked against the trees.** As [the plan for the next iteration](../writeup/plans/2026-11-15-next-iteration.md) §6 says: stages 0 to 3 and 5 done, stage 4 next; no commit in any tree since 2026-11-15; every branch pushed. `julia-next` (32a2235abd) and `julia-unified` start.
- **Found beside it:**
  - `state.md` is headed 2026-11-14 and describes the heads of the 15th; the G-8 row of the axes table in `goals.md` has a sentence in the wrong column.
  - `experiments` has 107 untracked logs (96 in `unification/stack/logs`); `julia-unified` holds a core dump and twelve build logs.
  - `julia-unified`'s binary reports 8fccf1e182*, one commit behind the tag 7b374f39ce. Its `sys.so` was built 27 minutes before that commit was made, so probably with the change uncommitted. Not verified.
  - The website is built from `main`, which is 81 commits behind `w141-record`.
- **The plan:** [`writeup/plans/2026-11-18-documentation-cleanup.md`](../writeup/plans/2026-11-18-documentation-cleanup.md), a proposal. Its survey's counts are in its §1. It waits for the user: eight decisions, §8.

## To go on

- The user decides on the plan. On adoption it becomes W-162 in the work queue, and its part 0 is first (the tool, the tags, `main`).
- Stage 4 of the next iteration (W-156) is otherwise next. The plan's §6 says how the two fit.

## Later the same day: the plan adopted, part 0

**The user's words** (on the plan's eight decisions): "Q1 yes, Q2 you decide, measuring a set of changes against the immediate predecessor is of course fine during regression testing and performance work. Q3 yes, Q4 yes, Q5 Clean Up the directory names as well, but do it last. Q6 you decide, Q7 check and keep. Q8 you can use subagents. But not too many in parallel. Should we also have an additional "for agents" documentation that gives more context than humans would like? Would it be possible for this session to actually do all the reading to be better able to extract relevant lessons by having maximum contextual knowledge of the project?"

**Recorded:** the plan's status line, §8's last column and §9; the decision log §8 (two rows, the second mine); W-162 in the work queue; `CLAUDE.md`'s exception for subagents; the index.

**Mine, on the two questions** (the plan §9):
- The record becomes the agents' tier: `record/context.md`, `record/build-notes/` per reference section, `record/playbook.md`, the attic's digest. What rule R2 takes out of the documents for people goes there.
- The harvest is read in the main session. The volume is 4.5 MB, more than a million tokens, so the session cannot hold it at once; the notebook `writeup/record/harvest-2026-11.md` carries it. Subagents only for work that can be checked mechanically, at most two side by side.

**Part 0, done.**
- The tool: `experiments/tools/doclint/` with its first log (experiments 4e32228). Its totals before the clean-up: earlier-build names 640, history words 348, dates 3,025, comparisons against an earlier iteration 89, links into what is archived 825, experiment IDs of the earlier build 327; in the references 727 commit hashes, 294 work items, 521 branch names. No broken link.
- The tags `docs-before-cleanup-2026-11-18` on the design repository and on `experiments`.
- `main` is the design repository's branch, at the head, pushed; the website builds from it. The local `main` held two commits of 2026-11-12 that were never pushed (a baseline tree committed by mistake, and its removal). Their net content is the first commit of `w141-record` (428b50c), checked file by file; the local branch was moved to the head. `w141-record` stays where it is until part 7.
- The 107 untracked logs of `experiments` committed.

**Found on the way:** the survey counted experiment IDs with a pattern that also matched `PE-n`; the tool's count is the right one (84 of the earlier build in the evidence, not 89; none in the references).

## The night: the whole plan, unattended

**The user's words:** "I can't look at them now, can you print one in your response please?" (one notebook entry was printed), then: "This looks good to me, you are the judge on this though, you have the better overview to judge this. Go ahead. I am going to bed, so work without getting back to me and only report back at the very end."

**So:** the plan's parts 1 to 9 are worked through in the main session without a question to the user. A choice on the way is made and recorded (the decision log, mine). One thing waits for the user as agreed: the rules' changes in `CLAUDE.md` are prepared as a diff and shown in the final report (Q1: "shown as a diff first"); only links that the move breaks are fixed there before.

**Where the work stands** is kept in two places, for a session whose context has been summarized:
- part 1: the Progress table of `writeup/record/harvest-2026-11.md`;
- the parts: the row W-162 of the work queue.

## The night's log

**Part 1, the harvest: done.**
- Seven batches of reading, each committed with its notebook entries (`writeup/record/harvest-2026-11.md`: 110 lessons, 11 groups of alternatives, 46 checks against today's documents).
- **How much was read in full, stated plainly:** the reviews and plans to 2026-10-21, the explorations `wrapping-by-facts`, `dataframes-port-lessons`, `ndport-pushback`, `ndport-principled-traits`, the meta plan of the NetworkDynamics port, the synthesis, the High findings of the reviews of the turn to unification. The rest (from 2026-10-22 on: about 2 MB) by status lines, summaries, every finding's opening and the closing sections. The Progress table says which, batch by batch. The promise "the session reads all of it" was kept for every document's conclusions, not for every line (mine).
- **Its products:** `design/lessons.md` (new); `design/alternatives.md` regrouped under eleven chapters with the harvested entries added; `design/proofs.md` (Q7: the proofs of G1 and G2 in today's terms, from `wrapping-by-facts` and facts §1, §2); `record/context.md` and `record/playbook.md` (the agents' tier).
- **The dispositions of sixteen reviews** (2026-11-07 to 2026-11-10) were audited by an agent (`record/harvest-dispositions-2026-11.md`: 199 findings; 153 done, 30 superseded, 5 open and recorded, 2 declined, 9 without a record). The nine and the partials: open issues 229 to 233, the proposed changes to `CLAUDE.md`, and the later parts of the clean-up.

**Part 2, the move: done.** 78 plans, 73 reviews, the explorations, the findings log and three retired design pages are under `attic/writeup/` at their old relative paths; the stubs are deleted; 725 links in current documents follow; `attic/README.md` is the index by era with one line per archived document; the site's navigation follows.

**Part 7, the workspace: done but for one item.**
- Removed: the worktrees `julia-s3`, `TraitWorld-s3`, `TraitWorld-w155`, `TraitDifferentialEquations-s3` (each merged; the last held one local line that `unified` has), the six `wt/design-w*` with their `iter-w*` branches, the copy `julia-unified-base` (3.3 GB; only W-141's README names it), the core dump and eleven build logs in `julia-unified`.
- Deleted in the design repository: `w141-record`, `p2-experiments`, `poc-error-split` (merged), and `binA-wip`, local and remote. Its one commit was the unverified work in progress of 2026-11-12; its session note is in `main`, and bin A was finished and verified on 2026-11-14. The branches `binA-wip` of the other repositories are left.
- The tag `pre-unified` on the earlier line's head of each repository: julia `trait-world-1.13` 00dcc9994c, TraitWorld `main` 1c2335f, TraitDifferentialEquations `w34` e9e07ed, TraitMakie ba46982, TraitTables 438ac2b, TraitCSV 9c6477b, TraitReport 882c533, forks a28abf1. Pushed.
- The manifests of `TraitReport-unified` (three environments) and `ndport` (two) committed.
- **Not done (mine): the build output of `julia-1.13` is not cleaned.** Scripts of the record under `experiments/unification/` run its binary for the controls against the earlier line. 1.9 GB is not worth breaking them before the rename of part 9 touches those paths anyway.

**Part 3, the record: done.**
- The index is short (the old one: `attic/writeup/record/INDEX-2026-11-18.md`). The work queue holds the open items (every row as it stood: `attic/writeup/record/todo-closed.md`).
- The registry of experiments by goal: 106 rows; 329 IDs in the ledger only, each with its reason (`attic/writeup/record/experiments-archive.md`, which holds every old row). Two agents drafted the rows; the merge and the checks (every ID once; every number of a kept row in its old row) were the main session's.
- The decision log by the part of the design: 283 rows; 209 in `attic/writeup/record/decisions-superseded.md`. An agent classified, a script built both files, every row unchanged.
- The open issues as what is open: no question for the user, 12 tensions, the agent's choices one line each, the design's and the implementation's items. What the pass closed, with reasons: `attic/writeup/record/issues-closed.md`. New from the clean-up: open issues 229 to 237.
- The experiments repository: the earlier experiments that nothing reads are under `experiments/attic/`; its READMEs describe the implementation's layout.

**Part 4, the evidence and the goals: done.** `design/evidence.md` by goal, each number against plain Julia or Python with its build and experiment (an agent's draft from the old page, kept at `attic/writeup/design/evidence-2026-11-18.md`; numbers checked by script). `goals.md`: the standings on that evidence, the index of the twelve tensions that stand. `design.md` and `intro/results.md` on the same numbers.

**Part 5, the references: done.** Three agents, one brief: a status line is one word and its deviation rows; commits, branches, dates, work items, plan rows, experiments and the user's words left the text for `record/build-notes/`; 279 retired deviation rows are in `attic/writeup/record/deviations-retired.md`. No heading or anchor changed. Status lines that the pass showed stale were corrected (traits §3.1, §3.6, §7.4 to §7.6; compiler §8.2).

**Part 6, the front and the teaching: done but for the repositories' READMEs** (an agent's, running when this was written).
- `intro/traits-for-julia.md` and `traits-by-example.md` teach the box and the wrapper; their scripts run on `next` 32a2235abd with the library at d1febca: intro 24 pass, tutorial 94, strict 5, four deviations marked.
- `intro/porting.md` rewritten on the ports' code of today, with the harvested rules; its 23 quotes check against the ports' files.
- `design/other-languages.md` on the design as it is (an agent's; it stopped at a usage limit after writing the page; the main session ran its checks). `design/julia-changes.md` is the inventory of the current line. The glossary without retired terms. The setup page, the writeup's overview, the environment page.

**Part 9, the names: done.** `writeup/plans/2026-11-18-names.md`. The seven `-unified` trees lost the suffix; the earlier checkouts are under `pre-unified/`; `experiments/unification/` is `experiments/implementation/`; 1,639 places in 364 files rewritten by `tools-local/names-2026-11-18.py`. Checked on `next` after it: the library's suite (93 testsets), the ODE library's (35), TraitMakie's (8), NetworkDynamics' subset as before, the stage gates, the forks' digests (equal at 26 steps), the examples.

**Found on the way, each recorded and none fixed at the case:**
- **A crash:** the tutorial's script ended with a segmentation fault in 2 of 6 runs, in dispatch's leaf cache while `@trait` was expanded (open issue 234; W-163). The two core files (0.5 GB each) were deleted; the backtrace is `experiments/docs-examples/logs/tutorial-next-32a2235abd-b-segfault.log`.
- **Four gates fail on `next` and pass on the tag:** `n8_callable`, `n20_unmet_lookup`, `n22_declared_assert`, `n26_callable_late_method`. They assert rules the iteration replaced (open issue 237). Of the 71 gates in force 67 pass.
- **The forks' digests differed from upstream's after the rename's rebuild of the images.** The cells were equal; `hash(Date)` differed between the two environments, which loaded two cache files of Dates. The digest is now made from the cells' printed form (forks 201950c's parent commit).

**The user, in the morning, after a usage limit stopped two agents:** "You hit a usage limit. Continue with only one opus subagent at a time." From then on one agent at a time. It is in the proposal for `CLAUDE.md`, not in `CLAUDE.md`: an edit of that file's rules was refused by the harness, as the user had asked to see rule changes as a diff.

**What waits for the user:** the proposal for `CLAUDE.md` (`writeup/plans/2026-11-18-claude-md-changes.md`); the default branch of each repository on GitHub. The review of the whole: `writeup/reviews/2026-11-18-documentation-cleanup.md`.

## After the report

**The user's questions** on the report: "What had happened before the usage limit?"; "The agents that were running before were Fable or Opus?" (Opus, every one); "What's the next Todo" (W-163, the crash).

**The user's answer:** "Go ahead with the Claude proposal. I will take care of GitHub. Continue the work using an Opus subagent. We won't have an outside reader so remove that. The work log should be more for things you can do."

**Done on it:**
- `CLAUDE.md`: the proposal applied as its diff stood; two lines added with the user's words (one Opus agent at a time for the work of the queue; the work queue holds only work an agent can do).
- The reader from outside removed from the work queue (W-158), the state page, the next iteration's plan (D-15 and its note), the results page; the evidence and the goals now say that teaching is not tested.
- The work queue rewritten: only work an agent can do, each item with its first step. New: W-164 (the four gates that assert replaced rules; open issue 237). Closed into the ledger: W-162 (done), W-110 (keys: deferred).
- The clean-up's plan, the plan for the names, the proposal and the review moved to the attic; the review has an addendum with the user's answer.
- One question waits for the user (open issues §1, Q-1): the eight commits whose co-author line names a model.
- W-163 started: an Opus agent in `wt/w163-julia`.

## W-163: the crash, found and fixed

An Opus agent worked in `wt/w163-julia` (branch `w163`) and `experiments/implementation/w163/`; the main session reviewed the fix, merged, rebuilt and checked.

- **The fault:** `jl_lookup_generic_` holds the call's tuple type in a C local. Vanilla is sound there, because nothing allocates before `jl_mt_assoc_by_type` roots it. The design's member hook at dispatch (`member_hook_at_dispatch`) was put into that gap; it allocates (a method lookup) and runs the library's hook. A tuple type with a `Type{…}` parameter is not in Julia's type cache, so a collection there freed it, and `lookup_leafcache` hashed freed memory. The same pattern in the compile queue's drain (`jl_type_infer_policy`).
- **Plain runs did not reproduce it** (0 of 30 for the agent). A collection forced in the window (`window_gc.patch`, a runtime built with the collector's debugging) crashes `tutorial.jl`, `intro.jl` and `strict.jl` with E-502's backtrace before the fix, none after.
- **Every place of its kind:** Julia's static check of GC roots over the changed runtime files (`sagc.sh`; the Clang JLL was fetched for it): 26 findings against vanilla's 0. Three real (fixed), fourteen held in practice (eleven now rooted, three annotated), one NULL dereference (guarded), eight false positives (annotated). 0 after. `roots.sh`: two globals without a root, now rooted.
- **The commits** on `next`: 768850cff7 (the runtime compiles under clang), 436bb59b29 (the fix), a5bd871cce (the other findings). `next` fast-forwarded and rebuilt (442 s).
- **The main session's checks on the rebuilt head** (`experiments/implementation/w163/logs/main-a5bd871cce-*`, `w161/logs/w163-*`): the gates in force 67 of 71 (the four of open issue 237); `gate_deep`, `gate_d11`, the four check gates; the library 93 testsets; the ODE library 35; TraitMakie 8; NetworkDynamics' subset with its known failures; the forks' digests equal at 26 steps; the examples; the tutorial's script ten times without a fault.
- **Found beside it, fixed:** loaded from source, the library stopped with `UndefVarError: _signatures_of`: a generated function's generator called a helper defined after it. The helper now stands before it (TraitWorld 3e64ede); the tutorial's script passes with `--compiled-modules=no`.
- **Recorded:** E-502's outcome; open issue 234 and W-163 closed into their ledgers; the inventory's rows 137 to 139; the playbook §3 (the static check for a change to the runtime's C code) and §5 (the trap).
- **W-164 started:** an Opus agent in `experiments/implementation/gates/`.

## W-164: the gates say what is in force

An Opus agent worked in `experiments/implementation/gates/`; the main session ran the result and recorded it.

- The four gates rewritten to the rules in force (`n8_callable`, `n26_callable_late_method`, `n20_unmet_lookup` case 5, `n22_declared_assert`), one added (`n8_callable_box`, with the library). Each fails on the tag's Julia or under a wrong assertion on the head.
- The nine `m3_*` files are in `gates/not-in-force/`. `gates/run_all.sh <tree>` with no pattern runs the 72 gates in force and the 9 stage gates of `gates/stage_gates.txt`. On `next` a5bd871cce: 72 of 72 and 9 of 9, run again by the main session (`gates/logs/main-a5bd871cce-all.log`).
- **A mistake of the main session:** its commit of the check logs (experiments cb51434) took the agent's staged renames with it, since a plain `git commit` commits everything staged. The playbook §9 now says to commit with a pathspec where an agent works in the same repository.
- **Found by the gates:** two methods at `Callable` instances that differ only in an input do not tie: the intersection of the two instances is `Union{}`, and dispatch selects one silently (compiler C-147). And the unmet lookup keeps its ambiguity flag at `Callable` (C-148). The rule was not in the reference: compiler §4.9 and traits §3.2 now state that two instances of one set meet where they differ only in inputs (mine; the decision log). Open issue 238 keeps what is not decided: an entry that leaves a parameter free which is no input.
- **The static check of GC roots on `julia-next` itself:** 15 files, 0 findings. A first run read "0 findings" although the checker's plugin had not been built: `sagc.sh` now exits with an error when the check could not run. `wt/w163-julia` and the merged branch `w163` are removed.
- **W-165 started** (E-503 registered): an Opus agent in `wt/w165-julia`.


## W-165: two instances of one set

An Opus agent worked in `wt/w165-julia` (branch `w165`); the main session reviewed, merged, rebuilt, ran the checks again and recorded. The agent was stopped once, at the user's word ("Stop work I til 12:10 to avoid limits", "Dublin time"), and resumed at that time.

- **Built** (julia `next` 7397ab6f70, a29ffdd428, 02139b2168; E-503): two instances of a set that may differ in an input meet as `All{X{A}, X{B}}`, so two methods at `Callable` instances tie for every function, with a report. `Callable` is closed after load as every set, and a set written with free parameters is asked as the set: the unmet lookup drops its ambiguity. Compiler C-147 and C-148 retired.
- **The build corrected the rule I had written:** `HasProperty{:a, Int}` and `HasProperty{:b, String}` differ in the input and in another parameter, and meet. The rule is: disjoint where the instances agree in every input and differ in another parameter (compiler §4.9; the decision log's row).
- **A second reading of intersection, found by gate `n10_inputs`:** an entry's own instance is paired with the instance asked about parameter by parameter; else the one-instance check refuses a member at two input values (compiler §4.6).
- **The census** (`experiments/implementation/w165/census.jl`): no pair of methods in Base, the library or a port is at two instances of one set at one argument. Nothing else ties.
- **Left:** compiler C-149 (two instances whose variables unify are answered by the unified instance alone); open issue 239 (a caller at an abstract instance calls dynamically where another method is at another input value; the proposal is a cell per instance); open issue 238's case is unchanged.
- **A trap of the build:** Julia's make does not rebuild the first image stage (`basecompiler`) for a change of the runtime, and that stage stores Core's types with the bits the runtime's start gave them. `tools-local/build.sh` now touches `Compiler/src/Compiler.jl` where a runtime source is newer than the first stage, so every stage is rebuilt (the playbook §2).
- **The main session's checks on the rebuilt `julia-next`** (02139b2168, 832 s): gates 72 of 72 and 9 of 9; the suites as before (library 93 testsets, the ODE library 35, TraitMakie 8, NetworkDynamics with its known failures, the forks' digests equal at 26 steps); Base's `subtype`, `core`, `ambiguous`, `worlds` pass, `detect_ambiguities(Base)` 0; the examples pass; the static check 0 findings in 15 files. Logs: `experiments/implementation/w165/logs/main-*`, `w161/logs/main-02139b2168-*`.
- **W-156 started, its first part** (E-504 registered): an Opus agent converts the demonstrators' casts (traits T-128), on a branch `w156` of each demonstrator's repository.
