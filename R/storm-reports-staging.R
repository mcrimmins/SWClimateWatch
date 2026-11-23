# Explicit, staging-only release adapter. No daily-runner hook or production flag.
storm_reports_staging_guard <- function() {
  if(!identical(Sys.getenv("SWC_S3_DESTINATION"),"s3://cales-climate-reports/climate/watch-staging/")||
     !identical(Sys.getenv("SWC_PRODUCTION_STATE_DIR"),"/home/crimmins/.local/state/swclimatewatch-staging"))
    stop("Storm report trial requires the exact staging destination and staging state directory.")
  invisible(TRUE)
}

validate_storm_reports_publication <- function(directory,require_enabled=TRUE) {
  data<-jsonlite::read_json(file.path(directory,"daily-data.json"))
  if(require_enabled&&(!isTRUE(data$storm_reports_enabled)||!isTRUE(data$publication_mode)))
    stop("Storm report publication is not enabled on this Explorer snapshot.")
  catalog<-jsonlite::read_json(file.path(directory,"storm-reports-manifest.json"))
  if(!identical(catalog$schema_version,1L)||!length(catalog$days))stop("Invalid storm report catalog.")
  dates<-vapply(catalog$days,`[[`,character(1),"date")
  if(anyDuplicated(dates)||anyNA(as.Date(dates))||is.unsorted(dates))stop("Invalid report dates.")
  rows<-list()
  for(day in catalog$days) {
    if(!grepl("^reports/[0-9]{4}-[0-9]{2}-[0-9]{2}[.]json$",day$path)||
       !identical(day$path,paste0("reports/",day$date,".json")))stop("Invalid report path.")
    if(identical(day$status,"UNAVAILABLE")) {
      if(day$reports!=0L||!is.null(day$md5))stop("Unavailable date has an invalid payload reference.")
      next
    }
    path<-file.path(directory,day$path)
    if(!file.exists(path)||!identical(unname(tools::md5sum(path)),day$md5))stop("Missing or modified report payload: ",day$date)
    p<-jsonlite::read_json(path)
    if(!identical(p$schema_version,1L)||!identical(p$date,day$date)||length(p$reports)!=day$reports||
      !identical(day$status,if(length(p$reports))"READY"else"EMPTY"))stop("Report count/status mismatch.")
    for(r in p$reports)if(!identical(substr(r$valid,1,10),day$date)||!identical(r$date,day$date)||
      !r$state%in%c("AZ","NM")||!nzchar(r$type)||!grepl("^[a-f0-9]{64}$",r$id))stop("Invalid report record.")
    rows<-c(rows,p$reports)
  }
  ids<-vapply(rows,`[[`,character(1),"id")
  if(anyDuplicated(ids))stop("Duplicate report identifiers.")
  times<-as.POSIXct(vapply(rows,`[[`,character(1),"valid"),format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  if(anyNA(times))stop("Invalid report event time.")
  explorer_dates<-vapply(data$days,`[[`,character(1),"date")
  available_dates<-dates[vapply(catalog$days,function(d)d$status!="UNAVAILABLE",logical(1))]
  for(timing in c("prism","utc")) {
    summary<-catalog$timeline[[timing]]
    if(!identical(vapply(summary,`[[`,character(1),"date"),explorer_dates))stop("Timeline does not match Explorer dates.")
    labels<-format(times+if(timing=="prism")43200 else 0,"%Y-%m-%d",tz="UTC")
    for(day in summary) {
      required<-if(timing=="prism")c(as.character(as.Date(day$date)-1),day$date)else day$date
      if(!identical(day$complete,all(required%in%available_dates))||
        !identical(day$available,any(required%in%available_dates))||
        !identical(day$stale,any(required%in%unlist(catalog$stale_dates))))stop("Timeline coverage mismatch.")
      for(region in c("AZNM","AZ","NM")) {
        subset<-rows[which(labels==day$date&vapply(rows,function(r)region=="AZNM"||r$state==region,logical(1)))]
        expected<-table(vapply(subset,`[[`,character(1),"type"))
        got<-day$regions[[region]]
        if(got$total!=length(subset)||!setequal(names(got$types),names(expected))||
          any(vapply(names(expected),function(type)got$types[[type]]!=unname(expected[[type]]),logical(1))))
          stop("Timeline report totals/types mismatch: ",day$date)
      }
    }
  }
  html<-paste(readLines(file.path(directory,"index.html"),warn=FALSE),collapse="\n")
  for(id in c("storm-panel","storm-timing","storm-timeline-note","storm-timeline-detail","storm-clear",
    "storm-view-panel","storm-view-count","storm-view-types","storm-view-extremes","storm-view-all","storm-view-reset-types"))
    if(!grepl(paste0('id="',id,'"'),html,fixed=TRUE))stop("Missing report control: ",id)
  for(asset in c("explorer.js","storm-reports.js","report-view-stats.js","storm-reports.css","leaflet.js","leaflet.css"))
    if(!file.exists(file.path(directory,asset)))stop("Missing report browser asset: ",asset)
  js<-paste(readLines(file.path(directory,"explorer.js"),warn=FALSE),collapse="\n")
  if(!grepl("swc:daily-selection",js,fixed=TRUE)||!grepl("dataset.reportDate",js,fixed=TRUE))stop("Explorer/report selection bridge is missing.")
  source("R/site-cache.R",local=TRUE)
  swc_cache_validate_app(directory)
  result<-data.frame(status="PASS",explorer_dates=length(explorer_dates),report_dates=length(dates),reports=length(rows),directory=directory)
  print(result,row.names=FALSE);invisible(result)
}

stage_storm_reports_snapshot <- function(directory="site/daily-explorer",
    work="data/diagnostics/storm-reports-staging",snapshot=NULL) {
  source("R/storm-reports-pilot.R",local=TRUE)
  original<-jsonlite::read_json(file.path(directory,"daily-data.json"))
  if(!isTRUE(original$publication_mode))stop("Stage the normal Daily Explorer first.")
  build_storm_reports_pilot(source_dir=directory,output_dir=work,copy_maps=FALSE,full_window=TRUE,snapshot=snapshot)
  original$storm_reports_preview<-NULL;original$storm_reports_enabled<-TRUE
  jsonlite::write_json(original,file.path(work,"daily-data.json"),auto_unbox=TRUE,digits=NA,null="null")
  source("R/site-cache.R",local=TRUE)
  swc_cache_version_app(work)
  validate_storm_reports_publication(work)
  catalog<-jsonlite::read_json(file.path(work,"storm-reports-manifest.json"))
  browser<-jsonlite::read_json(file.path(work,"cache-assets.json"))
  files<-unique(c("index.html","daily-data.json","storm-reports-manifest.json","cache-assets.json",
    vapply(browser$assets,`[[`,character(1),"canonical"),vapply(browser$assets,`[[`,character(1),"file"),
    "leaflet-package-LICENSE",paste0("images/",list.files(file.path(work,"images"),full.names=FALSE)),
    vapply(Filter(function(d)d$status!="UNAVAILABLE",catalog$days),`[[`,character(1),"path")))
  for(file in files) {
    from<-file.path(work,file);to<-file.path(directory,file)
    dir.create(dirname(to),recursive=TRUE,showWarnings=FALSE)
    if(!file.exists(to)||!identical(unname(tools::md5sum(from)),unname(tools::md5sum(to))))
      if(!file.copy(from,to,overwrite=TRUE))stop("Cannot stage storm-report asset: ",file)
  }
  validate_storm_reports_publication(directory)
  message("Verified storm report snapshot staged.")
  invisible(TRUE)
}

stage_storm_reports_staging <- function(directory="site/daily-explorer",work="data/diagnostics/storm-reports-staging") {
  storm_reports_staging_guard()
  stage_storm_reports_snapshot(directory,work)
  message("Staging trial only; daily report refresh is not enabled by this adapter.")
}
