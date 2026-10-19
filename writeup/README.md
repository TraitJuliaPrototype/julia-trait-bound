# writeup/

The design, written for three audiences. Nothing has been deleted: superseded documents are in [`../attic/writeup/`](../attic/writeup/), and the record lists everything with its status.

## For programmers: [`intro/`](intro/)

- [`intro/traits-for-julia.md`](intro/traits-for-julia.md): what traits are, what you write, what you get, one worked example, the costs.
- [`intro/results.md`](intro/results.md): what the demonstrators show, against fair baselines.
- [`intro/traits-by-example.md`](intro/traits-by-example.md) and [`intro/reference.md`](intro/reference.md): a tutorial that uses every part of the trait language, and its precise definition, with what is implemented, planned or open.
- [`glossary.md`](glossary.md): the project's terms in plain words, each with its origin in other languages or in Julia, and where it is defined precisely.

## For core developers: [`design.md`](design.md) and [`design/`](design/)

- **[`state.md`](state.md), the state of the prototype:** where traits and the facts compiler stand, the compiler changes as four mechanisms, and what is not yet established.
- **[`design.md`](design.md), the design:** the problem, the argument, traits, the rules, what Julia provides, what the evidence shows, what is not claimed, in prose. With [`design/implementation.md`](design/implementation.md) it is the source of truth: where another document disagrees with them, they win.
- **[`design/implementation.md`](design/implementation.md), the implementation in detail:** the terms, the problem in cases, the argument with its exceptions, the trait language, the three rules precisely, what Julia provides, the decisions in force, the evidence in short, the software and the next steps. Its chapters:
  - [`design/mechanisms.md`](design/mechanisms.md): the mechanisms in detail (declaring and conforming, generic implementations, `Callable`, keywords, results like the input, `Dynamic`, caching, AOT);
  - [`design/julia-changes.md`](design/julia-changes.md): every change to Julia, as built, with commits and upstream status;
  - [`design/evidence.md`](design/evidence.md): the measurements, with builds, baselines and run counts; what is not shown;
  - [`design/performance.md`](design/performance.md): where the costs come from, which owner each piece of code needs, the costs that remain;
  - [`design/comparison.md`](design/comparison.md): the choices against C++, Rust, Swift and Mojo; [`other-languages.md`](other-languages.md) is the research behind it;
  - [`intro/porting.md`](intro/porting.md): a working guideline for porters, in the design's vocabulary; part A will be rewritten for programmers.
- [`design/alternatives.md`](design/alternatives.md): designs tried, rejected or replaced, by topic, with the reasons.
- [`decisions.md`](decisions.md): the decisions in force, by topic, with their origins; the superseded rows at the end.
- [`open-issues.md`](open-issues.md): what is open; decisions waiting for the user first (§1); closed items at the end.
- [`glossary.md`](glossary.md): every term with its origin and precedents, and a link to its precise definition.

## For agents: [`record/INDEX.md`](record/INDEX.md)

Every review, exploration, plan, findings section and session note, with its date, its status and what supersedes it, and where to look for a decision's history, a measurement's raw numbers or an experiment's scripts. The record stays where it is (`reviews/`, `explorations/`, `plans/`, `design-findings.md`, `../session-notes/`), since many documents cite those paths.

## Conventions

- **Terms** as in `design/implementation.md` §1 (trait, implementation, receiver type, key, trait object, entry, worker, fact, run-time site, owner, stakeholder, pirate). "Representation" and "projection" belong to the design before keys, and appear only in history.
- **Writing:** short sentences, bullets for anything with more than two parts, one idea per sentence, no unexplained jargon; documents for programmers avoid the core developers' terms.
- The machine is shared: one Julia job at a time, at `nice -n 19`; full builds alone, under a memory guard.
