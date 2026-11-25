# Explicit staging trial; production and the current Explorer are unchanged.
wy2025_staging_guard <- function(destination=Sys.getenv("SWC_S3_DESTINATION")) {
  if(!identical(destination,"s3://cales-climate-reports/climate/watch-staging/")||
    !identical(Sys.getenv("SWC_PRODUCTION_STATE_DIR"),"/home/crimmins/.local/state/swclimatewatch-staging"))
    stop("WY2025 trial requires the exact staging destination and state directory.")
  invisible(TRUE)
}
stage_wy2025_trial <- function(directory="site/daily-explorer",source_dir="data/diagnostics/daily-explorer-wy2025-release") {
  wy2025_staging_guard()
  source("scripts/load-daily-explorer-wy2025.R",local=TRUE)
  validate_wy2025_explorer_navigation(source_dir)
  release<-jsonlite::read_json(file.path(source_dir,"wy2025-release.json"))
  target<-file.path(directory,"archive/wy2025")
  for(file in c(vapply(release$files,`[[`,character(1),"path"),"wy2025-release.json"))
    july_pilot_copy(file.path(source_dir,file),file.path(target,file))
  validate_wy2025_explorer_navigation(target)
  report_dir<-"data/diagnostics/daily-explorer-wy2025-staging"
  dir.create(report_dir,recursive=TRUE,showWarnings=FALSE)
  write.csv(data.frame(status="READY",release_md5=unname(tools::md5sum(file.path(target,"wy2025-release.json"))),
    files=length(release$files),checked_utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC")),
    file.path(report_dir,"last-stage.csv"),row.names=FALSE)
  message("WY2025 staging trial prepared: ",target)
  invisible(TRUE)
}
validate_wy2025_trial <- function(output_dir="site/_site",source_dir="site/daily-explorer") {
  wy2025_staging_guard()
  source("scripts/load-daily-explorer-wy2025.R",local=TRUE)
  targets<-c(file.path(source_dir,"archive/wy2025"),file.path(output_dir,"daily-explorer/archive/wy2025"))
  for(target in targets)validate_wy2025_explorer_navigation(target)
  hashes<-unname(tools::md5sum(file.path(targets,"wy2025-release.json")))
  if(anyNA(hashes)||length(unique(hashes))!=1L)stop("Source/rendered WY2025 releases differ; upload stopped.")
  imported<-file.path("data/diagnostics/daily-explorer-wy2025-release","wy2025-release.json")
  if(!file.exists(imported)||!identical(hashes[1],unname(tools::md5sum(imported))))stop("WY2025 differs from imported release; upload stopped.")
  message("PASS: imported, staged and rendered WY2025 releases match; current Explorer remains separate.")
  invisible(TRUE)
}
