# Optional local overlay build. Complete period means; no publication changes.
weather_overlay_specs <- function(date) {
  stamp<-format(as.Date(date),"%Y%m%d")
  rows<-data.frame(field=c("mslp","u850","v850","surface"),variable=c("MSLET","UGRD","VGRD","PRES"),
    level=c("mean sea level","850 mb","850 mb","surface"),stamp=stamp,period="day",optional=c(FALSE,FALSE,FALSE,TRUE))
  rbind(rows,data.frame(field=paste0("surface",sprintf("%02d",seq(0,21,3))),variable="PRES",level="surface",
    stamp=paste0(stamp,sprintf("%02d",seq(0,21,3))),period="3hour",optional=TRUE))
}

weather_overlay_record <- function(lines,spec) {
  parts<-strsplit(lines[nzchar(trimws(lines))],":",fixed=TRUE)
  if(!length(parts)||any(lengths(parts)<6))stop("Malformed overlay index.")
  offset<-suppressWarnings(as.numeric(vapply(parts,`[`,character(1),2)))
  if(any(!is.finite(offset))||any(offset<0)||any(diff(offset)<=0))stop("Invalid overlay offsets.")
  stamp<-paste0("d=",spec$stamp,if(spec$period=="day")"00" else "")
  if(any(vapply(parts,`[`,character(1),3)!=stamp))stop("Overlay index date mismatch.")
  found<-which(vapply(parts,`[`,character(1),4)==spec$variable & vapply(parts,`[`,character(1),5)==spec$level)
  timing<-if(spec$period=="day")"8@3 hour ave(anl),missing=0" else "anl"
  if(!length(found)&&spec$optional)return(NULL)
  if(length(found)!=1L||found==length(parts))stop("Missing or ambiguous overlay field: ",spec$field)
  if(parts[[found]][6]!=timing){if(spec$optional)return(NULL);stop("Incomplete overlay samples.")}
  start<-offset[found];end<-offset[found+1L]-1
  if(end<start||end-start+1>1e6)stop("Overlay range cap exceeded.")
  list(start=start,end=end)
}

weather_overlay_inputs <- function(dates,download_missing=FALSE,
    directory="data/diagnostics/weather-period-overlay-inputs",max_requests=700L,max_bytes=80e6) {
  if(length(dates)>30||anyDuplicated(dates))stop("Overlay date cap exceeded.")
  roots<-unique(c(directory,weather_mean_roots()))
  requests<-bytes<-0;rows<-list()
  fetch<-function(url,record=NULL,optional=FALSE,verify_grib=TRUE,etag=NULL) {
    if(requests>=max_requests||bytes>=max_bytes)stop("Overlay request/byte cap exceeded.")
    req<-weather_core_request(url)
    if(optional)req<-httr2::req_error(req,is_error=function(r)httr2::resp_status(r)>=400&&httr2::resp_status(r)!=404)
    if(!is.null(record))req<-httr2::req_headers(req,Range=sprintf("bytes=%.0f-%.0f",record$start,record$end),`Accept-Encoding`="identity")
    if(!is.null(etag))req<-httr2::req_headers(req,`If-Match`=etag)
    requests<<-requests+1L;response<-httr2::req_perform(req)
    if(optional&&(httr2::resp_status(response)==404||identical(httr2::resp_header(response,"Content-Length"),"0")))return(NULL)
    body<-httr2::resp_body_raw(response);bytes<<-bytes+length(body)
    if(bytes>max_bytes)stop("Overlay byte cap exceeded.")
    attributes(body)<-NULL
    if(!is.null(record)) {
      total<-weather_core_check_range(body,httr2::resp_status(response),httr2::resp_header(response,"Content-Range"),record$start,record$end)
      if(verify_grib)weather_core_check_response(body,httr2::resp_status(response),httr2::resp_header(response,"Content-Range"),record$start,record$end)
      attr(body,"object_size")<-total;attr(body,"etag")<-httr2::resp_header(response,"ETag")
    }
    body
  }
  for(date in as.character(dates)) {
    target<-file.path(directory,date);dir.create(target,recursive=TRUE,showWarnings=FALSE)
    specs<-weather_overlay_specs(date)
    for(i in seq_len(nrow(specs))) {
      s<-specs[i,];index_name<-paste0(s$period,"-pgb-",s$stamp,".idx")
      field_name<-paste0(s$period,"-pgb-",s$stamp,"-",s$variable,"-",gsub("[^A-Za-z0-9]","_",s$level),".grb")
      index<-path<-NULL
      # A cached field must match its original index and checksum marker.
      for(root in roots) {
        candidate<-file.path(root,date,field_name);idx<-file.path(root,date,index_name)
        if(s$period=="day"&&!file.exists(idx))idx<-file.path(root,date,"source.idx")
        if(file.exists(paste0(candidate,".recovered.idx")))idx<-paste0(candidate,".recovered.idx")
        if(!all(file.exists(c(candidate,paste0(candidate,".rds"),idx))))next
        valid<-tryCatch({rec<-if(file.info(idx)$size>0)weather_overlay_record(readLines(idx,warn=FALSE),s) else NULL
          if(is.null(rec)&&s$optional&&s$period=="3hour"&&file.exists(paste0(candidate,".recovery.rds"))) {
            recovery<-readRDS(paste0(candidate,".recovery.rds"))
            rr<-recovery$row
            if(is.list(recovery)&&identical(recovery$md5,unname(tools::md5sum(candidate)))&&
                nrow(rr)==1L&&identical(rr$stamp,s$stamp)&&identical(rr$variable,"PRES")&&identical(rr$level,"surface")&&identical(rr$timing,"anl")) {
              idx<-file.path(target,paste0(field_name,".recovered.idx"))
              writeLines(c(sprintf("1:%.0f:d=%s:PRES:surface:anl:",rr$start,s$stamp),
                sprintf("2:%.0f:d=%s:END:surface:anl:",rr$end+1,s$stamp)),idx)
              rec<-list(start=rr$start,end=rr$end)
            }
          }
          !is.null(rec)&&identical(readRDS(paste0(candidate,".rds"))$md5,unname(tools::md5sum(candidate)))&&file.info(candidate)$size==rec$end-rec$start+1},error=function(e)FALSE)
        if(isTRUE(valid)){path<-candidate;index<-idx;break}
      }
      state<-"CACHED";note<-""
      if(is.null(path)) {
        index<-file.path(target,index_name)
        if(!file.exists(index)) {
          cached_indexes<-c(file.path(roots,date,index_name),if(s$period=="day")file.path(roots,date,"source.idx"))
          cached_indexes<-cached_indexes[file.exists(cached_indexes)]
          if(length(cached_indexes))file.copy(cached_indexes[1],index)
        }
        base<-paste0("https://storage.googleapis.com/noaa-nws-ncep-core/grib/",s$period,"/pgb/",format(as.Date(date),"%Y/%m/"),"pgb.",s$stamp)
        if(!file.exists(index)) {
          if(!download_missing)stop("Missing cached overlay index. Set SWC_WEATHER_MEAN_DOWNLOAD=true for the bounded local overlay build.")
          raw<-fetch(paste0(base,".idx"),optional=s$optional)
          writeBin(if(is.null(raw))raw(0) else raw,index)
        }
        rec<-if(file.exists(index)&&file.info(index)$size>0)weather_overlay_record(readLines(index,warn=FALSE),s) else NULL
        if(is.null(rec)&&s$optional&&s$period=="3hour") {
          recovered<-tryCatch(weather_core_recover_surface_pressure(base,s$stamp,target,
            get_range=function(url,start,end,etag=NULL) {
              if(!download_missing)stop("Recovery input not cached.")
              fetch(url,list(start=start,end=end),verify_grib=FALSE,etag=etag)
            }),error=function(e){note<<-paste("Surface-pressure recovery unavailable:",conditionMessage(e));NULL})
          if(!is.null(recovered)) {
            path<-file.path(target,field_name);index<-paste0(path,".recovered.idx")
            writeLines(c(sprintf("1:%.0f:d=%s:PRES:surface:anl:",recovered$start,s$stamp),
              sprintf("2:%.0f:d=%s:END:surface:anl:",recovered$end+1,s$stamp)),index)
            saveRDS(list(md5=unname(tools::md5sum(path))),paste0(path,".rds"));state<-"RECOVERED"
          }
        }
        if(!is.null(path)) {
          # Recovered field already verified by GRIB identity; decoded below.
        } else if(is.null(rec)&&s$optional){state<-"UNAVAILABLE";note<-paste(note,"Terrain screening unavailable; corresponding wind arrows withheld.")} else {
          if(!download_missing)stop("Missing cached overlay field: ",date," ",s$field,". Set SWC_WEATHER_MEAN_DOWNLOAD=true.")
          raw<-fetch(paste0(base,".grb"),rec);path<-file.path(target,field_name)
          weather_moisture_write_bin(raw,path);saveRDS(list(md5=unname(tools::md5sum(path))),paste0(path,".rds"));state<-"FETCHED"
        }
      }
      rows[[length(rows)+1L]]<-data.frame(date,field=s$field,variable=s$variable,level=s$level,stamp=s$stamp,period=s$period,
        path=if(is.null(path))NA_character_ else path,index=if(file.exists(index))index else NA_character_,
        md5=if(is.null(path))NA_character_ else unname(tools::md5sum(path)),
        index_md5=if(file.exists(index))unname(tools::md5sum(index)) else NA_character_,state,note)
    }
    message("PWAT overlay inputs verified: ",date)
  }
  list(inputs=do.call(rbind,rows),requests=requests,bytes=bytes)
}

weather_overlay_decode <- function(inputs,reference_path,geometry) {
  reference<-weather_core_grid(reference_path);template<-terra::rast(reference_path)
  x<-terra::xFromCol(template,seq_len(terra::ncol(template)));x<-ifelse(x<120,x+360,x)
  cell<-terra::cellFromRowCol(template,match(geometry$y,reference$latitude),match(geometry$x,x))
  values<-lapply(seq_len(nrow(inputs)),function(i) {
    row<-inputs[i,]
    if(is.na(row$path))return(rep(NA_real_,nrow(geometry)))
    r<-terra::rast(row$path);grid<-weather_moisture_grid(row$path,reference)
    if(!identical(grid$section,reference$section)||!terra::compareGeom(template,r,stopOnError=FALSE)||terra::nlyr(r)!=1)stop("Overlay grid mismatch.")
    info<-terra::describe(row$path,print=FALSE)
    unit<-if(row$variable%in%c("UGRD","VGRD"))"[m/s]" else "[Pa]"
    time<-if(row$period=="day")as.POSIXct(paste(row$date,"21:00:00"),tz="UTC") else as.POSIXct(strptime(row$stamp,"%Y%m%d%H",tz="UTC"))
    expected<-c(paste0("GRIB_ELEMENT=",row$variable),paste0("GRIB_UNIT=",unit),paste0("GRIB_VALID_TIME=",sprintf("%.0f",as.numeric(time))))
    if(row$level=="850 mb")expected<-c(expected,"GRIB_SHORT_NAME=85000-ISBL")
    if(row$level=="surface")expected<-c(expected,"GRIB_SHORT_NAME=0-SFC")
    if(!all(vapply(expected,function(z)any(grepl(z,info,fixed=TRUE)),logical(1))))stop("Overlay variable, level, units or timestamp mismatch.")
    value<-as.numeric(terra::values(r,mat=FALSE))[cell]
    if(any(!is.finite(value))||any(if(unit=="[Pa]")value<10000|value>120000 else abs(value)>250))stop("Invalid overlay values.")
    value
  })
  names(values)<-inputs$field
  list(mslp=values$mslp,u850=values$u850,v850=values$v850,surface=values$surface,
    wind_mask=weather_moisture_wind_mask(do.call(cbind,values[paste0("surface",sprintf("%02d",seq(0,21,3)))]),850))
}

weather_overlay_average <- function(daily,days) {
  if(length(daily)!=days||!days%in%c(1L,7L,30L))stop("Complete overlay period required.")
  mean_field<-function(name,optional=FALSE) {
    m<-do.call(cbind,lapply(daily,`[[`,name))
    if(!optional&&any(!is.finite(m)))stop("Incomplete required overlay field.")
    rowMeans(m) # NA is retained: never form a partial mean.
  }
  list(mslp=mean_field("mslp"),u850=mean_field("u850"),v850=mean_field("v850"),
    surface=mean_field("surface",TRUE),wind_mask=Reduce(`&`,lapply(daily,`[[`,"wind_mask")))
}

weather_overlay_layers <- function(data,overlay,days) {
  data$height_dm<-data$pressure_hpa<-overlay$mslp/100;data$surface_hpa<-overlay$surface/100
  labels<-weather_contour_labels(data,breaks=seq(880,1080,4))
  centers<-weather_pressure_centers(data)
  centers<-centers[centers$x>124&centers$x<296&centers$y>12&centers$y<68,]
  for(i in seq_len(nrow(centers)))labels<-labels[((labels$x-centers$x[i])/3)^2+((labels$y-centers$y[i]-.5)/2)^2>1,]
  arrows<-data[overlay$wind_mask & match(data$x,sort(unique(data$x)))%%8==0 & match(data$y,sort(unique(data$y)))%%8==0,]
  at<-which(overlay$wind_mask & match(data$x,sort(unique(data$x)))%%8==0 & match(data$y,sort(unique(data$y)))%%8==0)
  arrows$u<-overlay$u850[at];arrows$v<-overlay$v850[at]
  arrows<-arrows[sqrt(arrows$u^2+arrows$v^2)>=2,]
  arrows$xend<-arrows$x+.12*arrows$u/cos(arrows$y*pi/180);arrows$yend<-arrows$y+.12*arrows$v
  list(ggplot2::geom_contour(data=data,ggplot2::aes(z=height_dm),breaks=seq(880,1080,4),colour="#303934",linewidth=.28),
    ggplot2::geom_label(data=labels,ggplot2::aes(label=label),size=2.4,linewidth=0,fill=scales::alpha("white",.65),label.padding=grid::unit(.04,"lines")),
    ggplot2::geom_segment(data=arrows,ggplot2::aes(xend=xend,yend=yend),colour="#163b56",linewidth=.28,arrow=grid::arrow(length=grid::unit(1,"mm"))),
    ggplot2::geom_label(data=centers,ggplot2::aes(label=type,colour=type),size=5,fontface="bold",linewidth=0,fill=scales::alpha("white",.75)),
    ggplot2::geom_label(data=centers,ggplot2::aes(y=y+1.5,label=round(pressure_hpa),colour=type),size=2.8,linewidth=0,fill=scales::alpha("white",.75)),
    ggplot2::scale_colour_manual(values=c(H="#174ea6",L="#b3261e"),guide="none"),
    ggplot2::annotate("segment",x=127,y=13,xend=127+.12*(20/1.943844)/cos(13*pi/180),yend=13,colour="#163b56",arrow=grid::arrow(length=grid::unit(1,"mm"))),
    ggplot2::annotate("label",x=145,y=13,label="20 knots",size=2.8,linewidth=0),
    ggplot2::labs(title=paste(if(days==1)"Daily mean" else paste0(days,"-day mean"),"PWAT, sea-level pressure and 850-mb flow"),
      caption=paste("NOAA CPC CORe | Pressure contours: 4 hPa | Arrows: mean 850-mb wind, not IVT or surface wind",
        paste0("Winds require all ",days*8," surface-pressure samples above 850 hPa. H/L: mean pressure centers, not tracked storms."),
        "Sea-level pressure over high terrain requires caution. Climate Science Applications Program - University of Arizona",sep="\n")))
}

run_weather_period_moisture_overlays <- function(download_missing=FALSE,output_dir="data/diagnostics/weather-period-means-pilot") {
  started<-proc.time()[["elapsed"]]
  periods<-read.csv(file.path(output_dir,"period-summary.csv"))
  source<-readRDS(file.path(output_dir,"30day","mean-native-grid.rds"))
  fetched<-weather_overlay_inputs(as.Date(source$dates),download_missing)
  write.csv(fetched$inputs,file.path(output_dir,"overlay-inputs.csv"),row.names=FALSE)
  reports<-list();daily<-NULL
  for(days in periods$days) {
    directory<-file.path(output_dir,paste0(days,"day"));native<-file.path(directory,"mean-native-grid.rds")
    base<-readRDS(native);selected<-fetched$inputs[fetched$inputs$date%in%base$dates,]
    signature<-digest::digest(list(source=selected[,c("date","field","md5","index_md5")],native=unname(tools::md5sum(native)),
      functions=lapply(list(weather_overlay_decode,weather_overlay_average,weather_overlay_layers,weather_pressure_centers,
        weather_moisture_wind_mask,weather_moisture_grid,weather_core_grid,weather_mean_plot),body)),algo="sha256")
    path<-file.path(directory,paste0("pwat-overlay-",days,"day.png"));marker<-paste0(path,".rds")
    old<-if(file.exists(marker))readRDS(marker) else NULL
    reused<-is.list(old)&&identical(old$signature,signature)&&file.exists(path)&&identical(old$md5,unname(tools::md5sum(path)))
    if(!reused) {
      if(is.null(daily))daily<-lapply(split(fetched$inputs,fetched$inputs$date),weather_overlay_decode,
        reference_path=source$inputs$path[source$inputs$field=="height500"][1],geometry=source$cells[,c("x","y","xmin","xmax","ymin","ymax")])
      overlay<-weather_overlay_average(daily[base$dates],days)
      weather_mean_plot(base$cells,as.Date(min(base$dates)),as.Date(max(base$dates)),directory,days=days,moisture_overlay=overlay)
      saveRDS(list(signature=signature,md5=unname(tools::md5sum(path)),wind_cells=sum(overlay$wind_mask)),marker)
    }
    reports[[length(reports)+1L]]<-data.frame(days,reused,wind_cells=readRDS(marker)$wind_cells)
    message("PWAT overlays ",days," day(s): ",if(reused)"REUSED" else "BUILT")
  }
  report<-do.call(rbind,reports);write.csv(report,file.path(output_dir,"overlay-periods.csv"),row.names=FALSE)
  summary<-data.frame(maps=3,built=sum(!report$reused),reused=sum(report$reused),requests=fetched$requests,bytes=fetched$bytes,seconds=proc.time()[["elapsed"]]-started)
  write.csv(summary,file.path(output_dir,"overlay-summary.csv"),row.names=FALSE)
  weather_period_viewer(periods,output_dir,moisture_overlays=TRUE)
  print(summary,row.names=FALSE);invisible(summary)
}
