# Gate M3 §6 (ports, R-1/R-3/R-4): the inference arms of fold_call, known_type,
# split_call. fold_call folds in a compiled global-cache frame (value material-
# ized at the statement — R-1 — plus a FoldRecord edge) and stays `nothing` at
# the interpreter; known_type folds to Const(isdispatchelem(widenconst(..))) —
# R-3; split_call with zero candidates == the call (R-4: the inliner stays inert).
include("util.jl")
import Compiler

# (A) fold_call at the interpreter: the runtime definition answers nothing
tgt(v) = 2v + 1                                  # a plain function to fold over
@assert Compiler.fold_call(tgt, 3) === nothing "the interpreter keeps the not-folded answer"

# (B) folded inside a marked, globally-cached frame: value + FoldRecord
fc3(v) = (r = Compiler.fold_call(tgt, v); r === nothing ? tgt(v) : r)
Compiler.mark_facts!(fc3)
@assert fc3(3) == 7
cif = only([c for c in all_cis(fc3) if c.min_world > 0])
@assert any(e -> isa(e, Compiler.FoldRecord), cif.edges) "fold records a FoldRecord: $(collect(cif.edges))"
@assert cif.rettype === Int || cif.rettype === 7 "folded frame's rettype concrete: $(cif.rettype)"
fr = only([e for e in cif.edges if isa(e, Compiler.FoldRecord)])
@assert fr.g === tgt && fr.args == (3,) && fr.value == 7 "FoldRecord carries (g, args, value): $fr"

# (C) `nothing`/Undecided do not fold
tgt_none(v) = nothing
tgt_un(v) = Compiler.Undecided()
fn3(v) = (r = Compiler.fold_call(tgt_none, v); r === nothing ? :notfolded : :folded)
fu3(v) = (r = Compiler.fold_call(tgt_un, v); r === nothing ? :notfolded : :folded)
Compiler.mark_facts!(fn3)
Compiler.mark_facts!(fu3)
@assert fn3(1) === :notfolded "a nothing fold does not fold"
@assert fu3(1) === :notfolded "an Undecided() fold does not fold"
@assert !any(e -> isa(e, Compiler.FoldRecord), only(all_cis(fn3)).edges)

# (D) known_type — R-3's widenconst form: true at known (dispatchelem) types,
# false where the site is abstract
kt_known(v::Int) = Compiler.known_type(v)
kt_site(x::Vector{Any}) = Compiler.known_type(x[1])
Compiler.mark_facts!(kt_known)
Compiler.mark_facts!(kt_site)
@assert kt_known(5) === true "known at a dispatchelem"
@assert kt_site(Any[5]) === false "unknown at an Any site"
cik = only([c for c in all_cis(kt_known) if c.min_world > 0])
@assert cik.rettype === Bool "known_type folds (no run-time call left): rettype $(cik.rettype), nortsite $(Compiler.decode_effects(cik.ipo_purity_bits).nortsite)"

# (E) split_call: zero candidates — the call delegates, value intact (R-4: the
# SplitCallInfo stays inert against the unported inliner split)
struct SPK3 end
sg3(x::Int) = x + 1000
sp3(x::Vector{Any}) = Compiler.split_call(SPK3, Int, sg3, x[1])
Compiler.mark_facts!(sp3)
@assert sp3(Any[3]) == 1003 "zero candidates: split_call == the call"

# with a candidate registered: narrowing runs, the value is still the call's
struct SPD3 end
struct DV3 <: SPD3 end
sd3(x::SPD3) = :cand
sd3(x) = :fallback
Compiler.register_dynamic_candidate!(SPD3, DV3)
sp4(x::Vector{Any}) = Compiler.split_call(SPD3, Symbol, sd3, x[1])
Compiler.mark_facts!(sp4)
@assert sp4(Any[DV3()]) === :cand "candidate runs for its key"
@assert sp4(Any[5]) === :fallback "the fallback answers for other values"

println("m3_fold_known: OK")
