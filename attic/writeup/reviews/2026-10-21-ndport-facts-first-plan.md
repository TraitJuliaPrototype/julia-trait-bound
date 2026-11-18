# Review: the NetworkDynamics port, P3 (the facts mode first)

**Reviewed:** [`../plans/2026-10-21-ndport-facts-first.md`](../plans/2026-10-21-ndport-facts-first.md) (status: proposal), part P3 of [the meta plan](../plans/2026-10-21-networkdynamics-port.md), work item W-32, as committed in 03ec787. Read against:
- CLAUDE.md;
- the P1 plan [`../plans/2026-10-21-ndport-workload.md`](../plans/2026-10-21-ndport-workload.md) and E-151's logs (`ndport/logs/p1/`), done since the P3 plan was written;
- the P2/P4 plan draft `../plans/2026-10-21-ndport-traits.md`, which builds on P3's setting N;
- [facts](../reference/facts.md) §2, §5–§7, §10–§13 and its Deviations; [traits](../reference/traits.md) §2, §9, §10; [lowering](../reference/lowering.md) §2;
- [porting guideline](../intro/porting.md) §0.1, §0.1a, §0.7; [evidence](../design/evidence.md) §1, §3;
- TraitWorld e9f4bfe: `src/trait_module.jl`, `ownership.jl`, `strict.jl`, `defcheck.jl`;
- the clones in `ndport/pkgs/`, `ndport/scripts/` and `env_port/`.

**Reviewer:** Opus 5.5, 2026-10-21. Nothing was run in Julia. "Verified" means read in the code, a manifest or a log. Package counts were checked with a short Python script over `env_port/Manifest.toml`.

**Severity.**
- **Blocker:** a run would not measure what the plan says, or would corrupt another setting's runs.
- **Should fix:** fix before the first P3 run.
- **Minor:** housekeeping, or a cheap improvement.

## Verdict

- The plan's reading of the references is mostly right and well cited:
  - what each setting promises;
  - what the product setting does not cover;
  - the role of extensions, the standard libraries and `return_type`;
  - why N leaves the solver's driver plain.
- **The three-line wrap of NetworkDynamics is realistic** (question 1, below). The pirates it lists in DiffEqBase and OrdinaryDiffEqCore are real. NetworkDynamics' source shows none.
- **Two blockers:**
  - **Finding 1:** setting N shares the working tree and the environment of P0, A0 and W.
  - **Finding 2:** the strict-mode check has no control. A refusal in N may come from Base's plain code, which strict mode also protects.
- **The plan predates E-151's outcome** (finding 3). E-151 already answers the cost of `all` and the Makie question. About a third of the runs can go.
- **Cost** (finding 4): about 18 sessions as planned. About 11 give the same answers.
- **The ownership gap** of the wrap is real and not in any Deviations table (finding 7).

## Answers to the five questions

**1. The claims, and the wrap.**
- **Correct, verified against the references:**
  - G1 and G2 as stated per setting, and the table of §1.3;
  - G2's exceptions this stack can meet;
  - the mode rule for W and N;
  - `jl_apply` entry points running plain code in the product setting;
  - F-2 and F-7 under `all`;
  - images under keep-compiled (lowering §2).
- Two claims go beyond the references: finding 9 (last-bit differences) and finding 12 (G2 under `all` as holding).
- **What `@trait_module begin … end` does to a package** (`trait_module.jl:52–146`):
  - It prepends the prologue: the module option `facts=true` and the registries.
  - It wraps every top-level statement in `@stmt`.
  - `include(path)` becomes `include(TraitWorld._transform_file, path)`.
  - A `struct` is rewritten through `_dynamic_fields` and `_bounded_struct`. Without trait names it is unchanged.
  - A plain function definition is passed through `_rewrite_fdef`. For a plain definition this adds `_check_methods` (ownership, rule 3) and `_check_entries_intact`.
  - Everything else passes unchanged: `using`, `const`, `export`, macro calls, `for`, `if`.
  - At the end, `_finish_module` runs `_refuse_overrides()`, `_warn_hidden_attributes` and `check_definitions`. At a package build, `check_definitions` is an error. It finds nothing without bounded methods.
- **It refuses:**
  - a pirate among the definitions it checks (`OwnershipError`);
  - an ordinary method replacing an entry;
  - the errors of T-34;
  - an override after an implementation.
- **The three-line wrap of NetworkDynamics** (`using TraitWorld`, `@trait_module begin`, `end`, plus TraitWorld in `[deps]`) is realistic:
  - the 26 top-level `include`s are transformed;
  - `@static if`, `@compile_workload`, `@kernel`, `@generated` and `@kwdef` pass through;
  - so do `RuntimeGeneratedFunctions.init(@__MODULE__)` and the two `@eval` loops in `metadata.jl`.
  - `@compile_workload`'s `include("precompile_workload.jl")` is not transformed. That file defines two functions of NetworkDynamics' own.
  - There are no submodules.
  - TraitWorld's exported names appear in NetworkDynamics only in docstrings, so `using TraitWorld` clashes with nothing today.
- **The unknown is scale, not syntax.** The largest code wrapped so far is TraitMakie's 791 lines. The forks wrap small submodules (layout B). NetworkDynamics has 15,136 lines.
  - Every plain definition pays `_dynamic_containers` (a walk of the body) and a `_tryeval` per annotation.
  - Each `Base.*` definition iterates every method of that function (`_check_methods`). NetworkDynamics has about 200 such definitions.
  - Expect ND's precompilation above the 12–22 s of §5.9, and record it.
- **Pirates, verified in the source:**
  - **DiffEqBase:**
    - `Base.isempty(::CallbackSet)` (`DiffEqBase/src/callbacks.jl:81`; `CallbackSet` is `SciMLBase.jl/src/callbacks.jl:488`);
    - `SciMLBase.isfunctionwrapper(::FunctionWrapper)` (`DiffEqBase.jl:116`);
    - `__solve` and `__init` on `AbstractDEProblem` (`solve.jl:1320`, `:1336`; imported from SciMLBase at `DiffEqBase.jl:97`).
    - Also, not listed: `Base.isempty(::AbstractContinuousCallback)` and `(::AbstractDiscreteCallback)` (`callbacks.jl:84–85`); `solve` and `init` on `AbstractDEProblem` (`solve.jl:150`, `:653`).
  - **OrdinaryDiffEqCore:** `SciMLBase.interp_summary(::Type{cacheType}, ::Bool) where {cacheType}` (`interp_func.jl:73`): every type in it is Core's.
  - **NetworkDynamics: none found.**
    - Every method of a foreign function names one of ND's types: `Base.*`, `SII.*`, `SciMLBase.*`, `Graphs.*`, `ConstructionBase.*`.
    - The unions are all ND's own (`Union{NWParameter, NWState}`, `symbolicindexing.jl:712`).
    - The functors are on ND's types.
    - The `@eval` loops define ND's own functions.
    - The census will confirm it.

**2. Do the checks show what they claim?** See findings 2 (strict mode: no control), 5 (load order: unlike sets, an incomplete classification) and 3 (the cost of `all`: already answered).
- Lost CodeInstances, counted as in `g2all.jl`, are the right measure for G2: valid CIs of the facts owner whose `max_world` closes at a load.
- They are not the right measure of the benefit. Two sets of different code are compared, and a single lost root can cost seconds.
- The user-facing number is the "after" pass's recompile time, by module. The plan prints it. It should be the headline (finding 5).

**3. Cost.** About 18 sessions: 17 required plus the U run that checks the split, a build, and up to 6 optional sessions and 2 more builds.
- Each session is a quick test, but together they are not proportionate. E-151 already answers three of P3's questions, and the order-B runs already contain the P1-order data.
- Finding 4 gives a run list of about 11 sessions that keeps every answer.

**4. The ownership gap.** Real and slightly larger than stated, with one partial cover. No reference covers it. Finding 7.

**5. Gaps and conflicts.**
- With the P1 plan and the P4 draft: the shared working tree (finding 1).
- With CLAUDE.md:
  - a deviation left unrecorded (finding 7);
  - a G1 interpretation not in the reference (finding 9, precedence rule 3);
  - more runs than the question needs (finding 4).
- With the harness: findings 2 and 8.

---

## Findings

### 1. (blocker) Setting N shares one working tree and one environment with P0, A0 and W

**Evidence (verified).**
- `env_port/Project.toml` tracks NetworkDynamics by path: `NetworkDynamics = {path = "../pkgs/NetworkDynamics.jl"}`.
- P0, A0 and W all use `env_port` (plan §4; `run_workload.sh`).
- `p3_wrap_nd.sh` creates `p3-wrap` in that working tree and resolves `env_port` again (§3). From then on, every setting loads whichever branch is checked out.
- Runs 3–5 interleave N with A0, W and P0. Each switch changes ND's source for the others.
- The log header records the clone's commit, plus `*` only for uncommitted changes (`run_workload.sh`). A P0 run with ND at `p3-wrap` would look valid.
- The re-resolve writes TraitWorld into NetworkDynamics' dependencies in the shared manifest, which P0 and A0 also use.
- The P4 draft (`2026-10-21-ndport-traits.md` §2.2) commits on `trait-port` in the same tree. It uses P0 "at `upstream`" and N "from E-153".
- `check_env.py` checks versions and tree hashes, not dependency lists. For a changed clone it prints "CHANGED against upstream" and does not fail. §1.4 item 2's "allows that one new dependency" describes nothing it does.

**Fix.**
- Give N its own working tree: `git -C pkgs/NetworkDynamics.jl worktree add ../NetworkDynamics-p3wrap p3-wrap`.
- Give N its own environment, `ndport/env_p3/`: `env_port`'s project, with NetworkDynamics' `[sources]` path pointing at the worktree. Resolve it offline.
- `env_port` stays at `upstream`. Make `check_env.py` fail when a clone used by `env_port` differs from `upstream`, and run it before every P0, A0 and W run.
- In `run_workload.sh`, N (and NA, if kept) uses `env_p3`. The header names the environment and ND's branch.
- Add `depot-p3/` to `ndport/.gitignore`.
- The P4 draft needs the same rule: a worktree per variant.

### 2. (blocker) The strict-mode check has no control, and a refusal in N need not come from NetworkDynamics' code

**Evidence (verified).**
- Strict mode protects every CI of the facts owner. It also protects plain CIs whose method is in Base, Core, a standard library, TraitWorld or a trait module (`_trait_world_code`, `strict.jl`; facts §10.2, "Note: it also protects other code").
- Rodas5P's Jacobian runs Base code on duals: broadcasting, reductions, LinearAlgebra's generic paths. These calls come from OrdinaryDiffEq's and ForwardDiff's plain code, so they are plain CIs of Base methods with facts at `+(::Dual, ::Dual)`.
- So in N the pirate may well be refused because it wins in Base's plain code. It would then be refused in P0 too, without any trait module. The table's N-on row would hold for the wrong reason.
- The error names the call signature only (T-21). From the text alone one cannot tell which code was protected.
- The A0-on row tests behaviour the reference describes only as the note's side effect. Under `all`, NetworkDynamics' code is owner `nothing` and is not protected, while Base's is. Whatever the result, it says nothing about the stack.
- The harness cannot run strict mode as written. `run_workload.sh` unsets `JULIA_TW_STRICT` and writes `strict=off` into every header literally.

**Fix.**
- Add **P0 with strict mode on** as the control. Expected: refused if the pirate wins in a Base CI at duals. That is the note's behaviour, not trait code's protection.
- In every refusal, print `e.caller`:
  - its owner;
  - its method and module;
  - `TraitWorld._trait_root(e.caller)`.
- For N, the claim holds only if a refusal names a CI of the facts owner whose method is ND's, or the user's `swing!`/`line!` compiled under it.
- If P0 also refuses, measure the N claim differently: strict off, compare which CIs of the facts owner are lost (N off already gives this). Then state that strict mode's refusal in this stack is decided by Base's code.
- Drop A0-on. Make W-on optional.
- Turn strict mode on in the script with `TraitWorld.strict!(true)` just before the pirate (finding 8). Record it in the header.

### 3. (should fix) E-151 already answers §2.3, §2.4's question about `all`, and §2.5's Makie question

**Evidence (verified, `ndport/logs/p1/`; evidence §3, the NetworkDynamics row).**
- Steady state ("again"), A0 against U:
  - d 15.3 ms against 19.6–19.8 ms;
  - e 0.5 ms against 0.3 ms;
  - f 83 ms against 35–38 ms;
  - g 197 ms against 156–158 ms.
- First pass 34.5 s against 39.7–40.4 s. Loads 11.9 s against 5.4–5.6 s.
- All 25 digests are bit-equal.
- "Changed" under `all` is 15.1 s against 15.9–16.3 s.
- E-151's attribution shows that Makie compiles almost nothing in "changed". The plotting steps' 0.6 s is NetworkDynamics' and SymbolicIndexingInterface's code reading the state.
- So E-153's criterion "steps d or e under `all` taking more than twice U's steady state" is already decided: no.
- §2.5's second question is already answered. Its first ("does the facts mode compile less for a new `Network` type") is answered at the level P3 needs: about 0.8 s less.
- §2.4 still cites the precompilation logs' single `using` times instead of E-151.

**Fix.**
- Cite E-151 in §1.2, §2.3–§2.5 and §0.
- Drop run 3's second A0 run and run 6, the attribution in A0.
- Remove the `all` parts from E-153's question (3) and its "would change" list.
- Keep the dispatch profiler in A0 as the optional P4 input it is.

### 4. (should fix) The runs: about 11 sessions give every answer the plan's 18 give

**Evidence.**
- `p3_loads.jl` runs, per setting:
  - steps a–e twice;
  - the plotting load;
  - a–e "after";
  - f and g for the first time;
  - with timing and digests.
- So one order-B session already gives that setting's first pass, steady state, protection and result equality. Run 3's W and N sessions repeat most of it.
- Run 7 (strict mode across the plotting load in W) repeats evidence §1's scan of 837 pirates by the letter, on a different stack.
- Stage C needs a new environment and a resolve, and answers no question of P3's.
- NA is optional and tests strict mode under `all`, which finding 2 drops.

**Fix: a run list** (all on the same builds, one job at a time):

| # | Run | Sessions |
|---|---|---|
| 0 | the U run that checks the split of `workload_steps.jl` against E-151's digests | 1 |
| 1 | census in P0 | 1 |
| 2 | wrap and build N (finding 1) | 1 build |
| 3 | order B in **P0 first**; then in N, A0 (E-29's result) and W | 4 |
| 4 | N in P1's order (E-152's "before" for the P4 draft) | 1 (2 if P4 needs n = 2) |
| 5 | pirate: N strict off, N strict on, P0 strict on (finding 2) | 3 |
| — | optional: dispatch profiler in A0; W strict pirate; the attribution in N | ≤ 3 |

- **A gate after P0's order-B run.** If P0 loses almost none of the stack's code (say under 100 CIs, and under 0.5 s of recompile in "after"), then the plotting load is no stimulus for this stack. A0, N and W can then only confirm G2 (zero loss), not show a benefit. Say so in E-153's outcome. Then run W's order B only if W's first pass is needed for the guideline.
- If one W session exceeds five minutes, it runs once. That is the plan's own rule, and it is now W's only session.

### 5. (should fix) Load-order protection: compare like with like, and classify losses by facts §2.2's list

**Evidence.**
- **P0 and N count different sets of code.** P0 counts plain CIs of every stack module. N counts CIs of the facts owner, which are NetworkDynamics' methods, the user's functions and everything ND's code reaches (NonlinearSolve, SymbolicIndexingInterface and Base on ND's paths).
- A lower count in N is therefore not by itself a benefit. In N, the plain integrator is lost and recompiled exactly as in P0 (§1.5's "What N does not give").
- **The classification is incomplete.** §2.1 traces each loss to the defining method and `owned_method`, and calls an owned definer "a stakeholder's change". By Lemma O this holds for a fact broken directly. G2 also loses facts CIs by other routes (facts §2.2: "by the invalidation of a CodeInstance of the other mode that it names"):
  - through a folded `return_type` answer: facts §7.1 rule 2, an edge to plain inference's result under its own owner;
  - through the compiler's plain code: facts §6.4, open issues §2 item 27;
  - through a binding redefined from another module.
- Such a tree can start at a non-pirate method of an unrelated package, such as Unitful's `Colon(::Any, ::Any, ::Quantity)` (evidence §1). It would then be counted as "a stakeholder's change" although its route is the `return_type` scope exclusion.
- Julia's invalidation log lists MethodInstances, not CodeInstances. Strict mode's safety net maps them to CIs by walking `mi.cache` and testing the owner (`_strict_after!`, `strict.jl`). The plan does not say how `p3_loads.jl` does it.

**Fix.**
- **The headline per setting:** the "after" pass's compile and recompile ms against "again", by module (the attribution instrument's columns). Give lost counts restricted to the same code in every setting: CIs of NetworkDynamics' methods and of the workload's functions, plain in P0 and of the facts owner in N and W. Report the full counts beside them.
- **Classify each lost CI of the facts owner by route:**
  - (a) a fact broken directly, whose definer is owned (a stakeholder's change, with the extension column) or not (a pirate);
  - (b) through a CI of another owner (the `return_type` owner, or plain compiler code);
  - (c) a binding.
- A loss is "unexplained" only outside (a)–(c). Map each class to facts §2.2's list in the outcome.
- Map log entries to CIs as `_strict_after!` does. Do this before trusting a zero.

### 6. (should fix) N's and W's first passes are not predicted; neither has an image of the code it compiles

**Evidence (verified).**
- NetworkDynamics' precompile workload is 20 lines: a three-vertex diffusion network, one call of the core loop (`src/precompile_workload.jl`).
- In N, ND's image holds only that path under the facts owner. Everything else ND reaches in tier S is compiled by facts in the session:
  - `find_fixpoint` into NonlinearSolve's polyalgorithm;
  - `jacobian_eigenvals`;
  - symbolic indexing;
  - the callbacks and `ODEProblem(nw, …)`.
- P0 takes the same code from plain images.
- §1.3's "N: ND's image holds ND's code compiled by facts" overstates this.
- W has no image of the facts owner at all (§1.3 says so). It compiles everything it reaches by facts, Makie's figure pipeline included. Makie alone took 134 s to precompile under `all`.
- §0 calls W "TraitReport's form (b)". Form (b) is a precompiled package (`TraitReport/src/ReportCore.jl`, `env_b/`), whose image holds its facts code. W is a script.
- §2.4's rule ("if W costs more than three times P0's, the guideline gets a rule: an application that is a trait module needs a package with a workload") follows from §1.3 without a run.

**Fix.**
- State the expectations: N's first pass above P0's in steps b–e, and W's well above.
- Give "N holds" a criterion that the P4 draft can use: N precompiles, every digest holds, and its first pass is recorded against P0's. The P4 draft picks layout A from it.
- Note that a larger ND workload is a package change beyond the three-line wrap. P4's `TraitWorld.@workload` is where it belongs.
- Remove "TraitReport's form (b)".
- Either measure the packaged form (the workload's module as a small package with `@compile_workload`), or state the guideline's rule as expected from §1.3 and keep W's single run as its number.

### 7. (should fix) The wrap's ownership gap is real, slightly larger than stated, and in no Deviations table

**Evidence (verified, `TraitWorld/src/trait_module.jl`).**
- **Checked:** `_process` (`:94–146`) passes to `_rewrite_fdef` and its `_check_methods` only:
  - `function` and `=` definitions whose signature is a call named by a symbol or a dotted name (`_is_fdef`, `:383`);
  - the same under a bare `@inline` or `@noinline` (`_PASS_MACROS`), under `@doc`, or under the concreteness and fully-typed prefixes.
- **Not checked** (each returns the expression unchanged):
  - `@generated` (NetworkDynamics `utils.jl:144`, `:161`; `component_functions.jl:1134`);
  - `@eval`, `eval`, `Core.eval` (the loops in `metadata.jl:168`, `:1036`);
  - `Base.@propagate_inbounds` and `@propagate_inbounds` (7 uses in `coreloop.jl` and `gbufs.jl`);
  - `Base.@constprop`, and `Base.@inline` written with its module (a dotted macro name is not in `_PASS_MACROS`);
  - `@kernel`, `@kwdef`, any other macro;
  - functors `(x::T)(…)`, NetworkDynamics' core loop among them (`coreloop.jl:1`);
  - definitions inside top-level `for`, `if`, `let`, `@static`;
  - files included inside a macro (`@compile_workload`).
- **A partial cover the plan misses.** `_check_methods(mod, f)` checks every not-yet-seen method of `f` that `mod` defined. So a later checked definition of the same function catches earlier unchecked ones.
  - DiffEqBase's `Base.@constprop :aggressive function solve(prob::AbstractDEProblem, …)` (`solve.jl:653`, the guideline's own example) is caught only by the plain `solve(prob::AbstractNoiseProblem, …)` at `:716`.
  - The gap is therefore order-dependent.
- **A second gap,** noted in `ownership.jl`'s header and also in no table: a definition laundered through `Core.eval(Owner, …)` counts as the owner's.
- **No reference covers it.** Traits §9 ("a definition in a trait module: the module owns the method's function or a type in it") and §10.2 ("`OwnershipError` at the definition") have status Implemented. No row of traits §17 covers it. T-34 is about error types.
- The census cannot "confirm" the gap. The method table does not say which syntax made a method.
- The gap does not touch P3's numbers: NetworkDynamics shows no pirate, and G2 does not depend on rule 3.

**Fix.**
- The coordinator adds a T- row now. CLAUDE.md: "Where the code falls short of a reference: that reference's Deviations table". The guideline's §0.7 says whoever changes the reference adds it, but here no reference changes; the row only records the code.
  - **Reference column:** §9, §10.2.
  - **Implementation column:** "only `function`/`=` definitions, bare `@inline`/`@noinline`, `@doc` and the prefixes are checked at once; methods made by other macros, `eval`, functors or inside top-level blocks are checked only when a later checked definition of the same function follows; `Core.eval(Owner, …)` counts as the owner's".
  - **Where:** `trait_module.jl:94–146`, `:383`; `ownership.jl` header.
  - Add a test that pins it: an expected failure.
- Drop "If the census confirms the gap" from risk 8.

### 8. (should fix) The new scripts need the harness, and W's plotting part has no home

**Evidence.**
- §3 gives `p3_loads.jl` and `p3_pirate.jl` a setting tag. Only `run_workload.sh` provides:
  - the lock, `nice`, the timeout;
  - the "precompiled" check;
  - the header with builds and load average;
  - the depot and `-J` per setting.
- In W, steps f and g must run inside the trait module after the plotting load. `ndw_trait.jl` wraps only `workload_steps.jl`. After the split, `workload_plot.jl` has to enter `NDW` later:
  - `Core.eval(NDW, :(using CairoMakie, GraphMakie, Observables))`;
  - then `Base.include(NDW, "workload_plot.jl")`.
  - That is not `@trait_module`'s transform. The definitions get the module flag (so they are compiled by facts) but not the wrap's checks. The plan does not say this.
- `JULIA_TW_STRICT=1` at start also runs strict mode's image check for every package activated during the stack's loads (`_strict_image_refusals`). That is a different experiment from "a pirate defined after the first solve".

**Fix.**
- Make `run_workload.sh` take the script and a `STRICT` variable, and print the real value in the header.
- Specify W's plot part as above, or move f and g into a second trait module defined after the plotting load.
- In `p3_pirate.jl`, call `TraitWorld.strict!(true)` just before the pirate.

### 9. (should fix) "Last-bit differences are not G1 failures" is an interpretation the references do not make

**Evidence.**
- Facts §2.1: "computes what the same call computes in plainly compiled code, in the same world, with the same effects, or raises".
- No reference or open issue mentions `muladd`, `@simd` or floating-point contraction (searched `reference/` and `open-issues.md`).
- E-151 found every digest bit-equal under `all`.
- The P1 plan's tolerances are a comparison convention. They do not exempt anything from G1.

**Fix.**
- Keep the tolerance fields as the pass/fail rule for the port.
- Record every exact difference in N, W or A0 with its first differing field.
- If one appears, open an issue on whether G1 admits contraction differences, rather than declaring it admitted (CLAUDE.md, precedence rule 3).

### 10. (minor) The `@generated` counts are textual mentions, not definitions

Definitions in `src/`, from a search for `@generated function` and `@generated f(`:

| Package | Plan's count | Definitions | Note |
|---|---|---|---|
| NetworkDynamics | 5 | 3 | `utils.jl:141`, `:158` are docstrings |
| SciMLBase | 12 | 9 | |
| DiffEqBase | 3 | 2 | |
| OrdinaryDiffEqCore | 13 | 12 | |
| RecursiveArrayTools | 6 | 4 | |
| SymbolicIndexingInterface | 1 | 1 | |
| Makie | 3 | 3 | |

### 11. (minor) DiffEqBase's list of pirates

- §1.5 and §9a list four kinds. Question 1 above adds `isempty` on the abstract callback types and `solve`/`init` on `AbstractDEProblem`.
- Say "several; the census lists them" rather than an enumeration that looks complete.

### 12. (minor) G2 under `all` is promised, not yet checked across loads

- §0 and §1.2 say "G1 and G2 hold for all of it".
- F-11: G2 across loads "is not run under `all` (E-29)".
- Write "promised; order B in A0 checks it (E-29)".

### 13. (minor) Import only what the wrap needs

- `using TraitWorld` brings TraitWorld's exports into NetworkDynamics' namespace.
- No clash today, but P4 adds names.
- The forks write `using TraitWorld: TraitWorld, @trait_module` (`forks/CSV/src/CSV.jl:26`). The prologue and `@stmt` use only qualified references, so this suffices.

### 14. (minor) §1.4 item 8 describes the wrap incompletely

- Add:
  - structs are rewritten;
  - each plain definition also gets `_check_entries_intact`;
  - the end runs `_refuse_overrides` and `check_definitions`, which fails a build on a problem.
- "Each plain function definition is followed by an ownership check" should say "each definition of the forms `_is_fdef` recognizes" (finding 7).

### 15. (minor) Risk 7 should point at open issue 46

- The union-split question is already open issue 46 (F-15).
- At a concrete split, dispatch selects one method, so a module's `max_methods 1` is not expected to stop a split.
- The dispatch profiler stays optional. A difference goes to issue 46, not to a new open issue.

### 16. (minor) Housekeeping

- 476 packages "in 353 s" (§0, §5.9) against E-151's "354 s".
- The census's `OPT` line repeats what the source already shows (§1.4 item 5). Drop it.
- The plotting load brings 167 packages beyond the simulation group's 186, TraitWorld included (verified from the manifest). The plan says 185.
- Stage C: drop it (finding 4).

---

## What was done with the findings

Nothing yet. The plan's author revises the plan. Finding 7's deviation row is the coordinator's.
