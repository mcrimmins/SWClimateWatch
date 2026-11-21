#!/usr/bin/env bash
# Enable only the staging flag, then exercise the normal VM daily runner.
set -euo pipefail
cd /home/crimmins/RProjects/SWClimateWatch-staging
readonly history_staging_config=/home/crimmins/.config/swclimatewatch/staging.env
(
  set -a
  source "$history_staging_config"
  set +a
  test "$SWC_S3_DESTINATION" = "s3://cales-climate-reports/climate/watch-staging/"
  test "$SWC_PRODUCTION_STATE_DIR" = "/home/crimmins/.local/state/swclimatewatch-staging"
  exec 9>"$SWC_PRODUCTION_STATE_DIR/daily.lock"
  flock -n 9 || { echo "STOP: another staging job is running."; exit 1; }
  cp -p "$history_staging_config" "$history_staging_config.before-station-history-daily-$(date +%Y%m%dT%H%M%S)"
  sed -i -E '/^[[:space:]]*(export[[:space:]]+)?SWC_STATION_HISTORY=/d' "$history_staging_config"
  printf '\nSWC_STATION_HISTORY=true\n' >> "$history_staging_config"
)
export TZ=America/Phoenix
set -a
source "$history_staging_config"
set +a
test "$SWC_S3_DESTINATION" = "s3://cales-climate-reports/climate/watch-staging/"
test "$SWC_PRODUCTION_STATE_DIR" = "/home/crimmins/.local/state/swclimatewatch-staging"
test "$SWC_STATION_HISTORY" = true
export SWC_PRODUCTION_CONFIG="$history_staging_config"
echo "Staging history enabled. Running the normal preflight and full daily workflow."
bash scripts/run-production-daily.sh --check
trial_log=$(mktemp "$SWC_PRODUCTION_STATE_DIR/logs/station-history-daily-trial-XXXXXX")
echo "Trial summary log: $trial_log"
bash scripts/run-production-daily.sh | tee "$trial_log"
grep -q '^VM runner finished: exit=0;' "$trial_log" || { echo "STOP: daily run was skipped or did not finish successfully."; exit 1; }
grep -q '^Stations: updated' "$trial_log" || { echo "STOP: the station update did not succeed in this run."; exit 1; }
grep -q '^Station history: READY;' "$trial_log" || { echo "STOP: this daily run did not report a ready station history."; exit 1; }
Rscript scripts/check-station-history-publication.R
Rscript scripts/check-station-history-daily.R
echo "PASS: staging daily history workflow completed. Production configuration is unchanged."
