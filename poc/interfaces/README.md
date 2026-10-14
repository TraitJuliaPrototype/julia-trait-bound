# poc/interfaces — interface packages around DataFrames.jl and Makie.jl

The proof of concept planned in `writeup/poc3-plan.md`, on top of
`TraitWorld/` and the packages in `poc/world/` (Columns, Stats, UserTypes,
Pirate, which this environment develops by path). Nothing here runs yet;
the folders are the layout the plan names.

| Folder | Plan section | Content |
|---|---|---|
| `env/` | §4 | the environment: Julia 1.12.2 pinned, the real DataFrames.jl, CSV.jl and CairoMakie, the packages of `poc/world` and of this directory developed by path |
| `Reports/` | §4 | trait package composing Columns and Stats: `summary`, `zscores`, the histogram reduction from `attic/ecosystem/ColPlots` |
| `DataFramesInterface/` | §4, §3.1 | interface package to DataFrames.jl: `DataFrame` conforms to `ColTable` through `Tables.columntable`; declared calls back into DataFrames; tolerations |
| `MakieInterface/` | §4, §3.1 | interface package to Makie (CairoMakie backend): `PointSeries`, handles for figures and axes, declared calls, Makie's globals behind them; tolerations |
| `App/` | §1 demo 2, §4 | the application: `main` (CSV, DataFrame, Reports, a plot), `sinks()`, and the trim variant `pipeline` |
| `ChurnStorm/` | §6 | the adversary, ported from `attic/ecosystem/ChurnStorm` |
| `scripts/` | §1 | `demo_session.jl`, the measurement scripts (formats of X1, X4, X6, X8), `build.sh` |

BaseInterface is a module of TraitWorld (plan §3.2), not a folder here.
Results go into `README.md` of this directory as the milestones complete,
in the form `poc/world/README.md` uses.
