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
- **TraitDifferentialEquations step 4, row 5** (8c25ae3): Tsit5 generic in the element type, step control on primal values; `u0` promoted to the parameters' duals; `gradient(loss, p)` with the tag `Tag{Sig{Tuple{Vector{Float64}}, Float64}, Float64}` and the loss as a dynamic call; a guard for losses that capture duals (nested differentiation gets ForwardDiff's own tag). Row 5: first gradient 34–55 ms, a second loss closure 17–21 ms (SciML 1.97–2.73 s, then 2.48 s); ForwardDiff's own tag 0.67–0.87 s. Float32 states (row 6): 0.59 s first session, 0.105 s with the view cache.
- **Two runtime defects found by the rows, fixed in TraitWorld** (a19ba7e, 2e408cc):
  1. **Policy code ran native code through bare `MethodInstance` invokes.** The optimizer emits `:invoke mi` for a callee whose result was not cached when the caller was optimized (a recursion partner, an uncached callee); at run time that runs the instance's native code, which loads invalidate (row 1 after big loads: 262 ms, `_field_problems` recompiled natively, 225 ms). Now such invokes name the policy's CodeInstance when it exists, else call a trampoline (`_invoke_under_policy`); the callees are compiled under the policy after the outermost inference, so images keep them (`methods(::Any)` compiled at run time after loads cost 6.5 s: the policy's compiler code, §1.3). Calls that only throw keep plain Julia's code. On stock Julia, which cannot compile foreign code instances at run time, the trampoline calls plain Julia's code of the same method.
  2. **Family conformances found their builder in each session** (34 ms for `FunctionModel` and the integrator): a family declaration now defines a conformance method for the family with a builder registry in the declaring module, filled on the slow path and saved with the declaring package's image. (A generator cannot do it: code reflection is not allowed in generated functions.) Row 1: 47 → **6.4–8.0 ms in every load order**.
- **TraitMakie's workload** covers its own colour types on each recipe: first PNG 18–22 ms in every order without view caches (session 26's 62–65 ms relied on a view cache; without one it was 137 ms).
- **The system image** (`experiments/sysimage`, rebuilt): a new key after the big loads 104–107 ms instead of 6.4 s; `using` 0.11–0.15 s instead of 0.27–0.29 s; everything else as without it.
- **Row 9, errors** (`scripts/errors.jl`): TraitWorld now hides its own frames in stack traces (through Base's `update_stackframes_callback`, chained; `JULIA_TW_ALL_FRAMES=1` shows them). Case 1: 12 frames, longest line 289 (SciML 29, 3,789); cases 2 and 3: 30 and 25 frames (12 of them Base's broadcasting inside the user's function), longest lines 865 and 302 (SciML 5,574 and 33,673).
- **Row 11, run time per step** (`scripts/runtime.jl`): n = 3: plain function 206 ns, model type 173 ns (1.19×), OrdinaryDiffEq 355 ns; n = 1,000: within 1%, 15% slower than OrdinaryDiffEq's fused loops.
- **Rows 13 and 10, images** (`experiments/demos/images.jl`): patched images carry 30–60% more native code (piece 5); precompile times similar; `using` 0.22–0.29 s.
- **Julia piece 11 examined and deferred** (julia-support.md, last section): frames of two interpreters; asserted effects (G1.10).
- **G2 after today's changes:** `g2all` 0 policy CodeInstances lost after each of 12 loads, work 9–13 ms.
- **Acceptance after today's changes:** a run hung: compiling the trampolines' callees after the outermost inference had no bound, and a recursion with growing types (G1.12) compiled ever deeper signatures until codegen choked. Bounded (type depth, count; 1fdc36d). Then 15/16: **G2.1 fails because of session 26's rule of facts at non-public functions** (16/16 with `JULIA_TW_INTERNAL_FACTS=0`); recorded as evidence for open-issues §1.7, behaviour unchanged.
- **Stock Julia** (2e408cc): it cannot compile foreign code instances at run time; the trampoline then calls plain Julia's code of the same method. Stock suite 306/306.
- **Definition checking at a trait module's end** (fad5bd2): an error at a package's build, a warning at the prompt; methods the checker cannot build archetypes for are left to the first call. All five libraries build with it (10–15% longer). **`MethodError` hints** name the bound an argument fails.
- **Rows:** TDE 8 (a winning pirate followed: 373 ms recompile, 2,192 calls to it), 13 (images); TraitMakie 8 (errors at entry, conformance, definition), 10 (images); TraitReport 10 (10⁶ rows: 0.35 s against pandas' 0.23 s).
- **Baselines without traits:**
  - **PlainPlots** (TraitMakie/baselines): run time equal within 5% (row 9); first PNG 19 ms against PlainPlots' 21 ms without loads and 100 ms with them; a new type costs TraitMakie about 0.1–0.2 s more (the conformance's checks).
  - **PlainODE** (TraitDifferentialEquations/baselines, FunctionWrappers and untyped callbacks): matches the trait form on rows 2 and 5 in a fresh session, loads 0.17 s faster and takes a first callback in 5 against 17 ms; the trait form keeps its numbers in every load order (row 1 after loads 6.5 against 54 ms; a first callback after loads 29 against 144 ms). TDE's workload now writes the integrator's fields as callbacks do (a second callback 25 → 5.4 ms).
- **Row 5 of TraitMakie needs the trimmed build:** `verify_main` in a session does not scan workers behind the policy's `invoke` (open-issues §3/§4).

## Final state (end of session 27)

- **Repositories:** TraitWorld b627edc (+ later commits of this note's last items, if any); TraitTables, TraitCSV (new); TraitDifferentialEquations 40dc8dc; TraitMakie 98cb008; TraitReport b7eb88e; experiments 27e1120; julia-1.13 unchanged (db82407fa6).
- **Tests:** TraitWorld 350 patched, 306 stock; acceptance 15/16 (G2.1, the rule of session 26); `g2all` 0 lost; TDE 23, TraitMakie 10, TraitTables 14, TraitCSV 10.
- **Headline numbers** (patched; view caches off unless stated):
  - TraitReport form (t) 0.53–0.56 s, Python 0.59–0.60 s, its plain baseline 0.50–0.54 s; under loads no compiled code of the three libraries lost;
  - TDE row 1 6.4–8.0 ms in every order; row 5 30–55 ms, then 17–21 ms (SciML 2–2.7 s, 2.48 s);
  - TraitMakie first PNG 18–22 ms in every order; a new key after big loads 52–107 ms on the system image (6.4 s without).

## Next

1. **Decisions for the user:** open-issues §1.5–1.8 (the review: concreteness, stakeholders and Lemma O, facts at non-public functions with G2.1 as evidence, overrides after a conformance).
2. **The review's minor findings** (open-issues §5.5): document fixes.
3. **Binaries** (deferred by the user, session 25): TraitMakie row 5 and 7, TDE row 12, TraitReport form (c).
4. **Julia:** piece 11 after a decision on asserted effects; a hidden-frames registry (the clean form of the frame filter); the policy in Julia's Compiler (the system image's cleaner form).
5. **Interactivity costs found by the baselines:** a first callback's dynamic field accesses (12 ms over PlainODE); a new type's conformance checks (0.1–0.2 s over a plain method).
