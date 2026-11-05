# Critical review: "Building the unified design into Julia from the upstream base" (2026-10-29)

**Reviewed:** `writeup/explorations/unified-build-from-vanilla-julia.md` at design-repository commit 4721a03. Upstream Julia read at `45b6d15e34` (v1.13.2, the patched branch's base) with `git -C julia-1.13 show`; the patched build `julia-1.13/julia` (1.13.2) ran two short scripts (`experiments/tools/jl --name critic-unified`, under a minute each; not kept, since they decide nothing the record needs). Not under review: option (e) itself ([compiler §7.1](../reference/compiler.md#71-memberships-and-dispatch), open issue 136, the decision log §5 of 2026-10-29).

**Method.** I read the exploration in full; facts.md in full; compiler §1–§5, §7; traits §3.4–§3.7, §5, §6, §7.1–§7.3, §9, §10, §13, §14 and the deviations it names; lowering's deviations L-1 to L-50 where cited; experiments §12 (E-252 to E-259) and the outcome lines of the other experiments the document cites; the earlier exploration's §5.5, §13.4, §14.4, §15; the store note §3.4; the precedents note. In upstream I checked every function the document names, at the cited line, and read the mechanism it attributes to it: `jl_compilation_sig`, `jl_isa_compileable_sig`, `cache_method`, `jl_normalize_to_compilable_sig`, `jl_method_table_insert`/`jl_method_table_activate`, `invalidate_code_instance`, `_invalidate_backedges`, `jl_promote_ci_to_current`, `ml_matches` and its visitor, `jl_typemap_*` (insertion, exact lookup, by-type lookup, intersection visitor), `subtype` and the other supertype walks of `subtype.c`, `jl_isa`, `type_morespecific_`, `isa_tfunc`/`subtype_tfunc`/`typeassert_tfunc`, `get_compileable_sig`, `abstract_call_gf_by_type` (`concrete_only`, `infer_compilation_signature`), `abstract_call_method` (`nospecializeinfer`), `finish!`, `store_backedges`, `compute_edges!`, `verify_method_graph`/`verify_method`, `emit_invoke`, `emit_call_specfun_other`, `gen_invoke_wrapper`, `jl_analyze_workqueue`, `new_opaque_closure`, `jl_update_all_fptrs`, `jl_update_all_gvars`, `write_gvars`, `jl_emit_native_impl`. Where I say *verified* I read the code or ran it; where I say *reasoning* I did not.

**Line citations.** Every line number the document cites is right at `45b6d15e34`, with one exception: `get_compileable_sig` is `Compiler/src/utilities.jl:159`, not `abstractinterpretation.jl:159` (an `end`). Two attributions are imprecise (L1).

**Counts.** High 4, Medium 11, Low 10.

**The short verdict.** The frame (five features as five extensions of mechanisms upstream has) is right and the inventory of places is unusually good. Three load-bearing claims do not hold as written: result edges that revalidate (D3) are unsound against Julia's direct-call binding; the over-approximating `typeintersect` is the wrong layer for "never fold a negative" and breaks invariants `ml_matches` and the inliner rely on; and the negative-fold exclusion must be structural, not "the right-hand side's name is open". The stage plan has one soundness gap (S1 alone) and omits the method table's typename index, without which S2 cannot find a method at a set. The rest is sound in direction and under-costed in places (the dynamic adapter, per-member inference, the store's second code generation).

---

## Verdicts on D1–D9

| Decision | Verdict | Why (findings) |
|---|---|---|
| **D1** stage order S0, S1, S3, S2, S4, S5 | **Change.** Split S0: the policy and the record yes; result-edge revalidation out (H1). S1 is not sound alone for dispatch (H4): either memberships invalidate in S1 as a method insertion does (a stopgap S2 removes), or S1 refuses Julia methods at open sets outside the library's generated ones. S3 before S2 is reasonable, but S3's "one MethodInstance per key" needs the inference-side rule (M4), and the typemap work (M1) is a prerequisite of S2 that no stage names. | H1, H4, M1, M4 |
| **D2** the key's shape: projection, or offsets in the key | **Projection for static callers; undecided for the dynamic path.** One CodeInstance has one boxed entry point; a member-agnostic adapter must read offsets at run time, or there is one adapter per member (M5). Decide after S3's prototype measures the boxed path against E-256's 80–96 ns. | M5 |
| **D3** the policy per method, with result edges that revalidate, in place of a second owner | **Reject as stated; adopt the half that holds.** The policy as a method property and the dependency record: yes. Result edges that revalidate: no, until calls through such an edge go through an indirection that re-resolves per MethodInstance (H1), and only for calls that were *called*, not inlined, constant-propagated or evaluated (M7). Until then the second owner stays the product setting's design. | H1, M7, M8 |
| **D4** memberships advance the world counter, with `min_world` | **Accept,** with two additions: a positive fold bounds the CodeInstance's `min_world` by the entry's (M6); each world bump costs every C-3 site one miss (L5). | M6, L5 |
| **D5** the cost at a bounded method's definition on an open set, accepted | **Accept in principle; the cost is overstated under the document's own C7 placement.** With C7 in `jl_type_morespecific` (M2), the insertion walk skips every chain-matched specialization and reaches only `f(::Any)`'s and the "no method" facts. Count W-S2a under both rules. | M2 |
| **D6** the store: machine code in shards by origin set, relinked by identity, per-environment first, `Main` excluded | **Accept the direction; correct two claims.** The JIT's object code cannot be written out; shards are re-emitted from inferred code at exit, a second code generation per instance in the producing session (M8). `clone_idxs` is multiversioning, not cross-image linking; cross-image calls already go through per-CodeInstance slots, so the "direct call" worry across shards is moot and the lookup-by-identity design fits the existing slot mechanism (M8). The admissibility predicate is right, and depends on H1's resolution for result edges. | M8, H1 |
| **D7** `Callable`'s `Dynamic` form on `OpaqueClosure` | **Defer; not convinced.** An opaque closure fixes `R` at creation, has one `source` method and a direct `specptr` call path in codegen; a world-following form over an arbitrary function re-creates the thunk the document means to remove (M9). Keep `:caller_world` unless a measurement says otherwise. | M9 |
| **D8** Base's sets closed, Core's kinds never members, as bootstrap bits | **Accept,** plus: the open-set test in inference is structural (H3), and `jl_isa`'s type-value branch returns 0 before any membership is consulted, so `Type{S}` memberships (open issue 91) need it changed (L10). | H3, L10 |
| **D9** a declared result type recorded on `Method` | **Accept as a general change.** The body's assertion stays the semantic source; the field is a bound inference may read. It changes `Core.Method`'s layout (serialization, Revise, Cthulhu read it). | L9 |

---

## High

### H1. Result edges that revalidate (D3) are unsound against Julia's call binding: a kept caller would keep calling the invalidated callee's machine code

**Location.** §0, §3.8 ("Result edges revalidate instead of invalidating"), §8.2, D3.

**What the document says.** A caller holding only a result edge to a replaced CodeInstance is marked with the revalidation sentinel; when next needed, `verify_method_graph` compares the edge against the callee's new instance and, if the result is equal, restores the caller's world range. "HotSpot and rustc do the same."

**What holds (verified).**
- Codegen binds a static call to the callee's *code*, not to its MethodInstance. `emit_invoke` (`src/codegen.cpp:5481`–`5553`): when the callee CodeInstance already has code, `jl_read_codeinst_invoke` gives its `fptr` and the call is emitted to `jl_ExecutionEngine->getFunctionAtAddress(fptr, …)`, a symbol for that address; otherwise the callee goes into `ctx.call_targets[codeinst]` and `jl_analyze_workqueue` (`src/jitlayers.cpp:371`–`400`) resolves the prototype to the callee's compiled function by name, or to a `jl_invoke` stub for that CodeInstance. Run: `f(x) = g(x) * 2` with `@noinline g` compiles to `call i64 @j_g_167(...)`; after `g` is redefined, `f`'s old CodeInstance has `max_world = 39487`, as upstream's transitive walk intends.
- So a caller C with a result edge to callee K, kept after K is invalidated because a fact *inside K* broke, still jumps to K's native code. K's code calls the old target of the changed method. C computes the old result in the new world: G1 ("the same world") fails, for plain code and facts code alike.
- The comparison the document proposes cannot see this: K′ (the recompiled callee) has the same `rettype`, `exctype`, effects and constant; the difference is in K's code, which C's code reaches by address.
- `verify_method` (`Compiler/src/reinfer.jl:162` onward) validates a CodeInstance edge by *identity*: it converts the edge to its MethodInstance for the dispatch check (`verify_call` at the callee's `specTypes`) and then recurses into the callee CodeInstance, taking its own world range (`if max_valid2 ≠ WORLD_AGE_REVALIDATION_SENTINEL` return its range). An invalidated K gives C `maxworld ≤ K.max_world`. "Reusing `verify_method_graph`" is a new edge kind with a new validation path, not a reuse.
- A sentinel-marked CodeInstance has `max_world = 1`, so `jl_method_compiled_callptr` and `jl_rettype_inferred` never return it; "when it is next needed" needs a hook in those lookups.
- The precedents are misread. HotSpot's nmethod dependencies *deoptimize* dependent compiled methods when a callee changes; it does not keep them. rustc's red-green is at the query level, and its object code refers to callees by symbol, re-linked on every build; the precedents note ([incremental-precedents-research](../record/incremental-precedents-research-2026-10-27.md) §2) describes early cutoff on query results, not on linked machine code.

**What would make it sound (reasoning).** A result edge is sound only if the call site re-resolves the callee at run time: a slot per (MethodInstance, ABI) holding the current valid code pointer, written when a new CodeInstance for that MethodInstance is compiled and when one is invalidated. Upstream has the shape already, per CodeInstance and never updated: package-image calls to another image's code load the pointer from a `p<name>` global (`emit_call_specfun_other`, `src/codegen.cpp:5355`–`5365`; filled by `jl_update_all_gvars`, `src/staticdata.c:2345`). Making that slot per MethodInstance and world-checked is the design to propose; its cost is one load per call (the per-call-site cache's order, C-3's fix pays the same). Without it, D3 keeps the second owner.

**Recommendation.** Keep from D3: the policy per method; the dependency record with result edges *as data* (so that W-S0a can measure how many callers would survive). Drop: revalidation in place of invalidation, until the slot exists. Rewrite §3.8's "What this does to the second cache owner" as conditional on the slot. Correct the precedents sentence.

### H2. "Over-approximating `typeintersect`" is the wrong layer for "never fold a negative": it breaks invariants `ml_matches` and the inliner rely on

**Location.** §2.3, §2.2 (last paragraph), S1's riskiest assumption; inherited from the earlier exploration's §13.4 item 3.

**What the document says.** `jl_type_intersection(S, X)` returns `S` for an open `X` that `S` is not a known member of, never `Union{}`; `jl_has_empty_intersection` says "not empty" for the same pair; Julia's docstring allows it.

**What holds (verified).**
- The method table's visitor assumes `ti ⊆ sig`. `jl_typemap_intersection_node_visitor` (`src/typemap.c`) computes `ti = jl_type_intersection_env_s(query, sig)` and passes it to `ml_matches_visitor`, which makes the match with `spec_types = ti`. For a dispatch tuple it already guards against a conservative intersection with `!(A <: B)` ("issue #30394"): the concrete case is pruned. For an *abstract* query `Tuple{typeof(f), AbstractFoo}` from plain inference, the bounded method `f(::X)` yields a partial match with `spec_types = AbstractFoo`, which is not a subtype of the method's signature.
- The inliner's union split tests `isa(x, case.sig)` where `case.sig` is `match.spec_types` (`Compiler/src/ssair/inlining.jl:1443`, `:538`). With `spec_types = AbstractFoo`, every `AbstractFoo` value would take the branch into the bounded method's code, members or not. Wrong dispatch, not a performance loss.
- `specialize_method(match)` creates a MethodInstance of the bounded method at `AbstractFoo`, a non-member type; inference of the body there is meaningless.
- `jl_isa` for a type value (`src/subtype.c:2513`–`2560`) and `jl_type_intersection`'s own datatype case (`:4292`–`:4300`) assume disjoint typenames mean an empty set, and the type cache relies on exact answers (`has_concrete_supertype`, `maybe_subtype_of_cache`; the document lists these as a risk). `obviously_disjoint` (`:560`–`:570`) is a third chain walk the rule would have to patch.

**Why it matters.** The decision (e) says "a negative membership is never folded, in inference or in dispatch." It does not say that the runtime's intersection must lie. The two can be separated:
- `jl_subtype` consults memberships (monotone, world-stamped): the runtime's truth in the current world.
- `jl_type_intersection` stays exact in the current world: `Union{}` for a non-member. `ml_matches` then prunes bounded methods at non-members, as it prunes everything else.
- A predicate `jl_could_join(S, X)` (`S` not a final non-member of `X`, with the structural walk of H3) is what *inference's lattice* and *dispatch's forward-looking questions* use: `isa_tfunc`, `subtype_tfunc`, `tmeet` and `typeassert_tfunc`, `Conditional` refinement; the shadow query of §3.3; and the insertion walk of §2.3 (where `jl_type_intersection2(type, mi->specTypes)` is empty, the walk also asks `could_join`).
- Partial matches of a bounded method at an abstract query should have `spec_types = X` (the erased key), so that the inliner's `isa(x, X)` is the membership test and the instance inferred is the `Dynamic` one. That is also the right answer for the abstract-query case the document never states (plain code calling `f(x::AbstractFoo)` where `f` has a bounded method).

**Recommendation.** Replace §2.3's first paragraph by the three-layer rule above. Add "abstract queries" as a subsection: what `ml_matches` returns for a bounded method at an abstract signature, and what inference does with it. Put `obviously_disjoint`, `jl_isa`'s type-value branch and `jl_type_intersection`'s datatype case on S1's list.

### H3. The negative-fold exclusion must be structural; "the right-hand side's name is open" misses sets inside tuples and unions

**Location.** §2.2 ("Inference"), §2.3.

**What holds (verified).** `isa_tfunc` (`Compiler/src/tfuncs.jl:877`) returns `Const(false)` when `isdispatchelem(v)`, before any intersection test. `isdispatchelem(Tuple{Int})` and `isdispatchelem(Type{Int})` are `true` (run). So:
- `isa(t, Tuple{X})` with `t::Tuple{S}` folds to `false` today and would stay folded under the document's rule, since `Tuple{X}`'s name is `Tuple`, not open. After `S ∈ X`, `Tuple{S} <: Tuple{X}` is true (covariant). Compiled code keeps the stale `false`: G1 in plain code, with no edge to invalidate it.
- `Vector{Union{S, X}} <: Vector{X}` flips from false to true at the membership (the invariant parameters become equal as sets). `subtype_tfunc` with `isexact_a` folds `Const(false)`.
- `typeassert_tfunc`'s `tmeet(S, X)` gives `Union{}` today: code after `x::X` on an `x::S` is inferred unreachable and removed. After the membership the assertion passes at run time, but the compiled code has no code after it.
- U7's counter classified both sides structurally (`_u7_kind` with an `intuple` argument, `experiments/w83/u7/u7count.jl`), so E-255's numbers may already cover nested sets; the document's rule does not.

**Recommendation.** A predicate `has_open_set(t)`, walking parameters and unions (cached as a bit on the type object, as `has_concrete_subtype` is), replaces "t's name is open" everywhere §2.2 names a `Const(false)` path, and in `tmeet`, `typesubtract` and the `hasintersect` sites U7 instrumented (63 in the Compiler). Say it in S1's "what" and test it: `isa(::Tuple{S}, Tuple{X})` and `x::X` on an `S`, compiled before the membership, answered after it, in the new and the old world.

### H4. S1 alone is not sound for dispatch: once `S <: X` is true in the type system, Julia dispatches to any method at an open set, and neither memberships nor guards protect compiled callers until S2

**Location.** §6 S1 ("useful and testable alone"), §3.2, §3.3.

**What holds (reasoning from verified mechanisms).** After S1, `jl_subtype(S, X)` is true for a member. A plain Julia method `g(::X)` (anyone can write one; S1 does not forbid it) is then applicable at `(S,)` by Julia's own `ml_matches`. Three things go stale at the membership, and S1 as written touches none of them:
- the leaf cache and typemap cache entries at `(S,)` selecting `g(::Any)` (the §3.2 walk is listed under S2);
- compiled static calls `g(s::S)` folded to `g(::Any)` with a backedge on `g(::Any)`'s instance: a membership inserts no method, so nothing lowers their `max_world`; the guard that would cover them is S2's;
- "no method" facts (`mt->backedges`) at `(S,)`.
The document's S1 test checks `isa` and `<:` after a late `@implement`; it does not call a method at a set.

**Recommendation.** Make S1 sound in one of two ways, and say which: (a) `jl_declare_membership` runs the insertion walk of `jl_method_table_activate` for every method at `X` or a superset of `X`, as if `Tuple{F, …, S, …}` had been inserted (a stopgap S2 replaces by guards; it also gives a measurement, the count of invalidations a membership causes today, which E-252 estimated with a plain method); or (b) S1 refuses a method whose signature names an open set unless the method is the library's generated worker, reached only through an entry that decides dispatch itself. Option (a) is less code and measurable; option (b) keeps "memberships invalidate nothing" literally true one stage earlier. Either way the §3.2 cache walk moves into S1.

---

## Medium

### M1. The method table's typename index does not see memberships: no stage names `typemap.c`, and S2 cannot find a method at a set without it

**Location.** §3.1, §3.3 ("the typemap's per-typename split finds that in one step"), S2's "Where".

**What holds (verified).** `jl_typemap_level_insert_` (`src/typemap.c:1400`–`1470`) indexes an entry whose argument type has a typename, abstract types included, under `name1[typename]`. Every lookup walks the *query* type's supertype chain and probes `name1` by each supertype's name: `jl_typemap_assoc_by_type` (`:1048`–`1056`), `jl_typemap_level_assoc_exact` (`:1234`–`1244`), `jl_typemap_intersection_visitor` (`:781`–`795`), and the pre-filter `tname_intersection_dt` (`:398`–`412`), which rejects an entry by typename before any intersection is computed. A method `f(::X)` sits under `name1[X.name]`; a query at a member `S` never reaches it. The level split happens for functions with many methods, which are exactly the cases E-259 counts (`show`, `==`, `hash`, `convert`, `axes`). For small functions the entries are in a linear list, tested by `jl_type_intersection_env_s`, and the subtype fallback suffices.

**Recommendation.** Two options, both cheap: put entries at open sets in `cache->linear` (always visited) and never in `name1`; or make the four walks consult the query type's membership list after its chain. Name it in S2's "Where" and in §3.3's cost sentence. Also note that `METHOD_SIG_LATEST_ONLY` is cleared on every intersecting method at insertion (`jl_method_table_activate`), so a bounded method on `show` costs every `show` method at a non-final type its fast path.

### M2. C7 can be a signature-level rule in `jl_type_morespecific`; the document's argument against it does not hold, and the per-match flag costs the insertion walk and the ambiguity tools

**Location.** §2.4, §3.3 (last paragraph), §8.4, S2.

**The document's argument.** "`Matrix{Float64}` orders `AbstractMatrix` before `ColTable`; another member might have `ColTable` as its only match", so C7 is per argument, not per signature pair.

**Why it does not hold (reasoning).** An order between two methods matters only where both apply. Under the document's own rule, a membership in an open set is always an entry (also `struct S <: X`), and Base's sets are closed, so a value that matches both `f(::AbstractMatrix)` and `f(::ColTable)` reached the closed type through its chain and the open set through an entry, every time. "A closed type other than `Any` is more specific than an open set, at a position" is therefore a relation between the two *signatures*, consistent with Julia's partial order (sets are above `Any` already; two closed unrelated abstract types cannot share a member; open against open goes by set-in-set entries, else ambiguous, as the document says). The remaining per-position conflicts (`f(::KVec{T}, ::Vector{T})` against `f(::AbstractVector, ::Any)`) are ambiguities under Julia's rule, which traits §5.5 already reports.

**What the placement buys (verified mechanisms).** `ml_matches` sorts by `interferences` (`src/gf.c:5090`, `:5122`), computed at insertion from `jl_type_morespecific` (`jl_method_table_activate`, `morespec[j]`). With C7 in `jl_type_morespecific`: `interferences`, `is_replacing`, `detect_ambiguities` and `Test` work unchanged; and the insertion walk `continue`s past every chain-matched method (`if (morespec[j]) continue;`), so inserting `f(::X)` invalidates only `f(::Any)`'s specializations and the "no method" facts. With the document's placement, `jl_type_morespecific` leaves the pair unordered, `ambig = 1`, and every specialization of `f(::AbstractMatrix)` at a non-final type goes through `_invalidate_dispatch_backedges`: the cost D5 accepts is largely self-inflicted.

**Recommendation.** Put C7 in `type_morespecific_`'s datatype case (`src/subtype.c:5484` region): an open typename against a closed one, at a position, orders the closed one first. Drop the `jl_subtype_env` out-flag and the `jl_method_match_t` bit unless a case needs a per-query order; I found none. Re-count W-S2a under this rule.

### M3. `Keyed{X, R, F} <: X` and `Dynamic{X} <: X` are special cases of `subtype`, not declarations, and `Keyed` fails `jl_isa_compileable_sig` as it stands

**Location.** §2.6, §2.7, §3.4, §7 (third row).

**What holds (verified).** `abstract type Keyed{X,R,F} <: X end` is refused: "invalid subtyping in definition of Keyed: can only subtype data types" (run). So `Keyed{X,R,F} <: X` is a case in `subtype` like `Type{T}`'s, and likewise in `intersect`, `type_morespecific_`, `obviously_disjoint`. The `MembershipEntry` schema has `set :: TypeName`; a generic entry "`Dynamic{X}` is a member of `X`" has no fixed set, so it is a special case too (the document's "generic membership entry on its own TypeName" cannot be stored as written). `jl_isa_compileable_sig` (`src/gf.c:1414`–`1590`) returns 0 for an abstract element that is not a `Type` and not in a `nospecialize` slot (`if (!jl_is_concrete_type(elt)) return 0`), and for a `nospecialize` slot requires `elt == decl_i` exactly: `Keyed{…}` passes neither; the erased key passes only as `X` itself. `jl_compilation_sig` has no rule that could produce `Keyed` (its widenings are kinds, `Type{T}`, `nospecialize`, `Function`, varargs). `cache_method` would then try `ml_matches(compilationsig)` for guard signatures; forcing `cache_with_orig` for keyed instances keeps the leaf-cache mapping the document wants and avoids guard entries.

**Recommendation.** List the special cases in §2.6 and S3: `subtype`, `intersect`, `type_morespecific_`, `obviously_disjoint`, `jl_isa_compileable_sig` (a branch keyed on a method's bound-position bits), `jl_compilation_sig` (the same), `cache_method` (force `cache_with_orig`), `jl_isa` (concrete `t` fast path is fine; `Keyed` is abstract).

### M4. Inference specializes per member type whatever `jl_compilation_sig` says; "one MethodInstance per key" needs the `nospecializeinfer` path, and the first-seen rule makes the compilation signature caller-dependent

**Location.** §0, §3.4, §3.5, S3's riskiest assumption; E-256's divergence (1).

**What holds (verified).** `abstract_call_gf_by_type` infers the match at its concrete signature for the caller's result, and, when `infer_compilation_signature(interp)`, *also* infers the compileable signature "so it is available to the compiler in case it ends up needing it for the invoke" (`Compiler/src/abstractinterpretation.jl:325`–`350`). That is why E-256 saw a CodeInstance per type for `@nospecialize`: the compilation signature governs codegen and the `:invoke` target, not inference. The path that widens inference itself is `is_nospecializeinfer(method)` → `get_nospecializeinfer_sig` in `abstract_call_method` (`:632`–`:633`). For bounded methods, whose results are declared, the per-type inference buys nothing and costs an inference per member: the mechanism to cite and extend is `@nospecializeinfer`, with the `S → Keyed{X,R,F}` mapping inside `get_nospecializeinfer_sig`'s analogue.

**A second point (reasoning).** The first-seen rule gives one `(method, tt)` two compilation signatures: the key for a static caller that knows `S`, the erased `X` for a dynamic caller. `jl_normalize_to_compilable_sig`, `cache_method`, `jl_method_match_to_mi` and `precompile` assume one answer per `(method, tt)`. It is workable (the leaf cache serves dynamic callers with the erased instance; inference's `get_compileable_sig` serves static callers with the key), but it is a change to that contract, and compiling ahead at a member's key (traits §13) then needs its own request form.

**Recommendation.** Rewrite §3.4's first paragraph around `nospecializeinfer`; state the two compilation signatures and where each is produced; add to S3's test "one inference per key, not per member" (count CodeInstances of the bounded method after calls at two members with one key).

### M5. The boxed adapter is per member, not per key: "no entries, no views" and "one instance per key" cannot both hold on the dynamic path

**Location.** §3.4 ("The projection convention", "The adapter"), §3.5, §8.4, T-94.

**What holds (verified mechanism, reasoning on the design).** A CodeInstance has one `invoke` and one `specptr`; `gen_invoke_wrapper` (`src/codegen.cpp:7040`) emits one boxed-to-specsig wrapper per compiled instance. The keyed instance's wrapper must turn *any* member's boxed value into the key's parts: the receiver and the declared fields at the member's offsets. Either the wrapper reads the offsets from a per-(member type, set) table at run time (TraitWorld's layout table, moved into the runtime: a lookup per dynamic call), or there is one wrapper per member (a CodeInstance per member for the boxed entry, the per-type cost T-94 names). A static caller that knows `S` emits the projection in place and is unaffected.

**Recommendation.** Say which, and cost it in S3's prototype: the dynamic call of E-256 (80–96 ns today) is the number to beat, and E-164's view numbers are the reference. D2 cannot be decided before this measurement.

### M6. A positive membership fold needs a `min_world` bound; memberships on foreign types need an image activation list; redeclaration needs an invalidation walk by key

**Location.** §2.2 ("The compile-time positive … with no edge"), §2.1 ("Worlds"), §4.3.

**What holds (reasoning from verified mechanisms).**
- A fold of `S <: X` to `Const(true)` records nothing. The CodeInstance's `min_world` is then bounded only by its other edges and may lie below the entry's `min_world`. A task in an older world (`invoke_in_world`, E-254's part B case) running that CodeInstance sees `true` where its world has no membership. Methods avoid this through the match's `min_valid`. The fold must raise `min_world` to the entry's; that is a world bound, not an invalidation edge.
- A package image that declares `BaseTraits`' memberships writes entries on `Array`'s `TypeName`, an object of the system image. Images cannot modify other images' objects except through explicit lists activated at load (`extext_methods`, backedges, new specializations). Memberships on foreign types need such a list, activated before the image's code is validated, and a membership edge kind in `verify_method` for the folded positives (the document names the record entry in §3.8 but not the loader side).
- "A redeclared implementation replaces the entry's key … a stakeholder's change": code compiled at `Keyed{X, R_old, F_old}` and callers that folded against the old key must be invalidated. The walk by key is not described; the old entry needs a `max_world` for older tasks, as a replaced method does.

**Recommendation.** Add the three to §2.1/§2.2 and to S1's list; test the old-world fold in S1's test.

### M7. Result edges, even with H1 fixed, cannot cover constant propagation, concrete evaluation or inlining

**Location.** §3.8 (the record's four kinds; "result edges may go anywhere"), §4.1 item 1.

**What holds (reasoning).** A value folded by concrete evaluation, a constant propagated through the callee, or an inlined body depend on the callee's *code* with those arguments, not on its `rettype`, `exctype`, `ipo_purity_bits` or `rettype_const` for all arguments. K′ may agree with K on all four and compute a different constant for the folded arguments (its code changed; that is why K was invalidated). Such edges must stay code edges (invalidate), as the "inlined-code identity" already is. The document lists folds and inlining separately but leaves constant propagation and concrete evaluation under result edges by omission.

**Recommendation.** Define a result edge as "the call was emitted as a call and its result used as a type"; everything else is a code edge. W-S0a should count under that definition.

### M8. The store (D6): the JIT's object code cannot be written out; cross-image calls are already slot-indirect; `clone_idxs` is multiversioning

**Location.** §4.4 ("Recording", "the JIT keeps the object code it emitted"), §7 (first row), S4's riskiest assumption.

**What holds (verified).**
- Package images are emitted by `jl_emit_native_impl` (`src/aotcompile.cpp:784`) from inferred code with `external_linkage`, then `jl_dump_native`; the ORC JIT links its modules in memory with addresses resolved. There is no path from JIT object code to an image. `precompile_keep_ir` (`src/gf.c:1067`; `staticdata_utils.c:125`) keeps inferred `CodeInfo`, not object code. A shard written at exit is a second code generation per instance in the producing session; E-205 (unverified by me; the row exists) says code generation dominates compile time, so the producing session pays most of what the consuming sessions save, once per instance.
- `jl_image_fptrs_t.clone_idxs` are "sorted indices of the cloned functions" (`src/processor.h:83`), the CPU-target clones; `jl_update_all_fptrs` uses them with `jl_sysimg_val_mask`. They have nothing to do with linking against other images.
- A call from one image into another's code loads the pointer from a `p<name>` global (`emit_call_specfun_other`, `src/codegen.cpp:5355`–`5365`, `external_fns`), filled at load by `jl_update_all_gvars` from `link_ids_external_fnvars` (`src/staticdata.c:2345`–`2370`, `write_gvars` `:2323`). So cross-image calls are one indirection already; "if relinking by identity cannot keep direct calls between shards" worries about a form that does not exist. Relinking by identity is: resolve each external-function slot and each data relocation by identity instead of build id and offset. The uniquing pass (`uniquing_types`, `uniquing_objs`) already resolves external types and MethodInstances structurally, as §4.3 says.

**Recommendation.** Correct the two sentences; add the producing session's second code generation (or kept LLVM IR, with its memory) to §4.4 and to S4's test; name the per-MethodInstance slot of H1 as the same mechanism, so that one design serves both D3 and D6.

### M9. `Callable` on `OpaqueClosure` (D7) re-creates the thunk it means to remove

**Location.** §2.7, §8.7, D7.

**What holds (verified).** `new_opaque_closure` (`src/opaque_closure.c:31`–`135`) compiles one `source` method's specialization in a fixed `world`, selects the return type at creation (`selected_rt`, from the CodeInstance's `rettype` against the declared bounds), builds the type `OpaqueClosure{argt, selected_rt}` and stores `invoke`/`specptr` pointers; codegen calls `specptr` directly where it knows the type. A `Dynamic{Callable{A, S}}` holds a user's generic function (traits §7.5), whose target at `A` may change with any method definition: there is no single `source`, the pointer must be re-resolved per world, and `R` must be the declared `S` with the per-call check the contract already requires. Supplying a `source` means a synthesized method calling `f(args...)`, with a world-checked pointer cache in front: that is the `:caller_world` thunk with a different object around it.

**Recommendation.** Keep the `cfunction` thunk; state what the opaque-closure form would gain (the one candidate: codegen's direct `specptr` call for the `Compiled` form, which the key gives anyway). Defer D7 until a measurement names a cost of the thunk that the object would remove.

### M10. Guard cells per (member typename, set) are too coarse for parametric memberships; the ambiguity report at a membership needs an index the method table does not have

**Location.** §3.3 ("The guard"), §2.3 ("Ambiguity between two open sets").

**What holds (reasoning).** `Vector{T} where T <: Real ∈ KVec` sets the cell `(Array, KVec)`. Every guarded site at `Vector{String}` then takes the slow branch, a full dispatch, on every call, for the rest of the session: the static call is lost permanently where the membership does not even apply. A cell per (member type object, set) for parametric entries keeps the fast path; the type object is a stable cached object. The ambiguity report "for each function with a method on the new set and a method on one of the others" needs an index from set typename to methods whose signatures name it; the method table is indexed by function, and `jl_methtable_t.backedges` by callers' top typenames.

**Recommendation.** Say both; the index is small (methods at sets are rare: U5 counted 127).

### M11. The codegen precedent for the guard is wrong: there is no "world-age check for `invokelatest`" to copy

**Location.** §3.3 ("Codegen emits it as it emits a world-age check for invokelatest").

**What holds (verified).** `invokelatest` lowers to a `:latestworld` statement; codegen stores the world counter into the task's `world_age` (`src/codegen.cpp:6907` region; `emit_tls_world_age_store`) and the call then dispatches in that world. Nothing in codegen compares a stored world against the task's and branches. The closest existing shape is the patched `:caller_world` thunk (`src/runtime_ccall.cpp`), which is runtime C++, and `ir_inline_unionsplit!`'s branch shape for the two targets (the document names this one in S2, correctly).

**Recommendation.** Replace the sentence: the guard is a load of the cell's `min_world`, a compare against `emit_tls_world_age_load`, and a two-way branch emitted by the inliner's union-split path; LLVM hoists the load where E-259 measured it.

---

## Low

### L1. Attribution precision
- `jl_method_table_insert` (`src/gf.c:3204`) is now a wrapper; the intersection walk and invalidation are in `jl_method_table_activate` (`:2953`). §2.3 and §3.2 should cite the latter.
- `get_compileable_sig` is `Compiler/src/utilities.jl:159`.
- "1.13's global table with per-typename caches": there is one global `jl_methcache_t` (`src/julia.h:918`–`:931`); the typemap *levels* split by typename.
- The chain walk is in more places than `:1535` and `:1580`: `obviously_disjoint` (`:562`, `:566`), the datatype fast path at `:2096`, `intersect` (`:3818`), `jl_type_intersection` (`:4294`), `type_morespecific_` (`:5484`), and typemap.c's four (M1). S1's "Where" should list them.

### L2. The line counts hold
`TraitWorld/src` is 13,565 lines; the seven files S3 names total 5,955 ("about 6,000"). Not all of `core.jl` goes (the registries S1 keeps until S2), so the figure is an upper bound.

### L3. The `concrete_only` precedent is read correctly, and the generalization is a real change of key
`is_concrete_only(func)` (`abstractinterpretation.jl:143`) refuses when any applicable match has a non-concrete `spec_types`, keyed by the *callee's* function. The facts policy is keyed by the caller's method and by the fact-signature forms. "Generalize" is the right word; the PR will touch `abstract_call_gf_by_type`'s one site and `find_method_matches`'s gate (where the patched build has it).

### L4. Conventions
- `Keyed{X, R, F}` appears in reflection: `Base.specializations`, `@code_typed`, stack traces (`f(::Keyed{ColTable, Vector{Vector{Float64}}, …})`), `MethodError` hints. The user's rule against hidden type parameters was about struct parameters the user does not write; this is a compilation-signature type the user never writes but will see. Say how it prints in each place (the `Base.show` method covers `Type{<:Keyed}`; stack traces print signatures through `show_tuple_as_call`, which may need the same).
- `Both{X, Y}` likewise.
- `facts`, `bounded`, `concrete`, `no_pirates` as declaration names are from the user's perspective; "`Dynamic` is `@nospecialize` with a declared contract" is a core developers' framing, fine in an exploration, not for `intro/`.
- No inlining is promised; "inlined where small" quotes E-256.

### L5. Memberships advancing the world counter meets C-3
Exact-type entries of the per-call-site cache and `:caller_world` entries are capped at the latest world when made (compiler C-3). Every `@implement` then costs each such site one miss. Not a problem; a reason to fix C-3 before S1 lands in the demonstrators' sessions.

### L6. Numbers I did not re-derive
E-164, E-180, E-188, E-194, E-195, E-205, E-212, E-214, E-215, E-233, E-234: the rows exist in `experiments.md` and are marked done; I checked that each number the document quotes appears in its row's outcome where the preview showed it (E-233's 1,884, E-234's ranges, E-259's counts and nanoseconds, E-255's percentages) and did not re-derive the rest.

### L7. The abstract-query case is absent
Nowhere does the document say what `ml_matches` returns for a bounded method at an abstract signature (plain code calling `f(x::AbstractFoo)`), what `fully_covers` is, and what inference does with the partial match. H2 gives the answer the mechanism needs (`spec_types = X`, never fully covering, the erased instance inferred). It belongs in §2.3 or §3.3.

### L8. The `jl_subtype_env` out-flag, if kept, must survive backtracking
`subtype` backtracks over unions and `UnionAll`s (`save_env`/`restore_env`); a flag set on a failed path must be reset. With M2 the flag is not needed.

### L9. D9's field is a bound, not a result
Inference may read `declared_rettype` as an upper bound only because the body asserts it; `return_type` and `Callable` checks must keep the assertion in the body. Adding a field to `Core.Method` changes its serialized layout; Revise and Cthulhu construct or read `Method`s.

### L10. `jl_isa` returns 0 for a type value against a non-`Type` datatype before any membership is consulted
`src/subtype.c:2525`–`2545`: for `x` a type and `t` a datatype whose name is not `Type`, `jl_isa` returns 0 ("`else { return 0; }`"). So `isa(Int, X)` for a set `X` with the member `Type{Int}` (open issue 91's decision) is false whatever the entries say. §2.8's "no new rule is needed" is wrong for the runtime side; `jl_isa`'s type-value branch must consult `Type{S}` entries, and so must `intersect`, which `jl_isa` would otherwise use.

---

## What the document gets right, for the record

- The inventory of places (§1's table, §10's sources) is accurate line by line and is the best map of the upstream surface the project has; it should be kept as a working document whatever D1–D9 decide.
- "Sets as TypeName memberships, on the member" is a sound storage choice; the subtyping fallback after the chain fails is the right hook and the branch cost is as stated.
- The policy per method generalizing `concrete_only`, the dependency record as a CodeInstance property, and G2 as a predicate on the record are right and upstream-shaped; only the revalidation half fails (H1, M7).
- The erased key as `@nospecializeinfer`'s signature (once M4 corrects the attribution) is exactly rule 5, and E-256 is the evidence for it.
- The store's identity (what it is and is not keyed on), its validation by `verify_method_graph` for dispatch edges, its exclusions (§4.5), and "per-environment first" are right.
- The departures list (§8) is honest, and §7's "what would make the reframing fail" names the right risks in the right order, with H1 the one it misses.

## Suggested order of work after this review

1. Correct H1–H3 in the exploration (a dated addendum or a revision), since D3 and S1's design change with them.
2. W-S0a as proposed, with M7's definition of a result edge; it decides whether the per-MethodInstance slot is worth designing.
3. W-S2a under both C7 placements (M2).
4. S1 with H4's stopgap and the structural exclusion (H3), tested as H3 and M6 say.
5. S3's prototype with M4's inference rule and M5's boxed path measured before D2.
