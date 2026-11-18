# Environment and basic workflow

*A standing page: read it when picking up the project. It points to the documents that hold each subject now. Its earlier versions, with the machines and scripts of their day, are `attic/session-notes/00-environment-and-workflow-2026-10-14.md` and `-2026-10-19.md`.*

## Where to read

1. [`../CLAUDE.md`](../CLAUDE.md): the rules.
2. [`../writeup/record/INDEX.md`](../writeup/record/INDEX.md): where each kind of fact lives, the standing constraints of the machine, the repositories.
3. [`../writeup/record/context.md`](../writeup/record/context.md): how the project came to its shape, and what a new agent gets wrong.
4. [`../writeup/record/playbook.md`](../writeup/record/playbook.md): picking up the work, building, checking, measuring, the traps.
5. [`../writeup/setup.md`](../writeup/setup.md): cloning, building, the shared host.
6. The latest session note in this directory, from its last bullets backwards.

## The environment in short

- **The trees:** `julia-next/` (Julia with the design's changes), `julia-vanilla/` (v1.13.2, the plain baseline), `TraitWorld-unified/` and the demonstrators' `-unified/` trees. The heads: [the state](../writeup/state.md#today).
- **On the shared host:** `source env.sh` first. It keeps the depot in `.julia-depot/` inside the workspace and limits a job to 4 cores.
- **Building Julia:** `tools-local/build.sh <tree>`, alone; check `BUILD EXIT 0` at the end of `<tree>/tw-build.log`.
- **Jobs:** `experiments/tools/jl` runs a Julia job in a slot with its own depot and a memory guard.
- **In Claude Code's sandbox** `ps` does not show background jobs: wait for the task's notification.

## A session's note

One note per working session, `<date>-<topic>.md`: the user's words in full, what was done, every number with its commit, what is left. A note is never the only home of a fact ([`../CLAUDE.md`](../CLAUDE.md), the table).
