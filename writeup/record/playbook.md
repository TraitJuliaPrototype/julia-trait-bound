# The playbook: how the work is done

This page is in the agents' tier ([the record's index](INDEX.md)). [`CLAUDE.md`](../../CLAUDE.md) holds the rules; this page holds the know-how: how to build, check, measure, review and record, and the traps met so far.

- Setting up a machine: [`../setup.md`](../setup.md).
- Why the rules are what they are: [the project's context](context.md).
- A trap's story, where one is cited as L-n: [the harvest notebook](harvest-2026-11.md).

## 1. Picking up the work

Read, in this order:
1. [`CLAUDE.md`](../../CLAUDE.md), then [the context](context.md) §2 and §5.
2. [The goals](../goals.md) and [the state](../state.md).
3. [The work queue](todo.md), and the plan it names as running.
4. The latest session note, from its last bullets backwards.
5. The references, each with its Deviations table, when the work touches a rule.

Before changing anything:
- `git status` in every repository the work touches. A tree is never the only copy of work: commit and push each day's work.
- Check which tree an agent or another session is working in ([the running plan](../plans/2026-11-15-next-iteration.md) §6).

## 2. Building Julia

- `source env.sh` first on a shared host. Then `tools-local/build.sh <tree> [make target]`, alone. It chooses the width by the machine's load, nices the build, guards memory and time-stamps the log.
- **Check `BUILD EXIT 0`** at the end of `<tree>/tw-build.log`. An error inside the system image's build leaves no crash message.
- **Commit, then build.** A binary built from an uncommitted tree names a commit it was not built from, and every log line that prints the version is then wrong.
- **After a change to a struct's layout,** delete the staged system images.
- **A closed build is checked by a build.** A change to how a demonstrator erases or specializes is checked with `experiments/implementation/w166/build_c.sh table` as well as the suites: a session's suites cannot see what a closed build compiles differently.
- **A trimmed build needs the program's package images, written by the same Julia.** After a rebuild of Julia none is valid, the build loads the packages from source, and it runs no `__init__`: it then stops in a package's top-level code. `build_c.sh` writes the images first and names any package still loaded from source.
- **The script rebuilds every image stage when a runtime source is newer.** Julia's make does not. The first stage (`basecompiler`) stores Core's types with the state the runtime's start gave them (`post_boot_hooks`: a set's bits), so a rebuild of the later stages alone runs on the old state.
- **A build that takes twice its recorded time** is stopped and bisected, one build at a time (`WIDE=0`).
- **Every package image is rebuilt after a build.** The first run of anything includes precompilation. Run a warm-up before timing.
- **Do not edit the library while a job loads it from source.**
- **No `Pkg.update`, `Pkg.add` or `Pkg.gc` in the workspace's depot without need.** Pkg's automatic clean-up keeps only the packages of manifests Pkg itself has operated on in the depot. Most environments here are only loaded, so it removed 157 package installations that they need. `env.sh` turns it off (`JULIA_PKG_GC_AUTO=false`). What is removed comes back from the file system's nightly snapshot (`/p/projects/coen/.snapshots/<day>/julia-trait-bound/.julia-depot`); `experiments/tools/depot_check.jl` lists the packages a manifest names that the depot lacks.

## 3. Checking a change

In this order, each a few minutes at most:
1. The gates that concern the change (`experiments/implementation/gates/run_all.sh <tree> '<pattern>'`), then all of them: `run_all.sh <tree>` with no pattern runs every gate in force and every stage gate. That command is what "the gates pass" means.
2. The library's tests, as a file: `julia-next/julia --startup-file=no --project=TraitWorld TraitWorld/test/runtests.jl`. Not after `using TraitWorld` in `Main`: a test must not rest on what `Main` has loaded (a message prints `Core.Dynamic` where `Main` does not see the name).
3. After a change to the library or a port: the four trimmed programs, `experiments/implementation/w158/m-builds.sh <label>` (0 errors, each output equal to a session's). The gates build trimmed programs with the stub library only.
4. After a change to Julia's sets, memberships, dispatch at sets or the compiler's folds: the set-folds report, `julia-next/julia --startup-file=no experiments/implementation/audit/set_folds.jl` (about three minutes; 0 mismatches), and its image mode `set_folds_images.jl`.
3. The examples of `intro/` (`experiments/docs-examples/`).
4. One or two demonstrators' suites, chosen to reveal a regression first.
5. Base's four test files against the vanilla control (`experiments/implementation/e262_suites.sh`), for a change to the type system, dispatch or inference.
6. Julia's static check of GC roots over the changed runtime files (`experiments/implementation/w163/sagc.sh`; 0 findings on the head, as on vanilla) and the globals' roots (`roots.sh`), for a change to the runtime's C code.

**Testing a compiler change** (L26, L27, L36):
- Test at concrete argument types, and by what the runtime compiled. Reflection on the abstract signature, or after a run, shows something else.
- A claim "the same as plain Julia" is checked by a redefinition, in both modes.
- A check of a guarantee counts the code the guarantee is about.
- A deviation row gets an expected-failure check, or nobody re-verifies it.
- A decision that replaces a rule names the gates that pinned the old one. A gate must discriminate: it fails on the tag's Julia where the rule differs, or a wrong assertion fails on the head.

**Auditing code you did not write** (L88): by probes, not by its gates. Gates pin the defects their author believed in.

## 4. Measuring

**Before the run.**
- The registry row first: the question, and the result that would change the design. If the outcome takes the other branch, the plan changes or the row says why not (L72).
- A cheap vehicle first, minutes. A campaign waits for a freeze (`CLAUDE.md`).
- Read the harness's code. Measurement plans fail in the same few ways (L61, L71):
  - settings that share a working tree or a depot. Julia keeps ten cache files per package, so one setting evicts another's;
  - an image that is stale: `--compiled-modules=existing` then loads from source without a word. Make the harness fail on "Precompiling" and on a missing image;
  - a check without a control;
  - a timer that reads zero unless it is switched on (`Base.cumulative_compile_time_ns`);
  - state carried from one run to the next (a parameter vector a solve mutates);
  - a cache measured on the session that recorded it;
  - settings that differ in five things at once;
  - a criterion that cannot be decided.
  - a digest made with `hash`: the hash of a value of a package's type mixes in the type's identity, which differs between two cache files of that package. Digest the printed form.

**The run.**
- Fresh processes, one per cell. State the build (commit), the setting, strict mode, the load order, the number of runs, the machine's load.
- The control is plain Julia on the same code (vanilla v1.13.2, or plain code on the build), or Python. A comparison with an earlier iteration is a regression control and stays with its gate.
- Say whether a number measures interop or idiomatic trait code.
- Time each step a second time in the same session: a first call is compilation plus run time (L105).
- Check `/proc/loadavg` before and after. On a shared host a number moves with the load; counts do not.

**Reading the result.**
- Profile before attributing, and before judging a design by a first number. A tenfold loss was one "rare" path taken for the normal case (L90). Put a counter on every path that is supposed to be rare.
- A go or no-go on speed needs a correctness run in the same setting (L15).
- Logs are committed, in `experiments/<dir>/`. `/tmp` and a scratchpad are not durable.
- A finished experiment: its registry row and its evidence row in one commit.

## 5. When something fails

- Name the pattern and the rule that produces it. Propose the fix at the rule (`CLAUDE.md`, "A failure names a pattern").
- Where the pattern can recur, build the tool that finds every instance, and keep it in `experiments/` with a README. Tools built this way: the audit's probes (`implementation/audit/`), the dispatch profiler and `fully_typed`, the cause tool for lost code, the documentation lint (`tools/doclint/`), the static check of GC roots and a collection forced in a suspected window (`implementation/w163/`).
- Correctness ranks above every performance item (L39).
- A slowdown is recorded as a tension, not fixed at the case.

**Traps met, by kind.**
- **Silent and slow, not wrong:** a package that leans on Base folding a type computation; a plain caller's constant propagation into a `getproperty` switch (L54, L55). Found by the dispatch profiler.
- **Machinery that every call site reaches** must not specialize on what the site passes (L104).
- **A hook put into the runtime's C code opens a window.** A value a C function holds in a local, unrooted because nothing allocated before it was stored, is freed once a call that allocates or runs Julia code is placed in between. Found as a crash in one run of three; the static check finds each instance (`experiments/implementation/w163/sagc.sh`, with vanilla as the control).
- **Whatever caches a dispatch answer carries its world** (L16).
- **A raw pointer in an immutable struct survives into a package image** (L39). **Through a typed pointer a struct by value is a copy** (L50).
- **Code loaded at first use is invisible to the rest of the calling function** (world age); an entry that may load code goes through `invokelatest` (L70).
- **A type that ordinary code reads as an ordinary type** must be right wherever it is not special-cased (L89).
- **A change that touches Base** is checked against the guarantees for plain code before it is built (L95).

## 6. Plans and reviews

- **A plan** has a status line, the user's words that asked for it, the rule it changes, the gates, what changes in the record. It is not normative.
- **A hostile review before the build** pays for itself. The pattern that fixed eight unsound rules in one night: a plan, a review by an independent agent, the review's changes, then the build (L96).
- **A reviewer** reads the code, not the plan's claims; marks each statement verified or reasoned; runs probes of seconds; ranks by "a false statement about what is built" first.
- **A design's claim about Julia's internals** is checked against the code at the place named, by a second reader (L86).
- **A review is not edited** after it is written, except by a dated addendum. What was done with each finding is recorded where it was done, and listed in the review's addendum.
- **A fresh-eye review of a reference:** read it as an outsider, check each "Implemented" against the code, look for sections that contradict.
- **For a simpler design:** a brief with the goals and the lessons and none of the mechanisms, to independent designers (L100).

## 7. Working with agents

- **When:** only where `CLAUDE.md` allows. An agent starts no agent of its own.
- **One tree per agent.** Two agents never change one tree. The plan names who works where.
- **Each agent gets:** the plan, its rows, its gate, its range of IDs (deviation rows, experiments, open issues), and the rules of `CLAUDE.md`. It records as the main session would: the registry row before a run, the reference before the build, its own session note, the work queue's row.
- **The design repository:** an agent works in its own worktree on its own branch, merges `origin/main` and pushes to `main`.
- **`experiments`:** each agent in its own directory; a commit names its paths.
- **The main session** owns the merges, the gates after a merge and the report to the user.
- **What an earlier attempt showed** (`attic/oc-notes/`): reviewers of a change must see the diff and run probes; the notes must not be the only place a result lives; a bisection needs a baseline that was built and timed.

## 8. The record

- Every kind of fact has one home (`CLAUDE.md`, the table). Before finishing, grep every repository for the IDs, terms and numbers you changed.
- A decision: the reference first, then a row in the decision log with the user's words verbatim.
- A choice made while building: the reference, the decision log marked "mine", open issues §1.
- A session note per session: the user's words in full, every number with its commit, what is left.
- IDs are permanent. A retired row stays as its ID in its ledger.
- The lint: `python3 experiments/tools/doclint/doclint.py`. Its counts are zero for the current documents, or listed.

## 9. Git

- **Never `git add -A` beside a build tree or a depot.** A baseline tree was committed that way once.
- Commit with paths. Push when a piece of work is done, in every repository.
- **Where an agent works in the same repository, commit with a pathspec** (`git commit -m … -- <paths>`): a plain `git commit` after `git add <paths>` also takes what the other has staged.
- A worktree of the julia repository per line of work; the baseline's tree is changed by nobody.
- Before deleting a branch or a worktree: `git branch --merged`, `git log <branch> --not --remotes`.
