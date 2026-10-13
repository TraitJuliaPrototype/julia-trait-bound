# An ordinary application: the only package that depends on both Stats and
# UserTypes, so code for their combination lives here (rule 7).
module App
using Columns, Stats, UserTypes
using PrecompileTools: @compile_workload
export report, main

"A Stats function at UserTypes' own representation: neither package can cache it."
report(r::Ramp) = weighted(r, 1)

"""
A program: the kind of table is chosen at run time, so its type is a union of
two user types, and every call into the trait world goes through the entries.
"""
function main(args::Vector{String})
    n = length(args) > 1 ? parse(Int, args[2]) : 4
    t = (isempty(args) || args[1] == "ramp") ? Ramp(collect(1.0:n), 2) :
        Measurements([collect(1.0:n), collect(2.0:n+1)])
    # entries return what their workers return, which ordinary code asserts
    println(Core.stdout, colmean(t, 1)::Float64, " ", total(t, n)::Float64, " ", weighted(t, 1)::Float64)
    return 0
end

@compile_workload begin
    report(Ramp([1.0, 2.0], 2))
    main(["ramp", "3"]); main(["m", "3"])
end
end
