# Follow accepted Monthly Climate releases, then refresh cached daily/current data.
interactive_write_manifest <- function(manifest,folder) {
  temporary <- tempfile(fileext=".json"); on.exit(unlink(temporary),add=TRUE)
  jsonlite::write_json(manifest,temporary,auto_unbox=TRUE,pretty=TRUE,digits=16)
  interactive_pilot_copy(temporary,file.path(folder,"manifest.json"))
}

interactive_accepted_monthly <- function(site_dir="site") {
  checked <- validate_prism_monthly_publication(site_dir=site_dir,
    report_dir="data/diagnostics/interactive-monthly-publication")
  if(checked$summary$status!="PASS") stop("Interactive Maps requires a verified accepted Monthly Climate release.")
  doc <- xml2::read_html(file.path(site_dir,"pages/monthly-climate.qmd"))
  src <- xml2::xml_attr(xml2::xml_find_first(doc,'//img[@data-monthly-map]'),"src")
  path <- file.path(site_dir,"pages",dirname(src),"manifest.json")
  release <- jsonlite::read_json(path,simplifyVector=TRUE)
  list(end_month=release$end_month,version=release$version,products=release$products,path=path)
}

interactive_monthly_sources <- function(release,ranking_dir,spi_dir) {
  definitions <- interactive_pilot_definitions(release$end_month,ranking_dir,spi_dir)
  files <- character()
  for(d in definitions) {
    path <- file.path(d$folder,"complete.rds")
    if(!file.exists(path)) stop("Monthly numerical sources incomplete: ",d$folder)
    marker <- readRDS(path)
    if(!length(marker$files)||length(marker$files)!=length(marker$md5)||any(!file.exists(marker$files))||
        !identical(unname(tools::md5sum(marker$files)),marker$md5)) stop("Monthly numerical source integrity failed: ",d$folder)
    png <- file.path(d$folder,if(d$family=="spi")"spi.png" else paste0(d$family,"-ranking.png"))
    row <- release$products[release$products$family==d$family & release$products$duration==d$duration,,drop=FALSE]
    if(nrow(row)!=1L||!png %in% marker$files||!file.exists(png)||
        !identical(unname(tools::md5sum(png)),as.character(row$md5)))
      stop("Monthly numerical products differ from the accepted map release: ",d$folder)
    files <- c(files,path,marker$files)
  }
  files <- sort(unique(c(files,"R/interactive-map-pilot.R")))
  digest::digest(list(policy="accepted-monthly-viewer-v1",files=files,md5=unname(tools::md5sum(files))),algo="sha256")
}

interactive_refresh_monthly <- function(release,output_dir,
    cache_root="data/processed/interactive-map-monthly-releases",
    ranking_dir="data/diagnostics/prism-monthly-ranking-pilots",spi_dir="data/diagnostics/prism-monthly-spi-pilots",
    .sources=interactive_monthly_sources,.build=build_interactive_map_pilot) {
  if(!grepl("^[0-9]{4}-[0-9]{2}-[a-f0-9]+$",release$version)) stop("Invalid monthly release version.")
  cache <- file.path(cache_root,release$version)
  held <- tryCatch(copy_interactive_monthly_seed(cache,cache,verify_only=TRUE)$manifest,error=function(e)NULL)
  valid <- !is.null(held)&&identical(held$end_month,release$end_month)&&identical(held$monthly_release$version,release$version)
  source <- tryCatch(.sources(release,ranking_dir,spi_dir),error=function(e)e)
  retained <- FALSE; reused <- FALSE
  if(inherits(source,"error")) {
    if(!valid) stop("No matching verified viewer monthly release: ",conditionMessage(source))
    retained <- TRUE; reused <- TRUE
    message("Interactive monthly sources unavailable; retaining verified release ",release$version,". ",conditionMessage(source))
  }else if(valid&&identical(held$monthly_release$signature,source)) reused <- TRUE else {
    built <- .build(output_dir=cache,end=release$end_month,ranking_dir=ranking_dir,spi_dir=spi_dir)
    built$manifest$monthly_release <- list(version=release$version,signature=source)
    interactive_write_manifest(built$manifest,cache)
  }
  result <- copy_interactive_monthly_seed(cache,output_dir)
  result$monthly_reused <- reused; result$monthly_retained <- retained
  result
}

interactive_refresh_signature <- function(release,days) {
  m <- read_prism_manifest(prism_processed_manifest_path())
  rows <- m[m$product=="daily"&m$aoi_id==swc_prism$aoi_id&m$variable %in% c("pcpn","maxt","mint")&file.exists(m$path),,drop=FALSE]
  if(!nrow(rows)) stop("No cached daily PRISM inputs for viewer refresh.")
  latest <- max(rows$end_date)
  daily <- rows$path[rows$end_date>=latest-as.integer(days)+1L]
  normals <- vapply(c("maxt","mint"),daily_explorer_reference_path,character(1),statistic="mean")
  specs <- interactive_current_definitions()
  status <- read.csv("data/diagnostics/map-product-status.csv",stringsAsFactors=FALSE)
  current <- vapply(seq_len(nrow(specs)),function(i) {
    date <- status$actual_data_date[match(specs$id[i],status$id)]
    file.path("data/processed/prism/az-nm-pad050/daily",specs$folder[i],paste0(date,".tif"))
  },character(1))
  definitions <- interactive_pilot_definitions(release$end_month)
  monthly <- unlist(lapply(definitions,function(d) {
    marker <- file.path(d$folder,"complete.rds")
    c(marker,if(file.exists(marker))tryCatch(readRDS(marker)$files,error=function(e)character()) else character())
  }))
  files <- sort(unique(c(daily,normals,current,monthly,release$path,
    prism_processed_manifest_path(),prism_climatology_manifest_path(),"data/diagnostics/map-product-status.csv",
    list.files("R",pattern="\\.R$",full.names=TRUE),list.files("config",recursive=TRUE,full.names=TRUE),
    list.files("scripts/interactive-map-assets",full.names=TRUE),
    "site/stations/leaflet.js","site/stations/leaflet.css","site/stations/leaflet-package-LICENSE")))
  hashes <- rep("MISSING",length(files)); exists <- file.exists(files)
  hashes[exists] <- unname(tools::md5sum(files[exists]))
  digest::digest(list(policy="viewer-auto-refresh-v1",days=days,release=release$version,files=files,md5=hashes),algo="sha256")
}

refresh_interactive_map_site <- function(site_dir="site",output_dir="data/diagnostics/interactive-map-pilot",
    days=getOption("swc.interactive.daily_days",30L),cache_root="data/processed/interactive-map-monthly-releases") {
  if(length(days)!=1L||!is.finite(days)||days!=as.integer(days)||days<1L||days>90L) stop("Daily retention must be 1-90 calendar days.")
  started <- proc.time()[["elapsed"]]
  release <- interactive_accepted_monthly(site_dir)
  signature <- interactive_refresh_signature(release,days)
  stamp_path <- file.path(output_dir,"refresh-state.rds")
  stamp <- if(file.exists(stamp_path))tryCatch(readRDS(stamp_path),error=function(e)NULL) else NULL
  if(identical(stamp$signature,signature)&&isTRUE(tryCatch({validate_interactive_map_site(site_dir);TRUE},error=function(e)FALSE))) {
    result <- stamp$result; result$status <- "REUSED"
  }else {
    pilot <- interactive_refresh_monthly(release,output_dir,cache_root=cache_root)
    for(name in c("index.html","pilot.js","pilot.css")) interactive_pilot_copy(file.path("scripts/interactive-map-assets",name),file.path(output_dir,name))
    for(name in c("leaflet.js","leaflet.css","leaflet-package-LICENSE")) interactive_pilot_copy(file.path("site/stations",name),file.path(output_dir,name))
    pilot <- add_interactive_daily_maps(pilot,days=days,output_dir=output_dir)
    pilot <- add_interactive_current_maps(pilot,output_dir=output_dir)
    stopifnot(all(pilot$checks$passed))
    stage_interactive_map_site(pilot_dir=output_dir,site_dir=site_dir)
    result <- list(status="READY",monthly_end=release$end_month,monthly_version=release$version,
      monthly_retained=pilot$monthly_retained,daily_through=pilot$manifest$daily$latest_date,
      daily_bundles=sum(vapply(pilot$manifest$layers,function(x)identical(x$frequency,"daily"),logical(1))),
      current_products=length(pilot$manifest$current$products),
      current_unavailable=sum(!vapply(pilot$manifest$current$products,function(x)isTRUE(x$available),logical(1))))
    dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
    saveRDS(list(signature=signature,result=result),stamp_path)
  }
  result$elapsed_seconds <- round(proc.time()[["elapsed"]]-started,3)
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  write.csv(as.data.frame(result),file.path(output_dir,"workflow-status.csv"),row.names=FALSE)
  message("Interactive Maps: ",result$status,"; ",result$daily_bundles," daily bundles through ",result$daily_through,
    "; ",result$current_products," current products (",result$current_unavailable," unavailable); monthly ",result$monthly_end,
    if(isTRUE(result$monthly_retained))" (verified retained release)" else "","; ",result$elapsed_seconds,"s.")
  invisible(result)
}
