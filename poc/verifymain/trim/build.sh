#!/usr/bin/env bash
# juliac --trim builds of the minimal program: verified, without entry points, plain Julia; then run each.
set -u
cd "$(dirname "$0")"
JULIAC="$(julia --startup-file=no -e 'print(joinpath(Sys.BINDIR, "..", "share", "julia", "juliac", "juliac.jl"))')"
for a in "" _noverify _plain; do
    julia --startup-file=no --project=../env "$JULIAC" --output-exe "vmapp$a" --experimental --trim=unsafe-warn "app$a.jl" > "build$a.log" 2>&1
    echo "== vmapp$a: build exit $?, $(grep -c 'Verifier error' "build$a.log") trim verifier errors, $(stat -c %s "vmapp$a" 2>/dev/null) bytes"
    "./vmapp$a" 4 2>&1 | head -2
done
julia --startup-file=no --project=../env "$JULIAC" --output-exe vmapp_safe --experimental --trim=safe app.jl > build_safe.log 2>&1
echo "== --trim=safe on the verified program: build exit $?"
