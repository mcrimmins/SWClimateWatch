# Dated, human-readable evidence for each selected bullet. No source requests.
synopsis_support_href <- function(link, base="https://cales.arizona.edu/climate/watch/") {
  if(startsWith(link,"support/")) link else paste0(base,link)
}
synopsis_support_label <- function(link) {
  if(startsWith(link,"support/")||grepl("synopsis-evidence/",link,fixed=TRUE)) "Evidence and matching dates" else
    if(grepl("station-conditions",link,fixed=TRUE)) "Station Conditions" else "Related map"
}
synopsis_support_rows <- function(evidence) {
  packets<-list(evidence$facts,evidence$recent$facts,evidence$recent$days,
    evidence$station_week$candidates,evidence$station_extremes$candidates,
    evidence$regional_highlights$grids,evidence$regional_highlights$stations$facts,evidence$snow_context$facts)
  result<-list()
  for(packet in packets) if(is.data.frame(packet)&&nrow(packet)&&"fact_id" %in% names(packet))
    for(i in seq_len(nrow(packet))) result[[as.character(packet$fact_id[i])]]<-packet[i,,drop=FALSE]
  result
}

synopsis_support_table <- function(row) {
  labels<-c(name="Station",state="State",region="Region",metric="Metric",value="Value",units="Units",
    period_start="Period starts",period_end="Period ends",event_start="Event starts",event_end="Event ends",date="Date",
    reference="Comparison reference",normal="Reference average",observed="Observed count",sample_years="Reference years",
    historical_rank="Rank including current period",historical_first_year="First earlier endpoint year",historical_last_year="Last earlier endpoint year",
    historical_ties="Tied periods including current",historical_percentile="Historical percentile",rank_direction="Rank direction",
    context_normal="1991–2020 mean matching-window extreme",context_normal_years="Complete normal-reference windows",peak_anomaly="Departure of extreme from reference mean",
    historical_n="Earlier complete comparison windows",rank="Rank",rank_n="Rank sample size",percentile="Percentile",
    unusual_percentile="Percentile in unusual direction",context_status="Comparison support",
    mean_inches="Daily regional mean (inches)",rain_area_percent="Area receiving threshold (%)",rain_threshold_inches="Rain threshold (inch)",
    count="Stations meeting threshold",eligible="Eligible stations",percent="Eligible stations (%)",tail="Tail",variable="Variable",period="Summary period",
    coverage="Valid area fraction",threshold="Threshold",denominator="Eligible-area definition",eligible_area_km2="Eligible area (km²)",
    comparison_date="Compared with",status="Evidence status",caution_codes="Station cautions")
  keys<-intersect(names(labels),names(row));esc<-synopsis_escape_html
  paste0('<table>',paste(vapply(keys,function(key) {
    value<-row[[key]][1L]
    if(length(value)!=1L||is.na(value))return("")
    if(key=="metric") {
      value<-gsub("_"," ",value,fixed=TRUE)
      value<-gsub("pcpn","precipitation",value,fixed=TRUE)
      value<-gsub("swe","SWE",value,fixed=TRUE)
    }
    if(is.numeric(value))value<-format(signif(value,5),trim=TRUE,scientific=FALSE)
    paste0('<tr><th scope="row">',esc(labels[[key]]),'</th><td>',esc(as.character(value)),'</td></tr>')
  },character(1)),collapse=""),'</table>')
}

synopsis_support_temperature_map <- function(evidence,root,output_dir) {
  packet<-evidence$recent$facts
  x<-if(is.data.frame(packet))packet[packet$product=="tmean_departure_07day" & packet$region=="AZNM" & packet$metric=="mean_departure",,drop=FALSE] else data.frame()
  if(nrow(x)!=1L||!"source_path" %in% names(x)||!file.exists(x$source_path))return(NULL)
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  image<-file.path(output_dir,"temperature-7day.png");stamp<-paste0(image,".rds")
  signature<-digest::digest(list(version=1L,md5=unname(tools::md5sum(x$source_path)),end=x$period_end,
    code=unname(tools::md5sum(file.path(root,"R",c("map-southwest.R","map-product-scales.R","build-current-prism-maps.R"))))))
  cached<-if(file.exists(stamp))tryCatch(readRDS(stamp),error=function(e)NULL) else NULL
  if(file.exists(image)&&identical(cached$signature,signature)&&identical(cached$md5,unname(tools::md5sum(image))))return(image)
  r<-terra::rast(x$source_path)
  if(terra::nlyr(r)!=1L||as.character(as.Date(terra::time(r)))!=x$period_end ||
    !identical(unname(tools::md5sum(x$source_path)),x$source_md5))stop("Seven-day map source/date differs from supporting fact.")
  ctx<-new.env(parent=globalenv())
  for(file in c("config","acis-prism","process-prism","map-reference-layers","map-product-scales","map-southwest","build-current-prism-maps","build-current-prism-precipitation-maps"))
    sys.source(file.path(root,"R",paste0(file,".R")),ctx)
  plot<-ctx$build_prism_rolling_temperature_departure_map(r,"tmean",7L,as.Date(x$period_end))
  ctx$save_southwest_map(plot,image,logo_path=ctx$southwest_brand_logo_path(),footer_text=ctx$prism_map_footer_text())
  saveRDS(list(signature=signature,md5=unname(tools::md5sum(image))),stamp)
  image
}

synopsis_attach_support <- function(blocks,evidence,root,output_dir) {
  dir.create(file.path(output_dir,"support"),recursive=TRUE,showWarnings=FALSE)
  # Only generated highlight documents are replaced; the matching map cache is retained.
  unlink(list.files(file.path(output_dir,"support"),pattern="^highlight-[0-9]+\\.html$",full.names=TRUE))
  rows<-synopsis_support_rows(evidence);audit<-list();selected<-list()
  synthetic<-identical(evidence$data_kind,"synthetic_validation")
  has_week_temp<-any(vapply(blocks,function(b)any(grepl("tmean_departure_07day",b$fact_ids,fixed=TRUE)),logical(1)))
  map_note<-"";map<-if(has_week_temp&&!synthetic)tryCatch(synopsis_support_temperature_map(evidence,root,file.path(output_dir,"support")),
    error=function(e){map_note<<-conditionMessage(e);NULL}) else NULL
  for(i in seq_along(blocks)) {
    block<-blocks[[i]];ids<-unique(block$fact_ids);found<-intersect(ids,names(rows))
    # Explicit unavailable notices need no quantitative support. Numerical claims
    # require resolvable facts. A seven-day temperature claim requires its map.
    status<-if(!length(ids))"NOTICE" else if(length(found)!=length(ids))"MISSING_FACT" else "SUPPORTED"
    week_temp<-any(grepl("tmean_departure_07day",ids,fixed=TRUE))
    if(week_temp)block$links<-setdiff(block$links,"pages/daily-explorer.html")
    if(week_temp&&!synthetic&&is.null(map))status<-"MATCHING_MAP_UNAVAILABLE"
    audit[[length(audit)+1L]]<-data.frame(section=block$section,text=block$text,status=status,
      fact_ids=paste(ids,collapse=";"),note=if(week_temp)map_note else "",stringsAsFactors=FALSE)
    if(!status %in% c("NOTICE","SUPPORTED"))next
    if(length(ids)) {
      file<-paste0("highlight-",i,".html");esc<-synopsis_escape_html
      html<-c('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Synopsis supporting evidence</title>',
        '<style>body{font:16px/1.6 system-ui;color:#26383f;margin:2rem auto;padding:0 1rem;max-width:1000px}table{border-collapse:collapse;margin:1rem 0;width:100%}th,td{text-align:left;vertical-align:top;border-bottom:1px solid #d6dfe1;padding:.4rem}th{width:40%}img{width:100%;height:auto}a{color:#08718b}</style></head><body><main>',
        '<h1>Supporting evidence</h1>',if(synthetic)'<p><strong>Fictional seasonal test; not observations.</strong></p>',
        paste0('<p>Synopsis cutoff: ',esc(synopsis_date_text(evidence$snapshot_date)),'. Each fact retains its own observation period and reference.</p>'),
        paste0('<p>',esc(block$text),'</p>'))
      if(week_temp&&!is.null(map))html<-c(html,'<h2>Seven-day mean temperature departure</h2><a href="temperature-7day.png"><img src="temperature-7day.png" alt="Seven-day mean temperature departure for the exact stated period"></a>')
      for(id in found) html<-c(html,paste0('<h2>',esc(if("name" %in% names(rows[[id]]))rows[[id]]$name else if("metric" %in% names(rows[[id]]))gsub("_"," ",rows[[id]]$metric) else "Daily precipitation"),'</h2>'),synopsis_support_table(rows[[id]]))
      if(length(block$changes)) for(change in block$changes)html<-c(html,'<h2>Previous comparison snapshot</h2>',synopsis_support_table(change$previous_fact))
      if(is.data.frame(block$comparison_facts)&&nrow(block$comparison_facts))for(j in seq_len(nrow(block$comparison_facts)))
        html<-c(html,'<h2>Previous comparison snapshot</h2>',synopsis_support_table(block$comparison_facts[j,,drop=FALSE]))
      if(length(block$links))html<-c(html,'<h2>Related products</h2><p>These tools may show a newer date. The tables above preserve the evidence used for this synopsis.</p>',
        paste0('<p><a href="https://cales.arizona.edu/climate/watch/',esc(block$links),'">',esc(vapply(block$links,synopsis_support_label,character(1))),'</a></p>'))
      writeLines(c(html,'</main></body></html>'),file.path(output_dir,"support",file),useBytes=TRUE)
      block$support_link<-paste0("support/",file)
    }
    selected[[length(selected)+1L]]<-block
  }
  utils::write.csv(do.call(rbind,audit),file.path(output_dir,"highlight-link-audit.csv"),row.names=FALSE)
  attr(selected,"highlights")<-attr(blocks,"highlights");attr(selected,"regional_candidates")<-attr(blocks,"regional_candidates")
  selected
}
