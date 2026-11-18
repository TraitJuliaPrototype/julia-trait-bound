# Retired terms

The glossary's section of terms of earlier iterations, moved here by the documentation clean-up (W-162). A document of the attic or an early session note uses these terms; the table says what each is called now, or that it is gone.

These appear in documents before 2026-11-06, in the record ([`record/INDEX.md`](../../writeup/record/INDEX.md)) and in [the earlier references](reference/README.md). The options behind them are in [`design/alternatives.md`](../../writeup/design/alternatives.md).

| Old term | Now | Changed |
|---|---|---|
| open method, `@open` | [unbounded](../../writeup/glossary.md#bounded-and-unbounded) method, `@unbounded` | 2026-11-12 |
| fully bounded; the classification (of a method at a trait) | [bounded](../../writeup/glossary.md#bounded-and-unbounded): its instance at the box | 2026-11-15 |
| implementation, conformance (the noun) | [membership](../../writeup/glossary.md#membership-and-entry), declared by `@implement` | 2026-11-06 (conformance: 2026-10-19) |
| conforms to, `conforms(T, X)` | `T <: X`: a [member](../../writeup/glossary.md#membership-and-entry) | 2026-11-06 |
| generic implementation | [pattern member](../../writeup/glossary.md#pattern-member) | 2026-11-06 |
| bound, bounded function | a [method at a trait](../../writeup/glossary.md#method-at-a-trait); bounded is [a property of it](../../writeup/glossary.md#bounded-and-unbounded) | 2026-11-06 |
| receiver type, receiver | part of the [key](../../writeup/glossary.md#key) | 2026-11-06 |
| trait object, view, held view | the member's own value, passed unwrapped ([traits §3.5](reference/traits.md#35-values)) | 2026-11-06 |
| entry and worker (of a bounded function) | gone: one method, compiled per type, per key or once. "Entry" now means a [membership entry](../../writeup/glossary.md#membership-and-entry) | 2026-11-06 |
| kept value: `Compiled{X}` | a member's own value, or a [kept form](../../writeup/glossary.md#kept-form) | 2026-11-06 |
| trait cast, of the trait world, first seen through a trait | the [kept forms](../../writeup/glossary.md#kept-form): the value's type decides | 2026-11-06 |
| attribute, `Compiled` and `Dynamic` (of an argument at a call); cast; `keep`; `Kept{X}`; the fallback by scope, `first_seen`, the option `dynamic` | the [kept forms](../../writeup/glossary.md#kept-form): the [box](../../writeup/glossary.md#dynamicx) and the [wrapper](../../writeup/glossary.md#wrapper-compiled_forx); a trait [erasing by default](../../writeup/glossary.md#erasing-by-default-and-the-forwarder) | 2026-11-15 |
| bundle, tuple of traits | an [intersection](../../writeup/glossary.md#intersection-allx-y), named by a `const` | 2026-11-06 |
| associated type | a trait's [parameter](../../writeup/glossary.md#parameters-and-input-parameters) | 2026-11-06 |
| call-site split | the [split](../../writeup/glossary.md#split) | 2026-11-06 |
| world-checked call-site cache | [compiler §8](reference/compiler.md#8-world-checked-caches-at-dynamic-boundaries) | 2026-11-06 |
| mode (inference mode), facts mode and the setting `all` | [policy](../../writeup/glossary.md#policy-facts-and-plain), [setting](../../writeup/glossary.md#setting) | 2026-11-06 |
| boundary (rule 3 of the earlier design) | gone; a [boundary method](../../writeup/glossary.md#boundary-method) is a method flag | 2026-11-06 |
| identical or error | [G1](../../writeup/glossary.md#g1-identical-or-error) | 2026-11-06 |
| definition checking and archetype | [definition checking](../../writeup/glossary.md#definition-checking) | 2026-11-06 |
| results like the input (`Like`) | [`like` and `withfields`](../../writeup/glossary.md#like-and-withfields) | 2026-11-06 |
| item position, plain value, sibling | gone with the earlier lowering | 2026-11-06 |
| `@default_with_dynamic_self`, `@default_compiled_for_self`; `@default_compiled` | `@default_dynamic`: a trait [erasing by default](../../writeup/glossary.md#erasing-by-default-and-the-forwarder) | 2026-11-06; 2026-11-15 |
| representation, projection | [key](../../writeup/glossary.md#key) | session 22 |
| layering, trait wrappers, calls upward, sealing | the facts rule: trait code may call any Julia code | sessions 23–29 |

The earlier headings, so that links to them still land:

### Implementation
See [membership](../../writeup/glossary.md#membership-and-entry).
### Conforms to
See [membership](../../writeup/glossary.md#membership-and-entry).
### Generic implementation
See [pattern member](../../writeup/glossary.md#pattern-member).
### Bound and bounded function
See [method at a trait](../../writeup/glossary.md#method-at-a-trait).
### Receiver type
See [key](../../writeup/glossary.md#key).
### Trait object
See the table above.
### View and held view
See the table above.
### Entry and worker
See the table above.
### Kept value: `Dynamic{X}`, `Compiled{X}`, `Kept{X}`
See [kept form](../../writeup/glossary.md#kept-form).
### Trait cast
See [kept form](../../writeup/glossary.md#kept-form).
### Of the trait world
See [kept form](../../writeup/glossary.md#kept-form).
### `Compiled` and `Dynamic`
See [kept form](../../writeup/glossary.md#kept-form): the box and the wrapper.
### Cast
See [wrapper](../../writeup/glossary.md#wrapper-compiled_forx).
### `keep`
See [erasing by default](../../writeup/glossary.md#erasing-by-default-and-the-forwarder): a method's argument at such a trait is already a kept form.
### Call-site split
See [split](../../writeup/glossary.md#split).
### World-checked call-site cache
See [compiler §8](reference/compiler.md#8-world-checked-caches-at-dynamic-boundaries).
### Supertrait, bundle and tuple of traits
See [supertrait](../../writeup/glossary.md#supertrait) and [intersection](../../writeup/glossary.md#intersection-allx-y).
### Associated type
See [parameters](../../writeup/glossary.md#parameters-and-input-parameters).
### Facts mode and the setting `all`
See [policy](../../writeup/glossary.md#policy-facts-and-plain) and [setting](../../writeup/glossary.md#setting).
### Mode
See [policy](../../writeup/glossary.md#policy-facts-and-plain).
### Boundary and boundary method
See [boundary method](../../writeup/glossary.md#boundary-method).
### Identical or error
See [G1](../../writeup/glossary.md#g1-identical-or-error).
### Definition checking and archetype
See [definition checking](../../writeup/glossary.md#definition-checking).
### Results like the input: `Self`, `Like`, `withfields`
See [`Self`](../../writeup/glossary.md#self) and [`like` and `withfields`](../../writeup/glossary.md#like-and-withfields).
### Fully typed, fully typed mode, the certificate
See [fully typed](../../writeup/glossary.md#fully-typed-and-fully-typed-mode).
