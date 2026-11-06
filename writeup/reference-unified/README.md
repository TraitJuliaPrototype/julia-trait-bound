# The references: Julia with traits in its type system

**Draft** (2026-11-06, W-105). This folder is a proposal until the user adopts it; then it replaces `../reference/`. It describes the design as a whole, from the ground up. "The choices in this draft" below lists every choice beyond the decision log's, with who made it. A section whose choice still waits for the user says **Proposed** in its status line.

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
   - **Planned:** decided, not built;
   - **Proposed:** proposed by this draft, waiting for the user's decision (listed below);
   - **Optional:** built only if a measurement asks for it;
   - **Open:** not decided, linking [`../open-issues.md`](../open-issues.md).

**Deviations separately.** Each reference ends with a table, one row per place where the implementation differs from it: `ID | Section | The reference says | The implementation does | Where`. IDs are stable (`T-n`, `F-n`, `C-n`, `L-n`) and never reused.

**The current intended state, plus deviations.** No history, no measurements beyond numbers that are part of the design (the split limit of four). The evidence is in [`../design/evidence.md`](../design/evidence.md).

**Writing:** short sentences, one idea per sentence, bullets for anything with more than two parts. [`traits.md`](traits.md) serves programmers too: it explains a core developer's term in a plain sentence where it uses one.

## What goes where

- **A rule a user can observe** (accepted or refused, which method runs, which error, which code is shared): `traits.md`. How it is achieved: `lowering.md` and `compiler.md`.
- **What compiled code may assume** (facts, run-time sites, edges, invalidation, pirates as they affect validity): `facts.md`. Who may write a method or declare a membership, and the errors a user sees for it: `traits.md`.
- **An interface of Julia's** (a type-system rule, a compilation signature, a calling convention, a hook, what an image keeps): `compiler.md`, with its semantics.
- **What a macro of the library defines:** `lowering.md`.

## The choices in this draft

Every choice beyond the decision log's is listed here, with who made it. The analysis behind them: [`../plans/2026-11-06-traits-are-abstract-types.md`](../plans/2026-11-06-traits-are-abstract-types.md). A choice marked **mine** was made on the user's instruction (2026-11-06: "For the Gaps: Make decisions, think about existing languages, only where no principled option exists, come back to me"); each is in the decision log as mine, for the user to confirm.

| # | Choice | Made by | Where |
|---|---|---|---|
| P-1 | A default is the trait's method for its operation, and forwarding is served by the trait's method: every caller reaches them, as Rust's and Swift's default methods. | mine | [traits §4.2](traits.md#42-defaults), [§5.5](traits.md#55-forwarding-with-by) |
| P-2 | Each method at a trait is classified per argument, fully bounded (code per key) or open (code per type); `bounded` refuses open methods; `@trait_module` is the bundle of `facts`, `bounded`, `no_pirates`, as a module's first statement. | the user (Q2 (a)) | [traits §7.3](traits.md#73-fully-bounded-methods), [§13](traits.md#13-scopes-trait-modules) |
| P-3 | The attribute of each trait argument at each call: a cast at the call, then what the value carries, then the library's default (argument, then module), then the trait's default, then the scope's fallback: what the caller knows in a trait module, `Compiled` elsewhere. | mine for the order, on the user's request for trait and library defaults the user can override; the fallback by scope the user's | [traits §7.5](traits.md#75-what-decides) |
| P-4 | Casts are written as an argument of the call they decide. | mine | [traits §7.6](traits.md#76-casts) |
| P-5 | `Dynamic{X}` is a type of the library, a member of `X` by forwarding, compiled once, a member of `X` and its supertraits only (Rust's `dyn`, Swift's `any`); `keep(x)` stores an argument with its attribute. | mine | [traits §7.7](traits.md#77-dynamicx), [§7.8](traits.md#78-keeping-an-argument-with-its-attribute) |
| P-6 | Intersections `All{X, Y, Z, …}`; a bundle is an alias of one. | the user (Q5 (a)) | [traits §3.6](traits.md#36-intersections), [compiler §4.9](compiler.md#49-intersections) |
| P-7 | `Callable{A, S}`: memberships derived from the method table (a function is a member where its call at `A` infers to `S`), so dispatch picks by signature; a call through a value declared `Callable{A, S}` has the result `S`; `Dynamic` by default. | the user (dispatch by signature); derived memberships as its form, mine | [traits §9](traits.md#9-functions-callable), [compiler §7.4](compiler.md#74-callables-call) |
| P-8 | A declared field is the member's stored field of that name, read and written as `t.f`. | the user (Q7 (a)) | [traits §4.3](traits.md#43-fields) |
| P-9 | `struct S <: X` makes `X` the supertype; the membership is declared and checked by `@implement X S` after the methods. | the user (Q8 (c)) | [traits §5.2](traits.md#52-with-the-types-definition) |
| P-10 | A method whose result is `like(t, …)` or `withfields(t; …)` is compiled per type at `t`. | mine | [traits §6.5](traits.md#65-results) |
| P-11 | A trait with a contract counts as concrete as a parameter's value. | mine | [traits §14](traits.md#14-concreteness-and-fully-typed-mode) |
| P-12 | The key's Core type is `Core.TraitKey{X, R, F}`. | mine | [compiler §6.1](compiler.md#61-the-key-as-a-type) |
| P-13 | A keyed argument passed on is a static call guarded per (key, function), else a run-time site. | mine | [compiler §6.4](compiler.md#64-calls-from-code-compiled-per-key) |
| P-14 | A trait's contract lives on its `TypeName`, read without an edge. | mine | [compiler §4.1](compiler.md#41-sets) |
| P-15 | A trait's split candidates come from the runtime's index of its members, in declaration order. | mine | [compiler §7.2](compiler.md#72-the-split) |
| P-16 | A family states its trait's instance as a pattern of its variables, an equation's parameter included (closes open issue 140). | mine | [traits §5.8](traits.md#58-families), [lowering §4](lowering.md#4-members-checked-at-their-first-use) |
| P-17 | A function of `Self` that an equation names (`eltype(t)`) keeps a method fully bounded (open issue 137). | mine | [traits §7.3](traits.md#73-fully-bounded-methods) |
| P-18 | The member hook: the runtime asks the library for a pattern member's key at its first use at run time; inference never asks. | mine | [compiler §10.4](compiler.md#104-the-member-hook) |
| P-19 | `like(t, x)` and `withfields` as functions; overrides stay fixed at the membership. | mine (q-b, q-c) | [traits §6.5](traits.md#65-results), [§5.11](traits.md#511-overrides-and-redeclaration) |

## State of the build

- The type system's memberships are built in part on branch `unified` (stage W-98, begun). Dispatch at sets is built in part (W-99). Everything else is Planned: the stages are W-98 to W-104 ([the work queue](../record/todo.md)).
- The trait library on the unified build is not begun.
- The deviations of the branch are in [compiler.md](compiler.md#deviations).
