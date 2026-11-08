# Monthly Climate in the daily runner

## Policy and safeguards

Set `SWC_MONTHLY_MAPS=true` in a VM's external configuration to enable monthly
updates inside the existing daily runner. It is disabled by default. No second
cron job is needed. The runner's destination-specific lock covers the workflow.

- Days 1–5, America/Phoenix: refresh eight completed months (normally 24 inputs).
  Accept only a fully validated staged set; build current/affected retained maps.
- After a successful cycle: no new source requests, including outside days 1–5.
  Reuse completed products and their fixed SPI calibration fits where applicable.
- Stage a completed monthly release before computing the site fingerprint. A
  failed page-staging step retries from completed products without downloading.
- Unfinished downloads after day 5 require manual catch-up. Accepted inputs
  awaiting maps may resume outside the window without new downloads.
- Failed updates retain the previous verified immutable monthly release and
  warn through the console/ntfy. Other daily products may still publish. With no
  verified retained monthly release, publication stops rather than uploading a
  broken page. A page behind the expected month after day 5 raises an overdue
  warning even if no new source request is allowed that day.
- Missing initial input manifests are errors: the daily runner will not bootstrap
  the historical record. Transfer each machine's monthly cache before enabling.

The final console/ntfy summary includes the month on the site, requests, changed
inputs, maps built/reused and monthly elapsed time. Completed new builds also
send a progress notice; failures/pending cycles send warnings. Normal completed
or skipped days do not send a separate progress notice. Dry-run notification
behavior follows the existing daily runner. Its `dry_run` controls remote sync;
local data updates, including monthly work when enabled, can still occur.

The main daily log schema is unchanged. Monthly details are appended to
`data/diagnostics/prism-monthly-update/daily-publish.csv`. Updater per-cycle
records and the retained-release check report remain available separately.
Site-only publishing does not run monthly calculations. Disabling the flag
retains the existing Monthly Climate page and images.

## Laptop tests

```r
# Offline scheduler, failure, rollback, retry and daily integration tests.
source("scripts/test-monthly-daily-runner.R")

# Check an already-completed real cycle, forbidding source requests/builds/staging.
source("scripts/check-monthly-daily-runner.R")
```

The real-cache check writes only diagnostic reports/logs. If reconciliation is
needed, run `source("scripts/stage-prism-monthly-site.R")` and repeat. If a new
update is scheduled, use the normal updater; the check forbids source requests.

## Staging VM checkout and enablement

Commit/push the laptop changes to `codex/daily-explorer` and record its hash.
Include the new `R/monthly-publish.R`, modified daily publisher/updater/preflight,
daily entry-point comments, both new check/test scripts, tests and documentation.
Then run on the VM:

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
(
  set -e
  exec 9>/home/crimmins/.local/state/swclimatewatch-staging/daily.lock
  flock -n 9

  git stash push -m "Staging generated pages before monthly runner integration" -- \
    site/index.qmd site/pages/_synopsis-content.qmd \
    site/pages/current-snow.qmd site/pages/monthly-climate.qmd \
    site/pages/snow-conditions.qmd
  test -z "$(git status --porcelain --untracked-files=no)"
  git fetch origin codex/daily-explorer
  git checkout --detach FETCH_HEAD
  git rev-parse HEAD

  config=/home/crimmins/.config/swclimatewatch/staging.env
  sed -i '/^SWC_MONTHLY_MAPS=/d' "$config"
  printf '\nSWC_MONTHLY_MAPS=true\n' >> "$config"
  set -a
  source "$config"
  set +a
  export TZ=America/Phoenix
  test "$SWC_S3_DESTINATION" = "s3://cales-climate-reports/climate/watch-staging/"
  test "$SWC_PRODUCTION_STATE_DIR" = "/home/crimmins/.local/state/swclimatewatch-staging"

  Rscript scripts/stage-prism-monthly-site.R
  Rscript scripts/check-monthly-daily-runner.R
)
```

Compare the printed VM hash with the laptop release. Staging restores the VM's
own generated monthly page after checkout, with no laptop-image substitution.
Neither R command downloads or publishes. Preflight checks `filelock`, `MASS`
and the monthly input manifest when the feature is enabled.

After that block releases its lock, use the existing runner:

```bash
SWC_PRODUCTION_CONFIG=/home/crimmins/.config/swclimatewatch/staging.env \
  bash scripts/run-production-daily.sh --check

SWC_PRODUCTION_CONFIG=/home/crimmins/.config/swclimatewatch/staging.env \
  bash scripts/run-production-daily.sh
```

The second command runs the real daily workflow and uploads to **watch-staging**.
For the verified November cycle, expect `Monthly Climate: through October 2026;
cycle already complete; no new requests`. Check that line in the console and
ntfy summary, the monthly daily log, the page month and the publication checks.
Production checkout/configuration remain untouched by these commands.

## Manual catch-up and promotion

For a missed source window, run the following under the VM's destination lock:

```r
source("scripts/load-prism-monthly.R")
result <- run_prism_monthly_update(manual = TRUE)
print(result$summary)
```

The next daily run stages the completed release. To publish immediately, use the
existing monthly staging and site-only commands. Do not leave a manual override
in cron or falsify run dates to simulate future months.

After staging approval, production needs this tested code, its own monthly
cache/SPI fits and verified page/products, plus `SWC_MONTHLY_MAPS=true` in
**production.env**. Each checkout keeps its own revision state. Do not share a
mutable staging cache or state/lock directory with production.
