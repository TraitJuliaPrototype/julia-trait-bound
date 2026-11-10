# Session note and handover, 2026-11-10 (afternoon)

For the next agent session and the user. Every fact here has a home in the record; this note gives the chronology and where things stand. It follows [`2026-11-10-handover.md`](2026-11-10-handover.md), whose open work it takes in order.

## The instruction

The user (2026-11-10): "What's Todo in this project?", then "Make decisions where there is a principled option. Continue with the work.", then "Continue".

No subagent was used. The choices below were made by the agent without a plan's Fable review (none was judged really high impact); each is in the decision log and in open issues §1 for the user to confirm.

## What was done

| Experiment | What | Builds |
|---|---|---|
| E-347 | the ambiguity report asks each method a membership makes applicable at the member (W-132, C-78 retired); a tie with a method at `Any` reported like any other (decided); strict inference of an image's membership at load decided and queued (W-133); open issue 174 | `unified` 53d28eea68, TraitWorld 9383843 |
| E-348 | activation ends an older entry in force for the same member, set and inputs (C-84 retired); the library's search for the latest entry removed | `unified` 9f8d7d7c48, TraitWorld 1ea6af9 |
| E-349 | under strict mode an ambiguity at an image's activation is reported at error level after the load and kept (T-98 retired) | `unified` 9f8d7d7c48, TraitWorld 0aff625 |
| E-350 | a member by its definition used before its `@implement` raises `ImplementError`, at a use dispatch resolves at run time (L-52 narrowed to a compiled use) | `unified` 352b916899, TraitWorld 0aff625 |
| E-351 | the Base iterators compiled in every session: the system image holds those instances inferred, without machine code; a new audit tool; recorded as PE-32, not fixed | (no change) |

- E-348 to E-350 were built one after another and checked in one battery (`experiments/unification/e289/e348.sh`): every check passes. The outcomes are in [the experiments registry](../writeup/record/experiments.md), the numbers in [the evidence](../writeup/design/evidence.md).
- The goal's task after them: 1.81–1.87 s against E-345's 1.78–1.82 s (a warm-up and 3 runs alone, load 4.6–4.7). Within the noise; nothing flagged.
- The binary in `julia-unified/` was built from 352b916899's source before the commits; it reports 53d28eea68 with changes.

## E-351 in brief

- The question was the handover's item 4, with the guess "likely invalidated at load". The guess was wrong: the chain report is empty.
- The cause: a package image stores machine code only for the instances it stores itself. Where the system image already holds an instance with inferred code and no machine code, the package's code reuses it, and the JIT compiles it in each session.
- The tool `experiments/unification/audit/image_uncompiled.jl` lists these from any compile trace (its README: `experiments/unification/audit/README.md`). The goal's task: 8 of 28 compiled instances, 45.6 of 309.7 ms.
- Not taken up: it is Julia's behaviour, not one facts or traits cause or remove ([PE-32](../writeup/record/performance-explorations.md)).

## Waiting for the user

In [`open-issues.md`](../writeup/open-issues.md) §1, each marked mine, beside the morning's list:
- a tie with a method at `Any` is reported and refused at the membership like any other tie;
- strict mode infers an image's membership's checked calls again at its load (W-133, not built);
- activation ends an older entry;
- strict mode's error-level report of an ambiguity at an image's activation;
- a member by its definition used before its `@implement` raises.

The six core dumps in the design repository's root (`core-login02-*`, untracked) are still there for you to delete.

## Open work, in the order I would take it

1. **The member hook in the compile queue** (compiler C-31): a call compiled with the member's type known reaches the trait's method without a check. With it, L-52's remaining half (a compiled use of `S` through `X` before its `@implement`), and the dispatch cache such a call fills. This touches the compile queue: a plan first.
2. **W-133:** strict inference of an image's membership's checked calls at its load.
3. **Open issue 174:** the 2 pairs of two traits' methods with no joint method that reflection finds in TDE's environment.

## Builds and repositories

All pushed. Heads:

| Repository | Branch | Head |
|---|---|---|
| design (this one) | main | see `git log` (the commit with this note) |
| `experiments/` | main | 484aff3 |
| `julia-unified/` | unified | 352b916899 |
| `TraitWorld-unified/` | unified | 1ea6af9 |

The other repositories are at the heads of [the morning's handover](2026-11-10-handover.md).
