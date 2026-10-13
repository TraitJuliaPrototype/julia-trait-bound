# 2026-10-13 — Session 14: layering, seven rules, working with existing Julia

Design work only, in the note ("Traits for better Julia", Claude Doc, rev 85 to
101). The prototype (TraitRegions) is unchanged and still uses `@region` and
`@seal`.

## Decisions

- **Trait modules replace region blocks** in the note: `@trait_module module M … end`,
  trait-bounded arguments `t::ColTable` in any position and number.
- **Layering is the core principle:** "ordinary code may use the trait world;
  the trait world uses only itself". The user: "it's essentially this that
  enables everything downstream". The note now opens Core concepts with it,
  with a diagram.
- **Seven rules** (a proposal at rev 85, adopted at rev 92):
  1. layering;
  2. projection per trait, at the boundary;
  3. bounds propagate to the boundary;
  4. several bounds, several views;
  5. one ownership rule;
  6. what a call sees;
  7. where compiled code lives.
- **One representation per type rejected** as too restrictive: projections
  stay per (trait, type).
- **"Seal" retired** for "projection": `@implement ColTable T project(t) = …`.
  - A type that is its own representation: `@implement ColTable{T}`.
  - Own operations on a shared representation: `@implement ColTable T dynamic begin … end`.
  - Not `derive_trait`: "derive" suggests code generated from a type's
    structure, which is unsound here.
- **New note section "Working with existing Julia":**
  - **Traits over existing functions.** Capability traits such as `Indexable`
    over `Base.length` and `getindex`. Conformance is declared for families
    through Base's abstract types, never derived from the methods that exist:
    Base's fallbacks exist and throw, types conform by accident, and whether
    a call infers changes with loads.
  - **Defaults and generic implementations.** Generic implementations cover a
    family, or every representation of other traits. Specific beats generic,
    and an overlap is checked by the later, dependent package.
  - **Several traits, one projection:** `@implement (ColTable, RowTable) T …`,
    plus bundle traits.
  - **Dispatch: types first, then traits.** A trait bound ranks above `Any`
    and below every type. Unrelated bounds on one position need a resolving
    method, checked when the function is defined.
  - **`Callable{A, S}`** (the user's idea) for function arguments from
    ordinary code. Conformance is structural, and each call is checked.
    Whether a function from above is erased (a pointer, one worker per
    signature) or specialized (`@specialize`, compiled per function type as
    ordinary code in the caller's image) is the library's choice, per
    argument. Functions from the trait world are always specialized. A
    function used at two signatures carries two bounds.
- **Rule refinements:**
  - Rule 1 admits values handed down: trait objects and `Callable`s.
  - Rule 4: a projection declares whether it shares or copies the user's
    data, and mutating traits accept only sharing projections.
  - Rule 5 is checked per applicable signature, which closes the `Union`
    loophole. A delegate is an extension triggered only by packages its
    methods mention.

## Review

A Fable agent reviewed the user's five observations and the rules. Its main
points were adopted:
- `@implement` with a projection rather than "derive";
- declared conformance instead of derivation;
- the resolving-method rule for dispatch;
- joint projections;
- the `Union` loophole in rule 5;
- delegation scoped to its triggers;
- copying projections;
- function arguments as the largest gap.

## Next

A fresh proof of concept of the new design, including Base capability traits
(plan in `writeup/poc2-plan.md`).
