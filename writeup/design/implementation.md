# The implementation in detail (retired)

This document was retired on 2026-10-19: its content moved into the [references](../reference/README.md), which are the source of truth, and into the rationale. The headings below are kept so that links to them still land; each says where its content is now. The full text as it was: [`attic/writeup/design-2026-10-19/implementation.md`](../../attic/writeup/design-2026-10-19/implementation.md).

## 1. Terms

The [glossary](../glossary.md), with links to the precise definitions: [facts: Terms](../reference/facts.md#terms), the traits reference.

## 2. The problem

[The argument in detail §2](argument.md#2-the-problem).

## 3. The argument in four steps

[The argument in detail §3](argument.md#3-the-argument-in-four-steps).

### 3.1 Step 1: fully typed code is already invalidated only by stakeholders and pirates

[The argument in detail §3.1](argument.md#31-step-1-fully-typed-code-is-already-invalidated-only-by-stakeholders-and-pirates).

### 3.2 Step 2: outlaw pirates, and fully typed code is always valid and can be cached

[The argument in detail §3.2](argument.md#32-step-2-outlaw-pirates-and-fully-typed-code-is-always-valid-and-can-be-cached).

### 3.3 Step 3: the facts rule extends the guarantee to all code, at a cost where code is not fully typed

[The argument in detail §3.3](argument.md#33-step-3-the-facts-rule-extends-the-guarantee-to-all-code-at-a-cost-where-code-is-not-fully-typed).

### 3.4 Step 4: traits say what code needs, which makes the facts rule cheap, and can enforce concreteness

[The argument in detail §3.4](argument.md#34-step-4-traits-say-what-code-needs-which-makes-the-facts-rule-cheap-and-can-enforce-concreteness).

### 3.5 The default: following pirates (rule P), and what it gives up

[The argument in detail §3.5](argument.md#35-the-default-following-pirates-rule-p-and-what-it-gives-up); the tiers precisely: [facts: two tiers](../reference/facts.md#two-tiers).

### 3.6 How the two goals interact

[The argument in detail §3.6](argument.md#36-how-the-two-goals-interact).

## 4. Traits: saying what code needs

The [traits reference](../reference/traits.md) (the language) and the [lowering reference](../reference/lowering.md) (how it is built).

### 4.1 Traits and implementations

[traits §5](../reference/traits.md#5-implementations).

### 4.2 Compiled for what the bound can see

[traits §4](../reference/traits.md#4-keys-what-code-is-compiled-for); [lowering §5](../reference/lowering.md#5-keys-and-views), [lowering §6](../reference/lowering.md#6-trait-objects-layout-fields-writes).

### 4.3 Concreteness, opt-in per trait

[traits §3.7](../reference/traits.md#37-concreteness).

### 4.4 Overrides belong to the implementation

[traits §3.2](../reference/traits.md#32-defaults); [lowering §4.9](../reference/lowering.md#49-overrides-and-redeclaration).

### 4.5 `Dynamic{X}`: a value of abstract type `X`

[traits §10](../reference/traits.md#10-dynamicx-values-of-any-conforming-type); [lowering §13](../reference/lowering.md#13-dynamicx).

### 4.6 Functions as arguments: `Callable`, two modes

[traits §9](../reference/traits.md#9-callable-functions-at-a-declared-signature); [lowering §12](../reference/lowering.md#12-callable-and-dynamicfn); [compiler §3.1](../reference/compiler.md#31-the-cfunction-calling-convention-caller_world).

### 4.7 The rest of the trait language

The [traits reference](../reference/traits.md).

### 4.8 AOT follows from declared targets

[traits §15](../reference/traits.md#15-compiling-ahead); [lowering §15](../reference/lowering.md#15-compiling-ahead-workloads-closed-builds).

### 4.9 Entries: typed callers, untyped callers, types compiled ahead

[lowering §9](../reference/lowering.md#9-callers-typed-untyped-compiled-ahead).

## 5. The three rules

Rules 1 and 2: the [facts mode reference](../reference/facts.md). Rule 3, the boundary: [traits §6](../reference/traits.md#6-bounded-functions). Who may implement: [traits §12](../reference/traits.md#12-who-may-implement-pirates-strict-mode).

## 6. What Julia provides

The [compiler reference](../reference/compiler.md); the inventory with commits: [Changes to Julia](julia-changes.md).

## 7. The decisions in force

The design is stated in the references. The decision log, with origins and the user's words, is in the record for agents: [`record/decisions.md`](../record/decisions.md).

## 8. What the evidence shows, and what it does not

[Evidence: the summary](evidence.md#summary-what-the-evidence-shows-and-what-it-does-not).

## 9. The software: today, the target, the order of work

[State of the prototype §6](../state.md#6-the-software-today-the-target-the-order-of-work).

### 9.1 Today (2026-10-19)

[State §6.1](../state.md#61-today-2026-10-19).

### 9.2 The target

[State §6.2](../state.md#62-the-target).

### 9.3 The order of work

[State §6.3](../state.md#63-the-order-of-work).
