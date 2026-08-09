# Environment and basic workflow

*Standing reference — read this first when picking up the project. Verified 2026-08-09.*

## Project

Proof of concept for **trait-bounded Julia** ("TraitRegions.jl"). Read `Background/` before doing anything:

- `Background/trait_regions_design_sharpened.md` — the design: three-rung ladder (macro prototype → sealed-interpreter spike → language extension), the shared design core (seals, workers, witness tables), the closure rule, relation to JuliaLang/julia#54903.
- `Background/trait_regions_prototype_plan.md` — the implementation plan we are executing: claims C1–C5, architecture (~700–1000 LOC core), demo package `ColStats`, experiments E1–E6, milestones M0–M4.

## Environment (verified)

- Julia via **juliaup** at `/home/hellmann/.juliaup/bin/julia`. Default channel: **1.12.2**.
  Also installed: 1.10.0, 1.10.2, 1.11.0, 1.11.7, release (1.12.3).
  **Version policy (settled)**: all measurements were made on `julia +1.11.7`;
  TraitRegions tests pass unchanged on 1.11.7 AND 1.12.2; the Rung-2 sealed
  interpreter (`rung2/`) is **1.12-only** (Compiler stdlib). Note the
  ecosystem/scripts Manifest was instantiated under 1.11 — running those
  scripts under 1.12 requires re-instantiation (slow: Makie).
- Depot: `/home/hellmann/.julia` (writable from the sandbox).
- **Network works** in the sandbox: pkg.julialang.org reachable, `Pkg.add` verified end-to-end (FunctionWrappers v1.1.3 installed into a scratch env without prompts).
- A Julia MCP server (`mcp__julia__julia_eval` etc.) exists in this setup but was **disconnected** in the first session — do not rely on it; run Julia via Bash instead. If it is connected in a future session it gives a persistent REPL, which is nicer for iterative work.

## Basic workflow

1. Read `session-notes/` (this file, then the latest dated note) to pick up the thread.
2. Run Julia from Bash: `julia --project=<dir> -e '...'` or `julia --project=<dir> script.jl`.
   - Per the plan (§5), each experiment is a **standalone `julia --project` script** so compile-time measurement stays clean — don't run experiments in a reused session.
   - Shell cwd resets between Bash calls; prefer absolute paths or `--project=` with absolute paths.
3. Package development: the package will live in this repo (e.g. `TraitRegions/` with `Project.toml`); dev it into experiment environments with `Pkg.develop(path=...)`.
4. Throwaway scripts/envs go in the session scratchpad (path printed in the Claude session env), not the repo.
5. At the end of a work chunk, update the dated session note: what was done, what's next, any surprises.

## Session notes convention

- `00-environment-and-workflow.md` — this file, standing reference; update when the environment or workflow changes.
- `YYYY-MM-DD-NN-<topic>.md` — one per session, in order: **intent** (what I'm about to do), **done** (what actually happened), **next** (where to pick up).
