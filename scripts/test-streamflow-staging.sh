#!/usr/bin/env bash
# Manual, isolated Streamflow trial. No production or permanent daily flags.
set -euo pipefail
umask 077
if [[ $# -ne 1 ]]; then echo "Usage: bash scripts/test-streamflow-staging.sh /path/to/swc-streamflow-seed.tar.gz | --cached"; exit 2; fi
bundle=$1
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
log="$SWC_PRODUCTION_STATE_DIR/logs/streamflow-staging-$(date +%Y%m%dT%H%M%S).log"
exec > >(tee -a "$log") 2>&1
echo "Log: $log"
export SWC_STREAMFLOW_COMMIT
SWC_STREAMFLOW_COMMIT=$(git rev-parse HEAD)
echo "Commit: $SWC_STREAMFLOW_COMMIT"
command -v aws >/dev/null
Rscript -e 'source("R/streamflow-staging.R"); streamflow_staging_guard(); p<-c("jsonlite","digest","httr2","leaflet","testthat","withr"); missing<-p[!vapply(p,requireNamespace,logical(1),quietly=TRUE)]; if(length(missing))stop("Missing packages: ",paste(missing,collapse=", ")); source("scripts/find-streamflow-test-node.R"); print(find_streamflow_test_node()); stopifnot(file.exists("site/_site/daily-explorer/connected/connected-release.json"))'
echo "1/5: Verify and import public USGS caches; preserve differing existing files..."
if [[ "$bundle" == --cached ]]; then
  echo "Reusing the verified VM snapshot; no cache import or USGS requests."
  Rscript -e 'p<-jsonlite::read_json("data/diagnostics/streamflow-network-pilot/viewer/streamflow-data.json"); stopifnot(isTRUE(p$network_assessment),length(p$gauges)==32L)'
else
Rscript scripts/import-streamflow-staging.R "$bundle"
echo "2/5: Benchmark a live incremental update on the VM (bounded recent overlap)..."
Rscript -e 'source("scripts/load-streamflow-network.R"); x<-run_streamflow_network(Sys.Date()-1L,"incremental_live",download=TRUE); if(!isTRUE(x$summary$within_runtime_target))stop("VM benchmark did not meet the complete-refresh 60-second target; inspect benchmark-history.csv before publication.")'
fi
echo "3/5: Test cache/quality safeguards and build the versioned static review..."
Rscript scripts/test-streamflow-network.R
Rscript scripts/test-streamflow-staging.R
Rscript scripts/build-streamflow-staging.R
Rscript scripts/check-streamflow-staging.R
echo "4/5: Confirm the rendered Explorer is the same accepted release already on staging..."
remote_seal="$SWC_PRODUCTION_STATE_DIR/streamflow-published-connected-release.json"
aws s3 cp "${SWC_S3_DESTINATION}daily-explorer/connected/connected-release.json" "$remote_seal" --only-show-errors
cmp --silent "$remote_seal" site/_site/daily-explorer/connected/connected-release.json || { echo "STOP: local rendered and published connected releases differ. Finish the regular staging publication, then rerun."; exit 1; }
echo "5/5: Upload only the isolated Streamflow review prefix, without deletion..."
target="${SWC_S3_DESTINATION}daily-explorer/streamflow-trial/"
test "$target" = "s3://cales-climate-reports/climate/watch-staging/daily-explorer/streamflow-trial/"
aws s3 sync data/diagnostics/streamflow-staging/viewer/ "$target" --exclude index.html --cache-control 'no-cache,max-age=0,must-revalidate' --no-progress --only-show-errors
aws s3 cp data/diagnostics/streamflow-staging/viewer/index.html "${target}index.html" --cache-control 'no-cache,max-age=0,must-revalidate' --only-show-errors
aws s3 cp "${target}streamflow-staging-release.json" "$SWC_PRODUCTION_STATE_DIR/streamflow-uploaded-release.json" --only-show-errors
cmp --silent "$SWC_PRODUCTION_STATE_DIR/streamflow-uploaded-release.json" data/diagnostics/streamflow-staging/viewer/streamflow-staging-release.json
echo "PASS: Streamflow and Explorer jump navigation staged; automatic streamflow updates remain disabled."
echo "Review: https://cales.arizona.edu/climate/watch-staging/daily-explorer/streamflow-trial/"
