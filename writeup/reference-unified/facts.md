# The facts mode: the reference

**Draft** (W-105; [the folder's README](README.md)). This page defines the facts mode: the contract between compiled code and the method table. It says what code compiled by facts may assume about other code, what it records, which code is compiled by facts, and what the two guarantees promise. It describes the mode as designed. The status line of each section says how far it is built.

- The trait language: [`traits.md`](traits.md).
- The Julia interfaces this page relies on: [`compiler.md`](compiler.md).
- Why the design takes this shape: [the design](../design.md), §2.

## Summary

- Compiled code depends on the method table through **facts**: "at the concrete signature `s`, dispatch selects `r`".
- A call is inferred, with an edge, only at a **fact signature**: a signature at which only a stakeholder or a pirate can change dispatch.
- Every other call is a **run-time site**. It records no edge and is dispatched when it runs.
- **Nothing is skipped:** a CodeInstance is invalidated exactly when a definition changes dispatch at one of its facts, or something else it recorded changes.
- Two guarantees follow:
  - **G1, identical or error:** code compiled by facts computes what plainly compiled code computes, in the same world, or raises.
  - **G2, stable caches:** no load of an unrelated package invalidates code compiled by facts. Only a stakeholder's change or a winning pirate can.
- **Memberships invalidate nothing:** compiled code never relies on a type not being a member of a trait, and a call a later membership could change is guarded.
- **Each method has a policy:** facts, plain, or its caller's. One CodeInstance per MethodInstance and policy.
  - Methods of modules that declare `facts` (trait modules among them) are compiled by facts, whoever calls them.
  - The compiler is compiled plainly, whoever calls it.
- **Strict mode** makes "a winning pirate" an error at the pirate's definition. Then code compiled by facts is invalidated only by stakeholders' changes.
- **Two settings, and `--trim`:** the product setting compiles the methods whose policy is facts; the test bed `all` compiles everything but the compiler by facts; a trimmed build compiles everything plainly.
- The facts mode needs no traits: it protects any code it compiles. Traits make it cheap.
- It promises nothing about the speed of code that is not fully typed.

## Contents

1. [Terms](#1-terms)
2. [The guarantees](#2-the-guarantees)
3. [Fact signatures](#3-fact-signatures)
4. [What is inferred across a call](#4-what-is-inferred-across-a-call)
5. [Run-time sites](#5-run-time-sites)
6. [Which code is compiled how](#6-which-code-is-compiled-how)
7. [`return_type` and reflection](#7-return_type-and-reflection)
8. [Asserted effects](#8-asserted-effects)
9. [Operations on a value typed by its trait](#9-operations-on-a-value-typed-by-its-trait)
10. [Memberships](#10-memberships)
11. [Pirates and strict mode](#11-pirates-and-strict-mode)
12. [Package images](#12-package-images)
13. [The settings](#13-the-settings)
14. [What the facts mode does not promise](#14-what-the-facts-mode-does-not-promise)
15. [Status index](#15-status-index)
16. [Deviations](#16-deviations)

---

## 1. Terms

- <a id="term-owner"></a>**Owner.** A package owns the functions, types (traits included) and bindings it defines.
  - A method belongs to the module it is evaluated in.
  - Julia (Core, Base, the standard libraries) is one owner. **Open:** whether the standard libraries are owners of their own ([open issues §1.19](../open-issues.md#1-decisions-waiting-for-the-user)).
  - A package extension belongs to its parent.
  - At the prompt, `Main` is one owner, and each module defined directly under `Main` is an owner of its own.
  - A package's joint owners own what it owns with it ([traits §12.1](traits.md#121-who-may-declare-a-membership)).
- <a id="term-stakeholder"></a>**Stakeholders of a method:** the owner of its function, and the owners of the types in its own signature, judged at every signature it applies to. A `Union`'s members count one by one. A `Vararg{T}` tail contributes `T` only where it has at least one element.
- **Stakeholders of a concrete signature `s`:** the owner of its function, and the owners of every type in `s` at any depth (each argument type, its parameters, a `Type{T}`'s `T`, a value parameter's type) and of their supertypes. **A type's supertypes include the traits it is a member of,** in the world in question.
- <a id="term-pirate"></a>**Pirate:** a method defined by none of its stakeholders. Julia's type piracy, strict for unions.
- <a id="term-fact"></a>**Fact:** "at the concrete signature `s`, in the worlds `w₁` to `w₂`, dispatch selects `r`". `r` is one method, "no method", or "ambiguous".
- **A definition wins at `s`** when dispatch at `s` selects something else after it: the new method; an ambiguity; another method after a deletion or replacement.
- **Lemma O.** A method that applies at a concrete `s` and is no pirate is defined by a stakeholder of `s`. So only a stakeholder or a pirate can change a fact. A method at a trait applies at `s` only through a membership, which makes the trait's owner a stakeholder of `s`.
- **Lemma D.** A definition that does not win at `s` leaves dispatch at `s` unchanged, whatever the order of definitions.
- <a id="term-fact-signature"></a>**Fact signature:** a call signature at which only a stakeholder or a pirate can change dispatch (§3).
- <a id="term-edge"></a>**Edge:** a dependency a CodeInstance records ([compiler §3.1](compiler.md#31-the-record)):
  - a *dispatch edge*, a fact;
  - a *result edge*, a callee's result it used as a type;
  - a *code edge*, a callee's code it inlined, propagated constants into, or evaluated;
  - a *binding edge*, a global binding it reads;
  - a *membership cell* or *positive membership* (§10).

  Julia invalidates a CodeInstance when an edge breaks, and its callers through their edges to it.
- <a id="term-run-time-site"></a>**Run-time site:** a call in code compiled by facts that records no edge (§5).
- <a id="term-fully-typed"></a>**Fully typed:** code in which every call is at a fact signature, and every call in the code compiled into it, transitively.
- **Policy:** whether a method's code is compiled by facts or plainly (§6). *Facts:* the rules of this page. *Plain:* Julia's own inference.
- **Code compiled by facts:** CodeInstances of the facts policy.
- **Kinds of methods:** facts, boundary, plain and neutral methods (§6.1).
- **Setting:** which policy a neutral method has (§13).
- **Kind:** a type whose instances are types: `DataType`, `UnionAll`, `Union`, `typeof(Union{})`.
- **A stakeholder's change:** a definition, deletion, redefinition or membership by a stakeholder of what it changes.

---

## 2. The guarantees

### 2.1 G1: identical or error

> **G1.** A call in code compiled by facts computes what the same call computes in plainly compiled code, in the same world, with the same effects, or raises.

- "The same world" is the caller's world. A task in an older world sees that world's methods and memberships.
- "Or raises": code compiled by facts raises where plain code does not only where a value lacks a declared result type: an operation's on a value typed by its trait (§9), a `Callable`'s ([traits §9](traits.md#9-functions-callable)).
- A method that strict mode refuses does not exist for plain code either.
- The attribute of a trait argument ([traits §7.4](traits.md#74-the-attribute-compiled-and-dynamic)) changes speed, never a result: both attributes run the same methods.

**Why it holds.** Every valid CodeInstance has all its facts true in the current method table:
- compilation records only true facts;
- a definition changes dispatch only where it wins, and Julia invalidates exactly the code with a fact there;
- a membership changes no fact it could break: no code relies on a non-membership, and guards cover the calls a membership could change (§10);
- a package image's code is used only if its facts hold at load (§12);
- a run-time site records nothing and dispatches as plain Julia does;
- no asserted effect applies over a run-time site (§8).

G1 depends on no declaration. A wrong performance setting can make code slow, never wrong.

**The exception: values decided by inference.** `return_type`, `promote_op`, and the element types of empty `map`s, broadcasts, comprehensions and LinearAlgebra destinations are answered by inference. The facts mode gives plain inference's answer wherever it can (§7). It can still differ where inference decides: `Union{}` where every method at a run-time site throws, or a nested `return_type` in a callee.

**Conditions.** Code that branches on what inference knows computes the same result on both branches. Threads are untested.

**Status:** Planned (W-100; the acceptance suite in `experiments/unification/`).

### 2.2 G2: stable caches

> **G2.** A CodeInstance compiled by facts is invalidated only by a definition that changes dispatch at one of its facts, a redefinition of a binding it reads, a change of a callee's code it holds a code edge to, or a change of a callee's result it holds a result edge to. By Lemma O, such a definition is a stakeholder's, or a pirate's that wins there. A load that brings neither invalidates none of it, in any order.

**Why it holds.**
- Code compiled by facts holds only facts, bindings, and edges to callees as edges to the method table (§4).
- By Lemma O, a definition that changes a fact is a stakeholder's or a pirate's; by Lemma D, a pirate that does not win changes nothing.
- A membership invalidates nothing (§10).
- **A plain callee recompiled to an equal result** keeps a caller that holds only a result edge to it: the code slot revalidates the caller ([compiler §3.3](compiler.md#33-the-code-slot)).

**Scope.** G2 covers code compiled by facts, as recorded per CodeInstance by the predicate of [compiler §3.2](compiler.md#32-g2-as-a-predicate). It does not cover:
- plain code in the product setting;
- a facts caller's code edges into plain code: when such plain code changes, the caller is compiled again;
- plain inference's answers behind `return_type` (§7), which change exactly when plain Julia's do.

**Exceptions**, named wherever G2 is claimed:
- **A stakeholder's change:** an edit, Revise, an upgrade, a stakeholder's package extension, a redeclared membership.
- **A stakeholder's extension activated by an unrelated package,** whose method applies at a fact without naming its triggers' types: followed, as the stakeholder's change; in strict mode with a warning.
- **A binding redefined from another module** (`Core.eval(Other, …)`): refused at its source in strict mode (§11.3).
- **The standard libraries count as Julia's own code.** A standard library's method that wins at a fact is a stakeholder's change.
- **A method on a closure's type defined outside the closure's module.** The fact form "a closure's call at kinds" (§3) rests on the assumption that no other module does this.

**What invalidates nothing:**
- a new membership (§10);
- a new member of a trait among the candidates of a split (§9): candidates are read without an edge.

**Status:** Planned (W-100, W-101).

### 2.3 Two tiers

| Tier | Code compiled by facts is invalidated only by | Kind of property |
|---|---|---|
| **Strict** (strict mode on) | a stakeholder's change | holds in every environment that loads without a `PirateError`, with the exceptions of §2.2 |
| **Default** | a stakeholder's change, or a pirate that wins at one of its facts | measured per environment |

- The compiled code is the same in both tiers. Strict mode acts only when a method is defined or an image's methods are activated.
- By default a winning pirate is followed, as plain Julia follows it: the code with the broken fact is compiled again, once.

**Status:** Planned (W-103).

---

## 3. Fact signatures

**The criterion.** A signature is a fact signature when only a stakeholder or a pirate can change dispatch at it. A form not listed is a run-time site, until it is shown to meet the criterion and added.

| Form | Example | Why only a stakeholder or a pirate can change it |
|---|---|---|
| **A dispatch tuple:** concrete types, not kinds; `Type{T}` with `T` known | `f(::Int, ::Float64)` | Lemma O. A membership changes no fact here: a method at a trait the type joins later is guarded (§10). |
| **Its union splits,** where Julia's union splitting splits | `g(::Union{Int, Nothing})` | Each split is a dispatch tuple, with an edge per split. |
| **Unions of concrete elements in tuple arguments,** split by the same cost | `h(::Tuple{Union{Int, Missing}, Float64})` | A tuple of concrete or union elements holds exactly the values of its splits. |
| **A closure's call at kinds** | `map(T -> sizeof(T), types)` with `types::Vector{DataType}` | Only the closure's own module adds methods to a closure's type: an assumption, not Lemma O. Julia invalidates the edge, so G1 holds; G2 rests on the assumption. |
| **A concrete `Vararg` tail** | `vcat(::Vararg{Int})` | Every value's type is a dispatch tuple with the same owners: one edge for the family. |
| **`invoke` at a declared signature,** and `hasmethod` at one | `invoke(f, Tuple{AbstractArray}, x)` | A definition changes the resolution only if its own signature contains the declared one: its definer is a stakeholder of it, or a pirate. |
| **A key, at the parts of a keyed argument** | in code compiled per key, `area(receiver)` with the receiver's concrete type | The parts' types are concrete: a dispatch tuple. |
| **A keyed argument passed on,** where one method is selected for every member with that key, guarded | `g(t)` with `t` keyed for `ColTable` | A method of `g` defined later invalidates through the edge at the key; a later member with that key that another method of `g` would take lowers the guard's cell ([compiler §6.4](compiler.md#64-calls-from-code-compiled-per-key)). |

**Which unions split** is Julia's cost model exactly: the union lengths multiplied, the largest counted as 2, a split where the cost is at most `max_union_splitting` (4 by default).

**Not fact signatures** (run-time sites):
- an abstract argument type: `show(::IO, ::Any)`, `sum(::AbstractVector)`;
- a trait instance as an argument's type, outside the operations of §9: a member's own methods may differ;
- a kind passed to a function that is not a closure: `make(::DataType)`;
- a union with more than four splits;
- a `Vararg` tail of an abstract or kind element.

**Status:** Planned (W-100, W-102).

---

## 4. What is inferred across a call

### 4.1 At a fact signature

- The callee is inferred at the signature, or at each split. Its result type, exception type, effects and constant results flow into the caller, as in plain Julia.
- The caller records the fact as an edge, one per top-level split. "No method" and "ambiguous" are facts too.
- Inlining, constant propagation, concrete and semi-concrete evaluation work as in plain Julia, on the callee's effects as inferred; asserted effects are limited by §8.
- A global binding the code reads is an edge.
- The callee's code is compiled under its own policy (§6), with a result edge or a code edge (§6.3).

### 4.2 At a run-time site

- Nothing is inferred about the callee. The call's result is `Any`, its exception type `Any`, its effects unknown, except an operation's declared result (§9).
- No edge is recorded. The frame is marked as holding a run-time site, and so is every frame that calls it.
- Julia's heuristics for calls at abstract types do not apply: no speculation over the methods that match today, no result taken from the one method that matches today, no compile-time evaluation over the call.
- `Any` spreads into the code after the call, until a declared result or an assertion narrows it.

### 4.3 Edges and invalidation

- **Exact.** A CodeInstance is invalidated if and only if a definition wins at one of its facts, a binding it reads is redefined, a CodeInstance it holds a code edge to is invalidated, or one it holds a result edge to changes its result. No invalidation is skipped, and none is added beyond Julia's own at a concrete signature.
- **A result edge** to a callee recompiled to an equal result is revalidated, not broken ([compiler §3.3](compiler.md#33-the-code-slot)).

**Status:** Planned (W-100, W-101).

---

## 5. Run-time sites

- A run-time site is dispatched when it runs, as plain Julia's dynamic dispatch is: the lookup is Julia's, in the caller's world.
- **The method found runs its code of its own policy:** a facts method its facts code, a neutral method its code under the setting's policy. This holds for every dispatch, from compiled code or through the runtime (`jl_apply`, `@cfunction` pointers, finalizers, task entry).
- **Caches at run-time sites** remember what dispatch decided, for the worlds where that holds, and are checked against the caller's world. They never decide which method runs ([compiler §8](compiler.md#8-world-checked-caches-at-dynamic-boundaries)).
- A run-time site costs a dynamic dispatch, as in plain Julia.

**Status:** Planned (W-100).

---

## 6. Which code is compiled how

### 6.1 Kinds of methods

The kind follows from the method and its module alone.

| Kind | Which methods | Declared by |
|---|---|---|
| **Facts method** | methods of a module that declares `facts`, its submodules included; methods marked always facts | the module option ([compiler §2.1](compiler.md#21-the-module-option)), which `@trait_module` sets ([traits §13](traits.md#13-scopes-trait-modules)); the method flag |
| **Boundary method** | a method compiled in its caller's policy | the method flag `:facts_boundary` |
| **Plain method** | the compiler's own code | the module flag "never by facts" |
| **Neutral method** | everything else: Base, packages, user code at the prompt | — |

**Status:** Planned (W-100).

### 6.2 The policy rule

| Kind | Policy |
|---|---|
| facts method | facts |
| plain method | plain |
| boundary method | the policy of the code that reaches it |
| neutral method | the setting's: plain in the product setting, facts under the test bed `all` |

- **One CodeInstance per MethodInstance and policy.** A CodeInstance records its policy; a lookup never takes code of another policy. A neutral method in the product setting has only plain code, whoever calls it.
- **Under `--trim`** every method is plain (§13.3).

**Status:** Planned (W-100).

### 6.3 Calls between policies

- **By inference.** A callee of another policy is inferred under its own policy, in an inference of its own. The caller uses its result type and effects, and holds:
  - a **result edge** where it emits the call and uses its result as a type. The callee's recompilation to an equal result keeps the caller (§4.3);
  - a **code edge** where it inlines the callee, propagates constants into it or evaluates it at compile time.
- **Constant propagation from plain code into code compiled by facts** infers the callee again for the constants by the facts rules, in a call stack of its own. The result stays the caller's; the caller's edges are that inference's, facts on the path the constants take.
- **Concrete and semi-concrete evaluation** from plain code into a facts callee use the callee's effects as facts inferred them, with a code edge; not where the callee holds a run-time site.
- **Code compiled by facts calling the compiler's own plain code** propagates no constants into it.
- **At run time** each callee runs its own policy's code (§5).

**Status:** Planned (W-100).

### 6.4 The compiler's own code

- The compiler is compiled plainly, whoever calls it, in both settings and in every compile queue. Otherwise a caller compiled by facts would compile the abstract interpreter by facts, as type-unstable code with run-time sites.
- The compiler runs in its own world. Reflection runs it there also with an explicit interpreter.
- **The limit.** Code compiled by facts that calls compiler functions directly holds code edges to plain compiler code, valid as long as plain Julia keeps it valid. The loss is cacheability, not correctness.

**Status:** Planned (W-100).

---

## 7. `return_type` and reflection

### 7.1 `return_type`

`return_type` (and what uses it: `collect`, `map` over an empty collection, broadcasting, `promote_op`) asks what *plain* inference gives. Under the facts mode the answer is plain inference's, in the same world. In order:
1. **The facts mode's own answer is folded** when it cannot be wider than plain inference's: a constant, a concrete type that is not a kind, or `Union{}`.
2. **Otherwise plain inference's answer is folded** when the signature has at most four concrete splits, each with exactly one covering method, and plain inference's result at each rests on facts only. The fold records an edge per split, to plain inference's result, which lives under a cache owner of its own; no code runs from it.
3. **Otherwise it is computed at run time,** by plain inference, in both settings.

So a load changes a folded answer exactly when it changes plain Julia's.

**Status:** Planned (W-100). Optional: revalidating cached answers after loads ([PE-5](../record/performance-explorations.md)).

### 7.2 Reflection

- Reflection shows the code that runs: for a facts method, facts inference; under `all`, for every method but the compiler's.
- `code_typed`, `infer_return_type`, `verify_main` and the definition-time check see that code.
- Reflection with an explicit `NativeInterpreter` runs in the compiler's world.

**Status:** Planned (W-100).

---

## 8. Asserted effects

**Rule.** In code compiled by facts, no asserted effect applies over a run-time site, at any depth:
- a method's `Base.@assume_effects` does not apply when its frame, or any frame it calls, holds a run-time site;
- a statement's does not apply when the statement's call, or any frame it calls, holds one.

**Why.** An assertion lets a caller fold the frame at compile time; the fold would rest on a dispatch no edge records.

The rule applies to every method, Base's included. A frame without run-time sites keeps its assertions.

**Status:** Planned (W-100).

---

## 9. Operations on a value typed by its trait

An operation called on a value the code knows only by its trait ([traits §7.9](traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait)) is a call on a value of an open set of types ([compiler §7](compiler.md#7-operations-on-a-value-typed-by-its-trait)).

- **Candidates.** The trait's first four members, in declaration order, read without an edge.
- **Inference:**
  - the call is inferred at the union of the candidates that the value's type admits;
  - each branch is a fact, with its edge;
  - the call branches on the value's type over the candidates, with direct calls that may inline;
  - the last branch, the **fallback**, is a run-time site for any other type. It calls the call's target for the value's type through a table keyed by the type, in the caller's world, and records no edge.
- **The result** is the operation's declared result, asserted on every branch that is not known to give it. A result of another type raises a `TypeError`. The declaration is the contract each member was checked against; the assertion catches a member checked only at its first use, or one whose method was redefined.
- **A later member** reaches the fallback and invalidates nothing. Code compiled after its declaration may branch on it.
- **Code compiled once for a trait argument** records no edge to the set of members. A member loaded after it was compiled discards none of it.

So the split takes the place of the speculation the facts mode removes (§4.2), from a declaration rather than from the methods that exist today.

**Status:** Planned (W-102).

---

## 10. Memberships

A membership makes a type a member of a trait from a world on ([traits §3.1](traits.md#31-membership)). What compiled code may assume about memberships:
- **A positive membership may be relied on,** with the CodeInstance's world range starting no earlier than the membership's.
- **A negative one never, for an open trait.** No code folds "`S` is not a member of `X`", in inference or in dispatch. The exceptions are final answers: a closed abstract type, a type that is never a member.
- **A call that a later membership could change carries a guard.** Where a method at a trait would beat the method a call selects now, should the argument's type join the trait, the call reads a cell for (type, trait) in the caller's world. It then takes the bounded method or the one selected now ([compiler §5.6](compiler.md#56-guards-and-cells)).
- **So a membership invalidates nothing.** It lowers the dispatch caches whose answer it changes, so the next call looks up again.
- **G1 holds in the caller's world:** a task in a world before the membership sees the type as a non-member; one after it, as a member.
- **Who may declare a membership** is ownership's ([traits §12.1](traits.md#121-who-may-declare-a-membership)): the trait's owner or the type's. A membership is a stakeholder's declaration; a redeclared one is a stakeholder's change (§2.2).
- **Methods at traits** invalidate as any method does: a method at a trait defined later reaches the compiled callers its insertion changes.
- **`Callable`'s memberships** are decided by the functions' methods ([compiler §7.4](compiler.md#74-callables-call)): a membership begins or ends only with a method definition of its member's type at its signature, a stakeholder's change or a pirate's, by Lemma O. Code that relied on one holds an edge to the member's dispatch and is invalidated with it, as by any such definition. The result type is no part of a membership: it is checked on return, in plain code and code compiled by facts alike.

**Status:** Planned (W-98, W-99, W-102). Until the guards exist: [compiler C-18](compiler.md#deviations).

---

## 11. Pirates and strict mode

Who may write a method, and the errors a user sees, are in [traits §12](traits.md#12-ownership-pirates-strict-mode). This section says how pirates affect validity.

### 11.1 What a winning pirate does

- **By default it is followed,** as plain Julia follows it. The code holding the broken fact is invalidated and compiled again, once.
- A pirate that wins nowhere changes nothing, in any order (Lemma D).
- A pirate defined before the code is compiled is in the method table; the code's facts select it from the start.
- A pirate loaded before a package image breaks the image's facts at that signature; that code is discarded at validation and compiled again.

**Status:** Planned (W-100).

### 11.2 Strict mode

**Rule.** A definition is refused if all three hold:
1. **It is a pirate.** An extension counts as its parent. Methods of Julia's own code are not checked.
2. **It would win at a fact of code compiled by facts,** or of plain code such code rests on: `return_type`'s plain answers, the compiler's code, and Julia's plain code the compiler calls.
3. **Its package is no stakeholder of that signature,** joint owners counted as owners.

**When.** Before the method becomes visible: at a definition, and for a package image's methods before they are activated (a refused method stays inactive; the load reports the `PirateError`).

**How it finds the facts:** from the backedges of the specializations the method could take over and of the method table; from each, the callers' backedges, transitively, through the plain code of rule 2, to code compiled by facts. After the definition, validation's log is checked: a hit the walk missed deletes the method and raises ([lowering §13](lowering.md#13-strict-mode)).

**The property it secures:** code compiled by facts is never invalidated, except by a stakeholder's change, with the exceptions of §2.2.

**Not refused:** a pirate that wins nowhere in code compiled by facts; any stakeholder's method; a membership.

**Effects.** The refused method does not exist, for plain code either; G1 holds against the world without it. Code compiled with strict mode on or off is the same code.

**Status:** Planned (W-103).

### 11.3 Strict mode's errors at their sources

In strict mode, code compiled by facts, in a session and in package images, is invalidated only by edits to code it depends on. Every other invalidating event is an error at its source, or a warning:

| Source | In strict mode |
|---|---|
| a pirate loaded before a package image whose facts it breaks | reported at the image's load, naming the pirate, the code and the fact; the code is compiled again with the pirate |
| a pirate that wins inside plain code that code compiled by facts rests on | refused at the definition |
| a package extension's winning method at a fact whose signature names none of its triggers' types | followed, as its parent's change, with a warning naming the method and the code it affects |
| a binding redefined from another module that code compiled by facts reads | refused at the redefinition |
| a deletion of a method that code compiled by facts depends on | refused at the deletion |
| a membership that makes methods at two traits ambiguous for a type | refused at the membership |

**The symmetric check** is a lint: `verify_main` reports a fact of code compiled by facts that selects a pirate defined before the code was compiled.

**Status:** Planned (W-103).

---

## 12. Package images

**What an image holds.**
- Code of both policies compiled while the image was built, with machine code.
- Code for other packages' methods its workload compiled.
- Code compiled ahead at the keys of the memberships it declares ([traits §16](traits.md#16-compiling-ahead-closed-programs)).
- The memberships it declares on other modules' types, in a list of its own.
- The check records of members checked while it was built.
- `return_type`'s answers, without machine code.

**When it stays valid.**
- **At load, the image's memberships are activated before its code is validated,** with the loading session's worlds.
- A CodeInstance is used if all its facts hold in the loading session, its memberships and cells validate, and its code edges' callees are the same. Otherwise it is discarded, and compiled again when needed.
- A fact breaks only by a stakeholder's change or a winning pirate loaded earlier, so which code is kept depends on the method table, not on the order of unrelated loads.

**A store across sessions** (paused): code compiled by facts may come from a cache of machine code kept across sessions and environments. A stored entry is used when its edges verify in the session by Julia's own validation of loaded code, and its content is the same: the lowered code of its method and of each method its code edges name, the layouts it reads, the values it embeds. Its world range comes from that validation. The record of [compiler §3.1](compiler.md#31-the-record) is kept complete for it.

**Images and the setting.** A CodeInstance records its policy, so an image built under one setting is correct under the other; the other finds no code of its own policy for a neutral method, and compiles it.

**Status:** Planned (W-103; the store paused).

---

## 13. The settings

### 13.1 The product setting

- Facts methods are compiled by facts: the methods of modules that declare `facts`, and methods marked always facts.
- Plain code keeps all of Julia's behaviour: its inference, its speed, its invalidation.
- G1 and G2 hold for code compiled by facts.

**Status:** Planned (W-100).

### 13.2 The test bed `all`

- Everything is compiled by facts, except the compiler's own code.
- **Purpose:** to test the facts rule on code as it is written. It is not a user setting.
- `JULIA_COMPILE_BY_FACTS=1`, read once per process; planned spelling `--compile-by-facts=all`. A depot of its own, for speed.
- G1 and G2 hold under `all` for all code. Strict mode protects all code but the compiler's.

**Status:** Planned (W-100).

### 13.3 Trimmed binaries

- **A `--trim` build has no facts policy.** It compiles every method plainly.
- **Why:** a binary is a closed world. Nothing loads later, so there is no cache to protect.
- G1 holds by definition. Values decided by inference can differ between a session and the binary.
- `verify_main` lists the targets a program can reach ([traits §16](traits.md#16-compiling-ahead-closed-programs)).

**Status:** Planned (W-103).

---

## 14. What the facts mode does not promise

- **The speed of code that is not fully typed.** A run-time site costs a dynamic dispatch, and its result is `Any`; Julia's heuristics for type-unstable code are gone there. The design tolerates such a slowdown where rewriting the code with traits recovers it. Fully typed code pays nothing.
- **Protection for plain code** in the product setting.
- **"Never invalidated"** outside the strict tier, and within it only with the exceptions of §2.2.
- **Identical values decided by inference** (§2.1).
- **Threads:** untested.

---

## 15. Status index

| Item | Status | Where |
|---|---|---|
| G1, identical or error | Planned (W-100) | §2.1 |
| G2, stable caches; exceptions named | Planned (W-100, W-101) | §2.2 |
| fact signatures, keys among them | Planned (W-100, W-102) | §3 |
| run-time sites; each callee runs its own policy's code | Planned (W-100) | §4.2, §5 |
| kinds of methods; the policy rule; one CodeInstance per MethodInstance and policy | Planned (W-100) | §6 |
| result edges and the code slot | Planned (W-101) | §4.3, §6.3 |
| `return_type`; reflection | Planned (W-100) | §7 |
| no asserted effect over a run-time site | Planned (W-100) | §8 |
| operations on a value typed by its trait: the split | Planned (W-102) | §9 |
| memberships invalidate nothing; guards | Planned (W-98, W-99, W-102) | §10 |
| pirates followed; strict mode and its errors at their sources | Planned (W-103) | §11 |
| package images, memberships activated before validation | Planned (W-103) | §12 |
| the store across sessions | paused | §12 |
| product setting, test bed, `--trim` | Planned (W-100, W-103) | §13 |
| standard libraries as owners | Open | §1 |

---

## 16. Deviations

Nothing of this page is built on the unified build yet; nothing is recorded.

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
