# Environment and basic workflow

*Standing reference; read it first when picking up the project. Rewritten 2026-10-19 (session 29). The version of 2026-10-14 is `attic/session-notes/00-environment-and-workflow-2026-10-14.md`; its session table (sessions 01–20) is there, and [`../writeup/record/INDEX.md`](../writeup/record/INDEX.md) lists every session note.*

## Project

A design for traits in Julia, built as a patched Julia compiler (the facts compiler) and a package (TraitWorld), with demonstrators. Read in this order:
1. [`../writeup/record/INDEX.md`](../writeup/record/INDEX.md): the map of the record.
2. [`../writeup/design.md`](../writeup/design.md): the design, the source of truth.
3. [`../writeup/open-issues.md`](../writeup/open-issues.md) §1: decisions waiting for the user.
4. The latest session note, from its last bullets backwards (a "Next" section near the top of a long note can be done already).

## Layout

The root `README.md` has the table of repositories. In short:
- `julia-1.13/`: the patched Julia (worktree of `julia/`, branch `trait-world-1.13`, on v1.13.2);
- `TraitWorld/`: the package;
- the demonstrators: `TraitDifferentialEquations/`, `TraitMakie/`, `TraitTables/`, `TraitCSV/`, `TraitReport/`, `forks/`;
- `experiments/`: measurements and prototypes;
- `writeup/`: the design and the record;
- `session-notes/`: this file and one note per session;
- `attic/`: earlier phases.

## Environment (verified 2026-10-19)

- **The patched Julia:** `julia-1.13/julia`. TraitWorld and the demonstrators need it; stock Julia is not supported.
- **Stock Julia** for comparisons: `~/.julia/juliaup/julia-1.13.2+0.x64.linux.gnu/bin/julia`.
- **Depot** `~/.julia`, writable from the sandbox (`sandbox.filesystem.allowWrite`, since 2026-10-14). Run Julia with `JULIA_PKG_OFFLINE=true`.
- **The facts system image** (the `all` test bed): `julia-1.13/usr/lib/julia/facts/sys.so`, built by `experiments/factscompiler/scripts/build_facts_sysimage.sh`. Use it with a depot of its own first and `~/.julia` second: `JULIA_DEPOT_PATH=$TMPDIR/depot-facts:$HOME/.julia:`. A trailing colon alone adds only the bundled depots, and no package is found.
- **`ps` is blind in the sandbox:** background jobs are not visible; wait for task notifications.

## Basic workflow

**On the shared host** (since 2026-11-05) the standing constraints of [`../writeup/record/INDEX.md`](../writeup/record/INDEX.md) apply first: `source env.sh`; cores by load (a build may spike to half the cores while the others' load is below half; sustained use at most 16 cores in all; at or above half, 4 cores and one job at a time; `tools-local/build.sh`); no subagents. The list below is the project machine's workflow; where it names 16 cores, `/tmp/claude-1000` or `~/.julia`, the shared host uses `env.sh`'s settings.

1. **One Julia job at a time,** under the shared lock: `flock /tmp/claude-1000/julia-review.lock nice -n 10 …` (tests may use `nice -n 19`). The machine is shared with other simulations (30 GB, 16 cores); a parallel chain took it down on 2026-10-15. `JULIA_NUM_PRECOMPILE_TASKS=4`.
2. **Building Julia:** `julia-1.13/tw-build.sh` (niced, `-j4`, a memory watchdog), alone. Check `BUILD EXIT 0` at the end of `julia-1.13/tw-build.log`: a Julia-level error in the system image build leaves no crash message. Every package image is rebuilt afterwards, so first runs include precompilation.
3. **After a Julia change:** TraitWorld's suite, the acceptance suite (`experiments/facts/acceptance_compiler.jl`), the demonstrators' suites, the examples (`experiments/examples/run_all.sh`, which takes the lock itself). Scripts: `experiments/factscompiler/session29/scripts/` (`after_build.sh`, `demo_suites.sh`, `final_checks.sh`).
4. **Do not edit TraitWorld while a job loads it** from source against an older build.
5. **Measurements:** fresh processes, one per cell; state the run count; compare against the plain baseline of the same code. Keep scripts and logs in a repository (`/tmp` is not durable): `experiments/factscompiler/session29/` is the example.
6. **Fixes:** principled fixes that a future trait-world ecosystem would want, and Julia patches, over workarounds.
7. **Records:**
   - the design changes go into `writeup/design.md` (and its companions) and `writeup/decisions.md`;
   - open items into `writeup/open-issues.md`;
   - the session's log, with every number and commit, into its session note.

## The unified build's discipline (W-97 to W-104)

From [the synthesis plan](../writeup/plans/2026-11-05-unification-synthesis.md) §6, as adopted on 2026-11-06, with no subagents on the shared host:
- **One session does every role:** a per-site edit plan checked against the tree, the change, and a review of the diff. A review is backed by probes run on the built branch (`experiments/unification/audit/probes.jl` is the pattern), not by the author's reasoning.
- **The tree is never the only copy:** each day's work is committed on the stage's branch of the julia repository (`unified`). Gates, probes and acceptance cases live in `experiments/unification/`, not beside a worktree.
- **Every full build records its stages:** `tools-local/build.sh` time-stamps the log; Base, `Base.Compiler` and the system image's times go into the stage's registry row. A build that takes twice a stage's recorded time is stopped and bisected one build at a time (`WIDE=0`). Staged system images are deleted after a change to a struct's layout.
- **The record is the home:** numbers in the registry with their build, decisions in the log, deviations in the references, the chronology in a session note.
- **The gates of a stage** are its `experiments/unification/gates/` files, Base's four test files against the vanilla control (`experiments/unification/e262_suites.sh`), and `detect_ambiguities(Base)`.
