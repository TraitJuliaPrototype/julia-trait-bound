# M7, rule 7: where compiled code lives. Run in a fresh process with --trace-compile:
#   julia --startup-file=no --project=poc/world/env --trace-compile=stderr poc/world/m7_placement.jl [noapp]
using TraitWorld, Columns, Stats, UserTypes
noapp = get(ARGS, 1, "") == "noapp"
noapp || @eval using App
v = [[1.0, 2.0], [3.0, 5.0]]
m, r = Measurements(v), Ramp([1.0, 2.0], 2)
step(label, f) = (println(stderr, "### ", label); f(); println(stderr, "### end"))
step("Columns' representation: colmean(v, 1)", () -> colmean(v, 1))
step("a conformer's projection: colmean(Measurements, 1)", () -> colmean(m, 1))
step("a conformer's representation: colmean(Ramp, 1)", () -> colmean(r, 1))
step("Stats at Columns' representation: weighted(v, 1)", () -> weighted(v, 1))
step("Stats at UserTypes' representation: weighted(Ramp, 1)", () -> weighted(r, 1))
