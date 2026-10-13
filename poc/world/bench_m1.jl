# M1 costs: steady state per element, and making a new type usable in a fresh session.
#   julia --startup-file=no --project=poc/world/env poc/world/bench_m1.jl
using TraitWorld, Columns, Printf
const JL = Base.julia_cmd()
const ENVDIR = joinpath(@__DIR__, "env")

struct ViaImpl; cols::Vector{Vector{Float64}}; end            # projection onto the library's representation
@implement ColTable ViaImpl project(t) = t.cols
struct ViaOwn; cols::Vector{Vector{Float64}}; end             # same behaviour, dynamic operations of its own
@implement ColTable ViaOwn dynamic begin
    project(t) = t.cols
    ncols(r) = length(r)
    col(r, i) = r[i]
    value(r, i, j) = r[i][j]
end
function plain_total(cols::Vector{Vector{Float64}}, len::Int)
    s = 0.0
    for i in 1:length(cols), j in 1:len
        s += cols[i][j]
    end
    s
end
const SINK = Ref(0.0)
function best(f, args...; reps)
    f(args...)
    minimum(1:7) do _
        acc = 0.0
        t = @elapsed for _ in 1:reps; acc += f(args...); end
        SINK[] += acc
        t / reps
    end
end
println("steady state, total(t, len) over 4 columns (ns per call | per element)")
for len in (16, 4096)
    cols = [rand(len) for _ in 1:4]
    reps = len == 16 ? 200_000 : 2_000
    tp = best(plain_total, cols, len; reps)
    tv = best(total, cols, len; reps)                 # the representation itself, through the entry
    ti = best(total, ViaImpl(cols), len; reps)
    to = best(total, ViaOwn(cols), len; reps)
    @printf("  len %4d: plain %9.1f | representation %9.1f (%.2f×) | projection %9.1f (%.2f×) | dynamic %9.1f (%.2f×)   per element: %.2f | %.2f | %.2f | %.2f\n",
            len, 1e9tp, 1e9tv, tv / tp, 1e9ti, ti / tp, 1e9to, to / tp, 1e9tp / 4len, 1e9tv / 4len, 1e9ti / 4len, 1e9to / 4len)
end

const CASES = [
    ("projection onto the library's representation", """
        struct NewT; cols::Vector{Vector{Float64}}; end
        @implement ColTable NewT project(t) = t.cols
        x = NewT([[1.0, 2.0], [3.0, 4.0]])"""),
    ("dynamic operations at the library's representation", """
        struct NewT; cols::Vector{Vector{Float64}}; end
        @implement ColTable NewT dynamic begin
            project(t) = t.cols
            ncols(r) = length(r)
            col(r, i) = r[i]
            value(r, i, j) = r[i][j]
        end
        x = NewT([[1.0, 2.0], [3.0, 4.0]])"""),
    ("own representation with an implementation", """
        struct NewT; base::Vector{Float64}; n::Int; end
        @implement ColTable{NewT} begin
            ncols(r) = r.n
            col(r, i) = r.base .* i
            value(r, i, j) = r.base[j] * i
        end
        x = NewT([1.0, 2.0], 2)"""),
]
println("\na fresh session: define the type, implement, first call of colmean, colrange, total (ms)")
for (label, code) in CASES
    script = """
    using TraitWorld, Columns
    Base.cumulative_compile_timing(true)
    c0 = Base.cumulative_compile_time_ns()[1]; t0 = time_ns()
    include_string(Main, $(repr(code)))
    t1 = time_ns()
    colmean(x, 1); colrange(x, 2); total(x, 2)
    t2 = time_ns(); c2 = Base.cumulative_compile_time_ns()[1]
    print((t1 - t0) / 1e6, " ", (t2 - t1) / 1e6, " ", (c2 - c0) / 1e6)
    """
    out = read(`$JL --startup-file=no --project=$ENVDIR -e $script`, String)
    a, b, c = parse.(Float64, split(out))
    @printf("  %-52s implement %7.1f | first calls %7.1f | of which compiling %7.1f\n", label, a, b, c)
end
