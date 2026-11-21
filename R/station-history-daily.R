# Optional daily history overlay. The normal station publisher still performs
# the atomic directory swap, preserving the entire last good page on failure.
swc_station_history_enabled <- function() {
  value <- tolower(trimws(Sys.getenv("SWC_STATION_HISTORY","false")))
  if (!value %in% c("true","false","1","0","yes","no")) stop("Invalid SWC_STATION_HISTORY value.")
  value %in% c("true","1","yes")
}

swc_station_history_update <- function(
    source_dir = "data/diagnostics/acis-stations/station-explorer-prototype",
    history_dir = "data/diagnostics/station-custom-dates-pilot",
    stations = acis_reference_station_table(),
    cache_dir = "data/processed/acis-stations/reference-network/daily") {
  started <- proc.time()[["elapsed"]]
  source_dir <- normalizePath(source_dir,winslash="/",mustWork=TRUE)
  allowed <- paste0(tolower(normalizePath("data/diagnostics",winslash="/",mustWork=TRUE)),"/")
  if (!startsWith(tolower(source_dir),allowed)) stop("Build the history overlay in diagnostics before station staging.")
  history_dir <- file.path(normalizePath(dirname(history_dir),winslash="/",mustWork=TRUE),basename(history_dir))
  if(basename(history_dir)%in%c(".","..")||!startsWith(tolower(history_dir),allowed)||tolower(history_dir)==tolower(source_dir))stop("Use a separate diagnostics history cache.")
  current <- read.csv(file.path(source_dir,"station-explorer-data.csv"),stringsAsFactors=FALSE)
  if (!setequal(unique(current$uid),stations$uid) || length(unique(current$as_of)) != 1L) stop("History station identities differ from the current station snapshot.")
  dir.create(history_dir,recursive=TRUE,showWarnings=FALSE)
  summary_path <- file.path(history_dir,"daily-summary.csv")
  completed <- FALSE
  on.exit(if(!completed)write.csv(data.frame(status="ERROR",page_date=unique(current$as_of),staged=FALSE),summary_path,row.names=FALSE),add=TRUE)
  # No ACIS calls: use only observations just updated by the normal station job.
  history <- build_station_custom_dates_pilot(stations,cache_dir,history_dir)$summary
  lock <- filelock::lock(file.path(history_dir,"build.lock"),timeout=0)
  if(is.null(lock))stop("Another historical station cache job is running.")
  on.exit(filelock::unlock(lock),add=TRUE)
  custom <- file.path(source_dir,"custom-history");dir.create(custom,showWarnings=FALSE)
  files <- hashes <- character()
  for(uid in stations$uid) {
    marker <- readRDS(file.path(history_dir,"history",uid,"build.rds"))
    files <- c(files,marker$files);hashes <- c(hashes,unname(marker$md5))
  }
  catalog_hash <- unname(tools::md5sum(file.path(history_dir,"catalog.json")))
  files <- c("catalog.json",files);hashes <- c(catalog_hash,hashes)
  copied <- station_history_copy(files,history_dir,custom,hashes,preserve_dates=TRUE)
  copied <- copied + station_history_refresh_assets(source_dir,source_dir)
  write.csv(data.frame(status="READY",stations=nrow(stations),current_cutoff=unique(current$as_of),historical_chunks=history$years),
    file.path(source_dir,"integration-summary.csv"),row.names=FALSE)
  write.csv(data.frame(file=files,md5=hashes),file.path(source_dir,"history-checksums.csv"),row.names=FALSE)
  validate_station_history_integration(source_dir)
  # Remove only obsolete generated annual/index JSON from this diagnostics copy.
  existing <- list.files(file.path(custom,"history"),recursive=TRUE,full.names=FALSE)
  generated <- existing[grepl("^[0-9]+/([0-9]{4}-|index-)[a-f0-9]+[.]json$",existing)]
  obsolete <- generated[!paste0("history/",generated) %in% files]
  if(length(obsolete))unlink(file.path(custom,"history",obsolete))
  result <- data.frame(status="READY",page_date=unique(current$as_of),stations=nrow(stations),years=history$years,built=history$built,reused=history$reused,
    copied_files=copied,requests=0L,staged=FALSE,seconds=round(proc.time()[["elapsed"]]-started,3))
  write.csv(result,summary_path,row.names=FALSE)
  completed <- TRUE
  attr(result,"summary_path") <- summary_path
  message(swc_station_history_summary_line(result))
  result
}

swc_station_beta_finish <- function(
    source_dir="data/diagnostics/acis-stations/station-explorer-prototype",destination="site/stations",
    enabled=swc_station_history_enabled(),history_update=swc_station_history_update,stage=swc_station_beta_stage) {
  history <- if(enabled)history_update(source_dir=source_dir) else NULL
  # No station directory is replaced until its optional history is also ready.
  snapshot <- stage(source_dir=source_dir,destination=destination)
  if(!is.null(history)) {
    history$staged <- TRUE
    if(!is.null(attr(history,"summary_path")))write.csv(history,attr(history,"summary_path"),row.names=FALSE)
  }
  list(snapshot=snapshot,history=history)
}

swc_station_history_summary_line <- function(result) {
  sprintf("Station history: %s; %d stations, %d annual chunks; %d rebuilt, %d reused; 0 extra observation requests (%ss).",
    result$status,result$stations,result$years,result$built,result$reused,result$seconds)
}
