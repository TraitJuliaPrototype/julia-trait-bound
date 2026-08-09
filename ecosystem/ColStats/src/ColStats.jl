"""
ColStats — first-tier region package: stats ops over `ColTable`.
Workers precompile into this package's pkgimage for the canonical
representation.
"""
module ColStats

using TraitRegions, ColTables
using PrecompileTools: @compile_workload

export colmean, colstd, meanall, summarize, colrange

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

    colmean(t, i::Int) = _mean(col(t, i)::Vector{Float64})
    colstd(t, i::Int)  = _std(col(t, i)::Vector{Float64})

    function meanall(t)
        n = ncols(t)::Int
        acc = 0.0
        for i in 1:n
            acc += _mean(col(t, i)::Vector{Float64})
        end
        acc / max(n, 1)
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

    function colrange(t, i::Int)
        c = col(t, i)::Vector{Float64}
        lo = c[1]; hi = c[1]
        @inbounds for k in eachindex(c)
            x = c[k]
            lo = ifelse(x < lo, x, lo); hi = ifelse(x > hi, x, hi)
        end
        hi - lo
    end
end


struct _PCDummy
    cols::Vector{Vector{Float64}}
end

@compile_workload begin
    d = _PCDummy([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
    @seal ColTable _PCDummy begin
        project(t) = t.cols
        ncols(r)   = length(r)
        col(r, i)  = r[i]
    end
    colmean(d, 1); colstd(d, 2); meanall(d); summarize(d); colrange(d, 1)
    precompile_seal(ColTable, _PCDummy)
end

end
