# Review: the traits+facts compiler as built in session 29

Fable 5.1, 2026-10-19. Reviewed: `julia-1.13` db82407fa6..f6838f96fc (parts A–D, the trim switch, the
assertion rule), TraitWorld 3db6592..1098fab (`compiler.jl`, `core.jl`, `trait_module.jl`,
`checks.jl`, `verify.jl`, `strict.jl`, `certificate.jl`, `entry.jl`), `experiments/facts/acceptance_compiler.jl`,
`experiments/facts/invalidation/inval.jl`, against `writeup/design.md` and the plan's §6b. Every finding
is marked **Verified** (source read, or an experiment under `/tmp/claude-1000/review-impl2/`) or
**Reasoning**. Experiments ran on the patched build, one process at a time, niced; scripts and outputs:
`x1_dynamic.jl`/`x1.out`, `x1b_dynamic_tw.jl`/`x1b.out`, `x1c_nonfold.jl`/`x1c.out`,
`x2_owners.jl`/`x2.out`, `x3/` (two packages through package images), `x4/` (trimmed binaries).
TraitWorld experiments used the committed 1098fab (extracted with `git archive` to `tw1098/`): the
working tree's uncommitted edits (`implement.jl`, `strict.jl`, `certificate.jl`) do not precompile
("cannot document the following expression", `implement.jl:134`).

## 0. Verdict

The architecture is right and most of it is sound: one interpreter with a mode and an owner, the owner
chosen by the method's module, plain code naming facts CodeInstances through a nested inference,
run-time sites in facts code dispatching to facts code, facts code in package images. Package images
work, including the `return_type` fold through plain inference and its edges (verified here for the
first time outside TraitWorld's own tests, which have no image test). The acceptance suite's 17 cases
hold.

Three things are wrong, in this order:
1. **Part (D) compiles wrong code** whenever inference knows the dynamic value's type and the
   operation's method is vararg, which every trait-object forwarder is (`op(t::TObj{T}, args...)`).
   The inliner inlines the callee with the arguments of `dynamic_call` itself. Verified through
   TraitWorld with a module-level `const D = Dynamic{Col}(…)`: `FieldError: type UnionAll has no field
   views` from `viewof`, and a corrupted `BoundsError`. By construction it can be memory-unsafe.
2. **The assertion exemption breaks "identical or error" (G1)**, not only G2: a Base method asserted
   `:foldable` over a run-time site is folded in facts code with no edge, and a later non-pirate
   definition is followed by plain code and not by facts code. The design's sentence "the same exposure
   plain Julia has" is false; plain Julia records the edge. Verified in the mechanism; no Base method
   with that shape is known to me today, which bounds the damage, not the claim.
3. **`--trim` turns facts off only in the build process.** In the binary `JLOptions().trim == 0` and the
   module flag is still `1` (verified), so `jl_default_owner` asks for `:facts` code the build never
   made. Static `:invoke`s are unaffected; `jl_invoke` with a MethodInstance (`emit_invoke`'s
   `needsparams` path) and any dynamic site trim leaves are not. Medium: cheap to fix, hard to hit.

Everything else is coverage and claims (part (C) does not reach C-level re-entries; the `Dynamic`
split's result is typed `Any` and boxes one value per call; the candidate list makes speed depend on
compile order), waste (piece 5's foreign half now compiles every foreign owner's IR into images), and
places where one rule lives in two or three pieces of code.

## 1. What was verified to work

- **(A), (B), (C) end to end** (Verified in the cases I ran; the acceptance suite was run by session 29,
  not by me): a facts module's methods have only `:facts` CodeInstances; a plain caller names the facts
  CodeInstance through `facts_edge` and does not inline it; a run-time site in facts code compiles and
  runs `:facts` code of the callee (`x2.out`: `Plain.k` has only a `:facts` CodeInstance after a
  run-time site and a fact from facts code); a boundary (`Expr(:meta, :facts, 0)`) is compiled plainly
  (`Method.facts == 1`, owner `nothing`).
- **Package images** (Verified, `x3/run1.out`, `run2.out`, `run2a.out`, `run2b.out`): after `using`
  from an image, the module flag survives (`jl_write_module` dumps the struct raw, so the new field
  needs no serializer change), a submodule inherits it, `Method.facts` survives, every method has one
  `:facts` CodeInstance with native code (`invoke != C_NULL`) and inferred IR, calls run it without
  recompiling (the CodeInstance list is unchanged after the calls), and an unrelated `Base.string`
  method invalidates nothing. The `return_type` fold through plain inference survives too: `rtdirect`'s
  `:facts` CodeInstance keeps its edge to a `:facts_plain_return_type` CodeInstance of `h2(::Int)`,
  valid and in that MethodInstance's cache; `map(h2, Int[])` gives `Real[]` as plain Julia does; a
  redefinition of `h2` is followed (`Any[]` both, `Union{Float64, String}`). A run-time site's target
  (`Base.string(::Int)`) is in the image only if a workload ran it at precompile time; that is piece 5's
  `jl_set_image_keep_compiled`, switched on only when TraitWorld is loaded.
- **Cache owners do not mix** (Verified, source): `jl_get_ci_equiv` compares owners; `code_cache` is
  per owner; `jl_method_compiled_callptr_owner` filters by owner; `rests_on_facts` and
  `facts_plain_return_type` cache under `:facts_plain_return_type`, which nothing dispatches on.
  `return_type` at run time under the product setting uses a plain `NativeInterpreter` (owner
  `nothing`); under `all` a `PlainRTInterp`. The `Compiler.return_type` wrapper itself gets a `:facts`
  CodeInstance when called from facts code (`x2.out`); harmless.
- **World age** (Reasoning, source): `facts_edge` and `facts_interp` use the caller's world;
  `facts_plain_return_type` intersects the method-table validity with the plain result's worlds and
  calls `update_valid_age!`; the `Dynamic` fallback dispatches through `jl_apply_generic_facts` in the
  task's world; each split has an edge (acceptance G1.14, G1.17). Invoke-style edges `(sig, ci)` from
  `PlainRTInfo` are invalidated when a new method applies at `sig` and beats the target (G1.9, `x3`).
- **Fact signatures** (Reasoning): concrete tuples and their union splits are facts by Lemma O; tuple
  arguments with unions of concrete elements admit exactly their splits (tuples are covariant), so a
  method intersecting the signature applies at a split; a concrete `Vararg` tail keeps the owner set
  of every instance it admits; a closure's call at kinds can gain methods only from the closure's
  module (or from a pirate adding a method to a closure type). All four are "changeable only by
  stakeholders or pirates". `invoke` at an abstract signature (`abstract_invoke` is not routed through
  `facts_find_method_matches`) records an edge at the invoke type; a method that changes `findsup` there
  has a signature that is a supertype, whose owner is a stakeholder by the design's definition
  (supertype owners count). Sound, but unstated in rule 1.
- **Threads** (Reasoning, source): the candidate table is copy-on-write under `@atomicreplace`;
  `jl_compile_by_facts` caches its answer in an atomic; the engine's cross-thread cycle detection
  (`engine.cpp:78`) covers the nested inferences (`facts_edge`, `facts_plain_return_type`), which only
  enlarge a thread's set of reservations. Not exercised by any test; the design excludes threads.
- **Strict mode** (Verified, source): `_trait_world_code` protects every `:facts` CodeInstance and plain
  CodeInstances of trait-module methods (boundaries); the safety net catches what the pre-check misses.
- **`verify_main` and the certificate** (Verified, source): scanning infers facts methods, and code
  reached from them, under a facts interpreter with the `:facts` owner; `_has_native` accepts both
  owners; `fully_typed` walks from a plain caller so entries are seen as boundaries.
- **Lowering and `method.c`** (Verified, source): the boundary meta reaches the keyword sorter and the
  positional forwarder (`facts-meta-only`), merged metas are scanned; the `nargs > 2` branch in
  `jl_method_set_source` swallows every other three-argument meta for the rest of its `else if` chain,
  but nothing after it has `nargs > 2` today.

## 2. Correctness and soundness: findings, ranked

### 2.1 Part (D): wrong code when the dynamic value's type is known (critical) — Verified

`abstract_dynamic_call` (`facts.jl`) narrows `x` to the candidates' union only when `widenconst(x)` is
not a dispatch element. When `x` is concrete (a `Const` dynamic value such as a module-level
`const D = Dynamic{X}(…)`, a `Dynamic` constructed and used in one body, or a caller specialized at the
object's type) it returns the inner call's `CallMeta` unchanged: the statement is still
`dynamic_call(K, f, x, args...)`, its `info` describes `f(x, args...)`. The inliner only rewrites the
statement when `inst[:info] isa DynamicSplitInfo`. For a non-vararg callee `analyze_method!` refuses
(`na != npassedargs`), so the call stays dynamic: correct, but the direct call plain Julia would make is
lost. For a vararg callee the arity check passes (`method.isva`), and `ir_prepare_inlining!` maps the
callee's arguments onto `[dynamic_call, K, f, x, args...]`: `K` (a type) becomes the receiver and
`(f, x, args...)` the vararg tuple. When the whole call concrete-evaluates (a pure operation on a
constant, as `sconst()` in `x1b.out`) nothing is inlined and the result is right, which hides the bug
in small tests.

Experiments: `x1.out`, `abstract_x(x) = Compiler.dynamic_call(Shape, area, x, 1)` with
`area(s::Sq, extra...)`, called as `abstract_x(Sq(2.0))`: `FieldError: type DataType has no field a`
from `area` inlined into `abstract_x(::Sq)`, while `code_typed` at `(Any,)` shows the intended split
(which is why the check script and `verify_dynamic` did not see it). `x1c.out`, through TraitWorld
1098fab: a trait `Col` with `cdata(r)::Vector{Float64}` (not foldable: it returns a mutable value),
`const D = Dynamic{Col}(A([1.0, 2.0]))`, `csum_const() = sum(cdata(D))`: `FieldError: type UnionAll
has no field views` from `viewof` inlined into `csum_const` (the receiver is the trait family `Col`),
followed by a `BoundsError` whose array field is a `Symbol`, that is, a value of the wrong type in a
position codegen trusted. `csum_arg(D)` through a `Dynamic{Col}` argument gives `3.0`. The `FieldError`
is the lucky case (a `getfield` on a value whose codegen type is a kind falls back to the checked
builtin); a field read the callee's IR typed concretely becomes an unchecked load.

Every operation forwarder TraitWorld generates is vararg (`trait.jl:295`,
`op(t::TObj{T}, args...) = opcall(…, t, args...)`), so the condition for wrong code in trait code is
exactly "`opened(dyn)` inferred concretely", which `@constprop :aggressive` on `_dyn_call` makes
common for constant and locally made dynamic values.

Fix: the inliner must rewrite every `dynamic_call` statement to the call it stands for, keyed on the
callee (`sig.f === dynamic_call`), not on the info type; and `abstract_dynamic_call` should always
return a `DynamicSplitInfo` (with a flag "covered" when `x` was concrete, so `compute_inlining_cases`
need not add a dead fallback). Add the concrete case to the acceptance suite (G1.18: a constant
`Dynamic` with a non-foldable operation, and a caller specialized at the object's type) and to
`verify_dynamic`.

### 2.2 Asserted effects under facts can break G1 — Verified (mechanism)

Rule 1: "Compile-time evaluation only over facts, or where Julia's own asserted effects fold (Base and
Core methods asserted foldable). That exception inherits Base's assertion: the same exposure plain Julia
has." The second sentence is false. Plain Julia infers the asserted method's body and records edges for
its abstract calls (up to `max_methods` matches, or a method-table edge); concrete evaluation then
folds. Facts inference records no edge at a run-time site, and the fold bakes in the dispatch.

Experiment (`x2.out`): a method defined into `Base` as
`@assume_effects :foldable bfold_review(x::Int) = Main.Fold2.g2(Base.inferencebarrier(x))`, called at
a constant from plain and from facts code; then `Fold2.g2` redefined (a stakeholder's change, no
pirate): plain `(1) → (2)`, facts `(1) → (1)`; `FM2.kf`'s code is the folded constant. Facts code
keeps computing a value plain Julia no longer computes: G1 fails, not only G2.

Damage today: it needs a Base/Core method asserted `:foldable`/`:total` whose body has a call that is
not at a fact signature and that a non-Base method can win. The 22 assertions in `base/` (and the
`@_foldable_meta` users) are type-level or on Base types; I found none with that shape. The claim and
the mechanism are still wrong, and any future Base assertion of that shape becomes a silent G1 hole.
Under `all` (Base compiled by facts) the surface is Base's whole asserted set.

Fix: make the rule's first half exact. Fold a Base/Core asserted method under facts only when its
CodeInstance rests on facts (`rests_on_facts(edge)`, already written for `return_type`), else treat the
call as a run-time site. Type-level Base code is mostly at kind signatures (`DataType`, `Type{T}`),
which are facts, so the folds the DataFrames port needed (lesson 1.2) should survive; measure on the
BaseBenchmarks tail groups. Rewrite rule 1's sentence either way.

### 2.3 `--trim` turns facts off in the build, not in the binary — Verified (state), Reasoning (effect)

`jl_method_is_facts` (`module.c:741`) and `jl_compile_by_facts` (`gf.c:1117`) read
`jl_options.trim`. In the process that builds the image it is set, so every trait method is inferred
plainly and the image holds plain CodeInstances. In the built binary nothing restores `trim`: `x4/`'s
binary prints `JLOptions().trim at run time: 0` and `module facts flag: 1` (Verified). So
`jl_default_owner` answers `:facts` for a trait method again, `jl_method_compiled_callptr_owner` finds
no `:facts` CodeInstance, and `jl_compile_method_internal_owner` reaches its fallbacks: with IR stripped
(`def->source == jl_nothing`) it copies the unspecialized fptr into a new owner-`nothing` CodeInstance
if one exists (which the next `:facts` lookup misses again), else `MissingCodeError` (source,
`gf.c` lines 63–95 and 165–185 of the function).

What reaches it: not statically resolved `:invoke`s (they call a CodeInstance's pointer), and not the
single-method calls at `Any` that the inliner turns into `isa`-guarded invokes (my first binary's
"dynamic" call was one of those and ran at 0 ns). It is `jl_invoke` with a MethodInstance
(`emit_invoke`'s `needsparams` path: static parameters codegen cannot recompute) and whatever dynamic
sites `--trim=unsafe-warn` leaves; trimmed binaries refuse `jl_apply_generic` even for plain methods
(a `MethodError` from `jl_lookup_generic_` in `x4/driver6.out`), so the second class is already
fragile for everyone. Medium severity: a latent inconsistency, cheap to remove.

Fix: do not consult `jl_options` at run time. Clear the mode when the image is written: in
`jl_write_module`, `newm->facts = 0` when `jl_options.trim`; for methods (dumped by layout) set
`facts = 1` (boundary) in `jl_method_set_source` when `jl_options.trim`, or special-case them in the
serializer. Then a trimmed image is a plain image and the runtime needs no `trim` check at all;
`jl_compile_by_facts`'s trim branch stays for the build. The `x4/` build takes 5 s and 1.8 MB; keep one
in the acceptance set.

### 2.4 Part (C) reaches only codegen's own call sites — Verified

Facts code dispatches to facts code through four codegen sites (`emit_call`, `emit_invoke`'s
`needsparams` and fallback, `_apply_iterate`/`_apply` with known tuples, `_call_latest`/`_call_in_world`).
Any dispatch that goes through the runtime's `jl_apply` runs plain code: the `_apply_iterate` builtin
on a non-tuple (`Plain.h(v...)` with `v::Vector` from facts code gave `Plain.h` only a plain
CodeInstance, `x2.out`), the `invoke` builtin at run time (`Base.invoke(f, Tuple{Any}, x)` with `f`
unknown: plain), `jl_call`, `@cfunction` callbacks, finalizers, task entry. `invokelatest` is covered
(`Plain.g` got a `:facts` CodeInstance), because codegen handles `_call_latest`.

Consequence: not a G1 problem (plain code computes the same), and facts methods stay facts whoever
calls them (`jl_default_owner`). But the plain code reached that way is unprotected and compiled twice,
and `hcat(cols...)`-style splats are common in library code. The design's "a run-time site in
facts-compiled code runs facts-compiled code" needs the qualification, or `jl_f__apply_iterate` and
`jl_f_invoke` need owner-aware twins that codegen emits under `in_facts_code` (the builtin call sites
are known to codegen), which covers the two common cases.

### 2.5 The `Dynamic` split's result is `Any`: one box per call — Verified

`abstract_dynamic_call` returns `CallMeta(Any, …)` so that the fallback's unknown result is admitted;
TraitWorld asserts the declared type after the call. The union split then feeds typed branch results
and the fallback into a phi of type `Any`, and codegen boxes them: `x1b.out`, `stotal` over 2000
dynamic values of two conformances allocates 32,000 bytes (one `Float64` box each) at 8.7 ns per
element; the IR shows `φ (…)::Any` followed by `typeassert(%105, Float64)`. The split saves the
dispatch and pays an allocation, which is not what §4.5 promises for the raytrace case. Fix: pass the
declared result type to the compiler (`dynamic_call(K, RT, f, x, args...)`), return `RT` as the
call's type and typeassert the fallback inside the split, so the phi is typed. This also lets the
caller's type stay precise when `x` is concrete (§2.1).

### 2.6 The candidate list makes speed depend on compile order — Verified (cost), design-level

The split uses the candidates registered when the caller is compiled, with no edge (by design). A caller
compiled before a conformance is declared keeps the smaller split for ever; its values of the later type
run the fallback (correct, acceptance G1.17). `x1b.out`: a third conformance declared after `stotal`
was compiled runs through the fallback at 14.5 ns per element (still boxing); a caller compiled after
it splits three ways at 15.5 ns per element, that is, the three-way split with boxing is no faster than
the two-way split plus fallback. Review 1's finding 4 ("key branches make speed depend on load order")
is therefore still true of (D); `@constprop :aggressive` on `_dyn_call` only moves the decision to each
caller's own compile time. In a package image, the library's hot loops are compiled with the library's
own conformances and never split over a user's types. Either accept it and say so in §4.5, or record an
edge to the candidate list for the trait (invalidation at a conformance: the sanctioned extension point,
"code it depends on" in the design's own words, and rare).

### 2.7 Smaller soundness notes

- **Strict mode and `Vararg` facts** (Reasoning): `_would_win_split` tests the whole vararg signature
  (`concrete_splits` returns `nothing` for it), so a pirate winning at `f(a, e, e)` but not at `f(a)`
  is not refused before the definition; the safety net deletes it afterwards (`later = true`). State it
  or enumerate up to `max_varargs`.
- **Plain callers never fold facts methods** (Verified, `x1b.out`): `leaves_to_facts` blocks
  const-prop and concrete evaluation of a facts method from plain code, so `FMc.direct(5)` stays an
  `:invoke` where plain Julia folds `6`. Correct (plain rules must not infer facts code) and a
  behavioural difference to state. Entries are boundaries, so trait entries are unaffected.
- **Plain callers never inline facts code** (Verified, `x2.out`): `resolve_todo` looks the callee up
  in the plain cache, misses, and `compileable_specialization` (patched) emits an `:invoke` of the
  facts CodeInstance; `@inline` is ignored across the boundary. A good property, by accident of a cache
  miss; make it explicit in `resolve_todo` (`leaves_to_facts → :invoke`) and state it.
- **`facts_edge` from non-native interpreters**: `PlainRTInterp` and TraitWorld's `_CheckInterp`
  infer facts methods under plain rules in their own caches (intended: `return_type` is plain Julia's
  answer; the checks want plain precision). Cthulhu-style interpreters do the same. Fine; say so at
  `leaves_to_facts`.
- **Compiler code under `:facts`**: `jl_apply_generic_facts` compiles whatever method it finds under
  `:facts`, including `Compiler.return_type` and `Compiler.register_dynamic_candidate!` (both called
  from trait code). Harmless (their bodies are concrete). Under `all`, the compile queues
  (`compile!`, `interp_for_owner(…, nothing)`) do not apply `is_compiler_code`, so a facts system
  image may compile the compiler by facts: the plan's R2 ("checked by timing inference itself") is not
  recorded as done.
- **Hot path**: `jl_default_owner` adds three loads (`jl_options.trim`, `m->facts`, `m->module->facts`)
  to every `jl_apply_generic`. Probably invisible; measure once against the base commit.
- **`rests_on_facts`** walks up to 2000 CodeInstances per `return_type` fold with no memo; a
  compile-time cost on `return_type`-heavy code (broadcast). Memoize per CodeInstance and world.
- **`FACTS_IMAGE[]` is written inside `facts_default()`**, a predicate called from constructors. Move
  the write to the image build.
- **`jl_compile_method_internal_owner`'s fallbacks** create owner-`nothing` CodeInstances (the
  `unspecialized` copy, the interpreter under `--compile=min`); a `:facts` lookup then misses them on
  every call and recomputes. Correct; a cost only off the normal path (and the trimmed case of §2.3).

## 3. Simplicity

- **One rule, three places.** "Assertions are trusted only in Base and Core under facts" lives in
  `facts_eval_refused` (`concrete_eval_eligible`), `adjust_effects(ipo, def, interp)` and
  `merge_override_effects!`. After the second and third, the first is redundant except for CodeInstances
  cached plainly before the mode changed (the `all` test bed on a plain image). Keep one predicate
  `trusts_assertions(interp, method)` and the two effect sites; delete `facts_eval_refused`.
- **Two implementations of "the splits of a signature".** `fact_splits_ok`/`tuple_splits` count,
  `concrete_splits`/`tuple_alts`/`cartesian_push` enumerate, ~90 lines together, and they must agree
  (strict mode's `_fact_splits` uses the second, inference the first). Define
  `fact_splits_ok(T) = concrete_splits(T) !== nothing` and keep the vararg and closure cases apart.
- **Five redirect points** for "a facts method belongs to the facts owner": `typeinf_edge`,
  `typeinf_ext`, `typeinf_frame`, `abstract_call_method_with_const_args`, `compileable_specialization`
  (plus the accidental one in `resolve_todo`). Each is a one-liner, which is good; a single
  `owner_interp(interp, method)` would name the invariant. The C side mirrors it in `jl_default_owner`
  and four `_owner` variants: fine.
- **Two fields that must agree.** `NativeInterpreter.facts` and `.owner`: `(true, nothing)` is the
  `all` test bed, `(true, :facts)` the product, `(false, nothing)` plain, `(false, :facts)` never. One
  `mode` would do. Low priority.
- **The facts meta, parsed twice.** `method.c` scans a standalone `(meta facts n)` and a merged
  `(meta inline facts n)`; lowering appends a standalone copy to the keyword sorter and the forwarder but
  leaves the original body's merged form. Normalize in lowering (`pushmeta!` merging is the cause) and
  keep one branch in `method.c`.
- **Piece 5's foreign half is now waste.** `collect_foreign_cis!` and `add_foreign_codeinfos!` skip
  `:facts` (which goes through the compile queue) and so compile every *other* foreign owner's cached
  IR into the image: TraitWorld's `_CheckOwner` CodeInstances (the definition checks) and the
  `:facts_plain_return_type` ones, whose IR nothing ever calls. Keep `ext_foreign_cis` → `new_ext_cis`
  (needed so a `:facts` CodeInstance of a Base method and a `return_type` edge target are serialized and
  validated, as `x3` shows they are), delete the native-code half.
- **TraitWorld**: `compiler.jl` is 80 lines where `facts.jl` was 848; `_dyn_call`, `_note_conformances!`
  and `register_dynamic_candidate!` at construction are the right size. `_note_conformances!` infers
  `_dyn_tobj` under the checks' interpreter for every conformance on every `_bump!`, memoized in
  `_CAND_SEEN`: fine.

## 4. Experiments, summarized

| Script | What it checks | Result |
|---|---|---|
| `x1_dynamic.jl` | (D) with a vararg callee at a concrete `x`; the abstract split's IR | wrong code (`FieldError` on a `DataType`); the split's phi is `Any` |
| `x1b_dynamic_tw.jl` | TraitWorld `Dynamic`: constant and local values (foldable operation); allocation; order dependence; const-prop block | folded whole (correct); 16 bytes per call; fallback 14.5 ns, 3-way split 15.5 ns, 2-way 8.7 ns; `direct(5)` not folded |
| `x1c_nonfold.jl` | TraitWorld `Dynamic` constant with a non-foldable operation | wrong code (`FieldError: UnionAll has no field views`, a corrupted `BoundsError`) |
| `x2_owners.jl` | owners reached through `invokelatest`, a `Vector` splat, the `invoke` builtin, a run-time site; plain callers inlining facts code; the asserted-effects fold | `invokelatest` facts, splat and `invoke` plain; never inlined; facts stale `(2, 1)` against plain `(2, 2)` |
| `x3/load.jl` | a package compiled by facts through an image: flags, owners, native code, no recompile, inheritance | all as designed |
| `x3/load2.jl` | the `return_type` fold through plain inference across an image; redefinition | edge to a `:facts_plain_return_type` CodeInstance survives, valid; values equal plain; redefinition followed |
| `x4/app.jl` | a trimmed binary with a facts module | `trim == 0`, module flag `1` at run time; genuine run-time dispatch is unavailable in trimmed binaries even for plain methods, so the effect is reasoned (§2.3) |

## 5. Gaps against `design.md` §6 and the plan

| Claimed | State |
|---|---|
| `--compile-by-facts=no\|all\|traits` as a switch | An environment variable (`JULIA_COMPILE_BY_FACTS`) plus a system-image flag (`FACTS_IMAGE`); `traits` is what modules declare. No `jl_options` entry. Fine, but §6 should say so. |
| The mode in the package-image cache flags (plan §4) | Not done; `facts.jl` says "use a depot of its own". Images of `all` and plain sessions mix in one depot. The test bed only. |
| Base's tests in facts mode, every difference listed (plan §2.4) | Partial: strings ran; core did not finish (now addressed by `Vararg` facts); the rest did not run. |
| (B) "a method flag set by `@trait_module` on its workers" (§6 table) | Built as a module option with per-method boundaries, as plan §6b describes. design.md §6's table is out of date. |
| "Under part C, a run-time site in facts-compiled code runs facts-compiled code" (rule 1) | Only through codegen's call sites (§2.4). |
| `Dynamic`: "direct calls that inline, then a dynamic fallback, the result asserted to the declared type" (§4.5) | Built; wrong code at a known type (§2.1); the result boxed through an `Any` phi (§2.5); the first four candidates only (`MAX_FACT_SPLITS`), unstated; speed depends on compile order (§2.6). |
| "`--trim` implies `no`" (§6) | Build side only (§2.3). |
| The decisive control (order of work, step 2) | Cancelled in session 29 "until (D)"; (D) is done; not run. |
| Pieces 2 and 4 reverted; dead switches removed (§9.3 step 6) | Not done (housekeeping, inert). |
| Rule 1's fold exception "the same exposure plain Julia has" | False (§2.2). |
| `invoke` at abstract signatures | Not mentioned in rule 1; sound (§1). |
| G1's assumptions A4, A5 "which part B removes" (§5) | A4 (no method defined concurrently with compiling trait code) is now Julia's own engine; A5 (the generator) is gone with `checked_call`'s plain call. Agreed. |

Tests: TraitWorld has no package-image test; the acceptance suite has no concrete-`Dynamic` case
(the bug of §2.1 passes it), no `--trim` case, no threads. `inval.jl` S1–S8 were reproduced in
session 29 per the note; I did not re-run them.

## 6. Recommendations, ranked

1. **Fix (D)'s rewrite** (§2.1): the inliner rewrites every `dynamic_call` statement; inference always
   returns a `DynamicSplitInfo`. Add acceptance G1.18 (a constant `Dynamic` with an operation returning
   a `Vector`; a caller specialized at the object's type) and run `verify_dynamic` at concrete argument
   types too. Before any raytrace measurement, and before the demonstrators' numbers are trusted: any
   demonstrator with a constant or locally made `Dynamic` may be running wrong code.
2. **Type the split** (§2.5): `dynamic_call(K, RT, f, x, args...)` returning `RT`; typeassert the
   fallback inside. Then measure the raytrace; today the split allocates per call.
3. **Make the fold rule exact** (§2.2): fold an asserted Base/Core method only when its CodeInstance
   rests on facts; rewrite rule 1; re-run the BaseBenchmarks tails to see what it costs.
4. **Clear the mode in trimmed images** (§2.3), remove the run-time `jl_options.trim` checks, keep the
   5-second `x4/` build in the acceptance set.
5. **State (C)'s coverage** (§2.4) in design.md, and give `_apply_iterate` and `invoke` owner-aware
   twins emitted under `in_facts_code`.
6. **State the order dependence of the split** (§2.6) in §4.5 with the measured costs, or add an edge
   to the candidate list.
7. **Delete piece 5's foreign half** (§3) and `facts_eval_refused`; merge the two split
   implementations; normalize the facts meta in lowering.
8. **Add a package-image test to TraitWorld** (the `x3/` scripts are templates), and run the decisive
   control now that (D) exists; everything in design.md §8 predates B–D. Fix the working tree's
   precompile error before anything else runs on it.
