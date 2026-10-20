# Review: what follows the split (E-145), 2026-10-21

A fresh-eyes review (Fable, the critic agent) of [the plan](../plans/2026-10-21-what-follows-the-split.md) in its first version (proposal: the split's "default case" plus `table_call`, composed in TraitWorld with `known_type`) and of [E-145](../../experiments/fallback/README.md). The reviewer read code and logs and ran nothing. Its report follows as given. What was done with each finding is in the last section.

---

Verdict: the direction (keep the split, make the fallback a constant-cost table of world-checked pointers) is sound and the data support it. But the plan as written has one design conflict with the facts rule, composes the pieces in a way that re-derives the compiler's own knowledge in library code, and the README/plan overstate several numbers. Findings by severity. Verified = read in code/logs; reasoning = marked.

### 1. The split's "default case" conflicts with the facts rule, and its condition is misstated (verified)

Plan §4.2(a) infers `f` at `x`'s declared type (`Any` for `getfield(d, :t)`) and emits it as the last branch. `Tuple{_DynOp{X,F}, Any}` is not a fact signature; under the facts mode `find_method_matches` returns `FACTS_ABSTRACT_SITE` and no matches (`writeup/reference/compiler.md` §1.3; `facts.jl` `abstract_split_call` calls plain `abstract_call`, which goes through that gate). Trait modules are facts methods, so the default case would never be emitted where it matters, or would need an ad-hoc bypass. Two principled resolutions: (i) state the default case as an `invoke` at the declared signature, the sixth form of fact (§1.2 "Not gated"), exactly as `@dynamic_of` already does with `invoke(Dynamic{X}, Tuple{Val{:checked}, Any}, …)`; or (ii) make the fallback the table call, which is a run-time site (dispatch in the caller's world, no edge) and needs no new fact. I recommend (ii), see 2.

The condition "one method covers that type (no other method intersects it)" is wrong as stated: `_DynOp` has a vararg method `(op, t, args...)` that intersects every arity. What Julia requires is a single fully-covering match after `ml_matches` prunes less-specific fully-covering ones (`src/gf.c` around line 5615, `found_minmax`), no ambiguity. Say that, or the implementation will never fire for `_DynOp`. Also `SplitCallInfo` must carry both infos (narrowed and default) with both edge sets; `compute_inlining_cases`' filter to dispatch tuples when `!handled_all_cases` must be threaded correctly.

### 2. Composing through `known_type` in five library sites is the workaround smell (reasoning)

`known_type` is documented as the library's `__builtin_constant_p`. Using it inside `_DynOp`, `_DynField`, `_DynFieldSet`, `_ConformsTo` and `_store!` to re-decide what the compiler just decided (candidate branch vs. remainder) round-trips the compiler's knowledge through library code, and the plan's own risk ("both paths must compute the same result") is the cost of that duplication. The compiler knows `f`, the inferred argument types and `RT` at the split site, which is the table's key. Let `split_call` end in the table itself (a flag or the default when `x` is not concrete); keep `table_call` as a separate primitive only because `untyped.jl` can use it. This also honours the user's "move to the compiler directly" and keeps facts §9 true ("the last branch is a run-time site").

### 3. The table's shape: commit to the principled form or name the interim (verified + reasoning)

The plan's `table_call` makes `:caller_world` pointers per (signature, type) through generated pointer-makers (e145c's `cw_ptr`). That is three compilations per entry (the maker's specialization, the cfunction wrapper, the target): the measured 8 ms. Raw pointers are not relocatable, hence the session stamp; and each call is probe + thunk + converter + target (two to three indirect calls). The project's own principle (§3: "every cache that skips a dispatch holds world ranges and is checked against the caller's world") points to the shape §3.2 already has: a runtime table keyed by the object's type whose entries are (fptr, min_world, max_world), checked at the probe, never serialized, reached from a per-site slot that starts empty (as `emit_abi_call`'s `cfuncdata` slot 1 does). One indirect call, no stamp, no wrapper method per type. If the Julia-level build is kept as the first step, the plan must (a) make compiling the pointers ahead per declared implementation part of the design (lowering §15.1 already does this for the untyped table's pattern methods), not a "risk to revisit": 8 ms × signatures × types in every fresh session is a startup cost of the kind the project exists to remove (TraitTables: tens of column types × operations); (b) say where the stamp is checked (per call, as `untyped.jl` does, or at image activation through the §5.1 hook); (c) note C-3: thunk entries are capped at the latest world (`runtime_ccall.cpp:424`), so after any method definition every pointer in every table misses once, taking `cfun_lock` and a lookup. In a session that evals between loops this is 64 × k lookups per world bump; not measured. (d) Reconcile explicitly with `design/alternatives.md` ("pointer tables, rejected (s22) for world age, serialization and races"): this proposal is a pointer table, and each objection must be answered by name (caller-world thunks or world-ranged entries; never serialized or stamped; copy-on-write).

### 4. Measurement: sound in method, overstated in places (verified against the logs)

- "3× to 6× slower than any table": true in cache; on 131072 values `tw`/`s4+tab` is 2.3× (62.7/27.1) to 2.4× (84.2/35.3). "7 to 20 ns" for the table is in-cache only; large data is 27–36 ns.
- "the same at 8 and at 64 types, in any order" (plan §3): `tab` alone is 21.1 → 35.3 ns at large N (1.7×). Cyclic 64 is 17 ns against uniform 64's 35: the indirect call's misprediction, not the probe, dominates on random many-type data. The README's branch-predictor caveat covers splits only; it applies to the indirect call too, and no table design removes it.
- "`s4+dyn` within 15 % of `tw` in every row": 18.6 %, 16.8 %, 20.2 % at large N (uniform 8, uniform 16, skewed). Minor.
- "hot+wit 1.0× to 1.8× on large data": it is 0.8× to 1.8×; it is slower than `s4+wit` at uniform 16 (25.0 vs 20.5) and phases (18.2 vs 17.4), not only at uniform 64. The honest conclusion is stronger than the README's: a split over random types costs on large data, so recompiling with observed types pays only for skewed mixes.
- "a heavier body loses inlining at 16 types" is an artifact of emulating the split as an `@inline` Julia function the inliner refuses; the compiler's split is built into the caller's IR by `ir_inline_unionsplit!`, with each case's callee judged on its own. The longer split's rejection rests on code size and compile time only; say so. Note also that for `area` the 64-way `sall` beats the table in every mix (21 vs 35 ns at large N).
- `s4+tab` (e145c `SigTable`) has no session check; the `wit` rows do. The "equal on data in the cache" comparison is biased toward the table by one load and compare.
- Buried finding worth surfacing: `collect(DynamicItems{S}(v))` at 72 ns per element (r1, "make") is the conformance check's fallback; the table fixes it, and it is the stronger demonstrator-relevant number.
- Not measured: results that are not isbits, operations with arguments, field writes, the cost after a world bump, and the as-built TraitWorld path (plan step 7 rightly requires it).

### 5. "The type is the index" (reasoning)

Sound. The precedent is C++ and JVM vtables (reached through the object's header) and V8's megamorphic stub cache (a global table keyed by map and name), not Rust/Swift/Go, which carry a witness because their values need not be boxed; the plan's §2 table files C++/JVM under the witness column. The measured 1.5× at large N is the classic dependent-load cost of header-based dispatch against fat pointers. Deferring the carried witness is right; the plan should name the precedents correctly. Per-signature vs per-trait: per-signature specializes on the site's argument types (Julia's way) but multiplies tables and first-use cost by distinct argument signatures and gives nothing to CSE across operations on one value; a per-trait vtable keyed by declared signatures amortizes `typeof → table` across operations. Worth one sentence of justification, not a change.

### 6. Missing from the plan (verified where cited)

- `Self` results are not split today at all: `trait.jl:325–335` emits `f(opened(dyn), …)` then `_dyn_like`, which opens again (`entry.jl:937`): two dynamic calls. The plan's "every `Dynamic` operation then costs one probe" is false for them; add them (RT = `Any`, the result wrapped).
- Operations with keywords: the `Dynamic` methods generated at `trait.jl:325–345` are positional only; state the scope.
- The result ABI: a rule is needed (RT concrete isbits → by value; `Nothing` → void; union or abstract → `Any` and asserted after). Likewise arguments.
- Non-singleton `f`: a non-constant callable in `Expr(:cfunction)` takes the closure trampoline (`codegen.cpp:8036`, refused on AArch64). Pass `f` boxed as the first pointer argument, or restrict to singletons.
- `--trim`: a miss cannot compile (`jl_errorf("cfunction not available")`); tables must be filled at build time for declared implementations and the miss path made an error `verify_main` reports.
- Images: a table embedded as a constant per compiled site is serialized per image, so "one table per signature" becomes "per signature per image" unless merged at activation.
- Threads: compile the pointer outside the table lock, re-check, insert.
- Two table mechanisms (`untyped.jl`'s `UTable` and `table_call`) with the same shape side by side; the plan should at least show `UTable` is expressible as `table_call`, else `table_call` is too narrow.

---

## What was done (2026-10-21)

| Finding | Done |
|---|---|
| 1, 2 | Adopted (ii). Before the review returned, the same conflict had been found while reading `facts.jl`. The plan's revision 2 drops the default case and the `known_type` composition: the inliner emits the table call itself as the split's last branch (julia-1.13 `split-table`). TraitWorld is unchanged. |
| 3 | Kept the Julia-level pointers as the first step and named it so in the plan (§4.5): (a) compiling the pointers ahead per declared implementation is part of the design, built after the first measurement; (b) the stamp is checked per call by the probe; (c) C-3's miss after each method definition is recorded; (d) the s22 objections are answered by name (plan §4.3). The world-ranged runtime table of specialized entry points (one indirect call, nothing serialized) is the design's direction in the plan's §4.5, a later step. |
| 4 | README and plan corrected: the in-cache and large-data ranges given separately; the misprediction of the indirect call named; the longer split's rejection resting on code size and compile time; `hot+wit` 0.8× to 1.8×; the missing session check of `s4+tab` noted; the 72 ns conformance fallback surfaced. |
| 5 | The precedents corrected (C++, the JVM, V8's megamorphic cache for a key in the object's header; Rust, Swift, Go for a carried witness); one sentence on per-signature tables. |
| 6 | `f` passed boxed as the pointer's first argument (built). The result and argument rule written (plan §4.4). `--trim`: no table in a trimmed program (built); filling tables ahead is part of (3a). `Self` results, keyword operations, the per-image tables and `UTable` as a table call: listed in the plan's scope (§4.6) as not done. |
