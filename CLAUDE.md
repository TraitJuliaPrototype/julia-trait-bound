# Rules for agents: the documents

This directory is the design repository of trait-bound Julia. Beside `writeup/` it holds the other repositories of the workspace, each its own git repository: Julia with the design's changes, the library (TraitWorld), the demonstrators and `experiments/`. Which tree holds which branch, and the standing constraints of the machine: [`writeup/record/INDEX.md`](writeup/record/INDEX.md). For an agent that starts cold: [`writeup/record/context.md`](writeup/record/context.md) (why the rules are what they are) and [`writeup/record/playbook.md`](writeup/record/playbook.md) (how the work is done).

**The principle: every kind of fact has one home.** Every other document links there. A copy (a number, a status, a rule) names its source and build, or it goes stale.

**The current intended state, not the history.** The references, and every document that is not explicitly about the history (`design.md`, the glossary, `intro/`, `goals.md`, `state.md`, the evidence, the comparison, the open issues, the work queue, the registry), describe the current intended state of the design, plus the deviations of the implementation from it. Four rules (2026-11-18, the user: "At this point unified _is_ the implementation. The documentation should describe the intended design."; "The baseline is plane Julia and Python, not previous iterations of the design."):
- **One implementation.** A current document does not say "the unified build", "the earlier build" or "the prototype". It says the implementation, Julia, the library, and names a branch only where a number needs its build.
- **No chronology.** Not what was removed, replaced or decided against, not how a rule came about: no "was", "until <date>", "no longer", "superseded"; no date, commit, work item or "decided by" in a rule's text. Those have their own places: `design/alternatives.md` (what was considered, rejected or replaced, with the reason), `design/lessons.md` (what the work taught), the decision log, the agents' tier (`record/context.md`, `record/build-notes/`), reviews, plans, session notes and the attic.
- **A baseline is plain Julia or Python.** Plain Julia is vanilla v1.13.2, or plain code on the build. A comparison with an earlier iteration of the design is a regression control: it lives with its gate and in the registry's controls, not in the evidence, the goals, the state or `intro/`. (The user: "measuring a set of changes against the immediate predecessor is of course fine during regression testing and performance work.")
- **What is no longer relevant goes to the attic,** after its insights are in the lessons and the alternatives. It keeps its path under `attic/` and leaves no "Moved" page. The lint `experiments/tools/doclint/` counts what these rules forbid.

**The demonstrators follow the design.** A demonstrator already built never constrains the design. When the design changes, the demonstrators are changed to follow it. Experience from writing idiomatic trait code in Julia feeds back into the design only through review: an open issue or a proposal, decided like any other change.

**Principled solutions; the ports find the design's weak points.** The guiding principle is principled solutions. One purpose of the ports (SciML, Makie, DataFrames) is to find where the trait design is weak. Do not design a port around such a point. Record it as an open issue, with the case, the rule that blocks it and a proposal. A tweak in the trait design that enables a principled solution in a port's architecture is the most valuable finding there is. A port's change that applies a rule of the references is the port following the design, not a workaround: measure it and merge it (the lesson of the `IO` episode, [`writeup/design/lessons.md`](writeup/design/lessons.md) §5).

**A failure names a pattern** (2026-11-09, the user: "When we see failures like this, also think about principled fixes or new tools that reveal common patterns"). When a test, gate or measurement fails, look past the one case:
- name the pattern it belongs to, and the rule that produces it;
- propose the principled fix at that rule, not a patch at the case;
- where the pattern can recur, build a tool that finds every instance, and keep it in the experiments repository with a README (as `experiments/implementation/audit/`). The open issue records the tool and its counts.

**The goals direct the work** (2026-11-10, the user: "The entire point of this project is to show that Traits and Facts actually enable dramatically reducing (re) compilation and potentially improve speed and caching with limited to no downsides and better error messages and better AOT compilation experience. We also want to show that there is a clean and doable path for the ecosystem to transition with clear potting guidelines. Finally unification made the design of the Trait system dramatically simpler, making it easy to teach."). The goals, the claim on each axis and where each stands are [`writeup/goals.md`](writeup/goals.md). The order of work follows the weakest axes (the user: "Clean up our experiment, decisions and work/todo log to reflect the aim to build towards that goal, prioritising weakest spots.").

**The schedule.** The first schedule (the user, 2026-11-11: "The strategy should be to build the complete prototype. Then thoroughly measure it, and then do some performance work as long as it doesn't increase the code complexity too much.") is finished: the tag `prototype-2026-11`. The order of work now is the stages of [the next iteration](writeup/plans/2026-11-15-next-iteration.md); the items: `writeup/record/todo.md`. **Daily use is finished before the freeze** (2026-11-21, the user: "I support continuing the ODE program until it reaches 0 errors using only principled fixes. We are in no rush to get to stage 7."): the ODE program builds as a trimmed binary with 0 errors, by fixes at a rule of the design or by the port following the design, never by a patch at the case; the freeze and its round (W-159) wait for it.

**The cache across sessions is not built now** (2026-11-14, the user: "We don't build the cross session cache now. The measurement campaign should contain workloads that would exercise it and break down times in such a way that we can make a clear judgment."). The measurement round (W-145) carries those workloads: code of several packages first combined in a session, each compile's time attributed so that what an image holds, could hold or cannot hold is told apart.

**The speed work is retired; no claim of better steady-state speed** (2026-11-10, the user: "I don't want to claim better steady state speed, just no regression/the possibility to opt into full speed (compiled_for(x))."; 2026-11-11: "The speed work and performance things that are on hold probably should all be retired permanently.", "we retire the speed items, but of course we can later look into the attic to get inspiration for other things that could be done."). The claim is no regression where types are known, and full speed by opting in (`compiled_for(x)`). No work item pursues speed. Speed is measured only as a control. The performance explorations log is an archive. Performance work is one phase after the measurement round: fixes that add little code (W-146). **Workloads** (2026-11-08, the user: "Specific precompile workloads, unless they genuinely cover broad typical cases (String, Int Columns) are cheating."): a package image's workload counts only where it covers broad typical cases. [the decision log](writeup/record/decisions.md), "The project: the goals, the claims, speed, measuring".

**Principled ways of making the design fast** (2026-11-15, the user, on the compiler's part of one way to erase: "Yes please. Build the compiler for P1 and be cogniszent of finding principled ways of making the design fast."). The rule above stands: no claim of better steady-state speed, no patch at a case. While building the design's mechanisms, look for where a rule of the design itself lets the compiler do less (a membership test decided with an edge, a box that needs no heap, a check read from an instance that exists). Take such a way where it follows from a rule and adds little code. Record the others with their measurement and a proposal ([open issues](writeup/open-issues.md); a tension where a goal pays).

**Record a tension between the goals; do not resolve it at the case** (2026-11-10, the user: "I want to continue the strategy of recording pressure and tension between the goals (as we did for pushback on the design from speed and port work). The goal is not for me to review this bit by bit but to eventually create a synthesis, and iterate the design from all the evidence collected."; it widens the rule of 2026-11-08: "Where a design decision makes speed difficult to achieve, flag that for me to review."). Where a rule of the references, or a choice marked mine or the user's, sets one goal against another (a slowdown, a cost at load, a port that the rule blocks, a message that the mechanism cannot give), list it in `writeup/open-issues.md` §2, "Tensions between the goals", with the rule, its measured cost and a proposal, and add its row to the index in `writeup/goals.md` §3. Do not work around it in the implementation or a port. **A change that touches Base, or erases a type the whole ecosystem specializes on, is flagged before it is built:** its decision row names the guarantees for plain code it touches ([facts](writeup/reference/facts.md) §2, §13), and a proxy measured first says what it does not model.

**The agent's choices are not reviewed one by one** (2026-11-10, the user: "I don't want to review all decisions made by you."). A choice made while building stands as recorded: the reference, and the decision log marked "mine". Open issues §3 lists it as input to the synthesis (`writeup/goals.md` §4). Only a question the work cannot continue without is put to the user.

## Where each kind of content goes

| Content | Its home | Rule |
|---|---|---|
| The intended design: syntax, meaning, rules, guarantees, Julia's interfaces, the lowering | `writeup/reference/` (traits, facts, compiler, lowering; the optional extensions) | The source of truth. Each section ends with a status line: one word (Implemented, Planned, Optional, Open) and the deviations that qualify it. No commit, date, work item or name in it. Conventions: `writeup/reference/README.md`. |
| Where the code falls short of a reference | that reference's Deviations table | Stable IDs (T-, F-, C-, L-). The table lists open rows; a row names code or a test. A retired row leaves the table for the ledger. |
| Where a rule is in the code, the commits that built it, its gates, who decided it | `writeup/record/build-notes/<reference>.md`, by the reference's section | The agents' tier. Never the only home of the rule. |
| A decision | first the reference, then a row in `writeup/record/decisions.md` | A decision that is not in a reference is not in force. The log row quotes the user's words verbatim, gives the date, and names the reference sections it changed. |
| The goals, the claim on each axis, where each stands | `writeup/goals.md` | The standing links to the evidence for numbers and to the work queue for work. Updated in the commit that changes an axis's standing. |
| A tension between the goals | `writeup/open-issues.md` §2, "Tensions between the goals" | The rule, its measured cost (E-n), a proposal. Its row in the index, `writeup/goals.md` §3, with a stable `GT-n`. |
| A decision waiting for the user | `writeup/open-issues.md` §1, "Questions for the user" | The reference marks it Open and links the issue; it does not describe a guess. |
| A choice an agent made while building | the reference, and the decision log marked "mine" | Also listed in `open-issues.md` §3 as input to the synthesis; it does not wait for the user's review. |
| An alternative considered, rejected or replaced | `writeup/design/alternatives.md`, by topic | With the reason and, where measured, the experiment's ID. The references never mention alternatives. |
| What the work taught | `writeup/design/lessons.md` | Short, for people: one sentence per lesson, what it rests on, its experiment. The long form is in the agents' tier. |
| An experiment | a row in `writeup/record/experiments.md`, by goal; scripts and logs in `experiments/<dir>/` | The row comes before the run: the question, the baseline (plain Julia or Python), and the result that would change the design. When done: the build and the outcome with its key numbers; the write-up is the directory's README. Logs are committed; never only in `/tmp` or a scratchpad. A row that a later one replaces, or whose mechanism is gone, moves to the ledger. A proxy's row names what it does not model. |
| The current numbers behind a claim | `writeup/design/evidence.md`, by goal | Each number is against plain Julia or Python and cites its experiment (E-n) and build. Other documents link to it rather than copy. |
| Performance work the rule for performance work does not take up now | `writeup/record/performance-explorations.md` | An ID PE-n; what it is, what was measured (E-n), why not now, what would make it worth pursuing. An entry that returns to the queue names its W-item and stays. |
| Agreed work (a todo) | `writeup/record/todo.md` | Open items only, and only work an agent can do (2026-11-18, the user: "The work log should be more for things you can do."): what waits for the user is a question in the open issues §1; what needs a person from outside is not an item. A stable ID `W-n`, the source (the user's words), a status, links to the open issue, experiment or decision it serves. A closed item moves to the ledger with its last row. |
| An open question | `writeup/open-issues.md` | Open items only, each as it stands: the rule, the cost with its experiment, the proposal. Numbered, stable. When resolved, it moves to the ledger with the resolution and a link. |
| What is built now | `writeup/state.md` (the heads, what is built, the suites, what is next) and the Deviations tables | The one home of the heads. Changes to Julia: `writeup/design/julia-changes.md`, with commits. |
| Why the guarantees hold | `writeup/design/proofs.md` | It states no rule; it derives the guarantees of `reference/facts.md` from a model. |
| Why the design has its shape | `writeup/design.md`, the rationale | It cites the references for rules and the evidence for numbers, and states no rules of its own. |
| The design against other languages | `writeup/design/other-languages.md` | Claims about other languages cite primary sources or `writeup/record/other-languages-research-2026-10-16.md`. |
| Teaching | `writeup/intro/` | Current state only: no history, no core developers' terms. Its examples run in `experiments/docs-examples/`. |
| A review | `writeup/reviews/<date>-<topic>.md` while it is live | Not edited after it is written, except by a dated addendum that says what was done with each finding and where (a deviation row, an open issue, a commit). When every finding has its place, the review moves to the attic. |
| A plan or proposal | `writeup/plans/<date>-<topic>.md` while it is live | A status line at the top: proposal, adopted, done, superseded. Not normative. A plan that is done or superseded moves to the attic. |
| The chronology, and the user's words in full | `session-notes/` | Never the only home of a fact. |
| Guidance for agents: how to work, the user's standing preferences | this file, or the document in this table that owns the subject | Never only in Claude Code's project memory (see below). |
| Terms | `writeup/glossary.md` | The reference defines a term where it first matters; the glossary links there. |
| History | `attic/` (its `README.md` is the index, by era, with a line per archived document), `writeup/record/design-history.md`, `writeup/record/context.md` | Kept out of the references, `design.md` and `intro/`. |
| What is closed: closed work items and issues, superseded decisions, retired deviation rows, the experiments of earlier builds | the ledgers in `attic/writeup/record/` | Rows unchanged, IDs permanent. |
| How the work is done; why the rules are what they are | `writeup/record/playbook.md`; `writeup/record/context.md` | The agents' tier: it may hold chronology and the user's words; it is never the only home of a rule, a number or a decision. |

## Rules across documents

1. **Change together, in one commit.**
   - A decision: the reference and the decision log.
   - A fix that closes a deviation: retire the row, flip its expected-failure check, update `state.md`.
   - A finished experiment: its registry row and its evidence row.
2. **Look for stale copies before finishing.** Grep every repository for the IDs, terms and numbers you changed; fix or remove each copy. Reviews, plans and session notes are history: leave them.
3. **Precedence:** references, then `design.md`, then the evidence, then the record. A lower document that disagrees is fixed, or the disagreement becomes a deviation row or an open issue. It is never left standing.
4. **IDs are permanent.** T-, F-, C-, L-, E-, W-, GT- and open-issue numbers are never renumbered or reused. A retired or closed row lives in its ledger (`attic/writeup/record/`) with its text; the current document names the retired IDs in one line.
5. **A number says what it measures:** the build (commit), the setting (product, or the test bed `all`), strict mode on or off, the load order, the number of runs, the machine's load. And whether it measures interop (trait code calling plain code) or idiomatic trait code.
6. **Demonstrator and experiment READMEs** say how to run, and keep dated tables of their own results. For current numbers they link to the evidence.
7. **A single document that moves leaves a short "Moved" page at its old path;** current documents get their links updated. **A move to the attic keeps the path** (`writeup/plans/x.md` becomes `attic/writeup/plans/x.md`) **and leaves no page:** the attic's index states the rule once.

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

**No subagents on the shared host** (2026-11-06, the user: "no subagents on this machien please"). Reviews, audits and plans that the record assigns to an agent are done in the main session, and say so. The exceptions:
- a Fable review of a really high-impact choice made at a gate (below);
- the plan for the next iteration is implemented by agents on Opus, directed by the main session (2026-11-15, the user: "Have Opus agents implement the plan"). Who works in which tree, and the ranges of IDs: [the plan](writeup/plans/2026-11-15-next-iteration.md) §6. An agent starts no agent of its own, and keeps every other rule of this file.
- the work of the queue after the documentation clean-up (2026-11-18, the user, after a usage limit: "Continue with only one opus subagent at a time."; then: "Continue the work using an Opus subagent."): one Opus agent at a time, directed by the main session, in a tree of its own.
- from 2026-11-21 (the user: "delegating tasks for which it makes sense to Opus and Sonnet subagents (your judgement what is appropriate) don't run more than two subagents at a time, pay attention to the overall load on this machine."): at most two agents at a time, on Opus or Sonnet as the task needs, each in trees of its own; the main session checks the load before it starts one.

**Gates do not stop the work** (2026-11-06, the user: "Okay, don't stop at gates, even if they fail. Make a choice and record it. Ask a Fable agent to review the choice but only if it is really high impact. I am going to bed. Keep implementing."):
- A gate that fails, or a gate meant for the user, does not stop the stage's work. The agent makes the choice, records it (the reference, the decision log marked "mine", open issues §3 as input to the synthesis) and continues.
- Only for a really high-impact choice, a `fable-critic` agent reviews it; the review is written to `writeup/reviews/` as any review.

**No excessive benchmarking.** Run quick tests, a few minutes at most and less where feasible, chosen to reveal regressions first.

**Measurement campaigns at a freeze only** (2026-11-11, the user: "Small measurements are fine. Larger measurement campaigns that take more than a few minutes should be avoided until we have reached a conceptually complete state of the prototype."). Between freezes:
- a change is checked by the gates, the library's tests and one or two small cases that take minutes;
- a round over the ports, the unrelated loads, the sessions or every demonstrator's build waits for the next freeze (stage 7 of the next iteration). Its registry row says "registered, not run", and the work queue lists what waits.

The machine is shared. Jobs niced; full builds under a memory guard; above half load, one Julia job at a time and full builds alone. Details and the push pattern: `writeup/record/INDEX.md` ("Standing constraints") and `session-notes/00-environment-and-workflow.md`.
