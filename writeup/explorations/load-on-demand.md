# Implementations loaded on demand: a lean tree without a changed API

Status: **exploration** (2026-10-27, for [open issue 75](../open-issues.md#closed-items), option (ii); the issue closed 2026-10-27 by the clean-up, W-65: package extensions for keys and loading stubs for functions adopted, this option stays an exploration). Not normative. No Julia ran for it.

## 1. The question

A lean tree makes the load short (E-176: the dependencies of a plotting core load in 0.5–0.7 s, CairoMakie's whole tree in 2.7 s). But Makie's own recipes use the heavy packages: `hist` (StatsBase), `density` (KernelDensity), `qqplot` (Distributions), units (Unitful). Moved into extensions, they are no longer called the way upstream calls them: `hist(x)` would need `using StatsBase` first. The user asks for a port "called like the upstream packages are". Can the tree be lean and the API unchanged?

## 2. What plain Julia has

- **Package extensions** load when the user loads the trigger; the API changes (the user must know the trigger).
- **Lazy loading by hand:** FileIO loads ImageIO at the first `save` of a PNG (`LazyModules`, `Base.require` at first use, then `invokelatest`). The API is unchanged; the caller's code is compiled against `Any`, since nothing declares what the lazily loaded function returns, and every call goes through `invokelatest`.

## 3. What a trait core adds

A trait declares an operation's signature and result type, and its implementations are checked against them. That is what a caller needs to be compiled without the implementation:
- **The core declares the operation:** `@trait Binning begin bin(xs::Positions, n::Int)::Histogram end`, with `Histogram` a core type.
- **A provider package implements it** for a key: the statistics package's `@implement Binning …`, kept in its own image.
- **The core registers providers by key** in its image (a table from trait and key to the provider's package id), without loading them.
- **At the first call at a key with no implementation loaded,** the entry loads the provider (`Base.require`), then calls the implementation through the latest world, with its result asserted to the declared type. The caller's code was compiled against the declared result, so it stays typed; only the first call pays the load and one dynamic call.
- **Later calls** go through the loaded implementation as through any: once the provider is loaded, the next compilation of the caller sees the implementation (or the call stays a `Dynamic` operation, as now).

What it costs:
- The first call at such a key pays the provider's load (StatsBase: tens of milliseconds; Distributions: hundreds).
- A world-age step: code compiled before the load calls the implementation dynamically until recompiled; the facts rule makes the provider's methods stakeholders' (the trait's owner registered them), so nothing compiled by facts is invalidated by the load.
- Registration ahead of loading needs the provider's package id and the keys it implements, recorded at the provider's precompilation: a declaration in the provider's `Project.toml` or its image, read by the core.

## 4. What it would change

- **Traits reference:** a new kind of implementation, *registered, loaded on first use*; how a bound's entry treats a key whose implementation is registered but not loaded (today: no implementation is an error at the call, `MethodError` with the hint).
- **Lowering:** the entry's slow path loads the provider; the result is asserted as for a `Dynamic` operation.
- **Facts:** the provider's methods are a stakeholder's change (the trait's owner registers them), so loading one invalidates no code compiled by facts beyond what it implements.

## 5. A quick check, before any design

Emulated in plain Julia on a lean Makie fork with `hist` moved to a package loaded at its first call: the session's load without StatsBase, and `hist`'s first call with it. If the first call's extra cost is the provider's load and no more, option (ii) keeps the API at the cost of a delay at first use, which is what Python's matplotlib does with its own lazy imports (E-168: its backend loads at the first plot).
