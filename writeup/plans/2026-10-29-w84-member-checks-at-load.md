# W-84: a family member fixed while an image is built, not checked again at its load

Status: **done** (2026-10-29; adopted the same day, mine; W-84). Not normative. Built in TraitWorld ca92f22; measured in E-231 (the registry has the numbers): the SciML load 1.18 → 0.57 s, the forks' import 1.42 → 1.21 s.

## 1. What happens today

- A caller that knows a family member's type folds the member's builder (`Compiler.fold_call(_member_fold, reg, X, U)`, [lowering §4.6](../reference/lowering.md#46-families)). Inference fixes the member then: the member check, the builder, the registry entry, the override index (`_member_fix!`).
- When a package image keeps such a caller, its fold record is evaluated again at load (`fold_holds` → `_member_fold(AtLoad(), reg, X, U)` → `_member_fold_at_load`; [compiler §4.4](../reference/compiler.md#44-compilerfold_call)).
- The registry belongs to the family's declaring package, usually another image. So at load the member is not in it, and `_member_fix!` runs again in full.
- Cost, nearly all compilation:
  - the SciML session (E-230, TraitWorld c39fedc): 14 members, 744 ms of a 1.17 s load; the check 544 ms, the builder 59, the index 17; `IntegratorView` for `ParamIntegrator` alone 491 ms;
  - the forks (E-225, after a515e3a's `@nospecialize`): 27 members, 384 ms of a 1.40 s import.

## 2. What a load must re-establish

The fold's value is the member's builder. At load, the session must hold the member fixed with that builder: the registry entry, the member marked checked, its default-served operations in the override index. Only the check's verdict can differ from the build's, and only through the loading session's methods.

What the member check reads (`_member_problems`):
- the operations' methods at the member, and their inferred results;
- the conformance methods that apply: the family's implementation, the supertraits' implementations, the parameters' bounds;
- the declared fields and the concreteness declarations: types and declarations of the packages the image depends on.

What can differ between the image's build and a session that loads it:
- The image's dependencies are the same, by build id. Their types, traits, implementations and methods are the same.
- Other packages may have loaded before it. They can:
  - add a method that dispatch selects for an operation at the member (a pirate: the member's type, the operation and the declared argument types belong to the dependencies; at an abstract declared argument only the stakeholders' methods count, [traits §4.7](../reference/traits.md#47-families));
  - add an implementation. An added witness never turns a passing check into a failing one. Implementations of a dependency's trait for a dependency's type are made only by the dependencies (traits §10).
  - widen an inferred result deeper inside an operation's body, at an abstract call site, with a method of their own types.

## 3. The options

1. **Check again at load** (today). Sound against all three; costs what §1 says.
2. **A Julia change:** `AtLoad` names the image (or carries the fold's recorded value), so TraitWorld finds a record in the image that holds the fold. A change to `julia-1.13`.
3. **A record kept as a method of the image that made the fix** (chosen). While a package image is built, each member fixed there (the check passed, no warning) is written into that package's module, just before the image is written, as a method:
   `TraitWorld._member_record(::Type{X}, ::Type{U}, ::Val{image key}) = (builder, signatures, the methods dispatch selects there, the index records)`.
   - The signatures: for each operation of `X` at each declared arity, the declared argument types; for each trait in `X`'s closure, the conformance at the member. They follow from declarations of the image's dependencies, so they are kept, not computed again at load.
   - At load, `_member_fold_at_load` looks the record up by dispatch: the image's methods are in the method table before its code is validated. No Julia change.
   - The record holds while dispatch selects the same methods now. Then the member is fixed from it: the registry entry, the checked mark, the index records. No check, no builder. Otherwise the full path runs, as today.
4. **Keep the check's inferred code in the image,** so the check at load is cheap and Julia validates its results transitively. Plain code reached only dynamically is not kept (`queue_external_cis`): a Julia change, and the builder and index costs remain.

## 4. The choice, and its soundness

Option 3, by the rules: principled (an image's facts are methods, as a declaration's builder is, `_declared_builder`), no Julia change, no added mechanism beyond a record and its lookup.

The record holds exactly when the methods that serve the member are the same as when the check passed. This covers the first two cases of §2: a pirate that changes an operation's method, and the implementation that applies. It is the standard of E-203's checked worker records.

**What it does not cover:** a package outside the image's dependencies, loaded before it, that widens an inferred result deeper inside an operation's body. Today's check at load would refuse the member then; the record accepts it. The same holds in a session where that package loads after the member's first use: a member is never checked again after it is fixed (traits §4.7). So the record gives a state that a legitimate load order also gives. A single type's declaration kept in an image is not checked again at load at all. A full answer is option 4 (candidate open issue).

## 5. Expected saving

The whole of `_member_fold_at_load` for members with a record that holds: the SciML load about 0.7 s, the forks' import about 0.35 s, less the records' lookups (a dispatch lookup per method recorded). Part of the check's compilation may move to the first calls (the operations' inference at the member).

## 6. Tests (TraitWorld `test/`)

- A member folded while a package image is built has a record in that image; a session that loads it fixes the member from the record: no member check (the load report's counts).
- A package loaded before it that adds a method for one of the member's operations (a pirate): the record does not hold, the member is checked again, and its new verdict stands (refused, the fold does not hold).
- The member's builder from the record equals the builder the check would find.

## 7. As built (2026-10-29)

- TraitWorld ca92f22: `_note_image_member!` while the image is built, `_write_image_members` as an `atexit` hook of the build (it runs before Julia writes the image), `_member_from_record!` at load; the tests in `test/member_records.jl`; lowering §4.6 and its deviation L-45, traits §4.7.
- Tried and not kept, as no faster overall (E-231's harness, one round each): one record method per image, read into a session table, with TraitWorld's own workload running the load path so its code is in TraitWorld's image. The members' time at load fell to 3–4 ms, but the session and the load stayed within 0.04 s of the per-member records.
- A member fixed while Julia writes the image (code compiled at output, after the `atexit` hooks) has no record and is checked at load as before: 1 of the forks' 27 members.
- The records' remaining cost (SciML 103 ms): the first lookup's compilation (about 70 ms, code compiled by facts at its first call) and about 2 ms per member (each record method compiled at its first call).
