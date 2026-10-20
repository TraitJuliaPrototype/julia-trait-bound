# Trait-bound Julia

A design for traits in Julia, built as a patched Julia compiler and a package. Traits are abstract types with behaviour. Library code bounded by traits is compiled for what its bounds can see, checked where it is written, and never invalidated by an unrelated package's load. The facts mode in Julia's compiler gives that last guarantee to any code; traits make it cheap.

**Read it as a website:** [traitjuliaprototype.github.io/julia-trait-bound](https://traitjuliaprototype.github.io/julia-trait-bound/).

## Four goals

Julia is fast once code is compiled, but compiled code is fragile: loading a package can discard it, a new type compiles the same library code again, and whether a program will need the compiler at run time is hard to know. The project pursues four goals:

1. **Interactivity through composable caching of compiled code.** Compiled code is never discarded unless code it depends on changes. It is stored with the package that compiled it and reused in every session and every combination of packages; a new user type costs only the code specific to it.
   *Where it stands:* the facts mode of Julia's compiler gives this to any code. Upstream CSV.jl and DataFrames compiled in it lose 2 of 3,337 pieces of compiled code to nine unrelated loads (561 of 4,684 in Julia's usual mode; measured 2026-10-20 on julia-1.13 3b8085c222). Traits make it cheap, and keep a package stable under its own extensions.
2. **Simple ahead-of-time compilation.** Dispatch through trait code goes to declared implementations and declared function signatures, so a build can list exactly the code a program can reach.
   *Where it stands:* a trimmed TraitMakie binary is 4.07 MB (measured on the previous prototype); compiling the declared targets ahead of time from the implementations is the next step.
3. **Control performance cliffs.** Code says what it needs, so its speed does not depend on what else is loaded or on how many types exist today. Where a slow path remains, it is where the code says so, or it is reported: values that are mixed on purpose are declared (`Dynamic`, `Callable`) and stay fast, and an abstract type that reaches a hot path is reported at its root cause.
   *Where it stands:* a sum over mixed shapes runs at 0.9–1.4 ns per element, near plain Julia's 0.9 ns with two shape types and far from its 30 ns with four (measured 2026-10-19 on julia-1.13 61852d8fb1). Concrete mode and the fully-typed certificate report the root causes.
4. **Identical or error, with minimal changes to Julia.** A call computes what it computes in Julia today, or raises an error. Another package's method for types it does not own (piracy) is followed as in Julia today, or refused under an optional strict mode. Code written without traits keeps working, and a library adopts traits one function at a time.
   *Where it stands:* the acceptance suite's 23 checks pass in both settings (2026-10-20), including the adversarial cases found by reviews; the patched compiler's changes are proposals for upstream Julia.

## Where to start

**The design is defined by four references**, each stating the intended shape first and, separately, where the implementation deviates from it (a Deviations table with stable IDs):

| Reference | Defines |
|---|---|
| [Traits](writeup/reference/traits.md) | the trait language: syntax, meaning, checks and rules, for programmers and core developers |
| [The facts mode](writeup/reference/facts.md) | what compiled code may assume, the guarantees, which code is compiled how |
| [Compiler and runtime](writeup/reference/compiler.md) | what Julia's compiler and runtime provide |
| [Lowering](writeup/reference/lowering.md) | how the trait language is built on them |

Where any other document disagrees with them, they win ([conventions](writeup/reference/README.md)).

| You are | Read |
|---|---|
| a Julia programmer | [`writeup/intro/traits-for-julia.md`](writeup/intro/traits-for-julia.md), then the tutorial [`writeup/intro/traits-by-example.md`](writeup/intro/traits-by-example.md), the [trait language reference](writeup/reference/traits.md) and [`writeup/intro/results.md`](writeup/intro/results.md) |
| a core developer | [`writeup/state.md`](writeup/state.md), the state in one page; the four references above; [`writeup/design.md`](writeup/design.md), the rationale; then [evidence](writeup/design/evidence.md), [performance](writeup/design/performance.md), the [changes to Julia](writeup/design/julia-changes.md), the [comparison with other languages](writeup/design/other-languages.md), the [alternatives considered](writeup/design/alternatives.md) and the [open issues](writeup/open-issues.md) |
| an agent resuming work | [`writeup/record/INDEX.md`](writeup/record/INDEX.md), then `writeup/state.md`, the references' Deviations tables, `writeup/open-issues.md` §1, and the last bullets of the latest note in `session-notes/` |

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

- One note per working session in `session-notes/`; the design in `writeup/reference/`, the decision log in `writeup/record/decisions.md`, open questions in `writeup/open-issues.md`, kept current when the design changes.
- Writing: short sentences, bullets for anything with more than two parts, one idea per sentence, no unexplained jargon.
- The machine is shared: one Julia job at a time (`flock /tmp/claude-1000/julia-review.lock`), niced; full builds alone, under a memory guard.
