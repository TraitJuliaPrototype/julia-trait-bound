# The facts mode: the reference

This page defines the facts mode: the contract between compiled code and the method table. It says what code compiled by facts may assume about other code, what it records, which code is compiled in which mode, and what the two guarantees promise. It describes the mode as designed, independent of how Julia implements it, including the parts not built yet. Each section says how far it is built. Where the implementation differs, the [Deviations](#deviations) at the end say so.

- The trait language, and the errors a user sees: [Traits: the reference](traits.md).
- The Julia interfaces this page relies on (the module option, cache owners, the dispatch entry points, the hooks): [`compiler.md`](compiler.md).
- How trait constructs are mapped onto them (entries, workers, registries, images): [`lowering.md`](lowering.md).
- Why the design takes this shape: [the design](../design.md), §2.

**Status labels**, as in every reference:
- **Implemented:** in the patched Julia 1.13.2 (`julia-1.13/`) and TraitWorld today.
- **Planned:** decided, not built.
- **Optional:** built only if a measurement or a demonstrator asks for it.
- **Open:** not decided. The link names the question.

<a id="the-facts-mode"></a>
## Summary

- Compiled code depends on the method table through **facts**: "at the concrete signature `s`, dispatch selects `r`".
- A call is inferred, with an edge, only at a **fact signature**: a signature at which only a stakeholder or a pirate can change dispatch.
- Every other call is a **run-time site**. It is typed `Any`, records nothing, and is dispatched when it runs.
- **Nothing is skipped:** a CodeInstance is invalidated exactly when a definition changes dispatch at one of its facts.
- Two guarantees follow:
  - **G1, identical or error:** code compiled by facts computes what plainly compiled code computes, in the same world, or raises.
  - **G2, stable caches:** no load of an unrelated package invalidates code compiled by facts. Only a stakeholder's change or a winning pirate can.
- Each method has a mode: facts, plain, or its caller's. Code of the two modes is cached apart, under two cache owners.
  - Trait modules are compiled by facts, whoever calls them.
  - The compiler is compiled plainly, whoever calls it.
  - Entries are boundaries: compiled in their caller's mode.
- **Strict mode** makes "a winning pirate" an error at the pirate's definition. It applies to trait code: then trait code is never invalidated, except by stakeholders' changes.
- **Two settings, and `--trim`:**
  - the product setting compiles trait modules by facts;
  - the test bed `all` compiles everything by facts;
  - a trimmed build (`--trim`) has no facts mode: it compiles everything plainly.
- The facts mode needs no traits: it protects any code it compiles. Traits make it cheap.
- It promises nothing about the speed of code that is not fully typed.

## Contents

1. [Terms](#terms)
2. [The guarantees](#the-guarantees)
3. [Fact signatures](#facts-and-fact-signatures)
4. [What is inferred across a call](#inferred-across-a-call)
5. [Run-time sites](#run-time-sites)
6. [Which code is compiled in which mode](#which-code-is-compiled-how)
7. [`return_type` and reflection](#return-type)
8. [Asserted effects](#asserted-effects)
9. [The `Dynamic` split](#dynamic-split)
10. [Pirates and strict mode](#pirates)
11. [Package images](#package-images)
12. [The settings](#settings)
13. [What the facts mode does not promise](#not-promised)
14. [Status index](#status-index)
15. [Deviations](#deviations)

---

<a id="terms"></a>
## 1. Terms

Each term is defined here once. The [glossary](../glossary.md) gives their origins.

- <a id="term-owner"></a>**Owner.** A package owns the functions, types and bindings it defines.
  - A method belongs to the module it is evaluated in: `@eval Owner f(…) = …` defines it as `Owner`'s, whichever package's code evaluates it. **Open:** whether it should belong to the package whose code defines it, to settle by a census (E-189; [open issues §1](../open-issues.md#1-decisions-waiting-for-the-user), item 65).
  - Julia (Core, Base, the standard libraries) is one owner.
  - A package extension belongs to its parent package.
  - At the prompt, `Main` is one owner, and each module defined directly under `Main` is an owner of its own ([traits §10.1](traits.md#101-who-may-implement)).
  - A package's *joint owners*, which it names, own what it owns with it ([traits §10.1](traits.md#101-who-may-implement)). Wherever a package is an owner below, its joint owners are too.
- <a id="term-stakeholder"></a>**Stakeholders of a method:** the owner of its function, and the owners of the types in its own signature, judged at every signature it applies to. A `Union`'s members count one by one. A `Vararg{T}` tail contributes `T` only where it has at least one element: `f(::Int, ::MyT...)` is a pirate at `f(::Int)` unless its definer owns `f` or `Int`.
- **Stakeholders of a concrete signature `s`:** the owner of its function, and the owners of every type in `s` at any depth: each argument type, its parameters, a `Type{T}`'s `T`, a value parameter's type, and the supertypes of each of these.
- <a id="term-pirate"></a>**Pirate:** a method defined by none of its stakeholders. This is Julia's "type piracy", made strict for unions.
- <a id="term-fact"></a>**Fact:** "at the concrete signature `s`, in the worlds `w₁` to `w₂`, dispatch selects `r`". `r` is one method, "no method", or "ambiguous".
- <a id="term-wins"></a>**A definition wins at `s`** when dispatch at `s` selects something else after it:
  - the new method is selected, also where there was "no method";
  - the call becomes ambiguous;
  - for a deletion or a replacement, another method is selected.
- **Lemma O.** A method that applies at a concrete `s` and is no pirate is defined by a stakeholder of `s`. So only a stakeholder or a pirate can change a fact.
- **Lemma D.** A definition that does not win at `s` leaves dispatch at `s` unchanged, whatever the order of definitions.
- <a id="term-fact-signature"></a>**Fact signature:** a call signature at which only a stakeholder or a pirate can change dispatch. [§3](#facts-and-fact-signatures) lists the forms.
- <a id="term-edge"></a>**Edge:** a dependency that a CodeInstance records. It is a fact, a CodeInstance it calls or inlined, or a global binding it reads. Julia invalidates a CodeInstance when one of its edges breaks, and its callers through their edges to it.
- <a id="term-run-time-site"></a>**Run-time site:** a call in code compiled by facts that records no edge: one whose argument types are not a fact signature, or one at a fact signature that Julia's method matching gives up on (more matches than `max_methods`, a call after `:latestworld`, an `invoke` it cannot resolve) ([§5](#run-time-sites)).
- <a id="term-fully-typed"></a>**Fully typed:** code in which every call is at a fact signature, and every call in the code compiled into it, transitively.
- <a id="term-mode"></a>**Mode** (the inference mode): the rules a CodeInstance is inferred under. *Facts:* the rules of this page. *Plain:* Julia's own inference. Other "modes" (strict mode, fully typed mode) are named in full.
- <a id="term-cache-owner"></a>**Cache owner:** the key under which Julia caches code compiled under one set of rules. A lookup returns only code of the owner it asks for. So code of one mode never stands in for code of the other. The design uses two cache owners for code that runs, in both settings:
  - the **default owner**, plain Julia's, for plain code;
  - the **facts owner**, for code compiled by facts.

  Their names and interfaces are in [`compiler.md`](compiler.md).
- **Code compiled by facts:** CodeInstances inferred in the facts mode.
- <a id="term-boundary-method"></a>**Boundary method:** a method that carries the boundary flag and is compiled in its caller's mode, wherever it is defined ([§6.1](#kinds-of-methods)): TraitWorld's entries and `conformance` methods.
- **Setting:** which methods are compiled by facts when plain code or the runtime reaches them ([§12](#settings)).
- **Trait code:** the code of trait modules, compiled by facts.
- **Facts, boundary, plain and neutral methods:** the four kinds of methods of [§6.1](#kinds-of-methods).
- **Kind:** a type whose instances are types: `DataType`, `UnionAll`, `Union`, `typeof(Union{})`.
- **A stakeholder's change:** a definition, deletion or redefinition by a stakeholder of the fact it changes.

---

<a id="the-guarantees"></a>
## 2. The guarantees

<a id="g1"></a>
### 2.1 G1: identical or error

**Status: Implemented**, in both settings.

> **G1.** A call in code compiled by facts computes what the same call computes in plainly compiled code, in the same world, with the same effects, or raises.

**Meaning.**
- "The same world" is the caller's world. A task in an older world sees that world's methods and implementations.
- "Or raises": the facts mode raises where plain code does not only where a value lacks a declared result type: a `Dynamic` operation's ([§9](#dynamic-split)), a `Callable`'s ([traits §5.8](traits.md)).
- A method that strict mode refuses ([§10](#pirates)) does not exist for plain code either. The comparison is with the world without it.

**Why it holds.** Every valid CodeInstance has all its facts true in the current method table:
- compilation records only true facts;
- a definition, deletion or redefinition changes dispatch only where it wins, and Julia invalidates exactly the code with a fact there: nothing is skipped;
- a package image's code is used only if its facts hold at load ([§11](#package-images));
- a run-time site records nothing and dispatches as plain Julia does;
- no asserted effect applies over a run-time site, at any depth, so no fold rests on a dispatch no edge records ([§8](#asserted-effects)).

G1 depends on no declaration. A wrong performance setting can make code slow, never wrong.

**The exception: values decided by inference.**
- `return_type`, `promote_op`, and the element types of empty `map`s, broadcasts, comprehensions and LinearAlgebra destinations are answered by inference.
- Plain Julia itself answers some of them differently in different contexts. `return_type(pass, Tuple{Type{Int}})` is `Type{Int64}` at run time and `DataType` once folded.
- The facts mode gives plain inference's answer wherever it can ([§7](#return-type)). It can still differ where inference decides: `Union{}` where every method at a run-time site throws, or a nested `return_type` in a callee.

**Conditions.**
- Code that branches on what inference knows (`known_type`, `fold_call`, [`compiler.md`](compiler.md)) computes the same result on both branches.
- Threads are untested, except the split's tables and the untyped callers' table under 4 threads (`experiments/examples/threads/`).

**Tests.** The acceptance checks G1.1–G1.33 and G2.1 (there is no G1.16) define G1 operationally: `experiments/facts/acceptance_compiler.jl`, run plain and under `all`. They cover redefinitions by owners, winning pirates, calls into code written without traits, `return_type` after redefinitions, folds over run-time sites, `Dynamic` values of later implementations, and calls in older worlds.

<a id="g2"></a>
### 2.2 G2: stable caches

**Status: Implemented**, with the exceptions below.

> **G2.** A CodeInstance compiled by facts is invalidated only by a definition that changes dispatch at one of its facts, by a redefinition of a binding it reads, or by the invalidation of a CodeInstance of the other mode that it names ([§6.3](#calls-between-the-modes), [§6.4](#the-compilers-own-code)). By Lemma O, such a definition is a stakeholder's, or a pirate's that wins there. A load that brings neither invalidates none of it, in any order.

**Why it holds.**
- Code compiled by facts holds only facts and bindings as edges to the method table ([§4](#inferred-across-a-call)).
- By Lemma O, a definition that changes a fact is a stakeholder's or a pirate's.
- By Lemma D, a pirate that does not win changes nothing, in any order.

**Scope.** G2 covers code compiled by facts. It does not cover:
- plain code in the product setting;
- plain code that code compiled by facts runs: the compiler's ([§6.4](#the-compilers-own-code)). When such plain code is invalidated, the CodeInstance compiled by facts that names it is compiled again too;
- plain inference's answers behind `return_type` ([§7](#return-type)). They change exactly when plain Julia's do.

**Exceptions**, named wherever G2 is claimed:
- **A stakeholder's change:** an edit, Revise, an upgrade, a stakeholder's package extension. This is the stated exception.
- **A stakeholder's extension activated by an unrelated package,** whose method applies at a fact without mentioning its triggers' types. It is admitted as the stakeholder's change: followed, never refused. In strict mode a warning names the method and the trait code it affects ([§10.3](#strict-intended)).
- **A binding redefined from another module** (`Core.eval(Other, …)`). No hook sees it yet; strict mode's intended design is to refuse it at its source ([§10.3](#strict-intended)).
- **The standard libraries count as Julia's own code.** A standard library's method that wins at a fact, such as SparseArrays' `vcat` for Base's types, is a stakeholder's change. **Open:** whether they are owners of their own, to settle by a census (E-189; [open issues §1.19](../open-issues.md#1-decisions-waiting-for-the-user)).
- **Direct calls from code compiled by facts into the compiler** hold edges to plain code, valid as long as plain Julia keeps that code valid ([§6.4](#the-compilers-own-code)).
- **A method on a closure's type defined outside the closure's module.** The fact form "a closure's call at kinds" ([§3](#facts-and-fact-signatures)) rests on the assumption that no other module does this.

**What invalidates nothing.**
- A new implementation of a trait: lowering makes it a definition that wins at no existing fact ([`lowering.md`](lowering.md)).
- A new `Dynamic` candidate: candidates are read without an edge ([§9](#dynamic-split)).

**Tests.** G2.1 (a module extending a function called on type values) and G1.17 (a later implementation at a split site) check it in a session (`experiments/facts/acceptance_compiler.jl`). `experiments/facts/g2all.jl` counts the facts owner's valid CodeInstances across ten loads interleaved with the demonstrators' work, in both settings and in both orders (E-29); with `G2_DIAG=1` it names the method behind each lost one. `experiments/factscompiler/control/lost.jl` is a control for the default owner under `all`: it counts the valid CodeInstances of owner `nothing` of the listed packages before and after unrelated loads, so it counts no trait-module code, which is owner `:facts`.

<a id="two-tiers"></a>
### 2.3 Two tiers

**Status: Implemented** as a prototype; strict mode's full design is **Planned** ([§10.3](#strict-intended)).

| Tier | Trait code is invalidated only by | Kind of property |
|---|---|---|
| **Strict** (strict mode on) | a stakeholder's change | holds in every environment that loads without a `PirateError`, with the exceptions of §2.2 |
| **Default** | a stakeholder's change, or a pirate that wins at one of its facts | measured per environment |

- The compiled code is the same in both tiers. Strict mode acts only when a method is defined or an image's methods are activated.
- By default a winning pirate is followed, as plain Julia follows it. The code with the broken fact is compiled again, once.

---

<a id="facts-and-fact-signatures"></a>
## 3. Fact signatures

**Status: Implemented.**

**The criterion.** A signature is a fact signature when only a stakeholder or a pirate can change dispatch at it. Every form below meets it, the closure form under its stated assumption. A form not listed is a run-time site, until it is shown to meet the criterion and added.

| Form | Example | Why only a stakeholder or a pirate can change it |
|---|---|---|
| **A dispatch tuple:** concrete types, not kinds; `Type{T}` with `T` known | `f(::Int, ::Float64)` | Lemma O. |
| **Its union splits,** where Julia's union splitting splits | `g(::Union{Int, Nothing})` | Each split is a dispatch tuple. The fact stands for them, with an edge per split. |
| **Unions of concrete elements in tuple arguments,** split by the same cost over the tuple's elements | `h(::Tuple{Union{Int, Missing}, Float64})` | A tuple type of concrete or union elements holds exactly the values of its splits. Dispatch at it is dispatch at one of them. |
| **A closure's call at kinds** (`DataType`, `UnionAll`, `Union`) | `(T -> sizeof(T))(Int)` | Only the closure's own module adds methods to a closure's type. This is an assumption, not Lemma O: the owner of a type `X` who defines `(::typeof(clo))(::Type{X})` is a stakeholder of its own method, yet changes dispatch at `Tuple{typeof(clo), DataType}`. Julia invalidates the edge, so G1 holds; G2 for this form rests on the assumption ([§2.2](#g2)). A closure's type is recognized by its generated name (`#…`), which also admits lowering's generated functions (keyword bodies), under the same assumption. |
| **A concrete `Vararg` tail:** concrete members ending in `Vararg{E}`, `E` a concrete member. A concrete member is a dispatch element that is not a kind (a concrete type, or `Type{T}` with `T` known), or a tuple type of such members | `vcat(::Vararg{Int})` | Every value's type is a dispatch tuple with the same owners. The fact stands for that family, one dispatch tuple per arity, with one edge, as a union's splits do. Which compiled specialization serves a call is not part of the fact: past a function's `max_args` Julia compiles one at a widened signature, and any new method of the function can move that limit without changing dispatch. |
| **`invoke` at a declared signature,** and `hasmethod` at one | `invoke(f, Tuple{AbstractArray}, x)` | Dispatch of the declared signature as a whole: the most specific method whose signature contains it. A definition changes that only if its own signature contains the declared one, so its types are the declared types or their supertypes: its definer is a stakeholder of the declared signature, or a pirate. The edge is an invoke edge, which Julia invalidates only when the declared signature's resolution changes. |

**Which unions split** is Julia's cost model, exactly: the union lengths multiplied, the largest counted as 2, a split where the cost is at most the interpreter's `max_union_splitting` (4 by default). One union argument of any length splits; two union arguments of three members each do not, and the call is a run-time site. A tuple argument's elements are split by the same cost. The facts mode adds no limit of its own.

**Not fact signatures** (run-time sites):
- an abstract argument type: `show(::IO, ::Any)`, `sum(::AbstractVector)`;
- a kind passed to a function that is not a closure: `make(::DataType)`. Any owner of a type `X` may define `make(::Type{X})`, which applies at `DataType` without being a stakeholder of it;
- a union with more than four splits;
- a `Vararg` tail of an abstract or kind element: `Vararg{Any}`.

---

<a id="inferred-across-a-call"></a>
## 4. What is inferred across a call

**Status: Implemented.**

### 4.1 At a fact signature

- The callee is inferred at the signature, or at each split. Its result type, exception type, effects and constant results flow into the caller, as in plain Julia.
- The caller records the fact as an edge, one per top-level split. A union in a tuple argument is one edge at the tuple signature: Julia's intersection check makes it exact. "No method" and "ambiguous" are facts too.
- Inlining and constant propagation work as in plain Julia.
- Compile-time evaluation (concrete and semi-concrete) happens only for a call at a fact signature, on the callee's effects as inferred. Asserted effects are limited by [§8](#asserted-effects).
- A global binding the code reads is an edge, as in plain Julia. A redefinition by the binding's own module is a stakeholder's change.
- The callee's code is compiled in the mode [§6](#which-code-is-compiled-how) gives it.

### 4.2 At a run-time site

- Nothing is inferred about the callee. The call's result is `Any`, its exception type `Any`, its effects unknown.
- No edge is recorded.
- The frame is marked as holding a run-time site, and so is every frame that calls it, at any depth ([§8](#asserted-effects)).
- A call at a fact signature that Julia's method matching gives up on is a run-time site too (§1).
- Julia's heuristics for calls at abstract types do not apply:
  - no speculation over the methods that match today (`max_methods`);
  - no result type taken from the one method that matches today;
  - no compile-time evaluation over the call.
- `Any` spreads into the code after the call, until a declared result type or an assertion narrows it.
- An `invoke` at a declared signature is not a run-time site: it is inferred as in plain Julia, with an invoke edge ([§3](#facts-and-fact-signatures)).

<a id="edges-and-invalidation"></a>
### 4.3 Edges and invalidation

- **Exact.** A CodeInstance is invalidated if and only if a definition wins at one of its facts, a binding it reads is redefined, or a CodeInstance it has an edge to is invalidated. No invalidation is skipped, and none is added beyond what Julia's own invalidation adds at a concrete signature.
- **Per owner.** An edge to a bare MethodInstance (a cycle partner, a result that was not cached) stands for the caller's own owner's result. Only a CodeInstance of that owner breaks it. Replacing the method reaches every owner.
- **Across owners.** An edge from code of one owner to a CodeInstance of the other names that CodeInstance ([§6.3](#calls-between-the-modes)).

---

<a id="run-time-sites"></a>
## 5. Run-time sites

**Status: Implemented** ([compiler §2.5, dispatch from facts code](compiler.md#25-dispatch-from-facts-code)).

**Meaning.** A run-time site is dispatched when it runs, as plain Julia's dynamic dispatch is.
- The lookup is plain Julia's, in the caller's world.
- In code compiled by facts, the method found runs its code compiled by facts, under the facts owner. That code is compiled on a miss.
- The exception: a plain method ([§6.1](#kinds-of-methods)) runs its plain code.
- This holds for the calls the code generator emits: generic calls, `invoke`, `_apply_iterate` with a known tuple, `invokelatest`.

**Dispatch through the runtime's `jl_apply`** (splats of unknown length, `jl_call`, `@cfunction` pointers, finalizers, task entry) runs the callee's default owner's code ([§6.2](#the-mode-rule)):
- a trait module's method is a facts method, whose default owner is the facts owner, so trait code reached this way is code compiled by facts;
- a neutral method runs its plain code in the product setting. That code is not trait code, so trait code is never invalidated through this path;
- this rests on the mode rule alone, not on the runtime's internals.

**Caches at run-time sites.** A cache that skips a dispatch at run time (a per-call-site cache, a `cfunction` pointer's thunk) remembers what dispatch decided, for the worlds where that holds. It is checked against the caller's world. It never decides which method runs.

**Cost.** A run-time site costs a dynamic dispatch, as in plain Julia. Its result is `Any` ([§4.2](#inferred-across-a-call)).

---

<a id="which-code-is-compiled-how"></a>
## 6. Which code is compiled in which mode

<a id="kinds-of-methods"></a>
### 6.1 Kinds of methods

**Status: Implemented.**

Every method is of one of four kinds. The kind follows from the method and its module alone.

| Kind | Which methods | Declared by |
|---|---|---|
| **Facts method** | methods of a trait module and of its submodules; *always-facts* methods anywhere | the module option `facts=true`, which `@trait_module` sets and submodules inherit when they are created; `Expr(:meta, :facts_always)` in a method (TraitWorld's `@machinery`) |
| **Boundary method** | a method carrying the boundary flag, compiled in its caller's mode, wherever it is defined: TraitWorld's entries, `conformance` methods, and the entry methods compiled ahead | `Expr(:meta, :facts_boundary)` in the method. Lowering carries it into every method a definition lowers to (keyword sorter, positional forwarders) |
| **Plain method** | the compiler's own code: the `Compiler` module and its submodules | the module flag "never by facts" |
| **Neutral method** | everything else: Base, packages, user code at the prompt | — |

The spellings are [`compiler.md`](compiler.md)'s. User code writes `@trait_module`; TraitWorld writes the per-method marks.

<a id="the-mode-rule"></a>
### 6.2 The mode rule

**Status: Implemented**, in one function (`jl_code_owner`, [compiler §2.3](compiler.md#23-the-owners-and-the-mode-and-owner-of-a-methodinstances-code)).

The mode and cache owner of a MethodInstance's code depend on three things: the method's kind, the cache owner that reaches it, and the setting.

- **The cache owner that reaches it** is the facts owner when code of the facts owner reaches it: an inference edge, or a run-time site of that code that the code generator emits. Otherwise it is the default owner: a call from plain code, a top-level call, a dispatch through the runtime's `jl_apply` ([§5](#run-time-sites)), a compile queue's item of the default owner, reflection without an interpreter.
- **The mode of a neutral method reached from the default owner** is plain in the product setting and facts under `all`.

| Kind | Reached from the default owner | Reached from the facts owner |
|---|---|---|
| facts method | facts, facts owner | facts, facts owner |
| plain method | plain, default owner | plain, default owner |
| boundary or neutral method | from plain code: plain, default owner; from the runtime or the top level: product setting plain, default owner, `all` facts, facts owner | facts, facts owner |

- **The property:** plain results and results compiled by facts never share a cache. Plain code is the default owner's, and code compiled by facts the facts owner's, in both settings.
- **Under `--trim`** there is no facts mode: every method is compiled plainly, under the default owner ([§12.3](#trimmed-binaries)).
- The rule applies wherever code is compiled: a single request from the runtime, the compile queues (the JIT's, and the one that builds images), calls between the modes, and dispatch at run time.

<a id="calls-between-the-modes"></a>
### 6.3 Calls between the modes

**Status: Implemented** (constant propagation: acceptance G1.27–G1.29; concrete and semi-concrete evaluation: G1.30).

- **By inference.** The callee is inferred in its own mode, in an inference of its own. The caller names that CodeInstance, with an edge to it, and uses its result type and effects.
- **Constant propagation crosses from plain code into code compiled by facts.** A plain call with constant arguments infers the facts callee again for those constants, by the facts rules, in an inference of its own (a call stack of its own: a cycle back to its frame gives up constant propagation, as for any constant frame). The result stays the caller's, as constant propagation's always does, and the caller's edges are that inference's: facts on the path the constants take, which only a stakeholder or a pirate can change. No CodeInstance of the facts owner is cached by it; a callee the constant inference reaches at a new signature is compiled by facts and cached as facts code there, as for any facts caller. Otherwise the callee's result is its CodeInstance's.
- **Concrete and semi-concrete evaluation cross from plain code into code compiled by facts,** on the callee's effects as facts inferred them ([§4.1](#41-at-a-fact-signature)). The caller names the callee's facts CodeInstance, with an edge to it, as for inlining. Its result rests on that CodeInstance, which only a change to a fact the callee rests on invalidates. A callee whose facts code has a run-time site is not evaluated at compile time ([§8](#asserted-effects)).
- **The other direction,** code compiled by facts calling the compiler's own plain code, propagates no constants.
- **Inlining crosses.** The caller may inline the callee's code from the callee's owner's cache. The inlined code is not inferred again. The caller keeps an edge to that CodeInstance only.
- **At run time.** Dispatch from plain code to a facts method runs its facts code. Dispatch from code compiled by facts to a plain method runs its plain code.
- **A boundary method does not cross.** It is compiled in its caller's mode, so the crossing happens at the call it makes.

```julia
colmean(t::ColTable, i::Int) = …     # in a trait module: an entry (a boundary) and a worker (a facts method)
colmean(m, 1)                        # in plain code: the entry is compiled plainly and inlined;
                                     # the worker it calls is compiled by facts, and inlined from the facts owner's cache
```

<a id="the-compilers-own-code"></a>
### 6.4 The compiler's own code

**Status: Implemented.**

- The compiler is compiled plainly, whoever calls it, in both settings and in every compile queue.
- Why: otherwise a caller compiled by facts would compile the abstract interpreter by facts, as type-unstable code with run-time sites.
- The compiler runs in its own world, as plain Julia's does. Reflection runs it there also for an explicit interpreter. So later definitions cannot invalidate the compiler's code that reflection runs.
- **The limit.** Code compiled by facts that calls compiler functions directly, not through reflection, holds edges to plain compiler code. Those edges are valid as long as plain Julia keeps them valid. TraitWorld's checks make such calls. Running them in the compiler's world would break packages that extend the compiler for their own interpreters. The loss is cacheability, not correctness.

---

<a id="return-type"></a>
## 7. `return_type` and reflection

### 7.1 `return_type`

**Status: Implemented**, except the walk's limit ([F-13](#deviations)). **Optional:** cached answers revalidated after loads, instead of inferred again ([PE-5](../record/performance-explorations.md)). That changes speed, not answers.

**Meaning.** `return_type` (and what uses it: `collect`, `map` over an empty collection, broadcasting, `promote_op`) asks what *plain* inference gives. Under the facts mode the answer is plain inference's, in the same world.

**Rules**, in order:
1. **The facts mode's own answer is folded** when it cannot be wider than plain inference's, except by the `Union{}` case of [§2.1](#g1): a constant, a concrete type that is not a kind, or `Union{}`.
2. **Otherwise plain inference's answer is folded** when:
   - the signature has at most four concrete splits;
   - at each split exactly one method matches, and it covers the split fully;
   - plain inference's result at each split rests on facts only (or on an invoke edge at the method's own signature, [§3](#facts-and-fact-signatures)).

   The fold records an edge per split, to plain inference's result. That result lives under a cache owner of its own, and dispatch never runs code from it ([compiler §1.4](compiler.md#14-return_type)).
3. **Otherwise the answer is computed at run time,** by plain inference, in both settings. Plain inference infers every method plainly, facts methods included. So the fold and the run time give one answer: plain inference's, as stock Julia's would be. The answers have a cache owner of their own.

**Consequence.** A load changes a folded answer exactly when it changes plain Julia's. An answer computed at run time is computed again when plain Julia's would change.


<a id="reflection"></a>
### 7.2 Reflection

**Status: Implemented.**

- Reflection shows the code that runs. For a facts method it is facts inference; under `all`, for every method but the compiler's.
- `code_typed`, `infer_return_type`, `verify_main` and TraitWorld's rule checks (the first-call check, and definition checking at archetypes) all see that code.
- TraitWorld's other checks infer plainly, by design: the keep analysis and the result types of implementations, at archetypes in a cache of their own ([`lowering.md`](lowering.md#14-checks-and-where-their-results-live)).
- Reflection with an explicit `NativeInterpreter` runs in the compiler's world, as without one.

---

<a id="asserted-effects"></a>
## 8. Asserted effects

**Status: Implemented** (acceptance G1.10, G1.19, G1.32, G1.33).

**Rule.** In code compiled by facts, no asserted effect applies over a run-time site, at any depth:
- the method's assertion (`Base.@assume_effects` on the definition) does not apply when the frame, or any frame it calls, holds a run-time site;
- a statement's assertion (`Base.@assume_effects` on a block or a call) does not apply when the statement's call, or any frame it calls, holds one.

**Why.** An assertion lets a caller fold the frame at compile time. The fold would rest on a dispatch that no edge records, and a later definition could not invalidate it.

- The rule applies to every method, Base's included.
- A frame without run-time sites, in itself and in its callees, keeps its assertions, as in plain Julia.
- Tests: G1.10 (a fold over a run-time site follows a redefinition), G1.19 (a Base method asserted `:foldable` over a run-time site), G1.32 (an assertion one frame above a run-time site), G1.33 (an assertion over a call with too many matching methods).

---

<a id="dynamic-split"></a>
## 9. The `Dynamic` split

**Status: Implemented.** Planned: acceptance checks for code at a `Dynamic` position, with `Dynamic` positions.

An operation on a `Dynamic{X}` value, or on a trait object at a `Dynamic` position ([traits §6](traits.md#6-values-in-trait-code-compiled-and-dynamic), [§7](traits.md#7-kept-values-dynamicx-compiledx-keptx)), is a call on a value of an open set of types. A declared field read there is one too. Lowering writes it as `split_call(K, RT, f, x, args...)`: `K` names the trait, `RT` is the operation's declared result type ([`lowering.md`](lowering.md), [`compiler.md`](compiler.md)).

**Meaning.** `split_call(K, RT, f, x, args...)` computes `f(x, args...)::RT`.

**Rules.**
- **Candidates.** The types registered for `K` are its candidates: for a `Dynamic{X}`, the types of `X`'s implementations, registered in declaration order ([`lowering.md`](lowering.md#13-dynamicx)). The first four registered are used: the first four declared. The list is read without an edge.
- **When inference does not know `x`'s type:**
  - the call is inferred at the union of the candidates that `x`'s type admits;
  - each split is a fact, with its edge;
  - the call site branches on `isa` over the candidates, with direct calls that may inline;
  - the last branch, the **fallback**, is a run-time site for any other type. It calls the call's target for the value's type through a table keyed by the type, in the caller's world, and records no edge ([compiler §4.3](compiler.md#43-what-follows-the-split-the-table-of-a-calls-targets)).
- **When inference knows `x`'s type,** the call is an ordinary call at that type.
- **The result.** Inference types the call `Any` where it splits: the fallback's result is unknown. The lowering asserts the declared type `RT` after the call, so the code after it is typed `RT`. The optimizer's split asserts each case not known to be an `RT`, and the fallback, to `RT`. A result of another type raises a `TypeError`.
- **A later candidate** reaches the fallback. It invalidates nothing. Code compiled after its registration splits over it.
- **Code at a `Dynamic` position** is compiled once for the position: it records no edge to the set of implementations, and each branch of its splits is a fact. So a new implementation, loaded after it was compiled, discards none of it.

So the split takes the place of the speculation the facts mode removes ([§4.2](#inferred-across-a-call)), from a declaration rather than from the methods that exist today.

---

<a id="pirates"></a>
## 10. Pirates and strict mode

Who may write a method, and the errors a user sees, are in [traits §10](traits.md). This section says how pirates affect validity.

### 10.1 What a winning pirate does

**Status: Implemented.**

- **By default, a winning pirate is followed,** as plain Julia follows it. The code that holds the broken fact is invalidated and compiled again, once. It then computes plain Julia's result, with the pirate.
- **A pirate that wins nowhere changes nothing,** in any order (Lemma D).
- **A pirate defined before the code is compiled** is in the method table. The code's facts select it from the start.
- **A pirate already loaded when a package image loads** breaks the image's facts at that signature. That code is discarded at validation and compiled again ([§11](#package-images)).

<a id="strict-mode"></a>
### 10.2 Strict mode

**Status: Implemented** as a prototype.

```julia
TraitWorld.strict!(true)        # or start Julia with JULIA_TW_STRICT=1
```

**Rule.** A definition is refused if all three hold:
1. **It is a pirate.** An extension counts as its parent package. Methods of Julia's own code (Core, Base, the standard libraries) are not checked: Julia is one owner ([open issues §1.19](../open-issues.md#1-decisions-waiting-for-the-user)).
2. **It would win at a fact of code of the facts owner,** or at a fact of plain code that such code rests on: `return_type`'s plain answers, the compiler's own code, and Julia's own plain code, which the compiler's code calls. At a concrete signature, or at any split of a fact signature.
3. **Its package is no stakeholder of that signature** (joint owners are owners, §1), and no declared delegate of one. A *delegate* is an implementation package that counts as the owner of the core package it implements (`TraitWorld.delegate!(Core => Impl)`). Delegates are data, and transitional.

**When.** Before the method becomes visible:
- at a definition: at the prompt, by `include`, by `eval`;
- for a package image's methods, before they are activated. A refused method stays inactive, and the load reports the `PirateError`.

**How it finds the facts** (`TraitWorld/src/strict.jl`, `_winning_fact`): the calls of existing code at which the method would win, from the backedges of the specializations it could take over and of the method table; from each, the callers' backedges, transitively, as Julia's invalidation follows them, through the three classes of plain code in rule 2 only, to code of the facts owner. After the definition, Julia's invalidation log is checked again: a hit the walk missed deletes the method and raises `PirateError` (counted, `_STRICT_MISSES`).

**What it protects: code of the facts owner,** in both settings. In the product setting that is trait code (the code of trait modules, compiled by facts), TraitWorld's machinery, the split's thunks, and the Base methods compiled by facts for them: most of it is code trait code depends on. Under `all` it is every package's compiled code but the compiler's and the plain code of Julia that the compiler calls.

**The property it secures: trait code is never invalidated,** except by a stakeholder's change, with the exceptions of [§2.2](#g2). The property says nothing against protecting more.

**Not protected:** plain code of a package, of TraitWorld, or of a trait module's plain entries. A pirate that wins only there is followed, and that code is compiled again, as in plain Julia. Results of constant propagation from plain callers into facts code live in the plain caller, so a pirate that wins only on that path is followed too.

**Effects.**
- The refused method does not exist, for plain code either. G1 holds, against the world without it.
- Nothing changes at run time. Code compiled with strict mode on or off is the same code.
- If pirates never win, strict mode never errors.

**Not refused:** a pirate that wins nowhere in code of the facts owner or the plain code it rests on; any stakeholder's method; an implementation of a trait. Folds and the definition checks' verdicts are values, not edges: a pirate can change them without invalidating anything (folds are evaluated again at load, [compiler §4.4](compiler.md#44-compilerfold_call)).

<a id="strict-intended"></a>
### 10.3 Strict mode's intended design

**Status: Implemented** for a pirate loaded before an image (reported, row 1), the narrowed walk for plain code (row 2) and the warning for a package extension's winning method; **Planned** for rows 4 and 5 ([F-6](#deviations)). Built with the cache keyed on facts and their origins ([W-66](../record/todo.md); the user, 2026-10-27: "Take up strict mode with W-66").

In strict mode, trait code, in a session and in package images, is invalidated only by edits to code it depends on. Every other invalidating event is an error at its source, or, for a stakeholder's package extension, a warning:

| Source | The error |
|---|---|
| a pirate loaded before a package image whose facts it breaks | reported at the image's load, naming the pirate, the code and the fact: it came first, and the image's methods are active before its code is validated, so it cannot be refused. The image's code is compiled again with the pirate |
| a pirate that wins inside plain code that code of the facts owner rests on (a folded `return_type`, the compiler, Julia's plain code the compiler calls) | at the definition: the check follows those callers transitively |
| a package extension's winning method at a fact whose signature contains none of its triggers' types | no error: followed, as its parent's change (a stakeholder's), with a warning when the extension's methods become visible, naming the method and the trait code it affects |
| a binding redefined from another module (`Core.eval(Other, …)`) that trait code reads | at its source, the redefinition (§2.2) |
| a deletion of a method that trait code depends on, by anyone (a deletion carries no caller to name), except TraitWorld's own deletion of a refused declaration's methods and of a refused pirate | at the deletion |

- Edits stay the one exception, with a stakeholder's package extension, which is followed with a warning. An edit is meant to change what the code computes; an extension is its parent's code.
- **The symmetric check** is a lint, not a session default: `verify_main` reports a fact of trait code that selects a pirate defined before the code was compiled. **Planned.**

---

<a id="package-images"></a>
## 11. Package images

**Status: Implemented**, with strict mode's report of a pirate loaded before an image ([§10.3](#strict-intended)).

**What an image may hold.**
- Code of both owners, compiled while the package's image was built.
- Code for other packages' methods that its workload compiled: plain code where a call of the package that Julia sees reaches it; code of the facts owner also where only a dynamic call reached it (with keep-compiled, [compiler §2.9](compiler.md#29-what-package-images-keep)), copies of Base methods compiled by facts, for example. With machine code.
- Code of other owners (`return_type`'s answers) is kept as inferred code, without machine code: it never runs.
- What trait code a declared implementation brings ahead of time is [traits §13](traits.md)'s; how, [`lowering.md`](lowering.md)'s.

**When it stays valid.**
- At load, a CodeInstance is used if all its facts hold in the loading session, and every value it fixed by `fold_call` is the one its library gives in this session ([compiler §4.4](compiler.md#44-compilerfold_call)). Otherwise it is discarded, and compiled again when needed.
- A fact breaks only by a stakeholder's change or a winning pirate loaded earlier. Which code is kept therefore depends on the method table, not on the order of unrelated loads.
- A trimmed build uses no code compiled by facts.

**Images and the setting.** An image's CodeInstances mean the same in both settings: the mode is the owner ([§6.2](#the-mode-rule)).
- An image built under one setting is correct under the other. The other setting finds no code of its own default owner for a neutral method, and compiles it.
- So the setting is not part of an image's key. The test bed keeps a depot of its own, for speed: the images of one setting hold little of the other's code.

---

<a id="settings"></a>
## 12. The settings

<a id="product-setting"></a>
### 12.1 The product setting

**Status: Implemented.** The default.

- Facts methods are compiled by facts: trait modules and always-facts methods, and what they reach ([§6.2](#the-mode-rule)).
- Plain code keeps all of Julia's behaviour: its inference, its speed, its invalidation.
- G1 and G2 hold for code compiled by facts.

<a id="the-test-bed"></a>
### 12.2 The test bed `all`

**Status: Implemented** as an environment variable; **Planned:** the command-line flag.

- Everything is compiled by facts, except the compiler's own code.
- **Purpose:** to test the facts rule on code as it is written today. It is not a user setting.
- **How:**
  - `JULIA_COMPILE_BY_FACTS=1`, read once per process; or
  - a system image built with it, the facts system image. It holds Base and the standard libraries compiled by facts only. `JULIA_COMPILE_BY_FACTS=0` turns the mode off there, and the process then compiles plain Base at its start (tens of seconds): it is the test bed's image only.
  - Use a depot of its own, for speed ([§11](#package-images)).
- **Planned spelling:** `--compile-by-facts=no|all|traits`.
- G1 and G2 hold under `all` for all code. Strict mode under `all` protects code of the facts owner, which there is all code but the compiler's and Julia's plain code it calls (§10.2); TraitWorld's strict tests pass under `all` (E-198).

<a id="trimmed-binaries"></a><a id="closed-builds"></a>
### 12.3 Trimmed binaries

**Status: Implemented** for the code the build infers; whether code of the facts owner that package images keep reaches a trimmed binary is untested ([F-7](#deviations)).

- **A `--trim` build has no facts mode and no facts methods.** It compiles every method plainly.
- **Why:** a binary is a closed world. Nothing loads later, so there is no cache to protect.
- G1 holds by definition. Values decided by inference ([§2.1](#g1)) can differ between a session and the binary.
- **`verify_main`** lists the targets a program can reach through trait code ([traits §13](traits.md)). Plain code reached from trait code keeps plain Julia's AOT properties. Its open dynamic sites are reported as holes.
- `verify_main` scans each MethodInstance in the mode it runs in: a facts method, and code reached from code compiled by facts, by facts ([F-9](#deviations)).
- **Under `all`** it reports the run-time sites that the facts mode makes in Base, as the code runs in the session: `convert(Type{AbstractString}, ::Any)` inside `DomainError`, for one. It is conservative: a trimmed build compiles plainly and can only have fewer holes.

---

<a id="not-promised"></a>
## 13. What the facts mode does not promise

- **The speed of code that is not fully typed.**
  - A run-time site costs a dynamic dispatch, and its result is `Any`.
  - Julia's heuristics for type-unstable code are gone there ([§4.2](#inferred-across-a-call)).
  - The design tolerates such a slowdown when rewriting the code with traits recovers it. Fully typed code pays nothing: for it, facts inference is plain inference.
- **Protection for plain code** in the product setting.
- **"Never invalidated"** outside the strict tier, and within it only with the exceptions of [§2.2](#g2).
- **Identical values decided by inference** ([§2.1](#g1)).
- **The standard libraries as owners of their own.** They count as Julia's code: their methods on Base's types are stakeholders' changes, followed and never refused. **Open** ([open issues §1.19](../open-issues.md#1-decisions-waiting-for-the-user)).
- **Threads:** untested.

---

<a id="status-index"></a>
## 14. Status index

| Item | Status | Where |
|---|---|---|
| G1, identical or error | Implemented | [§2.1](#g1) |
| G2, stable caches; exceptions named | Implemented; cross-module bindings a named exception until strict mode's intended design | [§2.2](#g2); [§10.3](#strict-intended) |
| fact signatures (the six forms, split at Julia's `max_union_splitting`) | Implemented | [§3](#facts-and-fact-signatures) |
| run-time sites, typed `Any`, no edge | Implemented | [§4.2](#inferred-across-a-call) |
| run-time sites run facts code: calls the code generator emits | Implemented | [§5](#run-time-sites) |
| dispatch through `jl_apply` runs the default owner's code | Implemented | [§5](#run-time-sites) |
| caches at run-time sites checked against the caller's world | Implemented | [§5](#run-time-sites) |
| four kinds of methods | Implemented | [§6.1](#kinds-of-methods) |
| calls and inlining between the modes | Implemented | [§6.3](#calls-between-the-modes) |
| the compiler plain whoever calls it | Implemented | [§6.4](#the-compilers-own-code) |
| direct calls into the compiler from code compiled by facts: edges to plain code | Implemented | [§6.4](#the-compilers-own-code) |
| `return_type`: plain inference's answer, at compile time and at run time, in both settings | Implemented | [§7.1](#return-type) |
| `return_type`: revalidation after loads | Optional | [§7.1](#return-type); [PE-5](../record/performance-explorations.md) |
| reflection shows the code that runs | Implemented | [§7.2](#reflection) |
| no asserted effect over a run-time site | Implemented | [§8](#asserted-effects) |
| the `Dynamic` split | Implemented | [§9](#dynamic-split) |
| beyond four implementations, a table keyed by the value's type | Implemented | [§9](#dynamic-split); [compiler §4.3](compiler.md#43-what-follows-the-split-the-table-of-a-calls-targets) |
| winning pirates followed by default | Implemented | [§10.1](#pirates) |
| strict mode, prototype, on code of the facts owner | Implemented | [§10.2](#strict-mode) |
| strict mode's intended design: a pirate before an image reported, the warning for package extensions | Implemented | [§10.3](#strict-intended) |
| strict mode's errors for deletions and bindings redefined from outside; the symmetric lint | Planned | [§10.3](#strict-intended); F-6 |
| package images of both owners | Implemented | [§11](#package-images) |
| product setting; `all` by environment variable | Implemented | [§12](#settings) |
| `--compile-by-facts=no\|all\|traits` | Planned | [§12.2](#the-test-bed) |
| `--trim` compiles plainly | Implemented | [§12.3](#trimmed-binaries) |
| `verify_main` under `all`: Base's run-time sites reported | Implemented | [§12.3](#trimmed-binaries) |
| standard libraries as owners | Open (E-189) | [open issues §1.19](../open-issues.md#1-decisions-waiting-for-the-user) |

---

<a id="deviations"></a>
## 15. Deviations

Paths are in the workspace: `julia-1.13/` is the patched Julia, `TraitWorld/` the library.

| ID | Section | The reference says | The implementation does | Where |
|---|---|---|---|---|
| F-1 | — | *Retired*: see [§6.2](#the-mode-rule)]. | — | — |
| F-2 | — | *Retired*: see [§6.2](#the-mode-rule). | — | — |
| F-3 | — | *Retired*: see [§5](#run-time-sites). | — | — |
| F-4 | — | *Retired*: see [§10.2](#strict-mode), the note. | — | — |
| F-5 | — | *Retired*: see [§10.2](#strict-mode). | — | — |
| F-6 | [§10.3](#strict-intended) | In strict mode, a deletion of a method that trait code depends on, and a binding redefined from another module that trait code reads, are errors at their source. | Both are accepted: `Base.delete_method` reaches no hook, and a binding's redefinition is followed (§2.2's exception). | `TraitWorld/src/strict.jl` (no deletion or binding hook); `julia-1.13/src/gf.c` (`jl_method_table_disable`) |
| F-7 | [§12.3](#trimmed-binaries) | A trimmed build uses no code compiled by facts, also none that package images keep. | Untested: `--trim` is not part of an image's key, and whether code of the facts owner that images keep reaches a trimmed binary is not checked. | `julia-1.13/src/module.c:741` (`jl_method_is_facts` under trim) |
| F-8 | — | *Retired*: see [§12.3](#trimmed-binaries). | — | — |
| F-9 | [§12.3](#trimmed-binaries) | `verify_main` scans each MethodInstance in every mode it is reached in. | It scans an instance reached in both modes only in the mode it meets first. | `TraitWorld/src/verify.jl:353`, `:839` |
| F-10 | — | *Retired*: see [§7.1](#return-type). | — | — |
| F-11 | — | *Retired*: see [§2.2](#g2) and the [evidence](../design/evidence.md#1-the-guarantee). | — | — |
| F-12 | — | *Retired*: see [§8](#asserted-effects). | — | — |
| F-13 | [§7.1](#return-type) | Plain inference's answer is folded when it rests on facts. | The walk that decides it gives up after 2000 CodeInstances, and the query is answered at run time. As [compiler C-9](compiler.md#deviations). | `julia-1.13/Compiler/src/facts.jl:305` |
| F-14 | — | *Retired*: see [§10.3](#strict-intended). | — | — |
| F-15 | — | *Retired*: see [§3](#3-fact-signatures). | — | — |
| F-16 | — | *Retired*: see [§8](#8-asserted-effects) and [§6.2](#the-mode-rule). | — | — |
| F-17 | — | *Retired*: see [§6.3](#calls-between-the-modes). | — | — |
| F-18 | — | *Retired*: see [§6.3](#calls-between-the-modes). | — | — |
| F-19 | — | *Retired*: see [§1](#1-terms). | — | — |
| F-20 | — | *Retired*: see [§7.1](#return-type)]. | — | — |
| F-21 | — | *Retired*: see [§2.1](#g1)]. | — | — |
