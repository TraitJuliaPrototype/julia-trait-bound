# Wrapping by closed facts: a design derived from its proof

The idea in one sentence: **no wrappers. Trait-world code calls any Julia code directly, but may only *depend* on the method table through facts about closed signatures; whatever would need an open fact is called through a pointer instead.** Below, the model and theorem come first, and the rules are what the proof needs.

## 0. Model

- **Methods.** A method μ = (f, σ, body, mod), where σ is its signature type and mod is the module defining it. The method table M is a finite set of methods. For a concrete call signature s, `look_M(f, s)` is the unique most specific applicable method, or ⊥ (no method, or ambiguous: MethodError).
- **Worlds.** A world w names a table M_w. The event `def(μ)` produces M_{w+1} = M_w ∪ {μ}, minus any method with the same (f, σ) (a redefinition). `load(P)` is a batch of `def`s, plus the cached code of P's image, admitted only if it is valid (see below).
- **Reference semantics.** P_w(f, args) is plain Julia: every call dispatches by `look_{M_w}` on the runtime types. The observable result is the returned value or error, plus the sequence of effects (ccalls, IO, mutation).
- **Compiled code.** A CodeInstance c = (sig, validity range, F(c)). F(c) is the set of **facts** that inference relied on, taken transitively over the callees c reaches through edges. A fact has one of two forms:
  - *concrete:* (f, s, r) with s concrete (or a finite union of concrete signatures), asserting `look_M(f, s) = r`;
  - *open:* (f, S, {μ₁…μ_k}) with S containing an **open** type (one that can gain new subtypes when code is loaded, such as `Any`, `Real`, `AbstractVector`, or `Vector{<:Real}`), asserting "these are all the methods matching S".
  A signature is **closed** if it is a finite union of concrete signatures. Binding edges (constant globals) count as closed facts owned by the binding's module.
- **Calls that hold no facts.** A *dynamic call* dispatches at run time in the current world. A *pointer call* at a concrete signature s with declared result type R goes through a trampoline to the code currently valid for (f, s), re-resolving it if that code was invalidated (as `@cfunction` wrappers do), and asserts the result `::R`.

**Assumptions.**
- **A0 (Julia is sound):** if every fact in F(c) holds in M_w, then running c gives P_w. Plain Julia rests on this.
- **A1 (Julia never under-invalidates):** a `def` or `load` that falsifies a fact of c ends c's validity. A0 and A1 together are what make plain Julia correct.
- **A2 (quiet calls):** no method is defined while a trait-world call is running, so the latest world equals the caller's world. Without A2, pointer calls have `invokelatest` semantics.
- **A3 (trampoline):** a pointer call behaves as `P_w(f, args)::R`.

## 1. The theorems and the minimal conditions

**Theorem 1 (G1, identical or error).** Let c be trait-world code that is valid in w. Running c on any arguments returns P_w's value with P_w's effects, or raises. If it raises, the effects before the raise are a prefix of P_w's effects.

*Invariant I:* every valid trait-world c has all its facts true in the current table.
*Proof.* Execution is a sequence of segments:
- direct code, which equals P_w by A0 under I;
- dynamic calls, which use `look_{M_w}` and so match P_w (a checked one either matches or raises);
- pointer calls, which by A3 give P_w's value or raise on the `::R` assertion.

Joining segments preserves "equal, or raise after a common prefix of effects". The events preserve I:
- `def` and `load` falsify facts only in code they invalidate (A1), and image validation re-runs each lookup;
- dynamic and pointer calls change no table, and code compiled during them gets facts that are true in M_w. □

**Corollary (no skip predicate).** G1 needs no hook. It holds for any design that **never suppresses an invalidation Julia would perform**. The dangerous ingredient of earlier designs was a predicate that skipped invalidations. Lesson 2's silent wrong result came from such a predicate, which ignored the user's type in the signature. That bug cannot happen here because nothing is skipped: a user who redefines their own method falsifies a fact about their own type, and Julia invalidates the code.

So the real question is **G2**: how can trait code be valid across loads without skipping anything? The answer is to hold only facts that unrelated code cannot falsify.

**Lemma D (dominance, order independence).** Let (f, s, r) be a concrete fact. Suppose every method of a set S either does not apply to s or is strictly less specific than r on s. Then `look(f, s) = r` after inserting any subset of S in any order.
*Proof.* r stays applicable and strictly beats every applicable newcomer, and the old methods are unchanged, so r is still the unique most specific method. □

**Lemma O (ownership).** Define the *stakeholders* Stake(f, s) as the owner of f and the owners of every type occurring in s, including type parameters and supertypes. Call μ a **pirate** unless mod owns f, or some argument position of σ admits only types that mention a type owned by mod. If a non-pirate μ applies to a concrete s, then mod ∈ Stake(f, s).
*Proof.* Some position has Tᵢ <: σᵢ, and every type in σᵢ mentions a type owned by mod. □

**Theorem 2 (G2, stable cache).** Let c hold only closed facts (condition **K**). Load packages S in any order. Then c stays valid unless S contains
- (a) a stakeholder of one of c's fact signatures, or
- (b) a pirate that is not dominated on one of those signatures.
*Proof.* Each closed fact splits into concrete ones. By Lemma O, a method from a package outside (a) and (b) is a non-pirate that does not apply, or a pirate that is dominated. Lemma D finishes the proof. □

**Necessity (why this is the minimum).**
1. If a method of S *wins* on a fact signature of c, then plain Julia now runs different code there. Keeping c would break G1. So cases (a) and (b) can never be "unrelated": no design satisfies G1 and keeps c.
2. If c holds an open fact (f, S, ms), then any package can define a new subtype of an open position of S, together with a method of f for it. That package is not a pirate and need not be a stakeholder of anything c computes with, yet it falsifies the fact.
3. Hence **K is necessary and sufficient** for the strong form of G2: "only packages that change the meaning of this code invalidate it".
4. The theorem needs nothing about layering, sealing, who owns the called code, or wrapper declarations. It only needs **closed facts, and no skipped invalidations**.

## 2. The design: three rules

**R1 (direct or pointer, chosen by the compiler).**
- A call in trait-world code whose argument types are closed can target any function: Base, Cairo, ForwardDiff, or the user's own. It becomes a **direct call** (which holds the callee's facts) if the callee's code satisfies K.
- Otherwise it becomes a **pointer call** at that concrete signature. Its result is asserted to the type inferred at compile time.
- Any decision the trait world makes by looking at the method table is recorded as a closed fact on the code that uses it. For example, "T has no `length` of its own, so the default is used" becomes the fact (length, Tuple{T}, fallback). The fact goes on the code that uses the decision, never on the reflection machinery (lesson 8).

**R2 (dynamic calls are checked).** A call whose argument types are not closed is a dynamic call. It holds no fact, and its result is `Any` or asserted.
- In an AOT build, its targets must lie in the build's listed set C; any other target raises.
- Each such call is reported when the trait library is precompiled (G4).

**R3 (decide in the canonical table).** R1's decisions are made when the trait package is precompiled. Julia precompiles a package with only its dependency closure loaded, so the table, and therefore the cached code, is the same in every session and load order. At load, ordinary image validation applies; nothing is refused and nothing is skipped.

That is the whole mechanism. The compile step, checkable on one page:

```
compile_call(f, s):                      # s = inferred argument types at this call site
  if !closed(s)              -> dynamic call (checked)                   # R2
  ci = code for (f, s) in the current table
  if closed_bit(ci)          -> direct call                              # R1
  else                       -> pointer call at s, result ::infer(f,s)   # R1
closed_bit(ci) = all(closed(sig(e)) for e in ci.edges) && all(closed_bit(callee(e)) for e in ci.edges)
                                                       # one bit per CodeInstance, computed once
```

**Hooks needed.**
- **H-ptr:** a pointer call at a declared signature, with the re-resolving trampoline and a result assertion (fact 5; about 4 ns).
- **H-dyn:** the checked dynamic call (fact 1).
- **H-bit:** compiler access to a CodeInstance's edges without holding edges itself (an AbstractInterpreter or inlining policy), plus the ability to attach recorded facts to emitted code.
- **Not needed:** the method-insertion refusal callback and the invalidation-skip predicate. The skip predicate is optional, and only to trim Julia's over-invalidation. It must stay exact, or G1 is lost.

**Theorem 3 (G3, closed for AOT).** The reachable set of a trait-world program consists of:
- the trait code for its entry keys;
- the direct-call closure, listed by the edges;
- the pointer targets, a finite list of (f, concrete s);
- the dynamic-call targets, restricted to C by R2.

The plain code behind each pointer target is ordinary Julia. Its own closure is what the trim verifier checks, and the list above gives the verifier its entry points. The guarantee is therefore **relative**: a pointer target that the trim verifier rejects (for example, printing to an abstractly typed `stdout`) is a build error, as in plain Julia.

## 3. The test cases

**A. Base.**
- Calls on concrete element types are closed and direct, so they cost what plain Julia costs: arithmetic, `getindex`/`setindex!`, `sum(::Vector{Float64})`, `sort!`, `lu!(::Matrix{Float64})`, and `string(::Float64)`.
- Their facts mention only Base or LinearAlgebra types. Only a new Julia version, or a winning pirate, can falsify them.
- Printing to `stdout` (an abstractly typed global, then `show` on `Any`) is not closed, so it becomes a pointer call costing about 4 ns plus the IO. It is reported at precompile time.

**B. Cairo.jl.**
- `CairoContext` and the surfaces are concrete foreign types. They are ordinary field types in the plotting library's key and need no handle.
- Calls such as `move_to(ctx, x::Float64, y::Float64)` end in `ccall` and are direct. Their facts are owned by Cairo and Base. Effects occur in plain Julia's order (Theorem 1 covers effects).
- An opaque handle is needed only if the plotting library wants *one* compiled copy for several backends; that is a key choice, not a wrapping choice.
- Any type-unstable Cairo.jl function becomes a pointer call automatically.

**C. ForwardDiff.**
- The solver's key contains the element type `Dual{Tag,Float64,N}`. Methods such as `+(::Dual, ::Dual)` and `exp(::Dual)` are ForwardDiff's extensions of Base functions. They are closed facts with stakeholders Base, ForwardDiff, and the tag's owner. They are direct, so the solver runs at plain Julia speed.
- The solver's own Jacobian duals use a solver-owned tag. They are cached in the solver's image (whose dependency closure includes ForwardDiff) and survive every load except new versions of ForwardDiff or Base and winning pirates on `Dual` signatures.
- **No library-owned dual type is needed.** Nested duals (the user's gradient over the solver's Jacobian) are concrete too, and are compiled once per nesting.
- The user's `f!(du, u, p, t)` can be called in two ways:
  - *Direct*, if the key includes `typeof(f!)`: compiled per `f!` at plain speed. A user redefinition of `f!` falsifies a fact about the user's own type, so Julia invalidates the code (lesson 2 by construction).
  - *Pointer call* at the concrete signature: the solver is compiled once per `(u, p, t)` types, costs about 4 ns per right-hand-side call, and the trampoline sees the redefinition.

**D. Makie + CSV + DataFrames, any order.**
- Trait code holds closed facts only, on key types and on types from its dependencies. Theorem 2 with Lemma D gives order independence.
- Makie, CSV and DataFrames are not stakeholders unless their types are in a key. Their non-pirate methods for their own types on Base functions (`show(::IO, ::DataFrame)` and many more) invalidate plain code that holds open facts, but not trait code.
- Base pirates in the stack (OffsetArrays, StatsBase, Durations) cost a recompile only if they **win** on a signature the trait code actually calls. In that case plain Julia's behaviour of that code changed, and Theorem 2's necessity part says the recompile is required.
  - A pirate on `Union`/abstract argument types that loses to Base's concrete method costs nothing.
  - **Open question:** the measured 0.7–1 s of recompilation came from a coarser rule. Whether the 12 OffsetArrays methods win on any fact signature is decidable at load time, and should be measured with H-bit's report.
- Using these packages from trait code goes through pointer calls, because their code is not closed: about 4 ns per call, results asserted or kept as `Any`.
- Data crosses by explicit conversion in an ordinary layer (lesson 6), for example `Matrix{Float64}(df[:, [:x, :y]])`, before the call into the trait world.

## 4. What it gives up, and the strongest objection

**What it gives up.**
- **G2 is not "never".** A package that changes the meaning of trait code, as its stakeholder or as a winning pirate, invalidates that code. Theorem 2 shows that no design with G1 can do better.
- **Pointer calls** cost about 4 ns, the compiler cannot optimise across them, and a changed result type becomes an error (from the assertion) instead of a recompile.
- **No refusal or sealing.** The trait world cannot stop a package from redefining Base; it recompiles instead.
- **G3 is relative** to the trim verifier for plain code behind pointers.
- **Performance cliff.** A new dependency version that makes a Base function type-unstable silently turns a direct call into a pointer call. It is reported, but not prevented.

**Strongest objection.** "Closedness is the wrong boundary. Much of what numerical code needs is *nearly* closed: broadcasting, `promote`, generic linear algebra on `Matrix{Dual}` (its fallbacks infer through small unions of methods on abstract signatures). R1 will send hot calls through pointers, and users will start annotating calls, which brings the wrapper declarations back."

**Answer.**
1. The pointer is paid *per call site execution*, not per element. A broadcast or `lu!` on a `Matrix{Dual}` costs 4 ns once, and its inner loops run inside plain Julia's compiled code at full speed. The calls that sit inside trait-world loops (scalar arithmetic, indexing) are exactly the closed ones, and they are direct.
2. For the rest there is a variant that still needs no declarations: compile the callee in the trait world's own cache (a CodeInstance owner token for an external AbstractInterpreter), turning its open call sites into fact-free dynamic calls. That makes the callee closed, at the price of compiling it twice.
3. Every pointer call is listed in the precompile report, so the cost is visible and measurable rather than hidden.

The proof does not change in either case, because its only premises are A0–A3, closed facts, and no skipped invalidation.
