#!/usr/bin/env bash
set -euo pipefail
umask 077
cd /home/crimmins/RProjects/SWClimateWatch-staging
config=/home/crimmins/.config/swclimatewatch/staging.env
set -a
source "$config"
set +a
export TZ=America/Phoenix
export PATH="/usr/local/bin:/usr/lib/rstudio-server/bin/quarto/bin:/usr/bin:/bin:$PATH"
test "$SWC_S3_DESTINATION" = "s3://cales-climate-reports/climate/watch-staging/"
test "$SWC_PRODUCTION_STATE_DIR" = "/home/crimmins/.local/state/swclimatewatch-staging"
mkdir -p "$SWC_PRODUCTION_STATE_DIR"
trial_config=$(mktemp "$SWC_PRODUCTION_STATE_DIR/streamflow-daily-trial.XXXXXX")
before=$(mktemp "$SWC_PRODUCTION_STATE_DIR/streamflow-archives.XXXXXX")
trap 'rm -f -- "$trial_config" "$before"' EXIT
sha256sum site/daily-explorer/archive/wy2025/wy2025-release.json site/daily-explorer/archive/wy2026/wy2026-release.json > "$before"
printf 'source %q\n' "$config" > "$trial_config"
printf '\nunset SWC_DAILY_CONNECTED_STAGING SWC_DAILY_WY2025_STAGING SWC_DAILY_ARCHIVE_STAGING\nexport SWC_DAILY_CONNECTED=true\nexport SWC_STREAMFLOW=true\n' >> "$trial_config"
Rscript scripts/test-streamflow-daily.R
SWC_PRODUCTION_CONFIG="$trial_config" bash scripts/run-production-daily.sh --check
SWC_PRODUCTION_CONFIG="$trial_config" bash scripts/run-production-daily.sh
if ! test data/diagnostics/streamflow-daily/workflow-status.csv -nt "$trial_config"; then
  echo "STOP: no new Streamflow status; the daily runner may have skipped because another job holds the lock."
  exit 1
fi
sha256sum -c "$before"
Rscript scripts/check-streamflow-daily.R
echo "PASS: standard staging Explorer and daily Streamflow refresh; both archives retained."
echo "Review the standard staging Daily Explorer. Production and permanent configuration files were not changed."
