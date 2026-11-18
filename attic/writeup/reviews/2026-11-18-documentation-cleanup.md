# The documentation clean-up, reviewed

**What this is:** the main session's review of its own clean-up (W-162; [the plan](../plans/2026-11-18-documentation-cleanup.md)), written at its end on 2026-11-18. It says what each part did, how it was checked, what it found, and what it leaves. It is not an independent review: the same session did the work. A reader from outside is still owed (§6).

**The user's words that set it:** "At this point unified _is_ the implementation. The documentation should describe the intended design. The to-dos and the experiments lists and similar stuff should be cleaned up. The experiments list needs to show the experiments of the current implementation. The baseline is plane Julia and Python, not previous iterations of the design. We need to get rid of all reviews and plans that are not relevant anymore, they can go into an attic. The most relevant insights should be extracted into alternatives considered, lessons learned and similar documents."

## 1. What was done, by part

| Part | What | Result |
|---|---|---|
| 0 | the lint, the plan adopted | `experiments/tools/doclint/` counts what the rules forbid; `anchors.py` checks links with anchors |
| 1 | the harvest: every plan, review and exploration read before it moved | [the notebook](../record/harvest-2026-11.md): an entry per document, 110 lessons, 46 checks against the documents; [the lessons](../design/lessons.md); [the alternatives](../design/alternatives.md) in eleven chapters; [the proofs](../design/proofs.md); [the context](../record/context.md); [the playbook](../record/playbook.md) |
| 2 | the move | 78 plans, 73 reviews, the explorations and four retired pages under `attic/writeup/` at their paths; [the attic's index](../../attic/README.md) by era, a line per document |
| 3 | the record | the registry by goal (106 rows; 329 in the ledger); the decision log by the part of the design (283 rows; 209 in the ledger); the work queue (9 open items); the open issues as what is open; the performance explorations of this implementation |
| 4 | the evidence, the goals, the rationale, the results | each number against plain Julia or Python, with its build and experiment; what is not shown under each goal; twelve tensions that stand |
| 5 | the references | a status line is one word and its deviation rows; no commit, date, work item or name in a reference; 279 retired rows in the ledger; what left the references is in `record/build-notes/` |
| 6 | the front, the teaching, the glossary, the comparison, the inventory | the two teaching pages and the porting guideline on the box and the wrapper, with examples and quotes that run; the comparison with other languages on the design as it is; the inventory of Julia's commits for the current line |
| 7 | the workspace | merged worktrees and branches removed; the tag `pre-unified` on the earlier line of each repository |
| 8 | this review; the checks; the proposal for `CLAUDE.md` | below |
| 9 | the names | the library, the demonstrators and the forks without `-unified`; the earlier checkouts under `pre-unified/`; `experiments/implementation/` ([the plan](../plans/2026-11-18-names.md)) |

## 2. How it was checked

- **The lint** on the current documents. The columns for commits, work items, plan rows, branches and the user's words in the references: 0. Broken links: 0. Links with a missing anchor: 0.
- **What the lint still counts, and why it stays:**
  - "decided", "replaced by", "built on" as verbs of the design ("decided when the code is compiled"): the references, the rationale, the proofs, the goals;
  - the names of the trees and tags where a document is about them: the setup page, the state, the record's index, the registry's head (`julia-1.13`, `prototype-2026-11`);
  - the inventory of Julia's commits ([julia-changes](../design/julia-changes.md)): its rows name commits, dates and the experiments of their day. It is a ledger of commits;
  - experiments of the ledger cited by an open issue as its case (13), and by the evidence in "measured only on the library of October 2026" lines (8);
  - one link from each reference to the ledger of retired rows.
- **Conservation, by script:** every experiment ID, every decision row, every open issue number, every tension and every status line of the documents before the clean-up is in the current document or in its ledger. Every number in a kept registry row stands in that experiment's old row; every number of the evidence stands in the old evidence or the registry.
- **Two rows of the evidence read against their logs** (E-392, the nine loads; E-443, an operation on a box): the numbers are the logs'.
- **What runs, after the rename, on `next` 32a2235abd:**

  | What | Result | Log (`experiments/implementation/`) |
  |---|---|---|
  | the gates in force (71) | 67 pass; four assert rules the design replaced (open issue 237) | `logs/names-2026-11-18/gates.log` |
  | the stage gates (`gate_deep`, `gate_d11`, the four check gates) | pass | `w161/logs/names-summary.log` |
  | the library's suite | 93 testsets pass | `logs/names-2026-11-18/traitworld.log` |
  | the ODE library's suite; TraitMakie's | 35 testsets; 8 testsets; pass | `w161/logs/names-summary.log` |
  | NetworkDynamics' subset | as before the rename, with its known failures | the same |
  | the forks' session digests | equal to upstream's at 26 steps | `w161/logs/names2-summary.log` |
  | the examples of `intro/` | intro 24, tutorial 94, strict 5 pass; 4 marked deviations | `logs/names-2026-11-18/examples-*.log` |
  | the porting guideline's quotes against the ports' files | 0 problems | `experiments/docs-checks/check_quotes.py` |
- **The website's sources** prepare without error (355 documents; every navigation entry exists). The site itself is built by the repository's workflow; `mkdocs` is not installed on this host, so the build was not run here.

## 3. What the clean-up found

Each is recorded where it belongs; none was fixed at the case.

| Finding | Where |
|---|---|
| **A crash:** the tutorial's script ends with a segmentation fault in 2 of 6 runs, in dispatch's cache. Memory unsafety in the changed runtime | [open issue 234](../open-issues.md#4-runtime-and-measurements); W-163, before anything is measured |
| **Four gates assert rules the design replaced** (`Callable` by its methods; a declared result from the trait's method). "The gates pass" had meant the stage's own gates | open issue 237; the playbook §3 |
| The forks' digests differed from upstream's after the images were rebuilt: the digest used `hash`, which mixes in a type's identity | fixed in the check (`forks/scripts/session_check.jl`); the playbook §4 |
| The teaching pages taught the attribute and the casts; two of their examples failed on the head | the pages rewritten; the scripts run |
| A message of the definition-time check prints the compiler's tuple type; `withfields` at a box is not defined | open issues 235, 236 |
| Status lines that were stale: a membership taken back, the split at an intersection, the kept forms ("Planned" though built); the per-site cache's exact-type entries ("Implemented" though not carried) | corrected in the references |
| Five unacted findings of earlier reviews | open issues 229 to 233 ([the dispositions](../record/harvest-dispositions-2026-11.md)) |
| The goals and the evidence named a deviation row as open that is retired (compiler C-104) | removed |

## 4. The choices made (mine)

The decision log's row "The clean-up's choices made while it ran" lists them. The ones a reader should know:
- **The reading.** Documents to 2026-10-21 were read in full; later ones by status, summary, findings and results. Every archived document has a notebook entry.
- **Agents** did what can be checked by script: the registry's rows, the classification of decision rows, the open issues' rewrite, the evidence by goal, the references' pass, the teaching pages with their examples, the comparison with other languages, the repositories' READMEs. Each result was checked by the main session for conservation, numbers and anchors. Their prose was read in part, not line by line.
- **"Optional"** is the status of what is not built and is built only if a later decision asks: the cache across sessions, the per-site cache's exact-type entries.
- **The names.** The Julia trees and the branches keep their names; `ndport/pkgs/*-unified` keep theirs beside upstream's clones.

## 5. What is left

- **For the user:**
  - the eight commits "The README for the package as it is; its history to HISTORY.md" (one per repository of the library, the demonstrators, the forks and ndport) carry a co-author line that names a model. An agent wrote them so and they were pushed before the main session saw it. Rewriting them needs a forced push, which the harness refused; it is the user's to do or to allow;
  - the rule changes in `CLAUDE.md`: [the proposal with its diff](../plans/2026-11-18-claude-md-changes.md). In `CLAUDE.md` itself only paths were changed;
  - the default branch of each repository on GitHub (`unified`; for julia, `next`): a repository setting, not changed from here.
- **Not verified:**
  - compiler §10.4's hook at a miss of the split's table reads "Implemented"; the code was not read;
  - the notebook's checks C-3, C-10, C-17 to C-19, C-26, C-28, C-30: each resolved as "not measured" or "in part", with where it is recorded;
  - the agents' sentences marked as possibly stale in the references ([the notebook](../record/harvest-2026-11.md), "The references").
- **Not done:**
  - TraitTables, TraitCSV and TraitReport are not on the design's one way to erase (traits T-128; W-156). The teaching pages mark two deviations of the library (T-126, T-127);
  - the build output of `julia-1.13` is kept (1.9 GB);
  - scripts of the demonstrators that still name a Julia of an earlier line by default: TraitMakie's and TraitReport's `scripts/session.sh`, TraitReport's `measure.sh`, the forks' `check_session.sh` and `testsuites.sh` (each takes the Julia as an argument or a variable), ndport's `u_workload.sh` and `r5_workload.sh`. Each README says how to run on `julia-next`;
  - TraitReport's `src/TraitReport.jl` calls `TraitWorld.@workload`, which the library does not define: one of its forms may not load. It goes with the demonstrators' conversion (W-156);
  - the experiments' directories of the earlier library that a current script still reads stay where they are (`experiments/README.md` lists them).

## 6. What an independent reader should do next

- Read `intro/` as a programmer who has not seen the project, and the references as a core developer. The clean-up removed what the lint can count; whether the pages teach is not measured (G-8).
- Check ten more rows of the evidence against their logs.
- Run `python3 experiments/tools/doclint/doclint.py` and `anchors.py` before each commit to a current document.

## Addendum, 2026-11-18, later the same day

The user read the report and answered: "Go ahead with the Claude proposal. I will take care of GitHub. Continue the work using an Opus subagent. We won't have an outside reader so remove that. The work log should be more for things you can do."

What was done with each point of §5 and §6:
- **The rule changes in `CLAUDE.md`** are applied as proposed. Two lines were added with the user's words of that answer: one Opus agent at a time for the work of the queue; the work queue holds only work an agent can do.
- **The default branch on GitHub** is the user's.
- **The eight commits whose co-author line names a model** are a question for the user ([the open issues §1](../../../writeup/open-issues.md#1-questions-for-the-user)).
- **§6 is withdrawn:** there will be no reader from outside. The evidence and the goals say that teaching is not tested; the work queue's item on daily use and the next iteration's plan no longer name a reader.
- **The crash** is W-163, running; **the four gates** are W-164.
- **The work queue** was rewritten for what an agent can do, each item with its first step. W-162 is closed. W-110 (keys) left the queue as deferred.
- This review, the clean-up's plan, the plan for the names and the proposal moved to the attic with W-162's closing.

