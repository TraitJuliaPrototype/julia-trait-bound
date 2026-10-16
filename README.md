# Trait-bound Julia

A design for traits in Julia: abstract types with behaviour, so that library code compiled once per representation is cached, never invalidated by unrelated loads, checked where it is defined, and closed for ahead-of-time compilation. Start with the overview: [`writeup/notes/1-overview.md`](writeup/notes/1-overview.md).

## This workspace

This directory is the design repository. Five repositories sit inside it, each with its own history, ignored by this one:

| Directory | Repository | What |
|---|---|---|
| `.` | design | the notes (`writeup/notes/`), explorations (`writeup/explorations/`), findings, proposals, research, session notes; `attic/` holds the earlier phases |
| `julia/` | patched Julia | a clone of JuliaLang/julia. Branch `trait-world-1.13`: v1.13.2 with the invalidation filter (insertion half in `src/gf.c`, load half in `Compiler/src/reinfer.jl`), notes in `TRAITWORLD.md`, not built yet. Branch `trait-universe`: the same on 1.12, the current build |
| `TraitWorld/` | TraitWorld | the design as a package: traits, conformances, entries and workers, checks, definition checking, sealing, view caches, `verify_main` |
| `TraitDifferentialEquations/` | demonstrator 1 | ODE solvers in the trait world (skeleton; plan in its README) |
| `TraitMakie/` | demonstrator 2 | a plotting library in the trait world (skeleton; plan in its README) |
| `experiments/` | experiments | the smaller prototypes and measurements, formerly `poc/` |

These repositories have no remotes yet. Turning them into submodules of this one is a step for when they do.

## The plan

The aim now is to demonstrate that the trait world is viable: that large libraries written in it get the pay-offs, measured against their stock versions and against the same code without traits. Wrapping existing packages and sealing come later.

1. **Julia 1.13.2.**
   - Build the patched branch (`julia/TRAITWORLD.md`; a cold build needs the network and about an hour alone on the machine).
   - Move TraitWorld to 1.13, with the injected load filter as its mode on stock Julia (`experiments/runtime-injection/`).
   - Re-run its tests and re-baseline the measurements. Reasons and porting costs: `writeup/explorations/runtime.md`.
2. **TraitWorld features the demonstrators need,** each prototyped and measured. Design: `writeup/notes/4-details.md`.
   - `Dynamic{X}`;
   - trait fields as properties, and lenses;
   - associated types: output parameters, family conformances, bounds on parameters, archetypes for parameters (`writeup/explorations/associated-types.md`);
   - constructor operations and the conformance's inverse;
   - printing stack frames by bound and representation;
   - a pinned dynamic mode for models.
3. **TraitDifferentialEquations:** Tsit5, then Rodas5 with automatic differentiation, user models and callbacks, against stock SciML and a plain-Julia copy. Thirteen measurements, in its README.
4. **TraitMakie:** PlotCore with a Cairo backend, against Makie, a plain-Julia copy and matplotlib. Ten measurements, in its README.
5. **An upstream proposal** for the deep runtime pieces, backed by the demonstrators' numbers:
   - a dispatch check at dynamic sites;
   - trait-world code with machine code in package images;
   - a transactional image load.

**Later:** trait wrappers and sealing (`writeup/notes/3-wrapping.md`).

## Conventions

- Session notes in `session-notes/` record each working session.
- The design notes are edited locally; the earlier live document (a Claude Doc) is frozen at revision 1146, and its export is `writeup/traits-for-better-julia.md`.
- The machine is shared: one Julia job at a time, niced; full builds alone, under a memory guard.
