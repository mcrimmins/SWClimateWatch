# Local overlay of the connected Explorer. Existing archive and site files are read-only.
streamflow_explorer_root <- function()"data/diagnostics/daily-explorer-streamflow"
streamflow_explorer_sources <- function() {
  root<-connected_explorer_root();s<-readRDS(file.path(root,"sources.rds"))
  if(!identical(s$schema_version,2L))stop("Build the connected Explorer review first.")
  for(key in c("ui_hashes","current_hashes"))if(!identical(s[[key]],tools::md5sum(names(s[[key]]))))stop("Connected source changed; rebuild scripts/build-daily-explorer-connected.R first.")
  # Reuse previously accepted archive releases. Do not rescan tens of thousands
  # of immutable archive files for a small UI-only overlay; full checks remain
  # available in scripts/test-daily-explorer-connected.R before staging.
  for(a in s$archives)if(!identical(a$release_md5,unname(tools::md5sum(file.path(a$directory,a$marker)))))stop("Accepted archive release changed; rebuild connected navigation first.")
  s
}
build_streamflow_explorer <- function() {
  source("scripts/load-daily-explorer-connected.R",local=FALSE)
  streamflow_explorer_sources()
  source_root<-file.path(connected_explorer_root(),"preview")
  network<-"data/diagnostics/streamflow-network-pilot/viewer"
  if(!file.exists(file.path(network,"streamflow-data.json")))stop("Build the 32-gauge streamflow assessment first.")
  p<-jsonlite::read_json(file.path(network,"streamflow-data.json"))
  if(!isTRUE(p$network_assessment)||length(p$gauges)!=32L)stop("Expected a complete 32-gauge network snapshot.")
  root<-streamflow_explorer_root();dir.create(root,recursive=TRUE,showWarnings=FALSE)
  target<-file.path(root,"streamflow");dir.create(target,showWarnings=FALSE)
  files<-list.files(network,recursive=TRUE,full.names=FALSE)
  for(f in files){dir.create(dirname(file.path(target,f)),recursive=TRUE,showWarnings=FALSE);if(!file.copy(file.path(network,f),file.path(target,f),overwrite=TRUE))stop("Streamflow copy failed: ",f)}
  for(f in c("index.html","streamflow.js","streamflow.css","streamflow-model.js","streamflow-explorer-model.js"))
    if(!file.copy(file.path("scripts/streamflow-assets",f),file.path(target,f),overwrite=TRUE))stop("Missing streamflow UI: ",f)
  for(f in c("explorer-streamflow.js","explorer-streamflow.css"))file.copy(file.path("scripts/streamflow-assets",f),file.path(root,f),overwrite=TRUE)
  html<-paste(readLines(file.path(source_root,"index.html"),warn=FALSE),collapse="\n")
  controls<-paste0('<details id="streamflow-panel" class="card streamflow-panel"><summary>Streamflow</summary>',
    '<div class="streamflow-shared-controls"><label>View window<select id="streamflow-view-window"><option value="1">Selected day</option><option value="7">7 days</option><option value="30">30 days</option><option value="90">90 days · streamflow only</option></select></label>',
    '<label>Summary region<select id="streamflow-view-region"><option value="AZNM">Arizona + New Mexico</option><option value="AZ">Arizona</option><option value="NM">New Mexico</option></select></label></div>',
    '<p>Use the Explorer date controls above. Streamflow windows end on that date. The 7- and 30-day selections also update Map view; the 90-day window applies to Streamflow only.</p>',
    '<iframe id="streamflow-frame" title="Streamflow map, linked gauge table and hydrographs"></iframe></details>')
  writeLines(controls,file.path(root,"streamflow-panel.html"),useBytes=TRUE)
  html<-sub('</head>','<link rel="stylesheet" href="explorer-streamflow.css"><script src="explorer-streamflow.js" defer></script></head>',html,fixed=TRUE)
  writeLines(html,file.path(root,"index.html"),useBytes=TRUE)
  release_files<-c("index.html","streamflow-panel.html","explorer-streamflow.js","explorer-streamflow.css",paste0("streamflow/",list.files(target,recursive=TRUE)))
  hashes<-vapply(file.path(root,release_files),function(f)digest::digest(file=f,algo="sha256",serialize=FALSE),character(1))
  jsonlite::write_json(list(local_streamflow_explorer=TRUE,start=p$start,end=p$cutoff,gauges=32L,
    files=lapply(seq_along(release_files),function(i)list(path=release_files[i],sha256=hashes[i]))),file.path(root,"streamflow-release.json"),auto_unbox=TRUE,pretty=TRUE)
  validate_streamflow_explorer()
}
validate_streamflow_explorer <- function() {
  root<-streamflow_explorer_root();r<-jsonlite::read_json(file.path(root,"streamflow-release.json"))
  stopifnot(isTRUE(r$local_streamflow_explorer),r$gauges==32L,as.integer(as.Date(r$end)-as.Date(r$start))==89L)
  for(f in r$files){if(!grepl("^[A-Za-z0-9_./-]+$",f$path)||any(strsplit(f$path,"/",fixed=TRUE)[[1]]%in%c(".","..")))stop("Unsafe local release path.")
    path<-file.path(root,f$path);if(!file.exists(path)||!identical(f$sha256,digest::digest(file=path,algo="sha256",serialize=FALSE)))stop("Modified or missing Streamflow release asset: ",f$path)}
  p<-jsonlite::read_json(file.path(root,"streamflow/streamflow-data.json"))
  panel<-paste(readLines(file.path(root,"streamflow-panel.html"),warn=FALSE),collapse="\n")
  if(!grepl('<details id="streamflow-panel"',panel,fixed=TRUE)||grepl('<details[^>]* open',panel)||grepl('<iframe[^>]* src=',panel))stop("Streamflow section must start closed and unloaded.")
  for(g in p$gauges){d<-jsonlite::read_json(file.path(root,"streamflow",g$hydrograph));stopifnot(identical(d$id,g$id),length(d$rows)==90L,d$rows[[1]]$date==r$start,d$rows[[90]]$date==r$end)}
  result<-data.frame(status="PASS",gauges=length(p$gauges),start=r$start,end=r$end,requests=0L,
    copied_bytes=sum(file.info(file.path(root,vapply(r$files,`[[`,character(1),"path")))$size))
  print(result,row.names=FALSE);invisible(result)
}
streamflow_explorer_response <- function(req,sources=NULL) {
  root<-streamflow_explorer_root();path<-tryCatch(utils::URLdecode(req$PATH_INFO),error=function(e)"")
  if(!req$REQUEST_METHOD%in%c("GET","HEAD"))return(list(status=405L,headers=list(),body="Read-only local preview."))
  if(!is.character(path)||length(path)!=1L||!startsWith(path,"/")||!grepl("^/[A-Za-z0-9_./-]*$",path)||any(strsplit(sub("^/","",path),"/",fixed=TRUE)[[1]]%in%c("..",".")))return(list(status=400L,headers=list(),body="Invalid preview path."))
  relative<-sub("^/","",path);if(!nzchar(relative))relative<-"index.html"
  if(relative%in%c("index.html","streamflow-release.json","explorer-streamflow.js","explorer-streamflow.css")||startsWith(relative,"streamflow/")){
    f<-file.path(root,relative);if(!file.exists(f)||dir.exists(f))return(list(status=404L,headers=list(),body="Unavailable local asset."))
    types<-c(html="text/html; charset=utf-8",js="application/javascript; charset=utf-8",css="text/css; charset=utf-8",json="application/json",csv="text/csv",png="image/png")
    type<-unname(types[tolower(tools::file_ext(f))]);if(is.na(type))type<-"application/octet-stream"
    return(list(status=200L,headers=list("Content-Type"=type,"Cache-Control"="no-store"),body=if(req$REQUEST_METHOD=="HEAD")raw()else readBin(f,"raw",n=file.info(f)$size)))
  }
  if(is.null(sources))sources<-readRDS(file.path(connected_explorer_root(),"sources.rds"))
  result<-connected_explorer_response(req,sources=sources)
  # Adapt only the actual Explorer pages, not the nested hazard component.
  if(result$status==200L&&(relative=="current/index.html"||grepl("^archive/wy[0-9]{4}/months/[0-9]{4}-[0-9]{2}/index[.]html$",relative))){
    # HEAD uses the original headers; GET applies this small in-memory overlay.
    if(req$REQUEST_METHOD=="GET"){
      html<-if(is.raw(result$body))rawToChar(result$body)else result$body
      needle<-'<details id="storm-panel"'
      if(!grepl(needle,html,fixed=TRUE))needle<-'<details id="circulation-panel"'
      if(!grepl(needle,html,fixed=TRUE))stop("Inline Streamflow section hook needs review.")
      panel<-paste(readLines(file.path(root,"streamflow-panel.html"),warn=FALSE),collapse="\n")
      html<-sub(needle,paste0(panel,"\n",needle),html,fixed=TRUE,useBytes=TRUE)
      html<-sub('</head>','<link rel="stylesheet" href="/explorer-streamflow.css"><script src="/explorer-streamflow.js" defer></script></head>',html,fixed=TRUE,useBytes=TRUE)
      result$body<-charToRaw(html)
    }
  }
  result
}
serve_streamflow_explorer <- function(port=8807L) {
  source("scripts/load-daily-explorer-connected.R",local=FALSE)
  validate_streamflow_explorer();sources<-streamflow_explorer_sources()
  httpuv::startServer("127.0.0.1",port,list(call=function(req)streamflow_explorer_response(req,sources=sources)))
}
