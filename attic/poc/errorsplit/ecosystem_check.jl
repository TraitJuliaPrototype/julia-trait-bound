# The error split on the real ecosystem (stock 1.12.2), in load phases:
#   core packages -> ChurnStorm -> CairoMakie -> ColPlots (Makie inside a worker).
#   JULIA_TRAITBOUND=warn julia --startup-file=no --project=ecosystem/scripts12 poc/errorsplit/ecosystem_check.jl
# Also runs against a pre-PoC TraitRegions (no audit): phases 1-3 and the benchmark only.
using ColStats, ColReports, PlainStack, EagerTables, LazyTables, MatrixTables, TraitRegions, ColTables
using BenchmarkTools, Printf
const POC = isdefined(TraitRegions, :audit_all)

PlainStack.getcol(t::EagerTable, i::Int) = t.cols[i]
PlainStack.ncols_direct(t::EagerTable) = length(t.cols)

const LOG = IOBuffer()
POC && Base.CoreLogging.global_logger(Base.CoreLogging.SimpleLogger(LOG, Base.CoreLogging.Warn))
nwarn() = count("PiracyError", String(copy(LOG.data)))

tables = (EagerTable([rand(100) for _ in 1:6]), LazyTable(rand(100), 2), MatrixTables.MatTable(rand(100, 6)))
ops(t) = (report(t), report_dyn(t), summarize(t))

function phase(name)
    s = @timed foreach(ops, tables)
    @printf("%-28s 3 tables x 3 ops: %7.1f ms, compile %7.1f ms, recompile %7.1f ms", name,
            s.time * 1e3, s.compile_time * 1e3, s.recompile_time * 1e3)
    if POC
        a = @elapsed f = TraitRegions.audit_all()
        @printf(" | audit_all %6.1f ms, findings %d, piracy warnings %d", a * 1e3, length(f), nwarn())
    end
    println()
end

println("TraitRegions: ", POC ? "PoC, mode $(TraitRegions.MODE[])" : "baseline (pre-PoC)")
phase("first calls")
phase("second calls")
@printf("using ChurnStorm: %.0f ms\n", 1e3 * @elapsed @eval using ChurnStorm)
phase("after ChurnStorm")
@printf("using CairoMakie: %.0f ms\n", 1e3 * @elapsed @eval using CairoMakie)
phase("after CairoMakie")

if POC
    @printf("using ColPlots: %.0f ms\n", 1e3 * @elapsed @eval using ColPlots)
    s = @timed ColPlots.histcounts(tables[1], 1)
    @printf("histcounts first call: %.1f ms (compile %.1f)\n", s.time * 1e3, s.compile_time * 1e3)
    s = @timed ColPlots.histplot_naive(tables[1], 1)
    @printf("histplot_naive first call (Makie inside the worker, audit included): %.1f ms (compile %.1f)\n",
            s.time * 1e3, s.compile_time * 1e3)
    empty!(TraitRegions._CLEAN)
    a = @elapsed f = TraitRegions.audit_all()
    @printf("audit_all with an empty cache, Makie closure included: %.1f ms, findings %d, piracy warnings %d\n",
            a * 1e3, length(f), nwarn())
end

println("# steady state, report over 6 columns (ns/call)")
for len in (16, 256)
    t = EagerTable([rand(len) for _ in 1:6])
    b_static = @belapsed report($t)
    b_dyn    = @belapsed report_dyn($t)
    b_plain  = @belapsed report_p($t)
    @printf("len=%-4d plain %8.1f | static %8.1f | dyn %8.1f\n", len, b_plain * 1e9, b_static * 1e9, b_dyn * 1e9)
end
