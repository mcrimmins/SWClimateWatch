# Weather maps: retained daily archive and staging trial

Implemented after the approved local design and successful October 26 VM
benchmark. This release is **opt-in**: production remains disabled unless
`SWC_WEATHER_MAPS=true` is explicitly set in the installed run configuration.

The staging candidate includes three exact-date tabs: **500-mb heights**,
**250-mb jet**, and **Moisture & low-level flow**. The moisture map uses the
approved 0–3+ inch PWAT scale, 4-hPa pressure contours, screened 850-mb winds,
and automatic filtered H/L labels. IVT remains deferred.

Each newly built date adds approximately 27 selected-field/index requests and
2 MB of downloads for the combined three-map set, based on the separate pilots.
Measure the combined timing on the VM; the earlier six-map benchmark excluded
moisture. Recent-date rechecks refresh moisture inputs as well. Unchanged source
hashes reuse existing map PNGs; runs with no scheduled work make no requests.
An upstream hourly surface-pressure index can be absent or empty even when
daily fields are available (observed October 4–5 in the laptop trial). In that
case retain PWAT, pressure contours and H/L labels screened using the complete
daily surface-pressure field. Omit winds, and state the missing-overlay
limitation on the map and in last-batch.csv.
Do not fill missing screening samples or silently draw below-ground winds.
An index may also exist but lack a complete `PRES:surface` record, as observed
at 09 UTC on September 28, 2026. Treat that screening sample as unavailable,
not as a failed PWAT map. If the daily surface-pressure record itself is
missing/incomplete, omit H/L labels with a separate notice. Required PWAT,
sea-level pressure and wind-field validation remains strict; corrupt or
ambiguous GRIB records still fail the date. The September 28 regression trial
built with seven usable hourly pressure samples and nine daily-screened centers.

### Broken-index recovery (October 27 investigation)

The September 28 09 UTC index ended after 152 records/11,630,800 bytes, while
the GRIB object was 38,864,340 bytes. October 4 06 UTC and October 5 09 UTC had
empty indexes but GRIB objects of 38,530,880 and 38,001,976 bytes. Cache-bypassed
index checks reproduced these listings. Bounded GRIB reads recovered the missing
surface-pressure record in all three cases; the data were present despite the
bad indexes. The publisher's underlying index-generation problem is unknown.

When a three-hourly pressure index/record is missing, try a **2 MB search window**
around the GRIB object's midpoint, fetched as two separate 1 MB ranges plus a
16-byte object-header request. This position is an empirical search heuristic,
not a guarantee of field identity or future placement. Decode only a unique,
complete GRIB2 template-4.0 surface-pressure candidate with zero forecast lead.
Then run normal exact valid-time, units and Gaussian-grid checks. Pin range
requests to the same object ETag; reject ignored ranges or changing objects.

Recovery is limited to two hourly screening samples per date, within 32 request,
7 MB and existing request-time guards. It adds no requests for dates whose
indexes contain the required fields. Verified recovered records are cached;
scheduled recent-date refreshes recheck them. No full-file downloads, inferred
pressure values, alternate reanalyses or unbounded header scans are used. If the
bounded search cannot recover a sample, keep the missing-overlay behavior.
Recovery counts and errors appear in moisture summaries and archive batch notes.

The three initial cold recovery tests each transferred 2,000,016 bytes in three
requests, taking 4.85, 0.54 and 0.60 seconds respectively. Integrated map tests
restored all eight terrain-screening samples and wind overlays for all three
dates. These are laptop measurements, not a new VM timing benchmark.

Reproduce the small recovery/cache audit from the project root:

```r
source("scripts/audit-weather-core-index-recovery.R")
```

It tests the three known cases, retains only selected pressure records, and
writes `data/diagnostics/weather-core-index-recovery/recovery-test.csv`.
It does not update site assets, render Quarto or sync S3. After releasing the
fix to staging, the existing bounded backfill can regenerate affected maps
using cached main inputs and recover missing screening samples as needed.

## Retention and bounded work

- On first use, record a fixed start date 29 days before the latest completed
  Daily Explorer date. It does not move forward as a rolling deletion boundary.
  Keep all built dates, including earlier water years, on disk and in the
  weather manifest. Never delete weather records as the current window advances.
- Daily runs attempt at most **three new or renderer-outdated dates**, newest
  first, and re-fetch known inputs from the preceding **three days** at most
  once per run date. Rechecks download the selected records, not a full file;
  source hashes decide whether maps need rebuilding. This catches revisions
  whose byte offsets are unchanged. Older revisions require an explicit review
  or refresh; the short window does not detect all historical reanalysis changes.
- Checkpoint each completed date. A failed date is reported and can be retried
  on a later run. A manual backfill lowers the fixed start to the earliest date
  currently in the Explorer payload. Its batch size/run limit are explicit.
- Map fingerprints include source hashes, renderer functions, R and relevant
  package versions. Corrupt PNGs or changed renderers enter the bounded rebuild
  queue. Verified prior outputs remain available while that queue is processed.
- Data/state live in `data/processed/weather-circulation/`; public assets live
  under `site/daily-explorer/circulation/`. No PRISM, snow or station backfill is
  requested by these functions.

Retaining weather maps does **not** implement completed-year PRISM navigation.
The existing Explorer still publishes the current water year plus preceding
September. Its completed-year retention/navigation work remains a separate
roadmap item; retained weather assets can accompany it when implemented.

## Local test before deployment

Use the existing seven-date preview, rather than changing site source assets:

```r
source("scripts/load-weather-circulation-archive.R")
weather_test <- update_weather_circulation_archive(
  explorer_dir = "data/diagnostics/daily-explorer-circulation",
  archive_dir = "data/diagnostics/weather-archive-integration-test",
  max_new_dates = 3L,
  recheck_days = 0L
)
weather_test
```

This is a bounded test, not a request to backfill all years. The local snapshot
ends October 5, so the latest weather map will also be historical. Use the
existing preview server on port 8767 to inspect the date-linked tabs.

## Standalone staging/backfill commands

After Daily Explorer has been staged in the **VM staging worktree**, these R
console commands prepare weather assets without rendering Quarto or syncing S3:

```r
source("scripts/load-weather-circulation-archive.R")

# Preview the first batch; no downloads or staging writes.
backfill_weather_circulation_archive(batch_size = 3L, dry_run = TRUE)

# Build at most three dates; rerun the same command to resume.
weather_batch <- backfill_weather_circulation_archive(
  batch_size = 3L, max_batches = 1L, dry_run = FALSE
)
weather_batch
```

After checking the first batch, use explicit larger limits if desired, e.g.
`batch_size = 5L, max_batches = 6L` for at most 30 attempts. Backfill stops on
failure instead of repeatedly hammering a failing date. Completed dates are
skipped unless their renderer is outdated or an output has failed validation.
Inspect `archive-state.rds`, `last-batch.csv` and `update-summary.csv` under the
archive directory when resuming. Do not delete the archive or manifests.

## Daily staging trial

1. Commit/test the code on the laptop, then update the separate VM staging
   worktree to that exact commit using the established release procedure.
2. Add **only to the staging configuration**:
   ```bash
   SWC_WEATHER_MAPS=true
   ```
3. Confirm staging still targets `s3://cales-climate-reports/climate/watch-staging/`
   and uses the separate staging state/lock. Run its usual daily entry point:
   ```bash
   cd /home/crimmins/RProjects/SWClimateWatch-staging
   SWC_PRODUCTION_CONFIG=/home/crimmins/.config/swclimatewatch/staging.env bash scripts/run-production-daily.sh
   ```
4. Review exact-date matching, unavailable days, tab persistence, source-check
   dates and ntfy/console summary. The first run will build at most three dates;
   unbuilt dates are explicitly unavailable. Use the bounded backfill above to
   fill remaining Explorer coverage before an eventual production release.
5. Trial several new-date/revision runs. Production promotion remains a separate
   user decision; no production env or cron changes are performed by this code.

## Failure handling and reporting

The optional weather stage runs after successful PRISM Explorer staging. A
weather exception disables the optional panel for that run and core processing
continues. Per-date failures retain only checksum-verified older map pairs, with
their exact dates and last source-check date. Failed/unbuilt dates are absent
from the weather manifest; no latest-date substitution occurs in the browser.

Optional rendered-weather validation checks manifest paths, files and checksums
against staged sources. If it fails, only the rendered weather panel is disabled;
the already validated PRISM assets remain publishable. Console/ntfy reports the
failure. Weather summaries include dates retained, built/reused/failed counts,
backlog and latest date. Latest maps more than three days old trigger a warning;
this can be expected during a deliberately historical local test.

Weather failures do not weaken the existing core-map validation gates. Overall
site-render or core validation failures still prevent S3 sync as before.

## Still separate

No same-source anomaly baseline, full historical CORe download, automatic
completed-year Explorer navigation, indefinite retry loop or source switching
is included. No weather data are fetched in the browser: it loads static local
metadata/images only when the Weather maps section or selected tab is opened.

## Laptop to VM staging release

Commit the integration and moisture files on `codex/daily-explorer`; generated
maps/caches are ignored. Keep the deferred IVT experiment out of this release.

```cmd
git add -u
git add R/daily-explorer-circulation.R R/weather-circulation-archive.R R/weather-moisture-pilot.R docs/weather-circulation-daily-workflow.md scripts/build-daily-explorer-circulation-preview.R scripts/load-weather-circulation-archive.R scripts/run-weather-moisture-pilot.R scripts/serve-daily-explorer-circulation.R scripts/update-weather-circulation.R tests/test-daily-explorer-circulation-ui.cjs tests/testthat/test-daily-explorer-circulation.R tests/testthat/test-weather-circulation-archive.R tests/testthat/test-weather-moisture-pilot.R
git add R/weather-core-index-recovery.R scripts/audit-weather-core-index-recovery.R tests/testthat/test-weather-core-index-recovery.R
git diff --cached --stat
git commit -m "Stage daily weather maps with moisture and cached date archive"
git push origin codex/daily-explorer
git rev-parse HEAD
```

On the VM, use the existing staging checkout after other staging jobs finish.
Replace `PASTE_LAPTOP_HASH` with that full hash. Do not run this in production.
The release lock must match staging.env's `SWC_PRODUCTION_STATE_DIR`.

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
mkdir -p /home/crimmins/.local/state/swclimatewatch-staging
exec 9>/home/crimmins/.local/state/swclimatewatch-staging/daily.lock
flock -n 9
git status --short
git diff -- site/index.qmd site/pages/current-snow.qmd
```

Continue only if the lock succeeded. If the only tracked edits are generated
date lines in those two pages, preserve them before switching revisions:

```bash
git stash push -m "Staging generated page dates before weather release" -- site/index.qmd site/pages/current-snow.qmd
git status --short
git fetch origin codex/daily-explorer
git checkout --detach PASTE_LAPTOP_HASH
git rev-parse HEAD
flock -u 9
exec 9>&-
```

Stop if other edits remain or the printed hash differs from the laptop. Do not
apply the generated-date stash over the new release; the daily run updates dates.
In `/home/crimmins/.config/swclimatewatch/staging.env`, set
`SWC_WEATHER_MAPS=true`, retaining the staging destination and state directory.

```bash
grep -E '^SWC_(S3_DESTINATION|PRODUCTION_STATE_DIR|WEATHER_MAPS)=' /home/crimmins/.config/swclimatewatch/staging.env
SWC_PRODUCTION_CONFIG=/home/crimmins/.config/swclimatewatch/staging.env bash scripts/run-production-daily.sh --check
SWC_PRODUCTION_CONFIG=/home/crimmins/.config/swclimatewatch/staging.env bash scripts/run-production-daily.sh
cat data/processed/weather-circulation/last-batch.csv
cat data/processed/weather-circulation/update-summary.csv
```

Open <https://cales.arizona.edu/climate/watch-staging/> and its Daily Explorer.
The first run builds at most three dates (nine weather maps). Verify all three
tabs, the 3+ PWAT legend and H/L labels, date changes, lazy image loading, and
explicit unavailable dates. A repeat with no new/revised inputs should reuse
maps. Check the weather summary for failures before filling older dates with
the bounded backfill commands above. Leave production configuration and cron
unchanged until this staging trial passes.
