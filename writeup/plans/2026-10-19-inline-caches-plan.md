# World-checked inline caches at dynamic call sites (plan, 2026-10-19)

The user (2026-10-19): "Is there a principled unifying thing that binds (c) and this together and that could be tackled in a more principled manner?" Here "this" is the cache at the `Dynamic` split's fallback (step 1's remainder). The answer proposed: **world-checked polymorphic inline caches at dynamic call sites**, in Julia's runtime and codegen, whose entries carry a code pointer and an environment.

## 1. The problem: one problem in three places

A call whose target depends on the run-time type of a value, over an open set of types, appears in three places.

1. **The facts mode's run-time sites.** A call that is not at a fact signature dispatches at run time and records no edge, with its result typed `Any`. Plain Julia's type-unstable code pays this under `all`. These are the tails of BaseBenchmarks:
   - containers of `Any`, 17–126×;
   - sorts of mixed element types, up to 24×;
   - `parse_json`, 9×;
   - `raytrace`, 4×.
2. **The `Dynamic` split's fallback.** An operation on a `Dynamic` value is split over at most four registered implementations (part D). Every other type pays a dynamic call: the fifth implementation and beyond, and any registered after compilation.
3. **Untyped calls into trait code**, (c). Today they go through a table per entry position plus a caller-world pointer: about 25–29 ns, against 15–17 ns for plain Julia's dynamic call. Types compiled ahead have their own entry method (14 ns).

Julia's dynamic dispatch, `jl_apply_generic`, already caches its method lookup:
- a small hashed cache per call site, keyed by the return address;
- the global method cache, keyed by type.

What it lacks:
- a direct call with the argument types known at the site;
- a result that is not boxed when the site knows its type;
- for the facts mode, the same fast path at all (to be measured: dispatch to a `@nospecialize` method from facts code costs about 30 ns more than to a specialized one).

## 2. The mechanism

- **A cache per dynamic call site,** with a few entries. Each entry holds:
  - the argument types it was filled for;
  - a code pointer;
  - an environment word;
  - the range of worlds in which the entry holds.
- **A call** compares the argument types and the caller's world with the current entry, then calls the pointer, passing the environment.
- **A miss** dispatches as today, in the caller's world, and adds an entry. The range is where the method match and the CodeInstance both hold, up to the latest world at the lookup, extended on a later miss. This is step 1's rule.
- **States, as in V8 and HotSpot:**
  - monomorphic (one entry);
  - polymorphic (up to N entries, a linear check);
  - megamorphic (the global method cache, as today).
- **The environment word.** It is empty for an ordinary method. For a trait entry reached with a type, the miss handler returns two things:
  - the code compiled once per key;
  - as environment, the type's builder, that is, its offsets.

  This is Swift's opening of a protocol value: shared code, per-type data.

  TraitWorld provides the miss handler for its entries. (c)'s tables, holders and pointer wrappers then become instances of the general mechanism.
- **Semantics.** The cache stores dispatch results; it does not speculate.
  - A hit calls exactly what dispatch would call in that world.
  - A miss is dispatch.
  - No edge is recorded, so under the facts rule nothing is invalidated.
  - Results are identical by construction.
  - There is no guard that can fail permanently, and no cliff: a site that sees many types becomes megamorphic, which is today's cost.

## 3. Precedents

- Self (Hölzle, Chambers and Ungar, 1991: polymorphic inline caches).
- Smalltalk-80 inline caches (Deutsch and Schiffman, 1984).
- V8 and JavaScriptCore (inline caches with monomorphic, polymorphic and megamorphic states).
- HotSpot (inline caches at virtual calls).
- Swift's existential opening (per-type metadata as data, shared code).
- What is new is the world check, which keeps every call in the caller's world. It is step 1's mechanism, already built for `cfunction` pointers (`:caller_world`).

## 4. The stages, each measured before the next

0. **Acceptance and measurement first.**
   - Checks: a cached site in an older world after a redefinition (as G1.20/G1.21); a site that sees a new type after a load; a site that turns megamorphic.
   - Measurements:
     - the quick BaseBenchmarks subset under `all` and plain;
     - micro-benchmarks of a run-time site with one, four and sixteen types;
     - the `Dynamic` raytrace with 2, 4, 8 and 16 types;
     - untyped trait calls.
1. **A runtime-side cache in the facts mode's dynamic dispatch** (`jl_apply_generic_facts`, `src/gf.c`). It is keyed by the call site and the argument types, and holds the facts CodeInstance's entry point with its world range. There is no codegen change, and the arguments stay boxed. It measures how much of the run-time site's cost is the lookup, the first and cheapest gain.
2. **A codegen-emitted cache.**
   - The call site holds its cache data, as a `cfunction` thunk does. The type compare is inline.
   - The call is direct, through an adapter from the site's argument types to the callee's specialized signature. That adapter is step 1's `jl_jit_abi_converter` with the caller-world lookup.
   - A result whose type the site knows is not boxed.
   - This stage measures the remaining gap to a static call.
3. **Trait entries through the cache.** TraitWorld's miss handler supplies the code and environment for a trait entry and a type: per-key code plus the builder. (c)'s tables and pointer wrappers are removed, and the untyped call is one cached call.
4. **The `Dynamic` split's fallback through the cache.** The static split stays at four, for inlining hot types; the cache covers the rest.
5. **Megamorphic policy and memory.** Per-site entry limits; the transition to the global cache; caches belonging to a session (reset on load, as today's tables are); GC rooting of the CodeInstances held (by their MethodInstances' caches, as `cfunction` data assumes).

## 5. What it does not do

- It does not compile less: compiling per type stays a separate matter, handled by step 4 (compiling ahead) and the environment word.
- It does not make type-unstable code inline its callees: inlining needs types at compile time. Only a tiered recompilation would do that, which is out of scope, and was step 2's risk.

## 6. Risks and open questions

- **The gain over Julia's existing per-site lookup cache** is not known: it is what stage 1 measures. An estimate for a call: 15–20 ns down to 3–6 ns in stage 2.
- **Threads.** Entries are appended copy-on-write, and a reader sees an old or a new list (as in step 1).
- **Images.** Caches embedded in code are session data. They carry a session identity and are ignored after a load, as (c)'s tables are.
- **Code size** per call site: small, and only at dynamic sites.
- **Upstream.** Stages 1 and 2 are general Julia improvements, useful without traits. Stage 2 is a codegen change of the size of step 1 or larger.
