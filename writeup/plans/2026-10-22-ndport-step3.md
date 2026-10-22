# The NetworkDynamics port, P4 step 3: the component traits per kind, and the batches' crossings

Status: **proposal; P4 step 3 of the [W-32 meta plan](2026-10-21-networkdynamics-port.md)** (written 2026-10-22; to be reviewed before work starts). Not normative: the references hold ([`../reference/traits.md`](../reference/traits.md) above all).

Inputs:
- the meta plan's ground rules ("make a choice, record the pushback"), its choices 1–47, and its state: E-165 merged the tracks; the port works in `ndport/env_merged`, depot `depot-merged`, the trees on branches `port`;
- the traits plan [`2026-10-21-ndport-traits.md`](2026-10-21-ndport-traits.md) ("the traits plan"): §1.2 (step 1's trait), §2.3 (the batch functions), §4 (step 3 is `VertexDynamics`/`EdgeDynamics`; step 4 `ODERHS`), Appendix A (PB-1, PB-5); its review [`../reviews/2026-10-21-ndport-traits-plan.md`](../reviews/2026-10-21-ndport-traits-plan.md);
- the Fable exploration [`../explorations/ndport-principled-traits.md`](../explorations/ndport-principled-traits.md) ("expl."), §3.2–§3.4, §10.12, §10.13;
- the pushback log [`../explorations/ndport-pushback.md`](../explorations/ndport-pushback.md): P4-1 (the batches' crossings: the steady state 34.7 against upstream's 15.3 ms);
- `ndport/README.md` (settings, the harness), `ndport/logs/merge/NOTES.md` (E-165), `ndport/logs/p4/NOTES.md` (E-152), `ndport/logs/p4-issue48/` (the crossing after open issue 48);
- the porting guideline [`../intro/porting.md`](../intro/porting.md) (A12, B5);
- the references: traits §3.2, §3.6, §4.7, §4.8, §5.3, §6.2–§6.8, §7.1–§7.4, §14; lowering §4.6, §7, §8.2, §9.3, L-37, L-38;
- NetworkDynamics at `ndport/pkgs/NetworkDynamics-p4`, branch `port`, 324bcb7; TraitWorld c655dde (the worktree `TraitWorld-port`).

File and line references are to those trees. **Julia was run for this plan only for planning probes** (§2.2), under the low-load rules (one job, two cores, idle I/O, niced, through the shared lock), in `env_merged` with `depot-merged`: the julia-1.13 build E-165 used, TraitWorld c655dde, product setting, strict mode off, one run each, 2·10⁵ calls per timing, load 0.7–1.1. Their scripts are in the planning session's scratchpad; S3-0 commits them under `ndport/scripts/` and runs them again, so that the numbers below have a committed log. Until then they are indicative.

## Summary

- **The crossing has a part the port can remove now.** A crossing from a kept value into a bounded function costs about 40 ns when the function's ordinary arguments are concrete or untyped, and 150–215 ns when they are declared with abstract types (`batches::Vector`, `args::Base.RefValue`), as NetworkDynamics' batch functions declare them (§2.2). In NetworkDynamics today a crossing costs 160–170 ns, three per right-hand side.
- **First change (S3-1):** the batch functions' ordinary arguments untyped. Expected: about 90–140 ns less per crossing, 0.3–0.4 µs less per right-hand side, step d's steady state from 34.7 to about 29–32 ms. One method signature each, no change of results.
- **Then the traits per kind (S3-2, S3-3):** `VertexDynamics` and `EdgeDynamics`, each a subtrait of `ComponentDynamics`, which keeps the static facts the core loop reads (`hasf`, `fftype`, `pdim`, `extdim`). The vertex batches keep `Kept{VertexDynamics}`, the edge batches `Kept{EdgeDynamics}`; `run_vertex_batch!` and `run_edge_batch!` are bounded by them. NetworkDynamics' `FunctionDynamics` implements all three, as families.
- **Then a user's own type (S3-4):** `struct Swing end` with `@implement VertexDynamics Swing` enters a network through `VertexModel(dynamics = Swing(), …)`. The workload gains a `usertype` pass (off by default), whose digests must equal the `first` pass's exactly.
- **What it does not buy:** the rest of the gap. After S3-1 the right-hand side still pays three crossings at the table's floor (about 40–75 ns each) and three `Ref`s. A cheaper per-batch call needs a witness carried in the kept value, which is Optional (§2.4). W-40 does not change the crossing: the table already serves a family member as a declared type (§2.5).
- **Nothing Planned is needed.** TraitWorld stays at c655dde: 2e9ed68's fixes (T-64–T-67) are not used by this step.
- **Measured by E-166** (§6): exact results against U, strict mode off and on; the steady state against the merge's 34.7 ms; new equations and a new model type compile without SciML; the census; ND's test subset.
- **Time:** an afternoon, tight (§10). Split at S3-3 if it runs short: 3a (the crossing and the traits per kind) carries the measurable gain; 3b (user types) follows.

---

## 1. What step 3 changes

### 1.1 Before and after

- **Before** (324bcb7):
  - one trait, `ComponentDynamics`, at the core loop's convention: `hasf`, `fftype`, `pdim`, `extdim`, `compf!`, `compg!(m, outs::Tuple, …)` (`src/component_dynamics.jl`);
  - each erased batch keeps `Kept{ComponentDynamics}` holding a `FunctionDynamics` (`src/network_structure.jl`, `ComponentBatch`);
  - `_process_kept!` opens the model per batch and calls `run_vertex_batch!(m::ComponentDynamics, batches::Vector, k::Int, args::Base.RefValue)` or `run_edge_batch!` (`src/coreloop.jl`);
  - a user cannot bring a type of their own: every model is built from a record's `f` and `g`.
- **After:**
  - the batch functions take their ordinary arguments untyped (S3-1);
  - `ComponentDynamics` keeps the static facts; `VertexDynamics` and `EdgeDynamics` add the calls (§3.1);
  - vertex batches keep `Kept{VertexDynamics}`, edge batches `Kept{EdgeDynamics}`; each batch function is bounded by its kind's trait;
  - `VertexModel(dynamics = x, …)` and `EdgeModel(dynamics = x, …)` take any value whose type conforms; the batch keeps that value itself as its model.
- **Unchanged:** the `Network`'s type for every model (one batch type per kind); the order of every operation, so results stay exact; `KAExecution`'s and `PolyesterExecution`'s typed batches (PB-6, P4-2); the record types' fields; `get_graph`, symbolic indexing, callbacks; SciML (step 4 is `ODERHS`).

### 1.2 Where the code lives

- **NetworkDynamics:** the worktree `ndport/pkgs/NetworkDynamics-p4`, branch `port`, from 324bcb7; one commit per row of §4. `git diff upstream` stays the port.
- **The environment:** `ndport/env_merged`, depot `depot-merged`, unchanged. NetworkDynamics' `[deps]` already hold TraitWorld (`conforms` is TraitWorld's).
- **TraitWorld:** c655dde in `TraitWorld-port`, not moved. A move recompiles the merged stack (368 s in E-165) and changes the baseline. If it must move, the commit is recorded and the baseline runs again.
- **The workload:** additive and off by default (§4, S3-4): a file `scripts/workload_types.jl` with the user's types, included only where NetworkDynamics defines `VertexDynamics`; a pass `usertype` in `workload.jl` that runs only when `NDW_PASSES` names it. Without it the output is byte-identical.
- **Each row rebuilds NetworkDynamics** in `depot-merged` (it has no dependents in `env_merged` except its extensions). The cache cap of ten files per package: four rebuilds here; a run that precompiled is marked INVALID by the harness.

### 1.3 The baseline

E-165's setting M (`ndport/logs/merge/`): results exact against U; again c / d / e 5.2 / 34.7 / 1.0 ms strict off (P4P's spread 34.4–35.0 for d), 35.9–37.8 strict on; changed b–e 0.56 s; first a–e 31.1 s; session 65.9 s; the census: NetworkDynamics 1 (L-38's registry method), every other wrapped package 0; the one refusal under strict mode is OffsetArrays' `reshape` in Base's own code. P6's steady state 16.8 ms and U's 15.3 ms are the targets the port measures itself against.

---

## 2. The crossings (P4-1)

### 2.1 What a right-hand side pays now

- Tier S has one vertex batch (20) and one edge batch (40). A right-hand side runs three passes with batches: vertices `:g`, edges `:fg`, vertices `:f` (`src/coreloop.jl:39–122`). Each is one `Ref` of the pass's arguments and one crossing.
- The dispatch profile of E-165 (check H): per right-hand side, three dynamic calls, all `TraitWorld.checked_call` from the batch functions' untyped entries; no other dynamic call. So the crossing's worker call is a dynamic call.
- Planning probe C (tier S, NetworkDynamics at 324bcb7): the right-hand side 1,794 ns and 5 allocations; the same network with typed batches (`PolyesterExecution`, one thread) 611 ns and 0. Per pass, the crossing into an empty batch costs 162–172 ns; an erased pass costs 143–181 ns more than the same pass on typed batches. So the three crossings are about 500 ns of the 1,180 ns excess. The rest is not attributed here: the three `Ref`s, two allocations in the vertex crossings, the passes without batches. S3-0 attributes it once (§4).

### 2.2 The planning probes

Probe A: a scratch trait module with one trait, a family member (`Fam{F}` holding a plain function) and the caller in the module, as `_process_kept!` is: `for k …; f(compiled_for(ks[k]), …)` over a `Vector{Kept{VD}}`. Each line is the cost of one crossing into an empty batch, the caller's loop included.

| The bounded function's ordinary arguments | ns per crossing | allocations per call |
|---|---|---|
| `bs::Vector, k::Int, args::Base.RefValue` (NetworkDynamics' shape) | 213–217 | 1 (the `Ref`) |
| `bs::Vector{Batch}, k::Int, args::Base.RefValue` | 148–159 | 1 |
| `bs::Vector{Batch}, k::Int, args::Base.RefValue{AT}` (concrete) | 53–56 | 1 |
| `bs::Vector{Batch}, k::Int, args::Base.RefValue{A} where {A}` | 292–311 | 3 |
| `bs::Vector{Batch}, k::Int, du::Vector{Float64}, u::Vector{Float64}` (no `Ref`) | 49–51 | 0 |
| `bs::Vector{Batch}, k::Int, du, u` | 65–67 | 0 |
| `bs, k, du, u` (all untyped) | 66–69 | 0 |
| `bs, k, args` (untyped, with the `Ref`) | 74 | 1 |
| nine arguments (the pass's arguments one by one) | `MethodError`: the table's call wrapper `_UWrap` has methods up to eight arguments | — |

Probe B: the same trait, a minimal bounded function `run1!(m::VD, du::Vector{Float64}, u::Vector{Float64}, n::Int)`, and the same loop as an operation with a default called on the kept value:

| | family member | declared type |
|---|---|---|
| `compiled_for` and the bounded function, empty batch | 40 ns, 0 allocations | 41 ns, 0 |
| an operation with a default, on the kept value, empty batch | 411 ns, 0 | 36 ns, 0 |

What they show:
- The table serves a family member at a declared type's cost (lowering §9.3; open issue 48). The difference is the bounded function's shape.
- An abstract annotation on an ordinary argument makes the worker call dynamic. A concrete or an untyped one does not. `where {A}` on an argument's parameter is the most expensive.
- An operation on a kept family member takes L-37's path (about 400 ns); on a declared type it costs what a crossing does.

### 2.3 The change: the batch functions' ordinary arguments

```julia
# src/coreloop.jl: the ordinary arguments untyped (the probe: an abstract annotation makes each crossing a dynamic call)
function run_vertex_batch!(m::VertexDynamics, batches, k, args)   # batches: the kind's Vector; args: a Ref of the pass's arguments
    (ex, fg, inbufs, du, u, o, p, t) = args[]
    …                                                             # as at 324bcb7
end
function run_edge_batch!(m::EdgeDynamics, batches, k, args) … end
```

- S3-1 makes this change on the step-1 bound (`m::ComponentDynamics`); S3-3 changes the bound to the kind's trait.
- **The `Ref` stays.** The pass has eight values; passed one by one, the call has eleven arguments, beyond the table's eight. Grouped into tuples they would be boxed, as the `Ref` is.
- **Expected effect:** ND's crossing from 162–172 ns to about 60–75 ns; per right-hand side 0.3–0.4 µs less. Step d makes about 12,000–15,000 right-hand-side calls (E-152's reading, and today's excess per call), so about 3–6 ms less: d at about 29–32 ms, strict off.
- `fully_typed(run_vertex_batch!, …)` at the worker's signature is read at S3-1: the run-time sites stay those of the machinery and `Threads.@threads` (E-152's list).

**Not taken in this step:**
- **One crossing fewer per right-hand side,** by running a `StateMask` output (`g = 1`) in `_process_kept!` without a crossing. Within the design; a special case for one library type; about a third of the remaining crossings' cost (about 1 ms in step d). Revisit if wanted.
- **One `Ref` per right-hand side instead of per pass:** the pass's argument types differ (`fg`, the buffers), so one `Ref` would hold an abstract tuple, and the worker would read `Any`.

### 2.4 What the design does not allow

- **A per-batch call at a vtable's cost.** In Rust, `Vec<Box<dyn VertexDynamics>>` with a provided method `run_batch` costs one indirect call per batch. Here a crossing from a kept value is one lookup in the table by the held object's type, one call through a pointer, and the trait object's assembly ([traits §6.8](../reference/traits.md#68-costs-and-choosing), [lowering §9.3](../reference/lowering.md#93-untyped-callers-of-compiled-values-the-table)): about 40–75 ns in the probes, three per right-hand side. A witness carried in the value would make it a load and an indirect call; it is Optional (traits §6.8; [compiler §3.3](../reference/compiler.md#33-further-work-on-mechanism-3)).
- **No crossing at all** means keeping the models' types in the batches' container (upstream's typed tuple). The design allows it; it gives back the `Network`'s dependence on the equations, step 1's whole gain.
- **Associated constants** (the traits plan's PB-1): `pdim`, `extdim` and `fftype` are constants per key only because each implementation returns a constant. The trait cannot require it ([traits §3.4](../reference/traits.md#34-parameters-and-associated-types)). A user's type that returns `pdim` from a field gets `Union` views at its own functions.

### 2.5 What W-40 would change

- **Not the crossing.** W-40 fixes a family member's builder in the code of a *typed* caller (L-37). The crossing is an untyped call through the table, which already serves family members as declared types (probe B: 40 against 41 ns; TraitWorld's `test/untyped.jl` asserts equal allocations).
- **The operation form for `FunctionDynamics`.** An operation on a kept family member takes L-37's path today (probe B: 411 ns). With W-40 it should cost what it costs on a declared type (36 ns). Then the per-batch loop could be an operation with a default, called on the kept value, without a bounded function's entry. E-166's `usertype` pass is the place to compare the two forms after W-40 (§11).
- **Typed calls at construction** (the member check and the first typed uses of each `FunctionDynamics` member): small, once per model and session.
- **L-37's workaround** (declaring hot members one by one) does not apply: the members are `FunctionDynamics{typeof(user_f), …}`, whose parameter types the user owns, and an override by a parameter type's owner is Planned (T-28).

---

## 3. The traits

### 3.1 The declarations

In `src/component_dynamics.jl`, replacing step 1's trait (spelling as TraitWorld c655dde takes it):

```julia
using TraitWorld: @trait, @implement, Kept, compiled_for, conforms

"The static facts NetworkDynamics' core loop reads from a component's dynamics, vertex or edge."
@trait ComponentDynamics begin
    @default_with_dynamic_self
    hasf(m::ComponentDynamics)::Bool                                   # false for a static component
    NetworkDynamics.fftype(m::ComponentDynamics)::FeedForwardType
    NetworkDynamics.pdim(m::ComponentDynamics)::Int
    NetworkDynamics.extdim(m::ComponentDynamics)::Int = 0               # a default: no external inputs
end

"""
A vertex's dynamics at the core loop's calling convention. `ins` is a tuple: the aggregated input, then the
external inputs if any. Arguments the feed-forward kind does not read are `nothing`.
"""
@trait VertexDynamics <: ComponentDynamics begin
    @default_with_dynamic_self
    vertexf!(m::VertexDynamics, du, u, ins, p, t)::Nothing
    vertexg!(m::VertexDynamics, out, u, ins, p, t)::Nothing
end

"An edge's dynamics: as a vertex's, with an output at each end; `ins` holds the source's and the destination's outputs."
@trait EdgeDynamics <: ComponentDynamics begin
    @default_with_dynamic_self
    edgef!(m::EdgeDynamics, du, u, ins, p, t)::Nothing
    edgeg!(m::EdgeDynamics, osrc, odst, u, ins, p, t)::Nothing
end
```

- `VertexDynamics`, `EdgeDynamics` and `ComponentDynamics` are exported; the operations are declared `public` (decided at S3-2, recorded).

### 3.2 NetworkDynamics' implementation

```julia
# FunctionDynamics, its fields, hasf, fftype, pdim, extdim, compf! and compg!: as step 1. compf! and compg! are now
# FunctionDynamics' own helpers (plain functions of the package), no longer operations.
vertexf!(d::FunctionDynamics, du, u, ins, p, t) = compf!(d, du, u, ins, p, t)
vertexg!(d::FunctionDynamics, out, u, ins, p, t) = compg!(d, (out,), u, ins, p, t)
edgef!(d::FunctionDynamics, du, u, ins, p, t) = compf!(d, du, u, ins, p, t)
edgeg!(d::FunctionDynamics, osrc, odst, u, ins, p, t) = compg!(d, (osrc, odst), u, ins, p, t)
@implement ComponentDynamics D where {D <: FunctionDynamics}
@implement VertexDynamics D where {D <: FunctionDynamics}
@implement EdgeDynamics D where {D <: FunctionDynamics}
```

The batch keeps its kind's trait, and a conforming user's value as it is:

```julia
# src/network_structure.jl, in ComponentBatch's constructor (kept = true)
_kept_model(::Type{VertexModel}, x) = Kept{VertexDynamics}(x)
_kept_model(::Type{EdgeModel}, x) = Kept{EdgeDynamics}(x)
_kind_trait(::Type{VertexModel}) = VertexDynamics
_kind_trait(::Type{EdgeModel}) = EdgeDynamics
_dynamics(dT, f, g, ff, pdim, extdim) =
    conforms(typeof(f), _kind_trait(dT)) ? f : FunctionDynamics(f, g, ff, pdim, extdim)
# model = kept ? _kept_model(dT, _dynamics(dT, f, g, ff, Int(ps.strides), Int(es.strides))) : nothing
```

- `_process_kept!` takes the kind from the batch vector's type (its first parameter), so no call passes a kept value of one kind to the other kind's bound.
- `_vertex!` calls `vertexf!` and `vertexg!(m, _o, …)`; `_edge!` calls `edgef!` and `edgeg!(m, _osrc, _odst, …)`. The flags stay computed from `hasf`, `fftype`, `pdim`, `extdim` inside the per-component function, as step 1 does them (the traits plan §2.3).

### 3.3 A user's own type

What the workload's `usertype` pass declares (`scripts/workload_types.jl`, in the plain module `NDW`): `swing!` and `line!` under `AntiSymmetric`, as types, with the same arithmetic.

```julia
import NetworkDynamics as ND
using NetworkDynamics: PureStateMap, PureFeedForward
using TraitWorld: @implement

struct Swing end
ND.hasf(::Swing) = true
ND.fftype(::Swing) = PureStateMap()                    # the output is the first state, as g = 1
ND.pdim(::Swing) = 3
function ND.vertexf!(::Swing, dv, v, ins, p, t)
    P, I, γ = p
    dv[1] = v[2]
    dv[2] = (P - γ * v[2] + ins[1][1]) / I
    nothing
end
ND.vertexg!(::Swing, out, v, ins, p, t) = (out[1] = v[1]; nothing)
@implement ND.ComponentDynamics Swing
@implement ND.VertexDynamics Swing

struct Line end
ND.hasf(::Line) = false                                # a static edge
ND.fftype(::Line) = PureFeedForward()
ND.pdim(::Line) = 2
ND.edgef!(::Line, du, u, ins, p, t) = nothing
function ND.edgeg!(::Line, osrc, odst, u, ins, p, t)
    odst[1] = p[1] * sin(ins[1][1] - ins[2][1])        # line!: K * sin(v_s[1] - v_d[1])
    osrc[1] = -odst[1]                                 # AntiSymmetric
    nothing
end
@implement ND.ComponentDynamics Line
@implement ND.EdgeDynamics Line

# step a of the `usertype` pass (step_a(:swing_type) in workload_steps.jl calls it)
usertype_models() = (; vertex = VertexModel(dynamics = Swing(), sym = [:δ, :ω], outsym = [:δ],
                                            psym = [:P_ref, :I => 1, :γ => 0.1]),
                       edge = EdgeModel(dynamics = Line(), outsym = OUTSYM_OF_ANTISYMMETRIC,
                                        psym = [:K => 6.0, :limit => 1.0]))
```

- `OUTSYM_OF_ANTISYMMETRIC` is read from the function model's record (`EdgeModel(g = AntiSymmetric(line!), outsym = :P).outsym`), so that every symbolic index of steps c–g names the same output.
- **The record keyword `dynamics = x`** sets the record's `f = x`, `g = x` and `ff = fftype(x)`. The record gains no field. Its arity checks of `f` and `g` (`component_functions.jl:569–570`) are skipped for a value whose type conforms to the kind's trait. `pdim(x)` and `extdim` (through `Kept{…}(x)`, since a default serves kept values, not plain calls) are checked against the record's `psym` and `extin` at construction: `ArgumentError` naming both.
- Batches are grouped by the record's `compf` as today (`construction.jl:259`): one batch per model value.
- **Where user types are refused, with a message:** `KAExecution` and `PolyesterExecution` (typed batches call `f` and `g`); sparsity detection and the CUDA adaptation, which rewrite the raw functions (PB-5; opening a kept value at its own type is Open, open issue 16).

### 3.4 Why this shape

- **Per kind, not one trait for both.** The kind is a fact of the batch, so the bound can name it: `run_vertex_batch!(m::VertexDynamics, …)`. Two names avoid the joint-method rule for unrelated bounds at one position (traits §5.5; expl. §10.12). A user's vertex type implements the vertex calls only.
- **The supertrait holds the static facts once.** `@trait VertexDynamics <: ComponentDynamics` makes `hasf`, `fftype`, `pdim` and `extdim` available through a `VertexDynamics` bound (traits §3.6). This is expl. §3.2's shape.
- **No generic implementation.** The traits plan §4 named one ("ND serves `ComponentDynamics` for them by a generic implementation"). With the batches per kind it is not needed. It would also cost: the table does not serve a type that conforms through a generic implementation, so its crossings take the generic path (lowering §9.3); T-52 accepts a non-conforming member with a warning; a type implementing both kinds would meet two overlapping generic implementations (T-9).
- **Calls at the core loop's convention.** `ins` as a tuple and `nothing` for what the feed-forward kind does not read keep the views and the flags where step 1 put them. The user's functions see what upstream's `f` and `g` see, without the splat.
- **Untyped buffer arguments,** as in step 1: the loop runs at `Float64`, at the duals of the fixed point and of Rodas5P, at sparsity tracers, and with `t === nothing` (the traits plan §1.2).
- **Defaults:** `extdim` only. A default `hasf = true` would let a static edge forget to say so, and its `f` operation would still have to exist; `hasf` stays required.
- **What the declaration checks for a user's type:** that the methods exist. With untyped declared arguments the check does not infer the calls (traits plan §2.6; expl. §10.13). `pdim`, `fftype` and `hasf` have concrete arguments and are inferred: a `pdim` returning a `Float64` is refused at `@implement`.

### 3.5 Each construct against TraitWorld c655dde

| Construct | Where | Status | Deviations met |
|---|---|---|---|
| a supertrait without parameters, `VertexDynamics <: ComponentDynamics` | [§3.6](../reference/traits.md#36-supertraits-and-bundles) | Implemented | T-68 not met (no fields). The agreement is checked against a type's own implementations; families are not (the reference says so) |
| a default for an operation (`extdim`) | [§3.2](../reference/traits.md#32-defaults) | Implemented | T-2 not met (no parameters) |
| `@default_with_dynamic_self` on each trait | [§6.3](../reference/traits.md#63-defaults-a-traits-default-and-annotations) | Implemented | per trait, not inherited |
| three families over one type, variable form, by its own methods | [§4.7](../reference/traits.md#47-families) | Implemented | T-57 avoided (no block); L-37 (typed calls; the steady state's calls are untyped, §2.5); L-38 (one registry method per family: three in NetworkDynamics) |
| one-line implementations of two traits by a plain module for its own types | [§4.2](../reference/traits.md#42-one-line), [§10.1](../reference/traits.md#101-who-may-implement) | Implemented | none |
| `Kept{VertexDynamics}(x)` held through a struct's type parameter; `compiled_for(k)` at a bound, from code not bounded on it | [§7.1](../reference/traits.md#71-the-three-forms), [§6.4](../reference/traits.md#64-casts) | Implemented | the crossing's cost depends on the ordinary arguments' annotations; at most eight arguments (§7, candidate rows) |
| `conforms(T, X)` at construction | [§14](../reference/traits.md#14-membership) | Implemented | none |
| a closure over a trait object passed to Base (`Threads.@threads`) | [§5.3](../reference/traits.md#53-what-trait-code-may-do-with-a-trait-object) | Implemented | as in step 1 |

**Nothing Planned is needed; no known deviation blocks.** S3-0 (c) checks the supertrait with three families in a scratch module before S3-2 depends on it.

---

## 4. The changes, a function at a time

The checks:
- **(P)** NetworkDynamics and its extensions precompile in `env_merged` (strict mode on, as E-165's check P), which runs the trait module's definition checks;
- **(R)** `scripts/rhs_check.jl` in setting M: every hash equal to U's (`logs/p4/rhs-U.log`), `sametype`, `allocs`, `ns`; the threaded style with two threads. `rhs_p4.sh` gains the environment and the depot as variables if it has none;
- **(X)** `scripts/p4s3_rhs_split.jl`: the right-hand side's ns and allocations, and per pass the crossing into an empty batch and into the full batch;
- **(W)** the workload in setting M, one run, strict off, `compare_digests.py --exact` against E-151's U log;
- **(T)** ND's test subset, `nd_tests.sh` in `env_ndtest_p4pin` (depot `depot-p4pin`).

| # | File (at 324bcb7) | Function | Change | Check |
|---|---|---|---|---|
| S3-0 | `ndport/scripts/p4s3_cross_shapes.jl`, `p4s3_rhs_split.jl` (new, from the planning probes); E-166 registered, status running | — | **(a)** both scripts run, logs in `logs/p4s3/s0-*.log`: the before. **(b)** the split attributes the right-hand side's excess over typed batches once: the crossings, the `Ref`s, the passes without batches, by difference; a profile of 10⁵ right-hand sides if the difference is large. **(c)** in a scratch trait module on c655dde: §3.1's three traits, a family of all three over a stand-in for `FunctionDynamics`, a one-line `Swing` of two traits from a plain module, `Kept{VertexDynamics}` through a bounded function. A few minutes | logs |
| S3-1 | `src/coreloop.jl` | `run_vertex_batch!`, `run_edge_batch!` | the ordinary arguments untyped (§2.3); nothing else | P, R, X (the crossing ≤ 90 ns), W (step d) |
| S3-2 | `src/component_dynamics.jl` | `ComponentDynamics`, `VertexDynamics`, `EdgeDynamics`; `FunctionDynamics`' methods and families | §3.1, §3.2; `compf!`/`compg!` become plain helpers; nothing calls the new operations yet | P, R; every component of the check networks: `vertexf!`/`vertexg!` (or the edge operations) on a `Kept{…}` give `apply_compf`/`apply_compg`'s bits (as step 1's S1 lines) |
| S3-3 | `src/network_structure.jl` (`ComponentBatch`, `constructorof`), `src/coreloop.jl` (`KeptBatch`, `_process_kept!`, the batch functions, `_vertex!`, `_edge!`) | the batches per kind | `_kept_model`, `_dynamics` (§3.2); the bounds `m::VertexDynamics`, `m::EdgeDynamics`; `_process_kept!` by the vector's kind; `_vertex!`/`_edge!` call the kind's operations | P, R (`sametype=true`), X, W, T |
| S3-4 | `src/component_functions.jl` (`_fill_defaults`, `_construct_comp`, `chk_component`), `src/construction.jl` (the execution-style and sparsity refusals); `ndport/scripts/workload_types.jl` (new), `workload_steps.jl`, `workload.jl`, `rhs_check_nets.jl` | `VertexModel(dynamics = x)`, `EdgeModel(dynamics = x)`; the `usertype` pass | §3.3. The pass runs a–g with the model `:swing_type` when `NDW_PASSES` names it; a step that throws prints `D usertype <step> error=<type>` and ends the pass (as `graphtype`). `rhs_check.jl` gains tier S on `Swing`/`Line` for the sequential and threaded styles: hashes equal to tier S on `swing!`/`line!`, and `sametype` across the two | P, R, one U run with `usertype` (a fails: the keyword does not exist upstream) and byte-identity of the common passes; W with `usertype` (`--as=usertype:first`) |
| S3-5 | `ndport/` | — | E-166's runs (§5.1) | §5 |
| S3-6 | `ndport/README.md`, `logs/p4s3/NOTES.md`; for the coordinator: the pushback entries (§7), the guideline's B5 lessons (§8), the choices (§9), the evidence row | — | commits in `ndport/` and in the worktree | — |

- **Exact equality is expected at every row.** S3-1 changes only annotations. S3-2 and S3-3 call the same user functions on the same views in the same order. S3-4's types do the same arithmetic as `swing!` and `line!` under `AntiSymmetric`.
- **ND's precompile workload** (`TraitWorld.@workload`) builds function models only; it then holds the batch functions for the workload's keys, as now.

### 4.1 What does not change

- The `Network` struct and its constructor; the record types' fields; the public signatures except the new keyword `dynamics`.
- `apply_comp!`, the KA kernels and the Polyester path, for typed batches.
- `get_buffers`, the aggregators, the gather buffers, symbolic indexing, callbacks, initialization.
- Graphs and `GraphInterface` (step 2).

---

## 5. Checks and criteria

### 5.1 Settings and runs

- **U:** `env_upstream`, the reference for results (E-151's U log); one run with `NDW_PASSES=first,again,params,changed,usertype` at S3-4 (the before of the `usertype` pass; byte-identity of the common passes).
- **M-0:** E-165's logs (`logs/merge/R-strict0`, `R-strict1*`, `CH`): the before of this step.
- **M-3:** setting M after S3-6, at NetworkDynamics' last commit:
  - two runs strict off with `usertype` added;
  - one run strict on (`NDW_STRICT=1`) with `usertype`;
  - one attribution run (`NDW_DIAG=1`) with `usertype`;
  - one census and profile run (`NDW_SCRIPT=scripts/p6_census.jl`, as E-165's CH);
  - X and T once.
- Every run records the julia-1.13 build, TraitWorld c655dde, strict mode, the load order (P1's), two cores, idle I/O, and the load before and after (a run above 4 is repeated). With n = 2 the numbers are indicative.
- **What the numbers measure:** NetworkDynamics' trait code calling the user's plain functions (`FunctionDynamics`): interop. The `usertype` pass's models are idiomatic trait code (a user's types implementing the traits), reported apart.

### 5.2 Criteria

| # | Criterion | Before | Pass when |
|---|---|---|---|
| 0 | Results | M-0: 0 exact differences, strict off and on | the common passes `--exact` against U in every M-3 log; every R hash equal to U's; the `usertype` pass's digests a–g equal to the same session's `first` (`--as=usertype:first`). A gate |
| 1 | One network type | `sametype=true` | `sametype=true` for `swing!`/`swing2!`, and for the function models against `Swing`/`Line`. A gate |
| 2 | The crossing | 162–172 ns per crossing (planning probe C; S3-0's log replaces it) | ≤ 90 ns after S3-1 (X); reported at S3-3 and M-3 |
| 3 | Steady state, strict off | M-0: c / d / e 5.2 / 34.7 / 1.0 ms (P4P's d 34.4–35.0) | d ≤ **32.0 ms**, the minimum of two runs; c and e at most 1.10 × M-0's + 0.5 ms. A miss on d is confirmed by one more run. Reported against P6's 16.8 and U's 15.3 ms |
| 4 | Steady state, strict on | M-0: d 35.9–37.8 ms | reported; d at most 1.10 × strict off's + 5 ms |
| 5 | New equations compile | changed b–e 0.56 s | changed b–e ≤ 1.0 s in both runs. The `usertype` pass: b–e compile time reported; its new CodeInstances of SciML's packages and SymbolicIndexingInterface in b–e ≤ 50 (attribution run; E-152's list of modules) |
| 6 | Strict mode | one refusal: OffsetArrays' `reshape` at the plotting load | strict on: no refusal or warning naming NetworkDynamics, `NDW`'s implementations or TraitWorld's generated code; the extension warnings as M-0's |
| 7 | The census | NetworkDynamics 1 (L-38), every other wrapped package 0; joint as at S7 | NetworkDynamics: L-38's registry methods only (expected three, one per family); every other package as M-0 |
| 8 | ND's tests | `logs/p4g/ndtest-g3-pin.log`: massmatrix 6, doctor 26, diffusion 111 + 1 fail, inhomogeneous 43 + 2 fail (P4-1's three allocation assertions) | the same passes; the allocation counts of the three failing assertions reported |
| 9 | The right-hand side | 1,794 ns, 5 allocations (planning probe C); U 0.50 µs, 0 | reported (R, X): function models and `Swing`/`Line`, expected equal (§2.5) |

### 5.3 What a failure changes

- **Criteria 0, 1:** a port bug, fixed first. A `usertype` digest that differs is a difference in the type's arithmetic (the order in `edgeg!`), fixed in `workload_types.jl`.
- **Criterion 2 missed at S3-1:** ND's crossing differs from the probe's. `fully_typed` at the worker and the dispatch profile name the site; the finding goes to the candidate row (§7). The step continues: the traits do not depend on it.
- **Criterion 3 missed, confirmed:** the gain is smaller than the reading of §2.3. X's split says where the time is. The numbers go to P4-1. The step's other parts stand; nothing pauses.
- **Steady state worse at S3-3 than at S3-1** beyond 5 % + 0.5 ms: the per-kind traits cost something the reading does not show. Attributed with X and the profile; recorded.
- **Criterion 5 missed:** the attribution run names the module and the type that varies.
- **Criterion 6:** a refusal in NetworkDynamics or in `NDW`'s implementations is a TraitWorld or strict-mode finding, reported to the reference's owner as a T- or F- row.
- **Criterion 7:** a pirate beyond L-38's registry methods is investigated before the outcome is written.
- **S3-0 (c) refuses the supertrait with families:** `VertexDynamics` and `EdgeDynamics` become traits of their own, each declaring the four static operations; a pushback entry records it (§7).

---

## 6. The registry row

To be added to `writeup/record/experiments.md` §11 with status running before S3-0's first run.

| ID | Question | Status (date) | Where (scripts/logs) | Outcome | Written up in |
|---|---|---|---|---|---|
| E-166 | W-32 P4, step 3: the batches' crossings and the component traits per kind ([the step-3 plan](../plans/2026-10-22-ndport-step3.md)). NetworkDynamics' batch functions take their ordinary arguments untyped (planning probe: an abstract annotation makes each crossing from a kept value a dynamic call, 150–215 against 50–75 ns); `VertexDynamics` and `EdgeDynamics`, subtraits of `ComponentDynamics`, kept per kind in the batches; a user's own types (`Swing`, `Line`) through `VertexModel(dynamics = …)`, in a `usertype` pass of the workload. Setting M (`env_merged`, `depot-merged`), julia-1.13 as E-165, TraitWorld c655dde, product setting, P1's load order, two cores; two runs strict off, one strict on, one attribution run, one census run; against U (results) and E-165's M (the before). (0) Are the common passes and the right-hand-side checks exactly equal to U, strict off and on, and the `usertype` pass's digests equal to the `first` pass's? (1) Is the network's type the same for `swing!`, `swing2!` and the user's types? (2) What does a crossing cost after the change (before 160–170 ns)? (3) Is step d's steady state at most 32.0 ms strict off (before 34.7; P6 16.8; U 15.3)? (4) Do changed b–e still compile in at most 1.0 s, and does a new model type compile no SciML code? (5) Does strict mode refuse nothing in NetworkDynamics or in the user's implementations, and does the census count only L-38's registry methods? (6) Does ND's test subset pass as before? Measures library trait code calling plain user functions (interop), and a user's types implementing the traits (idiomatic), apart. **Would change the plan:** an exact difference (a port bug); the crossing not cheaper in NetworkDynamics (a TraitWorld finding, the candidate row); d above 32.0 ms, confirmed (the split names the time; P4-1 updated); a refusal under strict mode in the port's code; the supertrait with families refused (traits of their own, a pushback entry). | proposed (2026-10-22) | `ndport/` (its own repository): `scripts/p4s3_cross_shapes.jl`, `p4s3_rhs_split.jl`, `rhs_check.jl`, `rhs_check_nets.jl`, `workload.jl`, `workload_steps.jl`, `workload_types.jl`, `run_workload.sh` (setting M, `NDW_PASSES` with `usertype`), `nd_tests.sh`; `logs/p4s3/`; the worktree `pkgs/NetworkDynamics-p4`, branch `port` | — | `ndport/README.md`; `ndport/logs/p4s3/NOTES.md`; [the step-3 plan](../plans/2026-10-22-ndport-step3.md) |

When E-166 is done, its outcome and an evidence row in `writeup/design/evidence.md` are written in one commit (CLAUDE.md, rule 1). If the step is split (§10), E-166 closes on 3a's parts and 3b gets the next free ID in a dated addendum to this plan.

---

## 7. Expected pushback entries, and candidate deviation rows

**Pushback**, in the log's shape, numbered on from P4-4. Each is written there once E-166 confirms it.

**P4-1, updated.** "What the port did" gains step 3: the batch functions' ordinary arguments untyped, the crossing's cost before and after, and the floor that remains (§2.4: a lookup and a pointer call per batch, three per right-hand side; the witness carried in a value is Optional).

**P4-5. A value constant per implementation, for a user's type** (the traits plan's PB-1, met by a user's type for the first time).
- **The code:** `ND.pdim(::Swing) = 3`, `ND.fftype(::Swing) = PureStateMap()`. The core loop passes `nothing` for `p` when `pdim` is zero, and builds the views from `fftype`; both must be constants per key for the user's function to receive concrete arguments.
- **The idiomatic form:** an associated constant (Rust's `const PDIM: usize`, Swift's `static let`), which the trait could require.
- **The reference:** a trait's parameters are types ([traits §3.4](../reference/traits.md#34-parameters-and-associated-types)); nothing declares a value constant per type. The record's `psym` and the trait's `pdim` are two sources of one fact, checked equal at construction.
- **What it costs:** a type that returns `pdim` from a field gets `Union` views at its own functions; nothing warns. Measured if S3-4 has time: a `SwingP` reading `pdim` from a field, its right-hand side and `fully_typed`.
- **Blocks:** no.

**P4-6, only if S3-0 (c) refuses it. A supertrait whose subtraits are implemented by families.** The code, the refusal's text, the reference ([§3.6](../reference/traits.md#36-supertraits-and-bundles)), the form taken (traits of their own, the static operations declared twice), the cost (none at run time).

**Candidate deviation rows, for the owner of [`../reference/lowering.md`](../reference/lowering.md)** (found by this plan's probes; to be confirmed by S3-0's committed log before a row is written):
- **The table's call of the worker is dynamic when an ordinary argument of the bounded function is declared with an abstract type** (`::Vector`, `::Base.RefValue`, `::Base.RefValue{A} where {A}`): 150–310 ns per crossing against 50–75 ns for concrete or untyped arguments. Lowering §9.3 says one call through the pointer builds the views and calls the worker for the key. The dispatch profile of E-165 shows the dynamic `checked_call`.
- **The table's call wrapper takes at most eight arguments:** a crossing from a kept value into a bounded function of nine arguments raises `MethodError` (`no method matching (::TraitWorld._UWrap)(::_UCall{…}, …)`). Lowering §9.3 names no limit.

---

## 8. Lessons for the porting guideline (B5), expected from this step

To be written there, in the present tense, once S3-6 confirms them:
- **A bounded function entered from a kept value takes its ordinary arguments concrete or untyped.** An abstract annotation (`::Vector`, `::Base.RefValue`) makes each crossing a dynamic call (while the candidate deviation stands); the table takes at most eight arguments.
- **Measure the crossing on an empty batch.** Its cost against the batch's work says whether the barrier sits where the work behind it is large enough.
- **Keep a library's values per kind, as kept values of the kind's trait** (`Kept{VertexDynamics}`), with the shared static facts in a supertrait. The bound then names the kind, and no generic implementation is needed.
- **A user's own type joins with two one-line implementations,** its static facts as methods that return constants (`pdim(::Swing) = 3`), so that the library's views stay typed.
- **A record keeps the user's value beside its metadata** (`VertexModel(dynamics = x, …)`), and the library checks the trait's static facts against the record's.

---

## 9. Choices for the user to review (for the meta plan's list)

Numbered on from the meta plan's 47:

48. **The crossing's shape first** (S3-1): the batch functions' ordinary arguments untyped, before the traits change. It is measurable alone and changes no result.
49. **The traits per kind:** `VertexDynamics` and `EdgeDynamics`, subtraits of `ComponentDynamics`, which keeps `hasf`, `fftype`, `pdim`, `extdim`. Step 1's `compf!`/`compg!` leave the trait. The batches keep `Kept{VertexDynamics}` and `Kept{EdgeDynamics}`. No generic implementation (§3.4).
50. **The operations' names and convention:** `vertexf!`, `vertexg!`, `edgef!`, `edgeg!`, at the core loop's convention (`ins` a tuple; `nothing` for what the feed-forward kind does not read). The traits exported, the operations `public`.
51. **Defaults:** `extdim = 0` only; `hasf` required.
52. **A user's value enters through the record:** the keyword `dynamics = x` fills the record's `f`, `g` and `ff`; no new field. The batch keeps the value itself when `conforms(typeof(f), …)` holds.
53. **User types refused, with a message,** under `KAExecution`, `PolyesterExecution`, sparsity detection and the CUDA adaptation (PB-5, PB-6, P4-2).
54. **The `usertype` pass:** additive, off by default; `Swing` and `Line` with the arithmetic of `swing!` and `line!` under `AntiSymmetric`; compared with the `first` pass exactly.
55. **TraitWorld stays at c655dde** for this step.
56. **Not taken:** one crossing fewer for `StateMask` outputs; one `Ref` per right-hand side; the per-batch loop as an operation on the kept value (until W-40, §2.5).

---

## 10. Time, order, and the split

| Part | Rows | Work | Machine |
|---|---|---|---|
| 3a | S3-0 | register; commit and run the probes; the scratch declaration check | about 5 min |
| 3a | S3-1 | one signature each; P, R, X, one W | about 8 min (ND rebuild 1–2 min, W 70 s) |
| 3a | S3-2, S3-3 | the traits, the batches per kind; P, R twice; X, W, T | about 15 min (two rebuilds; T about 5 min) |
| 3b | S3-4 | the keyword, the refusals, `workload_types.jl`, the pass, the check networks; P, R, one U run, one W | about 10 min |
| — | S3-5 | E-166's runs (§5.1) | about 12 min (six sessions) |
| — | S3-6 | notes, README table, pushback, guideline, choices, evidence row | — |

- **The whole step: about 4.5–5.5 hours of work,** most of it editing and reading; under an hour of machine time, every job through the lock, between the user's own jobs. An afternoon, tight.
- **The order puts the measurable gain first.** If the afternoon runs short, stop after S3-3: run S3-5 without the `usertype` parts, close E-166 on 3a's criteria (0–4 and 6–9 without the user's types), and do 3b in the next session under the next free ID.
- **Why now, before `ODERHS` (step 4):** P4-1 is the port's largest open cost, and step 4 does not touch it. The user's types complete step 1's trait in the idiomatic form, the port's first idiomatic trait code, judged apart from interop (the traits plan §4).

---

## 11. When to revisit

The traits plan's §6 applies. In addition:
- **W-40 built:** compare the per-batch loop as an operation with a default on the kept value (probe B's form) against the bounded function, on `FunctionDynamics` and on `Swing`/`Line`. If the operation form is cheaper, it becomes the barrier.
- **The candidate rows confirmed and fixed in TraitWorld:** the batch functions' annotations may come back as documentation; the guideline's first lesson changes.
- **The witness carried in a value** leaving Optional: the per-batch floor (§2.4).
- **Step d still far from P6's 16.8 ms after E-166:** S3-0 (b)'s attribution decides whether the `StateMask` special case or the `Ref`s are next, or whether the rest belongs to the facts mode's threads and buffers (the traits plan §2.6).
- **A user's type in a tier M workload,** five or more model types (the split beyond four, expl. §11 item 3), or a model with external inputs.
