# Daily Explorer local storm report pilot

Local review started November 22, 2026. No production runner, cron, navigation,
publication or warning-polygon changes are enabled by these scripts.

## Build and preview

Run in RStudio from the SWClimateWatch project root:

```r
source("scripts/build-daily-explorer-storm-reports-pilot.R")
source("scripts/test-storm-reports-pilot.R")
source("scripts/preview-daily-explorer-storm-reports.R")
```

Open <http://127.0.0.1:8796/>. The default source is the already built local
`site/daily-explorer` data/maps. Override it with
`options(swc.storm.source_dir="data/diagnostics/daily-explorer")` only if that
separate cached Explorer is the one intended for review. No PRISM rebuild is
required. The pilot copies existing PNGs once, then skips unchanged copies.

The initial laptop review contains September 1–October 5, 2026, matching its
existing Explorer cache. Adding the preceding UTC date (August 31) to support
the first PRISM window gives 36 daily report payloads and 338 retained reports
(exact duplicates removed), all with mapped positions. September 29 is a useful
populated-day example. Counts change between PRISM and UTC timing because the
event windows differ; an empty UTC date does not imply an empty PRISM window.
These counts describe a retrieved snapshot, not a completeness claim.

The first build makes one bounded request covering at most 62 Explorer dates
and one request for the preceding UTC date. Existing pilots reuse their larger
cache and fetch only the extra preceding day. Reruns reuse both raw caches
without requests. The catalog records both retrieval times; its general
provenance line conservatively shows the oldest snapshot. An explicit refresh is:

```r
options(swc.storm.refresh=TRUE)
source("scripts/build-daily-explorer-storm-reports-pilot.R")
options(swc.storm.refresh=FALSE)
```

No NWS/IEM key is needed. The test script also runs controller checks with Node
if available, including the existing `swc.interactive.node` override. Serving
reuses port 8796 only when the server identifies itself as this pilot; an
unrelated listener is not stopped.

## Interactions and layout

- The report date and previous/next controls update the shared Explorer date,
  including year/season adjustments. The timeline and main date controls update
  reports in the other direction. Invalid/out-of-cache dates do not substitute
  a neighboring report date.
- The Explorer summary-region control filters report markers and rows to AZ,
  NM or both. Variable, temperature view and PNG comparison selections do not
  discard hazard types or change report dates.
- Reports have their own selected-day / trailing-7-day / trailing-30-day window.
  This intentionally differs from the PNG comparison's centered seven-day
  browsing window; the UI explains the distinction. Both end dates stay linked.
- The Daily regional conditions timeline includes a daily report-count strip
  beneath each climate bar, plus colored indicators for report categories.
  Hover/focus gives exact counts by report type and the event-time window;
  clicking still selects that Explorer day. Counts follow AZ/NM region and
  PRISM/UTC timing, remain daily regardless of the report panel's trailing window,
  and include all report types independent of its type/search filters. A plus
  marks a partial known count; ? is unavailable and 0 is a retrieved empty
  result. Counts mean reports, not unique storms or reporting completeness.
  The small catalog summary serves this strip without loading daily detail
  files. Re-rendering climate metrics, seasons or Map view rebuilds indicators
  even when the selected date has not changed. This remains pilot-only.
- Report timing defaults to **Match precipitation map**, ending at 12:00 UTC on
  the labeled map date for all three report-window lengths. **UTC calendar day**
  is available explicitly. An always-visible caption shows exact start/end UTC
  timestamps. Changing timing never moves the Explorer date, changes original
  event timestamps or silently changes the PNG/weather windows.
- Report type and text search apply to both map and table. A selected report
  type persists across dates with no reports of that type, visibly indicating
  that the result is empty. The status distinguishes total reports before
  filters from the matching report count below.
- Hover/focus a marker for a brief type, magnitude (when supplied), location and
  time preview anchored inside the map. Hover never selects, scrolls the table,
  pans the map or changes the full details. Moving away dismisses the preview.
- Click/tap a marker or any table row to pin one report in the **Selected report**
  section below the map. No Leaflet popup or native marker-title tooltip competes
  with this panel. Table selection pans to its marker; marker selection brings
  the corresponding table page into view without scrolling the whole page.
  Keyboard users activate the row button or marker with Enter. Focusing alone
  does not select. Full text, reporting source, qualifier and bulletin link have
  one permanent location. Clear selection resets both marker and row highlights.
- Exact coincident report positions share a numbered marker. Clicking it opens
  a report chooser below the map; the prior selection stays pinned until a
  report is chosen. The chooser respects current type/search/date/region filters.
  Nearby positions remain geographically distinct, with map zoom and the table
  available to distinguish them. No location offsets or event merging are used.
- **Reports in view** is a collapsible panel beside the map on desktop and below
  it on narrow screens. It counts individual reports within the map bounds after
  date/window/timing, region, report-type and text filters. It shows the matching
  total, outside-map count and reports without usable coordinates separately.
  Panning/zooming changes this panel, while the table retains all matching rows.
  Clicking a type count applies the existing type filter. All types resets only
  that filter, retaining text search, dates/timing, region and the map extent.
  Fit map to matching reports fits all located filtered reports without clearing
  those filters.
- The panel links the largest reported rainfall, hail size and wind gust to the
  existing pinned selection and table row. It retains tied reports individually,
  displays event time and measured/estimated qualifier, and never sums rainfall.
  Comparison uses source numeric magnitudes with recognized units: rain/hail in
  inches or converted millimeters, wind gusts in mph or converted knots, m/s or
  km/h. Missing/unknown units and nonnumeric/negative values are excluded from
  extrema but remain counted as reports. Wind damage/downburst narratives do not
  become gust measurements. Accumulation durations can differ, so these are
  reported maxima in the view, not standardized daily amounts or climate records.
  Partial/unavailable time coverage remains explicit. Bounds changes use loaded
  reports and do not request more observation data.
- Map markers use labeled category colors (a number indicates multiple reports,
  potentially of different types). The table renders 40 rows per page, with internal scrolling at
  narrow widths and no whole-page horizontal overflow in the local phone test.
- Rainfall, flash floods and other floods have separate categories: green amount
  labels for individual rain reports with source-supplied inch units, orange FF
  markers for flash floods, and blue F markers for floods. Compact 26 × 18 px
  rain labels show whole-inch lower bounds (4.29 inches becomes 4+), <1 for
  positive amounts below one inch, and 0 for zero. The legend explains these
  labels; hover and selected details retain the exact source precision and
  units. No reporting duration is inferred.
  Other or absent units remain in details and use an R marker instead of an
  invented inch value. Numbered shared-location circles remain report counts;
  mixed-category locations use a neutral color and the report chooser.
- Only the requested daily report JSON files are loaded. Requests already in
  flight are reused; a stale response cannot replace a newly selected date.
  Failed files can retry on a later selection. Closed report sections defer
  loading daily files until opened. Map tiles require an internet connection;
  cached report/table content does not depend on basemap availability.

## Source and interpretation

Source: NWS-issued Local Storm Reports archived by Iowa Environmental Mesonet.
The [GeoJSON service documentation](https://mesonet.agron.iastate.edu/geojson/lsr.py?help=)
documents the `states`, `sts` and `ets` parameters and source `product_id`.
The [archive documentation](https://mesonet.agron.iastate.edu/request/gis/lsrs.phtml)
states that the archive is incomplete and unofficial, and that its times are
event-valid times rather than text issuance times. The
[WPC viewer](https://www.wpc.ncep.noaa.gov/exper/lsr/lsr.php) inspired the
report-marker interaction; no WPC assets are copied.

The [PRISM day definition](https://prism.oregonstate.edu/documents/PRISM_update_schedule.pdf)
uses the 24 hours ending at 12:00 UTC on the labeled date. In default map-matching
mode, an N-day report window is [map date minus N days at 12:00 UTC, map date at
12:00 UTC). These endpoints are 5 a.m. MST / 6 a.m. MDT. UTC-calendar mode is
[map date minus N−1 days at 00:00 UTC, next date at 00:00 UTC). Exact boundaries
are enforced locally regardless of endpoint inclusion behavior, with the start
included and end excluded. Daily UTC files intersecting the requested interval
are loaded and then filtered by full event timestamps, including both boundary
dates in PRISM mode. Missing files flag their intersecting time ranges, merged
when contiguous, rather than implying zero reports. Delayed reports use their
reported event time; issuance time remains available through the original
bulletin. Magnitudes and units are preserved from the GeoJSON source, including
zero and absent magnitudes. No generic wind/rain unit conversion is imposed.

Response row IDs are not stable event IDs. Exact duplicates are removed using a
hash of retained fields, including source bulletin and text. Different bulletins
or amended report text are retained. Counts therefore mean reports, not unique
storms, damage footprints or unique impacts. Corrected/superseded report grouping
needs separate assessment before any storm-count statistics are introduced.

Successful empty FeatureCollections are different from failed/malformed data.
Every expected UTC day receives an explicit READY/EMPTY manifest entry. Missing
catalog entries or failed daily requests appear as unavailable/partial coverage,
never a fabricated zero. Invalid event times fail normalization. Reports without
usable coordinates remain in the table with an explicit position notice.
Remote text is rendered with `textContent`; bulletin URLs are constructed from a
validated source product ID and the documented NWS text retrieval endpoint.

## Remaining before staging

Review the local layout and desired event-day convention with the user, including
whether to offer a future local-day view. Then assess incremental recent-date
refresh for delayed/corrected reports, source retries, publication checks,
retention and last-good fallback. Those are necessary for unattended publication
but are not enabled in this pilot. Warning polygons remain a separate increment.
