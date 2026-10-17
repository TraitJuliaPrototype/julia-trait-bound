# Trait-bound Julia

A design for traits in Julia: abstract types with behaviour, so that library code compiled once for what its bounds can see is cached, never invalidated by unrelated loads, checked where it is defined, and closed for ahead-of-time compilation. Start with [`writeup/README.md`](writeup/README.md): the reading order, the decision register and the open issues.

**Resuming work:** read `writeup/README.md`, then `writeup/open-issues.md` §1 (decisions waiting for the user), then the "Next" list of the latest session note in `session-notes/`.

## This workspace

This directory is the design repository. Five repositories sit inside it, each with its own history, ignored by this one:

| Directory | Repository | What |
|---|---|---|
| `.` | design | `writeup/`: the notes, decisions, open issues, explorations, findings, research; `session-notes/`; `attic/` holds the earlier phases and superseded documents |
| `julia/` | patched Julia | a clone of JuliaLang/julia, checked out on branch `trait-universe` (1.12 with the filter, built in place). Branch `trait-world-1.13`: v1.13.2 with the invalidation filter (insertion half in `src/gf.c`, load half in `Compiler/src/reinfer.jl`), notes in `TRAITWORLD.md` |
| `julia-1.13/` | (worktree of `julia/`) | branch `trait-world-1.13`, built: `julia-1.13/julia` is the patched 1.13.2 with Julia pieces 1–5 and 9–10 (session 25); `tw-build.sh` rebuilds it niced under a memory watchdog |
| `TraitWorld/` | TraitWorld | the design as a package on Julia 1.13.2, stock and patched: traits, conformances as methods, keys, inlined entries and workers per key, the compiler policy of wrapping by facts, strict mode (a prototype), checks, definition checking, dynamic values, view caches, `verify_main`; 343 tests |
| `TraitDifferentialEquations/` | demonstrator 1 | ODE solvers in the trait world: step 1 (Tsit5, models, callbacks); plan and measurements in its README |
| `TraitMakie/` | demonstrator 2 | a plotting library in the trait world: step 1 (lines, scatter, Cairo); plan and measurements in its README |
| `experiments/` | experiments | the smaller prototypes and measurements, formerly `poc/`: `baseline-1.13.md`, `lens/` (layouts), `keys-proto/` (the runtime as methods), `world/`, `interfaces/` (pinned before keys), `solvers/`, `errors/`, `runtime-injection/`, `facts/` (wrapping by facts: acceptance, hunt, g2all, g2strict, typedbench), `aot/` (trimmed binaries on 1.13) |

These repositories have no remotes yet. Turning them into submodules of this one is a step for when they do.

## The plan

The aim now is to demonstrate that the trait world is viable: that large libraries written in it get the pay-offs, measured against their stock versions and against the same code without traits. Code written without traits is used directly, by **wrapping by facts** (adopted in session 23, validated in session 24: `writeup/explorations/wrapping-by-facts.md`); a **strict mode** for pirates is kept as an option (`writeup/explorations/strict-mode.md`, session 25).

1. **TraitWorld at the current design,** for what a trait world needs (not wrapping or sealing), in the order TraitDifferentialEquations needs it. Each feature gets small solver-shaped acceptance tests.
   1. `Dynamic{X}` (done);
   2. trait fields as properties, writable unless `@const` (done);
   3. associated types: defining equations, fields that define parameters, bounds, family conformances, parameter archetypes in definition checking (done; matching patterns such as `data::Vector{T}` not yet);
   4. results like the input: constructor operations returning `Self`, `Like{t}`, `withfields` (done);
   5. printing by bound and key, `conforms(T, X)` (done);
   6. keys (done: the reference layout, no implementing type under defaults, late overrides refused at checkpoints, fields matching parameters, immutable types held);
   7. the runtime as methods (done in session 23: typed calls 33 ns against 30 ns plain);
   8. a pinned dynamic mode for models, when the solver needs it.

   Two parts of the design need the language and are approximated in the package: membership as subtyping (an explicit `conforms(T, X)`), and a trait name in a field meaning its `Dynamic` (field types rewritten inside `@trait_module` only). Design: `writeup/notes/4-details.md`.
2. **Julia 1.13.2.** TraitWorld's tests pass on stock 1.13.2 and on the patched build (`julia-1.13/`, built in session 23). The measurements are re-baselined there (`experiments/baseline-1.13.md`). Reasons and porting costs: `writeup/explorations/runtime.md`.
3. **TraitDifferentialEquations:** Tsit5, then Rodas5 with automatic differentiation, user models and callbacks, against stock SciML and a plain-Julia copy. Thirteen measurements, in its README. Step 1 done (session 23).
4. **TraitMakie:** PlotCore with a Cairo backend, against Makie, a plain-Julia copy and matplotlib. Ten measurements, in its README. Step 1 done (session 23).
5. **Upstream proposals,** backed by the demonstrators' numbers (`writeup/explorations/julia-support.md`, reviewed in session 25):
   - first, "first-class foreign cache owners": native code for an `AbstractInterpreter`'s CodeInstances in package images, owner-aware bare edges, the inliner bug, compiling a call under an owner from inference (1.13's declared `CompilerPlugins` hook), a frozen world for the interpreter's compiler, instrumentation;
   - then the method-definition hook;
   - traits in the type system last.

## Conventions

- Session notes in `session-notes/` record each working session.
- The design notes are edited locally; the earlier live document (a Claude Doc) is frozen at revision 1146, and its export is `attic/writeup/traits-for-better-julia.md`.
- Decisions are recorded in `writeup/decisions.md` and open questions in `writeup/open-issues.md`; keep both current when the design changes.
- The machine is shared: one Julia job at a time, niced; full builds alone, under a memory guard.
