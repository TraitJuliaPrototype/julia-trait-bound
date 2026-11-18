# Review: the split table (julia-1.13 711484a23e) and W-2, 2026-10-21

A fresh-eyes review (Fable, the critic agent) of the night's code: the compiler change of [compiler §4.3](../reference/compiler.md#43-what-follows-the-split-the-table-of-a-calls-targets) and work item W-2 (TraitDifferentialEquations e37829f, TraitWorld 8d29f20). The reviewer read code, diffs and logs and ran nothing. Its findings, in brief, then what was done with each.

## The findings

1. **High (verified): the typed call's rule for arguments and results was wrong for concrete non-isbits types.** Julia's C ABI passes a struct type by value: a mutable struct argument beyond the split's candidates reached the target as a *copy* (identity lost, a mutation not seen by the caller, silently), and a result struct holding a reference raised "return type struct fields cannot contain a reference" at the first value beyond the candidates. No check exercised it. Do: isbits types of nonzero size by value, everything else boxed; the site's argument types in the target's type, asserted inside; a check with a mutable argument, a result with a reference, a `Dynamic` argument.
2. **Medium (verified):** the C side, the layouts, the memory ordering and the sessions are sound. Hardening: `jl_split_table_ptr` would call a null miss function before `Base.__init__`.
3. **Medium (reasoning):** worlds and owners hold. Open: code precompiled into package images and reused by a `--trim` build would carry a miss path that needs the JIT (row 12 not built); C-3's re-lookups after each definition, unmeasured.
4. **Low:** `verify_main` reads the new IR correctly; concrete mode would describe an abstract last-branch result as "a ccall returns Any".
5. **Low:** `facts.md` said "23 checks"; isbits non-singleton callables box per call, as the dynamic call did.
6. **Medium (judgment): `ODEProblem`'s `fn::Any` was workaround-shaped:** the function kept twice, `nothing` doubling as a flag, the dual form rebuilt per Jacobian call. A fixed chunk of 8 (the Jacobian already handles a partial last chunk) takes the chunk out of the type, so the dual form can be a typed field kept by `stored`.
7. **Medium: `stored` as API:** matches traits §6.6 and §9; say why it is for `Callable` only, and that a function of the trait world is kept as itself even where the caller does not know its type; `with_dynamic(f)` with Rodas5 untested.
8. **Low:** the claims match the logs; the rows are one run each, said so; the example's docstring stated as fact what W-8 is to measure.
9. **Low:** the rest of W-2 is clean; the README should name that callbacks assert `integ.p`'s type (the callback operations take `Dynamic{IntegratorView}` without parameters).

## What was done (2026-10-21)

| Finding | Done |
|---|---|
| 1 | `split_ccall_type` and `split_ccall_rt` (isbits of nonzero size by value, `Nothing` as no value, else boxed); the target `_SplitTarget{F, T, R, A}` asserts each argument to its site type (julia-1.13 6d480d0753). Acceptance G1.26: a mutable argument and result keep their identity and the caller sees the change, a result with a reference field arrives, a `Dynamic` argument. G1.26 failed on 711484a23e with the reviewer's error ("cfunction return type struct fields cannot contain a reference") and passes on 6d480d0753; 26 of 26 in both settings, every suite passes (`experiments/checks/logs/splittable-abi/`). Compiler §4.3 and the plan corrected. |
| 2 | The null check, with an error naming the cause. |
| 3 | Recorded: the `--trim` reuse of image code with a split table, beside C-14, in compiler §4.3's "Not in a trimmed program" (to verify when row 12 is built); C-3 stays as it is. |
| 4 | Not changed (low); noted here. |
| 5 | `facts.md`: the tests line (26 checks) and threads. |
| 6 | Adopted: `ODEProblem{T, P, R, D}` keeps the function at the duals as a typed field (`stored` at `DualSig{P, 8}`), the chunk fixed at 8; `fn::Any` and the per-call construction are gone (TraitDifferentialEquations 7ff312d). With it, TraitWorld makes a stored function's pointer at its first call (4834cfc), so the dual form costs nothing where Rodas5 is not used. |
| 7 | Traits §9: why `Callable`, and the trait-world function kept as itself; a test of `with_dynamic(f)` with Rodas5. |
| 8 | The example's docstring now leaves the user session's compilation to W-8. |
| 9 | The README names the limit. |
