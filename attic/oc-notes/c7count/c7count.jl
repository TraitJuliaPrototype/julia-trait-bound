# C7-count experiment (oc-notes, plan M0): the dispatch-invalidation volume of defining a
# bounded method on an open set, under the two C7 placements. Review M2 / decision P3.
#
#     jl --name NAME julia-1.13/julia --startup-file=no --project=<env> c7count.jl <label> <path-to-bounded.tsv> <pkg> [<pkg> …]
#
# For every function `f` with a bounded method (from U5's `<label>-bounded.tsv`), enumerate the
# cached specializations (MethodInstances, one dispatch entry per tuple) of all its methods and
# look at the bounded position p (after typeof):
#
#   N  specializations seen (the trait's own worker entries excluded -> M)
#   A  what the per-match-flag placement invalidates when the bounded method is defined:
#      specializations at a type that could still be or has been a member at p — everything
#      except a never-member kind (exploration §3.3's "not a final non-member", read per U7:
#      a concrete Base type can receive a membership later, so only Core's kinds are excluded)
#   B  what C7-in-jl_type_morespecific (review M2) reaches: specializations of the methods
#      *declared* `::Any` at p; plus the typemap "no method" backedges, not enumerable from
#      Julia (noted)
#   C  specializations whose type at p is a *member* of one of f's sets: genuine re-dispatch
#   K  specializations at a never-member kind (Core's DataType/Union/…/builtins/closures/memory,
#      U7's list): untouched by either rule
#   M  the trait's own worker specializations (TObj/CObj at p)
#   L  methods of f that lose METHOD_SIG_LATEST_ONLY (declared type at p is Any, non-concrete,
#      or a member — an intersecting method under membership)
#
# If <label>-hypo-show.tsv sits beside the census file, the same counts are made for the
# hypothetical `Base.show(::IO, ::X)` (position 2 of Base.show) over every set it names:
# U5's zero-hit census keeps the real bounded functions small; this is the stress case E-259
# counted guards for.
#
# Resolution: names are mostly bare (the census's `function` column); try them as (sub)module
# or global paths from every root seen so far — Main, Base, Core, TraitWorld, the row's
# function_owner, the row's defining_module. `A+B` in a bound is a tuple of sets: a member of
# the pair is a member of all its parts.
using TraitWorld
const TW = TraitWorld

label = ARGS[1]
tsv = abspath(ARGS[2])
for p in ARGS[3:end]
    Core.eval(Main, :(using $(Symbol(p))))
end
const OUT = get(ENV, "C7_OUT", dirname(@__FILE__))

# ---- self-check: Base.specializations finds all cached specializations ----
function selfcheck()
    g(x) = 1
    g(1); g(""); g(1.0)
    m = only(methods(g))
    n = 0
    for mi in Base.specializations(m)
        mi isa Core.MethodInstance || continue
        n += 1
    end
    n == 3 || error("selfcheck: found $n of 3 specializations")
end
selfcheck()

# ---- helpers ----
const WORKERS = Set{Symbol}((:TObj, :CObj))
function is_never_member(T)
    T === Any && return false
    (T isa Union || T isa UnionAll) && return true
    T isa DataType || return false          # TypeVar and friends: treat as could-join
    T.name.module === Core && (
        T.name.name === :DataType || T.name.name === :UnionAll || T.name.name === :Union ||
        T.name.name === :Module || T.name.name === :TypeVar || T.name.name === :TypeofBottom ||
        T.name.name === :Builtin || T.name.name === :OpaqueClosure ||
        T.name.name === :GenericMemory || T.name.name === :GenericMemoryRef ||
        T.name.name === :CoreModule) && return true
    T <: Core.OpaqueClosure && return true
    T <: Core.Builtin && return true
    return false
end
const ROOTS = Module[Main, Base, Core, TW]
function addroot(sym::AbstractString)
    s = String(sym)
    (isempty(s) || s == "false" || s == "true") && return
    top = Symbol(split(s, '.')[1])
    m = try
        getglobal(Main, top)
    catch
        try
            getproperty(Core, top)
        catch
            return
        end
    end
    m isa Module && m ∉ ROOTS && push!(ROOTS, m)
    return
end
parts_of(spec) = try
    s = String(spec)
    isempty(s) ? Symbol[] : Symbol.(split(s, '.'))
catch
    Symbol[]
end
function findfrom(parts, r::Module)
    v = r
    for p in parts
        isdefined(v, p) || return nothing
        v = getglobal(v, p)
    end
    v
end
function findtype(spec)::Type
    parts = parts_of(spec)
    isempty(parts) && return Union{}
    for r in ROOTS
        v = findfrom(parts, r)
        v isa Type && return v
    end
    # maybe the last part is missing a module qualification and sits in a root directly
    length(parts) > 1 && (v = findtype(string(parts[end]))) !== Union{} && return v
    Union{}
end
function findfunc(spec, extra::Vector{Module})
    parts = parts_of(spec)
    isempty(parts) && return (nothing, nothing, nothing)
    for r in [extra..., ROOTS...]
        v = findfrom(parts, r)
        v isa Function && return (r, parts[end], v)
    end
    if length(parts) > 1
        short = parts[end]
        for r in [extra..., ROOTS...]
            v = findfrom([short], r)
            v isa Function && return (r, short, v)
        end
    end
    (nothing, nothing, nothing)
end
# a bound is a tuple (conjunct) of sets; membership means member of every part
ismember(T, conjunct::Vector{Type}) = try
    T isa Type && isconcretetype(T) && all(X -> TW.conforms(T, X), conjunct)
catch
    false
end
declared(m, p) = try
    sig = m.sig
    sig = sig isa UnionAll ? Base.unwrap_unionall(sig) : sig
    sig isa DataType && length(sig.parameters) >= p + 1 ? sig.parameters[p+1] : nothing
catch
    nothing
end
function atpos(mi::Core.MethodInstance, p)
    try
        st = mi.specTypes
        st = st isa UnionAll ? Base.unwrap_unionall(st) : st
        st isa DataType && length(st.parameters) >= p + 1 ? st.parameters[p+1] : nothing
    catch
        nothing
    end
end

# ---- count a (function, position, bounds) group into counters ----
function count_group(fn, pos, conjuncts::Vector{Vector{Type}})
    N = A = B = C = K = M = L = 0
    for m in methods(fn)
        d = declared(m, pos)
        d === nothing && continue
        base = d isa TypeVar ? getfield(d, :ub) : d
        worker = base isa DataType && base.name.name in WORKERS
        if !worker
            loses = d === Any || (d isa Type && !isconcretetype(d)) ||
                    any(cj -> ismember(d, cj), conjuncts)
            loses && (L += 1)
        end
        for mi in Base.specializations(m)
            mi isa Core.MethodInstance || continue
            if worker
                M += 1
                continue
            end
            N += 1
            t = atpos(mi, pos)
            if t isa Type && any(cj -> ismember(t, cj), conjuncts)
                C += 1
                A += 1
            elseif t isa Type && is_never_member(t)
                K += 1
            else
                A += 1
            end
            d === Any && (B += 1)
        end
    end
    (N, A, B, C, K, M, L)
end

# ---- read the bounded census ----
struct BRow
    fn::Function
    where::String
    pos::Int
    conjuncts::Vector{Vector{Type}}
    setnames::Vector{String}
    foreign::Bool
end
addroot("TraitWorld")
rows = BRow[]
open(tsv) do io
    lines = readlines(io)
    isempty(lines) && return
    hdr = split(lines[1], '\t')
    cfn = findfirst(==("function"), hdr)
    cb = findfirst(==("bounds"), hdr)
    cf = findfirst(==("foreign_fn"), hdr)
    cdm = findfirst(==("defining_module"), hdr)
    cow = findfirst(==("function_owner"), hdr)
    (cfn === nothing || cb === nothing || cf === nothing) && error("bad tsv header")
    for line in lines[2:end]
        cols = split(line, '\t')
        length(cols) < length(hdr) && continue
        fname = String(cols[cfn])
        dm = cdm === nothing ? "" : String(cols[cdm])
        ow = cow === nothing ? "" : String(cols[cow])
        addroot(dm); addroot(ow)
        extra = Module[]
        for s in (dm, ow)
            isempty(s) && continue
            p = parts_of(s)
            for r in ROOTS
                v = findfrom(p, r)
                v isa Module && (push!(extra, v); break)
            end
        end
        fnmod, fnnm, fn = findfunc(fname, extra)
        fn === nothing && (println("UNRESOLVED function: $fname (in $dm)"); continue)
        where = fnmod === nothing ? fname : "$(fnmod).$(fnnm)"
        for m in eachmatch(r"(\d+):([^\s]+)", String(cols[cb]))
            pos = parse(Int, m.captures[1])
            parts = String.(split(String(m.captures[2]), '+'))
            Ts = Vector{Type}(undef, 0)
            for s in parts
                T = findtype(s)
                if T === Union{}
                    println("PARTIAL sets for $fname: $parts")
                else
                    push!(Ts, T)
                end
            end
            isempty(Ts) && (println("NO SET RESOLVED for $fname ($parts)"); continue)
            push!(rows, BRow(fn, where, pos, Vector{Type}[Ts], parts, cols[cf] == "true"))
        end
    end
end

groups = Dict{Tuple{Function,Int},Vector{BRow}}()
for r in rows
    push!(get!(Vector{BRow}, groups, (r.fn, r.pos)), r)
end

# ---- count ----
out = open(joinpath(OUT, "$(label)-c7.tsv"), "w")
println(out, "function\tposition\tsets\tforeign\tN\tA\tB\tC\tK\tM\tL")
tot = zeros(Int, 8)
for ((fn, pos), rs) in sort(collect(groups); by = g -> (string(g[1][1]), g[1][2]))
    setnames = unique(reduce(vcat, [r.setnames for r in rs]))
    conjuncts = unique(reduce(vcat, [r.conjuncts for r in rs]))
    foreign = any(r.foreign for r in rs)
    (N, A, B, C, K, M, L) = count_group(fn, pos, conjuncts)
    name = rs[1].where
    println(out, name, "\t", pos, "\t", join(setnames, ","), "\t", foreign, "\t", N, "\t", A, "\t", B, "\t", C, "\t", K, "\t", M, "\t", L)
    println(rpad(name, 56), " p=$pos N=$N A=$A B=$B C=$C K=$K M=$M L=$L")
    tot .+= (N, A, B, C, K, M, L, 1)
    flush(out)
end
close(out)
println("== $label: $(tot[8]) (function, position) pairs; N=$(tot[1]); A(flag)=$(tot[2]); B(morespec, ::Any methods only)=$(tot[3]); C(members)=$(tot[4]); K(never-member)=$(tot[5]); M(workers)=$(tot[6]); L(fast-path)=$(tot[7])")
println("(B excludes the typemap \"no method\" backedges — per (function, tuple), not enumerable from Julia; the flag placement's A includes them.)")

# ---- the hypothetical Base.show stress case ----
hypo = joinpath(dirname(tsv), "$(label)-hypo-show.tsv")
isfile(hypo) || (println("no hypo file: $hypo"); exit(0))
hs = open(hypo) do io
    lines = readlines(io)
    hdr = split(lines[1], '\t')
    cs = findfirst(==("set"), hdr)
    [String(split(line, '\t')[cs]) for line in lines[2:end] if !isempty(line)]
end
outh = open(joinpath(OUT, "$(label)-hypo-show-c7.tsv"), "w")
println(outh, "set\tN\tA\tB\tC\tK\tM\tL")
th = zeros(Int, 8)
for s in hs
    T = findtype(s)
    T === Union{} && (println("HYPO UNRESOLVED set: $s"); continue)
    addroot(s)
    (N, A, B, C, K, M, L) = count_group(Base.show, 2, [Type[T]])
    println(outh, s, "\t", N, "\t", A, "\t", B, "\t", C, "\t", K, "\t", M, "\t", L)
    println("hypo-show  ", rpad(s, 48), " N=$N A=$A B=$B C=$C K=$K M=$M L=$L")
    th .+= (N, A, B, C, K, M, L, 1)
end
close(outh)
println("== $label hypo-show: $(th[8]) sets; N=$(th[1]) A=$(th[2]) B=$(th[3]) C=$(th[4]) K=$(th[5]) L=$(th[7])")
