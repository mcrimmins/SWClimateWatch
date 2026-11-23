#!/usr/bin/env bash
# Manual staging trial only; does not enable automatic daily hazard updates.
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
log="$SWC_PRODUCTION_STATE_DIR/logs/nws-hazards-staging-$(date +%Y%m%dT%H%M%S).log"
exec > >(tee -a "$log") 2>&1
echo "Log: $log"
git rev-parse HEAD
Rscript -e 'p<-c("sf","maps","httr2","jsonlite","digest","leaflet"); missing<-p[!vapply(p,requireNamespace,logical(1),quietly=TRUE)]; if(length(missing))stop("Missing packages: ",paste(missing,collapse=", "))'
unset SWC_STORM_REPORTS_STAGING
export SWC_STORM_REPORTS=true
export SWC_NWS_HAZARDS_STAGING=true
echo "Build hazards for retained VM Explorer dates; reuse cached maps and reports..."
Rscript scripts/publish-site-s3.R
Rscript scripts/check-nws-hazards-publication.R
echo "NWS hazards staging trial complete. Automatic daily hazard refresh is not yet enabled."
