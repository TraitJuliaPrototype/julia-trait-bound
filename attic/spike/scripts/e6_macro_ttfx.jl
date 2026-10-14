# E6 — fresh-session TTFX on the MACRO surface (validates that TraitRegions
# preserves the M0 dyn-path numbers). Fresh process per mode:
#   julia +1.11.7 --startup-file=no --project=. e6_macro_ttfx.jl region
#   julia +1.11.7 --startup-file=no --project=. e6_macro_ttfx.jl direct
using RegionDemo, TraitRegions
using Printf

struct Plain
    cols::Vector{Vector{Float64}}
end

const mode = ARGS[1]
tp = Plain([rand(100) for _ in 1:8])

if mode == "region"
    reg = @timed @seal ColTable Plain begin
        project(t) = t.cols
        ncols(r)   = length(r)
        col(r, i)  = r[i]
    end
    fc = @timed (colmean(tp, 3) + colstd(tp, 2) + meanall(tp) + summarize(tp))
elseif mode == "direct"
    reg = @timed @eval begin
        RegionDemo.getcol(t::Plain, i::Int) = t.cols[i]
        RegionDemo.ncols_direct(t::Plain) = length(t.cols)
    end
    fc = @timed (colmean_direct(tp, 3) + colstd_direct(tp, 2) + meanall_direct(tp) + summarize_direct(tp))
end

@printf("mode=%-7s register: %6.1f ms compile   first-4-ops: %6.1f ms compile (%6.1f ms total)\n",
        mode, reg.compile_time * 1e3, fc.compile_time * 1e3, fc.time * 1e3)
