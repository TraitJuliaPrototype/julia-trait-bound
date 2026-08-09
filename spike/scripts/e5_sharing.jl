# E1-lite — sharing / small nominal types (C1): 12 user types over one
# representation ⇒ 1 worker MethodInstance on the erased path, vs. per-T
# instances on the fc and direct paths.
# Run: julia +1.11.7 --project=. e5_sharing.jl
using M0Spike, MethodAnalysis

const N = 12
for k in 1:N
    S = Symbol("User", k)
    @eval begin
        struct $S
            cols::ColR
        end
        M0Spike.getcol(t::$S, i::Int) = t.cols[i]
        M0Spike.ncols_direct(t::$S) = length(t.cols)
    end
    T = @eval $S
    register_seal!(T; project = x -> x.cols, ncols = r -> length(r), col = (r, i) -> r[i])
    register_fc!(T;   project = x -> x.cols, ncols = r -> length(r), col = (r, i) -> r[i])
end

for k in 1:N
    t = Base.invokelatest(@eval($(Symbol("User", k))), [rand(50) for _ in 1:4])
    a = Base.invokelatest(colmean, t, 2)
    b = Base.invokelatest(colmean_fc, t, 2)
    c = Base.invokelatest(colmean_direct, t, 2)
    @assert a == b == c
    Base.invokelatest(colstd, t, 1); Base.invokelatest(colstd_fc, t, 1); Base.invokelatest(colstd_direct, t, 1)
    Base.invokelatest(meanall, t); Base.invokelatest(meanall_fc, t); Base.invokelatest(meanall_direct, t)
end

mi(f) = length(methodinstances(f))
println("MethodInstance counts after $N types × 3 ops:")
println("  erased workers:  colmean_worker=", mi(M0Spike.colmean_worker),
        "  colstd_worker=", mi(M0Spike.colstd_worker),
        "  meanall_worker=", mi(M0Spike.meanall_worker), "   (claim: 1 each)")
println("  fc workers:      colmean_worker_fc=", mi(M0Spike.colmean_worker_fc),
        "  colstd_worker_fc=", mi(M0Spike.colstd_worker_fc),
        "  meanall_worker_fc=", mi(M0Spike.meanall_worker_fc), "   (expect ~N each)")
println("  direct ops:      colmean_direct=", mi(colmean_direct),
        "  colstd_direct=", mi(colstd_direct),
        "  meanall_direct=", mi(meanall_direct), "   (expect ~N each)")
println("  per-T entries:   colmean=", mi(colmean), " colstd=", mi(colstd), " meanall=", mi(meanall),
        "   (tiny, per-T by design)")
