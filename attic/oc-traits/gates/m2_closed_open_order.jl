# Gate M2 item 2 (C7 in type_morespecific_, probe 3 flipped): at a position, a
# closed non-Any typename orders ABOVE an open one. Before C7 the Kind-vs-Col
# pair was unordered, the LATEST_ONLY fast path early-exited on the later set
# entry, and a member dispatched to the set method although its own chain
# method applied. Also pins: Any still loses to the set; the wrapper-erase and
# erased-Keyed orderings; invariant (container-parameter) positions unchanged.
using Traits
include("util.jl")

abstract type Sup3 end
abstract type Kind3 <: Sup3 end
struct Deep3 <: Kind3 end              # fully under the closed Kind3 chain

@trait Col3
w3(::Kind3) = :kind
w3(::Col3)  = :set
w3(::Sup3)  = :sup                     # even more general closed — must not win
let e = @implement Deep3 Col3
    @assert e isa Core.MembershipEntry
end

@assert (w3(Deep3()) === :kind) "closed chain method wins over the set method (probe 3)"

# type-level orderings (Base.morespecific reaches type_morespecific_ directly)
sig(t) = Tuple{typeof(w3), t}
@assert Base.morespecific(sig(Kind3), sig(Col3)) "closed beats open"
@assert !Base.morespecific(sig(Col3), sig(Kind3)) "…and not the other way"
@assert Base.morespecific(sig(Kind3), sig(Sup3)) && !Base.morespecific(sig(Sup3), sig(Kind3)) "closed-vs-closed untouched (vanilla chain rule: deeper chain wins)"
@assert Base.morespecific(sig(Col3), sig(Any)) "sets still beat Any (no C7 arm for Any)"

# the wrapper arms: Dynamic{X} erases strictly onto X; erased Keyed refines X
@assert Base.morespecific(sig(Core.Dynamic{Col3}), sig(Col3)) "Dynamic{X} over X"
@assert !Base.morespecific(sig(Col3), sig(Core.Dynamic{Col3})) "…not symmetric"
@assert Base.morespecific(sig(Core.Keyed{Col3, Nothing, Nothing}), sig(Col3)) "erased Keyed over X"
# (Keyed as the b-side erases only on the a-side per plan §2 — no pin beyond
# the partial order: Keyed-vs-Kind3 stays unordered, matching Col3-vs-Kind3's
# strictness only through the set itself.)

# invariant positions keep vanilla semantics: a set as a container parameter is
# not ordered against a closed one by C7 (arguments are invariant positions)
@assert !Base.morespecific(sig(Vector{Kind3}), sig(Vector{Col3})) "invariant: unordered stays unordered"
@assert !Base.morespecific(sig(Vector{Col3}), sig(Vector{Kind3})) "invariant: symmetric"

# abstract-member ordering unchanged (M1b behavior: the subtype probes order an
# abstract member against a set it joins; C7 must not contradict them)
@trait Abs3
abstract type AMem3 end
@implement AMem3 Abs3
w3b(::Abs3) = :set
@assert Base.morespecific(sig(Kind3), sig(Abs3)) "closed over an abstract-member set (agrees with the probes)"
@assert !Base.morespecific(sig(Abs3), sig(Kind3)) "…asymmetric"
@assert !Base.morespecific(Tuple{typeof(w3b), AMem3}, Tuple{typeof(w3), Any}) "member-vs-Any: Any loses as ever"

println("m2_closed_open_order: OK")
