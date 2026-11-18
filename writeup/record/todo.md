# Work queue

The work an agent can do: what is to be done, in what order, and the first step of each.

- **Only work an agent can do** (the user: "The work log should be more for things you can do."). What waits for the user is a question in [the open issues §1](../open-issues.md#1-questions-for-the-user). What needs a person from outside the project is not an item.
- **Each item has an ID, `W-n`,** stable and never reused. A new item takes the next free number (W-167).
- **Status:** running (who, in which tree), next, then (after which item), last.
- **Each item names its first step,** so that a session can start it without a plan of its own.
- **A closed item** (done, dropped, merged, deferred) leaves this page for [the ledger](../../attic/writeup/record/todo-closed.md), with its last row.
- **What is not here:** a question to decide is an open issue ([`../open-issues.md`](../open-issues.md)); an experiment is in [the registry](experiments.md); a decision is in [the decision log](decisions.md). A work item links them.

## The order

1. The report's, the plot's and the ODE program's builds (W-166, open issue 243).
2. The stages of [the next iteration](../plans/2026-11-15-next-iteration.md) (§3; who works in which tree: §6): daily use (W-158), a freeze and a short round (W-159), the patches for upstream (W-19, with W-143).
3. Last: `operations(x)` (W-150).

No item pursues speed. A slowdown found is recorded as a tension ([the goals](../goals.md) §3).

## Queue

| ID | Work | First step | Source | Status | Links |
|---|---|---|---|---|---|
| W-166 | **The demonstrators' programs build again.** The table program builds with 0 errors and runs (E-507, E-508). Left: the trimmed build's process at LAPACK while loading (open issue 243): the diagnosis (is Colors' stop the same fault; why the report's and the plot's loads reach it on the head and did not at the tag), then the report's, the plot's and the ODE program's counts on the head. | `experiments/implementation/w166/apps/loadrun_lapack.jl` on vanilla and on the head; then `gdb` on the plot's build as `logs/s3-gdb-nls.log` was made for the ODE program's. | mine: found by the main session's check of E-506; a claim of G-6 that held on the tag did not hold on the head | running (E-509): an Opus agent, the diagnosis of open issue 243 | [open issue 243](../open-issues.md#2-design); E-507, E-508 |
| W-158 | **Daily use.** The ODE program without callbacks through a build (open issue 184); the prune list; `intro/` on the reduced design with its examples run; the messages of open issue 235; `withfields` at a box (open issue 236); the gate `n14_callable_args` read once more against the box's rule. | `experiments/implementation/w135/build.sh ode`: the errors left under `--trim=safe`, by kind. | as W-156 | then, after W-166 | [the plan](../plans/2026-11-15-next-iteration.md) §3 |
| W-159 | **A freeze, a short round, the iteration assessed.** The rows a change claims to move, each against plain Julia and Python, with the tag `prototype-2026-11` as the regression control; plain code's first work on the head bisected (open issue 225); the image that misses an instance (open issue 228); the goals' standings and tensions updated; an addendum to the synthesis. | The harness checked against the playbook §4's traps; then the registry's rows, before any run. | as W-156 | then, after W-158 | [the plan](../plans/2026-11-15-next-iteration.md) §3, §4; [the synthesis](../plans/2026-11-14-synthesis.md) |
| W-19 | **The changes to Julia as small, self-contained patches** for upstream: as orthogonal as possible, each reviewable by a core developer alone, each marked as useful without traits, belonging to the facts mode, or belonging to traits. The inventory follows the patches. | The rows of kind *general* in [the inventory](../design/julia-changes.md): each rebased alone onto v1.13.2 and built. | the user: "Split all the changes to julia into a set of small, self contained and as orthogonal as possible parts. Each should be easily reviewable by a core developer in isolation." | then, after W-159 | [Julia's changes](../design/julia-changes.md) |
| W-143 | **A fully typed Base surface for trait code:** Base and the standard libraries fully typed at the signatures typed code calls them with. Left: the calls at a value typed `Any`, an abstract type or a kind in Base's plain code (open issue 218); a query that names the matched instance (open issue 219); the part that is dynamic by purpose (`show`, the REPL, loading) recorded, not patched. | `experiments/implementation/w157/census.jl` on the head: the culprits by kind, largest first. | the user: "Record "fully typed Base surface for trait code" as a desirable together with your plan." | with W-19's patches | open issues 179, 181, 218, 219; GT-8 |
| W-150 | **`operations(x)` at the REPL:** the operations available on a value or a type, grouped by trait, with their signatures, declared results, defaults and docstrings; methods of no trait under "other". A key binding runs it on the word under the cursor. | The contract's entries of a trait read from a session (`Core`'s `operations` slot), printed for one value. | the user: "do record operations(x) as an idea. It can wait until everything else is done." | last | [the goals](../goals.md) G-8 |
