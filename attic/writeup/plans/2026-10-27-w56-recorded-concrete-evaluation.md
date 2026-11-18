# W-56: concrete evaluation over run-time sites, with the dispatches it performs recorded as edges

Status: **deferred** (2026-10-27): [its review](../reviews/2026-10-27-w56-recorded-concrete-evaluation.md) found the recorder unsound as drafted; W-57 (Base's asserted helpers fully typed) instead. Not normative.

Serves: [W-56](../record/todo.md); [open issue 66](../open-issues.md#4-runtime-and-measurements); [facts §8](../reference/facts.md#asserted-effects); [compiler §1.3](../reference/compiler.md#13-run-time-sites), §1.5; E-162.

## 1. The problem

W-52 (julia-1.13 0c589fd385) made the facts mode's rule hold as written: no asserted effect applies over a run-time site, at any depth. That closed a G1 hole. It also stopped folds that Base relies on:
- `array_subpadding(S, T)` is asserted `:total`; it calls `padding(T::DataType)`, asserted `:foldable`.
- Inside `padding`, the calls on `T::DataType` (`fieldoffset`, `datatype_fieldcount`, `getproperty`) are run-time sites under the facts mode: at `DataType` any type's owner may add a method for its own type (`fieldoffset(::Type{MyT}, …)`), so the signature is no fact.
- So the frame of `array_subpadding` holds a run-time site through its callee, and its assertion no longer applies. `array_subpadding(Dual{…}, Float64)` is computed at every `reinterpret` of dual numbers, with hundreds of thousands of dynamic dispatches per solve.
- In the port, a Rodas5P solve takes 311–339 ms against Tsit5's 4.5 ms; step d's steady state 267.7 ms against 33–47 ms before W-52 (E-162; `ndport/logs/p4-regress-*.log`). Results stay bit-equal.

## 2. The idea

A run-time site is no fact because its argument *types* admit methods of many owners. But a concrete evaluation runs the call on *values*. Every dynamic dispatch it performs is at the concrete signature of the values it meets:
- `fieldoffset(Dual{Float64,Float64,1}, 2)` dispatches at `Tuple{typeof(fieldoffset), Type{Dual{Float64,Float64,1}}, Int}`;
- that is a dispatch tuple, a fact signature ([facts §3](../reference/facts.md#facts-and-fact-signatures));
- its stakeholders are Julia's and `Dual`'s owners: only they, or a pirate, can change what it selects.

So a fold made by a concrete evaluation rests on the facts it actually used. If those facts are recorded as the caller's edges, the fold is valid exactly as long as they hold. G1 and G2 hold for it as for any code compiled by facts.

## 3. The design

**The runtime: a dispatch recorder** (`src/gf.c`).
- `jl_dispatch_record_begin()` and `jl_dispatch_record_end() -> Vector{Any}` on the current task.
- While recording, every generic dispatch (`jl_apply_generic`, cache hit or miss, and `invoke`'s lookup) appends the signature it dispatched at, with a type-valued argument as `Type{T}`, and the method it selected.
- Off, it costs one predictable branch per dispatch; or the recorder is a separate entry the concrete evaluator calls through, so the common path is unchanged. To measure.

**The compiler: recorded concrete evaluation** (`Compiler/src/abstractinterpretation.jl`, `concrete_eval_call`).
- Under the facts mode, where a call's effects are not foldable only because an assertion was dropped over a run-time site (the callee's method asserts, its effects have `nortsite` clear), and every argument is a constant:
  1. the call is evaluated concretely with the recorder on;
  2. if every recorded signature is a fact signature, the call folds to its value, and each record becomes an edge of the caller: the signature and the method it selected (the edge form `1, sig, method`, verified at load as any dispatch edge);
  3. otherwise (a signature that is no fact, an error, a dispatch at a kind's value with a free parameter), nothing folds and nothing changes.
- The effects the evaluation may assume are the assertion's, as in plain Julia: the asserter promises consistency and termination; the records make the dispatch part of that promise checkable.

**Images.** The edges are ordinary dispatch edges: image validation checks them at load as it checks any (`reinfer.jl`, `verify_call`).

## 4. Questions for review

- Can the recorder see every dispatch a concrete evaluation performs: calls through `invokelatest`, `Core._apply_iterate`, keyword sorters, `jl_invoke` of cached specializations without a lookup?
- Is the edge form `1, sig, method` right for a dispatch whose result is one method at a dispatch tuple, including "no method" (a `MethodError` caught inside the call)?
- Re-entrancy: concrete evaluation may trigger inference (a JIT of the callee); the recorder must follow the task, not the thread.
- The cost at compile time: an evaluation per call site per signature, as plain Julia's concrete evaluation.

## 5. Validation

- E-162's step d with Rodas5P back near its earlier 33–47 ms (P4, the same build otherwise).
- Acceptance: G1.32 and G1.33 still pass; a new check that a recorded fold follows a stakeholder's new method at one of its recorded signatures (a `fieldoffset(::Type{MyT}, …)` method), and that an unrelated load invalidates nothing (G2).
- Every suite.
