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
exec 9>"$SWC_PRODUCTION_STATE_DIR/daily.lock"
flock -n 9 || { echo "STOP: another staging job is running."; exit 1; }
unset SWC_DAILY_CONNECTED_STAGING SWC_DAILY_WY2025_STAGING SWC_DAILY_ARCHIVE_STAGING SWC_NWS_HAZARDS_STAGING SWC_STORM_REPORTS_STAGING
export SWC_DAILY_CONNECTED=true
export SWC_NWS_HAZARDS=true SWC_STORM_REPORTS=true
mkdir -p "$SWC_PRODUCTION_STATE_DIR/logs"
log="$SWC_PRODUCTION_STATE_DIR/logs/connected-entry-$(date +%Y%m%dT%H%M%S).log"
exec > >(tee -a "$log") 2>&1
echo "Log: $log"
git rev-parse HEAD
export SWC_CONNECTED_RELEASE_COMMIT=$(git rev-parse HEAD)
Rscript -e 'testthat::test_file("tests/testthat/test-daily-explorer-connected-publication.R",stop_on_failure=TRUE)'
Rscript scripts/publish-site-s3.R
echo "PASS: production-compatible adapter and standard Daily Explorer entry published to staging."
