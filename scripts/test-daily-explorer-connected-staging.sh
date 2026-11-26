#!/usr/bin/env bash
set -euo pipefail
umask 077
mode=${1:-publish}
if [[ $# -gt 1 || ( "$mode" != publish && "$mode" != daily ) ]]; then
  echo "Usage: bash scripts/test-daily-explorer-connected-staging.sh [publish|daily]"
  exit 2
fi
cd /home/crimmins/RProjects/SWClimateWatch-staging
set -a
source /home/crimmins/.config/swclimatewatch/staging.env
set +a
export TZ=America/Phoenix
export PATH="/usr/local/bin:/usr/lib/rstudio-server/bin/quarto/bin:/usr/bin:/bin:$PATH"
test "$SWC_S3_DESTINATION" = "s3://cales-climate-reports/climate/watch-staging/"
test "$SWC_PRODUCTION_STATE_DIR" = "/home/crimmins/.local/state/swclimatewatch-staging"
mkdir -p "$SWC_PRODUCTION_STATE_DIR/logs"
log="$SWC_PRODUCTION_STATE_DIR/logs/connected-explorer-${mode}-$(date +%Y%m%dT%H%M%S).log"
exec > >(tee -a "$log") 2>&1
echo "Log: $log"
git rev-parse HEAD
test -f data/diagnostics/daily-explorer-wy2025-release/wy2025-release.json
test -f data/diagnostics/daily-explorer-wy2026-release/wy2026-release.json
unset SWC_DAILY_ARCHIVE_STAGING SWC_NWS_HAZARDS_STAGING SWC_STORM_REPORTS_STAGING
export SWC_NWS_HAZARDS=true SWC_STORM_REPORTS=true
export SWC_DAILY_WY2025_STAGING=true SWC_DAILY_CONNECTED_STAGING=true
Rscript -e 'for(f in c("tests/testthat/test-daily-explorer-connected.R","tests/testthat/test-daily-explorer-connected-staging.R")) testthat::test_file(f,stop_on_failure=TRUE)'
if [[ "$mode" == publish ]]; then
  exec 9>"$SWC_PRODUCTION_STATE_DIR/daily.lock"
  flock -n 9 || { echo "STOP: another staging job is running."; exit 1; }
  Rscript scripts/publish-site-s3.R
else
  Rscript scripts/check-daily-explorer-connected-staging.R
  config=/home/crimmins/.config/swclimatewatch/staging.env
  trial_config=$(mktemp "$SWC_PRODUCTION_STATE_DIR/connected-daily-trial.XXXXXX")
  snapshot=$(mktemp "$SWC_PRODUCTION_STATE_DIR/connected-before-daily.XXXXXX")
  trap 'rm -f -- "$trial_config" "$snapshot"' EXIT
  printf 'source %q\n' "$config" > "$trial_config"
  printf '\nunset SWC_DAILY_ARCHIVE_STAGING SWC_NWS_HAZARDS_STAGING SWC_STORM_REPORTS_STAGING\nexport SWC_NWS_HAZARDS=true\nexport SWC_STORM_REPORTS=true\nexport SWC_DAILY_WY2025_STAGING=true\nexport SWC_DAILY_CONNECTED_STAGING=true\n' >> "$trial_config"
  sha256sum site/daily-explorer/archive/wy2025/wy2025-release.json site/daily-explorer/archive/wy2026/wy2026-release.json > "$snapshot"
  SWC_PRODUCTION_CONFIG="$trial_config" bash scripts/run-production-daily.sh --check
  SWC_PRODUCTION_CONFIG="$trial_config" bash scripts/run-production-daily.sh
  test data/diagnostics/daily-explorer-connected-staging/last-stage.csv -nt "$trial_config" || {
    echo "STOP: no fresh combined staging evidence; check for a lock skip or failed publication."
    exit 1
  }
  sha256sum -c "$snapshot"
fi
Rscript scripts/check-daily-explorer-connected-staging.R
if [[ "$mode" == daily ]]; then echo "PASS: both archive releases survived the full staging daily run."; fi
echo "Trial URL: https://cales.arizona.edu/climate/watch-staging/daily-explorer/connected/"
echo "Staging only. Standard Explorer entry, production and permanent environment files unchanged."
