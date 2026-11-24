#!/usr/bin/env bash
# Staging only: publish the fixed archive, then optionally test daily retention.
set -euo pipefail
umask 077
mode=${1:-publish}
if [[ $# -gt 1 || ( "$mode" != publish && "$mode" != daily ) ]]; then
  echo "Usage: bash scripts/test-daily-explorer-archive-staging.sh [publish|daily]"
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
log="$SWC_PRODUCTION_STATE_DIR/logs/archive-pilot-${mode}-$(date +%Y%m%dT%H%M%S).log"
exec > >(tee -a "$log") 2>&1
echo "Log: $log"
git rev-parse HEAD
unset SWC_NWS_HAZARDS_STAGING SWC_STORM_REPORTS_STAGING
export SWC_NWS_HAZARDS=true SWC_STORM_REPORTS=true SWC_DAILY_ARCHIVE_STAGING=true
if [[ "$mode" == publish ]]; then
  exec 9>"$SWC_PRODUCTION_STATE_DIR/daily.lock"
  flock -n 9 || { echo "STOP: another staging job is running."; exit 1; }
  Rscript scripts/publish-site-s3.R
  Rscript scripts/check-daily-explorer-archive-staging.R
else
  # Do not hold the lock here: the normal daily runner owns the same lock.
  Rscript scripts/check-daily-explorer-archive-staging.R
  trial_config=$(mktemp "$SWC_PRODUCTION_STATE_DIR/archive-daily-trial.XXXXXX")
  snapshot=$(mktemp "$SWC_PRODUCTION_STATE_DIR/archive-before-daily.XXXXXX")
  trap 'rm -f -- "$trial_config" "$snapshot"' EXIT
  printf 'source %q\n' "$config" > "$trial_config"
  printf '\nunset SWC_NWS_HAZARDS_STAGING SWC_STORM_REPORTS_STAGING\nexport SWC_NWS_HAZARDS=true\nexport SWC_STORM_REPORTS=true\nexport SWC_DAILY_ARCHIVE_STAGING=true\n' >> "$trial_config"
  sha256sum site/daily-explorer/archive-pilot/integration-release.json > "$snapshot"
  SWC_PRODUCTION_CONFIG="$trial_config" bash scripts/run-production-daily.sh --check
  SWC_PRODUCTION_CONFIG="$trial_config" bash scripts/run-production-daily.sh
  if ! test data/diagnostics/daily-explorer-archive-staging/last-stage.csv -nt "$trial_config"; then
    echo "STOP: no fresh archive staging evidence. Inspect the daily log for a lock skip or skipped publication."
    exit 1
  fi
  sha256sum -c "$snapshot"
  Rscript scripts/check-daily-explorer-archive-staging.R
  echo "PASS: the archive release and all referenced files survived the full staging daily run."
fi
echo "Archive trial URL: https://cales.arizona.edu/climate/watch-staging/daily-explorer/archive-pilot/"
echo "Staging-only trial complete. Production and permanent environment files were not changed."
