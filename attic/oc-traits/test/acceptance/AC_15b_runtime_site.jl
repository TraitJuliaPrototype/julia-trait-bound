# AC-15b (new; facts §4.2/§5 — the run-time-site shape at unit scale, the G2
# property in one frame): an abstract call in marked code answers `Any` with
# ZERO dispatch edges at the site, clears nortsite, and a LATER METHOD AT THE
# SITE IS FOLLOWED WITHOUT RECOMPILATION: the CI's world bounds are untouched
# while its value moves (dynamic dispatch in the caller's world).
include("ac_util.jl")

dyn15b(x) = 1.0
rb15b(v::Vector{Any}) = dyn15b(v[1])
mark!(rb15b)

@assert rb15b(Any[1]) == 1.0
ci = only([c for c in all_cis(rb15b) if c.min_world > 0])
w_before = ci.max_world
@assert ci.rettype === Any "the site's result is not typed: $(ci.rettype)"
@assert !Compiler.decode_effects(ci.ipo_purity_bits).nortsite "the site clears nortsite"
nopair = !any(1:length(ci.edges)-1) do i
    s = ci.edges[i]
    s isa DataType && s.name === Tuple.name && s.types[1] === typeof(dyn15b)
end
@assert nopair "zero dispatch edges at the run-time site: $(collect(ci.edges))"

dyn15b(s::Symbol) = 2.0                       # a later method at the site's function

@assert rb15b(Any[:a]) == 2.0 "the later method is followed"
@assert ci.max_world === w_before "without invalidating the CI: $w_before -> $(ci.max_world)"
@assert ci.rettype === Any
cis_after = [c for c in all_cis(rb15b) if c.min_world > 0]
@assert cis_after == [ci] "no recompilation happened (one CI, the same object)"

ac_finish(@__FILE__)
