#!/usr/bin/env bash
# Demo 2 (writeup/poc3-plan.md §1): juliac builds. The full application
# without trimming, and the pipeline with --trim; sizes, trim verifier
# warnings, and each binary run once with --trace-compile to a file.
#   cd poc/interfaces/build && ./build.sh [full|trim|prof]
# prof: app_full's steps timed one by one, run-time compilation traced (app_prof.jl).
set -u
cd "$(dirname "$0")"
JULIA="julia +1.12.2 --startup-file=no"
JULIAC="$($JULIA -e 'print(joinpath(Sys.BINDIR, "..", "share", "julia", "juliac", "juliac.jl"))')"
SAMPLE="../App/data/sample.csv"
WHICH="${1:-both}"
if [ "$WHICH" = full ] || [ "$WHICH" = both ]; then
    $JULIA --project=../env "$JULIAC" --output-exe app_full --experimental app_full.jl > build_full.log 2>&1
    echo "== app_full: build exit $?, $(stat -c %s app_full 2>/dev/null) bytes"
    JULIA_DEBUG= ./app_full "$SAMPLE" out_full.png 2>&1 | head -5
fi
if [ "$WHICH" = prof ]; then
    $JULIA --project=../env "$JULIAC" --output-exe app_prof --experimental app_prof.jl > build_prof.log 2>&1
    echo "== app_prof: build exit $?, $(stat -c %s app_prof 2>/dev/null) bytes"
    ./app_prof "$SAMPLE" out_prof.png 2>&1 | tail -12
fi
if [ "$WHICH" = trim ] || [ "$WHICH" = both ]; then
    $JULIA --project=../env "$JULIAC" --output-exe app_trim --experimental --trim=unsafe-warn app_trim.jl > build_trim.log 2>&1
    echo "== app_trim: build exit $?, $(grep -c 'Verifier error' build_trim.log) trim verifier warnings, $(stat -c %s app_trim 2>/dev/null) bytes"
    ./app_trim "$SAMPLE" 2>&1 | head -5
fi
