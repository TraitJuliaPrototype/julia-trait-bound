# X4, ported from attic/ecosystem/scripts: invalidation immunity at ecosystem
# scale (writeup/poc3-plan.md §1, demo 1 step 4). The trait stack is loaded and
# hot; then a churn source loads under @snoop_invalidations, and the trees that
# touch the trait stack are counted; then the next calls' compile time.
#   julia +1.12.2 --startup-file=no --project=poc/interfaces/env poc/interfaces/scripts/x4_churn.jl storm   (ChurnStorm: 100 types, Base methods, 20 redefinitions)
#   julia +1.12.2 --startup-file=no --project=poc/interfaces/env poc/interfaces/scripts/x4_churn.jl makie   (using CairoMakie)
#   … x4_churn.jl makie plain   (the baseline: CairoMakie's invalidations with no trait stack loaded)
using SnoopCompileCore, Printf
const WHAT = ARGS[1]
const PLAIN = length(ARGS) > 1 && ARGS[2] == "plain"
const SAMPLE = joinpath(@__DIR__, "..", "App", "data", "sample.csv")
using DataFrames, CSV
df = CSV.read(SAMPLE, DataFrame)
if !PLAIN
    @eval using Columns, Stats, Reports, DataFramesInterface
    summarize(df); zscores(df, 1); histcounts(df, 1)          # hot
    m = Matrix(df); summarize(m); histcounts(m, 2)
end
invs = WHAT == "storm" ? (@snoop_invalidations (@eval using ChurnStorm)) :
                         (@snoop_invalidations (@eval using CairoMakie))
using SnoopCompile
const STACK = ("Columns", "Stats", "Rows", "BaseTraits", "Reports", "DataFramesInterface", "MakieInterface", "TraitWorld")
# the raw log first: every invalidated instance, by package root (robust to entries SnoopCompile does not parse)
rootname(mi) = mi.def isa Method ? string(nameof(Base.moduleroot(mi.def.module))) : "?"
raw = Dict{String,Int}()
for x in invs.logmeths
    x isa Core.MethodInstance || continue
    r = rootname(x)
    raw[r] = get(raw, r, 0) + 1
end
n_stack = sum(get(raw, s, 0) for s in STACK)
@printf("X4 [%s%s] invalidated instances: %d in total, %d in the trait stack\n", WHAT, PLAIN ? ", plain" : "", sum(values(raw)), n_stack)
for s in STACK
    get(raw, s, 0) > 0 && println("   ", rpad(s, 20), raw[s])
end
trees = try invalidation_trees(invs) catch e; println("   (invalidation_trees: ", sprint(showerror, e), ")"); nothing end
if trees !== nothing
    ours(tr) = (s = sprint(show, tr); any(m -> occursin(m * ".", s), STACK))
    @printf("   invalidation trees: total=%d  touching the trait stack=%d\n", length(trees), count(ours, trees))
    for tr in filter(ours, trees)
        println("  -> ", first(sprint(show, tr), 300))
    end
end
if !PLAIN
    s1 = @timed (summarize(df); zscores(df, 1); histcounts(df, 1); summarize(m))
    @printf("   post-churn: the next calls compile %.2f ms\n", (s1.compile_time + s1.recompile_time) * 1e3)
end
