# Plan: declared results that never depend on inference (open issue 171)

Status: **proposal** (2026-11-09, night), for a Fable review before it is built. The user (2026-11-09): "For tonight, Focus on fixing unsound rules and deviations. For each come up with a plan, have a Fable agent review it, and act on the review."

## 1. The fault

The rule as built ([traits §7.9](../reference/traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait), [compiler §7.2](../reference/compiler.md#72-the-split); open issue 168 (a), mine, E-333, `unified` 0c836f3ef6):
- a call of an operation at a value typed by its set, or by a closed abstract type with a contract, has the operation's declared result;
- each branch through a pointer and the fallback **convert** the member's result to it (`Base._to_declared`) and assert it (`Compiler/src/ssair/inlining.jl:739`, `:1988`).

The conversion was introduced for `IO` as a set, whose members Core's streams and `Filesystem.File` return a `UInt` count where `IO` declares `Int` (open issue 168).

The fault ([the documentation review](../reviews/2026-11-09-documentation-consistency.md), H4; checked in the main session; `experiments/unification/audit/probe_result_by_inference.jl` with its log):
- On `unified` b05ae361e0, `struct S <: IO end; Base.write(::S, ::UInt8) = UInt(7)`.
- `write(v[1], 0x01)` returns `Int64` for `v::Vector{IO}`, `UInt64` for `v::Vector{Any}`, and `UInt64` for both under `--compile=min`.
- A stream whose `write` returns a `String` raises `MethodError` through `Vector{IO}` and returns through `Vector{Any}`.
- So the conversion lives where inference makes the split, and a result's *value* depends on what inference knows.

Against the guarantees:
- [facts §2.1](../reference/facts.md#21-g1-identical-or-error), G1: the same result, **or raises**, where a value lacks a declared result type. A converted value is neither.
- [facts §13.1](../reference/facts.md#131-the-product-setting): plain code keeps all of Julia's behaviour. A value typed `IO` is plain code's everyday case.

## 2. The fix

### 2.1 A closed abstract type with a contract declares no result

- At a closed type, nothing joins later and nothing is checked: Julia's streams are members by `struct S <: IO`. No declared result can be guaranteed for a user's stream.
- **Rule** ([compiler §7.1](../reference/compiler.md#71-the-rule), [§7.5](../reference/compiler.md#75-io), [traits §3.4](../reference/traits.md#34-open-and-closed), [§9b](../reference/traits.md#9b-streams-io)): a closed abstract type's contract names its operations and its candidates. An operation's result at a value typed by the type is `Any`, Julia's own answer at such a receiver. The split branches over the candidates with direct calls and the table past them, and neither converts nor asserts.
- `base/iotrait.jl`: each operation's declared result `Any` (`jl_method_set_declared_result(m, Any, 1)` keeps the operation's flag that the split reads).
- What is lost: `write`'s `Int`, `read(io, UInt8)`'s `UInt8` and `haskey`'s `Bool` at a value typed `IO`. Vanilla infers `Any` at such a receiver for each of them (dozens of methods, past `max_methods`), so plain code infers what it infers on vanilla. The split's direct calls and its firewall stay.
- Core's streams and `Filesystem.File` keep their `UInt` counts, as on vanilla (unchanged since b05ae361e0).

### 2.2 A call through a trait asserts, never converts

- At a set, every member is checked against the declared result at its membership or first use ([traits §5.10](../reference/traits.md#510-checks)), so the conversion is the identity for a checked member. It changes a value only for a member that escaped the check (a method redefined later, a member by its declared supertype: open issue 168).
- **Rule** (traits §7.9, §11; compiler §7.2): the call's result is the declared result, **asserted**: a result of another type raises a `TypeError`. That is G1's "or raises". A dynamic call of the same operation returns the member's own result, which the check made the declared type for a checked member.
- `Compiler/src/ssair/inlining.jl`: the `_to_declared` call goes from the split's branches, the fallback and `handle_declared_result!`; only the `typeassert` stays. `declared_converts`, `info.convert` and `Base._to_declared` with `SPLIT_TARGET`'s use for it go, if nothing else uses them.

### 2.3 Base's own counts

- With 2.1, nothing asks Core's streams or `Filesystem.File` for an `Int`. They stay as on vanilla.

## 3. Alternatives considered

- **(b) Base's counts made `Int` and the call asserting at `IO`** (171 (b)): Base's streams agree in every mode, but a user's stream returning a `UInt` raises through `IO` and not through `Any`. Raising that depends on inference, in plain code. Rejected for a closed type.
- **(c) The conversion in the member** (171 (c)): a method serving an operation converts its own result wherever it is called. That is inference-independent, but for `IO` it rewrites plain methods' results (`write(::S, ::UInt8)` returning `Int` even when called directly), a change to plain code's behaviour. At a set it needs the library to wrap every serving method. Rejected for now; it would return only if assertion at sets proves too strict for the ports.
- **(d) The split's result as the join of the candidates' inferred results and the fallback's ordinary inference at the receiver:** sound and sometimes more precise than `Any`. But at `IO` the fallback's ordinary inference is `Any` (too many methods), so it gains nothing there and adds a second inference per call. Deferred; it may matter for a closed type with few methods.

## 4. Gates

- `n19_io_trait` (2): `UIntIO`'s `write` through `wb(@nospecialize(io::IO), …)` and through `IOContext{IO}` returns `UInt(1)`, the same as through `Vector{Any}` and under `--compile=min`. `BadIO` returns `"one"` through each. The split still branches over the candidates with no candidate edges, as checked now.
- `experiments/unification/audit/probe_result_by_inference.jl` becomes a gate case: every line prints what the stream's own method returns, compiled and with `--compile=min`.
- A gate at a set (`n16_declared_result` or a new case in `n19`): a member by `struct S <: X` whose operation's method returns another integer type raises a `TypeError` through the trait, and returns its own value by a dynamic call.
- The battery; the forks' digests and the REPL transcript; TraitDifferentialEquations' suite; TraitReport's forms. These show whether a port relied on a conversion.
- Measured, not gated (no speed target, decisions §5): E-328's workloads on the eraser and the forks' `show` and `write` steps, to record what `Any` costs.

## 5. What changes in the record

- traits §3.4, §7.9, §9b, §11 (the errors' table: `MethodError` "a result that does not convert" goes); compiler §7.1, §7.2, §7.5; facts §2.1, §9, §13.1, §14 (the exception and the Open marks of 171 go); `design.md` §4; the glossary's Split; `intro/porting.md` if it mentions the conversion.
- Open issue 171 closed (2.1 and 2.2); open issue 168: (a) replaced by assertion, recommendation updated; the decision row "A call through a trait converts a member's result" superseded by a row for 2.1 and 2.2; `design/alternatives.md`: the conversion, with E-333 and the reason.
- The registry: E-340 before the run.

## 6. Risks

- **A port relies on the conversion at a set:** a checked member never needed it. A `TypeError` names the member that escaped its check, which is the check's own fault to fix (168).
- **Speed at `IO`:** a call's result `Any` where `Int` was. A count accumulated through a value typed `IO` becomes a dynamic `+`, as on vanilla. Formatted output ignores the counts.
- **The eraser `IOContext{IO}`:** its forwarding methods return what the split returns, `Any`, as `IOContext{IO_t}` with an abstract `IO_t` does on vanilla.
