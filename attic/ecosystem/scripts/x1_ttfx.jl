# X1 — ecosystem TTFX: fresh session, never-seen user type, composed op
# (`report` = summarize + per-column mean/std/range across two packages).
# Fresh process per mode:  julia +1.11.7 --startup-file=no --project=. x1_ttfx.jl <mode>
# modes: static (faked-native wiring) | dyn (honest Rung-1) | fc (ceiling) | plain (twin)
using ColStats, ColReports, PlainStack, TraitRegions, ColTables
using Printf

struct MyTable
    cols::Vector{Vector{Float64}}
end

const mode = ARGS[1]
t = MyTable([rand(200) for _ in 1:6])

if mode == "plain"
    reg = @timed @eval begin
        PlainStack.getcol(t::MyTable, i::Int) = t.cols[i]
        PlainStack.ncols_direct(t::MyTable) = length(t.cols)
    end
    fc = @timed report_p(t)
else
    reg = @timed TraitRegions.register!(ColTable, MyTable,
        (project = x -> x.cols, ncols = r -> length(r), col = (r, i) -> r[i]))
    fc = mode == "static" ? (@timed report(t)) :
         mode == "dyn"    ? (@timed report_dyn(t)) :
                            (@timed report_fc(t))
end

@printf("X1 mode=%-7s register: %6.1f ms compile   first-report: %6.1f ms compile (%6.1f ms total)\n",
        mode, reg.compile_time * 1e3, fc.compile_time * 1e3, fc.time * 1e3)
