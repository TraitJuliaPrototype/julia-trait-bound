#!/usr/bin/env python3
"""The paths in files for the renaming of 2026-11-18 (writeup/plans/2026-11-18-names.md, step 4).

    python3 tools-local/names-2026-11-18.py            # a dry run: the files that would change, with counts
    python3 tools-local/names-2026-11-18.py --write    # change them

It rewrites, in text files of the workspace outside logs, attics, session notes, build trees and depots:
  R-unified            -> R               for the library, the demonstrators and the forks
  experiments/unification, a path component unification/  -> implementation
It never searches outside the workspace. Run before or after the directories are moved: it reads no path it rewrites.
"""
import os, re, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
NAMES = "TraitWorld|TraitDifferentialEquations|TraitMakie|TraitTables|TraitCSV|TraitReport|forks"
SUBS = [
    (re.compile(r"(?<![\w/-])(pkgs/)?(%s)-unified(?![\w-])" % NAMES), lambda m: m.group(0) if m.group(1) else m.group(2)),
    (re.compile(r"(?<=[\w.}$])/(%s)-unified(?![\w-])" % NAMES), lambda m: "/" + m.group(1)),
    (re.compile(r"/unification(?=[/\"'`\s),:;\]]|$)", re.M), lambda m: "/implementation"),
    (re.compile(r"(?<=[`(\s\"'=])unification/"), lambda m: "implementation/"),
]
SKIP_DIRS = {".git", ".julia-depot", ".jl-locks", "logs", "attic", "session-notes", "site", "site-src", "pre-unified",
             "julia-1.13", "julia-next", "julia-unified", "julia-vanilla", "TraitWorld-base", "wt", "node_modules",
             "depot", "data", "deps", "usr", "srccache"}
SKIP_FILES = {"writeup/record/decisions.md", "writeup/plans/2026-11-18-documentation-cleanup.md",
              "writeup/plans/2026-11-18-names.md", "writeup/plans/2026-11-18-claude-md-changes.md",
              "writeup/plans/2026-11-14-synthesis.md", "writeup/reviews/2026-11-15-conceptual-design.md",
              "writeup/record/harvest-2026-11.md", "writeup/record/harvest-dispositions-2026-11.md",
              "writeup/record/design-history.md", "writeup/record/context.md",
              "tools-local/names-2026-11-18.py", "session-notes"}
EXT = (".md", ".jl", ".sh", ".py", ".toml", ".yml", ".yaml", ".json", ".txt", ".c", ".h", ".cfg", ".gitignore", ".tsv")
write = "--write" in sys.argv
total = files = 0
for dp, dn, fn in os.walk(ROOT):
    rel = os.path.relpath(dp, ROOT)
    dn[:] = [d for d in dn if d not in SKIP_DIRS and not d.startswith("depot") and not d.startswith(".julia")
             and not (rel == "ndport" and d == "pkgs-bundles")]
    for f in fn:
        p = os.path.join(dp, f); r = os.path.relpath(p, ROOT)
        if r in SKIP_FILES or not (f.endswith(EXT) or f in ("env.sh", ".gitignore", "run", "Makefile")) or f.endswith((".log", ".out")):
            continue
        if os.path.islink(p) or os.path.getsize(p) > 3_000_000:
            continue
        try:
            t = open(p, encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue
        n = 0; new = t
        for pat, fun in SUBS:
            new, k = pat.subn(fun, new); n += k
        if new != t:
            files += 1; total += n
            if write:
                open(p, "w", encoding="utf-8").write(new)
            else:
                print(f"{n:5d}  {r}")
print(f"{'changed' if write else 'would change'}: {total} places in {files} files")
