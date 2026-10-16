using OrdinaryDiffEq
function report(tag, f)
    e, bt = try; f(); (nothing, nothing); catch err; (err, catch_backtrace()); end
    e === nothing && (println("== $tag: no error"); return)
    full = sprint(io -> showerror(io, e, bt))
    lim = sprint(io -> showerror(IOContext(io, :stacktrace_types_limited => Ref(false), :displaysize => (50, 120)), e, bt))
    head = split(full, "Stacktrace:")[1]
    for (name, s) in (("REPL", lim), ("full", full))
        ls = split(s, '\n')
        println("== $tag, $name: $(length(ls)) lines, $(sizeof(s)) bytes, frames $(count(l -> occursin(r"^\s*\[\d+\]", l), ls)); message before the trace $(sizeof(head)) bytes")
    end
    write(joinpath(@__DIR__, "$(tag)_full.txt"), full); write(joinpath(@__DIR__, "$(tag)_limited.txt"), lim)
end
lorenz!(du, u, p, t) = (du[1] = p[1] * (u[2] - u[1]); du[2] = u[1] * (p[2] - u[3]) - u[2]; du[3] = u[1] * u[2] - p[3] * u[3]; nothing)
const cache = zeros(3)
lorenz_cached!(du, u, p, t) = (cache .= u; lorenz!(du, cache, p, t))
p = [10.0, 28.0, 8 / 3]
report("implicit_dualcache", () -> solve(ODEProblem(lorenz_cached!, [1.0, 0.0, 0.0], (0.0, 1.0), p), Base.loaded_modules[only(k for k in keys(Base.loaded_modules) if k.name == "OrdinaryDiffEqRosenbrock")].Rodas5()))

