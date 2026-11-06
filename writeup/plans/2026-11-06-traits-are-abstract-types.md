# The references under "traits are abstract types"

Status: **proposal** (2026-11-06, mine; W-105). Not normative. Nothing in the references is changed yet. Written in the main session, no subagents, from a full reading of the four references at f19f5ac.

The request (the user, 2026-11-06): "Unification changes and simplifies the referecne design substantially. Unification states "Traits are AbstractTypes" From this it follows that Traits can occur everywhere AbstractTypes can, and that they are parametrized the way AbstractTypes are parametrized, including Trait{<:T} and the like. This explicitly contradicts a number of things that are currently in the reference design. It also should eliminate a lot of the reference design. So before we continue implementation work on the unified perspective, we need to actually fix and simplify the reference. Carefully go through the four reference documents and work out the implications of unification." And, while this was written: "If the ports have to be substantially changed that is fine. They were built under old assumptions and should be considred informative rather than limitative."

## Contents

0. [Summary](#0-summary)
1. [The premise, and what follows from it](#1-the-premise-and-what-follows-from-it)
2. [Where the references contradict it](#2-where-the-references-contradict-it)
3. [What it eliminates](#3-what-it-eliminates)
4. [Choices the premise leaves open](#4-choices-the-premise-leaves-open)
5. [Gaps: what no reference states yet](#5-gaps-what-no-reference-states-yet)
6. [Section by section](#6-section-by-section)
7. [Deviations, open issues, other documents](#7-deviations-open-issues-other-documents)
8. [The order of the rewrite](#8-the-order-of-the-rewrite)

---

## 0. Summary

- **The premise:** a trait is an abstract type. It differs from a closed abstract type in two things only: members may join it after their definition, and it has a contract checked at each membership. Everything else is Julia's: where it may be written, how it is parametrized, what a value of it is, how dispatch treats it.
- **The references were written for a different model.** In it, a trait is a bound that turns a value into a *trait object*, a view distinct from the value, that is valid only inside trait modules, and that has its own storage forms (`Kept{X}`), annotations that are not types (`x::Dynamic{X}`, `Iterable{Compiled{Shape}}`, `Opened{X}`, `::Like{t}`), errors (`TraitBoundError` where Julia's dispatch would pick another method) and an entry per function. Compiler §7, written for unification today, still carries part of that model: "a trait's name in a field means `Kept{X}`", three Core wrapper types with a subtype rule.
- **What follows needs no decision** (§1.2, F1 to F18). The four that remove the most:
  - **F4, the value is the value.** No trait objects, views or witnesses. `typeof(t)`, passing `t` on, returning it: all as for any abstract-typed argument.
  - **F3, variance.** Item positions are Julia's variance: `Iterable{<:Shape}`. The crossing views, `Through{Y, A}`, `CompiledItems`, the item-parameter annotations and most of traits §6.6, §8.2 and §8.3 go.
  - **F7, storage.** A field or container typed `X` holds members, as one typed by an abstract type does. `Kept{X}`, `Compiled{X}` and the seven-column table of traits §6.3 go.
  - **F18, signatures are Julia's.** Every annotation in a method's signature is a type, since a method at a trait is a plain method, written anywhere, with no macro around it. `::Like{t}`, `Opened{X}`, `x::Dynamic{X}` as "a bound with a default", the field-bound sugar and tuples written `(X, Y)` cannot stay as they are.
- **What the premise leaves open: eight choices** (§4). Recommended in brief:
  - **Q1:** the references state the unified design; TraitWorld on julia-1.13 becomes *the prototype*, summarized by deviation rows; its mechanism moves out of the references.
  - **Q2:** sharing per key is a classification of each method (fully bounded or open); `@trait_module` turns "open" into an error; the module is a bundle of options, not a world.
  - **Q3:** Julia's compile rule: per key for every caller. Erasure where a method's argument (`@nospecialize`) or a trait's default asks for it. The first-seen rule goes.
  - **Q4:** `Dynamic{X}` is an ordinary struct of the library, a member of `X` by forwarding to its one field. It is a member of `X` and `X`'s supertraits, not of other traits its object is in.
  - **Q5:** a tuple of traits becomes an intersection type in Julia's type system (a new type constructor, spelling to choose); a bundle is a `const` alias of one.
  - **Q6:** `Callable{A, S}` is a set every type belongs to. Its call is checked where the callee's static type is a `Callable`, and erased by default.
  - **Q7:** a declared field is a stored field of that name, as Swift's protocol properties are the type's own. Field mappings go; no port uses one.
  - **Q8:** `struct S <: X` is allowed; `S` is checked at its first use, as a family member is.
- **Gaps** (§5): the compiler's rule for an operation called on a value typed by its trait (the declared result, asserted; the split); per-type compilation of open methods; where the contract is kept for the compiler; `Keyed` as an element of fact signatures; two names `Keyed` (BaseTraits' trait and the Core key type).
- **Size:** traits.md's chapters 6 and 7 (about 360 lines) become one short chapter. Chapters 5 and 8 shrink to Julia's rules plus what is new. lowering.md (835 lines) becomes a short page. Compiler §2's two-owner mechanism leaves the design for §7.6. facts.md changes in its terms, §6 and §9.
- **W-98 waits** for Q4, Q5, Q8 and F12: they change what the type system implements. The rest bears on later stages.

---

## 1. The premise, and what follows from it

### 1.1 The premise

- `@trait X{P…}` declares an abstract type `X{P…}`. Its `TypeName` is open: a type may become a member after its definition.
- Beyond an abstract type it has a **contract**: operations with declared argument and result types, declared fields, and parameters as associated types. It is checked at each membership.
- The decisions already taken stand ([decisions](../record/decisions.md) §5):
  - membership is transitive;
  - parameters are invariant, with `X{<:T}` and `X{>:T}` at the place of use;
  - option (e): negatives never fold, guards, memberships invalidate nothing;
  - C7: a closed type other than `Any` before an open set;
  - one CodeInstance per MethodInstance and policy;
  - the code slot.

### 1.2 What follows, with no decision

| # | Consequence | It replaces |
|---|---|---|
| F1 | **A trait stands wherever a type stands:** any method's signature in any module; a field's type; a type parameter (`Vector{X}`, `Dict{K, X}`, `Ref{X}`); `Union{Nothing, X}`; `where {T <: X}`; a struct parameter's bound; `isa`, `<:`, `typeassert`, `convert(X, x)`; `Type{<:X}`; a declared supertype (`struct S <: X`, `abstract type A <: X`). | traits §2 (bounded functions only in trait modules; decision 41); §3.1 (a bare trait name on a further argument refused); §5.1 (`Vector{<:ColTable}` refused) |
| F2 | **`X` alone is `X{P…} where {P…}`,** a `UnionAll`, as `AbstractVector` is. `v::KVec` takes a member at any parameter value. | traits §5.1's rule that a `Dynamic` annotation must fix the parameters its results use: the erased key always carries the member's parameter values |
| F3 | **Parameters follow Julia:** invariant, `<:` and `>:` at the place of use, `where` variables with bounds, the diagonal rule, a variable inside a parameter (`KVec{Vector{T}}`). So `Iterable{Shape}` is the trait at the item type `Shape`, and an item position is `Iterable{<:Shape}`. | traits §5.1 (a variable for part of a parameter refused), §8.2 (a trait's name as a bound's parameter names an item position), §6.6, §8.3; lowering §13.1 |
| F4 | **A member's value is a value of the trait,** and passing it passes it. Nothing converts it, and no trait object exists. Inside `f(t::X)`, `t` is the caller's value. `typeof(t)`, `t === x`, passing it on, storing it and returning it mean what they mean for any abstract-typed argument. | traits §5.2–§5.4, §5.3's refusals, §5.6 "trait objects never go up bare", §6.5's last bullet, §6.9; open issue 138 (returning the argument) |
| F5 | **Supertraits are supertypes.** `@trait B <: A` makes `B <: A`. A member of `B` is a member of `A`: `@implement B T` makes `T <: A` with no separate declaration, and its check covers `A`'s contract. Where `T` also has its own membership in `A`, the two must agree (today's agreement rule). | traits §3.6 ("`T` must conform to `A` too, by its own implementation") |
| F6 | **Dispatch is Julia's,** with C7 and the guards. A value that matches no method reaches the most specific method that applies, or `MethodError`. | traits §5.1 and §5.5: `TraitBoundError` for a value at other parameters or a broken shared variable; "does not reach the fallback" |
| F7 | **A field, container element or `Ref` typed by a trait holds members,** boxed, as one typed by an abstract type does. A struct parameter bounded by a trait is Julia's bound: the default constructor sets it to the value's type. | traits §7.1–§7.4 (`Kept{X}`, `Compiled{X}`, a trait's name in storage meaning `Kept{X}`, the constructor as a bound); compiler §7 (intro, §7.5); lowering §13, §13.2 |
| F8 | **A default is a method at the trait;** forwarding is served by the trait's method for each operation. Plain code that calls an operation on a member reaches them. The member's own methods are more specific and win. | traits §3.2 and §4: "defaults and forwarding serve trait code only … plain code … finds no method" |
| F9 | **Assignment converts as Julia's does:** `convert(X, x)`, the identity for a member. A library's `Base.convert(::Type{ColorSpec}, ::Symbol)` is ordinary Julia. | traits §7.3's first-seen point at a store |
| F10 | **A family or a set-in-set membership makes every matching type a member when it is declared.** Memberships only grow, so a member that fails the contract cannot become a non-member. Its check runs at its first use and raises `ImplementError` there; `isa` stays `true`. | traits §4.7, §4.8, §11.1: "refused at its first use" |
| F11 | **A generic implementation is the membership of a set in a set,** `@implement GTable Indexable{Vector{Float64}} begin … end`, with its methods at that set. A computed condition cannot be a membership. Overlaps are Julia's ambiguities, reported at the membership that creates them (compiler §7.3). Forwarding carries through by itself: `GTable`'s methods call `Indexable`'s operations on the value, which the trait's methods forward. | traits §4.8's `R: Trait` constraints, its overlap rules, T-9, T-30, T-79 |
| F12 | **One instance per set and member.** A type may reach a set by several paths. The set's parameters other than inputs are associated types, so all paths must give the same instance. A declaration that would give a second instance is refused. | nothing: a rule to add (traits §3.4, compiler §7.2) |
| F13 | **Ownership and Lemma O carry over, with memberships as supertypes.** The owner of a set is a stakeholder of each concrete signature that names a member, from the membership's world. A method at a set by the set's owner, on any function, is no pirate. | traits §5.5's "who may add a bounded method", now ownership alone; lowering L-3's restriction |
| F14 | **Errors:** where Julia's dispatch decides, Julia's error applies. A value at other parameters, a broken shared variable, a missing method at an operation's declared argument types: `MethodError`. A keyword of the wrong type: `TypeError`. `TraitBoundError` and `TraitArgumentError` lose their cases. `TraitUseError`, `ImplementError`, `OwnershipError` and `PirateError` keep theirs. | traits §5.1, §5.5, §5.7, §9 |
| F15 | **`conforms(T, X)` is `T <: X`.** | traits §14, lowering L-5 |
| F16 | **The encodings go:** entries, workers, views and witnesses, trait objects (`TObj`), `HeldValue`, records as methods with sentinels, `Untyped` fallbacks, the struct rewrite, `@stmt`, needs and attributes fixed at a module's end, the untyped callers' table, the crossing views. | lowering §3–§13, §17 |
| F17 | **Sharing per key is a property of a method,** not a rule every method obeys. Code is shared per key only where the body reaches the argument through the contract alone, and a method at a trait may do anything with its argument (F4). So the compiler finds, per method and argument, whether it is *fully bounded*. What happens to a method that is not is Q2. | traits §5.3's refusals as a language rule |
| F18 | **A method's signature is Julia's.** A method at a trait is a plain method, defined anywhere, with no macro around it. So every annotation in it is a type, with the meaning of a type. An annotation that is not a type has no place: `::Like{t}` (a function `like(t, x)` instead), `c::Opened{X}` (the body opens the value), `x::Compiled{X}` and `x::Dynamic{X}` as "a bound with a default" (Q3), `ms::Iterable{Compiled{Mark}}` (F3), `t::(X, Y)` (Q5), the field-bound sugar `f::(F <: Bound)`. | traits §1's grammar (`Bound`, `Attribute`, `ItemParam`, `Opened`, `Result`'s `Like`), §5.6, §6.3, §6.4, §7.4 |

Two of these reverse rules the user decided explicitly, so I list them for an explicit "yes":
- **F1** reverses decision 41 (the user, 2026-10-21: "For issue 41: Refuse."). The premise states the reversal: "Traits can occur everywhere AbstractTypes can".
- **F8** reverses "defaults and forwarding serve trait code only".

---

## 2. Where the references contradict it

Each row is a statement in force today that the premise makes false. The rewrite removes or replaces each.

| # | Where | It says | Against |
|---|---|---|---|
| 1 | traits §2 | Bounded functions exist only in trait modules. Outside, a trait's name on an argument is refused, "now and with traits in the type system". Outside, a value is taken as `Kept{X}` or by a type. | F1 |
| 2 | traits §7.2; §6.3's table; compiler §7 (intro: "a trait's name in a field meaning … `Kept{X}`"), §7.5 ("`convert(Kept{X}, x)` is how a plain value enters a field declared with a set's name"); lowering §17's table | A trait's name in a field or container means `Kept{X}`; with traits in the type system, everywhere. | F7 |
| 3 | traits §3.1 | A trait's bare name on an operation's further argument is refused. | F1 |
| 4 | traits §5.1, §6.3 | `x::Compiled{X}` and `x::Dynamic{X}` on an argument accept any member, not only values of that type. | F18, F4 |
| 5 | traits §5.1, §5.5, §9 | `TraitBoundError` at the call for other parameters, a broken shared variable, a violated `where` bound; "it does not reach the fallback". | F6, F14 |
| 6 | traits §5.1 | A `where` variable for part of a parameter is refused. | F3 |
| 7 | traits §5.1, §6.6, §8.2, §8.3 | `Iterable{Shape}` names an item position. A `Vector{Circle}` and a `Vector{Any}` are taken by it. | F3 |
| 8 | traits §5.1 | A trait inside a container's type in a signature (`Vector{<:ColTable}`) is refused. | F1, F3 |
| 9 | traits §5.2–§5.4, §6.5 (last bullet), §6.9 | A bounded function receives a trait object. It may not pass it bare, store it bare, return it bare or ask its type. A trait object is seen only through the traits it entered with. | F4 |
| 10 | traits §3.2, §4 | Defaults and forwarding serve trait code only; plain code finds no method. | F8 |
| 11 | traits §3.6 | `T` must implement each supertrait by an implementation of its own. | F5 |
| 12 | traits §4.7, §4.8, §11.1 | A family member, or a type through a generic implementation, that fails the contract is refused, so it does not conform. | F10 |
| 13 | traits §4.8 | Constraints `R: Trait` and `R <: Type`, with predicates; overlap rules of their own. | F11 |
| 14 | traits §5.6 | `::Like{t}` as a result annotation. "Trait objects never go up bare." | F18, F4 |
| 15 | traits §5.7 | Keyword defaults are evaluated "after each value is seen through its bound"; a bounded keyword refuses with `TraitBoundError`. | F4, F14 |
| 16 | traits §6.2 | Entering the trait world at six kinds of place, each a conversion point. An operation's result declared with a trait "is `Dynamic`". | F4, F7 |
| 17 | traits §6.4 | `with_dynamic(x)` and `compiled_for(x)` without a trait, passing dispatch as markers; `Opened{X}`, "only an annotation: no value has that type". | F18 (and Q4) |
| 18 | traits §6.5 | A kept value is seen through every trait its object conforms to, also a `Dynamic` one. | F4, under Q4 |
| 19 | traits §7.4 | A struct's constructor without parameters is the bound, applying the first-seen rule and `Callable`'s default. The bound at the field: `f::(F <: Bound)`. | F7, F18 |
| 20 | traits §11 | `Kept{X}` and `Compiled{X}` count as concrete. | F7 |
| 21 | traits §14 | The table "an abstract type / a trait", with different rows for parameters ("set per implementation"), supertypes ("requirements, by an implementation of its own"), values, dispatch. `conforms` beside `<:`. | the premise; F5, F15 |
| 22 | compiler §7.5 | `Dynamic{X}`, `Compiled{X}` and `Kept{X}` are Core types, members of `X` by a rule of `subtype`. | F7, F16 (and Q4) |
| 23 | compiler §2, facts §6.1–§6.4 | Code of the two modes lives side by side under two cache owners. | the decided §7.6 (one CodeInstance per MethodInstance and policy), stated beside it rather than in its place |
| 24 | facts §1 | "Trait code: the code of trait modules"; boundary methods are "TraitWorld's entries and `conformance` methods". | F16, Q2 |
| 25 | facts §2.2 | "A new implementation of a trait: lowering makes it a definition that wins at no existing fact." | option (e) (compiler §7.1): a membership changes no fact, and guards cover the calls it could change |
| 26 | facts §9 | "Lowering writes it as `split_call`." | the compiler's operation rule (§5, G1) |
| 27 | lowering, all of §1–§16 | The trait language realized by entries, workers, views, records and rewrites. | F16 |

---

## 3. What it eliminates

| Goes | Where today | In its place |
|---|---|---|
| trait objects, views, witnesses, archetype witnesses | traits §5.2, §6.5, §12; lowering §5–§7 | the value itself (F4); per-key code by the compilation signature (compiler §7.5) |
| entries, workers, `Untyped` fallbacks, the joint-method check at a module's end | traits §5.5; lowering §8–§10 | Julia's dispatch with C7; the ambiguity report at a membership (compiler §7.3) |
| `Kept{X}`, `Compiled{X}`, `HeldValue{X}` | traits §7; lowering §13 | a field typed `X` (F7); `Dynamic{X}` alone (Q4) |
| the table "what each spelling means, by position" (seven columns) | traits §6.3 | one meaning per spelling: a trait's name is the trait; `Dynamic{X}` is a type |
| the first-seen rule and its six entry points | traits §6.2, §6.3 | Q3 |
| `Opened{X}`, set-less `with_dynamic`, cast markers passing dispatch, `rewrap` as a primitive | traits §6.4 | `Dynamic{X}(x)` and unwrapping (Q4) |
| the warning on an annotation of a function neither exported nor public | traits §6.3, §9 | nothing: annotations are types or Julia's `@nospecialize` |
| item positions, `Through{Y, A}`, `CompiledItems`, `DynamicItems`, `DynamicValues`, a user's `Vector{Any}` taken as it is | traits §6.6, §8.2, §8.3; lowering §13.1 | variance (F3); a container of another element type is converted (`Shape[...]` or `Dynamic{Shape}.(v)`) |
| trait casts | traits §6.9 | `isa` and dispatch (raw members); unwrap and rewrap (`Dynamic{X}`) |
| `conforms(T, X)` | traits §14 | `T <: X` |
| `TraitBoundError`'s dispatch cases, `TraitArgumentError` | traits §5, §9 | `MethodError`, `TypeError` (F14) |
| `::Like{t}` as an annotation; the pending result `LikeResult` and its inversion at the entry | traits §5.6; lowering §11 | `like(t, x)`, a function that rebuilds by the membership's forwarding field |
| the struct rewrite: the stripped bound, the generated constructor, `getproperty` for `Callable` fields, the field-bound sugar | traits §7.4; lowering §13.2 | Julia's struct (F7) |
| `R: Trait` constraints, predicates, overlap rules of generic implementations | traits §4.8 | set-in-set memberships (F11) |
| the `@stmt` wrapping, the module-end fixing of needs, attributes and keep flags | traits §2; lowering §8.3 | top-level statements as Julia runs them; the classification per method (Q2) |
| records as methods of `@max_methods 1` functions with sentinels; family registries and builders; `_member_record` | lowering §3, §4 | entries on `TypeName`s (compiler §7.2), the contract where the compiler reads it (G7) |
| family builders fixed in callers by `fold_call` | lowering §4.6; compiler §4.4's one use | entries with patterns: a member's key is known from its entry |
| `known_type`'s use at the entry | compiler §4.1; lowering §8.2 | none (Q3); the primitive stays only if something else uses it |
| the type printer registry | compiler §5.3; lowering §16 | `Keyed` printed as the key by `show` (decided) |
| the second cache owner in the product setting: dispatch from facts code to facts copies, inlining across owners, edges for a second owner | compiler §2.3–§2.8; facts §6.1–§6.3 | one CodeInstance per MethodInstance and policy (compiler §7.6, decided), the code slot |

**Open issues answered by the premise:** 132 (`where {I, J <: I}` is Julia's), 135 (a bounded constructor is a method at its bound), 138 (returning the argument), 36 (already closed toward this). Open issue 137 (`eltype` of a bounded argument) changes: under F4 `eltype(t)` is a call on the value. Whether it keeps a method fully bounded is a question of what the contract includes (G11).

---

## 4. Choices the premise leaves open

Each: the question, the options, my recommendation, and what it changes.

### Q1. How the references describe a design that is not built yet

- **The situation.** Today "Implemented" means "in TraitWorld on the patched julia-1.13". The premise describes the unified build, of which stage 1 is begun. Gates B and C (the synthesis plan) were to decide whether levels 1 and 2 are adopted.
- **Options:**
  - **(a)** The references state the unified design. Status lines refer to the unified build: most sections become Planned, with W-98 to W-104. TraitWorld on julia-1.13 is **the prototype**, the platform the demonstrators run on until the unified build replaces it. Each reference gets a short note on the prototype and a few deviation rows, one per encoding family, as L-1 to L-6 are now. Deviation rows for rules that survive and that the prototype gets wrong keep their IDs. The prototype's mechanism leaves the references:
    - lowering §2–§16 go to a description page, `writeup/design/prototype.md` (non-normative), or TraitWorld's own documentation;
    - compiler §2.3–§2.8 go to `design/julia-changes.md` §2, which already inventories them.
    - Gates B and C become build gates: does the unified build reach level 1 and level 2 at the stated cost? If one fails, the design is revised, and the alternative is recorded.
  - **(b)** Two layers in each reference: the prototype as Implemented, the unified design as Planned beside it. This keeps everything that (a) removes, and doubles each section.
- **Recommendation: (a).** It is what the request asks for, and the only form in which the references get simpler.
- **What it changes:** every reference's front matter and status index; lowering.md becomes a short page on the unified expansion (§6.4); state.md describes the prototype as the running system.

### Q2. Trait modules, and the contract in method bodies

- **The question.** F17: a method at a trait may use its argument outside the contract. Does the language refuse that, report it, or only compile differently?
- **Options:**
  - **(a)** Every method at a trait is classified, per argument, as **fully bounded** or **open**. Fully bounded means the body reaches the argument only through the contract (G11 says exactly what that admits). A fully bounded method is compiled per key; an open one per type, as Julia compiles it. A scope that declares `bounded` turns "open" into `TraitUseError` at the definition. `@trait_module` is the bundle of `facts`, `no_pirates` and `bounded`, with the prefixes for concreteness and fully typed mode. It is written as `module M; @trait_module; … end` (today's Planned form, T-81). No source is rewritten, so Revise works.
  - **(b)** Refuse open methods at traits everywhere. This contradicts F4 and F1: a method on an abstract type may do anything with its argument.
  - **(c)** Classification only, no refusal anywhere. A library loses the guarantee that its functions are shared.
- **Recommendation: (a).** This is level 3's surface, which the premise brings forward: "trait modules dissolve into declarations on a scope; a function is classified fully bounded or open where it is defined". The exploration's rule 4 and §5.1 state it. Definition checking at archetypes becomes the check under the `bounded` flag (compiler §7.5).
- **What it changes:** traits §2, §5.2–§5.4, §9; facts §1's "trait code"; compiler §7.5 (G2).

### Q3. How a member is compiled at a trait position

- **The question.** Today a plain value's attribute is decided where it enters: by the first-seen rule, the trait's default, an annotation and a cast, in that order. Under the premise a value enters nothing, so what is left is a compile policy, a choice of speed. Julia's own rule: every caller gets code specialized for the value's type; `@nospecialize` widens it; `@specialize` overrides a module's `@nospecialize`.
- **Options:**
  - **(J) Julia's rule, per key.**
    - Code at a trait position is compiled per key for every caller, static or dynamic. A dynamic call dispatches on the value's type and runs the code for its key: today's `Compiled` function barrier.
    - **Erasure**, today's `Dynamic`, is code compiled once at the erased key `X{p…}`, with operations dispatched at run time to declared results. It applies where the method says `@nospecialize t::X`, where the trait declares it the default, or where the value is a `Dynamic{X}` (Q4).
    - A method may override the trait's default with `@specialize`.
    - The trait's dynamic default keeps its exception for types of the trait world, so Base's functions passed to `Callable` positions stay specialized.
    - `@default_compiled_for_self` becomes the rule, so the declaration goes.
    - A struct's parameter is the value's type (F7). A library that wants a `Dynamic` field wraps the value in its outer constructor.
    - Cost: an untyped caller (the prompt, a `Vector{Any}`) compiles per key at an unannotated position, as Julia compiles per type.
  - **(F) The first-seen rule as a compile policy.**
    - A static caller that knows the type gets the key; a dynamic caller gets the erased code. This needs two compilation signatures per method and tuple, as compiler §7.5 has them (the review's M4).
    - Annotations at the position become `@specialize` and `@nospecialize`.
    - Erasure carries without wrapping: an erased caller's callees see unknown types, so they are erased too.
    - Cost: the mechanism of two compilation signatures, `cache_with_orig` forced for keyed instances, and a policy that plain abstract types do not have.
- **Recommendation: (J).**
  - It is the abstract types' rule, and it has one compilation signature per method and tuple.
  - What (F) buys, untyped callers compiling nothing in the library, is what the trait's dynamic default buys where a library wants it: a solver's model, `Callable`.
  - Values still carry where they are wrapped (Q4).
  - It reverses the first-seen rule, a decision of the user, so it needs an explicit "yes".
- **Sub-point.** Under either option a parameter whose value is a trait (with a contract) counts as concrete for `@enforce_concrete_only`, as `Kept{X}` does today. Its operations have declared results, so code over it is typed. `Any` and closed abstract types do not count.
- **What it changes:** traits §5.1, §5.7, §5.8, §6 (rewritten as one chapter on keys and erasure), §7.4, §11, §13; compiler §7.5 (one compilation signature; `known_type` loses its user).

### Q4. `Dynamic{X}`: what carries erasure

- **The question.** With `Kept{X}` and `Compiled{X}` gone (F7), what is `Dynamic{X}`, and what are the casts?
- **Recommendation:**
  - **An ordinary struct of the library, not a Core type:** `struct Dynamic{X}; object::X; end`. `@trait X` declares `Dynamic{X}`'s membership in `X`, forwarding to `object` (for a parametric trait, the family `Dynamic{X{T}} where T` in `X{T}`).
  - Its forwarding field has an abstract type, so its key is the erased one. Today's rule for a field of abstract type gives exactly `Dynamic`'s meaning: one compiled copy, each operation dispatched when it runs, with its declared result.
  - No rule in `subtype`, no special case in intersection: C-20 (the wrappers in intersection and dispatch) retires.
  - `Dynamic{X}(x)` wraps; `compiled_for(d)` returns the object; a cast always names the trait. `with_dynamic(x)` without a trait goes: no type is a member of every trait. `Opened{X}` goes: a body that wants per-key code opens its value, `f(c::Column) = g(compiled_for(c))`. `rewrap(g, d)` is `Dynamic{X}(g(compiled_for(d)))`, a helper if one is wanted.
  - **The consequence to accept:** a `Dynamic{X}` is a member of `X` and its supertraits only, not of the other traits its object belongs to. `has_mass(f::HasMassMatrix) = true; has_mass(f) = false` answers `false` for a wrapped function with a mass matrix. A `Vector{Dynamic{Column}}` of pooled columns does not reach `f(c::(Column, Pooled))`. Raw members reach every trait they are in, since dispatch is on their type. Under Q3 (J), a raw value at an erased position stays raw, so the case arises only where a value is wrapped on purpose. Wrap as `Dynamic{(Column, Pooled)}` (Q5) where both are wanted.
- **The alternative:** dispatch looks through `Dynamic`, selecting by the object's run-time type. That is value-dependent dispatch outside the type system, which the premise excludes.
- **What it changes:** traits §6.4, §6.5, §7; compiler §7.5; lowering §13; C-20.

### Q5. Tuples of traits

- **The question.** `(X, Y)` is "the trait of values in both", an intersection. Julia's type language has unions, not intersections, and `t::(X, Y)` is not a type (F18). Tuples are used for several bounds, a bundle's meaning, `Dynamic{(X, Y)}`, `Callable` at several signatures, and supertrait lists.
- **Options:**
  - **(a) An intersection type constructor** in Julia's type system (spelling to choose: `Both{X, Y}`, `And{X, Y}`, `All{X, Y}`).
    - Subtyping: `S <: Both{X, Y}` when `S <: X` and `S <: Y`; `Both{X, Y} <: Z` when `X <: Z` or `Y <: Z`.
    - It is normalized as `Union` is: flattened, sorted, deduplicated.
    - It is more specific than each member.
    - A bundle is a `const` alias, `const Table = Both{ColTable, RowTable}`.
    - Its members are derived, not declared: transitivity through it follows from the rule.
  - **(b) Derived entries:** a `Both{X, Y}` typename per pair, with an entry for `S` declared whenever `S` joins the second (the exploration's form). The cost is a product of memberships, and the entries must follow redeclarations.
  - **(c) No anonymous intersections:** every combination is a named subtrait with declared memberships (`@trait Table <: (ColTable, RowTable)` with each type declared). Several bounds on one argument go; `Callable` at several signatures needs another form.
- **Recommendation: (a).**
  - It is the principled form, Julia's `Union` dual.
  - It makes bundles plain aliases.
  - It lets `Dynamic{Both{X, Y}}` exist with no further rule.
  - Its cost is a type-system addition in the stage W-98 is building: subtype, intersection, specificity, the normal form.
- **What it changes:** traits §3.6 (bundles), §3.7, §5.1, §5.8; compiler §7.2 (a new case); W-98's scope.

### Q6. `Callable`

- **The question.** Today any callable conforms to `Callable{A, S}` without a declaration, and each call is checked. Under the premise `Callable{A, S}` must be a type with members. The user named `Callable{A, <:Any}` as one (2026-11-06).
- **Options:**
  - **(a) A set every type belongs to,** by a rule: `T <: Callable{A, S}` for every `T`, `A`, `S`.
    - Its one operation is the call. A call whose callee's static type is a `Callable{A, S}` (an argument, a field, an element) is checked: the arguments against `A` (`MethodError`), the result asserted to `S` (`TypeError`).
    - Its default is erasure, one compiled copy per signature, through the `:caller_world` thunk (compiler §3.1).
    - Several signatures are an intersection (Q5); a call picks the signature its argument types match, where it is compiled.
    - `Callable{A, <:Any}` leaves the result unchecked. `Callable` without parameters is the function kept before its signature is known (open issue 102).
    - Consequences:
      - Dispatch cannot choose among methods by a function's signature: two methods that differ only in a `Callable` bound are ambiguous for every function. Today's design has no such rule either.
      - A struct parameter `F <: Callable{A, S}` is the function's type, so a call through that field is the function's own call, unchecked. The check applies where the static type is the `Callable`.
      - T-87 (`Callable` as a trait with input parameters) retires.
  - **(b) Memberships on demand:** the library declares `F ∈ Callable{A, S}` at a function's first meeting with a `Callable{A, …}` position, with `S` inferred. Dispatch by signature becomes possible. A redefinition of the function must redeclare.
  - **(c) A wrapper the caller builds,** `Callable{A, S}(f)`. Plain functions no longer meet a `Callable` bound without it.
- **Recommendation: (a).** It keeps today's meaning, "anything callable, checked at each call", and puts the check where a static type can carry it.
- **What it changes:** traits §5.8, §7.5; lowering §12; compiler §7.5 (the erased call); T-87, T-90, L-31, L-36.

### Q7. Declared fields

- **The question.** Under F4, `t.name` is `getproperty(t, :name)` on the value, in every method. A field mapping (`@implement Named Book name => title`) renames a property per trait. But the property namespace belongs to the type, and two traits mapping one name differently would conflict.
- **Options:**
  - **(a) Swift's rule:** a declared field is a stored field of that name, read and written by `getfield`. A type whose `getproperty` differs from `getfield` at a declared field's name does not conform, and is refused at the implementation, naming the field. Mappings and paths of stored fields go. Data stored under another name conforms through a wrapper type (§15) or through operations (`HasProperty`).
  - **(b)** Keep mappings, served by a method of `Base.getproperty` at the trait. Two traits mapping one name for one type are ambiguous, reported at the membership. Plain code reading `book.name` then sees the mapping.
  - **(c)** Declared fields read through the trait, with a spelling other than `.`.
- **Recommendation: (a).** No port and no fork declares a field mapping (a grep of the ports' `src/` and the whole `forks/` tree for `@implement … a => b`, 2026-11-06), and the Planned paths are not built. It makes the key's field parts the stored fields by construction, which compiler §7.5's calling convention assumes.
- **What it changes:** traits §3.3, §4.4, §4.5 (T-31 retires), §6.7; lowering §4.5.

### Q8. `struct S <: X` and `abstract type A <: X`

- **The question.** F1 allows a trait as a declared supertype. Compiler §7.2 has it as a final membership. When is `S` checked against the contract, given that its methods come after the struct?
- **Options:**
  - **(a) At its first use,** as a family member is (F10).
  - **(b) At the end of `S`'s module,** with a hook Julia does not have yet (the plain-module form of trait modules needs it too).
  - **(c)** Only with an `@implement X S` after the methods; a `struct S <: X` without one is refused at the module's end.
- **Recommendation: (a), and (b) where the hook exists.** It is one rule for every membership that is not checked at its declaration. A member of a closed abstract type under a trait (`abstract type A <: X`; `struct S <: A`) is checked the same way.
- **What it changes:** traits §4 (a form of joining), §4.9, §14; compiler §7.2.

### Three small ones

- **q-a.** `Core.Keyed{X, R, F}` and BaseTraits' trait `Keyed{K, V}` share a name. The Core type is never written by users and prints as the key, so rename it (`Core.TraitKey`, or another).
- **q-b.** `like(t, x)` replaces `::Like{t}`: the value `x` rebuilt into `t`'s type by the membership's forwarding field and mapped fields. Called from code that knows `t`'s type, it is compiled for it.
- **q-c.** Overrides stay fixed at the implementation (traits §4.9). A later method of an operation that a default serves for the type is still refused. Under the premise it would otherwise change the type's key (a member keyed by its fields alone would become its own receiver), which is a redeclaration. I keep the rule; following it as a redeclaration is the alternative.

---

## 5. Gaps: what no reference states yet

| # | Gap | Where it belongs |
|---|---|---|
| G1 | **The operation rule.** A call of an operation of `X` on a value whose static type is `X` (or `X{p…}`, or the erased key) infers as the operation's declared result. The result is asserted at the call, and the call splits over `X`'s first four members, the rest through the table. This is today's `split_call` inside `Dynamic`'s methods, made the compiler's. It is sound because each member was checked against the contract, and a member checked only at first use (F10) is caught by the assertion. | compiler §7 (new section); facts §3, §9 |
| G2 | **Open methods compiled per type.** Compiler §7.5 records "the classification 'open'" but not what is then compiled: the method specialized per type, as Julia does, with no keyed instance. | compiler §7.5 |
| G3 | **`Keyed{X, R, F}` in a call's signature.** Per-key code passes its argument on as `Keyed{…}`. Is that an element of a fact signature, and does the negative-fold exclusion treat it as open? A later membership can add a member with the same key, which is also a member of a closed type with a more specific method. | compiler §1.2, §7.2, §7.5; facts §3 |
| G4 | **`struct S <: X`**: its check (Q8), and whether it is an entry or `S`'s supertype (the stage-1 work makes it the supertype). | traits §4, compiler §7.2 |
| G5 | **One instance per set and member** (F12): checked by the library before `jl_declare_membership`, or by the runtime. | traits §3.4, compiler §7.2 |
| G6 | **The trait's method per operation** (F8): one method at `X`, from `@trait`, serving defaults and forwarding. Per-key code folds it to the receiver's method or the default's body. It is an open set's method, so C7 ranks it below every closed type's. | traits §3.2, §4.3; lowering |
| G7 | **Where the contract lives for the compiler:** the declared results (G1), the fields (the calling convention), the defaults. Options: on the set's `TypeName`, or on the trait's methods as declared results (D9's declared result on `Method`, which then promises the result for every member). | compiler §7.5 |
| G8 | **The candidates of a split:** registered by the library at each membership, as today, or read from a set-to-members index. | compiler §4.2, §7 |
| G9 | **`Callable`'s erased call** (Q6): the `:caller_world` thunk, made per signature, as the operation rule's form for `Callable`. | compiler §7.5 |
| G10 | **Compiling ahead** from a membership: the methods at the set and its supersets, at the new member's key, found through the set-to-methods index of compiler §7.3. | traits §13; compiler §7.3, §7.8 |
| G11 | **What "fully bounded" admits.** Admitted: operations of `X` and its supertraits; declared fields; passing the argument to a position whose type is `X` or a supertrait; storing it where the type is `X` or a supertype; returning it; `===`. Not admitted: `typeof`, `isa` against another trait, passing it to other functions. Open issue 137 asks whether `eltype(t)` is admitted where an equation defines a parameter as `eltype(Self)`. | traits §5.3's successor; compiler §7.5 |

---

## 6. Section by section

**Keep** means the section's rules stand, with wording updated (trait object → value, trait code → code under the facts policy). **Rewrite** means its substance stands in a new form. **Goes** means its subject leaves the reference, for the place named.

### 6.1 traits.md

| Section | Disposition | Why |
|---|---|---|
| §1 Syntax summary | **Rewrite:** `@trait`, `@implement` and the scope declarations; methods, types, fields and structs are Julia's. `Bound`, `Attribute`, `ItemParam`, `KeptType`, `Cast`, `Opened`, `Like`, the struct parameter's trait bound and `Membership` go. `BoundedClosure` is Julia's `(u::ColTable) -> …`. | F1, F18 |
| §2 Trait modules | **Rewrite** per Q2: a bundle of scope options in the plain-module form. "Only inside", "`Kept` outside", `@stmt`'s order, "a package's module line cannot carry it" and the module's end for a redefined function go. | F1, F16, Q2 |
| §3 intro | **Rewrite:** "an abstract type with a contract". | premise |
| §3.1 Operations | **Keep**, without the refusal of a trait's bare name on a further argument. A call is checked by dispatch, and its result where the receiver's static type is the trait (G1). | F1, F14 |
| §3.2 Defaults | **Rewrite:** a default is the trait's method; plain code reaches it. | F8, G6 |
| §3.3 Fields | **Rewrite** per Q7. A field typed by a trait is a field of that type, not `Kept{X}`. | F7, Q7 |
| §3.4 Parameters | **Keep**; add F2 and F12. Input parameters stay: a type may be a member of several instances of an input family. | F2, F12 |
| §3.5 `Self` | **Keep.** The new value comes back as a value, or as a `Dynamic{X}` from a `Dynamic{X}`. | F4 |
| §3.6 Supertraits, bundles | **Rewrite:** supertraits are supertypes (F5); a bundle is an alias (Q5). The agreement check stays for a type with its own membership in the supertrait. | F5, Q5 |
| §3.7 Tuples | **Rewrite** per Q5. | Q5 |
| §4 intro | **Rewrite:** an implementation is a membership declaration plus the contract check. "It discards no trait code" becomes option (e). "Defaults and forwarding serve trait code only" goes (F8). The record moves to compiler §7.2. | F8, F16 |
| §4.1–§4.3, §4.6 | **Keep.** | — |
| §4.4 Field mappings, §4.5's mapping cases | **Goes** under Q7 (a). | Q7 |
| §4.7 Families | **Keep the form;** a failing member raises at first use and stays a member (F10); "a member's implementation is fixed at its first use" becomes the check alone. The image record of a member's check stays as a rule. | F10, F16 |
| §4.8 Generic implementations | **Rewrite** as the membership of a set in a set (F11). | F11 |
| §4.9 Checks at the declaration | **Keep;** add the check of `struct S <: X` (Q8) and F12. | Q8, F12 |
| §4.10 Types that only convert | **Keep.** | — |
| §5 intro | "Bounded functions exist only inside trait modules" **goes.** | F1 |
| §5.1 Bounds | **Rewrite** to Julia's rules (F3, F6), plus several bounds (Q5) and erasure at a position (Q3). Refusals of variables inside parameters and of traits inside containers go. | F3, F6, F18 |
| §5.2 What a bounded function receives | **Goes:** the value (F4), one sentence in §5. | F4 |
| §5.3 What trait code may do | **Rewrite** as "fully bounded" (G11) with Q2's refusal. | F17, Q2 |
| §5.4 Internal functions | **Keep in substance:** an unannotated function called with the argument is compiled at the key and classified with its caller. | G11 |
| §5.5 Dispatch | **Rewrite:** C7, Julia's ambiguity with the report at a membership, the fallback as Julia's, ownership for who may add a method. `TraitBoundError`, the module-end check and L-3, L-50, T-83, T-95 go. | F6, F13 |
| §5.6 Results | **Rewrite:** ordinary result annotations; `like(t, x)` (q-b); `withfields` stays; "never go up bare" goes. | F4, F18 |
| §5.7 Keywords, defaults, varargs | **Rewrite** as Julia's, with the per-key rule for varargs; `TraitBoundError` becomes `TypeError`. `Callable` with keywords per Q6. | F14, F18 |
| §5.8 `Callable` | **Rewrite** per Q6. | Q6 |
| §6 (all of it) | **Rewrite as one chapter, "Compiling: keys and erasure":** the key (§6.7, kept), erasure and when it applies (Q3), `Dynamic{X}` (Q4), costs (§6.8, kept). §6.2's entry points, §6.3's table, §6.4's casts, §6.6 and §6.9 go. | F4, F7, Q3, Q4 |
| §7 Kept values | **Goes into the new §6 and storage:** a field typed `X` (F7); `Dynamic{X}` (Q4); a struct parameter as Julia's (F7, Q3); equality of `Dynamic{X}` stays; functions kept per Q6. | F7, Q4, Q6 |
| §8.1 BaseTraits | **Keep;** rename per q-a. Base's types join as members of sets (`AbstractVector{T} <: Indexable{T}`). `asvector` stays as Julia's struct. | q-a |
| §8.2, §8.3 Item positions, containers | **Rewrite** as variance (F3): `Iterable{<:Shape}`; a `Vector{Any}` is converted first. | F3 |
| §8.4 Algorithms | **Keep.** | — |
| §9 Checks | **Rewrite** the table (F14, Q2, Q8). | — |
| §10.1–§10.3 | **Keep.** "An implementation is a method" becomes "a membership declaration, owned as a method would be"; "trait code" becomes code under the facts policy. | F13 |
| §10.4 No sealing | **Keep;** add that Base's abstract types are closed (no later memberships), and sealed sets (Optional, PE-19). | compiler §7.1 |
| §11 Concreteness, fully typed | **Keep;** the kept forms' line per Q3's sub-point. Operations on values typed by a trait count as declared, not as faults. | F7 |
| §12 Printing | **Rewrite:** the key printed in signatures; `Dynamic{X}` printed with its object. Trait objects and TraitWorld's hidden frames go. | F4, F16 |
| §13 Compiling ahead | **Keep the rule;** the mechanism goes to compiler (G10). `JULIA_TW_AHEAD` and `@workload` become the library's. | G10 |
| §14 Membership | **Becomes chapter 2, "Traits are abstract types":** the premise, membership, subtyping, transitivity, variance, closed and open sets, `struct S <: X`. The comparison table compares a closed abstract type with a trait. `conforms` goes. | premise, F15 |
| §15 Named implementations | **Keep** (Planned). | — |
| §16 Status index | **Regenerate.** | — |
| §17 Deviations | §7.1. | — |

### 6.2 compiler.md

| Section | Disposition | Why |
|---|---|---|
| Front matter, summary | **Rewrite:** the intended design is §1, §3–§7. julia-1.13 is the prototype's platform. The summary's row 2 becomes the policy per method. | Q1 |
| §1.1 The interpreter | **Rewrite:** the facts mode is a property of an inference, chosen by the method's policy. The owner token stays for the test bed and for `return_type`'s cache. | §7.6 |
| §1.2–§1.6 | **Keep;** add G1 and G3. | G1, G3 |
| §2.1, §2.2, §2.10 | **Keep** (the module option, the method flag, `--trim`). The boundary flag keeps its meaning; its users in the prototype go. | — |
| §2.3–§2.8 | **Goes** to `design/julia-changes.md` §2 as the prototype's mechanism; one deviation row. §7.6 takes their place. | Q1, decided §7.6 |
| §2.9 Images | **Rewrite** for one CodeInstance per MethodInstance and policy. | §7.6 |
| §3 | **Keep.** `:caller_world` serves `Callable`'s erased call (G9). | — |
| §4.1 `known_type` | Loses its user under Q3 (J). **Keep** as a primitive useful without traits, or retire. | Q3 |
| §4.2, §4.3 | **Keep:** the primitive and the table behind the operation rule (G1, G8). | G1 |
| §4.4 `fold_call` | Loses its user (family builders). **Keep** as a primitive, or retire. | F16 |
| §5.1 Hooks | **Keep** (strict mode, overrides). | — |
| §5.2 Field-offset intrinsics | **Keep:** the calling convention's writable fields. | §7.5 |
| §5.3 Type printers | **Goes** with its user (piece 17); `Keyed` prints by `show`. | F16 |
| §5.4, §6 | **Keep.** | — |
| §7 intro | **Rewrite:** drop "`Kept{X}` in a field"; syntax as traits.md. | contradiction 2 |
| §7.1–§7.4 | **Keep;** add F12 and Q8 to §7.2, and Q5's case if (a). | F12, Q5, Q8 |
| §7.5 | **Rewrite:** one compilation signature (Q3); `Dynamic{X}` as a library struct (Q4); `Compiled`, `Kept` and `convert(Kept{X}, x)` go; add G1, G2, G7, G9, G11. | Q3, Q4 |
| §7.6–§7.8 | **Keep.** | — |
| Deviations | C-6 and C-16 retire (owner-copy cases); C-20 retires under Q4; C-3, C-7, C-8, C-9, C-14 stay (their mechanisms stay in the design and are carried to the unified build); C-18, C-19, C-21 to C-26 stay. | — |

### 6.3 facts.md

| Section | Disposition | Why |
|---|---|---|
| Summary | **Rewrite:** "code of the two modes is cached apart, under two cache owners" becomes one CodeInstance per MethodInstance and policy; "entries are boundaries" goes; "trait modules are compiled by facts" becomes "methods whose policy is facts". | §6.5 |
| §1 Terms | **Rewrite:** "trait code" → code under the facts policy; "boundary method" without TraitWorld's examples; "cache owner" for the test bed and `return_type` only; stakeholders of a concrete signature include its types' sets, from their memberships' worlds (F13); edges include membership cells and result edges. | F13, Q2 |
| §2.1 G1 | **Keep.** | — |
| §2.2 G2 | **Rewrite** the statement with §6.5 (result edges, the slot). "What invalidates nothing" restated by option (e): a membership changes no fact; a family member's fold goes. | contradiction 25 |
| §2.3, §3, §4.1, §4.2 | **Keep;** §3 gains G1's form (an operation at a value typed by its trait: a run-time site with a declared result) and G3. | G1, G3 |
| §4.3 | **Rewrite** "per owner" for one owner. | §6.5 |
| §5 Run-time sites | **Rewrite:** the callee runs its own policy's code; `jl_apply`'s case is no longer special. | §6.5 |
| §6.1 | **Keep** the four kinds. | — |
| §6.2–§6.5 | **Rewrite as one rule,** §6.5's: the policy is the method's. | §6.5 |
| §7, §8 | **Keep.** `return_type`'s answers keep their owner token. | — |
| §9 The `Dynamic` split | **Rewrite** as the operation rule (G1), with its candidates. | G1 |
| §10 | **Keep;** "trait code" per §1. | — |
| §11 Images | **Rewrite** for one owner; add memberships in images (compiler §7.8). | §7.6, §7.8 |
| §12, §13 | **Keep,** with the terms. | — |
| Deviations | F-6, F-7, F-9, F-13 stay. | — |

### 6.4 lowering.md

Under Q1 (a) it becomes a short page, "what the library's macros expand to", on compiler §7's interfaces:
- **`@trait X`:**
  - the abstract type with the open bit;
  - the operation functions;
  - the trait's method per operation (G6);
  - the contract where the compiler reads it (G7);
  - `Dynamic{X}`'s membership (Q4);
  - supertraits as set-in-set memberships.
- **`@implement X S`:**
  - the checks;
  - the block's methods;
  - `jl_declare_membership` with the key and the forwarding field;
  - `Expr(:latestworld)`;
  - the candidates (G8);
  - compiling ahead (G10).
- **Methods at traits:** nothing to expand.
- **The scope declarations:** the module option, `no_pirates`' hooks, the `bounded` flag.
- **`like`, `withfields`:** their rebuild by the membership's forwarding field.
- **Checks and their records:** where each runs, what an image keeps.

Every current section goes to the prototype's description (Q1): §1–§16 as written, and §17's table becomes the prototype's deviation summary, L-1 to L-6. Rows L-7 to L-50 describe the prototype's mechanism and go with it, except where a rule survives (§7.1).

---

## 7. Deviations, open issues, other documents

**Deviation rows** (IDs are permanent; each that goes stays as *Retired*, pointing to the section that holds its subject):
- **traits**
  - Retire, with the rule they measured: T-22, T-23 (becomes the prototype's summary row), T-30, T-31, T-35 (rewritten if `Dynamic{X}`'s constructor operation still fails), T-36, T-39, T-48, T-55, T-74, T-75, T-76, T-79, T-83, T-87, T-88, T-89, T-94, T-95.
  - Stay as the prototype's, where their rule survives: T-2, T-4, T-6, T-7, T-9 (if overlaps keep a rule), T-10 to T-15, T-19, T-20, T-21, T-28, T-32, T-34 (in part), T-37, T-38, T-49, T-52, T-56, T-57, T-68, T-81 (becomes the plain-module form's), T-82, T-84 to T-86, T-90, T-91 to T-93.
- **lowering:** L-1 to L-6 become the prototype's summary; L-7 to L-50 go with the prototype's description.
- **compiler:** per §6.2.
- **facts:** none retire.

**Open issues:**
- Answered by the premise: 132, 135, 138 (§3).
- Changed: 137 (G11), 140 (unchanged in substance; it is about entries).
- New, when the user decides: whichever of Q1 to Q8 stays open. Weak points found on the way get issues of their own: G3, and Q4's consequence if it is not accepted.

**Decision log:** each "yes" to F1, F8 and Q1 to Q8 is a row with the user's words. The reversed rows move to the log's superseded section:
- decision 41 (a trait's name on an argument refused outside trait modules);
- the first-seen rule, if Q3 (J);
- the kept forms;
- item positions as a trait's name in a bound's parameter;
- open issue 82's "seen through every trait" for `Dynamic` values;
- the field-mapping decisions, if Q7 (a).

**`design/alternatives.md`** gains "Traits as abstract types: options not taken": trait objects and views; `Kept{X}` as storage; the first-seen rule (if J); a dispatch that looks through `Dynamic`; derived entries for intersections; `Callable` by on-demand membership or by wrapper; field mappings by a trait's `getproperty`.

**Other documents with stale copies,** to fix after the references, in this order:
- the glossary: trait object, kept value, `Compiled`, `Kept`, entry, worker, view, witness, item position, first-seen rule, trait module, bound, boundary method, cache owner, cast;
- `design.md`, the rationale;
- `intro/`, the teaching, and its examples in `experiments/docs-examples/`;
- `state.md`;
- `design/other-languages.md`, whose comparisons assume trait objects;
- `porting-to-traits.md`;
- the record INDEX.
- The evidence's numbers stand: they measured the prototype and say so.

**The ports and demonstrators** follow the design once the unified build can run them (the user, 2026-11-06: "informative rather than limitative"). The forms they use that the premise removes are mechanical to change: `Kept{…}`, `Opened{…}`, `compiled_for`, set-less casts, `Iterable{Shape}` item positions.

---

## 8. The order of the rewrite

1. **The user decides:**
   - F1 and F8 explicitly, and the rest of F1–F18 as a list;
   - Q1 to Q8, and q-a to q-c.
2. **traits.md first,** since it wins on meaning:
   - the new outline: chapter 2 "Traits are abstract types", then declarations, memberships, methods, compiling (keys and erasure), storage, collections, checks, ownership, concreteness, scopes, printing, compiling ahead;
   - a new status index;
   - its deviation table.
3. **compiler.md:**
   - §7 corrected, with G1 to G11 placed;
   - §2's mechanism moved to `julia-changes.md`;
   - its deviation rows.
4. **facts.md:** the terms, §2.2, §5, §6, §9, §11.
5. **lowering.md:** the short page; the prototype's description moved, as one commit with the L- rows.
6. **The record:**
   - the decision log, alternatives, open issues;
   - a grep for every changed term across the repositories (CLAUDE.md, rule 2).
7. **W-98 resumes** on the corrected compiler §7.2: it needs Q4, Q5, Q8 and F12. The glossary, `design.md` and `intro/` follow as their own items.
