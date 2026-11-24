# Explicit staging-only trial. The normal current Explorer remains separate.
daily_archive_staging_guard <- function(destination=Sys.getenv("SWC_S3_DESTINATION")) {
  if(!identical(destination,"s3://cales-climate-reports/climate/watch-staging/")||
    !identical(Sys.getenv("SWC_PRODUCTION_STATE_DIR"),"/home/crimmins/.local/state/swclimatewatch-staging"))
    stop("Daily archive trial requires the exact staging destination and state directory.")
  invisible(TRUE)
}
stage_daily_archive_trial <- function(directory="site/daily-explorer",
    source_dir="data/diagnostics/daily-explorer-archive-integrated") {
  daily_archive_staging_guard()
  source("scripts/load-daily-explorer-archive-integration.R",local=TRUE)
  validate_daily_explorer_archive_integration(source_dir)
  manifest<-jsonlite::read_json(file.path(source_dir,"integration-release.json"))
  target<-file.path(directory,"archive-pilot")
  for(file in c(vapply(manifest$files,`[[`,character(1),"path"),"integration-release.json"))
    july_pilot_copy(file.path(source_dir,file),file.path(target,file))
  validate_daily_explorer_archive_integration(target)
  report_dir<-"data/diagnostics/daily-explorer-archive-staging"
  dir.create(report_dir,recursive=TRUE,showWarnings=FALSE)
  write.csv(data.frame(status="READY",release_md5=unname(tools::md5sum(file.path(target,"integration-release.json"))),
    files=length(manifest$files),checked_utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC")),
    file.path(report_dir,"last-stage.csv"),row.names=FALSE)
  message("Staging-only archive prepared separately from the current Explorer: ",target)
  invisible(TRUE)
}
validate_daily_archive_trial <- function(output_dir="site/_site",source_dir="site/daily-explorer") {
  daily_archive_staging_guard()
  source("scripts/load-daily-explorer-archive-integration.R",local=TRUE)
  targets<-c(file.path(source_dir,"archive-pilot"),file.path(output_dir,"daily-explorer/archive-pilot"))
  for(target in targets)validate_daily_explorer_archive_integration(target)
  hashes<-unname(tools::md5sum(file.path(targets,"integration-release.json")))
  if(length(hashes)!=2L||anyNA(hashes)||length(unique(hashes))!=1L)stop("Source/rendered archive releases differ; upload stopped.")
  message("PASS: staged and rendered archive releases match; current Explorer paths are separate.")
  invisible(TRUE)
}
