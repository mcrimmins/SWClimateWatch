# Isolated review adapter: verified existing PNGs only, no data requests.
stage_daily_explorer_weather_means_preview <- function(
    source_dir="data/diagnostics/daily-explorer",
    mean_dir="data/diagnostics/weather-period-means-pilot",
    weather_dir="data/diagnostics/weather-circulation-explorer-cache",
    output_dir="data/diagnostics/daily-explorer-weather-means") {
  permitted<-normalizePath("data/diagnostics",winslash="/",mustWork=TRUE)
  output<-normalizePath(output_dir,winslash="/",mustWork=FALSE)
  if(!startsWith(output,paste0(permitted,"/"))||identical(output,normalizePath(source_dir,winslash="/",mustWork=TRUE))||
      identical(output,normalizePath(mean_dir,winslash="/",mustWork=TRUE)))stop("Use a separate preview directory under data/diagnostics.")
  payload<-jsonlite::read_json(file.path(source_dir,"daily-data.json"))
  periods<-read.csv(file.path(mean_dir,"period-summary.csv"))
  if(!identical(sort(as.integer(periods$days)),c(1L,7L,30L))||length(unique(periods$end))!=1L||
      any(as.Date(periods$end)-as.Date(periods$start)+1!=periods$days))stop("Invalid complete period suite.")
  end<-periods$end[1]
  if(!end%in%vapply(payload$days,`[[`,character(1),"date"))stop("No matching PRISM day for this weather pilot.")
  # Preserve September and cross-year browsing, ending at the reviewed window.
  payload$days<-Filter(function(day)day$date<=end,payload$days)
  payload$latest_cached_date<-end;payload$publication_mode<-FALSE
  payload$circulation_preview<-TRUE;payload$circulation_period_means_preview<-TRUE
  payload$local_review_note<-paste0("Local review: 7-/30-day weather means end ",end,
    ". Other endpoints show an unavailable notice. Daily weather coverage follows the local cache; no downloads or publication.")
  dir.create(file.path(output_dir,"maps"),recursive=TRUE,showWarnings=FALSE)
  copy<-function(from,to) {
    if(!file.exists(from)||file.info(from)$size<=0)stop("Missing preview resource: ",from)
    dir.create(dirname(to),recursive=TRUE,showWarnings=FALSE)
    if(file.exists(to)&&identical(unname(tools::md5sum(from)),unname(tools::md5sum(to))))return(invisible())
    if(!file.copy(from,to,overwrite=TRUE))stop("Could not copy preview resource.")
  }
  checked_maps<-function(days) {
    directory<-file.path(mean_dir,paste0(days,"day"))
    base<-file.path(directory,c(paste0(c("height500-","pwat-","jet250-"),days,"day.png"),"mean-native-grid.rds"))
    marker<-readRDS(file.path(directory,"complete.rds"))
    overlay<-file.path(directory,paste0("pwat-overlay-",days,"day.png"));over<-readRDS(paste0(overlay,".rds"))
    if(!all(file.exists(c(base,overlay)))||!identical(marker$md5,unname(tools::md5sum(base)))||
        !identical(over$md5,unname(tools::md5sum(overlay))))stop("Weather period output checksum mismatch; rebuild the period suite.")
    c(height500=base[1],jet250=base[3],moisture=overlay)
  }
  means<-lapply(c(7L,30L),function(days) {
    paths<-checked_maps(days)
    images<-setNames(paste0("circulation/means/",end,"-",days,"day-",names(paths),".png"),names(paths))
    for(field in names(paths))copy(paths[[field]],file.path(output_dir,images[[field]]))
    list(days=days,start=as.character(as.Date(end)-days+1),end=end,images=as.list(images))
  })
  current<-checked_maps(1L)
  daily<-lapply(payload$days,function(day) {
    date<-day$date;paths<-file.path(weather_dir,date,paste0(c("height500","jet250","moisture"),".png"))
    if(date==end)paths<-unname(current)
    if(!all(file.exists(paths)))return(list(date=date,status="unavailable"))
    fields<-c("height500","jet250","moisture")
    images<-setNames(paste0("circulation/maps/",date,"-",fields,".png"),fields)
    for(i in seq_along(paths))copy(paths[i],file.path(output_dir,images[i]))
    list(date=date,status="available",images=as.list(images))
  })
  images<-unlist(lapply(payload$days,function(day)unlist(day$images,use.names=FALSE)),use.names=FALSE)
  if(any(!grepl("^maps/[0-9]{4}-[0-9]{2}-[0-9]{2}-(pcpn|maxt|mint|tmean)-(observed|departure)\\.png$",images)))stop("Unexpected PRISM image reference.")
  for(image in images)copy(file.path(source_dir,image),file.path(output_dir,image))
  for(asset in c("index.html","explorer.js","explorer.css"))copy(file.path("scripts/daily-explorer-assets",asset),file.path(output_dir,asset))
  html<-readLines(file.path(output_dir,"index.html"),warn=FALSE)
  html<-sub('<details id="circulation-panel" class="card circulation" hidden>',
    '<details id="circulation-panel" class="card circulation" open hidden>',html,fixed=TRUE)
  writeLines(html,file.path(output_dir,"index.html"),useBytes=TRUE)
  jsonlite::write_json(list(schema_version=1L,source="NOAA CPC CORe",days=daily),file.path(output_dir,"circulation-manifest.json"),auto_unbox=TRUE)
  jsonlite::write_json(list(schema_version=1L,periods=means),file.path(output_dir,"circulation-means-manifest.json"),auto_unbox=TRUE)
  jsonlite::write_json(payload,file.path(output_dir,"daily-data.json"),auto_unbox=TRUE,digits=NA)
  validate_daily_explorer_assets(output_dir)
  summary<-data.frame(prism_dates=length(payload$days),daily_weather_dates=sum(vapply(daily,function(d)d$status=="available",logical(1))),
    mean_end=end,mean_periods=2L,mean_maps=6L,requests=0L)
  write.csv(summary,file.path(output_dir,"preview-summary.csv"),row.names=FALSE)
  print(summary,row.names=FALSE);message("Local Daily Explorer weather means ready: ",output_dir)
  invisible(summary)
}
