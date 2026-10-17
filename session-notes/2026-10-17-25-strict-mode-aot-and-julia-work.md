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
- **Removal merged** (TraitWorld main b60b126): calls, wrappers, sealing, filter, doors, layering, audit, guard and `mode!`; −1837 lines; 308 tests on both 1.13.2 builds; demonstrators, acceptance 16/16 and the hunt pass. Notes rewritten by a subagent (1-overview, 4-details, 3-wrapping; a banner in 2-design-choices). Design repo commit 28c494e.
- **Strict mode implemented** (TraitWorld 7b328a5, `src/strict.jl`, `test/strict.jl` 32 checks).
  - **Rule:** refuse a pirate (rule 3, `owned_method`) that would win at a fact of valid trait-world code, unless it is a declared delegate. Checking ownership of the *method* (not of the fact's signature) is needed: an owner's method on its abstract type wins at other packages' subtypes. It also gives the fast path.
  - **Implementation:** a pre-check over the backedges of the specializations the method could take over, and over the method table's missing-method backedges; Julia's invalidation log after the definition as a safety net; image methods left inactive.
  - **g2all interleaved, strict on:** nothing refused, 0 misses, nothing lost.
  - **Load cost:** at first +6.6 s on CSV, DataFrames and CairoMakie (ownership 100 µs per method; the owner memo had been dropped by the removal). After the memo and the fast path: 4.68 s against 4.14 s (65,318 methods checked in 0.16 s; 837 pirates by the letter walked in 0.49 s; none refused).
  - **Prompt definitions:** `SU.scale(x::Float64) = …` typed at the prompt is the session's, a pirate by the letter, and refused. `@eval SU …` (as Revise attributes edits) is the owner's.
- **The user asked:** what would strict mode need so that compiled trait code is never invalidated? My answer:
  1. pirates loaded before an image: an image-validation report (Julia piece 15) and an error;
  2. dependence through native code: a transitive check (piece 14), and `twolibs` as acceptance for the machinery's registries;
  3. extensions' winning methods at signatures without their triggers' types: refused;
  4. deletion: a deletion hook (piece 1′);
  5. edits: the one exception.

  The user: "Record what you gave above as the intended design for strict mode. Defer concrete work on it for now." Recorded in `strict-mode.md` §2b, `decisions.md` and `julia-support.md` (pieces 15 and 1′, deferred).
- **Piece 10 built** (julia-1.13, Compiler only: `handle_invoke_expr!` inlines exactly a foreign CodeInstance it is given; the CodeInstance edge dedup compares owners). TraitWorld branch `inliner-fix` drops the call-site `@noinline` when the runtime has it (`_INLINER_KEEPS_CI`; `JULIA_TW_NOINLINE=1` forces it back).
  - **Typed calls:** 33.0–35.8 ns, against 38.0–39.5 ns with `@noinline` (plain about 30). Untyped calls unchanged (108–123 ns).
  - **Tests:** suite 340/340, acceptance 16/16, the hunt passes except C24b (the harness bug), both demonstrators pass.
- **Piece 10 committed:** julia f72f7368f0, TraitWorld 1871c4e (main), experiments 876f104 (typedbench, aot/).
  - **g2all with the fix:** 0 lost in both load orders; the first work in "before" takes 147 ms.
  - The 41–309 s loads in that run were cache rebuilds after the new system image.
- **The user on AOT:** "AOT means no LLVM in the binary … now we have made calling ordinary Julia code easy, so we don't get any benefits there … whether some additional aot focused annotations when calling ordinary code from trait world would be possible."
  - Answered in `aot-under-facts.md` §6. The policy already lists, per call into ordinary code and at the trait package's build, the run-time sites (Theorem 3). That over-approximates the binary's holes.
  - **Options:**
    - A: a report at package build;
    - B: `@closed` calls, a build error otherwise;
    - C: result assertions at the boundary;
    - D: `@targets` lists for open sites;
    - E: `@interpreted` calls (needs Julia piece 16, an interpreter fallback in trimmed binaries).
  - **Recommendation:** prototype A and B with the first binaries; C as the stated pattern; D and E after the CSV binary.
