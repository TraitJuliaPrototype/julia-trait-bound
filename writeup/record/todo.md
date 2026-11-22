# Work queue

The work an agent can do: what is to be done, in what order, and the first step of each.

- **Only work an agent can do** (the user: "The work log should be more for things you can do."). What waits for the user is a question in [the open issues §1](../open-issues.md#1-questions-for-the-user). What needs a person from outside the project is not an item.
- **Each item has an ID, `W-n`,** stable and never reused. A new item takes the next free number (W-171).
- **Status:** running (who, in which tree), next, then (after which item), last.
- **Each item names its first step,** so that a session can start it without a plan of its own.
- **A closed item** (done, dropped, merged, deferred) leaves this page for [the ledger](../../attic/writeup/record/todo-closed.md), with its last row.
- **What is not here:** a question to decide is an open issue ([`../open-issues.md`](../open-issues.md)); an experiment is in [the registry](experiments.md); a decision is in [the decision log](decisions.md). A work item links them.

## The order

1. The rest of the patches for upstream: the traits series (W-19).

No item claims better steady-state speed. A slowdown found is recorded as a tension ([the goals](../goals.md) §3).

## Queue

| ID | Work | First step | Source | Status | Links |
|---|---|---|---|---|---|
| W-19 | **The changes to Julia as small, self-contained patches** for upstream: as orthogonal as possible, each reviewable by a core developer alone, each marked as useful without traits, belonging to the facts mode, or belonging to traits. The inventory follows the patches. **The first part is done:** eighteen patches useful without traits, each one commit on v1.13.2 (`up/01` to `up/18`; [the inventory §5](../design/julia-changes.md#patches)), and [the plan for the two series](../plans/2026-11-22-upstream-series.md). **The second and third parts are done:** `up/19` (the call's own signature in a dispatch backedge, at no cost to a plain load), the facts series F0 to F12 as commits on v1.13.2 with F4 in three (`w19-facts`, `w19-facts-split`), and the two series built together (`w19-g-facts`); the facts series' head alone reproduces the facts mode's result (E-534). **The fourth and fifth parts are done:** the traits parts T1 to T10 (`w19-traits-v2`, on the facts series with its tests in Julia's `test/`; E-539). Left: T11 with T15, T12 with T13, T14 with T17 and the options' rename (then the library's suite on the series' head), T16; row 181 and the world bound of a final negative into the parts they belong to; T1, T2a to T2c, T7, T9a, T9b, F4a and F4b built alone; the general patches `up/20` and above (rows 174 to 178, 180); the static check of the collectors' roots over the new C; each patch's message and comments read once more for a core developer. | T11 with T15 on `w19-traits-v2` (the README's fifth part names what each of T11 to T17 needs, the seams and the order of builds), built; the gates `n22`, `n23`, `n35`. | the user: "Split all the changes to julia into a set of small, self contained and as orthogonal as possible parts. Each should be easily reviewable by a core developer in isolation." | next: the traits series' last parts (five parts done: E-533, E-534, E-539) | [Julia's changes](../design/julia-changes.md) |
