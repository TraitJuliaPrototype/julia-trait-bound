# Does a second loss closure / a second callback closure recompile the solver? Stock SciML, one session.
using OrdinaryDiffEq
const FD = Base.require(Base.PkgId(Base.UUID("f6369f11-7733-5829-9624-2563aa707210"), "ForwardDiff"))
macro t(label, ex)
    quote
        local s = time(); local r = $(esc(ex)); local e = time() - s
        println(rpad($label, 58), round(e, digits = 3), " s"); r
    end
end
lorenz!(du, u, p, t) = (du[1] = p[1] * (u[2] - u[1]); du[2] = u[1] * (p[2] - u[3]) - u[2]; du[3] = u[1] * u[2] - p[3] * u[3]; nothing)
p = [10.0, 28.0, 8 / 3]; u0 = [1.0, 0.0, 0.0]; ts = (0.0, 1.0)
prob = ODEProblem(lorenz!, u0, ts, p)
@t "Tsit5 warm-up" solve(prob, Tsit5())
loss1(q) = sum(solve(remake(prob; p = q, u0 = eltype(q).(prob.u0)), Tsit5(); saveat = 0.5)[end])
loss2(q) = sum(abs2, solve(remake(prob; p = q, u0 = eltype(q).(prob.u0)), Tsit5(); saveat = 0.5)[end])
@t "gradient, loss1 (first)" FD.gradient(loss1, p)
@t "gradient, loss2 (new closure, same shapes)" FD.gradient(loss2, p)
cbA = DiscreteCallback((u, t, i) -> t > 0.5, i -> (i.u[1] += 1.0))
cbB = DiscreteCallback((u, t, i) -> t > 0.7, i -> (i.u[2] += 1.0))
@t "DiscreteCallback A (first)" solve(prob, Tsit5(); callback = cbA)
@t "DiscreteCallback B (new closures, same kind)" solve(prob, Tsit5(); callback = cbB)
@t "callbacks A and B together (CallbackSet)" solve(prob, Tsit5(); callback = CallbackSet(cbA, cbB))
