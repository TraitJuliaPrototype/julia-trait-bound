# The record: an index for agents

The map of what is on record. It is written for an agent that needs to find a fact, a number, a decision or how to work. Nothing here is the design itself.

## Where each kind of fact lives

The full table, with the rule for each kind, is in [`CLAUDE.md`](../../CLAUDE.md). In short:

| You look for | It is in |
|---|---|
| a rule of the design | [the references](../reference/README.md): traits, facts, compiler, lowering, the optional extensions |
| where the code falls short of a rule | that reference's Deviations table |
| why the design has its shape | [the rationale](../design.md); [the proofs](../design/proofs.md) |
| a number behind a claim | [the evidence](../design/evidence.md), by goal |
| an experiment: its question, build and outcome | [the registry](experiments.md); its scripts and logs in `experiments/` |
| the goals, the standing on each, the tensions | [the goals](../goals.md) |
| what is built, the heads, the suites | [the state](../state.md) |
| agreed work | [the work queue](todo.md) |
| an open question, a tension's entry | [the open issues](../open-issues.md) |
| a decision, with the user's words | [the decision log](decisions.md) |
| what was tried and not taken | [the alternatives](../design/alternatives.md) |
| what the work taught | [the lessons](../design/lessons.md) |
| every commit to Julia | [Julia's changes](../design/julia-changes.md) |
| the design against other languages | [other languages](../design/other-languages.md); the research notes in this directory |
| a term | [the glossary](../glossary.md) |
| the chronology, the user's words in full | `session-notes/`, one note per session, named by date |
| anything earlier | [the attic](../../attic/README.md) |

## The agents' tier

This directory holds more context than a reader of the design wants. An agent that starts cold reads it.

| Document | What it holds |
|---|---|
| [`context.md`](context.md) | the project for an agent that starts cold: the eras and why each turn was taken, what the user wants and why, what a new agent tends to get wrong |
| [`playbook.md`](playbook.md) | how the work is done: building, checking, measuring, reviews, agents, the traps met |
| [`build-notes/`](build-notes/traits.md): [traits](build-notes/traits.md), [facts](build-notes/facts.md), [compiler](build-notes/compiler.md), [lowering](build-notes/lowering.md), [extensions](build-notes/extensions.md), [Julia's stack](build-notes/julia-stack.md), [the choices](build-notes/choices.md) | per section of a reference: the status line as it stood, with the commits that built the rule, its gates, its decision and its experiments; how the stack of Julia's commits was checked; the choices an agent made in the references |
| [`decisions.md`](decisions.md), [`experiments.md`](experiments.md), [`todo.md`](todo.md) | the ledgers that are current |
| [`design-history.md`](design-history.md) | the timeline, with pointers into the attic |
| [`performance-explorations.md`](performance-explorations.md) | performance work not taken up: an archive, read for ideas |
| [`harvest-2026-11.md`](harvest-2026-11.md), [`harvest-dispositions-2026-11.md`](harvest-dispositions-2026-11.md) | the reading of every archived plan, review and exploration: the digest behind the lessons and the alternatives; what was done with the findings of the last reviews |
| the research notes (`*-research-*.md`, `julia-1.14-scan-*.md`) | research on other languages and on Julia |

**The ledgers of what is closed** are in the attic, under `attic/writeup/record/`: [every experiment registered](../../attic/writeup/record/experiments-archive.md), [closed work items](../../attic/writeup/record/todo-closed.md), [closed issues](../../attic/writeup/record/issues-closed.md), [superseded decisions](../../attic/writeup/record/decisions-superseded.md), [retired deviation rows](../../attic/writeup/record/deviations-retired.md), [the performance explorations of the library of October 2026](../../attic/writeup/record/performance-explorations-earlier.md).

**Rules of this tier.** It may hold chronology, provenance and the user's words. It is never the only home of a rule of the design, a number or a decision.

## How to resume work

[The playbook](playbook.md) §1. In one line: `CLAUDE.md`, the context, the goals and the state, the work queue and the plan it names, the latest session note.

The plans that are running or awaited:
- [the next iteration](../plans/2026-11-15-next-iteration.md): the decisions of the iteration that is being built, its stages, who works in which tree, where it stands;
- [the synthesis](../plans/2026-11-14-synthesis.md) and [the review of the conceptual design](../reviews/2026-11-15-conceptual-design.md), which the iteration answers;
- The documentation clean-up of 2026-11-18 is done. Its rules are in [`CLAUDE.md`](../../CLAUDE.md); its plan, its review and what it found are in the attic ([the plan](../../attic/writeup/plans/2026-11-18-documentation-cleanup.md), [the review](../../attic/writeup/reviews/2026-11-18-documentation-cleanup.md)).

## Standing constraints

The rules are in [`CLAUDE.md`](../../CLAUDE.md), "Working on this machine", with the user's words. Their detail:

- **`source env.sh` first** on a shared host. It loads the compiler, keeps the Julia depot inside the workspace and limits Julia and `experiments/tools/jl` to 4 cores ([setup](../setup.md)).
- **Cores by load.** Check `/proc/loadavg` before each compile and before starting jobs side by side.
  - While the others' load is below half the cores, a build may spike to half the cores for its parallel compile phase. `tools-local/build.sh <tree>` chooses and enforces this.
  - Sustained use stays at 4 cores per job and at most 16 in all. Builds one after another run with `WIDE=0`.
  - At or above half load: 4 cores, one job at a time, full builds alone.
- **Jobs are niced; full builds run under a memory guard** (`tools-local/loadguard.sh`).
- **Never search outside the workspace.** `find`, `du`, `grep -r` run inside the directories they concern.
- **Subagents** only where `CLAUDE.md` names an exception; an agent starts none.
- **Pushing:** commits may be pushed at will, in every repository of the workspace.
- **Measurements:** minutes, not hours; campaigns at a freeze.
- **Project memory** of Claude Code is not relied on.

## The repositories

This directory is the design repository (`writeup/`, `session-notes/`, `attic/`; branch `main`). The others sit inside it, each its own repository, ignored by this one. Each tree's current head: `git -C <dir> log -1`; the heads a result was measured on are in [the state](../state.md).

| Directory | What | Branch |
|---|---|---|
| `julia-next/` | Julia with the design: v1.13.2 and the stack of [Julia's changes](../design/julia-changes.md); the tree the work is done in | `next` |
| `julia-unified/` | the same repository at the tag `prototype-2026-11`: the regression control of the running iteration | the tag |
| `julia-vanilla/` | Julia v1.13.2 unchanged: the plain baseline | detached at the release |
| `TraitWorld/` | the library: `@trait`, `@implement`, the checks, BaseTraits | `unified` |
| `TraitWorld-base/` | the library at the tag: the regression control | the tag |
| `TraitDifferentialEquations/`, `TraitMakie/`, `TraitTables/`, `TraitCSV/`, `TraitReport/` | the demonstrators: an ODE library, a plotting library, a table library, a CSV reader, a report against pandas | `unified` |
| `forks/` | Tables, DataFrames and CSV ported, with upstream's suites | `unified` |
| `ndport/` | NetworkDynamics and the packages under it: the workload, its environments and logs; the clones under `ndport/pkgs/` are restored from bundles | `main` |
| `experiments/` | gates, measurements, tools; one directory per experiment or work item, each with a README | `main` |
| `tools-local/` | the build script and the load guard (in the design repository) | — |
| `julia-1.13/`; `pre-unified/` | the library on a patched Julia 1.13 and its demonstrators, of October 2026: the tag `pre-unified` of each repository. History. `julia-1.13/` holds the julia repository, of which the other Julia trees are worktrees; the directories under `pre-unified/` hold the other repositories, of which the trees above are worktrees | — |
| `wt/` | worktrees of agents | — |
