#!/usr/bin/env bash
# WY2025 staging publication/retention; never edit permanent environment files.
set -euo pipefail
umask 077
mode=${1:-publish}
if [[ $# -gt 1 || ( "$mode" != publish && "$mode" != daily ) ]]; then
  echo "Usage: bash scripts/test-daily-explorer-wy2025-staging.sh [publish|daily]"
  exit 2
fi
cd /home/crimmins/RProjects/SWClimateWatch-staging
config=/home/crimmins/.config/swclimatewatch/staging.env
set -a
source "$config"
set +a
export TZ=America/Phoenix
export PATH="/usr/local/bin:/usr/lib/rstudio-server/bin/quarto/bin:/usr/bin:/bin:$PATH"
test "$SWC_S3_DESTINATION" = "s3://cales-climate-reports/climate/watch-staging/"
test "$SWC_PRODUCTION_STATE_DIR" = "/home/crimmins/.local/state/swclimatewatch-staging"
mkdir -p "$SWC_PRODUCTION_STATE_DIR/logs"
log="$SWC_PRODUCTION_STATE_DIR/logs/wy2025-${mode}-$(date +%Y%m%dT%H%M%S).log"
exec > >(tee -a "$log") 2>&1
echo "Log: $log"
git rev-parse HEAD
unset SWC_DAILY_ARCHIVE_STAGING SWC_NWS_HAZARDS_STAGING SWC_STORM_REPORTS_STAGING
export SWC_NWS_HAZARDS=true SWC_STORM_REPORTS=true SWC_DAILY_WY2025_STAGING=true
if [[ "$mode" == publish ]]; then
  exec 9>"$SWC_PRODUCTION_STATE_DIR/daily.lock"
  flock -n 9 || { echo "STOP: another staging job is running."; exit 1; }
  Rscript scripts/publish-site-s3.R
  Rscript scripts/check-daily-explorer-wy2025-staging.R
else
  Rscript scripts/check-daily-explorer-wy2025-staging.R
  trial_config=$(mktemp "$SWC_PRODUCTION_STATE_DIR/wy2025-daily-trial.XXXXXX")
  snapshot=$(mktemp "$SWC_PRODUCTION_STATE_DIR/wy2025-before-daily.XXXXXX")
  trap 'rm -f -- "$trial_config" "$snapshot"' EXIT
  printf 'source %q\n' "$config" > "$trial_config"
  printf '\nunset SWC_DAILY_ARCHIVE_STAGING SWC_NWS_HAZARDS_STAGING SWC_STORM_REPORTS_STAGING\nexport SWC_NWS_HAZARDS=true\nexport SWC_STORM_REPORTS=true\nexport SWC_DAILY_WY2025_STAGING=true\n' >> "$trial_config"
  sha256sum site/daily-explorer/archive/wy2025/wy2025-release.json > "$snapshot"
  SWC_PRODUCTION_CONFIG="$trial_config" bash scripts/run-production-daily.sh --check
  SWC_PRODUCTION_CONFIG="$trial_config" bash scripts/run-production-daily.sh
  test data/diagnostics/daily-explorer-wy2025-staging/last-stage.csv -nt "$trial_config" || {
    echo "STOP: no fresh WY2025 staging evidence; inspect the daily log for a lock skip or skipped publication."
    exit 1
  }
  sha256sum -c "$snapshot"
  Rscript scripts/check-daily-explorer-wy2025-staging.R
  echo "PASS: all referenced WY2025 files survived the full staging daily run."
fi
echo "Archive trial URL: https://cales.arizona.edu/climate/watch-staging/daily-explorer/archive/wy2025/"
echo "Staging-only trial complete. Production and permanent environment files were not changed."
