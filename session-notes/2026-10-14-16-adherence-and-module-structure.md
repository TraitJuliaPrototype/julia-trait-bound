# 2026-10-14 — Session 16: conformance by field or methods; exported and internal functions; linked representations; parametric types; keywords

Design only, in the note ("Traits for better Julia", Claude Doc, rev 953 to
1019). The prototype (TraitWorld) is unchanged: the user is interested in the
design, not in developing the proof of concept further.

## The user's asks

- The example under "An example: a library and its user" still showed the
  earlier core concepts. Boil it down to field and method adherence, and give
  a fuller example of the forms further down (inline note and a comment
  thread, which the user stopped and resolved before this session).
- A simpler implementation scheme: a type with a field `data::R` adheres
  through it, the projection is elided, and the simplest form is
  `@implement LibTrait MyType`.
- Distinguish exported from internal functions in a trait module: internal
  ones operate on representations and non-exported types; only exported ones
  need bounds, the rest must infer fully from R.
- Unsure: a module-level declaration that links representations,
  `@trait_module Table{R} with ColTable{R}, RowTable{R}`.

## Done in the note

- The example rewritten: `@implement ColTable Measurements` (a field) and
  `@implement ColTable Ramp` (methods), with the inference rule and the two
  cost classes. The prototype runs the library as written and the written-out
  forms; the one-line form is design.
- New section "How a type adheres to a trait" at the end of the core concepts:
  seven forms, a table of what each compiles, the checks at the declaration.
- The interactivity example and "Several traits, one projection" use the
  one-line form; the trade-off on dynamic operations now says "at a shared
  representation"; two typos fixed.
- Two proposals were first written under "Possible extensions"; the user
  decided ("Lets adopt 2 and leave out 3"), and the note was changed at rev
  964: rule 3 reworded (a trait object passes to functions without a bound,
  which are compiled for it, and to a bounded argument only where its own
  trait or a supertrait is expected); a paragraph on exported and internal
  functions in "What code in a trait module may do", and the table row
  "passing a trait object to the module's own functions, or on where its own
  trait is expected"; the "Trait modules" bullet now says exported functions
  take bounded arguments and internal functions need none; the user's
  "(Explore: …)" note is resolved and removed; linked representations per
  module are a bullet in "Other options considered".

## Design, as decided (1 adopted with the example, 2 adopted, 3 rejected)

1. **`@implement Trait T` with no body** reads the type. Methods of the
   trait's operations for `T` make it its own representation, checked as an
   implementation. Otherwise the field named `data`, or the one field whose
   type adheres, is the projection; a field whose type adheres by projection
   composes. Methods win over a field; partial methods, several adhering
   fields without `data`, or an abstract field type are errors at the
   declaration, with the field or operation named. Nothing is checked at a
   call.
2. **Internal functions without bounds** (adopted). Exported functions
   are the boundary and carry bounds; internal functions are inferred and
   compiled with the worker that calls them; the handle still admits only the
   trait's operations, so a use the bounds do not cover is a build-time error
   naming the bound to add. Concrete mode is the "infers fully from R"
   condition. Rule 3 and one row of the "may do" table would change.
3. **Linking per module** (rejected, in "Other options considered"). Bundle traits link per
   function already, and a type links by one field whose type implements
   both. A module-level link makes every function need the joint adherence,
   which loses adoption one trait at a time; read as a module generic over
   one R it cannot express two representations in one function.

## Later in the session

- Terminology: the user chose "conform" over "adhere"; every "adhere" in the
  note was replaced (rev 976, with the proposal below).
- Parametric user types, first a proposal at rev 976, accepted by the user
  ("Proposal looks good") and folded in at rev 978 as its own subsection: a
  parametric type conforms as a family declared with `where`, as Base's
  families are, or per instantiation; the one-line form on a parametric type
  means the whole family. Checks at the declaration for the family: a
  field's family of types must be covered by one implementation's or
  projection's family (subtyping decides; a generic implementation's
  predicate must be decidable on the family's structure); methods must cover
  the family with results inferred at the family's signature; every
  instantiation concrete. A refusal names the instantiations that would
  conform. Avoids checks at a first call and derived conformance.
- Structure (user: "Keep the first half of the note light, add subtleties
  like this further down"): a new H2 "Finer points" between "Working with
  existing Julia" and "Trade-offs" holds "How a type conforms to a trait"
  (moved out of the core concepts, rev 977), "Parametric user types" and
  "Keyword and default arguments". The rules, the "what code may do" table
  and the module-structure paragraph stayed in the first half.
- Keyword and default arguments (rev 979, the user asked for a design):
  as in plain Julia, with one placement rule. Defaults are trait-world code
  evaluated in the worker after projection (a default may be `t` itself or
  call an operation); evaluating them at the entry would run trait-world code
  on the user's value. A positional default is Julia's shorter method, an
  exported method whose body calls the full one (rule 3). The entry projects
  every bounded argument, positional or keyword, and passes the supplied
  keywords on as a named tuple; the worker fills defaults, compiled per set
  of supplied keywords by name and type as Julia's keyword sorter is. A
  keyword is typed like a positional argument (bound, declared type, or the
  value supplied); declared types are asserted at the entry; no dispatch on
  keywords, so a bound on a keyword only projects and restricts. A default
  for a bounded parameter is a trait object of that trait or a value of an
  implemented representation, checked when the worker is compiled. Functions
  from above called with keywords name them in a third `Callable` parameter,
  a named tuple type, checked with `hasmethod` at the boundary. The "Open:"
  list under Callable no longer names keyword arguments.
- The principle (rev 984; the user asked for "a simple principle from which
  these decisions flow" instead of case by case): rules 1 and 2 read
  operationally. Only values cross the boundary, each where a bound stands,
  and the bound says how the value is translated (trait bound projects,
  declared type asserts, `Callable` makes a pointer at a signature or, with
  `@specialize`, a worker compiled above on the function's type; no bound
  means a trait-world value). Code never crosses: the trait world never
  compiles against code from above. No bound for the way up, so what goes up
  goes as itself. Everything in a call that is not a value stays inside
  (defaults, keyword sorting, splatting, dispatch). A bound is a crossing
  point and has an entry, on a named function or a closure alike. Stated at
  the head of "Finer points"; the subsections apply it.
- Derived at rev 984: varargs (one bullet in "Keyword, default and variable
  arguments": several crossing points with one bound, compiled per tuple of
  representations); a new H3 "Functions that cross the boundary": a returned
  closure is a trait-world value, called from above on trait-world values as
  ordinary code using the trait world, and keeps captured trait objects; a
  closure with a bound has an entry; an unbounded closure on a value from
  above runs as plain Julia and concrete mode refuses it; a `Callable` result
  is translated by its bound (a `Callable` result: a pointer at the inner
  signature per call, or inferred at the boundary under `@specialize`; a
  trait result: projected per call, representation inferred at the boundary
  as open result types are); trait objects never go up (no upward bound, no
  self above). The "Open:" list under Callable keeps only the cost of an
  unspecialized call.
- The user asked whether the library's `@specialize` choice survives the
  principle: yes; erased moves the function down as a pointer, specialized
  moves the worker up as ordinary code (rule 7); the trait world's compiled
  code never depends on the function's code either way.

- Callable modes (rev 988). The user wanted the library to set a default
  for compiling per function type versus calling through a pointer, with
  the caller able to override. Explored: subtraits (the user's first idea,
  AbstractCallable/ConcreteCallable), wrappers at the call site, a call-site
  macro, a module or build policy, a keyword at the call (rejected: enters
  the library's namespace), a heuristic (rejected: a cliff by construction).
  The user rejected "erase/specialize" as the implementer's words, and
  `inline` because a compiled call is not necessarily inlined. Decided: a
  third parameter `Callable{A, S, M}` with exported `CompiledCall` and
  `DynamicCall` (default), and wrappers `compiled_call(f)` /
  `dynamic_call(f)`; the bound carries the library's default, a bound
  without the parameter accepts either mode; the value's type wins because
  the library has no stake (rule 7: neither mode touches its cache); the
  long form `Callable{A, S, DynamicCall}(f)` is FunctionWrappers'
  constructor (FunctionWrappers' own README names no mechanism: "type
  stable and efficient wrapper", "a function that sends (x1::T1, …) ->
  ::TN"). `@specialize` retired throughout; "static and inlined" corrected
  to "a direct call the compiler may inline"; trait-world functions are
  always compiled calls; a `Callable` result overrides by returning a
  wrapper; the Trade-offs and cliffs bullets reworded. A module or build
  policy as a middle precedence level was discussed and left out.
- Code not written with traits in mind (rev 992 to 1004, a long exchange).
  Base: the user pushed back on "we monitor the trait world to touch only a
  trait-compatible part of Base" and asked for the honest reading; agreed:
  all of Base is in, membership is per specialization, checked on the
  compiled code (every global read has a trait-world type, deeply concrete;
  no door; callees checked transitively; dynamic sites select only owners'
  methods), with the door list as the only curated thing. Doors have a
  direction: outward (logging, display, print to stdout) are dynamic calls
  upward without an inference edge, nailed to declared sinks in a build;
  inward (eval, invokelatest, deserialize, reflection, getglobal, task
  storage, raw memory) only as declared calls with a checked result, and
  values denoting code from above have no admitting bound. The same check
  applies to any package: rule 1 now says a trait module may import any
  package and what its workers reach is checked (DiffEq's numerics pass,
  Makie's state and effects do not, which is the right answer for both).
  AOT and interactivity hold by the same argument; the new requirements:
  outward doors and declared calls have no inference edge, and a package's
  precompiled specializations are reused after the audit, not recompiled.
- Interface packages (the user's "translation package", renamed at their
  request): a package whose surface is trait modules; for an outside package
  like Makie, a trait half (traits, bounded functions, conformances,
  handles = the mirror image of trait objects) and an ordinary half (declared
  calls, the outside package's globals behind them, the declared signatures
  as precompile workload). Compiled code: rule 7 unchanged; the trait half's
  workers in the trait-world cache without Makie in their closure; Makie's
  code at the declared signatures in Makie's or the interface package's
  ordinary cache. Interface packages to Base (the curator of traits over
  Base's interfaces) and to standard libraries with inward doors
  (Distributed). The "Calling into non-trait code" extension sketch was
  removed; the pattern is settled under "Finer points".
- Piracy, three rounds. (1) The user feared constant PiracyErrors under
  "poison at the call"; I offered immune (ignore pirates in the trait world)
  and recompile-and-warn. (2) The user chose immune, then worried about
  subtle bugs from two versions of one method; I agreed (hash/isless/convert
  invariants across worlds disagree silently) and recommended refusing the
  load. (3) Decided: loading an interface package *seals* its dependency
  closure, both halves; a definition that would pirate a sealed package is
  refused at precompile, else at load, else at the definition, naming the
  pirate, method and owner; owners keep their freedom; the opt-out is plain
  Julia (tolerated pirates, declared by an interface package for its tree or
  per package in a project, recompile the touched signatures with a
  warning); the interim is everything tolerated with refusal as strict mode.
  "Identical or error" stays exact. The user: "this brings back the notion of
  sealing"; the old "sealed resolution" bullet under Other options was
  reworded to avoid the clash (that was immunity, rejected twice).
- Note edits at rev 992 to 1004: core paragraph (trait world = Base + trait
  modules + what they reach, checked), rule 1, rule 6, interactivity bullet,
  "Identical or error" (refuse at the load; opt-out; code block), three
  trade-off bullets, the "may do" table (Base/any package row, Makie row,
  outward/inward door rows, sealed-package row), the rules-in-practice
  table's piracy row, "Working with existing Julia" lead, the Finer points
  closing sentence, three new Finer points subsections ("Base and the
  standard libraries", "Interface packages" with a MakieTraits sketch,
  "Sealing"), Other options (immune/sealed resolution reworded; poisoning at
  the call and an allowlist of Base added as rejected).

- Interface packages as a category of their own (rev 1008 to 1010, the
  user's correction of my reading "any trait-surfaced package is one"): an
  interface package gives trait-world code a surface to something that is
  not a trait module, Base, a standard library, a solver, Makie, and is the
  only way a trait module reaches non-trait code (rule 1 reworded and
  enforced by the check: "no interface admits X" is the error). It admits by
  the check and declares what fails. BaseInterface is implicit in every
  trait module (Base is implicit in every Julia module) and is the home of
  the door list and of the curated traits over Base's interfaces; each
  standard library gets its own interface (Distributed, Serialization with
  declared calls; Logging the home of the outward sinks). Sealing has two
  sources: a trait package seals itself, an interface package seals what it
  wraps. Tolerations live in the interface's project file, read before its
  dependencies load. Anyone may write an interface package (no methods
  added, rule 5 untouched); two for one package do not conflict; a package
  may ship an interface module for its own ordinary dependencies. The
  MakieTraits sketch was renamed MakieInterface; one table row added
  ("calling a package that no interface package admits or declares: no").
- The user asked for a Fable review with a clean context window of the
  whole note for reasoning errors (the fable-critic agent, on a markdown
  export of the note at rev 1010); its report goes to
  `session-notes/2026-10-14-17-fable-review-of-note-rev1010.md`.
- The user asked for an implementation plan for a new proof of concept that
  demonstrates the interactive experience and AOT compilation with interface
  packages around DataFrames.jl and Makie.jl, reusing earlier work:
  `writeup/poc3-plan.md` (two demos with measured steps, deltas on
  TraitWorld, packages under `poc/interfaces/`, milestones M0 to M9,
  carry-over from TraitWorld, poc/world, ecosystem/ColPlots and ChurnStorm,
  the August harnesses; `binary/` not revived; risks; decisions for
  review). The user accepted the DataFrame projection (`Tables.columntable`,
  shared columns) and asked for the piracy-refusal approximation to be
  explained; the plan now says: a package callback after the load deletes
  untolerated pirate methods and throws (no call sees a pirate; the package
  stays loaded and broken; one recompile), tolerations read before loading,
  refuse-then-tolerate in two processes, `check_no_piracy()` in a package's
  tests for the precompile-time check, and a method-insertion hook in the
  runtime as the step after the PoC. The user confirmed: fake the refusal on
  stock Julia now, patch Julia later. The plan says in §1 that the packages
  are the real DataFrames.jl and CairoMakie, not the note's toy.
- Repository cleanup (user: "move stuff no longer relevant into the
  attic"): `attic/` mirrors the old root layout (Background, TraitRegions,
  ecosystem, binary, rung2, spike, reviews, poc/{concrete, errorsplit,
  reprparam, verifymain}, writeup/trait_regions_discourse_draft.md,
  session-notes/design-observations.md), with `attic/README.md`; 149 git
  renames, `.gitignore` updated for `attic/binary/julia/`; a layout note at
  the top of `writeup/design-findings.md`. Local copy of the note:
  `writeup/traits-for-better-julia.md` (rev 1010 export). Folders for the
  next PoC under `poc/interfaces/` with placeholder packages and a README.
  `session-notes/00-environment-and-workflow.md` rewritten for the current
  layout, with an index of the dated notes. Nothing committed.

- Fable review of the note at rev 1010 (session note 17): 16 findings, all
  accepted, folded in at rev 1013 to 1019. The resolutions that are design
  decisions, taken by me and flagged to the user: (1) a load that seals also
  checks the session as it stands, so a pirate loaded before the seal is a
  conflict too, refused in strict mode (the sealing load fails, naming the
  pirate) and tolerated with a warning and a recompile otherwise; "no call
  ever sees a pirate" became "no call sees a pirate that was not tolerated".
  (2) The place of refusal is where methods enter the table: for an image,
  before any insertion, which needs a transactional image load (added to
  trade-off 8); precompile-time refusal is an early warning only, since
  compile caches are shared across environments (verified by the reviewer
  in base/loading.jl). (3) CompiledCall: a compiled-call worker infers into
  the function and lives outside the library's cache; a library that makes
  it a function's default gives up goal 1 for that function; "the library
  has no stake" became "the library's cache has no stake"; the principle
  now says code never crosses into the cache. (4) Rule 6 defines the view
  of an implementation written in the session: the trait package's view
  plus the implementation's own methods, not Main's imports. (5) The
  dispatch check is ownership-based, as the prototype's audit already is: a
  dynamic site accepts a method owned by a trait-world package that owns
  the function or an argument type, so a downstream trait module's method
  for its own type is accepted and the restriction the reviewer feared does
  not arise. (6) Admission at the entry: a type that decides (deeply
  concrete) by its type; a type that does not (a field declared Real,
  Vector{Any}) has its abstract parts walked, at a cost concrete mode
  reports; representations must decide by type. The Config example stands.
  (7) Parametric families: an instantiation with an abstract parameter
  (Series{Real}) is refused at the entry by its type. (8) The door check
  covers static paths; a dynamic site's target is checked when it compiles;
  concrete mode reports the sites. Also fixed: open Callable result types
  as a second exception; tolerance lists unioned; supertraits taken out of
  the extensions; keywords in a fourth Callable parameter K; 4 ns measured
  (not "open"); 19 ms first calls (not 9–10); the 110 ns entry cost stated;
  "types cannot multiply compile cost" and goal 1 qualified to projections;
  trade-off 9 vs 1; --trim default fails the build; remotecall_fetch; "the
  prototype checks every row" narrowed; the sysimage's standard libraries
  in every view; "as a bare value" in the table; the sorter/body
  compilation stated as Julia does it; hasmethod's weakness with kw....
  Not changed: the reviewer's unverified list (the 74× and "a few ms"
  target are the prototype's own numbers and a target).

## Open points

- TraitWorld does not implement forms 1 and 2 (field and method inference),
  families of user types, keyword, optional and vararg arguments in
  trait-bounded functions (it rejects the last three), the Callable mode
  parameter, the global check and door list, interface packages, declared
  calls and handles, or sealing; its layering check stops at Base. Its
  dispatch check is ownership-based, which the note now states as the rule.
- The cost of a dynamic `Callable` call is not measured.
- The completeness of the door list is the one curated assumption.
- Syntax for declared calls and handles (`@call`, `@handle`) and for
  tolerating a pirate (`tolerate!`) is a sketch.
