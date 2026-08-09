# E1/E6-lite — per-call overhead of the erased path (M0 gate a).
# Run: julia +1.11.7 --project=. e1_overhead.jl
using M0Spike, BenchmarkTools, Printf

struct T1
    cols::ColR
end
mkdata(len) = T1([rand(len) for _ in 1:8])

register_seal!(T1; project = t -> t.cols, ncols = r -> length(r), col = (r, i) -> r[i])
register_dyn!(T1;  project = t -> t.cols, ncols = r -> length(r), col = (r, i) -> r[i])
register_fc!(T1;   project = t -> t.cols, ncols = r -> length(r), col = (r, i) -> r[i])
M0Spike.getcol(t::T1, i::Int) = t.cols[i]
M0Spike.ncols_direct(t::T1) = length(t.cols)

println("# op | column length | direct ns | erased ns | dyn ns | fc ns | ratios erased/dyn vs direct")
for len in (16, 256, 4096)
    t = mkdata(len)
    # correctness cross-check
    @assert colmean(t, 3) == colmean_dyn(t, 3) == colmean_fc(t, 3) == colmean_direct(t, 3)
    @assert meanall(t) == meanall_dyn(t) == meanall_fc(t) == meanall_direct(t)
    for (name, fs) in (("colmean", (colmean_direct, colmean, colmean_dyn, colmean_fc)),
                       ("colstd",  (colstd_direct,  colstd,  colstd_dyn,  colstd_fc)))
        d = @belapsed $(fs[1])($t, 3)
        e = @belapsed $(fs[2])($t, 3)
        y = @belapsed $(fs[3])($t, 3)
        f = @belapsed $(fs[4])($t, 3)
        @printf("%-8s len=%-5d  direct %8.1f  erased %8.1f  dyn %8.1f  fc %8.1f  ratios %.2f / %.2f\n",
                name, len, d * 1e9, e * 1e9, y * 1e9, f * 1e9, e / d, y / d)
    end
    d = @belapsed meanall_direct($t)
    e = @belapsed meanall($t)
    y = @belapsed meanall_dyn($t)
    f = @belapsed meanall_fc($t)
    @printf("%-8s len=%-5d  direct %8.1f  erased %8.1f  dyn %8.1f  fc %8.1f  ratios %.2f / %.2f\n",
            "meanall", len, d * 1e9, e * 1e9, y * 1e9, f * 1e9, e / d, y / d)
end
