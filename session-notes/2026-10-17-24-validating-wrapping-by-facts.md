# Session 24: validating "wrapping by facts" (running notes)

The user (end of session 23): "Go ahead. Push forward without coming back to me until you have completely validated the design, or until you have proven that it can not be made to work. Call out to subagents to generate ideas if stuck. Once you have convinced yourself of something subtle/complex have a subagent review it." And: "keep frequent running notes on this work in a sensible location" (this file).

**Design:** `writeup/explorations/wrapping-by-facts.md`.

**State at the start:**
- TraitWorld `main` c62efbf: `FactsInterp`, the compiler policy, in `src/facts.jl`.
- julia-1.13 `trait-world-1.13` 9af2f27786: pieces 1–5.
- Acceptance 5/5 on both builds.

## What "completely validated" means here

1. **G1 (identical or error):** the acceptance checks plus the demonstrators, under redefinitions, pirates, and calls into code written without traits (ForwardDiff, Cairo used directly). No skip predicate may be active (rule P).
2. **G2 (stable cache):** with CSV, DataFrames, CairoMakie and others loaded before or after, in any order, no trait-world code is invalidated except by stakeholders or winning pirates. TraitWorld's machinery should not be invalidated either, or should not matter.
3. **Speed:** typed calls near plain Julia; first calls fast from images; hot loops of the demonstrators at plain speed.
4. **The subtle points reviewed by a subagent:** the soundness of the implementation (exemptions, return types, opaque closures, images), and the proof's assumptions.

## Open points found at the start (reading `src/facts.jl` and the agent's notes)

- **Machinery exemption.** Calls to TraitWorld's own functions are inferred under Julia's own policy (abstract edges). This is sound, since edges are recorded and not skipped, but it costs G2 (machinery invalidated by loads: 631 instances on stock in row 7) unless the machinery's paths are concrete.
- **The patched build still registers the skip predicate** (the policy hook of piece 2, rule 4 by required package). Rule P says nothing is skipped. Measure with the predicate off; remove it if the facts alone suffice.
- **Typed calls cost 42 ns** under the policy (32.7 ns without, 29.9 ns plain): `_facts_call` is not inlined, plus a world check and an opaque-closure call.
- **Row 7 "before" costs 0.56 s** on the patched build: to diagnose.
- **On stock Julia** (no piece 5) every session compiles the policy's cache: inherent, so stock is not the target for speed.

## Log

- (start) Phase A: the demonstrators use ForwardDiff and Cairo directly. Rule 1 is off by default (`LAYERING[]`), so trait modules may import Cairo.
- **A1: TraitMakie calls Cairo directly** (branch `direct-cairo`, uncommitted). The declared calls (`@call`), the `Surface` handle and the Cairo helpers in the ordinary module are gone; `PlotCore` does `using Cairo` and calls it. Patched build, filter on:
  - tests pass;
  - first PNG 83 ms alone, 143 ms with CSV and DataFrames loaded before, 84 ms with them loaded after;
  - invalidated after the loads: PlotCore 0, TraitWorld 0.
- **Key test: the skip predicate off** (`JULIA_TW_FILTER=0`, so nothing is skipped, as rule P demands). Patched build:

  | | none | loaded before | loaded after |
  |---|---|---|---|
  | TraitMakie first PNG | 145 ms | 252 ms | 303 ms |
  | TraitMakie invalidations | | | PlotCore 0, TraitWorld machinery 312 |
  | TDE row 1, first solve | 52 ms | 2.49 s | 2.72 s |
  | TDE row 2, second model function | 15 ms | 15.6 ms | 15 ms |
  | TDE row 4, new callback | 22 ms | 123 ms | 4.5 s |

  TDE "after": ODECore 8 invalidated (`keep_callback`, `solve_ode`), the ordinary layer 13, machinery 751.

  **So the facts policy alone does not yet give G2.** The filter (a skip predicate) was carrying it. Suspects:
  - **(a)** entries and the ordinary layer are compiled natively, with abstract edges;
  - **(b)** the machinery's exemption from the policy;
  - **(c)** native CodeInstances of trait-module methods next to the facts ones.

  Next: attribute the chains (trigger, root edge, holder).
