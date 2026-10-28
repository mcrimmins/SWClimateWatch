# Bounded PWAT/MSLP/low-level-wind renderer, used by the opt-in weather adapter.
weather_moisture_write_bin <- function(bytes,path) {
  if(!is.raw(bytes)) stop("Expected raw weather response bytes.")
  # Range-response attributes carry ETag/object size for recovery checks, but
  # writeBin requires an unadorned vector. Keep the caller's metadata intact.
  attributes(bytes) <- NULL
  writeBin(bytes,path)
}

weather_moisture_grid <- function(path,reference=NULL) {
  if (is.null(reference)) return(weather_core_grid(path))
  tryCatch(weather_core_grid(path),error=function(error) {
    b<-readBin(path,"raw",n=file.info(path)$size)
    uint<-function(x) sum(as.numeric(x)*256^rev(seq_along(x)-1))
    k<-17L; section<-NULL
    while (k<length(b)-4L) {
      n<-uint(b[k+0:3]); if(n<5 || k+n-1>length(b)) stop(error)
      s<-b[k+seq_len(n)-1]; if(as.integer(s[5])==3L) {section<-s; break}; k<-k+n
    }
    omit<-c(47:50,56:59)
    if (length(section)!=72L || !identical(section[-omit],reference$section[-omit]) ||
        abs(uint(section[47:50])-uint(reference$section[47:50]))>1000 ||
        abs(uint(section[56:59])-uint(reference$section[56:59]))>1000) stop(error)
    # Same Gaussian N/grid; flx and pgb endpoints differ slightly in encoding.
    reference
  })
}

weather_moisture_wind_mask <- function(surface_pressure,level_hpa) {
  if (!is.matrix(surface_pressure) || ncol(surface_pressure)!=8L ||
      length(level_hpa)!=1L || !level_hpa %in% c(700,850)) stop("Require eight pressure samples and 700 or 850 hPa.")
  rowSums(is.finite(surface_pressure) & surface_pressure>level_hpa*100)==8L
}

# Only terrain-screening pressure is optional. Missing/incomplete samples must
# not be filled, and malformed fields or required map variables still fail.
weather_moisture_select_field <- function(idx,variable,level,optional=FALSE) {
  if(optional && !(identical(variable,"PRES") && identical(level,"surface")))
    stop("Only surface-pressure screening fields may be optional.")
  row<-idx[idx$variable==variable & idx$level==level,,drop=FALSE]
  timing<-if(idx$period[1]=="day") "8@3 hour ave(anl),missing=0" else "anl"
  if(nrow(row)==0L || (nrow(row)==1L && !is.na(row$timing) && row$timing!=timing)) {
    if(optional) return(NULL)
    stop("Required complete field not found: ",variable," ",level)
  }
  if(nrow(row)!=1L || is.na(row$timing) || row$timing!=timing ||
      is.na(row$end) || row$end<row$start || row$end-row$start>1e6)
    stop("Invalid or ambiguous field: ",variable," ",level)
  row
}

weather_pressure_centers <- function(data,contrast_hpa=2,separation_km=900,max_centers=10L) {
  empty<-data.frame(x=numeric(),y=numeric(),pressure_hpa=numeric(),type=character(),contrast_hpa=numeric())
  x<-sort(unique(data$x)); y<-sort(unique(data$y))
  if(length(x)<5 || length(y)<5 || anyDuplicated(paste(data$x,data$y))) return(empty)
  z<-matrix(NA_real_,length(x),length(y))
  z[cbind(match(data$x,x),match(data$y,y))]<-data$pressure_hpa
  shift<-function(m,dx,dy) {
    result<-matrix(NA_real_,nrow(m),ncol(m))
    ix<-seq_len(nrow(m)); iy<-seq_len(ncol(m))
    goodx<-ix+dx>=1 & ix+dx<=nrow(m); goody<-iy+dy>=1 & iy+dy<=ncol(m)
    result[ix[goodx],iy[goody]]<-m[ix[goodx]+dx,iy[goody]+dy,drop=FALSE]
    result
  }
  # One native-cell weighted smoothing suppresses grid noise for detection only.
  # Contours remain unchanged; printed pressures come from original values.
  smooth<-matrix(0,nrow(z),ncol(z)); complete<-matrix(TRUE,nrow(z),ncol(z))
  weights<-c(1,2,1)
  for(dx in -1:1) for(dy in -1:1) {
    moved<-shift(z,dx,dy); complete<-complete & is.finite(moved)
    smooth<-smooth+ifelse(is.finite(moved),moved,0)*weights[dx+2]*weights[dy+2]/16
  }
  smooth[!complete]<-NA_real_
  if(!any(is.finite(smooth)) || diff(range(smooth,na.rm=TRUE))<contrast_hpa) return(empty)
  low<-high<-is.finite(smooth)
  strict_low<-strict_high<-matrix(FALSE,nrow(smooth),ncol(smooth))
  for(dx in -1:1) for(dy in -1:1) if(dx!=0 || dy!=0) {
    neighbor<-shift(smooth,dx,dy)
    low<-low & is.finite(neighbor) & smooth<=neighbor
    high<-high & is.finite(neighbor) & smooth>=neighbor
    strict_low<-strict_low | (is.finite(neighbor) & is.finite(smooth) & smooth<neighbor-1e-5)
    strict_high<-strict_high | (is.finite(neighbor) & is.finite(smooth) & smooth>neighbor+1e-5)
  }
  low<-low & strict_low; high<-high & strict_high
  candidates<-which(low | high,arr.ind=TRUE)
  if(!nrow(candidates)) return(empty)
  grid<-expand.grid(x=x,y=y); grid$pressure<-as.vector(smooth)
  distance<-function(lon,lat,xx,yy) {
    a<-sin((yy-lat)*pi/360)^2+cos(lat*pi/180)*cos(yy*pi/180)*sin((xx-lon)*pi/360)^2
    6371*2*asin(sqrt(pmin(1,pmax(0,a))))
  }
  found<-list()
  for(i in seq_len(nrow(candidates))) {
    ix<-candidates[i,1]; iy<-candidates[i,2]; xx<-x[ix]; yy<-y[iy]
    # Do not invent centers at a clipped map edge.
    edge<-min(distance(xx,yy,c(min(x),max(x),xx,xx),c(yy,yy,min(y),max(y))))
    if(edge<800) next
    d<-distance(xx,yy,grid$x,grid$y)
    inner<-d<=400; ring<-d>=500 & d<=800
    if(sum(is.finite(grid$pressure[ring]))<.9*sum(ring)) next
    value<-smooth[ix,iy]; type<-if(low[ix,iy]) "L" else "H"
    sign<-if(type=="L") 1 else -1
    if(any(sign*(grid$pressure[inner]-value)< -1e-6,na.rm=TRUE)) next
    differences<-sign*(grid$pressure[ring]-value)
    contrast<-stats::median(differences,na.rm=TRUE)
    # A broad high can be elongated. Require median contrast plus 90% support
    # around the ring, without demanding a full 2 hPa in every direction.
    if(!is.finite(contrast) || contrast<contrast_hpa ||
      unname(stats::quantile(differences,.1,na.rm=TRUE))<.1) next
    row<-which(data$x==xx & data$y==yy)
    # Pressure reduction difference is a conservative existing-data elevation
    # proxy. Avoid centers with roughly >100 hPa of reduction to sea level.
    if("surface_hpa" %in% names(data) && (!is.finite(data$surface_hpa[row]) ||
      data$pressure_hpa[row]-data$surface_hpa[row]>100)) next
    found[[length(found)+1L]]<-data.frame(x=xx,y=yy,pressure_hpa=data$pressure_hpa[row],
      type=type,contrast_hpa=contrast)
  }
  if(!length(found)) return(empty)
  centers<-do.call(rbind,found)
  centers<-centers[order(-centers$contrast_hpa,centers$x,centers$y),]
  keep<-logical(nrow(centers)); counts<-c(H=0L,L=0L)
  for(i in seq_len(nrow(centers))) {
    previous<-which(keep)
    if(sum(keep)>=max_centers || counts[centers$type[i]]>=ceiling(max_centers/2)) next
    if(length(previous) && any(distance(centers$x[i],centers$y[i],centers$x[previous],centers$y[previous])<separation_km)) next
    keep[i]<-TRUE; counts[centers$type[i]]<-counts[centers$type[i]]+1L
  }
  centers[keep,,drop=FALSE]
}

weather_moisture_plot <- function(template,latitude,pwat,mslp,u,v,mask,date,level,path,surface_pressure=NULL) {
  data<-terra::as.data.frame(template,xy=TRUE,na.rm=FALSE)[,1:2]; names(data)<-c("x","y")
  data$y<-rep(latitude,each=terra::ncol(template)); data$x<-ifelse(data$x<120,data$x+360,data$x)
  edges<-c(90,(head(latitude,-1)+tail(latitude,-1))/2,-90)
  data$ymin<-rep(tail(edges,-1),each=terra::ncol(template)); data$ymax<-rep(head(edges,-1),each=terra::ncol(template))
  data$xmin<-data$x-terra::res(template)[1]/2; data$xmax<-data$x+terra::res(template)[1]/2
  data$pwat<-pwat/25.4; data$height_dm<-mslp/100; data$u<-u; data$v<-v; data$mask<-mask
  data$pressure_hpa<-mslp/100
  if(!is.null(surface_pressure)) data$surface_hpa<-surface_pressure/100
  detection_started<-proc.time()[["elapsed"]]
  context<-data[data$x>=120 & data$x<=300 & data$y>=0 & data$y<=85,]
  centers<-weather_pressure_centers(context)
  centers<-centers[centers$x>124 & centers$x<296 & centers$y>12 & centers$y<68,]
  detection_seconds<-proc.time()[["elapsed"]]-detection_started
  utils::write.csv(centers,sub("\\.png$","-centers.csv",path),row.names=FALSE)
  data<-data[data$x>=120 & data$x<=300 & data$y>=10 & data$y<=70,]
  labels<-weather_contour_labels(data,breaks=seq(880,1080,4))
  for(i in seq_len(nrow(centers))) labels<-labels[
    ((labels$x-centers$x[i])/3)^2+((labels$y-centers$y[i]-.5)/2)^2>1,]
  arrows<-data[match(data$x,sort(unique(data$x)))%%8==0 &
    match(data$y,sort(unique(data$y)))%%8==0 & data$mask & is.finite(data$u) & is.finite(data$v),]
  arrows<-arrows[sqrt(arrows$u^2+arrows$v^2)>=2,]
  arrows$xend<-arrows$x+.12*arrows$u/cos(arrows$y*pi/180); arrows$yend<-arrows$y+.12*arrows$v
  world<-ggplot2::map_data("world"); world$x<-ifelse(world$long<120,world$long+360,world$long)
  world$piece<-cumsum(c(TRUE,diff(world$group)!=0 | abs(diff(world$x))>180))
  states<-ggplot2::map_data("state"); states$x<-states$long+360
  sw<-states[states$region %in% c("arizona","new mexico"),]
  plot<-ggplot2::ggplot(data,ggplot2::aes(x,y))+
    ggplot2::geom_rect(ggplot2::aes(xmin=xmin,xmax=xmax,ymin=ymin,ymax=ymax,fill=pwat),colour=NA)+
    ggplot2::geom_path(data=world,ggplot2::aes(x,lat,group=piece),inherit.aes=FALSE,linewidth=.25,colour="#47504e")+
    ggplot2::geom_path(data=states,ggplot2::aes(x,lat,group=group),inherit.aes=FALSE,linewidth=.15,colour="#686b60")+
    ggplot2::geom_contour(ggplot2::aes(z=height_dm),breaks=seq(880,1080,4),colour="#303934",linewidth=.28)+
    ggplot2::geom_label(data=labels,ggplot2::aes(label=label),size=2.4,linewidth=0,
      fill=scales::alpha("white",.65),label.padding=grid::unit(.04,"lines"))+
    ggplot2::geom_segment(data=arrows,ggplot2::aes(xend=xend,yend=yend),colour="#163b56",linewidth=.28,
      arrow=grid::arrow(length=grid::unit(1,"mm")))+
    ggplot2::geom_path(data=sw,ggplot2::aes(x,lat,group=group),inherit.aes=FALSE,linewidth=1.05,colour="white")+
    ggplot2::geom_path(data=sw,ggplot2::aes(x,lat,group=group),inherit.aes=FALSE,linewidth=.6,colour="#843b86")+
    ggplot2::geom_label(data=centers,ggplot2::aes(label=type,colour=type),size=5,fontface="bold",
      linewidth=0,fill=scales::alpha("white",.75),label.padding=grid::unit(.03,"lines"))+
    ggplot2::geom_label(data=centers,ggplot2::aes(y=y+1.5,label=round(pressure_hpa),colour=type),size=2.8,fontface="bold",
      linewidth=0,fill=scales::alpha("white",.75),label.padding=grid::unit(.03,"lines"))+
    ggplot2::scale_colour_manual(values=c(H="#174ea6",L="#b3261e"),guide="none")+
    (if(any(mask)) list(ggplot2::annotate("rect",xmin=123,xmax=157,ymin=10.8,ymax=15.5,fill="white",alpha=.9),
    ggplot2::annotate("segment",x=127,y=13,xend=127+.12*(20/1.943844)/cos(13*pi/180),yend=13,
      colour="#163b56",arrow=grid::arrow(length=grid::unit(1,"mm")),linewidth=.3),
    ggplot2::annotate("text",x=144,y=13,label="20 knots",size=3)) else NULL)+
    ggplot2::scale_fill_gradientn(colours=c("#776a5a","#a57c50","#c68a42","#edb86a","#f8edb2",
      "#d8efc1","#8dd4ad","#4daead","#4383bc","#6963b5","#754594","#46185f"),
      values=scales::rescale(c(0,.1,.25,.5,.75,1,1.25,1.5,1.75,2,2.5,3),from=c(0,3)),
      limits=c(0,3),oob=scales::squish,name="Total precipitable water (inches)",
      breaks=c(0,.25,.5,.75,1,1.5,2,2.5,3),
      labels=c("0","0.25","0.5","0.75","1","1.5","2","2.5","3+"),
      guide=ggplot2::guide_colourbar(barwidth=grid::unit(20,"cm")))+
    ggplot2::coord_quickmap(xlim=c(120,300),ylim=c(10,70),expand=FALSE)+
    ggplot2::scale_x_continuous(breaks=seq(120,300,30),labels=c("120E","150E","180","150W","120W","90W","60W"))+
    ggplot2::labs(title=if(any(mask)) paste0("Moisture and low-level flow: PWAT, sea-level pressure and ",level,"-mb winds") else
      "Moisture: PWAT and sea-level pressure (wind overlay unavailable)",
      subtitle=paste(date,"UTC | CORe ensemble mean | Eight-sample daily average | Pressure contours: 4 hPa"),x=NULL,y=NULL,
      caption=paste(if(!any(mask)) "NOAA CPC CORe | Wind overlay unavailable: incomplete terrain-screening inputs" else
        paste0("NOAA CPC CORe | ",level,"-mb winds omitted if below terrain at any of eight daily samples"),
        if(!is.null(surface_pressure) && !any(is.finite(surface_pressure)))
          "H/L unavailable: incomplete daily surface pressure. Sea-level pressure over high terrain requires caution." else
          "H/L: filtered daily-mean pressure centers, not tracked storms. Sea-level pressure over high terrain requires caution.",
        "Winds at one level, not IVT | Climate Science Applications Program - University of Arizona",sep="\n"))+
    ggplot2::theme_minimal(base_size=10)+ggplot2::theme(plot.title=ggplot2::element_text(face="bold"),
      legend.position="bottom",legend.title.position="top")
  ggplot2::ggsave(path,plot,width=12,height=6.8,dpi=160,bg="white")
  invisible(list(centers=nrow(centers),detection_seconds=detection_seconds))
}

run_weather_moisture_pilot <- function(dates=as.Date(c("2023-03-01","2024-07-15")),wind_level=850L,
    output_dir=file.path("data","diagnostics","weather-moisture-pilot"),refresh=FALSE) {
  dates<-as.Date(dates)
  if (!length(dates) || length(dates)>2L || anyNA(dates) || anyDuplicated(dates) ||
      length(wind_level)!=1L || !wind_level %in% c(700,850)) stop("Choose 1-2 dates and 700 or 850 mb.")
  all_runs<-lapply(seq_along(dates),function(i) {
    date<-dates[i]; started<-proc.time()[["elapsed"]]; bytes<-requests<-download_seconds<-0
    directory<-file.path(output_dir,as.character(date)); dir.create(directory,recursive=TRUE,showWarnings=FALSE)
    reference<-template<-NULL; metadata<-list()
    recoveries<-0L; recovered_hours<-character(); recovery_notes<-character()
    get<-function(url,start=NULL,end=NULL,allow_missing=FALSE,record=TRUE,etag=NULL) {
      if (proc.time()[["elapsed"]]-started>90 || requests>=32 || bytes>7e6 ||
          (!is.null(start) && bytes+end-start+1>7e6)) stop("Moisture request/time budget exceeded.")
      begin<-proc.time()[["elapsed"]]; req<-weather_core_request(url)
      if(allow_missing) req<-httr2::req_error(req,is_error=function(resp) httr2::resp_status(resp)>=400 && httr2::resp_status(resp)!=404L)
      if(!is.null(start)) req<-httr2::req_headers(req,Range=sprintf("bytes=%.0f-%.0f",start,end),`Accept-Encoding`="identity")
      if(!is.null(etag)) req<-httr2::req_headers(req,`If-Match`=etag)
      requests<<-requests+1L; response<-httr2::req_perform(req)
      if(allow_missing && (httr2::resp_status(response)==404L || identical(httr2::resp_header(response,"Content-Length"),"0"))) return(raw(0))
      raw<-httr2::resp_body_raw(response)
      bytes<<-bytes+length(raw); download_seconds<<-download_seconds+proc.time()[["elapsed"]]-begin
      if(is.null(start)) {if(httr2::resp_status(response)!=200L) stop("Missing moisture index.")}
      else {
        total<-weather_core_check_range(raw,httr2::resp_status(response),httr2::resp_header(response,"Content-Range"),start,end)
        if(record) weather_core_check_response(raw,httr2::resp_status(response),httr2::resp_header(response,"Content-Range"),start,end)
        attr(raw,"object_size")<-total; attr(raw,"etag")<-httr2::resp_header(response,"ETag")
      }
      raw
    }
    index<-function(type,hour=NULL) {
      period<-if(is.null(hour)) "day" else "3hour"
      stamp<-paste0(format(date,"%Y%m%d"),if(!is.null(hour)) sprintf("%02d",hour) else "")
      base<-paste0("https://storage.googleapis.com/noaa-nws-ncep-core/grib/",period,"/",type,"/",format(date,"%Y/%m/"),type,".",stamp)
      path<-file.path(directory,paste0(period,"-",type,"-",stamp,".idx"))
      raw<-if(file.exists(path) && !refresh) readBin(path,"raw",n=file.info(path)$size) else {
        b<-get(paste0(base,".idx"),allow_missing=!is.null(hour)); writeBin(b,path); b
      }
      if(!length(raw) && !is.null(hour)) {
        metadata[[length(metadata)+1L]]<<-data.frame(variable="PRES",level="surface unavailable",
          source=paste0(base,".idx"),start=NA_real_,end=NA_real_,md5=NA_character_)
        return(NULL)
      }
      parts<-strsplit(trimws(strsplit(rawToChar(raw),"\n",fixed=TRUE)[[1]]),":",fixed=TRUE)
      parts<-parts[lengths(parts)>1L]; if(any(lengths(parts)<6L)) stop("Malformed moisture index.")
      offsets<-as.numeric(vapply(parts,`[`,character(1),2L))
      if(any(!is.finite(offsets)) || any(diff(offsets)<=0)) stop("Invalid moisture index offsets.")
      stamps<-vapply(parts,`[`,character(1),3L)
      if(any(stamps!=paste0("d=",format(date,"%Y%m%d"),if(is.null(hour)) "00" else sprintf("%02d",hour)))) stop("Index date mismatch.")
      data.frame(start=offsets,end=c(offsets[-1]-1,NA_real_),variable=vapply(parts,`[`,character(1),4L),
        level=vapply(parts,`[`,character(1),5L),timing=vapply(parts,`[`,character(1),6L),base=base,
        stamp=stamp,period=period,type=type)
    }
    field<-function(idx,variable,level,unit,optional=FALSE,force_refresh=refresh) {
      row<-weather_moisture_select_field(idx,variable,level,optional)
      if(is.null(row)) {
        metadata[[length(metadata)+1L]]<<-data.frame(variable=variable,level=paste(level,"unavailable"),
          source=paste0(idx$base[1],".idx"),start=NA_real_,end=NA_real_,md5=NA_character_)
        return(rep(NA_real_,terra::ncell(template)))
      }
      path<-file.path(directory,paste0(row$period,"-",row$type,"-",row$stamp,"-",variable,"-",gsub("[^A-Za-z0-9]","_",level),".grb"))
      marker<-paste0(path,".rds")
      old<-if(file.exists(marker)) readRDS(marker) else NULL
      if(force_refresh || !file.exists(path) || !is.list(old) || !identical(old$md5,unname(tools::md5sum(path)))) {
        raw<-get(paste0(row$base,".grb"),row$start,row$end); weather_moisture_write_bin(raw,path)
        saveRDS(list(md5=unname(tools::md5sum(path))),marker)
      }
      info<-terra::describe(path,print=FALSE)
      expected_time<-as.numeric(as.POSIXct(strptime(row$stamp,"%Y%m%d%H",tz="UTC")))
      if(row$period=="day") expected_time<-as.numeric(as.POSIXct(paste(date,"21:00:00"),tz="UTC"))
      if(!any(grepl(paste0("GRIB_ELEMENT=",variable),info,fixed=TRUE)) ||
          !any(grepl(paste0("GRIB_UNIT=",unit),info,fixed=TRUE)) ||
          !any(grepl(paste0("GRIB_VALID_TIME=",sprintf("%.0f",expected_time)),info,fixed=TRUE))) stop("Unexpected moisture field units or valid time.")
      if(grepl(" mb$",level) && !any(grepl(paste0("GRIB_SHORT_NAME=",sprintf("%.0f",as.numeric(sub(" mb$","",level))*100),"-ISBL"),info,fixed=TRUE))) stop("Wind level mismatch.")
      grid<-weather_moisture_grid(path,reference); raster<-terra::rast(path)
      if(is.null(reference)) {reference<<-grid; template<<-raster}
      else if(!identical(grid$section,reference$section) || !terra::compareGeom(template,raster,stopOnError=FALSE)) stop("Moisture grid mismatch.")
      metadata[[length(metadata)+1L]]<<-data.frame(variable=variable,level=level,source=paste0(row$base,".grb"),
        start=row$start,end=row$end,md5=unname(tools::md5sum(path)))
      as.numeric(terra::values(raster,mat=FALSE))
    }
    pgb<-index("pgb"); flx<-index("flx")
    mslp<-field(pgb,"MSLET","mean sea level","[Pa]")
    # Pressure-center terrain screening uses the matching complete daily mean.
    # Wind screening independently requires every hourly sample above ground.
    daily_surface_pressure<-field(pgb,"PRES","surface","[Pa]",optional=TRUE)
    pwat<-field(flx,"PWAT","atmos col","[kg/(m^2)]")
    u<-field(pgb,"UGRD",paste(wind_level,"mb"),"[m/s]")
    v<-field(pgb,"VGRD",paste(wind_level,"mb"),"[m/s]")
    ps<-vapply(seq(0,21,3),function(hour) {
      idx<-index("pgb",hour)
      missing<-is.null(idx) || is.null(weather_moisture_select_field(idx,"PRES","surface",TRUE))
      if(missing && recoveries<2L) {
        recoveries<<-recoveries+1L
        stamp<-paste0(format(date,"%Y%m%d"),sprintf("%02d",hour))
        base<-paste0("https://storage.googleapis.com/noaa-nws-ncep-core/grib/3hour/pgb/",format(date,"%Y/%m/"),"pgb.",stamp)
        recovered<-tryCatch(weather_core_recover_surface_pressure(base,stamp,directory,
          get_range=function(url,start,end,etag=NULL) get(url,start,end,record=FALSE,etag=etag),
          refresh=refresh),error=function(e) {
            recovery_notes<<-c(recovery_notes,paste(stamp,conditionMessage(e))); NULL
          })
        if(!is.null(recovered)) {
          recovered_hours<<-c(recovered_hours,stamp)
          # Run the ordinary units, exact valid-time and grid checks, even for
          # a recovered/cached record. Never infer identity from byte position.
          return(field(recovered,"PRES","surface","[Pa]",force_refresh=FALSE))
        }
      }
      if(is.null(idx)) rep(NA_real_,length(u)) else field(idx,"PRES","surface","[Pa]",optional=TRUE)
    },numeric(length(u)))
    mask<-weather_moisture_wind_mask(ps,wind_level)
    if(any(!is.finite(mslp)) || any(!is.finite(pwat)) || any(pwat<0 | pwat>150)) stop("Invalid pressure/PWAT values.")
    before_plot<-proc.time()[["elapsed"]]
    path<-file.path(directory,paste0("pwat-mslp-wind",wind_level,".png"))
    plot_marker<-paste0(path,".rds")
    plot_signature<-digest::digest(list(source=metadata,level=wind_level,
      renderer=lapply(list(weather_moisture_plot,weather_pressure_centers,weather_moisture_wind_mask),body),
      R=R.version.string,packages=vapply(c("terra","ggplot2","maps","scales"),function(p)
        as.character(utils::packageVersion(p)),character(1))),algo="sha256")
    old_plot<-if(file.exists(plot_marker)) tryCatch(readRDS(plot_marker),error=function(e) NULL) else NULL
    reuse_plot<-is.list(old_plot) && identical(old_plot$signature,plot_signature) && file.exists(path) &&
      identical(old_plot$md5,unname(tools::md5sum(path)))
    if(reuse_plot) plot_result<-old_plot$result else {
      plot_result<-weather_moisture_plot(template,reference$latitude,pwat,mslp,u,v,mask,date,wind_level,path,
        surface_pressure=daily_surface_pressure)
      saveRDS(list(signature=plot_signature,md5=unname(tools::md5sum(path)),result=plot_result),plot_marker)
    }
    utils::write.csv(do.call(rbind,metadata),file.path(directory,paste0("sources-",wind_level,".csv")),row.names=FALSE)
    result<-data.frame(date=as.character(date),wind_level=wind_level,requests=requests,transferred_bytes=bytes,
      download_seconds=download_seconds,render_seconds=proc.time()[["elapsed"]]-before_plot,
      total_seconds=proc.time()[["elapsed"]]-started,masked_global_wind_cells=sum(!mask),map=path)
    result$pressure_centers<-plot_result$centers; result$center_detection_seconds<-plot_result$detection_seconds
    result$map_reused<-reuse_plot
    result$terrain_samples_available<-sum(colSums(is.finite(ps))>0)
    result$center_screen_available<-any(is.finite(daily_surface_pressure))
    result$pressure_recovery_attempts<-recoveries
    result$pressure_recovered_samples<-length(recovered_hours)
    result$pressure_recovery_notes<-paste(recovery_notes,collapse="; ")
    message("Moisture map ready: ",path); result
  })
  summary<-do.call(rbind,all_runs)
  utils::write.csv(summary,file.path(output_dir,paste0("summary-",wind_level,".csv")),row.names=FALSE)
  history<-file.path(output_dir,paste0("run-history-",wind_level,".csv"))
  logged<-cbind(run_utc=format(Sys.time(),"%Y-%m-%d %H:%M:%S UTC",tz="UTC"),summary)
  if(file.exists(history)) {
    old<-utils::read.csv(history)
    for(name in setdiff(names(logged),names(old))) old[[name]]<-NA
    logged<-rbind(old[,names(logged),drop=FALSE],logged)
  }
  utils::write.csv(logged,history,row.names=FALSE)
  print(summary,row.names=FALSE)
  invisible(list(summary=summary))
}
