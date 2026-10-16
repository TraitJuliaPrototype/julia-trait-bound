# Trait-bound Julia

A design for traits in Julia: abstract types with behaviour, so that library code compiled once for what its bounds can see is cached, never invalidated by unrelated loads, checked where it is defined, and closed for ahead-of-time compilation. Start with [`writeup/README.md`](writeup/README.md): the reading order, the decision register and the open issues.

**Resuming work:** read `writeup/README.md`, then `writeup/open-issues.md` §1 (decisions waiting for the user), then the "Next" list of the latest session note in `session-notes/`.

## This workspace

This directory is the design repository. Five repositories sit inside it, each with its own history, ignored by this one:

| Directory | Repository | What |
|---|---|---|
| `.` | design | `writeup/`: the notes, decisions, open issues, explorations, findings, research; `session-notes/`; `attic/` holds the earlier phases and superseded documents |
| `julia/` | patched Julia | a clone of JuliaLang/julia. Branch `trait-world-1.13`: v1.13.2 with the invalidation filter (insertion half in `src/gf.c`, load half in `Compiler/src/reinfer.jl`), notes in `TRAITWORLD.md`, not built yet. Branch `trait-universe`: the same on 1.12, the current build |
| `TraitWorld/` | TraitWorld | the design as a package on stock Julia 1.13.2: traits, conformances, keys, entries and workers, checks, definition checking, dynamic values, sealing, view caches, `verify_main`; `main` at 3e4bd5a, 311 tests |
| `TraitDifferentialEquations/` | demonstrator 1 | ODE solvers in the trait world (skeleton; plan in its README) |
| `TraitMakie/` | demonstrator 2 | a plotting library in the trait world (skeleton; plan in its README) |
| `experiments/` | experiments | the smaller prototypes and measurements, formerly `poc/`: `baseline-1.13.md`, `lens/` (layouts), `keys-proto/` (the runtime as methods), `world/`, `interfaces/` (pinned before keys), `solvers/`, `errors/`, `runtime-injection/` |

These repositories have no remotes yet. Turning them into submodules of this one is a step for when they do.

## The plan

The aim now is to demonstrate that the trait world is viable: that large libraries written in it get the pay-offs, measured against their stock versions and against the same code without traits. Wrapping existing packages and sealing come later.

1. **TraitWorld at the current design,** for what a trait world needs (not wrapping or sealing), in the order TraitDifferentialEquations needs it. Each feature gets small solver-shaped acceptance tests.
   1. `Dynamic{X}` (done);
   2. trait fields as properties, writable unless `@const` (done);
   3. associated types: defining equations, fields that define parameters, bounds, family conformances, parameter archetypes in definition checking (done; matching patterns such as `data::Vector{T}` not yet);
   4. results like the input: constructor operations returning `Self`, `Like{t}`, `withfields` (done);
   5. printing by bound and key, `conforms(T, X)` (done);
   6. keys (done in the reference layout, a750ecd; not yet: no implementing type under defaults, refusing late overrides);
   7. **pending the user's decision:** the runtime as methods (`writeup/explorations/keys-plan.md` §6), which brings calls to plain-Julia speed;
   8. a pinned dynamic mode for models, when the solver needs it.

   Two parts of the design need the language and are approximated in the package: membership as subtyping (an explicit `conforms(T, X)`), and a trait name in a field meaning its `Dynamic` (field types rewritten inside `@trait_module` only). Design: `writeup/notes/4-details.md`.
2. **Julia 1.13.2, alongside.** TraitWorld's tests pass on stock 1.13.2. The measurements are re-baselined there (`experiments/baseline-1.13.md`), and the load filter is injected into stock Julia (`experiments/runtime-injection/`). The patched build (`julia/TRAITWORLD.md`) is postponed. Reasons and porting costs: `writeup/explorations/runtime.md`.
3. **TraitDifferentialEquations:** Tsit5, then Rodas5 with automatic differentiation, user models and callbacks, against stock SciML and a plain-Julia copy. Thirteen measurements, in its README.
4. **TraitMakie:** PlotCore with a Cairo backend, against Makie, a plain-Julia copy and matplotlib. Ten measurements, in its README.
5. **An upstream proposal** for the deep runtime pieces, backed by the demonstrators' numbers:
   - a dispatch check at dynamic sites;
   - trait-world code with machine code in package images;
   - a transactional image load.

**Later:** trait wrappers and sealing (`writeup/notes/3-wrapping.md`).

## Conventions

- Session notes in `session-notes/` record each working session.
- The design notes are edited locally; the earlier live document (a Claude Doc) is frozen at revision 1146, and its export is `attic/writeup/traits-for-better-julia.md`.
- Decisions are recorded in `writeup/decisions.md` and open questions in `writeup/open-issues.md`; keep both current when the design changes.
- The machine is shared: one Julia job at a time, niced; full builds alone, under a memory guard.
