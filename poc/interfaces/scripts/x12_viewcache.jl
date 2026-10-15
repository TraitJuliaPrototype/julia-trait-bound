# View caches (TraitWorld/src/viewcache.jl): a representation the library's
# image does not hold (UserTypes.Ramp, its own representation, never seen by
# Reports), its first calls in a session, with and without the view cache,
# and with other packages loaded before or after the view's packages.
#   record: a lean session calls Reports on a Ramp, then builds the view cache in the foreground
#   lean | before | after: a new session (before/after: CSV, DataFrames, the DataFrames wrapper
#   and MakiePlots loaded before or after Reports and UserTypes)
# On the attic's patched Julia, the trait-world filter (insertion and load-time halves;
# JULIA_TW_FILTER=0 switches both off).
#   JULIA_TW_VIEWCACHE_DIR=<fresh dir> julia +1.12.2 --startup-file=no --project=poc/interfaces/env poc/interfaces/scripts/x12_viewcache.jl record|lean|before|after
using Printf
const SCEN = ARGS[1]
t = 0.0
SCEN == "before" && (t += @elapsed @eval using CSV, DataFrames, DataFramesWrapper, MakiePlots)
t += @elapsed @eval using TraitWorld, Reports, UserTypes
SCEN == "after" && (t += @elapsed @eval using CSV, DataFrames, DataFramesWrapper, MakiePlots)
@printf("%s: loaded in %.2f s; view caches loaded: %d, signatures they checked: %d\n", SCEN, t,
        count(n -> !(n in TraitWorld._VC_STALE), TraitWorld._VC_SEEN), length(TraitWorld._VC_CHECKED))
ms(s) = @sprintf("%7.1f ms (%6.1f ms compiling, %6.1f ms of it recompiling)", s.time * 1e3, s.compile_time * 1e3, s.recompile_time * 1e3)
r = UserTypes.Ramp([1.0, 2.0, 3.0], 3)
println("summarize(ramp), first        ", ms(@timed summarize(r)))
println("histcounts(ramp, 1), first    ", ms(@timed Reports.histcounts(r, 1)))
println("zscores(ramp, 2), first       ", ms(@timed Reports.zscores(r, 2)))
println("colstd(ramp, 1), first        ", ms(@timed Reports.colstd(r, 1)))
println("report(ramp), first           ", ms(@timed Reports.report(r)))
println("workers checked in this session (not from a cache): ", length(TraitWorld._VC_NEW))
TraitWorld._FILTER_ON[] && println("patched Julia: invalidations skipped ", TraitWorld.filter_skipped(),
                                   ", image edges kept at load ", TraitWorld.load_filter_skipped())
if SCEN == "record"
    t = @elapsed built = viewcache_flush(; wait = true)
    @printf("view caches written and built in %.1f s: %s\n", t, join(built, ", "))
end
