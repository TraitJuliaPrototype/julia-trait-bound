using User, Helper
v = [1.0, 2.0, 3.0]
s = @timed User.run_all(v)   # first dynamic sweep over all 100 in this session
println("aggregate first-call compile over 100 foreign fns: ",
        round(s.compile_time * 1e3, digits = 1), " ms")
