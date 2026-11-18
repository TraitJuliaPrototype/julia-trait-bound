# Cleaning up the writeup: a proposal (2026-10-19)

The user asked for a cleanup of the notes, without deleting anything. The writeup should show the work done, to three audiences:
- **programmers** using Julia, who do not need to know what an implementing type is;
- **core developers**, who want the precise rules and the major implementation choices;
- **agents**, who need every finding, experiment, decision and insight on record.

`design.md` stays the source of truth, for core developers.

## 1. What is wrong now

**Out of date and contradicting `design.md`:**
- `notes/1–4` (1,647 lines). They predate the session-29 framing and still describe four rules, layering, sealing and representations; each carries two banners saying so. `design.md` covers their substance, but not all of their detail. That detail is listed in §3.2 below.
- **Root `README.md`:**
  - the julia-1.13 branch "with the invalidation filter" (removed today);
  - "pieces 1–5, 9, 10, 17" (2 and 4 are reverted);
  - TraitWorld "stock and patched", 350 tests (stock is dropped);
  - the order of work as a to-do list (steps 1–5 are done).
- **`writeup/README.md`:** reading order through the stale notes; `julia-support.md` described as pieces 2, 4, 6 "dropped".
- **`design.md` itself,** in parts that predate today:
  - §5 rule 1: "folds where Base's asserted effects fold". Superseded by the review rule: no asserted effect applies to a frame with a run-time site.
  - §6: the inlining row says "for facts code only" (ungated today).
  - §8: "They predate parts B, C and D", the control listed as "not shown", typed calls 33/30 ns, raytrace 470–484 ms.
  - §9.1: pieces 2 and 4 "to revert", "Not measured yet: everything".
  - §9.3: an order of work whose steps 1–6 are done.
  - §10: "no claim that traits … protect code from loads until the control … has run" (it has run).
  - §11: points to the stale notes.
- **The demonstrators' READMEs** (TraitMakie, TraitReport, TraitDifferentialEquations, forks): a status line "nothing timed in session 30"; history tables from sessions 23–27; a "To measure after (D)" section, now measured.
- **`explorations/julia-support.md`:** the piece list as of session 25; it does not know (A)–(D) or today's compiler changes.
- **`open-issues.md`:** many items closed by session 29 (the compiler, the control, pieces 2/4, the forks' suites) and not yet marked.

**Fine as a record, but unindexed:**
- 12 reviews, 10 explorations, 2 plans, `design-findings.md` (1,153 lines), 29 session notes.
- `decisions.md` (the register with history), `other-languages.md` (research), `porting-to-traits.md` (in progress).

**Missing:**
- Anything for programmers. `notes/1-overview.md` comes closest, and it uses the design's vocabulary.
- One current page of results. The numbers are spread over `design.md` §8, `notes/5-performance.md`, four READMEs and the session note.

## 2. The proposed layout

Three entry points, one per audience. Nothing is deleted. Superseded files move to `attic/` with a pointer, or stay where they are with a status line.

```
README.md                      the workspace and the three entry points (rewritten)
writeup/
  README.md                    the map: which audience reads what (rewritten)

  intro/                       PROGRAMMERS (new)
    traits-for-julia.md        what you write, what you get, one worked example; no compiler terms
    results.md                 what the demonstrators show, in plain words, honest comparisons
    porting.md                 how to port a package (porting-to-traits.md, moved; jargon reduced)

  design.md                    CORE DEVELOPERS: the source of truth (updated, §3.1 below)
  design/                      core-developer companions (new directory)
    julia-changes.md           every change to Julia as built: parts A–D, the optimizer changes, the compiler
                               staying plain, the pieces kept/reverted; commits; upstream status
                               (replaces explorations/julia-support.md and design §6's long table rows)
    evidence.md                the current measurements, one table per demonstrator and experiment, with build
                               and date; what is not shown (from design §8, notes/5-performance.md, the READMEs)
    performance.md             notes/5-performance.md: the themes and learnings (moved, kept as is)
    mechanisms.md              the detail design.md compresses: keywords, defaults and varargs; functions that
                               cross; generic and named implementations; several traits on one object; parametric
                               user types; types that only convert (from notes/4-details.md, re-checked against
                               design.md)
    comparison.md              the choices against C++, Rust, Swift, Mojo, and their costs (notes/2-design-choices.md
                               §1–4, 8–10 and "costs", refreshed; other-languages.md stays the research behind it)
  decisions.md                 the register with history (stays: many links point here)
  open-issues.md               open items (closed ones marked, not removed)

  record/                      AGENTS (new index; the files stay where they are)
    INDEX.md                   every record document: what it holds, its date, its status, what in design.md
                               supersedes it, and where to look for a kind of question (a finding, a decision's
                               history, a measurement's raw log, a review's verdict)
  explorations/, plans/, reviews/, design-findings.md, other-languages.md     unchanged, indexed
  notes/                       frozen: 1–4 move to attic/writeup/notes-2026-10-18/ (see 3.2); 5 moves to design/

session-notes/                 unchanged (the per-session log; INDEX.md lists them with one line each)
```

**Why not move the record files.** Session notes, reviews, memories and other repositories cite their paths more than a hundred times. An index gives agents the map without breaking those links. The only moves are the four stale notes (to the attic, with a stub left at each old path) and `porting-to-traits.md` (with a stub).

## 3. The work, file by file

### 3.1 `design.md`: bring it to today (core developers)

- §5 rule 1: the assertion rule as built.
- §6: the table rows shortened to one line each, with detail in `design/julia-changes.md`; the inliner changes as ungated; the B1 boundary kept.
- §8: rewritten from the measurements (session 29, final build). Shown: the control (load protection is the facts rule's, for any code); the raytrace and `Dynamic` against plain; first calls in every load order; the forks' session. Not shown: the ~990 ms after loads under `all`, TDE row 4, the clean `@implement` regression, Python not rerun.
- §9: "today" as built; the order of work replaced by the next steps (diagnosis, §4.8 AOT, upstream PRs, the forks).
- §10: the control's claim settled; the claims still not made.
- §11: points to the new layout.
- No other content change: the rules, terms and decisions stay as they are.

### 3.2 `notes/1–4`: what each holds that the new layout must keep

| Note | Kept where | Content not in `design.md` today |
|---|---|---|
| `1-overview.md` | `intro/traits-for-julia.md` (rewritten for programmers) | the worked example ("a library and its user"), the pay-offs in plain words |
| `2-design-choices.md` | `design/comparison.md` | §1–4, 8–10, the costs, "other options considered", the predictions from other languages; §5–7 are history (layering, sealing) |
| `3-wrapping.md` | `intro/porting.md` (adopting traits one function at a time; traits over existing functions) and `design.md` §3 (pirates, strict mode: already there) | the four cases (Base, Cairo, ForwardDiff, Makie/CSV/DataFrames) as examples |
| `4-details.md` | `design/mechanisms.md` | keywords/defaults/varargs, functions that cross, generic and named implementations, several traits, parametric user types, types that only convert, results like the input in detail, identical-or-error in detail |

Each old note moves to `attic/writeup/notes-2026-10-18/` unchanged, and leaves a one-paragraph stub at its old path that names where each section went.

### 3.3 New documents for programmers (`intro/`)

- **`traits-for-julia.md`:** the problem in user terms ("your code recompiles when you load another package"; "a collection of mixed types is slow"; "errors surface deep inside a library"), what you write (`@trait`, `@implement`, a bounded function), what you get, the example, the honest costs.
  - Vocabulary: trait, conformance, bounded function, `Dynamic`. Not: key, implementing type, CodeInstance, fact.
- **`results.md`:** the demonstrators in plain words, each with its fair baseline and caveats; numbers rounded, with a link to `design/evidence.md` for the precise ones.
- **`porting.md`:** `porting-to-traits.md`, moved, with part A in plain terms.

### 3.4 The record (agents)

- **`record/INDEX.md`:** one row per document (path, date, status: current / history / superseded by …, one-line content).
  - Covers the reviews (with their verdicts and what was acted on), explorations, plans, `design-findings.md` by section (current vs history, as its header says), and session notes 01–29.
  - A "where to look" section: a decision's history, a measurement's raw log (`/tmp` logs are not durable: the session note quotes them), an experiment's script, a review's finding and its outcome.
- **`open-issues.md`:** items closed in session 29 marked closed with the commit, not removed.
- **Root and `writeup/README.md`:** rewritten as maps.
- **The demonstrators' READMEs** (in their own repositories):
  - the status line and "To measure after (D)" replaced by the session-29 numbers;
  - the history tables kept under a "History" heading.

## 4. Order of work, and what it costs

1. `record/INDEX.md` and the two READMEs: the map first, so nothing gets lost while files move (~1 hour of agent work).
2. `design.md` brought to today, and `design/evidence.md`, `design/julia-changes.md`, `design/performance.md` (moved).
3. `design/mechanisms.md` and `design/comparison.md` from notes 4 and 2; then the notes to the attic with stubs.
4. `intro/` for programmers, last: it is new writing, and it should be checked against the current `design.md`. A Fable review against the audience (can a Julia programmer read it without the glossary?) before it is final.
5. The demonstrators' READMEs and `open-issues.md`.

Each step is a commit; every move leaves a stub; links are checked with a script after each step.

## 5. Decisions for the user

1. **Moves or stubs-only.** Move the four stale notes to the attic with stubs (proposed), or leave them in place with a third banner.
2. **The programmer-facing documents:** write them now (step 4), or after the next performance round, when the numbers settle.
3. **Where the record index lives:** `writeup/record/INDEX.md` (proposed), or merged into `writeup/README.md`.
