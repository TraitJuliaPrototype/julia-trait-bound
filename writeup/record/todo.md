# Work queue

The work an agent can do: what is to be done, in what order, and the first step of each.

- **Only work an agent can do** (the user: "The work log should be more for things you can do."). What waits for the user is a question in [the open issues §1](../open-issues.md#1-questions-for-the-user). What needs a person from outside the project is not an item.
- **Each item has an ID, `W-n`,** stable and never reused. A new item takes the next free number (W-172).
- **Status:** running (who, in which tree), next, then (after which item), last.
- **Each item names its first step,** so that a session can start it without a plan of its own.
- **A closed item** (done, dropped, merged, deferred) leaves this page for [the ledger](../../attic/writeup/record/todo-closed.md), with its last row.
- **What is not here:** a question to decide is an open issue ([`../open-issues.md`](../open-issues.md)); an experiment is in [the registry](experiments.md); a decision is in [the decision log](decisions.md). A work item links them.

## The order

1. The rest of the patches for upstream: the traits series (W-19).

2. Beside it, the audit of folds about a set across worlds (W-171).

No item claims better steady-state speed. A slowdown found is recorded as a tension ([the goals](../goals.md) §3).

## Queue

| ID | Work | First step | Source | Status | Links |
|---|---|---|---|---|---|
| W-19 | **The changes to Julia as small, self-contained patches** for upstream: as orthogonal as possible, each reviewable by a core developer alone, each marked as useful without traits, belonging to the facts mode, or belonging to traits. **The series is made whole** ([the inventory §5](../design/julia-changes.md#patches); [the plan](../plans/2026-11-22-upstream-series.md)): 25 patches useful without traits (`up/01` to `up/25`, `w19-stack-v2`), the facts series (F0 to F12 with its tests), the traits series (T1 to T17 with S3): 66 commits on v1.13.2, 12,381 lines added; its head builds, passes the gates and Base's tests, and runs the library's suite and the nine loads (E-533, E-534, E-539). Left: rows 182 to 188 of the inventory into the parts they belong to, and what the audit (W-171) still adds; T16 cut in three; testsets in Julia's `test/` for T11 to T17; the parts not built alone, built; the static check of the collectors' roots over the new C; `trimming`'s test run; each patch's message and comments read once more for a core developer; the branch of work-in-progress trees (`w19-traits-v2-cut`) removed when nothing needs it. | Rows 182 to 188 as commits on the stack (`traits-v2/…`), then T16's cut, each compiled, the head built once: the gates all pass (`n38` too). | the user: "Split all the changes to julia into a set of small, self contained and as orthogonal as possible parts. Each should be easily reviewable by a core developer in isolation." | next: after the audit's fixes are in `next` (six parts done) | [Julia's changes](../design/julia-changes.md) |
| W-171 | **An audit of every fold about a set, across worlds.** The tool is built (`experiments/implementation/audit/set_folds.jl`; E-542): on the head before it 8,975 mismatches from eight patterns; four are fixed and merged, and no question about types mismatches. Left: the four patterns about dispatch and equality (compiler C-162 to C-165), each fixed at its rule with a gate, until the tool reports nothing; the tool's modes for package images and for the library (the kept forms, declared results, the `trusted` mark, `Callable`); what less evaluation at compile time costs trait code (row 187), measured on the sessions. | C-164 (the declaration walk at an abstract type, a set or a union): its probes in `experiments/implementation/w171/probes/gen/`, the fix in `src/gf.c`'s walk, the tool after it. | the user (CLAUDE.md): "When we see failures like this, also think about principled fixes or new tools that reveal common patterns"; three soundness holes of one family found by chance on one day (rows 181, 182, 184 of the inventory) | running: an agent in `wt/w171-julia` (E-543) | compiler §4.8, §5.5, C-162 to C-165; the proofs; gates `n37` to `n41` |
