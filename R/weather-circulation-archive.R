# Retained, growing weather-map archive. Explicit opt-in at publication time.
weather_write_json <- function(value,path) {
  text <- jsonlite::toJSON(value,auto_unbox=TRUE,null="null",na="null",digits=NA,pretty=TRUE)
  if (!file.exists(path) || !identical(paste(readLines(path,warn=FALSE),collapse="\n"),as.character(text)))
    writeLines(text,path,useBytes=TRUE)
}

weather_archive_plan <- function(explorer_dates,known_dates=character(),start_date=NULL,
    today=Sys.Date(),max_new_dates=3L,recheck_days=3L,checked_dates=character()) {
  dates <- sort(unique(as.Date(explorer_dates))); today <- as.Date(today)
  if (!length(dates) || anyNA(dates) || length(today)!=1L || is.na(today)) stop("Invalid weather archive dates.")
  if (length(max_new_dates)!=1L || !is.finite(max_new_dates) || max_new_dates<0 || max_new_dates>30 ||
      max_new_dates!=floor(max_new_dates) || length(recheck_days)!=1L || !is.finite(recheck_days) ||
      recheck_days<0 || recheck_days>7 || recheck_days!=floor(recheck_days)) stop("Bound new dates to 0-30 and rechecks to 0-7 days.")
  eligible <- dates[dates<today]
  if (!length(eligible)) return(data.frame(date=character(),action=character()))
  start <- if (is.null(start_date)) max(eligible)-29L else as.Date(start_date)
  if (length(start)!=1L || is.na(start)) stop("Invalid archive start date.")
  eligible <- eligible[eligible>=start]
  missing <- rev(eligible[!as.character(eligible) %in% known_dates])
  scheduled <- head(missing,max_new_dates)
  # Re-fetch recent complete records at most once per run date. Comparing full
  # field hashes detects revisions even when byte offsets have not changed.
  recheck <- eligible[eligible>=today-recheck_days & as.character(eligible) %in% known_dates &
    !as.character(eligible) %in% checked_dates]
  data.frame(date=c(as.character(scheduled),as.character(recheck)),
    action=c(rep("BUILD",length(scheduled)),rep("RECHECK",length(recheck))))
}

update_weather_circulation_archive <- function(explorer_dir=file.path("site","daily-explorer"),
    archive_dir=file.path("data","processed","weather-circulation"),today=Sys.Date(),
    max_new_dates=3L,recheck_days=3L,backfill=FALSE) {
  started <- proc.time()[["elapsed"]]
  payload_path <- file.path(explorer_dir,"daily-data.json")
  payload <- jsonlite::read_json(payload_path)
  dates <- vapply(payload$days,`[[`,character(1),"date")
  if (!length(dates)) stop("No Daily Explorer dates.")
  dir.create(archive_dir,recursive=TRUE,showWarnings=FALSE)
  state_path <- file.path(archive_dir,"archive-state.rds")
  state <- if (file.exists(state_path)) readRDS(state_path) else list(start_date=NULL,records=list(),checked=list())
  valid <- vapply(state$records,function(record) {
    paths <- file.path(archive_dir,"daily",record$date,c("height500.png","jet250.png","moisture.png"))
    all(file.exists(paths)) && identical(unname(tools::md5sum(paths)),record$md5)
  },logical(1))
  state$records <- state$records[valid]
  renderer <- weather_renderer_signature()
  current_dates <- names(state$records)[vapply(state$records,function(record)
    identical(record$renderer,renderer),logical(1))]
  eligible <- as.Date(dates); eligible <- eligible[eligible<as.Date(today)]
  if (!length(eligible)) stop("No completed dates to build.")
  if (is.null(state$start_date)) state$start_date <- as.character(max(eligible)-29L)
  if (backfill) state$start_date <- as.character(min(as.Date(state$start_date),min(eligible)))
  checked <- names(state$checked)[vapply(state$checked,function(x) identical(x,as.character(today)),logical(1))]
  plan <- weather_archive_plan(dates,current_dates,state$start_date,today,
    max_new_dates,recheck_days,checked)
  reports <- list()
  for (i in seq_len(nrow(plan))) {
    date <- plan$date[i]
    message("Weather archive ",i,"/",nrow(plan),": ",date," (",plan$action[i],")")
    result <- build_weather_circulation_cached(as.Date(date),file.path(archive_dir,"daily"),
      refresh=identical(plan$action[i],"RECHECK"))
    reports[[i]] <- result
    if (result$status!="FAILED") {
      paths <- file.path(archive_dir,"daily",date,c("height500.png","jet250.png","moisture.png"))
      state$records[[date]] <- list(date=date,md5=unname(tools::md5sum(paths)),renderer=renderer)
      state$checked[[date]] <- as.character(today)
    }
    # Checkpoint every successful date, so interruption never loses the batch.
    saveRDS(state,state_path)
  }
  if (!file.exists(state_path)) saveRDS(state,state_path)
  reports <- if (length(reports)) do.call(rbind,reports) else
    data.frame(date=character(),status=character(),requests=numeric(),transferred_bytes=numeric(),elapsed_seconds=numeric(),note=character())
  # Retain records from earlier runs/years; no rolling deletion. Only verified
  # complete three-map sets enter the manifest, including after an upstream failure.
  dir.create(file.path(explorer_dir,"circulation","maps"),recursive=TRUE,showWarnings=FALSE)
  records <- list(); failed_outputs <- 0L
  for (date in sort(names(state$records))) {
    source_paths <- file.path(archive_dir,"daily",date,c("height500.png","jet250.png","moisture.png"))
    if (!all(file.exists(source_paths)) ||
        !identical(unname(tools::md5sum(source_paths)),state$records[[date]]$md5)) {
      failed_outputs <- failed_outputs+1L; next
    }
    fields <- c("height500","jet250","moisture")
    relative <- setNames(paste0("circulation/maps/",date,"-",fields,".png"),fields)
    copied <- tryCatch({
      for (j in seq_along(fields)) {
        destination <- file.path(explorer_dir,relative[j])
        if (!file.exists(destination) || !identical(unname(tools::md5sum(destination)),state$records[[date]]$md5[j]))
          if (!file.copy(source_paths[j],destination,overwrite=TRUE)) stop("Weather map staging copy failed.")
        if (!identical(unname(tools::md5sum(destination)),state$records[[date]]$md5[j])) stop("Weather map checksum mismatch.")
      }
      TRUE
    },error=function(e) FALSE)
    if (!copied) {failed_outputs<-failed_outputs+1L; next}
    records[[date]] <- list(date=date,status="available",images=as.list(relative),
      verified_on=state$checked[[date]])
  }
  failures <- sum(reports$status=="FAILED")+failed_outputs
  manifest <- list(schema_version=1L,source="NOAA CPC CORe",status=if(failures) "PARTIAL" else "READY",
    days=unname(records))
  weather_write_json(manifest,file.path(explorer_dir,"circulation-manifest.json"))
  payload$circulation_enabled <- TRUE
  weather_write_json(payload,payload_path)
  summary <- list(status=manifest$status,days=length(records),maps=3L*length(records),
    built=sum(reports$status=="BUILT"),reused=sum(reports$status=="REUSED"),failed=failures,
    pending=sum(eligible>=as.Date(state$start_date) & !as.character(eligible) %in%
      names(state$records)[vapply(state$records,function(record) identical(record$renderer,renderer),logical(1))]),
    latest=if(length(records)) max(names(records)) else NA_character_,
    lag_days=if(length(records)) as.integer(as.Date(today)-as.Date(max(names(records)))) else NA_integer_,
    requests=sum(reports$requests),elapsed_seconds=proc.time()[["elapsed"]]-started)
  utils::write.csv(as.data.frame(summary),file.path(archive_dir,"update-summary.csv"),row.names=FALSE)
  utils::write.csv(reports,file.path(archive_dir,"last-batch.csv"),row.names=FALSE)
  message("Weather maps: ",summary$days," dates retained; ",summary$built," built, ",summary$reused,
    " reused, ",summary$failed," failed; ",summary$pending," pending.")
  invisible(summary)
}

disable_weather_circulation <- function(explorer_dir=file.path("site","daily-explorer")) {
  path <- file.path(explorer_dir,"daily-data.json")
  if (file.exists(path)) {
    payload <- jsonlite::read_json(path); payload$circulation_enabled <- FALSE
    weather_write_json(payload,path)
  }
  invisible(NULL)
}

backfill_weather_circulation_archive <- function(explorer_dir=file.path("site","daily-explorer"),
    archive_dir=file.path("data","processed","weather-circulation"),today=Sys.Date(),
    batch_size=3L,max_batches=1L,dry_run=TRUE) {
  if (length(max_batches)!=1L || !is.finite(max_batches) || max_batches<1 || max_batches>100 ||
      max_batches!=floor(max_batches) || !is.logical(dry_run) || length(dry_run)!=1L || is.na(dry_run))
    stop("Choose 1-100 batches and a logical dry_run.")
  if (length(batch_size)!=1L || !is.finite(batch_size) || batch_size<1 || batch_size>30 ||
      batch_size!=floor(batch_size)) stop("Choose a batch size of 1-30 dates.")
  payload <- jsonlite::read_json(file.path(explorer_dir,"daily-data.json"))
  dates <- vapply(payload$days,`[[`,character(1),"date")
  state_path <- file.path(archive_dir,"archive-state.rds")
  state <- if (file.exists(state_path)) readRDS(state_path) else list(records=list())
  renderer <- weather_renderer_signature()
  known <- names(state$records)[vapply(state$records,function(record) identical(record$renderer,renderer),logical(1))]
  plan <- weather_archive_plan(dates,known,start_date=min(as.Date(dates)),today=today,
    max_new_dates=batch_size,recheck_days=0)
  if (dry_run) {
    print(plan,row.names=FALSE)
    message("Backfill preview only. At most ",batch_size*max_batches," date attempts; archived dates are retained.")
    return(invisible(list(plan=plan)))
  }
  result <- NULL
  for (batch in seq_len(max_batches)) {
    message("Weather backfill batch ",batch,"/",max_batches)
    result <- update_weather_circulation_archive(explorer_dir,archive_dir,today,
      max_new_dates=batch_size,recheck_days=0,backfill=TRUE)
    if (result$pending==0L) break
    if (result$failed>0L) {message("Stopped after a failed date; inspect last-batch.csv before resuming."); break}
  }
  invisible(result)
}

validate_weather_circulation_assets <- function(directory) {
  payload <- jsonlite::read_json(file.path(directory,"daily-data.json"))
  if (!isTRUE(payload$circulation_enabled)) return(invisible(TRUE))
  manifest <- jsonlite::read_json(file.path(directory,"circulation-manifest.json"))
  if (!identical(manifest$schema_version,1L) || !is.list(manifest$days)) stop("Invalid weather manifest.")
  seen <- character()
  for (day in manifest$days) {
    date <- day$date
    if (length(date)!=1L || is.na(as.Date(date)) || date %in% seen || !identical(day$status,"available")) stop("Invalid weather date.")
    seen <- c(seen,date)
    for (field in c("height500","jet250","moisture")) {
      expected <- paste0("circulation/maps/",date,"-",field,".png")
      if (!identical(day$images[[field]],expected) || !file.exists(file.path(directory,expected)) ||
          file.info(file.path(directory,expected))$size<=0) stop("Missing or invalid weather image.")
    }
  }
  invisible(TRUE)
}
