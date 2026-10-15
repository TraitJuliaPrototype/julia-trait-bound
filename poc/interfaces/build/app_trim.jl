# juliac --trim build of the trait-world pipeline alone (demo 2 step 3): no
# DataFrames, no Makie. verify_main enumerates the entries' targets, registers
# them as entry points, fills the entry caches and closes the world.
using TraitWorld
import Pipeline
function (@main)(args::Vector{String})::Cint
    Pipeline.pipeline(args)
    return 0
end
let r = verify_main(Pipeline.pipeline, (Vector{String},); entrypoints = true)
    println(Core.stdout, "verify_main: ", isempty(filter(h -> !h.errorpath, r.holes)) ? "no normal-path holes" : "OPEN",
            ", ", length(r.targets), " targets registered as entry points")
end
