# Prediction vs observation, each in a fresh process:
#   predict: verify_main's verdict for App.f after `using App` (no call made);
#   observe: `--trace-compile` while running App.f(["4"]) once, which uses a
#            table type the representative workload run (n = 1) never saw.
#   julia --startup-file=no poc/verifymain/observe.jl [minimal|eco]
const JL = Base.julia_cmd()
const WHICH = isempty(ARGS) ? "minimal" : ARGS[1]
const ENV_DIR = joinpath(@__DIR__, WHICH == "eco" ? "ecoenv" : "env")
const CASES = WHICH == "eco" ?
    [(app, "main", mode) for app in ("EcoApp", "EcoAppW") for mode in ("recompile", "warn")] :
    [(app, f, mode) for app in ("VMApp", "VMAppW") for f in ("main", "main_plain")
                    for mode in ("recompile", "warn") if !(f == "main_plain" && mode == "warn")]

function predict(app, f, mode)
    code = """
    using $app, TraitRegions
    r = verify_main($app.$f, (Vector{String},))
    nh = count(h -> !h.errorpath, r.holes)
    print(nh, " ", length(r.uncompiled))
    for h in r.holes; h.errorpath || print("\\n    hole: ", TraitRegions._calleestr(h)); end
    for S in r.uncompiled; print("\\n    no native code: ", S); end
    """
    out = read(addenv(`$JL --startup-file=no --project=$ENV_DIR -e $code`, "JULIA_TRAITBOUND" => mode), String)
    return out
end

# Two channels: --trace-compile names each method compiled to native code;
# the cumulative compile timer also counts inference and instances that share
# unspecialized code, which the trace does not show.
function observe(app, f, mode)
    trace = tempname()
    # reported through a raw ccall (to stderr), so reporting compiles nothing
    code = """
    using $app
    Base.cumulative_compile_timing(true)
    t0 = Base.cumulative_compile_time_ns()[1]
    $app.$f(["4"])
    ns = Base.cumulative_compile_time_ns()[1] - t0
    @ccall jl_safe_printf("COMPILE_NS %llu\\n"::Cstring; ns::UInt64)::Cvoid
    """
    err = Pipe()
    run(pipeline(addenv(`$JL --startup-file=no --project=$ENV_DIR --trace-compile=$trace -e $code`,
                        "JULIA_TRAITBOUND" => mode); stdout = devnull, stderr = err), wait = false) |> wait
    close(err.in)
    out = read(err, String)
    ns = parse(Int, split(only(filter(l -> startswith(l, "COMPILE_NS"), split(out, '\n'))))[2])
    # the trace file is created on the first compile only
    lines = isfile(trace) ? filter(l -> startswith(l, "precompile("), readlines(trace)) : String[]
    return lines, ns / 1e6
end

for (app, f, mode) in CASES
    p = predict(app, f, mode)
    o, ms = observe(app, f, mode)
    nh, nu = parse.(Int, split(first(split(p, '\n'))))
    println(rpad("$app.$f", 19), rpad("guard $mode", 16), "predicted: ", nh, " normal-path hole(s), ",
            nu, " uncompiled | observed: ", length(o), " runtime compile(s), ", round(ms; digits = 1), " ms compiling")
    for l in Iterators.drop(split(p, '\n'), 1); println(l); end
    for l in o; println("    compiled at runtime: ", l); end
end
