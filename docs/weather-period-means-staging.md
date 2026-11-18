# Weather period means: staging trial

The Daily Explorer offers daily, trailing 7-day and trailing 30-day weather
maps for 500-mb heights, 250-mb vector-mean jet/flow and PWAT with mean pressure,
850-mb flow and H/L overlays. Weather averaging is independent of the daily
thumbnail grid. Clicking a daily thumbnail selects Daily; date arrows preserve
the averaging choice. Missing windows are explicit; no date substitution or
partial means. All samples must support terrain screening for displayed winds.

The daily publisher now calls the mean builder after daily weather updates
when both `SWC_WEATHER_MAPS=true` and `SWC_WEATHER_PERIOD_MEANS=true` are set.
The means flag defaults off; activating it in the installed VM configuration
requires no cron change. The builder reads existing daily CORe GRIB caches
and checksum markers, including recovered pressure samples. It performs zero
network requests. No laptop cache transfer is required for a VM with the
retained operational weather archive. Missing input windows are reported in
`data/processed/weather-period-means/last-batch.csv` and withheld.

The first trial builds three new endpoints (up to six periods/18 PNGs). Reruns
reuse unchanged inputs/outputs and advance to the next unfinished endpoints.
Up to 30 recent retained daily endpoints are considered. Each period is
checkpointed; revised source hashes invalidate overlapping means. Decoded
daily inputs are cached across periods. GRIB and RDS files never enter the site.

## Laptop

Run tests, explicitly stage the weather changes, inspect `git diff --cached
--stat`, commit and push `codex/daily-explorer`. Keep generated synopsis content
and unrelated IVT experiments out of this release. Record `git rev-parse HEAD`
after committing; it must match the VM checkout before building.

## VM: checkout and first trial

Run this from the VM terminal, as a complete block:

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
(
  set -euo pipefail
  set -a
  source /home/crimmins/.config/swclimatewatch/staging.env
  set +a
  export TZ=America/Phoenix
  export PATH="/usr/local/bin:/usr/lib/rstudio-server/bin/quarto/bin:/usr/bin:/bin:$PATH"
  test "$SWC_S3_DESTINATION" = "s3://cales-climate-reports/climate/watch-staging/"
  test "$SWC_PRODUCTION_STATE_DIR" = "/home/crimmins/.local/state/swclimatewatch-staging"
  mkdir -p "$SWC_PRODUCTION_STATE_DIR/logs"
  exec 9>"$SWC_PRODUCTION_STATE_DIR/daily.lock"
  flock -n 9 || { echo "STOP: another staging job is running."; exit 1; }

  git stash push -m "Staging generated pages before weather period means" -- site/index.qmd site/pages
  test -z "$(git status --porcelain --untracked-files=no)" || {
    git status --short
    echo "STOP: tracked changes remain."
    exit 1
  }
  git fetch origin codex/daily-explorer
  git checkout --detach FETCH_HEAD
  git rev-parse HEAD

  SWC_WEATHER_MEANS_MAX_NEW_DATES=3 Rscript scripts/build-staging-weather-periods.R 2>&1 |
    tee "$SWC_PRODUCTION_STATE_DIR/logs/weather-period-build.log"
  SWC_WEATHER_MEANS_MAX_NEW_DATES=0 Rscript scripts/build-staging-weather-periods.R 2>&1 |
    tee "$SWC_PRODUCTION_STATE_DIR/logs/weather-period-cache-check.log"
  Rscript -e 'x <- read.csv("data/processed/weather-period-means/last-batch.csv"); print(x[x$status %in% c("BUILT","REUSED","UNAVAILABLE"), ], row.names=FALSE)'

  Rscript scripts/publish-site-s3.R
  Rscript scripts/check-weather-period-publication.R
  Rscript scripts/check-weather-publication.R
)
```

`max_new=0` must build nothing and reuse the completed periods, with zero
requests. Deferred windows are expected after a bounded batch; unavailable
windows need an input-cache review, not relaxed completeness thresholds.
If no complete periods exist, the staging script stops before publication.

## Review

Open [staging Daily Explorer](https://cales.arizona.edu/climate/watch-staging/pages/daily-explorer.html).
Use an endpoint listed as REUSED/BUILT in the log. The newest PRISM date may
be newer than CORe. Test 7-/30-day means across all three tabs, date arrows,
daily thumbnails, Map view, season/year boundaries, and unavailable endpoints.
The Show daily map button should appear only when that exact daily map exists.
Verify staged and rendered checks pass. A generic daily-weather coverage WARN
can be independent of mean-map validation; inspect the reported missing dates.

## Additional cached backfill

Repeat the first build/publish steps under the staging lock to advance another
three endpoints. Increase `SWC_WEATHER_MEANS_MAX_NEW_DATES` to at most 30 for a
larger initial trial; rendering time and image count increase accordingly.
Do not run the mean build concurrently with a staging data refresh.

## Automatic daily integration and promotion

The daily workflow runs daily weather first, then reads cached inputs for
means. Source revisions invalidate overlapping windows; the endpoint cap
limits rebuild work and carries the backlog forward. Mean errors clear only
the means selector flag and leave daily weather available. Missing periods
remain gaps; no replacement dates or partial means. The workflow report and
console/ntfy completion summary include counts and elapsed seconds.

On the laptop, commit/push `R/daily-publish.R`, `R/weather-period-archive.R`,
`scripts/production.env.example`, `tests/testthat/test-weather-period-workflow.R`
and these publishing/roadmap documents. Check out that same commit on staging
under its lock, then set these lines in the staging configuration (back it up
first; replace previous definitions):

```bash
SWC_WEATHER_MAPS=true
SWC_WEATHER_PERIOD_MEANS=true
SWC_WEATHER_MEANS_MAX_NEW_DATES=3
```

Release the checkout lock before invoking the runner, which obtains its own:

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
SWC_PRODUCTION_CONFIG=/home/crimmins/.config/swclimatewatch/staging.env \
  bash scripts/run-production-daily.sh
Rscript scripts/check-weather-period-publication.R
cat data/processed/weather-period-means/workflow-status.csv
```

Review the refreshed staging site and its log. Expected: zero extra mean-input
requests, completed means reused, new/revised endpoints built up to the cap,
and rendered period validation PASS. Deferred/unavailable counts are explicit.
Continue seasonal and upstream-revision monitoring after promotion.

For production, pin to the accepted staging commit under BOTH staging and
production locks. Save the previous production commit, stash generated tracked
site pages, verify the tracked checkout is clean, fetch and check out that
commit. With both locks still held, copy the verified cache with:

```bash
mkdir -p /home/crimmins/RProjects/SWClimateWatch/data/processed/weather-period-means
cp -a /home/crimmins/RProjects/SWClimateWatch-staging/data/processed/weather-period-means/. \
  /home/crimmins/RProjects/SWClimateWatch/data/processed/weather-period-means/
```

Generated map PNGs and the Explorer manifest are staged from that cache by the
next workflow; no rendered site or whole raw-data transfer is needed. Set the
same three weather flags in `production.env` while preserving its `watch/`
destination and production state directory. Release BOTH locks, then invoke:

```bash
cd /home/crimmins/RProjects/SWClimateWatch
SWC_PRODUCTION_CONFIG=/home/crimmins/.config/swclimatewatch/production.env \
  bash scripts/run-production-daily.sh
Rscript scripts/check-weather-period-publication.R
```

The existing cron reads this configuration on every run and will thereafter
update means automatically. Disable just means with
`SWC_WEATHER_PERIOD_MEANS=false`; the next daily workflow clears the selector
while preserving daily weather. Keep the saved commit and configuration backup
for code rollback if needed.
