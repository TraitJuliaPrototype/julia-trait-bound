# juliac --trim build of the minimal trait-bound program (VMApp.main).
#   cd poc/verifymain/trim && julia --project=../env $JULIAC --output-exe vmapp --experimental --trim=unsafe-warn app.jl
using TraitRegions, VMApp

function (@main)(args::Vector{String})::Cint
    VMApp.main(args)
    return 0
end

# trait dispatch is dynamic, so trim cannot see its targets; verify_main
# enumerates them from the seals and registers them as entry points
let r = verify_main(VMApp.main, (Vector{String},); entrypoints = true)
    println(Core.stdout, "verify_main: ", isclosed(r) || r.checked_native == false ? "no normal-path holes" : "OPEN",
            ", ", length(r.targets), " trait targets registered as entry points")
end
