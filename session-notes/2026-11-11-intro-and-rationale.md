# 2026-11-11: the introduction and the rationale

The user: "Look at the documentation next, especially the introduction material and the high level rationale and arguments."

Read as the review part of W-137, ahead of the plan's order (W-135's rest and W-136 wait), and widened to `design.md`. Done in the main session. The review, with every finding and what was done with it: [`writeup/reviews/2026-11-11-intro-and-rationale.md`](../writeup/reviews/2026-11-11-intro-and-rationale.md).

## What was done, in order

1. Read `README.md`, `goals.md`, `design.md`, `state.md` and the four pages of `intro/` against the goals of 2026-11-10 and the evidence of E-355 to E-361.
2. Ran `intro/`'s examples on the head (TraitWorld 05991fc): 18, 83 and 5 pass; the quoted messages match. Logs in `experiments/docs-examples/logs/`.
3. Reading the tutorial's §12 as a newcomer: `keep` at the prompt stores a `Dynamic{Shape}`, from a function the value. Probed (`experiments/docs-examples/keep_at_prompt.jl`): code that asks more of the item than its trait gets different answers. Open issue 175. "Open" in three senses: open issue 176.
4. A tool for the porting guide's quotes, `experiments/docs-checks/check_quotes.py`: four of 23 had moved.
5. The pages changed:
   - `design.md`: the goals linked; E-355 in §2.3; §2.6 renamed, with what is measured and what is only argued, and GT-8; a new §2.7 for the argument's map to the goals and the arguments for G-5, G-7, G-8; §4's non-claims (speed, plain code's cost, trimmed binaries).
   - `intro/traits-for-julia.md`: the guarantee's limit, the loads' numbers, the costs, the prompt.
   - `intro/results.md`: rewritten by claim, from E-355 to E-360 and E-337, without the core developers' terms.
   - `intro/traits-by-example.md`: the attribute's step 5, the kept item, `Callable` as the exception, trimmed binaries.
   - `intro/porting.md`: the path in five steps with gains, costs and commits; what a port does not do.
6. The record: `goals.md` (G-7, G-8), the work queue (W-137 in progress), the record index, `state.md` §6.3.

## Choices made (mine)

- The rationale gained arguments for G-5, G-7 and G-8 (§2.7). They cite the references and state no rule.
- The sessions against Python moved from "What you get" to "What it costs" in the introduction: no goal claims parity.
- Nothing was measured anew. The results page's session totals are E-337's, its steps E-324's, each named.
- The reference's sentence "Both run the same methods and give the same results" (traits §7.4) stands until open issue 175 is decided; the tutorial teaches the exception.

## Then: "Do that too"

The user, on the list of what was left: "Do that too".

- The introduction reordered: the worked example before the parts.
- The evidence's summary replaced by a map from the axes to its sections. The old summary held eight numbers that no row of the body had, so its lists stay as a section of the earlier build's results (mine).
- The guide's part B read against the ports' heads: one sentence corrected.
- W-137 done. The review has an addendum.

## Left

- The motivation's numbers on Julia 1.13 (the review's P3): with the synthesis.
- The plan's order: W-135's rest, W-136, then W-128's image items.
