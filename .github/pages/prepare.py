"""Collect the design repository's Markdown files into site-src/ for MkDocs.

- Every tracked .md file is copied with its directory structure; README.md is a directory's home page.
- Links into the workspace's other repositories (TraitWorld/, experiments/, julia-1.13/, ...) become
  links to those repositories on GitHub.
- A directory linked to without a README.md gets a generated index page listing its documents.
"""
import os, re, shutil, subprocess

ORG = "https://github.com/TraitJuliaPrototype"
REPOS = {"TraitWorld": "TraitWorld/blob/main", "TraitDifferentialEquations": "TraitDifferentialEquations/blob/main",
         "TraitMakie": "TraitMakie/blob/main", "TraitTables": "TraitTables/blob/main", "TraitCSV": "TraitCSV/blob/main",
         "TraitReport": "TraitReport/blob/main", "forks": "forks/blob/main", "experiments": "experiments/blob/main",
         "julia-1.13": "julia/blob/trait-world-1.13", "julia": "julia/blob/trait-world-1.13"}
root = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
out = os.path.join(root, "site-src")
shutil.rmtree(out, ignore_errors=True)
files = [f for f in subprocess.check_output(["git", "-C", root, "ls-files", "*.md"], text=True).split()
         if not f.startswith(".")]
link = re.compile(r"\]\(([^)\s#]+)(#[^)\s]*)?\)")
dirs_linked = set()

def fix(m, src):
    t, anchor = m.group(1), m.group(2) or ""
    if re.match(r"[a-z]+:", t) or t.startswith("/"):
        return m.group(0)
    full = os.path.normpath(os.path.join(os.path.dirname(src), t))
    if src.startswith("attic/writeup/notes-2026-10-18/") and not os.path.exists(os.path.join(root, full)):
        # the old notes' links were written for writeup/notes/: point them at the current documents
        alt = os.path.normpath(os.path.join("writeup/notes", t))
        if os.path.exists(os.path.join(root, alt)):
            return f"]({os.path.relpath(alt, os.path.dirname(src))}{anchor})"
    head = full.split(os.sep)[0]
    if head in REPOS:
        rest = os.sep.join(full.split(os.sep)[1:])
        return f"]({ORG}/{REPOS[head]}/{rest}{anchor})".replace("/blob/main/)", "/tree/main)")
    target = os.path.join(root, full)
    if os.path.isdir(target):
        if os.path.exists(os.path.join(target, "README.md")):
            return f"]({t.rstrip('/')}/README.md{anchor})"
        if os.path.exists(target.rstrip("/") + ".md"):
            # a directory beside a document of the same name (design/ and design.md) is that document's
            # companion: both would render at the same address, so the link goes to the document
            return f"]({t.rstrip('/')}.md{anchor})"
        if any(x.endswith(".md") for x in os.listdir(target)):
            dirs_linked.add(full)
            return f"]({t.rstrip('/')}/index.md{anchor})"
        return f"]({ORG}/julia-trait-bound/tree/main/{full}{anchor})"
    if os.path.exists(target) and not t.endswith(".md"):
        return f"]({ORG}/julia-trait-bound/blob/main/{full}{anchor})"
    return m.group(0)

# the site's search covers the pages for programmers and for core developers only
SEARCHED = {"writeup/intro/traits-for-julia.md", "writeup/intro/results.md", "writeup/intro/porting.md",
            "writeup/design.md", "writeup/design/mechanisms.md", "writeup/design/julia-changes.md",
            "writeup/design/evidence.md", "writeup/design/performance.md", "writeup/design/comparison.md",
            "writeup/design/implementation.md", "writeup/design/alternatives.md",
            "writeup/other-languages.md", "writeup/decisions.md", "writeup/open-issues.md",
            "writeup/glossary.md"}
NOSEARCH = "---\nsearch:\n  exclude: true\n---\n\n"

for f in files:
    os.makedirs(os.path.join(out, os.path.dirname(f)), exist_ok=True)
    s = open(os.path.join(root, f), encoding="utf-8").read()
    s = link.sub(lambda m: fix(m, f), s)
    if f not in SEARCHED:
        s = NOSEARCH + s
    open(os.path.join(out, f), "w", encoding="utf-8").write(s)

for d in sorted(dirs_linked):
    if not os.path.isdir(os.path.join(out, d)) or os.path.exists(os.path.join(out, d, "README.md")) \
            or os.path.exists(os.path.join(out, d, "index.md")):
        continue
    lines = [f"# {d}/", ""]
    for f in sorted(os.listdir(os.path.join(out, d))):
        p = os.path.join(out, d, f)
        name = f + "/" if os.path.isdir(p) else f
        title = name
        if f.endswith(".md"):
            for l in open(p, encoding="utf-8"):
                if l.startswith("# "):
                    title = l[2:].strip(); break
        if f.endswith(".md") or os.path.isdir(p):
            lines.append(f"- [{title}]({name})")
    open(os.path.join(out, d, "index.md"), "w", encoding="utf-8").write(NOSEARCH + "\n".join(lines) + "\n")
print(f"{len(files)} documents; generated indexes for {len(dirs_linked)} linked directories")
