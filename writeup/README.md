# writeup/

The design, written for three audiences: programmers, core developers, and agents. What is no longer current is in [the attic](../attic/README.md).

## For programmers: [`intro/`](intro/)

- [`intro/traits-for-julia.md`](intro/traits-for-julia.md): what traits are, what you write, what you get, one worked example, the costs.
- [`intro/traits-by-example.md`](intro/traits-by-example.md): a tutorial that uses every part of the trait language.
- [`intro/porting.md`](intro/porting.md): a guideline for porting a package to traits.
- [`intro/results.md`](intro/results.md): what the demonstrators show, against plain Julia and Python.
- [`glossary.md`](glossary.md): the project's terms in plain words, each with its origin in other languages or in Julia, and where it is defined precisely.

## For core developers: [`reference/`](reference/README.md), then the rest

**The references are the source of truth** for the design. Each records, apart from the design, where the implementation falls short (a Deviations table with stable IDs). Where another document disagrees with them, they win. Their conventions: [`reference/README.md`](reference/README.md).

- [`reference/traits.md`](reference/traits.md): the trait language.
- [`reference/facts.md`](reference/facts.md): the facts mode: what compiled code may assume, the guarantees, which code is compiled how.
- [`reference/compiler.md`](reference/compiler.md): what Julia's compiler and runtime provide.
- [`reference/lowering.md`](reference/lowering.md): how the trait language is built on them.
- [`reference/extensions.md`](reference/extensions.md): the optional extensions.

Explaining, measuring, comparing (not normative):
- [`goals.md`](goals.md): the goals, where each stands, the tensions between them.
- [`state.md`](state.md): what is built, the heads, the suites, what is next.
- [`design.md`](design.md): the rationale: the problem, the argument, what is not claimed.
- [`design/proofs.md`](design/proofs.md): why the guarantees hold.
- [`design/evidence.md`](design/evidence.md): the measurements, by goal, each against plain Julia or Python; what is not shown.
- [`design/julia-changes.md`](design/julia-changes.md): the changes to Julia, one row per commit.
- [`design/other-languages.md`](design/other-languages.md): the choices against C++, Rust, Swift and Mojo.
- [`design/alternatives.md`](design/alternatives.md): designs tried, rejected or replaced, by topic, with the reasons.
- [`design/lessons.md`](design/lessons.md): what the work taught.
- [`open-issues.md`](open-issues.md): what is open: questions for the user, the tensions, the agent's choices, design, implementation.

## For agents: [`record/INDEX.md`](record/INDEX.md)

The agents' tier: where each kind of fact lives, the project's context, the playbook, the build notes, the ledgers (decisions, experiments, work), the standing constraints. Nothing in the record is normative.

## Plans and reviews

`plans/` and `reviews/` hold the ones that are live. A plan that is done and a review whose findings all have their place move to the attic.

## Conventions

- **Terms** as in [`glossary.md`](glossary.md) and the references.
- **Writing:** short sentences, bullets for anything with more than two parts, one idea per sentence; documents for programmers avoid the core developers' terms.
- **Every kind of fact has one home:** [`../CLAUDE.md`](../CLAUDE.md).
