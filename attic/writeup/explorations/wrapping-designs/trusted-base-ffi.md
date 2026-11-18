# Wrapping by not wrapping: a trusted base and a values-only boundary

**Approach.** The trait world (TW) wraps nothing. It compiles its own code, plus the code it trusts, as one unit. Trusted code is Core, Base, the stdlibs shipped in the sysimage, TW modules, and admitted packages. Every other method is reached the way an FFI reaches a C function. The TW calls that method's own plain-Julia compiled code through its entry pointer, at a concrete signature, passing only values, and asserts the type of the result. There are no wrapper declarations, delegation lists, doors, handle types, sealing or refusals.

G1 does not depend on any declaration. It rests on one kind of fact the compiler records, "at concrete signature s, dispatch selects r", and on one hook that invalidates code exactly when such a fact stops holding. Trust and admission decide only three things:
- what gets inlined (speed),
- whose definitions can invalidate cached code (G2),
- what is statically closed (G3).

## 1. Rules and hooks

**Notation.** For a world w and a concrete signature s (a dispatch tuple, e.g. `Tuple{typeof(+),Float64,Float64}`), `D_w(s)` is plain Julia's dispatch result: a method, `none` or `ambiguous`.

**R1 (facts).** Compiled TW code depends on the method table only through facts `(s, r)`, where s is concrete and `r = D_w(s)` at the compile world. These facts are the code's edge set `E(c)`. They include:
- MethodError paths (`r = none`),
- folded `applicable`/`hasmethod` queries,
- every decision the TW itself makes. A trait default is an ordinary method, and "T uses the default `length`" is the fact `D(length, T) = default`.

A call site whose argument types are not concrete after union splitting is dispatched at run time and records nothing.

**R2 (trust).** At a fact `(s, r)`:
- **Trusted r:** its body is compiled into the TW code under R1, recursively, and inlining is allowed.
- **Untrusted r:** the site is a *foreign call*. It calls r's native specialization at s through its specialized entry pointer, fetched from r's currently valid native CodeInstance and re-fetched when that instance's world range ends. The result is asserted to the type that native inference predicts for r at s. Nothing inside r is recorded.

*Trusted* means defined in Core, Base, a shipped stdlib, a TW module (any module that declares traits or conformance), or an admitted package.

**R3 (admission).** `@admit P` is one line, written in a TW module (for example a package extension) or in user code. It adds the methods *defined in* package P to the trusted set. It does not add other packages' methods on P's types, or the methods P's code calls in other packages. Admission is a performance declaration; G1 does not depend on it.

**Hooks:**
- **H1 (TW compiler).** An AbstractInterpreter with its own cache owner that implements R1 and R2:
  - it records only concrete facts;
  - abstract sites become run-time dispatch;
  - a foreign call becomes a specsig pointer call with a world check and a typeassert.

  The policy uses the stock compiler-plugin interface. The patched parts are codegen and serialization of external-owner instances, and the foreign-call stub.
- **H2 (exact predicate).** A method definition, deletion or redefinition invalidates a TW CodeInstance c iff it changes `D` at some s with `(s,·) ∈ E(c)`. Package-image validation admits c iff every fact still holds.
  - Because s is concrete, "changes D at s" means either the new method d is applicable to s and wins (or creates an ambiguity), or d replaces or removes r.
  - Facts are indexed by function, like Julia's backedges.
  - The machinery holds no inference edges itself (lesson 8).

**Not needed:** an insertion-refusal hook, sealing, and checked dynamic calls. They become optional strict modes (§4).

## 2. Guarantees and proof sketch

**Assumptions**
- **A1.** Compilation preserves source semantics, given the dispatch facts it relied on. This holds for the native and the TW policy alike, with `@assume_effects` and `@generated` honest, as Julia already requires.
- **A2.** Execution is world-pinned as in plain Julia. An entry call runs at the world current at entry, and run-time dispatch uses that world.
- **A3.** Results that depend on inference itself are outside G1. The main case is `Core.Compiler.return_type`, for example the eltype of an empty `map` or `collect`. Plain Julia does not fix them either: they depend on compile order and inference limits.
- **A4.** Core, Base and the shipped stdlibs are not redefined after startup. This is needed only for G2's classification, not for G1.

**Invariant I.** For every TW CodeInstance c and every world w in c's validity range, every `(s, r) ∈ E(c)` satisfies `D_w(s) = r`.

**Every event preserves I:**
- **Compilation at world w.** H1 records `D_w(s)` for every static decision. By R1 there are no other static decisions, so I holds at creation.
- **Method definition, deletion or redefinition (world w to w+1).** D changes only at signatures where d is applicable or where the removed method was selected. H2 closes the range of every c that has a fact at such an s. For every other c, `D_{w+1}(s) = D_w(s)` holds for all its facts.
- **Package load.** A load is a sequence of definitions (the case above) plus cached instances. H2 admits a cached c only if all its facts hold now. Validity is therefore a predicate on the resulting method table, so load order is irrelevant.
- **Run-time dispatch.** It creates no TW instance and does not change the table.
- **Call through a pointer.** The target is `r = D_w(s)` by I. r's native instance is maintained by plain Julia's own invalidation, and the stub re-fetches the pointer when that instance's world range ends.
- **`eval` during a call.** New definitions belong to later worlds. The running call stays at its world (A2), exactly as in plain Julia.

**G1 (identical or error).** Running c at world w evaluates the same method bodies on the same arguments as plain Julia at world w, or it raises at a foreign-result assertion.

The proof is an induction over execution steps:
- a direct site runs `r = D_w(s)` (by I and A1);
- a run-time site runs `D_w` of the actual types;
- a foreign site runs r's own native code;
- an assertion either passes the value through unchanged or raises.

No declaration enters this argument. **G1 holds for every choice of trusted set: a wrong `@admit` can make code slow, never wrong.** The same reasoning covers lesson 2: when a user redefines a method of its own type, the fact at that signature changes, so the code is invalidated. Lesson 4 is covered too: the owner of T, or of T's supertype, adding `length(::T)` changes `D(length, T)`, so the code recompiles to the new method.

**G2 (stable cache).** Definition d invalidates c only if d changes D at the signature s of one of c's facts. In that case d's module either:
- owns the function in s, or a type occurring in s at any depth, or a supertype of such a type (it is a *stakeholder* of s); or
- is a pirate at s.

c's fact signatures come from three places: TW source, trusted bodies, and the *entry* signatures of foreign calls. None of them lies inside untrusted code. This gives three consequences:
- **(a)** A package that owns nothing in those signatures invalidates c only through a pirate that *wins* dispatch at a concrete signature c uses. Pirates that merely intersect Base signatures, which is the common kind, cost nothing.
- **(b)** Definitions inside untrusted code (Makie internals, extensions, backends) never invalidate c, unless they change dispatch at an exact entry signature c calls. In that case G1 requires the invalidation.
- **(c)** Cached code is reused in every session and load order in which its facts hold.

**G3 (closed for AOT).**
- The methods reachable without passing a foreign or run-time site are the trusted r of the transitive fact closure. This set is finite and listable: it is the edge set.
- Foreign sites form a finite list of concrete signatures. In a closed AOT build, each resolves to one method.
- Run-time sites are listed per site.

G3 is exact for TW and trusted code. The closure of a foreign callee remains plain Julia's trimming problem (the juliac `--trim` verifier).

**G4 (early errors).** The binder knows the concrete s of every foreign site when a key is precompiled. It reports `D(s) = none` at that point (e.g. a wrong-arity Cairo call), and it lints foreign results whose predicted type is not concrete.

## 3. Test cases

**A. Base.** Everything here is trusted.
- **Compute:** `sum`, `sort!`, broadcast and `lu!` on Float64 arrays become concrete facts and compile as in plain Julia. LAPACK goes through `ccall` and libblastrampoline, whose routing is run-time state: loading MKL.jl changes plain Julia and the TW identically.
- **Printing:** `stdout::IO` sites and `show` on `Any` are run-time dispatch. They can reach any package's `show`, exactly as plain Julia does (lesson 9).
- **Cost:** hot paths match plain Julia.
  - The TW compiles its own copies of the Base specializations it uses. A sysimage instance whose edges already are concrete facts could be adopted unchanged.
  - Abstract sites that native Julia resolves by enumerating up to three methods become run-time dispatch, at tens of ns each. These are mostly printing, error and promotion paths.

**B. Cairo.jl.** Cairo is not trusted.
- The plotting library calls `Cairo.move_to(ctx, x, y)` in its source as usual. The compiler emits a foreign call: a fact for `(s, Cairo's method)` and a pointer call into Cairo's native code, about 4 ns plus the `ccall`.
- The `CairoContext` is just a value the TW holds and passes along. There is no handle type and no door, and side effects happen in plain Julia.
- **Cost:** 10⁵ segments add about 0.5 ms. Alternatively, `@admit Cairo` (a thin, closed package) inlines it at zero overhead.

**C. ForwardDiff.**
- **Setup:** the solver's extension `TraitODEForwardDiffExt` declares `@admit ForwardDiff`. The user's `ForwardDiff.gradient(p -> loss(solve(prob(p))), p0)` runs in plain Julia and enters the TW with a `Vector{Dual{Tag,Float64,N}}`.
- **Dual arithmetic:** in the solver loops, `+`, `*`, `muladd` and `exp` on Duals, and the `Partials` arithmetic, are ForwardDiff's own methods. They are trusted, compiled into the TW code, and inlined and vectorized as in plain Julia.
- **Calls out of ForwardDiff:** what ForwardDiff calls in NaNMath, SpecialFunctions or LogExpFunctions on Float64 is foreign, adding about 4 ns to a 20 ns `pow`.
- **The right-hand side:** the user's `f!(du, u, p, t)` is a foreign call at the Dual signature (lesson 10). Plain Julia compiles `f!` for Duals, and each call adds about 4 ns.
- **Jacobians:** the solver builds `Dual{SolverTag}` values with ForwardDiff's constructors (trusted) and calls `f!` with them as foreign calls. Nested duals work the same way.
- **G2:** a fact on a Dual signature can change only through ForwardDiff (fixed after load), the user (who owns the function type inside `Tag`), or a pirate on Dual.
- **Without admission:** every dual operation is a foreign call. Results are still correct, but loops are an estimated 5–20× slower. A foreign-call profile names the hot sites so the user knows to admit.
- No library-owned dual type is needed.

**D. Makie + CSV + DataFrames, any order.**
- **Pirates:** nothing is refused, so Base pirates (OffsetArrays, StatsBase, Durations) load. A pirate costs nothing unless it wins dispatch at a concrete signature in a TW fact.
  - A pirate that does win triggers recompilation of the affected instances (0.7–1 s, as measured). After that, the site is a foreign call into the pirate's method, and the result is plain Julia's.
  - The environment's own precompile, in an app package that depends on both, caches that recompiled code. The cost is paid once per environment.
- **Makie calls the TW:** Makie calls TW code from plain Julia after converting `x, y` to `Matrix{Float64}` (lesson 6). The entry costs a few ns.
- **The TW calls Makie:** a TW recipe calls Makie through foreign calls. Makie's type-unstable internals stay outside the facts, and loading backends or extensions invalidates nothing (G2(b)).
- **Load order:** G2(c).

## 4. What users lose, and the strongest objection

**Losses**
- **No optimization across a foreign call.** Inlining, constant propagation and SIMD stop at the boundary, and each call costs about 4 ns. A type-unstable foreign function returns a non-concrete type, and the TW code after it becomes dynamic.
- **Run-time TypeErrors.** If something deep inside a foreign callee changes the callee's result type, the TW raises a `TypeError` where plain Julia would continue. G1 allows this, and the failing instance is invalidated so that the next entry recompiles.
- **G3 stops at the boundary.** The TW lists the foreign sites but cannot make Makie trimmable.
- **No protection from pirates.** The TW follows plain Julia even when a pirate is wrong. An optional strict mode, using an insertion hook, could refuse only those definitions that *win* at a TW fact. That is narrow enough for D to still load.
- **A second compile cache** for Base specializations, costing compile time and disk.
- **Admission is a global performance setting users must know about.** Forgetting it costs speed silently, which the foreign-call profile mitigates.
- **Few early errors about foreign code.** There are no declared signatures to check; this is the price of having none.
- **Inference-dependent results are excluded** (A3).

**Strongest objection.**

> "The predicate is exact only because R1 forbids abstract facts. Base code inferred for concrete types still has abstract sites: `@nospecialize` printing, `Type` arguments, `Any` fields, `_apply_iterate`, keyword sorters. Native Julia resolves them by enumeration and records abstract edges, and these are exactly the edges that pirates intersect. R1 either makes them dynamic and slow, or brings back 'invalidate on intersecting pirates', which costs 0.7–1 s per load (fact 3)."

**Answer.**
1. Union splitting stays: a union of concrete types splits into concrete facts. Only genuinely abstract argument types lose static resolution.
2. For concrete keys, the numeric and array hot paths infer concretely. The abstract sites sit on printing, error, IO and promotion paths, which plain Julia already dispatches dynamically or which are cold.
3. A hot abstract site can use a *match-set fact*, "the methods applicable to S are M". H2 can recompute that set, so G1 stays exact. The price is that a pirate merely *adding* an applicable method invalidates, so this form is for measured hot spots only.
4. Whether this holds is measurable, and that is the first experiment:
   - count the abstract sites in TW closures for A and C, and the cost of making them dynamic;
   - count the pirates in the D stack that *win* at concrete signatures used by TW code.

   If either number is large, this design fails. If both are small, wrapping reduces to three rules and two hooks, and its G1 proof does not depend on any declaration being right.
