# M5: Callable. Erased against specialized against plain Julia; first call of a new closure.
#   julia --startup-file=no --project=poc/world/env poc/world/bench_m5.jl
using TraitWorld, Columns, Stats, Printf
const JL = Base.julia_cmd()
const ENVDIR = joinpath(@__DIR__, "env")
const SINK = Ref(0.0)
function best(f, args...; reps)
    f(args...)
    minimum(1:7) do _
        acc = 0.0
        t = @elapsed for _ in 1:reps; acc += sum(f(args...)); end
        SINK[] += acc
        t / reps
    end
end
k = 2.5
const g = x -> k * x + 1.0            # a closure from above: it captures a global of this script
const h = x -> 2.5x + 1.0             # a closure from above with nothing captured
println("one call per element, over one column (ns per call | per element)")
for len in (16, 4096)
    t = [rand(len), rand(len)]
    v = t[1]
    reps = len == 16 ? 200_000 : 5_000
    pm = best(x -> map(h, x), v; reps)
    em = best(colmap, h, t, 1; reps)
    ps = best(x -> sum(h, x), v; reps)
    ss = best(colsum, h, t, 1; reps)
    bs = best(colsum, abs2, t, 1; reps)
    pb = best(x -> sum(abs2, x), v; reps)
    @printf("  len %4d: map plain %8.1f | colmap erased %8.1f (%.1f ns/el)   sum plain %8.1f | colsum specialized %8.1f (%.2f×)   Base's abs2: plain %8.1f | colsum %8.1f (%.2f×)\n",
            len, 1e9pm, 1e9em, 1e9(em - pm) / len, 1e9ps, 1e9ss, ss / ps, 1e9pb, 1e9bs, bs / pb)
end

println("\na fresh session: the first call with a new closure (ms)")
for (label, call) in (("erased   colmap(f, t, 1)", "colmap(f, t, 1)"), ("special. colsum(f, t, 1)", "colsum(f, t, 1)"),
                      ("plain    map(f, t[1])  ", "map(f, t[1])"))
    script = """
    using TraitWorld, Columns, Stats
    t = [[1.0, 2.0], [3.0, 4.0]]
    colmap(x -> x, t, 1); colsum(x -> x, t, 1); map(x -> x, t[1])    # warm the machinery with another closure
    Base.cumulative_compile_timing(true)
    f = x -> 3.0x - 1.0
    c0 = Base.cumulative_compile_time_ns()[1]; t0 = time_ns()
    $call
    t1 = time_ns(); c1 = Base.cumulative_compile_time_ns()[1]
    print((t1 - t0) / 1e6, " ", (c1 - c0) / 1e6)
    """
    out = read(`$JL --startup-file=no --project=$ENVDIR -e $script`, String)
    a, c = parse.(Float64, split(out))
    @printf("  %s  %7.2f  (compiling %7.2f)\n", label, a, c)
end
