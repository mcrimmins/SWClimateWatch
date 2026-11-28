# AZ/NM streamflow pilot: local review

Agreed November 27, 2026. This pilot assesses public source coverage and workload
before any site, Daily Explorer or daily-runner integration. It writes only
`data/raw/streamflow-pilot/` and `data/diagnostics/streamflow-pilot/`.
Historical statistics add a verified cache in `data/raw/streamflow-statistics/`.

The separate [32-gauge assessment and incremental benchmark](streamflow-network-pilot.md)
now cover the proposed expanded network, with its own state, reports and preview.

## Historical context added for local review

The November 27 availability check succeeded at all 12 primary daily-mean
series. Latest-day sample counts range from **49 to 129 approved daily values**.
Ten gauges support 365 calendar days under the pilot's 30-value minimum; the
Embudo and Otowi Rio Grande gauges also support February 29. No leap-day
substitution, smoothing or interpolation is applied.

The viewer now adds a dashed historical median, a 25th–75th band and an optional
10th–90th outer band. A selector hides or narrows historical context. The linked
daily table and CSV include percentile thresholds and the calendar-day sample
count. Map/table categories are below 10th, 10th–25th, 25th–75th, 75th–90th and
above 90th. Boundaries follow `<P10`, `P10<=x<P25`, `P25<=x<=P75`,
`P75<x<=P90`, `x>P90`. A value equal to multiple published thresholds is marked
as a tie rather than assigned a false exact percentile; this includes common
zero-flow ties. Insufficient/invalid history and missing flow are explicit.

Fill encodes historical daily standing. Freshness remains a separate table
field and marker outline: delayed/stale markers are dashed, and stale markers
are dimmed. Categories describe the actual observation date, not a substituted
cutoff date, and do not establish flood categories or historical records.
The seven-day mean is deliberately not classified against daily percentiles.

Source: USGS [Statistics API](https://api.waterdata.usgs.gov/statistics/v0/docs),
`observationNormals`, approved DOY percentiles, parameter 00060, matched to the
primary **daily-mean series ID** returned by OGC time-series metadata. The API's
`parent_time_series_id` field in the normals response refers to that daily
series; it is not interchangeable with the continuous-parent ID in OGC metadata.

The Statistics API does **not** supply exact reference-year bounds in this
response. The visible baseline is therefore labeled the available approved
record, not 1991–2020 and not the separate metadata record bounds. Sample
support can vary by calendar day. Reservoir operations/diversions and watershed
changes are not normalized away. Full-record/regulated-period interpretation
still needs review before broader publication.

Historical-statistics workload: **12 additional response pages, 1,355,035 bytes
(about 1.29 MiB)** cached. The initial statistics assessment took about 10.4 s;
a repeat used zero requests and took about 1.4 s on this laptop. Augmented
browser assets/catalog total about 189 KiB; all 12 enriched hydrograph JSONs
total about 338 KiB and remain loaded one gauge at a time. These are local
measurements, not promises of VM or browser load time. Inspect
`statistics-availability.csv`, `statistics-requests.csv` and
`statistics-workload.csv` under the pilot directory.

## Run and preview

From RStudio in the project root:

```r
setwd("C:/Users/Crimmins/RProjects/SWClimateWatch")
options(swc.streamflow.refresh = FALSE, swc.streamflow.download = TRUE)
source("scripts/build-streamflow-pilot.R")
source("scripts/test-streamflow-pilot.R")
source("scripts/preview-streamflow-pilot.R")

streamflow_pilot$coverage
streamflow_pilot$workload
streamflow_pilot$statistics$availability
streamflow_pilot$statistics$workload
View(read.csv("data/diagnostics/streamflow-pilot/requests.csv"))
```

Preview: <http://127.0.0.1:8798/>. Node checks are optional if Node is not on
RStudio's PATH; the R checks and preview still run. To supply an existing Node
installation, set `options(swc.streamflow.node = "C:/path/to/node.exe")`.

Verify cache reuse with downloads explicitly disabled:

```r
options(swc.streamflow.download = FALSE)
source("scripts/build-streamflow-pilot.R")
streamflow_pilot$workload
```

For a deliberate source refresh (provisional values may change):

```r
options(swc.streamflow.download = TRUE, swc.streamflow.refresh = TRUE)
source("scripts/build-streamflow-pilot.R")
options(swc.streamflow.refresh = FALSE)
```

Historical references have their own refresh switch and are reused across
cutoff dates. To deliberately recheck approved statistics and revisions:

```r
options(swc.streamflow.download = TRUE, swc.streamflow.statistics.refresh = TRUE)
source("scripts/build-streamflow-pilot.R")
options(swc.streamflow.statistics.refresh = FALSE)
```

Routine local review can reuse all existing caches. No automatic monthly or
daily statistics refresh policy is enabled yet. Per-gauge statistics failures
preserve the observed-flow viewer with unavailable historical context and an
explicit availability report; they never borrow another series or stale file
from the previous built viewer. Statistics with sample count below 30, reversed
thresholds, unsupported units, duplicate calendar days or wrong identity are
withheld. Exact-date gaps remain gaps even when historical bands exist there.

By default the cutoff is yesterday in the local R session. To reproduce the
accepted assessment window, set `options(swc.streamflow.cutoff="2026-11-26")`.
An unchanged query reuses its verified source cache, including the latest-value
inventory and metadata. A rebuild is not a source refresh; download timestamps
are preserved and visible. No automatic refresh or cron integration exists.

## Sources and coverage

Use USGS's modern [OGC API v1](https://api.waterdata.usgs.gov/docs/ogcapi/),
not the legacy WaterServices API. Parameter **00060**, statistic **00003**, unit
**ft^3/s** identify daily mean discharge. Inventory queries are restricted to
state codes 04/35 and stream site type ST. Their complete pagination includes
historical last observations; these are not all active gauges. Metadata item
lookups verify selected gauges' IDs, states, coordinates and stream site type.
Primary daily-mean time-series metadata resolves the series used for each
hydrograph; ambiguous series are withheld rather than arbitrarily selected.

November 27 source assessment, cutoff November 26:

| Stream-site inventory | Arizona | New Mexico |
| --- | ---: | ---: |
| Locations with an accessible latest daily-flow record | 440 | 445 |
| Locations reporting within seven days of cutoff | 156 | 143 |
| Locations with a numeric flow within those seven days | 149 | 132 |

Duplicate series account for 443 AZ/446 NM inventory rows. Counts describe
responses from this source snapshot, not guaranteed statewide completeness.
Nonnumeric source observations remain distinct from measured zero flow.

The viewer deliberately uses **six gauges in each state**, covering Colorado,
Little Colorado, Verde, Salt, Gila and San Pedro rivers in AZ, and upper/central
Rio Grande, San Juan, Pecos and Gila rivers in NM. See `streamflow_sites()` for
the explicit selection. This is geographic/source sampling, not a statistically
representative network or a classification of natural versus regulated flow.

Daily observations use their source calendar dates, with each site's time-zone
metadata displayed. They are not instantaneous measurements or a conversion
to the PRISM precipitation reporting day. Do not infer flood peaks, flood stages,
historical records or exact percentile ranks. Daily historical categories now
use the approved statistics described above; they do not classify seven-day means.
Metadata begin/end dates alone do not establish complete historical years.

## Workload and proposed expansion policy

- Current configured release: **38 source response pages**: two state inventories
  plus location metadata, time-series metadata and 90 daily values at each of
  12 gauges. The required cached response bodies total about **0.93 MiB**.
- Browser initial payload is about **180 KiB**, including local Leaflet assets.
  All 12 hydrograph JSONs together total about **147 KiB**, fetched individually
  only when a gauge is selected. Map tiles are separate external requests.
- The first exploratory build completed in about 14 seconds. Subsequent cached
  builds took roughly 6–13 seconds on this laptop. These are local pilot
  measurements, not VM daily-runtime or broad-network projections.
- Each invocation has a **60-request ceiling** and a ten-page bound per query.
  All source pages have checksum-verified caches; cache-only mode makes no HTTP
  requests. `requests.csv`, `workload.csv` and `run-history.csv` record actual
  request/reuse counts, response-body bytes and elapsed times. Response bytes
  are decompressed bodies, not wire-level traffic measurements.
- Anonymous access succeeded for this small assessment. If higher limits are
  needed, USGS supports an optional `USGS_API_KEY` environment variable; it is
  sent only in the `X-Api-Key` header and never saved to the cache metadata or
  browser payload. See [USGS API key guidance](https://api.waterdata.usgs.gov/docs/ogcapi/keys/).
- Before daily integration: cache site/series metadata with a longer refresh
  interval; refresh recent daily windows with a bounded revision overlap;
  retain verified data with explicit stale/error labels on failures. Fetch
  history only for the chosen network, then extend incrementally. Define and
  benchmark this policy separately; this pilot does not implement an updater.
- Before wider use of historical percentiles: review eligible series and completeness,
  zero-flow/tie behavior and season matching, and review regulation/diversion
  interpretation. Long metadata spans alone are insufficient. NOAA flood
  categories/stages and operational flood guidance are separate sources.

## Review and validation

The map, table and selected hydrograph share one selection. Clicking another
gauge cancels stale rendering of earlier loads. Search/state filters and table
sorting retain the selection where possible. A selected gauge has 30-/90-day
views, a linked daily-value table below its SVG plot, keyboard day controls,
CSV data and a prominent USGS source link. Marker fill encodes historical daily
standing; freshness remains separate in the table and marker outlines.

Provisional status and qualifiers are retained. Missing/nonnumeric/censored,
negative values needing review and conflicting daily rows do not become zero.
Plots break at gaps. Seven-/30-day means require complete numeric daily windows
ending at the cutoff; no older day or partial sample substitutes for a missing
endpoint. CSVs cover the same 90-day calendar and include source-quality fields.

R tests cover parameter/unit/identity guards, missing/zero/censored values,
duplicate conflicts, complete means, recency and verified cache reuse. JavaScript
model tests cover missing/zero distinctions, line gaps, search/filter/sort and
dates. The built payload is validated against the 12 local 90-day hydrographs.
Browser review confirmed linked gauge selection and changing the plot window.
Review the pilot locally before selecting a wider network, historical baseline
or any staging/daily integration.
