# Isolated seven-day CORe means. No daily publisher or site integration.
weather_mean_roots <- function() c("data/processed/weather-circulation/daily",
  "data/diagnostics/weather-period-inputs","data/diagnostics/weather-period-overlay-inputs","data/diagnostics/weather-moisture-missing-pressure-test",
  "data/diagnostics/weather-seven-day-inputs","data/diagnostics/weather-circulation-explorer-cache",
  "data/diagnostics/weather-circulation-recent-test","data/diagnostics/weather-circulation-pilot",
  "data/diagnostics/weather-moisture-pilot")

weather_mean_record <- function(lines,date,field) {
  parts<-strsplit(lines[nzchar(trimws(lines))],":",fixed=TRUE)
  if(!length(parts)||any(lengths(parts)<6L))stop("Malformed cached CORe index.")
  offset<-suppressWarnings(as.numeric(vapply(parts,`[`,character(1),2)))
  if(any(!is.finite(offset))||any(offset<0)||any(offset!=floor(offset))||any(diff(offset)<=0))stop("Invalid index offsets.")
  if(!field%in%c("height500","pwat","u250","v250"))stop("Unsupported selected field.")
  variable<-switch(field,height500="HGT",pwat="PWAT",u250="UGRD",v250="VGRD")
  level<-switch(field,height500="500 mb",pwat="atmos col",u250="250 mb",v250="250 mb")
  found<-which(vapply(parts,`[`,character(1),4)==variable & vapply(parts,`[`,character(1),5)==level)
  if(length(found)!=1L||found==length(parts))stop("Missing or ambiguous daily field: ",field)
  row<-parts[[found]]
  if(row[3]!=paste0("d=",format(as.Date(date),"%Y%m%d"),"00")||
      row[6]!="8@3 hour ave(anl),missing=0")stop("Require the exact date and eight complete UTC samples.")
  start<-offset[found];end<-offset[found+1L]-1
  if(end<start||end-start+1>1e6)stop("Unbounded selected field.")
  list(start=start,end=end)
}

weather_mean_cached_field <- function(date,field,roots) {
  stamp<-format(as.Date(date),"%Y%m%d")
  for(root in roots) {
    directory<-file.path(root,as.character(date))
    path<-file.path(directory,if(field!="pwat")paste0(field,".grb") else paste0("day-flx-",stamp,"-PWAT-atmos_col.grb"))
    index<-file.path(directory,if(field!="pwat")"source.idx" else paste0("day-flx-",stamp,".idx"))
    if(!all(file.exists(c(path,index))))next
    candidate<-tryCatch({
      record<-weather_mean_record(readLines(index,warn=FALSE),date,field)
      if(file.info(path)$size!=record$end-record$start+1)stop("Record size differs from index.")
      weather_core_check_response(readBin(path,"raw",n=file.info(path)$size),206L,
        sprintf("bytes %.0f-%.0f/%.0f",record$start,record$end,record$end+1),record$start,record$end)
      md5<-unname(tools::md5sum(path));expected<-NULL
      if(file.exists(paste0(path,".rds")))expected<-readRDS(paste0(path,".rds"))$md5
      if(is.null(expected)&&field!="pwat"&&file.exists(file.path(directory,"complete.rds"))) {
        files<-readRDS(file.path(directory,"complete.rds"))$files
        expected<-files$md5[basename(files$path)==paste0(field,".grb")]
      }
      if(length(expected)!=1L||!identical(md5,unname(expected)))stop("Unverified cached field checksum.")
      data.frame(date=as.character(date),field,path,index,md5,index_md5=unname(tools::md5sum(index)),stringsAsFactors=FALSE)
    },error=function(e)NULL)
    if(!is.null(candidate))return(candidate)
  }
  NULL
}

plan_weather_seven_day <- function(end_date,roots=weather_mean_roots()) {
  end_date<-as.Date(end_date)
  if(length(end_date)!=1L||is.na(end_date)||end_date>=as.Date(Sys.time(),tz="UTC"))stop("Choose a completed UTC end date.")
  rows<-list()
  for(date in as.character(seq(end_date-6,end_date,by="day")))for(field in c("height500","pwat")) {
    found<-weather_mean_cached_field(date,field,roots)
    if(is.null(found))found<-data.frame(date,field,path=NA_character_,index=NA_character_,md5=NA_character_,index_md5=NA_character_)
    found$ready<-!is.na(found$path);rows[[length(rows)+1L]]<-found
  }
  do.call(rbind,rows)
}

weather_mean_download_missing <- function(plan,directory="data/diagnostics/weather-seven-day-inputs",max_dates=4L) {
  missing<-plan[!plan$ready,,drop=FALSE]
  if(length(unique(missing$date))>max_dates)stop("Missing-date cap exceeded; transfer existing VM caches or choose another week.")
  bytes<-requests<-0L
  get<-function(url,start=NULL,end=NULL) {
    if(requests>=16L||bytes>=8e6)stop("Selected-field request/byte budget exceeded.")
    req<-weather_core_request(url)
    if(!is.null(start))req<-httr2::req_headers(req,Range=sprintf("bytes=%.0f-%.0f",start,end),`Accept-Encoding`="identity")
    requests<<-requests+1L;response<-httr2::req_perform(req);body<-httr2::resp_body_raw(response)
    if(is.null(start)){if(httr2::resp_status(response)!=200L)stop("Index unavailable.")}else
      weather_core_check_response(body,httr2::resp_status(response),httr2::resp_header(response,"Content-Range"),start,end)
    bytes<<-bytes+length(body);if(bytes>8e6)stop("Selected-field byte budget exceeded.")
    attributes(body)<-NULL;body
  }
  for(i in seq_len(nrow(missing))) {
    date<-as.Date(missing$date[i]);field<-missing$field[i];stamp<-format(date,"%Y%m%d")
    target<-file.path(directory,as.character(date));dir.create(target,recursive=TRUE,showWarnings=FALSE)
    type<-if(field=="height500")"pgb" else "flx"
    base<-paste0("https://storage.googleapis.com/noaa-nws-ncep-core/grib/day/",type,"/",format(date,"%Y/%m/"),type,".",stamp)
    index<-get(paste0(base,".idx"))
    record<-weather_mean_record(strsplit(rawToChar(index),"\n",fixed=TRUE)[[1]],date,field)
    body<-get(paste0(base,".grb"),record$start,record$end)
    path<-file.path(target,if(field=="height500")"height500.grb" else paste0("day-flx-",stamp,"-PWAT-atmos_col.grb"))
    writeBin(index,file.path(target,if(field=="height500")"source.idx" else paste0("day-flx-",stamp,".idx")))
    writeBin(body,path);saveRDS(list(md5=unname(tools::md5sum(path)),source=base),paste0(path,".rds"))
    message("Cached selected CORe field: ",date," ",field)
  }
  list(requests=requests,bytes=bytes)
}

weather_mean_complete_average <- function(values) {
  if(!is.matrix(values)||ncol(values)!=7L||any(!is.finite(values)))stop("Seven finite daily values per cell are required; no partial means or infilling.")
  rowMeans(values)
}

weather_mean_decode <- function(plan) {
  if(nrow(plan)!=14L||!all(plan$ready)||anyDuplicated(plan[c("date","field")]))stop("Seven dates and both fields are required.")
  dates<-sort(unique(as.Date(plan$date)))
  if(length(dates)!=7L||any(diff(dates)!=1))stop("Seven consecutive calendar dates required.")
  template<-grid<-NULL;data<-list(height500=list(),pwat=list())
  for(i in seq_len(nrow(plan))) {
    row<-plan[i,];info<-terra::describe(row$path,print=FALSE)
    required<-if(row$field=="height500")c("GRIB_ELEMENT=HGT","GRIB_UNIT=[gpm]","GRIB_SHORT_NAME=50000-ISBL") else c("GRIB_ELEMENT=PWAT","GRIB_UNIT=[kg/(m^2)]")
    valid_time<-as.numeric(as.POSIXct(paste(row$date,"21:00:00"),tz="UTC"))
    required<-c(required,paste0("GRIB_VALID_TIME=",sprintf("%.0f",valid_time)))
    if(!all(vapply(required,function(x)any(grepl(x,info,fixed=TRUE)),logical(1))))stop("Wrong field identity, units or UTC valid time.")
    r<-terra::rast(row$path)
    if(terra::nlyr(r)!=1L)stop("Expected one selected GRIB layer.")
    if(is.null(grid)){grid<-weather_core_grid(row$path);template<-r}
    else {
      check<-weather_moisture_grid(row$path,grid)
      if(!identical(check$section,grid$section)||!terra::compareGeom(template,r,stopOnError=FALSE))stop("Daily grids do not match; no resampling permitted.")
    }
    x<-terra::xyFromCell(template,seq_len(terra::ncell(template)))[,1]
    x<-ifelse(x<120,x+360,x);y<-rep(grid$latitude,each=terra::ncol(template))
    keep<-x>=120&x<=300&y>=10&y<=70
    values<-as.numeric(terra::values(r,mat=FALSE))[keep]
    if(any(!is.finite(values))||any(if(row$field=="pwat")values<0|values>150 else values<3000|values>7000))stop("Invalid source values in pilot domain.")
    data[[row$field]][[row$date]]<-values
  }
  edges<-c(90,(head(grid$latitude,-1)+tail(grid$latitude,-1))/2,-90)
  cells<-data.frame(x=x[keep],y=y[keep],xmin=x[keep]-terra::res(template)[1]/2,xmax=x[keep]+terra::res(template)[1]/2,
    ymin=rep(tail(edges,-1),each=terra::ncol(template))[keep],ymax=rep(head(edges,-1),each=terra::ncol(template))[keep])
  cells$height_dm<-weather_mean_complete_average(do.call(cbind,data$height500[as.character(dates)]))/10
  cells$pwat_inches<-weather_mean_complete_average(do.call(cbind,data$pwat[as.character(dates)]))/25.4
  cells
}

weather_mean_plot <- function(data,start,end,directory,days=7L,include_jet=FALSE,moisture_overlay=NULL) {
  stopifnot(days%in%c(1L,7L,30L),as.integer(as.Date(end)-as.Date(start))+1L==days)
  prefix<-if(days==1L)"Daily mean" else paste0(days,"-day mean")
  world<-ggplot2::map_data("world");world$x<-ifelse(world$long<120,world$long+360,world$long)
  world$piece<-cumsum(c(TRUE,diff(world$group)!=0|abs(diff(world$x))>180))
  states<-ggplot2::map_data("state");states$x<-states$long+360
  sw<-states[states$region%in%c("arizona","new mexico"),]
  subtitle<-paste(format(as.Date(start),"%b %d, %Y"),"to",format(as.Date(end),"%b %d, %Y"),"UTC |",days,"complete daily mean(s)")
  base<-function(p)p+
    ggplot2::geom_path(data=world,ggplot2::aes(x,lat,group=piece),inherit.aes=FALSE,linewidth=.3,colour="#39464b")+
    ggplot2::geom_path(data=states,ggplot2::aes(x,lat,group=group),inherit.aes=FALSE,linewidth=.18,colour="#465459",alpha=.65)+
    ggplot2::geom_path(data=sw,ggplot2::aes(x,lat,group=group),inherit.aes=FALSE,linewidth=1.05,colour="white")+
    ggplot2::geom_path(data=sw,ggplot2::aes(x,lat,group=group),inherit.aes=FALSE,linewidth=.6,colour="#843b86")+
    ggplot2::coord_quickmap(xlim=c(120,300),ylim=c(10,70),expand=FALSE)+
    ggplot2::scale_x_continuous(breaks=seq(120,300,30),labels=c("120E","150E","180","150W","120W","90W","60W"))+
    ggplot2::labs(x=NULL,y=NULL,subtitle=subtitle,caption=paste("Data source: NOAA CPC CORe | Ensemble mean reanalysis",
      paste0("Equal-weight mean of ",days," UTC day(s); each day has eight samples at 00-21 UTC"),
      "Climate Science Applications Program - University of Arizona",sep="\n"))+
    ggplot2::theme_minimal(base_size=11)+ggplot2::theme(plot.title=ggplot2::element_text(face="bold"),
      legend.position="bottom",legend.title.position="top",panel.grid.minor=ggplot2::element_blank())
  labels<-weather_contour_labels(data)
  height<-base(ggplot2::ggplot(data,ggplot2::aes(x,y))+
    ggplot2::geom_rect(ggplot2::aes(xmin=xmin,xmax=xmax,ymin=ymin,ymax=ymax,fill=height_dm),colour=NA)+
    ggplot2::geom_contour(ggplot2::aes(z=height_dm),breaks=seq(420,630,6),colour="#263238",linewidth=.3)+
    ggplot2::geom_contour(ggplot2::aes(z=height_dm),breaks=c(588,594),colour="#263238",linewidth=.48)+
    ggplot2::geom_contour(ggplot2::aes(z=height_dm),breaks=seq(420,630,30),colour="#263238",linewidth=.65)+
    ggplot2::geom_label(data=labels,ggplot2::aes(label=label),size=2.6,fill=scales::alpha("white",.8),linewidth=0,label.padding=grid::unit(.06,"lines"))+
    ggplot2::scale_fill_gradientn(colours=c("#24496e","#417bb2","#93bdd9","#d3e6eb","#f5f2df","#f4d487","#edb557","#e89436","#d87526","#bb571e","#913c18"),
      values=scales::rescale(c(480,510,540,558,570,582,588,594,600,606,612),from=c(480,612)),limits=c(480,612),
      breaks=c(480,510,540,570,582,588,594,600,606,612),oob=scales::squish,name="Mean 500-mb height (dam)",
      guide=ggplot2::guide_colourbar(barwidth=grid::unit(20,"cm")))+
    ggplot2::labs(title=paste(prefix,"500-mb heights (6-dam contours)")))
  pwat<-base(ggplot2::ggplot(data,ggplot2::aes(x,y))+
    ggplot2::geom_rect(ggplot2::aes(xmin=xmin,xmax=xmax,ymin=ymin,ymax=ymax,fill=pwat_inches),colour=NA)+
    ggplot2::scale_fill_gradientn(colours=c("#776a5a","#a57c50","#c68a42","#edb86a","#f8edb2","#d8efc1","#8dd4ad","#4daead","#4383bc","#6963b5","#754594","#46185f"),
      values=scales::rescale(c(0,.1,.25,.5,.75,1,1.25,1.5,1.75,2,2.5,3),from=c(0,3)),limits=c(0,3),oob=scales::squish,
      breaks=c(0,.25,.5,.75,1,1.5,2,2.5,3),labels=c("0","0.25","0.5","0.75","1","1.5","2","2.5","3+"),name="Mean precipitable water (inches)",
      guide=ggplot2::guide_colourbar(barwidth=grid::unit(20,"cm")))+
    ggplot2::labs(title=paste(prefix,"precipitable water")))
  paths<-c(height500=file.path(directory,paste0("height500-",days,"day.png")),pwat=file.path(directory,paste0("pwat-",days,"day.png")))
  if(!is.null(moisture_overlay)) {
    pwat<-pwat+weather_overlay_layers(data,moisture_overlay,days)
    paths[["pwat"]]<-file.path(directory,paste0("pwat-overlay-",days,"day.png"))
  } else ggplot2::ggsave(paths[[1]],height,width=12,height=6.8,dpi=160,bg="white")
  ggplot2::ggsave(paths[[2]],pwat,width=12,height=6.8,dpi=160,bg="white")
  if(include_jet) {
    if(!all(c("u250","v250")%in%names(data)))stop("Mean wind components are required for jet maps.")
    flow<-weather_streamlines(data)
    arrows<-do.call(rbind,lapply(split(flow,flow$group),function(line){
      i<-floor(nrow(line)/2);data.frame(x=line$x[i],y=line$y[i],xend=line$x[i+2],yend=line$y[i+2])
    }))
    if(is.null(arrows))arrows<-data.frame(x=numeric(),y=numeric(),xend=numeric(),yend=numeric())
    labels<-c("<40","40-60","60-80","80-100","100-120","120-140","140-160","160-180","180-200","200+")
    data$wind_band<-cut(sqrt(data$u250^2+data$v250^2)*1.943844,c(0,40,60,80,100,120,140,160,180,200,Inf),right=FALSE,labels=labels)
    jet<-base(ggplot2::ggplot(data,ggplot2::aes(x,y))+
      ggplot2::geom_rect(ggplot2::aes(xmin=xmin,xmax=xmax,ymin=ymin,ymax=ymax,fill=wind_band),colour=NA,show.legend=TRUE)+
      ggplot2::geom_path(data=flow,ggplot2::aes(group=group),linewidth=.24,colour="#263238",alpha=.8)+
      ggplot2::geom_segment(data=arrows,ggplot2::aes(xend=xend,yend=yend),arrow=grid::arrow(length=grid::unit(1.2,"mm")),linewidth=.25)+
      ggplot2::scale_fill_manual(name="Speed of mean 250-mb wind components (knots)",drop=FALSE,
        values=setNames(c("#f5f8fa","#d3eef1","#8bd1dd","#3ca5ba","#387f92","#74ad74","#dad76a","#f2ad4e","#dd6541","#9c3564"),labels),
        guide=ggplot2::guide_legend(nrow=1))+
      ggplot2::labs(title=paste(prefix,"250-mb jet and flow")))
    paths<-c(paths,jet250=file.path(directory,paste0("jet250-",days,"day.png")))
    ggplot2::ggsave(paths[["jet250"]],jet,width=12,height=6.8,dpi=160,bg="white")
  }
  paths
}

run_weather_seven_day_pilot <- function(end_date="2026-10-05",download_missing=FALSE,
    roots=weather_mean_roots(),output_dir="data/diagnostics/weather-seven-day-pilot") {
  started<-proc.time()[["elapsed"]];end_date<-as.Date(end_date);start<-end_date-6
  directory<-file.path(output_dir,paste0(start,"_to_",end_date));dir.create(directory,recursive=TRUE,showWarnings=FALSE)
  plan<-plan_weather_seven_day(end_date,roots)
  transfer<-list(requests=0L,bytes=0)
  if(any(!plan$ready)&&download_missing) {
    transfer<-weather_mean_download_missing(plan)
    plan<-plan_weather_seven_day(end_date,unique(c("data/diagnostics/weather-seven-day-inputs",roots)))
  }
  write.csv(plan,file.path(directory,"inputs.csv"),row.names=FALSE)
  if(any(!plan$ready))stop("Incomplete cached week: ",sum(!plan$ready)," missing/unverified fields. See ",file.path(directory,"inputs.csv"),". No partial maps built.")
  signature<-digest::digest(list(version=2,source=plan[,c("date","field","md5","index_md5")],
    renderer=body(weather_mean_plot),decode=body(weather_mean_decode),aggregate=body(weather_mean_complete_average),
    dependencies=lapply(list(weather_core_grid,weather_gaussian_latitudes,weather_moisture_grid,weather_contour_labels,weather_mean_record),body),
    R=R.version.string,packages=vapply(c("terra","ggplot2","maps","scales"),function(p)as.character(utils::packageVersion(p)),character(1))),algo="sha256")
  marker<-file.path(directory,"complete.rds");old<-if(file.exists(marker))tryCatch(readRDS(marker),error=function(e)NULL) else NULL
  paths<-file.path(directory,c("height500-7day.png","pwat-7day.png","mean-native-grid.rds"))
  reused<-is.list(old)&&identical(old$signature,signature)&&all(file.exists(paths))&&identical(unname(tools::md5sum(paths)),old$md5)
  decode_seconds<-render_seconds<-0
  if(!reused) {
    before<-proc.time()[["elapsed"]];data<-weather_mean_decode(plan);decode_seconds<-proc.time()[["elapsed"]]-before
    before<-proc.time()[["elapsed"]];weather_mean_plot(data,start,end_date,directory);render_seconds<-proc.time()[["elapsed"]]-before
    saveRDS(list(cells=data,dates=sort(unique(plan$date)),height_units="dam",pwat_units="inches",inputs=plan),paths[3])
    saveRDS(list(signature=signature,md5=unname(tools::md5sum(paths))),marker)
  }
  report<-data.frame(start=as.character(start),end=as.character(end_date),days=7L,fields=14L,maps=2L,reused,
    requests=transfer$requests,transferred_bytes=transfer$bytes,decode_seconds,render_seconds,
    elapsed_seconds=proc.time()[["elapsed"]]-started,output_mb=sum(file.info(paths)$size)/1024^2)
  write.csv(report,file.path(directory,"summary.csv"),row.names=FALSE)
  relative<-basename(directory)
  html<-paste0('<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Seven-day weather means</title>',
    '<style>body{font:16px system-ui;color:#253941;max-width:1250px;margin:2rem auto;padding:0 1rem;background:#f4f7f8}img{width:100%;background:white;border:1px solid #d5dfe3}button{padding:.6rem;margin:.4rem;cursor:pointer}button[aria-selected="true"]{background:#e7f0f5;font-weight:bold}</style></head><body>',
    '<h1>Seven-day weather means</h1><p>',format(start,"%b %d, %Y"),' to ',format(end_date,"%b %d, %Y"),' UTC · Seven complete days · Local pilot</p>',
    '<p>Absolute mean conditions, with the same scales as the daily maps. Height contours show persistent circulation context; PWAT is column moisture, not rainfall or moisture transport. Averaging can hide short-lived events. No site publication or daily workflow changes.</p>',
    '<div role="tablist" aria-label="Weather mean map"><button role="tab" aria-selected="true" data-image="height500-7day.png">500-mb heights</button><button role="tab" aria-selected="false" data-image="pwat-7day.png">Precipitable water</button></div>',
    '<img id="map" alt="Seven-day mean 500-mb heights" src="',relative,'/height500-7day.png"><p><a id="full" href="',relative,'/height500-7day.png" target="_blank">Open full-resolution map</a> · <a href="',relative,'/summary.csv">Run summary</a> · <a href="',relative,'/inputs.csv">Source inventory</a></p>',
    '<script>document.querySelectorAll("[data-image]").forEach(b=>b.onclick=()=>{document.querySelectorAll("[data-image]").forEach(t=>t.setAttribute("aria-selected",String(t===b)));const p="',relative,'/"+b.dataset.image;document.getElementById("map").src=p;document.getElementById("map").alt="Seven-day mean "+b.textContent;document.getElementById("full").href=p;});</script></body></html>')
  writeLines(html,file.path(output_dir,"index.html"),useBytes=TRUE)
  message("Seven-day weather pilot: ",if(reused)"REUSED" else "BUILT","; 7/7 days; ",transfer$requests," requests. No publication.")
  report
}
