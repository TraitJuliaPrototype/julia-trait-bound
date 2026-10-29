# One way to write generics: abstract types as traits

Status: **exploration** (2026-10-28, an exploratory agent's analysis, Fable; not adopted; §16 added 2026-10-29 from the quick runs E-252 to E-258). Not normative.

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
11. [One kind of membership: candidates](#11-one-kind-of-membership-candidates)
12. [Sources](#12-sources)
13. [Invalidation for subtyping: making `S <: X` sound for late memberships](#13-invalidation-for-subtyping-making-s--x-sound-for-late-memberships)
14. [CommonSolve's `solve`: a ground-up design](#14-commonsolves-solve-a-ground-up-design)
15. [The project as a set of co-designed features](#15-the-project-as-a-set-of-co-designed-features)
16. [What the quick runs found (2026-10-29)](#16-what-the-quick-runs-found-2026-10-29)

---

## 1. Summary: the answer

**Partly: yes for the language; the one distinction that seemed to resist (§1, second bullet) has a principled way through (§11), at the price of one coherence rule.**

- **Yes.** An abstract type and a trait are the same kind of thing: a named set of types with a declared membership. Every rule of the design can be stated once, for that one thing. An abstract type is a trait whose contract is empty and whose members are all declared where they are defined. `Any` is the trait that declares nothing and that every type belongs to. An untyped function `f(x)` is a function bounded by `Any`. Julia's specialization is `Compiled`; Julia's `@nospecialize` with dynamic dispatch is `Dynamic`; the facts rule is what `Dynamic` means when the contract is empty. Under this reading there is one dispatch, one compile rule, one attribute rule. Trait modules dissolve into two module options that already exist (compiled by facts; no pirates). The "trait world" and its boundary stop being a world and become a per-function property.
- **The obstacle, and its answer.** The design's two dispatch tiers (types first, then traits; [traits §5.5](../reference/traits.md#55-dispatch-types-first-then-traits)) are not an artefact of TraitWorld's encoding. They are what makes an implementation invalidate nothing ([the rationale §2.2](../design.md#22-step-2-refuse-the-pirates-that-would-win-and-fully-typed-code-is-never-invalidated), "Implementations are the extension point"). If `@implement X S` made `S <: X` in Julia's own dispatch, it would change what `f(::S)` selects wherever `f(::X)` exists: a definition that wins at a fact, and a load that invalidates. The first reading of this (§5.5) keeps two kinds of membership: **declared with the type** (`struct S <: X`: a fact, Julia's static dispatch) and **declared later** (`@implement X S`: resolved at the trait tier when the code runs, without an edge). **§11 finds that the two collapse into one** under a coherence rule that is Lemma O applied to memberships, and that is Rust's orphan rule for blanket impls in Julia's terms: what must be refused is one combination only, *a set that takes foreign members by its own owner* together with *a method bounded by that set on a function its definer does not own*. Everything else (a membership declared by the member's owner, a membership declared by the set's owner for a foreign type, a bounded method by the function's owner, a bounded method on a foreign function for a set whose members all joined by their own owners) is loaded before any code that could see it compiles, in every load order, so it changes no compiled fact. The forbidden combination is piracy in disguise, and gets the treatment pirates get: refused in a trait module at the definition, refused by strict mode where it would win, followed by default with one recompile. With that, `@implement X S` is `S <: X` in Julia's own dispatch, and "abstract type" and "trait" are one construct with one kind of membership. "Static beats dynamic" survives only as a precedence rule for ties (a type's own supertypes before memberships added later: CLOS's and Dylan's local precedence order), not as a dispatch mechanism.
- **What it simplifies.** The interaction rules disappear: what trait code may do with a trait object (§5.3), internal functions (§5.4), a trait's name refused outside trait modules (§2; decision 41), the three kept forms (§7), the entries per shape (lowering L-3), the boundary principle as a rule. They are replaced by one classification the compiler makes per function: *fully bounded* (the body uses only its bounds' contracts) or not. A fully bounded function is compiled per key and checked at its definition; any other function is today's plain Julia, compiled per concrete type, with the facts rule at its run-time sites. The `fully_typed` report already computes most of this.
- **What it costs.** Multiple membership in Julia's subtyping (a real change to `jl_subtype`, type intersection and ambiguity detection); ambiguity between methods on two unrelated traits is reportable only when a common member appears (Julia issue #5's problem, Fortress's exclusion relation, the design's T-83); the coherence rule of §11 refuses one pattern the design allows today (a bounded method on a foreign function, such as `Base.show(io, ::X)`, for a set whose owner declares foreign members), with a newtype or the set's own wrapper type as the escape; no gain for an abstract type that declares no contract (`Number` stays `Number`); and the decided rule that a trait's name is refused outside trait modules (open issue 41) is reversed.
- **The smallest step that pays** (§13): the storage simplification needs only `S <: X` in Julia's subtyping, not the rest. It is sound with one rule the design already states: a positive membership answer may be folded at compile time (memberships are monotone), a negative one never is; `typeintersect` with an open set over-approximates, as its contract allows; a registry read at run time, with a world of its own as methods have. No new edges, no invalidation, the REPL covered. §11's timing argument explains why package code could fold negatives too, but nothing needs it.
- **SciML's `solve`** (§14): the front end `CommonSolve.solve(prob::ODEProblemTrait, alg)` by SciMLBase is refused today by lowering L-3 only; the coherence rule of §11 allows it as long as `ODEProblemTrait`'s members join in their own packages, which is how SciML's problem types are declared. The cost the rule has in SciML is nil for the front end; it falls on operator-style traits over Base's types bounding Base's functions, where Base's typed methods make it harmless, so the static check should be a warning, not an error.
- **The project's shape** (§15, the user's framing): five co-designed features (traits as abstract types, `Dynamic`, `Callable`, compiling by facts, declarations on a scope) on two foundations (the trait declaration, ownership); the goals are combinations of them. A trait module may stay as the combination of all declarations, or a few combinations may be blessed. To return to when the ports are finished.
- **What to do with it.** It does not change the design's rules. It changes the *framing* of W-27 (traits in the type system): not "encode a trait beside abstract types" but "an abstract type is a set whose members joined with their definitions; `@implement` adds a member; one dispatch". §10 and §11.5 give the experiments: a census of the demonstrators and ports for the forbidden combination (minutes), a probe of extension load order (minutes), and the subtyping probe (a build). Until they run, W-27's direction should stay open, not decided.

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
- **Revised by §11:** under the coherence rule there, the two kinds of membership need no separate mechanism; both are Julia's static dispatch. What remains of this rule is a precedence order for ties (§11.3, C7).

```julia
describe(m::AbstractMatrix) = "a matrix"      # static membership of Matrix{Float64}
describe(t::ColTable) = "a table"             # dynamic membership of Matrix{Float64}, by @implement
describe(x) = "something"                     # x::Any
describe([1.0 2.0])                           # "a matrix": the type's own supertype before a later membership (§11 C7), as today
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
| "types first, then traits" as a tier | a precedence order for ties (a type's own supertypes before later memberships, §11 C7); dispatch itself is Julia's, under the coherence rule of §11 |
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

**This section's conclusion is the one §11 revisits.** The argument above shows that *some* late membership breaks a compiled fact. §11 asks exactly which, by who declares it and where it loads, and finds that only one combination can, which a coherence rule can refuse. Read §5.5 as the problem and §11 as the answer.

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

## 11. One kind of membership: candidates

Added on 2026-10-28 after the user's question: "Any creative principled original solutions to the 'two kinds of membership' issue?" §5.5 established that *some* late membership breaks a compiled fact. This section asks *which*, exactly, and whether a rule removes it for a reason rather than by a tier. No Julia ran.

### 11.1 The constraint, made precise

The breaking event needs four things:

1. a caller `P` compiled at the concrete signature `(S,)`, with the fact "`f` at `(S,)` selects `m₀`" (`m₀` is `f(::Any)`, a tree method, or "no method");
2. a method `f(::X)` that is more specific than `m₀` at `S`;
3. a membership `S ∈ X`;
4. items 2 and 3 both visible *after* item 1 was compiled. Whichever of 2 and 3 became visible last is the definition that won at `(S,)`.

**Who can declare 2 and 3, and where it loads.** Julia loads a package's dependencies before the package's own code runs, and loads a package extension as soon as the last of its triggers is loaded, before the loading of the package that pulled the trigger continues. So a definition is visible to `P` when `P` compiles iff it lives in a package in `P`'s dependency tree, or in an extension whose triggers are all in that tree. `P` compiled at `(S,)` calling `f` has at least `S`'s package and `f`'s owner in its tree (it names both). The design already relies on this argument once, for family-member overrides (decision log §1, 2026-10-26: "every caller that names `S{MyT}` depends on that package, so the override is in place before any use, in every load order; an extension loads later").

| Definition | By whom, where | In `P`'s tree when `P` compiles? |
|---|---|---|
| `f(::X)` | `f`'s owner, in its package | yes: `P` depends on `f`'s owner, and `f`'s owner depends on `X` (it names it), so `X` is in the tree too |
| `f(::X)` | `f`'s owner, in an extension of its package triggered by `X` | **no**: `f`'s owner does not depend on `X`; `X` may load later |
| `f(::X)` | `X`'s owner, in its package (`f` foreign to it) | **no**: nothing makes `P` depend on `X` |
| `f(::X)` | anyone else | a pirate: refused in trait modules, strict mode's business in plain code |
| `S ∈ X` | `S`'s owner, in `S`'s package | yes |
| `S ∈ X` | `S`'s owner, in an extension of `S`'s package triggered by `X` | only if `X` is in the tree |
| `S ∈ X` | `X`'s owner, in `X`'s package (`X` depends on `S`'s package) or in an extension triggered by `S`'s package | only if `X` is in the tree |

Read the table together. **A membership not in the tree matters only if a method `f(::X)` not in the tree accompanies it, or vice versa.** If `f(::X)` is `f`'s owner's, in its package, then `X` is in the tree, and every membership of `X`, by whomever and in whatever extension of `X`'s or `S`'s package, is in the tree as well. If every membership of `X` is declared by the member's own owner in the member's own package, then `X` is in the tree of every member's package, hence in `P`'s tree, and every method `f(::X)` by `X`'s owner is in the tree too. The one combination that escapes: **a membership declared outside the member's package (by `X`'s owner, or in an extension) together with a method `f(::X)` declared outside `f`'s owner's package (by `X`'s owner, or in an extension).** That is the only way a definition can win at a compiled `(S,)` through membership.

In plain Julia the same combination exists in one form only: `X`'s owner defining `f(::S)` for a foreign `f` and a foreign `S`. That is type piracy. The combination is piracy in disguise, assembled from two declarations each of which looks like the owner's right.

### 11.2 Candidates

Each with its rule, an example, what it guarantees, what it costs, what breaks.

#### C1. Members belong to the member: a membership is declared only in the member's own package

- **Rule.** `S ∈ X` may be declared only by `S`'s owner, in `S`'s package (not an extension), or at `S`'s definition (`struct S <: X`). A set's owner may not make a foreign type a member.
- **Example.** `struct Measurements <: ColTable … end` or, later in the same package, `@implement ColTable Measurements by data`. TraitWorld could not declare `@implement Indexable A where {A <: AbstractVector}` for Base's vectors; Base would have to.
- **Guarantees.** Every membership is in the tree of every caller that names the member. Bounded methods on `X` by anyone (`X`'s owner, `f`'s owner) are in the tree too (§11.1). Memberships are facts; one kind of membership; G1, G2 and Lemma O as written (the implementer is `S`'s owner, a stakeholder of every `(S,)`).
- **Costs.** This is Rust's orphan rule with half its permissions: `impl ForeignTrait for LocalType` only. It loses `impl LocalTrait for ForeignType`: BaseTraits for Base's containers, TraitCSV's `String15` in CSV's extension, every "trait owner's extension for a foreign type" of [traits §10.1](../reference/traits.md#101-who-may-implement). The escape is the newtype (C8).
- **Breaks.** The design's showcase for implementations as the extension point. Too much to give up; kept as the limit case that shows the shape of the rule.

#### C2. Methods belong to the function: a method bounded by a set with foreign members is declared only in the function's owner's package

- **Rule.** If `X` has any membership declared outside the member's package (by `X`'s owner, by a family or generic implementation, in an extension), then a method `f(::X)` may be defined only in the package that owns `f` (joint owners included), not in an extension of it. Memberships stay as today: by the set's owner or the type's owner, extensions allowed.
- **Example.** TraitCSV declares `String15` columns members of `CSVColumn` in its extension, and bounds its own functions by `CSVColumn`: allowed. TraitCSV may not define `Base.show(io::IO, c::CSVColumn)`: `show` is Base's. It writes `Base.show(io, c::Dynamic{CSVColumn})` (its own wrapper type) or an operation `describe(c::CSVColumn)::String`.
- **Guarantees.** `f(::X)` in `f`'s owner's package puts `X` in every caller's tree, so every membership of `X` is there too (§11.1). One kind of membership; G1, G2 as written; Lemma O with the refinement of C4.
- **Costs.** No bounded method on a foreign function for an open set. This is what lowering L-3 does today by accident of the encoding ("only a function's owner may add a bounded method of a shape the function has none of yet"), which [traits §5.5](../reference/traits.md#55-dispatch-types-first-then-traits) means to lift ("or to another package's function where the package owns a trait the bound names"). It is also the rule [traits §10.1](../reference/traits.md#101-who-may-implement) already has for operations: "Operations that are existing functions (`Base.size`) may be implemented only for types the declaring package owns."
- **Breaks.** Makie D4's pattern (a geography package adds `Makie.plot(x::GeoData)`) only if `GeoData` has foreign members by the geography package. With members by their own owners (the geography package's own types) C2 does not apply, and the method is allowed. `Base.show` for a trait with foreign members is the common casualty.

#### C3. The coherence rule: refuse only the combination, per set

- **Rule.** A set is declared in one of two modes. **Members by owner** (the default for `abstract type`; an option for `@trait`): every membership is in the member's own package; bounded methods on it may be defined by anyone who owns the function or the set. **Open members** (the default for `@trait`, as today): the set's owner may declare foreign members, in its package or its extensions, and a family or generic implementation may cover foreign types; then a bounded method on the set may be defined only in its function's owner's package. A sub-set of a members-by-owner set is members-by-owner (its members are the parent's members). The mode is checked at each `@implement` and at each bounded method's definition, so the check is order-independent and local.
- **Example.**

  ```julia
  @trait Indexable{T} begin … end                     # open members (default): TraitWorld declares Base's vectors
  retain!(f, xs::(MutableIndexable, Resizable)) = …   # TraitWorld owns retain!: allowed
  Base.filter!(f, xs::MutableIndexable) = …           # refused: Base owns filter!, Indexable has foreign members
                                                      # (BaseTraits already avoids this, traits §8.4, for another reason)
  @trait GeoData @members_by_owner begin … end        # the geography package's own types join it
  Makie.plot(x::GeoData) = …                          # allowed: no foreign member can ever join GeoData
  @implement GeoData Shapefile.Table                  # refused in the geography package: not the member's owner;
                                                      # Shapefile may declare it, or a newtype wraps it
  ```
- **Guarantees.** By §11.1, no definition can win at a compiled `(S,)` through membership. So memberships can be Julia's subtyping, consulted by static dispatch, recorded as facts. One kind of membership. G1 unchanged. G2 gains nothing new to except. Lemma O needs C4's refinement of "stakeholder", or the ordering lemma stated beside it.
- **Costs.** One declaration per set (a mode), and one refusal: the combination. Rust's orphan rule refuses the same thing: an impl of a foreign trait for an uncovered type parameter (`impl<T: Local> Foreign for T`) is rejected because "no uncovered type parameters may appear" before the first local type ([the Rust reference, orphan rules](https://doc.rust-lang.org/reference/items/implementations.html#orphan-rules)). In Julia's terms: dispatching a foreign function on a local set over foreign types.
- **Breaks.** Exactly what C2 breaks, for open sets only. The census U5 (§11.5) counts how often the demonstrators and the ports do it. From reading: BaseTraits does not; TraitCSV, TraitTables, TraitMakie and TraitDifferentialEquations bound their own functions; the one known wish is `Base.show` on a trait, which the design routes through printing by key today ([traits §12](../reference/traits.md#12-printing)).

#### C4. Lemma O for memberships: the forbidden combination is a pirate, and is treated as one

- **Rule.** Restate the terms of [facts §1](../reference/facts.md#1-terms):
  - *Consented supertypes* of a type `S`: the sets `S` was declared a member of by `S`'s own owner (with its definition, or later in `S`'s package).
  - *Stakeholders of a concrete signature `s`*: the owner of its function, and the owners of every type in `s` and of its consented supertypes. A membership declared by the set's owner does **not** make that owner a stakeholder of the member's signatures.
  - *A membership is a definition.* It wins at `s` when dispatch at `s` selects something else after it.
  - **Lemma O, extended:** a definition (a method or a membership) that wins at a concrete `s` is a stakeholder's, or a pirate's. A method or a membership by a non-stakeholder that wins at `s` is a pirate at `s`.
  - **Lemma M (ordering):** a definition by the function's owner in its package, or a membership by the member's owner in its package, is loaded before any code at `s` can be compiled, in every load order, so it never wins at a *compiled* fact. Only the combination of §11.1 can.
- **Enforcement, as for method pirates today** ([traits §10.2](../reference/traits.md#102-pirates), [facts §10](../reference/facts.md#pirates)): a trait module refuses the combination at the definition (C3's static check); strict mode refuses the later half of a combination where it would win at a fact of compiled facts-owner code (the membership, or the method, whichever comes second); the default session follows it and recompiles the broken code once. The machinery exists: strict mode's walk from the definition to the facts it would change needs to see a membership as a definition that applies at the member's signatures, and nothing else.
- **Example.** A package `X` defines `Base.show(io::IO, x::X)` (its own set) and, in an extension triggered by `S`'s package, `@implement X S`. In a session where `P`'s code already printed an `S` through `show(::IO, ::Any)`: by default, `P`'s `show` call at `(S,)` is recompiled once and now prints through `X`'s method; in strict mode, the `@implement` is refused with a `PirateError` naming `P`'s code and the fact, as a winning pirate is today; in a trait module the `@implement` was refused when `X` declared `Base.show` on an open set, before any session.
- **Guarantees.** G1: a refused definition does not exist for plain code either; a followed one computes plain Julia's result after one recompile. G2: unchanged in its letter, with "pirate" now covering memberships; a load that brings no stakeholder's change and no winning pirate invalidates nothing. Lemma O holds as extended; Lemma M says why the allowed cases are harmless. One kind of membership.
- **Costs.** Strict mode's check must consider memberships; the facts' terms gain one definition (consented supertypes). The behaviour in the default session is what plain Julia does with a pirate: follow, recompile once.
- **Breaks.** Nothing that plain Julia allows. The refused combination is one plain Julia cannot express (a type's supertypes are fixed by its author), and whose plain analogue (`Base.show(::IO, ::S)` by `X`'s owner) is piracy.
- **Why this is the principled form.** The design already has one rule for who may change dispatch at a concrete signature (Lemma O) and one mechanism for those who may not (pirates: refused in new code, refused where they win under strict mode, followed by default). Memberships become definitions under the same rule and the same mechanism. Nothing is added but the word "membership" in two places. C3 is C4's static face, as "a trait module may not define a pirate" is strict mode's static face for methods.

#### C5. A membership-sensitive fact criterion

- **Rule.** A call `f(s::S)` is a fact only if `S`'s membership in every set that bounds a method of `f` is settled. Where `S` could still join such a set, the call is a run-time site: no edge, dispatched when it runs.
- **Guarantees.** No late membership breaks a compiled fact, by construction.
- **Costs.** Every call of a function that has a bounded method, at every type that is not yet a member, pays a dynamic dispatch and an `Any` result, forever. `f(x::Int)` where `f` has `f(::X)` and `Int` could join `X`: a run-time site. This is the trait tier spread over the whole program, at the price of the facts rule's tails everywhere.
- **Breaks.** Performance of exactly the calls the design makes cheap. Rejected; recorded because it is the first thing one thinks of.

#### C6. Membership epochs: compiled code keeps the membership of its compile world

- **Rule.** Dispatch consults memberships as of the world the caller was compiled in; a new membership advances a membership world; old code is not invalidated and keeps the old answer.
- **Guarantees.** No invalidation.
- **Costs.** The same value dispatches differently in code compiled before and after the membership: C++0x's `late_check` inconsistency ("an object could be used in exactly the same way in two places in a program with different semantics", [the research record §3](../record/other-languages-research-2026-10-16.md#3-layering-bound-code-calls-only-bound-code)) and the cause of Rust specialization's unsoundness (type checking and code generation picking different impls, [Turon 2017](https://aturon.github.io/blog/2017/07/08/lifetime-dispatch/)). Julia's world age avoids this for methods by advancing every task at the top level and invalidating; a membership world without invalidation is stale code by design. Rejected.

#### C7. What remains of "static beats dynamic": a precedence order for ties, not a mechanism

- **Rule.** Dispatch is Julia's specificity over sets. Where two applicable methods are incomparable (`f(::AbstractMatrix)` and `f(::ColTable)` on a `Matrix{Float64}` that is a member of both), the tie is broken by the member's **local precedence order**: the supertypes named in the type's definition, in order, before memberships added later. Among memberships added later no order is assumed, and the ambiguity is reported where the overlap is created (the membership or the method that completes it, as issue #5 proposed and as the design's T-83 does); the joint method is written over the tuple of sets ([traits §3.7](../reference/traits.md#37-tuples-of-traits)).
- **The analogue.** This is CLOS's and Dylan's class precedence list: "the definition of a class specifies a total ordering on that class and its direct superclasses", "each direct superclass precedes all other direct superclasses that follow it in the sequence", and the computed order must be "consistent with the local precedence order of C" ([Dylan Reference Manual, Classes](https://opendylan.org/books/drm/Classes)); the C3 linearization made it monotonic ([Barrett et al. 1996](https://dl.acm.org/doi/10.1145/236337.236343)). A type's definition lists its supertypes in order; a membership added later is appended. "Types first" is the two-rank form of that list.
- **Why keep any order at all.** Julia's signatures cannot express an intersection of two sets (`where` takes one upper bound), so the joint method for a tree type and a set has no spelling without a new type form. The tuple of sets covers two traits; "tree type before set" covers the tree-and-set case without intersection types. With intersection types in the lattice, the order could go and Julia's ambiguity rule alone would remain; that is a larger change to subtyping than W-27 plans.
- **What is an artefact, then.** The *mechanism*: an entry at `Any` deciding membership at run time with no edge. Under C4 it is not needed for G2. The *order* is a design choice with a known analogue, and it is what keeps "a library adopts traits one function at a time" true.

#### C8. The escape: a newtype

- Where C3 refuses a foreign member of a set that bounds foreign functions, the set's owner wraps: `struct AsGeo{T}; x::T; end; @implement GeoData AsGeo{T} where {T <: Shapefile.Table} by x`. This is Rust's answer to the orphan rule and the design's deferred named implementation ([traits §15](../reference/traits.md#15-named-implementations), `Via{Fast}(x)`). The wrapper is the set owner's own type, so every rule above is met. The cost is the caller's `AsGeo(t)`; [alternatives](../design/alternatives.md#other-options-considered-and-not-taken) rejected explicit wrapping as the general form, and it stays the escape only.

### 11.3 Which candidates keep the guarantees

| | One kind of membership | G1 | G2 | Lemma O | Untyped code | Existing packages | What it refuses |
|---|---|---|---|---|---|---|---|
| C1 members by owner | yes | yes | yes | as written | unchanged | unchanged | foreign members by a set's owner: BaseTraits, TraitCSV's extension |
| C2 methods by owner | yes | yes | yes | with C4's terms | unchanged | unchanged | bounded methods on foreign functions for open sets: `Base.show(::IO, ::X)` |
| **C3 the combination refused, per set** | yes | yes | yes | with C4's terms | unchanged | unchanged | only the combination; a mode per set |
| **C4 Lemma O extended; pirates' treatment** | yes | yes | yes, letter and spirit | extended | unchanged | unchanged | the combination, where it wins; C3 statically in trait modules |
| C5 membership-sensitive facts | yes | yes | yes | as written | slower everywhere | slower | nothing; costs instead |
| C6 epochs | yes | **no** (inconsistent dispatch) | yes | — | — | — | — |
| C7 precedence order | (a tie rule for any of the above) | yes | yes | — | unchanged | unchanged | nothing; orders |
| the design today (two tiers) | no | yes | yes | as written | unchanged | unchanged | a dynamic member overriding a tree method |

### 11.4 What the other languages suggest

- **Rust's coherence** is the direct precedent for C3: an impl is valid if the trait is local, or a local type appears among the impl's types before any uncovered type parameter ([reference, orphan rules](https://doc.rust-lang.org/reference/items/implementations.html#orphan-rules)). The refused `impl<T: Local> Foreign for T` is "a foreign function dispatching on a local set over arbitrary types", which is §11.1's combination. Rust needs the rule for coherence (one impl per pair); Julia needs it for facts (no late winner). The same rule serves both, which is some evidence that it is the right cut.
- **Haskell's orphan instances** ([GHC user's guide](https://downloads.haskell.org/ghc/latest/docs/users_guide/separate_compilation.html)) show the cost of the other choice: an instance declared in a module that owns neither the class nor the type is visible depending on what was imported, and GHC must read every orphan module's interface "even though this is usually wasted work". A membership in an extension is Julia's orphan instance; Lemma M says which ones are harmless (those whose counterpart method is the function owner's).
- **Swift's retroactive conformances** ([SE-0364](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0364-retroactive-conformance-warning.md)): "protocol conformances are globally unique within a process", and when two modules declare one "it is indeterminate which definition of this conformance will 'win'". Swift's problem is two memberships of one pair; ownership rules it out here. Swift's remedy (a warning, `@retroactive`) is strict mode's shape: refuse or flag the declaration, not the use.
- **Scala 3 givens** ([reference](https://docs.scala-lang.org/scala3/reference/contextual/givens.html)) state no ownership rule and resolve by scope; the design rejected scope-based selection ([alternatives](../design/alternatives.md#named-implementations-by-module-deferred)). Not a candidate.
- **Dylan's sealing** ([DRM, Define Sealed Domain](https://opendylan.org/books/drm/Define_Sealed_Domain)) is a promise about *methods* on a domain, made by the function's library, so the compiler may bind early. C3's "members by owner" is a promise about *memberships*, made by the set, so the method table at a member is complete when the member loads. It is sealing turned around: the set promises, not the function; and it costs no closed world. The design's rejection of sealing ([alternatives](../design/alternatives.md#sealing-rejected)) was of sealed functions and abstract types; a per-set membership mode is not that.
- **Fortress's exclusion relation** ([Allen et al. 2011](https://people.mpi-sws.org/~skilpat/papers/multipoly.pdf)) is needed to check overloads for ambiguity *at definition* in an open world. C7 gives that up and reports at the overlap, as issue #5 and T-83 do. If definition-time completeness is wanted later, nominal exclusions ("`Number` and `AbstractString` share no member") are the known form, and they compose with C3.
- **CLOS and Dylan's class precedence list** ([DRM, Classes](https://opendylan.org/books/drm/Classes); [Barrett et al. 1996](https://dl.acm.org/doi/10.1145/236337.236343)) are the precedent for C7: the order in a type's own definition decides ties, and later additions never reorder earlier ones (monotonicity).

### 11.5 Recommendation, and the experiment that decides

**Recommendation: C4 with C3 as its static face, and C7 for ties.** In one paragraph: a membership is a definition; the stakeholders of a signature are the owners of its function, its types and their consented supertypes; a definition by a non-stakeholder that wins at a compiled fact is a pirate, membership or method alike, and gets the pirate's treatment (refused in trait modules, refused by strict mode where it wins, followed by default); a set declares whether its members join by their own owners or by the set's owner, and the trait module refuses, at the definition, the one combination that could ever win (a foreign member of a set together with a method on that set for a foreign function); ties between a type's own supertypes and later memberships go to the former. Then `@implement X S` is `S <: X`, there is one kind of membership and one dispatch, and the only new sentence in the facts reference is the definition of consented supertypes.

What it reverses in the design: the plan to lift L-3 for open sets ([traits §5.5](../reference/traits.md#55-dispatch-types-first-then-traits), "or to another package's function where the package owns a trait the bound names"); that permission survives only for members-by-owner sets. What it keeps: everything in [traits §10](../reference/traits.md#10-who-may-implement-pirates-strict-mode), the showcase extensions (TraitCSV, BaseTraits), the ports' capability traits (their functions are their owners'), and SciML's front end on CommonSolve's `solve` (§14: `ODEProblemTrait` is a members-by-owner set, so the bounded method is allowed; E-159's note that §11 "would refuse it for good" read the rule too broadly). §14.4 refines the enforcement: the static refusal in trait modules should be a warning, and strict mode's refusal where a definition wins the rule.

**The smallest experiments** (registry rows first; minutes each; no Julia change):

| ID | Question | How | Result that decides |
|---|---|---|---|
| **U5. Does anything we built do the forbidden combination?** | How often do the demonstrators and the port's core bound a foreign function by a set whose owner declares foreign members? | A script over TraitWorld's registries in each demonstrator's and the port's trait modules: for every bounded method (`__tw_entries__`, the workers' bounds), the function's owner module against the defining module; for every implementation and family, the type's owner against the declaring module. Join on the set. Count the pairs; list them. | Zero or a handful with an obvious own-function spelling: C3 costs nothing in practice, and the recommendation stands. Many, or `Base.show` everywhere: C3's mode default must be weighed, or the design keeps the entry at `Any` for `show`-like functions only. |
| **U6. Does Lemma M's premise hold in Julia's loader?** | Are an extension's definitions visible before a dependent package compiles, in precompilation and in a session, when both triggers are in the dependent's tree? | Four tiny packages in a scratch depot: `X` (a set and a method), `T` (a type), `XTExt` (the membership), `P` depending on `X` and `T` with a precompile workload at `(T,)`. Build `P`; check with `--trace-compile` and `Base.loaded_modules` that `XTExt` loaded before `P`'s workload ran; then a session that loads `P` alone, and one that loads `T`, compiles a call at `(T,)` in `Main`, then loads `X`. | The first two show the extension first; the third shows one invalidation of `Main`'s code (a stakeholder's own session). Any other order breaks Lemma M and sends the recommendation back to C2. |
| U3 (§10) | the subtyping side | as in §10 | as in §10; U3 now also measures the cost of a `jl_subtype` lookup for memberships as facts |

Order: U6 (an hour), U5 (an afternoon), then U3 (a build). U5 and U6 decide the recommendation; U3 decides whether Julia's subtyping can carry it.

**After the quick runs (2026-10-29):** Lemma M does not hold for memberships declared in extensions (U6); see §16 and [open issue 136](../open-issues.md).

---

## 12. Sources

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
- Rust: [The Rust Reference, Traits (dyn compatibility)](https://doc.rust-lang.org/reference/items/traits.html); [The Rust Reference, Implementations (orphan rules)](https://doc.rust-lang.org/reference/items/implementations.html#orphan-rules); Turon, [Lifetime dispatch](https://aturon.github.io/blog/2017/07/08/lifetime-dispatch/), 2017.
- Swift: [SE-0335 existential `any`](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0335-existential-any.md); [SE-0352 implicitly opened existentials](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0352-implicit-open-existentials.md); [SE-0364 warning for retroactive conformances](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0364-retroactive-conformance-warning.md); Rose, [Swift Regret: Retroactive Conformances](https://belkadan.com/blog/2021/11/Swift-Regret-Retroactive-Conformances/), 2021.
- Haskell, GHC: [Orphan modules and instance declarations](https://downloads.haskell.org/ghc/latest/docs/users_guide/separate_compilation.html) (the GHC user's guide).
- Scala 3: [Given instances](https://docs.scala-lang.org/scala3/reference/contextual/givens.html).
- Dylan, CLOS: [Dylan Reference Manual, Classes (the class precedence list)](https://opendylan.org/books/drm/Classes); Barrett, Cassels, Haahr, Moon, Playford, Withington, [A Monotonic Superclass Linearization for Dylan](https://dl.acm.org/doi/10.1145/236337.236343), OOPSLA 1996 (the ACM page was not fetched; the citation is as the GOO manual gives it); [CLHS, `make-instances-obsolete`](https://www.lispworks.com/documentation/lw70/CLHS/Body/f_mk_i_1.htm).
- HotSpot: [`src/hotspot/share/code/dependencies.hpp`](https://github.com/openjdk/jdk/blob/master/src/hotspot/share/code/dependencies.hpp) (the OpenJDK repository; not fetched directly, the search found [a mirror](https://builds.shipilev.net/patch-openjdk-leyden-premain/src/hotspot/share/code/dependencies.hpp.html) and the glossary's wording "an optimistic assumption associated with an nmethod … a given class has no subclasses").
- Swift runtime: [Eagerly load protocol conformances](https://forums.swift.org/t/eagerly-load-protocol-conformances/53687) (Swift forums; the conformance cache cleared on a dynamic library's load, the lookup paths); Emerge Tools, [Swift protocol conformance](https://www.emergetools.com/blog/posts/SwiftProtocolConformance).
- SciML: [CommonSolve.jl](https://github.com/SciML/CommonSolve.jl) (its docstrings as read from `~/.julia/packages/CommonSolve/zocpq/src/CommonSolve.jl`); upstream sources in `ndport/pkgs/`.
- Julia internals read, not run: `julia-1.13/Compiler/src/tfuncs.jl` (`isa_tfunc`, `subtype_tfunc`), `src/jltypes.c` (`jl_type_union`), `src/subtype.c` (`jl_subtype`), `base/runtime_internals.jl` (`typeintersect`'s docstring).
- Clojure: [Protocols](https://clojure.org/reference/protocols).
- Go: [The Go Programming Language Specification](https://go.dev/ref/spec), interface types (the spec's wording was not fetched; secondary sources agree that satisfaction is implicit and structural).

---

## 13. Invalidation for subtyping: making `S <: X` sound for late memberships

Added on 2026-10-28 after the user's follow-up. What the discussion established: the storage simplification of §5.2 (`Kept{X}` and `Compiled{X}` collapse to `X`, `Dynamic{X} <: X`, a raw member is the `Compiled` form, the casts stay) needs only `S <: X` in Julia's subtyping; dispatch stays the design's two tiers, since no plain method is typed with a trait (decision 41) and bounded methods are entries at `Any` (L-3). What `S <: X` touches is `isa`, storage, `Union` simplification and type intersection. And abstract types work in subtyping because supertypes are fixed at a type's definition: `@implement X S` adds one later, and Julia has invalidation for method facts, not for subtyping facts.

### 13.1 What Julia relies on today, and where a late membership would break it

Read from the patched build (`julia-1.13`), not run.

| Where a subtyping answer is fixed into something | What it fixes | A late `S ∈ X` would |
|---|---|---|
| inference's `isa_tfunc` (`Compiler/src/tfuncs.jl:886`): `Const(false)` when `v` is a dispatch element not `⊑ t`, or when `!hasintersect(v, t)` | an `x isa X` branch folded away in a CodeInstance, no edge | make a dead branch live: **unsound** for the compiled code |
| `subtype_tfunc` (`tfuncs.jl:926`): `Const(false)` when `isexact_a`, or no intersection | a `T <: X` folded to `false` | the same |
| `typeintersect` in inference (`tmerge`, type assertions, `abstract_call` filtering): `Union{}` for `S` and `X` with no common subtype | a type assertion `x::X` on an `x::S` typed as always throwing; code after it dead | **unsound** |
| `Union` normalization (`jl_type_union`, `src/jltypes.c:650`): a member absorbed by a supertype | `Union{S, X}` stays two members today; after the membership the same set is `X` | sound: `Union{S, X}` is a superset of every value either way; type equality is mutual subtyping, so `Union{S, X} == X` holds after, by `<:` |
| method tables: `jl_typemap` insertion sorts methods by subtyping; `ml_matches` and the ambiguity check intersect signatures; the leaf cache maps a concrete signature to its method with a world range | which methods apply at `(S,)`, in which order | nothing, while no method in the table is typed with a set (the two tiers); if one were, this is §5.5's problem |
| the type cache (`jl_cache_type_`): canonical type objects | identity of `Union{S, X}` and of `Dynamic{X}` instances | nothing: no cached object records a negative answer |
| package images | CodeInstances with the folds above; no validation of them | the folds survive a load that brings the membership: **unsound** |
| run time: `jl_isa`, `jl_subtype` on `DataType.super` | the answer for a value | a registry read instead of the chain: fine |

The sound column has one entry; everything unsound is a **negative** answer (`false`, `Union{}`) fixed at compile time. A positive answer never changes: memberships are added, never removed (a struct redefinition in Julia 1.13 makes a new type; a redeclared implementation is the owner's change, [traits §4.9](../reference/traits.md#49-checks-at-the-declaration)). That asymmetry is the whole answer.

### 13.2 Candidate (a): memberships known before any code asks

- **Rule.** Lemma M of §11.4, applied to subtyping facts: a compiled negative answer about `S` and `X` is sound if every declaration that could make `S ∈ X` is loaded before the code that asks is compiled.
- **What must hold.** Code that folds `S <: X` knows `S` (it is specialized at `S`, or names it) and names `X` (its module depends on `X`'s package, or `X` reached it as a constant from a caller whose module does). So both `S`'s package and `X`'s package are loaded when the fold happens. Every membership between them lives in one of the two packages or in an extension of one triggered by the other (ownership, [traits §10.1](../reference/traits.md#101-who-may-implement)), and all of those are loaded once both are. The premise is weaker than §11's: no coherence rule on methods is needed, because dispatch is not involved.
- **What breaks it.** `Main`: a type and a function compiled at the prompt, then `@implement` at the prompt. The fold is stale. Revise edits likewise. Julia answers the same situation for methods with invalidation; Lemma M has no answer for `Main`, where "loaded before" has no meaning.
- **Guarantees.** For package code, folds of negatives are sound without any edge; G2 untouched. For `Main`, nothing.
- **Cost.** None at run time. The timing argument must be checked against Julia's loader once (U6, §11.5).
- **Julia change.** None beyond the registry read in `jl_subtype`.
- **Verdict.** Enough for packages, not for sessions. It explains why (c) loses nothing in packages; it is not a rule to adopt on its own.

### 13.3 Candidate (b): backedges on subtyping answers

- **Rule.** A compile-time negative answer that depends on an open set records a *membership edge* `(S, X)` on the CodeInstance, as a method fact records an edge today. `@implement X S` walks the edges of `(S, X)` and invalidates them; an image's membership edges are checked at load, as method edges are (`verify_method_graph`), or the fold is evaluated again at load as W-40's `fold_call` is ([compiler §4.4](../reference/compiler.md#44-compilerfold_call)).
- **What Julia records today.** Nothing for subtyping: `isa_tfunc`, `subtype_tfunc` and `typeintersect` return constants with no edge; CodeInstances carry method edges, binding edges and `fold_call` folds only. The change: a new edge kind in `Compiler` (recorded in the three tfuncs and in `typeintersect`'s callers where the answer is `Union{}` against an open set), a backedge list per `(type, set)` pair in the runtime, invalidation in `src/gf.c`'s walk, and image validation.
- **Prior art.** HotSpot's class hierarchy analysis: a compiled method carries dependencies, "optimistic assumptions" such as "a given class has no subclasses"; loading a class that breaks one discards the dependent methods and deoptimizes their frames, with an index from classes to dependent nmethods so that the check is cheap ([`dependencies.hpp`](https://github.com/openjdk/jdk/blob/master/src/hotspot/share/code/dependencies.hpp); the search found a mirror and a glossary, §12). That is exactly a membership edge: "`S` is not an `X`" is a hierarchy assumption. Swift's runtime takes the blunt form: its protocol-conformance cache is cleared when a dynamic library loads, since negative entries may have become stale ([forum, eagerly load protocol conformances](https://forums.swift.org/t/eagerly-load-protocol-conformances/53687); the 2020 commit it discusses). CLOS redefines classes and updates instances lazily (`make-instances-obsolete`, [CLHS](https://www.lispworks.com/documentation/lw70/CLHS/Body/f_mk_i_1.htm)), which is about layouts, not compiled dispatch; its dispatch caches are implementation matters.
- **Guarantees.** Sound everywhere, `Main` included; negatives fold as today; G2 gains a new named invalidation source, "a membership the code assumed absent", which is a stakeholder's change only where the implementer is one (§11.1's analysis: in packages it never fires by Lemma M; in `Main` it is the user's own change).
- **Cost.** A new edge kind through inference, the runtime and images: the largest Julia change of the three. Each fold of a negative against an open set costs an edge. Deoptimization of running frames is not needed: Julia's world age lets a running task keep its world, as for methods.
- **Verdict.** Correct and known, and more than is needed, because the folds it protects are rare in trait code (§13.5). Keep as the form to reach for if (c) measurably costs.

### 13.4 Candidate (c): never fold a negative; let intersection over-approximate; a registry with worlds

- **Rule.** For a set `X` that admits late members (flagged on the abstract type):
  1. `jl_subtype(S, X)` consults a membership registry when `S`'s supertype chain fails; a membership has a `min_world`, so a task in an older world does not see it, as it does not see a newer method ([facts §2.1](../reference/facts.md#21-g1-identical-or-error), "the same world");
  2. in inference, `isa_tfunc` and `subtype_tfunc` return `Const(true)` where the answer is positive and known, and `Bool` (unknown) instead of `Const(false)` where the negative answer rests on `S ∉ X` for an open `X`; the test is emitted and runs as a registry read;
  3. `typeintersect(S, X)` returns `S` where `S` is not a known member, never `Union{}`. Julia's contract allows it: "Compute a type that contains the intersection of `T` and `S`. Usually this will be the smallest such type or one close to it" (`base/runtime_internals.jl:1139`). A positive membership keeps the exact case, `typeintersect(S, X) == S` when `S <: X`;
  4. `Union` normalization uses only positive answers, which is what it does today when `jl_subtype` says `false`: `Union{S, X}` stays two members until the membership is declared, and is a superset of every value either way.
- **Guarantees.** No compiled code holds a negative membership answer, so no membership can invalidate anything: G2 holds with no new edge, in packages and in `Main`. G1 holds: a value's `isa` is answered in the caller's world. This is the design's own rule, already stated: "Compiled code never folds a membership test to `false`: the answer is taken when the code runs, so a later implementation invalidates no trait code" ([traits §14](../reference/traits.md#14-membership)), and it is the facts rule's shape: do not record what can change, compute it when it runs. The registry read without an edge is what the `Dynamic` split does for its candidate list ([facts §9](../reference/facts.md#9-the-dynamic-split)).
- **Cost.** A run-time registry read wherever `x isa X` is unknown for an open `X`, and a wider type where inference used `Union{}` to prune. Where does trait code ask a negative? Rarely: `x isa Dynamic{X}` on a raw member of a `Vector{X}` is a question about a *concrete closed* type and folds as today; `x isa X` on an item of a `Vector{X}` is positive from the element type and folds; the capability test of open issue 82 (b) (`c isa PushdownColumn` on a stored column) is the one place a negative is asked, and there a run-time read is what one wants, so that a capability declared later is seen without a recompile. Plain code asks `isa` of abstract types that are not open sets, which fold as today. U7 counts the rest.
- **Julia change.** Small: the registry and its read in `jl_subtype` and `jl_isa` (the planned piece 7 in any form); a branch in two tfuncs; `typeintersect`'s handling of a flagged set; the `min_world` on registry entries. No new edge kind, no validation, no image change.
- **The world-age split asked about.** It is the `min_world` of item 1: a membership becomes visible at the top level, like a method, and compiled code never fixed the negative, so there is nothing to split. The facts mode's split of two cache owners is not needed; the subtyping answer is the same in both modes.
- **Verdict.** The rule to adopt. (a) explains why packages lose no performance to it in practice; (b) is the fallback if U7 finds hot negative folds.

### 13.5 Anything else principled

- **Memberships of sets never asked negatively.** A set could be declared `closed` (no late members) and then fold negatives as abstract types do: `Number`, Base's trees. That is the flag of (c) with the default the other way round, and it is what "admits late members" means. No separate candidate.
- **Positive-only `Union` absorption as a type-identity rule.** Already Julia's behaviour; noted in 13.1.
- **A set as a refinement, not a supertype** (`S ∧ X`): changes nothing above; intersection types would help only the joint method of §11 C7.

### 13.6 The smallest deciding experiments

| ID | Question | How | Result that decides |
|---|---|---|---|
| **U7. How often does inference fold a negative membership?** | Would (c)'s unfolded negatives cost anything measurable? | A counter in a forked `Compiler` package (as `experiments/factscompiler` did), in `isa_tfunc`, `subtype_tfunc` and the `Union{}` branch of `typeintersect`'s callers, counting negative folds whose right-hand side is an abstract type that BaseTraits or a demonstrator declares members of (`Indexable`, `Iterable`, `Shape`, `Column`, `ODEProblemTrait`, …), against all negative folds. Run the demonstrators' suites and TraitWorld's under it. | Under 1% of negative folds, none in a hot loop: (c) is free, and §13.4 goes into W-27's plan. Hot folds in a demonstrator's loop: (b)'s edges for those sets, or `closed` for them. |
| **U8. The REPL case under (c).** | Does a function compiled before `@implement` see the membership after it, with no recompile and in the right world? | In TraitWorld as it is (the registry is `conforms`): a `Main` function that tests `conforms(typeof(x), X)` compiled at a `Main` type, then `@implement X S` at the prompt, then the call again; and the same call from a task started before the `@implement` (`invoke_in_world` with the earlier world). Count the CodeInstances compiled for the function before and after. | The second call answers `true` with no new CodeInstance; the old-world task answers `false`. Then the `min_world` rule is the one to build into the registry. |
| U3 (§10) | the subtyping probe | as in §10, with (c)'s four items as its specification | as in §10 |

Order: U8 (minutes, no change), U7 (an afternoon, no build), then U3.

---

## 14. CommonSolve's `solve`: a ground-up design

Added on 2026-10-28 after the user's follow-up. The case: E-159 (stage B, [the move-3 plan](../plans/2026-10-28-sciml-move3-today.md)); the files read: `TraitDifferentialEquations/src/TraitDifferentialEquations.jl`, `lib/ODECore/src/core.jl` (`ODEAlgorithm`, `solve_core`, `solve_ode`), `lib/TraitRodas/src/TraitRodas.jl`, [`sciml-as-traits.md`](sciml-as-traits.md) (move 3, principle 1, PB-F), CommonSolve's source (`~/.julia/packages/CommonSolve/zocpq/src/CommonSolve.jl`, [SciML/CommonSolve.jl](https://github.com/SciML/CommonSolve.jl)), and upstream's front end (`ndport/pkgs/OrdinaryDiffEq.jl/lib/DiffEqBase/src/solve.jl`, `SciMLBase.jl/src/SciMLBase.jl:49–50`).

### 14.1 What CommonSolve's `solve` is for

CommonSolve's own words: it "defines the shared solver interface functions used by solver packages that need common names without exporting them into downstream user namespaces"; "downstream packages extend these functions on problem, algorithm, iterator, or cache types that they own. This keeps independent solver ecosystems compatible without introducing type piracy or method ambiguities"; and the rule: "Extensions must dispatch the first positional argument on a type that they own." The fallback `solve(args...; kwargs...) = solve!(init(args...; kwargs...))` composes the iterator interface.

So `solve` is one verb in the user's namespace across problem kinds (ODE, nonlinear, linear, optimization), with **the problem kind's package as the stakeholder**, by CommonSolve's own rule. In SciML as built the rule is bent twice: DiffEqBase defines `solve(prob::AbstractDEProblem, args...)` for SciMLBase's types (a pirate by the letter, held by joint owners, [alternatives](../design/alternatives.md#split-packages-restructuring-or-implementations-instead-of-joint-owners)), and the algorithm packages dispatch on the *second* argument through SciMLBase's own `__solve(prob, alg::OrdinaryDiffEqAlgorithm)` (`DiffEqBase/src/solve.jl:1320`), which is a stakeholder's method because `__solve` is SciMLBase's. In the trait world the problem kind is a trait (`ODEProblemTrait`), and its members include users' types, which the kind's package does not own. "The first argument on a type you own" becomes "the first argument bounded by a set you own": the extension-trait form (PB-F), which L-3 refuses today.

### 14.2 The designs

Each: who owns what; whether it passes L-3 today and the coherence rule of §11; what users and solver authors write; what it costs; its distance from SciML.

**A. The front end as SciMLBase's bounded method on CommonSolve's `solve`, over members-by-owner sets** (the extension-trait form, PB-F; move 3 as the exploration states it).

```julia
# SciMLBase (a trait module)
@trait ODEProblemTrait{T, P} @members_by_owner begin … end       # every problem type joins in its own package
@trait ODEAlgorithm @members_by_owner begin
    solve_core(a::ODEAlgorithm, m::CoreProblem, cbs::Vector{Any}, opts::SolverOptions)::ODESolution
end
CommonSolve.solve(prob::ODEProblemTrait, alg::ODEAlgorithm; kw...) = solve_ode(prob, alg, _cbs(kw), _options(; kw...))
CommonSolve.solve(prob::ODEProblemTrait; kw...) = solve(prob, default_algorithm(prob); kw...)
# OrdinaryDiffEqTsit5 (a solver package)
@implement ODEAlgorithm Tsit5 begin solve_core(a, m, cbs, opts) = tsit5_solve(m, …) end
# a user's package
@implement ODEProblemTrait MyProb
solve(MyProb(…), Tsit5())                                        # CommonSolve's solve, re-exported by the umbrella
```

- **Owns:** CommonSolve the verb; SciMLBase the problem kind's set and the algorithm set; each solver package its algorithms; each user their problem type.
- **L-3 today:** refused (the entry at `Any` for the shape `(prob, alg)` may be added only by `solve`'s owner). With piece 7 the method is an ordinary method on a set, and L-3 has no object. Before piece 7, the entry must be shared: two kinds' packages (SciMLBase, NonlinearSolveBase) each add a bound at the same position, so the entry's `needed` list is merged at the load that brings the second (Makie D4's rule, decided as open issue 89). That is W-36, merged into W-34.
- **The coherence rule:** **allowed.** `ODEProblemTrait`'s members join in their own packages (SciMLBase's `ODEProblem` in SciMLBase, ModelingToolkit's in ModelingToolkit, a user's in the user's package), so the set is members-by-owner, and §11.1's table puts every membership in the tree of every caller at `(MyProb,)`. The method is in SciMLBase's package proper. E-159's note that §11 "would refuse it for good" was too broad: it is refused only if SciMLBase declares foreign members of `ODEProblemTrait` (a family over a package that does not depend on it), which SciML has no case for: every SciML package depends on SciMLBase.
- **Users write** one line, `@implement ODEProblemTrait MyProb`, and call `solve` as today. **Solver authors write** `@implement ODEAlgorithm Alg begin solve_core … end`, as TraitRodas does.
- **Cost:** the front end is compiled per key of the problem (its receiver type, since a problem implements `rhs!`), as SciML compiles per problem type today, behind the `@nospecializeinfer` barrier TDE has; the solver per numerical key by W-63; the algorithm `Compiled` where the caller names it (`Tsit5()` is concrete: the first-seen rule), `Dynamic` from a `Vector{ODEAlgorithm}` of a default chain.
- **Distance from SciML:** the smallest. It is DiffEqBase's `solve(prob::AbstractDEProblem, args...)` moved to SciMLBase with the abstract type replaced by the trait, and `__solve(prob, alg)` replaced by the operation `solve_core`: move 3 exactly.

**B. CommonSolve owns the sets: `Problem` and `Algorithm`, with `solve` its own bounded method.**

```julia
# CommonSolve (a trait module)
@trait Algorithm begin
    solve_with(a::Algorithm, prob, opts)::Any         # prob untyped: the kind is the algorithm's business
end
@trait Problem begin
    default_algorithm(p::Problem)::Dynamic{Algorithm}
end
solve(prob, alg::Algorithm; kw...) = solve_with(alg, prob, kw)
solve(prob::Problem; kw...) = solve(prob, default_algorithm(prob); kw...)
# SciMLBase
@trait ODEProblemTrait{T, P} <: Problem begin … end          # a user implements both: @implement (Problem, ODEProblemTrait) MyProb
# a solver package
@implement Algorithm Tsit5 begin solve_with(a, prob, kw) = solve_ode(prob, a, …) end   # bounds prob by ODEProblemTrait inside
```

- **Owns:** CommonSolve the verb and both sets; the kinds' packages their kind traits as sub-sets; solver packages their algorithms.
- **L-3 today:** passes (the entry is the owner's). **Coherence:** passes (the method is `solve`'s owner's; memberships anywhere).
- **Users write** `@implement (Problem, ODEProblemTrait) MyProb`; solver authors `@implement Algorithm Alg`.
- **Cost:** CommonSolve becomes a trait module and fixes the operations' signatures for every ecosystem (`solve_with(a, prob, opts)` with `prob` and the result untyped, so a `Dynamic` algorithm's result is `Any` until the kind's package asserts it); the keyword front end moves into each algorithm's `solve_with` or into a `Problem` operation (`prepare(p, kw)`), which splits SciML's front-end body by algorithm instead of by kind.
- **Distance from SciML:** larger: it makes a four-function namespace package into the owner of two traits, and moves the front end's body out of the kind's package. Socially possible (CommonSolve is SciML's), structurally a bigger move than A.

**C. Dispatch on the algorithm as an operation, with the umbrella's own `solve`** (TDE today).
- **Owns:** the umbrella its own `solve`; the core `solve_ode` and `ODEAlgorithm`; solver packages implement `solve_core`.
- **L-3, coherence:** pass (own functions).
- **Cost:** the one verb is lost: `using DifferentialEquations, NonlinearSolve` brings two `solve`s, which is the case CommonSolve exists for. Users of a problem type of their own reach CommonSolve's verb only by a typed method they write (`CommonSolve.solve(p::MyProb, alg) = solve_ode(p, alg)`): the "viral" cost of §9's C++ debate.
- **Distance:** it is where TDE stands; a workaround, not a design.

**D. The problem kind as an associated type of the algorithm**: `@trait Algorithm{K}` with `K = problem_kind(Self)`, `solve(prob::K, alg::Algorithm{K})`. A bound cannot name another argument's associated type as a trait of its own in the design (`solve(prob::K, …)` with `K` a trait variable is not offered, [traits §3.4](../reference/traits.md#34-parameters-and-associated-types), "a parameter bound that names its own trait" is not offered either). It reduces to B with the kind carried as a value, and buys nothing over B's untyped `prob`. Not a candidate on its own.

**E. Joint ownership: CommonSolve names the kinds' packages.** `@joint_owners SciMLBase NonlinearSolveBase LinearSolve …` in CommonSolve. Then SciMLBase's bounded method is the function owner's, and passes L-3 and the coherence rule as they stand. But only the owner declares joint owners ([traits §10.1](../reference/traits.md#101-who-may-implement)), so CommonSolve would list its dependents, against the dependency's direction; and each joint owner widens strict mode's exception ("a joint owner's change is a stakeholder's change"). It is the migration aid the design already has for split packages, not the end state ([sciml-as-traits §4, move 3](sciml-as-traits.md): "joint owners are a migration aid").

### 14.3 Recommendation

**A, with the algorithm's driver as an operation (which is D's half that TDE already built).** Reasons:
- it is move 3 as the exploration states it, and the smallest change to SciML's structure: SciMLBase takes the front end's body it already should own, and `__solve` becomes a declared operation;
- it passes the coherence rule of §11 without a per-case exception, because SciML's problem kinds are members-by-owner sets by construction: a problem type's package depends on SciMLBase, so it declares its own membership. The `@members_by_owner` mode is a statement of what is already true;
- it keeps CommonSolve a namespace package with no dependency on TraitWorld;
- users and solver authors write one line each;
- what it waits for is L-3's retirement (W-36, in W-34): with piece 7, nothing; before, the shared entry whose `needed` list merges at load (open issue 89's rule).

B is the fallback if SciML would rather not make its kind traits members-by-owner (no SciML case asks for foreign members; a case would be a kind's package implementing its trait for a package that does not depend on it). E is the stopgap the port uses now.

### 14.4 Does the coherence rule's cost in SciML disappear?

For the front end, yes: the forbidden combination does not arise, since `ODEProblemTrait`'s members are declared by their owners. The port's census (U5, §11.5) should find the front end clean once W-36 lands.

Where the rule does bite in a SciML-shaped ecosystem is elsewhere: **operator-style sets over Base's types bounding Base's functions.** SciMLOperators declares Base's matrices as operators (foreign members by the set's owner) and would want `LinearAlgebra.mul!(y, op::AbstractSciMLOperator, x)` (a bounded method on a foreign function). That is the combination. But it never wins at a compiled fact for a Base matrix, because Base's typed `mul!(::AbstractVector, ::AbstractMatrix, ::AbstractVector)` exists and a typed method beats a bound (C7). So:
- **strict mode's refusal (C4) fires nothing there,** which is right;
- **the static refusal in a trait module (C3) would refuse a harmless definition,** because it cannot see the typed method that shields it.

Refinement to §11.5's recommendation, from this case: the static check in trait modules should be a **warning** naming the combination and the typed method, if any, that shields it, and strict mode's refusal where a definition would win at a compiled fact should be **the rule**. That is how the design treats method pirates in plain code already (followed by default, refused where they win under strict mode); the trait module's own definitions get the warning instead of the error, since the combination is not a pirate by its signature. With that, the coherence rule costs SciML nothing that the facts rule does not already cost.

**The smallest experiment:** U5 (§11.5) over `ndport/pkgs` and TDE, joining bounded methods on foreign functions with sets that have foreign members, and for each hit checking whether a typed method of the function shields every member: the number of hits without a shield is the rule's true cost in SciML. Expected from reading: zero for the front end, a few operator-style hits, all shielded.

---

## 15. The project as a set of co-designed features

Added on 2026-10-28 from a discussion with the user; not adopted. The user's question: "So lets assume unification is feasible. Could we then declare the whole project as a set of largely independent features? 1) Extend AbstractTypes to Traits with explicit and late membership that guarantees properties of the types. 2) Explicit Wrapping with Dynamic that means code uses only whats known from the AbstractTypes. 3) A Callable Trait. 4) Compiling by Facts which uses only concrete facts and things known explicitly from ABstractTypes. 5) annotations that declare that a piece of code (package, module, function, block) is "compile by facts"; "fully typed by its traits" = bounded; has concrete type; "allows no pirates". Then these orthogonal (but co-designed) features combine to allow dramatically reducing invalidations, fast collections of heterogeneous but bounded data, and pervasive caching of machine code."

The user's assessment: "I think the added value of this framing is, above all, that it makes it much clearer what the shape of what we are building is. We will return to this once the ports are in a shape that we can consider finished."

### 15.1 Two foundations

The features are not independent all the way down. They share two foundations:

- **The trait declaration:** operations with signatures, associated types, `Self`. Features 1, 2, 3 and "bounded" (5b) read it.
- **Ownership:** who may declare a membership or a method. Feature 1 needs it for sound late membership (§11's coherence rule). "No pirates" (5d) is its strict, opt-in form. Feature 4 needs it so that its facts stay true.

### 15.2 The features

1. **Abstract types as traits.** Membership is declared, and may come late. Answers are monotone: a positive answer may be folded, a negative one never (§13 (c)). Associated types, families and `by` forwarding belong here.
2. **`Dynamic{X}`.** An explicit wrapper, itself a member of `X`. Code that holds it sees only `X`. Opening it (`compiled_for`) is the inverse.
3. **`Callable`.** A function value at a declared signature, called compiled or dynamically. It needs feature 1 only for its shape; it could be built in.
4. **Compiling by facts.** It uses only facts that never change: methods sealed by ownership, positive memberships, concrete types. The result is identical to plain compilation, or an error.
5. **Declarations on a scope** (a package, a module, a function, a block):
   - (a) compiled by facts;
   - (b) bounded: checked at its definition, and compiled per key (what the bound can see) rather than per concrete type;
   - (c) concretely typed (the fully-typed certificate);
   - (d) no pirates.

### 15.3 Where they are coupled

- **The key is the joint between 2 and 5b.** `Dynamic` pays off because bounded code compiles one worker per key, shared by every value with that key. Without keys, `Dynamic` is a box.
- **1 and 4 share one rule.** "Never fold a negative" is the same rule in the type system and in compiling by facts.
- **2 and 3 meet in a `Dynamic` holding a `Callable`.** W-17's costs are there today (boxing; the lookup of a trait the object lacks, E-225).
- **Each declaration of 5 needs a rule for calls that cross its edge** (bounded code calling unbounded code, facts code calling plain code). Today's entries and workers live at those edges. Unification shrinks the edges; it does not remove them. What remains is mostly feature 4 applied to calls out of bounded code.

### 15.4 The goals as combinations

| Goal | Needs |
|---|---|
| Far fewer invalidations | 4, 5d, and 1's rule on negatives; 5b shrinks the code compiled per concrete type |
| Fast collections of heterogeneous, bounded data | 1, 2, 5b (keys); 3 for function-valued fields |
| Pervasive caching of machine code | 4 (code depends only on facts with origins), 5d (nobody changes them), 5b (fewer instances) |

### 15.5 Separate declarations, a trait module, or blessed combinations

Today the trait module is the one unit that switches on 5a–5d together. The framing makes them separate declarations at any granularity. The user's note: "it might be reasonable to still have a trait module that switches on everything at once. Or to have a number of 'blessed' combinations". The options:

- **Separate declarations only.** Each is one sentence of meaning. A plain package could declare 5a and 5d first (invalidation safety, caching) and adopt bounded code later. The cost: the rules at the edges (§15.3) are stated per pair of declarations, not once.
- **A trait module as the combination of all four,** beside the separate declarations: the common case stays one line.
- **A few blessed combinations** (for example "facts and no pirates" for a plain package, "everything" for a trait module): the edge rules are stated and tested for those combinations only.

The ports so far use two of these shapes already: the forks' upstream code runs plain beside the trait kernels, and the demonstrators' trait modules switch on everything.

Return to it when the ports are in a shape that can be considered finished (the user, above).

---

## 16. What the quick runs found (2026-10-29)

Added on 2026-10-29 from the quick runs E-252 to E-258 and U9, E-259 ([the registry](../record/experiments.md) §12; numbers and builds in each README under `experiments/w83/`; [the plan](../plans/2026-10-29-unification-evidence.md#6-results-of-the-quick-runs) §6). The sections above stay as written. Where they disagree with this section, this section holds.

- **Lemma M is refuted (U6, E-252).** §11.1's premise holds only for a package strictly downstream of an extension. What Julia's loader guarantees:
  - an extension `E` is loaded before code of `P` compiles when `P` is a package (not an extension), neither `E`'s parent nor one of its triggers, and every trigger of `E` is in `P`'s tree;
  - when `P` is an extension, `E` is loaded only if `E`'s triggers are a strict subset of `P`'s;
  - for an image, only as of the environment in which the image was written.

  So a membership declared in an extension can arrive after code at `(S,)` was compiled: in the member's own package (R6, R7), in another extension (R8), or in an older image (R12). Memberships that C3 and C4 allow can win at compiled facts, and C2 repairs none of these cases (in each the bounded method is `f`'s owner's, in its package). The choice that follows is [open issue 136](../open-issues.md).
- **§13.4 item 3, refined (U7, E-255).** Never folding a negative costs nothing measurable for open sets (0.003–0.9 % of negative folds, none in a demonstrator's loop). But about 90 % of negative folds feed the compiler's bookkeeping: could a value be a `Module`, a `Type`, a `Bool`, a builtin or an opaque closure. Item 3 as written would stop these folding, and a call through a value of an open set would infer `Any`. Refinement: Core's kinds (`DataType`, `UnionAll`, `Union`, `Module`, `TypeVar`, the builtins, opaque closures, the memory types) are never late members of a set. Whether `Type{T}` may be a member is open. Negatives between types Core and Base own stay folded by ownership, so a `closed` default for the sets Core and Base own (§13.5) loses nothing measured.
- **§13.4 item 1 works as stated (U8, E-254).** A registry whose entries carry a `min_world`, read in the caller's world with no edge, gives the new answer with no new CodeInstance, and the old world keeps the old one, in plain Julia. TraitWorld's `conforms` is not built that way: it decides in the newest world and, in the product setting, a caller holds method edges into the registry.
- **The kept forms stay (U2, E-257).** A `Vector{Any}` of raw members and `Dynamic{X}` wrappers allocates nothing per element, but costs 15–57 % more than `Vector{Kept{X}}` at 2–4 types (+0.2 to +0.7 ns per element). The cost is the wrapper inside the box, a second load; raw members cost no more than `Kept`. §5.2's collapse is not taken: level 1 keeps `Kept{X}` as the storage form. An operation on an item typed `X` must be the compiler's split at the call, not a method call at `X`.
- **Rule 5 diverges in two places (U4, E-256).** `f(@nospecialize x)` is `Dynamic{Any}` only at callers that do not know `x`'s type: a caller that knows it makes inference specialize the function per type (native code once, inference per type). And today's entry rebuilds the trait object for a `Dynamic` value on every call (80–96 ns, 80 B), so at function granularity a `Dynamic` position costs what an untyped call costs. That is a cost of today's encoding ([traits T-94](../reference/traits.md#17-deviations)); a `Dynamic{Any}` position under the model needs no assembly.
- **Rule 4 buys little sharing for existing code (U1, E-258).** Of 74 generic functions rewritten with bounds, 4 are fully bounded with today's traits, 13 with each abstract type's documented interface as the contract, 20 if returning the argument were allowed. The open points are not `similar` and `axes` but the call graph (other generic functions called with the value) and iterator adaptors. Level 3 stands as a simplification of the language (§8 item 3). Two refinements are open issues 137 (`eltype(x)` as a constant of the key) and 138 (returning the bounded argument).
- **C3's cost, and "members by owner" read through consent (U5, E-253).** No code base does the forbidden combination: 0 of 127 bounded methods are on a foreign function or in an extension (partly because lowering L-3 already restricts them). "Members by owner" should count consent through the declarer's own abstract type: a type `T <: S` consents to `S`, and `S`'s owner, by a generic implementation in `S`'s package, puts `S` in the set. Likewise a member owned through a type parameter (ownership rule 3). Read so, 31 of 52 sets are members by owner, among them all the ports' domain sets (TDE 24 of 24, NetworkDynamics 4 of 4); the 21 open sets are exactly those that adopt Base's types. A hypothetical `Base.show` on each open set is shielded by Base's typed methods for every foreign member except `Factorization` and `IO`, which supports §14.4's warning.
- **Option (e) of [open issue 136](../open-issues.md) holds on the ports (U9, E-259).** Never folding a negative membership in dispatch puts a guard where a later membership could change the selected method. Over five sessions there are 7 such sites (3 distinct), all where plain code calls trait code; none is in a loop, none in bounded code, where an argument's membership is positive by construction and the ports have no subtrait method competing with a supertrait's. 3 fall on a `MethodError` path; 4 on a capability predicate written as dispatch (`is_nonlinear_algorithm`), where a run-time read is what the predicate means (§13.4), and a declared `::Bool` removes the widening. Two conditions follow, which (e) states:
  - Base's abstract types stay closed (members only through `struct S <: A`). Open, they would put guards on 1,326–4,619 specializations per session (`axes`, `eltype`, `hash`, `==`, `broadcasted`), 173–1,122 where a package could declare the membership.
  - §13.4 item 1's registry is a cell per (type, set) holding the `min_world`, fixed when the guard compiles: no measurable cost, since LLVM hoists it out of loops. A table lookup costs 27–28 ns per call, E-254's scanned `Vector` 357–375 ns.
  - A sealed variant (a set whose memberships are all declared at the member's definition or in its own package proper folds its negatives) folds 4 of the 7; open sets that take Base's types (`Positions`) keep theirs.
