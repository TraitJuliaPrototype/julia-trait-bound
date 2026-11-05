# AC-17 (new; facts §6.4 — the compiler's own code is ALWAYS plain):
# (a) mark_facts! on a Compiler function has no effect (the frame refuses the
#     Compiler module, R-2/R-9);
# (b) after an `all` workload (marked calls and membership compiles above),
#     EVERY CodeInstance of EVERY function of `Compiler` and `Base.Compiler`
#     reads nortsite == true — plain inference has no site that clears the bit,
#     so a false there can only be policy leakage into the compiler. This is
#     the census differential (R-12: method CIs, not thunks).
include("ac_util.jl")
using Traits

# --- the workload: exercises the policy machinery in this process ------------
@trait S17
struct M17 end
@implement M17 S17
g17(::S17) = 1
c17(m::M17) = g17(m)
sink17(a) = a
r17(v::Vector{Any}) = sink17(v[1])
u17(x::Int) = x + 1
w17(a::Int) = u17(a)
for f in (c17, r17, w17)
    mark!(f)
end
@assert c17(M17()) == 1 && r17(Any[1]) == 1 && w17(1) == 2
map(x -> x + 1, [1, 2, 3])          # some real inference too

# --- (a) marking a Compiler function changes nothing --------------------------
target = Compiler.decode_effects          # a plain Compiler method, hot during this file
Compiler.mark_facts!(target)              # refused or ignored — must not throw
target(UInt32(0))
for c in all_cis(target)
    @assert Compiler.decode_effects(c.ipo_purity_bits).nortsite "a marked Compiler function stayed plain"
end

# --- (b) the census -------------------------------------------------------------
# (only Compiler's methods with an abstract call could EVER read nortsite
# false; a policy leak through the module refusal shows here)
cleaks = Any[]
for mod in (Compiler, Base.Compiler)
    for nm in names(mod; all=true)
        isdefined(mod, nm) || continue
        f = getfield(mod, nm)
        f isa Function || continue
        try
            for m in methods(f)
                for mi in Base.specializations(m)
                    isdefined(mi, :cache) || continue
                    c = getfield(mi, :cache)::Core.CodeInstance
                    while c !== nothing
                        Compiler.decode_effects(c.ipo_purity_bits).nortsite ||
                            push!(cleaks, (mod === Base.Compiler ? "Base.Compiler" : "Compiler", nm, mi.specTypes))
                        c = isdefined(c, :next) ? c.next : nothing
                    end
                end
            end
        catch
            # builtins and friends without `methods`/`specializations`: skip
        end
    end
end
@assert isempty(cleaks) "policy leaked into the compiler: nortsite-false CIs: $(first(cleaks, min(5, length(cleaks))))"

ac_finish(@__FILE__)
