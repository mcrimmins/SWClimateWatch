# Automatic Interactive Snow refresh and promotion

**Production complete November 17, 2026.** The user confirmed staging and
production after the ordering correction (`bf159b6`). Production publication
completed in 7m 08s; all 54 current and 352 historic maps passed. Source and
rendered viewer validation passed for the November 17 Snow release, with
seven-day change available (180 assets; 109,252,882 bytes). The Snow refresh
reported `READY`, one snapshot/four metrics, in 7.766 seconds. The separate
weather warning represented one missing date (76/77 Explorer coverage).

No promotion remains. Confirm the next scheduled daily Snow refresh separately;
the commands below are retained as release/recovery instructions.

The user accepted the Snow viewer on staging at `050c7ec47884542ab93b6adeb178b1de60979f18`.
This increment enables automatic Snow refresh by default in the existing shared
Interactive Maps staging step. Both the daily runner and site-only publisher
use it. No cron edit, API key or cache transfer is required. An explicit
`SWC_INTERACTIVE_SNOW=false` remains an opt-out.

## Behavior

- The normal daily SNODAS update precedes the viewer and unchanged-site check.
  The viewer uses only the verified Current Snow date, images and reference
  signature. The historical winter example is excluded.
- A checkout that resets the generated Snow page, or a changed code/input
  signature, triggers the normal cached map rebuild for the **same** verified
  date. It uses the existing quality gate and makes no source downloads. A
  failed/held rebuild stops publication rather than editing the signature.
- Unchanged releases and base PRISM manifests reuse the verified Snow bundle.
  A reset site can be restaged from the verified cache. Corruption causes a
  rebuild; source revisions, a new date, or changed seven-day availability
  invalidate reuse. Missing exact endpoints remain unavailable.
- A new active snow season without a verified release gets `WAITING`, clearing
  a retained prior-season Snow selection. Outside the active update season,
  the last verified snapshot may remain, with its actual date. Explicit
  disablement also removes a retained Snow selection.
- The workflow CSV and daily summary report Snow status, date and seven-day
  availability. Four Snow metrics are included in the current-product count.
  Snow refresh failure stops the sync. Existing static Snow maps are unaffected
  by the viewer opt-out.

Reports: `data/diagnostics/interactive-map-pilot/workflow-status.csv` and
`data/diagnostics/interactive-map-snow-current/{workflow-status.csv,refresh-state.rds}`.

## Laptop

In RStudio, run:

```r
setwd("C:/Users/Crimmins/RProjects/SWClimateWatch")
source("scripts/test-interactive-map-snow-workflow.R")
```

Then in Windows Command Prompt:

```bat
cd /d C:\Users\Crimmins\RProjects\SWClimateWatch
git add R/daily-publish.R R/interactive-map-snow-current.R
git add scripts/stage-cached-interactive-map-site.R scripts/check-interactive-map-snow-current.R scripts/production.env.example scripts/test-interactive-map-snow-workflow.R
git add scripts/deploy-site-s3.R scripts/prepare-interactive-map-snow-current.R
git add tests/testthat/test-interactive-map-workflow.R tests/testthat/test-interactive-map-snow-workflow.R
git add tests/testthat/test-deploy-site-s3.R tests/testthat/test-interactive-snow-publication-order.R
git add docs/development-roadmap.md docs/interactive-map-snow-pilot.md docs/interactive-map-snow-staging.md docs/interactive-map-snow-daily.md
git diff --cached --stat
git diff --cached --check
git commit -m "Refresh verified Snow viewer automatically during daily publication"
git push origin codex/daily-explorer
git rev-parse HEAD
```

Do not stage generated Home/synopsis/Snow pages, climate data, local Node,
unrelated IVT files, or stray pasted-command filenames.

## VM: update staging

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
(
  set -e
  exec 9>/home/crimmins/.local/state/swclimatewatch-staging/daily.lock
  flock -n 9 || { echo "STOP: staging job running."; exit 1; }
  git stash push -m "Staging generated pages before automatic Snow viewer" -- \
    site/index.qmd site/pages/_synopsis-content.qmd site/pages/current-snow.qmd \
    site/pages/snow-conditions.qmd site/pages/monthly-climate.qmd
  git status --short
  test -z "$(git status --porcelain --untracked-files=no)"
  git fetch origin codex/daily-explorer
  git checkout --detach FETCH_HEAD
  git rev-parse HEAD
)
```

Compare the hash with the laptop. Then run the full daily cycle, using the
explicit staging configuration (the runner acquires its own lock):

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
SWC_PRODUCTION_CONFIG=/home/crimmins/.config/swclimatewatch/staging.env bash scripts/run-production-daily.sh
TZ=America/Phoenix Rscript scripts/check-interactive-map-snow-current.R
cat data/diagnostics/interactive-map-snow-current/workflow-status.csv
```

Review the Snow date, four metrics and exact seven-day availability at
<https://cales.arizona.edu/climate/watch-staging/pages/interactive-maps.html>.
Expect `Interactive Snow: ready/reused; through <date>; seven-day change ...`.
The full daily run can take its usual climate-update time; this is not a
site-only run. No environment export is needed to keep Snow in later runs.

## VM: promote the tested staging commit

Run only after the staging daily cycle and rendered Snow check pass. This
records the former production commit and pins production to the exact staging
commit while both checkouts are locked. It copies no staging climate data over
production. Existing untracked generated water-year product pages may remain.

```bash
cd /home/crimmins/RProjects/SWClimateWatch
(
  set -e
  exec 8>/home/crimmins/.local/state/swclimatewatch-staging/daily.lock
  flock -n 8 || { echo "STOP: staging job running."; exit 1; }
  exec 9>/home/crimmins/.local/state/swclimatewatch/daily.lock
  flock -n 9 || { echo "STOP: production job running."; exit 1; }

  release_commit=$(git -C /home/crimmins/RProjects/SWClimateWatch-staging rev-parse HEAD)
  git rev-parse HEAD > /home/crimmins/.local/state/swclimatewatch/previous-production-commit.txt
  git stash push -m "Production generated pages before automatic Snow viewer" -- \
    site/index.qmd site/pages/_synopsis-content.qmd site/pages/current-snow.qmd \
    site/pages/snow-conditions.qmd site/pages/monthly-climate.qmd
  git status --short
  test -z "$(git status --porcelain --untracked-files=no)"
  git fetch origin codex/daily-explorer
  git checkout --detach "$release_commit"
  git rev-parse HEAD

  set -a
  source /home/crimmins/.config/swclimatewatch/production.env
  set +a
  export TZ=America/Phoenix
  export PATH="/usr/local/bin:/usr/lib/rstudio-server/bin/quarto/bin:/usr/bin:/bin:$PATH"
  test "$SWC_S3_DESTINATION" = "s3://cales-climate-reports/climate/watch/"
  test "$SWC_PRODUCTION_STATE_DIR" = "/home/crimmins/.local/state/swclimatewatch"
  SWC_S3_DESTINATION=s3://cales-climate-reports/climate/watch/ SWC_PRODUCTION_STATE_DIR=/home/crimmins/.local/state/swclimatewatch Rscript scripts/publish-site-s3.R
  Rscript scripts/check-interactive-map-snow-current.R
)
```

The production checkout's existing daily cron now uses automatic Snow refresh.
Confirm its next run reports the verified Snow date and matching change
availability. No persistent setting needs adding unless deliberately opting out.

## Local validation evidence

### Publication-order correction

The first production promotion attempt stopped at grouped-map validation:
`snow_swe`, `snow_departure` and `snow_percent` failed, and no S3 upload occurred.
The site-only publisher had recorded grouped-page image hashes before the new
viewer step reconciled the cached Current Snow maps. Their replacement bytes
then differed from those recorded hashes. The publisher now prepares cached
Snow before catalogs, synopsis and groups capture any image inventory. The late
viewer step finds the same verified release. All existing rendered checksum
guards remain enabled. Regression tests exercise this sequence with revised
image bytes and verify that a Snow preparation failure stops downstream stages.

For this correction commit, include `scripts/deploy-site-s3.R`,
`scripts/prepare-interactive-map-snow-current.R`,
`scripts/test-interactive-map-snow-workflow.R`,
`tests/testthat/test-deploy-site-s3.R`,
`tests/testthat/test-interactive-snow-publication-order.R`, and the updated
roadmap/release guide. The corrected site-only staging publication passed in
7m 06s, and its exact commit was successfully promoted to production. No cache
transfer or full daily download cycle was needed for this correction.

The fixture suite covers unchanged reuse, reset-page reconciliation, same-date
revisions, new dates, endpoint availability, corrupted cached payloads, changed
base PRISM manifests, quality holds, season rollover/WAITING, disablement, and
daily summary/order/publication failure guards. The native cached laptop check
rebuilt its older October 7 release through the existing quality gate, built
the Snow viewer, and reused it on the next call (about 1.9 seconds). That is a
local smoke measurement, not the VM daily-run timing.
