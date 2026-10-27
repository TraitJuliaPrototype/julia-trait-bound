# Strict mode on facts code, and its error at an image's load (W-66, step 3)

Status: **proposal** (2026-10-28, mine; W-66). Not normative. For a fresh-eye review before it is built.

## 1. What it is for

- The user (2026-10-27): "Take up strict mode with W-66", and "Agreed on your suggestions on how to incorporate the facts first Julia reviewer": [the facts-first review](2026-10-27-facts-first-julia-work.md) §2.1 (strict mode on code of the facts owner) goes into W-66; its narrowing of what strict mode protects is on W-71's list for the user's confirmation.
- [W-66's note](2026-10-27-facts-keyed-cache.md) §3, step 3: "the index for package images: open issue 73's lever and strict mode's intended design (F-6), with no store. Its gain is to be stated before the build."

## 2. The index for package images: its gain, stated

- Its bound: validation is about 1.4 s of stock's load (E-185); remembering the outcome of all of it saves 0.6–0.8 s (E-186); facts code is 11% of what C loads. So the index saves at most about 0.1–0.15 s of C's 4.3 s load.
- Julia's validation already takes a fast path where an edge's method dominates its signature or its interference set is covered (`Compiler/src/reinfer.jl`, `verify_call`).
- **Mine:** not built now. It is [PE-8](../record/performance-explorations.md). Remembered validation, with about five times the gain, was set aside (PE-1). The index stays the tool for the store's entries (step 4).

So step 3 is strict mode's intended design, without the index. Two parts, both in TraitWorld, with no Julia change.

## 3. Part A: strict mode protects code of the facts owner

As the facts-first review §2.1 states it:
- `_trait_world_code(ci)` is `ci.owner === :facts` (`TraitWorld/src/strict.jl`).
- The walk up through plain callers (`_trait_dependent`) follows only CodeInstances of owner `:facts_plain_return_type` and of the compiler's own methods (`jl_method_is_plain`). Any other plain caller is dropped before `typeintersect` and `_would_win`.
- The safety net (`_strict_after!`) uses the same predicate.

**Why it is sound:** by the mode rule, code of the facts owner holds edges to plain code in two classes only: the plain answers `return_type` folds, and the compiler's own code. Under `all`, W-22 removes the third class, the shared default owner (C-2). So a pirate invalidates trait code only at a fact a `:facts` CodeInstance records, or at a fact inside those two classes, reached through their callers.

**What it gives up:** a pirate that wins only in plain code of Julia, TraitWorld, or a trait module's plain entries is no longer refused. That code is compiled again, as in plain Julia. Trait code is not affected.

**Depends on W-22:** under `all` before W-22, other packages' code compiled by facts has owner `nothing`, and part A would stop protecting it. Part A is built after W-22.

## 4. Part B: the error for a pirate loaded before an image

[Facts §10.3](../reference/facts.md#strict-intended), row 1: in strict mode, "a pirate loaded before a package image whose facts it breaks" is an error "at the image's validation, naming the pirate and the code". Today the image's code is discarded at validation and compiled again, silently (F-6).

**How, with Julia's own record:**
- In strict mode, TraitWorld's image hook (`_on_image_methods`, called before the image's methods are activated, in the same load as its validation) starts Julia's invalidation log (`jl_debug_method_invalidation`), as the safety net does around a definition.
- Validation (`insert_backedges_typeinf`) writes an entry for each edge it rejects: the edge, the CodeInstance, and the methods that match now (`"insert_backedges_callee"`).
- After the load (the package callback, where `_report_refused_at_load` already runs), TraitWorld stops the log and reads it. For a rejected CodeInstance of owner `:facts`: a matching method whose package is no stakeholder of the edge's signature, nor a delegate of one, and is not Julia's own, is a pirate that broke the image's facts.
- **The error:** a `PirateError` reported at the load, naming the pirate, the image's code and the fact. It is reported as strict mode's refusals at a load already are: by `@error` after the load, since a load cannot be undone halfway. The image's broken code stays discarded and is compiled again, with the pirate.

**Why the log, not a Julia hook:** compiler §5.4's piece 15 ("image validation that reports the winning method") is what the log already gives, when it is on. It is on only in strict mode, and only for the span of one image's load.

**Limits:**
- The hook is not called for an image without methods. Such an image's facts code is reported only if a later image's load turns the log on. The proposal: start the log in the package callback of the previous load as well, or accept the gap and record it in F-6.
- The log also records the invalidations of activation (plain code), which strict mode reads past.
- Deletions (row 5) and a binding redefined from another module (row 4) need Julia hooks (piece 1′ and a binding hook). They stay in F-6.

## 5. Checks (to register as E-197 before they run)

- **Part A:**
  - (a) one C session in strict mode in E-168's shape, before and after: the load, `TraitWorld._STRICT_STATS`, `_REFUSED_PIRATES` listed;
  - (b) D in strict mode before and after (E-180's shape);
  - (c) TraitWorld's suite, the strict tests, `experiments/docs-examples/strict.jl`; the acceptance.
  
  **Would change the plan:** a refusal that the user's examples need coming only from plain code; or walking a small part of strict mode's cost (then the cost is ownership or compiling the strict code, and the fix is elsewhere).
- **Part B:** a test with a pirate package loaded before a trait package whose image has a fact the pirate wins: strict mode on reports a `PirateError` naming both; off, the load is silent and the result is the pirate's (G1). A pirate that wins nowhere in the image: no report.

## 6. Where it would be recorded

- [Facts §10.2](../reference/facts.md#strict-mode): rule 2 at "a fact of code compiled by facts, or of the plain answers and the compiler code it rests on"; the note on protecting other code goes.
- [Facts §10.3](../reference/facts.md#strict-intended): row 1 Implemented; F-6 keeps rows 4 and 5.
- [Compiler §5.4](../reference/compiler.md#54-planned-hooks-for-strict-modes-intended-design): pieces 14 and 15 not needed (the narrowed walk; the log); 1′ and a binding hook remain.
- The decision log, marked mine, with W-71 (the narrowing); `design/alternatives.md`: strict mode protecting plain code of Julia, TraitWorld and trait modules' entries; and the index for package images (PE-8).
