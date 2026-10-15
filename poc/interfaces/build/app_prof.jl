# A profiling variant of app_full (session 21): App.main's steps, timed one by
# one from process start, with the run-time compilation they cause (traced to
# stderr with `Base.@trace_compile`). Built like app_full: `./build.sh prof`.
# With APP_PROF_REPLAY=1 at build time, the compilations an earlier run traced
# (runtime_compiles.jl) are replayed as precompile statements first.
using TraitWorld
import App, CSV, DataFrames, MakiePlots, Reports

if get(ENV, "APP_PROF_REPLAY", "") == "1"
    # the statements name types of every loaded package: bind their names here first
    for (id, m) in Base.loaded_modules
        isdefined(Main, Symbol(id.name)) || Core.eval(Main, :(const $(Symbol(id.name)) = $m))
    end
    let ok = 0, all = 0
        for l in readlines(joinpath(@__DIR__, "runtime_compiles.jl"))
            all += 1
            try
                Core.eval(Main, Meta.parse(l)) && (ok += 1)
            catch
            end
        end
        println(Core.stdout, "replayed ", ok, " of ", all, " recorded run-time compilations")
    end
end

"Seconds since this process started (Linux: /proc/self/stat's start time against /proc/uptime)."
function since_start()
    stat = read("/proc/self/stat", String)
    fields = split(stat[findlast(')', stat)+2:end])          # after the command name
    start = parse(Float64, fields[20]) / 100                  # field 22 of stat, in clock ticks (100 Hz)
    return parse(Float64, split(read("/proc/uptime", String))[1]) - start
end

function (@main)(args::Vector{String})::Cint
    t_main = since_start()
    Base.cumulative_compile_timing(true)
    c0 = Base.cumulative_compile_time_ns()
    path = isempty(args) ? App.SAMPLE : args[1]
    out = length(args) > 1 ? args[2] : "report.png"
    laps = Pair{String,Float64}[]
    t = time()
    lap(name) = (now = time(); push!(laps, name => now - t); t = now)
    Base.@trace_compile begin
        df = CSV.read(path, DataFrames.DataFrame); lap("CSV.read")
        s = Reports.summarize(df)::Vector{Reports.ColSummary}; lap("summarize")
        App.report(Core.stdout, DataFrames.names(df), s); lap("print summaries")
        f = MakiePlots.figure()
        ax = MakiePlots.axis!(f; title = basename(path), xlabel = DataFrames.names(df)[1]); lap("figure, axis")
        MakiePlots.histbars!(ax, df, 1)
        MakiePlots.vlines!(ax, [s[1].mean]); lap("bars, line")
        MakiePlots.savefig(out, f); lap("render, save PNG")
    end
    c1 = Base.cumulative_compile_time_ns()
    io = Core.stderr
    println(io, "process start to main: ", round(t_main; digits = 3), " s")
    for (k, v) in laps
        println(io, "  ", rpad(k, 18), round(v; digits = 3), " s")
    end
    println(io, "compiling in main: ", round((c1[1] - c0[1]) / 1e9; digits = 3), " s (recompiling ",
            round((c1[2] - c0[2]) / 1e9; digits = 3), " s)")
    println(io, "process start to end of main: ", round(since_start(); digits = 3), " s")
    return 0
end
