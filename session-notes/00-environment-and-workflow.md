# Environment and basic workflow

*Standing reference, read this first when picking up the project. Rewritten 2026-10-14 for the current layout; the environment facts were verified 2026-08-09 and 2026-10-13.*

## Project

A trait system for Julia, designed in the note "Traits for better Julia" (a Claude Doc, https://claude.ai/code/artifact/4f98f689-d7c8-4487-a92b-282a77417d20; local copy `writeup/traits-for-better-julia.md`, rev 1022) and prototyped on stock Julia. Read in this order:

1. `writeup/traits-for-better-julia.md`, the design.
2. `writeup/design-findings.md`, measurements, proof-of-concept results and the long tables.
3. `writeup/poc3-plan.md`, the plan being executed: interface packages around DataFrames.jl and Makie.jl, two demonstrations (interactive session, AOT), milestones M0–M9.
4. The latest dated session note.

## Layout

| Path | What |
|---|---|
| `TraitWorld/` | the current package: traits, implementations, trait modules, entries and workers, checks, audit, concrete mode, `verify_main`; since session 18 also keyword/default/vararg arguments, Callable modes, the one-line conformance, interface packages (`interface.jl`), the door check (`doors.jl`) and sealing (`sealing.jl`); 186 tests |
| `poc/world/` | the proof of concept of the note at rev 105 on TraitWorld: Columns, Stats, UserTypes, BaseTraits, Pirate, App, the M1–M7 scripts, the trimmed binary (`trim/`), and `README.md` with all results |
| `poc/interfaces/` | the current proof of concept (`writeup/poc3-plan.md`): Reports, DataFramesInterface, MakieInterface, App, Pipeline, the adversaries, the demo scripts, `build/`; results in its `README.md` |
| `writeup/` | the note's local copy, the findings, the plans (`poc2-plan.md` is TraitWorld's architecture plan, done; `poc3-plan.md` is current) |
| `session-notes/` | this file and one dated note per session |
| `attic/` | the earlier design (TraitRegions, the ecosystem PoC, the patched Julia, spikes, reviews), kept for reference; see `attic/README.md`. Paths in documents written before 2026-10-14 map to `attic/<same path>` |

## Environment (verified)

- Julia via **juliaup** at `/home/hellmann/.juliaup/bin/julia`. Default channel **1.12.2**; also installed 1.10.0, 1.10.2, 1.11.0, 1.11.7, release (1.12.3). TraitWorld and `poc/world` run on 1.12.2; `juliac` is at `$(Sys.BINDIR)/../share/julia/juliac/juliac.jl` (see `poc/world/trim/build.sh`). The August measurements were made on 1.11.7 (attic). Julia 1.13.1 is published but `juliaup add 1.13.1` failed twice on 2026-10-14 (download reset); the only simplification it would bring is one global method table for the sealing scan (session 18).
- Depot `/home/hellmann/.julia`, writable. DataFrames, CSV, CairoMakie, Makie and Tables are in the depot already (several versions); `poc/interfaces/env` pins the ones it uses at M0.
- **Network works** from the sandbox: pkg.julialang.org reachable, `Pkg.add` verified.
- A Julia MCP server may appear in some sessions; do not rely on it. Run Julia via Bash.

## Quick start (verified 2026-10-14)

    julia +1.12.2 --startup-file=no --project=TraitWorld -e 'using Pkg; Pkg.test()'   # 186 tests, about three minutes
    julia +1.12.2 --startup-file=no --project=poc/world/env poc/world/m1run.jl        # the note's example on TraitWorld

The interfaces proof of concept (`writeup/poc3-plan.md`): M0–M8 done and
measured (sessions 18–20), results in `poc/interfaces/README.md` and `writeup/design-findings.md` §13; the
untrimmed juliac build of `App` did not fit in the free memory (session note
20). M9 done: the Fable review is folded in, the note updated to rev 1022; two design
questions were decided or explained in the note at rev 1022; who names a split package's implementations stays open (session note 20). Record results in `poc/interfaces/README.md` and a dated
session note.

## Basic workflow

1. Read this file, then the latest dated session note.
2. Run Julia from Bash: `julia --project=<dir> -e '...'` or `julia --project=<dir> script.jl`, with absolute paths (the shell's cwd resets between calls). Claude Code's Bash sandbox allows writes to the depot `~/.julia` since 2026-10-14 (`sandbox.filesystem.allowWrite` in the user settings; before that, `Pkg.test` and precompilation failed with EROFS inside the sandbox).
3. Measurements are standalone `julia --project` scripts, one fresh process per mode, so compile-time numbers stay clean. `--trace-compile` and `@snoop_invalidations` through the harness `attic/poc/verifymain/observe.jl`, ported as TraitWorld's measurements use it.
4. Packages live in this repository and are developed into environments by path (`Pkg.develop(path=...)`).
5. Throwaway scripts and environments go in the session scratchpad, not the repository.
6. **The machine is shared with other simulations** (30 GB, 16 cores). One heavy Julia job at a time, never parallel chains; `JULIA_NUM_PRECOMPILE_TASKS=4` and `nice -n 10`; a juliac build of anything containing Makie only alone and under a memory watchdog (kill below about 4 GB `MemAvailable`). A parallel chain took the machine down on 2026-10-15 (session note 20).
7. The design lives in the note; findings that change the design go into the note first, then into `writeup/design-findings.md`; the session note records what was decided and why. Refresh `writeup/traits-for-better-julia.md` from the note when the note changes.
8. At the end of a work chunk, update the dated session note: intent, done, next.

## Session notes

| Note | One line |
|---|---|
| `2026-08-09-01-setup.md` | 2026-08-09 — Session 01: setup and sandbox verification |
| `2026-08-09-02-plan.md` | 2026-08-09 — Session 02: mandate, plan assessment, start of implementation |
| `2026-08-09-03-m0-results.md` | 2026-08-09 — Session 03: M0 spike results — ALL GATES PASS, go for M1 |
| `2026-08-09-04-m1-traitregions.md` | 2026-08-09 — Session 04: M1 — TraitRegions.jl macro package, working |
| `2026-08-09-05-ecosystem-poc-sketch.md` | 2026-08-09 — Session 05: sketch for the multi-package ecosystem PoC |
| `2026-08-09-06-ecosystem-results.md` | 2026-08-09 — Session 06: ecosystem PoC built and measured (X1–X7) |
| `2026-08-09-07-scaling-up-assessment.md` | 2026-08-09 — Session 07: scaling-up assessment (user question) |
| `2026-08-09-08-critical-review.md` | 2026-08-09 — Session 08: independent critical review (subagent, verbatim summary) |
| `2026-08-09-09-rung3-binary-sketch.md` | 2026-08-09 — Session 09: sketch — PoC Julia binary with full Rung-3 support |
| `2026-10-13-10-poc-error-split.md` | 2026-10-13 — Session 10: design rewrite, two reviews, Stage-1 PoC (error split) |
| `2026-10-13-11-verify-main.md` | 2026-10-13 — Session 11: verified mains and compiled binaries |
| `2026-10-13-12-concrete-mode.md` | 2026-10-13 — Session 12: design reset (closure rule), concrete mode |
| `2026-10-13-13-representation-parameter.md` | 2026-10-13 — Session 13: the representation as a trait parameter |
| `2026-10-13-14-layering-and-existing-julia.md` | 2026-10-13 — Session 14: layering, seven rules, working with existing Julia |
| `2026-10-13-15-traitworld.md` | 2026-10-13 — Session 15: TraitWorld, the proof of concept of the new design |
| `2026-10-14-16-adherence-and-module-structure.md` | 2026-10-14 — Session 16: conformance by field or methods; exported and internal functions; linked representations; parametric types; keywords |
| `2026-10-14-17-fable-review-of-note-rev1010.md` | 2026-10-14 — Session 17: Fable review of the note at rev 1010 (16 findings, folded in at rev 1019) |
| `2026-10-14-18-poc3-review-and-m1-m4.md` | 2026-10-14 — Session 18: review of the note (rev 1019) and the PoC plan, no blockers, six corrections; M0 environment, M1, M2, M4 and the M3 machinery on TraitWorld |
| `2026-10-14-19-poc3-m3-packages.md` | 2026-10-14 — Session 19: review of session 18 (one bug: interface registration lost at precompile), the M3 packages written and run, demo 1 steps 1–3 once; finding: an error path gave every entry an inference edge that `using DataFrames` invalidated (fixed with barriers); the audit's `Base._which` recompile (prepared) |
| `2026-10-15-20-crash-recovery-and-m8.md` | 2026-10-15 — Session 20: recovery after the machine crashed (memory, parallel jobs); session 19's unrecorded work reconstructed; an uncached ownership lookup made sealing 7× slower (fixed); the tolerations lists; the trimmed pipeline runs (3.53 MB, 39 warnings); the full build does not fit in the free memory; M9: design-findings §13 and a Fable review (18 items; the scan via the global method table; the implementer exemptions hide 1042 of 1091 pirates, open for the design) |
