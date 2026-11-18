# The references: Julia with traits in its type system

The four references define the design. Each states the design as intended, and records apart from it where the implementation falls short. A fifth page holds the optional extensions, which no rule of the four depends on.

| Reference | Defines | Wins on |
|---|---|---|
| [`traits.md`](traits.md) | The trait language: traits as abstract types, memberships, methods, the box and the wrapper, the checks and errors, as user code sees them | What a program means |
| [`facts.md`](facts.md) | The facts mode: what compiled code may assume about other code, the guarantees, which code is compiled how | What compiled code may assume |
| [`compiler.md`](compiler.md) | What Julia's compiler and runtime provide: sets and memberships, dispatch, the kept forms and their forwarders, the facts inference, the dependency record | Julia's interfaces |
| [`lowering.md`](lowering.md) | What the trait library's macros expand to on those interfaces | Consistent with all three; it decides nothing they decide |
| [`extensions.md`](extensions.md) | Optional extensions: keys, code shared among members the contract sees alike | Nothing: no rule of the four depends on it |

Where another document disagrees with the references, they win. Why the design has this shape: [the rationale](../design.md); why the guarantees hold: [the proofs](../design/proofs.md).

## Conventions for every reference

**The intended design.** Each section states the design as intended, whether or not it is built:
1. the syntax or the interface;
2. its meaning;
3. its rules and checks, and when they apply;
4. a short example where it helps;
5. a status line.

**The status line** is one word and the deviations that qualify it: "**Status:** Implemented, but for T-105."
- **Implemented:** in the implementation: Julia with the design's changes, or the trait library on it. The heads are in [the state](../state.md#today).
- **Planned:** decided, not built. A guarantee the design commits to is Planned, however late it is delivered.
- **Optional:** a mechanism built when a measurement or a later decision asks for it. User code may not rely on what it would give until it is Planned.
- **Open:** not decided; the line links [the open issue](../open-issues.md).
- Where parts of a section differ, the line names the part: "Implemented; a membership taken back: Planned."
- The line may name the gate or test that checks the rule. It holds no commit, branch, date, work item or name of who decided. Those are in [the build notes](../record/build-notes/), by section.

**Guarantees and their mechanisms.** A guarantee is a promise to user code: what is accepted or refused, which method runs, what compiled code may assume, what a membership or a load does to compiled code. It is stated in `traits.md` or `facts.md`. The mechanism that delivers it is in `compiler.md`.

**Deviations apart.** Each reference ends with a table, one row per place where the implementation differs from it: `ID | Section | The reference says | The implementation does | Where`.
- IDs are stable (`T-n`, `F-n`, `C-n`, `L-n`) and never reused.
- The table lists the open rows. A row names code or a test.
- A retired row leaves the table. Its ID stands in one line below the table, and its text is in [the ledger](../../attic/writeup/record/deviations-retired.md).

**The current intended state, plus deviations.** No history, no alternative that was not taken, no measurement beyond a number that is part of the design (the split's limit of four). The evidence is in [`../design/evidence.md`](../design/evidence.md); what was not taken, in [`../design/alternatives.md`](../design/alternatives.md).

**Writing:** short sentences, one idea per sentence, bullets for anything with more than two parts. [`traits.md`](traits.md) serves programmers too: it explains a core developer's term in a plain sentence where it uses one.

## What goes where

- **A rule a user can observe** (accepted or refused, which method runs, which error, which code is shared): `traits.md`. How it is achieved: `lowering.md` and `compiler.md`.
- **What compiled code may assume** (facts, run-time sites, edges, invalidation, pirates as they affect validity): `facts.md`. Who may write a method or declare a membership, and the errors a user sees for it: `traits.md`.
- **An interface of Julia's** (a type-system rule, a compilation signature, a calling convention, a hook, what an image keeps): `compiler.md`, with its semantics.
- **What a macro of the library defines:** `lowering.md`.

## Who chose what

A rule of the references was decided by the user or chosen by an agent while building. Neither is said in the references. The decisions are in [the decision log](../record/decisions.md); the agent's choices are listed in [the open issues](../open-issues.md) as input to the next synthesis, and in [the build notes](../record/build-notes/choices.md) with their dates.
