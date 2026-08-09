# E2-lite — the headline: fresh session, never-seen types. How much compilation
# does conformance + the first operations trigger, per lowering?  (M0 gate b)
#
# Two never-seen types per run:
#   Plain — realistic conformer: witnesses are trivial accessors.
#   Lazy  — bespoke witness (materializes columns via broadcast): the witness
#           body itself is genuinely new code every path must compile.
# Four ops: colmean, colstd, meanall, summarize (heavy body).
# All timed sections are straight-line top-level expressions so each sees the
# current world (no invokelatest, which would swamp the measurement).
#
# Run each mode in a FRESH process:
#   for m in erased dyn fc direct; julia +1.11.7 --startup-file=no --project=. e2_fresh_ttfx.jl $m
using M0Spike
using Printf

struct Plain
    cols::ColR
end

struct Lazy
    base::Vector{Float64}
    n::Int
end

const mode = ARGS[1]
tp = Plain([rand(100) for _ in 1:8])
tl = Lazy(rand(100), 8)

report(label, reg, fc) =
    @printf("mode=%-6s %-5s  register: %7.1f ms compile   first-4-ops: %7.1f ms compile (%7.1f ms total)\n",
            mode, label, reg.compile_time * 1e3, fc.compile_time * 1e3, fc.time * 1e3)

if mode == "erased"
    regP = @timed register_seal!(Plain; project = t -> t.cols, ncols = r -> length(r), col = (r, i) -> r[i])
    fcP  = @timed (colmean(tp, 3) + colstd(tp, 2) + meanall(tp) + summarize(tp))
    report("Plain", regP, fcP)
    regL = @timed register_seal!(Lazy; project = t -> ColR([[Float64(t.n)], t.base]),
                                 ncols = r -> Int(r[1][1]), col = (r, i) -> r[2] .* Float64(i))
    fcL  = @timed (colmean(tl, 3) + colstd(tl, 2) + meanall(tl) + summarize(tl))
    report("Lazy", regL, fcL)
elseif mode == "dyn"
    regP = @timed register_dyn!(Plain; project = t -> t.cols, ncols = r -> length(r), col = (r, i) -> r[i])
    fcP  = @timed (colmean_dyn(tp, 3) + colstd_dyn(tp, 2) + meanall_dyn(tp) + summarize_dyn(tp))
    report("Plain", regP, fcP)
    regL = @timed register_dyn!(Lazy; project = t -> ColR([[Float64(t.n)], t.base]),
                                ncols = r -> Int(r[1][1]), col = (r, i) -> r[2] .* Float64(i))
    fcL  = @timed (colmean_dyn(tl, 3) + colstd_dyn(tl, 2) + meanall_dyn(tl) + summarize_dyn(tl))
    report("Lazy", regL, fcL)
elseif mode == "fc"
    regP = @timed register_fc!(Plain; project = t -> t.cols, ncols = r -> length(r), col = (r, i) -> r[i])
    fcP  = @timed (colmean_fc(tp, 3) + colstd_fc(tp, 2) + meanall_fc(tp) + summarize_fc(tp))
    report("Plain", regP, fcP)
    regL = @timed register_fc!(Lazy; project = t -> ColR([[Float64(t.n)], t.base]),
                               ncols = r -> Int(r[1][1]), col = (r, i) -> r[2] .* Float64(i))
    fcL  = @timed (colmean_fc(tl, 3) + colstd_fc(tl, 2) + meanall_fc(tl) + summarize_fc(tl))
    report("Lazy", regL, fcL)
elseif mode == "direct"
    regP = @timed @eval begin
        M0Spike.getcol(t::Plain, i::Int) = t.cols[i]
        M0Spike.ncols_direct(t::Plain) = length(t.cols)
    end
    fcP = @timed (colmean_direct(tp, 3) + colstd_direct(tp, 2) + meanall_direct(tp) + summarize_direct(tp))
    report("Plain", regP, fcP)
    regL = @timed @eval begin
        M0Spike.getcol(t::Lazy, i::Int) = t.base .* Float64(i)
        M0Spike.ncols_direct(t::Lazy) = t.n
    end
    fcL = @timed (colmean_direct(tl, 3) + colstd_direct(tl, 2) + meanall_direct(tl) + summarize_direct(tl))
    report("Lazy", regL, fcL)
end
