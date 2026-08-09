# Design observations — improvements and simplifications

Running log (newest last). Feed into the community writeup and any Rung-3
proposal.

## Confirmed design changes (already adopted in TraitRegions)

1. **Plain-`Function` witness tables beat FunctionWrappers.** ~10× cheaper
   registration (no cfunction), no stale-pointer window (dynamic dispatch is
   always current-world), equally invalidation-immune, same steady-state cost
   on chunky signatures. FunctionWrappers' type enforcement is replaced by
   seal-time `return_types` checks. The design doc's "witness consistency:
   documented hole" row is obsolete — the hole was an artifact of the wrapper
   mechanism, not of the design.
2. **`@nospecialize` entries/registration are load-bearing**, not an
   optimization: they turn per-(op,T) entry compilation (~6.6 ms each) into
   one-instance-ever, pkgimage-cached code.
3. **Purely syntactic region rewrite + seal-time checking** decouples trait,
   seal, and region packages completely (no macro-expansion-order coupling).
   The trait declaration is consulted only at seal time — which suggests a
   deeper simplification: *the trait is a contract object, not a dispatch
   object*. A hypothetical native design could treat trait declarations as
   checkable metadata rather than types.
4. **One worker function serves both erased and `@full_compile` lowerings**
   (pass `s.w` erased vs `s.raw` concrete NamedTuple). No duplicate worker
   generation; fc is literally "the same worker, more type information" —
   a much cleaner story than the plan's separate fc lowering.
5. **The `haskey(w, :g)` branch unifies witness calls and cross-region op
   calls** at zero cost (NamedTuple haskey folds at compile time). The macro
   never needs to know the witness set.

## Evidence-backed conclusions for the writeup

6. **Static cross-region wiring erases the abstraction cost entirely**
   (X3: 0.99–1.31× plain Julia) while keeping flat TTFX (X1: 14 ms vs 25 ms
   and growing). This is the cleanest possible argument for native support:
   the mechanism is *known cheap*; only its soundness needs the compiler.
7. **The dynamic op-table only matters for tiny bodies** (5× at len=16,
   ≤1.2× at 256+). A native implementation's devirtualization matters most
   for fine-grained call graphs — coarse ones are already fine at Rung 1.
8. **Makie/plotting: the region machinery is free but wins nothing** —
   Makie's own per-session internals (~230 ms/first plot) dominate. Design A
   (Makie in-worker) shows no Rung-1 penalty; the case for the boundary
   pattern is invalidation guarantees and AOT eligibility, not TTFP. Do not
   oversell.
9. **Worker instances = representations × lowerings-used** (X5: 3 for 13
   types), and pkgimage ownership of a novel representation's workers by its
   conformer package works today via `precompile_seal`.

## Friction found (candidates for native support / #54903 arguments)

10. **The `__init__`/`reinit` dance.** Registries live in *other* packages'
    module state, and cross-package mutations during precompile are
    discarded — so conformers seal in `__init__`, region packages replay op
    registrations via `reinit(@__MODULE__)`, and every package must remember
    to do so. Native enrollment (Pkg/loading-level registration, à la #54903
    metadata) would delete this entire class of boilerplate. This is the
    single best concrete "why the language should own this" exhibit.
11. **Seal checks run at load time** (per conformer, per session) instead of
    once at precompile. Cheap today (~ms), but O(#conformers) at ecosystem
    scale; native would check at precompile/resolution.
12. **Return-type asserts at trait-call sites are user-written.** Correct
    but unenforced; forgetting one silently degrades downstream inference.
    Fix candidates: `@generated` workers injecting asserts from the trait
    declaration (Rung-1-compatible, adds complexity), or native lowering
    (trivial). Worth prototyping only if the writeup needs it.
13. **`Base.return_types` at seal time is best-effort** and silently
    degrades to arity checks when inference returns `Any` — fine for a PoC,
    unacceptable as a guarantee; native gets this from declared signatures.

## Simplification candidates (design is currently *more* general than needed)

14. The `Seal.R` field is only used for checks/enumeration — dispatch never
    consults it (the worker call dispatches on `typeof(r)` naturally).
    A native design needs R only as a cache key, which it derives itself.
15. `dyncall`'s per-call dict lookup could be cached (Ref per call site),
    but given (7), it's not worth complexity at Rung 1.
16. Traits with an empty witness set ("pure data" seals: project only) fall
    out for free — worth a demo op in the writeup since the design doc
    highlights them.
17. `imports` declarations could be inferred (any `g(t,…)` where `g`
    resolves to a loaded region op of the same trait) — but explicitness is
    the honest stand-in for enrollment metadata; keep as-is at Rung 1.

18. **The Makie speedup lives in marginal types, not the first plot (X8).**
    Idiomatic `convert_arguments` recipes respecialize Makie's pipeline per
    user type (~155 ms/type, unbounded); erased reduction holds Makie's
    types constant (~18 ms/type, flat). Frame plotting claims as "cost of
    the Nth custom type", never "time to first plot".
19. **`max_methods` union-splitting interacts with erased designs**: a
    generic caller above the erased entries pays a one-time ~100–350 ms
    recompile when its call site sees a 4th distinct type. Not an
    invalidation; once per session; worth documenting so users don't
    misread it as the abstraction failing. A native implementation could
    avoid it entirely (entries wouldn't exist as dispatchable methods).

20. **Pkgimages drop native code for foreign runtime-dispatched CIs (X9).**
    Workload-compiled Makie signatures survive with `cache=true, native=false`
    — first use pays pure LLVM codegen (~250 ms/session), zero inference,
    zero recompile. No package-level workload or @recompile_invalidations can
    fix it; a sysimage or AOT does. Cite as: erased designs make workloads
    *enumerable*, but Rung 1 inherits Julia's native-code retention policy —
    one more per-session constant that native support (or juliac over the
    closed universe) eliminates.

21. **Rung-2-lite via `invoke_in_world` (X10).** Sealed resolution's
    semantic fork needs no custom interpreter to demonstrate: pinning
    resolution to a registration-bumped universe world gives constructive
    piracy-immunity (pirate invisible inside regions, applies outside,
    0 ms recompile, blame names the offender) in ~30 LOC. The full
    interpreter spike's remaining value is *territory* (allowlist/closure
    rule) and AOT enumerability — cite `invoke_in_world` as the existing
    precedent that world-pinned execution is already in the language.

22. **Sealed resolution cannot be a post-filter (X11).** jl_matching_methods
    drops methods fully shadowed by a more-specific match, so filtering a
    pirate out afterwards leaves its universe-internal victims missing; the
    spike recovers them by direct method-list search. A native
    implementation should restrict the table *below* the matcher. Also:
    OC-from-IR wants argtypes[1]==typeof(env); MethodTableView needs
    isoverlayed. Stage A core: ~120 LOC total on the 1.12 Compiler stdlib.
