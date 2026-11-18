#!/usr/bin/env bash
# VM staging only: rebuild comparison caches/maps before rendering or uploading.
set -euo pipefail
project_dir=$(cd "$(dirname "$0")/.." && pwd)
cd "$project_dir"
set -a
source /home/crimmins/.config/swclimatewatch/staging.env
set +a
export TZ=America/Phoenix
export PATH="/usr/local/bin:/usr/lib/rstudio-server/bin/quarto/bin:/usr/bin:/bin:$PATH"
test "$project_dir" = '/home/crimmins/RProjects/SWClimateWatch-staging'
test "$SWC_S3_DESTINATION" = 's3://cales-climate-reports/climate/watch-staging/'
test "$SWC_PRODUCTION_STATE_DIR" = '/home/crimmins/.local/state/swclimatewatch-staging'
mkdir -p "$SWC_PRODUCTION_STATE_DIR/logs"
exec 9>"$SWC_PRODUCTION_STATE_DIR/daily.lock"
flock -n 9 || { echo 'STOP: another staging job is running.'; exit 1; }
log_file="$SWC_PRODUCTION_STATE_DIR/logs/prism-comparison-$(date +%Y%m%dT%H%M%S)-$$.log"
echo "Log: $log_file"
exec > >(tee -a "$log_file") 2>&1
started=$SECONDS
finish() {
  result=$?
  trap - EXIT
  echo "Comparison staging finished: exit=$result; elapsed=$((SECONDS-started)) seconds."
  exit "$result"
}
trap finish EXIT
echo "Staging commit: $(git rev-parse HEAD)"
echo 'Rebuilding enabled PRISM maps and retained freeze comparisons from cached inputs...'
Rscript scripts/rebuild-prism-code-review-fixes.R
Rscript scripts/check-prism-comparison-caches.R
echo 'Rendering, validating and publishing watch-staging...'
Rscript scripts/publish-site-s3.R
echo 'PRISM comparison staging completed; production was not changed.'
