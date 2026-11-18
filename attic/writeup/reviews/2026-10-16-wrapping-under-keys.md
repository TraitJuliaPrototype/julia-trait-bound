# Review: code written without traits, under keys and the runtime as methods

Reviewer's scope: `writeup/notes/3-wrapping.md` in full; the parts of `1-overview.md`, `2-design-choices.md` and `4-details.md` it relies on (rules 1–4, ownership, the boundary principle, Callable, Dynamic values, "Types that only convert"); `decisions.md`, `open-issues.md`; session notes 22 and 23. Code read: `TraitWorld/src/{entry,calls,doors,wrapper,sealing,ownership}.jl` and parts of `implement.jl` and `trait_module.jl` (TraitWorld `main` at 8407e1c; it moved from d65bb57 during the review, and the filter experiment was re-run on 8407e1c); `julia-1.13/src/gf.c` (the insertion half of the filter); `TraitMakie` at 937f62c; `TraitDifferentialEquations` at 0bd2ffb (the Rodas5 step with `LDual`, committed after session note 23); `experiments/interfaces/{DataFramesWrapper,StaticArraysCoreWrapper}`.

**Verified** means a source quote or an experiment run here (scripts and outputs in the appendix). **Reasoning** means an argument I did not run. Three experiments ran, each alone, niced, under the shared lock.

## Verdict in one paragraph

The wrapping note was written for a design in which library code saw only representations: plain data of trait-world types. Under keys, library code is compiled for the implementing type and the declared fields' types, and these are very often the user's own types. That changes what "above" and "below" mean. Rule 4 already says so ("a call sees the owners of … the types in its keys"). The overview, the wrapping note and the runtime still say the old thing ("nothing that happens above can change what it computes"). The patched filter implements the old premise. As a result it returns stale results when a user redefines its own implementation (F1, verified). The same shift explains most of the other findings. Foreign values no longer enter through projections. In practice they come in through conversions in a library's ordinary layer, a route the notes do not describe (F5). User implementations are in an undefined layering position (F2). Family conformances over Base's abstract types silently ignore their members' owners (F3). Sealing has no answer yet for pirates that sit behind calls upward but pirate Base (F4). Nothing here refutes the layering idea. The fixes are mostly to say precisely who is in a key's view, and to make the runtime follow that.

## Findings, ranked by damage to the thesis

### F1 (critical, verified). The patched filter keeps trait-world code stale when the owner of a type in its key redefines its own code

**Evidence.**
- `julia-1.13/src/gf.c:2169–2179` states the filter's premise: "a definition elsewhere, for the definer's own types, can never apply to trait-world code (layering: no value of an outside type reaches it)." `TraitWorld/src/wrapper.jl:102–107` repeats it.
- `tw_protected` (`gf.c:2257`) skips an invalidation in two cases: the code instance belongs to a registered trait module, and the new method's definer owns a top-level type of its own signature. It never asks whether that type occurs in the code instance's key.
- Under keys the premise is false by design. In `1-overview.md:150`, `Ramp` "implements the operations, so its bound sees `Ramp`, and Columns' functions are compiled once for it". `4-details.md:97` says that "a call sees the owners of its function and of the types in its keys". `3-wrapping.md:183` promises "redefining your own code all work as today".
- **Experiment** (`filter_redef.jl`, `filter_helper.jl`): a trait module `KCols` with `kmean(t::KTable, i)`. A user type `KRamp` in `Main` implements `kcol` itself. Then:

  | | stock 1.13.2 | patched 1.13.2 |
  |---|---|---|
  | `kmean(r, 2)` before | 4.0 | 4.0 |
  | after the owner redefines `kcol(r::KRamp, i::Int)` (plain Julia: 40.0) | 40.0 | **4.0** (1 invalidation skipped) |
  | after the owner adds a more specific `kcol(::KRamp2, ::Int)` (plain: 400.0) | 400.0 | **4.0** |
  | after the owner redefines its own helper that `kcol` calls (plain: 40.0) | – | **4.0** |

**Why it matters.** This is a silent wrong result, the one outcome "identical or error" excludes. It happens in the documented `Ramp` pattern, in the Revise and REPL workflow the design promises to keep, and on the build the demonstrators are measured with. The same mechanism reaches Base specializations at user key types, by reasoning. Take a worker for `data::Vector{MyNum}`: `sum` is invalidated when the user redefines `+(::MyNum, ::MyNum)`, but the worker that calls `sum` is protected and keeps the old code. TraitWorld's 346 tests pass on the patched build because none redefines an implementation. The same pattern appears in a decision taken while this review ran. Which functions keep a trait object is "decided once, when the trait module is complete", and "a method added at the prompt to a callee that keeps does not update its callers' flags" (`open-issues.md` §3.2, commit c21ed59). Each such decision fixed at completion needs a rule for the owners' later redefinitions.

**Correction.**
- *Runtime:* make the filter key-aware. Protect a code instance only if the definer owns no datatype that occurs, at any depth, in the instance's `specTypes` (the `TObj`/`View`/`Key` parameters included). That is rule 4's view, "the owners of … the types in its keys", applied at insertion. The load half needs the same test. The same test also covers the machinery: code in TraitWorld specialized on a user's type should not be protected against that type's owner. Today that safety rests on an unchecked invariant ("registries hold no edges", `decisions.md:77`).
- *Notes:* replace `1-overview.md:66` ("Compiled code in the trait world depends only on what lies below it, so nothing that happens above can change what it computes") with: "Code compiled for a key depends on the trait world below it and on the owners of the key's types. Only they can change it, and it lives with them (rule 4)."
- Qualify `4-details.md:106`, "loading a package can never change what code in the trait world computes": "… except the owners of the types in its keys and their delegates, whose changes recompile it as today".
- Add a test that redefines an implementation at the prompt.

### F2 (high, verified). User implementations written in ordinary modules have no defined place in the layering

**Evidence.**
- `4-details.md:255`: "the methods are trait-bound code wherever they are written". `4-details.md:315`: "Layering: the methods' code stays in the trait world (rule 1)".
- Against that, `4-details.md:11` (Terms): "Trait world. Every trait module and every wrapped package". `4-details.md:73`: "What trait modules call: trait modules and wrapped packages". `4-details.md:80`: "Code from above reaches the trait world only as values handed down".
- The prototype accepts an implementation in `Main` that calls the user's own ordinary helper (`filter_helper.jl`: no refusal at `@implement`, none at the first call). The worker check stops at the operation call (`checks.jl` `_layering!`: "the machinery: … operations … continue"). It never inspects the implementation.

**Why it matters.** Under keys, implementing a trait by methods is one of the two main forms; forwarding is the other. The notes make three claims that cannot all hold. (a) User implementations are trait-world code, so they may not call the user's own functions. (b) They are ordinary code, so code from above reaches workers statically. (c) The trait world consists of trait modules and wrapped packages. F1 is the runtime consequence of not choosing.

**Correction.** Choose (recommended): "A conformer's package is in the view of its own keys. An implementation may call the trait world and its own package's functions, and these are checked the same way, transitively. A call into any other package from an implementation is refused (rule 1)." Then:
- `4-details.md:11`: the trait world for a key includes the owners of its types.
- `4-details.md:73`: add "and the implementations of the types in its keys".
- `4-details.md:80`: add "and, for a key, the implementations its owner wrote".
- TraitWorld checks implementations at `@implement`.

The alternative, implementations only inside trait modules, is simpler to check. But it would make every user who implements by methods write a trait module.

### F3 (high, verified). Family conformances over Base's abstract types ignore later methods by the members' owners

**Evidence.**
- `3-wrapping.md:38`: `@implement Indexable A where {A <: AbstractVector}`, with Base's families as the answer to "explicit conformance is viral" (`2-design-choices.md:79`, `:403`).
- `4-details.md:197`: "An override belongs to the conformance … A method of a trait's operation for a type whose conformance already serves that operation by a default is refused when it is defined."
- `TraitWorld/src/implement.jl:533`, `(T isa DataType && isconcretetype(T)) || return (b = nothing, recs = ())`: families record no defaults, so `check_overrides` never sees their members.
- **Experiment** (`family_override.jl`, stock 1.13.2): a trait `KSz` with a defaulted `kdesc`, conformed by the family `A <: AbstractVector`, and a user subtype `MyV`. After `KF.kdesc(v::MyV) = "mine"`:
  - the method is accepted;
  - `check_overrides()` is empty;
  - plain `kdesc(v)` is `"mine"`, while `report(v)` still returns `"size 3"`.

**Why it matters.** Family declarations reach types whose owners never opted in, and the overwhelming majority of them are defined after the family. The rule as written would refuse ordinary Julia methods for such types. The prototype instead disagrees silently. Neither is acceptable. With capability traits over Base's own functions the case is common, because users define `Base.length`, `isempty` and `iterate` for their subtypes all the time. A further hole: a member's `T = eltype(Self)` read through the slow path is cached by `GENERATION`. A later `eltype` method by the owner needs `refresh!()` (`entry.jl:73–82`), so an associated type can change under compiled code.

**Correction.**
- State in `3-wrapping.md` ("Traits over existing functions"): a trait whose operations are existing functions gives them no defaults, so that Base's methods, fallbacks included, are the implementation. That is what "take Base's documented interface at its word" (`:46`) means.
- For defaults in families generally, emit the default as a method at the family's bound (`kdesc(v::AbstractVector)`). Julia's dispatch then picks an owner's more specific method, and F1's key-aware filter recompiles the worker.
- Defining equations of family members are evaluated per member at the worker's compilation and invalidated with the owner's methods, not cached by generation.

### F4 (high, verified from sources and session 23). Sealing and calls upward make contradictory promises about pirates of Base behind calls upward

**Evidence.**
- `3-wrapping.md:156`: "Audited, not sealed. What lies behind declared calls is in no view, so its pirates change no trait-world code." But `3-wrapping.md:203` concedes that "OffsetArrays' 12 methods and one deprecated StatsBase method are on Base's functions at Base's types, refused or tolerated in every session that loads them". Both sit in Makie's tree, behind the calls upward.
- Session note 23, row 7 (`:81–83`): loading CSV, DataFrames and CairoMakie invalidates 2–4 ODECore methods and 323 machinery methods on the patched build. "The loads bring pirates of Base … which invalidate by design."
- The patched build has no refusal hook (`julia-1.13/TRAITWORLD.md` lists only the two filter halves). `runtime.md:22` lists the hook as not built.
- Claims that ignore this: `1-overview.md:149` ("Loading CairoMakie afterwards changes none of it"); `4-details.md:646` (`using CairoMakie … changes none of its code`); TraitDifferentialEquations' README row 7 prediction ("identical; 0 trait-world invalidations") and its success criterion "row 7 stays at zero".

**Why it matters.** The calls-upward story is the design's answer to Makie, and Makie's tree pirates Base. Base is sealed in every trait session (`3-wrapping.md:195`). In strict mode, Makie therefore cannot be loaded next to any trait module. In the default mode, the pirate recompiles what it touches, which is plain Julia with a warning. So the zero-invalidation prediction for row 7 is unreachable with this load set under the design's own semantics, not only under today's runtime. The note's summary sentence (`:211`), "it lands mostly on split cores, which wrappers resolve", is contradicted by the first realistic session the demonstrators measured.

**Correction.**
- Replace `3-wrapping.md:156`: "Calls upward exempt a package from sealing, not its pirates. A pirate of Base, or of any sealed package, that sits behind calls upward is refused or tolerated like any other. Its pirates of unsealed packages change no trait-world code."
- Qualify `1-overview.md:149` and `4-details.md:646`: "unless a pirate of Base in CairoMakie's tree touches what it compiled against (13 methods today, tolerated by default)".
- Change TraitDifferentialEquations' row-7 prediction to "0 invalidations from owned methods; pirates tolerated with a warning".
- Make the pirate-free load set the acceptance test, as session 23's Next §1 suggests.

### F5 (high, reasoning plus sources). Under keys, the wrapper's role for foreign *types* is unclear, and the practical route for foreign data is not documented

**Evidence.**
- `3-wrapping.md:78`: a wrapper holds "Conformances and doors: which of the package's types conform to which traits". `4-details.md:94` (rule 3): "A package written without traits is owned in the trait world by its trait wrapper".
- The prototype did the opposite. In `experiments/interfaces/DataFramesWrapper/src/DataFramesWrapper.jl:2–5`, a DataFrame enters "through the projection in Columns' own extension … (rule 3: a wrapper owns neither the trait nor the type)". `TraitWorld/src/ownership.jl:200–208` never treats the wrapper as owner; only the named delegates count.
- Keys removed the projection that route used (`decisions.md:32`). A DataFrame cannot forward: its columns are a `Vector{AbstractVector}`. Two routes remain:
  - An implementation per foreign type. It calls DataFrames' code, so DataFrames must be admitted by the check. Every column access is then a dynamic site whose targets are methods of column types from unwrapped packages (SentinelArrays, PooledArrays, InlineStrings), which rule 4 makes raise (`4-details.md:99`).
  - Explicit conversion (`4-details.md:582–594`). As written there, `colmean_any(t::TableLike, i)` converts *inside* the trait world, through `column(t, n)::AbstractVector`, so the same dynamic sites appear.
- What the demonstrator actually does (`TraitMakie/src/TraitMakie.jl:70–84`): `_xy(x, y) = hcat(Vector{Float64}(x), Vector{Float64}(y))` in the *ordinary* layer, then the bound.
- `2-design-choices.md:80` answers "viral" with "trait wrappers that declare for a whole package". `2-design-choices.md:120` introduces "an implementation its wrapper's delegates write". Neither has a counterpart in `3-wrapping.md`.

**Why it matters.** Under keys, foreign containers with their own layout (DataFrame, StructArray, a CSV.File) have three options: compile the library per foreign type, which needs the foreign package admitted and is unlikely to pass; convert inside, which has the same problem; or convert above. Only the last works today, and it needs no wrapper and seals nothing. If wrappers also declare conformances, each data package's wrapper must depend on every trait library: N×M dependencies, with "one wrapper per package" making it a coordination problem.

**Correction.** Rewrite "What a wrapper holds" and add a subsection "Foreign values under keys":
1. **A wrapper admits, seals, names delegates and lists doors.** It does not declare conformances to other packages' traits. Those come from the trait owner, as a package extension triggered by the foreign package, or from the foreign package when it adopts traits. A wrapper declares conformances only to traits it owns, as the capability traits of the Base wrapper.
2. **The four routes for a foreign value,** cheapest first:
   - (a) conversion in the library's ordinary layer, or in its package extension for the foreign package (`TraitMakie._xy`): any input, compiled per input type above the cache, no wrapper, nothing sealed;
   - (b) an implementation or a reading trait inside, only for types whose access code is in the trait world (wrapped, or trait-world types);
   - (c) a handle with a declared call that converts (`@call to_columns(h)::Vector{Vector{Float64}}`);
   - (d) a handle that implements a trait by declared calls (the pattern of `solvers.md:282` for GPU arrays, not in the notes).
3. In `4-details.md` "Types that only convert", say where the conversion runs, and present (a) as the default for foreign data.
4. Reword rule 3's "owned … by its trait wrapper": the wrapper speaks for the package in the trait world only to name delegates and tolerations, which is what the prototype does.

### F6 (medium). Results of calls upward and of functions from above with a trait bound cannot be "translated as an argument's bound would"

**Evidence.**
- `4-details.md:533`: "Results of a function from above are values crossing downward, so the result bound translates them as an argument's bound would." `4-details.md:529`: `tables(f::Callable{Tuple{Int}, ColTable}, n::Int)`. `3-wrapping.md:105`: "the result translated by its bound".
- The prototype allows only `Nothing`, handles and deeply concrete results (`calls.jl:156`).

**Why it matters.** An argument's bound works because the entry selects the worker per key before the body runs. A result arrives inside a worker that is already running, at a key nobody knows statically. Under keys the trait object's type carries the key, so code after the call cannot be compiled for it.

**Correction.** "A trait bound on a result from above makes a `Dynamic{X}`. Pass it to a bounded function to run compiled per key." The same rule then covers `@call …::ColTable`.

### F7 (medium). Opaque values handed down: the solver demonstrator relies on what the notes forbid

**Evidence.**
- `4-details.md:140`: "An exported function's argument without a bound takes trait-world values only, so a user type passed there runs as ordinary code (rule 1)."
- In `TraitDifferentialEquations/src/ODECore.jl:310`, `solve_ode(m::ODEModel, …, p, …)` takes the user's `p` unbounded. At `:315` it stores it as `Tsit5Integrator{Float64, typeof(p)}`, and callbacks read it through `IntegratorView{T, P}`'s `p::P`. Nothing checks it: unbounded arguments pass through the entry as they are (`trait_module.jl:556`).
- Two definitions of "trait-world value" disagree. `3-wrapping.md:58–61` defines it by parts ("a value with parts is one when all its parts are"). `entry.jl:519–524` (`_tw_type`) defines it by the defining module (`is_trait_world(T.name.module) || return false`).

**Why it matters.** SciML's `p`, Makie's user attributes and any "user data" slot are values that the library stores and hands back up, but never operates on. The design has the upward mirror of this, the handle, and no downward one. By the parts definition, a user struct of `Float64`s is a trait-world value, yet its methods are code from above. By the module definition, ODECore's interface breaks.

**Correction.** Name the category. "An opaque value is a value from above held at an unbounded argument or an unbounded associated type. Library code may store it, pass it on and hand it up, and calls nothing on it; definition checking enforces this, since an unbounded archetype has no operations. Its type is part of the key." Then state the definition of trait-world value once, by owning module, as `_tw_type` does, and delete the parts definition. The alternative, requiring a handle built in the ordinary layer, compiles the solver once for all `p` types, but costs an unwrap at every call upward.

### F8 (medium, verified from code). Sealing does not yet fit conformances as methods, or keys

**Evidence.**
- TraitWorld is never sealed (`sealing.jl:25`, `SEALED = ["Julia"]`). `_pirate_of_sealed` requires every owner in the signature to be sealed (`sealing.jl:149`). So a stranger's hand-written method of `conformance`, `needed` or a registry, whose signature always involves TraitWorld, is never reported.
- Under keys, conformers are in views (`4-details.md:97`), and `3-wrapping.md:162` says "every package in a worker's view is sealed by the load that brings it there". But only trait packages and wrapped packages are sealed (`calls.jl:121–123`). A third party's `Columns.col(::UserPkg.Ramp, ::Int64)` therefore goes unreported. It invalidates normally, since the filter treats it as a pirate, so it changes results with no warning.
- Two stakeholders that both declare `@implement ColTable T`, say the trait owner's extension and the type's owner, now define the same `conformance(::As{ColTable}, ::T)` method. Nothing checks this at load (`_on_package_load`), so the later load wins. This brings back `design-findings.md:56`, "Overlapping seals override each other silently". `4-details.md:54` says "the design reports it at load".
- Rule 3 says ownership "can be delegated by its owner, never claimed" (`4-details.md:93`), yet a third-party wrapper names delegates (`:94`). The note does not reconcile the two.

**Correction.**
- Seal TraitWorld from the start, as Julia is. Judge machinery methods by their `As{X}` and `EntryPos{F}` parameters, which `_owners!` already does.
- Seal a conformer's package when its first conformance loads, or say explicitly that it is not sealed and why.
- Scan new `conformance` methods at each load for duplicate signatures from different packages.
- Say that a wrapper's naming of delegates is a claim the environment accepts by choosing that wrapper, one per package. That is the actual mechanism.

### F9 (medium). The walk of abstract parts at the entry contradicts the reference layout and is not implemented

**Evidence.**
- `3-wrapping.md:64`: a type that does not decide "has its abstract parts walked by the entry, at a cost proportional to them". The same at `4-details.md:161`, `2-design-choices.md:357`.
- Against it, `decisions.md:34`: "No snapshots, no exit check". Under keys, a trait object reads the user's object at every access, and a `Dynamic` keeps it.
- The prototype walks nothing (`trait_module.jl:556`).

**Why it matters.** A walk at the entry is a snapshot. A callback called upward, or code above holding the same object, can put a value from above into a `Vector{Any}` or an abstract field after the walk. The only guard that holds across time is the dispatch check at dynamic sites (rule 4, `4-details.md:99`).

**Correction.** Drop the walk. "A value of a type that does not decide is admitted, and every dynamic site that reaches its abstract parts checks the target (rule 4). Concrete mode reports the argument type."

### F10 (medium). Automatic differentiation and package-defined numbers: what TraitDifferentialEquations needs is not in the notes

**Evidence.**
- `2-design-choices.md:55`: "`Float64` and `Measurement{Float64}` are trait-world values by their types". `4-details.md:413`: "Numbers are trait-world values by their types". But `Measurement` and `ForwardDiff.Dual` belong to packages written without traits. Their arithmetic is their packages' code, so they are trait-world values only if those packages are wrapped (rule 1).
- In `ODECore.jl` at 0bd2ffb (the decision is `decisions.md:62`, "ForwardDiff joins the trait world later through a trait wrapper"), Rodas5 uses a library-owned `LDual{N} <: Real` (`:87–133`). It holds two `DynamicFn`s at signatures the ordinary layer fixes from data, `N = min(length(u0), 8)` (`TraitDifferentialEquations.jl:64–68`, `FunctionModelAD{P, N}`). And `jacobian!` is a defaulted operation (`ODECore.jl:24`).
- `4-details.md:235` rejects "a type conforming at several values of a parameter". A model type that implements `rhs!` itself conforms at `ODEModel{Float64}` only, so the solver cannot call its `rhs!` with duals. Route A gets finite differences unless the user implements `jacobian!`. Doing that with ForwardDiff is a call into an unwrapped package (F2).
- A ForwardDiff wrapper would seal ForwardDiff's dependency closure. That includes StaticArraysCore (through DiffResults) and ChainRulesCore (through SpecialFunctions), both verified from the local `Project.toml` files. So it needs the StaticArraysCore wrapper whenever StaticArrays loads (the 794 methods of `3-wrapping.md:199`). It would also need a ChainRulesCore wrapper naming ChainRules as a delegate. DiffEqBase's `nextfloat(::Dual)` pirate becomes a refusal (`solvers.md:329`).

**Why it matters.** The library-owned dual works, and it is a clean example of the design. But the notes describe none of its parts: library-owned numeric types as the trait world's AD, `DynamicFn` at several signatures chosen in the ordinary layer, and the extension-point operation (`jacobian!`) instead of calling the model at another element type. Meanwhile the ForwardDiff wrapper, planned for later, pulls in two split-core wrappers through sealing.

**Correction.**
- Fix `2-design-choices.md:55` and `4-details.md:413`: "Base's numbers are trait-world values by their types; a package's numbers are, once the package is wrapped."
- Document `DynamicFn` and `dynamic_fn` in `4-details.md` "Function arguments", with the multi-signature `FunctionModelAD` pattern. This answers open issue §2.10 for the case where the ordinary layer can compute the signature.
- State that a model's own element type is one value per conformance, so a solver differentiates through an operation (`jacobian!`), not by calling `rhs!` at another `T`.
- Record the ForwardDiff wrapper's sealing closure in `solvers.md` §11.

### F11 (low to medium). Smaller stale or inconsistent statements

- `4-details.md:308`, form 7 "a family declaration | Compiled anew: nothing". Under keys each member is its own implementing type, so the library compiles per member type, as form 2 does.
- `3-wrapping.md:56`, "Julia's package images already hold such specializations; the design adds that nothing above can invalidate them". The insertion half protects no Base specialization (session note 23, `:83`; open-issues §4.2). With user key types it should not protect them against those types' owners either (F1). Say "nothing outside the key's view", and mark it as not yet in the runtime.
- `3-wrapping.md:48` and `:93–94`: the capability traits and "the Base wrapper" do not exist in TraitWorld; only comments mention `Indexable` (`trait.jl:9`, `implement.jl:7`). The note should name their home, TraitWorld itself as the language stand-in, and say they are design only.
- `3-wrapping.md:105–108`: "at a declared signature, through a pointer". `@call` is `invokelatest` on whatever argument types arrive (`calls.jl:66`): the result is declared, the arguments are not. It is fine as a prototype; say so.
- `3-wrapping.md:197–207`, `4-details.md:649` (view caches "per key … about 3 ms") and `2-design-choices.md:136` (convert-then-plot 36 ms against the trait route 35–47 ms) cite `experiments/interfaces`, measured per representation before keys, unmarked. `keys-plan.md:156` asked for these to be marked. TraitMakie now measures 61–132 ms for a new forwarding type at the prompt (README row 4), slower than the 36 ms hand erasure.
- `1-overview.md:182–189` (Status: "311 tests", "200–460 ns … waits for a decision", "the 1.13 build is postponed", "skeletons with plans") contradicts `writeup/README.md:3`'s claim that everything is current at the end of session 23. `4-details.md:631` (entry about 215 ns) and `:693` (about 110 ns) contradict each other and the 33 ns measured (`decisions.md:80`).
- `README.md:10` labels 3-wrapping "deferred while the demonstrators are built". Calls upward, handles and `DynamicFn` are in active use by both demonstrators. Move "Calls upward" into `4-details.md` and leave wrappers and sealing deferred.
- `3-wrapping.md:69`, "for a solver, most of `solve`", passes the check. No solver was ever wrapped; mark it as a prediction.

## Answers to the five questions

### Q1. Wrong or stale statements

| Where | Statement | Status | Finding |
|---|---|---|---|
| 1-overview:66 | "depends only on what lies below it, so nothing that happens above can change what it computes" | wrong under keys; the runtime implements it, wrongly | F1 |
| 1-overview:149; 4-details:646 | CairoMakie "changes none of it" | overclaims (Base pirates in its tree) | F4 |
| 1-overview:182–189 | Status | stale | F11 |
| 2-design-choices:55; 4-details:413 | `Measurement{Float64}` a trait-world value by type | wrong (needs a wrapper) | F10 |
| 2-design-choices:80, :120 | wrappers or their delegates declare foreign conformances | inconsistent with 3-wrapping and the prototype | F5 |
| 2-design-choices:136 | convert-then-plot vs trait route | pre-keys, unmarked | F11 |
| 3-wrapping:38, :46, :48 | Base's families, "checked when declared" | no override protection; capability traits absent | F3, F11 |
| 3-wrapping:56 | "nothing above can invalidate them" | not in the runtime; wrong for user keys | F1, F11 |
| 3-wrapping:58–61 | trait-world values by parts | conflicts with `_tw_type` and with ODECore's `p` | F7 |
| 3-wrapping:62–64 | arguments "translated", abstract parts "walked" | keys take the user's object; walk is a snapshot | F9 |
| 3-wrapping:78; 4-details:94 | the wrapper declares conformances / owns the package | prototype: it owns nothing; N×M | F5, F8 |
| 3-wrapping:105; 4-details:533 | results "translated by their bound" | impossible for trait bounds without `Dynamic` | F6 |
| 3-wrapping:156 | "its pirates change no trait-world code" | false for pirates of Base | F4 |
| 3-wrapping:162 | every package in a view is sealed | conformers, now in views, are not; TraitWorld not | F8 |
| 3-wrapping:183 | redefining your own code works as today | false on the patched build | F1 |
| 3-wrapping:197–207, :211 | Makie tree audit; "lands mostly on split cores" | pre-keys; contradicted by row 7 | F4, F11 |
| 4-details:11, :73, :80 | the trait world is trait modules and wrapped packages; only values from above | user implementations are neither | F2 |
| 4-details:106 | "loading a package can never change …" | except key owners and their delegates | F1 |
| 4-details:140 | unbounded arguments take trait-world values only | contradicted by ODECore | F7 |
| 4-details:161 | Any / `Vector{Any}` "after a walk" | snapshot; unimplemented | F9 |
| 4-details:308 | family declaration compiles nothing | compiles per member | F11 |
| 4-details:631, :649, :693 | entry costs; view caches per key | stale or pre-keys | F11 |

### Q2. Does the wrapper design still work under keys?

**What breaks:**
- The route by which a foreign table shared library code (a projection to `Vector{Vector{Float64}}`) is gone.
- Conformances for foreign types now either compile the library per foreign type, which needs the foreign package's code admitted, or convert explicitly.
- Family conformances work only through the slow path, and without override protection (F3).
- The walk at the entry (F9) and translated results (F6) no longer have a meaning.
- Who declares a foreign type's conformance was already inconsistent between note and prototype, and keys force the question (F5).

**What gets simpler:**
- Wrappers never write projections or inverses.
- Overlap between a family conformance and a type's own is Julia's dispatch on `conformance` methods: the more specific wins, with no machinery.
- A new conformance invalidates no entry (`@max_methods 1`).
- Data-source packages (DataFrames, CSV) need no wrapper at all if conversion happens above (route (a) of F5). Then they are never sealed, which removes Tables' 4 and StatsBase's 3 refusals that `3-wrapping.md:204` attributes to wrapping DataFrames.
- Wrappers remain necessary only for packages whose *functions* trait-world code must call: LinearAlgebra-like libraries, StaticArrays' arithmetic, ForwardDiff's duals, SpecialFunctions.

**The pending decision** ("conversions in trait wrappers", `open-issues.md:7`) dissolves.
- An implicit conversion at a bound is a computed projection again: a hidden copy, no write-through, an inverse for `Like{t}`, snapshot semantics. Keys removed exactly that.
- A conversion *trait* implemented for a foreign type is an ordinary implementation, already governed by rule 3.
- Recommendation: close it as "no implicit conversions; conversions are explicit, by default in the library's ordinary layer".

**Handles versus values.**
- A call upward that returns a deeply concrete value is fine.
- One that returns a conforming foreign value should give `Dynamic{X}` (F6).
- Handles need two more forms the notes lack: handles with operations implemented by declared calls, and opaque values handed down (F7).

### Q3. Sealing and ownership

- **Conformances as methods fit rule 3,** because `_owners!` reads the `As{X}` parameter. A conformer's `conformance(::As{ColTable}, ::MyType)` is owned through `MyType`, and the trait owner's through `ColTable`.
- **Sealing does not yet cover them:** TraitWorld is unsealed, duplicates go undetected at load, and conformers are unsealed (F8).
- **The patched filter is the real problem** (F1). It protects trait modules and the machinery under a premise that keys falsified. The verified result is silent staleness. "Registries hold no edges" makes the protection of the *registries* sound. It does not make sound the protection of trait-module code compiled for user keys.
- **The row-7 finding is the design working as specified,** with pirates tolerated. But the notes promise more than the specification gives (F4). Two things are needed before row 7 can test the design: a pirate-free load set, and a key-aware callee rule at insertion.

### Q4. What the demonstrators needed

**Covered by the notes:**
- declared calls into code above (`@call`);
- handles (`Surface`);
- `Dynamic` values going up (`Dynamic{IntegratorView}` to callbacks);
- traits implemented for Base types by their owner (`Positions` for `Matrix{Float64}`).

**Used but not described:**
- *the shim form of declared calls,* into the package's own ordinary functions with concrete signatures (`TraitMakie.jl:18–60`). It is the better form: precompiled in the package's own image, and it isolates Makie's or Cairo's API. Recommend it in `3-wrapping.md` instead of `@call Makie.scatter!(…)` directly;
- *conversion in the ordinary layer* (`_xy`; F5);
- *`DynamicFn` and `dynamic_fn`,* including two signatures fixed by the ordinary layer from data (`FunctionModelAD{P, N}`; F10);
- *opaque `p`* (F7);
- *a library-owned dual type,* with the Jacobian as an operation (F10).

**Missing for the next steps:**
- a statement that package numbers need wrappers;
- the ForwardDiff wrapper's sealing closure (StaticArraysCore, ChainRulesCore);
- no AD route for model types that implement `rhs!` themselves, because of one `T` per conformance;
- a definition of how wrapped code calls a function from above: `ForwardDiff.jacobian!` receiving a `DynamicFn` or a trait-world closure, at signatures ForwardDiff chooses (open-issues §2.10).

### Q5. Predictions in 2-design-choices

| Prediction or cost | Stated status | Assessment |
|---|---|---|
| 1. "Explicit conformance is viral" (`:403`) | answered | Partly. The one-line form serves forwarding and own methods. Foreign layouts cannot forward, so they need per-type implementations by trait owners (N×M extensions) or conversions. Families have the F3 hole. |
| 2. Layering attacked for gradual adoption (`:404`, §5 `:201`) | answered | Designed, not shown. No wrapper exists under keys, and both demonstrators avoided wrapping entirely (calls upward, shims, ordinary-layer conversion, `DynamicFn`). That is evidence that calls upward suffice for these two libraries, not that wrapping works. The ForwardDiff case will be the first real test, and it drags in two split cores. |
| 4. Retroactive conformance answered by named implementations (`:406`) | answered | Design only (not prototyped). A named implementation for a foreign type still needs the foreign package's code admitted. |
| Cost 2: "lands mostly on split cores" (`:352`, `3-wrapping.md:211`) | – | The audit's substance stands (ownership did not change with keys). But the first realistic load set already hits real pirates of Base (row 7), and each wrapper extends the sealed set (ForwardDiff → StaticArraysCore, ChainRulesCore). |
| §3 "What is new over discipline" (`:136`) | – | Stale. Pre-keys numbers. For foreign data the keys route *is* convert-then-call, so there the trait world's gain is the checked bound and the cached library, not the per-type cost. For forwarding types, TraitMakie measures 61–132 ms, worse than hand erasure. |
| Cost 1: calls out are calls upward; time to first plot equals an ordinary module's | – | Supported by TraitMakie (0.1–0.22 s alone). Load-order dependence remains (0.31 s with CSV and DataFrames before), as open-issues §4.5 says. |
| Cost 6: curation, one wrapper per package | – | Valid; more curation under keys (F5). |

## Decisions the user would need to take

1. **Owners of key types in the view** (F1, F2). Recommended: a conformer's package is in its keys' view. The filter is key-aware. Implementations may call the trait world and their own package, checked transitively. The alternative is implementations only inside trait modules.
2. **Defaults in family conformances** (F3). Recommended: no defaults on existing functions; family defaults emitted as methods at the family's bound, resolved by dispatch. Rejected alternative: applying the override rule to family members, which refuses ordinary users' methods.
3. **Close "conversions in trait wrappers"** (open-issues §1.1). Recommended: no implicit conversions; explicit conversion, by default in the library's ordinary layer.
4. **Who declares a foreign type's conformance** (F5, F8). Recommended: the trait owner's package extension, as the prototype did. Wrappers admit, seal, name delegates and list doors, and declare conformances only to their own traits. Reword rule 3's "owned by its wrapper".
5. **Opaque values handed down** (F7). Unbounded positions as opaque, definition-checked (recommended), or handles built in the ordinary layer.
6. **Trait-bounded results from above** (F6). `Dynamic{X}` (recommended), or forbid them.
7. **Sealing scope under keys** (F8). Seal TraitWorld; seal conformers; detect duplicate conformances at load.
8. **What row 7 is to show** (F4). Strict or tolerate as the demonstrators' mode. A pirate-free load set as acceptance, and upstream fixes for OffsetArrays and StatsBase as the long-term answer.
9. **The ForwardDiff route** (F10). When to wrap ForwardDiff, accepting StaticArraysCore and ChainRulesCore wrappers. Whether route A (model types implementing `rhs!`) gets AD through `jacobian!` only, or through a new feature: operations generic in an unconstrained element type, which `4-details.md:235` currently excludes.

## Appendix: experiments

All scripts are in `/tmp/claude-1000/-home-hellmann-Repos-julia-trait-bound/6c8f1719-6fc1-42fb-a8dc-c45452eef443/scratchpad/`. They ran with `--project=TraitWorld`, niced, under the shared lock. `filter_helper.jl` and `family_override.jl` ran on 8407e1c; `filter_redef.jl` ran first on the tree in flux between 5efbb4c and 8407e1c, then again on 8407e1c with the same output.

**`filter_redef.jl`.** Patched `julia-1.13/julia`:
```
filter on: true  skipped so far: 0
before redefinition: kmean(r, 2) = 4.0   (plain: 4.0)
after redefinition:  kmean(r, 2) = 4.0   (plain: 40.0)
skipped invalidations: 1
KRamp2 before: 4.0
KRamp2 after a more specific method: 4.0   (plain: 400.0)
skipped invalidations: 2
```
Stock 1.13.2: 40.0 and 400.0, as plain Julia.

**`filter_helper.jl`.** Patched: an implementation in `Main` calling the user's own helper is accepted. After the helper is redefined, `kmean` returns 4.0 where plain Julia gives 40.0 (1 invalidation skipped).

**`family_override.jl`.** Stock 1.13.2:
```
before: report(v) = "size 3"
late method for MyV: accepted
plain Julia: kdesc(v) = "mine"
after: report(v) = "size 3"
check_overrides(): String[]
```
