# Gate M3 §1 (R-12: behavioral pins strict; the bail remark is OBSERVED only):
# a facts frame resolves fact-signature calls as plain (pair edge, concrete
# rettype) and refuses non-fact calls — no (sig, callee) pair at the site,
# rettype Any. Plus the is_fact_sig table (F1-F4 forms, §1a; Keyed => false).
include("util.jl")
import Compiler

mark!(f) = Compiler.mark_facts!(f)

# ---------- (A) the criterion table ----------
f_sig(::Int) = 1
v_sig(::Int, ::Vararg{String}) = 1
h_sig(::Any) = 1
cl_sig = (x::Int) -> x + 1                      # generated-name closure (F4 subject)

const T = Tuple
check(t, want, why) = begin
    got = Compiler.is_fact_sig(t)
    @assert got == want "is_fact_sig($t) ($why): got $got, want $want"
end
check(T{typeof(f_sig), Int}, true, "F1 dispatch tuple")
check(T{typeof(h_sig), Any}, false, "Any is not a fact")
check(T{typeof(f_sig), Union{Int, String}}, true, "F2 two-union, cost 2 <= 4")
check(T{typeof(v_sig), Int, Vararg{String}}, true, "F3 concrete Vararg tail")
check(T{typeof(v_sig), Int, Vararg{Any}}, false, "Vararg{Any} tail is not a fact")
check(T{typeof(cl_sig), Type{Int}}, true, "F4 closure at kinds")
check(T{typeof(f_sig), Type{Int}}, false, "kinds at a non-closure head: F1 rejects, no F4")
check(T{typeof(f_sig), Core.Keyed{Int, Nothing, Nothing}}, false, "Keyed is never a fact element (D1)")

# ---------- (B) the gate at find_method_matches: a fact call ----------
g_fact(x::Int) = x + 1
function marked_fact(a::Int)
    g_fact(a)
end
mark!(marked_fact)
@assert marked_fact(1) == 2
cif = only([c for c in all_cis(marked_fact) if c.min_world > 0 &&
            Base.unwrap_unionall(c.owner.def.specTypes).types[2] === Int])
@assert cif.rettype === Int "fact call: concrete rettype, got $(cif.rettype)"
haspair = any(1:length(cif.edges)-1) do i
    cif.edges[i] === T{typeof(g_fact), Int} &&
        cif.edges[i+1] isa Union{Core.MethodInstance, Core.CodeInstance}
end
@assert haspair "fact call records its (sig, callee) pair: edges=$(collect(cif.edges))"
@assert Compiler.decode_effects(cif.ipo_purity_bits).nortsite "fact-only frame keeps nortsite"

# ---------- (C) a run-time site ----------
unknown_call(a) = a
function marked_rts(v::Vector{Any})
    unknown_call(v[1])
end
mark!(marked_rts)
@assert marked_rts(Any[5]) == 5
cir = only([c for c in all_cis(marked_rts) if c.min_world > 0])
@assert cir.rettype === Any "run-time site: rettype Any, got $(cir.rettype)"
@assert !(cir.edges isa Nothing)
noedge = !any(1:length(cir.edges)-1) do i
    cir.edges[i] isa Type && cir.edges[i+1] isa Union{Core.MethodInstance, Core.CodeInstance} &&
        occursin("unknown_call", string(cir.edges[i]))
end
@assert noedge "the run-time site records no (sig, callee) pair: edges=$(collect(cir.edges))"
@assert !Compiler.decode_effects(cir.ipo_purity_bits).nortsite "run-time site clears nortsite"
# observed, not pinned (R-12): the facts-bail remark, if it reaches the source
if isdefined(cir.src, :remarks) && cir.src.remarks !== nothing
    println("OBSERVED remarks: ", cir.src.remarks)
end

println("m3_policy_sites: OK")
