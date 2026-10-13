# Runs every load-order scenario in a fresh process per mode and checks the outcome.
const HERE = @__DIR__
const ENVDIR = joinpath(HERE, "env")

function run_case(mode, pkgs; flags = ``)
    out = IOBuffer(); err = IOBuffer()
    cmd = addenv(`$(Base.julia_cmd()) --startup-file=no $flags --project=$ENVDIR $(joinpath(HERE, "run.jl")) $pkgs`,
                 "JULIA_TRAITBOUND" => mode)
    run(pipeline(ignorestatus(cmd); stdout = out, stderr = err))
    o = String(take!(out)); e = String(take!(err))
    line = something(findfirst(l -> startswith(l, "RESULT"), split(o, '\n')), 0)
    res = line == 0 ? "no RESULT; stderr: " * first(e, 300) : split(o, '\n')[line]
    (res = String(res), piracy_warnings = count("PiracyError:", e), orphan_warnings = count("orphan seal", e))
end

field(res, k) = (m = match(Regex("$k=(\\S+)"), res); m === nothing ? "" : m.captures[1])

const CASES = [
    ("MyTable alone",            ["MyTable"]),
    ("MyTable, then Pirate",     ["MyTable", "Pirate"]),
    ("Pirate, then MyTable",     ["Pirate", "MyTable"]),
    ("MyTable, then Dominated",  ["MyTable", "Dominated"]),
    ("Dominated, then MyTable",  ["Dominated", "MyTable"]),
    ("MyTable, then Legit",      ["MyTable", "Legit"]),
    ("Legit, then MyTable",      ["Legit", "MyTable"]),
    ("MyTable, then FakeImpl",   ["MyTable", "FakeImpl"]),
    ("FakeImpl, then MyTable",   ["FakeImpl", "MyTable"]),
]

# expected colsum value per (case, mode)
function expected(name, mode)
    pir = occursin("Pirate", name); impl = occursin("FakeImpl", name)
    pir && mode == "error" && return "PiracyError"
    (pir || impl) && return "12.0"
    return "6.0"
end
expected_warn(name, mode) = (occursin("Pirate", name) && mode == "warn") ? 1 : 0

println("| scenario | mode | colsum | compile ms | first call ms | piracy warnings | sqnorm | steady ns/call | ok |")
println("|---|---|---|---|---|---|---|---|---|")
allok = true
for (name, pkgs) in CASES, mode in ("warn", "error", "recompile")
    r = run_case(mode, pkgs)
    v = field(r.res, "colsum")
    ok = v == expected(name, mode) && r.piracy_warnings == expected_warn(name, mode) && field(r.res, "sqnorm") == "14.0"
    global allok &= ok
    println("| $name | $mode | $v | $(field(r.res, "compile")) | $(field(r.res, "firstcall")) | $(r.piracy_warnings) | $(field(r.res, "sqnorm")) | $(field(r.res, "steady_ns")) | $(ok ? "yes" : "NO: " * r.res) |")
end
# orphan rule: checked when the seal is defined, i.e. when Orphan precompiles
r = run_case("warn", ["Orphan"]; flags = `--compiled-modules=no`)
println("\nOrphan (warn mode): orphan warnings = $(r.orphan_warnings); ", r.res)
allok &= r.orphan_warnings >= 1
println(allok ? "\nALL SCENARIOS AS EXPECTED" : "\nSOME SCENARIOS DIFFER")
