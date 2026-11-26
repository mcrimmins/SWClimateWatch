# Combined WY2025/WY2026 Explorer staging trial

Prepared November 26, 2026, after local acceptance of the combined Explorer.
The trial uses the VM's current conditions and both complete archive years
(730 archive dates). Trial URL:
<https://cales.arizona.edu/climate/watch-staging/daily-explorer/connected/>.
The standard Explorer entry remains intact until staging acceptance. This
guide supersedes the earlier one-year connected staging instructions.

## Laptop: export, commit, transfer

In RStudio, export only the verified WY2026 publication files:

```r
setwd("C:/Users/Crimmins/RProjects/SWClimateWatch")
source("scripts/export-daily-explorer-wy2026-staging.R")
```

Wait for PASS. This checks all source hashes, packages the manifest-listed
publication files and confirms the tar entry list and unchanged source release
before writing a GNU-compatible SHA256 sidecar. Do not rebuild/repair the
archive while exporting. The files are:

- `data/diagnostics/swc-daily-explorer-wy2026.tar.gz`
- `data/diagnostics/swc-daily-explorer-wy2026.tar.gz.sha256`

WY2025 is already imported on staging and needs no additional transfer. Raw
PRISM/CORe, decoded grids and intermediate work caches are not included.

In Windows Command Prompt:

```bat
cd /d C:\Users\Crimmins\RProjects\SWClimateWatch
git add --pathspec-from-file=scripts/daily-explorer-two-year-release-files.txt
git diff --cached --stat
git diff --cached --check
git commit -m "Stage combined Explorer with WY2026 archive and loading fixes"
git push origin codex/historic-monthly-pilot
git rev-parse HEAD
scp "data\diagnostics\swc-daily-explorer-wy2026.tar.gz" "data\diagnostics\swc-daily-explorer-wy2026.tar.gz.sha256" crimmins@10.222.142.128:/home/crimmins/incoming/
```

Review the staged file list before committing. Unrelated station documentation,
moisture pilots, generated pages and stray command-text files stay out.
The publication bundle is ignored by Git.

## VM: checkout and verified import

Replace the placeholder with the laptop hash. This block stops if there are
remaining tracked changes; it preserves generated navigation/pages in a stash.

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
(
  set -e
  expected_commit=PASTE_LAPTOP_COMMIT_HASH_HERE
  test "${#expected_commit}" -eq 40
  exec 9>/home/crimmins/.local/state/swclimatewatch-staging/daily.lock
  flock -n 9 || { echo "STOP: another staging job is running."; exit 1; }
  git fetch origin codex/historic-monthly-pilot
  test "$(git rev-parse FETCH_HEAD)" = "$expected_commit"
  git stash push -m "Staging generated pages before combined archive Explorer" -- \
    site/index.qmd site/_quarto.yml site/pages/_synopsis-content.qmd \
    site/pages/current-snow.qmd site/pages/snow-conditions.qmd \
    site/pages/monthly-climate.qmd site/pages/archive
  git status --short
  test -z "$(git status --porcelain --untracked-files=no)"
  git switch --detach "$expected_commit"
  test "$(git rev-parse HEAD)" = "$expected_commit"
  test -f scripts/import-daily-explorer-wy2026-staging.sh
  git rev-parse HEAD
)
```

Continue only after the block prints the laptop hash and completes without
error. After both transfer files have arrived:

```bash
bash -n scripts/import-daily-explorer-wy2026-staging.sh &&
bash scripts/import-daily-explorer-wy2026-staging.sh
```

The importer loads staging.env, verifies the exact bucket/state and takes the
staging lock. It checks SHA256 and bounded tar paths, extracts to a fresh
candidate, validates the complete native release and exact publication file
list, then moves it to `data/diagnostics/daily-explorer-wy2026-release/`.
Any previous import is preserved with a timestamp. An interrupted import
remains separate for inspection. No historical sources or maps are rebuilt.

## Publish and review

```bash
bash -n scripts/test-daily-explorer-connected-staging.sh &&
bash scripts/test-daily-explorer-connected-staging.sh publish
```

The script checks both imported releases, runs code tests, loads only staging
settings, locks the job and performs a cached site-only publication. WY2025
uses its existing retention adapter; WY2026 is staged from the imported bundle.
The static connected adapter adds only about 1.6 MB of navigation/metadata,
content-hashed browser assets and year-specific base paths. The context loader
uses private connected catalogs to cross archive-year boundaries, while all
PNGs, geometry and original archive catalogs stay at their existing paths.
The current viewer retains buffered dates for trailing views; completed
archives own overlapping dates in the year/month navigation.

Before upload, both imported/staged/rendered archive releases undergo full
hash, coverage and module checks. The connected catalog must match its source
date ownership and routing, include both years and have the same current
cutoff as the staged Explorer. Every sealed navigation asset and the
source/rendered connected release must agree. Incomplete/corrupt data stop
the upload. The central deploy guard rejects production destinations/state.

Review WY2025 → WY2026 → Current; September 30/October 1 in both transitions;
7-/30-day views; weather/report/hazard modules and timelines; saved links;
deferred thumbnails and narrow-screen layout. Local static browser QA passed
the archive-year transition, full-resolution map and return to the local
current cache. On staging, Current must reflect the VM's cache instead.

## Full daily-run retention

After visual acceptance of the site-only trial:

```bash
bash scripts/test-daily-explorer-connected-staging.sh daily
```

This uses a temporary staging config with both retention flags; permanent
environment files, production and cron are unchanged. It snapshots both
archive release hashes, runs the standard daily runner and requires fresh
combined-stage evidence. A skipped/locked run does not count as success.
Afterward both archive hashes must be unchanged and all imported/staged/
rendered checks pass again. Logs are printed under the staging state directory.
Standard entry-point replacement and production promotion follow acceptance.
