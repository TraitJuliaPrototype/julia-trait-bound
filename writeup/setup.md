# Setting up the development environment

This page takes you from an empty machine to a working copy of every repository, a built patched Julia, and the point in the record where work continues.

**Checked on 2026-11-05:** the clone steps from GitHub into an empty directory, the restore of `ndport/pkgs/`, and loading TraitWorld on an existing build. A cold build from a fresh clone was not part of that check.

## What you need

- **System:** Linux on x86-64. The project runs on Ubuntu, with 16 cores and 30 GB of memory.
- **Disk:** about 3 GB for each built Julia, and tens of GB for `~/.julia` once the demonstrators are precompiled.
- **Tools for building Julia:** GNU make, gcc and g++, gfortran, python, perl, curl or wget, m4, awk, patch, cmake, pkg-config and which. On Ubuntu:

  ```sh
  sudo apt install build-essential gfortran python3 perl curl m4 gawk patch cmake pkg-config
  ```

- **Optional:**
  - [juliaup](https://github.com/JuliaLang/juliaup) and stock Julia 1.13.2 (`juliaup add 1.13.2`), for comparisons with unpatched Julia.
  - [uv](https://github.com/astral-sh/uv), for the Python baselines ([`experiments/ttfx/README.md`](https://github.com/TraitJuliaPrototype/experiments/blob/main/ttfx/README.md) names the versions).

## Clone the repositories

The design repository holds the others, each with its own history. Packages refer to their siblings by relative path, so they must sit side by side.

Use `~/Repos` if you can. Some environments name absolute paths under `/home/hellmann/Repos/julia-trait-bound` (see [Paths](#paths)).

```sh
mkdir -p ~/Repos && cd ~/Repos
git clone https://github.com/TraitJuliaPrototype/julia-trait-bound
cd julia-trait-bound

for r in TraitWorld TraitDifferentialEquations TraitMakie TraitTables TraitCSV TraitReport forks experiments ndport; do
    git clone https://github.com/TraitJuliaPrototype/$r
done
git -C TraitDifferentialEquations switch w34
ndport/pkgs-bundles/restore.sh

git clone --filter=blob:none -b trait-world-1.13 https://github.com/TraitJuliaPrototype/julia julia-1.13
```

- **`TraitDifferentialEquations`:** its current work is on branch `w34`.
- **`ndport/pkgs-bundles/restore.sh`:** recreates `ndport/pkgs/`, the clones of the packages NetworkDynamics uses. Each comes from its upstream repository, with the port's branches, stage tags and worktrees added.
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

## Work from the upstream Julia base

The unified design can be built from upstream Julia instead of on the patched branch. This route is [an exploration](explorations/unified-build-from-vanilla-julia.md), not an adopted plan. Read [its review](reviews/2026-10-29-unified-build-review.md) with it.

Upstream v1.13.2 is commit `45b6d15e34`, and the exploration's line citations refer to that commit. To get a tree at that commit on its own branch:

```sh
git -C julia-1.13 worktree add ../julia-upstream -b unified 45b6d15e34
cp julia-1.13/tw-build.sh julia-upstream/
julia-upstream/tw-build.sh
```

`unified` is only an example name for the branch.

An unfinished earlier attempt is available as material to draw on, unverified: its Julia commits are on `origin/oc-build`, and its plan, notes and tests are in `attic/oc-notes/` and `attic/oc-traits/`.

## Paths

These assume the original location, `/home/hellmann/Repos/julia-trait-bound`:

- **Absolute paths in environments:** `TraitReport/env`, `TraitReport/env_loads`, `experiments/phase2-round/env_cache_*` and `experiments/w83/u6/arr/*/env`. Elsewhere, edit their `Project.toml` files.
- **`TraitMakie/scripts/session.sh`:** sets `ROOT` to that path.

Some environments have no committed manifest. They resolve when instantiated, so their package versions can differ from the recorded runs.

## Running Julia jobs

- **Slots:** `experiments/tools/jl [--name NAME] command…` runs a job pinned to a slot, with its own depot and a memory guard. It writes to `/tmp/claude-1000` and assumes 16 cores, so check `JL_SLOTS` and its core count on another machine.
- **Exclusive jobs:** use `jl --exclusive command…` for measurements and Julia builds.
- **Measurements:** recorded numbers belong to the machine they were measured on. On a new machine, rerun the baselines before comparing with [the evidence](design/evidence.md).

## Working with Claude Code

- **Rules:** [`CLAUDE.md`](../CLAUDE.md) in the design repository loads by itself.
- **Project memory:** it is not in any repository. Copy `~/.claude/projects/<project key>/memory/` by hand. The key comes from the project's path, which is one more reason to keep the same path.
- **Sandbox:** Julia needs to write to its depot, so add `~/.julia` to `sandbox.filesystem.allowWrite` in your settings. On Ubuntu, if the sandbox fails with a `setgroups` error, the `bwrap-userns-restrict` AppArmor profile is the cause.

## Where to continue

1. [How to resume work](record/INDEX.md#how-to-resume-work): what to read, in order.
2. [The state of the prototype](state.md), §6.3: the order of work.
3. [The work queue](record/todo.md): "The plan" at the top, and each item's status.
4. [Open issues](open-issues.md), §1: the decisions waiting for the user.
