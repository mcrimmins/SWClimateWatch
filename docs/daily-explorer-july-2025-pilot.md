# Full July 2025 Daily Explorer benchmark

This is an isolated local benchmark under
`data/diagnostics/daily-explorer-july-2025/`. No site files, cron settings or
S3 objects are changed. It expands the previously reviewed PRISM navigation
samples to all 31 July dates and adds the existing weather/event suite.

## Measured local results

User-reported November 24 validation passed: 31 dates, 217 PRISM maps, 93 daily
weather maps, 186 weather-mean maps, 360 reports over 32 report dates and 856
hazards. All 103 policy/cache checks also passed. The preview was served
successfully; detailed browser payload/memory measurements remain separate.

Successful preparation batches totaled 437.286 seconds (7m 17s), 1,560 requests
and 126,359,015 downloaded bytes. Build batches totaled 1,155.080 seconds
(19m 15s), including six event requests. Combined recorded work was 26m 32s;
user pauses and subsequent validation/preview are excluded. Existing July
sample PRISM maps were reusable, so this is not a completely cold rebuild.
The final summary's 133.987 seconds and nine built/84 reused weather periods
refer to its last call, not the entire benchmark. The final run-history call
also includes storage/reporting overhead after the summary timer was captured.

The reported viewer size is about 191.6 MB; all recorded storage categories
sum to 610.5 MB, including working copies and selected shared weather inputs.
This excludes additional raw event archives/cache metadata. Viewer totals
include duplicate versioned assets and other locally copied files; they are
not the initial browser transfer. The small difference between build-summary
and storage viewer bytes comes from the release manifest written after the
summary's file list was gathered. Use these results for initial planning,
then assess archive integration and other seasons before bulk expansion.

The July viewer is a companion full-month benchmark with July fixed as its
month, using the usual Explorer date/variable/region/map-view controls. The
multi-year/month navigation and retention pilot remains separate. Wiring
all-source month partitions into that archive shell follows review of this
benchmark; this does not yet create a multi-year published Explorer.

## Inputs and bounds

- PRISM uses cached daily grids and existing 1991–2020 reference methods;
  there are no PRISM requests. The seven prior July sample dates can seed
  this build, with their signatures rechecked before reuse.
- CORe needs June 2–July 31: 60 complete daily input dates so July 1's trailing
  30-day mean is complete. Required inputs are HGT500, PWAT, U250/V250, sea-level
  pressure and U850/V850. Surface-pressure daily/eight-sample inputs retain
  existing screening guards; missing optional terrain inputs withhold affected
  overlays rather than substituting terrain or filling missing values.
- Preparation handles at most ten new dates per call. Per date, selected core
  downloads are capped at eight requests/four MB; overlay/index/recovery work
  is capped at 80 requests/15 MB. These are safety ceilings, not size forecasts.
  The first download can be substantial; files are cached and each successful
  date is checkpointed. Request/time history is recorded for completed batches.
- Rendering defaults to seven new endpoints per call; complete period markers
  and hashes allow interruption/reuse. Rendering requests no weather data.
- Event assembly requests at most two report windows and four hazard queries
  on the first build, then reuses caches. June 30 supports noon-UTC alignment;
  the existing IEM carry-in/lifecycle/non-VTEC coverage caveats remain visible.
  An upstream error stops the build; it is never converted to zero events.

## Run locally

From the project root in RStudio:

```r
options(swc.july.download = TRUE)
for (batch in seq_len(6)) {
  source("scripts/prepare-daily-explorer-july-2025.R")
  if (july_inputs$status == "READY") break
}
stopifnot(july_inputs$status == "READY")

for (batch in seq_len(5)) {
  source("scripts/build-daily-explorer-july-2025.R")
  if (july_build$status == "READY") break
}
stopifnot(july_build$status == "READY")

options(swc.july.download = FALSE)
source("scripts/test-daily-explorer-july-2025.R")
source("scripts/preview-daily-explorer-july-2025.R")
```

Open `http://127.0.0.1:8800/`. Existing input files, decoded caches and completed
periods are verified before reuse. If interrupted or a source request fails,
rerun the same preparation/build blocks; completed verified work is retained.
Use `options(swc.july.max_input_dates=3L)` or
`options(swc.july.max_end_dates=2L)` for smaller jobs, then rerun enough times
to reach READY. A single explicit render job can allow 31 endpoints instead.
Keep options at their defaults when using the six/five iteration counts above.

Expected maps: 217 PRISM + 93 daily weather + 186 weather means = **496**.
The final viewer is marked complete only after all dates/periods are present.
The validator checks all July dates and seven PRISM maps per date, exact
weather windows and hashes, all 62 means, 32 report dates, event/geometry
references, both timing/region/type timeline summaries and versioned assets.
The viewer retains storm reports, hazards, linked selection, both timeline
rows and daily/7-/30-day weather selection.

## Review and workload reports

Check July 1's 30-day weather mean (starts June 2), July 31, wet/quiet days,
both event timing modes, type/reset controls and links, and regional/variable
changes. Winds may be withheld where the surface-screening data are incomplete;
that is independent of whether the mean meteorological fields are complete.

Reports under the pilot root include:

| File | Meaning |
| --- | --- |
| `input-plan.csv` | Sixty input-date checkpoints; recomputed from verified files on rerun. |
| `last-preparation.csv`, `run-history.csv` | Successful preparation/build timing and request counters; interrupted failed batches can contain unrecorded final attempts. Build-phase byte totals are unknown when event requests occur, rather than reported as zero. |
| `weather-progress.csv` | All 93 daily/7-/30-day periods, built/reused/deferred state and eligible wind-mask cells. |
| `terrain-input-coverage.csv` | Optional daily/hourly terrain-field gaps by input date. |
| `storage.csv` | Viewer, PRISM work, decoded, rendered-weather and marker bytes; selected shared weather data/index bytes separately. Shared weather caches are not duplicated into the viewer. |
| `build-summary.csv` | Final 496-map release totals, event request count, viewer bytes and final-call time. Sum completed build calls in run-history for the multi-batch time. |

Local policy/cache unit checks can run before downloading:
`testthat::test_file("tests/testthat/test-daily-explorer-july-pilot.R", stop_on_failure=TRUE)`.
The full release check requires the completed July data/render build. Do not
extrapolate a full archive budget from the earlier PRISM-only sample; measure
this full month and assess browser payload/loading before expanding.
