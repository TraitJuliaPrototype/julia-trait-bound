# numbers — measured, with build and setting (newest first)

One line per number (or per table): date, what it measures, build (commit), setting
(product / `all` / strict), the machine's load if it matters, the number.

## 2026-10-30 — M2 declare-walk volume (gate `m2_volume`, coordinator re-run)

M2 diff on `efb87dfbdf` (uncommitted, build-matched), final binary, idle slot:
24 types each with a compiled `vt` specialization through the catch-all, then 24
`@implement`s into one open set. Stat deltas + wall:

| declares | replays | visits | morespec_skips | spec_inval | cache_lowerings | latest_only_clears | wall |
|---|---|---|---|---|---|---|---|
| 24 | 24 | 24 | 0 | **48** | 0 | 0 | **0.014 s** |

48 invalidations = 2 per declare (the member's `vt` spec + one shared), against the
naive-A ceiling of N·N = 576 — **B-band, ≈8 % of naive**; ≈0.6 ms per declare on a
cold-cache script start. The `m2_stale_caller` counters (1 replay, 1 visit,
1 spec-invalidation for one affected caller) show the walk is intersection-driven,
not scan-driven.

**Conservative-shape scale (round-2 review B annotation).** `spec_inval` counts
dispatch-replacement **events** (replays × MIs), not distinct MethodInstances —
a spec losing its winner to two replayed methods counts twice; the conservative
path's own specs are pushed uncounted (their winner cannot flip). One conservative
declare (a set under `Vararg`, `/tmp/opencode/m2reviewW2-probe.jl`, coordinator
re-run): `replays=1 spec_inval=1 cache_lowerings=2898` — the conservative full
mt-cache wipe lowers **every live entry of the (global, this base) methcache**
and flushes the leafcache; vanilla activate's intersecting-insert flush is the
precedent class. No conservative declare occurs inside `m2_volume`, so this cost
mode lives only here.

## 2026-10-30 — M2 inertness gate

`/usr/bin/time -v make -C julia-oc test-subtype test-core test-ambiguous`, M2 diff
on `efb87dfbdf` (uncommitted), full rebuild green (the first invocation,
`m2-suites.log`, timed the sysimage rebuild too: 6:12.68 / 6.07 GB with exit 0 and
3× SUCCESS — not comparable), clean second run (`m2-suites2.log`), machine idle:

| | wall | peak RSS | exit |
|---|---|---|---|
| M0 control | 2:03.36 | 2,329,916 KB | 0 |
| M1b (`m1b-suites2.log`) | 1:49.71 | 2,323,936 KB | 0 |
| M2 final, GC-roots build (`m2-suites4.log`) | **1:40.87 (−18.2 %)** | 2,329,108 KB (−0.03 %) | 0 |
| M2, review-round-1 build (`m2-suites3.log`) | 1:42.43 (−17.0 %) | 2,327,604 KB (−0.10 %) | 0 |
| M2, pre-review build (`m2-suites2.log`) | 1:40.21 (−18.8 %) | 2,326,296 KB (−0.15 %) | 0 |

All three suites SUCCESS, exit 0. As for M1a/M1b the wall reads fast (warm,
idle-niced machine); no slowdown anywhere, peak RSS indistinguishable —
**M2 is inert within the gate.**

## 2026-10-30 — C7 placement count (M0)

See `c7count/<label>-c7.tsv` and the `== <label>` lines in `c7count/logs/`.
Old build `julia-1.13` at `00dcc9994c` (the U5 commits exactly); depot `w83u9` (U9's,
warm); `jl` slot, offline. Columns per (function, position):
N entries, A = flag placement, B = `morespecific` placement (`::Any`-declared methods;
the typemap "no method" backedges cannot be enumerated from Julia and are noted),
C = members (genuine re-dispatch), K = never-member kinds (untouched),
M = the trait's own workers, L = methods losing `METHOD_SIG_LATEST_ONLY`.

(summaries appended when the runs finish)

### Result (pass 2, 2026-10-30)

Build `julia-1.13` @ `00dcc9994c` (U5 commits exactly), depot `w83u9`, offline, jl slots;
pass wall time ~10 min. Files `<label>-c7.tsv` and `<label>-hypo-show-c7.tsv` here.
Columns: N entries, A = flag placement, B = `morespecific` placement as measured (specs of
`::Any`-declared methods — see refinement), C = members (true re-dispatch), K = never-member
kinds, L = methods losing `METHOD_SIG_LATEST_ONLY`.

**Real bounded functions** (U5's censuses; every (function, position) pair of the session):

| session | pairs | N | A | B | C | K |
|---|---|---|---|---|---|---|
| tables | 18 | 94 | 91 | 22 | 2 | 3 |
| forks | 54 | 528 | 516 | 128 | 68 | 12 |
| tde | 47 | 168 | 152 | 56 | 19 | 16 |
| makie | 56 | 258 | 257 | 128 | 47 | 1 |
| ndport | 106 | 431 | 415 | 191 | 66 | 16 |

**Hypothetical `Base.show(::IO, ::X)`** (the stress case; one bounded method per set of
U5's `<label>-hypo-show.tsv`, position 2; totals over the sets, ~10–19 sets per session):

| session | sets | N/def | A/def (share) | B/def | C/def |
|---|---|---|---|---|---|
| tables | 11 | ~445 | ~413 (93 %) | ~13 | ~15 |
| tde | 9 | ~490 | ~458 (93 %) | ~13 | ~16 |
| forks | 15 | ~670 | ~627 (94 %) | ~18 | ~23 |
| makie | 15 | ~538 | ~497 (92 %) | ~15 | ~11 |
| ndport | 19 | ~776 | ~732 (94 %) | ~18 | ~15 |

**Verdicts.**
- **P3 confirmed, and stronger than M2 stated.** B measured every entry of every
  `::Any`-declared method; but the plan's three-layer rule keeps `typeintersect` exact,
  so the insertion walk at the definition only reaches entries at actual members —
  the true `morespecific`-placement cost at a definition is ≈ **C** (entries it correctly
  re-dispatches, 11–23 per hypothetical `show` definition, 0–13 for the real functions),
  not A. The flag placement reaches A (92–99 % of everything, 400–730 per foreign
  definition, per E-233's order — its 1,884 victims). A/B ≈ 30–40×; A/C ≈ 30–50×.
  C7 goes in `type_morespecific_` (plan P3 stands; M2's "skips every chain-matched
  specialization" is exactly what the counts show).
- **D5 accepted, cost small under (H2 exact intersection + M2 C7):** defining a bounded
  `show` on an open set invalidates ~its own member entries (C) plus typemap bookkeeping;
  the ~500/session the flag placement would eat is avoided. The foreign-function warning
  (exploration §14.4) stays as the rule anyway; L (fast-path clearing) is a flag write on
  ~100–200 `show` methods per definition under either placement, not invalidation.
- **Caveat:** the counting itself compiles a few `show` entries as it runs (first set
  sees ~12 % fewer); orders of magnitude, not exact. "no method" typemap backedges are
  not enumerable from Julia and sit outside A/B/C.


## M1a inertness gate (2026-10-30)

`make -C julia-oc test-subtype test-core test-ambiguous`, one invocation, M1a build
(branch `oc-build`, M1a edits applied, full rebuild green):

| | wall | peak RSS | exit |
|---|---|---|---|
| M0 control (vanilla, `logs-m0-control.log`) | 2:03.36 | 2,329,916 KB | 0 |
| M1a (`logs-m1a-check2.log`) | **1:55.72 (−6.2 %)** | 2,331,052 KB (+0.05 %) | 0 |

All three suites SUCCESS (subtype 317,568 pass / 43 broken as control; core 7,354,041
pass; ambiguous pass). One test edit was required and is expected, not a regression:
`test/core.jl:47` hard-codes `TypeName`'s atomic-field list — `:memberships` added
(upstream convention when adding an atomic field). First run (`logs-m1a-check1.log`)
failed on exactly that, 1:50.04; the −6 % wall is machine noise (subtype 9.3 s vs
control's; within run-to-run spread), conclusion: **M1a is inert within the ±10 % gate.**


## M1b inertness gate (2026-10-30)

`/usr/bin/time -v make -C julia-oc test-subtype test-core test-ambiguous`, one
invocation, M1b build (all M1b edits applied — flags word UInt32, membership
helpers, epoch design, Core wrappers + constructors, boot masks — full rebuild
green, gates 10/10 × 5 rounds):

| | wall | peak RSS | exit |
|---|---|---|---|
| M0 control (vanilla, `logs-m0-control.log`) | 2:03.36 | 2,329,916 KB | 0 |
| M1a (`logs-m1a-check2.log`) | 1:55.72 (−6.2 %) | 2,331,052 KB (+0.05 %) | 0 |
| M1b (`m1b-suites2.log`) | **1:49.71 (−11.1 %)** | 2,323,936 KB (−0.26 %) | 0 |

All three suites SUCCESS with exit 0: subtype 317,568 pass / 43 broken (exactly
the control), core 7,354,041 pass / 7 broken (exactly the control count; the
core.jl:8413 union-isa regression found in round 1 was fixed by re-guarding the
`jl_isa` union arm to ground bodies), ambiguous 155 pass / 3 broken. The wall
reads fast because the machine ran the whole suite warm and idle-niced; subtype
10.3 s vs control ≈9–11 s, core 58.7 s — per-suite splits are in control range,
so, as for M1a, the wall is run-to-run noise and **M1b is inert within the gate**
(no slowdown; peak RSS indistinguishable).
