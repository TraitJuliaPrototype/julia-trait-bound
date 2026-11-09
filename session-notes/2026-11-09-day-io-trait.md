# 2026-11-09, day: `IO` as Base's trait, and finality opt-in

The chronology of the session after the handover of the morning ([`2026-11-09-handover.md`](2026-11-09-handover.md)). Every fact has its home in the record; this note links there.

## 1. Where the project stands

The user asked where the project stands; the answer followed the handover and `state.md`. `state.md` §1 named older heads than §6.1 (`unified` 23022b0ec7, TraitWorld 6b342e9); fixed in this session's commit.

## 2. The core files

The user: "Delete the core dumps". The four untracked core files (about 10.9 GB) were deleted: `core-login02-842363` (a Claude Code crash), `core-login02-864686`, `TraitWorld-unified/core-login02-3042057`, `forks-unified/DataFrames/test/core-login02-1710729` (Julia crashes on the unified build).

## 3. The compiler by facts?

The user: "Okay, what are the next steps? Compiler compiled by facts and checking if that makes it dramatically slower on plain code?"

- The traced sessions of E-326 (`experiments/unification/e326/trace-*-w326b.jl`) attribute to recompiling the compiler about 9 ms of the goal's task's 273 ms traced, 17 ms of setting D's 1,526 ms and 17 ms of TraitReport (t)'s 163 ms. E-295 brought the compiler's invalidations by upstream CSV and DataFrames to 195 instances against vanilla's 193.
- So the compiler compiled by facts could win at most 10–20 ms per session; the cost E-318 and E-325 point at is Base's code compiled plainly (the REPL's display invalidated by DataStrings' methods; validation's costly edges in plain code failing G2).
- Not run. The recommendation given: open issue 164's decision first, then Base's printing by facts as the experiment.

## 4. Open issue 164 becomes `IO` as Base's trait

The user: "What's 164 again?", then: "The real point here is that Base should support and default to Dynamic{IO} right?"

- Agreed, as 164's proposal (c) at its root. Four points it meets: traits §7.5's exception for Julia's own types (the REPL's stream is Julia's); the run-time cost of a stream compiled once; negatives at an open set (`x isa IO`, guards at `print`, `write`, `show`), which the flagged item's proposal (d), finality by ownership, would remove; `IO`'s contract.
- The user: "Yes please." to recording it as 164 (d) and to a proxy measurement.
- **E-328** (registered before the run, `experiments/unification/e328/`): the smoke run showed `IOContext{IO}` 4.4–5.1× on byte and short-string writes; a variant emulating the split first came out slower than erasure, because its fallback's untyped result made Base's `Int(unsafe_write(…))` a second dynamic call; with the declared result asserted, as compiler §7.2 has it, the split recovers most. Two variants added to the row before the full run. Outcome in the registry and evidence §2.

## 5. The decisions

The user: "Finality should be opt in. Everything else is approved."

- Recorded in the references (traits §3.4, §7.5, §9b; facts §2.2, §10; compiler §4.8, §6.3, §7.5), decisions §9 (two rows the user's, two mine), open issue 164 closed, the flagged item's proposal (d) decided opt-in, 158's second case noted, W-129 queued, PE-19 returned to the queue as W-129, the alternatives not taken in `design/alternatives.md`.
- Mine, for the user to confirm (open issues §1): opted in per trait, spelled `@closed_after_load`; the final negative as an edge on the pair's cell; `IO` closed after load; `IO`'s declared results; the candidates' order `IOBuffer`, `IOStream`, `TTY`, `PipeEndpoint`.
- Read "Everything else is approved" as the other two decisions listed for 164 (d) (step 4's exception not applied to `IO`; `IO`'s contract with `IOBuffer` among the candidates) and the recommendation (d) itself, with (a) not merged.

## 6. W-129 (a): traits closed after load, built

The user: "Start".

- `unified` bf447db25e: the set's bit `closed_after_load`; a module's `loaded` mark (Base's loader in `run_package_callbacks`; Core, Base and the system image's other modules in `Base.__init__`; a submodule through its parents; Main never); `jl_membership_final`; final cells (`isfinal`, `backedges`) opened by a membership, which invalidates their dependents after the cells' lock; `jl_call_shadows` leaves out the guard at a final pair; `isa_tfunc` and `subtype_tfunc` fold the negative and record the cells; `store_backedges` adds the CodeInstance to a final cell's backedges; a package image drops them and validation re-adds them, the system image keeps them, pruned.
- TraitWorld-unified 9a45c36: `@closed_after_load` in a trait's body.
- Deviations recorded: C-76 (the declarers' joint owners not consulted), C-77 (the fold only at `isa`, `<:` and the guard; `tmeet`, `typesubtract`, `Conditional` refinement and the lattice's meets still refuse).
- Gate `n18_closed_after_load` (in a session; package images in both load orders). Faults on the way: the folded `isa` is cached as an `InterConditional` with `thentype` `Union{}`, not `false` (the gate accepts both); a child process's `using` order.
- E-329: the battery `w329` passes (gates 54 of 54); TDE's suite passes; precompile refuses nothing. The sessions were 2–3× E-326's, first with one run and then with a warm-up and 3; the load was 26–30 of 128 against 2.5 for E-326. The unchanged early build's form (f) at the same load was slowed by the same factor (6.3–7.2 s against 2.5 s). So the 5 % criterion is not resolved; the sessions are measured again with part (b), at low load.
- Noted for part (b): the system image's membership cells are not put in the cell table at start (only package images' cells, through `fixup_objs`), so a membership would not open a guard or a final cell compiled into the system image. `IO`'s final cells in Base need that.

## 7. W-129 (b): `IO` as Base's trait, built

- E-329's sessions were measured again with a warm-up and 3 runs (`w329b`): 2–3× E-326's. The unchanged early build's form (f) at the same load (26–30 of 128) was 2.5–3× its own earlier run, so the machine, not the change. E-329 recorded as done with the 5 % criterion unresolved; committed and pushed (design d8b1251, experiments 69c5f98, `unified` bf447db25e, TraitWorld 9a45c36).
- E-330 registered before the build.
- `unified` b133374e9d, after five builds:
  - `Cint` is not defined in Core where `IO` is declared: the `ccall` takes `Int`.
  - The split's fallback was reached during Base's build (JuliaSyntax validates into `devnull`, past the candidates) before `__init__` installs the table's miss: installed at Base's build too, and first in `__init__`.
  - No module's `__init__` runs while an image is generated (`init.c`): the miss became a tag of the system image. Core's and Base's `loaded` marks are set in `sysimg.jl` and saved with the module struct.
  - Changing the tags left the compiler's image stale (make does not rebuild it on a change to `libjulia`): the images were removed by hand; the stale one segfaulted at restore.
  - `jl_declared_methods_of` scanned every method at a set; with `IO`, about a thousand of Base's. It reads the function's list now.
- Faults the new gate found:
  - `get(io, :compact, false)` at a receiver typed `IO` compiled to `return false`. All four candidates are served by Base's default at `::IO`, whose instance is compiled once, so the split's case widened to `IO` and covered every stream. Each branch is now `Compiled` for its candidate.
  - Base's `detect_ambiguities` went from 0 to 66: `write(::AbstractString, …)` against `write(::IO, …)` and the like, met at `All{AbstractString, IO}`. `isambiguous` now ignores an argument met only as an intersection (no value in the query's world, compiler §4.9), as it ignores `Union{}`. Base is back to 0.
- TraitWorld 4443d2c: its module-end hook would refuse every `struct S <: IO` without `@implement`. A set whose contract no `@trait` declared is skipped; traits §5.2 states `IO`'s exception (from §9b). The library still holds no contract for `IO` (T-106).
- Choices recorded as mine (decisions §9, open issues §1): Core and Base loaded at the end of Base's build; the system image's indices of sets; the raising defaults of `eof`, `isopen`, `close`; a split's branch `Compiled`; ambiguity reflection in the query's world.
- `unified` d554855579, found by Base's `precompile` test (the child that loads a package without LLVM): a split's table miss makes no pointer in a session without the compiler, and the fallback takes the dynamic call; the readers of a package cache's header `@specialize`d. The test still fails at `read(::GenericIOBuffer)` (438 of 457): open issue 166.

## 8. E-330: correct and far slower; two reports find the causes

The user, while E-330 ran: "When we see failures like this, also think about principled fixes or new tools that reveal common patterns". Recorded in CLAUDE.md ("A failure names a pattern").

- E-330 (load 24–37): the gate and the battery pass, but Base's `precompile`; TDE's suite passes; nothing refused at precompile. E-328's workloads on an `IOBuffer`, plain code that knows the stream: 2–24× vanilla's (the proxy said 0.85–2.2×). The sessions 3–5× E-329's: the goal's task 15.8–16.1 s against the control's 4.08–4.28 s; the forks' `show` step rose to 2.0 s.
- The erasure report (`experiments/unification/audit/erased_calls.jl`): first 99 dynamic sites, then, counting `Core.attributed_call` (the run-time site of a call that passes a `Dynamic` attribute on, which the first version skipped as a builtin), 2,018 in Base's 931 methods typed `IO`. It also lists the wrappers over a stream: `IOContext`, `EachLine`, `ReadEachIterator`, JuliaSyntax's `Lexer`.
- Cause 1, traced by hand: `print(io::IO, s::String)` compiles `write(io, s)` to `Core.attributed_call(…)::Any`, and since `print` is inlined, plain code holding an `IOBuffer` gets the dynamic call. `write(::IO, ::Char)` has one match, yet the inliner bails: the lookup's `ambig` flag is set. Since `IO` is a set, `write(filename::AbstractString, …)` meets it at `All{AbstractString, IO}`; neither is more specific there; `ml_matches` leaves the ambiguous match out but keeps the flag. The intersection stays a bare `All` even after a common member exists (checked with `S9 <: AbstractString` declared a member of `IO`), so its shape cannot tell; the world must be asked.
- Also: `write(::IO, ::UInt8)` declared `Integer` makes `n += write(io, b)` infer `Any` in `write(::IO, ::Char)`.
- Cause 2, the load report (`audit/load_invalidations.jl`): 18,781 instances invalidated at the goal's load; `length(::HasLength)` 11,994 under the pruned arm `length(::LinearAlgebra.Factorization)` (in `TermInfoRaw`'s constructor, under `load_terminfo`, `ttyhascolor`, `get(::TTY, :color, …)`), then through the split's `TTY` branch into `ioproperties(::IO)`, `IOContext(::IO)` and everything printing, the parser above it. The edge from a branch to the candidate's instance is what carries it.
- Soundness of the lookup's fix, thought through: dropping a match met only at an unmet intersection is wrong where it would prune an arm a later member reaches (`length(::Factorization)` against `length(::HasLength)`), and where it would win over the covering method. It is right where a covering match exists that it is not more specific than: a later member there is an ambiguity, the report's case. The report covers two sets only; a member's declared supertype is C-78.
- Recorded: E-330 done; E-331 registered; the flagged item in open issues §1 with five proposals ((e), Julia's own streams compiled per type, revisits the user's decision); 166 rewritten with the counts and (d), the wrappers held as `IO`; 167 (the firewall: a branch not inlined calls through a `:caller_world` pointer and holds no edge); compiler §5.4's rule and C-78; the decision row, mine.
- Built for E-331: `drop_unmet_matches` in `ml_matches`, `jl_has_unmet_argument` reading the entries at the set components; reflection asks the same; gate `n20_unmet_lookup`.

## 9. E-332 and E-333: the firewall, `Int` counts, and three failures that named patterns

- Built together: a split's branch not inlined calls its candidate's target through a `:caller_world` pointer, with no edge (E-332, open issue 167 (a)); `write(io, ::UInt8)` and `unsafe_write` declared `Int` (E-333).
- Failure 1, the system image's build: `TypeError` at the pointer target's `::Int`, from `show(::Float64)` writing to Core's `stdout`. Core's `unsafe_write` returns its count `nb::UInt`, as does `Filesystem.File`'s. The pattern: `IO`'s members join by `struct S <: IO`, before their methods exist, so traits §5.10's check of each serving method's result never runs. The tool: `experiments/unification/audit/declared_results.jl`, the declared-result report (Base 2 streams, REPL's `LimitIO` a forwarder, and a stream in CSV's tests returning `n::UInt`). Asserting `Int` would break that test stream. The fix at the rule (mine, open issue 168): a call through a trait converts a member's result to the declared result, as `f(…)::R` converts; a checked member returns `R` already. Base's two streams return `Int`.
- Failure 2, the standard libraries' precompile: `split_branch_pointer` read `Base._SplitTarget` by name and called its constructor in the compiler's world, which precedes Base's definitions (`MethodError`, world 0x2dd6). The pattern: compiler code must not look up a Base binding defined after the compiler; Base hands it over (`Compiler.SPLIT_TARGET`), and the instance is built with `Core.apply_type`. A grep of `Compiler/src` finds no other such lookup.
- Failure 3, the same stage: a generated function's generator (world 18709, `multidimensional.jl`) printed a `Symbol`, and `write(::IO, ::String)`'s pointer branch dispatched to `_SplitTarget` in that world, before its definition. The pattern: a `:caller_world` pointer's target must exist in every world a caller can run in. The target and `_to_declared` move to `base/splittarget.jl`, first in `Base.jl`; the table's miss, which had the same exposure (`jl_apply_generic` in the caller's world), runs in the latest world. Gate n19 calls through `IO` in an old world.
- Measured on 0c836f3ef6: E-328's workloads 1.0–2.6× vanilla's but `write(io, ::Char)` 4.4×, `show(::Vector)` 3.4×; the goal's task 12.2–13.9 s; the load report still 22,791 instances under split edges, `get` at `TTY` inlined after constant propagation of `:color`. Failure 4's pattern: an inlined branch brings its body's edges. 7bd8b6e512 inlines a branch only where its body is a leaf (builtins and intrinsics only), and `@specialize`s `write(io, ::Char)`: 6,687 instances invalidated, 2,110 under split edges; the goal's task 10.8–10.9 s.
- The imports stayed at 8 s. The compile trace: TraitWorld's `_image_methods_hook` and `_strict_at_load!` and Base's `_atexit` recompiled at each package's load (about 2.3 s). The invalidation log: their chains, 35–42 deep, start at instances compiled for `All{AbstractString, IO}` (`print(::IO, ::All{…})`, `iterate(::All{…}, ::Integer)`). A new tool, `audit/unmet_instances.jl`: 58 such instances in the system image. Open issue 169.
- The user: "Do we know why turning IO into a trait caused such a massive regression yet?" Answered: per call, two causes found and mostly fixed; the load, invalidation through shared instances, partly fixed; what stays unexplained named.
- The user: "Send out a Fable agent to think about a principled fix to this. Maybe an equation for the output type?" Its plan, `writeup/plans/2026-11-09-compiled-once-equations.md`: inference already uses only the contract, and the fan-in's edges are the optimizer's; so equations (first order, already supported) type the results but remove no edge. Proposals: the firewall as a rule of §7.2 (dispatch edge, declared result, code edge to a leaf only), wrappers holding the stream as `IO`, `IO`'s contract completed (`read(io, ::Type{T})::T`, `position`, `displaysize`), an unmet intersection folded behind a guard. Its proposal 4 matched the chains traced the same hour.

- The battery `w332` on 7bd8b6e512: gate n8 and TraitWorld's `Callable` test failed. A `Callable`'s call whose arguments are proved in `A` carries a `DeclaredResultInfo`, the info E-333's conversion reads, so its result converted (`MethodError`) where traits §9 asserts it (`TypeError`). The pattern: one info shared by two rules. `DeclaredResultInfo` now says which (`convert`). Base's `precompile`: one more failure in the child without the compiler (166).
- Found while the battery ran: E-331 keeps a match at an unmet intersection where it would win (§5.2 ranks the closed `AbstractString` above the open `IO`), so `show(::IO, ::Char)`'s `write(io, b1, b2, b3, b4)` split compiled an instance at `All{AbstractString, IO}`. E-334 registered and built: such a match dropped, and `isa` folded, as a final negative with a cell on (`AbstractString`, `IO`), opened by a membership that meets the intersection (open issue 169 (a)).

## 10. E-334 done; E-335: the typemap's root list

- E-334's first build left 28 of the 58 unmet instances: compiled while Base was built, before Core and Base counted as loaded, so the final negative did not apply to them. The end of Base's build (`base/sysimg.jl`) now invalidates them with their callers, in a new world (`jl_invalidate_code_instances_new_world`). Two at `All{AbstractDict{K, V}, IO} where {K, V}` stayed: a component with free variables is now asked at its type name.
- Failure, and its pattern: a runtime change (`src/datatype.c`) relinked `libjulia-internal` but did not rebuild the system image, so one run measured the old image. Julia's make rebuilds the image only when `base/` changes, yet the runtime's rules shape what Base's build compiles. The tool: `tools-local/build.sh` touches `base/sysimg.jl` where a runtime source is newer than `sys.so` (`KEEP_IMAGE=1` keeps it).
- The unmet-instance report counted objects, not code: an invalidated instance keeps its old code. It now counts code valid in the latest world, as gate n20 (4) does.
- Results on `unified` 1906196731: unmet instances with valid code 58 → 0; the load report 6,687 → 4,271 invalidated, 191 under a split's branch; the goal's task 8.71–8.78 s against 10.8–10.9 s (imports 6.4 s against 8.0 s, the read 1.6 s against 2.0 s); the battery's gates 56 of 56.
- The compile trace of the imports: 0.6 s of compiling left. `_image_methods_hook` no longer recompiles. `_strict_at_load!` recompiles through plain invalidations at `AbstractString` under `showerror` (`convert(String, ::AbstractString)`, `thisind`), `_atexit` through TraitWorld's `length(::HasLength)` at `LinearAlgebra.Factorization` (open issue 167's pruned arm, via `TermInfoRaw`'s `convert(BitVector, …)`), `temp_cleanup_atexit` through `close(::IO)`.
- The profile of the load: of 5.0 s, image validation (`insert_backedges`, `verify_call`, `ml_matches`) 2.8 s, nearly all in the typemap visitor's linear list, with self time in `obviously_disjoint`'s first tests. The pattern, named with a new tool, the typemap report (`audit/typemap_linear.jl`): a method whose signature mentions an open set is filed in the linear list of the level it reaches first, and the global table's first level is the function's type. So all 1,199 of Base's methods with `IO` in their signature sit in one list at the root, which every lookup of every function walks. With few sets this cost nothing; with `IO` a set it is most of validation, and every dispatch miss pays it too.
- The principled fix at that rule (E-335, registered before the run): a method is listed unindexed at a level only where the type at that level's position mentions a set; at the other positions it is indexed as any other. `show(io::IO, x)` is filed under `typeof(show)`, then listed one level down with the other 238 `show` methods. If the per-function lists still cost, the next step is a bucket per set at the set's position, indexed one level down.

## 11. E-335 done; the read; E-336

- E-335 on `unified` 45fa624462: the root's list is gone (Base's linear lists 2,258 → 1,663); the load's main thread 5.0 → 2.4 s, validation 2.78 → 0.70 s; the goal's task 4.44–4.51 s (imports 2.2–2.3 s, at E-329's level), the read 1.5 s against E-329's 0.06 s.
- The read compiles nothing by inference. Its profile: 1.4 s in LLVM, machine code for code the load invalidated and revalidation made valid again (`show_unquoted(::IO, ::Expr, …)`, 577 ms, reached through an `@assert` message's `string(::Expr)` in CSV's code). Its system-image CodeInstance ends at world 39658, during the load.
- The chain: TranscodingStreams' `seekstart(::TranscodingStream)` replaces the instance `seekstart(::IO)`, whose callers include plain code that knows its stream (`isvalid_file_crc(::IOStream)`, `_join_preserve_annotations`). A new tool, the set-root report (`audit/set_roots.jl`): 1,659 of 4,194 instances invalidated at insertions sit under a root at `IO`.
- The pattern and its rule: a method typed `io::IO` is compiled once, so every caller reaches the instance at `IO`; the forward edge keeps the call's signature, the backedge drops it (`ForwardToBackedgeIterator`), and a method inserted later invalidates every caller of the instance. Vanilla Julia has the same imprecision for `@nospecialize` methods. The fix at the rule (E-336, registered): such a backedge keeps the call's signature as `(svec(sig), caller)`, and insertion asks whether the new method replaces the old one over the part of that signature it meets.
- Also found: two of the roots are operations (`close`, `get(io, key, default)`); their defaults' instances are reached by plain code at a type with no method of its own (`close_stdio(::IOServer)`, `show_typealias(::IOBuffer, …)`), the same pattern. `setproperty!(::IO, …)` is invalidated by TraitWorld's method for `Core.Dynamic` (`Dynamic{IO}` is an `IO`), `get(::IO, …)` by BaseTraits' method at `Keyed` (met at `IOContext`).

## 12. E-336, and the Fable plan on alternatives

- E-336's first build failed its gate (n21): a caller at `IOBuffer` was still invalidated. Its edge was the one-CodeInstance form: the attribute's rewriting of a match (`attributed_match`) replaces its `spec_types` with the instance's, so `_add_edges_impl` saw them equal. The test is now whether the instance is no wider than the call's signature.
- The second build: the read 1.5 → 0.31 s, but the imports 2.2 → 3.5–4.0 s. The load profile: `store_backedges` 0.9 s. Its duplicate check walks the iterator again for each backedge (quadratic), and each step built a marker for every call-signature edge; before, those backedges were `nothing`. Fixed: the backedges collected once, compared by identity; the `svec` made at the `ccall`.
- The third build: the goal's task 3.46–3.63 s; the early build's form (f), run just after at the same load as the control Fable asked for: 2.49–2.56 s. Set roots 1,659 → 950.
- The user: "Ask Fable if another approach to IO rather than turning it into a trait would be more sensible/principled." The plan (`writeup/plans/2026-11-09-io-alternatives.md`) recommends (B): `IO` stays Julia's closed abstract type with its contract declared, `IOContext{IO}` the eraser, erasure the author's choice; it finds 164's case unmeasured since E-330 and facts §13.1 contradicted. Listed in open issues §1 for the user; the user asked the same question again and was pointed to the answer.

## 13. Option B: `IO`'s contract on the closed type

- The user: "Go with the Fable plans recommendations". Recorded in one commit (design 87a254e): traits §3.4 (a closed abstract type may declare a contract), §9b rewritten (the eraser `IOContext{IO}`, erasing the author's choice), compiler §7.1, §7.2, §7.5 and the examples that used `IO` as a set (now `ColTable`, a `@nospecialize` `k`), C-80 (the build still holds `IO` as a set), C-81 (a package's candidates for its closed type not kept in its image); the decision row; the `IO`-as-a-set rows moved to the superseded section; alternatives.md's entry with E-330 to E-336's costs; open issues 164 re-closed, 166 and 168 reworded, §1's flagged item and the "whether `IO` should be a set" entry removed; E-337 registered.
- The user, mid-turn: "Send another agent out to document the porting lessons from this." A Fable agent wrote `writeup/reviews/2026-11-09-io-porting-lessons.md` (fourteen lessons) and the guide's 0.4, 0.6, A10, A11 (design f0c306c). One claim corrected before the commit: `IOContext{IO}(ctx)` unwraps an `IOContext` (the inner constructor does), it does not wrap it whole. Its proposals for CLAUDE.md are left for the user.
- The code (E-337): the contract written on the `TypeName`'s contract slot as the operations' methods (`jl_declare_contract(T, ops)`), since a `TypeName` has no free bit and the slot is serialized with it; inference reads it (`jl_contract_operations`) where it reads a set's declared methods; the four checks admit a type with a contract; `boot.jl` no longer opens `IO`; `iotrait.jl` declares the contract and the candidates, without `Dynamic{IO}` and the raising defaults; the ten `@specialize` additions and the `Int` counts of Core's streams and `Filesystem.File` reverted; `IOContext{IO}(io, kv…)`. Gates n19 rewritten, n20 and n21 (1) on test sets. The forks' DataFrames erases at its two display entries, as `e323` did, with `IOContext{IO}(io)`.
- Two gate checks were wrong, not the build: `w1` in n20 folds to a constant (now told apart by its result type), and `@nospecialize` at a closed type lets a caller that knows the stream infer the entry at it (n19 now calls the entry dynamically, as the REPL does).
- E-337 (`unified` b05ae361e0, forks a8fe1b5, load 6–8): the goal's task 1.76–1.80 s against the early build's 2.46–2.57 s; the forks' `show` step 0.081–0.110 s against 0.204–0.217 s; E-328's raw workloads vanilla's; the battery `w337` passes, Base's `precompile` 457 of 457. The trace: 53.5 ms of the `show` step in the split's targets at the REPL's streams (open issue 170, recommendation C-39's ahead-of-time targets).

## 14. The B-display arm (E-338)

- The user asked whether everything is slow unless rewritten under B. Answer: no; plain code is vanilla's, the rewrite buys only the first display's compile at a stream no image saw (164's case).
- The user: "Measure the B-display arm". On branch `b-display` (`unified` 562b08ddb6), REPL's `show_limited` passes `IOContext{IO}`. Arms: (0) DataFrames as before E-337, 0.159–0.198 s; (w) DataFrames' code unchanged, one workload line at `IOContext{IO}(IOBuffer())`, 0.087 s in each run; (e) E-337's entries, 0.065–0.115 s; control 0.205–0.211 s. Output equal. REPL's suite fails one completion test, as vanilla does on this machine.
- The build restored to `unified` b05ae361e0 afterwards; the arm's branches pushed (`julia-unified` and `forks-unified` `b-display`). Adoption is in open issues §1 for the user.

## 15. Two Fable reviews; the documentation review's findings

- The user asked for the state and the next work. Found on the way: the goal's task on b05ae361e0 is 1.76–1.80 s (E-337) against E-326's 1.62–1.63 s and the gate of 1.65 s; the imports grew from 1.02 to 1.17–1.20 s. Not yet explained; the bisection waits.
- The user: "Please send out a Fable review to look at all the performance work done today, and assess and review it. Then send a second Fable agent out to look at the state of the documentation, especially whether the reference is consistent and reflected in the other documents." Both started in the background (the exception to the rule against subagents: the user's request).
- The documentation review (`writeup/reviews/2026-11-09-documentation-consistency.md`): 18 findings. What was done with each:
  - H1 (`design.md` on `IO`), H2 (`facts.md`'s strict mode Planned), H3 (`facts.md`'s split Planned, the result asserted not converted): fixed.
  - H4 (the conversion changes plain code's result at a value typed `IO`): checked in the main session, and worse than the review said: the result depends on inference (`Vector{IO}` gives `Int64`, `Vector{Any}` `UInt64`, `--compile=min` `UInt64`). Stated in facts §2.1, §13.1, §14, traits §3.4, §9b, `design.md` §4 as Open; open issue 171 with proposals; open issues §1 for the user. The probe: `experiments/unification/audit/probe_result_by_inference.jl`.
  - M1 (heads copied into the references): the copies replaced by links to `state.md` §6.1. M2 (bare W-items as statuses): the five lines, and the README's convention. M4 (160): traits §7.6, compiler §6.9 and P-23 mark it Open. M5: `lowering.md`'s anchor; the other citations link into the attic and resolve there; the closed items' numbering noted at their heading; the checker adopted with a link rule (`experiments/docs-checks/`). M6: the glossary's contract of a closed type, candidates, eraser.
  - M3 (W-129's commits not folded) and L4 (comments naming C-18): W-129's last step, recorded in its row and in julia-changes §7.1's rule.
  - L1 (Draft): Adopted, and the README's "Proposed" replaced by the "mine" convention; L2, L3, L5, L6, L7, L8: fixed.

## 16. The work queue's clean-up

- The user: "What open work remains right now in the Todo?", then "Do a clean up pass." About 25 rows of the earlier build (julia-1.13 with TraitWorld `main`) still read queued or in progress, and the queue's plan was the order of 2026-10-29.
- Each row checked against the current references and code (TraitWorld `unified` has no second spelling and none of the earlier library's tools; C-9, F-13, T-79 are the earlier references' rows):
  - done: W-9, W-14, W-22, W-27 (traits in the type system: the unified build), W-29 (as `All{X, Y}`), W-67, W-77, W-83, W-85, W-86 (the receiver at any position, traits §4.1), W-106;
  - merged: W-7 into W-121, W-124, W-126; W-11 into W-22 and PE-5; W-35 into W-104; W-66 and W-74 (3) into W-120; W-82 and the rest of W-88 into the unified build's stages;
  - moved: W-57 to PE-29 (Base is plain in the product setting), W-73 to PE-9, W-75 to PE-30 (strict mode's load, not measured on the unified build);
  - dropped: W-68, W-72, the rest of W-80, T-79;
  - restated: W-17, calls through a trait against plain calls on the unified build.
- The plan rewritten as the current order; the order of 2026-10-29 moved to `record/design-history.md` with its text. traits §4.1's "asserted" made "converted and asserted" (missed by the documentation review's H3).
- Open now: W-104, W-121, W-124 to W-129, W-17, W-119; waiting: W-19, W-110, W-120, W-127.

## 17. The performance review's findings

- The review (`writeup/reviews/2026-11-09-performance-day.md`, Fable): 3 high, 6 medium, 2 low. Checked in the main session: H2's probe reproduced on the head (`f(MyS(), 1)` raises `MethodError`, `g(MyS())` compiled at `Callable` returns `:callable`); M2's `write` step read in the logs (0.505 s on the head, 0.121–0.157 s in every `b-display` arm).
- What was done with each:
  - H1 (the goal's task misses its gate on the head, +0.15 s in the imports against E-326): `state.md` lines 3, 13, the §5 table and bullet; evidence §3; E-337's row; W-125's status and the queue's plan. The cause (M1) not yet profiled: next, `audit/profile_load.jl` on the head.
  - H2 (dispatch's drop of an unmet match unsound at `Callable`, unguarded at open sets): compiler §5.4 rewritten (the match stays at an open set; `Callable` read by its methods), C-82, open issue 172 (keep, or a guarded drop), the decision row replaced (the old one superseded), alternatives, julia-changes row 74, open issues §1; the probe adopted (`experiments/unification/audit/probe_unmet_callable.jl`). Not built yet: W-129's left list.
  - H3 (rows committed with their outcome; logs naming the previous commit): the registry's conventions (commit the row before the run; a session's baseline; a criterion crossed by its margin ends the line of work; a census before a Base-wide change), notes on E-334 to E-336; `e289/run.sh` prints the binary's own commit.
  - M2 (B-display's `write` step): E-338's row, evidence, open issues §1's item, PE-25, W-126.
  - M3: the conventions above. M4: open issue 173 (extension memberships late at a set closed after load); E-327 on the head before 167's rule, E-334's walk skipped, in W-129's left list. M5: two flagged items in open issues §1 (the attribute at the method's declared type; the firewall's pointer). M6: E-338's row notes its reasoning. L1: open issue 171. L2: E-337's (t) without Python, at stage 1's edge, in its row.
