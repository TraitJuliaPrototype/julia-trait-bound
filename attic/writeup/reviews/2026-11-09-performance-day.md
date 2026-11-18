# Review: the performance work of 2026-11-09 (night and day)

The user (2026-11-09): "Please send out a Fable review to look at all the performance work done today, and assess and review it."

Written by a Fable agent at the user's request, the exception to the rule against subagents on the shared host. Hostile but fair: every number below was checked against its log or commit, not taken from the session's write-ups. *Verified* means read in a log, a diff or a run of my own; *inferred* means reasoning from them.

**What was read:**
- the session notes [`2026-11-08-night.md`](../../session-notes/2026-11-08-night.md) and [`2026-11-09-day-io-trait.md`](../../session-notes/2026-11-09-day-io-trait.md);
- the 23 Julia commits of the day (`0ba6317994` to `b05ae361e0`) and branch `b-display` (`562b08ddb6`): the full diffs of `bf447db25e`, `43c222c751`, `0c836f3ef6`, `7bd8b6e512`, `1906196731`, `45fa624462`, `53ec4356bf`, `b05ae361e0`; the diffstats of the rest;
- the forks' commits `a8fe1b5` and `d196bed`; TraitWorld's `9a45c36`, `4443d2c`;
- the registry rows E-328 to E-338 with their "would change" clauses, and the design repository's commits that added them;
- the logs `experiments/unification/e289/logs/{f,forks,d,t}-*-w326b..w338*.log`, `e337-w337.log`, `e338-w338.log`, `e338-repl-tests*.log`; `e328/logs/e328-*-w337.log`; `stack/logs/w337-*.log`; the traced sessions `e323/session-traced-w337.out` and `-w338w.out`; `e326/trace-goal-w326b.jl`;
- compiler §3.1, §4.8, §5.1, §5.4, §7, §9 and the Deviations C-39, C-54, C-76 to C-81; traits §3.4, §9b; open issues §1 and 164 to 170; decisions §5 and §9; todo W-124, W-126, W-128, W-129; the plans on IO's alternatives and on compiled-once equations; the porting-lessons review;
- the runtime around the changes: `src/typemap.c` (`jl_typemap_level_insert_`), `src/gf.c` (`_invalidate_backedges`, `_invalidate_dispatch_backedges`, `jl_call_shadows`), `src/datatype.c` (the cells, `jl_membership_final`, `jl_has_unmet_argument`), `src/staticdata.c` (the cells and backedges in images), `src/builtins.c` (`Core.attributed_call`'s table), `src/method.c` (`get_next_edge`), `base/show.jl` (`IOContext`).

**Not read:** the night's C-27, C-70, C-63 and C-36 diffs line by line (their gates and E-320/E-324 were read); TraitWorld's source beyond the two commits; the ports' tests.

**What was run** (`source env.sh`, niced, one job at a time, load 4.6–5.5 of 128; scratch in `/tmp/claude-3147/-p-projects-coen-julia-trait-bound/24a7c1e0-a2ec-401b-8a6e-3d7a1561fce2/scratchpad/perf-review/`):
- `callable_unmet.jl` on the head: a soundness probe of the unmet-intersection rule (finding 4);
- the goal's task twice on the head with `--trace-compile-timing` (the first run precompiled `env_fu`'s images, 225 s: presumably the depot's images were stale after the system image was rebuilt at 22:22, following the E-338 arm), and `@time_imports` of its packages once.

No file but this one was written. No build, no benchmark longer than a few minutes.

## Summary

The day's engineering is of high quality and the record is unusually complete. Two things are wrong at the top:

- **The goal's task does not meet its gate on the head.** It is 1.76–1.80 s against a gate of 1.65 s, and 9 % slower than the build of the morning (E-326, 1.62–1.63 s). The record compares the head only with the early build (2.5 s) and `state.md` still says the gate is met. The slowdown is in the loads, not in compilation (my trace: the same 28 compiles as E-326, 301 against 273 ms), and it is independent of the forks' change (TraitReport (t) and the forks' arm (0) show it too). The suspect is E-336's `store_backedges` at load.
- **One rule built on the way is unsound, verified by a probe:** dispatch's lookup drops a match at an intersection it judges unmet by reading entries only. `Callable`'s memberships are methods, not entries, so `All{AbstractString, Callable}` counts as unmet while a string type with a call method is in it. Compiled code then runs the covering method where a dynamic call raises the ambiguity. At an open set the same drop has no cell, so a later membership leaves compiled code and dispatch disagreeing until the joint method is defined.

Beside these: B-display's largest gain, 0.38 s of the forks' `write` step, is in the logs and in no row; three logs name the wrong build; five rows were first committed with their outcome.

## Findings, by severity

### H1. The goal's task misses its gate on the head, and the record says it is met — verified

- The gate: the goal's task ≤ 1.65 s (Python + 1 s; [the plan](../plans/2026-11-08-python-speed.md) stage 3; W-125).
- On the head (`e289/logs/f-unified-w337.log`, `unified` b05ae361e0, forks a8fe1b5, load 6.3–6.4, a warm-up and 3 runs): **1.764, 1.803, 1.788 s**; imports 1.169–1.196 s.
- On the morning's build (`f-unified-w326b.log`, `unified` 6767b03893, load 2.7): **1.620–1.627 s**; imports 1.018–1.046 s.
- So the head is +0.14–0.18 s (+9 %), all of it in the imports (+0.15 s). The other steps are equal (read 0.045–0.048, summarize 0.15, plot 0.10, exit 0.11–0.12).
- The load does not explain it: the early build's form (f), run interleaved at load 6.3 (`f-early-w337.log`), gives 2.46–2.57 s, the same as at load 2.3–6.0 on 2026-11-08 (E-289: 2.46–2.49 s).
- The same shift is in sessions the forks' change cannot reach:
  - TraitReport (t): imports 0.324 s (w326b) → 0.373–0.407 s (w337); wall 0.73–0.78 → 0.79–0.83 s. Same TraitReport, TraitMakie and TraitCSV commits in both runs;
  - the forks' session with DataFrames unchanged (E-338 arm (0), forks 4824b4b as in E-326): imports 0.95–1.21 s against E-326's 0.82–1.06 s.
- What the record says: E-337's row and evidence §3 compare the head only with the early build ("faster than the early build"); `state.md` line 3 says the goal's task runs "within Python + 1 s", line 13 that stage 3's gate "is met", and its §5 table keeps 1.62–1.63 s in bold as the current number with the head's 1.76–1.80 s a bullet below, unmarked as a regression. The io-alternatives plan (§2.1) had already noted that no run since E-330 had a control at its load; E-337 added the early build as the control but not the morning's unified build, which is the one that answers "does Base still pay for the set machinery".
- **Proposal:**
  - `state.md` lines 3 and 13, its §5 table, evidence §3 and W-125's status say the gate is not met on the head: 1.76–1.80 s, +0.15 s against E-326;
  - the registry's convention gains a line: a session's row names the last unified build it was measured on as its baseline, beside the load's control;
  - the cause: finding M1.

### H2. The lookup's drop of an unmet match is unsound at `Callable`, and unguarded at every open set — verified by a probe

- The rule (compiler §5.4, `unified` 43c222c751, E-331): `drop_unmet_matches` in `ml_matches_i` (`src/gf.c`) removes a match whose argument is met only at an intersection `All{X, Y}` that `jl_has_unmet_argument` judges unmet, where a covering match exists that it is not more specific than. `jl_has_unmet_argument` → `all_type_met` → `set_entries_meet` (`src/datatype.c`) reads `jl_set_entries` only.
- `Callable`'s memberships are read from methods, not entries (compiler §7.4). So a string type with a call method is in `All{AbstractString, Callable}` while the rule says no type is.
- The probe (`perf-review/callable_unmet.jl`, run on the head):

  ```
  struct MyS <: AbstractString end; (s::MyS)(x) = 1
  f(::AbstractString, xs...) = :str;  f(::Core.Callable, ::Int) = :callable
  g(x::Core.Callable) = f(x, 1)
  ```

  prints `MyS <: Callable: true`; the lookup at `(Callable, Int)` returns one match, `ambig=false`; `jl_has_unmet_argument(All{AbstractString, Callable})` = 1; `f(MyS(), 1)` raises `MethodError` (ambiguous); `g(MyS())` returns `:callable`; `code_typed(g)` is `return :callable`. The same value gets an error from dispatch and an answer from compiled code: G1 ("identical or error") fails, with no later membership needed.
- At an ordinary open set the drop records no cell (E-334's final cell exists only for sets closed after load). A membership that meets the intersection later leaves the compiled caller running the covering method while dispatch is ambiguous, until the joint method is defined. §5.4 states this as the rule ("Until the joint method is defined, a call compiled before the membership runs the covering method for the new member"). That is a folded negative at an open set, which §4.8 forbids, written into §5.4 as if it were harmless. The ambiguity report warns; it does not keep G1.
- The rule was built for `All{AbstractString, IO}` with `IO` a set. `IO` is no set now. What remains is the general case, whose benefit (a static call at `describe(::ColTable)` against `describe(::AbstractString)` where the signatures are incomparable) is unmeasured on any port.
- **Proposal:**
  - a deviation row now (C-, §5.4): the drop is unsound for a `Callable` component and unguarded at an open set, with the probe as its gate case;
  - the fix at the rule: drop a match only where the pair is final (a set closed after load: E-334's `drop_unmet_final_matches`, which records the cell), and never where a component is `Callable`. At an open set keep the match, so the call stays dynamic, or give it a guard cell on the pair, as the equations plan's proposal 4 suggests. `jl_has_unmet_argument` stays for reflection, with `Callable` answered by its methods;
  - gate `n20_unmet_lookup` gains the probe and a case with a membership declared after compilation at an open set.

### H3. Five rows were first committed with their outcome, and three logs name the wrong build — verified

- CLAUDE.md: "The row comes before the run: the question, and the result that would change the design." The design repository's commits that touch `experiments.md` today (`git log -- writeup/record/experiments.md`):
  - E-328 registered 09:12, done 09:19; E-331 added as *running* 14:27; E-335, E-336, E-337, E-338 registered 17:56, 18:30, 20:14, 21:55, each before its run. Good.
  - **E-329, E-330, E-332, E-333, E-334** first appear in the commits that mark them done (11:20, 14:27, 16:37, 16:37, 17:56). The session note says E-330 and E-334 were "registered before"; nothing in any repository shows it. Each has a "would change" clause, so the criterion may have been written first, but it cannot be verified.
- The build in a log's header is `git log -1` of the worktree at run time (`e289/run.sh`), not the binary's. The runs of E-334, E-335 and E-336 preceded their commits:
  - `f-unified-w334.log` (17:47) says `unified 7bd8b6e512`; the row says 1906196731 (committed 17:52);
  - `f-unified-w335.log` (18:07) says 1906196731; the row says 45fa624462 (18:17);
  - `f-unified-w336.log` (19:51) says 45fa624462; the row says 53ec4356bf (20:09).
  Rule 5 ("a number says what it measures: the build") is met by the rows and contradicted by their logs. The e328 logs do better: they print the binary's own `GIT_VERSION_INFO` (`53ec4356bf*` for E-337's binary, built from a dirty tree before b05ae361e0 was committed).
- The current `julia-unified/julia` is a third build (the system image is dated 22:22, after the `b-display` arm and the restore), not E-337's binary; my first run had to precompile every image of `env_fu`.
- **Proposal:**
  - commit the row before the run, as E-335 to E-338 did; where the build is in flight, the row says so and names the commit afterwards;
  - `run.sh` and `battery.sh` print the binary's `Base.GIT_VERSION_INFO.commit` with its dirty mark beside the worktree's head, and refuse a run on a dirty tree unless a label says `-wip`;
  - the three rows and evidence §3 note that the logs' headers name the previous commit.

### M1. Where the +0.15 s went: not compilation; the loads' own work — verified in part, cause inferred

- My trace of the goal's task on the head: 28 compiles, 301 ms in all (`summary_line` 132 ms, `_atexit` 34 ms, `first(Generator)` 15 ms). E-326's trace (`e326/trace-goal-w326b.jl`): 28 compiles, 273 ms, the same three on top (99, 34, 16 ms). So the imports' extra 0.15 s is not code compiled at load.
- `@time_imports` on the head: TraitWorld 67 ms (39 % compilation: about 26 ms compiled at its load, where E-326 reported none), Parsers 32, CSV 179, PrettyTables 106, DataFrames 307, CSV's InlineStrings extension 27, Colors 40, TraitMakie 34 ms. No per-package timing of E-326's build exists to compare.
- The candidates, by what changed between the builds and lies on the load path:
  - **E-336's `store_backedges` at load** (`Compiler/src/typeinfer.jl`): the backedges are now collected into a `Vector{Any}` of tuples, the duplicate check is still quadratic in a CodeInstance's backedges, and each call-signature edge allocates an `svec` at the `ccall`. E-336's own profile put it at 0.20 s of the goal's load after the fix (0.9 s before). No profile of E-326's build names its cost; *inferred* as the first suspect, since it scales with the images loaded, as the regression does ((t) +0.05, the forks +0.1, the goal +0.15);
  - the images themselves: every port was precompiled anew on the new build; code compiled under the split at `IO` and with call-signature edges may be larger. The sizes of the old images are gone;
  - `verify_method`'s final-cell branch and `_add_edges_impl`'s subtype test: negligible by inspection.
  - Not candidates: the typemap listing (E-335, faster by construction); `drop_unmet_matches` (one bit read per match without a set); the IO contract's reads (inference only); the system image's restore (startup 0.18 s in both).
- No load profile exists on the head: `audit/logs/profile-load-fu-*` ends at E-336's build. E-337 measured sessions and workloads but not the load's composition, although its own "would change" clause named "the profile" as the next step if Base still paid.
- **Proposal, cheapest first, no build until step 3:**
  1. `audit/profile_load.jl` on the head's goal load (one run, a minute), against `profile-load-fu-e336-flat.log`: the self time of `store_backedges`, `verify_call`, `jl_insert_backedges`, `jl_restore_*`;
  2. if `store_backedges` is 0.1 s or more: make the duplicate check linear (an `IdSet` of `(item, sig)` pairs) and stop allocating for the common case (one edge, `nothing` signature); that is a Compiler change, which needs only the system image rebuilt;
  3. if the profile points at restore or validation instead: one build of b05ae361e0 with 53ec4356bf's Julia side reverted (gate `n21` expected to fail), the goal's task and (t) on it. Only then a bisection over the four remaining builds.

### M2. B-display's largest effect is unreported: the forks' `write` step falls from 0.5 to 0.12 s — verified

- `forks-unified-w337.log` (the head, DataFrames erasing): `write` 0.505–0.515 s. `forks-unified-w326b.log`: 0.483–0.491 s.
- On branch `b-display`, all three arms (`forks-unified-w3380/w338w/w338e.log`): `write` **0.121–0.157 s**. The arm (0) has DataFrames' code and workload unchanged, so the REPL's three lines alone remove 0.38 s.
- The traced sessions confirm what moved: on the head the step compiles `show(::IOContext{LimitIO{TTYTerminal}}, ::MIME"text/plain", ::String)` for 134.6 ms (`session-traced-w337.out` line 447; E-318's case, the returned path displayed) plus `open`'s keyword body; on `b-display` the segment compiles 75.6 ms with no `String` display (`session-traced-w338w.out`).
- E-338's row reports the `show` step (0.087 s) and the session's wall (2.56–2.68 s against 2.95–3.56 s) and attributes nothing to `write`. The adoption item in open issues §1 says "the forks' `show` step 0.087 s" only. The session's wall gain is mostly the `write` step, not the `show` step. This matters for the user's decision: B-display removes a whole class (PE-25's: a value's display at the REPL's stream type compiled per session, invalidated or never in an image), not one package's case.
- **Proposal:** E-338's outcome, evidence §3 and the §1 item name the `write` step's 0.38 s and the `String` display; PE-25 notes that the arm removes its REPL half; W-126's forks gate (the steps ≤ 1 s) is met on `b-display` (the steps sum to 0.87 s in run 2 of `w338w`) and not on the head (1.24 s in run 2 of `w337`), which the queue should say.

### M3. The route through W-129 was built first and measured after; the proxy could not see what broke — verified

- Timeline: (a) built 10:41; (b) 12:35–13:44 after five builds; E-330's result 14:02; six fixes 14:43–20:09; the user asked for the alternatives plan; (c) built 20:31. About seven hours and six Julia builds between (b)'s first measurement and (c).
- E-328's proxy (a hand-routed split on vanilla) answered the per-call question and nothing else. The three costs that made E-330 ten times slower were structural and readable from the design without a build:
  - every method whose signature mentions a set goes into the root's linear list (the old comment in `src/typemap.c` said so: "its entry stays in the linear list, which every walk visits"); Base has 1,199 methods typed `IO`;
  - every method at an abstract Base type with a signature incomparable to a method at `IO` meets it at `All{AbstractString, IO}`; `detect_ambiguities` found 66 at once;
  - an instance compiled once is shared by every caller and carries every invalidation below its candidates.
  A census of Base's methods at `IO` (one `grep`), one `detect_ambiguities` run and the typemap report would have predicted E-330 in an hour.
- The porting-lessons review already draws L4, L10, L12. What it does not say: the "would change" clause of E-330 (a session slower by 5 %) was crossed by a factor of four, and the response was six fixes, not the question the user then asked. CLAUDE.md's "gates do not stop the work" is about a gate meant for the user; a registered criterion crossed by 4× is a result that changes the plan, which the row itself said.
- **Proposal:** a line in the registry's conventions: a criterion crossed by more than its own margin ends the experiment's line of work until the row's "would change" branch is taken or the user says otherwise; a Base-wide change gets a static census before its build (methods at the set, ambiguities, shared instances).

### M4. Of the general rules kept after `IO` left, two should be gated and one measured on the ports — reasoning

Which rules still earn their keep, now that no set is `IO` and no port opts into closed-after-load:

| Rule | Build | Earns its keep? | Proposal |
|---|---|---|---|
| Sets closed after load; final cells (§4.8) | bf447db25e, E-329 | Yes: the user's decision, opt-in; no cost without opting in (the bit is read first). One hazard: `run_package_callbacks` marks a package loaded before its extensions run, so a membership declared in an extension (CSV's InlineStrings extension declares 20) is always "late" and invalidates at every load once the set opts in. | Mark the package loaded after the extensions whose triggers are already loaded; note it in §4.8. |
| Dispatch's lookup drops an unmet match (§5.4) | 43c222c751, E-331 | No, as built (H2). | Restrict to final pairs; `Callable` answered by its methods. |
| The firewall: a branch through a pointer, only a leaf inlined (§7.2) | 0c836f3ef6, 7bd8b6e512, E-332 | Unmeasured where it now applies. Its cost is 1.5–2.2× per short write through `IOContext{IO}` (E-337: `"ab"` 1.40 against 0.92 ms, bytes 13.35 against 6.17 ms); its benefit (18,781 → 6,687 invalidated at load) was measured with `IO` a set. Every split of every set pays the pointer now: the ports' `Dynamic` paths, TDE's and NetworkDynamics' among them. NetworkDynamics was last measured on E-327, before E-332. | E-327 again on the head (new equations, steady state), a few minutes; then decide the rule, or the slot the equations plan proposes. |
| A call through a trait converts the result (traits §7.9) | 0c836f3ef6, E-333 | Yes, small, needed by `IO`'s contract (Core's streams return `UInt`). | Keep. |
| An unmet intersection final at a closed set, with `base/sysimg.jl`'s walk (§4.8, C-79) | 1906196731, E-334 | Dead until a port opts in. The `sysimg.jl` block walks every specialization of every method at each system-image build for nothing while Base declares no such set. | Keep the rule behind the opt-in; skip the walk when no set is closed after load. |
| A set's methods listed only at the set's position (§5.1) | 45fa624462, E-335 | Yes: general, sound by the level's invariant (every walk that reaches a level visits its linear list), cheap. | Keep. |
| A dispatch edge keeps the call's signature (§3.1) | 53ec4356bf, E-336 | Yes in principle: it also fixes vanilla's `@nospecialize` imprecision; the backedge readers I checked (`_invalidate_backedges`, `_invalidate_dispatch_backedges`, `jl_prune_mi_backedges`, the image writer's queue) handle the `svec` form. Its load cost is M1's suspect. | Keep; fix the duplicate check (M1). |
| A split's branch `Compiled` for its candidate; ambiguity reflection in the query's world; `jl_declared_methods_of` by the function's list | b133374e9d | Yes: each is a correctness fix found by `IO` that any set needs. | Keep. |
| `IO`'s contract on the closed type; `IOContext{IO}` | b05ae361e0, E-337 | Yes: the user's decision; four gates relaxed, one slot on the `TypeName`. | Keep; C-81 (a package's candidates lost at load) needs a plan before any port declares a contract. |

### M5. The flagged list misses the rule that caused E-330 — reasoning

- The flagged items in open issues §1 are right as far as they go: the guarantee with (d) opt-in; the compiler compiled plainly; a cast at an untyped parameter; B-display (a decision, not a cost). The `IO`-as-a-set item was rightly removed.
- Missing: **the attribute resolves at the method's declared type, not at the caller's knowledge** (compiler §6.3, step 4). A set whose default is `Dynamic` compiles its methods once, and a caller that knows the member's concrete type still reaches that instance. Measured: Base's writers 1.2–24× with `IO` a set (E-330, E-333); NetworkDynamics' steady state 2× until its batch kernel was typed by the trait (E-314). `IO` escaped by leaving the sets; TDE's and NetworkDynamics' sets have not. Facts §13.1's promise for plain code holds only because no plain Base type is a set.
- Missing: **the firewall's pointer per call** (167 (a), mine): a design choice that trades per-call speed for isolation from invalidation; it is in §1 as a choice but not under the flagged list, where its measured cost belongs.
- The B-display item should carry M2's number.
- **Proposal:** two flagged entries with the numbers above and the proposals already in 162 and 167; the B-display item amended.

### M6. E-338 is fair; its one untested claim is reasoning, not measurement — verified

- The arms ran on one build, interleaved between two controls, each with a fresh precompile, a warm-up and 3 runs; the digests and the REPL transcript were checked for (0) and (w); REPL's suite fails the same one test on vanilla (`e338-repl-tests-vanilla.log`: 2,328 passed, 1 failed, 6 broken, both). Good.
- "(0) near the per-type cost, so a workload at an `IOBuffer` does not cover `IOContext{IO}`": no arm ran DataFrames' `IOBuffer` MIME line without the erasing code on `b-display`. The claim follows from per-type compilation and I accept it; the row should say it is reasoning.
- The workload lines comply with the user's rule: `show(IOBuffer(), MIME"text/plain"(), df)` displays the library's own six-column frame (Int, String, range, pooled, Bool, Float64) by the entry the REPL takes, as upstream's `show(IOBuffer(), df)` already does; the `IOContext{IO}(IOBuffer())` line is the same at the erased type. Neither names the goal's shapes. The second needs a convention (170 (b)'s helper), else every package must know the eraser's spelling.

### L1. The IO contract's declared results change plain code's inference at abstract `IO` — verified in the code, already open issue 171

- `declared_operation_result` returns `Int` for `write(io::IO, ::UInt8)` wherever the receiver's inferred type is exactly `IO`, and the split converts. Vanilla infers `Any` there and returns what the stream returns. A stream whose `read(io, UInt8)` returns an `Int` now converts, and may raise `InexactError`. The documentation-consistency review raised it (H4 → open issue 171); it belongs with W-129 (c)'s last step, not later.

### L2. Small points

- E-337's TraitReport (t) run has no Python control: `t-unified-w337.log` shows `/nonexistent/bin/python` three times (PYENV wrong). The row's "within Python + 1 s" for (t) rests on E-326's Python numbers.
- (t) is at its stage-1 gate's edge: 0.79–0.83 s against ≤ 0.8 s.
- `Core.attributed_call`'s lock-free table (b61e326170): sound as read. The slot holds an immutable `svec` stored whole; readers check bits, world and the exact argument types; a definition advances the world and misses the table. Fine.
- `IOContext{IO}(ctx::IOContext)` unwraps because the inner constructor does so in vanilla 1.13.2 (no diff against 45b6d15e34), so `b-display`'s `IOContext{IO}(IOContext(LimitIO(…), io))` holds the `LimitIO`, not a context of a context. The session note's correction was right.
- The system image is rebuilt at every runtime change now (`tools-local/build.sh` touching `base/sysimg.jl`): right, and it cost one wrong measurement before it existed (E-334's first run).
- E-335's "imports 2.22–2.29 s, at E-329's level": E-329 ran at load 30; the comparison means nothing, as L10 of the porting-lessons review says.

## The questions, answered

1. **Soundness of the experiments.** The criteria are explicit and the outcomes report against them, including the failures (E-329 unresolved, E-330 crossed, E-332's wrong proposal). The numbers in the rows match their logs everywhere I checked (E-328 to E-338: the goal's task, the forks' steps, D, (t), the workloads' ratios). Three weaknesses: five rows first committed with their outcome (H3); three logs naming the wrong build (H3); E-337's criterion registered against the early build, so the one comparison that answers its own question (against E-326) was never made (H1).
2. **Against the gates on the head.** The goal's task 1.76–1.80 s: **not met** (≤ 1.65 s), +0.15 s against E-326. The forks' session 2.95–3.56 s on the head, 2.56–2.68 s on `b-display`; the steps ≤ 1 s met only on `b-display` (M2). Setting D 1.96–1.98 s: met. TraitReport (t) 0.79–0.83 s: at the edge. The regression is real, in the loads, not in compilation; M1 names the cheapest path.
3. **Principled and correct?** Closed after load, final cells, the typemap listing, the call-signature backedge, the contract slot and the eraser are rules at the right place and sound as read, with the caveats in M4 (extensions declaring late; C-81). The unmet-match drop is unsound (H2). The firewall is a rule with a per-call price whose benefit is unmeasured where it now applies (M4). The unmet-final-negative machinery is dead code with a walk in the system image's build (M4). Threads and images: the final cells are locked and serialized correctly; `Core.attributed_call`'s table is sound; the pointer targets dispatch in the caller's world.
4. **The route.** Inefficient by about a day of builds, for reasons a static census would have given in an hour (M3). Of the rules built on the way: keep E-333, E-335, E-336 and the `Compiled` branches; restrict E-331 to final pairs; gate E-334's walk; measure E-332 on the ports before stating it as §7.2's rule.
5. **The workload rule.** Both lines comply; E-338 is fair; its `IOBuffer` claim is reasoning (M6).
6. **The flagged decisions.** Right, incomplete: the step-4 attribute rule and the firewall's cost are missing; B-display's item understates its gain (M5, M2).
7. **What next,** by expected gain per complexity:
   1. **M1's diagnosis** of the goal's +0.15 s: one profile, no build; a one-function fix if `store_backedges` is it. The headline gate depends on it.
   2. **B-display's adoption** (the user's decision): about 0.5 s of the forks' session (0.1 s `show`, 0.38 s `write`) for three lines in REPL, one in `TextDisplay`, and a convention for the workload line; W-126's forks gate met with it. The visible change (`show` sees `IOContext{IO}`) is the only risk, and REPL's suite passed.
   3. **H2's fix** (restrict the drop): correctness, small, and it removes a rule's worth of code at open sets.
   4. **E-327 again on the head** (NetworkDynamics): decides whether the firewall's pointer stays as §7.2's rule or the slot replaces it (167). A few minutes.
   5. **W-126's goal gate** (after the imports ≤ 0.2 s, now 0.30 s): 0.13 s of it is the script's own `summary_line`, which no image holds; the stage's own text says it is Julia's floor for a script's own code. State it, and move the lever to the imports.
   6. **Open issue 170** (C-39): ≤ 44 ms of the `show` step, and 7 ms once B-display is adopted. After 2.
   7. **W-124's remainder** (setting D's first solve 0.27–0.30 s against ≤ 0.2 s): PE-27's generator and the user's right-hand side; medium work for 0.1 s on a session already within its gate.
   8. **W-128's rest**, with the new rows: C-76 to C-79, C-81, and H2's row.
