# Local 1/7/30-day suite; source the existing CORe and seven-day helpers first.
weather_period_plan <- function(end_date="2026-10-05",days=30L,roots=weather_mean_roots()) {
  stopifnot(length(days)==1L,days%in%c(1L,7L,30L))
  end_date<-as.Date(end_date)
  if(length(end_date)!=1L||is.na(end_date)||end_date>=as.Date(Sys.time(),tz="UTC"))stop("Choose a completed UTC end date.")
  rows<-list()
  for(date in as.character(seq(end_date-days+1,end_date,by="day")))for(field in c("height500","pwat","u250","v250")) {
    row<-weather_mean_cached_field(date,field,roots)
    if(is.null(row))row<-data.frame(date,field,path=NA_character_,index=NA_character_,md5=NA_character_,index_md5=NA_character_)
    row$ready<-!is.na(row$path);rows[[length(rows)+1L]]<-row
  }
  do.call(rbind,rows)
}

weather_period_download <- function(plan,directory="data/diagnostics/weather-period-inputs",
    max_dates=30L,max_fields=120L,max_requests=180L,max_bytes=60e6) {
  missing<-plan[!plan$ready,,drop=FALSE]
  if(nrow(missing)>max_fields||length(unique(missing$date))>max_dates)stop("Suite download cap exceeded.")
  requests<-bytes<-0;indexes<-new.env(parent=emptyenv())
  get<-function(url,record=NULL) {
    if(requests>=max_requests||bytes>=max_bytes)stop("Suite request/byte budget exceeded.")
    req<-weather_core_request(url)
    if(!is.null(record))req<-httr2::req_headers(req,Range=sprintf("bytes=%.0f-%.0f",record$start,record$end),`Accept-Encoding`="identity")
    requests<<-requests+1L;response<-httr2::req_perform(req);body<-httr2::resp_body_raw(response)
    if(is.null(record)){if(httr2::resp_status(response)!=200L)stop("Daily index unavailable.")} else
      weather_core_check_response(body,httr2::resp_status(response),httr2::resp_header(response,"Content-Range"),record$start,record$end)
    bytes<<-bytes+length(body);if(bytes>max_bytes)stop("Suite byte cap exceeded.")
    attributes(body)<-NULL;body
  }
  for(date in unique(missing$date)) {
    target<-file.path(directory,date);dir.create(target,recursive=TRUE,showWarnings=FALSE)
    for(field in missing$field[missing$date==date]) {
      stamp<-format(as.Date(date),"%Y%m%d");type<-if(field=="pwat")"flx" else "pgb"
      base<-paste0("https://storage.googleapis.com/noaa-nws-ncep-core/grib/day/",type,"/",format(as.Date(date),"%Y/%m/"),type,".",stamp)
      if(!exists(base,indexes,inherits=FALSE))assign(base,get(paste0(base,".idx")),indexes)
      index<-base::get(base,envir=indexes,inherits=FALSE)
      record<-weather_mean_record(strsplit(rawToChar(index),"\n",fixed=TRUE)[[1]],date,field)
      body<-get(paste0(base,".grb"),record)
      path<-file.path(target,if(field=="pwat")paste0("day-flx-",stamp,"-PWAT-atmos_col.grb") else paste0(field,".grb"))
      writeBin(index,file.path(target,if(field=="pwat")paste0("day-flx-",stamp,".idx") else "source.idx"))
      writeBin(body,path);saveRDS(list(md5=unname(tools::md5sum(path)),source=base),paste0(path,".rds"))
    }
    message("Cached suite inputs: ",date)
  }
  list(requests=requests,bytes=bytes)
}

weather_period_daily <- function(plan,cache_dir) {
  date<-unique(plan$date)
  if(length(date)!=1L||nrow(plan)!=4L||!all(plan$ready)||!setequal(plan$field,c("height500","pwat","u250","v250")))stop("Require four verified daily fields.")
  key<-digest::digest(list(version=1,input=plan[,c("date","field","md5","index_md5")],
    code=lapply(list(weather_period_daily,weather_core_grid,weather_moisture_grid,weather_gaussian_latitudes),body),terra=as.character(utils::packageVersion("terra"))),algo="sha256")
  dir.create(cache_dir,recursive=TRUE,showWarnings=FALSE)
  path<-file.path(cache_dir,paste0(date,".rds"));marker<-paste0(path,".md5.rds")
  old<-if(file.exists(marker))tryCatch(readRDS(marker),error=function(e)NULL) else NULL
  if(is.list(old)&&identical(old$key,key)&&file.exists(path)&&identical(old$md5,unname(tools::md5sum(path))))return(readRDS(path))
  reference<-template<-NULL;values<-list()
  plan<-plan[match(c("height500","pwat","u250","v250"),plan$field),]
  for(i in 1:4) {
    row<-plan[i,];info<-terra::describe(row$path,print=FALSE)
    required<-switch(row$field,height500=c("GRIB_ELEMENT=HGT","GRIB_UNIT=[gpm]","GRIB_SHORT_NAME=50000-ISBL"),
      pwat=c("GRIB_ELEMENT=PWAT","GRIB_UNIT=[kg/(m^2)]"),u250=c("GRIB_ELEMENT=UGRD","GRIB_UNIT=[m/s]","GRIB_SHORT_NAME=25000-ISBL"),
      v250=c("GRIB_ELEMENT=VGRD","GRIB_UNIT=[m/s]","GRIB_SHORT_NAME=25000-ISBL"))
    required<-c(required,paste0("GRIB_VALID_TIME=",sprintf("%.0f",as.numeric(as.POSIXct(paste(date,"21:00:00"),tz="UTC")))))
    if(!all(vapply(required,function(x)any(grepl(x,info,fixed=TRUE)),logical(1))))stop("Wrong suite field, units, pressure level or valid time.")
    r<-terra::rast(row$path);if(terra::nlyr(r)!=1)stop("Expected one GRIB layer.")
    if(is.null(reference)) {
      reference<-weather_core_grid(row$path);template<-r
      x<-terra::xyFromCell(r,seq_len(terra::ncell(r)))[,1];x<-ifelse(x<120,x+360,x)
      y<-rep(reference$latitude,each=terra::ncol(r));keep<-x>=120&x<=300&y>=10&y<=70
      edges<-c(90,(head(reference$latitude,-1)+tail(reference$latitude,-1))/2,-90)
      geometry<-data.frame(x=x[keep],y=y[keep],xmin=x[keep]-terra::res(r)[1]/2,xmax=x[keep]+terra::res(r)[1]/2,
        ymin=rep(tail(edges,-1),each=terra::ncol(r))[keep],ymax=rep(head(edges,-1),each=terra::ncol(r))[keep])
    } else {
      check<-weather_moisture_grid(row$path,reference)
      if(!identical(check$section,reference$section)||!terra::compareGeom(template,r,stopOnError=FALSE))stop("Suite grids differ; no resampling.")
    }
    value<-as.numeric(terra::values(r,mat=FALSE))[keep]
    if(any(!is.finite(value))||any(switch(row$field,height500=value<3000|value>7000,pwat=value<0|value>150,abs(value)>250)))stop("Invalid suite field values.")
    values[[row$field]]<-value
  }
  result<-list(date=date,geometry=geometry,values=do.call(cbind,values),inputs=plan)
  saveRDS(result,path);saveRDS(list(key=key,md5=unname(tools::md5sum(path))),marker)
  result
}

weather_period_average <- function(daily,days) {
  if(!days%in%c(1L,7L,30L)||length(daily)!=days)stop("Require the complete selected period.")
  dates<-as.Date(vapply(daily,`[[`,character(1),"date"))
  if(anyNA(dates)||anyDuplicated(dates)||any(diff(dates)!=1))stop("Require consecutive unique UTC dates.")
  first<-daily[[1]]
  for(d in daily)if(!identical(d$geometry,first$geometry)||!identical(dim(d$values),dim(first$values))||
    !identical(colnames(d$values),c("height500","pwat","u250","v250"))||any(!is.finite(d$values)))stop("Incomplete values or inconsistent native grids.")
  values<-Reduce(`+`,lapply(daily,`[[`,"values"))/days
  data<-first$geometry
  data$height_dm<-values[,"height500"]/10;data$pwat_inches<-values[,"pwat"]/25.4
  data$u250<-values[,"u250"];data$v250<-values[,"v250"]
  data$speed_knots<-sqrt(data$u250^2+data$v250^2)*1.943844
  data
}

run_weather_period_suite <- function(end_date="2026-10-05",download_missing=FALSE,
    output_dir="data/diagnostics/weather-period-means-pilot",roots=weather_mean_roots()) {
  started<-proc.time()[["elapsed"]];end_date<-as.Date(end_date)
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  plan<-weather_period_plan(end_date,30,roots);write.csv(plan,file.path(output_dir,"input-plan.csv"),row.names=FALSE)
  transfer<-list(requests=0,bytes=0)
  if(any(!plan$ready)&&download_missing) {
    transfer<-weather_period_download(plan)
    plan<-weather_period_plan(end_date,30,roots)
  }
  write.csv(plan,file.path(output_dir,"input-plan.csv"),row.names=FALSE)
  if(any(!plan$ready))stop("Missing/unverified suite inputs: ",sum(!plan$ready),". No partial means. Inspect input-plan.csv; opt in to bounded selected-field downloads if needed.")
  reports<-list();decoded<-NULL
  for(days in c(1L,7L,30L)) {
    selected<-plan[as.Date(plan$date)>=end_date-days+1,,drop=FALSE]
    directory<-file.path(output_dir,paste0(days,"day"));dir.create(directory,showWarnings=FALSE)
    paths<-file.path(directory,c(paste0(c("height500-","pwat-","jet250-"),days,"day.png"),"mean-native-grid.rds"))
    signature<-digest::digest(list(version=1,days=days,source=selected[,c("date","field","md5","index_md5")],
      functions=lapply(list(weather_mean_plot,weather_streamlines,weather_contour_labels,weather_period_average,weather_period_daily),body),
      R=R.version.string,packages=vapply(c("terra","ggplot2","maps","scales"),function(p)as.character(utils::packageVersion(p)),character(1))),algo="sha256")
    marker<-file.path(directory,"complete.rds");old<-if(file.exists(marker))tryCatch(readRDS(marker),error=function(e)NULL) else NULL
    reused<-is.list(old)&&identical(old$signature,signature)&&all(file.exists(paths))&&identical(old$md5,unname(tools::md5sum(paths)))
    seconds<-proc.time()[["elapsed"]]
    if(!reused) {
      if(is.null(decoded)) {
        decoded<-lapply(split(plan,plan$date),weather_period_daily,cache_dir=file.path(output_dir,"decoded"))
        message("Decoded/verified ",length(decoded)," daily records for all time scales.")
      }
      chosen<-decoded[as.character(seq(end_date-days+1,end_date,by="day"))]
      data<-weather_period_average(chosen,days)
      weather_mean_plot(data,end_date-days+1,end_date,directory,days=days,include_jet=TRUE)
      saveRDS(list(cells=data,dates=names(chosen),inputs=selected),paths[4])
      saveRDS(list(signature=signature,md5=unname(tools::md5sum(paths))),marker)
    }
    reports[[length(reports)+1]]<-data.frame(days,start=as.character(end_date-days+1),end=as.character(end_date),maps=3L,reused,seconds=proc.time()[["elapsed"]]-seconds)
    message("Weather suite ",days," day(s): ",if(reused)"REUSED" else "BUILT")
  }
  report<-do.call(rbind,reports)
  write.csv(report,file.path(output_dir,"period-summary.csv"),row.names=FALSE)
  summary<-data.frame(dates=30,fields=120,maps=9,built=sum(!report$reused)*3,reused=sum(report$reused)*3,
    requests=transfer$requests,bytes=transfer$bytes,seconds=proc.time()[["elapsed"]]-started,
    retained_mb=sum(file.info(list.files(output_dir,recursive=TRUE,full.names=TRUE))$size,na.rm=TRUE)/1024^2)
  write.csv(summary,file.path(output_dir,"run-summary.csv"),row.names=FALSE)
  weather_period_viewer(report,output_dir)
  list(summary=summary,periods=report)
}

weather_period_viewer <- function(periods,directory,moisture_overlays=FALSE) {
  writeLines(c('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Weather period means</title>',
    '<style>body{font:16px system-ui;background:#f1f5f6;color:#24363e;margin:24px auto;max-width:1300px;padding:0 16px}main{background:white;padding:20px;border-radius:10px}nav{display:flex;gap:8px;margin:16px 0;flex-wrap:wrap}button,select{font:inherit;padding:9px;border:1px solid #b5c8ce;border-radius:5px;background:white}button[aria-selected="true"]{background:#e6f1f4;border-color:#237a8b}img{width:100%;height:auto}p{line-height:1.5}#range{color:#506770}</style>',
    '<main><h1>Weather maps: period means</h1><label>Period <select id="period"><option value="1">1 day</option><option value="7" selected>7 days</option><option value="30">30 days</option></select></label>',
    '<nav role="tablist" aria-label="Weather variable"><button role="tab" data-field="height500" aria-selected="true">500-mb heights</button><button role="tab" data-field="jet250" aria-selected="false">250-mb jet and flow</button><button role="tab" data-field="pwat" aria-selected="false">PWAT</button></nav>',
    '<p id="range" aria-live="polite"></p><img id="map" alt=""><p><a id="full" target="_blank" rel="noopener">Open full-resolution PNG</a></p><p id="note"></p>',
    '<p>Complete UTC days only; each daily field contains eight three-hour samples. Shared color scales allow comparison across periods. These are absolute conditions, not anomalies. Local pilot only.</p></main>',
    paste0('<script>const periods=',jsonlite::toJSON(periods, dataframe="rows",auto_unbox=TRUE),';const moistureOverlays=',tolower(as.character(moisture_overlays)),';'),
    'let field="height500";const select=document.getElementById("period"),buttons=Array.from(document.querySelectorAll("[data-field]"));',
    'function render(){const p=periods.find(p=>String(p.days)===select.value),name=field==="pwat"&&moistureOverlays?"pwat-overlay":field,src=`${p.days}day/${name}-${p.days}day.png`;document.getElementById("map").src=src;document.getElementById("full").href=src;document.getElementById("map").alt=`${p.days}-day ${field} mean ending ${p.end}`;document.getElementById("range").textContent=`${p.start} through ${p.end} UTC · ${p.days} complete day(s)`;document.getElementById("note").textContent=field==="jet250"?"Shading is the speed of the mean wind vector; streamlines show mean flow. Changing wind directions can weaken the period mean. This is not mean scalar wind speed, maximum wind or surface wind.":field==="pwat"?(moistureOverlays?"PWAT is column water vapor (inches); contours show mean sea-level pressure every 4 hPa. Arrows show mean 850-mb flow, screened above terrain at every sample. H/L mark filtered mean pressure centers, not tracked storms. These winds are not IVT or surface winds.":"PWAT shows total column water vapor, in inches. It is not precipitation or moisture transport."):"500-mb heights show broad troughs and ridges; contours are spaced every 6 dam.";buttons.forEach(b=>b.setAttribute("aria-selected",String(b.dataset.field===field)));}',
    'select.addEventListener("change",render);buttons.forEach(b=>b.addEventListener("click",()=>{field=b.dataset.field;render()}));render();</script></html>'),
    file.path(directory,"index.html"),useBytes=TRUE)
}
