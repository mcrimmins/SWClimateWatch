# Station explorer and public beta

The local research preview builds the interactive RCC-ACIS station map and
tabbed tables. A screened snapshot is also staged as the public Station
Conditions beta page, with a guarded refresh in the daily update. It uses the 62 unique station records in the
reference-network daily audit and their existing full-period local daily
caches. The 51 fixed stations have map locations; the 11 ThreadEx area-composite
series are table-only and are explicitly labeled as such.

From the project root, after the daily caches are complete, run:

```r
source("scripts/build-acis-station-explorer-prototype.R")
```

The script uses the newest valid cache date, capped at yesterday, as one page
date. A lagging or missing station cache is marked stale/unavailable on that
date; it no longer delays every other station. Popups show the last cache date
for stale stations. For a different available date:

```r
Sys.setenv(SWC_ACIS_EXPLORER_AS_OF = "2026-09-28")
source("scripts/build-acis-station-explorer-prototype.R")
Sys.unsetenv("SWC_ACIS_EXPLORER_AS_OF")
```

To refresh only the presentation and coverage CSVs from the last built station
summary, without recalculating historical periods, run:

```r
source("scripts/refresh-acis-station-explorer-preview.R")
```

Use the full build script above when station data or the `as_of` date changes.
The full build now also generates one small, on-demand daily-detail JSON file
per station. To regenerate just those files from existing daily caches for the
preview's current `as_of` date, run:

```r
source("scripts/build-acis-station-explorer-details.R")
```

## Local daily-refresh pilot

The manual refresh pilot is separate from the unified daily publish command;
the public beta calls its bounded updater and publication screen internally.
It uses yesterday as its target date by default and does nothing beyond a
cache-status preview unless a positive request limit is set:

```r
source("scripts/update-acis-station-explorer-pilot.R")
table(swc_station_explorer_pilot$after$pending)
```

To update all pending records in one resumable local run, then rebuild the
local explorer page and station-detail files:

```r
Sys.setenv(SWC_ACIS_EXPLORER_MAX_REQUESTS = "62")
source("scripts/update-acis-station-explorer-pilot.R")
swc_station_explorer_pilot$failures
table(swc_station_explorer_pilot$after$pending)
Sys.unsetenv("SWC_ACIS_EXPLORER_MAX_REQUESTS")
```

Use a smaller request limit for a short batch; rerun the same command to
continue. Each successful station cache is reusable, and a failed station
does not discard the other caches. If at least one cache reaches the target
date, the local page advances to that date and labels lagging stations as
stale. If none does, the page remains on the newest available cache date.
`SWC_ACIS_EXPLORER_AS_OF` can override the target date and
`SWC_ACIS_EXPLORER_REFRESH_DAYS` controls the recent-days refetch (default 45).
Set `SWC_ACIS_EXPLORER_BUILD=false` to refresh caches without rebuilding the
page. None of these options renders, uploads, or links the public site.

Selecting a map point or table station loads its detail file through the local
server; the main page does not embed all daily histories. The detail panel
charts daily precipitation and high/low temperature for the selected period,
shows usable-record dates and current-window coverage, and places the current
period on a percentile gauge. The percentile gauge reuses the already-computed
full-record rank; it is not a new climatology or a replacement for the
station-by-station comparison-year information in the table.

For the full basemap preview, run this second line in the same R session:

```r
source("scripts/serve-acis-station-explorer-prototype.R")
```

It opens `http://127.0.0.1:8765/` in your browser. The local server runs in
the background while that R session remains open. OpenStreetMap tiles are
requested only for the map area you view, with visible attribution and normal
browser caching. Internet access is required for those tiles. Opening
`data/diagnostics/acis-stations/station-explorer-prototype/index.html`
directly from disk still shows stations and boundary outlines but intentionally
does not request basemap tiles: OpenStreetMap requires a web-page Referer.
This is a research-preview tile source, not yet a production hosting decision.
The page never makes live RCC-ACIS requests.

Leaflet JavaScript and CSS assets are copied from the installed R `leaflet`
package, and the station and boundary data are embedded in the HTML. The
adjacent CSV contains the exact data behind the prototype for spot checks.
The map shows state outlines across the contiguous United States so they do
not end at the Arizona-New Mexico data footprint. Surrounding states are
lighter than Arizona and New Mexico; county detail remains regional.

The build also writes `coverage-by-station.csv` (one row per station, period,
and map metric) and `coverage-summary.csv` (reason counts for mapped fixed
stations). Reasons distinguish incomplete current windows, quality flags or
accumulated precipitation, stale caches, too few 1991-2020 normal years, and
too few earlier years for a rank. The current-value completeness rule and the
15-/25-year minimum comparison thresholds and 20-/30-year unqualified
thresholds apply. The page's collapsible
coverage section summarizes the selected map metric and links to the full CSV.

## First-pass interaction

- Choose a 7-, 30-, or 90-day rolling window, or a rolling 6- or 12-calendar-
  month period, at the top of the map. The selection changes the map, hover
  summaries, all three table tabs, and the displayed start date together.
- Select the colored map metric: precipitation total or mean temperature,
  their 1991–2020 departures, or their full-record percentile ranks. The legend
  changes with metric and period. Each station label shows its selected numeric
  value on that legend's color; a dash means unavailable, not zero.
- Hover for a compact precipitation and temperature summary. Click or tap a
  fixed-station label for a larger bubble with station ID, selected value,
  departure, rank, comparison years, data coverage, and any reason the selected
  value is unavailable. Available values are numbered; unavailable stations
  are small muted dots by default, with an option to label them. Nearby
  numbered labels become colored dots until you zoom in. All dots remain
  clickable. A basemap toggle can remove tile detail when it is too busy.
  Search, state, and value-availability filters act on both map and tables.
- The tables are numerically sortable and have three tabs: current values,
  percentiles and ranks, and recent single-day extremes. ThreadEx series are
  present in each table but are never plotted as physical point locations.

## Statistical definitions and limitations

- A selected-period value uses every valid daily observation from its start
  through the page date. The 7/30/90-day windows have fixed lengths. A 6- or
  12-month period starts the day *after* the corresponding calendar date six
  or twelve months before the end date, so it includes the end date and can
  vary in day count. Month-end dates roll to the last available day. The
  exact start date and number of days appear above the map. Precipitation is
  summed; mean temperature is the mean of valid daily
  `(maxt + mint) / 2` pairs. Complete precipitation is required for
  departures and ranks. If only the most recent one or two precipitation
  reports are missing (at most one for a 7-day period), the observed total is
  shown as a provisional lower bound with `≥` and a dashed map edge; its
  departure, rank and percentile are withheld. Interior gaps, larger lags,
  and quality-flagged days make the total unavailable. A temperature mean
  can use at least 95% of paired days if no gap exceeds two consecutive days.
  Coverage of 98% or more displays normally; 95–<98% carries `*` and a
  dashed edge on temperature values and comparisons. Below the 95% floor, or with
  quality flags, the mean and its comparisons are unavailable. A stale
  station cache is unavailable rather than treated as a reporting lag.
  An ACIS trace counts as zero precipitation. Accumulated precipitation
  cannot be assigned to a single day and is excluded.
- Departures subtract the arithmetic average of seasonally matched
  totals or means from 1991–2020. At least 15 eligible comparison years are
  required. Results based on 15–19 years display a limited-sample caution.
- Percentiles use one eligible selected-length period ending on the same calendar date
  in **each earlier usable year**, not five overlapping periods per year. The
  current year is excluded. At least 25 valid years are required; 25–29
  years display a limited-sample caution. The
  percentile is `100 * (number lower + 0.5 * number tied) / n`; rank 1 is the
  wettest or warmest. February 29 is sampled only in leap years. Each station's
  valid reference start/end and sample count are shown in the rank table and
  adjacent CSV. These are station-specific full-period comparisons, not a shared
  1991–2020 rank baseline. Popup "Highest comparable period" values use this
  same set of eligible calendar-matched windows plus the current period if it
  sets or ties the high. The displayed date is the window's ending date; ties
  show the most recent occurrence. This is not the maximum across every
  possible rolling window in the station record.
  Historical precipitation periods must be complete. Historical temperature
  periods use the same 95% paired-day and two-day maximum-gap rule as current
  periods; the popup reports how many temperature comparison periods are
  partial. This is a project screening policy, not an estimate for missing
  temperatures.
- Recent extremes are the largest daily precipitation, highest maximum
  temperature, and lowest minimum temperature in the latest complete selected
  period. They are rolling-window indicators, **not** the formal annual or
  monthly Climdex indices. Ties use the first date.

The broad station network remains a beta research selection, not a final
publication decision. Before removing the beta label, review source/component changes, product
coverage, late observations, and the complete-window thresholds. The local
preview includes an on-demand daily chart and usable-record summary for the
selected station, but it does not yet provide a full station metadata page.

The repeatable, local [publication-readiness audit](station-publication-readiness.md)
separates unavailable products from calculable products that still need
human station-record review.

## Planned daily-chart interaction (deferred)

Make the selected station's daily plots interactive without changing the
underlying station-screening rules:

- Hover, keyboard focus, or tap a precipitation bar to see its calendar date
  and daily total in inches. Explicitly distinguish trace, missing, and
  quality-flagged reports; never present a missing day as zero.
- Hover, focus, or tap either temperature series to see the date and the
  observed daily high and low in degrees F. Identify missing or flagged values
  rather than connecting a line across them as though observed.
- Offer restrained, optional annotations for extremes in the displayed period:
  the wettest single day and its date, the largest rolling three-day
  precipitation total and its start/end dates, and possibly the highest high
  and lowest low. A three-day annotation should mark the three-day span, not
  imply that its total fell on one bar. Keep annotations sparse so they do not
  obscure the daily data; a toggle or compact summary is acceptable.
- Decide separately whether an extreme is for the currently selected plot
  window, a season, or the station's full period of record. Label the scope,
  completeness requirement, tie rule, and comparison years before publishing
  any ranking or formal WMO/Climdex-style index. The existing recent-extremes
  table is not a formal climate-extremes-index series.

This is a usability and product-scoping request, not yet an implemented chart
feature. Preserve the present static plots until the event definitions and
mobile/accessible interaction are tested.

The source and quality-audit context is in
[station-reference-network.md](station-reference-network.md) and
[station-daily-pilot.md](station-daily-pilot.md).
