#!/usr/bin/env bash
# Resume a failed combined-Explorer publication after the code fix is checked out.
set -euo pipefail
umask 077
cd /home/crimmins/RProjects/SWClimateWatch
set -a
source /home/crimmins/.config/swclimatewatch/production.env
set +a
export TZ=America/Phoenix
export PATH="/usr/local/bin:/usr/lib/rstudio-server/bin/quarto/bin:/usr/bin:/bin:$PATH"
test "$SWC_S3_DESTINATION" = "s3://cales-climate-reports/climate/watch/"
test "$SWC_PRODUCTION_STATE_DIR" = "/home/crimmins/.local/state/swclimatewatch"
test "${SWC_DAILY_CONNECTED:-false}" = true
exec 9>"$SWC_PRODUCTION_STATE_DIR/daily.lock"
flock -n 9 || { echo "STOP: a production job is running."; exit 1; }
for year in 2025 2026; do test -f "data/diagnostics/daily-explorer-wy${year}-release/wy${year}-release.json"; done
unset SWC_DAILY_CONNECTED_STAGING SWC_DAILY_WY2025_STAGING SWC_DAILY_ARCHIVE_STAGING SWC_NWS_HAZARDS_STAGING SWC_STORM_REPORTS_STAGING
export SWC_DAILY_CONNECTED=true SWC_NWS_HAZARDS=true SWC_STORM_REPORTS=true
export SWC_CONNECTED_RELEASE_COMMIT=$(git rev-parse HEAD)
mkdir -p "$SWC_PRODUCTION_STATE_DIR/logs"
log="$SWC_PRODUCTION_STATE_DIR/logs/connected-retry-$(date +%Y%m%dT%H%M%S).log"
exec > >(tee -a "$log") 2>&1
echo "Log: $log"
git rev-parse HEAD
Rscript -e 'testthat::test_file("tests/testthat/test-daily-explorer-connected-publication.R",stop_on_failure=TRUE)'
Rscript scripts/publish-site-s3.R
echo "PASS: combined Explorer production publication completed; hazard seals and both archives validated."
