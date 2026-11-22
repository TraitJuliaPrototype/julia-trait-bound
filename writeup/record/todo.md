# Work queue

The work an agent can do: what is to be done, in what order, and the first step of each.

- **Only work an agent can do** (the user: "The work log should be more for things you can do."). What waits for the user is a question in [the open issues §1](../open-issues.md#1-questions-for-the-user). What needs a person from outside the project is not an item.
- **Each item has an ID, `W-n`,** stable and never reused. A new item takes the next free number (W-170).
- **Status:** running (who, in which tree), next, then (after which item), last.
- **Each item names its first step,** so that a session can start it without a plan of its own.
- **A closed item** (done, dropped, merged, deferred) leaves this page for [the ledger](../../attic/writeup/record/todo-closed.md), with its last row.
- **What is not here:** a question to decide is an open issue ([`../open-issues.md`](../open-issues.md)); an experiment is in [the registry](experiments.md); a decision is in [the decision log](decisions.md). A work item links them.

## The order

1. The last stage of [the next iteration](../plans/2026-11-15-next-iteration.md) (§3; who works in which tree: §6): the patches for upstream (W-19, with W-143).

2. Then the profiling of the workloads (W-169): where a session's time is spent, and the candidates for fixes that add little code.

No item claims better steady-state speed. A slowdown found is recorded as a tension ([the goals](../goals.md) §3).

## Queue

| ID | Work | First step | Source | Status | Links |
|---|---|---|---|---|---|
| W-19 | **The changes to Julia as small, self-contained patches** for upstream: as orthogonal as possible, each reviewable by a core developer alone, each marked as useful without traits, belonging to the facts mode, or belonging to traits. The inventory follows the patches. **The first part is done:** eighteen patches useful without traits, each one commit on v1.13.2 (`up/01` to `up/18`; [the inventory §5](../design/julia-changes.md#patches)), and [the plan for the two series](../plans/2026-11-22-upstream-series.md). Left: the call's own signature in a dispatch edge as `up/19`; the facts series (F0 to F8, about nine builds), then the traits series; each patch's message and comments read once more for a core developer. | `up/19`: the call-signature backedge cut from the final diff (compiler §3.1; rows 79, 83, s3-8), built alone, `test/worlds.jl` and `test/precompile.jl`. | the user: "Split all the changes to julia into a set of small, self contained and as orthogonal as possible parts. Each should be easily reviewable by a core developer in isolation." | running: the first part done (E-533) | [Julia's changes](../design/julia-changes.md) |
| W-143 | **A fully typed Base surface for trait code:** Base and the standard libraries fully typed at the signatures typed code calls them with. Left: the calls at a value typed `Any`, an abstract type or a kind in Base's plain code (open issue 218); a query that names the matched instance (open issue 219); the part that is dynamic by purpose (`show`, the REPL, loading) recorded, not patched. | `experiments/implementation/w157/census.jl` on the head: the culprits by kind, largest first. | the user: "Record "fully typed Base surface for trait code" as a desirable together with your plan." | with W-19's patches | open issues 179, 181, 218, 219; GT-8 |
| W-169 | **A round of detailed profiling of the workloads we have:** for each session (upstream CSV with DataFrames compiled plainly and by facts, the forks, the table's, the ODE port's with and without callbacks, the plot's and the report's, NetworkDynamics' workload, each beside its plain run), where the time goes, precisely: load (the image's restore, the memberships' activation, the hooks), inference, code generation, compiled again and why, dispatch at run time, the work; by package and by function. Then the list of candidates, each with what it would save, the rule of the design that lets the compiler do less there, and its size in code. | The registry's row first (the question, the baseline of plain Julia per workload, what would change the design); then the harness: one profile per session with Julia's own timers and counters (`Base.cumulative_compile_time_ns`, the invalidation and validation logs, `--trace-compile-timing`, the sampling profiler at 1 ms with the frames of `experiments/implementation/w167/load_parts.jl`), on the freeze's heads. | the user: "Once W-19 is done, we should do a round of detailed profiling of the workloads we have, to understand precisely where session time is spent and identify further \"low hanging fruit\" for speed work." | then, after W-19 | GT-9, GT-33, GT-12; open issues 255, 258; E-521, E-531, E-532; [the performance explorations](performance-explorations.md) |
