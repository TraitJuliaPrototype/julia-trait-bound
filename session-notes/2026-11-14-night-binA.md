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

## Choices, mine

- The check is the build's own code run in the session; not a second walk, not a child process.
- The check reads the build's replacements of Base from the build script's files, as an overlay. What is no method is not read.
- Fully typed mode raises only where the check lists a call.
- The cast names are bound, not reserved; `@unbounded`; `OperationError`; errors raised at the user's line.

## The commits

- `julia-unified` `unified`: 3f33d9e684 (the casts), 8f42ba7ed7 (the hook's error), 381cc8b953 (the check; C-88 (a)).
- TraitWorld `unified`: 0dad2e6, 399f389, 78a78af. TraitDifferentialEquations `unified`: cecf2c3.
- The branches `binA-wip` are left as they were, as a record of the work in progress.
- The local branches `unified` of `julia-unified` and `main` of the design repository are stale and diverged from their remotes. The work is on `unified-w141` (pushed to `origin/unified`) and `w141-record` (pushed to `origin/main`).
