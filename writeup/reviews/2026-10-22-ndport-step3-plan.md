# Review: the NetworkDynamics port, P4 step 3: the component traits per kind, and the batches' crossings (plan)

Date: 2026-10-22. Reviewer: an Opus 5.5 agent, fresh eyes. Not edited after writing, except by a dated addendum.

**Reviewed:** [`../plans/2026-10-22-ndport-step3.md`](../plans/2026-10-22-ndport-step3.md) (status: proposal).

**Read against:**
- the meta plan [`../plans/2026-10-21-networkdynamics-port.md`](../plans/2026-10-21-networkdynamics-port.md) (ground rules, "make a choice, record the pushback", choices 1–47, state after E-165);
- the traits plan [`../plans/2026-10-21-ndport-traits.md`](../plans/2026-10-21-ndport-traits.md) §4 and Appendix A; the exploration [`../explorations/ndport-principled-traits.md`](../explorations/ndport-principled-traits.md) §3.2; the step-2 plan's review [`2026-10-21-ndport-graph-plan.md`](2026-10-21-ndport-graph-plan.md) (for the style);
- the pushback log [`../explorations/ndport-pushback.md`](../explorations/ndport-pushback.md) (P4-1);
- [`../reference/traits.md`](../reference/traits.md) §3.6, §4.7, §6.8; [`../reference/lowering.md`](../reference/lowering.md) §8.1–§9.3, L-37, L-38; [`../reference/compiler.md`](../reference/compiler.md) §1.2–§1.3, §2.5;
- `ndport/README.md`, `ndport/logs/merge/NOTES.md` (E-165, check H), the planning probes `ndport/scripts/p4s3-planning/` (70dec1d), `scripts/rhs_p4.sh`, `workload.jl`, `workload_steps.jl`, `workload_plot.jl`;
- NetworkDynamics at `ndport/pkgs/NetworkDynamics-p4`, branch `port`, 324bcb7: `src/component_dynamics.jl`, `coreloop.jl`, `network_structure.jl`, `construction.jl`, `component_functions.jl`, `doctor.jl`, `sparsity.jl`, `linear_analysis.jl`, `initialization.jl` (by grep);
- TraitWorld c655dde (`TraitWorld-port`, clean): `src/untyped.jl`, `trait_module.jl` (the entry and the table's pattern method, `:820`–`:1030`), `checks.jl` (`checked_call`), `implement.jl` (supertraits, families), `test/untyped.jl`; TraitWorld main 2e9ed68 for the diff since c655dde.

**Julia was run twice,** a tiny probe each, under the low-load rules (one job, two cores, idle I/O, niced, through `/tmp/claude-1000/julia-review.lock`): `env_merged` with `depot-merged`, the julia-1.13 build E-165 used (`libjulia-internal` built 2026-10-21 20:43), TraitWorld c655dde, product setting, strict mode off, one run, 2·10⁶ calls per timing, the minimum of three, load 2.4–2.5. The script and its output are in the Appendix. Every other statement about behaviour is from reading the code.

## Verdict

- **The step is the right next step, and it fits the references.** The traits per kind with the static facts in a supertrait, the batches kept per kind, and a user's type entering through the record are within traits §3.6, §4.7, §7.1 and §14. Nothing Planned is needed. No design change. The plan's construct table (§3.5) is correct against c655dde, with one addition for S3-0 (c) (finding 9).
- **The crossing's cost is real, and its size is right, but its mechanism is misread** (finding 3):
  - an untyped ordinary argument does not make the worker's call static: the call is a run-time site for untyped and abstract arguments alike;
  - what costs 60 ns per abstract annotation is a redundant type assertion in TraitWorld's table path (`trait_module.jl:999`), after the entry's own dispatch has already checked the type.
- **So the principled fix is in TraitWorld, not in NetworkDynamics** (recommendation below). S3-1 becomes a small TraitWorld work item, measured the same way, and NetworkDynamics keeps upstream's annotations.
- **Two blockers,** each in a row as written:
  - S3-2 removes `compf!`/`compg!` from the trait while `_vertex!`/`_edge!` still call them on the trait object (finding 1);
  - S3-4's user types fail at construction: a static edge with `f = x`, `_dynamics` testing `f`, the output symbol's clash (finding 2).
- **The refusals for user types miss the component-level callers** of the raw functions: initialization, the doctor, linearization (finding 6). An adaptor at the record removes most refusals.
- **The pass marks are sound.** The checks need three additions (findings 7, 9, 10).
- **The time is longer than an afternoon:** about 6–8 hours with the fixes (finding 8). Plan the split up front.

## Recommendation on the TraitWorld-side fix

**Take it. S3-1 becomes "S3-1 (TraitWorld)", and NetworkDynamics keeps its annotations.**

- **What the table's path does today** (one trait position, `trait_module.jl:963`–`1004`):
  1. the entry (its signature carries each ordinary argument's annotation, `:861`) calls through the pointer;
  2. `_UWrap` calls the pattern method with every argument in an `XAny` holder (`untyped.jl:183`–`187`);
  3. the pattern method unwraps each ordinary argument **with an assertion of its declared type**: `x = getfield(xa, :x)::$(ann)` (`trait_module.jl:999`);
  4. it calls `checked_call(f, views, args…)` (`:1004`).
- **Why the assertion is redundant:** the pattern method is reached only from inside the entry, and Julia's dispatch has selected the entry by the same annotations. The assertion adds no check. It only tells inference the type.
- **What the assertion buys, and what it costs:**
  - for a concrete type, the worker's call becomes a fact, so a static call (probe A: 49–56 ns);
  - for an abstract type (`Vector`, `Base.RefValue`), the call is still a run-time site (compiler §1.3), as with `Any`, and the assertion itself is a subtype test at run time. The Appendix's probe: two such assertions on an `Any` value cost 118 ns in facts code (121 ns in plain code, same build); the run-time site after them costs 16.5 ns.
- **The fix:** assert only a concrete declared type; leave any other ordinary argument as it comes (`Any`). For example, the pattern method's line becomes `x = TraitWorld._held_as(xa, ann)`, with `@inline _held_as(xa::XAny, ::Type{T}) where {T} = isconcretetype(T) ? getfield(xa, :x)::T : getfield(xa, :x)`.
  - The helper takes the holder, not the value: in facts code a call with an `Any` argument is a run-time site (`untyped.jl:13`–`16`). `isconcretetype(T)` folds per method.
  - The run-time site then dispatches on the arguments' concrete types to the worker compiled for them, exactly as it does today. No worker changes. The cost is the untyped row's: 66–74 ns in probe A.
- **The coordinator's variant, "call the worker at the declared signature (an `invoke`)", is not sound for speed.** It would run the worker compiled for the abstract declared types: in `run_vertex_batch!`, `args[]` would be inferred `Any`, and every call in the batch loop would be a run-time site. Julia specialises a method on the arguments' run-time types, whatever their annotations say. The right form is "check nothing more, and let the existing dispatch select the worker for the concrete types".
- **Within the intended shape:**
  - traits §6.8: a `Compiled` value whose type the code does not know "selects the code compiled for its key once per call, a function barrier";
  - lowering §9.3: "One call through it builds the views from the builder's data and calls the worker for the key";
  - neither makes the cost depend on how the ordinary arguments are declared. A plain Julia function barrier does not re-check annotations after dispatch. So today's behaviour is a deviation from §9.3, and the fix retires it.
- **The same work item takes two neighbours** (findings 4, 5):
  - an ordinary argument whose annotation names a `where` variable is excluded from the table (`trait_module.jl:836`–`838`). Once nothing is asserted for it, the exclusion can go (to be checked by a test);
  - `_UWrap` has methods for at most eight arguments (`untyped.jl:183`): a ninth raises `MethodError`. Raise the bound together with `checked_call`'s fixed arities (`checks.jl:311`), or table only entries within the wrapper's arity. A correctness fix, one line plus a test.
- **Size:**
  - TraitWorld: about 10–20 lines in `trait_module.jl` and `untyped.jl`; tests in `test/untyped.jl`: an entry with `bs::Vector, args::Base.RefValue` gives the right result with the untyped form's allocations; a `where`-annotated argument tabled; a nine-argument crossing that works. The TraitWorld suite once.
  - The port: TraitWorld moves, so the merged stack recompiles once (368 s in E-165), and the baseline runs again at the new commit.
  - About 1–1.5 hours of work and 10–15 minutes of machine time, against S3-1's two signatures and 8 minutes. The extra hour buys the fix for every TraitWorld user, not only for NetworkDynamics.
- **How the plan changes:**
  - **S3-1 (TraitWorld):** on a branch from c655dde in `TraitWorld-port` (the same commit cherry-picked onto main: c655dde..2e9ed68 touches `trait_module.jl` only in `_fkey`, far from these lines). Checks:
    1. probe A again: `bs::Vector, args::RefValue` and `bs::Vector{Batch}, args::RefValue` within 10 ns of the untyped row; the `where {A}` row tabled (one allocation, the `Ref`); the nine-argument row runs;
    2. then setting M rebuilt on the new commit **with NetworkDynamics at 324bcb7 unchanged**: P, R, X, W. This run measures the gain and becomes the baseline for S3-2 on. Criterion 2 (≤ 90 ns) and criterion 3 (d ≤ 32.0 ms) stay as they are.
  - **The rest of the plan:** choice 48 becomes "the crossing fixed in TraitWorld first"; choice 55 becomes "TraitWorld at c655dde plus the fix"; §7's candidate rows are written by the owner of the lowering reference with the probe's committed log and retired by the fix (or §9.3 gains one sentence of the intended shape: "an ordinary argument's declared type is checked once, by the entry's dispatch"); §8's first lesson goes (the guideline would otherwise teach a workaround for an implementation artefact); §11's second bullet goes; P4-1's update says the cost was fixed in TraitWorld.
  - `git diff upstream` stays smaller: the port's diff carries no annotation removals.
- **Optional later:** a pointer keyed also on the ordinary arguments' concrete types would make the worker's call static (about 50 against 70 ns per crossing). That is a larger change, for when the remaining per-batch cost matters.

## Findings

### 1. (blocker, for S3-2's row) S3-2 takes `compf!`/`compg!` out of the trait while the loop still calls them on the trait object

- S3-2: "`compf!`/`compg!` become plain helpers; nothing calls the new operations yet". S3-3 changes `_vertex!` and `_edge!`.
- Between the two rows, `_vertex!(m, …)` and `_edge!(m, …)` (`coreloop.jl:278`–`320`) still call `compf!(m, …)` and `compg!(m, …)`. There `m` is the trait object a `ComponentDynamics` bound passes.
- Once they are no longer operations, `compf!` has methods only for `FunctionDynamics`. A trait object matches none. The module's definition check reports the call (check P), or the right-hand side raises `MethodError` (check R).
- **Fix,** either:
  - keep `compf!`/`compg!` as operations of `ComponentDynamics` through S3-2, and remove them in S3-3 together with the switch of `_vertex!`/`_edge!`; or
  - merge S3-2 and S3-3 into one row, with S3-3's checks.

### 2. (blocker, for S3-4 as written) The user's types fail at construction

- **A static edge with `f = x`.** §3.3: "`dynamics = x` sets the record's `f = x`, `g = x`". For `Line` (`hasf` false) the record then has an `f`. `_construct_comp` sets `sym = Symbol[]` only when there is no `f` (`component_functions.jl:711`–`720`), so it raises "Either `dim` or `sym` must be provided" (`:726`).
- **`_dynamics` tests `f`.** With `f = nothing` for a static component instead, `_dynamics(dT, f, g, …) = conforms(typeof(f), …) ? f : FunctionDynamics(…)` (§3.2) builds `FunctionDynamics(nothing, Line(), …)`. Its `edgeg!` then calls `Line()(osrc, odst, ins…, p, t)`: `MethodError` at the right-hand side.
- **The vertex's output symbol.** `Swing` with `sym = [:δ, :ω]` and `outsym = [:δ]` clashes. A `StateMask` output is allowed to clash because `_has_sym_to_outsym_mapping(g)` is true for it (`:1005`). For `g = Swing()` it is false (`:1042`), so the uniqueness check raises `ArgumentError` (`:1019`–`1035`).
- **The component check warns at every construction.** `chk_component` (`doctor.jl:89`, on by default: `CHECK_COMPONENT = Ref(true)`, `NetworkDynamics.jl:154`) calls `compfg(c)(…)`, which calls `f(du, u, ins…, p, t)`. For `f = Swing()` that is a `MethodError`, caught and printed as a warning (`doctor.jl:109`–`112`). `dealias = true` copies each model, so it warns again. S3-4 lists `chk_component` among its functions but not what changes there.
- **Fix:**
  - the keyword sets `f = hasf(x) ? x : nothing` and `g = x`;
  - `_dynamics` tests `g`, which every component has: `conforms(typeof(g), _kind_trait(dT)) ? g : FunctionDynamics(f, g, …)`;
  - `usertype_models` passes `allow_output_sym_clash = true` for `Swing`, as a `StateMask` gets it implicitly;
  - `chk_component` calls the trait's operations for a conforming value, or finding 6's adaptor makes it work unchanged.

### 3. (should fix) The crossing's mechanism: an untyped argument does not make the worker's call static

- **§2.2 says:** "An abstract annotation on an ordinary argument makes the worker call dynamic. A concrete or an untyped one does not." The candidate deviation row (§7), the guideline lesson (§8) and E-166's question (2) follow from it.
- **By reading:**
  - the pattern method calls `checked_call(f, views, args…)` with each ordinary argument as `getfield(xa, :x)` (untyped: `Any`) or `getfield(xa, :x)::ann` (`trait_module.jl:999`, `:1004`);
  - under the facts mode a call whose argument types are not concrete is a run-time site (compiler §1.3). `Any` and `Vector` are both not concrete;
  - so the worker's call is a dynamic dispatch for untyped and abstract arguments alike, and static only when every ordinary argument is declared concrete.
- **By the probe (Appendix):** two abstract assertions cost 118 ns; the run-time site itself 16.5 ns. Probe A's rows agree: two abstract annotations 213–217 ns, one 148–159 ns, none 74 ns.
- **Consequences for the plan:**
  - after S3-1 (or the TraitWorld fix), check H still shows three dynamic `checked_call`s per right-hand side (E-165: 35,290 in steps c–e). That is expected. It is not a sign that the change failed;
  - "`fully_typed(run_vertex_batch!, …)` … the run-time sites stay those of the machinery" (§2.3) holds, with the pattern method's call among them;
  - the expected gain is unchanged: about 120 ns per crossing, 0.36 µs per right-hand side, which agrees with §2.3's 0.3–0.4 µs.
- **Fix:** restate "What they show", the candidate row ("the table's pattern method asserts each ordinary argument's declared type again; for a non-concrete type that is a subtype test per argument, about 60 ns, while the worker's call stays a run-time site"), §8's lesson, and question (2)'s clause. Better: take the recommendation above, and the row is written and retired by the fix.

### 4. (should fix) The `where {A}` row measures the generic path, not an annotation

- Probe A's `rd(…, args::Base.RefValue{A}) where {A}` costs 292–311 ns and 3 allocations. §2.2 reads it as "the most expensive" annotation.
- By reading, the entry is not tabled at all: `tabled` requires that no ordinary argument's annotation names a `where` variable (`trait_module.jl:836`–`838`, "a holder binds no type variable"). The call takes the generic path: the trait object assembled behind one dynamic call, the worker selected by a second (lowering §9.3).
- §9.3's "Which entries" names keywords and varargs only. So this exclusion is a third deviation from §9.3, beside findings 3 and 5.
- **Fix:** say so in §2.2 and in §7's rows. The TraitWorld fix can lift it (recommendation).

### 5. (should fix) The eight-argument limit is a correctness bug, not a cost

- `_UWrap` has methods for 0–8 arguments (`untyped.jl:183`). The pointer for a nine-argument entry is made for nine `Any` arguments (`_ufptr`, `:189`), and its call raises `MethodError`.
- `checked_call` has a vararg method beside its fixed arities (`checks.jl:308`), and the generic path has no limit. Only the table's path fails, and it fails a valid call.
- §7's row should say "raises `MethodError`", and the fix is one line (recommendation).
- **NetworkDynamics does not need it.** §2.3's reason to keep the `Ref` holds without the limit: through the pointer every argument is passed as `Any`, so `t::Float64` and the `inbufs` tuple would be boxed one by one, two allocations against the `Ref`'s one. Say that instead of "beyond the table's eight".

### 6. (should fix) User types reach more callers of the raw functions than the refusals name

- §3.3 refuses user types under `KAExecution`, `PolyesterExecution`, sparsity detection and CUDA.
- With `f = g = x`, every caller of the record's raw functions at upstream's convention fails too:
  - `compfg(c)` (`component_functions.jl:1159`): component initialization (`initialization.jl:319`, `:989`, `:1055`), the doctor (`doctor.jl:109`), the MTK extension (`ext/MTKExt_utils.jl:1110`, `:1142`);
  - `linearize_component` (`linear_analysis.jl:710`–`735`);
  - `ff_to_constraint` (`component_functions.jl:1182`), which builds new functions from `f` and `g`.
- The workload reaches none of them (`find_fixpoint` and `jacobian_eigenvals` use the network's right-hand side), so the gates pass. But a user's `initialize_component!` on a `Swing` vertex raises `MethodError`.
- **Fix,** one of:
  - (a) list each and refuse it with a message, in choice 53;
  - (b) **recommended:** the record's `f` and `g` hold adaptors to upstream's convention. For example, `VertexF(x)` with `(a::VertexF)(du, u, args...) = vertexf!(a.x, du, u, args[1:end-2], args[end-1], args[end])` (upstream calls `f(du, u, ins..., p, t)`), and a `g` adaptor per feed-forward kind and kind of component (one output for a vertex, two for an edge), as `_gargs` orders them. `_dynamics` unwraps an adaptor and keeps `x` itself. Then:
    - initialization, the doctor, linearization, `ff_to_constraint` and `chk_component` work unchanged;
    - the typed batches (`PolyesterExecution`, `KAExecution` on the CPU) call the adaptors;
    - sparsity detection tests the adaptor with tracers first (`sparsity.jl:120`–`170`), and `filter_conditionals` returns a non-RGF function unchanged;
    - only CUDA's `_adapt_rgf` stays refused.
  - (b) changes choices 52 and 53. It is the step's choice to make, by the meta plan's rule.

### 7. (should fix) A crossing pass mark at S3-3

- At S3-3 the bound becomes a subtrait. The trait object then carries the supertrait's view too, and the table may build it through `_builder_for` rather than the one declared builder (`_umiss`, `untyped.jl:67`–`71`, by the number of traits `needed` lists).
- Criterion 2 is "reported at S3-3" only, and the stop rule is on the steady state (5 % + 0.5 ms).
- **Fix:** add a pass mark: S3-3's crossing at most S3-1's + 15 ns, else attributed (X and `fully_typed`) before S3-4.

### 8. (should fix) The time: about 6–8 hours, not an afternoon

- The plan says 4.5–5.5 hours, "tight". With findings 1, 2 and 6, S3-2/S3-3 and S3-4 each take longer than estimated. The keyword alone touches `_fill_defaults`, `_construct_comp`, `chk_component`, the refusals, the workload and the check networks.
- With the TraitWorld fix: about one hour more, and one rebuild of the merged stack (368 s).
- **Estimate:**
  - 3a (S3-0, the TraitWorld fix, S3-2/S3-3 merged): 3.5–4.5 hours;
  - 3b (S3-4 with the adaptor, S3-5, S3-6): 2.5–3.5 hours.
- **Fix:** plan the split up front. 3a closes E-166 on criteria 0–4 and 6–9 without the user's types; 3b takes the next free ID, as §10 already allows. The machine time (under an hour) is realistic.

### 9. (should fix) S3-0 (c): test the supertrait's operations through the table, on a family member

- At c655dde a family's declaration skips the supertrait check: `_check_now` returns for a non-concrete `R` before the loop over `trait_closure(X)` (`implement.jl:536`–`542`). The member check (`_member_problems`, `:830`) checks the trait's own operations and fields, not that the member conforms to the supertrait.
- So what S3-3 relies on is first exercised at run time: a `VertexDynamics` trait object of a `FunctionDynamics` member that answers `hasf`, `fftype`, `pdim` and `extdim`'s default.
- **Fix:** S3-0 (c) calls, in a bounded function `run(m::VertexDynamics, …)`, `hasf(m)`, `pdim(m)` and `extdim(m)` (the default), entered by `compiled_for(Kept{VertexDynamics}(member))` from an untyped caller (the table's path), and once from a typed caller. Also a member whose `ComponentDynamics` family is missing: what is refused, and where.

### 10. (should fix) Checks missing at S3-3 and S3-4

- **The refusals' messages** (choice 53): S3-4's check column has none. One line per refused path in `rhs_check.jl` or a small script: the `ArgumentError` and its text.
- **The typed batches on function models:** S3-3 changes `ComponentBatch`'s constructor and S3-4 the record. R covers the sequential and threaded styles only. Run `scripts/p4_polyester_check.jl` once at S3-3 and at S3-4.
- **T at S3-4:** the keyword changes `_construct_comp`, which every test calls. T runs at S3-3 only.

### 11. (minor) Citations and the harness

- §3.3: `component_functions.jl:569`–`570` are `_takes_n_vecs_and_t` and `_takes_n_vecs_no_t`, used by the feed-forward inference (`_infer_fftype`, `:547`). They are not arity checks of `f` and `g`. With `ff` given, they are not reached anyway.
- `chk_component` is in `doctor.jl:89`, not `component_functions.jl`.
- Batching by model: `_find_identical_components` and `_component_hash` (`construction.jl:266`–`281`), not `:259`.
- `rhs_p4.sh` already takes `P4ENV`, `P4DEPOT` and `TWDIR`. It runs with `JULIA_NUM_PRECOMPILE_TASKS=4` and without `taskset -c 0-1` and `ionice`. Align it with the two-core rule (README, from 2026-10-22 13:34).

### 12. (minor) The pushback log's P4-1 is stale in one bullet

- "The reference: a family member takes the entry's generic path" contradicts lowering §9.3 since 3bebf13 ("A family member is served by the table like a declared type").
- When S3-6 updates P4-1, correct that bullet too.

### 13. (minor) Moving TraitWorld moves three settings

- `env_merged`, `env_p4_pin` and `env_p6_pin` all read `../../TraitWorld-port`, a detached HEAD at c655dde.
- If the recommendation is taken: check out a named branch there (for example `port`), record the commit in each header (the harness does), and say that P4P and IP rebuild when next used.
- Tell any other agent working in `env_merged` before NetworkDynamics or TraitWorld is rebuilt in `depot-merged`.

## The questions asked, in short

1. **Are the claims right?**
   - The code's shape (§1.1), the batches, the three crossings per right-hand side, the family and L-38's three registry methods, the user types' arithmetic against `swing!` and `AntiSymmetric(line!)` (`component_functions.jl:121`–`127`): right.
   - The crossing's mechanism: wrong (findings 3, 4); its size: right.
   - The construction of user types: wrong as written (finding 2).
2. **Are the checks sufficient?** With findings 7, 9 and 10, yes. Criterion 7's three registry methods and criterion 1's `sametype` follow from the code.
3. **Are the pass marks sound?** Yes: d ≤ 32.0 ms leaves 1–2 ms of margin over the expected 30–31 ms (about 12,000 right-hand sides in step d, by check H's 12,991 edge crossings over c–e). A crossing mark at S3-3 is missing (finding 7).
4. **Does it fit the references?** Yes. Nothing Planned is needed. The current table behaviour is three deviations from lowering §9.3 (findings 3–5), better fixed than worked around (recommendation).
5. **Is the time realistic?** The machine time, yes. The work, no: 6–8 hours (finding 8).
6. **What is missing?** The component-level callers of the raw functions (finding 6); the supertrait through the table (finding 9); the refusal and typed-batch checks (finding 10).

## Appendix: the review's probe

`assert_probe.jl` (run in `ndport/` with `JULIA_PROJECT=env_merged`, `JULIA_DEPOT_PATH=depot-merged:~/.julia:`, under the lock as above). It emulates the table's pattern method (`trait_module.jl:999`, `:1004`) for `bs::Vector, k::Int, args::Base.RefValue`:

```julia
using TraitWorld, Printf
@trait_module module P
using TraitWorld
struct XAny; x::Any; end
struct Batch; n::Int; end
@noinline g(a, b, c) = nothing
@noinline fa(x1::XAny, x2::XAny, x3::XAny) = g(getfield(x1, :x)::Vector, getfield(x2, :x)::Int, getfield(x3, :x)::Base.RefValue)
@noinline fb(x1::XAny, x2::XAny, x3::XAny) = g(getfield(x1, :x), getfield(x2, :x)::Int, getfield(x3, :x))
@noinline fc(x1::XAny, x2::XAny, x3::XAny) = (a = getfield(x1, :x); c = getfield(x3, :x); a::Vector; c::Base.RefValue; g(a, getfield(x2, :x)::Int, c))
@noinline fd(x1::XAny, x3::XAny) = (getfield(x1, :x)::Vector; getfield(x3, :x)::Base.RefValue; nothing)
end
function tm(f, n = 2_000_000)
    f(); f(); t0 = time_ns(); for _ in 1:n; f(); end; (time_ns() - t0) / n
end
x1 = P.XAny([P.Batch(0)]); x2 = P.XAny(1); x3 = P.XAny(Ref((1.0, [1.0])))
for (name, f) in (("asserted abstract, then the call", () -> P.fa(x1, x2, x3)),
                  ("not asserted, then the call", () -> P.fb(x1, x2, x3)),
                  ("asserted, the call with the untyped values", () -> P.fc(x1, x2, x3)),
                  ("the two asserts alone", () -> P.fd(x1, x3)))
    @printf("%-46s ns=%.1f allocs=%d\n", name, minimum(tm(f) for _ in 1:3), @allocations(f()))
end
```

| | facts code (`@trait_module`) | plain module, same build |
|---|---|---|
| asserted abstract, then the call | 143.4 ns, 0 allocations | 120.0 ns, 0 |
| not asserted, then the call | 16.5 ns, 0 | 1.9 ns, 0 (inferred: a static call) |
| asserted, the call with the untyped values | 142.0 ns, 0 | 122.2 ns, 0 |
| the two asserts alone | 118.2 ns, 0 | 121.4 ns, 0 |

One run each, load 2.4–2.5; indicative. In facts code the call after an unasserted `Any` value is a run-time site (16.5 ns); the two subtype tests are the cost.
