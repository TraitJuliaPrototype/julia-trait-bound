# Concrete mode in TraitWorld: the abstract field three trait modules below a hot loop.
#   julia --project=poc/world/concrete/env -e 'using Pkg; Pkg.precompile()'    # shows the build-time warning
#   julia --startup-file=no --project=poc/world/concrete/env poc/world/concrete/run.jl
using TraitWorld, CTop, CBottom, Printf
using Base.CoreLogging: with_logger, SimpleLogger
log = IOBuffer()
v = rand(10^6)
with_logger(SimpleLogger(log)) do
    scaled_sum(v, Config(0.5)); scaled_sum_typed(v, TypedConfig(0.5))
end
println("warnings at first use in a new session: ", count("Warning", String(take!(log))))
best(f) = minimum(@elapsed(f()) for _ in 1:5)
ta = best(() -> scaled_sum(v, Config(0.5)))
tc = best(() -> scaled_sum_typed(v, TypedConfig(0.5)))
@printf("abstract field: %.2f ms (%.1f ns/element) | typed field: %.2f ms (%.2f ns/element) | %.0f×\n",
        1e3ta, 1e9ta / 10^6, 1e3tc, 1e9tc / 10^6, ta / tc)
W = TraitWorld
sig = Tuple{typeof(scaled_sum), typeof(W.TObj((W.View{Series}(W.Impl{()}(), v),))), Config}
t = @elapsed fs = check_concrete(sig)
@printf("check_concrete: %d finding(s), %.0f ms\n", length(fs), 1e3t)
println(sprint(W._print_findings, :scaled_sum, "Series at Vector{Float64}", fs))
