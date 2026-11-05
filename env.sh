# Environment for working on a shared host: `source env.sh` from any directory.
# Written for a shared RHEL 9 host with environment modules and no apt (see writeup/setup.md).
# On the project's own machine, none of this is needed.

# Compiler from modules: the system gcc lacks the static libstdc++ that Julia's build links.
if command -v module >/dev/null 2>&1; then
  module load gcc/13.2.0 git/2.52.0 2>/dev/null
fi

export TW_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# The Julia depot inside the workspace instead of ~/.julia
export JULIA_DEPOT_PATH=$TW_ROOT/.julia-depot

# At most 4 cores
export JULIA_NUM_THREADS=4
export JULIA_CPU_THREADS=4
export JULIA_NUM_PRECOMPILE_TASKS=4
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
export MAKEFLAGS=-j4

export J=$TW_ROOT/julia-1.13/julia
# Stock Julia for comparisons (juliaup channel 1.13.2, the upstream base of the patched build)
export JSTOCK="$HOME/.juliaup/bin/julia +1.13.2"

# experiments/tools/jl: 4 cores in all, one slot, no core pinning, locks and depots inside the workspace
export JL_CORES=4 JL_SLOTS=1 JL_NOPIN=1
export JL_LOCKDIR=$TW_ROOT/.jl-locks
export JL_DEPOTS=$TW_ROOT/.julia-depot/agent-depots
