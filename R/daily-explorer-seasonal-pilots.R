# Small seasonal comparisons; shared July machinery, separate diagnostic releases.
seasonal_explorer_windows <- function() {
  base<-"data/diagnostics/daily-explorer-seasonal-pilots"
  list(winter=list(id="winter",title="Winter February 1-7 2025",start="2025-02-01",end="2025-02-07",root=file.path(base,"winter")),
    quiet=list(id="quiet",title="Late June comparison June 24-30 2025",start="2025-06-24",end="2025-06-30",root=file.path(base,"quiet")))
}
seasonal_explorer_load <- function() {
  source("R/daily-explorer-july-pilot.R",local=FALSE)
  july_pilot_load()
}
seasonal_explorer_seed <- function(window) {
  context<-july_pilot_context(window)
  # Reuse only verified markers referencing the existing shared GRIB files.
  # No source fields or accepted July viewer assets are copied or modified.
  donors<-c(july_pilot_root(),vapply(seasonal_explorer_windows(),function(w)w$root,character(1)))
  seeded<-0L
  for(date in context$support) {
    if(!is.null(july_pilot_input(context$root,date)))next
    for(donor in donors) {
      x<-july_pilot_input(donor,date)
      if(is.null(x))next
      directory<-file.path(context$root,"inputs",date)
      dir.create(directory,recursive=TRUE,showWarnings=FALSE)
      saveRDS(x,file.path(directory,"complete.rds"))
      stopifnot(!is.null(july_pilot_input(context$root,date)))
      seeded<-seeded+1L;break
    }
  }
  seeded
}
prepare_seasonal_explorer <- function(download=FALSE,max_new_dates=10L) {
  # Validate limits before seeding anything, even if all dates are cached.
  if(length(download)!=1L||!is.logical(download)||is.na(download)||
    length(max_new_dates)!=1L||is.na(max_new_dates)||!max_new_dates%in%1:10)stop("Bound preparation to 1-10 dates per window.")
  rows<-lapply(seasonal_explorer_windows(),function(w) {
    seeded<-seasonal_explorer_seed(w)
    result<-prepare_daily_explorer_july(download,max_new_dates,window=w)
    data.frame(window=w$id,seeded=seeded,result)
  })
  result<-do.call(rbind,rows)
  write.csv(result,"data/diagnostics/daily-explorer-seasonal-pilots/input-summary.csv",row.names=FALSE)
  print(result,row.names=FALSE);invisible(result)
}
build_seasonal_explorer <- function(download_events=FALSE,max_end_dates=7L) {
  if(length(download_events)!=1L||!is.logical(download_events)||is.na(download_events)||
    length(max_end_dates)!=1L||is.na(max_end_dates)||!max_end_dates%in%1:7)stop("Bound rendering to 1-7 endpoints per window.")
  windows<-seasonal_explorer_windows()
  # Check both plans before beginning any expensive rendering.
  for(w in windows) {
    context<-july_pilot_context(w)
    if(any(vapply(context$support,function(d)is.null(july_pilot_input(context$root,d)),logical(1))))
      stop("Finish input preparation for both windows first: ",w$id)
  }
  rows<-lapply(windows,function(w) {
    x<-build_daily_explorer_july(download_events,max_end_dates,window=w)
    if(identical(x$status,"READY"))validate_daily_explorer_july(window=w)
    data.frame(window=w$id,status=x$status)
  })
  result<-do.call(rbind,rows)
  write.csv(result,"data/diagnostics/daily-explorer-seasonal-pilots/build-status.csv",row.names=FALSE)
  print(result,row.names=FALSE);invisible(result)
}
check_seasonal_explorer <- function() {
  windows<-seasonal_explorer_windows()
  result<-do.call(rbind,lapply(windows,function(w) {
    x<-validate_daily_explorer_july(window=w)
    root<-july_pilot_context(w)$root
    progress<-read.csv(file.path(root,"weather-progress.csv"))
    stopifnot(nrow(progress)==21L,!any(progress$status=="DEFERRED"))
    p<-jsonlite::read_json(file.path(root,"viewer/daily-data.json"))
    # Counts describe reports/events, never unique storms or impact severity.
    # Zero is valid only after the complete report/hazard coverage checks above.
    weather<-data.frame(window=w$id,start=w$start,end=w$end,
      wind_eligible_min=min(progress$wind_eligible_cells),wind_eligible_max=max(progress$wind_eligible_cells))
    write.csv(weather,file.path(root,"review-coverage.csv"),row.names=FALSE)
    metric<-function(variable,statistic)vapply(p$days,function(d) {
      value<-d$regions$AZNM[[variable]][[statistic]]
      if(is.null(value))NA_real_ else as.numeric(value)
    },numeric(1))
    data.frame(window=w$id,x,regional_precip_inches=sum(metric("pcpn","mean")),
      mean_temperature_departure_f=mean(metric("tmean","departure")))
  }))
  write.csv(result,"data/diagnostics/daily-explorer-seasonal-pilots/validation-summary.csv",row.names=FALSE)
  print(result,row.names=FALSE);invisible(result)
}
