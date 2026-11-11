# Calendar-date daily precipitation maxima from earlier eligible station years.
acis_attach_precipitation_records <- function(detail,cache,min_years=30L,
    leap_min_years=8L,min_span_years=30L,tolerance=.0001) {
  stopifnot(is.data.frame(detail$daily),length(min_years)==1L,min_years>=1,
    length(leap_min_years)==1L,leap_min_years>=1,length(min_span_years)==1L,
    min_span_years>=0,length(tolerance)==1L,is.finite(tolerance),tolerance>=0)
  dates<-as.Date(detail$daily$date)
  stopifnot(all(c("date","pcpn","pcpn_status") %in% names(detail$daily)),!anyNA(dates),!anyDuplicated(dates))
  groups<-list();raw<-data.frame()
  if(!is.null(cache)) {
    stopifnot(as.integer(cache$uid)==as.integer(detail$uid))
    raw<-cache$daily
    needed<-c("date","variable","numeric_value","observed","flag","accumulated")
    stopifnot(all(needed %in% names(raw)),inherits(raw$date,"Date"))
    raw<-raw[raw$variable=="pcpn" & raw$date<=min(as.Date(detail$as_of),as.Date(cache$as_of)),,drop=FALSE]
    if(anyDuplicated(raw$date))stop("Duplicate precipitation record dates.")
    good<-!is.na(raw$observed)&raw$observed&is.finite(raw$numeric_value)&
      raw$numeric_value>=0&raw$numeric_value<=100 &
      (is.na(raw$flag)|raw$flag %in% c("","T")) &
      (is.na(raw$accumulated)|!raw$accumulated)
    good[is.na(good)]<-FALSE
    eligible<-raw[good,,drop=FALSE]
    trace<-(!is.na(eligible$flag)&eligible$flag=="T")
    if("trace" %in% names(eligible))trace<-trace|(!is.na(eligible$trace)&eligible$trace)
    eligible$numeric_value[trace]<-0
    groups<-split(eligible,format(eligible$date,"%m-%d"))
  }
  values<-rep(NA_real_,length(dates));years<-rep("",length(dates))
  counts<-integer(length(dates));first<-last<-rep(NA_integer_,length(dates))
  status<-rep("INSUFFICIENT_HISTORY",length(dates))
  observed_status<-as.character(detail$daily$pcpn_status)
  observed_status[is.na(observed_status)|!nzchar(observed_status)]<-"MISSING"
  if(nrow(raw)) {
    ix<-match(dates,raw$date)
    accumulated<-!is.na(ix)&!is.na(raw$accumulated[ix])&raw$accumulated[ix]
    accumulated[is.na(accumulated)]<-FALSE
    observed_status[accumulated]<-"ACCUMULATED"
  }
  for(i in seq_along(dates)) {
    md<-format(dates[i],"%m-%d");sample<-groups[[md]]
    if(is.null(sample)||!nrow(sample))next
    sample<-sample[sample$date<dates[i],,drop=FALSE]
    counts[i]<-nrow(sample)
    if(!counts[i])next
    sy<-as.integer(format(sample$date,"%Y"));first[i]<-min(sy);last[i]<-max(sy)
    required<-if(md=="02-29")leap_min_years else min_years
    if(counts[i]<required || as.integer(format(dates[i],"%Y"))-first[i]<min_span_years)next
    extreme<-max(sample$numeric_value);values[i]<-extreme
    if(extreme>tolerance)years[i]<-paste(sort(sy[abs(sample$numeric_value-extreme)<=tolerance]),collapse=",")
    value<-detail$daily$pcpn[i]
    if(observed_status[i]=="TRACE")value<-0
    usable<-observed_status[i] %in% c("AVAILABLE","TRACE") &&
      is.numeric(value)&&length(value)==1L&&is.finite(value)
    status[i]<-if(observed_status[i]=="ACCUMULATED")"ACCUMULATED_REPORT" else
      if(!usable)"MISSING_OR_FLAGGED" else if(value>extreme+tolerance)"NEW_RECORD" else
      if(extreme<=tolerance)"NO_MEASURABLE_RECORD" else
      if(observed_status[i]=="TRACE")"WITHIN_RANGE" else
      if(abs(value-extreme)<=tolerance)"TIED_RECORD" else "WITHIN_RANGE"
  }
  detail$daily$record_pcpn<-values;detail$daily$record_pcpn_years<-years
  detail$daily$record_pcpn_n<-counts;detail$daily$record_pcpn_first_year<-first
  detail$daily$record_pcpn_last_year<-last;detail$daily$record_pcpn_status<-status
  detail$daily$pcpn_record_observation_status<-observed_status
  detail$precipitation_records<-list(method="Earlier eligible years on the exact calendar date; plotted observations excluded from their own references.",
    minimum_years=as.integer(min_years),leap_minimum_years=as.integer(leap_min_years),
    minimum_age_of_first_year=as.integer(min_span_years),tie_tolerance_inches=tolerance,
    trace_method="Trace contributes zero; an all-zero or trace-only reference cannot produce a tied wettest-day claim.",
    leap_day_method="Actual earlier February 29 reports only; no interpolation.",
    provenance="Eligible cached station/ThreadEx reports; accumulated and flagged reports excluded, not certified official records.")
  detail
}
