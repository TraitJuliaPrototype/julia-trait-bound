# The references

The four references define the intended shape of the design. For that shape they are the source of truth: where any other document disagrees with them, they win. Each one also records, separately, where the current implementation deviates from it.

| Reference | Defines | Wins on |
|---|---|---|
| [`traits.md`](traits.md) | The trait language: syntax, meaning, checks and rules, as user code sees them | What a program means |
| [`facts.md`](facts.md) | The facts mode: what compiled code may assume, the guarantees, and which code is compiled how | What compiled code may assume |
| [`compiler.md`](compiler.md) | What Julia's compiler and runtime provide: the interfaces the other three build on | Julia's interfaces |
| [`lowering.md`](lowering.md) | How the trait language is realized on those interfaces: entries, workers, keys, trait objects, tables, images | Consistent with all three; it decides nothing they decide |

The other documents explain, measure or record; none of them is normative:
- [`../design.md`](../design.md): the rationale (the problem, the argument, what is not claimed);
- [`../design/evidence.md`](../design/evidence.md) and [`../design/performance.md`](../design/performance.md): the measurements and the cost model;
- [`../design/julia-changes.md`](../design/julia-changes.md): the inventory of Julia changes, with commits and upstream status;
- [`../intro/`](../intro/): teaching;
- [`../record/`](../record/INDEX.md): the record for agents, including the decision log.

## Conventions for every reference

**Intended shape first.** Each section states the design as intended, whether or not it is built:
1. the syntax or the interface;
2. its meaning;
3. its rules and checks, and when they apply;
4. a short example where it helps;
5. a one-line status: **Implemented**, **Planned** (decided, not built) or **Open** (not decided, linking [`../open-issues.md`](../open-issues.md)).

A Planned or Open item is written as the design intends it, not as the implementation does it today.

**Deviations separately.** Each reference ends with a section **Deviations**: a table with one row per place where the implementation differs from the reference.

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|

- IDs are stable: `T-n` (traits), `F-n` (facts), `C-n` (compiler), `L-n` (lowering). A removed row keeps its ID retired; numbers are not reused.
- A Planned item is a deviation only where the implementation does something else today (accepts it with another meaning, refuses it with a misleading error). Unbuilt and refused cleanly needs no row: the status line says it.
- "Where" names code (`file:line` in the repository), a commit, or a test.
- Tests, commits, open issues and [`../state.md`](../state.md) cite deviations by ID.

**No history, no measurements.** No "previously", no session numbers, no rejected designs (those are in [`../design/alternatives.md`](../design/alternatives.md) and the record). A number appears only when it is part of the design, such as the split limit of four.

**Terms** as in [`../glossary.md`](../glossary.md). A reference defines its own terms precisely where they first matter; the glossary links there.

**Writing:** short sentences, one idea per sentence, bullets for anything with more than two parts. [`traits.md`](traits.md) serves programmers too, so it explains the core developers' terms in a plain sentence where it uses them.

## What goes where

- **A rule a user can observe** (accepted or refused, which result, which error, which code is shared) belongs to `traits.md`. How it is achieved belongs to `lowering.md`.
- **What compiled code may assume about other code** (facts, run-time sites, edges, modes, invalidation, pirates as they affect validity) belongs to `facts.md`. Who may write a method, and the errors a user sees for it, belongs to `traits.md`.
- **An interface of Julia's** (a compiler mode, a cache, an intrinsic, a hook, a calling convention, what an image keeps) belongs to `compiler.md`, with its semantics. Why the design needs it is one sentence there, with a link.
- **The mapping** from trait constructs to Julia methods, types and caches belongs to `lowering.md`.
