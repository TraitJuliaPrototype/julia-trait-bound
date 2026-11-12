# A membership is a method

**Status:** proposal (2026-11-11, written in the main session; W-141). Not built, not adopted. Not normative: the references change when it is adopted. It follows W-140 ([the proposal](2026-11-11-membership-piracy.md), built), which made a membership *behave* as a method does. This one makes it *be* one.

## The user's words

> "Membership declarations behaving more like methods sounds correct here. Do you see a way to adapt the design and implementation to leverage existing mechanisms and principles?"

> "I want this as a proposal. The biggest pro is conceptual simplicity. Explaining and defining el was much as possible in terms of existing concepts. Then continue on the AOT line"

## The definition proposed

One sentence defines a membership:

> **`@implement X S` defines a method of `Core.implements` at `(Type{X}, Type{<:S})`. `S <: X` holds where that function has a method for the pair.**

Everything else a user has to know about a membership is then something they know about methods.

- `implements` is one generic function, in Core. It is never called by a user.
- Its method's body says how the member serves the trait: by itself, or through a forwarding field.
- A trait is an abstract type whose subtypes are named by these methods, beside `struct S <: X`.

`Callable` is defined this way today: a function is a member where one of its own methods covers the call ([compiler §7.4](../reference/compiler.md#74-callables-call)). The proposal gives every trait the rule that `Callable` has.

## What a user learns, and from where

| A question about memberships | The answer, as a fact about methods |
|---|---|
| When does a membership start to hold? | When its method is defined: from that world on. Running code sees it after it returns to the top level, or through `invokelatest` |
| What does declaring one recompile? | What a new method recompiles: the code that called at that type and got another answer. A new type's membership recompiles nothing |
| Who may declare one? | Who may define a method without piracy: the owner of the function's argument that is the trait, or the owner of the type |
| What is a pirate's membership? | A pirate's method. Followed by default, refused under strict mode where it would change compiled code |
| Can I take one back, or change it? | As a method: delete it, define it again. Revise does both |
| A membership for every `Vector{T}`? | A method with a `where` clause |
| Every `Indexable` is `Iterable`? | A method at `Type{<:Indexable}` |
| Two declarations that both apply? | Method ambiguity, reported as Julia reports it |
| Which memberships exist? | `methods(Core.implements, …)`, behind `members(X)` |
| Is it kept in my package's image? | As the package's methods are |

`intro/` would teach a membership in one paragraph, by pointing at methods. GT-14 (a membership has a world) stops being a rule of its own.

## What the references would say

| Rule today | Rule proposed |
|---|---|
| A membership is an entry on the trait, with a member pattern, an instance, a receiver, a declarer and two worlds ([compiler §4.2](../reference/compiler.md#42-memberships), [§4.3](../reference/compiler.md#43-worlds)) | A membership is a method of `implements`. Its signature holds the instance and the pattern; its module is the declarer; its worlds are a method's; its body gives the receiver |
| A positive answer folds through its entry, an edge of its own kind ([compiler §4.8](../reference/compiler.md#48-negatives-fold-with-an-edge-positives-through-entries)) | It folds through the method, an ordinary edge |
| A negative answer folds with an edge on the pair's cell ([compiler §5.6](../reference/compiler.md#56-cells)) | It folds with a missing-method edge at the pair, as a call with no method does |
| A membership invalidates as a method does ([compiler §5.5](../reference/compiler.md#55-a-membership-invalidates-as-a-method-does)) | A membership is a method; it invalidates as one |
| Who may declare a membership; a third party's is a pirate's ([traits §12.1](../reference/traits.md#121-who-may-declare-a-membership), [§12.2](../reference/traits.md#122-pirates)) | The piracy rule for methods, read at `implements` |
| G2 names memberships among a stakeholder's changes ([facts §2.2](../reference/facts.md#22-g2-stable-caches), [§10](../reference/facts.md#10-memberships)) | Lemma O covers them: no clause of their own |
| An image keeps the memberships its modules declared and activates them at load; an entry edge is checked to be in force ([compiler §9](../reference/compiler.md#9-images-and-the-machine-code-cache)) | An image keeps its methods and validates its edges |
| One instance per member; a trait's inputs ([compiler §4.6](../reference/compiler.md#46-one-instance-per-member)) | Two methods of `implements` that apply at one type with different instances are ambiguous |
| `Callable`'s memberships are its members' methods (§7.4) | The general rule, with `Callable` reading the member's own methods in place of `implements`' |

## What the implementation would drop

- `Core.MembershipCell`, its table per trait, its registration at load, its image format, its branch in image validation, `final_cells_invalidate`.
- `Core.MembershipEntry` as a kind of edge, with `jl_membership_in_force`.
- The list of declared memberships an image carries, and their activation.
- The entry's own worlds and the code that retires an entry.
- The ownership check for memberships in the library (`ownership.jl`), beside the one for methods.
- The bit `closed_after_load`, and `type_declarers_loaded`.

## What stays, and why

- **The replay of the trait's methods at the new member** ([compiler §5.5](../reference/compiler.md#55-a-membership-invalidates-as-a-method-does)). A caller of `area(::Shape)` holds an edge on `area`, not on `implements`. So a new method of `implements` must still ask which calls of the trait's methods it changes. This is the insertion code in replay, as built in W-140; it would be called from the insertion of an `implements` method.
- **An index for subtyping.** Subtyping asks about memberships on every query with a trait in it (GT-9; E-270: 1.7 to 1.8 times an unrelated pair). It would read a per-type list kept in step with `implements`' methods, as it reads the entries today. The list is a cache of the method table, not a second source.
- **Contracts and checks.** What a member must provide, and the check at the declaration, are the library's, as today.
- **The split and its table** ([compiler §7.2](../reference/compiler.md#7-operations-on-a-value-typed-by-its-trait), §7.3): code compiled once reaches a later member through the table and holds no edge.

## Choices inside it

- **(a) One function or one per trait.** *Proposed:* one function, `Core.implements`, with the trait as its first argument. The piracy rule then reads as it does for any method with two owned arguments. One function per trait would give each trait its own method table entry and backedges, at the price of a hidden name per trait.
- **(b) `struct S <: X`.** A member by its definition has no method. *Proposed:* it stays Julia's subtyping, as for any abstract type; the check still runs at its `@implement` ([traits §5.2](../reference/traits.md#52-with-the-types-definition)).
- **(c) Strict mode.** With W-140 every third-party membership is refused under strict mode (mine). As a method it would be refused where it would change compiled code, as any pirate ([traits §12.3](../reference/traits.md#123-strict-mode)). *Proposed:* the method's rule, so that there is one rule.
- **(d) What the method returns.** *Proposed:* the receiver: nothing for the member itself, the field's name for a forwarding member. The runtime reads it from the method without running it.

## Two steps

**Step 1: edges only.** Small; it tests the idea against the gates.
- A folded negative records a missing-method edge at the pair; a folded positive an ordinary edge. Entries stay as they are, and a declaration invalidates through the method table's backedges.
- Removes: cells, their image handling, the entry as an edge.
- Checks: the gates (`n18_closed_after_load`, `n20_unmet_lookup`, `f7_membership_edges`, `n3_image_memberships`), the library's suite, two orders of E-358's composition, the small cases of E-365.
- **Would stop here:** image validation of the new edges costs a lookup per folded pair that the cell did not (the profile of the goal's load, `audit/profile_load.jl`); or an abstract type's pair (an intersection no type is in) has no signature that a missing-method edge can carry.

**Step 2: the declaration is a method.** Larger; a stage of its own.
- `jl_declare_membership` inserts a method of `implements`; the per-type list becomes an index filled at insertion and at an image's activation of its methods.
- The library's `@implement` lowers to the method's definition and the check; `ownership.jl`'s membership rule goes.
- The references, `intro/`, the glossary, the decision log, in the commit that builds it.
- Checks: every gate that declares a membership; the library's and the demonstrators' suites; Revise on a membership, by hand.

## Risks

- **Bootstrap.** Core declares `Callable` and its own memberships before generic functions work. `implements` may need its first methods written by the runtime.
- **Subtyping in an older world.** Intersection and subtyping ask about earlier worlds ([compiler §4.3](../reference/compiler.md#43-worlds)). A method has the worlds; the index must answer by them as the entries do.
- **Cost to plain code.** If the index cannot be kept as cheap as the entries, GT-9 grows. To measure in step 1's shape first.
- **Method-table size and ambiguity checks.** One function with every membership of a session: thousands of methods under one name. Julia's ambiguity detection and `methods` printing at that size are untested here.
- **The trait's parameters.** A trait with inputs (`Indexable{T}`) puts a type with free variables in `Type{…}` position. Whether dispatch on `Type{X{T}} where T` gives the instance per member as the entries do is to be tried before step 2.

## What it does not touch

The attribute and `Dynamic`, the split and its table, keys, the closed build, contracts and their checks, `Callable`'s own rule.

## What to decide

1. Whether to adopt the definition as the intended design (the references then mark the present entries as a deviation).
2. Whether step 1 runs as an experiment before the AOT line is finished, or after.
3. Choice (c), strict mode's rule for a third-party membership.

## Addendum, 2026-11-12: what the build corrected

Built through stage 2 ([the build plan](2026-11-11-membership-as-method-build.md), E-367). Three statements above do not hold as written:
- **The signature.** The method is at `(Type{X}, Type{S})`. `Type{<:S}` is for an abstract member only: for a concrete member it makes insertion grow with the trait's members.
- **"Two declarations that both apply: method ambiguity."** A member of two subtraits is in their supertrait twice, with no conflict. `S <: X` holds where a method applies; the method is never called.
- **"Can I take one back: as a method, delete it."** Deleting the method does not reach the code that called a trait's method at the member. It is refused until the walk runs for a removal.

Open issue 180 holds the rest.
