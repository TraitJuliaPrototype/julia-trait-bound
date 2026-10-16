# Brief: using code written without traits from a "trait world" in Julia

You are asked for a fresh design. Read only this brief; do not look for or rely on any existing design documents.

## The setting

Julia compiles a method for the concrete types of its arguments; generic functions get methods from any package; loading a package can add methods anywhere (including to Base functions), which invalidates compiled code whose inference depended on the method table ("invalidation"). Concretely: inference records "edges" (backedges) from compiled code to the methods/method-table signatures it relied on; inserting a method that intersects such a signature invalidates the code. Type piracy = defining a method of a function you don't own for types you don't own.

A **trait world** is a part of a Julia program written against traits (abstract types with declared operations and fields; types conform by explicit declaration; library code is compiled per "key" = the types the trait can see, not per user type). It is being built as a research prototype and wants these guarantees for compiled trait-world code:

- **G1 (identical or error):** a call into the trait world computes exactly what plain Julia would compute for the same program, or raises an error. Never a different result.
- **G2 (stable cache):** compiled trait-world code is reused across sessions and load orders; loading an unrelated package never invalidates it.
- **G3 (closed for AOT):** the set of methods a trait-world program can reach is finite and listable, so a trimmed binary can be built.
- **G4 (early errors):** mistakes are reported where library code is defined, not deep at run time.

The trait world needs code written without traits: Base (arithmetic, arrays, strings, IO, LinearAlgebra), C-library wrappers (Cairo.jl), numeric packages (ForwardDiff's dual numbers), and large ecosystems (Makie). Your task is the design of **how the trait world uses such code** ("wrapping"): it must be much simpler than a design based on per-package wrapper declarations, delegation lists, sealing regions and declared "doors", and its guarantees must be **provable** from stated assumptions about the runtime.

## Hard facts and lessons (from prototypes and measurements)

1. Method insertion and package-image validation can be hooked in a patched Julia: a callback before a method is activated (may refuse it), and a predicate deciding whether a given definition can change a given compiled CodeInstance (to skip invalidation). A dispatch check at dynamic call sites in trait-world code is also possible (checked dynamic call). Assume these hooks exist; say which you need.
2. **Who can change compiled code:** under layering (trait-world code calls only trait-world code), a method can change a compiled call only if it applies to the call's signature. The "stakeholders" of a method are the owner of its function and the owners of the types in its signature. A compiled specialization's signature includes the user's types when the code was compiled for them (e.g. a worker compiled for the user's own type that implements a trait) — then that user's later definitions (e.g. redefining its own method) MUST invalidate it. A predicate that ignored this produced silent wrong results.
3. **Pirates of Base are common in real stacks:** OffsetArrays (12 methods of Base functions on Base types), StatsBase, Durations all pirate Base. A rule "refuse every pirate of Base" makes CSV+DataFrames+Makie unloadable next to the trait world; a rule "invalidate on pirates" makes cached trait-world code recompile after such loads (measured 0.7–1 s first-call costs).
4. **Defaults over existing functions break:** if the trait world decides "type T uses the trait's default for `length`" and T's owner (or the owner of T's abstract supertype) later adds `length(::T)`, plain Julia would call the new method; the trait world must then error or recompile.
5. **Calls through function pointers at a declared signature** (`@cfunction`-style, or `invokelatest` with a declared result type) carry no inference edge into the callee; the caller's compiled code cannot be invalidated by the callee's dependencies; cost: ~4 ns (pointer) to ~100+ ns (invokelatest). Results are asserted to the declared type. Opaque "handles" can carry foreign objects through the trait world without the trait world inspecting them.
6. **Explicit conversion works best for foreign data:** e.g. a plotting library converts `x, y` vectors into its own `Matrix{Float64}` in an ordinary (non-trait) layer before calling into the trait world. Implicit conversions at the boundary hid copies and needed inverses.
7. **Numbers from packages are the hardest case:** an ODE solver in the trait world must run on ForwardDiff's `Dual` for gradients and Jacobians; Dual's arithmetic methods belong to ForwardDiff (they extend Base functions for ForwardDiff's types — not piracy). A library-owned dual type was used as a stopgap.
8. Machinery code that reflects on method tables must hold no inference edges (or it gets invalidated by every declaration).
9. Dynamic dispatch inside Base code (e.g. `show` on `Any`, `iterate`, `promote`) can reach methods from any package.
10. Users must be able to write ordinary generic Julia functions (e.g. an ODE right-hand side `f!(du, u, p, t)`) and pass them in.

## Test cases your design must handle (say how)

- **A. Base:** the trait world uses arithmetic, arrays, `sum`, `sort`, `LinearAlgebra.lu!`, string formatting, printing.
- **B. Cairo.jl:** a plotting library draws through a C library wrapper (side effects, handles).
- **C. ForwardDiff:** a trait-world ODE solver runs its loops on `Vector{Dual{Tag,Float64,N}}` supplied by the user's gradient computation, and computes Jacobians with duals of its own.
- **D. Makie + CSV + DataFrames loaded in the same session,** in any order, some of which pirate Base.

## What to deliver

Write your design to the file path given in your task, in at most ~3 pages of markdown:
1. The design in a few rules (fewer is better), with the runtime hooks it needs.
2. A precise statement of what is guaranteed (G1–G3 at least), the assumptions, and a **proof sketch** (an invariant on method tables / compiled code / worlds, and why every event — method definition, package load, dynamic dispatch, call through a pointer — preserves it).
3. How A–D work, with costs.
4. What it gives up, and the strongest objection to it with your answer.
Then reply with a summary of under 300 words. Do not run Julia. Do not read repository files other than this brief.
