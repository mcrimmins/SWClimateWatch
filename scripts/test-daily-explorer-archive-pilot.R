source("scripts/load-daily-explorer.R")
source("R/daily-explorer-archive-pilot.R")
root<-"data/diagnostics/daily-explorer-archive-pilot"
validate_daily_explorer_archive_pilot(root)
catalog<-jsonlite::read_json(file.path(root,"archive-catalog.json"))
# Replay the actual current-map staging/pruning adapter in an isolated copy.
sandbox<-daily_archive_pilot_root("data/diagnostics/daily-explorer-archive-retention-test")
files<-list.files(file.path(root,"archive"),recursive=TRUE)
for(file in files) {
  to<-file.path(sandbox,"archive",file);dir.create(dirname(to),recursive=TRUE,showWarnings=FALSE)
  stopifnot(file.copy(file.path(root,"archive",file),to,overwrite=TRUE))
}
before<-tools::md5sum(file.path(sandbox,"archive",files))
stopifnot(file.copy(file.path(root,"archive-catalog.json"),file.path(sandbox,"archive-catalog.json"),overwrite=TRUE))
catalog_before<-tools::md5sum(file.path(sandbox,"archive-catalog.json"))
parts<-lapply(Filter(function(m)startsWith(m$path,"current/"),catalog$months),function(m)jsonlite::read_json(file.path(root,m$path)))
records<-unlist(lapply(parts,`[[`,"days"),recursive=FALSE)
records<-records[order(vapply(records,`[[`,character(1),"date"))]
stopifnot(length(records)>=2L)
make_builder<-function(n)function(water_years,start_date,end_date,output_dir,manifest,publication_mode) {
  chosen<-tail(records,n);dir.create(file.path(output_dir,"maps"),recursive=TRUE,showWarnings=FALSE)
  for(i in seq_along(chosen))for(key in names(chosen[[i]]$images)) {
    image<-chosen[[i]]$images[[key]];relative<-paste0("maps/",basename(image))
    stopifnot(file.copy(file.path(root,image),file.path(output_dir,relative),overwrite=TRUE))
    chosen[[i]]$images[[key]]<-relative
  }
  for(asset in c("index.html","explorer.js","explorer.css"))file.copy(file.path("scripts/daily-explorer-assets",asset),file.path(output_dir,asset),overwrite=TRUE)
  jsonlite::write_json(list(schema_version=1L,publication_mode=TRUE,latest_cached_date=tail(chosen,1)[[1]]$date,days=unname(chosen)),
    file.path(output_dir,"daily-data.json"),auto_unbox=TRUE,null="null")
  list(built=0L,reused=n)
}
manifest<-read_prism_manifest(prism_processed_manifest_path())
first<-stage_daily_explorer_site(window_days=2,output_dir=file.path(sandbox,"current"),work_dir=file.path(sandbox,"work-two"),manifest=manifest,builder=make_builder(2))
second<-stage_daily_explorer_site(window_days=1,output_dir=file.path(sandbox,"current"),work_dir=file.path(sandbox,"work-one"),manifest=manifest,builder=make_builder(1))
stopifnot(first$maps==14L,second$maps==7L,
  length(list.files(file.path(sandbox,"current/maps"),pattern="[.]png$"))==7L,
  identical(catalog_before,tools::md5sum(file.path(sandbox,"archive-catalog.json"))),
  identical(before,tools::md5sum(file.path(sandbox,"archive",files))))
message("PASS: actual daily staging/pruning removed seven obsolete CURRENT maps; all completed-year files remained byte-identical.")
node<-c(getOption("swc.interactive.node",""),unname(Sys.which("node")),"data/diagnostics/local-test-tools/node.exe",
  file.path(Sys.getenv("ProgramFiles"),"nodejs/node.exe"),Sys.glob(file.path(Sys.getenv("ProgramFiles"),"WindowsApps","OpenAI.CodexPrimaryRuntime.*","dependencies/node/bin/node.exe")))
node<-node[nzchar(node)&file.exists(node)]
if(!length(node))stop("R/retention checks passed; set options(swc.interactive.node='C:/path/to/node.exe') for JavaScript checks.")
stopifnot(system2(node[1],"tests/daily-explorer-archive-model.cjs")==0L,
  system2(node[1],c("--check",file.path(root,"explorer.js")))==0L)
message("PASS: local archive navigation assets and retention rehearsal. Nothing downloaded or published.")
