# Build notes: traits

This page is in the agents' tier ([the record's index](../INDEX.md)).
It holds what the pass of 2026-11-18 over [the traits reference](../../reference/traits.md) took out of it: where each rule is in the code, the commits that built it, its gates, who decided it, its experiments.
The reference is the source of truth for the rule; this page is its build log, by section, in the reference's order.

### The top of the page

- **Taken from the page's text:** **Adopted** (the user, 2026-11-06; W-105; [the folder's README](../../reference/README.md)). This page defines the trait language: what a trait is, how a type joins one, how methods at traits dispatch and are compiled, what is checked, and which errors a user sees. It describes the language as designed. The status line of each section says how far it is built.
- **Taken from the page's text:** **Status labels:** Implemented, Planned, Optional, Open, and "mine" for a choice an agent made, as [the README](../../reference/README.md#conventions-for-every-reference) defines them.

### §2 Syntax summary

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2 for `@trait` and `@implement` (W-106); `@trait_module` and `@default_dynamic` bb78d02 (W-111); concreteness W-114. The library still accepts `@default_compiled`, the options `dynamic` and `first_seen`, and the casts: T-127.

### §3.1 Membership

- **The status line as it stood:** Implemented in Julia's type system on branch `unified` 62016706d0 ([compiler §4](../../reference/compiler.md#4-sets-and-memberships), with its deviations); `@trait` and `@implement` in TraitWorld `unified` e7ff8e2. A membership taken back: Planned (§5.13).

### §3.2 Parameters

- **The status line as it stood:** Implemented on `unified` 62016706d0 (subtyping) and in TraitWorld `unified` e7ff8e2 (the checks); a member at several values of an input on `unified` 350c5b1c59 and in TraitWorld `unified` a658203 (gate `n10_inputs`), but for the refusal of an input left open (T-105). A family states its instance as a pattern, an equation's parameter included (§5.8): mine (2026-11-06; open issue 140).

### §3.3 Where a trait stands

- **The status line as it stood:** Implemented on `unified` 62016706d0 and 29035cab11 (W-98, W-99): a set is an abstract type wherever a type stands.

### §3.4 Open and closed

- **The status line as it stood:** Implemented on `unified` 62016706d0 (W-98). A non-membership relied on: Implemented on `unified` a19d937eaa (W-140; [compiler §4.8](../../reference/compiler.md#48-negatives-fold-with-an-edge-positives-through-entries), [§5.5](../../reference/compiler.md#55-a-membership-invalidates-as-a-method-does); gates `n18_closed_after_load`, `n7_guards`, `n16_declared_result`, `n25_image_before_set_method`), with compiler C-88. The rule: the user (2026-11-11, "declaring membership of a type in a trait if you own neither the type or the trait is piracy").

### §3.5 Values

- **The status line as it stood:** Implemented on `unified` 62016706d0 (W-98): a member's value is a value of the trait, unwrapped. The argument at a trait that erases by default as a kept form: Implemented (the plan's D-1, 2026-11-15; [decisions](../decisions.md) §3): the method made at the kept forms where it is defined (julia `next` 8b1ec88a56, TraitWorld `unified` 21ae901; W-160), with T-125. A view that is not the object: the user (2026-11-15, "1 is acceptable").

### §3.6 Intersections

- **The status line as it stood:** Implemented (W-107; the user, 2026-11-06: Q5 (a), "spelled All{X,Y,Z,...}") on `unified` 8a9144928e with TraitWorld `unified` ae4d250, but for the split's members (W-109). The name from the library: mine (2026-11-07; [open issue 148](../../open-issues.md#2-design), its recommendation (b)).

### §4.1 Operations

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2 at each membership; the result asserted at a call through the trait: Implemented (§7.9). An operation as an entry of the contract, with no method at the trait for an operation without a default, and Julia's `MethodError` with the contract's hint outside the declared signature: Implemented (the plan's D-4, 2026-11-15; [decisions](../decisions.md) §1): julia `next` 5448a8b7bf, TraitWorld `unified` c838f76 and 4b6c1d6 (W-161, E-498).

### §4.2 Defaults

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2; mine (2026-11-06). Only a default as a method at the trait: Implemented (D-4; julia `next` 5448a8b7bf, TraitWorld `unified` c838f76 and 4b6c1d6 (W-161, E-498)).

### §4.3 Fields

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2 (the user, 2026-11-06, Q7 (a)); a field named by an input in TraitWorld `unified` a658203, mine (2026-11-08). Swift's protocol properties are the conforming type's own properties in the same way.

### §4.4 `Self`

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2.

### §4.5 Supertraits

- **The status line as it stood:** Implemented on `unified` 62016706d0 and in TraitWorld `unified` e7ff8e2.

### §4.6 Erasing by default

- **The status line as it stood:** Implemented (the plan's D-1, 2026-11-15; [decisions](../decisions.md) §3): the library records it on its contract (TraitWorld `unified` 5e2ef71, W-151), and its expansion hook reads it where a method is defined (julia `next` 8b1ec88a56, TraitWorld 21ae901; W-160), with T-125. The trait's say over a plain member: the user (2026-11-06: "Dynamic or not as a trait and library default, that the user can override"); as forwarders made at each method: the user (2026-11-15: "if Callable wants it anyway that's how it should be").

### §5.1 The forms

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2.

### §5.2 With the type's definition

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2 for the declaration and its check, and 701aaab for the refusal at a module's end, by Julia's module-end hook ([compiler §10.1](../../reference/compiler.md#101-definition-and-image-hooks), `unified` 28c401eb0c); the use before it raised at a use dispatched at run time in TraitWorld 0aff625 with `unified` 352b916899 (E-350), mine (2026-11-10); a use compiled with the type known on `unified` fcdfd0da36 (E-352; the user, 2026-11-06, Q8 (c): "declared membership stays as a design goal"). The membership's entry, and the parameters from the definition: TraitWorld e8554d9, mine (2026-11-10, W-131, E-345).

### §5.3 One line

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2.

### §5.4 With a block of methods

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2.

### §5.5 Forwarding with `by`

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2; the trait's method serving a forwarding member is mine (2026-11-06). The member's own methods for required operations: TraitWorld (W-128), mine (open issue 158 (a), 2026-11-08).

### §5.6 Several traits at once

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2.

### §5.7 Stating parameters

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2.

### §5.8 Families

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2, each member checked at its first use, at dispatch and before compiled code runs (`unified` fcdfd0da36, E-352; compiler C-31); a variable bounded by a `Union` declared per type in dd72b10; the variables in the block's methods in 401c7b4, mine (2026-11-08).

### §5.9 Abstract types and traits as members

- **The status line as it stood:** Implemented on `unified` 62016706d0 and in TraitWorld `unified` e7ff8e2.

### §5.10 Checks

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2 at a declaration and at a first use at dispatch; an image keeps the answers that passed while it was built ([lowering §11](../../reference/lowering.md#11-checks-errors-and-what-images-keep); `unified` b1c0b50f4c, TraitWorld 347176a). The rule at an abstract further argument: TraitWorld 4be0097, mine (2026-11-07). A method that takes any receiver serving an operation without a default: Implemented (D-4; julia `next` 5448a8b7bf, TraitWorld `unified` c838f76 and 4b6c1d6 (W-161, E-498); open issue 150's case, `mul!`, `w161/d4/op150.jl`). The check kept while a member: TraitWorld `unified` 5b3c427, mine (2026-11-10), for memberships declared in the session and members of a family, an abstract type or a trait checked in it; for a membership loaded from a package's image, TraitWorld 6871ea9 with `unified` e42047dba2 (E-344). A member by its definition, from an image too: TraitWorld e8554d9 (W-131, E-345). Cost: one dictionary lookup per method definition; for a definition of an operation's function, one intersection per kept call under the function, and one inference per call the method would take. The check as its serving instances, kept with edges and validated with an image; a method below an operation's body judged through them; the walk shared with strict mode: Planned (the plan's D-3, 2026-11-15), with T-129.

### §5.11 Overrides and redeclaration

- **The status line as it stood:** Implemented in TraitWorld `unified` 701aaab by the definition and image hooks ([compiler §10.1](../../reference/compiler.md#101-definition-and-image-hooks)), for memberships declared in the session; for one loaded from an image, TraitWorld 6871ea9 (E-344). A redeclaration's new entry on `unified` 62016706d0. The forwarding's methods, members checked at their first use, and the call a method would take (it applies there and no method in force beats it): TraitWorld `unified` 5b3c427, mine (2026-11-10).

### §5.12 Types that only convert

- **The status line as it stood:** Planned.

### §5.13 Taking a membership back

- **The status line as it stood:** Implemented in TraitWorld `s3` 9e0e3f4 with `next-s3` 213c759370 (the plan's D-13, 2026-11-15; the user, by adopting the plan; `test/delete.jl`, E-459), but for Revise: no extension yet ([lowering L-64](../../reference/lowering.md#15-deviations)). The mechanism (the membership's method deleted, the walk run for the removal), the name `delete_membership` and its keyword `by` (the module that takes it back, by default the declarer), and what cannot be taken back alone: mine (2026-11-15).
- **Taken from the section's text:** a later method at the member is judged by them no longer;

### §6.1 A method at a trait is a method

- **The status line as it stood:** Implemented in Julia's dispatch on `unified` 29035cab11 ([compiler §5](../../reference/compiler.md#5-dispatch)); how a method is compiled: §7.3's status.

### §6.2 Specificity

- **The status line as it stood:** Implemented on `unified` 62016706d0 ([compiler §5.2](../../reference/compiler.md#52-specificity)); intersections 8a9144928e (W-107).

### §6.3 Ambiguity

- **The status line as it stood:** Implemented on `unified` 0d529d33a9 for a concrete member, 264b7f959f for a pattern ([compiler §5.4](../../reference/compiler.md#54-the-ambiguity-report-at-a-membership)): the warning names the function, the two traits and the joint method's signature, `f(::All{…})` (8a9144928e, W-107); the error under strict mode on `unified` 0bb8f38830 with TraitWorld 960b99e (E-343), for the membership that creates the ambiguity on `unified` 2ee5569252 (E-346); a tie with a method at a declared supertype, a superset or `Any` on `unified` 53d28eea68 with TraitWorld 9383843 (`test/declared.jl`, E-347); at an image's activation reported after the load on `unified` 9f8d7d7c48 with TraitWorld 0aff625 (E-349, [§12.3](../../reference/traits.md#123-strict-mode)).

### §6.4 The fallback

- **The status line as it stood:** Implemented on `unified` 29035cab11: Julia's dispatch.

### §6.5 Results

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2. As the library's conveniences: the plan's D-14 (2026-11-15).

### §6.6 Keywords, defaults, varargs

- **The status line as it stood:** Implemented as Julia's: a positional default's two methods, a keyword typed by a trait (`TypeError` for a value that is no member) and a vararg of different members run in `experiments/docs-examples/tutorial.jl` (§9 there; TraitWorld c9f701e, where under `bounded` the default's short method waits for the method it calls, §7.3).

### §6.7 Constructors

- **The status line as it stood:** Planned.

### §6.8 Who may add a method

- **The status line as it stood:** Implemented: Julia's rule, with the refusal in a scope that declares `no_pirates` (TraitWorld `unified` 7adcc94, W-114; §12.2). Owner-only functions: TraitWorld `s3` 4210852 with `next-s3` e483299622 (D-9, E-458).

### §7.1 How an argument is compiled

- **The status line as it stood:** Per type and `@nospecialize`: Julia's. The two kept forms: TraitWorld `unified` 5e2ef71 (W-151), with T-126. On the build, `@nospecialize` at a trait argument still takes the attribute's path ([compiler C-112](../../reference/compiler.md#deviations)). Per key: Optional, to be built late (W-110; the user, 2026-11-06: "keys as optional is approved", and "Keep them optional and build them late"). A use case to investigate, traits with operations only: [open issue 147](../../open-issues.md#2-design).

### §7.2 The key

- **The status line as it stood:** Optional (W-110; the plan's D-14, 2026-11-15).

### §7.3 Bounded methods

- **The status line as it stood:** Implemented (the plan's D-3, 2026-11-15, confirmed by the user's adoption of the plan; [decisions](../decisions.md) §2): TraitWorld `unified` 6f86b4e (W-151; `src/atbox.jl`; E-401, E-406: E-397's mistakes found at their lines, no fault in the ports' 249 methods); the instance read from Julia's cache and kept at a load (TraitWorld 9c0912b, `next` 75a7f1795b; W-160, E-440, E-444), with [compiler C-115](../../reference/compiler.md#deviations) (read apart where a box's call runs the attribute's instance); an equation's function at the box: T-130. The fault classes, the stand-ins and what is not read: mine (2026-11-15, the prototype's). `bounded` on in trait modules with a switch: the user (2026-11-06, Q2 (a)); `@unbounded`: mine (2026-11-06).

### §7.4 The two kept forms: the box and the wrapper

- **The status line as it stood:** Planned (the plan's D-1, 2026-11-15; [decisions](../decisions.md) §3). Built in TraitWorld `unified` 5e2ef71 to 6f86b4e (W-151; E-401 to E-406): the box `Core.Dynamic`, the wrapper `Compiled{T}` as the library's type (T-126). The forms as values: the user (2026-11-15, "So provisionally I would accept P1 with the addendum.", then "Yes please. Build the compiler for P1 …"). The wrapper's reach: the user (2026-11-15, "I would say that we want wide reach. If a subtrait provides a higher performance specialisation we don't want to miss that."). The name `Compiled{T}`: mine (2026-11-15).

### §7.5 What decides

- **The status line as it stood:** Planned (the plan's D-1, 2026-11-15; [decisions](../decisions.md) §3). Built in TraitWorld `unified` 6f86b4e (W-151); the forwarders made where a method is defined (julia `next` 8b1ec88a56, TraitWorld 21ae901; W-160), with T-125; Julia still resolves an attribute at each trait argument ([compiler C-112](../../reference/compiler.md#deviations)), and the library still offers its surface (T-127). The principle: the user (2026-10-21, "Values carry"); the choice in the value's type: the user (2026-11-15, D-1).

### §7.6 `compiled_for(x)`

- **The status line as it stood:** Planned (the plan's D-1, 2026-11-15). Built in TraitWorld `unified` 5e2ef71 (W-151; `test/bytype.jl`), with T-126: the library's exported `compiled_for` is still the cast of Julia's, and a module binds the wrapper's function as `TraitWorld.ByType.compiled_for`. The wrapper's name and its reach of every `Callable` by its call method: mine (2026-11-15, the prototype's).

### §7.7 `Dynamic{X}`

- **The status line as it stood:** Implemented: the struct is Julia's `Core.Dynamic` (`unified` e692e57ab7, W-111); its memberships and methods are the library's (TraitWorld `unified` bb78d02); a `Dynamic{All{Callable…}}` called at either signature in 401c7b4. A box of the same trait as itself, of a subtrait and of a wrapper as their object's box: TraitWorld 5a9d19d (W-151), in place of `Core.Dynamic`'s own constructor ([compiler C-113](../../reference/compiler.md#deviations)); the membership decided when compiled: Implemented (`next` 5b1900641f, W-160). Mine (2026-11-06). In `Core`, members of intersections, parameters required, the second signature: mine (2026-11-06, the reviews of the draft). A box of the same trait as itself: mine (2026-11-15, the prototype's).

### §7.8 Erasing by default: the forwarder

- **The status line as it stood:** Implemented (the plan's D-1, 2026-11-15; [decisions](../decisions.md) §3; W-160): Julia's `next` 8b1ec88a56 asks the library's expansion hook where a method is defined ([compiler §6.3](../../reference/compiler.md#63-the-forwarders)); TraitWorld `unified` 21ae901, d537141, 2bf59b9; the box's test decided where the code is compiled (`next` 5b1900641f), with [compiler C-111](../../reference/compiler.md#deviations) and T-125 for the forwarder's record of its method. The forwarder's shape, which arguments erase, the trait's own methods not forwarded, and no type exempt: mine (2026-11-15, the prototype's). The default constructors forwarded: mine (2026-11-15). The arguments not boxed and the forwarder compiled per member type where the member fixes its trait's parameters: mine (2026-11-15, W-160). A trait's parameters left open erase, an input left open does not: TraitWorld `unified` fb67ac1 ([open issue 204](../../../attic/writeup/record/issues-closed.md), E-497), mine (2026-11-15: the trait's default applies to anyone who writes a method).

### §7.9 Operations on a value the code knows only by its trait

- **The status line as it stood:** The declared result, asserted, and the branches on the first four members implemented on `unified` e70675a606 with TraitWorld e9a63f7 ([compiler §7](../../reference/compiler.md#7-operations-on-a-value-typed-by-its-trait)); and the table past them; declared fields: W-109. Asserted, never converted, on `unified` ef1233e79e (open issue 171, gate `n22_declared_assert`, E-340): mine (2026-11-10).

### §7.10 Costs, and choosing

- **The status line as it stood:** Planned.
- **Taken from the section's text:** (E-401 to E-407)

### §8.1 Fields and containers typed by a trait

- **The status line as it stood:** Julia's storage, with TraitWorld `unified` e7ff8e2's members: Implemented. The conversion into storage typed `Dynamic{X}`: TraitWorld `unified` 5e2ef71 (W-151; a late load of it ends nothing, E-404). Storage that keeps the form given: the plan's D-1 (2026-11-15; [decisions](../decisions.md) §3), the storage table of [the review's addendum](../../reviews/2026-11-15-conceptual-design.md#addendum-2026-11-15-the-main-session-p1-corrected-in-discussion-and-provisionally-accepted).

### §8.2 A struct parameter bounded by a trait

- **The status line as it stood:** Julia's bound and default constructor, with TraitWorld `unified` e7ff8e2's members: Implemented. The parameter recording the form, and a plain member boxed at an erasing trait: the plan's D-1 (2026-11-15); built where a method is defined, Julia's default outer constructor included (julia `next` 8b1ec88a56, TraitWorld `unified` 2bf59b9; W-160), with T-125.

### §8.3 Equality

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2 for the box, 5e2ef71 for the wrapper; mine (2026-11-06), the wrapper's mine (2026-11-15).

### §9 Functions: `Callable`

- **The status line as it stood:** Implemented (the plan's D-2, 2026-11-15, the user: "Okay, accept the change."; [decisions](../decisions.md) §3; W-153): every function a member by Core's entry, subtyping reads no method, julia `next` eaa19da272; the box's test at `A`, the wrapper's at entry and `@implement Callable T`, TraitWorld `unified` c14d2e4 (W-161, E-500), with [compiler C-146](../../reference/compiler.md#deviations) and T-156. The box's call, checked at both ends: TraitWorld 5d52f0d (W-113); the hint for a function with no method at `A`: TraitWorld e572379 (W-114), the hint at a failed result L-58. `S` checked on return: the user (2026-11-06, "For Callable S go with checked on return. Keep it simple."). A callable struct declared a member, and a wrapper's calls as the function's own: mine (2026-11-15). The wrapper's result inferred at entry against `S` ([GT-24](../../goals.md#3-tensions-between-the-goals) (b)): mine (2026-11-15, W-161). A callable struct of plain code, which declares nothing: [GT-32](../../goals.md#3-tensions-between-the-goals). Keywords Planned.

### §9b Streams: `IO`

- **The status line as it stood:** Implemented on `unified` b05ae361e0 (E-337); the display erasing on `unified` 8c4b93f867 with the forks' DataFrames plain and its workload line (forks ddc20f6; E-339), adopted (the user, 2026-11-09: "That said, b-display is adopted."; E-338; `TextDisplay` mine); the counts `Int`, converted at the call, on 0c836f3ef6 (E-333). The user (2026-11-09: "Go with the Fable plans recommendations", [the plan](../../../attic/writeup/plans/2026-11-09-io-alternatives.md) §4.2, option B). `eof`, `isopen` and `close` out of the contract: mine (2026-11-09).

### §10.1 BaseTraits

- **The status line as it stood:** Implemented in TraitWorld `unified` 4be0097 with `unified` 0ce5b7f752 (W-114); `HasProperty` in TraitWorld `unified` a658203 with `unified` 350c5b1c59; tests `basetraits.jl`. The table's contracts follow the prior art of Rust, Swift and Mojo ([the research](../collection-and-linalg-traits-research-2026-11-07.md); the user, 2026-11-07: "When it comes to Base Traits and Lin Alg Traits, send out an agent that collects prior art from Rust, Swift, Mojo") and [the review of the choices](../../../attic/writeup/reviews/2026-11-07-basetraits-choices.md); each choice is mine (2026-11-07), listed in [open issues §1](../../open-issues.md#1-decisions-waiting-for-the-user). Base's own tests pass with BaseTraits loaded, at their times without it (E-282).
- **Taken from the section's text:** (E-281)

### §10.2 Element types

- **The status line as it stood:** Implemented: Julia's variance with BaseTraits' memberships (TraitWorld `unified` 4be0097); tests `basetraits.jl`.

### §10.3 Algorithms

- **The status line as it stood:** Implemented in TraitWorld `unified` 4be0097 (W-114).

### §11.1 When checks run

- **The status line as it stood:** Implemented in TraitWorld `unified` e7ff8e2 at `@trait`, at `@implement` and at a member's first use at dispatch; at a module's end and at a method's definition (an override) in TraitWorld 701aaab; a member's check kept at a method's definition and an image's load in 5b3c427 (§5.10); `bounded` in bb78d02 (W-111); ownership, pirates and strict mode in 7adcc94 (W-114). The ambiguity at a membership an error under strict mode on `unified` 0bb8f38830 (E-343); at an image's activation reported at error level after the load on 9f8d7d7c48 with TraitWorld 0aff625 (E-349).

### §11.2 Definition checking

- **The status line as it stood:** Implemented (the plan's D-3, 2026-11-15; [decisions](../decisions.md) §2): TraitWorld `unified` 6f86b4e (W-151; `check_definitions` and the `bounded` refusal read the box); an edit infers the instance at the box once, at its definition (TraitWorld 9c0912b, W-160, E-440), with [compiler C-115](../../reference/compiler.md#deviations); the failure at the definition in a trait module, and so while a package is precompiled (TraitWorld `unified` bb78d02, W-111).

### §11.3 Errors and their messages

- **The status line as it stood:** `ImplementError` and `TraitUseError` in TraitWorld `unified` e7ff8e2; `OwnershipError`, `PirateError`, `NotFullyTypedError` and `AbstractTypeError` in 7adcc94 (W-114). A concrete part refused at a call (§14) raises `TraitUseError`: mine (2026-11-07). The form of a message: TraitWorld 6a8ee7f and 158d000 with `unified` dd3f6d839b (`test/messages.jl`; E-362), mine (2026-11-11); the messages against plain Julia's for the same mistakes: [evidence §4d](../../design/evidence.md#4d-error-messages-against-plain-julias). A check's error raised at the user's line: TraitWorld 399f389 with `unified` 8f42ba7ed7 (`test/messages.jl`), mine (2026-11-12; [decisions](../decisions.md) §2). An operation called outside its declared signature as Julia's `MethodError` with the contract's hint: Implemented (D-4; julia `next` 5448a8b7bf, TraitWorld `unified` c838f76 and 4b6c1d6 (W-161, E-498)). A pirate reported where it ends deep-G2 code: §12.2. A port's run-time failures: [open issue 177](../../open-issues.md#2-design).

### §11.4 Hints

- **The status line as it stood:** Implemented in TraitWorld `unified` 7adcc94 (W-114), as hints on Julia's `MethodError`; the ambiguity's joint method is Julia's own message on `unified` (`f(::All{X, Y})`), so the library adds none. No hint at another owner's function: TraitWorld 99c4934, mine (2026-11-11; E-363). The declared signature read from the contract, where an argument at the operation's receiver position is a member: Implemented (D-4; julia `next` 5448a8b7bf, TraitWorld `unified` c838f76 and 4b6c1d6 (W-161, E-498)). The SciML error cases' gate: T-99.

### §12.1 Who may declare a membership

- **The status line as it stood:** Implemented in TraitWorld `unified` 7adcc94 (W-114): `owner`, `@joint_owners`, `OwnershipError` at `@implement` and for a block's methods, an extension's triggers; tests `ownership.jl`. Open: whether the standard libraries are owners of their own ([open issues §1.19](../../open-issues.md#1-decisions-waiting-for-the-user)).

### §12.2 Pirates

- **The status line as it stood:** Implemented in TraitWorld `unified` 7adcc94 (W-114): the definition hook refuses a pirate in a `no_pirates` scope. A method of another's owner-only function as a pirate's, and `@owner_only`: TraitWorld `s3` 4210852, 4f34916 with `next-s3` e483299622 (the plan's D-9, 2026-11-15; `test/owner_only.jl`, E-458); the form `@owner_only` and the default for trait modules are mine (2026-11-15). A pirate's membership: TraitWorld dbfb488 (W-140, stage 1; `test/ownership.jl`); by the method's rule, in a `no_pirates` scope and under strict mode: TraitWorld a2ca7be with `unified` 7fee959383 (`test/ownership.jl`, `test/strict.jl`): the user (2026-11-12; [decisions](../decisions.md) §4). A pirate reported by default where it ends deep-G2 code: TraitWorld `s3` 2770c10 with `next-s3` 5d2ec7ff85 (the plan's D-12, 2026-11-15; `test/report.jl`, E-457); the switch's name and spelling are mine (2026-11-15). The reports given are kept (`TraitWorld.PIRATE_REPORTS`).

### §12.3 Strict mode

- **The status line as it stood:** Implemented in TraitWorld `unified` 7adcc94 with `unified` 5f2373b2d5 (W-114): the refusal before the definition, the check after it, the image hook, the report after a load, the deletion hook; the earlier library's strict-mode cases pass (`test/strict.jl`). An ambiguity at a membership refused on `unified` 0bb8f38830 with TraitWorld 960b99e (`test/strict_membership.jl`, E-343). An ambiguity at an image's activated membership reported at error level after the load and kept (`TraitWorld._LOAD_AMBIGUITIES`) in TraitWorld 0aff625 with `unified` 9f8d7d7c48 (gate `stack/strict_activation.jl`, E-349): mine (2026-11-10). The report at error level, kept (`TraitWorld._LOAD_MEMBERSHIPS`), in TraitWorld 048c44e (gate `stack/strict_load_membership.jl`, E-353): mine (2026-11-10); only the check instances that fail validation inferred again: Planned (D-3), with T-129. A pirate's membership by the method's rule: TraitWorld a2ca7be with `unified` 7fee959383 (`test/strict.jl`; gate `stack/strict_pirate_membership.jl`): the user (2026-11-12). With T-96, T-97, T-112. The warning at an extension's method: TraitWorld 12b8b31 (stack gate `strict_extension_method`).

### §13 Scopes: trait modules

- **The status line as it stood:** Implemented in TraitWorld `unified` bb78d02 (`@trait_module`; W-111; the user, 2026-11-06, Q2 (a)). The three options and no other: the plan's D-1 and D-14 (2026-11-15); the library still accepts `dynamic` and `first_seen` (T-127).

### §14 Concreteness and fully typed mode

- **The status line as it stood:** Implemented in TraitWorld `unified` 7adcc94 with `unified` 5f2373b2d5 (W-114; [compiler §2.7](../../reference/compiler.md#27-fully-typed-mode)); tests `fullytyped.jl`, acceptance case `AC_16`, gate `n9_fully_typed`. With T-100, T-101. Fully typed as exactly what compiles ahead, the report as the build's own check: Implemented on `unified` 381cc8b953 with TraitWorld `unified` 78a78af (W-142; E-369: the check and the build agree on 17 of 18 programs), with T-109; the check as the build's code run in the session, and the modes raising only where it refuses: mine (2026-11-12; [decisions](../decisions.md) §6). The abstract result as no fault, and `@enforce_concrete_only result`: Implemented on `unified` 22db66e23c with TraitWorld `unified` d804c78 (W-142; gate `n9_fully_typed`, test `fullytyped.jl`); the user (2026-11-11): "I meant 2 not 1. So 2, 3, 4 with Kept is agreed. We can think about syntax sugar for this later.". The name `result`: mine (2026-11-11). The modes' check in the compiler: mine (2026-11-07). A trait as a concrete parameter value is mine (2026-11-06), as Rust's `Vec<Box<dyn Trait>>` and Swift's `[any P]` are concrete. Fully typed with the setting as its parameter, in a session and when closed, and the report's two lists: mine (2026-11-15; the plan's D-10), with T-122.

### §15 Printing

- **The status line as it stood:** Implemented: `Dynamic{X}`'s printing in TraitWorld `unified` 745056c (W-111), the wrapper's in 5e2ef71 (W-151).

### §16 Compiling ahead, closed programs

- **The status line as it stood:** `make_executable` and `make_library`: Implemented in TraitWorld `unified` 19862aa (W-139; `test/build.jl`, E-364's `make.jl`): mine in their form (2026-11-11), asked for by the user. A function written at the prompt: Implemented in TraitWorld `unified` 633d6c0 (E-364: entered at a real prompt, built, run); the selection by name from the prompt's history is mine (2026-11-11). The fully typed report as the build's, the check before a build, and the build's Base read by the check: Implemented in TraitWorld `unified` 78a78af with `unified` 381cc8b953 (W-142; E-369: TraitTables' table program is fully typed, builds and runs; `experiments/implementation/w139/make.jl`), with T-109; the replacements as an overlay method table read from the build script's files: mine (2026-11-14; [decisions](../decisions.md) §6). A closed build compiling generic code for its members: Implemented on `unified` 97861c6b31 ([compiler §7.6](../../reference/compiler.md#76-a-closed-build); W-139, E-364), for a set whose members are declared at concrete types, at families (`S{T} where T`) or at subtraits; not at an abstract type (compiler C-86). The rest: Implemented in TraitWorld `unified` 05991fc with `unified` 5f2373b2d5 and e81cd49a67 (W-114, W-135): compiling ahead, gate `ahead_two_packages.jl`; `verify_main`, tests `verify.jl`, with T-108. The targets at a value known only by its trait, the entry points and the bound: mine (2026-11-10); a wrapper's in place of a cast's: the plan's D-1 (2026-11-15), with T-127. A build that compiles what is written, and a method that erases compiled ahead at the box: Planned (D-1, D-3), with [compiler C-112, C-114](../../reference/compiler.md#deviations) and [lowering L-66](../../reference/lowering.md#15-deviations). Trimmed binaries: E-361 ([evidence §4](../../design/evidence.md#4-builds-and-binaries)).

### §17 Named implementations

- **The status line as it stood:** Planned (deferred).

### §18 Status index

- **The table as it stood** (the pass rewrote its status column to follow the new status lines):

| Construct | Status | Section |
|---|---|---|
| a trait is an abstract type; membership, transitivity, worlds | Implemented (`unified` 62016706d0) | §3.1 |
| parameters as associated types; invariance, `X{<:T}`; one instance per member | Implemented (`unified` 62016706d0, TraitWorld e7ff8e2); inputs `unified` 350c5b1c59, TraitWorld a658203, but T-105 | §3.2 |
| a family states its instance as a pattern, equations included | Implemented (TraitWorld e7ff8e2) | §3.2, §5.8 |
| a trait wherever a type stands | Implemented (`unified` 29035cab11) | §3.3 |
| a non-membership relied on, with its edge; a pirate's membership | Implemented (`unified` bf447db25e, 80aa919bed, 7fee959383; TraitWorld dbfb488, a2ca7be), with C-76, C-77, C-88, T-112 | §3.4, §12.2 |
| intersections `All{X, Y, Z, …}`; bundles as aliases | Implemented (`unified` 8a9144928e, TraitWorld ae4d250) | §3.6 |
| operations, `where` on operations, the receiver at any position | Implemented (TraitWorld e7ff8e2) | §4.1 |
| an operation as an entry of the contract: no method at the trait for one without a default; `MethodError` with the contract's hint outside the declared signature | Implemented (D-4; julia `next` 5448a8b7bf, TraitWorld `unified` c838f76, W-161) | §4.1, §4.2, §11 |
| defaults as the trait's methods, reached by every caller | Implemented (TraitWorld e7ff8e2) | §4.2 |
| declared fields as stored fields | Implemented (TraitWorld e7ff8e2) | §4.3 |
| `Self`; supertraits | Implemented (TraitWorld e7ff8e2) | §4.4, §4.5 |
| `struct S <: X`, declared and checked by `@implement X S` | Implemented (TraitWorld e7ff8e2, 701aaab: the module's end; 0aff625 with `unified` fcdfd0da36: the use before it) | §5.2 |
| one line, block, several traits, stated parameters | Implemented (TraitWorld e7ff8e2) | §5.3–§5.7 |
| forwarding: the member's own methods; a default through the trait's method | Implemented (TraitWorld e7ff8e2; the member's methods W-128) | §5.5 |
| families; abstract types and traits as members | Implemented (TraitWorld e7ff8e2, dd72b10) | §5.8, §5.9 |
| checks at the declaration and at first use | Implemented (TraitWorld e7ff8e2, `unified` ec4f9a8714, fcdfd0da36: at dispatch and before compiled code runs; C-31); kept while a member, also from an image (TraitWorld 6871ea9, E-344); pattern answers in images L-55; the check as kept instances with edges: Planned (D-3, T-129) | §5.10 |
| overrides fixed; redeclaration | Implemented (TraitWorld 701aaab; from images TraitWorld 6871ea9, E-344); a redeclaration's entry (`unified` 62016706d0) | §5.11 |
| a membership taken back, `delete_membership`; Revise on memberships | Implemented (TraitWorld `s3` 9e0e3f4, `next-s3` 213c759370; D-13, E-459); Revise: Planned, with L-64 | §5.13 |
| dispatch: specificity, ambiguity reported at a membership, fallback | Implemented (`unified` 62016706d0, 0d529d33a9, 8a9144928e) | §6.2–§6.4 |
| `like`, `withfields`: the library's conveniences | Implemented (TraitWorld e7ff8e2) | §6.5 |
| keywords, defaults, varargs at traits | Implemented as Julia's (TraitWorld c9f701e under `bounded`) | §6.6 |
| keys and shared code: an optional extension | Optional, built late (W-110; open issue 147) | §7.2; [extensions §1](../../reference/extensions.md#1-keys-code-shared-among-members-the-contract-sees-alike) |
| bounded methods: the instance at the box, read where a method is defined | Implemented (D-3; TraitWorld 6f86b4e, W-151; read from Julia's cache, 9c0912b, W-160), with compiler C-115, T-130; `bounded` and `@unbounded` TraitWorld bb78d02 (W-111) | §7.3, §11.2 |
| the two kept forms, the box and the wrapper; the value's type decides | Planned (D-1); built in TraitWorld 5e2ef71 to 6f86b4e (W-151), with T-126, T-127, compiler C-112, C-113 | §7.4–§7.6 |
| `Dynamic{X}`, the box | Implemented (`unified` e692e57ab7, W-111; TraitWorld 5a9d19d; its test decided where the code is compiled, `next` 5b1900641f, W-160), with compiler C-113 | §7.7 |
| erasing by default: the forwarder made where a method is defined | Implemented (`next` 8b1ec88a56, TraitWorld `unified` 21ae901; W-160), with T-125, compiler C-111 | §4.6, §7.8 |
| operations on a value known only by its trait | Implemented (`unified` e70675a606, W-109) | §7.9 |
| storage typed by a trait; struct parameters; storage keeps the form given | Implemented (Julia's, with TraitWorld e7ff8e2; the conversion into `Dynamic{X}` 5e2ef71) | §8 |
| `Callable`: every function a member; the signature checked at the box and at a wrapper's entry, the result on return | Implemented (D-2: `next` eaa19da272, TraitWorld c14d2e4; W-161), with compiler C-146, T-156 | §9 |
| A closed abstract type with a contract; `IO`'s contract; the eraser `IOContext{IO}` | Implemented (`unified` b05ae361e0) | §3.4, §9b |
| BaseTraits; element types by variance; `retain!` | Implemented (TraitWorld 4be0097, `unified` 0ce5b7f752; W-114; `HasProperty` TraitWorld a658203, `unified` 350c5b1c59) | §10 |
| checks, errors, hints | Implemented (TraitWorld e7ff8e2; definition checking 59134ef, bb78d02; hints and the errors of §12, §14 7adcc94; errors at the user's line 399f389); an operation outside its signature as Julia's `MethodError` with the contract's hint: Implemented (D-4; TraitWorld `unified` c838f76) | §11 |
| ownership, joint owners, pirates, strict mode | Implemented (TraitWorld 7adcc94, `unified` 5f2373b2d5; W-114; an ambiguity at a membership refused, E-343, and reported at an image's activation, E-349), with T-96, T-97 | §12 |
| owner-only functions, `@owner_only` | Implemented (TraitWorld `s3` 4210852, `next-s3` e483299622; D-9, E-458), with compiler C-130 | §6.8, §12.2 |
| a pirate reported where it ends deep-G2 code; `report_pirates!` | Implemented (TraitWorld `s3` 2770c10, `next-s3` 5d2ec7ff85; D-12, E-457) | §12.2 |
| the standard libraries as owners | Open | §12.1 |
| scopes: `@trait_module` and its options `facts`, `bounded`, `no_pirates` | Implemented (TraitWorld bb78d02, W-111), with T-127 | §13 |
| concreteness and fully typed mode | Implemented (TraitWorld 7adcc94, `unified` 5f2373b2d5; W-114; the report as the build's check: TraitWorld 78a78af, `unified` 381cc8b953, W-142), with T-100, T-101, T-109; fully typed in a session listed apart: Planned (D-10, T-122) | §14 |
| printing | Implemented | §15 |
| compiling ahead, `verify_main` | Implemented (TraitWorld 05991fc, `unified` 5f2373b2d5, e81cd49a67; W-114, W-135; the check before a build: TraitWorld 78a78af, W-142), with T-108, T-109 | §16 |
| named implementations | Planned (deferred) | §17 |

### §19 Deviations

- **The sentence above the table as it stood:** The library on the unified build is TraitWorld `unified` (its head: [state.md §6.1](../../state.md#today)); the lowering's deviations are [lowering.md's](../../reference/lowering.md#15-deviations), the type system's and dispatch's [compiler.md's](../../reference/compiler.md#deviations). The rows below are where the library falls short of this reference's guarantees.
- **The retired rows** moved to the ledger's part `attic/writeup/record/deviations-retired-traits.part.md`: T-1 to T-95, T-97, T-98, T-102, T-103, T-106, T-107, T-110, T-111, T-113, T-114, T-120, T-121, T-123, T-124.
- **Taken from the open row T-96:** `julia-unified` (no hook); TraitWorld (the row reads: Julia (no hook); TraitWorld)
- **Taken from the open row T-99:** The hints are gated on the SciML error cases (the work plan's M8). (the row reads: The hints are gated on the SciML error cases.)
- **Taken from the open row T-99:** The SciML cases run on the port (E-363) and reach no hint (the row reads: The SciML cases run on the port and reach no hint)
- **Taken from the open row T-99:** TraitWorld `test/hints.jl`; `experiments/implementation/w136/sciml/` | (the row reads: TraitWorld `test/hints.jl` |)
- **Taken from the open row T-100:** | `julia-unified` `Compiler/src/facts.jl` (the row reads: | Julia's `Compiler/src/facts.jl`)
- **Taken from the open row T-104:** | `Compiler/src/optimize.jl`, `base/experimental.jl`; [the review](../../../attic/writeup/reviews/2026-11-07-implementation-day.md) M7 | (the row reads: | Julia's `Compiler/src/optimize.jl`, `base/experimental.jl` |)
- **Taken from the open row T-109:** The verdicts agree on 17 of 18 programs (E-369). What differs: (the row reads: The check and the build can give different verdicts. What differs:)
- **Taken from the open row T-109:** (the check reports the call, the build builds: `bb_invokelatest`; the closed rule (the row reads: (the check reports the call, the build builds; the closed rule)
- **Taken from the open row T-109:** [open issue 184](../../open-issues.md#2-design) (the row reads: [open issue 184](../../open-issues.md#4-design))
- **Taken from the open row T-109:** `src/buildbase.jl`; `experiments/implementation/w142/` (`agree.sh`, the apps `bb_*`); [open issue 181](../../open-issues.md#2-design) | (the row reads: `src/buildbase.jl`; [open issue 181](../../open-issues.md#4-design) |)
- **Taken from the open row T-112:** and refused (TraitWorld `s3` 9e0e3f4). (the row reads: and refused.)
- **Taken from the open row T-125:** `@erasing` is kept as the definition itself, for code written for the prototype. (the row reads: `@erasing` is kept as the definition itself.)
- **Taken from the open row T-126:** The library's exported `compiled_for` is still Julia's cast (the row reads: The library's exported `compiled_for` is Julia's cast)
- **Taken from the open row T-127:** The library still offers the attribute's surface, beside the kept forms: (the row reads: The library offers the attribute's surface, beside the kept forms:)
- **Taken from the open row T-128:** Converted: TraitDifferentialEquations' front end and callbacks (813808a), NetworkDynamics' kernel (946c0dc). (the row reads: Converted: TraitDifferentialEquations' front end and callbacks, NetworkDynamics' kernel.)
- **Taken from the open row T-128:** | the demonstrators' `-unified` trees, `forks`; stage 4 of [the plan](../../plans/2026-11-15-next-iteration.md) (W-156) | (the row reads: | the demonstrators' sources named in the row: TraitTables, TraitCSV, the forks' Tables, TraitMakie, TraitReport, TraitDifferentialEquations |)
- **Taken from the open row T-129:**  ([open issue 115](../../../attic/writeup/record/issues-closed.md), closed by rule) (the row reads: nothing in its place)
- **Taken from the open row T-129:** (`_LOAD_MEMBERSHIPS`; E-353, E-382: GT-2) (the row reads: (`_LOAD_MEMBERSHIPS`; [GT-2](../../goals.md#3-tensions-between-the-goals)))
- **Taken from the open row T-156:** since a method matches the call's types (E-500). (the row reads: since a method matches the call's types.)
