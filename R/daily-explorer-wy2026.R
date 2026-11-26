# Local WY2026 month batches. No live site, environment, scheduler or S3 writes.
wy2026_explorer_load <- function() {
  source("R/daily-explorer-wy2025.R",local=FALSE)
  source("R/daily-explorer-seasonal-pilots.R",local=FALSE)
  seasonal_explorer_load()
  source("R/nws-hazards-staging.R",local=FALSE)
  source("R/daily-explorer-archive-integration.R",local=FALSE)
}
wy2026_explorer_root <- function()daily_archive_pilot_root("data/diagnostics/daily-explorer-wy2026")
wy2026_explorer_windows <- function() {
  starts<-seq(as.Date("2025-10-01"),as.Date("2026-10-01"),by="month")
  setNames(lapply(seq_len(12L),function(i) {
    month<-format(starts[i],"%Y-%m")
    list(id=paste0("wy2026-",month),title=paste("WY2026",month),start=as.character(starts[i]),
      end=as.character(starts[i+1L]-1L),root=file.path("data/diagnostics/daily-explorer-wy2026/months",month),event_lookback_days=30L)
  }),format(starts[1:12],"%Y-%m"))
}
wy2026_explorer_source <- function(month) {
  w<-wy2026_explorer_windows()[[month]]
  if(is.null(w))stop("Choose a WY2026 month: 2025-10 through 2026-09.")
  list(window=w,root=july_pilot_context(w)$root,release="window-release.json")
}
wy2026_explorer_plan <- function(validate=FALSE) {
  rows<-lapply(names(wy2026_explorer_windows()),function(month) {
    w<-wy2026_explorer_windows()[[month]];s<-wy2026_explorer_source(month)
    file<-file.path(s$root,"viewer",s$release);present<-file.exists(file)
    status<-if(present)"RELEASE_PRESENT"else"PENDING";note<-""
    if(present&&validate) {
      error<-tryCatch({validate_daily_explorer_july(file.path(s$root,"viewer"),window=s$window);NULL},error=function(e)conditionMessage(e))
      status<-if(is.null(error))"READY"else"INVALID";note<-if(is.null(error))""else error
    }
    dates<-as.character(seq(as.Date(w$start),as.Date(w$end),by="day"))
    data.frame(month,start=w$start,end=w$end,dates=length(dates),support_start=as.character(as.Date(w$start)-29L),
      weather_support_dates=length(dates)+29L,prism_maps=7L*length(dates),daily_weather_maps=3L*length(dates),
      mean_maps=6L*length(dates),status,note)
  })
  plan<-do.call(rbind,rows)
  write.csv(plan,file.path(wy2026_explorer_root(),"month-plan.csv"),row.names=FALSE)
  plan
}
wy2026_explorer_seed <- function(month) {
  s<-wy2026_explorer_source(month)
  if(is.null(s$window))return(invisible(NULL))
  context<-july_pilot_context(s$window)
  donors<-unique(c(july_pilot_root(),vapply(seasonal_explorer_windows(),`[[`,character(1),"root"),
    vapply(wy2025_explorer_windows(),`[[`,character(1),"root"),
    vapply(wy2026_explorer_windows(),`[[`,character(1),"root")))
  donors<-setdiff(donors,s$root)
  for(date in context$support) {
    if(!is.null(july_pilot_input(s$root,date)))next
    for(donor in donors) {
      x<-july_pilot_input(donor,date);if(is.null(x))next
      path<-file.path(s$root,"inputs",date,"complete.rds")
      dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE);saveRDS(x,path)
      stopifnot(!is.null(july_pilot_input(s$root,date)));break
    }
  }
  for(date in context$dates) {
    target<-file.path(s$root,"prism/cache",paste0(date,".rds"))
    if(!file.exists(target))for(donor in donors) {
      file<-file.path(donor,"prism/cache",paste0(date,".rds"))
      x<-if(file.exists(file))tryCatch(readRDS(file),error=function(e)NULL)else NULL
      if(!is.list(x)||!is.list(x$record$images))next
      images<-unlist(x$record$images,use.names=FALSE)
      if(!all(file.exists(file.path(donor,"prism",images))))next
      for(image in images)july_pilot_copy(file.path(donor,"prism",image),file.path(s$root,"prism",image))
      july_pilot_copy(file,target);break # Regular PRISM builder rechecks signatures.
    }
    for(n in c(1L,7L,30L)) {
      target<-file.path(s$root,"weather",date,paste0(n,"day"))
      if(weather_period_archive_current(target))next
      for(donor in donors) {
        from<-file.path(donor,"weather",date,paste0(n,"day"))
        if(!weather_period_archive_current(from))next
        for(file in c("height500.png","jet250.png","moisture.png","mean-native-grid.rds","complete.rds"))
          july_pilot_copy(file.path(from,file),file.path(target,file))
        stopifnot(weather_period_archive_current(target));break
      }
    }
  }
  invisible(NULL)
}
run_wy2026_explorer_batch <- function(month=NULL,download=FALSE,max_input_dates=10L,max_end_dates=7L) {
  if(length(download)!=1L||!is.logical(download)||is.na(download)||
    length(max_input_dates)!=1L||is.na(max_input_dates)||!max_input_dates%in%1:10||
    length(max_end_dates)!=1L||is.na(max_end_dates)||!max_end_dates%in%1:7)stop("Use TRUE/FALSE downloads, 1-10 input dates and 1-7 weather endpoints.")
  if(!is.null(month)&&(length(month)!=1L||is.na(month)||!month%in%names(wy2026_explorer_windows())))stop("Invalid WY2026 month.")
  # Local archive requests may be larger than the operational daily ranges.
  # Restore the caller's request settings even when a batch fails or is stopped.
  withr::local_options(list(
    swc.storm_reports.timeout=getOption("swc.wy2026.report_timeout",120),
    swc.storm_reports.max_tries=getOption("swc.wy2026.report_max_tries",3L)))
  plan<-wy2026_explorer_plan()
  if(is.null(month)) {
    pending<-plan$month[plan$status=="PENDING"]
    if(!length(pending))return(invisible(data.frame(status="ALL_RELEASES_PRESENT",month=NA_character_)))
    month<-pending[1]
  }
  s<-wy2026_explorer_source(month)
  marker<-file.path(s$root,"viewer",s$release)
  # A selected completed month is validated, never blindly rebuilt.
  if(file.exists(marker)) {
    error<-tryCatch({validate_daily_explorer_july(file.path(s$root,"viewer"),window=s$window);NULL},error=function(e)conditionMessage(e))
    if(is.null(error))return(invisible(data.frame(status="MONTH_READY",month)))
    message("Repairing selected month ",month,": ",error,". Cached inputs and maps will be rechecked.")
    if(!file.remove(marker))stop("Cannot retire invalid local month release marker.")
  }
  message("WY2026 batch: ",month)
  wy2026_explorer_seed(month)
  inputs<-tryCatch(prepare_daily_explorer_july(download,max_input_dates,window=s$window),error=function(e) {
    stop(conditionMessage(e),"\nWY2026 checkpoint retained. Cache-only mode never downloads. To permit missing CORe/event inputs, set options(swc.wy2026.download=TRUE) and resume. Daily PRISM inputs must already be cached.",call.=FALSE)
  })
  status<-"PREPARING"
  if(inputs$status=="READY") {
    x<-tryCatch(build_daily_explorer_july(download_events=download,max_end_dates=max_end_dates,window=s$window),error=function(e) {
      stop(conditionMessage(e),"\nWY2026 checkpoint retained; resume the same month after resolving the input error. Missing CORe/event inputs require options(swc.wy2026.download=TRUE); daily PRISM is cache-only.",call.=FALSE)
    })
    status<-if(identical(x$status,"READY"))"MONTH_READY"else"BUILDING"
    if(status=="MONTH_READY")validate_daily_explorer_july(file.path(s$root,"viewer"),window=s$window)
  }
  result<-data.frame(status,month,inputs_ready=inputs$ready,inputs_required=inputs$required)
  write.csv(result,file.path(wy2026_explorer_root(),"last-batch.csv"),row.names=FALSE)
  wy2026_explorer_plan();print(result,row.names=FALSE);invisible(result)
}
validate_wy2026_explorer <- function(require_complete=TRUE) {
  plan<-wy2026_explorer_plan(validate=TRUE)
  print(plan,row.names=FALSE)
  if(any(plan$status=="INVALID"))stop("Invalid month release; select that month with options(swc.wy2026.month='YYYY-MM') and rerun its batch to repair. Inspect month-plan.csv.")
  if(require_complete&&!all(plan$status=="READY"))stop("WY2026 is incomplete; resume the pending monthly batches.")
  if(all(plan$status=="READY"))stopifnot(sum(plan$dates)==365L,sum(plan$prism_maps)==2555L,
    sum(plan$daily_weather_maps)==1095L,sum(plan$mean_maps)==2190L)
  invisible(plan)
}
build_wy2026_explorer_navigation <- function(require_complete=TRUE) {
  plan<-validate_wy2026_explorer(require_complete)
  ready<-plan$month[plan$status=="READY"]
  if(!length(ready))stop("Complete at least one month before previewing.")
  root<-file.path(wy2026_explorer_root(),"preview");dir.create(root,recursive=TRUE,showWarnings=FALSE)
  marker<-file.path(root,"wy2026-release.json")
  if(file.exists(marker))file.remove(marker)
  months<-lapply(ready,function(month) {
    s<-wy2026_explorer_source(month);source_dir<-file.path(s$root,"viewer")
    release<-jsonlite::read_json(file.path(source_dir,s$release))
    directory<-file.path(root,"months",month)
    # Copy only verified viewer files; working grids and decoded caches stay out.
    for(file in c(vapply(release$files,`[[`,character(1),"path"),s$release))
      july_pilot_copy(file.path(source_dir,file),file.path(directory,file))
    # Neighbour metadata supplies calendar views across month boundaries.
    # Report/hazard viewers have their own complete 30-day lookback per month.
    july_pilot_copy("scripts/daily-explorer-archive-assets/month-context.js",file.path(directory,"month-context.js"))
    html<-paste(readLines(file.path(directory,"index.html"),warn=FALSE),collapse="\n")
    html<-sub("</head>",'<script src="month-context.js"></script></head>',html,fixed=TRUE)
    writeLines(html,file.path(directory,"index.html"),useBytes=TRUE)
    for(file in c("explorer.js","storm-reports.js","hazards-explorer.js")) {
      path<-file.path(directory,file)
      if(!file.exists(path))next
      js<-paste(readLines(path,warn=FALSE),collapse="\n")
      if(file=="explorer.js") {
        js<-gsub("day.images?.[field] !==","SWCMonthContext.canonical(day.images?.[field]) !==",js,fixed=TRUE)
        js<-gsub("period.images?.[field] !==","SWCMonthContext.canonical(period.images?.[field]) !==",js,fixed=TRUE)
      }
      if(file=="storm-reports.js")js<-gsub("fetch(entry.path)","SWCMonthContext.fetchReport(entry.path)",js,fixed=TRUE)
      for(name in c("daily-data.json","circulation-manifest.json","circulation-means-manifest.json","storm-reports-manifest.json","hazard-timeline.json"))
        for(quote in c('"',"'"))js<-gsub(paste0("fetch(",quote,name,quote),paste0("SWCMonthContext.fetch(",quote,name,quote),js,fixed=TRUE)
      writeLines(js,path,useBytes=TRUE)
    }
    daily_archive_integrated_assets(directory)
    july_pilot_copy("scripts/daily-explorer-archive-assets/connected-frame.css",file.path(directory,"archive-frame.css"))
    html<-paste(readLines(file.path(directory,"index.html"),warn=FALSE),collapse="\n")
    html<-sub("</head>",'<link rel="stylesheet" href="archive-frame.css"></head>',html,fixed=TRUE)
    writeLines(html,file.path(directory,"index.html"),useBytes=TRUE)
    swc_cache_version_app(directory)
    frozen<-jsonlite::read_json(file.path(directory,s$release))
    files<-unique(c(vapply(frozen$files,`[[`,character(1),"path"),"archive-month-bridge.js","archive-frame.css","month-context.js",
      list.files(directory,pattern="^cache-assets[.]json$")))
    # Cache-versioned bridge is also part of the immutable viewer release.
    assets<-jsonlite::read_json(file.path(directory,"cache-assets.json"))$assets
    files<-unique(c(files,vapply(assets,`[[`,character(1),"file")))
    frozen$files<-unname(lapply(files,function(f)list(path=f,md5=unname(tools::md5sum(file.path(directory,f))))))
    jsonlite::write_json(frozen,file.path(directory,s$release),auto_unbox=TRUE,pretty=TRUE)
    validate_daily_explorer_july(directory,window=s$window)
    dates<-vapply(jsonlite::read_json(file.path(directory,"daily-data.json"))$days,`[[`,character(1),"date")
    list(month=month,water_year=2026L,dates=unname(as.list(dates)),path=paste0("months/",month,"/daily-data.json"),
      viewer=paste0("months/",month,"/index.html"),md5=unname(tools::md5sum(file.path(directory,"daily-data.json"))),full=TRUE,sample=FALSE)
  })
  catalog<-list(schema_version=1L,archive_pilot=TRUE,archive_integration_pilot=TRUE,wy2026_pilot=TRUE,
    latest=max(unlist(lapply(months,`[[`,"dates"))),months=unname(months))
  weather_write_json(catalog,file.path(root,"archive-catalog.json"))
  for(file in c("archive-model.js","archive-shell.js","archive-shell.css","integrated-index.html"))
    july_pilot_copy(file.path("scripts/daily-explorer-archive-assets",file),file.path(root,if(file=="integrated-index.html")"index.html"else file))
  html<-paste(readLines(file.path(root,"index.html"),warn=FALSE),collapse="\n")
  html<-sub("July 2025 includes weather, storm reports and NWS hazards. Other available months contain PRISM sample dates.",
    "WY2026 local archive: completed months include PRISM, daily and 7-/30-day weather, storm reports and archived NWS hazards. Unbuilt dates are unavailable.",html,fixed=TRUE)
  writeLines(html,file.path(root,"index.html"),useBytes=TRUE)
  swc_cache_version_app(root)
  # Explicit manifest excludes any stale month directories from an earlier preview.
  files<-c("index.html","archive-catalog.json","cache-assets.json")
  assets<-jsonlite::read_json(file.path(root,"cache-assets.json"))$assets
  files<-unique(c(files,vapply(assets,`[[`,character(1),"canonical"),vapply(assets,`[[`,character(1),"file")))
  for(month in ready) {
    s<-wy2026_explorer_source(month);r<-jsonlite::read_json(file.path(root,"months",month,s$release))
    files<-c(files,paste0("months/",month,"/",c(s$release,vapply(r$files,`[[`,character(1),"path"))))
  }
  release<-list(schema_version=1L,water_year=2026L,complete=length(ready)==12L,
    files=unname(lapply(unique(files),function(f)list(path=f,md5=unname(tools::md5sum(file.path(root,f)))))))
  weather_write_json(release,marker)
  validate_wy2026_explorer_navigation(root,require_complete)
  invisible(root)
}
validate_wy2026_explorer_navigation <- function(directory=file.path(wy2026_explorer_root(),"preview"),require_complete=TRUE) {
  release<-jsonlite::read_json(file.path(directory,"wy2026-release.json"))
  if(!identical(release$schema_version,1L)||!identical(release$water_year,2026L)||!length(release$files)||(require_complete&&!isTRUE(release$complete)))stop("Incomplete WY2026 navigation release.")
  for(f in release$files) {
    if(!nws_hazards_safe_path(f$path)||!file.exists(file.path(directory,f$path))||
      !identical(f$md5,unname(tools::md5sum(file.path(directory,f$path)))))stop("Changed/missing WY2026 preview asset: ",f$path)
  }
  c<-jsonlite::read_json(file.path(directory,"archive-catalog.json"))
  if(!identical(c$schema_version,1L)||!isTRUE(c$archive_pilot)||!isTRUE(c$wy2026_pilot)||!isTRUE(c$archive_integration_pilot)||!is.null(names(c$months)))stop("Wrong WY2026 catalog.")
  months<-vapply(c$months,`[[`,character(1),"month")
  if(anyDuplicated(months)||!identical(months,sort(months))||!all(months%in%names(wy2026_explorer_windows())))stop("Invalid WY2026 month list.")
  if(!identical(release$complete,length(months)==12L))stop("WY2026 completion marker mismatch.")
  dates<-character()
  for(m in c$months) {
    s<-wy2026_explorer_source(m$month)
    if(!identical(m$viewer,paste0("months/",m$month,"/index.html"))||!identical(m$path,paste0("months/",m$month,"/daily-data.json"))||
      !identical(m$water_year,2026L)||!isTRUE(m$full))stop("Invalid month route.")
    p<-jsonlite::read_json(file.path(directory,m$path));d<-vapply(p$days,`[[`,character(1),"date")
    w<-wy2026_explorer_windows()[[m$month]]
    expected<-as.character(seq(as.Date(w$start),as.Date(w$end),by="day"))
    if(!identical(d,expected)||!identical(d,unlist(m$dates,use.names=FALSE))||
      !identical(m$md5,unname(tools::md5sum(file.path(directory,m$path)))))stop("Month dates or digest mismatch.")
    validate_daily_explorer_july(dirname(file.path(directory,m$path)),window=s$window)
    dates<-c(dates,d)
  }
  if(anyDuplicated(dates)||!identical(c$latest,max(dates))||
    (require_complete&&!identical(dates,as.character(seq(as.Date("2025-10-01"),as.Date("2026-09-30"),by="day")))))stop("WY2026 date coverage mismatch.")
  swc_cache_validate_app(directory)
  result<-data.frame(status="PASS",months=length(months),dates=length(dates),maps=length(dates)*16L,
    viewer_bytes=sum(file.info(file.path(directory,vapply(release$files,`[[`,character(1),"path")))$size))
  print(result,row.names=FALSE);invisible(result)
}
