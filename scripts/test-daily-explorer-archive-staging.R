source("scripts/load-daily-explorer-archive-integration.R")
source("R/daily-explorer-archive-staging.R")
withr::with_envvar(c(SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch/",
  SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch"),
  stopifnot(inherits(try(daily_archive_staging_guard(),silent=TRUE),"try-error")))
withr::with_envvar(c(SWC_S3_DESTINATION="s3://cales-climate-reports/climate/watch-staging/",
  SWC_PRODUCTION_STATE_DIR="/home/crimmins/.local/state/swclimatewatch-staging"), {
  stopifnot(inherits(try(daily_archive_staging_guard("s3://cales-climate-reports/climate/watch/"),silent=TRUE),"try-error"))
  source("scripts/deploy-site-s3.R",local=TRUE)
  withr::with_envvar(c(SWC_DAILY_ARCHIVE_STAGING="true"), {
    error<-tryCatch({deploy_swc_site("s3://cales-climate-reports/climate/watch/");""},error=conditionMessage)
    stopifnot(grepl("exact staging destination",error,fixed=TRUE))
  })
  root<-daily_archive_pilot_root("data/diagnostics/daily-explorer-archive-staging-test")
  current<-file.path(root,"source/daily-explorer")
  stage_daily_archive_trial(current)
  target<-file.path(current,"archive-pilot");release<-jsonlite::read_json(file.path(target,"integration-release.json"))
  protected<-file.path(target,c(vapply(release$files,`[[`,character(1),"path"),"integration-release.json"))
  before<-tools::md5sum(protected)
  # Real current adapter, using two accepted current PRISM sample records.
  source_root<-"data/diagnostics/daily-explorer-archive-integrated/prism"
  cat<-jsonlite::read_json(file.path(source_root,"archive-catalog.json"))
  parts<-lapply(Filter(function(m)startsWith(m$path,"current/"),cat$months),function(m)jsonlite::read_json(file.path(source_root,m$path)))
  records<-unlist(lapply(parts,`[[`,"days"),recursive=FALSE)
  records<-records[order(vapply(records,`[[`,character(1),"date"))]
  stopifnot(length(records)>=2L)
  builder<-function(n)function(water_years,start_date,end_date,output_dir,manifest,publication_mode) {
    chosen<-tail(records,n);dir.create(file.path(output_dir,"maps"),recursive=TRUE,showWarnings=FALSE)
    for(i in seq_along(chosen))for(key in names(chosen[[i]]$images)) {
      image<-chosen[[i]]$images[[key]];relative<-paste0("maps/",basename(image))
      july_pilot_copy(file.path(source_root,image),file.path(output_dir,relative));chosen[[i]]$images[[key]]<-relative
    }
    for(asset in c("index.html","explorer.js","explorer.css"))july_pilot_copy(file.path("scripts/daily-explorer-assets",asset),file.path(output_dir,asset))
    jsonlite::write_json(list(schema_version=1L,publication_mode=TRUE,latest_cached_date=tail(chosen,1)[[1]]$date,days=unname(chosen)),file.path(output_dir,"daily-data.json"),auto_unbox=TRUE,null="null")
    list(built=0L,reused=n)
  }
  manifest<-read_prism_manifest(prism_processed_manifest_path())
  stage_daily_explorer_site(window_days=2,output_dir=current,work_dir=file.path(root,"work-two"),manifest=manifest,builder=builder(2))
  stage_daily_explorer_site(window_days=1,output_dir=current,work_dir=file.path(root,"work-one"),manifest=manifest,builder=builder(1))
  stopifnot(length(list.files(file.path(current,"maps"),pattern="[.]png$"))==7L,identical(before,tools::md5sum(protected)))
  stage_daily_archive_trial(file.path(root,"rendered/daily-explorer"))
  validate_daily_archive_trial(file.path(root,"rendered"),source_dir=current)
})
message("PASS: production/explicit-destination guards; normal current-map pruning retained every archive file; source/rendered-copy validation. No uploads.")
