# Strict mode: defining a winning pirate is an error

Exploration of 2026-10-17 (session 25). The user: "I want to keep the option open to have strict mode, so trait code is never invalidated. If it rarely happens anyway it's cheap in terms of user friction but powerful as a guarantee." And, correcting my first reading: "I would love a mode that makes defining a winning pirate an error. If pirates never win then we never error."

My first draft assessed a different mode, in which trait code raises at the call where an outside pirate would be selected (the views design). It is summarized in §5, with what a hostile review found in it. That mode is not what the user wants, and it is not pursued.

## 1. The mode

**Rule (strict mode).** A method definition is refused, with an error, if both:
1. **The new method would win** at a concrete signature `s` where valid trait-world code holds a fact. That is, Julia would invalidate that code because of the definition. "Win" includes:
   - being selected at `s`;
   - making the call at `s` ambiguous;
   - replacing the method selected there.
2. **The method is a pirate** (rule 3): its package does not own, in every signature the method applies to, the function or one of the types. An abstract type counts, so `Base.length(::AT)` by AT's owner is no pirate even where it wins at another package's subtype. A package extension counts as its parent.
3. **Its package is not a declared delegate** of an owner of `s` (§3).

By Lemma O this is the same as "not a stakeholder of `s`" for every method that is no pirate. Testing ownership of the *method* rather than of `s` also gives the check its fast path: owned methods, which are nearly all methods, need no walk.

**The scope:**
- **Every definition counts:** at the prompt, by `include`, and a package image's methods at load.
- **Trait-world code** is everything compiled under the facts policy (owner `FactsOwner`), plus the entries' native code, whose facts are dispatch facts at the workers' signatures.
- **Stakeholders' definitions are followed as today.** The owner of a type redefining its own method recompiles the trait code, as plain Julia recompiles.
- **Pirates that win nowhere in trait-world code are accepted.** They change only plain code.

**What it guarantees** (with Theorem 2 of the facts design):
- **Trait-world code is never invalidated by a pirate.**
  - By Lemma O, a non-pirate that applies at a concrete `s` is a stakeholder of `s`. So, with this mode, the only definitions that invalidate trait code are its stakeholders'.
  - In a session, those are edits to packages the code depends on, or to the session's own types.
- **G1 still holds.** A refused method does not exist, for plain Julia either. The trait code computes what plain Julia computes in the world that has no such method.
- **Load order matters only for who gets the error.**
  - A pirate defined *after* trait code that it would change is refused.
  - A pirate defined *before* the trait code is compiled is followed, as in plain Julia. The code compiled later holds a fact selecting it, and that fact can never be broken by a pirate afterwards, since a later winning definition by a non-stakeholder is refused too.
  - For the "before" case, an optional symmetric check makes a fact that selects a pirate an error at compile time (§4).
- **If pirates never win, it never errors.**
  - Session 24's `g2all` loaded twelve packages after both demonstrators had run, interleaved with work: CSV, DataFrames, CairoMakie, a package with 100 types and 20 redefinitions, a Base pirate, OffsetArrays, StatsBase, Unitful, IntervalArithmetic, Distributions, Interpolations and StaticArrays.
  - Not one trait-world CodeInstance was invalidated. So strict mode would have refused nothing.
  - E2 found no concrete fact of the demonstrators' code at which a pirate from that stack wins.

**What it costs:**
- **The refused package does not get its method,** also for its plain users. That is the point of the mode, and why it is off by default.
- **A check at every method definition:** the facts the new method would break. It is cheap when exact, because Julia computes the same set already (§2).
- **Nothing at run time.** No cache owner per mode, no checked calls, no change to compiled code. Code compiled with the mode on or off is the same code.

## 2. How to implement it

**The exact check is Julia's own invalidation set, asked for before the method becomes visible.**
- `jl_method_table_insert` computes it: the specializations whose dispatch the new method replaces, and the backedges that the replacement breaks (`gf.c`, `_invalidate_dispatch_backedges`, `invalidate_missing_backedges`).
- **Wanted from Julia:** a read-only query "which CodeInstances would this definition invalidate", callable from the definition hook (piece 1) before activation. It is the same walk without the stores. It is useful upstream too: SnoopCompile-style tools could ask before loading.
- The hook then filters that set to trait-world code and the non-stakeholder case, and throws.
- **For a package image,** the image hook (piece 1, implemented in the patched build) receives all its new methods before `jl_activate_methods`. A refused method stays inactive, and the load reports an error naming the method and the trait code.

**A prototype without the new query** (TraitWorld, patched build):
- **Pre-check in the definition hook,** in Julia:
  - for each existing method of the function that the new signature intersects and that is not more specific than the new method;
  - for each of its specializations, and each backedge of those whose caller is trait-world code;
  - take the concrete signature `s` of the edge, and ask whether the new method applies at `s` and is more specific than the current winner there, or ambiguous with it.
  - Also check the method table's backedges for calls that had no method (a gap filled by a pirate).
- **Safety net after the definition:** Julia's invalidation log (`jl_debug_method_invalidation`) shows what was actually invalidated. A trait-world CodeInstance invalidated by a non-stakeholder means the pre-check missed it. The prototype then deletes the method, raises, and records the miss. That costs one recompile, and measures how good the pre-check is.
- **Attribution:**
  - `Method.module` (its root module), with extensions mapped to their parent (`Base.EXT_PRIMED`).
  - Exact attribution of the loading package (`@eval Base …` from a package) needs piece 1's loading context.

## 2a. The prototype (session 25)

TraitWorld main 7b328a5 (`src/strict.jl`), on the patched 1.13.2 build. Switched on with `JULIA_TW_STRICT=1` or `TraitWorld.strict!()`.

**What it does:**
- **Before a definition** (piece 1's hook):
  - an owned method (rule 3) passes at once;
  - for a pirate, the backedges of the specializations it could take over are walked, together with the method table's backedges for calls that found no method;
  - the definition is refused (`PirateError`) where it would win at a fact of valid trait-world code.
- **After the definition:** Julia's invalidation log is the safety net. A trait-world CodeInstance invalidated by a pirate is a miss of the check before; the method is deleted again and the miss is recorded.
- **At an image's load:** the image hook leaves refused methods inactive, and the load reports them.

**Tests** (`test/strict.jl`, 32 checks, all pass):
- refused:
  - a winning pirate of Base (`abs2(::Float64)`);
  - a pirate that fills a gap trait code ran into;
  - a later redefinition by a pirate that was defined before the trait code;
  - a session's definition at the prompt of a package's function for Base types;
- accepted:
  - pirates that win nowhere in trait code;
  - the function's owner (`@eval SU …`, as Revise attributes edits);
  - an owner's method on its abstract type, at another package's subtype;
  - a declared delegate;
- with the mode off, the pirate is followed;
- the safety net never fired: 0 misses.

**`g2all` with strict mode on** (`experiments/facts/g2strict.jl`):
- **The load sequence:** both demonstrators work, then twelve packages load one at a time with work after each.
- **Refused: nothing. Safety-net misses: 0.** No trait-world code was lost, and work stayed at 9–15 ms, as with the mode off.

**The cost at load** (CSV, DataFrames, CairoMakie, after the demonstrators' work):

| | load |
|---|---|
| strict mode off | 4.14 s |
| strict mode on | 4.68 s |

- In the "on" run, 65,318 methods were checked, in 0.16 s.
- 837 of them are pirates by the letter, and walking them took 0.49 s. None was refused.
- The first version checked ownership without the fast path and without memoized owners: 9–11 s.

**The exact check** (piece 14) would replace the walk by Julia's own invalidation set, and the safety net with it.

## 2b. The intended design: compiled trait code never invalidated (deferred)

The user (session 25): "What would we need for strict mode that never invalidates compiled trait code?" And, after the answer below: "Record what you gave above as the intended design for strict mode. Defer concrete work on it for now."

**The guarantee.** In strict mode, compiled trait-world code, in the session and in package images, is invalidated only by edits to its own dependencies. Every other event that would invalidate it is an error at its source. Nothing is checked at run time: all the checks happen when a method is defined or deleted, or an image is loaded.

**What the prototype (§2a) already gives:** a pirate defined after the trait code that it would change is refused.

**What remains, and what each needs:**

| # | Source of invalidation | What is needed | Where |
|---|---|---|---|
| 1 | **A pirate loaded before a trait package's image.** The image's facts were compiled without it; image validation rejects the code, which is recompiled following the pirate. The refusal cannot act, since the pirate came first. (Code compiled *in* a session where the pirate already exists follows it, and can never be invalidated by it afterwards.) | A hook in image validation that reports why a CodeInstance is rejected: the edge, and the method that now wins there. Strict mode then reports an error naming the pirate and the trait package, instead of recompiling. | Julia, small: image validation is Julia code in 1.13 (`Compiler/src/reinfer.jl`); **piece 15** |
| 2 | **Dependence through native code.** Trait code holds edges to native code: `return_type` folds from native inference (`_NativeRT`), and the machinery's exempt functions. A pirate winning inside that native code invalidates the trait code through it. The prototype checks direct callers only, so it misses this; the safety net catches it after the fact. | A transitive check: follow callers upwards to trait-world code. **Piece 14** (the exact "would invalidate" query) gives it, since Julia's invalidation walk is transitive; without it, TraitWorld walks the callers itself. | Julia piece 14, or TraitWorld |
| 2′ | **A second trait library extending the machinery's registries** (`param`, `implementation`). Measured: 0 of 7461 instances lost (`twolibs.jl`), but not guaranteed. | `twolibs` as an acceptance check. Where it fails, registry calls made concrete facts. | TraitWorld |
| 3 | **Package extensions loaded later.** An extension counts as its parent, so it passes as a stakeholder. But a method of it at a signature that contains none of its triggers' types changes code that existed before the trigger loaded. | A strict-mode rule: refuse an extension's winning method at a fact whose signature contains no type of its triggers. | TraitWorld |
| 4 | **Method deletion** (`Base.delete_method`) does not go through the definition hook. | A deletion hook (an extension of piece 1), and refusal of deletions by anyone but the method's owner. | Julia, small: **piece 1′** |
| 5 | **Edits** (REPL, Revise, redefined constants) to packages the code depends on, or to the session's types. | Nothing: kept as the one stated exception. An edit is meant to change what the code computes, and plain Julia recompiles too. Freezing packages once trait code is compiled against them would break Revise. | — |

**Expected friction.**
- None of these sources has been observed. In `g2all` no trait-world code was invalidated even with the mode off.
- So this hardens a guarantee rather than fixing a seen problem.

**Status: deferred.** Recorded as the intended design. Pieces 1′, 14 and 15 are on the Julia list for when it is taken up.

## 3. Split-core packages

**A stakeholder of `s` owns the function or a type in `s`.**
- StaticArrays defines `Base.size(::SArray)`, but StaticArraysCore owns `SArray`. By the letter, that method is a pirate.
- It is refused only if it would *win at an existing trait-world fact*: trait code compiled with `SArray` values while StaticArrays was not loaded. That is rare, since the values come from StaticArrays.
- When it happens, the fix is a delegate: a declaration that StaticArrays implements StaticArraysCore, so it counts as a stakeholder for StaticArraysCore's types.
- **Delegates are declared by:**
  - a curated list in TraitWorld (StaticArrays, StatsBase for StatsAPI, Makie for MakieCore, …);
  - or the application: `TraitWorld.delegate!(StaticArraysCore => StaticArrays)`.
- This is the one piece of the old wrapper design that stays, as data.

## 4. Optional: the symmetric check

**What it closes.** Strict mode leaves one asymmetry: a pirate defined before the trait code is compiled is followed.
- The symmetric check makes the policy refuse to compile a fact that selects a pirate (a non-stakeholder's method that wins at `s`).
- The trait call then raises at its first compilation, naming the pirate.

**What it gives:** results that do not depend on load order, at the price of an error in the "before" order where the plain session would run.

**Its friction:** split-core packages again, now also in the common order (StaticArrays loaded before the trait code). Delegates (§3) cover them.

**Recommendation:**
- Offer it as a lint, not as the session default. `verify_main` reports such facts at build, which is where they matter most (`aot-under-facts.md` §5).
- In a session, strict mode alone gives what the user asked for: trait code never invalidated by a pirate.

## 5. The mode I first assessed (not pursued)

My first draft read "strict mode" as the views design's: a call in trait code that would select a pirate from outside its dependencies raises `HiddenMethodError`. A hostile review (session 25) found it much costlier:
- **A strict cache.** To be sound, everything reached through a run-time site must run under the policy with the same check: a second copy of the Base code used there, a lookup and `invoke` per run-time call (about 0.5 µs), and trampolines at tasks, finalizers, `invokelatest` and callbacks.
- **A cache owner per mode,** since the compiled code differs.
- **No reduction in invalidation.** A winning pirate invalidates the same code; it recompiles to raise instead of to follow.
- **Friction from split-core packages at every call from Base's generic code,** not only at definition.

What survives from it:
- the build-time lint (§4);
- the observation that **"never invalidated" in the literal sense needs either refusal (this mode) or a skip predicate** (giving up rule P). The skip predicate stays rejected.

## 6. What it needs from Julia, and what is decided

- **Piece 1** (the definition hook, which may refuse; with the image hook), implemented in the patched build.
- **New, small:** the read-only "would invalidate" query (piece 14), for an exact check.
- **No invalidation predicate (piece 2), no dispatch check (piece 6), no second cache.**

**Decided (session 25):**
- Strict mode is this refusal mode: optional, off by default, chosen per session or application.
- The views/`HiddenMethodError` mode is not pursued.
- The symmetric check is a lint, available in `verify_main`.
- Delegates are kept as data, for split-core packages.
