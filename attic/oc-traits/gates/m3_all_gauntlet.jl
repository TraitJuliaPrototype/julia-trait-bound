# Gate M3 §5 (D9): the policy is INERT on the M1/M2 surface. Runs every
# m1_*/m2_* gate as a subprocess under JULIA_FACTS=1 — the same scripts, exit 0
# required. Cheap (the whole set is seconds) and run at EVERY verification run.
using Test  # only for @assert-free timing convenience; not used for assertions

const JULIA = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project())`
const gdir = @__DIR__

gates = sort(basename.(filter(f -> occursin(r"^m[12]_", f) && endswith(f, ".jl"),
                              readdir(gdir); join=false)))
@assert length(gates) >= 22 "expected all m1/m2 gates present, found $(length(gates))"

fails = String[]
for g in gates
    rc = success(addenv(`$JULIA $(joinpath(gdir, g))`, ["JULIA_FACTS" => "1"]))
    rc || push!(fails, g)
    println(rpad(g, 34), rc ? "OK under all" : "FAIL under all")
end
@assert isempty(fails) "gates failed under JULIA_FACTS=1: $(join(fails, ", "))"

println("m3_all_gauntlet: OK ($(length(gates)) gates under the policy)")
