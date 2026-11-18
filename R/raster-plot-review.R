# Local-only geometry audit and before/after plotting. Never rewrites climate grids.
raster_plot_capture <- function(code) {
  messages <- character()
  value <- withCallingHandlers(code,warning=function(w) {
    messages <<- c(messages,conditionMessage(w));invokeRestart("muffleWarning")
  })
  list(value=value,warnings=unique(messages))
}

raster_plot_git <- function(configured=getOption("swc.raster.plot.git",""),candidates=NULL,.which=Sys.which) {
  if(length(configured)!=1L||is.na(configured))stop("Set swc.raster.plot.git to one Git executable path.")
  if(nzchar(configured)) {
    if(!file.exists(configured))stop("Configured Git executable does not exist: ",configured)
    return(normalizePath(configured,winslash="/",mustWork=TRUE))
  }
  if(is.null(candidates)) {
    roots <- c(Sys.getenv("ProgramFiles"),Sys.getenv("ProgramW6432"),Sys.getenv("ProgramFiles(x86)"),
      if(nzchar(Sys.getenv("LOCALAPPDATA")))file.path(Sys.getenv("LOCALAPPDATA"),"Programs"))
    roots <- roots[nzchar(roots)]
    candidates <- c(file.path(roots,"Git","cmd","git.exe"),file.path(roots,"Git","bin","git.exe"))
  }
  paths <- unique(c(unname(.which("git")),candidates))
  paths <- paths[nzchar(paths)&file.exists(paths)]
  if(!length(paths))stop("Git was not found in R's PATH or standard installation folders. Set options(swc.raster.plot.git = 'C:/path/to/git.exe') and rerun.",call.=FALSE)
  normalizePath(paths[1L],winslash="/",mustWork=TRUE)
}

raster_plot_legacy_environment <- function(commit="1c23270adfe1f17e47ff7f0cb9a4519f20a87f56") {
  if(!grepl("^[a-f0-9]{40}$",commit)) stop("Expected a full baseline commit hash.")
  git <- raster_plot_git()
  if(.Platform$OS.type=="windows")git <- utils::shortPathName(git)
  code <- system2(git,c("show",paste0(commit,":R/map-southwest.R")),stdout=TRUE)
  if(!is.null(attr(code,"status"))) stop("The reviewed baseline commit is unavailable locally.")
  env <- new.env(parent=environment(build_prism_freeze_free_map))
  eval(parse(text=code),envir=env)
  env
}

audit_raster_plot_geometry <- function(report_dir="data/diagnostics/raster-plot-review",status_path="data/diagnostics/map-product-status.csv") {
  status <- read.csv(status_path,stringsAsFactors=FALSE)
  dates <- unique(status$actual_data_date[status$validation_status=="PASS"&!is.na(status$actual_data_date)])
  roots <- file.path(swc_paths$processed,"prism",swc_prism$aoi_id,c("daily","seasonal"))
  paths <- unique(unlist(lapply(roots,list.files,pattern="[.]tif$",recursive=TRUE,full.names=TRUE)))
  paths <- paths[basename(paths) %in% paste0(dates,".tif")]
  if(!length(paths)) stop("No matching cached current-map grids; refresh the local cache/status first.")
  rows <- lapply(paths,function(path) {
    r <- terra::rast(path);if(terra::nlyr(r)!=1L)return(NULL)
    data <- terra::as.data.frame(r,xy=TRUE,na.rm=TRUE);names(data)[3L] <- "value"
    mapping <- ggplot2::aes(x,y,fill=value)
    old <- raster_plot_capture(ggplot2::ggplot_build(ggplot2::ggplot()+ggplot2::geom_raster(data=data,mapping=mapping)))
    fixed <- raster_plot_capture(ggplot2::ggplot_build(ggplot2::ggplot()+southwest_raster_layer(data,mapping,terra::res(r))))
    data.frame(path=path,cells=nrow(data),engine=southwest_raster_geometry(data,terra::res(r))$engine,
      before_warnings=paste(old$warnings,collapse=" | "),after_warnings=paste(fixed$warnings,collapse=" | "),
      md5=unname(tools::md5sum(path)))
  })
  result <- do.call(rbind,rows)
  dir.create(report_dir,recursive=TRUE,showWarnings=FALSE)
  write.csv(result,file.path(report_dir,"grid-audit.csv"),row.names=FALSE)
  if(any(nzchar(result$after_warnings)))stop("Fixed plotting emitted warnings; inspect grid-audit.csv.")
  message("Current PRISM grid audit: ",nrow(result)," cached fields; ",sum(nzchar(result$before_warnings)),
    " raw raster warnings before; 0 after. Published freeze-status overlays are checked separately.")
  result
}

build_raster_plot_review <- function(output_dir="data/diagnostics/raster-plot-review") {
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  previous <- options(swc.map.tribal=file.exists(southwest_reference_layer_path("tribal")),
    swc.map.rivers=FALSE,swc.map.interstates=FALSE)
  on.exit(options(previous),add=TRUE)
  legacy <- raster_plot_legacy_environment()
  audit <- audit_raster_plot_geometry(output_dir)
  status <- read.csv("data/diagnostics/map-product-status.csv",stringsAsFactors=FALSE)
  states <- southwest_state_boundaries();counties <- southwest_county_boundaries()
  countries <- southwest_country_boundaries();cities <- southwest_reference_cities()
  records <- list(); articles <- character()
  pair <- function(id,title,before,after,source=NULL,synthetic=FALSE) {
    first <- after$layers[[1L]]$data
    if(!identical(before$layers[[1L]]$data,first))stop("Display data changed: ",id)
    built <- raster_plot_capture(ggplot2::ggplot_build(after))
    if(length(built$warnings))stop("Fixed plot warning: ",id,": ",paste(built$warnings,collapse="; "))
    for(variant in c("before","after")) {
      plot <- if(variant=="before")before else after
      filename <- paste0(id,"-",variant,".png")
      captured <- raster_plot_capture(save_southwest_map(plot,file.path(output_dir,filename),
        logo_path=southwest_brand_logo_path(),footer_text=if(synthetic)"SYNTHETIC GEOMETRY TEST — not climate observations; not published" else "LOCAL PLOTTING REVIEW — cached data; not published"))
      records[[length(records)+1L]] <<- data.frame(id=id,variant=variant,source=if(is.null(source))"synthetic" else source,
        cells=nrow(first),geometry=class(plot$layers[[1L]]$geom)[1],warnings=paste(captured$warnings,collapse=" | "),file=filename)
      if(variant=="after"&&length(captured$warnings))stop("Fixed rendering emitted a warning: ",id)
      message("Raster plotting review: ",id," · ",variant," ready.")
    }
    articles <<- c(articles,paste0('<section><h2>',title,'</h2><div class="pair">',
      '<figure><figcaption>Before · production baseline</figcaption><a href="',id,'-before.png"><img src="',id,'-before.png" alt="Before: ',title,'"></a></figure>',
      '<figure><figcaption>After · native cell geometry</figcaption><a href="',id,'-after.png"><img src="',id,'-after.png" alt="After: ',title,'"></a></figure></div></section>'))
  }
  for(product in c("length","departure")) {
    id <- paste0("mint_freeze_free_",product)
    row <- status[status$id==id & status$validation_status=="PASS",,drop=FALSE]
    if(nrow(row)!=1L)stop("No verified cached map date: ",id)
    date <- as.Date(row$actual_data_date);year <- as.integer(format(date,"%Y"))
    path <- prism_freeze_free_output_path(product,year,date)
    if(!file.exists(path))stop("Cached derived grid missing: ",path)
    r <- terra::rast(path)
    if(!identical(as.Date(terra::time(r)),date))stop("Grid date mismatch: ",id)
    for(scale in c("continuous","categorical")) {
      # Select a display mode without changing configured production defaults.
      rebuild <- function(map_env) {
        builder <- build_prism_freeze_free_map;env <- new.env(parent=environment(builder))
        helper <- if(is.null(map_env))southwest_raster_map else map_env$southwest_raster_map
        env$southwest_raster_map <- function(...)helper(...,scale_type=scale)
        environment(builder)<-env
        builder(r,product,date,year,states=states,counties=counties,countries=countries,cities=cities)
      }
      pair(paste0(id,"-",scale),paste(row$label,"·",scale,"·",date),rebuild(legacy),rebuild(NULL),path)
    }
  }
  for(id in c("tmean_value","pcpn_total_30day")) {
    row <- status[status$id==id & status$validation_status=="PASS",,drop=FALSE]
    if(nrow(row)!=1L)stop("Missing dense-grid control: ",id)
    date <- as.Date(row$actual_data_date)
    path <- if(id=="tmean_value")prism_temperature_derived_output_path("tmean","value",date) else
      file.path(swc_paths$processed,"prism",swc_prism$aoi_id,"daily/accumulation/pcpn/30day",paste0(date,".tif"))
    r <- terra::rast(path)
    builder <- if(id=="tmean_value")build_prism_temperature_value_map else build_prism_accumulation_map
    old_builder <- builder;environment(old_builder)<-legacy
    args <- list(r,states=states,counties=counties,countries=countries,cities=cities)
    if(id=="tmean_value")args$variable<-"tmean" else {args$days<-30L;args$rivers<-NULL}
    pair(id,paste("Dense-grid control ·",row$label,"·",date),do.call(old_builder,args),do.call(builder,args),path)
  }
  # A regularly thinned grid can draw oversized pixels without any warning.
  r <- terra::rast(nrows=8,ncols=10,xmin=-115.5,xmax=-102.5,ymin=30.8,ymax=37.5,crs="EPSG:4326")
  values <- rep(NA_real_,terra::ncell(r));cells <- which(terra::colFromCell(r,seq_len(terra::ncell(r))) %in% c(2,4,6,8))
  values[cells] <- rep(c(0,1,2,3),length.out=length(cells));terra::values(r)<-values
  args <- list(raster=r,states=states,title="Synthetic check: missing columns remain empty",caption=NULL,
    counties=counties,countries=countries,cities=cities,tribal_areas=NULL,fill_label="Synthetic value",scale_type="continuous")
  pair("synthetic-gapped-grid","Synthetic gap check · not climate observations",do.call(legacy$southwest_raster_map,args),do.call(southwest_raster_map,args),synthetic=TRUE)
  report <- do.call(rbind,records)
  ids <- unique(report$id)
  differences <- vapply(ids,function(id) {
    compared <- magick::image_compare(magick::image_read(file.path(output_dir,paste0(id,"-before.png"))),
      magick::image_read(file.path(output_dir,paste0(id,"-after.png"))),metric="AE")
    as.numeric(attr(compared,"distortion"))
  },numeric(1))
  report$changed_pixel_fraction <- unname(differences[report$id])
  if(any(differences[c("tmean_value","pcpn_total_30day")]!=0))stop("An unaffected dense-grid control changed visually.")
  unchanged <- identical(unname(tools::md5sum(audit$path)),audit$md5)
  if(!unchanged)stop("An input grid changed during review; rerun from a stable cache.")
  write.csv(report,file.path(output_dir,"map-review.csv"),row.names=FALSE)
  write.csv(data.frame(status="PASS",grids=nrow(audit),raw_warnings_before=sum(nzchar(audit$before_warnings)),
    raw_warnings_after=sum(nzchar(audit$after_warnings)),review_pairs=length(articles),input_grids_unchanged=unchanged),file.path(output_dir,"summary.csv"),row.names=FALSE)
  writeLines(c('<!doctype html><html><head><meta charset="utf-8"><title>Raster plotting geometry review</title><style>body{font:16px system-ui;max-width:1700px;margin:auto;padding:20px;color:#243b46}.pair{display:grid;grid-template-columns:1fr 1fr;gap:16px}figure{margin:0}figcaption{font-weight:bold;margin:8px 0}img{width:100%}section{margin:28px 0}a{color:#176d88}@media(max-width:800px){.pair{grid-template-columns:1fr}}</style></head><body>',
    '<h1>Raster plotting geometry review</h1><p>Cached freeze-free length and departure maps, in continuous and categorical display modes. Left: production baseline. Right: explicit native-size cells for sparse data. Numerical values, masks, reference periods and dates are unchanged. Click an image for full resolution.</p>',
    '<p>First/last-freeze status maps already use explicit cells; the shared helper now protects other sparse maps too. Dense-grid temperature and precipitation controls must remain pixel-identical. The final example is synthetic and demonstrates a silent oversized-cell case.</p>',
    '<p><a href="summary.csv">Summary</a> · <a href="grid-audit.csv">Cached-grid audit</a> · <a href="map-review.csv">Map/warning report</a></p>',articles,'</body></html>'),file.path(output_dir,"index.html"),useBytes=TRUE)
  message("Local raster review ready: ",output_dir,"/index.html. No downloads, grid writes, operational map changes or publication.")
  invisible(list(audit=audit,maps=report))
}
