# Gate M2 item 1 (query side, §9's M2-real shape): the set-in-set match shape
# through methods(f, (B,))'s match records (B ⊆ X composes for a member of B),
# pinned across worlds; the abstract-member carry — M2's documented remainder —
# asserted only for SOUNDNESS (the query fronts and the compiled answer agree).
using Traits
include("util.jl")

@trait XQ
@trait BQ <: XQ                 # subtype link: becomes an entry too (setsuper hook)
struct MQ end
wq(::XQ) = :set
wq(::Int) = :int
wqv(x) = wq(x)                  # module-level (world-old) call shape

@assert isempty(methods(wq, (MQ,))) "no match before the declaration"
w_pre = curworld()
@implement MQ BQ

ms = methods(wq, (MQ,))
@assert any(m -> m.sig.parameters[2] === XQ, ms) "match record names XQ through BQ ⊆ XQ"
hidden = try
    Base.invoke_in_world(w_pre, wqv, MQ())
    false                     # answered in the old world: wrongly visible
catch e
    e isa MethodError         # no method matches there: the match is invisible
end
@assert hidden "the pre-declaration world keeps no match (worlds pin)"
@assert wq(MQ()) === :set "dispatch through the composed chain"
@assert wq(1) === :int "unrelated queries unaffected (I1)"

# the abstract-member carry: M2's remainder (deviations.md) — pin consistency,
# not the answer itself
@trait AQ
abstract type AMem end
struct SubA <: AMem end
wq2(::AQ) = :set
wq2(::Any) = :any
@implement AMem AQ

isa_ans = SubA() isa AQ
m_ans = any(mm -> mm.sig.parameters[2] === AQ, methods(wq2, (SubA,)))
println("m2_abstract_query abstract-carry: isa=", isa_ans, " methods-match=", m_ans)
@assert isa_ans == m_ans "soundness: the isa front and the methods front agree"
r = wq2(SubA())
@assert (isa_ans && r === :set) || (!isa_ans && r === :any) "the compiled answer agrees with the fronts"

println("m2_abstract_query: OK")
