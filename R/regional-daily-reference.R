# Local-only daily climate references. Inputs stay read-only; no download hooks.
regional_daily_specs <- function() list(
  wet_days = list(label = "Wet days", units = "Average days", breaks = c(-Inf,1,5,10,20,30,45,60,90,Inf),
    labels = c("<1","1-5","5-10","10-20","20-30","30-45","45-60","60-90",">=90")),
  wet_amount = list(label = "Average precipitation per wet day", units = "Inches per wet day", breaks = c(-Inf,.1,.15,.2,.25,.3,.4,.5,.75,Inf),
    labels = c("<0.10","0.10-0.15","0.15-0.20","0.20-0.25","0.25-0.30","0.30-0.40","0.40-0.50","0.50-0.75",">=0.75")),
  heavy_days = list(label = "Heavy-precipitation days", units = "Average days", breaks = c(-Inf,.1,.25,.5,1,2,3,5,10,Inf),
    labels = c("<0.1","0.1-0.25","0.25-0.5","0.5-1","1-2","2-3","3-5","5-10",">=10")),
  freeze_days = list(label = "Freeze nights", units = "Average nights", breaks = c(-Inf,1,5,10,20,40,60,90,120,Inf),
    labels = c("<1","1-5","5-10","10-20","20-40","40-60","60-90","90-120",">=120")),
  hot_days = list(label = "Hot days", units = "Average days", breaks = c(-Inf,1,5,10,20,40,60,90,120,Inf),
    labels = c("<1","1-5","5-10","10-20","20-40","40-60","60-90","90-120",">=120")))

regional_daily_thresholds <- function() c(wet = .04, heavy = 1, freeze = 32, hot = 90)

regional_daily_dates_match <- function(actual, expected) {
  actual <- as.Date(actual); expected <- as.Date(expected)
  length(actual) == length(expected) && !anyNA(actual) && !anyNA(expected) &&
    all(as.numeric(actual) == as.numeric(expected))
}

regional_daily_month_stats <- function(p, lo, hi, thresholds = regional_daily_thresholds()) {
  stopifnot(is.matrix(p), identical(dim(p), dim(lo)), identical(dim(p), dim(hi)))
  p[!is.finite(p) | p < 0 | p > swc_prism$plausible_ranges$pcpn[2]] <- NA_real_
  invalid_pair <- is.finite(lo) & is.finite(hi) & lo > hi
  lo[!is.finite(lo) | lo < swc_prism$plausible_ranges$mint[1] | lo > swc_prism$plausible_ranges$mint[2] | invalid_pair] <- NA_real_
  hi[!is.finite(hi) | hi < swc_prism$plausible_ranges$maxt[1] | hi > swc_prism$plausible_ranges$maxt[2] | invalid_pair] <- NA_real_
  wet <- prism_is_wet_day(p, thresholds[['wet']])
  cbind(wet_days = rowSums(wet, na.rm = TRUE), wet_sum = rowSums(ifelse(wet, p, 0), na.rm = TRUE),
    heavy_days = rowSums(prism_is_wet_day(p, thresholds[['heavy']]), na.rm = TRUE),
    freeze_days = rowSums(lo <= thresholds[['freeze']] + 1e-6, na.rm = TRUE),
    hot_days = rowSums(hi >= thresholds[['hot']] - 1e-6, na.rm = TRUE),
    p_days = rowSums(is.finite(p)), lo_days = rowSums(is.finite(lo)), hi_days = rowSums(is.finite(hi)))
}

regional_daily_finalize <- function(stats, expected_days) {
  stats[stats[, 'p_days'] != expected_days, c('wet_days','wet_sum','heavy_days')] <- NA_real_
  stats[stats[, 'lo_days'] != expected_days, 'freeze_days'] <- NA_real_
  stats[stats[, 'hi_days'] != expected_days, 'hot_days'] <- NA_real_
  stats
}

regional_daily_average <- function(year_stats) {
  stopifnot(length(year_stats) > 0L)
  fields <- c('wet_days','wet_amount','heavy_days','freeze_days','hot_days')
  result <- support <- matrix(NA_real_, nrow(year_stats[[1]]), length(fields), dimnames = list(NULL, fields))
  for (field in fields) {
    input <- if (field == 'wet_amount') 'wet_days' else field
    values <- matrix(vapply(year_stats, function(x) x[, input], numeric(nrow(result))), nrow = nrow(result))
    n <- rowSums(is.finite(values)); support[, field] <- n
    if (field == 'wet_amount') {
      amounts <- matrix(vapply(year_stats, function(x) x[, 'wet_sum'], numeric(nrow(result))), nrow = nrow(result))
      value <- rowSums(amounts) / rowSums(values)
      value[rowSums(values) == 0] <- NA_real_
    } else value <- rowMeans(values)
    value[n != length(year_stats)] <- NA_real_
    result[, field] <- value
  }
  list(values = result, support = support)
}

plan_regional_daily_reference <- function(output_dir = 'data/diagnostics/regional-daily-reference-pilot') {
  manifest <- read_prism_manifest(prism_processed_manifest_path())
  months <- format(seq(as.Date('1991-01-01'), as.Date('2020-12-01'), by = 'month'), '%Y-%m')
  plan <- expand.grid(variable = c('pcpn','mint','maxt'), month = months, stringsAsFactors = FALSE)
  plan$path <- plan$md5 <- plan$note <- ''; plan$complete <- FALSE
  for (i in seq_len(nrow(plan))) {
    start <- as.Date(paste0(plan$month[i], '-01')); end <- seq(start, by='month', length.out=2)[2] - 1
    selected <- manifest[manifest$product == 'daily' & manifest$aoi_id == swc_prism$aoi_id &
      manifest$variable == plan$variable[i] & manifest$start_date == start & manifest$end_date == end, ]
    if (nrow(selected) != 1L) {plan$note[i] <- 'Expected one verified full-month daily archive'; next}
    plan$path[i] <- selected$path; plan$md5[i] <- selected$md5
    expected_units <- if (plan$variable[i] == 'pcpn') 'inch' else 'degreeF'
    plan$complete[i] <- identical(selected$native_units, expected_units) && file.exists(selected$path) && identical(unname(tools::md5sum(selected$path)), selected$md5)
    if (!plan$complete[i]) plan$note[i] <- 'Missing file or processed checksum mismatch'
    if (i %% 90L == 0L) message('Daily reference input check: ',i,'/',nrow(plan),' files.')
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  write.csv(plan, file.path(output_dir, 'input-plan.csv'), row.names = FALSE)
  message('Daily reference inputs: ', sum(plan$complete), '/', nrow(plan), ' verified; no downloads.')
  plan
}

plot_regional_daily_reference <- function(raster, metric, period) {
  spec <- regional_daily_specs()[[metric]]; threshold <- regional_daily_thresholds()
  colors <- if (metric == 'hot_days') c('#ffffcc','#ffeda0','#fed976','#feb24c','#fd8d3c','#fc4e2a','#e31a1c','#bd0026','#800026') else
    c('#f7fbff','#deebf7','#c6dbef','#9ecae1','#6baed6','#4292c6','#2171b5','#08519c','#08306b')
  data <- terra::as.data.frame(raster, xy = TRUE, na.rm = FALSE); names(data) <- c('x','y','value')
  cls <- as.character(cut(data$value, spec$breaks, labels = spec$labels, right = FALSE)); cls[!is.finite(data$value)] <- 'Unavailable'
  data$class <- factor(cls, levels = c(spec$labels,'Unavailable'))
  definition <- switch(metric, wet_days = 'Daily precipitation >=0.04 inch', wet_amount = 'Wet days >=0.04 inch; pooled wet-day amounts',
    heavy_days = 'Daily precipitation >=1 inch', freeze_days = 'Daily minimum <=32 F', hot_days = 'Daily maximum >=90 F')
  period_label <- if (period == 'annual') 'Annual: January-December' else paste(regional_reference_seasons()[[period]]$label, regional_reference_seasons()[[period]]$text)
  base <- plot_regional_climate_reference(raster, 'precipitation', 1991:2020)
  base$layers[[1]] <- ggplot2::geom_tile(data = data, ggplot2::aes(x,y,fill=class), width=terra::res(raster)[1],height=terra::res(raster)[2])
  suppressMessages(base + ggplot2::scale_fill_manual(values=stats::setNames(c(colors,'#ede8df'),levels(data$class)),drop=FALSE,name=spec$units) +
    ggplot2::labs(title=paste(spec$label, '-', period_label), subtitle=paste('1991-2020 |', definition)))
}

build_regional_daily_reference_pilot <- function(output_dir = 'data/diagnostics/regional-daily-reference-pilot', force = FALSE) {
  if (!is.logical(force) || length(force) != 1L || is.na(force)) stop('force must be TRUE or FALSE.')
  started <- proc.time()[['elapsed']]
  plan <- plan_regional_daily_reference(output_dir)
  if (!all(plan$complete)) stop('Daily inputs are incomplete. Inspect input-plan.csv; no downloads attempted.')
  template <- terra::rast(plan$path[1])[[1]]; n <- terra::ncell(template)
  periods <- c('annual', names(regional_reference_seasons())); metrics <- names(regional_daily_specs())
  method <- digest::digest(list(regional_daily_thresholds(), swc_prism$plausible_ranges,
    swc_prism$wet_day_storage_tolerance_inches, regional_reference_seasons(), regional_reference_function_text(list(
    regional_daily_month_stats, regional_daily_finalize, regional_daily_average, prism_is_wet_day)), 'daily-reference-v1'), algo='sha256')
  year_paths <- character(); built <- reused <- 0L
  for (year in 1991:2020) {
    rows <- plan[substr(plan$month,1,4)==as.character(year), ]
    signature <- digest::digest(list(rows[c('month','variable','md5')],method), algo='sha256')
    path <- file.path(output_dir,'years',paste0(year,'.rds')); marker <- paste0(path,'.complete.rds')
    saved <- if (file.exists(marker)) tryCatch(readRDS(marker),error=function(e) NULL) else NULL
    if (!force && is.list(saved) && identical(saved$signature,signature) && file.exists(path) && identical(unname(tools::md5sum(path)),saved$md5)) {
      reused <- reused+1L; message('Daily reference ',year,': REUSED.')
    } else {
      quarters <- lapply(1:4,function(q) matrix(0,n,8,dimnames=list(NULL,c('wet_days','wet_sum','heavy_days','freeze_days','hot_days','p_days','lo_days','hi_days'))))
      days <- integer(4)
      for (month in 1:12) {
        key <- sprintf('%d-%02d',year,month); rasters <- lapply(c('pcpn','mint','maxt'),function(variable) {
          p <- rows$path[rows$month==key & rows$variable==variable]
          r <- read_prism_daily_raster(p, variable, validate_values=FALSE)
          dates <- seq(as.Date(paste0(key,'-01')),seq(as.Date(paste0(key,'-01')),by='month',length.out=2)[2]-1,by='day')
          if (!regional_daily_dates_match(terra::time(r),dates)) stop('Missing or misordered daily layers: ',p)
          terra::compareGeom(template,r,stopOnError=TRUE,tolerance=0); terra::values(r,mat=TRUE)
        })
        q <- (month-1L)%/%3L+1L
        quarters[[q]] <- quarters[[q]] + regional_daily_month_stats(rasters[[1]],rasters[[2]],rasters[[3]])
        days[q] <- days[q]+ncol(rasters[[1]])
        if (month%%3==0) message('Daily reference ',year,': ',month,'/12 months summarized.')
      }
      all <- c(list(regional_daily_finalize(Reduce('+',quarters),sum(days))), lapply(1:4,function(q) regional_daily_finalize(quarters[[q]],days[q])))
      names(all) <- periods
      dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE); temporary <- paste0(path,'.tmp')
      saveRDS(all,temporary); if (!file.copy(temporary,path,overwrite=TRUE)) stop('Could not install year cache'); unlink(temporary)
      saveRDS(list(signature=signature,md5=unname(tools::md5sum(path))),marker); built <- built+1L
    }
    year_paths <- c(year_paths,path)
  }
  dependencies <- unname(tools::md5sum(year_paths))
  render_signature <- digest::digest(list(dependencies,regional_daily_specs(),regional_reference_seasons(),regional_reference_function_text(list(plot_regional_daily_reference,plot_regional_climate_reference))),algo='sha256')
  marker <- file.path(output_dir,'complete.rds'); saved <- if (file.exists(marker)) tryCatch(readRDS(marker),error=function(e) NULL) else NULL
  if (!force && is.list(saved) && identical(saved$signature,render_signature) && all(file.exists(saved$files)) && identical(unname(tools::md5sum(saved$files)),saved$md5)) {
    message('Daily reference maps: all 25 REUSED.'); return(invisible(saved$summary))
  }
  files <- character(); summary <- list()
  for (period in periods) {
    refs <- regional_daily_average(lapply(year_paths,function(path) readRDS(path)[[period]]))
    dir.create(file.path(output_dir,period),recursive=TRUE,showWarnings=FALSE)
    for (metric in metrics) {
      raster <- terra::setValues(template,refs$values[,metric]); names(raster) <- metric
      stem <- file.path(output_dir,period,metric); tif <- paste0(stem,'.tif'); png <- paste0(stem,'.png'); coverage <- paste0(stem,'-sample-years.tif')
      terra::writeRaster(raster,tif,overwrite=TRUE,datatype='FLT4S',gdal='COMPRESS=DEFLATE')
      terra::writeRaster(terra::setValues(template,refs$support[,metric]),coverage,overwrite=TRUE,datatype='INT1U',gdal='COMPRESS=DEFLATE')
      message('Rendering ',period,' / ',metric,'.')
      save_southwest_map(plot_regional_daily_reference(raster,metric,period),png,logo_path=southwest_brand_logo_path(),
        footer_text='Data: PRISM Climate Group via RCC-ACIS | 1991-2020; 30 complete periods required\nProject-calculated daily reference | Climate Science Applications Program - University of Arizona')
      files <- c(files,tif,png,coverage)
      summary[[length(summary)+1L]] <- data.frame(period=period,metric=metric,valid_cells=sum(is.finite(refs$values[,metric])),file=png)
    }
  }
  summary <- do.call(rbind,summary); write.csv(summary,file.path(output_dir,'summary.csv'),row.names=FALSE)
  methods <- data.frame(metric=metrics,definition=c('Mean annual/quarter days with precipitation >=0.04 inch','Sum of precipitation on wet days / number of wet days across 30 complete periods; not mean yearly intensity',
    'Mean days with daily precipitation >=1 inch','Mean nights with minimum temperature <=32 F','Mean days with maximum temperature >=90 F'),
    reference='1991-2020',support='All 30 complete periods separately by variable; no zero filling. No wet days: intensity withheld.',seasons='JFM/AMJ/JAS/OND calendar quarters')
  write.csv(methods,file.path(output_dir,'methods.csv'),row.names=FALSE)
  files <- c(files,file.path(output_dir,c('summary.csv','methods.csv')))
  html <- c('<!doctype html><html><head><meta charset="utf-8"><title>Daily regional reference maps</title><style>body{font:16px system-ui;max-width:1500px;margin:24px auto;padding:16px}img{width:100%}.maps{display:grid;grid-template-columns:1fr 1fr;gap:18px}@media(max-width:800px){.maps{grid-template-columns:1fr}}</style></head><body>',
    '<h1>Regional daily climate references: 1991–2020</h1><p>Local review. Annual and calendar quarters; 30 complete periods required. Zero counts remain zero. Beige means unavailable. Intensity is pooled over wet days, not all calendar days.</p><p><a href="methods.csv">Methods</a> · <a href="summary.csv">Summary</a></p>')
  for (period in periods) {
    html <- c(html,paste0('<h2>',period,'</h2><div class="maps">'))
    for (metric in metrics) {file <- paste0(period,'/',metric,'.png'); html <- c(html,paste0('<article><a href="',file,'"><img loading="lazy" src="',file,'" alt="',period,' ',metric,'"></a></article>'))}
    html <- c(html,'</div>')
  }
  writeLines(c(html,'</body></html>'),file.path(output_dir,'index.html'),useBytes=TRUE)
  files <- c(files,file.path(output_dir,'index.html'))
  saveRDS(list(signature=render_signature,files=files,md5=unname(tools::md5sum(files)),summary=summary),marker)
  message('Local daily references ready: 25 maps; ',built,' years built, ',reused,' reused; ',round(proc.time()[['elapsed']]-started),' seconds. No downloads or publication.')
  invisible(summary)
}
