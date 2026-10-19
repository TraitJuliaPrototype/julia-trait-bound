# writeup/

The design, written for three audiences: programmers, core developers, and agents. Nothing has been deleted: superseded documents are in [`../attic/writeup/`](../attic/writeup/), and the record lists everything with its status.

## For programmers: [`intro/`](intro/)

- [`intro/traits-for-julia.md`](intro/traits-for-julia.md): what traits are, what you write, what you get, one worked example, the costs.
- [`intro/traits-by-example.md`](intro/traits-by-example.md): a tutorial that uses every part of the trait language.
- [`reference/traits.md`](reference/traits.md): the trait language reference, for programmers and core developers alike: the syntax, what it means, the rules, and what is implemented, planned or open.
- [`intro/results.md`](intro/results.md): what the demonstrators show, against fair baselines.
- [`glossary.md`](glossary.md): the project's terms in plain words, each with its origin in other languages or in Julia, and where it is defined precisely.

## For core developers: [`reference/`](reference/README.md), then the rest

**The references are the source of truth** for the intended shape of the design. Each records, separately, where the implementation deviates (a Deviations table with stable IDs). Where any other document disagrees with them, they win. Their conventions: [`reference/README.md`](reference/README.md).

- [`reference/traits.md`](reference/traits.md): the trait language.
- [`reference/facts.md`](reference/facts.md): the facts mode: what compiled code may assume, the guarantees, which code is compiled how.
- [`reference/compiler.md`](reference/compiler.md): what Julia's compiler and runtime provide.
- [`reference/lowering.md`](reference/lowering.md): how the trait language is realized on them.

Explaining, measuring, comparing (not normative):
- [`state.md`](state.md): the state of the prototype in one page.
- [`design.md`](design.md): the rationale: the problem, the argument, what is not claimed.
- [`design/evidence.md`](design/evidence.md): the measurements, with builds, baselines and run counts; what is not shown.
- [`design/performance.md`](design/performance.md): where the costs come from, and the costs that remain.
- [`design/julia-changes.md`](design/julia-changes.md): the inventory of Julia changes, with commits and upstream status.
- [`design/comparison.md`](design/comparison.md): the choices against C++, Rust, Swift and Mojo; [`other-languages.md`](other-languages.md) is the research behind it.
- [`design/alternatives.md`](design/alternatives.md): designs tried, rejected or replaced, with the reasons.
- [`open-issues.md`](open-issues.md): what is open; questions waiting for the user first (§1).
- [`intro/porting.md`](intro/porting.md): a working guideline for porters.
- [`glossary.md`](glossary.md): every term, with a link to its precise definition.

## For agents: [`record/INDEX.md`](record/INDEX.md)

The annex for agents: every review, exploration, plan, findings section and session note, with its date, status and what supersedes it; the decision log, with the user's words and the origin of every decision ([`record/decisions.md`](record/decisions.md)); where to find a measurement's raw numbers or an experiment's scripts. Nothing in the record is normative.

## Conventions

- **Terms** as in [`glossary.md`](glossary.md) and the references (trait, implementation, receiver type, key, trait object, entry, worker, fact, run-time site, owner, stakeholder, pirate). "Representation" and "projection" belong to the design before keys, and appear only in history.
- **Writing:** short sentences, bullets for anything with more than two parts, one idea per sentence, no unexplained jargon; documents for programmers avoid the core developers' terms.
- The machine is shared: one Julia job at a time, at `nice -n 19`; full builds alone, under a memory guard.
