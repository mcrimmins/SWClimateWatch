# Circulation render cache shared by local preview and optional daily adapter.
weather_renderer_signature <- function() {
  moisture <- c("weather_moisture_plot","weather_pressure_centers","weather_moisture_wind_mask",
    "weather_moisture_grid","weather_moisture_select_field","run_weather_moisture_pilot",
    "weather_core_check_range","weather_core_find_surface_pressure","weather_core_recover_surface_pressure")
  digest::digest(list(version=2L,R=R.version.string,
    moisture=lapply(moisture,function(name) {
      if(!exists(name,mode="function")) return(NULL)
      code <- body(get(name))
      # Canonicalize the transport-only attributed-raw writer repair to its
      # previous call. It changes saved bytes' attributes, not bytes or pixels,
      # and must not invalidate all retained map dates.
      if(name=="run_weather_moisture_pilot") code <- do.call(substitute,
        list(code,list(weather_moisture_write_bin=quote(writeBin))))
      code
    }),
    functions=lapply(list(weather_core_decode,weather_core_grid,weather_gaussian_latitudes,
      weather_circulation_plot,weather_contour_labels,weather_streamlines),body),
    packages=vapply(c("terra","ggplot2","maps","scales"),function(p)
      as.character(utils::packageVersion(p)),character(1))),algo="sha256")
}
build_weather_circulation_pair_cached <- function(dates, output_dir, refresh = FALSE) {
  dates <- as.Date(dates)
  if (!length(dates) || length(dates)>4L || anyNA(dates) || anyDuplicated(dates))
    stop("Choose 1-4 unique circulation dates.")
  renderer <- weather_renderer_signature()
  rows <- lapply(seq_along(dates),function(i) {
    date <- dates[i]; started <- proc.time()[["elapsed"]]
    directory <- file.path(output_dir,as.character(date)); requests <- bytes <- 0
    result <- tryCatch({
      download <- if (refresh) weather_core_download(date,directory,refresh=TRUE) else
        weather_core_download(date,directory)
      requests <- download$requests; bytes <- download$transferred_bytes
      signature <- digest::digest(list(renderer=renderer,date=as.character(date),
        source=download$plan,md5=unname(tools::md5sum(download$paths))),algo="sha256")
      marker <- file.path(directory,"map-cache.rds")
      old <- if (file.exists(marker)) tryCatch(readRDS(marker),error=function(e) NULL) else NULL
      paths <- file.path(directory,c("height500.png","jet250.png"))
      current <- is.list(old) && identical(old$signature,signature) &&
        all(file.exists(paths)) && identical(unname(tools::md5sum(paths)),old$md5)
      if (!current) {
        rasters <- weather_core_decode(download$paths,directory)
        weather_circulation_plot(rasters,date,directory)
        if (!all(file.exists(paths)) || any(file.info(paths)$size<=0)) stop("Incomplete map outputs.")
        saveRDS(list(signature=signature,md5=unname(tools::md5sum(paths))),marker)
      }
      list(status=if (current) "REUSED" else "BUILT",note="")
    },error=function(e) list(status="FAILED",note=conditionMessage(e)))
    data.frame(date=as.character(date),status=result$status,requests=requests,
      transferred_bytes=bytes,elapsed_seconds=proc.time()[["elapsed"]]-started,note=result$note)
  })
  result <- do.call(rbind,rows)
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  utils::write.csv(result,file.path(output_dir,"map-build-status.csv"),row.names=FALSE)
  result
}

# Keep moisture in the same bounded date transaction as heights/jet. Its source
# and output checksums allow unchanged runs to skip decoding and plotting.
build_weather_circulation_cached <- function(dates,output_dir,refresh=FALSE) {
  result <- build_weather_circulation_pair_cached(dates,output_dir,refresh)
  for(i in seq_len(nrow(result))) {
    if(result$status[i]=="FAILED") next
    started <- proc.time()[["elapsed"]]
    tryCatch({
      date <- result$date[i]; directory <- file.path(output_dir,date)
      marker <- file.path(directory,"moisture-map-cache.rds")
      path <- file.path(directory,"moisture.png")
      inputs <- function() sort(list.files(directory,pattern="^(day|3hour)-.*\\.(grb|idx)$",full.names=TRUE))
      signature <- function() digest::digest(list(renderer=weather_renderer_signature(),
        source=unname(tools::md5sum(inputs()))),algo="sha256")
      old <- if(file.exists(marker)) tryCatch(readRDS(marker),error=function(e) NULL) else NULL
      current <- !refresh && is.list(old) && length(inputs())>0 && file.exists(path) &&
        identical(old$signature,signature()) && identical(old$md5,unname(tools::md5sum(path)))
      if(!current) {
        moisture <- run_weather_moisture_pilot(as.Date(date),output_dir=output_dir,refresh=refresh)$summary
        result$requests[i] <- result$requests[i]+moisture$requests
        result$transferred_bytes[i] <- result$transferred_bytes[i]+moisture$transferred_bytes
        if(!file.copy(moisture$map,path,overwrite=TRUE)) stop("Could not stage moisture map.")
        note <- if(!is.null(moisture$terrain_samples_available) && moisture$terrain_samples_available<8L)
          "Moisture wind overlay omitted: incomplete hourly terrain-screening inputs." else ""
        if(identical(moisture$center_screen_available,FALSE))
          note <- trimws(paste(note,"H/L omitted: incomplete daily surface-pressure screening."))
        if(!is.null(moisture$pressure_recovered_samples) && moisture$pressure_recovered_samples>0)
          note <- trimws(paste(note,moisture$pressure_recovered_samples,"hourly pressure sample(s) recovered from GRIB despite incomplete index."))
        if(!is.null(moisture$pressure_recovery_notes) && nzchar(moisture$pressure_recovery_notes))
          note <- trimws(paste(note,moisture$pressure_recovery_notes))
        saveRDS(list(signature=signature(),md5=unname(tools::md5sum(path)),note=note),marker)
        result$note[i] <- note
        if(!isTRUE(moisture$map_reused)) result$status[i] <- "BUILT"
      } else if(!is.null(old$note)) result$note[i] <- old$note
    },error=function(e) {result$status[i]<<-"FAILED"; result$note[i]<<-conditionMessage(e)})
    result$elapsed_seconds[i] <- result$elapsed_seconds[i]+proc.time()[["elapsed"]]-started
  }
  utils::write.csv(result,file.path(output_dir,"map-build-status.csv"),row.names=FALSE)
  result
}

stage_daily_explorer_circulation_preview <- function(
    source_dir=file.path("data","diagnostics","daily-explorer"),
    output_dir=file.path("data","diagnostics","daily-explorer-circulation"),
    weather_dir=file.path("data","diagnostics","weather-circulation-explorer-cache"),
    preview_days=7L,sample_days=3L) {
  if (!file.exists(file.path(source_dir,"daily-data.json"))) stop("Build the local Daily Explorer first.")
  # This preview must never write to site/ or overwrite its source explorer.
  permitted <- normalizePath(file.path("data","diagnostics"),winslash="/",mustWork=TRUE)
  output <- normalizePath(output_dir,winslash="/",mustWork=FALSE)
  if (!startsWith(output,paste0(permitted,"/")) ||
      identical(output,normalizePath(source_dir,winslash="/",mustWork=TRUE)))
    stop("Use a separate preview directory under data/diagnostics.")
  if (length(preview_days)!=1L || !is.finite(preview_days) || preview_days<1 || preview_days>30 ||
      preview_days!=floor(preview_days) || length(sample_days)!=1L || !is.finite(sample_days) ||
      sample_days<1 || sample_days>4 || sample_days!=floor(sample_days)) stop("Bound the preview to 1-30 PRISM dates and 1-4 circulation dates.")
  payload <- jsonlite::read_json(file.path(source_dir,"daily-data.json"))
  if (!length(payload$days)) stop("No local PRISM dates.")
  payload$days <- tail(payload$days,preview_days)
  dates <- as.Date(vapply(tail(payload$days,sample_days),`[[`,character(1),"date"))
  status <- build_weather_circulation_cached(dates,weather_dir)
  dir.create(file.path(output_dir,"maps"),recursive=TRUE,showWarnings=FALSE)
  copy <- function(from,to) {
    if (!file.exists(from)) stop("Missing preview input: ",from)
    if (file.exists(to) && identical(unname(tools::md5sum(from)),unname(tools::md5sum(to)))) return(invisible())
    if (!file.copy(from,to,overwrite=TRUE)) stop("Could not copy preview input: ",from)
  }
  for (asset in c("index.html","explorer.js","explorer.css"))
    copy(file.path("scripts","daily-explorer-assets",asset),file.path(output_dir,asset))
  images <- unlist(lapply(payload$days,function(day) unlist(day$images,use.names=FALSE)),use.names=FALSE)
  if (any(!grepl("^maps/[0-9]{4}-[0-9]{2}-[0-9]{2}-(pcpn|maxt|mint|tmean)-(observed|departure)\\.png$",images)))
    stop("Unexpected PRISM image reference.")
  for (image in images) copy(file.path(source_dir,image),file.path(output_dir,image))
  dir.create(file.path(output_dir,"circulation","maps"),recursive=TRUE,showWarnings=FALSE)
  records <- lapply(seq_len(nrow(status)),function(i) {
    date <- status$date[i]
    if (status$status[i]=="FAILED") return(list(date=date,status="unavailable"))
    fields <- c("height500","jet250","moisture")
    paths <- setNames(paste0("circulation/maps/",date,"-",fields,".png"),fields)
    for (field in names(paths)) copy(file.path(weather_dir,date,paste0(field,".png")),file.path(output_dir,paths[[field]]))
    list(date=date,status="available",images=as.list(paths))
  })
  jsonlite::write_json(list(schema_version=1L,source="NOAA CPC CORe",days=records),
    file.path(output_dir,"circulation-manifest.json"),auto_unbox=TRUE,pretty=TRUE)
  payload$publication_mode <- FALSE; payload$circulation_preview <- TRUE
  payload$latest_cached_date <- tail(payload$days,1)[[1]]$date
  jsonlite::write_json(payload,file.path(output_dir,"daily-data.json"),auto_unbox=TRUE,digits=NA,pretty=FALSE)
  print(status,row.names=FALSE)
  message("Local circulation preview ready: ",file.path(output_dir,"index.html"))
  invisible(list(directory=output_dir,status=status,page=file.path(output_dir,"index.html")))
}
