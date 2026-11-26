# Navigation-only local review. Existing current/archive publication files are read-only.
connected_explorer_load <- function() {
  source("scripts/load-daily-explorer-wy2025.R",local=FALSE)
  source("R/daily-explorer-wy2026.R",local=FALSE)
}
connected_explorer_root <- function()daily_archive_pilot_root("data/diagnostics/daily-explorer-connected")
connected_explorer_current <- function() {
  configured<-getOption("swc.connected.current_dir",NULL)
  if(!is.null(configured))return(normalizePath(configured,winslash="/",mustWork=TRUE))
  candidates<-c("site/daily-explorer","data/diagnostics/daily-explorer-nws-hazards","data/diagnostics/daily-explorer-site")
  rows<-lapply(candidates,function(d) {
    f<-file.path(d,"daily-data.json");if(!file.exists(f))return(NULL)
    p<-tryCatch(jsonlite::read_json(f),error=function(e)NULL)
    if(is.null(p)||!length(p$days))return(NULL)
    data.frame(directory=d,date=p$latest_cached_date,features=sum(vapply(c("circulation_enabled","storm_reports_enabled","storm_reports_preview","nws_hazards_enabled","nws_hazards_preview"),function(k)isTRUE(p[[k]]),logical(1))))
  })
  rows<-do.call(rbind,rows);if(is.null(rows)||!nrow(rows))stop("No cached current Explorer. Set options(swc.connected.current_dir='path/to/viewer').")
  normalizePath(rows$directory[order(rows$date,rows$features,decreasing=TRUE)[1]],winslash="/",mustWork=TRUE)
}
connected_explorer_archives <- function(directories) {
  if(!is.character(directories)||!length(directories)||anyNA(directories))stop("Supply completed archive directories.")
  entries<-lapply(directories,function(directory) {
    directory<-normalizePath(directory,winslash="/",mustWork=TRUE)
    markers<-list.files(directory,pattern="^wy[0-9]{4}-release[.]json$")
    if(length(markers)!=1L)stop("Expected one water-year release: ",directory)
    year<-as.integer(substr(markers,3,6))
    if(!year%in%c(2025L,2026L))stop("Unsupported connected archive year.")
    list(directory=directory,year=year,marker=markers)
  })
  names(entries)<-vapply(entries,function(x)paste0("wy",x$year),character(1))
  if(anyDuplicated(names(entries)))stop("Duplicate archive year.")
  entries[order(names(entries))]
}
connected_explorer_catalog <- function(current,archive) {
  archives<-connected_explorer_archives(archive)
  p<-jsonlite::read_json(file.path(current,"daily-data.json"))
  dates<-vapply(p$days,`[[`,character(1),"date")
  months<-unname(unlist(lapply(names(archives),function(id) {
    a<-jsonlite::read_json(file.path(archives[[id]]$directory,"archive-catalog.json"))
    lapply(a$months,function(m)list(month=m$month,water_year=m$water_year,dates=m$dates,kind="archive",viewer=paste0("archive/",id,"/",m$viewer)))
  }),recursive=FALSE))
  archived_dates<-unlist(lapply(months,`[[`,"dates"),use.names=FALSE)
  if(anyDuplicated(archived_dates))stop("Duplicate dates in completed archives.")
  # Completed archives own overlapping retained dates in the recent cache.
  dates<-dates[!dates%in%archived_dates]
  if(!length(dates))stop("Current cache has no dates after the completed archives.")
  for(month in sort(unique(substr(dates,1,7)))) {
    if(month%in%vapply(months,`[[`,character(1),"month"))stop("Partial current/archive month overlap.")
    selected<-dates[substr(dates,1,7)==month]
    months[[length(months)+1L]]<-list(month=month,water_year=daily_explorer_water_year(selected[1]),dates=unname(as.list(selected)),kind="current",viewer="current/index.html")
  }
  months<-months[order(vapply(months,`[[`,character(1),"month"))]
  list(schema_version=1L,connected_explorer=TRUE,latest=max(dates),months=unname(months))
}
connected_explorer_context_catalog <- function(archives,id) {
  context<-jsonlite::read_json(file.path(archives[[id]]$directory,"archive-catalog.json"))
  context$months<-unname(unlist(lapply(names(archives),function(owner) {
    source<-jsonlite::read_json(file.path(archives[[owner]]$directory,"archive-catalog.json"))
    lapply(source$months,function(m) {
      if(owner!=id){m$path<-paste0("../",owner,"/",m$path);m$viewer<-paste0("../",owner,"/",m$viewer)}
      m
    })
  }),recursive=FALSE))
  context
}
connected_explorer_frame_html <- function(html,bridge) {
  html<-gsub("explorer([.]swc-[a-f0-9]{16})?[.]js","explorer.js",html,perl=TRUE)
  style<-paste0('<link rel="stylesheet" href="',sub("connected-bridge.js","connected-frame.css",bridge,fixed=TRUE),'">')
  if(grepl("archive-month-bridge",html,fixed=TRUE)) {
    html<-gsub("archive-month-bridge([.]swc-[a-f0-9]{16})?[.]js",bridge,html,perl=TRUE)
    sub("</head>",paste0(style,"</head>"),html,fixed=TRUE)
  }else sub("</head>",paste0(style,'<script src="',bridge,'" defer></script></head>'),html,fixed=TRUE)
}
connected_explorer_startup_js <- function(js) {
  needle<-"refreshMetricOptions(); selectLatestDate();"
  if(!grepl(needle,js,fixed=TRUE))stop("Connected initial-preference hook needs review.")
  startup<-paste0("const connectedQuery = new URL(location.href).searchParams;\n",
    "    const connectedSet = (id,key) => {const el=document.getElementById(id), value=connectedQuery.get(key); if(el && value && [...el.options].some(o=>o.value===value))el.value=value;};\n",
    "    connectedSet('region','region'); connectedSet('variable','variable'); refreshMetricOptions();\n",
    "    for(const [id,key] of [['view','view'],['metric','metric'],['compare','compare'],['circulation-compare','compare'],['circulation-period','weatherPeriod'],['storm-timing','timing'],['storm-window','eventWindow']])connectedSet(id,key);\n",
    "    for(const [key,id] of [['openWeather','circulation-panel'],['openReports','storm-panel'],['openHazards','hazard-panel']])if(connectedQuery.has(key)&&document.getElementById(id))document.getElementById(id).open=connectedQuery.get(key)==='true';\n",
    "    const connectedDate = connectedQuery.get('date'); if (connectedDate && byDate.has(connectedDate)) selectDate(connectedDate); else selectLatestDate();")
  js<-sub(needle,startup,js,fixed=TRUE)
  # Keep thumbnail URLs inert until the parent reports their actual on-screen
  # range. Native lazy loading treats a tall iframe as a large viewport.
  for(pair in list(c('img.src = image; img.loading = "lazy";', 'img.dataset.connectedSrc = image; img.loading = "lazy"; img.width = 1116; img.height = 780;'),
    c('image.loading = "lazy"; image.src = source;', 'image.loading = "lazy"; image.dataset.connectedSrc = source;'))) {
    if(!grepl(pair[1],js,fixed=TRUE))stop("Connected thumbnail hook needs review.")
    js<-sub(pair[1],pair[2],js,fixed=TRUE)
  }
  js
}
connected_explorer_current_js <- function(js) {
  needle<-"const available = days.filter(day => day.water_year === year);"
  if(!grepl(needle,js,fixed=TRUE))stop("Current month filter hook needs review.")
  js<-sub(needle,paste0("const connectedMonth = new URL(location.href).searchParams.get('connectedMonth');\n  ",
    "const available = days.filter(day => day.water_year === year && (!connectedMonth || day.date.startsWith(connectedMonth)));"),js,fixed=TRUE)
  js<-connected_explorer_startup_js(js)
  needle<-"function selectDate(date) {"
  if(!grepl(needle,js,fixed=TRUE))stop("Current cross-month date hook needs review.")
  sub(needle,paste0(needle,"\n  const cq = new URL(location.href).searchParams;\n  if (cq.get('connectedMonth') && byDate.has(date) && !date.startsWith(cq.get('connectedMonth'))) {\n    parent.postMessage({type:'swc:connected-month',token:cq.get('archiveToken'),date:date,ready:false},location.origin); return;\n  }"),js,fixed=TRUE)
}
build_connected_explorer <- function(current_dir=connected_explorer_current(),archive_dir=getOption("swc.connected.archive_dirs",
    c("data/diagnostics/daily-explorer-wy2025/preview","data/diagnostics/daily-explorer-wy2026/preview"))) {
  root<-connected_explorer_root();current<-normalizePath(current_dir,winslash="/",mustWork=TRUE)
  archives<-connected_explorer_archives(archive_dir)
  directories<-vapply(archives,`[[`,character(1),"directory")
  validate_daily_explorer_assets(current)
  prior<-file.path(root,"sources.rds")
  reusable<-if(file.exists(prior))tryCatch({
    s<-readRDS(prior)
    if(!identical(s$schema_version,2L)||!identical(s$current,current)||
       !identical(vapply(s$archives,`[[`,character(1),"directory"),directories))FALSE else {validate_connected_explorer(full_archive=FALSE);TRUE}
  },error=function(e)FALSE)else FALSE
  if(reusable)message("Reusing the fully validated, unchanged archive snapshots; refreshing navigation only.")else for(a in archives) {
    message("Checking completed WY",a$year," source...")
    if(a$year==2025L)validate_wy2025_explorer_navigation(a$directory)else validate_wy2026_explorer_navigation(a$directory)
  }
  protected<-c(file.path(current,c("index.html","explorer.js","daily-data.json")),
    unlist(lapply(archives,function(a)file.path(a$directory,c("index.html","archive-catalog.json",a$marker))),use.names=FALSE))
  before<-tools::md5sum(protected)
  public<-file.path(root,"preview");overrides<-file.path(root,"overrides")
  dir.create(public,recursive=TRUE,showWarnings=FALSE);dir.create(overrides,recursive=TRUE,showWarnings=FALSE)
  assets<-"scripts/daily-explorer-archive-assets"
  for(f in c("connected-model.js","connected-shell.js","connected-shell.css","connected-frame.css","connected-bridge.js"))
    july_pilot_copy(file.path(assets,f),file.path(public,f))
  july_pilot_copy(file.path(assets,"connected-index.html"),file.path(public,"index.html"))
  catalog<-connected_explorer_catalog(current,directories)
  weather_write_json(catalog,file.path(public,"connected-catalog.json"))
  html<-paste(readLines(file.path(current,"index.html"),warn=FALSE),collapse="\n")
  html<-gsub("explorer([.]swc-[a-f0-9]{16})?[.]js","explorer.js",html,perl=TRUE)
  writeLines(connected_explorer_frame_html(html,"../connected-bridge.js"),file.path(overrides,"current-index.html"),useBytes=TRUE)
  js<-paste(readLines(file.path(current,"explorer.js"),warn=FALSE),collapse="\n")
  writeLines(connected_explorer_current_js(js),file.path(overrides,"current-explorer.js"),useBytes=TRUE)
  payload<-jsonlite::read_json(file.path(current,"daily-data.json"))
  # This private selection manifest verifies current-route ownership. The
  # current frame still reads its original payload, including buffered dates
  # needed for trailing comparisons across the water-year boundary.
  current_dates<-unlist(lapply(Filter(function(m)m$kind=="current",catalog$months),`[[`,"dates"),use.names=FALSE)
  payload$days<-Filter(function(d)d$date%in%current_dates,payload$days)
  weather_write_json(payload,file.path(overrides,"current-daily-data.json"))
  for(id in names(archives)) {
    archive<-archives[[id]]$directory
    a<-jsonlite::read_json(file.path(archive,"archive-catalog.json"))
    for(m in a$months) {
    html<-paste(readLines(file.path(archive,m$viewer),warn=FALSE),collapse="\n")
    writeLines(connected_explorer_frame_html(html,"../../../../connected-bridge.js"),file.path(overrides,paste0(m$month,".html")),useBytes=TRUE)
    js<-paste(readLines(file.path(archive,dirname(m$viewer),"explorer.js"),warn=FALSE),collapse="\n")
    writeLines(connected_explorer_startup_js(js),file.path(overrides,paste0(m$month,"-explorer.js")),useBytes=TRUE)
    }
    # Adjacent metadata can cross the boundary between the completed years.
    # Rebase to the owning year's read-only mount, retaining lazy PNG/geometry.
    context<-connected_explorer_context_catalog(archives,id)
    weather_write_json(context,file.path(overrides,paste0(id,"-context-catalog.json")))
    release<-jsonlite::read_json(file.path(archive,archives[[id]]$marker))
    archives[[id]]$files<-c(archives[[id]]$marker,vapply(release$files,`[[`,character(1),"path"))
    archives[[id]]$release_md5<-unname(tools::md5sum(file.path(archive,archives[[id]]$marker)))
    archives[[id]]$stats<-file.info(file.path(archive,archives[[id]]$files))[,c("size","mtime")]
  }
  files<-c(list.files(public,full.names=TRUE),list.files(overrides,full.names=TRUE))
  # The read-only server exposes only publication assets, never work directories.
  current_files<-list.files(current,recursive=TRUE)
  current_files<-current_files[!grepl("^(archive|connected)/",current_files)]
  current_files<-current_files[grepl("[.](html|js|css|json|png|jpg|jpeg|svg|woff|woff2|txt)$",current_files,ignore.case=TRUE)]
  snapshot<-list(schema_version=2L,current=current,archives=archives,current_files=current_files,
    current_hashes=tools::md5sum(file.path(current,current_files)),
    ui_hashes=tools::md5sum(files),protected=before)
  saveRDS(snapshot,file.path(root,"sources.rds"))
  result<-validate_connected_explorer(full_archive=FALSE)
  write.csv(result,file.path(root,"build-summary.csv"),row.names=FALSE)
  if(!identical(before,tools::md5sum(protected)))stop("Original Explorer sources changed during navigation build.")
  message("Connected local navigation ready; no maps rendered, downloads, publication or source changes.")
  invisible(result)
}
validate_connected_explorer <- function(full_archive=TRUE) {
  message(if(full_archive)"Checking connected navigation and full archive hashes..."else"Checking connected navigation, current cache and immutable archive snapshot...")
  root<-connected_explorer_root();s<-readRDS(file.path(root,"sources.rds"));public<-file.path(root,"preview")
  if(!identical(s$schema_version,2L))stop("Rebuild connected navigation for the two-archive server.")
  if(!identical(s$ui_hashes,tools::md5sum(names(s$ui_hashes))))stop("Connected UI changed; rebuild the navigation preview.")
  if(!identical(s$current_hashes,tools::md5sum(names(s$current_hashes))))stop("Current cache changed; rebuild the navigation preview.")
  for(a in s$archives) {
    if(!identical(a$release_md5,unname(tools::md5sum(file.path(a$directory,a$marker)))))stop("Accepted archive release changed; rebuild the preview.")
    stats<-file.info(file.path(a$directory,a$files))[,c("size","mtime")]
    if(!identical(a$stats,stats))stop("Archive files changed; rebuild and fully validate the preview.")
    if(full_archive) {
      if(a$year==2025L)validate_wy2025_explorer_navigation(a$directory)else validate_wy2026_explorer_navigation(a$directory)
    }
  }
  c<-jsonlite::read_json(file.path(public,"connected-catalog.json"))
  expected<-connected_explorer_catalog(s$current,vapply(s$archives,`[[`,character(1),"directory"))
  if(!identical(c,expected))stop("Connected routes differ from current/archive source dates.")
  if(anyDuplicated(unlist(lapply(c$months,`[[`,"dates"),use.names=FALSE)))stop("Duplicate connected dates.")
  stopifnot(length(Filter(function(m)m$kind=="archive",c$months))==12L*length(s$archives))
  filtered<-jsonlite::read_json(file.path(root,"overrides/current-daily-data.json"))
  current_dates<-unlist(lapply(Filter(function(m)m$kind=="current",c$months),`[[`,"dates"),use.names=FALSE)
  if(!identical(vapply(filtered$days,`[[`,character(1),"date"),current_dates))stop("Current date filter differs from the catalog.")
  result<-data.frame(status="PASS",archive_years=length(s$archives),archive_dates=sum(vapply(Filter(function(m)m$kind=="archive",c$months),function(m)length(m$dates),integer(1))),current_dates=sum(vapply(Filter(function(m)m$kind=="current",c$months),function(m)length(m$dates),integer(1))),
    months=length(c$months),current_latest=c$latest,navigation_bytes=sum(file.info(names(s$ui_hashes))$size),maps_rebuilt=0L,requests=0L)
  print(result,row.names=FALSE);invisible(result)
}
connected_explorer_response <- function(req,root=connected_explorer_root(),sources=readRDS(file.path(root,"sources.rds"))) {
  response<-function(status,text)list(status=status,headers=list("Content-Type"="text/plain; charset=utf-8","Cache-Control"="no-store","X-SWC-Connected-Preview"="multi-year-v3"),body=text)
  if(!req$REQUEST_METHOD%in%c("GET","HEAD"))return(response(405L,"Read-only preview."))
  path<-tryCatch(utils::URLdecode(req$PATH_INFO),error=function(e)"")
  if(!is.character(path)||length(path)!=1L||!startsWith(path,"/"))return(response(400L,"Invalid path."))
  relative<-sub("^/","",path);if(!nzchar(relative))relative<-"index.html"
  if(endsWith(relative,"/"))relative<-paste0(relative,"index.html")
  if(!grepl("^[A-Za-z0-9_./-]+$",relative)||any(strsplit(relative,"/",fixed=TRUE)[[1]]%in%c(".","..","")))return(response(400L,"Invalid path."))
  public<-file.path(root,"preview");override<-file.path(root,"overrides");file<-NULL
  if(relative=="current/index.html")file<-file.path(override,"current-index.html")
  else if(relative=="current/explorer.js")file<-file.path(override,"current-explorer.js")
  else if(startsWith(relative,"current/")) {
    name<-substring(relative,nchar("current/")+1L)
    if(name%in%sources$current_files)file<-file.path(sources$current,name)
  }else if(grepl("^archive/wy[0-9]{4}/",relative)) {
    id<-strsplit(relative,"/",fixed=TRUE)[[1]][2]
    a<-sources$archives[[id]]
    if(is.null(a)&&id=="wy2025"&&!is.null(sources$archive))a<-list(directory=sources$archive,files=sources$archive_files)
    name<-substring(relative,nchar(paste0("archive/",id,"/"))+1L)
    if(is.null(a))return(response(404L,"This archive year is unavailable."))
    if(name=="archive-catalog.json"&&file.exists(file.path(override,paste0(id,"-context-catalog.json"))))file<-file.path(override,paste0(id,"-context-catalog.json"))
    else if(grepl("^months/[0-9]{4}-[0-9]{2}/index[.]html$",name)&&name%in%a$files)file<-file.path(override,paste0(strsplit(name,"/",fixed=TRUE)[[1]][2],".html"))
    else if(grepl("^months/[0-9]{4}-[0-9]{2}/explorer[.]js$",name)&&name%in%a$files)file<-file.path(override,paste0(strsplit(name,"/",fixed=TRUE)[[1]][2],"-explorer.js"))
    else if(name%in%a$files)file<-file.path(a$directory,name)
  }else if(relative%in%basename(names(sources$ui_hashes)))file<-file.path(public,relative)
  if(is.null(file)||!file.exists(file)||dir.exists(file))return(response(404L,"This preview asset is unavailable."))
  ext<-tolower(tools::file_ext(file));types<-c(html="text/html; charset=utf-8",js="application/javascript; charset=utf-8",css="text/css; charset=utf-8",json="application/json; charset=utf-8",png="image/png",jpg="image/jpeg",jpeg="image/jpeg",svg="image/svg+xml",woff="font/woff",woff2="font/woff2",txt="text/plain; charset=utf-8")
  type<-unname(types[ext]);if(is.na(type))type<-"application/octet-stream"
  list(status=200L,headers=list("Content-Type"=type,"Cache-Control"="no-store","X-SWC-Connected-Preview"="multi-year-v3"),body=if(req$REQUEST_METHOD=="HEAD")raw()else readBin(file,"raw",n=file.info(file)$size))
}
serve_connected_explorer <- function(port=8805L) {
  validate_connected_explorer(full_archive=FALSE)
  root<-connected_explorer_root();s<-readRDS(file.path(root,"sources.rds"))
  httpuv::startServer("127.0.0.1",port,list(call=function(req)connected_explorer_response(req,root,s)))
}
