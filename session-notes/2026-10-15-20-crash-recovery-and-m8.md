# 2026-10-15 — Session 20: crash recovery, an ownership regression, the tolerations, demo 2

Intent: the machine crashed at about 08:59 while session 19 was waiting on
three background jobs; find out what was in flight, recover, and finish the
remaining work of M6–M8 (the trimmed binary's run, the full build, the
tolerations lists) before M9.

## What session 19 did after its note (reconstructed)

Session 19's note was written at 20:29 on 2026-10-14, before the usage limit
cut it off. After the limit reset it continued until 08:13 on 2026-10-15
without updating the note; its work is in the working tree and in
`poc/interfaces/README.md` and plan §10:

- the next-steps list of note 19: `_match` instead of `Base._which`, the
  interface registration at load (a package root is its own `parentmodule`),
  workload additions, the MakieInterface invalidation chain closed (plan
  §10.1, the slow path's typed loops), the `demo1.jl` step markers;
- M5 (`doors.jl`): the door lists, the check of globals, static module
  access (§10.8); demo 1 step 7 in TraitWorld's tests;
- M6 (`sealing.jl`): the scan by a walk over module names (§10.2), the
  rescan rules (§10.3), interface closures (§10.4), extension ownership from
  images (§10.5), scan state reset in `__init__` (the pirate-first order had
  found nothing because precompilation serialized the scan cursor);
  `BasePirate`; `x6_pirate.jl`, `x7_trees.jl`;
- M7: `x4_churn.jl`, `x5_redefine.jl`, `x8_types.jl`, `m0_plain.jl` run;
- M8: `verify_main` for keyword entries and declared calls (§10.9),
  `verify_app.jl`, the `Pipeline` package (§10.7), `build/`.
- 186 tests.

## The crash

The previous boot's journal shows memory pressure from 08:45 until the
crash ("Under memory pressure, flushing caches" every minute). Running at the
time, in parallel: the environment precompile followed by the measurement
chain, the untrimmed juliac build of `App` (CairoMakie included, started
about 08:06), and a third chain waiting to rebuild the trimmed binary. The
logs were in `/tmp` and were lost with the reboot; the transcript kept the
last results. The user runs other simulations on this machine: from now on
one heavy job at a time, `JULIA_NUM_PRECOMPILE_TASKS=4`, `nice`, and the full
build alone under a memory watchdog.

## Finding: an uncached ownership lookup made sealing 7× slower

The first rerun gave a demo 1 load of 29.4 s (README: 9.6 s) and a full
scan with Makie loaded of 16.2 s (README: 2.4 s). Cause: session 19's last
edit to `_extension_parent` (`ownership.jl`), which recognizes extensions
loaded from images, ends with a walk over all loaded modules calling
`Base.get_extension` for every package that is not an extension, and did
not remember the negative answer; the scan looks up the owner once per
method. Measured: 55 µs per lookup over 293 loaded modules; full scan 15.0 s,
2.0 s with a negative cache, the same 49 pirates. Fixed with
`_NOT_EXTENSIONS`, loaded package roots known not to be extensions, reset in
`__init__` (plan §10.10). After the fix: full scan 2.9 s, demo 1 load 9.1 s,
the one-line `@implement` 577 ms; 186 tests pass.

## The tolerations

`x7_trees.jl` (now emptying `TOLERATED` before each scan, so it shows the
raw audit): DataFrames' tree, 4 methods of Tables (DataAPI's `nrow`/`ncol`
on NamedTuples and vectors); Makie's tree with CairoMakie loaded, 49 methods
of 10 packages. Written into `[traits] tolerate`: DataFramesInterface
`["Tables"]`, MakieInterface the nine others (CompositionsBase, FFTA,
ImageCore, Interpolations, IntervalSets, Makie, OffsetArrays, PlotUtils,
StatsBase) and, after the review, Tables too (it is in Makie's tree). Demo 1 also reported Durations (CSV's dependency; it defines
`Dates.format`/`tryparsenext` for its own `DatePart{'n'}`), which is outside
any wrapped tree: tolerated by the project, `env/Project.toml`. Plan §10.4
said both lists stay empty; corrected.

Open question for the design: CompositionsBase's InverseFunctions extension
defines `InverseFunctions.inverse(::Base.Splat{typeof(∘)})`. Ownership
treats an extension as its parent only, so this is piracy, though the
extension exists because its trigger owns the function. Counting triggers as
owners would make it legal, and would be the natural reading of "an
extension is how an owner delegates" when the trigger is the owner of the
function. Not changed; for the note.

## Demo 2

`verify_main` on `App.main` (unchanged by the fixes): 5 declared targets
(`Figure`, `axis`, `vlines!`, `save`, `barplot!`), 1 entry, 2 workers; the
trait part closed, the build-time checks and audit clean; 140 normal-path
holes, all in the ordinary code: CSV 112, Base 17, DataFrames 11.

The trimmed pipeline: the binary built from session 19's last `Pipeline`
(with `readdlm`) died at its first dynamic call. With the concrete reader it
still died, at `readlines`' `EachLine.ondone`, a closure field of type
`Function`; `verify_main` had listed exactly that as a normal-path hole, as
it had listed `rpad`'s `repeat` and the `show` of a vector. `Pipeline` now
reads the file whole and prints one value per `print`. Result:
`verify_main` one normal-path hole (the builtin `invoke_modify` in Base's
scheduler `wait()`, which IO reaches and juliac handles); the binary
3.53 MB, 39 trim verifier warnings, runs in 0.02 s (49 MB RSS) with the
in-session result. The 39 warnings (classification corrected after the
review): 10 are the entry's two dynamic steps on the normal path of every
call, the builder and the worker call, to targets `verify_main` registered as
entry points and found by dispatch at run time; 26 are error, slow and check
paths the closed world skips; 3 are TraitWorld's `__init__` reading the
project's tolerations (no active project in a binary); none is in the
pipeline's own code. M7 of `poc/world` had 2.09 MB and 47 warnings.

The untrimmed build of `App` (demo 2 step 2) did not complete. Run alone,
`nice`d, under a watchdog that kills it below 4 GB of available memory
(`MemAvailable`; about 17 GB were available at the start, the other
simulation holding the rest): killed after 326 s in LLVM's code generation
for the whole image (`jl_dump_native`, lowest 2.9 GB available), and again
after 1149 s with `JULIA_IMAGE_THREADS=1` (lowest 3.8 GB). So the build
needs roughly 14 GB or more on top of what this machine has free while the
simulation runs; it is very likely what took the machine down this morning,
in parallel with the precompile and the measurements. Not retried; it needs
the machine to itself, or a larger one.

A last demo 1 run with the tolerations in place: no piracy report at all;
load 10.3 s, the step 2 calls 2.8 ms, 1.0 ms, 0.2 ms, the one-line
`@implement` 681 ms (run-to-run spread on the shared machine; the README
gives ranges).

## Verified in this session

- `Pkg.test()` of TraitWorld: 186 pass, before and after the fix.
- Every script rerun in fresh processes after the fix (logs in the session's
  scratchpad, not kept): x6 in four modes (refuse in both orders, tolerate,
  warn: as before), x7, x5, x4 storm and makie, x8 trait, demo 1 twice,
  `verify_app.jl` pipeline and main; numbers in the README.
- The trimmed binary built and ran three times; the full build killed twice
  by the guard, the machine unaffected.

## M9: design-findings §13 and the Fable review

`writeup/design-findings.md` §13 holds the PoC's table and findings. A Fable
review (fable-critic, read-only, one niced Julia process at a time) of the
code and the claims returned 18 items. Verified here before acting: the
exemption list and its effect (the reviewer's log: 49 methods with
`DEFAULT_IMPLEMENTS`, 1091 without), `recompile_time` being part of
`compile_time` (Base's `timing.jl`), the callable-type pirate missed by the
names walk.

Fixed and tested (191 tests pass, one `@test_broken`):

- the sealing scan now visits Julia 1.12's single global method table,
  `Core.methodtable` (0.03 s with Makie loaded against 2.3 s for the names
  walk, a superset of its methods, the same 49 pirates), which also finds
  call methods of callable types (`(::Base.Fix1{…})(x)`); demo load 6.1 s,
  full scans 0.02–0.81 s, x6's loads 0.01–0.17 s;
- the door walk's budget end warns at every concrete level;
- the scripts report `compile_time` with `recompile_time` as "of which";
- `repr` is no outward door; the dynamic-call comment in `doors.jl` says
  what stock Julia does not check;
- `verify_app.jl` prints the holes with a caller in the trait stack (0) and
  the declared targets not walked (5);
- `x7_trees.jl` derives each interface's list from its own tree; Tables is
  in Makie's tree, so MakieInterface tolerates it too (its own precompile
  had reported it);
- the demo's "new keyword set" now uses a type the image lacks,
  `cols = (2, 3)`: **0.9 s in the trait world (0.73 s recompiling), 46 ms in
  plain Julia** — the per-signature check's code, invalidated by Makie's
  load, recompiles. The old 0.2 ms used a type in Reports' workload.

Corrected in the README, §13 and plan §10.11–14: the implementer exemptions
and the raw count; the trimmed binary's warnings (10 are the entry's two
dynamic steps on the normal path, to registered targets; 26 skipped paths;
3 `__init__`); what "the trait part is closed" means and that declared
targets are not walked; the first-plot comparison (not comparable; a third
to a half of Makie's first-plot time is recompilation despite the workload,
cause not traced); refuse mode's order dependence; the static door check;
the standard libraries counted as Julia; sinks not implemented; X4's units.

Not fixed (listed as limits): refuse mode's order dependence (fix: read
every interface's tolerations from the manifest at TraitWorld's load);
`_manifest_closure` sealing only the package name when the active manifest
lacks it; declared targets with keywords listed at the keyword-less
signature; `_sig_alternatives`' cap at 256 Union combinations, beyond which
a Union mentioning one own type passes; warn mode reporting each definer
once; `_DOOR_FACTS` never invalidated; `_WALK[]` not thread-safe; tests for
interface tolerations read from an image, `_manifest_closure` and the
pirate-first order with a package.

For the user (design decisions):

1. **Implementers** (the review's major finding): who declares that
   StaticArrays implements StaticArraysCore? The note says only an owner
   names a delegate; `design-findings.md` §3 and TraitWorld have the
   implementer declare. 95 % of the piracy in Makie's tree hangs on this.
2. **Extension triggers** (adopted, see below): the review argues triggers confer nothing
   (CompositionsBase's InverseFunctions extension is an orphan case from
   aliasing a Base value).
3. Whether §13's findings go into the live note.

Decided after the review (the user): the live note updated to rev 1022.
Rule 5 now says "an extension owns what its parent owns; its triggers confer
nothing" (decision 2 adopted); a new Sealing bullet "Split packages are most
of a real tree's piracy (open)" explains decision 1's problem with the
numbers, and trade-off 2 points to it; trade-off 8 gains the requirement
that the runtime's entry code has no static inference edge into Base's
generic code; the closing paragraph points to `poc/interfaces/README.md`.
The local copy `writeup/traits-for-better-julia.md` was patched with the same
edits. Decision 1 (who declares implementations) stays open; TraitWorld's
`DEFAULT_IMPLEMENTS` is unchanged until it is decided.

## Design round: trait wrappers (note rev 1058)

Decided by the user, after two Fable reviews (the core-interface idea, then
the folded draft):

- A library written with traits needs no special rules; the machinery for
  split packages is for legacy code only.
- **Trait wrappers** replace interface packages for legacy code that comes
  into the trait world: one per package per environment, standing in for
  its owner (rule 5's new clause), delegating to the implementation packages
  it names among its dependencies (StaticArraysCore names StaticArrays),
  holding conformances, doors and tolerations; it retires to a re-export
  when the package adopts traits. BaseInterface became the Base wrapper.
- **Interface packages are gone as a category.** Code that stays outside is
  reached by **calls upward**, one mechanism for `Callable` arguments,
  declared calls (`@call`, any trait package may declare them) and Base's
  doors; handles come back. A shared package of Makie calls is a convention.
- **Sealing follows rule 6's views:** every package in a worker's view is
  sealed by the load that brings it there (trait packages; wrappers with
  their packages, implementations and dependencies; Julia). What lies
  behind calls upward is in no view: audited at build, never sealed.
  Rule 6's view now says "trait-world dependencies"; the dispatch check
  admits "an owner or a delegate".

Why the dependency is needed (verified): with StaticArraysCore alone an
`SVector` has no `size`, `length` throws, `a[1]` throws; a worker compiled
then would keep a stale error under the design's filter. Core-side naming
alone gives no load guarantee, since a core cannot depend on its
implementation.

The note was edited block by block (rev 1022 → 1058); the local copy follows
it. Counts corrected: ColorTypes' group is 226 (172 + 42 + 12), StatsAPI's
22; the Fable review's claim that no StatsBase method pirates Julia is wrong
(the deprecated `quantile(::AbstractArray{<:Real})` does).

Proposed by the review, not applied, for the user: rules 2–4 merged into one
boundary rule (five rules; renumbering touches ~100 references in code,
tests and docs); rule 7 as a consequence of rule 6; delete the "How common
interactions resolve" table; move earlier forms of the design from "Other
options" to design-findings; move "Generic implementations" and "Several
traits, one projection" out of "Working with existing Julia"; open-typed
arguments are described three ways (walked at the entry; "runs as ordinary
code"; "must be concretely typed"), pick one. The PoC still has
`@interface_package` and the built-in implementer list.

## Note rev 1110 and the PoC rework (the user: "Yes" to all five proposals)

The note: four rules (1 layering; 2 the boundary translates, once per bound
= old 2-4; 3 ownership = old 5; 4 what a call sees, and where its code lives
= old 6 and 7; four, not five as first said), every reference renumbered
(39 finds generated and checked against the draft), the interactions table
cut, "Generic implementations" and "Several traits, one projection" moved to
Finer points, nine earlier forms of the design moved to design-findings §14,
open-typed arguments walked at the entry everywhere (the rev 1019 decision);
a projection's share/copy declaration moved to the conformance checks.
design-findings maps the old rule numbers at its top.

The PoC: `interface.jl` became `calls.jl` (`@call`, `@handle`, declared calls
held by the ordinary module around the trait module) and `wrapper.jl`
(`@trait_wrapper Pkg Impl…`, WRAPPERS, DELEGATES, one wrapper per package);
`DEFAULT_IMPLEMENTS` and `[traitbound] implements` are gone, a delegate
counts as an owner in `owned_method` and the scan; `is_trait_world` includes
wrapped packages and their implementations; only trait packages and
wrappers seal. Packages renamed: MakieInterface -> MakiePlots (declared
calls, no seal, no tolerations), DataFramesInterface -> DataFramesWrapper
(`@trait_wrapper DataFrames`, tolerates Tables); new StaticArraysCoreWrapper
and ColorTypesWrapper. Rule numbers in TraitWorld's messages, comments and
tests renumbered. 199 tests pass, one `@test_broken`.

Measured (the whole chain rerun, niced): the audit of what is sealed is 20
methods with DataFrames wrapped and Makie called (OffsetArrays 12, StatsBase
4, Tables 4); StaticArraysCoreWrapper absorbs 511 StaticArrays methods,
ColorTypesWrapper 212; wrapping ColorTypes shows ImageCore's `showarg` at
other packages' types and PlotUtils' `convert(::Type{RGB}, ::Unsigned)`
(both tolerated, by the wrapper and by the project). Demo 1 loads in 6.0 s
without a piracy report; step 2 and 3 as before; X8 43-47 ms per type at a
load average of 4.4 (35-41 before; load or the wrapper lookup, not
separated); the trimmed binary 3.53 MB, 39 warnings, runs; `verify_main` of
App unchanged (0 holes in the trait stack).

## Time to first plot (the user: "in 100s of milliseconds?")

No, for an ad-hoc session: 21 s to the first PNG (plain Julia 27 s), 15 s of
it compiling, of which, by `scripts/x9_ttfp_blame.jl`, almost all re-infers
code invalidated by loads: `Base.thisind(::InlineString, ::Int)` from CSV's
dependency InlineStrings alone 8.4 s, SentinelArrays 3.8 s, Makie's tree
the rest; not piracy, not the trait stack, not load order. Yes, through the
application's image: `using App` 6.0-6.3 s, then read, summarize, plot and
PNG in 0.35 s with nothing recompiled (rule 4: the package that depends on
all of them holds the code). The remaining cost is the load (CairoMakie's
image about 4.2 s). For interactive sessions the design's answer is rule 4's
package extension: e.g. an extension of MakiePlots triggered by CSV whose
workload holds Makie's code compiled with InlineStrings present (not tried).

## Combination caches (`poc/interfaces/ComboCache`)

The user asked how to patch Julia to cache more aggressively with the
design's guarantees. Measured first (`x10_load_validation.jl`, instrumenting
`Base.StaticData._insert_backedges`, which 1.12 runs as Julia code in a fixed
require world): load-time validation is 1.8 s over 285 images, 0.03 s of it
the trait world's own; the 13 s of recompilation are in Makie's and CSV's
ordinary code, where the trait world's guarantees do not hold. So the lever
is rule 4, combination caches, not a Julia patch: `ComboCache` records a
session (`--trace-compile`), generates a package depending on the project
packages it loaded with the recorded compilations as workload, builds it in
the background, and loads it in later sessions. It works only when the
generated package imports its dependencies in the session's load order:
cached code's validity depends on the load order, and a build in another
order keeps Makie code valid that the session invalidates, so the replay
stores nothing for it. Order-faithful: first PNG 7.5 s (22 s without), read
to PNG 0.34 s after loading, as with App. The MakiePlots CSV extension is
removed (superseded). Not yet: automatic recording and loading (today three
explicit steps), keying caches by load order and package versions, and the
Julia patch for trait-world code (the invalidation filter, attic 0a33fef).

## The trait-world invalidation filter (patched Julia)

Ported the August idea to the current design as `jl_set_trait_world_filter`
in the attic clone's `src/gf.c` (`attic/binary/trait_world_filter_v1.patch`):
an insertion skips invalidating code of trait modules and TraitWorld when the
trigger is defined outside the trait world and Julia and owns a type or the
function of its signature (pirates invalidate). The clone needed its
standard library symlinks re-pointed after the attic move; build only `make
-C src`. A/B (`x11_filter.jl`): 92 skips; a new type's first `summarize`
54 ms instead of 227 ms (no recompiling); the first `@implement` 0.65-0.74 s
instead of 0.85-0.99 s; a new keyword type 1.0 s instead of 1.26 s, the rest
being Base/Compiler code the checks call, shared with ordinary code (needs
trait-world instances of Base code, trade-off 8's other half). 199 tests pass
on stock and on the patched build.

## Next

1. Open: refuse mode's order dependence (read every wrapper's tolerations
   from the manifest at TraitWorld's load); the remaining review items.
2. The untrimmed build of `App`, only when the machine is free.
3. Smaller: `App.pipeline` duplicates `Pipeline.pipeline` (the earlier
   in-App variant with `readdlm`), kept in App's workload; remove or label
   it. The not-fixed review items above.
