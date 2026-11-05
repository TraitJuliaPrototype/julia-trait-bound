# oc-notes — the traits-v2 build

**Status: unfinished attempt, not adopted.** (Added 2026-11-05.) A QWEN38 class model wrote this on 2026-10-30/31. It reached M2 of M0–M7; M3 stopped on a hang while building the compiler. Its code, gates and notes are unverified material to draw on. The decisions P1–P8 that its plan credits to the user are not in [the decision log](../../writeup/record/decisions.md), so they are not in force. Its Julia commits are on branch `oc-build` of the `julia` repository. Paths below refer to the folders it had then, beside this one.

New, self-contained effort: the unified trait design built into Julia from the vanilla
base (v1.13.2 at `45b6d15e34`, branch `oc-build` in `julia-oc/`). The prior build's
record (`writeup/`, `TraitWorld/`, `julia-1.13/`) is read-only background.

| File | What |
|---|---|
| [plan.md](plan.md) | the implementation plan: mission, the pinned decisions P1–P8, the design as built, milestones M0–M7 with gates. Start here. |
| [notes.md](notes.md) | dated decision and event log, newest first. |
| [numbers.md](numbers.md) | every measured number with build commit and setting. |
| [deviations.md](deviations.md) | where the code falls short of the plan or the references. |
| [c7count/](c7count/) | the M0 experiment: the C7 placement count (script, TSVs, logs). |

| Folder (beside this one) | What |
|---|---|
| `julia-oc/` | the new Julia (git worktree, branch `oc-build`); build it with `./oc-build.sh` |
| `oc-traits/` | the new library package `Traits.jl` |

Conventions: `notes.md` from the first decision you make; every number to `numbers.md`
with its build; nothing written into the old folders.
