# P2 cache perf: per-call cost of sealed dynamic dispatch vs plain.
module RegionCode
    const WIT = Base.RefValue{Any}(sort)
    _medw(c::Vector{Float64}) = (cs = WIT[](c)::Vector{Float64}; cs[(length(cs) + 1) ÷ 2])
end
sealed_on() = ccall(:jl_set_sealed_mode, Int8, (Int8,), Int8(1))
sealed_off(old) = ccall(:jl_set_sealed_mode, Int8, (Int8,), old)
data = [5.0, 1.0, 4.0, 2.0, 3.0]
function bench_plain(n, data)
    acc = 0.0
    t0 = time_ns()
    for _ in 1:n; acc += RegionCode._medw(data); end
    ((time_ns() - t0) / n, acc)
end
function bench_sealed(n, data)
    acc = 0.0
    old = sealed_on()
    t0 = time_ns()
    for _ in 1:n; acc += RegionCode._medw(data); end
    dt = (time_ns() - t0) / n
    sealed_off(old)
    (dt, acc)
end
bench_plain(1000, data); bench_sealed(1000, data)   # warm (universe unset: sealed inactive)
const UNIVERSE = Any[Base, Core, Base.Compiler, RegionCode]
ccall(:jl_set_universe_filter, Cvoid, (Any,), UNIVERSE)
p, _ = bench_plain(200_000, data)
s, _ = bench_sealed(200_000, data)
ccall(:jl_set_universe_filter, Cvoid, (Ptr{Cvoid},), C_NULL)
println("plain: ", round(p, digits=1), " ns/call   sealed(cached): ", round(s, digits=1),
        " ns/call   overhead: ", round(s - p, digits=1), " ns (", round(s/p, digits=2), "x)")
