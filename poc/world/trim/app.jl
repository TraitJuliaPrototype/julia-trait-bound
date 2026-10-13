# juliac --trim build of App.main, a trait-bound program whose table type is chosen at run time.
#   cd poc/world/trim && ./build.sh
using TraitWorld
import App

function (@main)(args::Vector{String})::Cint
    App.main(args)
    return 0
end

# entry steps are dynamic calls, so trim cannot see their targets: verify_main
# enumerates them, registers them as entry points, fills the entry caches and
# closes the world (no checks, guard, erasure or reflection in the binary)
let r = verify_main(App.main, (Vector{String},); entrypoints = true)
    println(Core.stdout, "verify_main: ", isempty(filter(h -> !h.errorpath, r.holes)) ? "no normal-path holes" : "OPEN",
            ", ", length(r.targets), " targets registered as entry points")
end
