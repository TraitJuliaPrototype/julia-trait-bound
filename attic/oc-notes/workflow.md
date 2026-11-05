# Workflow — the agent pipeline for the traits-v2 build

Status: **in force** (user decision, 2026-10-30; written by the coordinator after
M1a/M1b). Applies to the implementation milestones (M1b–M7), risk-tiered (§7).
The coordinator is the main session. Everything here is subordinate to the plan
(`oc-notes/plan.md`) and the design invariants it carries.

## 1. Roles

1. **Coordinator (main session)** — the only role with standing rights:
   sole writer of `oc-notes/notes.md` and `oc-notes/numbers.md` and of the git
   history; owns the build slot (starts/kills builds, grants them to agents);
   approves or amends the edit plan before implementation starts; arbitrates all
   disputes; runs the milestone gates and the timing suite itself; writes every
   agent brief; commits, and records the resulting SHA in `notes.md`.
2. **Planner agent** — fresh session. Reads plan §4.x, the recon/notes sections,
   the review document, and the real sources; delivers exactly one artifact:
   `oc-notes/<milestone>-editplan.md` — per-site hunks with tree-verified
   context, the invariant each hunk must hold, gate coverage, honest deferrals,
   and open questions for the coordinator. Edits nothing else.
3. **Plan reviewer** — fresh session, *not* the planner. Audits the edit plan
   against the tree and the design (does every hunk's quoted context still
   exist? does any hunk break an invariant? is a needed site missed? are the
   gate claims real?). Verdict per site: approve / fix(how) / reject, with
   `file:line` citations. Writes findings for the coordinator; does not edit
   the plan.
4. **Implementation agent (author)** — sole writer of the file set the approved
   plan lists. Applies the plan (adapting drifted hunks and reporting it),
   compiles, runs static analysis, iterates until the gate scripts pass. No
   git commands that mutate state; no edits to gates, tests, or notes; stops on
   any §6 escalation.
5. **Implementation reviewer** — fresh session. Reads `git diff` (never the
   plan's claims about it) and the acceptance artifacts — gate scripts and
   tests — as ground truth. Delivers numbered findings with severity
   (blocker / major / minor / nit), each citing `file:line`, and a verdict:
   approve / request-changes. The author answers item-by-item; they alternate
   **max two rounds** (three by exception). A semantic dispute does not iterate:
   it goes to the coordinator, who rules and amends the notes.

Independence is the point: no agent reviews its own output; reviewers do not
inherit the author's reasoning. The coordinator's pre-commit gate run is the
final review — a review verdict never replaces it.

## 2. Per-milestone pipeline

1. Coordinator briefs the planner (scope, invariant excerpt, machine state).
2. Edit plan lands → plan reviewer starts **while** the coordinator does
   non-conflicting prep (gate scripts, numbers bookkeeping, next-milestone
   recon). Coordinator resolves findings, attaches binding amendments, approves.
3. Author implements under an exclusive build slot (§3); reports with a
   structured final message (per-site deviations, analysis output, gate
   results, test numbers, `git status`/`diff --stat`, anything red and why).
4. Implementation reviewer audits the diff → author ↔ reviewer rounds (§1.5).
5. Coordinator: whitespace check of added lines, gate scripts ×N, Base's three
   suites vs the control (`numbers.md`, ±10 %), `detect_ambiguities(Base)`
   unchanged where due; records; commits (`component: Summary` per AGENTS.md);
   notes the SHA and the outcome in `notes.md`.

A milestone is done at step 5, not at "gates pass locally".

## 3. Hard resources (shared machine, shared tree)

- **Build slot**: one compiled-Julia job machine-wide at a time, niced,
  memory-guarded (the `oc-build.sh` watchdog). An agent: check nothing runs
  (`pgrep -af "make -"`), run via `setsid nice -n 19 …` to `/tmp/opencode`
  logs, wait with sleep-loops, leave no orphan `make`. Never interleave a
  `make -C src` loop with a full build.
- **Single writer per tree**: at most one author touches `julia-oc/` (the file
  list of the approved plan is its boundary). Read-only agents are unlimited.
  Never review a tree mid-write — review starts when the author reports rest.
- **Agents never**: mutate git state; write outside their file list; touch the
  gate scripts, tests, `notes.md`, `numbers.md`; delete staged images except
  on the coordinator's explicit instruction (or the plan's documented tripwire).

## 4. What parallelizes

Yes: planning the *next* milestone during the current one's build/review (its
author waits for the predecessor's commit); plan review ∥ coordinator prep;
separate read-only research agents; clang analysis of files no author is
writing; gate-script authoring (coordinator); timing-record bookkeeping.
No: two builds; two writers on one file set; a diff review while the author
still writes; any overlap of build slot holders.

## 5. Review focus (every finding cites `file:line`)

**C side** — GC rooting across every allocation (args are assumed rooted;
`JL_GC_PUSH`/`JL_GC_PROMISE_ROOTED` per AGENTS.md); the world protocol (runtime
queries use `jl_current_task->world_age`; entries filtered by `min/max_world`;
world 0 = image build); lock discipline (`world_counter_lock`) and atomic
publication order (publish before advancing the counter; readers acquire);
memoized-bit upkeep and recursion termination on self-referential types;
self-description discipline: widening any self-described struct's bit-group
(`jl_datatype_t.flags`, TypeName…) must update the matching
`jl_svecset(...->types, …)` type — the serializer/GC follow the self-description,
not the C struct (M1a latent-truncation incident, notes 2026-10-30) — AND every
Julia-side consumer of the field must be audited: `getfield` boxes per the
self-description, so literal masks/comparisons written for the old width break
bootstrap code wherever promotion methods do not exist yet (the uint32-flags
`&(UInt32,UInt16)` MethodError hunt, notes 2026-10-30);
image/serialization: no struct-layout change without the coordinator (tripwire:
the TypeName list in `test/core.jl:47` + the staged-image wipe rule); new
ccallables registered in `src/jl_exported_funcs.inc`; style: 4 spaces, no
trailing whitespace/tabs, comments like the neighbors.

**Compiler side** — no negative folds while a pair could join; entry-derived
positives never fold until M2's `min_world` machinery; over-wide lattice
results justified per consumer; with no set open, every new check is a false
flag read (invariant I3 — Base behavior bit-identical, zero gate activations).

**Acceptance** — every new rule gains a gate line or a test line; gates run
against `julia-oc/julia --project=oc-traits`; the three suites inside ±10 % of
the recorded control.

## 6. Escalation ladder (agent stops working the item and reports)

any needed git mutation; a needed struct-layout change; a gate resisting three
fix rounds; a build failure it cannot localize; any semantic/design decision
(subtyping rules, world semantics, lattice shape, error policy); machine
memory pressure. Briefs carry a timebox; at the box, bring the tree to rest
(no orphan processes!) and report state.

## 7. Risk tiers (avoid ceremony where it does not pay)

- **Tier A** (type system, dispatch, compiler, codegen, images): full pipeline,
  both reviewers. Default for M2–M7 halves touching `src/` or `Compiler/src/`.
- **Tier B** (gate/test/doc edits, small self-contained C additions ≤ ~20
  lines, `oc-traits/` library work): one agent + coordinator review directly.
- **Tier C** (notes, numbers, measurement runs, read-only recon): coordinator,
  or a read-only explore agent.

## 8. Brief template (agents start blank — briefs are self-contained)

absolute repo paths and which worktree; the role and its single artifact; the
owned file list; the *excerpted* invariants (not "go read the notes"); the
current machine state and slot rules; prohibitions (git, out-of-scope writes,
acceptance files); escalation conditions (§6) and the timebox; the exact
report format. Follow-ups may reuse a finished session by ID; a reviewer is
always fresh.

## 9. Worked example (M1b, 2026-10-30)

planner → `oc-notes/m1b-editplan.md` (caught four recon discrepancies, found
the codegen re-fold); coordinator review → two binding amendments (GC-root
`inst` in the membership answer; refuse `never_member` in `jl_set_open_set`)
+ one new gate (`m1_parametric_set.jl`); author under the build slot; reviewer
after rest; coordinator runs gates ×5 and the timing suite, then commits.
