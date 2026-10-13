# poc/errorsplit — Stage 1 of the design: the error split on stock Julia

TraitRegions (this branch) audits, at every entry into a region op, the
compiled concrete-edge closure of the op's worker for methods defined by a
package that owns neither the function nor its argument types
(`TraitRegions/src/ownership.jl`, `TraitRegions/src/audit.jl`). Session modes
via `JULIA_TRAITBOUND` or `TraitRegions.mode!`: `warn` (default), `error`
(raise `PiracyError`), `recompile` (plain Julia).

## Packages

| package | role |
|---|---|
| Stats | trait `Col`, region ops `colsum` (calls `Stats.weight`) and `sqnorm` (LinearAlgebra `dot`) |
| MyTable | conformer with a new representation `Vector{Float32}`, precompiles its workers |
| Pirate | `Stats.weight(::Float32)`: owns neither the function nor the type |
| Dominated | `Stats.weight(::Number)`: piratical, but never the target of a call |
| Legit | `Stats.weight(::LegitNum)`, `Base.show(::IO, ::LegitNum)` for its own type |
| FakeImpl | same method as Pirate, but declares `[traitbound] implements = ["Stats"]` |
| Orphan | seals `Vector{Float32}` for `Col`: owns neither |

## Run

    julia --project=poc/errorsplit/env -e 'using Pkg; Pkg.instantiate()'
    julia poc/errorsplit/scenarios.jl          # 9 load orders x 3 modes + orphan, checked
    JULIA_TRAITBOUND=warn julia --project=ecosystem/scripts12 poc/errorsplit/ecosystem_check.jl

`ecosystem_check.jl` runs the nine-package ecosystem in load phases (core,
ChurnStorm, CairoMakie, ColPlots) and reports first-call cost, the
recompilation each load forces on region code, audit cost and findings, and
the steady-state `report` benchmark. Results: session-notes/2026-10-13-10-poc-error-split.md.
