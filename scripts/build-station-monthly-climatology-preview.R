# Isolated station climatology review. Cached histories only; no site staging.
source("R/config.R")
source("R/acis-station-inventory.R")
source("R/acis-station-daily-pilot.R")
source("R/acis-station-current-prototype.R")
source("R/acis-station-monthly-climatology.R")

build_station_monthly_climatology_preview <- function(
    source_dir="data/diagnostics/acis-stations/station-explorer-prototype",
    output_dir="data/diagnostics/station-monthly-climatology-preview",
    reference_cache_dir="data/diagnostics/station-monthly-climatology-cache") {
  started<-proc.time()[["elapsed"]]
  if(!file.exists(file.path(source_dir,"station-explorer-data.csv")))
    stop("Build the integrated Station Conditions preview first.")
  stopifnot(normalizePath(source_dir,winslash="/",mustWork=TRUE)!=normalizePath(output_dir,winslash="/",mustWork=FALSE))
  rows<-read.csv(file.path(source_dir,"station-explorer-data.csv"),stringsAsFactors=FALSE)
  uids<-unique(rows$uid);snapshot<-unique(rows$as_of)
  stopifnot(length(snapshot)==1L)
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  files<-list.files(source_dir,full.names=TRUE);files<-files[!dir.exists(files)]
  if(!all(file.copy(files,output_dir,overwrite=TRUE)))stop("Could not copy preview assets.")
  js<-paste(readLines(file.path(output_dir,"explorer.js"),warn=FALSE,encoding="UTF-8"),collapse="\n")
  old<-'`<div class="detail-lower"><section><h3>Usable daily record</h3><ul>`'
  if(!grepl(old,js,fixed=TRUE))stop("Station climatology integration point changed.")
  if(!grepl('SWCStationMonthlyClimatology.section',js,fixed=TRUE))
    js<-sub(old,paste0('window.SWCStationMonthlyClimatology.section(detail.monthly_climatology) + ',old),js,fixed=TRUE)
  if(!grepl('SWCStationMonthlyClimatology.mount',js,fixed=TRUE))js<-sub('detailContentEl.innerHTML = detailContent(current, detail);',
    'detailContentEl.innerHTML = detailContent(current, detail); window.SWCStationMonthlyClimatology.mount(detailContentEl.querySelector(".station-climatology"),detail.monthly_climatology);',js,fixed=TRUE)
  js<-sub('src="seasonal/index.html?','src="../acis-stations/station-explorer-prototype/seasonal/index.html?',js,fixed=TRUE)
  writeLines(js,file.path(output_dir,"explorer.js"),useBytes=TRUE)
  html<-paste(readLines(file.path(output_dir,"index.html"),warn=FALSE,encoding="UTF-8"),collapse="\n")
  if(!grepl('src="monthly-climatology.js"',html,fixed=TRUE))html<-sub('<script src="explorer.js" defer></script>',
    '<script src="monthly-climatology.js" defer></script><script src="explorer.js" defer></script>',html,fixed=TRUE)
  if(!grepl('href="monthly-climatology.css"',html,fixed=TRUE))html<-sub('</head>','<link rel="stylesheet" href="monthly-climatology.css"></head>',html,fixed=TRUE)
  html<-sub('</head>','<meta name="swc-preview" content="station-monthly-climatology"></head>',html,fixed=TRUE)
  writeLines(html,file.path(output_dir,"index.html"),useBytes=TRUE)
  if(!all(file.copy(file.path("scripts/station-monthly-climatology-assets",c("monthly-climatology.js","monthly-climatology.css")),output_dir,overwrite=TRUE)))
    stop("Could not copy monthly chart assets.")
  detail_dir<-file.path(output_dir,"station-details");dir.create(detail_dir,showWarnings=FALSE)
  report<-vector("list",length(uids))
  message("Monthly station climatology: ",length(uids)," cached stations; no requests.")
  for(i in seq_along(uids)) {
    uid<-uids[i]
    cache<-acis_station_read_daily_cache(acis_station_daily_cache_path(uid),uid)
    detail<-jsonlite::read_json(file.path(source_dir,"station-details",paste0(uid,".json")),simplifyVector=TRUE)
    stopifnot(as.integer(detail$uid)==as.integer(uid),detail$as_of==snapshot)
    reference<-read_or_build_acis_monthly_climatology(cache,uid,reference_cache_dir,as_of=snapshot)
    full<-read_or_build_acis_monthly_climatology(cache,uid,reference_cache_dir,period="record",as_of=snapshot)
    detail$monthly_climatology<-reference$reference
    detail$monthly_climatology$full_record<-full$reference
    jsonlite::write_json(detail,file.path(detail_dir,paste0(uid,".json")),auto_unbox=TRUE,
      dataframe="rows",na="null",null="null",digits=7)
    monthly<-reference$reference$monthly
    report[[i]]<-data.frame(uid,name=detail$name,reused=reference$reused,record_reused=full$reused,
      precipitation_months=sum(is.finite(monthly$precip_inches)),temperature_months=sum(is.finite(monthly$high_f)),
      record_precipitation_months=sum(is.finite(full$reference$monthly$precip_inches)),
      record_temperature_months=sum(is.finite(full$reference$monthly$high_f)),record_span=full$reference$baseline)
    if(i%%10L==0L || i==length(uids))message("Monthly climatology: ",i,"/",length(uids))
  }
  report<-do.call(rbind,report)
  write.csv(report,file.path(output_dir,"coverage.csv"),row.names=FALSE)
  message(sprintf("Monthly station climatology ready: %d stations; %d baseline and %d full-record caches reused; %.1fs. No site files or publication changed.",
    length(uids),sum(report$reused),sum(report$record_reused),proc.time()[["elapsed"]]-started))
  invisible(report)
}
station_monthly_climatology_preview <- build_station_monthly_climatology_preview()
