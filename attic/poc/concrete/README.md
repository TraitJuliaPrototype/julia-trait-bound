# poc/concrete — concrete mode: abstract types in hot loops, traced to their root

An opt-in contract that a region's code works on concrete types only
(`TraitRegions/src/concrete.jl`):

```julia
@warn_on_abstract @region Series begin ... end     # the whole region, warnings
@region Series begin
    @error_on_abstract f(t, c::Config) = ...         # one op, errors
end
```

The check runs once per op and representation: when a package is built (its
workload calls the op, or a conformer's `precompile_seal` compiles it) and at
the first call at a representation not checked yet. It walks the optimized
code of the worker and of every function of the region's own package that it
calls on a normal path, and reports each use of an abstract value: a dynamic
call, a field read on a value of unknown type, an abstract return or result
type. Each report is traced back, through any number of layers and packages,
to its root cause:

- a field declared with an abstract type;
- a variable captured by a closure and reassigned (boxed);
- a variable whose type changes between paths;
- a container with an abstract element type;
- a non-constant global;
- an abstract declared result.

Reports group by root cause; uses inside loops are counted. Warn mode reports
each root cause once; error mode raises `AbstractTypeError` instead of running
(every call, like poison). Results of checks made during the region package's
own build are kept in its image, so later sessions are not warned again.
`check_concrete(Trait)` returns the same findings for every op and sealed
representation, for tests and CI.

`@region` now also asserts every witness result to the type the trait
declares, so an inference failure inside a conformer's witness stops at the
trait boundary instead of spreading into workers.

## The hierarchy

| package | role |
|---|---|
| `CBottom` | `Config` with `scale::Real` (the cause); `TypedConfig` with `scale::Float64` (the fix) |
| `CMid1`, `CMid2` | `gain(c) = scale(c) * 2`; `factor(c) = gain(c) + 1` |
| `CTop` | trait `Series`, a seal, and a `@warn_on_abstract` region whose hot loop calls `CMid2.factor` |

    julia --project=poc/concrete/env -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
    julia --startup-file=no --project=poc/concrete/env poc/concrete/run.jl

## Results (stock 1.12.2, October 2026)

Building `CTop` prints:

    Warning: @warn_on_abstract: region op `scaled_sum` at representation Vector{Float64} uses abstract types on its normal path; 1 root cause:
      1. field `scale` of `CBottom.Config` is declared `Real` (CBottom.jl:6)
           3 uses, 2 in loops; first in a loop: CTop.jl:21  *(::Float64, ::Any)
           ← CMid2.factor(::CBottom.Config) returns Any (CTop.jl:21)
           ← dynamic call +(::Any, ::Int64) returns Any (CMid2.jl:4)
           ← CMid1.gain(::CBottom.Config) returns Any (CMid2.jl:4)
           ← dynamic call *(::Real, ::Int64) returns Any (CMid1.jl:4)

`scaled_sum_typed` (same code, `TypedConfig`) is not reported. In a later
session (`run.jl`): no warning at first use; the loop over 10^6 elements takes
66.2 ms with the abstract field and 0.89 ms with the typed one, 74× (66 vs
0.9 ns per element).

On the nine-package ecosystem, `check_concrete(ColTable)` (1.3 s for every op
at every sealed representation, nothing annotated) reports:

| op | root causes |
|---|---|
| `ColPlots.histcounts` | 1: variable `lo` is boxed (ColPlots.jl:35), 16 uses, 10 in loops |
| `ColPlots.histplot_naive` (Makie inside a worker, deliberately) | 1: traced through Makie's `_block` into `GridLayoutBase.top_parent`, which returns `Any` |

every other op is clean. One check costs 5–27 ms warm.

## Limits

Only the region's own package's code is checked; other code appears in
traces, not as findings. A check made during a conformer's build cannot be
kept in the region package's image, so it reruns at the first call of each
session. Witness calls are indirect calls by design (5.0× at 16 elements for
fine-grained traits, X3) and are not flagged. Traces follow the optimized code;
when the optimizer removes a cause (a box), the abstract result type remains
and is reported with the boxed variables found in the lowered code. Small
unions of up to four concrete types count as concrete (union splitting).
