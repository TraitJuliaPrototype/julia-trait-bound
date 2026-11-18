# Review: the architect's memo on a lean trait core that keeps the old APIs (W-60)

Reviewer: fresh eyes (Opus 5.5), files read only, no Julia run (2026-10-27).

**Under review:** `writeup/plans/2026-10-27-lean-core-old-apis.md` at d734721 (status: proposal, mine).

**Read against:**
- the references: `writeup/reference/traits.md`, `facts.md`, `compiler.md`, `lowering.md`;
- `writeup/design/evidence.md` §3; `experiments/ttfx/README.md` (E-168 to E-180) and its logs `logs/p2/*-imports.log`, `logs/p176/floor.log`, `logs/p179/`;
- `writeup/record/experiments.md` (E-180's row, committed at 91aa0d1, after the memo);
- the plans `2026-10-27-ttfx-sciml-makie.md`, `2026-10-27-session-cache.md`, `2026-10-27-port-architecture-ttfx.md`;
- `writeup/open-issues.md` items 72–75; `writeup/intro/porting.md` (0.3–0.5, B1, B5, B6); `writeup/explorations/load-on-demand.md`;
- the reviews `writeup/reviews/2026-10-27-*.md`, chiefly `w58-direction` and `cache-and-port-notes`;
- upstream sources in `ndport/pkgs/` (Makie 0.24.16, SciMLBase 3.58.0, OrdinaryDiffEq, DiffEqCallbacks), and `experiments/ttfx/env_up/Manifest.toml`.

Judged against the user's goal: SciML and Makie ports with a lean core of genuine trait code, open sets as traits; users keep upstream's call API; Makie's recipe authors keep theirs; SciML's problem and algorithm authors may migrate; a fast load and first use against Python (1.45 s) and stock (9.16 s); quick experiments; nothing proposed upstream; the cache across sessions as the lever.

## Verdict

- **The shape is sound and the memo is honest about cost.** Four layers, open sets as traits, old recipes as plain code above a protected core, a migration only where the user allowed one. It states that the load budget fails, and keeps packaging apart from what traits add.
- **Three load-bearing mechanisms do not work as written (B1–B3):**
  - code loaded at first use is invisible to the rest of the calling function (world age);
  - the compatibility layer is not plain where the core calls it (the mode rule);
  - "loading a group discards no core code" contradicts G2's stated exceptions and a measurement, with the memo's own example group.
- **Several costs are understated (M5–M8).** E-180, committed minutes after the memo, puts the cache's parts at 0.45 s at setting C's size, not 0.10–0.15 s. With the measured TraitWorld term and the omitted FileIO, the session is about 2.3–4.8 s, not 1.8–3.8 s.
- **The SciML migration is larger than claimed (M1–M3).** `init` for a problem type that implements the trait is refused by traits §5.5 and L-3. The algorithm family over existing methods keeps the throwing fallbacks. Callbacks read integrator fields the view does not declare.
- **The experiments:** X1, X2, X5 and X6 are quick, but X1 and X2 cannot deliver all they promise as built. X3 and X4 have no plain control. None tests B1–B3, and X7 can test all three in minutes (M9).

---

## Blocking

### B1. Code loaded at first use is invisible to the rest of the calling function

**The claim.** §1.4: "Loading on demand needs no new language feature." The stub loads the provider and calls it through `invokelatest`; "then one dynamic call per plot call". The same holds for the compatibility machinery "loaded at the first old-style plot" (§1.2), and for SciML's default algorithm and legacy front end "loaded at first use" (§1.3).

**Why it fails.**
- A call runs in the world in which it started. The stub's own `invokelatest` sees the new methods. The caller's frame does not: facts §2.1, "A task in an older world sees that world's methods and implementations."
- So in `function f(x); hist(x); save("h.png", current_figure()); end`, `save` runs in the world before the statistics group loaded:
  - the core's render walk reaches `Hist` through the table of the call's targets;
  - a miss "calls `Base._split_table_miss!(table, T)` in the caller's world" (compiler §4.3);
  - `emit!(::Hist)` does not exist there, so the walk raises `MethodError`.
- The same holds after `stairs!` loads the compatibility machinery, where the family's operations on `Plot{F, T}` are invisible. It holds after `solve(prob)` loads the default algorithm's package: `sol(t)` reaches the interpolant, a kept value whose methods live in that package.
- The workload's own plotting is a function (`plot_two`, `experiments/ttfx/plotting.jl`). It triggers no load at first use today. Any user script that does so inside a function does.
- Plain lazy loading has the same limit. `explorations/load-on-demand.md` §3 treats the world-age step as a matter of recompiling ("until recompiled"). It is a matter of the caller's world, whatever is compiled. Python has no world age, so "called like upstream" fails here and not in Python.

**Fix.**
- State the world-age constraint in §1.4, and choose one of these:
  - (a) every user-facing entry that can reach code loaded on demand calls into the core through `invokelatest`: render, `save`, `display`, `sol(t)`, the property sugar. This costs one dynamic call per entry, which is fine per plot call. It is not fine for `sol(t)` in a loop.
  - (b) an on-demand load below top level raises an error that names the `using`. This changes the API.
- Open an issue for the user: the user's constraint ("called like upstream") meets a Julia property.
- X7 must test a first `hist` and a `save` in one function (M9).

### B2. The compatibility layer is not plain where the core calls it

**The claim.**
- §1.1's table gives the compatibility layer the mode "plain".
- §2.2 says the costs are "today's", "compiled … plainly", and "None of it reaches the core".
- §2.3's table says "plain".
- §3.3 rejects the compatibility layer as trait code because its `Dict{Symbol, Any}` and `Any` values "would put it on the facts mode's interop tails".

**Why it fails.**
- The core's render walk calls `emit!`, `children` and `datalimits` on `Kept{Plot}` values. For an old-style plot these reach the family's operation methods, which "call the compatibility layer's own functions (`data_limits`, the children list)".
- Within the four candidates this is a direct call inferred from the facts owner. Beyond them it is `_SplitTargetFacts`, "compiled by facts whoever calls it" (compiler §4.3).
- By the mode rule a neutral method reached from the facts owner is compiled by facts (facts §6.2). Porting 0.5 says it outright: "Plain means: not in a trait module. A plain function that trait code calls is compiled by facts on that path."
- So the part of the compatibility machinery that the render walk reaches is compiled by facts in the session: data limits, children and upstream's bounding boxes over ComputePipeline graphs. The memo rejected exactly this. B5 measured this class of cost: NonlinearSolve reached from a trait module, 21.9 against 6.5 s.
- The bridge is right. A `Dynamic{Callable}` runs through a `:caller_world` pointer, and the callee runs its default owner's code, which is plain for a closure in a plain module (lowering §12). Kept-value operations are not called that way.
- The stub rule "stubs stay in plain code" (§1.4) holds only for stubs that plain code calls. A user's trait module that calls `hist`, or a stub inside the core (M7), compiles `Base.require` by facts.

**Fix.**
- §1.1, §2.2 and §2.3 say: facts where the core calls the layer, plain on the creation path.
- Then choose one of these:
  - (a) the family's operations hand over at once to `Dynamic{Callable}`s that the adapter holds, so the facts part stays a few lines and the compatibility code runs plain;
  - (b) accept facts copies, and give the compatibility package a workload that renders through the core, so its image holds them.
- Measure the first old-style render either way (M9).

### B3. "Loading a group discards no core code" contradicts G2's exceptions, and a measurement

**The claims.**
- §1.4, item 1: "Loading it discards no core code."
- §2.3: "The core is protected across every load in a session, including groups loaded at first use, old recipe packages and the compatibility machinery."
- §2.5, item 1: groups "load at any time and discard none of the core (E-177)".

**Why they fail.**
- facts §2.2 lists G2's exceptions "wherever G2 is claimed": a stakeholder's change, which includes a stakeholder's package extension and one activated by an unrelated package. The standard libraries count as Julia's own code.
- The memo's own example group is the measured counter-case:
  - the statistics recipes bring StatsBase and Distributions, and with them SparseArrays;
  - in TraitReport, trait code did 344–417 ms of work after StatsBase or Distributions loaded, and that work is "SparseArrays' `vcat`, a standard library's method" (evidence §3);
  - porting B1 item 11: SparseArrays' `vcat` "wins at `vcat(::Int64, ::Vector{Int64})` … so loading it recompiles the reader".
- E-179's lean Makie drops SparseArrays. So in M5 the core loads without it, and the first `hist` brings it.
- E-177 did not load groups, old recipe packages or a compatibility layer. It loaded DataFrames under `all`, where every package is compiled by facts, and OffsetArrays and StaticArrays on D. It does not support §2.5 item 1 as written.
- The implementation itself discards nothing (traits §4). The provider's dependency tree can.

**Fix.**
- Name the exceptions where the claim is made.
- Restate item 1 as a hypothesis: "discard none of the core except by stakeholders' changes, which include standard libraries' methods on Base's types and stakeholders' extensions the group activates".
- Test it in X7 with a provider that brings SparseArrays (M9).

---

## Major

### M1. SciML's `init` for a problem type that implements the trait is refused as described

- §1.3: "`init` is a typed method naming the solver's own algorithm type (B6)". Problem packages may "implement `ODEProblemTrait` for their own type".
- For such a problem, `init` needs a bounded problem argument. Traits §5.5: "a package may add [a bounded method] to a function it owns, or to another package's function where the package owns a trait the bound names." A solver package owns neither `init` (CommonSolve's) nor `ODEProblemTrait` (SciMLBase's).
- L-3 refuses the very case: "`__init(prob::ODEProblemTrait, alg::MyAlg)` from a solver package is refused beside the core's `__init(prob::ODEProblemTrait, alg)` (E-156 P14; W-36)".
- Porting B6, move 3, says it "Needs L-3 retired (PB-F)". The memo cites B6 but not this. It also loads `solve(prob)` without an algorithm on demand (§1.3), and that is PB-F itself.
- "The recommended architecture changes no reference" then holds only for the canonical `ODEProblem` path, where `init` is a plain method typed on concrete types.
- **Fix.** Choose `init`'s form before X4. The principled form within the references is an operation of `ODEAlgorithm` that builds the integrator, implemented by each algorithm package for its own types. B6 lists it ("`init` as an operation of the problem trait", or a family per problem). Say what it costs (a `Dynamic` result per solve, or a key per algorithm and problem). Put it in the migration's list.

### M2. The algorithm migration is larger than "one family declaration plus `SolverOptions`"

- **`isfsal` cannot be an operation of SciMLBase's trait.** It is OrdinaryDiffEqCore's own function (`lib/OrdinaryDiffEqCore/src/alg_utils.jl:80`). SciMLBase does not depend on OrdinaryDiffEqCore. `alg_order` and `isadaptive` are SciMLBase's (imported at `OrdinaryDiffEqCore.jl:26`, `:94`).
- **"Existing methods serve them" keeps the unchecked contract.**
  - OrdinaryDiffEqCore's `alg_order(alg::Union{OrdinaryDiffEqAlgorithm, DAEAlgorithm})` raises "Order is not defined" (`alg_utils.jl:663`). A family member without its own method conforms through it.
  - `isadaptive(alg) = false` at `Any` (`:312`) is a pirate by the letter once joint owners go (S2: "no pirates in the core").
  - The family therefore checks less than S2's "checked contracts" promises, until these fallbacks are removed. That is part of the migration.
- **`SolverOptions{T}` in place of `DEOptions`:**
  - 1,979 source lines in the 60 sublibraries of `OrdinaryDiffEq.jl/lib/` contain `opts.` (Tsit5 11, Rosenbrock 58, Core 137); 84 files read `integrator.opts.` or `opts.internalnorm`;
  - 73 lines in Rosenbrock and Differentiation read the Jacobian field or test for it (`f.jac`, `jac === nothing`, `has_jac`);
  - unless `SolverOptions` keeps `DEOptions`' field names, with its function fields (`internalnorm`, `isoutofdomain`) as `Callable` fields, the change reaches every solver.
- **Fix.** State the migration as a list:
  - the trait's owner and its operations' owners;
  - the fallbacks to remove;
  - `init`'s form (M1);
  - `SolverOptions`' field names.
- This answers the memo's own §6 question 4: not as small as claimed, but mechanical if the field names stay.

### M3. Callback authors do not keep their API with the view as declared

- §1.3: a callback "receives a `Dynamic{IntegratorView{U, T, P}}` and reads its declared fields". The fields listed are `u`, `t`, `p` and `dt`.
- DiffEqCallbacks (`ndport/pkgs/DiffEqCallbacks.jl/src`) also reads:
  - `integrator.sol` 20 times and `integrator.opts` 20 times;
  - `tprev` 8, `f` 5, `alg` 4, `uprev` 2, `iter` 1.
- Callbacks are "everything else", which the user wants unchanged.
- **Fix.** Either the view declares these fields (and `opts` changes type, M2), or callbacks receive the concrete integrator as today and keep their code. Say which, and what it costs in compilation per callback.

### M4. The compatibility layer: ownership, piracy, names, and per-member checks

- **Who owns `Plot{F, T}`.** §1.2 says "The names and types live in the umbrella: `Plot{F, T}` …". Two paragraphs later the family is "declared by the compatibility layer, which owns `Plot{F, T}`". If the umbrella owns the type and a separate, lazily loaded package declares the family, the declaration is refused (traits §10.1: the trait's owner or the type's owner).
- **The machinery's methods are pirates by the letter.** The machinery adds methods to the umbrella's empty generic functions for the umbrella's own types: the creation pipeline, the conversion cascade's generic `convert_arguments` methods, theming. Those are pirates by the letter. They contradict rule 2 (§1.1) and §1.4's "a provider adds no method to the umbrella's functions". Their load invalidates the umbrella's plain code. In strict mode's intended design, a pirate selected by facts code (B2) is refused.
  - The existing remedy: the umbrella declares the compatibility package a joint owner (traits §10.1, "for split packages"). A joint owner's changes are stakeholders' changes.
- **One name, two meanings.** `Plot` names both the core's trait and the old type, and both are visible after `using`. `Lines` and `Hist` likewise:
  - upstream's `stairs.jl` uses `documented_attributes(Lines)` and `shared_attributes(p, Lines)`;
  - `SciMLBaseMakieExt.jl:66` writes `Makie.plottype(sol::SciMLBase.AbstractTimeseriesSolution) = Makie.Lines`, and `:68` `Makie.used_attributes(::Type{<:Plot}, sol::…)`.
  - The memo makes `lines!` return a core `LinesPrim`. So `Lines` must stay the old type for dispatch, and must carry an attribute schema kept in step with the core's typed record. Porting B1 item 7 records the clash on `using`.
- **The family is checked per member at its first use** (traits §4.7). `Plot{F, T}`'s `T` is the argument types, so each new argument shape of each old recipe is a member check in each session, unless an image or the cache holds it. E-171 gives the scale: a new type's `@implement` takes 0.08 s. X3 should count them.
- **Old recipe packages with a workload record the machinery as an image dependency** (the previous review's M2: an image requires every module loaded while it was built). §2.2 says so, but not the consequence: any session that loads such a package (GraphMakie, AlgebraOfGraphics) loads the machinery at `using`. "Loaded at the first old-style plot" holds only for sessions without one.

### M5. The load estimate leaves out or understates five terms

| Term | The memo (s) | The record |
|---|---|---|
| TraitWorld and the trait packages' hooks | 0.10–0.30 | measured 0.25–0.29 (D against Dp after TraitWorld 04095fe, the README's E-172 section); C against S +0.33 (3.85 against 3.52 s, E-169 and E-176). The lower bound has no source. |
| the cache's parts | 0.10–0.15 | E-180 (TraitWorld `session-cache` 031932a, julia-1.13 6800be7839): D 5 parts, 0.15 s; **C 45 parts, 0.45 s**. "The parts' load is the next lever." The architecture multiplies dependency sets (core, umbrella, compatibility layer, groups, algorithm packages), so it multiplies parts. |
| FileIO and Pkg | absent | `save` stays FileIO's binding (§1.2), so FileIO loads at `using`, and FileIO binds Pkg: 7 + 132 ms (`logs/p2/S-imports.log`). Risk 7 names it; the table omits it. The floor's list (`probe_floor.jl`) has no FileIO. |
| the umbrella; extensions the workload's own loads trigger | absent | SciMLBaseMakieExt loads in the workload's environment (`logs/p179/L-1.log`). The umbrella's types, stubs and keyword front ends are not counted. |
| work after the load, with a cache | 0.4–1.1 | 0.4 is D's: a different, smaller workload (evidence §3). With the real mechanism at scale, C/pk takes about 1.5 s after its load (6.07–6.19 against 4.51–4.63 s, E-180). |

- With these terms, indicatively: load about 1.8–3.3 s, session about 2.3–4.8 s. The target of about 3 s is met only at the low end.
- "Facts images without edge validation under strict mode" (§2.1) needs strict mode on. Strict mode's intended design is deferred by the user (open issues §1, "Deferred", item 1). Say that this lever waits for it.
- **Fix:** recompute §2.1 and §0 with E-180, and pushback 4 with them.

### M6. "Makie's own code is the load" is not what E-179 shows

- §0 builds the main mechanism on it: "Makie's own code loads by use, not at `using`".
- The arithmetic:
  - the lean `using CairoMakie` takes 2.32 s (173 packages);
  - the plotting floor is 0.72 s (83 packages, `logs/p176/floor.log`), Makie's image 0.71 s and CairoMakie 0.18 s;
  - that leaves about 0.7 s in some 90 packages the lean fork kept, beside loader overhead. Among them: Pkg through FileIO 0.13 s, ImageCore 0.08, JSON 0.07 (`S-imports.log`).
- So Makie's own code is under half of the lean load. E-179's README draws the same conclusion ("Makie's own code is the load"), and so does evidence §3. Fix the copies.
- The architecture still needs a small `PlotCore`. But the gain from loading Makie's code by use is bounded by what remains of those 90 packages.
- **Fix.** First a zero-run attribution: the lean environment's package list less the floor's, summed from the existing logs. Then one `@time_imports using CairoMakie` session in `lean/env_lean`.

### M7. Extensions do not cover every key

- §1.4 says the key case is covered by extensions. The memo's §6 asks whether a case is missed.
- One is: a key whose package is light and already loaded, while its implementation needs a heavy package:
  - a `LaTeXString` label needs MathTeXEngine (risk 8: 0.21 s of the floor);
  - Makie re-exports `L"…"`, so LaTeXStrings is always loaded.
- An extension can depend only on its triggers and its parent's dependencies. A stub inside the core's text layout is facts code (B2).
- Either option (ii)'s registry (O2), or a stub reached through a `Dynamic{Callable}` that runs plain, covers it.
- Record the case in open issue 75.

### M8. Provider code "compiled into its own image" is overstated

- §1.2 (`Lollipop`) and §1.4 (`Hist`) say the provider's operations at its key are compiled into its image (traits §13).
- Traits §13 compiles ahead bounded functions with one trait position, at the new key (L-15 narrower still).
- The memo's render walk calls operations on `Kept{Plot}` through the table. Its targets and thunks are made at the type's first use in each session (compiler §4.3, C-14 Planned).
- The provider's own `emit!` (the binning, the primitives) is in its image only if a workload of the provider renders through the core.
- §1.4's cost line ("the provider's load …; then one dynamic call per plot call") omits that first-use compilation.
- **Fix.** Name the path (table or bounded function per plot). Give each group a workload that renders through the core. Say what the cache keeps: the targets at library keys are cacheable.

### M9. The experiments: controls, tools and coverage

- **No plain control where a trait-specific claim is tested.**
  - X3 ("nothing of the core recompiled after the late load") and X4 ("core CodeInstances lost (predicted 0)") test §2.5's items 1 and 4.
  - At small scale the plain twins also lose almost nothing: Dp/b "again" 0.02 s (E-168), 0.04 s after a late load (E-177).
  - Without PlainPlots and PlainODE built the same way, a zero decides nothing. The memo's §6 asks this; the answer is no for X3 and X4.
- **X1 cannot see "uses".**
  - `record_cis.jl` records CodeInstances created after the load mark. In S, Makie's image already holds much of the plot's path, so what the session creates is a skewed sample.
  - Counts by source file do not give "the compatibility machinery's share of Makie's image" in seconds.
  - Use path-limited coverage (`--code-coverage=@<Makie's src>`, one untimed session) for what runs, including MathTeXEngine. Use `@time_imports` for the load.
  - X1 is still minutes. It is not "no new code".
- **X2's second half needs the fork.**
  - OrdinaryDiffEqRosenbrock and OrdinaryDiffEqDifferentiation depend on LinearSolve (`env_up/Manifest.toml`). "LinearSolve kept out of the path" is the lean Rosenbrock fork, not a session.
  - The first half is in the existing log: Rosenbrock's own increment 58 ms, LinearSolve 41, PureKLU 61, LHLFactorization 22, IntelOpenMP_jll 46 (`S-imports.log`).
- **X5's recording session runs the same wrapper.** Its prediction is therefore close to true by construction. The informative result is the residual keys the wrapper cannot reach. Say so.
- **X7 should carry B1–B3.** It is the smallest build and already has a plain control. Four cases, minutes in all:
  - (i) the first `hist` and a `save` in one function (B1);
  - (ii) a provider that brings SparseArrays, with the core's facts CodeInstances lost counted (B3);
  - (iii) a plain-module family kept in the axis, with the CodeInstances of owner `:facts` in that module counted at the first render (B2);
  - (iv) the stub's cost per call.
- **X3 and X4 are builds of days, not experiments of minutes.** The memo's §5 says so; §0's "minutes to an hour" counts machine time only. Narrow X3 to the waist test over TraitMakie with PlainPlots as control. Leave the `Axis`, log ticks and grid slice for the port.

### M10. The SciML + Makie path the goal names runs through the old API

- `plot(sol)` goes through SciMLBaseMakieExt's `convert_arguments`, `used_attributes` and `plottype`. That is the compatibility layer, loaded at first use (B1, B2).
- §1.3 declares `Trajectory{U, T}` ("solutions as plotting sees them"), but no `PlotCore` trait in §1.2's table takes it.
- SciMLBase is on the side allowed to migrate. Its Makie recipe could implement the core's position traits for `Trajectory`, so the goal's own path stays in the trait world.
- Say which path `plot(sol)` takes, and list SciMLBase's Makie extension in the migration.

---

## Minor

- **m1. "Typed stub" is a misnomer.** The stub takes `args...; kw...` and calls `invokelatest`; nothing is typed at the call. Call it a loading stub, or say what is typed (the provider's implementation behind it).
- **m2. "Each rests on a reference; none is new" (§1.1, the waist):**
  - rule 5 rests on the plan's class (f), not a reference;
  - rule 1's "the core never names a provider's types" is a new convention;
  - rule 2 cites porting A4, which is about extensions only.
  - Say "conventions over the references".
- **m3. `pos::Dynamic{Positions{2}}` (§1.2) is refused** if any of `Positions{N, T}`'s results names `T` (traits §5.1). Write `Dynamic{Positions{2, Float64}}`, which the entry's normalization gives anyway. Code at a `Dynamic` position is compiled once, not "once per position family"; its loops run `compiled_for` the data.
- **m4. `log10` "becomes a `Kept{Transform}` by `convert(Transform, log10)`":** §1.2's table has the core implement `Transform` for `typeof(log10)`. A conforming value is not converted (traits §7.3).
- **m5. The `Lollipop` sketch has no `emit!`.** Say whether `Plot`'s `emit!` has a default; an operation without one is an error at `@implement` (traits §4.1).
- **m6. §2.3 uses E-177 out of its setting.** The 0.02 s against 6.1 s compares Makie wholly by facts (`all`) with Makie plain. The memo's layering keeps the umbrella and the creation path plain, and its exposure there is unmeasured. Say so where E-177 is quoted.
- **m7. Numbers without builds** (CLAUDE.md rule 5):
  - §2.1's table and §2.6 quote numbers without the build or setting; the memo says the evidence is their home;
  - "9–18 ns" should cite the evidence (E-145), not `other-languages.md`.
- **m8. E-180 is not cited.** §1.5 and §2.5 item 2 call order independence "the design's claim". E-180 now shows it on D (order B with a cache recorded in order A, 1.05–1.11 s; a late load, 1.16–1.19 s) and gives the parts' load (M5).
- **m9. X4 "digests equal to TDE's".** Compare with upstream's digests, within the plan's tolerance (§2): TDE runs Rodas5, the workload Rodas5P.
- **m10. "Builds on, and replaces where they disagree":** when the memo is adopted, the port note's §4–§5 and the load-on-demand exploration need status lines that say so (CLAUDE.md, plans).
- **m11. A stale copy outside the memo.** Open issue 75 in `writeup/open-issues.md` (line 9) begins with a broken fragment, `("+R.replace("../","")+" 2; W-58)`. Fix it with the memo's adoption, since the memo answers that issue.

---

## What the memo gets right

- The four layers, and the five conventions that keep the core narrow, follow porting 0.3–0.5 and A7.
- Old recipes run as upstream's code above the core, rather than being translated (M4, rejected for the right reason: `plot!` bodies are arbitrary code).
- The bridge as a `Dynamic{Callable}` holds no edge into the compatibility layer and runs plain (lowering §12).
- It separates keys (extensions) from functions (stubs). That is a useful split of open issue 75, and extensions are right for most keys.
- It uses the user's permission narrowly: problem and algorithm authors migrate; users, recipe authors and callback authors are meant to keep their APIs.
- It is honest about the load: the budget of 1.2 s fails at every point, pushback 4 says so, and open issue 73's levers stay needed.
- §2.5 keeps packaging and trait-specific claims apart, and keeps the direction review's caution.
- Every experiment states what would change the architecture. X7 has a plain control. X5 and X6 each isolate one key.
- All 41 links and anchors resolve.

## Recommendation: what to run first

1. **Zero-run analyses** (no Julia, minutes):
   - X2's first half from `logs/p2/S-imports.log`;
   - E-179's attribution (M6): the lean environment's packages less the floor's, summed from the existing logs.
   - Then one `@time_imports using CairoMakie` in `lean/env_lean` (seconds).
2. **X7, extended as in M9** (TraitMakie and PlainPlots, a provider package, minutes). It is the one experiment that tests B1, B2 and B3, the mechanisms the architecture rests on, with a plain control. A registry row first.
3. **X1 by coverage** (one untimed session) and **X6** (minutes, existing tooling). X5 after them, framed as in M9.
4. **On paper before X4:** `init`'s form (M1), the integrator view's fields (M3), `SolverOptions`' field names (M2). Then X4 with PlainODE as control.
5. **X3 narrowed** to the waist test with PlainPlots as control, after X7 and X1. The `Axis`, log ticks and grid slice belongs to the port.
6. **Recompute §2.1** with E-180 and the terms of M5 before the wrap-up (W-61) quotes a session range.
