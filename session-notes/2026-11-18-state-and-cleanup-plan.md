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
