# Re-render only affected PNGs from exact cached derived grids. No calculations/downloads.
rebuild_cached_freeze_free_maps <- function(output_dir=swc_paths$maps,
    processed_dir=swc_paths$processed,source_maps_dir=swc_paths$maps,
    status_path="data/diagnostics/map-product-status.csv",config_path="config/map-products.yml",
    report_dir="data/diagnostics/raster-plot-rebuild") {
  status <- read.csv(status_path,stringsAsFactors=FALSE)
  config <- yaml::read_yaml(config_path)
  jobs <- list()
  # Verify both inputs before touching either published output.
  for(product in c("length","departure")) {
    id <- paste0("mint_freeze_free_",product);p <- config$products[[id]]
    enabled <- !is.null(p)&&isTRUE(if(is.null(p$enabled)) {
      if(is.null(config$defaults$enabled))TRUE else config$defaults$enabled
    } else p$enabled)
    if(!enabled)next
    row <- status[status$id==id,,drop=FALSE]
    if(nrow(row)!=1L||!isTRUE(row$enabled)||row$validation_status!="PASS")stop("No passing map record: ",id)
    date <- as.Date(row$actual_data_date);year <- as.integer(format(date,"%Y"))
    if(length(date)!=1L||is.na(date))stop("Missing verified date: ",id)
    image <- file.path(source_maps_dir,p$image)
    if(!file.exists(image)||!identical(unname(tools::md5sum(image)),as.character(row$image_md5)))
      stop("Map/status fingerprint mismatch: ",id,". Run scripts/build-map-product-site.R first.")
    source <- prism_freeze_free_output_path(product,year,date,processed_dir=processed_dir)
    if(!file.exists(source))stop("Exact cached derived grid missing: ",source)
    r <- terra::rast(source)
    if(terra::nlyr(r)!=1L||!identical(as.Date(terra::time(r)),date))stop("Cached derived grid date mismatch: ",id)
    if(!any(is.finite(terra::values(r,mat=FALSE))))stop("No supported cells: ",id)
    jobs[[id]] <- list(id=id,product=product,date=date,year=year,raster=r,source=source,
      md5=unname(tools::md5sum(source)),latest=file.path(output_dir,p$image),
      dated=prism_freeze_free_map_path(product,date,maps_dir=output_dir))
  }
  if(!length(jobs))stop("Both affected maps are disabled; no rebuild requested.")
  prepared <- file.path(report_dir,"prepared");dir.create(prepared,recursive=TRUE,showWarnings=FALSE)
  for(id in names(jobs)) {
    j <- jobs[[id]]
    message("Re-rendering cached map: ",id," · ",j$date)
    plot <- build_prism_freeze_free_map(j$raster,j$product,j$date,j$year)
    path <- file.path(prepared,paste0(id,".png"))
    warnings <- character()
    withCallingHandlers(save_southwest_map(plot,path,logo_path=southwest_brand_logo_path(),
      footer_text=if(j$product=="length")"Data source: PRISM Climate Group via RCC-ACIS" else prism_map_footer_text()),
      warning=function(w){warnings<<-c(warnings,conditionMessage(w));invokeRestart("muffleWarning")})
    if(length(warnings))stop("Map rendering warned; outputs not installed: ",paste(unique(warnings),collapse="; "))
    if(!identical(readBin(path,"raw",n=8),as.raw(c(137,80,78,71,13,10,26,10))))stop("Invalid prepared PNG: ",id)
    jobs[[id]]$prepared <- path
  }
  for(j in jobs)if(!identical(unname(tools::md5sum(j$source)),j$md5))stop("A cached input changed; no PNGs installed.")
  rows <- lapply(jobs,function(j) {
    for(destination in unique(c(j$dated,j$latest))) {
      dir.create(dirname(destination),recursive=TRUE,showWarnings=FALSE)
      if(!file.copy(j$prepared,destination,overwrite=TRUE)||
          !identical(unname(tools::md5sum(destination)),unname(tools::md5sum(j$prepared))))stop("PNG installation failed: ",destination)
    }
    data.frame(id=j$id,date=as.character(j$date),source=j$source,source_md5=j$md5,
      input_unchanged=identical(unname(tools::md5sum(j$source)),j$md5),dated_map=j$dated,latest_map=j$latest,status="PASS")
  })
  report <- do.call(rbind,rows);rownames(report)<-NULL
  write.csv(report,file.path(report_dir,"status.csv"),row.names=FALSE)
  print(report[,c("id","date","input_unchanged","status")],row.names=FALSE)
  message("Cached freeze-free maps rebuilt; derived grids and comparison caches unchanged. No downloads or publication.")
  invisible(report)
}
