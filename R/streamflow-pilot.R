# Isolated USGS daily-mean streamflow assessment. No site/daily-runner writes.
streamflow_sites <- function() data.frame(
  id=paste0("USGS-",c("09380000","09402000","09506000","09498500","09448500","09471000",
    "08279500","08313000","08330000","09355500","08378500","09430500")),
  state=rep(c("AZ","NM"),each=6),
  river=c("Colorado","Little Colorado","Verde","Salt","Gila","San Pedro",
    "Rio Grande (Embudo)","Rio Grande (Otowi)","Rio Grande (Albuquerque)","San Juan","Pecos","Gila"),
  stringsAsFactors=FALSE)

streamflow_text <- function(x) if(is.null(x)||!length(x))"" else paste(unlist(x),collapse="; ")
streamflow_request <- function(collection, params=list(), cache_dir="data/raw/streamflow-pilot",
    download=TRUE, refresh=FALSE, metrics=new.env(parent=emptyenv()), request_limit=60L) {
  if(!grepl("^(latest-daily|daily|time-series-metadata|monitoring-locations)(/USGS-[0-9]+)?$",collection))stop("Unsupported USGS collection.")
  dir.create(cache_dir,recursive=TRUE,showWarnings=FALSE)
  base<-"https://api.waterdata.usgs.gov/ogcapi/v1/collections/"
  endpoint<-paste0(base,if(grepl("/",collection,fixed=TRUE))sub("/","/items/",collection,fixed=TRUE)else paste0(collection,"/items"))
  url<-httr2::request(endpoint)
  url<-do.call(httr2::req_url_query,c(list(url),c(list(f="json"),params)))$url
  features<-list();seen<-character();pages<-0L
  if(is.null(metrics$rows))metrics$rows<-list()
  if(is.null(metrics$requests))metrics$requests<-0L
  repeat {
    if(url %in% seen || pages>=10L)stop("USGS pagination repeated or exceeded the 10-page pilot bound.")
    if(!startsWith(url,paste0(endpoint,"?")) && !identical(url,endpoint))stop("Unexpected USGS pagination origin.")
    seen<-c(seen,url);pages<-pages+1L
    key<-digest::digest(url,algo="sha256",serialize=FALSE)
    file<-file.path(cache_dir,paste0(key,".json"));marker<-paste0(file,".rds")
    meta<-if(file.exists(marker))tryCatch(readRDS(marker),error=function(e)NULL)else NULL
    reused<-!refresh&&file.exists(file)&&is.list(meta)&&identical(meta$sha256,digest::digest(file=file,algo="sha256",serialize=FALSE))
    started<-Sys.time()
    if(!reused) {
      if(!download)stop("Verified USGS cache is missing; allow downloads for the initial build.")
      if(metrics$requests>=request_limit)stop("Pilot request budget reached; rerun to reuse verified cache.")
      remaining<-if(is.null(metrics$deadline))45 else as.numeric(difftime(metrics$deadline,Sys.time(),units="secs"))
      if(remaining<=0)stop("Streamflow source-time budget reached; retain verified data and retry later.")
      metrics$requests<-metrics$requests+1L
      message("USGS ",collection," page ",pages," (request ",metrics$requests,"/",request_limit,")")
      req<-httr2::request(url)|>httr2::req_timeout(min(45,remaining))|>httr2::req_user_agent("SWClimateWatch-local-streamflow-pilot")
      api_key<-Sys.getenv("USGS_API_KEY","")
      if(nzchar(api_key))req<-httr2::req_headers(req,`X-Api-Key`=api_key)
      response<-httr2::req_perform(req);body<-httr2::resp_body_raw(response)
      parsed<-jsonlite::fromJSON(rawToChar(body),simplifyVector=FALSE)
      if(!is.list(parsed)||is.null(parsed$type)||!parsed$type%in%c("FeatureCollection","Feature"))stop("USGS response is not GeoJSON.")
      writeBin(body,file)
      meta<-list(sha256=digest::digest(file=file,algo="sha256",serialize=FALSE),url=url,
        fetched_utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"))
      saveRDS(meta,marker)
    }
    x<-jsonlite::read_json(file)
    part<-if(identical(x$type,"Feature"))list(x)else x$features
    if(!is.list(part))stop("USGS response lacks a feature list.")
    features<-c(features,part)
    metrics$rows[[length(metrics$rows)+1L]]<-data.frame(collection=collection,page=pages,reused=reused,
      transferred_bytes=if(reused)0 else file.info(file)$size,cache_bytes=file.info(file)$size,
      features=length(part),seconds=as.numeric(difftime(Sys.time(),started,units="secs")),fetched_utc=meta$fetched_utc)
    next_link<-Filter(function(l)identical(l$rel,"next"),x$links)
    if(!length(next_link)||!length(part))break
    if(length(next_link)!=1L)stop("Ambiguous USGS next-page link.")
    url<-next_link[[1]]$href
  }
  features
}

streamflow_rows <- function(features, expected_id=NULL, series=NULL) {
  rows<-lapply(features,function(f) {
    p<-f$properties
    if(!identical(p$parameter_code,"00060")||!identical(p$statistic_id,"00003")||!identical(p$unit_of_measure,"ft^3/s"))
      stop("USGS returned an unexpected parameter, statistic or unit.")
    if(!is.null(expected_id)&&!identical(p$monitoring_location_id,expected_id))stop("Gauge filter mismatch.")
    if(!is.null(series)&&!identical(p$time_series_id,series))stop("Time-series filter mismatch.")
    date<-streamflow_text(p$time)
    if(!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$",date)||is.na(as.Date(date)))stop("Invalid daily observation date.")
    raw<-streamflow_text(p$value)
    number<-if(grepl("^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$",raw))as.numeric(raw)else NA_real_
    quality<-if(!is.finite(number))"Nonnumeric / unavailable" else if(number<0)"Negative flow: review" else "Numeric observation"
    if(!is.finite(number)||number<0)number<-NA_real_
    coord<-unlist(f$geometry$coordinates)
    data.frame(id=streamflow_text(p$monitoring_location_id),series=streamflow_text(p$time_series_id),date=date,
      cfs=number,raw_value=raw,approval=streamflow_text(p$approval_status),qualifier=streamflow_text(p$qualifier),
      quality=quality,last_modified=streamflow_text(p$last_modified),
      lon=if(length(coord)>=2)coord[1]else NA_real_,lat=if(length(coord)>=2)coord[2]else NA_real_,stringsAsFactors=FALSE)
  })
  if(!length(rows))return(data.frame(id=character(),series=character(),date=character(),cfs=numeric(),raw_value=character(),
    approval=character(),qualifier=character(),quality=character(),last_modified=character(),lon=numeric(),lat=numeric()))
  do.call(rbind,rows)
}

streamflow_calendar <- function(rows, start, end) {
  dates<-as.character(seq(as.Date(start),as.Date(end),by="day"))
  result<-data.frame(date=dates,cfs=NA_real_,raw_value="",approval="",qualifier="",quality="Missing",reported=FALSE)
  for(date in intersect(dates,rows$date)) {
    indices<-which(rows$date==date);i<-match(date,dates);r<-rows[indices[1],]
    fields<-c("cfs","raw_value","approval","qualifier","quality")
    result[i,fields]<-r[fields];result$reported[i]<-TRUE
    if(nrow(unique(rows[indices,c("cfs","raw_value","approval","qualifier")]))>1L) {
      result$cfs[i]<-NA_real_;result$quality[i]<-"Conflicting daily rows: review"
    }
  }
  result
}

streamflow_summary <- function(data, cutoff) {
  report<-which(data$reported);last<-if(length(report))max(report)else NA_integer_
  date<-if(is.na(last))""else data$date[last];value<-if(is.na(last))NA_real_ else data$cfs[last]
  lag<-if(nzchar(date))as.integer(as.Date(cutoff)-as.Date(date))else NA_integer_
  freshness<-if(is.na(lag))"Unavailable"else if(lag<=3)"Recent"else if(lag<=7)"Delayed"else "Stale"
  mean_for<-function(n) {x<-tail(data$cfs,n);if(length(x)==n&&all(is.finite(x)))mean(x)else NA_real_}
  list(latest_date=date,latest_cfs=value,lag_days=lag,freshness=freshness,
    approval=if(is.na(last))""else data$approval[last],qualifier=if(is.na(last))""else data$qualifier[last],
    latest_quality=if(is.na(last))"No reports in window"else data$quality[last],
    mean_7day_cfs=mean_for(7L),mean_30day_cfs=mean_for(30L),
    numeric_days=sum(is.finite(data$cfs)),reported_days=sum(data$reported),window_days=nrow(data))
}

build_streamflow_pilot <- function(cutoff=Sys.Date()-1L, refresh=FALSE, download=TRUE,
    sites=streamflow_sites(),output_dir="data/diagnostics/streamflow-pilot",daily_rows_provider=NULL,
    metrics=new.env(parent=emptyenv()),request_limit=60L) {
  started<-Sys.time();cutoff<-as.Date(cutoff)
  if(length(cutoff)!=1L||is.na(cutoff))stop("Invalid streamflow cutoff.")
  if(!grepl("^data/diagnostics/[A-Za-z0-9_/-]+$",output_dir)||any(strsplit(output_dir,"/",fixed=TRUE)[[1]]%in%c(".","..")))
    stop("Pilot output must be a plain path under data/diagnostics.")
  if(!nrow(sites)||anyDuplicated(sites$id)||any(!grepl("^USGS-[0-9]+$",sites$id)))stop("Invalid pilot gauge selection.")
  start<-cutoff-89L;root<-output_dir
  dir.create(file.path(root,"hydrographs"),recursive=TRUE,showWarnings=FALSE)
  request<-function(collection,params=list(),refresh_override=refresh)streamflow_request(collection,params,
    refresh=refresh_override,download=download,metrics=metrics,request_limit=request_limit)
  coverage<-list();inventory<-list()
  for(state in c(AZ="04",NM="35")) {
    label<-if(state=="04")"AZ"else"NM"
    f<-request("latest-daily",list(state_code=state,site_type_code="ST",parameter_code="00060",statistic_id="00003",limit=5000L))
    rows<-streamflow_rows(f);rows$state<-label;inventory[[label]]<-rows
    recent<-as.Date(rows$date)>=cutoff-6L & as.Date(rows$date)<=cutoff
    coverage[[label]]<-data.frame(state=label,series=nrow(rows),gauges_with_any_latest_daily=length(unique(rows$id)),
      gauges_reported_in_last_7days=length(unique(rows$id[recent])),
      gauges_with_numeric_flow_in_last_7days=length(unique(rows$id[recent&is.finite(rows$cfs)])))
  }
  selected<-sites;gauges<-list();failures<-list()
  for(i in seq_len(nrow(selected))) {
    id<-selected$id[i];message("Pilot gauge ",i,"/",nrow(selected),": ",id)
    gauge<-tryCatch({
      loc<-request(paste0("monitoring-locations/",id))
      if(length(loc)!=1L||!identical(loc[[1]]$id,id))stop("Gauge metadata is missing or ambiguous.")
      p<-loc[[1]]$properties;coords<-unlist(loc[[1]]$geometry$coordinates)
      expected_state<-if(selected$state[i]=="AZ")"04"else"35"
      if(!identical(p$state_code,expected_state)||!identical(p$site_type_code,"ST")||length(coords)!=2L||any(!is.finite(coords)))
        stop("Gauge is not a located stream site in its expected state.")
      meta<-request("time-series-metadata",list(monitoring_location_id=id,parameter_code="00060",statistic_id="00003",limit=1000L))
      primary<-Filter(function(f)identical(f$properties$statistic_id,"00003")&&
        identical(f$properties$unit_of_measure,"ft^3/s")&&identical(f$properties$computation_period_identifier,"Daily")&&
        identical(f$properties$primary,"Primary"),meta)
      if(length(primary)>1L)primary<-Filter(function(f){
        last<-as.Date(substr(streamflow_text(f$properties$end),1,10));first<-as.Date(substr(streamflow_text(f$properties$begin),1,10))
        !is.na(last)&&!is.na(first)&&last>=cutoff-7L&&first<=cutoff
      },primary)
      if(length(primary)!=1L)stop("Expected exactly one current primary daily-mean discharge series.")
      series<-primary[[1]]$id
      if(is.null(daily_rows_provider)) {
        f<-request("daily",list(monitoring_location_id=id,time_series_id=series,parameter_code="00060",statistic_id="00003",
          datetime=paste(start,cutoff+1L,sep="/"),limit=1000L))
        rows<-streamflow_rows(f,id,series)
      } else rows<-daily_rows_provider(id,series,start,cutoff,request)
      data<-streamflow_calendar(rows,start,cutoff)
      write.csv(data,file.path(root,"hydrographs",paste0(id,".csv")),row.names=FALSE,na="")
      jsonlite::write_json(list(id=id,rows=data),file.path(root,"hydrographs",paste0(id,".json")),
        auto_unbox=TRUE,dataframe="rows",na="null",digits=10)
      c(list(id=id,series_id=series,name=p$monitoring_location_name,state=selected$state[i],river=selected$river[i],lat=coords[2],lon=coords[1],
        source_refresh_status=if(is.null(attr(rows,"refresh_status")))"VERIFIED_SOURCE" else attr(rows,"refresh_status"),
        time_zone=streamflow_text(p$time_zone_abbreviation),drainage_sqmi=p$drainage_area,
        record_begin=primary[[1]]$properties$begin,record_end=primary[[1]]$properties$end,
        record_note="Observation metadata bounds are not the reference-year bounds of the published historical statistics.",
        usgs_url=paste0("https://waterdata.usgs.gov/monitoring-location/",id,"/"),
        hydrograph=paste0("hydrographs/",id,".json"),csv=paste0("hydrographs/",id,".csv")),streamflow_summary(data,cutoff))
    },error=function(e){failures[[length(failures)+1L]]<<-data.frame(id=id,state=selected$state[i],note=conditionMessage(e));NULL})
    if(!is.null(gauge))gauges[[length(gauges)+1L]]<-gauge
  }
  errors<-if(length(failures))do.call(rbind,failures)else data.frame(id=character(),state=character(),note=character())
  write.csv(errors,file.path(root,"unavailable-gauges.csv"),row.names=FALSE)
  if(!length(gauges))stop("No pilot gauges built; inspect unavailable-gauges.csv. Last viewer has not been replaced.")
  coverage<-do.call(rbind,coverage);inventory<-do.call(rbind,inventory)
  write.csv(coverage,file.path(root,"coverage.csv"),row.names=FALSE)
  write.csv(inventory,file.path(root,"source-inventory.csv"),row.names=FALSE,na="")
  requests<-do.call(rbind,metrics$rows);write.csv(requests,file.path(root,"requests.csv"),row.names=FALSE)
  assets<-"scripts/streamflow-assets"
  for(name in c("index.html","streamflow.css","streamflow.js","streamflow-model.js","streamflow-explorer-model.js"))
    if(!file.copy(file.path(assets,name),file.path(root,name),overwrite=TRUE))stop("Cannot stage pilot browser asset.")
  for(name in c("leaflet.js","leaflet.css","leaflet-package-LICENSE")) {
    src<-file.path("site/stations",name)
    if(!file.exists(src))src<-file.path(find.package("leaflet"),"htmlwidgets/lib/leaflet",name)
    if(!file.copy(src,file.path(root,name),overwrite=TRUE))stop("Missing Leaflet asset: ",name)
  }
  dir.create(file.path(root,"images"),showWarnings=FALSE)
  images<-list.files(file.path(find.package("leaflet"),"htmlwidgets/lib/leaflet/images"),full.names=TRUE)
  file.copy(images,file.path(root,"images"),overwrite=TRUE)
  payload<-list(pilot="swc-streamflow",schema_version=1L,cutoff=as.character(cutoff),start=as.character(start),
    built_utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),parameter="00060",statistic="00003",unit="ft^3/s",
    source_fetched_from=min(requests$fetched_utc),source_fetched_through=max(requests$fetched_utc),
    configured_gauges=nrow(selected),gauges=gauges,unavailable=errors,coverage=coverage)
  jsonlite::write_json(payload,file.path(root,"streamflow-data.json"),auto_unbox=TRUE,dataframe="rows",na="null",digits=10)
  viewer_files<-list.files(root,recursive=TRUE,full.names=TRUE)
  viewer_files<-viewer_files[grepl("[.](html|js|css|json|csv|png)$",viewer_files)]
  initial<-file.path(root,c("index.html","streamflow.css","streamflow.js","streamflow-model.js","streamflow-data.json","leaflet.js","leaflet.css"))
  workload<-data.frame(status=if(nrow(errors))"PARTIAL"else"READY",cutoff=as.character(cutoff),pilot_gauges=length(gauges),
    unavailable_gauges=nrow(errors),requests=sum(!requests$reused),reused=sum(requests$reused),
    transferred_bytes=sum(requests$transferred_bytes),source_cache_bytes=sum(requests$cache_bytes),
    initial_payload_bytes=sum(file.info(initial)$size),hydrograph_json_bytes=sum(file.info(list.files(file.path(root,"hydrographs"),pattern="json$",full.names=TRUE))$size),
    seconds=as.numeric(difftime(Sys.time(),started,units="secs")))
  write.csv(workload,file.path(root,"workload.csv"),row.names=FALSE)
  history_path<-file.path(root,"run-history.csv")
  history<-if(file.exists(history_path))read.csv(history_path,stringsAsFactors=FALSE)else workload[FALSE,]
  write.csv(rbind(history,workload),history_path,row.names=FALSE)
  print(coverage,row.names=FALSE);print(workload,row.names=FALSE)
  message("Local streamflow pilot ready: ",root,". No site, cron or S3 files changed.")
  invisible(list(directory=root,coverage=coverage,workload=workload,gauges=gauges))
}
