# Streamflow and Explorer navigation staging trial

Prepared November 27, 2026. This manual trial publishes only
`climate/watch-staging/daily-explorer/streamflow-trial/`. It includes the inline
Streamflow section, collapsed gauge table, linked date/window/region controls and
sticky product jump buttons. The normal staging Explorer and production are not
replaced; automatic streamflow refresh is not enabled yet.

## Laptop: R console

```r
setwd("C:/Users/Crimmins/RProjects/SWClimateWatch")
source("scripts/build-daily-explorer-streamflow.R")
source("scripts/test-daily-explorer-streamflow.R")
source("scripts/test-streamflow-staging.R")
source("scripts/export-streamflow-staging.R")
```

Transfer both files:

- `data/diagnostics/streamflow-transfer/swc-streamflow-seed.tar.gz`
- `data/diagnostics/streamflow-transfer/swc-streamflow-seed.tar.gz.sha256`

The verified package is approximately 1.6 MB compressed, containing 542 files
and approximately 10 MB uncompressed. It contains only the public USGS raw
observation/metadata cache, approved historical-statistics cache and the
32-gauge processed state/viewer. It excludes other datasets, credentials,
environment files and local executables. No Daily Explorer archive transfer is
needed: both archives already exist on the VM.

## Laptop: Windows terminal

Commands work as individual lines in Command Prompt or PowerShell. Inspect the
staged file list before committing; unrelated cleanup/documentation work should
remain outside this release.

```text
cd C:\Users\Crimmins\RProjects\SWClimateWatch
git add .gitattributes "R/streamflow-*.R" "scripts/*streamflow*.R" scripts/test-streamflow-staging.sh scripts/streamflow-assets "docs/streamflow-*.md" "tests/streamflow-*.cjs" "tests/testthat/test-streamflow-*.R"
git diff --cached --stat
git commit -m "Prepare Streamflow and Explorer navigation for staging"
git push origin codex/historic-monthly-pilot
git rev-parse HEAD
ssh crimmins@10.222.142.128 "mkdir -p /home/crimmins/incoming"
scp data\diagnostics\streamflow-transfer\swc-streamflow-seed.tar.gz data\diagnostics\streamflow-transfer\swc-streamflow-seed.tar.gz.sha256 crimmins@10.222.142.128:/home/crimmins/incoming/
```

The shared roadmap has other pending changes; this explicit commit list includes
the dedicated Streamflow documentation instead of committing those other edits.

## VM: checkout

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
(
  set -e
  exec 9>/home/crimmins/.local/state/swclimatewatch-staging/daily.lock
  flock -n 9 || { echo "STOP: another staging job is running."; exit 1; }

  git stash push -m "Staging generated pages before Streamflow trial" -- \
    site/index.qmd site/_quarto.yml site/pages/_synopsis-content.qmd \
    site/pages/snow-conditions.qmd site/pages/monthly-climate.qmd \
    site/pages/daily-explorer.qmd site/pages/archive

  if test -n "$(git status --porcelain --untracked-files=no)"; then
    git status --short
    echo "STOP: tracked changes remain; review them before checkout."
    exit 1
  fi
  git fetch origin codex/historic-monthly-pilot
  release_commit=$(git rev-parse FETCH_HEAD)
  echo "Staging commit: $release_commit"
  git switch --detach "$release_commit"
  test "$(git rev-parse HEAD)" = "$release_commit"
  git log -1 --oneline
)
```

Confirm the printed commit matches the laptop. Existing untracked product pages
are preserved. Then run:

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
bash -n scripts/test-streamflow-staging.sh &&
bash scripts/test-streamflow-staging.sh \
  /home/crimmins/incoming/swc-streamflow-seed.tar.gz
```

## What the VM script does

It checks the staging checkout/destination/state, holds the staging lock, verifies
the package checksum and every imported file, and preserves differing pre-existing
streamflow cache files in a dated backup. It then performs a real incremental
USGS update on the VM using the short revision overlap. Publication stops unless
the complete update meets the 60-second target with no cold-history repairs or
metadata/statistics downloads.

The static trial uses the VM's already-rendered current Explorer and both accepted
archive years. It versions new JS/CSS assets and verifies the full trial manifest,
32 gauge histories and archive routes. It confirms the rendered connected release
matches the one already uploaded to staging. It uploads only the trial prefix,
with browser revalidation headers and no S3 deletion. This small static trial
does not require a full Quarto render or normal daily run.

If the rendered/published seal check fails, finish the normal staging publication
first and rerun the trial; do not bypass the check. Failed/slow VM benchmarks stop
before publication and leave their diagnostics for review.

## Review and evidence

Review https://cales.arizona.edu/climate/watch-staging/daily-explorer/streamflow-trial/

Check the product jump buttons; the initially collapsed Streamflow section and
gauge table; historical date colors/values; 7-/30-day synchronization; 90-day
Streamflow-only window; selected gauge persistence; displayed-window CSV; and
explicit unavailable messages on older archive dates. Actual gauge dates and
USGS reporting conventions remain visible.

Logs: `/home/crimmins/.local/state/swclimatewatch-staging/logs/streamflow-staging-*.log`.
VM benchmark: `data/diagnostics/streamflow-network-pilot/benchmark-history.csv`.
Trial manifest: `data/diagnostics/streamflow-staging/viewer/streamflow-staging-release.json`.

The next step after successful review is to plan standard-site and daily-runner
integration, including the slower metadata/statistics refresh policy. This trial
does not make those operational changes.
