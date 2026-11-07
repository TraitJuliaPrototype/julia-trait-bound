# Review: the BaseTraits choices of W-114 (2026-11-07)

**Reviewer:** a `fable-critic` agent, at the main session's request. Read only: no build, no Julia run, the machine shared. Each finding says whether it is **verified** (read in the source named) or **reasoned** (my reading of rules and code, not run).

**What was reviewed.**
- The reference: [traits §10](../reference/traits.md#10-collections) (§10.1–§10.3), with §3, §4.1–§4.2, §5.8–§5.9, §7.3, §7.9, §9, §12, §13; [lowering §2, §3, §10](../reference/lowering.md); [compiler §5.2–§5.3, §7.1](../reference/compiler.md).
- The code: `TraitWorld-unified/src/BaseTraits.jl`, `test/basetraits.jl`; `src/trait.jl` (`_trait_method`), `src/implement.jl` (`_implement_one!`, `_define_block!`, `_check_pattern_member`), `src/check.jl` (`_params_at`), `src/classify.jl` (`_in_contract`); the earlier library's `TraitWorld/src/BaseTraits.jl` for comparison.
- Julia: `julia-1.13/base/show.jl:1327` (`print` of an `Unsigned`), `base/abstractarray.jl:243` (`eltype(::Type) = Any`), `stdlib/LinearAlgebra-*/src/factorization.jl:40, 156–157`; `julia-unified/src/subtype.c:6187, 6251–6320` (`sub_msp`, `tuple_morespecific`).
- The record: the research note of 2026-11-07, open issues 109, 110, closed items 21–24, decisions §3 (2026-10-20, 2026-10-28), PE-21, PE-22, E-280.

**In one paragraph.** The collection choices (1, 2, 5, 6) are sound and match the prior art. Two choices are wrong as built: `BoundedText` (8) drops the per-type constants the user adopted on 2026-10-28 and that open issue 109 measured, and `Solvable` (5) takes a name, `solve!`, that the SciML demonstrator and CommonSolve already export, where LinearAlgebra's own `ldiv!` is the principled operation. The test file aborts at its matrix-free member (`eltype` undefined). The implementation puts twelve methods at open sets on ten of Base's hottest functions and makes every array, dict, number, string and char a member: PE-21's own trigger has fired, and nothing is measured. None of the eight choices is in the decision log or open issues §1, and none of choice 7's deferrals is an open issue.

---

## Findings, by severity

### H1. `BoundedText` as built undoes the adopted design and the measured case (choice 8) — verified

- **The rule in force:** decisions §3 (2026-10-28, mine, confirmed with the references): "`BoundedText` is a constant per type for fixed-width types and a value's own bound otherwise." Open issue 109 measured why: with a constant per type "the loop folds to a constant and costs nothing"; per value, `Symbol` cost 31 µs against 2.5 µs per 10⁴ cells, `BigInt` 1.9 ms against 19 µs.
- **The code** (`BaseTraits.jl:150–157`): every bound is per value. `Integer` is `ndigits(x) + (x < 0)`, exact and O(digits); `Number`, `Dates.TimeType` and `Symbol` *print* (`string(x)`, `String(x)`), one allocation per value. The earlier library (`TraitWorld/src/BaseTraits.jl:429–488`) had `_intwidth(sizeof(x))`, `24`, `16`, `sizeof(x)` for `Symbol`, `24`/`32`/`18` for Dates, and cheap formulas for `Rational` and `Complex`. All of that is gone.
- **A bound that is not a bound:** `textbound(x::AbstractString) = ncodeunits(x)` with `AbstractString` as the member. A non-UTF-8 `AbstractString` (LegacyStrings' UTF-16 types) prints transcoded UTF-8: one code unit can become three bytes. The earlier library had `4 * length(x)` for strings other than `String` and `SubString{String}`. The contract ("an upper bound") is violated by a member Base's abstract type admits.
- **Dropped members:** `Dates.Period`, `Dates.CompoundPeriod` (the earlier library had both; the table says "Dates' types").
- **Verified in passing:** `print(io, n::Unsigned)` prints decimal (`show.jl:1327`), so `ndigits` is right for unsigned integers.
- **Recommendation:**
  - constants per type where the width is fixed: `BitInteger` by `sizeof`, `Bool` 5, the three floats, `AbstractChar` 4, `Date`, `DateTime`, `Time`; `sizeof(x)` for `Symbol`; a formula for `Rational` and `Complex`; printing only for `BigFloat`, `Irrational`, package numbers;
  - `AbstractString` members: `String` and `SubString{String}` by `ncodeunits`, every other `AbstractString` by `4 * length(x)`;
  - take up open issue 109's proposal now: `textbound(::Type{T})` returning an `Int` or `nothing`, so a writer sizes a column without visiting cells. It is the one BaseTraits feature a port already measured and asked for.

### H2. `solve!` collides with the SciML demonstrator's own export; `ldiv!` is the principled operation (choices 5, 6, 7) — verified

- `TraitDifferentialEquations/src/*.jl:26` exports `solve!` (the integrator's `solve!(integ)`), as CommonSolve and every SciML package do. `using TraitWorld` exports BaseTraits' `solve!` (closed item 22). A user module with `using TraitWorld, TraitDifferentialEquations` gets Julia's "both export `solve!`" warning, and `solve!(integ)` is an `UndefVarError`. The reference accepts name clashes in general (§10.1, last bullet); this one is with the port the trait is for.
- LinearAlgebra already has the operation with the right shape and name: `ldiv!(Y::AbstractVector, A::Factorization, B::AbstractVector)` (`factorization.jl:156`). The research note (§3.4, §4.2) names `ldiv!` as what preconditioners implement; Krylov.jl's and LinearSolve.jl's preconditioners define exactly `ldiv!(y, P, x)`.
- With `ldiv!` as the operation, `Factorization{T}` joins with no block, and the types open issue 109 names (`Diagonal`, the triangular types, `Bidiagonal`, which `factorize` returns and which have `ldiv!`) join by one line each. `LinearOperator` already takes Base's `mul!` for the same reason.
- **The family `Factorization{T}` over-promises:** `Eigen`, `Schur`, `GeneralizedSVD`, `GeneralizedEigen` are `Factorization`s with no `ldiv!`. The block's `solve!` infers `Union{} <: Nothing` for them (the inner `ldiv!` has no method), so the check passes and the solve throws a `MethodError` from inside the trait's own method (reasoned). The contract "`x` solves `F x = b`" is declared for members that cannot.
- **Recommendation:** the operation `LinearAlgebra.ldiv!(x::AbstractVector{T}, F::Solvable, b::AbstractVector{T})::AbstractVector{T}`; no `solve!` and no new exported name. Members: the solving factorizations as families (`LU{T}`, `Cholesky{T}`, `CholeskyPivoted{T}`, `QR*{T}`, `LQ{T}`, `BunchKaufman{T}`, `LDLt{T}`, `SVD{T}`, `Hessenberg{T}`) or the abstract family with the over-promise recorded; plus `Diagonal{T}`, `UpperTriangular{T}`, `LowerTriangular{T}`, `Bidiagonal{T}`.

### H3. The test file aborts at its matrix-free member: `eltype(Diag2)` is `Any` (choice 6) — verified

- `test/basetraits.jl:22–27` defines `Diag2` with `size` and `mul!` and declares `@implement LinearOperator{Float64} Diag2`. It defines no `eltype`.
- `check.jl:112–124`: the stated `T = Float64` is compared with the equation `eltype(Self)` at `Diag2`; `Base.eltype(::Type) = Any` (`abstractarray.jl:243`); they differ, so the declaration raises `ImplementError` ("the parameter T is Float64 (stated) but its equation T = eltype(Self) gives Any"). A top-level error ends the file: no testset runs.
- The library's own tests know this: `test/core.jl:11` defines `Base.eltype(::Type{Ramp}) = Float64` before `@implement KVec Ramp`.
- **Recommendation:** `Base.eltype(::Type{Diag2}) = Float64` in the test; one sentence in §10.1: a matrix-free member defines `eltype`. SciML's operators do.

### H4. BaseTraits puts methods at open sets on Base's hottest functions and makes every array a member; PE-21's trigger has fired — verified (the mechanism), reasoned (the cost)

- `_trait_method` (`trait.jl:255`) defines, per operation, a method at the set on the operation's function (lowering §2). BaseTraits therefore adds twelve set methods to ten functions: `length`, `iterate` (two arities), `getindex` (two sets: `Indexable`, `Keyed`), `firstindex`, `setindex!`, `resize!`, `haskey`, `get`, `size`, `mul!`.
- Its memberships (`BaseTraits.jl:137–162`) put `AbstractArray`, `AbstractDict`, `AbstractMatrix`, `Number`, `AbstractString`, `AbstractChar`, `Symbol` and `Dates.TimeType` in sets. After it loads, no concrete array, dict, number, string or char is "obviously disjoint" from a set (compiler §4.7), so every inference query at those functions visits the set methods (compiler §5.3, PE-21: `length` with one set method and a member, +18 % per query; PE-22: +5–8 % at `getindex` with no set method). The record's `jl_declare_membership` walk also runs over those functions' tables at TraitWorld's load.
- PE-21's own "what would make it worth pursuing": "BaseTraits (W-114) puts methods at sets on many of Base's hot functions." That is now the case. E-268 is withdrawn, so no experiment measures it.
- This is not a wrong choice: the user chose that Base's containers conform through Base's methods (closed item 23, decisions §3 2026-10-20). It is an unmeasured cost on every session that loads TraitWorld, plain code included.
- **Recommendation:** before BaseTraits is included in `TraitWorld.jl`, one quick measurement (a few minutes, per the rule): the library's test suite's compile time and the quick BaseBenchmarks subset, with and without BaseTraits loaded; and the load-time cost of the memberships' walk. If the tax is above the noise, PE-21 moves to the queue. A registry row first.

### M1. The eight choices are in the reference only; nothing is in the decision log or open issues §1, and choice 7's deferrals are not open issues — verified

- `git diff` of `record/decisions.md` and `open-issues.md` adds rows for fully typed mode, errors, compiling ahead and hints, none for BaseTraits. `grep` for "adjoint", "mixed precision", "SubString", "several right-hand", "IterableOnce", "growing by a value" in `open-issues.md`, `decisions.md`, `traits.md`, `alternatives.md`: nothing.
- `HasProperty{N, R}` is in the table (§10.1) and lowering §10, and not in `BaseTraits.jl` (no `HasProperty` anywhere in `src/`); compiler C-32 blocks it (a second value of an input is refused). No deviation row says so. §10.1's status still reads "Planned (W-114)" beside code that exists.
- By CLAUDE.md: a choice made while building goes to the reference, the decision log marked "mine", and open issues §1; a deferred question is an open issue; where the code falls short of the reference, a T- row.
- **Recommendation:** one decision-log row per choice (1–8), each listed in open issues §1; open issues for: the adjoint and transposed solves, mixed precision (one element type per operand, as Mojo's kernels), several right-hand sides, growing by a value, defaults defined in terms of each other (a minimal complete definition), keys of another type (`Borrow<Q>`), `IterableOnce` as a supertrait, `HasProperty` (with C-32); a T- row for `HasProperty`.

### M2. `get(d, k, default::V)` makes `get(d, k, nothing)` an error and invites sentinels (choice 4) — reasoned from the classifier

- The idiom Base's `get` exists for is `get(d, k, nothing)::Union{Nothing, V}`. Under the contract, `default` must be a `V`: the test's own `lookup` returns `-1` for a missing key (`test/basetraits.jl:20`), the sentinel that Rust's `Option`, Swift's optional subscript and Mojo's `get(key) -> Optional` were designed to remove.
- What happens to `get(d, k, nothing)` in trait code: `_in_contract` (`classify.jl:66`) asks `declared_operation_result`, which finds no set method at `(Keyed{String,Int}, String, Nothing)` (the set method keeps `default::V`, `trait.jl:265–270`); then `_methods_by_ftype` finds Base's `get(::Dict{K,V}, key, default)` whose parameter is no trait, so the use is open. In a `bounded` trait module the method is refused (`TraitUseError`); through a `Dynamic{Keyed{String, Int}}` it is a `MethodError`.
- **Alternative:** `get(d::Keyed, k::K, default::D)::Union{V, D} where {D}`. `_trait_method` keeps an argument typed by an operation's `where` variable; whether the check (§4.1 "fixed by its arguments and checked at each membership") handles a variable the trait's parameters do not fix is to verify, else a T- row. Mojo offers both forms; Base's `get` has this shape already.
- **Recommendation:** the `where {D}` form if the check supports it; otherwise keep `V` and say in §10.1 that `get` takes a default of the value type, with the `haskey`-then-`getindex` double lookup as the alternative.

### M3. `MutableIndexable`'s Base members are `Vector` only; the ports write through views (choice 2's neighbour) — verified (the table), reasoned (the ports)

- `@implement MutableIndexable{T} Vector{T}` (`BaseTraits.jl:142`). Not members: `BitVector`, a `view` of a `Vector`, `ReshapedArray`, StaticArrays' `MVector`, RecursiveArrayTools' `ArrayPartition`, a `SubArray` column of `view(df, rows, :)`.
- SciML's integrators write into views and partitions; DataFrames' row views are `SubArray` columns; Makie writes into buffers. Each is an `AbstractVector` with `setindex!`, excluded by the table.
- Writability is not a property of `AbstractArray` in Julia. The research note's answer (§4.1, "Conditional membership"; Swift's `Array: Equatable where Element: Equatable`) is a family with a bound on the parent: `@implement MutableIndexable{T} SubArray{T, 1, P} where {T, P <: MutableIndexable{T}}`. `implement.jl:47–53` accepts `T <: B` for any `B`, and the member's check uses `T <: pat` with memberships, so a trait as a family bound looks supported; no test shows it.
- **Recommendation:** add `BitVector`, and the `SubArray`/`ReshapedArray` families conditioned on the parent; a test for a trait as a family variable's bound.

### M4. `IndexableVector` propagates `@inbounds` into the member, against §10.1's own rule — verified

- `BaseTraits.jl:176`: `Base.@propagate_inbounds Base.getindex(v::IndexableVector, i::Int) = v.c[firstindex(v.c) + i - 1]`. A plain caller's `@inbounds` (Statistics' kernels, the stated consumer) is propagated into `c[…]`: the member's own bounds check is skipped too. The only thing bounding `i` is then `length(c)`, the value §10.1 says the check cannot verify and trait code must not index on alone. For a `Vector` member with a wrong `length`, that is an out-of-bounds read; Rust's `ExactSizeIterator` is the lesson the research note quotes.
- Also dropped from the earlier library: `Base.IndexStyle(::Type{<:IndexableVector}) = IndexLinear()`. Without it iteration goes through `CartesianIndex` per step.
- **Recommendation:** no `@propagate_inbounds` (the member always checks); `IndexLinear`; `k = keep(x)` once in `asvector` (`:183` calls `keep` twice).

### M5. `Solvable`'s contract claims what LinearAlgebra's member does not deliver (choice 5) — verified

- §10.1: "`Solvable`'s vectors are any `AbstractVector` of the element type, views and arrays on other devices included." `ldiv!(Y::AbstractVector, A::Factorization, B::AbstractVector)` calls `require_one_based_indexing(Y, B)` (`factorization.jl:157`): an `OffsetVector` throws. For a BLAS `LU` a GPU vector takes the generic scalar path or fails. Views are fine (the test's case).
- Choice 5 itself (`AbstractVector{T}` over `Vector{T}`) is right: every solver trait found takes views of any storage (research §3.4).
- **Recommendation:** the contract says what the check cannot verify as the member's promise: "for the vectors the member accepts; LinearAlgebra's factorizations accept one-based vectors in host memory."

### M6. `Resizable` promises less than its name and less than Base's method does silently (choice 3) — verified

- The contract is shrinking only (`n ≤ length(c)`); the operation is `resize!`, whose `Vector` method grows with undefined items and raises nothing for `n > length(c)`. A call outside the contract is silent, not an error. The prior art names shrinking `truncate` (Rust) and has no growth without a value (Rust, Mojo) or no resize at all (Swift).
- `retain!` needs only shrinking, so the contract is enough for it. What the ports need first is growth by a value: `push!` is in every port (building a result vector, `push!(sol.u, copy(u))`). Choice 7 defers "growing by a value" without an issue.
- **Recommendation:** either rename to what it promises (`Truncatable`, still served by `resize!`), or keep the name and add `push!(c, x::T)::Any` as the growing operation of a second trait after Rust's `Extend<A>` (`Appendable{T}`, `Vector{T}` by Base's method), which is the one a port will ask for first.

### M7. The table's members leave out Base's other repeatable iterables (choice 1) — verified (the table), reasoned (the ports)

- Choice 1 is right: all three languages distinguish one pass from repeatable (research §1.1), and Swift's designers named the confusion the protocol's main hazard. Base's listed members satisfy it.
- Not members: `Tuple`, `NamedTuple`, `AbstractSet`, `AbstractString` (as `Iterable{Char}`), `Base.Generator` and the `Iterators` adapters (repeatable, and what a Rust `impl IntoIterator` or a Swift `Sequence` argument accepts). `area(s) for s in shapes` is a `MethodError` at an `Iterable` bound. A `Set` is not even `HasLength`.
- `String`'s `length` is O(n): `AbstractString` belongs in `Iterable{Char}` and not in `HasLength`, which supports "constant time" in `HasLength`'s contract.
- **Recommendation:** `AbstractSet{T}` in `HasLength` and `Iterable{T}`; `AbstractString` in `Iterable{Char}`; `NTuple{N, T}` in `Iterable{T}` and `Indexable{T}` (`firstindex` is 1); `IterableOnce` as a supertrait (so that `Iterable <: IterableOnce`) as the open issue for generators.

### M8. Choice 2 is right and should close open issue 110; one test is missing — reasoned

- `firstindex` in the contract follows Swift's `ArraySlice` lesson and SE-0191's `Int`; `asvector` maps `1:length` onto `firstindex(c):…` correctly, and `retain!` loops from `firstindex`.
- Open issue 110 ("two traits for reading items by position: `Column` and `Indexable`") is now answerable without a design change: `@implement Indexable{T} Column{T} where {T} begin getindex(c, i) = cell(c, i); firstindex(c) = 1 end` under §5.9 (a trait as a member, with a block). The DataFrames port owns `Column`, so §12.1's rule for block methods on `Base.getindex` allows it. `CellVector` becomes `asvector`.
- No test declares a trait as a member of a parametric trait with a `where` variable. `_pattern_instance` and `_check_pattern_member` look able to; it should be shown.
- **Recommendation:** close 110 by this route when the port is rebuilt; add the test.

### L1. `Iterable`'s state is `Any`: a loop over a value known only by its trait boxes the state per step — reasoned

- Through a `Dynamic{Iterable{Float64}}`, `iterate` returns the declared `Union{Nothing, Tuple{Float64, Any}}` (§7.9), so an `Int` state is boxed each step. The research note asked for this to be measured before a state type is considered. Per-type code is unaffected.
- **Recommendation:** an E- row: items per second over a `Dynamic{Iterable{Float64}}` against a `Vector{Float64}`, before a port's hot loop runs on a `Dynamic` iterable.

### L2. `mul!` declared `::Any` loses the idiom the test itself uses (choice 6) — verified

- `test/basetraits.jl:28`: `apply(A::LinearOperator{Float64}, x) = mul!(similar(x), A, x)` returns the declared result, `Any`, through the trait. Under fully typed mode that is a reported site. LinearAlgebra's `mul!` returns its first argument, so `::AbstractVector{T}` infers for every Base member.
- **Recommendation:** `::AbstractVector{T}` (and for `ldiv!` under H2).

### L3. Names that collide with the ecosystem the traits are for — verified (the names)

- `LinearOperator` is the type of LinearOperators.jl, the matrix-free type Krylov.jl and LinearSolve.jl accept. `using TraitWorld` beside it needs a qualification in exactly the port that would use the trait. `solve!`: H2.
- `HasLength` is also `Base.HasLength`, `Base.IteratorSize`'s value. Base does not export it, so no clash at `using`; but `IteratorSize(x) isa HasLength` in a trait module silently tests TraitWorld's trait. The research note asked for a sentence telling them apart.
- **Recommendation:** a sentence on `Base.HasLength` in §10.1; consider another name than `LinearOperator` before the SciML port fixes it (`LinearMap` is LinearMaps.jl's; `MatrixFree` or `LinearOp` are free).

### L4. Specificity of the set methods against Base's at mixed positions — reasoned from `subtype.c`, to be confirmed by the tests

- The set methods `get(::Keyed{K,V}, ::K, ::V)`, `getindex(::Keyed{K,V}, ::K)`, `haskey(::Keyed{K,V}, ::K)`, `setindex!(::MutableIndexable{T}, ::T, i)` and `mul!(::AbstractVector{T}, ::LinearOperator{T}, ::AbstractVector{T})` are more specific than Base's at a further argument (`K`, `V`, `T` against `Any` or `AbstractVector`) and less specific at the receiver (a set against a closed type, compiler §5.2). Were this an ambiguity, `d["a"]`, `get(d, k, v)` and `A * x` would fail in every session with BaseTraits loaded.
- `tuple_morespecific` (`subtype.c:6251–6320`) refuses only where the other method is strictly more specific at an element; a typevar bounded by `Any` is not more specific than `Any` (`type_morespecific_`: "`b == Any && !is_typevar(a)`"), and `sub_msp(Any, K)` wraps `K` as `K where K`, which is `Any`. So Base's closed methods win, as compiler §5.2 intends. The tests exercise the cases (`lookup`, `A * [1.0, 1.0]`, `retain!`); they decide.

### L5. `retain!`'s classification at an intersection is untested — reasoned

- `retain!` reaches `firstindex` and `length` (operations of supertraits) through the component `MutableIndexable{T}` of `All{MutableIndexable{T}, Resizable}`. `_trait_of` accepts an intersection (`classify.jl:61`); `declared_operation_result` walks a set's supertraits for fields and asks `atype <: m.sig` for operations, which holds through the supertrait memberships. If either step misses, BaseTraits refuses `retain!` at its definition under `bounded`, and the module does not load.

### L6. Smaller defects and overclaims — verified

- §10.3: "`retain!` is compiled once per item type, not per function." A function Julia defines is `Compiled` (§9), so `retain!(iseven, v)` is compiled per function. Say "per closure".
- The table gives `resize!` and `setindex!` no result type; §4.1 requires one of every operation. The code declares `::Any`.
- `HasLength`'s "in constant time": `Base.ImmutableDict` and `Base.EnvDict` are `AbstractDict` members with O(n) `length`. "Expected in constant time", as the docstring already says.
- The `Factorization` family's block defines `solve!(::Factorization, ::Any, ::Any)` (`_define_block!` cannot bind the family's `T` in the declared argument types, so the further arguments are untyped): wider than the operation, harmless.
- Mixed precision: `T = eltype(Self)` on the vectors refuses `ldiv!`-able combinations LinearAlgebra accepts (an `LU{Float32}` with `Float64` vectors). Deferred by choice 7; it needs its issue (M1).

---

## The choices, each in one line

| Choice | Verdict | Where |
|---|---|---|
| 1. `Iterable{T}` repeatable, nondestructive | Right (Swift `Collection`, Rust `IntoIterator for &C`, Mojo `Iterable`). Members missing: sets, strings, tuples; `IterableOnce` as a supertrait, an issue. | M7, L1 |
| 2. `Indexable{T}` with `firstindex`, offset vectors members | Right (Swift's `ArraySlice`, SE-0191's `Int`). Closes open issue 110's case under §5.9. | M8, M4 |
| 3. `Resizable` shrinking only | Half right: enough for `retain!`, wrong name, silent outside the contract; `push!` is what the ports need first. | M6 |
| 4. `Keyed` adds `get(d, k, default::V)` | Defensible, but a sentinel trap; `default::D where {D}` with `Union{V, D}` is the principled form. | M2 |
| 5. `Solvable` over `AbstractVector{T}` | Right; the contract overclaims offset and device vectors for LinearAlgebra's member. | M5 |
| 6. `LinearOperator{T}` with `size` and `mul!` | Right in shape; members must define `eltype` (the test does not); `::Any` loses the result; the name is LinearOperators.jl's. | H3, L2, L3 |
| 7. The deferrals | Right to defer; not recorded anywhere. | M1 |
| 8. `BoundedText` by abstract types, bounds per value | Wrong as built: regresses the adopted per-type constants and open issue 109's measured case; an unsound bound for non-UTF-8 strings. Membership by abstract types is fine. | H1 |

And, not a choice of the list: `solve!` as a new exported name where `ldiv!` exists is the one I would change first, because it breaks the SciML demonstrator's namespace (H2); the set methods on Base's hot functions need their quick measurement before the library loads BaseTraits (H4).

## What the ports will need first and the table lacks

- `push!` (growing by a value): every port (M6).
- `MutableIndexable` for views, `BitVector`, `MVector`, `ArrayPartition`: SciML, DataFrames (M3).
- `AbstractSet`, `Tuple`, `AbstractString` as iterables: DataFrames, Makie (M7).
- `ldiv!` for preconditioners and the matrix types `factorize` returns: SciML (H2).
- The five-argument `mul!(y, A, x, α, β)` and `*` as a default: SciML's Krylov paths (deferred; an issue, M1).
- `HasProperty{N, R}`: the DataFrames port's `df.col` and NetworkDynamics' records (M1; blocked by C-32).
- `textbound(::Type{T})`: CSV's writer (H1; open issue 109).
- `Column{T} <: Indexable{T}`: DataFrames (M8; open issue 110).

## What should happen with each finding

Per CLAUDE.md, where each is taken up is recorded there, not here: H1–H3, M4, L2 in `BaseTraits.jl` and `test/basetraits.jl`; H4 as an E- row and PE-21's status; M1 as decision-log rows, open issues and a T- row; M2, M3, M5–M8, L3 in §10.1 and the code; L4, L5 by running the tests.
