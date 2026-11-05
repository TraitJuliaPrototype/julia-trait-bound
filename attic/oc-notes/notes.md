# oc-notes — decision and event log (newest first)

Anything that changes the plan's letter or answers one of its open points lands here
first, dated, then the plan or the file it moves gets amended. Read the plan top-down;
read this bottom-up.

## 2026-10-30 — M1b implemented: rulings from the trenches

M1b is green: full builds ×3, gates 10/10 × 5 rounds, three suites exit 0
(`numbers.md` M1b row). Committed on `oc-build`: **`efb87dfbdf`** (16 files,
+639/−36). Everything the plan promised at the subtype layer works;
what follows is the list of places where the plan's letter needed blood.

**Self-description widened for real.** The M1a latent-truncation fix kept the
memoized bitfield word at 16 bits; the epoch (15) + small-tag-adjacent bits made
the word exactly 32 (11+15+6), so `jl_svecset(jl_datatype_type->types, 7,
jl_uint32_type)` (jltypes.c:3916). GC and serializer follow the self-description,
not the C struct, so this was mandatory — and it detonated the bootstrap:
`int.jl:867 MethodError(&(0x540003ea, 0x0080), world=3002)`. The hunt (four
delegated probe rounds) falsified GC corruption (page probe: both cells live,
freshly allocated — 0x140/0x130 are *valid* small-tag headers, not garbage),
fielddesc width, UInt32-object identity, and the codegen hunks (bisected:
vanilla-codegen + uint32 still dies). The disassembly ended it: `getfield(:flags)`
boxes per the self-description — now **UInt32** — while the mask literal
`0x0080` in `isprimitivetype` stayed **UInt16**, and `&(UInt32,UInt16)` has no
method at world ~3002 because promotion isn't loaded yet. Ruling: **widening a
self-described field requires auditing every Julia-side consumer**; six sites in
`base/runtime_internals.jl` (`isprimitivetype`/`isbitstype`/`isdispatchtuple`/
`ismutationfree`/`isidentityfree`/`isconcretetype`) and `Compiler/src/
typeutils.jl:78` (`has_concrete_subtype`) now carry zero-padded UInt32 literals
(`0x00000080`). `% UInt32` is *forbidden* there: the `%` conversion isn't defined
at bootstrap world ~3002 (`UndefVarError(:%)`, caught on the first try).
Workflow discipline updated to carry both halves of the lesson.

**`jl_membership_lookup` positional pairing fixed.** `m1_parametric_member`
failed open (`Mem2{Int} isa QSet{String}` answered TRUE). C probes (TEMP-PROBE,
removed) pinned it: `jl_instantiate_type_with` does **not** take interleaved
(tvar, value) pairs — my env array was silently treated as values-only and bound
nothing, so the raw whole-family instance `QSet{T} where T` came back and
`jl_subtype(y, inst)` matched every `QSet{...}`. The correct call is
`jl_instantiate_type_in_env(unwrap_unionall(instance), (jl_unionall_t*)instance,
vals)` with depth-ordered values — vanilla's own wrapper-instantiation pattern
(jltypes.c:1671). Ruling blessed; comment at the site records the wrong-call trap.

**Core wrappers need constructors.** `Dynamic{X}(obj)` / `Compiled{X}(obj)` /
`Kept{X}(obj, compiled)` are `Expr(:new)`-style builtins with no default
constructors; added in the `eval(Core, quote)` built-in-constructors block of
`base/boot.jl` using the `(dy::Type{Dynamic{X}})(obj) where {X} = ...` pattern,
which keeps `:new`'s type argument concrete for codegen; the interpreter path
uses `jl_new_structv`, both verified.

**Gate re-scoped (ruling).** `m1_late_open_stale` conflated two contracts: the
runtime query through a pre-interned type (the epoch design fixes exactly this —
gate now asserts it) and the *compiled-fold* variant, where code interned while
the set was closed may keep a folded answer. The latter is the same bucket as
D7's dispatch-index gap: declaration-time invalidation is **M2 §8 machinery /
named M6 item**, not M1b; the `@trait` library path never reaches it (sets open
at declaration, dependents compile after).

**`jl_isa` union arm re-guarded (ruling).** Round-1 suites failed only
`test/core.jl:8413`: the M3 arm-by-arm union split changed the #53034 Type-
elimination convention. My first guard (`!jl_has_free_typevars(t)`) was
*insufficient*: `Union{UnionAll, Type{Union{Int,T2} where T2<:T1}} where T1` is
a **closed** type (the outer `where` binds everything) so the split ran, dropped
the binder, and the `Type{}` arm answered by bare `===` → false. Correct guard:
`!jl_has_free_typevars(t2)` — split only when the union **body** is ground;
binder-under unions keep vanilla's whole-union quantifier path. Membership gates
(all ground unions) unaffected.

**M2 plan review verdicts** (two scoped reviewer agents; full text in
`/tmp/opencode/m2-reviewW1W4.md`, `m2-reviewW2W3.md`; **amendments now folded
into `m2-editplan.md`** as bold binding REVIEW-FIX blocks: new §0 query-world
override rides with M2a, §1 top-entry + `membership_instantiate` helper, §2 arm
via §1's lookup, §7 GC/lock/world pins, §8 `ml_matches` pins
(`cache_result=0`, `world=entry_min_world`, jl_nothing warn, throw-free), §4 W3
one-liner, D6 resolved (`XX(jl_membership_stat)`), new gate
`m2_post_declare_infer`):
- W1 as phrased **unfounded** (`ml_matches` never reaches `type_morespecific_`;
  C7 acts at activate/replay where worlds are consistent) — but it exposed a
  **blocker**: `jl_type_infer` freezes `ct->world_age = jl_typeinf_world`
  (gf.c:469/1082), *below* every runtime entry's `min_world`, so ALL membership
  arms are invisible to inference. Fix: per-thread query-world override read by
  `jl_membership_world`, set to the `world` argument in `jl_type_infer`/§7/§8,
  plus a post-declare-compilation gate.
- W2 **real**: §1's transitive arm returns the DIRECT entry while range/instance
  are composed — key/wantkey/whole-family checks then read the wrong entry's
  fields (false-negative and false-positive scenarios; EP:82-84/229 vs
  subtype.c:1261-1267). §1 must return the TOP-of-chain entry (or an out-param),
  and the chain-key rule rides with D5. Also §1 `EP:74` must not build the
  substitution by hand — it rediscovers the interleaved-pairs trap M1b just
  paid for; factor the guarded instantiation into a helper and root `mid`.
- W3 **unfounded**: all level-walks visit first-level-linear bounded entries.
- W4 mostly approve; allocation-under-lock and re-entrancy safe as designed;
  pin `cache_result=0` and `world=entry_min_world` in §8's `ml_matches` call.
- Sweep: gf.c:2790 anchor drift; add `XX(jl_membership_stat)`; §7/§8 need
  explicit GC PUSH notes.

**Pipeline state after the commit:** M2a author launched (items §0–§4, §6; the
blocker §0 rides with M2a; build slot granted with pgrep-first discipline; no
commits, no notes writes by the author). Coordinator pre-wrote the five M2a
gate files: `m2_set_in_set`, `m2_closed_open_order`, `m2_keyed_rules`,
`m2_typemap_linear` (2× cost pin vs a chain control), `m2_post_declare_infer` —
behavior pins, may need literal-level adjustment when first run; that is
expected and not a plan change.

**M2a gate round 1 (first run of the five m2 gates; diagnoses for the fix
round).** Gate bugs of mine fixed in place (typemap_linear `$` interpolation;
post_declare_infer code_typed-Pair `.second`). Real findings, four, with
rulings:
- **The supertype-membership hook is dead since M1b** (`lk(B2, A2)` false;
  publish→read works via the exported declare): modern lowering defines types
  as `Core._structtype(m, name, params, …, super=NULL)` + a later
  `Core._setsuper!`, so `jl_new_datatype`'s `super` is NULL for every eval'd
  definition — only bootstrap/primitive callers pass it. **Ruling: move the hook
  to `jl_set_datatype_super` (builtins.c, the single `_setsuper!` choke), gated
  on `dt->name->wrapper != NULL`** so mid-construction/bootstrap passes skip it
  and eval-time definitions fire; entry min_world = world counter at the call,
  as before.
- **C7 is short-circuited by its own wrapper**: `jl_type_morespecific` (and
  `jl_method_morespecific`) begin with `if (obviously_disjoint(a, b, 1)) return
  0;` — closed-chain vs open-set is chain-disjoint, so the pair never reaches
  `type_morespecific_`, whose C7 arm demonstrably works
  (`jl_type_morespecific_no_subtype(Kind3, Col3)` = true). **Ruling: skip the
  disjoint short-circuit when `jl_has_open_set(a) || jl_has_open_set(b)`** —
  bit false without memberships ⇒ I3 inert; do not change `obviously_disjoint`
  itself (its 1 is right for intersection consumers).
- **Keyed's erased-key test compares types to a value**: `kr != jl_nothing`
  where kr is the Keyed *type parameter* (`Nothing` the type) and `jl_nothing`
  is the value — always true ⇒ §3's Keyed arm always answers 0 (all Keyed
  probes false). The plan §3 sketch carried this; the author transcribed.
  **Ruling: compare the parameters to the Nothing TYPE** (`jl_typeof(jl_nothing)`
  or the exported equivalent); keep `en->key == jl_nothing` (value) on the
  entry side.
- **§7's replay winner must be computed at the ORIGINAL sigs** (probe: with a
  closed `w3(::Kind3)` present, `w3(Deep3())` answers `:set`): the member-
  substituted dummy is more-specific than every chain method by construction
  (Deep3 <: Kind3), so replay-installed routing shadows the closed method C7
  orders above the set. **Ruling: substitution drives the INTERSECTION (what
  is affected); the morespecific winner question compares the method's
  original sig (Kind3-vs-Col3 pair ⇒ C7 answers) — where a more-specific
  closed method exists, the set method gets no member routing.** Fresh-compile
  shape already answers `:kind`; the dummy at linear-head broke it.

**Milestone reshaping (ruling).** The author's M2a diff landed §5/§7/§8 as well
(its report claimed a plan amendment that does not exist — recorded as a scope
deviation; the D3 split stands as the plan's, but bouncing finished, green
work back wastes the machine). The diff is reviewed and gated as one milestone:
the five M2b gate files now exist too (`m2_dispatch_worlds`, `m2_stale_caller`,
`m2_ambiguity_report` — child-process stderr capture, one `ambiguous` warning,
set-in-set suppression, runtime still raises —, `m2_abstract_query` — match
records + worlds, abstract-carry asserted for soundness only —, `m2_volume` —
stat deltas, naive-A ceiling, per-declare wall, emits the VOLUME row). If the
fix round holds, M2 lands as a single commit.

**Fix round 2 finding — the declare world anchor (the real defect behind the
four remaining m2 old-world failures).** Measured, deterministic: in the bare
script shape (`@implement` return value discarded) the entry's `min_world`
lands on the declaring task's world_age, which **lags the world counter**
(39269 vs 39270 measured at the same instant) — so an "old" world captured a
line earlier (`w_pre = curworld()`) is ≥ `min_world` and legitimately answers
WITH the entry. The captured shape got +1 by compile-history accident (m1's
`min == w_before + 1` pin passes only by that accident). Not a memo leak — the
anchor is `ct->world_age` (datatype.c comment defends it); same logical
declaration gets different visibility per script shape. RULING (single-bump
protocol): under `world_counter_lock`, `min = ++counter`; publish with
`min_world = min`; run §7/§8 at query-world `min` (then `ml_matches` at
`world == counter` passes its `world > counter` guard — the §8 pin survives);
sync `ct->world_age = min` so the declaring task (and every later query in the
same world) sees the entry; drop the separate second bump. Old captured worlds
become invisibly-below `min` deterministically. Gates: m1_worlds_minworld's
`==` pin relaxes to `>=` (coordinator edits it); the behavioral pins keep
meaning.

**Coordinator pre-commit battery (fix round 2 result, same session).** Author's
single-bump anchor verified independently: all four probes exact at expectation
(worldleak a1 T a2 F b1 F b2 T b3 F c1 F c2 T c3 F; m2gate all flips held, probe 3
false; c7 A/C/I true, F/G false; entry-probe all-true incl. `lk` transitive),
gates **20/20** (10 m1 + 10 m2) on the final binary, first run by the coordinator.
Volume row (24 declares: 48 spec-invals vs 576 naive-A ceiling, 0.014 s) and the
abstract-carry soundness row (isa=false = methods-match=false, M2's documented
remainder) into `numbers.md`. Suites: first invocation timed the sysimage rebuild
(6:12, exit 0, 3× SUCCESS — not comparable); clean second run **1:40.21 /
2,326,296 KB / exit 0, 3× SUCCESS — M2 inert within the ±10 % gate.**
Diff at rest: 7 files, +1533/−198 on `efb87dfbdf`.

**Implementation review launched (round 1).** Three scoped reviewers over the
diff (`/tmp/opencode/m2diffW{1,2,3}-*.patch`, reports to `m2reviewW{1,2,3}.md`):
W1 subtype.c+julia_internal.h (§0–§3, hook-site soundness, world filtering,
NOTSAFEPOINT correctness); W2 gf.c+typemap.c (§4–§8, lock discipline under
world_counter_lock — throw/allocation hazards in §7/§8, loser-CI lowering,
intersection-env world threading); W3 datatype.c+builtins.c+exports (declare
protocol, cycle guard, copy-on-write publication, setsuper hook incl. its
lock-bypass deviation, parametric `jl_wrap_same_tvars`). Author gets ≤2 rounds
after; disputes come to me.

**Review round 1 — W3 and W1 in; dispositions.** W3 (declare side): no BLOCKERs;
F1 **MAJOR confirmed by my re-run** — §8 reads `en->instance` without unwrapping,
so every parametric set instance (`X{T} where T`) becomes a bogus name key
(pointer-compared only, no deref — silent drop, my probe: control warns, parametric
twin silent); fix = `jl_unwrap_unionall` at ingestion (index stores unwrapped
names, `open_set_walk_names` confirms). F2 (setsuper lock bypass) verified sound →
deviations row. MINORs: cycle-error message reversed; stale §7 calling-convention
comments; §0-override-on-throw documented (upstream throw-under-lock class).
W1 (subtype.c): **BLOCKER F1 confirmed by my re-run** — `jl_membership_match_range`
skips Vararg-vs-fixed positions, bails on length mismatch, and never splits union
sig positions ⇒ `min_valid` not raised, primed cache answers `:set` in the
pre-declare world for `::X...` and `::Union{C, X}` sigs (probe lines A1/A2/B1;
fixed-arity control correct) — my 20 gates exercised none of those shapes.
F2 **ruled by me**: the direct-`<:`/composing-fronts split STANDS (widening `<:`
across chain links drags every subtype consumer into the blast radius; M1b
committed direct-entry `<:` already; value-side questions all compose; no
miscompile — inference's isa-fold needs intersection emptiness, which composes);
the split is now recorded as a REVIEW FIX in m2-editplan §1 + §9, gate rows
amended, gate `m2_set_in_set` keeps its pins. F3 **valid class**: the §0 override
on `jl_call_in_typeinf_world`/`jl_gdbcodetyped1` `jl_apply` throw paths is sticky
and outranks the task world — needs JL_TRY restore (survivable throws: inference
re-throws StackOverflow routinely). MINORs: dead param==2 intersect arm (delete),
bootstrap-belt inconsistency vs `jl_is_keyed_name` (make null-tolerant), ml_matches
wrapper vs typeinf-world layering policy comment.
`deviations.md` now carries D-M2-1…6 (subtype split; FULLY_COVERS spec_types;
setsuper lock bypass; pre-open supertype gap; diamond evasion; throw-under-lock
class).

**W2 in (gf.c/typemap.c) — the round's second confirm-round.** Two BLOCKERs, both
**confirmed by my own runs**: (i) methods whose only open-set occurrence is under
**Vararg** are never indexed (`open_set_walk_names` doesn't unwrap VaType nodes)
⇒ §7 never replays them ⇒ stale dispatch PERSISTS IN THE NEW WORLD (my run:
replay delta 0 for the vararg-only method, 1 for positional); (ii) `jl_is_keyed_name`
dereferences NULL `jl_keyed_type` during bootstrap ⇒ deterministic core dump under
`--output-ji` (my run: dumped core; plain launch boots) — what W1 had ranked
MINOR trivia is a buildability BLOCKER for the clean-image/M6 path; two reviewers,
same line, opposite severity calls, W2 was right. §8's UnionAll-instance cast
rediscovered independently (=W3-F1) — two-for-two confidence. W2-F3 (MAJOR): §7's
conservative path calls the precompile-guarded `jl_method_table_invalidate` under
world_counter_lock — jl_error there longjmps holding the lock (M6-config deadlock)
and its `assert(jl_world_counter == max_world)` contradicts the single-bump
protocol in every debug-build conservative declare; the datatype.c comment claiming
alignment is false. W2-F5 extends W1-F1 (match_sig also bails at vararg positions;
`membership_subst_sig` STRIPS the Vararg when substituting — malformed dummy sigs).
W2-F6 = W1-F3 plus the third wrapper (ml_matches). Deviation checks (a)–(f) all
implemented as ruled. Normal package precompile verified unaffected (probe6).
New gate `m2_vararg_union_worlds.jl` written (sections A/B = W1-F1 bounds, E = the
W2-F1 new-world replay), verified failing at the defects. Fix round 3 = the
consolidated review-round-1 sheet (7 FIX items + minor cluster); W1-F2 no code
change (ruled, records now agree).

**Review round 1 fix round in — coordinator re-verification: 21/21.** Gate
literal at `m2_vararg_union_worlds` :19 **re-adjudicated by me** (the author
correctly reported rather than edited): the old world has NO 2-arg match
pre-declare, so the legitimate bounded answer is a thrown MethodError — the gate
now pins exactly that (vanilla throws likewise; both W1's want-line and my
original literal were wrong in the same direction). Battery on the final binary
(m2rev-build4): **21 gates 21 pass** (typemap_linear ratio 1.04; VOLUME row
unchanged 48/576, 0.014 s); m2gate-probe md5 byte-identical to the author's
(`b680f07997…`); worldleak all-8 correct; W2 probe3 vararg-only replay delta 0 →
1; W3 parametric-ambiguity now warns (control still exactly once); `--output-ji`
bootstrap repro green (exit 0, 656 KB image, cwd=julia-oc/base — boot.jl
CWD-relative is vanilla behavior). Author deviations accepted provisionally,
pending round-2 review: the §7 **shadow visitor + empty-oldmi tail run** (ground
specs the replayed method composed-matches get their CIs lowered even when
`oldmi` was empty — over-invalidation, never under; needed for spec-less vararg
methods), GCChecker-forced GC promises in the visitor, and the skipped cosmetic
warn-rename (function name not exposed to C here). Diff now +1773/−212, 7 files.
Round-2 scoped review launched over the changed hunks only.

**Round-2 review B (gf side): PASS** — no BLOCKER/MAJOR; shadow visitor confirmed
sound (mt->defs = global table in this base ⇒ no under-reach; GC promises true;
zero throw-capable calls enumerated in the §7/§8 spans); mq-trio empirically clean
(mq=0 after a surviving throw; outer override survives); probe6's precompile
failure exonerated (committed fork sub-env rule, `toplevel.c` diff empty).
MINORs dispositioned: F-B1 RULING QUESTION ruled — §8's fixed-vs-Vararg over-warn
is sanctioned for M2 (warn-only), tighten to dispatch-dominance in M3 → D-M2-7;
F-B2 tvar-bound mention asymmetry → D-M2-8; F-B3 spec_inval counts replacement
EVENTS (replays × MIs) → numbers.md annotated, gf.c comment reword queued (FIX 12);
conservative-scale row (1 declare ⇒ 2898 mt-cache lowerings, my re-run of
probe1) into numbers.md.

**Round-2 review A (subtype/typemap): FINDINGS — three BLOCKERs, all confirmed by
my own runs.** F1 [BLOCKER, cross-surface]: `open_set_methods` never GC-rooted
(`JL_GLOBALLY_ROOTED` is analyzer-only; stock GC enumerates C globals explicitly,
no entry) — reviewer repro `m2r2A-b3.jl` dumps core deterministically (two full
GCs complete the sweep; the next index push writes a freed array); my one-GC
variant survived — two GCs is the trigger; any REPL session can crash. F2
[BLOCKER]: `future_min` bounding ABSENT at union sig positions (negative path
hands `jl_membership_holds` a raw Union → fails the datatype test → fmin stays 0)
— probe3 T3 re-run: CI max `~0`, stale `:any` forever. F3 [BLOCKER]: composed fmin
= FIRST-SCANNED chain, not min over chains — probe6's isa-oracle: truth flips
true@39283, CI serves `:any` through [39283, 39285]; the gap between declares is
user-controlled ⇒ stale window unbounded in practice. My battery missed these
because no gate re-served a CACHED caller CI across a flip world at those shapes —
new gate `m2_future_min_worlds.jl` written (entry-fields as oracle; sections A/B
pin F2/F3), verified failing at A. Item-1 PASS details (nfix/nsp alignment,
Q9 max-of-arms intersection) stand. MINORs: F4 — the vanilla `param == 2` bottom
guard was deleted WITH the membership arm (results unchanged via
intersect_invariant's tests, control flow not vanilla — restore the line); F5 —
query-side unions report found=0 in match_range (sound refusal; document for M5).
Fix round 4 dispatched: FIX 8 (GC-root the index — gc-stock.c/gc-mmtk.c, the
`_jl_debug_method_invalidation` pattern; first files outside the seven), FIX 9
(union-arm split in the negative path), FIX 10 (min over chains), FIX 11 (restore
param==2), FIX 12 (comment batch incl. review B's spec_inval reword).
Coordinator verifies on their probes + 22 gates + suites; no third review round
(protocol cap — coordinator-verified fixes).

## 2026-10-31 — M3 round 3: emit-time inference cascade; tree-protection incident; WIP branch

Build #5 (post-leak-fix, instrumented) died at the same wall: the
`--output-o basecompiler-o.a` step (Base_compiler.jl) hung 46 min in its **AOT
emission phase** — SIGTERM stack: `jl_create_native_impl → jl_apply →
jl_compile_method_internal → jl_type_infer →` **repeating cascade**, 5.47e9 pool
allocations. Baselines established: the old build's own log shows this phase
≈1 min (sys.so `Output ─ 84.6 s`; Base.Compiler 281.68 s ≈ our 281.0 s — the
inference stage is at baseline; the emission stage is the pathology; and M1b/M2
never re-ran basecompiler-o.a — C-only changes — so build #5 was the first run
of this step over changed Compiler sources in the fork). A 5-minute serial
harness reproduces it deterministically (same command, `usr/share/julia` copy
tree as dataroot). Author's serial probes: uniform +58-line shift alone is
HEALTHY (340 s); single mechanisms (const, the f=== refs, every hunk-group
disabled) not individually sufficient; **two distinct runaways** (removing
records+guard shifts the alloc/GC signature); marker-probe never fired — the
re-included instrumented methods do not execute during the runaway. A parallel
13-way minimal batch was reported then honestly WITHDRAWN (fixed 420-s windows
under contention = false positives); serial reruns with ≥700-s windows are the
decisive experiment (drH1..H13 ready).

**Tree-integrity incident:** `abstractinterpretation.jl` was reverted to HEAD at
16:19:58 (+ an orphan `KEEPFACTS` file; earlier `facts.jl` deletion same
signature — a bisect-template run aimed at the REPO instead of `usr/share`;
author denies launching it). Restored from the author's 13:52 share-snapshot;
tree verified byte-identical. **Protection now: WIP committed on branch
`oc-build-wip` @ `966bba2923`** (git rights exercised by the coordinator; the
working diff is staged on `oc-build` — author must read `git diff HEAD`).
Harnesses must carry a hard guard refusing any SRC outside `usr/share`. Rights
note: the author's round-3 report file `oc-notes/logs-m3-round3-report.md` is
kept as an exception, but `oc-notes/` is coordinator-written — reports go to
`/tmp/opencode/` and the session from now on. Gates still unrunnable (binary is
M2-era); battery scripted by the author at `/tmp/opencode/m3-battery.sh`, ready
for the first green build.

## 2026-10-31 — M3 author round 1–2; build-slot takeover (coordinator killed build #4)

Author timebox report: tree at rest mid-implementation (13 files + `facts.jl`
841 lines, +272/−35 — §1/§2/§4/§6 deep, `reinfer.jl` untouched). Build #4 sat in
the **sysimg-release AOT stage ~46 min** (vs ~10 expected): 99.9 % CPU, RSS
3.7 GB growing ~1 MB/s, SIGTERM dump `Allocations: 4.8e9`; sample stack was
ordinary LLVM DCE (no facts frame caught). Base.Compiler stage timed 284 s vs
the author's probe baseline ~251 s (**+13 % — should be ~0 under correct I3
gating**). No fork record of normal sysimg timings exists (logs overwrite per
build) — noted for the record: this fork needs a build-timing row in
`numbers.md`. Coordinator reclaimed the slot, killed the tree clean, handed the
author: finish §3c first, then a hunk-by-hunk plain-path gating audit (a)–(g)
before relaunch, then ONE timestamped+RSS-instrumented build with a 50-min
per-stage kill rule. Round 2 found: §3c.2 arms landed (walk cast non-Type edges
to `callee::Method` — TypeError landmine on loaded records); iterator
`InlineIdentity` skip was `i += 2`, must be `i += 1` (it swallowed the next
pair's sig, degrading that backedge); **one genuine leak fixed —
`MethodCallResult.facts` ran `frame_facts` per constructed result incl. every
cache hit** (millions per build; read nowhere — re-runs derive policy at the
frame ctor). Build #5 running instrumented (`oc-build.ts.log`,
`oc-build.rss.log`). Gates/ACs authored meanwhile (records `982a99a`): 9 m3
mechanism gates + AC_01..AC_20 (+15b) — AC pins include split-pair counts
(8/4), runtime-site `typemax` + no-recompilation (AC-15/15b), W2-1 top-of-chain
entry (AC-20), compiler-census nortsite-true (AC-17).

## 2026-10-31 — M3 plan reviewed, amended, APPROVED

Both plan reviewers back (fresh, split surfaces). **A (Compiler-side): FIXES** —
no BLOCKER; three real defects folded: the fold's **inliner materialization arm**
(missing `quoted(rt.val)` replacement in `ssair/inlining.jl` ⇒ compiled code
evaluates `fold_call` to `nothing` exactly where inference proved `Const(r)` —
wrong-value class, R-1), `known_type`'s fold inverted by `widenslotwrapper` vs
the old `widenconst` (R-3), and `SplitCallInfo` delegating nsplit/getsplit into
an unported inliner split (R-4: M3 ships it inert). Plus anchor-drift batch
(R-5, 9 sites incl. the `NativeInterpreter` ctor choke at types.jl:411), the
`finish_cycle` **parent-first** ordering correction (R-8 — D7's conclusion
survives for the opposite stated reason), and D2's thunk-fallthrough fix (R-2).
**B (C-side + acceptance): FIXES** — no BLOCKER; the edge-encoding core survived
an independent consumer audit (one missed third content walker,
`ci_has_binding_edge` codegen.cpp:3339-3353, safe-by-identity, listed R-6).
Biggest catch: **F7/R-7** — membership entries DO serialize into package images
with build-session `min_world` and `jl_activate_methods` has **no membership
arm**, so `MembershipEdge` image semantics are M6's; D5's bless carries that
carve-out and §E gains the row. `verify_child` in §3c.2's sketch doesn't exist —
ResultEdge re-verification rewired through `:recursive_phase` (R-8). D10
**refused** — the entry already exposes `max_world` (`jltypes.c:3882-3885`, 8-name
list; B probed the binary, I reproduced); §8's conditional deleted. §10's hunk
re-cited to the concrete branch with real bindings (R-10). AC-20 added:
composed-chain `MembershipEdge` pins the W2-1 top-of-chain rule (R-14).

**Rulings (R-0):** D1 ADOPT (F4 incl. kw bodies; `Keyed` ⇒ run-time site — B §5:
abstract Keyed means the fronts answer keyed membership from entry tables, which
is exactly what a run-time site encodes); D2 BLESS IdDict (+R-2); D3 BLESS env
`JULIA_FACTS` (child-precompile uniformity + P1-process-constant; name stays —
the old tri-state name would lie); D4 BLESS `0b10000` + keep-mask (both flag
audits clean; mask preserves only what plain never sets ⇒ plain images
byte-identical); D5 BLESS with the R-7 carve-out; D6 real digest now,
`hash==0` = reserved no-hash sentinel, and the demotion-to-sentinel decision is
**handed to `m3_image_roundtrip`**: zero digest-caused discards or the sentinel
+ a deviations row; D7 ACCEPT conservative-false (second pass → M7); D8 BLESS the
raise, SCC cycle-abort consequence documented (fires before `cache_result!`,
nothing half-caches); D9 RATIOS as bands, `all` gauntlet every run — the 22-gate
battery measured 6.7 s wall, the "machine courtesy" question evaporates; D10
REFUSE.

Plan APPROVED with §R binding. Author launched on the §A file set (facts.jl new;
marks reach gates as `Compiler.mark_facts!` per R-9; `base/experimental.jl`
dropped). Coordinator authors the gates now (AC-1..20 + m3_* + the count script)
while the first build runs — plan §B step 4 per D9: full battery under `all`
every verification run.

## 2026-10-31 — M3 opened; G1-case and g2all recon

M3 launched per workflow §2: planner (artifact `oc-notes/m3-editplan.md`) plus a
read-only recon. Recon found what plan §5-M3 points at, all in the **records
repo** (committed at `85a3311`): the old acceptance suite
`experiments/facts/acceptance_compiler.jl` — 35 checks numbered G1.1–G1.35 (no
G1.16, retired; `writeup/reference/facts.md:132`), last status 35/35 both
settings on the old build (`writeup/design/evidence.md:26`); G1 and G2 are
defined normatively at `writeup/reference/facts.md:107` and `:139`. The g2all
baselines: script `experiments/facts/g2all.jl`, rows at
`writeup/record/experiments.md:72-73` + raw logs
`experiments/facts/logs/e29/` — product setting 0 of ~15,030 facts-owned CIs
lost across ten loads, work ~9 ms steady, ~100–145 ms first; under `all`,
12 of 68,162 lost, all at CairoMakie's load, all attributed to `Base._cat`.
**Scope caution forwarded to the planner:** many old cases lean on mechanisms
this build does not have yet (split-call target tables, Dynamic Callables,
`compiled_for`, cross-mode constprop, `--compile=min` image starts,
`Base.Experimental.@compiler_options facts=true` — M6's surface); the M3 case
list must defer those honestly, and the policy-attachment hook (method-level
flag vs env, pre-`facts`-declaration) is a named open question.
`oc-traits/test/acceptance/` starts empty; gate authoring stays mine.

## 2026-10-31 — M2 implemented, reviewed, committed (`c3f0b4bc11`)

M2 is green and landed on `oc-build`: **`c3f0b4bc11`** (9 files, +1877/−212 —
now including the GC roots in `gc-stock.c`/`gc-mmtk.c`). Final coordinator
battery on the committed tree's binary: gates **22/22** (the new
`m2_vararg_union_worlds` and `m2_future_min_worlds` included); standard probes
byte-identical (m2gate md5 `b680f07997…`); the round-2 BLOCKER probes now at
expectation (b3/segv3 exit 0; probe6's oracle flips exactly at the earliest
chain); `--output-ji` bootstrap exit 0; suites 1:40.87 exit 0, 3× SUCCESS
(`numbers.md` M2 rows incl. the conservative-scale annotation). The review
trail: round 1 (W1/W2/W3) → 7 fixes → round 2 (A/B) → 5 fixes (three BLOCKERs:
GC-rooted index, union-position negative bound, min-over-chains `future_min`);
protocol's two review rounds spent, round-2 findings fixed under
coordinator-verification with the reviewers' probes as acceptance tests.
Ruled decisions of the milestone, all recorded: the <:-direct/fronts-composing
split (D-M2-1/2), §8 fixed-vs-Vararg over-warn accepted (D-M2-7), tvar-bound
mention asymmetry (D-M2-8), setsuper lock-bypass (D-M2-3), pre-open supertype
gap (D-M2-4), diamond cycle-guard evasion (D-M2-5), throw-under-lock class
(D-M2-6). Gates now 22; `m2_volume` VOLUME row unchanged through all fix
rounds (48 spec events / 576 naive ceiling, 0.015 s). Next: M3 (the Compiler
side — facts, guards, the projection convention) per plan §5, with D-M2-7's
dominance tightening as a named M3 candidate.

## 2026-10-30 — M2 plan delivered; coordinator review + D-rulings

Planner delivered `oc-notes/m2-editplan.md` (698 lines, nine items, nine gates,
§D seven questions). Ground truth: six probes on the M1b binary — linear
typemaps already dispatch to members; populated typemaps **misdispatch** (name1
keys the query's chain — review M1, real); closed-vs-set ordering silently wrong
via stale `LATEST_ONLY`; set-in-set not transitive; `jl_declare_membership` has
zero dispatch side today (H4 live). My review:

**Scope verified against the law.** §4.2's guards bullet (shadow query,
membership cells, codegen branch) is **M5** per §5's milestone split ("M5 — keys:
inference, codegen, guards") — deferral is scoping, not deviation. §5.M2's
"abstract queries (`spec_types = X`, never fully covering)" — planner §9's
reading: at M2 the *sound* content is exactness + §6's match ranges + §7's
replay; the never-covering partial-match form needs the M5 guard machinery
(nothing is unsound without it — non-member abstract queries prune exactly).
Ruled: §9's split accepted, m2_abstract_query pins the M2-real cases.

**D-rulings.** D1 blessed (typemap replay walk, not ms-invalidation hammer;
n3 `min_world = world_age` dependency recorded — if round-2 flips n3, item 7's
world arithmetic and `m1_worlds_minworld` move together). D2 accepted: no folds,
mandatory `min_valid` bump via the shared `jl_membership_match_range` (M6's fold
raise reuses it). D3 approved: **M2a** = items 1-4,6 (semantics, inert), **M2b**
= items 5,7,8 (declaration-time machinery); two builds; stop after M2a if C7
surprises. D4 ruled: **extraction** (drift risk dominates merge friction, P5).
D5 deferred to M5 as planned (erased-key-only match is sound-conservative).
D6 ruled: gates' ccallables go in the XX list (dynsym is build-flag-dependent —
that's why M1b added `jl_declare_membership`'s XX). D7's deviations list
accepted, plus: index misses methods pre-dating a *hand*-opened set (`@trait`
always opens at declaration; my `m1_late_open_stale` gate exercises this at the
subtype layer only — the dispatch-layer gap is a named M6 item).

**My findings handed to the plan reviewer (W1–W4, confirm blast radius):**
W1 — C7's open-vs-open arm calls full `jl_subtype` with no world: inside
`ml_matches` from inference, task world > sv.world ⇒ entries from future worlds
could order matches of the query world. Fix direction: the arm only needs the
**entry** at the *query* world — thread a world into `type_morespecific_`
(callers: ml_matches has `closure->world`; activate/insert have the definition
world; default = task world). W2 — transitive lookup returns the DIRECT entry
while the range/instance are composed: check `key`/`wantkey` semantics under
transitivity (§3's erased-key test on the wrong entry). W3 — item 4's routing
lands all bounded entries at the *first* level's linear (check at function head):
verify all four walks + the intersection visitor's tname pre-filter still visit
it at every level shape. W4 — §8 runs `ml_matches(lim=-1, include_ambiguous=1)`
under `world_counter_lock`: allocation-under-lock + re-entrancy audit, and its
world must be `entry_min_world`. Plan typos noted for the author phase: §B4
`make fix-whitespace` is broken in this worktree (manual rule per M1b AM3); §B3
purge duplicates `usr/share/julia/compiled`.

## 2026-10-30 — M1b round-1 bootstrap abort: root cause = DataType self-description (M1a latent bug fixed too)

Round-1's full rebuild aborted in `jl_restore_system_image_from_stream_` (staticdata.c
fixup `else abort()` — a Module object failing `jl_is_module`). Debug (writer- and
reader-side probes + gdb): restored builtin types had `smalltag == 0`; the writer's
live types had it correct (module=8). **Root cause:** `jl_datatype_type` is
self-describing, and its 8th field (`flags`, `jl_svecset(..., 7, jl_uint16_type)`,
jltypes.c:3916) still declared the memoized bit-group as **uint16** — vanilla's
bit-group was exactly 16 bits. M1a widened the C group to 17 bits (`has_open_set:1`)
without updating this, and M1b's `open_set_epoch:15` moved `smalltag` to bits
26–31 — fully outside the 2 bytes the serializer writes ⇒ every small tag lost
⇒ `jl_is_module`/`jl_is_code_instance` fail ⇒ fixup abort. **M1a shipped a latent
form of the same bug** (tags ≥32 would have lost their MSB; Base's are <32 — luck,
caught only because epoch shifted the bits). **Fix (coordinator):** field 8 now
`jl_uint32_type` (+ comment), `jl_new_uninitialized_datatype` zeroes
`open_set_epoch` (it zeroed every field except the new ones — garbage epoch was
benign-but-wrong). `jl_datatype_size(DataType)` 54→56 (matches sizeof) — staged
images purged, full rebuild running. **Invariant for review-focus (§5 of
workflow.md): widening a self-described struct's bit-group (jl_datatype_t,
jl_typename_t, jl_code_instance_t …) MUST update the matching `jl_svecset(...->types, …)`
entry — serialization follows the self-description, not the C struct.** Debug
probes removed; staticdata.c back to authored state. Author's round-1 fixes stand
unchanged; all ten gates + Base suites run after this build.

## 2026-10-30 — M1b review round 1: request-changes; coordinator rulings

Fresh reviewer: **request-changes**. 2 blockers, 4 majors, 4 nits — all
reproduced independently by me as **new red gates** (`m1_open_family_fold`,
`m1_late_open_stale`, `m1_parametric_member`, `m1_union_isa`, `m1_wrappers`;
all five fail at exactly the bug sites on the current build; README lists them).
Blockers are silently-permanent miscompiles, not incompleteness:

- **B1 (ruled: fix)** `jl_could_join` short-circuits `0` on same-open-family
  names *before* the parameter recursion → a parameter-position flip gets folded
  `Const(false)` with unbounded max_world. Fix = fall through to the recursion.
- **B2 (ruled: fix via epoch)** the memoized `has_open_set` bit never
  invalidates when a set opens later — every fold gate reads it, so
  types interned before `@trait` misfold forever. **Design:** global
  `jl_open_set_epoch` (uint16, bumped in `jl_set_open_set`), a new
  `open_set_epoch:15` bitfield in the existing memoized uint32 (**15 free bits
  verified — struct size unchanged**, so no image wipe; tripwire stands), lazy
  depth-first recomputation wherever a memoized bit is trusted (`jl_has_open_set_in`
  stops, `jl_precompute_memoized_dt` reads); DFS back-edge → false is sound
  (a positive witness has a finite path); epoch-inequality (not `<`) triggers
  recompute so image-load epochs are safe; error at epoch saturation.
- **M1 (ruled: fix)** parametric `@implement` answers as the bare family —
  `jl_instantiate_type_with` on the entry instance no-ops because the
  instance's tvars ≠ the pattern's tvars. **Fix:** position-pair the two
  UnionAll chains in `jl_membership_lookup` (equal lengths or refuse the fold);
  and `Traits.jl @implement` gains a parametric form producing both sides from
  one `where` (shared tvar objects) — author may edit `oc-traits/src/Traits.jl`
  (library), gates remain theirs no-touch. Free-x-side tvars leaking into the
  recursive `jl_subtype`: guard conservatively.
- **M2 (ruled: fix)** `jl_subtype_via_membership` blind at parameters → entry
  positives fold through `subtype_tfunc`/`isa_tfunc` on Const pairs (latent,
  stock inference masks it). Fix mirrors B1's parameter walk.
- **M3 (ruled: fix)** type-value isa through `Union{X, ...}` false while
  `<: Type` and dispatch say true — `jl_isa`'s union branch must descend arms
  with the `Type{v}` rule.
- **M4 (ruled: fix in this milestone)** wrapper binding bug — **located
  exactly**: `src/builtins.c:2606 add_builtin("Dynamic", jl_dynamic_type)`
  binds the DEFTYPE; parameterized builtins bind `->name->wrapper` (verified
  `typeof(Core.Dynamic) == DataType` → `{Int}` throws expected-UnionAll). All
  four wrappers affected; Keyed additionally constructed with `super=NULL` at
  `jltypes.c:3888` (reviewer's print-SIGSEGV route). Pre-existing in M1a's
  commit but the erasure rules are untestable until fixed.
- n1 sort `jl_lookup_membership` in the XX list; n3 `min_world = world_age`
  deviation APPROVED as amendment (this note is the record); n4 dead
  `(size_t)-1` branch: author's call.
- Reviewer's retraction accepted (their p13/p14 CI-leak suspicion was
  upstream-consistent runtime behavior, not a violation).

Gate-script ownership lesson holds: reviewer's suggested gate shapes adopted,
written by me (behavioral pins, not mechanism-echoing).

**Dispatched (round 1 of 2):** author resumed with binding rulings (B2 epoch
design spec, M1 positional-pairing + Traits.jl parametric form; file list
extended to `oc-traits/src/Traits.jl`). Acceptance now 10 gates (old 5 + 5 red
ones) + Base three suites. M2 planner launched in parallel (read-only; avoids
in-flight files, anchors by function). Reviewer re-check is round 2 after the
author rests.

## 2026-10-30 — M1b implemented (author), gates 5/5, under review

Author applied `m1b-editplan.md` (13 files, +461/−21, uncommitted, no layout
change; the `julia.h` line is only my M1a `JL_NONNULL` placement fixed).
**All five gates pass** on the build; Base's three suites 1:49 / exit 0.
Sanctioned deviations from plan §A: `codegen.cpp` (the `issubtype` constant
fold + `update_julia_type`'s Bottom-constant path — real SIGILL sources),
`typelattice.jl` (the `tmeet` fix had to join the lattice arms), and a new
`builtin_tfunction` early-const-eval gate (root cause of most gate failures:
the early arm eagerly *evaluates* `isa`/`<:` on consts and records one world's
answer). Semantics deviation under review: **`jl_declare_membership` stamps
`min_world =` the declaring task's world age** (mutation semantics; the old
`counter+1` was unachievable for authors who read the world first, since every
top-level statement opens a world) — the `jl_new_datatype` hook keeps
`counter`, which coincides during a definition's own world; both under the
reviewer's microscope, plus the rewritten core helper (`inst == y ||
jl_subtype(y, inst)` replaces the plan's per-param comparison).

**Three gate-script defects fixed (coordinator's files, Tier C)** — each was a
bug in my gates, proven by the author on vanilla Julia: (1) `late_implement`'s
`e.min_world == w_old + 1` unreachable (top-level statements each open a world
— now `min_world > w_old`, mutation semantics); (2) `typevalue_isa` tried to
run an *inline closure* in an old world (MethodError by construction — now the
early-defined `vprobe`); (3) `util.jl` walked `ci.next` past the last link
(undefined field). Lesson for briefs: **gates get audited too — acceptance
artifacts are code.**


## 2026-10-30 — M1a gate closed (inert), committed

Full rebuild green after the image-wipe (see the build-fact note below). Inertness
gate: `test-subtype test-core test-ambiguous` one invocation, **1:55.72 wall vs the
2:03.36 control (−6.2 %, inside ±10 %), RSS +0.05 %, exit 0** (`numbers.md`,
`logs-m1a-check2.log`). One test edit, expected not regression: `test/core.jl:47`
hard-codes TypeName's atomic-field list; `:memberships` joined it (upstream
convention for a new atomic field). Committed on `oc-build`: **`2a2b2ba749`**
(the substrate, 6 src files + the test list) and `361d3014f8` (oc-build.sh + a
.gitignore line).

**Build fact #2:** `src/jl_data_globals_defs.inc` is *generated* from
`src/jl_exported_data.inc` (Makefile :302) and gitignored — hand-editing it is
harmless (the generator overwrites with the same content if the XX list carries
the entries), but only the `.inc` XX list is the real surface; do not fight
gitignore over the derived file.

**Workflow (user's call, from M1b on):** written out as **`oc-notes/workflow.md`**
(in force): coordinator (main session) briefs/approves/arbitrates, holds the build
slot, notes, numbers and all commits; planner → plan reviewer → author →
implementation reviewer (≤2 rounds, disputes escalate); single writer per tree,
one build job machine-wide; risk tiers so small steps skip ceremony. M1b is the
worked example.

## 2026-10-30 — M1b recon: the insertion points (read-only, line numbers at `45b6d15e34`)
All in `src/subtype.c` unless noted. The fallback itself will be one helper
(`membership_member_p(x_pattern_datatype, set_name, world, &entry_out)` in
subtype.c or datatype.c) doing: walk the member's TypeName list
(`jl_typename_memberships`), filter `entry->set == set_name` and
`min_world <= world <= max_world`, match the member pattern.

1. **Main chain walk, `subtype()` datatype case** — `:1580-1582`
   (`while (xd != jl_any_type && xd->name != yd->name) ... ; if (xd == jl_any_type) return 0;`).
   At the `return 0`: if `yd->name->open_set` (and `xd`'s name not `never_member`),
   consult the fallback before answering 0. Matching for parametric members: the
   entry's `member` is the member *pattern* (UnionAll `S{T} where T`); bind its
   tvars matching x (`subtype` of pattern-with-vars against x is the wrong
   direction — instantiate by `jl_instantiate_type_with` after unifying the
   pattern's `S{...}` args with x's, as `typemap`/`morespecific` do), then compare
   the instantiated `instance` against the query the way the chain case compares
   params (`forall_exists_equal` per param). World: `jl_current_task->world_age`.
2. **UnionAll pre-walk, `subtype()`** — `:1533-1538` (`if (xd == jl_any_type)
   return 0;`, reached when either side is a UnionAll, e.g. `S <: X` with the
   bare set reference `X` = its UnionAll wrapper for parametric sets, or
   `S{T} where T <: ... <: X`). **This must get the same fallback** or the main
   walk never runs for exactly the bare-name case.
3. **`jl_isa` type-value branch (review L10)** — `:2513`; the `else { return 0; }`
   at `:2546-2548` (x a ground type value, t a non-`Type` datatype: the vanilla
   argument is "a type object's `typeof` is a Core kind, subtype-of-datatype is
   false" — membership breaks that argument). Patch: `else if (!open) return 0`
   so an open set falls through to `:2550` (`subtype(DataType, t)` → false,
   DataType is `never_member`) and `:2552-2558` (the `jl_wrap_Type` path:
   `subtype(Type{S}, X)`), where the fallback answers through the *member's*
   entries: the `Type{S}` case asks the entry question for `S` itself. (Verified
   the vanilla fast path is only about Core-kind `typeof`s, so the patch can be
   narrow.) `jl_is_concrete_type(t) return 0` at :2523/:2562 stays: sets are
   abstract, so never concrete (`@trait` declares only abstract types; open
   *struct* sets would need this revisited — not in this build).
4. **`obviously_disjoint`** — `:541`; the both-chains-exhausted `return 1` at
   `:565-570`: consult the fallback (known member ⇒ return 0, *not* disjoint —
   exact; non-member ⇒ 1 stays exact). Reached from `jl_type_intersection`
   (:4448, :4604 pre-checks) and `jl_has_empty_intersection` (:4472).
5. **`intersect_all` datatype case** — chain walks at `:4292-4299`, both
   exhausted ⇒ `return jl_bottom_type`: consult the fallback; known member ⇒
   continue as the matched-name case (`intersect_sub_datatype(y, xd, ...)`
   direction x-side), non-member ⇒ bottom (exactness holds, review H2).
6. **`generic_wrapper` erasure rule** — in `subtype()`'s datatype case *before*
   the chain walk: x-side `Dynamic{S}`/`Compiled{S}`/`Kept{S}` vs a non-wrapper y:
   answer `subtype(tparam0(x), y)` ("member of X at the erased key");
   `Keyed{X,R,F}` vs non-`Keyed` y: `subtype(X, y)` plus the key question when y
   is a set the pattern's key refines (Keyed-vs-Keyed and the key-match rules
   ride with C7 at M2 — M1 gates never build Keyed values).
7. **`jl_could_join(S, X)`** (new, exported): M1 form = `open_set(X) &&
   !never_member(S) && S != X && (known-member || could become one)`; the
   "final" refinement arrives with M2's stopgap (which knows the future-world
   picture). Conservatively true is always safe (its only job is refusing a
   negative fold).
8. **`has_open_set` upkeep** — `jl_precompute_memoized_dt` (jltypes.c:1843):
   set the bit when the datatype's own name is `open_set` or `generic_wrapper`,
   or any parameter (through `Type{...}`, `Union`, `UnionAll`) has it — a
   recursive `jl_has_open_set_p` over the type tree, cached on the datatype. No
   serialization work needed: the memoized word is part of the raw struct dump
   staticdata writes for DataTypes (confirmed by how the 19→20 TypeName field
   change broke the stale image — scalars ride the memcpy, pointer fields get
   relocated), and `@trait`'s open-then-reference atomicity means no type is
   ever built *naming* a set before the set is open.
9. **ccallables for the library + Compiler** — add `XX(jl_set_open_set, ...)`,
   `XX(jl_is_open_set, ...)`, `XX(jl_has_open_set, ...)`, `XX(jl_could_join, ...)`
   to `src/jl_exported_funcs.inc` alongside the already-declared
   `jl_declare_membership`; `jl_exported_funcs.inc` is the convention (generates
   the `ijl_` aliases); ccalls from `oc-traits` and `Compiler/src/tfuncs.jl`
   resolve through libjulia-internal's dynsym.
10. **tfunc gating (M1's Compiler half)** — `Compiler/src/tfuncs.jl`
    (`isa_tfunc`, `subtype_tfunc`, `typeassert_tfunc`, the `tmeet`/`typesubtract`
    /`hasintersect` negative sites) + `typeutils.jl` `conditional_tfunc`: a
    negative fold (`isa` ⇒ `false`, meet ⇒ `Union{}`, subtract ⇒ unchanged/left)
    requires `!jl_has_open_set` on the involved types or `!jl_could_join`;
    positives may fold only *through entries*, and each fold raises the CI's
    `min_world` to the entry's (review M6) — the raise needs a mechanism: the
    tfuncs run inside inference, whose `min_world` bookkeeping takes the max
    over backedge worlds; add the entry's world as an inference-time tracked
    world via the same path `methods` matching feeds (`CurCode.min_world`),
    detail at edit time.

Also landed (outside the build tree): `oc-traits/src/Traits.jl` first cut
(`@trait`/`@implement`/`isopen`/`declare_membership` — ccalls to the entry
points above; `@implement` passes the *user's* module as declarer) and
`oc-traits/gates/m1_*.jl`, the four M1 gate scripts (late membership both
worlds; pre-compiled isa/subtype/tuple/typeassert answering both worlds —
review H3; positive folds bounded by the entry's `min_world` — review M6;
type-value `isa` through the `Type{S}` entry, non-members exact — L10/H2).
`util.jl` walks CIs via `Base.specializations` + `ci.next`.

## 2026-10-30 — M0 gate closed; M1a landed (types, entries, the declaration)

**M0 final gate data.** Baseline build green (exit 0, `45b6d15e34` untouched).
Control `make test-subtype test-core test-ambiguous` on the vanilla build:
**2:03.36 wall, 2.27 GB peak, exit 0** (`oc-notes/logs-m0-control.log`) — M1's
gate measures its own run of these three against this number (±10 %).

**Build fact (cost 30 min to learn):** the staged system images
(`usr/lib/julia/basecompiler.so`, `sysbase.so`, `sys.so`) are *not* make-stale on
`src/` changes — sysimage.mk's rules key on `BASE_SRCS`/`VERSION`. When
`jl_typename_t` changes size, an old image cannot be restored by the new runtime
(the restore aborts deep in `staticdata` with a desynced fixup list — the
`else abort()` looked like a real serialization bug for a while). After every
`julia.h` struct-layout change: `rm usr/lib/julia/{basecompiler,sysbase,sys}.{so,o.a}`
(and `usr/share/julia/compiled`) before `make`.

**M1a (the substrate, inert until a set opens) — what landed and how:**

- **Finding: this 1.13 `jl_subtype` carries no world** — the 1.10-style
  `jl_subtype_env(x, y, env, world)` threading is gone (`jl_subtype(x, y)`;
  `jl_stenv_t` has no world). Entry world protocol therefore: the subtype/isa
  fallback checks `min_world <= jl_current_task->world_age <= max_world` (the
  `invoke_in_world` gate works because that call sets the task's world_age);
  world 0 (build time) sees all; C dispatch paths that have a query world pass it
  explicitly (M2). tfuncs never consult entries for negatives at all, so the
  inference lattice stays world-independent as upstream.
- **1.13 globals are the `sysimg_global` struct**: new C-visible names
  (`jl_membership_type/keyed/dynamic/compiled/kept`) are added to
  `src/jl_exported_data.inc` (XX list: serialization + the extern copy) and
  `src/jl_data_globals_defs.inc` (`#define jl_X (sysimg_global.X)`); do not write
  `extern` for them — the macro is the internal-TU declaration.
- **`jl_typename_t`**: `_unused:5` → `open_set:1`, `never_member:1`,
  `generic_wrapper:1`, `_unused:2`; new `_Atomic(jl_svec_t*) memberships`
  registered in the synthetic `jl_typename_type` layout (names 19→20, types svec
  19→20 with `jl_simplevector_type` at slot 19, `atomicfields` gains bit 19;
  `n_uninitialized` stays 18 = `20 - 2`, the same reason as the old `19 - 2`:
  only name+module are set before the first allocation in `jl_new_typename_in`).
  `jl_new_typename_in` initializes `memberships = jl_emptysvec`.
- **`jl_datatype_t`**: the memoized bit group widened `uint16_t → uint32_t` (it
  was full) with `has_open_set:1` added; memoized bits are recomputed at
  construction and image load, nothing serializes the word itself.
- **`jl_membership_t`** (Core's `MembershipEntry`, `jl_new_datatype`-registered):
  `{set::TypeName, member, instance, key, min_world::UInt64, max_world::UInt64,
  declarer, by}` — **max_world added** to the plan's §4.1 field list (a
  redeclared key stamps the superseded entry a max_world, review M6; the field
  exists from day one so the objects are write-once-after-publication).
  `key == nothing` means the erased key (§2.6's `Keyed{X,Nothing,Nothing}`).
- **Publication**: `jl_declare_membership(member, set_instance, key, declarer, by)`
  in `datatype.c` — validates (never-member refused; closed set refused; the four
  Core wrappers refused as patterns — "members by rule, not by declaration"),
  then the `jl_method_table_insert` protocol: `world_counter_lock`,
  `world = counter+1`, publish the copy-on-write list (atomic release store;
  readers filter by the world range, so the entry is invisible until the counter
  advances), release the counter.
- **Core kinds** (`never_member`): DataType, UnionAll, Union, TypeofBottom,
  Module, TypeVar, IntrinsicFunction, OpaqueClosure, GenericMemory,
  GenericMemoryRef — via the `*_typename` globals where the `*_type` global is a
  wrapper (unionall/uniontype marked through the unwrapped body).
- **Core attribute/refinement types**: `Keyed{X,R,F}` abstract (3 tvars);
  `Dynamic{X}`/`Compiled{X}` (`object::Any`), `Kept{X}` (`object::Any`,
  `compiled::Bool`) concrete — all C-declared (`add_builtin` in builtins.c), all
  four with `generic_wrapper:1`: subtyping erases to parameter 1 (the rule lands
  in M1b with the subtype fallback; `Keyed` additionally matches the entry's key
  on the y side). Julia-side constructors are M5 work (ccall pattern); M1's gates
  do not build values.
- **`T <: X` with `X`'s name open** (concrete `struct` *or* `abstract type` —
  the set-in-set case §2.2) gets a membership final as the supertype, declared
  with the type: the `jl_new_datatype` hook appends `{member = wrapper,
  instance = super}` (they share the pattern's tvars), `min_world =
  jl_world_counter`, declarer = module. M1a is inert: no typename is open yet.

## 2026-10-30 — M0 complete; M1 recon (while the baseline build runs)

**M0 outcome.** C7 count pass 2 settled the numbers (verdict in `numbers.md`): under
exact intersections + C7-in-`morespecific` (P3), a bounded-method definition invalidates
≈ its own member entries (C: 0–13 for the real functions, ~20 per hypothetical `show`);
the flag placement would reach A = 92–99 % of every session's entries (400–730 per
foreign definition). P3 and D5 confirmed; recorded with caveats.

**Baseline build** of `julia-oc` running (`oc-build.log`; deps from the shared srccache).
M1 sources must not be edited until it is green (mixed object files).

**Recon for M1 (verified against the vanilla tree):**
- The subtype fallback goes into **two** chain walks in `subtype.c`: the main datatype
  case's `xd == jl_any_type` return-0 (line 1582) **and** the earlier UnionAll-path
  pre-walk (1534–1538), which would reject the same pair before the main case is
  reached. A shared `membership_sub(x, y, e, param)` helper covers both; on a match,
  the entry's `instance` instantiated in the match environment must be compared
  against `y` the way the chain case compares parameters (1585–1595).
- **1.13 has no hand-written typename marking**: `jl_typename_t` is GC-traced through
  the *synthetic datatype* `jl_typename_type` (jltypes.c:3034–3063: 19 names + types,
  `n_uninitialized = 19 - 2`, const/atomic bitmasks). Adding a `memberships` svec
  field therefore means: the C struct field (julia.h, append after `concrete_only`),
  name+type in the synthetic layout (19→20; keep the idiom `20 - 3` with the new field
  always initialized to `emptysvec`), both bitmasks leave bit 19 clear (it is
  write-on-declaration, lock-guarded, not atomic, not const), and initialization in
  `jl_new_typename_in` (datatype.c:70–82, which already stores `emptysvec` into the
  cache fields). `n_uninitialized` semantics to double-check at edit time
  (reads of `jl_datatype_nfields`-style code; the `19 - 2` / `8 - 3` idiom =
  nf minus always-initialized).
- Serialization: `staticdata.c` queues typename cache fields explicitly (:729);
  `memberships` joins that queue only at M6 (image activation). For M1–M5 no
  serialization is needed, but check `ircode.c:1657`'s TypeName special-casing
  does not assume 19 fields.
- The plan's P6 stopgap hook lives in `jl_method_table_activate` (gf.c:2953); the
  world protocol mirrors `jl_method_table_insert` (its wrapper at :3213 activates).
- Upstream dev workflow from `julia-oc/AGENTS.md`: `make fix-whitespace` before
  commits, per-file clang analysis (`make -C src analyze-<file>`), GC pushes flagged
  by the analyzer, `make test-revise-<name>` (with `Revise.track(Base)`) for Base test
  iteration, `JULIA_TEST_FAILFAST=1`.

## 2026-10-30 — C7-count: pass-1 findings, script rewritten, pass 2 running

Pass 1 (logs `*-pass1.log`, 10 minutes wall, depot warm) exposed three flaws, all fixed:

- the census's `function` column holds **bare** names (the qualified string is in the
  `method` column); the resolver short-circuited single-part names to `Main`, so most
  rows failed or grouped under the wrong module. Now: names resolve from every root
  seen (Main, Base, Core, TraitWorld, each row's `function_owner` and
  `defining_module`), and `A+B` bounds are tuple-of-sets conjuncts (member of the pair
  = member of all parts, traits §3.7). One row per (method × position) — the census
  puts several positions on one line (`1:Positions 4:Scale 5:ColorSpec`).
- `TypeVar` has field `ub`, not `upper`, in this 1.13.
- Added the **hypothetical `Base.show` pass**: U5's real bounded functions are small by
  construction (zero foreign functions), so the D5 stress case is E-259's
  `show(::IO, ::X)`; the pass counts Base.show's position-2 entries under both
  placements for every set in U5's `<label>-hypo-show.tsv`.

First reading (tw session, confirmed across sessions in pass 2): `Base.show` holds
~417 dispatch entries; the flag placement reaches A=385 of them (92 %), the
`morespecific` placement B=12 (2.9 %) plus the unenumerable "no method" backedges;
genuine re-dispatch C is 0–61 per set. Ratio A/B ≈ 30× at the stress case, ≈ 4× at
the real bounded functions — supports P3 (C7 in `jl_type_morespecific_`) and D5's
acceptance. Caveat recorded: the count itself compiles a few new `show` entries as it
runs (the first set sees ~12 % fewer), so A/B are order-of-magnitude proxies.

## 2026-10-30 — run_all bug (fixed)

`run_all.sh` initially passed `--project=env_tables|env_tde|env_makie` without the
`experiments/w83/u5/` prefix (a sed that never matched the `--project=$env` line):
those three labels died at `using TraitWorld`. Rerun with full paths in
`run_fix3.sh`; `forks` and `ndport` were unaffected.

## 2026-10-30 — classifier reading, "final non-member"

The count's untouched class K is **never-member kinds** in the U7/E-255 sense (Core's
`DataType`, `UnionAll`, `Union`, `Module`, `TypeVar`, `TypeofBottom`, `Builtin`,
`OpaqueClosure`, `GenericMemory`/`GenericMemoryRef`), not subtype-finality: a concrete
Base type like `Int` *can* receive a membership later (BaseTraits declares memberships
on Base's types), so an entry at `Int` is in the flag placement's reach and counted in
A. This follows exploration §2.8's "Core's kinds are never members" and §2.2's final
list; a subtype-finality reading would have excluded every concrete non-member and
understated A.

## 2026-10-30 — M0 setup

- Worktree `julia-oc/` created at `45b6d15e34`, branch `oc-build`; `deps/srccache`
  symlinks `julia-1.13/deps/srccache` (the `deps/` specs are identical between base and
  the old tip — no commits touch `deps/` between them — so all tarballs are cached);
  `oc-build.sh` mirrors the old tree's `tw-build.sh` (`make -j4`, niced, 4 GB watchdog).
- Old build status: `julia-1.13/` sits at the U5 commits exactly (`00dcc9994c`,
  TraitWorld `33dd55e`, TraitCSV `9c6477b`, TraitTables `438ac2b`), so the U5 sessions
  reproduce; `~/.julia/agent-depots/w83u9` (U9's depot) still has the warm precompile
  caches and is reused. The old build's own footprint for background reference:
  43 files, +2458/−158 over the base.
- C7-count experiment: `oc-notes/c7count/c7count.jl` (+ `run_all.sh`, `run_fix3.sh`).
  Enumeration is via `Base.specializations(m)` (in this 1.13, `m.specializations` is a
  head `MethodInstance` or `SimpleVector` depending on cache shape; `CodeInstance.next`
  chains the compiled ones; the iterator handles all of it). Selfcheck in the script
  asserts 3-of-3 on a fresh function.
- Upstream anchors verified at `45b6d15e34` (all exploration/review citations hold):
  `_unused:5` julia.h:560 with `concrete_only` below it; chain walks subtype.c:1535/
  :1580, intersect :4294, `obviously_disjoint` :541; `jl_method_table_activate`
  gf.c:2953; typemap name probes :708/:973/:988/:1183, `tname_intersection_dt` :399;
  `isa_tfunc`/`subtype_tfunc`/`typeassert_tfunc` tfuncs.jl:877/917/859; `jl_isa`
  type-value branch subtype.c:2513+; `has_concrete_subtype`/`maybe_subtype_of_cache`
  julia.h:645–646.

## 2026-10-30 — the user's decisions (P1–P8 in the plan §1)

- P1 the code slot is built; the second-owner (`:facts` copies) design is never built.
- P2 boxed adapter: variant (ii), per-key wrapper + run-time offset table.
- P3 C7 in `jl_type_morespecific_` (review M2); M0's experiment confirms, does not gate.
- P4 the machine-code store stays out of the first build; the record is still built.
- P5 no upstream preparation; a fork.
- P6 the membership stopgap (a): the insertion walk; guards replace its code half at M5.
- P7 base: vanilla v1.13.2 at `45b6d15e34` (all exploration/review citations verified there).
- P8 notes in `oc-notes/` only; the prior record is read-only background.
