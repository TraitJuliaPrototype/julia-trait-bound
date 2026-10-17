# Traits for better Julia: design choices

> **Status (2026-10-17).** Parts of this note describe the design before wrapping by facts (`writeup/explorations/wrapping-by-facts.md`, validated in session 24), and are no longer true:
> - **§5, layering,** is gone for calls: trait-world code may call any Julia code, and its compiled code depends on the method table only through dispatch facts at concrete signatures ([the design in detail: the four rules](4-details.md#the-four-rules), rule 1).
> - **§6 and §7, and costs 1, 2, 6 and 8:** no pirate is refused at load (an override of a declared conformance is, decision 4 of session 27). There is no sealing, no trait wrapper, no delegate and no declared call. Pirates are followed as in plain Julia; trait modules may not define them; an optional strict mode refuses a pirate that would change trait-world code ([code written without traits](3-wrapping.md)).
> - **"Other options considered", the edge-level rule,** is close to what was adopted. Its cliff at abstract calls is accepted (run-time dispatch, on cold paths in the demonstrators), and the closed world for AOT is restated ([AOT](4-details.md#aot-the-reachable-code-is-declared)).
>
> This note is to be revised.

This note covers what the design decides, how C++, Rust, Swift and Mojo decided the same questions, what went wrong for them, and why we chose as we did. The [overview](1-overview.md) states the goals; [the design in detail](4-details.md) states the rules.

The research behind this note is in `writeup/other-languages.md`, from primary sources: Stroustrup's HOPL papers and WG21 papers, Rust RFCs, Swift Evolution proposals, Mojo's changelogs and proposals. Claims about other languages carry a link or point there.

## At a glance

| Decision | C++ | Rust | Swift | Mojo | Ours |
|---|---|---|---|---|---|
| What a trait is | concept: a predicate on types (C++20) | trait: not a type, except as `dyn Trait` | protocol: also a type (`any P`) | trait: not a type | an abstract type with behaviour |
| Conformance | structural (C++20); C++0x had declared concept maps, then dropped them | declared `impl` | declared, global, retroactive allowed | declared (structural added 2024, removed 2025) | declared `@implement`, never derived from methods |
| Generic code checked | at instantiation only | at definition, against bounds | at definition | before instantiation | at definition, at archetypes; open parameters per signature |
| Code generated | per type (templates) | per type (monomorphization) | once, dictionary passing; specialization an optimization | per type, whole program | per key: what a bound can see; per type only by choice |
| Conformance through a field | — | by hand, or `Deref` | by hand | — | forwarding, compiled per the field's type |
| Dynamic position | virtual functions, type erasure | `dyn Trait`, chosen by the callee | `any P`, existentials | none (roadmap) | dynamic operations, dynamic calls (the caller overrides), `Dynamic{X}` |
| Storable dynamic value | yes | `Box<dyn Trait>` | `any P` | `Variant`, `PythonObject` | `Dynamic{X}` |
| Who may add a conformance | anyone (structural) | owner of trait or type (orphan rule) | anyone, warned since Swift 6 | the struct's author; extensions proposed | owner or delegate; anyone for a named implementation |
| Overlap | partial specialization | specialization unstable since 2016 | overlapping conformances banned | — | more specific beats generic, a chain; unseen overlaps surface at the call |
| Where compiled generic code lives | every translation unit; `export` removed | the instantiating crate, duplicated per crate | the library, or the client via `@inlinable` | the final program | the image of the package that chose the type |
| Dynamic world | — | — | Objective-C runtime | Python via `PythonObject` | dynamic Julia, above the trait world |

## 1. A trait is an abstract type with behaviour

**The choice.** A trait is an abstract type whose behaviour is declared: operations with declared argument and result types, and fields with declared types. Optionally it guarantees that whatever conforms becomes concrete with respect to that behaviour. Traits are a kind of abstract type, not a separate concept:
- `x isa ColTable` and `T <: ColTable` mean conformance;
- a trait takes parameters, as `AbstractArray{T, N}` does;
- by position, a trait reads as an abstract type reads:
  - an argument is compiled for what its bound can see, as an abstract-typed argument is compiled per type;
  - a field or container holds any conforming value behind the trait's operations, as an abstract-typed field holds a boxed value;
  - `Vector{<:ColTable}` has one key for all elements, as `Vector{<:AbstractFloat}` has one element type.

**How other languages place it:**
- **Rust's traits are not types,** except as `dyn Trait`.
- **C++20's concepts are predicates on types.**
- **Swift's protocols are types,** and that confusion cost it most. The bare protocol name as an existential "had risen to the level of active harm" ([SE-0335](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0335-existential-any.md)), because it hid boxing and dispatch behind a name that looked like a generic constraint. Rust made `dyn` explicit for the same reason ([RFC 2113](https://rust-lang.github.io/rfcs/2113-dyn-trait-syntax.html)).

**Why ours is different.** Julia types already serve both roles. An abstract type in an argument is specialized, and in a field it is boxed, and Julia's performance tips teach both. So a trait reading like an abstract type by position follows a convention Julia users know, instead of introducing one. The cost that position hides is smaller than Swift's: a dispatch with declared results and targets closed by ownership, not an open `Any`. Concrete mode reports it in a hot loop.

**What traits add over abstract types** is in the declaration, not at the use:
- A type joins a trait after it is defined, and joins several. Julia fixes a type's supertypes when it is defined, because subtyping must not change under compiled code. A conformance can come later because only an owner or a delegate declares it, loaded with the type's or the trait's package (rule 3), so once both are loaded no load changes it.
- The contract is checked at the conformance and at the library's build.
- Code is compiled for what the bound can see, so types that forward to fields of one type share compiled code (§3).

| Use of an abstract type | Trait form |
|---|---|
| dispatch on a family, `f(x::AbstractArray)` | a bound, `f(x::ArrayLike)`: compiled per type for a type that implements the operations, as today, per field type for one that forwards |
| fallback methods for subtypes that define a few | default operations and generic implementations |
| a field or container of mixed types, `Vector{Number}` | `Vector{NumberLike}`, dynamic values: targets closed by ownership, results declared |
| one concrete element type, `Vector{<:AbstractFloat}` | `Vector{<:ColTable}`, one key for all elements |
| a constraint on a type parameter, `struct S{T <: Real}` | a type parameter constrained to conforming types |
| required fields (not expressible in Julia today) | fields declared by the trait, typed by its associated types |
| documentation of intent | operations with declared result types, checked |

**Numbers need no trait.** `Float64` and `Measurement{Float64}` are trait-world values by their types, and Base's numeric tower stays. Promotion runs on concrete types in Base. A numeric *trait*, for numbers that conform after the fact or forward to a field, would need operations across two implementing types, which is promotion; that is open.

**Rejected:** hidden type parameters, a struct implicitly parametric in the types of fields declared by bounds. "Hidden type parameters seem antithetical to Julia" (the user, 2026-10-16). Stored state with a fixed type uses explicit type parameters; with a changing one, dynamic values.

## 2. Conformance is declared

**The choice.** A type conforms because someone declared it, `@implement ColTable T`, never because the methods happen to exist. The one-line form keeps declaration cheap: it reads the type, and the checks run at the declaration.

**Other languages.**
- **C++.** This was the central fight of the C++0x concepts effort.
  - Indiana (Gregor, Siek, Lumsdaine) wanted declared concept maps. Their example: `istream_iterator` structurally satisfies Forward Iterator, so the faster two-pass algorithm is chosen and fails at run time ([Gregor et al. 2006](https://www.cs.kent.edu/~jmaletic/cs69995-PC/papers/gregor-06.pdf)).
  - Texas A&M (Stroustrup) wanted implicit matching. Accidental matches are "not in the top 100 problems", and explicit maps make library writers "push resolution of even the most obvious choices onto their users" ([N2906](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2009/n2906.pdf)).
  - C++20 ended up structural, with "satisfied but not modeled" being ill-formed with no diagnostic required.
- **Mojo** added structural conformance in 2024 and removed it in 2025.
- **Rust and Swift** declare conformance from the start.
- **Carbon**, the successor Google proposed for C++, chose declared `impl` plus coherence.

**Why.** In Julia, structural matching proves even less than in C++, where Stroustrup's argument rested on names *and* types matching:
- Base's fallbacks exist and throw, so `getindex` has a method for every `AbstractArray` and `hasmethod` is true almost everywhere.
- Types conform by accident: a `Number` iterates and indexes, a `String` indexes by byte.
- Whether a call infers changes with what is loaded.

**The cost, and the answer.** The C++ debate predicts the objection that explicit conformance is "viral". The answers:
- the one-line `@implement`;
- family declarations through Base's abstract types (`@implement Indexable A where {A <: AbstractVector}`), C++0x's templated concept maps;
- trait wrappers that declare for a whole package ([Code written without traits](3-wrapping.md)).

## 3. Compiled for what the bound can see

**The choice.** Julia compiles a method for the full concrete type of each argument. A trait-bound function is compiled for its bounds' *keys* instead: the types its bounds can see.
- **The implementing type,** whose own methods serve at least one operation: the conforming type itself, or the field it forwards the trait to, `@implement ColTable Measurements` with `data::Vector{Vector{Float64}}`. A conformance whose operations are all served by the trait's defaults, written over declared fields, has none.
- **The types of the declared fields.** A field typed by an associated type, `u::U` in `Integrator{U, P}`, puts that type in the key, whatever else the conforming type holds.

Library code reaches a value only through its bound, so this is all it can depend on. Types that differ elsewhere share compiled code.

**Between nested types and `Any`.** Julia code today chooses, field by field, between types that carry the types of all their parts and `Any`. The trait world makes that choice per conformance and per call mode instead, and code above a bound keeps the trait's contract whichever way it goes.

| Position | Compiled | A call on the value | Compiled for | A load elsewhere |
|---|---|---|---|---|
| Julia: a type parameter | per nested type | direct | the whole type | can invalidate it |
| Julia: an `Any` field | the caller once, each target per runtime type when first reached | dynamic, result `Any` unless asserted | nothing | can add targets |
| the type implements the operations | the library per type, in the conformer's image | direct | the type, reached through its operations | changes nothing (rule 4) |
| forwarding to a field | the library per field type | direct | the field's type | changes nothing (rule 4) |
| declared fields | the library per tuple of field types | a load at the field's offset in the user's object | the fields' types | changes nothing (rule 4) |
| dynamic operations | the library once per conformer, in the conformer's image | indirect, result type declared | the field's type | changes nothing (rule 4) |
| dynamic call | the library once per signature, the function by its caller | indirect, result type declared | the signature | changes nothing (rule 4) |
| compiled call | per function type, in the caller's image | direct | the function's type | can invalidate it, as today |
| `Dynamic{X}` | each operation with its conformance; the library per key where it is opened | a dispatch on the stored value, result type declared | the operations, until opened | changes nothing (rule 4) |

**Growth ends where it is chosen to.** Forwarding, declared fields and dynamic positions end the growth there: code above compiles per tuple of the keys at its own bounds, whatever was built below.
- **Within one function** the compiled code still multiplies over that function's bounds, as `meandiff` does over its pair.
- **Across layers** it adds up, because each layer's keys are the types that layer declares, not the types assembled from the layers beneath.
- **It continues only by choice, in the chooser's image:**
  - a type that implements the operations itself;
  - a parametric family;
  - a generic implementation;
  - a compiled call;
  - a dynamic call with an open result type.

The argument is structural; it is not yet measured on a stack of trait modules.

**Why keys and not representations.** Until session 22 the design translated a value to a *representation*: plain data produced by a projection, a field read or any computed function, with an inverse to rebuild the user's type. Keys keep what that bought and drop the rest:
- **Sharing narrows to forwarding.** A field's type is the key, so every type forwarding to a `Vector{Vector{Float64}}` shares the library's code. Types that a computed projection used to map onto it now convert explicitly (below).
- **Nothing is copied.** A trait object is the user's object with the offsets of what its bound sees, in one layout per trait and key, so every read sees the current value and every write reaches the user, as in plain Julia; the inverse for a result like the input is the user's object with fields replaced. With the alias metadata Julia's own loads carry, loops run as in plain Julia; the cost is about 2 ns per call (`experiments/lens/layout.md`).
- **Several fields.** A key is the types of all declared fields, not one representation that a solver's state, parameters and time would have to be packed into.
- **Lost:** computed projections, a lazily derived representation or a foreign type converted on the way in. A library that wants shared code for such types converts explicitly, at the cost of a copy, no `Like{t}` and no write-through ([the design in detail: Types that only convert](4-details.md#types-that-only-convert)); a foreign type may also conform by an implementation its wrapper's delegates write, compiled per foreign type ([code written without traits](3-wrapping.md)).

**Precedents** (from memory and the review of the keys plan; not in `writeup/other-languages.md`):
- **Haskell's** newtype deriving and `DerivingVia` give a type the instance of a type with the same runtime representation, a `Coercible` one. That is closer to the earlier representations than to forwarding one field of a record with other fields, which neither supports. The instance's code exists once because Haskell passes dictionaries, not because of deriving.
- **Go's** struct embedding satisfies an interface through methods the compiler generates per outer type, the analogue of our entry. Go 1.18 compiles one generic instance per "GC shape", grouping types by underlying type and all pointers together: a key that ignores what the generated code does not distinguish.
- **Kotlin's** `by` forwards an interface's methods to a field.
- **.NET** shares generic code among reference types.
- **Julia's own** function-barrier idiom, passing only the fields an inner function needs, and SciML's AutoSpecialize, which wraps the user's function to stop specialization, are the closest relatives.

None of them makes a forwarded field the compile key, because none specializes generic code per type the way Julia does.

**The dynamic positions are not `Any`.**
- Result types are declared and asserted, so code after a call infers concretely.
- The targets are conformances and declared signatures, which only owners and delegates add, so no load from outside adds one and a build can list them.
- A key with an abstract part (concreteness is opt-in per trait) is such a position by the conformer's choice: one worker, run-time dispatch where it reads that part; `@warn_on_abstract` and concrete mode report it.
- The cost is the direct call: about 4 ns for a dynamic call and 6.3 ns (7× plain Julia) for a per-element dynamic operation on the prototype, and 20–80 ns for a dispatch on a `Dynamic` value. These positions suit calls made per plot, per attribute or per callback, not per element.

**What is new over discipline.** Plain Julia can reach the same shape by discipline: convert to a few concrete types first, pass only the fields a function needs, assert results after dynamic calls. On the prototype, a hand-written convert-then-plot function costs 36 ms per new table type, the trait route 35–47 ms. Three things are new:
1. **The bound is enforced,** so nothing in library code specializes on the user's type or on fields its bound does not declare.
2. **The targets of the dynamic positions are closed** by ownership and listed for a build.
3. **Code compiled per type lives in the image of the package that chose the type,** where no other load invalidates it, so that position costs build time and disk rather than session latency.

**Makie as the case in point.**
- **Today:**
  - Its pipeline specializes on the user's argument types before `convert_arguments` reaches its own types: 297 ms per new table type on the prototype.
  - At its inputs and recipe attributes it keeps values at `Any`. Inside its compute graph a node's type is fixed by its first value, so changing a colour from `:red` to a vector of colours fails in Makie 0.24 (`writeup/explorations/makie-rewrite.md` §1).
  - Julia's dispatch tracing shows what that `Any` hides. A first bar chart with a line reaches 1,940 distinct methods; other values of the same types add one; each new argument type or attribute shape adds 35–84.
- **In a trait world:**
  - user data reaches Makie through data traits, which user types implement or forward to a field; the conversion to Makie's own types, positions as `Point{N, Float64}` or `Point{N, Float32}` by the data's element type and colors as `RGBAf`, is library code bounded by those traits;
  - Makie owns traits for what users extend (colors, observables, recipes), held as dynamic values in scenes;
  - each compute step is a function bounded by its inputs.

  This is a sketch of a rewrite. Makie as written is reached by calls upward.

**What stays** is the trade-off at each position, as in every language with both generics and dynamic dispatch:
- more keys cost compiled code;
- a conversion the library writes costs a copy, and loses what its target cannot hold (dual numbers through a `Float32` pipeline);
- a dynamic position costs an indirect call or a dispatch.

## 4. Generic code is checked at its definition

**The choice.** Library code is checked once, where it is defined, against its bounds alone, at archetypes: stand-in keys whose operations and fields return values of their declared types and nothing more. Bounds with open parameters, and functions from above with open result types, are checked per signature at the first call.

**Other languages.**
- **C++0x** checked definitions through archetypes.
  - The concepts compiler was "more than 10 times slower", where vendors opposed anything over 20%.
  - Constrained code sometimes compiled to worse code.
  - The specification ran to 91 pages with 125 concepts.
  - Concepts were removed in July 2009 ([HOPL4](https://www.stroustrup.com/hopl20main-p5-p-bfc9cd4--final.pdf) §6.2).
- **C++20** checks only use: "Template constraints are applied to enforce the correctness of template use, not the correctness of template definitions" ([N3580](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2013/n3580.pdf)).
- **Doug Gregor's prediction** came true: without definition checking at the start "we will never get separate type checking", because every constrained template written before has incomplete requirements ([P0240R0](https://open-std.org/JTC1/SC22/WG21/docs/papers/2016/p0240r0.html)).
- **Rust, Swift and Mojo** check generic bodies before instantiation.

**Why it is cheap for us.** Two facts make a worker's code the same for every key:
1. A trait object has no methods but its traits' operations.
2. Every operation declares its result type.

The C++0x obstacles do not arise:
- **Name lookup inside constrained code** is settled by dispatch on the trait object.
- **Calls into unconstrained code** are ruled out by layering.
- **Implicit conversions** happen on declared concrete result types.

**Measured.** On the prototype the check reuses the existing worker checks unchanged.
- It finds `size(t)`, `typeof(t)` and `sum(t)` in a library before any type conforms.
- It checks a library of five functions in under 200 ms in a cold session.
- It takes only 3–4 ms off a new key's first call; most of a first call is compilation.

The gain is errors at the library's build, independent of conforming types, not latency.

## 5. Layering: trait-bound code calls only trait-bound code

**The choice.**

> **Ordinary code may use the trait world; the trait world uses only itself.**

Code outside the trait world runs for it only as a call upward, through a pointer at a declared signature.

**Other languages.** This is, word for word, the rule of C++0x ([HOPL4](https://www.stroustrup.com/hopl20main-p5-p-bfc9cd4--final.pdf) §6.2.5): "A constrained template cannot call an unconstrained one because it is not known what operations an unconstrained template uses." C++ treated it as a defect. Two objections ended definition checking ([P0557](https://www.stroustrup.com/good_concepts.pdf) §8.2):
1. **Gradual adoption:** a library with concepts "cannot use an older library before that library has been modernized".
2. **Scaffolding:** "we would be unable to insert debug aids, logging code, telemetry code … without affecting its interface". The evolution group's chair: "I cannot support any proposal for concepts that includes definition checking."

**Our answers:**
- **Gradual adoption:** trait wrappers, which bring a package written without traits into the trait world unchanged, and declared calls upward to code that stays outside ([Code written without traits](3-wrapping.md)).
- **Scaffolding:** outward doors. Logging, display and printing are calls upward with no inference edge.

**Mojo** runs layering the other way: static Mojo is the host, and Python is a value (`PythonObject`). Its planned in-language gradual typing never shipped. The clean boundary is the part that works; for us dynamic Julia already exists, so the boundary is what we build.

**A C++0x hole to avoid.** `late_check` let a value behave differently in two places, because a concept map did not apply inside unconstrained code. Our analogue is a value crossing upward. The boundary principle (only values cross, each translated by its bound) rules it out. A `Dynamic` value calls its conformance's operations wherever it is used.

## 6. Ownership, and who may implement

**The choice.**
- A package may add a method only where it owns the function or one of the types, in every signature the method applies to.
- Ownership can be delegated by its owner, never claimed.
- Unnamed implementations follow that rule.
- A named implementation, used only where a caller names it, may be written by anyone.
- Sealing enforces the rule at load ([The design in detail: Ownership](4-details.md#ownership)).

**Other languages.**
- **Rust.** The orphan rule is our rule: "either the trait must be local or the self-type must be local" ([Matsakis 2015](https://smallcultfollowing.com/babysteps/blog/2015/01/14/little-orphan-impls/)).
  - **Its reasons:** the "hashtable problem" (a value built with one `Hash` impl and queried with another), that any two crates must combine, and semver.
  - **Its pain:**
    - newtype boilerplate;
    - adapter impls with "no obvious home" (chrono × diesel; [RFC 2451](https://rust-lang.github.io/rfcs/2451-re-rebalancing-coherence.html));
    - "a kind of chilling effect" on interoperation, with Matsakis concluding the rule "will have to be weakened" ([2022](https://smallcultfollowing.com/babysteps/blog/2022/04/17/coherence-and-crate-level-where-clauses/));
    - a crate is compilation unit, optimization boundary and coherence boundary at once.
  - **Named impls** are being proposed ([BoxyUwU 2026](https://www.boxyuwu.blog/posts/an-incoherent-rust/)).
- **Swift** allows retroactive conformances, and its ABI lead regrets it: "Swift should never have allowed arbitrary retroactive conformances" ([Rose 2021](https://belkadan.com/blog/2021/11/Swift-Regret-Retroactive-Conformances/)). His preferred options are owner-only conformances, wrapper types, or named, non-discoverable conformances. Since Swift 6 a retroactive conformance warns, and which of two wins "is indeterminate" ([SE-0364](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0364-retroactive-conformance-warning.md)).
- **Mojo** has no extensions yet; its draft proposes an orphan-like placement rule.
- **Julia** has the rule as a convention: type piracy is discouraged, and Aqua.jl checks it.

**Why ours works.** Rule 3 is what Swift wishes it had. Our package boundary is not also the optimization boundary. Delegation gives adapter code a home when the owner agrees. Named implementations give it one when the owner does not:
- **The choice travels with the value.** A trait object carries its witness, so the implementation is chosen once, at the crossing, and Rust's hashtable problem cannot arise.
- **It changes nothing unnamed.** A named implementation changes no code that does not name it, so it is not piracy.
- **Ambiguity surfaces where it matters.** An unordered overlap that the later package cannot see raises an error where a call meets both, naming both modules, as Julia does for two modules exporting one name.

**Overlap and specialization.**
- **Rust:**
  - Specialization ([RFC 1210](https://rust-lang.github.io/rfcs/1210-impl-specialization.html)) has been unstable since 2016, because type checking and code generation could pick different impls once lifetimes were erased ([Turon 2017](https://aturon.github.io/blog/2017/07/08/lifetime-dispatch/)).
  - Turon's fix: do not let a more specific impl change associated types.
  - Rust made adding a blanket impl a breaking change.
- **Ours:**
  - Julia has no lifetimes. Its analogue is inference and dispatch disagreeing, which rule 4 settles by compiling against a fixed view.
  - A more specific implementation must declare the same parameter values as the generic one.
  - A generic implementation added later that overlaps a downstream specific one surfaces at the call, not at the load.

**Costs to expect:**
- newtypes for the foreign-trait, foreign-type case, where nobody names an implementation;
- the social cost of owners naming delegates;
- pressure for convenience.

## 7. Where compiled code lives, and when it binds

**The choice.**
- Compiled code is compiled against exactly the methods its owners' view holds (rule 4).
- It lives in the image of the package that chose the type: the trait module for the types it implements its traits for, the conformer for its own, a package depending on all of them for a combination, the session last.
- It is bound early: library code compiled for a key does not pick up a more specific method defined later downstream.

**Other languages.**
- **C++ `export`** (1996–2010) tried to compile templates separately and failed.
  - It took three person-years at EDG, "more work to implement than any three other C++ language features combined" ([N1426](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2003/n1426.pdf)).
  - An instantiation's meaning depended on its context, which was "effectively unpredictable", and consistency across translation units had to be diagnosed for the first time.
- **Rust** compiles generics in the instantiating crate, duplicated in siblings.
  - Sharing upstream instantiations "will impede optimization somewhat" and is off in optimized builds ([#48611](https://github.com/rust-lang/rust/pull/48611)).
  - Polymorphization was removed in 2024 ([MCP 810](https://github.com/rust-lang/compiler-team/issues/810)).
  - Compile times are the standing complaint ([Anderson 2020](https://www.pingcap.com/blog/rust-compilation-model-calamity/)).
- **Swift** compiles generic code once, with dictionary passing, for separate compilation and later ABI stability.
  - The price is performance cliffs: 20× from moving code into a package, "about 2 orders of magnitude" for unspecialized code ([SE-0460](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0460-specialized.md)).
  - The remedies (`@inlinable`, cross-module optimization, `@specialized`) are heuristics or annotations.
- **Mojo** caches type-checked code per package and generates machine code per program: a closed world.
- **Early versus late binding** is where C++ and separate compilation parted. Checked once against its constraints, `merge` would call the slow `copy` even for random-access iterators, so C++ chose late binding and lost separate compilation (Siek, [The C++0x "Concepts" Effort](https://arxiv.org/pdf/1201.0027) §3.5).

**Why ours.**
- **Export's meaning problem is removed.** Rule 4 makes compiled code mean what its owners' methods say, and a load that would change it is a refused pirate: consistency across packages is diagnosed.
- **No duplication.** Code lives where the type was chosen, once, not per sibling as in Rust.
- **No cliffs.** A bound gives specialization for what it can see by construction, not by heuristic, so there is no slow fallback path as in Swift.
- **Early binding is deliberate.** A type that needs its own behaviour implements the operations itself, or names an implementation.

**What we give up.**
- Code compiled once in its owner's image is never inlined into other packages, which is why Rust turns sharing off in optimized builds.
- Resilience: a package upgrade recompiles.

## 8. Static and dynamic positions, and their defaults

**The choice.**
- **Data** is compiled per key, statically.
- **Functions from above** are dynamic by default (`DynamicCall`); the library sets the default and the caller overrides it per value, with `compiled_call(f)` or `dynamic_call(f)`.
- **Data made dynamic** is chosen explicitly:
  - by the conformance (dynamic operations);
  - at the use, `Dynamic{X}`, or a trait name in a field or container.

**Defaults in other languages:**

| Language | Generic code over types | Function arguments | The other mode |
|---|---|---|---|
| C++ | compiled per type | per function type; `std::function` dynamic | `virtual`, type erasure, explicit |
| Rust | compiled per type | `impl Fn` per closure; `&dyn Fn` dynamic | `dyn Trait`, explicit, in the callee's signature |
| Swift | compiled once, witness tables; specialization an optimization | indirect unless inlined | `@inlinable`, cross-module optimization, `@specialized` |
| Mojo | compiled per type | compiled per closure type | none inside Mojo |
| Julia today | compiled per concrete type | compiled per function type if called in the body | `@nospecialize`, `Any` fields, FunctionWrappers |
| Ours | per key: what a bound can see | dynamic by default; the caller overrides | dynamic operations, `Dynamic{X}` |

Not researched for this note (from memory): Go compiles one generic instance per memory layout with dictionaries for operations, the closest relative of compiling per key; method calls through the dictionary are dynamic and not inlined. Haskell passes dictionaries by default, with `SPECIALIZE` pragmas.

**Why.**
- **Functions dynamic by default.** That is what Swift chose by design and Rust's practitioners recommend by experience ("prefer `&dyn Fn()` over `impl Fn()`", [matklad](https://matklad.github.io/2021/09/04/fast-rust-builds.html)), because compiling per closure costs much and rarely pays. Unlike Rust, the caller can override, so the choice does not leak into the library's API.
- **Data static per key.** Operations are direct calls, with no dictionary at run time.
- **Explicit dynamic data.** It follows Swift's lesson to spell the slow path where it is used, never implied, and to decide it before the ecosystem grows.
- **Dynamic values by dispatch, not pointer tables.** The review of the stored-values proposal measured pointer tables:
  - they break under world age and serialization, and under racing writes;
  - they cost 9 ns per call against 22–78 ns for dispatch, which closes its targets by ownership and needs no compilation for a first call from an image.

**Dynamic compatibility.** Rust restricts `dyn Trait` to traits without generic methods, `Self` results or `async fn`. Our operations are concrete signatures on the implementing type, and a dynamic value dispatches rather than using a table, so these restrictions hardly bind. They would if operations became generic over other bounds.

## 9. Error messages

**Where unreadable errors come from.** Three ingredients, all needed (`writeup/design-findings.md` §17, `experiments/errors/`):
1. **The failure is detected deep inside the library,** because the library never states what it requires.
2. **The whole path is printed,** 22–44 stack frames in the SciML cases.
3. **Every step is printed at its full concrete type,** because concreteness at the bottom forces the concrete type into every signature above. A SciML integrator's type is 3,553 characters, mostly the library's own nesting.

**Other languages.**
- **C++20 concepts** move detection to the call and name the failed requirement. But GCC 14's explanation of `std::ranges::sort` on a list is as long as the unconstrained one (29 lines against 28), types still print in full, and incomplete constraints still fail deep inside.
- **Rust's errors are short,** except where nested types must be printed; one Diesel error names a "30 page long type".
- **SciML** writes guidance messages by hand, for missing parameters, tuple states and failed automatic differentiation. Each states a requirement after the fact.

**Ours:**
- **Detection moves earlier,** to the conformance (missing operations, wrong result types) and to the library's build (definition checking).
- **Frames inside the trait world print by bound and key,** `step!(i::Integrator{Vector{Float64}, Params, Tsit5Cache})`, not by the integrator's full type. This is design: the prototype's printing of trait-object types by bound is written but not yet run, and its stack frames still show its machinery types (`writeup/design-findings.md` §17).
- **The limit:** bugs in user code above the trait world, as in all three SciML cases, are still found at run time. The traces get shorter, and requirements like "`f` is called with dual numbers" become part of the signature, as a second `Callable` bound.

## 10. The complexity budget

| | What grew out of control | Cost |
|---|---|---|
| C++0x | the concepts specification, archetypes, `late_check` | 91 pages, compiler 10 times slower, removed |
| Rust | trait solver, generic associated types, specialization | solver rewrite since 2023; generic associated types took 6.5 years; specialization unstable for 10 |
| Swift | recursive associated-type constraints, overloading in the type checker | generic signatures undecidable; "unable to type-check this expression in reasonable time" |
| Mojo | (avoided by design) | no inference from result types: "don't do it again" (Lattner) |

The expensive features were type-level computation in traits: associated types, recursion among them, higher-ranked bounds, overlap and negative reasoning. Traits as "operations and fields with declared concrete types" stay out of most of that space. Associated types are not the expensive part; reasoning about them symbolically is. Rust and Swift check a generic body once against its where-clauses, so an associated type is an unknown to normalize, equate and solve for, and recursion among them makes that undecidable. Our workers compile per concrete key, where an associated type is a field's type or a type function evaluated on a concrete type. Only definition checking reasons about them symbolically, and there they are first order: named variables with trait bounds, equal only through a shared variable, never recursive. Parameters are associated types, one value per conformance, as Rust's RFC 195 argued (`writeup/explorations/associated-types.md`).

## What the choices cost

The design restricts what trait-bound code may do, and only there.

1. **Calls out are calls upward.**
   - Code in a trait module reaches a package that stays outside, such as Makie, only through declared calls, with handles for what comes back.
   - A package whose work is state and effects, which is what Makie as written is, is reached that way and never run inside.
   - The C++0x objections and our answers are in §5.
2. **A stranger's piracy refuses a load.**
   - Once a sealed package is loaded, loading a pirate fails, naming it. The error reaches whoever loads the pirate, not its author.
   - The opt-out is plain Julia for the signatures it touches.
   - This is the most contested part. Measured on Makie's tree, 1042 of 1091 pirates are implementations their cores' wrappers would name ([Code written without traits: Sealing](3-wrapping.md#sealing)).
3. **Values crossing in must be closed.** Arguments from ordinary code must be one of:
   - values whose type conforms to the bound;
   - `Callable` functions;
   - `Dynamic` values;
   - values of trait-world types: a type that decides is admitted by its type, any other is walked at the entry.

   Inward doors (eval, deserialization, reflection) are available only as declared calls with a checked result.
4. **Trait objects see only their keys.**
   - Code in a trait module never sees the user's type. It builds a value like its input through constructor operations and the conformance's inverse, the user's object with fields replaced ([the design in detail: Results like the input](4-details.md#results-like-the-input)).
   - A trait object reads the user's object at every access, about 2 ns per call over plain Julia, loops unchanged.
   - A value kept beyond a call keeps the user's object, so it follows the user's fields.
   - A type converted on the way in, a computed view of its data, is not a conformance: the library converts explicitly, and the result does not follow the user's object.
5. **Types come first.** A type that matches a type-annotated method takes it, even when it also conforms to a trait bound of the same function. Reaching the trait method needs a type that no type method catches, or a newtype.
6. **Code written without traits is curated.** Capability traits with their conformances for Base's families, and each wrapper's implementations and conformances, are declared by hand. A package has one wrapper per environment.
7. **Dynamic positions are indirect.**
   - About 4 ns for a dynamic call.
   - 6.3 ns (7× plain Julia per element) for a dynamic operation.
   - 20–80 ns for an operation on a `Dynamic` value.
8. **Runtime work, not yet proven.**
   - Trait-bound code needs its own compiled instances, so Base code used by both worlds compiles twice.
   - It also needs an invalidation filter, a dispatch check, a hook that refuses a pirate before an image's methods enter the method table, and the check of globals and doors on compiled code.
   - These exist only as prototypes. The prototypes show one requirement on that runtime: entry code must have no static inference edge into Base's generic code, or loading DataFrames or Makie invalidates every entry.
9. **Smaller restrictions.**
   - Offering traits is per module and bottom-up.
   - One semantic exception: element types Julia derives from inference.
   - The orphan case: a foreign trait for a foreign type needs an owner, a delegate, a newtype, or a named implementation.
10. **Code is bound early and shared.**
    - Library code is compiled against the implementations its view holds, not looked up again where it is used.
    - Code compiled once in its owner's image is never inlined into other packages.

## Other options considered

- **One forwarding field per type,** for every trait it joins. Rejected as too restrictive: what a type means differs between traits.
- **Representations reached by any projection,** computed or copied, with a written inverse (the design until session 22). Replaced by keys (§3): computed projections copied, needed inverses and stale views, and packed several fields into one type.
- **The edge-level rule:** let trait-bound code call ordinary packages freely, compile only concrete calls against the current methods, and make abstract ones dynamic. Rejected for its built-in cliff at abstract calls, copies of much library code, and no closed world for AOT.
- **Absorbing dependencies:** each package brings its ordinary dependencies into its own world. Rejected because two packages that absorb Makie conflict as soon as one defines a recipe.
- **Deriving conformance from the methods that exist.** Rejected (§2).
- **Trait bounds that compete with types:** trait-bounded methods ranked like abstract types of the other kind. Rejected because the conflict would surface only in an application that loads both packages. The conflict is between traits and those abstract types; between concrete types and traits there is none.
- **Explicit wrapping at the call,** `f(ColTable(x))`. Rejected because adopting traits would change every caller.
- **Function types in the type system,** `Float64 -> Float64`. A far larger change to Julia than one trait whose only operation is checked at every call.
- **Better invalidation precision.** Largely upstream in Julia 1.12 already, and not enough on its own.
- **A global invalidation filter,** ignoring later definitions everywhere. Unsound for ordinary code.
- **Hidden type parameters** for fields declared by bounds. Rejected as un-Julian (§1).
- **Dynamic values through pointer tables.** Rejected for world age, serialization and races (§8).
- **Selecting implementations by imported scope,** as Scala's implicits do. Rejected: an entry is compiled once and does not know its caller's module.

## Predictions from other languages, and their status

| # | Prediction | Source | Status |
|---|---|---|---|
| 1 | "Explicit conformance is viral" | C++0x | answered: one-line `@implement`, family declarations, wrappers |
| 2 | Layering attacked for gradual adoption and scaffolding | C++0x | answered: wrappers and calls upward, outward doors (§5) |
| 3 | A `late_check`-like inconsistency where values cross upward | C++0x | ruled out by the boundary principle; an example and a test are still to write |
| 4 | Pressure for retroactive conformance | Swift, Rust | answered: named implementations |
| 5 | A later generic implementation overlapping a specific one | Rust | answered: surfaces at the call, names both |
| 6 | A more specific implementation changing types | Rust | answered: same parameter values required |
| 7 | Load-time checks scanning all methods | Swift | open: index by function and type |
| 8 | Demand for a storable dynamic value | Swift, Rust | answered: `Dynamic{X}` |
| 9 | Shared code not inlined across packages | Rust | stated (cost 10) |
| 10 | Early binding misses a more specific method | C++0x | stated: deliberate, with escapes (§7) |
| 11 | Implicit defaults added later break things | Swift | decided: concreteness is opt-in per trait and decided when a trait is published |
| 12 | Type-level computation in traits | all four | kept out: symbolic reasoning about associated types; associated types themselves adopted in first-order form |
