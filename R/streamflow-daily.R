# Incremental observations reuse the reviewed metadata and approved statistics.
# Reference maintenance is deliberately separate from the daily request budget.
streamflow_daily_root <- function() "data/diagnostics/streamflow-daily"
streamflow_daily_enabled <- function() identical(tolower(Sys.getenv("SWC_STREAMFLOW")),"true")
streamflow_daily_guard <- function() {
  if(!identical(tolower(Sys.getenv("SWC_DAILY_CONNECTED")),"true"))stop("Streamflow requires the connected Daily Explorer.")
  source("R/daily-explorer-connected-publication.R",local=TRUE)
  connected_publication_guard(Sys.getenv("SWC_S3_DESTINATION"))
}
streamflow_snapshot_check <- function(directory) {
  p<-jsonlite::read_json(file.path(directory,"streamflow-data.json"))
  if(!isTRUE(p$network_assessment)||length(p$gauges)!=32L||anyDuplicated(vapply(p$gauges,`[[`,character(1),"id")))stop("Expected 32 distinct gauges.")
  if(as.integer(as.Date(p$cutoff)-as.Date(p$start))!=89L)stop("Expected a 90-day Streamflow snapshot.")
  for(g in p$gauges){
    if(!grepl("^[A-Za-z0-9_./-]+$",g$hydrograph)||any(strsplit(g$hydrograph,"/",fixed=TRUE)[[1]]%in%c("..",".")))stop("Unsafe hydrograph path.")
    d<-jsonlite::read_json(file.path(directory,g$hydrograph))
    dates<-vapply(d$rows,`[[`,character(1),"date")
    if(!identical(d$id,g$id)||!identical(dates,as.character(seq(as.Date(p$start),as.Date(p$cutoff),by="day"))))stop("Invalid gauge dates: ",g$id)
  }
  invisible(p)
}
streamflow_copy_snapshot <- function(from,to) {
  dir.create(to,recursive=TRUE,showWarnings=FALSE)
  for(f in list.files(from,recursive=TRUE)){
    dir.create(dirname(file.path(to,f)),recursive=TRUE,showWarnings=FALSE)
    if(!file.copy(file.path(from,f),file.path(to,f),overwrite=TRUE))stop("Cannot copy Streamflow snapshot: ",f)
  }
}
streamflow_seal_snapshot <- function(directory) {
  files<-setdiff(list.files(directory,recursive=TRUE),"snapshot-seal.json")
  jsonlite::write_json(lapply(files,function(f)list(path=f,sha256=digest::digest(file=file.path(directory,f),algo="sha256",serialize=FALSE))),
    file.path(directory,"snapshot-seal.json"),auto_unbox=TRUE,pretty=TRUE)
}
streamflow_verify_snapshot <- function(directory) {
  rows<-jsonlite::read_json(file.path(directory,"snapshot-seal.json"))
  if(!length(rows))stop("Missing Streamflow snapshot seal.")
  for(f in rows){
    if(!grepl("^[A-Za-z0-9_./-]+$",f$path)||any(strsplit(f$path,"/",fixed=TRUE)[[1]]%in%c("..",".")))stop("Unsafe snapshot path.")
    if(!identical(f$sha256,digest::digest(file=file.path(directory,f$path),algo="sha256",serialize=FALSE)))stop("Modified Streamflow snapshot: ",f$path)
  }
  streamflow_snapshot_check(directory)
}
update_streamflow_daily <- function(today=Sys.Date(),run=NULL) {
  if(!streamflow_daily_enabled())return(list(status="DISABLED"))
  streamflow_daily_guard()
  source("scripts/load-streamflow-network.R",local=TRUE)
  root<-streamflow_daily_root();dir.create(root,recursive=TRUE,showWarnings=FALSE)
  release<-file.path(root,"release");started<-Sys.time();note<-""
  if(is.null(run))run<-function()run_streamflow_network(as.Date(today)-1L,"incremental_live",TRUE,
    root=file.path(root,"candidate"),state_dir="data/diagnostics/streamflow-network-pilot/state")
  result<-tryCatch({
    result<-run();p<-streamflow_snapshot_check(result$viewer)
    if(!identical(p$cutoff,as.character(as.Date(today)-1L)))stop("Streamflow cutoff differs from requested completed day.")
    streamflow_seal_snapshot(result$viewer)
    streamflow_verify_snapshot(result$viewer)
    # Promote only a fully checked directory; preserve the previous snapshot.
    previous<-file.path(root,"previous")
    if(dir.exists(previous))unlink(previous,recursive=TRUE)
    if(dir.exists(release)&&!file.rename(release,previous))stop("Cannot preserve previous Streamflow snapshot.")
    if(!file.rename(result$viewer,release)){
      if(dir.exists(previous))file.rename(previous,release)
      stop("Cannot promote Streamflow snapshot.")
    }
    s<-result$summary
    list(status=if(isTRUE(s$complete_source_refresh))"READY"else"PARTIAL",requests=s$requests,cutoff=p$cutoff,gauges=length(p$gauges))
  },error=function(e){
    note<<-conditionMessage(e)
    p<-tryCatch(streamflow_verify_snapshot(release),error=function(e)NULL)
    list(status=if(is.null(p))"UNAVAILABLE"else"PARTIAL",requests=NA_integer_,
      cutoff=if(is.null(p))NA_character_ else p$cutoff,gauges=if(is.null(p))0L else length(p$gauges))
  })
  result$error<-note;result$seconds<-as.numeric(difftime(Sys.time(),started,units="secs"))
  result$checked_utc<-format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  write.csv(as.data.frame(result),file.path(root,"workflow-status.csv"),row.names=FALSE,na="")
  message(sprintf("Streamflow: %s; %d gauges through %s; %s requests (%.1fs). %s",result$status,result$gauges,result$cutoff,result$requests,result$seconds,note))
  result
}
stage_streamflow_connected <- function(output) {
  streamflow_daily_guard()
  source("R/site-cache.R",local=TRUE)
  release<-file.path(streamflow_daily_root(),"release")
  p<-streamflow_verify_snapshot(release)
  widget<-file.path(output,"streamflow");streamflow_copy_snapshot(release,widget)
  # The connected release seals the adapted widget; its source-only seal would
  # no longer describe the versioned presentation files below.
  unlink(file.path(widget,"snapshot-seal.json"))
  for(f in c("index.html","streamflow.js","streamflow.css","streamflow-model.js","streamflow-explorer-model.js"))
    if(!file.copy(file.path("scripts/streamflow-assets",f),file.path(widget,f),overwrite=TRUE))stop("Missing Streamflow browser asset.")
  f<-file.path(widget,"index.html");html<-rawToChar(readBin(f,"raw",n=file.info(f)$size))
  html<-sub("Southwest Climate Watch · Local pilot","Southwest Climate Watch",html,fixed=TRUE,useBytes=TRUE)
  html<-sub("AZ/NM streamflow · Local review","AZ/NM streamflow · Southwest Climate Watch",html,fixed=TRUE,useBytes=TRUE)
  writeBin(charToRaw(html),f)
  status<-read.csv(file.path(streamflow_daily_root(),"workflow-status.csv"),stringsAsFactors=FALSE)
  if(nrow(status)!=1L)stop("Invalid daily Streamflow status.")
  # The old cutoff and a conspicuous notice survive a failed source refresh.
  if(status$status!="READY"){
    f<-file.path(widget,"index.html");html<-rawToChar(readBin(f,"raw",n=file.info(f)$size))
    html<-sub("<body>",'<body><p role="status"><strong>Streamflow refresh incomplete.</strong> Showing the last verified observations; dates and missing values remain explicit. Retry is scheduled for the next daily run.</p>',html,fixed=TRUE,useBytes=TRUE)
    writeBin(charToRaw(html),f)
  }
  swc_cache_version_app(widget)
  names<-vapply(c("explorer-streamflow.js","explorer-streamflow.css"),function(f){
    src<-file.path("scripts/streamflow-assets",f);name<-sub("([.][^.]+)$",paste0(".swc-",substr(unname(tools::md5sum(src)),1,16),"\\1"),f)
    if(!file.copy(src,file.path(output,name),overwrite=TRUE))stop("Cannot stage Streamflow adapter.");name
  },character(1))
  panel<-paste0('<details id="streamflow-panel" class="card streamflow-panel"><summary>Streamflow</summary>',
    '<div class="streamflow-shared-controls"><label>View window<select id="streamflow-view-window"><option value="1">Selected day</option><option value="7" selected>7 days</option><option value="30">30 days</option><option value="90">90 days · streamflow only</option></select></label>',
    '<label>Summary region<select id="streamflow-view-region"><option value="AZNM">Arizona + New Mexico</option><option value="AZ">Arizona</option><option value="NM">New Mexico</option></select></label></div>',
    '<p>Streamflow windows end on the Explorer date. The 7- and 30-day selections also update Map view; 90 days applies only to Streamflow. Archived dates outside the retained flow window are unavailable.</p>',
    '<iframe id="streamflow-frame" title="Streamflow map, linked gauge table and hydrographs"></iframe></details>')
  pages<-list.files(output,pattern="index[.]html$",recursive=TRUE)
  pages<-pages[pages=="index.html"|grepl("^(current|months/[0-9]{4}-[0-9]{2})/index[.]html$",pages)]
  for(f in pages){
    path<-file.path(output,f);html<-rawToChar(readBin(path,"raw",n=file.info(path)$size))
    prefix<-if(f=="index.html")""else if(startsWith(f,"months/"))"../../../../connected/"else"connected/"
    if(f!="index.html"){
      needle<-'<details id="storm-panel"';if(!grepl(needle,html,fixed=TRUE))needle<-'<details id="circulation-panel"'
      if(!grepl(needle,html,fixed=TRUE))stop("Missing Streamflow section hook: ",f)
      html<-sub(needle,paste0(panel,"\n",needle),html,fixed=TRUE,useBytes=TRUE)
    }
    head<-paste0('<link rel="stylesheet" href="',prefix,names[2],'"><script src="',prefix,names[1],'" defer></script>')
    html<-sub("</head>",paste0(head,"</head>"),html,fixed=TRUE,useBytes=TRUE)
    writeBin(charToRaw(html),path)
  }
  jsonlite::write_json(list(schema_version=1L,start=p$start,cutoff=p$cutoff,gauges=32L,status=status$status),file.path(output,"streamflow-release.json"),auto_unbox=TRUE,pretty=TRUE)
  unique(c(pages,names,"streamflow-release.json",paste0("streamflow/",list.files(widget,recursive=TRUE))))
}
validate_streamflow_connected <- function(directory) {
  root<-file.path(directory,"connected")
  p<-streamflow_snapshot_check(file.path(root,"streamflow"))
  source("R/site-cache.R",local=TRUE);swc_cache_validate_app(file.path(root,"streamflow"))
  c<-jsonlite::read_json(file.path(root,"connected-catalog.json"))
  for(f in unique(c("index.html",vapply(c$months,`[[`,character(1),"viewer")))){
    path<-file.path(root,f);html<-rawToChar(readBin(path,"raw",n=file.info(path)$size))
    if(!grepl("explorer-streamflow.swc-",html,fixed=TRUE)||!grepl("</html>",html,fixed=TRUE)||
       (f!="index.html"&&!grepl('id="streamflow-panel"',html,fixed=TRUE)))stop("Missing standard Explorer Streamflow/navigation: ",f)
  }
  result<-data.frame(status="PASS",gauges=length(p$gauges),cutoff=p$cutoff,pages=length(unique(vapply(c$months,`[[`,character(1),"viewer"))))
  print(result,row.names=FALSE);invisible(result)
}
