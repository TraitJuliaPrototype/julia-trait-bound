# Session note and handover, 2026-11-10 (night): the goals

For the next agent session and the user. Every fact here has a home in the record; this note gives the chronology and the user's words in full. It follows [`2026-11-10-evening-hook-queue-strict-load.md`](2026-11-10-evening-hook-queue-strict-load.md).

## The user's words

After the evening's report:

> "The entire point of this project is to show that Traits and Facts actually enable dramatically reducing (re) compilation and potentially improve speed and caching with limited to no downsides and better error messages and better AOT compilation experience. We also want to show that there is a clean and doable path for the ecosystem to transition with clear potting guidelines. Finally unification made the design of the Trait system dramatically simpler, making it easy to teach. Please critically assess how we stand with respect to these goals, and what of the remaining work directly contributes to these goals."

After the assessment:

> "I don't want to claim  better steady state speed, just no regression/the possibility to opt into full speed (compiled_for(x)). I want to stop pursuing speed for now. We have gained enough to be satisfied. The IO work also shows the difficulty of reasonable solutions to isolated slowdowns in an existing ecosystem. Record this, and your assessment of the goals in a new document that tracks our progress on each axis. Clean up our experiment, decisions and work/todo log to reflect the aim to build towards that goal, prioritising weakest spots. I don't want to review all decisions made by you. I want to continue the strategy of recording pressure and tension between the goals (as we did for pushback on the design from speed and port work). The goal is not for me to review this bit by bit but to eventually create a synthesis, and iterate the design from all the evidence collected."

## What was done

Documents only; nothing was built or run. The assessment was made in the main session from the evidence and `state.md`.

- **A new document, [`writeup/goals.md`](../writeup/goals.md):** the goals in the user's words; eight axes G-1 to G-8 with the claim on each; where each stands, its weakest point and the work that serves it; the index of tensions GT-1 to GT-10; the synthesis.
- **The rules** (`CLAUDE.md`): the goals direct the work; speed work is stopped; a tension between the goals is recorded, not resolved at the case; the agent's choices are not reviewed one by one.
- **The decision log:** the speed row in §5, the goals and the tensions rows in §8; "No speed target" moved to the superseded rows; the status "for the user to confirm" reads "input to the synthesis" (46 rows).
- **The open issues §1:** the flagged list is "tensions between the goals", its entries numbered GT-1 to GT-7, with three new ones: GT-8 (G2 covers less on the unified build), GT-9 (the membership machinery costs plain code), GT-10 (an isolated slowdown in an existing ecosystem: the lesson of `IO`). The lists of the agent's choices are input to the synthesis.
- **The work queue:** "The plan" ordered by the weakest axes; new items W-134 (the guarantee's controls on the unified build), W-135 (binaries), W-136 (error messages), W-137 (the guideline and the intro against the head), W-138 (the synthesis); W-121 and W-129 paused; W-17 a control measured once.
- **The experiments registry:** the proposed speed experiments parked (E-34, E-74, E-106, E-107, E-127, E-191); the proposed experiments that serve a goal assigned to their W-item (E-30, E-60, E-61, E-83, E-96, E-109, E-110, E-112, E-118).
- **`state.md`** §6.3, the references' README, the intro's two lines on the retired target, the record index.

## Choices of mine in it

- The eight axes and the standing of each.
- The order: G-1's controls before G-6 and G-5, though those two have less evidence, because the other claims rest on G-1.
- AOT binaries (W-135) taken up though the user deferred AOT in session 25: the user's goals name the AOT experience; the annotations A to E stay deferred.
- The existing proposed experiments were re-pointed, not replaced: each run gets a new row.

## Handover

- Next: W-134. Register its experiments first.
- Not done, from the evening: the static analysis of `src/gf.c` on `unified` fcdfd0da36. The six `core-login02-*` dumps in the design repository's root are the user's to delete.
