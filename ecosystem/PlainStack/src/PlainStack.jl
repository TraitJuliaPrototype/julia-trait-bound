"""
PlainStack — the plain twin: the same stats + report ops written as ordinary
generic Julia dispatching on the user type through `getcol`/`ncols_direct`
overloads. Same bodies as ColStats/ColReports; monomorphizes per user type.
"""
module PlainStack

using PrecompileTools: @compile_workload

export getcol, ncols_direct,
       colmean_p, colstd_p, meanall_p, summarize_p, colrange_p, report_p

function getcol end
function ncols_direct end

_mean(c::Vector{Float64}) = begin
    s = 0.0
    @inbounds @simd for k in eachindex(c)
        s += c[k]
    end
    s / max(length(c), 1)
end

_std(c::Vector{Float64}) = begin
    n = 0; mean = 0.0; m2 = 0.0
    @inbounds for k in eachindex(c)
        n += 1
        d = c[k] - mean
        mean += d / n
        m2 += d * (c[k] - mean)
    end
    n < 2 ? 0.0 : sqrt(m2 / (n - 1))
end

_summary_of(c::Vector{Float64}, hist::Vector{Int}) = begin
    m = _mean(c); s = _std(c)
    lo = c[1]; hi = c[1]
    @inbounds for k in eachindex(c)
        x = c[k]
        lo = ifelse(x < lo, x, lo); hi = ifelse(x > hi, x, hi)
    end
    w = hi > lo ? (hi - lo) : 1.0
    fill!(hist, 0)
    @inbounds for k in eachindex(c)
        hist[1 + min(15, floor(Int, 16 * (c[k] - lo) / w))] += 1
    end
    cs = sort(c)
    m + s + lo + hi + cs[max(1, length(cs) ÷ 2)] + Float64(maximum(hist))
end

colmean_p(t, i::Int) = _mean(getcol(t, i)::Vector{Float64})
colstd_p(t, i::Int)  = _std(getcol(t, i)::Vector{Float64})

function meanall_p(t)
    n = ncols_direct(t)::Int
    acc = 0.0
    for i in 1:n
        acc += _mean(getcol(t, i)::Vector{Float64})
    end
    acc / max(n, 1)
end

function summarize_p(t)
    n = ncols_direct(t)::Int
    acc = 0.0
    hist = zeros(Int, 16)
    for i in 1:n
        c = getcol(t, i)::Vector{Float64}
        isempty(c) && continue
        acc += _summary_of(c, hist)
    end
    acc
end

function colrange_p(t, i::Int)
    c = getcol(t, i)::Vector{Float64}
    lo = c[1]; hi = c[1]
    @inbounds for k in eachindex(c)
        x = c[k]
        lo = ifelse(x < lo, x, lo); hi = ifelse(x > hi, x, hi)
    end
    hi - lo
end

function report_p(t)
    n = ncols_direct(t)::Int
    acc = summarize_p(t)
    for i in 1:n
        acc += colmean_p(t, i) - colstd_p(t, i) + colrange_p(t, i)
    end
    acc
end

struct _PCDummy
    cols::Vector{Vector{Float64}}
end
getcol(t::_PCDummy, i::Int) = t.cols[i]
ncols_direct(t::_PCDummy) = length(t.cols)

@compile_workload begin
    d = _PCDummy([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
    report_p(d); meanall_p(d)
end

end
