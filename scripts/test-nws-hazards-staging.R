# Isolated, cache-only release rehearsal; never writes site/ or uploads.
source("R/nws-hazards-staging.R")
source("R/site-cache.R")
source("R/storm-reports-staging.R")
withr::with_envvar(c(SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch/",
  SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch"),
  stopifnot(inherits(try(nws_hazards_staging_guard(),silent=TRUE),"try-error")))
stopifnot(!nws_hazards_safe_path("../escape"),!nws_hazards_safe_path("/escape"))
base<-"data/diagnostics/daily-explorer-nws-hazards"
fixture<-"data/diagnostics/nws-hazards-staging-test/source"
dir.create(fixture,recursive=TRUE,showWarnings=FALSE)
files<-list.files(base,recursive=TRUE)
files<-files[!grepl("^(maps|hazards)/",files)]
for(file in files) {
  to<-file.path(fixture,file);dir.create(dirname(to),recursive=TRUE,showWarnings=FALSE)
  stopifnot(file.copy(file.path(base,file),to,overwrite=TRUE))
}
original<-jsonlite::read_json(file.path(fixture,"daily-data.json"))
original$publication_mode<-TRUE;original$storm_reports_enabled<-TRUE
original$nws_hazards_preview<-NULL;original$storm_reports_preview<-NULL
original$circulation_enabled<-TRUE;original$circulation_period_means_enabled<-TRUE
original$preservation_test<-list(missing=NULL,weather="keep original weather metadata")
jsonlite::write_json(original,file.path(fixture,"daily-data.json"),auto_unbox=TRUE,digits=NA,null="null")
writeLines("unchanged weather map",file.path(fixture,"weather-preservation-test.txt"))
withr::with_envvar(c(SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch-staging/",
  SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch-staging"),
  stage_nws_hazards_staging(fixture,"data/diagnostics/nws-hazards-staging-test/candidate"))
after<-jsonlite::read_json(file.path(fixture,"daily-data.json"));after$nws_hazards_enabled<-NULL
stopifnot(identical(original,after),identical(readLines(file.path(fixture,"weather-preservation-test.txt")),"unchanged weather map"))
release<-jsonlite::read_json(file.path(fixture,"hazard-publication.json"))
victim<-file.path(fixture,release$files[[1]]$path)
saved<-readBin(victim,"raw",n=file.info(victim)$size)
writeBin(charToRaw("tampered"),victim)
stopifnot(inherits(try(validate_nws_hazards_publication(fixture),silent=TRUE),"try-error"))
writeBin(saved,victim)
validate_nws_hazards_publication(fixture)
swc_cache_version_app(fixture)
validate_nws_hazards_publication(fixture)
rendered<-"data/diagnostics/nws-hazards-staging-test/rendered/daily-explorer"
for(file in list.files(fixture,recursive=TRUE)) {
  to<-file.path(rendered,file);dir.create(dirname(to),recursive=TRUE,showWarnings=FALSE)
  stopifnot(file.copy(file.path(fixture,file),to,overwrite=TRUE))
}
validate_nws_hazards_publication(rendered)
message("PASS: production guard, full-date staging overlay, weather/null preservation, payload/geometry/timeline/assets and tamper rejection. No upload.")
