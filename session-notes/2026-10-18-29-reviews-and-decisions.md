# Session 29: three reviews after the pivot, and the user's decisions

The user (start of session 29): "The previous session ran out of usage in the middle of building the Demonstrators. Before we resume I want a few Fable reviews for what we have been doing." Three Fable 5.1 reviews:
1. the current design and the fixes since the last reviews;
2. the overall framing and motivation, with the user's proposed reframing around two goals (composable caching and AOT as "compiled code is never invalidated unless the code changes", piracy defined by ownership and stakeholders; and "we can't express what our code actually needs");
3. the shape of the implementation and the demonstrators: "whether this is truly fit for purpose or contains path dependencies that we should break out of … I think we were trying too much to keep things as a package originally. Now that we are modifying the Julia compiler internally, we should revisit and critically appraise prior implementation decisions."

**State at the start:** design repository 0683e27; TraitWorld 47e4274; experiments cac8e72; forks 06e8b97; julia-1.13 db82407fa6 with uncommitted work in `Compiler/src/` (`facts.jl` and hooks in `Compiler.jl`, `abstractinterpretation.jl`, `tfuncs.jl`: the in-tree port of (A), begun); `experiments/factscompiler/results/full1c/` untracked (a second BaseBenchmarks run, partial).

## Session 28, reconstructed (it ran out of usage and left no note)

From the commits of 2026-10-17 18:00 to 2026-10-18 10:22 and the documents they touched:
- **The DataFrames/CSV port** (`forks/`, demonstrator 4, plan `writeup/plans/2026-10-17-dataframes-traits-plan.md`): M0–M4 and M5 in progress (06e8b97): `Tables.ColumnCore`, `DataFrame` storage `Vector{Dynamic{Column}}`, `ColumnKernels` workers, the CSV read path as a worker (`CSVSource`). The session over the forks: 1.19 s excluding imports (upstream 10.9 s, pandas 0.32 s). Lessons: `writeup/explorations/dataframes-port-lessons.md`.
- **TraitWorld rule changes for the port:** facts fold where Base's asserted effects fold (c62e23e); run-time sites in policy code run the policy's code (1d93677, with per-site caches 5b50482, 9ddd4a0); facts at tuples with unions of concrete elements (5b50482).
- **The pivot** (`writeup/plans/2026-10-17-policy-in-compiler-plan.md`, the user's direction): the facts policy as a mode of Julia's own compiler, (A) a mode of inference, (B) a second cache owner, (C) owner-aware dynamic dispatch; a switch `--compile-by-facts=no|all`; (A) measured before committing to (B).
- **(A) as a forked Compiler package** (`experiments/factscompiler`, 76c4deb). BaseBenchmarks in facts mode against off: geometric mean 1.016 overall, 1.064 without `scalar`; `io` 1.32; tails on containers of `Any`, abstract element types, small-union broadcasts (4305a07). `return_type` step 2 (6792e79): the union broadcast 229× → 1.09×. Recovery: raytrace and `parse_json` (76e82f5).
- **Sealing dropped** (open-issues §2.26, the user): a closed contract is a trait, not a sealed abstract type.
- **Witness tables for `Dynamic`** (TraitWorld 30527ed, 66253db) and **key branches at `Dynamic` call sites** (d3bb298); raytrace with an open set of primitives (experiments 2bf47f8). A fix of `return_type` folding (`cached_return_type`, 47e4274).

## The reviews

All three in `writeup/reviews/`:
- **`2026-10-18-design-and-fixes.md`:** session 27's four fixes hold in text and prototype; acceptance 16/16 re-run on 47e4274. Session 28's pivot changed the architecture without the notes or the register. Ranked:
  1. the global facts mode changes values (`map(f2, Real[])` is `Vector{Any}`, plain `Vector{Float64}`), and the go/no-go benchmark ran in it; Base's tests in facts mode were never run;
  2. **witness tables violate world age** (verified: 500.0 where plain gives 5.0 in an older world; a `@cfunction` entry runs in the latest world);
  3. strict mode and the machinery's exemption are undefined under one owner; the in-tree draft exempts TraitWorld by module name (sealing by another name);
  4. key branches make speed depend on load order (the `max_methods` cliff in new clothes);
  5. rule changes 1.1, 1.2, 1.8 of the lessons are in the prototype, not in the notes;
  6. no session-28 entries in the register; rows contradict the plan;
  7. the in-tree `facts.jl` calls `jl_compile_by_facts`, which does not exist.
- **`2026-10-18-framing-and-motivation.md`:** "piracy is the principal way code is invalidated" is false for stock Julia (four non-pirate invalidations verified); in facts mode only stakeholders, winning pirates and redefinitions invalidate. So rule R (facts only) is the hidden premise and must be stated with its cost. Goal 2 is right; "works with any type without recompilation" overclaims (keys compile per key). **Revision 2 (§5), on the user's comment "work the argument from strict mode first; the fact that it will not be the default comes later":** the guarantee first, then three forced steps (rule R; Lemma O; refusal of winning pirates), the residual named (stakeholder edits, extensions, bindings, image pirates), rule P as the relaxation and what it gives up, the commitments (pieces 1′, 14, 15, `twolibs`, the extension rule, bindings), a revised outline and a draft overview, the sections to change (§5.7).
- **`2026-10-18-implementation-shape.md`:** TraitWorld 8,707 lines: ≈5,500 design-needed and sound, ≈770 imitate the compiler, ≈2,200 work around being a package, ≈250 leftovers. The largest path dependency is the foreign cache owner (≈1,300 lines plus the system image and pieces 5, 9, 10, 12). The policy's protection is trait-independent, so under `all` the plain baselines get it too: the decisive control is missing. `Dynamic` belongs in the compiler. The forks validate a function barrier more than a trait (kernels use `vector(c)`, not the declared operations; CSV's trait is `CSVSource`, not `CSVColumn{T}`). Target architecture and migration order in its last sections.

## Decisions (the user, session 29)

Recorded in `writeup/decisions.md` ("Session 29") and `writeup/open-issues.md` §1:
1. **Strict mode first, for the framing:** yes. The design is argued from the guarantee "compiled code is never invalidated unless code it depends on changes", with refusal of winning pirates as the base; that strict mode is not the default comes later, as a relaxation.
2. **`--compile-by-facts=all` is a test bed,** not a user setting (plan P-c).
3. **Drop stock-Julia support** (plan P-b): TraitWorld requires the patched build.
4. **`Dynamic` moves to the compiler directly;** no further package work on witness tables or key branches.
5. **Pause the forks** (demonstrator 4) for now, at M5 in progress.
6. **Overarching principle:** "tolerate slow downs if they can be recovered by redesigning code through traits."

**Second message** (after the fourth review, `writeup/reviews/2026-10-18-decisions-revisited.md`): "Witness table: Yes. On 2. We need compiled call to have an ODE RHS that has the right type signature. Julia's type system can't express that otherwise. Everything else looks good. Make a consolidated design and decision document on the current state of affairs. Press on towards actually building the compiler we need in the order proposed above." Witness tables off by default (TraitWorld); the review's changes 1 and 3–10 adopted, change 2 rejected (`Callable` keeps both modes); the consolidated document is `writeup/design.md`, the register marks retired rows as history and gains "Session 29, continued"; open-issues §1.9 and §1.12 closed, §1.11 half closed, §2.26's first bullet answered, §1.15–1.17 added.

**The user's third message (framing):** "The framing should start with what is already true today: Fully typed code gets invalidated by stakeholders and pirates. Outlaw pirates and it is always valid and can be cached. Adopt the facts rule, and you can extend this guarantee to all code, but at a significant performance cost. Adopt traits to express what exactly code needs makes it cheap and can (optionally) enforce concreteness, so that type stable code is always fully typed." Checked, with five refinements (fully typed is transitive and excludes kinds; the exceptions of "always valid"; strict mode alone suffices for fully typed code; the cost sits exactly where code is not fully typed; traits recover it by concrete keys, declared result types, declared conformances). `design.md` §2–3 rewritten on this spine, a draft for the user's review.

## Final state (end of session 29)

- Repositories as at the start; the three reviews, this note and the register, open-issues, plan and writeup index updates committed in the design repository.
- The in-tree port in `julia-1.13/Compiler/src/` is still uncommitted and does not load (review 1, finding 7).

## Next

To confirm with the user; the order follows the implementation review's migration order, with the decisions above applied:
1. **(A) in-tree, one source of truth for the fact rules:** finish `julia-1.13/Compiler/src/facts.jl` (the flag in `jl_options`), build, retire the two other copies; run Base's tests in facts mode (plan §2.4, never run).
2. **The decisive control:** the plain baselines (PlainODE, PlainPlots, PlainTables) and upstream DataFrames under `all`, lost CodeInstances and first-call times, against the trait forms.
3. **(B) and (C) in Julia:** a second owner for trait-bound code and owner-aware dynamic dispatch; then delete TraitWorld's imitation (`FactsInterp`, site caches, trampolines, view caches, the system image) and the stock-Julia paths.
4. **`Dynamic` in the compiler:** the call-site split in the inliner, with world-age-correct dispatch.
5. **The notes rewritten strict-first** (framing review §5.5–5.7); the session-28 rule changes (1.1, 1.2, 1.8) written into the notes or reverted; the register's contradictions fixed.
6. Then resume the forks (with `CSVColumn{T}`, kernels on declared operations, the upstream-under-`all` control).

**The user (later in session 29):** the four-step framing, "fully typed" as the name and the fully-typed certificate: "1-3 is a yes". "After the full traits+facts compiler is built, have Fable review the implementation." Order of work from here: (B)+(C) built and tested; `Dynamic` in the compiler (D); TraitWorld's imitation and stock paths deleted; the fully-typed certificate; then a Fable review of the implementation.

**Later in session 29 (the build):**
- (A) in Julia: `880ae49dad`. The facts system image: `experiments/factscompiler/scripts/build_facts_sysimage.sh` (193 MB against 205 MB plain).
- Julia's own tests in facts mode (plan §2.4, first run; `JULIA_CPU_THREADS=3`, 90 min limit): strings tests fail only on inference-precision checks at abstract signatures (`return_types(write, (IO, AbstractString))`, `infer_return_type(prevind, Tuple{AbstractString, Vararg})`, `is_foldable` of a `lazy"…"` throw), as expected; `core` did not finish: issue #10981's `vcat(x...)` with 2·10^6 splatted arguments, a run-time site at a `Vararg` tuple dispatched over all arguments again and again. Decision: concrete `Vararg` tails are facts (decisions.md). The other test files did not run; to run again on the next build.
- (B)+(C) built (uncommitted until tested): the module option `@compiler_options facts=true`; owner `:facts`; `jl_default_owner`; owner-aware `jl_compile_method_internal`, `jl_type_infer`; `jl_apply_generic_facts`, `jl_invoke_facts` emitted in facts code; facts CodeInstances through the compile queues and into package images. Small case (`/tmp/claude-1000/factsB/b.jl`): a facts module's methods have only `:facts` code; a plain caller keeps native code; a run-time site in facts code runs `Lib.foo` under `:facts`; a non-pirate method leaves the facts code valid.
- TraitWorld's tests under (B) (TraitWorld's own policy off): 14 sets pass, `M7: verify_main` fails: entries compiled by facts at `@nospecialize` signatures. Fix: boundaries (decisions.md), in the next build, with `Vararg` facts and plain inference of facts methods routed to facts (reflection).
- The four porting agents were cut off by a usage limit before they had changed anything, and resumed; they run with `JULIA_TW_COMPILER_FACTS=0` until (B) is validated. The control experiment was cancelled (measurements wait for (D)).

