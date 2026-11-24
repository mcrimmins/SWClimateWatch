# Integrate accepted local bundles; never fetch data, render maps or publish.
daily_archive_integrated_assets <- function(directory) {
  html<-paste(readLines(file.path(directory,"index.html"),warn=FALSE),collapse="\n")
  if(grepl("archive-month-bridge.js",html,fixed=TRUE))stop("Embed a fresh copied month, not an already modified month.")
  html<-sub("</head>",paste0('<style>main>header{display:none}.controls label:has(#year),.controls label:has(#archive-month),.controls label:has(select[disabled]){display:none}#latest,#circulation-latest{display:none}main{padding-top:0!important}</style>',
    '<script src="archive-month-bridge.js" defer></script></head>'),html,fixed=TRUE)
  writeLines(html,file.path(directory,"index.html"),useBytes=TRUE)
  july_pilot_copy("scripts/daily-explorer-archive-assets/archive-month-bridge.js",file.path(directory,"archive-month-bridge.js"))
  swc_cache_version_app(directory)
}
daily_archive_freeze <- function(directory,file="integration-release.json") {
  files<-setdiff(list.files(directory,recursive=TRUE),file)
  value<-list(schema_version=1L,files=unname(lapply(files,function(f)list(path=f,md5=unname(tools::md5sum(file.path(directory,f)))))))
  if(file=="july-release.json")value$month<-"2025-07"
  jsonlite::write_json(value,file.path(directory,file),auto_unbox=TRUE,pretty=TRUE)
}
build_daily_explorer_archive_integration <- function(output_dir="data/diagnostics/daily-explorer-archive-integrated",
    archive_dir="data/diagnostics/daily-explorer-archive-pilot",july_dir="data/diagnostics/daily-explorer-july-2025/viewer") {
  validate_daily_explorer_archive_pilot(archive_dir);validate_daily_explorer_july(july_dir)
  protected<-c(file.path(archive_dir,c("index.html","cache-assets.json","archive-catalog.json")),file.path(july_dir,c("index.html","cache-assets.json","july-release.json")))
  before<-tools::md5sum(protected)
  root<-daily_archive_pilot_root(output_dir)
  if(normalizePath(root,winslash="/",mustWork=TRUE)%in%normalizePath(c(archive_dir,july_dir),winslash="/",mustWork=TRUE))stop("Use a separate integrated preview directory.")
  catalog<-jsonlite::read_json(file.path(archive_dir,"archive-catalog.json"))
  browser<-jsonlite::read_json(file.path(archive_dir,"cache-assets.json"))
  files<-unique(c("index.html","archive-catalog.json","cache-assets.json",
    vapply(browser$assets,`[[`,character(1),"canonical"),vapply(browser$assets,`[[`,character(1),"file")))
  for(m in catalog$months) {
    if(m$month=="2025-07")next # July is served solely from the complete bundle.
    p<-jsonlite::read_json(file.path(archive_dir,m$path))
    files<-c(files,m$path,unlist(lapply(p$days,function(d)unlist(d$images,use.names=FALSE)),use.names=FALSE))
  }
  for(f in unique(files))july_pilot_copy(file.path(archive_dir,f),file.path(root,"prism",f))
  prism_catalog<-catalog;prism_catalog$months<-Filter(function(m)m$month!="2025-07",catalog$months)
  jsonlite::write_json(prism_catalog,file.path(root,"prism/archive-catalog.json"),auto_unbox=TRUE,pretty=TRUE)
  # Reset index/cache metadata from the source on every build; helper is idempotent
  # with respect to the resulting bytes, without modifying either source bundle.
  daily_archive_integrated_assets(file.path(root,"prism"))
  release<-jsonlite::read_json(file.path(july_dir,"july-release.json"))
  for(f in c("july-release.json",vapply(release$files,`[[`,character(1),"path")))july_pilot_copy(file.path(july_dir,f),file.path(root,"bundles/2025-07",f))
  daily_archive_integrated_assets(file.path(root,"bundles/2025-07"))
  daily_archive_freeze(file.path(root,"bundles/2025-07"),"july-release.json")
  found<-FALSE
  for(i in seq_along(catalog$months)) {
    m<-catalog$months[[i]]
    if(m$month=="2025-07") {
      found<-TRUE;m$dates<-unname(as.list(july_pilot_dates()));m$path<-"bundles/2025-07/daily-data.json"
      m$md5<-unname(tools::md5sum(file.path(root,m$path)));m$viewer<-"bundles/2025-07/index.html";m$full<-TRUE;m$sample<-FALSE
    } else {
      m$path<-paste0("prism/",m$path);m$viewer<-"prism/index.html";m$full<-FALSE
    }
    catalog$months[[i]]<-m
  }
  if(!found)stop("The navigation pilot must include July 2025.")
  catalog$archive_integration_pilot<-TRUE
  jsonlite::write_json(catalog,file.path(root,"archive-catalog.json"),auto_unbox=TRUE,pretty=TRUE)
  for(f in c("archive-model.js","archive-shell.js","archive-shell.css"))july_pilot_copy(file.path("scripts/daily-explorer-archive-assets",f),file.path(root,f))
  july_pilot_copy("scripts/daily-explorer-archive-assets/integrated-index.html",file.path(root,"index.html"))
  swc_cache_version_app(root);daily_archive_freeze(root)
  validate_daily_explorer_archive_integration(root)
  if(!identical(before,tools::md5sum(protected)))stop("Original accepted source bundles were modified.")
  message("Integrated local archive: ",root,". Existing accepted bundles retained; no downloads, map builds or publication.")
  invisible(root)
}
validate_daily_explorer_archive_integration <- function(directory="data/diagnostics/daily-explorer-archive-integrated") {
  release<-jsonlite::read_json(file.path(directory,"integration-release.json"))
  if(!identical(release$schema_version,1L)||!length(release$files))stop("Missing integrated archive release.")
  for(f in release$files) {
    if(!nws_hazards_safe_path(f$path))stop("Unsafe archive release path.")
    path<-file.path(directory,f$path)
    if(!file.exists(path)||!identical(unname(tools::md5sum(path)),f$md5))stop("Missing/changed integrated asset: ",f$path)
  }
  catalog<-jsonlite::read_json(file.path(directory,"archive-catalog.json"))
  if(!isTRUE(catalog$archive_pilot)||!isTRUE(catalog$archive_integration_pilot)||!is.null(names(catalog$months)))stop("Invalid integrated catalog.")
  all_dates<-character()
  for(m in catalog$months) {
    expected<-if(isTRUE(m$full))"bundles/2025-07/index.html"else"prism/index.html"
    if(!identical(m$viewer,expected)||!nws_hazards_safe_path(m$path)||!grepl("^[0-9]{4}-(0[1-9]|1[0-2])$",m$month))stop("Invalid month route.")
    path<-file.path(directory,m$path)
    if(!identical(unname(tools::md5sum(path)),m$md5))stop("Partition checksum mismatch.")
    p<-jsonlite::read_json(path);dates<-vapply(p$days,`[[`,character(1),"date")
    if(!identical(dates,unlist(m$dates,use.names=FALSE))||any(substr(dates,1,7)!=m$month)||any(daily_explorer_water_year(dates)!=m$water_year))stop("Route dates/year mismatch.")
    all_dates<-c(all_dates,dates)
    if(isTRUE(m$full)&&(!identical(m$month,"2025-07")||!identical(dates,july_pilot_dates())))stop("Wrong full-month route.")
  }
  if(anyDuplicated(all_dates)||!identical(max(all_dates),catalog$latest))stop("Duplicate dates or invalid latest date.")
  validate_daily_explorer_archive_pilot(file.path(directory,"prism"))
  validate_daily_explorer_july(file.path(directory,"bundles/2025-07"))
  for(d in c(directory,file.path(directory,"prism"),file.path(directory,"bundles/2025-07")))swc_cache_validate_app(d)
  result<-data.frame(status="PASS",months=length(catalog$months),dates=length(all_dates),full_july_dates=31L,source_requests=0L)
  print(result,row.names=FALSE);invisible(result)
}
