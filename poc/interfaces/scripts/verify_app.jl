# Demo 2 step 1 (writeup/poc3-plan.md §1, §3.7): verify_main on the full
# application and on the trim variant. Fresh process:
#   julia +1.12.2 --startup-file=no --project=poc/interfaces/env poc/interfaces/scripts/verify_app.jl [main|pipeline]
using TraitWorld
const WHICH = isempty(ARGS) ? "pipeline" : ARGS[1]
if WHICH == "main"
    using App
    App.main([App.SAMPLE, joinpath(tempdir(), "verify_app.png")])
    f = App.main
else
    using Pipeline
    Pipeline.pipeline(String[])
    f = Pipeline.pipeline
end
t = @elapsed r = verify_main(f, (Vector{String},))
show(stdout, MIME"text/plain"(), r); println()
println("\nverify_main took ", round(t; digits = 1), " s")
kinds = Dict{Symbol,Int}()
for (k, _) in r.targets; kinds[k] = get(kinds, k, 0) + 1; end
println("targets by kind: ", sort!(collect(kinds)))
for (k, S) in r.targets
    k === :declared && println("  declared: ", S)
end
holes = filter(h -> !h.errorpath, r.holes)
bymod = Dict{String,Int}()
for h in holes
    m = h.caller.def isa Method ? string(Base.moduleroot(h.caller.def.module)) : "?"
    bymod[m] = get(bymod, m, 0) + 1
end
println("normal-path holes by package root: ", sort!(collect(bymod); by = p -> -p[2]))
# "the trait part is closed": no normal-path hole whose caller is in the trait
# stack, and every trait dispatch site has enumerated targets. The code behind
# declared calls (Makie's, DataFrames') is not walked, so its holes are not counted.
const TRAIT_STACK = ("TraitWorld", "BaseTraits", "Columns", "Rows", "Stats", "Reports")
println("normal-path holes with a caller in the trait stack: ", sum(p[2] for p in bymod if p[1] in TRAIT_STACK; init = 0),
        "; declared targets not walked: ", count(t -> t[1] === :declared, r.targets))
