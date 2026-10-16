# Session 23 (2026-10-16): the runtime as methods, patched Julia 1.13.2, the first demonstrator steps

## The user's decisions at the start

The user asked for a review of the design, the decisions needed before implementing it, then: "implement the new design, get the patched Julia 1.13.2 up and running and make as much progress as possible on TraitMakie and TraitDifferentialEquations". Recommendations D1–D9 were accepted ("go"), with two refinements from the user's questions:
- **D5, the model:** a plain right-hand side is stored as a dynamic call (`DynamicFn`) in the library's `FunctionModel{P}`, so the solver compiles per parameter type, never per function. A model type that implements `rhs!` is the comparison (compiled per type).
- **D6, AD tags:** the user asked whether `Dual{Tag{Callable{A, S, DynamicCall}}}` is achievable. Answer, tested (`$TMPDIR/tag/t.jl`, ForwardDiff on 1.13.2): yes, with the tag naming the callable's *primal* signature (`Tag{Sig{A, S}, Float64}`, ForwardDiff's tag check off), because a tag at the dual signature would contain itself.
  - Two different loss closures then share one solver specialization, and give the default tags' gradients.
  - Nesting is ordered by construction: the inner signature contains the outer duals.
  - The hazard: a closure that captures outer duals and differentiates at the same primal signature gets the outer level's tag. The test returned 4.0 instead of 6.0, silently. The guard is to inspect the closure's field types where the `Callable` is made and fall back to its own type as the tag. That is as sound as ForwardDiff's defaults.

The review's issues (in the reply of that turn), in short:
1. Conformances as methods invalidate their own entries, and the patched filter would keep the stale code. Measured, and fixed by `@max_methods 1` plus a fallback.
2. Refusing a late override needs a runtime hook. TraitWorld checks at declarations, at the end of a trait module and at first calls.
3. "Own methods" must include applicable inherited methods (types first).
4. Two TraitDifferentialEquations rows had no mechanism under keys (a new model type in milliseconds; a second loss closure).
5. "View" meant four things.
6. Small inconsistencies in the notes.

## Patched Julia 1.13.2 (`julia-1.13/`, a worktree of `julia/` on `trait-world-1.13`)

- **Built and running.** `julia-1.13/tw-build.sh` runs `make -j4` niced under a memory watchdog that kills the build below 4 GB available. The build needs these network hosts: cache.julialang.org, github.com, api.github.com, codeload.github.com, objects.githubusercontent.com, release-assets.githubusercontent.com, raw.githubusercontent.com, curl.haxx.se, curl.se.
- **Three fixes to the load half** (`Compiler/src/reinfer.jl`, commits 28d71bf9cb, f1cf1efa1c, b058af111e). Image validation runs in the compiler's world, which is fixed early in the bootstrap, before Base's `ENV`, `split` and `pathof` exist. The injected variant had moved that world forward, so its tests never saw this.
  - The globals use `RefValue`, because `Ref` has no constructors at that point of the bootstrap.
  - The environment is read with `getenv`.
  - The names of the standard libraries are a literal list.
- **Two TraitWorld fixes for the patched build:**
  - **A trait module is registered with the filter when it starts.** It was registered only when complete, so the methods it defined while loading counted as outside definitions and left the machinery's registries stale (`trait_params(StateVector)` returned `()`).
  - **The machinery is protected again.** That is sound now that the registries hold no edges (below).
- **Tests:** TraitWorld's 346 tests pass on the patched build as on stock.

## TraitWorld: the runtime as methods (keys-plan §6) and the rest of §4b

Commits e26683a, 87d30f9, 4be9524 and d65bb57 on `main`.

**The runtime as methods:**
- **Conformances are methods.** `conformance(As{X}(), u::U)` is defined by `@implement` from a builder fixed when the conformance is declared.
  - It is declared with `@max_methods 1`, and has a fallback (generic implementations and families: the slow path, cached).
  - A new conformance invalidates no compiled entry. Test: "a new conformance invalidates no entry".
- **Entries are `@inline` ordinary methods,** `@nospecialize` on trait arguments.
  - `enter(EntryPos{F,pos,nargs}(), t)` builds the trait object from `needed(...)`, which is fixed when the trait module is complete, or before its `@workload`.
  - `checked_call` is inlined, with methods for fixed arities.
  - Dispatch is on singleton instances (`As{X}()`, `EntryPos{...}()`). Dispatch on type values was 105 and 214 ns.
- **Trait sets carry no free type variable.** A trait set is the families plus one `PTag{F, i, v}` per fixed parameter. Before, a worker signature `TObj{T} where {Self, T >: ColTable{Self}}` left `Self` undeterminable, so Julia called every worker through the boxed calling convention: 48–64 bytes per call, open issue 3.10 of session 22.
- **Measured** (`total(t, 16)`, 4 × 16 elements):
  - typed callers: 33 ns against 30 ns plain, no allocation (209–460 ns before);
  - the worker alone runs at plain speed;
  - untyped callers: 270–450 ns. The cause is not yet found; it is not the `Union` in the trait set and not the `checked_call` varargs.

**The rest of §4b:**
- **No implementing type when defaults serve every operation.** `Key{Nothing, F}`: two record types that keep the defaults share one worker; an override makes the type the implementing type.
- **Overrides refused after a conformance.** `check_overrides`, applied at declarations, at the end of a module and at first calls; on stock Julia there is no hook at the definition itself.
- **Fields define parameters by matching** (`data::Vector{T}`, `Dict{K, V}`), with the mismatch refused at the conformance.
- **An immutable type's parts are held** (one worker per key for mutable and immutable types; mutable types are read through).
- **Limitation:** a result like the input cannot be rebuilt from a `Dynamic` of an immutable type, which keeps only its parts. It raises an error naming this.

**What the demonstrators needed:**
- **Registries hold no edges.** Every registry (`trait_params`, `trait_fields`, `implementation`, `projection`, `op_*`, …) has `@max_methods 1` and two sentinel methods. Before, loading a package that declares traits re-inferred `_builder_for`: 0.4 s in a solver's first call. Loading TraitDifferentialEquations now invalidates nothing.
- **Internal functions of a trait module take trait objects without bounds,** checked through their bodies. The notes adopted this; the prototype had not implemented it.
- **`DynamicFn{A,S}` and `dynamic_fn`** for stored functions, and `Dynamic{X}(x)` for a library's own values.
- **Family conformances by fields:** `@implement IntegratorView Tsit5Integrator{T,P} where {T,P}`.
- **Dynamic positions count as deeply concrete;** `Nothing` passes by reference in dynamic calls; caches are keyed by `Pair{Any,Any}`; module scans skip deprecated bindings.

## TraitDifferentialEquations step 1 (f4c526d)

**`ODECore`** (trait module):
- **Traits:** `ODEModel{T}`, `IntegratorView{T,P}` (fields only, so there is no implementing type) and `Callback`.
- **Library types:** `FunctionModel{P}` (a `DynamicFn`) and `FunctionCallback`.
- **The solver:** Tsit5 with a PI controller and saveat by Hermite interpolation. Callbacks are kept as `Dynamic{Callback}` and see the integrator as `Dynamic{IntegratorView}`. A callback may write `u`, terminate, or change `p`.
- **The ordinary layer:** SciML's interface, plus a precompile workload.
- **Accuracy:** it agrees with stock OrdinaryDiffEq to 1e-13 at tight tolerance.

Measured, fresh sessions, stock 1.13.2 (stock SciML in brackets, `experiments/baseline-1.13.md`):

| row | what | trait world | stock SciML |
|---|---|---|---|
| 1 | first Tsit5 solve | 73–76 ms | 0.14–0.17 s |
| 2 | a second model function | 14 ms | 0.10–0.11 s |
| 4 | a new `DiscreteCallback` | 12–14 ms | 0.67–0.83 s |
| 10 | `typeof(integrator)` | `Tsit5Integrator{Float64, Vector{Float64}}` | 3,553 chars |
| 7 | rows 1, 2, 4 with CSV, DataFrames, CairoMakie loaded before or after | row 2 unchanged, row 4 35–51 ms; row 1 0.7–1.05 s; ODECore invalidated: 2–4 methods (`keep_callback`, `solve_ode`); machinery: 323 (patched) to 670 (stock) | to measure |

**Row 7 is not yet what the design predicts.** The loads bring pirates of Base: OffsetArrays (12 methods), StatsBase and Durations. The filter lets pirates invalidate by design. The triggers also include owned methods (InlineStrings, Unitful) reaching Base methods compiled for the machinery, which the insertion half does not protect. Separating the two needs a pirate-free load set.

## TraitMakie step 1 (f85b069)

**`PlotCore`** (trait module):
- **Traits:** `Positions`, `ColorSpec` and `Plot`. `Lines` and `Scatter` keep their data and colour as dynamic values.
- **Axes** keep their plots as `Vector{Plot}`. The loops over data are bounded functions, compiled per key when opened.
- **Cairo** is reached through declared calls (`@call`) into the ordinary module.
- **The ordinary layer** offers `lines`, `scatter`, `save`, and converts `x, y` explicitly.

Measured (three fresh runs per order):

| | stock 1.13.2 | patched 1.13.2 |
|---|---|---|
| load | 0.35–0.39 s | 0.30–0.41 s |
| work to the first PNG, alone | 0.105–0.22 s | 0.13–0.22 s |
| CSV and DataFrames loaded before | 0.31–0.32 s | 0.32–0.33 s |
| CSV and DataFrames loaded after | 0.37 s | 0.083–0.090 s |
| PlotCore code invalidated by those loads | 0 | 0 |
| TraitWorld machinery invalidated | 285 | 14 |
| a new data type at the prompt (forwarding) | 61–132 ms | 61–107 ms |

## Next

1. **Row 7 and TraitMakie row 2:**
   - a pirate-free load set;
   - Base methods compiled for trait-world callers at insertion (the insertion half's equivalent of the load half's callee rule);
   - the "before" order's 0.2 s.
2. **TraitDifferentialEquations step 3, Rodas5:** a library-owned tag for the Jacobian; ODEModel at dual signatures.
3. **Step 4:** label tags for gradients (`tgradient`, with the capture guard).
4. **TraitMakie rows 4–6:** a user recipe; a colour shape change (`:red`, then a vector, then `Gradient`); dispatch targets.
5. **The untyped entry path** (270–450 ns).
6. **Phase 4:** remove the `{R}` spelling (D2; not done this session).
7. **Rebuild the trimmed-binary acceptance** (`verify_main` passes in the tests; the juliac build was not run).
