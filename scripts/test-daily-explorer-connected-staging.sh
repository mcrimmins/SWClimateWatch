#!/usr/bin/env bash
set -euo pipefail
umask 077
cd /home/crimmins/RProjects/SWClimateWatch-staging
set -a
source /home/crimmins/.config/swclimatewatch/staging.env
set +a
export TZ=America/Phoenix
export PATH="/usr/local/bin:/usr/lib/rstudio-server/bin/quarto/bin:/usr/bin:/bin:$PATH"
test "$SWC_S3_DESTINATION" = "s3://cales-climate-reports/climate/watch-staging/"
test "$SWC_PRODUCTION_STATE_DIR" = "/home/crimmins/.local/state/swclimatewatch-staging"
mkdir -p "$SWC_PRODUCTION_STATE_DIR/logs"
log="$SWC_PRODUCTION_STATE_DIR/logs/connected-explorer-$(date +%Y%m%dT%H%M%S).log"
exec > >(tee -a "$log") 2>&1
echo "Log: $log"
exec 9>"$SWC_PRODUCTION_STATE_DIR/daily.lock"
flock -n 9 || { echo "STOP: another staging job is running."; exit 1; }
git rev-parse HEAD
test -f data/diagnostics/daily-explorer-wy2025-release/wy2025-release.json
unset SWC_DAILY_ARCHIVE_STAGING SWC_NWS_HAZARDS_STAGING SWC_STORM_REPORTS_STAGING
export SWC_NWS_HAZARDS=true SWC_STORM_REPORTS=true
export SWC_DAILY_WY2025_STAGING=true SWC_DAILY_CONNECTED_STAGING=true
Rscript -e 'for(f in c("tests/testthat/test-daily-explorer-connected.R","tests/testthat/test-daily-explorer-connected-staging.R")) testthat::test_file(f,stop_on_failure=TRUE)'
Rscript scripts/publish-site-s3.R
Rscript -e 'source("R/daily-explorer-connected-staging.R"); validate_connected_trial()'
echo "Trial URL: https://cales.arizona.edu/climate/watch-staging/daily-explorer/connected/"
echo "Staging only. Standard Explorer entry, production and permanent environment files unchanged."
