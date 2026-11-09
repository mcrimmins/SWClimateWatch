# Cached SNODAS context. Areas are AZ/NM state-center cells, not the padded map domain.
synopsis_snow_settings <- function(config) {
  x <- utils::modifyList(list(minimum_median_inches=1, minimum_reference_years=18,
    snow_threshold_inches=0.1, change_threshold_inches=0.25, minimum_area_km2=500,
    minimum_signal_percent=20, low_percent_median=75, high_percent_median=125,
    maximum_age_days=2), if(is.null(config$snow)) list() else config$snow)
  if(any(!vapply(x,function(v) is.numeric(v)&&length(v)==1L&&is.finite(v)&&v>0,logical(1))) ||
    x$minimum_reference_years < 18 || x$minimum_reference_years > 21 ||
    x$minimum_reference_years != floor(x$minimum_reference_years) ||
    x$low_percent_median >= 100 || x$high_percent_median <= 100 || x$minimum_signal_percent > 100)
    stop("Invalid synopsis snow thresholds.")
  x
}

synopsis_snow_stats <- function(current, median, years, previous, weights, config) {
  s <- synopsis_snow_settings(config)
  if(any(lengths(list(current,median,years,weights)) != length(current)) ||
    (!is.null(previous)&&length(previous)!=length(current))) stop("Snow vectors must align.")
  inside <- is.finite(weights)&weights>0
  if(any(is.finite(current)&current<0) || any(is.finite(median)&median<0)) stop("Negative snow input.")
  reference <- inside & is.finite(median)&median>=s$minimum_median_inches &
    is.finite(years)&years>=s$minimum_reference_years
  summarize <- function(mask, valid, metrics) {
    area <- sum(weights[mask]); good <- mask & valid
    coverage <- if(area>0) sum(weights[good])/area else 0
    status <- if(area<s$minimum_area_km2) "SMALL_REFERENCE_AREA" else
      if(coverage<config$minimum_area_coverage) "LOW_COVERAGE" else "AVAILABLE_CACHED"
    values <- if(status=="AVAILABLE_CACHED") metrics(good) else NULL
    list(status=status,area_km2=area,coverage=coverage,values=values)
  }
  storage <- summarize(reference,is.finite(current),function(g) {
    ratio <- 100*current[g]/median[g]; w<-weights[g]
    c(mean_swe_inches=weighted.mean(current[g],w),mean_median_inches=weighted.mean(median[g],w),
      area_below_median_percent=100*sum(w[ratio<s$low_percent_median])/sum(w),
      area_above_median_percent=100*sum(w[ratio>s$high_percent_median])/sum(w))
  })
  change <- list(status="NO_EXACT_PRIOR",values=NULL,area_km2=0,coverage=0)
  if(!is.null(previous)) {
    # Eligible footprint includes current/prior snow and normally snowy terrain;
    # missing endpoints remain missing, never zero or a snow-loss signal.
    footprint <- inside & (reference | (is.finite(current)&current>=s$snow_threshold_inches) |
      (is.finite(previous)&previous>=s$snow_threshold_inches))
    change <- summarize(footprint,is.finite(current)&is.finite(previous),function(g) {
      delta<-current[g]-previous[g];w<-weights[g]
      c(mean_change_inches=weighted.mean(delta,w),
        area_gain_percent=100*sum(w[delta>=s$change_threshold_inches])/sum(w),
        area_loss_percent=100*sum(w[delta<= -s$change_threshold_inches])/sum(w))
    })
  }
  list(storage=storage,change=change)
}

synopsis_snow_evidence <- function(root,date,config,output_dir) {
  date<-as.Date(date); s<-synopsis_snow_settings(config)
  result<-list(status="UNAVAILABLE",facts=data.frame(),active=format(date,"%m") %in% c("10","11","12","01","02","03","04","05"),
    note="No supported snow summary for this cutoff.",cache_reused=FALSE)
  if(!result$active) {result$status<-"INACTIVE_SEASON";return(result)}
  tryCatch({
    ctx<-new.env(parent=globalenv())
    for(f in c("config","snodas","audit-snodas","snodas-inventory","snodas-bootstrap","snodas-quality-pilot",
      "snodas-season-audit","snodas-baseline","snodas-analysis-qc","snodas-grid","snodas-climatology-pilot",
      "snodas-climatology-window-pilot","snodas-daily-climatology","snodas-map-pilot","snodas-seasonal-anomaly",
      "snodas-daily-comparison-pilot")) sys.source(file.path(root,"R",paste0(f,".R")),ctx)
    processed<-normalizePath(file.path(root,"data/processed"),winslash="/",mustWork=TRUE)
    original_manifest_reader<-ctx$read_snodas_manifest
    ctx$read_snodas_manifest<-function(...) {
      x<-original_manifest_reader(...)
      if(nrow(x)) {
        relative<-!grepl("^([A-Za-z]:|[/\\\\])",x$path)
        x$path[relative]<-file.path(root,x$path[relative])
        x$path<-normalizePath(x$path,winslash="/",mustWork=FALSE)
      }
      x
    }
    manifest<-read.csv(file.path(processed,"snodas/manifest.csv"),stringsAsFactors=FALSE)
    candidates<-sort(unique(manifest$date[manifest$date<=as.character(date)&manifest$date>=as.character(date-s$maximum_age_days)]),decreasing=TRUE)
    pair<-NULL
    verified_pair<-function(stamp) {
      rows<-manifest[manifest$date==as.character(stamp)&manifest$variable %in% c("swe","depth"),,drop=FALSE]
      if(nrow(rows)!=2L||!setequal(rows$variable,c("swe","depth"))||anyNA(rows$md5)||any(rows$units!="inch"))return(FALSE)
      files<-vapply(rows$variable,function(v)ctx$snodas_processed_path(as.Date(stamp),v,processed),character(1))
      all(file.exists(files))&&identical(unname(tools::md5sum(files)),rows$md5)
    }
    endpoint<-NULL;reference_paths<-NULL
    for(stamp in candidates) {
      if(!verified_pair(stamp))next
      reference_paths<-ctx$snodas_climatology_day_paths(ctx$snodas_climatology_output_root(processed_dir=processed),format(as.Date(stamp),"%m-%d"))
      spec<-ctx$snodas_climatology_spec(format(as.Date(stamp),"%m-%d"),2005:2025,0.1,3L,15L)
      if(ctx$snodas_climatology_day_complete(reference_paths,spec)){endpoint<-as.Date(stamp);break}
    }
    if(is.null(endpoint))return(result)
    has_previous<-verified_pair(endpoint-7L)
    paths<-c(ctx$snodas_processed_path(endpoint,"swe",processed),ctx$snodas_processed_path(endpoint,"depth",processed),unname(reference_paths))
    if(has_previous)paths<-c(paths,ctx$snodas_processed_path(endpoint-7L,"swe",processed),ctx$snodas_processed_path(endpoint-7L,"depth",processed))
    signature<-digest::digest(list(version=2L,date=date,endpoint=endpoint,config=config,paths=paths,
      md5=unname(tools::md5sum(paths)),code=unname(tools::md5sum(file.path(root,"R",c("conditions-synopsis-snow.R","snodas-analysis-qc.R","snodas-grid.R")))),
      maps=as.character(utils::packageVersion("maps")),terra=as.character(utils::packageVersion("terra"))))
    cache_path<-file.path(output_dir,"snow-evidence-cache.rds")
    cache<-if(file.exists(cache_path)) tryCatch(readRDS(cache_path),error=function(e)NULL) else NULL
    if(identical(cache$signature,signature)) {cache$result$cache_reused<-TRUE;return(cache$result)}
    pair<-ctx$load_snodas_swe_map_pilot_inputs(endpoint,processed_dir=processed)
    previous<-if(has_previous)ctx$snodas_read_comparison_endpoint(endpoint-7L,pair$observed,processed) else NULL
    weights<-synopsis_area_weights(pair$observed); rows<-list()
    for(region in names(weights)) {
      stats<-synopsis_snow_stats(terra::values(pair$observed,mat=FALSE),terra::values(pair$median_swe,mat=FALSE),
        terra::values(pair$sample_years,mat=FALSE),if(is.null(previous))NULL else terra::values(previous,mat=FALSE),weights[[region]],config)
      for(kind in names(stats)) {
        z<-stats[[kind]]
        if(is.null(z$values)) next
        for(metric in names(z$values)) rows[[length(rows)+1L]]<-data.frame(
          fact_id=paste("snow",region,kind,metric,sep=":"),product=paste0("snow_",kind),region=region,metric=metric,
          value=unname(z$values[[metric]]),units=if(grepl("percent$",metric))"percent of eligible snow area" else "inches SWE",
          period_start=as.character(if(kind=="change")endpoint-7L else endpoint),period_end=as.character(endpoint),
          reference=if(kind=="storage")"WY2005–WY2025 centered five-day date-specific median; at least 18 reference years" else "Exact seven-day endpoints; net SWE change, not snowfall or melt",
          denominator=if(kind=="storage")sprintf("AZ/NM cells with median SWE >=%g inch and >=%d reference years",s$minimum_median_inches,s$minimum_reference_years) else
            sprintf("AZ/NM cells normally snowy or with >=%g inch SWE at either endpoint",s$snow_threshold_inches),
          eligible_area_km2=z$area_km2,coverage=z$coverage,status=z$status,
          link=if(kind=="storage")"pages/snow-conditions.html?tab=percent" else "pages/snow-conditions.html?tab=change",stringsAsFactors=FALSE)
      }
    }
    result$status<-"CHECKED";result$date<-as.character(endpoint)
    result$facts<-if(length(rows))do.call(rbind,rows) else data.frame()
    result$note<-"Snow date is independent of PRISM; ratios use normally snowy terrain, with missing cells withheld."
    result$signature<-signature; result$source_paths<-paths;result$source_md5<-unname(tools::md5sum(paths))
    saveRDS(list(signature=signature,result=result),cache_path);result
  },error=function(e) {result$note<-conditionMessage(e);result})
}

synopsis_snow_blocks <- function(evidence) {
  packet<-evidence$snow_context
  if(is.null(packet)||!isTRUE(packet$active)||!is.data.frame(packet$facts)||!nrow(packet$facts))return(list())
  s<-synopsis_snow_settings(evidence$configuration);result<-list()
  facts<-packet$facts[packet$facts$status=="AVAILABLE_CACHED" & packet$facts$region=="AZNM",,drop=FALSE]
  age<-as.integer(as.Date(evidence$snapshot_date)-as.Date(facts$period_end))
  facts<-facts[which(age>=0 & age<=s$maximum_age_days & facts$coverage>=evidence$configuration$minimum_area_coverage & facts$eligible_area_km2>=s$minimum_area_km2),,drop=FALSE]
  getrow<-function(metric)facts[facts$metric==metric,,drop=FALSE]
  add<-function(kind,text,rows,section,tone) {
    result[[length(result)+1L]]<<-list(section=section,text=text,kind=paste0("snow_",kind),
      fact_ids=rows$fact_id,links=unique(rows$link),emphasis=list(list(text=regmatches(text,regexpr("[0-9]+%",text)),tone=tone,strong=FALSE)))
  }
  low<-getrow("area_below_median_percent");high<-getrow("area_above_median_percent")
  if(nrow(low)==1L&&nrow(high)==1L) {
    deficit<-low$value>=high$value;x<-if(deficit)low else high
    if(x$value>=s$minimum_signal_percent || evidence$season$id=="winter") {
      rows<-facts[facts$product=="snow_storage",,drop=FALSE]
      text<-sprintf("On %s, %.0f%% of normally snowy terrain in Arizona and New Mexico had SWE %s %g%% of its date-specific median (WY2005–WY2025). The comparison is limited to areas with typical SWE of at least %g inch and %d reference years.",
        synopsis_date_text(x$period_end),x$value,if(deficit)"below" else "above",if(deficit)s$low_percent_median else s$high_percent_median,
        s$minimum_median_inches,s$minimum_reference_years)
      if(low$value<s$minimum_signal_percent&&high$value<s$minimum_signal_percent)
        text<-sprintf("On %s, %.0f%% of normally snowy AZ/NM terrain had SWE between %g%% and %g%% of its date-specific median (WY2005–WY2025). The eligible area requires typical SWE of at least %g inch and %d reference years.",
          synopsis_date_text(x$period_end),100-low$value-high$value,s$low_percent_median,s$high_percent_median,s$minimum_median_inches,s$minimum_reference_years)
      if(low$value>=s$minimum_signal_percent&&high$value>=s$minimum_signal_percent)
        text<-paste0(text,sprintf(" Snow storage was spatially mixed: %.0f%% of this eligible area was below %g%% and %.0f%% above %g%% of median.",low$value,s$low_percent_median,high$value,s$high_percent_median))
      add("storage",text,rows,"Water year so far",if(deficit)"dry" else "wet")
    }
  }
  gain<-getrow("area_gain_percent");loss<-getrow("area_loss_percent")
  if(nrow(gain)==1L&&nrow(loss)==1L) {
    gaining<-gain$value>=loss$value;x<-if(gaining)gain else loss
    if(x$value>=s$minimum_signal_percent) {
      rows<-facts[facts$product=="snow_change",,drop=FALSE]
      text<-sprintf("During %s, modeled SWE %s by at least %g inch across %.0f%% of AZ/NM terrain with current, prior or typical snow. This is net snowpack-water change, not snowfall or a measure of melt alone.",
        synopsis_date_range(x$period_start,x$period_end),if(gaining)"increased" else "decreased",s$change_threshold_inches,x$value)
      if(gain$value>=s$minimum_signal_percent&&loss$value>=s$minimum_signal_percent)
        text<-paste0(text,sprintf(" Gains and losses were both widespread: %.0f%% gained and %.0f%% lost at least %g inch.",gain$value,loss$value,s$change_threshold_inches))
      add("change",text,rows,"Past 7 days",if(gaining)"wet" else "dry")
    }
  }
  result
}
