# Critical review #2 (Fable agent): binary work + post-review repairs

Verified against gf.c as built; probes in session scratchpad
(probe_poison/probe_invoke/probe_stale/probe_guard.jl). Ranked:

1. **Global CI-cache poisoning (VERIFIED, most damaging).** Any method
   compiled while the filter is active (sealed_mode NOT needed) stores an
   unnarrowed CI in the ordinary global cache; after clear_universe(),
   plain dispatch serves sealed answers forever (probe: 3.0 vs live 4.0,
   silent). The "immortal workers for free / not narrowing is sound"
   framing (README, notes 09) is unsound and contaminates check3's
   methodology (filter active across load + timed sweep).
2. **Inverse leak (VERIFIED for invoke):** jl_gf_invoke paths never consult
   the filter — invoke inside a sealed frame returns the pirate. P1b's real
   guarantee = "dynamically dispatched edges only".
3. **Sealed C cache stale for universe-INTERNAL evolution (VERIFIED):**
   only jl_set_universe_filter flushes; enrolled-module method definitions
   don't. Native backend unwired in TraitRegions, so the flush contract
   exists only in test scripts.
4. **Invalidation guard covers 1 of 3 channels** (dispatch backedges only;
   typename backedges + mt/leafcache wipe unguarded) — experiment passed
   because the scenario only exercises that channel. BUT attribution
   CONFIRMED by reviewer's own control: 446.9 ms in-universe churn vs 0.0
   scoped — the 456→0 result is real and the guard's.
5. **Sealed-cache concurrency:** wrong-MI on slot collision races,
   JL_GC_PROMISE_ROOTED after POP unsound on overwrite; duplicate
   declarations (cosmetic).
6. **Q3's premise false:** jl_task_t already has C-only hidden fields;
   a task field is routine. Thread-scoping compromise unnecessary.
7. **Q2 table not reproducible from committed tree; single runs.**
   Mitigation verified by reviewer: PT-tagging 0.0 ms AND load-churn kill
   both REPLICATE ON STOCK 1.12.2 — headline mechanism not
   patched-binary-only.
8. TraitRegions A3/duplicate guards are precompile-time only — image-merge
   load order silently overwrites (guard never runs at load).
9. sealed() silently downgrades when unfrozen; post-freeze loads re-break
   (x10 regression is now a convention, undocumented in writeup).
10. Doc drift: writeup still has "growing-with-stack-size", pre-P0
    __init__ friction text; TraitRegions docstring still recommends
    reinit; README describes P1a-only.

## Survives hostile review
Filter-below-matcher + shadow recovery (A5 fix at right layer); P1b for
dynamic edges; guard causality (reviewer-verified control); stock-Julia
Q2(b) chain; honest perf numbers (35/87-90 ns re-measured); QUESTIONS.md
format; seals-as-methods refactor + tests on stock 1.12.

## Directive
Do NOT present "immortality for free". Reframe as Q5 (open question);
scope P1b claim to dynamic edges; state guard covers dispatch-backedge
channel only.
