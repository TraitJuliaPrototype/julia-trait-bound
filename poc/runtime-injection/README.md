# Load-time filter by injection, without a rebuild (session 22)

Experiments of the runtime exploration (`writeup/explorations/runtime.md`):
the load-time half of the trait-world invalidation filter, injected into a
stock Julia (1.12.2 and 1.13.2) instead of built into a patched one.

- `exp/inject_x12.jl`: x12 on stock 1.12.2 with the patched validation code injected (CSV and Makie loaded first: `report` 4.9 ms instead of 29 ms).
- `exp113/`: a minimal test (packages TW, Out, Pir) on 1.12.2 and 1.13.2. Cached code survives an owned outside method loaded first; a pirate still invalidates it. `reinfer_tw_1132.jl` is the filter ported to 1.13.2's `Compiler/src/reinfer.jl`.
- `pa/`: the two versions of `reinfer.jl` compared while porting.

Compiled caches were removed. The Julia 1.13.2 tarball and the scratch clone used are not kept.
