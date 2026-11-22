source("R/storm-reports-staging.R")
local({
  env<-c("SWC_S3_DESTINATION","SWC_PRODUCTION_STATE_DIR")
  old<-Sys.getenv(env,unset=NA_character_)
  on.exit(for(i in seq_along(env))if(is.na(old[i]))Sys.unsetenv(env[i])else do.call(Sys.setenv,setNames(list(old[i]),env[i])),add=TRUE)
  Sys.setenv(SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch/",
    SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch")
  stopifnot(inherits(try(storm_reports_staging_guard(),silent=TRUE),"try-error"))
  Sys.setenv(SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch-staging/",
    SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch-staging")
  root<-tempfile("storm-release-check-",tmpdir="data/diagnostics")
  dir.create(root,recursive=TRUE)
  fixture<-file.path(root,"daily-explorer");dir.create(fixture)
  original<-jsonlite::read_json("site/daily-explorer/daily-data.json")
  original$publication_mode<-TRUE
  original$circulation_enabled<-TRUE;original$circulation_period_means_enabled<-TRUE
  jsonlite::write_json(original,file.path(fixture,"daily-data.json"),auto_unbox=TRUE,digits=NA,null="null")
  writeLines("preserve verified weather manifest",file.path(fixture,"circulation-manifest.json"))
  dir.create(file.path(fixture,"circulation"));writeBin(as.raw(1:10),file.path(fixture,"circulation","sentinel.png"))
  kept<-file.path(fixture,c("circulation-manifest.json","circulation/sentinel.png"))
  before<-unname(tools::md5sum(kept))
  stage_storm_reports_staging(fixture,file.path(root,"candidate"))
  after<-jsonlite::read_json(file.path(fixture,"daily-data.json"))
  original$storm_reports_enabled<-TRUE
  stopifnot(identical(after,original),identical(before,unname(tools::md5sum(kept))))
  manifest<-jsonlite::read_json(file.path(fixture,"storm-reports-manifest.json"))
  first<-file.path(fixture,manifest$days[[1]]$path)
  writeLines("corrupted",first)
  stopifnot(inherits(try(validate_storm_reports_publication(fixture),silent=TRUE),"try-error"))
  message("PASS: production guard, isolated staging overlay, unchanged weather payloads/assets, versioned assets and corruption rejection.")
})
