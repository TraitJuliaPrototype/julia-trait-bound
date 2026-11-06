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
- **The trees:** `julia-unified/` (branch `unified` at c3f0b4bc11, from `origin/oc-build`) and `julia-vanilla/` (detached at `45b6d15e34`), each with `julia-1.13`'s source cache copied in. `unified` built from 11:47 (load 5–7; at `-j4`, see below).
- **The decisions** 1–13 in the decision log §5, with the user's words.
- **The references' Planned sections:** compiler §7 rewritten as the unified build (§7.2 memberships, §7.3 one dispatch, §7.4 guards and cells, §7.5 keys, attributes and the check, §7.6 compiling by facts per method, §7.7 the code slot (Optional), §7.8 images and the machine-code cache), C-18 (the stopgap); facts §6.5 and a scope note in §2.2; traits §3.6, §6.7, §12, §14 and the status index; lowering §17's table of what removes each encoding.
- **Open issue 140** (mine, found while writing compiler §7.2): under explicit memberships, generic implementations and families over abstract types have no stated way to get their entries before the first call; three proposals.
- **The work items** W-97 to W-104 (one per stage); **the registry rows** E-260 (the C7 count re-run), E-261 (W-S0a), E-262 (the builds, the gates and Base's suites).
- **Alternatives** not taken, in `design/alternatives.md` ("The unified build: options not taken"); the evidence plan's order and the exploration's D1–D9 marked as replaced by the synthesis plan; the review marked acted on.
- **The build of `unified`** (11:47–12:01): `tools-local/build.sh` ran at `-j4`, not `-j64`: `nproc` honours `OMP_NUM_THREADS=1` from `env.sh`. And I edited the script while it ran, which garbled its last lines. Both fixed (`getconf`, and the script runs from a private copy). The binary runs (`1.13.2 c3f0b4bc11`).
- **The vanilla control** started 12:01:54 at `-j64` (load 8).
- **E-262 (2):** the 22 gates pass on `unified`.
- **The audit** ([`../writeup/reviews/2026-11-06-oc-build-audit.md`](../writeup/reviews/2026-11-06-oc-build-audit.md)), in the main session. Probes on the built branch show two high defects. A1: `@implement S X` makes `S isa X` true and calls a bounded method with the type object. A2: `Dynamic{X} <: X` holds, but a call with one reaches the fallback. Six medium: patterns beyond eight variables match nothing; the per-thread query world; the epoch and its cap of 32,767 sets; the single-path cycle check; the ambiguity report's arity; the chain composition. Recorded as compiler C-19 to C-25, and in W-98 and W-99.
- **E-262 done.** The control built in 790 s at `-j64`. Base's four test files pass on both builds; `unified` is 2–6 % slower, one run each; `detect_ambiguities(Base)` is 0 on both.
- **The environments** for E-260 and E-261 are being instantiated in the workspace depot (they never were on this host): `env_tables`, the forks', TDE's, Makie's, `TraitDifferentialEquations/scripts/env` and `TraitMakie/scripts/env` done by 12:16.

## The user reverses decision 4

> I have reconsidered explicit membership. It must be transitive. So A <: B <: C has to imply A <: C. I have never seen a type system that doesn't have that. We need to explicitly think about invariance, covariance and contravariance with respect to parameters. Does U <: V imply T{U} <: T{V} I lean towards: yes if all parameters satisfy it. This decision might simplify other aspects of the design, too.

- Transitivity recorded as in force: the decision log (the explicit row moved to the superseded section), compiler §7.2, traits §3.6 and §14, alternatives, C-22 restated, the audit's addendum (A8 reverses: the attempt's composition is kept and extended to `<:` and to supertype chains).
- Open issue 140 narrowed by it: generic implementations and families over abstract types become memberships of a set or an abstract type in a set. What remains is a family whose parameter an equation defines that is not a pattern.
- Variance written up as open issue 141. My proposal refines the user's lean: each parameter's variance is derived from the contract. Covariant where the contract only produces the parameter (where "yes" is sound); contravariant where it only consumes it (`Callable`'s arguments); invariant otherwise. The diagonal rule is the point to settle.
- Probe P7: the branch does not read entries along a member's supertype chain (`PS7 <: PAbs7`, `PAbs7` a member of `PX7`, but `!(PS7 <: PX7)`).
- **E-260 and E-261 done** (the environments installed 12:08–12:21, no errors). E-260 reproduces the attempt's C7 count exactly: decision 2 stands. E-261: the slot keeps 341 of 1,233 and 1,622 of 6,430 invalidated CodeInstances, and 67 of 120 and 91 of 100 facts callers of invalidated plain code. By decision 3's rule the slot is built (W-101); compiler §7.7 Planned; the decision log row marked mine.
- **W-97 done.** The build discipline is in `00-environment-and-workflow.md`. Nothing pushed: the commits of the design and experiments repositories are local, waiting for the user's word.
