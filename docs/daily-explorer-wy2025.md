# WY2025 local monthly backfill

Scope: October 1, 2024–September 30, 2025, in resumable calendar-month batches.
The complete archive contains 365 dates, 2,555 PRISM maps, 1,095 daily weather
maps and 2,190 trailing-mean weather maps (5,840 maps total), plus observed
storm reports and archived NWS hazards. Nothing is published by these scripts.

## Plan and build

Run in RStudio:

```r
setwd("C:/Users/Crimmins/RProjects/SWClimateWatch")
source("scripts/plan-daily-explorer-wy2025.R")

options(
  swc.wy2025.download = TRUE,
  swc.wy2025.month = NULL,
  swc.wy2025.require_complete = TRUE,
  swc.wy2025.max_input_dates = 10L,
  swc.wy2025.max_end_dates = 7L
)

for (batch in seq_len(120)) {
  source("scripts/run-daily-explorer-wy2025-batch.R")
  if (identical(wy2025_batch$status, "ALL_RELEASES_PRESENT")) break
}

options(swc.wy2025.download = FALSE)
source("scripts/test-daily-explorer-wy2025.R")
source("scripts/preview-daily-explorer-wy2025.R")
```

The loop stops at the first error. Rerun it to resume after resolving a source
failure. Stop between batches with RStudio's Stop control; complete input
markers and rendered-period checkpoints are reused. Interrupted files fail
checksum checks and are rebuilt; missing weather inputs never become partial
means or zero values. The 120-call loop is a bounded convenience, not a claim
that every source will be available; rerun if the final year check reports
pending months. `ALL_RELEASES_PRESENT` describes markers only; the separate
test/check step verifies every referenced asset and all coverage.
If a final check reports an invalid month, select that month explicitly and
rerun its batch. The runner retires only the invalid release marker, then
rechecks cached inputs/maps and repairs the release. It does not delete caches.

For hands-on monthly review, select a month and rerun individual batches:

```r
options(swc.wy2025.download = TRUE, swc.wy2025.month = "2024-10")
source("scripts/run-daily-explorer-wy2025-batch.R")
# Repeat until wy2025_batch$status is "MONTH_READY".

options(swc.wy2025.require_complete = FALSE)
source("scripts/check-daily-explorer-wy2025.R")
source("scripts/preview-daily-explorer-wy2025.R")

# Restore full-year defaults before the automatic loop/final acceptance.
options(swc.wy2025.month = NULL, swc.wy2025.require_complete = TRUE)
```

Preview: <http://127.0.0.1:8804/>. Only verified complete months appear. Missing
calendar dates remain unavailable, and no nearby date is substituted.

## Boundaries, reuse and workload

- Each call works on one month, prepares at most ten additional supporting
  weather dates and renders at most seven new weather endpoints. Each endpoint
  includes 1-, 7- and 30-day products with all required fields and overlays.
- A month's weather support begins 29 days before its first date. The complete
  year therefore needs September 2, 2024–September 30, 2025: 394 unique dates.
- Inputs, PRISM map caches and rendered weather are seeded from verified July,
  winter, June and already-built monthly caches. Regular builders recheck
  scientific signatures before accepting copied outputs. Raw GRIB files stay
  shared; only small checksum markers reference them from each work directory.
- Accepted pilot bundles are retained. July is assembled again as a WY2025
  month using its cached maps, with an expanded event lookback; its reviewed
  original release stays unchanged.
- Every month includes 30 preceding UTC days of report/hazard coverage so
  early-month 7-/30-day report windows work. Report padding and noon/UTC timing
  are validated; hazard archive requests remain split into at most 31-day
  source windows. Existing carry-in and VTEC archive limitations still apply.
- The navigation fetches adjacent daily map metadata for trailing 30-day and
  centered 7-day views, with paths rebased to the owning month. PNGs and hazard
  geometry remain lazy-loaded. Adjacent months must be complete and present
  in the catalog; dates outside WY2025 are not added to the daily map archive.
- No performance guarantee or fixed total runtime is implied. This is a
  substantial historical build. Review real request/time/storage logs before
  staging. Private viewer copies and the assembled preview both occupy disk;
  do not treat their combined bytes as unique publication size.

## Files and checks

Everything is under `data/diagnostics/daily-explorer-wy2025/`:

- `month-plan.csv`: all twelve months and expected map/support counts.
  `RELEASE_PRESENT` means a marker exists; `READY` means full validation passed.
- `last-batch.csv`: last active month and preparation/build state.
- `months/YYYY-MM/`: per-month input plan, preparation/render checkpoints,
  run history, build summary, storage CSV, native work caches and verified viewer.
- `preview/`: navigation and copies of only the verified viewer files, with
  `wy2025-release.json` listing the exact publication-candidate assets.
  Source grids, working caches and unrelated stale preview directories are
  excluded from that release manifest. No cleanup is performed.

Validation checks contiguous month/day coverage, all 5,840 map references,
source/render hashes, daily and complete 7-/30-day weather windows, report
coverage and timelines, hazard event/geometry references and timeline totals,
versioned browser assets, month routing and the whole-year release digest.
The browser-code test covers adjacent-month metadata, rebased paths, lazy
image loading and reuse of metadata requests. Full visual review and staging
retention checks follow the local build; these scripts do not alter daily
production or permanent environment files.
