# Isolated 32-gauge eligibility and rolling revision-window benchmark.
streamflow_network_sites <- function() {
  base<-streamflow_sites();base$role<-"Existing pilot gauge"
  extra<-data.frame(id=paste0("USGS-",c("09415000","09504500","09505800","09490500","09494000","09499000","09444500","09480500","09482500","09512500",
    "08284100","08324000","09364010","08353000","08354900","08361000","08383500","08406500","07221500","09444000")),
    state=rep(c("AZ","NM"),each=10),
    river=c("Virgin (Littlefield)","Oak Creek (Cornville)","West Clear Creek","Black River","White River","Tonto Creek",
      "San Francisco (Clifton)","Santa Cruz (Nogales)","Santa Cruz (Tucson)","Agua Fria (Mayer)",
      "Rio Chama (La Puente)","Jemez","Animas (Aztec)","Rio Puerco","Rio Grande (San Acacia)","Rio Grande (Elephant Butte)",
      "Pecos (Puerto de Luna)","Pecos (Malaga)","Canadian (Sanchez)","San Francisco (Glenwood)"),
    role=c("Geographic gap","Verde tributary","Verde tributary","Salt headwaters","Salt headwaters","Salt tributary",
      "Eastern basin coverage","Southern basin coverage","Southern basin coverage","Central basin coverage",
      "Northern tributary","Northern tributary","Northern tributary","Middle basin tributary","Lower mainstem",
      "Managed-release context","Middle Pecos","Lower Pecos","Northeast coverage","Southwest tributary"))
  x<-rbind(base,extra);x$management_note<-"Regulation/diversion review pending; do not interpret percentile as climate attribution"
  x$management_note[x$id%in%paste0("USGS-",c("09380000","09355500","08361000"))]<-"Downstream of major dam; managed-flow context"
  x
}

streamflow_merge_window <- function(old,new,start,end,retain_start) {
  # A successful response replaces its entire interval, including days absent
  # from the new response. Removed/revised observations must not survive as old data.
  old<-old[old$date<as.character(start)|old$date>as.character(end),,drop=FALSE]
  new<-new[new$date>=as.character(start)&new$date<=as.character(end),,drop=FALSE]
  rows<-rbind(old,new)
  rows<-rows[rows$date>=as.character(retain_start)&rows$date<=as.character(end),,drop=FALSE]
  rows[order(rows$date),,drop=FALSE]
}

streamflow_network_provider <- function(state_dir,mode,download,events) {
  dir.create(state_dir,recursive=TRUE,showWarnings=FALSE)
  function(id,series,start,cutoff,request) {
    file<-file.path(state_dir,paste0(id,".rds"));marker<-paste0(file,".sha256")
    state<-NULL
    if(file.exists(file)&&file.exists(marker)) {
      hash<-readLines(marker,warn=FALSE)
      if(length(hash)==1L&&identical(hash,digest::digest(file=file,algo="sha256",serialize=FALSE)))
        state<-tryCatch(readRDS(file),error=function(e)NULL)
    }
    through<-tryCatch(as.Date(state$through),error=function(e)as.Date(NA))
    valid<-is.list(state)&&identical(state$id,id)&&identical(state$series,series)&&is.data.frame(state$rows)&&
      all(c("id","series","date","cfs","raw_value","approval","qualifier","quality","last_modified","lon","lat")%in%names(state$rows))&&
      length(through)==1L&&!is.na(through)&&through<=cutoff&&through>=start
    old_through<-if(valid)state$through else ""
    if(valid && (any(state$rows$id!=id)||any(state$rows$series!=series)))stop("Processed state identity mismatch.")
    from<-if(valid)max(start,min(cutoff-13L,as.Date(state$through)+1L))else start
    query<-list(monitoring_location_id=id,time_series_id=series,parameter_code="00060",statistic_id="00003",
      datetime=paste(from,cutoff+1L,sep="/"),limit=1000L)
    old<-if(valid)state$rows else streamflow_rows(list())
    reason<-"";success<-FALSE
    rows<-tryCatch({
      # Live incremental runs always recheck the revision overlap. Cache replay
      # is a separate, explicitly labeled offline timing, never a daily-fetch benchmark.
      f<-request("daily",query,refresh_override=mode=="incremental_live"&&download)
      new<-streamflow_rows(f,id,series)
      rows<-streamflow_merge_window(old,new,from,cutoff,start)
      success<-TRUE;rows
    },error=function(e){reason<<-conditionMessage(e);if(!valid)stop(e);old[old$date>=as.character(start)&old$date<=as.character(cutoff),,drop=FALSE]})
    changed<-0L
    if(success) {
      days<-union(old$date,rows$date)
      signature<-function(d,x){y<-x[x$date==d,c("cfs","raw_value","approval","qualifier","quality")];rownames(y)<-NULL;digest::digest(y,algo="sha256")}
      changed<-sum(vapply(days,function(d)!identical(signature(d,old),signature(d,rows)),logical(1)))
      state<-list(schema_version=1L,id=id,series=series,through=as.character(cutoff),rows=rows,
        refreshed_utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"))
      # Write a fresh state/checksum pair. A partial write cannot be reused.
      saveRDS(state,file);writeLines(digest::digest(file=file,algo="sha256",serialize=FALSE),marker)
    }
    events$rows[[length(events$rows)+1L]]<-data.frame(id=id,mode=mode,query_start=as.character(from),query_end=as.character(cutoff),
      query_days=as.integer(cutoff-from)+1L,bootstrap=!valid,status=if(success)"UPDATED"else"STALE_RETAINED",
      old_through=old_through,changed_dates=changed,note=reason)
    attr(rows,"refresh_status")<-if(success)"VERIFIED_SOURCE"else"STALE_RETAINED"
    rows
  }
}

streamflow_network_eligibility <- function(directory,sites,events) {
  p<-jsonlite::read_json(file.path(directory,"streamflow-data.json"))
  availability<-read.csv(file.path(directory,"statistics-availability.csv"),stringsAsFactors=FALSE)
  failed<-read.csv(file.path(directory,"unavailable-gauges.csv"),stringsAsFactors=FALSE)
  output<-lapply(seq_len(nrow(sites)),function(i) {
    s<-sites[i,];g<-Filter(function(g)identical(g$id,s$id),p$gauges)
    a<-availability[availability$id==s$id,,drop=FALSE];e<-events[events$id==s$id,,drop=FALSE]
    status<-"METADATA_OR_SOURCE_UNAVAILABLE";reason<-paste(failed$note[failed$id==s$id],collapse=" | ")
    latest<-"";samples<-NA_integer_;days<-0L;numeric<-0L;name<-s$river
    if(length(g)==1L) {
      g<-g[[1]];name<-g$name;latest<-g$latest_date;samples<-if(is.null(g$historical_samples))NA_integer_ else g$historical_samples
      days<-if(nrow(a))a$days_supported[1]else 0L;numeric<-g$numeric_days
      if(nrow(e)&&any(e$status!="UPDATED")) {status<-"STALE_RETAINED";reason<-paste(e$note,collapse=" | ")}
      else if(!identical(g$freshness,"Recent")||is.null(g$latest_cfs)) {status<-"STALE_OR_NONNUMERIC";reason<-"A recent numeric daily observation is unavailable"}
      else if(days<330L||is.na(samples)||samples<30L) {status<-"OBSERVATIONS_ONLY";reason<-"Require 330+ supported calendar days and 30+ approved values on the displayed day"}
      else {status<-"ELIGIBLE";reason<-"Primary-series, recent-flow and historical sample checks passed"}
    }
    data.frame(id=s$id,state=s$state,name=name,river=s$river,role=s$role,status=status,reason=reason,
      latest_date=latest,latest_day_samples=samples,supported_days=days,numeric_days_in_window=numeric,
      management_note=s$management_note,stringsAsFactors=FALSE)
  })
  do.call(rbind,output)
}

run_streamflow_network <- function(cutoff,mode=c("bootstrap","incremental_live","cache_replay"),download=TRUE,
    root="data/diagnostics/streamflow-network-pilot",state_dir=file.path(root,"state")) {
  mode<-match.arg(mode);cutoff<-as.Date(cutoff)
  if(mode=="incremental_live"&&!download)stop("A live incremental benchmark requires downloads; use cache_replay for an offline run.")
  if(length(cutoff)!=1L||is.na(cutoff)||cutoff>=Sys.Date())stop("Use a completed-day cutoff before today.")
  if(!grepl("^data/diagnostics/[A-Za-z0-9_/-]+$",root)||any(strsplit(root,"/",fixed=TRUE)[[1]]%in%c(".","..")))stop("Network output must be under data/diagnostics.")
  viewer<-file.path(root,"viewer")
  dir.create(root,recursive=TRUE,showWarnings=FALSE)
  sites<-streamflow_network_sites();write.csv(sites,file.path(root,"network-plan.csv"),row.names=FALSE)
  started<-Sys.time();events<-new.env(parent=emptyenv());events$rows<-list()
  metrics<-new.env(parent=emptyenv())
  # Bootstrap is one-time setup; steady updates have a 45-second source budget
  # so assembly/reference reuse can fit within the proposed 60-second increment.
  metrics$deadline<-started+if(mode=="bootstrap")180 else 45
  provider<-streamflow_network_provider(state_dir,mode,download,events)
  build<-build_streamflow_pilot(cutoff=cutoff,download=download,sites=sites,output_dir=viewer,
    daily_rows_provider=provider,metrics=metrics,request_limit=if(mode=="bootstrap")120L else 60L)
  statistics<-add_streamflow_statistics(viewer,download=download&&mode=="bootstrap",refresh=FALSE)
  event_table<-if(length(events$rows))do.call(rbind,events$rows)else data.frame(id=character(),mode=character(),query_start=character(),query_end=character(),
    query_days=integer(),bootstrap=logical(),status=character(),old_through=character(),changed_dates=integer(),note=character())
  eligibility<-streamflow_network_eligibility(viewer,sites,event_table)
  p<-jsonlite::read_json(file.path(viewer,"streamflow-data.json"))
  for(i in seq_along(p$gauges)) {
    r<-eligibility[match(p$gauges[[i]]$id,eligibility$id),]
    p$gauges[[i]]$eligibility<-r$status;p$gauges[[i]]$management_note<-r$management_note
  }
  p$network_assessment<-TRUE
  jsonlite::write_json(p,file.path(viewer,"streamflow-data.json"),auto_unbox=TRUE,na="null",digits=10)
  elapsed<-as.numeric(difftime(Sys.time(),started,units="secs"))
  # Length of gauges is a list count, not a data-frame row count.
  complete<-length(build$gauges)==32L&&nrow(event_table)==32L&&all(event_table$status=="UPDATED")
  request_rows<-do.call(rbind,metrics$rows)
  metadata_requests<-sum(!request_rows$reused&request_rows$collection!="daily")
  summary<-data.frame(mode=mode,cutoff=as.character(cutoff),configured=32L,built=length(build$gauges),
    eligible=sum(eligibility$status=="ELIGIBLE"),observations_only=sum(eligibility$status=="OBSERVATIONS_ONLY"),
    stale_or_failed=sum(!eligibility$status%in%c("ELIGIBLE","OBSERVATIONS_ONLY")),
    requests=metrics$requests,metadata_requests=metadata_requests,statistics_requests=statistics$workload$requests,
    transferred_bytes=sum(do.call(rbind,metrics$rows)$transferred_bytes)+statistics$workload$transferred_bytes,
    max_query_days=if(nrow(event_table))max(event_table$query_days)else 0L,
    bootstrap_gauges=sum(event_table$bootstrap),changed_dates=sum(event_table$changed_dates),
    complete_source_refresh=complete,seconds=elapsed,target_seconds=60,
    within_runtime_target=mode=="incremental_live"&&complete&&elapsed<=60&&metadata_requests==0L&&statistics$workload$requests==0L&&all(!event_table$bootstrap))
  write.csv(eligibility,file.path(root,"eligibility.csv"),row.names=FALSE,na="")
  write.csv(eligibility,file.path(viewer,"eligibility.csv"),row.names=FALSE,na="")
  write.csv(event_table,file.path(root,paste0(mode,"-gauges.csv")),row.names=FALSE)
  write.csv(summary,file.path(root,"last-run.csv"),row.names=FALSE)
  history<-file.path(root,"benchmark-history.csv")
  previous<-if(file.exists(history))read.csv(history,stringsAsFactors=FALSE)else summary[FALSE,]
  write.csv(rbind(previous,summary),history,row.names=FALSE)
  print(table(eligibility$status));print(summary,row.names=FALSE)
  message("32-gauge assessment: ",root,"; production and the 12-gauge pilot were not changed.")
  invisible(list(directory=root,viewer=viewer,eligibility=eligibility,summary=summary))
}
