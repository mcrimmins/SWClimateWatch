#!/usr/bin/env bash
# Verify and import only the publication bundle. Preserve a prior import.
set -euo pipefail
umask 077
cd /home/crimmins/RProjects/SWClimateWatch-staging
set -a
source /home/crimmins/.config/swclimatewatch/staging.env
set +a
export TZ=America/Phoenix
test "$SWC_S3_DESTINATION" = "s3://cales-climate-reports/climate/watch-staging/"
test "$SWC_PRODUCTION_STATE_DIR" = "/home/crimmins/.local/state/swclimatewatch-staging"
exec 9>"$SWC_PRODUCTION_STATE_DIR/daily.lock"
flock -n 9 || { echo "STOP: another staging job is running."; exit 1; }
bundle=/home/crimmins/incoming/swc-daily-explorer-wy2026.tar.gz
(cd /home/crimmins/incoming && sha256sum -c swc-daily-explorer-wy2026.tar.gz.sha256)
mkdir -p data/diagnostics
candidate=$(mktemp -d data/diagnostics/wy2026-import.XXXXXX)
export SWC_WY2026_IMPORT_CANDIDATE="$candidate"
export SWC_WY2026_IMPORT_ENTRIES="${candidate}.entries.rds"
echo "Importing to $candidate; source caches and maps will not be rebuilt."
Rscript -e 'p <- "/home/crimmins/incoming/swc-daily-explorer-wy2026.tar.gz"; entries <- utils::untar(p,list=TRUE,tar="internal"); stopifnot(length(entries)>0L,!anyDuplicated(entries),all(grepl("^[A-Za-z0-9_./-]+$",entries)),!any(startsWith(entries,"/")),!any(vapply(strsplit(entries,"/",fixed=TRUE),function(x)any(x %in% c("..",".","")),logical(1)))); saveRDS(entries,Sys.getenv("SWC_WY2026_IMPORT_ENTRIES"))'
tar -xzf "$bundle" -C "$candidate"
Rscript -e 'source("scripts/load-daily-explorer-wy2026.R"); d<-Sys.getenv("SWC_WY2026_IMPORT_CANDIDATE"); validate_wy2026_explorer_navigation(d); r<-jsonlite::read_json(file.path(d,"wy2026-release.json")); expected<-c("wy2026-release.json",vapply(r$files,`[[`,character(1),"path")); stopifnot(setequal(readRDS(Sys.getenv("SWC_WY2026_IMPORT_ENTRIES")),expected),setequal(list.files(d,recursive=TRUE),expected)); cat("PASS: exact imported publication files and release hashes.\n")'
target=data/diagnostics/daily-explorer-wy2026-release
if [[ -e "$target" ]]; then
  backup="${target}.previous-$(date +%Y%m%dT%H%M%S)"
  test ! -e "$backup"
  mv -- "$target" "$backup"
  echo "Preserved prior import: $backup"
fi
mv -- "$candidate" "$target"
echo "WY2026 publication import ready: $target"
