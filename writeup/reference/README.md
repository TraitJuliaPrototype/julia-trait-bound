# The references: Julia with traits in its type system

**The references** (adopted: the user, 2026-11-06: "Adopt all recommendations. Go"). They describe the design as a whole, from the ground up. "The choices in these references" below lists every choice beyond the decision log's, with who made it. A section whose choice still waits for the user says **Proposed** in its status line.

The four references define the intended shape of the design. Each one also records, separately, where the implementation deviates from it.

| Reference | Defines | Wins on |
|---|---|---|
| [`traits.md`](traits.md) | The trait language: traits as abstract types, memberships, methods, the attribute, the checks and errors, as user code sees them | What a program means |
| [`facts.md`](facts.md) | The facts mode: what compiled code may assume about other code, the guarantees, which code is compiled how | What compiled code may assume |
| [`compiler.md`](compiler.md) | What Julia's compiler and runtime provide: sets and memberships, dispatch, keys, the attribute's compilation, the facts inference, the dependency record | Julia's interfaces |
| [`lowering.md`](lowering.md) | What the trait library's macros expand to on those interfaces | Consistent with all three; it decides nothing they decide |

## Conventions for every reference

**Intended shape first.** Each section states the design as intended, whether or not it is built:
1. the syntax or the interface;
2. its meaning;
3. its rules and checks, and when they apply;
4. a short example where it helps;
5. a one-line status:
   - **Implemented:** on branch `unified` of the julia repository (the worktree `julia-unified/`, on v1.13.2), or in the trait library built on it;
   - **Planned:** decided, not built. A guarantee the design commits to is Planned, however late the stage that delivers it;
   - **Proposed:** proposed, waiting for the user's decision (listed below);
   - **Optional:** a mechanism built when a measurement or a later decision asks for it. User code may not rely on what it would give until it is Planned;
   - **Open:** not decided, linking [`../open-issues.md`](../open-issues.md).

**Guarantees and their mechanisms.** A guarantee is a promise to user code: what is accepted or refused, which method runs, what compiled code may assume, what a membership or a load does to compiled code. It is stated in `traits.md` or `facts.md`. The mechanism that delivers it is in `compiler.md`. A guarantee the design commits to is Planned with the stage that delivers it, however late. Optional is kept for mechanisms whose gain user code cannot build on, or whose guarantee is not yet committed.

**Deviations separately.** Each reference ends with a table, one row per place where the implementation differs from it: `ID | Section | The reference says | The implementation does | Where`. IDs are stable (`T-n`, `F-n`, `C-n`, `L-n`) and never reused.

**The current intended state, plus deviations.** No history, no measurements beyond numbers that are part of the design (the split limit of four). The evidence is in [`../design/evidence.md`](../design/evidence.md).

**Writing:** short sentences, one idea per sentence, bullets for anything with more than two parts. [`traits.md`](traits.md) serves programmers too: it explains a core developer's term in a plain sentence where it uses one.

## What goes where

- **A rule a user can observe** (accepted or refused, which method runs, which error, which code is shared): `traits.md`. How it is achieved: `lowering.md` and `compiler.md`.
- **What compiled code may assume** (facts, run-time sites, edges, invalidation, pirates as they affect validity): `facts.md`. Who may write a method or declare a membership, and the errors a user sees for it: `traits.md`.
- **An interface of Julia's** (a type-system rule, a compilation signature, a calling convention, a hook, what an image keeps): `compiler.md`, with its semantics.
- **What a macro of the library defines:** `lowering.md`.

## The choices in these references

Every choice beyond the decision log's is listed here, with who made it. The analysis behind them: [`../plans/2026-11-06-traits-are-abstract-types.md`](../plans/2026-11-06-traits-are-abstract-types.md). A choice marked **mine** was made on the user's instruction (2026-11-06: "For the Gaps: Make decisions, think about existing languages, only where no principled option exists, come back to me"); the user confirmed them with the references' adoption (the user, 2026-11-06: "Adopt all recommendations. Go"). P-20 to P-28 answer the draft's two reviews: [the prototypes'](../reviews/2026-11-06-unified-reference-prototypes.md) and [the work plan's](../plans/2026-11-06-work-plan-under-the-draft-reference.md). P-29 to P-32 came with the work plan's adoption (the user, 2026-11-06) and its experiments.

| # | Choice | Made by | Where |
|---|---|---|---|
| P-1 | A default is the trait's method for its operation, and forwarding is served by the trait's method: every caller reaches them, as Rust's and Swift's default methods. | mine | [traits §4.2](traits.md#42-defaults), [§5.5](traits.md#55-forwarding-with-by) |
| P-2 | Each method at a trait is classified per argument, fully bounded (code per key where keys are built, P-29) or open (code per type); `bounded` refuses open methods; `@trait_module` is the bundle of `facts`, `bounded`, `no_pirates`, before the module's first method. | the user (Q2 (a)) | [traits §7.3](traits.md#73-fully-bounded-methods), [§13](traits.md#13-scopes-trait-modules) |
| P-3 | The attribute of each trait argument at each call: a cast at the call, then what the value carries, then the library's default (argument, then module), then the trait's default, then the scope's fallback: what the caller knows in a trait module, `Compiled` elsewhere. | mine for the order, on the user's request for trait and library defaults the user can override; the fallback by scope the user's | [traits §7.5](traits.md#75-what-decides) |
| P-4 | Casts are written as an argument of the call they decide. | mine | [traits §7.6](traits.md#76-casts) |
| P-5 | `Dynamic{X}` is a struct of `Core` whose memberships and methods are the library's, a member of `X` by forwarding, compiled once, a member of `X` and its supertraits only (Rust's `dyn`, Swift's `any`), `X` with its parameters; `keep(x)` stores an argument with its attribute. | mine | [traits §7.7](traits.md#77-dynamicx), [§7.8](traits.md#78-keeping-an-argument-with-its-attribute) |
| P-6 | Intersections `All{X, Y, Z, …}`; a bundle is an alias of one. | the user (Q5 (a)) | [traits §3.6](traits.md#36-intersections), [compiler §4.9](compiler.md#49-intersections) |
| P-7 | `Callable{A, S}`: a function is a member where it has a method at `A` (`hasmethod`), so dispatch picks by the arguments' signature; `S` is checked on return at a call through a value declared `Callable{A, S}`; `Dynamic` by default. | the user (dispatch by signature; `S` checked on return) | [traits §9](traits.md#9-functions-callable), [compiler §7.4](compiler.md#74-callables-call) |
| P-8 | A declared field is the member's stored field of that name, read and written as `t.f`. | the user (Q7 (a)) | [traits §4.3](traits.md#43-fields) |
| P-9 | `struct S <: X` makes `X` the supertype; the membership is declared and checked by `@implement X S` after the methods. | the user (Q8 (c)) | [traits §5.2](traits.md#52-with-the-types-definition) |
| P-10 | A method whose result is `like(t, …)` or `withfields(t; …)` is compiled per type at `t`. | mine | [traits §6.5](traits.md#65-results) |
| P-11 | A trait with a contract counts as concrete as a parameter's value. | mine | [traits §14](traits.md#14-concreteness-and-fully-typed-mode) |
| P-12 | The key's Core type is `Core.TraitKey{X, R, F}`; the runtime computes a member's key from its membership and the contract. | mine | [compiler §6.1](compiler.md#61-the-key-as-a-type) |
| P-13 | A keyed argument passed on is a static call guarded per (key, function), else a run-time site. | mine | [compiler §6.4](compiler.md#64-calls-from-code-compiled-per-key) |
| P-14 | A trait's contract lives on its `TypeName`, read without an edge. | mine | [compiler §4.1](compiler.md#41-sets) |
| P-15 | A trait's split candidates come from the runtime's index of its members, in declaration order. | mine | [compiler §7.2](compiler.md#72-the-split) |
| P-16 | A family states its trait's instance as a pattern of its variables, an equation's parameter included (closes open issue 140). | mine | [traits §5.8](traits.md#58-families), [lowering §4](lowering.md#4-members-checked-at-their-first-use) |
| P-17 | A function of `Self` that an equation names (`eltype(t)`) keeps a method fully bounded (open issue 137). | mine | [traits §7.3](traits.md#73-fully-bounded-methods) |
| P-18 | The member hook: the runtime asks the library to check a pattern member at its first use, at dispatch or before code relying on it is published, outside every lock; inference never asks. | mine | [compiler §10.4](compiler.md#104-the-member-hook) |
| P-19 | `like(t, x)` and `withfields` as functions; overrides stay fixed at the membership. | mine (q-b, q-c) | [traits §6.5](traits.md#65-results), [§5.11](traits.md#511-overrides-and-redeclaration) |
| P-20 | `bounded` on by default in trait modules, with switches: `@open f(…) = …` marks a method open on purpose, `@trait_module bounded = false` a module; storing a trait argument at a struct parameter or in a closure makes a method open; a constructor that sets a parameter bounded by a trait is never refused. | the user (the default with a switch); `@open`, the idioms and the constructors, mine | [traits §7.3](traits.md#73-fully-bounded-methods), [§13](traits.md#13-scopes-trait-modules) |
| P-21 | Normal forms of `Union` and `All` read declared supertypes only, so a type expression gives the same type in every world. | mine | [compiler §4.9](compiler.md#49-intersections) |
| P-22 | At an intersection: the key is the tuple of the components' keys; the split's candidates are the first component's that are members of every component; disagreeing trait defaults leave the attribute to the scope's fallback; a closed component makes it closed against an open set. | mine | [traits §3.6](traits.md#36-intersections), [compiler §4.9](compiler.md#49-intersections) |
| P-23 | The cast names are reserved as `ccall` is; a cast at a plain argument has no effect and `detect_unused_casts` lists it. | mine | [traits §7.6](traits.md#76-casts), [compiler §6.9](compiler.md#69-casts-and-keep) |
| P-24 | Attribute bits travel only through `Core.attributed_call`; a plain dynamic call and Julia's caches carry none. | mine | [compiler §6.3](compiler.md#63-the-attribute-at-a-call) |
| P-25 | The trait's methods reach a key's parts through `Core.trait_receiver` and `Core.trait_field`. | mine | [compiler §6.5](compiler.md#65-the-calling-convention) |
| P-26 | A module-end hook of Julia's. | mine | [compiler §10.1](compiler.md#101-definition-and-image-hooks) |
| P-27 | `HasProperty{N, R}`'s operation is `getproperty` at the constant name `N`, typed `R` on a value known by its trait. | mine | [traits §10.1](traits.md#101-basetraits), [compiler §7.1](compiler.md#71-the-rule) |
| P-28 | Smaller rules: `Type{S}` entries on `S`'s `TypeName`; one instance per member checked by the runtime; the classification kept with edges; a `Union` bound in a family declared per type; array literals join declared supertypes only. | mine | [compiler §4.6](compiler.md#46-one-instance-per-member), [§4.10](compiler.md#410-type-values), [§6.7](compiler.md#67-the-definition-time-check); [lowering §3](lowering.md#3-implement); [traits §10.2](traits.md#102-element-types) |
| P-29 | Keys are Optional, to be built late: a fully bounded method is compiled per type until keys are built; the classification, the contract on the trait's `TypeName` and the receiver each membership records stay Planned, as what keys need. Built late; a use case to investigate, traits with operations only: [open issue 147](../open-issues.md#2-design). | the user (2026-11-06: "keys as optional is approved"; "Keep them optional and build them late") | [traits §7.1](traits.md#71-three-ways-to-compile-an-argument), [§7.2](traits.md#72-the-key), [compiler §6.1](compiler.md#61-the-key-as-a-type) |
| P-30 | `Callable`'s memberships are `F`'s methods, read by subtyping as entries: no method-table query with a memo of its own inside subtyping; a question that reaches itself gives the least fixed point. | mine (E-267) | [compiler §7.4](compiler.md#74-callables-call) |
| P-31 | The G2 bit on every CodeInstance of either policy; an image keeps code reached only dynamically where the bit is set; the boundary flag is the second policy per method. | adopted with the work plan (the user, 2026-11-06); the trade-offs review's M1, M2 | [compiler §2.2](compiler.md#22-the-method-flag), [§3.2](compiler.md#32-g2-as-a-predicate), [§9](compiler.md#9-images-and-the-machine-code-cache) |
| P-32 | An argument the scope's fallback made `Dynamic` is reported (`detect_dynamic_fallbacks`), not counted as declared. | adopted with the work plan (the user, 2026-11-06); the trade-offs review's M9 | [traits §14](traits.md#14-concreteness-and-fully-typed-mode) |

## State of the build

- The type system's sets and memberships are built on branch `unified` (stage W-98, done: e0487d74d9; compiler §4 with C-27). Dispatch at sets is built (W-98's 7db137f922 and W-99's 67cc090897, bdd48fe0bb; compiler §5.1–§5.5 with C-18 and C-29); guards (§5.6) are W-112. The changes useful without traits (compiler §11), the world-checked caches (§8.1, §8.2) and an image's rule for a signature type without a hash (§9) are built, one commit each, below them. Everything else is Planned or Optional: the stages are W-98 to W-114 ([the work queue](../record/todo.md); [the work plan](../plans/2026-11-06-work-plan-under-the-draft-reference.md), adopted 2026-11-06).
- The trait library on the unified build: TraitWorld `unified` e7ff8e2, the first slice (W-106; lowering's Deviations table).
- The deviations of the branch are in [compiler.md](compiler.md#deviations).
