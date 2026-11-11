# Isolated full Station Conditions preview. Cached observations only.
source("R/config.R")
source("R/acis-station-current-prototype.R")
source("R/acis-station-temperature-normals.R")
source("R/acis-station-temperature-records.R")
source("R/acis-station-precipitation-records.R")

build_station_temperature_normals_preview <- function(
    source_dir="data/diagnostics/station-seasonal-integration",
    output_dir="data/diagnostics/station-temperature-normals-preview",
    cache_dir="data/processed/acis-stations/reference-network/daily",
    reference_cache_dir="data/diagnostics/station-temperature-normals-cache",
    min_years=20L,smoothing_days=15L,refresh_assets_only=FALSE) {
  started<-proc.time()[["elapsed"]]
  diagnostics<-normalizePath("data/diagnostics",winslash="/",mustWork=TRUE)
  source_dir<-normalizePath(source_dir,winslash="/",mustWork=TRUE)
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  output_dir<-normalizePath(output_dir,winslash="/",mustWork=TRUE)
  stopifnot(startsWith(source_dir,paste0(diagnostics,"/")),
    startsWith(output_dir,paste0(diagnostics,"/")),source_dir!=output_dir)
  needed<-c("index.html","explorer.js","explorer.css","station-explorer-data.csv",
    "station-details","seasonal/index.html","seasonal/stations.json")
  if(!all(file.exists(file.path(source_dir,needed))))
    stop("The combined seasonal station preview is required first; run scripts/build-station-seasonal-integration.R.")
  rows<-read.csv(file.path(source_dir,"station-explorer-data.csv"))
  snapshot<-unique(rows$as_of)
  stopifnot(length(snapshot)==1L, !is.na(as.Date(snapshot)))
  seasonal<-jsonlite::read_json(file.path(source_dir,"seasonal/stations.json"))
  if(!identical(seasonal$as_of,snapshot))stop("Seasonal station preview dates do not match.")
  # Reuse the seasonal files through the same localhost server instead of copying
  # thousands of historical files into another preview directory.
  files<-list.files(source_dir,full.names=TRUE)
  files<-files[!dir.exists(files)]
  if(!all(file.copy(files,output_dir,overwrite=TRUE)))stop("Could not copy station page assets.")
  js<-paste(readLines(file.path(source_dir,"explorer.js"),encoding="UTF-8",warn=FALSE),collapse="\n")
  replace_once<-function(old,new) {
    if(length(gregexpr(old,js,fixed=TRUE)[[1]])!=1L || !grepl(old,js,fixed=TRUE))
      stop("Station chart integration point changed: ",old)
    js<<-sub(old,new,js,fixed=TRUE)
  }
  replace_once("const usable = days.flatMap(day => [day.maxt, day.mint])",
    "const usable = days.flatMap(day => [day.maxt, day.mint, day.normal_maxt, day.normal_mint, day.record_high, day.record_low])")
  replace_once('function temperatureChart(days, station) {',
    'function temperatureChart(days, station) { window.SWCStationTemperatureNormals.bind(days,station);')
  replace_once('function precipitationChart(days, station) {',
    'function precipitationChart(days, station) { window.SWCStationTemperatureNormals.bind(days,station);')
  replace_once('`fill="#327eaa"${wettest ?',
    '`${window.SWCStationTemperatureNormals.precipitationBarStyle(day)}${wettest ?')
  replace_once('return chartFrame(threeDayBand + bars + empty + hits,',
    'return chartFrame(window.SWCStationTemperatureNormals.precipitationDefinitions() + threeDayBand + bars + empty + hits,')
  replace_once('precipitationChart(days, station) + chartControls()',
    'window.SWCStationTemperatureNormals.precipitationLegend() + precipitationChart(days, station) + chartControls()')
  replace_once('const hits = days.map((day, i) => chartHit(left + i * step, step,\n      precipitationDayText(day, station), i === 0)).join("");',
    'const hits = days.map((day,i) => window.SWCStationTemperatureNormals.precipitationHit(day,left+i*step,step,i===0)).join("");')
  replace_once('temperatureDayText(day, station), i === 0)',
    'window.SWCStationTemperatureNormals.tooltip(day), i === 0)')
  replace_once('const hits = days.map((day, i) => chartHit(left + i * step, step,\n      window.SWCStationTemperatureNormals.tooltip(day), i === 0)).join("");',
    'const hits = days.map((day,i) => window.SWCStationTemperatureNormals.hit(day,left+i*step,step,i===0)).join("");')
  replace_once('if (readout) readout.textContent = hit.dataset.chartReadout;',
    'if (readout && !window.SWCStationTemperatureNormals.renderReadout(hit,readout)) readout.textContent = hit.dataset.chartReadout;')
  replace_once('<p class="chart-readout" aria-live="polite">Hover, focus, or tap a day for its high and low.</p>',
    '<div class="chart-readout temperature-readout" aria-live="polite">Hover, focus, or tap a day to compare temperatures.</div>')
  replace_once('<p class="chart-readout" aria-live="polite">Hover, focus, or tap a day for its precipitation report.</p>',
    '<div class="chart-readout temperature-readout precipitation-readout" aria-live="polite">Hover, focus, or tap a day to compare precipitation.</div>')
  replace_once('return chartFrame(line("maxt", "#b35b37")',
    'return chartFrame(window.SWCStationTemperatureNormals.paths(days,x,y) + line("maxt", "#b35b37")')
  replace_once('marks + empty + hits,',
    'window.SWCStationTemperatureNormals.markers(days,x,y) + empty + hits,')
  replace_once('temperatureChart(days, station) + chartControls()',
    'window.SWCStationTemperatureNormals.legend(days,detail.temperature_reference,detail.temperature_records) + temperatureChart(days, station) + chartControls()')
  relative<-substring(source_dir,nchar(diagnostics)+2L)
  replace_once('`<section class="station-cumulative"><h3>Seasonal precipitation and historical comparisons</h3>` +',
    'selectedExtremeSummary(station) + `<section class="station-cumulative"><h3>Seasonal precipitation and historical comparisons</h3>` +')
  replace_once('selectedExtremeSummary(station) +\n      `<div class="detail-lower">',
    '`<div class="detail-lower">')
  standing_pattern<-'(?s)<section><h3>Historical standing</h3>.*?</section>'
  standing_match<-regexpr(standing_pattern,js,perl=TRUE)
  if(standing_match[[1]]<0)stop("Historical standing integration point changed.")
  standing<-regmatches(js,standing_match)
  replace_once(standing,"")
  replace_once('`<h3>Frequency and persistence</h3>',
    paste0('`',standing,'<h3>Frequency and persistence</h3>'))
  # A small local wrapper reuses the original seasonal data and scripts.
  seasonal_dir<-file.path(output_dir,"seasonal")
  dir.create(seasonal_dir,showWarnings=FALSE)
  seasonal_html<-paste(readLines(file.path(source_dir,"seasonal/index.html"),warn=FALSE,encoding="UTF-8"),collapse="\n")
  seasonal_html<-sub('<head>','<head><base href="../../SOURCE/seasonal/">',seasonal_html,fixed=TRUE)
  seasonal_html<-sub('SOURCE',relative,seasonal_html,fixed=TRUE)
  seasonal_html<-sub('<section id="station-card"',
    '<details class="card station-history-toggle"><summary>Seasonal cumulative precipitation</summary><section id="station-card"',seasonal_html,fixed=TRUE)
  seasonal_html<-sub('<section id="annual-history"',
    '</details><details class="card station-history-toggle"><summary>Historical seasonal and water-year totals</summary><section id="annual-history"',seasonal_html,fixed=TRUE)
  seasonal_html<-sub('<details class="card methods">','</details><details class="card methods">',seasonal_html,fixed=TRUE)
  seasonal_html<-sub('</head>','<style>.station-history-toggle>summary{cursor:pointer;font-weight:600;padding:.4rem}.station-history-toggle>section.card{border:0;box-shadow:none;margin:0}</style></head>',seasonal_html,fixed=TRUE)
  writeLines(seasonal_html,file.path(seasonal_dir,"index.html"),useBytes=TRUE)
  writeLines(js,file.path(output_dir,"explorer.js"),useBytes=TRUE)
  html<-paste(readLines(file.path(output_dir,"index.html"),encoding="UTF-8",warn=FALSE),collapse="\n")
  html<-sub('<script src="explorer.js" defer></script>',
    '<script src="temperature-normals.js" defer></script><script src="explorer.js" defer></script>',html,fixed=TRUE)
  html<-sub('</head>','<link rel="stylesheet" href="temperature-normals.css"><meta name="swc-preview" content="station-temperature-normals"></head>',html,fixed=TRUE)
  normal_note<-paste0('<p><strong>Daily temperature normal lines:</strong> Project-calculated 1991-2020 calendar-day averages use paired, unflagged high/low observations, with at least ',min_years,
    ' valid years per calendar date. A centered ',smoothing_days,
    '-day smoother is applied only where every date in its cyclic calendar window has adequate support; the reported support is the minimum across that window, and eligible years can vary by date. February 29 interpolates adjacent reference days. Hover departures use this smoothed reference; the table retains its existing period-anomaly method. These are not official NOAA normals, and no missing observed temperatures are filled.</p>')
  html<-sub('</details>',paste0(normal_note,'</details>'),html,fixed=TRUE)
  record_note<-paste0('<p><strong>Daily temperature record lines:</strong> Dotted lines show the highest daily maximum and lowest daily minimum among earlier eligible years on that exact calendar date. Current observations and later years are excluded. References need 30 earlier observations, with the earliest qualifying report at least 30 calendar years before the plotted year; February 29 needs at least eight actual earlier leap-day reports with the same age requirement, never interpolated values. Missing, flagged and inverted daily temperatures are excluded. Hover identifies record values, all tied record years and the comparison sample. New/tied markers describe this eligible cached station or ThreadEx record, not certified official records; comparison ties allow 0.01 degree F for numerical precision.</p>')
  html<-sub('</details>',paste0(record_note,'</details>'),html,fixed=TRUE)
  precipitation_note<-'<p><strong>Daily precipitation record table:</strong> Observed totals are compared with earlier eligible reports on the exact calendar date, using the same 30-year count/age requirements as temperature records and actual leap-day reports only. Missing, flagged, accumulated and invalid reports are excluded. Trace reports are shown as trace and contribute zero to historical comparisons; zero or trace-only reference samples never create tied wettest-day labels. Hover records are within the eligible cached station or ThreadEx history, not certified official records. The wettest day or three-day span within the selected period is a separate indicator.</p>'
  html<-sub('</details>',paste0(precipitation_note,'</details>'),html,fixed=TRUE)
  writeLines(html,file.path(output_dir,"index.html"),useBytes=TRUE)
  assets<-file.path("scripts/station-temperature-normals-assets",c("temperature-normals.js","temperature-normals.css"))
  if(!all(file.copy(assets,output_dir,overwrite=TRUE)))stop("Could not copy normal-line assets.")
  if(refresh_assets_only) {
    message("Station chart display refreshed; existing station reference data retained. No downloads or publication.")
    return(invisible(output_dir))
  }
  detail_dir<-file.path(output_dir,"station-details");dir.create(detail_dir,showWarnings=FALSE)
  uids<-unique(rows$uid);report<-vector("list",length(uids))
  message("Preparing temperature normal lines for ",length(uids)," stations; no downloads.")
  for(i in seq_along(uids)) {
    uid<-uids[i]
    path<-acis_station_daily_cache_path(uid,cache_dir)
    cache<-acis_station_read_daily_cache(path,uid)
    reference<-read_or_build_acis_temperature_normals(cache,uid,reference_cache_dir,min_years,smoothing_days)
    detail<-jsonlite::read_json(file.path(source_dir,"station-details",paste0(uid,".json")),simplifyVector=TRUE)
    stopifnot(detail$uid==uid,detail$as_of==snapshot)
    detail<-acis_attach_temperature_normals(detail,reference$reference)
    detail<-acis_attach_temperature_records(detail,cache)
    detail<-acis_attach_precipitation_records(detail,cache)
    writeLines(as.character(jsonlite::toJSON(detail,auto_unbox=TRUE,dataframe="rows",na="null",null="null",digits=7)),
      file.path(detail_dir,paste0(uid,".json")),useBytes=TRUE)
    valid<-is.finite(reference$reference$daily$normal_maxt)&is.finite(reference$reference$daily$normal_mint)
    report[[i]]<-data.frame(uid,name=detail$name,reused=reference$reused,
      supported_calendar_days=sum(valid),minimum_supported_years=if(any(valid)) min(reference$reference$daily$normal_years[valid]) else NA_integer_,
      record_high_days=sum(is.finite(detail$daily$record_high)),record_low_days=sum(is.finite(detail$daily$record_low)))
    if(i%%10L==0L || i==length(uids))message("Temperature normals: ",i,"/",length(uids))
  }
  report<-do.call(rbind,report)
  write.csv(report,file.path(output_dir,"normal-support.csv"),row.names=FALSE)
  message(sprintf("Temperature normals preview ready: %d stations; %d reference caches reused; %.1fs. Observations through %s. No publication.",
    length(uids),sum(report$reused),proc.time()[["elapsed"]]-started,snapshot))
  invisible(report)
}

station_temperature_normals_preview <- build_station_temperature_normals_preview()
