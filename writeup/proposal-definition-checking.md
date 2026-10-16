# Definition checking, and named implementations

Proposal of 2026-10-16 (session 22). Adopted by the user, with these decisions:
- definition checking, as proposed;
- checking deferred for open parameters ("pragmatic and sensible");
- named implementations, with the module name as the name and "liberal": anyone may write one.

It answers two findings of `other-languages.md`:
- C++ never got definition checking; Rust, Swift and Mojo have it.
- Rule 3 leaves no home for adapter code, the pain both Rust's orphan rule and Swift's `@retroactive` report.

## 1. Definition checking at archetypes

**Before.** The prototype checked each worker's typed code per signature, so per representation. That happened when the library was built, for its own representations, and at the first call of every new one. A library was checked only at the representations someone happened to compile, which is closer to C++ templates than to Rust.

**The observation.** Two facts make a worker's code nearly independent of the representation:
1. **A trait object has no methods except its traits' operations.** The trait macro defines only those, so what library code does with `t` is the same set of calls for every representation.
2. **Every operation declares its result type,** which `opcall` asserts. So everything computed from the results has the same types for every representation.

What varies by representation is only the implementations of the operations, and those are checked at their conformance. So one inference run against a stand-in representation checks a worker for all representations.

**The archetype.** `Archetype{X}` stands in for a representation of trait `X`, with a witness `ArchWit` whose dispatch returns an opaque value.
- `opcall` asserts the declared result type of that value, so inference continues with exactly what the trait promises and nothing more.
- A bounded position becomes `TObj{…, Tuple{View{X, ArchWit, Archetype{X}}, …}}`, with the bound's supertraits sharing its archetype.
- The existing checks then run unchanged: rule 2, escapes, layering, globals, doors.

**Deferred to the first call, checked per signature as before:**
- **Bounds with open parameters,** `x::ArrayLike{T}` with `T` free. Code that computes with `T` would need a bound on `T` to be checked here.
- **Workers taking a function from above.** In the design this means a `Callable` whose result type is open. The prototype is cruder: it defers every `Callable` argument, and keyword and vararg workers too.
- **Concrete mode's findings.** For a trait that does not require concreteness they depend on the implementations; they run at the first call as before.

**Why C++0x failed at this and we do not:**
- C++ had to change name lookup inside constrained templates; our trait object has only its traits' methods, by dispatch.
- Constrained templates could not call unconstrained ones; our layering rule already forbids that, and calls upward go through pointers.
- Implicit conversions and mixed arithmetic happen in our case on declared concrete result types, which is ordinary concrete Julia.
- The C++0x checker was more than 10 times slower than compilation. Ours is one inference run per method, at the library's build.

**Prototype** (`TraitWorld/src/defcheck.jl`; demo `poc/world/defcheck_demo.jl`; 10 tests):
- `check_definitions(Columns)`: five methods checked clean, 184–199 ms in a cold session including the checker's own compilation. In a design implementation this runs at the library's build and is stored with its image.
- A library with mistakes, checked before any representation exists:
  - `spread(t::ColTable) = size(t)` → "`size` has no method for a trait object carrying ColTable", at its line;
  - `leak(t) = typeof(t)` → "`typeof(t)`: code must not depend on the user's type";
  - `sum(t)` and passing `t` where another trait is needed (rule 2) are found the same way;
  - clean methods are recorded.
- First calls of a representation defined in the session (`Ramp2`, its own representation), two fresh sessions each way:

  | worker | checked per signature | checked at definition |
  |---|---|---|
  | `colmean` | 58.3–61.9 ms | 55.0–58.2 ms |
  | `colrange` | 24.8–25.5 ms | 21.4–21.6 ms |
  | `meandiff` | 10.5–11.4 ms | 10.2–11.1 ms |

  The per-signature check is 3–4 ms of a first call; the rest is compilation. The note's "first calls 19 ms, most of it inference in the checks" is not borne out here. The gain is that errors come at the library's build, independent of representations, not latency.

## 2. Named implementations

**The problem** (other-languages §4 and §5):
- Rule 3 lets only owners and delegates implement, which leaves adapter code without a home. That is Rust's chrono × diesel, and the pressure Swift answered with `@retroactive`.
- A trait owner who adds a generic implementation later can create an unordered overlap with a downstream specific one, which the check "when the specific one is defined" misses. Rust made adding a blanket impl a breaking change for this reason.

**The enabling fact.** A trait object carries its witness, where its operations come from, in its type (`View{X, W, R}`). So the choice of implementation is made once, at the crossing, and travels with the value:
- workers are compiled per (representation, witness), so two implementations never mix in compiled code;
- a `Dynamic` keeps the implementation it was made with.

Rust keeps one impl per (trait, type) because of the "hashtable problem": a value built with one implementation and queried with another. That cannot arise here, because the implementation is part of the value.

**Rules:**
1. **A named implementation is named by its module.** Module `Fast` writes `@implement named ColTable Measurements …` (a sketch of the syntax). A caller selects it with `via(Fast, m)`, a wrapper the entry strips, as it strips `compiled_call(f)`. Julia's precedent: `using A, B` where both export `f` makes bare `f` an error at use and asks for `A.f`.
2. **Anyone may write one.** A named implementation is used only where it is named, so it changes no code that does not name it, and it is not piracy. Its operations are methods keyed by a witness type its module owns, so rule 3 holds. Its compiled code lives where rule 4 puts a combination: its own package depends on the trait's and the type's packages.
3. **Discoverable implementations are unchanged.** An unnamed implementation is written by an owner or a delegate (rule 3), and "more specific beats generic" picks among them.
4. **Ambiguity surfaces at the crossing.**
   - Two discoverable implementations that apply without one being more specific are reported when the later is defined, if it sees the earlier, as now.
   - Otherwise, as when a trait owner adds a generic implementation in a later version, the load is not refused. An unnamed crossing that meets both raises an error naming both modules and the fix, `via(A, x)` or `via(B, x)`. Code where the old choice is more specific keeps working.

   That is "identical or error".
5. **A more specific implementation declares the same parameter values** as the generic one it overrides, so a choice between them never changes types. That is Turon's lesson from Rust specialization.
6. **Membership counts discoverable implementations only.** `x isa ColTable` is true through an unnamed implementation. A type with only named ones is a member only where it is named.
7. **Equality and printing.** Two `Dynamic` values with the same representation and different witnesses compare unequal, extending the `AnyHashable` rule. Trait objects and `Dynamic` values print their implementation: `ColTable via Fast`.
8. **No selection by scope.** A module-level "prefer `Fast`" is rejected: the entry is compiled once in the library's image and does not know its caller's module, and Scala 2's implicits show where import-dependent implementations lead.

## 3. Note edits

- **A subsection "Definition checking"** in "Finer points", after "How a type conforms to a trait".
- **The check list of "What code in a trait module may do":** library code is checked at its definition, at archetypes.
- **"Generic implementations":** overlap now names both orders and points to named implementations.
- **A subsection "Named implementations"** in "Finer points", and rule 3: "an owner or a delegate" for discoverable implementations, anyone for named ones.
- **"Other options considered"** gains nothing: named implementations were not considered before.

Items 2–5 of the session's revisit list go into the note at the same time:
- the answers to C++0x's objections;
- early binding as deliberate;
- the concreteness default as a commitment;
- the cost of shared compiled code.
