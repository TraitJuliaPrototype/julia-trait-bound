# Work queue

The agreed work that is open: what is to be done, why, in what order, and what it waits for.

- **Each item has an ID, `W-n`,** stable and never reused. A new item takes the next free number (W-164).
- **Status:** next, open, waiting (say for what), paused, idea.
- **Source:** who asked; the user's words where the user asked.
- **A closed item** (done, dropped, merged, retired, stopped) leaves this page for [the ledger](../../attic/writeup/record/todo-closed.md), with its last row. The ledger holds every item up to W-162 with its history.
- **What is not here:** a question to decide is an open issue ([`../open-issues.md`](../open-issues.md)); an experiment is in [the registry](experiments.md); a decision is in [the decision log](decisions.md). A work item links them.

## The plan

The order of work is the stages of [the next iteration](../plans/2026-11-15-next-iteration.md) (§3; who works in which tree and where it stands: §6).

| Stage | What | Item |
|---|---|---|
| 4 | the ports follow the design: one way to erase, `Callable` as a contract at the box, operations as contract entries | W-156 |
| 6 | daily use: a program through a build, the prune list, the teaching, a reader from outside | W-158 |
| 7 | a freeze, a short measurement round, the iteration assessed | W-159 |
| 8 | the changes to Julia as patches for upstream | W-19 |

Stages 0 to 3 and 5 are closed. The speed work is retired: no item pursues speed, and a slowdown found is recorded as a tension ([the goals](../goals.md) §3).

## Queue

| ID | Work | Source | Status | Links |
|---|---|---|---|---|
| W-163 | **A crash in dispatch's cache: find every place of its kind, and fix them.** Julia's static check of roots (`make -C src analyzegc`) over the changed runtime files; the gates and the examples of `intro/` once under a stressed collector; the counts recorded; the fix at each place. Before the measurement round. | mine, by the rule that a failure names a pattern (`CLAUDE.md`): the tutorial's script crashed in 2 of 6 runs on `next` | next | [open issue 234](../open-issues.md#4-runtime-and-measurements) |
| W-162 | **The documentation clean-up:** the documents describe the intended design and the implementation as it is; the record shows the current experiments, work and decisions; plans and reviews that are no longer relevant are in the attic, their insights in the lessons and the alternatives; the workspace tidied; the directories renamed last. | the user: "Currently a lot of the documentation seems still to be written in terms of the history, and referencing the pre unified implementation. At this point unified _is_ the implementation. The documentation should describe the intended design." | next: in progress, by its parts | [the plan](../plans/2026-11-18-documentation-cleanup.md); [the harvest notebook](harvest-2026-11.md) |
| W-156 | **Stage 4: the ports follow.** Every demonstrator on the head with the box and the wrapper in place of casts, `Callable`'s guards and operations as contract entries; the suites' table again; the annotations per port counted; the porting guideline rewritten on the converted ports; then the attribute's machinery removed from Julia and the library (compiler C-112, traits T-127). | the user: "Have Opus agents implement the plan" | next, not started | [the plan](../plans/2026-11-15-next-iteration.md) §3, §6 ("Where it stands") |
| W-158 | **Stage 6: daily use.** The ODE program without callbacks through a build (open issue 184); the prune list; `intro/` on the reduced design with its examples run; W-150 if small; a reader from outside prepared. | as W-156 | open, after W-156 | [the plan](../plans/2026-11-15-next-iteration.md) §3 |
| W-159 | **Stage 7: a freeze, a short round, the iteration assessed.** The rows a change claims to move, each against plain Julia and Python, with the tag `prototype-2026-11` as the regression control; the goals' standings and tensions updated; an addendum to the synthesis: each tension closed, smaller or standing, each decision's gain and cost. | as W-156 | open, after W-158 | [the plan](../plans/2026-11-15-next-iteration.md) §3, §4; [the synthesis](../plans/2026-11-14-synthesis.md) |
| W-19 | **The changes to Julia as small, self-contained patches** for upstream: as orthogonal as possible, each reviewable by a core developer alone, each marked as useful without traits, belonging to the facts mode, or belonging to traits. The inventory follows the patches. The branch is a stack of such commits already; a stage's rework replaces its commits. | the user: "Split all the changes to julia into a set of small, self contained and as orthogonal as possible parts. Each should be easily reviewable by a core developer in isolation." | waiting: stage 8, after W-159 | [Julia's changes](../design/julia-changes.md) |
| W-143 | **A fully typed Base surface for trait code:** Base and the standard libraries fully typed at the signatures typed code calls them with. The tool and the census exist; the patches so far are in the stack. Left: the calls at a value typed `Any`, an abstract type or a kind in Base's plain code (open issue 218); a query that names the matched instance (open issue 219); the part that is dynamic by purpose (`show`, the REPL, loading) recorded, not patched. | the user: "Record "fully typed Base surface for trait code" as a desirable together with your plan." | open: continues with W-19's patches | open issues 179, 181, 218, 219; GT-8 |
| W-110 | **Keys:** members that share a layout and a receiver share one compiled instance of a fully bounded method. An optional extension; no rule depends on it. Built when a measurement asks for it, or when the user commits to what keys guarantee. | the user: "Keys should be considered purely a performance optimization. They can stay deferred." | waiting: optional, deferred | [the optional extensions](../reference/extensions.md); [PE-33](performance-explorations.md) |
| W-150 | **`operations(x)` at the REPL:** the operations available on a value or a type, grouped by trait, with their signatures, declared results, defaults and docstrings; methods of no trait under "other". A key binding runs it on the word under the cursor. An editor or a language server is out of scope. | the user: "do record operations(x) as an idea. It can wait until everything else is done." | idea, last (with W-158 if small) | [the goals](../goals.md) G-8 |
