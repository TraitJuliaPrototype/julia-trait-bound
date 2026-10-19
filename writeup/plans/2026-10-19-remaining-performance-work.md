# Remaining principled performance work (2026-10-19, evening; revised after review)

This list continues `2026-10-19-principled-speed-plan.md`. It was revised after the Fable review (`../reviews/2026-10-19-inline-caches-review.md`) and the direct check of the same evening.

## Done today

- **Step 0, the ground truth.**
  - A quick BaseBenchmarks subset: 148 benchmarks, about 3.5 minutes. Its short budget sometimes leaves a single sample, so outliers must be rerun. Its geomean is over a selection of tails and controls, never the facts mode's cost.
  - The ~990 ms after the loads is diagnosed. Plain `return_type` inference is about 70% of the profile, about half of that in the optimizer. `CSV._parse` is compiled again because SparseArrays' `vcat` wins inside it: the Fable plan estimates about 280 ms. Plan: `2026-10-19-return-type-after-loads-plan.md`.
- **Step 1, world-checked caches.** The `cfunction` calling convention `:caller_world`: `DynamicCall` runs in the caller's world (G1.20, G1.21), at 4.47 ns.
- **Step 3, cheaper entries.**
  - Facts code is inlined into plain callers: typed trait calls 2.6 → 0.8 ns.
  - Untyped calls through (c), the table of declared implementations: about 25–29 ns.
- **Step 4, compiling ahead.** A declared implementation's workers, entry methods and first-call checks come with the declaring package's image.
  - A type compiled ahead has an entry method of its own: an untyped call is one dispatch (about 14 ns).
  - The first untyped call with a new type: 90 → 3–4 ms.
- **Caches at call sites, stage 1** (`2026-10-19-inline-caches-plan.md`). Exact-type entries in Julia's `call_cache` for calls whose cache entry is not a leaf signature: the facts tails on containers of `Any` were a lookup cost (verified by a profile with the fix off).
  - `push!(d, pop!(d))` 61.7 → 12.9 ns.
  - The quick subset under `all`: geomean 0.93, `collection` 0.60.
  - G1.22.
- **Step 2, guarded devirtualization:** postponed (the user).

## Correctness first

1. **The TraitMakie image flake:** "identical" broken once in five runs (a 3.3e-5 pixel difference). Reproduce, or rule out.
2. **A `const DynamicFn` in a package image: a real crash risk (checked by reading).** The image writer resets `Ptr` fields to null only in mutable structs (`staticdata.c`), and `Erased` is immutable: its pointer is saved as the old session's address, and compiled code may fold it in as a literal.
   - No demonstrator stores one (they make `DynamicFn`s at run time); a package that writes `const D = dynamic_fn(…)` would crash when `D` is called in the next session.
   - Fix: `Erased` holds the pointer in a small mutable cell, which the writer resets; a call that finds null makes the pointer again, once per session. One load and one compare per call.
   - Check: a package with such a constant, loaded from its image in a fresh session.
3. **Acceptance checks for the (c) path and its world ranges** (`_umiss`, `_pmiss`):
   - an implementation redefined;
   - a family member;
   - a generic implementation;
   - an `@implement` after the site was used;
   - an older world through `invoke_in_world`.

   Also the checks `implementation.md` §9.3 lists: the compiler-plain edges, held views, the inliner changes.
4. **Threads:** the new caches add lock-free readers, and the evidence page lists threads as untested.

## Performance, in order

1. **The measurement round, on a quiet machine:**
   - the call benchmarks;
   - the quick subset;
   - the demonstrators' rows, including what entries compiled ahead cost a package's image;
   - the full BaseBenchmarks, once.

   The documents' numbers change only after it.
2. **Step 5, the machinery's own startup.**
   - TraitWorld's slow paths compiled into its own image.
   - The clean-case `@implement` cost: 77–97 ms, against 36 ms on the previous prototype.
   - Checks' results kept in images: started in step 4 for workers.
3. **The ~990 ms after the loads** (the Fable plan): a differential test of `return_type` answers (stock Julia as the oracle), then red-green revalidation of the cached answers. The `vcat` part waits on whether the standard libraries should be separate owners.
4. **Call-site caches, the next steps** (inline-caches plan §3):
   - entries with an open `max_world`, also for step 1's thunk;
   - the facts owner's per-call normalization (a memo);
   - profiles of the remaining tails, and the size of `call_cache`;
   - the `Dynamic` split beyond four implementations, when a demonstrator needs it;
   - a codegen-emitted cache only if the profiles show lookup dominating.
5. **`Callable` with abstract argument types** (about 30 ns): the same fallback to a dynamic adapter that the untyped path had. The `@nospecialize` fix applies, keeping concrete signatures specialized.
6. **Upstream proposals,** each general for Julia:
   - caller-world `cfunction`s;
   - inlining from another owner's cache;
   - `known_type`;
   - exact-type entries in `call_cache`;
   - the two inliner changes;
   - the run-time `return_type` entry in the image;
   - reflection in the compiler's world.
7. **Step 2,** only if untyped code under `all` still matters after items 1–4.

## Why this order

- Correctness ranks above every performance item.
- The measurement round decides every number in the documents, and needs the quiet machine anyway.
- Steps 5 and the ~990 ms are measured costs every session pays: milliseconds to a second.
- The remaining call-site work is nanoseconds per call, on paths within 2× of plain Julia, or on untyped code that the user's rule lets traits recover.
