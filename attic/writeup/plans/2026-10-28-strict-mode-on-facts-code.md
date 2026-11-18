# Strict mode on facts code, and its error at an image's load (W-66, step 3)

Status: **done** (2026-10-28, mine; W-66; TraitWorld 0976025, E-198), revision 2: after [its fresh-eye review](../reviews/2026-10-28-strict-mode-on-facts-code.md) (§7). Not normative. Its choices are for the user's confirmation in W-71's review session.

## 1. What it is for

- The user (2026-10-27): "Take up strict mode with W-66", and "Agreed on your suggestions on how to incorporate the facts first Julia reviewer": [the facts-first review](2026-10-27-facts-first-julia-work.md) §2.1 (strict mode on code of the facts owner) goes into W-66; its narrowing of what strict mode protects is on W-71's list.
- [W-66's note](2026-10-27-facts-keyed-cache.md) §3, step 3: strict mode's intended design (F-6), with no store.

## 2. The index for package images, not now

- It is an architectural change that facts enable (the rule's first clause). It is set aside by the rule's other clause: a minor speedup for a change to Julia's loader. Its bound and builds are in [PE-8](../record/performance-explorations.md).
- Its natural time is with the store (step 4), whose entries it validates anyway.
- **So strict mode at load does not wait for it.** Row 1 of facts §10.3 is found from validation's own record instead (§4). The user's decision placed strict mode at load on the index ("images of facts code validated against a session index of candidate methods … strict mode is the policy for a winning candidate"). Moving it to validation's record is mine, recorded in the decision log and listed for W-71. The index form is in `design/alternatives.md`.

Two parts follow, both in TraitWorld, with no Julia change.

## 3. Part A: what strict mode protects

**The rule.** Strict mode protects **code of the facts owner**. A pirate is refused if it would win at a fact of such code, or at a fact of plain code that such code rests on, through these plain classes only:
- the plain answers `return_type` folds (owner `:facts_plain_return_type`);
- the compiler's own code (`jl_method_is_plain`);
- **plain code of Julia's own methods** (Core, Base, the standard libraries), of owner `nothing`. The compiler's code calls them, and facts code that calls the compiler directly (TraitWorld's machinery) rests on them (the review's B1).

**In the code** (`TraitWorld/src/strict.jl`):
- `_trait_world_code(ci)` is `ci.owner === :facts`.
- `_trait_dependent` walks up through callers of the three classes above. Any other plain caller is dropped before `typeintersect` and `_would_win`.
- The safety net (`_strict_after!`) uses the same predicate.

**Why it is sound:** code of the facts owner holds edges to plain code only through `return_type`'s answers and the compiler's code (the mode rule; facts §6.4). The compiler's code rests on the compiler and on Julia's own plain code. Invalidation follows owners (`src/gf.c`, `_invalidate_backedges`): plain code that facts code does not name, directly or through these classes, never invalidates it.

**Edges the walk does not test, before and after** (named, not changed here):
- a generator's reported edges, and an `invoke` at a method's own abstract signature (the review's m1);
- results of constant propagation from plain callers into facts code, which live in the plain caller (m2);
- folds and the definition checks' verdicts, which are values (m3);
- run-time sites and the split's fallback: they record no edge. Strict mode is about invalidation, not about what a run-time site calls (m4).

**What it gives up:** a pirate that wins only in plain code of a package (not Julia's own), of TraitWorld, or of a trait module's plain entries is no longer refused. That code is compiled again, as in plain Julia. Code of the facts owner is not affected.

**What "code of the facts owner" is:**
- In the product setting: trait code; TraitWorld's machinery (`@machinery`); the split's thunks; Base methods compiled by facts for them. It is more than trait code. Most of it is code trait code depends on.
- Under `all` after W-22: all code but the compiler's and Julia's plain code that the compiler calls. So under `all` strict mode refuses a pirate winning at a fact of any package's compiled code (the review's M4).

**Depends on W-22:** before it, under `all` code compiled by facts had owner `nothing`.

## 4. Part B: the error for a pirate loaded before an image

[Facts §10.3](../reference/facts.md#strict-intended), row 1: in strict mode, "a pirate loaded before a package image whose facts it breaks" is an error "at the image's validation, naming the pirate and the code". Today the image's code is discarded at validation and compiled again, silently (F-6).

**The record.** Validation writes its own log: `Compiler.ReinferUtils.debug_method_invalidation(true)` switches it (`Compiler/src/reinfer.jl`). It is not the runtime's log, which strict mode's safety net uses around a definition; the two never meet (the review's B2).

**Its lifetime** (the review's M1):
- In strict mode the validation log is on for the session: switched on at `strict!(true)` and at TraitWorld's `__init__` under `JULIA_TW_STRICT=1`.
- Every package callback reads the entries and empties the array in place. If another tool switched the log off or replaced it, the callback turns it on again with a fresh array, and never empties an array it did not make.
- No part depends on the image hook. Images without external methods, nested loads (one `using` restores several images) and extensions loaded inside callbacks are covered.
- Not while an image is being generated (`jl_generating_output()`): a precompile worker's report would be lost in its log (m7).
- **Its cost:** with the log on, validation does not stop at a CodeInstance's first failed edge, and matches without a limit. Both apply only to failing edges. Measured in E-198.

**Reading an entry** (`(edge, "insert_backedges_callee", codeinst, matches)`; the review's M2):
- Only call edges: `edge` a `MethodInstance` or a signature. A `FoldRecord` or `Binding` entry is skipped: its `matches` is stale.
- For each split of the edge's signature (`_fact_splits`): the method dispatch selects there now, or an ambiguity. A listed method that applies without winning is not a cause.
- The cause is a pirate if its definer is no stakeholder of that split, no delegate of one, and not Julia's own.
- **A stakeholder's package extension** is row 3 of §10.3: a warning, not an error.
- The CodeInstance concerned is `codeinst` if its owner is `:facts`. If it is a `:facts_plain_return_type` answer, the `verify_methods` entries `(child, "verify_methods", cause)` lead to the facts callers in the image.

**The report.** A `PirateError` naming the pirate, the image's code and the fact, reported by `@error` in the package callback.
- **It is a report, not an exception** (the review's M3). The pirate came first and is active, and the image's methods are active before validation. A load cannot be undone halfway, and a package callback's exception is caught by Julia (`base/loading.jl`, `run_package_callbacks`). The image's broken code is compiled again, with the pirate: trait code computes the pirate's result.
- So facts §10.3 row 1 reads "reported at the load". This weakens what §10.3 states; it is listed for W-71.
- **A stronger form, not taken now:** the affected trait module's entries raise the recorded `PirateError` when called. New machinery; in `design/alternatives.md`.

**The Julia form, not taken now:** compiler §5.4's piece 15 proper, a few lines in `_include_from_serialized` that pass a flag-gated log per image to a callback. Exact per image, nothing shared. Part B relies on an internal interface (`ReinferUtils.debug_method_invalidation` and the entry format), which may change with Julia; compiler §5.4 names it.

**Still in F-6:** a deletion of a method that trait code depends on (row 5; piece 1′). A binding redefined from another module (row 4) is facts §2.2's exception; F-6 is restated to name it.

## 5. Checks: E-198 (registered before it runs)

- **Part A:**
  - (a) one C session in strict mode in E-168's shape, before and after: the load, `TraitWorld._STRICT_STATS`, `_REFUSED_PIRATES` listed;
  - (b) D in strict mode before and after (E-180's shape);
  - (c) TraitWorld's suite, its strict tests, `experiments/docs-examples/strict.jl`, the acceptance; the OffsetArrays `reshape` case of `intro/porting.md`;
  - (d) B1's chain: a pirate on a Base function at a signature the compiler's code calls, after TraitWorld's machinery has run: refused;
  - (e) a strict session under `all`, or the case recorded as untested.
  
  **Would change the plan:** a refusal the user's examples show coming only from plain code outside the classes; walking a small part of strict mode's cost.
- **Part B**, a test with a pirate package loaded before a trait package whose image has a fact the pirate wins:
  - strict mode on: a `PirateError` reported naming both; off: silent, the pirate's result (G1);
  - a pirate that wins nowhere in the image: no report;
  - a fact with two splits, the pirate winning at one;
  - a fold failing beside a call edge in one CodeInstance: no report against the fold;
  - the pirate in a dependency loaded by the same `using`; an image that extends no other module's function; an extension of a stakeholder (a warning);
  - the log's cost on C's load in order B.
- **`twolibs`**, the adopted acceptance case of the intended design (decisions §4), if it exists by then; else named as missing.

## 6. Where it would be recorded

- [Facts §10.2](../reference/facts.md#strict-mode): rule 2, "How it finds the facts", "What it protects" (code of the facts owner, and what that is in each setting), the note on other code, "Not refused" (folds, the checks' verdicts).
- [Facts §10.3](../reference/facts.md#strict-intended): row 1 Implemented as a report; F-6 restated (rows 4 and 5). §11's status. §12.2: strict mode under `all`.
- [Traits §10.3](../reference/traits.md) status and its note on protecting other code; `state.md`; `intro/porting.md` (the OffsetArrays case, by E-198's result).
- [Compiler §5.4](../reference/compiler.md#54-planned-hooks-for-strict-modes-intended-design): piece 14 not needed (the narrowed walk); piece 15 used in its internal form, named; 1′ and a binding hook remain. `design/julia-changes.md` §3.
- The decision log, marked mine, with W-71: the narrowing; row 1 by validation's record, reported. `design/alternatives.md`: strict mode protecting plain code of packages, TraitWorld and trait modules' entries; strict mode at load by the index; the stronger form of row 1.
- PE-8 corrected.

## 7. The review, and what is done with it

[The review](../reviews/2026-10-28-strict-mode-on-facts-code.md) (fresh eyes, Opus, of revision 1):
- **B1** (the compiler's Base callees): option (a), Julia's own plain code walked through (§3). Option (b), no edges from facts code to the compiler's code, removes the class and G2's exception, but touches a decision of the user's: listed for W-71.
- **B2** (the wrong log): validation's own log (§4).
- **M1** (the log's lifetime): on for the session in strict mode, read in every callback (§4).
- **M2** (reading entries): §4's rules.
- **M3** (a report, not an error): stated, listed for W-71; the stronger form in alternatives.
- **M4** (`all`): §3; E-198 (e).
- **M5** (PE-8's clause; the changed mechanism): §2; PE-8 corrected; decision log and alternatives.
- **M6** (copies): §6.
- **m1–m4:** named in §3. **m5:** §2 cites PE-8. **m6:** §5. **m7:** §4. **m8:** moot with a session-wide log.
