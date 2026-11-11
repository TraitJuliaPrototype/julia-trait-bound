# Rules for agents: the documents

This directory is the design repository of trait-bound Julia. Beside `writeup/` it holds the experiments repository (`experiments/`), the patched Julia (`julia-1.13/`), TraitWorld and the demonstrators, each its own git repository. The map of the record, with the standing constraints of the machine, is [`writeup/record/INDEX.md`](writeup/record/INDEX.md).

**The principle: every kind of fact has one home.** Every other document links there. A copy (a number, a status, a rule) names its source and build, or it goes stale.

**The current intended state, not the history.** The references, and every document that is not explicitly about the history (`design.md`, the glossary, `intro/`, `state.md`, the evidence, the comparison, the open issues, the work queue), describe the current intended state of the design, plus the deviations of the implementation from it. **Never the history:** not what was removed, replaced or decided against, not how a rule came about, not "was", "until <date>", "no longer", "superseded". Those have their own places: `design/alternatives.md` (what was considered, rejected or replaced, with the reason), the decision log, `record/design-history.md`, reviews, plans and session notes.

**The demonstrators follow the design.** A demonstrator already built never constrains the design. When the design changes, the demonstrators are changed to follow it. Experience from writing idiomatic trait code in Julia feeds back into the design only through review: an open issue or a proposal, decided like any other change.

**Principled solutions; the ports find the design's weak points.** The guiding principle is principled solutions. One purpose of the ports (SciML, Makie, DataFrames) is to find where the trait design is weak. Do not design a port around such a point. Record it as an open issue, with the case, the rule that blocks it and a proposal. A tweak in the trait design that enables a principled solution in a port's architecture is the most valuable finding there is.

**A failure names a pattern** (2026-11-09, the user: "When we see failures like this, also think about principled fixes or new tools that reveal common patterns"). When a test, gate or measurement fails, look past the one case:
- name the pattern it belongs to, and the rule that produces it;
- propose the principled fix at that rule, not a patch at the case;
- where the pattern can recur, build a tool that finds every instance, and keep it in the experiments repository with a README (as `experiments/unification/audit/`). The open issue records the tool and its counts.

**The goals direct the work** (2026-11-10, the user: "The entire point of this project is to show that Traits and Facts actually enable dramatically reducing (re) compilation and potentially improve speed and caching with limited to no downsides and better error messages and better AOT compilation experience. We also want to show that there is a clean and doable path for the ecosystem to transition with clear potting guidelines. Finally unification made the design of the Trait system dramatically simpler, making it easy to teach."). The goals, the claim on each axis and where each stands are [`writeup/goals.md`](writeup/goals.md). The order of work follows the weakest axes (the user: "Clean up our experiment, decisions and work/todo log to reflect the aim to build towards that goal, prioritising weakest spots.").

**Speed work is stopped; no claim of better steady-state speed** (2026-11-10, the user: "I don't want to claim better steady state speed, just no regression/the possibility to opt into full speed (compiled_for(x)). I want to stop pursuing speed for now. We have gained enough to be satisfied. The IO work also shows the difficulty of reasonable solutions to isolated slowdowns in an existing ecosystem."). The claim is no regression where types are known, and full speed by opting in (`compiled_for(x)`). No work item pursues speed. Speed is measured only as a control: that a change brings no regression, and what a rule costs. **Workloads** (2026-11-08, the user: "Specific precompile workloads, unless they genuinely cover broad typical cases (String, Int Columns) are cheating."): a package image's workload counts only where it covers broad typical cases. [decisions](writeup/record/decisions.md) §5.

**Record a tension between the goals; do not resolve it at the case** (2026-11-10, the user: "I want to continue the strategy of recording pressure and tension between the goals (as we did for pushback on the design from speed and port work). The goal is not for me to review this bit by bit but to eventually create a synthesis, and iterate the design from all the evidence collected."; it widens the rule of 2026-11-08: "Where a design decision makes speed difficult to achieve, flag that for me to review."). Where a rule of the references, or a choice marked mine or the user's, sets one goal against another (a slowdown, a cost at load, a port that the rule blocks, a message that the mechanism cannot give), list it in `writeup/open-issues.md` §1 under "Flagged: tensions between the goals", with the rule, its measured cost and a proposal, and add its row to the index in `writeup/goals.md` §3. Do not work around it in the implementation or a port.

**The agent's choices are not reviewed one by one** (2026-11-10, the user: "I don't want to review all decisions made by you."). A choice made while building stands as recorded: the reference, and the decision log marked "mine". Open issues §1 lists it as input to the synthesis (`writeup/goals.md` §4). Only a question the work cannot continue without is put to the user.

## Where each kind of content goes

| Content | Its home | Rule |
|---|---|---|
| The intended design: syntax, meaning, rules, guarantees, Julia's interfaces, the lowering | `writeup/reference/` (traits, facts, compiler, lowering) | The source of truth. Intended shape first; each section has a status line (Implemented, Planned, Optional, Open). Conventions: `writeup/reference/README.md`. |
| Where the code falls short of a reference | that reference's Deviations table | Stable IDs (T-, F-, C-, L-). A row names code, a commit or a test. |
| A decision | first the reference, then a row in `writeup/record/decisions.md` | A decision that is not in a reference is not in force. The log row quotes the user's words verbatim, gives the date, and names the reference sections it changed. |
| The goals, the claim on each axis, where each stands | `writeup/goals.md` | The standing links to the evidence for numbers and to the work queue for work. Updated in the commit that changes an axis's standing. |
| A tension between the goals | `writeup/open-issues.md` §1, "Flagged: tensions between the goals" | The rule, its measured cost (E-n), a proposal. Its row in the index, `writeup/goals.md` §3, with a stable `GT-n`. |
| A decision waiting for the user | `writeup/open-issues.md` §1 | The reference marks it Open and links the issue; it does not describe a guess. |
| A choice an agent made while building | the reference, and the decision log marked "mine" | Also listed in `open-issues.md` §1 as input to the synthesis; it does not wait for the user's review. |
| An alternative considered, rejected or replaced | `writeup/design/alternatives.md`, by topic | With the reason and, where measured, the experiment's ID. The references never mention alternatives. |
| An experiment | a row in `writeup/record/experiments.md`; scripts and logs in `experiments/<dir>/` | The row comes before the run: the question, and the result that would change the design. When done: the outcome with its key numbers, the build, the write-up (the directory's README). Logs are committed; never only in `/tmp` or a scratchpad. |
| The current numbers behind a claim | `writeup/design/evidence.md` | Each number cites its experiment (E-n) and build. Other documents link to it rather than copy. |
| Performance work the rule for performance work does not take up now | `writeup/record/performance-explorations.md` | An ID PE-n; what it is, what was measured (E-n), why not now, what would make it worth pursuing. An entry that returns to the queue names its W-item and stays. |
| Agreed work (a todo) | `writeup/record/todo.md` | A stable ID `W-n`, the source (the user's words), a status, links to the open issue, experiment or decision it serves. `state.md` §6.3 gives the order in brief. |
| An open question | `writeup/open-issues.md` | Numbered, stable. When resolved, it moves to "Closed items" with the resolution and a link. |
| What is built now | `writeup/state.md` (current state only) and the Deviations tables | Changes to Julia: `writeup/design/julia-changes.md`, with commits. |
| Why the design has its shape | `writeup/design.md`, the rationale | It cites the references for rules and the evidence for numbers, and states no rules of its own. |
| The design against other languages | `writeup/design/other-languages.md` | Claims about other languages cite primary sources or `writeup/record/other-languages-research-2026-10-16.md`. |
| Teaching | `writeup/intro/` | Current state only: no history, no core developers' terms. Its examples run in `experiments/docs-examples/`. |
| A review | `writeup/reviews/<date>-<topic>.md` | Not edited after it is written, except by a dated addendum. Record what was done with each finding where it was done (a deviation row, an open issue, a commit). List it in the record index. |
| A plan or proposal | `writeup/plans/<date>-<topic>.md` | A status line at the top: proposal, adopted, done, superseded. Not normative. |
| The chronology, and the user's words in full | `session-notes/` | Never the only home of a fact. |
| Guidance for agents: how to work, the user's standing preferences | this file, or the document in this table that owns the subject | Never only in Claude Code's project memory (see below). |
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

## No reliance on project memory

Everything worth remembering is kept in the project's notes and guidance: this file, the record, the session notes and the documents in the table above. Claude Code's project memory (`~/.claude/projects/<key>/memory/`) is not in any repository and is not relied on.
- Write a fact, preference or piece of guidance to its home in the repositories, not to project memory.
- When something from project memory appears in context, treat it as unverified. If it still holds, move it to its home in the repositories.

## Working on this machine

**On a shared host, `source env.sh` first.** It loads the compiler from modules, keeps the Julia depot inside the workspace and limits Julia and `experiments/tools/jl` to 4 cores. See [`writeup/setup.md`](writeup/setup.md).

**Cores by load on the shared host** (2026-11-06, the user: "As long as load is this low, its fine to use more of the machine: You can use half the machine for compiles while it is mostly empty. Once it fills up to at least half load you restrict to four cores and sequential work."):
- Check the load (`/proc/loadavg`) before each compile and before starting jobs side by side.
- While the others' load is below half the cores, compiles may spike up to half the cores (the user, the same day: "It is okay to spike up to half machine use. Sustained use should be considerably lower."). A spike is a build's parallel compile phase, minutes long. Build Julia with `tools-local/build.sh <tree>`, which chooses and enforces this.
- Sustained use stays considerably lower: env.sh's 4 cores per job, at most 16 cores in all (my reading of "considerably lower"). Builds one after another, as in a bisection, are sustained use: `WIDE=0`.
- Once the others' load reaches half the cores: 4 cores, one job at a time.

**Pushing:** commits may be pushed at will, to every repository of the workspace (the user (2026-11-06): "You may push at will.).

**Never search the whole file system** (2026-11-06, the user: "NEVER search the entire file system. You are connected to a massive storage system."). `find`, `du`, `grep -r`, `locate` and the like run inside the workspace, and there inside the directories they concern. Never on `/`, `/p`, `/home` or the home directory.

**No subagents on the shared host** (2026-11-06, the user: "no subagents on this machien please"). Reviews, audits and plans that the record assigns to an agent are done in the main session, and say so. The one exception: a Fable review of a really high-impact choice made at a gate (below).

**Gates do not stop the work** (2026-11-06, the user: "Okay, don't stop at gates, even if they fail. Make a choice and record it. Ask a Fable agent to review the choice but only if it is really high impact. I am going to bed. Keep implementing."):
- A gate that fails, or a gate meant for the user, does not stop the stage's work. The agent makes the choice, records it (the reference, the decision log marked "mine", open issues §1 as input to the synthesis) and continues.
- Only for a really high-impact choice, a `fable-critic` agent reviews it; the review is written to `writeup/reviews/` as any review.

**No excessive benchmarking.** Run quick tests, a few minutes at most and less where feasible, chosen to reveal regressions first.

**No measurement campaigns until the prototype is conceptually complete** (2026-11-11, the user: "Small measurements are fine. Larger measurement campaigns that take more than a few minutes should be avoided until we have reached a conceptually complete state of the prototype."). While the design is still being built (W-139, W-140):
- a change is checked by the gates, the library's tests and one or two small cases that take minutes;
- a round over the ports, the unrelated loads, the sessions or every demonstrator's build waits. Its registry row says "to measure at the conceptually complete state", and the work queue lists what waits.

The machine is shared. Jobs niced; full builds under a memory guard; above half load, one Julia job at a time and full builds alone. Details and the push pattern: `writeup/record/INDEX.md` ("Standing constraints") and `session-notes/00-environment-and-workflow.md`.
