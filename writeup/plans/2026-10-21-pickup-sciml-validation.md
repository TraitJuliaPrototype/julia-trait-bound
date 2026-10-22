# Pick up here: the night's results, then W-40 and the port

Status: **current; the pick-up note for the next session** (rewritten 2026-10-22, end of session 33). Read this note, then the documents it names. The session note: [`../../session-notes/2026-10-22-33-decisions-and-validation.md`](../../session-notes/2026-10-22-33-decisions-and-validation.md).

## First: the night of 2026-10-22/23

- `experiments/overnight-2026-10-22/tonight.sh`, started by the user outside the sandbox: the W-41/W-43 build (julia-1.13 fa4e7f5798), the facts system image, every suite and check (`experiments/checks/run_all.sh w41-w43`, with acceptance G1.30, G1.31), then W-39's measurements E-162–E-164 on the new build (TraitWorld 4410407).
- **Read** `experiments/overnight-2026-10-22/logs/driver.log` first (a line per step; "STOPPED" names a failed step), then `logs/checks.log`, then W-39's summaries in `experiments/overnight-2026-10-21/logs/` (`e162-summary.txt`, `e162-orderB-summary.txt`, `e162-digests.txt`, `compare-*.log`, `demos/`, `hetero-idiomatic/logs/night1-*`).
- **Write:** the README's runs table; the registry rows E-162–E-164; the evidence; `ndport/README.md`; if the checks pass, retire facts F-15 and F-18 and set W-41, W-43 done (julia-changes, todo). Every environment's package images are rebuilt at first use on the new build.
- If the night did not run: start it again the same way (the README says how); nothing else depends on it.

## Where things stand

- **Decisions of 2026-10-22** (the decision log; open issues' closed items): 46 (unions split by Julia's cost model, W-43), 47 (a library's `convert(X, x)`, W-44), 49 (a family member's builder folded by the compiler, W-40), 51 (option (a+)), 52 (concrete evaluation crosses the modes, W-41), 54 (hidden parameters stay rejected; the bound at the field, W-42), 55 (a supertrait with parameters by name, done in W-46). The meta plan's choices 1–47 accepted; the rule "make a choice, record the pushback". Open for the user when wanted: open issue 56 (the builders' choices in W-45/W-46).
- **W-34, the SciML strategy** ([the plan](2026-10-21-w34-sciml-prerequisites.md)): E-156 (probes), E-157 (move 1 holds in form B), E-158 (move 2 works; its per-step cost, +1.35 µs and 1 kB with two callbacks, waits for W-40) done. TraitWorld fixed: T-5, T-63–T-67 (W-45, W-46).
- **W-32, the port** ([the meta plan](2026-10-21-networkdynamics-port.md)): G3 and the merge of P4 and P6 done (E-165): bit-equal, new equations 0.56 s, the session 65.9 s against upstream's 70 s. P4 step 3 part 3a done (E-166; W-49 in TraitWorld): the steady state 29.5 ms (upstream 15.3). The port works in `ndport/env_merged`, its trees on branches `port`; TraitWorld for the port pinned at `TraitWorld-port` (branch `w49`).
- **W-47,** making loads fast: registered, not urgent ([the exploration](../explorations/fast-loads.md)).

## The next session: what to do, in order

1. **The night's results** (above).
2. **W-40** (lowering §4.6, L-37): a design note first (how the compiler checks a family member and folds its builder while inferring a caller that knows its type), then the build on a following night. Move 2 and the port's operations on kept family members wait on it.
3. **TraitWorld deviations, small:** W-48 (T-69, T-70), W-50 (T-71, T-72); W-42 (the bound at the field), W-44 (a library's `convert(X, x)`).
4. **The port:** P4 step 3 part 3b (a user's own component types; [the step-3 plan](2026-10-22-ndport-step3.md), revised), then step 4 (`ODERHS` in form B).
5. **W-34:** W-36 (L-3, on move 3's path) before E-159; E-160; E-161 after W-40.

## Before starting

- `CLAUDE.md`; [`../record/todo.md`](../record/todo.md); [`../open-issues.md`](../open-issues.md) §1.
- **The machine:** one Julia job at a time through the lock. **In the daytime the user works in parallel:** every Julia run with `JULIA_NUM_PRECOMPILE_TASKS=1 JULIA_NUM_THREADS=1` and `flock <lock> taskset -c 0-1 ionice -c3 nice -n 19`. Full builds and long rounds at night, started by the user outside the sandbox (a job started from the sandboxed Bash tool dies with the command). [`../record/INDEX.md`](../record/INDEX.md), "Standing constraints".
- The user's standing rules for the port: the design is not changed by the port; agents may add highly orthogonal features; changes to existing designs go to the user; make a choice and record the pushback.
