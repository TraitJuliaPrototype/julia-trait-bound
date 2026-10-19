# Review of the reorganized writeup (2026-10-19)

Reviewer: Fable 5.1, independent. Scope: `writeup/intro/*.md` (programmers), `writeup/design.md` and `writeup/design/*.md` (core developers), `writeup/record/INDEX.md` (agents), against the code (`TraitWorld/src`, `julia-1.13/Compiler/src/facts.jl`, `strict.jl`, `ownership.jl`), the session notes and the demonstrators' READMEs. Nothing in the repository was edited. Scratch: `/tmp/claude-1000/-home-hellmann-Repos-julia-trait-bound/e0c44133-0ba1-4a71-abd7-4611822ff738/scratchpad/` (`worked.jl`, `worked2.jl`, their `.out`, `links.py`).

**Verified by experiment** (marked V): the worked example runs; the error messages; the printing claim; the link check (0 broken in 12 files); the test-set count (47); `strict!`/`conforms`/`fully_typed` exist; strict mode's treatment of standard libraries; `MAX_FACT_SPLITS = 4`; the switch's name; commit/file/line counts. Everything else is reading and cross-checking (marked R).

Findings are ranked by damage to the thesis or to the reader. "Fix" gives a replacement sentence where one suffices.

---

## A. Critical and high

### 1. SparseArrays' `vcat` is called a pirate, and strict mode is said to refuse it. By the design's own definition it is neither. (V)

- `design.md:30` (Terms): "Julia (Core, Base, the standard libraries) is one owner." `TraitWorld/src/ownership.jl:103,127`: `owner(m)` returns `:Julia` for every standard library. `TraitWorld/src/strict.jl:125`: `definer === :Julia && return nothing`: strict mode never refuses a standard library's method.
- So `vcat(::Number, ::Vector)` defined by SparseArrays is a stakeholder's method (Julia's own), not a pirate, and strict mode cannot refuse it, as built and as defined.
- Where the wrong claim stands: `intro/traits-for-julia.md:140` (the only example of piracy given to programmers is this one), `:359` ("It would refuse SparseArrays' `vcat`"); `intro/results.md:162`; `design/evidence.md:30`; `design/performance.md:69` ("a pirate, here a standard library"; "strict mode would refuse SparseArrays at StatsBase's load"); `design.md:350`; `design/mechanisms.md:621`; the session note 29 line 131 is the origin ("Strict mode would refuse the pirate").
- Consequence for the thesis: the one diagnosed residue after loads (TraitReport 333–410 ms against 41 ms) is, under the design's rule, a *stakeholder's* change (Julia's own code loaded later), i.e. it falls inside "code it depends on changes". That is honest to say, and it raises a design question the user has not been asked: should standard libraries be separate owners (TraitWorld's `_type_root`, `ownership.jl:257`, already treats a standard library's *types* as its own, unlike `owner`)?
- Fix (all sites): "StatsBase loads SparseArrays, a standard library, whose `vcat` for Base's `Number` and `Vector` wins at a fact signature inside `CSV._parse`. The design counts the standard libraries as Julia's own code (§1), so this is a stakeholder's change: not a pirate, not refused by strict mode (`strict.jl:125`). Whether standard libraries should be separate owners is open (open-issues §1)." In the intro, replace the piracy example at `:140` with a real third-party pirate (one from `experiments/examples`' strict-mode case), and delete the sentence at `:359`.

### 2. The headline motivating number is a stakeholder's extension, not an unrelated package's method. (R)

- `intro/traits-for-julia.md:32` and `design.md:55`: "With DataFrames loaded, CSV.jl's first read took 2.5 s instead of 0.19 s", placed under "an unrelated package adds a method for its own type".
- Source (session note 26 line 16; `plans/2026-10-17-dataframes-traits-plan.md:120`): DataFrames loads InlineStrings, which activates **CSV's own extension** `CSVInlineStringsExt`, whose methods on CSV's internal functions invalidate CSV's image code. Under `design.md` §3.2 this is "a package extension of a stakeholder" (the open exception), which the facts mode follows as the code changing. The facts rule does not prevent this case; conformances as the extension point do.
- Fix (intro `:32`): move the sentence to problem 2 or to "What you get 2", as: "A package's own extension can discard its compiled code: with DataFrames loaded, CSV.jl's first read took 2.5 s instead of 0.19 s, because DataFrames loads InlineStrings and that activates CSV's extension, which adds methods to CSV's internal functions. In the trait world an extension declares a conformance instead, which discards nothing (TraitCSV's `String15`)." Same correction in `design.md:55`.

### 3. `design.md` §8 says a new callback closure costs 12–24 ms "in every load order". The evidence table says 171 ms in one order. (R)

- `design.md:344`: "A new callback closure 12–24 ms, a second loss closure 17–18 ms, in every load order". `design/evidence.md:59`: 12.4 / 24.0 / **170.7** ms (loads after). `evidence.md:66` and `results.md:111` state the 171 ms as undiagnosed.
- Fix: "A new callback closure 12–24 ms with no loads or loads before; 171 ms with the loads after the first solve (one run, not diagnosed); a second loss closure 17–18 ms in every order."

### 4. `design.md` §3.5 presents the package-era `g2all` result as the current state of the default tier. (R)

- `design.md:128`: "so far, always 'none' (0 CodeInstances lost over twelve loads in any order, `experiments/facts/g2all`)". That is session 24 (note 24 line 196), under the package policy. In session 29 the control under `all` lost **2 of 3,340** upstream CodeInstances (`evidence.md:26`), not attributed, and `CSV._parse`'s facts code was recompiled after StatsBase (finding 1).
- Fix: "In the package era (session 24, `g2all`) none over twelve loads; under `all` in session 29, 2 of 3,340 upstream CodeInstances were lost to nine loads and are not yet attributed, and one recompilation is diagnosed (a standard library's `vcat`, finding 1)."

### 5. Rule 1 and part (C) claim run-time sites in facts code always run facts code. The implementation review verified they do not. (R)

- `design.md:234` ("Under part C, a run-time site in facts-compiled code runs facts-compiled code") and `:263`. `reviews/2026-10-19-compiler-implementation.md` §2.4 (verified): (C) covers codegen's four call sites; dispatch through the runtime's `jl_apply` (the `_apply_iterate` builtin with unknown tuples, `jl_call`, `@cfunction`, finalizers, task entry) runs plain code. `record/INDEX.md:90` lists the review's item (4) as "to state in design.md"; it is not stated anywhere in `design.md` or `design/julia-changes.md:13`.
- Damage: a protection hole, not a correctness one (the facts frame records no edge there), but the rule as written is false.
- Fix (`design.md:234`): "Under part C, a run-time site in facts-compiled code runs facts-compiled code where codegen emits the call (direct calls, `invoke`, `_apply_iterate` with known tuples, `invokelatest`); dispatch that goes through the runtime's `jl_apply` (splats of unknown length, `jl_call`, `@cfunction`, finalizers, task entry) runs plain code (review of 2026-10-19, §2.4)." Mirror it in `julia-changes.md:13`.

### 6. `intro/porting.md` is routed to programmers but is a core-developer document with a stale status. (R)

- Root `README.md:8` and `writeup/README.md:9` send programmers there. Its vocabulary: fact signature, run-time site, worker, cache owner, `FactsInterp`, archetype, "implementation review P7" (lines 7, 14, 15, 24, 27, 35). Its status paragraph (`:7`) says parts (B), (C), (D) are coming and the machinery "is being removed" and "No timing ... until (D) is in": all done in session 29. It calls the work "Session 30" (`:24, :77, :114`), a number the record does not use.
- The plan (§3.3) promised "porting.md: porting-to-traits.md, moved, with part A in plain terms". Only the move happened.
- Fix: either rewrite the status paragraph and part A in the intro's vocabulary now, or list it under core developers in both READMEs until it is, with one line: "a working guideline for porters, in the design's vocabulary; part A will be rewritten for programmers".

### 7. `results.md` says the two inliner fixes "are proposed for upstream Julia". Nothing is proposed. (R)

- `intro/results.md:73`. `design/julia-changes.md:52`: "After broader measurement in plain Julia"; root `README.md`: "These repositories have no remotes yet"; `intro/traits-for-julia.md:17`: "Nothing is upstream."
- Fix: "The fixes apply to all code in the patched build and are candidates for upstream Julia after broader measurement."

---

## B. Medium: overclaims, numbers, and contradictions between companions

### 8. "about 1 ns per element" rounds 0.92–1.40 ns down. (R)
- `intro/traits-for-julia.md:312`. Evidence: 0.92–1.40 ns (`evidence.md:38`); at 10⁶ elements 4.5–5.7 against plain's 3.9–4.0.
- Fix: "Summing areas over a vector of `Dynamic{Shape}`: 1–1.4 ns per element when the data is in cache. Plain Julia: about 0.9 ns when it sees two shape types, about 30 ns when it sees four. On a million elements: 4.5–5.7 ns against plain's 4 ns."

### 9. "New trait code costs the same in every load order" is 82 against 133 ms. (R)
- `design.md:343`. Evidence row: first solve 82 / 133 / 89 ms. `performance.md:67` says "about what it costs without them".
- Fix: "New trait code costs about the same in every load order (within 1.6×): ..."

### 10. "A method with a concrete type annotation wins over a bounded one." Any type annotation wins, abstract included. (R)
- `intro/traits-for-julia.md:105`. `design.md:216`: "A trait bound ranks above `Any` and below every type"; `mechanisms.md:291`: `describe([1.0 2.0])` takes the `AbstractMatrix` method although `Matrix{Float64}` is a `ColTable`.
- Fix: "A method with a type annotation, concrete or abstract, wins over a bounded one; only an untyped method loses to it. So a library can adopt traits one function at a time."

### 11. "when the method would change your compiled code": strict mode protects trait code only. (R)
- `intro/traits-for-julia.md:142`. `design.md:241`: "a fact of compiled trait code"; `:311`: "strict mode protects facts-owned code".
- Fix: "... when the method would change compiled trait code (library code in trait modules). Plain code is not protected by it."

### 12. "Inside, it can use only what the trait declares: here `ncols` and `col`" reads as "may call nothing else". (R)
- `intro/traits-for-julia.md:103`. The example body calls `sum` and `length`. `design.md:237`: "Trait code may call any Julia code directly."
- Fix: "Inside, on `t` it can use only what the trait declares, here `ncols` and `col`. On ordinary values, such as the column `col` returns, it calls any Julia code."

### 13. The test-bed switch has two names. (V)
- Built: `JULIA_COMPILE_BY_FACTS=1` (`facts.jl:7,16`, `src/gf.c:1115`; `design.md:268`, `julia-changes.md:16`). Also written: `--compile-by-facts=all|no|traits` (`design.md:319` decision row, `:373` target; `TraitDifferentialEquations/README.md:49,125`).
- Fix (`design.md:319,373`): "`JULIA_COMPILE_BY_FACTS=1` (`all`) is a test bed; a command-line flag `--compile-by-facts=no|all|traits` is the target spelling, not built."

### 14. The noise estimate differs between the programmer and the core-developer page. (R)
- `intro/results.md:7`: "Differences of 10–20% can be noise." `design/evidence.md:8`: "Repeated runs vary by about 5% when the machine is busy." The session note (line 151) measured 5%.
- Fix: one statement in both: "Repeated runs varied by about 5% on a busy machine; treat differences under 10% as noise."

### 15. The control's first row mislabels its subject. (R)
- `intro/results.md:30`: "The report's plain form (a table library without traits, with TraitMakie)". The row is PlainTables + TraitMakie; TraitMakie is trait code; the 14 CodeInstances lost in plain mode are all PlainTables' (`TraitMakie/README.md:93`). Saying so strengthens the point.
- Fix: "A plain table library (PlainTables) together with TraitMakie: compiled code lost to the loads | 14 of 218 (all of them PlainTables') | 0 of 206".

### 16. BaseBenchmarks' configuration is misdescribed as today's `all`. (R)
- `design.md:110`: "Measured on plain code (`all`, a test bed) ... Base compiled plainly in the system image." It was session 28, with (A) as a forked `Compiler` package, before parts B–D and the inliner changes (`evidence.md:32`). Today's `all` image compiles Base by facts (`facts.jl:7`). Two configurations, one name.
- Fix: "Measured in session 28 with (A) as a forked Compiler package, Base compiled plainly in the system image, before parts B–D and the inliner changes (to rerun on the current test bed): ..."

### 17. "No numbers for stock Julia" contradicts §8 and the evidence. (R)
- `design.md:404`. `evidence.md:44` (stock 1.13.2: 21.9–23.3 ms), SciML on stock 1.12.2 throughout.
- Fix: "No numbers for TraitWorld on stock Julia: the design needs the patched build. Stock numbers appear only as baselines and say so."

### 18. "the nine-package load loses no facts code of TraitWorld" has no source. (R)
- `design.md:265`. The control counted PlainTables + TraitMakie (TraitMakie lost none, `TraitMakie/README.md:93`); TraitWorld's own CodeInstances were not counted separately in the session note (searched: no match).
- Fix: "the control's nine-package load lost no facts code in the modules it counted (TraitMakie 0); TraitWorld's own code was not counted separately."

### 19. "about 4 ns" per dynamic call is package-era evidence and is not in `evidence.md`. (R)
- `intro/traits-for-julia.md:134`, `design.md:205`, `mechanisms.md:357`, `comparison.md:115`. Source: `design-findings.md:424` (4.0–4.4 ns, before session 29). `evidence.md` has no row.
- Fix: add a row to `evidence.md` §2 ("a `Callable` in `DynamicCall` mode, per call: 4.0–4.4 ns, session 23 prototype, not remeasured"), or write "about 4 ns (measured on the earlier prototype)" at each site.

### 20. The `using` overhead is 0.04–0.20 s, not 0.18–0.20 s. (R)
- `comparison.md:328` and `performance.md:100`: "0.18–0.20 s above the plain forms'". That is form (b). TraitReport (t) against (pt): 0.53–0.54 against 0.49–0.50 (`evidence.md:85–86`). `intro:342` has it right.
- Fix: "0.04–0.20 s above the plain forms' (TraitReport's two pairs)".

### 21. A history row sits in the table of decisions in force. (R)
- `design.md:295`: "Witness tables off by default until `Dynamic` is in the compiler; deleted once (D) was built". The table says "Only the current decisions."
- Fix: delete the row (it is in `decisions.md:149` as history) or fold it into the `Dynamic{X}` row.

### 22. The stakeholder's-extension exception is presented as settled in the intro. (R)
- `intro/traits-for-julia.md:284`: "the package that owns the function, or one of the types, changes it: an edit, an upgrade, one of its package extensions". `design.md:91`: refuse or admit, "still open".
- Fix: "... an edit, an upgrade, and (still being decided) one of its package extensions".

### 23. Programmer pages carry editorial markers. (R)
- 16 `[[TBD: ...]]` in `intro/results.md`, 4 in `intro/traits-for-julia.md`; none in `design.md` or `evidence.md`. For a programmer they read as unfinished copy; most repeat a caveat already in prose.
- Fix: convert each to a plain sentence ("Not measured on the current compiler.") or move the list to "What is not shown yet", which already exists (`results.md:203`).

### 24. The worked example's TBD can be closed. (V)
- `intro/traits-for-julia.md:148`: "[[TBD: run the worked example as written on the current build ...]]". It ran (julia-1.13 a89a91629a, TraitWorld 375a930): `colmean(m, 1) = 1.5`, `colmean(r, 2) = 3.0`, `meandiff = 0.0`, `colmap = [6.0, 10.0]`, `means(s, 1) = [1.5, 1.5]`; `fieldtype(Shelf, :tables) === Vector{Dynamic{ColTable}}`. The `ImplementError` text is verbatim as printed (`:247`). The `colsum` case warns at the module's end and raises `TraitUseError` at the call, with the text of `:267–269` (the warning form is prefixed "trait module Columns2:"). `colmap(x -> 1, m, 1)` raises `TypeError: in typeassert, expected Float64, got a value of type Int64`. `colmean(42, 1)` raises `MethodError`. `typeof` of the trait object prints `ColTable at Vector{Vector{Float64}}`, and a stack frame prints `boom(t::ColTable at Vector{Vector{Float64}}, i::Int64)`.
- One caveat for the text at `:307` ("TraitWorld hides its own frames"): the entry frame `boom(t::Any, i::Int64) @ ./none:-1` still shows. Fix: "TraitWorld hides most of its own frames in stack traces (the entry's frame remains)."
- Fix (`:148`): replace the TBD with "Run as written on the build of 2026-10-19; at a REPL, enter the user's declarations one at a time (`struct Counts` before its `@implement`)."

### 25. Five demonstrators against the design's four. (R)
- `intro/traits-for-julia.md:15` counts "a CSV reader with a table" and "a data report" separately; `design.md` and the plan number four demonstrators (TraitTables/TraitCSV belong to TraitReport).
- Fix: "four demonstrators: an ODE solver, a plotting library, a data report (with its own CSV reader and table library), and ports of CSV.jl and DataFrames.jl".

---

## C. Core-developer companions: smaller contradictions and stale detail

### 26. `julia-changes.md` size line is off by one commit. (V)
- `:5`: "30 commits ... 33 files, about 1,270 lines added". `git log v1.13.2..HEAD`: 31 commits, 35 files, 1,282 insertions (a89a91629a added `tw-build.sh` later today).
- Fix: "31 commits (one a build script), 35 files, about 1,280 lines added" or date the count to 61852d8fb1.

### 27. `mechanisms.md` misattributes "dissolves". (R)
- `:489`: "design.md's session-29 decisions say 'dissolves'". It is `decisions.md:154`; `design.md` does not use the word.
- Fix: "the s27 narrowing, which `decisions.md`'s session-29 row says 'dissolves', is still in the code (`_narrow`, `src/core.jl:358`)".

### 28. `mechanisms.md` §8 and `design.md` disagree on pirates in trait modules; stated, but not in `open-issues.md` §1. (R)
- `mechanisms.md:315`: the prototype refuses *any* pirate defined in a trait module (`OwnershipError`); `design.md` refuses only a *winning* pirate, under strict mode. The companion flags it; `open-issues.md` §1 does not list it as a decision for the user.
- Fix: add to `open-issues.md` §1: "Trait modules: refuse every pirate at definition (prototype) or only winning pirates under strict mode (design)?"

### 29. `comparison.md` prediction 7 and `design.md:98` cite g2strict as current. (R)
- Both say strict mode's check was measured (0.54 s, 837 pirates, none refused) without saying it ran under the session-25 package policy, before the compiler; `evidence.md:16` says so. `design.md:134` admits "strict mode under the `all` setting is unmeasured".
- Fix (`comparison.md:368`, `design.md:98`): append "(session 25, under the package policy; not rerun on the compiler)".

### 30. Root `README.md` counts eight repositories; its own table lists nine. (V)
- `:22`: "Eight repositories sit inside it". `ls -d */.git`: julia (+ worktree), TraitWorld, TraitDifferentialEquations, TraitMakie, TraitReport, TraitTables, TraitCSV, forks, experiments = nine (plus three untracked old TraitWorld copies).
- Fix: "Nine repositories sit inside it".

### 31. `design.md` §4.7 against `mechanisms.md` §13 on what is exercised. (R)
- `design.md:214`: "the demonstrators use only `Self` constructors". `mechanisms.md:440` has to add "that is true of the demonstrators, not of the prototype's tests". Consistent, but a reader of §4.7 alone takes "exercised" for the prototype.
- Fix (`design.md:214`): "TraitWorld's tests exercise all of them ...; the demonstrators use only `Self` constructors (TraitCSV)." (already nearly so; make the two halves one sentence).

---

## D. The agent record (`writeup/record/INDEX.md`)

### 32. The repository table was stale within hours. (V)
- `:232–245`: seven of ten "latest commit" cells differ from HEAD now (design 82b8aeb, julia-1.13 a89a91629a, TDE 65ca602, TraitMakie 52f8591, TraitReport 9749baa, forks 254ace8, experiments e23ced3).
- Fix: drop the column, or head it "as of the index's commit; `git -C <dir> log -1` for the current one".

### 33. "Session 30" is used in the demonstrators' READMEs, their commit messages and `intro/porting.md` for what the record calls session 29. (R)
- `INDEX.md:239–240` quote "session-30 runs"; `porting.md:24,77,114`. An agent resuming work will look for a note 30.
- Fix: add under "How to resume work": "The demonstrators' READMEs and `intro/porting.md` call session 29's autonomous run 'session 30'; there is no note 30."

### 34. The compiler-implementation review's item (4) is listed as "to state in design.md" and was not. (R)
- `INDEX.md:90`; see finding 5.
- Fix: mark it "open: not yet stated" so the next agent sees the gap, or close it by fixing `design.md`.

### 35. Companions missing from "Other writeup documents". (R)
- `:146–155` lists `decisions.md`, `open-issues.md`, `other-languages.md`, `porting-to-traits.md`, `design/performance.md`, but not `design/evidence.md`, `design/julia-changes.md`, `design/mechanisms.md`, `design/comparison.md` with date and status (they appear only in the layout list at the top).
- Fix: four rows, status "current (2026-10-19)", with each one's "where it disagrees, design.md wins" line.

### 36. Accurate rows, spot-checked (no action). (V/R)
- Reviews table: "87 rows" (`decisions-revisited.md:13`), commit range `db82407fa6..f6838f96fc` (`compiler-implementation.md:3`), both correct. `design-findings.md` classification matches its header. Session notes 00–29 all exist; session 28 correctly marked "no note". Experiments directories listed match `experiments/`. `TraitWorld/README.md` indeed does not exist. All 12 documents' relative links resolve.

---

## E. Nits

37. `intro/results.md:57`: "about 2.5× in the ray tracer" is 2.5–2.9× (827/336 to 882/300). Write "2.5–3×".
38. `intro/traits-for-julia.md:343`: "@implement ... about 0.1–0.3 s for a new type": TraitMakie's data type is 77–97 ms. Write "0.08–0.3 s".
39. `design/evidence.md:3` names the final build 61852d8fb1; the branch's HEAD is a89a91629a (build script only). Add "(a89a91629a adds only `tw-build.sh`)".
40. `intro/traits-for-julia.md:80` gives the prototype spellings `@concrete_only`/`@warn_on_abstract` without saying the single declaration with a level is adopted and not built (`design.md:181`). One clause: "(the spelling will change to one declaration with a level)".

---

## Verdict per audience

- **Programmers** (`traits-for-julia.md`, `results.md`): readable without the glossary; the only core-developer term that slips in is "trait object", and it is defined where it appears. The worked example is correct TraitWorld code and runs with the stated outputs and error texts (finding 24). The pages are honest in tone and carry their caveats, with four substantive errors: the piracy example and the strict-mode promise (1), the CSV number's framing (2), "concrete type annotation" (10), and "your compiled code" (11); plus rounding in the trait's favour at (8) and the TBD markers (23). Fix those and the pages are publishable.
- **Core developers**: `design.md` and the companions agree with each other and with the code on the rules, the parts (A)–(D), the limits (four splits, six `Callable` arguments) and nearly all numbers. Three statements are false against the record or the code (findings 1, 3, 5), one presents stale evidence as current (4), and the test-bed switch has two names (13). No superseded design (four rules, layering, sealing, wrappers, representations, witness tables, view caches, stock Julia) survives except as marked history, with one history row misplaced (21). `porting.md` is the one document still written in the old moment (6).
- **Agents**: `INDEX.md` is accurate where spot-checked and complete enough to resume: it names the build, the lock, the logs' impermanence, every note and review with its status. Its weaknesses are the same-day-stale commit table (32), the "session 30" alias (33), one closed-looking item that is open (34), and four companions without a status row (35).
