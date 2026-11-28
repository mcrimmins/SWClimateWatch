#!/usr/bin/env bash
# Re-render the standard staging Explorer using the verified Streamflow release.
# No observation refresh and no changes to production or permanent config.
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
export SWC_DAILY_CONNECTED=true SWC_STREAMFLOW=true
export SWC_CONNECTED_RELEASE_COMMIT
SWC_CONNECTED_RELEASE_COMMIT=$(git rev-parse HEAD)
mkdir -p "$SWC_PRODUCTION_STATE_DIR/logs"
log="$SWC_PRODUCTION_STATE_DIR/logs/streamflow-navigation-$(date +%Y%m%dT%H%M%S).log"
exec > >(tee -a "$log") 2>&1
echo "Log: $log"
echo "Commit: $SWC_CONNECTED_RELEASE_COMMIT"
Rscript scripts/test-streamflow-daily.R
Rscript -e 'source("R/streamflow-daily.R"); streamflow_verify_snapshot(file.path(streamflow_daily_root(),"release")); invisible(TRUE)'
Rscript scripts/publish-site-s3.R
Rscript -e 'source("R/streamflow-daily.R"); for(d in c("site/daily-explorer","site/_site/daily-explorer"))validate_streamflow_connected(d)'
echo "PASS: standard staging Explorer rebuilt with versioned jump-navigation fix."
echo "Review: https://cales.arizona.edu/climate/watch-staging/pages/daily-explorer.html"
