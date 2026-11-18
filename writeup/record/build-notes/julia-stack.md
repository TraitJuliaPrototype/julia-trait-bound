# Build notes: the stack of Julia's commits

How the commits of [the inventory](../../../design/julia-changes.md) were made and checked. In the agents' tier ([the record's index](../../INDEX.md)); moved here from the inventory by the documentation clean-up (W-162), unchanged.

## The stack to the tag

- **W-100 was developed on branch `w100`** from the stack's top (commits 24–35), and joined the stack when the stage was done. Its commits but 34 are confined to the facts mode, for a rebase onto vanilla when the series is proposed; 34 goes with the type system's commits.
- **Not carried yet,** each with the stage that needs it: the field-offset intrinsics (W-110); `known_type` (b5bb9ab881) and the registry of type printers (db82407fa6), which no stage of the references uses yet.
- **Not carried:** the invalidation filter and its hooks (pieces 2 and 4, reverted on `trait-world-1.13`), the remembered validation (reverted there), build scripts.
- **The measured first build of stage 1,** fd800b27b9 (the W-98 gates' and E-270's build; commits 13 and 14 are its code with their comments cleaned, the same after comments are stripped), is kept on branch `w98-fd800b27b9`.
- **How the stack was checked (2026-11-06 and 07;** `experiments/unification/stack/README.md`**):**
  - each commit that changes the runtime's C code built on its own (`julia-src-release`); the Julia code of commits 1 to 3, 7, 9 to 12 was built only with the others, at the checkpoints; the MMTk collector's lines are not built (the stock collector is);
  - full builds at the eleventh general commit and at each stage's top, with Base's `core`, `subtype`, `worlds`, `ambiguous`, `reflection`, `reinterpretarray`, `Compiler/inline`, `Compiler/inference`, `ccall`, `precompile`, `exceptions` and `threads` test files, the unification gates, E-262's four files, E-270's and E-269's questions. `threads` fails one BLAS-threads case the same way on vanilla (env.sh's `JULIA_CPU_THREADS=4`);
  - **found and fixed on the way:**
    - the exact-type entries of the per-call-site cache made a type of a 1.2×10⁸-argument splat in Base's `core` test (74 against 59 s, 4.4 against 2.2 GB) and, at sites that see many types, slowed dynamic calls (170 against 137 ns over 50 container types). Bounded, then reused from the leaf cache, they still cost such sites 50 % more, so they are not carried ([PE-20](../../record/performance-explorations.md)); the wildcard entries are (commit 4);
    - a method at an open set on `length` made method matching 48–60 % slower for non-members (E-269): commit 16, an intersection's disjointness by reachability, and the typemap's world range computed only where a membership can narrow it;
  - the top 3ad297247e (tag `measured-3ad297247e`; the measurements' build): gates 24 of 24; E-262's four files at vanilla's wall times (`core` 58.5 s, 2.2 GB); `reflection`, `reinterpretarray`, `Compiler/inline`, `Compiler/inference`, `ccall`, `precompile`, `exceptions` pass; TraitWorld's tests and both workloads pass; E-270 as on fd800b27b9 (run 6); E-269's third session: dynamic calls as vanilla's, method matching +3–18 % with a method at an open set (PE-21).
  - the final top, ec4f9a8714: the same code with two fixes from [the review of the `All` encoding](../../../attic/writeup/reviews/2026-11-07-all-representation.md) folded into commits 12 and 13 (a membership never absorbs a `Union` component; a set as a query's type meets any typename at a split typemap level): gates 26 of 26 (`m2_union_normal_form`, `m2_set_query_split` new), E-262's four files at vanilla's times.
  - the top with W-107, 8a9144928e (commit 18, the probe branch `w107-probe` folded; [the review of the encoding](../../../attic/writeup/reviews/2026-11-07-all-representation.md) and its addendum): gates 32 of 32; E-262's four files at vanilla's times; the six other files, `precompile` and `exceptions` pass; `detect_ambiguities(Base)` 0; TraitWorld's tests and both workloads pass; E-269's session s4: matching with no method at a set 4–8 % above vanilla's (PE-22), dynamic calls as vanilla's.
  - the top with W-108, 28c401eb0c (commit 19): gates 33 of 33 (`n3_image_memberships` new: four packages on a fresh depot, both load orders, a call before and after the membership's load, an image built without it); E-262's four files at vanilla's times; the six other files, `precompile` and `exceptions` pass; `detect_ambiguities(Base)` 0; TraitWorld's tests (the override rule, the module's end) and both workloads pass.
  - W-109's first three commits, e70675a606: gates 33 of 33; E-262's four files at vanilla's times; the six other files, `precompile` and `exceptions` pass; `detect_ambiguities(Base)` 0; TraitWorld's tests (operation results, the split, the table) and both workloads pass.
  - W-109's top, 50da8d8ee2 (commit 23): the same, with TraitWorld 59134ef's `declared fields` and `classification`; Base's `core` test lists the new atomic field of `TypeName`.

## Branch `next`

- **How it is checked** (`experiments/unification/w155/README.md`): after each commit Base's `core`, `subtype`, `Compiler/inline` and `Compiler/inference`, the deep class's gate `gate_deep.jl`, the library's suite on its branch `w155`, and the forks' session digests (E-417, E-419).
- **W-160's rows** (`experiments/unification/w160/README.md`): after each commit Base's `core`, `subtype`, `Compiler/inline` and `Compiler/inference`, the library's suite on `unified`, the ports' suites, and the row's gate (E-436 to E-442).

## Branch `next-s3`

- **How it is checked** (`experiments/unification/w155b/README.md`; for s3-7 on, `experiments/unification/w157/README.md`): after each commit Base's `core`, `subtype`, `Compiler/inline` and `Compiler/inference`, the row's gate, the library's suite on its branch `s3`, and the forks' session digests. Stage 5's rows also: the census of the deep class (`w157/census.jl`), the test files of the Base files they touch, and what plain Julia pays (E-479).
