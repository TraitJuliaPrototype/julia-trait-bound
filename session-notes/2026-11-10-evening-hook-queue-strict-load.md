# Session note and handover, 2026-11-10 (evening)

For the next agent session and the user. Every fact here has a home in the record; this note gives the chronology and where things stand. It follows [`2026-11-10-afternoon-activation-strict-l52.md`](2026-11-10-afternoon-activation-strict-l52.md), whose three items of open work it builds.

## The instruction

The user (2026-11-10): "Implement 1. 2. and 3. But no plan and review required. Before you start, what are the most important other outstanding deviations/work items?"

No subagent was used, no plan written, no review asked. The choices are in the decision log, marked as the agent's, and in open issues §1 for the user to confirm.

## What was done

| Experiment | What | Builds |
|---|---|---|
| E-352 | the member hook in the compile queue: inference notes the member, the runtime asks the hook before the code runs and keeps the answer; a failed use is left to dispatch; callers are compiled again when a failed check passes (compiler C-31 narrowed, lowering L-52 retired) | `unified` fcdfd0da36, TraitWorld 048c44e |
| E-353 | strict mode infers an image's memberships at its load and reports a method loaded earlier that breaks a check (W-133 done) | TraitWorld 048c44e |
| E-354 | open issue 174 closed: TraitIndexing's `_read` has a joint method; BaseTraits' `getindex` pair stays, named in the tests | TraitDifferentialEquations f903e40, TraitWorld 048c44e |

- All three were checked in one run (`experiments/unification/e289/e352.sh`): every check passes. The outcomes are in [the experiments registry](../writeup/record/experiments.md), the numbers in [the evidence](../writeup/design/evidence.md).
- The goal's task after them: 1.83–1.84 s against E-350's 1.81–1.87 s (a warm-up and 3 runs alone, load 5.2–5.5). No regression.
- The binary in `julia-unified/` was built from fcdfd0da36's source before the commit; it reports 352b916899 with changes.

## What the work found

- **Inference's method matching fills the dispatch cache.** The first build left a failing member's use as a dynamic call, and the call still reached the trait's method: the entry was cached during inference, so dispatch's miss path, where the hook is asked, never ran. The entry is dropped for a failed member.
- **A check can fail and pass later** (a member by its definition, before and after its `@implement`). The runtime keeps the callers compiled while it failed and compiles them again.
- **W-133's cost is above what its row allowed:** about 70 ms at the load of the three ports' images under strict mode (7.6 ms with inference cached). Strict mode only. Flagged in open issues §1 with a proposal.
- **A method defined after the load that changes a checked call's result only through a callee is not refused and not reported.** traits §5.10 refuses only a method that would serve the checked call; the call through the trait asserts the result. In open issues §1 with W-133's item.

## Waiting for the user

In [`open-issues.md`](../writeup/open-issues.md) §1, each marked mine, beside the afternoon's list:
- the member hook in the compile queue: a failed use left to dispatch, compiled again when the check passes;
- strict mode's report at load, never a refusal; its cost (flagged); the callee case above;
- two traits' operations of one function: a joint method, or the pair named in the package's tests.

The six core dumps in the design repository's root (`core-login02-*`, untracked) are still there for you to delete.

## Open work, in the order I would take it

1. **What C-31 leaves:** a call by `invoke` at the set's method asks no hook; with threads another thread may run the code before the queue's check ends. Images keep no check states (lowering L-55, compiler C-30).
2. **The deviations that matter for correctness** (W-128): the rows left in the compiler, traits and lowering Deviations tables.
3. **The ports against upstream** (W-104), **finality by ownership, opt-in** (W-129), and the items of [`todo.md`](../writeup/record/todo.md) in `state.md` §6.3's order.
4. The static analysis of `src/gf.c` (`clang-sagc`) was not run on fcdfd0da36.

## Builds and repositories

All pushed. Heads:

| Repository | Branch | Head |
|---|---|---|
| design (this one) | main | see `git log` (the commit with this note) |
| `experiments/` | main | af7106e |
| `julia-unified/` | unified | fcdfd0da36 |
| `TraitWorld-unified/` | unified | 048c44e |
| `TraitDifferentialEquations-unified/` | unified | f903e40 |

The other repositories are at the heads of [the morning's handover](2026-11-10-handover.md).
