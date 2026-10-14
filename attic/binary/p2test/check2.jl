using User
using LoadChurn    # loaded AFTER User: its method definition invalidates the tagged CIs
v = [1.0, 2.0, 3.0]
s = @timed User.run_all(v)
println("after load-churn: compile ", round(s.compile_time * 1e3, digits = 1),
        " ms, recompile ", round(s.recompile_time * 1e3, digits = 1), " ms")
