# Gate M2 item 8 (§8, exploration §2.3): a member of two sets whose function
# holds a method at both warns EXACTLY ONCE at the second @implement (stderr,
# warn-only — no error), while a member joined through a set Z that carries its
# own method suppresses the report; the runtime dispatch still raises (advisory).
include("util.jl")

const JULIA = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project())`

body_warn = """
    using Traits
    @trait XA
    @trait YA
    f(::XA) = :x
    f(::YA) = :y
    struct MA end
    @implement MA XA                     # first join: no pair, no warning
    @implement MA YA                     # member of both: the report fires here
    res = try
        f(MA())
        "nothrow"
    catch e
        (e isa MethodError || occursin("ambiguous", sprint(showerror, e))) ? "raised" : "wrong"
    end
    println("CHILD_RUNTIME ", res)
    println("CHILD_DONE")
"""

body_suppress = """
    using Traits
    @trait XB
    @trait YB
    g(::XB) = :x
    g(::YB) = :y
    @trait ZB
    @implement ZB XB                     # ZB joins XB (first join: silent)
    g(::ZB) = :z                         # a method on ZB: more specific than both
    @implement ZB YB                     # second join: pair (XB, YB) suppressed
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

out, err = child(body_warn)
@assert occursin("CHILD_DONE", out) "warn-case child completed: $out"
nwarn = length(collect(eachmatch(r" is ambiguous for ", err)))   # §8's message format
@assert nwarn == 1 "exactly one §8 warning, got $nwarn in: $err"
@assert occursin("CHILD_RUNTIME raised", out) "runtime dispatch raises at the member (advisory)"
@assert !occursin("ERROR", err) "no error thrown by the declaration itself"

out2, err2 = child(body_suppress)
@assert occursin("CHILD_DONE", out2) "suppress-case child completed: $out2"
@assert !occursin(" is ambiguous for ", err2) "a set-in-set method on both sides suppresses: $err2"

println("m2_ambiguity_report: OK")
