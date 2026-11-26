#!/usr/bin/env bash
# Copy only accepted publication releases; persist the daily adapter explicitly.
set -euo pipefail
umask 077
cd /home/crimmins/RProjects/SWClimateWatch
staging=/home/crimmins/RProjects/SWClimateWatch-staging
exec 8>/home/crimmins/.local/state/swclimatewatch-staging/daily.lock
flock -n 8 || { echo "STOP: a staging job is running."; exit 1; }
exec 9>/home/crimmins/.local/state/swclimatewatch/daily.lock
flock -n 9 || { echo "STOP: a production job is running."; exit 1; }
expected_commit=$(git -C "$staging" rev-parse HEAD)
test -f "$staging/R/daily-explorer-connected-publication.R"
echo "Promoting staging commit: $expected_commit"
export SWC_CONNECTED_RELEASE_COMMIT="$expected_commit"
# Confirm the standard-entry staging publication contains this code's adapter.
Rscript -e 'root<-"/home/crimmins/RProjects/SWClimateWatch-staging"; r<-jsonlite::read_json(file.path(root,"site/_site/daily-explorer/connected/connected-release.json")); stopifnot(isTRUE(r$operational),identical(r$code_commit,Sys.getenv("SWC_CONNECTED_RELEASE_COMMIT"))); for(year in c(2025,2026)){path<-paste0("archive/wy",year,"/wy",year,"-release.json"); dep<-Filter(function(d)d$path==path,r$dependencies); imported<-file.path(root,paste0("data/diagnostics/daily-explorer-wy",year,"-release/wy",year,"-release.json")); stopifnot(length(dep)==1L,identical(dep[[1]]$md5,unname(tools::md5sum(imported))))}; p<-paste(readLines(file.path(root,"site/_site/pages/daily-explorer.html")),collapse="\n"); stopifnot(grepl("../daily-explorer/connected/index.html?embedded=1",p,fixed=TRUE))'
git rev-parse HEAD > /home/crimmins/.local/state/swclimatewatch/previous-production-commit.txt
git stash push -m "Production generated pages before combined Explorer" -- site/index.qmd site/_quarto.yml site/pages/_synopsis-content.qmd site/pages/current-snow.qmd site/pages/snow-conditions.qmd site/pages/monthly-climate.qmd site/pages/daily-explorer.qmd site/pages/archive
git status --short
test -z "$(git status --porcelain --untracked-files=no)" || { echo "STOP: tracked changes remain."; exit 1; }
git fetch origin codex/historic-monthly-pilot
git switch --detach "$expected_commit"
test "$(git rev-parse HEAD)" = "$expected_commit"
for year in 2025 2026; do
  src="$staging/data/diagnostics/daily-explorer-wy${year}-release"
  dst="data/diagnostics/daily-explorer-wy${year}-release"
  test -f "$src/wy${year}-release.json"
  mkdir -p "$dst"
  cp -a -- "$src/." "$dst/"
done
config=/home/crimmins/.config/swclimatewatch/production.env
backup="${config}.before-connected-$(date +%Y%m%dT%H%M%S)"
test ! -e "$backup"
cp -p -- "$config" "$backup"
if grep -q '^SWC_DAILY_CONNECTED=' "$config"; then
  sed -i 's/^SWC_DAILY_CONNECTED=.*/SWC_DAILY_CONNECTED=true/' "$config"
else
  printf '\nSWC_DAILY_CONNECTED=true\n' >> "$config"
fi
echo "Configuration backup: $backup"
set -a
source "$config"
set +a
export TZ=America/Phoenix
export PATH="/usr/local/bin:/usr/lib/rstudio-server/bin/quarto/bin:/usr/bin:/bin:$PATH"
test "$SWC_S3_DESTINATION" = "s3://cales-climate-reports/climate/watch/"
test "$SWC_PRODUCTION_STATE_DIR" = "/home/crimmins/.local/state/swclimatewatch"
unset SWC_DAILY_CONNECTED_STAGING SWC_DAILY_WY2025_STAGING SWC_DAILY_ARCHIVE_STAGING SWC_NWS_HAZARDS_STAGING SWC_STORM_REPORTS_STAGING
export SWC_DAILY_CONNECTED=true
mkdir -p "$SWC_PRODUCTION_STATE_DIR/logs"
log="$SWC_PRODUCTION_STATE_DIR/logs/connected-promotion-$(date +%Y%m%dT%H%M%S).log"
exec > >(tee -a "$log") 2>&1
echo "Log: $log"
Rscript scripts/publish-site-s3.R
echo "PASS: combined Explorer and both archive years published to production; daily adapter enabled."
