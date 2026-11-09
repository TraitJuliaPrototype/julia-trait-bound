# Plan: two small deviations, C-57 and C-81

Status: **adopted with the review's changes** (2026-11-10; [the review](../reviews/2026-11-09-plan-review-c57-c81.md)), built as `unified` 0ee9e4f8a6 (C-57) and 18bbbf0841 (C-81), E-340. The user (2026-11-09): "For tonight, Focus on fixing unsound rules and deviations. For each come up with a plan, have a Fable agent review it, and act on the review."

Neither is unsound. Each is a place where the build falls short of a rule of the references, and each fix is small and at the rule.

## 1. C-57: a call's dispatch fact at its own signature, for G2

**The rule** ([compiler §6.3](../reference/compiler.md#63-the-attribute-at-a-call)): a call records its dispatch fact at its own signature, whichever instance runs.

**The deviation** (C-57): a static call that runs an instance compiled once (a method at a set with the default `Dynamic`, or a `@nospecialize` argument) records the instance's signature, at the set, as its dispatch edge. That signature is not a fact signature, so the caller's G2 bit is clear (compiler §3.2), and an image drops the caller's code where it is reached only dynamically (§9).

**What changed since the row was written:** E-336 (`unified` 53ec4356bf) stores such an edge as `(CallSigBackedge(sig), mi)` with the call's own signature (`Compiler/src/typeinfer.jl:917–937`, `stmtinfo.jl:184–190`). The backedge already invalidates by the call's signature. Only the G2 check still reads the instance's: `Compiler/src/facts.jl:221–222`:

```julia
(invokesig === nothing || invokesig isa CallSigBackedge) || continue
is_fact_sig(item.specTypes) || return false
```

**The fix:** for a `CallSigBackedge`, G2 asks `is_fact_sig(invokesig.sig)`, the call's own signature; an ordinary edge keeps `item.specTypes`. One line.

**Why sound:** G2 says the code is invalidated only by a stakeholder's change ([facts §2.2](../reference/facts.md#22-g2-stable-caches)). After E-336 a method defined later invalidates the caller only where it replaces the matched method over the intersection with the call's signature (`src/gf.c`, the call-signature backedge). So the stakeholders of the caller's fact are those of the call's signature, not of the set.

**Gates:**
- `n21_callsig_backedge`: add that the caller's CodeInstance has its G2 bit set (`flags & 0x10`) where the call's signature is a fact signature (a concrete member). Today it is clear.
- `f4_g2_bit` unchanged.
- The image keep counts (`JULIA_DEBUG_EXTERNAL_CIS=1`) for TraitWorld and the forks before and after: recorded, not gated.

**Record:** C-57 retired; compiler §6.3's status names the commit.

## 2. C-81: a closed type's candidates kept by its image

**The rule** ([compiler §7.2](../reference/compiler.md#72-the-split); [traits §3.4](../reference/traits.md#34-open-and-closed)): a closed abstract type's contract names its operations and its candidates, which its declaring module registers.

**The deviation** (C-81): the candidates live in the runtime's global table `jl_set_candidates` (`src/datatype.c:206`), which only the system image serializes (`src/staticdata.c:141`, `INSERT_TAG`). A package that declares a contract on its own closed type loses its candidates when its image is loaded, unless it registers them again in `__init__`. The operations survive: they are on the `TypeName`'s contract slot.

**The fix: the candidates are part of the contract, on the `TypeName`.**
- `jl_declare_contract(T, ops, cands)`: writes `svec(ops, cands)` once on the contract slot (`cands` an `svec` of concrete subtypes of `T`, in order). The image keeps it with the `TypeName`, as it keeps the operations today.
- `jl_contract_operations(T)` returns the first element; `jl_candidates_of(T)` for a closed type returns the second, as a fresh `Vector{Any}`. For a set it reads `jl_set_candidates` as now.
- `jl_register_candidate` at a closed type is refused: the declaring module names its candidates with the contract. Sets keep registering at a pattern member's first use (§10.4).
- `base/iotrait.jl`: one call with the four candidates, `IOBuffer, IOStream, TTY, PipeEndpoint`.
- TraitWorld reads the contract slot only when it holds its own `Contract` object (`c isa Contract ? c : nothing`). An `svec` of two `svec`s is still not one.

**Alternatives:** serializing `jl_set_candidates` per package (the entries whose key is the package's `TypeName`): a second place for what belongs to the type, and merging tables at load. Rejected.

**Gates:**
- `n19_io_trait` (0): the candidates are still `[IOBuffer, IOStream, TTY, PipeEndpoint]`; `jl_register_candidate(IO, T)` raises.
- A new case in `n19` or `n22`: a package in a fresh depot declares a contract on its own closed abstract type with two candidates. In a new session after its image is loaded, `jl_candidates_of` gives both and a call at a value typed by the type splits over them. The precompile harness of `n18_closed_after_load` is the model.

**Record:** C-81 retired; compiler §7.1 (`jl_declare_contract`'s signature), §7.2, §7.5; traits §3.4 unchanged.

## 3. Build

Both go into the build that carries C-82 and open issue 171 ([their plans](2026-11-09-c82-unmet-match-lookup.md), [171](2026-11-09-171-declared-results-without-conversion.md)), one commit each, then the battery once.

## 4. After the review

[The review](../reviews/2026-11-09-plan-review-c57-c81.md): build both, with changes. What was done:
- **C-57, 2:** the backedge also carries the callee's own invalidation (a member's method that changes the instance's result invalidates the caller); stated in compiler §3.2's status with the commit.
- **C-57, 3:** E-340 registered before the build, with the image keep counts and the goal's imports measured.
- **C-57, 4:** `n21` asserts G2 for a caller at a member with the callee not inlined, inlined, and a facts caller, and not for a caller at the set or at `Any`.
- **C-81, 6:** `jl_declare_contract` refuses a type that another image holds (Base's build excepted for Core's `IO`): a contract declared in the image that defines the type, mine, in compiler §7.1 and traits §3.4.
- **C-81, 7:** the candidates are fixed with the contract: no module adds one later (REPL's `LimitIO` can never be `IO`'s candidate; noted in open issue 170).
- **C-81, 8, 9:** gate `n23` (the refusals in a session; a package image keeps its candidates; the split names them after load; a later registration refused); candidates checked concrete, subtypes, named once; the list rooted.
- **10–12:** the stale copies fixed with the references; the commits ordered 171, C-57, C-81.
