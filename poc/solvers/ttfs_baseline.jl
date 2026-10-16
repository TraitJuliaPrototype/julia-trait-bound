# Baseline time-to-first-solve for the solver exploration: one fresh session, stock SciML.
t0 = time(); using OrdinaryDiffEq; tload = time() - t0
const ROS = Base.loaded_modules[only(k for k in keys(Base.loaded_modules) if k.name == "OrdinaryDiffEqRosenbrock")]
const FD = Base.require(Base.PkgId(Base.UUID("f6369f11-7733-5829-9624-2563aa707210"), "ForwardDiff"))
println("load OrdinaryDiffEq: ", round(tload, digits = 2), " s")
macro t(label, ex)
    quote
        local s = time(); local r = $(esc(ex)); local e = time() - s
        println(rpad($label, 58), round(e, digits = 3), " s")
        r
    end
end
lorenz!(du, u, p, t) = (du[1] = p[1] * (u[2] - u[1]); du[2] = u[1] * (p[2] - u[3]) - u[2]; du[3] = u[1] * u[2] - p[3] * u[3]; nothing)
rossler!(du, u, p, t) = (du[1] = -u[2] - u[3]; du[2] = u[1] + p[1] * u[2]; du[3] = p[2] + u[3] * (u[1] - p[3]); nothing)
p = [10.0, 28.0, 8 / 3]; u0 = [1.0, 0.0, 0.0]; ts = (0.0, 1.0)
@t "Tsit5, lorenz!, Vector{Float64} (first)" solve(ODEProblem(lorenz!, u0, ts, p), Tsit5())
@t "Tsit5, lorenz! again" solve(ODEProblem(lorenz!, u0, ts, p), Tsit5())
@t "Tsit5, rossler! (new function type)" solve(ODEProblem(rossler!, u0, ts, [0.2, 0.2, 5.7]), Tsit5())
@t "Tsit5, lorenz!, Vector{Float32} (new state type)" solve(ODEProblem(lorenz!, Float32.(u0), Float32.(ts), Float32.(p)), Tsit5())
cb1 = DiscreteCallback((u, t, i) -> t > 0.5, i -> (i.u[1] += 1.0))
@t "Tsit5 + DiscreteCallback (new callback type)" solve(ODEProblem(lorenz!, u0, ts, p), Tsit5(); callback = cb1)
cb2 = ContinuousCallback((u, t, i) -> u[1] - 5.0, i -> (i.p[1] = 9.0))
@t "Tsit5 + ContinuousCallback (new callback type)" solve(ODEProblem(lorenz!, u0, ts, p), Tsit5(); callback = cb2)
@t "Rodas5, lorenz! (first)" solve(ODEProblem(lorenz!, u0, ts, p), ROS.Rodas5())
@t "Rodas5, lorenz! again" solve(ODEProblem(lorenz!, u0, ts, p), ROS.Rodas5())
@t "Rodas5, rossler! (new function type)" solve(ODEProblem(rossler!, u0, ts, [0.2, 0.2, 5.7]), ROS.Rodas5())
prob = ODEProblem(lorenz!, u0, ts, p)
loss(q) = sum(solve(remake(prob; p = q, u0 = eltype(q).(prob.u0)), Tsit5(); saveat = 0.5)[end])
@t "ForwardDiff.gradient through Tsit5 (first)" FD.gradient(loss, p)
@t "ForwardDiff.gradient through Tsit5 again" FD.gradient(loss, p)
for (name, alg, kw) in (("Tsit5", Tsit5(), (;)), ("Tsit5 + DiscreteCallback", Tsit5(), (; callback = cb1)), ("Rodas5", ROS.Rodas5(), (;)))
    T = string(typeof(init(prob, alg; kw...)))
    println("typeof(integrator) $(rpad(name, 26)) $(sizeof(T)) chars, $(count(==('{'), T)) parameter lists")
end
