# USGS approved day-of-year percentiles, matched to the primary daily series.
streamflow_statistics_request <- function(id, series, download=TRUE, refresh=FALSE,
    cache_dir="data/raw/streamflow-statistics") {
  if(!grepl("^USGS-[0-9]+$",id)||!grepl("^[a-f0-9]+$",series))stop("Invalid statistics identity.")
  endpoint<-"https://api.waterdata.usgs.gov/statistics/v0/observationNormals"
  params<-list(monitoring_location_id=id,parent_time_series_id=series,parameter_code="00060",
    normal_type="DOY",computation_type="percentile",approval_status="approved",mime_type="application/json",page_size=10000L)
  dir.create(cache_dir,recursive=TRUE,showWarnings=FALSE)
  features<-list();seen<-character();metrics<-list();next_token<-NULL
  repeat {
    query<-params;if(!is.null(next_token))query$next_token<-next_token
    url<-do.call(httr2::req_url_query,c(list(httr2::request(endpoint)),query))$url
    if(url%in%seen||length(seen)>=10L)stop("Statistics pagination repeated or exceeded its bound.")
    seen<-c(seen,url);key<-digest::digest(url,algo="sha256",serialize=FALSE)
    file<-file.path(cache_dir,paste0(key,".json"));marker<-paste0(file,".rds")
    meta<-if(file.exists(marker))tryCatch(readRDS(marker),error=function(e)NULL)else NULL
    reused<-!refresh&&file.exists(file)&&is.list(meta)&&identical(meta$sha256,digest::digest(file=file,algo="sha256",serialize=FALSE))
    started<-Sys.time()
    if(!reused) {
      if(!download)stop("Verified historical-statistics cache is unavailable; allow the initial statistics download.")
      message("USGS historical percentiles: ",id," page ",length(seen))
      req<-httr2::request(url)|>httr2::req_timeout(45)|>httr2::req_user_agent("SWClimateWatch-local-streamflow-statistics")
      key_header<-Sys.getenv("USGS_API_KEY","")
      if(nzchar(key_header))req<-httr2::req_headers(req,`X-Api-Key`=key_header)
      response<-httr2::req_perform(req);body<-httr2::resp_body_raw(response)
      parsed<-jsonlite::fromJSON(rawToChar(body),simplifyVector=FALSE)
      if(!identical(parsed$type,"FeatureCollection")||!is.list(parsed$features))stop("Invalid historical-statistics response.")
      writeBin(body,file);meta<-list(sha256=digest::digest(file=file,algo="sha256",serialize=FALSE),url=url,
        fetched_utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"));saveRDS(meta,marker)
    }
    x<-jsonlite::read_json(file)
    features<-c(features,x$features)
    metrics[[length(metrics)+1L]]<-data.frame(id=id,reused=reused,cache_bytes=file.info(file)$size,
      transferred_bytes=if(reused)0 else file.info(file)$size,seconds=as.numeric(difftime(Sys.time(),started,units="secs")),
      fetched_utc=meta$fetched_utc)
    next_token<-x[["next"]]
    if(is.null(next_token)||!length(next_token)||identical(next_token,""))break
    if(!is.character(next_token)||length(next_token)!=1L||grepl("^https?://",next_token))
      stop("Unexpected statistics pagination token; no alternate URL followed.")
  }
  list(features=features,metrics=do.call(rbind,metrics))
}

streamflow_normals <- function(features,id,series,min_samples=30L) {
  days<-format(seq(as.Date("2000-01-01"),as.Date("2000-12-31"),by="day"),"%m-%d")
  result<-data.frame(month_day=days,p10=NA_real_,p25=NA_real_,p50=NA_real_,p75=NA_real_,p90=NA_real_,
    sample_count=NA_integer_,supported=FALSE,note="No matching approved historical percentiles")
  seen<-character()
  for(f in features) {
    if(!identical(f$properties$monitoring_location_id,id))stop("Statistics gauge identity mismatch.")
    for(d in f$properties$data) {
      if(!identical(d$parent_time_series_id,series))stop("Statistics primary-series identity mismatch.")
      if(!identical(d$parameter_code,"00060")||!identical(d$unit_of_measure,"ft^3/s")||
          (!is.null(d$parent_statistic_id)&&!identical(d$parent_statistic_id,"00003")))stop("Statistics parameter/unit/statistic mismatch.")
      for(v in d$values) {
        if(!identical(v$time_of_year_type,"day_of_year")||!identical(v$computation,"percentile"))next
        day<-v$time_of_year;i<-match(day,days)
        if(is.na(i))stop("Invalid historical calendar day.")
        if(day%in%seen)stop("Duplicate historical day in primary-series statistics.")
        seen<-c(seen,day)
        n<-v$sample_count
        if(length(n)!=1L||!is.finite(n)||n<0||n!=as.integer(n))stop("Invalid historical sample count.")
        result$sample_count[i]<-as.integer(n)
        if(tolower(streamflow_text(v$approval_status))!="approved") {result$note[i]<-"Historical statistics are not approved";next}
        percent<-as.character(unlist(v$percentiles));raw<-as.character(unlist(v$values))
        if(length(raw)!=length(percent)||anyDuplicated(percent))stop("Invalid historical percentile vector.")
        wanted<-c("10","25","50","75","90");index<-match(wanted,percent)
        values<-suppressWarnings(as.numeric(raw[index]))
        if(anyNA(index)||any(!is.finite(values))||any(values<0)||is.unsorted(values,strictly=FALSE)) {
          result$note[i]<-"Missing, negative or unordered historical thresholds";next
        }
        if(n<min_samples) {result$note[i]<-paste("Fewer than",min_samples,"approved values for this calendar day");next}
        result[i,c("p10","p25","p50","p75","p90")]<-as.list(values)
        result$supported[i]<-TRUE;result$note[i]<-"USGS available approved record; reference year bounds not supplied"
      }
    }
  }
  result
}

streamflow_historical_category <- function(value,normal) {
  if(!is.finite(value))return("Unavailable")
  if(nrow(normal)!=1L||!isTRUE(normal$supported))return("History unavailable")
  q<-unlist(normal[c("p10","p25","p50","p75","p90")],use.names=FALSE)
  if(sum(q==value)>1L)return("Tied thresholds")
  if(value<q[1])"Below 10th" else if(value<q[2])"10th\u201325th" else if(value<=q[4])"25th\u201375th" else if(value<=q[5])"75th\u201390th" else "Above 90th"
}

add_streamflow_statistics <- function(directory="data/diagnostics/streamflow-pilot",download=TRUE,refresh=FALSE) {
  started<-Sys.time();payload<-file.path(directory,"streamflow-data.json");p<-jsonlite::read_json(payload)
  if(!identical(p$pilot,"swc-streamflow"))stop("Not a streamflow pilot release.")
  dir.create(file.path(directory,"normals"),showWarnings=FALSE)
  availability<-list();metrics<-list()
  for(i in seq_along(p$gauges)) {
    g<-p$gauges[[i]];note<-"";source_time<-"";normal<-NULL
    tryCatch({
      response<-streamflow_statistics_request(g$id,g$series_id,download=download,refresh=refresh)
      metrics[[length(metrics)+1L]]<-response$metrics;source_time<-max(response$metrics$fetched_utc)
      normal<-streamflow_normals(response$features,g$id,g$series_id)
    },error=function(e)note<<-conditionMessage(e))
    if(is.null(normal)) {
      normal<-streamflow_normals(list(),g$id,g$series_id)
      normal$note<-if(nzchar(note))note else "Statistics unavailable"
    }
    file<-file.path(directory,g$hydrograph);data<-jsonlite::read_json(file,simplifyVector=TRUE)$rows
    matched<-match(format(as.Date(data$date),"%m-%d"),normal$month_day)
    joined<-normal[matched,c("p10","p25","p50","p75","p90","sample_count","supported","note")]
    names(joined)<-c("p10","p25","p50","p75","p90","sample_count","history_supported","history_note")
    data<-cbind(data,joined)
    # Repeated augmentation must not duplicate columns when called on an
    # already augmented pilot; the base build normally resets the rows first.
    data<-data[,!duplicated(names(data),fromLast=TRUE),drop=FALSE]
    jsonlite::write_json(list(id=g$id,rows=data),file,auto_unbox=TRUE,dataframe="rows",na="null",digits=10)
    write.csv(data,file.path(directory,g$csv),row.names=FALSE,na="")
    write.csv(normal,file.path(directory,"normals",paste0(g$id,".csv")),row.names=FALSE,na="")
    latest<-normal[normal$month_day==substr(g$latest_date,6,10),,drop=FALSE]
    g$historical_category<-streamflow_historical_category(if(is.null(g$latest_cfs))NA_real_ else g$latest_cfs,latest)
    g$historical_samples<-if(nrow(latest)==1L)latest$sample_count else NA_integer_
    g$historical_note<-if(nrow(latest)==1L)latest$note else "No matched observation day"
    g$historical_reference<-"USGS available approved period of record; exact reference years not supplied by Statistics API"
    g$statistics_fetched_utc<-source_time
    p$gauges[[i]]<-g
    ns<-normal$sample_count[normal$supported]
    availability[[length(availability)+1L]]<-data.frame(id=g$id,state=g$state,name=g$name,
      days_returned=sum(!is.na(normal$sample_count)),days_supported=sum(normal$supported),
      minimum_supported_samples=if(length(ns))min(ns)else NA_integer_,maximum_supported_samples=if(length(ns))max(ns)else NA_integer_,
      latest_day_samples=g$historical_samples,latest_category=g$historical_category,note=note,source_fetched_utc=source_time)
  }
  p$historical_statistics<-list(source="USGS Statistics API observationNormals",minimum_samples=30L,
    reference="Available approved record, not a fixed 1991-2020 baseline; reference year bounds not supplied",
    category_note="Published daily percentile thresholds give categories, not exact percentile ranks or flood categories.")
  jsonlite::write_json(p,payload,auto_unbox=TRUE,na="null",digits=10)
  availability<-do.call(rbind,availability)
  write.csv(availability,file.path(directory,"statistics-availability.csv"),row.names=FALSE,na="")
  metrics<-if(length(metrics))do.call(rbind,metrics)else data.frame(id=character(),reused=logical(),cache_bytes=numeric(),transferred_bytes=numeric(),seconds=numeric(),fetched_utc=character())
  write.csv(metrics,file.path(directory,"statistics-requests.csv"),row.names=FALSE)
  summary<-data.frame(gauges=nrow(availability),gauges_with_supported_days=sum(availability$days_supported>0),
    gauges_with_latest_category=sum(!availability$latest_category%in%c("Unavailable","History unavailable")),
    requests=sum(!metrics$reused),reused=sum(metrics$reused),transferred_bytes=sum(metrics$transferred_bytes),
    cache_bytes=sum(metrics$cache_bytes),
    initial_payload_bytes=sum(file.info(file.path(directory,c("index.html","streamflow.css","streamflow.js","streamflow-model.js","streamflow-data.json","leaflet.js","leaflet.css")))$size),
    hydrograph_json_bytes=sum(file.info(list.files(file.path(directory,"hydrographs"),pattern="json$",full.names=TRUE))$size),
    seconds=as.numeric(difftime(Sys.time(),started,units="secs")))
  write.csv(summary,file.path(directory,"statistics-workload.csv"),row.names=FALSE)
  print(availability[,c("id","days_supported","latest_day_samples","latest_category")],row.names=FALSE)
  print(summary,row.names=FALSE)
  invisible(list(availability=availability,workload=summary))
}
