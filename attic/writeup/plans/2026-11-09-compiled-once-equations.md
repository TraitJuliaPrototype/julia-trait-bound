**Status:** proposal (2026-11-09; written by a Fable agent at the user's request).

# Code compiled once at a trait: equations for the result, and a firewall for the edges

The user (2026-11-09): "Send out a Fable agent to think about a principled fix to this. Maybe an equation for the output type?"

This plan evaluates the equation idea on its merits, names the rules that produce each part of the regression, and proposes the rule changes. It is not normative. Where it says *verified*, the claim was checked against the code, the logs or the references named; where it says *inferred*, it is reasoning that the experiment at the end tests.

## Summary

- **The regression has two independent causes, and an equation addresses only one of them.**
  - *Type loss:* in an instance compiled once at `IO`, a call on the stream that is not an operation infers `Any`, and a wrapper built from the stream (`IOContext{typeof(io)}`) is abstract. An equation for the result, in the first-order form the design already has (`where` variables, [traits §4.1](../reference/traits.md#41-operations)), fixes the first; a rule that a wrapper built in code compiled once holds the stream as `IO` fixes the second.
  - *Fan-in:* the shared instance depends on each candidate's implementation wherever a branch is inlined or called directly. No equation changes that: inference already uses only the contract (verified below). The fix is a rule about edges, the **contract firewall**: code compiled once at a trait depends on a member only through dispatch at the branch's signature, the declared result, and, for a leaf, the member's own method.
- **Recommendation:** adopt the firewall as a rule of [compiler §7.2](../reference/compiler.md#72-the-split) (proposal 1), with the code slot as its mechanism where the `:caller_world` pointer costs too much per call; declare `IO`'s remaining stream-decided calls as operations with `where` results (proposal 2); let Base's wrappers hold the stream as `IO` (proposal 3); fold an unmet intersection behind a guard (proposal 4). One experiment decides what the firewall costs per call and whether anything of the load remains.

## 1. The case

Build `unified` 0c836f3ef6 (E-331, E-332 and E-333 in), against vanilla v1.13.2, load 9–12 of 128.

**Per call** (`experiments/unification/e328/logs/e328-unified-w332.log` and `e328-vanilla-w332.log`, column `raw`: plain code writing straight to an `IOBuffer`, minimum of 7 runs): `print` of `Int`s 1.2×, of `Float64`s 1.5×, of `"ab"` 2.2×, `write` of `Char`s 4.4×, of bytes 1.0×, `join` 2.6×, `@printf` 1.0×, `show` of a `Vector{Float64}` 3.4×, `string(…)` 1.1×. The proxy predicted 0.85–1.19× on formatted output and 1.6–2.2× on a byte or a short string per call (E-328).

**The sessions** (`experiments/unification/e289/logs/f-unified-w332.log`): the goal's task 12.2–13.9 s, imports 8.8–10.3 s; on E-329 (before `IO` was a set) 3.2–4.6 s with imports about 3 s ([experiments](../record/experiments.md), E-330's row).

**What the reports count** (`experiments/unification/audit/logs/*-0c836f3ef6.log`):
- The erasure report: Base's 931 methods typed `IO` hold 155 split fallbacks, 983 calls through `Core.attributed_call`, and 1,093 other dynamic sites on a value of `IO`. Tested with an `IOBuffer` in place of the stream, 128 are dynamic because of the stream (`read` 41, keyword calls 13, `displaysize` 11, `position` 11, `_copyline` 5, `seek` 4, `write` 3), 953 because of another argument. Receivers: `IO` 1,009, `IOContext` 69.
- The load report: 17,035 instances invalidated at the goal's load; TraitWorld's `length(::HasLength)` 7,422 of them under one pruned arm, `length(::LinearAlgebra.Factorization)`; "through a split's branch": `get` at `TTY` 11,108 instances under 374 edges, `eof` at `PipeEndpoint` 4,828 under 39, `read` at `IO` 4,706 under 3, `write` at `All{AbstractString, IO}` 1,873 under 20. The four rows sum to 22,791, more than the 17,035 invalidated: an instance is counted under every matching edge above it, so the rows overlap.
- The declared-result report: no serving method of `IO`'s operations infers outside its declaration, in Base, the standard libraries or the goal's packages.

## 2. The rules that produce each part

### 2.1 Per call

1. **Only an operation splits** ([compiler §7.1](../reference/compiler.md#71-the-rule)). *Verified:* `declared_operation_result` (`julia-unified/Compiler/src/abstractinterpretation.jl:168-202`) returns a result only where a method with the covering flag applies (`atype <: m.sig`, line 197); every other call on a value typed `IO` is inferred as Julia infers an abstract call. `read(io, Int32)` at `IO` has several matching methods at subtypes of `IO`, so it is a dynamic call with the result `Any` (the 41 `read` sites). Compiled per stream type, as vanilla does, it is one static call.
2. **A wrapper built in code compiled once is abstract.** *Verified:* `IOContext(io::IO, dict)` builds `IOContext{typeof(io)}` (`julia-unified/base/show.jl:326-328`); compiled once, `typeof(io)` is the run-time type, so the instance's result is `IOContext{<:IO}`. On such a receiver no split applies: `operation_split_type` takes a candidate only where `C <: p` (`abstractinterpretation.jl:277`), and `IOBuffer <: IOContext` is false, so each operation on an abstract `IOContext` is a dynamic call with its result asserted (`split === nothing`, line 316; `handle_declared_result!`, `ssair/inlining.jl:1990-2002`), and every other call on it infers `Any`. `show(::Vector)` wraps its stream so (`show_vector`), which is the shape of its 3.4×: *inferred* from the code, not traced.
3. **A branch not inlined is one indirect call per operation** (E-332; `split_branch_pointer`, `inlining.jl:526-540`): the `:caller_world` thunk, then the `_SplitTarget` instance (`julia-unified/base/splittarget.jl:17-23`), then the candidate's method. One short string per call pays it once per `print` (`write(::IO, ::String)` is one `unsafe_write`, `base/strings/io.jl:239-240`): about 8 ns of the 14 ns per `print` of `"ab"`. *Inferred* from the numbers; the thunk's own cost is not measured.
4. **The lookup's fault and the `Integer` result** are fixed (E-331, E-333).

### 2.2 The load

5. **An inlined branch brings its body's edges** ([compiler §7.2](../reference/compiler.md#72-the-split)). *Verified:* `split_case_edge!` (`inlining.jl:1664-1673`) records an edge for an `InliningTodo`; on 0c836f3ef6 every branch the inliner would inline is inlined. `get(::TTY, :color, false)` (`base/terminfo.jl:394`) is small and constant-propagated, so it is inlined into every instance compiled once that reads a stream's properties (`ioproperties(io::IO)`, `base/show.jl:320`), and its edge reaches `load_terminfo`, where the pruned arm sits: the 374 edges and 11,108 instances.
6. **The firewall as built has holes.** *Verified* in `handle_call!` (`inlining.jl:1595-1637`, the working tree with `split_inline_leaf`): the pointer applies only where the split has a table (`split_branch_pointer` returns `nothing` without one, line 527: a function type that is not concrete, a kind, more than six arguments); a branch without a pointer stays a direct call *with* its edge (line 1634-1635). A `ConstantCase` keeps its edge whatever its body (line 1629 tests only `InliningTodo`; line 1669-1670 records the constant's edge). A leaf is decided by the body's statements, not by its record.
7. **Instances at an unmet intersection are entry points.** `All{AbstractString, IO}` is the meet of a set and an abstract type no entry relates ([compiler §4.7](../reference/compiler.md#47-three-layers), §4.9), and a negative at an open set never folds (§4.8), so inference keeps the arm `x isa AbstractString` at a value typed `IO`, and Base's image holds instances compiled at the intersection (`escape_raw_string(IO, All{AbstractString, IO}, Char)`, `convert(Type{String}, All{AbstractString, IO})`, `iterate(All{AbstractString, IO})`: the load report's roots). They are dead until a string type joins `IO`, yet live callers at `IO` hold edges to them, and plain calls in them (`iterate`, `convert`, `IndexStyle`) are reached by late methods' pruned arms. *Verified* that the instances exist and are roots; *inferred* which sites narrow to the intersection.
8. **The report's rows "at `IO`" and "at `All{…}`" are not branches.** *Verified:* `split_edge` (`experiments/unification/audit/load_invalidations.jl:129-146`) takes any callee whose receiver is a subtype of the operation's set, `IO <: IO` included, and does not check the callee's method or arity. So `read` at `IO` (4,706) counts ordinary static calls between two instances compiled once (`read(::IO, ::Type{String})`, `read(::IO, ::Integer)`), and `write` at `All{AbstractString, IO}` counts calls into the dead instances of item 7. A branch's candidate is concrete (§7.2). The tool should test the callee's receiver against the set's candidates; it mislabels these rows.
9. **Chains between instances compiled once are not a cause.** A static call from `print(::IO, x)` to `write(::IO, ::String)` is the same edge vanilla holds between `print(::IOBuffer, x)` and `write(::IOBuffer, ::String)`. The difference is at the leaves: in vanilla, what `TTY`'s code reaches invalidates `TTY`'s instances only; here one leaf under one candidate reaches the one graph every stream's caller runs. The sharing multiplies the *union of the candidates' dependencies*, not the chains. The chains carry the invalidation only after a leaf lets it in, so the fix is at the leaves (items 5–7). With the leaves firewalled, the 4,706 under `read` at `IO` should fall with the `PipeEndpoint` subtree they overlap (`eof(::PipeEndpoint)` is inlined on 0c836f3ef6): *inferred*; the experiment's load report decides.

### 2.3 The thesis tested

"Compiled once means a shared instance, so any type information lost in it, or any edge leaking out of it, is multiplied across all callers."
- Edges: verified (item 5: 374 edges, 11,108 instances).
- Type information: refined. The loss is not multiplied across callers; it is *at the one instance dispatch selects for every caller*, so a caller that knows the stream (E-328's `raw` column, plain code writing to an `IOBuffer`) gets the erased code too. That follows from the user's decision and is paid once per call, not per caller.
- Missed: the entry points at unmet intersections (item 7) are not about sharing; they come from `All` at an open set in inference. And the firewall's holes (item 6) are mechanism, not rule.

## 3. The equation idea, evaluated

An operation's declared result as a function of the argument types, beyond the trait's own parameters: `read(io::IO, ::Type{T})::T`, `IOContext(io::IO, …)::IOContext{IO}`. Three forms, in order of power.

### 3.1 First order: a type expression over the operation's `where` variables

`read(io::IO, ::Type{T})::T where {T}`; `readbytes!(io::IO, b::AbstractVector{UInt8}, nb)::Int`; `read(io::IO, ::Type{T}, dims::NTuple{N, Int})::Array{T, N}`.

- **Already in the design and the code.** *Verified:* "`where` variables on an operation are fixed by its arguments" ([traits §4.1](../reference/traits.md#41-operations)); lowering records a result "built from … the method's static parameters" ([compiler §6.8](../reference/compiler.md#68-a-declared-result-on-method)); `declared_result_at` instantiates the result in the environment of `atype ∩ m.sig`, and rewraps it as an upper bound where a variable stays free (`abstractinterpretation.jl:289-299`); where several declared methods apply, their results are intersected (lines 194-200). Nothing new is needed in the compiler. `IO` just declares twelve operations ([traits §9b](../reference/traits.md#9b-streams-io); `base/iotrait.jl:28-44`), none with a variable.
- **Sound.** The call's code is typed by the declared result, and every path converts and asserts to it: an inlined branch whose result is not known to be in it (`inlining.jl:696-700`), a branch through a pointer and the table's fallback (`_SplitTarget`, `base/splittarget.jl:21-22`), the dynamic call (`handle_declared_result!`). A result with a free variable is an upper bound. The intersection of several upper bounds is one, since the asserted value is in each. So inference's use of the equation is sound whatever a member returns; a member outside it raises at the call where vanilla returned the odd value.
- **Who checks a member.** For a trait joined by `@implement`, [traits §5.10](../reference/traits.md#510-checks) infers each serving method at the declared signature; at a further argument declared abstract (`::Type{T}`) it does not infer, and "each call through the trait asserts it". For `IO`'s nominal members no check runs ([open issue 168](../open-issues.md#2-design)); the conversion at the call is the check, and the declared-result report finds a member outside the contract ahead of time (168 (b)). An equation changes none of this.
- **With §7.9's conversion:** `convert(T, r)` for `T` a bits type converts a count of another width silently and raises `InexactError` where it cannot; for `T` a `String`, a `Vector{UInt8}` converts. The same rule as for a return annotation.
- **With the split:** the call splits as any operation's does, over the four candidates, each branch `Compiled` for its candidate: `read(s::IO, T::Union{Type{Int16}, …})` (`base/io.jl:927-931`) at `IOBuffer` is a static call to `unsafe_read(::IOBuffer, …)`. The result is `T`, so the value after the call keeps its type where today it is `Any`.
- **With the facts mode:** a run-time site's result is `Any` "except where a declared result types it" ([compiler §1.3](../reference/compiler.md#13-run-time-sites)); a result instantiated from the call's types types it the same way.
- **What it covers:** the 128 stream-decided sites, by declaring `read(io, ::Type{T})::T`, `position(io)::Int`, `seek(io, ::Integer)::Self`, `displaysize(io)::Tuple{Int, Int}`, `readbytes!(io, b, nb)::Int`, `unsafe_read(io, p, n)::Nothing`; the keyword calls through operations with keywords ([traits §6.6](../reference/traits.md#66-keywords-defaults-varargs)) where the ports need them. Each new operation turns a dynamic call (20–80 ns, `Any`) into a split (a few ns, typed).
- **What it does not do:** remove an edge. *Verified:* the call's result is `drt` whatever the branches infer (`CallMeta(drt, Any, Effects(), SplitCallInfo(call.info, drt))`, `abstractinterpretation.jl:330`), and the split's call info adds no edges of its own (`add_edges_impl(::Vector{Any}, ::SplitCallInfo) = nothing`, `Compiler/src/stmtinfo.jl:125`). The edges of the fan-in are the inliner's (`split_case_edge!`), decided after inference. So "the caller needs no edge into any member's code" is true at inference already; the equation cannot make the inliner keep it so. That needs the firewall (§4.1).

### 3.2 Second order: a result over the instance's static types

`IOContext(io::IO, …)::IOContext{IO}`; `eachline(io::IO)::EachLine{IO}`.

- **The equation Base's code suggests, `IOContext{typeof(io)}`, is not expressible, and should not be.** [Compiler §6.8](../reference/compiler.md#68-a-declared-result-on-method) records no result "computed from the arguments (`::typeof(x)`)", rightly: in an instance compiled once, the stream's static type is `IO`, and no equation can recover the run-time type the instance erased. An equation that named it would give `IOContext{<:IO}`, abstract, and §2.1 item 2 shows what that costs.
- **The expressible equation is over the static types:** `IOContext{IO}`, a type at the definition. It holds only where Base's constructor builds that type in the method typed `io::IO` ([open issue 166](../open-issues.md#2-design) (d)). So this form is a specification the implementation must meet, not an inference shortcut. The principle: **a value built from a trait argument in code compiled once has the trait as its parameter**, as Rust's `BufWriter<Box<dyn Write>>` has. `keep` is the precedent for "the type as the instance sees it" ([compiler §6.9](../reference/compiler.md#69-casts-and-keep): resolved where the instance is compiled); `IOContext{Dynamic{IO}}` would follow from `keep(io)`, but `IOContext{IO}` is the same for `IO`, whose default is `Dynamic`, without the box.
- **The result:** `IOContext{IO}` is concrete; `show_delim_array(io::IOContext{IO}, …)` is a static call; `print(ctx, x)` dispatches to the instance compiled once at `IO`, whose operations split; `IOContext{IO}` should be among the candidates, or the table serves it. Its branch forwards to `ctx.io::IO`, a second split. Two splits per operation through a wrapper is the cost of erasure, as E-328's `known` column showed for `IOContext`'s forwarding.
- **Visible:** `typeof(IOContext(stdout))` becomes `IOContext{IO}`. A package that dispatches on `IOContext{<:IOBuffer}` sees a change. `IOContext{IOBuffer}(io, dict)` stays for code per type.

### 3.3 Third order: type functions

`T = eltype(Self)`, `promote_type(T, U)` in a result. [Traits §3.2](../reference/traits.md#32-parameters) does not offer equations between type functions, after the research's finding that symbolic reasoning about associated types is where the other languages' cost lies ([other-languages §3](../design/other-languages.md)). `IO` needs none. Not proposed.

### 3.4 Verdict

The user's direction is right: the contract, not the implementation. The design already infers by the contract; what it lacks is (a) enough of `IO`'s contract declared, in the first-order form, (b) a rule that wrappers carry the static type, and (c) a rule that the *optimizer* also depends only on the contract. (a) and (b) are equations; (c) is not, and (c) is where the load goes.

## 4. Proposals

### 4.1 Proposal 1: the contract firewall at a split

**The rule** (replaces the branch rules of [compiler §7.2](../reference/compiler.md#72-the-split), fourth and fifth bullets): in code compiled once at a set, a branch of an operation's split holds exactly these dependencies on its candidate:
- a dispatch edge at the branch's signature (a fact: the candidate is concrete);
- the declared result, converted and asserted;
- for a leaf only, a code edge to the candidate's serving method: a method is a leaf where its own record holds no code edge, no dispatch edge and no result edge to another method. Such a branch may be inlined, constant-propagated and folded. Every other branch is a **contract call**.
- Nothing else: no edge to what the candidate's method depends on, whatever the caller's policy, whether or not the split has a table, and for a constant-folded branch as for an inlined one.

This is [facts §2.2](../reference/facts.md#22-g2-stable-caches)'s G2 shape at one boundary: dispatch edges at facts, code edges only to callees whose own records are G2, result edges to nothing a third party can change. It holds for Base's plain code at `IO` because the rule is the split's, not the policy's.

**The mechanism.** Two deliver it; both exist in part.
- *The `:caller_world` pointer* (E-332, built): the branch calls the candidate's target through a thunk that dispatches in the caller's world. Correct; the thunk and the `_SplitTarget` hop cost per call (§2.1 item 3), and it needs a table (§2.2 item 6).
- *The code slot* ([compiler §3.3](../reference/compiler.md#33-the-code-slot), built for result edges): the branch is an `:invoke` whose target loads through a slot checked against the task's world; a miss finds the callee's code valid in that world with the result the caller was compiled against, else the dispatching entry. A slot call costs 0.08 ns more than a bound call (E-283). What the firewall adds is a new kind in the record, a *contract edge*: the walk that invalidates a callee through its own edges (`src/gf.c:3186-3205`, where a result-edge caller is marked and keeps its backedge) neither invalidates nor marks a caller whose edge to the callee is a contract edge; the backedge stays, so a method inserted at the signature, which reaches the caller through the callee's MethodInstance, still invalidates it. No revalidation walk: the caller used nothing of the callee's inference. The slot's miss path repairs the slot. *Inferred:* that method insertion and CI invalidation reach `gf.c:3182` by distinct paths (`replaced_ci` set only in the second); to confirm when built. A slot callee must be in its MethodInstance's cache (`Compiler/src/typeinfer.jl:166-175`), so a contract call targets the candidate's generic instance, not a constant-propagated one; a leaf keeps constant propagation.
- Recommended: state the rule now; keep the pointer where it is built; add the slot where the experiment (§5) shows the pointer's cost on short writes; close the holes (no table, `ConstantCase`) under either.

**Soundness.** A contract call runs the method dispatch selects at the branch's concrete signature, in the caller's world (the slot's or the thunk's world check), with the result converted to the declared one. A method defined later at that signature invalidates the caller through the dispatch edge: a stakeholder's change, as in Julia. The callee's code changing underneath (its own edges) changes nothing the caller relied on. A leaf's code edge is a dependence on the member's own method, which is the member's serving method, part of the membership. The calling convention of the `:invoke` is the callee CodeInstance's (`inlining.jl:688-689`): the slot's rule that the new code have the same result, else the dispatching entry, keeps it.

**Cost in speed.** The firewall forbids inlining a candidate's non-leaf body into code compiled once. For `IO`: `write(::IOBuffer, ::UInt8)` and `unsafe_write(::IOBuffer, …)` call `ensureroom` and are not leaves; `eof`, `isopen`, `get`, `haskey` and `read(::IOBuffer, UInt8)` are. So formatted output pays one contract call per `print` (bounded by E-328's `split` proxy, 0.85–1.19×, plus the slot's or the thunk's cost); one byte or one short string per call pays it per call, which [traits §9b](../reference/traits.md#9b-streams-io) already answers with `@specialize`. The number to measure is the contract call against a direct `:invoke`: the slot at 0.08 ns (E-283) against the thunk's unknown cost.

**Cost in load.** None; it removes the fan-in at every branch. What stays is a candidate's method redefined (rare) and the leaves' own records.

**What it leaves open.** An image's validation of a contract edge (accept, and let the slot resolve); the slot's miss for a callee whose result changed under a declared `Any` (the dispatching entry asserts `Any`: fine); whether a leaf's definition should also exclude a binding edge to a non-constant global (`get_have_color`'s `have_color` is read by a non-leaf, so not today's case).

### 4.2 Proposal 2: `IO`'s contract completed with first-order equations

**The rule it changes:** [traits §9b](../reference/traits.md#9b-streams-io)'s list of operations, and `base/iotrait.jl:28-44`. No change to §4.1 or compiler §6.8.

- Add `read(io, ::Type{T})::T where {T}` (Base's default `read(s::IO, T::Type)` at `base/io.jl:1205` rewritten with the variable), `read(io, ::Type{T}, dims)::Array{T, N}` if the ports need it, `position(io)::Int`, `seek(io, ::Integer)::Self`, `displaysize(io)::Tuple{Int, Int}`, `readbytes!(io, ::AbstractVector{UInt8}, ::Integer)::Int`, `unsafe_read(io, ::Ptr{UInt8}, ::UInt)::Nothing`.
- Run the declared-result report for each before declaring it; a member outside it converts at the call (168 (a)).

**Soundness:** §3.1. **Speed:** each turns a dynamic call into a split; the 128 stream-decided sites fall to the keyword calls. **Load:** none. **Open:** keyword operations ([traits §6.6](../reference/traits.md#66-keywords-defaults-varargs)) for `readline`, `readuntil`; whether `displaysize` at `TTY`, which the REPL invalidates (`base/stream.jl:563-572`), should be an operation at all.

### 4.3 Proposal 3: a wrapper built in code compiled once holds the stream as the trait

**The rule it adds** (to [traits §7.9](../reference/traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait) and [§9b](../reference/traits.md#9b-streams-io)): a value whose type takes the stream's type as a parameter, built in a method compiled once at `IO`, takes `IO` there: `IOContext(io::IO, …)::IOContext{IO}`, `eachline(io::IO)::EachLine{IO}`, `readeach(io::IO, T)::ReadEachIterator{T, IO}`. The constructor at the exact type stays for code per type. Open issue 166 (d), with its reason stated as the equation of §3.2.

**Soundness:** the constructor builds what it declares. **Speed:** `show(::Vector)` and every path through `IOContext` recover static dispatch on the wrapper; each operation through it is two splits (§3.2). `IOContext{IO}` joins the candidates (compiler §7.5), in place of `PipeEndpoint` or as a fifth. **Load:** none. **Open:** the visible type change; JuliaSyntax's `Lexer{IO_t}`, which Base's parser builds from an `IOBuffer` it knows (per type: no change needed).

### 4.4 Proposal 4: an unmet intersection folds behind a guard

**The rule it changes:** [compiler §4.7](../reference/compiler.md#47-three-layers) and §4.8. Where inference meets a value typed by a set with a closed abstract type that no entry relates (`tmeet(IO, AbstractString)`), the arm is unreachable while the intersection is unmet in the world, as E-331 made it for dispatch (§5.4), behind a cell per (abstract type's name, set) that any membership of a type under the abstract type opens. The guard reads the cell, as §5.6's guards do; no edge, so "a membership invalidates nothing" holds.

**Soundness:** the arm is unreachable in every world where the cell is closed; a membership that makes the intersection met opens the cell before any value of the new member exists (the walk at the declaration, §5.5), and the guard takes the dynamic path. It also removes C-78's staleness for inference's arms; dispatch's drop (§5.4) could read the same cell.

**Speed:** one hoisted load per such arm; no instances at `All{AbstractString, IO}` in the image, so smaller images. **Load:** removes the entry points of §2.2 item 7 (1,873 counted, overlapping). **Open:** a cell on an abstract typename is new (today's cells are per member typename or type object, §5.6); the walk at a membership must open the cells of the member's declared supertypes.

### 4.5 Alternatives judged and not recommended

- **Julia's own streams compiled per type** (the flagged item's (e)): revisits the user's decision; the REPL's stream would not be covered by an image's workload. Not principled by the user's goal.
- **Base's methods at `IO` compiled by facts:** the general form of proposal 1 (G2 for the whole method, run-time sites at every non-fact call). It needs Base's own system image by facts (PE-23) and types for inference's hot positions. Proposal 1 takes the one boundary that matters.
- **The leaf heuristic alone** (`split_inline_leaf`, the build in progress): the right mechanism without the rule; it leaves the holes of §2.2 item 6.
- **Witness tables:** rejected before ([alternatives](../design/alternatives.md), "Dynamic values"); the `:caller_world` pointer behind the split is their sound form.
- **The split seeing through one wrapper level** (candidates `IOContext{C}` for each candidate `C`): aimed at one case; proposal 3 is the rule.

## 5. The experiment that decides

To register as the next E-n before it runs; the build in progress (leaf-only inlining) is its first arm.

**Questions.**
1. *Does the firewall remove the load's fan-in?* The load report on the leaf-only build, with `split_edge` fixed to count branches only (a concrete candidate): instances under branch edges; the sessions (E-289's four, a warm-up and 3 runs, the control first).
2. *What does a contract call cost per operation?* E-328's workloads, `raw`, on three builds: direct-invoke branches with `Int` declared (0c836f3ef6 with `split_branch_pointer` returning `nothing`), the pointer (0c836f3ef6 + leaf-only), the slot (to build). `print` of `"ab"`, `join`, `print` of `Int`s carry the answer.
3. *What do the equations and the wrappers recover?* The erasure report after proposal 2 (stream-decided sites) and `show` of a vector after proposal 3.

**Results that would change the design.**
- (1) Branch edges near zero and imports back near 3 s: proposal 1 is the rule, and the pointer suffices for load. Thousands remaining under `read` at `IO` after the tool's fix, with no branch above them: a plain leaf under an instance compiled once that the firewall does not cover; the load report names it, and proposal 4 or a wider leaf rule follows.
- (2) The pointer within 20 % of the direct invoke: the slot is not worth building for `IO`. The pointer 2× or more on a short string per call, and the slot within 20 % of the direct invoke: the slot is the firewall's mechanism and compiler §3.3 gains the contract edge.
- (3) Stream-decided sites below 20 and `show` of a vector within 1.2× of vanilla: the equations' first-order form is enough, and §3.3's type functions stay out. `show` still above 2×: another loss in the wrapper's path, to find with the erasure report at `IOContext{IO}`.

## 6. What was verified, and what was not

- Verified by reading: the operation rule and the split's inference (`abstractinterpretation.jl:163-331`); the inliner's branch forms, edges, leaf test and holes (`ssair/inlining.jl:526-540, 610-720, 1595-1673, 1990-2006`); `SplitCallInfo`'s edges (`stmtinfo.jl:121-125`); the slot's mark in the walk (`src/gf.c:3112-3205`) and its callee rule (`typeinfer.jl:159-200`); Base's `IOContext`, `ioproperties`, `get(::TTY, …)`, `read` and `write` methods at the lines cited; the audit tool's `split_edge`; the four logs cited.
- Not verified (no build, no run): the pointer's cost per call; the shape of `show(::Vector)`'s 3.4×; what lies under `read` at `IO`; which sites narrow to `All{AbstractString, IO}`; that a contract edge can be kept out of both the mark and the invalidation in `gf.c` without touching the method-insertion path.
