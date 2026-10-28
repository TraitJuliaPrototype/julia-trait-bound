# Fresh ideas for the Makie port, and the design's weak points it exposes

Status: **proposal** (2026-10-28, a fresh-eye agent's ideas, Opus; not adopted). Not normative.

Serves: the user's request (2026-10-28): "Remember that one purpose of the ports is to identify weak points in the design." and "Feel free to send out fresh eyes opus subagents to come up with fresh ideas for the design and/or the architecture of the ports." The coordinator passed on a second note of the user's: "The guiding principle should be principled solutions. If a tweak in the trait design can enable a principled solution in the port architecture, that's the most valuable finding we can have." So §3, the design changes, gets the most room.

Method: I read the references, TraitMakie and upstream first, and formed a view. Only then did I read [the Makie rewrite](../explorations/makie-rewrite.md), [the lean-core memo](2026-10-27-lean-core-old-apis.md) and [open issues §1](../open-issues.md#1-decisions-waiting-for-the-user). §4 says where I differ from them. No Julia was run. Upstream is Makie 0.24.16 (`~/.julia/packages/Makie/dVJIx`), CairoMakie 0.15.16 (`wf7sU`), ComputePipeline 0.1.8 (`E2l50`), GridLayoutBase 0.11.3 (`K7sJt`). Line numbers in `traits.md` are those of the file at commit a7e102c.

## 0. Summary

**The architecture, in one line each:**
- **Marks are a closed set of types.** Recipes, data, attribute values, backends, scales, blocks and capabilities are open sets, each a trait. Every plotting library I looked at has this waist (§2.8).
- **A recipe is a stat plus marks,** as in ggplot2. A stat is a function with a declared signature. Its result is a typed derived value, so the typed compute graph is the recipes' own structure, not a separate engine.
- **Inputs are kept, derived values are declared.** A shape-changing input (`:red`, then a vector) is a `Kept{X}` field. A derived value has the stat's declared result type. ComputePipeline does the reverse, which is why 0.24.16 breaks on shape changes.
- **Pull with versions inside, push only at the edge.** The core never runs callbacks. Sources that can report a version say so through a capability.
- **Capabilities are traits owned by whoever asks:** the legend, the data inspector, a backend's native drawing, recolouring, a source's version. They are not operations of one central `Plot` trait.

**The design changes this needs, by value:**
1. **D1. A kept value is seen, at a bound, through every trait its object conforms to** (open issue 82, option (a)). Makie gives three cases where the capability's owner is a third package: a backend drawing a recipe natively, the legend, the data inspector. There option (c), operations with defaults on the stored trait, cannot work. Rules: `traits.md:856`, `:635`, `:917`.
2. **D2. One operation at several signatures of one arity,** with disjoint further arguments. Cases: `backend_show(screen, io, ::MIME"…", scene)` per format, and the rewrite's `Backend` with `draw!` per mark kind, which the reference refuses today. Rule: `traits.md:198`.
3. **D3. Forwarding for a whole family, each member checked at its first use.** The planned rule "covered by one implementation's family" refuses `Live{T}` and `Observable{T}` as data, because `Positions` has two implementations. With the per-member rule, open issue 13 (live bounds) closes with no new construct. Rule: `traits.md:478` (T-7).
4. **D4. The joint-method rule cannot see sibling packages.** "An unrelated bound never goes unreported" (`traits.md:629`) fails for two packages that each add a bound to Makie's `plot`. Proposal: report where the overlap is created, at the implementation, and at the call otherwise.
5. **D5. State what a trait's declared field of a trait type is:** `Kept{X}`, written with §7.3's conversion. Then `Colored` (a recolourable colour) and attribute groups are traits of fields. Rules: `traits.md:235–244`, `:816`.
6. **D6. State what a trait-world closure stored by plain code captures.** It matters wherever layout and observables call back into the core. Rules: `traits.md:598`, `:599`, `:709`.

**Needed, but no design change:** several arguments as one value (open issue 12: the argument tuple conforms), input parameters (open issue 6: not needed once D1 and D2 hold), glue packages (Julia's piracy rule already covers them), ticks against scales (operations of the scale).

## 1. Makie as it is: the open sets and where it compiles

| Open set | Upstream's mechanism | Where |
|---|---|---|
| plot types (recipes) | `@recipe` makes `Plot{F, ArgTypes}`; `plot!(p::Stairs{<:Tuple{…}})` dispatches on the converted arguments | `recipes.jl:180`, `compute-plots.jl:766–806`, `basic_recipes/stairs.jl:8–63` |
| data types | `convert_arguments(P, args...)` (about 140 methods), conversion traits `PointBased`, `CellGrid`, `ImageLike` | `conversion.jl:21–97`, `compute-plots.jl:502` |
| attribute values | `convert_attribute(value, Key{:color}, Key{:scatter})` (about 95 methods); a recipe's own attributes `Ref{Any}` "to make sure it can change type" | `compute-plots.jl:604–614` |
| attribute sets | a recipe copies a child's: `documented_attributes(Lines)...`, `shared_attributes(p, Lines)` | `stairs.jl:16`, `:61` |
| derived values | ComputePipeline: nodes by `Symbol`, edges as closures; an edge's outputs become `RefValue{T}` at the first resolve, so a later value of another type fails | `ComputePipeline.jl:145`, `:586` |
| backends | `draw_atomic(scene, screen, ::Scatter)` per primitive; a recipe drawn natively by override (`draw_plot(…, ::Poly)`, `hasmethod(draw_poly, …)`) | CairoMakie `plot-primitives.jl:136–196`, `overrides.jl:12–33` |
| output formats | `backend_show(screen, io, ::MIME"image/svg+xml", scene)`, one per MIME | CairoMakie `display.jl:52`, `:98`, `:105` |
| per-plot capabilities | `legendelements(plot::Lines, legend)`, with a default that recurses into children; `show_data(inspector, plot::Scatter, idx)`, default `false` | `makielayout/blocks/legend.jl:733–898`, `interaction/inspector.jl:479–784` |
| scales, ticks, formats | `get_ticks(ticks, scale, formatter, vmin, vmax)`: multiple dispatch over three open sets | `makielayout/lineaxis.jl:592–775` |
| blocks | `@Block` makes a struct with `layoutobservables` and one `Observable{T}` per attribute; `@forwarded_layout` hands layout to a field | `makielayout/blocks.jl:10–48` |
| layout content | GridLayoutBase asks for a field `layoutobservables` of one exact type; `GridContent.content` is untyped "(type hiding)" | `layoutobservables.jl:368–382`, `types.jl:53–60` |

**Observations that shaped my view:**
- **Makie's primitives are already a closed set** (`PrimitivePlotTypes`, `compute-plots.jl:573`). Backends draw only those.
- **GridLayoutBase's protocol is a trait of one declared field.** It is written by hand: `hasfield(T, :layoutobservables) && fieldtype(…) === LayoutObservables{GridLayout}`. Its untyped `content` is a kept value in all but name.
- **`@forwarded_layout` is `by` forwarding,** spelled as a macro.
- **Every per-plot capability is a generic function dispatched on the plot's type,** with a structural default (recurse into children, or `false`). New plot types and new capabilities are both open. This is the expression problem, and Julia's dispatch solves it today.
- **ComputePipeline types a node by its first value.** That is backwards for attributes. The input's shape may change; the derived value's type should not.

## 2. The architecture I propose

### 2.1 What is open, what is closed

| Piece | Open or closed | Form |
|---|---|---|
| marks (lines, scatter, path, text, image, mesh) | closed: the library owns all | concrete types holding resolved arrays and an attribute group |
| data a recipe reads | open | traits read in place: `Positions`, `GridValues`, `ImageValues`, `MeshValues`; sources by forwarding (D3) |
| data that needs a computation | open | `Plottable`: one trait whose operation converts to a data kind and names the default recipe |
| recipes | open | trait `Recipe`: `marks!(r, sink)`, `datalimits(r)`, `children(r)` |
| stats | open | functions at a declared signature, `Callable{Tuple{…}, Out}`, kept in a derived value |
| attribute values | open | `ColorSpec`, `MarkerShape`, `Colormap`, `LinePattern`: kept fields; a store converts (§7.3) |
| attribute groups | closed per mark | records (`LineStyle`, `MarkerStyle`, `FillStyle`) shared by reference between a recipe and its marks; traits of fields (D5) |
| capabilities | open in both directions | one trait each, owned by the package that asks; selected on stored values (D1) |
| backends | open | trait over the closed mark set: few required operations, the rest defaults |
| scales, tick locators, formats | open | three traits; a pair-specific choice is an operation of the scale |
| blocks | open | `Layoutable`: a trait of one declared field, as GridLayoutBase already has it |
| reactivity | — | pull with versions inside; Observables in the user API and the compatibility layer |

### 2.2 Recipes are stats plus marks

ggplot2 splits a layer into a `Stat` (`compute_group`) and a `Geom` (`draw_panel`). Vega-Lite's composite marks are "macros" of primitive marks. TraitMakie's three recipes with children are exactly this: `Stairs` is the stat `steppoints` and a lines mark, `Hist` is `binned` and a bars mark, `Band` is `bandoutline` and a polygon.

```julia
# a sketch, not run
mutable struct Hist                              # a recipe of the core's
    values::Sample                               # Kept{Sample}: any conforming data, read in place
    bins::Int
    style::FillStyle                             # the attribute group, shared with the mark
    counts::Derived{Matrix{Float64}}             # the stat's result: its declared type, fixed
end
@implement Recipe Hist begin
    marks!(h, sink) = push!(sink, BarsMark(pull!(h.counts), h.style))
    datalimits(h) = barlimits(pull!(h.counts))
end
```

- **`Derived{T}`** holds a value of type `T`, the versions of its inputs when it was computed, and the stat as a kept `Callable` at its declared signature. `pull!` recomputes only when a version changed.
- **The stat's declared result is the node's type.** So the graph is typed by declarations, never by a first value. A shape change happens only at a kept input.
- **The attribute group is one object.** The recipe and its mark hold the same `FillStyle`. `h.color = :red` changes both, with no copy and no notification. This replaces `shared_attributes(p, Lines)` (`stairs.jl:61`).
- **Versions.** A setter through the ordinary layer (`h.bins = 12`) bumps the recipe's version. A source with a version (`Live`, an `Observable` the user API counts) implements a capability `Versioned` (`version(s)::UInt`); one without is recomputed at each render. Selecting `Versioned` on a stored source is D1.
- **A user's stat** is an ordinary function. `Dynamic` by default at its `Callable` position: the library compiles once per signature.

### 2.3 Capabilities belong to whoever asks

- **The legend** is a block group. It owns `@trait LegendEntries begin legend_entries(p::LegendEntries, s::LegendStyle)::Vector{LegendElement} end`. It implements it for the core's marks and recipes (trait owner's right, `traits.md:1200`). A recipe package implements it for its own recipe (type owner's right).
- **The default recurses,** as upstream's does (`legend.jl:897`):

  ```julia
  entries(p::Recipe, s::LegendStyle) = reduce(vcat, (entries(c, s) for c in children(p)); init = LegendElement[])
  entries(p::(Recipe, LegendEntries), s::LegendStyle) = legend_entries(p, s)
  ```
  The axis keeps `Vector{Recipe}`, that is `Vector{Kept{Recipe}}`. The second method must be selectable for a kept value whose object conforms. That is D1.
- **The data inspector** is the same shape (`inspector.jl:782`: default `false`).
- **A backend's native drawing of a recipe** is the backend's own trait: Cairo owns `CairoNative` and implements it for the core's `Poly` recipe. Its render walk has `draw_plot(s::CairoScreen, p::Recipe)` (emit marks) and `draw_plot(s::CairoScreen, p::(Recipe, CairoNative))`. This replaces `hasmethod(draw_poly, …)` (`overrides.jl:19`) with a declared, checked capability.
- **Recolouring** is `Colored`, a trait of one field `color::ColorSpec` (D5). TraitMakie's `Plot` declares `setcolor!` for every plot today (`TraitMakie/src/PlotCore.jl:197–201`): the trait owner closed the set, the workaround of open issue 82 (c), already in the built demonstrator.

### 2.4 Backends: a minimum plus defaults

- plotters' `DrawingBackend` requires `get_size`, `ensure_prepared`, `present` and `draw_pixel`. `draw_path`, `fill_polygon`, `draw_text` and `blit_bitmap` are provided methods that a vector backend overrides.
- matplotlib's `RendererBase.draw_markers`: "The base (fallback) implementation makes multiple calls to `draw_path`. Backends may want to override this method."
- So a `Backend` trait requires `draw_path!` and `draw_image!`, and declares the other marks with defaults in terms of those. A new backend conforms with two methods and gains speed by overriding. Capability per mark is an override of a default; no input parameter is needed.
- Output formats are one operation at several MIME types (D2).

### 2.5 Data

- **Read in place where the data is stored:** `Positions` for `Matrix{Float64}`, `Vector{Point2}`, and the argument tuple `(x, y)` as a family over `Tuple{AbstractVector{<:Real}, AbstractVector{<:Real}}`. `lines(x, y)` then copies nothing, and a user's mutated `y` shows at the next render, as with upstream's observables. Open issue 12 needs no bound over several arguments: the arguments are one value.
- **Convert where the data must be computed:** `Plottable` with `plotdata(x)::Kept{PlotData}` and `default_recipe(x)`. This is Swift Charts' `Plottable` (`primitivePlottable`) and Makie's own `plottype`. `plot(x)` takes this one bound, so no family of unrelated bounds on `plot` arises (open issue 14; D4).
- **Sources forward** to their stored value: `Live{T} by val`, `Observable{T} by val` (Observables' field `val::T`). The core reads the current value at each render. The redraw on change stays plain (D3).
- Shape-dependent conversions (`heatmap(x, y, z)` deciding edges from centres) stay in the plain conversion layer, as the lean-core memo has them.

### 2.6 Reactivity and layout

- **No callbacks into the core.** The core is pulled: `render` pulls derived values; layout is a pass.
- **Layout as two passes,** measure and arrange, as in WPF and Flutter: a block reports its dimensions and protrusions; the grid solves; each block takes its box. GridLayoutBase's solver becomes a pure function over `Vector{Kept{Layoutable}}`. Its observable web stays in the compatibility layer for old blocks.
- **Blocks' attributes** are typed fields, kept where the shape may change, not `Observable{T}` per attribute. `block.xticks = …` converts at the store (§7.3), and bumps the block's version.
- **Interaction handlers** stay user `Callable`s at declared signatures, `Dynamic` by default.

### 2.7 Old APIs

I agree with the lean-core memo §1.2: a compatibility layer runs `@recipe`, `plot!`, ComputePipeline and `convert_arguments` above the core, with the old `Plot{F, T}` family implementing `Recipe` through a hand-over. One addition: old recipes' capabilities reach the new blocks by generic implementations the blocks own, `@implement LegendEntries P where {P <: Makie.Plot}`, whose operation calls the old `legendelements`. This, too, needs D1 to be selected on a stored value.

### 2.8 Other libraries

| Library | Open item set | Waist | Capabilities of stored items |
|---|---|---|---|
| plotters (Rust) | elements, generic `Drawable<DB, CM>`, compiled per element and backend | `DrawingBackend`: four required methods, the rest provided ([docs](https://docs.rs/plotters-backend/latest/plotters_backend/trait.DrawingBackend.html), [Drawable](https://docs.rs/plotters/latest/plotters/element/trait.Drawable.html)) | `Ranged` merges scale (`map`) and ticks (`key_points`); an associated type `FormatOption` picks the default formatter ([Ranged](https://docs.rs/plotters/latest/plotters/coord/ranged1d/trait.Ranged.html)) |
| egui_plot (Rust) | `PlotItem`, dyn compatible | epaint's `Shape` enum, closed, with a `Callback` variant for "backend-specific painting" ([Shape](https://docs.rs/epaint/latest/epaint/enum.Shape.html)) | provided methods with defaults (`allow_hover`, `find_closest`, `on_hover`); shared data through `base()`/`base_mut()` ([PlotItem](https://docs.rs/egui_plot/latest/egui_plot/trait.PlotItem.html)): closed by the trait's owner |
| matplotlib | `Artist` subclasses: primitives and containers ([artists](https://matplotlib.org/stable/tutorials/artists.html)) | `RendererBase.draw_path`, with fallbacks for the rest ([backend_bases.py](https://github.com/matplotlib/matplotlib/blob/main/lib/matplotlib/backend_bases.py), line 236) | methods on the base class |
| Matplot++ (C++) | subclasses of `axes_object` | gnuplot command strings (`plot_string()`, pure virtual) | virtuals with defaults: `xmin()`, `requires_colormap()` ([axes_object.h](https://github.com/alandefreitas/matplotplusplus/blob/master/source/matplot/core/axes_object.h)) |
| Swift Charts | marks are closed; data conforms to `Plottable`, "a type that can serve as data to plot in a chart", through a primitive value ([Plottable](https://developer.apple.com/documentation/charts/plottable)) | the marks | Swift tests protocol conformance at run time (`as?`, [Protocols, "Checking for Protocol Conformance"](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/protocols/)) |
| Vega-Lite | specs; composite marks are "macros for complex layered graphics that contain multiple primitive marks" ([mark](https://vega.github.io/vega-lite/docs/mark.html)) | eleven primitive marks | none: a declarative grammar |
| ggplot2 | `Stat` (`compute_group`) and `Geom` (`draw_panel`, `draw_key`) combined in a layer ([extending](https://ggplot2.tidyverse.org/articles/extending-ggplot2.html)) | grid grobs | `draw_key` per geom: closed by `Geom` |

- **Every library has a closed waist at the backend.** Makie's port should keep one.
- **Libraries in single-dispatch languages close an item's capabilities in its base** (egui's provided methods, Matplot++'s virtuals, ggplot2's `draw_key`). Swift opens them by a run-time conformance test. Rust opens them only by `dyn Any` downcasts to concrete types ([`std::any`](https://doc.rust-lang.org/std/any/index.html)). Makie opens them by dispatch on the run-time type.
- **The trait design today forces the egui choice on stored values.** D1 gives them Julia's.

## 3. Weak points of the design, and the changes I propose

Ordered by what each change buys the port. For each: the case, the rule that blocks it, the proposal, and its cost elsewhere.

### D1. A kept value is seen through every trait its object conforms to

**The case.**
- The axis keeps its plots as `Vector{Kept{Recipe}}`: core marks, new recipes and old `Plot{F, T}` side by side.
- Three packages ask each stored plot for a capability they own: the legend (`legendelements`, `legend.jl:733–898`), the data inspector (`show_data`, `inspector.jl:479–784`), a backend's native drawing (`overrides.jl:12–33`). Each has a structural default for plots without it.
- In the lean core (memo §1.2) the legend and the inspector are block groups loaded on demand. They are not the core's trait owner.

**The rules that block it.**
- `traits.md:856` (§6.5): "A kept value of `X` passed to a bound of another trait `Y` … is refused (`TraitBoundError`)." A tuple bound `(Recipe, LegendEntries)` is "another trait".
- `traits.md:635` (§5.5): a kept value "reaches the bounded method for its trait".
- `traits.md:917` (§6.9): a trait cast "is not part of the language".
- A tuple of traits cannot help: the items of one container conform to different sets of traits (open issue 82).

**What remains today:** option (c) of open issue 82, an operation with a default on the stored trait. It needs the stored trait's owner to declare every capability every block group will ever ask for. `Recipe` becomes a god-trait, and a third package (the legend) cannot add one. TraitMakie already shows the symptom: `setcolor!` in `Plot`.

**The proposal: open issue 82's option (a), as a rule of §6.5.**
- A kept value that holds the user's whole object is seen, at a bound, through every trait its object conforms to. Dispatch among bounds selects by the object's conformance, as for a plain value (§5.5's ranking: a bound that carries every trait of another beats it).
- The attribute carries, as now.
- A trait object inside bounded code stays as it entered. That keeps the 2026-10-21 decision's reason intact: such an object may hold only the parts its traits see, and definition checking relies on its traits ([alternatives](../design/alternatives.md), "Seeing a value through another trait").
- Functions keep their signatures (`traits.md:1052`): a `Callable`'s signature is checked where it enters, which is its point.
- The spelled form, (b), comes with it: `conforms(k, Y)` tests the held object, `Kept{Y}(k)` sees it through `Y` or raises `TraitBoundError`.

**What it costs.**
- A conformance lookup per call where a kept value meets a bound of a trait it was not kept as. It is cacheable per type. A `Dynamic` call pays a lookup by type already (`traits.md:905`).
- Which method a stored value reaches can change when an implementation is declared later. That is Julia's behaviour. It invalidates no compiled code, since membership is taken when the code runs and never folded to `false` (`traits.md:1381`).
- Kept values held by their parts, not whole (T-35's case), cannot be seen through more traits. They are refused at such a bound, naming the cast.
- TraitWorld already does much of this: T-53's entry assembles `Y`'s view from the held object. The deviation becomes the design, with the refusal of a non-conforming object.

### D2. One operation at several signatures of one arity

**The case.**
- CairoMakie's output formats: `backend_show(screen, io, ::MIME"image/svg+xml", scene)`, `::MIME"application/pdf"`, `::MIME"application/postscript"` (`display.jl:52`, `:98`, `:105`). The function is an existing protocol; it cannot be renamed per format.
- A backend over the closed mark set: `draw!(b, ::LinesMark)`, `draw!(b, ::ScatterMark)`, …. The Makie rewrite's `Backend{R}` (§2.5) declares `draw!` six times at one arity.

**The rule that blocks it.** `traits.md:198` (§3.1): "One operation may be declared at several arities (`iterate` above), not twice at the same arity."

**What remains today.** One declaration at an abstract argument type (`m::MIME`, `p::Mark`) and a capability operation (`showable(b, m)::Bool`). The implementation check then cannot say which formats a backend covers. A missing one is a `MethodError` at the call. That is the unchecked convention traits exist to replace.

**The proposal.**
- An operation may be declared at several signatures of one arity when their further argument types are pairwise disjoint (no value fits two). `@trait` checks the disjointness.
- Each declaration has its own result type and may have its own default.
- `@implement` checks each declaration as an operation of its own.
- A call selects the declaration by the further arguments' types, as Julia's dispatch would. Definition checking selects it at the archetype where those types are known, and otherwise treats the call as a run-time choice whose result is the union of the declared results.

**What it costs.** A trait's operation becomes a small method table instead of one signature: in `@trait`, in the archetype, in error messages. It touches open issues §6's item "two traits declaring one function at one arity" (`Indexable` and `Keyed`, both `getindex`). That case differs: the traits differ, and `Int` keys are not disjoint from `Keyed{Int, V}`. D2 settles only the case within one trait.

### D3. Forwarding for a whole family, each member checked at its first use

**The case.**
- `Live{T}` in TraitMakie needs four declarations, one per parameter value (`TraitMakie/src/TraitMakie.jl:145–148`).
- Observables' `Observable{T}` (field `val::T`) should be data as it is: a plot reads its current value at each render.
- The core's own sources (`Node{T}`) are the same shape.

**The rule that blocks it.** `traits.md:478` (§4.7): "The family of field types must be covered by one implementation's family." `Positions` is implemented by `Matrix{Float64}` and by `Vector{NTuple{2, Float64}}`, two implementations. So `@implement Positions Live{T} by val where {T}` is refused even after T-7 is built.

**The proposal.**
- A forwarding family's member is checked at its first use, as every family member is (`traits.md:466–469`). It forwards to the implementation its field's type has.
- A member whose field type has none (`Live{String}`, `Observable{Any}`) is refused at its first use, with `ImplementError` naming the field and its type.

**What it costs.** No whole-family guarantee at the declaration. Families already give none (`traits.md:466`: "Each member is checked at its first use").

**What it buys.** Open issue 13 ("live bounds", `Live{X}` as a bound modifier) closes with no new construct. A source of values is a value that conforms by forwarding. The notification stays plain code, as TraitMakie's README already argues.

### D4. The joint-method rule cannot see sibling packages

**The case.** Makie owns `plot`. A geography package adds `plot(x::GeoData)` and a graph package adds `plot(x::GraphData)`, each with a trait it owns (allowed: `traits.md:633`). Both depend on Makie, not on each other. A type that conforms to both reaches an ambiguity.

**The rule.** `traits.md:629` (§5.5): "A package that adds a bounded method to the function … is checked at its own module's end, so an unrelated bound never goes unreported." Each package's end sees Makie's bounds and not its sibling's. So the overlap is unreported until a call. The claim does not hold.

**The proposal.**
- State where the overlap is found: at the implementation that creates it. When `@implement` makes a type conform to two traits that bound unrelated methods of one function at one position, and both methods are loaded, it reports the missing joint method. Otherwise the call raises `TraitBoundError` naming the joint method to write.
- For the port: avoid open families of bounds on one function. `plot(x)` takes one bound, `Plottable`, whose operations name the data kind and the default recipe (§2.5). Open issue 14 is then avoided, not answered.

**What it costs.** A check per implementation over the functions with bounded methods at the implemented trait. A report at `@implement` may come from a package that does not own either bound; it is a warning there, since that package cannot add the joint method.

### D5. A trait's declared field of a trait type

**The case.**
- `@trait Colored begin color::ColorSpec end`: the capability "has a colour of any shape", which a `recolor!` selects (D1). It replaces `setcolor!` in TraitMakie's `Plot`.
- Attribute groups as traits of fields: `@trait LineStyled begin linewidth::Float64; color::ColorSpec end`, implemented by `Stairs` and by its lines mark (upstream: `documented_attributes(Lines)...`, `stairs.jl:16`).

**The rules.** §3.3 (`traits.md:235–244`) says a declared field has "the declared type", and a writable field needs a stored type exactly equal to it (`:239`). §6.3's table (`:816`) gives `Kept{X}` for a trait's name "as a field's or element type, inside a trait module". That reads as a struct's field. Nothing says what a *trait's* declared field typed by a trait's name is.

**The proposal.** State it: a trait's declared field typed by a trait's name is `Kept{X}`. A conforming type stores it as `Kept{X}` (in a trait module, a field written `color::ColorSpec`). A write through the trait converts as a store does (§7.3: a conforming value keeps or takes its attribute; another value goes through the owner's `convert(X, x)`). A read gives the kept value with its attribute.

**What it costs.** Nothing new: it names what TraitMakie's structs already store.

### D6. A trait-world closure stored by plain code

**The case.** GridLayoutBase lays out by observable callbacks (`layoutobservables.jl`); ComputePipeline stores edges as closures (`ComputeEdge.callback::Function`); Makie's blocks register `on(…)` handlers. In the compatibility layer, and wherever a port keeps them, a closure made in trait code may capture a trait object and be stored in an `Observable`'s listener list.

**The rules.** `traits.md:598`: a closure capturing a trait object may be "passed to Base", checked like the function. `:599`: keeping a trait object beyond the call needs a declared trait name or kept form. `:709`: "Functions returned to plain code are ordinary closures of the trait module. A closure that captured a trait object keeps the user's object." The three do not say which applies to a closure stored by plain code: a trait object then outlives the call without a declared form.

**The proposal.** State that a closure which escapes to plain code captures each trait object as a kept value of its bound, with its attribute: the closure keeps it as a field of a trait's name would. A later call from plain code is a call into trait code, dispatched when it runs (`traits.md:765`).

**What it costs.** A captured `Compiled` trait object becomes a kept `Compiled{X}`: an operation on it costs a lookup by type (`traits.md:905`), not a direct call. The architecture of §2.6 keeps such closures out of the core, so the cost falls only on the compatibility layer.

### Gaps that need no design change

- **Several arguments as one value** (open issue 12): the argument tuple conforms, as a family over Base's `Tuple` declared by the trait's owner (§2.5). Conversions that depend on the combination stay plain.
- **Live bounds** (open issue 13): closed by D3.
- **`plot(x)` over data kinds** (open issue 14): one `Plottable` bound (D4).
- **Input parameters** (open issue 6): backends need none once marks are closed types and D2 holds. A backend's per-recipe capability is a trait of its own (D1). I found no Makie case that needs a type conforming at several values of one parameter.
- **Ticks against scales:** upstream's `get_ticks` dispatches over three open sets (`lineaxis.jl:592`). A pair-specific choice becomes an operation of the scale, `default_ticks(s::AxisScale)::Kept{TickLocator}`. plotters goes further and merges scale and ticks into one trait (`Ranged`).
- **Glue packages** (plotting a third package's type): an implementation of a foreign trait for a foreign type belongs in the trait owner's extension (`traits.md:1200–1201`). That is Julia's piracy rule, and Makie's ecosystem already uses extensions for it.
- **Colours whose meaning depends on other attributes** (numbers through a colormap and a range): an operation takes the context, `resolve(c::ColorSpec, ctx::ColorContext)::ResolvedColors`, at array granularity. Operations on `Dynamic` values should work on whole arrays, never per point (TraitMakie's `rgba(c, i)` per point is the counter-example; its `colors(compiled_for(c), n)` the fix).

## 4. Where I differ from the existing plans

1. **The rewrite (§2.5): "No backend special-cases a recipe."** I keep backend special cases, as capability traits the backend owns (§2.3). Making each special case a mark grows the closed set with every backend's wish: CairoMakie wants `Poly` as a path, a GPU backend wants it triangulated. This needs D1.
2. **The rewrite's `Backend{R}` declares `draw!` six times at one arity.** `traits.md:198` refuses that. Neither plan noted it. D2, or distinct names per mark.
3. **The memo's `Drawable` (`children`, `datalimits`, `emit!`) places no capabilities.** The legend, the inspector and recolouring have no home there, and TraitMakie puts `setcolor!` into `Plot`. I propose one trait per capability, owned by whoever asks, selected by D1.
4. **The memo derives values by `refresh!` first, a typed graph "where a measurement asks".** I propose the stat-plus-marks split from the start. It is the principled structure of a recipe (ggplot2, Vega-Lite), and it gives the typed graph as fields of the recipe, with no engine. `refresh!` recomputes every stat at every render.
5. **The memo subscribes a user's `Observable` in the umbrella and converts each new value into the core's input.** I propose that the observable conforms by forwarding (D3) and is read in place. Only the redraw on change stays plain.
6. **The memo calls GridLayoutBase as it is, by facts on the core's path.** I propose layout as a measure-and-arrange pass over `Kept{Layoutable}`, with GridLayoutBase's solver as a pure function. Its observable web, with `GridContent.content` untyped, is where the facts mode pays most (porting 0.5).
7. **The memo's table implements `ColorSpec` "for `Symbol`".** Closed issue 68 decided that `Symbol` does not conform; validated names do. A stale copy in a plan; I note it only.
8. **The memo converts `x, y` into `Vector{Point2d}` in the umbrella.** I would also offer the argument tuple as `Positions` (§2.5): no copy, and mutation shows. Which one pays is a measurement, not a principle: Makie converts to `Float32` points anyway for its GPU backends.
9. **The rewrite's gaps 3 and 9** (live bounds; the joint-method rule for `plot`) are answered by D3 and D4 without new constructs.

**Where I agree:** marks as the narrow waist; inputs kept, derived values declared; the compatibility layer with a hand-over for old recipes; loading stubs and entries through `invokelatest`; the user API thin and plain.

## 5. The smallest experiments that would decide

Each names the result that would change the design. Each is minutes on TraitMakie's scale.

| ID | Question | How | Result that changes the design |
|---|---|---|---|
| F1 | D1: can a third package's capability be selected on a stored plot, and at what cost? | A package `LegendLite` owning `LegendEntries`, implemented for `Lines` and `Scatter`, not for `Hist`; `entries` over `Vector{Plot}` with the two methods of §2.3. Run on today's TraitWorld (T-53's entry) and record what it selects, the time per selection for `Dynamic` kept values, and the core's CodeInstances lost when `LegendLite` loads after the core. | If selection costs well above a `Dynamic` call's lookup, or the load invalidates core code: prefer (b), the explicit cast, over (a). |
| F2 | D4: is a sibling overlap reported before the call? | Two small packages each adding a bound to one function of a third; a type conforming to both; note where an error first appears. | Expected: only at the call. Confirms that `traits.md:629` overclaims. |
| F3 | D3: does per-member forwarding give the same keys as the four declarations? | Once T-7 is built: `@implement Positions Live{T} by val where {T}`; compare compiled keys and the PNGs with today's four declarations; check that `Live{String}` is refused at its first use. | A difference in keys or images. |
| F4 | §2.2: does a stat as a `Derived` value pay over `refresh!`? | `Hist` of 10⁵ values: second render, and a render after `bins` changes; PNGs equal. | If the second render does not drop to the mark's drawing time, the split waits, as the memo has it. |
| F5 | D2: what does the workaround cost in checking? | A probe: `@trait` with two declarations at one arity (expect refusal); the abstract-`MIME` form with one format missing (expect a `MethodError` at the call, nothing at `@implement`). | None to measure; it records the gap for the decision. |

F1 and F2 need no change to TraitWorld. F1 also gives open issue 82 its second port's evidence: the DataFrames memo found the pooled column, Makie the legend, the inspector and native drawing.
