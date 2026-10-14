# usage: JULIA_TRAITBOUND=<mode> julia --project=env run.jl Pkg1 Pkg2 ...  (loaded in that order)
for p in ARGS
    try
        Core.eval(Main, :(using $(Symbol(p))))
    catch err
        println("RESULT load=", p, " failed: ", typeof(err)); exit(0)
    end
end
using MyTable, Stats, TraitRegions
t = MyTable.MyTab(Float32[1, 2, 3])
function measure(f)
    t0 = time_ns()
    s = try
        @timed f(t)
    catch err
        err isa PiracyError || rethrow()
        return "PiracyError", NaN, NaN, (time_ns() - t0) / 1e6
    end
    return s.value, s.compile_time * 1e3, s.recompile_time * 1e3, s.time * 1e3
end
v, c, rc, tt = measure(Stats.colsum)
v2, c2, _, _ = measure(Stats.sqnorm)
again = @elapsed for _ in 1:10^5; try Stats.sqnorm(t) catch end; end
println("RESULT colsum=", v, " compile=", round(c, digits = 1), " recompile=", round(rc, digits = 1),
        " firstcall=", round(tt, digits = 1), " sqnorm=", v2, " sqcompile=", round(c2, digits = 1),
        " steady_ns=", round(again * 1e9 / 10^5, digits = 1))
