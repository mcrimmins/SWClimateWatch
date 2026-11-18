# Station explorer and public page

The local research preview builds the interactive RCC-ACIS station map and
tabbed tables. A screened snapshot is also staged as the public Station
Conditions page, with a guarded refresh in the daily update. It uses the 62 unique station records in the
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
the public station page calls its bounded updater and publication screen internally.
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
- Hover for the selected map metric, its departure when applicable, and a
  brief data-caution indicator. Click or tap a fixed-station label for a
  larger bubble with station ID, selected value,
  departure, rank, comparison years, data coverage, and any reason the selected
  value is unavailable. Available values are numbered; unavailable stations
  are small muted dots by default, with an option to label them. Nearby
  numbered labels become colored dots until you zoom in. All dots remain
  clickable. A basemap toggle can remove tile detail when it is too busy.
  Search, state, and value-availability filters act on both map and tables.
- The tables are numerically sortable and have three tabs: current values,
  percentiles and ranks, and recent daily/three-day extremes. ThreadEx series are
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
- Recent extremes are the wettest day, wettest three consecutive days, highest
  maximum temperature, and lowest minimum temperature in the selected period.
  Each requires a complete, unflagged daily series for its variable. The
  three-day total reports both start and end dates and uses trace as zero.
  Ties use the earliest occurrence. These are rolling-window indicators,
  **not** historical records or formal annual/monthly Climdex indices.
- Additional frequency and persistence indicators count unusually hot days
  (maximum temperature above the station's centered-five-day 1991–2020 90th
  percentile), unusually warm nights (minimum temperature above the matching
  threshold), the longest unusually hot run, and the longest dry run (<0.04
  inch per day). These use the selected period and require complete, unflagged
  observations and, for temperature, at least 15 baseline years for every day.
- Freeze nights use minimum temperature at or below 32°F during the latest
  October–March cool season. Through March the count is season-to-date; from
  April through September the completed season remains shown. Its departure
  is observed count minus the mean count for matching season-to-date periods
  in at least 15 complete 1991–2020 seasons. Positive means more freeze nights
  than average. Incomplete current seasons or inadequate historical coverage
  are withheld rather than treating missing nights as nonfreezing.

The broad station network remains subject to source/component changes, product
coverage limits, late observations, and complete-window thresholds. The local
preview includes an on-demand daily chart and usable-record summary for the
selected station, but it does not yet provide a full station metadata page.

The repeatable, local [publication-readiness audit](station-publication-readiness.md)
separates unavailable products from calculable products that still need
human station-record review.

## Local pilot: cumulative water-year precipitation (November 3, 2026)

The standalone three-station pilot is separate from the public Station
Conditions page and daily publisher. It reads existing fixed-station caches
for Tucson International Airport (29687), Phoenix Airport (1403), and Albuquerque
International Airport (19376); it does not request ACIS data.

From the project root in RStudio:

```r
source("scripts/build-station-cumulative-pilot.R")
source("scripts/serve-station-cumulative-pilot.R")
```

The preview opens at `http://127.0.0.1:8770/`; output is under
`data/diagnostics/station-cumulative-pilot/`. The serving script reuses an
already running cumulative preview on that port. Rebuild and refresh the
browser to see changes. If another application owns the port, choose a new
one with `serve_station_cumulative_pilot(port = 8771)`; no existing server is stopped.
The initial laptop snapshot ends October 6, 2026; it is labeled as cached data,
not a current operational snapshot. Current-date changes require newer station
caches, not changes to the plot's calendar.

The plot shows the current water year's cumulative precipitation, a selected
complete historical water year (defaulting to the previous year when eligible),
and mean of complete WY1991-WY2020 cumulative curves. A pale band shows their
pointwise 25th-75th percentiles (quantile type 8), with at least 20 complete
baseline years. This is a historical distribution range, not an uncertainty or
forecast interval; quantiles are calculated from cumulative totals at each date,
not summed daily quantiles. All three initial stations support all 30 baseline
years. Season-to-date and full-water-year views share hover/tap readouts and an
accessible date slider. Future comparison curves are historical context, not
forecasts. Month/day alignment omits a separate February 29 position but includes
its rainfall in March 1 and subsequent totals.

Trace precipitation contributes zero; other quality flags, multi-day accumulated
reports and invalid/missing values are unusable. A cumulative line stops at the
first unusable day rather than filling it with zero or resuming a misleading
complete total. Subsequent known amounts are identified in the readout as an
observed lower bound with missing/flagged counts. Reference years must be
complete for the entire water year so the mean curve's sample remains constant.

The historical dropdown includes only fully complete past water years from
each cached record, with no large collection of colored background lines.
The default previous-year series is already in the station payload; additional
years are fetched only on selection and cached in the browser. Failed or stale
comparison requests do not replace the selected station/year or remove its
current/reference curves. An explicit None option hides the comparison.

The pilot also adds two thin dotted historical high/low boundaries using all
eligible complete historical years, not only the normal-period sample. Hover
readouts show each boundary's value, record years and ties; the winning year may
change along a boundary. A status row compares current accumulation through the
latest plotted date with those bounds, distinguishing above/below range, ties
and unavailable current data. These are records among the stated complete-year
sample, not all-time claims over incomplete or unsupported station years.

Closest match is a dropdown option based on root-mean-square difference between
calendar-matched cumulative progressions from October 1 through the latest
plotted observation date, not just similarity of the final total. It requires
complete current accumulation and at least 20 complete historical years.
Errors are in inches; the method does not normalize by annual totals or use
future current-year data. A numerical tolerance of 0.000001 inch resolves
floating-point ties for both record comparisons and matching. The most recent
tied match is displayed, with the tie count; matches before 30 aligned dates
carry an early-season note. The matched year is descriptive, not a forecast.
The existing 365-position month/day alignment and leap-day convention apply;
the displayed matching cutoff is explicit if February 29 is not a separate point.

Initial three-line build: about 3 seconds and 77 KB per station. With the band
and historical selection: about 9 seconds, 94-98 KB per station, and 291 small
historical curve files totaling approximately 0.54 MB for all three stations.
With record boundaries, year annotations and closest-match metadata, the main
station files are approximately 139-144 KB each; the historical curve files are
unchanged. Context calculation reuses already screened historical curves and
adds no downloads. No full collection of historical curves is fetched in the browser.
Unchanged JSON files are not rewritten. `history-audit.csv` records excluded
years and missing/flagged counts. These are local pilot costs, not a benchmark
for full-network daily integration. Tests cover missing/flagged
days, traces, baseline eligibility, leap-day accumulation, future values, line
gaps, browser inspection, caching, failed requests and station-selection races:
Record and matching tests also cover changing record years, ties, sparse or
incomplete data, and a case where the closest progression differs from the
closest ending total.

```r
testthat::test_dir("tests/testthat", filter = "^acis-station-cumulative-pilot$")
```

```bash
node tests/test-station-cumulative-ui.cjs
```

Next after visual review: choose placement in station details; cache baseline
and historical calculations independently from current-year refreshes; consider
optional very faint background curves; test stations with incomplete records; then assess full
network payload/runtime before staging. This pilot does not change publication.

## Future scope: custom date periods

Backlog entry, October 25, 2026. Assess a start/end-date selector in addition
to the existing summary-period presets; no UI or processing change is authorized
by this note. Runtime, published size and browser responsiveness are constraints.

- Start with dates bounded to the recent daily series already exported in
  on-demand station detail JSON (currently the longest supported rolling window).
  Basic observed totals/means and eligible recent extremes could be calculated
  from those values without new station-history downloads. This still needs a
  browser/payload benchmark and is not a promise of zero update or browser cost.
- Decide whether the first version is selected-station-only or changes the
  whole network map and table. The latter needs daily data for all displayed
  stations, unlike the current on-demand detail view. Load/cache it only when
  custom mode is selected; retain the lightweight preset startup path.
- Preserve current precipitation completeness/lower-bound rules, paired-day
  temperature thresholds, flags and notation. Specify their behavior for custom
  durations, one-day windows and maximum allowed range; do not silently apply
  a permissive long-window missing-day rule to a short event. Test agreement
  between browser calculations and the existing R definitions.
- Arbitrary-date departures, percentiles and ranks need matching historical
  windows and support checks. Existing preset summaries cannot be interpolated
  into valid custom-period comparisons. Initially withhold unavailable
  comparisons with an explicit explanation. A later approved design could use
  constrained precomputed periods or a separate on-demand service; do not ship
  full historical daily records or precompute every start/end combination.
- Keep seasonal freeze-night counts explicitly tied to October-March, rather
  than silently redefining that indicator when custom dates change.
- Before implementation, benchmark a few representative ranges across the full
  network: transfer bytes, additional published size, update time, browser memory
  and calculation/interaction latency on desktop and a mobile-class device.
  Include missing/flagged/stale stations, leap days and month/year boundaries.
- Review the scope and cost with the user, then prototype locally. No production
  or daily-workflow integration until the performance limits and statistical
  behavior are approved.

## Daily-chart interaction

Hover, focus, or tap a chart day to see its date and precipitation total or
daily high and low in a readout below the chart. Trace precipitation, missing
observations, and quality-flagged values are distinguished; missing is never
shown as zero. The temperature lines retain gaps for unavailable values.
Keyboard users can move by date with the left and right arrows and jump to
the first or last date with Home or End. Previous/next-day buttons also let
touch users inspect narrow daily marks in longer periods. This changes
presentation only, not station screening.

## Selected-period extreme annotations

The detail view puts four extremes in a compact summary below the charts.
The precipitation chart marks the wettest day and shades the full three-day
span; the temperature chart marks the highest high and lowest low. Hover and
keyboard readouts identify the marked dates. Incomplete periods show an
unavailable extreme instead of a potentially understated maximum. The
three-day calculation uses only consecutive daily observations, not a
three-day total assigned to a single bar.

Seasonal and full-period-of-record extremes, comparison-year rankings, and
formal WMO/Climdex-style indices remain separate future products. They need
their own period, completeness, tie, and comparison-year definitions before
publication.

The source and quality-audit context is in
[station-reference-network.md](station-reference-network.md) and
[station-daily-pilot.md](station-daily-pilot.md).

## Cumulative plot integration (local review, November 3, 2026)

The selected station detail now includes the water-year cumulative plot beneath
its daily charts, for all 62 cached fixed-station and ThreadEx records. The map
and table summary-period selector still controls daily plots and period metrics;
the cumulative plot explicitly remains October 1–September 30. Its own selector
switches season-to-date/full-year display, with historical high/low bounds,
1991–2020 mean and middle-50% band, historical-year selection and closest
progression. Current gaps stop complete totals; missing station caches and
insufficient baseline/history support receive explicit unavailable messages.

The explorer build and daily station updater generate these files from cached
observations without additional ACIS requests. Historical screening and
reference curves are cached in
`data/processed/acis-stations/cumulative-history/`, keyed by historical
precipitation content, station identity, water year and calculation version.
Past revisions or October rollover invalidate them; current-year revisions
refresh the current curve and closest match without rescreening past years.
The browser loads only the selected station payload and one comparison curve
at a time. The parent passes station identity and page date to the embedded
plot; unknown stations/date mismatches cannot silently show a different plot.
Staging copies the cumulative directory, and staging and rendered-site
validation require station payloads and the catalogued comparison files.

To refresh the integrated preview from existing caches (no downloads or upload):

```r
source("scripts/build-acis-station-cumulative.R")
source("scripts/refresh-acis-station-explorer-preview.R")
source("scripts/serve-acis-station-explorer-prototype.R")
```

Select a station on the map or in a table, then scroll below its daily plots.
The earlier three-airport standalone prototype remains available for isolated
plot experiments. The cumulative integration is live as of November 4; the
historical-total chart described below is a subsequent local increment.

The full-network local benchmark produced about 16 MB of cumulative JSON
(3,902 files, including the main station payloads and catalog). A repeat build
reused all 62 historical/reference caches in about 29 seconds, with no ACIS
requests. This measures the cumulative stage only, not full publication. Browser
startup does not fetch this collection; files are requested for a selected station
and comparison year. Production integration was confirmed by the user on November 4;
the benchmark above remains a laptop measurement.

## Historical water-year totals (November 4 local increment)

Below the cumulative plot, completed water years now appear as interactive
precipitation-total bars. This reuses `comparison_years` annual totals already
present in each station's small payload; no additional daily histories,
downloads, historical-curve requests or numerical fitting are introduced.
Small `annual_history` metadata adds the cached record's starting year,
missing/incomplete years and supported full-year normal. The current year
is a hatched bar, labeled season to date with its observation cutoff and any
lower-bound caution. It remains excluded from completed-year comparisons.

The normal is the endpoint of the supported complete-WY1991–WY2020 mean
cumulative curve. It is withheld below 20 complete baseline years. Hover/tap or
keyboard slider inspection reports year, inches and percent of that full-year
average; percent is unavailable if the normal is missing or zero. Above/below
average colors describe amounts, not statistical rarity. Incomplete/flagged
years are gaps rather than zero bars. No trend or record-homogeneity claim is
made. Seasonal periods and regional summaries remain future increments.

Refresh with `scripts/build-acis-station-cumulative.R`; the normal daily
station builder includes this update automatically. Review locally, then stage
before explicit production promotion. The same integrated preview is served
from the station explorer directory.
