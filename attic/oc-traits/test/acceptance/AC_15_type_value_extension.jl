# AC-15 (old G2.1): an unrelated module EXTENDS a function called on type
# values — the marked CI stays valid (`max_world == typemax(UInt)` before and
# after the extension): kind positions are not facts (§1a, D1's Keyed/kinds
# rule), the call is a run-time site, and a run-time site records nothing to
# invalidate — G2's "a load that brings neither invalidates none", at unit
# scale. The value still moves, dynamically, in both modes.
include("ac_util.jl")

module Pk15
    trt(::Type{T}) where {T} = false
    trt(::Type{Int}) = true
end

clf15(T) = Pk15.trt(T)                    # the call site: T::DataType — a kind, not a fact
kt15(v::Vector{DataType}) = count(clf15, v)
mark!(clf15)
mark!(kt15)

r0 = kt15(DataType[Int, Float64])
@assert r0 == 1 "before the extension: $r0"
ci = only([c for c in all_cis(kt15) if c.min_world > 0])
cic = only([c for c in all_cis(clf15) if c.min_world > 0])
@assert ci.max_world === typemax(UInt) "marked caller CI is unbounded: $(ci.max_world)"
@assert cic.max_world === typemax(UInt) "the run-time-site frame itself is unbounded: $(cic.max_world)"

module Qk15
    struct QT end
    Pk15.trt(::Type{QT}) = true           # the unrelated extension (a pirate at Pk15.trt)
end

r1 = kt15(DataType[Int, Float64, Qk15.QT])
p1 = count(T -> Pk15.trt(T), DataType[Int, Float64, Qk15.QT])
@assert r1 == p1 == 2 "G2.1: the extension is followed dynamically: $r1 vs plain $p1"
@assert ci.max_world === typemax(UInt) "the extension invalidated nothing: $(ci.max_world)"
@assert cic.max_world === typemax(UInt) "neither at the site frame: $(cic.max_world)"
@assert only([c for c in all_cis(clf15) if c.min_world > 0]) === cic "no recompilation happened"

ac_finish(@__FILE__)
