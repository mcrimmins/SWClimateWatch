# Read-only publication audit: local metadata/files only, never downloads/maps.
audit_weather_publication <- function(source_dir=file.path("site","daily-explorer"),
    rendered_dir=NULL,archive_dir=file.path("data","processed","weather-circulation"),
    report_dir=file.path("data","diagnostics","weather-publication-status"),
    today=Sys.Date(),require_enabled=TRUE) {
  errors<-warnings<-character()
  read<-function(path) tryCatch({
    value<-jsonlite::read_json(path)
    if(!is.list(value)) stop("Expected a metadata object.")
    value
  },error=function(e) {
    errors<<-c(errors,paste("Cannot read",path,conditionMessage(e))); NULL
  })
  payload<-read(file.path(source_dir,"daily-data.json"))
  enabled<-isTRUE(payload$circulation_enabled)
  if(require_enabled && !enabled) errors<-c(errors,"Staged weather panel flag is missing or disabled.")
  dates<-tryCatch(vapply(payload$days,`[[`,character(1),"date"),error=function(e) character())
  parsed<-tryCatch(as.Date(dates),error=function(e) as.Date(NA_character_))
  if(!length(dates) || anyNA(parsed) || anyDuplicated(dates) || any(as.character(parsed)!=dates)) {
    errors<-c(errors,"Invalid or empty Explorer dates."); dates<-character()
  }
  eligible<-sort(dates[dates<as.character(as.Date(today))])
  if(!length(eligible)) errors<-c(errors,"Explorer has no completed dates.")
  expected<-if(length(eligible)) as.character(seq(as.Date(min(eligible)),as.Date(max(eligible)),by="day")) else character()
  manifest_path<-file.path(source_dir,"circulation-manifest.json")
  manifest<-if(file.exists(manifest_path)) read(manifest_path) else NULL
  if(enabled && is.null(manifest)) errors<-c(errors,"Enabled weather panel has no manifest.")
  if(!is.null(manifest) && (!identical(manifest$schema_version,1L) || !is.list(manifest$days)))
    errors<-c(errors,"Invalid weather manifest schema.")
  records<-if(is.list(manifest$days)) manifest$days else list()
  seen<-complete<-character(); files<-character()
  for(record in records) {
    if(!is.list(record)) {errors<-c(errors,"Invalid weather manifest record."); next}
    date<-record$date
    valid_date<-tryCatch(length(date)==1L && !is.na(as.Date(date)) &&
      identical(as.character(as.Date(date)),date),error=function(e) FALSE)
    if(!valid_date || date %in% seen || !identical(record$status,"available")) {
      errors<-c(errors,"Invalid or duplicate weather manifest record."); next
    }
    seen<-c(seen,date)
    if(!is.list(record$images)) {errors<-c(errors,paste("Missing image list:",date)); next}
    if(date>=as.character(as.Date(today))) errors<-c(errors,paste("Weather map is not a completed UTC date:",date))
    images_valid<-TRUE
    for(field in c("height500","jet250","moisture")) {
      relative<-paste0("circulation/maps/",date,"-",field,".png")
      if(!identical(record$images[[field]],relative)) {
        images_valid<-FALSE; errors<-c(errors,paste("Invalid image path:",date,field)); next
      }
      files<-c(files,relative)
      path<-file.path(source_dir,relative)
      if(!file.exists(path) || file.info(path)$size<=0) {
        images_valid<-FALSE
        errors<-c(errors,paste("Missing or empty staged image:",relative))
      }
    }
    if(images_valid) complete<-c(complete,date)
  }
  rendered_enabled<-NA
  if(!is.null(rendered_dir)) {
    rendered<-read(file.path(rendered_dir,"daily-data.json"))
    rendered_enabled<-isTRUE(rendered$circulation_enabled)
    if((require_enabled || enabled) && !rendered_enabled)
      errors<-c(errors,"Rendered weather panel flag is missing or disabled.")
    if(rendered_enabled && !enabled) errors<-c(errors,"Rendered weather activation differs from staging.")
    if(!identical(rendered$latest_cached_date,payload$latest_cached_date))
      errors<-c(errors,"Rendered Explorer latest date differs from staging.")
    if(enabled) {
      compare<-c("circulation-manifest.json",files)
      for(relative in compare) {
        source<-file.path(source_dir,relative); target<-file.path(rendered_dir,relative)
        if(!file.exists(target) || !file.exists(source) ||
            !identical(unname(tools::md5sum(source)),unname(tools::md5sum(target))))
          errors<-c(errors,paste("Rendered weather file missing or different:",relative))
      }
    }
  }
  details<-data.frame(date=expected,explorer_available=expected %in% eligible,
    weather_available=expected %in% complete,note=rep("",length(expected)),
    overlay_status_known=rep(FALSE,length(expected)),stringsAsFactors=FALSE)
  for(i in seq_len(nrow(details))) {
    marker<-file.path(archive_dir,"daily",details$date[i],"moisture-map-cache.rds")
    cached<-if(file.exists(marker)) tryCatch(readRDS(marker),error=function(e) NULL) else NULL
    image<-file.path(source_dir,paste0("circulation/maps/",details$date[i],"-moisture.png"))
    if(file.exists(image) && identical(cached$md5,unname(tools::md5sum(image))) &&
        is.character(cached$note) && length(cached$note)==1L && !is.na(cached$note)) {
      details$note[i]<-cached$note; details$overlay_status_known[i]<-TRUE
    }
  }
  available<-details$weather_available & details$explorer_available
  recent<-if(length(expected)) expected>=as.character(as.Date(max(expected))-29L) else logical()
  gap_count<-sum(!available)
  if(enabled && gap_count) warnings<-c(warnings,paste(gap_count,"Explorer dates lack weather maps."))
  latest<-if(length(complete)) max(complete) else NA_character_
  lag<-if(!is.na(latest)) as.integer(as.Date(today)-as.Date(latest)) else NA_integer_
  if(enabled && (is.na(lag) || lag>3L)) warnings<-c(warnings,"Weather maps have no latest date or are more than three days old.")
  if(enabled && length(seen)==0L) warnings<-c(warnings,"Weather panel is enabled but contains no dates.")
  summary<-data.frame(status=if(length(errors)) "FAIL" else if(!enabled && !require_enabled) "DISABLED" else if(length(warnings)) "WARN" else "PASS",
    staged_enabled=enabled,rendered_enabled=rendered_enabled,quarantined=FALSE,
    explorer_dates=length(expected),available_dates=sum(available),missing_dates=gap_count,
    recent_expected=sum(recent),recent_available=sum(available & recent),
    retained_dates=length(complete),retained_maps=3L*length(complete),latest=latest,lag_days=lag,
    recovered_dates=sum(available & grepl("recovered from GRIB",details$note,fixed=TRUE)),
    wind_withheld_dates=sum(available & grepl("wind overlay omitted",details$note,fixed=TRUE)),
    centers_withheld_dates=sum(available & grepl("H/L omitted",details$note,fixed=TRUE)),
    unknown_overlay_dates=sum(available & !details$overlay_status_known),
    note=paste(unique(c(errors,warnings)),collapse="; "),
    checked_utc=format(Sys.time(),"%Y-%m-%d %H:%M:%S UTC",tz="UTC"))
  if(!is.null(report_dir)) {
    dir.create(report_dir,recursive=TRUE,showWarnings=FALSE)
    utils::write.csv(summary,file.path(report_dir,"summary.csv"),row.names=FALSE)
    utils::write.csv(details,file.path(report_dir,"dates.csv"),row.names=FALSE)
  }
  invisible(list(summary=summary,dates=details))
}
