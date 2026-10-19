# writeup/

The design, written for three audiences. Nothing has been deleted: superseded documents are in [`../attic/writeup/`](../attic/writeup/), and the record lists everything with its status.

## For programmers: [`intro/`](intro/)

- [`intro/traits-for-julia.md`](intro/traits-for-julia.md): what traits are, what you write, what you get, one worked example, the costs.
- [`intro/results.md`](intro/results.md): what the demonstrators show, against fair baselines.

## For core developers: [`design.md`](design.md) and [`design/`](design/)

- **[`design.md`](design.md) is the source of truth:** the terms, the problem, the argument in four steps, traits, the three rules, what Julia provides, the decisions in force, the evidence in short, the implementation and the next steps. Where another document disagrees with it, it wins.
- [`design/mechanisms.md`](design/mechanisms.md): the mechanisms in detail (declaring and conforming, generic implementations, `Callable`, keywords, results like the input, `Dynamic`, caching, AOT).
- [`design/julia-changes.md`](design/julia-changes.md): every change to Julia, as built, with commits and upstream status.
- [`design/evidence.md`](design/evidence.md): the measurements, with builds, baselines and run counts; what is not shown.
- [`design/performance.md`](design/performance.md): the performance phase of session 29: results, themes, lessons, as corrected by its review.
- [`design/comparison.md`](design/comparison.md): the choices against C++, Rust, Swift and Mojo; [`other-languages.md`](other-languages.md) is the research behind it.
- [`intro/porting.md`](intro/porting.md): a working guideline for porters, in the design's vocabulary; part A will be rewritten for programmers.
- [`decisions.md`](decisions.md): the register of decisions, with history.
- [`open-issues.md`](open-issues.md): what is open; decisions waiting for the user first (§1).

## For agents: [`record/INDEX.md`](record/INDEX.md)

Every review, exploration, plan, findings section and session note, with its date, its status and what supersedes it, and where to look for a decision's history, a measurement's raw numbers or an experiment's scripts. The record stays where it is (`reviews/`, `explorations/`, `plans/`, `design-findings.md`, `../session-notes/`), since many documents cite those paths.

## Conventions

- **Terms** as in `design.md` §1 (trait, conformance, implementing type, key, trait object, entry, worker, fact, run-time site, owner, stakeholder, pirate). "Representation" and "projection" belong to the design before keys, and appear only in history.
- **Writing:** short sentences, bullets for anything with more than two parts, one idea per sentence, no unexplained jargon; documents for programmers avoid the core developers' terms.
- The machine is shared: one Julia job at a time, at `nice -n 19`; full builds alone, under a memory guard.
