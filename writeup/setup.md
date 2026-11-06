# Setting up the development environment

This page takes you from an empty machine to a working copy of every repository, a built patched Julia, and the point in the record where work continues.

**Checked on 2026-11-05:**
- The clone steps from GitHub into an empty directory, the restore of `ndport/pkgs/`, and loading TraitWorld on an existing build.
- On a shared RHEL 9 host (see [On a shared host](#on-a-shared-host)), every step on this page from an empty directory:
  - a cold build: `BUILD EXIT 0` in about 15 minutes;
  - TraitWorld loads and its tests pass;
  - the restore of `ndport/pkgs/`, and every `ndport` environment finds its path packages. None was loaded.

## What you need

- **System:** Linux on x86-64. The project runs on Ubuntu, with 16 cores and 30 GB of memory.
- **Disk:** about 3 GB for each built Julia, and tens of GB for `~/.julia` once the demonstrators are precompiled.
- **Tools for building Julia:** GNU make, gcc and g++, gfortran, python, perl, curl or wget, m4, awk, patch, cmake, pkg-config and which. On Ubuntu:

  ```sh
  sudo apt install build-essential gfortran python3 perl curl m4 gawk patch cmake pkg-config
  ```

- **The static C++ library:** the build links `libstdc++` statically. On RHEL it is in `libstdc++-static`, or in a gcc from environment modules.

- **Optional:**
  - [juliaup](https://github.com/JuliaLang/juliaup) and stock Julia 1.13.2 (`juliaup add 1.13.2`), for comparisons with unpatched Julia.
  - [uv](https://github.com/astral-sh/uv), for the Python baselines ([`experiments/ttfx/README.md`](https://github.com/TraitJuliaPrototype/experiments/blob/main/ttfx/README.md) names the versions).

## Clone the repositories

The design repository holds the others, each with its own history. Packages refer to their siblings by relative path, so they must sit side by side.

Any location works (see [Paths](#paths)).

```sh
mkdir -p ~/Repos && cd ~/Repos
git clone git@github.com:TraitJuliaPrototype/julia-trait-bound
cd julia-trait-bound

for r in TraitWorld TraitDifferentialEquations TraitMakie TraitTables TraitCSV TraitReport forks experiments ndport; do
    git clone git@github.com:TraitJuliaPrototype/$r
done
git -C TraitDifferentialEquations switch w34
ndport/pkgs-bundles/restore.sh
git -C TraitWorld worktree add ../TraitWorld-port w49
git -C TraitDifferentialEquations worktree add ../TraitDifferentialEquations-w96 w96

git clone --filter=blob:none -b trait-world-1.13 git@github.com:TraitJuliaPrototype/julia julia-1.13
```

- **SSH:** the commands clone over SSH, so that pushes work. To read only, replace `git@github.com:` with `https://github.com/`.
- **`TraitDifferentialEquations`:** its current work is on branch `w34`.
- **`ndport/pkgs-bundles/restore.sh`:** recreates `ndport/pkgs/`, the clones of the packages NetworkDynamics uses. Each comes from its upstream repository, with the port's branches, stage tags and worktrees added.
- **The worktrees `TraitWorld-port` and `TraitDifferentialEquations-w96`:** some `ndport` environments load from them (`env_*_pin` and `env_w96`; [`ndport/README.md`](https://github.com/TraitJuliaPrototype/ndport/blob/main/README.md)).
- **`--filter=blob:none`:** fetches file contents on demand, so the Julia clone stays small. Reading old files then needs the network.

## Build the patched Julia

TraitWorld and the demonstrators need the patched Julia. Stock Julia is not supported.

```sh
julia-1.13/tw-build.sh
tail -1 julia-1.13/tw-build.log    # must say: BUILD EXIT 0
```

- The script runs `make -j4`, niced, and kills the build if available memory falls below 4 GB.
- Allow about an hour for a cold build.
- Always check `BUILD EXIT 0`. An error in the system image build can leave no crash message.
- Rebuild only the system image with `TW_TARGET=julia-sysimg-release julia-1.13/tw-build.sh`.
- The test bed `all` needs a second system image, built by `experiments/factscompiler/scripts/build_facts_sysimage.sh`.

## Check that it works

```sh
J=$PWD/julia-1.13/julia
$J --project=TraitWorld -e 'using Pkg; Pkg.instantiate(); using TraitWorld; println("TraitWorld loads")'
```

Run TraitWorld's test suite for a fuller check:

```sh
(cd TraitWorld && $J --project=. -e 'using Pkg; Pkg.test()')
```

The checks to run after a change to Julia are in [the workflow notes](../session-notes/00-environment-and-workflow.md).

## The unified build

The unified design ([compiler §7](reference/compiler.md#7-traits-in-the-type-system)) is built from upstream Julia v1.13.2 (`45b6d15e34`) on branch `unified` of the julia repository ([the synthesis plan](plans/2026-11-05-unification-synthesis.md), W-97 to W-104). Its worktree, and a vanilla control for comparisons:

```sh
git -C julia-1.13 fetch origin unified
git -C julia-1.13 worktree add ../julia-unified unified
git -C julia-1.13 worktree add --detach ../julia-vanilla 45b6d15e34
tools-local/build.sh julia-unified
tools-local/build.sh julia-vanilla
```

- Copy `julia-1.13/deps/srccache/` into each new tree first to save the downloads.
- Until branch `unified` is pushed, start it from `origin/oc-build` (`-b unified c3f0b4bc11`).
- Its gates and acceptance cases: `experiments/unification/`.

## Paths

- **Environments:** they name their sibling packages by paths relative to the environment.
- **Scripts:** the session and check scripts of TraitReport, TraitMakie and forks, `experiments/checks/run_all.sh` and `experiments/factscompiler/scripts/build_facts_sysimage.sh` find the workspace from their own location. `TW_ROOT` overrides it.
- **Older experiment scripts and logs** still name the original location, `/home/hellmann/Repos/julia-trait-bound`. They record past runs.

Some environments have no committed manifest. They resolve when instantiated, so their package versions can differ from the recorded runs.

## Running Julia jobs

- **Slots:** `experiments/tools/jl [--name NAME] command…` runs a job pinned to a slot, with its own depot and a memory guard. By default it takes 16 cores in 4 slots, keeps its locks in `/tmp/claude-1000` and its depots in `~/.julia/agent-depots`. `JL_CORES`, `JL_SLOTS`, `JL_NOPIN`, `JL_LOCKDIR` and `JL_DEPOTS` change that on another machine.
- **Exclusive jobs:** use `jl --exclusive command…` for measurements and Julia builds.
- **Measurements:** recorded numbers belong to the machine they were measured on. On a new machine, rerun the baselines before comparing with [the evidence](design/evidence.md).

## On a shared host

On a machine shared with other people, without root:

- **`source env.sh`** in the design repository before working. It:
  - loads `gcc/13.2.0` from environment modules, for the static C++ library;
  - keeps the Julia depot in `.julia-depot/` inside the workspace;
  - limits Julia, make and `jl` to 4 cores, with no core pinning;
  - sets `$J` (the patched Julia) and `$JSTOCK` (stock 1.13.2 through juliaup).
- **Builds:** `tools-local/build.sh <julia tree> [make target]` (from the design repository). It applies the rule for cores by load ([standing constraints](record/INDEX.md)):
  - while the others' load is below half the cores, `make -j<half the cores>`; otherwise `-j4`;
  - a wide build whose others' load reaches half the cores is stopped and continues at `-j4`;
  - a narrow build pauses while the load is above 110 and resumes below 90 (`HI`, `LO`), as `tools-local/loadguard.sh <pgid>` does for any process group;
  - a wide build is a spike: its parallel compile phase lasts minutes. Sustained use (builds one after another, long jobs) stays considerably lower: `WIDE=0`, and at most 16 cores in all;
  - niced, killed below 4 GB of available memory; the log `<tree>/tw-build.log` is time-stamped per line, ends with the wall time, the sampled peak RSS and `BUILD EXIT <rc>`.
- **Subagents:** none on a shared host; see [`CLAUDE.md`](../CLAUDE.md).
- **Module names** are those of the host it was written for. Adjust them elsewhere.

## Working with Claude Code

- **Rules:** [`CLAUDE.md`](../CLAUDE.md) in the design repository loads by itself.
- **Project memory:** not relied on. Notes and guidance live in the repositories ([`CLAUDE.md`](../CLAUDE.md), "No reliance on project memory").
- **Sandbox:** Julia needs to write to its depot, so add `~/.julia` (or the depot `env.sh` sets) to `sandbox.filesystem.allowWrite` in your settings. On Ubuntu, if the sandbox fails with a `setgroups` error, the `bwrap-userns-restrict` AppArmor profile is the cause.

## Where to continue

1. [How to resume work](record/INDEX.md#how-to-resume-work): what to read, in order.
2. [The state of the prototype](state.md), §6.3: the order of work.
3. [The work queue](record/todo.md): "The plan" at the top, and each item's status.
4. [Open issues](open-issues.md), §1: the decisions waiting for the user.
