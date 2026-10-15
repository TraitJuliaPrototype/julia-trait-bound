# The audit of the wrapped trees (writeup/poc3-plan.md §5, M6): which packages
# in DataFrames' and CairoMakie's dependency closures pirate the sealed region
# (Julia, the trait packages, the interfaces' closures). Their names are what
# the two interface packages tolerate in their Project.toml. Fresh process:
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
    return sort!(collect(keys(bypkg)))
end
@eval using Columns, Stats, Reports
report("trait stack")
@eval using DataFramesInterface
dfi = report("+ DataFramesInterface (DataFrames' tree)")
@eval using MakieInterface
mk = report("+ MakieInterface (Makie's tree, CairoMakie loaded)")
# each interface tolerates the pirates in its own wrapped tree (Tables is in both)
println("\ntolerate in DataFramesInterface: ", filter(in(TraitWorld._manifest_closure("DataFrames")), dfi))
println("tolerate in MakieInterface: ", filter(in(TraitWorld._manifest_closure("Makie")), mk))
