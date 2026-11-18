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
