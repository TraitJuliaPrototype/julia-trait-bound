# The program both apps compile (VMApp: verified build, VMAppW: workload only).
# Its data is a collection whose element types are chosen at runtime.

struct AppTab; v::Vector{Float32}; end
@seal Stats.Col AppTab begin
    project(t) = t.v
    vals(r)    = r
end

function tables(n::Int)
    ts = Any[]
    for i in 1:n
        push!(ts, isodd(i) ? MyTable.MyTab(Float32[1, 2, i]) : AppTab(Float32[i, 3]))
    end
    return ts
end

"Trait-bound main: every call on a runtime-typed value is a region op."
function main(args::Vector{String})
    n = parse(Int, args[1])
    acc = 0.0f0
    for t in tables(n)
        acc += Stats.colsum(t)::Float32 + Stats.sqnorm(t)::Float32
    end
    println(Core.stdout, acc)
    return acc
end

# Plain Julia, idiomatic: generic code, specialized per runtime type.
cols(t::MyTable.MyTab) = t.cols
cols(t::AppTab) = t.v
plainsum(t) = sum(cols(t)) + sum(abs2, cols(t))

function main_plain(args::Vector{String})
    n = parse(Int, args[1])
    acc = 0.0f0
    for t in tables(n)
        acc += plainsum(t)::Float32
    end
    println(Core.stdout, acc)
    return acc
end
