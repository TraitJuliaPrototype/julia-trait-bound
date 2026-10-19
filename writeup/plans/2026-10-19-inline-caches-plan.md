# Caches at dynamic call sites (plan, 2026-10-19; revised after review the same day)

The user (2026-10-19): "Is there a principled unifying thing that binds (c) and this together and that could be tackled in a more principled manner?" Here "this" is the cache at the `Dynamic` split's fallback.

The first version proposed world-checked polymorphic inline caches as one mechanism for three problems. A Fable review (`../reviews/2026-10-19-inline-caches-review.md`) and the measurements of the same day revised that:
- The mechanism is sound for the two problems at run-time sites.
- The third (untyped trait calls) would need a custom-dispatch hook in the runtime, a separate decision.
- The facts tails were a lookup cost, now fixed in Julia's own per-site cache (stage 1, below).

## 1. The diagnosis, measured

**Stage 0** (`experiments/factscompiler/ic/`): a dynamic call to an ordinary method costs the same plain and under facts, 13–17 ns. The facts mode's dispatch uses Julia's own lookup and per-site cache (`call_cache`), so it adds nothing there.

**The tails** (containers of `Any`, 17–126×) are monomorphic or bimorphic sites: `anys` holds `Int` and `String`. They dispatch to methods whose cache entry is not a leaf signature, such as Base's `push!(a::Vector{Any}, @nospecialize x)` and `setindex!(A::Array{Any}, @nospecialize(x), i::Int)`. Julia's `call_cache` holds leaf signatures only, so each such call did a full method-cache lookup.

**The direct check:** with the fix off, `push!(d, pop!(d))` on such a vector takes 61.7 ns. 769 of about 856 profile samples are in dispatch, all of them lookup:
- `lookup_arg_type_tuple`, hashing the arguments: 362;
- `jl_typemap_assoc_exact`, the method-cache search: about 480.

There is no frame of normalization or of `jl_compile_method_internal_owner`.

## 2. Built: stage 1, exact-type entries in `call_cache` (`gf.c`, `call_cache_exact`)

When a call's cache entry is not a leaf signature, the site gets an entry for the exact argument types, mapping to the same method instance. It is matched by exact types only, and valid from the cache entry's first world up to the latest world at insertion.

Results:
- `push!(d, pop!(d))`: 61.7 → 12.9 ns.
- The BaseBenchmarks `pop!` case: 276 → 14 ns.
- The quick subset under `all`: geomean 0.93 against the morning, `collection` 0.60. Plain is unchanged (0.99).
- Acceptance G1.22: a cached site through a redefinition keeps the caller's world.

This is the review's recommended form: a change to Julia's existing per-site cache, general for Julia, not a new mechanism.

## 3. Next, in order

1. **Entries with an open `max_world`, as Julia's own cache keeps them.** Today a stage-1 entry, like step 1's `cfunction` thunk (`jl_get_abi_converter_caller_world`), is capped at the latest world at the lookup. After any method definition, every cached site misses once and looks up again. That is sound, but a cost per world change that Julia's cache does not pay; programs that define methods while running pay it at every hot site.
   - The sound, simpler form: the entry refers to the typemap entry and the CodeInstance, whose `max_world` Julia lowers on invalidation (`invalidate_mt_cache`). A hit compares the world with both ranges.
   - The same applies to step 1's thunk.
2. **The facts owner's per-call normalization** (review §2). `jl_compile_method_internal_owner` returns the wider instance's CodeInstance for a non-default owner without keeping anything on the narrow instance, so a call that arrives with a narrow instance (an `invoke` naming a specialization, the first dispatch of a signature) normalizes again on every call. It is not what the measured tails paid (§1), but it is a latent cost per call.
   - Fix: a memo from the narrow instance to the wider one.
   - Copying the CodeInstance onto the narrow instance, as the plain owner does, needs an answer first: invalidation lowers the original's `max_world`, not the copy's.
3. **Profile the remaining tails before building more.** After stage 1, `filter!` on `Vector{Any}` takes 35 ns per element under `all`: lookup about 15%, the call through the CodeInstance about 18%, the GC. Then:
   - `Dict` iteration on `Any` (7 → 115 ns);
   - the `sumrange_view` family, an inlining question.

   Try the size and associativity of `call_cache` first (`N_CALL_CACHE`, `options.h`), a two-line experiment.
4. **The `Dynamic` split beyond four implementations: the simpler options first,** neither needing codegen:
   - raise `MAX_FACT_SPLITS` for `dynamic_call` only (its candidates are registered without edges, so a longer split costs code size, not validity);
   - or put a per-site table of `(type, :caller_world pointer)` at the fallback, with concrete arguments (about 5 + 4.5 ns against about 20 now).

   No demonstrator has five implementations yet; this waits for one.
5. **A codegen-emitted cache with direct calls (old stage 2):** only if the profiles show lookup, not the ABI or the callee, dominating. At a run-time site the arguments are boxed and the result is `Any`, so the realistic gain is 3–8 ns per call: the boxed call through a pointer measured 12 ns.
6. **Untyped trait calls (old stage 3):** not an instance of a cache of dispatch results. It needs a hook by which a package substitutes the target of a call for a type, with its own acceptance checks. Today's design stays: (c) at about 25–29 ns, and an entry method of its own for types compiled ahead (about 14 ns, plain Julia 15–17). A hook would buy a few nanoseconds: a separate decision, not planned.

## 4. Precedents, corrected

- **The polymorphic inline caches of Self** (Hölzle, Chambers and Ungar, 1991) **and the inline caches of Smalltalk-80** (Deutsch and Schiffman, 1984). Their large reported gains came mostly from type feedback feeding inlining (Hölzle and Ungar, 1994), which a cache alone does not give.
- **V8 and JavaScriptCore:** monomorphic, polymorphic and megamorphic states. V8's megamorphic path, a global hashed stub cache, is the design of Julia's `call_cache`.
- **HotSpot:** compiled inline caches are monomorphic or megamorphic (vtable and itable stubs). Polymorphism is handled by profile-guided inlining with guards.
- **CPython's specializing adaptive interpreter** (PEP 659): a per-site cache checked against a version tag at every execution, without deoptimization. It is the closest precedent. Its version tags are per type, not one global counter, which is §3.1's point about capped ranges.
- **Julia's own `call_cache` and the `cfunction` thunk:** the mechanisms this work extends. Julia's cache entries already carry world ranges. What is new is keying by the caller's world (step 1), and exact-type entries for non-leaf signatures (stage 1).

## 5. What it does not do

- It does not compile less: compiling per type is a separate matter (step 4, entries compiled ahead).
- It does not inline at run-time sites. Plain Julia's advantage on the tails (`push!` at 1.7 ns) is inlining at abstract signatures, which a cache cannot reach. The rest is the facts rule's price, which the user's rule accepts where traits recover it.
