# Read cached inputs only. No downloads, rendering or site/VM changes.
source("scripts/load-daily-explorer-wy2026.R")
inventory_wy2026_explorer <- function() {
  windows<-wy2026_explorer_windows();root<-wy2026_explorer_root()
  dates<-as.character(seq(as.Date(windows[[1]]$start)-29L,as.Date(windows[[12]]$end),by="day"))
  manifest<-read.csv("data/processed/prism/manifest.csv",stringsAsFactors=FALSE)
  manifest$start_date<-as.Date(manifest$start_date);manifest$end_date<-as.Date(manifest$end_date)
  message("WY2026: checking daily PRISM layer headers. No downloads.")
  index<-daily_explorer_index(as.Date("2025-10-01"),as.Date("2026-09-30"),manifest)
  rows<-lapply(seq_along(dates),function(i) {
    d<-dates[i];base<-weather_period_plan(d,1L)
    overlay<-tryCatch(weather_overlay_inputs(as.Date(d),download_missing=FALSE)$inputs,error=function(e)NULL)
    required<-c("mslp","u850","v850")
    overlays<-if(is.null(overlay))FALSE else all(required%in%overlay$field)&&!anyNA(overlay$path[match(required,overlay$field)])
    if(i%%30L==0L)message("WY2026 cached weather inventory: ",i,"/",length(dates))
    data.frame(date=d,core_fields_verified=sum(base$ready),required_overlays_present=overlays)
  })
  support<-do.call(rbind,rows)
  result<-do.call(rbind,lapply(windows,function(w) {
    target<-as.character(seq(as.Date(w$start),as.Date(w$end),by="day"))
    needed<-support[support$date>=as.character(as.Date(w$start)-29L)&support$date<=w$end,]
    bounds<-list(c(w$start,as.character(as.Date(w$end)+1L)),c(as.character(as.Date(w$start)-30L),w$start))
    reports<-vapply(bounds,function(b) {
      f<-file.path("data/raw/storm-reports/az-nm",paste0(b[1],"_",b[2],".rds"))
      x<-if(file.exists(f))tryCatch(readRDS(f),error=function(e)NULL)else NULL
      is.list(x)&&identical(x$start,b[1])&&identical(x$end,b[2])&&!is.null(x$fetched_utc)
    },logical(1))
    data.frame(month=substr(w$start,1,7),dates=length(target),
      prism_day_inputs=sum(index$date%in%target),prism_required=3L*length(target),
      supporting_weather_dates=nrow(needed),core_complete=sum(needed$core_fields_verified==4L),
      required_overlays_present=sum(needed$required_overlays_present),report_range_caches=sum(reports),report_ranges_required=2L)
  }))
  write.csv(support,file.path(root,"cache-support.csv"),row.names=FALSE)
  write.csv(result,file.path(root,"cache-inventory.csv"),row.names=FALSE)
  print(result,row.names=FALSE)
  message("PRISM checks are layer headers; full cell/record checks occur during building. Overlay presence is not full checksum/screening validation. Hazard archives and optional terrain still require builder validation.")
  invisible(result)
}
wy2026_inventory<-inventory_wy2026_explorer()
