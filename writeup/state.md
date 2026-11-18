# The state of the implementation

What is built, on which heads, which suites pass, and what is next. For core developers and for agents.

- The design is the four [references](reference/README.md). Each section there ends with a status line, and each reference ends with a Deviations table: where the implementation falls short.
- Where each goal stands: [the goals](goals.md). The numbers: [the evidence](design/evidence.md). The work: [the work queue](record/todo.md).
- This page is the one home of the heads. Other documents link here.

<a id="today"></a>
## 1. The heads

| Tree | Repository, branch | Head | What it is |
|---|---|---|---|
| `julia-next` | julia, `next` | 32a2235abd | Julia v1.13.2 with the design's changes: the tree the work is done in ([the inventory](design/julia-changes.md)) |
| `TraitWorld` | TraitWorld, `unified` | 51e3a86 | the library: `@trait`, `@implement`, the checks, BaseTraits |
| `TraitDifferentialEquations` | `unified` | 0816231 | the ODE library |
| `TraitMakie` | `unified` | efc3ec0 | the plotting library |
| `TraitTables`, `TraitCSV`, `TraitReport` | `unified` | 7eb82b7, f296d0e, 2a81de6 | the table library, the CSV reader, the report against pandas |
| `forks` | forks, `unified` | b8cab0b | Tables, DataFrames and CSV ported, with upstream's suites |
| `ndport` | `main` | 6b41d66 | NetworkDynamics (its branch `unified` 6d311a3), Graphs and GraphMakie ported, with the workload |
| `julia-vanilla` | julia, v1.13.2 | 45b6d15e34 | plain Julia: the baseline |

The code of the library and the demonstrators is that of d1febca (the library), ae1a966 (the ODE library), d905a0b (the plotting library) and bf6799b (the forks), on which the suites below ran; the commits since change paths, READMEs and one check script.

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
- **Julia and four demonstrators still carry the machinery of an argument's attribute** (casts beside the box and the wrapper; compiler C-112, traits T-127, T-128). TraitTables, TraitCSV and TraitReport are not yet converted to the box and the wrapper. Converting them and removing the machinery is the next stage (§4).
- **Keys** are an optional extension, not built ([the extensions](reference/extensions.md)).
- **A cache across sessions** is not built ([the goals](goals.md), G-3).

## 3. The suites on the head

| What | On | Result |
|---|---|---|
| the gates of each stage of the iteration (`w155/`, `w155b/`, `w160/`, `w161/`) | `next` (E-496) | pass |
| the gates in force (`experiments/implementation/gates/`, 71 files) | `next` | 67 pass; four assert rules the design replaced ([open issue 237](open-issues.md#4-runtime-and-measurements)) |
| the library's suite | `next` (E-496) | passes |
| TraitDifferentialEquations, TraitMakie | `next` (E-496) | their suites pass |
| NetworkDynamics | `next` (E-496) | its suite passes; the workload's digests are unchanged |
| the forks | the tag (E-373, E-392) | the session's digests equal upstream's; Tables' and CSV's upstream suites pass; DataFrames' has the failures of [open issue 157](open-issues.md#2-design) |
| TraitTables, TraitCSV, TraitReport | the tag (E-373) | pass; on `next` after their conversion |
| the examples of `intro/` (`experiments/docs-examples/`) | `next` | pass, with the deviations T-126 and T-127 marked; the tutorial's script crashed in 2 of 6 runs (open issue 234) |

Base's own test files against the vanilla control, and the acceptance cases of the facts mode, are gates of a change to the type system, dispatch or inference ([the playbook](record/playbook.md) §3).

## 4. What is next

First, a fault: the tutorial's script crashes in one run of three on the head, in dispatch's cache ([open issue 234](open-issues.md#4-runtime-and-measurements); W-163). It is found and fixed before anything is measured.

Four gates assert rules the design replaced ([open issue 237](open-issues.md#4-runtime-and-measurements); W-164): they are rewritten next.

Then the stages of [the next iteration](plans/2026-11-15-next-iteration.md), in [the work queue](record/todo.md):
1. the demonstrators follow the design, and the attribute's machinery leaves Julia and the library (W-156);
2. daily use: a program of the ODE library through a build, the teaching (W-158);
3. a freeze and a short measurement round, each row against plain Julia and Python (W-159);
4. the changes to Julia as patches for upstream (W-19).

## 5. The target

The design of the references, built on Julia as a stack of self-contained commits that are proposed upstream where they are useful without traits, with the library as a package.
