# Trait-bound Julia

A design for traits in Julia: abstract types with behaviour, so that library code compiled for what its bounds can see is cached, never invalidated unless code it depends on changes, checked where it is defined, and closed for ahead-of-time compilation. Start with [`writeup/design.md`](writeup/design.md), the current design and its decisions; [`writeup/README.md`](writeup/README.md) has the reading order.

**Resuming work:** read `writeup/design.md`, then `writeup/open-issues.md` §1 (decisions waiting for the user), then the "Next" list of the latest session note in `session-notes/`.

## This workspace

This directory is the design repository. Eight repositories sit inside it, each with its own history, ignored by this one:

| Directory | Repository | What |
|---|---|---|
| `.` | design | `writeup/`: the notes, decisions, open issues, explorations, findings, research; `session-notes/`; `attic/` holds the earlier phases and superseded documents |
| `julia/` | patched Julia | a clone of JuliaLang/julia, checked out on branch `trait-universe` (1.12 with the filter, built in place). Branch `trait-world-1.13`: v1.13.2 with the invalidation filter (insertion half in `src/gf.c`, load half in `Compiler/src/reinfer.jl`), notes in `TRAITWORLD.md` |
| `julia-1.13/` | (worktree of `julia/`) | branch `trait-world-1.13`, built: `julia-1.13/julia` is the patched 1.13.2 with Julia pieces 1–5, 9, 10 and 17 (session 26); `tw-build.sh` rebuilds it niced under a memory watchdog (`TW_TARGET=julia-sysimg-release` for the system image alone) |
| `TraitWorld/` | TraitWorld | the design as a package on Julia 1.13.2, stock and patched: traits, conformances as methods, keys, inlined entries and workers per key, the compiler policy of wrapping by facts, strict mode (a prototype), checks, definition checking, dynamic values, view caches, `verify_main`; 350 tests patched, 306 stock |
| `TraitDifferentialEquations/` | demonstrator 1 | ODE solvers in the trait world: steps 1 and 3 (Tsit5, models, callbacks; Rodas5 with ForwardDiff); plan and measurements in its README |
| `TraitMakie/` | demonstrator 2 | a plotting library in the trait world: step 1 (lines, scatter, Cairo), a trimmed binary; plan and measurements in its README |
| `TraitTables/` | demonstrator 3, library | a DataFrame-shaped table in the trait world: `Column{T}`, `Vector{Dynamic{Column}}` columns (session 27) |
| `TraitCSV/` | demonstrator 3, library | a CSV reader in the trait world: `CSVColumn{T} <: Column`; InlineStrings' `String15` as a conformance in an extension (session 27) |
| `TraitReport/` | demonstrator 3 | a data report in a fresh session (CSV, DataFrames, TraitMakie) against pandas and matplotlib: the ordinary script, a trait-world report and a plain package as the fair baseline (session 26); next, TraitTables and TraitCSV; plan and measurements in its README |
| `experiments/` | experiments | the smaller prototypes and measurements, formerly `poc/`: `baseline-1.13.md`, `lens/` (layouts), `keys-proto/` (the runtime as methods), `world/`, `interfaces/` (pinned before keys), `solvers/`, `errors/`, `runtime-injection/`, `facts/` (wrapping by facts: acceptance, hunt, g2all, g2strict, typedbench), `aot/` (trimmed binaries on 1.13), `sysimage/` (the policy in the platform: TraitWorld in the system image), `demos/` (the demonstrators' rows) |

These repositories have no remotes yet. Turning them into submodules of this one is a step for when they do.

## The plan

The current design, its decisions and the order of work are in [`writeup/design.md`](writeup/design.md) (session 29). In short:
- **The framing:** compiled code is never invalidated unless code it depends on changes. Facts at concrete signatures, ownership, and the refusal of a winning pirate (strict mode) make it true; the default session follows pirates instead. Traits let code say what it needs, so it is compiled per key, checked where it is defined, and typed without speculation.
- **The platform:** the facts policy moves into Julia's compiler: (A) a facts mode of inference, (B) a second cache owner for trait code, (C) owner-aware dynamic dispatch, (D) the `Dynamic` call-site split. `--compile-by-facts=all` is a test bed. Stock Julia is not supported.

The order of work (`writeup/design.md` §9.3):
1. (A) in-tree in `julia-1.13/`, one copy of the fact rules; Base's tests in facts mode.
2. The decisive control: the plain baselines and upstream DataFrames under `all`.
3. (B) and (C) in Julia; delete TraitWorld's imitation of them.
4. `Dynamic` in the compiler (D).
5. The demonstrators' claims re-pointed; the notes rewritten for the strict-first framing.
6. Housekeeping; then the forks resumed; then the upstream proposals.

## Conventions

- Session notes in `session-notes/` record each working session.
- The design notes are edited locally; the earlier live document (a Claude Doc) is frozen at revision 1146, and its export is `attic/writeup/traits-for-better-julia.md`.
- Decisions are recorded in `writeup/decisions.md` and open questions in `writeup/open-issues.md`; keep both current when the design changes.
- The machine is shared: one Julia job at a time, niced; full builds alone, under a memory guard.
