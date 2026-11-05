# Gate M3 §3 (R-1's companion, R-6 context): a facts frame's record carries the
# new edge kinds where the corresponding decisions happened — InlineIdentity at
# an inline, ResultEdge at an emitted call, LayoutIdentity at a field read —
# while plain invalidation through the code edges is UNCHANGED (the records are
# classification; store_backedges registers nothing through them).
include("util.jl")
import Compiler

struct P3R
    f::Int
end

inl3(x::Int) = xor(x, 0x0f)                     # tiny: inlined
@noinline emit3(x::Int) = (x * 3) ⊻ 0x01        # stays emitted
lay3(p::P3R) = p.f                              # getfield at a concrete DataType

function rec3(x::Int, p::P3R)
    inl3(x) + emit3(x) + lay3(p)
end
for f in (inl3, emit3, lay3, rec3)
    Compiler.mark_facts!(f)
end
@assert rec3(0x21, P3R(4)) == xor(0x21, 0x0f) + xor(0x21 * 3, 0x01) + 4

ci = only(all_cis(rec3))
has(T) = any(e -> isa(e, T), ci.edges)
@assert has(Compiler.InlineIdentity) "inlined callee recorded an InlineIdentity: $(collect(ci.edges))"
@assert has(Compiler.ResultEdge) "emitted callee recorded a ResultEdge: $(collect(ci.edges))"
@assert has(Compiler.LayoutIdentity) "field read recorded a LayoutIdentity: $(collect(ci.edges))"

# the record kinds registered NO backedges: the iterator-skip hunk (R-6/B) — a
# plain redefinition of the inlined callee still moves rec3's answer (the code
# edge still invalidates; nothing about the record broke the mechanism)
inl3(x::Int) = xor(x, 0x00)                     # redefined: identity changes
@assert rec3(0x21, P3R(4)) == 0x21 + xor(0x21 * 3, 0x01) + 4 "redefinition of the inlined callee is followed (plain invalidation intact)"

# and a run-time site in a marked frame records NO dispatch pair for that site
# (the pair-walk counts pairs at site sigs mentioning sink3):
sink3(a) = a
function rec3r(v::Vector{Any}, x::Int)
    sink3(v[1])
    inl3(x)
end
Compiler.mark_facts!(rec3r)
@assert rec3r(Any[1], 0x21) == 0x21
ci2 = only(all_cis(rec3r))
@assert !any(1:length(ci2.edges)-1) do i
    ci2.edges[i] isa Type && occursin("sink3", string(ci2.edges[i]))
end "the Any-position site recorded no dispatch pair: $(collect(ci2.edges))"

println("m3_record_kinds: OK")
