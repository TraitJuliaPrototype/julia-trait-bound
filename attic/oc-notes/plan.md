# Traits-v2: the greenfield build — implementation plan

**Unfinished attempt, not adopted; the status line below is as written then.** (Added 2026-11-05.) A QWEN38 class model wrote this on 2026-10-30/31. It reached M2 of M0–M7; M3 stopped on a hang while building the compiler. Its code, gates and notes are unverified material to draw on. The decisions P1–P8 that its plan credits to the user are not in [the decision log](../../writeup/record/decisions.md), so they are not in force. Its Julia commits are on branch `oc-build` of the `julia` repository. Paths below refer to the folders it had then, beside this one.

Status: **in force** (the user, 2026-10-30). Written from the exploration
`writeup/explorations/unified-build-from-vanilla-julia.md` and its review
`writeup/reviews/2026-10-29-unified-build-review.md`, with the review's corrections
folded in and the user's decisions of 2026-10-30 pinned (§1). This plan lives in
`oc-notes/plan.md`. Not normative against §1; normative against nothing
else — §4 states the design this build implements, the references state the project's.

---

## 0. Mission and scope

Build, from a vanilla Julia base, the unified design: abstract types with declared
late membership are traits; a bounded method is a Julia method; per-key compilation
is specialization at a refinement type; facts is an inference policy with a
dependency record; a code slot lets callers revalidate instead of recompiling; one
language surface carries the four scope declarations. One branch, one artifact,
milestones gated by test suites — no stage gates, no upstream PR series, no registry.

**In scope (the first big build):**
- memberships in the type system (`open` sets, entry lists, the `subtype`/`isa`
  fallback, worlds, the structural negative-fold exclusion);
- one dispatch under option (e): bounded methods as methods, dispatch-cache walks,
  guards with cells, C7, the typemap consults, the ambiguity report at a membership;
- keys as `Keyed{X, R, F}`, per-key inference, the projection convention, the boxed
  adapter (variant (ii), §1), `Dynamic`/`Compiled`/`Kept` in Core;
- the facts policy per method, the dependency record, `nortsite`, the check as an
  inference mode, the declared result on `Method`;
- **the code slot and result-edge revalidation** (§1: it is built);
- the scope declarations (`facts`, `bounded`, `concrete`, `no_pirates`) and a small
  library package with `@trait`/`@implement`;
- image activation for memberships (so a precompiled package can declare memberships
  on foreign types);
- one demonstrators-shaped workload at the end (M7).

**Out of scope (deliberately):**
- the machine-code store: shards, identity serialization, relocation by identity,
  loading, relinking. The dependency record is still built (it serves G2, guards,
  revalidation, and the store later); nothing serializes it;
- upstream preparation of any kind — this is a fork; no PR series, no "upstream shape"
  argument;
- the 1.14 rebase (see §2 for the base; revisit after M4–M5 stand);
- sealed sets ([PE-19]), `--trim`/`verify_main`, `Both{X,Y}` beyond what the ports need.

## 1. Decisions pinned (user, 2026-10-30)

| # | Decision | Consequence for the build |
|---|---|---|
| P1 | **We build the code slot.** | M4 builds the per-`(MethodInstance, ABI)` slot and red-green revalidation for result edges (M7's definition: an emitted call whose result was used as a type; inlining, constant propagation and concrete evaluation stay code edges and invalidate). The `:facts` second-owner / facts-copies-of-Base design is **never built**: the policy is a method property from the start (M3). The old build's owner mechanism is background, not a template. |
| P2 | **Boxed adapter: variant (ii).** | One boxed wrapper per keyed `CodeInstance`; it reads the receiver and field offsets at run time from a **table per (member typename, set)** carried on the member's `TypeName` beside the membership list and the guard cells. Cost target and fallbacks in M5. |
| P3 | **C7 lives in `jl_type_morespecific_`** (review M2): at a position, a closed non-`Any` typename orders above an open one; set-over-set through entries. No `jl_subtype_env` out-flag, no per-match bit, no new `interferences` state. M0's experiment confirms the volume claim; if it surprises, record in `notes.md` and continue with this placement. |
| P4 | **The store stays out.** | Build the record completely (§4.4); do not serialize or relink anything. |
| P5 | **No upstream preparation.** | The fork may take liberties a PR would not (e.g., the `declared_rettype` field, `Keyed` special cases). Keep the diff reviewable for your own sake, not upstream's. |
| P6 | **M1/M2's stopgap (a):** `jl_declare_membership` runs the insertion walk for every method at the set or a superset (review H4a). It logs its invalidation volume (data for M2/M5). M5's guards replace only the code invalidation; the dispatch-cache walk stays forever. |
| P7 | **Base: v1.13.2, commit `45b6d15e34`.** | Every upstream line citation in the exploration and the review is verified at that commit. The 1.14 scan's items (lock-free inference, binding partitions) are a later rebase. |
| P8 | **Notes: `oc-notes/` only.** | Do not register E-/W- IDs; do not edit `writeup/`. The prior build's record is background (§3). |

## 2. Environment and layout

**Machine constraints (they stand):** the machine is shared. One compiled-Julia job
at a time, niced; full builds alone, under a memory guard; use the existing slot
harness `experiments/tools/jl` (it manages the depot and the exclusive slot) or
coordinate manually. Expect a full Julia build ~30–60 min; iterate with
`make -j$(nproc)` and per-file rebuilds.

**Folders (create in M0):**

| Folder | What |
|---|---|
| `julia-oc/` | the new Julia, a worktree of `julia-1.13/` at base `45b6d15e34`, branch `oc-build`: `git -C julia-1.13 worktree add -b oc-build ../julia-oc 45b6d15e34`. Built by `oc-build.sh` (created 2026-10-30: `-j4`, niced, 4 GB watchdog, log `oc-build.log`, after the old tree's `tw-build.sh`); `deps/srccache` symlinks the old tree's (the `deps/` specs are identical between the base and the old tip, so nothing new downloads). Build it once to completion before touching sources. |
| `oc-traits/` | the new library package (`Traits.jl`): the declaration macros, the contract tables, the errors, its test suite. A fresh, small package — **do not fork TraitWorld**; it is background reading for the semantics of `@implement`'s checks (traits reference §4, §9). |
| `oc-notes/` | this `plan.md`; `notes.md` (dated decision log); `deviations.md`; `numbers.md`; `README.md` (index, one line per milestone done). |

**Sessions for testing:** small scripted sessions you write in M0–M1
(`oc-traits/test/sessions/`), not the old ports. What the old ports contribute is
their *shapes* (M7), read from the record.

## 3. Sources, in reading order

1. This plan + `oc-notes/notes.md` (what later decisions changed).
2. **The review** (`2026-10-29-unified-build-review.md`) — its corrections are binding;
   where it contradicts the exploration, the review wins. Its verdicts on D1–D9 and
   findings H1–H4, M1–M11, L1–L10 are cited below by ID.
3. **The exploration** (`unified-build-from-vanilla-julia.md`) §2–§5: the mechanism
   design (entries, keys, guards, the record, the projection). Its §10 source list is
   the map of upstream; apply review L1's corrections (the insertion walk is
   `jl_method_table_activate`, `gf.c:2953`; `get_compileable_sig` is
   `Compiler/src/utilities.jl:159`; one global `jl_methcache_t`; the chain walks are
   in `obviously_disjoint` `subtype.c:562,:566`, the datatype fast path `:2096`,
   `intersect` `:3818`, `jl_type_intersection` `:4294`, `type_morespecific_` `:5484`,
   and typemap.c's four).
4. The references for the *language semantics* this build must keep: `traits.md`
   (declaration, operations, families, forwarding, §6 attributes, §7 storage, §9
   checks, §13 ahead-of-time), `facts.md` (fact signatures, run-time sites, G1/G2,
   ownership), `compiler.md` §1, §3, §4 (effects, split_call, folds). **`lowering.md`
   §17 describes the old encoding — it is what we replace; do not reproduce it.**
5. The old build as reference material only: `julia-1.13/` (65 commits on the base;
   `writeup/design/julia-changes.md` lists them), `TraitWorld/src` (the checks, the
   contract tables, the split). Read them to know a mechanism exists; implement fresh.
6. Numbers quoted below: E-164 (typed call 0.8 ns; view 17.6–18.8 ns at 64 types),
   E-256 (entry per call 80–96 ns, 80 B; 32–45 entry CodeInstances per held type),
   E-255 (negative folds 0.003–0.9 %; ~90 % Core kinds), E-259 (7 guard sites; cell
   read free, table lookup 27–28 ns), E-253 (131 bounded methods; `show` shielded
   except `Factorization` and `IO`), E-233 (1,884 instances invalidated by insertions
   in the forks' session).

## 4. The design as built (review corrections folded in)

Condensed normative statements; the exploration sections carry the derivation.

### 4.1 The type system (M1)

- A set is a `TypeName` with an `open` bit (5 unused bits, `julia.h:560`); a
  `never_member` bit marks Core's kinds (`DataType`, `UnionAll`, `Union`,
  `TypeofBottom`, `Module`, `TypeVar`, builtins, `OpaqueClosure`, the memory types);
  Base's typenames are born closed. `@trait` sets `open`; `struct S <: X` with `X`
  open adds a final membership alongside the supertype (exploration §2.1).
- Membership entries live on the **member's** `TypeName`: an immutable
  `MembershipEntry {set::TypeName, member, instance, key, min_world, declarer, by}`;
  the list is a `SimpleVector` replaced copy-on-write. `jl_declare_membership`
  (in `datatype.c`) takes the world lock, stamps `min_world`, publishes, advances
  `jl_world_counter` (D4 accepted; like `jl_method_table_insert`). Entries are never
  removed; a redeclared key replaces the entry with a new `min_world` and gives the
  old one a `max_world`, and runs an invalidation walk by key (review M6).
- `jl_subtype` consults the list when the chain reaches `Any` and the RHS's name is
  open (exploration §2.2); **the fallback lives after the chain, one flag read on the
  slow path.** Sets-in-sets by their own entries.
- **Three layers (review H2):** (i) `subtype`/`isa` above; (ii) `jl_type_intersection`,
  `jl_has_empty_intersection`, the type cache, `obviously_disjoint`, `jl_isa`'s
  type-value branch and `jl_type_intersection`'s datatype case **stay exact** — patch
  the last three only to consult `Type{S}` entries (open issue 91, review L10);
  (iii) new `jl_could_join(S, X)` (S a final non-member ⇒ false; else the entry
  question) is the *forward-looking* predicate used by the inference lattice and the
  shadow/insertion questions — never by dispatch's match construction.
- **`has_open_set(t)` (review H3):** a cached bit on the type object (like
  `has_concrete_subtype`), structural, walking parameters and unions; set when any
  parameter is a set's name or a `Keyed`/`Dynamic`/`Compiled`/`Kept` wrapper.
  `isa_tfunc`, `subtype_tfunc`, `typeassert_tfunc`, `tmeet`, `typesubtract`, the
  `hasintersect` sites and `Conditional` refinement consult `has_open_set` +
  `jl_could_join` before folding a negative. Positives fold only through entries,
  and a fold raises the consumer's `min_world` to the entry's (review M6).
- `Core.Keyed{X,R,F}` is a subtype special case like `Type{T}` (the abstract
  declaration is refused, review M3): rules in `subtype`, `intersect`,
  `type_morespecific_`, `obviously_disjoint`; it is never instantiated.
  `Core.Dynamic{X}`, `Compiled{X}`, `Kept{X}` are `struct`s holding `object::Any`
  (`Kept` a `compiled::Bool` flag), each with a runtime special case "member of `X`
  at the erased key" — not a stored entry (review M3).
- Abstract queries (review H2/L7): when `ml_matches` meets a bounded method at an
  abstract signature, the partial match carries `spec_types = X` (the erased key),
  never fully covering; inference infers the erased instance.

### 4.2 One dispatch under (e) (M2)

- A bounded method is a plain method at `Tuple{typeof(f), X, ...}`. No entries, no
  workers, no generated fallbacks, no own keyword sorter — Julia's lowering, incl.
  the `kwcall` sorter, applies (this retires old lowering L-3, L-47, L-48, L-50 and
  open issue 135).
- **Stopgap P6:** at `jl_declare_membership`, run `jl_method_table_activate`'s walk
  for every method at the set or a superset as if `Tuple{F, …, S, …}` were inserted,
  plus the permanent dispatch-cache walk (lower `max_world` of leaf/typemap entries
  whose selected method changes). Log counts; they are the measurement E-252's
  runtime analogue.
- **Typemap (review M1):** methods at open sets are inserted into `cache->linear`
  and never into `name1` (bounded methods are rare; E-253: 131 across four ports).
  Measure the lookup cost on `show`-size tables at M2's gate; the four walks
  consulting the query's membership list is the later optimization, not in this build.
  Note which intersecting methods lose `METHOD_SIG_LATEST_ONLY` (M0 counts it).
- **C7 (P3):** `type_morespecific_`'s datatype case: closed non-`Any` typename above
  open typename at a position; open-vs-open by set-in-set entries (through the
  subtype fallback), else unordered.
- **Guards (exploration §3.3, corrected by M10/M11):** inference's shadow query
  (`find_method_matches` asking `ml_matches` for methods rejected only at the
  `jl_subtype` step whose set could win) records, per shadow `(Z, i)`, a **membership
  cell** — one mutable one-field object per (member type *object* for parametric
  entries, else member typename, set), created by the compiler, hung on the member's
  `TypeName`; `min_world = typemax` until a matching entry is declared. Codegen:
  load the cell, `icmp uge` against `emit_tls_world_age_load()`, two-way branch
  shaped like `ir_inline_unionsplit!`; the slow branch is a full dispatch whose
  result type joins `m₀`'s with the bounded method's `declared_rettype` (or `Any`).
  There is **no `invokelatest` precedent** (review M11); the patched `:caller_world`
  thunk stays the model for `Callable` only.
- `Callable`: the `Dynamic` form keeps the `cfunction` thunk with the
  `:caller_world` convention (review M9; exploration D7 deferred).
- Ambiguity report at a membership (exploration §2.3, review M10): a small index
  from set typename → methods whose signatures name it (rare, so a dictionary
  suffices); at `jl_declare_membership`, cross it with the member's other sets and
  report an order-independent warning (an error under `no_pirates`).

### 4.3 Keys, attributes, the projection (M5)

- **Per-key inference via the `nospecializeinfer` path (review M4):** bounded
  methods carry bound-position bits; a `get_nospecializeinfer_sig` analogue maps a
  concrete member `S` at a bound position to `Keyed{X, R, F}` from `S`'s entry — so
  *inference* is per key, not per member. `Compiled` positions take the key;
  `Dynamic` positions widen to `X` (the erased key) as `@nospecialize` does.
- **Two compilation signatures per `(method, tt)` (review M4):** the key for static
  callers (`get_compileable_sig`, and the `jl_compilation_sig` rule for bound
  positions), the erased `X` for dynamic callers (leaf cache + `cache_method` →
  `cache_with_orig` forced for keyed instances, review M3). `jl_isa_compileable_sig`
  gains a branch keyed on the method's bound-position bits that admits `Keyed`.
  Ahead-of-time compilation at a key needs its own request form (traits §13).
- **Projection convention (static callers):** the `specsig` of a bound position is
  the key's parts — the receiver by its own convention; `@const`/immutable fields by
  value; a two-word (object, offset) reference for each writable declared field; the
  boxed object where the keep analysis (an inference escape pass marking escapes)
  says the method may keep it. A static caller at `S` emits the projection inline.
- **Boxed adapter, variant (ii) (P2):** `gen_invoke_wrapper`'s analogue for a keyed
  instance reads (receiver, fields, offsets) from the per-(typename, set) table;
  writes go through the object+offset references it assembles. Cost targets: the
  dynamic call must land under E-256's 80–96 ns entry today (goal: E-164's
  17.6–18.8 ns band for the repeated call once the table lookup is hoisted/cached
  per call site); CodeInstances per new member type must be O(keys), not O(members).
  If the numbers miss badly, the fallback is per-member wrappers — record the
  measurement in `numbers.md` before switching.
- **Attributes (exploration §3.5):** kept wrappers dispatch: `Dynamic{X}` reaches the
  erased instance directly; `Compiled{X}` dispatches on the held object's type to the
  keyed instance (one extra dispatch through the leaf cache); `Kept{X}` branches on
  its flag first. Casts are constructors. Field stores of a set's name `convert` to
  `Kept{X}` (traits §7.3, U2/E-257 keeps `Kept` as the mixed-storage form).
- **Declared result on `Method`** (`declared_rettype`, set by lowering from
  `f(...)::RT`): a bound inference may read only because the body asserts it (review
  L9); it changes `Core.Method`'s layout — adjust serialization and the `Method`
  constructors in Base, Revise-style packages are out of scope.
- **The check (`bounded_check` inference mode, exploration §3.7):** one inference at
  the erased signature; only the contract's operations resolve (to the declared
  results); any other use of the bounded argument is a run-time site, reported as
  `TraitUseError` (enforcing scopes) or classified "open" (classifying scopes); the
  classification bit lands on the method. No separate checker.

### 4.4 The facts policy and the dependency record (M3)

- The policy is per method (module/method/block from M6's `facts` declaration; the
  compiler's own code is always plain). It gates `find_method_matches` by the fact
  signature criterion (facts §3) and marks run-time sites with the `nortsite` effect
  bit; `return_type` answers at non-fact signatures stay plain. The precedent shape
  is `concrete_only` (keyed by the callee); ours is keyed by the caller's method
  (review L3 confirms the shape).
- **The record** = `CodeInstance.edges` extended with four edge kinds (exploration
  §3.8): **result edges** (emitted calls only — P1/M7: the callee CI whose
  `rettype`/`exctype`/effects/`rettype_const` the caller used as a type),
  **inlined-code identities** (method + lowered-code hash), **layout identities**,
  **membership cells + folded positives** (with the entry, for the `min_world`
  bound). Written by `compute_edges!`/`store_backedges`/the inliner; folds and
  bindings as they are.
- **G2 is a predicate on the record** (every dispatch edge at a fact signature;
  every inlined identity's own record satisfies G2; result edges may go anywhere),
  computed at `finish!`, stored as a bit. Strict mode and `concrete` enforcement
  (`NotFullyTypedError` = `nortsite` + no `concrete` opt-out) read it.
- **No second owner exists** (P1): one CI per `(MethodInstance, policy, flags)`; the
  test bed `all` is a session-wide default policy (`--project` + depot switch, or a
  `Base.Experimental` switch), not an owner token.

### 4.5 The code slot and revalidation (M4)

- One slot per `(MethodInstance, ABI)` holding the current valid specialization
  pointer (+ `min/max` world or a validity stamp); written when a CI for that MI
  compiles and cleared/rewritten when one is invalidated. Static call sites that
  hold a **result edge** to the callee load through the slot instead of binding the
  address (review H1's soundness fix); everything else binds as today.
- The revalidation walk: when a callee CI is replaced, callers holding only result
  edges to it take the `WORLD_AGE_REVALIDATION_SENTINEL` (their `max_world = 1`), and
  the *lookup path* is hooked (`jl_method_compiled_callptr`, `jl_rettype_inferred`,
  review H1): on a sentinel hit, compare the callee's current valid CI's recorded
  result against the edge; equal ⇒ `jl_promote_ci_to_current` and continue; unequal
  ⇒ re-infer. Code edges (inlining, constant-propagation, concrete evaluation,
  dispatch) invalidate transitively as upstream.
- Consequence: a caller whose only dependence is "the callee returns a Bool" survives
  the callee's recompilation, in plain and facts code — the claim D3 made, now sound
  against the machine code. Gate: synthetic and session-level cascades (§5 M4).
- The same slot is what a future store would relink by identity; do not build the
  store (P4), but keep the slot's write points in a file of their own so the store
  later adds a loader, not a new mechanism.

### 4.6 The surface (M6)

- `oc-traits/`: `@trait X ... end` (operations with result types, fields,
  associated types; sets `open`), `@implement X S by field ... end` (the contract
  checks in Julia, then `jl_declare_membership`), `Self`, bounds in `where` and on
  struct parameters — semantics as `traits.md` §§3–8. `Dynamic`/`Compiled`/`Kept`,
  `Keyed` printing (`ColTable at Vector{Vector{Float64}}`) incl. `show_tuple_as_call`
  and `MethodError` hints (review L4).
- Scope declarations: `facts` (module/method/block, via `@compiler_options`-style +
  `Expr(:meta)`), `bounded` (module/method: a set's name in argument position is a
  bound; in a field, it means `Kept{X}`), `concrete` (enforce `nortsite`),
  `no_pirates` (refusal at definition + at load via the method-definition and image
  hooks; the walk over the record for "would win at a fact" — facts §10.3). A trait
  module = the four together.
- Edge rules of exploration §5's table hold as stated (values cross, code doesn't;
  the projection makes it mechanical).
- **Image activation:** package images write a list of their memberships on foreign
  typenames (like `extext_methods`), activated before the image's code is validated,
  with a membership edge kind in `verify_method` for their folded positives (review
  M6). Gate: a two-package session where the second declares a membership on the
  first's type, precompiled, in a fresh depot.

## 5. Milestones

Each: build, land, gate. Gates run `Base.runtests` subsets and the scripts named;
record every number with the build commit in `numbers.md`. If a gate fails twice
without progress, write the case into `notes.md` and pick the named fallback.

### M0 — bring-up + the C7 volume experiment (½ day)
- Create `julia-oc/` (worktree at `45b6d15e34`, branch `oc-build`), full build, run
  `Base.runtests` core as the control timing; create `oc-traits/`, `oc-notes/` with
  this plan and the notes skeleton.
- **The experiment (on the OLD build `julia-1.13/julia`, no new build needed,
  ~5 min):** script over the U5 sessions (`experiments/w83/u5/env_*`,
  `forks-bounded.tsv`; depot per run, `jl --name c7count`). For each function `f`
  with a bounded method, enumerate its compiled specializations (via
  `methods(f)` → `specializations`) and at the bounded position classify the type:
  **A** = count with a non-final type at that position (what the per-match-flag
  placement would invalidate at a definition of the bounded method — all
  chain-matched non-final specializations); **B** = count at `Any` (what
  `morespecific` placement reaches, plus the "no method" backedges of the
  methtable); **C** = count whose type is a member of the bounding set (registry
  query; the true re-dispatch population); plus the number of `methods(f)` that
  would lose `METHOD_SIG_LATEST_ONLY` (those with a non-final arg that intersects).
  Per function and session, a TSV.
  **Settles:** B ≪ A expected (E-233's 1,884 is the upper bound). If so, P3 is
  confirmed and the insertion cost is "f(::Any)'s specializations + the method's
  own"; if A ≈ B everywhere even for `show`, the placement hardly matters — note it,
  keep P3. If C > 0 meaningfully, those are genuine re-dispatch points and the
  ambiguity report gets traffic — note per function.
- Gate: `julia-oc/julia -e '1'`; control test times recorded; experiment table in
  `oc-notes/`.

### M1 — the type system (~1 week)
- Implement §4.1. Files: `src/julia.h`, `src/datatype.c` (entries,
  `jl_declare_membership`), `src/subtype.c` (fallback, the exactness patches,
  `Type{S}` in `jl_isa`/`obviously_disjoint`/`intersect`, `Keyed` special cases),
  `src/jltypes.c` (`has_open_set` bit upkeep in type instantiation),
  `Compiler/src/tfuncs.jl` (`isa_tfunc`, `subtype_tfunc`, `typeassert_tfunc`,
  `tmeet`/`typesubtract`/`hasintersect` sites), `Compiler/src/typeutils.jl`
  (`Conditional`), `base/boot.jl` (`Dynamic`/`Compiled`/`Kept`, the bootstrap bits),
  a small `oc-traits` `@trait`/`@implement` first cut (declaration + `jl_declare_membership`).
- **Gate:** Base's `subtype`, `core`, `ambiguous`, `typemap` tests pass; their time
  within 10 % of the M0 control; `detect_ambiguities(Base)` unchanged; scripts:
  late `@implement` — `S <: X`, `s isa X` true in the new world, false in an old
  world via `invoke_in_world`; `isa(::Tuple{S}, Tuple{X})` and `x::X` on an `S`
  compiled before the membership, re-run in both worlds (review H3's tests);
  old-world positive fold with `min_world` (review M6's test); `isa(Int, X)` with a
  `Type{Int}` membership true (review L10).

### M2 — dispatch: methods at sets, the stopgap, typemap, C7, ambiguity (~1 week)
- Implement §4.2's dispatch half: methods at sets findable (linear placement),
  the stopgap insertion walk + permanent dispatch-cache walk in
  `jl_declare_membership` (logged), C7 in `type_morespecific_`, the set→methods
  index + the membership-time ambiguity report, abstract queries
  (`spec_types = X`, never fully covering) through `ml_matches` → inference.
- **Gate:** `g(s::S)` calling before/after a late `@implement` selects the right
  method in the right world in both worlds (this is where H4's soundness comes from);
  the log shows the invalidation volume per membership (feed into `numbers.md`,
  compare with M0's prediction); `detect_ambiguities` unchanged on Base; a scripted
  `show`-class function with ~200 methods still looks up within 2× of control
  (the linear-list cost check).

### M3 — facts policy + record + `nortsite` + test bed `all` (~1 week)
- Implement §4.4. Files: `Compiler/src/abstractinterpretation.jl` (policy gate at
  `find_method_matches`/`abstract_call_gf_by_type`), `effects.jl` (`nortsite`),
  `typeinfer.jl` (`compute_edges!`, record kinds, the G2 bit at `finish!`),
  `gf.c`/`staticdata_utils.c` (definition/image/deletion/binding hooks;
  `verify_method` learning the record's new kinds), `split_call`, `fold_call`,
  `known_type` (fresh ports of the old build's mechanisms as reference), the
  session-wide default-policy switch for the test bed.
- **Gate:** the G1 acceptance cases rewritten for the new library (start the case
  list in `oc-traits/test/acceptance/`; the old suite's *cases* are background)
  pass plain and under `all`; G2 counts on a scripted trait session match the old
  build's ballpark (g2all rows in the old record); plain behavior bit-identical to
  control on Base tests.

### M4 — the code slot + revalidation (~1 week)
- Implement §4.5. Files: new `src/codeslot.c` (+ `julia.h`), `src/gf.c`
  (compile/invalidate write points, the sentinel-lookup hooks in
  `jl_method_compiled_callptr`/`jl_rettype_inferred`), `src/codegen.cpp` (slot load
  at result-edge call sites), `Compiler/src/reinfer.jl` (result-edge validation
  compared against the callee's current result, not recursion by identity).
- **Gate:** synthetic cascade — `f` calls `g` (emitted, not inlined); redefine `g`
  to code with the same `rettype`/`exctype`/effects; `f`'s CI survives (sentinel →
  promoted) and `f(1)` computes the same value; redefine to a *different* result and
  `f` re-infers. Same in plain and facts code. Then a session-level count: replay a
  session, count sentinel promotions vs re-inferences (this is the old E-260
  question, now measured on the real mechanism; record it).

### M5 — keys: inference, codegen, guards (~2 weeks)
- Implement §4.3 + §4.2's guards. Files: `Compiler/src/abstractinterpretation.jl`
  (the `get_nospecializeinfer_sig` analogue, `get_compileable_sig`), `src/gf.c`
  (`jl_compilation_sig`, `jl_isa_compileable_sig`, `cache_method`
  `cache_with_orig`), `src/codegen.cpp` (the projection `specsig`, the boxed
  wrapper with the offset table, guard emission per M11's shape),
  `Compiler/src/ssair/inlining.jl` (the guard branch via the unionsplit path),
  `src/method.c` (`declared_rettype`), the keep-analysis pass, `bounded_check`,
  the wrapper dispatch for kept values (§4.3 attributes).
- **Gate:** two members sharing a key ⇒ **one** keyed CodeInstance + one inference
  (count `CodeInstances` after calls at both); typed call ≈ E-164's band; the
  dynamic boxed call under E-256's 80–96 ns (numbers into `numbers.md`; if missed,
  record, then take the per-member-wrapper fallback as P2's amendment); a guard
  site: compiled call at `S` before a late membership, after it the guarded branch
  dispatches correctly, and in a loop the guard's load is hoisted (inspect LLVM:
  one load outside); writable fields write through the field reference (a kernel-
  shaped test: sum a column, set a cell); `Vector{Kept{X}}` mixed storage per U2.

### M6 — the surface + images (~1 week)
- Implement §4.6: the macros finished, the four scope declarations, printing rules,
  `Keyed`'s `Base.show`, `no_pirates`' hooks, the image activation list +
  `verify_method` membership kind.
- **Gate:** a two-package image session (§4.6's test); the acceptance suite under
  all four declarations; errors as in `traits.md` §9/§10 for the named cases.

### M7 — the first workload (~1 week)
- Rewrite two shapes from the record into the new encoding, *fresh* (read the old
  ports for the shape, not the code): **(a)** the table/column kernel (a `Column`
  trait, 3–4 members sharing ≤2 keys, a `groupreduce`-style kernel reading cells
  through the view, one `Dynamic` position); **(b)** the solver front end (an
  `ODEAlgorithm`-style open set, `is_nonlinear_algorithm`-style capability
  predicate → its guard site, a `solve` bounded method on a foreign function to
  exercise M2's warning + invalidation).
- **Gate:** results identical to plain Julia's equivalent; instances compiled per
  key, not per member; the guard census matches U9's order of magnitude (a handful,
  none in bounded code); wall numbers into `numbers.md`.

## 6. Notes hygiene (`oc-notes/`)

- `notes.md`: dated entries "what changed, why, which decision/mechanism it moves".
  Anything that contradicts this plan lives here first, then the plan is amended
  with a dated line (the plan is a living document; the exploration and the review
  are not).
- `deviations.md`: one row per known gap between this branch and the plan or the
  references; no IDs needed beyond a stable per-section number.
- `numbers.md`: every number with build commit, setting, and what it measures.
- Do not write into `writeup/`, `experiments/`, `TraitWorld/`, or the old `julia-1.13`
  branch. The prior record is read-only background.

## 7. Standing risks and the probes that watch them

| Risk (source) | Watch | Fallback |
|---|---|---|
| Leaf cache / `cache_method` invariants with `Keyed` (M3) | M5 first day: `cache_with_orig` forced; guard signatures off | keyed instances keep their own small cache inside `gf.c` (not fatal) |
| Typemap linear-list cost on `show`-class functions (M1) | M2 gate's 200-method lookup timing | the membership-list consult in the four walks (M1's option two) |
| Boxed adapter variant (ii) too slow (M5, P2) | M5 gate numbers | per-member wrappers, recorded as an amendment |
| `has_open_set` bit upkeep misses a construction site (H3) | M1's `Tuple`/`Union` tests + a debug assert in `subtype` for "bit says closed, entry found" | recompute structurally without the bit (slow but correct) |
| Revalidation soundness corner: a caller embedding a *constant* from the callee (H1/M7) | M4 gate's different-result case; record classification asserts (a `rettype_const` used ⇒ code edge) | narrow result edges to `rettype`-dependence only |
| Guard volume if a foreign function takes bounded methods (`show`) | M0's C column; M2's log; U9's census as the expectation | the foreign-function warning stays a rule; sealed sets later |
| Concurrency (1.14's lock-free inference) | deferred: 1.13 keeps the inference lock; entry lists copy-on-write and cell writes single-word atomic from day one so the rebase is a test, not a redesign | — |

## 8. First actions for the build agent (in order)

1. Run M0's C7-count experiment on the old build (script from §5 M0; ~5 min, depot
   `c7count`), fill the TSV, note the verdict in `notes.md`.
2. Create the folders and the worktree (§2), kick off the full `julia-oc` build in
   the background (exclusive slot), write `oc-notes/README.md` while it builds.
3. When the build finishes: control `runtests` timing into `numbers.md`; begin M1.
4. Keep `notes.md` current from the first decision you make.
