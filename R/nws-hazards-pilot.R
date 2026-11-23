# Isolated, retrospective IEM VTEC WWA assessment. No site or daily-runner writes.
nws_hazards_cases <- function() {
  latest<-max(as.Date(vapply(jsonlite::read_json("site/daily-explorer/daily-data.json")$days,`[[`,character(1),"date")))
  data.frame(id=c("recent","quiet","monsoon","winter"),
    label=c("Recent Explorer dates","Spring comparison","Monsoon comparison","Winter comparison"),
    start=c(as.character(latest-29),"2024-05-01","2024-07-01","2023-02-01"),
    end=c(as.character(latest+1),"2024-05-31","2024-07-31","2023-03-03"))
}

nws_hazards_request <- function(start,end=NULL,at=NULL,simple=FALSE,refresh=FALSE,
    cache_dir="data/raw/nws-hazards/az-nm") {
  params<-list(accept="shapefile",location_group="states",states="AZ,NM",
    addsvs="true",simple=tolower(as.character(simple)),limit0="false",limit1="false",limitps="false")
  if(is.null(at)) {
    params$timeopt<-1L;params$sts<-paste0(start,"T00:00Z");params$ets<-paste0(end,"T00:00Z")
  } else {params$timeopt<-2L;params$at<-paste0(at,"T00:00Z")}
  key<-digest::digest(params,algo="sha256");dir.create(cache_dir,recursive=TRUE,showWarnings=FALSE)
  zip<-file.path(cache_dir,paste0(key,".zip"));meta_path<-paste0(zip,".rds")
  meta<-if(file.exists(meta_path))tryCatch(readRDS(meta_path),error=function(e)NULL)else NULL
  reused<-!refresh&&file.exists(zip)&&is.list(meta)&&identical(meta$md5,unname(tools::md5sum(zip)))
  started<-Sys.time()
  if(!reused) {
    message("NWS hazards: ",if(is.null(at))paste(start,"to",end)else paste("active at",at),"; all AZ/NM VTEC types.")
    request<-httr2::request("https://mesonet.agron.iastate.edu/cgi-bin/request/gis/watchwarn.py")
    request<-do.call(httr2::req_url_query,c(list(request),params))
    request<-httr2::req_timeout(httr2::req_user_agent(request,"SWClimateWatch-local-hazard-pilot"),120)
    tmp<-tempfile(tmpdir=cache_dir,fileext=".zip");on.exit(unlink(tmp),add=TRUE)
    httr2::req_perform(request,path=tmp)
    members<-utils::unzip(tmp,list=TRUE)$Name
    if(!any(grepl("[.]shp$",members)))stop("Archive returned no shapefile (possibly an empty result or source error); no zero coverage assumed.")
    if(!file.copy(tmp,zip,overwrite=TRUE))stop("Cannot cache hazard archive.")
    meta<-list(md5=unname(tools::md5sum(zip)),params=params,fetched_utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"))
    saveRDS(meta,meta_path)
  }
  members<-utils::unzip(zip,list=TRUE)$Name
  if(any(grepl("[/\\\\]",members))||any(!grepl("^[A-Za-z0-9_.-]+$",members)))stop("Unsafe archive filenames.")
  folder<-tempfile();dir.create(folder);on.exit(unlink(folder,recursive=TRUE),add=TRUE)
  utils::unzip(zip,exdir=folder)
  shape<-list.files(folder,pattern="[.]shp$",full.names=TRUE)
  if(length(shape)!=1L)stop("Expected one hazard shapefile.")
  x<-sf::read_sf(shape,quiet=TRUE)
  list(data=x,metrics=data.frame(request=if(is.null(at))"issued"else"carry-in",reused=reused,
    bytes=file.info(zip)$size,seconds=as.numeric(difftime(Sys.time(),started,units="secs")),rows=nrow(x)),meta=meta)
}

nws_hazards_time <- function(x,optional=FALSE) {
  x<-as.character(x);empty<-is.na(x)|!nzchar(x)
  result<-as.POSIXct(x,format="%Y%m%d%H%M",tz="UTC")
  if(any(is.na(result)&(!empty|!optional)))stop("Invalid hazard timestamp.")
  result
}

nws_hazards_tags <- function(x,i) {
  text<-function(name){if(!name%in%names(x))return(NULL);v<-x[[name]][i];if(length(v)!=1L||is.na(v))return(NULL);v<-trimws(as.character(v));if(!nzchar(v)||tolower(v)%in%c("none","null","na"))NULL else v}
  positive<-function(name){v<-suppressWarnings(as.numeric(text(name)));if(length(v)==1L&&is.finite(v)&&v>0)v else NULL}
  severity<-text("HV_SEV");if(identical(severity,"0"))severity<-NULL
  record<-text("HV_REC");if(identical(record,"OO"))record<-NULL
  gauge<-text("HV_NWSLI");if(identical(gauge,"00000"))gauge<-NULL
  emergency<-text("EMERGENC")
  values<-list(wind_mph=positive("WINDTAG"),hail_inches=positive("HAILTAG"),
    tornado=text("TORNTAG"),damage_threat=text("DAMAGTAG"),
    emergency_lifecycle=if(!is.null(emergency)&&tolower(emergency)%in%c("true","t","1","yes"))TRUE else NULL,
    flood_severity=severity,flood_cause=text("HV_CAUSE"),flood_record=record,gauge_id=gauge)
  Filter(Negate(is.null),values)
}

nws_hazards_normalize <- function(x,start,end) {
  required<-c("WFO","ISSUED","EXPIRED","INIT_ISS","PHENOM","GTYPE","SIG","ETN","STATUS","NWS_UGC","POLY_BEG","POLY_END","PROD_ID","VTEC_YR")
  if(!all(required%in%names(x)))stop("Hazard archive schema changed.")
  issued<-nws_hazards_time(x$ISSUED,TRUE);expires<-nws_hazards_time(x$EXPIRED)
  begin<-nws_hazards_time(x$POLY_BEG,TRUE);finish<-nws_hazards_time(x$POLY_END,TRUE)
  # The source can omit ISSUE for a followup storm polygon; its SQL uses
  # coalesce(issue, polygon_begin), so use that same documented fallback.
  missing_issue<-is.na(issued)&x$GTYPE=="P"
  issued[missing_issue]<-begin[missing_issue]
  if(anyNA(issued)||anyNA(x$VTEC_YR)||anyNA(x$ETN))stop("Hazard has no usable effective start or event identifier.")
  # Storm polygons carry explicit revision intervals; county rows carry resolved
  # archive issue/expiration intervals, not a complete message-by-message history.
  begin[is.na(begin)]<-issued[is.na(begin)];finish[is.na(finish)]<-expires[is.na(finish)]
  begin<-pmax(begin,issued);finish<-pmin(finish,expires)
  key<-paste(x$VTEC_YR,x$WFO,x$PHENOM,x$SIG,sprintf("%04d",x$ETN),sep="-")
  # Avoid drawing/counting the same event twice as both counties and polygons.
  polygon_events<-unique(key[x$GTYPE=="P"])
  keep<-finish>begin & begin<as.POSIXct(as.Date(end),tz="UTC") & finish>as.POSIXct(as.Date(start),tz="UTC") &
    (x$GTYPE=="P"|!key%in%polygon_events)
  x<-x[keep,];key<-key[keep];begin<-begin[keep];finish<-finish[keep]
  x<-sf::st_transform(x,4326)
  states<-sf::st_as_sf(maps::map("state",regions=c("arizona","new mexico"),fill=TRUE,plot=FALSE))
  states<-sf::st_transform(states,4326)
  # Use planar operations in a projected CRS for robust membership and display simplification.
  projected<-sf::st_make_valid(sf::st_transform(x,5070));state_projected<-sf::st_transform(states,5070)
  hits<-sf::st_intersects(projected,state_projected)
  membership<-lapply(seq_len(nrow(x)),function(i){
    if(x$GTYPE[i]=="C")return(substr(x$NWS_UGC[i],1,2))
    unname(c("AZ","NM")[hits[[i]]])
  })
  events<-list();geometries<-list();geometry_lookup<-new.env(parent=emptyenv());original_vertices<-display_vertices<-0L
  labels<-jsonlite::read_json("scripts/nws-hazards-assets/phenomena.json",simplifyVector=TRUE)
  sigs<-c(W="Warning",A="Watch",Y="Advisory",S="Statement",O="Outlook",N="Synopsis",F="Forecast")
  for(event in unique(key)) {
    ix<-which(key==event);r<-x[ix[1],];segments<-list()
    for(i in ix) {
      g<-sf::st_geometry(projected[i,]);mapped<-!sf::st_is_empty(g)
      gid<-NULL
      if(mapped) {
        raw_key<-digest::digest(g[[1]],algo="sha256")
        original_vertices<-original_vertices+nrow(sf::st_coordinates(g))
        if(exists(raw_key,geometry_lookup,inherits=FALSE)) {
          saved<-get(raw_key,geometry_lookup);gid<-saved$id
          display_vertices<-display_vertices+saved$vertices
        } else {
          display<-sf::st_transform(sf::st_simplify(g,dTolerance=150,preserveTopology=TRUE),4326)
          if(sf::st_is_empty(display))display<-sf::st_geometry(x[i,])
          vertices<-nrow(sf::st_coordinates(display));display_vertices<-display_vertices+vertices
          g<-display[[1]]
          type<-if(inherits(g,"MULTIPOLYGON"))"MultiPolygon"else if(inherits(g,"POLYGON"))"Polygon"else stop("Unsupported display geometry.")
          geo<-list(type=type,coordinates=unclass(g));gid<-digest::digest(geo,algo="sha256")
          geometries[[gid]]<-geo;assign(raw_key,list(id=gid,vertices=vertices),geometry_lookup)
        }
      }
      segment<-list(start=format(begin[i],"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),
        end=format(finish[i],"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),geometry=gid,
        states=unname(as.list(membership[[i]])),zone=if(is.na(x$NWS_UGC[i]))""else x$NWS_UGC[i],
        status=x$STATUS[i],product=if(is.na(x$PROD_ID[i]))""else x$PROD_ID[i],tags=nws_hazards_tags(x,i))
      segments[[length(segments)+1L]]<-segment
    }
    # Exact duplicate rows from carry-in and issued queries are removed earlier.
    title<-labels[[r$PHENOM]];if(is.null(title))title<-paste("Hazard",r$PHENOM)
    significance<-unname(sigs[r$SIG]);if(is.na(significance))significance<-r$SIG
    if(r$PHENOM=="FW"&&r$SIG=="A")title<-"Fire Weather"
    states_for_event<-sort(unique(unlist(lapply(segments,`[[`,"states"))))
    events[[length(events)+1L]]<-list(id=event,title=paste(title,significance),phenomenon=r$PHENOM,
      significance=r$SIG,wfo=r$WFO,year=as.integer(r$VTEC_YR),etn=as.integer(r$ETN),
      states=unname(as.list(states_for_event)),segments=unname(segments),
      geometry_type=if(any(x$GTYPE[ix]=="P"))"Storm polygon"else"County / forecast zone")
  }
  list(events=unname(events),geometries=geometries,original_vertices=original_vertices,
    display_vertices=display_vertices,rows=nrow(x))
}

build_nws_hazards_pilot <- function(cases=nws_hazards_cases(),refresh=FALSE,
    output_dir="data/diagnostics/nws-hazards-pilot",simple=FALSE) {
  source("R/storm-reports-pilot.R",local=TRUE)
  output_dir<-storm_reports_output_path(output_dir,"site/daily-explorer")
  if(anyDuplicated(cases$id)||any(!grepl("^[a-z0-9-]+$",cases$id))||
    any(as.Date(cases$end)<=as.Date(cases$start))||any(as.Date(cases$end)-as.Date(cases$start)>31))stop("Use unique pilot cases of 1–31 days.")
  dir.create(file.path(output_dir,"geometry"),recursive=TRUE,showWarnings=FALSE)
  dir.create(file.path(output_dir,"cases"),recursive=TRUE,showWarnings=FALSE)
  dir.create(file.path(output_dir,"bundles"),recursive=TRUE,showWarnings=FALSE)
  for(file in c("index.html","hazards.js","hazard-model.js","hazards.css"))
    file.copy(file.path("scripts/nws-hazards-assets",file),file.path(output_dir,file),overwrite=TRUE)
  for(file in c("leaflet.js","leaflet.css","leaflet-package-LICENSE"))
    file.copy(file.path("site/stations",file),file.path(output_dir,file),overwrite=TRUE)
  dir.create(file.path(output_dir,"images"),showWarnings=FALSE)
  file.copy(list.files(file.path(find.package("leaflet"),"htmlwidgets/lib/leaflet/images"),full.names=TRUE),file.path(output_dir,"images"),overwrite=TRUE)
  inventory<-workload<-windows<-list()
  for(i in seq_len(nrow(cases))) {
    case<-cases[i,];started<-Sys.time();message("Hazard pilot: ",case$label)
    issued<-nws_hazards_request(case$start,case$end,simple=simple,refresh=refresh)
    carry<-nws_hazards_request(case$start,at=case$start,simple=simple,refresh=refresh)
    x<-rbind(issued$data,carry$data)
    process_start<-Sys.time()
    cache_key<-digest::digest(list(issued$meta$md5,carry$meta$md5,case$start,case$end,
      cache_version=2L,
      normalize=body(nws_hazards_normalize),time=body(nws_hazards_time),tags=body(nws_hazards_tags),
      labels=unname(tools::md5sum("scripts/nws-hazards-assets/phenomena.json"))),algo="sha256")
    processed_dir<-"data/processed/nws-hazards-pilot";dir.create(processed_dir,recursive=TRUE,showWarnings=FALSE)
    processed_path<-file.path(processed_dir,paste0(cache_key,".rds"))
    result<-if(file.exists(processed_path))tryCatch(readRDS(processed_path),error=function(e)NULL)else NULL
    processed_reused<-is.list(result)&&identical(result$key,cache_key)&&
      identical(result$digest,digest::digest(result$data,algo="sha256"))
    if(processed_reused)result<-result$data else {
      # Deduplicate full attributes + geometry, not event IDs. Do this only when
      # source inputs changed; checksummed processed reuse skips the whole pass.
      attributes<-as.list(sf::st_drop_geometry(x));geometry<-sf::st_geometry(x)
      keys<-vapply(seq_len(nrow(x)),function(j)digest::digest(list(
        attributes=lapply(attributes,`[`,j),geometry=geometry[[j]]),algo="sha256"),character(1))
      x<-x[!duplicated(keys),]
      message("  ",nrow(x)," source rows; normalizing event intervals and display geometry…")
      result<-nws_hazards_normalize(x,case$start,case$end)
      result$input_rows<-nrow(x)
      saveRDS(list(key=cache_key,digest=digest::digest(result,algo="sha256"),data=result),processed_path)
    }
    if(processed_reused)message("  Verified processed cache reused.")
    process_seconds<-as.numeric(difftime(Sys.time(),process_start,units="secs"))
    geometry_sizes<-vapply(result$geometries,function(g)nchar(jsonlite::toJSON(g,auto_unbox=TRUE,digits=6,null="null"),type="bytes"),numeric(1))
    geometry_bytes<-sum(geometry_sizes)
    bundles<-list()
    for(prefix in unique(substr(names(result$geometries),1,1))) {
      bundle<-result$geometries[substr(names(result$geometries),1,1)==prefix]
      id<-digest::digest(bundle,algo="sha256");relative<-paste0("bundles/",id,".json")
      jsonlite::write_json(bundle,file.path(output_dir,relative),auto_unbox=TRUE,digits=6,null="null")
      bundles[[prefix]]<-relative
    }
    metadata<-list(schema_version=1L,id=case$id,start=case$start,end_exclusive=case$end,geometry_bundles=bundles,
      fetched_utc=c(issued$meta$fetched_utc,carry$meta$fetched_utc),events=result$events)
    path<-file.path(output_dir,"cases",paste0(case$id,".json"))
    jsonlite::write_json(metadata,path,auto_unbox=TRUE,digits=6,null="null")
    payload<-readBin(path,"raw",n=file.info(path)$size)
    # Measure terminal 1/7/30-day views and busiest daily/weekly/monthly windows.
    dates<-seq(as.Date(case$start),as.Date(case$end)-1,by="day")
    segments<-unlist(lapply(result$events,`[[`,"segments"),recursive=FALSE)
    event_index<-rep(seq_along(result$events),lengths(lapply(result$events,`[[`,"segments")))
    begins<-as.numeric(as.POSIXct(vapply(segments,`[[`,character(1),"start"),format="%Y-%m-%dT%H:%M:%SZ",tz="UTC"))
    ends<-as.numeric(as.POSIXct(vapply(segments,`[[`,character(1),"end"),format="%Y-%m-%dT%H:%M:%SZ",tz="UTC"))
    geometry_ids<-vapply(segments,function(s)if(is.null(s$geometry))NA_character_ else s$geometry,character(1))
    for(n in c(1L,7L,30L))for(day in as.character(dates)) {
      end<-as.numeric(as.POSIXct(as.Date(day)+1,tz="UTC"));start<-max(as.numeric(as.POSIXct(as.Date(case$start),tz="UTC")),end-n*86400)
      active<-begins<end&ends>start;ids<-unique(geometry_ids[active&!is.na(geometry_ids)])
      windows[[length(windows)+1L]]<-data.frame(case=case$id,date=day,days=n,events=length(unique(event_index[active])),segments=sum(active),
        geometries=length(ids),geometry_bytes=sum(geometry_sizes[ids]))
    }
    metrics<-rbind(issued$metrics,carry$metrics)
    workload[[i]]<-data.frame(case=case$id,start=case$start,end_exclusive=case$end,requests=sum(!metrics$reused),
      cached_requests=sum(metrics$reused),archive_bytes=sum(metrics$bytes),download_seconds=sum(metrics$seconds[!metrics$reused]),
      read_cache_seconds=sum(metrics$seconds[metrics$reused]),process_seconds=process_seconds,processed_reused=processed_reused,events=length(result$events),
      raw_rows=result$input_rows,display_segments=result$rows,unique_geometries=length(result$geometries),
      original_vertices=result$original_vertices,display_vertices=result$display_vertices,
      metadata_bytes=length(payload),metadata_gzip_bytes=length(memCompress(payload,"gzip")),geometry_bytes=geometry_bytes,
      total_seconds=as.numeric(difftime(Sys.time(),started,units="secs")))
    types<-sort(unique(vapply(result$events,`[[`,character(1),"title")))
    inventory[[i]]<-list(id=case$id,label=case$label,start=case$start,end_exclusive=case$end,events=length(result$events),
      types=unname(as.list(types)),path=paste0("cases/",case$id,".json"))
  }
  stats<-do.call(rbind,workload);view_stats<-do.call(rbind,windows)
  write.csv(stats,file.path(output_dir,"workload.csv"),row.names=FALSE)
  history<-file.path(output_dir,paste0("workload-",format(Sys.time(),"%Y%m%dT%H%M%S"),".csv"))
  write.csv(stats,history,row.names=FALSE)
  write.csv(view_stats,file.path(output_dir,"view-workload.csv"),row.names=FALSE)
  jsonlite::write_json(list(schema_version=1L,pilot=TRUE,cases=unname(inventory),workload=unname(lapply(seq_len(nrow(stats)),function(i)as.list(stats[i,])))),file.path(output_dir,"catalog.json"),auto_unbox=TRUE,pretty=TRUE,null="null")
  print(stats,row.names=FALSE);message("Local pilot ready: ",output_dir)
  invisible(list(summary=stats,views=view_stats,output_dir=output_dir))
}
