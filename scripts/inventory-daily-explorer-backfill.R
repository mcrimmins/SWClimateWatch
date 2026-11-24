# Inventory only: reads local caches and writes diagnostic CSVs. No downloads,
# map builds, site changes or publication. Run from the repository root.
source("scripts/load-daily-explorer.R")
source("R/weather-circulation-pilot.R")
source("R/weather-seven-day-pilot.R")
source("R/storm-reports-daily.R")

inventory_daily_explorer_backfill <- function(start="2024-10-01",end=NULL,
    output_dir="data/diagnostics/daily-explorer-backfill-inventory") {
  manifest<-read.csv("data/processed/prism/manifest.csv",stringsAsFactors=FALSE)
  manifest$start_date<-as.Date(manifest$start_date);manifest$end_date<-as.Date(manifest$end_date)
  usable<-manifest[manifest$product=="daily"&manifest$aoi_id==swc_prism$aoi_id&
    manifest$variable%in%c("pcpn","maxt","mint")&file.exists(manifest$path),]
  if(!all(c("pcpn","maxt","mint")%in%usable$variable))stop("No usable daily PRISM manifest for all three inputs.")
  if(is.null(end))end<-min(vapply(split(usable$end_date,usable$variable),function(x)as.numeric(max(x)),numeric(1)))
  end<-if(is.numeric(end))as.Date(end,origin="1970-01-01")else as.Date(end)
  start<-as.Date(start)
  if(length(start)!=1L||length(end)!=1L||is.na(start)||is.na(end)||end<start||end-start>1200)stop("Choose a bounded backfill interval of at most 1,201 days.")
  first<-start-30L;dates<-as.character(seq(first,end,by="day"))
  message("Inventory PRISM layer headers: ",first," through ",end,". No raster values or downloads.")
  index<-daily_explorer_index(first,end,manifest)
  result<-data.frame(date=dates,month=substr(dates,1,7),input_buffer=as.Date(dates)<start,
    water_year=daily_explorer_water_year(dates),stringsAsFactors=FALSE)
  for(v in c("pcpn","maxt","mint"))result[[paste0("prism_",v,"_header")]]<-dates%in%index$date[index$variable==v]
  result$core_fields_verified<-0L
  result$report_day_verified<-FALSE
  roots<-weather_mean_roots()
  for(i in seq_along(dates)) {
    date<-dates[i]
    result$core_fields_verified[i]<-sum(vapply(c("height500","pwat","u250","v250"),
      function(field)!is.null(weather_mean_cached_field(date,field,roots)),logical(1)))
    result$report_day_verified[i]<-!is.null(storm_reports_read_day(file.path("data/processed/storm-reports/az-nm",paste0(date,".rds"))))
    if(i%%90L==0L)message("Inventory dates: ",i,"/",length(dates))
  }
  # ZIP presence with matching recorded digest is source-cache evidence only,
  # not proof of parsed event/geometry coverage or carry-in completeness.
  result$hazard_issued_zip_cached<-FALSE
  for(path in list.files("data/raw/nws-hazards/az-nm",pattern="[.]zip[.]rds$",full.names=TRUE)) {
    x<-tryCatch(readRDS(path),error=function(e)NULL);zip<-sub("[.]rds$","",path)
    if(!is.list(x)||!file.exists(zip)||!identical(x$md5,unname(tools::md5sum(zip)))||!identical(x$params$timeopt,1L))next
    a<-substr(x$params$sts,1,10);b<-substr(x$params$ets,1,10)
    result$hazard_issued_zip_cached<-result$hazard_issued_zip_cached|(dates>=a&dates<b)
  }
  result$prism_all_headers<-result$prism_pcpn_header&result$prism_maxt_header&result$prism_mint_header
  monthly<-do.call(rbind,lapply(split(result,result$month),function(x)data.frame(month=x$month[1],
    input_dates=nrow(x),target_dates=sum(!x$input_buffer),prism_three_input_dates=sum(x$prism_all_headers),
    prism_missing_day_inputs=sum(!x$prism_pcpn_header)+sum(!x$prism_maxt_header)+sum(!x$prism_mint_header),
    core_four_field_dates=sum(x$core_fields_verified==4L),core_missing_day_fields=sum(4L-x$core_fields_verified),
    reports_verified_dates=sum(x$report_day_verified),hazard_zip_cached_dates=sum(x$hazard_issued_zip_cached))))
  refs<-expand.grid(variable=c("maxt","mint"),statistic=c("mean","p10","p90"),stringsAsFactors=FALSE)
  refs$path<-mapply(daily_explorer_reference_path,refs$variable,refs$statistic)
  refs$present<-file.exists(refs$path)
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  write.csv(result,file.path(output_dir,"dates.csv"),row.names=FALSE)
  write.csv(monthly,file.path(output_dir,"months.csv"),row.names=FALSE)
  write.csv(refs,file.path(output_dir,"references.csv"),row.names=FALSE)
  print(monthly,row.names=FALSE)
  message("Inventory saved: ",output_dir)
  message("Limits: PRISM headers are not a cell-value audit; CORe overlay/surface-screening inputs and rendered assets still need a separate audit. Missing local caches do not establish remote source gaps. Request/storage budgets require the subsequent plan/benchmark.")
  invisible(list(dates=result,months=monthly,references=refs))
}

explorer_backfill_inventory<-inventory_daily_explorer_backfill()
