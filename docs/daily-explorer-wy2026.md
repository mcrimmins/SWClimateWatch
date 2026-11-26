# WY2026 local monthly archive

Scope: October 1, 2025–September 30, 2026, in twelve resumable monthly
batches. The full year contains 365 dates and 5,840 maps: 2,555 PRISM,
1,095 daily CORe and 2,190 trailing 7-/30-day CORe maps, plus storm reports
and archived NWS hazards. Supporting weather starts September 2, 2025.
Event lookback starts September 1, 2025. No site, VM, scheduler, production
environment or accepted WY2025 release is modified.

## Inventory and build

```r
setwd("C:/Users/Crimmins/RProjects/SWClimateWatch")
source("scripts/plan-daily-explorer-wy2026.R")
source("scripts/inventory-daily-explorer-wy2026.R")
```

The November 25 laptop inventory found all 1,095 target PRISM day/variable
layer headers, but only 54/394 supporting dates with all four verified core
CORe fields. Most required overlays and exact report-range caches also remain
missing. This is an inventory, not scientific validation of complete products.
Hazard archive coverage is validated by the monthly builder.

Downloads default to FALSE. For a full build, explicitly allow missing CORe
and event inputs; verified existing files are still reused:

```r
options(
  swc.wy2026.download = TRUE,
  swc.wy2026.month = NULL,
  swc.wy2026.require_complete = TRUE,
  swc.wy2026.max_input_dates = 10L,
  swc.wy2026.max_end_dates = 7L,
  swc.wy2026.max_batches = 200L
)
source("scripts/run-daily-explorer-wy2026.R")
```

Each batch prepares at most ten additional supporting weather dates and
renders at most seven new weather endpoints. Each endpoint includes daily,
7-day and 30-day products with complete input windows. A source error stops
the loop and retains checkpoints; re-source the runner to resume. A completed
weather endpoint is reused even if a later event fetch times out. WY2026
storm-report requests use a 120-second timeout and up to three attempts,
including the initial request, for transient HTTP/connection failures. These
settings are local to the batch and restored on exit; operational defaults
remain 45 seconds and one attempt. Failed downloads do not replace a good
cache or become empty report coverage. For a persistent source failure,
retry later rather than restarting or deleting the weather checkpoints.
A completed
month is skipped automatically; explicitly selecting one validates it and
repairs an invalid release from cached inputs. The 200-call limit is bounded,
not a completion guarantee. No data gaps are filled or silently skipped.

For cache-only operation set `swc.wy2026.download = FALSE`. Missing CORe/event
inputs then stop the build. PRISM is always cache-only: this runner does not
download or revise daily PRISM grids. Existing PRISM comparison/reference
checks and source signatures continue to apply.

Verified input markers reference shared original GRIB files. The seed step
also reads WY2025 month caches, earlier July/seasonal pilots and completed
WY2026 months. Donor files are never modified; copied map/render checkpoints
are still checked by the regular builders before reuse. There is no cleanup
or transfer in these scripts.

## Validate and preview

After the runner finishes:

```r
options(swc.wy2026.download = FALSE, swc.wy2026.require_complete = TRUE)
source("scripts/test-daily-explorer-wy2026.R")
source("scripts/build-daily-explorer-wy2026-navigation.R")
source("scripts/preview-daily-explorer-wy2026.R")
```

Preview: <http://127.0.0.1:8808/>. Navigation construction is explicit;
previewing an existing release does not recopy all maps. It validates its
current release before serving. Stop with `servr::daemon_stop(wy2026_server)`
or stop the matching server listed by `servr::daemon_list()` in that R session.

To review an early completed month:

```r
options(swc.wy2026.month = "2025-10", swc.wy2026.download = TRUE)
source("scripts/run-daily-explorer-wy2026.R")
options(swc.wy2026.require_complete = FALSE)
source("scripts/check-daily-explorer-wy2026.R")
source("scripts/build-daily-explorer-wy2026-navigation.R")
source("scripts/preview-daily-explorer-wy2026.R")
# Restore for the full-year run:
options(swc.wy2026.month = NULL, swc.wy2026.require_complete = TRUE)
```

Validation covers exact month/year dates, all referenced map hashes, complete
weather windows, report padding/timing, hazards and timeline counts, browser
assets and immutable release manifests. Partial-year previews include only
verified complete months; unbuilt dates stay unavailable.

## Outputs and next steps

All private work is under `data/diagnostics/daily-explorer-wy2026/`:

- `month-plan.csv`, `cache-inventory.csv`, `cache-support.csv`, `last-batch.csv`.
- `months/YYYY-MM/`: input/render checkpoints, run history, storage reports
  and verified viewer releases.
- `preview/`: assembled publication candidate and `wy2026-release.json`.

Working month viewers and the assembled preview occupy separate disk space.
Read each month's `storage.csv` and the final navigation `viewer_bytes` before
packaging. No exact runtime or disk guarantee is implied by the prior year.
Adding this year to the connected selector, transfer/export, staging retention
and production acceptance follow local validation and visual review.

## Loading-screen repair

The first complete preview exposed a shared month-loader check restricted to
the WY2025 catalog flag. WY2026 metadata was rejected, and the old frame bridge
did not forward initialization errors to the parent. The loader now accepts
the schema-1 WY2026 catalog as well as the existing WY2025 format; child errors
are displayed in the parent instead of remaining on a loading notice.

For an already assembled preview, update only navigation files and release
seals, then validate all referenced assets:

```r
source("scripts/repair-daily-explorer-wy2026-navigation.R")
```

No weather/PRISM rendering, downloads or copying of map bundles occurs. The
pre-repair manifests are saved in `navigation-before-loading-repair.rds`.
Existing source month viewers and WY2025 releases are untouched. A fresh
navigation build also includes the correction. Reload the browser after the
repair finishes to fetch the new content-hashed scripts.

The separate archive preview initially retained the older resize controller,
although the connected Explorer already had settled-height handling. Its
controller now coalesces height messages for 160 ms, ignores changes below
four pixels, retains frame space during loading and avoids rewriting selectors
or history on height-only messages. The month bridge restores controls in one
render and preserves the selected date when Map view changes. Shared frame
styles reserve timeline rows and scrollbar space. These are browser-only
changes; the same repair script updates their release seals without map work.
Browser checks confirmed unchanged timeline bounds across January 31 period
changes and a transition to January 30, and tests cover cold start, date/token
guards and selector/height stability. Legitimate layout-height changes still
occur when the number of maps or reports changes.
