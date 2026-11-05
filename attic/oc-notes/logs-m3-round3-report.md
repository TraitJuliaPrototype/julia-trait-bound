# M3 round-3 report — basecompiler AOT hang root-cause hunt (builds #4/#5 aftermath)

STATUS AT TIMEBOX: no build launched (no confirmed fix — bisect route per your rules).
Tree at rest (repo = intact M3; usr/share/julia/Compiler/src re-synced byte-identical to repo; no orphans; no git writes).

## 1. TREE INTEGRITY INCIDENT — external writes to the repo tree (please read)

- 16:19:58: `julia-oc/Compiler/src/abstractinterpretation.jl` was overwritten with its HEAD
  content (losing all M3 hunks) and an empty `Compiler/src/KEEPFACTS` file appeared.
- Same signature as the earlier `Compiler/src/facts.jl` deletion (~between 13:52 and 16:20).
- Signature matches a run of MY `/tmp/opencode/bisect.sh` variant but with SRC pointed at the
  REPO instead of usr/share (the empty KEEPFACTS is exactly its `git show HEAD:Compiler/src/KEEPFACTS > "$SRC/KEEPFACTS"` redirect failing; the ai revert matches the loop's next iteration; the facts.jl deletion matches its `rm -f "$SRC/facts.jl"`).
- I did NOT run any such command against the repo. If a coordinator-side bisect ran my script
  template from the repo root with SRC=Compiler/src, that explains both incidents.
- RECOVERY: both files restored from `/tmp/opencode/share-snap/` (pristine copy of the 13:52:50
  build-copy = current-intended state, taken before all bisect runs). Verified: all 10 touched
  Compiler files in repo == share-snap == usr/share; `git diff --stat` back to +305/−37 over
  14 files; abstractinterpretation.jl 4686 lines, facts.jl 844 lines.
- ACTION: the M3 ai content existed ONLY in repo+share-snap+usr/share; had share-snap not
  existed, M3 abstractinterpretation work would be lost. Suggest one commit (yours) at next review.

## 2. Round-2 implementation items — landed and kept as briefed
- §3c.2 reinfer arms (neutral record-kind skip arms + R-8 ResultEdge descent via edge.ci).
- §3 ForwardToBackedgeIterator: record skips + InlineIdentity `i += 1` fix (identity rides after the (sig,ci) pair).
- MethodCallResult.facts leak removed (field reserved, default-false; re-run frames compute policy at inferencestate.jl:873). Plain cache-hit path back to upstream cost.
- All files re-pass Meta.lower. Guards (a)–(g) of your audit: quoted in round-2 message; one genuine leak (facts-per-result) found + fixed.

## 3. Root-cause hunt — evidence matrix (harness = your command, timed; healthy = EXIT-0 ≈ 310 s, eval ~281 s + ~1 min emit)

Reproduced stuck in-harness: harness1/2 + all D-variants — deterministic ~644 M allocations at 420 s at IDENTICAL point under −O0/−O1 (not LLVM slowness; SIGINT ignored → deep native loop). SIGTERM shape (your log + mine identical): create_native → jl_compile_method_internal → jl_type_infer → jl_apply → … → jl_compile_method_internal → jl_compile_codeinst_now → LLVM.

| variant | result |
|---|---|
| CONTROL all Compiler .jl = HEAD (facts.jl un-included) | EXIT-0 310 s |
| ai=HEAD, ALL other M3 + facts.jl included (×3 re-runs) | EXIT-0 310–315 s |
| FULL M3 | STUCK (>46 min build #5; 420 s harness) |
| ai = HEAD text + 58 filler lines (line-shift artifact test) | EXIT-0 340 s — artifact hypothesis DEAD |
| ai = M3, split/fold/known refs → local `nothing` dummies (B) | STUCK |
| HEAD + ONLY const FACTS_ABSTRACT_REASON (C) | EXIT-0 320 s |
| M3 minus (bail arm + find_method_matches kwarg/gate + const) (D) | STUCK |
| M3 minus H3 records only (E) / minus H6 guard only (F) | STUCK / STUCK |
| M3 minus {records+guard} (H346) | STUCK, DIFFERENT loop: 591 M vs 644 M allocs, GC 313 vs 293 → TWO independent runaway loops |
| per-hunk disables H12/H5/H4A (each) | STUCK, all ≈644 M/GC 293 |
| G: full M3 + behavior-neutral MARKERS in finish!/acm-constructions/bail/arms, facts arms replaced by inert marked returns | STUCK, ZERO marker firings during the hang, eval-phase summary collapsed 281 s → 24 s |

Readings so far (serial runs only — all solo, window ≥420s vs healthy 310–340s):
1. NOT a line-number artifact; NOT any single hunk; NOT the three f===split/fold/known binding refs; NOT the const alone; NOT bail-remark/G2/records/guard individually.
2. The two-allocation-signatures (644 M vs 591 M) ⇒ ≥2 independent emit-time loops, which is why single-hunk disabling never moved the needle.
3. G's zero marker-fires: the re-included Compiler's finish!/abstract_call_method code never RAN during the runaway (markers compile out under `if false`-style neutralization is ALSO why eval collapsed to 24 s — G was not a clean observer; treat its stuck verdict as: neutralized-arms version still hangs).
4. The only binary constant across every stuck run vs every healthy run remains: ai contains M3 content in the body of abstract_call_method/abstract_call_method_with_sparams/abstract_call_gf_by_type region (all healthy variants: HEAD text of those functions; all stuck: ≥1 M3 remnant in-file).
5. Working theory (fits 4): these functions' methods exist in the sys.so Compiler too; during create_native the emit-time jl_type_infer cascade runs inference with the SYS.IMG-Compiler engine (its cached MIs/worlds) while the live module's bindings now hold the re-included versions; the M3 refs (ccall `jl_has_open_set`, facts.jl globals, the 8th MethodCallResult field, `sv.facts` loads) create sysimg-code ↔ new-binding backedge/version churn that the emit-time loop never settles. Deterministic, OOM-shaped, plain-path (no facts frames involved).

## 4. In flight at send time: 13 single-hunk MINIMALITY probes (HEAD + exactly one diff-hunk each)
All 13 launched in parallel at 17:11:14 (16 cores); verdict ≈ 17:17–19. This is the decisive matrix: every prior disable-probe removed a group but left ≥1 other hunk, so minimality was never tested. Whichever (which) single-hunk variants go STUCK identifies the minimal poison set ⇒ a targeted fix (guard or restructure that hook) without losing §R bindings.
Results + fix recommendation: follow-up message.

## 5. Battery
Not run: any gate/AC verdict on the M2 sysimage (usr/bin/julia linked 13:00:14, yesterday's M2) would be invalid per I3 protocol. Gates runnable only after a successful M3 build.

## 6. Tree state
- git status --porcelain: 14 M files (Compiler×9 incl. reinfer, src/gf.c, src/jl_exported_funcs.inc, src/julia.h, src/staticdata.c, src/subtype.c) + ?? facts.jl (new, 844 lines) + ?? oc-build.{ts,rss}.log. diff --stat: +305/−37.
- No build processes; no orphans; bisect kit in /tmp/opencode (bisect.sh, share-snap/, drA–drH*/, probe*.log, probe*result.txt, mkG.py) — all evidence retained.
- Build slot: free, unused.

## 7. Deviations ledger (unchanged from round 2 + additions)
- optimize.jl / ssair/show.jl file-set additions (InliningState.facts field).
- add_extra_cache_for_all!/ALL_CACHE_BUDGET orphan → §5 over-spec, left inert.
- fold_holds AtLoad-only contract; G2 AtLoad keep; reinfer arms per R-8.
- facts.jl content as landed (§R rulings R-1/R-3/R-4/R-8/R-10/R-12, D4/D6/D9 unchanged).
- NEW: tree-integrity incident §1 above.

## 8. MINIMALITY MATRIX — INVALID METHODOLOGY, RESULTS WITHDRAWN (kept for transparency)
HEAD + exactly ONE difflib-hunk of M3-ai (13 hunks; drH1..H13 via same dataroot harness):
- STUCK (≥420s, SIGTERM): H1(const block :53), H4(records block), H5(find_method_matches kwarg+gate),
  H6/H7/H8(bail-site constructions +`, nothing`), H9(MethodCallResult field comment-lines),
  H11(split/fold/known arms), H12(is_return_type arm), H13(merge_override_effects guard).
- CRASHED FAST (invalid combos, not verdicts): H2(kwarg-at-call-only MethodError), H3(arm-without-const UndefVar), H10(mismatch 2->3).
Cross-checked against earlier: HEAD+58 blank lines = HEALTHY; HEAD+57 blanks+const-block-at-file-head = HEALTHY (C);
but HEAD+const-block-at-true-position (H1) = STUCK. And H6/H7/H8 are ONE-LINE, zero-shift, SEMANTICALLY-NULL edits
(explicit 7th positional `nothing` = the default) — STUCK.
CORRECTION (17:26): the 13 parallel H-runs shared the box (13 heavy single-threaded jobs); the fixed 420s
kill window produced false STUCKs — H4/H6/H9/H11/H12 had not even reached the eval summary by kill (allocs
~190–305M vs healthy-eval ≈ 640M at healthy-eval-time), H1/H5/H7/H8/H13 printed the summary mid-contention.
The H-matrix proves nothing except that parallel heavy runs need proportionally-larger windows. THE
MINIMALITY EXPERIMENT IS STILL OPEN and is the top next step (rerun serially, or pairs, window ≥700s).
Serial-only valid matrix stands: {D,H12,H5,H346,H4A,E,F,B,G} stuck; {control, ai=HEAD ×3, A, C} healthy.
The withdrawn reading also removes the 'no-op token hangs build' claim (H6/H7/H8 verdicts were batch-false).
Original withdrawn text follows for audit: ⇒ Poison is neither line-shift alone nor any semantic mechanism (a no-op token hangs the build). What all stuck variants share and A/C lack: the re-included source bytes of a method that sys.so's
baked Compiler also holds differ — while sys.so (linked 23:08 yesterday) carries M2's UNCOMMITTED .jl state, and
HEAD = M1-only. The basecompiler step consumes sys.so's engine + re-included sources; my healthy controls all restore
~sys.so-era bytes. STRONGEST CANDIDATE MECHANISM (needs coordinator check): the sys.so/`usr/lib` C libs vs
`git show HEAD` skew — i.e. bisecting against HEAD(M1) is bisecting against a tree that NEVER existed at any image
build: sys.so has M2's typeinfer/effects/etc. (uncommitted-then-built), while every probe substitutes M1 versions.
The first edit ever made to ai (coordinator's archaeology) coinciding with first hang fits, but the A/C healthy runs
constrain it to "content-byte changes in files whose sysimg-baked methods participate in emit-time inference", not
mere line drift.
NEXT DECISIVE PROBES (6 min each, ready-to-run, NOT run — out of time):
  P-i:  HEAD-ai + 4 blank lines INSIDE :52 (partial pure-blank shift, zero content). stuck ⇒ byte/line-position
        participation; healthy ⇒ content-token sensitivity.
  P-ii: HEAD-ai + const block APPENDED AT FILE END (content, zero intra-file shift).
  P-iii: reconstruct the TRUE image-baseline ai (the bytes sys.so was built from: M2-era working copy, e.g. from
        13:52's own share-snap minus M3 hunks = exactly `git HEAD + M2-hunks` — M2 diff for ai = the bail-site
        7-arg forms ONLY, if M2 touched those) and verify: HEAD+M2-ai-state as dataroot ai ⇒ expected HEALTHY baseline;
        then re-add ONE M3 hunk on that baseline. All my probes used HEAD-baseline, which may be the wrong zero-point.
FIX PATH IF CONFIRMED: commit M2+M3 ai state as one; re-derive hunks on the image-baseline; no design change to §R.
