# How much of an ad-hoc session's time to first plot would a Makie in the
# trait world save? On the attic's patched Julia, JULIA_TW_PROTECT names
# packages the trait-world filter treats as if they were trait-world code
# (measurement only: sound here because MakiePlots hands Makie plain vectors
# and strings, never CSV's or the user's types). One fresh process per run:
#   JULIA_DEPOT_PATH=<own depot>:~/.julia [JULIA_TW_PROTECT=Makie,…] attic/binary/julia/julia --startup-file=no --project=poc/interfaces/env poc/interfaces/scripts/x13_makie_protected.jl [csvfirst]
# Makie's tree: CairoMakie's dependencies without standard libraries and JLLs, and MakiePlots (141 packages).
using Printf
const CSVFIRST = !isempty(ARGS) && ARGS[1] == "csvfirst"     # load order: CSV and DataFrames first
t0 = time()
CSVFIRST && @eval using CSV, DataFrames
@eval using TraitWorld, Columns, Reports, DataFramesWrapper, MakiePlots
CSVFIRST || @eval using CSV, DataFrames
t1 = time()
Base.cumulative_compile_timing(true)
c0 = Base.cumulative_compile_time_ns()
df = CSV.read(joinpath(pkgdir(MakiePlots), "..", "App", "data", "sample.csv"), DataFrame)
summarize(df)
f = figure(); ax = axis!(f; title = "column 1")
histbars!(ax, df, 1)
savefig(joinpath(tempdir(), "x13.png"), f)
t2 = time()
c1 = Base.cumulative_compile_time_ns()
@printf("protected: %s%s\nload %.2f s; read, summarize, plot, PNG %.2f s; to the first PNG %.2f s\n",
        (p = get(ENV, "JULIA_TW_PROTECT", ""); isempty(p) ? "(none)" : count(==(','), p) > 2 ? "Makie's tree" : p),
        CSVFIRST ? " (CSV and DataFrames loaded first)" : "", t1 - t0, t2 - t1, t2 - t0)
@printf("compiling during the work %.2f s (recompiling %.2f s)\n", (c1[1] - c0[1]) / 1e9, (c1[2] - c0[2]) / 1e9)
@printf("filter: invalidations skipped %d, image edges kept at load %d; protected modules %d\n",
        TraitWorld.filter_skipped(), TraitWorld.load_filter_skipped(), length(TraitWorld._FILTER_MODS))
