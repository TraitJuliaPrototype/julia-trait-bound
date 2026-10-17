# writeup/

Everything here is current as of 2026-10-17 (session 26). Superseded documents are in `attic/writeup/`.

## Read in this order

1. **[`notes/1-overview.md`](notes/1-overview.md):** why, the idea, the pay-offs, an example, the status.
2. **[`notes/2-design-choices.md`](notes/2-design-choices.md):** what the design decides, against C++, Rust, Swift and Mojo, and what each choice costs.
3. **[`notes/4-details.md`](notes/4-details.md):** the design in detail: terms, ownership, the four rules, traits, conformance, keys, dynamic values, results like the input, caching, AOT.
4. **[`notes/3-wrapping.md`](notes/3-wrapping.md):** code written without traits: called directly, compiled under the facts policy; pirates; strict mode (an option); what Julia must provide.
5. **[`decisions.md`](decisions.md):** every decision with its status (adopted, rejected, deferred, pending) and whether the prototype runs it.
6. **[`open-issues.md`](open-issues.md):** everything open: decisions waiting for the user, design questions, the prototype's gaps, the runtime and measurements.

## Supporting documents

| File | What | Status |
|---|---|---|
| `other-languages.md` | research: how C++, Rust, Swift and Mojo arrived at their trait designs, with criticisms and sources | current |
| `design-findings.md` | the evidence log: measurements, prototype results, earlier forms of the design and why they changed, in session order | current evidence in §1, 5, 6, 13, 15–19; history elsewhere (its header) |
| `explorations/keys-plan.md` | how TraitWorld implements keys: two reviews' decisions, phases, the reference layout, the runtime as methods (§6) | implemented (session 23); the session note records what changed in implementing it |
| `explorations/wrapping-by-facts.md` | a simpler, provable design for using code written without traits: concrete facts, nothing skipped; synthesis of three fresh designs (`explorations/wrapping-designs/`) | adopted (session 23), validated (session 24: assumptions A3–A5, implementation rules 1–7) |
| `explorations/julia-support.md` | what TraitWorld needs from Julia proper, the order to implement them, and what is implemented in the patched build | reviewed in session 25 for wrapping by facts and strict mode: pieces 2, 4, 6 dropped, 9–13 added, new order |
| `explorations/strict-mode.md` | strict mode: defining a pirate that would win at a trait-world fact is an error, so trait code is never invalidated by a pirate | session 25; adopted as an option, prototype planned |
| `explorations/aot-under-facts.md` | AOT under wrapping by facts: builds compile plain Julia, what the trait world still gives, three risks, three binaries to measure | session 25 |
| `reviews/2026-10-17-demonstrators-under-facts.md` | the three demonstrators' rows checked against wrapping by facts; the order of work (Julia pieces and TraitWorld fixes over workarounds) | session 26 |
| `reviews/2026-10-16-wrapping-under-keys.md` | review of code written without traits under keys (F1–F11, nine decisions) | F1 fixed; F2, F4–F8 and F10 dissolved by wrapping by facts; F3, F9 open (open-issues §4b) |
| `explorations/runtime.md` | the runtime the design needs, Julia 1.13, the load filter, the minimal runtime for the demonstrators | current, recommendation adopted |
| `explorations/runtime_load_filter_1.13.2.patch` | the load half of the invalidation filter, ported to 1.13.2 | history: the filter is not needed under wrapping by facts |
| `explorations/associated-types.md` | associated types: whether Rust's and Swift's experience applies, joint parametrization, bounds | adopted in first-order form; written before keys |
| `explorations/solvers.md` | the design of TraitDifferentialEquations: traits, composition, callbacks, AD, the SciML baseline | demonstrator design; written before keys (banner) |
| `explorations/makie-rewrite.md` | the design of TraitMakie: fundamental traits, a typed compute graph, the minimal demonstrator | demonstrator design; written before keys (banner) |

## Where the rest lives

- **`session-notes/`:** one note per working session. The latest is `2026-10-17-26-demonstrators-and-traitreport.md`; its "Next" list is the starting point for the next session.
- **The repositories inside the design repository** (`README.md` at the root): `TraitWorld/` (the prototype), `experiments/` (measurements and prototypes), `julia/` (patched Julia), `TraitDifferentialEquations/`, `TraitMakie/` and `TraitReport/` (the demonstrators).
- **`attic/`:** the earlier phases: TraitRegions, the ecosystem proof of concept, the frozen live note (revision 1146), the proposals and plans of sessions 14–22.

## Conventions

- **Terms** as in `notes/4-details.md` "Terms": trait, conformance, implementation, implementing type, key, trait object, entry, worker, view. "Representation" and "projection" belong to the design before keys, and appear only in history.
- **Writing:** short sentences, bullets for anything with more than two parts, one idea per sentence, no unexplained jargon.
- The machine is shared: one Julia job at a time, at `nice -n 19`; full builds alone, under a memory guard.
