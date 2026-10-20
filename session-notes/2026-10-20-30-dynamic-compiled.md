# Session 30 (2026-10-20): `Compiled` and `Dynamic` built (W-4)

## To resume

1. `../CLAUDE.md`: the rules for documents, with two new rules in bold: current intended state plus deviations, never history; quick regression tests, no benchmarking outside performance work.
2. `../writeup/record/todo.md`: **next W-2** (TraitDifferentialEquations around `ODEProblemTrait`, written in the new language), then W-3. W-17 measures `Compiled` and `Dynamic` after the idiomatic rewrites and E-145.
3. `../writeup/reference/traits.md` §6.6 (the rule), §3.8, §9, §10, §10.2; `lowering.md` §5, §8.2, §9.2, §12, §13, §13.1. Deviations T-47 to T-50, L-31, L-35. Performance issues P1–P10: open issues item 35.
4. Every repository is on main again (TraitWorld 7fc229c); nothing is pushed.

## What was done (in order)

- The material of W-4 reviewed; the user refined the rule (the type the code knows decides; attributes on item parameters; no warning on disagreement; no synonyms; the prompt `Dynamic`, to revisit).
- An implementation plan, reviewed by Fable (`../writeup/reviews/2026-10-20-dynamic-compiled-plan.md`), revised twice; the user narrowed it to the semantics (`../writeup/plans/2026-10-20-dynamic-compiled-implementation.md` §1a).
- Phase 1–2: the references and the design documents written to the intended design.
- The spike (E-148): `known_type` folds as the entry needs in every shape; it must be evaluated in the entry's own body.
- TraitWorld (branch `dynamic-compiled`, merged): the erased key, the entry's decision, conversions, attributes, `@dynamic`, rule 8, `Callable{A, S}`, `Dynamic{Callable}`, items (`Through{Y, A}`, `CompiledItems`), `dynamic by` refused. Found: a call dispatched at run time passes `Dynamic` values (also Julia's `@allocated f(x)`); in an operation's methods `Dynamic{X}` stays a type; a family registry keyed by a gensym collided across images (fixed).
- The demonstrators: TraitDifferentialEquations in the new spelling; `compiled_for` where TraitTables, TraitCSV and TraitMakie loop over a stored `Dynamic`.
- Checks: `run_all.sh` (logs `experiments/checks/logs/dyncomp/`), every suite passes but TraitWorld under `all` stops at the known F-8, as before; acceptance 23 of 23 in both settings; E-147: every demonstrator row runs, none grossly slower.
- Phase 6–7: `intro/`, state, evidence; statuses flipped; deviations retired.
- The user's two rules, and a cleanup of history from the references.
