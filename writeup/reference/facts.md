# The facts mode: the reference

This page defines the facts mode: the contract between compiled code and the method table. It says what code compiled by facts may assume about other code, what it records, which code is compiled by facts, and what the two guarantees promise. Each section ends with a status line (Implemented, Planned, Optional, Open), as [the README](README.md#conventions-for-every-reference) defines them. The [Deviations](#16-deviations) table lists where the implementation falls short of this page.

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
  - **G2, stable caches:** no load of an unrelated package invalidates code compiled by facts that is deep G2: code that rests on facts, bindings and memberships at any depth. Only a stakeholder's change or a winning pirate can.
- **A membership invalidates as a method definition does:** the code that relied on its absence, and no other. It is a stakeholder's declaration, or a pirate's (§10).
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
  - Julia (Core, Base, the standard libraries) is one owner. **Open:** whether the standard libraries are owners of their own ([open issue 19](../open-issues.md#2-design)).
  - A package extension belongs to its parent.
  - At the prompt, `Main` is one owner, and each module defined directly under `Main` is an owner of its own.
  - A package's joint owners own what it owns with it ([traits §12.1](traits.md#121-who-may-declare-a-membership)).
- <a id="term-owner-only"></a>**Owner-only function:** a function whose methods only its owner may define (§3).
  - By default: a function of a trait module (a module whose `owner_only` option is on, which `@trait_module` turns on; its submodules included) that the module neither exports nor declares `public`. A closure of such a module is one.
  - By declaration: a function its owner declares so in its module, exported or not ([traits §12.2](traits.md#122-pirates)).
  - Not by default: the internal functions of Base and the standard libraries, and the functions of a module that declares only `facts` (a package compiled by facts with one line, the porting path's first step). Packages extend such internals as a matter of course.
- <a id="term-stakeholder"></a>**Stakeholders of a method:** the owner of its function, and the owners of the types in its own signature, judged at every signature it applies to. Of a method of an owner-only function: the function's owner alone. A `Union`'s members count one by one. A `Vararg{T}` tail contributes `T` only where it has at least one element.
- **Stakeholders of a concrete signature `s`:** the owner of its function, and the owners of every type in `s` at any depth (each argument type, its parameters, a `Type{T}`'s `T`, a value parameter's type) and of their supertypes. **A type's supertypes include the traits it is a member of,** in the world in question. Of any signature of an owner-only function, concrete or not: the function's owner.
- <a id="term-pirate"></a>**Pirate:** a method defined by none of its stakeholders. Julia's type piracy, strict for unions; and a method of an owner-only function by anyone but its owner, whatever types it names.
- <a id="term-fact"></a>**Fact:** "at the signature `s`, in the worlds `w₁` to `w₂`, dispatch selects `r`", where `s` is concrete or is a signature of an owner-only function. `r` is one method, the methods that match (at a signature that is not concrete), "no method", or "ambiguous".
- **A definition wins at `s`** when dispatch at `s` selects something else after it: the new method; an ambiguity; another method after a deletion or replacement.
- **Lemma O.** A method that applies at a signature `s` and is no pirate is defined by a stakeholder of `s`, where `s` is concrete or `s` is any signature of an owner-only function. So only a stakeholder or a pirate can change a fact. A method at a trait applies at a concrete `s` only through a membership, which makes the trait's owner a stakeholder of `s`. A method of an owner-only function that is no pirate is its owner's, and its owner is a stakeholder of every call of it.
- **Lemma D.** A definition that does not win at `s` leaves dispatch at `s` unchanged, whatever the order of definitions.
- <a id="term-fact-signature"></a>**Fact signature:** a call signature at which only a stakeholder or a pirate can change dispatch (§3).
- <a id="term-edge"></a>**Edge:** a dependency a CodeInstance records ([compiler §3.1](compiler.md#31-the-record)):
  - a *dispatch edge*, a fact;
  - a *result edge*, a callee's result it used as a type;
  - a *code edge*, a callee's code it inlined, propagated constants into, or evaluated;
  - a *binding edge*, a global binding it reads;
  - an *absence edge* or *positive membership* (§10).

  Julia invalidates a CodeInstance when an edge breaks, and its callers through their edges to it.
- <a id="term-deep-g2"></a>**Deep G2:** a CodeInstance is deep G2 when every dispatch edge of its record is at a fact signature and every callee among its edges is deep G2 ([compiler §3.2](compiler.md#32-g2-as-a-predicate)). Its code rests on facts, bindings and memberships only, at any depth. The class of such CodeInstances is the *deep class*.
- <a id="term-run-time-site"></a>**Run-time site:** a call in code compiled by facts that records no edge (§5).
- <a id="term-final"></a>**Final:** an answer no later definition can change (§3, "What is final"). A call is **settled** where only a stakeholder or a pirate can change its dispatch, or nothing can.
- <a id="term-fully-typed"></a>**Fully typed,** in a setting: code in which every call, and every call in the code compiled into it, transitively, is settled in that setting (§3). **Fully typed in a session:** every such call is at a fact signature. **Fully typed when closed:** a closed build resolves every such call ([traits §14](traits.md#14-concreteness-and-fully-typed-mode)).
- **Policy:** whether a method's code is compiled by facts or plainly (§6). *Facts:* the rules of this page. *Plain:* Julia's own inference.
- **Code compiled by facts:** CodeInstances of the facts policy.
- **Kinds of methods:** facts, boundary, plain and neutral methods (§6.1).
- **Setting:** which policy a neutral method has (§13).
- **Kind:** a type whose instances are types: `DataType`, `UnionAll`, `Union`, `typeof(Union{})`.
- **A stakeholder's change:** a definition, deletion or redefinition of a method, or a membership declared, redeclared or taken back, by a stakeholder of what it changes.

---

## 2. The guarantees

### 2.1 G1: identical or error

> **G1.** A call in code compiled by facts computes what the same call computes in plainly compiled code, in the same world, with the same effects, or raises.

- "The same world" is the caller's world. A task in an older world sees that world's methods and memberships.
- "Or raises": code compiled by facts raises where plain code does not only where a value lacks a declared result type: an operation's on a value typed by its trait (§9), a `Callable`'s ([traits §9](traits.md#9-functions-callable)). Such an operation's result is asserted, never converted ([traits §7.9](traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait)): no path returns a value plain code would not. A closed type with a contract promises no result, so its operations raise nothing new (§13.1).
- A method that strict mode refuses does not exist for plain code either.
- The kept form of a trait argument ([traits §7.4](traits.md#74-the-two-kept-forms-the-box-and-the-wrapper)) changes speed, never a result, but where code asks a kept form what only the object can answer.

**Why it holds.** Every valid CodeInstance has all its facts true in the current method table:
- compilation records only true facts;
- a definition changes dispatch only where it wins, and Julia invalidates exactly the code with a fact there;
- a membership changes dispatch only at its member, and invalidates exactly the code with a fact there or a folded negative of the pair (§10);
- a package image's code is used only if its facts hold at load (§12);
- a run-time site records nothing and dispatches as plain Julia does;
- no asserted effect applies over a run-time site (§8).

G1 depends on no declaration. A wrong performance setting can make code slow, never wrong.

**The exception: values decided by inference.** `return_type`, `promote_op`, and the element types of empty `map`s, broadcasts, comprehensions and LinearAlgebra destinations are answered by inference. The facts mode gives plain inference's answer wherever it can (§7). It can still differ where inference decides: `Union{}` where every method at a run-time site throws, or a nested `return_type` in a callee.

**Conditions.** Code that branches on what inference knows computes the same result on both branches. Threads are untested.

**Status:** Implemented, but for [compiler C-45, C-47, C-51](compiler.md#deviations) (the acceptance suite, `experiments/implementation/test/acceptance/`).

### 2.2 G2: stable caches

> **G2.** A CodeInstance compiled by facts that is deep G2 is invalidated only by a definition that changes dispatch at one of its facts or at a fact of a callee among its edges, at any depth; a redefinition of a binding that it or such a callee reads; or a membership of a pair whose absence it or such a callee relied on. By Lemma O, such a definition is a stakeholder's, or a pirate's that wins there; such a membership is declared by an owner of the trait or of the type, or is a pirate's (§10). A load that brings neither invalidates none of it, in any order.

**Why it holds.**
- A CodeInstance is invalidated when an edge of its record breaks, and when a callee among its edges is invalidated.
- In the deep class every record, at any depth, holds only facts, bindings, memberships, and edges to callees in the class (§1, [compiler §3.2](compiler.md#32-g2-as-a-predicate)). So an invalidation reaches such code only through a fact, a binding or a membership.
- By Lemma O, a definition that changes a fact is a stakeholder's or a pirate's; by Lemma D, a pirate that does not win changes nothing.
- A membership invalidates only code that relied on its absence (§10). Its declarer owns the trait or the type, and is a stakeholder of that code, or is a pirate.

**Scope.** G2 covers code compiled by facts that is deep G2, as each CodeInstance records it ([compiler §3.2](compiler.md#32-g2-as-a-predicate)). It does not cover:
- plain code in the product setting. Plain code in the class is stable by the same reasoning; G2 claims it as what code compiled by facts rests on;
- code compiled by facts that rests on a callee outside the class, at any depth (a plain callee of Base that commits across a call at an abstract type): it is compiled again when that callee is. The share of a package's code compiled by facts that is in the class measures the reach of G2 ([the evidence, G-1](../design/evidence.md#1-the-guarantee));
- plain inference's answers behind `return_type` (§7), which change exactly when plain Julia's do.

**Exceptions**, named wherever G2 is claimed:
- **A stakeholder's change:** an edit, Revise, an upgrade, a stakeholder's package extension, a redeclared membership, a membership of a type and a trait that compiled code asked about (§10).
- **A stakeholder's extension activated by an unrelated package,** whose method applies at a fact without naming its triggers' types: followed, as the stakeholder's change; in strict mode with a warning.
- **A binding redefined from another module** (`Core.eval(Other, …)`): refused at its source in strict mode (§11.3).
- **The standard libraries count as Julia's own code.** A standard library's method that wins at a fact is a stakeholder's change.
- **A method on a closure's type defined outside the closure's module.** The fact form "a closure's call at kinds" (§3) rests on the assumption that no other module does this.

**What invalidates nothing:**
- a new type that joins a trait (§10): no earlier code asked about it;
- a new member of a trait among the candidates of a split (§9): candidates are read without an edge.

**Status:** Implemented.

### 2.3 Two tiers

| Tier | Code compiled by facts in the deep class is invalidated only by | Kind of property |
|---|---|---|
| **Strict** (strict mode on) | a stakeholder's change | holds in every environment that loads without a `PirateError`, with the exceptions of §2.2 |
| **Default** | a stakeholder's change, or a pirate that wins at one of its facts | measured per environment |

- The compiled code is the same in both tiers. Strict mode acts only when a method is defined or an image's methods are activated.
- By default a winning pirate is followed, as plain Julia follows it: the code with the broken fact is compiled again, once.

**Status:** Implemented, but for [traits T-96](traits.md#19-deviations).

---

## 3. Fact signatures

**What is final.** A call is inferred across where its dispatch is **settled:** only a stakeholder or a pirate can change it, or nothing can. Which calls are settled follows from one input, what is **final**: an answer no later definition can change.
- **In a session,** what is final is what Julia fixes: a closed abstract type's members, and the types that are never members. Every other answer may change by a later definition. So a settled call is one that only a stakeholder or a pirate can change: a call at a fact signature (the criterion below), an owner-only function's at any signature.
- **In a closed build,** every set's members and every function's methods are final: nothing is defined after the build. So every call whose targets the build can list is settled, and a closed build's rules follow ([compiler §7.6](compiler.md#76-a-closed-build)).
- **Plain inference** takes every answer as final, and invalidation repairs what changes: plain code is right in every world, and any load may end it (G2 does not cover it, §2.2).
- **Fully typed** is one definition with the setting as its parameter (§1): every call, in the code and in what it calls, is settled in that setting. A call settled in a session is settled when closed. A call settled only when closed (a value typed `Any` passed to a function with one method that is not owner-only) is dispatched when it runs in a session.

**The criterion.** A signature is a fact signature when only a stakeholder or a pirate can change dispatch at it. A form not listed is a run-time site, until it is shown to meet the criterion and added.

| Form | Example | Why only a stakeholder or a pirate can change it |
|---|---|---|
| **A dispatch tuple:** concrete types, not kinds; `Type{T}` with `T` known | `f(::Int, ::Float64)` | Lemma O. A membership of one of its types changes dispatch there and invalidates through the fact's edge, as a method does; it is a stakeholder's or a pirate's (§10). |
| **Its union splits,** where Julia's union splitting splits | `g(::Union{Int, Nothing})` | Each split is a dispatch tuple, with an edge per split. |
| **Unions of concrete elements in tuple arguments,** split by the same cost | `h(::Tuple{Union{Int, Missing}, Float64})` | A tuple of concrete or union elements holds exactly the values of its splits. |
| **A closure's call at kinds** | `map(T -> sizeof(T), types)` with `types::Vector{DataType}` | Only the closure's own module adds methods to a closure's type: an assumption, not Lemma O. Julia invalidates the edge, so G1 holds; G2 rests on the assumption. A closure of a module that declares `facts` is an owner-only function: the next row covers it, by Lemma O. |
| **A call of an owner-only function, at any signature** (§1) | `helper(x)` with `x::Any`; `limits(p.pos)` with `p.pos::Positions` and `limits` the package's own internal function | Lemma O with the wider reading of a pirate (§1): a method of it by anyone but its owner is a pirate's, whatever types it names. So the methods dispatch can select there are its owner's, or a pirate's. |
| **A concrete `Vararg` tail** | `vcat(::Vararg{Int})` | Every value's type is a dispatch tuple with the same owners: one edge for the family. |
| **`invoke` at a declared signature,** and `hasmethod` at one | `invoke(f, Tuple{AbstractArray}, x)` | A definition changes the resolution only if its own signature contains the declared one: its definer is a stakeholder of it, or a pirate. |

**Which unions split** is Julia's cost model exactly: the union lengths multiplied, the largest counted as 2, a split where the cost is at most `max_union_splitting` (4 by default).

**Not fact signatures** (run-time sites), at a function that is not owner-only:
- an abstract argument type: `show(::IO, ::Any)`, `sum(::AbstractVector)`;
- a trait instance as an argument's type, outside the operations of §9: a member's own methods may differ;
- a kind passed to a function that is not a closure: `make(::DataType)`;
- a union with more than four splits;
- a `Vararg` tail of an abstract or kind element.

**Owner-only functions** (the row above; §1):
- **By default** each function of a trait module (its `owner_only` option on: `@trait_module`'s default, [traits §12.2](traits.md#122-pirates)), its submodules included, that the module neither exports nor declares `public`, is owner-only. So is a closure of such a module, and the function's keyword calls (a call with keywords is a call of `Core.kwcall` at the function's type, whose methods the function's definitions make).
- **By declaration** a function's owner makes any function of its module owner-only, an exported one included ([traits §12.2](traits.md#122-pirates)).
- **Not by default:** Base's and the standard libraries' internal functions, which packages extend, and every function of a module that declares only `facts`, as an existing package does on the porting path's first step: its internal functions are the interface other packages extend. The default does not depend on how the caller is compiled: the callee's module decides.
- **The call is inferred as plain inference infers it** at its signature, the callee under its own policy, with Julia's ordinary dispatch edge. Where Julia's method matching gives up (more matches than `max_methods`), the call is a run-time site, as at any fact ([compiler §1.3](compiler.md#13-run-time-sites)).
- **A pirate of it is followed** by default, and its edge invalidates the code: G1 holds ([§2.1](#21-g1-identical-or-error)). It is refused in strict mode where it wins at a fact (§11.2), and in a scope that declares `no_pirates` ([traits §12.2](traits.md#122-pirates)).
- **Whether a function is owner-only is read where a call of it is inferred.** Its owner may lift it later, by `public` or `export`. That is the owner's change: it ends the code that relied on it, as the redefinition of a binding the code reads ends that code.

**Status:** Implemented, but for [compiler C-130](compiler.md#deviations) (a later `public` or `export` ends nothing); fully typed in a closed build: Implemented, but for [compiler C-103](compiler.md#deviations) and [traits T-122](traits.md#19-deviations); with keys, two more forms: Optional ([extensions §1.3](extensions.md#13-calls-from-code-compiled-per-key)).

---

## 4. What is inferred across a call

### 4.1 At a fact signature

- The callee is inferred at the signature, or at each split. Its result type, exception type, effects and constant results flow into the caller, as in plain Julia.
- The caller records the fact as an edge, one per top-level split. "No method" and "ambiguous" are facts too.
- Inlining, constant propagation, concrete and semi-concrete evaluation work as in plain Julia, on the callee's effects as inferred; asserted effects are limited by §8.
- A global binding the code reads is an edge.
- The callee's code is compiled under its own policy (§6); the caller holds an edge to it (§6.3).

### 4.2 At a run-time site

- Nothing is inferred about the callee. The call's result is `Any`, its exception type `Any`, its effects unknown, except an operation's declared result (§9).
- No edge is recorded. The frame is marked as holding a run-time site, and so is every frame that calls it.
- Julia's heuristics for calls at abstract types do not apply: no speculation over the methods that match today, no result taken from the one method that matches today, no compile-time evaluation over the call.
- `Any` spreads into the code after the call, until a declared result or an assertion narrows it.

### 4.3 Edges and invalidation

- **Exact.** A CodeInstance is invalidated if and only if a definition wins at one of its facts, a binding it reads is redefined, a membership ends an absence it relied on, or a CodeInstance it holds an edge to is invalidated. No invalidation is skipped, and none is added beyond Julia's own at a concrete signature.

**Status:** Implemented, but for [compiler C-52](compiler.md#deviations).

---

## 5. Run-time sites

- A run-time site is dispatched when it runs, as plain Julia's dynamic dispatch is: the lookup is Julia's, in the caller's world.
- **The method found runs its code of its own policy:** a facts method its facts code, a neutral method its code under the setting's policy. This holds for every dispatch, from compiled code or through the runtime (`jl_apply`, `@cfunction` pointers, finalizers, task entry).
- **Caches at run-time sites** remember what dispatch decided, for the worlds where that holds, and are checked against the caller's world. They never decide which method runs ([compiler §8](compiler.md#8-world-checked-caches-at-dynamic-boundaries)).
- A run-time site costs a dynamic dispatch, as in plain Julia.

**Status:** Implemented.

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

**Status:** Implemented.

### 6.2 The policy rule

| Kind | Policy |
|---|---|
| facts method | facts |
| plain method | plain |
| boundary method | the policy of the code that reaches it |
| neutral method | plain in the product setting; under the test bed `all`, the policy of the code that reaches it |

- **The code that reaches a method** is the code that calls it, of its own policy. Where the runtime itself calls (task entry, finalizers, `__init__`, a C caller), the setting's default reaches: plain in the product setting, facts under the test bed ([compiler §2.3](compiler.md#23-one-codeinstance-per-methodinstance-and-policy)). So under the test bed everything user code reaches is compiled by facts, and the compiler's own calls stay plain.
- **One CodeInstance per MethodInstance and policy.** A CodeInstance records its policy; a lookup never takes code of another policy. A neutral method in the product setting has only plain code, whoever calls it.
- **Under `--trim`** every method is plain (§13.3).

**Status:** Implemented, but for [compiler C-49](compiler.md#deviations).

### 6.3 Calls between policies

- **By inference.** A callee of another policy is inferred under its own policy, in an inference of its own. The caller uses its result type and effects, and holds:
  - a **result edge** where it emits the call and uses its result as a type;
  - a **code edge** where it inlines the callee, propagates constants into it or evaluates it at compile time.
- **Constant propagation from plain code into code compiled by facts** infers the callee again for the constants by the facts rules, in a call stack of its own. The result stays the caller's; the caller's edges are that inference's, facts on the path the constants take.
- **Concrete and semi-concrete evaluation** from plain code into a facts callee use the callee's effects as facts inferred them, with a code edge; not where the callee holds a run-time site.
- **Code compiled by facts calling the compiler's own plain code** propagates no constants into it.
- **At run time** each callee runs its own policy's code (§5). A callee that takes the policy of the code reaching it runs the code of the caller's policy, through every way of calling: a generic call, `invoke`, a splat, `invokelatest`.

**Status:** Implemented, but for [compiler C-45, C-50](compiler.md#deviations).

### 6.4 The compiler's own code

- The compiler is compiled plainly, whoever calls it, in both settings and in every compile queue. Otherwise a caller compiled by facts would compile the abstract interpreter by facts, as type-unstable code with run-time sites.
- The compiler runs in its own world. Reflection runs it there also with an explicit interpreter.
- **The limit.** Code compiled by facts that calls compiler functions directly holds code edges to plain compiler code, valid as long as plain Julia keeps it valid. The loss is cacheability, not correctness.

**Status:** Implemented.

---

## 7. `return_type` and reflection

### 7.1 `return_type`

`return_type` (and what uses it: `collect`, `map` over an empty collection, broadcasting, `promote_op`) asks what *plain* inference gives. Under the facts mode the answer is plain inference's, in the same world. In order:
1. **The facts mode's own answer is folded** when it cannot be wider than plain inference's: a constant, a concrete type that is not a kind, or `Union{}`.
2. **Otherwise plain inference's answer is folded** when the signature has at most four concrete splits, each with exactly one covering method, and plain inference's result at each rests on facts only. The fold records an edge per split, to plain inference's result, which lives under a cache owner of its own; no code runs from it.
3. **Otherwise it is computed at run time,** by plain inference, in both settings.

So a load changes a folded answer exactly when it changes plain Julia's.

**Status:** Implemented, but for [compiler C-47](compiler.md#deviations); revalidating cached answers after loads: Optional.

### 7.2 Reflection

- Reflection shows the code that runs: for a facts method, facts inference; under `all`, for every method but the compiler's.
- `code_typed`, `infer_return_type`, `verify_main` and the definition-time check see that code.
- Reflection with an explicit `NativeInterpreter` runs in the compiler's world.

**Status:** Implemented, but for F-24 and [compiler C-115](compiler.md#deviations).

---

## 8. Asserted effects

**Rule.** In code compiled by facts, no asserted effect applies over a run-time site, at any depth:
- a method's `Base.@assume_effects` does not apply when its frame, or any frame it calls, holds a run-time site;
- a statement's does not apply when the statement's call, or any frame it calls, holds one.

**Why.** An assertion lets a caller fold the frame at compile time; the fold would rest on a dispatch no edge records.

The rule applies to every method, Base's included. A frame without run-time sites keeps its assertions.

**Status:** Implemented.

---

## 9. Operations on a value typed by its trait

An operation called on a value the code knows only by its trait ([traits §7.9](traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait)) is a call on a value of an open set of types ([compiler §7](compiler.md#7-operations-on-a-value-typed-by-its-trait)). A value typed by a closed abstract type with a contract takes the split at the contract's operations, over the type's declared candidates, with no declared result ([compiler §7.1](compiler.md#71-the-rule)).

- **Candidates.** The trait's first four members, in declaration order, read without an edge.
- **Inference:**
  - the call is inferred at the union of the candidates that the value's type admits;
  - each branch is a fact, with its edge;
  - the call branches on the value's type over the candidates, with direct calls that may inline;
  - the last branch, the **fallback**, is a run-time site for any other type. It calls the call's target for the value's type through a table keyed by the type, in the caller's world, and records no edge.
- **The result** is the operation's declared result, asserted on every branch not known to give it and never converted: a result of another type raises a `TypeError` ([traits §7.9](traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait), [§11](traits.md#11-checks-and-errors)). The declaration is the contract each member was checked against, and a member keeps its check while it is a member ([traits §5.10](traits.md#510-checks)); the assertion catches what the check does not reach: a result at an abstract further argument, a method already in the session when an image's membership loads, and inference's own limits.
- **A later member** reaches the fallback and invalidates nothing. Code compiled after its declaration may branch on it.
- **Code compiled once for a trait argument** records no edge to the set of members. A member loaded after it was compiled discards none of it.
- **No method at the trait takes part in an operation without a default.** The declared result is read from the trait's contract ([compiler §4.1](compiler.md#41-sets)), without an edge: it never changes after the declaration. Each branch, the fallback and a dynamic call reach the member's own method ([traits §4.1](traits.md#41-operations)). So such an operation adds no method at a set: declaring the trait, or a membership in it, ends no code through it. Only a default is a method at the set, and it invalidates as any method does (§10).

So the split takes the place of the speculation the facts mode removes (§4.2), from a declaration rather than from the methods that exist today.

**Status:** Implemented, but for [compiler C-38, C-39](compiler.md#deviations).

---

## 10. Memberships

A membership makes a type a member of a trait from a world on ([traits §3.1](traits.md#31-membership)). What compiled code may assume about memberships:
- **A positive membership may be relied on,** with the CodeInstance's world range starting no earlier than the membership's, and ending where it is taken back.
- **A negative one may be relied on, with an edge.** Code that folds "`S` is not a member of `X`", in inference or in dispatch, records the pair. A membership of that pair declared later invalidates it. A closed abstract type and a type that is never a member need no edge: their answer is final ([traits §3.4](traits.md#34-open-and-closed)).
- **A call selects its method without a guard.** It holds its ordinary dispatch edge. A membership replays the trait's methods at the new member and invalidates the callers whose selection changes ([compiler §5.5](compiler.md#55-a-membership-invalidates-as-a-method-does)).
- **So a membership invalidates the code that relied on its absence, and no other,** as a method definition invalidates its callers ([compiler §4.8](compiler.md#48-negatives-fold-with-an-edge-positives-through-entries)). A new type that joins invalidates nothing: no earlier code asked about it, and a call at a wider signature matched the trait's methods already. Code compiled once at a trait reaches a later member through its table and relies on no absence ([compiler §7.3](compiler.md#73-the-table-of-a-calls-targets)).
- **G1 holds in the caller's world:** a task in a world before the membership sees the type as a non-member; one after it, as a member.
- **A membership taken back** ([traits §5.13](traits.md#513-taking-a-membership-back)) ends the code that relied on it, as a deleted method ends its callers: the code that folded the positive, through its edge to the membership's method, and the callers whose selection at the member changes, by the walk run for the removal ([compiler §5.5](compiler.md#55-a-membership-invalidates-as-a-method-does), [§5.6](compiler.md#56-the-memberships-method-and-the-edges)). No other code ends: a call that dispatched to the member's own method keeps its fact. It is a stakeholder's change, or a pirate's, as its declaration is. A task in a world before it keeps the membership.
- **Who may declare a membership** is ownership's ([traits §12.1](traits.md#121-who-may-declare-a-membership)): the trait's owner or the type's. A membership is a stakeholder's declaration; a redeclared one is a stakeholder's change (§2.2). One by neither owner is a pirate's ([traits §12.2](traits.md#122-pirates)), and behaves as a pirate's method: followed by default, refused under strict mode where it would change code compiled by facts (§11.2).
- **Methods at traits** invalidate as any method does: a method at a trait defined later reaches the compiled callers at its members. A caller at a type that is no member stays valid; the membership reaches it when the type joins.
- **`Callable`'s memberships** are entries, as any trait's: every `Function` is a member of every `Callable{A, S}`, and a callable type that is no `Function` where its owner declares it ([compiler §7.4](compiler.md#74-callables-call)). A function's signature is checked where it is boxed, and its result on return from the box, in plain code and code compiled by facts alike. A method definition begins or ends no membership.

**Status:** Implemented, but for [compiler C-77, C-79, C-88](compiler.md#deviations) (gates `n7_guards`, `n18_closed_after_load`, `n25_image_before_set_method`, `n26_callable_late_method`).

---

## 11. Pirates and strict mode

Who may write a method, and the errors a user sees, are in [traits §12](traits.md#12-ownership-pirates-strict-mode). This section says how pirates affect validity. A pirate is as §1 defines it: a method of another owner's owner-only function is one, whatever types it names.

### 11.1 What a winning pirate does

- **By default it is followed,** as plain Julia follows it. The code holding the broken fact is invalidated and compiled again, once.
- **And it is reported** where the code it ends is deep G2 (§1, §2.2): a warning names the method, its definer and the code ([traits §12.2](traits.md#122-pirates)). Deep-G2 code is ended only by a stakeholder's change or a pirate, so the report tells exactly the pirates that cost such code. It is silent only by choice, and refused in strict mode (§11.2). The report reads what the invalidation itself holds: no walk before the definition and no cost at a load ([compiler §10.2](compiler.md#102-hooks-for-strict-mode)).
- A pirate that wins nowhere changes nothing, in any order (Lemma D).
- A pirate defined before the code is compiled is in the method table; the code's facts select it from the start.
- A pirate loaded before a package image breaks the image's facts at that signature; that code is discarded at validation and compiled again.

**Status:** Implemented (test `report.jl`).

### 11.2 Strict mode

**Rule.** A definition is refused if all three hold:
1. **It is a pirate:** a pirate's method, or a membership by neither the trait's owner nor the type's. An extension counts as its parent. Methods of Julia's own code are not checked.
2. **It would win at a fact of code in the deep class** (§2.2) that code compiled by facts is or rests on (for a membership: the answer that the type is no member, or a call at the type where a method at the trait would be selected): the code compiled by facts, the plain callees in the class below it, `return_type`'s plain answers.
3. **Its package is no stakeholder of that signature,** joint owners counted as owners.

**When.** Before the method or the membership becomes visible: at a definition or a declaration, and for a package image's methods and memberships before they are activated (a refused one stays inactive; the load reports the `PirateError`).

**How it finds the facts:** from the backedges of the specializations the method could take over and of the method table; from each caller in the deep class, the callers' backedges, transitively, through code in the class, to code compiled by facts. A caller outside the class ends the walk: what rests on it is outside the class too. After the definition, validation's log is checked: a hit the walk missed deletes the method and raises ([lowering §13](lowering.md#13-strict-mode)). For a membership the facts are the absence edges its method meets ([compiler §5.6](compiler.md#56-the-memberships-method-and-the-edges)) and, for each method at the trait, the facts that method would win at with the member in the trait's place.

**The same walk for a member's check.** A member's check is its serving instances, kept with their edges ([traits §5.10](traits.md#510-checks)). A definition that would end one is found by this walk over their backedges, in every mode, and is refused where the call, inferred again with it, leaves the declared result or becomes ambiguous. So strict mode's refusal and the check's are one mechanism. At an image's load only the check instances that fail validation are inferred again.

**The property it secures:** code compiled by facts in the deep class is never invalidated, except by a stakeholder's change, with the exceptions of §2.2.

**Not refused:** a pirate that wins nowhere in the deep class; any stakeholder's method or membership. A pirate that wins only in code outside the class is followed, as a load's method there is.

**Effects.** The refused method or membership does not exist, for plain code either; G1 holds against the world without it. Code compiled with strict mode on or off is the same code.

**Status:** Implemented, but for [traits T-112](traits.md#19-deviations); the same walk for a member's check: Planned, with [traits T-129](traits.md#19-deviations).

### 11.3 Strict mode's errors at their sources

In strict mode, code compiled by facts in the deep class, in a session and in package images, is invalidated only by edits to code it depends on. Every other invalidating event is an error at its source, or a warning:

| Source | In strict mode |
|---|---|
| a pirate loaded before a package image whose facts it breaks | reported at the image's load, naming the pirate, the code and the fact; the code is compiled again with the pirate |
| a pirate that wins inside plain code in the deep class that code compiled by facts rests on | refused at the definition |
| a package extension's winning method at a fact whose signature names none of its triggers' types | followed, as its parent's change, with a warning naming the method and the code it affects |
| a binding redefined from another module that code compiled by facts reads | refused at the redefinition |
| a deletion of a method that code compiled by facts depends on | refused at the deletion |
| a membership that makes methods at two traits ambiguous for a type | refused at the membership |
| a pirate's membership that would change code compiled by facts | refused at the declaration; in a package image, at the load |

**The symmetric check** is a lint: `verify_main` reports a fact of code compiled by facts that selects a pirate defined before the code was compiled.

**Status:** Implemented, but for [traits T-96](traits.md#19-deviations).

---

## 12. Package images

**What an image holds.**
- Code of both policies compiled while the image was built, with machine code.
- Code for other packages' methods its workload compiled.
- Code compiled ahead for the memberships it declares ([traits §16](traits.md#16-compiling-ahead-closed-programs)).
- The memberships it declares on other modules' types, in a list of its own.
- The checks of the members checked while it was built ([lowering §11](lowering.md#11-checks-errors-and-what-images-keep)).
- `return_type`'s answers, without machine code.

**When it stays valid.**
- **At load, the image's memberships are activated before its code is validated,** with the loading session's worlds.
- A CodeInstance is used if all its facts hold in the loading session, its membership edges validate, and its code edges' callees are the same. Otherwise it is discarded, and compiled again when needed.
- A fact breaks only by a stakeholder's change or a winning pirate loaded earlier. So which code in the deep class is kept depends on the method table, not on the order of unrelated loads.
- **Code a session reaches only by a dynamic call** (another package's method, compiled for the image's code) is kept where it is deep G2, of either policy ([compiler §9](compiler.md#9-images-and-the-machine-code-cache)). Code outside the class could be ended by an unrelated load, and is compiled where a session needs it.

**A store across sessions:** code compiled by facts may come from a cache of machine code kept across sessions and environments. A stored entry is used when its edges verify in the session by Julia's own validation of loaded code, and its content is the same: the lowered code of its method and of each method its code edges name, the layouts it reads, the values it embeds. Its world range comes from that validation. The record of [compiler §3.1](compiler.md#31-the-record) is kept complete for it.

**Images and the setting.** A CodeInstance records its policy, so an image built under one setting is correct under the other; the other finds no code of its own policy for a neutral method, and compiles it.

**Status:** Implemented; a store across sessions: Optional.

---

## 13. The settings

### 13.1 The product setting

- Facts methods are compiled by facts: the methods of modules that declare `facts`, and methods marked always facts.
- Plain code keeps all of Julia's behaviour: its inference, its speed, its invalidation, its results. At a value typed by a closed abstract type with a contract (Base's `IO`) a call of one of its operations is compiled as the split, in plain code too, with its result `Any` and nothing converted or asserted ([compiler §7.1](compiler.md#71-the-rule)): the split changes how the call is dispatched, not what it returns.
- G1 and G2 hold for code compiled by facts.

**Status:** Implemented.

### 13.2 The test bed `all`

- Everything is compiled by facts, except the compiler's own code.
- **Purpose:** to test the facts rule on code as it is written. It is not a user setting.
- `JULIA_COMPILE_BY_FACTS=1`, read once per process; planned spelling `--compile-by-facts=all`. A depot of its own, for speed.
- G1 and G2 hold under `all` for all code. Strict mode protects all code but the compiler's.

**Status:** Implemented; the flag `--compile-by-facts=all`: Planned.

### 13.3 Trimmed binaries

- **A `--trim` build is the facts rule with everything final** (§3, "What is final"). A binary is a closed world: nothing loads later, so every set's members and every function's methods are final, and there is no cache to protect.
- **Where everything is final, plain inference's assumption holds.** So the build infers every method by Julia's own inference and records no policy ([compiler §2.6](compiler.md#26---trim)): no third rule.
- **Its sets are closed for the same reason:** an operation on a value known only by its trait is compiled for the members the build has ([compiler §7.6](compiler.md#76-a-closed-build)).
- G1 holds by definition. Values decided by inference can differ between a session and the binary.
- `verify_main` lists the targets a program can reach ([traits §16](traits.md#16-compiling-ahead-closed-programs)).

**Status:** Implemented, but for [compiler C-103](compiler.md#deviations).

---

## 14. What the facts mode does not promise

- **The speed of code that is not fully typed.** A run-time site costs a dynamic dispatch, and its result is `Any`; Julia's heuristics for type-unstable code are gone there. The design tolerates such a slowdown where rewriting the code with traits recovers it. Fully typed code pays nothing.
- **Protection for plain code** in the product setting.
- **"Never invalidated"** outside the strict tier, and within it only with the exceptions of §2.2.
- **Stable caches for code outside the deep class** (§2.2): code compiled by facts that rests on a callee outside the class is compiled again when that callee is.
- **Identical values decided by inference** (§2.1).
- **Threads:** untested.

---

## 15. Status index

| Item | Status | Where |
|---|---|---|
| G1, identical or error | Implemented, but for compiler C-45, C-47, C-51 | §2.1 |
| G2, stable caches, for the deep class; exceptions named | Implemented | §2.2 |
| fact signatures | Implemented, but for compiler C-130; with keys, two more forms: Optional ([extensions §1.3](extensions.md#13-calls-from-code-compiled-per-key)) | §1, §3 |
| run-time sites; each callee runs its own policy's code | Implemented | §4.2, §5 |
| kinds of methods; the policy rule; one CodeInstance per MethodInstance and policy | Implemented, but for compiler C-45, C-49, C-50 | §6 |
| `return_type`; reflection | Implemented, but for F-24 and compiler C-47, C-115 | §7 |
| no asserted effect over a run-time site | Implemented | §8 |
| operations on a value typed by its trait: the split | Implemented, but for compiler C-38, C-39 | §9 |
| a membership invalidates as a method does | Implemented, but for compiler C-77, C-79, C-88 | §10 |
| pirates followed; strict mode and its errors at their sources | Implemented, but for traits T-96, T-112; the same walk for a member's check: Planned, with traits T-129 | §11 |
| package images, memberships activated before validation | Implemented | §12 |
| the store across sessions | Optional | §12 |
| product setting, test bed, `--trim` | Implemented, but for compiler C-103 (`--trim`); the flag `--compile-by-facts=all`: Planned | §13 |
| what is final; a call settled; fully typed in a setting (a session, a closed build); a trimmed build as the facts rule with everything final | Implemented, but for compiler C-103 and traits T-122 | §1, §3, §13.3 |
| standard libraries as owners | Open ([open issue 19](../open-issues.md#2-design)) | §1 |

---

## 16. Deviations

The rows below are where the implementation falls short of this page; the heads are in [the state](../state.md).

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| F-24 | [§7.2](#72-reflection) | `infer_return_type` and the definition-time check see the code of the method's policy. | `code_typed` and `Base.infer_return_type` infer with the default interpreter (`_default_interp`, plain): a facts method's top frame is inferred plainly, its callees under their own policy. TraitWorld's membership check reads it, so a member is checked by a mix of the two ([open issue 157](../open-issues.md#2-design)). Inferring it under the method's policy makes TraitMakie's `MappedColors` fail its check at `rgba`, a function barrier whose result facts types `Any` (157's case). The plain frame is not kept as the method's code (`typeinf_type` infers it uncached; gate `n15_image_policy`). | `Compiler/src/reflection_interface.jl` (`_default_interp`), `base/reflection.jl`; TraitWorld `src/check.jl` |

**Retired IDs** (their rows are in [the ledger](../../attic/writeup/record/deviations-retired.md)): F-1 to F-23, F-25.
