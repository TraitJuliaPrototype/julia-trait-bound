# Strict mode: defining a winning pirate is an error

Exploration of 2026-10-17 (session 25). The user: "I want to keep the option open to have strict mode, so trait code is never invalidated. If it rarely happens anyway it's cheap in terms of user friction but powerful as a guarantee." And, correcting my first reading: "I would love a mode that makes defining a winning pirate an error. If pirates never win then we never error."

My first draft assessed a different mode, in which trait code raises at the call where an outside pirate would be selected (the views design). It is summarized in §5, with what a hostile review found in it. That mode is not what the user wants, and it is not pursued.

## 1. The mode

**Rule (strict mode).** A method definition is refused, with an error, if both:
1. **The new method would win** at a concrete signature `s` where valid trait-world code holds a fact. That is, Julia would invalidate that code because of the definition. "Win" includes:
   - being selected at `s`;
   - making the call at `s` ambiguous;
   - replacing the method selected there.
2. **The defining package is not a stakeholder of `s`:** it owns neither the function nor a type in `s`. A package extension counts as its parent, and declared delegates count as the package they implement (§3).

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
