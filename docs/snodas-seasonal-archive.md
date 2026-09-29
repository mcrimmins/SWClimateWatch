# SNODAS end-of-season archive pilot

The first archive candidate is a **completed October 1-May 31 snow season**,
identified by the year in which May falls. This is deliberately not a May 31
SWE snapshot: much of Arizona and New Mexico is normally snow-free by then,
so a late-spring snapshot would hide the season's snowpack history.

Two maps are calculated from the paired daily regional SNODAS grids:

- **Peak SWE (inches):** the maximum screened SWE at each cell on any
  available day of that season. All years use the same categorical classes
  as the observed daily SWE pilot.
- **Snow-covered days:** count of days with screened SWE at least 0.1 inch.
  All years use the same 0-1, 1-7, 7-30, 30-60, 60-90, 90-120, 120-180,
  and >180-day classes. This measures snow persistence, not accumulated
  snowfall or an average depth.

Each day screens mismatched SWE/depth cells, then aligns to the common
post-2013 grid. Cells must have valid SWE on at least 90% of *all* October-May
calendar days, including dates known missing from the source inventory.
Otherwise both map values are blank at that cell. A third coverage GeoTIFF
retains the valid-day fraction for diagnosis. The source grids are never
modified. A `quality-summary.csv` records missing days, excluded cells,
high peak SWE, and a PASS/REVIEW/FAIL status. A year with any modeled
peak at or above 50 inches, pairwise exclusions, or missing source dates
requires review; 50 inches is a provisional attention threshold, not a
physical cap.

For a high-peak year, run the separate, unpublished provenance check. It
re-reads only local paired daily grids and records the date and location
of every cell with mapped peak SWE at least 50 inches. It compares the
daily maximum with the saved seasonal maximum, groups touching high cells
into eight-neighbor patches, and counts valid days and days with SWE at
least 75% of that cell's peak within seven calendar days on either side.
The resulting `peak-provenance-cells.csv` and
`peak-provenance-summary.csv` sit next to the archive pilot maps. A
"closer inspection" cue means a map/daily mismatch above 0.005 inch,
fewer than eight valid days in the window, less than 75% near-peak days,
or a patch of fewer than three high cells. These are diagnostic cues,
not an automatic mask or a claim that a brief isolated peak is wrong.
The provenance audit alone does not alter the archive map or its existing
`REVIEW` status; a separately documented exception is required to mask a
source-level outlier.

### Reviewed WY2014 Wolf Creek exception

One WY2014 cell centered near 37.4875°N, 106.7875°W reports a seasonal
peak of 72.87402 inches SWE on April 7, 2014. The original SNODAS archive
reports the same 72.87402 inches SWE and 192.20472 inches depth as the
processed regional grids; their source checksums match. The [Wolf Creek
Summit SNOTEL station (874)](https://wcc.sc.egov.usda.gov/nwcc/site?sitenum=874),
approximately 1.6 km away, [reported 25.5 inches SWE and 71 inches snow
depth on that date](https://wcc.sc.egov.usda.gov/awdbRestApi/services/v1/data?stationTriplets=874%3ACO%3ASNTL&elements=WTEQ%2CSNWD&duration=DAILY&beginDate=2014-03-31&endDate=2014-04-14).
The eight adjacent SNODAS cells have substantially lower seasonal peaks
(roughly 23-33 inches). The source cell persisted across the surrounding
days, so this is not a one-day processing glitch. Its sharp spatial
contrast and the nearby station measurement support masking only this
derived peak-SWE cell while retaining the original daily observations.

### Reviewed WY2016 Promontory exception

One WY2016 cell centered near 34.3708°N, 111.0042°W reports a seasonal
peak of 53.50394 inches SWE. The original March 1, 2016 SNODAS archive
reports the same 53.50394 inches SWE and 131.45669 inches depth as the
processed regional grids; their source checksums match. This is not an
error introduced by clipping or unit conversion. The [Promontory SNOTEL
station (705)](https://wcc.sc.egov.usda.gov/nwcc/site?sitenum=705),
approximately 0.7 km away, [reported 6.1 inches SWE and 14 inches snow
depth on that date](https://wcc.sc.egov.usda.gov/awdbRestApi/services/v1/data?stationTriplets=705%3AAZ%3ASNTL&elements=WTEQ%2CSNWD&duration=DAILY&beginDate=2016-02-25&endDate=2016-03-05).
The eight adjacent SNODAS cells have much lower seasonal peaks (4.9-16.8
inches). A point observation is not proof of the exact grid-cell value, but
this combined evidence warrants a targeted publication mask.

`snodas_seasonal_peak_qc_rules()` records both exceptions. The seasonal
builder changes **only the specified cell in each derived peak-SWE GeoTIFF
and PNG** to NoData. It does not modify raw or processed daily SNODAS
grids, snow-covered-days maps, or other years. Each rule checks the cell's
location and reviewed original peak within 0.01 inch. If input values are
revised or the grid changes, the build stops for renewed review instead of
silently masking a different value. The source signature includes the
applicable rule, and `quality-summary.csv` records its ID and masked-cell
count. Both years remain `REVIEW`, not automatically approved for
publication. No general 50-inch cap is applied: other high peaks require
their own evidence and disposition.

### Review queue across all completed years

The read-only review queue summarizes completed October-May archive years
without recalculating seasonal maps or downloading source data. It writes
`year-summary.csv` and `peak-candidates.csv` under
`data/diagnostics/snodas-seasonal-review/`. The year table keeps missing
inventory dates, paired SWE/depth exclusions, documented peak masks, and
high-SWE candidate counts in separate columns. A missing or checksum-
mismatched archive is labeled `MISSING` or `UNVERIFIED`, not treated as a
zero-issue year. A missing or stale peak-provenance audit is marked
`MISSING_OR_STALE` and its cells are queued for that audit.
`OUTPUTS_VERIFIED` means the saved peak grid and quality report match the
completion marker; this quick report does not re-checksum every daily
input or replace the full archive builder's source verification.

For each still-mapped peak at or above 50 inches, the candidate table
records the peak date and above-threshold patch ID from the provenance
audit, then compares its value with the eight adjacent *seasonal peak*
cells. A
provisional `CHECK_SOURCE` cue requires at least five valid neighbors, a
peak at least 15 inches above their median, and a peak at least 1.5 times
that median. A map/daily mismatch above 0.005 inch also gives this cue.
An isolated one- or two-cell patch at least 10 inches and 1.25 times
above the neighboring median receives the intermediate `CHECK_CONTEXT`
cue, even if it does not meet both sharp-contrast cutoffs.
Weak temporal support means fewer than eight valid days in the 15-day
window or less than 75% of those valid days within 75% of the peak.
`LOCALLY_COHERENT` means none of these cues were found; it is **not** an
independent validation of the modeled SWE. These cutoffs prioritize human
review only. They never mask a cell, alter a quality status, or approve a
year for publication. In particular, a one-cell patch above 50 inches
does not alone imply an outlier: WY2008 has a 50.55-inch cell surrounded
by roughly 40-46-inch cells and sustained nearby-day SWE, unlike WY2014's
much sharper source-level contrast.

Run from the project root in RStudio (no downloads):

```r
source("scripts/load-snodas-seasonal-review.R")
review <- build_snodas_seasonal_review_queue()
review$years[, c("water_year", "archive_state", "quality_status",
                 "known_missing_days", "days_with_pairwise_exclusions",
                 "peak_cells_50in", "peak_audit_state",
                 "sharp_local_contrast_cells",
                 "isolated_moderate_contrast_cells",
                 "provenance_needed_cells")]
subset(review$peaks, review_priority != "LOCALLY_COHERENT")
review$paths
```

### Read-only event-level QC pilot

The second-stage pilot in `R/snodas-seasonal-qc-pilot.R` is a **triage
experiment**, not a new publication gate or an automatic outlier mask. It
starts from checksum-verified seasonal peak maps and their current
peak-provenance audits. The original download files, processed daily grids,
seasonal maps, documented masks, and PASS/REVIEW/FAIL statuses are unchanged.
It writes only diagnostic CSV files under
`data/diagnostics/snodas-seasonal-qc-pilot/`.

For each mapped peak of at least 50 inches, the pilot reads its **peak-day**
regional SWE and snow-depth grids. It compares the cell with eight immediate
neighbors, counts neighbors with at least 75% of its SWE, and compares its
SWE/depth ratio with nearby ratios. Valid snow-free neighbors count in the
SWE comparison; only positive-depth neighbors enter the ratio comparison.
It also compares the peak with the 95th
percentile of the same cell's verified *other-year* seasonal peaks when at
least ten reference years are available. The latter is context, never by
itself grounds to mask or demand manual review: a real wet year can set a
record. The existing 15-day temporal evidence and map/daily agreement are
also used. A peak-day SWE contrast of at least 15 inches and 1.5 times the
neighbor median becomes a review cue only when accompanied by fewer than
two nearby supporting cells, a locally unusual SWE/depth ratio, or weak
temporal support. Map/daily disagreement above 0.005 inch is a separate
review cue. A locally unusual ratio means at least 0.15 above and 1.5 times
the neighbor median ratio. These numerical cutoffs are **provisional pilot
settings**, not physical SWE limits.

The output has four levels: `peaks.csv` preserves individual diagnostics;
`events.csv` groups cells by connected high-SWE patch; `episodes.csv` groups
review patches in a water year whose first peak dates are at most two days
apart; and `years.csv` summarizes coverage, documented masks, and review
counts. `COHERENT_EXTREME` and `CONTEXT_FLAG` do not ask for pixel-by-pixel
inspection. Only `REVIEW_EPISODE` and `NEEDS_EVIDENCE` enter the provisional
manual queue. An unavailable or stale daily file yields `NEEDS_EVIDENCE`,
not a passing result. Already documented WY2014 and WY2016 publication masks
remain visible in `documented_masked_cells` but are not rediscovered from
their masked seasonal peaks.

Run locally in RStudio after the archive and provenance audits are complete
(no network downloads or map rebuilds):

```r
source("scripts/load-snodas-seasonal-qc-pilot.R")
qc_pilot <- build_snodas_seasonal_qc_pilot()
qc_pilot$years[, c("water_year", "archive_state",
                   "documented_masked_cells", "qc_pilot_review_events",
                   "qc_pilot_review_episodes")]
qc_pilot$episodes
qc_pilot$paths
```

For a quick backtest of known cases, pass
`years = c(2005L, 2008L, 2014L, 2016L)`. The pilot still uses all
checksum-verified 2005-2025 archives as its other-year reference. In the
initial local backtest, WY2005's 261 high-peak cells formed 38 connected
patches, of which 10 review patches condensed into four date episodes.
The examined May 19 cell (60.67 inches SWE) was a context flag rather than
a standalone review because two neighbors supported it and the SWE/depth
ratio resembled neighboring cells. WY2008's 50.55-inch coherent peak produced
no review episode; the documented WY2014/WY2016 masks remained unchanged.
The full 21-year output and false-positive burden must be inspected before
this pilot can replace the present 50-inch quality gate. It also does **not**
yet discover relative anomalies below 50 inches, so it is not a universal
operational screen.

### Relative-anomaly discovery pilot (including peaks below 50 inches)

`R/snodas-relative-qc-pilot.R` provides a second, read-only candidate scan.
On every checksum-verified seasonal peak map, it finds cells with peak SWE
of at least 10 inches that exceed the median of at least five valid adjacent
cells by both 10 inches and a factor of 1.5. These are deliberately sensitive
**candidates**, not outliers to erase or a manual-review queue. Connected
candidate cells are counted as patches. The numerical cutoffs are provisional
screening settings, not scientific upper limits for Southwestern SWE.

The saved WY2014 and WY2016 peak maps have one documented mask apiece. For
positive-control backtesting only, the pilot reads the unmodified October-May
daily SWE/depth grids at those two locations, confirms the original peak and
date against the recorded exception value, and restores that value **in
memory** before running the same relative detector. A missing or changed
source value is not silently restored. The output distinguishes candidate
cells, patches, and verified known-mask benchmarks. It does not rewrite a
daily grid, publication map, exception rule, or quality status.

Run from the project root in RStudio (local files only):

```r
source("scripts/load-snodas-relative-qc-pilot.R")
relative_qc <- build_snodas_relative_qc_pilot()
relative_qc$summary[, c("water_year", "archive_state",
                        "relative_candidates",
                        "relative_candidates_under_50in",
                        "relative_patches", "known_masks_detected")]
relative_qc$benchmarks
relative_qc$paths
```

An initial local run across WY2005-WY2025 found 440 candidates, including
403 below 50 inches, in 373 separate patches. Both documented source-level
outliers were detected when their verified original values were restored
in memory. The coherent WY2008 50.55-inch peak did not qualify. WY2005
alone produced 250 candidates; this is precisely why **none** of these
candidate cells should be sent for individual manual inspection or masked
based on the spatial test alone. The episode triage pilot below adds
peak-date temporal evidence, same-day SWE/depth context, and date grouping.
Smooth, broad-area model biases may still evade a local-contrast screen.

### Relative-anomaly episode triage pilot

`R/snodas-relative-qc-triage.R` adds that second stage while remaining
**diagnostic only**. For each relative candidate, it reads the locally
processed October-May SWE/depth pair, rejects invalid pairs, identifies the
daily peak date, checks agreement with the seasonal peak, and measures how
often SWE stayed within 75% of the peak during the surrounding 15 days. On
the peak date it also compares SWE and the SWE/depth ratio with valid adjacent
cells. Snow-free neighbors with zero SWE and depth still count for the SWE
comparison; density ratios use only positive-depth neighbors. Fewer than
five valid adjacent pairs, unavailable daily evidence, or
an unverified source is labeled `NEEDS_EVIDENCE`, never a clean result.

To keep normal mountain gradients out of the manual queue, an isolated
same-day peak needs at least a 15-inch and 1.5-times neighbor contrast
**plus** a stronger cue. One cue is fewer than two supporting neighbors
*and* at least 30 inches and twice the same-day neighbor median; the others
are an unusual SWE/depth ratio or weak temporal support. A seasonal/daily
peak mismatch above 0.005 inch also enters review. The 30-inch/twofold
criterion is a provisional triage setting, calibrated against the documented
WY2014 and WY2016 errors and a snowy WY2005 backtest. It is **not** a
physical limit, a proof of bad data, or an automatic mask. A persistent
SNODAS model artifact can pass the temporal check, while a real topographic
extreme can look spatially isolated.

Review cells are grouped by connected candidate patch **and peak date**;
flagged patch-date events within two days become a review episode. The
candidate table retains `CONTEXT_FLAG` and `COHERENT_EXTREME` cases without
requiring pixel-by-pixel inspection. Separate CSVs under
`data/diagnostics/snodas-relative-qc-triage/` preserve candidates, events,
episodes, year summaries, and the known-mask benchmark. The seasonal maps,
daily grids, documented masks, and archive quality statuses do not change.

Run a small local backtest in RStudio before the full inventory:

```r
source("scripts/load-snodas-relative-qc-triage.R")
triage_check <- build_snodas_relative_qc_triage(
  c(2005L, 2008L, 2014L, 2016L))
triage_check$summary[, c("water_year", "relative_candidates",
                         "review_episodes", "missing_evidence_episodes")]
triage_check$benchmarks[, c("water_year", "source_matched",
                            "relative_detected", "triage_priority")]
triage_check$episodes
```

In that backtest, both known source-level errors were detected and marked
`REVIEW_EVENT`. After counting valid snow-free neighbors, WY2005's 250
relative candidates condensed to three review episodes and no
insufficient-evidence episodes; WY2008 had none. These results support
testing the full 21-year inventory, but two
positive controls cannot establish sensitivity to every outlier type. A
smooth regional bias may evade this local-contrast discovery step. Do not
replace the current publication gate or enable automatic masking based on
this pilot alone.

For the full read-only local run, use
`triage <- build_snodas_relative_qc_triage()` and inspect
`triage$summary`, `triage$episodes`, and `triage$benchmarks`.

### Local episode review report

`R/snodas-relative-qc-report.R` turns saved triage diagnostics into a local
HTML review report. It does **not** rerun the 21-year candidate scan or use
the network. Each expandable episode contains one card per flagged cell:
5-by-5 peak-day SWE and snow-depth neighborhoods, the focal and adjacent-cell
median histories for the seven days before and after the peak, and a table
of exact daily values. Snow-free but valid adjacent cells count in the SWE
and depth medians. The two documented publication-mask locations are labeled
as known reference cases; all other flags remain unclassified. A high
contrast, weak temporal support, or unusual SWE/depth ratio is a review
cue, **not** a declaration that the modeled value is wrong.

After running the full triage, create and open the report from the project
root in RStudio:

```r
source("scripts/load-snodas-relative-qc-report.R")
review_report <- build_snodas_relative_review_report()
browseURL(normalizePath(review_report$paths[["index"]]))
review_report$cells[, c("water_year", "peak_date", "cell",
                        "peak_swe_inches", "known_rule_id", "review_cues")]
```

The HTML and accompanying `review-cells.csv` and `daily-history.csv` are
written only to
`data/diagnostics/snodas-relative-qc-triage/review-report/`. They are local
diagnostics, not website products. The builder checks that every flagged
cell appears in exactly one episode. With the current WY2005-WY2025
inventory, this is six episodes containing nine flagged cells; two are
already documented mask locations, leaving seven values to assess. No
source grids, archive maps, exception rules, or publication statuses are
changed. Retain or mask decisions require independent evidence rather than
an automatic numerical cutoff.

The full WY2005-WY2025 triage was reviewed on September 28, 2026. All seven
newly flagged values were retained after episode-level visual inspection;
neither a new mask nor a blanket threshold was warranted. The existing
WY2014 Wolf Creek and WY2016 Promontory publication masks remain in force.
Six episodes and nine cells were in the diagnostic queue, with no missing-
evidence episodes. This review does **not** turn the source quality labels
from `REVIEW` into `PASS`, nor does it establish that the screen will detect
all future SNODAS artifacts. New flags or revised source grids need a new
review before site staging.

### Staging snow maps on Historic Years pages

The 21 completed WY2005-WY2025 seasonal summaries already contain 42
peak-SWE and snow-covered-day PNGs (about 34 MB total). The local staging
step **copies those existing images** into the Quarto site's generated-map
directory and adds a two-card *Snow season* section to the corresponding
Historic Years pages. It does not recalculate 21 years of daily snow data,
render the Quarto site, upload to S3, or change the source quality labels.
Earlier water years have no SNODAS snow cards.

Before staging, the code requires a current, complete 21-year relative-QC
scan tied to the exact peak-map and quality-report checksums. It verifies
each seasonal output against its completion marker, confirms the two
documented peak masks remain in place, and requires the seven other flagged
cells to match the tracked `retain` decisions in
`config/snodas-seasonal-review-decisions.csv`. A changed map, new flag,
missing evidence, or failed checksum stops staging for renewed review.
`REVIEW` years remain labeled `REVIEW` in their source quality reports;
staging is not a reclassification to `PASS`.

Run this once in RStudio after sourcing the updated code. The first command
refreshes diagnostic checksums but makes no downloads or map changes:

```r
source("scripts/load-snodas-relative-qc-triage.R")
triage <- build_snodas_relative_qc_triage()
source("scripts/stage-snodas-historic-site.R")
pilot_plan <- stage_snodas_historic_site(
  c(2014L, 2024L), dry_run = TRUE)
pilot_plan
```

If the preview shows two valid years, stage just those two for a visual site
check:

```r
stage_snodas_historic_site(c(2014L, 2024L), dry_run = FALSE)
```

The page edit is confined to a marked generated SNODAS section and is
idempotent; existing RONI text and PRISM cards are retained. Re-run staging
after regenerating PRISM archive pages because the PRISM page writer can
replace generated page content. To render the two pilot pages from the
RStudio PowerShell terminal, run `Set-Location site`, then
`quarto render pages/archive/wy2014.qmd` and
`quarto render pages/archive/wy2024.qmd`. Review the local pages before
running the same staging function for `2005:2025` or deploying the site.

To regenerate and check WY2014 locally in RStudio, without a new download:

```r
source("scripts/load-snodas-seasonal-archive.R")
season_2014 <- build_snodas_seasonal_archive_year(2014L)
season_2014$quality[, c("status", "peak_qc_masked_cells",
                       "peak_qc_rule_ids", "peak_cells_for_review")]
peak_2014 <- terra::rast(season_2014$paths[["peak_swe"]])
point <- matrix(c(-106.7875, 37.4875), ncol = 2L)
cell <- terra::cellFromXY(peak_2014, point)
stopifnot(is.na(terra::values(peak_2014, mat = FALSE)[cell]))
source("scripts/load-snodas-seasonal-peak-audit.R")
peak_review_2014 <- audit_snodas_seasonal_peaks(2014L)
peak_review_2014$summary
```

To regenerate and check just this unpublished year locally in RStudio
(roughly the same time as the initial WY2016 build):

```r
source("scripts/load-snodas-seasonal-archive.R")
season_2016 <- build_snodas_seasonal_archive_year(2016L)
season_2016$quality[, c("status", "peak_qc_masked_cells",
                       "peak_qc_rule_ids", "peak_cells_for_review")]
peak_2016 <- terra::rast(season_2016$paths[["peak_swe"]])
point <- matrix(c(-111.0042, 34.3708), ncol = 2L)
cell <- terra::cellFromXY(peak_2016, point)
stopifnot(is.na(terra::values(peak_2016, mat = FALSE)[cell]))
```

After rebuilding, rerun `audit_snodas_seasonal_peaks(2016L)` using
`scripts/load-snodas-seasonal-peak-audit.R` to refresh the provenance
report against the masked peak raster. The audit still reads unmodified
daily source grids and inspects remaining mapped high peaks.

From the project root in RStudio, check WY2017 (no network requests):

```r
source("scripts/load-snodas-seasonal-peak-audit.R")
peak_review_2017 <- audit_snodas_seasonal_peaks(2017L)
peak_review_2017$summary
table(peak_review_2017$cells$peak_date)
subset(peak_review_2017$cells, context == "closer inspection")
```

The builder currently writes only to
`data/diagnostics/snodas-seasonal-archive/wyYYYY/`. It does not add cards
to the historic-year pages or publish maps. This lets us inspect at least
one ordinary and one high-snow year before choosing the final archive
presentation. Re-running a year with unchanged source grids returns its
checksummed outputs without recalculating.

From the project root in RStudio, build and inspect the WY2024 pilot locally:

```r
source("scripts/load-snodas-seasonal-archive.R")
season_2024 <- build_snodas_seasonal_archive_year(2024L)
season_2024$quality
season_2024$paths[c("peak_map", "snow_days_map", "quality")]
```

The calculation reads roughly 244 paired regional days. It reports progress
every 25 days and makes **no network requests**. The PNGs are unpublished
comparison maps. If the result looks useful, the next step is to test a
snowier year, settle the archive card wording, and then build years
WY2005-WY2025 in bounded, resumable batches before connecting them to
Historic Years.

If raster calculation finished but map rendering failed, the three regional
GeoTIFFs may already exist. To avoid repeating all daily reads, use
`resume_partial = TRUE`. This explicitly checks that the grids are newer
than their sources, match the common geometry, and have a complete season
audit whose checksums match the source files. If any check fails, it stops
without trusting the partial files and you must run the full calculation.

```r
season_2024 <- build_snodas_seasonal_archive_year(
  2024L, resume_partial = TRUE
)
```

## Local batch build for the historical archive

Use the batch runner after reviewing the WY2017 and WY2024 pilots. It
builds one year at a time from local processed SWE/depth grids and makes
**no network requests**. You must supply the water years explicitly.
Source the loader from the project root in RStudio, preview the selected
years, then run a bounded first batch:

```r
source("scripts/load-snodas-seasonal-archive-batch.R")
run_snodas_seasonal_archive_batch(2005:2025, dry_run = TRUE)
archive_batch <- run_snodas_seasonal_archive_batch(
  2005:2025, max_new_years = 2L
)
archive_batch$results[, c("water_year", "event", "quality_status",
                          "elapsed_seconds", "note")]
```

Re-run that same call to build the next two unfinished years. Already
current years do not use the two-year limit: the underlying builder
verifies source and output checksums before skipping them. For an
unattended local run, omit `max_new_years` or set it to `Inf`. Errors are
recorded, and the runner continues to later years by default. To stop
at the first error, use `continue_on_error = FALSE`. A current year's
`REVIEW` quality status is retained in the output; it is not treated as
a computation error or approval for publication.

Every attempted year is checkpointed in
`data/diagnostics/snodas-seasonal-archive/batch-log.csv`. If RStudio or
Windows stops mid-year, rerun the same call. Completed years are skipped.
When all three seasonal rasters exist but the completion marker does not,
the runner asks the builder to verify and reuse those partial rasters;
if they are stale or lack a matching full-season audit, that year is
logged as an error rather than silently trusted. The outputs remain in
the diagnostics tree and are **not** added to Historic Years or deployed
by this command.
