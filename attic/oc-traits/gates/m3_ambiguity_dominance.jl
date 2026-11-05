# Gate M3 §10 (deviations D-M2-7): the ambiguity report compares dispatch's
# outcome, not the raw `ambig` pair flag. A fixed-vs-Vararg pair whose member
# dispatch resolves to a single, fully-covering winner warns ZERO times now;
# the genuinely ambiguous shape (two incomparable methods) still warns once.
include("util.jl")

const JULIA = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project())`

# D-M2-7 shape: kd(::VC2) vs kd(::Vararg{VC3}); a member of both sets.
# Dispatch resolves by dominance (fixed-arity beats Vararg at a concrete type),
# so the call has ONE answer and the §8 pair-flag was an over-report.
body_dominates = """
    using Traits
    @trait VC2
    @trait VC3
    kd(::VC2)          = :vc2
    kd(::Vararg{VC3})  = :vc3
    struct PC end
    @implement PC VC2                    # first join: silent
    @implement PC VC3                    # pair (VC2, VC3): dominance suppresses now
    println("CHILD_RUNTIME ", kd(PC()))
    println("CHILD_DONE")
"""

# Regression: the genuinely ambiguous pair (two incomparable methods, no
# dominating winner) must STILL warn exactly once — m2_ambiguity_report's case.
body_ambiguous = """
    using Traits
    @trait XD
    @trait YD
    fd(::XD) = :x
    fd(::YD) = :y
    struct MD end
    @implement MD XD
    @implement MD YD
    res = try
        fd(MD()); "nothrow"
    catch e
        (e isa MethodError || occursin("ambiguous", sprint(showerror, e))) ? "raised" : "wrong"
    end
    println("CHILD_RUNTIME ", res)
    println("CHILD_DONE")
"""

function child(body)
    sp, op, ep = tempname(), tempname(), tempname()
    write(sp, body)
    open(op, "w") do of
        open(ep, "w") do ef
            run(pipeline(`$JULIA $sp`, stdout=of, stderr=ef))
        end
    end
    out, err = read(op, String), read(ep, String)
    rm.([sp, op, ep], force=true)
    return out, err
end

out1, err1 = child(body_dominates)
@assert occursin("CHILD_DONE", out1) "dominance child completed: $out1"
nwarn1 = length(collect(eachmatch(r" is ambiguous for ", err1)))
@assert nwarn1 == 0 "D-M2-7: dominance-suppressed pair warns zero times, got $nwarn1 in: $err1"
@assert occursin("CHILD_RUNTIME :vc2", out1) "dispatch resolves the dominating winner: $out1"

out2, err2 = child(body_ambiguous)
@assert occursin("CHILD_DONE", out2) "ambiguity child completed: $out2"
nwarn2 = length(collect(eachmatch(r" is ambiguous for ", err2)))
@assert nwarn2 == 1 "the incomparable pair still warns exactly once, got $nwarn2"
@assert occursin("CHILD_RUNTIME raised", out2) "runtime still raises at the truly ambiguous member"

println("m3_ambiguity_dominance: OK")
