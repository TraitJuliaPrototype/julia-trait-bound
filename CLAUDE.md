# Rules for agents: the documents

This directory is the design repository of trait-bound Julia. Beside `writeup/` it holds the experiments repository (`experiments/`), the patched Julia (`julia-1.13/`), TraitWorld and the demonstrators, each its own git repository. The map of the record, with the standing constraints of the machine, is [`writeup/record/INDEX.md`](writeup/record/INDEX.md).

**The principle: every kind of fact has one home.** Every other document links there. A copy (a number, a status, a rule) names its source and build, or it goes stale.

**The current intended state, not the history.** The references, and every document that is not explicitly about the history (`design.md`, the glossary, `intro/`, `state.md`, the evidence, the comparison, the open issues, the work queue), describe the current intended state of the design, plus the deviations of the implementation from it. **Never the history:** not what was removed, replaced or decided against, not how a rule came about, not "was", "until <date>", "no longer", "superseded". Those have their own places: `design/alternatives.md` (what was considered, rejected or replaced, with the reason), the decision log, `record/design-history.md`, reviews, plans and session notes.

## Where each kind of content goes

| Content | Its home | Rule |
|---|---|---|
| The intended design: syntax, meaning, rules, guarantees, Julia's interfaces, the lowering | `writeup/reference/` (traits, facts, compiler, lowering) | The source of truth. Intended shape first; each section has a status line (Implemented, Planned, Optional, Open). Conventions: `writeup/reference/README.md`. |
| Where the code falls short of a reference | that reference's Deviations table | Stable IDs (T-, F-, C-, L-). A row names code, a commit or a test. |
| A decision | first the reference, then a row in `writeup/record/decisions.md` | A decision that is not in a reference is not in force. The log row quotes the user's words verbatim, gives the date, and names the reference sections it changed. |
| A decision waiting for the user | `writeup/open-issues.md` §1 | The reference marks it Open and links the issue; it does not describe a guess. |
| A choice an agent made while building | the reference, and the decision log marked "mine" | Also listed in `open-issues.md` §1 for the user to confirm. |
| An alternative considered, rejected or replaced | `writeup/design/alternatives.md`, by topic | With the reason and, where measured, the experiment's ID. The references never mention alternatives. |
| An experiment | a row in `writeup/record/experiments.md`; scripts and logs in `experiments/<dir>/` | The row comes before the run: the question, and the result that would change the design. When done: the outcome with its key numbers, the build, the write-up (the directory's README). Logs are committed; never only in `/tmp` or a scratchpad. |
| The current numbers behind a claim | `writeup/design/evidence.md` | Each number cites its experiment (E-n) and build. Other documents link to it rather than copy. |
| Agreed work (a todo) | `writeup/record/todo.md` | A stable ID `W-n`, the source (the user's words), a status, links to the open issue, experiment or decision it serves. `state.md` §6.3 gives the order in brief. |
| An open question | `writeup/open-issues.md` | Numbered, stable. When resolved, it moves to "Closed items" with the resolution and a link. |
| What is built now | `writeup/state.md` (current state only) and the Deviations tables | Changes to Julia: `writeup/design/julia-changes.md`, with commits. |
| Why the design has its shape | `writeup/design.md`, the rationale | It cites the references for rules and the evidence for numbers, and states no rules of its own. |
| The design against other languages | `writeup/design/other-languages.md` | Claims about other languages cite primary sources or `writeup/record/other-languages-research-2026-10-16.md`. |
| Teaching | `writeup/intro/` | Current state only: no history, no core developers' terms. Its examples run in `experiments/docs-examples/`. |
| A review | `writeup/reviews/<date>-<topic>.md` | Not edited after it is written, except by a dated addendum. Record what was done with each finding where it was done (a deviation row, an open issue, a commit). List it in the record index. |
| A plan or proposal | `writeup/plans/<date>-<topic>.md` | A status line at the top: proposal, adopted, done, superseded. Not normative. |
| The chronology, and the user's words in full | `session-notes/` | Never the only home of a fact. |
| Terms | `writeup/glossary.md` | The reference defines a term where it first matters; the glossary links there. |
| History | `attic/`, `writeup/record/design-history.md` | Kept out of the references, `design.md` and `intro/`. |

## Rules across documents

1. **Change together, in one commit.**
   - A decision: the reference and the decision log.
   - A fix that closes a deviation: retire the row, flip its expected-failure check, update `state.md`.
   - A finished experiment: its registry row and its evidence row.
2. **Look for stale copies before finishing.** Grep every repository for the IDs, terms and numbers you changed; fix or remove each copy. Reviews, plans and session notes are history: leave them.
3. **Precedence:** references, then `design.md`, then the evidence, then the record. A lower document that disagrees is fixed, or the disagreement becomes a deviation row or an open issue. It is never left standing.
4. **IDs are permanent.** T-, F-, C-, L-, E- and open-issue numbers are never renumbered or reused. A retired deviation row stays as its ID, marked *Retired*, with a pointer to what holds its subject now; it tells no story of what it was (that is in the record).
5. **A number says what it measures:** the build (commit), the setting (product, or the test bed `all`), strict mode on or off, the load order, the number of runs, the machine's load. And whether it measures interop (trait code calling plain code) or idiomatic trait code.
6. **Demonstrator and experiment READMEs** say how to run, and keep dated tables of their own results. For current numbers they link to the evidence.
7. **A moved document leaves a short "Moved" page at its old path,** because reviews and session notes cite paths; current documents get their links updated.

## Writing

- Short sentences, one idea per sentence, bullets for anything with more than two parts.
- Terms as in the glossary and the references. Explain a core developers' term in a plain sentence where `intro/` or `reference/traits.md` uses it.
- Never promise inlining. Names from the API user's perspective. No hidden type parameters.
- Do not write the user's account e-mail address anywhere. Commits use the configured identity.

## Working on this machine

**No excessive benchmarking unless the work is specific performance work.** Otherwise run quick tests, a few minutes at most and less where feasible, chosen to reveal regressions first.

The machine is shared. One Julia job at a time, niced; full builds alone, under a memory guard. Details and the push pattern: `writeup/record/INDEX.md` ("Standing constraints") and `session-notes/00-environment-and-workflow.md`.
