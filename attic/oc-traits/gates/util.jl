# shared probes for the M1 gate scripts (plan §5 M1)

# all cached CodeInstances of a function, newest surface first
function all_cis(@nospecialize(f))
    out = Core.CodeInstance[]
    for m in methods(f)
        for mi in Base.specializations(m)
            ci = getfield(mi, :cache)::Core.CodeInstance
            while ci !== nothing
                push!(out, ci)
                ci = isdefined(ci, :next) ? ci.next : nothing  # the last link's next is undefined
            end
        end
    end
    return out
end

# the world the current task is executing in
curworld() = Base.tls_world_age()
