# The abstract field three layers below a hot loop: what it costs, and what
# concrete mode reports. Fresh process after the packages are precompiled:
#   julia --project=poc/concrete/env -e 'using Pkg; Pkg.precompile()'   # shows the build-time warning
#   julia --startup-file=no --project=poc/concrete/env poc/concrete/run.jl
using CTop, CBottom, TraitRegions, Printf
using Base.CoreLogging: with_logger, SimpleLogger

# 1. the check ran when CTop was built; a session that uses it is not warned again
log = IOBuffer()
sig = Signal(rand(10^6))
with_logger(SimpleLogger(log)) do
    scaled_sum(sig, Config(0.5)); CTop.scaled_sum_typed(sig, TypedConfig(0.5))
end
println("warnings at first use in a new session: ", count("Warning", String(take!(log))))

# 2. the cliff: the same loop, abstract vs concrete field, 10^6 elements
best(f) = minimum(@elapsed(f()) for _ in 1:5)
ta = best(() -> scaled_sum(sig, Config(0.5)))
tc = best(() -> CTop.scaled_sum_typed(sig, TypedConfig(0.5)))
@printf("abstract field: %.2f ms (%.1f ns/element) | typed field: %.2f ms (%.2f ns/element) | %.0f×\n",
        1e3ta, 1e9ta / 10^6, 1e3tc, 1e9tc / 10^6, ta / tc)

# 3. the same report on demand, for tests and CI
t = @elapsed r = check_concrete(Series)
@printf("check_concrete(Series): %d op(s) with findings, %.0f ms\n", length(r), 1e3t)
for ((op, R), fs) in r
    println(sprint(TraitRegions._print_findings, op, R, fs))
end
