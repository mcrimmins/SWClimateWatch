#!/usr/bin/env bash
# VM staging only: verify/install the portable reference cache, render and publish.
set -euo pipefail
project_dir=$(cd "$(dirname "$0")/.." && pwd)
cd "$project_dir"
set -a
source /home/crimmins/.config/swclimatewatch/staging.env
set +a
export TZ=America/Phoenix
export PATH="/usr/local/bin:/usr/lib/rstudio-server/bin/quarto/bin:/usr/bin:/bin:$PATH"
test "$SWC_S3_DESTINATION" = 's3://cales-climate-reports/climate/watch-staging/'
test "$SWC_PRODUCTION_STATE_DIR" = '/home/crimmins/.local/state/swclimatewatch-staging'
test "$project_dir" = '/home/crimmins/RProjects/SWClimateWatch-staging'
mkdir -p "$SWC_PRODUCTION_STATE_DIR"
exec 9>"$SWC_PRODUCTION_STATE_DIR/daily.lock"
flock -n 9 || { echo 'STOP: another staging job is running.'; exit 1; }
archive="$HOME/incoming/swc-regional-climate-seed.tar.gz"
(
  cd "$(dirname "$archive")"
  sha256sum -c "$(basename "$archive").sha256"
)
# Only the prepared publication cache may be installed by this archive.
while IFS= read -r member; do
  case "$member" in
    data/processed/regional-climate-reference/1991-2020/*) ;;
    *) echo "STOP: unexpected archive path: $member"; exit 1 ;;
  esac
  case "/$member/" in
    *'/../'*|*'/./'*) echo 'STOP: unsafe archive member'; exit 1 ;;
  esac
done < <(tar -tzf "$archive")
tar -xzf "$archive" -C "$project_dir"
echo "Staging commit: $(git rev-parse HEAD)"
Rscript scripts/stage-cached-climate-of-region.R
Rscript scripts/publish-site-s3.R
Rscript scripts/check-climate-of-region-publication.R
echo 'Climate of the Region staging test complete; production was not changed.'
