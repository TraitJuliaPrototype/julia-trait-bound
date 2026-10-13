# M7: verify_main on a program whose table type is chosen at run time.
#   julia --startup-file=no --project=poc/world/env poc/world/m7_verify.jl
using TraitWorld, App
App.main(["ramp", "4"]); App.main(["m", "4"])
r = verify_main(App.main, (Vector{String},))
show(stdout, MIME"text/plain"(), r); println()
println("\ntargets:")
for (k, S) in r.targets
    println("  ", rpad(string(k), 8), S)
end
