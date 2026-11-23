#!/usr/bin/env bash
# Full staging daily run, with a process-only hazard opt-in. No production edit.
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
trial_config=$(mktemp "$SWC_PRODUCTION_STATE_DIR/nws-hazards-daily-trial.XXXXXX")
trap 'rm -f -- "$trial_config"' EXIT
printf 'source %q\n' "$config" > "$trial_config"
printf '\nunset SWC_NWS_HAZARDS_STAGING SWC_STORM_REPORTS_STAGING\nexport SWC_NWS_HAZARDS=true\nexport SWC_STORM_REPORTS=true\n' >> "$trial_config"
echo "Run the full daily workflow with hazard refresh against staging only."
SWC_PRODUCTION_CONFIG="$trial_config" bash scripts/run-production-daily.sh --check
SWC_PRODUCTION_CONFIG="$trial_config" bash scripts/run-production-daily.sh
if ! test data/diagnostics/nws-hazards-daily/workflow-status.csv -nt "$trial_config"; then
  echo "STOP: no new hazard workflow report; the runner may have skipped because another job held the lock."
  exit 1
fi
unset SWC_NWS_HAZARDS_STAGING SWC_STORM_REPORTS_STAGING
export SWC_NWS_HAZARDS=true
export SWC_STORM_REPORTS=true
Rscript scripts/check-nws-hazards-daily.R
echo "Full staging daily hazard test complete. Review READY/PARTIAL/UNAVAILABLE and the site before promotion."
echo "The hazard opt-in was limited to this test; permanent environment files and production were not changed."
