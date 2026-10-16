# Session 22 (2026-10-16): other languages, the framing of bounds, error messages

## Other languages
`writeup/other-languages.md`: four research agents (C++, Rust, Swift, Mojo) read
primary sources; the write-up compares by decision (conformance, definition
checking, layering, ownership, overlap, where compiled code lives, dynamic
positions, complexity) and ends with twelve predictions for our design.
Strongest findings: our layering rule is word for word the C++0x rule that
helped kill definition checking (objections: gradual adoption, scaffolding;
our answers: wrappers and calls upward, outward doors); Swift's ABI lead
says Swift should have had owner-only conformances (our rule 3); C++ export
failed because cached instantiations' meaning depended on context, which
rule 4 removes; every other language with dynamic positions has a storable
dynamic value, we do not.

## Framing (the user's correction)
"A Julia type carries contract and representation in one" was wrong: a
concrete type is data, behaviour lives in methods anywhere. The user's
framing, now in the note (rev 1117): a trait bound is an abstract type that
guarantees the value becomes concrete, and because the bound determines how,
the signature does not have to carry the concrete type.

## Error messages
`poc/errors/`, findings §17. Three ingredients: failure detected deep (no
stated requirements), the path printed, every step at full concrete type
(because concreteness below forces the concrete type into every signature
above). SciML: up to 89.6 kB per message, one line 33,673 characters, the
integrator's type 3,553 characters; SciML writes guidance messages by hand
(NullParameters, tuple states, autodiff Jacobian). Concepts move detection
to the call but GCC's explanation is no shorter (29 vs 28 lines) and types
print in full. Bounds: conformance and library build checks move detection
earlier; printing by bound and representation shortens the rest; user-code
bugs (all three SciML cases) are still found at run time.

## Makie (the user's intuition)
Attribute, Recipe and Observable traits, so users define their own. Answered
in chat: fits rule 3; the attribute variety becomes conformances; the product
across attributes is avoided only if each compute edge is its own worker;
storing user observables and attributes in a scene needs a storable dynamic
value (findings §16.6.1) or bound-typed struct fields (§17.5.2).

## Stored values (the user: "Go ahead and design these two")
`writeup/proposal-stored-values.md`, revision 2. Revision 1 was reviewed by
the fable-critic agent on Opus (Fable's limit reached), with experiments.
Main corrections: stored projections are snapshots, now defined as
convert-at-store with the user's object rooted for sharing views (a freed
`unsafe_wrap` buffer was read otherwise); `Dynamic{X}` by dispatch on a boxed
trait object (22–78 ns, no pointers: pointer tables broke under world age,
serialization and racing writes); the integrator's 3,553 characters contain
no user type (findings §17.4 corrected); solvers are a stated limitation,
with user models as trait-world conformances as the route. Decisions D1–D4
open for the user.

## Next
- Note: say explicitly that wrappers/calls upward and outward doors answer
  the C++0x objections; present rule 4's early binding as deliberate.
- Design a storable dynamic value and bound-typed fields (both needed by the
  Makie traits).
- Check overlap when a generic implementation is added after a specific one.
