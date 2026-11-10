# Plan: a membership loaded from an image keeps its check (W-130, lowering L-55)

Status: **proposal** (2026-11-10, night), for a Fable review before it is built. The user (2026-11-09): "For tonight, Focus on fixing unsound rules and deviations. For each come up with a plan, have a Fable agent review it, and act on the review."

## 1. The gap

- [Traits §5.10](../reference/traits.md#510-checks): a member's check holds while it is a member. A method defined after the check that would serve a checked call with a result outside the declared one, or make the operation ambiguous at the member, is refused; a method that would take a call a default or the forwarding serves is refused ([§5.11](../reference/traits.md#511-overrides-and-redeclaration)).
- Built (TraitWorld `unified` 5b3c427, E-342): the records the definition hook reads (`_FIXED_CALLS`, `_CHECKED_RESULTS`) are made where a check runs in the session: at `@implement` and at a pattern member's first use.
- Not covered ([lowering L-55](../reference/lowering.md#deviations)): a concrete membership loaded from a package's image. Its check ran while the image was built; the session has no record of it. So:
  - Revise on a tracked package: a redefinition of a serving method is not re-checked;
  - a package extension's or another package's method at the member, a pirate among them: accepted, and the call through the trait raises `TypeError` where the dynamic call returns the method's value.
- Gate `stack/recheck_packages.jl`, case 3, asserts the gap (TE's `area(::Square, ::Int) = 1` accepted where `Square`'s membership is in TA's image).

## 2. The rule (unchanged)

The membership and the contract are the record; the session's dictionaries are a cache of them. A membership in force in the session has its records, wherever it was declared.

## 3. The mechanism

**Runtime (`julia-unified`):**
- `jl_activate_memberships` appends each entry it activates (not one refused at activation, C-35's path) to a session list `jl_activated_entries` (rooted, written under the world counter's lock, replaced never mutated in place, or an array only appended to under the lock).
- `JL_DLLEXPORT size_t jl_activated_memberships_count(void)` and `JL_DLLEXPORT jl_value_t *jl_activated_memberships_since(size_t k)` (an svec of the entries from index `k`).
- An image's memberships activate after the image hook has run on its methods (`staticdata.c` 4533–4551). An image's own methods were checked against its own memberships when it was built, so the order is right for them; another image's methods meet the entry's records once it is activated.

**TraitWorld:**
- `_sync_image_records!()`: where the runtime's count exceeds the library's cursor, read the new entries and, for each with a concrete member, a live entry (`max_world == typemax`) and a set whose contract the library declared, rebuild its records. The cursor advances.
- The rebuild: `check_member(bare(X), S; stated = instance, how = How(by), defaults, results, infer = false)`. With `infer = false`, `_check_contract!` does not infer a serving method's result: the image's check passed when it was built, so a call whose result the check would infer records a `_CheckedResult`, a call a default serves a `_FixedCall`; a forwarding member's forwarders are fixed calls at `Tuple{typeof(op.f), S, Any…}` (the forwarders' own signature, `_define_fwd!`), once per operation and arity. The problems it finds are ignored (the membership is in force). No inference, so the cost per entry is method lookups.
- Called first in `_check_membership_calls` (the definition hook's first call and the image hook): one `ccall` and a comparison per method definition.
- A pattern member from an image is checked at its first use in the session and gets its records then (as now).

## 4. What it does not do

- **A method in the session before the membership loads** that breaks the image's check (a pirate loaded earlier) is not found: the rebuild does not infer. Facts §11.3 reports a pirate loaded before the code it changes; the same report here would infer each checked call at load (an option: under strict mode only).
- **The answers of the checks of pattern members** stay per session (the first half of L-55).
- **Threads:** the records' dictionaries are not locked, as now (facts §2.1's single-threaded scope).

## 5. Alternatives

- **Rebuild at the package's load callback** (`Base.package_callbacks`): runs after the whole dependency chain of a `using` has loaded (`_require_search_from_serialized`'s `newdeps` loop), so an image loaded in the same chain meets no record in the image hook. Rejected.
- **Pass the image's memberships to the image hook:** covers the image's own methods only, which its build checked already. Rejected.
- **Scan a package's own types and traits at load:** misses a membership declared by a joint owner; needs the set's entry list from Julia. Rejected for the runtime's list.
- **Keep the records in the image** (the second half of L-55's intended design): the records are the library's Julia objects keyed by functions; an image keeps them only through a global the package owns, and a later image's methods need all of them merged. The runtime's entries already are in the image.

## 6. Gates

- `stack/recheck_packages.jl`: case 3 flips (TE's method left inactive with a warning, `area(Square(1.0), 2)` keeps `1.0`); with `using TE` alone (TA loaded through the chain); a Revise-like redefinition in the session of TA's serving method at `Square` refused; a forwarding member from an image, its forwarder overwritten in the session, refused.
- TraitWorld's suite; the battery's TraitWorld and workloads; the forks' checks and TDE's suite (a port that redefines a serving method of a member from an image would now be refused).
- The cost: the hook per definition with and without images loaded (a micro-measure, not a gate).

## 7. Records

- traits §5.10's status (coverage), §5.11's; lowering L-55 (the records half retired or narrowed to the pattern members' answers), §11's "What a package image keeps"; compiler §10.1 or §9 (the activated list); julia-changes; the decision log, mine; W-130 done; open issue 168's recommendation.
