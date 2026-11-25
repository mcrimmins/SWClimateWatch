# WY2025 Daily Explorer staging trial

Local acceptance reported November 24, 2026: twelve complete months, 365 dates,
5,840 maps and their storm report/hazard coverage. Staging acceptance and
production promotion remain pending. The explicit staging-only flag is
`SWC_DAILY_WY2025_STAGING=true`; it rejects production destinations/state
before work and in the central deploy validation before uploads.

Trial URL:
<https://cales.arizona.edu/climate/watch-staging/daily-explorer/archive/wy2025/>

The regular current Daily Explorer and earlier July archive trial remain
separate. This step adds no production navigation, scheduled backfill or
permanent environment changes and performs no cache cleanup.

## Laptop: export and commit

In RStudio, validate and package the accepted preview:

```r
setwd("C:/Users/Crimmins/RProjects/SWClimateWatch")
source("scripts/export-daily-explorer-wy2025-staging.R")
```

The bundle can take several minutes to package and verify. Export includes
only `wy2025-release.json` and its exact manifest-listed publication files,
validates all source hashes and the tar entry list, and writes a GNU-compatible
SHA256 sidecar. It excludes raw grids, decoded weather, input markers, work
directories and unrelated stale preview files. Do not rebuild the archive while
packaging. Both files must finish successfully before transferring:

- `data/diagnostics/swc-daily-explorer-wy2025.tar.gz`
- `data/diagnostics/swc-daily-explorer-wy2025.tar.gz.sha256`

In Windows Command Prompt:

```bat
cd /d C:\Users\Crimmins\RProjects\SWClimateWatch
git add --pathspec-from-file=scripts/daily-explorer-wy2025-release-files.txt
git diff --cached --stat
git diff --cached --check
git commit -m "Add resumable WY2025 Daily Explorer archive and staging trial"
git push origin codex/historic-monthly-pilot
git rev-parse HEAD
scp "data\diagnostics\swc-daily-explorer-wy2025.tar.gz" "data\diagnostics\swc-daily-explorer-wy2025.tar.gz.sha256" crimmins@10.222.142.128:/home/crimmins/incoming/
```

The explicit commit list includes the shared seasonal/year builder changes
and staging guards. Check the staged diff before committing; unrelated station
documentation, moisture pilots, generated product pages, fixtures and stray
command-text files stay out. Data bundles remain ignored by Git.

## VM: checkout and import

Use the staging checkout. Paste the laptop commit into `expected_commit`.
The following checks stop if other tracked edits remain. Generated pages and
navigation are preserved in a stash, including `site/_quarto.yml`, which has
needed preservation during earlier staging tests. Untracked generated product
pages are left intact.

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
(
  set -euo pipefail
  expected_commit=PASTE_LAPTOP_COMMIT_HERE
  exec 9>/home/crimmins/.local/state/swclimatewatch-staging/daily.lock
  flock -n 9 || { echo "STOP: another staging job is running."; exit 1; }
  git stash push -m "Staging generated pages before WY2025 Explorer" -- \
    site/_quarto.yml site/index.qmd site/pages/_synopsis-content.qmd \
    site/pages/current-snow.qmd site/pages/snow-conditions.qmd \
    site/pages/monthly-climate.qmd site/pages/archive
  git status --short
  test -z "$(git status --porcelain --untracked-files=no)" || {
    echo "STOP: tracked changes remain; preserve/review them before checkout."
    exit 1
  }
  git fetch origin codex/historic-monthly-pilot
  test "$(git rev-parse FETCH_HEAD)" = "$expected_commit"
  git checkout --detach "$expected_commit"
  git rev-parse HEAD
  (cd /home/crimmins/incoming && sha256sum -c swc-daily-explorer-wy2025.tar.gz.sha256)
  mkdir -p data/diagnostics/daily-explorer-wy2025-release
  tar -xzf /home/crimmins/incoming/swc-daily-explorer-wy2025.tar.gz \
    -C data/diagnostics/daily-explorer-wy2025-release
  TZ=America/Phoenix Rscript -e 'source("scripts/load-daily-explorer-wy2025.R"); validate_wy2025_explorer_navigation("data/diagnostics/daily-explorer-wy2025-release")'
)
```

Import only the publication bundle. No historical source-data fetches or map
renders are needed on the VM. Keep the current incoming bundle/checksum until
staging and eventual production acceptance; do not copy staging's entire data
directory into production.

## Publish, review and retention

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
bash -n scripts/test-daily-explorer-wy2025-staging.sh && \
bash scripts/test-daily-explorer-wy2025-staging.sh publish
```

The script loads staging.env, checks destination/state, takes the daily lock,
enables process-only flags and runs the normal cached site publication. It
stages the imported release under `site/daily-explorer/archive/wy2025/`.
Every referenced source/rendered asset must validate, and both release digests
must equal the imported release before S3 upload. The existing Quarto resource
rule covers the nested archive. A timestamped log is printed.

Review at least one date per month, October 1/September 30, month-boundary
7-/30-day views, both timeline rows, report/hazard lookbacks, region/type
filters, weather means, saved links and narrow-screen layout. Check the normal
current Explorer too. Then test a full daily-run refresh/retention:

```bash
bash scripts/test-daily-explorer-wy2025-staging.sh daily
```

This uses a temporary staging configuration and the standard VM runner. A
fresh WY2025 staging report must exist, the saved release digest must remain
unchanged and the imported, staged and rendered releases must still pass.
Skipped/locked jobs do not count as successful retention tests. After review,
production promotion is a separate step.
