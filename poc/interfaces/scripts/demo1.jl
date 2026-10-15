# Runs demo_session.jl in a fresh process with --trace-compile and reports,
# per step, what compiled at run time and whether any of it is trait-world
# code (the trait stack's workers, entries and builders should all come from
# package images: writeup/poc3-plan.md §1, demo 1 step 2).
#   julia +1.12.2 --startup-file=no poc/interfaces/scripts/demo1.jl
const JL = Base.julia_cmd()
const ENV_DIR = normpath(joinpath(@__DIR__, "..", "env"))
const SESSION = joinpath(@__DIR__, "demo_session.jl")
const STACK = ("Columns", "Stats", "Rows", "BaseTraits", "Reports", "DataFramesInterface", "MakieInterface", "TraitWorld", "UserTypes")
trace = tempname()
run(`$JL --startup-file=no --project=$ENV_DIR --trace-compile=$trace $SESSION`)
lines = isfile(trace) ? filter(l -> startswith(l, "precompile("), readlines(trace)) : String[]
println("\n=== compiled at run time, per step (--trace-compile) ===")
step = 0
counts = Dict{Int,Vector{String}}()
for l in lines
    m = match(r"step(\d)_marker", l)
    if m !== nothing
        global step = parse(Int, m.captures[1])
        continue
    end
    push!(get!(counts, step, String[]), l)
end
intrait(l) = any(s -> occursin(Regex("\\b" * s * "\\."), l), STACK)
for s in sort(collect(keys(counts)))
    ls = counts[s]
    tw = filter(intrait, ls)
    println("step ", s, ": ", length(ls), " method instance(s) compiled, ", length(tw), " mentioning the trait stack")
    for l in tw
        println("    ", first(l, 160))
    end
    for l in filter(!intrait, ls)
        println("    (other) ", first(l, 120))
    end
end
