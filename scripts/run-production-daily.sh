#!/usr/bin/env bash
# Linux VM entry point. Run with bash; no executable-bit change is required.
set -euo pipefail
umask 077

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
config_file="${SWC_PRODUCTION_CONFIG:-/home/crimmins/.config/swclimatewatch/production.env}"
mode="${1:-run}"
if [[ $# -gt 1 || ( "$mode" != run && "$mode" != --check ) ]]; then
  echo "Usage: bash scripts/run-production-daily.sh [--check]" >&2
  exit 2
fi
if [[ ! -r "$config_file" ]]; then
  echo "Missing VM configuration: $config_file" >&2
  echo "Copy scripts/production.env.example there and edit it first." >&2
  exit 2
fi
# This is a trusted, user-owned shell configuration, outside the repository.
set -a
source "$config_file"
set +a
export TZ=America/Phoenix
export AWS_DEFAULT_REGION=us-west-2
export AWS_REGION=us-west-2
: "${SWC_S3_DESTINATION:?Set an explicit S3 destination in production.env}"
case "$SWC_S3_DESTINATION" in
  s3://cales-climate-reports/climate/watch-staging/|s3://cales-climate-reports/climate/watch/) ;;
  *) echo "VM runner requires the dedicated watch-staging/ or watch/ destination." >&2; exit 2 ;;
esac
state_dir="${SWC_PRODUCTION_STATE_DIR:-/home/crimmins/.local/state/swclimatewatch}"
rscript="${SWC_RSCRIPT:-Rscript}"
for command_name in flock git "$rscript" quarto aws; do
  command -v "$command_name" >/dev/null || {
    echo "Required command missing from configured PATH: $command_name" >&2
    exit 2
  }
done
mkdir -p "$state_dir/logs"
# Share this exact lock with controlled code releases. Do not remove the lock file.
exec 9>"$state_dir/daily.lock"
if ! flock -n 9; then
  echo "$(date --iso-8601=seconds) SKIPPED: another update or code release holds the lock."
  exit 0
fi
cd "$project_dir"
log_file="$state_dir/logs/$(date +%Y%m%dT%H%M%S)-$$.log"
echo "Log: $log_file"
exec > >(tee -a "$log_file") 2>&1
started_seconds=$SECONDS
finish() {
  result=$?
  trap - EXIT
  echo "VM runner finished: exit=$result; elapsed=$((SECONDS - started_seconds)) seconds; $(date --iso-8601=seconds)"
  exit "$result"
}
trap finish EXIT
echo "Started: $(date --iso-8601=seconds)"
echo "Project: $project_dir"
echo "Code commit: $(git rev-parse HEAD)"
echo "Destination: $SWC_S3_DESTINATION"
echo "Time zone: $TZ"
if [[ "$mode" == --check ]]; then
  "$rscript" -e 'source("scripts/check-production-readiness.R"); if (!isTRUE(swc_production_preflight_result$ready) || !isTRUE(swc_production_preflight_result$timezone_matches)) stop("VM readiness check is incomplete.", call. = FALSE)'
else
  "$rscript" scripts/daily-update-and-publish.R
fi
