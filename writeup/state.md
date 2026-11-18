# The state of the implementation

What is built, on which heads, which suites pass, and what is next. For core developers and for agents.

- The design is the four [references](reference/README.md). Each section there ends with a status line, and each reference ends with a Deviations table: where the implementation falls short.
- Where each goal stands: [the goals](goals.md). The numbers: [the evidence](design/evidence.md). The work: [the work queue](record/todo.md).
- This page is the one home of the heads. Other documents link here.

<a id="today"></a>
## 1. The heads

| Tree | Repository, branch | Head | What it is |
|---|---|---|---|
| `julia-next` | julia, `next` | f5328f94c5 | Julia v1.13.2 with the design's changes: the tree the work is done in ([the inventory](design/julia-changes.md)) |
| `TraitWorld` | TraitWorld, `unified` | 9d4f782 | the library: `@trait`, `@implement`, the checks, BaseTraits |
| `TraitDifferentialEquations` | `unified` | 3e60c29 | the ODE library |
| `TraitMakie` | `unified` | 1888698 | the plotting library |
| `TraitTables`, `TraitCSV`, `TraitReport` | `unified` | e1ec1f4, 094dcb2, ec34d12 | the table library, the CSV reader, the report against pandas |
| `forks` | forks, `unified` | a3a37d6 | Tables, DataFrames and CSV ported, with upstream's suites |
| `ndport` | `main` | 6928edb | NetworkDynamics (its branch `unified` 82513ee), Graphs and GraphMakie ported, with the workload |
| `julia-vanilla` | julia, v1.13.2 | 45b6d15e34 | plain Julia: the baseline |

The suites below ran on these heads but for the commits that only change READMEs.

**The regression control** is the tag `prototype-2026-11` in every repository: `julia-unified` (7b374f39ce) and `TraitWorld-base` (e11c7cc) are its trees. A change is measured against plain Julia and Python; the tag says whether the implementation got worse.

## 2. What is built

**Julia** is a stack of self-contained commits on v1.13.2, the changes that are useful without traits first ([the inventory](design/julia-changes.md)). Built, by chapter of [the compiler reference](reference/compiler.md):
- sets and memberships in the type system, with intersections; dispatch at a trait; a membership that behaves as a method does, with its edges and its invalidation;
- the facts policy per method, the record of what compiled code depends on, the deep class as a bit on each CodeInstance, images that keep code reached only dynamically;
- the split at a value known by its trait or by a closed abstract type with a contract; `Callable` as a contract at the box;
- one way to erase: a method at a trait that erases by default is made at the kept forms where it is defined; a positive membership decided with an edge;
- owner-only functions; a membership taken back; strict mode's hooks; fully typed mode as a closed build's own check; compiling ahead from a session.

**The library** provides `@trait` (operations as contract entries, defaults, fields, inputs, supertraits), `@implement` (the forms, families, forwarding), the checks at a declaration and at a member's first use, bounded methods, `@trait_module`, the box `Dynamic{X}` and the wrapper `compiled_for(x)`, `Callable`, ownership and strict mode, fully typed mode with `fully_typed`, `make_executable` and `make_library`, hints, and BaseTraits ([traits §10](reference/traits.md#10-collections)).

**What is not built, or built differently,** is in the Deviations tables: [traits](reference/traits.md#19-deviations) (T-), [facts](reference/facts.md#16-deviations) (F-), [compiler](reference/compiler.md#deviations) (C-), [lowering](reference/lowering.md#15-deviations) (L-). The largest:
- **Three of the four demonstrators' programs do not build as trimmed binaries.** The table program builds and runs. The plot's and the report's count 6 errors each, a hole of Base reached from a JLL's `__init__`; the ODE program counts 12, six of them its own ([open issue 184](open-issues.md#2-design)).
- **Keys** are an optional extension, not built ([the extensions](reference/extensions.md)).
- **A cache across sessions** is not built ([the goals](goals.md), G-3).

## 3. The suites on the head

| What | On | Result |
|---|---|---|
| the gates: 72 in force and the 9 stage gates, by one command (`experiments/implementation/gates/run_all.sh <tree>`) | `next` | all pass; none carries an expected-failure check |
| the library's suite | `next` | passes (93 testsets) |
| TraitDifferentialEquations, TraitMakie | `next` | their suites pass (35 and 8 testsets), and their REPL sessions' checks |
| NetworkDynamics | `next` | its test subset passes but for its known failures (`diffusion_test`, `inhomogeneous_test`) |
| the forks | `next`; the tag for upstream's suites (E-373, E-392) | the session's digests equal upstream's at 26 steps on `next`; Tables' upstream suite on `next` has one error, `ByRow(Dict)` ([open issue 240](open-issues.md#2-design)); on the tag Tables' and CSV's upstream suites pass, DataFrames' has the failures of [open issue 157](open-issues.md#2-design) |
| TraitTables, TraitCSV, TraitReport | `next` (E-504) | pass: 3 and 2 testsets; the report's check 3 of 3 and its REPL session 8 of 8 |
| the examples of `intro/` (`experiments/docs-examples/`) | `next` | pass (26, 95 and 5 checks), with one known deviation marked ([open issue 235](open-issues.md#5-implementation-and-measurements)); the tutorial's script ten times without a fault |
| Julia's static check of GC roots over the changed runtime files (`experiments/implementation/w163/sagc.sh`) | `next` | 0 findings, as on vanilla (E-502) |
| Base's `subtype`, `core`, `ambiguous`, `worlds`, `Compiler/inline`, `Compiler/inference`; `detect_ambiguities(Base)` | `next` | pass, as on vanilla; 0 (E-508) |
| the table program as a trimmed binary (`experiments/implementation/w135/build.sh table`) | `next` | builds with 0 errors, 2.7 MB, and prints the session's output; the eight small trait programs build and run (E-508). The plot's and the report's programs count 6 errors, the ODE program 12 (`experiments/implementation/w166/build_c.sh`, which writes the images first; E-509) |

Base's own test files against the vanilla control, and the acceptance cases of the facts mode, are gates of a change to the type system, dispatch or inference ([the playbook](record/playbook.md) §3).

## 4. What is next

The stages of [the next iteration](plans/2026-11-15-next-iteration.md), in [the work queue](record/todo.md):
1. daily use: a program of the ODE library through a build, the teaching (W-158);
2. a freeze and a short measurement round, each row against plain Julia and Python (W-159);
3. the changes to Julia as patches for upstream (W-19).

## 5. The target

The design of the references, built on Julia as a stack of self-contained commits that are proposed upstream where they are useful without traits, with the library as a package.
