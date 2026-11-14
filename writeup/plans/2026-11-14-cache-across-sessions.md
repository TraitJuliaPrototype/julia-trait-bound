# The cache across sessions: the question again, with phase 3's first numbers

**Status:** proposal, for the user (W-120; [the schedule](2026-11-11-complete-prototype.md), phase 3). Nothing is built. The user (2026-11-11): "We should probably revisit the cross session cache now." The mandate (2026-11-12): "keep going until the numbers of phase 3 are in. When they are in only get back to me if they actually indicate a trade off."

Written by the main session (2026-11-14). Not normative.

## The question

G-3's claim is that traits and facts improve caching. Package images are the cache that exists. A cache across sessions would add a store that outlives a session and is not one package's image. What would it hold that the images cannot, and what is that worth?

## The numbers (E-372)

Two sessions on the head (`unified` add2f921c9), each a fresh process: TraitCSV and TraitTables reading and summarizing a table; the ODE port solving Lorenz with Tsit5 and Robertson with Rodas5. `experiments/unification/w120/`; [evidence §3](../design/evidence.md#3-first-calls-and-sessions).

| | The table session | The ODE session |
|---|---|---|
| Wall | 0.76 s | 1.25 s |
| Start of Julia (E-291) | 0.18 s | 0.18 s |
| Load | 0.43 s | 0.57 s |
| First run, all of it compiling | 0.063 s | 0.40 s |
| Compiled in the session, in all | 186 ms | 692 ms |
| of it the session's own code | 77 ms | 360 ms |
| of it Julia's own methods | 103 ms | 261 ms |
| of it code a package's own image could hold | 0 | 42 ms |
| of it compiled again | 6 ms | 30 ms |
| of it a library's code that names no session type | 0 | 0 |

## What they say

1. **The images already hold what a cache was meant to hold.** The code of the trait libraries compiled once for a trait, or for the libraries' own types, is in the packages' images, and the loads keep it. This is the design's own claim (compiled once, kept by the G2 bit), and on these two sessions it holds.
2. **Where it did not hold, the cause was a rule, not a missing store.** The ODE session took 2.75 s the day before. The solver was compiled in every session because one edge failed G2 and the image dropped the instance. The fix was at the rule (compiler §7.4). A cache across sessions would have hidden that fault, and paid for it at each change of the environment.
3. **What is left for a cache is of two kinds.**
   - *The session's own code:* `main` and the user's functions, at most 77 ms and 360 ms here. It is the same only while the script is the same. A cache would serve the second run of an unchanged script.
   - *Julia's own methods at signatures no image holds:* printing a `Float64`, `round` with `sigdigits`, a range. 103 ms and 261 ms. A workload line in Julia's own images holds these for every user, with no new mechanism, and stands without traits (W-19).
4. **The bound.** A cache that held everything and cost nothing to load and validate would take the table session from 0.76 s to 0.57 s and the ODE session from 1.25 s to 0.56 s. A real one validates what it loads.
5. **The larger part of both sessions is the load,** 0.43 s and 0.57 s, which no cache of compiled code touches.

## The options

- **(a) Stop the cache here.** G-3's claim rests on the images: the libraries' code is held and kept. The session's own code is compiled each session, as in plain Julia. Work goes to what the tools of E-372 find: an instance that a workload compiles and an image drops (the pattern of the `Callable` edge), on each port as it comes to the head.
- **(b) A cache for the session's own code,** keyed on the script's source and the environment: the smallest vehicle is Julia's own (`--trace-compile` and a package image of the script's methods, as PackageCompiler and `juliac` do). It needs no change to Julia. Its gain is the first row of point 3, for a script run again unchanged.
- **(c) A store on today's loader for any code by the G2 bit** (the review of 2026-11-07, step 6). It is the large build. On these sessions it has nothing more to hold than (b).

## Recommendation

**(a), with one tool kept:** the check of E-372 as a gate for each port (`sessions.sh`, `classify_trace.py`): a session of the port's own workload compiles no library code that names no session type. It is what would have caught the `Callable` edge.

**What would change this:** a port in phase 4 whose session compiles library code that no image can hold by any rule: a composition of two packages' types that neither package's image, nor an extension's, can compile. The class "composition" of `classify_trace.py` counts it. It is 0 on both sessions now. The forks (CSV, DataFrames) and TraitMakie are the ones to watch: their sessions are not on the head.

**The trade-off for the user:** (a) leaves the session's own code to be compiled in every session, 0.08 to 0.36 s here, as plain Julia does. (b) removes it for unchanged scripts at the cost of a build step a user must run. The numbers do not decide between them; they do say that (c) is not needed for what these two ports do.
