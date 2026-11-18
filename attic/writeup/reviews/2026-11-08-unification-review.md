# Review: the unification as built, and the night of 2026-11-07/08 (2026-11-08)

The user (2026-11-08): "We have built a new version of our trait design, called unification. Check what's been done last night. Review the whole thing. Then compare the speed of the new version to the final speed that the previous version achieved. Then come up with a plan to reach Python speed."

Done in the main session, by the standing rule of no subagents on the shared host. The speed comparison is E-289 (with E-290 and E-291); the plan is [`plans/2026-11-08-python-speed.md`](../plans/2026-11-08-python-speed.md).

**What was read:**
- last night's session note, commits and records;
- yesterday's two reviews and what was done with them;
- the compiler reference's §4, §5, §6.2–§6.3, §9 and §10, and its Deviations table;
- open issues 157–159 and §1's choices;
- the walk and the activation in the runtime (`src/gf.c` 4401–4782, `src/datatype.c` 380–436);
- the state, the evidence, the work queue and the experiments registry.

**Not read line by line:** the rest of the 53-commit stack (8,103 lines), TraitWorld-unified's source, and the ports' code. Measured: E-289, E-290, E-291.

## What was done last night

- **W-104, the ports:** every port runs on the unified build with upstream's or the earlier build's results:
  - the forks' upstream suites: Tables passes; CSV fails 6 of 330,545 and DataFrames 4, both recorded as open issue 158;
  - slice 3: TraitDifferentialEquations (32 testsets, 3 checks broken by C-54) and NetworkDynamics (its test subset, and the workload's 32 digests).
- **Runtime:**
  - C-32 (a set's inputs);
  - the slot's last resort (yesterday's H1);
  - the Callable/kind fix;
  - C-70 and C-71 recorded.
- **Library:** fixes found by the ports (classification, a family's variables in scope, checks of an image's pattern members).
- **Open issues 157–159,** each with the case, the rule and proposals.
- **W-122:** `state.md` rewritten for the unified build.
- **W-121 begun:**
  - the hooks precompiled (TraitWorld e967ca0, TraitReport (t) 4.9 → 3.2 s);
  - the walk named as the load's cost (E-286, E-287);
  - the goal's task measured on the unified build, 26.4–27.0 s against Python's 0.65 s (E-288).

## Findings, by severity

### H1. The unified build's 7–11× loss is a cost bug in the walk at activation, not the design — measured (E-290)

- E-290 profiles DataFrames' load and splits the walk's samples by part:
  - the walk is 92.6 % of the load;
  - **96 % of the walk is its conservative pass;**
  - the cache tail is 0.2 % (my hypothesis before the profile, wrong).
- The conservative pass is documented in the code as "rare shapes only". It is taken whenever `membership_subst_sig` cannot substitute the member, and that includes **every method at a parametric set whose parameter is a method variable** (`f(c::TextColumn{T}) where T`: `jl_has_free_typevars(uw)`, then "a different instance of the family: conservative"). That is the normal shape of `Column{T}`, `Iterable{T}` and `Indexable{T}`.
- The pass then does two things, once for each replayed method:
  - it visits `mt->defs` and asks every ground specialization whether the replayed method matches it through the membership; since Julia 1.12 there is one global method table, so this is every method of every function;
  - it lowers every live method-cache entry of the session (`invalidate_all_mt_cache`).
- DataFrames' load replays 836 methods, so the session's specializations are visited 836 times.
- The reference (§5.5) asks for the entries whose selected method changes: recorded as **compiler C-72**.
- **Recommendation:** the plan's stage 1:
  - visit by intersection with the replayed method's function, which is exact;
  - substitute at a parametric set by binding its variables from the member's instance.

  The gates of the walk and a case for a parametric set replayed at a member check both.
- **Process:** no gate or experiment measured activation's cost before the ports. The reference's §9 says only that activation runs "for each as at a declaration". It should state the bound: in proportion to what a membership can change, not to the session.

### H2. The design's headline for SciML is lost on the unified build: new functions recompile — measured (E-289; the logs of W-104)

- **Setting D** on the unified build:
  - the first solve takes 2.80 s, all compiling, against the earlier build's 0.19 s;
  - a second model takes 0.79 against 0.053–0.06 s.
- **NetworkDynamics' new equations** (`changed` b–e) take 9.02 against 1.10 s, 1.54 s of it compiled again. The earlier build's result was 14× faster than upstream there (E-250).
- `state.md` said "the work after loading is fast". That holds for the forks' steps (2.24 against 2.81 s) and not here.
- The likely cause is C-54: the default `Dynamic` is not reached at `ODEProblem(f::Callable{RHSSig{P, T}, Nothing}, u0::AbstractVector{T}, …)`, so the solver compiles per function. Not yet shown.
- NetworkDynamics' recompilation (none on the earlier build) has no candidate yet.
- **Recommendation:** the plan's stage 2.1:
  - a probe with a `with_dynamic` cast at the call (minutes);
  - then §6.2's "once" built for `X{T}`.

  And stage 2.3: the invalidation log of NetworkDynamics' session. `state.md` is corrected (done with this review).

### H3. P-23 makes `compiled_for` and `with_dynamic` reserved words for all code — verified (PlainODE fails to load)

- TraitDifferentialEquations' plain twin defines `compiled_for(f)`. On the unified build its precompilation fails: "syntax: "compiled_for" is a cast, reserved as ccall is".
- Every package or script that uses either name breaks, with or without traits. A new reserved word is a breaking change that upstream would not take, and the stack is meant to be proposable (W-19).
- **Recommendation:** casts recognized by their binding (`Core.compiled_for`), not by name; or macro forms. Recorded as **open issue 160**, listed in §1 (P-23 is mine).

### M1. "A membership invalidates nothing" is paid for in plain code's inference, and nobody counts it — reasoned, with open issue 158's cases

- Two costs reach code that never uses traits once the library is loaded:
  - every call that a later membership could change carries a guard, and its result joins the shadow's declared result (`Any` where none is declared);
  - every negative test at an open set stays unfolded.
- Open issue 158 shows both in upstream CSV and DataFrames: 144 bytes per cell read, and `@inferred` failing.
- E-282 measured wall time on Base's test files, not inference precision.
- There is no counter of guarded calls or refused negative folds.
- **Recommendation:** the counter first (the plan's stage 2.4), in the goal's session and the forks' suites. Then open issue 158's (a) with C-36. I agree with (a) as the open issue argues it. C-36 is needed for its second case either way.

### M2. The stack's own rule has slipped, and a binary named a commit it was not built from — verified

- **The rule:** julia-changes §7.1 says "a stage's rework replaces its commits instead of adding fixes on top". The code slot is now four commits interleaved with W-104's (7500630036, 67ba8105fb, f90d152208, 49ab4294b6). They should be folded into one before any of W-19's proposals.
- **The binary:** `julia-unified/usr/bin/julia` reports `9dab7b6983*`, while the logs name `350c5b1c59`. It was built from the uncommitted tree (01:39–01:52) that became 49ab4294b6 and 350c5b1c59 (committed at 01:58). Every changed source predates the build, so the content is the same, but a log line `V julia …` names the wrong commit.
- **Recommendation:** commit, then build.

### M3. The walk runs under the world counter's lock — verified (`jl_memberships_activated`)

- Activation runs the walk, the cells and the ambiguity report for every entry while the lock is held. So for DataFrames' 20 s, no other thread can define a method or load a package.
- Stage 1 shortens it. A cost bound in §9 (H1) keeps it short.

### M4. Measurement harnesses — verified

- E-288's loop for form (f) was not committed: only its log was. E-289's `run.sh` now has form (f).
- `forks/scripts/measure_session.sh` does not check that the steps succeeded. `forks/data`, generated and not committed, did not exist on this host, so E-289's first earlier-build and pandas runs read a missing file and timed errors. They are kept as `*-INVALID-nodata.log` and were run again.
- The same script unsets `JULIA_DEPOT_PATH`, so it uses the home depot. That is against setup.md's depot inside the workspace on the shared host.

### M5. The record — verified

- E-284 to E-288 had 3 cells in the registry's 6-column table: split, done with this review.
- The compiler reference's Deviations header was three commits behind, and the references' README "State of the build" named TraitWorld e7ff8e2, the first slice: both brought to today, done with this review.
- Two logs in `experiments/` were untracked (`unification/workloads/logs/w104b-*.log`).
- The design repository does not ignore the `-unified` worktrees. Its `git status` lists seven untracked directories, among them a core file.
- The core files are still on disk: `core-login02-842363` (5.9 GB, the Claude Code extension's process, 2026-11-07 17:00) at the root, and `TraitWorld-unified/core-login02-3042057` (1.1 GB). Yesterday's review asked for them to go (L7); the session left them for the user.
- `src/datatype.c`'s comments name the walk "compiler C-18", which is retired.

### L1. Setting D's results differ from E-242's in the fifth digit — measured, not explained

- Lorenz gives `-9.40845` against `-9.40841`, and the PNGs differ by a few dozen bytes.
- E-242 ran TDE 388cb33. The unified port branches from e9e07ed, which changed Tsit5's interpolant (W-96). This is likely, not checked on the earlier build at e9e07ed.

### L2. The code slot has kept nothing in any measured session — recorded (E-283), still open (W-119)

- The slot carries much of the stack's newest complexity, and three review rounds have found fixes in it.
- Its counters belong in the plan's stage 2 runs. If the ports' sessions show no CodeInstance kept, E-283's criterion for narrowing it applies.

## What holds up

- **The unification's shape:**
  - one relation answers `<:`, `isa`, intersection and dispatch;
  - the second owner, `Kept{X}` and the facts copies of Base are gone;
  - the library shrank from 13,565 to 3,803 lines while the Julia patch grew from 2,458 to 8,103 lines.
- **After the imports, the unified build is faster in the forks' session:** 2.24 against 2.81 s on the same host. The read is 0.39 against 0.59 s, the join 0.075 against 0.25 s.
- **Every port runs with upstream's or the earlier build's results,** and the battery passes (state §4).
- **Last night followed the record's rules:**
  - each finding became a deviation row or an open issue with the case, the rule and proposals;
  - the choices marked mine are logged and listed for the user;
  - yesterday's review was acted on: H1 in 49ab4294b6; H2, M3, L1 and L2 in f90d152208; M2's gate case; M4 in W-122.
- **The hooks' fix** (e967ca0) was found by a profile and measured before and after (E-286).

## Recommendations, in order

1. The plan's stage 1, C-72 (H1): a bug fix under W-121's rule.
2. The C-54 probe, then C-54 (H2); NetworkDynamics' invalidation log.
3. Open issue 160 for the user (H3); the guard counter (M1).
4. Fold the slot's commits; commit before building (M2).
5. A data check in `measure_session.sh`; commit E-289's harness (M4). The rest of M5: the logs, `.gitignore`, the core files (the user's call).
