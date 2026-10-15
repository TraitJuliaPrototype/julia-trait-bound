# 2026-10-14 — Session 18: critical review of the note (rev 1019) and the PoC plan; M0 to M4 of the interfaces PoC

Intent: review `writeup/traits-for-better-julia.md` (rev 1019) and
`writeup/poc3-plan.md` for blockers, then implement as much of the plan as
possible. No blockers were found. Implemented on TraitWorld: M1 (keyword,
default and variable arguments), M2 (Callable modes), M4 (the one-line
conformance), the machinery of M3 (`@interface_package`, `@handle`, `@call`,
handles in the checks), and the environment of M0. The test suite went from
117 to 159 passes. Nothing is committed; the working tree holds everything
(see "State for the restart" at the end).

## The review

### Verdict

No blocker. The note at rev 1019 is coherent for what the PoC needs. The
plan has three design-level errors and three stock-Julia facts wrong, all
with cheap fixes that keep the demonstrations as planned. Decisions I took
are marked "decided"; they are mine, flagged for the user.

### Plan corrections

1. **DataFramesInterface's conformance violates rule 5** (plan §4, decision
   3). `@implement ColTable DataFrame …` in DataFramesInterface is the orphan
   case of trade-off 9: the interface owns neither Columns' trait nor
   DataFrames' type, and the note says an interface package "adds no
   methods and never touches rule 5". A projection is a method. The note's
   own answers are a delegate (Columns names a package extension triggered
   by DataFrames) or a newtype. Decided: Columns gains
   `ext/ColumnsDataFramesExt.jl` with the projection (the delegate route,
   which TraitWorld already checks: M6 of `poc/world`), and
   DataFramesInterface keeps what an interface package is for: wrapping
   DataFrames' tree (sealing, tolerations), the declared calls back
   (`nrow`, a constructor returning a handle) and a workload. Finding for
   the note: an interface package for a *data source* that feeds another
   package's trait cannot conform the source's type itself; "Interface
   packages" says "conformances" without saying whose.
2. **The DataFrame projection cannot be `Tables.columntable`** (plan §4,
   §7 risk 1). Its result is a `NamedTuple` whose type depends on the data
   (column names and types), so the representation would be chosen per
   value, against rule 4 ("representations must decide by their type") and
   against demo 1 step 2 ("no trait-world compilation"): a worker per
   column-type tuple compiles at the first call. Decided: the projection
   returns a `Vector{Vector{Float64}}` holding the DataFrame's own column
   vectors (elements shared, outer vector fresh), and refuses a column that
   is not a `Vector{Float64}`, naming it. Consequence: `DataFrame` conforms
   to `ColTable` (read access through Columns' precompiled workers), not to
   a mutating trait such as `ColStore`, for which the projection would have
   to be declared `copies`.
3. **Refusal at load cannot fail `using Pirate`** (plan §3.3). Verified in
   `base/loading.jl` (1.12.2, `run_package_callbacks`): Base catches every
   exception a package callback throws and logs it as
   "Error during package callback"; the load continues and `using` returns.
   The stock-Julia approximation is therefore: the callback deletes the
   untolerated pirate methods and reports a `PiracyError` through Base's
   error log. The same holds for the other order (pirate first): the
   sealing load cannot be refused either; decided: delete the pirate in
   both orders, so that "no call sees an untolerated pirate" holds, and
   report. Also verified: callbacks run per package, nested loads included,
   and `Base.toplevel_load[]` is `true` only in the callback of the
   top-level `using` (it is restored before the callback runs), so the scan
   can run once per `using`, over methods whose `primary_world` is past a
   cursor, instead of once per dependency.
4. **Enumerating methods on 1.12.2.** There is no per-module index and no
   `Core.GlobalMethods` (that is 1.13). `Base._methods_by_ftype(Tuple{Vararg{Any}}, -1, world)`
   lists every method: 24,131 in 0.42 s in a bare session, so expect 1 to 2
   s per top-level `using` with CairoMakie loaded. An Aqua-style walk over
   `names` of the top-level modules finds 16,851 in 0.13 s but misses
   submodules. Decided: the world-cursor scan with `_methods_by_ftype`,
   once per top-level load.
5. **Keywords in the entry** (plan §3.5, §7 risk 3). Generated functions
   accept keyword parameters on 1.12, but the clean path is a
   `checked_kwcall(nt, f, args...)` that forwards to `Core.kwcall`: the
   worker stays an ordinary keyword method, internal callers use keyword
   syntax, and Julia's own sorter fills the defaults inside the trait world.
   Implemented that way.
6. **Julia 1.13.** The user offered 1.13 "if that simplifies things". The one
   simplification found is item 4 (one global method table). Installing
   1.13.1 failed twice (the tarball download from julialang-s3 was reset
   through the proxy), so it is untested here. Recommendation: stay on
   1.12.2, where the Makie stack is precompiled and the measurements were
   made; revisit 1.13 if M8's `juliac` build hits trouble.

### Findings on the note (rev 1019), beyond the plan

- Rule 1 against the "may do" table row "importing and calling Base, a
  standard library or any package that an interface package admits": it is
  ambiguous whether a trait module may `using` the admitted package itself
  or only the interface. Decided for the prototype: a trait module imports
  trait modules and interface packages (whose root re-exports the trait
  half); the wrapped package itself is still a `LayeringError` to import.
- Handles cross both ways: a figure handle is returned to ordinary code and
  passed back in. "Trait objects go in, not out" and "a handle is the
  mirror image of a trait object" leave this implicit. Implemented: a
  handle is a value outside and opaque inside (`h.ref` and `typeof(h)` are
  refused in a worker; a handle passed to a declared call is unwrapped; a
  trait object passed to a declared call is refused: "trait objects never
  go up").
- A declared call's result "a trait-world value, a handle, or nothing" is
  checked at the definition as: a handle type, `Nothing`, or a deeply
  concrete type.
- The one-line form on a type that has methods for *some* operations is an
  error naming the missing ones (the note: "partial methods ... are
  errors"); a field whose type conforms only through a family at an
  abstract type (`data::AbstractVector{Vector{Float64}}`) is refused naming
  the field, as the note says; a field type that conforms to nothing gives
  "no field conforms", listing the fields.

### Facts verified on 1.12.2 for later milestones

- `Base.delete_method` exists; `Method.primary_world` exists.
- `Core.kwcall` is the keyword call; `Base.values(kws)` is the supplied
  named tuple inside `f(; kws...)`.
- `Base.package_callbacks` take a `PkgId`; exceptions are swallowed (above).

## Implemented

All in `TraitWorld/`, tests in `TraitWorld/test/runtests.jl` (testsets
"poc3 M1" to "poc3 M4"), 159 passes.

- **M1, keyword, default and variable arguments** (`trait_module.jl`
  rewritten from `_Arg` down; `entry.jl`; `checks.jl`; `concrete.jl`).
  - Positional defaults are expanded into Julia's shorter methods, each a
    trait-bounded definition with its own entry (`colmean_or(t, i = 1)`).
  - Keyword parameters: a trait bound projects at the entry (`enter_kw`,
    its own `EntryCache`, a value that conforms to nothing is a
    `TraitBoundError` at the entry); a `Callable` keyword is wrapped
    (`enter_kw_callable`); a declared type is asserted by the worker's own
    sorter, as plain Julia does; defaults are evaluated in the worker
    (`baseline::ColTable = t`, `cols = 1:ncols(t)`).
  - The entry forwards the supplied keywords as a named tuple to
    `checked_kwcall(nt, f, views...)`, which carries the per-signature flag
    and guard as `checked_call` does and calls `Core.kwcall`.
  - Varargs of trait objects: `ncols_sum(ts::ColTable...)`, projected per
    element (`enter_each`), worker compiled per tuple of representations;
    `traits_at` understands vararg signatures (`nargs == -1`).
  - Untyped fallbacks with keywords are tagged like the others, so they do
    not replace the entry; `fallback` now looks for the tagged method
    itself (a vararg entry accepts the tag too, which recursed until a
    segfault before the fix: `_has_tagged_fallback`).
  - The rule-3 check accepts the keyword sorter's own `isa`/`typeassert`
    on a `TObj` keyword (`_handle_type`); concrete mode reads the function
    off a `Core.kwcall` signature (`_worker_ftype`).
- **M2, Callable modes** (`core.jl`, `entry.jl`): `Callable{A, S, M}` with
  `CallMode`, `DynamicCall` (the default) and `CompiledCall`; the wrappers
  `compiled_call(f)`, `dynamic_call(f)` and the long form
  `Callable{A, S, M}(f)` (`CallAs`), stripped at the entry, the value's
  mode winning, a long form with another signature refused.
  `@specialize` is retired with an error naming the replacement;
  `poc/world/Stats` updated (`colsum` has `CompiledCall` in its bound).
- **M4, the one-line conformance** (`implement.jl`, `_implement_oneline`):
  `@implement ColTable T` and `@implement (ColTable, RowTable) T`. Methods
  for every operation without a default make `T` its own representation
  (the existing-methods implementation, checked); otherwise the field named
  `data`, or the one field whose type conforms, is the projection, composed
  with the field type's own projection when it has one (`Nested` holding a
  `Meas1`). Errors name the fields or the missing operations. Parametric
  families are not declared this way (an error says so).
- **M3 machinery** (`interface.jl`, new): `@interface_package Makie`
  (records the wrapped module in `INTERFACES`, reads `[traits] tolerate`
  from the package's Project.toml into `TOLERATED`, calls
  `_seal_interface!`, a no-op until M6); `@handle Figure`
  (`struct Figure <: Handle; ref::Any; end`); `@call Pkg.f(args; kws)::S`,
  which resolves `Pkg.f` in the interface package's root at expansion time
  and splices a `DeclaredCall{S}` literal into the worker: `invokelatest`
  with handles unwrapped, the result asserted or wrapped as a handle, no
  inference edge; `DECLARED` lists them per interface for `verify_main`.
  `_check_import` and `_finish_module` accept an interface package's root
  as an import. Tested with a fake outside package (`FakeOutside`,
  `FakeInterface`, `UsesPlots` in the test file).
- **M0, the environment**: `poc/interfaces/env` instantiated and
  precompiled on Julia 1.12.2 with CSV 1.1.0, CairoMakie 0.15.16,
  DataFrames 1.8.2, Makie 0.24.16, PrecompileTools 1.3.4, SnoopCompile
  3.2.9, SnoopCompileCore 3.1.3, Tables 1.14.0 (`Manifest.toml` is new).
  The path packages are added as the milestones create them. The plain-twin
  baselines and the harness ports of M0 are not done.

## Not done, in plan order

- M0: baselines (time to first result and first plot without traits,
  `using CairoMakie` invalidations), the ports of `observe.jl`, `x4_churn.jl`,
  `x8_makie_scaling.jl`.
- M3: the packages `Reports`, `DataFramesInterface`, `MakieInterface`, the
  Columns extension `ColumnsDataFramesExt` (correction 1), demo 1 steps 1
  and 2. `verify_main` does not yet know `checked_kwcall` (a keyword entry
  would show as a hole), `DeclaredCall`'s `invokelatest` (a `:latest` hole
  until M8), or `CallAs` wrappers at `enter_callable` in a closed world.
- M5 (BaseInterface: door lists, the global check, the walk into Base), M6
  (sealing: the registry, the package callback with the world cursor, the
  delete-and-report refusal, tolerations, both load orders), M7, M8, M9.
- `Callable`'s fourth parameter `K` (keywords of a function from above) is
  not implemented.

## State for the restart

- Working tree, uncommitted: modified `TraitWorld/src/{TraitWorld,checks,concrete,core,entry,implement,trait_module}.jl`,
  `TraitWorld/test/runtests.jl`, `poc/world/Stats/src/Stats.jl`,
  `poc/interfaces/env/Project.toml`; new `TraitWorld/src/interface.jl`,
  `poc/interfaces/env/Manifest.toml`, this note; `writeup/poc3-plan.md`
  gained the section "Review corrections (session 18)";
  `poc/interfaces/README.md` and `session-notes/00` updated.
- Verify: `julia +1.12.2 --startup-file=no --project=TraitWorld -e 'using Pkg; Pkg.test()'`
  (159 passes) and `julia +1.12.2 --startup-file=no --project=poc/world/env poc/world/m1run.jl`.
- A `git status` run inside the Bash sandbox lists about twenty untracked
  dotfiles in the repository root (`.bashrc`, `.gitconfig`, `.idea`,
  `.vscode`, `.claude/settings.json`, ...). They are not files: the sandbox
  masks those paths with `/dev/null` device nodes in its own view. Outside
  the sandbox the tree holds only the changes listed above.
- Next step: M3's packages, starting with `Columns/ext/ColumnsDataFramesExt.jl`
  and `Reports`, then demo 1 steps 1 and 2 in `poc/interfaces/scripts/demo_session.jl`.
