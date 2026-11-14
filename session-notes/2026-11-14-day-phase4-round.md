# 2026-11-14, the day: bin A emptied, phase 4, the measurement round begun

Continues [`2026-11-14-night-binA.md`](2026-11-14-night-binA.md). The user's words that direct it (2026-11-14): "We don't build the cross session cache now. The measurement campaign should contain workloads that would exercise it and break down times in such a way that we can make a clear judgment. Please continue with the rest of the work as planned in the order we planned." Done in the main session, no subagents.

## Bin A's rest

- **T-102 closed** (TraitWorld 78da5cb): `like`'s rebuilding of a forwarding member is a method made at its `@implement … by f`; `withfields` makes the constructor's call when compiled. Nothing is looked up when they run: both are fully typed, and work on a member of a precompiled package (stack gate `like_precompiled`). A missing positional constructor is Julia's `MethodError` with a hint. Lowering §8; traits T-102 retired.
- **The rest sorted** (mine; the schedule's addendum "bin A is empty", decisions §8): to the synthesis C-88 (c), (e) as GT-18, C-90 as open issue 182, C-41, F-24, open issue 178, T-109; accepted C-30, C-31, C-45, C-49, C-50, C-86, C-87, C-88 (d), T-96, L-56's rest. The prototype is conceptually complete.

## Phase 4: the demonstrators on the head (E-373)

`experiments/unification/w104/` (`suites.sh`, logs, README). Every suite passes or has its known failures (state §4).
- Changed in the ports to follow the design: `@unbounded` for `@open` (forks, NetworkDynamics); the cast `compiled_for` imported in NetworkDynamics (its name is bound, not reserved); the ODE port's callbacks stored without `keep`.
- **The tool over-reported:** `detect_kept_storage` listed a `Dynamic` a method makes itself (TraitMakie's nine). It lists a `keep`'s value only (TraitWorld baadf9f).
- **A fault at a rule, found by the ODE port's front end:** a result annotation at a trait, `f(…)::X`, was inferred as `Any`. The annotation's lowered code tests `x isa X`, and a test at a set refined neither branch. It narrows the true branch now (`unified` 86deee2f98; compiler §4.8; gate `n31_isa_narrows`; the battery passes).
- **Open issue 183:** the ODE port's front end is kept from inference by hand (`@nospecializeinfer`), so its program is not fully typed (4 calls, one cause), with or without a cast. For the ports' lessons (W-147).
- NetworkDynamics' clones cannot be pushed (their `origin` is upstream): `ndport/pkgs-bundles/make.sh` writes the bundles, committed in `ndport`.

## Phase 5: the freeze and the round (W-145)

- [The round's plan](../writeup/plans/2026-11-14-measurement-round.md): the frozen build (tag `round-2026-11` in every repository), the rules, eight parts.
- **Part 1, calls (E-374):** parity where the types are known, but a call with the cast `compiled_for(f)` at a `Callable` is not inlined (1.34 against 0.79 ns). A cast `with_dynamic` at a call from typed code is a run-time call with the result `Any`: 344 ns. Both on phase 6's list.
- **Part 2, the cache workloads (E-375):** two independent generated packages first combined in a session, six cases of who declares the membership, three forms. Plain Julia compiles the library's algorithms at the other package's type in every session unless a workload names the combination; the trait form compiled for the type has them in the declaring package's image with no workload; the form compiled once never compiles them. What is left in every form is the session's own code and Julia's methods at its signatures. The cache plan's second addendum has the table for the judgment.
- Parts 3 and 4a started (E-376 to E-381).

## A mistake to know of

`experiments` commit 50d2634 holds the cache workloads' depot (48 files, 56 MB of compiled images) and the generated packages: `git add -A` took them. The next commit (fd431af) removes them from the tree and ignores them. The history still carries them; a rewrite of the pushed history was not done (a force push was refused by the session's permissions). For the user to decide.

**Later the same day:** the user: "Rewrite the experiments history please." Done: the two commits after f4db3a9 are rebuilt without the depot and the generated packages (5b24871, 5abba4b; the same trees and messages) and pushed with a lease. The old head dee896e is kept locally under the tag `pre-rewrite-backup`, not pushed.

**The round was stopped** on the user's word ("Please stop and report back after the Ports are up."): parts 1 and 2 are done; parts 3 to 7 (E-376 to E-386) were stopped before any measurement and their rows still say "running".

## The ODE port's front end, reworked (E-387)

The user: "Rework the front end of ODE. Could the old front end become a thin compatibility shim? In an extra package maybe?"

- **The port** (TraitDifferentialEquations 0483ac0): `ODEProblem`, `remake`, `solve`, `init`, `solve_ode`, `init_ode` are typed; the property readers (`_system`, `_mass_matrix`, `_jac_prototype`, `_problem_callbacks`, `_names`) dispatch; the problem keeps whether its mass matrix is the identity; the type's parameters are written out where a problem is made. The suite passes; NetworkDynamics' subset is unchanged.
- **A rule of the design was in the way, not the port:** code compiled once that passes its trait argument on (to another method, or from a keyword method to its body) is a call made when it runs, and a closed build refused it. So no port could make `ODEProblem(f, …)` at `Callable`'s default typed for a build. Changed at the rule (mine; compiler §7.6, `unified` 21c9b33e39): a closed build compiles a trait argument for its type wherever the call knows it.
- **A fault found on the way:** a cast at a call of a parametric type's constructor was dropped in compiled callers (the same commit; gate `n6_attribute`).
- **The report** named the session's cause for a call the build compiles: fixed (TraitWorld 2072e75).
- **Numbers:** the ODE session 1.25 → 1.33 s; the build's errors on the ODE program 122 → 50, none in the front end. Open issue 183 closed; open issue 184 holds what is left (the core's callbacks first).
- The battery passes on 21c9b33e39 (label `fe`; its TraitWorld run failed on an interim edit of the library and passes on 2072e75).
- The round's freeze is lifted (the plan's addendum); E-376 to E-386 are registered, not run.

## The round resumed and done (E-374 to E-386)

The user: "Then continue the measurement round." A second freeze (tag `round-2026-11-b`, `unified` 21c9b33e39); parts 1 and 2 run again with the same numbers, then parts 3 to 8.

- **Holds:** the demonstrators' trait packages lose no instance to nine unrelated loads, twenty member packages or a prompt's definitions (E-376 to E-380); plain code pays what it paid (E-381); the table program builds and runs, the ODE program counts 50 errors and runs under `unsafe-warn` (E-383); the messages are unchanged (E-385); NetworkDynamics' digests are identical (E-386).
- **The round's finding:** the membership walk's conservative path (compiler C-88 (c)) ends 1,069 instances at the forks' load (Base 749, DataFrames 240, Statistics 80). The first `describe` costs 0.80 s against 0.14 s without the walk (`experiments/unification/w145/loads/walk_work.jl`). It explains the forks' slower first work and session.
- **A wrong finding, withdrawn the same hour:** the first batch of TraitReport's trait form and setting D read loads twice those of `unified` b05ae361e0 (0.71–0.77 s against 0.37–0.41 s; 0.94–0.96 s against 0.54 s), and the design repository's commit 3d5f6a9 says so in its message. Run again at load 0.8 they are 0.39–0.40 s and 0.57 s. The first batch ran at load 5.6, and TraitReport's script had no warm-up: a process after another environment's run reads its images slowly (0.67 s, then 0.39 s). `e289/run.sh` warms that batch up now. The forks' numbers repeat.
- **Mistakes of the harness, corrected:** `load.jl` counted code instances where the log holds method instances; `w136`'s summary read the run's own output file; the first run of the forks' and upstream's REPL sessions included a precompile (runs 2 and 3 count).
- Each tension's cost: evidence §4c. Phase 6's list: W-146, seven items.
- **Next:** phase 6 (W-146), first the two losses above; then W-147 and W-138.

