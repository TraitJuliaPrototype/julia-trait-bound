# attic/ — the earlier design's work, kept for reference

Moved here on 2026-10-14, when the design note reached rev 1010 and the
next proof of concept (`writeup/poc3-plan.md`) was planned on top of
TraitWorld. Everything here mirrors the layout it had at the repository
root, so relative paths inside it (Manifests, scripts) still work, and
paths cited in session notes and in `writeup/design-findings.md` written
before this date map to `attic/<same path>`.

| Directory | What it was |
|---|---|
| `Background/` | the TraitRegions design and its prototype plan (August 2026) |
| `TraitRegions/` | the first package: regions, seals, witness tables; the reference implementation of the earlier design, with its tests and `observe.jl` harness |
| `ecosystem/` | the nine-package ecosystem proof of concept on TraitRegions (ColTables, ColStats, ColPlots with CairoMakie, conformers, ChurnStorm, PlainStack) and the X1–X8 measurement scripts; sources for the ports planned in `writeup/poc3-plan.md` §6 |
| `poc/concrete`, `poc/errorsplit`, `poc/reprparam`, `poc/verifymain` | the October experiments on TraitRegions (sessions 10–13), all since ported to TraitWorld (`poc/world`) |
| `binary/` | the patched Julia 1.12.2 (universe filter in `gf.c`), its tests and the questions for core developers. Not revived: the rev-1010 design refuses pirates at load and needs no sealed resolution; the runtime change it wants instead is a hook on method insertion. `binary/julia/` is an untracked clone with a build inside (2.3 GB) |
| `rung2/` | the sealed-interpreter spike |
| `spike/` | the M0 spikes |
| `reviews/` | the August architect memo and the critical review of `binary/` |
| `writeup/trait_regions_discourse_draft.md` | the community write-up draft of the earlier design |
| `session-notes/design-observations.md` | the running log of design observations from the TraitRegions period |
