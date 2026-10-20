# What follows the `Dynamic` split: a table by type (E-145)

**Status:** done (2026-10-21, revision 2; julia-1.13 711484a23e, TraitWorld 1c45999), flagged for the user's review (open issues item 38). Step 6 (§5) is later work. Revision 1 (a "default case" of the split, composed in TraitWorld with `known_type`) conflicted with the facts rule; the review of the same day ([`reviews/2026-10-21-what-follows-the-split.md`](../reviews/2026-10-21-what-follows-the-split.md)) found it too, and its findings are answered in §4.

The user (2026-10-21): "I think the rule stands. The old behaviour gets reactivated for compiled_for, as per your suggestion. Then it's E-145. You have a quiet machine and the whole night to figure out what follows a split. […] try to come up with principled thoroughly reasoned proposals, rather than asking me to approve dozens of detailed points. Go ahead and implement things when you reached a satisfactory proposal and flag for later review. Finally the principle of this whole project is: Principled clean solutions that stick to establish best practices and experiences from decades of prior work, adapted to Julia's specifics. No workarounds or hacks."

The measurements are in [`experiments/fallback/README.md`](../../experiments/fallback/README.md) (E-145).

## 1. The question

An operation on a `Dynamic{X}` value, `area(d)`, is `Compiler.split_call(X, RT, f, obj, args…)` ([compiler §4.2](../reference/compiler.md#42-compilersplit_call-the-call-site-split)):
- **The split:** `isa` branches over the first four implementations declared. Each branch is compiled for its type and may be inlined.
- **The last branch:** Julia's dynamic dispatch. Its per-site cache holds four entries and thrashes beyond them. Its result comes back boxed.

What should the last branch be? The options (open issues item 32): the dynamic call (built), a longer split, a per-site cache, a table per trait, a witness carried in the value, or recompiling in the background with the observed types.

## 2. What decades of prior work do

Every mature implementation layers the same three pieces:

| Piece | What it does | Where |
|---|---|---|
| **A guess compiled inline** | a few likely types checked first, each with its code inlined | inline caches (Smalltalk, Self), guarded devirtualization (HotSpot, .NET, LLVM's indirect-call promotion, Go's PGO devirtualization) |
| **A constant-cost path for every other type** | the type selects the code through a table: a load or a probe and an indirect call, whatever the number of implementations and their order | C++'s and the JVM's vtables, reached through the type in the object's header; V8's megamorphic stub cache, keyed by the object's map; Rust's vtables, Swift's witness tables and Go's itabs, carried beside the value |
| **Feedback** (optional) | the types a site actually sees replace the guess, by recompiling | the tiered JITs (HotSpot, .NET's dynamic PGO, V8, JavaScriptCore), CPython 3.11's specialization |

Today we have the first piece only. Behind it sits a path whose cost grows with the number of types (the four-entry cache thrashes), allocates (the boxed result), and depends on the order of declarations.

## 3. What the measurements say (E-145)

Per element, one to three flops per operation, on 1000 values (in the cache) and on 131072 values (with a cache miss per boxed object):

- **Today's fallback:** 40 to 90 ns and an allocation per element at 16 to 64 types in the cache, 60 to 100 ns on large data. A table is 3× to 6× faster in the cache and about 2.3× on large data.
- **A table** (the type selects a pointer): 6 to 15 ns in the cache, 16 to 36 ns on large data; no allocation; no order dependence. On random mixes of many types the indirect call's misprediction dominates (cyclic 64 types: 17 ns, uniform 64: 35 ns, on large data). No table removes that, as in every language.
- **Where the table's index comes from:** a probe by the value's type in a table per call signature, or a witness carried in the value. Equal in the cache (the emulated table lacked the session check, one load and compare). On large data of 16 or 64 types the carried witness is up to 1.5× faster: the classic cost of reaching the table through the object's header.
- **A longer split:** the fastest for one multiply (21 ns at 64 types on large data, against 35 for the table). But a loop's code grows to 19 KB at 16 types and 190 KB at 64, and compiling it costs 15 and 41 ms per site. Rejected on code size and compile time. (The emulation's split, an `@inline` function, also stopped inlining a heavier body at 16 types; the compiler's own split builds each case into the caller and would not meet that.)
- **A split over the observed hot types** (what recompiling would produce): 3× faster than the table only for one multiply in the cache, in skewed or phase-changing mixes; 1.4× to 2.1× for a heavier body; 0.8× to 1.8× on large data, where a split over random types costs.
- **The conformance check** of a value of unknown type, `@dynamic_of` (a `Vector{Any}` seen as `Dynamic` items), takes the same fallback: 72 ns per element at 64 types.
- **The first use of a type** at a call signature: about 8 ms (the pointer's maker, its thunk, the target compiled).

## 4. The design

**Keep the split in front. Replace its last branch by a table of the call's targets, keyed by the value's type. The compiler emits it.**

### 4.1 The last branch

Where a split is open (the value's type may be outside the candidates), the inliner emits as its last branch, instead of the dynamic call (`ir_inline_unionsplit!`, `split_table_call!` in `Compiler/src/ssair/inlining.jl`):

```julia
T  = Core.typeof(x)
fp = foreigncall(:jl_split_table_ptr, Ptr{Cvoid}, (Any, Any), table, T)     # one probe, or the miss
r  = foreigncall(fp, R, (Any, Any, A...), f, x, args...)                     # typed, through the pointer
```

- **`table`** is the table of the call's signature: the function's type `F`, the other arguments' types `A`, the result type `R`, and whether the calling code is compiled by facts (`SplitTable`, `Compiler/src/facts.jl`). One per signature and session, embedded in the code as a constant. Sites with the same signature share it.
- **`jl_split_table_ptr`** (`src/gf.c`) probes the table by the address of `T` (open addressing). A miss calls Base's `_split_table_miss!` in the caller's world, which makes the pointer and adds it.
- **The pointer** is a `:caller_world` `cfunction` ([compiler §3.1](../reference/compiler.md#31-the-cfunction-calling-convention-caller_world)) of `Base._SplitTarget{F,T,R}()`, whose method is `(f::F)(x::T, args...)::R`, with `f` and `x` passed boxed. In code compiled by facts, the target is `_SplitTargetFacts`, whose method is compiled by facts whoever calls it (`Expr(:meta, :facts_always)`). So code compiled by facts reaches code compiled by facts, as its dynamic calls do.
- **The facts rule:** the last branch stays a run-time site. It dispatches in the caller's world and records no edge. No new fact is needed.
- **Nothing in TraitWorld changes.** Every `split_call` gets it: operations, field reads and writes, the conformance check of `@dynamic_of`, BaseTraits' stores.

### 4.2 Adapted to Julia

- **The type is the index.** Every Julia object carries its type in its header, so the table is keyed by it, as C++'s and the JVM's vtables are reached. A `Dynamic` needs no second pointer: its layout stays "the user's object" (decided). Rust, Swift and Go carry a witness because their values need not be boxed.
- **One table per call signature, not per trait.** The pointer's argument and result types are the site's own, so nothing is boxed beyond the value itself; Julia compiles per signature. The price is one table per distinct signature, not one per trait shared by its operations.

### 4.3 The objections to pointer tables (rejected in s22, built in s28 and deleted in s29), answered

- **World age:** each pointer runs in the caller's world, through the thunk's world-checked cache. A redefinition is seen as a dynamic call sees it; the table holds no world and needs no invalidation. The witness tables of s28 ran in the latest world: that was their defect.
- **Serialization:** pointers are never valid across sessions. A table saved in a package image carries another session's stamp; the probe checks the stamp on every call, so the table counts as empty and fills again.
- **Races:** a table's state is replaced on each addition (copy-on-write, published atomically), never mutated. The pointer is made before the update.

### 4.4 Arguments and result

- `f` and `x` pass boxed (`Any`). A callable that is not a singleton is boxed per call.
- Another argument passes as its type where that is concrete and not a kind, else boxed.
- The result type is the split's declared result where concrete, else `Any`. The target asserts it (`::R`), so a value of another type raises a `TypeError`, never a conversion. The join is asserted to the declared result as before.
- At most six arguments after the value (`MAX_SPLIT_TABLE_ARGS`, the targets' fixed arities); beyond, the dynamic call.

### 4.5 The interim, and the direction

The pointers are made by Julia code at the first miss, about 8 ms per signature and type (the maker, the thunk, the target). Two consequences:
- **Compiling the pointers ahead per declared implementation** is part of the design, as lowering §15.1 compiles the untyped table's pattern methods ahead. To build after the first measurement.
- **After any method definition** every thunk misses once, since its entries are capped at the latest world (deviation C-3). Not measured.

The direction: a runtime table whose entries are the specialized code's entry points with their world ranges, checked at the probe, never serialized. One indirect call, no thunk, no maker per type. It is the shape of the per-site cache (compiler §3.2), and a change to code generation.

### 4.6 Scope: what this does not change

- The split, its limit (four, Julia's own union-splitting limit), its order (the first four declared), and `split_call`'s meaning.
- The rule of `Compiled` and `Dynamic`, and what `Dynamic` holds.
- **Not covered:**
  - operations whose result is `Self`, which open the value and dispatch twice (`_dyn_like`), not split at all;
  - keyword operations, which have no `Dynamic` method;
  - a program built with `--trim`, which keeps the dynamic call (no code is made at run time);
  - one table per signature per package image, not merged at load;
  - the untyped callers' table (`untyped.jl`), a separate mechanism; whether it can be a split table is a later question.

### 4.7 Not chosen

- **A longer split:** code size and compile time per site.
- **A per-site cache** (a polymorphic inline cache): it thrashes beyond its size (40 ns at 64 types with 8 entries), as Julia's own four-entry cache does today.
- **A witness carried in the value** (Optional): up to 1.5× faster on large mixes of many types, at 8 bytes per value, a lookup per value made from an unknown type, and a new layout for `Dynamic`. To revisit with a real workload in W-17.
- **Recompiling in the background with the observed types** (Optional, compiler §1.6): it pays only for skewed mixes of cheap operations in the cache. To revisit when a demonstrator shows a hot site whose types are outside the declared four.
- **A "default case" of the split, composed in TraitWorld with `known_type`** (revision 1): its call at an abstract type is not a fact, so the facts mode would never emit it in trait code, and the composition re-decided in the library what the compiler knows.

## 5. Building it

| Step | Where | What |
|---|---|---|
| 1 | julia-1.13 (branch `split-table`) | `src/gf.c` (`jl_split_table_ptr`, `jl_split_session`, `jl_set_split_table_miss`); `Compiler/src/facts.jl` (`SplitTable`, `SplitState`, the registry, `split_state_add`); `Compiler/src/ssair/inlining.jl` (`split_fallback_table`, `split_table_call!`, `UnionSplit.table`); `base/splittable.jl` (the targets, `_split_pointer`, `_split_table_miss!`), registered in `Base.__init__` |
| 2 | build | `tw-build.sh`, then the facts image; alone, under the memory guard |
| 3 | tests | a test in julia-1.13's test suite: a split beyond its candidates (a result, no allocation, a redefinition seen, a type declared later, a `MethodError`); TraitWorld's suite, the demonstrators, `run_all.sh` |
| 4 | measure | the `tw` rows of e145b once on the new build (the as-built row against `s4+tab`), the conformance row, the first use of a type |
| 5 | documents | compiler §3.3 and §4.2 (the last branch), facts §9; lowering §13; julia-changes (a new piece); open issues 32 (closed), 35 (P3); the decision log ("mine", flagged); alternatives; evidence (E-145); the registry row; state |
| 6 | later | compiling the pointers ahead (§4.5); the world-ranged runtime table |

## 6. Risks

- **The inliner change:** the last branch is three statements in the fall-through block, with no control flow of their own; a mistake shows as a wrong result or a crash in the tests of step 3.
- **The runtime layout:** `jl_split_table_ptr` reads `SplitTable` and `SplitState` by their Julia layouts. A change to either breaks it; both are declared side by side with a comment.
- **A build of the system image** is needed. A failed build costs time, not correctness.
