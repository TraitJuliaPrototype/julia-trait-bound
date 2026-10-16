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

Decisions (the user): solvers postponed; fields declared by a bound
rejected ("Hidden type parameters seem antithetical to Julia"); `Dynamic{X}`
adopted ("Go for it"), now in the live note at rev 1125: Finer points
subsection "Dynamic values" (made at a bound, translated once when made,
sharing views root the user's object, operations dispatch with declared
results, opened by a bound, equality as Swift's AnyHashable, several traits,
up and down as a trait-world value), the table rows, the Makie paragraph,
closures, AOT and trade-off 7.

Traits and abstract types (the user: "our Traits are what AbstractTypes
should have been. There should be no reason to use AbstractTypes anymore if
Traits succeed"; "I like the AbstractType sugar"), note rev 1128: a trait's
name in a field or container means its Dynamic, in an argument a bound,
`Vector{<:ColTable}` one representation (projection of user vectors open);
new subsection "Traits and abstract types" in "Working with existing Julia"
(every use of an abstract type has a trait form; what traits add is in the
declaration: membership after the fact by owners, checked contract,
translation; "types first, then traits" settles the transition, and without
abstract types the rule is concrete types first, then traits by refinement;
open: isa and <: as conformance, traits with parameters, numeric tower); the
trait concept bullet; the rejected competing-ranking option reread.

Open points decided (the user: "yes, yes, and needs detailed investigation.
We are not removing AbstractTypes, in fact AbstractTypes that can become
concrete are a key design point"), note rev 1131: a trait is an abstract
type guaranteed to become concrete (abstract types stay; traits are a kind
of them); membership is subtyping (`isa`, `<:` mean conformance); traits take
parameters declared by the conformance (several values per type open);
numbers need no trait (the tower stays; promotion on concrete types in Base);
numeric traits and cross-representation promotion open.

Correction (the user: "Concreteness guarantees are opt in though"), note
rev 1139: a trait is an abstract type with behaviour; optionally it
guarantees that its members become concrete with respect to the behaviour it
carries. Every place that stated concreteness as universal now says "where
the trait requires it" (the trait concept, the bound paragraph of "Between
nested types and Any", the hot-loop cliff, "Traits and abstract types", the
conformance checks, the one-line form, trade-off 7).

Definition checking and named implementations (the user: "I like the
proposal. Open Parameters defer checking sounds pragmatic"; "Liberal it is.
Go for it and then fold 2-5 into the note after you checked the archetype
check"). `writeup/proposal-definition-checking.md`. Prototype:
`TraitWorld/src/defcheck.jl` (`Archetype{X}`, `ArchWit`, `archetype_tobj`,
`archetype_sig`, `check_definitions`; a worker's first call skips its
per-signature check when its method was checked at definition), demo
`poc/world/defcheck_demo.jl`, 10 new tests (all pass). Results: Columns
checked in 184–199 ms cold; mistakes in a library found with no
representation (`size(t)`, `typeof(t)`, `sum(t)`, rule 2), at their lines;
first calls of a new own representation 3–4 ms faster (colrange 24.8–25.5 →
21.4–21.6 ms): the checks are a small part of a first call, the gain is early
errors. Named implementations (liberal: anyone, used only via `via(M, x)`).
Note rev 1146: both subsections, rule 3, generic overlap in both orders, the
check paragraph, concreteness as a commitment, trade-off 1 (C++0x's
objections answered), trade-offs 9 and 10 (early binding, shared code).

Restructure (the user: "the note has grown out of proportion"; "Everything
as markdown locally"): four notes in `writeup/notes/`:
1-overview (motivation, pay-offs, the idea, the Columns example, costs,
status, further reading; no wrapping), 2-design-choices (the comparison with
C++, Rust, Swift, Mojo by decision, lessons, reasoning, costs, rejected
options, predictions and their status), 3-wrapping (adopting traits, traits
over existing functions, wrappers, Base, calls upward, sealing), 4-details
(terms, ownership, the four rules, boundary principle, declaring traits,
conformance forms, generic and named implementations, traits as abstract
types, dispatch, definition checking, Callable, keywords, crossing
functions, Dynamic values, caching, AOT, performance, identical or error,
extensions, open points). New: an ownership introduction from Julia's own
notion of type piracy (who owns a function that gets methods from many
places, with a table of examples); trait fields (`data::R` names the
projection; other fields are fields of the representation, read-only, a
field being an operation with a fixed implementation). The single note's
local copy is archived with a banner; the live Claude Doc is unchanged
(rev 1146).

Ownership by stakeholders (the user: "owners are always modules? ... How is
ownership decided here?"): owners are packages; a method has stakeholders
(the owner of its function and of every type in its signature) and may be
defined only by one of them or a delegate; why: stakeholders are exactly the
owners a call is compiled against (rule 4). Writable fields (the user:
"desugar data::R to requiring two methods"; "write the lens version"): trait
fields are properties (`getproperty`/`setproperty!` on the representation),
writable unless `const`; copying projections refused; the projection field
`data::R` is a lens (the user's object and the field's index), live, kept as a
lens in `Dynamic` values. Measured (`poc/lens/lens_bench.jl`, findings §18):
lens read 4.6 ns via builtin getfield on Any, 1.15 ns as a pointer load at the
offset, 1.0 ns held; write 13.6 ns vs 0.6 direct.

Results like the input (constructor operations returning `R`; the
conformance's inverse: identity, the lens's other half, or `unproject`; the
entry translates on the way out), in `4-details.md`.

Four explorations (`writeup/explorations/`, commit a04e2f0):
- associated-types.md: the design already has associated types (output
  parameters, `eltype(R)`); Rust's/Swift's pain came from symbolic reasoning,
  which arises for us only at definition checking, overlap/coverage and
  Dynamic; adopt output parameters, joint family conformance
  (`@implement ArrayLike{T,1} Series{T} where {T}`), bounds on parameters, the
  `R` bound as a supertrait; forbid recursive bounds and type-function
  equations; `Archetype{X, P}`.
- runtime.md: move to Julia 1.13.2 (tagged 14 Oct 2026; 1.12 unmaintained);
  gf.c patch applies, load patch rewritten (`Compiler/src/reinfer.jl`); the
  load-time half works by injection on stock 1.12.2/1.13.2 (x12: 4.9 vs 29 ms);
  owner-tagged CodeInstances keep no machine code in images (no demonstrator
  vehicle); the critical path is a vertical-slice rewrite (2–4 months).
- makie-rewrite.md: eight traits; Makie 0.24 nodes have fixed types (a colour
  shape change fails), so the notes' reason for Any holds only at inputs;
  demonstrator PlotCore + CairoBackend, baseline PlainPlots, ten measurements.
- solvers.md: seven traits (StateVector{T}, ODEModel, IntegratorView via a lens,
  Integrator, Callback, …); stock baseline: a new callback closure 0.84–0.96 s,
  a second AD loss 2.48 s (full recompile), Rodas5 integrator type 24,426
  characters; demonstrator Tsit5 + Rodas5 with AD + callbacks.

Workspace restructure (the user: "Yes on all decisions. Set up the folder in a
way that matches the plan ... We are focusing on demonstrating a trait world
viability, we will look at wrapping and sealing later"): the design
repository keeps writeup/, session-notes/, attic/ and a README with the plan;
inside it, ignored by it, five repositories: `julia/` (moved from
attic/binary/julia; new branch `trait-world-1.13` = v1.13.2 + both filter
halves + TRAITWORLD.md, not built; `trait-universe` = the 1.12 build),
`TraitWorld/` (split with history), `experiments/` (formerly poc/, split with
history), `TraitDifferentialEquations/` and `TraitMakie/` (skeletons with
plans and measurement tables). Paths in current docs updated (poc/ to
experiments/). Notes: associated types adopted in first-order form (R last,
defining equations, parameter bounds, family conformances, parameter
archetypes), the explorations' gaps as open points, Makie correction.

TraitWorld at the current design (the user: "should the first step be to bring
Trait world up to the current design instead?", yes; the build postponed),
all on stock 1.13.2: `Dynamic{X}` (3a1d3a6), trait fields and lenses
(2830a19), associated types with parameter archetypes (35fd2d1), results like
the input (7f59f8a): `f(t::ColTable)::Like{t}`, constructor operations
returning R (a `Dynamic` stays `Dynamic`), the inverse as identity (same type
checked), field copy rebuilt by the type's constructor (a sibling
representation gives `Series{Float32}`), or the conformer's
`unproject(t, r)`; a written `project(t) = t.cols` now counts as a field
projection. Found: no field projection for a whole family of user types yet,
and the inverse is not listed for AOT (`verify_main` reports it). 283 tests.
I ran the test suite while the re-baseline agent was timing; asked it to
re-take the overlapping numbers.

Keys replace representations (the user: "Do we really need this to make the
caches work? Or is the only real reason we have it is to enable concreteness
guarantees?"; then "in principle we can compile per collection of associated
types of the fields"; "I think the motivation also needs a big change with
removing representation as a concept"). Answer: cache validity never needed
representations; reuse needs a key without the user's type, which in Julia
means an entry that passes the parts code may touch (a calling convention, not
a compiler rewrite). Notes rewritten (6c7f088): operations declared at the
trait, `Self` for the implementing type, forwarding to a field (`by`), key =
implementing type + declared field types (associated types), computed
projections removed, motivation now "Julia compiles for the whole type of each
argument" / "compiled for what the bound can see"; findings §19. Sent to
fable-critic for review. TraitWorld not yet changed (R last, computed
projections); feature 5 (printing) and `conforms` written, not yet run.

Two reviews of keys (fable-critic on Opus, Fable's limit hit): notes and plan
revised (06d8534, explorations/keys-plan.md). TraitWorld ca9b8a9: printing by
bound and key, `conforms`, the design's trait and conformance syntax lowered to
the internal form; 308 tests. Re-baseline on 1.13.2 done
(experiments/baseline-1.13.md, 734e57f): solver structure unchanged, 0-20%
faster; injected load filter on stock 1.13.2 matches the patched 1.12 build
(x12 summarize 3.2-3.6 ms, x13 first PNG 8.1-8.5 s vs 14.2-14.4 s); entry
fixed cost now 215-220 ns vs 110 ns recorded (a TraitWorld regression since
M5, same on 1.12.2); precompile 17-26% faster. Open: the user's question
whether `f(t::Trait{U,T})` desugars to a worker per key reading the user's
object through offsets (reference layout): recommended as the one layout,
pending a held-vs-reference benchmark and the user's decision.

## Next
- Build the patched 1.13.2 (needs network, ~1 h alone); move TraitWorld to
  1.13 with the injected load filter as its stock mode; re-baseline.
- TraitWorld features left for the demonstrators: printing frames by bound
  and representation, the pinned model mode, family field projections,
  `conforms(T, X)`.
- TraitDifferentialEquations step 1 (Tsit5, a trait-world model, rows 1, 2,
  4, 7, 10), then TraitMakie.
- Later (wrapping is paused): named implementations (`via`); archetype
  checks for keyword, vararg and `Callable` workers with declared results.
