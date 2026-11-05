#!/bin/bash
cd /home/hellmann/Repos/julia-trait-bound-oc
export JULIA_PKG_OFFLINE=true OPENBLAS_NUM_THREADS=1 C7_OUT=$PWD/oc-notes/c7count
J="experiments/tools/jl --name w83u9 julia-1.13/julia --startup-file=no"
C=oc-notes/c7count/c7count.jl
U=experiments/w83/u5
run() { label=$1; env=$2; shift 2; echo "== $label"; $J --project=$env $C $label $U/$label-bounded.tsv "$@"; }
run tables $U/env_tables TraitTables TraitCSV InlineStrings
run tde $U/env_tde TraitDifferentialEquations ODECore TraitArrayTools TraitIndexing TraitRodas TraitNonlinearSolve TraitImplicit TraitLinSolvers TraitNLSolvers
run makie $U/env_makie TraitMakie MakieCompat MakieCompatStats
echo FIX3-DONE
