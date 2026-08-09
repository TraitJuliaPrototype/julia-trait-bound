"""
RegionDemo — the M0 demo rebuilt on the TraitRegions macro surface.

A `ColTable` trait over representation `Vector{Vector{Float64}}`, a region
with the four M0 ops (colmean, colstd, meanall, summarize), and the ordinary
generic-Julia baseline (`*_direct` over per-type `getcol`/`ncols_direct`).
The precompile workload puts the region workers into the pkgimage.
"""
module RegionDemo

using TraitRegions
using PrecompileTools: @compile_workload

export ColTable,
       colmean, colstd, meanall, summarize,
       colmean_direct, colstd_direct, meanall_direct, summarize_direct,
       getcol, ncols_direct

@trait ColTable begin
    ncols(r)::Int
    col(r, i::Int)::Vector{Float64}
end

@region ColTable begin
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
        m = _mean(c)
        s = _std(c)
        lo = c[1]; hi = c[1]
        @inbounds for k in eachindex(c)
            x = c[k]
            lo = ifelse(x < lo, x, lo)
            hi = ifelse(x > hi, x, hi)
        end
        w = hi > lo ? (hi - lo) : 1.0
        fill!(hist, 0)
        @inbounds for k in eachindex(c)
            b = 1 + min(15, floor(Int, 16 * (c[k] - lo) / w))
            hist[b] += 1
        end
        cs = sort(c)
        med = cs[max(1, length(cs) ÷ 2)]
        m + s + lo + hi + med + Float64(maximum(hist))
    end

    colmean(t, i::Int) = _mean(col(t, i)::Vector{Float64})
    colstd(t, i::Int)  = _std(col(t, i)::Vector{Float64})

    function meanall(t)
        n = ncols(t)::Int
        tot = 0.0
        cnt = 0
        for i in 1:n
            c = col(t, i)::Vector{Float64}
            @inbounds @simd for k in eachindex(c)
                tot += c[k]
            end
            cnt += length(c)
        end
        tot / max(cnt, 1)
    end

    function summarize(t)
        n = ncols(t)::Int
        acc = 0.0
        hist = zeros(Int, 16)
        for i in 1:n
            c = col(t, i)::Vector{Float64}
            isempty(c) && continue
            acc += _summary_of(c, hist)
        end
        acc
    end
end

# --- ordinary generic-Julia baseline (monomorphizes per user type) ----------

function getcol end
function ncols_direct end

colmean_direct(t, i::Int) = _mean(getcol(t, i)::Vector{Float64})
colstd_direct(t, i::Int)  = _std(getcol(t, i)::Vector{Float64})

function meanall_direct(t)
    n = ncols_direct(t)::Int
    tot = 0.0
    cnt = 0
    for i in 1:n
        c = getcol(t, i)::Vector{Float64}
        @inbounds @simd for k in eachindex(c)
            tot += c[k]
        end
        cnt += length(c)
    end
    return tot / max(cnt, 1)
end

function summarize_direct(t)
    n = ncols_direct(t)::Int
    acc = 0.0
    hist = zeros(Int, 16)
    for i in 1:n
        c = getcol(t, i)::Vector{Float64}
        isempty(c) && continue
        acc += _summary_of(c, hist)
    end
    return acc
end

# --- precompile workload ----------------------------------------------------

struct _PCDummy
    cols::Vector{Vector{Float64}}
end

getcol(t::_PCDummy, i::Int) = t.cols[i]
ncols_direct(t::_PCDummy) = length(t.cols)

@compile_workload begin
    d = _PCDummy([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
    @seal ColTable _PCDummy begin
        project(t) = t.cols
        ncols(r)   = length(r)
        col(r, i)  = r[i]
    end
    colmean(d, 1); colstd(d, 2); meanall(d); summarize(d)
    colmean_direct(d, 1); colstd_direct(d, 2); meanall_direct(d); summarize_direct(d)
end

end # module
