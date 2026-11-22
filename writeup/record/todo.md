# Work queue

The work an agent can do: what is to be done, in what order, and the first step of each.

- **Only work an agent can do** (the user: "The work log should be more for things you can do."). What waits for the user is a question in [the open issues §1](../open-issues.md#1-questions-for-the-user). What needs a person from outside the project is not an item.
- **Each item has an ID, `W-n`,** stable and never reused. A new item takes the next free number (W-169).
- **Status:** running (who, in which tree), next, then (after which item), last.
- **Each item names its first step,** so that a session can start it without a plan of its own.
- **A closed item** (done, dropped, merged, deferred) leaves this page for [the ledger](../../attic/writeup/record/todo-closed.md), with its last row.
- **What is not here:** a question to decide is an open issue ([`../open-issues.md`](../open-issues.md)); an experiment is in [the registry](experiments.md); a decision is in [the decision log](decisions.md). A work item links them.

## The order

1. The last stage of [the next iteration](../plans/2026-11-15-next-iteration.md) (§3; who works in which tree: §6): the patches for upstream (W-19, with W-143).
2. Last: `operations(x)` (W-150).

No item pursues speed. A slowdown found is recorded as a tension ([the goals](../goals.md) §3).

## Queue

| ID | Work | First step | Source | Status | Links |
|---|---|---|---|---|---|
| W-19 | **The changes to Julia as small, self-contained patches** for upstream: as orthogonal as possible, each reviewable by a core developer alone, each marked as useful without traits, belonging to the facts mode, or belonging to traits. The inventory follows the patches. | The rows of kind *general* in [the inventory](../design/julia-changes.md): each rebased alone onto v1.13.2 and built. | the user: "Split all the changes to julia into a set of small, self contained and as orthogonal as possible parts. Each should be easily reviewable by a core developer in isolation." | next | [Julia's changes](../design/julia-changes.md) |
| W-143 | **A fully typed Base surface for trait code:** Base and the standard libraries fully typed at the signatures typed code calls them with. Left: the calls at a value typed `Any`, an abstract type or a kind in Base's plain code (open issue 218); a query that names the matched instance (open issue 219); the part that is dynamic by purpose (`show`, the REPL, loading) recorded, not patched. | `experiments/implementation/w157/census.jl` on the head: the culprits by kind, largest first. | the user: "Record "fully typed Base surface for trait code" as a desirable together with your plan." | with W-19's patches | open issues 179, 181, 218, 219; GT-8 |
| W-150 | **`operations(x)` at the REPL:** the operations available on a value or a type, grouped by trait, with their signatures, declared results, defaults and docstrings; methods of no trait under "other". A key binding runs it on the word under the cursor. | The contract's entries of a trait read from a session (`Core`'s `operations` slot), printed for one value. | the user: "do record operations(x) as an idea. It can wait until everything else is done." | last | [the goals](../goals.md) G-8 |
