# One way to write generics: abstract types as traits

Status: **exploration** (2026-10-28, an exploratory agent's analysis, Fable; not adopted). Not normative.

Serves W-83. The user's question: "Right now Julia has two more or less distinct ways to write generic code: Multiple Dispatch on functions written for abstract types (in the case of no type annotations at all Any), and traits with the compiled/dynamic switch. I wonder whether a unified perspective is possible, where we have one way to write generics. This would probably mean that abstract types are just traits. There are several subtleties with this: E.g. Trait modules, Dynamic, Facts mode. But it has the potential to simplify the design by eliminating a lot of the 'how trait and ordinary code interact' questions."

Read for it: the references in full ([traits](../reference/traits.md), [facts](../reference/facts.md) §1–§6, §9–§12, [compiler](../reference/compiler.md) §1–§2, §7, [lowering](../reference/lowering.md) §5–§9, §17), [the rationale](../design.md), [the tutorial](../intro/traits-for-julia.md), [alternatives](../design/alternatives.md), [other languages](../design/other-languages.md) and [its research record](../record/other-languages-research-2026-10-16.md), [the decision log](../record/decisions.md), [open issues](../open-issues.md), W-27, and the three fresh-ideas proposals of 2026-10-28 ([SciML](../plans/2026-10-28-fresh-ideas-sciml.md), [Makie](../plans/2026-10-28-fresh-ideas-makie.md), [DataFrames](../plans/2026-10-28-fresh-ideas-dataframes.md)). No Julia ran. Line numbers are of the files at the design repository's head on 2026-10-28. The primary sources for other languages are in §9 and the source list.

## Contents

1. [Summary: the answer](#1-summary-the-answer)
2. [What each does today](#2-what-each-does-today)
3. [The unified model](#3-the-unified-model)
4. [What it removes, and what it adds](#4-what-it-removes-and-what-it-adds)
5. [The subtleties, one by one](#5-the-subtleties-one-by-one)
6. [Where the current design would change](#6-where-the-current-design-would-change)
7. [Migration](#7-migration)
8. [Costs and risks](#8-costs-and-risks)
9. [Prior art](#9-prior-art)
10. [The smallest experiments](#10-the-smallest-experiments)
11. [Sources](#11-sources)

---

## 1. Summary: the answer

**Partly: yes for the language, no for one distinction, which moves rather than disappears.**

- **Yes.** An abstract type and a trait are the same kind of thing: a named set of types with a declared membership. Every rule of the design can be stated once, for that one thing. An abstract type is a trait whose contract is empty and whose members are all declared where they are defined. `Any` is the trait that declares nothing and that every type belongs to. An untyped function `f(x)` is a function bounded by `Any`. Julia's specialization is `Compiled`; Julia's `@nospecialize` with dynamic dispatch is `Dynamic`; the facts rule is what `Dynamic` means when the contract is empty. Under this reading there is one dispatch, one compile rule, one attribute rule. Trait modules dissolve into two module options that already exist (compiled by facts; no pirates). The "trait world" and its boundary stop being a world and become a per-function property.
- **No, for one distinction.** The design's two dispatch tiers (types first, then traits; [traits §5.5](../reference/traits.md#55-dispatch-types-first-then-traits)) are not an artefact of TraitWorld's encoding. They are what makes an implementation invalidate nothing ([the rationale §2.2](../design.md#22-step-2-refuse-the-pirates-that-would-win-and-fully-typed-code-is-never-invalidated), "Implementations are the extension point"). If `@implement X S` made `S <: X` in Julia's own dispatch, it would change what `f(::S)` selects wherever `f(::X)` exists: a definition that wins at a fact, and a load that invalidates. So one construct survives with two kinds of membership: **declared with the type** (`struct S <: X`: a fact, Julia's static dispatch, invalidates callers as any stakeholder's definition does) and **declared later** (`@implement X S`: resolved at the trait tier when the code runs, without an edge, invalidates nothing). "Abstract type" and "trait" become names for the two kinds of membership of one construct. That is less than the user asked for, and more than the design has today.
- **What it simplifies.** The interaction rules disappear: what trait code may do with a trait object (§5.3), internal functions (§5.4), a trait's name refused outside trait modules (§2; decision 41), the three kept forms (§7), the entries per shape (lowering L-3), the boundary principle as a rule. They are replaced by one classification the compiler makes per function: *fully bounded* (the body uses only its bounds' contracts) or not. A fully bounded function is compiled per key and checked at its definition; any other function is today's plain Julia, compiled per concrete type, with the facts rule at its run-time sites. The `fully_typed` report already computes most of this.
- **What it costs.** Multiple membership in Julia's subtyping (a real change to `jl_subtype`, type intersection and ambiguity detection); ambiguity between methods on two unrelated traits is reportable only when a common member appears (Julia issue #5's problem, Fortress's exclusion relation, the design's T-83); no gain for an abstract type that declares no contract (`Number` stays `Number`); and the decided rule that a trait's name is refused outside trait modules (open issue 41) is reversed.
- **What to do with it.** It does not change the design's rules. It changes the *framing* of W-27 (traits in the type system): not "encode a trait beside abstract types" but "make an abstract type a trait with static members, and let a trait add dynamic members". §10 gives three experiments that decide whether Julia's subtyping can carry it. Until they run, W-27's direction should stay open, not decided.

---

## 2. What each does today

### 2.1 What an abstract type does

From the Julia manual ([types](https://docs.julialang.org/en/v1/manual/types/), [interfaces](https://docs.julialang.org/en/v1/manual/interfaces/)) and the subtyping papers ([Zappa Nardelli et al. 2018](https://hal-univ-tlse3.archives-ouvertes.fr/INRIA/hal-01882137); [Belyakova et al. 2024](https://janvitek.org/pubs/pldi24.pdf)):

| What | How |
|---|---|
| names a set of types | a node of the type graph; "cannot be instantiated, and serve only as nodes in the type graph" |
| membership | nominal, declared in the subtype's definition, `struct S <: A`; one supertype per type (`DataType.super`); concrete types are final |
| dispatch | by subtyping: the most specific applicable method; ambiguity is an error at the call unless a more specific method exists; detected at method definition by type intersection, which is `Union{}` for two unrelated abstract types |
| parameters | invariant: `Point{Float64}` is not a `Point{Real}`; a subtype fixes a supertype's parameters (`struct MyArr{T, N} <: AbstractArray{T, N}`), so they are associated types by construction ([associated types](associated-types.md) §1); covariance by `AbstractVector{<:Real}` (a `UnionAll`) |
| `isa`, `<:` | a run-time test and a static relation, folded by inference where known; usable anywhere, including `where` clauses and `Type{T}` arguments |
| as a field or element type | boxed storage; a read gives the abstract type; each operation on it is a dynamic dispatch, or Julia's speculation over the methods that match today (`max_methods`) and union splitting over small unions |
| as an argument | the method is compiled for the argument's concrete type at each call (specialization); the body may call anything on the value |
| contract | none that is checked: Base documents the interfaces (`iterate`, `getindex`, `size`), with required and optional methods; Base's fallbacks throw ("satisfied" is a `MethodError` found late); "Holy traits" (`IndexStyle`, `IteratorSize`) are values computed from a type that steer dispatch |
| the lattice | `Union`, `UnionAll`, covariant `Tuple`, the diagonal rule, `Type{T}`; subtyping as implemented is undecidable; a restriction to use-site variance in value types restores decidability and fits nearly all code in the corpus |

### 2.2 What a trait does, beyond that

From [traits](../reference/traits.md):

| What | Where |
|---|---|
| membership after the fact, by a stakeholder, any number per type | §4, §10.1, §14 |
| a declared contract: operations with result types, fields with types, checked at `@implement` and at the library's definition | §3, §4.9, §9 |
| associated types by fields, equations or stated values; bounds on them; input parameters (Planned) | §3.4 |
| the key: code compiled for what the bound can see, so types sharing a key share code | §6.7 |
| `Compiled` and `Dynamic` per value; defaults and casts; values carry through storage | §6, §7 |
| kept values with declared results; the call-site split over declared implementations; `Callable` | §7, §5.8, [facts §9](../reference/facts.md#9-the-dynamic-split) |
| no edge to the method table from any of it: an implementation invalidates nothing | [facts §2.2](../reference/facts.md#g2) |
| dispatch below every type, above `Any`; the joint-method rule among unrelated bounds | §5.5 |

### 2.3 What is really different

Strip the mechanism away and two differences remain. Everything else in §2.2 follows from them.

1. **A declared contract or an open one.** `f(x::AbstractArray)` may call anything on `x`; `f(x::ArrayLike)` may call only what `ArrayLike` declares. The closed contract is what gives definition checking, keys, declared results at dynamic positions, and the list of targets for AOT. The open contract is what gives Julia's "write it and see" and its speculation over the method table.
2. **Membership that is a fact or membership that is not.** `S <: A` is fixed where `S` is defined, so dispatch at the concrete signature `(S,)` is a fact, and a method `f(::A)` applies to it from the start. `@implement X S` comes later, from another package. If it made `S <: X` in Julia's dispatch, every compiled call `f(s::S)` whose fact selected `f(::Any)` would now select `f(::X)`: an invalidation caused by a load. The design avoids that by resolving trait membership at run time inside the entry, with no edge ([lowering §8.2](../reference/lowering.md#82-the-entry); [facts §2.2](../reference/facts.md#g2), "What invalidates nothing").

Both are differences in *what compiled code may assume*, not in what a bound is. That is the opening for a unified model: one bound, and two properties of it that the compiler reads.

---

## 3. The unified model

Stated plainly, as rules. Each has a small example. "Set" is used for the one construct; the spellings are illustrative.

### Rule 1. One construct: a set of types with declared membership

- A set is declared with `abstract type A end` or `@trait X begin … end`. Both make a set. The second may declare a contract (rule 2).
- A type joins a set in two ways:
  - **with its definition:** `struct S <: A end`, or `struct S <: (A, X) end` (several sets; the first is a Julia supertype as today, the others are memberships declared with the type). Membership declared this way is **static**: a fact of the type.
  - **after the fact:** `@implement X S`, by a stakeholder of `S` or `X` ([traits §10.1](../reference/traits.md#101-who-may-implement)). Membership declared this way is **dynamic**: read when code runs, never a fact.
- `S <: X` and `s isa X` are true for both kinds. Inference folds a static membership; it never folds a dynamic one to `false` ([traits §14](../reference/traits.md#14-membership) says this already).
- A set's supertypes are requirements: `@trait B <: A` means every member of `B` is a member of `A`, by its own declaration. `abstract type B <: A end` means the same, with the members' declarations implied by the tree. One relation.
- Parameters are associated types: one value per member, fixed by a field, an equation, the member's own parameters (`struct MyArr{T, N} <: AbstractArray{T, N}`) or stated at the implementation ([traits §3.4](../reference/traits.md#34-parameters-and-associated-types)). Invariance is what "one value per member" means. Input parameters stay the extension the fresh-ideas round decided (open issue 85).

```julia
abstract type Number end                      # a set with no contract, all members static (Base today)
@trait Shape begin                            # a set with a contract
    area(s::Shape)::Float64
end
struct Circle <: Shape; r::Float64; end       # a static member: checked here, like @implement
area(c::Circle) = π * c.r^2
@implement Shape Square                       # a dynamic member, declared later by Square's owner
```

### Rule 2. A contract, possibly empty

- A set may declare operations with result types, fields with types, defaults and concreteness ([traits §3](../reference/traits.md#3-trait-declarations)). A set that declares nothing has the empty contract. `Any` has the empty contract and every type as a static member.
- Joining a set with a contract is checked, for static and dynamic members alike ([traits §4.9](../reference/traits.md#49-checks-at-the-declaration)). A static member is checked at its definition; where its methods come later in the same module, at the module's end. A member of a family, at its first use, as today.
- An abstract type of Base gains a contract when Base writes one into it. Until then BaseTraits' families (`@implement Indexable A where {A <: AbstractVector}`) give the same set a contract from outside, as today ([traits §8.1](../reference/traits.md#81-basetraits-traits-for-bases-concepts)).

### Rule 3. One dispatch, with a partial order that keeps implementations non-invalidating

- A method's applicability is `x isa A` for each argument. Among applicable methods, the most specific wins, by the subset relation among sets, as Julia ranks today.
- **The order between the two kinds of membership is a rule of the order, not a second mechanism:** a method selected by a *static* membership of the argument's type beats one selected only by a *dynamic* membership. Among methods selected by dynamic memberships, a subset beats its superset, and unrelated sets at one position need a joint method ([traits §5.5](../reference/traits.md#55-dispatch-types-first-then-traits)). `Any` is below both: every method whose bound the value meets by a declaration beats the untyped method.
- **Why this order:** dispatch among static memberships is a fact at a concrete signature, so Julia's static dispatch records it. Dispatch among dynamic memberships is decided when the code runs, with no edge. A new dynamic membership therefore changes no fact. That is the rule that makes an implementation invalidate nothing, kept as an ordering rule instead of as "types first, then traits".
- What the order gives up: a dynamic member can never override a method on one of its static supertypes. That is today's cost 4 ([other languages](../design/other-languages.md#what-the-choices-cost)), unchanged, and it is what lets a library adopt contracts one function at a time.

```julia
describe(m::AbstractMatrix) = "a matrix"      # static membership of Matrix{Float64}
describe(t::ColTable) = "a table"             # dynamic membership of Matrix{Float64}, by @implement
describe(x) = "something"                     # x::Any
describe([1.0 2.0])                           # "a matrix": static beats dynamic, as today
```

### Rule 4. One compile rule: per key, where the key is what the body can see

- A function is compiled per **key** per bounded argument: what its body can see of the argument.
- The compiler classifies each function once, at its definition (today's definition checking, [traits §9](../reference/traits.md#9-checks-and-when-they-run), run as a classification): **fully bounded** if the body reaches each bounded argument only through its set's contract, or **open** otherwise.
- A fully bounded function's key is the receiver type and the declared fields' types ([traits §6.7](../reference/traits.md#67-what-compiled-code-is-compiled-for)): types with equal keys share code. An open function's key is the whole concrete type: today's specialization, since the body may do anything with the value.
- A function bounded by the empty contract is always open. So `f(x)` and `f(x::Number)` compile exactly as Julia compiles them today.
- `@enforce_bounded f(…)` (or a module option) turns "open" into an error for a function meant to be shared: today's `TraitUseError`. Without it, stepping outside the contract costs sharing, not correctness.
- Fully bounded, type-stable code over concrete keys is fully typed: every call in it is at a fact signature. For it, facts inference is plain inference ([facts §1](../reference/facts.md#term-fully-typed)). That is the one place where "code that only uses declared operations gets the facts-mode guarantees automatically" is true, and it is true today.

```julia
colmean(t::ColTable, i::Int) = sum(col(t, i)) / length(col(t, i))   # fully bounded: per key
colsum(t::ColTable) = sum(t)          # open: `sum(t)` is not in the contract; compiled per concrete type
@enforce_bounded colsum(t::ColTable) = sum(t)                       # an error at the definition
```

### Rule 5. One attribute rule: `Compiled` is specialization, `Dynamic` is erasure

- Every value at a bound is `Compiled` or `Dynamic` ([traits §6](../reference/traits.md#6-values-in-trait-code-compiled-and-dynamic)). `Compiled`: the code compiled for the value's key runs for it. `Dynamic`: code compiled once runs for it, and each operation is resolved when it runs, with the contract's declared result.
- In plain Julia the same two exist as method-level switches: specialization (`Compiled`) and `@nospecialize` with dynamic dispatch (`Dynamic`). The design makes the switch per value and gives the `Dynamic` path declared results. Nothing new is needed to see untyped code this way: `f(@nospecialize x)` is `f(x::Dynamic{Any})`, and its calls on `x` are operations of the empty contract, whose results are `Any`.
- The first-seen rule, trait defaults, annotations and casts stay as [traits §6.2–§6.5](../reference/traits.md#62-how-plain-values-enter-the-trait-world) state them. The attribute is set where a plain value is first seen through a set *with a contract*; the empty contract makes nothing of it.
- The kept forms collapse (§5.2 below): with `X` a type, a container `Vector{X}` holds members of `X`; a `Dynamic{X}` is itself a member of `X` (`Dynamic{X} <: X`, which `conforms(Dynamic{X}, X)` already says). A raw member in such a container is `Compiled`, a wrapped one `Dynamic`. `Compiled{X}` and `Kept{X}` are not needed as storage types.

### Rule 6. The facts rule is the compile rule for everything that is not fully bounded

- Compiled code depends on the method table only through facts ([facts §2](../reference/facts.md#the-guarantees)). Unchanged.
- In the unified model this reads: a call on a value whose set has the empty contract, at a signature that is not a fact, is an operation of `Any`, which declares nothing, so its result is `Any` and it is resolved when it runs. Plain Julia's heuristics are a guess at the contract of `Any` from the method table, and that guess is what loads break. The facts mode is the semantics of `Dynamic` over the empty contract.
- Which code is compiled by facts stays a module or method option ([compiler §2.1–§2.2](../reference/compiler.md#21-the-module-option)): the product setting or the test bed, as today. Traits do not decide it; they make it cost nothing where functions are fully bounded.

### Rule 7. Ownership and strict mode, unchanged

- Who may declare a dynamic membership is who may declare an implementation: a stakeholder ([traits §10.1](../reference/traits.md#101-who-may-implement)). Who may declare a static one is the type's author, as today. Lemma O covers both: a static membership is the type's own definition; a dynamic one changes no fact.
- Pirates, strict mode and joint owners are untouched ([facts §10](../reference/facts.md#pirates)).

---

## 4. What it removes, and what it adds

### 4.1 Removed: rules about the interaction of two worlds

| Today | Under the unified model |
|---|---|
| trait modules as the place where bounded functions exist ([traits §2](../reference/traits.md#2-trait-modules)) | a module option `facts=true` (exists) and a module option `bounded=true` (classification and per-key compilation for the module's functions); no third world |
| a trait's name on an argument refused outside trait modules (§2; decision 41) | a set's name on an argument is a bound everywhere; outside a `bounded` module the function is classified open, so it compiles per concrete type |
| what trait code may do with a trait object (§5.3's table), internal functions (§5.4) | one classification: fully bounded or open; an open function is plain Julia |
| the boundary principle as a rule (values cross by their bound; code never crosses) | a mechanism: the compiler builds the view at the method's prologue, statically for a known type, at run time otherwise. Nothing to state as a rule |
| entries per shape, `Untyped` fallbacks, hand-written ambiguity checks (lowering L-3) | Julia's dispatch over sets with the order of rule 3; the entry is the compiler's |
| three kept forms, `Kept{X}` as a trait's name in storage, the table by position of §6.3 | one: `X` as a type; `Dynamic{X} <: X` the wrapped form (§5.2) |
| `conforms(T, X)` beside `T <: X` (L-5) | `T <: X` |
| "types first, then traits" as a tier | "static before dynamic membership" as a rule of the order; same results |
| T-83, D4: unrelated bounds of sibling packages reported at the load that creates the overlap | the same report, now the ordinary ambiguity of multiple membership; §5.5 says why it cannot be earlier |
| open issue 36 (a trait-typed assertion in a body), closed items waiting for W-27 (items of one concrete conforming type, §2.31) | `v::X` in a body is an `isa` check and a first-seen point, as decided for W-27 |

### 4.2 Removed from the user's view of the language

- One kind of declaration for "a family of types", not two. The tutorial's bullet list of how a trait differs from an abstract type ([traits-for-julia](../intro/traits-for-julia.md), "A trait") becomes: a set may have a contract; a member may be declared later.
- The question "is this an abstract type or a trait?" at design time becomes "does this set declare a contract, and may others join it later?"
- Open issue 82 (a kept value seen through every trait its object conforms to) is simply `isa`: a stored `Column` that is also a `PooledColumn` reaches `groupcodes(c::(Column, PooledColumn))` because dispatch among dynamic memberships is by what the object is a member of. The three ports asked for exactly this (SciML §2.6, Makie D1, DataFrames WP2).

### 4.3 Added

- **A classification per function** (fully bounded or open), computed at the definition. TraitWorld's definition checker does it today for trait modules; the cost is one inference at archetypes per function.
- **Two kinds of membership in one construct**, and the order rule between them. This is the one thing a user must learn that is new to Julia: "declared with the type: it dispatches like a supertype; declared later: it dispatches below every supertype".
- **Multiple membership in Julia's subtyping.** `S <: X` for a dynamic membership must be answered by `jl_subtype` from a registry, not from `DataType.super`. This is W-27's piece 7 in any form; §5.5 and §8 give its cost.
- **Contracts for Base's abstract types,** if Base wants the sharing: written into `AbstractArray`, `AbstractDict`, with the throwing fallbacks turned into "optional" sub-sets (§7).

---

## 5. The subtleties, one by one

### 5.1 Trait modules

**What they do today** ([traits §2](../reference/traits.md#2-trait-modules); [lowering §8](../reference/lowering.md#8-bounded-functions-workers-and-entries)): five things.

1. Set `facts=true` for the module's methods.
2. Refuse a pirate at its definition.
3. Make a trait's name on an argument a bound, and in a field or container a `Kept{X}`; outside, the name is a plain type.
4. Rewrite bounded functions into workers and entries, note positions, fix needs and attributes at the module's end.
5. Run definition checking at the module's end, and again for a function defined later.

**Under the unified model:**
- 1 and 2 are module options already ([compiler §2.1](../reference/compiler.md#21-the-module-option); `OwnershipError`). They stay, as options a package sets, with no connection to traits. The product setting keeps them per module; the test bed `all` sets 1 everywhere.
- 3 dissolves: a set's name is a type everywhere. In an argument it is a bound. In a field it is the member's own type, boxed, with `Dynamic{X}` a member (§5.2). Decision 41 ("refused, now and with traits in the type system") is reversed by this model, and that reversal is the point: the question "what does `x::X` mean outside a trait module" has no answer other than "the same as inside", once the function's classification, not its module, decides what is compiled.
- 4 becomes the compiler's: the generic function's dispatch is the entry; the view is built in the method prologue ([compiler §7](../reference/compiler.md#7-traits-in-the-type-system) plans this).
- 5 becomes the classification of rule 4, run at every definition, with `@enforce_bounded` or a module option making "open" an error where a library wants the guarantee. The module's end stays the point where a module's own methods for a static member's contract are complete.

**What remains of the trait module** is a module that says `facts=true`, `bounded=true` and `no_pirates=true`. That is one spelling, `@trait_module`, for three options. It is not a world. The "how trait and ordinary code interact" questions become "what does a call from an open function into a fully bounded one cost", which is the ordinary question of calling any method: dispatch, a view built at the prologue, then shared code.

### 5.2 `Dynamic`, and the kept forms

**Today:** three storage forms, `Dynamic{X}`, `Compiled{X}`, `Kept{X}`, each a wrapper type holding the object and its attribute; a trait's name in a field inside a trait module means `Kept{X}` ([traits §7](../reference/traits.md#7-kept-values-dynamicx-compiledx-keptx)); the union form was measured and rejected for boxing (3,248 against 48 bytes; [alternatives](../design/alternatives.md#storage-as-always-dynamic-and-stored-replaced-by-values-that-carry-through-storage)).

**Under the model, with `X` a type:**
- A `Vector{X}` holds members of `X`, boxed, as a `Vector{AbstractFloat}` holds numbers today. A member read from it has an unknown concrete type in the code. That is today's `Compiled` kept value: "each item's code selected when it is passed on" ([traits §6.6](../reference/traits.md#66-items-of-a-users-container)). No wrapper is needed for it.
- `Dynamic{X}` stays a wrapper, and is itself a member of `X`: `Dynamic{X} <: X`. The design already says `conforms(Dynamic{X}, X)` is `true` ([traits §14](../reference/traits.md#14-membership)). An operation on it is the split ([facts §9](../reference/facts.md#9-the-dynamic-split)), as today.
- So `Kept{X}` is `X`: a field `model::Model` holds a `Model`, raw or wrapped, and a value stored keeps what it is. "Values carry" holds by construction: a raw member stays raw, a wrapper stays wrapped; `compiled_for` unwraps, `with_dynamic` wraps. A plain value stored takes the set's default (`Compiled` unless `@default_with_dynamic_self`), exactly as [traits §7.3](../reference/traits.md#73-assigning-from-plain-code) says: stored raw, or wrapped.
- `Compiled{X}` as a storage type is not needed: a raw member is the `Compiled` form. As a cast marker in plain code (`compiled_for(x)` before a call) it stays a transient wrapper, as today.
- **The reading of an item** becomes `Union{X, Dynamic{X}}` at the type level, which is `X`. In the code it is one `isa Dynamic` branch before the split. Whether that costs what the measured union form cost is experiment U2 (§10): that measurement compared two wrapper types of a union, where a boxed raw member is already boxed by the container.
- **A struct parameter bounded by a set** ([traits §7.4](../reference/traits.md#74-a-struct-parameter-bounded-by-a-trait)) is then Julia's own `struct S{F <: X}`: the parameter is a member's type under `Compiled`, or `Dynamic{X}` under `Dynamic`, which is what the reference states. The rewrite that strips the bound (L-6) goes.

**What `Dynamic` is, in one sentence:** Julia's `@nospecialize`, per value instead of per method, with the contract's declared results instead of `Any`. Over the empty contract the two coincide, which is why the model needs no new rule for untyped code.

**What stays an addition over plain Julia:** the split over declared implementations ([compiler §4.2](../reference/compiler.md#42-compilersplit_call-the-call-site-split)) and declared results at dynamic positions. Plain Julia has nothing to split on for `Any`.

### 5.3 The facts mode

- Unchanged in substance. G1 and G2 are properties of code compiled by facts, whatever its bounds ([facts §2](../reference/facts.md#the-guarantees)).
- The unified model says where it costs nothing and where it costs: nothing in fully bounded functions over concrete keys; a run-time site per unknown-typed call elsewhere. The classification of rule 4 names the open functions. That is `fully_typed` ([traits §11.3](../reference/traits.md#113-fully-typed-mode)), turned from a report into the compiler's own view of each method.
- "Code that only uses declared operations gets facts-mode guarantees automatically": true as a statement about *invalidation*, since such code holds only facts; false as a statement about *which mode compiled it*, since the mode is the module's option, and a fully bounded function compiled plainly is still protected only where its callees are. The design should keep saying both.
- Could the facts mode become the only mode, so the option goes too? That is the test bed `all` as the product: BaseBenchmarks at 1.037 with tails to 27.8× ([evidence §1](../design/evidence.md#1-the-guarantee)). The user's principle (a slowdown is tolerated where traits recover it) argues for it only once the tails are rewritten as fully bounded loops. The model makes that a measurable migration (§7), not a decision to take now.

### 5.4 Ownership and strict mode

- Unchanged. The model adds one reading: a static membership is part of the type's definition, so its owner is a stakeholder of every signature it changes; a dynamic membership changes no fact, so it needs no stakeholder in the facts sense, and the ownership rule for it ([traits §10.1](../reference/traits.md#101-who-may-implement)) is the orphan rule's purpose: coherence, not invalidation ([other languages §5](../design/other-languages.md#5-who-may-implement-ownership-and-stakeholders)).
- **One hazard the model makes visible.** If `struct S <: (A, X)` declares two static memberships, then `f(::A)` and `f(::X)` on `S` are ambiguous unless a joint method exists. Today Julia detects such an ambiguity when the second method is defined, because `typeintersect(A, X)` is `Union{}` for unrelated abstract types. With a type that may be under both, the intersection is no longer empty, and the check needs either an exclusion relation (Fortress, §9) or a report at `S`'s definition (Karpinski's rule in issue #5). §5.5.

### 5.5 Ambiguity, and why the tier is load-bearing

This is the subtlety that limits the answer to "partly". Three facts:

1. **Julia's ambiguity detection rests on disjointness.** When a method `f(::A)` is added beside `f(::B)`, Julia intersects the signatures. For two abstract types with no common subtype the intersection is `Union{}`, so no ambiguity is reported and none can arise. With multiple membership, every pair of sets can have a common member later. Either every pair is potentially ambiguous (Fortress's answer: declare nominal exclusions, and derive the rest; [Allen et al. 2011](https://people.mpi-sws.org/~skilpat/papers/multipoly.pdf)), or the ambiguity is reported when the common member appears (issue #5's proposal: require `f(::C)` when `C <: A, B`; the design's T-83 and Makie's D4: report at the implementation that creates the overlap).
2. **For static memberships the report at the member's definition is early enough:** the type's author sees it, and the joint method belongs to a stakeholder.
3. **For dynamic memberships it is a third package's problem:** `@implement X S` in `X`'s extension creates an overlap between `f(::A)` (A's package) and `f(::X)` (X's package) at `S`. Neither owns the joint method's place. The design's rule (unrelated bounds need a joint method, checked at the module's end; sibling packages at the load) is the only form that does not need an exclusion relation. The unified model keeps it as the rule for the dynamic tier.

**Why dynamic membership cannot enter Julia's static dispatch:** suppose `f(x::Any) = …` and `f(x::X) = …`, and a caller `g(s::S)` compiled with the fact "`f` at `(S,)` selects `f(::Any)`". Then `@implement X S` in a later-loaded package makes `f(::X)` applicable at `(S,)`. If dispatch is Julia's, the fact changes, `g` is invalidated, and "implementations invalidate nothing" ([the rationale §2.2](../design.md#22-step-2-refuse-the-pirates-that-would-win-and-fully-typed-code-is-never-invalidated)) is false. By Lemma O the definer is a stakeholder (the owner of `X`, which is now a supertype of `S`), so it is not a pirate; it is the "stakeholder's extension activated by an unrelated trigger" case that G2 names as an exception ([facts §2.2](../reference/facts.md#g2)). TraitCSV's `String15` implementation, the rationale's showcase, would then invalidate CSV code compiled for `String15` columns. So the tier is not a convenience: dynamic memberships must be resolved at run time, without an edge, as today's entries do. The unified model keeps exactly this, as the order rule of rule 3.

**What the model gains anyway:** one language for both tiers, and the tier's name changed from "trait vs abstract type" to "declared later vs declared with the type". A set may have members of both kinds. `Shape` with `struct Circle <: Shape` (static) and `@implement Shape Square` (dynamic) is one set; `f(::Shape)` reaches both; the circle by a fact, the square by the entry's run-time check.

### 5.6 Inference, specialization and the key

- **For open functions nothing changes.** `f(x::Number)` is compiled per concrete `x`, as today; under the facts rule its unknown-typed calls are run-time sites; under plain inference Julia speculates. The model does not make `Number` code faster or safer. It makes the reason visible: the contract is empty.
- **For fully bounded functions the key replaces the type.** This is the design's claim ([traits §6.7](../reference/traits.md#67-what-compiled-code-is-compiled-for)), applied to any function whose bound is a set with a contract, whether the membership is static or dynamic. `sum(v::AbstractVector)` written against a declared `Indexable{T}` would compile per `(receiver, T)`, so a `SubArray` of a `Vector{Float64}` that forwards would share code with the vector. Base does not forward today; the gain needs contracts and forwarding declarations, not the model alone.
- **Inference precision at abstract signatures.** Plain Julia infers `size(x)::Tuple` over `x::AbstractArray` from the methods that match today (`max_methods`). The facts rule removes that; a declared contract restores it from the declaration. The model does not change the trade; it names it: precision from the method table is a guess at the contract of an empty set.
- **`where` clauses and `Type{T}`.** `f(x::T) where {T <: X}` reads `T` from the value's type, as today for an abstract bound; for a dynamic membership `T` is the concrete type and `T <: X` is a run-time check that never folds to `false`. `Type{S}` as a member of a set is the fresh-ideas decision (open issue 91), and reads the same.
- **Parametric invariance and `Vector{AbstractFloat}`.** A set's parameters are associated types, so `Vector{Int} <: Indexable{Int}` and not `<: Indexable{Real}`: invariance is "one value per member". `AbstractVector{<:Real}` is `Indexable{T} where T <: Real`. `Vector{AbstractFloat}` is a concrete container whose element set is `AbstractFloat`: boxed items, `Compiled` when raw. Nothing in the model changes a layout.
- **Union splitting** stays Julia's cost model at fact signatures ([facts §3](../reference/facts.md#facts-and-fact-signatures)); the split over declared implementations is the same idea applied to a set's dynamic members.

### 5.7 `isa` and `<:` in the type system (W-27)

- The model needs `S <: X` to be answered for dynamic memberships. `DataType.super` holds one supertype; a registry of memberships per type must be consulted by `jl_subtype` when the chain fails. Subtyping is already undecidable in corners ([Belyakova et al. 2024](https://janvitek.org/pubs/pldi24.pdf)); a registry lookup adds a table read, not a new form of type, as long as sets with parameters keep associated-type (invariant, one value per member) parameters, which Julia's subtyping handles for `AbstractArray{T, N}` today.
- Type intersection must change: `typeintersect(A, X)` for two sets that may share members is not `Union{}`. This affects method sorting, ambiguity detection (§5.5) and `Union` normalization. The safe form: intersection among static sets stays as today (a tree); a set with dynamic members intersects any other set, and such intersections are never used to prove disjointness. That is a two-tier rule inside `jl_subtype`, the mirror of rule 3.
- The piece-7 plan ([compiler §7](../reference/compiler.md#7-traits-in-the-type-system)) lists membership as subtyping, a dispatch tier, compiler-generated entries, and syntax. The unified model asks the same pieces to be built so that an abstract type is the static case of the same thing. That is the direction change W-83 asks about.

---

## 6. Where the current design would change

Not a proposal to change them now; a list of what the model touches, for the decision W-83 names.

| Reference | Today | Under the model |
|---|---|---|
| [traits §2](../reference/traits.md#2-trait-modules), decision 41 | a trait's name on an argument outside trait modules is refused | a bound everywhere; the function is classified open outside a `bounded` module |
| [traits §5.3–§5.4](../reference/traits.md#53-what-trait-code-may-do-with-a-trait-object) | a table of allowed uses; `TraitUseError` | a classification; the error only under `@enforce_bounded` or the module option |
| [traits §5.5](../reference/traits.md#55-dispatch-types-first-then-traits), §14 | types first, then traits | static membership before dynamic membership; same results |
| [traits §7](../reference/traits.md#7-kept-values-dynamicx-compiledx-keptx), §7.2, [lowering L-6](../reference/lowering.md#18-deviations) | `Dynamic{X}`, `Compiled{X}`, `Kept{X}`; a trait's name in storage means `Kept{X}` | `X` in storage; `Dynamic{X} <: X`; `Compiled{X}` only as a cast marker |
| [traits §14](../reference/traits.md#14-membership) | "a trait is a kind of abstract type with its own rules"; the comparison table | one construct; the table becomes "static or dynamic membership" |
| [compiler §7](../reference/compiler.md#7-traits-in-the-type-system), W-27 | encode traits beside abstract types | abstract types as the static case of sets |
| [other languages §1](../design/other-languages.md#1-a-trait-is-an-abstract-type-with-behaviour) | "an abstract type with behaviour" | the same sentence, now literal |
| [alternatives](../design/alternatives.md#other-options-considered-and-not-taken), "trait bounds that compete with types, rejected" | rejected: the conflict would surface only in an application that loads both | still rejected for dynamic members, for the same reason (§5.5); static members compete as supertypes do today |

What does not change: the facts mode and its guarantees, ownership, strict mode, keys, the attribute rule, the split, `Callable`, collections and the crossing of a user's container, concreteness, compiling ahead, printing. The model restates them; it does not alter their content.

---

## 7. Migration

- **Existing packages:** nothing changes. Their abstract types are sets with the empty contract and static members; their functions are open; they compile as today.
- **Base's abstract types:** a contract can be written into `AbstractArray`, `AbstractDict`, `IO`, one at a time, with the manual's required methods as operations and its optional ones as sub-sets (`HasLength`, `IndexStyle` as a capability). Each existing subtype becomes a checked static member at its first use, by the family rule ([traits §4.7](../reference/traits.md#47-families)), with the always-throws rule (a fallback is not an implementation). The subtypes that fail the check are the ones RequiredInterfaces.jl and Interfaces.jl find today by hand. BaseTraits is the dress rehearsal: its families over `AbstractVector` and `AbstractDict` are those contracts, declared from outside.
- **`Number`, `Real`, `Integer`:** stay empty. Promotion is not an operation on one receiver (open issue 8). The model loses nothing here and gains nothing.
- **Method tables:** a method on a set is an ordinary method; the entries per shape go; the dynamic tier's resolution moves into the generic function's dispatch (the planned piece 7). Base's own methods on abstract types are static-tier methods, untouched.
- **The demonstrators and ports:** the capability traits of all three ports (SciML's integrator capabilities, Makie's legend and native drawing, DataFrames' external columns) are dynamic memberships selected by `isa` at a bound: open issue 82 (a), which is decided and being built (W-81). TraitDifferentialEquations' `ODEProblemTrait`, TraitMakie's `Plot`, the forks' `Column` are sets with contracts; their `@implement` lines are unchanged. The `Kept{…}` spellings in their structs become the set's name.
- **The order of work:** W-27 is last in the order of work for a reason ([compiler §7](../reference/compiler.md#7-traits-in-the-type-system), "Why last"). The model changes what W-27 builds, not when. The three experiments of §10 can run before it, on the patched Julia and TraitWorld as they are.

---

## 8. Costs and risks

Honestly, in order of weight.

1. **Backward compatibility of the type lattice.** Multiple membership changes `typeintersect` for sets that admit dynamic members. Any code that relied on two unrelated abstract types being disjoint (ambiguity detection, `Union` simplification, `isdisjoint`-style reasoning in Base's dispatch) must treat such sets as possibly overlapping. The two-tier rule inside subtyping (§5.7) confines this to sets that declare they admit dynamic members; an abstract type that stays as today is unchanged. Still a change to `jl_subtype` and `jl_type_intersection`, with the subtype cache and the method-sorting code behind them.
2. **Ambiguity resolution is late by necessity** for dynamic members (§5.5). The design has this cost today (T-83); the model does not add it, and does not remove it. Fortress removed it by an exclusion relation, which is a second declaration language and which the design has not wanted.
3. **No gain without contracts.** The user's hope, one way to write generics, is met for the language. The *performance and checking* gains reach only sets with contracts and functions that are fully bounded. Code over `Number` or `Any` is as it was. A reader may expect more from "abstract types are traits" than it delivers.
4. **Inference precision.** Where plain Julia's speculation over the method table paid off (one matching method at an abstract call), the facts rule loses it, and a contract must be written to get it back. Unchanged from today; the model makes the loss the default reading of an empty contract.
5. **Compile times.** Two effects in opposite directions: fewer copies for fully bounded functions over shared keys; one classification inference per function definition in `bounded` modules, and a registry lookup in subtyping for dynamic memberships. Neither is measured. The classification is what definition checking costs today (under 200 ms for a library of five functions on the previous prototype, [other languages §4](../design/other-languages.md#4-generic-code-is-checked-at-its-definition)).
6. **The facts mode's guarantees** are unchanged. One new exposure: if the kept-forms collapse (§5.2) makes `Dynamic{X} <: X`, then an operation on a raw member read from a `Vector{X}` is a call at an abstract type in the code, a run-time site, unless the compiler emits the split for it as it does for `Dynamic{X}` today. The split must then be emitted for every call on a value typed by a set with a contract, not only for the wrapper. That is a change to the lowering of operations, not to the guarantee.
7. **Two kinds of membership is a concept to teach.** It replaces "abstract type or trait", which was also one. Rust teaches `dyn` against `impl`; Swift teaches `any` against `some`; this teaches "declared with the type" against "declared later". The honest comparison: the thing Julia users already know, "subtype the abstract type", keeps its meaning exactly.
8. **The decision reversed.** Open issue 41 (a trait's name on an argument outside trait modules is refused, "now and with traits in the type system") was decided by the user on 2026-10-21. The model cannot hold with it. That is the one decision in force the model contradicts, and it is the user's to revisit.

---

## 9. Prior art

What each language did with the same question, from primary sources. The research record ([other-languages-research](../record/other-languages-research-2026-10-16.md)) covers C++, Rust, Swift and Mojo in depth; this section adds the languages with multiple dispatch, Julia's own history, and the type-class line.

| Language | Sets of types | Membership | Dispatch | Contract | What it says to the model |
|---|---|---|---|---|---|
| **Haskell** type classes ([Wadler and Blott 1989](https://www.cs.tufts.edu/~nr/cs257/archive/phil-wadler/class.pdf); [Peyton Jones, Jones, Meijer 1997](https://courses.cs.washington.edu/courses/cse590p/06sp/multi.pdf)) | classes are not types | declared instances, after the fact, global | none: dictionary passing, resolved statically | declared, checked | the origin of "declared, checked, after the fact"; multi-parameter classes made the system "unsound and undecidable" in corners, the warning the complexity budget repeats ([other languages §7](../design/other-languages.md#7-the-complexity-budget)) |
| **Scala** ([Oliveira, Moors, Odersky 2010](https://infoscience.epfl.ch/record/150280)) | type classes as objects | implicits, selected by scope | static | declared | selection by scope rejected here ([alternatives](../design/alternatives.md#named-implementations-by-module-deferred)): an entry compiled once does not know its caller's module |
| **Rust** ([reference, traits](https://doc.rust-lang.org/reference/items/traits.html)) | traits are not types, except `dyn Trait` | declared `impl`, orphan rule | static (monomorphized) or `dyn` (vtable) | declared, checked at definition | `dyn` compatibility (no generic methods, no `Self` returns, upcasting to supertraits only since 1.86) is the price of a trait object that must carry its table; Julia compiles per signature at run time and does not pay it (SciML §2.1); the orphan rule is rule 7 |
| **Swift** ([SE-0335](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0335-existential-any.md); [SE-0352](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0352-implicit-open-existentials.md); [Rose 2021](https://belkadan.com/blog/2021/11/Swift-Regret-Retroactive-Conformances/)) | protocols are types (`any P`) | declared, retroactive allowed, regretted | witness tables; `as?` tests conformance at run time | declared | the closest to "a trait is a type": its lesson is to spell the dynamic form (`any`) and to own conformances; the model keeps both (`Dynamic{X}`, rule 7) |
| **Go** ([spec](https://go.dev/ref/spec)) | interfaces are types | structural, implicit | dynamic through the interface value | structural | rejected here: Base's throwing fallbacks make structural matching prove nothing ([other languages §2](../design/other-languages.md#2-implementations-are-declared)) |
| **Clojure** ([protocols](https://clojure.org/reference/protocols)) | protocols | `extend-type` after the fact, open; "if you don't own the protocol or the type, extend only in application code" | single dispatch on the first argument's type | names only | the ownership advice is Julia's piracy convention and rule 7; single dispatch avoids §5.5 |
| **Dylan** ([DRM, sealing](https://opendylan.org/books/drm/Define_Sealed_Domain)) | abstract classes, multiple inheritance | declared with the class | multiple dispatch; generics and classes sealed by default, `open` to extend | none | multiple inheritance with multiple dispatch, made compilable by sealing; the design rejected sealing ([alternatives](../design/alternatives.md#sealing-rejected)) and gets the same by facts |
| **Cecil** ([Chambers and Chen 1999](https://projectsweb.cs.washington.edu/research/projects/cecil/www/Papers/dispatching.html)) | classes and predicates | declared | predicate dispatch: single, multiple, predicate classes and pattern matching as one theory | predicates | one dispatch theory over several membership forms: the shape of rule 3 |
| **Fortress** ([Allen et al. 2011](https://people.mpi-sws.org/~skilpat/papers/multipoly.pdf)) | traits with multiple inheritance, parametric | declared with the type | symmetric multiple dispatch, checked modularly for type safety | declared | the closest precedent to "abstract types are traits with multiple dispatch": its modular checking needs an **exclusion relation** among types (nominal exclusions, plus implicit ones between instances of a polymorphic type) to admit overloads that open-world extension would otherwise forbid. That is the cost of §5.5 made into a language feature |
| **Julia** | abstract types; informal interfaces ([manual](https://docs.julialang.org/en/v1/manual/interfaces/)) | declared with the type, single supertype | multiple dispatch by subtyping | none checked | [#5 "abstract multiple inheritance"](https://github.com/JuliaLang/julia/issues/5) (Karpinski 2011, open, speculative): the "no incest" rule, and the objection that it needs all descendants known; [#6975 "Interfaces for Abstract Types"](https://github.com/JuliaLang/julia/issues/6975) (2014, open, "Potential 2.0"): declared required methods, with the objection that signatures and variance are the hard part; [#2345](https://github.com/JuliaLang/julia/issues/2345) (2013): Holy's trait functions as the answer to an inextensible `Union`, preferred by Bezanson over multiple inheritance; Interfaces.jl and RequiredInterfaces.jl ([announcement](https://discourse.julialang.org/t/ann-requiredinterfaces-jl/101296)): "abstract types are interfaces with all constraints and requirements being implicit", checked by hand |
| **Julia, the papers** | [Zappa Nardelli et al. 2018](https://hal-univ-tlse3.archives-ouvertes.fr/INRIA/hal-01882137) (subtyping formalized); [Belyakova et al. 2024](https://janvitek.org/pubs/pldi24.pdf) (undecidable; decidable with use-site variance in value types); [Pelenitsyn et al. 2021](https://arxiv.org/abs/2109.01950) (type stability and groundedness as the properties that let the JIT optimize) | | | | the model's "fully bounded, type-stable, over concrete keys" is close to type groundedness, reached by declaration rather than by discipline; any change to subtyping should stay inside the decidable restriction |

**What the prior art says in one paragraph.** Every language with declared contracts and multiple dispatch (Dylan, Cecil, Fortress) had to pay for the open world somewhere: Dylan by sealing, Fortress by an exclusion relation, Cecil by whole-program analysis. Every language with a trait object (Rust, Swift) made the dynamic form explicit and restricted it. Julia's own history (issues #5, #6975, #2345) circled the same three obstacles: ambiguity under multiple membership, the cost of signatures in a declared interface, and the fear of changing the type system. The design pays for the open world with the facts rule and the dynamic tier; the model keeps those payments and removes only the separate language.

---

## 10. The smallest experiments

Each needs a registry row first ([record/experiments.md](../record/experiments.md)); none ran. Each is minutes, one Julia job, niced; none is a benchmark campaign. The result that decides is named.

| ID | Question | How | Result that decides |
|---|---|---|---|
| **U1. How much existing abstract-typed code is already fully bounded?** | Does the classification of rule 4 catch a useful fraction of generic code as written today, given Base's documented interfaces as contracts? | Take BaseTraits' `Indexable{T}`, `Iterable{T}`, `HasLength` as the contracts of `AbstractVector`. Run TraitWorld's definition checker (`check_definitions`, at archetypes) over a slice of generic code written against `AbstractVector`: PlainTables' column functions, and twenty of Base's `abstractarray.jl` functions, each rewritten only by changing the annotation to the bound. Count fully bounded against open, and list what the open ones reach outside the contract. | Above a third fully bounded, or open only for a few named operations (`similar`, `axes`): the model buys sharing for existing code, and the contracts to write are short. Below that: "abstract types as traits" is a language simplification only, and §8 item 3 is the headline. |
| **U2. Do the kept forms collapse without the boxing cost?** | Is `Vector{X}` of raw members and `Dynamic{X}` wrappers as cheap to read and split as `Vector{Kept{X}}`? | In TraitWorld as it is: a `Vector{Any}` holding `Circle`, `Square` raw and two `Dynamic{Shape}` wrappers; a loop that branches `isa Dynamic` then runs the split (the `DynamicItems` view already wraps on read; here the raw members are not wrapped). Measure per-element time and allocation against the `Kept{Shape}` vector of E-164; 1,000 elements, medians. | Within 20% and no allocation per element: the collapse is free, and §5.2 goes into W-27's plan. Allocation per raw element, or above 20%: the wrapper stays, and `Kept{X}` is the honest spelling. |
| **U3. Can `jl_subtype` carry dynamic membership, and what does it do to ambiguity detection?** | Is multiple membership feasible in the patched Julia at the cost of a registry lookup, and does ambiguity detection survive the two-tier intersection rule? | In `julia-1.13`, a probe branch: a per-type registry of memberships (`jl_type_implements(T, X)`), consulted by `jl_subtype` when `T`'s supertype chain fails and `X` is marked as admitting dynamic members; `typeintersect` of such an `X` with any set returns the intersection non-empty. Register BaseTraits' families and the demonstrators' implementations as memberships. Run `Test.detect_ambiguities(Base)`, Base's `core` and `subtype` test files, and the demonstrators' suites. Time `Base.runtests(["subtype"])` against the main line. | Base's subtype tests pass; `detect_ambiguities` reports no new ambiguity for sets that admit no dynamic members; the subtype test file within 10%; and the demonstrators' `conforms` calls can be replaced by `<:`. Then W-27 takes the unified direction. A new ambiguity in Base, or a slowdown above 10%, sends the model back to §5.7's two-tier rule or to an exclusion relation. |
| **U4. Is an untyped function a `Dynamic` over `Any`?** | Does `f(@nospecialize x)` under the facts mode behave as the design's `Dynamic` position does (compiled once, every operation a run-time site with result `Any`)? | `experiments/facts/`: a function with `@nospecialize` under the product setting and under `all`, `code_typed` and a timing against the same function at a `Dynamic{X}` bound of a trait with one operation. Count CodeInstances per call type. | One CodeInstance for the untyped form in both settings and `Any` results at each call under `all`: rule 5's reading holds, and the tutorial can say "`Dynamic` is `@nospecialize` with declared results". A difference names where the two paths diverge, to state in [facts §5](../reference/facts.md#run-time-sites). |

Order: U4 and U2 first (an afternoon, no build), then U1 (a day of rewriting annotations), then U3 (a build, alone, under the memory guard). U3 decides; U1 says whether the decision matters beyond the language.

---

## 11. Sources

The design's documents are linked in place. External sources, all opened:

- Julia manual: [Types](https://docs.julialang.org/en/v1/manual/types/); [Interfaces](https://docs.julialang.org/en/v1/manual/interfaces/).
- Julia issues: [#5 abstract multiple inheritance](https://github.com/JuliaLang/julia/issues/5) (Karpinski, 2011, open); [#6975 Interfaces for Abstract Types](https://github.com/JuliaLang/julia/issues/6975) (tknopp, 2014, open, "Potential 2.0"); [#2345 StridedArray should be an abstract class, not a union](https://github.com/JuliaLang/julia/issues/2345) (stevengj, 2013; Holy's trait functions).
- Julia packages: [RequiredInterfaces.jl announcement](https://discourse.julialang.org/t/ann-requiredinterfaces-jl/101296) (Seelengrab, 2023), with Interfaces.jl discussed there.
- Julia papers: Zappa Nardelli, Belyakova, Pelenitsyn, Chung, Bezanson, Vitek, [Julia Subtyping: A Rational Reconstruction](https://hal-univ-tlse3.archives-ouvertes.fr/INRIA/hal-01882137), OOPSLA 2018; Belyakova, Chung, Tate, Vitek, [Decidable Subtyping of Existential Types for Julia](https://janvitek.org/pubs/pldi24.pdf), PLDI 2024 (DOI 10.1145/3656421); Pelenitsyn, Belyakova, Chung, Tate, Vitek, [Type Stability in Julia](https://arxiv.org/abs/2109.01950), OOPSLA 2021; Bezanson, Bolewski, Chen, [Fast Flexible Function Dispatch in Julia](https://arxiv.org/abs/1808.03370), 2018.
- Fortress: Allen, Hilburn, Kilpatrick, Luchangco, Ryu, Chase, Steele, [Type Checking Modular Multiple Dispatch with Parametric Polymorphism and Multiple Inheritance](https://people.mpi-sws.org/~skilpat/papers/multipoly.pdf), OOPSLA 2011 ([conference page](https://2011.splashcon.org/details/oopsla-2011-papers/57/Type-Checking-Modular-Multiple-Dispatch-with-Parametric-Polymorphism-and-Multiple-Inh)).
- Cecil: Chambers and Chen, [Efficient Multiple and Predicate Dispatching](https://projectsweb.cs.washington.edu/research/projects/cecil/www/Papers/dispatching.html), OOPSLA 1999.
- Dylan: [Dylan Reference Manual, Define Sealed Domain](https://opendylan.org/books/drm/Define_Sealed_Domain); [Declaring Characteristics of Generic Functions](https://opendylan.org/books/drm/Declaring_Characteristics_of_Generic_Functions).
- Haskell: Wadler and Blott, [How to make ad-hoc polymorphism less ad hoc](https://www.cs.tufts.edu/~nr/cs257/archive/phil-wadler/class.pdf), POPL 1989; Peyton Jones, Jones, Meijer, [Type classes: an exploration of the design space](https://courses.cs.washington.edu/courses/cse590p/06sp/multi.pdf), Haskell Workshop 1997.
- Scala: Oliveira, Moors, Odersky, [Type Classes as Objects and Implicits](https://infoscience.epfl.ch/record/150280), OOPSLA 2010.
- Rust: [The Rust Reference, Traits (dyn compatibility)](https://doc.rust-lang.org/reference/items/traits.html).
- Swift: [SE-0335 existential `any`](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0335-existential-any.md); [SE-0352 implicitly opened existentials](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0352-implicit-open-existentials.md); Rose, [Swift Regret: Retroactive Conformances](https://belkadan.com/blog/2021/11/Swift-Regret-Retroactive-Conformances/), 2021.
- Clojure: [Protocols](https://clojure.org/reference/protocols).
- Go: [The Go Programming Language Specification](https://go.dev/ref/spec), interface types (the spec's wording was not fetched; secondary sources agree that satisfaction is implicit and structural).
