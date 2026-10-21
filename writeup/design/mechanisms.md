# The mechanisms in detail (retired)

This document was retired on 2026-10-19: its language rules moved into the [traits reference](../reference/traits.md), how they are built into the [lowering reference](../reference/lowering.md), the guarantees into the [facts mode reference](../reference/facts.md), and its measured costs into [evidence](evidence.md) and [performance](performance.md). The headings below are kept so that links to them still land. The full text as it was: [`attic/writeup/design-2026-10-19/mechanisms.md`](../../attic/writeup/design-2026-10-19/mechanisms.md).

## 1. Declaring a trait

[traits §3](../reference/traits.md#3-trait-declarations); [lowering §3](../reference/lowering.md#3-trait-declarations).

### Operations

See the parent section.

### Defaults

See the parent section.

### Fields

See the parent section.

### Associated types

See the parent section.

### Supertraits and bundles

See the parent section.

### Concreteness

See the parent section.

## 2. How a type conforms

[traits §4](../reference/traits.md#4-implementations); [lowering §4](../reference/lowering.md#4-implementations).

## 3. Generic implementations

[traits §4.8](../reference/traits.md#48-generic-implementations); [lowering §4.7](../reference/lowering.md#47-generic-implementations).

## 4. Named implementations (deferred)

[traits §15](../reference/traits.md#15-named-implementations).

## 5. Several traits on one object

[traits §4.5](../reference/traits.md#45-several-traits-at-once); [traits §5.1](../reference/traits.md#51-bounds).

## 6. Parametric user types and families

[traits §4.7](../reference/traits.md#47-families); [lowering §4.6](../reference/lowering.md#46-families).

## 7. Traits as abstract types, and dispatch

[traits §5.5](../reference/traits.md#55-dispatch-types-first-then-traits); [traits §14](../reference/traits.md#14-membership).

### Where a trait's name stands

See the parent section.

### Dispatch: types first, then traits

See the parent section.

## 8. Inside a trait module

[traits §2](../reference/traits.md#2-trait-modules).

## 9. Definition checking at archetypes

[traits §9](../reference/traits.md#9-checks-and-when-they-run); [lowering §14](../reference/lowering.md#14-checks-and-where-their-results-live).

## 10. `Callable` and its two modes

[traits §5.8](../reference/traits.md#58-callable-functions-at-a-declared-signature); [lowering §12](../reference/lowering.md#12-callable-and-dynamiccallable).

## 11. Keyword, default and variable arguments

[traits §5.7](../reference/traits.md#57-keywords-defaults-and-varargs); [lowering §10](../reference/lowering.md#10-keywords-defaults-and-varargs).

## 12. Functions that cross the boundary

[traits §5.7](../reference/traits.md#57-keywords-defaults-and-varargs), [traits §5.8](../reference/traits.md#58-callable-functions-at-a-declared-signature).

## 13. Results like the input

[traits §5.6](../reference/traits.md#56-results-declared-types-like-withfields); [lowering §11](../reference/lowering.md#11-results-like-the-input).

## 14. Types that only convert

[traits §4.10](../reference/traits.md#410-types-that-only-convert).

## 15. `Dynamic` values, as built

[traits §7](../reference/traits.md#7-kept-values-dynamicx-compiledx-keptx); [lowering §13](../reference/lowering.md#13-dynamicx).

## 16. The trait object's layout

[lowering §6](../reference/lowering.md#6-trait-objects-layout-fields-writes).

## 17. Caching per key

[traits §6.7](../reference/traits.md#67-what-compiled-code-is-compiled-for); [lowering §5](../reference/lowering.md#5-keys-and-views); [facts: package images](../reference/facts.md#package-images); the costs: [performance](performance.md).

## 18. AOT

[traits §13](../reference/traits.md#13-compiling-ahead); [lowering §15](../reference/lowering.md#15-compiling-ahead-workloads-closed-builds); [facts: trimmed binaries](../reference/facts.md#trimmed-binaries); sizes: [evidence](evidence.md).

## 19. Identical or error

[facts: G1](../reference/facts.md#g1).
