# Trait-bound Julia

A design for traits in Julia, built as a patched Julia compiler and a package. Traits are abstract types with behaviour. Library code bounded by traits is compiled for what its bounds can see, checked where it is written, and never invalidated by an unrelated package's load. The facts mode in Julia's compiler gives that last guarantee to any code; traits make it cheap.

**Read it as a website:** [traitjuliaprototype.github.io/julia-trait-bound](https://traitjuliaprototype.github.io/julia-trait-bound/).

## Four goals

Julia is fast once code is compiled, but compiled code is fragile: loading a package can discard it, a new type compiles the same library code again, and whether a program will need the compiler at run time is hard to know. The project pursues four goals:

1. **Interactivity through composable caching of compiled code.** Compiled code is never discarded unless code it depends on changes. It is stored with the package that compiled it and reused in every session and every combination of packages; a new user type costs only the code specific to it.
   *Where it stands:* the facts mode of Julia's compiler gives this to any code. Upstream CSV.jl and DataFrames compiled in it lose 2 of 3,340 pieces of compiled code to nine unrelated loads (570 of 4,712 in Julia's usual mode). Traits make it cheap, and keep a package stable under its own extensions.
2. **Simple ahead-of-time compilation.** Dispatch through trait code goes to declared implementations and declared function signatures, so a build can list exactly the code a program can reach.
   *Where it stands:* a trimmed TraitMakie binary is 4.07 MB (measured on the previous prototype); compiling the declared targets ahead of time from the implementations is the next step.
3. **Control performance cliffs.** Code says what it needs, so its speed does not depend on what else is loaded or on how many types exist today. Where a slow path remains, it is where the code says so, or it is reported: values that are mixed on purpose are declared (`Dynamic`, `Callable`) and stay fast, and an abstract type that reaches a hot path is reported at its root cause.
   *Where it stands:* a sum over mixed shapes runs at 0.9–1.4 ns per element, near plain Julia's 0.9 ns with two shape types and far from its 30 ns with four. Concrete mode and the fully-typed certificate report the root causes.
4. **Identical or error, with minimal changes to Julia.** A call computes what it computes in Julia today, or raises an error. Another package's method for types it does not own (piracy) is followed as in Julia today, or refused under an optional strict mode. Code written without traits keeps working, and a library adopts traits one function at a time.
   *Where it stands:* the acceptance suite's 19 checks pass, including the adversarial cases found by reviews; the patched compiler's changes are proposals for upstream Julia.

## Where to start

| You are | Read |
|---|---|
| a Julia programmer | [`writeup/intro/traits-for-julia.md`](writeup/intro/traits-for-julia.md), then [`writeup/intro/results.md`](writeup/intro/results.md) |
| a core developer | [`writeup/design.md`](writeup/design.md), the design in prose, and [`writeup/design/implementation.md`](writeup/design/implementation.md), the implementation in detail: together the source of truth; the details' chapters in [`writeup/design/`](writeup/design/): the mechanisms, the changes to Julia, the evidence, the performance work, the comparison with other languages; [`writeup/design/alternatives.md`](writeup/design/alternatives.md): the alternatives considered; [`writeup/intro/porting.md`](writeup/intro/porting.md): a working guideline for porters, in the design's vocabulary; part A will be rewritten for programmers |
| an agent resuming work | [`writeup/record/INDEX.md`](writeup/record/INDEX.md), then `writeup/design.md`, `writeup/open-issues.md` §1, and the last bullets of the latest note in `session-notes/` |

## This workspace

This directory is the design repository. Nine repositories sit inside it, each with its own history, ignored by this one:

| Directory | Repository | What |
|---|---|---|
| `.` | design | `writeup/` (the design, its companions, the introduction, the record), `session-notes/` (one note per working session), `attic/` (earlier phases and superseded documents) |
| `julia/`, `julia-1.13/` | patched Julia | a clone of JuliaLang/julia; `julia-1.13/` is a worktree on branch `trait-world-1.13`: v1.13.2 with the facts compiler, parts (A)–(D) and the session-29 changes ([`writeup/design/julia-changes.md`](writeup/design/julia-changes.md)). `julia-1.13/tw-build.sh` rebuilds it, niced, under a memory watchdog |
| `TraitWorld/` | TraitWorld | the design as a package on the patched build (stock Julia is not supported): traits, implementations as methods, keys, entries and workers, `Dynamic`, `Callable`, definition checking, concrete mode and the fully-typed certificate, strict mode, `verify_main`, printing |
| `TraitDifferentialEquations/` | demonstrator | ODE solvers in the trait world: Tsit5, Rodas5, model types, callbacks, gradients; the plain baseline `PlainODE` |
| `TraitMakie/` | demonstrator | a plotting library in the trait world; the plain baseline `PlainPlots` |
| `TraitTables/`, `TraitCSV/` | demonstrator libraries | a column table (`Vector{Dynamic{Column}}`) and a CSV reader whose column types are declared implementations |
| `TraitReport/` | demonstrator | a data report in a fresh session, against pandas and against the same libraries without traits |
| `forks/` | demonstrator | CSV, DataFrames and Tables ported to traits, against upstream, with the upstream test suites |
| `experiments/` | experiments | the smaller prototypes and measurements: `facts/` (acceptance, the framing cases), `factscompiler/` (the compiler's measurements, the control), `examples/` (worked examples for each rule), and earlier phases ([`writeup/record/INDEX.md`](writeup/record/INDEX.md) lists them) |

All of them are in the GitHub organization [TraitJuliaPrototype](https://github.com/TraitJuliaPrototype), each under its directory's name (the design repository as `julia-trait-bound`, the patched Julia as a fork, `julia`, on branch `trait-world-1.13`). The packages' environments refer to their siblings by relative path, so clone them side by side:

```sh
git clone https://github.com/TraitJuliaPrototype/julia-trait-bound
cd julia-trait-bound
for r in TraitWorld TraitDifferentialEquations TraitMakie TraitTables TraitCSV TraitReport forks experiments; do
    git clone https://github.com/TraitJuliaPrototype/$r
done
git clone -b trait-world-1.13 https://github.com/TraitJuliaPrototype/julia julia-1.13
```

Then build the patched Julia (`julia-1.13/tw-build.sh`, or `make` in `julia-1.13/`). Some environments (`TraitReport/env_loads`) still name absolute paths of the original workspace.

## Conventions

- One note per working session in `session-notes/`; decisions in `writeup/decisions.md`, open questions in `writeup/open-issues.md`, kept current when the design changes.
- Writing: short sentences, bullets for anything with more than two parts, one idea per sentence, no unexplained jargon.
- The machine is shared: one Julia job at a time (`flock /tmp/claude-1000/julia-review.lock`), niced; full builds alone, under a memory guard.
