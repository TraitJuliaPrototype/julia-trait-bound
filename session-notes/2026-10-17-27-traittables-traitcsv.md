# Session 27: TraitTables and TraitCSV, the fresh-eye review (running notes)

The user (start of session 27): "Send out a Fable 5.1 reviewer that looks at the current state of the design. It needs a fresh eye review after the churn. Is it consistent? (e.g. is deep concreteness opt in or required?). In parallel continue the work on the demonstrators." Then: "please continue working on this without prompting me for input until the demonstrators and the associated julia runtime pieces are done."

**State at the start:** design repo 7f97aa1; TraitWorld 6bcca9f; TraitMakie, TraitDifferentialEquations, TraitReport as at the end of session 26.

## Log

- **The review** (Fable 5.1, `writeup/reviews/2026-10-17-consistency-fresh-eye.md`): the core after wrapping by facts is coherent; four significant inconsistencies, each touching a headline claim:
  1. concreteness opt-in in the text, unconditional (and stricter) in the prototype;
  2. Lemma O and "stakeholder" misstated;
  3. facts at non-public functions outside the rules;
  4. overrides after a conformance refused against rule P.
  Recorded as decisions waiting for the user (open-issues §1.5–1.8); minor findings in §5.5.
- **TraitTables** (new repository): `Column{T}`, every `Vector` by a family declaration, `Table` with `Vector{Dynamic{Column}}`, summaries, selection, sorting, printing. 14 tests.
- **TraitCSV** (new repository): `CSVColumn{T} <: Column` (the decision's `CellType`, renamed: the conforming values are columns), conformances for `Int`, `Float64`, `String`; `String15` in an extension. 10 tests. Definition checking refused a `sizehint!` on a trait object in the first draft.
- **TraitWorld fixes found by them** (f4b54a5):
  - a trait's name as a container's element type inside functions (`Column[]`, `Vector{CSVColumn}` arguments) now means its `Dynamic`, as the design says; before, only struct fields were translated;
  - **`Dynamic{X}` keeps only the views of `X` and its supertraits.** A column made from a `CSVColumn` trait object carried two views, so `floats(::Column)` got a new key and compiled in the session (0.16 s plot phase, 0.1 s exit): workers are compiled for what the bound sees, and a dynamic value now carries only that. A cached run-time computation, since generators run in their definition's world (tested);
  - the view caches' exit hook runs under the policy (its native code was invalidated by loads: 155 ms at exit); a cache that fails to build is removed instead of being retried at every exit; no flush while an image is generated (a detached build warned during precompilation).
  - Tests: 344 + 4 new pass on the patched build.
- **Measurement artefact:** the sandbox kills a detached view-cache build when the command ends, so caches stayed stale and every run paid at exit. Built in the foreground (`viewcache_flush()`) before measuring; user sessions are not affected.
- **TraitMakie** (681f4ed): `Bars`, `VLines`, `barplot`, `hist`, `vlines!`; the workload renders a histogram. The report's figure now matches Python's.
- **TraitReport form (t)** (0a4dc1f): a plain script over TraitCSV, TraitTables and TraitMakie; **form (pt)**, the same libraries without traits, as its fair baseline. Results (patched; README "Form (t)"):
  - fresh session: (t) 0.52–0.56 s, (pt) 0.50–0.52 s, Python 0.58–0.69 s, PlainReport 0.94–0.95 s. Small precompiled libraries reach Python's time with or without traits;
  - under loads (nine packages, both orders): (t) 66–80 ms, none of the three libraries' compiled code lost; (pt) 102–147 ms, 17 of 49 methods lost and 16 recompiled. Session 26's form (b): 5.3–5.7 s;
  - a strings column with `String15` (an extension's conformance): 44 ms in later sessions (0.7 s in the first, before the view cache holds TraitTables' summary for `Vector{String15}`); CSV.jl 3.9–5.0 s in every session.
