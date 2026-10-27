# Julia 1.14.0-alpha1: what is new, and what it means for this project (2026-10-27)

Sources:
- the 1.14.0-alpha1 announcement (2026-10-21, [discourse](https://discourse.julialang.org/t/julia-v1-14-0-alpha1-is-now-available/140136));
- `NEWS.md` on the `release-1.14` branch ([raw](https://raw.githubusercontent.com/JuliaLang/julia/release-1.14/NEWS.md));
- the PRs named below;
- `release-1.14` sources read directly where our patches touch them: `src/gf.c`, `Compiler/src/effects.jl`, `Compiler/src/reinfer.jl`.

Our patched Julia is 1.13.2 (`julia-1.13/`, [`../design/julia-changes.md`](../design/julia-changes.md)). Nothing here was built or run. It is a scan by reading, to decide when and how to move.

## In brief

1. **Inference no longer holds a global lock.** 1.13's `jl_typeinf_lock` around `jl_type_infer` (`gf.c`, verified in `release-1.13`) is gone in 1.14 (`release-1.14` `gf.c`: a reentrancy check and a `sigatomic` region instead). This changes W-40's analysis, and our patches that assumed serialised inference.
2. **`Effects` gains `reset_safe`, at bits 15–16 of the encoded effects.** Our W-52 bit `nortsite` is stored at bit 15. On a move to 1.14 it moves to bit 17.
3. **Global accesses carry binding partitions in lowered code** ([#62452](https://github.com/JuliaLang/julia/pull/62452)). New `Core.*_partition` builtins appear in optimized IR, with binding edges recorded by the optimizer. The facts mode's binding edges and G2's binding exception sit exactly here.
4. **Syntax versions per package** ([#60018](https://github.com/JuliaLang/julia/pull/60018)): a package parses with the syntax version its `Project.toml` names. This is the route by which trait syntax could one day enter the language without breaking anyone (compiler §7, the last step).
5. **Broadcast element types come from one inference query** ([#62564](https://github.com/JuliaLang/julia/pull/62564)), replacing `combine_eltypes`. This touches facts §7.1's list of values decided by inference.
6. **Task cancellation** ([#60281](https://github.com/JuliaLang/julia/pull/60281)): cancellation points, resets, the `reset_safe` effect. Inference runs under `sigatomic`, so no reset interrupts it.

## Strategic items

### 1. No global inference lock

- **What changed.** `release-1.14`'s `jl_type_infer` has no `JL_LOCK(&jl_typeinf_lock)`. It keeps the reentrancy guard on a MethodInstance the thread already reserves (`jl_engine_hasreserved`) and wraps inference in a `sigatomic` region ("sigatomic defers asynchronous unwinds (e.g. task abandonment) until inference has finished"). In 1.13 the lock is there, marked temporary.
- **For us:**
  - W-40 ([the note](../plans/2026-10-26-w40-member-builder-fold.md) §10, §11): the first review's B1 was a deadlock between the inference lock and TraitWorld's lock. In 1.14 that lock is gone, but folds then run on several threads truly at once. The discipline stays (no waiting on TraitWorld's lock, no yield), and the thread checks in §7 become meaningful, where under 1.13 they prove little.
  - The facts mode's own state shared across inferences (the split's candidate registry, `SPLIT_TABLES`, the plain `return_type` cache) is copy-on-write or atomic already ([compiler §4.2](../reference/compiler.md#42-compilersplit_call-the-call-site-split), §4.3). It should be reviewed for concurrent inference before a move.
- **Recommendation:** watch; plan the move for 1.14.0 final. Revisit W-40's §7 thread checks on 1.14.

### 2. `reset_safe` in `Effects`

- **What changed.** `Effects` has a field `reset_safe::UInt8`, encoded at shift 15 and read back with a two-bit mask (bits 15–16). The fields' order also changes: `reset_safe` follows `effect_free`.
- **For us:** julia-1.13 0c589fd385 (W-52) adds `nortsite` at bit 15, stored inverted. It collides. On a move: `nortsite` at bit 17; the positional `Effects` constructor gains our field after `reset_safe`.
- **Recommendation:** rebase cost, small. Note it in [`../design/julia-changes.md`](../design/julia-changes.md)'s W-52 row when moving.

### 3. Binding partitions in lowered code

- **What changed** ([#62452](https://github.com/JuliaLang/julia/pull/62452), merged 2026-09-17):
  - the optimizer's `GLOBALS` pass resolves each global access to its partition;
  - inference records a binding edge per access with a world range;
  - constant reads fold "now soundly, because of the edge";
  - new builtins: `getglobal_partition`, `setglobal_partition` and their kin;
  - code that inspects optimized IR sees new operand types.
- **For us:**
  - The facts mode treats binding edges as allowed edges ([facts G2](../reference/facts.md#g2)), so the rule holds. But TraitWorld's checks that walk optimized IR (`verify_main`, the keep analysis, fully typed mode) must learn the new operands.
  - `rests_on_facts` (`facts.jl`) and the W-40 record's walkers handle `Core.Binding` edges already.
  - Image validation in 1.14 also adds a `Core.PossiblyAmbiguous` marker before an edge (`reinfer.jl`), which our walkers must skip as well.
- **Recommendation:** rebase cost, moderate, in TraitWorld's IR walkers.

### 4. Syntax versions

- **What changed** ([#60018](https://github.com/JuliaLang/julia/pull/60018)): `syntax.julia_version` in `Project.toml` (default: the lowest Julia in compat) selects the parser's revision for the package. Macros see the calling module's syntax. The author: "I'm not proposing using this for any big syntax revolutions", the aim being to clean up corners.
- **For us:**
  - The design's last step ([compiler §7](../reference/compiler.md#7-traits-in-the-type-system)) brings traits into the type system and then into syntax. A versioned parser is the mechanism by which `trait` and `implement` could become keywords for packages that opt in, while every other package parses as before.
  - It also gives macros like `@trait_module` a defined contract across versions.
- **Recommendation:** an opportunity for the upstream proposals ([`../design/julia-changes.md`](../design/julia-changes.md) §4): name it there as the route for syntax.

### 5. Broadcast element types

- **What changed** ([#62564](https://github.com/JuliaLang/julia/pull/62564)): `Broadcast.result_eltype(bc)`, one inferred return type of the element computation, replaces `combine_eltypes`. Array leaves are read at their declared element types behind an inference barrier.
- **For us:** [facts §2.1](../reference/facts.md#g1) and §7.1 list broadcast element types among the values decided by inference, answered by plain inference under the facts mode. The mechanism changes; whether the answer is still a `return_type` query under the facts mode's rules is to check before a move.
- **Recommendation:** watch; a check on a move (acceptance G1.9 and G1.11 cover `return_type`).

### 6. Task cancellation

- **What changed** ([#60281](https://github.com/JuliaLang/julia/pull/60281)): cancellation sources and tokens, `@cancel_check`, resets to the last cancellation point, `@ccall reset_safe=`. Inference runs in a `sigatomic` region.
- **For us:**
  - W-40's `g` runs inside inference, so no reset reaches it.
  - The run-time path (the slow path, the split table's miss) is ordinary code and can be reset at a cancellation point. TraitWorld's registries are copy-on-write and published atomically, so a reset leaves them consistent.
  - Warnings queued by the fold are flushed on the run-time path; a reset there loses at most a warning.
- **Recommendation:** watch.

## Rebase cost from 1.13 to 1.14, by our patched area

| Our area ([julia-changes](../design/julia-changes.md)) | 1.14 upstream | Cost |
|---|---|---|
| Facts mode in inference (`abstractinterpretation.jl`, `facts.jl`) | binding partitions in IR (#62452); field types refined through conditionals (#41199, #47574) | moderate |
| Effects (W-52 `nortsite`) | `reset_safe` at bits 15–16 | small: move to bit 17 |
| Owners, dispatch from facts code, call-site caches (`gf.c`) | no global inference lock | moderate: review shared state for concurrent inference |
| Image validation (`reinfer.jl`; W-40's records) | `Core.PossiblyAmbiguous` marker | small |
| Definition and image-activation hooks (`gf.c`, `staticdata.c`) | not seen changed in the parts read | to check |
| `--trim` | a static, JIT-free `libjulia-internal.a` for JuliaC (#63618); `Libdl.LazyLibrary` incompatible with `--trim` | small, and helpful for trimmed binaries |
| TraitWorld's macros (struct and body rewrites) | `typegroup` blocks (#60569), `@label` blocks (#60481) | small: pass them through, rewrite structs inside a `typegroup` |
| TraitWorld's `ccall(:jl_generating_output)` | `Base.generating_output()` public (#61224) | none: use it |

## Everything else new in 1.14, briefly

- `Type{T} <: S` only if every type equal to `T` is an instance of `S` (#33136, #62141); TraitWorld does not rely on `Type{X} <: DataType` (grep).
- Primitive types of any bit width, and `Core.sizeof` rounding to alignment (#61359, #61361).
- Inference refines immutable and `const` field types through conditionals and call signatures (#41199, #47574).
- Parallel precompilation shares one thread budget, `JULIA_PRECOMPILE_THREADS` (#61958); cache file names include Pkg's `environment_id` (#63268).
- Coverage and instrumented package images reworked (#62514, #62724).
- `fetch(::Task)` infers its result (#59221); reference forms of `@atomic` (#62382); asymmetric fences (#60311).
- `@methods` in InteractiveUtils (#62311); `Test.detect_closure_boxes` (#60478).
- `StringView` in Base (#60526); `tap`, `unsplat` (#61340, #62714).
- A SAT resolver in Pkg; `[compat-overrides]`; comments kept in `Project.toml`.
- Optimized (`+opt`, PGO/LTO/BOLT, about 10% faster precompile and load) and assertion builds, experimental.
