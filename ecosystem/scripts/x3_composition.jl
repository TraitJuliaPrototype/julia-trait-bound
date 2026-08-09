# X3 — steady-state cost of cross-region composition, all lowerings +
# hoisted-seal ceiling.  julia +1.11.7 --startup-file=no --project=. x3_composition.jl
using ColStats, ColReports, PlainStack, TraitRegions, ColTables, EagerTables
using BenchmarkTools, Printf

PlainStack.getcol(t::EagerTable, i::Int) = t.cols[i]
PlainStack.ncols_direct(t::EagerTable) = length(t.cols)

println("# report (summarize + 3 ops × ncols): ns/call, 6 columns")
for len in (16, 256, 4096)
    t = EagerTable([rand(len) for _ in 1:6])
    @assert report(t) == report_dyn(t) == report_fc(t) == report_p(t)
    s = TraitRegions.seal_of(ColTable, t)
    r = s.project(t)
    b_plain  = @belapsed report_p($t)
    b_static = @belapsed report($t)
    b_dyn    = @belapsed report_dyn($t)
    b_fc     = @belapsed report_fc($t)
    b_hoist  = @belapsed ColReports.var"report#worker"($(s.w), $r)     # entry overhead removed
    @printf("len=%-5d plain %9.1f | static %9.1f (%.2fx) | dyn %9.1f (%.2fx) | fc %9.1f (%.2fx) | hoisted-static %9.1f\n",
            len, b_plain*1e9, b_static*1e9, b_static/b_plain, b_dyn*1e9, b_dyn/b_plain,
            b_fc*1e9, b_fc/b_plain, b_hoist*1e9)
end
