#!/usr/bin/env bash
# Site-only staging test of the laptop's reviewed, portable archive release.
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
bundle=${1:-/home/crimmins/incoming/swc-historic-monthly-release.tar.gz}
test -f "$bundle"
mkdir -p data/processed
echo "Unpacking reviewed Historic Years maps..."
tar -xzf "$bundle" -C data/processed
echo "Staging and validating the 924-map archive..."
Rscript scripts/stage-cached-historic-monthly-archive.R
Rscript scripts/check-historic-monthly-publication.R --source-only
echo "Rendering, validating and publishing staging only..."
Rscript scripts/publish-site-s3.R
Rscript scripts/check-historic-monthly-publication.R
echo "Historic Years staging test complete. Production was not changed."
