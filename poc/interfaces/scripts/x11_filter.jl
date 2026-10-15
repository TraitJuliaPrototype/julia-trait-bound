# The trait-world invalidation filter of the attic's patched Julia, A/B on the
# same build (JULIA_TW_FILTER=1 or 0): after the stack, the DataFrames wrapper,
# MakiePlots, CSV and DataFrames load, the costs that recompiled TraitWorld's
# check code before: the one-line conformance of a new type, a first call at a
# keyword type the images lack, and how many invalidations the filter skipped.
#   JULIA_DEPOT_PATH=<own depot>:~/.julia attic/binary/julia/julia --startup-file=no --project=poc/interfaces/env poc/interfaces/scripts/x11_filter.jl
using Printf
t = @elapsed @eval using TraitWorld, Columns, Reports, DataFramesWrapper, MakiePlots
t2 = @elapsed @eval using CSV, DataFrames
@printf("filter %s; load %.2f s + %.2f s; invalidations skipped by the filter: %d\n",
        TraitWorld._FILTER_ON[] ? "ON" : "off", t, t2, TraitWorld.filter_skipped())
ms(s) = @sprintf("%7.1f ms (%6.1f ms compiling, %6.1f ms of it recompiling)", s.time * 1e3, s.compile_time * 1e3, s.recompile_time * 1e3)
struct Measurements; data::Vector{Vector{Float64}}; end
s1 = @timed @eval @implement ColTable Measurements
println("@implement ColTable Measurements      ", ms(s1))
m = Measurements([[1.0, 2.0, 4.0], [3.0, 5.0, 7.0]])
s2 = @timed summarize(m)
println("summarize(m), first                    ", ms(s2))
df = CSV.read(joinpath(pkgdir(MakiePlots), "..", "App", "data", "sample.csv"), DataFrame)
summarize(df)
s3 = @timed summarize(df; cols = (2, 3))
println("summarize(df; cols = (2, 3)), first    ", ms(s3))
struct Second; data::Vector{Vector{Float64}}; end
s4 = @timed @eval @implement ColTable Second
println("@implement ColTable Second             ", ms(s4))
@printf("invalidations skipped by the filter, in total: %d\n", TraitWorld.filter_skipped())
