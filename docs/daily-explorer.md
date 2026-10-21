# Daily Explorer

Daily Explorer is integrated into navigation and the daily publishing workflow.
It stages the current water year to date plus the preceding September, ending
on the latest cached PRISM date, not today's date. Each day remains available
as the year progresses instead of dropping out after 90 days. At the next
water-year rollover the published window starts at the new preceding September;
completed full-year daily archives are a separate future feature. Existing work
caches are retained. The local preview commands below do not download or publish.
Production promotion is explicit; developing this branch does not update the VM.

The explorer includes precipitation and maximum, minimum, and mean daily
temperature. Mean temperature is derived from paired native maximum/minimum
cells as `(maximum + minimum) / 2`, with missing inputs propagated. Its
1991–2020 normal averages the matching maximum/minimum normals. Mean-temperature
percentile coverage is not calculated. There are seven map images per complete
day (precipitation plus observed/departure for each temperature variable).

Map View controls the timeline's dates: Single day retains the seasonal
timeline; 7 days uses the centered grid window; 30 days uses the trailing grid
window. The timeline metric remains independent. Notable days still rank the
selected season. Routine regional data-coverage badges are hidden, but the
95% validity checks remain enforced. Map footers credit Climate Science
Applications Program – University of Arizona and PRISM via RCC-ACIS; missing
cell background conventions are explained on the page instead of each map.

From the project root in the RStudio Console:

```r
source("scripts/build-daily-explorer.R")
source("scripts/serve-daily-explorer.R")
```

The preview opens at `http://127.0.0.1:8766/`. It uses the latest water year
present in the local processed PRISM manifest, not today's date or the VM's
newer data. The header states the cached dates. The initial laptop sample is
October 1–5, 2026 (WY2027). The prepared review preview additionally includes
September 2026 (WY2026), using the longer-period command below.

For a longer cached period, choose years and optional date bounds explicitly:

```r
source("scripts/load-daily-explorer.R")
swc_daily_explorer <- build_daily_explorer(
  water_years = c(2026L, 2027L),
  start_date = as.Date("2026-09-01")
)
source("scripts/serve-daily-explorer.R")
```

This builds seven PNGs per fully available day: precipitation, observed maximum,
minimum and mean temperature, and their three temperature departures. Longer
periods therefore take more time and storage. No full historical backfill is
performed automatically. The output lives entirely under the ignored directory
`data/diagnostics/daily-explorer/`. Rebuilding with a narrower date selection
limits the active dataset but retains old cached files for reuse.

## Views and interpretation

- A seasonal timeline selects dates and exposes exact daily regional values on
  hover or keyboard focus. Departure bars use color for sign and height for
  magnitude. Missing days have a hatched background; observed zero is valid.
- Select water year, full year/cool season/warm season/monsoon, summary region,
  variable, and observed/departure temperature display. Periods are restricted
  to built cache dates; no forecast or unbuilt future days are implied.
- All maps show the combined region and surrounding context. The summary
  region controls statistics, timeline, and rankings, not the map extent.
- Geographic context and labeling reuse the public site's shared renderer:
  state, county, international and cached tribal boundaries; the standard city
  network and Tucson's southwest label placement. Explorer city labels use
  small, bold near-black text (2.05 mm) with the public renderer's bordered,
  translucent white labels to minimize coverage while remaining readable;
  public maps retain their existing translucent backgrounds.
  This label style was selected for the Daily Explorer on October 21, 2026.
  Optional rivers/interstates follow the same map options as public products.
  The explorer keeps its own categorical colors and compact image dimensions.
  Legends use one horizontal row across the bottom, including all 11
  precipitation categories.
- The Map view selector offers Single day, a centered seven-day grid, and a
  30-day grid ending on the selected date. The monthly grid uses five columns
  and six rows on large screens, with three or two columns on smaller screens.
  Grids use built dates across season/water-year boundaries, preserving gaps.
  Clicking a thumbnail selects its date in the large map and adjusts the year
  and season selectors if needed. Every map uses the same geographic extent and
  fixed categorical scales. PNG links expose the same preview-resolution
  image; they are not described as full-resolution exports.
- Notable days are ranked within the selected period. They do not claim
  historical records, event impacts, station extremes, or formal Climdex indices.

Area-weighted summaries use native grid cells whose centers fall in Arizona
or New Mexico, with geodesic cell areas from `terra::cellSize`. At least 95%
of the regional area must have usable inputs for each statistic; reference
coverage is checked separately. Combined summaries weight by area rather than
averaging state means. Fixed precipitation thresholds allow float32 storage
tolerance consistent with the project's PRISM configuration.

Daily precipitation maps use 11 fixed categories, in inches: zero, >0–0.01,
0.01–0.05, 0.05–0.10, 0.10–0.25, 0.25–0.50, 0.50–1, 1–1.5, 1.5–2,
2–3, and >3. Nonzero intervals include their upper endpoint. The blue–green–purple
palette is shared by every date; zero and missing data remain distinct.

Temperature departures and percentile exceedance coverage reuse the existing
1991–2020 centered-five-day reference grids. No new percentile calculations
are required. Missing reference files/layers leave the affected metric or map
unavailable while preserving observed maps and other usable summaries. Strict
greater-than/less-than comparisons define warm/cold coverage. Freezing uses
minimum temperature at or below 32°F.

The spatial precipitation 99th percentile is area weighted over that day's
regional grid, including dry cells. It is explicitly separate from a historical
precipitation percentile. Source daily reporting dates are used without
assuming a uniform local midnight observation boundary. Recent PRISM values
remain preliminary and revisable.

## Incremental builds and validation

For a quick before/after label comparison without rebuilding every map, run
`source("scripts/preview-daily-explorer-labels.R")` and open
`http://127.0.0.1:8766/label-pilot/`. This renders wet/dry examples for September
30 and October 2, 2026, and updates just those two precipitation dates in the
existing explorer. A normal builder run applies the style to all selected days.

A separate smaller/lighter option is available with
`source("scripts/preview-daily-explorer-light-labels.R")`, then
`http://127.0.0.1:8766/light-label-pilot/`. It compares the earlier 3.05 mm bold
labels and 0.07 halo radius with 2.55 mm regular-weight labels and a 0.035 halo
radius. It does not replace the active explorer maps or change their defaults.

For the follow-up readability comparison, run
`source("scripts/preview-daily-explorer-readable-labels.R")` and open
`http://127.0.0.1:8766/readable-label-pilot/`. Both options now use 2.05 mm bold
near-black text. Option A uses a minimal soft halo (radius 0.012); Option B
now uses the public site's translucent bordered labels at the smaller font
size and is the new default.
The preview script does not replace existing active images; rebuild the explorer
to apply the new defaults to all dates. Inspect the linked full-size images,
not just the side-by-side thumbnails, when deciding on readability.

Each date has a private RDS cache containing summaries and an input signature.
The signature includes actual source-file and reference-file MD5 checksums,
the selected source layers, region geometry, shared map context and rendering
code. A change to a
monthly source rebuilds affected dates selected from that file, even if only
one layer changed. Missing output images also trigger a rebuild. UI assets
are copied on every build; JavaScript-only changes do not rebuild maps.

After a failed/interrupted build, rerun the same command. Completed dates are
reused. The browser dataset is written after all selected dates are processed.
For an explicit rebuild use `build_daily_explorer(force = TRUE)`.

Focused calculation tests:

```r
testthat::test_dir("tests/testthat", filter = "daily-explorer")
```

The production adapter uses the existing PRISM source preference: recent daily
files first, then the shorter source interval, then the newest processing time.
Equal-priority overlapping files stop the build. Raw grids are never changed.
Actual selected source/reference checksums invalidate revised dates. Cache RDS
files stay in `data/diagnostics/daily-explorer-site/cache/`; only assets and
referenced PNGs go to `site/daily-explorer/`. Obsolete generated PNGs in that
exact site maps folder are pruned locally; source grids and work caches remain.
S3 synchronization still uses **no remote deletion**, so older unreferenced S3
objects may accumulate. Remote retention cleanup is a separate task.

Missing dates remain gaps. Missing reference data leave departures unavailable
without filling values or removing the observed map. Validation checks dates,
safe image references, nonempty assets, the rendered iframe, and exact checksums
of the newly staged JSON, UI assets and map images before any S3 sync. Explorer failure stops
the publisher and does not advance its last-success marker.

First-build and daily-change runtime must be measured on VM staging. The
laptop integration pilot used three days (21 PNGs); a cached rerun reused all
three in about five seconds. This is not a measured full-season/year VM runtime.
The growing-water-year laptop test then staged September 1–October 5, 2026
(35 days / 245 PNGs) in 477 seconds; a repeat reused all 35 dates in 9.6 seconds.
These are cached-input laptop measurements, not VM or full daily-publisher timings.
Native-resolution downloads and a longer daily-map archive remain follow-ups.

## VM staging and release checklist

Do not copy laptop climate data again and do not run an unqualified live
publisher during testing. Leave the existing production cron/config unchanged.
Use a separate staging checkout with its own **copied** data and generated
assets (no shared writable symlinks/hardlinks). The VM has enough disk for
this temporary second copy based on the reported capacity; check again first.
Run staging after the normal production job finishes to limit CPU/I/O contention.

### 1. Laptop: verify, commit and push the feature branch

In the project terminal:

```text
git status --short
git branch --show-current
Rscript -e "testthat::test_dir('tests/testthat', filter='daily-explorer|daily-publish|deploy-site-s3', reporter='summary')"
node tests/test-daily-explorer-ui.cjs
git add -u
git add R/daily-explorer*.R docs/daily-explorer.md scripts/*daily-explorer* tests/test-daily-explorer-ui.cjs tests/testthat/test-daily-explorer*.R site/pages/daily-explorer.qmd
git diff --cached --stat
git commit -m "Integrate Daily Explorer with daily publication"
git push -u origin codex/daily-explorer
git rev-parse HEAD
```

Confirm the branch is `codex/daily-explorer` and review staged files first;
do not include unrelated changes. Record the full hash as `TESTED_COMMIT_HASH`
below. Node is needed only for the lightweight development UI tests, not by
the VM daily publisher. Do not merge into main until staging passes.

### 2. VM: create an isolated staging checkout and seed it locally

Check that production is idle, inspect disk usage and pick a time outside its
scheduled run. These commands assume the staging path does not already exist;
stop and inspect it if it does. Replace the hash placeholder before running.

```bash
cd /home/crimmins/RProjects/SWClimateWatch
df -h /home
git fetch origin
git worktree add --detach /home/crimmins/RProjects/SWClimateWatch-staging TESTED_COMMIT_HASH
mkdir -p /home/crimmins/RProjects/SWClimateWatch-staging/data
cp -a --reflink=auto data/. /home/crimmins/RProjects/SWClimateWatch-staging/data/
mkdir -p /home/crimmins/RProjects/SWClimateWatch-staging/site/maps
cp -a --reflink=auto site/maps/generated /home/crimmins/RProjects/SWClimateWatch-staging/site/maps/
cp -a --reflink=auto site/stations /home/crimmins/RProjects/SWClimateWatch-staging/site/
cp -p site/index.qmd /home/crimmins/RProjects/SWClimateWatch-staging/site/index.qmd
cp -p site/pages/current-snow.qmd /home/crimmins/RProjects/SWClimateWatch-staging/site/pages/current-snow.qmd
```

`--reflink=auto` uses a copy-on-write copy where supported, otherwise a normal
copy; either way, writes to staging cannot alter production files. Copy the
verified current snow/dashboard pages because generated map dates on the VM
may be newer than their committed source. Existing `/home` backups remain the
recovery mechanism; no original data are moved or deleted here.

Create a private staging configuration from the working production settings:

```bash
cp -n /home/crimmins/.config/swclimatewatch/production.env /home/crimmins/.config/swclimatewatch/staging.env
chmod 600 /home/crimmins/.config/swclimatewatch/staging.env
nano /home/crimmins/.config/swclimatewatch/staging.env
```

In **staging.env only**, set these lines, preserving the working PATH and other
settings. Keep the original production.env unchanged:

```bash
SWC_S3_DESTINATION=s3://cales-climate-reports/climate/watch-staging/
SWC_PRODUCTION_STATE_DIR=/home/crimmins/.local/state/swclimatewatch-staging
```

### 3. VM staging: first build, render, validate and upload

Run the same date-aware entry point, explicitly selecting the staging config:

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
SWC_PRODUCTION_CONFIG=/home/crimmins/.config/swclimatewatch/staging.env bash scripts/run-production-daily.sh --check
SWC_PRODUCTION_CONFIG=/home/crimmins/.config/swclimatewatch/staging.env bash scripts/run-production-daily.sh
```

The first run builds the data water year to date plus the preceding September:
up to 396 dates / 2,772 PNGs at the end of a leap water year. It may take several
minutes or longer depending on season progress; do not infer a daily runtime
from this one-time cost. Subsequent runs add new dates and rebuild revised
inputs while retaining unchanged earlier dates. Review the
runner log for explorer days/maps, rebuilt/reused dates, elapsed time and the
explicit watch-staging destination. Inspect
`https://cales.arizona.edu/climate/watch-staging/pages/daily-explorer.html`
and its full-screen link. Test observed/departure mean, maximum and minimum
temperature, rainfall, state selectors, 7-/30-day grids, both directions across
September 30/October 1 when in range, and unavailable dates at cache edges.

Run the same staging command again to check cache reuse, and once after a new
daily data arrival to measure incremental cost. No new staging cron is required.
Do not manually invoke a second staging process concurrently with the runner.

### 4. Promote only after staging approval

On the laptop, if main has not diverged:

```text
git switch main
git pull --ff-only origin main
git merge --ff-only codex/daily-explorer
git push origin main
git rev-parse HEAD
```

If fast-forward fails, stop and reconcile the branches; do not force/reset.
Use the tested full hash with the existing
[controlled VM release procedure](vm-daily-operations.md#controlled-code-releases):
take the production lock, record the rollback hash, inspect/preserve generated
page changes, fetch and detach at the tested hash, then release the lock.
Do not repoint production to the staging checkout or change its data paths.

In the production checkout, after the code release and with production.env
still targeting `watch/`:

```bash
cd /home/crimmins/RProjects/SWClimateWatch
bash scripts/run-production-daily.sh --check
bash scripts/run-production-daily.sh
```

Production will build its own explorer cache from current production data.
There is no need to transfer the staging cache or add a new cron entry. Inspect
the live explorer and next scheduled run. Rollback code uses the previously
recorded hash and the same lock/preservation procedure; it does not roll back
data. With deletion disabled, obsolete unlinked S3 explorer assets may remain
after rollback, but navigation comes from the rolled-back site render.

## Future work: city labels on the rest of the site

Consider adopting the Daily Explorer's smaller city-label size on
the other current and historical maps. Compare readability over precipitation,
temperature and snow colors, especially where labels intersect boundaries
(such as Yuma and Sierra Vista), before changing the site-wide default. The
shared renderer already supports `city_label_style = "label"` and custom text size;
existing public products retain their boxed labels
until that separate change is approved.
