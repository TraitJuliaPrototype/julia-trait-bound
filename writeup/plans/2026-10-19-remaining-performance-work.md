# Remaining principled performance work (2026-10-19, evening)

This list continues `2026-10-19-principled-speed-plan.md` after a day of work on it. It records what is done, then what remains, in the order proposed.

## Done today

- **Step 0, the ground truth.**
  - A quick BaseBenchmarks subset: 148 benchmarks, about 3.5 minutes.
  - The ~990 ms after the loads is diagnosed: about 700 ms of plain `return_type` inference (the price of identical answers), and about 280 ms of `CSV._parse` compiled again because SparseArrays' `vcat` wins inside it. Plan: `2026-10-19-return-type-after-loads-plan.md`.
- **Step 1, world-checked caches.** The `cfunction` calling convention `:caller_world`: `DynamicCall` runs in the caller's world (G1.20, G1.21), at the same cost (4.47 ns).
- **Step 3, cheaper entries.**
  - Facts code is inlined into plain callers: typed trait calls 2.6 → 0.8 ns, as plain Julia.
  - Untyped calls 51 → 25–29 ns through (c), the table of declared implementations.
- **Step 4, compiling ahead.** A declared implementation's workers, entry methods and first-call checks come with the declaring package's image.
  - For types compiled ahead: an entry method of their own, so an untyped call is one dispatch (about 14 ns).
  - For every other type: (c), compiled once per key.
  - The first untyped call with a new type takes 3–4 ms instead of 90.
- **Step 2, guarded devirtualization:** postponed (the user).

## Remaining, in the order proposed

1. **World-checked inline caches at dynamic call sites** (`2026-10-19-inline-caches-plan.md`). The unifying mechanism for:
   - the facts mode's run-time sites (the BaseBenchmarks tails under `all`);
   - the `Dynamic` split's fallback (step 1's remainder);
   - untyped trait calls ((c) becomes its environment word).

   Staged: a runtime-side cache first, then codegen. It replaces the separate work on step 1's remainder and on (c)'s pointer path. As a cache of dispatch results, without speculation, it is also the answer to step 2's goal without step 2's cliffs.
2. **Step 5, the machinery's own startup.**
   - TraitWorld's slow paths compiled into its own image.
   - The clean-case `@implement` cost: 77–97 ms, against 36 ms on the previous prototype.
   - Checks' results kept in images: started in step 4 for workers.
3. **The ~990 ms after the loads** (the Fable plan):
   - a differential test of `return_type` answers, with stock Julia as the oracle;
   - then red-green revalidation of the cached answers, as rustc and Salsa do and Julia's own `reinfer.jl` (estimated 400–600 ms of the 700).

   The `vcat` part waits on whether the standard libraries should be separate owners (an open design question).
4. **A measurement round on a quiet machine:**
   - the call benchmarks;
   - the quick subset;
   - the demonstrators' rows, including what an entry method compiled ahead costs a package's image;
   - once, the full BaseBenchmarks.

   The documents still show the old entry costs until then.
5. **Smaller items:**
   - `Callable` with abstract argument types still goes through the pointer's dynamic adapter (about 30 ns). The `@nospecialize` fix of the untyped path applies, with care for concrete signatures. Item 1 may subsume it.
   - Whether a constant `DynamicFn`, whose pointer is folded into compiled code as an address, survives in package images.
   - The first-call check flag: one load per typed call.
   - The TraitMakie image flake, seen once in five runs: a correctness watch.
6. **Upstream proposals,** each general for Julia:
   - caller-world `cfunction`s;
   - inlining from another owner's cache;
   - `known_type`;
   - the two inliner changes;
   - the run-time `return_type` entry in the image;
   - reflection in the compiler's world;
   - later, item 1.
7. **Step 2,** only if untyped code under `all` still matters after item 1.

## Why this order

- Item 1 is the broadest gain and the most principled: one mechanism for three problems, proven in other languages, with no change of semantics. Its first stage is a small runtime change that is quick to measure.
- Item 2 removes first-call costs that every session pays, independent of item 1.
- Item 3 has a plan, needs a differential test first, and is larger.
- Item 4 must come before any numbers in the documents change.
