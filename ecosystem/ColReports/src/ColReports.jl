"""
ColReports — second-tier region package: ops composing ColStats ops, in all
three cross-region lowerings so they can be compared head-to-head:

  * `report`     — statically-wired imports (the faked-native lowering)
  * `report_dyn` — dynamic op-registry calls (the honest Rung-1 lowering)
  * `report_fc`  — `@full_compile` + static wiring (the optimization ceiling)

All three share the same body.
"""
module ColReports

using TraitRegions, ColTables, ColStats
using PrecompileTools: @compile_workload

export report, report_dyn, report_fc

@region ColTable [ColStats.colmean, ColStats.colstd, ColStats.summarize, ColStats.colrange] begin
    function report(t)
        n = ncols(t)::Int
        acc = summarize(t)
        for i in 1:n
            acc += colmean(t, i) - colstd(t, i) + colrange(t, i)
        end
        acc
    end

    @full_compile function report_fc(t)
        n = ncols(t)::Int
        acc = summarize(t)
        for i in 1:n
            acc += colmean(t, i) - colstd(t, i) + colrange(t, i)
        end
        acc
    end
end

@region ColTable begin
    function report_dyn(t)
        n = ncols(t)::Int
        acc = summarize(t)
        for i in 1:n
            acc += colmean(t, i) - colstd(t, i) + colrange(t, i)
        end
        acc
    end
end


struct _PCDummy
    cols::Vector{Vector{Float64}}
end

@seal ColTable _PCDummy begin
    project(t) = t.cols
    ncols(r)   = length(r)
    col(r, i)  = r[i]
end

@compile_workload begin
    d = _PCDummy([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
    report(d); report_dyn(d); report_fc(d)
    precompile_seal(ColTable, _PCDummy)
end

end
