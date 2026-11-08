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
