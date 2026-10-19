# Review: `reference/traits.md` and `reference/lowering.md` against the code

Fresh-eyes review of the two references against TraitWorld at 227781a (`TraitWorld/src`, `TraitWorld/test`), the demonstrators, the runnable checks in `experiments/docs-examples/` and the tutorial. Method: every construct's syntax, meaning, rules and status read against the code paths that implement it, by tracing the macro expansions and the run-time paths by hand. No Julia was run (the machine is shared), so each finding says whether it is **verified by reading** the code (the path is unconditional) or **reasoning** (depends on Julia behaviour I could not execute here), and names the test that would settle it where that matters.

Line numbers: `traits.md:n`, `lowering.md:n` are the references at the reviewed revision; code lines are TraitWorld 227781a.

Severity: **high** = a statement about what is Implemented that the code contradicts, a missing or wrong Deviations row, or an example that would not run as shown; **medium** = an imprecise rule or an arguably wrong status; **low** = names, wording, citations.

Summary: 6 high, 12 medium, 11 low.

---

## High

### H1. The entry methods compiled ahead, `f(::T, …)`, are new methods of the library's function and invalidate the untyped path itself (the question the lowering agent raised)

- `traits.md:337` ("It changes no compiled code. Declaring one discards nothing."), `traits.md:865-867` (§15), `lowering.md:380-389` (§9.2 "On the untyped path nothing is compiled per user type"), `lowering.md:395-399` (§9.3).
- Code: `TraitWorld/src/ahead.jl:168-195` (`_ahead_entry!`), called from `ahead.jl:143`; the method is `f(a1::T, a2::C2, …) = invoke(f, Tuple{Any, C2, …}, …)`, `@inline`, boundary, evaluated into `T`'s module while the implementing package is precompiled, so it is part of that package's image.

Assessment (reasoning on Julia's method-table insertion; the code path itself is verified):

1. The method is inserted into `f`'s method table twice: in the precompile process and again when the image is loaded in a session. `jl_method_table_insert` invalidates every specialization of a less specific method whose `specTypes` intersect the new signature, and every caller holding an edge for an intersecting abstract signature.
2. The tabled entry is `@nospecialize` on its trait position (`trait_module.jl:551-552`), so the entry's own compiled code for untyped callers is the specialization at `Tuple{typeof(f), Any, Int}`. That `specTypes` intersects `Tuple{typeof(f), T, Int}`, and the new method is more specific there, so **the entry's `Any` specialization is invalidated by every load of a package that compiled an entry ahead for it**, together with every caller that has it as a backedge (every untyped plain caller compiled against `f` with at most `max_methods` matching methods). This is the code the table in §9.2 exists to keep stable. The library's workload compiles exactly that specialization (`TraitWorld.jl:138` does, for `_PC`).
3. Plain callers compiled at an abstract type that `T` subtypes (`g(v::AbstractVector) = f(v, 1)`) are invalidated as in plain Julia.
4. Trait code is not affected: compiled by facts, a call at an abstract type is a run-time site without an edge. Under the test bed (`all` compiled by facts) nothing is invalidated; the finding is about the product setting, where plain code is compiled plainly.
5. `_ahead_entry!` guards "types first" (`ahead.jl:177`: no ahead entry where a typed method already wins for `T`), so H1 is about invalidation, not about dispatch ranking. One ranking hole remains: a typed method on an abstract supertype of `T` defined *after* the ahead entry (by the owner, at the prompt) loses to it, against `traits.md:612`.

So the lowering agent's concern is real and larger than stated: the ahead entry does not only threaten "plain callers that inferred `f` at an abstract argument"; it invalidates the generic entry's own untyped specialization. `traits.md:337` is contradicted for the product setting.

Test that settles it (no package build needed): in a session with a library trait module whose `f(t::X, i::Int)` is tabled and a plain `g(x) = f(x, 1)`, call `g` on values from an `Any[]` loop so the entry's `Any` specialization and `g` are compiled; then `ccall(:jl_debug_method_invalidation, Any, (Cint,), 1)`, call `TraitWorld._ahead_entry!(Main, T, f, 1, 2)` directly (it does not check `jl_generating_output`; `_compile_ahead` does), stop the log, and look for the entry's and `g`'s `MethodInstance`s with `jl_method_table_insert`. Repeat with a precompiled package and `JULIA_TW_AHEAD=0` as the control. SnoopCompileCore's `@snoop_invalidations using Impl` shows the same.

Proposed fix: a Deviations row in both references (T: §5, §15; L: §9.3) stating the product-setting invalidation; and a design decision: drop the ahead entry (the pattern method already gives untyped callers code compiled once per key, with nothing new in `f`'s method table), or make it something that is not a method of `f`.

### H2. Families are not checked at the declaration, and families with a block are never checked

- `traits.md:454` ("It is checked for the family as a whole: the methods must cover the family, with results that infer to the declared types."), `traits.md:511` (§5.10 "Results", "All of these run at `@implement`"), status `traits.md:465` (Implemented except T-5, T-6, T-7).
- Code, verified by reading:
  - at the declaration, every family path passes `()` as the given operations and a non-concrete `R` to `_check_implementation` (`implement.jl:1051`, `:1103`, `:1129`), and `_check_implementation_now` returns after the ownership checks when `R` is not concrete (`implement.jl:514`: "families and generic implementations are checked per type"); the joint-family-by-fields path (`implement.jl:1256-1272`) runs no check at all;
  - at a member's first use, only a family declared by existing methods (`ImplRec(:family, ())`) has its operations checked, and a failure is a `@warn`, not an `ImplementError` (`implement.jl:345-349`; `_family_builder`, `:733-735`, then keeps the member on the slow path);
  - a family with a block is `ImplRec(:methods, D)` and `_witness` returns `Impl{D}()` without any check (`implement.jl:342`). `@implement KVec A where {A <: Vector{<:Real}} begin kget(v, i) = string(v[i]) end` is accepted and fails only at a call, as a `TypeError` from the result assertion in `opcall`.
- The tutorial's §13 family (`traits-by-example.md:450-453`) is of the unchecked kind; the test `runtests.jl:284-289` documents the warning behaviour for existing-method families.

Proposed fix: status "Planned" for the family-wide check with two Deviations rows: (a) no check at a family's declaration beyond ownership; (b) members of existing-method families are checked at first use with a warning, members of block families never. `lowering.md:187-190` already says "checks its operations (a family of existing methods)"; make traits.md agree.

### H3. A later declaration for one member of a declared family is refused (block) or defines no `conformance` method (one line)

- `lowering.md:192` ("A later declaration for one member is a more specific `conformance` method."), `traits.md:455` ("The package that owns a member's parameter type … may define an override for that member until then").
- Code, verified by reading: `_has_conformance_method(X, T)` (`implement.jl:656-661`) answers true whenever the most specific `conformance` method for `T` is not the fallback at `Any`; for a member `S{Int}` of a declared family, that is the family's method `conformance(::As{X}, u::S{P}) where P`, whose third signature parameter is `S{P}`, not `Any`. Hence:
  - `@implement X S{Int} begin … end` after `@implement X S{P} where {P}` is refused by the redeclaration check (`implement.jl:946-954`, `:970-976`: "already conforms to X: an implementation is not redeclared in a session");
  - `@implement X S{Int}` (one line) is accepted but skips `_conformance_methods` (`implement.jl:1192`), so no `conformance`, `_declared_builder` or `_declared_defaults` method exists for the member; it is served by the family's slow path (`_conf_family_slow`), which happens to find the member's `implementation` record. The untyped table then marks it untabled (`untyped.jl:76-86`).
- The test `keys_syntax.jl:135-136` covers only a plain method defined before first use for an existing-method family, not a member declaration.

Proposed fix: either fix `_has_conformance_method` to compare the found method's signature parameter with `T` (as `_umiss` does at `untyped.jl:76`), or a Deviations row in both references and "Planned" for the member override in traits.md §5.7.

### H4. Redeclaring a one-line, `by` or mapped implementation is accepted silently and keeps the first declaration's builder

- `traits.md:524` (status: "today a second declaration in a session is refused, naming the reason"), `traits.md:520`, `lowering.md:222`.
- Code, verified by reading: the redeclaration check runs only when the last argument is a `begin … end` block (`implement.jl:946`, `:970`). For the other forms the expansion redefines `implementation`/`projection` (same-signature methods replace the old ones) and skips `_conformance_methods` when a `conformance` method exists (`implement.jl:1192`, `:1371`). So `@implement ColTable Halves by right` followed by `@implement ColTable Halves by left` is accepted: `projection(ColTable, Halves)` and `conforms` now say `left`, while `conformance`, `_declared_builder` (the untyped table) and `_declared_defaults` keep the builder for `right`. A one-line redeclaration re-runs the checks and otherwise changes nothing.

Proposed fix: a Deviations row ("accepted with another meaning"); extend the refusal at `implement.jl:943-955` to every form, until redeclaration is built.

### H5. "Forwarding carries through" a generic implementation is not implemented

- `traits.md:481` ("A type that forwards `Indexable` to a field forwards `GTable` to the same field."), status `traits.md:489` says only that it "is not covered by a test".
- Code, verified by reading: a `by` declaration defines a `projection` record and no `implementation` record (`implement.jl:1363-1366`). For `U` forwarding `Indexable` to `data`, `proj_lookup(GTable, U)` (`implement.jl:414-424`) finds no projection and asks `witness(GTable, U)`; `_witness` (`implement.jl:337-367`) needs `witness(Indexable, U)` for the constraint, which is `nothing` (no `implementation` method, no generic key), so the generic record does not match and `U` is `NOTRAIT` for `GTable`: `MethodError` at the call. Only an explicit `@implement GTable U by data` works (then the field type's generic witness is found).

Proposed fix: status Planned with a Deviations row; or implement by letting `proj_lookup` fall back to the constraint traits' projection when all constraints forward to the same field.

### H6. A parametric trait's `Dynamic` does not fix the result types of its operations

- `traits.md:733` ("A parametric trait's `Dynamic` fixes the parameters its operations' result types use, `Dynamic{StateVector{Float64}}`, so code after a call infers."), status `traits.md:754` Implemented.
- Code, verified by reading: `trait.jl:303-304` computes `retx = dep(d.ret) ? :Any : d.ret` at macro time, where `dep` is true for any result naming `Self` or a parameter, and the method `op(dyn::Dynamic{X__}, …) where {X__ <: name}` asserts `::$retx` (`trait.jl:314`, `:318`); the compiler's split types its join `RT` and asserts the fallback to it (`julia-1.13/Compiler/src/facts.jl:437-466`). So `sample(d::Dynamic{Samples{Float64}}, 1)` infers `Any`, whatever the `Dynamic` fixes. `lowering.md:499` states the truth ("or `Any` where it names `Self` or a parameter"), so the two references disagree.

Proposed fix: a Deviations row in traits.md and Planned; or compute the asserted type from `X__`'s fixed parameters (a generated or `@constprop` path that reads `Dynamic{StateVector{Float64}}`'s parameter when it is not a variable).

---

## Medium

### M1. "Registries read without edges" holds only when more than one method applies

- `lowering.md:109` ("Code compiled at an abstract argument infers nothing from a record's methods and holds no edge to them."), `lowering.md:649` (§17 row), L-4 (`lowering.md:664`), and `entry.jl:17-20`.
- Reasoning on `@max_methods 1`: inference drops edges when the number of applicable methods exceeds the limit; with exactly one applicable method, the sentinel, it infers it and records an edge for the abstract signature. Cases: a tabled entry's `conformance(As{X}(), ::Any)` compiled (inlined into a plain caller, or in the library's workload) while `X` has no declared implementation yet; a specialized entry inlined into a plain caller at an abstract type no declared implementation's type intersects; `keeps`/`needed` before the module's end (intended, the module redefines them). The first declared method intersecting the signature invalidates that code.
- Also: about half the record functions have no sentinel method at all (`param`, `param_bound`, `field_type`, `_fieldmatch`, `_fieldpos`, `op_function`, `op_args`, `op_ret`, `op_default`, `generic_op`, `generic_rec`, `_declared_defaults`); `lowering.md:109` says every one has.

Proposed fix: state the condition (no edge where at least two methods apply; the sentinel gives the edge otherwise), and list the functions with sentinels.

### M2. Definition checking does not run in the checks' own cache

- `lowering.md:70` (table row: "the definition checks' inference | plain inference on a `NativeInterpreter` | own cache owner `_CheckOwner` at archetypes"), `lowering.md:547` ("It runs in the checks' own cache, so nothing it infers reaches the program.").
- Code, verified by reading: `_worker_problems` (`checks.jl:84-89`) uses `Base.code_typed_by_type(sig; optimize = false, world)` with the default interpreter, by design ("the checks' interpreter inferred the whole call graph again under plain rules … 1.6 s"); archetype signatures are therefore inferred by facts into the facts cache. `_check_kw`/`_check_kw_at` are used by the keep analysis (`defcheck.jl:229`), `conformance_problems` (`implement.jl:244`), `_generic_problems`, `_rep_of` and `_note_conformances!`. `lowering.md:552` says the opposite of `:547` for the same function.

Proposed fix: say that the rule check infers archetype signatures in the facts cache (harmless: an archetype never runs), and that only the keep analysis and the result-type checks use `_CheckOwner`.

### M3. Several traits with a field mapping are refused with misleading errors

- `traits.md:67-77` (grammar: any `Traits` with any `How`), §5.4 and §5.5.
- Code, verified by reading: `_keys_implement` handles a tuple head only for `(X, Y) T by f` with a bare field name (`implement.jl:863-866`); `(X, Y) T name => stored` reaches `_implement_projection` with the pair as the body and fails with "a projection needs exactly one `project(t) = …`" (`implement.jl:1286`); `(X, Y) T by f, name => stored` fails with "expected `project(t) = …` or a begin … end block after the type" (`implement.jl:1280`). Both name forms the design does not have (the T-11 family).

Proposed fix: a Deviations row; the fix in `_keys_implement` is small (apply the mapping split before the tuple-head branch).

### M4. T-5 is scoped too narrowly: any family with a block whose target is a parametric type expression is broken

- `traits.md:979` (T-5: "A joint family takes a block of methods"), `traits.md:442-447` (examples).
- Code, verified by reading: `_keys_implement` line 900-902 turns `X S{P} where {P} begin … end` into `X{S{P} where {P}}` plus the block whenever the target is not a bare variable, trait parameters or not; `_implement_where` is reached only for `A where {A <: …}` (`implement.jl:896`). So `@implement Fam S{P} where {P} begin nf(s) = s.k end` defines `implementation(::Type{Fam}, ::Type{S})` (the UnionAll, which no member matches), a `conformance(::As{Fam}, u::S)` method with no builder, and the members are `NOTRAIT`: `MethodError` with the hint. Only the first and third examples of `traits.md:442-444` (no block; a bare variable) work with the shown status.

Proposed fix: widen T-5 to "a family whose target is a parametric type expression, with a block"; or lower that form through `_implement_family` (it is a one-line change in `_keys_implement`, the block branch at 900 should test for a `where` target first).

### M5. "Code at the prompt is owned by the session" is not what ownership does, and the extension trigger rule is undocumented

- `traits.md:794`.
- Code, verified by reading: `_owner` (`ownership.jl:117-130`) makes `Main` one owner and every module directly under `Main` its own owner. A trait module defined at the prompt and the prompt itself are different owners, so `@implement ColTable Vector{Int} …` at the prompt, for a trait of a prompt-defined module, is refused (test `runtests.jl:121-122`). The tutorial's examples pass because the user's types are defined in `Main`.
- `_check_delegate` (`implement.jl:474-492`) refuses an implementation in a package extension whose trigger package's types the implementation does not mention (`ImplementError`, "the extension … is triggered by …, which its methods do not mention"). traits.md §12.1 says only "belongs in the trait owner's package extension".

Proposed fix: state both rules in §12.1.

### M6. The untyped pointer path has an undocumented arity limit of five positional arguments

- `lowering.md:385` (one trait position through a caller-world pointer), `lowering.md:467` (six arguments for `Erased`).
- Code: `_UWrap` has methods for 0 to 5 arguments after the callable (`untyped.jl:177-181`), while the entry takes the pointer path for every tabled entry with one trait position and `nall = length(args)` (`trait_module.jl:659-666`). For an entry with six or more positional arguments, `_ufptr(F, Val(6))` builds a `cfunction` of `_UWrap()` at an arity it has no method for. Reasoning: the untyped call then fails (at the `cfunction`'s creation in `_pmiss`, or with a `MethodError` when the pointer is called); I could not run it. Test: a tabled entry `f(t::X, a::Int, b::Int, c::Int, d::Int, e::Int)` called from an `Any[]` loop.

Proposed fix: route `nall > 5` to the dynamic-call branch (`trait_module.jl:668-674`), and document the limit in §9.2.

### M7. T-9 is imprecise: there is an overlap check, at the first call

- `traits.md:983` (T-9: "No overlap check."), `traits.md:485` ("two overlapping generic implementations with neither more specific are refused").
- Code, verified by reading: a type matching two generic records raises `ImplementError` "… matches N generic implementations of X (…), none more specific: add a specific implementation" from the slow path (`_ambiguous_generic`, `implement.jl:332-335`, `:368`), so the entry's call raises it. Nothing is checked at the declaration, and "more specific" among generic implementations is not computed (every match counts).

Proposed fix: reword T-9: "at a call, a type matching two generic implementations raises `ImplementError`; nothing at the declaration; no specificity among generic implementations; the parameter-value rule is not checked".

### M8. The block form ignores an existing method of the type for an operation the block leaves out

- `traits.md:205` ("An implementation keeps it, or overrides it with its own method."), `traits.md:519` ("a supertype owner's method (`op(::AbstractSample)`) is part of an implementation declared after it").
- Code, verified by reading: `_missing_and_defaults` (`implement.jl:837-845`) makes every operation not named in the block default-served, whether or not `T` already has a method for it; `_dispatch` on `Impl{D}` calls the default for every `op ∈ D` (`core.jl:671-674`). `_declare_conformance_now` (`implement.jl:648`) then leaves such operations out of the override records, so neither is the existing method used nor is a later redefinition refused. The sentences above hold for the one-line form only (`_existing_defaults`, `implement.jl:312-318`).

Proposed fix: say in §3.2/§5.10 that with a block, an override must be in the block; or make `_missing_and_defaults` consult `_has_op_method` as the one-line form does.

### M9. Candidates of the `Dynamic` split are registered only for types with an `implementation` method

- `lowering.md:505-508` ("for each declared implementation at a concrete type, after each declaration and each package load").
- Code, verified by reading: `_note_conformances!` (`core.jl:397-420`) iterates `methods(implementation)` at concrete types. Types that conform by `by` forwarding or by a field mapping alone have only a `projection` record (`implement.jl:1363-1366`), family members have a UnionAll signature; neither is registered until a `Dynamic` of such a value is made (`core.jl:348`). Code compiled before that takes the fallback for them.

Proposed fix: say so in §13; or iterate `methods(projection)` too.

### M10. What is compiled ahead and what untyped callers get is narrower than §15 says

- `traits.md:867` ("A caller that does not know the argument's type reaches the code for any declared implementation without compiling anything per type."), `lowering.md:572-578`, L-15 (`lowering.md:675`: "vararg positions are skipped").
- Code, verified by reading: `ahead.jl:132` (`tpos == (pos,)`), `:138` and `:151-152` restrict the pattern method and both kinds of entry to entries with exactly one trait position and otherwise concrete arguments; entries with two trait positions get no worker, no pattern method and no entry compiled ahead. Keyword, vararg and `Callable` entries are specialized per type (L-12), which §15 of traits.md does not mention.

Proposed fix: add "several trait positions" to L-15 and cite L-12 from traits.md §15.

### M11. The checks table omits the operation-call check and its error

- `traits.md:763-772`.
- Code: every operation call on a trait object checks the arguments against `op_args` and raises `TraitArgumentError` (`core.jl:645-667`), and asserts the result (`TypeError`). `lowering.md:295`, `:543` and T-11 name it; the user-facing table does not. §3.1 (`traits.md:193`) says the check exists without naming the error.

Proposed fix: a row "a call of an operation on a trait object | arguments; result | `TraitArgumentError`, `TypeError`".

### M12. Errors at a failed `@implement` leave methods and records behind

- `traits.md:507` ("All of these run at `@implement`… A failure raises `ImplementError`."), §5.10 says nothing about the state after a failure.
- Code, verified by reading: in the block form the operations' methods and the `implementation` record are evaluated before `_check_implementation` runs (`implement.jl:996-1000`); a result-type failure leaves `ncols(::T)` and `implementation(X, T)` defined and no `conformance` method. With `by f begin … end` (T-14) the methods are defined for the field's type before the rule-3 check (`precheck = false`, `implement.jl:1353`), so a refused declaration still added methods to a type the package may not own.

Proposed fix: state it under §5.10 (prototype), or run the checks on the expression before evaluating definitions.

---

## Low

### L1. Error types in the §11 table and the status lines

- `traits.md:768` says a definition in a trait module that fails ownership raises `OwnershipError`; adding a bounded method to another module's function where it has no entry of that shape is `error(...)`, an `ErrorException` (`trait_module.jl:537-539`). Also `ErrorException`: a vararg of `Callable` (`:268`), `@specialize` (`:260`), a vararg not last (`:466`), `::Like{x}` naming no bounded argument (`:522`), a keyword with several `Callable` bounds (`:341`).
- `traits.md:383` ("The one-line form needs a concrete type. A parametric type conforms as a family"): the refusal (`implement.jl:1152`) says "the prototype does not declare parametric families this way" without naming the `where` form.

### L2. `Like{t}`: "the same type" versus "the same type family"

- `traits.md:633` says the new receiver "must be of the same type"; `entry.jl:713-716` accepts any type of the same `typename` (`LSeries{Float32}` for `LSeries{Float64}`), as `lowering.md:440` says.

### L3. Unstated run-time refusals in the `Like`/`Dynamic` paths

- `_rebuild` uses the positional outer constructor; a type without one raises `TraitBoundError` "cannot be rebuilt" (`entry.jl:730-738`).
- A constructor operation on a `Dynamic` of a trait with fields raises `TraitBoundError` (`entry.jl:744`); `traits.md:268` and `:638` state the rule without the exception.
- A `Dynamic` of an immutable value whose views hold only parts cannot give a `Like` result (`entry.jl:691-693`).

### L4. Citations

- `lowering.md:237`: "`ArchWit` at an archetype (`core.jl:585`)" is `defcheck.jl:32`; `core.jl:585` is `Impl`.
- T-4 (`traits.md:978`) cites `implement.jl:562` for `_field_problems`, which starts at `:560`.
- T-9 cites `implement.jl:1109`, a comment line; the generic branch is `:1110-1132`, the ambiguity error `:332`.

### L5. Grammar details (`traits.md:60`, `:84`)

- `Operation` requires a named receiver; `::Shape` without a name is accepted (`trait.jl:156`).
- `KwArg ::= Name "::" Bound …` admits the several-`Callable` form, which `_classify_kw` refuses (`trait_module.jl:341`).

### L6. "Reported when defined" is "reported at the module's end"

- `traits.md:615`: ambiguities between a bounded method and a typed method in another position are found by `check_entry_ambiguities` in `_finish_module` (`trait_module.jl:813`), as the joint-method rule is, not at the definition.

### L7. "No receiver type" has two more conditions

- `traits.md:318`: the code also requires that the declarations do not name `Self` and that every parameter is defined by a field (`entry.jl:456-465`); `lowering.md:233` has it right.

### L8. A trait object reaching another trait's entry is a `TraitBoundError` at run time

- `traits.md:591` ("A forbidden use is a `TraitUseError`"): the definition check reports it as such; at run time, where the check did not see it, the entry raises `TraitBoundError` (`_rule3_error`, `entry.jl:267-272`; `lowering.md:320`).

### L9. The ahead entry can outrank a typed method defined later

- See H1, point 5: `traits.md:612` ("below every type") holds at the time the ahead entry is made (`ahead.jl:177`), not for typed methods on a supertype of `T` defined afterwards.

### L10. The docs-example checks are untracked and their results unrecorded

- `experiments/` is excluded by `.gitignore:11`; `traits.md:971` and the T-1, T-2, T-15, T-16, T-18 rows cite `reference.jl` as "Where". No run of `reference.jl`, `tutorial.jl` or `strict.jl` is recorded in the repository (no tally in `state.md`, the record or a review), so the "would run as shown" question for the examples rests on reading. My trace of `@implement Stepper Clock by data, t => time` (reference.jl:175, the `by f, FieldMap` form) through `implement.jl:879-883` and `_field_problems` passes by reading, given Julia parses `by data, t => time` as `by` followed by the tuple `(data, t => time)`.

### L11. Wording that the reference's own conventions forbid

- `lowering.md:469` ("commit dc67242") and `lowering.md:372` ("julia-changes c7f1eae1c0") are history inside a reference (`README.md:40`: "No history").

---

## Verified as accurate (sample)

Traced and found consistent with the code, listed so the reader knows what was checked, not only what failed: the one-line form picks no field and names the `by` lines (`implement.jl:1198-1216`); forwarding does not chain (`implement.jl:536-537`); field mappings and `getproperty` rule (`implement.jl:564-578`); writable-field rules (`implement.jl:593-596`); stated parameters (`implement.jl:1008-1021`); `@concrete_only` on a forwarding field and on a family member at the call (`implement.jl:1307-1316`, `:710-711`); the override hook and its message (`hooks.jl:138-155`); the entry's fallback and hint text (`entry.jl:484-504`, `frames.jl:74-75`, T-22); keyword translation and `TypeError` on a declared keyword type (`entry.jl:331-342`, worker signature); `Callable` modes, `CallAs` precedence, trait-world functions passed as themselves, the six-argument limit of `Erased` (`entry.jl:569-600`, `core.jl:714-720`, `:744`); `DynamicFn` (`entry.jl:617-625`); `Dynamic` equality, hashing and printing (`core.jl:431-434`); the trait name as `Dynamic` in fields and containers (`trait_module.jl:143-213`); the untyped table's world ranges and session stamp (`untyped.jl:64-100`, L-13); `verify_main`'s `:inverse` holes (T-20); strict mode's backedge walk and safety net (L-18); the four-candidate split (`facts.jl:117`, `:420-428`); T-1, T-2, T-3, T-4, T-6, T-7, T-8, T-10 to T-22 and L-1 to L-19 as described, with the line numbers checked (except the three in L4 above).
