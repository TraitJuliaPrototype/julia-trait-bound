# Trait-bound Julia

A design for traits in Julia, with a prototype: a changed Julia, a library and ports of parts of three ecosystems.

- **A trait is an abstract type that types may join after they are defined, with a contract that is checked at each membership.** Library code written against a trait is checked where it is written and compiled for what its contract lets it see.
- **Compiling "by facts"** makes compiled code depend on the method table only where nobody but the owners of the code's own functions and types can change it. Such code is kept when an unrelated package loads. Any Julia code can be compiled this way, with one line per module. Traits make living under the rule cheap and checked.

**Read it as a website:** [traitjuliaprototype.github.io/julia-trait-bound](https://traitjuliaprototype.github.io/julia-trait-bound/).

## What it sets out to show

Julia is fast once code is compiled, but compiled code is fragile. Loading a package can discard it, a new type compiles the same library code again, and whether a program needs the compiler at run time is hard to know. The project's claims, one per axis:

| Axis | The claim |
|---|---|
| Recompilation | compiled code is kept through unrelated loads, and trait code is compiled once where its contract allows |
| Run-time speed | no regression against plain Julia where types are known; no claim of better steady-state speed |
| Caching | what is compiled is kept in package images |
| Downsides | what the design costs code that uses no trait, and code that does, is small and stated |
| Error messages | an error names the contract and the place it is broken |
| Compiling ahead | a trait bound handles generics as in Rust and Mojo: checked once against the bound, compiled for the members a build has |
| Transition | a path for the ecosystem, with porting guidelines |
| Simplicity | one mechanism, easy to teach |

Where each stands, with what supports it and what is weakest: [the goals](writeup/goals.md). The numbers, each against plain Julia or Python: [the evidence](writeup/design/evidence.md).

## Where to start

| You are | Read |
|---|---|
| a Julia programmer | [Traits for Julia](writeup/intro/traits-for-julia.md), then [Traits by example](writeup/intro/traits-by-example.md), [Porting to traits](writeup/intro/porting.md) and [the results](writeup/intro/results.md) |
| a core developer | [the goals](writeup/goals.md) and [the state](writeup/state.md); the four references below; [the rationale](writeup/design.md) and [the proofs](writeup/design/proofs.md); then [the evidence](writeup/design/evidence.md), [Julia's changes](writeup/design/julia-changes.md), [other languages](writeup/design/other-languages.md), [the alternatives](writeup/design/alternatives.md), [the lessons](writeup/design/lessons.md) and [the open issues](writeup/open-issues.md) |
| an agent | [`CLAUDE.md`](CLAUDE.md), then [the record's index](writeup/record/INDEX.md) |

**The design is defined by four references.** Each states the intended design and, apart from it, where the implementation falls short (a Deviations table with stable IDs).

| Reference | Defines |
|---|---|
| [Traits](writeup/reference/traits.md) | the trait language: syntax, meaning, checks and rules |
| [The facts mode](writeup/reference/facts.md) | what compiled code may assume, the guarantees, which code is compiled how |
| [Compiler and runtime](writeup/reference/compiler.md) | what Julia's compiler and runtime provide |
| [Lowering](writeup/reference/lowering.md) | how the trait language is built on them |

Where another document disagrees with them, they win ([conventions](writeup/reference/README.md)).

## This workspace

This directory is the design repository: `writeup/` (the design and the record), `session-notes/` (one note per working session) and `attic/` (earlier work, with [an index](attic/README.md)). The other repositories sit inside it, each with its own history, ignored by this one:

| Repository | What |
|---|---|
| `julia` | a fork of JuliaLang/julia: v1.13.2 with the design's changes ([the inventory](writeup/design/julia-changes.md)) |
| `TraitWorld` | the library: `@trait`, `@implement`, the checks, the collection traits |
| `TraitDifferentialEquations`, `TraitMakie`, `TraitTables`, `TraitCSV`, `TraitReport` | the demonstrators: an ODE library, a plotting library, a table library, a CSV reader, a report against pandas |
| `forks` | Tables, DataFrames and CSV ported to traits, with upstream's test suites |
| `ndport` | NetworkDynamics and the packages under it, ported |
| `experiments` | gates, measurements and tools |

All are in the GitHub organization [TraitJuliaPrototype](https://github.com/TraitJuliaPrototype). Which directory holds which branch, and how to clone and build: [the record's index](writeup/record/INDEX.md) and [setting up](writeup/setup.md).

## Conventions

- Every kind of fact has one home; the table is in [`CLAUDE.md`](CLAUDE.md).
- Writing: short sentences, one idea per sentence, bullets for anything with more than two parts.
