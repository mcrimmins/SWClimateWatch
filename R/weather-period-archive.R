# Manual staging adapter. Cached inputs only; not called by the daily runner.
weather_period_archive_current <- function(directory,signature=NULL) {
  paths<-file.path(directory,c("height500.png","jet250.png","moisture.png","mean-native-grid.rds"))
  marker<-file.path(directory,"complete.rds")
  old<-if(file.exists(marker))tryCatch(readRDS(marker),error=function(e)NULL) else NULL
  is.list(old)&&(is.null(signature)||identical(old$signature,signature))&&all(file.exists(paths))&&
    identical(old$md5,unname(tools::md5sum(paths)))
}

build_weather_period_archive <- function(explorer_dir="site/daily-explorer",
    output_dir="data/processed/weather-period-means",max_new_end_dates=3L,recent_end_dates=30L,
    end_dates=NULL,roots=weather_mean_roots()) {
  if(length(max_new_end_dates)!=1L||!max_new_end_dates%in%0:30||length(recent_end_dates)!=1L||!recent_end_dates%in%1:30)stop("Bound endpoint counts to 0-30 new and 1-30 recent.")
  payload<-jsonlite::read_json(file.path(explorer_dir,"daily-data.json"))
  daily<-jsonlite::read_json(file.path(explorer_dir,"circulation-manifest.json"))
  dates<-sort(intersect(vapply(payload$days,`[[`,character(1),"date"),
    vapply(Filter(function(d)identical(d$status,"available"),daily$days),`[[`,character(1),"date")))
  if(!length(dates))stop("No matching retained daily weather dates.")
  ends<-if(is.null(end_dates))rev(tail(dates,recent_end_dates)) else sort(unique(as.character(as.Date(end_dates))),decreasing=TRUE)
  if(length(ends)>30L||anyNA(as.Date(ends))||!all(ends%in%dates))stop("Choose up to 30 retained Explorer/weather endpoints.")
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  started<-proc.time()[["elapsed"]];report<-list();new_ends<-character()
  input_cache<-new.env(parent=emptyenv())
  decoded_cache<-new.env(parent=emptyenv())
  input_for<-function(date) {
    if(exists(date,input_cache,inherits=FALSE))return(get(date,input_cache,inherits=FALSE))
    value<-tryCatch({
      base<-weather_period_plan(date,1L,roots)
      if(!all(base$ready))stop("Missing/unverified HGT, PWAT or 250-mb input on ",date)
      overlay<-weather_overlay_inputs(as.Date(date),download_missing=FALSE,
        directory=file.path(output_dir,"overlay-index-cache"))$inputs
      list(base=base,overlay=overlay)
    },error=function(e)list(error=paste("Cached inputs unavailable on",date,
      sub(" Set SWC_WEATHER_MEAN_DOWNLOAD=true.*$","",conditionMessage(e)),"Refresh or backfill the daily weather archive first.")))
    assign(date,value,input_cache);value
  }
  decode_for<-function(date) {
    if(exists(date,decoded_cache,inherits=FALSE))return(get(date,decoded_cache,inherits=FALSE))
    input<-input_for(date)
    base<-weather_period_daily(input$base,file.path(output_dir,"decoded"))
    key<-digest::digest(list(inputs=input$overlay[,c("date","field","md5","index_md5")],
      geometry=base$geometry,code=lapply(list(weather_overlay_decode,weather_moisture_grid,weather_moisture_wind_mask),body)),algo="sha256")
    path<-file.path(output_dir,"decoded",paste0(date,"-overlay.rds"));mark<-paste0(path,".md5.rds")
    old<-if(file.exists(mark))tryCatch(readRDS(mark),error=function(e)NULL) else NULL
    if(is.list(old)&&identical(old$key,key)&&file.exists(path)&&identical(old$md5,unname(tools::md5sum(path))))overlay<-readRDS(path) else {
      overlay<-weather_overlay_decode(input$overlay,input$base$path[input$base$field=="height500"],base$geometry)
      saveRDS(overlay,path);saveRDS(list(key=key,md5=unname(tools::md5sum(path))),mark)
    }
    value<-list(base=base,overlay=overlay);assign(date,value,decoded_cache);value
  }
  for(end in ends)for(days in c(7L,30L)) {
    start<-as.character(as.Date(end)-days+1L);window<-as.character(seq(as.Date(start),as.Date(end),by="day"))
    directory<-file.path(output_dir,"periods",end,paste0(days,"day"));note<-""
    status<-tryCatch({
      inputs<-lapply(window,input_for)
      failures<-vapply(inputs,function(x)!is.null(x$error),logical(1))
      if(any(failures))stop(inputs[[which(failures)[1]]]$error)
      fingerprint<-lapply(inputs,function(x)list(base=x$base[,c("date","field","md5","index_md5")],overlay=x$overlay[,c("date","field","md5","index_md5")]))
      signature<-digest::digest(list(version=1,end=end,days=days,inputs=fingerprint,R=R.version.string,
        functions=lapply(list(weather_mean_plot,weather_overlay_layers,weather_pressure_centers,weather_period_daily,
          weather_overlay_decode,weather_period_average,weather_overlay_average,weather_streamlines,weather_contour_labels,
          weather_moisture_grid,weather_core_grid,weather_gaussian_latitudes,weather_moisture_wind_mask),body),
        packages=vapply(c("terra","ggplot2","maps","scales"),function(p)as.character(utils::packageVersion(p)),character(1))),algo="sha256")
      if(weather_period_archive_current(directory,signature))"REUSED" else if(!end%in%new_ends&&length(new_ends)>=max_new_end_dates)"DEFERRED" else {
        new_ends<-union(new_ends,end)
        dir.create(directory,recursive=TRUE,showWarnings=FALSE)
        message("Weather period means: ",end," / ",days," days (cached inputs only)")
        decoded<-lapply(window,decode_for)
        cells<-weather_period_average(lapply(decoded,`[[`,"base"),days)
        overlay<-weather_overlay_average(lapply(decoded,`[[`,"overlay"),days)
        png<-weather_mean_plot(cells,as.Date(start),as.Date(end),directory,days=days,include_jet=TRUE)
        weather_mean_plot(cells,as.Date(start),as.Date(end),directory,days=days,moisture_overlay=overlay)
        file.copy(png[["height500"]],file.path(directory,"height500.png"),overwrite=TRUE)
        file.copy(png[["jet250"]],file.path(directory,"jet250.png"),overwrite=TRUE)
        file.copy(file.path(directory,paste0("pwat-overlay-",days,"day.png")),file.path(directory,"moisture.png"),overwrite=TRUE)
        saveRDS(list(cells=cells,overlay=overlay,dates=window),file.path(directory,"mean-native-grid.rds"))
        paths<-file.path(directory,c("height500.png","jet250.png","moisture.png","mean-native-grid.rds"))
        saveRDS(list(signature=signature,md5=unname(tools::md5sum(paths)),start=start,end=end,days=days,
          wind_cells=sum(overlay$wind_mask)),file.path(directory,"complete.rds"))
        # Named temporary renders are redundant once canonical files are verified.
        if(!weather_period_archive_current(directory,signature))stop("Weather period output verification failed.")
        redundant<-c(unname(png),file.path(directory,paste0("pwat-overlay-",days,"day.png")))
        if(any(!file.remove(redundant)))stop("Could not remove duplicate temporary renders.")
        "BUILT"
      }
    },error=function(e){note<<-conditionMessage(e);"UNAVAILABLE"})
    report[[length(report)+1L]]<-data.frame(end,start,days,status,note)
    write.csv(do.call(rbind,report),file.path(output_dir,"last-batch.csv"),row.names=FALSE)
  }
  # Publish only this run's verified/current periods, so revisions never leave
  # stale means in the manifest. Retained files stay available for later reuse.
  report<-do.call(rbind,report);records<-list()
  for(i in which(report$status%in%c("BUILT","REUSED"))) {
    row<-report[i,];directory<-file.path(output_dir,"periods",row$end,paste0(row$days,"day"))
    if(!weather_period_archive_current(directory))stop("Period output changed before staging.")
    fields<-c("height500","jet250","moisture");paths<-file.path(directory,paste0(fields,".png"))
    images<-setNames(paste0("circulation/means/",row$end,"-",row$days,"day-",fields,".png"),fields)
    dir.create(file.path(explorer_dir,"circulation","means"),recursive=TRUE,showWarnings=FALSE)
    for(j in seq_along(paths)) {
      dest<-file.path(explorer_dir,images[j]);hash<-unname(tools::md5sum(paths[j]))
      if(!file.exists(dest)||!identical(hash,unname(tools::md5sum(dest))))if(!file.copy(paths[j],dest,overwrite=TRUE))stop("Could not stage period PNG.")
    }
    records[[length(records)+1L]]<-list(start=row$start,end=row$end,days=as.integer(row$days),images=as.list(images),md5=as.list(setNames(unname(tools::md5sum(paths)),fields)))
  }
  weather_write_json(list(schema_version=1L,source="NOAA CPC CORe",periods=records),file.path(explorer_dir,"circulation-means-manifest.json"))
  payload$circulation_period_means_enabled<-length(records)>0
  weather_write_json(payload,file.path(explorer_dir,"daily-data.json"))
  # UI updates are staged without rebuilding PRISM or other site products.
  for(asset in c("index.html","explorer.js","explorer.css"))file.copy(file.path("scripts/daily-explorer-assets",asset),file.path(explorer_dir,asset),overwrite=TRUE)
  checked<-validate_weather_period_assets(explorer_dir)
  summary<-data.frame(periods=checked$periods,maps=length(checked$images),built=sum(report$status=="BUILT"),reused=sum(report$status=="REUSED"),
    deferred=sum(report$status=="DEFERRED"),unavailable=sum(report$status=="UNAVAILABLE"),requests=0L,seconds=proc.time()[["elapsed"]]-started)
  write.csv(summary,file.path(output_dir,"update-summary.csv"),row.names=FALSE);print(summary,row.names=FALSE)
  invisible(summary)
}

validate_weather_period_assets <- function(directory) {
  payload<-jsonlite::read_json(file.path(directory,"daily-data.json"))
  if(!isTRUE(payload$circulation_period_means_enabled))return(invisible(list(periods=0L,images=character())))
  manifest<-jsonlite::read_json(file.path(directory,"circulation-means-manifest.json"))
  if(!identical(manifest$schema_version,1L)||!is.list(manifest$periods)||!length(manifest$periods))stop("Invalid weather period manifest.")
  dates<-vapply(payload$days,`[[`,character(1),"date");seen<-images<-character()
  for(p in manifest$periods) {
    if(length(p$end)!=1L||!p$end%in%dates||!p$days%in%c(7L,30L)||
        !identical(p$start,as.character(as.Date(p$end)-p$days+1)))stop("Invalid weather period window.")
    key<-paste(p$end,p$days);if(key%in%seen)stop("Duplicate weather period.");seen<-c(seen,key)
    for(field in c("height500","jet250","moisture")) {
      expected<-paste0("circulation/means/",p$end,"-",p$days,"day-",field,".png");path<-file.path(directory,expected)
      if(!identical(p$images[[field]],expected)||!file.exists(path)||file.info(path)$size<=0||
          !identical(p$md5[[field]],unname(tools::md5sum(path))))stop("Missing, invalid or stale weather mean PNG.")
      images<-c(images,expected)
    }
  }
  invisible(list(periods=length(seen),images=images))
}
