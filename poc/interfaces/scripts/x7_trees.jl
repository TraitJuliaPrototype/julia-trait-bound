# The audit of what is sealed (the note, "Sealing" and "Trait wrappers"): after
# each load, which methods pirate the sealed region, i.e. what the trait world
# compiles against: Julia, the trait packages, and what trait wrappers bring in
# with their implementations and dependencies. Makie, reached only by calls
# upward (MakiePlots), is in no view and is not sealed. For the two core
# wrappers the script also shows what they would report without the
# implementations they name. Tolerations are ignored, so the output is what the
# lists must name. Fresh process:
#   julia +1.12.2 --startup-file=no --project=poc/interfaces/env poc/interfaces/scripts/x7_trees.jl
using TraitWorld, Printf
TraitWorld.piracy_mode!(:warn)
function report(tag)
    TraitWorld._RESCAN[] = true                       # every method, not only those since the load's own scan
    empty!(TraitWorld.TOLERATED)                      # the raw audit: what the lists must name
    t = @elapsed found = TraitWorld.find_pirates!()
    bypkg = Dict{String,Int}()
    for p in found; bypkg[p.definer] = get(bypkg, p.definer, 0) + 1; end
    @printf("%s: %d piratical method(s) from %d package(s), scanned in %.2f s; sealed: %d names\n", tag, length(found), length(bypkg), t, length(TraitWorld.SEALED))
    for (d, n) in sort!(collect(bypkg); by = p -> -p[2])
        ex = first(filter(p -> p.definer == d, found)).method
        println("   ", rpad(d, 26), rpad(n, 5), first(string(ex), 110))
    end
    return bypkg
end
"What the scan reports with a wrapper's implementations not named: the delegation's effect."
function without_delegates(tag, core::Module)
    k = TraitWorld._wrap_key(core)
    saved = TraitWorld.DELEGATES[k]
    TraitWorld.DELEGATES[k] = Module[]; empty!(TraitWorld._PIRATICAL)
    b = report(tag)
    TraitWorld.DELEGATES[k] = saved; empty!(TraitWorld._PIRATICAL)
    return b
end
@eval using Columns, Stats, Reports
report("trait stack")
@eval using DataFramesWrapper
report("+ DataFramesWrapper (seals DataFrames' tree)")
@eval using MakiePlots
mk = report("+ MakiePlots (calls into Makie; CairoMakie loaded, nothing of it sealed)")
@eval using StaticArraysCoreWrapper
const StaticArraysCore = StaticArraysCoreWrapper.StaticArraysCore
report("+ StaticArraysCoreWrapper (seals StaticArraysCore, StaticArrays and their dependencies)")
without_delegates("   the same without StaticArrays named", StaticArraysCore)
@eval using ColorTypesWrapper
const ColorTypes = ColorTypesWrapper.ColorTypes
ct = report("+ ColorTypesWrapper (seals ColorTypes, Colors, ColorVectorSpace, ImageCore and their dependencies)")
without_delegates("   the same without Colors, ColorVectorSpace and ImageCore named", ColorTypes)
