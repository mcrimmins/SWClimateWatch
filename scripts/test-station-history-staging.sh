#!/usr/bin/env bash
# Explicit staging trial only; no production checkout or daily-runner changes.
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
log="$SWC_PRODUCTION_STATE_DIR/logs/station-history-staging-$(date +%Y%m%dT%H%M%S).log"
exec > >(tee -a "$log") 2>&1
echo "Log: $log"
git rev-parse HEAD
Rscript -e 'p <- c("filelock","jsonlite","digest","xml2"); missing <- p[!vapply(p,requireNamespace,logical(1),quietly=TRUE)]; if(length(missing))stop("Install required R packages first: ",paste(missing,collapse=", "))'

incoming=/home/crimmins/incoming
archive="$incoming/swc-station-history-seed.tar.gz"
(cd "$incoming" && sha256sum -c swc-station-history-seed.tar.gz.sha256)
tar -tzf "$archive" | awk '$0 !~ /^(catalog[.]json|update-summary[.]csv|history(\/.*)?)$/ {bad=1} $0 ~ /(^|\/)\.\.(\/|$)/ {bad=1} END {exit bad}'
mkdir -p data/diagnostics
import_dir=$(mktemp -d data/diagnostics/station-history-seed.XXXXXX)
tar -xzf "$archive" -C "$import_dir" --no-same-owner --no-same-permissions
test -f "$import_dir/catalog.json"
test -f "$import_dir/update-summary.csv"
test -d "$import_dir/history"
seed=data/diagnostics/station-custom-dates-pilot
if test -e "$seed"; then
  backup="${seed}.before-staging-$(date +%Y%m%dT%H%M%S)"
  mv -- "$seed" "$backup"
  echo "Previous history pilot preserved at $backup"
fi
mv -- "$import_dir" "$seed"
Rscript scripts/check-station-history-cache-coverage.R

echo "1/5: Rebuild screened Current conditions from VM caches; no ACIS downloads. This may take several minutes."
Rscript scripts/build-acis-station-explorer-prototype.R
echo "2/5: Reconcile the historical seed with the VM's cached observations; progress follows by station."
Rscript scripts/build-station-custom-dates-pilot.R
echo "3/5: Build and validate the combined station snapshot."
Rscript -e 'source("scripts/load-station-custom-dates-pilot.R"); source("R/station-history-integration.R"); print(build_station_history_integration(mode="full"),row.names=FALSE)'
echo "4/5: Stage the combined page and publish only to the guarded staging destination."
Rscript scripts/stage-station-history-integration.R
Rscript scripts/publish-site-s3.R
echo "5/5: Verify staged and rendered historical data and versioned browser assets."
Rscript scripts/check-station-history-publication.R
echo "Station history staging trial complete. Automatic daily history refresh remains disabled."
