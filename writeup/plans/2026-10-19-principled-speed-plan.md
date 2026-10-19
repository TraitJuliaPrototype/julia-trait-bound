# Making everything fast, by principled and proven designs: an order of work (proposal, 2026-10-19)

The user (2026-10-19): "the focus now should continue to be on principled ways to make everything fast, and as close as possible to established and battle proven designs of other languages."

The facts mode removes Julia's speculation at calls whose argument types are not known, and records no edge there. Today such a call dispatches through the generic path, at tens of nanoseconds, with its result typed `Any`. Most remaining costs trace to that, or to work done in a session that an image could have held. Established virtual machines and compilers solved both problems long ago. The order below takes their designs, in an order where each step reuses the one before.

## 0. Ground truth (short)

- Rerun BaseBenchmarks under `all` on the current compiler: the facts mode's tails as they are today (the last run predates parts B–D and the inliner changes).
- Diagnose the ~990 ms upstream CSV + DataFrames still pay after nine loads under `all`, with a full list of what is compiled again and the winning methods.
- Output: the list of slow paths, ranked, that steps 1–4 are measured against.

## 1. World-checked inline caches at dynamic call sites (fixes G1.20 first)

- **The mechanism.** A cache per call site of `(type, entry point, world range)`; the call checks type and world, then calls; a miss dispatches as now and adds an entry. Specified in `design.md` §4.5.
- **Precedents:** polymorphic inline caches in Self (Hölzle, Chambers and Ungar, 1991), in V8 and in the Java virtual machines. Julia's generic dispatch already keeps a hashed cache keyed by call site, so the new part is a guarded direct call compiled into the caller, with the world check.
- **Uses:**
  - **`Callable`'s `DynamicCall`,** replacing the `@cfunction` pointer: G1.20 passes, and the call stays about as cheap as an indirect call.
  - **`Dynamic` beyond four implementations,** between the split and the fallback.
  - **The fallback of the split itself.**
- **Measure:** against the split (about 1 ns), the generic fallback, and plain Julia's best and worst cases (the sum and the raytrace benchmarks with 2, 4, 8 and 16 types).

## 2. Guarded devirtualization at the facts mode's run-time sites (postponed)

**Postponed (the user, 2026-10-19).** Code bounded by traits has its calls at facts and never reaches these sites; the step serves untyped plain code under `all`, which is the case "slower is fine if traits can easily recover it" covers. It is also the largest risk. A failed guard is a cliff: that site turns dynamic for good, silently, until its caller is compiled again. If the step returns, it comes with:
- a report of failed guards, which says the site, the method that broke the guard, and its package (as HotSpot's `PrintCompilation` "made not entrant" and V8's `--trace-deopt` do), through the warnings machinery;
- possibly compiling the caller again after a failure (as the Java virtual machines do after deoptimization), which turns the permanent cost into one compilation.

The step 0 benchmarks under `all` stay: they record what the facts mode costs untyped code.


- **The problem it solves.** The facts mode's cost on code that is not type-stable: at an abstract call, plain Julia infers through the methods that exist today and records an edge; the facts mode does neither, so the result is `Any`.
- **The mechanism.** At such a site, the compiler still compiles the methods plain inference would choose, but guarded, not assumed: a type check against the argument and a validity check against the method table.
  - The validity check is a cheap counter per generic function, or the world range of step 1.
  - The fast path is inlined with its types known.
  - On a failed guard, the call takes the dynamic path and records nothing.
  - So unrelated loads still invalidate nothing; at worst they make a guard fail.
- **Precedents:**
  - HotSpot's class-hierarchy analysis with guards and deoptimization;
  - .NET's guarded devirtualization;
  - V8's speculative optimization with checks.

  Julia's invalidation is itself deoptimization by recompiling; guards make it lazy and local.
- **Target:** the BaseBenchmarks tails of step 0 (containers of `Any`, abstract element types, small-union broadcasts), toward plain Julia's speed with the facts mode's guarantee.
- **Risk:** the largest step. It needs a careful definition of the guard, so that "identical or error" holds. The acceptance suite's G1 cases come first.

## 3. Cheaper entries: typed calls and calls from untyped code

- **Typed calls** cost 36–38 ns against 33.8–34.5 ns for the same loop in plain Julia. The cost is in the entry's `conformance` construction and checks.
- **Calls with an argument of unknown type** cost about 120 ns, against about 55 ns for a plain dynamic call: two dynamic dispatches (the `conformance` lookup, then the worker) and a boxed trait object.
- **Mechanism:** the `conformance` lookup through the call-site cache of step 1 (type → builder), and the worker call fused with it.
- **Precedents:** Swift's witness-table lookup caching and its existential opening; Rust creates a `dyn` value once.

## 4. Compile ahead from declared implementations (`design.md` §4.8)

- **The mechanism.** When a package declares an implementation, its precompile workload compiles the trait's declared workers for its key: the code a first call needs exists in that package's image.
- **What it replaces:** hand-written workload extensions (the forks' `CSVDataFramesInlineStringsExt`), and the clean-case cost of `@implement` and first calls.
- **Precedents:**
  - Rust's monomorphization in the crate that sees both the generic code and the type;
  - Swift's cross-module specialization (`@inlinable`, `@_specialize`);
  - C++'s explicit template instantiation.

  The design's declared targets make the list exact, which is also what AOT builds need.

## 5. The machinery's own startup

- **The problem:** TraitWorld's slow paths are compiled by facts (`@machinery`), and type-unstable by nature, so they compile facts copies of Base methods in each session. This is the likely cost behind the clean-case `@implement` (77–97 ms for a forwarding implementation).
- **Fixes:**
  - a precompile workload for the machinery under its own owner;
  - checks results kept in images.
- **Precedents:** Swift's module interfaces and Rust's incremental compilation, which keep the compiler's own analyses between builds.

## Interleaved, independent

- **Upstream proposals** of the general fixes:
  - the run-time `return_type` entry in the image;
  - reflection in the compiler's world;
  - the two inliner changes, after broader measurement.
- **Acceptance checks** for each step, written before the step: G1.20 for step 1, guard cases for step 2.

## Why this order

- Step 1 fixes a correctness defect (G1.20), and its mechanism is reused by step 3.
- Step 2 is postponed (above): traits recover the costs it targets.
- Steps 4 and 5 remove first-call costs, independent of steps 1 and 3.
- The order in force: 0, 1, 3, 4, 5.
- Step 0 comes first because it sets the targets, and because "diagnose, then fix" is the user's standing order.
