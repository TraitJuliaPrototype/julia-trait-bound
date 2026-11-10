# Plan: the ambiguity report covers a method at a member's declared supertype (compiler C-78)

Status: **proposal** (2026-11-10, night), for a Fable review before it is built. The user (2026-11-09): "For tonight, Focus on fixing unsound rules and deviations. For each come up with a plan, have a Fable agent review it, and act on the review."

## 1. The deviation

- [Compiler §5.4](../reference/compiler.md#54-the-ambiguity-report-at-a-membership): at a membership, for each function with a method at the new set and a method at another set the member is in, **or at one of the member's declared supertypes**, with no method more specific for the member, a warning names the pair and the joint method. Strict mode makes it an error (E-343).
- C-78: the report covers methods at sets only. `struct S <: AbstractString` joining a set `X` gets no warning for `f(::X)` against `f(::AbstractString)`, and strict mode accepts the membership; the next call `f(S())` raises the ambiguity.
- Since W-131 (E-345) a member by its definition (`struct S <: X`) has an entry, so the second trait's `@implement` meets a pair of sets. In the other order (`struct S <: X; @implement Y S` before `@implement X S`) the `Y` membership is not reported, since `X` is a declared supertype there, not an entry yet; under strict mode the `X` declaration is then refused but `S <: X` holds by the definition (W-131's review, M1). Also not covered: `struct S <: A`, a plain abstract type, joining `X`; a method at `Any` that ties with the set's method at another argument.
- The row's second half ("a call compiled before runs `f(::X)` for it where a dynamic call raises the ambiguity") no longer holds: gate `n20_unmet_lookup` (3) asserts the compiled caller agrees with dispatch on today's build. The row is narrowed to the report.

## 2. The proposal: ask each method at the new set against the method table at the member

The report today pairs methods at two sets. The principled question is narrower and complete: **which methods does the membership make applicable at the member, and is any of them ambiguous there?**

- For each method `mX` at the new set `X` (`jl_methods_at_set(X)`) and at each set `X` joins (its supersets by entries, as the walk's `membership_superset_sets`):
  - `q = sig_at_member(mX.sig, X, member)`: the method's signature with the member in place of its set (as today);
  - the matches at `q` in the entry's world, without caches (`ml_matches_i`, as E-343's search);
  - an ambiguity: a match `m` with `mX` both covering `q`'s intersection, neither more specific, and no match more specific than both that covers it (`ambiguous_at`'s rule, generalised from a pair to the matches).
- One finding per function and new set, naming `mX`, the other method's signature (a set, a declared supertype, or `Any`), and the joint signature.
- The pairs of sets become a special case of the same search: the existing pair loop is replaced by it, not kept beside it.
- A pattern member: the same at `q` with the pattern's variables (today's abstract path), with the dominance rule of today.

## 3. Cost

- Today: per pair of sets, per pair of methods of one function at both, one `ml_matches`. Proposed: per method at the new set and its supersets, one `ml_matches` at `q`. For a set with `n` methods, `n` lookups, against `n × m` pairs today; the lookups are at concrete types for a concrete member (fast paths in `ml_matches_i`), under the world counter's lock as today.
- A set with many methods (BaseTraits' `Indexable` reaches Base's `getindex`): the methods at the set are the trait's own methods, few; the lookup at `q` finds Base's methods at the member's type. A guard: the walk's caps (16 sets).

## 4. Alternatives

- **Add the declared supertypes as a third list beside the pairs:** the chain's types' methods by function, paired with the set's: covers `A` but not `Any` or a method at a union, and doubles the loops. Rejected for the general search.
- **Leave it to the call:** the call raises the ambiguity; strict mode's promise (an ambiguity at a membership is an error) does not hold. Rejected.

## 5. Gates

- `m2_ambiguity_report` and `m2_ambiguity_arity`, `m2_ambiguity_called_before`, `n20_unmet_lookup` unchanged; a new gate `m2_ambiguity_declared_super`: `struct S <: A` (plain abstract) with `f(::A)` and `f(::X)`, `@implement X S` warns once naming `f(::A)`; under strict mode refused; with `f(::All{…})`-style resolution (`f(::S)` defined first) silent; a method at `Any` that ties at another argument reported; the set-in-set suppression of `m2_ambiguity_report` holds.
- TraitWorld's suite: `declared.jl`'s strict case in the order W-131's review found (M1): `struct S <: X`, then `@implement Y S` under strict mode is refused at once, since `f(::X)` applies at `S` by the definition and ties with `f(::Y)`; the order no longer decides. `strict_membership.jl` unchanged. The battery (Base's `ambiguous` test, the acceptance cases); the ports' loads (a port whose membership the broader report warns about, or refuses under strict mode).

## 6. Records

- compiler §5.4 (the search), C-78 retired; traits §6.3; julia-changes; the decision log, mine; open issues §1 (the order rule's item closed or narrowed).
