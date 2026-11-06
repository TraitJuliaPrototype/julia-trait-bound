# 2026-11-06: the unified build, stage 0

On the shared RHEL 9 host (128 cores). The synthesis plan of 2026-11-05 ([`../writeup/plans/2026-11-05-unification-synthesis.md`](../writeup/plans/2026-11-05-unification-synthesis.md)) adopted; stage 0 (W-97) begun.

## The user's words

On being asked what is needed to start implementing the plan, the user answered (2026-11-06):

> As long as load is this low, its fine to use more of the machine: You can use half the machine for compiles while it is mostly empty. Once it fills up to at least half load you restrict to four cores and sequential work. (record this as a rule) Decision 1: agreed. Decision 2, agreed, decision 3. agreed, decision 4, agreed. decision 5 agreed. decision 6. agreed decision 7 we stay on 13.2 Decision 8 agreed decision 9 agreed. 10. agreed, though the design and implementation should be aware that a machine code cache is the eventual goal. 11. agreed. 12. agreed 13 confirmed as your call. Agreed on W-S0a. Get started (and no subagents on this machien please)

And, while the work ran:

> One clarification to the rule: It is okay to spike up to half machine use. Sustained use should be considerably lower.

"Agreed on W-S0a" answers the proposal to count, as the slot's estimate, "facts callers whose only edges to invalidated callees are result edges, where the callee's result did not change", on more than the forks' session: E-238 found that none of the 1,884 MethodInstances invalidated in the forks' session were compiled again there, so a count of recompilations alone would say nothing.

## Done

- **The rule for cores by load** in `CLAUDE.md`, the record's standing constraints, `setup.md` and the workflow note; `tools-local/build.sh` applies it to a Julia build (wide at the start below half load, narrowed to `-j4` when the others' load reaches half, paused above 110; stage times and sampled peak RSS in the log). "Sustained use considerably lower" read as at most 16 cores in all (mine). No subagents on the shared host, in the same places.
- **The trees:** `julia-unified/` (branch `unified` at c3f0b4bc11, from `origin/oc-build`) and `julia-vanilla/` (detached at `45b6d15e34`), each with `julia-1.13`'s source cache copied in. `unified` building at `-j64` from 11:46 (load 5–7).
- **The decisions** 1–13 in the decision log §5, with the user's words.
- **The references' Planned sections:** compiler §7 rewritten as the unified build (§7.2 memberships, §7.3 one dispatch, §7.4 guards and cells, §7.5 keys, attributes and the check, §7.6 compiling by facts per method, §7.7 the code slot (Optional), §7.8 images and the machine-code cache), C-18 (the stopgap); facts §6.5 and a scope note in §2.2; traits §3.6, §6.7, §12, §14 and the status index; lowering §17's table of what removes each encoding.
- **Open issue 140** (mine, found while writing compiler §7.2): under explicit memberships, generic implementations and families over abstract types have no stated way to get their entries before the first call; three proposals.
- **The work items** W-97 to W-104 (one per stage); **the registry rows** E-260 (the C7 count re-run), E-261 (W-S0a), E-262 (the builds, the gates and Base's suites).
- **Alternatives** not taken, in `design/alternatives.md` ("The unified build: options not taken"); the evidence plan's order and the exploration's D1–D9 marked as replaced by the synthesis plan; the review marked acted on.
