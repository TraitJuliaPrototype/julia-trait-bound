# X3, slice 1: an unchanged upstream recipe over TraitMakie

Status: **adopted** (2026-10-28, mine; W-70). Not normative. Serves [the lean-core memo](2026-10-27-lean-core-old-apis.md) §1.2 and its experiment X3 (§4), narrowed to a first slice of hours. The user (2026-10-28): "Go for it and continue with the other ports afterwards."

## 1. The question

Can an old-style Makie recipe, upstream's source unchanged, run above a trait core? The core reaches it only through a declared trait: the hand-over of the memo's §1.2. What does the old API cost there, at the first plot and after a late load?

## 2. What the slice builds

A package `MakieCompat` in `TraitMakie/compat/MakieCompat/`, plain code that uses the trait world. It holds:
- **Upstream's `stairs.jl`, unchanged** (Makie 0.24.16, `src/basic_recipes/stairs.jl`), included into the module. Every name the file uses is defined by the layer: `@recipe`, `documented_attributes`, `Lines`, `conversion_trait`, `PointBased`, `plot!`, `Point2`, `map!`, `lines!`, `shared_attributes`.
- **`Plot{F, T}`**, upstream's plot type: the plotting function's type `F`, the converted arguments' types `T`; its attributes, its compute graph and its children.
- **`@recipe Name begin … end`**: the type alias `Name{T} = Plot{typeof(name), T}`, the attribute defaults (splatted `documented_attributes(...)` included), `name(args...; kw...)` and `name!(fig, args...; kw...)`.
- **The conversion** of `PointBased` arguments, `(xs, ys)` to `converted_1::Vector{Point2{Float64}}`: the one case `stairs` needs.
- **A compute graph** with ComputePipeline's author API: `map!(f, p, inputs, output)`, a node read as `p.name`, inputs for the converted arguments and the attributes, recomputed when an input changed.
- **Leaves as core primitives:** `lines!(p, attrs, node)` inside an old `plot!` makes a `PlotCore.Lines` child. The bridge feeds it the node's value at each use, as TraitMakie's own recipes refresh their children.
- **The hand-over:** the layer implements TraitMakie's `Plot` trait for `Plot{F, T}`, a family (traits §4.7). `datalimits` and `draw!` go to the children, and `setcolor!` sets the `:color` attribute. An axis keeps old plots beside core plots as `Kept{Plot}`.

**A simplification against the memo:** the layer owns `Plot{F, T}` itself. In the memo the umbrella owns it and the layer is a joint owner. The ownership question is the same, and the second slice takes it up.

## 3. Measures (E-219)

- **Correctness:** an old-style `stairs!(fig, xs, ys; step)` for `:pre`, `:post` and `:center` draws the same PNG as TraitMakie's own `stairs!` with the same data and attributes, when the two step algorithms agree. A change of `step` or `color` after the plot is made shows at the next save.
- **Cost:** in a fresh process, `using MakieCompat` and the first old-style PNG, against TraitMakie's own first `stairs` PNG.
- **After a late load:** `using DataFrames` after the first PNG, then the second PNG of each kind; the time and the CodeInstances recompiled, core against the layer.
- **Would change the design:** a name or an operation of the old API that the layer cannot provide without a rule the references refuse, or the hand-over needing more than the `Plot` trait's operations.

## 4. Not in this slice

PlainPlots with the same layer (the control); the umbrella as owner with the layer as joint owner; `Attributes` and `Observable` as user-facing types; the cascade of `convert_arguments` beyond `PointBased`; `SpecApi`; other upstream recipes.
