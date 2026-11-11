# Earlier-year calendar-date records for the daily charts; never interpolate records.
acis_attach_temperature_records <- function(detail,cache,min_years=30L,
    leap_min_years=8L,min_span_years=30L,tolerance=.01) {
  stopifnot(is.data.frame(detail$daily),length(min_years)==1L,min_years>=1,
    length(leap_min_years)==1L,leap_min_years>=1,length(min_span_years)==1L,
    min_span_years>=0,length(tolerance)==1L,is.finite(tolerance),tolerance>=0)
  if(!is.null(cache)) stopifnot(as.integer(cache$uid)==as.integer(detail$uid))
  dates<-as.Date(detail$daily$date)
  stopifnot(!anyNA(dates),!anyDuplicated(dates))
  source<-if(is.null(cache)) data.frame() else cache$daily
  groups<-list(maxt=list(),mint=list())
  if(nrow(source)) {
    needed<-c("date","variable","numeric_value","observed","flag")
    stopifnot(all(needed %in% names(source)),inherits(source$date,"Date"))
    source<-source[source$variable %in% c("maxt","mint") &
      source$date<=min(as.Date(detail$as_of),as.Date(cache$as_of)),,drop=FALSE]
    if(anyDuplicated(source[c("date","variable")]))stop("Duplicate temperature record dates.")
    valid<-!is.na(source$observed)&source$observed&is.finite(source$numeric_value)&
      abs(source$numeric_value)<=150 & (is.na(source$flag)|source$flag=="")
    valid[is.na(valid)]<-FALSE
    high<-source[source$variable=="maxt" & valid,,drop=FALSE]
    low<-source[source$variable=="mint" & valid,,drop=FALSE]
    matched<-match(high$date,low$date)
    inverted<-which(!is.na(matched) & high$numeric_value<low$numeric_value[matched])
    bad<-high$date[inverted]
    high<-high[!high$date %in% bad,,drop=FALSE];low<-low[!low$date %in% bad,,drop=FALSE]
    groups<-list(maxt=split(high,format(high$date,"%m-%d")),mint=split(low,format(low$date,"%m-%d")))
  }
  for(kind in c("high","low")) {
    variable<-if(kind=="high") "maxt" else "mint"
    prefix<-paste0("record_",kind)
    values<-rep(NA_real_,length(dates));years<-rep("",length(dates))
    counts<-integer(length(dates));first<-last<-rep(NA_integer_,length(dates))
    status<-rep("INSUFFICIENT_HISTORY",length(dates))
    for(i in seq_along(dates)) {
      md<-format(dates[i],"%m-%d")
      sample<-groups[[variable]][[md]]
      if(is.null(sample)||!nrow(sample))next
      sample<-sample[sample$date<dates[i],,drop=FALSE]
      counts[i]<-nrow(sample)
      if(!counts[i])next
      sample_years<-as.integer(format(sample$date,"%Y"))
      first[i]<-min(sample_years);last[i]<-max(sample_years)
      required<-if(md=="02-29") leap_min_years else min_years
      if(counts[i]<required || as.integer(format(dates[i],"%Y"))-first[i]<min_span_years)next
      extreme<-if(kind=="high") max(sample$numeric_value) else min(sample$numeric_value)
      values[i]<-extreme
      years[i]<-paste(sort(sample_years[abs(sample$numeric_value-extreme)<=tolerance]),collapse=",")
      observation<-detail$daily[[variable]][i]
      usable<-is.numeric(observation)&&length(observation)==1L&&is.finite(observation)
      status[i]<-if(!usable) "MISSING_OBSERVATION" else if(abs(observation-extreme)<=tolerance)
        paste0("TIED_",toupper(kind)) else if(if(kind=="high") observation>extreme+tolerance else observation<extreme-tolerance)
        paste0("NEW_",toupper(kind)) else "WITHIN_RANGE"
    }
    detail$daily[[prefix]]<-values
    detail$daily[[paste0(prefix,"_years")]]<-years
    detail$daily[[paste0(prefix,"_n")]]<-counts
    detail$daily[[paste0(prefix,"_first_year")]]<-first
    detail$daily[[paste0(prefix,"_last_year")]]<-last
    detail$daily[[paste0(prefix,"_status")]]<-status
  }
  detail$temperature_records<-list(method="Earlier eligible years on the exact calendar date; each observation excluded from its own reference.",
    minimum_years=as.integer(min_years),leap_minimum_years=as.integer(leap_min_years),
    minimum_calendar_span=as.integer(min_span_years),tie_tolerance_f=tolerance,
    leap_day_method="Actual earlier February 29 observations only; no interpolation.",
    provenance="Records within this cached station or ThreadEx series, not certified official station records.")
  detail
}
