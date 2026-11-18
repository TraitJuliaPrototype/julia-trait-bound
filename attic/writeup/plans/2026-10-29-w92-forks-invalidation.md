# W-92: the forks' invalidated plain code and the facts route

Status: adopted (mine, 2026-10-29): the forks' public layer stays plain; the facts route is measured and kept on the branch `w92-wrapped`; its two weak points go to the main session as candidate open issues.

Sources: [W-92](../record/todo.md); E-233 ([`experiments/phase2-round/README.md`](../../experiments/phase2-round/README.md)); E-238 ([`experiments/w92-forks-invalidation/README.md`](../../experiments/w92-forks-invalidation/README.md), its logs, and `forks/logs/w92/`); [facts §2.2, §6, §11, §12](../reference/facts.md); [porting 0.1a](../intro/porting.md#01a-making-an-unchanged-package-a-trait-module).

## 1. The census

The forks' session (REPL, typing hints off) compiles in its steps 38 roots that the trace marks `# recompile`, 446 ms. The mark means only that the MethodInstance had machine code of some owner before. By kind:

| Kind | ms | Entered from | Covered by the facts owner? |
|---|---|---|---|
| DataFrames' API code rejected at load (`manipulate`, `innerjoin`, `combine`) | 226 | the REPL, through the plain API | no: plain code only |
| the compiler's code (`typeinf_code` rejected at load; closures over `PlainRTInterp`) | 136 | TraitWorld's `Callable` entry, inferring the user's function | no: the compiler is always plain ([facts §6.4](../reference/facts.md#the-compilers-own-code)) |
| Base's methods on the columns, compiled plainly beside an existing facts copy | 83 | DataFrames' plain code | the facts copy exists; plain code cannot use it |

- No code that a method insertion invalidated (1,884 MethodInstances at the REPL's start and the imports) is compiled again in the steps.
- **The cause of the 226 ms is a trait package.** DataFrames' plain code calls `Column`'s operations on values of unknown type (`vector(::Any)`, `take(::Any, …)`). Plain inference records an edge on those signatures. CSV's subtraits `CSVColumn <: Column` and `TextColumn <: Column` are lowered to methods of `Column`'s operation functions on the subtraits' kept forms (`TraitWorld/src/trait.jl:540`). They match there, so DataFrames' image code fails validation when CSV is loaded first.
- Code of the facts owner is not affected by these methods: at a fact signature they never apply, and an untyped call in facts code is a run-time site without an edge.
- At the imports, the REPL's `ansi_write` (0.17 s) is compiled again, invalidated by DataStrings' `convert`. That is Julia's own code, entered by the REPL.

## 2. The options

1. **The forks' public layer as trait-module code** (porting 0.1a applied to DataFrames, the branch `w92-wrapped`). The API's untyped calls become run-time sites. Facts and traits enable this; it needs no design change.
2. **The session under the test bed `all`.** That is not a user setting ([facts §12.2](../reference/facts.md#the-test-bed)). It serves as the reference for what the facts owner's reach buys when images hold its code.
3. **Lowering: a subtrait adds no method to another package's function.** The supertrait's declaration would define one method per operation that serves the kept forms of every subtrait. This changes TraitWorld's lowering, so it is a design matter (§4, candidate 1).
4. **Calls typed at DataFrames' call sites** (`invokelatest`, barriers). A minor tweak; excluded by the rules.

## 3. Measured, and the choice

E-238, 2 timed runs each, the session without the REPL's bimodal start:

| | wall | steps (compiling) | imports |
|---|---|---|---|
| main: the public layer plain | 3.60 s | 2.08–2.10 s (1.59–1.60) | 1.39–1.40 s |
| option 1: the public layer as trait-module code | 3.84–3.94 s | 2.26–2.31 s (1.78–1.80) | 1.46–1.50 s |
| option 2: main under `all` | 3.27–3.30 s | 1.89–1.90 s (1.16) | 1.26–1.29 s |

- Option 1 removes the rejection: `select_filter` is 0.15–0.17 s faster, and `join` 0.02 s.
- But it compiles the facts owner's copies of everything the public layer reaches that no image holds: the display at the REPL's I/O type, `describe`, the `ByRow` paths, and Base's methods beneath them (about 340 CodeInstances of Base in the session). `show` gets 0.19 s slower, `describe` 0.08 s, `user_function` 0.09–0.10 s, and the imports 0.07–0.10 s. The net is +0.24–0.34 s.
- Option 2 shows that the same reach pays when images hold the facts owner's code: −0.31–0.34 s.

**The choice: the forks' public layer stays plain; option 1 stays on the branch `w92-wrapped`, measured and checked.** Adopting option 1 would make the session slower in the product setting. The two causes are weak points of the design, not of the port (CLAUDE.md: record them, do not design the port around them):
- a subtrait's lowering puts methods on another package's function (option 3);
- the product setting has no image of the facts owner's copies of Base.

With either one fixed, option 1 or no change at all recovers the 0.23 s.

## 4. Candidates for the main session

1. **A subtrait's declaration adds methods to the supertrait's operation functions** (`op(dyn::HeldValue{X}, args...) where X<:Sub`, `trait.jl:540`). The [lowering reference](../reference/lowering.md) §3 describes only the methods on the trait's own kept forms, so this is also a reference gap.
   - Effect: plain callers of the supertrait's operations at unknown types are rejected at load, or invalidated, by every subtrait another package declares. Here that is 237 CodeInstances of DataFrames and 0.23 s of the session.
   - Proposal: the supertrait's declaration defines one method per operation for the kept forms of any trait that has it among its supertraits. A subtrait then defines no method of another package's function.
2. **The facts owner's copies of Base in the product setting.** Trait-module code that reaches Base compiles Base by facts in the session. The system image holds plain copies only, and a package image holds facts copies only of what its workload reached.
   - Proposal (two forms): a CodeInstance that plain inference compiled fully typed (every edge a fact) also serves the facts owner, since for it facts inference is plain inference ([facts §13](../reference/facts.md#not-promised)); or the product system image keeps the facts owner's copies of Base reached by a workload.
   - Measured: option 1's +0.4 s in the session; option 2's −0.3 s.
3. **TraitWorld refuses `@nospecialize` on an ordinary vararg** (`@nospecialize(args...)`, also typed `args::T...`) in a trait module, as if it were bounded (`trait_module.jl:874`: `_classify` names a vararg by its expression, kind `:vararg`). The [lowering reference](../reference/lowering.md) §8 says it is kept on ordinary arguments. The workaround is the spelling `args::Vararg{T}`. A candidate T- or L- deviation.
4. **A subtrait's implementation changes the supertrait's member records.** Tables' image holds 30 `conformance(::As{Column}, ::Vector{…})` of the facts owner. They are rejected at load when CSV's `@implement CSVColumn A where {A <: Vector}` loads, because their member-fold records changed. [Facts §2.2](../reference/facts.md#g2) lists no such exception, so this is a candidate F- deviation or open issue.
5. **The compiler's code that TraitWorld's `Callable` entry runs** (`typeinf_code` rejected at load, its closures over `PlainRTInterp` compiled again): 0.13 s of the steps. This is the limit [facts §6.4](../reference/facts.md#the-compilers-own-code) names. It concerns W-91's entries.

## 5. Cases for W-83

- DataFrames' public layer is untyped code over `Any`, the selection mini-language, calling trait operations untyped. In plain mode its edges make it rejectable by any later subtrait. As trait-module code it is protected, but it pays for the facts owner's copies of Base. Unification would make this layer facts code by default, so candidate 2 decides what it costs.
- The subtrait methods of candidate 1 exist because a subtrait is not a Julia subtype of its supertrait (`abstract type X <: Trait`). If `CSVColumn <: Column` were a subtype relation, the supertrait's own methods on `HeldValue{<:Column}` would serve it.
