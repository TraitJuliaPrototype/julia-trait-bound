# Proving the references: the demonstrators next (proposal, 2026-10-20)

The user (2026-10-20): "think about what's next for the Demonstrators and to prove out the design defined in the references … note down a proposal somewhere." A proposal only; nothing here is decided or started.

**The aim.** The four references (`../reference/`) now state the intended shape, and their Deviations tables say where the prototype falls short. Proving the design means three things:
1. every rule marked Implemented is checked by a test that names it;
2. every guarantee holds in realistic stacks, not only in small cases;
3. the demonstrators exercise the parts of the language a real ecosystem needs, at a scale beyond a few hundred lines.

The work below is ordered by how much it would change our confidence in the design, not by size.

## 1. A conformance suite for the references (first; cheap, and the base for everything else)

As a language's reference has a test suite, each reference gets one. `experiments/docs-examples/` already runs the traits reference's examples (56 checks) and the tutorial's (64).

- **One check per rule.** Every Implemented rule in the four references gets a check whose name cites the section (`traits §5.2`, `facts §3`, `compiler §3.2`, `lowering §9.2`). Today's checks cover the traits reference's examples; the facts, compiler and lowering references have almost none of their own (the acceptance suite covers G1/G2 by case, not by section).
- **One check per deviation, expected to fail.** Each live T-, F-, C-, L- row gets a check written for the intended shape and marked as a known deviation (`@test_broken` style). A fix flips it, and the table row is retired in the same commit. A deviation without such a check is a claim nobody re-verifies.
- **Run in both settings.** Product setting and test bed `all`; and strict mode on and off where the rule concerns it.
- **A coverage line in each reference's status index:** how many Implemented rules have a check.

Cost: mostly writing checks against code that exists. It also finds rules that are wrong as stated, as the reviews of 2026-10-19 did (T-26 to T-36 were found by reading, and none has a check yet).

## 2. The guarantees in realistic stacks

The references' central claims are G1 (identical or error) and G2 (no load of an unrelated package invalidates trait code), and, in strict mode, that trait code is never invalidated.

- **G2 across loads, for code compiled by facts** (F-11). `experiments/facts/g2all.jl` is ported to count owner `:facts` (2026-10-20). Run it for every demonstrator, in three load orders (before, interleaved, none), with the big-loads stack (CSV, DataFrames, CairoMakie, StatsBase, Unitful, IntervalArithmetic, Distributions, Interpolations, StaticArrays). Expected: zero lost. Each loss is either a named exception (a stakeholder's change, an extension, accepted entries compiled ahead) or a bug.
- **Strict mode in a real stack.** The product setting with strict mode on, the same loads: what is refused, what is warned (extensions), what it costs at load. Strict mode was last measured in a real stack on the previous prototype.
- **The extension rule in a real package.** TraitCSV's InlineStrings extension and the forks' CSV extensions are real cases of decision 4 (followed, with a warning). Check that the warning appears where a fact of trait code changes, and nowhere else.
- **G1 on upstream test suites.** The forks (CSV.jl, DataFrames.jl, Tables.jl ported to traits) carry the upstream test suites. Resuming them (paused in session 29) is the strongest G1 evidence available: thousands of upstream assertions, run against trait code. Start with Tables.jl (smallest), then CSV.jl.
- **Base's test suite under the test bed** (started once, not completed): a long run for a quiet night, recording failures by cause.

## 3. The demonstrators: what each should prove next

| Demonstrator | Proves today | Next, to prove the references |
|---|---|---|
| TraitDifferentialEquations | Callable modes, keys per model, gradients compiled per key | Row 6 (a `Float32` state, first solve 363 ms) is the slowest row: find whether it is a family member compiled on first use (traits §5.7) or a missing image entry. `LorenzModels` as the "user package" whose image holds its compiled-ahead entries: measure what it costs the package's image and what it saves the first solve (traits §15). Associated types (`StateVector{T}`) are where `where` variables in bounds (T-16) and parametric `Dynamic` results (L-20) bite: a row that needs them. |
| TraitMakie | forwarding, colours as a trait, recolouring, a trimmed binary | Row 5 (dispatch targets for a closed build) is unmeasured since the policy was removed: `verify_main` on the full plotting workload, then a trimmed binary of the session's plots. Dynamic beyond four implementations (Optional, compiler §3.3): a plot with five or more mark types in one figure is the natural first demonstrator that needs it. The pixel flake: reproduce or rule out. |
| TraitReport (TraitTables, TraitCSV) | a fresh-session CSV → PNG at 0.79–0.81 s against Python's 0.58–0.59 s (the round of 2026-10-20, [evidence §3](../design/evidence.md#3-first-calls-and-sessions)) | *Done:* the Python environment recreated for a fair baseline (pandas 3.0.6, matplotlib 3.11.2, the round of 2026-10-20). A trimmed binary of the report (AOT from declared targets at the scale of three packages). The InlineStrings extension case (§2). Families of column types (`Column{T}`) with forwarding for a whole family, when built (traits §5.7, Planned). |
| forks (CSV, DataFrames, Tables) | — (paused) | The scale test: libraries of tens of thousands of lines, the upstream test suites (§2), the porting guideline (`../intro/porting.md`) applied as written, and a count of what the references could not express (each a new Open item or a T- row). |

## 4. A new demonstrator, if one is added

A demonstrator should exercise what none of the four does. The gaps:
- **Composition:** two trait libraries by different authors, used together by a third package that implements both traits for its types (open: "composition beyond libraries of a few hundred lines untested").
- **Many implementations:** a trait with ten or more implementations used through `Dynamic` (forces the Optional path beyond four).
- **Generic implementations and families at once** (traits §5.7, §5.8), including the overlap rules (Planned).
- **Heterogeneous collections through collection traits** ([open issue 31](../open-issues.md), added 2026-10-20): an `Iterable`-style trait with a declared item bound and a view over a user's vector, in TraitWorld itself rather than in a demonstrator. TraitMakie's lists of marks and TraitTables' columns would be its first users, and the review's heterogeneous loops (`../reviews/2026-10-20-heterogeneous-collections.md` §5) its first measurement.

A small statistics library fits all three: distributions as a trait with many implementations (`Normal`, `Exponential`, … as families over their parameter types), a generic implementation for "anything with a CDF", and a second, independent library (for example a plotting trait from TraitMakie) composed in a third package. It should start small, with the conformance suite's style of checks from the first day.

## 5. What would count against the design

Recorded so that the results can be read honestly:
- a loss of trait code under G2 that no named exception explains;
- a G1 difference on an upstream test suite that is not one of the named exceptions (values Julia decides by inference);
- a rule in a reference that a real port cannot follow without a workaround that the references would have to call a pirate or a hidden type parameter;
- costs that traits cannot recover: a demonstrator row slower than its plain baseline after the facts mode and traits are both applied, with no deviation explaining it.

## 6. Order and size

1. The conformance suite for the facts and compiler references, and xfail checks for the live deviations (a day).
2. G2 across loads for every demonstrator, and strict mode in the real stack (half a day, mostly machine time).
3. TraitDifferentialEquations row 6 and the `LorenzModels` image; TraitMakie row 5 (a day).
4. The forks: Tables.jl's upstream suite, then CSV.jl's (several days).
5. A new demonstrator, only after 1–3, and only if the forks leave composition and many implementations unexercised.
