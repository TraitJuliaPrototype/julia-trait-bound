# Pick-up note: bin A in progress (2026-11-12, stopped at the user's word)

The user (2026-11-12): "Come to an end at the next natural stopping point and write a pick up note for the next session to continue from."

The mandate still in force: "Okay keep going until the numbers of phase 3 are in. When they are in only get back to me if they actually indicate a trade off. If they suggest a clear path of action take that and continue."

## Where the work is

**Done, verified and pushed today** (on `unified` of `julia-unified` and TraitWorld, `main` of the design repository and the experiments):
- W-141 decided: a membership behaves as a method; its method of `Core.implements` is the edges' implementation (`unified` 8b4fde6e84).
- A pirate's membership follows the pirate method's rule (`unified` 7fee959383, TraitWorld a2ca7be; traits T-112).

**In progress, not verified, not on `unified` or `main`:** branch `binA-wip` in five repositories (`julia-unified`, `TraitWorld-unified`, `TraitDifferentialEquations-unified`, `experiments`, the design repository). **The built Julia in `julia-unified/` is this branch's build, and it has a known fault (below).** To get a good tree back: check out `unified-w141` and run `tools-local/build.sh julia-unified`.

The checkouts are left on `binA-wip`.

## What the branch holds

| Item | Change | State |
|---|---|---|
| W-142 (1): the report is the build's check | `Compiler.closed_check(mis, world)`: the closed build's rounds and verifier, run in a session under an owner of its own (`NativeInterpreter(…; closed = owner)`, every method plain). `closed_build(interp)` replaces `closed_build()` at the five rule sites. TraitWorld's `fully_typed` and `verify_main` take their sites from it; the mode's hook raises only where it refuses | works: 2 to 3 s a program; `w142/agree.sh closed` on build 1: 11 of 13 agree (was 7) |
| W-142, the two that differed | `family_trait`: `ci_has_source` did not put the check's own code into the codegen cache (fixed in `typeinfer.jl`). `ft_plain_hole`: the real build refuses `repeat(::Char, ::Int)` because a body inlined from the system image names its `:invoke` target as a `MethodInstance`, which `collectinvokes!` did not queue and the verifier refused. Changed both (`typeinfer.jl`, `verifytrim.jl`) | **the fault:** `collectinvokes!` is shared with `add_codeinsts_to_jit!`, which now meets a `MethodInstance` and fails (`MethodError: ci_has_invoke(::MethodInstance)`), in any session that shows an error. Fix: queue the instance only in `compile!` (a keyword), or skip it in `add_codeinsts_to_jit!` |
| W-142 (4) | `make_executable` and `make_library` run the check first (`_check_before_build`) | written, not run |
| Open issue 160 | The casts' names are not reserved: lowering emits `if compiled_for === Core.compiled_for … attributed_call … else the ordinary call` (`src/julia-syntax.scm`); gate `n6_attribute` rewritten | gates `n6`, `n13`, `n30` fail on build 2, an `UndefVarError` behind the fault above. Not yet read: probably a module that writes a cast without the name bound |
| C-88 (a) | The edges of `Callable` matches are recorded where the IR interpreter infers a call again (`record_callable_*!` take any `AbsIntState`) | built, no gate case yet |
| Open issue 177 (b) | A check's error is returned by the definition hook and raised by the runtime (`jl_call_definition_hook`), and raised by `@implement`'s own code at the caller's line | built; **the library and the runtime change go together**: with an older runtime the hook's errors would be dropped |
| Open issue 177 (a) | `OperationError` in place of the hand-thrown `MethodError` of a trait's method | written; tests that expect `MethodError` not yet updated |
| Open issue 176 | `@open` renamed `@unbounded`, "open method" to "unbounded method": library, tests, the ODE port, the docs examples, references, glossary, intro | text done; suite not run to the end |

**Checks on build 2** (`experiments/unification/w142/logs/`): gates 66 pass, 12 fail (the nine `m3_*` as before, and `n6`, `n13`, `n30`); TraitWorld's suite stops in `fullytyped.jl` with two failures: the report names the build's site inside Base (`reducedim.jl:999`) and no longer the root cause "field `data` of `Holder` is declared AbstractVector". The session walk's cause is used only where its site has the same file and line as the build's. To fix: where the build's site lies below a call the walk reported, give the walk's site and cause for it.

## Next steps, in order

1. Fix the `collectinvokes!` fault; rebuild (`tools-local/build.sh julia-unified`, about 10 minutes; do not edit `Compiler/` or `src/` while it runs).
2. Read the cast gates' failure; fix; gates back to 69.
3. The report's root causes (above); the suite to the end; update tests for `OperationError`; a gate case for C-88 (a); a test that a check's error has the user's line as its first frame.
4. `w142/agree.sh` to 13 of 13; build and run `w139/apps/zz_repeat.jl` (does a build with a `MethodInstance` invoke run?); then TraitTables' table program and the ODE port's (W-142 (5)).
5. Record, in one commit per decision: traits §14, §16, T-100, T-107, T-109; compiler §2.7, §6.9, §7.6, §10.1, C-88; traits §7.3, §7.6, §11.3; decisions marked mine (the check as the build's own run in the session; unreserved cast names; `@unbounded`; `OperationError`; errors raised at the user's line); alternatives (the check in a child process: exact, but a build's constraints on what can be checked); open issues 160, 176, 177 (a), (b) closed, 167 and 168 closed on re-reading (their rules are in compiler §7.2 and traits §5.10), 173, 115, 116 re-read; `julia-changes.md`; E-rows. Then merge `binA-wip` into `unified` and `main`.
6. Bin A's rest: W-143 (the holes under the demonstrators' programs), open issue 2 re-read.
7. Phase 3, first step: what a session still compiles that no image holds. Tools to start from: `experiments/unification/e312/` (the census of a session's compiles, the G2 bit), `e289/` (the sessions), `--trace-compile` with timing. Only TraitTables and the ODE port run on the head; the other ports are phase 4.

## Choices made on the way, to record with step 5

- The check is the build's own code run in the session, not a second walk and not a child process. A child process would be exact by construction but takes only what a build can load (a file's `main`, a package's function).
- Fully typed mode's check in compiled code stays the session's rule; its hook asks the build's check and raises only where that refuses. What the session's inference does not see as a run-time site is still not raised (T-100).
- A build limit (more than 64 members) is a fault of both by construction.
