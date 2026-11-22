# Work queue

The work an agent can do: what is to be done, in what order, and the first step of each.

- **Only work an agent can do** (the user: "The work log should be more for things you can do."). What waits for the user is a question in [the open issues §1](../open-issues.md#1-questions-for-the-user). What needs a person from outside the project is not an item.
- **Each item has an ID, `W-n`,** stable and never reused. A new item takes the next free number (W-171).
- **Status:** running (who, in which tree), next, then (after which item), last.
- **Each item names its first step,** so that a session can start it without a plan of its own.
- **A closed item** (done, dropped, merged, deferred) leaves this page for [the ledger](../../attic/writeup/record/todo-closed.md), with its last row.
- **What is not here:** a question to decide is an open issue ([`../open-issues.md`](../open-issues.md)); an experiment is in [the registry](experiments.md); a decision is in [the decision log](decisions.md). A work item links them.

## The order

1. The rest of the patches for upstream: the traits series (W-19), then Base's surface (W-143).

No item claims better steady-state speed. A slowdown found is recorded as a tension ([the goals](../goals.md) §3).

## Queue

| ID | Work | First step | Source | Status | Links |
|---|---|---|---|---|---|
| W-19 | **The changes to Julia as small, self-contained patches** for upstream: as orthogonal as possible, each reviewable by a core developer alone, each marked as useful without traits, belonging to the facts mode, or belonging to traits. The inventory follows the patches. **The first part is done:** eighteen patches useful without traits, each one commit on v1.13.2 (`up/01` to `up/18`; [the inventory §5](../design/julia-changes.md#patches)), and [the plan for the two series](../plans/2026-11-22-upstream-series.md). **The second and third parts are done:** `up/19` (the call's own signature in a dispatch backedge, at no cost to a plain load), the facts series F0 to F12 as commits on v1.13.2 with F4 in three (`w19-facts`, `w19-facts-split`), and the two series built together (`w19-g-facts`); the facts series' head alone reproduces the facts mode's result (E-534). **The fourth part is done:** the traits parts T1 to T5 on `w19-g-facts` (`w19-traits`; E-539), and the tests of F9 to F12 in Julia's `test/` (`w19-facts-tests-v2`). Left: T6 to T17, each on `w19-traits`; the stack moved onto `w19-facts-tests-v2`; T1, T2a to T2c, F4a and F4b built alone; `!==` as a general patch `up/20`; each patch's message and comments read once more for a core developer. | T6 on `w19-traits` (the plan's §2.3; the README's fourth part, §8, names what each of T6 to T17 needs and the order of builds), built. | the user: "Split all the changes to julia into a set of small, self contained and as orthogonal as possible parts. Each should be easily reviewable by a core developer in isolation." | running: the traits series (four parts done: E-533, E-534, E-539) | [Julia's changes](../design/julia-changes.md) |
| W-143 | **A fully typed Base surface for trait code:** Base and the standard libraries fully typed at the signatures typed code calls them with. The census on the head is done (E-535). Left: Base's reads of a type's flags, the type joins `up/03` left, `CyclePadding`, the task code's stores (the four diffs of `experiments/implementation/w143c/patches/`), each built, counted and added to the patches for upstream; the compiler's record of `TypeVar`, `UnionAll` and a top-level union (compiler C-160; open issue 218 (g)); the calls at a value typed `Any`, an abstract type or a kind (open issue 218); a query that names the matched instance (open issue 219); the part that is dynamic by purpose (`show`, the REPL, loading) recorded, not patched. | The four diffs applied on `next` in a worktree, one build, then `experiments/implementation/w143c/run.sh` on the three sessions: the share of the class before and after, per patch by the census's groups. | the user: "Record "fully typed Base surface for trait code" as a desirable together with your plan." | after W-19's traits series frees the trees | open issues 179, 181, 218, 219; GT-8; E-535 |
