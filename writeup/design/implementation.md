# The implementation in detail (retired)

This document was retired on 2026-10-19: its content moved into the [references](../reference/README.md), which are the source of truth, and into the rationale. The headings below are kept so that links to them still land; each says where its content is now. The full text as it was: [`attic/writeup/design-2026-10-19/implementation.md`](../../attic/writeup/design-2026-10-19/implementation.md).

## 1. Terms

The [glossary](../glossary.md), with links to the precise definitions: [facts: Terms](../../attic/writeup/reference/facts.md#terms), the traits reference.

## 2. The problem

[The rationale §1](../design.md#1-the-problem).

## 3. The argument in four steps

[The rationale §2](../design.md#2-the-argument-in-four-steps).

### 3.1 Step 1: fully typed code is already invalidated only by stakeholders and pirates

[The rationale §2.1](../design.md#21-step-1-fully-typed-code-is-already-invalidated-only-by-stakeholders-and-pirates).

### 3.2 Step 2: outlaw pirates, and fully typed code is always valid and can be cached

[The rationale §2.2](../design.md#22-step-2-refuse-the-pirates-that-would-win-and-fully-typed-code-is-never-invalidated).

### 3.3 Step 3: the facts rule extends the guarantee to all code, at a cost where code is not fully typed

[The rationale §2.3](../design.md#23-step-3-the-facts-rule-extends-the-guarantee-to-code-that-is-not-fully-typed).

### 3.4 Step 4: traits say what code needs, which makes the facts rule cheap, and can enforce concreteness

[The rationale §2.4](../design.md#24-step-4-traits-say-what-code-needs-which-makes-the-facts-rule-cheap).

### 3.5 The default: following pirates (rule P), and what it gives up

[The rationale §2.5](../design.md#25-the-default-following-pirates-and-what-it-gives-up); the tiers precisely: [facts: two tiers](../../attic/writeup/reference/facts.md#two-tiers).

### 3.6 How the two goals interact

[The rationale §2.6](../design.md#26-how-the-two-parts-depend-on-each-other).

## 4. Traits: saying what code needs

The [traits reference](../reference/traits.md) (the language) and the [lowering reference](../reference/lowering.md) (how it is built).

### 4.1 Traits and implementations

[traits §4](../../attic/writeup/reference/traits.md#4-implementations).

### 4.2 Compiled for what the bound can see

[traits §6.7](../../attic/writeup/reference/traits.md#67-what-compiled-code-is-compiled-for); [lowering §5](../../attic/writeup/reference/lowering.md#5-keys-and-views), [lowering §6](../../attic/writeup/reference/lowering.md#6-trait-objects-layout-fields-writes).

### 4.3 Concreteness, opt-in per trait

[traits §11](../../attic/writeup/reference/traits.md#11-concreteness-and-fully-typed-mode).

### 4.4 Overrides belong to the implementation

[traits §3.2](../../attic/writeup/reference/traits.md#32-defaults); [lowering §4.8](../../attic/writeup/reference/lowering.md#48-overrides-and-redeclaration).

### 4.5 `Dynamic{X}`: a value of abstract type `X`

[traits §7](../../attic/writeup/reference/traits.md#7-kept-values-dynamicx-compiledx-keptx); [lowering §13](../../attic/writeup/reference/lowering.md#13-dynamicx).

### 4.6 Functions as arguments: `Callable`, two modes

[traits §5.8](../../attic/writeup/reference/traits.md#58-callable-functions-at-a-declared-signature); [lowering §12](../../attic/writeup/reference/lowering.md#12-callable-and-dynamiccallable); [compiler §3.1](../../attic/writeup/reference/compiler.md#31-the-cfunction-calling-convention-caller_world).

### 4.7 The rest of the trait language

The [traits reference](../reference/traits.md).

### 4.8 AOT follows from declared targets

[traits §13](../../attic/writeup/reference/traits.md#13-compiling-ahead); [lowering §15](../../attic/writeup/reference/lowering.md#15-compiling-ahead-workloads-closed-builds).

### 4.9 Entries: typed callers, untyped callers, types compiled ahead

[lowering §9](../../attic/writeup/reference/lowering.md#9-callers-typed-untyped-compiled-ahead).

## 5. The three rules

Rules 1 and 2: the [facts mode reference](../reference/facts.md). Rule 3, the boundary: [traits §5](../../attic/writeup/reference/traits.md#5-bounded-functions). Who may implement: [traits §10](../../attic/writeup/reference/traits.md#10-who-may-implement-pirates-strict-mode).

## 6. What Julia provides

The [compiler reference](../reference/compiler.md); the inventory with commits: [Changes to Julia](julia-changes.md).

## 7. The decisions in force

The design is stated in the references. The decision log, with origins and the user's words, is in the record for agents: [`record/decisions.md`](../record/decisions.md).

## 8. What the evidence shows, and what it does not

[Evidence: the summary](evidence.md#summary-what-the-evidence-shows-and-what-it-does-not).

## 9. The software: today, the target, the order of work

[State of the prototype §6](../state.md#6-the-software-today-the-target-the-order-of-work).

### 9.1 Today (2026-10-19)

[State §6.1](../state.md#today).

### 9.2 The target

[State §6.2](../state.md#62-the-target).

### 9.3 The order of work

[State §6.3](../state.md#63-the-order-of-work).
