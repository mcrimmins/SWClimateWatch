#!/usr/bin/env bash
# Manual trial only. No production changes or persistent daily opt-in.
set -euo pipefail
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
mkdir -p "$SWC_PRODUCTION_STATE_DIR/logs"
log="$SWC_PRODUCTION_STATE_DIR/logs/storm-reports-staging-$(date +%Y%m%dT%H%M%S).log"
exec > >(tee -a "$log") 2>&1
echo "Log: $log"
git rev-parse HEAD
Rscript -e 'p<-c("httr2","jsonlite","digest","leaflet"); missing<-p[!vapply(p,requireNamespace,logical(1),quietly=TRUE)]; if(length(missing))stop("Missing packages: ",paste(missing,collapse=", "))'
export SWC_STORM_REPORTS_STAGING=true
echo "Build cached Explorer and storm reports, render, validate, and publish to staging..."
Rscript scripts/publish-site-s3.R
echo "Verify source/rendered report dates, counts, timing summaries and browser assets..."
Rscript scripts/check-storm-reports-publication.R
echo "Storm report staging trial complete. Automatic daily report refresh remains disabled."
