# AC-18 (new; §8 — the membership seam): a marked caller at a member compiled
# AFTER the declare uses M2's §0 query-world override; pin (i) the dispatch
# (sig, callee) edge at the concrete member signature, (ii) ci.min_world >=
# entry.min_world, (iii) a MembershipEdge carrying the entry, and (iv) the
# non-member abstract query as a run-time site (no pair, rettype Any, nortsite
# false — later members answered dynamically).
include("ac_util.jl")
using Traits

@trait S18
g18(::S18) = :set
struct M18 end
e18 = @implement M18 S18
mk18(m::M18) = g18(m)
mk18b(v::Vector{Any}) = g18(v[1])           # abstract query over the set function
mark!(mk18)
mark!(mk18b)

@assert mk18(M18()) === :set
@assert mk18b(Any[M18()]) === :set "the abstract query answers dynamically"

ci = only([c for c in all_cis(mk18) if c.min_world > 0])
haspair = any(1:length(ci.edges)-1) do i
    s = ci.edges[i]
    s isa DataType && s === Tuple{typeof(g18), M18} &&
        (ci.edges[i+1] isa Core.MethodInstance || ci.edges[i+1] isa Core.CodeInstance)
end
@assert haspair "dispatch edge at the concrete member sig: $(collect(ci.edges))"
@assert ci.min_world >= e18.min_world "world bound above the declare: $(ci.min_world) >= $(e18.min_world)"
fes = [e for e in ci.edges if isa(e, Compiler.MembershipEdge)]
@assert length(fes) == 1 "exactly one MembershipEdge: $(collect(ci.edges))"
@assert fes[1].entry === e18 "the edge carries the entry: $(fes[1].entry)"

cib = only([c for c in all_cis(mk18b) if c.min_world > 0])
@assert cib.rettype === Any "abstract query over the set: rettype Any, got $(cib.rettype)"
@assert !any(1:length(cib.edges)-1) do i
    s = cib.edges[i]
    s isa DataType && s.name === Tuple.name && s.types[1] === typeof(g18)
end "the abstract query records no dispatch pair: $(collect(cib.edges))"
@assert !Compiler.decode_effects(cib.ipo_purity_bits).nortsite "nortsite false at the set-abstract site"

# a member declared LATER is followed at the run-time site without recompilation
struct N18 end
@implement N18 S18
@assert mk18b(Any[N18()]) === :set "the later member answers dynamically"
@assert cib.max_world === typemax(UInt) "bounds untouched at the run-time site: $(cib.max_world)"

ac_finish(@__FILE__)
