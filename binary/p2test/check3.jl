# Final experiment: invalidation scoping. Universe set BEFORE the churn
# package loads; its method definition then cannot kill universe code.
using User, Helper
v = [1.0, 2.0, 3.0]
r0 = User.run_all(v)                     # warm; also the pre-churn ground truth
const UNIVERSE = Any[Base, Core, Base.Compiler, Main, Helper, User]
ccall(:jl_set_universe_filter, Cvoid, (Any,), UNIVERSE)
using LoadChurn                          # defines Helper.inner(::Float64) — outside the universe
s = @timed User.run_all(v)
ccall(:jl_set_universe_filter, Cvoid, (Ptr{Cvoid},), C_NULL)
println("scoped-invalidation: compile ", round(s.compile_time * 1e3, digits = 1),
        " ms, recompile ", round(s.recompile_time * 1e3, digits = 1),
        " ms, semantics preserved: ", s.value == r0)
ok = s.compile_time + s.recompile_time < 0.05 && s.value == r0
println(ok ? "INVALIDATION SCOPING: PASS — universe code survives load-order churn by construction" :
             "INVALIDATION SCOPING: inspect")
