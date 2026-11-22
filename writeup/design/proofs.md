# The proofs of the guarantees

Why G1 and G2 hold, and why the facts rule has the form it has. The statements themselves, their conditions and their exceptions are in [the facts reference](../reference/facts.md) §2; the terms in its §1. This page states no rule. It gives the model, the assumptions about Julia, and the arguments, so that a change to the design can be checked against them.

## 1. The model

- **A method** has a signature and an owner ([facts §1](../reference/facts.md#1-terms)).
- **A world** is a version of the method table, with the memberships that hold in it.
- **Dispatch** at a signature `s` in a world `w`, written `D(w, s)`, is one method, the methods that match, "no method" or "ambiguous".
- **A fact** is "at `s`, in the worlds `w₁` to `w₂`, dispatch selects `r`", with `s` concrete or a signature of an owner-only function.
- **A CodeInstance** holds a record of what its code depends on: its edges ([compiler §3.1](../reference/compiler.md#31-the-record)). It is valid in a range of worlds.
- **The facts rule (R).** Code compiled by facts depends on the method table only through facts. A call that is at no fact signature records nothing and dispatches when it runs, in the caller's world ([facts §3](../reference/facts.md), §5).
- **Nothing is skipped (P).** A fact is invalidated exactly when a definition changes dispatch at its signature. No invalidation is suppressed.

## 2. What is assumed of Julia

| | The assumption | Where it is checked |
|---|---|---|
| A0 | Inference and the optimizer are sound for the edges they record: code with a true record computes what dispatch in its world computes. | Julia's own tests; Base's four test files against the control ([the playbook](../record/playbook.md) §3) |
| A1 | Julia never under-invalidates: a definition that changes dispatch at a recorded signature ends the code that recorded it. At a concrete signature its invalidation is exact: a definition invalidates if and only if it wins there or makes the call ambiguous. | E-23, on plain Julia |
| A2 | A call runs in the world current at its entry. | Julia's semantics |
| A3 | Values decided by inference are outside "identical": `return_type`, `promote_op`, the element type of an empty `map`, a broadcast, a comprehension. Plain Julia answers these differently in different contexts. | [facts §2.1](../reference/facts.md#21-g1-identical-or-error), the exception; [§7](../reference/facts.md) |
| A4 | No method is defined on another thread while code is compiled. | untested ([facts §2.1](../reference/facts.md#21-g1-identical-or-error), "Conditions") |

## 3. Theorem 1 (G1): identical or error

**Statement.** Code compiled by facts that is valid in a world `w` computes what plain code computes in `w`, with the same effects, or raises.

**Invariant.** Every valid CodeInstance has all its facts true in the current method table.

**Every event keeps the invariant.**
- *Compilation* records only true facts.
- *A definition, deletion or redefinition* changes `D(w, s)` only at signatures where it wins. By P and A1, exactly the code with a fact there is invalidated.
- *A membership* changes dispatch only at its member. It invalidates the code with a fact there, and the code that folded the pair's absence ([facts §10](../reference/facts.md#10-memberships)).
- *A package image's code* is admitted only if its facts hold at the load ([facts §12](../reference/facts.md)).
- *A run-time site* records nothing, so no event can make its record false.
- *An asserted effect* does not apply over a run-time site, at any depth ([facts §8](../reference/facts.md#8-asserted-effects)). So no fold rests on a dispatch that no edge records.

**The induction,** over the steps of an execution in `w`:
- a call at a fact signature runs `D(w, s)`, by the invariant and A0;
- a run-time site runs plain dispatch in `w`, by A2;
- an assertion of a declared result passes the value through or raises. It never converts, so no path returns a value plain code would not.

**Corollaries.**
- G1 depends on no declaration. A choice about what is compiled for a value changes speed, never a result.
- The rule about asserted effects must be transitive, because its reason is. A rule per frame lets a caller fold over a callee's run-time site.

## 4. Theorem 2 (G2): stable caches

**Statement.** A CodeInstance in the deep class is invalidated only by a stakeholder's change, or by a pirate that wins at one of its facts or of a callee's, at any depth ([facts §2.2](../reference/facts.md#22-g2-stable-caches)). A load that brings neither invalidates none of it, in any order.

**Lemma D (dominance).** A definition that does not win at `s` leaves `D(w, s)` unchanged, whatever the order of definitions.
- *Proof.* Dispatch at `s` selects by specificity among the methods that apply at `s`. A method that is not selected, and makes no ambiguity, is not in the answer. The answer does not depend on the order in which the others were defined. ∎
- It gives independence of load order.

**Lemma O (ownership).** A method that applies at a signature `s` and is no pirate is defined by a stakeholder of `s`, for `s` concrete or `s` any signature of an owner-only function.
- *Proof, `s` concrete.* A method that is no pirate is defined by the owner of its function, or of a type in its own signature. The function is `s`'s function. A type `T` in the method's signature that makes it apply at `s` is a type of `s`, a supertype of one, or a trait that a type of `s` is a member of. The stakeholders of `s` include the owners of all of these.
- *Three cases need the definition's care.*
  - A `Union` in the method's signature: the method applies at `s` through one member. So each member counts by itself.
  - A `Vararg{T}` tail: at the arity where the tail is empty, the method applies and `T` is no type of `s`. So `T` counts only where the tail has an element.
  - A method at a trait applies at a concrete `s` only through a membership. The membership makes the trait a supertype of the member, and so its owner a stakeholder of `s`.
- *Proof, an owner-only function.* A method of it that is no pirate is its owner's, and its owner is a stakeholder of every call of it. ∎

**Proof of the theorem.**
- A CodeInstance is invalidated when an edge of its record breaks, or a callee among its edges is invalidated.
- In the deep class every record, at any depth, holds only facts, bindings, memberships and edges to callees in the class.
- A fact breaks only by a definition that wins at its signature (Lemma D, A1). By Lemma O that definition is a stakeholder's or a pirate's.
- A membership ends only code that relied on its absence. Its declarer owns the trait or the type, and is a stakeholder of that code, or is a pirate ([facts §10](../reference/facts.md#10-memberships)). ∎

**Necessity: why facts are concrete.**
- In cases of a stakeholder's change and a winning pirate, plain Julia's own result changes. No design with G1 can keep the code.
- An *abstract* fact, "the methods matching `S` are exactly these", is broken by any package that defines a new subtype together with a method. That package is no pirate, and no stakeholder of anything the code computes with.
- So a fact at a concrete signature is the widest dependency that only a stakeholder or a pirate can break. An owner-only function widens it by ownership: nobody else may add a method at all.
- For the same reason a call at a kind (a type passed as a value) is no fact for an ordinary function: the owner of any type may define `f(::Type{MyT})`. It is one for a closure's call, which only the closure's owner extends.

**What the theorem does not cover** is the reference's scope ([facts §2.2](../reference/facts.md#22-g2-stable-caches), "Scope"): code that rests on a callee outside the class. The share of a package's code in the class measures the theorem's reach ([the evidence](evidence.md) §1).

## 5. Theorem 3: what a program can reach

**Statement.** What a program compiled by facts can reach is finite and listable: the closure of its entry points under their edges, and its run-time sites, each with its argument types.

- In a closed build nothing is defined later, so every set's members and every function's methods are final ([facts §3](../reference/facts.md), "What is final"). A run-time site resolves among the build's methods.
- A value known only by its trait can be one of the trait's members in the build; a `Callable` has its declared signature. So the targets of a call through a trait are a list ([traits §16](../reference/traits.md#16-compiling-ahead-closed-programs)).
- The guarantee is relative to Julia's own verifier for trimmed builds, for plain code reached through a run-time site or a pointer.

## 6. Strict mode

- Strict mode refuses a definition that would win at a fact of code compiled by facts and is no stakeholder's ([facts §11](../reference/facts.md)).
- With Theorem 2: in a session that loads without such a refusal, code in the deep class is invalidated only by a stakeholder's change. That is the strict tier of [facts §2.3](../reference/facts.md#23-two-tiers).
- It is Julia's own invalidation set, asked for before the method becomes visible. If pirates never win, strict mode never raises.

## 7. Where a proof would break

A change to the design is checked against these points first.
- **A record that is not complete:** an answer cached without its world or its edge (a dispatch cache, a table, a fold). The invariant then has nothing to invalidate. So also an answer computed at compile time from a question whose answer depends on the world: a shortcut that declares a question about a set settled by the types' structure must be complete for every shape subtyping walks, and code run by the compiler records nothing for the questions about sets it asks.
- **A fact at a signature that is not concrete** and not an owner-only function's: Lemma O fails, and an unrelated package can break it.
- **Ownership judged where the method does not apply:** a `Vararg` tail, a `Union`, a type parameter.
- **A rule whose reason is transitive, stated per frame.**
- **Code of another policy below a fact:** the theorem holds for the deep class only.
