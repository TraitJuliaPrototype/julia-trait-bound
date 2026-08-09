# Design-A experiment: what fraction of real-world invalidation kills are
# SPURIOUS (new method intersects the killed signature but does not change
# what that signature resolves to)?
#   julia +1.11.7 --startup-file=no --project=. xA_spurious.jl
using ColStats, ColReports, EagerTables, PlainStack, SnoopCompileCore
t = EagerTable([rand(100) for _ in 1:6])
PlainStack.getcol(x::EagerTable, i::Int) = x.cols[i]
PlainStack.ncols_direct(x::EagerTable) = length(x.cols)
report(t); report_p(t)
invs = @snoop_invalidations (using CairoMakie)
using SnoopCompile
trees = invalidation_trees(invs)
world = Base.get_world_counter()
function classify(trees, world)
    tot = 0; genuine = 0; unresolved = 0
    for tr in trees
        for (sig, root) in tr.mt_backedges
            sig isa Type || continue
            tot += 1
            ms = try Base._methods_by_ftype(sig, -1, world) catch; nothing end
            if ms isa Vector
                # genuine iff the invalidating method is now the TOP match for
                # the killed signature (it actually changes resolution).
                # First cut: a rigorous version needs the killed call sites
                # inferred argtypes, not the (often abstract) backedge sig.
                genuine += (!isempty(ms) && ms[1].method === tr.method) ? 1 : 0
            else
                unresolved += 1
            end
        end
    end
    (tot, genuine, unresolved)
end
tot, genuine, unresolved = classify(trees, world)
nmb = sum(length(tr.backedges) for tr in trees)
println("mt_backedge-killed signatures: ", tot,
        " | genuine (new method now wins): ", genuine,
        " | spurious: ", tot - genuine - unresolved,
        " (", round(100 * (tot - genuine - unresolved) / max(tot, 1), digits = 1), "%)",
        " | unresolved: ", unresolved)
println("method-backedge roots (unclassified by this probe): ", nmb)
