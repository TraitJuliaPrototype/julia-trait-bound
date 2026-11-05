# M3 edit plan — facts policy, the dependency record, `nortsite`, the G2 bit, the test bed `all`

Plan only (planner subagent, 2026-10-31). Scope is exactly plan §4.4 + §5.M3's gates,
plus D-M2-7's dominance tightening (named an M3 candidate in notes.md 2026-10-31).
All anchors **tree-verified at `c3f0b4bc11`** (branch `oc-build`) — file:line quotes
below were read fresh from this tree, and behavior anchors were probed on
`julia-oc/usr/bin/julia` (probe `/tmp/opencode/m3_anchor_probe.jl`). **No struct- or
word-layout change is planned (§A rule; see §2 for the self-description audit).**
The old build (`julia-trait-bound/julia-1.13` @ `00dcc9994c`, branch `trait-world-1.13`)
is reference only — line numbers there are its own; §F lists every place old ≠ new.

> **§R (coordinator amendments, plan review round 1) is BINDING and overrides the
> text above and below it.** Rulings on §G; D10 is deleted by R-0.

## 0. Ground truth and invariants

**What M1–M2 give the Compiler side (all verified at HEAD):**
1. §0's query-world override makes inference answer membership queries at the *right*
   world (`jl_set_membership_query_world`, read by `jl_membership_world`) — a facts
   frame compiled after an `@implement` sees the entry (gate `m2_post_declare_infer`).
2. Entry-derived matches carry world bounds into `matches.valid_worlds` →
   `sv.valid_worlds` → CI `min_world` (M2 §6 `jl_membership_match_range`, including
   Vararg/Union positions and `future_min`) — a facts CI at a member already has
   M2's `min_world` bound; the record's membership edge (§8) must **carry the entry**
   so M4's revalidation can re-check that bound, not recompute it.
3. The membership fronts compose (`isa`, `intersect`, dispatch); `subtype()` answers
   direct entries only (D-M2-1). **Consequence for this plan (binding):** nothing in
   M3 may read `<:` as membership-complete. The policy gate and G2 rest on *dispatch
   outcomes and isa/intersection answers*, which compose; no hunk consults `<:` as a
   membership oracle.
4. Today **no positive membership ever folds in the compiler**: `positive_fold_blocked`
   (`Compiler/src/typeutils.jl:60-63`) refuses every entry-answered positive "until
   M6's min_world bookkeeping lands (M2)". So M3's membership edge kind lands with
   the *plumbing* built and taught (§3, §8, §9), and its producer is half-full:
   dispatch-at-set-shapes (§8) emit it; folded positives arrive with M6's raise.
5. Probed on the binary: `Effects` has **9 fields, no `nortsite`** (probe 1);
   `encode_effects` words use bits 0–14, **bit 15 free** (probe 1b/1c);
   `CodeInstance.flags` = `0b00001011` — **bits 4–7 free** (probe 2);
   `jl_get_module_max_methods(Main) = -1` — the module-option precedent works (probe 7);
   CI edges of an inlining function are bare `CodeInstance` items; a non-inlined call
   is a `(sig, MI)` pair (probe 3/8, §3's table).

**Invariants (continued from m2-editplan):**
- **I1 exactness** — no answer widens; the policy *narrows what inference is allowed
  to assume*, never what dispatch answers.
- **I2 no folded positives** — stands; §8's edge kind is the record half of M6's raise.
- **I3 inertness** — with no `JULIA_FACTS` env, no marks, and no open sets, every new
  check is a false `Bool` read or a cheap identity-compare; the three Base suites must
  stay bit-identical to the control (`numbers.md`: M0 2:03.36, M2 1:40.87, exit 0).
- **I5 cache soundness** — unchanged; §8 rides on M2's bounds.
- **P1 (pinned)** — *one* CI per `(MethodInstance, policy, flags)` and **no second
  owner, ever**. Here the policy is a property of *the method being inferred* (the
  caller), so an MI has exactly one policy by construction: no owner token, no cache
  key fork, no `FACTS_OWNER`/`jl_code_owner`/`leaves_to`/`facts_edge` (all old-build,
  not ported — §F). The only owner *token* M3 uses is for `return_type`'s plain-answer
  cache (§7), which never runs code; state the P1-honor line per section.
- **P-new (G1 corollary)** — the policy changes typing/records/speed, never results:
  a policy CI and a plain CI of the same MI compute the same values in the same world
  (facts.md §2.1 "G1 depends on no declaration"). Every gate asserts exactly this.

## 1. The facts policy, keyed by the caller's method — `Compiler/src/facts.jl` (new)

### 1a. The criterion, formal

`facts.jl` (new file; `include`d in `Compiler/src/Compiler.jl` between
`include("tfuncs.jl")` (:185) and `include("abstractinterpretation.jl")` (:187) —
one-line edit; covers **both** BaseCompiler and the stdlib Compiler, because
`base/Base_compiler.jl:378` includes the same `Compiler.jl`).

`is_fact_sig(T, max_union_splitting)` is true iff `T isa DataType && T <: Tuple` and
one of the facts §3 forms holds. Written down formally (the six forms; the old build's
`facts.jl:196-311` is the port source, functions quoted there by line):

| # | form (informal) | predicate |
|---|---|---|
| F1 | dispatch tuple | `isdispatchtuple(T)` — every element a concrete non-kind, no Vararg |
| F2 | tuple-element union splits, Julia's cost | no Vararg; every element is a dispatchelem, or a tuple type of elems/`Union`s of concrete elems (`tuple_union_lengths!`), and `union_split_cost(lengths) ≤ max_union_splitting` (=4 default, `InferenceParams().max_union_splitting`, probe 6) |
| F3 | concrete `Vararg` tail | every fixed element a *concrete member*, tail `Vararg{E}` with `E` a concrete member; concrete member = dispatchelem that is not a kind, or a tuple type of concrete members (`concrete_member`/`vararg_fact`) |
| F4 | a closure's call at kinds | `is_closure_type(T.parameters[1])` (generated name `#…`) and every element a dispatchelem or `DataType`/`UnionAll`/`Union` (`kinds_ok`) |
| F5 | top-level union split | each split of the call's argument union is F1–F4 (checked by the gate, not by `is_fact_sig` — §1c) |
| F6 | `invoke`/`hasmethod` at a declared signature | **not gated** — resolved by `findsup` + invoke edge, as plain Julia (facts §1.2 "Not gated"); the second `find_method_matches` caller, `abstract_applicable` (`tfuncs.jl:3229` in `abstract_applicable`, `tfuncs.jl:3221`), keeps plain behavior |

A form not listed is a run-time site. **Degrees of freedom in the reference (D1):**
F4's generated-name rule also admits lowering's keyword-sorter bodies, and F4's G2
is explicitly an *assumption* in facts §3 ("only the closure's own module adds
methods"); a `Keyed{X,R,F}` element is not covered by F1–F4 (it is a kind-like
`generic_wrapper` name, never instantiated) → M3 rule: **`Keyed` at a position is
not a fact element → the call is a run-time site** (conservative; M5's erased-key
fact form, if ruled, extends `is_fact_sig` then). Recommendation: adopt F4 as-is.

### 1b. Policy attachment (internal, M6 binds the surface)

`facts.jl` holds the session state:

```julia
# Policy marks. The policy is a property of the method BEING INFERRED (the caller),
# so one MI has one policy: no cache key forks (P1). Marks live in a session table;
# the declaration surface (`facts`, module scope, image persistence) is M6 and binds
# onto these functions.
const FACTS_MARKS = IdDict{Any, Symbol}()   # Method|Module => :facts
const CONCRETE_MARKS = IdDict{Method, Bool}() # `concrete` enforcement (§4c)
const COMPILER_MODULE = Ref{Module}(@__MODULE__)
mark_facts!(@nospecialize(f)) = for m in methods(f); FACTS_MARKS[m] = :facts; end
```

The per-frame decision, computed **once per frame at construction** (not per call
site — the hot-path cost is one `Bool` field read per call site):

```julia
facts_default() = ccall(:jl_facts_default, Cint, ()) != 0     # §5: env, read once per process in C
function frame_facts(mi::Core.MethodInstance, interp)
    def = mi.def
    def isa Core.Method || return facts_default()             # top-level thunks
    mod = def.module
    (mod === COMPILER_MODULE[] || _is_child_of(mod, COMPILER_MODULE[])) && return false  # the compiler is ALWAYS plain
    haskey(FACTS_MARKS, def) && return true
    haskey(FACTS_MARKS, mod) && return true
    return facts_default()
end
```

`_is_child_of` walks `parentmodule` (3 lines; the compiler's own code stays plain in
*every* setting and compile queue — facts §6.4). Cost with nothing marked and no env:
`facts_default()` is one ccall to a C-side cached value (~10 ns) **once per frame
construction**; the per-call-site cost is `sv.facts` (a field read). I3: empty dicts
⇒ `haskey` misses ⇒ false everywhere; frames never created by us (external
interpreters) never set it. **Alternatives considered (D2), rejected here:** a bit on
`jl_method_t`/`jl_typename_t` (layout + serialization; `concrete_only`
(`src/julia.h:567`, set at `base/broadcast.jl:197`, read at
`Compiler/src/inferencestate.jl:1127-1131`) is the *shape* precedent — a per-name
word set from Julia — but its key (callee name) is wrong for us, and the module
precedent `jl_get_module_max_methods` (`src/module.c:733`, read via
`inferencestate.jl:1133-1138`) needs a Module field, i.e. a layout change we do not
own in M3). A rooted-C-table variant (M2's `open_set_methods` pattern incl. its
`gc-stock.c`/`gc-mmtk.c` roots) is D2's alternative; the Julia-side table wins on
diff size and bootstrap risk, loses on image persistence — which M6 must rebuild
anyway when it binds the declarations.

`InferenceState` gets `facts::Bool` — struct `Compiler/src/inferencestate.jl:262`
(field area; outer constructor `InferenceState(result, cache_mode, interp)` at :599
is the single choke — set `facts = frame_facts(result.linfo, interp)` there; the
inner constructor at :322 takes it as a parameter). `MethodCallResult`
(`abstractinterpretation.jl:854`) gets the same field, set at its constructors from
`frame_facts(mi, interp)` of the method/CI whose frame it re-runs — so semi-concrete
evaluation and IPO re-runs keep the frame's policy (the old build got this for free
from the owner-keyed interp; we carry it per frame). `NativeInterpreter`
(`Compiler/src/types.jl:380`, ctor :389) gains `facts::Bool` = `facts_default()` —
the *session default* only; the per-frame rule above is the authority (the old
build's `interp.facts` **and** `interp.owner` do not come; owner stays `nothing` — P1).

### 1c. The gate at `find_method_matches` — `abstractinterpretation.jl`

Anchor (`abstractinterpretation.jl:365-372`, as read):

```julia
function find_method_matches(interp::AbstractInterpreter, argtypes::Vector{Any}, @nospecialize(atype);
                             max_union_splitting::Int = InferenceParams(interp).max_union_splitting,
                             max_methods::Int = InferenceParams(interp).max_methods)
    if is_union_split_eligible(typeinf_lattice(interp), argtypes, max_union_splitting)
        return find_union_split_method_matches(interp, argtypes, max_methods)
    end
    return find_simple_method_matches(interp, atype, max_methods)
end
```

Hunk (port of old `facts_find_method_matches`, old `facts.jl:316-329`):

```julia
function find_method_matches(interp::AbstractInterpreter, argtypes::Vector{Any}, @nospecialize(atype);
                             max_union_splitting::Int = InferenceParams(interp).max_union_splitting,
                             max_methods::Int = InferenceParams(interp).max_methods,
                             facts::Bool = false)
    if facts
        facts_gate(interp, argtypes, atype, max_union_splitting, max_methods) === nothing ||
            return facts_gate(...)          # FACTS_ABSTRACT_SITE, or fall through below
    end
    ... unchanged body ...
end
```

(concrete shape: the two-line form —
`facts && !facts_splits_ok_all(...) && return FACTS_ABSTRACT_SITE;` then today's body;
`facts_splits_ok_all` = the old `facts_find_method_matches` body: if
`is_union_split_eligible`, every `switchtupleunion` split must satisfy `is_fact_sig`,
else the plain `is_fact_sig(atype)` must; each split's *match* still comes from
today's `find_*_method_matches`, so world ranges and M2's bounds flow untouched.)

`FACTS_ABSTRACT_SITE = FailedMethodMatch("facts mode: argument types not concrete,
dispatched at run time")` (old `facts.jl:313`). Callers:
- `abstract_call_gf_by_type` (`:122`; the call at `:132`) passes `facts = sv.facts` —
  `sv::AbsIntState` is in scope at both the call site and the `FailedMethodMatch` arm.
  **P1 line:** the gate consults the *frame's* policy; the callee is inferred under
  its own frame's policy in `typeinf_edge` as today — one cache, one CI per MI.
- `abstract_applicable`'s call (`tfuncs.jl:3229`) passes nothing ⇒ `facts=false`
  (form F6, "not gated").

**Run-time sites.** Under `facts`, a call that records no edge is a run-time site:
result `Any`, exctype `Any`, effects `EFFECTS_RTSITE` (nortsite false, §2). Today
those arms already return `(Any, Any, Effects(), NoCallInfo())`; they become
`(Any, Any, unedged_effects(sv), NoCallInfo())` with
`unedged_effects(sv) = sv.facts ? EFFECTS_RTSITE : Effects()` (old `facts.jl:26`).
Call sites in THIS tree (all with `sv` in scope), anchors as read:
- `abstract_call_gf_by_type`: `:130` (after `:latestworld`), `:135`
  (`FailedMethodMatch` — includes `FACTS_ABSTRACT_SITE`, "Too many methods matched",
  and the union-split "For one of the union split cases…" at `:391`), `:147`
  (concrete-only refusal — `is_concrete_only(func)` at `:143`, the callee-keyed
  precedent), `:157` (top-level refusal at `:151-161`).
- `abstract_invoke` (`:2304`): the six bail-outs at `:2346`, `:2350`, `:2352`,
  `:2361`, `:2362`, `:2368` (`nargtype isa DataType || … # other cases are not
  implemented below` ×2, `hasintersect(… Method, CodeInstance) …`, `isexact ||`,
  `isdispatchelem(ft) ||`, `matched === nothing ||`). An `invoke` at a *resolved*
  declared signature keeps its invoke edge and is **not** a run-time site (form F6).
I3: every one of these is `Effects()` under `!sv.facts` — line-identical behavior.
The frame's `ipo_effects` merges `nortsite` like `nortcall`, so the site propagates
to callers through their `abstract_call` effect merges — no separate frame flag
(the old build's second attempt, commit `0c589fd385`, landed exactly here).

## 2. The `nortsite` effect bit — `Compiler/src/effects.jl` (+ two enforcement readers)

**Self-description audit (the M1a lesson, done before designing):** in 1.13 the
effects *word* is `jl_code_instance_t.ipo_purity_bits`, `_Atomic(uint32_t)`
(`src/julia.h` "purity results" block, the comment at `:479` pointing at
`encode_effects`); its Julia-visible field type is `UInt32` — probe 4 read it back
as `UInt32` (`16608`). Bits 0–14 are used by `encode_effects`
(`Compiler/src/effects.jl:339-349`); **bit 15 is free and the word does not widen**
— so the M1a truncation hazard does not apply: no width change, no `jl_svecset`
edit, no `test/core.jl:47` tripwire touch. Consumers enumerated (all read the word;
none assumes bits > 14): `effects.jl` encode/decode (`:339`/`:351`);
`abstractinterpretation.jl:2337` (decode of a cached CI in `abstract_invoke`);
`optimize.jl:689`; `typeinfer.jl:158` (encode), `:683` (encode), `:965` (decode);
`ssair/inlining.jl:856`, `:895`, `:1349`; `ssair/irinterp.jl:10`; C: the three
writers pass the word through (`gf.c:727`, `:746`, `:790` in `jl_ci_map` /
`jl_fill_codeinst` / `jl_update_codeinst`), `staticdata.c:552`
`effects_foldable(uint32_t)` reads bits 0–13 only (`:563-568` mask tests —
adding an inverted bit 15 leaves it correct), `julia.h`'s purity comment block
(update the comment: `uint32_t rtsite : 1; // inverted, bit 15`).
The **statement/method override word is NOT touched**: `Core.EffectsOverride`
(`base/expr.jl:906`, 11 Bool fields, stored in `jl_method_t.purity` and ssaflags
bits `NUM_IR_FLAGS(3)..`) stays as is — *only the facts mode clears `nortsite`; no
assertion sets it* (facts §1.3), so it never becomes overridable. If a future
decision wants an override bit, that IS a word decision → D4 asks, but M3 needs none.

**The port** (old `effects.jl:104-106, 132, 143, 154, 199, 214, 283-287, 302, 323,
367, 381` — the hunks transfer textually onto this tree's struct at
`effects.jl:119-156` (`nortcall::Bool` at `:128`, ctor param `nortcall::Bool)` at
`:138`, kw ctor `:182-203` with `nortcall::Bool = effects.nortcall` at `:192`):

```julia
    nortcall::Bool
    nortsite::Bool                      # :no run-time site here or in a callee (facts mode; facts §1.3)
...                                        # inner ctor: positional param, default true in kw ctor
const EFFECTS_RTSITE = Effects(Effects(); nortsite=false)   # after EFFECTS_UNKNOWN (:180)
...
is_nortsite(effects::Effects)            = effects.nortsite  # beside is_nortcall (:305)
# encode_effects: add  (((!e.nortsite) % UInt32) << 15)     # stored inverted: zeroed words read as "no run-time site"
# decode_effects: add  iszero((e >> 15) & 0x01)
# is_better_effects / merge_effects: the nortcall lines, duplicated for nortsite (:205/:275 areas, mirror :285)
```

Inverted storage means CIs created on the C side with a zeroed word (the
`jl_new_codeinst` paths, `finish!(mi, ci, src)`'s `zero(UInt32)` at
`typeinfer.jl:202`) read `nortsite = true` — sound: plain code never clears it.

**Assertion withdrawal** (facts §8; the two readers). Old build did it as a wrapper;
port that shape onto this tree's call sites:
1. Method-level: `adjust_effects(ipo_effects, def)` (`typeinfer.jl:480`, callers
   `:566`, `:607`, `:1113`, `:1137`) — add the wrapper
   `adjust_effects(ipo_effects, def, frame) =
       frame isa InferenceState && frame.facts && !is_nortsite(ipo_effects) ?
       ipo_effects : adjust_effects(ipo_effects, def)`
   and pass `frame`/`me` at the four call sites (each has the frame in hand;
   `:1113`/`:1137` have `frame`). An asserted `@assume_effects` does not apply to a
   frame that holds a run-time site, itself or transitively (`nortsite` carried).
2. Statement-level: `merge_override_effects!` (`abstractinterpretation.jl:3631-3639`)
   — wrap: `effects = (sv.facts && !is_nortsite(effects)) ? effects :
   override_effects(effects, decode_statement_effects_override(sv))`, i.e. apply
   the statement's `@assume_effects` only when `nortsite` holds (old
   `abstractinterpretation.jl:3654` shape). `set_curr_ssaflag!` unchanged.
I3: `frame.facts == false` short-circuits both readers before touching `nortsite`;
`decode_statement_effects_override` cost unchanged on plain paths.
(The old build's `WITHDRAWN_LOG` tool is deferred — §E.)
**Consequence for §4/§5:** `ci` effects give `nortsite`; *fully typed* is a per-CI
fact from here on, readable by any consumer without walking the record.

## 3. The dependency record — `CodeInstance.edges` extended

**The layout today (probe- + read-verified).** `edges` is a `_Atomic(jl_svec_t*)`
(`julia.h`, "inference state cache" block) holding, positionally (§C of m2-editplan
called these kinds; the iterator `ForwardToBackedgeIterator`,
`typeinfer.jl:712-751`, and `verify_method`, `reinfer.jl:217-287`, agree):

| edge slot content | meaning | iterator | verify_method |
|---|---|---|---|
| `sig::Type, callee::MI\|CI` | resolved call (fact + code edge) | pair → MI backedge | `verify_call` |
| `n::Int, sig, callee…` (`abs(n)` matches, `n>0` fully_covers) | method-table query (dispatch edge; `n<0` = "no method") | `item isa Int` skip-into-content (`:721`) | Int arm (`:235`) |
| `invokesig, Method\|MI\|CI` | `invoke` edge; a bare `Method` = failed-call marker | Method skip (`:724`, `:739`) | else arm (`:255-270`) |
| `Core.Binding` | binding read | `:728` | Binding arm (`:242`) |
| `invokesig, MethodTable` | legacy abstract dispatch | `:740` | `:257` skip |
| bare `CodeInstance` | inlined/const-prop identity edge | `:731` → MI backedge | CI → recursive child |

**The four new kinds — struct-wrapped slots** (self-identifying; order-independent;
the serializer is kind-blind so images "just work" — verified: the three C readers of
`edges` today are defensive to unknown items: `gf.c:2006-2012` skips non-`CodeInstance`
in the promote walk; `gf.c:2464-2472` compares by pointer identity in targeted
invalidation; `strip_specializations_` `staticdata.c:2603` replaces the whole svec
under `--strip-ir`). Precedent: the old build rode `FoldRecord` through the same
machinery (`old typeinfer.jl:751` iterator skip, `old reinfer.jl:242-247` verify arm).

```julia
# facts.jl — the record kinds (plan §4.4). All ride edges as single items.
struct ResultEdge       ci::CodeInstance end                       # §3b: emitted call whose
                                                                   # callee result the caller
                                                                   # used as a type
struct InlineIdentity   method::Method; hash::UInt64 end           # inlined code identity
struct LayoutIdentity   datatype::DataType end                     # layout identity
struct MembershipEdge cell::Any; entry::Any; sig end               # membership cell (nothing
                                                                   # in M3 — M5 fills) + the
                                                                   # entry + the query sig
struct FoldRecord       g::Any; args::Tuple; value::Any end        # fold (old-build port)
```

**Encoding decisions (D5):** structs, not tagged pairs — a tagged-pair encoding (e.g.
`(Kind, payload…)`) would force every consumer to peek forward, and
`ForwardToBackedgeIterator`/`verify_method`'s else-arms currently *misread* unknown
first items as invoke edges (`verify_method:255-269` treats any unrecognized item as
`(invokesig, callee)` — the `@assert !(edge isa Method)` at `reinfer.jl:224` only
guards `Method`). Struct wrappers make every consumer's `elseif edge isa …` arm
trivial and the misread impossible. **Serialization consequence to bless (D5):** a
record edge holds the live `Method`/`CodeInstance`/`DataType` alive and is serialized
into precompiled images (the old build accepted this for `FoldRecord`); package images
keep identity references to everything they inlined/folded/laid out — memory cost, and
deliberate (the store, P4, later *wants* them; nothing today consumes them).

### 3b. Producers — `compute_edges!`, the inliner, the frames

- **Result edges.** Classification, not replacement: under `sv.facts`, every
  *emitted* (non-inlined, non-const-folded) call that records a `(sig, CI|MI)` pair
  additionally records `ResultEdge(callee_ci)` **alongside the pair**. The pair keeps
  invalidating the caller as upstream (M4's slot + sentinel revalidation is what
  flips emitted calls to revalidate-in-place — plan §4.5; until M4 lands, result edges
  are pure classification for G2 and revalidation groundwork). Where the callee has no
  cached CI (cycle partners, uncached constprop), the pair is a bare MI /
  `ci_as_edge` — no `ResultEdge` (a *bare MI* edge means "same-owner local result",
  facts §4.3 — M4's edge case, not M3's).
  Site: `abstract_call_gf_by_type`'s merge of each match's `mresult.edge` (the
  `handle1` closure, `abstractinterpretation.jl:191+`): when `sv.facts &&
  !inlined && !const_result_used_the_ci`, push `ResultEdge(edge_ci)` on `sv.edges`
  once per distinct callee. `sv.edges` is the running vector `compute_edges!`
  (`typeinfer.jl:790-800`) snapshots via `result_edges` (:100) — pushing directly is
  how the old build added `FoldRecord`s (`FoldCallInfo`, old `facts.jl:524-527`).
- **Inline identities.** The inliner: `ssair/inlining.jl` `add_inlining_edges!` /
  `ir_inline_constant!` / `ir_inline_constant_prop_result!` paths that add the
  callee CI edge — where `add_edges!(edges, ci)` happens for a *cross-frame* inline,
  also push `InlineIdentity(m, lowered_code_hash(m))` for the inlined method (D6:
  the hash function — recommendation: session-cached `IdDict{Method,UInt64}` of a
  stable digest over the uncompressed CodeInfo body; computed only for frames with
  `facts` (so `all` and marked code), once per Method per session; `:code` vector,
  `slotnames` skipped). The *existing* CI edge stays (invalidation unchanged, §3 note).
  The inliner's pass runs post-inference over `sv.src`/IR — it appends edges into
  `src.edges`/`ir.edges` which `compute_edges!`/`finish!` pick up (`compute_edges!`
  already appends `sv.src.edges`, `:795-798`).
- **Layout identities.** A census pass at `finish!` (facts frames only, gated
  `caller.facts`): scan the optimized `CodeInfo` for `calls(s)->(s.args[1] ===
  Core.getfield | setfield! | nfields | Core.arraysize)` statements and record
  `LayoutIdentity(widenconst(slottypes/ssatype of the aggregate arg))` per distinct
  concrete `DataType`. Coarse on purpose (§E: the store refines; layout edges'
  contribution to invalidation policy is M4+; nothing consumes them today —
  plan §4.4 "the record is still built").
- **Membership edges**: §8.
- **FoldRecord**: §6.

### 3c. Consumers to teach (the exact list, all verified)

1. `ForwardToBackedgeIterator` (`typeinfer.jl:716-751`) — add, beside the `Method`
   skip at `:724`:

```julia
        elseif item isa Union{ResultEdge, InlineIdentity, LayoutIdentity, MembershipEdge, FoldRecord}
            i += 1
            continue # record edges register no backedge: nothing invalidates through them (M3)
```

   (the old build's identical skip: `old typeinfer.jl:751` for `FoldRecord`).
   **This is the hunk that keeps `store_backedges` (`:761-788`) honest** — its
   `item::MethodInstance` downcast (`:782`) would otherwise crash on a record kind.
2. `verify_method` (`reinfer.jl:162`; the non-CI loop `:217-287`) — new arms before
   the else-arm at `:255`:

```julia
                    elseif edge isa FoldRecord
                        j += 1
                        min_valid2 = minworld; max_valid2 = fold_holds(edge, validation_world) ? typemax(UInt) : UInt(0)
                    elseif edge isa ResultEdge
                        j += 1
                        # M3 validates a result edge as a code edge (conservative): the callee CI's own
                        # verification result must hold; M4's revalidation relaxes this to result-equality.
                        r = verify_child(edge.ci, ...)     # same machinery as the recursive phase's child
                        min_valid2, max_valid2 = r.result_minworld, r.result_maxworld
                    elseif edge isa InlineIdentity
                        j += 1
                        min_valid2, max_valid2 = minworld, (lowered_code_hash(edge.method) == edge.hash ? typemax(UInt) : UInt(0))
                    elseif edge isa LayoutIdentity
                        j += 1
                        min_valid2 = minworld; max_valid2 = maxworld    # layout re-verification is the store's (P4)
                    elseif edge isa MembershipEdge
                        j += 1
                        min_valid2 = minworld; max_valid2 = membership_edge_holds(edge, validation_world) ? typemax(UInt) : UInt(0)
```

   and the recursive phase (`:293-315`, the `edge isa CodeInstance` search at `:301`)
   additionally treats `edge isa ResultEdge` as a child (its `ci` gets its own
   `VerifyMethodInitialState`) — result edges keep their callee *verified* in M3.
   `insert_backedges`/`scan_new_methods!` are untouched (they read method edges, not
   CI records).
3. `compute_edges!` — nothing (record kinds ride the vectors it merges), *but*
   `add_edges!`'s CallInfo hooks add the fold/split payloads:
   `FoldCallInfo`/`SplitCallInfo` `add_edges_impl` (§6) push the kinds.
4. C side: **no C change is needed for serialization** (generic object-graph writer;
   the three readers are defensive — table above), *except* the strip path is already
   fine and the **method-deletion / binding-invalidation hooks**: deletion — nothing
   new in M3 (a deleted method still kills callers through the pre-existing code
   edges; record kinds hold no separate registration, so there is no dangling
   backedge to break); binding-invalidation — the existing `Core.Binding` machinery
   is untouched. The *hooks* those names refer to in the plan letter (`method.c`/
   `gf.c` definition hooks, image-activation refusals) are the **M6** no_pirates
   machinery (§E) — M3 states this as its honest remainder.
5. `emit_codeinst_and_edges` (`gf.c:364-397`) reads `:invoke` *expressions*, not
   edges — untouched. `jl_get_ci_edges`-style consumers: none in this tree (grep
   verified: the only C edge-content loops are the two in `gf.c` above + `method.c`'s
   *lowering*-time `:edges` (different object), plus `staticdata.c:2603`).

**P1 line:** record kinds are data in `edges` under the single cache owner; no owner
token, no second CI anywhere.

## 4. G2 as a predicate on the record; the bit; strict/concrete readers

### 4a. The predicate — `facts.jl`

Port of the old `rests_on_facts` (old `facts.jl:414-449`) re-keyed per §4.4's letter:

```julia
g2_holds(ci::CodeInstance) = g2_edges(ci.edges, true)
function g2_edges(edges, top::Bool)
    i = 1
    while i ≤ length(edges)
        e = edges[i]
        if e isa Union{ResultEdge, LayoutIdentity, MembershipEdge, FoldRecord, Method, Core.Binding}
            i += 1                                  # may go anywhere / no dispatch dependence
        elseif e isa Int                            # dispatch edge (method-table query)
            sig = edges[i+1]; is_fact_sig(sig) || return false
            i += 2 + abs(e)                         # + callee list
        elseif e isa Union{MethodInstance, CodeInstance}   # bare CI/MI (inline/const-prop/cycle)
            # inline identities are cross-checked via their InlineIdentity; the code edge's sig is the
            # callee's specTypes; require it a fact when the pair stands alone (top-level), else trust
            is_fact_sig(C.get_ci_mi(e).specTypes) || return false
            # recursion into the child's record happens through the InlineIdentity bit read below only
            i += 1
        elseif e isa Core.MethodTable
            is_fact_sig(edges[i-1]) || return false  # consults i>1 by construction: see hunk
            i += 2
        elseif e isa InlineIdentity
            ci = edges[i+1]                          # the code edge added beside it (§3b) — pair trust:
            i += 1
        elseif e isa Type                            # (sig, callee) pair — dispatch+code edge
            is_fact_sig(e) || return false
            callee = edges[i+1]
            callee isa Union{MethodInstance,CodeInstance,Method} || return false
            if callee isa Union{MethodInstance,CodeInstance}
                # inlined callees must themselves satisfy G2 (§4.4): the stored bit;
                # unset (cycle partner, not yet marked) reads false — conservative, D7
                callee isa CodeInstance && !ci_is_g2(callee) && !isconstcallee && return false
            end
            i += 2
        elseif e isa Core.Binding
            i += 1
        else
            return false                             # unknown item: conservative
        end
    end
    return true
end
```

(the final code in the author pass collapses the obvious arms; the *rule* is the
letter: **every dispatch edge at a fact signature; every inlined identity's own
record satisfies G2 (the stored bit — no recursion, so cost is O(edges) bit reads);
result edges may go anywhere.** Invoke pairs `(invokesig, mi)`: fact OR
`invokesig == (mi.def::Method).sig` — the old `rests_on_facts:440` clause.)
**Cycle note (D7):** a cycle partner's CI gets its G2 bit only at its own `finish!`;
the SCC finishes children-first (`finishinfer!` reverse order), so an inlined child
inside the same cycle can read false → parent G2 false. Inlining *is* blocked across
direct recursion upstream, so the reachable loss is small; the conservative read is
sound (G2 false never claims a property). Accept for M3 or bless the SCC second pass — D7.

### 4b. The bit — `ci.flags` bit 4 + the finish! hook

Anchor: `jl_code_instance_t`'s `_Atomic(uint8_t) flags` (`src/julia.h:500-503`;
bits `0b001` specsig, `0b010` invoke-match, `0b100` = `JL_CI_FLAGS_FROM_IMAGE`
(`julia.h:449`), `0b1000` = `JL_CI_FLAGS_NATIVE_CACHE_VALID` (`:450`); probe 2:
bits 4–7 free). No width change (uint8 word already described; the G2 value fits
the existing UInt8 field ⇒ **no M1a hazard**, no constfields/atomicfields bitmap
edit — `src/jltypes.c:3733-3740` untouched).

- New `#define JL_CI_FLAGS_G2 0b00010000` (`src/julia.h:450` beside the others).
- New ccallable `JL_DLLEXPORT void jl_ci_set_g2(jl_code_instance_t *ci)`
  (`gf.c` next to `jl_mi_cache_insert`'s flag write `:813`):
  `jl_atomic_fetch_or_relaxed(&ci->flags, JL_CI_FLAGS_G2);` — add
  `XX(jl_ci_set_g2)` to `src/jl_exported_funcs.inc` (M1b/M2 precedent: the gates'
  and Compiler's ccallables live in the XX list; the generated
  `jl_data_globals_defs.inc` is regenerated by the Makefile, notes build fact #2).
- `finish!` (`typeinfer.jl:104`): after the `ccall(:jl_update_codeinst, …)` at `:162`
  and **before** `cache_result!` (`:165-167`, so no one can see the CI before its bit),
  for `caller.facts`: `g2_holds_pending(ci) && ccall(:jl_ci_set_g2, …)`. The read
  side (`ci_is_g2`) mirrors `is_code_from_image` (`typeinfer.jl:1340-1342`,
  `CI_FLAGS_FROM_IMAGE` pattern). The second `finish!` (user-src, `:194-224`) computes
  the predicate over its `edges` the same way (its `ipo_effects` is the zero word ⇒
  nortsite true by the inverted encoding — a user-src CI claims "fully typed", the
  old build accepted the same default; note it).
- `codeinst_as_edge` (`:1009-1034`, the constprop CI-as-edge): set the bit there too
  (`caller.facts` known from `sv.facts`) — these CIs are G2-read by other frames.
- **Image load:** `staticdata.c:1773` currently *clears* CI flags at load keeping only
  the native-cache bit: `newci->flags &= JL_CI_FLAGS_NATIVE_CACHE_VALID` → hunk:
  `&= (JL_CI_FLAGS_NATIVE_CACHE_VALID | JL_CI_FLAGS_G2)`. Without it a loaded facts CI
  loses its G2 claim (silently under-claiming — safe but wrong for the counts).
  `JL_CI_FLAGS_FROM_IMAGE` still set at `:2312` as today. (This is a serialization
  *behavior* change on a flag word → inside D4's bless.)
- **`verify_method` does not recompute G2** (it verifies edges; the bit is an
  assertion about classification, and §3c's verify arms are the soundness). The bit
  survives because `verify_method`'s cleanup (`reinfer.jl:317-346`) only writes
  min/max world + flags-read at `:329` (native-cache) — flag bits it doesn't touch
  ride through; note `reinfer.jl:9` `const CI_FLAGS_NATIVE_CACHE_VALID = 0b1000` →
  add `const CI_FLAGS_G2 = 0b00010000` beside it for reinfer's future readers.

### 4c. Strict mode and `concrete` enforcement

`NotFullyTypedError` (defined in `Compiler`, exported for `Base.Experimental` — name
only; message names the MI and the first untyped call's line via `sv.src`):

```julia
# finish! hook, after the G2 mark (typeinfer.jl:164 neighborhood):
if caller.facts && !is_nortsite(result.ipo_effects) && haskey(CONCRETE_MARKS, mi.def) && CONCRETE_MARKS[mi.def]
    throw(NotFullyTypedError(mi))    # `concrete` was demanded (§4.4); no opt-out present
end
```

- The error fires **only** for `concrete`-marked methods (M6 binds the `concrete`
  declaration to `mark_concrete!`); under `all` and plain marks it never fires — the
  policy tolerates run-time sites (facts §13). Throwing at `finish!` is a compile-time
  error surfacing through `code_typed`/dispatch — D8 blesses throw-vs-report.
- **Strict mode (pirates):** M3 delivers its *predicate half*: the G2 bit +
  `g2_edges` + `ci_is_g2` answer "is this valid trait-world code, and are its facts
  concrete" — the definition-time refusal walk (`_winning_fact`'s walk over callers,
  plan §4.6's "refusal at definition + at load via the method-definition and image
  hooks") is **M6**: it needs the definition hook the old build had as patch-piece 1,
  which this tree does not have. §9 states the hook as M6's consumer of what M3 builds.

## 5. The test bed `all` — one mechanism: the environment (with the argument)

Plan §4.4/§12.2 of facts: `all` is a *session-wide default policy*. Chosen: **env
var** `JULIA_FACTS=1` (`1` on, unset/`0` off; M3 has no other modes; the name is
D3's to bikeshed — `JULIA_COMPILE_BY_FACTS` was the old build's), read **once per
process** in C:

```c
// gf.c — read once per process; no image save in M3 (see below)
static int jl_facts_default_cached = -1;
JL_DLLEXPORT int jl_facts_default(void)
{
    if (jl_facts_default_cached == -1) {
        const char *v = getenv("JULIA_FACTS");
        jl_facts_default_cached = (v && v[0] && strcmp(v, "0") != 0);
    }
    return jl_facts_default_cached;
}
```

(`XX(jl_facts_default)`; `Compiler.facts_default()` = the ccall, §1b — the old
build's `facts_default`+`FACTS_IMAGE` pair, old `facts.jl:15-22`, needs no image
save here because the *only* per-CI policy trace M3 keeps is the record bits, and a
package image's code is correct under either setting: G1 needs no declaration.)

- **Why env beats the alternatives (the cost/inertness argument asked for):**
  1. *Uniformity across processes*: package **precompilation runs in child
     processes** which inherit the environment; a `Base.Experimental` toggle is
     in-memory and invisible to them — a session under the toggle would precompile
     its dependencies *plain*, silently splitting the test bed exactly where G2
     claims live (the old build hit this and answered "use a depot of its own" —
     facts §12.2; the env carries both the session and its children).
  2. *P1*: with the env, the policy is a **process constant** ⇒ an MI's policy never
     changes ⇒ "one CI per (MI, policy, flags)" holds with *no* policy in the cache
     identity (the CI cache lookups `jl_rettype_inferred`/`jl_method_compiled_callptr`
     stay untouched). A runtime toggle would force a per-CI policy bit *checked at
     every cache hit* to avoid serving a wrong-policy CI — that is policy forking the
     cache hit-path: the road to a second owner, forbidden by P1. If the coordinator
     wants runtime toggles eventually, the design is a policy bit + hit check — raise
     as its own milestone decision, not here.
  3. *Inertness*: plain = getenv once at first inference; the suites never see the
     env; I3 holds by construction.
  - *`--project`+depot switch*: not a policy mechanism at all (it changes what loads,
    not how inference behaves); it is the recommended *companion* for the G2-count
    gate (own depot so `all` images don't mix with plain ones — facts §12.2 speed
    note, not correctness).
- **The sysimage compiler stays plain automatically**: the build (`make`,
  `basecompiler`/`sys.ji` stages) runs in the build shell without `JULIA_FACTS`;
  belt: `frame_facts` returns false for the Compiler module regardless (§1b), so even
  a mis-set build env cannot facts-compile the compiler; `--compile=min`,
  `--output-ji` bootstrap unaffected (probe on the M2 binary class: gates already run
  the bootstrap; M3 adds the `--output-ji` repro as a gate step like M2 did).
- Gates run "under `all`" = the same script, env set (m2-style: `JULIA_FACTS=1
  julia --startup-file=no --project=oc-traits script.jl`), own depot via the `jl`
  harness or `JULIA_DEPOT_PATH` — the coordinator's harness choice stands.

## 6. `split_call`, `fold_call`, `known_type` — fresh ports (inference halves)

All three are plain Compiler-level functions (identity definitions at run time;
inference folds them). Anchors: hook them in `abstract_call_known`
(`abstractinterpretation.jl:2724`) as new arms *before* `elseif is_return_type(f)`
(`:2850`) — `f === split_call && la >= 5` / `f === fold_call && la >= 2` /
`f === known_type && la == 2` (the old build's chain, old `abstractinterpretation.jl:2811-2817`).
Each arm runs for *every* interpreter (policy or not) — I3 because:
`known_type`'s answer is sound for plain too (a total fold of a property inference
already knows), `fold_call` only folds where *the user calls it* (nobody does in
plain code — zero cost beyond three `f ===` compares on a chain that already runs
~20), and `split_call` without registered candidates is literally the inner call.
Old-build sources and what transfers:

- **`known_type(x) = false`** (old `facts.jl:501`), inference
  `abstract_call_known`-arm → `CallMeta(Const(isdispatchelem(widenslotwrapper(argtypes[2]))),
  Union{}, EFFECTS_TOTAL, NoCallInfo())` when `argtypes[2]` is a `Const`/concrete;
  no fold (unfoldable arg) → `Const(false)` total. GCC's `__builtin_constant_p` for
  types; the I3-inert claim: with no open sets no library *writes* a `known_type`
  call, and the fold never changes a value (both branches compute the same —
  the rule compiler.md §4.1 puts on the *caller*).
- **`fold_call` + `Undecided`/`AtLoad`/`FoldRecord`/`FoldCallInfo`** (old
  `facts.jl:513-527, 542-575`): `abstract_fold_call` gated on
  `interp isa NativeInterpreter && sv isa InferenceState &&
  !iszero(sv.cache_mode & CACHE_MODE_GLOBAL)` (reflection top frame / constprop /
  semi-concrete never fold), every arg a Const, `Core._call_in_world(world, g,
  vals...)`, `nothing`/`Undecided()`/error → NOT_FOLDED (the call stays `nothing`,
  `EFFECTS_TOTAL`), else `Const(r)` + `FoldRecord` edge. `fold_holds(rec, world)`
  re-evaluates `g(AtLoad(), args...)` at load — wired into `verify_method` (§3c arm).
  **Why I3-inert:** no producers in Base; the edge kind teaches images to re-eval a
  fold that cannot exist in plain-loaded code (no FoldRecord edges ⇒ arms never run).
  M3 divergence from old: the fold may fire for **any** frame, plain or policy (the
  old build's gate was "compiled for the global cache" + native interp; the policy
  adds nothing — the *record* machinery is what makes the fold sound across images,
  and M6's declarations are the only user-facing producers before M5).
- **`split_call(K, RT, f, x, args...)` = `f(x, args...)::RT`** (old `facts.jl:490`)
  with `abstract_split_call` (old `facts.jl:746-773`): narrow `x` to
  `typeof(x) ∩ ⋃candidates` (registry `DYNAMIC_CANDIDATES`, copy-on-write IdDict,
  old `facts.jl:577-608`, candidates read **without an edge** — a later candidate
  reaches the fallback and invalidates nothing); when narrowed, the statement types
  `Any` with merged `EFFECTS_RTSITE` (the fallback is a run-time site) and the call's
  info wraps in `SplitCallInfo(info, open=true, RT)` (old `facts.jl:735-743`).
  **M3 scope: the inference half only.** The inliner's isa-branch split + fallback
  (old `ssair/inlining.jl` `ir_inline_unionsplit!`/`split_fallback_table` and the
  C-side table `jl_split_table_ptr`) is **M5** — the guard machinery lands there
  (plan §4.2 guards), and the fallback-table's pointer thunks are exactly M5's boxed
  adapter's neighbors (§4.3 P2). In M3 an *open* split stays the plain dynamic call
  with `Any` + rtsite mark (sound, slow — the split's speed arrives with M5; the
  inference-side facts edges per candidate are built and counted). No `Base` surface:
  scripts write `Base.Compiler.split_call` / marks; M5/M6 bind the library spellings.

## 7. `return_type` stays plain at non-fact signatures

Anchor: `is_return_type` (`Compiler.jl:115`), dispatch arm
`abstractinterpretation.jl:2850-2851`, fold machinery `return_type_tfunc`
(`tfuncs.jl:3140`, nortcall-tainted `UNKNOWN` at `:3141`). The rule (facts §7.1,
compiler.md §1.4), in a wrapper `facts_return_type(interp, argtypes, si, sv)` used
**only when `sv.facts`**:
1. **facts' own answer folds** when it cannot be wider than plain's: `Const`, a
   concrete non-kind type, or `Union{}` — those are exact values, their dispatch
   dependence already carries the frame's fact edges. (Today's fold path inside
   `return_type_tfunc` does exactly this from the frame's inference — M3 keeps it
   *only* under that condition; at non-fact sigs the frame's inference answered `Any`
   (the gate) so nothing wider ever reaches the fold. `Union{}` = the A3 exception.)
2. *(plain-and-facts fold in `PlainRTInterp`, old `facts.jl:339-478`
   `facts_plain_return_type`/`concrete_splits`/`PlainRTInfo`)* — **deferred to M6**
   (§E): with steps 1+3 only, answers stay *plain Julia's* (step 3 runs
   `return_type_interp` = plain inference), so G1.8/G1.9/G1.11's value-equality
   assertions hold; what step 2 buys is the compile-time *fold* (speed), not a
   different answer. Owner note preserved: `PlainRTInterp.cache_owner =
   :facts_plain_return_type` is an owner *token on a never-run cache* — no dispatch
   or codegen ever looks there (facts §1.4) — P1-compatible, but it rides with step 2
   in M6.
3. **otherwise the answer is computed at run time**, and the site is a run-time site:
   return `UNKNOWN`-shaped `CallMeta(Type, Any, Effects(EFFECTS_UNKNOWN; nortcall=false), …)`
   — plus, in a facts frame, the statement's effects merge `EFFECTS_RTSITE` (it is
   an unedged call). At run time `_return_type` runs plain inference in the compiler's
   world (unchanged upstream behavior: `Base._return_type` with no interpreter →
   NativeInterpreter plain; the old build's `return_type_interp` pinning rides with
   step 2).
4. `nortcall` interplay: `is_foldable(…, check_rtcall)` unchanged; a facts frame
   folding `return_type` (step 1) keeps `nortcall` bookkeeping as today.
I3: `sv.facts == false` → `return_type_tfunc` untouched, bit-identical.
Membership angle (the M1–M2 seam): a `return_type` at a *member* signature is F1 —
facts answer folds; its valid_worlds carry M2's entry bound already. `all`-mode note:
`map`/`broadcast` element types on concrete arrays are step-1 folds (dispatch-tuple
queries) — no measurable slowdown expected off the hot paths (facts E1's table).

## 8. The membership edge and the M2 seam

Emission (facts frames, and ONLY under `facts` — the record is the policy's artifact):
at the match loop of `abstract_call_gf_by_type` (`:168` `infercalls`), per applicable
match with `sig` whose unwrapped params contain an open-set name —
`jl_has_open_set(sig)` one bit read (I3) → for each set-named position, look up the
entry that made the match legal and push `MembershipEdge(nothing, entry, sig)`.
The lookup needs a **new ccallable returning the entry** (probe:
`jl_lookup_membership` (`subtype.c:1810`) returns an **Int**, not the entry):

```c
// subtype.c, beside jl_lookup_membership; XX-registered (D6 precedent m2): returns
// the entry object of the membership chain that answers `x ∈ set` at `world`, or
// jl_nothing. chain=1 (composed answers — the fronts' semantics, D-M2-1/2); the TOP
// entry of the chain, per the W2-1 ruling, since consumers read its fields.
JL_DLLEXPORT jl_value_t *jl_membership_entry_for(jl_value_t *x, jl_value_t *set_instance, size_t world);
```

The entry object is the Julia-visible one `jl_declare_membership` already returns
(`oc-traits/src/Traits.jl:24-27` returns it; the M1/M2 gates read `e.min_world` — so
`min_world` is readable; **max_world**: the C entry carries it for re-declared keys
(plan §4.1); if the Julia-visible field list lacks it, extending the entry's field
list is the M1b-authorized surface (`jltypes.c:3051` name list) — flagged as a build
detail, not a D, since a missing field only weakens `membership_edge_holds` to the
min-world half). `cell` is `nothing` in M3: **membership cells are M5's** (plan §4.2:
cells are created by the compiler *with the guard machinery*); the field is reserved
so M5 fills a kind that is already taught everywhere (§3c). "Folded positives"
arrive with M6's fold raise (§0.4) — same kind, `cell`/`sig`/`entry` filled;
`positive_fold_blocked` is then deleted or narrowed (M6's decision, not M3's).
`membership_edge_holds(edge, world)` (reinfer arm, §3c) = the entry is a live
membership at `world` at `sig` — implemented by `jl_membership_entry_for(sig-type…,
…, world) === edge.entry || jl_membership_holds_at(sigelem, set, world)` — reusing
`jl_membership_holds_at` (`subtype.c:1475`, verified). G2 treats the edge as
free-riding (§4a): the CI's own `min_world` already carries M2's bound; the edge is
the *witness*, consumed by M4's sentinel revalidation ("compare the callee's current
result / entry against the edge") and M6's activation.
**P1 line:** the edge is data; the entry lookup is a read of M2's structures; no
world is re-decided here.

## 9. Image load, deletion and binding hooks — what M3 actually builds

Summary of §3c/§4b with the honest remainders (plan letter: "`gf.c`/`staticdata_utils.c`
(definition/image/deletion/binding hooks; `verify_method` learning the record's new
kinds)"):
- **`verify_method` learning the kinds** — delivered (§3c item 2; `reinfer.jl` is the
  1.13 home of `verify_method`, the old build same: `old reinfer.jl:242-247`;
  `staticdata_utils.c` itself needs **no** kind knowledge — its CI touchpoint
  (`:913-918` world stamping, the "max_world is not updated until edges are verified"
  note) is kind-blind).
- **Image load** — flags mask hunk (`staticdata.c:1773`), kind-transparent
  serialization (no change), strip path (`:2603`) already safe, `effects_foldable`
  (`:552`) unaffected (bit 15 read nowhere).
- **Definition hooks** — M6 (no_pirates refusal needs the pre-definition hook;
  this tree has none; the old build's piece 1 is the reference, and plan §4.6 names
  the hooks for M6). M3 leaves `g2_edges`/`ci_is_g2` as the query strict mode will
  filter through.
- **Deletion hooks** — none needed in M3 (§3c item 4); M4's revalidation and M6's
  strict mode are the consumers that will *want* them (`Base.delete_method` →
  `jl_method_table_disable` invalidates via code edges exactly as today).
- **Binding invalidation** — the `Core.Binding` machinery is the existing record of
  "bindings as they are" (plan §4.4's clause): binding pairs ride unchanged;
  `maybe_add_binding_backedge!` (`typeinfer.jl:755-759`) untouched. The cross-module
  `Core.eval(Other, …)` hole stays facts §2.2's named exception (M6 strict design).

## 10. D-M2-7 tightening — dominance in the ambiguity report (`src/gf.c` §8)

The named M3 candidate (notes 2026-10-31; deviations D-M2-7: "M3+: suppress when the
sorted match list at the member has a dominating (`FULLY_COVERS`) head — compare
dispatch's outcome, not the raw `ambig` flag"). Anchor (`src/gf.c:6205-6206`, the
report's concrete-member branch):

```c
                                if (!(jl_membership_holds_at((jl_value_t*)qn->wrapper, X, entry_min_world) ||
                                      jl_membership_holds_at((jl_value_t*)qn->wrapper, Y, entry_min_world)))
```

Hunk (inside `jl_membership_ambiguity_report`'s concrete-branch, after the
`ml_matches(…, lim=-1, incl_ambig=1, …)` query that sets `ambig` — the §8 pins
(`cache_result=0`, `world=entry_min_world`) hold unchanged):

```c
    if (ambig) {
        // D-M2-7: dispatch resolves by dominance — ask dispatch's own question at the
        // member: a single, fully-covering winner means the call is NOT ambiguous at
        // runtime, and the warning is over-report. World/cache pins as the -1 query.
        size_t lo2, hi2;
        jl_value_t *dm = ml_matches(mt, mc, member_sig_query, /*lim*/1, /*incl_ambig*/0,
                                     /*intersections*/1, entry_min_world, /*cache_result*/0, &lo2, &hi2, &ambig2);
        if (dm && jl_array_nrows(dm) == 1 && ((jl_method_match_t*)jl_array_ptr_ref(dm, 0))->fully_covers)
            ambig = 0; // one dominating winner: dispatch has a single answer at the member
    }
```

(The member_sig_query = the same query the -1 query used; `ml_matches` here runs
inside the §7/§8 throw-free region — `lim=1` allocates no more than the -1 call did,
cache_result=0 keeps the M2 pin against `cache_method` side effects, gf.c:1888-1903
rationale unchanged.) Fixed-vs-Vararg pair `kd(::VC2)` vs `kd(::Vararg{VC3})` then
suppresses (deviations D-M2-7 row retires); the set-in-set suppression path stays as
built in M2. Gates: `m2_ambiguity_report` must stay green *and* gain the new
negative case (a fixed-vs-Vararg pair must warn **zero** times now — the M2 gate
kept "one warning" for the X/Y shape; the D-M2-7 shape is added, not replaced).
I3: unreachable without open sets (the report only runs from `jl_declare_membership`).

## A. Files touched

| File | Why |
|---|---|
| `julia-oc/Compiler/src/facts.jl` *(new)* | §1 criterion + gate helper + marks, §3 record kinds, §4 `g2_edges`, §6 primitives, §7 `facts_return_type` wrapper |
| `julia-oc/Compiler/src/Compiler.jl` | `include("facts.jl")` after `tfuncs.jl` (:185/:187); `reinfer.jl` import of the record kinds (:197's `ReinferUtils` include unchanged — the `using ..Compiler:` line inside reinfer.jl grows) |
| `julia-oc/Compiler/src/effects.jl` | §2 nortsite (struct :119/:128/:138, kw ctor :182/:192, `EFFECTS_RTSITE` :180, `is_better_effects` :205, `merge_effects` :275/:285, accessors :305, encode :339, decode :351) |
| `julia-oc/Compiler/src/abstractinterpretation.jl` | §1 gate arg + rtsite arms (:132, :130/:135/:147/:157, invoke :2346/:2350/:2352/:2361/:2362/:2368), §3b result-edge push (`handle1`), §6 known_type/fold_call/split_call arms (:2850 chain), §2 merge_override_effects! (:3631), MethodCallResult.facts (:854) |
| `julia-oc/Compiler/src/inferencestate.jl` | `facts::Bool` on InferenceState (:262 struct, ctor :322/:599), `frame_facts` (+ marks accessors) |
| `julia-oc/Compiler/src/types.jl` | `NativeInterpreter.facts` default field (:380/:389) |
| `julia-oc/Compiler/src/typeinfer.jl` | §3c iterator skip (:716-751), §4b G2 mark at `finish!` (:104/:162-167), `codeinst_as_edge` (:1009), layout census (§3b, `finish!`), §4c NotFullyTypedError hook |
| `julia-oc/Compiler/src/abstractinterpretation.jl` §7 | `facts_return_type` wrapper call at :2850 |
| `julia-oc/Compiler/src/tfuncs.jl` | (none in M3 — §7 lives at the call arm; step 2's `return_type_tfunc` surgery is M6) |
| `julia-oc/Compiler/src/ssair/inlining.jl` | §3b `InlineIdentity` push at the inline-edge sites (:856/:895 neighborhoods) |
| `julia-oc/Compiler/src/reinfer.jl` | §3c verify arms (:217-287 loop, :293-315 child search), `CI_FLAGS_G2` (:9) |
| `julia-oc/src/julia.h` | `JL_CI_FLAGS_G2` (:449-450 area), purity-word comment (:479 block) |
| `julia-oc/src/gf.c` | `jl_facts_default`, `jl_ci_set_g2`, `jl_membership_entry_for` (§8 — subtype.c actually: see next row), §10 dominance hunk (:6205 area) |
| `julia-oc/src/subtype.c` | `jl_membership_entry_for` (beside :1810; entry = top-of-chain, W2-1 rule) |
| `julia-oc/src/staticdata.c` | flags keep-mask (:1773) |
| `julia-oc/src/jl_exported_funcs.inc` | `XX(jl_facts_default)`, `XX(jl_ci_set_g2)`, `XX(jl_membership_entry_for)` (the generated `.inc` regenerates; notes build fact #2) |
| `oc-traits/test/acceptance/*` *(new)* | the AC scripts (coordinator writes; §C names them) |
| `oc-traits/gates/m3_*.jl` *(new)* | the mechanism gates (coordinator writes) |
| `base/experimental.jl` | optional 5-line shim `mark_facts!`→`Base.Compiler.mark_facts!` (skip if D2/D3 come out differently) |

Not touched: `jl_code_instance_t`/`jl_method_t`/`jl_typename_t` layouts (**none** —
the G2 bit is *inside* the existing uint8 flags word; the `concrete_only`-style new
words are M6/D2 territory), `jl_datatype_t` self-description, `boot.jl`,
`typemap.c`/`method.c`, `codegen.cpp` (no effect-bit reads there; §2 audit),
`test/*` (tripwire untouched — if `test/core.jl:47` goes red, a layout changed
accidentally and the §B purge ritual applies, which would be a bug in the authoring).

## B. Build & test checklist

1. Per-file analysis for the three C files: `make -C julia-oc/src analyze-gf analyze-subtype analyze-staticdata --output-sync -j8`
   (+ `clang-sagc-*`). `jl_membership_entry_for` returns a rooted value — JL_GC root
   the walk's locals per the M2 GC-lesson (the round-2 F1 class: check analyzer, not
   habit).
2. `oc-build.sh` full build (exclusive slot, pgrep-first). No image wipe expected
   (no layout change); if `test/core.jl:47` fires, stop — §A's rule was violated.
3. Plain battery: 22 existing gates; `make test-subtype test-core test-ambiguous`
   one invocation, wall vs control (M0 2:03.36 / M2 1:40.87) ±10 %, exit 0
   (I3: this run must be **bit-identical behavior**; a diff of the logs is the
   strongest cheap check).
4. `all` battery: `JULIA_FACTS=1` run of every gate (§AC-25) + the suites a *second*
   time are NOT required at the gate (expensive); the `all` acceptance suite covers it.
5. `--output-ji` bootstrap repro (M2's checklist item — the class of defect that bit
   W2-F1): clean cwd, boot.jl-relative caveat as before.
6. Fresh-depot precompile round trip (§AC-18): `JULIA_FACTS=1 julia --project=<tmp>
   -e 'import Pkg; Pkg.precompile()'` then a plain-session load of the same depot —
   exercises reinfer + the flags mask both directions.
7. `make fix-whitespace` before commit; commit per AGENTS.md ("compiler: …", "facts: …").

## C. Gates — coverage of every §4.4 rule; the AC table

Two artifacts, coordinator-authored: `oc-traits/test/acceptance/AC_*.jl` (G1
acceptance, rewritten for the new library — **marks, not TraitWorld entries**; each
AC script runs its body twice: plain session with policy marks, and the same body
under `JULIA_FACTS=1`; the assertion is *policy value == plain value* or a named
raise, per the old suite's phrasing style) and `oc-traits/gates/m3_*.jl` (mechanism
pins). The old suite (`experiments/facts/acceptance_compiler.jl`, 35 checks,
35/35 in the record) is the case source; per-case disposition below (deferrals carry
the *why* — the old scripts lean on owner/split-table/registry machinery this build
deliberately does not have).

### Gate coverage (acceptance, M3-scope)

| # | old case | pins (plain-vs-`all` both: expected identical) |
|---|---|---|
| AC-1 | G1.1, G1.2, G1.4, G1.6 | marked caller + redefinition by owner / of a helper / winning pirate / later more-specific method: policy value == plain value before and after (policy never *protects* wrongly — G1) |
| AC-2 | G1.5 | marked code calling Base/LinearAlgebra/Printf (`det`, `@printf`) — identical values; CIs carry fact dispatch edges at concrete splits (`all_cis` + edge-kinds probe) |
| AC-3 | G1.7, G1.12 | recursion through marked entries, incl. growing types: terminates, values == plain (also the D7 conservative-G2 check — record but do not pin the bit) |
| AC-4 | G1.8 | `return_type` at an abstract-typed query (empty `map` eltype) inside marked code: `typeof` == plain's (§7 steps 1/3) |
| AC-5 | G1.9 | `return_type` follows a redefinition (policy answer moves when plain's moves) |
| AC-6 | G1.11 | `return_type` at widened compilation signatures == plain's |
| AC-7 | G1.10 | method-level `@assume_effects :foldable` over a run-time site follows a redefinition (nortsite withdraws the assertion) |
| AC-8 | G1.19 | a *Base* method asserted `:foldable` over a run-time site reached from marked code does not freeze the dispatch |
| AC-9 | G1.32 | an assertion one frame above a run-time site does not fold over it |
| AC-10 | G1.33 | an assertion over a too-many-matching-methods call does not fold (the fact-gate FailedMatch + nortsite) |
| AC-11 | G1.14 | `invoke_in_world` at an old world in marked code does not see a later definition (policy CI world bounds — same as plain; M2's machinery + facts edges coexist) |
| AC-12 | G1.15 | a cycle's callee redefined deep inside invalidates the marked caller (code edges through cycles unchanged in M3) |
| AC-13 | G1.31 *(criterion half)* | tuple-argument union split by Julia's cost (1-of-8 splits; 2×3-of-3 does not; 2×2-of-2 does): splits get per-split `(sig, CI)` fact edges; the non-split case is a run-time site (edge count 0, rettype `Any`, nortsite false). *The old script's split-table asserts ride with M5's candidates/tables* |
| AC-14 | G1.34 | narrow-after-wide MI keeps its own sparams (mechanism regression in marked code) |
| AC-15 | G2.1 | an unrelated module extends a function called on type values (`make(::DataType)` form): marked CI's `max_world == typemax(UInt)` (the kind-not-fact ⇒ run-time site ⇒ nothing to invalidate) |
| AC-15b | new | the run-time-site shape (facts §4.2/§5): abstract call in marked code ⇒ stmt `Any`, **zero** dispatch edges at that stmt's sig, effects nortsite false, a later method is followed *without recompilation* (`max_world` unchanged, value moves) — the G2 property at unit scale |
| AC-16 | new | `concrete` enforcement: marked `concrete` + a run-time site ⇒ `NotFullyTypedError` from `code_typed`; unmarked ⇒ compiles; marked + fully typed ⇒ compiles (§4c; D8's blessing) |
| AC-17 | new | compiler-always-plain (facts §6.4): `mark_facts!` on a Compiler function is refused/ignored; after an `all` workload, every CI of a sampled Compiler function has `decode_effects(ci.ipo_purity_bits).nortsite == true` (plain never clears it) — the differential pin |
| AC-18 | new | membership seam (§8, M2 interaction): compile marked caller at a member *after* `@implement` (uses §0's query-world override), pin the dispatch edge at the concrete member sig, `ci.min_world ≥ entry.min_world`, and a `MembershipEdge` present carrying that entry; non-member abstract query ⇒ run-time site |
| AC-19 | G1.35 *(half)* | `JULIA_FACTS=1` process boots, runs the acceptance prelude, and `detect_ambiguities(Base)` is unchanged (`all` must not perturb *plain-visible* surfaces outside the policy) |

### Mechanism gates (`oc-traits/gates/`, coordinator scripts)

| script | pins |
|---|---|
| `m3_policy_sites.jl` | §1c: for a marked caller, each un-inferred non-fact call records *no* `(sig, mi)` pair (walk `ci.edges` kinds per stmt sig) and rettype `Any`; each fact call records its pair; remarks appear (`code_typed(...).remarks`-style) naming the facts bail; `is_fact_sig` table check (F1–F4 forms × the §3 examples, incl. closure-at-kinds and `vararg_fact`, `Keyed` ⇒ false) |
| `m3_rtsite_effects.jl` | §2: `EFFECTS_RTSITE` merges and propagates through nested calls (3-deep chain, nortsite false at the root), plain frames never clear it; `decode_effects(encode_effects(e))` round-trips bit 15 both ways; a C created via the user-src path reads nortsite true |
| `m3_record_kinds.jl` | §3: a marked function that inlines one callee, emits one call, reads one field, folds one `fold_call` → its `edges` contain `InlineIdentity`, `ResultEdge`, `LayoutIdentity`, `FoldRecord` respectively, and *no backedge registrations broke* (plain invalidation control: redefining the inlined callee still invalidates the caller; redefining the emitted callee invalidates in M3 — §3b's classification-not-replacement note) |
| `m3_fold_known.jl` | §6: `fold_call` folds in a compiled global-cache frame (value + `FoldRecord`), returns `nothing` in the interpreter (`fold_call(g) === nothing` at the prompt), `Undecided()` doesn't fold; `known_type` true/false fold; `split_call` with zero candidates == the call; with candidates registered (`Compiler.register_dynamic_candidate!`), narrowing + `Any` + rtsite (no fallback table yet — M5) |
| `m3_g2_bit.jl` | §4: fact-only policy CI ⇒ `flags & 0b10000` set; a CI with a non-fact *speculative dispatch edge* (plain frame, e.g. marked-off abstract call with a matched method) ⇒ bit unset; `all`-mode: bit set on sampled Base CIs compiled under the policy; loaded-from-image CI keeps the bit (fresh-depot precompile round trip — pairs with `m3_image_roundtrip`) |
| `m3_image_roundtrip.jl` | §3c/§9: fresh depot; precompile a package under `JULIA_FACTS=1` whose init-path code inlines + emits + folds (fold value stable across sessions — no pointers); load in a fresh process (plain and under `all`): the package's CIs verify (`max_world == typemax`), fold re-evaluated and held; then a package whose fold *changes* between build and load (env-seeded constant) ⇒ that CI discarded and recompiled (the `fold_holds`-false path — old build's C-14 lesson class) |
| `m3_ambiguity_dominance.jl` | §10: `kd(::VC2)` + `kd(::Vararg{VC3})` + member of both ⇒ **no** warning (was: over-warn, D-M2-7), runtime resolves `:vc2`; `m2_ambiguity_report`'s cases unchanged (regression) |
| `m3_all_gauntlet.jl` | AC-19 + runs every `m1_*`/`m2_*` gate under `JULIA_FACTS=1` (subprocess loop, per-gate env) — the policy is inert on the M1/M2 surface |

**G2-count script (shape, per §5.M3's gate and the g2all bands):**
`m3_g2_counts.jl` under `JULIA_FACTS=1`, own depot: (work A) a scripted trait
session — `@trait Col` + one `@implement`, bounded methods at members (M2 shapes),
LinearAlgebra `det`/`lu`, `map`/`broadcast`/`sort` on concrete arrays, a marked
`colmean`-style worker; **count**: walk `Base.specializations` over a fixed module
list, total CIs, `g2`-bit count, nortsite-clear count (report). (work B) a churn
storm *in-session* — a module defining 100 types + Base methods + 20 redefinitions
+ loser pirates (ChurnStorm's shape from the g2all rows) — then more work A;
**assert**: G2-bit CIs lost to *non-stakeholder* definitions == 0 (old product-setting
rows: **0 of 12,368–15,030** across ten loads, E-28/E-29 in
`writeup/record/experiments.md:72-73`; `all`-row: 12 of 68,162, all a stakeholder's
`Base._cat` change — an allowed-class loss); any loss must attribute to a stakeholder
redefinition section (pin the attribution by checking the invalidation log
`_jl_debug_method_invalidation`). Ballpark for G2-bit *share*: the old facts-owner
code was ~100 % G2-clean by construction; ours should read ≥ 99 % on this session —
absolute counts differ (old sessions were stack-sized; this script is small),
ratios are the band, per the coordinator's instruction. Rows into `numbers.md`
with the build commit.

**Base suites (plain):** §B step 3 — bit-identical behavior to control is the I3
gate (wall within ±10 % of the M2 row 1:40.87; the −18 % M2 improvement may drift
back a little; the bound, not the delta, is the gate).

## D. Why each gate passes (argument, abbreviated per family)

- **AC-1…AC-6 / AC-15b (G1 family):** under `facts`, dispatch-tuple calls are
  resolved and edged exactly as plain (F1 ⇒ the gate admits them to today's path —
  the inference at a dispatch tuple is *identical* code), so values match plain by
  construction; non-fact calls get no result type, so codegen emits today's dynamic
  dispatch, which is plain Julia's — "or raises" covers MethodError parity
  (run-time sites raise the MethodError plain raises, in the caller's world: the
  world age at entry is upstream's). Redefinitions follow because upstream
  invalidation on the recorded fact edges is exact at concrete signatures (the
  wrapping-by-facts E3: exact in all nine cases) and the record skips nothing (P).
- **AC-7…AC-10 (assertion family):** `nortsite` is merged IPO-wide (§2), and the
  two readers consult it before any override applies — a fold over an unrecorded
  dispatch becomes impossible: any frame whose reach contains a run-time site keeps
  its asserted effects unused (`adjust_effects` wrapper +
  `merge_override_effects!`). Values then track redefinitions by AC-1's argument.
- **AC-11/AC-12 (worlds/cycles):** unchanged mechanisms (M2's bounds + upstream
  cycle invalidation); the ACs are regression shields against the new edges leaking
  into `store_backedges` (§3c's skip means *no new backedge registrations* —
  `m3_record_kinds` asserts this).
- **AC-13:** F2's cost model *is* `unionsplitcost`/`max_union_splitting` — the split
  set equals Julia's own splitting, so "1 of 8 yes / two of three no / two of two
  yes" holds by the same arithmetic `switchtupleunion` uses.
- **AC-16:** the throw is a direct reading of two bits M3 computes; `concrete` marks
  are the only trigger.
- **AC-17:** plain inference has no site that clears nortsite (§2: `unedged_effects`
  answers `Effects()`; the split/fold/RT clears are `facts`-gated) and
  `frame_facts` refuses the Compiler module.
- **AC-18:** M2 §6 raised `matches.valid_worlds` through `update_valid_age!` already
  (HEAD code path, unchanged); the membership edge is emitted from the same match
  loop reading the same entry (§8's `jl_membership_entry_for`, top-of-chain per W2-1).
- **`m3_image_roundtrip`:** edges serialize kind-transparently (probe + §3 audit:
  three defensive C readers, generic writer); `verify_method`'s new arms keep
  conservative verdicts; the flags mask (`staticdata.c:1773`) carries the G2 bit.
- **Base suites + `detect_ambiguities` inert:** every §1–§8 hunk is behind
  `sv.facts` / `item isa` (never true for old records) / a new bit read defaulting
  false / a struct never constructed by plain code; `JULIA_FACTS` unset ⇒
  `facts_default()==0` ⇒ `frame_facts()==false` for unmarked code ⇒ line-for-line
  today's tree.
- **`m3_ambiguity_dominance`:** dispatch resolves by dominance (sorted winner), and
  the `lim=1, incl_ambig=0` query *is* dispatch's question at the member;
  `fully_covers` head ⇒ a single runtime answer ⇒ the raw `ambig` pair flag was the
  over-report (D-M2-7's exact wording).

## E. Deferrals (honest, each with its milestone)

| deferred | why / unlock |
|---|---|
| `return_type` **step 2** (the `PlainRTInterp` fold + `PlainRTInfo` + `rests_on_facts` reuse), the runtime `return_type_interp` pinning | speed, not answers (§7: steps 1+3 keep answers plain's); rides with M6's declaration surface (the fold's *users* are trait images) |
| `split_call` inliner split + fallback + the C split table (`jl_split_table_ptr` family) + candidate registration ordering pins | M5 (the guard machinery + boxed adapter land adjacent; old build's table = reference, incl. its C-3/C-14 deviations) |
| Membership **cells** (the `MembershipEdge.cell` field) and guard emission | M5 (plan §4.2: cells are created *by the compiler with the shadow query*) |
| Membership **folded positives** (deleting/narrowing `positive_fold_blocked`, the min_world raise on folds) | M6 (the named "positive-fold decision" — D-M2-1's closing row) |
| Module/method/block `facts` **declaration surface**, image persistence of marks, the `no_pirates` definition/load hooks, the symmetric lint | M6 (plan §4.6; needs a Module word → the layout decision is M6's, D2-shaped) |
| Code slot + result-edge **revalidation** (consuming `ResultEdge` instead of invalidating) | M4 (plan §4.5, exactly) |
| G2 SCC-aware second pass for inlined cycle partners | refinement (D7; conservative false is sound meanwhile) |
| `WITHDRAWN_LOG` (the old W-57 assertion-withdrawal census tool) | optional; rebuild in M7 with the workloads if wanted |
| `--trim`/`verify_main` under the policy | out of scope (plan §0), M6+ at most |
| ChurnStorm-scale load sequences (real package loads) | M7's workloads (the M3 count is the in-script emulation) |
| `Keyed` fact form (if M5 rules erased-key facts) | M5 (`is_fact_sig` extension point, §1a) |
| Old G1.3/G1.13 (conformance defaults/predicate), G1.17/G1.18, G1.20–G1.26, G1.27–G1.30, G1.35's `--compile=min` half | acceptance disposition table below (§C deferrals) |

**Acceptance deferral sub-table** (old case → unlock; why not M3-scope):

| old | unlock | reason |
|---|---|---|
| G1.3 | M6 | conformance *defaults* are lowering/contract machinery (the "field default" is TraitWorld's; ours is M6's contract tables) |
| G1.13 | M6 | generic-conformance *predicate* needs `@implement`'s contract decision |
| G1.16 | — | retired (no case; facts.md:132) |
| G1.17, G1.18 | M5 | `Dynamic` values at split call sites — needs split inlining + candidates |
| G1.20, G1.21 | M5/M6 | `Dynamic` Callable + `:caller_world` thunk worlds (Callable is plan M5's, the `:caller_world` patch is M5/M6's) |
| G1.22, G1.23 | M5 | the old build's per-call-site dispatch caches at run-time sites (mechanism 3) — upstream caches answer M3's need; the old caches return with the guards |
| G1.24, G1.25, G1.26 | M5 | the split table of call targets, `compiled_for` — table machinery |
| G1.27–G1.30 | M5 | cross-mode constprop/concrete-eval checks were owner-design artifacts; in the single-cache design they reduce to value-equality regressions, re-derived when keyed types make cross-mode calls interesting (and already partially covered by AC-1/AC-3) |
| G1.31 (split-table half) | M5 | §C AC-13 note — criterion half M3-scope |
| G1.35 (`--compile=min` facts image) | M6 | the image-default save (`FACTS_IMAGE` analogue) is M6 with the declaration surface |

## F. Old build ≠ this build (every divergence a reader might trip on)

| old (`trait-world-1.13`) | this build (M3) |
|---|---|
| `FACTS_OWNER` / `interp.owner` / `jl_code_owner` / `leaves_to` / `facts_edge` / `facts_const_call` / `interp_for_owner` / `jl_apply_generic_facts` / owner-qualified lookups (`jl_method_compiled_callptr_owner`) | **not ported** (P1 forbids the second owner). Policy is per-frame (§1b); cross-mode constprop/concrete-eval need no plumbing — a callee frame gets its policy from its own def, one cache serves all |
| `facts_mode(interp)` everywhere | `sv.facts` per frame (the key is the caller's method — plan §4.4's "keyed by the caller's method", review L3's shape; `concrete_only` (`inferencestate.jl:1127`) remains the *callee*-keyed precedent we do NOT re-key) |
| `facts_default` + `FACTS_IMAGE` + `jl_compile_by_facts` (1/0/2 tri-state) + the facts sysimage story | `jl_facts_default()` = env, two-state, no image save (§5); the facts-image is an M6 consideration |
| `@compiler_options facts=true` module option, `Expr(:meta, :facts_boundary/:facts_always)`, boundary methods | not in M3 (M6 binds marks; boundary methods are moot with no owner — §4.4's table row "entries are boundaries" dissolves) |
| `StrictMode`'s `_winning_fact` walk + definition hook (pieces 1/14/15) | M6; M3 ships `g2_edges`/`ci_is_g2` as the predicate half (§4c) |
| G2 was an *empirical* claim measured by `g2all` (no per-CI bit) | the G2 **bit is new to this build** (plan §4.4) — `rests_on_facts` is its seed, `flags&0b10000` its store |
| `PlainRTInterp`/`return_type_interp`/`facts_plain_return_type` | deferred (E); runtime `return_type` stays today's `_return_type` |
| `split_call` full machinery (inliner split, tables, `_SplitTarget`) | inference half only (§6) |
| `FoldRecord` + `fold_holds` at `old reinfer.jl:242-247` | ported near-verbatim (§3c) |
| old `is_fact_sig`/`unedged_effects`/`EFFECTS_RTSITE`/gate inside `find_method_matches` (`old:368`) | ported; the gate takes the frame's flag, not the interp's |
| the old split tables' `:caller_world` thunks, dispatch profiler (`JULIA_FACTS_DISPATCH_PROFILE`), `register_type_printer`, field-offset intrinsics | untouched / not-ported — adjacent milestones' territory (M5/M6), listed so the author doesn't "helpfully" port them |

## R. Coordinator amendments (plan review round 1) — BINDING, override the text above

The two plan reviews (A = Compiler-side, B = C-side + acceptance, 2026-10-31,
reports at `/tmp/opencode/m3plan{A,B}.md`) and the coordinator's rulings on §G.
Where this section contradicts the sections above, THIS is what gets built.

**R-0. The §G rulings.**

- **D1 — ADOPT.** F4 as written (generated-name closures including lowering's
  keyword-sorter bodies; its G2 clause is facts §3's own stated assumption). The
  `Keyed`-position ⇒ run-time-site rule stands (B §5: `Keyed` is abstract here —
  the fronts answer keyed membership from entry tables, exactly what a run-time
  site encodes; `Dynamic`/`Compiled`/`Kept` are concrete and stay outside the
  rule, correct-by-construction).
- **D2 — BLESS the session `IdDict`s** with R-2's fallthrough fix. No C table,
  no method bit. Gates reach the marks as `Compiler.mark_facts!` (R-9);
  `base/experimental.jl` drops out of §A (M6's surface).
- **D3 — BLESS env `JULIA_FACTS=1`**, name as written (greenfield spelling; the
  old tri-state name would lie). Amendment: comment the lazy `int` cache as a
  benign idempotent race; no relaxed-ordering machinery needed. Tree precedent
  for the process-cached getenv exists (`JULIA_MEMBERSHIP_LOG`, gf.c:2355).
- **D4 — BLESS `JL_CI_FLAGS_G2 = 0b00010000`** and the `staticdata.c:1773`
  keep-mask extension (`&= (JL_CI_FLAGS_NATIVE_CACHE_VALID | JL_CI_FLAGS_G2)`).
  Writer audit clean both reviews (no equality-comparers; destructive stores on
  fresh CIs only; probe `flags == 0b1011`). The mask preserves a bit plain code
  never sets ⇒ plain images byte-identical.
- **D5 — BLESS struct wrappers + the identity-keeping references, CARVE-OUT per
  R-7:** what serializes sanely today is {ResultEdge, InlineIdentity,
  LayoutIdentity, FoldRecord}. `MembershipEdge` keeps its kind (consumers are
  taught once) but its *image semantics* (entry-world re-stamping, activation)
  are M6's — stated, not silently dodged.
- **D6 — the real digest now**, sharpened: `hash == 0` is the reserved
  "no-hash" sentinel and `verify_method`'s arm passes on it; the digest is a
  structural walk of the uncompressed CodeInfo (`:code`, `codelocs`,
  ssatype-count; skip `slotnames`), session-cached `IdDict{Method,UInt64}`,
  re-verified once per Method at load. Acceptance condition: `m3_image_roundtrip`
  shows **zero digest-caused CI discards**; if it fails at author time, the
  pre-blessed fallback is the sentinel (one-line demotion) + a deviations row —
  decided by the gate, not by argument.
- **D7 — ACCEPT conservative-false** for M3; second pass deferred (§E row stays,
  retargeted M7). R-8 fixes the ordering parenthetical.
- **D8 — BLESS the raise** under `concrete` marks only (never under `all` or
  plain marks). Documented consequence (A-F16/D8): a throw inside a cycle's
  `finish_cycle` aborts that cycle's whole completion — acceptable: it fires
  before `cache_result!`, nothing half-caches; the error names the first
  untyped call's line.
- **D9 — bands approved as RATIOS** (≥99 % G2-bit share on the scripted session;
  0 non-stakeholder losses, attribution via `_jl_debug_method_invalidation`);
  absolute counts differ from E-28/E-29 and are reported, not pinned. The `all`
  gauntlet runs at **every** verification run — measured: the 22-gate battery
  wall is 6.7 s.
- **D10 — REFUSE** (B-F6; tree-verified + coordinator probe): `max_world` is
  already exposed on the entry (`jltypes.c:3882-3885`, the 8-name list
  `set, member, instance, key, min_world, max_world, declarer, by`). §8's
  conditional field-extension text and this D10 item are **deleted**; the
  `jltypes.c:3051` cite (the TypeName list) is retracted. No tripwire.

**R-1 (§6, §A — A-F1, wrong-value class).** `ssair/inlining.jl` gains the fold
MATERIALIZATION arm beside the plan's InlineIdentity pushes: when
`inst[:info] isa FoldCallInfo && rt isa Const`, replace the statement with
`quoted(rt.val)` (port of old `inlining.jl:1373-1378`). Without it, compiled
code evaluates the `fold_call` runtime definition to `nothing` exactly where
inference proved `Const(r)`. §A's `ssair/inlining.jl` row grows accordingly;
`m3_fold_known`'s compiled-frame value pin is the acceptance test.

**R-2 (§1b — A-F9).** `frame_facts` must consult the marks for Module defs
(top-level thunks) before falling through to `facts_default()`:
`haskey(FACTS_MARKS, def)` checked for both Method and Module; a thunk under a
marked Module (or `all`) is a facts frame — intended, and the reason AC-17
samples Compiler *method* CIs (R-12).

**R-3 (§6 — A-F3).** `known_type`'s fold is `Const(isdispatchelem(widenconst(argtypes[2])))`
— `widenconst`, not `widenslotwrapper` (the latter leaves `Const(x)` wrapped and
the fold inverts to `Const(false)` for the main case).

**R-4 (§6 — A-F2).** M3's `SplitCallInfo` does **not** delegate
`nsplit`/`getsplit` (return `nothing` ⇒ no split-inlining). The old base
statement rewrite (`old inlining.jl:1387-1393`) is M5's, with the split table —
state it in §6/§E; `m3_fold_known` registers candidates in a plain session and
the inliner must see the inert shape.

**R-5 (anchor batch — A-F4/F15, region-correct drifts).**
`NativeInterpreter` ctor = `types.jl:396`, the positional `return
NativeInterpreter(world, method_table, inf_cache, codegen, inf_params,
opt_params)` at **:411** must grow the `facts` argument (§A's ":380/:389" row
fixes to ":380/:396/:411"); top-level refusal return :158; `abstract_applicable`
tfuncs.jl:3220; inner `InferenceState` ctor :321; `merge_override_effects!`
starts :3630 (wrap target :3635); `effects_foldable` masks at
`staticdata.c:555-558`; flags field `julia.h:498-501`; reinfer else-arm :256;
§7 step-2's old-cite range splits — `rests_on_facts` (old facts.jl:414-449) is
NOT deferred (it is §4a's seed).

**R-6 (§3 — B-F1).** The consumer list is **not** "the three C readers":
`ci_has_binding_edge` (`codegen.cpp:3339-3353`) is a third content loop — safe
by pointer identity against a `jl_binding_t*` (no code change), but it is listed
and annotated. Whole-svec movers join the table: `gf.c:4368-4373` (wider-MI
compile copy — see R-8's twin clause) and `ircode.c:1128` (uncompress seeds
CodeInfo edges; covered by the iterator skip).

**R-7 (§9, §E, §C — B-F7).** Add §9's honest remainder: membership entries live
in the TypeName's `memberships` list and **do serialize** with build-session
`min_world`; load activation (`jl_activate_methods`) has **no membership arm**,
so `MembershipEdge` verification in a loaded image compares a build-session
world against the loader's counter with no ordering guarantee — failures discard
and recompile (sound, slow, and NOT yet exercised). §E gains:
"membership entries/edges in package images (world re-stamping, activation) →
**M6**". `m3_image_roundtrip` states its membership-edge exclusion explicitly.

**R-8 (§4a/§4b — A-F5/F6, B-F9, and B-F2 for §3c).** §4a's cycle note:
`finish_cycle` finishes **parent-first** (loops `cycleid:length(frames)`,
`typeinfer.jl:251-300`) — the conservative-false conclusion stands for the
opposite stated reason. Add the one-line argument that (Type, MI) pair-callees
have no G2 bit to read (MI is never inlined — inlining needs a CI — so the
arm's head `is_fact_sig` check is the whole job); CI pair-callees read the bit.
§4b: the wider-MI compile copy (`gf.c:4368-4373`) does not carry the bit to the
twin — marker-only, one clause, may shave sample counts. §3c.2 restructure
(B-F2): the sketched `verify_child(edge.ci, ...)` call does not exist — the
ResultEdge child enters through the `:recursive_phase` search
(`reinfer.jl:293-315`, the `edge isa CodeInstance` arm at :301 also accepting
`edge isa ResultEdge`, pushing `VerifyMethodInitialState(edge.ci)`); the
non-CI arm is neutral (`min_valid2 = minworld; max_valid2 = maxworld`) and the
existing child-merge at `:return_to_parent` carries the verdict.

**R-9 (§A, R-0/D2).** Marks API: `facts.jl` defines `mark_facts!`,
`mark_concrete!`, `is_fact_sig` in the `Compiler` module (not exported); the
gates/acceptance reach them as `Compiler.mark_facts!` etc.
`base/experimental.jl` row: removed (M6). §A row `gf.c` drops the
`jl_membership_entry_for` mention (it is a subtype.c entry only).

**R-10 (§10 — B-F4/F5).** The dominance hunk belongs to the **concrete**-member
branch (`gf.c:6143-6170`, the `-1` query at :6162-6164), not :6205. Bindings:
`mtX`, `jl_method_table->cache`, the applied query already in `gc[3]`,
`int ambig2 = 0` declared, `dm` rooted in a `gc[]` slot across use,
`dm == jl_nothing` guarded. The `m2_ambiguity_report` regression argument is
verified (incomparable-methods winner ⇒ no `FULLY_COVERS` head ⇒ pin survives);
the pinned substring ` is ambiguous for ` untouched.

**R-11 (§7 — A-F12).** Step 3's wrapper returns the UNKNOWN-*shaped* word
(`Effects(EFFECTS_UNKNOWN; nortcall=false)`) — the conservative one; say which
word and keep the choice.

**R-12 (§D, §C — A-F13, B-F11).** AC-17's inertness sentence: the rtsite clears
are gated on *vocabulary use* (someone calls `split_call`/`known_type`/
`fold_call`), not on `sv.facts` — plain Base has zero producers. AC-17 samples
Compiler **method** CIs only. `m3_policy_sites`: the facts-bail remark is
**observed, not pinned** (`add_remark!` exists at :157's region; whether the
remark survives into `ci.src` is an author-time observation reported to the
coordinator) — the behavioral pins (no `(sig, mi)` pair at the stmt's sig,
rettype `Any`) carry the assertion.

**R-13 (§6 — A-F14).** Carry the `fold_call` contract into its M3 docstring
("code uses it only between paths that compute the same result", old
facts.jl:512) and port the `MAX_FACT_SPLITS` cap with the candidate registry
(old facts.jl:600-608).

**R-14 (§C — B-F8).** New acceptance case **AC-20**: composed-chain membership
edge — `@implement S Z; @implement Z X` (chain S→Z→X); compile a marked caller
at `S` after the declares; the emitted `MembershipEdge`'s `entry` is the
**top-of-chain** entry (the W2-1 rule), and the §8 recheck
(`entry_for(...) === edge.entry || jl_membership_holds_at(...)`) holds at the
entry's world and fails below. AC-18 stays the direct-entry shape.
`m3_rtsite_effects` gains the assertion-through-a-cycle case (A-F16: partial
nortsite mid-cycle, re-narrowed at cycle finish).

**R-15 (§B).** Step 3's "log diff" claim is dropped: plain-behavior identity is
pin-by (exit 0, 3× SUCCESS, the 22-gate battery green, `detect_ambiguities(Base)`
unchanged) plus the ±10 % band. Step 4 per D9: the `all` gauntlet runs every
verification run (6.7 s). Analysis list gains nothing (codegen.cpp untouched).

## G. Open questions for the coordinator

1. **D1 — the criterion's degrees of freedom (§1a):** adopt F4 (closure-at-kinds via
   generated `#…` names, *including* lowering's keyword bodies) with facts §3's
   stated G2 assumption; and confirm the M3 rule "`Keyed` position ⇒ run-time site"
   until M5 rules an erased-key fact form. (Both are conservative; adopting F4 buys
   `map`-over-types facts; rejecting it makes those run-time sites — G1 unaffected.)
2. **D2 — the internal attachment (policy/concrete marks):** recommended: session-side
   `IdDict` in `facts.jl` + `mark_facts!`/`mark_concrete!` (cost: one `haskey`/frame
   in a session that has marks, a `haskey` on two empty dicts otherwise, zero C-side
   footprint; persistence deliberately absent until M6). Alternative: a rooted C
   table (the `open_set_methods` pattern incl. `gc-stock.c`/`gc-mmtk.c` roots —
   round-2 F1 lesson). A `jl_method_t` bit is *not* offered (layout, D-M2-class
   serialization, and `did_scan_source`/`dispatch_status` bits are all semantically
   owned). M6 must rebuild persistence whatever we pick.
3. **D3 — the `all` mechanism:** env `JULIA_FACTS` (§5's three-point argument: child
   precompile uniformity, P1 via process-constant policy, inertness). Rejecting env
   for a `Base.Experimental` toggle forces a policy bit checked on every CI cache hit
   — a policy fork in the hit-path; if the coordinator wants that anyway, it is a
   design of its own (and its name bikesheds to `JULIA_COMPILE_BY_FACTS` = the old
   spelling, if continuity of muscle memory wins).
4. **D4 — the G2 bit on `ci.flags` (0b10000) + the `staticdata.c:1773` keep-mask
   change:** the bit lives in an existing uint8 word with 4 free bits (probe 2) —
   no width change, so the M1a hazard is audited away (§2/§4b), but :1773 changes
   *what survives an image load* for a flag word. Bless the word + the mask (and the
   `JL_CI_FLAGS_G2` define), or name an alternative store (a fifth effects bit —
   rejected: `nortsite ≠ G2` semantically; a new CI field — layout, refused here).
5. **D5 — the record encoding:** struct-wrapper edge items (vs tagged pairs), and
   with it: record edges serialize into package images and keep Method/CI/DataType
   objects alive. (Old build precedent = `FoldRecord` only; M3 generalizes it. The
   strong-reference cost is accepted knowingly; the store (P4) later wants exactly
   these identities.)
6. **D6 — `InlineIdentity`'s hash:** recommendation = session-cached digest of the
   uncompressed CodeInfo body, build-side once per Method, re-verified once per
   Method at image load in `verify_method`; alternative = placeholder `hash=0` now,
   real hashing with the store (M7) — then `verify_method` cannot catch a
   silently-redefined inlined body (the *edge kind* would be a store promise only).
   Cost line: load-time re-hash is O(inlined-methods per image) — the old build's
   load-scan precedents (`scan_new_methods!`) are the same class.
7. **D7 — G2 through cycles:** accept conservative-false for a parent whose inlined
   child is an unfinished SCC partner (§4a note), or bless the second pass over the
   SCC at `finishinfer!` end now. (No acceptance case depends on the bit through a
   cycle; the count script's ≥99 % share tolerates the losses — they are rare by the
   inlining-recursion argument.)
8. **D8 — `NotFullyTypedError` throws at `finish!`:** confirmed to *raise* through
   `code_typed`/first call (not warn), only under a `concrete` mark (§4c)? (The old
   build had no such throw — its enforcement was TraitWorld-level; first blood for
   a compile-time error type in the native path.)
9. **D9 — the G2-count bands and the `all`-gauntlet cost:** confirm the count
   script's ratios (≥99 % G2-bit share; 0 non-stakeholder losses) as the M3 band
   against the g2all rows (E-28: 0/12,368; E-29: 0/15,030 product, 12/68,162 `all`
   stakeholder-only), and confirm running all 22 M1/M2 gates under `all` at every
   M3 gate run (≈2× gate wall) vs every-other-run — machine-sharing courtesy call.
10. **D10 — `jl_membership_entry_for`'s entry surface:** confirm adding the entry's
    `max_world` to the Julia-visible field list (alongside `min_world`, the
    `jltypes.c:3051` name list M1 extended) if it is not exposed — the membership
    edge's verify arm needs the range, and M1/M2 gates only ever read `min_world`,
    so it is unverified today. (Entry-list field growth is copy-on-write + the XX'd
    accessor; no layout of `jl_typename_t` changes.)
