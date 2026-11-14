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
