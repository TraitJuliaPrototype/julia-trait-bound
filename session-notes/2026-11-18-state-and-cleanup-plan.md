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
