# Incremental report cache, optional daily workflow and cache-only publication.
storm_reports_enabled <- function()tolower(Sys.getenv("SWC_STORM_REPORTS","false"))=="true"
storm_reports_daily_guard <- function() {
  destinations<-c("s3://cales-climate-reports/climate/watch-staging/","s3://cales-climate-reports/climate/watch/")
  states<-c("/home/crimmins/.local/state/swclimatewatch-staging","/home/crimmins/.local/state/swclimatewatch")
  index<-match(Sys.getenv("SWC_S3_DESTINATION"),destinations)
  if(is.na(index)||!identical(Sys.getenv("SWC_PRODUCTION_STATE_DIR"),states[index]))stop("Storm report daily workflow requires matching destination/state settings.")
}

storm_reports_read_day <- function(path) {
  for(file in c(path,paste0(path,".previous"))) {
    if(!file.exists(file))next
    x<-tryCatch(suppressWarnings(readRDS(file)),error=function(e)NULL)
    if(is.list(x)&&identical(x$schema_version,1L)&&length(x$date)==1L&&
      is.character(x$fetched_utc)&&length(x$fetched_utc)==1L&&
      identical(x$digest,digest::digest(x$reports,algo="sha256"))&&
      all(vapply(x$reports,function(r)identical(r$date,x$date),logical(1))))return(x)
  }
  NULL
}
storm_reports_write_day <- function(date,reports,fetched_utc,cache_dir) {
  path<-file.path(cache_dir,paste0(date,".rds"))
  x<-list(schema_version=1L,date=date,reports=reports,fetched_utc=fetched_utc,
    digest=digest::digest(reports,algo="sha256"))
  temporary<-tempfile(tmpdir=cache_dir);on.exit(unlink(temporary),add=TRUE);saveRDS(x,temporary)
  previous<-if(file.exists(path))tryCatch(suppressWarnings(readRDS(path)),error=function(e)NULL)else NULL
  if(is.list(previous)&&identical(previous$digest,digest::digest(previous$reports,algo="sha256")))
    if(!file.copy(path,paste0(path,".previous"),overwrite=TRUE))stop("Cannot retain report cache backup.")
  if(!file.copy(temporary,path,overwrite=TRUE))stop("Cannot save report cache.")
  x
}

refresh_storm_reports_cache <- function(start,end,download=TRUE,refresh_days=14L,max_requests=3L,
    cache_dir="data/processed/storm-reports/az-nm",raw_dir="data/raw/storm-reports/az-nm",
    fetcher=function(start,end)read_storm_reports_cache(start,end,refresh=TRUE,cache_dir=raw_dir)) {
  source("R/storm-reports-pilot.R",local=TRUE)
  start<-as.Date(start);end<-as.Date(end)
  if(is.na(start)||is.na(end)||end<=start||end-start>401||refresh_days<1||refresh_days>62||max_requests<1)stop("Invalid storm report refresh window.")
  dir.create(cache_dir,recursive=TRUE,showWarnings=FALSE)
  dates<-as.character(seq(start,end-1,by="day"))
  read_day<-function(date)storm_reports_read_day(file.path(cache_dir,paste0(date,".rds")))
  days<-setNames(lapply(dates,read_day),dates)
  # Import existing verified staging/pilot bulk caches for missing dates only.
  missing<-names(days)[vapply(days,is.null,logical(1))]
  if(length(missing))for(path in list.files(raw_dir,pattern="^[0-9-]+_[0-9-]+[.]rds$",full.names=TRUE)) {
    bounds<-strsplit(sub("[.]rds$","",basename(path)),"_",fixed=TRUE)[[1]]
    needed<-missing[missing>=bounds[1]&missing<bounds[2]]
    if(!length(needed))next
    x<-tryCatch(readRDS(path),error=function(e)NULL)
    rows<-tryCatch({if(!identical(x$start,bounds[1])||!identical(x$end,bounds[2])||is.null(x$fetched_utc))stop("Invalid seed");normalize_storm_reports(x$raw,x$start,x$end)},error=function(e)NULL)
    if(is.null(rows))next
    for(date in needed)days[date]<-list(storm_reports_write_day(date,Filter(function(r)r$date==date,rows),x$fetched_utc,cache_dir))
    missing<-names(days)[vapply(days,is.null,logical(1))]
  }
  recent_start<-max(start,end-as.integer(refresh_days))
  pending_path<-file.path(cache_dir,"refresh-pending.rds")
  pending<-if(file.exists(pending_path))tryCatch(suppressWarnings(readRDS(pending_path)),error=function(e)dates[dates>=as.character(recent_start)])else character()
  if(!is.character(pending))pending<-dates[dates>=as.character(recent_start)]
  plan<-list(c(as.character(recent_start),as.character(end)))
  retries<-union(missing,intersect(pending,dates))
  older<-as.Date(retries[retries<as.character(recent_start)])
  while(length(older)) {
    first<-min(older);last<-first
    while(as.character(last+1)%in%as.character(older)&&last-first<61)last<-last+1
    plan[[length(plan)+1L]]<-as.character(c(first,last+1))
    older<-older[older>last]
  }
  requests<-changed<-0L;refreshed<-failed<-character();errors<-character()
  if(download)for(batch in head(plan,as.integer(max_requests))) {
    requests<-requests+1L
    first<-as.Date(batch[1]);last<-as.Date(batch[2]);target<-dates[dates>=batch[1]&dates<batch[2]]
    x<-tryCatch({value<-fetcher(first,last);normalize_storm_reports(value$raw,first,last);
      if(length(value$fetched_utc)!=1L||is.na(as.POSIXct(value$fetched_utc,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")))stop("Invalid report fetch timestamp.")
      value},error=function(e){errors<<-c(errors,conditionMessage(e));NULL})
    if(is.null(x)){failed<-c(failed,target);next}
    rows<-normalize_storm_reports(x$raw,first,last)
    for(date in target) {
      subset<-Filter(function(r)r$date==date,rows)
      if(is.null(days[[date]])||!identical(days[[date]]$digest,digest::digest(subset,algo="sha256")))changed<-changed+1L
      days[date]<-list(storm_reports_write_day(date,subset,x$fetched_utc,cache_dir))
    }
    refreshed<-c(refreshed,target)
  }
  available<-names(days)[!vapply(days,is.null,logical(1))]
  pending<-intersect(union(setdiff(pending,refreshed),failed),dates)
  if(download)saveRDS(pending,pending_path)
  stale<-intersect(pending,available);missing<-setdiff(dates,available)
  if(!download) {
    stale<-union(stale,available[vapply(days[available],function(x){t<-as.POSIXct(x$fetched_utc,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC");is.na(t)||difftime(Sys.time(),t,units="hours")>36},logical(1)) & available>=as.character(recent_start)])
  }
  snapshot<-list(reports=unname(unlist(lapply(days[available],`[[`,"reports"),recursive=FALSE)),available_dates=available,
    stale_dates=stale,snapshots=lapply(days[available],function(x)x[c("date","fetched_utc")]))
  summary<-data.frame(status=if(!length(available))"UNAVAILABLE"else if(length(missing)||length(stale))"PARTIAL"else"READY",
    cutoff=as.character(end-1),dates=length(dates),available=length(available),reports=length(snapshot$reports),
    refreshed=length(unique(refreshed)),changed=changed,reused=length(setdiff(available,refreshed)),
    stale=length(stale),missing=length(missing),requests=requests,error=paste(unique(errors),collapse="; "))
  list(snapshot=snapshot,summary=summary)
}

prepare_storm_reports_daily <- function(directory="site/daily-explorer",download=TRUE,
    cache_dir="data/processed/storm-reports/az-nm",report_dir="data/diagnostics/storm-reports-daily") {
  if(!storm_reports_enabled())return(list(status="DISABLED"))
  storm_reports_daily_guard()
  source("R/storm-reports-staging.R",local=TRUE)
  started<-Sys.time();payload<-jsonlite::read_json(file.path(directory,"daily-data.json"))
  dates<-as.Date(vapply(payload$days,`[[`,character(1),"date"))
  result<-refresh_storm_reports_cache(min(dates)-1,max(dates)+1,download=download,cache_dir=cache_dir)
  stage_storm_reports_snapshot(directory,file.path(report_dir,"candidate"),snapshot=result$snapshot)
  result$summary$seconds<-round(as.numeric(difftime(Sys.time(),started,units="secs")),3)
  dir.create(report_dir,recursive=TRUE,showWarnings=FALSE)
  write.csv(result$summary,file.path(report_dir,if(download)"workflow-status.csv"else"publication-status.csv"),row.names=FALSE)
  print(result$summary,row.names=FALSE)
  as.list(result$summary[1,])
}

validate_storm_reports_daily <- function(output_dir="site/_site") {
  if(!storm_reports_enabled())return(invisible(NULL))
  source("R/storm-reports-staging.R",local=TRUE)
  validate_storm_reports_publication("site/daily-explorer")
  validate_storm_reports_publication(file.path(output_dir,"daily-explorer"))
}
