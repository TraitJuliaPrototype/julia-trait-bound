# AC-19 (old G1.35 half; new reading — D9): the `JULIA_FACTS=1` process boots,
# runs a small acceptance prelude (the policy surface exists and is usable),
# and `detect_ambiguities(Base)` is UNCHANGED against the plain setting — the
# test bed must not perturb plain-visible surfaces outside the policy.
# Two children (plain and `all`), same binary and project; the ambiguity lists
# compared as sorted text. This file drives its own settings, so it ends with
# its own OK line instead of ac_finish.
const JULIA = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project())`

prog = """
    using InteractiveUtils, Traits
    import Compiler
    struct A19 end
    f19(::A19) = 1
    g19(x::Int) = x + 1
    Compiler.mark_facts!(g19)
    @assert isdefined(Compiler, :mark_facts!) && isdefined(Compiler, :mark_concrete!) &&
            isdefined(Compiler, :is_fact_sig) "the policy surface exists"
    @assert g19(1) == 2
    ambs = detect_ambiguities(Base)
    println("NAMBIG ", length(ambs))
    for a in sort(collect(ambs); by=x -> sprint(show, x))
        println("AM ", sprint(show, a))
    end
    println("PRELUDE OK")
"""

function run_child(env)
    sp, op, ep = tempname(), tempname(), tempname()
    try
        open(op, "w") do of
            open(ep, "w") do ef
                run(pipeline(addenv(`$JULIA -e $(prog)`, env), stdout=of, stderr=ef))
            end
        end
        out, err = read(op, String), read(ep, String)
        occursin("PRELUDE OK", out) || error("prelude failed: $out\n$err")
        n = tryparse(Int, match(r"NAMBIG (\d+)", out).captures[1])
        list = join(filter(l -> startswith(l, "AM "), split(out, '\n')), "\n")
        return n, list
    finally
        rm.([sp, op, ep], force=true)
    end
end

n_plain, l_plain = run_child(String[])
n_all, l_all = run_child(["JULIA_FACTS" => "1"])
@assert !isnothing(n_plain) && n_plain == n_all "the ambiguity count moved under the policy: $n_plain vs $n_all"
@assert l_plain == l_all "the ambiguity list moved under the policy"
println("AC_19: OK   (detect_ambiguities(Base) = $n_plain, unchanged under all)")
