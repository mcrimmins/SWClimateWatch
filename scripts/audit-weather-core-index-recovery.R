# Three known bad-index cases. Selected byte windows only; no site/S3 changes.
source("scripts/load-weather-circulation-archive.R")
directory<-file.path("data","diagnostics","weather-core-index-recovery")
dir.create(directory,recursive=TRUE,showWarnings=FALSE)
stamps<-c("2026092809","2026100406","2026100509")
reports<-list()
for(stamp in stamps) {
  calls<-bytes<-0; started<-proc.time()[["elapsed"]]
  get_range<-function(url,start,end,etag=NULL) {
    if(calls>=3L || end-start+1>1e6) stop("Audit transfer budget exceeded.")
    req<-weather_core_request(url) |>
      httr2::req_headers(Range=sprintf("bytes=%.0f-%.0f",start,end),`Accept-Encoding`="identity")
    if(!is.null(etag)) req<-httr2::req_headers(req,`If-Match`=etag)
    calls<<-calls+1L
    response<-httr2::req_perform(req); body<-httr2::resp_body_raw(response)
    bytes<<-bytes+length(body)
    attr(body,"object_size")<-weather_core_check_range(body,httr2::resp_status(response),
      httr2::resp_header(response,"Content-Range"),start,end)
    attr(body,"etag")<-httr2::resp_header(response,"ETag")
    body
  }
  base<-paste0("https://storage.googleapis.com/noaa-nws-ncep-core/grib/3hour/pgb/",
    substr(stamp,1,4),"/",substr(stamp,5,6),"/pgb.",stamp)
  row<-weather_core_recover_surface_pressure(base,stamp,directory,get_range)
  if(is.null(row)) stop("No validated candidate found in the bounded window for ",stamp)
  path<-file.path(directory,paste0("3hour-pgb-",stamp,"-PRES-surface.grb"))
  info<-terra::describe(path,print=FALSE)
  expected<-as.numeric(as.POSIXct(strptime(stamp,"%Y%m%d%H",tz="UTC")))
  stopifnot(any(grepl("GRIB_ELEMENT=PRES",info,fixed=TRUE)),
    any(grepl("GRIB_UNIT=[Pa]",info,fixed=TRUE)),
    any(grepl(paste0("GRIB_VALID_TIME=",sprintf("%.0f",expected)),info,fixed=TRUE)))
  weather_core_grid(path)
  before<-calls
  weather_core_recover_surface_pressure(base,stamp,directory,get_range)
  stopifnot(calls==before)
  reports[[stamp]]<-data.frame(stamp=stamp,status="PASS",requests=calls,bytes=bytes,
    elapsed_seconds=proc.time()[["elapsed"]]-started,cache_check_requests=calls-before)
  utils::write.csv(do.call(rbind,reports),file.path(directory,"recovery-test.csv"),row.names=FALSE)
}
print(do.call(rbind,reports),row.names=FALSE)
message("Selected-field recovery and cache verification complete; no site rendering or S3 sync.")
