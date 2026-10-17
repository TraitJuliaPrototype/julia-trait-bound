# Session 25: strict mode, AOT, the Julia work (running notes)

The user (start of session 25, after a state-of-play summary): "I want to keep the option open to have strict mode, so trait code is never invalidated. If it rarely happens anyway it's cheap in terms of user friction but powerful as a guarantee. I want an assessment of how that plays with the easy AOT goal. Finally review the proposed Julia work and go ahead in any order you like. Make the decisions that need to be made."

**State at the start:** TraitWorld main ef43b3f, julia-1.13 `trait-world-1.13` 5b5b98758f, experiments 8c028b3; design repo 2e35981. Wrapping by facts validated in session 24 (acceptance 16/16, g2all 0 lost).

## Plan

1. The assessment: `writeup/explorations/strict-mode.md` (strict mode under wrapping by facts; how it plays with AOT). Reviewed by a subagent.
2. The Julia work reviewed: `writeup/explorations/julia-support.md` re-ordered for wrapping by facts with strict mode kept open.
3. Decisions recorded in `writeup/decisions.md`.
4. The documents brought up to date (README, writeup/README, open-issues, banners).
5. Code: remove what wrapping by facts replaces (filter, sealing, wrappers, declared calls).
6. A strict-mode prototype and its measurements (how often it fires, what it costs).
7. Then, as time allows: new trait code after big loads (the checks' recursion); a trimmed binary under the current design.

## Log
- **Assessment written:** `writeup/explorations/strict-mode.md`.
  - **Rule S:** a dispatch in the policy's code that selects a hidden method raises `HiddenMethodError`. Hidden means a pirate relative to the site: outside the platform and the dependency closure of the site's module and of the signature's type owners.
  - **No snapshot is needed,** unlike the views design's lenient mode, since strict never runs the overwritten method.
  - **Implementation on the policy:** hidden winners at concrete signatures become run-time sites, and run-time sites are checked. A later winning pirate breaks the fact through Julia's exact invalidation, once.
  - **"Never invalidated", literally,** is only possible by ignoring pirates silently (lenient), which breaks "identical or error". Rejected.
  - **AOT:** in a closed world strict mode is a build-time listing with no run-time cost at sites without hidden candidates. It gives reproducible binaries and per-package reachable sets.
  - **The real AOT question is independent of strict:** dropping layering means plain callees have plain Julia's trim properties (pay-off 2 needs restating). `--trim` builds compile the plain call natively, which is right (G1 by definition, no G2 in a binary). So no Julia piece is needed for trimming foreign CodeInstances.
  - A review subagent is running (the Fable reviewer hit its usage limit; rerun on Opus).
- **Julia work reviewed** (`julia-support.md`, new section):
  - **Dropped:** pieces 2 (invalidation hook), 4 (post-inference hook) and 6 (codegen dispatch check).
  - **Kept:** 1 (attribution for strict mode), 3, 5, 7 and 8.
  - **Added:** 9–12 from session 24, and 13 (instrumentation of foreign CodeInstances).
  - **Piece 11 found half-declared in 1.13:** `Core.OptimizedGenerics.CompilerPlugins.typeinf`/`typeinf_edge` ("the optimizer has license to" resolve `typeinf` at compile time), never implemented by the compiler. Implementing that half is piece 11, which removes A4 and the generator.
  - **New order:** 10, 9, 11, 12, 5, 13, 1, 3, then 7 and 8. The first upstream proposal is "first-class foreign cache owners".
- **Decisions recorded** in `decisions.md` (s25 rows):
  - strict mode kept as an option, in rule S's form;
  - lenient views rejected;
  - follow plain Julia by default;
  - AOT builds compile the plain call;
  - pay-off 2 restated;
  - the Julia work reviewed;
  - the machinery replaced by wrapping by facts removed;
  - `LDual` superseded.
- **Documents:**
  - `writeup/README.md`, `open-issues.md` (§4 items 2 and 5 resolved; §4b triaged: F2, F4–F8 and F10 dissolved; F3, F9 and F11 open) and the root `README.md` plan are updated.
  - The notes (1-overview pay-off 2, 4-details rule 1 and AOT, 3-wrapping) are still to be rewritten.
- **Removal of the replaced machinery delegated** to a subagent on TraitWorld branch `remove-wrapping`: calls, wrapper (with the filter), sealing, doors, layering, the native piracy audit and guard, the sealing and piece-4 parts of hooks. It runs the suites one Julia job at a time.
- **Hostile review of the assessment** (subagent on Opus). The main findings, all accepted, and `strict-mode.md` rewritten:
  1. **Critical:** a checked run-time site that calls native code checks only the first dispatch, and pirates below run unchecked. Sound strict mode keeps everything reached dynamically under the policy: a strict cache (a second copy of the Base code used there), a lookup and `invoke` per run-time call (about 0.5 µs), and trampolines at tasks, finalizers, `invokelatest`, callbacks and `invoke`.
  2. Core and strict compile different code, so one cache owner per mode, by a compile-time preference. A run-time switch is unsound.
  3. Strict mode does not reduce invalidation; it buys reproducibility of dispatch decisions. "Never invalidated" literally is a trade with rule P (a skip predicate plus a per-entry guard), not an impossibility. Deferred.
  4. AOT: native closed-world builds give no application-independent reachable sets (abstract facts range over the application's methods), and hidden methods cannot be dropped from a binary. Strict mode in AOT is a **pirate lint** at build: fail or warn, also useful under the core.
  5. Unverified risk: `--trim` is not in `CacheFlags`, so an image built without trim could carry policy-path entries into a trim build. To test.
  6. **Friction from split-core packages:** StaticArrays' `Base.size(::SArray)` (StaticArraysCore owns the type) is hidden at Base's `axes`, even for a library depending on StaticArrays. The view's granularity is an open choice: per callee with a platform list, delegates, or per entry.
  7. The local form holds for dispatch decisions only; deletions, `@eval` attribution, A3 values and global state are outside it.
- **Decision (mine):** before building strict mode in sessions, run a **friction census** (hidden selections in the code compiled by the demonstrators' workloads, with g2all's stack and a StaticArrays-keyed workload, under the three view granularities). Build the pirate lint into `verify_main`.
- **The user corrected both questions:**
  - "I meant AOT and the new wrapped by facts."
  - "I would love a mode that makes defining a winning pirate an error. If pirates never win then we never error."
- **New `writeup/explorations/aot-under-facts.md`.**
  - **What a build compiles:** builds compile plain Julia (native, closed world). That is right for G1 and G2 and better for trimming.
  - **What the trait world still gives:** listed runtime-type dispatch, mostly closed trait code, build-time checks.
  - **What wrapping by facts changed:** a declared boundary became a walked one. Plain code is as trimmable as in plain Julia.
  - **Risks:** images built without `--trim` (not in `CacheFlags`, confirmed) carrying policy-path entries; A3 values; slow paths.
  - **To measure:** three binaries (TraitMakie and Cairo; TDE and ForwardDiff; CSV/DataFrames).
- **`strict-mode.md` rewritten for the user's mode:**
  - **The rule:** a definition is refused if it would win at a trait-world concrete fact and its package is not a stakeholder.
  - **What it gives:** trait code is never invalidated by a pirate; G1 holds; no run-time cost; g2all shows it would have refused nothing.
  - **The exact check is Julia's own invalidation set,** asked for before activation: a new Julia piece 14, the read-only "would invalidate" query.
  - **Prototype:** a Julia-level pre-check over backedges, plus a safety net from the invalidation log.
  - **Split-core packages:** delegates kept as data.
  - **The symmetric "before" check** becomes a `verify_main` lint.
  - The `HiddenMethodError` mode is summarized and not pursued.
- **Decisions and julia-support updated** (piece 1's role; piece 14 added). The census script is dropped, since it measured the wrong mode. The notes agent was told the corrected mode.
