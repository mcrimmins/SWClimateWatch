# Isolated PRISM-only archive pilot. Live staging and publication are untouched.
daily_archive_pilot_root <- function(directory) {
  source("R/storm-reports-pilot.R",local=TRUE)
  path<-storm_reports_output_path(directory,"site/daily-explorer")
  dir.create(path,recursive=TRUE,showWarnings=FALSE)
  path
}

daily_archive_pilot_assets <- function(directory) {
  html<-paste(readLines("scripts/daily-explorer-assets/index.html",warn=FALSE),collapse="\n")
  html<-sub('<script src="explorer.js" defer>', '<script src="archive-model.js" defer></script><script src="explorer.js" defer>',html,fixed=TRUE)
  html<-sub('<label>Season<select', '<label>Month<select id="archive-month"></select></label><label hidden>Season<select',html,fixed=TRUE)
  html<-sub('<p id="error"', '<p id="archive-status" role="status" class="muted">Loading sample archive…</p><p id="error"',html,fixed=TRUE)
  html<-sub('<h1>Daily Explorer</h1>','<h1>Daily Explorer archive pilot</h1>',html,fixed=TRUE)
  html<-gsub("selected season","selected month",html,fixed=TRUE)
  writeLines(html,file.path(directory,"index.html"),useBytes=TRUE)
  js<-paste(readLines("scripts/daily-explorer-assets/explorer.js",warn=FALSE),collapse="\n")
  js<-sub('const response = await fetch("daily-data.json", {cache:"no-store"});\n    if (!response.ok) throw new Error(`Data request failed (${response.status}).`);\n    const payload = await response.json();',
    'const payload = await archiveInitialPayload();',js,fixed=TRUE)
  js<-sub('const available = days.filter(day => day.water_year === year);',
    'const available = days.filter(day => day.water_year === year && day.date.startsWith($("archive-month").value));',js,fixed=TRUE)
  js<-sub('function selectDate(date) {', 'function selectDate(date) {\n  if (archiveCatalog && byDate.has(date) && date.slice(0,7) !== $("archive-month").value) {archiveNavigate(date); return;}',js,fixed=TRUE)
  js<-sub('function selectLatestDate() {', 'function selectLatestDate() {\n  if (archiveCatalog) {archiveNavigate(archiveCatalog.latest); return;}',js,fixed=TRUE)
  js<-sub('selectedDate === days.at(-1).date;', 'selectedDate === (archiveCatalog ? archiveCatalog.latest : days.at(-1).date);',js,fixed=TRUE)
  js<-sub('const years = [...new Set(days.map(day => day.water_year))].sort((a,b) => b-a);',
    'const years = [...new Set(archiveCatalog.months.map(m => m.water_year))].sort((a,b) => b-a);',js,fixed=TRUE)
  js<-sub('String(years[0])','String(archiveYear)',js,fixed=TRUE)
  js<-sub('refreshMetricOptions(); selectLatestDate();','refreshMetricOptions(); selectedDate = archiveDate; render(); archiveBind();',js,fixed=TRUE)
  js<-sub('["year","season","region","view","metric","ranking"]','["season","region","view","metric","ranking"]',js,fixed=TRUE)
  js<-sub('renderTimeline(); renderMap(); renderComparison(); renderDiscussions(); renderNotable(); renderCirculation();',
    'renderTimeline(); renderMap(); renderComparison(); renderDiscussions(); renderNotable(); renderCirculation(); archiveUpdateUrl();',js,fixed=TRUE)
  loader<-paste(readLines("scripts/daily-explorer-archive-assets/archive-loader.js",warn=FALSE),collapse="\n")
  js<-sub('\ninitialize();',paste0('\n',loader,'\ninitialize();'),js,fixed=TRUE)
  if(grepl('fetch("daily-data.json"',js,fixed=TRUE)||!grepl('async function archiveInitialPayload',js,fixed=TRUE))stop("Archive asset adaptation failed.")
  writeLines(js,file.path(directory,"explorer.js"),useBytes=TRUE)
  file.copy("scripts/daily-explorer-assets/explorer.css",file.path(directory,"explorer.css"),overwrite=TRUE)
  file.copy("scripts/daily-explorer-archive-assets/archive-model.js",file.path(directory,"archive-model.js"),overwrite=TRUE)
  source("R/site-cache.R",local=TRUE);swc_cache_version_app(directory)
}

build_daily_explorer_archive_pilot <- function(output_dir="data/diagnostics/daily-explorer-archive-pilot",
    manifest=read_prism_manifest(prism_processed_manifest_path())) {
  output_dir<-daily_archive_pilot_root(output_dir)
  # Keep completed releases separate from paths owned/pruned by the current updater.
  latest<-daily_explorer_site_window(manifest)$end_date
  samples<-sort(unique(c(as.character(seq(as.Date("2025-07-01"),as.Date("2025-07-07"),by="day")),
    "2025-09-30","2025-10-01","2025-10-02",as.character(seq(latest-1,latest,by="day")))))
  months<-split(samples,substr(samples,1,7));entries<-list();builds<-list()
  current_year<-daily_explorer_water_year(latest)
  for(month in names(months)) {
    dates<-months[[month]];year<-daily_explorer_water_year(dates[1]);historical<-year<current_year
    relative<-if(historical)paste0("archive/WY",year)else "current"
    work<-file.path(output_dir,"work",month)
    build<-build_daily_explorer(water_years=year,start_date=min(dates),end_date=max(dates),
      manifest=manifest,output_dir=work,publication_mode=FALSE)
    payload<-jsonlite::read_json(file.path(work,"daily-data.json"))
    payload$days<-Filter(function(d)d$date%in%dates,payload$days)
    if(length(payload$days)!=length(dates)||any(lengths(lapply(payload$days,`[[`,"images"))!=7L))stop("Pilot requires all seven PRISM maps at each sample date.")
    for(i in seq_along(payload$days))for(key in names(payload$days[[i]]$images)) {
      image<-payload$days[[i]]$images[[key]]
      dest<-file.path(output_dir,relative,image);dir.create(dirname(dest),recursive=TRUE,showWarnings=FALSE)
      if(!file.exists(dest)||!identical(unname(tools::md5sum(file.path(work,image))),unname(tools::md5sum(dest))))
        if(!file.copy(file.path(work,image),dest,overwrite=TRUE))stop("Cannot stage archive image.")
      payload$days[[i]]$images[[key]]<-paste0(relative,"/",image)
    }
    path<-paste0(relative,"/months/",month,".json");dir.create(dirname(file.path(output_dir,path)),recursive=TRUE,showWarnings=FALSE)
    payload$latest_cached_date<-max(dates);payload$circulation_enabled<-FALSE
    payload$circulation_period_means_enabled<-FALSE;payload$archive_pilot<-TRUE
    payload$built_at<-NULL
    jsonlite::write_json(payload,file.path(output_dir,path),auto_unbox=TRUE,digits=NA,null="null")
    entries[[length(entries)+1L]]<-list(month=month,water_year=year,path=path,dates=unname(as.list(dates)),
      sample=TRUE,md5=unname(tools::md5sum(file.path(output_dir,path))))
    builds[[length(builds)+1L]]<-data.frame(month,days=length(dates),maps=length(dates)*7L,built=build$built,reused=build$reused)
  }
  catalog<-list(schema_version=1L,archive_pilot=TRUE,latest=as.character(latest),months=unname(entries))
  jsonlite::write_json(catalog,file.path(output_dir,"archive-catalog.json"),auto_unbox=TRUE,pretty=TRUE,null="null")
  daily_archive_pilot_assets(output_dir)
  summary<-do.call(rbind,builds);write.csv(summary,file.path(output_dir,"build-summary.csv"),row.names=FALSE)
  print(summary,row.names=FALSE);message("Unpublished PRISM sample archive: ",output_dir)
  invisible(summary)
}

validate_daily_explorer_archive_pilot <- function(directory="data/diagnostics/daily-explorer-archive-pilot") {
  source("R/site-cache.R",local=TRUE)
  catalog<-jsonlite::read_json(file.path(directory,"archive-catalog.json"))
  if(!identical(catalog$schema_version,1L)||!isTRUE(catalog$archive_pilot)||!is.null(names(catalog$months)))stop("Invalid pilot catalog.")
  all_dates<-images<-character()
  for(m in catalog$months) {
    expected<-if(startsWith(m$path,"archive/"))sprintf("archive/WY%d/months/%s.json",m$water_year,m$month)else paste0("current/months/",m$month,".json")
    if(!identical(expected,m$path)||!grepl("^[0-9]{4}-(0[1-9]|1[0-2])$",m$month))stop("Unsafe archive partition path.")
    path<-file.path(directory,m$path)
    if(!file.exists(path)||!identical(unname(tools::md5sum(path)),m$md5))stop("Month partition checksum mismatch.")
    p<-jsonlite::read_json(path);dates<-vapply(p$days,`[[`,character(1),"date")
    if(!identical(dates,unlist(m$dates,use.names=FALSE))||is.unsorted(dates,strictly=TRUE)||
      any(substr(dates,1,7)!=m$month)||any(daily_explorer_water_year(dates)!=m$water_year)||
      isTRUE(p$publication_mode)||!is.null(names(p$days)))stop("Invalid month dates or publication flags.")
    prefix<-sub("/months/.*$","",m$path)
    for(d in p$days) {
      if(length(d$images)!=7L||!identical(d$water_year,m$water_year))stop("Missing PRISM map or invalid year.")
      for(image in unlist(d$images))if(!startsWith(image,paste0(prefix,"/maps/",d$date,"-"))||
        grepl("[.][.]",image)||!grepl("^[A-Za-z0-9_./-]+[.]png$",image)||!file.exists(file.path(directory,image))||file.info(file.path(directory,image))$size<=0)stop("Missing or unsafe map image.")
      images<-c(images,unlist(d$images,use.names=FALSE))
    }
    all_dates<-c(all_dates,dates)
  }
  if(anyDuplicated(all_dates)||!identical(max(all_dates),catalog$latest))stop("Invalid archive latest date or duplicate date.")
  swc_cache_validate_app(directory)
  result<-data.frame(status="PASS",months=length(catalog$months),dates=length(all_dates),maps=length(images),bytes=sum(file.info(file.path(directory,images))$size))
  print(result,row.names=FALSE);invisible(result)
}
