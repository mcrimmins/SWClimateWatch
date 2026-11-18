# Monthly project-calculated references from cached station observations.
acis_monthly_reference_inputs <- function(cache,period="reference",as_of=NULL) {
  period<-match.arg(period,c("reference","record"))
  if(is.null(cache))return(list(daily=NULL,cutoff=NA_character_,baseline=if(period=="reference")"1991\u20132020" else "Full available record"))
  cutoff<-as.Date(cache$as_of)
  if(!is.null(as_of))cutoff<-min(cutoff,as.Date(as_of))
  if(period=="reference")cutoff<-min(cutoff,as.Date("2020-12-31"))
  first<-as.Date(format(cutoff,"%Y-%m-01"))
  month_end<-seq(first,by="month",length.out=2L)[2]-1
  if(cutoff<month_end)cutoff<-first-1
  d<-cache$daily
  d<-d[d$date<=cutoff & d$variable %in% c("maxt","mint","pcpn"),,drop=FALSE]
  if(period=="reference")d<-d[d$date>=as.Date("1991-01-01"),,drop=FALSE]
  label<-if(period=="reference")"1991\u20132020" else if(nrow(d))
    paste0("Full available record (",format(min(d$date),"%Y"),"\u2013",format(max(d$date),"%Y"),")") else "Full available record"
  list(daily=d,cutoff=format(cutoff,"%Y-%m"),baseline=label)
}

acis_station_monthly_climatology <- function(cache,uid,min_years=20L,period="reference",as_of=NULL) {
  period<-match.arg(period,c("reference","record"))
  stopifnot(length(min_years)==1L,min_years>=1,min_years<=30)
  inputs<-acis_monthly_reference_inputs(cache,period,as_of)
  result<-data.frame(month=1:12,precip_inches=NA_real_,high_f=NA_real_,low_f=NA_real_,
    precip_p25=NA_real_,precip_p75=NA_real_,high_p25=NA_real_,high_p75=NA_real_,low_p25=NA_real_,low_p75=NA_real_,
    precipitation_years=0L,temperature_years=0L)
  for(variable in c("precip","high","low")) {
    for(stat in c("median","min","max"))result[[paste0(variable,"_",stat)]]<-NA_real_
    for(stat in c("min_years","max_years"))result[[paste0(variable,"_",stat)]]<-""
    for(stat in c("first_year","last_year"))result[[paste0(variable,"_",stat)]]<-NA_integer_
  }
  if(!is.null(cache)) {
    stopifnot(as.integer(cache$uid)==as.integer(uid))
    d<-inputs$daily
    stopifnot(inherits(d$date,"Date"),all(c("variable","numeric_value","observed","flag","accumulated","trace") %in% names(d)))
    if(anyDuplicated(d[c("date","variable")]))stop("Duplicate station climatology date/variable.")
    groups<-split(d,format(d$date,"%Y-%m"))
    monthly<-lapply(names(groups),function(key) {
      part<-groups[[key]];start<-as.Date(paste0(key,"-01"))
      dates<-seq(start,seq(start,by="month",length.out=2L)[2]-1,by="day")
      # Match within each variable, preserving absent dates explicitly.
      get<-function(variable){v<-part[part$variable==variable,,drop=FALSE];v[match(dates,v$date),,drop=FALSE]}
      h<-get("maxt");l<-get("mint");p<-get("pcpn")
      usable<-function(v) !is.na(v$observed)&v$observed&is.finite(v$numeric_value)&
        (is.na(v$flag)|v$flag=="")&abs(v$numeric_value)<=150
      paired<-usable(h)&usable(l)&h$numeric_value>=l$numeric_value
      paired[is.na(paired)]<-FALSE
      gaps<-rle(!paired);longest<-if(any(gaps$values))max(gaps$lengths[gaps$values]) else 0L
      temperature_ok<-mean(paired)>=.95 && longest<=2L
      precipitation_ok<-!is.na(p$observed)&p$observed&is.finite(p$numeric_value)&
        p$numeric_value>=0&p$numeric_value<=100&
        (is.na(p$flag)|p$flag %in% c("","T"))&
        (is.na(p$accumulated)|!p$accumulated)
      precipitation_ok[is.na(precipitation_ok)]<-FALSE
      trace<-(!is.na(p$trace)&p$trace)|(!is.na(p$flag)&p$flag=="T")
      p$numeric_value[trace]<-0
      data.frame(year=as.integer(substr(key,1,4)),month=as.integer(substr(key,6,7)),
        precip=if(all(precipitation_ok))sum(p$numeric_value) else NA_real_,
        high=if(temperature_ok)mean(h$numeric_value[paired]) else NA_real_,
        low=if(temperature_ok)mean(l$numeric_value[paired]) else NA_real_)
    })
    if(length(monthly)) {
      monthly<-do.call(rbind,monthly)
      for(m in 1:12) {
        x<-monthly[monthly$month==m,,drop=FALSE]
        result$precipitation_years[m]<-sum(is.finite(x$precip))
        result$temperature_years[m]<-sum(is.finite(x$high)&is.finite(x$low))
        if(result$precipitation_years[m]>=min_years) {
          result$precip_inches[m]<-mean(x$precip,na.rm=TRUE)
          result$precip_p25[m]<-unname(quantile(x$precip,.25,na.rm=TRUE,type=7))
          result$precip_p75[m]<-unname(quantile(x$precip,.75,na.rm=TRUE,type=7))
        }
        if(result$temperature_years[m]>=min_years) {
          result$high_f[m]<-mean(x$high,na.rm=TRUE);result$low_f[m]<-mean(x$low,na.rm=TRUE)
          for(variable in c("high","low")) {
            result[[paste0(variable,"_p25")]][m]<-unname(quantile(x[[variable]],.25,na.rm=TRUE,type=7))
            result[[paste0(variable,"_p75")]][m]<-unname(quantile(x[[variable]],.75,na.rm=TRUE,type=7))
          }
        }
        for(variable in c("precip","high","low")) {
          valid<-is.finite(x[[variable]])
          if(any(valid)) {
            result[[paste0(variable,"_first_year")]][m]<-min(x$year[valid])
            result[[paste0(variable,"_last_year")]][m]<-max(x$year[valid])
          }
          if(sum(valid)<min_years)next
          values<-x[[variable]][valid];years<-x$year[valid]
          result[[paste0(variable,"_median")]][m]<-median(values)
          result[[paste0(variable,"_min")]][m]<-min(values)
          result[[paste0(variable,"_max")]][m]<-max(values)
          result[[paste0(variable,"_min_years")]][m]<-paste(sort(years[abs(values-min(values))<=1e-8]),collapse=",")
          result[[paste0(variable,"_max_years")]][m]<-paste(sort(years[abs(values-max(values))<=1e-8]),collapse=",")
        }
      }
    }
  }
  list(schema_version=4L,uid=as.integer(uid),period_id=period,baseline=inputs$baseline,
    last_complete_month=inputs$cutoff,minimum_years=as.integer(min_years),
    variability="Precipitation boxes show the 25th\u201375th percentiles and median, with whiskers spanning the actual minimum\u2013maximum. Temperature lines show averages of monthly mean daily highs/lows, inner bands their 25th\u201375th percentiles, and outer envelopes their actual minimum\u2013maximum. All use the same eligible months in the selected reference period (R quantile type 7); no 1.5-IQR outlier rule. All tied extreme years are retained (numerical tolerance 1e-8). Extremes are lowest/highest in the selected available reference period, not certified official records or individual daily temperature records. Bands are not confidence intervals. Means may fall outside the IQR for skewed precipitation.",
    official_normals=FALSE,monthly=result,
    method="Mean of eligible monthly totals or monthly mean daily highs/lows across the selected reference period. Only finished calendar months are included. Precipitation months require every calendar day; trace is zero and accumulated reports are excluded. Temperature months require at least 95% valid paired days and no missing run over two days. At least 20 eligible years per month and variable; no infilling. Leap-day observations are included in their February. Fixed stations and ThreadEx retain separate histories.")
}

read_or_build_acis_monthly_climatology <- function(cache,uid,cache_dir,min_years=20L,period="reference",as_of=NULL) {
  period<-match.arg(period,c("reference","record"))
  inputs<-acis_monthly_reference_inputs(cache,period,as_of)
  d<-inputs$daily
  if(!is.null(d)) {
    d<-d[,c("date","variable","numeric_value","observed","flag","accumulated","trace"),drop=FALSE]
    d<-d[order(d$date,d$variable),,drop=FALSE];rownames(d)<-NULL
    d$date<-as.integer(d$date);d$numeric_value<-as.numeric(d$numeric_value)
  }
  key<-digest::digest(list(version=4L,uid=as.integer(uid),min_years=min_years,period=period,daily=d),algo="sha256",serializeVersion=2)
  dir.create(cache_dir,recursive=TRUE,showWarnings=FALSE)
  path<-file.path(cache_dir,paste0(uid,if(period=="record")"-record" else "",".rds"))
  old<-if(file.exists(path))tryCatch(readRDS(path),error=function(e)NULL) else NULL
  reused<-identical(old$key,key)&&is.list(old$reference)
  reference<-if(reused)old$reference else acis_station_monthly_climatology(cache,uid,min_years,period,as_of)
  if(reused) {
    # Refresh descriptive metadata without repeating unchanged calculations.
    metadata<-acis_station_monthly_climatology(NULL,uid,min_years,period,as_of)
    reference$baseline<-inputs$baseline
    reference$last_complete_month<-inputs$cutoff
    reference$method<-metadata$method;reference$variability<-metadata$variability
  }
  if(!reused || !identical(reference,old$reference))saveRDS(list(key=key,reference=reference),path)
  list(reference=reference,reused=reused)
}

prepare_acis_station_monthly_reference <- function(cache,uid,as_of,
    cache_dir=file.path("data","processed","acis-stations","monthly-climatology")) {
  baseline<-read_or_build_acis_monthly_climatology(cache,uid,cache_dir,as_of=as_of)
  record<-read_or_build_acis_monthly_climatology(cache,uid,cache_dir,period="record",as_of=as_of)
  reference<-baseline$reference
  reference$full_record<-record$reference
  reference$snapshot_date<-as.character(as.Date(as_of))
  list(reference=reference,reused=c(reference=baseline$reused,record=record$reused))
}

validate_acis_station_monthly_detail <- function(detail,uid,as_of) {
  fail<-function()stop("Station monthly climatology is missing, stale or invalid; rebuild station details.",call.=FALSE)
  bundle<-detail$monthly_climatology
  if(is.null(bundle)||is.null(bundle$full_record)||
     !identical(as.character(detail$as_of),as.character(as.Date(as_of)))||
     !identical(as.character(bundle$snapshot_date),as.character(as.Date(as_of)))||
     !identical(as.integer(detail$uid),as.integer(uid)))fail()
  for(period in c("reference","record")) {
    ref<-if(period=="reference")bundle else bundle$full_record
    x<-ref$monthly
    if(!identical(ref$schema_version,4L)||!identical(ref$period_id,period)||
       !identical(as.integer(ref$uid),as.integer(uid))||
       !identical(ref$minimum_years,20L)||!is.data.frame(x)||nrow(x)!=12L||
       !identical(as.integer(x$month),1:12))fail()
    if(period=="reference"&&!identical(ref$baseline,"1991\u20132020"))fail()
    if(period=="record"&&(length(ref$baseline)!=1L||!startsWith(ref$baseline,"Full available record")))fail()
    cutoff<-ref$last_complete_month
    if(!is.null(cutoff)&&!is.na(cutoff)) {
      if(!grepl("^[0-9]{4}-[0-9]{2}$",cutoff))fail()
      start<-tryCatch(as.Date(paste0(cutoff,"-01")),error=function(e)NA)
      if(is.na(start)||seq(start,by="month",length.out=2L)[2]-1>as.Date(as_of))fail()
    }else if(any(x$precipitation_years>0|x$temperature_years>0))fail()
    for(key in c("precip","high","low")) {
      count_field<-if(key=="precip")"precipitation_years" else "temperature_years"
      if(!count_field%in%names(x))fail()
      count<-x[[count_field]]
      fields<-paste0(key,c("_min","_p25","_median","_p75","_max"))
      mean_field<-switch(key,precip="precip_inches",high="high_f",low="low_f")
      if(!all(c(fields,mean_field,paste0(key,c("_first_year","_last_year","_min_years","_max_years")))%in%names(x))||
         anyNA(count)||any(count<0|count!=as.integer(count)))fail()
      if(period=="reference"&&any(count>30))fail()
      for(i in 1:12) {
        values<-as.numeric(unlist(x[i,fields],use.names=FALSE));avg<-x[[mean_field]][i]
        if(count[i]<20) {if(any(is.finite(c(values,avg))))fail();next}
        if(any(!is.finite(c(values,avg)))||any(diff(values)< -1e-6)||avg<values[1]-1e-6||avg>values[5]+1e-6)fail()
        first<-x[[paste0(key,"_first_year")]][i];last<-x[[paste0(key,"_last_year")]][i]
        if(!is.finite(first)||!is.finite(last)||count[i]>last-first+1)fail()
        if(period=="reference"&&(first<1991||last>2020))fail()
        if(!is.null(cutoff)&&!is.na(cutoff)) {
          last_allowed<-as.integer(substr(cutoff,1,4))-(i>as.integer(substr(cutoff,6,7)))
          if(last>last_allowed)fail()
        }
        for(which in c("min","max")) {
          years<-suppressWarnings(as.integer(strsplit(x[[paste0(key,"_",which,"_years")]][i],",",fixed=TRUE)[[1]]))
          if(!length(years)||anyNA(years)||any(years<first|years>last))fail()
        }
      }
    }
  }
  invisible(TRUE)
}
