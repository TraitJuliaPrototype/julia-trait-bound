"""
M0Spike — hand-written (no macros) spike of the trait-region design core.

One trait ("ColTable"-like), one representation `ColR = Vector{Vector{Float64}}`,
three chunky operations, three lowerings of each:

  * erased path   — entry + worker; worker keyed on `R` only, witnesses called
                    through FunctionWrappers (the design default).
  * fc path       — same worker body, witnesses passed as a raw NamedTuple of
                    function singletons ⇒ Julia monomorphizes per witness set
                    (the `@full_compile` opt-out).
  * direct path   — ordinary generic Julia: ops dispatch on the user type `T`
                    through `getcol`/`ncols_direct` overloads (the baseline).

The PrecompileTools workload compiles the erased workers into the pkgimage so a
fresh session with a never-seen type can hit precompiled native code (claim C2).
"""
module M0Spike

using FunctionWrappers: FunctionWrapper
using PrecompileTools: @compile_workload

export ColR, register_seal!, register_fc!, register_dyn!,
       colmean, colstd, meanall, summarize,
       colmean_fc, colstd_fc, meanall_fc, summarize_fc,
       colmean_dyn, colstd_dyn, meanall_dyn, summarize_dyn,
       colmean_direct, colstd_direct, meanall_direct, summarize_direct,
       getcol, ncols_direct

# ---------------------------------------------------------------------------
# Representation and seal machinery (erased path)
# ---------------------------------------------------------------------------

"The shared representation: a table is a vector of Float64 columns."
const ColR = Vector{Vector{Float64}}

"Interior witness table — signatures mention only `ColR`, never the user type."
struct WTable
    ncols::FunctionWrapper{Int,Tuple{ColR}}
    col::FunctionWrapper{Vector{Float64},Tuple{ColR,Int}}
end

"Seal = commitment point: projection to `ColR` plus the witness table."
struct Seal
    project::FunctionWrapper{ColR,Tuple{Any}}
    w::WTable
end

const SEALS = IdDict{Type,Seal}()

# Registration and entries deliberately do NOT specialize on the user type or
# the witness closures: one compiled instance each, ever, cached in the
# pkgimage. A new type pays only for compiling its own witness bodies.
function register_seal!(T::Type; @nospecialize(project), @nospecialize(ncols), @nospecialize(col))
    haskey(SEALS, T) && error("duplicate seal for $T")
    SEALS[T] = Seal(FunctionWrapper{ColR,Tuple{Any}}(project),
                    WTable(FunctionWrapper{Int,Tuple{ColR}}(ncols),
                           FunctionWrapper{Vector{Float64},Tuple{ColR,Int}}(col)))
    return nothing
end

@inline function seal_of(@nospecialize(t))
    s = get(SEALS, typeof(t), nothing)
    s === nothing && error(typeof(t), " is not sealed for ColTable")
    return s::Seal
end

# ---------------------------------------------------------------------------
# Worker bodies (shared textually across all three lowerings)
# ---------------------------------------------------------------------------
# Chunky bodies: each witness call returns a whole column; the loop work per
# indirect call is O(column length).

@inline function _mean(c::Vector{Float64})
    s = 0.0
    @inbounds @simd for k in eachindex(c)
        s += c[k]
    end
    return s / max(length(c), 1)
end

@inline function _std(c::Vector{Float64})
    # Welford's algorithm
    n = 0; mean = 0.0; m2 = 0.0
    @inbounds for k in eachindex(c)
        n += 1
        d = c[k] - mean
        mean += d / n
        m2 += d * (c[k] - mean)
    end
    return n < 2 ? 0.0 : sqrt(m2 / (n - 1))
end

"""
Heavy chunky body — stands in for a realistic region op whose compile cost is
worth sharing: per-column mean/std/extrema/16-bin histogram/sorted median,
folded into one Float64 so the return stays simple.
"""
@inline function _summarize(ncols_f, col_f, r)::Float64
    n = ncols_f(r)::Int
    acc = 0.0
    hist = zeros(Int, 16)
    for i in 1:n
        c = col_f(r, i)::Vector{Float64}
        isempty(c) && continue
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
        hmax = maximum(hist)
        cs = sort(c)
        med = cs[max(1, length(cs) ÷ 2)]
        acc += m + s + lo + hi + med + Float64(hmax)
    end
    return acc
end

# --- erased workers: keyed on (WTable, ColR) only — one instance, ever -------

@noinline colmean_worker(w::WTable, r::ColR, i::Int) = _mean(w.col(r, i))
@noinline colstd_worker(w::WTable, r::ColR, i::Int)  = _std(w.col(r, i))

@noinline function meanall_worker(w::WTable, r::ColR)
    n = w.ncols(r)
    tot = 0.0
    cnt = 0
    for i in 1:n
        c = w.col(r, i)
        @inbounds @simd for k in eachindex(c)
            tot += c[k]
        end
        cnt += length(c)
    end
    return tot / max(cnt, 1)
end

# --- per-T entries: tiny, all real work behind the worker barrier ------------

function colmean(@nospecialize(t), i::Int)
    s = seal_of(t)
    colmean_worker(s.w, s.project(t), i)
end

function colstd(@nospecialize(t), i::Int)
    s = seal_of(t)
    colstd_worker(s.w, s.project(t), i)
end

function meanall(@nospecialize(t))
    s = seal_of(t)
    meanall_worker(s.w, s.project(t))
end

# One instance: WTable fields are concretely-typed FunctionWrappers, so
# _summarize specializes exactly once for this path.
@noinline summarize_worker(w::WTable, r::ColR) = _summarize(w.ncols, w.col, r)

function summarize(@nospecialize(t))
    s = seal_of(t)
    summarize_worker(s.w, s.project(t))
end

# ---------------------------------------------------------------------------
# "dyn" erased path: witness table with plain `Function` fields.
# Witness calls are dynamic dispatches (no inference edge, no cfunction), so
# registration compiles nothing wrapper-related; per-call cost is one dynamic
# dispatch per witness call — amortized by chunky bodies. Return types are
# asserted at the call site to keep the worker body type-stable.
# ---------------------------------------------------------------------------

struct WTableDyn
    ncols::Function
    col::Function
end

struct SealDyn
    project::Function
    w::WTableDyn
end

const SEALS_DYN = IdDict{Type,SealDyn}()

function register_dyn!(T::Type; @nospecialize(project), @nospecialize(ncols), @nospecialize(col))
    haskey(SEALS_DYN, T) && error("duplicate dyn seal for $T")
    SEALS_DYN[T] = SealDyn(project, WTableDyn(ncols, col))
    return nothing
end

@inline function seal_dyn_of(@nospecialize(t))
    s = get(SEALS_DYN, typeof(t), nothing)
    s === nothing && error(typeof(t), " is not dyn-sealed for ColTable")
    return s::SealDyn
end

@noinline colmean_worker_dyn(w::WTableDyn, r::ColR, i::Int) = _mean(w.col(r, i)::Vector{Float64})
@noinline colstd_worker_dyn(w::WTableDyn, r::ColR, i::Int)  = _std(w.col(r, i)::Vector{Float64})

@noinline function meanall_worker_dyn(w::WTableDyn, r::ColR)
    n = w.ncols(r)::Int
    tot = 0.0
    cnt = 0
    for i in 1:n
        c = w.col(r, i)::Vector{Float64}
        @inbounds @simd for k in eachindex(c)
            tot += c[k]
        end
        cnt += length(c)
    end
    return tot / max(cnt, 1)
end

function colmean_dyn(@nospecialize(t), i::Int)
    s = seal_dyn_of(t)
    colmean_worker_dyn(s.w, s.project(t)::ColR, i)
end

function colstd_dyn(@nospecialize(t), i::Int)
    s = seal_dyn_of(t)
    colstd_worker_dyn(s.w, s.project(t)::ColR, i)
end

function meanall_dyn(@nospecialize(t))
    s = seal_dyn_of(t)
    meanall_worker_dyn(s.w, s.project(t)::ColR)
end

# Body duplicated rather than routed through _summarize: passing the abstract
# `Function` fields as arguments would re-specialize the heavy body per closure
# type, silently destroying the sharing this path exists to provide.
@noinline function summarize_worker_dyn(w::WTableDyn, r::ColR)::Float64
    n = w.ncols(r)::Int
    acc = 0.0
    hist = zeros(Int, 16)
    for i in 1:n
        c = w.col(r, i)::Vector{Float64}
        isempty(c) && continue
        m = _mean(c)
        s = _std(c)
        lo = c[1]; hi = c[1]
        @inbounds for k in eachindex(c)
            x = c[k]
            lo = ifelse(x < lo, x, lo)
            hi = ifelse(x > hi, x, hi)
        end
        w2 = hi > lo ? (hi - lo) : 1.0
        fill!(hist, 0)
        @inbounds for k in eachindex(c)
            b = 1 + min(15, floor(Int, 16 * (c[k] - lo) / w2))
            hist[b] += 1
        end
        hmax = maximum(hist)
        cs = sort(c)
        med = cs[max(1, length(cs) ÷ 2)]
        acc += m + s + lo + hi + med + Float64(hmax)
    end
    return acc
end

function summarize_dyn(@nospecialize(t))
    s = seal_dyn_of(t)
    summarize_worker_dyn(s.w, s.project(t)::ColR)
end

# ---------------------------------------------------------------------------
# `@full_compile`-style path: same bodies, raw witnesses ⇒ per-T instances
# ---------------------------------------------------------------------------

const FC_WITNESSES = IdDict{Type,Any}()

function register_fc!(T::Type; @nospecialize(project), @nospecialize(ncols), @nospecialize(col))
    FC_WITNESSES[T] = (project = project, ncols = ncols, col = col)
    return nothing
end

@noinline colmean_worker_fc(w, r, i::Int) = _mean(w.col(r, i))
@noinline colstd_worker_fc(w, r, i::Int)  = _std(w.col(r, i))

@noinline function meanall_worker_fc(w, r)
    n = w.ncols(r)
    tot = 0.0
    cnt = 0
    for i in 1:n
        c = w.col(r, i)
        @inbounds @simd for k in eachindex(c)
            tot += c[k]
        end
        cnt += length(c)
    end
    return tot / max(cnt, 1)
end

function colmean_fc(t, i::Int)
    w = FC_WITNESSES[typeof(t)]
    colmean_worker_fc(w, w.project(t), i)
end

function colstd_fc(t, i::Int)
    w = FC_WITNESSES[typeof(t)]
    colstd_worker_fc(w, w.project(t), i)
end

function meanall_fc(t)
    w = FC_WITNESSES[typeof(t)]
    meanall_worker_fc(w, w.project(t))
end

@noinline summarize_worker_fc(w, r) = _summarize(w.ncols, w.col, r)

function summarize_fc(t)
    w = FC_WITNESSES[typeof(t)]
    summarize_worker_fc(w, w.project(t))
end

# ---------------------------------------------------------------------------
# Baseline: ordinary generic Julia, monomorphized per user type
# ---------------------------------------------------------------------------

"Overload per user type: `getcol(t, i)::Vector{Float64}`."
function getcol end

"Overload per user type: `ncols_direct(t)::Int`."
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

summarize_direct(t) = _summarize(ncols_direct, getcol, t)

# ---------------------------------------------------------------------------
# Precompile workload: put the erased workers (and entry/registry machinery)
# into the pkgimage. Wrapper pointers do not serialize, so all registry state
# is cleared afterwards; only compiled code survives — which is the point.
# ---------------------------------------------------------------------------

struct _PCDummy
    cols::ColR
end

@compile_workload begin
    d = _PCDummy([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
    register_seal!(_PCDummy;
        project = t -> t.cols,
        ncols   = r -> length(r),
        col     = (r, i) -> r[i])
    colmean(d, 1)
    colstd(d, 2)
    meanall(d)
    summarize(d)
    register_dyn!(_PCDummy;
        project = t -> t.cols,
        ncols   = r -> length(r),
        col     = (r, i) -> r[i])
    colmean_dyn(d, 1)
    colstd_dyn(d, 2)
    meanall_dyn(d)
    summarize_dyn(d)
    empty!(SEALS)
    empty!(SEALS_DYN)
    empty!(FC_WITNESSES)
end

end # module
