# Trait-bound Julia

A design for traits in Julia, built as a patched Julia compiler and a package. Traits are abstract types with behaviour. Library code bounded by traits is compiled for what its bounds can see, checked where it is written, and never invalidated by an unrelated package's load. The facts mode in Julia's compiler gives that last guarantee to any code; traits make it cheap.

## Where to start

| You are | Read |
|---|---|
| a Julia programmer | [`writeup/intro/traits-for-julia.md`](writeup/intro/traits-for-julia.md), then [`writeup/intro/results.md`](writeup/intro/results.md); porting a package: [`writeup/intro/porting.md`](writeup/intro/porting.md) |
| a core developer | [`writeup/design.md`](writeup/design.md), the source of truth; its companions in [`writeup/design/`](writeup/design/): the mechanisms, the changes to Julia, the evidence, the performance work, the comparison with other languages |
| an agent resuming work | [`writeup/record/INDEX.md`](writeup/record/INDEX.md), then `writeup/design.md`, `writeup/open-issues.md` §1, and the last bullets of the latest note in `session-notes/` |

## This workspace

This directory is the design repository. Eight repositories sit inside it, each with its own history, ignored by this one:

| Directory | Repository | What |
|---|---|---|
| `.` | design | `writeup/` (the design, its companions, the introduction, the record), `session-notes/` (one note per working session), `attic/` (earlier phases and superseded documents) |
| `julia/`, `julia-1.13/` | patched Julia | a clone of JuliaLang/julia; `julia-1.13/` is a worktree on branch `trait-world-1.13`: v1.13.2 with the facts compiler, parts (A)–(D) and the session-29 changes ([`writeup/design/julia-changes.md`](writeup/design/julia-changes.md)). `julia-1.13/tw-build.sh` rebuilds it, niced, under a memory watchdog |
| `TraitWorld/` | TraitWorld | the design as a package on the patched build (stock Julia is not supported): traits, conformances as methods, keys, entries and workers, `Dynamic`, `Callable`, definition checking, concrete mode and the fully-typed certificate, strict mode, `verify_main`, printing |
| `TraitDifferentialEquations/` | demonstrator | ODE solvers in the trait world: Tsit5, Rodas5, model types, callbacks, gradients; the plain baseline `PlainODE` |
| `TraitMakie/` | demonstrator | a plotting library in the trait world; the plain baseline `PlainPlots` |
| `TraitTables/`, `TraitCSV/` | demonstrator libraries | a column table (`Vector{Dynamic{Column}}`) and a CSV reader whose column types are conformances |
| `TraitReport/` | demonstrator | a data report in a fresh session, against pandas and against the same libraries without traits |
| `forks/` | demonstrator | CSV, DataFrames and Tables ported to traits, against upstream, with the upstream test suites |
| `experiments/` | experiments | the smaller prototypes and measurements: `facts/` (acceptance, the framing cases), `factscompiler/` (the compiler's measurements, the control), `examples/` (worked examples for each rule), and earlier phases ([`writeup/record/INDEX.md`](writeup/record/INDEX.md) lists them) |

These repositories have no remotes yet.

## Conventions

- One note per working session in `session-notes/`; decisions in `writeup/decisions.md`, open questions in `writeup/open-issues.md`, kept current when the design changes.
- Writing: short sentences, bullets for anything with more than two parts, one idea per sentence, no unexplained jargon.
- The machine is shared: one Julia job at a time (`flock /tmp/claude-1000/julia-review.lock`), niced; full builds alone, under a memory guard.
