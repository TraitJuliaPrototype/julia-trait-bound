# The night of 2026-11-14: bin A, from the pick-up note

The user (2026-11-14): "Continue the work here, I am going to bed, work through the night."

Started from [`2026-11-12-pickup-binA.md`](2026-11-12-pickup-binA.md). The mandate in force is the one of 2026-11-12: bin A to empty, then phase 3's first step; a trade-off goes to the user, a clear path is taken.

## What was done, in order

1. **The pick-up's fault fixed.** `collectinvokes!` queues an invoke's method instance only in a build's queue (`compile!`), not in the JIT's. Gates back: 70 pass, the nine `m3_*` fail as before.
2. **The cast gates.** They failed because the names are bound now and the gates' stub library did not export them. The stub imports and exports `Core`'s casts.
3. **The report's root cause.** A call the build refuses below a call the session's walk reported (inside Base's `sum`) is reported at the walk's site, in the user's code, with its cause. The library's suite passes.
4. **W-142 to the end.** `agree.sh`: 13 of 13. Then the demonstrators' programs found two more things:
   - a rule site that asked the trim option, not the interpreter: the split's table (the inliner). The check listed 22 `cfunction`s;
   - **the build's Base is not the session's.** `juliac`'s build script replaces 28 methods of Base before it compiles. The table program prints a type's name, and the check listed 25 calls inside `show`. Fixed at the rule: the library reads the script's files into an overlay method table, and the check infers through it (compiler §2.7, traits §16, lowering §14; open issue 181; mine). One program still differs, `Base.invokelatest`, a binding and no method.
   - 17 of 18 programs agree (E-369). The table program is fully typed, builds and runs. The ODE port's is not (57 calls), and is refused.
5. **Errors.** `OperationError` tested; a check's error has the user's line as its first frame (a new test). E-362's trait runs again: 2 library frames above the user's line, where they were 24 (E-370).
6. **C-88 (a):** a gate case in `n26` for a call inferred again with a constant.
7. **Recorded:** the references, the decision log (five rows mine, two superseded, the deferred annotations retired), open issues (160, 176, 167, 168, 173, 177 (a) and (b), the deferred item 2 closed; 115, 116 restated; 181 new), alternatives, the evidence, the goals (G-5, G-6, G-8), the registry (E-369, E-370), the work queue, the schedule's addendum.

8. **More of bin A.** A cast with keyword arguments (L-56). T-97 (the warning at an extension's method; a stack gate with a real extension), T-111 (`detect_kept_storage`: it lists the ODE port's six sites), L-57 (the error names the constructor) retired. T-102 restated: `like` is not fully typed. Out of bin A, mine: C-55, T-105, L-58 to B; C-56, T-99 to C.
9. **A fault found while reading L-58: a `Callable`'s check was lost where an instance knew the function.** `apply(compiled_for(bad), 1.0)` returned a value outside `S`; `apply(with_dynamic(bad), 1.0)` raised. Fixed at the rule: the declaration decides the check, in every instance (compiler §7.4, C-90; gate `n8_callable`). The call compiled for the function costs what a plain call costs (E-371).
10. **Phase 3's first step (E-372),** taken while bin A is not empty, since no open row of it changes the measurement. The ODE session compiled its solver in every session, 538 ms, though the port's workload compiles it. The tools (`image_has.jl`, `g2_why.jl`) led to one edge: a `Callable` absence edge to every call of a `Vector`, which failed G2, so the image dropped the instance. Narrowed at the rule (compiler §7.4, C-88 (b) closed). **The ODE session: 2.75 s to 1.25 s.** The compiler's own closures over a type, 138 ms a session, boxed.
11. **The cache's proposal** (`writeup/plans/2026-11-14-cache-across-sessions.md`), for the user: no library code is left for a cache to hold on the two sessions; it recommends stopping the cache. Nothing is built.

## Choices, mine

- The check is the build's own code run in the session; not a second walk, not a child process.
- The check reads the build's replacements of Base from the build script's files, as an overlay. What is no method is not read.
- Fully typed mode raises only where the check lists a call.
- The cast names are bound, not reserved; `@unbounded`; `OperationError`; errors raised at the user's line.
- A `Callable`'s check is decided by the declaration; its absence edge is as narrow as the question.
- Phase 3's first step before bin A is empty; the triage revised.

## The commits

- `julia-unified` `unified`: 3f33d9e684 (the casts), 8f42ba7ed7 (the hook's error), 381cc8b953 (the check; C-88 (a)).
- TraitWorld `unified`: 0dad2e6, 399f389, 78a78af. TraitDifferentialEquations `unified`: cecf2c3.
- Later in the night: `julia-unified` 23e1dd3feb (a cast with keywords), a0602148ca (`Callable`'s check), add2f921c9 (the absence edge; the closures); TraitWorld 12b8b31.
- The branches `binA-wip` are left as they were, as a record of the work in progress.
- The local branches `unified` of `julia-unified` and `main` of the design repository are stale and diverged from their remotes. The work is on `unified-w141` (pushed to `origin/unified`) and `w141-record` (pushed to `origin/main`).
