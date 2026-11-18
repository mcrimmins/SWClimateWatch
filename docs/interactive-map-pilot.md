# Interactive climate map viewer

## Automatic publication refresh (November 16)

The viewer now refreshes within the existing daily workflow and site-only
publisher. Daily/current inputs follow the VM caches; monthly payloads follow
the verified accepted Monthly Climate release, including same-month revisions.
The old fixed October seed is no longer used by publication. Matching verified
monthly viewer caches may be retained when numerical sources are temporarily
incomplete. A new accepted release without matching viewer data blocks upload.
The ordinary monthly update window/request limits are unchanged. See
[workflow testing and VM steps](interactive-map-staging.md).

Refresh runs before unchanged-site detection. Source signatures and complete
asset checks reuse unchanged preparation, while new dates, source revisions,
recovered files and changed references or viewer code invalidate it. The
publication path checks source and rendered assets before S3 upload. The status
CSV is `data/diagnostics/interactive-map-pilot/workflow-status.csv`.

The following sections also preserve the earlier local pilot's review history;
their fixed-October references describe that initial snapshot.

## Current Conditions local preview

The initial view is now Current Conditions, followed by Daily History and
Monthly Climate. This increment offers 39 snapshots from the existing Current Maps
products, without recalculating any climate products:

| Variable | Metric | Periods |
| --- | --- | --- |
| Precipitation | Total | 1, 7, 30, 90 days; water year to date |
| Precipitation | Percentile rank | 7, 30, 90 days; water year to date |
| Precipitation | Percent of normal | 30, 90 days; water year to date |
| Temperature | Mean, departure, percentile rank | Water year to date |
| Mean temperature | Percentile rank | 7, 30, 90 days |
| Mean/high/low temperature | Departure | 30 days |
| Precipitation change | Change in 30-day percentile | Over 14 days |
| Current dry spell | Length, percentile | Ongoing through the product date |
| Longest dry spell | Length, percentile | 180 days |

Current Conditions follows Variable → Measure → Metric → Period. Measures are
precipitation totals, precipitation change, current/longest dry spell and
mean/high/low temperature. Periods and metrics are filtered within each measure;
compatible choices survive changes and unsupported choices fall back to an
available choice. Measure is hidden in Daily History and Monthly Climate.
Companion point queries require the same measure as well as matching dates,
so a rainfall percentile cannot be paired with a dry-spell length.
Ongoing dry spells show an "As of" date: their start differs by grid cell.
Dry days have less than 0.04 inch, and higher dry-spell percentiles mean longer
spells. Change is expressed in percentile points, never rainfall inches.

```r
options(swc.interactive.full_site = FALSE)
source("scripts/build-interactive-map-site-preview.R")
source("scripts/preview-interactive-map-site.R")
```

Current Conditions uses each product's own latest displayed date, not a date
chosen from the Daily History calendar. Period choices follow the variable and
metric and exclude unsupported combinations. Compatible water-year selections
survive variable changes. Each view remembers its own selection. Every layer
shows the exact start/end dates and its existing description, and links to the
corresponding static product page. Current snapshot dates may differ; the initial
laptop set is through November 3, 2026.

The adapter respects product/default enablement in `config/map-products.yml`.
It requires a passing `data/diagnostics/map-product-status.csv` record with an
unchanged latest-image hash, and loads only that exact date's numerical grid.
The grid must have one WGS84 layer with the same internal date and plausible
metric values. There is no search for an older substitute when a required file
is missing or mismatched. Refresh the ordinary Current Maps generation/validation
first if its local report is stale; this adapter does not repair those products.

Current percentile fields remain 0–100 percentiles using the existing fixed
reference; monthly record-category logic is not applied. Percent of normal
retains the saved low-normal/missing-data mask. Water-year comparisons retain
their original date-matched reference. Float64 payloads preserve every saved
value and missing cell exactly. Grid/image hashes bind immutable viewer assets
to their source snapshots. Each additional snapshot is approximately 0.40 MiB;
all 39 add about 15.7 MiB to the active release. The browser cache stays bounded
at three bundles across all views.

`data/diagnostics/interactive-current-status.csv` reports unavailable products
and reasons; `interactive-current-checks.csv` records exact cell verification.
Local preparation does not update the daily runner, stage remotely or publish.
First/last freeze dates, freeze-free season and snow remain future increments.

### Additional Current Conditions measures

The viewer also includes 30-day unusually warm-day/cold-night counts and freeze
counts/anomalies; 90-day wet-day frequency, wet-day intensity and very-wet-day
contribution with their percentiles; and water-year maximum three-day precipitation,
its percentile and share of water-year precipitation. Warm/cold counts use the
existing calendar-day 90th/10th percentiles. Freeze nights have lows at or below
32 °F; positive count anomalies mean more freezes. A wet day has at least
0.04 inch. Intensity stays missing without qualifying wet days. Very-wet-day
contribution uses the local wet-day 95th percentile. Both contribution shares
and water-year three-day shares retain their minimum 0.10-inch-total masks.
Shares are percentages, not percent of normal; percentile rows remain separate.
All companion queries still require the same measure and exact dates.

## Daily and monthly local viewer

The View selector includes seven daily views: precipitation total;
temperature high, low and mean; and high/low/mean departures. Monthly mode keeps
the existing 28 combinations. Mode changes remember monthly period and metric
and daily date and metric, with compatible variable selection. Daily variable
changes retain the date. Back/forward moves one calendar day; endpoints are
disabled at the retained range limits. Gaps remain selectable and show an exact
date unavailable notice without retaining another date's raster.

```r
source("scripts/build-interactive-map-site-preview.R")
options(swc.interactive.full_site = FALSE)
source("scripts/preview-interactive-map-site.R")
```

Daily retention defaults to the latest 30 calendar days ending at the local
processed PRISM cache endpoint. At initial development this is October 5 through
November 3, 2026; it is not a statement about current production freshness.
Set `options(swc.interactive.daily_days = 60L)` before building to expand local
review (allowed range 1–90 days). This does not acquire missing source data.
Monthly mode remains the fixed October 2026 release. Source/normal checksums,
native units, layer dates, geometry and high/low consistency are checked before
daily payload generation. The existing Daily Explorer source precedence resolves
recent/archive overlaps; ambiguous ties are rejected.

Departures reuse verified, exactly date-matched 1991–2020 centered five-day
reference grids. Means require paired high/low values; mean normals require both
reference cells. Float64 observed/normal fields preserve exact paired means and
browser-computed differences without additional rounding. Precipitation retains
native float32 values. No interpolation, missing-value filling, new rankings,
source downloads or climatology recalculation are introduced.

Daily input gaps/checksum/reference failures are listed in
`data/diagnostics/interactive-daily-input-status.csv`. Exact per-field and
derived-difference verification is in `interactive-daily-checks.csv` beside it.
Changed source/reference hashes invalidate affected immutable payloads. All
current daily source values are checked again on build, including reused files.
Each bundle remains below 1 MiB and the shared browser LRU cache remains bounded
at three bundles. Thirty days add about 79 MiB of active payloads; this expanded
storage/transfer scope needs its own staging/runtime review. Automatic daily
publication is not enabled by these local scripts.

## Integrated local website preview

The Interactive Maps page now sits immediately after Monthly Climate in the
sidebar. It embeds the reviewed explorer with a full-screen link, automatic
frame height and links to the local Monthly Climate/About pages. The standalone
pilot remains available. The integrated preview still uses the October 2026
snapshot, not an automatic monthly release selector.

The monthly suite now has 28 Variable / Metric / Period combinations:

| Variable | Metric | Periods |
| --- | --- | --- |
| Precipitation | Total, percentile ranking, departure from normal, SPI | 1, 3, 6, 12 months |
| Temperature | Mean, percentile ranking, departure from normal | 1, 3, 6, 12 months |

All periods end October 2026. Exact start/end dates, units, legend and selected
cell values follow the selection. Ranking and departure choices survive variable
switches; unsupported choices fall back to Total or Mean. Period, map position,
opacity, background and selected location remain unchanged. SPI is a precipitation
metric. Amounts/means/departures/ranks for a variable and period share one lazily
loaded payload; SPI has its own payload. The browser retains at most three data
bundles using least-recently-used eviction. New maps do not trigger downloads
from PRISM or statistical refitting.

Rank values retain fractional average ranks for ties. Precipitation record flags
reuse the existing no-common-zero safeguards. Departures reuse supported fixed
1991–2020 reference grids; their missing masks are not filled. Monthly source
files are still verified against their completion-marker hashes, and every
encoded field is compared exactly to its saved source values on build.

For a page-only update after the initial full-site navigation render:

```r
source("scripts/build-interactive-map-site-preview.R")
options(swc.interactive.full_site = FALSE)
source("scripts/preview-interactive-map-site.R")
```

The current 12 bundles plus supporting assets total approximately 9.4 MiB of
referenced files; each bundle remains below 1 MiB. Retained older versioned files
are not included in that active-release total. Preparation/publication retention
and a new mobile/connection benchmark must be checked before staging the larger
suite. The offline controller check covers all 28 combinations and bin edges.
Daily products use a separate date-aware adapter and freshness/support checks,
rather than relabeling the completed-month grids.

Run from the project root in R:

```r
source("scripts/build-interactive-map-site-preview.R")
source("scripts/preview-interactive-map-site.R")
```

The second script renders the full local site so all sidebars include the new
entry, then opens `http://127.0.0.1:8791/pages/interactive-maps.html`.
Keep R open while reviewing; refresh the browser after another build/render.
Local renders use Quarto's `--no-clean` option, updating the served output
directory in place. This avoids the Windows sharing violation caused by
removing `_site` while a preview server holds it open. No server shutdown or
folder deletion is required. Old unreferenced local preview files can remain;
the required current assets are still checksum-validated after rendering.
This option changes only this local preview script, not production rendering.
For later page-only layout iterations, set
`options(swc.interactive.full_site = FALSE)` before sourcing the preview script;
restore `TRUE` when reviewing sidebar navigation throughout the site.
To serve an already-rendered preview without rendering again, source
`scripts/serve-interactive-map-site-preview.R`.

Generated explorer assets live in ignored `site/interactive-maps/` and are
explicit Quarto resources. Control scripts, styles and Leaflet files have
content-versioned URLs. Source and rendered asset checks require all listed
files and checksums, the embedded frame and the rendered navigation link.
Embedded map height depends on width rather than frame height to prevent
resize feedback on narrow screens. No daily runner or S3 integration is added
by these local preview scripts. Staging validation and publication integration
remain separate work after local acceptance.

Local-only November 15, 2026 increment. No navigation, daily runner, source
downloads or publication changes in the standalone pilot. Uses the completed October 2026 monthly
products already retained on the laptop:

- Precipitation totals, percentiles/record categories and departures at 1/3/6/12 months.
- Mean temperature, percentiles/record categories and departures at 1/3/6/12 months.
- SPI-1/3/6/12, with calibration sample counts and withheld-data reasons.

Run in R from the project root:

```r
source("scripts/build-interactive-map-pilot.R")
source("scripts/preview-interactive-map-pilot.R")
```

Preview: `http://127.0.0.1:8790/`. Keep that R session open. Rerunning the
preview script reuses its server if present; another service on that port
produces an explanatory error. After rebuilding, refresh the browser.
`servr::daemon_stop()` stops preview servers managed by that R session.

The builder verifies completion-marker checksums, aligned WGS84 grids and every
exported cell against its saved raster. It retains float32 source precision,
integer ranks/counts, and missing masks. Cell centers and north/west-inclusive,
south/east-exclusive outside-grid edges are checked by the offline browser-code
test. There is no smoothing, aggregation or color-derived query. Display cells
are projected to the Leaflet map at their original geographic edges.

Artifacts live under `data/diagnostics/interactive-map-pilot/`; build and
cell-verification CSV reports live in its parent directory. Immutable binary
filenames include source hashes, geometry and encoding policy. Unchanged files
are checksum-verified and reused. Monthly completion markers verify the saved
product snapshot; this pilot does not re-audit/download upstream revisions.

```r
interactive_map_pilot$summary
interactive_map_pilot$checks
# Optional, if Node is installed:
system2("node", "tests/interactive-map-pilot.cjs")
```

## Interaction review

Exercise all 28 variable/metric/period combinations (only the agreed October
ending month is available). Zoom/pan should persist when switching.
Click/tap queries the source cell and outlines it; the same location is queried
again after switching. Test opacity, reset, missing cells and narrow screens.
Keyboard: focus the map, use arrows and +/−, and press Enter to query the center.
The numeric readout below the legend is also an accessible live region.

Choose Street, Terrain (Esri shaded relief), Satellite (Esri World Imagery),
or None from the Basemap selector. Switching preserves the climate product,
opacity, zoom/pan and selected source cell. Lower climate opacity to see more
background detail. Imagery is geographic context, not current weather/snow;
acquisition dates vary. Provider attribution changes with the active basemap.
Service/source credits are linked from the page. Tile errors have their own
status and do not hide climate availability.
Routine success messages are suppressed. Loading and error notices appear
below the map, while keyboard/query guidance stays in the reading instructions.

Terrain and Satellite now have a default-on Roads & place names checkbox.
Transparent transportation and place-reference tiles use a separate pane above
the climate raster and below popups; pointer events pass through to cell queries.
Changing climate products leaves these overlays in place. Street retains its
own labels and disables the extra checkbox; None removes all hosted overlays.
The checkbox choice is retained when returning to Terrain/Satellite. Road and
place detail varies by zoom. Additional service credits are displayed on-map.
These Esri hosted services are not an entirely open-source stack. The local
pilot reuses the existing Leaflet architecture without Google credentials.

Before production, replace/assess the legacy reference service dependency:
[Esri's retirement schedule](https://www.esri.com/arcgis-blog/products/arcgis-living-atlas/announcements/sunsetting-legacy-basemaps)
lists World Transportation for March 2028 and World Boundaries and Places for
December 2029; legacy reference content is no longer routinely updated. The
configurable manifest keeps provider replacement separate from climate grids.

Local state outlines and climate data work without internet. The optional
[OpenStreetMap basemap](https://operations.osmfoundation.org/policies/tiles/)
requires internet and retains visible attribution. Normal browser caching is
used; no basemap tile prefetching. For automated/offline tests use
`http://127.0.0.1:8790/?basemap=off` to avoid requesting tiles. The pilot reuses
the project's local Leaflet distribution and license. Rendering follows the
[Leaflet GridLayer API](https://leafletjs.com/reference-1.9.4.html#gridlayer).

## Performance and staging gate

Point tables keep the same order across metrics: observed total/mean, departure,
percent of normal (where supported), historical percentile, and warm/wet rank
with its sample size. Monthly totals, means, departures and rankings use the
same bundled statistics; SPI adds its index and separately labeled calibration
count. Daily temperatures show observed, reference and departure instead.
Current Conditions queries existing companion payloads only for the identical
variable, start date and end date. Missing/failed comparisons remain unavailable;
no percentile is converted into a rank or sample count. Current comparisons
use 1991–2020, monthly ranks use the available record from 1895, and SPI uses
its separate 1895–2020 calibration. These reference distinctions appear below
the point table. Companion files load only on a point query and share the bounded
three-bundle cache; stale query results cannot overwrite a newer selection.

The built bundles are approximately 0.96 MiB for each precipitation/temperature
period and 0.35 MiB for each SPI period. Only the selected bundle loads; a
three-bundle cache is bounded as the user explores. Native cells are drawn onto browser canvas tiles. No server-side
tile generation or live R service is needed beyond the local static preview.

The page's performance disclosure records first-ready, cold/cached switches,
query and opacity timings, optional browser heap size, and resource traffic in
the downloadable measurements. Basemap traffic must be assessed separately.
Build timings appear in the R console; unchanged outputs should be reused.
These diagnostics do not establish phone performance, frame rates, added heap
relative to an empty browser, or simulated-connection compliance.

Before staging, assess the roadmap targets on a representative phone and
desktop, cold/warm caches and a 10 Mbps/100 ms connection. Check pan/zoom frame
rates, memory growth after repeated switches, basemap fallback, and sampled
geographic alignment. The local correctness/build checks alone are not a
production performance sign-off. Staging integration remains a separate step.
