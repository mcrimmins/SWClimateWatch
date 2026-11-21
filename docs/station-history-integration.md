# Selected Station history tabs — local review

The local preview adds **Current conditions** and **Explore station history**
inside Selected Station. Current conditions is the default and retains the
daily charts, normals, records, historical standing, seasonal comparisons and
monthly climatology. Opening history loads only the selected station's index
and the years needed for the selected dates, using the existing custom-date
pilot and worker.

```r
setwd("C:/Users/Crimmins/RProjects/SWClimateWatch")
source("scripts/build-station-history-integration.R")
source("scripts/check-station-history-csv.R")
source("scripts/preview-station-history-integration.R")
```

The preview is served at http://127.0.0.1:8786/. Build and preview in RStudio.
The build command now defaults to a guarded **layout-only refresh** when a
verified combined snapshot already exists. It compares current embedded data,
the station summary/detail files, the history catalog and compact build markers;
changed data require an explicit full rebuild. It does not read/recalculate
every annual history file just to change HTML, JavaScript or CSS. Measured
layout refreshes took 0.94–9.64 seconds, compared with the earlier 508-second
combined snapshot rebuild. No observations are downloaded. The snapshot lives in
`data/diagnostics/station-history-integration`, separate from `site/stations`.
It uses the standard diagnostic station snapshot, which must already include
monthly climatology and daily precipitation records. Both snapshots currently
use observations through November 3, 2026; this work does not refresh inputs.

After changing the input caches, rebuild the historical pilot as appropriate,
then explicitly rebuild the full combined snapshot:

```r
source("scripts/load-station-custom-dates-pilot.R")
source("R/station-history-integration.R")
build_station_history_integration(mode = "full")
```

Before staging, run the independent full payload check (the fast layout refresh
does not replace this check):

```r
source("scripts/check-station-history-integration.R")
```

The full snapshot builder also omits the unused old `cumulative/` pilot folder
and reuses source hashes within a build, avoiding redundant scans. It retains
the seasonal viewer and the Leaflet attribution/license. Full byte validation
remains deliberately separate from routine layout review.

## CSV verification and browser save check

`scripts/check-station-history-csv.R` runs the exact browser worker/serializer,
then independently reads the CSVs in R and compares every date, identity,
numeric value, blank and quality label against the annual source files. Tests
also cover flagged values, trace zero, cancellation, stale exports and the
prepared-file fallback. Diagnostic outputs are in
`data/diagnostics/station-history-csv-check`.

Real cases passed: Anvil Ranch's 30 days (six missing temperature values),
Tucson's 30 days (three trace days), and Yuma's complete 55,094-row record
(2,132 trace days and 2,082 missing numeric fields). The CSV retains daily
resolution even when the plot groups dates.

The integrated browser showed the correct prepared filename/date range and
row count for short and full-record exports. Automated retrieval of the saved
browser download was blocked by the browser tooling: embedded blob retrieval
is unsupported, and top-level capture stalled. The user confirmed **both
browser downloads passed on November 21**. For a repeat save check in
your normal browser, download one short period and Yuma's Full record; if the
automatic save does not start, click **Save prepared CSV**. After each save:

```r
# The function is loaded by check-station-history-csv.R above.
validate_station_history_csv_download()
```

Choose the downloaded file, preserving its original filename. R should report
PASS. Changing dates or stations removes the prepared-file link, preventing an
older selection from being downloaded accidentally.

## Narrow-screen review, November 20

Tested the integrated page at an observed width of 375 CSS pixels on the laptop
browser. Both page and history frame had no horizontal overflow; charts stack
vertically, tables fit, and keyboard selection updates both readouts. Canvas
labels now use the displayed chart width and device pixel ratio rather than
being squeezed from a fixed 1,000-pixel bitmap. The viewport override was reset
after testing.

Measured 30-day load: 171 ms, worker 0.9 ms, render 5.4 ms. Yuma's full record:
151 annual requests / 823,355 uncompressed bytes, 7.745 s load, worker 63.5 ms,
render 10.2 ms, 599 displayed intervals. Repeating the full selection took
3.8 ms with no requests. These are laptop/localhost results at phone width;
physical phone hardware and slower networks have not been measured. See
`narrow-performance.json` and `narrow-history-tables.jpg` under the integration
diagnostics directory.

## Linkage and efficiency

- History has no separate station picker: it follows Selected Station.
- Custom dates are independent of the map's summary period. Changing that
  preset updates Current conditions while preserving the historical selection.
- Changing station discards the previous history frame and worker. Closing the
  detail panel discards history and resets the preferred tab to Current conditions.
- Current conditions does not request historical payloads before history is opened.
- The history worker, four-request concurrency, annual-file cache, bounded plots,
  coverage rules and CSV generator are shared with the standalone pilot.
- Both historical plots share a selected day or displayed interval. Hover or
  click either chart, use its previous/next buttons, or focus it and use the
  arrow keys (Home/End jump to the bounds). A shaded band marks the selection
  on both plots. Each plot has a table below it with the same selected dates,
  values and coverage. Trace, missing and flagged precipitation are distinct;
  long-period tables label grouped totals/subtotals and paired-day averages.
- Custom periods show observed statistics, not the preset period's historical
  ranks, temperature normals or record comparisons. The page states this explicitly.

## Local verification, November 20

The combined build verified 62 station records and 5,948 historical annual
chunks, preserved current station detail payloads, and passed publication file
checks. The initial combined snapshot copy took about six minutes; this is a
local review build, not an addition to the daily workflow.

Controller checks cover lazy loading, unchanged current content, preset
independence, selected-station changes, message guards, keyboard tabs and
closing cleanup. Six R copy/reuse assertions passed. Existing chart-tool,
temperature-normal and monthly-climatology JavaScript tests also passed.

Browser checks confirmed Anvil Ranch's custom 2000 calendar-year selection
survived changing the current summary from 30 to 7 days. Selecting Tucson
loaded Tucson's history, and closing/reopening restored Current conditions
without a historical frame. Browser CSV saving was confirmed by the user on
November 21. Physical-phone/network performance and a full-network VM new-date
benchmark remain review items before daily integration. Nothing is enabled in the daily
runner by these scripts.

The linked historical table tests also cover leap-day selection, missing and
flagged observations, trace values, both navigation bounds, keyboard/click
selection and incomplete grouped intervals. Moving within a chart uses the
already loaded display intervals and makes no new history requests.
