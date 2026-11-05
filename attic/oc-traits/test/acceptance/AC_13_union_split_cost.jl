# AC-13 (old G1.31, the behavior half; the is_fact_sig table half is pinned by
# gates/m3_policy_sites): unions in tuple arguments split by JULIA'S OWN COST
# (`unionsplitcost`: the product of the union lengths, the longest counted as
# 2): one union of eight splits (cost 2), two unions of three do not (cost 6),
# two unions of two do (cost 4). Split sites get per-split (sig, callee) fact
# edges and a concrete rettype; the non-split case is a run-time site: rettype
# Any, zero dispatch pairs at the callee, nortsite false. The old script's
# split-table asserts ride with M5 (deferral §E).
include("ac_util.jl")

const U8 = Union{Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64}
const U3 = Union{Int8, Int16, Int32}
const U2 = Union{Int8, Int16}

u13g(t) = 1                       # the callee: resolves per split case
u13g2(x, y) = 2

# (a) one union of eight inside a tuple argument: cost 2 => splits
a13(v::Vector{Any}) = (t = v[1]::Tuple{U8, Float64}; u13g(t))
ap13(v::Vector{Any}) = (t = v[1]::Tuple{U8, Float64}; u13g(t))
mark!(a13)
@assert a13(Any[(Int8(3), 1.0)]) == ap13(Any[(Int8(3), 1.0)]) == 1

# (b) two unions of three: cost 6 => no split => run-time site
b13(v::Vector{Any}) = (t = v[1]::Tuple{U3, U3}; u13g(t))
bp13(v::Vector{Any}) = (t = v[1]::Tuple{U3, U3}; u13g(t))
mark!(b13)
@assert b13(Any[(Int8(1), Int16(2))]) == bp13(Any[(Int8(1), Int16(2))]) == 1

# (c) two arguments, each a union of two: cost 4 => splits
c13(v::Vector{Any}) = (x = v[1]::Tuple{U2}; y = v[2]::Tuple{U2}; u13g2(x, y))
cp13(v::Vector{Any}) = (x = v[1]::Tuple{U2}; y = v[2]::Tuple{U2}; u13g2(x, y))
mark!(c13)
@assert c13(Any[(Int8(1),), (UInt8(2),)]) == cp13(Any[(Int8(1),), (UInt8(2),)]) == 2

pairs_at(f, sighead) = begin
    ci = only([c for c in all_cis(f) if c.min_world > 0])
    n = count(1:length(ci.edges)-1) do i
        s = ci.edges[i]
        s isa DataType && s.name === Tuple.name && s.types[1] === sighead &&
            (ci.edges[i+1] isa Core.MethodInstance || ci.edges[i+1] isa Core.CodeInstance)
    end
    ci, n
end

cia, na = pairs_at(a13, typeof(u13g))
@assert na == 8 "one-of-eight: 8 per-split (sig, callee) pairs, got $na: $(collect(cia.edges))"
@assert cia.rettype === Int "split site: concrete rettype, got $(cia.rettype)"
@assert Compiler.decode_effects(cia.ipo_purity_bits).nortsite "split site records every dispatch"

cib, nb = pairs_at(b13, typeof(u13g))
@assert nb == 0 "the non-split case records no pair at u13g: $(collect(cib.edges))"
@assert cib.rettype === Any "run-time site: rettype Any, got $(cib.rettype)"
@assert !Compiler.decode_effects(cib.ipo_purity_bits).nortsite "run-time site clears nortsite"

cic, nc = pairs_at(c13, typeof(u13g2))
@assert nc == 4 "two-of-two: 4 per-split pairs, got $nc: $(collect(cic.edges))"
@assert cic.rettype === Int

ac_finish(@__FILE__)
