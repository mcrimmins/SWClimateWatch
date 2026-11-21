# Historical Station Conditions — daily workflow

Manual staging and browser review passed November 21. The daily integration is
implemented locally; a full staging daily run is the next release gate.
Production has not been enabled by this change.

## Behavior and failure handling

Enable with `SWC_STATION_HISTORY=true` in the VM's installed configuration.
The default is false until the release is promoted deliberately.

The existing station job fetches its usual observations, builds the screened
Current conditions snapshot, then prepares history from those same cached
observations before the atomic station-directory swap. History makes no extra
ACIS observation requests. Unchanged annual chunks are reused; appended dates
and historical corrections regenerate their affected years. Current conditions
and history remain together in the same station page, with the reviewed tabs,
independent history dates, linked tables and daily CSV exports.

The daily integration overlays the current diagnostics snapshot rather than
copying the entire seasonal/climatology preview tree. Immutable historical
payload timestamps survive copying/staging. Only obsolete generated annual/index
JSON is pruned from the diagnostics copy; no raw station observations are deleted.

A missing, corrupt or shortened source history fails the station update before
its public directory is replaced. The normal daily workflow retains the last
verified station page and reports the station error while other products can
continue. The history report distinguishes prepared history from successful
station staging; the staging test requires an actually successful station job,
matching source/rendered manifests and full payload validation.

The policy signature now hashes function code text, independent of the source
environment used by RStudio/Rscript/the isolated daily loader. The first run
under this policy may rebuild the annual cache once; subsequent runs reuse it.
This one-time migration is expected and does not add data requests.

## Local verification

```r
source("scripts/test-station-history-daily.R")
```

Checks cover opt-in/default-off behavior, normal daily loading, overlay-before-
stage ordering, failure retention, shorter-record rejection, affected-year reuse,
stable policy signatures and the daily report. Existing station publication,
cache versioning and the broader daily-publisher tests are included.

The three-station copied-cache simulation (263 annual chunks) rebuilt exactly
three years after appending one day, and three after older corrections, reusing
260 in each case (9.35 s and 9.11 s on the laptop). A fresh Rscript process reused
all 263 chunks with zero rebuilds in 1.21 s. These sample timings do not replace
the 62-station VM daily-run measurement. No live laptop station cache was changed.

## Laptop release

Commit the daily integration files and push `codex/historic-monthly-pilot`.
Record the full commit hash. No new cache transfer is needed for staging: the
manual staging trial already seeded and validated its 62-station history.

## VM staging test

Use the staging checkout and its usual release lock to preserve generated
pages, fetch the branch and check out the pushed commit. Include `site/_quarto.yml`
in the generated-file stash because cached Historic Years staging updates it.
Compare the full VM hash with the laptop before proceeding.

```bash
bash -n scripts/test-station-history-daily-staging.sh
bash scripts/test-station-history-daily-staging.sh
```

The script guards the staging destination/state directory, takes the release
lock while backing up and updating **only staging.env**, and persists
`SWC_STATION_HISTORY=true`. It then invokes the normal VM runner with
`SWC_PRODUCTION_CONFIG` explicitly pointing at staging.env: preflight followed
by the complete daily workflow. The runner owns its normal lock and log file;
the wrapper does not hold a competing lock during the run. Skipped runs and
station/history failures do not count as a successful trial.

Expected log evidence includes:

```text
Stations: updated; 62 records (51 mapped).
Station history: READY; 62 stations, ... annual chunks; ... rebuilt, ... reused; 0 extra observation requests (...s).
VM runner finished: exit=0; ...
PASS: staging daily history workflow completed. Production configuration is unchanged.
```

Delayed observations can legitimately report updated-with-stale-stations; their
dates/coverage remain visible. Review both Station Conditions tabs after the run
and retain the commit hash, full summary and history timing/copy counts.

The standalone checks are:

```bash
TZ=America/Phoenix Rscript scripts/check-station-history-publication.R
TZ=America/Phoenix Rscript scripts/check-station-history-daily.R
```

## Production preparation

After the full staging run and user review pass, promote that exact commit,
prepare/verify the production historical cache from the tested staging seed or
production's full raw station caches, then enable the same flag in production.env
under the production release lock. Back up production's prior commit/config and
retain the normal station cache/date/publication guards. Run and validate the
production workflow before treating the release as live. No production checkout,
configuration edit or upload is performed by the staging script.

For rollback, restore the prior reviewed commit/config or set the flag false;
the next successful standard station update restores the existing Current
conditions page. Keep the historical cache for later diagnosis/retry.
