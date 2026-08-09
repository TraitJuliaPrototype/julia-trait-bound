using LoadChurn2          # dominated method exists BEFORE User's image validates
using User
v = [1.0, 2.0, 3.0]
s = @timed User.run_all(v)
println("load-channel dominated-newcomer: compile ",
        round(s.compile_time * 1e3, digits = 1), " ms  (value ok: ", s.value == User.run_all(v), ")")
