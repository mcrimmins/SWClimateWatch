# Date-matched water-year mean temperature, departure and percentile rank.
prism_wy_temperature_dates <- function(start,end) seq(as.Date(start),as.Date(end),by="day")

prism_wy_temperature_signature <- function(dates,aoi_id,manifest) {
  selection <- do.call(rbind,lapply(c("maxt","mint"),function(v)
    select_prism_daily_sources(v,dates,aoi_id,manifest)))
  prism_accumulation_source_signature(selection,manifest)
}

prism_wy_temperature_daily <- function(dates,aoi_id,manifest) {
  hi <- read_prism_best_daily_range("maxt",dates,aoi_id,manifest)
  lo <- read_prism_best_daily_range("mint",dates,aoi_id,manifest)
  stopifnot(identical(hi$dates,lo$dates))
  terra::compareGeom(hi$raster,lo$raster,stopOnError=TRUE)
  result <- terra::ifel(hi$raster>=lo$raster,(hi$raster+lo$raster)/2,NA)
  terra::time(result) <- hi$dates
  list(raster=result,dates=hi$dates)
}

prism_wy_temperature_sum <- function(dates,aoi_id,manifest) {
  daily <- prism_wy_temperature_daily(dates,aoi_id,manifest)$raster
  if(length(dates)==1L) daily else terra::app(daily,sum,na.rm=FALSE)
}

prism_wy_temperature_days <- function(periods) {
  n <- as.numeric(periods$end_date-periods$start_date)+1
  alt <- !is.na(periods$interpolation_end_date)
  n[alt] <- (n[alt]+as.numeric(periods$interpolation_end_date[alt]-periods$start_date[alt])+1)/2
  n
}

build_prism_water_year_temperature_cache <- function(date,
    baseline_start=swc_prism$percentile_start,baseline_end=swc_prism$percentile_end,
    aoi_id=swc_prism$aoi_id,processed_dir=swc_paths$processed,
    processed_manifest=read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    allow_incremental=TRUE,quiet=FALSE) {
  periods <- prism_water_year_reference_periods(date,baseline_start,baseline_end)
  dates <- prism_water_year_source_dates(periods)
  key <- prism_wy_temperature_signature(dates,aoi_id,processed_manifest)
  root <- file.path(processed_dir,"prism",aoi_id,"climatology",
    paste0(format(as.Date(baseline_start),"%Y%m%d"),"-",format(as.Date(baseline_end),"%Y%m%d")),
    "water-year-temperature")
  dir.create(root,recursive=TRUE,showWarnings=FALSE)
  path <- file.path(root,"reference-sums.tif");meta_path <- file.path(root,"reference-state.rds")
  saved <- if(file.exists(meta_path)) tryCatch(readRDS(meta_path),error=function(e)NULL) else NULL
  valid <- identical(saved$version,1L) && file.exists(path) &&
    identical(saved$md5,unname(tools::md5sum(path)))
  method <- "direct"; sums <- NULL
  if(valid && identical(saved$periods,periods) && identical(saved$key,key)) {
    sums <- read_prism_water_year_cache(path,periods$cache_date);method <- "reuse"
  } else if(valid && allow_incremental &&
      identical(saved$periods$water_year,periods$water_year) &&
      identical(saved$periods$start_date,periods$start_date) &&
      all(is.na(saved$periods$interpolation_end_date)) && all(is.na(periods$interpolation_end_date)) &&
      all(periods$end_date>saved$periods$end_date)) {
    old_key <- prism_wy_temperature_signature(prism_water_year_source_dates(saved$periods),aoi_id,processed_manifest)
    if(identical(old_key,saved$key)) {
      previous <- read_prism_water_year_cache(path,saved$periods$cache_date)
      additions <- lapply(seq_len(nrow(periods)),function(i)
        prism_wy_temperature_dates(saved$periods$end_date[i]+1,periods$end_date[i]))
      all_dates <- sort(unique(as.Date(unlist(additions),origin="1970-01-01")))
      daily <- prism_wy_temperature_daily(all_dates,aoi_id,processed_manifest)
      layers <- lapply(seq_len(nrow(periods)),function(i) {
        selected <- daily$raster[[match(additions[[i]],daily$dates)]]
        previous[[i]]+if(terra::nlyr(selected)==1L) selected else terra::app(selected,sum,na.rm=FALSE)
      })
      sums <- do.call(c,layers);method <- "incremental"
    }
  }
  counts <- prism_wy_temperature_days(periods)
  if(is.null(sums)) {
    layers <- lapply(seq_len(nrow(periods)),function(i) {
      primary <- prism_wy_temperature_sum(prism_wy_temperature_dates(periods$start_date[i],periods$end_date[i]),aoi_id,processed_manifest)
      if(!is.na(periods$interpolation_end_date[i])) {
        alternate <- prism_wy_temperature_sum(prism_wy_temperature_dates(periods$start_date[i],periods$interpolation_end_date[i]),aoi_id,processed_manifest)
        n1 <- as.numeric(periods$end_date[i]-periods$start_date[i])+1
        n2 <- as.numeric(periods$interpolation_end_date[i]-periods$start_date[i])+1
        primary <- (primary/n1+alternate/n2)/2*counts[i]
      }
      if(!quiet && (i%%5L==0L || i==nrow(periods))) message("Water-year temperature reference: ",i,"/",nrow(periods))
      primary
    })
    sums <- do.call(c,layers)
  }
  terra::time(sums) <- periods$cache_date
  if(method!="reuse") {
    write_prism_processed_raster(sums,path,datatype="FLT8S")
    saveRDS(list(version=1L,periods=periods,key=key,md5=unname(tools::md5sum(path)),
      build_method=method,built_at=format(Sys.time(),tz="UTC",usetz=TRUE)),meta_path)
  }
  means <- do.call(c,lapply(seq_len(nrow(periods)),function(i) sums[[i]]/counts[i]))
  terra::time(means) <- periods$cache_date
  if(!quiet) message("Water-year temperature reference: ",method,".")
  list(raster=means,periods=periods,path=path,build_method=method)
}

prism_water_year_temperature_comparisons <- function(current,reference,date) {
  terra::compareGeom(current,reference,stopOnError=TRUE)
  normal <- terra::app(reference,mean,na.rm=FALSE)
  rank <- terra::app(c(current,reference),function(x,...) {
    if(any(!is.finite(x))) NA_real_ else prism_type8_percentile_rank(x[1],x[-1])
  })
  result <- list(mean=current,departure=current-normal,percentile=rank)
  for(i in seq_along(result)) {names(result[[i]])<-paste0("tmean_water_year_",names(result)[i]);terra::time(result[[i]])<-as.Date(date)}
  result
}

build_current_prism_water_year_temperature_maps <- function(date=NULL,
    baseline_start=swc_prism$percentile_start,baseline_end=swc_prism$percentile_end,
    aoi_id=swc_prism$aoi_id,processed_dir=swc_paths$processed,maps_dir=swc_paths$maps,
    processed_manifest=read_prism_manifest(prism_processed_manifest_path(processed_dir)),
    map_products=c("mean","departure","percentile"),overwrite=TRUE,quiet=FALSE,
    logo_path=southwest_brand_logo_path()) {
  map_products <- match.arg(map_products,c("mean","departure","percentile"),several.ok=TRUE)
  if(is.null(date)) date <- latest_common_prism_date(c("maxt","mint"),aoi_id,processed_manifest)
  date <- as.Date(date)
  if(length(date)!=1L || is.na(date)) stop("Provide one valid temperature map date.")
  start <- prism_water_year_start(date)
  daily_dates <- prism_wy_temperature_dates(start,date)
  current <- prism_wy_temperature_sum(daily_dates,aoi_id,processed_manifest)/length(daily_dates)
  reference <- build_prism_water_year_temperature_cache(date,baseline_start,baseline_end,aoi_id,
    processed_dir,processed_manifest,quiet=quiet)
  rasters <- prism_water_year_temperature_comparisons(current,reference$raster,date)
  period <- format_prism_map_period(start,date)
  baseline <- paste0("relative to water years ",format(as.Date(baseline_start),"%Y"),"-",format(as.Date(baseline_end),"%Y"))
  records <- lapply(map_products,function(product) {
    id <- paste0("tmean_water_year_",product)
    raster_path <- file.path(processed_dir,"prism",aoi_id,"daily","water-year","tmean",product,paste0(date,".tif"))
    if(!overwrite && file.exists(raster_path)) stop("Temperature raster exists; set overwrite=TRUE.")
    write_prism_processed_raster(rasters[[product]],raster_path,datatype="FLT8S")
    if(product=="mean") {
      scale<-prism_temperature_value_scale("tmean");palette<-c("#313695","#4575b4","#91bfdb","#ffffbf","#fdae61","#d73027","#7f0000")
      title<-"mean temperature to date";label<-"Mean temperature (degrees F)"
    } else if(product=="departure") {
      scale<-list(limits=c(-10,10),breaks=c(-10,-5,-2,0,2,5,10));palette<-c("#313695","#4575b4","#abd9e9","#f7f7f7","#fdae61","#d73027","#7f0000")
      title<-"mean-temperature departure";label<-"Departure (degrees F)"
    } else {
      scale<-list(limits=c(0,100),breaks=c(0,10,25,50,75,90,100));palette<-c("#313695","#4575b4","#91bfdb","#f7f7f7","#fdae61","#d73027","#7f0000")
      title<-"mean-temperature percentile rank";label<-"Percentile rank"
    }
    plot <- southwest_raster_map(rasters[[product]],states=southwest_state_boundaries(),
      title=paste("Water year",prism_water_year(date),title),
      subtitle=if(product=="mean") period else paste(period,baseline,sep=" | "),
      caption=NULL,fill_label=label,palette=palette,
      palette_values=if(product=="percentile") c(0,10,25,50,75,90,100) else if(product=="departure") scale$breaks else NULL,
      limits=scale$limits,breaks=scale$breaks,labels=as.character(scale$breaks),
      counties=southwest_county_boundaries(),countries=southwest_country_boundaries(),
      cities=southwest_reference_cities(),rivers=southwest_major_rivers(),product_id=id,mask_to_states=FALSE)
    map_root<-file.path(maps_dir,"prism","temperature");dir.create(map_root,recursive=TRUE,showWarnings=FALSE)
    dated<-file.path(map_root,paste0("tmean-water-year-",product,"-",date,".png"))
    latest<-file.path(map_root,paste0("tmean-water-year-",product,"-latest.png"))
    if(!overwrite && (file.exists(dated)||file.exists(latest))) stop("Temperature map exists; set overwrite=TRUE.")
    save_southwest_map(plot,dated,logo_path=logo_path,
      footer_text=if(product=="mean") "Data source: PRISM Climate Group via RCC-ACIS" else prism_map_footer_text(baseline_start,baseline_end))
    if(!file.copy(dated,latest,overwrite=TRUE)) stop("Could not install latest temperature map.")
    data.frame(date=date,product=product,raster_path=raster_path,map_path=dated,latest_map_path=latest,
      cache_method=reference$build_method)
  })
  do.call(rbind,records)
}
