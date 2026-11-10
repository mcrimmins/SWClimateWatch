# Stable map endpoints and a complete publication catalog. Never fetches data or builds climate maps.
map_hotlink_escape <- function(x) {
  x<-gsub("&","&amp;",as.character(x),fixed=TRUE);x<-gsub("<","&lt;",x,fixed=TRUE)
  x<-gsub(">","&gt;",x,fixed=TRUE);gsub('"',"&quot;",x,fixed=TRUE)
}
map_hotlink_safe_path <- function(path) {
  is.character(path)&&length(path)==1L&&!is.na(path)&&
    grepl("^[A-Za-z0-9_./-]+$",path)&&!grepl("(^/|(^|/)\\.\\.?(/|$)|^[A-Za-z]:)",path)
}
map_hotlink_path <- function(root,path) {
  if(!map_hotlink_safe_path(path))stop("Unsafe map path: ",path)
  full<-normalizePath(file.path(root,path),winslash="/",mustWork=FALSE)
  base<-paste0(normalizePath(root,winslash="/",mustWork=TRUE),"/")
  inside<-if(.Platform$OS.type=="windows")startsWith(tolower(full),tolower(base)) else startsWith(full,base)
  if(!inside)stop("Map path escapes publication directory.")
  full
}
map_hotlink_png <- function(path) {
  file.exists(path)&&identical(readBin(path,"raw",n=8),as.raw(c(137,80,78,71,13,10,26,10)))
}
map_hotlink_base <- function(destination) {
  if(!is.character(destination)||length(destination)!=1L||
    !grepl("^s3://[^/]+/[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)+/$",destination))stop("Use an exact site S3 destination for map URLs.")
  sub("^s3://[^/]+/","https://cales.arizona.edu/",destination)
}
map_hotlink_rows <- function(root, products, metadata_dir="data/diagnostics") {
  rows<-list()
  add<-function(id,family,label,source="",alias="",date="",status="AVAILABLE",note="",page="") {
    if(nzchar(source)&&!map_hotlink_safe_path(source))stop("Invalid declared map source: ",source)
    if(nzchar(alias)&&(!map_hotlink_safe_path(alias)||!startsWith(alias,"maps/latest/")||!endsWith(alias,".png")))stop("Invalid stable map endpoint.")
    if(status=="AVAILABLE"&&!map_hotlink_png(map_hotlink_path(root,source)))stop("Published map missing or invalid: ",source)
    rows[[length(rows)+1L]]<<-data.frame(id=id,family=family,label=label,source=source,alias=alias,date=date,
      status=status,note=note,page=page,stringsAsFactors=FALSE)
  }
  grouped_path<-file.path(root,"assets/current-map-groups/manifest.json")
  if(!file.exists(grouped_path))stop("Stage grouped Current Maps before creating hotlinks.")
  grouped<-jsonlite::read_json(grouped_path,simplifyVector=TRUE)
  dates_path<-file.path(metadata_dir,"map-product-status.csv")
  dates<-if(file.exists(dates_path))read.csv(dates_path,stringsAsFactors=FALSE) else data.frame()
  for(i in seq_len(nrow(products))) {
    p<-products[i,];g<-grouped[grouped$product==p$id,,drop=FALSE]
    if(p$enabled&&nrow(g)!=1L)stop("Enabled product is not in the accepted grouped manifest: ",p$id)
    available<-p$enabled&&isTRUE(g$available[1])
    source<-paste0("maps/generated/",p$image);date<-""
    if(available) {
      hash<-unname(tools::md5sum(map_hotlink_path(root,source)))
      if(!identical(hash,g$md5[1L]))stop("Current map differs from accepted manifest: ",p$id)
      if(nrow(dates)&&all(c("id","image_md5","actual_data_date") %in% names(dates))) {
        d<-dates[dates$id==p$id & dates$image_md5==hash,,drop=FALSE]
        if(nrow(d)==1L&&!is.na(d$actual_data_date))date<-d$actual_data_date
      }
    }
    add(paste0("current/",p$id),paste("Current",p$section),p$label,
      if(available)source else "",paste0("maps/latest/current/",p$id,".png"),date,
      if(!p$enabled)"DISABLED" else if(available)"AVAILABLE" else "UNAVAILABLE",
      if(!available)"This product is not available in the accepted current publication; no older map is substituted." else "",
      if(nrow(g))paste0("pages/",g$page[1L]) else "")
  }
  snow_labels<-c(snow_swe="Snow water equivalent",snow_departure="SWE departure",snow_percent="SWE percent of median",snow_change="Seven-day SWE change")
  snow_files<-c(snow_swe="swe-observed.png",snow_departure="swe-departure.png",snow_percent="swe-percent-median.png",snow_change="swe-change-7day.png")
  snow_path<-file.path(metadata_dir,"snodas-current-site/publication.csv")
  snow_meta<-if(file.exists(snow_path))read.csv(snow_path,stringsAsFactors=FALSE) else data.frame()
  for(id in names(snow_labels)) {
    g<-grouped[grouped$product==id,,drop=FALSE];ok<-nrow(g)==1L&&isTRUE(g$available[1L]);date<-""
    source<-paste0("maps/generated/snodas/current/",snow_files[[id]])
    if(ok&&!identical(unname(tools::md5sum(map_hotlink_path(root,source))),g$md5[1L]))stop("Snow map differs from accepted publication.")
    md5field<-c(snow_swe="observed_md5",snow_departure="departure_md5",snow_percent="percent_md5",snow_change="change_md5")[[id]]
    if(ok&&nrow(snow_meta)==1L&&all(c("date",md5field) %in% names(snow_meta))&&identical(snow_meta[[md5field]],g$md5[1L]))date<-snow_meta$date
    add(paste0("snow/",id),"Current Snow",snow_labels[[id]],if(ok)source else "",paste0("maps/latest/snow/",snow_files[[id]]),date,
      if(ok)"AVAILABLE" else "UNAVAILABLE",if(!ok)"This comparison is not available for the accepted snow date." else "", "pages/snow-conditions.html")
  }
  monthly_page<-file.path(root,"pages/monthly-climate.html")
  if(!file.exists(monthly_page))stop("Rendered Monthly Climate page is missing.")
  doc<-xml2::read_html(monthly_page);node<-xml2::xml_find_first(doc,'//*[@data-monthly-end]')
  month<-xml2::xml_attr(node,"data-monthly-end")
  images<-xml2::xml_find_all(doc,'//img[@data-monthly-map]')
  ids<-xml2::xml_attr(images,"data-monthly-map")
  expected<-as.vector(outer(c("temperature","precipitation","spi"),c(1,3,6,12),paste,sep="-"))
  if(length(images)!=12L||!setequal(ids,expected))stop("Monthly hotlinks require all twelve accepted maps.")
  for(img in images) {
    id<-xml2::xml_attr(img,"data-monthly-map");src<-xml2::xml_attr(img,"src")
    if(!grepl("^\\.\\./maps/generated/prism/monthly/[0-9]{4}-[0-9]{2}-[a-f0-9]{16}/[a-z]+-[0-9]{2}month[.]png$",src))stop("Unsafe monthly source.")
    source<-sub("^../","",src);version<-basename(dirname(source))
    manifest<-jsonlite::read_json(file.path(root,dirname(source),"manifest.json"),simplifyVector=TRUE)
    p<-manifest$products[paste(manifest$products$family,manifest$products$duration,sep="-")==id,,drop=FALSE]
    if(nrow(p)!=1L||manifest$end_month!=month||!identical(unname(tools::md5sum(map_hotlink_path(root,source))),p$md5))stop("Monthly map/manifest mismatch.")
    label<-paste(p$duration,"month",switch(p$family,temperature="temperature ranking",precipitation="precipitation ranking",spi="SPI"))
    add(paste0("monthly/",id),"Monthly Climate",label,source,paste0("maps/latest/monthly/",p$file),month,
      page="pages/monthly-climate.html",note="Completed months; revision-aware monthly updates.")
  }
  # Historical pages already have stable year-specific paths. Catalog only maps
  # actually referenced by the published page, rather than every cached file.
  for(page in list.files(file.path(root,"pages/archive"),pattern="^wy[0-9]{4}[.]html$",full.names=TRUE)) {
    doc<-xml2::read_html(page)
    for(img in xml2::xml_find_all(doc,"//img")) {
      src<-xml2::xml_attr(img,"src")
      if(is.na(src)||!grepl("^../../maps/generated/(prism|snodas)/seasonal-archive/wy[0-9]{4}/[A-Za-z0-9_-]+[.]png$",src))next
      source<-substring(src,7L);id<-sub("^maps/generated/","archive/",sub("[.]png$","",source))
      label<-xml2::xml_attr(img,"alt");if(is.na(label)||!nzchar(label))label<-basename(source)
      add(id,"Historic seasons",label,source,date=toupper(sub("[.]html$","",basename(page))),page=paste0("pages/archive/",basename(page)))
    }
  }
  daily_path<-file.path(root,"daily-explorer/daily-data.json")
  daily<-if(file.exists(daily_path))jsonlite::read_json(daily_path) else NULL
  daily_fields<-c(pcpn_observed="Daily precipitation",maxt_observed="Daily maximum temperature",maxt_departure="Daily maximum temperature departure",
    mint_observed="Daily minimum temperature",mint_departure="Daily minimum temperature departure",tmean_observed="Daily mean temperature",tmean_departure="Daily mean temperature departure")
  latest<-list()
  if(isTRUE(daily$publication_mode))for(day in daily$days)for(field in names(day$images)) {
    if(!field %in% names(daily_fields)||!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$",day$date))stop("Unexpected Daily Explorer map/date.")
    image<-day$images[[field]]
    expected<-paste0("maps/",day$date,"-",gsub("_","-",field),".png")
    if(!identical(image,expected))stop("Daily Explorer image/date mismatch.")
    source<-paste0("daily-explorer/",image)
    add(paste("daily",day$date,field,sep="/"),"Daily Explorer dates",daily_fields[[field]],source,date=day$date,page="pages/daily-explorer.html")
    if(is.null(latest[[field]])||day$date>latest[[field]]$date)latest[[field]]<-list(source=source,date=day$date)
  }
  for(field in names(daily_fields)) {
    x<-latest[[field]];ok<-!is.null(x)
    add(paste0("daily/latest/",field),"Latest daily maps",daily_fields[[field]],if(ok)x$source else "",
      paste0("maps/latest/daily/",gsub("_","-",field),".png"),if(ok)x$date else "",if(ok)"AVAILABLE" else "UNAVAILABLE",
      if(ok)"Latest published PRISM day, which may lag today's date." else "No accepted daily map is available.","pages/daily-explorer.html")
  }
  weather_fields<-c(height500="500-mb heights",jet250="250-mb jet and flow",moisture="PWAT and low-level flow")
  manifest_path<-file.path(root,"daily-explorer/circulation-manifest.json");weather<-list()
  if(isTRUE(daily$circulation_enabled)&&file.exists(manifest_path)) {
    manifest<-jsonlite::read_json(manifest_path)
    for(day in manifest$days) {
      if(!identical(day$status,"available"))next
      for(field in names(weather_fields)) {
        image<-day$images[[field]];expected<-paste0("circulation/maps/",day$date,"-",field,".png")
        if(!identical(image,expected))stop("Weather map/date mismatch.")
        source<-paste0("daily-explorer/",image)
        add(paste("weather",day$date,field,sep="/"),"Weather map dates",weather_fields[[field]],source,date=day$date,page="pages/daily-explorer.html")
        if(is.null(weather[[field]])||day$date>weather[[field]]$date)weather[[field]]<-list(source=source,date=day$date)
      }
    }
  }
  for(field in names(weather_fields)) {
    x<-weather[[field]];ok<-!is.null(x)
    add(paste0("weather/latest/",field),"Latest weather maps",weather_fields[[field]],if(ok)x$source else "",
      paste0("maps/latest/weather/",field,".png"),if(ok)x$date else "",if(ok)"AVAILABLE" else "UNAVAILABLE",
      if(ok)"CORe UTC daily mean; date is independent of PRISM." else "No verified weather map is available in this publication. No older map is substituted.","pages/daily-explorer.html")
  }
  # The weekly temperature map belongs to the current selected synopsis evidence.
  synopsis<-file.path(root,"pages/synopsis.html");weekly<-NULL
  if(file.exists(synopsis)) {
    doc<-xml2::read_html(synopsis)
    links<-unique(xml2::xml_attr(xml2::xml_find_all(doc,'//a[contains(@href,"synopsis-evidence/")]'),"href"))
    for(link in links) {
      rel<-sub("^.*synopsis-evidence/","synopsis-evidence/",link)
      if(!map_hotlink_safe_path(rel)||!endsWith(rel,".html"))next
      proof_path<-map_hotlink_path(root,rel);if(!file.exists(proof_path))stop("Synopsis evidence page missing.")
      proof<-xml2::read_html(proof_path)
      if(length(xml2::xml_find_all(proof,'//img[@src="temperature-7day.png"]'))) {
        weekly<-list(source=paste0(dirname(rel),"/temperature-7day.png"),date=substr(basename(dirname(rel)),1L,10L));break
      }
    }
  }
  add("synopsis/temperature-7day","Synopsis supporting maps","Seven-day mean temperature departure",
    if(!is.null(weekly))weekly$source else "","maps/latest/synopsis/temperature-7day.png",if(!is.null(weekly))weekly$date else "",
    if(!is.null(weekly))"AVAILABLE" else "UNAVAILABLE","Only available when the weekly temperature map is in the selected synopsis evidence.","pages/synopsis.html")
  result<-do.call(rbind,rows)
  result<-result[!duplicated(result$id),,drop=FALSE]
  if(anyDuplicated(result$alias[nzchar(result$alias)]))stop("Duplicate stable map endpoint.")
  result[order(result$family,result$id),,drop=FALSE]
}

map_hotlink_install <- function(source,target) {
  if(file.exists(target)&&identical(unname(tools::md5sum(source)),unname(tools::md5sum(target))))return(invisible(FALSE))
  dir.create(dirname(target),recursive=TRUE,showWarnings=FALSE)
  temp<-tempfile(tmpdir=dirname(target));on.exit(unlink(temp),add=TRUE)
  if(!file.copy(source,temp,overwrite=TRUE))stop("Could not copy stable map.")
  replace_file_atomically(temp,target)
  invisible(TRUE)
}
map_hotlink_placeholder <- function(path,label,note) {
  dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
  grDevices::png(path,width=1200,height=800,res=120)
  on.exit(grDevices::dev.off(),add=TRUE)
  graphics::par(mar=rep(0,4));graphics::plot.new();graphics::plot.window(c(0,1),c(0,1))
  graphics::rect(0,0,1,1,col="#f1f4f4",border=NA)
  graphics::text(.5,.7,paste(strwrap(label,45),collapse="\n"),cex=1.7,col="#26383f")
  graphics::text(.5,.5,"Map currently unavailable",cex=1.5,col="#87501c")
  graphics::text(.5,.32,paste(strwrap(note,75),collapse="\n"),cex=1,col="#455a64")
  graphics::text(.5,.1,"Southwest Climate Watch | See the map link catalog for status and dates",cex=.9,col="#455a64")
}

stage_map_hotlinks <- function(root,destination,products=read_map_product_config(),
    metadata_dir="data/diagnostics",registry_path="data/diagnostics/map-hotlinks/registry.rds") {
  root<-normalizePath(root,winslash="/",mustWork=TRUE);base<-map_hotlink_base(destination)
  rows<-map_hotlink_rows(root,products,metadata_dir)
  registry<-if(file.exists(registry_path))tryCatch(readRDS(registry_path),error=function(e)NULL) else NULL
  if(is.data.frame(registry)&&nrow(registry)) {
    retired<-registry[!registry$id %in% rows$id & nzchar(registry$alias),,drop=FALSE]
    if(nrow(retired)) {
      retired$source<-"";retired$date<-"";retired$status<-"DISABLED"
      retired$note<-"This product is no longer in the active publication set. No older map is substituted."
      rows<-rbind(rows,retired[,names(rows),drop=FALSE])
    }
  }
  changed<-0L
  for(i in seq_len(nrow(rows))) {
    row<-rows[i,]
    if(!nzchar(row$alias))next
    if(!startsWith(row$alias,"maps/latest/"))stop("Invalid retained endpoint.")
    target<-map_hotlink_path(root,row$alias)
    if(row$status=="AVAILABLE")changed<-changed+as.integer(map_hotlink_install(map_hotlink_path(root,row$source),target)) else {
      temporary<-tempfile(fileext=".png");map_hotlink_placeholder(temporary,row$label,row$note)
      changed<-changed+as.integer(map_hotlink_install(temporary,target));unlink(temporary)
    }
  }
  rows$path<-ifelse(nzchar(rows$alias),rows$alias,rows$source)
  rows$url<-paste0(base,rows$path);rows$source_url<-ifelse(nzchar(rows$source),paste0(base,rows$source),"")
  rows$md5<-unname(tools::md5sum(vapply(rows$path,function(p)map_hotlink_path(root,p),character(1))))
  # Full renders may recreate output directories. Restore unchanged alias mtimes
  # from the small registry so AWS sync does not resend every image each day.
  if(is.data.frame(registry)&&all(c("id","md5","alias_mtime") %in% names(registry)))for(i in which(nzchar(rows$alias))) {
    old<-registry[registry$id==rows$id[i],,drop=FALSE]
    if(nrow(old)==1L&&identical(old$md5,rows$md5[i])&&is.finite(old$alias_mtime))
      Sys.setFileTime(map_hotlink_path(root,rows$path[i]),as.POSIXct(old$alias_mtime,origin="1970-01-01",tz="UTC"))
  }
  catalog<-list(schema_version=1L,generated_utc=format(Sys.time(),"%Y-%m-%d %H:%M:%S UTC",tz="UTC"),
    base_url=base,latest_cache_seconds=300L,maps=rows)
  dir.create(file.path(root,"maps"),recursive=TRUE,showWarnings=FALSE)
  jsonlite::write_json(catalog,file.path(root,"maps/catalog.json"),dataframe="rows",auto_unbox=TRUE,pretty=TRUE,na="null")
  utils::write.csv(rows,file.path(root,"maps/catalog.csv"),row.names=FALSE,na="")
  writeLines(map_hotlink_catalog_html(rows),file.path(root,"maps/catalog.html"),useBytes=TRUE)
  # Keep the public endpoint contract across render cleanup and future disabled products.
  dir.create(dirname(registry_path),recursive=TRUE,showWarnings=FALSE)
  contract<-rows[,c("id","family","label","source","alias","date","status","note","page","md5")]
  contract$alias_mtime<-as.numeric(file.info(vapply(rows$path,function(p)map_hotlink_path(root,p),character(1)))$mtime)
  saveRDS(contract,registry_path)
  validate_map_hotlinks(root)
  message("Stable map links: ",sum(nzchar(rows$alias))," rolling endpoints (",sum(nzchar(rows$alias)&rows$status!="AVAILABLE"),
    " unavailable/disabled notices); ",sum(!nzchar(rows$alias))," dated links; ",changed," alias files changed.")
  invisible(rows)
}

map_hotlink_catalog_html <- function(rows) {
  esc<-map_hotlink_escape
  html<-c('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Map links — Southwest Climate Watch</title>',
    '<style>body{font:16px/1.5 system-ui;color:#26383f;max-width:1400px;margin:2rem auto;padding:0 1rem}input{padding:.6rem;width:min(90%,600px)}table{width:100%;border-collapse:collapse;margin-top:1rem}th,td{text-align:left;vertical-align:top;padding:.6rem;border-bottom:1px solid #d4dfe2}code{overflow-wrap:anywhere;font-size:.85rem}a{color:#08718b}.unavailable{color:#87501c}button{cursor:pointer;padding:.3rem .6rem}.table-wrap{overflow:auto}</style></head><body>',
    '<h1>Map links</h1><p>Use <strong>Latest</strong> URLs to follow updates. Use <strong>Dated</strong> URLs for a specific observation day or historical season. Dates and references are printed on the images; different sources update on different schedules.</p>',
    '<p>Unavailable latest products show a clearly labeled notice image, rather than silently substituting an older map. A failed publication leaves the last successfully uploaded files in place. New latest-image uploads request a five-minute browser cache; an upstream proxy may apply its own policy.</p>',
    '<p><a href="catalog.csv">Download CSV</a> · <a href="catalog.json">Download JSON</a></p><label for="map-search">Find a map</label><br><input id="map-search" type="search" placeholder="Variable, period, family, year or date"><p id="map-count" aria-live="polite"></p>',
    '<div class="table-wrap"><table><thead><tr><th>Map</th><th>Family</th><th>Period / data through</th><th>Status</th><th>Hotlink URL</th></tr></thead><tbody>')
  for(i in seq_len(nrow(rows))) {
    r<-rows[i,];href<-sub("^maps/","",r$path)
    html<-c(html,paste0('<tr><td>',esc(r$label),'<br><small>',if(nzchar(r$alias))'Latest' else 'Dated','</small></td><td>',esc(r$family),'</td><td>',
      esc(if(nzchar(r$date))r$date else "See image / status"),'</td><td class="',if(r$status!="AVAILABLE")'unavailable' else '', '">',esc(r$status),
      if(nzchar(r$note))paste0('<br><small>',esc(r$note),'</small>'),'</td><td><a href="',esc(href),'"><code>',esc(r$url),'</code></a> <button type="button" data-copy="',esc(r$url),'">Copy</button></td></tr>'))
  }
  c(html,'</tbody></table></div><script>const input=document.getElementById("map-search"),rows=[...document.querySelectorAll("tbody tr")],count=document.getElementById("map-count");function filter(){const q=input.value.toLowerCase().trim();let n=0;for(const row of rows){row.hidden=!row.textContent.toLowerCase().includes(q);if(!row.hidden)n++;}count.textContent=n+" maps";}input.addEventListener("input",filter);filter();document.addEventListener("click",async e=>{const b=e.target.closest("button[data-copy]");if(!b)return;try{await navigator.clipboard.writeText(b.dataset.copy);b.textContent="Copied";}catch{window.prompt("Copy this map URL",b.dataset.copy);}});</script></body></html>')
}
validate_map_hotlinks <- function(root) {
  path<-file.path(root,"maps/catalog.json")
  catalog<-jsonlite::read_json(path,simplifyVector=TRUE);rows<-catalog$maps
  if(!is.data.frame(rows)||!nrow(rows)||anyDuplicated(rows$id)||anyDuplicated(rows$path))stop("Invalid map hotlink catalog.")
  for(i in seq_len(nrow(rows))) {
    r<-rows[i,];path<-map_hotlink_path(root,r$path)
    if(!map_hotlink_png(path)||!identical(unname(tools::md5sum(path)),r$md5))stop("Stable map checksum failed: ",r$id)
    if(r$status=="AVAILABLE"&&!identical(unname(tools::md5sum(map_hotlink_path(root,r$source))),r$md5))stop("Stable map differs from accepted source: ",r$id)
    if(!identical(r$url,paste0(catalog$base_url,r$path)))stop("Unexpected public map URL.")
  }
  if(!all(file.exists(file.path(root,"maps",c("catalog.html","catalog.csv")))))stop("Map link catalog downloads are missing.")
  invisible(TRUE)
}
