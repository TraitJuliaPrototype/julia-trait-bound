#!/usr/bin/env bash
# juliac --trim builds of App.main: verified, and without verify_main; then run each.
set -u
cd "$(dirname "$0")"
JULIAC="$(julia --startup-file=no -e 'print(joinpath(Sys.BINDIR, "..", "share", "julia", "juliac", "juliac.jl"))')"
for a in "" _noverify; do
    julia --startup-file=no --project=../env "$JULIAC" --output-exe "app$a" --experimental --trim=unsafe-warn "app$a.jl" > "build$a.log" 2>&1
    echo "== app$a: build exit $?, $(grep -c 'Verifier error' "build$a.log") trim verifier errors, $(stat -c %s "app$a" 2>/dev/null) bytes"
    "./app$a" ramp 4 2>&1 | head -3
    "./app$a" m 4 2>&1 | head -3
done
