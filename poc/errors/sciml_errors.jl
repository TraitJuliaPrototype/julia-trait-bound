# Two classic SciML failures, printed as the REPL prints them (types limited) and in full.
using OrdinaryDiffEq
const FD = Base.require(Base.PkgId(Base.UUID("f6369f11-7733-5829-9624-2563aa707210"), "ForwardDiff"))

function report(tag, f)
    e, bt = try
        f(); (nothing, nothing)
    catch err
        (err, catch_backtrace())
    end
    e === nothing && (println("== $tag: no error"); return)
    full = sprint(io -> showerror(io, e, bt))
    lim = sprint(io -> showerror(IOContext(io, :stacktrace_types_limited => Ref(false), :displaysize => (50, 120)), e, bt))
    for (name, s) in (("as the REPL shows it", lim), ("in full", full))
        ls = split(s, '\n')
        println("== $tag, $name: $(length(ls)) lines, $(sizeof(s)) bytes, longest line $(maximum(length, ls)) chars, frames $(count(l -> occursin(r"^\s*\[\d+\]", l), ls))")
    end
    write(joinpath(@__DIR__, "$(tag)_full.txt"), full)
    write(joinpath(@__DIR__, "$(tag)_limited.txt"), lim)
end

# 1. The model reads parameters the problem was never given.
function lorenz!(du, u, p, t)
    du[1] = p[1] * (u[2] - u[1]); du[2] = u[1] * (p[2] - u[3]) - u[2]; du[3] = u[1] * u[2] - p[3] * u[3]
end
report("noparams", () -> solve(ODEProblem(lorenz!, [1.0, 0.0, 0.0], (0.0, 1.0)), Tsit5()))

# 2. A hand-made Float64 cache meets dual numbers when the loss is differentiated.
const cache = zeros(3)
function lorenz_cached!(du, u, p, t)
    cache .= u                       # Float64 buffer: cannot hold Duals
    lorenz!(du, cache, p, t)
end
prob = ODEProblem(lorenz_cached!, [1.0, 0.0, 0.0], (0.0, 1.0), [10.0, 28.0, 8 / 3])
loss(p) = sum(solve(remake(prob; p, u0 = eltype(p).(prob.u0)), Tsit5(); saveat = 0.5)[end])
report("dualcache", () -> FD.gradient(loss, [10.0, 28.0, 8 / 3]))

# the type of the integrator a stack frame carries
integ = init(prob, Tsit5())
T = string(typeof(integ))
println("typeof(integrator): $(sizeof(T)) chars, $(count(==('{'), T)) type-parameter lists")
write(joinpath(@__DIR__, "integrator_type.txt"), T)
