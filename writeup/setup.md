# Setting up the development environment

This page takes you from an empty machine to a working copy of every repository, a built Julia with the design's changes, and the point in the record where work continues.

## What you need

- **System:** Linux on x86-64.
- **Disk:** about 3 GB for each built Julia, and tens of GB for the Julia depot once the demonstrators are precompiled.
- **Tools for building Julia:** GNU make, gcc and g++, gfortran, python, perl, curl or wget, m4, awk, patch, cmake, pkg-config and which. On Ubuntu:

  ```sh
  sudo apt install build-essential gfortran python3 perl curl m4 gawk patch cmake pkg-config
  ```

- **The static C++ library:** the build links `libstdc++` statically. On RHEL it is in `libstdc++-static`, or in a gcc from environment modules.
- **Optional:** [uv](https://github.com/astral-sh/uv), for the Python baselines (`experiments/ttfx/README.md` names the versions).

## Clone the repositories

The design repository holds the others, each with its own history. Packages refer to their siblings by relative path, so they must sit side by side. Any location works (see [Paths](#paths)).

```sh
git clone git@github.com:TraitJuliaPrototype/julia-trait-bound
cd julia-trait-bound

# the library, the demonstrators, the experiments
for r in TraitWorld TraitDifferentialEquations TraitMakie TraitTables TraitCSV TraitReport forks; do
    git clone git@github.com:TraitJuliaPrototype/$r
    git -C $r worktree add ../$r-unified unified          # the implementation is on branch `unified`
done
git clone git@github.com:TraitJuliaPrototype/experiments
git clone git@github.com:TraitJuliaPrototype/ndport
ndport/pkgs-bundles/restore.sh

# Julia: one clone, a worktree per line
git clone --filter=blob:none -b trait-world-1.13 git@github.com:TraitJuliaPrototype/julia julia-1.13
git -C julia-1.13 worktree add ../julia-next next                      # Julia with the design's changes
git -C julia-1.13 worktree add --detach ../julia-vanilla 45b6d15e34    # v1.13.2 unchanged: the plain baseline
```

- **SSH:** the commands clone over SSH, so that pushes work. To read only, replace `git@github.com:` with `https://github.com/`.
- **The directories without a suffix** (`TraitWorld/`, `julia-1.13/`, …) are each repository's main checkout, on the branches of the library on Julia 1.13 (history; tag `pre-unified`). The work is done in the worktrees.
- **`ndport/pkgs-bundles/restore.sh`** recreates `ndport/pkgs/`, the clones of the packages NetworkDynamics uses. Each comes from its upstream repository, with the port's branches and worktrees added.
- **`--filter=blob:none`** fetches file contents on demand, so the Julia clone stays small.
- **The regression control** of the running iteration is the tag `prototype-2026-11`:

  ```sh
  git -C julia-1.13 worktree add --detach ../julia-unified prototype-2026-11
  git -C TraitWorld worktree add --detach ../TraitWorld-base prototype-2026-11
  ```

## Build Julia

```sh
source env.sh                          # on a shared host; see below
tools-local/build.sh julia-next
tail -1 julia-next/tw-build.log        # must say: BUILD EXIT 0
tools-local/build.sh julia-vanilla
```

- Copy `deps/srccache/` from a built tree into a new one first, to save the downloads.
- The script nices the build, guards memory, chooses its width by the machine's load and time-stamps the log.
- Always check `BUILD EXIT 0`. An error in the system image's build can leave no crash message.
- The script rebuilds the system image where a runtime source (`src/`) is newer than it. Julia's make does so only for a change in `base/`. `KEEP_IMAGE=1` keeps the image.

## Check that it works

```sh
J=$PWD/julia-next/julia
$J --project=TraitWorld-unified -e 'using Pkg; Pkg.instantiate(); using TraitWorld; println("the library loads")'
(cd TraitWorld-unified && $J --project=. -e 'using Pkg; Pkg.test()')
experiments/unification/gates/run_all.sh julia-next
```

What to run after a change: [the playbook](record/playbook.md) §3.

## Paths

- **Environments** name their sibling packages by paths relative to the environment.
- **Scripts** find the workspace from their own location. `TW_ROOT` overrides it.
- **Older experiment scripts and logs** name the location they ran in. They record past runs.
- Some environments have no committed manifest. They resolve when instantiated, so their package versions can differ from the recorded runs.

## Running Julia jobs

- **Slots:** `experiments/tools/jl [--name NAME] command…` runs a job in a slot, with its own depot and a memory guard. `JL_CORES`, `JL_SLOTS`, `JL_NOPIN`, `JL_LOCKDIR` and `JL_DEPOTS` set the cores, the slots, the locks and the depots.
- **Exclusive jobs:** `jl --exclusive command…` for measurements and Julia builds.
- **Measurements:** recorded numbers belong to the machine they were measured on. On a new machine, rerun the baselines before comparing with [the evidence](design/evidence.md).

## On a shared host

On a machine shared with other people, without root:

- **`source env.sh`** in the design repository before working. It:
  - loads `gcc/13.2.0` from environment modules, for the static C++ library;
  - keeps the Julia depot in `.julia-depot/` inside the workspace;
  - limits Julia, make and `jl` to 4 cores, with no core pinning.
- **Builds:** `tools-local/build.sh <julia tree> [make target]` applies the rule for cores by load ([the standing constraints](record/INDEX.md#standing-constraints)):
  - while the others' load is below half the cores, `make -j<half the cores>`; otherwise `-j4`;
  - a wide build whose others' load reaches half the cores is stopped and continues at `-j4`;
  - a narrow build pauses while the load is above 110 and resumes below 90 (`HI`, `LO`), as `tools-local/loadguard.sh <pgid>` does for any process group;
  - a wide build is a spike: its parallel compile phase lasts minutes. Builds one after another run with `WIDE=0`;
  - niced, killed below 4 GB of available memory; the log `<tree>/tw-build.log` ends with the wall time, the sampled peak memory and `BUILD EXIT <rc>`.
- **Module names** are those of the host it was written for. Adjust them elsewhere.

## Working with Claude Code

- **Rules:** [`CLAUDE.md`](../CLAUDE.md) in the design repository loads by itself.
- **Project memory:** not relied on. Notes and guidance live in the repositories.
- **Sandbox:** Julia needs to write to its depot, so add the depot `env.sh` sets (or `~/.julia`) to `sandbox.filesystem.allowWrite` in your settings.

## Where to continue

[The record's index](record/INDEX.md), then [the playbook](record/playbook.md) §1.
