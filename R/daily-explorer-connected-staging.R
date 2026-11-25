# Static navigation trial. Original current and accepted archive files stay intact.
connected_staging_guard <- function(destination=Sys.getenv("SWC_S3_DESTINATION")) {
  if(!identical(destination,"s3://cales-climate-reports/climate/watch-staging/") ||
     !identical(Sys.getenv("SWC_PRODUCTION_STATE_DIR"),"/home/crimmins/.local/state/swclimatewatch-staging"))
    stop("Connected Explorer trial requires the exact staging destination and state directory.")
  invisible(TRUE)
}
connected_static_html <- function(html,base,script,bridge,style) {
  html<-connected_explorer_frame_html(html,bridge)
  html<-sub('src="explorer.js"',paste0('src="',script,'"'),html,fixed=TRUE)
  # frame_html derives its CSS name from the bridge name; use the explicit seal.
  html<-sub(paste0('<link rel="stylesheet" href="',sub("connected-bridge.js","connected-frame.css",bridge,fixed=TRUE),'">'),
    paste0('<link rel="stylesheet" href="',style,'">'),html,fixed=TRUE)
  sub("<head>",paste0('<head><base href="',base,'">'),html,fixed=TRUE)
}
build_connected_static <- function(current,archive,output=file.path(current,"connected"),validate_archive=TRUE) {
  if(validate_archive)validate_wy2025_explorer_navigation(archive)
  validate_daily_explorer_assets(current)
  if(!identical(normalizePath(dirname(output),winslash="/",mustWork=TRUE),normalizePath(current,winslash="/",mustWork=TRUE)) || basename(output)!="connected")
    stop("Connected output must be the current Explorer's connected subdirectory.")
  dir.create(output,recursive=TRUE,showWarnings=FALSE)
  seals<-character()
  put<-function(text,path) {
    f<-file.path(output,path);dir.create(dirname(f),recursive=TRUE,showWarnings=FALSE)
    writeLines(text,f,useBytes=TRUE);seals[path]<<-unname(tools::md5sum(f));path
  }
  asset<-function(text,name) {
    tmp<-tempfile();writeLines(text,tmp,useBytes=TRUE);withr::defer(unlink(tmp))
    path<-sub("([.][^.]+)$",paste0(".swc-",substr(unname(tools::md5sum(tmp)),1,16),"\\1"),name)
    put(text,path)
  }
  read<-function(path)paste(readLines(path,warn=FALSE),collapse="\n")
  assets<-"scripts/daily-explorer-archive-assets"
  shared<-setNames(vapply(c("connected-model.js","connected-shell.js","connected-shell.css","connected-frame.css","connected-bridge.js"),
    function(f)asset(read(file.path(assets,f)),f),character(1)),c("model","shell","shell_css","frame_css","bridge"))
  html<-read(file.path(assets,"connected-index.html"))
  for(f in names(shared)) {
    original<-c(model="connected-model.js",shell="connected-shell.js",shell_css="connected-shell.css",frame_css="connected-frame.css",bridge="connected-bridge.js")[[f]]
    html<-gsub(original,shared[[f]],html,fixed=TRUE)
  }
  html<-sub("Daily Explorer · connected local review","Daily Explorer · connected staging review",html,fixed=TRUE)
  html<-sub("Southwest Climate Watch · Local review","Southwest Climate Watch · Staging review",html,fixed=TRUE)
  put(html,"index.html")
  catalog<-connected_explorer_catalog(current,archive)
  for(i in seq_along(catalog$months)) {
    m<-catalog$months[[i]]
    if(m$kind=="archive")m$viewer<-paste0("months/",m$month,"/index.html")
    catalog$months[[i]]<-m
  }
  put(jsonlite::toJSON(catalog,auto_unbox=TRUE,null="null",pretty=TRUE),"connected-catalog.json")
  js<-asset(connected_explorer_current_js(read(file.path(current,"explorer.js"))),"current/explorer.js")
  put(connected_static_html(read(file.path(current,"index.html")),"../../",paste0("connected/",js),
    paste0("connected/",shared[["bridge"]]),paste0("connected/",shared[["frame_css"]])),"current/index.html")
  a<-jsonlite::read_json(file.path(archive,"archive-catalog.json"))
  for(m in a$months) {
    prefix<-paste0("months/",m$month,"/")
    js<-asset(connected_explorer_startup_js(read(file.path(archive,dirname(m$viewer),"explorer.js"))),paste0(prefix,"explorer.js"))
    origin<-paste0("archive/wy2025/",dirname(m$viewer),"/")
    context<-read(file.path(archive,dirname(m$viewer),"month-context.js"))
    if(!grepl("swcMonthContext(location.href)",context,fixed=TRUE))stop("Static month context hook needs review.")
    context<-asset(sub("swcMonthContext(location.href)","swcMonthContext(document.baseURI)",context,fixed=TRUE),paste0(prefix,"month-context.js"))
    html<-connected_static_html(read(file.path(archive,m$viewer)),paste0("../../../",origin),paste0("../../../../connected/",js),
      paste0("../../../../connected/",shared[["bridge"]]),paste0("../../../../connected/",shared[["frame_css"]]))
    html<-gsub('src="month-context([.]swc-[a-f0-9]{16})?[.]js"',paste0('src="../../../../connected/',context,'"'),html,perl=TRUE)
    put(html,paste0(prefix,"index.html"))
  }
  dependencies<-c("daily-data.json","explorer.js","archive/wy2025/wy2025-release.json")
  hashes<-unname(tools::md5sum(file.path(current,dependencies)))
  if(anyNA(hashes))stop("Connected trial requires the accepted archive beside the current viewer.")
  manifest<-list(schema_version=1L,files=unname(lapply(names(seals),function(p)list(path=p,md5=seals[[p]]))),
    dependencies=unname(lapply(seq_along(dependencies),function(i)list(path=dependencies[i],md5=hashes[i]))))
  weather_write_json(manifest,file.path(output,"connected-release.json"))
  validate_connected_static(current)
}
validate_connected_static <- function(directory) {
  root<-file.path(directory,"connected");m<-jsonlite::read_json(file.path(root,"connected-release.json"))
  for(pair in list(list(rows=m$files,root=root),list(rows=m$dependencies,root=directory)))for(f in pair$rows) {
    if(!is.character(f$path)||grepl("(^/|(^|/)\\.\\.(/|$)|\\\\)",f$path))stop("Unsafe connected publication path.")
    if(!identical(f$md5,unname(tools::md5sum(file.path(pair$root,f$path)))))stop("Connected publication differs: ",f$path)
  }
  c<-jsonlite::read_json(file.path(root,"connected-catalog.json"))
  for(p in unique(vapply(c$months,`[[`,character(1),"viewer")))if(!file.exists(file.path(root,p)))stop("Missing connected viewer: ",p)
  data<-jsonlite::read_json(file.path(directory,"daily-data.json"))
  if(!identical(c$latest,data$latest_cached_date))stop("Connected current date differs from staged data.")
  result<-data.frame(status="PASS",months=length(c$months),archive_dates=sum(vapply(Filter(function(m)m$kind=="archive",c$months),function(m)length(m$dates),integer(1))),
    current_latest=c$latest,navigation_bytes=sum(file.info(file.path(root,vapply(m$files,`[[`,character(1),"path")))$size))
  print(result,row.names=FALSE);invisible(result)
}
stage_connected_trial <- function() {
  connected_staging_guard()
  source("scripts/load-daily-explorer-connected.R",local=FALSE)
  build_connected_static("site/daily-explorer","site/daily-explorer/archive/wy2025")
}
validate_connected_trial <- function(output_dir="site/_site") {
  connected_staging_guard()
  for(d in c("site/daily-explorer",file.path(output_dir,"daily-explorer")))validate_connected_static(d)
  files<-file.path(c("site/daily-explorer",file.path(output_dir,"daily-explorer")),"connected/connected-release.json")
  if(length(unique(unname(tools::md5sum(files))))!=1L)stop("Source/rendered connected releases differ.")
  message("PASS: connected navigation, loading adapters and source/rendered dependencies match.")
}
