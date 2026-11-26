# Update browser assets and release seals only. No downloads, map rendering or
# copying of map bundles. Stop the preview server while this runs.
source("scripts/load-daily-explorer-wy2026.R")
wy2026_repair_root<-file.path(wy2026_explorer_root(),"preview")
wy2026_repair_marker<-file.path(wy2026_repair_root,"wy2026-release.json")
wy2026_repair_release<-jsonlite::read_json(wy2026_repair_marker)
stopifnot(identical(wy2026_repair_release$water_year,2026L))
wy2026_repair_catalog<-jsonlite::read_json(file.path(wy2026_repair_root,"archive-catalog.json"))
if(!isTRUE(wy2026_repair_catalog$wy2026_pilot))stop("Not a WY2026 preview.")
# Record the pre-repair manifests for inspection/recovery; leave all maps intact.
wy2026_repair_backup<-file.path(wy2026_explorer_root(),"navigation-before-loading-repair.rds")
if(!file.exists(wy2026_repair_backup))saveRDS(list(release=wy2026_repair_release,
  months=lapply(wy2026_repair_catalog$months,function(m)jsonlite::read_json(file.path(wy2026_repair_root,dirname(m$viewer),"window-release.json")))),wy2026_repair_backup)
wy2026_repair_seal<-function(release,directory,changed) {
  rows<-setNames(release$files,vapply(release$files,`[[`,character(1),"path"))
  for(p in unique(changed)) {
    hash<-unname(tools::md5sum(file.path(directory,p)))
    if(is.na(hash))stop("Missing repair asset: ",p)
    rows[[p]]<-list(path=p,md5=hash)
  }
  release$files<-unname(rows);release
}
wy2026_repair_changed<-character()
for(m in wy2026_repair_catalog$months) {
  message("Repair WY2026 navigation: ",m$month)
  prefix<-dirname(m$viewer);directory<-file.path(wy2026_repair_root,prefix)
  for(f in c("month-context.js","archive-month-bridge.js"))
    july_pilot_copy(file.path("scripts/daily-explorer-archive-assets",f),file.path(directory,f))
  july_pilot_copy("scripts/daily-explorer-archive-assets/connected-frame.css",file.path(directory,"archive-frame.css"))
  html<-paste(readLines(file.path(directory,"index.html"),warn=FALSE),collapse="\n")
  if(!grepl("archive-frame",html,fixed=TRUE)) {
    html<-sub("</head>",'<link rel="stylesheet" href="archive-frame.css"></head>',html,fixed=TRUE)
    writeLines(html,file.path(directory,"index.html"),useBytes=TRUE)
  }
  swc_cache_version_app(directory)
  assets<-jsonlite::read_json(file.path(directory,"cache-assets.json"))$assets
  changed<-unique(c("index.html","cache-assets.json","archive-frame.css","month-context.js","archive-month-bridge.js",vapply(assets,`[[`,character(1),"file")))
  release<-wy2026_repair_seal(jsonlite::read_json(file.path(directory,"window-release.json")),directory,changed)
  weather_write_json(release,file.path(directory,"window-release.json"))
  wy2026_repair_changed<-c(wy2026_repair_changed,paste0(prefix,"/",c(changed,"window-release.json")))
}
for(f in c("archive-shell.js","archive-shell.css"))july_pilot_copy(file.path("scripts/daily-explorer-archive-assets",f),file.path(wy2026_repair_root,f))
swc_cache_version_app(wy2026_repair_root)
wy2026_repair_assets<-jsonlite::read_json(file.path(wy2026_repair_root,"cache-assets.json"))$assets
wy2026_repair_changed<-c(wy2026_repair_changed,"index.html","cache-assets.json","archive-shell.js","archive-shell.css",vapply(wy2026_repair_assets,`[[`,character(1),"file"))
weather_write_json(wy2026_repair_seal(wy2026_repair_release,wy2026_repair_root,wy2026_repair_changed),wy2026_repair_marker)
validate_wy2026_explorer_navigation(wy2026_repair_root,require_complete=isTRUE(getOption("swc.wy2026.require_complete",TRUE)))
message("WY2026 navigation repaired and validated. No map rebuilds or downloads.")
