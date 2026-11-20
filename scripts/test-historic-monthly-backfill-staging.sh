#!/usr/bin/env bash
set -euo pipefail
cd /home/crimmins/RProjects/SWClimateWatch-staging
set -a
source /home/crimmins/.config/swclimatewatch/staging.env
set +a
export TZ=America/Phoenix
export PATH="/usr/local/bin:/usr/lib/rstudio-server/bin/quarto/bin:/usr/bin:/bin:$PATH"
test "${SWC_S3_DESTINATION:-}" = "s3://cales-climate-reports/climate/watch-staging/"
test "${SWC_PRODUCTION_STATE_DIR:-}" = "/home/crimmins/.local/state/swclimatewatch-staging"
exec 9>"$SWC_PRODUCTION_STATE_DIR/daily.lock"
flock -n 9 || { echo "STOP: another staging job is running."; exit 1; }
bundle=${1:-/home/crimmins/incoming/swc-historic-monthly-backfill-release.tar.gz}
test -f "$bundle"
echo "Verifying the existing WY1982-2025 publication bundle..."
Rscript -e 'source("scripts/load-historic-monthly-publication.R"); invisible(historic_monthly_release_records())'
echo "Unpacking the reviewed WY1896-1981 publication bundle..."
tar -xzf "$bundle" -C data/processed
Rscript scripts/stage-cached-historic-monthly-archive.R
Rscript scripts/check-historic-monthly-publication.R --source-only
Rscript scripts/check-historic-monthly-backfill-publication.R --source-only
echo "Rendering, validating and publishing staging only..."
Rscript scripts/publish-site-s3.R
Rscript scripts/check-historic-monthly-publication.R
Rscript scripts/check-historic-monthly-backfill-publication.R
echo "Historic Years backfill staging complete: 130 years, 2730 monthly maps. Production was not changed."
