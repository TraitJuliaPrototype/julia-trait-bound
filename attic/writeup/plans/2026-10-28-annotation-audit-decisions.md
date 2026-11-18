Status: **proposal** (2026-10-28, night; mine, by the user's rules). Not normative.

# Open issues 98–106: what to decide, what to build

The annotation audit ([review](../reviews/2026-10-28-ports-annotation-workarounds.md)) raised open issues 98–108 ([open issues](../open-issues.md) §2, §3). This note applies the user's rules to each:
- "For other open issues/design details that were flagged: make decisions by the principles we had before. Only get back to me now with genuine well articulated trade offs. Otherwise go for the decision that allows a more principled solution."
- "Making the trait/type system more expressive is a principled change."

Each item gets one of: **build** (clear, small, done tonight), **mine, flagged** (decided by the rules, Planned in the reference when written, for the review session W-71), **for the user** (a genuine trade-off).

## Build

- **100, declared results that do not reach the caller.** A bounded function's declared result already reaches plain callers when it is a plain type (TraitWorld 38a3abf, asserted at the entry since 254bcd8). The same holds for a kept-form result, `Dynamic{X}`: a concrete type, which the worker returns as declared, and never a result like the input. So `tocolumn(::Vector{Int})` infers `Dynamic{Column}`, and the four sites that assert it go. Traits §7.6 then says "declare the result", not "assert it".

## Mine, flagged

- **98, opening a stored `Dynamic` at the callee.** Today every caller of a kernel writes `compiled_for`; a caller that forgets pays about 2× (E-214). A bound that opens its value (`c::Opened{Column}`: one dispatch per call, then code per key) lets the function that knows its cost model say it. More expressive; values keep their attribute everywhere else. Flagged: it is a new attribute; the ports' 26 call sites are the evidence.
- **102, a function kept before its signature is known.** `ByRow(f)` and `DiscreteCallback(cond, affect!)` receive functions whose argument types the first bound fixes. A kept function without a signature (`Dynamic{Callable}`), entered at a signature at its first bound, says so. More expressive.
- **104, a struct parameter's `Compiled` value read back.** A value read from a field typed by a bounded parameter keeps the attribute the parameter records. It makes traits §7.4 and §6.5 agree.
- **105, changing a function while keeping its attribute.** A public `rewrap(g, f)`: `g` with `f`'s form and attribute. It replaces TDE's reads of TraitWorld's internals.
- **106, operation types naming another argument's type variable.** `where` variables on an operation's declaration, fixed by its arguments. More expressive; low priority (once per solve).

## For the user

- **101, the member check against the call's assertion.** Today a family member is refused unless inference proves each operation's result type. The proposal accepts a result that infers wider but not disjoint, since each call on a trait object asserts the declared type anyway. The trade-off is real: the member check's proof is a guarantee at declaration time (an error before any call), the assertion is one at run time (an error at the first wrong value). The ports' cases (`length(c)::Int`, `c[i]::eltype(c)` for DataFrames' `RepeatedVector`) would lose two assertions; a user's type with a result that is sometimes wrong would fail later.

## Needs a measurement first

- **103, kept-value constructors compiled per value type.** Making a `Dynamic` value from plain code compiles the constructor once per value type (per closure). Unspecialized constructors compile once, but a constructor in a hot loop (MakieCompat makes a `Dynamic{Positions}` per triangle) may pay a dispatch per value. Measure both before deciding.
