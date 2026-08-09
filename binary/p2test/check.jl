using User, Helper
mis = collect(Base.specializations(first(methods(hfun))))
for mi in mis
    c = isdefined(mi, :cache) ? mi.cache : nothing
    println(mi.specTypes, " cache=", c !== nothing,
            c !== nothing ? " native=$(c.invoke != C_NULL || c.specptr != C_NULL)" : "")
end
s = @timed User.run_dyn(rand(1000))
println("first dynamic call: compile ", round(s.compile_time*1e3, digits=1), " ms")
