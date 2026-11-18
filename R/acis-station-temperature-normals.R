# Project-calculated reference curves for local daily-chart review.
acis_station_temperature_normals <- function(cache,baseline_years=1991:2020,
    min_years=20L,smoothing_days=15L) {
  stopifnot(length(min_years)==1L,is.finite(min_years),min_years>=1,
    min_years==as.integer(min_years),length(smoothing_days)==1L,is.finite(smoothing_days),
    smoothing_days>=1,smoothing_days<=31,smoothing_days%%2==1,
    length(baseline_years)>0,!anyNA(baseline_years),!anyDuplicated(baseline_years),
    all(baseline_years==as.integer(baseline_years)))
  calendar<-format(seq(as.Date("2001-01-01"),as.Date("2001-12-31"),by="day"),"%m-%d")
  high<-low<-rep(NA_real_,365L);count<-integer(365L)
  if(!is.null(cache)) {
    d<-cache$daily
    required<-c("date","variable","numeric_value","observed","flag")
    if(!all(required %in% names(d)) || !inherits(d$date,"Date")) stop("Invalid daily normal inputs.")
    d<-d[d$variable %in% c("maxt","mint") & d$date<=cache$as_of &
      as.integer(format(d$date,"%Y")) %in% baseline_years,,drop=FALSE]
    if(anyDuplicated(d[c("date","variable")])) stop("Duplicate temperature reference dates.")
    dates<-sort(unique(d$date))
    hi<-d[d$variable=="maxt",,drop=FALSE];lo<-d[d$variable=="mint",,drop=FALSE]
    hi<-hi[match(dates,hi$date),,drop=FALSE];lo<-lo[match(dates,lo$date),,drop=FALSE]
    valid<-function(x) !is.na(x$observed)&x$observed&is.finite(x$numeric_value)&
      abs(x$numeric_value)<=150 & (is.na(x$flag)|x$flag=="")
    good<-valid(hi)&valid(lo)&hi$numeric_value>=lo$numeric_value
    md<-format(dates,"%m-%d");good[is.na(good)]<-FALSE
    good<-good & md!="02-29"
    count<-as.integer(table(factor(md[good],levels=calendar)))
    if(any(good)) {
      h<-tapply(hi$numeric_value[good],md[good],mean)
      l<-tapply(lo$numeric_value[good],md[good],mean)
      high<-as.numeric(h[calendar]);low<-as.numeric(l[calendar])
    }
  }
  high[count<min_years]<-low[count<min_years]<-NA_real_
  half<-(smoothing_days-1L)/2L
  windows<-lapply(seq_len(365L),function(i) ((i-1L+seq(-half,half))%%365L)+1L)
  smooth<-function(x) vapply(windows,function(w) if(any(!is.finite(x[w]))) NA_real_ else mean(x[w]),numeric(1))
  support<-vapply(windows,function(w) min(count[w]),integer(1))
  rows<-data.frame(month_day=calendar,normal_maxt=round(smooth(high),3),
    normal_mint=round(smooth(low),3),normal_years=support)
  neighbors<-match(c("02-28","03-01"),calendar)
  feb<-data.frame(month_day="02-29",normal_maxt=mean(rows$normal_maxt[neighbors]),
    normal_mint=mean(rows$normal_mint[neighbors]),normal_years=min(support[neighbors]))
  rows<-rbind(rows,feb)
  rows<-rows[order(rows$month_day),];rownames(rows)<-NULL
  list(schema_version=1L,uid=if(is.null(cache)) NA_integer_ else as.integer(cache$uid),
    baseline_years=as.integer(baseline_years),minimum_years=as.integer(min_years),
    smoothing_days=as.integer(smoothing_days),official_normals=FALSE,
    method="Calendar-day paired high/low means, followed by a centered cyclic smoother; unsupported days remain unavailable.",
    support_note="Minimum paired reference-year count across the smoothing window; years may differ among calendar dates.",
    leap_day_method="February 29 interpolates the smoothed February 28 and March 1 references.",
    daily=rows)
}

read_or_build_acis_temperature_normals <- function(cache,uid,cache_dir,
    min_years=20L,smoothing_days=15L) {
  baseline<-1991:2020
  d<-if(is.null(cache)) NULL else cache$daily
  if(!is.null(d)) {
    d<-d[d$variable %in% c("maxt","mint") & d$date<=cache$as_of &
      as.integer(format(d$date,"%Y")) %in% baseline,
      c("date","variable","numeric_value","observed","flag"),drop=FALSE]
    d<-d[order(d$date,d$variable),,drop=FALSE];rownames(d)<-NULL
    d$date<-as.integer(d$date)
    d$numeric_value<-as.numeric(d$numeric_value)
  }
  # Canonical dates/numbers and value serialization prevent storage changes
  # after row appends from invalidating an unchanged historical reference.
  key<-digest::digest(list(version=1L,uid=as.integer(uid),baseline=baseline,
    min_years=min_years,smoothing_days=smoothing_days,daily=d),algo="sha256",serializeVersion=2)
  dir.create(cache_dir,recursive=TRUE,showWarnings=FALSE)
  path<-file.path(cache_dir,paste0(uid,".rds"))
  old<-if(file.exists(path)) tryCatch(readRDS(path),error=function(e) NULL) else NULL
  reused<-identical(old$key,key)&&is.list(old$reference)&&identical(old$reference$schema_version,1L)
  if(reused) reference<-old$reference else {
    reference<-acis_station_temperature_normals(cache,baseline,min_years,smoothing_days)
    reference$uid<-as.integer(uid)
    saveRDS(list(key=key,reference=reference),path)
  }
  list(reference=reference,reused=reused)
}

acis_attach_temperature_normals <- function(detail,reference) {
  stopifnot(as.integer(detail$uid)==as.integer(reference$uid),is.data.frame(detail$daily))
  ix<-match(substr(detail$daily$date,6,10),reference$daily$month_day)
  for(field in c("normal_maxt","normal_mint","normal_years"))
    detail$daily[[field]]<-reference$daily[[field]][ix]
  detail$temperature_reference<-reference[setdiff(names(reference),"daily")]
  detail
}
