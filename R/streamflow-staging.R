# Isolated static trial. The standard Explorer, accepted archives and daily flags stay intact.
streamflow_staging_guard <- function() {
  if(!identical(Sys.getenv("SWC_S3_DESTINATION"),"s3://cales-climate-reports/climate/watch-staging/")||
     !identical(Sys.getenv("SWC_PRODUCTION_STATE_DIR"),"/home/crimmins/.local/state/swclimatewatch-staging")||
     !identical(normalizePath(".",winslash="/",mustWork=TRUE),"/home/crimmins/RProjects/SWClimateWatch-staging"))stop("Streamflow trial requires the dedicated staging checkout, destination and state directory.")
  invisible(TRUE)
}
streamflow_trial_default <- function()"data/diagnostics/streamflow-staging/viewer"
stage_streamflow_trial <- function(source_dir="site/_site/daily-explorer",output=streamflow_trial_default(),require_staging=TRUE) {
  if(require_staging)streamflow_staging_guard()
  if(!grepl("^data/diagnostics/[A-Za-z0-9_/-]+$",output)||any(strsplit(output,"/",fixed=TRUE)[[1]]%in%c(".","..")))stop("Trial output must be under data/diagnostics.")
  source("scripts/load-daily-explorer-connected.R",local=FALSE)
  source("R/daily-explorer-connected-staging.R",local=FALSE)
  source("R/streamflow-explorer.R",local=FALSE)
  source("R/site-cache.R",local=FALSE)
  validate_connected_static(source_dir)
  original<-file.path(source_dir,"connected");network<-"data/diagnostics/streamflow-network-pilot/viewer"
  p<-jsonlite::read_json(file.path(network,"streamflow-data.json"))
  if(!isTRUE(p$network_assessment)||length(p$gauges)!=32L)stop("Build the complete 32-gauge snapshot first.")
  dir.create(output,recursive=TRUE,showWarnings=FALSE)
  # Copy the tiny shell and HTML entry pages only. Its base URLs continue to
  # refer to already-published current maps and archive assets beside this trial.
  files<-list.files(original,recursive=TRUE)
  selected<-files[grepl("^[^/]+[.](js|css|json)$",files)&!files%in%c("connected-release.json","cache-assets.json")]
  selected<-c(selected,"index.html",files[grepl("^(current|months/[0-9]{4}-[0-9]{2})/index[.]html$",files)])
  for(f in selected){dir.create(dirname(file.path(output,f)),recursive=TRUE,showWarnings=FALSE);if(!file.copy(file.path(original,f),file.path(output,f),overwrite=TRUE))stop("Cannot copy trial shell: ",f)}
  for(f in c("explorer-streamflow.js","explorer-streamflow.css"))file.copy(file.path("scripts/streamflow-assets",f),file.path(output,f),overwrite=TRUE)
  widget<-file.path(output,"streamflow");dir.create(widget,showWarnings=FALSE)
  for(f in list.files(network,recursive=TRUE)){dir.create(dirname(file.path(widget,f)),recursive=TRUE,showWarnings=FALSE);if(!file.copy(file.path(network,f),file.path(widget,f),overwrite=TRUE))stop("Cannot copy gauge snapshot.")}
  for(f in c("index.html","streamflow.js","streamflow.css","streamflow-model.js","streamflow-explorer-model.js"))file.copy(file.path("scripts/streamflow-assets",f),file.path(widget,f),overwrite=TRUE)
  swc_cache_version_app(widget)
  # Version the overlay independently; accepted connected seals are untouched.
  hashed<-vapply(c("explorer-streamflow.js","explorer-streamflow.css"),function(f){
    h<-substr(unname(tools::md5sum(file.path(output,f))),1,16);name<-sub("([.][^.]+)$",paste0(".swc-",h,"\\1"),f)
    file.copy(file.path(output,f),file.path(output,name),overwrite=TRUE);name
  },character(1))
  # Reuse the local section template without depending on the laptop's connected sources.
  panel<-paste0('<details id="streamflow-panel" class="card streamflow-panel"><summary>Streamflow</summary>',
    '<div class="streamflow-shared-controls"><label>View window<select id="streamflow-view-window"><option value="1">Selected day</option><option value="7" selected>7 days</option><option value="30">30 days</option><option value="90">90 days · streamflow only</option></select></label>',
    '<label>Summary region<select id="streamflow-view-region"><option value="AZNM">Arizona + New Mexico</option><option value="AZ">Arizona</option><option value="NM">New Mexico</option></select></label></div>',
    '<p>Use the Explorer date controls above. Streamflow windows end on that date. The 7- and 30-day selections also update Map view; the 90-day window applies to Streamflow only.</p>',
    '<iframe id="streamflow-frame" title="Streamflow map, linked gauge table and hydrographs"></iframe></details>')
  read<-function(f){x<-rawToChar(readBin(f,"raw",n=file.info(f)$size));x}
  head<-function(prefix)paste0('<link rel="stylesheet" href="',prefix,hashed[2],'"><script src="',prefix,hashed[1],'" defer></script>')
  for(f in selected[grepl("[.]html$",selected)]){
    html<-read(file.path(output,f))
    if(f=="index.html")prefix<-"" else {
      prefix<-paste0(if(startsWith(f,"months/"))"../../../../"else"","streamflow-trial/")
      needle<-'<details id="storm-panel"';if(!grepl(needle,html,fixed=TRUE))needle<-'<details id="circulation-panel"'
      if(!grepl(needle,html,fixed=TRUE))stop("Missing inline trial hook: ",f)
      html<-sub(needle,paste0(panel,"\n",needle),html,fixed=TRUE,useBytes=TRUE)
    }
    html<-sub("</head>",paste0(head(prefix),"</head>"),html,fixed=TRUE,useBytes=TRUE)
    writeBin(charToRaw(html),file.path(output,f))
  }
  all<-list.files(output,recursive=TRUE);all<-setdiff(all,"streamflow-staging-release.json")
  release<-list(schema_version=1L,staging_only=TRUE,start=p$start,end=p$cutoff,gauges=32L,
    code_commit=Sys.getenv("SWC_STREAMFLOW_COMMIT",""),
    source_seal=digest::digest(file=file.path(original,"connected-release.json"),algo="sha256",serialize=FALSE),
    files=lapply(all,function(f)list(path=f,sha256=digest::digest(file=file.path(output,f),algo="sha256",serialize=FALSE))))
  jsonlite::write_json(release,file.path(output,"streamflow-staging-release.json"),auto_unbox=TRUE,pretty=TRUE)
  validate_streamflow_trial(output,source_dir)
}
validate_streamflow_trial <- function(directory=streamflow_trial_default(),source_dir="site/_site/daily-explorer") {
  m<-jsonlite::read_json(file.path(directory,"streamflow-staging-release.json"))
  if(!identical(m$schema_version,1L)||!isTRUE(m$staging_only)||m$gauges!=32L)stop("Invalid Streamflow trial release.")
  source("R/site-cache.R",local=TRUE);swc_cache_validate_app(file.path(directory,"streamflow"))
  for(f in m$files){if(!grepl("^[A-Za-z0-9_./-]+$",f$path)||any(strsplit(f$path,"/",fixed=TRUE)[[1]]%in%c(".","..","")))stop("Unsafe trial file path.")
    p<-file.path(directory,f$path);if(!file.exists(p)||!identical(f$sha256,digest::digest(file=p,algo="sha256",serialize=FALSE)))stop("Modified trial file: ",f$path)}
  if(!identical(m$source_seal,digest::digest(file=file.path(source_dir,"connected/connected-release.json"),algo="sha256",serialize=FALSE)))stop("Published Explorer changed; rebuild the Streamflow trial.")
  catalog<-jsonlite::read_json(file.path(directory,"connected-catalog.json"))
  original<-jsonlite::read_json(file.path(source_dir,"connected/connected-catalog.json"))
  if(!identical(catalog,original))stop("Trial routes differ from the accepted Explorer.")
  pages<-unique(c("current/index.html",vapply(catalog$months,`[[`,character(1),"viewer")))
  for(f in pages){html<-rawToChar(readBin(file.path(directory,f),"raw",n=file.info(file.path(directory,f))$size))
    if(!grepl('<details id="streamflow-panel"',html,fixed=TRUE)||!grepl("</html>",html,fixed=TRUE)||!grepl('explorer-streamflow.swc-',html,fixed=TRUE))stop("Missing inline trial section: ",f)}
  p<-jsonlite::read_json(file.path(directory,"streamflow/streamflow-data.json"))
  stopifnot(length(p$gauges)==32L,as.integer(as.Date(m$end)-as.Date(m$start))==89L)
  for(g in p$gauges){d<-jsonlite::read_json(file.path(directory,"streamflow",g$hydrograph));stopifnot(identical(d$id,g$id),length(d$rows)==90L,d$rows[[1]]$date==m$start,d$rows[[90]]$date==m$end)}
  result<-data.frame(status="PASS",gauges=32L,pages=length(pages),archive_years=length(unique(vapply(Filter(function(m)m$kind=="archive",catalog$months),`[[`,numeric(1),"water_year"))),current_latest=catalog$latest,flow_latest=m$end,requests=0L)
  print(result,row.names=FALSE);invisible(result)
}
