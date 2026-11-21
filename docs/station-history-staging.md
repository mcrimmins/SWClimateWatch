# Historical Station Conditions — staging trial

The manual trial below passed staging review November 21. Daily integration
testing follows [the daily release guide](station-history-daily.md).

November 21: the user confirmed both saved browser CSVs passed. Local chart,
CSV, narrow-layout, cache-reuse and snapshot tests passed. This increment is a
manual staging trial. Daily history refresh and production promotion remain
separate steps after review.

The staging changes also include the previously requested removal of the old
Historic Years pilot introduction, as a separate commit.

## Laptop preparation

In RStudio, from the project root:

```r
source("scripts/bundle-station-history-seed.R")
```

This creates `swc-station-history-seed.tar.gz` and its LF-terminated `.sha256`
sidecar in the project root. The initial bundle is 5.7 MiB. It includes the
catalog, completion summary and historical annual JSON/build markers. It
excludes raw climate grids, rendered site files, test CSVs and browser runtimes.

Commit explicit station-related files on `codex/historic-monthly-pilot`, push
that branch, and record the full commit hash. Leave the unrelated IVT pilots,
untracked test data and stray pasted-command files uncommitted. Transfer both
bundle files with SCP to `crimmins@10.222.142.128:/home/crimmins/incoming/`.

## VM checkout

Use the staging checkout only. Substitute the full laptop hash below:

```bash
cd /home/crimmins/RProjects/SWClimateWatch-staging
(
  set -e
  expected_commit=PASTE_THE_FULL_LAPTOP_HASH
  exec 9>/home/crimmins/.local/state/swclimatewatch-staging/daily.lock
  flock -n 9 || { echo "STOP: another staging job is running."; exit 1; }
  git stash push -m "Staging generated pages before station history" -- \
    site/index.qmd site/pages/_synopsis-content.qmd \
    site/pages/current-snow.qmd site/pages/snow-conditions.qmd \
    site/pages/monthly-climate.qmd site/pages/archive
  git status --short
  test -z "$(git status --porcelain --untracked-files=no)"
  git fetch origin codex/historic-monthly-pilot
  test "$(git rev-parse FETCH_HEAD)" = "$expected_commit"
  git checkout --detach "$expected_commit"
  git rev-parse HEAD
)
```

After the hashes match:

```bash
bash -n scripts/test-station-history-staging.sh
bash scripts/test-station-history-staging.sh
```

The script takes the staging lock, checks destination/state settings, verifies
the transferred checksum, preserves any previous history pilot and extracts the
seed. It requires the VM station caches to span at least the seed dates; if that
guard fails, stop and transfer the missing full station caches rather than
silently shortening the historical record. It then rebuilds screened Current
conditions from the VM's caches, reconciles the historical seed with those
caches, builds/stages the combined viewer, and publishes to staging only.
No ACIS observation requests are made. The first rebuild may take several
minutes, with labeled phases and per-station historical progress.

Required R packages include filelock, jsonlite, digest and xml2; the script stops
before importing the seed if any are unavailable. Node is not required for this
VM build; the JavaScript tests were run on the laptop. Logs are written under
`/home/crimmins/.local/state/swclimatewatch-staging/logs/` with the prefix
`station-history-staging-`.

## Review and validation

Open <https://cales.arizona.edu/climate/watch-staging/pages/station-conditions.html>.
Review Current conditions, Explore station history, switching stations, custom
dates, long selections, chart/table navigation, CSV downloads and narrow layout.
Current data dates must match the VM's verified snapshot; history dates remain
independent and station-specific. Check both the embedded page and full-screen
station explorer.

The normal station staging function now copies/version-checks both viewer apps
and validates the historical payloads before swapping the station directory.
The publisher checks the rendered history before S3 upload. The independent
post-publication check can be rerun with:

```bash
TZ=America/Phoenix Rscript scripts/check-station-history-publication.R
```

Missing payloads or stale asset hashes stop publication. Unit tests cover
preserving the last good page when a history file is missing. Existing station
pages without the history module keep their normal behavior.

The old archive introduction is removed by the cached Historic Years staging
step; no archive maps need rebuilding or transferring. A subsequent ordinary
staging daily run can replace this manual history trial until daily integration
is enabled. Production and its cron configuration are unchanged.

Shell syntax must be checked on the VM with `bash -n` above. The laptop's
restricted Git Bash could not initialize its Windows signal pipe; R and
JavaScript tests ran successfully on the laptop.
