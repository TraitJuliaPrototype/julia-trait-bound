# M2: Base capability traits, declared conformance, generic implementations.
#   julia --startup-file=no --project=poc/world/env poc/world/m2_basetraits.jl
using TraitWorld, BaseTraits, Columns, Printf
const TW = TraitWorld

# --- 1. survey: declared, conforming, or merely having the methods --------------------
types = Any[Vector{Float64}, Vector{Vector{Float64}}, Matrix{Float64}, UnitRange{Int}, StepRange{Int,Int},
            Base.OneTo{Int}, LinRange{Float64,Int}, BitVector, typeof(view([1.0, 2.0], 1:2)),
            NTuple{3,Int}, Tuple{Int,Float64}, String, SubString{String}, Dict{Int,Float64}, Set{Int},
            Int, Float64, Char, Pair{Int,Int}, @NamedTuple{a::Int, b::Int}, Nothing]
structural(X, R) = all(op -> all(N -> hasmethod(TW._opfn(X, op), Tuple{R, TW._declared_args(X, op, R, N).parameters...}),
                                 TW._arities(X, op)), TW._ops(X))
mark(declared, conforms, has) = declared ? (conforms ? "declared" : "DECLARED, FAILS") : (has ? "accidental" : "-")
println(rpad("representation", 60), rpad("HasLength", 18), rpad("Iterable", 18), "Indexable")
for R in types
    cells = String[]
    for X in (HasLength, Iterable, Indexable)
        d = TW.witness(X, R) !== nothing
        c = d ? isempty(TW.conformance_problems(X, R, TW._ops(X))) : false
        push!(cells, rpad(mark(d, c, structural(X, R)), 18))
    end
    println(rpad(string(R), 60), join(cells))
end
println("""
  declared: conformance declared (here for Base's families) and confirmed by inference at the declared types
  accidental: not declared, but the methods exist: structural conformance would accept it""")

# --- 2. a subtype that breaks Base's AbstractVector contract ------------------------------
struct Broken <: AbstractVector{Float64}; n::Int; end
Base.size(b::Broken) = (b.n,)                       # forgets getindex
@trait_module module Firsts
using TraitWorld, BaseTraits
first_of(t::Indexable) = t[1]
end
println("\nBroken <: AbstractVector{Float64}, without getindex:")
println("  problems found by inference: ", TW.conformance_problems(Indexable, Broken, (:getindex,)))
e_plain = try Broken(2)[1]; nothing catch e; e end
e_trait = try Firsts.first_of(Broken(2)); nothing catch e; e end
println("  plain Julia:   ", typeof(e_plain), ": ", sprint(showerror, e_plain)[1:min(end, 90)])
println("  trait module:  ", typeof(e_trait), ": ", sprint(showerror, e_trait)[1:min(end, 90)])
println("  identical error: ", typeof(e_plain) === typeof(e_trait) && sprint(showerror, e_plain) == sprint(showerror, e_trait))

# --- 3. ColTable follows from the capability traits --------------------------------------
struct Wrapped; v::Vector{Vector{Float64}}; end         # a user representation, Indexable only
@implement HasLength{Wrapped} begin length(r) = length(r.v) end
@implement Indexable{Wrapped} begin getindex(r, i) = r.v[i] end
Base.eltype(::Type{Wrapped}) = Vector{Float64}
cols = [rand(4) for _ in 1:3]
println("\nColTable through the generic implementation:")
for x in (cols, Tuple(cols), Wrapped(cols), view(cols, 1:3))
    println("  ", rpad(string(typeof(x)), 70), "colmean = ", round(colmean(x, 1), digits = 4),
            "   witness: ", nameof(typeof(TW.witness(ColTable, typeof(x)))))
end
println("  Int: ", try colmean(42, 1) catch e; typeof(e) end, " (has length and getindex, not declared)")

# --- 4. generic against specific, steady state -------------------------------------------
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
println("\ntotal(t, len) over 4 columns: specific implementation against generic (ns per call)")
for len in (16, 4096)
    c4 = [rand(len) for _ in 1:4]
    reps = len == 16 ? 200_000 : 2_000
    ts = best(total, c4, len; reps)
    tt = best(total, Tuple(c4), len; reps)
    tw = best(total, Wrapped(c4), len; reps)
    @printf("  len %4d: specific %9.1f | generic, NTuple %9.1f (%.2f×) | generic, user Indexable %9.1f (%.2f×)\n",
            len, 1e9ts, 1e9tt, tt / ts, 1e9tw, tw / ts)
end

# --- 5. cost of a conformance check ---------------------------------------------------------
println("\nconformance check of Indexable (µs): first, then warm")
for R in (Vector{Int}, UnitRange{Int}, Tuple{Float64,Float64,Float64})
    t1 = @elapsed TW.conformance_problems(Indexable, R, TW._ops(Indexable))
    t2 = @elapsed TW.conformance_problems(Indexable, R, TW._ops(Indexable))
    @printf("  %-40s %9.1f %9.1f\n", string(R), 1e6t1, 1e6t2)
end
