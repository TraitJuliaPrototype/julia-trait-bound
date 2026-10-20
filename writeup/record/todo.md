# Work queue

The agreed work, for agents and the user: what is to be done, why, in what order, and what it waits for. Begun 2026-10-20 (the user: "Record this change as a todo (do we need a registry for todos?)").

How to use it:
- **Each item has an ID, `W-n`,** stable and never reused. A new item takes the next free number.
- **Status:** **next** (to take up now), **queued**, **waiting** (for a decision, an agent or another item; say which), **done** (with the commit), **dropped** (with the reason). A done or dropped row stays.
- **Source:** who asked, and when; the user's words where the user asked.
- **What is not here:** questions to decide are open issues (`../open-issues.md`); experiments are in the registry (`experiments.md`); decisions are in the decision log (`decisions.md`). A work item links them.
- [`../state.md`](../state.md) §6.3 gives the order of work in brief and links here.

## Queue

| ID | Work | Source | Status | Links |
|---|---|---|---|---|
| W-1 | **Merge BaseTraits into TraitWorld's main** once the implicit crossing is built (a container with untyped items crosses by the bound; a non-conforming item fails when read); then run every demonstrator's test suite against main. | the user's answers on open issues §1 items 21–25 (2026-10-20) | waiting (the BaseTraits agent) | `../open-issues.md` §1 closed items 21–25; `decisions.md` §3 |
| W-2 | **Restructure TraitDifferentialEquations around a problem trait:** `ODEProblemTrait` (operations `rhs!`, `jacobian!` with its default; declared fields `u0`, `tspan`, `p`), with TDE's own `ODEProblem` as the canonical implementation (its `rhs!` served by its function, a `Callable` in `DynamicCall` mode; `FunctionModel` folded in); `solve(prob, alg)` the one entry point. The rows and the documents say "a new problem type", not "a new model type". | the user (2026-10-20): "I would call @implement ODEProblem Lorenz implementing a new Problem Type, rather than a new model type. And it probably should be @implement ODEProblemTrait LorenzProblem with TDE's own ODEProblem being the cannonical implementation of the trait"; "For now keep ODEProblemTrait" | waiting (W-1) | `../../TraitDifferentialEquations/src/ODECore.jl` |
| W-3 | **Make the differences between abstract types and traits clear** in the references and in `intro/`: subtyping (membership by declaration, after the fact, several traits per type, supertraits as requirements), dispatch (types first, then traits), what `<:` means for each, and what the prototype's `conforms(T, X)` stands in for. | the user (2026-10-20): "We also want to make the differences between abstract types and traits clear. They follow different rules for subtyping for example." | waiting (W-1) | `../reference/traits.md` §2–§3, §7; `../glossary.md` |
| W-4 | **Work out the unifying language for trait positions:** `f(x::Dynamic{X})` erased, `f(x::Compiled{X})` static, overrides `compiled_for(x)` and `with_dynamic(x)`; rules stated without receiver types, which become an optimization of `Compiled{X}` in the lowering. | the user (2026-10-20), open issue 33 | waiting (W-1, W-2; to circle back with the user) | `../open-issues.md` item 33; `decisions.md` §3 |
| W-5 | **TraitMakie's rows timed whole,** as TraitDifferentialEquations' are since E-146 (`@elapsed` leaves out each call's own compilation). | E-146 (2026-10-20) | queued | `../open-issues.md` §4 item 13 |
| W-6 | **Run E-145** (what follows the `Dynamic` split): the idiomatic rewrites give the hot site with more than four implementations it waited for. | `../open-issues.md` item 32 (2026-10-20) | queued (after W-1) | `experiments.md` E-145 |
| W-7 | **The first gradient with loads** (82–89 against 68–70 ms): diagnose. | E-146 | queued | `../design/evidence.md` §3 |
| W-8 | **A problem type in a package of its own** (the proving plan's `LorenzModels`): measure what its image keeps of the solver compiled for its key, and the first solve in a fresh session. | the proving plan §3; the user's question (2026-10-20): "the compiled code is cached between sessions?" | queued (after W-2) | `../plans/2026-10-20-proving-the-references.md` §3 |
| W-15 | **Facts F-11 against evidence §1:** F-11 says no current check counts code compiled by facts across package loads, while evidence §1 reports `g2all.jl` (ported to owner `:facts`, experiments 6cc0e09) with 12,368 such CodeInstances, 0 lost, in the round of 2026-10-20. Retire or narrow F-11 if the port is the check it asks for. | the rationale's proofreading (2026-10-20) | queued (after W-1: facts.md is being edited) | `../reference/facts.md` F-11; `../design/evidence.md` §1 |
| W-16 | **The idiomatic heterogeneous rows on a quiet machine:** the implicit crossing against the explicit view, like for like (the machine was noisy on 2026-10-20). | the user (2026-10-20): "The machine is noisy right now" | queued | `experiments.md` E-134, E-144; `../../experiments/hetero-idiomatic/` |

## Carried over from the order of work (`../state.md` §6.3, 2026-10-19)

| ID | Work | Status |
|---|---|---|
| W-9 | Correctness: the TraitMakie image flake; a `const DynamicFn` in a package image (a stale pointer); acceptance checks for the untyped calls' table and its world ranges; threads; G2 across package loads counting code compiled by facts. | queued |
| W-10 | The rest of the machinery's startup: the compiler's reflection code compiled again after loads. | queued |
| W-11 | The `return_type` answers after loads: a differential test, then red-green revalidation (the 45–63 ms part of open issue §4.10). | queued |
| W-12 | The next call-site cache steps: entries with an open `max_world`; the `call_cache` size. | queued |
| W-13 | Upstream proposals (`../design/julia-changes.md` §4). | queued |
| W-14 | The forks resumed, with `CSVColumn{T}` and kernels that use the declared operations. | queued |
