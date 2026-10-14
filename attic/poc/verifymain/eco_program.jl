# The ecosystem program both apps compile (EcoApp: verified build, EcoAppW:
# workload only). Three conformers, two representations, ops from two
# region packages; the table types are chosen at runtime.

function tables(n::Int)
    ts = Any[]
    for i in 1:n
        k = i % 3
        push!(ts, k == 1 ? EagerTable([collect(range(0.0, Float64(j), length = 50)) for j in 1:4]) :
                  k == 2 ? LazyTable(collect(range(0.0, 1.0, length = 50)), 3) :
                           MatTable(reshape(collect(range(0.0, 1.0, length = 200)), 50, 4)))
    end
    return ts
end

function main(args::Vector{String})
    n = parse(Int, args[1])
    acc = 0.0
    for t in tables(n)
        acc += report(t)::Float64 + report_dyn(t)::Float64 + summarize(t)::Float64 + colmean(t, 1)::Float64
    end
    println(Core.stdout, acc)
    return acc
end
