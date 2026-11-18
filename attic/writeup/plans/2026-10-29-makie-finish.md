# The Makie port's finish: the workload's path through `PlotCore`

Status: **done** (2026-10-29, mine; W-70; E-227, E-228). Not normative. The second part of W-70's finish line: "the workload's whole path through `PlotCore`" (the user, 2026-10-29: "I agree with your finish lines"). It follows [slice 4](2026-10-29-x3-slice4.md) and serves [the lean-core memo](2026-10-27-lean-core-old-apis.md) §1.2 (the user API) and its X3 ("The `Axis`, log ticks and grid slice belongs to the port").

## 1. The question

Do the workload's plotting calls, upstream's user API unchanged, run through the umbrella into the trait core? What does the plotting part of a session cost then, against matplotlib's, and does a late load recompile any of it?

## 2. The workload's path

The workload is E-168's plot (`experiments/ttfx/plotting.jl`): two axes stacked, the second with `xscale = log10`, three lines each; a second figure with one axis and one line; each saved as a PNG.

| Upstream call | Upstream's code on the path (E-183, lines run) | In `PlotCore` before this slice | After this slice |
|---|---|---|---|
| `Figure(size = (800, 600))` | `figures.jl` 28, `scenes.jl` 135, `theming.jl` 20, `camera/` 165 | a figure with one axis, made by TraitMakie's own `figure` | the umbrella's `Figure(; size)`: a core figure with no axis yet |
| `fig[1, 1]`, `fig[2, 1]` | GridLayoutBase's `GridPosition` | none | the umbrella's grid position (plain) |
| `Axis(fig[2, 1]; xscale = log10)` | `makielayout/blocks.jl` 125, `blocks/axis.jl` 348, `lineaxis.jl` 226, `wilkinson.jl` 5, `tick_format.jl` 24, `basic_recipes/text.jl` 251, `layouting/` 159, `richtext.jl` 5 (the log labels' superscripts), `interactions.jl` and `mousestatemachine.jl` 51 | none: one linear axis per figure, its ticks a plain function | a core axis in a grid cell; its scale a kept value of a new trait `Scale` (the core implements it for `identity` and `log10`); the ticks and their labels operations of the scale |
| `lines!(ax, x, y)` | `figureplotting.jl` 50, `compute-plots.jl` 316, `conversions.jl` 127, `recipes.jl` 44, `basic_plots.jl` 18, `dim-converts/` 42, `float32-scaling.jl` 38, `layouting/data_limits.jl` 12, the palette's cycle | `lines!(fig, x, y)` on the figure's one axis, colour given or blue | `lines!(ax, x, y)`: a core `Lines` in that axis, its colour the next of the axis's palette (Makie's `wong_colors`), width 1.5 |
| `save(path, fig; px_per_unit = 1)` | `display.jl` 64, `backend-functionality.jl` 34; CairoMakie's drawing of lines, text and polygons | `save(path, fig)` | `save(path, fig; px_per_unit)`: the canvas scaled by `px_per_unit` |

**What stays outside the core, and why it may:**
- **Upstream's ComputePipeline graph** (`compute-plots.jl`) is not on the path: a user's `lines!` makes the core's primitive directly (the memo §1.2: "the core primitive otherwise"). The old recipe API's graph is the compatibility layer's, reached only by old recipes.
- **The axis's interactions** (`interactions.jl`, `mousestatemachine.jl`) do nothing for a PNG.
- **Text layout over FreeType** (`text.jl`, `text_layouting.jl`): the core draws text with Cairo's own text API, as TraitMakie does.
- **GridLayoutBase's solver:** the grid's cells are equal and the margins fixed. The memo calls the solver "called as it is first"; it is the next piece when a figure needs it (colorbars, legends, unequal content).
- **Float32 scaling and dim-converts:** the core is `Float64` throughout.

So the PNGs are not upstream's pixels. They draw the same figure: the same axes, curves, colours in the same order, and ticks at powers of ten on the log axis.

## 3. What the slice builds

**In the core (`PlotCore`, a trait module):**
- **`Scale`**, a trait: `scaled(s, x)::Float64`, `scaleticks(s, lo, hi, n)::Vector{Float64}` (tick positions in scaled coordinates), `ticklabel(s, v)::String`. Implemented for `typeof(identity)` (the linear ticks TraitMakie has) and `typeof(log10)` (ticks at whole powers of ten, labels `10⁻³` with superscript digits). A user implements it for a scale of their own.
- **`Axis`** keeps its scales as `Scale` fields (kept values) and its grid cell. **`Figure`** keeps its axes, `Vector{Axis}`.
- **The kernels take the scales opened** (`Opened{Scale}`) beside the data: compiled per data key and scale key.
- **`Transform2D`** carries the axis's scales, so the `Plot` trait's `draw!(p, c, t)` keeps its signature.
- **The render** lays the axes out in the grid: equal cells, each with TraitMakie's margins. A figure with one axis draws the same pixels as before.
- **`add_axis!`** and the `add_*!` functions on an axis; `render_png(f, path, px_per_unit)`.
- **A palette** (Makie's `wong_colors`) and each axis's place in it.

**In the umbrella (TraitMakie, plain):**
- `Figure(; size)`, `fig[r, c]`, `Axis(fig[r, c]; xscale, yscale, title, xlabel, ylabel)`, `lines!(ax, x, y; color, linewidth)` (the colour cycled when not given), `save(path, fig; px_per_unit)`. Exported, so `plotting.jl` runs as it is after `using TraitMakie`.
- TraitMakie's own calls (`lines(x, y)`, `lines!(fig, …)`) act on the figure's first axis, as before.
- The workload grows the upstream calls: two axes, a log axis, the palette, `px_per_unit`.

## 4. Checks and measures

**Correctness (E-227):**
- `plotting.jl`, unchanged, run over TraitMakie with the workload's solutions: its PNGs equal, byte for byte, the same figures drawn through the core's own functions (`add_axis!`, `add_lines!`, `render_png`).
- Against upstream's PNGs (E-168's `jl-1.png`, `jl-2.png`): the same size; a look at both, stated (axes, curves, colours, ticks); the share of differing pixels reported, not a criterion.
- TraitMakie's `Pkg.test()` (stock image): its reference images unchanged, PlainPlots still draws the same pixels.
- Slices 1–4's checks (`experiments/x3/check.jl`, `check4.jl`).

**Costs (E-227),** 2 fresh processes each, as the slices: `using TraitMakie`; the first PNG of `plot_two` with and without TraitMakie's workload (PrecompileTools' `precompile_workload = false`); after a late `using DataFrames`, the next `plot_two` and the CodeInstances inferred for it.

**The plotting part of a session (E-228),** 2 fresh processes after a warm-up: start, `using TraitMakie`, `plot_two`, `plot_one`, `plot_two` again, as E-168's marks. Against E-168's matplotlib (load 0.45 s with SciPy, first plot 0.51 s) and stock CairoMakie (first plot 1.51 s), and D's TraitMakie own API (0.15 s). The solutions come from the workload's solves, saved once (`experiments/x3/data/`), so the session measures only the plotting.

**Would change the design:** an upstream user call on the path that the umbrella cannot map to the core without a rule the references refuse; a scale that cannot be a kept value; anything on the path recompiled after the late load.

## 5. Open issue 112

It is not on the workload's path. The path's derived values (limits, ticks, pixels) are computed by the core's bounded functions at each render, typed by their declared results; no node graph is involved. Open issue 112 is the old recipe API's: a recipe child's arguments are nodes of the parent's untyped graph. Its proposal, typed derived values in the core, needs a recipe whose children read core-typed derived values. That is the old API's path, not the workload's, and phase 4 (W-83) may change the answer. So this slice does not build it; the issue stays open, scoped to the old recipe API.

## 6. Not in this slice; the remaining steps

- GridLayoutBase's solver (protrusions measured from tick labels; unequal rows); text over FreeType; Makie's theme beyond the palette.
- Blocks other than `Axis` (`Label`, `Colorbar`, `Legend`): an open set, `Layoutable` in the memo. The core holds `Vector{Axis}` (a case for W-83, §7).
- The PlainPlots control for the workload's path (E-168 has the large-scale control: stock CairoMakie recompiles 0.44 s after a late load).
- The umbrella's other user calls (`scatter!(ax, …)`, `hist(ax, …)` on an axis, `lines(fig[1, 1], …)`): the same mapping, by need.
- The ttfx harness's setting D with upstream's user API for the plots: TraitDifferentialEquations' solutions are read by its own accessors, not upstream's fields (`sol.t`, `sol.u`), so `plotting.jl` needs SciML's port (W-34) to run on them as it is.

## 7. Cases for W-83

- **Blocks:** upstream's `Block` is an abstract type, and `Axis` one of its subtypes; the memo's `Layoutable` would be a trait. The core holds `Vector{Axis}`, the simplest form, until phase 4 says whether the two are one.
- **Scales:** upstream's scales are functions, and their protocol is generic functions on the function's type (`inverse_transform(::typeof(log10))`). Here `Scale` is a trait implemented for `typeof(log10)`. Under unification this is the same protocol either way.

## 8. The result (E-227, E-228)

- `plotting.jl` runs unchanged over TraitMakie; its PNGs equal the core's own drawing of the same figures, byte for byte. Against upstream's PNGs: the same figure, not the same pixels (§2).
- Nothing on the path recompiles after a late `using DataFrames`.
- The plotting part of a session: 0.68–0.69 s against matplotlib's 0.98–0.99 s on the same solutions; the first plot 0.16 s against 0.53 s. Numbers and builds: the registry rows, and [MakieCompat's README](../../TraitMakie/compat/MakieCompat/README.md).
- Found on the way: the X3 pixel comparison tool read blank images; fixed. Slice 3's band is close to the core's, not equal (E-223).
