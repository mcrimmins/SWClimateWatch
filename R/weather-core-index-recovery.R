# Bounded recovery for incomplete NOAA indexes. Never downloads a full GRIB.
weather_core_check_range <- function(body,status,content_range,start,end) {
  expected<-sprintf("bytes %.0f-%.0f/",start,end)
  if(!is.raw(body) || status!=206L || is.null(content_range) ||
      !startsWith(content_range,expected) || length(body)!=end-start+1)
    stop("Server did not return the exact requested byte range.")
  total<-suppressWarnings(as.numeric(sub(".*/","",content_range)))
  if(length(total)!=1L || !is.finite(total) || total<=end) stop("Invalid GRIB object size.")
  total
}

weather_core_find_surface_pressure <- function(bytes,offset=0) {
  uint<-function(x) sum(as.numeric(x)*256^rev(seq_along(x)-1L))
  hits<-grepRaw(charToRaw("GRIB"),bytes,fixed=TRUE,all=TRUE)
  found<-list()
  for(start in hits) {
    if(start+15L>length(bytes) || as.integer(bytes[start+6L])!=0L ||
        as.integer(bytes[start+7L])!=2L) next
    size<-uint(bytes[start+8:15]); end<-start+size-1
    if(size<20 || size>1e6 || end>length(bytes) ||
        !identical(bytes[(end-3):end],charToRaw("7777"))) next
    raw<-bytes[start:end]; k<-17L; product<-NULL; valid<-TRUE
    while(k<length(raw)-3L) {
      if(k+4L>length(raw)-4L) {valid<-FALSE; break}
      n<-uint(raw[k+0:3])
      if(n<5 || k+n-1>length(raw)-4L) {valid<-FALSE; break}
      if(as.integer(raw[k+4L])==4L) {
        if(!is.null(product)) {valid<-FALSE; break}
        product<-raw[k+seq_len(n)-1]
      }
      k<-k+n
    }
    # GRIB2 template 4.0, discipline 0/category 3/parameter 0,
    # zero forecast lead, first surface type 1, no second surface.
    if(!valid || k!=length(raw)-3L || length(product)<34L ||
        uint(product[8:9])!=0 || as.integer(product[10])!=3L ||
        as.integer(product[11])!=0L ||
        uint(product[19:22])!=0 || as.integer(product[23])!=1L ||
        as.integer(product[29])!=255L) next
    found[[length(found)+1L]]<-list(start=offset+start-1,end=offset+end-1,body=raw)
  }
  if(length(found)>1L) stop("Ambiguous surface-pressure recovery candidates.")
  if(length(found)) found[[1]] else NULL
}

weather_core_recover_surface_pressure <- function(base,stamp,directory,get_range,refresh=FALSE) {
  if(!grepl("^[0-9]{10}$",stamp) || !grepl("/grib/3hour/pgb/",base,fixed=TRUE))
    stop("Recovery supports only three-hourly CORe pgb analyses.")
  path<-file.path(directory,paste0("3hour-pgb-",stamp,"-PRES-surface.grb"))
  marker<-paste0(path,".recovery.rds")
  old<-if(file.exists(marker)) tryCatch(readRDS(marker),error=function(e) NULL) else NULL
  if(!refresh && is.list(old) && identical(old$base,base) && file.exists(path) &&
      identical(unname(tools::md5sum(path)),old$md5)) return(old$row)
  header<-get_range(paste0(base,".grb"),0,15)
  total<-attr(header,"object_size"); etag<-attr(header,"etag")
  if(length(header)!=16L || !identical(header[1:4],charToRaw("GRIB")) ||
      length(total)!=1L || !is.finite(total) || total<2e6 || total>100e6 ||
      is.null(etag) || !nzchar(etag)) stop("Invalid recovery object header or identity.")
  # Empirical search location only; no field is inferred from its position.
  # Strict GRIB metadata/date/units/grid checks still run on the recovered record.
  start<-floor(total/2)-1000000L
  a<-get_range(paste0(base,".grb"),start,start+999999L,etag)
  b<-get_range(paste0(base,".grb"),start+1000000L,start+1999999L,etag)
  if(!identical(attr(a,"object_size"),total) || !identical(attr(b,"object_size"),total) ||
      !identical(attr(a,"etag"),etag) || !identical(attr(b,"etag"),etag))
    stop("CORe object changed during recovery.")
  candidate<-weather_core_find_surface_pressure(c(a,b),offset=start)
  if(is.null(candidate)) return(NULL)
  weather_core_check_response(candidate$body,206L,
    sprintf("bytes %.0f-%.0f/%.0f",candidate$start,candidate$end,total),candidate$start,candidate$end)
  row<-data.frame(start=candidate$start,end=candidate$end,variable="PRES",level="surface",
    timing="anl",base=base,stamp=stamp,period="3hour",type="pgb")
  writeBin(candidate$body,path)
  hash<-unname(tools::md5sum(path))
  saveRDS(list(md5=hash),paste0(path,".rds"))
  saveRDS(list(base=base,row=row,md5=hash,etag=etag),marker)
  row
}
