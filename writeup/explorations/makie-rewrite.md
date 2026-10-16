# A Makie rewrite around fundamental traits

Exploration, 2026-10-16, for the notes as of commit a03a18a ("results like the input"). The question (the user's): given the design as it now stands, what would a Makie rewrite centred on a few fundamental traits look like? The user also holds that demonstrating the design in practice needs a rewrite of this kind, so the last section scopes a minimal demonstrator.

Sources: the four notes, `writeup/proposal-stored-values.md`, `writeup/design-findings.md` §15–§16 and §18, `experiments/interfaces/README.md` (x8, x13–x16), `experiments/interfaces/MakiePlots/`, and the source of Makie 0.24.16 (`~/.julia/packages/Makie/dVJIx`), ComputePipeline 0.1.8 (`E2l50`), CairoMakie 0.15.16 (`wf7sU`), Observables 0.5.5 and GridLayoutBase 0.11.3. Two short scripts checked how Makie's compute graph treats a value that changes type (§1). Code below is a sketch unless it quotes Makie; names and signatures are illustrative.

## Summary

- **Makie already has the design's shape, informally.** Its conversion traits (`PointBased`, `CellGrid`, `ImageLike`) are projections onto representation families of its own. `convert_attribute` projects attribute values. The eleven primitive plot types are a closed set that backends draw. Since 0.24 the compute graph fixes each node's type at its first value. What it lacks are declared result types, a boundary that stops specialization on the user's types, targets closed by ownership, and a rule for where per-type code lives.
- **Eight traits carry the rewrite:**
  - data, in two levels: `Coords` per argument and `Positions{N, T}` for point data;
  - `ColorSpec`, for attribute values with several shapes;
  - `Source`, for live data;
  - `Plot`, for recipes;
  - `Backend`, which draws a closed set of concrete primitives;
  - `Transform`;
  - `Layoutable`;
  - `AxisValues`, for Dates, units and categories.

  Everything else is concrete Makie-owned data.
- **The compute graph becomes typed by construction.** A node has a fixed type: `Node{T}` for inputs and `Derived{T}` for computed values. A node whose shape may change holds a `Dynamic`. An edge is a stored function with a declared result type. Recipes are their own representations, so each recipe's edges are compiled once, in the image of the recipe's author. Primitives are the narrow waist: recipes and backends never meet in compiled code, so no combination image is needed for them.
- **What this predicts:**
  - Makie's own code is never recompiled by loads. x13 already shows this when Makie's tree is merely protected: 8.5–8.9 s to the first PNG instead of 15.7–16.2 s.
  - A new user data type costs its projection, about 35–47 ms on the prototype, against Makie's 297 ms (x8).
  - The about 1,940 dynamic-dispatch targets of a first plot become static calls inside workers, plus a dispatch per plot, per changed attribute shape and per block, over listed conformances.
  - `verify_main` can follow a plot down to the backend, which no static analysis does today.

  Load time is a matter of the dependency tree, not of the design, and does not shrink by itself.
- **Gaps the rewrite exposes:**
  - projections from several arguments at once;
  - trait parameters computed from the representation (`Float32` positions for `Int8` data);
  - live bounds (an argument that is a value or a source of values);
  - union-valued operations;
  - tasks;
  - how a trait-world closure is stored as a dynamic function.
- **A minimal demonstrator:** four primitives, a typed graph, four built-in recipes, Cairo as the one backend, and one user package that defines a data type, a colour, a source and a recipe. It can measure every claimed pay-off against Makie 0.24.16 and against the same code written without traits.

## 1. Makie as it is, in the design's terms

**The pipeline.** `lines!(ax, x, y; kw...)` goes through `_create_plot!` to `Plot{lines}(args, Dict{Symbol, Any}(kw))` (`compute-plots.jl:766`). This:
1. creates a `ComputeGraph` and adds each argument as an input whose node is reset to `RefValue{Any}` (`_register_input_arguments!`);
2. derives the conversion trait from the plot type and the arguments, and expands dimensions;
3. runs the dim converts (Dates, Unitful, categorical) and `convert_arguments` (140 definitions in `src/`), then destructures the result into named nodes (`positions`);
4. adds every documented attribute as an input. A primitive's attribute passes through `AttributeConvert{key, plot}`, a functor over `convert_attribute` (95 definitions). A recipe's attribute is stored as `Ref{Any}` "to make sure it can change type";
5. builds the final type `Plot{FinalPlotFunc, typeof(converted)}`.

`connect_plot!` then adds the theme, the cycle and the transformation. It also adds the `Float32Convert` and the camera, runs `calculated_attributes!`, which registers colour mapping, position transforms and data limits as further edges, and finally calls the recipe's `plot!(p)`.

**The plot object** (`coretypes.jl:66`):

```julia
mutable struct Plot{PlotFunc, T} <: ScenePlot{PlotFunc}      # Makie 0.24.16
    transformation::Union{Nothing, Transformable}
    kw::Dict{Symbol, Any}
    attributes::ComputeGraph
    plots::Vector{Plot}
    deregister_callbacks::Vector{Observables.ObserverFunction}
    parent::Union{AbstractScene, Plot}
end
```

There are 64 `@recipe` definitions and 16 `@Block` types in `src/`.

**ComputePipeline:**
- **Inputs.** An `Input` keeps `value::Any` and a conversion function.
- **Nodes.** A `Computed` node holds `value::RefValue`.
- **Edges.**
  - A `ComputeEdge` holds `callback::Function`.
  - At its first resolve, `TypedEdge(edge)` builds a `TypedEdge{InputTuple, OutputTuple, F}` through `invokelatest`, with the output `RefValue`s typed by the first result.
  - Later results are stored into those typed refs.
- **Sites.** There are 371 `map!` and `register_computation!` sites in Makie's `src/`, and 821 `lift`, `on` and `onany` sites. These are the 656 ComputePipeline targets of x15.

**Node types are already fixed at the first value.** Two checks on Makie 0.24.16 (niced scripts, the `experiments/interfaces/env` environment):
- **A colour that changes shape fails.** For `lines!` with `color = :red`, the colour node is `RefValue{RGBA{Float32}}`. Setting `p.color = [:red, :blue, :green]` then fails with "Failed to resolve scaled_color". The same happens through a recipe (`barplot!`, then `b.color = [...]`): "Failed to resolve color".
- **New data is converted to the first value's type.** Updating a `lines!` plot made from `Float64` data with `Float32` vectors keeps `positions` a `Vector{Point{2, Float64}}`: the update is silently converted.

So the reason the notes give for Makie's `Any`, that "an attribute's value can change type over time", now holds only at the inputs and recipe attributes. A primitive's derived nodes are typed by the first value, and a change of shape is an error. The rewrite can keep the fixed types and restore changes of shape with a `Dynamic` at the input (§3).

**Observables.** Listeners are `Vector{Pair{Int, Any}}`, called through `Base.invokelatest` (`Observables.jl:206`). Scenes, transformations and the layout use observables for their state. `Transformation.transform_func` is an `Observable{Any}`.

**Scenes and layout:**
- **Scene.** A `Scene` is mutable. It holds `plots::Vector{Plot}`, `theme::Attributes` (a `Dict{Symbol, Any}`), its own `compute::ComputeGraph`, `float32convert` and `current_screens::Vector{MakieScreen}`.
- **Blocks.** `@Block` types (`Axis`, `Colorbar`, `Legend`, …) are already typed. Each attribute is a field `Observable{T}` with a declared `T`.
- **GridLayoutBase.** Its `LayoutObservables` are typed. Its `GridContent.content` is deliberately untyped ("type hiding").

**Backends.**
- **The draw loop.** CairoMakie's `cairo_draw` collects the atomic plots of a scene, sorts them by z and calls `draw_atomic(scene, screen, plot)` per plot type (`plot-primitives.jl`).
- **Backends extend the plot's graph.** `draw_atomic` for `Lines` adds nodes to the plot's own compute graph (`add_projected_line_points!`, `clip_line_points`) and reads a `cairo_attributes` node. CairoMakie also treats some recipes (`Poly`, `Band`, `Tricontourf`) as atomic, so a backend can depend on a recipe.

**Globals:**
- `CURRENT_FIGURE` is a `Ref{Union{Nothing, Figure}}`;
- `CURRENT_DEFAULT_THEME` is an `Attributes`;
- `activate!` chooses the backend for the session.

**The match with the design.** Makie's conversion traits are projections onto families of Makie's own (`float_type` picks `Point{N, Float64}` or `Point{N, Float32}` by element type, `conversions.jl:733–752`). `convert_attribute` is a projection per attribute. The atomic plot types are a closed set. What is missing is the following:
1. **A boundary.** `_create_plot!`, `conversion_trait`, `preferred_axis_type` and the dim converts all see the user's types before conversion.
2. **Declared results,** so values between edges are `Any` until an edge is first typed.
3. **Ownership of the targets,** so any load can add a `convert_arguments` method and invalidate.
4. **A placement rule** for per-type code.

## 2. The fundamental traits

The rewrite has one trait module, here `PlotCore`, owning eight traits and a set of concrete types: the representations. The representations are as follows:
- **Positions:** `Point{N, T}` for `N ∈ {2, 3}` and `T ∈ {Float32, Float64}`.
- **Colours:** `RGBAf`.
- **Geometry:** `Rect2f`, `Rect3d`, `Mat4d` and `Vec`.
- **Text and layout:** `String`, and small concrete structs for camera state, colour context, resolved colours and the primitives.

Concrete Makie data (cameras, `Float32Convert`, `LinearScaling`, camera and projection maths) needs no trait. The design says numbers need none either.

### 2.1 Data: `Coords` and `Positions`

Makie converts per plot call, often from several arguments at once (`lines(x, y)`, `convert_arguments(::PointBased, x::RealVector, y::RealVector)`). The rewrite splits this into a trait per argument and a worker that combines.

```julia
@trait Coords{T, R} begin                       # one coordinate axis of data; T is Float64 or Float32
    coords(r::R)::Vector{T}
end
@trait Positions{N, T, R} begin                 # point data, Makie's PointBased
    points(r::R)::Vector{Point{N, T}}
end

@implement Positions{N, T}{Vector{Point{N, T}}} begin points(r) = r end   # the family's own representation
@implement Coords{Float64}{Vector{Float64}} begin coords(r) = r end
@implement Coords{Float64}{V} where {V <: AbstractVector{<:Union{Int64, Float64}}} copies begin
    coords(r) = Vector{Float64}(r)
end
@implement Coords{Float32}{V} where {V <: AbstractVector{<:Union{Float32, Int8, UInt8, Int16, UInt16}}} copies begin
    coords(r) = Vector{Float32}(r)
end

lines!(ax::Axis, p::Positions{2}; kw...) = …                      # compiled per (N, T): four families
lines!(ax::Axis, x::Coords, y::Coords; kw...) =
    lines!(ax, Point2.(promote_coords(coords(x), coords(y))); kw...)   # the worker combines
```

- **The conversion is the projection.** Per user type only the projection compiles, in the conformer's image. Everything after it is compiled per position family, in `PlotCore`'s image.
- **Families of Base types are declared by the trait's owner** (rule 3). A user conforms in one line: `@implement Positions{2, Float64} Trajectory`, with a field `data::Vector{Point2d}`.
- **Grid, image, volume and mesh data** are four more traits of the same shape. `GridData{T}` projects onto `(Vector{T}, Vector{T}, Matrix{T})`, as `VertexGrid` and `CellGrid` describe today. Each carries a representation family of its own.

**`AxisValues`, for dim converts.** Dates, Unitful quantities and categorical values change what an axis shows, not only how values are stored. A categorical axis also needs state shared by every plot on that axis. The rewrite makes this a trait whose representation is the axis's conversion state:

```julia
@trait AxisValues{R} begin
    tofloat!(r::R, xs::Vector{Any})::Vector{Float64}        # sketch; see gap 1 on typed inputs
    ticks(r::R, lims::Vec2d)::Vector{Float64}
    ticklabel(r::R, x::Float64)::String
end
```

- An `Axis` keeps one `Dynamic{AxisValues}` per dimension.
- Dates, Unitful and categorical values are conformances in Makie's package extensions. Makie owns the trait, and the extensions own what Makie owns.
- Tick labels go back as `String`, so the axis never needs a value of the user's type ("results like the input" is not needed here).

### 2.2 `ColorSpec`

`to_color` today returns five shapes with different downstream meanings (findings §16.4). The stored-values proposal sketched `colors(r, n, cm)::Vector{RGBAf}`, which loses numeric colours. The rewrite declares one coarse operation whose result is a single concrete record:

```julia
struct ColorContext                    # concrete, Makie's: what resolving colours needs
    n::Int                             # number of elements
    colormap::Vector{RGBAf}
    colorrange::Vec2f                  # NaN for automatic
    lowclip::RGBAf; highclip::RGBAf; nan_color::RGBAf
    alpha::Float32
end
struct ResolvedColors                  # one representation for every shape
    rgba::Vector{RGBAf}                # length 1 when uniform
    uniform::Bool
    values::Vector{Float32}            # numeric colours before mapping, else empty
    autorange::Vec2f                   # for a colorbar
end
@trait ColorSpec{R} begin
    resolve(r::R, ctx::ColorContext)::ResolvedColors
end
```

- **Conformances.** `Symbol`, `String`, the `Colorant` family, vectors of colorants, real vectors and patterns all conform, declared by Makie. A user's `Gradient` conforms by its methods.
- **Storage.** A plot holds `color::ColorSpec`, which is a `Dynamic{ColorSpec}`.
- **Cost.** The edge that resolves colours opens it once per recompute: one dispatch, then code compiled for that representation in the conformer's image.
- **Why one record per attribute.** Findings §16.4 rejected "a concrete record per combination of shapes", a product across forty attributes. A record per attribute is not a product. Each edge sees one concrete type, and the backend takes the uniform fast path by testing `uniform`, as CairoMakie tests `color isa AbstractArray` today.

### 2.3 `Source`: live data

Users make data live today by passing an `Observable`. The rewrite keeps Observables.jl as ordinary code above the trait world, together with users' `lift` chains, and admits a source at the plot's bound:

```julia
@trait Source{T, R} begin
    value(r::R)::T
    subscribe!(r::R, f::Callable{Tuple{T}, Nothing})::Nothing
end
# in PlotCore (the trait's owner), for Observables' type:
@implement Source{T}{Observables.Observable{T}} where {T} begin
    value(r) = @call getindex(r)::T                  # a declared call: Observables stays outside
    subscribe!(r, f) = @call Observables.on(f, r)::Nothing
end
```

The function `PlotCore` subscribes is a trait-world closure with a bounded signature, `(v::Positions{2}) -> setinput!(node, v)`.
- **Each update is a crossing.** Observables calls the closure from above, and its entry projects every new value, as "Functions that cross the boundary" already provides.
- **In-place mutation.** A sharing projection sees a user mutate the array in place before `notify`. A copying projection is refreshed by the update, which is what Makie's users already expect from `notify`.
- **Sources of the user's own.** A sensor, a file follower or a simulation conforms to `Source{Vector{Point2d}}` by its methods. Its effects are declared calls upward.

This needs a bound that accepts "a value conforming to `X`, or a source of such values". It is gap 3 in §7.

### 2.4 `Plot`: recipes

A recipe is a type of its own that is its own representation: a mutable struct of typed nodes and children. `@implement Plot Stairs` checks its operations, and the edges compile once for the type, in its author's image.

```julia
@trait Plot{R} begin
    children(r::R)::Vector{Dynamic{Plot}}                        # empty for a primitive
    emit!(r::R, sink::PrimitiveSink, cam::CameraState)::Nothing   # primitives only; default: nothing
    datalimits(r::R)::Rect3d
    const visible::Node{Bool}
end
```

- **Built-in recipes.** `barplot`, `hist`, `stairs`, `band` and the rest are recipes of this kind. They build their children out of Makie's primitive recipes `Lines`, `Scatter`, `Poly`, `Text`, `Image` and `Mesh`.
- **Passing attributes on.** A child reads the parent's nodes directly, where Makie today copies them by name (`shared_attributes(p, Lines)`).
- **Defaults.** Theming becomes typed keyword defaults evaluated in the worker (`color::ColorSpec = theme(:linecolor)`), as "Keyword, default and variable arguments" places defaults.

### 2.5 `Backend` and the primitives

Primitives are concrete structs in clip space or data space, after the transform and the `Float32` conversion. For example:

```julia
LinesPrim(points::Vector{Point3f}, model::Mat4f, colors::ResolvedColors, widths::Vector{Float32},
          dash::Vector{Float32}, clip::Rect2f, z::Float32)
```

This mirrors CairoMakie's `cairo_attributes` node, made into a type.

```julia
@trait Backend{R} begin
    begin_frame!(r::R, size::Vec2i, background::RGBAf)::Nothing
    draw!(r::R, p::LinesPrim)::Nothing
    draw!(r::R, p::ScatterPrim)::Nothing
    draw!(r::R, p::PolyPrim)::Nothing
    draw!(r::R, p::TextPrim)::Nothing
    draw!(r::R, p::ImagePrim)::Nothing
    draw!(r::R, p::MeshPrim)::Nothing
    finish!(r::R)::Nothing
end
```

- **Rendering a figure.** The renderer walks the scene's `Vector{Dynamic{Plot}}`, with one dispatch per plot. Each plot fills a `PrimitiveSink` that holds one concrete vector per primitive kind, and the backend's `draw!` calls are static.
- **Data a backend derives** (clip-space points, Cairo paths, GPU buffers) lives in a cache the backend owns, keyed by the primitive's identity and version. Plots' graphs never grow backend nodes.
- **No backend special-cases a recipe.** CairoMakie's atomic `Poly` becomes `PolyPrim`, a primitive.

### 2.6 `Transform`, `Layoutable`, interaction

```julia
@trait Transform{R} begin                       # log10, sqrt, polar, a user's own
    apply(r::R, ps::Vector{Point2d})::Vector{Point2d}
    inverse(r::R, p::Point2d)::Point2d
    valid(r::R, lims::Rect2d)::Rect2d
end
@trait Layoutable{R} begin                       # GridLayoutBase's protocol, declared
    reporteddimensions(r::R)::Dimensions
    protrusions(r::R)::RectSides{Float32}
    place!(r::R, bbox::Rect2f)::Nothing
end
@trait Interaction{R} begin
    process!(r::R, e::MouseEvent, ax::Axis)::Consume
end
```

- **`Transform`.** Its operation takes the whole vector, so the dispatch on an axis's `Dynamic{Transform}` happens per update, not per point.
- **`Layoutable`.** Blocks conform as their own representations. A grid holds `Vector{Dynamic{Layoutable}}`, which replaces `GridContent.content`'s hidden `Any` with a closed one. A user's widget is `@implement Layoutable MyWidget`.
- **Interaction.** User handlers on events stay `Callable`s, dynamic by default. Event values (`MouseButtonEvent`, `KeyEvent`) are concrete structs already.

### 2.7 Globals and the ordinary layer

The current figure, the theme stack and `activate!` are session state. They live in an ordinary module above `PlotCore`. That module provides the MATLAB-style `lines(x, y)`, holds the current figure and the current backend, and passes both down. Layering allows exactly this: ordinary code uses the trait world. The trait world then reads no mutable global except constants such as the default theme record, a deeply concrete value. This is what "Calls upward" already prescribes for Makie as written ("globals become declared calls"), here placed one layer up.

## 3. A typed compute graph

**Nodes.**
- `Node{T}` is an input: the value, a version counter and a list of dependent node identities.
- `Derived{T}` is computed: the value, the versions of its inputs when last computed, and the edge.
- `T` is one of Makie's representations or a `Dynamic`.

Both are concrete for every `T`, and neither carries the function's type. So a recipe struct that holds them is a flat concrete type, and the nesting of §16.1 does not start.

**Edges are stored functions with declared result types.** An edge is a closure created inside a trait module, over the nodes it reads, stored as a dynamic call `Callable{Tuple{}, T}`.

```julia
mutable struct Stairs                                   # a recipe of the user's own
    points::Node{Vector{Point2d}}
    step::Node{Symbol}
    color::Node{ColorSpec}                              # Node{Dynamic{ColorSpec}}: the shape may change
    linewidth::Node{Float32}
    steppoints::Derived{Vector{Point2d}}
    line::Lines                                         # a child, Makie's primitive recipe
end
function Stairs(p::Positions{2, Float64}; step::Symbol = :pre,
                color::ColorSpec = theme(:linecolor), linewidth::Float32 = theme(:linewidth))
    pts, st, c, lw = Node(points(p)), Node(step), Node(color), Node(linewidth)
    sp = @derive stepify(pts[], st[])::Vector{Point2d}  # an edge: compiled here, called through a pointer
    return Stairs(pts, st, c, lw, sp, Lines(sp; color = c, linewidth = lw))
end
@implement Plot Stairs begin
    children(r) = Dynamic{Plot}[r.line]
    datalimits(r) = datalimits(r.line)
end
```

**What is compiled per what:**

| Piece | Compiled per | Lives in |
|---|---|---|
| `Node{T}`, `Derived{T}`, version checks, propagation | value type `T`, from Makie's representations | `PlotCore`'s image |
| built-in recipes and primitives (edges, data limits, colour mapping, transforms, `Float32` conversion) | recipe × position family (≤ 4) × opened representation, summed over edges | `PlotCore`'s image |
| `resolve` of a `ColorSpec` | colour representation | the conformer's image: Makie for `Symbol`, `RGBAf` and vectors, the user for `Gradient` |
| projection of user data | user type | the user's image |
| a user's recipe | its type, once | the user's image |
| `draw!` | backend × primitive kind, a closed product | the backend's image |
| layout | once, over `Dynamic{Layoutable}` | `PlotCore`'s image |
| user callbacks and `lift`s | the trait side once per signature; the closure above | the caller's image |
| recipe × backend | nothing: primitives decouple them | — |

**What stays dynamic, and what it costs:**
- one dispatch per plot per frame, to emit primitives;
- one dispatch per `Dynamic` attribute when it changes (20–80 ns);
- one indirect call per edge recompute (about 4 ns);
- one dispatch per block per layout pass;
- user callbacks.

A figure with ten plots of forty attributes each spends microseconds on these per update, against the milliseconds of rendering. No dynamic position sits on a per-element path. Per-element loops (colour mapping, transforms, clipping, the `Float32` rescaling) run inside workers opened at representations.

**What changes over ComputePipeline:**
- **No inference on first use.** The result type is declared at registration, so the first resolve needs no `invokelatest` and no inference of the edge.
- **Enumerable edges.** Each `@derive` site is a closure type in the module that wrote it, so a build enumerates the edges by walking the recipe constructors.
- **Changes of shape work again.** They occur only at `Dynamic` inputs, so `:red` to a vector of colours works, which it does not in 0.24.16 (§1), at the cost of one dispatch per recompute.
- **Representations of data follow Makie's current behaviour.** The family is fixed at creation, and later updates are projected onto it.

What it gives up: ComputePipeline's single graph per plot, introspectable by name (`plot.attributes[:scaled_color]`), becomes fields of the recipe struct. Inspection by name works through `getproperty`, which is what trait fields are.

**Theming.** Makie's `@inherit linecolor` becomes a typed `Theme` record with fields for the shared keys (`linecolor::ColorSpec`, `linewidth::Float32`, `fontsize::Float32`, `palette::Palette`), plus a `Dict{Symbol, Any}` of recipe-specific entries.
- **The dictionary is the inside position of findings §16.2:** values made inside the module, dispatch closed by ownership, reported by concrete mode, never on a per-element path.
- **Setting the theme from above crosses.** `set_theme!(linewidth = 2)` translates each value at its key's declared bound.

## 4. What a user writes

```julia
using PlotCore, CairoBackend                       # ordinary code
import PlotCore: points, resolve, children, datalimits

# a data type: one line, the projection is the only new code
struct Trajectory; data::Vector{Point2d}; t0::Float64; end
@implement Positions{2, Float64} Trajectory

# an attribute value: its own representation, compiled once in this package's image
struct Gradient; from::RGBAf; to::RGBAf; end
resolve(g::Gradient, ctx::ColorContext) =
    ResolvedColors([weighted_color_mean(i / ctx.n, g.to, g.from) for i in 1:ctx.n], false, Float32[], Vec2f(NaN))
@implement ColorSpec Gradient

# an observable: Observables' type conforms through PlotCore's declaration; nothing to write
xy = Observable([Point2d(0, 0), Point2d(1, 1)])
lines!(ax, xy; color = Gradient(colorant"red", colorant"blue"))
xy[] = [Point2d(0, 1), Point2d(1, 0)]              # the update crosses at the subscribed closure's entry

# a recipe: Stairs above, in this package
stairs!(ax, Trajectory(pts, 0.0); step = :post)
```

**Named implementations.** These cover adapters whose author owns neither the trait nor the type. A plotting-grammar package that owns neither `Positions` nor `DataFrame` writes `@implement named Positions{2, Float64} DataFrame begin … end` and calls `lines!(ax, via(Grammar, df))`. The choice travels with the value, and a `Dynamic` made from it keeps it.

**Generic implementations.** `Positions{2, Float64}` for every `ColTable` representation with two columns is a single declaration by `PlotCore`'s owner, or by a package extension it delegates to. That is the route by which Tables-like data reaches plots without per-type methods.

## 5. Where compiled code lives, and what follows

**Time to first plot.** x13 is the closest evidence. With Makie's tree treated as trait-world code (only protected, not rewritten), the first PNG took 8.5–8.9 s instead of 15.7–16.2 s in both load orders, and Makie recompiled nothing. The rest split as follows:
- the load: 5.4–5.7 s;
- CSV × DataFrames: 2.4 s, a combination no image holds;
- `barplot`'s first `plot!`: 0.24 s, outside Makie's workload.

A rewrite removes the per-user-type specialization before conversion as well (x8: 297 ms per table type against 35–47 ms by projection). Its workload can cover every primitive at every position family, because that set is finite and listed. The prediction is therefore that the work after loading is a few hundred milliseconds in any load order, dominated by what is genuinely new: a user's own representation, or a recipe nobody compiled.

The load is not predicted to shrink. It is a function of the number of images and their `__init__` work (285 images, CairoMakie about 4 s). A smaller dependency tree, merged images or a system image are the levers there.

**Invalidation.** With the runtime pieces (the filter at insertion and at image load, findings §15), no load invalidates trait-world code. On stock Julia this holds only for workers whose Base calls are concrete. The rewrite's own discipline is the same as TraitWorld's machinery: inference barriers around messages and reflection.

**The 1,940 targets.** x15's split was ComputePipeline 656, Base 649 (`setindex!` 159, `map` 47), Makie 378 and Observables 86.
- **ComputePipeline's targets** (`TypedEdge` construction, function wrappers, `add_input!`) become static calls in workers plus the listed edge calls.
- **Base's `setindex!` and `map` on `Dict{Symbol, Any}`** disappear with typed recipe structs.
- **Observables' targets** remain only at the `Source` boundary.

The remaining dynamic sites are dispatches on `Dynamic{Plot}`, `Dynamic{ColorSpec}`, `Dynamic{Transform}`, `Dynamic{Layoutable}` and `Dynamic{AxisValues}`, each over the conformances that reach it. The prediction, to be measured, is tens of targets for x15's plot, and zero to a handful more per new data type or attribute shape (x16 measured 35–84 per new type or shape today).

**AOT.** `verify_main` stops after 4–246 instances per Makie call today (x14). In the rewrite it follows `save(path, fig)` through layout, emission and `draw!` down to Cairo:
- **Cairo.jl** is about 120 `ccall`s on concrete types; whether it passes the check as a wrapped package is decided by the check.
- **FreeType and the font lookup** are `ccall`s and file reads. The artifact lookup reads a TOML file and may download, so it stays a declared call.
- **FileIO's format dispatch** is reflection, so it stays outside, and the backend writes PNG through Cairo directly.

The App binary's lesson carries over. Run-time compilation came from machine code that downstream workloads made for upstream entries and Julia dropped. Rule 4 says that code belongs in the downstream image. A demonstrator should check whether its trimmed binary needs the replay trick.

## 6. What is reused, wrapped, rewritten, or left outside

**Wrapped, if the check passes:**
- GeometryBasics, through the existing StaticArraysCore wrapper;
- ColorTypes and Colors, through the existing wrapper;
- PlotUtils (it pirates `Base.convert(::Type{RGB}, ::Unsigned)`, which has to go);
- Isoband and Contour, DelaunayTriangulation, Packing, KernelDensity (with a StatsAPI wrapper naming StatsBase), Cairo, FreeType and FreeTypeAbstraction, MathTeXEngine.

These are algorithms or bindings on concrete types. x14 found sealing for Makie's tree "a few wrappers away": StatsAPI, AbstractFFTs, ComputePipeline with Observables, and AxisAlgorithms.

**Ported with types, largely as written.** Makie's algorithmic code is ordinary functions on concrete values:
- bar layout and stacking (`calculate_bars`), stair steps, contours, histograms;
- colour mapping, `Float32` scaling, camera and projection maths;
- CairoMakie's clipping and stroking;
- text layout, tick finding, the layout solver of GridLayoutBase (2.9k lines).

Most of the 55.5k lines of `Makie/src` are of this kind.

**Rewritten:**
- the plot object and the creation pipeline (`Plot{F, T}`, `_create_plot!`, `convert_arguments`' cascade, `AttributeConvert`, `Attributes`);
- the `@recipe` and `@Block` macros;
- ComputePipeline's use, and the 821 `lift`/`on` sites, as typed nodes;
- theming;
- `draw_atomic`'s graph extensions, as backend caches;
- the SpecApi, whose `PlotSpec` values become trait-world data that diffing suits.

**Outside, through declared calls:**
- GLFW windows and event loops; event values come in through entries (`process_event!(fig, e::MouseButtonEvent)`);
- `display` (an outward door);
- FileIO;
- ffmpeg recording;
- artifact downloads;
- GPU shader compilation, which is the driver's.

GLMakie's buffer preparation can be trait-world code; its OpenGL context lives behind declared calls.

**Old recipes keep working above.** An ordinary compatibility module can provide `@recipe`, `Attributes` and `lift` on top of `PlotCore`: ordinary code may use the trait world. Ecosystem recipes then keep working as ordinary code with today's costs, and move down one by one. This is "Adopting traits, one function at a time" applied to a plotting ecosystem.

## 7. Migration

1. **Calls upward (done).** MakiePlots: trait code reaches Makie through declared calls, and time to first plot is an ordinary module's.
2. **A typed front over Makie as written.** A trait module projects user data onto Makie's representations and attributes onto trait-world values, then calls Makie. Add the four core wrappers, remove the one real pirate, and give Makie's tree the filter's protection (x13 made real).
   - Gain: no recompilation of Makie, and about 40 ms per new user type instead of 297 ms.
   - Limit: Makie's inside stays `Any`, closed only in practice, by workloads.
3. **`PlotCore`.** The traits, the primitives, the typed graph, `Axis` and the layout, ported from Makie's algorithms, with the compatibility module above it.
4. **Backends.** CairoMakie first, then GLMakie and WGLMakie, with buffer preparation in the trait world and the context outside.
5. **Interaction, `Blocks`, the SpecApi; then the ecosystem** (AlgebraOfGraphics, GeoMakie, GraphMakie), each moving from the compatibility layer down when its owner chooses.

## 8. Gaps the rewrite reveals in the design

1. **Projections from several arguments.** `lines(x, y)` and `heatmap(x, y, z)` build one representation from several values, and `float_type(x, y)` promotes across them. Bounds are per argument. Projecting each argument and combining in the worker works when every argument projects alone, as `Coords` does. It fails where the conversion depends on the combination: `convert_arguments(::CellGrid, x, y, z)` decides edges from centres by comparing sizes. The notes' open numeric-traits point (promotion across representations) is the same question.
2. **Trait parameters computed from the representation.** `Coords{T}` for `Vector{Int8}` is `Float32` and for `Vector{Int}` is `Float64`. A family declaration must therefore state `T` as a function of the family's element type. That is the associated-types question being explored (`writeup/explorations/associated-types.md`, referenced by "Results like the input"). Without it, the rewrite needs one declaration per element-type group, as sketched above.
3. **Live bounds.** "A value conforming to `X`, or a `Source` of such values" is the common case for every plot argument. `Source{X}` with a trait as parameter is not in the notes. Neither is a bound modifier `Live{X}` whose entry projects the current value and subscribes a bounded closure for the updates. The second is narrower and fits rule 2.
4. **Union-valued operations.** The notes declare operations with concrete result types. Makie's attribute shapes tempted a small `Union` result (the "inside position" of findings §16.2). The rewrite avoids it with one record per attribute (`ResolvedColors`). The notes should say whether a small `Union` of concrete representations is a permitted result type, and what concrete mode reports for it.
5. **Trait-world closures stored as dynamic functions.** The typed graph stores edges as `Callable{Tuple{}, T}` made from closures created inside the module. The notes say functions from the trait world are compiled calls as arguments, and that a `Callable` in `DynamicCall` mode is the dynamic value of a function. They do not say how a trait-world closure is stored in a field typed by `Callable`: by dispatch on its type, or by a pointer. Findings §16.6, item 3, already notes that images cannot hold the prototype's pointers.
6. **Tasks and concurrency.** ComputePipeline's `map_latest!` and Makie's async updates (9 sites) spawn tasks; layout and rendering hold locks. The notes list task storage as an inward door but say nothing about spawning a trait-world closure, or about `Dynamic` values shared across threads (the stored-values review found racing writes for pointer tables only).
7. **Assignment from above into a trait-world object.** `plot.color = x` from the REPL must project `x` into the `Dynamic{ColorSpec}` field and mark the node dirty. Stored-values D3 covered assignment to fields declared by a bound and was rejected with D3. The notes' "a bound in a field projects the value" covers construction; whether `setproperty!` from ordinary code on a field declared by a trait name is an entry should be stated.
8. **Per-recipe compile cost at the REPL.** A recipe defined at the prompt compiles its constructor and edges in the session, and views exclude modules under `Main` (findings §15, open). Makie users define recipes interactively. The demonstrator should measure this case.
9. **Errors at the boundary for multi-trait dispatch.** `plot(x)` picks a plot type from the argument (`plottype`). With traits, that is dispatch among bounds `Positions`, `GridData`, `ImageData` and `MeshData`. A type conforming to two of them needs a method for both (rule: unrelated bounds need a joint method), or `plot` becomes a function with a declared preference order. The notes' dispatch rules decide this, but a family as wide as plot types will hit the joint-method rule often.
10. **Printing frames by bound and representation.** This is still open on the prototype (findings §16.3, §16.6 item 4). Without it, the readable-error pay-off cannot be shown in a plotting demonstrator, where errors pass through many recipe layers.

## 9. A minimal demonstrator

The demonstrator is the smallest plotting library that exercises every pay-off measurably. Its shape is Makie's, at about a twentieth of its size. Estimate: 2,500–4,000 lines for the core, 600–1,000 for the backend.

**Packages:**
- **`PlotCore` (trait module).**
  - Traits: `Coords`, `Positions{2}` (two families, `Float64` and `Float32`), `ColorSpec`, `Source`, `Plot`, `Backend`, `Transform` (identity and `log10`), `Layoutable`.
  - Primitives: `LinesPrim`, `ScatterPrim` (circles and squares), `PolyPrim` (rectangles and polygons) and `TextPrim` (Cairo's toy text API, so no FreeType).
  - Built-in recipes: `lines`, `scatter`, `barplot` (onto `PolyPrim`), `hist` (binning onto `barplot`).
  - The typed graph of §3; an `Axis` with limits from data, linear ticks, tick labels and the `Float32` conversion; a two-cell grid layout.
  - A workload covering every primitive at both position families.
- **`CairoBackend` (trait module).** Implements `Backend` for a Cairo PNG surface. Cairo.jl is wrapped if it passes the check, behind declared calls otherwise; either outcome is a result.
- **`Plotting` (ordinary).** `lines(x, y)`, the current figure, `save`.
- **`UserPlots` (a user package).** `Trajectory` (one-line conformance), `Gradient` (a `ColorSpec`), `Sensor` (a `Source`), a `Stairs` or band-with-mean recipe. Also a session variant that defines the same at the REPL.
- **Baselines:**
  - **`PlainPlots`:** the same algorithms and the same features written without traits: `Dict{Symbol, Any}` attributes, Observables, ComputePipeline-style untyped edges. This baseline separates what the design contributes from what smallness contributes.
  - **Makie 0.24.16 with CairoMakie** for the same plots, through the same calls.
  - **matplotlib** (`experiments/interfaces/python/app.py`).

**What to measure:**

| # | Measurement | How | Against | Prediction to test |
|---|---|---|---|---|
| 1 | time to first PNG, fresh process | `time()` laps, load and work separately | PlainPlots, Makie, matplotlib | work after load ≤ 0.3 s in every order |
| 2 | load-order independence | the same, with CSV and DataFrames (with InlineStrings), ChurnStorm and BasePirate loaded before, after or not at all; stock Julia and the patched filter | PlainPlots in the same orders (expected: InlineStrings-style invalidation, as Makie's 8.4 s) | spread across orders under 10% for PlotCore |
| 3 | invalidations | `@snoop_invalidations` over each load | PlainPlots | 0 trait-world instances with the filter; on stock Julia, only workers with abstract Base calls |
| 4 | cost of a new type | first plot of `Trajectory`, a new `Gradient`, a new recipe, from images and from a REPL definition | Makie's 297 ms per table type (x8); PlainPlots | projection only: tens of ms; a REPL recipe: its own compile |
| 5 | dispatch targets | `jl_force_trace_dispatch_enable`, x15/x16's phases A–G | Makie's 1,879 + 1/64/35/41/84 | tens, all in listed conformances; 0–2 per new shape |
| 6 | attribute shape change | `color = :red`, then a vector, then `Gradient` | Makie 0.24.16 fails (§1) | works; one dispatch per change |
| 7 | closure and AOT | `verify_main` from `main` to `draw!`; juliac `--trim` | App's full binary (1.17 GB, 0.89 s; 0.69 s replayed), Pipeline's 3.5 MB | closed; a trimmed binary under 20 MB that runs; count of trim warnings in PlotCore's code: 0 |
| 8 | errors | `lines(["a", "b"])`, a `ColorSpec` returning the wrong type, a recipe calling an undeclared operation, a pirate of `PlotCore` | Makie's `argument_error` and stack trace; PlainPlots | the error at the entry or the conformance, naming the bound; lines and bytes as in findings §17 |
| 9 | run-time cost of dynamic positions | 10⁵-point `lines` updated 100 times through a `Source`; 50 plots redrawn | PlainPlots, Makie | within 10% of PlainPlots; dispatch overhead invisible next to stroking |
| 10 | precompile cost and image sizes | build times, `.so` sizes per package | PlainPlots | larger images, stated; the price of placement |

**How to judge it.** The demonstrator succeeds if 1–3 and 6–7 hold where PlainPlots fails them. These are the design's claims: placement, no invalidation, closure. It should report 4, 5 and 9 as numbers, whatever they are. Item 8 depends on printing frames by bound and representation (gap 10), so that work belongs in the demonstrator's scope.

**What it cannot show:**
- whether the trait count stays at eight for 64 recipes, 16 blocks and three backends;
- whether load time scales with image size;
- whether a GPU backend fits the `Backend` trait without per-recipe special cases.

Porting one large recipe (`contourf` or `barplot` with stacking and labels) and one interactive block (a `Slider` driving a `Source`) is the cheapest next step toward those questions.

**Constraints for running it.** It runs on the shared machine:
- one Julia job at a time, niced, with precompile tasks limited to 4;
- the juliac builds alone, under the memory guard;
- the trimmed demonstrator binary should be far below App's 16.5 GB build footprint, which is itself a measurement worth recording.
