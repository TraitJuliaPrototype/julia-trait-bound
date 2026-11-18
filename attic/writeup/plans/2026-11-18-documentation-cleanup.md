# The documentation clean-up: a plan

**Status:** done (2026-11-18; W-162 closed). Was: adopted (2026-11-18, the user, on §8's decisions: "Q1 yes, Q2 you decide, measuring a set of changes against the immediate predecessor is of course fine during regression testing and performance work. Q3 yes, Q4 yes, Q5 Clean Up the directory names as well, but do it last. Q6 you decide, Q7 check and keep. Q8 you can use subagents. But not too many in parallel. Should we also have an additional "for agents" documentation that gives more context than humans would like? Would it be possible for this session to actually do all the reading to be better able to extract relevant lessons by having maximum contextual knowledge of the project?"). W-162 in [the work queue](../record/todo.md), which holds the status of each part. Written in the main session as a proposal the same day, from a survey of every document of `writeup/`, the record, the attic, the experiments repository and the trees of the workspace. Not normative. What the adoption changed: §9.

The user (2026-11-18):

> "So I want to do some housekeeping and also clean up the documentation. Currently a lot of the documentation seems still to be written in terms of the history, and referencing the pre unified implementation. At this point unified _is_ the implementation. The documentation should describe the intended design. The to-dos and the experiments lists and similar stuff should be cleaned up. The experiments list needs to show the experiments of the current implementation. The baseline is plane Julia and Python, not previous iterations of the design. We need to get rid of all reviews and plans that are not relevant anymore, they can go into an attic. The most relevant insights should be extracted into alternatives considered, lessons learned and similar documents. Please make a comprehensive documentation clean up plan and come back to me with a thorough suggestion."

**The answer in brief.**
- Four rules, read from the request (§2). Every document is kept, rewritten, merged or archived by them (§4).
- The insights are harvested **before** anything moves (part 1). Then about 175 documents go to the attic in one move (78 plans, 73 reviews, 21 explorations, the findings log, the retired design pages).
- The registry, the work queue, the open issues and the decision log each split into what is current and a ledger in the attic. IDs stay permanent.
- The evidence is rewritten by claim, each number against plain Julia or Python.
- A small tool counts what the rules forbid, so the clean-up can be checked and stays clean.
- Eight decisions were the user's (§8); what the adoption added is §9: the record as the agents' tier, the harvest read in the main session, the directories renamed last.

## 1. What the survey found

Counts are of 2026-11-18, design repository a233783.

**How much there is.**

| Where | Size | Of it current |
|---|---|---|
| `writeup/plans/` | 80 files, 13,100 lines | 2 are live (the next iteration, the synthesis it consolidates) |
| `writeup/reviews/` | 74 files, 15,400 lines | 1 is live (the conceptual design, 2026-11-15) |
| `writeup/explorations/` | 22 files, 5,650 lines | written for the earlier build, but for the proofs (§8, Q7) |
| `writeup/design-findings.md` | 1,153 lines | the evidence log to session 22; its own header calls most of it history |
| `record/experiments.md` | 435 rows, E-1 to E-501, median row 1,434 characters | 250 rows are the earlier build's (E-1 to E-251), 10 are explorations run on it (E-252 to E-261), 175 are the unified line's |
| `record/todo.md` | 160 items, median row 1,113 characters | about 12 are open; statuses carry chains of "Earlier: … Before: …" |
| `open-issues.md` | 1,152 lines | 676 lines are closed items; 39 numbered items are open in §2 to §6 |
| `record/decisions.md` | 565 lines | §1 to §8 are ordered by the earlier design (keys, entries); 95 lines are superseded decisions |
| `record/INDEX.md` | 402 lines | lists every review, plan and note; its table of repositories is "as of 2026-10-19" |
| `design/alternatives.md` | 728 lines, 60 sections | in the order things happened, with dated headings |

**Where the history sits in documents that should hold none.**
- **The references.** Their rules are current. Their status lines are build logs: 282 commit hashes in `compiler.md`, 107 in `traits.md`; 110 and 93 work items; the user's words, dates, the plan's D-numbers, branch names (`unified` 116 times in `compiler.md`, `next` 50 times). The Deviations tables hold more retired rows than open ones (compiler: 70 of 93).
- **The evidence** (786 lines) is ordered by rounds and waves, not by claims. It cites 84 experiments of the earlier build beside 165 of the unified line. §3 (first calls and sessions, 264 lines) names julia-1.13 in 34 places. Ten rows compare against an earlier iteration ("the attribute's 7.2 ns", "the baseline's 2.90 s", "the earlier build's digests").
- **`state.md`** tells the next iteration as five waves of builds, and lists eight finished phases.
- **`goals.md`** §3: most tension rows read "Decided 2026-11-15 … Built on `next-s3` e967266d9e …".
- **`design/performance.md`** is entirely on julia-1.13. **`design/julia-changes.md`** §1 to §6 describe the earlier build's patch; §7 is the unified stack.
- **The front doors are the stalest.** The root `README.md` states four goals, the julia-1.13 trees, entries, workers and keys. `writeup/README.md` lists "key, trait object, entry, worker" as the terms. `setup.md` builds julia-1.13.
- **The demonstrators' READMEs** on their `unified` branches still report session 29 (TraitDifferentialEquations 24 mentions, TraitReport 18, the forks 14).
- **Stubs.** Sixteen "Moved" pages (`writeup/decisions.md`, `notes/`, `reference-unified/`, `design/argument.md`, …), and two pages the site's navigation itself calls "Retired".

**Where the design and its teaching disagree.** `intro/` and the glossary still teach the attribute, the casts and `keep` (`porting.md` 12 and 11 mentions, `traits-by-example.md` 6 and 6). The references replaced them with one way to erase on 2026-11-15. W-158 holds the rewrite.

**Housekeeping.**
- **The website is built from `main`,** which is 81 commits behind `w141-record` (a fast-forward).
- `experiments` has 107 untracked logs (96 in `unification/stack/logs`). `julia-unified` holds a core dump and twelve build logs.
- Trees whose work is merged: `julia-s3` (2.4 GB, all of it in `next`), `TraitWorld-s3`, `TraitWorld-w155`, `TraitDifferentialEquations-s3`, the six `wt/design-w*` worktrees with their `iter-w*` branches. `julia-unified-base` is a 3.3 GB copy of sources from 2026-11-11.
- 227 scripts of `experiments` name the directories `*-unified`, `julia-unified` or `julia-next`. Renaming directories would break them.

## 2. The rules the clean-up applies

Read from the request. R1 and R2 sharpen what `CLAUDE.md` says already; R3 and R4 are new.

- **R1. The unified line is the implementation.** Outside the history, no document names the earlier build (julia-1.13, TraitWorld `main`, entries, workers, the untyped table), and none says "the unified build": it is "the build", "the prototype", "Julia with the patch".
- **R2. A current document states the intended design, and where the implementation deviates.** It carries no chronology: no date of a decision, no commit of a build, no work item that built it, no "decided", "built on", "replaced", "after stage 5". Who decided, when, and in which words is the decision log's. Which commit built it is the inventory's (`design/julia-changes.md`) and git's.
- **R3. A baseline is plain Julia or Python.** Plain Julia is vanilla v1.13.2 (`julia-vanilla`), or the same code without traits on the patched build; the row says which. A comparison against an earlier iteration of the design (julia-1.13; the tag `prototype-2026-11` against `next`; the attribute against the box) is a regression control. It lives with its gate in the experiments repository, and in no current document.
- **R4. What is no longer relevant goes to the attic, after its insights are extracted.** A plan that is done, a review that is acted on, an exploration of a design not taken, a closed issue, a finished work item, an experiment of an earlier build. The attic keeps the relative path, so `writeup/plans/x.md` is found at `attic/writeup/plans/x.md`.

## 3. The layout after the clean-up

```
README.md                 what the project is, the goals, where to start, the workspace
writeup/
  README.md               the map for three audiences
  goals.md                the goals; the standing per axis; the index of standing tensions
  state.md                one page: the heads, what is built, the suites, what is next
  design.md               the rationale
  glossary.md
  setup.md
  open-issues.md          open items only
  intro/                  traits-for-julia, traits-by-example, porting, results
  reference/              README, traits, facts, compiler, lowering, extensions
  design/
    evidence.md           by goal; each number against plain Julia or Python
    julia-changes.md      the stack on v1.13.2, one row per commit
    other-languages.md
    alternatives.md       by topic
    lessons.md            new
    proofs.md             if Q7 is taken
  record/
    INDEX.md              a short map; the standing constraints; the repositories
    decisions.md          the decisions in force, by reference section
    experiments.md        the registry of current experiments
    todo.md               open work only
    design-history.md     the timeline, with pointers into the attic
    *-research-*.md       the five research notes, in place
  plans/                  the live ones
  reviews/                the live ones
session-notes/            unchanged: the chronology
attic/
  README.md               the index, by era; the rule for paths
  writeup/plans/, reviews/, explorations/, design/, record/, design-findings.md
```

`writeup/` outside plans and reviews falls from about 19,900 lines to an estimated 9,000 to 10,000. Plans and reviews fall from 154 files to 4.

## 4. Each document: what happens to it

| Document | What happens |
|---|---|
| `reference/traits.md`, `facts.md`, `compiler.md`, `lowering.md`, `extensions.md` | **Kept; one pass (part 5).** A status line becomes one word and the deviations that qualify it: "**Status:** Implemented, but for T-105." Commits, dates, work items, the user's words and "mine" leave. The gate that checks a rule may stay, as a test's name. The Deviations table lists open rows; the retired IDs stand in one line below it and in the ledger. |
| `reference/README.md` | Kept; the conventions follow R2. |
| `design.md` | Kept. The three numbers of the julia-1.13 build are replaced by the current ones or taken out; it cites the evidence. |
| `glossary.md` | Kept; a pass to the references' terms (the box, the wrapper; no attribute, casts, `Kept`). |
| `goals.md` | Kept. §2's standings without comparisons to an earlier iteration. §3 indexes the tensions that stand, each with its rule and its cost today; a tension closed by its gate moves to the closed ledger. |
| `state.md` | **Rewritten:** a table of heads, what is built by reference section (linking the Deviations tables), the suites on the head, what is next. No waves, no finished phases. |
| `open-issues.md` | **Split.** Open items stay: questions for the user; tensions; design; implementation. Each entry: the rule, the cost today with its experiment, the proposal. The 676 lines of closed items and the chronicles inside open entries ("measured so far", "after W-140", "after D-4") go to the ledger. The agent's choices become one line each, linking the decision log. |
| `design/evidence.md` | **Rewritten by claim (part 4).** |
| `design/alternatives.md` | **Restructured by topic,** and extended by the harvest (part 1). |
| `design/lessons.md` | **New** (part 1). |
| `design/julia-changes.md` | Kept: §7 becomes the document, one stack. §1 to §6 (the earlier patch) to the attic. Upstream status, tests and building rewritten for the stack. |
| `design/other-languages.md` | Kept; a pass (25 links into the attic, 9 experiments of the earlier build). |
| `design/performance.md` | **To the attic.** What it teaches about placing code goes to the lessons; where a session's time goes (E-388) is a section of the evidence. |
| `design/implementation.md`, `mechanisms.md`, `argument.md`, `comparison.md` | To the attic or deleted (retired pages and stubs). |
| `intro/traits-for-julia.md`, `traits-by-example.md` | Kept; rewritten on one way to erase now, their examples run on `next` (W-158's part, pulled forward: the library has D-1). |
| `intro/porting.md` | Kept; history out now. Its rewrite follows stage 4, when the ports are converted. |
| `intro/results.md` | Kept; rebuilt from the evidence. |
| `setup.md`, `README.md`, `writeup/README.md` | **Rewritten** for the trees and terms of today. |
| `record/experiments.md` | **Split and rewritten (part 3).** |
| `record/todo.md` | **Split:** open items only, each with its status now. The closed ones, about 148, to the ledger. "The plan" section points to the next iteration's stages. |
| `record/decisions.md` | **Split:** the decisions in force, ordered by the reference section they set, each with the user's words and date. Superseded decisions and those on mechanisms that no longer exist to the ledger. "Pending" is emptied: D-1 and D-2 are built. |
| `record/INDEX.md` | **Rewritten, short:** where each kind of fact lives, how to resume, the standing constraints, the repositories. The lists of reviews, plans, explorations and notes move to `attic/README.md`. |
| `record/design-history.md` | Kept; extended by a timeline of the eras, each with pointers into the attic and to the snapshot of the earlier build's numbers. |
| `record/performance-explorations.md` | Split by build: the entries on the unified line stay (current documents cite PE-5, PE-23, PE-24, PE-25, PE-33); the rest to the attic. |
| `record/*-research-*.md` (5) | Kept in place: research on other languages and on Julia, not on an iteration. |
| `plans/` | Live: `2026-11-15-next-iteration.md`, `2026-11-14-synthesis.md` (stage 7 writes its addendum), this plan. The other 78 to the attic. Two are folded first: the judgment on the cache across sessions (into the alternatives and the evidence's "not shown"), the measurement round's method (into `experiments/unification/w145/README.md`). |
| `reviews/` | Live: `2026-11-15-conceptual-design.md`. The other 73 to the attic. The 22 reviews since 2026-11-06 are checked first: a finding not acted on becomes an open issue or a deviation row. |
| `explorations/` | To the attic (21). `wrapping-by-facts.md`: Q7. |
| `design-findings.md` | To the attic. Its measurements of stock Julia stay in the registry where they ran on v1.13.2. |
| Stubs (`decisions.md`, `other-languages.md`, `porting-to-traits.md`, `notes/`, `reference-unified/`, `intro/reference.md`) | Deleted (Q4). |
| `session-notes/` | Unchanged. `00-environment-and-workflow.md` is brought up to date. |
| `mkdocs.yml` | The navigation follows §3. |

## 5. The parts, in order

Each part ends with the documents consistent and the tool's counts recorded. Sizes: S a session's part, M a session, L several.

### Part 0: the tool, the tags, the branch (S)

- **`experiments/tools/doclint/`,** with a README. It counts, per document:
  - links that do not resolve;
  - names of the earlier build, and "unified build";
  - history words in current documents (`no longer`, `superseded`, `formerly`, `Earlier:`, `was:`, `replaced by`, `decided`, `built on`);
  - commit hashes, dates and W-numbers in the references;
  - experiment IDs cited by a current document that are not in the current registry;
  - links from a current document into plans, reviews or the attic;
  - comparisons against an earlier iteration (a word list, reviewed by hand).
  Today's counts (§1) are its first log. The end state is zero, or a listed exception.
- **A tag** `docs-before-cleanup-2026-11-18` on the design repository and on `experiments`.
- **`main` fast-forwarded** to `w141-record` (Q3), so the website shows the current documents. The work goes on on `main`.
- The untracked logs of `experiments` committed.

### Part 1: the harvest (L)

Nothing moves before this part is done. It reads the plans, the reviews, the explorations, the findings log and the performance explorations: about 35,000 lines, in the main session (Q8).

- **Into `design/alternatives.md`, by topic.** The proposed chapters:
  1. What a trait is: regions and seals; representations and projections; keys in the core; traits as abstract types and the options not taken there.
  2. Memberships: "invalidates nothing"; the type equality; only growing; a membership as a method.
  3. Erasing: pointer and witness tables; `Callable`'s modes; `Dynamic` and `Compiled`; `stored`; the attribute and the casts; `Callable` by its methods.
  4. The facts rule and G2: the policy as package code; layering and its workarounds; the predicate; the code slot; calls that only throw.
  5. Ownership, pirates and strict mode.
  6. Checks: the classification; concreteness for every trait; fully typed in two words.
  7. Caches: combination and view caches; remembered validation; the cache keyed on the environment; fingerprints; the cache across sessions, not built.
  8. Compiling ahead: a closed build's rules as a list; members by declaration.
  9. Changes to Julia reverted or moot.
  10. Claims withdrawn; terms retired.
  Each entry: what it was, why it was not taken, the experiment, the document in the attic.
- **Into `design/lessons.md`, new.** What the work taught, stated as it holds now, each with its experiment. A first list, from what the current documents already say; the harvest confirms, replaces or adds:
  - *The design.* The facts rule alone gives most of the gain (E-392). Base's plain surface bounds the guarantee (GT-8, E-478). A trait laid over a type the whole ecosystem specializes on moves every caller (`IO`; GT-10). A membership that behaves as a method needs no rules of its own. One way to erase took the place of five steps. A closed build takes its members by use (GT-15).
  - *Speed.* A slowdown chased at one case does not hold; where a rule lets the compiler do less, it does.
  - *Images and workloads.* A membership's declaration puts code into an image that a workload would have to name (E-375).
  - *The ports.* The parameters in the outermost layer; a typed front end; a lean core; what each ecosystem asked of the design (open issues 157 to 162, 184).
  - *Measuring.* The registry row before the run; a criterion that ends a line of work; fresh processes, load order and a shared host's noise; what counts as a fair workload.
  - *Working with agents.* Gates that do not stop the work; one tree per agent; IDs in ranges; what a weaker model's attempt at the build showed (`attic/oc-notes/`).
- **Into `intro/porting.md`:** a lesson that is guidance for a port.
- **Into open issues or Deviations:** a finding of a review since 2026-11-06 that nothing acted on.
- **The check:** a list, kept in the attic's index, of each archived document and where its insights went, or "none beyond the record".

### Part 2: the move to the attic (M)

- One commit moves the 78 plans, 73 reviews, 21 explorations, `design-findings.md` and the retired design pages, with `git mv`, keeping relative paths.
- `attic/README.md` becomes the index, by era: the regions (August 2026); TraitWorld on julia-1.13 with keys, entries and the facts mode (October 2026); the unified line's finished plans and reviews (November 2026). It states the rule for paths once.
- Links in current documents are fixed or removed. Links inside the attic, the session notes and the ledgers are left: they are history.

### Part 3: the record (L)

- **The registry.** `record/experiments.md` holds an experiment when all hold:
  - it ran on the unified line (`unified` or `next`), or it measures plain Julia or Python alone;
  - its outcome is the latest answer to its question;
  - the mechanism it measures is in the references;
  - its baseline is plain Julia or Python (R3).
  The rows are ordered by goal (the problem in plain Julia; G-1 to G-8; gates), not by work item. A row: ID, question, baseline, build, outcome with its key numbers, directory. A few hundred characters; the write-up is the directory's README. Python's numbers (E-230, E-289) stay: they are a baseline.
- **The controls against the tag** (`next` against `prototype-2026-11`) stand in a last section until stage 7's freeze, then go to the ledger.
- **The ledger** `attic/writeup/record/experiments-archive.md` holds every other row unchanged, E-1 to E-261 and the superseded rows of the unified line. The registry's head names the ranges.
- **The experiments repository.** The directories of the earlier build move under `experiments/attic/`, after a grep for scripts of `unification/` that read them. `unification/` keeps its name (Q5). The README is rewritten: what is current, how to run a gate.
- **The work queue, the open issues, the decision log, the index:** as in §4. The ledgers: `attic/writeup/record/todo-closed.md`, `issues-closed.md`, `decisions-superseded.md`, `deviations-retired.md`.

### Part 4: the evidence, the goals, the state, the results (M to L)

- **`design/evidence.md` by goal.** For each axis: the claim, then one table. A row: what is measured, the trait or facts form, plain Julia, Python where it applies, the build, the experiment. Then "not shown". An estimated 250 to 300 lines.
- **A claim only the earlier build measured** is listed under "not shown on this build", with the row of stage 7's round that measures it, or it is dropped with its mechanism.
- **The snapshot** of today's page goes to `attic/writeup/design/evidence-2026-11-18.md`; `design-history.md` points to it for the numbers of earlier builds.
- **Until stage 7,** a row names the build it was measured on (`unified` at the tag, or `next`). Stage 7's round puts every row on the freeze.
- **Stage 7's round changes with R3** (Q2): each row against plain Julia and Python. The tag is a regression control in the gates.
- `goals.md`, `state.md` and `intro/results.md` are rebuilt from it.

### Part 5: the references (M)

- The status lines and Deviations tables, as in §4. The pass changes no rule.
- A commit named in a status line is checked against `design/julia-changes.md` before it leaves; a missing one gets its row there.
- A decision's provenance is checked against the decision log before it leaves; a missing one gets its row there.
- `reference/README.md` states the new conventions.

### Part 6: the front doors and the teaching (M)

- The root `README.md`, `writeup/README.md`, `setup.md`, the glossary, `mkdocs.yml`.
- `intro/traits-for-julia.md` and `traits-by-example.md` on the references of today; their examples run in `experiments/docs-examples/` on `next`.
- Each demonstrator's README on its `unified` branch: what it is, how to run it on the head, a link to the evidence. Its dated tables of the earlier build go to its repository's history.

### Part 7: the workspace (S)

- **Removed:** `julia-s3`, `TraitWorld-s3`, `TraitWorld-w155`, `TraitDifferentialEquations-s3`, `wt/design-w*`, the merged `iter-w*` branches, `julia-unified-base` after a check that no gate reads it. About 6 GB.
- **Kept until stage 7's controls have run:** `julia-unified` and `TraitWorld-base` (the tag), `wt/w151-base`, `w160-tm`, `w161-tde-base`, `w161-tw`.
- **Kept:** `julia-vanilla`. It is the plain Julia baseline.
- **The earlier build** (Q6): a tag `pre-unified` on each repository's earlier branch; `julia-1.13`'s build output cleaned. The checkouts stay: the `-unified` worktrees hang from them.
- `binA-wip` has one commit that `w141-record` lacks: looked at, then merged or dropped. `p2-experiments` and `poc-error-split` are merged: deleted.
- Build logs and the core dump in `julia-unified` deleted; the Manifests of `TraitReport-unified` and `ndport` committed or ignored.

### Part 8: the rules, and the last check (S)

- **`CLAUDE.md`** (Q1), as a diff for the user:
  - R1 to R4 in "The current intended state, not the history".
  - The table: new homes for the lessons, the ledgers and the attic; "agreed work" and "an experiment" say what the current page holds.
  - Rule 4: an ID is permanent; a retired or closed row lives in its ledger. Rule 7: a single move leaves a "Moved" page; a move to the attic keeps the path and leaves none.
  - The references' status line as one word.
  - The paragraphs whose condition is met are taken out or shortened: the schedule to the synthesis; "no measurement campaigns until the prototype is conceptually complete".
- The tool's counts at zero or listed.
- The website built once from the tree.
- A review of the result in the main session, written to `reviews/` as any review.

## 6. How it fits the next iteration

- Stage 4 (W-156) is next there. The clean-up changes no code, so the two do not collide in a tree. They do collide in the documents: an agent of stage 4 writes status lines, registry rows and queue rows.
- **Recommended:** parts 0 to 3 and 5 before stage 4 starts, so that its agents write into the new shapes. Parts 4 and 6 can run beside stage 4. The numbers of part 4 are refreshed by stage 7.
- W-158's teaching part moves into part 6. Stage 7's round follows R3.

## 7. Risks

- **A lost insight.** The harvest reads 35,000 lines once. The guard: nothing is deleted, the attic keeps paths, and the index records where each document's insights went.
- **A broken citation.** Session notes and archived documents cite paths that move. The guard: the attic's path rule, stated once. The tool checks the links of current documents only.
- **A reference pass that changes a rule by accident.** The guard: the pass touches status lines and tables only, one reference per commit, with the diff read against the rule text.
- **Evidence thinner than before.** Some claims rest on the earlier build alone. The page will say "not shown on this build" where it did not before. That is the honest state, and stage 7 has the list.
- **The ledgers grow stale as history does.** They are not maintained; they are the record of 2026-11-18 and take new closed rows as they close.

## 8. Decisions for the user

Adopting the plan takes each as recommended, unless the user names an exception. The user's answers (2026-11-18) are the last column; in full, the status line.

| | The question | Recommended | Decided |
|---|---|---|---|
| Q1 | **`CLAUDE.md`:** may the rules R1 to R4, the changes to rules 4 and 7 and the removal of finished paragraphs be written into it? | Yes, shown as a diff first. | Yes (the user). |
| Q2 | **Is the tag `prototype-2026-11` "a previous iteration"?** If so, `next` against the tag is a control, not evidence, and stage 7's round measures against plain Julia and Python. | Yes. | Yes (mine; the user: "Q2 you decide, measuring a set of changes against the immediate predecessor is of course fine during regression testing and performance work."). A change measured against its immediate predecessor is a control: it stands in the registry's section of controls and in its gate's README. The evidence, the goals, the state and `intro/` state numbers against plain Julia and Python. |
| Q3 | **The design repository's branch:** `main` fast-forwarded to `w141-record`, and the work continues on `main`. | Yes; it also repairs the website. | Yes (the user). Done: `main` 59c6f97. |
| Q4 | **No "Moved" pages** for the move to the attic, and the sixteen existing stubs deleted. Old citations resolve by the attic's path rule. | Yes. | Yes (the user). |
| Q5 | **Names.** Documents stop saying "the unified build". The directories `*-unified`, the branch `unified` and `experiments/unification/` keep their names until stage 7's freeze: 227 scripts name them. | Keep now; rename at the freeze, or never. | Renamed too, as the last part (the user: "Clean Up the directory names as well, but do it last."): part 9, §9. |
| Q6 | **The earlier build is history:** tagged, its build output cleaned, no document says it still runs. | Yes. | Yes (mine; the user: "Q6 you decide"). |
| Q7 | **The proofs** (`explorations/wrapping-by-facts.md`, the argument for G1 and G2): checked against today's facts reference and kept as `design/proofs.md`, or archived. | Check and keep: the guarantee is the project's first claim. | Check and keep (the user). |
| Q8 | **Who reads for the harvest.** The rule is no subagents on this host. The harvest is 35,000 lines of reading that splits cleanly by era. | The main session, in three sittings. Opus agents only if the user extends the exception. | Subagents allowed, few side by side (the user: "you can use subagents. But not too many in parallel."). The harvest's reading stays in the main session: §9. |

## 9. What the adoption added

**The record is the agents' tier, with more context than a human reader wants** (the user: "Should we also have an additional "for agents" documentation that gives more context than humans would like?"). Yes (mine). It is also where the clean-up puts what rule R2 takes out of the documents for people: the context is kept, in the one place written for a reader who wants all of it.
- **Where:** `writeup/record/`, which the site already calls "The record, for agents". No new top-level directory.
- **What it adds** beside the ledgers (the decision log, the registry, the work queue):
  - `record/context.md`: the project for an agent that starts cold. The eras and why each turn was taken; the user's standing preferences with their reasons; what a new agent tends to get wrong. Chronology is allowed here.
  - `record/build-notes/traits.md`, `facts.md`, `compiler.md`, `lowering.md`: one entry per section of the reference, under the section's number. Where the rule is in the code (files, functions); the commits that built it; the gates and tests that check it; the decision's row in the log; the experiments; the pitfalls met while building. Part 5 moves what it takes out of a status line here.
  - `record/playbook.md`: how the work is done. Building, the gates, measuring on the shared host, the traps (a build tree beside `git add -A`, load order, a stale image), how agents are briefed and kept apart. It takes in `session-notes/00-environment-and-workflow.md`, the index's standing constraints and the long form of the lessons on measuring and on working with agents.
  - `attic/README.md`: a digest per archived document, from the harvest: what it was, what it found, where its insights went.
- **Its rules:**
  - It may hold chronology, provenance and the user's words.
  - It is never the only home of a rule of the design, a number or a decision. It links to the reference, the evidence and the decision log.
  - It is written for an agent without context: complete before short.
  - `CLAUDE.md` stays the rules; the playbook is the know-how.
- **For people:** `design/lessons.md` and `design/alternatives.md` stay short. The long form of a lesson is in the agents' tier.

**The harvest is read in the main session** (the user: "Would it be possible for this session to actually do all the reading to be better able to extract relevant lessons by having maximum contextual knowledge of the project?"). Yes (mine), with one limit stated plainly.
- **The volume:** plans 1.6 MB, reviews 2.1 MB, explorations 0.7 MB, the findings log 0.1 MB: 4.5 MB, more than a million tokens. The record beside it (the registry, the queue, the open issues, the decision log, the evidence, the alternatives) is 2 MB more; the session notes 0.8 MB.
- **The limit:** the session reads all of it, but cannot hold all of it at once. Its context is summarized as it fills. What carries the knowledge is a notebook, written as the reading goes.
- **The notebook:** `writeup/record/harvest-2026-11.md`. One entry per document, written right after it is read: what it was, what it found, what became of each finding, what is not yet in a current document, and candidates for the lessons and the alternatives. Committed after each batch. It becomes the attic's digest and the source of `record/context.md`.
- **The order:** by date, oldest first, so that each document is read knowing what came before it. Plans, reviews and explorations of one day together. The session notes are read beside them for the user's words.
- **Subagents** are used for work that can be checked mechanically, at most two side by side (my reading of "not too many in parallel"): the demonstrators' READMEs, fixing links after the move, the registry's rows put into the new shape. Not for the reading.

**Part 9: the names (L), last.** After every other part, at a time when no agent works in the trees.
- The directories `*-unified` lose the suffix; the earlier checkouts take a name that says what they are. The `-unified` trees are worktrees of the earlier checkouts today, so each repository's main checkout changes its branch first.
- The branch `unified` of each repository becomes its default branch.
- `experiments/unification/` is renamed, or its directories move up, after `experiments/attic/` holds the earlier ones.
- The 227 scripts that name these paths, and the environments' Manifests, follow in the same commits.
- **The check:** the gates and each demonstrator's suite run once after the rename.
- Its steps are written as a short plan of their own before it starts.

