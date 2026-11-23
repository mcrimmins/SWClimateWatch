# Optional retrospective hazards. Downloads occur only in the daily update;
# publication restaging is strictly cache-only.
nws_hazards_enabled <- function()tolower(Sys.getenv("SWC_NWS_HAZARDS","false"))=="true"
nws_hazards_daily_guard <- function() {
  source("R/storm-reports-daily.R",local=TRUE)
  storm_reports_daily_guard()
  if(!storm_reports_enabled())stop("NWS hazards require SWC_STORM_REPORTS=true.")
  if(tolower(Sys.getenv("SWC_NWS_HAZARDS_STAGING"))=="true")stop("Unset the manual hazard staging flag before daily integration.")
}

nws_hazards_request_manager <- function(end,download=TRUE,max_requests=6L,refresh_days=14L,
    state_dir="data/processed/nws-hazards-daily",fetcher=NULL,now=Sys.time()) {
  if(is.null(fetcher)) {source("R/nws-hazards-pilot.R",local=TRUE);fetcher<-nws_hazards_request}
  end<-as.Date(end)
  if(length(end)!=1L||is.na(end)||length(max_requests)!=1L||is.na(max_requests)||max_requests<1||
     length(refresh_days)!=1L||is.na(refresh_days)||refresh_days<1||refresh_days>31)stop("Invalid hazard refresh settings.")
  dir.create(state_dir,recursive=TRUE,showWarnings=FALSE)
  path<-file.path(state_dir,"retry-pending.rds")
  pending<-if(file.exists(path))tryCatch(readRDS(path),error=function(e)character())else character()
  if(!is.character(pending))pending<-character()
  requests<-refreshed<-reused<-stale<-deferred<-missing<-0L;errors<-character();seen<-character()
  request<-function(start,end=NULL,at=NULL,simple=FALSE,refresh=FALSE) {
    key<-digest::digest(list(start=start,end=end,at=at,simple=simple),algo="sha256")
    seen<<-union(seen,key)
    recent<-as.Date(start)>=end_date-refresh_days || (!is.null(end)&&as.Date(end)>end_date-refresh_days) ||
      (!is.null(at)&&as.Date(start)+31>end_date-refresh_days)
    cache<-tryCatch(fetcher(start,end=end,at=at,simple=simple,download=FALSE),error=function(e)NULL)
    should_refresh<-is.null(cache)||recent||key%in%pending
    if(download&&should_refresh&&requests<max_requests) {
      requests<<-requests+1L
      fresh<-tryCatch(fetcher(start,end=end,at=at,simple=simple,refresh=TRUE,download=TRUE),error=function(e){errors<<-c(errors,conditionMessage(e));NULL})
      if(!is.null(fresh)) {
        pending<<-setdiff(pending,key);refreshed<<-refreshed+1L
        return(fresh)
      }
      pending<<-union(pending,key)
    } else if(download&&should_refresh) {
      deferred<<-deferred+1L;pending<<-union(pending,key)
    }
    if(is.null(cache)) {
      pending<<-union(pending,key);missing<<-missing+1L
      stop("A required hazard archive window has no verified cached data; retry next run.")
    }
    reused<<-reused+1L
    fetched<-as.POSIXct(cache$meta$fetched_utc,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
    aged<-recent&&(length(fetched)!=1L||is.na(fetched)||difftime(now,fetched,units="hours")>36)
    if(key%in%pending||aged)stale<<-stale+1L
    cache
  }
  # Use an immutable name: request() has an argument named end.
  end_date<-end
  stats<-function()list(requests=requests,refreshed=refreshed,reused=reused,stale=stale,
    deferred=deferred,missing=missing,pending=length(intersect(pending,seen)),error=paste(unique(errors),collapse="; "))
  save<-function(){if(download)saveRDS(pending,path);invisible(NULL)}
  note<-function(){x<-stats();if(x$stale||x$deferred)
    sprintf("Cached hazard archive: %d stale source windows; %d refreshes deferred. Counts may change when retries succeed. This is not live warning information.",x$stale,x$deferred)
    else ""}
  list(request=request,stats=stats,save=save,note=note)
}

prepare_nws_hazards_daily <- function(directory="site/daily-explorer",download=TRUE,
    report_dir="data/diagnostics/nws-hazards-daily",state_dir="data/processed/nws-hazards-daily",fetcher=NULL) {
  if(!nws_hazards_enabled())return(list(status="DISABLED"))
  nws_hazards_daily_guard()
  source("R/nws-hazards-staging.R",local=TRUE)
  source("R/site-cache.R",local=TRUE)
  source("R/storm-reports-staging.R",local=TRUE)
  validate_storm_reports_publication(directory)
  started<-Sys.time();payload<-jsonlite::read_json(file.path(directory,"daily-data.json"))
  dates<-vapply(payload$days,`[[`,character(1),"date")
  manager<-nws_hazards_request_manager(as.Date(max(dates))+1,download=download,state_dir=state_dir,fetcher=fetcher)
  on.exit(manager$save(),add=TRUE)
  error<-NULL
  ok<-tryCatch({stage_nws_hazards_snapshot(directory,file.path(report_dir,"candidate"),
    request_fun=manager$request,coverage_note=manager$note);TRUE},error=function(e){error<<-conditionMessage(e);FALSE})
  x<-manager$stats()
  if(!ok) {
    # Recover only from a pre-hazard candidate. Never leave an old timeline
    # controller/counts visible beside an unavailable notice. Later validation
    # failures stop publication rather than masking a mixed release.
    candidate<-file.path(report_dir,"candidate")
    plain_index<-file.path(candidate,"index.html")
    if(!file.exists(plain_index)||grepl('id="hazard-panel"',paste(readLines(plain_index,warn=FALSE),collapse="\n"),fixed=TRUE))
      stop("NWS hazard candidate failed after assembly; publication stopped: ",error)
    browser<-jsonlite::read_json(file.path(candidate,"cache-assets.json"))
    recovery<-unique(c("index.html","cache-assets.json",vapply(browser$assets,`[[`,character(1),"canonical"),
      vapply(browser$assets,`[[`,character(1),"file")))
    for(file in recovery)if(!file.copy(file.path(candidate,file),file.path(directory,file),overwrite=TRUE))stop("Cannot restore report-only Explorer.")
    payload$nws_hazards_enabled<-FALSE;payload$nws_hazards_preview<-NULL
    jsonlite::write_json(payload,file.path(directory,"daily-data.json"),auto_unbox=TRUE,digits=NA,null="null")
    html<-paste(readLines(file.path(directory,"index.html"),warn=FALSE),collapse="\n")
    html<-sub('<details id="circulation-panel"',paste0('<p id="hazard-unavailable" role="status">NWS hazard archive unavailable for the current Explorer window. Automatic retries resume on subsequent daily runs; unavailable does not mean no hazards.</p><details id="circulation-panel"'),html,fixed=TRUE)
    writeLines(html,file.path(directory,"index.html"),useBytes=TRUE)
    swc_cache_version_app(directory)
    warning("NWS hazard update unavailable: ",error,call.=FALSE)
  }
  result<-data.frame(status=if(!ok)"UNAVAILABLE"else if(x$stale||x$deferred)"PARTIAL"else"READY",
    cutoff=max(dates),explorer_dates=length(dates),events=if(ok)length(jsonlite::read_json(file.path(directory,"hazards/cases/explorer.json"))$events)else 0L,
    requests=x$requests,refreshed=x$refreshed,reused=x$reused,stale=x$stale,deferred=x$deferred,missing=x$missing,
    retry_pending=x$pending,error=if(is.null(error))x$error else error,seconds=round(as.numeric(difftime(Sys.time(),started,units="secs")),3))
  dir.create(report_dir,recursive=TRUE,showWarnings=FALSE)
  jsonlite::write_json(as.list(result[1,]),file.path(directory,"hazard-workflow-status.json"),auto_unbox=TRUE,null="null")
  write.csv(result,file.path(report_dir,if(download)"workflow-status.csv"else"publication-status.csv"),row.names=FALSE)
  print(result,row.names=FALSE);as.list(result[1,])
}

validate_nws_hazards_daily <- function(output_dir="site/_site",source_dir="site/daily-explorer") {
  if(!nws_hazards_enabled())return(invisible(NULL))
  source("R/nws-hazards-staging.R",local=TRUE)
  for(directory in c(source_dir,file.path(output_dir,"daily-explorer"))) {
    payload<-jsonlite::read_json(file.path(directory,"daily-data.json"))
    status<-jsonlite::read_json(file.path(directory,"hazard-workflow-status.json"))
    cutoff<-max(vapply(payload$days,`[[`,character(1),"date"))
    if(!identical(status$cutoff,cutoff))stop("Hazard workflow cutoff differs from Explorer.")
    if(status$status%in%c("READY","PARTIAL")) {
      validate_nws_hazards_publication(directory)
      if(status$status=="PARTIAL"&&!grepl('id="hazard-data-status"',paste(readLines(file.path(directory,"index.html")),collapse="\n"),fixed=TRUE))stop("Missing stale hazard notice.")
    } else if(status$status=="UNAVAILABLE") {
      if(isTRUE(payload$nws_hazards_enabled)||!grepl('id="hazard-unavailable"',paste(readLines(file.path(directory,"index.html")),collapse="\n"),fixed=TRUE))stop("Missing explicit hazard unavailable notice.")
    } else stop("Invalid hazard daily status.")
  }
  message("PASS: daily hazard source/rendered coverage, cutoff and publication status.")
}
