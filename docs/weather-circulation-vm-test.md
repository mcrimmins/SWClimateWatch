# Isolated weather/circulation VM test

The approved local map design and three-date laptop test are ready for a VM
benchmark. This is the next gate before Daily Explorer integration. No changes
to production configuration, cron, public pages or S3 are included.

**Result reported October 26, 2026:** VM PASS; six maps in 12.604 seconds,
18.17 seconds for the whole script; cache check zero requests. These instructions
remain for reproducing the benchmark. The next step is review of the isolated
local Daily Explorer circulation preview described in the scope document.

## 1. Laptop: commit and push the pilot

Run in the SWClimateWatch project terminal (current branch: `codex/daily-explorer`).
Review the staged changes before committing.

```cmd
git add R/weather-circulation-pilot.R R/weather-circulation-recent-test.R scripts/load-weather-circulation-pilot.R scripts/run-weather-circulation-pilot.R scripts/run-weather-circulation-recent-test.R scripts/run-weather-circulation-vm-test.R tests/testthat/test-weather-circulation-pilot.R tests/testthat/test-weather-circulation-recent-test.R docs/weather-circulation-scope.md docs/weather-circulation-vm-test.md docs/development-roadmap.md
git diff --cached --stat
git commit -m "Add isolated CORe circulation pilot and VM benchmark"
git push origin codex/daily-explorer
git rev-parse HEAD
```

The generated maps and data are ignored and are not uploaded to Git.

## 2. VM: fetch into a dedicated small checkout

For the first run, create a separate worktree. This needs no existing data seed;
the pilot downloads only three selected fields per date. Do not update the
production checkout or use the daily production runner for this test.

```bash
cd /home/crimmins/RProjects/SWClimateWatch
git fetch origin codex/daily-explorer
git worktree add --detach /home/crimmins/RProjects/SWClimateWatch-weather-test FETCH_HEAD
cd /home/crimmins/RProjects/SWClimateWatch-weather-test
git rev-parse HEAD
```

The VM hash should match the laptop hash printed after committing. Stop and
resolve a mismatch before benchmarking. If this test worktree already exists,
inspect its status and commit before updating it; do not reset it blindly.

## 3. VM: run the bounded test

```bash
cd /home/crimmins/RProjects/SWClimateWatch-weather-test
mkdir -p data/diagnostics/weather-circulation-vm-test
set -o pipefail
TZ=America/Phoenix flock -n data/diagnostics/weather-circulation-vm-test/run.lock Rscript scripts/run-weather-circulation-vm-test.R 2>&1 | tee data/diagnostics/weather-circulation-vm-test/console.log
```

This probes the previous seven dates, downloads at most three dates, renders
six maps and checks a second pass with plotting disabled. There is no scheduled
job or S3 sync. The separate lock prevents duplicate benchmark runs; it does not
lock production. Run after the daily job finishes for representative timings
without resource contention. `pipefail` preserves a failing R exit status when
using `tee`.

The script saves R/package versions, platform, core count, time zone, commit,
session information, status and timing reports. It fails if dependencies are
missing, a probe reports an error, fewer than three dates build, decoding or
rendering fails, or verified download-cache reuse fails.

## 4. Share the results

```bash
cat data/diagnostics/weather-circulation-vm-test/vm-test-status.csv
cat data/diagnostics/weather-circulation-vm-test/recent-test-summary.csv
cat data/diagnostics/weather-circulation-vm-test/first-pass.csv
cat data/diagnostics/weather-circulation-vm-test/environment.csv
```

The first run measures new downloads. Later invocations reuse existing dates,
so retain the first report or console output when comparing. Use a new dated
output location only when deliberately planning another cold benchmark; do not
remove production or historical caches.

## Next integration gate

After reviewing VM results, develop date-linked circulation panels locally:

- Separate optional manifest and collapsible panel, preserving current PRISM
  variables and date controls. Load images only when the panel is opened.
- Exact selected UTC date only; explicitly unavailable if missing. Do not
  silently substitute the latest circulation date for the selected PRISM date.
- Explain that UTC daily circulation means and PRISM reporting periods differ.
- Add an input/renderer fingerprint for map reuse and a bounded source-recheck
  policy. Current pilot download caches verify local hashes; plotting always
  reruns and upstream revisions are not automatically detected.
- Keep optional weather failures isolated from core publication, with explicit
  freshness/status reporting and staging validation.
- First test a short window in the local Daily Explorer. Baseline anomalies,
  historical backfill and production enablement require separate decisions.

The existing Daily Explorer validates its own PRISM image names and manifest.
Keep optional circulation assets separate rather than weakening those checks.
