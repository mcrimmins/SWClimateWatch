# Local-only combination of the existing Explorer/report pilot and WWA viewer.
source("R/nws-hazards-pilot.R")

nws_hazards_timeline <- function(events,dates,start,end) {
  segments<-unlist(lapply(events,`[[`,"segments"),recursive=FALSE)
  index<-rep(seq_along(events),lengths(lapply(events,`[[`,"segments")))
  begins<-as.numeric(as.POSIXct(vapply(segments,`[[`,character(1),"start"),format="%Y-%m-%dT%H:%M:%SZ",tz="UTC"))
  ends<-as.numeric(as.POSIXct(vapply(segments,`[[`,character(1),"end"),format="%Y-%m-%dT%H:%M:%SZ",tz="UTC"))
  titles<-vapply(events,`[[`,character(1),"title")
  setNames(lapply(c("prism","utc"),function(timing)lapply(dates,function(date){
    finish<-as.numeric(as.POSIXct(paste(date,if(timing=="prism")"12:00:00"else"00:00:00"),tz="UTC"))+if(timing=="utc")86400 else 0
    begin<-finish-86400
    regions<-setNames(lapply(c("AZNM","AZ","NM"),function(region){
      keep<-begins<finish&ends>begin
      if(region!="AZNM")keep<-keep&vapply(segments,function(s)region%in%unlist(s$states),logical(1))
      found<-unique(index[keep]);counts<-table(titles[found])
      list(total=length(found),types=as.list(setNames(as.integer(counts),names(counts))))
    }),c("AZNM","AZ","NM"))
    list(date=date,complete=begin>=as.numeric(as.POSIXct(as.Date(start),tz="UTC"))&&finish<=as.numeric(as.POSIXct(as.Date(end),tz="UTC")),
      available=finish>as.numeric(as.POSIXct(as.Date(start),tz="UTC"))&&begin<as.numeric(as.POSIXct(as.Date(end),tz="UTC")),regions=regions)
  })),c("prism","utc"))
}

build_nws_hazards_explorer <- function(source_dir="site/daily-explorer",
    output_dir="data/diagnostics/daily-explorer-nws-hazards",refresh=FALSE,
    report_snapshot=NULL,copy_maps=TRUE,full_window=FALSE,request_fun=nws_hazards_request,lookback_days=1L) {
  if(length(lookback_days)!=1L||is.na(lookback_days)||!lookback_days%in%1:30)stop("Bound hazard lookback to 1-30 days.")
  source("R/storm-reports-pilot.R",local=TRUE)
  output_dir<-storm_reports_output_path(output_dir,source_dir)
  payload<-jsonlite::read_json(file.path(source_dir,"daily-data.json"))
  dates<-vapply(payload$days,`[[`,character(1),"date")
  if(length(dates)>400L)stop("Hazard Explorer build is bounded to 400 retained dates.")
  start<-if(full_window)min(as.Date(dates))-lookback_days else max(min(as.Date(dates)),max(as.Date(dates))-61)-lookback_days
  end<-max(as.Date(dates))+1
  starts<-seq(start,end-1,by=31)
  cases<-data.frame(id=paste0("part-",seq_along(starts)),label=paste("Explorer archive",seq_along(starts)),
    start=as.character(starts),end=as.character(pmin(starts+31,end)))
  # Keep the report builder's normal bounded cache semantics and canonical assets.
  build_storm_reports_pilot(source_dir=source_dir,output_dir=output_dir,refresh=refresh,
    snapshot=report_snapshot,copy_maps=copy_maps,full_window=full_window,lookback_days=lookback_days)
  widget<-file.path(output_dir,"hazards")
  assessment<-build_nws_hazards_pilot(cases=cases,refresh=refresh,output_dir=widget,request_fun=request_fun)
  events<-list();geometries<-list()
  for(case in cases$id) {
    x<-jsonlite::read_json(file.path(widget,"cases",paste0(case,".json")))
    for(e in x$events) {
      existing<-events[[e$id]]
      if(is.null(existing))events[[e$id]]<-e else {
        existing$segments<-c(existing$segments,e$segments)
        keys<-vapply(existing$segments,digest::digest,character(1),algo="sha256")
        existing$segments<-unname(existing$segments[!duplicated(keys)])
        existing$states<-unname(as.list(sort(unique(unlist(c(existing$states,e$states))))))
        events[[e$id]]<-existing
      }
    }
    for(path in unlist(x$geometry_bundles))geometries<-modifyList(geometries,jsonlite::read_json(file.path(widget,path)))
  }
  # Prefer storm geometry globally even if a different chunk only had county rows.
  events<-unname(lapply(events,function(e){
    if(any(vapply(e$segments,function(s)!nzchar(s$zone),logical(1)))) {
      e$segments<-unname(Filter(function(s)!nzchar(s$zone),e$segments));e$geometry_type<-"Storm polygon"
    };e
  }))
  bundles<-list()
  for(prefix in unique(substr(names(geometries),1,1))) {
    pool<-geometries[substr(names(geometries),1,1)==prefix]
    path<-paste0("bundles/",digest::digest(pool,algo="sha256"),".json")
    jsonlite::write_json(pool,file.path(widget,path),auto_unbox=TRUE,digits=6,null="null");bundles[[prefix]]<-path
  }
  metadata<-list(schema_version=1L,id="explorer",start=as.character(start),end_exclusive=as.character(end),
    geometry_bundles=bundles,events=events)
  jsonlite::write_json(metadata,file.path(widget,"cases/explorer.json"),auto_unbox=TRUE,digits=6,null="null")
  stats<-assessment$summary[1,]
  for(column in names(stats)[vapply(stats,is.numeric,logical(1))])stats[[column]]<-sum(assessment$summary[[column]])
  stats$case<-"explorer";stats$start<-as.character(start);stats$end_exclusive<-as.character(end)
  stats$processed_reused<-all(assessment$summary$processed_reused);stats$events<-length(events)
  stats$unique_geometries<-length(geometries)
  bytes<-readBin(file.path(widget,"cases/explorer.json"),"raw",n=file.info(file.path(widget,"cases/explorer.json"))$size)
  stats$metadata_bytes<-length(bytes);stats$metadata_gzip_bytes<-length(memCompress(bytes,"gzip"))
  stats$geometry_bytes<-sum(vapply(geometries,function(g)nchar(jsonlite::toJSON(g,auto_unbox=TRUE,digits=6,null="null"),type="bytes"),numeric(1)))
  jsonlite::write_json(list(schema_version=1L,pilot=TRUE,cases=list(list(id="explorer",label="Daily Explorer dates",start=as.character(start),end_exclusive=as.character(end),
    events=length(events),path="cases/explorer.json")),workload=list(as.list(stats[1,]))),file.path(widget,"catalog.json"),auto_unbox=TRUE,null="null")
  timeline<-list(schema_version=1L,start=as.character(start),end_exclusive=as.character(end),
    types=unname(lapply(events[!duplicated(vapply(events,`[[`,character(1),"title"))],function(e)e[c("title","phenomenon","significance")])),
    timeline=nws_hazards_timeline(events,dates,start,end))
  jsonlite::write_json(timeline,file.path(output_dir,"hazard-timeline.json"),auto_unbox=TRUE,null="null")
  for(asset in c("hazards-explorer.js","hazards-explorer.css"))
    file.copy(file.path("scripts/nws-hazards-assets",asset),file.path(output_dir,asset),overwrite=TRUE)
  file.copy("scripts/nws-hazards-assets/hazard-model.js",file.path(output_dir,"hazard-model.js"),overwrite=TRUE)
  html<-paste(readLines(file.path(output_dir,"index.html"),warn=FALSE),collapse="\n")
  html<-sub('</head>','<link rel="stylesheet" href="hazards-explorer.css"><script src="hazard-model.js" defer></script><script src="hazards-explorer.js" defer></script></head>',html,fixed=TRUE)
  html<-sub('<details id="circulation-panel"',paste0('<details class="card" id="hazard-panel" open><summary>NWS watches, warnings and advisories</summary><p class="muted small">Archived hazards active during the selected window. Date, region and event timing are linked with the Explorer and storm reports. These are issued hazards, not observed impacts.</p><iframe id="hazard-frame" src="hazards/index.html?embedded=1" title="Archived NWS hazard map and linked table" style="width:100%;height:1200px;border:0" loading="lazy"></iframe></details>\n<details id="circulation-panel"'),html,fixed=TRUE)
  html<-sub('<p id="storm-timeline-note"',paste0('<div class="event-row-controls"><label><input type="checkbox" id="show-report-row" checked> Storm reports</label><label><input type="checkbox" id="show-hazard-row" checked> NWS hazards</label><span class="muted small">Daily counts below the weather bars</span></div><details class="event-legend"><summary>Event colors and counting</summary><p>Rows count observed reports and unique active VTEC hazard events separately. Multi-day hazards appear on each active day; zone pieces and updates do not increase event counts. ? means unavailable; + means partial coverage. Hazard colors match the hazard map and stats panel.</p><div id="hazard-timeline-legend"></div></details>\n<p id="storm-timeline-note"'),html,fixed=TRUE)
  html<-sub('<div id="storm-timeline-legend" class="storm-legend"></div>','',html,fixed=TRUE)
  html<-sub('</details>\n<p id="storm-timeline-note"','<div id="storm-timeline-legend" class="storm-legend"></div></details>\n<p id="storm-timeline-note"',html,fixed=TRUE)
  html<-sub('<div id="timeline" class="timeline" role="group" aria-label="Daily values; select a date"></div>',
    '<div class="event-timeline-layout"><div class="event-row-labels" aria-hidden="true"><span>Reports</span><span>Hazards</span></div><div id="timeline" class="timeline" role="group" aria-label="Daily weather, report and hazard counts; select a date"></div></div>',html,fixed=TRUE)
  html<-sub('<p id="storm-timeline-detail"','<p id="hazard-timeline-detail" class="muted small" aria-live="polite">Loading daily hazard counts…</p><p id="storm-timeline-detail"',html,fixed=TRUE)
  writeLines(html,file.path(output_dir,"index.html"),useBytes=TRUE)
  payload<-jsonlite::read_json(file.path(output_dir,"daily-data.json"));payload$nws_hazards_preview<-TRUE
  payload$local_review_note<-"Local Explorer review: storm reports and archived NWS hazards. No site publication or daily-runner integration."
  jsonlite::write_json(payload,file.path(output_dir,"daily-data.json"),auto_unbox=TRUE,digits=NA,null="null")
  source("R/site-cache.R",local=TRUE)
  swc_cache_version_app(output_dir)
  message("Local Explorer + reports + hazards ready: ",output_dir)
  invisible(list(summary=stats,output_dir=output_dir))
}
