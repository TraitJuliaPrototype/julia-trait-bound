# M6: piracy (the audit), layering beyond imports.
#   julia --startup-file=no --project=poc/world/env poc/world/m6_rules.jl [warn|error|recompile]
using TraitWorld, Columns, Stats
mode = Symbol(get(ARGS, 1, "warn"))
TraitWorld.mode!(mode)
m = [1.0 2.0; 3.0 4.0]
println("mode $mode. before the pirate: weighted(m, 1) = ", weighted(m, 1))
using Pirate                         # defines Stats.weight(::Float64): owns neither the function nor the type
r = try weighted(m, 1) catch e; e end
println("after the pirate:  weighted(m, 1) = ", r isa Exception ? sprint(showerror, r)[1:min(end, 300)] : r)
println("plain Julia, for comparison: ", sum(x -> Stats.weight(x) * x, m[:, 1]))

# layering beyond imports: a trait module that reaches ordinary code without importing it
module Plain; f(x) = x + 1.0; end
@trait_module module Sneaky
using TraitWorld, Columns
sneak(t::ColTable) = Main.Plain.f(colmean(t, 1))
end
println("\nSneaky.sneak: ", try Sneaky.sneak(m) catch e; sprint(showerror, e) end)
