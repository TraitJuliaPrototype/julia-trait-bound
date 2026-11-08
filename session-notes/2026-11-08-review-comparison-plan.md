# 2026-11-08, morning: the review of the unification, the comparison with the earlier build, the plan to reach Python's speed

## The user's words

- "We have built a new version of our trait design, called unification. Check what's been done last night. Review the whole thing. Then compare the speed of the new version to the final speed that the previous version achieved. Then come up with a plan to reach Python speed."
- During the runs: "If the source of differences between the previous and the new version is already clear, no need to run the old version again"
- Later: "If we are within Python + 1s that would be also fantastic. Python is aspirational rather than a strict goal."

## What was done

- **The night's work checked** (the session note `2026-11-08-w104-suites-c32.md`, the commits, the records): W-104 done, C-32, the slot's last resort, open issues 157–159, `state.md` rewritten, W-121 begun with E-286 to E-288.
- **The review** (main session, no subagents): [`writeup/reviews/2026-11-08-unification-review.md`](../writeup/reviews/2026-11-08-unification-review.md). H1 the walk's conservative pass (C-72), H2 the first calls of setting D and NetworkDynamics' new equations (C-54 likely), H3 the reserved cast names (open issue 160).
- **E-289, the comparison on the same host** (`experiments/unification/e289/`). After the user's word, the earlier build ran only for the goal's task (never run on it before) and the forks' session (its steps after the imports unexplained):
  - the goal's task: earlier 2.46–2.49 s, unified 27.1–27.4 s, Python 0.63–0.65 s;
  - the forks' session: earlier 5.06–5.07 s, unified 38.0–38.5 s (its steps faster: 2.24 against 2.81 s), pandas 0.69–0.75 s;
  - setting D on the unified build 11.6–11.8 s (the earlier 1.34–1.35 s, E-242);
  - from the records: TraitReport (t) 0.63 against 3.18–3.20 s; NetworkDynamics 31.3 against 100.4 s, new equations 1.10 against 9.02 s.
- **Two runs invalid:** `forks/data` did not exist on this host, so the earlier forks session and pandas timed errors after the read. Kept as `*-INVALID-nodata.log`, data copied from `forks-unified/data` (deterministic generator), run again. `measure_session.sh` now refuses to run without its data (forks and forks-unified).
- **E-290:** my guess before the profile was the walk's cache tail (a whole-cache visit per replayed method); the profile says the conservative pass, 96 % of the walk. It is taken for every method at a parametric set with a free parameter and visits every method of every function (Julia 1.12's single method table). Recorded as compiler C-72.
- **E-291:** a bare Julia process 0.15–0.18 s on every build, Python 0.02 s.
- **The plan:** [`writeup/plans/2026-11-08-python-speed.md`](../writeup/plans/2026-11-08-python-speed.md), a proposal, with the user's target of Python + 1 s (about 1.65 s for the goal's task). Stage 1 is C-72, a bug fix under W-121's own rule.
- **Found on the way:**
  - TDE's plain twin `PlainODE` does not load on the unified build (P-23 reserves `compiled_for`): open issue 160;
  - the binary in `julia-unified` reports `9dab7b6983*`, built from the tree that became 350c5b1c59 (all sources predate the build);
  - setting D's results differ from E-242's in Lorenz's fifth digit (TDE e9e07ed's interpolant, likely).
- **Record fixes:**
  - the registry's E-284 to E-288 split into six cells;
  - the compiler reference's Deviations header and the references' build summary brought to today;
  - `state.md`'s headline and §5 corrected ("the work after loading is fast" did not hold for setting D and NetworkDynamics);
  - the `-unified` worktrees ignored by the design repository.
- **Left for the user:** the core files `core-login02-842363` (5.9 GB, the Claude Code extension's process) and `TraitWorld-unified/core-login02-3042057` (1.1 GB).
- **Environments resolved on this host for the earlier build** (offline, julia-1.13): `TraitReport/env_t`, `env_pt`, `env_f`; `forks/env_forks` (home depot, as its script uses).

## Later the same morning: the plan adopted, stage 1

### The user's words

- "Specific precompile workloads, unless they genuinely cover broad typical cases (String, Int Columns) are cheating. The traits+facts mode should enable us to work with Compiled code like with precompiled libraries. That's where the expectation of speed comes from. Go for the plan."
- During the build: "One further note for the rules: Where a design decision makes speed difficult to achieve, flag that for me to review."

### What was done

- **Records:** the plan adopted (status, decisions §5, W-123 to W-127); stage 4 restricted to broad workloads; the user's two rules in CLAUDE.md (flag a design decision that makes speed hard; the target and workloads); the first flagged decision in open issues §1: "a membership invalidates nothing" with "negatives never fold" (open issue 158's costs, uncounted).
- **W-123, the walk (C-72), `unified` aa997b2180:** the conservative pass and the cache walks visit the replayed method's own function only (an intersection with `Tuple{F, Vararg{Any}}`); the member is substituted at a parametric set whose parameter is a method variable (or a variable bounded by the set); a method at other instances is not replayed. New gate `m2_parametric_replay` (passes). A check of the loads (`walk_stats.jl`, not a measurement): DataFrames 21 → 1.8 s, TraitWorld 0.86 → 0.10 s, CSV 2.8 → 1.7 s. The battery `w123` on it.
- **The next term, found by the profile after the fix:** CSV's load 75 % inference and compilation: `--trace-compile` shows 0.9 s compiling the native interpreter's `infercalls` closure and 0.26 s recompiling TraitWorld's two hooks. The invalidation log: loading TraitWorld invalidates 1,585 of the compiler's own instances, through `ClassifyInterp`'s methods of the compiler's functions (C-40, E-281). So C-40 moved into stage 1.
- **C-40, `unified` 98fcbdfbba and TraitWorld's `classify.jl`:** `Compiler.DefinitionCheckInterpreter`, the compiler's own interpreter of the definition-time check (an ephemeral cache, the library's hook called from `abstract_call_known` behind a test that folds for every other interpreter); the library keeps its recording logic in a state object and defines no method of the compiler's functions.
- **The binary of the first build** reports 350c5b1c59 (built before aa997b2180 was committed, from the same source); C-40's build is committed first.

## Afternoon: stage 1 continued, W-128 begun

### The user's words

- On the census of deviations, and the suggestion to build the correctness group and the speed-path group alongside stage 2: "Go ahead."

### What was done

- **E-292 to E-295** (registry rows): the compiler's own invalidations brought to vanilla's level (195 against 193) by narrowing the stack's compiler code (9d428d473b, 28d2334164); TraitWorld's hooks no longer invalidated by a plain package's `print` method (e6eaa85, typed triggers).
- **W-128, build B1** (`unified` 07c0bee2a2): C-73 (a method at a set re-guards a pruned arm at its insertion), C-71 (a failed member check lowers the entries made while it ran), C-35 (one instance per member through images). Gates `n11`, `n12`; TraitWorld test F10b.
- **E-296 on B1:** correct; the goal's task 3.62–3.70 s, setting D 6.35–6.56 s, TraitReport (t) 1.02–1.07 s. The forks' session slower, 9.9–10.4 s. Diagnosis (the logs are kept with E-296): at a REPL, CSV's load takes 5.4–5.8 s against 0.6 s. C-73's rule makes TraitWorld's methods at sets for required operations invalidate the system image's code with a pruned `Nothing` arm; TraitWorld's image carries replacements compiled at `::AbstractInterpreter`; REPL's interpreter methods reject them at load, and the rejection reaches TraitWorld's hook (5.3 s inferred again). The guard cells in the validation log were a red herring: the log names every edge of a rejected instance (fixed in the log).
- **Flagged** (open issues §1): the measured cost of the rule for pruned arms, the other side of "a membership invalidates nothing".
- **Open issue 158 (a), built as part of W-128 (mine):** `unified` 40401f67d8 reads a `serves_no_member` meta in a method's body before its insertion (bit 1 of `declared_covers`); such a method, like one declared `Union{}`, is no shadow. A declared result could not mark it: a required operation's method carries the result covering every member. TraitWorld marks the trait's method for a required operation and defines forwarding's methods at the member. `Dynamic{X}` stays served by the trait's method (it joins at the declaration, so the method still serves no type that joins later): fewer methods than the review's proposal, same effect.
- **Build B2** (1d493ca959 with 40401f67d8: C-54, C-60, C-46, the mark): E-297 registered, with a check of CSV's load after REPL's and TDE's suite.
