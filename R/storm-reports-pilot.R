# NWS Local Storm Report normalization, local review builder and viewer assets.
storm_reports_endpoint <- "https://mesonet.agron.iastate.edu/geojson/lsr.geojson"

storm_reports_output_path <- function(output_dir,source_dir) {
  root<-normalizePath("data/diagnostics",winslash="/",mustWork=TRUE)
  if(length(output_dir)!=1L||is.na(output_dir)||!nzchar(output_dir))stop("Use one pilot output directory.")
  if(any(strsplit(gsub("\\\\","/",output_dir),"/",fixed=TRUE)[[1]]%in%c(".","..")))
    stop("Pilot output path must not contain dot segments.")
  # Linux normalizePath(mustWork=FALSE) may leave nonexistent paths relative.
  # Resolve the nearest existing ancestor before checking containment, without
  # creating directories outside the permitted diagnostics tree.
  ancestor<-output_dir;pending<-character()
  while(!dir.exists(ancestor)) {
    if(file.exists(ancestor))stop("Pilot output path contains a file instead of a directory.")
    parent<-dirname(ancestor)
    if(identical(parent,ancestor))stop("Cannot resolve pilot output directory.")
    pending<-c(basename(ancestor),pending);ancestor<-parent
  }
  output<-do.call(file.path,as.list(c(normalizePath(ancestor,winslash="/",mustWork=TRUE),pending)))
  compare<-function(x)if(.Platform$OS.type=="windows")tolower(x)else x
  if(!startsWith(compare(output),paste0(compare(root),"/")))stop("Pilot output must be under data/diagnostics.")
  if(identical(compare(output),compare(normalizePath(source_dir,winslash="/",mustWork=TRUE))))
    stop("Use a separate pilot output directory.")
  output
}

storm_reports_timeline <- function(reports, dates, cached_dates,stale_dates=character()) {
  times<-as.POSIXct(vapply(reports,`[[`,character(1),"valid"),format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  setNames(lapply(c("prism","utc"),function(timing) lapply(dates,function(date) {
    end<-as.POSIXct(paste(date,if(timing=="prism")"12:00:00"else"00:00:00"),tz="UTC")
    if(timing=="utc")end<-end+86400
    begin<-end-86400
    needed<-unique(as.character(as.Date(c(begin,end-1),tz="UTC")))
    rows<-reports[which(times>=begin&times<end)]
    regions<-setNames(lapply(c("AZNM","AZ","NM"),function(region) {
      subset<-Filter(function(r)region=="AZNM"||r$state==region,rows)
      counts<-table(vapply(subset,`[[`,character(1),"type"))
      list(total=length(subset),types=as.list(setNames(as.integer(counts),names(counts))))
    }),c("AZNM","AZ","NM"))
    list(date=date,complete=all(needed%in%cached_dates),available=any(needed%in%cached_dates),
      stale=any(needed%in%stale_dates),regions=regions)
  })),c("prism","utc"))
}

normalize_storm_reports <- function(raw, start, end) {
  if (!identical(raw$type, "FeatureCollection") || is.null(raw$features))
    stop("Response is not a storm-report FeatureCollection.")
  start <- as.Date(start); end <- as.Date(end) # half-open UTC interval
  scalar <- function(x) if (is.null(x) || !length(x) || is.na(x[1])) "" else as.character(x[1])
  rows <- lapply(raw$features, function(f) {
    p <- f$properties
    if (!is.list(p)) stop("Storm report properties are malformed.")
    valid <- scalar(p$valid)
    time <- as.POSIXct(valid, format="%Y-%m-%dT%H:%M:%SZ", tz="UTC")
    if (is.na(time) || !grepl("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$",valid))
      stop("Storm report has an invalid UTC event timestamp.")
    if (time < as.POSIXct(start,tz="UTC") || time >= as.POSIXct(end,tz="UTC")) return(NULL)
    state <- toupper(scalar(p$state))
    if (!state %in% c("AZ","NM")) return(NULL)
    lat <- suppressWarnings(as.numeric(scalar(p$lat)))
    lon <- suppressWarnings(as.numeric(scalar(p$lon)))
    mapped <- is.finite(lat) && is.finite(lon) && abs(lat)<=90 && abs(lon)<=180
    mag <- scalar(p$magnitude); unit <- scalar(p$unit)
    if (mag %in% c("None","null","NaN","-9999")) mag <- ""
    qualifier <- scalar(p$qualifier)
    qualification <- switch(qualifier, M="Measured", E="Estimated", U="Unknown", "Not specified")
    # Feature ids are response row numbers, not stable event identifiers. Hash
    # all retained source fields, including text/product, for exact duplicates only.
    row <- list(valid=valid,date=substr(valid,1,10),type=scalar(p$typetext),
      magnitude=mag,unit=unit,qualifier=qualification,city=scalar(p$city),
      county=scalar(p$county),state=state,source=scalar(p$source),
      remark=scalar(p$remark),wfo=scalar(p$wfo),product_id=scalar(p$product_id),
      lat=if(mapped)lat else NULL,lon=if(mapped)lon else NULL,mapped=mapped)
    if (!nzchar(row$type)) stop("Storm report has no event type.")
    row$id <- digest::digest(row,algo="sha256",serialize=TRUE)
    row
  })
  rows <- Filter(Negate(is.null),rows)
  if(length(rows)) {
    rows <- rows[!duplicated(vapply(rows,`[[`,character(1),"id"))]
    rows <- rows[order(vapply(rows,`[[`,character(1),"valid"),vapply(rows,`[[`,character(1),"id"))]
  }
  rows
}

storm_reports_archive_request <- function(start,end,
    timeout=getOption("swc.storm_reports.timeout",45),
    max_tries=getOption("swc.storm_reports.max_tries",1L)) {
  if(!is.numeric(timeout)||length(timeout)!=1L||!is.finite(timeout)||timeout<1||timeout>180||
     !is.numeric(max_tries)||length(max_tries)!=1L||is.na(max_tries)||!max_tries%in%1:3)
    stop("Bound report requests to 1-180 seconds and 1-3 attempts.")
  httr2::request(storm_reports_endpoint)|>
    httr2::req_url_query(sts=paste0(start,"T00:00Z"),ets=paste0(end,"T00:00Z"),states="AZ,NM")|>
    httr2::req_user_agent("SWClimateWatch local storm report pilot")|>
    httr2::req_timeout(timeout)|>
    httr2::req_retry(max_tries=max_tries,retry_on_failure=TRUE)
}

read_storm_reports_cache <- function(start, end, refresh=FALSE,
    cache_dir="data/raw/storm-reports/az-nm") {
  start<-as.Date(start);end<-as.Date(end)
  if(is.na(start)||is.na(end)||end<=start||end-start>62)stop("Use a report window of 1–62 UTC days.")
  dir.create(cache_dir,recursive=TRUE,showWarnings=FALSE)
  path<-file.path(cache_dir,paste0(start,"_",end,".rds"))
  previous<-if(file.exists(path))tryCatch(readRDS(path),error=function(e)NULL)else NULL
  if(!is.null(previous) && !refresh) {
    if(!identical(previous$start,as.character(start))||!identical(previous$end,as.character(end))||
        is.null(previous$fetched_utc)||is.null(previous$url))stop("Report cache metadata mismatch; refresh the pilot cache.")
    normalize_storm_reports(previous$raw,start,end)
    return(previous)
  }
  request<-storm_reports_archive_request(start,end)
  message("Storm reports: ",start," to ",end," (end excluded); fetching uncached range.")
  # A failed refresh does not overwrite the last good cache or become an empty day.
  response<-httr2::req_perform(request)
  raw<-httr2::resp_body_json(response,simplifyVector=FALSE)
  normalize_storm_reports(raw,start,end)
  result<-list(raw=raw,start=as.character(start),end=as.character(end),
    fetched_utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),url=request$url)
  temporary<-tempfile(tmpdir=cache_dir);on.exit(unlink(temporary),add=TRUE)
  saveRDS(result,temporary)
  if(!file.copy(temporary,path,overwrite=TRUE))stop("Could not save report cache.")
  result
}

build_storm_reports_pilot <- function(source_dir="site/daily-explorer",
    output_dir="data/diagnostics/daily-explorer-storm-reports",refresh=FALSE,
    copy_maps=TRUE,full_window=FALSE,snapshot=NULL,lookback_days=1L) {
  if(length(lookback_days)!=1L||is.na(lookback_days)||!lookback_days%in%1:30)stop("Bound report lookback to 1-30 days.")
  output_dir<-storm_reports_output_path(output_dir,source_dir)
  payload<-jsonlite::read_json(file.path(source_dir,"daily-data.json"))
  dates<-vapply(payload$days,`[[`,character(1),"date")
  start<-min(as.Date(dates));end<-max(as.Date(dates))+1
  # Bound the first source trial; older Explorer dates explicitly say unavailable.
  if(!full_window)start<-max(start,end-62)
  if(end-start>400)stop("Storm report trial is bounded to 400 Explorer dates.")
  if(is.null(snapshot)) {
    starts<-seq(start,end-1,by=62)
    caches<-lapply(starts,function(first)read_storm_reports_cache(first,min(first+62,end),refresh))
    cache<-caches[[1]]
    reports<-unlist(lapply(caches,function(x)normalize_storm_reports(x$raw,x$start,x$end)),recursive=FALSE)
    padding<-read_storm_reports_cache(start-lookback_days,start,refresh)
    reports<-c(normalize_storm_reports(padding$raw,start-lookback_days,start),reports)
    snapshots<-lapply(c(list(padding),caches),function(x)x[c("start","end","fetched_utc","url")])
    available_dates<-as.character(seq(start-lookback_days,end-1,by="day"));stale_dates<-character()
  } else {
    reports<-snapshot$reports;snapshots<-snapshot$snapshots
    available_dates<-snapshot$available_dates;stale_dates<-snapshot$stale_dates
  }
  if(is.null(reports))reports<-list()
  dir.create(file.path(output_dir,"reports"),recursive=TRUE,showWarnings=FALSE)
  copy<-function(from,to) {
    dir.create(dirname(to),recursive=TRUE,showWarnings=FALSE)
    if(!file.exists(from))stop("Missing pilot resource: ",from)
    if(file.exists(to)&&identical(unname(tools::md5sum(from)),unname(tools::md5sum(to))))return(invisible())
    if(!file.copy(from,to,overwrite=TRUE))stop("Cannot copy pilot resource: ",from)
  }
  # Only this isolated preview gets the report module and selection bridge.
  for(asset in c("index.html","explorer.css","explorer.js"))
    copy(file.path("scripts/daily-explorer-assets",asset),file.path(output_dir,asset))
  for(asset in c("storm-reports.js","report-view-stats.js","storm-reports.css","storm-reports-panel.html"))
    copy(file.path("scripts/storm-reports-assets",asset),file.path(output_dir,asset))
  for(asset in c("leaflet.js","leaflet.css","leaflet-package-LICENSE"))
    copy(file.path("site/stations",asset),file.path(output_dir,asset))
  leaflet_images<-list.files(file.path(find.package("leaflet"),"htmlwidgets/lib/leaflet/images"),full.names=TRUE)
  for(image in leaflet_images)copy(image,file.path(output_dir,"images",basename(image)))
  images<-unique(unlist(lapply(payload$days,function(d)unlist(d$images,use.names=FALSE))))
  if(any(!grepl("^maps/[0-9-]+-(pcpn|maxt|mint|tmean)-(observed|departure)\\.png$",images)))stop("Unexpected Explorer map path.")
  if(copy_maps)for(image in images)copy(file.path(source_dir,image),file.path(output_dir,image))
  payload$publication_mode<-FALSE
  payload$circulation_enabled<-FALSE;payload$circulation_period_means_enabled<-FALSE
  payload$storm_reports_preview<-TRUE
  payload$local_review_note<-"Local storm report pilot: dates and region follow Daily Explorer. Weather means are omitted from this isolated review; no publication or daily-run changes."
  jsonlite::write_json(payload,file.path(output_dir,"daily-data.json"),auto_unbox=TRUE,digits=NA,null="null")
  html<-paste(readLines(file.path(output_dir,"index.html"),warn=FALSE),collapse="\n")
  panel<-paste(readLines("scripts/storm-reports-assets/storm-reports-panel.html",warn=FALSE),collapse="\n")
  html<-sub('<details id="circulation-panel"',paste0(panel,'\n<details id="circulation-panel"'),html,fixed=TRUE)
  html<-sub('</head>','<link rel="stylesheet" href="leaflet.css"><link rel="stylesheet" href="storm-reports.css"><script src="leaflet.js" defer></script><script src="report-view-stats.js" defer></script><script src="storm-reports.js" defer></script></head>',html,fixed=TRUE)
  html<-sub("The summary-region selector changes the timeline, statistics, and notable-day list.",
    "The summary-region selector changes the timeline, statistics, notable-day list and storm-report map/table.",html,fixed=TRUE)
  html<-sub('<div id="timeline"',paste0('<p id="storm-timeline-note" class="muted small">Loading daily report counts…</p><div id="storm-timeline-legend" class="storm-legend"></div>\n<div id="timeline"'),html,fixed=TRUE)
  html<-sub('  </section>\n  <section class="card map-card"',
    '    <p id="storm-timeline-detail" class="muted small" aria-live="polite">Hover or focus a day for report counts by type. Select a bar to explore that day.</p>\n  </section>\n  <section class="card map-card"',html,fixed=TRUE)
  writeLines(html,file.path(output_dir,"index.html"),useBytes=TRUE)
  js<-paste(readLines(file.path(output_dir,"explorer.js"),warn=FALSE),collapse="\n")
  hook<-'renderCirculation();\n  document.dispatchEvent(new CustomEvent("swc:daily-selection", {detail:{date:selectedDate,region:$("region").value}}));'
  needle<-"renderNotable(); renderCirculation();"
  if(!grepl(needle,js,fixed=TRUE))stop("Explorer selection bridge needs review.")
  js<-sub(needle,paste0("renderNotable(); ",hook),js,fixed=TRUE)
  js<-sub('button.type = "button"; button.className = `day',
    'button.dataset.reportDate = date; button.type = "button"; button.className = `day',js,fixed=TRUE)
  js<-paste(js,'document.addEventListener("swc:request-date", e => { if (typeof e.detail?.date === "string" && inCachedDateRange(e.detail.date)) selectDate(e.detail.date); else document.dispatchEvent(new CustomEvent("swc:daily-selection", {detail:{date:selectedDate,region:$("region").value}})); });',sep="\n")
  js<-paste(js,'document.addEventListener("swc:request-selection", () => { if (selectedDate) document.dispatchEvent(new CustomEvent("swc:daily-selection", {detail:{date:selectedDate,region:$("region").value}})); });',sep="\n")
  writeLines(js,file.path(output_dir,"explorer.js"),useBytes=TRUE)
  report_dates<-as.character(seq(start-lookback_days,end-1,by="day"))
  entries<-lapply(report_dates,function(date) {
    rows<-Filter(function(r)r$date==date,reports)
    if(is.null(rows))rows<-list()
    file<-paste0("reports/",date,".json")
    if(!date%in%available_dates)return(list(date=date,status="UNAVAILABLE",reports=0L,path=file,md5=NULL))
    jsonlite::write_json(list(schema_version=1L,date=date,reports=unname(rows)),file.path(output_dir,file),auto_unbox=TRUE,digits=NA,null="null")
    list(date=date,status=if(length(rows))"READY"else"EMPTY",reports=length(rows),path=file,
      md5=unname(tools::md5sum(file.path(output_dir,file))))
  })
  manifest<-list(schema_version=1L,source="NWS Local Storm Reports via Iowa Environmental Mesonet",
    fetched_utc=if(length(snapshots))min(vapply(snapshots,`[[`,character(1),"fetched_utc"))else "Unavailable",
    query_url=storm_reports_endpoint,snapshots=snapshots,stale_dates=as.list(stale_dates),
    start=as.character(start-lookback_days),end_exclusive=as.character(end),days=entries,
    timeline=storm_reports_timeline(reports,dates,available_dates,stale_dates))
  jsonlite::write_json(manifest,file.path(output_dir,"storm-reports-manifest.json"),auto_unbox=TRUE,pretty=TRUE,null="null")
  summary<-data.frame(dates=length(entries),reports=length(reports),mapped=sum(vapply(reports,`[[`,logical(1),"mapped")),
    first=start-lookback_days,last=end-1,explorer_first=start,publication=FALSE)
  write.csv(summary,file.path(output_dir,"storm-reports-summary.csv"),row.names=FALSE)
  print(summary,row.names=FALSE)
  invisible(summary)
}
