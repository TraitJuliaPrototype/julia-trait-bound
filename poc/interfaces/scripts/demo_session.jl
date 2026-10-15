# Demo 1, the interactive session (writeup/poc3-plan.md §1): run line by line
# in a REPL, or as a script that prints the measurements of each step.
#   julia +1.12.2 --startup-file=no --project=poc/interfaces/env poc/interfaces/scripts/demo_session.jl
# scripts/demo1.jl runs it in a fresh process with --trace-compile and lists
# what compiled at run time, per step.
using Printf
# compile_time includes recompile_time (Base prints the latter as "of which")
ms(s) = @sprintf("%.1f ms (%.1f ms compiling%s)", s.time * 1e3, s.compile_time * 1e3,
                s.recompile_time > 0 ? @sprintf(", %.1f ms of it recompiling", s.recompile_time * 1e3) : "")
# a marker in the --trace-compile output: a fresh function compiles when first called
# (it must compute something, or Julia returns its constant without native code)
macro step(n)
    f = Symbol("step", n, "_marker")
    esc(:(@noinline $f(x::Int) = x + $n; $f(1); println("--- step ", $n)))
end

# --- step 1: the trait stack, the DataFrames wrapper and the Makie calls load ---------------------------
@step 1
t1 = @timed @eval using TraitWorld, Columns, Stats, Reports, DataFramesWrapper, MakiePlots
println("using TraitWorld, Columns, Stats, Reports, DataFramesWrapper, MakiePlots: ", round(t1.time; digits = 2), " s")
println("wrappers registered: ", join(sort(string.(nameof.(values(TraitWorld.WRAPPERS)))), ", "),
        "; modules holding declared calls: ", join(sort(string.(nameof.(TraitWorld.declarers()))), ", "),
        "; declared calls: MakiePlots ", length(TraitWorld.declared_calls(MakiePlots)),
        ", DataFramesWrapper ", length(TraitWorld.declared_calls(DataFramesWrapper)))
println("Reports imports: ", join(string.(nameof.(filter(m -> m isa Module, ccall(:jl_module_usings, Any, (Any,), Reports)))), ", "))
using DataFrames, CSV                          # the session is ordinary code
const SAMPLE = joinpath(@__DIR__, "..", "App", "data", "sample.csv")
df = CSV.read(SAMPLE, DataFrame)

# --- step 2: a DataFrame analysed by a trait module and plotted ------------------------
@step 2
s1 = @timed summarize(df)
println("summarize(df):            ", ms(s1))
println("  ", join([@sprintf("%s mean %.3f std %.3f", n, c.mean, c.std) for (n, c) in zip(names(df), s1.value)], "; "))
s2 = @timed zscores(df, 1)
println("zscores(df, 1):           ", ms(s2))
s3 = @timed summarize(df; cols = (2, 3))          # a tuple: Reports' workload has ranges and vectors only
println("summarize(df; cols=(2,3)): ", ms(s3), "  (a keyword type the image lacks: the sorter and body compile per type, as in plain Julia)")
f = figure(); ax = axis!(f; title = "sample.csv", xlabel = "x")
p1 = @timed histbars!(ax, df, 1)
println("histbars!(ax, df, 1):     ", ms(p1), "  (the trait world bins, Makie draws bars)")
p2 = @timed scatter!(ax, df, 1, 2)
println("scatter!(ax, df, 1, 2):   ", ms(p2))
p3 = @timed render(f)
println("render(f):                ", ms(p3))
savefig(joinpath(tempdir(), "demo_step2.png"), f)
h = frame(names(df), df)
println("frame(names, df) -> a handle with ", nrows_of(h), " rows, ", ncols_of(h), " columns (DataFramesWrapper's declared calls)")
bad = DataFrame(x = [1.0, 2.0], n = [1, 2])
try
    summarize(bad)
catch e
    println("summarize(df with an Int column): ", sprint(showerror, e))
end

# --- step 3: a new user type at the REPL, the one-line conformance ------------------------
@step 3
struct Measurements; data::Vector{Vector{Float64}}; end
c1 = @timed @eval @implement ColTable Measurements
println("@implement ColTable Measurements: ", ms(c1))
m = Measurements([df[!, i] for i in 1:3])
r1 = @timed summarize(m)
println("summarize(m), first result for the new type: ", ms(r1))
r2 = @timed (f2 = figure(); ax2 = axis!(f2); histbars!(ax2, m, 1); render(f2))
println("first plot for the new type:                 ", ms(r2))
println("same summary as through the DataFrame: ", r1.value == s1.value)
