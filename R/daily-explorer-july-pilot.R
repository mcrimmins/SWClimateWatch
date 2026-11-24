# Full July benchmark: diagnostic files only; no site, cron or S3 changes.
july_pilot_dates <- function() as.character(seq(as.Date("2025-07-01"),as.Date("2025-07-31"),by="day"))
july_pilot_support <- function() as.character(seq(as.Date("2025-06-02"),as.Date("2025-07-31"),by="day"))
july_pilot_load <- function() {
  source("scripts/load-daily-explorer.R",local=FALSE)
  source("scripts/load-weather-period-archive.R",local=FALSE)
  source("R/daily-explorer-archive-pilot.R",local=FALSE)
  source("R/nws-hazards-explorer.R",local=FALSE)
  source("R/storm-reports-staging.R",local=FALSE)
  source("R/site-cache.R",local=FALSE)
}
july_pilot_root <- function()daily_archive_pilot_root("data/diagnostics/daily-explorer-july-2025")
july_pilot_copy <- function(from,to) {
  if(!file.exists(from))stop("Missing pilot input: ",from)
  dir.create(dirname(to),recursive=TRUE,showWarnings=FALSE)
  if(!file.exists(to)||!identical(unname(tools::md5sum(from)),unname(tools::md5sum(to))))
    if(!file.copy(from,to,overwrite=TRUE))stop("Could not copy pilot asset.")
}
july_pilot_input <- function(root,date) {
  marker<-file.path(root,"inputs",date,"complete.rds")
  x<-if(file.exists(marker))tryCatch(readRDS(marker),error=function(e)NULL)else NULL
  if(!is.list(x)||!identical(x$date,date)||!identical(x$digest,digest::digest(list(x$base,x$overlay),algo="sha256")))return(NULL)
  rows<-rbind(x$base[,c("path","md5","index","index_md5")],x$overlay[,c("path","md5","index","index_md5")])
  for(i in seq_len(nrow(rows))) {
    r<-rows[i,]
    if(is.na(r$path))next # Optional terrain inputs remain explicitly absent.
    if(!all(file.exists(c(r$path,r$index)))||!identical(unname(tools::md5sum(r$path)),r$md5)||
      !identical(unname(tools::md5sum(r$index)),r$index_md5))return(NULL)
  }
  if(nrow(x$base)!=4L||!all(x$base$ready)||!setequal(x$base$field,c("height500","pwat","u250","v250"))||
    any(x$base$date!=date)||any(x$overlay$date!=date)||!all(c("mslp","u850","v850")%in%x$overlay$field)||
    anyNA(x$overlay$path[x$overlay$field%in%c("mslp","u850","v850")]))return(NULL)
  x
}
july_pilot_log <- function(root,phase,status,started,requests=0,bytes=0) {
  path<-file.path(root,"run-history.csv")
  row<-data.frame(utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),phase,status,requests,bytes,
    seconds=as.numeric(difftime(Sys.time(),started,units="secs")))
  utils::write.table(row,path,append=file.exists(path),col.names=!file.exists(path),row.names=FALSE,sep=",")
}

prepare_daily_explorer_july <- function(download=FALSE,max_new_dates=10L) {
  if(length(download)!=1L||is.na(download)||!is.logical(download)||length(max_new_dates)!=1L||!max_new_dates%in%1:10)stop("Bound preparation to 1-10 new dates per call.")
  root<-july_pilot_root();support<-july_pilot_support();ready<-vapply(support,function(d)!is.null(july_pilot_input(root,d)),logical(1))
  write.csv(data.frame(date=support,ready=ready),file.path(root,"input-plan.csv"),row.names=FALSE)
  remaining<-support[!ready];requests<-bytes<-0;done<-0L;started<-Sys.time()
  for(date in head(remaining,max_new_dates)) {
    message("July input preparation ",done+1L,"/",min(length(remaining),max_new_dates),": ",date)
    base<-weather_period_plan(date,1L)
    if(!all(base$ready)) {
      if(!download)stop("Weather inputs missing. Set options(swc.july.download=TRUE) to permit bounded downloads; no partial means will be built.")
      transfer<-weather_period_download(base,max_dates=1L,max_fields=4L,max_requests=8L,max_bytes=4e6)
      requests<-requests+transfer$requests;bytes<-bytes+transfer$bytes;base<-weather_period_plan(date,1L)
    }
    if(!all(base$ready))stop("Four verified weather fields are required on ",date)
    over<-weather_overlay_inputs(as.Date(date),download_missing=download,max_requests=80L,max_bytes=15e6)
    requests<-requests+over$requests;bytes<-bytes+over$bytes
    if(anyNA(over$inputs$path[over$inputs$field%in%c("mslp","u850","v850")]))stop("Required overlay input missing on ",date)
    x<-list(date=date,base=base,overlay=over$inputs)
    x$digest<-digest::digest(list(x$base,x$overlay),algo="sha256")
    directory<-file.path(root,"inputs",date);dir.create(directory,recursive=TRUE,showWarnings=FALSE)
    saveRDS(x,file.path(directory,"complete.rds"))
    write.csv(over$inputs,file.path(directory,"overlays.csv"),row.names=FALSE)
    done<-done+1L
    write.csv(data.frame(date,requests,bytes,seconds=as.numeric(difftime(Sys.time(),started,units="secs"))),file.path(root,"last-preparation.csv"),row.names=FALSE)
  }
  ready<-vapply(support,function(d)!is.null(july_pilot_input(root,d)),logical(1))
  plan<-data.frame(date=support,ready=ready);write.csv(plan,file.path(root,"input-plan.csv"),row.names=FALSE)
  result<-data.frame(status=if(all(ready))"READY"else"PARTIAL",ready=sum(ready),required=length(support),remaining=sum(!ready),prepared=done,requests,bytes)
  july_pilot_log(root,"prepare",result$status,started,requests,bytes)
  print(result,row.names=FALSE);invisible(result)
}

july_pilot_decode <- function(root,input) {
  date<-input$date;base<-weather_period_daily(input$base,file.path(root,"decoded"))
  key<-digest::digest(list(input$digest,base$geometry,body(weather_overlay_decode),body(weather_moisture_grid),body(weather_moisture_wind_mask),R.version.string),algo="sha256")
  file<-file.path(root,"decoded",paste0(date,"-overlay.rds"));marker<-paste0(file,".marker.rds")
  old<-if(file.exists(marker))tryCatch(readRDS(marker),error=function(e)NULL)else NULL
  if(is.list(old)&&identical(old$key,key)&&file.exists(file)&&identical(old$md5,unname(tools::md5sum(file))))over<-readRDS(file)else {
    over<-weather_overlay_decode(input$overlay,input$base$path[input$base$field=="height500"],base$geometry)
    saveRDS(over,file);saveRDS(list(key=key,md5=unname(tools::md5sum(file))),marker)
  }
  list(base=base,overlay=over)
}

build_daily_explorer_july <- function(download_events=FALSE,max_end_dates=7L) {
  if(length(max_end_dates)!=1L||!max_end_dates%in%1:31)stop("Bound rendering to 1-31 weather endpoints per call.")
  root<-july_pilot_root();dates<-july_pilot_dates();started<-Sys.time()
  inputs<-setNames(lapply(july_pilot_support(),function(d)july_pilot_input(root,d)),july_pilot_support())
  if(any(vapply(inputs,is.null,logical(1))))stop("Prepare all 60 supporting weather dates first. Inspect input-plan.csv.")
  prism<-file.path(root,"prism")
  # Seed the seven previously reviewed July dates; signatures are rechecked by
  # the regular builder before any reused record is accepted.
  seed<-"data/diagnostics/daily-explorer-archive-pilot/work/2025-07"
  for(d in dates) {
    file<-file.path(seed,"cache",paste0(d,".rds"))
    if(!file.exists(file)||file.exists(file.path(prism,"cache",basename(file))))next
    x<-tryCatch(readRDS(file),error=function(e)NULL)
    if(!is.list(x)||!is.list(x$record$images))next
    for(image in unlist(x$record$images))july_pilot_copy(file.path(seed,image),file.path(prism,image))
    july_pilot_copy(file,file.path(prism,"cache",basename(file)))
  }
  build_daily_explorer(water_years=2025L,start_date=min(dates),end_date=max(dates),output_dir=prism)
  payload<-jsonlite::read_json(file.path(prism,"daily-data.json"));payload$latest_cached_date<-max(dates)
  jsonlite::write_json(payload,file.path(prism,"daily-data.json"),auto_unbox=TRUE,digits=NA,null="null")
  public<-file.path(root,"viewer");dir.create(public,recursive=TRUE,showWarnings=FALSE)
  # Incomplete builds are never exposed as a validated full-month release.
  if(file.exists(file.path(public,"july-release.json")))file.remove(file.path(public,"july-release.json"))
  decoded<-new.env(parent=emptyenv());rendered<-list();new_ends<-character()
  functions<-lapply(list(weather_period_average,weather_overlay_average,weather_mean_plot,weather_overlay_layers,
    weather_pressure_centers,weather_period_daily,weather_overlay_decode,weather_core_grid,weather_moisture_grid,
    weather_gaussian_latitudes,weather_moisture_wind_mask,weather_streamlines,weather_contour_labels,july_pilot_decode),body)
  for(end in dates)for(n in c(1L,7L,30L)) {
    window<-as.character(seq(as.Date(end)-n+1L,as.Date(end),by="day"));selected<-inputs[window]
    signature<-digest::digest(list(version=1L,end=end,n=n,inputs=vapply(selected,`[[`,character(1),"digest"),functions=functions,
      R=R.version.string,packages=vapply(c("terra","ggplot2","maps","scales"),function(p)as.character(utils::packageVersion(p)),character(1))),algo="sha256")
    directory<-file.path(root,"weather",end,paste0(n,"day"));status<-"REUSED"
    if(!weather_period_archive_current(directory,signature)) {
      if(!end%in%new_ends&&length(new_ends)>=max_end_dates) {status<-"DEFERRED"}else {
        new_ends<-union(new_ends,end);message("July weather: ",end," / ",n," day(s), cached inputs only")
        dir.create(directory,recursive=TRUE,showWarnings=FALSE)
        values<-lapply(window,function(d){if(!exists(d,decoded,inherits=FALSE))assign(d,july_pilot_decode(root,inputs[[d]]),decoded);get(d,decoded,inherits=FALSE)})
        cells<-weather_period_average(lapply(values,`[[`,"base"),n)
        overlay<-weather_overlay_average(lapply(values,`[[`,"overlay"),n)
        paths<-weather_mean_plot(cells,as.Date(window[1]),as.Date(end),directory,days=n,include_jet=TRUE)
        weather_mean_plot(cells,as.Date(window[1]),as.Date(end),directory,days=n,moisture_overlay=overlay)
        for(field in c("height500","jet250"))july_pilot_copy(paths[[field]],file.path(directory,paste0(field,".png")))
        july_pilot_copy(file.path(directory,paste0("pwat-overlay-",n,"day.png")),file.path(directory,"moisture.png"))
        saveRDS(list(cells=cells,overlay=overlay,dates=window),file.path(directory,"mean-native-grid.rds"))
        files<-file.path(directory,c("height500.png","jet250.png","moisture.png","mean-native-grid.rds"))
        saveRDS(list(signature=signature,md5=unname(tools::md5sum(files)),start=window[1],end=end,days=n,
          wind_cells=sum(overlay$wind_mask)),file.path(directory,"complete.rds"))
        # Remove only this renderer's redundant named PNGs, after verification.
        if(!weather_period_archive_current(directory,signature))stop("Weather output verification failed.")
        file.remove(c(unname(paths),file.path(directory,paste0("pwat-overlay-",n,"day.png"))))
        status<-"BUILT"
      }
    }
    rendered[[length(rendered)+1L]]<-data.frame(end,days=n,status,
      wind_eligible_cells=if(status=="DEFERRED")NA_integer_ else readRDS(file.path(directory,"complete.rds"))$wind_cells)
    write.csv(do.call(rbind,rendered),file.path(root,"weather-progress.csv"),row.names=FALSE)
  }
  progress<-do.call(rbind,rendered)
  if(any(progress$status=="DEFERRED")) {july_pilot_log(root,"build","PARTIAL",started);message("Weather rendering checkpoint saved. Rerun the build script to continue; no complete viewer published yet.");return(invisible(list(status="PARTIAL",remaining=sum(progress$status=="DEFERRED"))))}
  # Fetch/archive event metadata once; subsequent assembly can be cache-only.
  event_request<-function(...)nws_hazards_request(...,download=download_events)
  source("R/storm-reports-pilot.R",local=TRUE)
  bounds<-list(c("2025-07-01","2025-08-01"),c("2025-06-30","2025-07-01"))
  report_requests<-0L
  raw<-lapply(bounds,function(b) {
    path<-file.path("data/raw/storm-reports/az-nm",paste0(b[1],"_",b[2],".rds"))
    x<-if(file.exists(path))tryCatch(readRDS(path),error=function(e)NULL)else NULL
    if(download_events) {
      if(is.null(x))report_requests<<-report_requests+1L
      return(read_storm_reports_cache(b[1],b[2]))
    }
    if(!is.list(x)||!identical(x$start,b[1])||!identical(x$end,b[2])||is.null(x$fetched_utc))stop("Verified July report cache missing. Set options(swc.july.download=TRUE) for the bounded first event build.")
    normalize_storm_reports(x$raw,b[1],b[2]);x
  })
  snapshot<-list(reports=unname(unlist(lapply(raw,function(x)normalize_storm_reports(x$raw,x$start,x$end)),recursive=FALSE)),
    available_dates=as.character(seq(as.Date("2025-06-30"),as.Date("2025-07-31"),by="day")),stale_dates=character(),
    snapshots=lapply(raw,function(x)x[c("start","end","fetched_utc","url")]))
  events<-file.path(root,"events")
  event_result<-build_nws_hazards_explorer(source_dir=prism,output_dir=events,copy_maps=FALSE,full_window=TRUE,request_fun=event_request,report_snapshot=snapshot)
  event_requests<-report_requests+event_result$summary$requests
  for(file in list.files(events,recursive=TRUE))if(!file%in%c("daily-data.json"))july_pilot_copy(file.path(events,file),file.path(public,file))
  for(d in payload$days)for(image in unlist(d$images))july_pilot_copy(file.path(prism,image),file.path(public,image))
  daily<-periods<-list()
  for(end in dates)for(n in c(1L,7L,30L)) {
    directory<-file.path(root,"weather",end,paste0(n,"day"));fields<-c("height500","jet250","moisture")
    paths<-file.path(directory,paste0(fields,".png"))
    images<-setNames(if(n==1L)paste0("circulation/maps/",end,"-",fields,".png")else paste0("circulation/means/",end,"-",n,"day-",fields,".png"),fields)
    for(i in seq_along(paths))july_pilot_copy(paths[i],file.path(public,images[i]))
    marker<-readRDS(file.path(directory,"complete.rds"))
    record<-list(start=marker$start,end=end,days=n,images=as.list(images),md5=as.list(setNames(unname(tools::md5sum(paths)),fields)))
    if(n==1L)daily[[length(daily)+1L]]<-c(list(date=end,status="available"),record)else periods[[length(periods)+1L]]<-record
  }
  weather_write_json(list(schema_version=1L,source="NOAA CPC CORe",days=daily),file.path(public,"circulation-manifest.json"))
  weather_write_json(list(schema_version=1L,source="NOAA CPC CORe",periods=periods),file.path(public,"circulation-means-manifest.json"))
  payload$publication_mode<-FALSE;payload$july_full_pilot<-TRUE
  payload$circulation_enabled<-payload$circulation_period_means_enabled<-TRUE
  payload$storm_reports_preview<-payload$nws_hazards_preview<-TRUE
  payload$local_review_note<-"Unpublished July 2025 full-month benchmark. PRISM, daily and 7-/30-day weather, reports and archived hazards. Weather uses June 2 onward for complete trailing windows; event coverage includes June 30 for precipitation-map timing."
  weather_write_json(payload,file.path(public,"daily-data.json"))
  html<-paste(readLines(file.path(public,"index.html"),warn=FALSE),collapse="\n")
  html<-sub('<h1>Daily Explorer</h1>','<h1>Daily Explorer · July 2025 pilot</h1>',html,fixed=TRUE)
  html<-sub('<label>Season<select','<label>Month<select disabled><option>July 2025</option></select></label><label hidden>Season<select',html,fixed=TRUE)
  writeLines(html,file.path(public,"index.html"),useBytes=TRUE);swc_cache_version_app(public)
  files<-list.files(public,recursive=TRUE);files<-setdiff(files,"july-release.json")
  release<-list(schema_version=1L,month="2025-07",files=unname(lapply(files,function(f)list(path=f,md5=unname(tools::md5sum(file.path(public,f)))))))
  jsonlite::write_json(release,file.path(public,"july-release.json"),auto_unbox=TRUE,pretty=TRUE)
  summary<-data.frame(status="READY",dates=31L,prism_maps=217L,daily_weather_maps=93L,mean_maps=186L,
    weather_built=sum(progress$status=="BUILT"),weather_reused=sum(progress$status=="REUSED"),
    event_requests=event_requests,
    viewer_bytes=sum(file.info(file.path(public,files))$size),seconds=as.numeric(difftime(Sys.time(),started,units="secs")))
  write.csv(summary,file.path(root,"build-summary.csv"),row.names=FALSE);print(summary,row.names=FALSE)
  cache_paths<-unique(unlist(lapply(inputs,function(x)c(x$base$path,x$base$index,x$overlay$path,x$overlay$index)),use.names=FALSE))
  cache_paths<-cache_paths[!is.na(cache_paths)&file.exists(cache_paths)]
  dirs<-c(viewer=public,prism_work=prism,rendered_weather=file.path(root,"weather"),decoded=file.path(root,"decoded"),input_markers=file.path(root,"inputs"))
  sizes<-vapply(dirs,function(d)sum(file.info(list.files(d,recursive=TRUE,full.names=TRUE))$size,na.rm=TRUE),numeric(1))
  sizes<-c(sizes,selected_shared_weather_inputs=sum(file.info(cache_paths)$size))
  write.csv(data.frame(category=names(sizes),bytes=unname(sizes)),file.path(root,"storage.csv"),row.names=FALSE)
  coverage<-do.call(rbind,lapply(inputs,function(x)data.frame(date=x$date,
    optional_terrain_missing=sum(is.na(x$overlay$path)&x$overlay$field%in%c("surface",paste0("surface",sprintf("%02d",seq(0,21,3))))))))
  write.csv(coverage,file.path(root,"terrain-input-coverage.csv"),row.names=FALSE)
  july_pilot_log(root,"build","READY",started,requests=event_requests,bytes=if(event_requests>0)NA_real_ else 0)
  invisible(summary)
}

validate_daily_explorer_july <- function(directory=file.path(july_pilot_root(),"viewer")) {
  if(!file.exists(file.path(directory,"july-release.json")))stop("No complete July release. Finish or resume the build first.")
  release<-jsonlite::read_json(file.path(directory,"july-release.json"))
  if(!identical(release$schema_version,1L)||!identical(release$month,"2025-07")||!length(release$files))stop("No complete July release. Resume the build first.")
  for(f in release$files) {
    if(!is.character(f$path)||length(f$path)!=1L||grepl("[.][.]",f$path)||startsWith(f$path,"/")||!grepl("^[A-Za-z0-9_./-]+$",f$path))stop("Unsafe July release path.")
    path<-file.path(directory,f$path)
    if(!file.exists(path)||!identical(f$md5,unname(tools::md5sum(path))))stop("Changed or missing release file: ",f$path)
  }
  p<-jsonlite::read_json(file.path(directory,"daily-data.json"));dates<-vapply(p$days,`[[`,character(1),"date")
  if(!isTRUE(p$july_full_pilot)||isTRUE(p$publication_mode)||!identical(dates,july_pilot_dates())||
    !identical(p$latest_cached_date,"2025-07-31")||!isTRUE(p$circulation_enabled)||!isTRUE(p$circulation_period_means_enabled)||
    !isTRUE(p$storm_reports_preview)||!isTRUE(p$nws_hazards_preview))stop("July dates or feature flags invalid.")
  if(any(lengths(lapply(p$days,`[[`,"images"))!=7L))stop("Every July date requires seven PRISM maps.")
  prism<-validate_daily_explorer_assets(directory);stopifnot(prism$maps==217L)
  daily<-jsonlite::read_json(file.path(directory,"circulation-manifest.json"))$days
  if(!identical(vapply(daily,`[[`,character(1),"date"),dates))stop("Daily weather dates do not cover July.")
  for(d in daily) {
    if(!identical(d$status,"available")||!identical(d$start,d$date)||d$days!=1L)stop("Invalid daily weather window.")
    for(field in c("height500","jet250","moisture")) {
      expected<-paste0("circulation/maps/",d$date,"-",field,".png")
      if(!identical(d$images[[field]],expected)||!identical(d$md5[[field]],unname(tools::md5sum(file.path(directory,expected)))))stop("Daily weather checksum mismatch.")
    }
  }
  means<-validate_weather_period_assets(directory)
  if(means$periods!=62L||length(means$images)!=186L)stop("July requires all 62 complete weather means.")
  validate_storm_reports_publication(directory,require_enabled=FALSE)
  reports<-jsonlite::read_json(file.path(directory,"storm-reports-manifest.json"))
  if(!identical(vapply(reports$days,`[[`,character(1),"date"),c("2025-06-30",dates))||
    any(vapply(reports$days,function(d)d$status=="UNAVAILABLE",logical(1))))stop("Reports lack required July/noon coverage.")
  data<-jsonlite::read_json(file.path(directory,"hazards/cases/explorer.json"))
  if(!identical(data$start,"2025-06-30")||!identical(data$end_exclusive,"2025-08-01")||!is.null(names(data$events)))stop("Invalid hazard window/array.")
  ids<-vapply(data$events,`[[`,character(1),"id");if(anyDuplicated(ids))stop("Duplicate hazard event IDs.")
  pools<-lapply(data$geometry_bundles,function(path){if(!grepl("^bundles/[a-f0-9]{64}[.]json$",path))stop("Unsafe hazard geometry path.");jsonlite::read_json(file.path(directory,"hazards",path))})
  for(e in data$events)for(s in e$segments)if(!is.null(s$geometry)) {
    if(!grepl("^[a-f0-9]{64}$",s$geometry)||is.null(pools[[substr(s$geometry,1,1)]][[s$geometry]]))stop("Missing hazard geometry.")
  }
  timeline<-jsonlite::read_json(file.path(directory,"hazard-timeline.json"))$timeline
  expected<-nws_hazards_timeline(data$events,dates,data$start,data$end_exclusive)
  canonical<-function(x)jsonlite::toJSON(x,auto_unbox=TRUE,null="null",digits=NA)
  if(!identical(canonical(timeline),canonical(expected)))stop("Hazard timing/region/type totals differ.")
  swc_cache_validate_app(directory);swc_cache_validate_app(file.path(directory,"hazards"))
  result<-data.frame(status="PASS",dates=31L,prism_maps=217L,daily_weather_maps=93L,mean_maps=186L,
    reports=sum(vapply(reports$days,`[[`,numeric(1),"reports")),hazards=length(data$events))
  print(result,row.names=FALSE);invisible(result)
}
