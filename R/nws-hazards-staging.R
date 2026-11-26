# Guarded manual staging overlay. Daily hazard integration is a separate step.
nws_hazards_staging_guard <- function() {
  if(!identical(Sys.getenv("SWC_S3_DESTINATION"),"s3://cales-climate-reports/climate/watch-staging/")||
    !identical(Sys.getenv("SWC_PRODUCTION_STATE_DIR"),"/home/crimmins/.local/state/swclimatewatch-staging"))
    stop("NWS hazard trial requires the exact staging destination and state directory.")
  invisible(TRUE)
}

nws_hazards_safe_path <- function(path) {
  length(path)==1L&&!is.na(path)&&grepl("^[A-Za-z0-9_./-]+$",path)&&
    !startsWith(path,"/")&&!any(strsplit(path,"/",fixed=TRUE)[[1]]%in%c(".",".."))
}

validate_nws_hazards_publication <- function(directory) {
  source("R/nws-hazards-explorer.R",local=TRUE)
  source("R/storm-reports-staging.R",local=TRUE)
  source("R/site-cache.R",local=TRUE)
  payload<-jsonlite::read_json(file.path(directory,"daily-data.json"))
  if(!isTRUE(payload$publication_mode)||!isTRUE(payload$nws_hazards_enabled)||
    !isTRUE(payload$storm_reports_enabled)||isTRUE(payload$nws_hazards_preview))stop("Published hazard/report controls are not enabled.")
  release<-jsonlite::read_json(file.path(directory,"hazard-publication.json"))
  if(!identical(release$schema_version,1L)||!length(release$files))stop("Invalid hazard publication manifest.")
  for(file in release$files) {
    if(!nws_hazards_safe_path(file$path))stop("Unsafe hazard publication path.")
    path<-file.path(directory,file$path)
    if(!file.exists(path)||!identical(unname(tools::md5sum(path)),file$md5)||file.info(path)$size!=file$bytes)
      stop("Missing or modified hazard publication file: ",file$path)
  }
  catalog<-jsonlite::read_json(file.path(directory,"hazards/catalog.json"))
  if(length(catalog$cases)!=1L||!identical(catalog$cases[[1]]$path,"cases/explorer.json"))stop("Hazard publication must use the VM Explorer case.")
  data<-jsonlite::read_json(file.path(directory,"hazards/cases/explorer.json"))
  if(!identical(data$schema_version,1L)||!is.list(data$events)||!is.null(names(data$events)))stop("Hazard events must be an array.")
  dates<-vapply(payload$days,`[[`,character(1),"date")
  if(!identical(data$start,as.character(min(as.Date(dates))-1))||
    !identical(data$end_exclusive,as.character(max(as.Date(dates))+1)))stop("Hazard coverage does not match retained Explorer dates.")
  ids<-vapply(data$events,`[[`,character(1),"id");if(anyDuplicated(ids))stop("Duplicate hazard events.")
  pools<-lapply(data$geometry_bundles,function(path){
    if(!grepl("^bundles/[a-f0-9]{64}[.]json$",path))stop("Unsafe geometry bundle.")
    jsonlite::read_json(file.path(directory,"hazards",path))
  })
  for(e in data$events) {
    if(!is.null(names(e$segments))||!is.null(names(e$states))||!length(e$segments))stop("Hazard segment/state arrays invalid.")
    for(s in e$segments) {
      times<-as.POSIXct(c(s$start,s$end),format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
      if(anyNA(times)||times[1]>=times[2]||!is.null(names(s$states))||any(!unlist(s$states)%in%c("AZ","NM")))stop("Invalid hazard segment.")
      if(!is.null(s$geometry)) {
        if(!grepl("^[a-f0-9]{64}$",s$geometry))stop("Invalid geometry ID.")
        g<-pools[[substr(s$geometry,1,1)]][[s$geometry]]
        if(is.null(g)||!g$type%in%c("Polygon","MultiPolygon")||!is.list(g$coordinates)||!length(g$coordinates))stop("Missing or invalid hazard geometry.")
      }
      if(!is.null(s$tags)&&length(s$tags)) {
        for(key in c("wind_mph","hail_inches"))if(!is.null(s$tags[[key]])&&(!is.numeric(s$tags[[key]])||length(s$tags[[key]])!=1L||!is.finite(s$tags[[key]])||s$tags[[key]]<=0))stop("Invalid structured hazard magnitude.")
      }
    }
  }
  timeline<-jsonlite::read_json(file.path(directory,"hazard-timeline.json"))
  expected<-nws_hazards_timeline(data$events,dates,data$start,data$end_exclusive)
  # JSON normalization ensures integer/double and empty-array comparisons agree.
  canonical<-function(x)jsonlite::toJSON(x,auto_unbox=TRUE,null="null",digits=NA)
  if(!identical(canonical(timeline$timeline),canonical(expected)))stop("Hazard daily timing/region/type totals do not match event data.")
  html<-paste(readLines(file.path(directory,"index.html"),warn=FALSE),collapse="\n")
  if(!grepl('id="show-report-row" checked',html,fixed=TRUE)||!grepl('id="show-hazard-row" checked',html,fixed=TRUE)||
    !grepl('src="hazards/index.html?embedded=1"',html,fixed=TRUE))stop("Missing hazard/timeline controls.")
  swc_cache_validate_app(directory);swc_cache_validate_app(file.path(directory,"hazards"))
  validate_storm_reports_publication(directory)
  result<-data.frame(status="PASS",explorer_dates=length(dates),events=length(data$events),
    geometry_bundles=length(pools),cutoff=max(dates),directory=directory)
  print(result,row.names=FALSE);invisible(result)
}

stage_nws_hazards_staging <- function(directory="site/daily-explorer",
    work="data/diagnostics/nws-hazards-staging") {
  nws_hazards_staging_guard()
  stage_nws_hazards_snapshot(directory,work)
}

stage_nws_hazards_snapshot <- function(directory="site/daily-explorer",
    work="data/diagnostics/nws-hazards-staging",request_fun=NULL,coverage_note=NULL) {
  source("R/nws-hazards-explorer.R",local=TRUE)
  source("R/storm-reports-staging.R",local=TRUE)
  source("R/site-cache.R",local=TRUE)
  if(is.null(request_fun))request_fun<-nws_hazards_request
  validate_storm_reports_publication(directory)
  original<-jsonlite::read_json(file.path(directory,"daily-data.json"))
  reports<-jsonlite::read_json(file.path(directory,"storm-reports-manifest.json"))
  available<-Filter(function(d)d$status%in%c("READY","EMPTY"),reports$days)
  rows<-unname(unlist(lapply(available,function(d)jsonlite::read_json(file.path(directory,d$path))$reports),recursive=FALSE))
  if(is.null(rows))rows<-list()
  snapshot<-list(reports=rows,available_dates=vapply(available,`[[`,character(1),"date"),
    stale_dates=unlist(reports$stale_dates),snapshots=reports$snapshots)
  build_nws_hazards_explorer(source_dir=directory,output_dir=work,report_snapshot=snapshot,
    copy_maps=FALSE,full_window=TRUE,request_fun=request_fun)
  original$nws_hazards_preview<-NULL;original$nws_hazards_enabled<-TRUE
  jsonlite::write_json(original,file.path(work,"daily-data.json"),auto_unbox=TRUE,digits=NA,null="null")
  widget<-file.path(work,"hazards")
  html<-paste(readLines(file.path(widget,"index.html"),warn=FALSE),collapse="\n")
  html<-sub("NWS hazards · Southwest Climate Watch local review","Archived NWS hazards · Southwest Climate Watch",html,fixed=TRUE)
  html<-sub("Local review only.","Archive via IEM.",html,fixed=TRUE)
  if(!is.null(coverage_note)) {
    note<-coverage_note()
    if(nzchar(note)) {
      # The note is generated locally from counters, never from source text.
      html<-sub('<div class="controls">',paste0('<p id="hazard-data-status" role="status">',note,'</p><div class="controls">'),html,fixed=TRUE)
      root<-paste(readLines(file.path(work,"index.html"),warn=FALSE),collapse="\n")
      root<-sub('<iframe id="hazard-frame"',paste0('<p id="hazard-data-status" role="status">',note,'</p><iframe id="hazard-frame"'),root,fixed=TRUE)
      writeLines(root,file.path(work,"index.html"),useBytes=TRUE)
    }
  }
  writeLines(html,file.path(widget,"index.html"),useBytes=TRUE)
  if(tolower(Sys.getenv("SWC_DAILY_CONNECTED"))=="true") {
    source("R/daily-explorer-connected-publication.R",local=TRUE)
    connected_publication_guard()
    # The hazard/report assembler regenerates the outer HTML from canonical
    # assets. Apply the connected entry to that final output before sealing it.
    entry<-file.path(work,"index.html")
    writeLines(connected_publication_redirect(paste(readLines(entry,warn=FALSE),collapse="\n")),entry,useBytes=TRUE)
  }
  swc_cache_version_app(work);swc_cache_version_app(widget)
  assets<-function(path){x<-jsonlite::read_json(file.path(path,"cache-assets.json"));unique(c("index.html","cache-assets.json",
    vapply(x$assets,`[[`,character(1),"canonical"),vapply(x$assets,`[[`,character(1),"file")))}
  data<-jsonlite::read_json(file.path(widget,"cases/explorer.json"))
  files<-unique(c("daily-data.json","storm-reports-manifest.json","hazard-timeline.json",assets(work),
    "leaflet-package-LICENSE",paste0("images/",list.files(file.path(work,"images"))),
    vapply(available,`[[`,character(1),"path"),paste0("hazards/",c(assets(widget),"catalog.json","cases/explorer.json",
      "leaflet-package-LICENSE","workload.csv","view-workload.csv",unlist(data$geometry_bundles),paste0("images/",list.files(file.path(widget,"images")))))))
  if(!all(vapply(files,nws_hazards_safe_path,logical(1))))stop("Unsafe staging file list.")
  release_files<-setdiff(files,c("daily-data.json","storm-reports-manifest.json",vapply(available,`[[`,character(1),"path")))
  manifest<-list(schema_version=1L,files=unname(lapply(release_files,function(path)list(path=path,
    md5=unname(tools::md5sum(file.path(work,path))),bytes=file.info(file.path(work,path))$size))))
  jsonlite::write_json(manifest,file.path(work,"hazard-publication.json"),auto_unbox=TRUE,pretty=TRUE,null="null")
  validate_nws_hazards_publication(work)
  for(file in c(files,"hazard-publication.json")) {
    from<-file.path(work,file);to<-file.path(directory,file);dir.create(dirname(to),recursive=TRUE,showWarnings=FALSE)
    if(!file.exists(to)||!identical(unname(tools::md5sum(from)),unname(tools::md5sum(to))))
      if(!file.copy(from,to,overwrite=TRUE))stop("Cannot stage hazard file: ",file)
  }
  validate_nws_hazards_publication(directory)
  message("Verified NWS hazard staging overlay ready; existing weather payload and maps preserved.")
  invisible(TRUE)
}
