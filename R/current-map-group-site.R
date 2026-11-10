# Production presentation adapters. Scientific map builders remain unchanged.
.swc_group_module_files <- Filter(function(x) is.character(x) && length(x) == 1L,
  lapply(sys.frames(), function(frame) frame$ofile))
.swc_group_module_dir <- dirname(tail(.swc_group_module_files,1)[[1]])
source(file.path(.swc_group_module_dir, "temperature-tabs-preview.R"))
source(file.path(.swc_group_module_dir, "current-map-groups-preview.R"))
current_map_group_assets <- local({
  path <- normalizePath(file.path(.swc_group_module_dir,"../scripts/temperature-tabs-preview-assets"),winslash="/",mustWork=TRUE)
  function() path
})
rm(.swc_group_module_dir,.swc_group_module_files)

current_site_groups <- function() {
  group <- function(title, section, ids, kind) list(title = title, section = section, ids = ids, kind = kind)
  base <- list(
    "temperature-values" = group("Current values", "Temperature", paste0(c("maxt", "tmean", "mint"), "_value"), "values"),
    "temperature-departures" = group("Departures", "Temperature", paste0(rep(c("maxt", "tmean", "mint"),2), "_departure_", rep(c("daily","30day"),each=3)), "departures"),
    "precipitation-totals" = group("Recent totals", "Precipitation", sprintf("pcpn_total_%02dday", c(1,7,30,90)), "totals"),
    "precipitation-ranks" = group("Percentile ranks", "Precipitation", sprintf("pcpn_percentile_%02dday", c(7,30,90)), "ranks"))
  extras <- current_preview_groups()
  for (key in names(extras)) base[[key]] <- c(extras[[key]], list(ids = extras[[key]]$rows$product, kind = "group"))
  for (key in names(current_remaining_groups())) {
    extra <- current_remaining_groups()[[key]]
    base[[key]] <- c(extra, list(ids=extra$rows$product, kind="group"))
  }
  titles <- c("temperature-values"="Current temperatures", "temperature-departures"="Departures from normal",
    "temperature-daily-ranks"="Daily percentile ranks", "temperature-rolling-ranks"="7–90-day mean ranks",
    "freeze-monitoring"="Freeze dates and season length", "dry-spells"="Dry spells")
  for (key in names(titles)) base[[key]]$title <- unname(titles[[key]])
  base[["precipitation-ranks"]]$intro <- "Percentile ranks show how unusual precipitation is relative to corresponding 1991–2020 periods. A high percentile means wetter conditions; this is not percent of normal."
  base[c("temperature-values", "temperature-departures", "temperature-daily-ranks", "temperature-rolling-ranks", "water-year-temperature",
    "temperature-extremes", "freeze-nights", "freeze-monitoring", "precipitation-totals", "precipitation-ranks",
    "precipitation-percent-normal", "precipitation-change", "water-year-precipitation", "water-year-extremes",
    "dry-spells", "wet-days", "snow-conditions")]
}

current_remaining_groups <- function() {
  row <- function(tab,label,variant,option,product) data.frame(tab=tab,label=label,variant=variant,option=option,product=product)
  group <- function(title,section,rows,intro,tab_notes=NULL) list(title=title,section=section,rows=rows,intro=intro,tab_notes=tab_notes)
  list(
    "temperature-extremes"=group("Temperature extremes","Temperature",rbind(
      row("warm","Extreme warm days","map","Past 30 days","maxt_extreme_warm_count_30day"),
      row("cold","Extreme cold nights","map","Past 30 days","mint_extreme_cold_count_30day")),
      "Counts over the past 30 days use seasonal 1991–2020 percentile thresholds. These are unusually warm days or cold nights, rather than all-time records."),
    "freeze-nights"=group("Freeze nights","Temperature",rbind(
      row("count","Count","map","Past 30 days","mint_freeze_count_30day"),
      row("departure","Departure from normal","map","Past 30 days","mint_freeze_anomaly_30day")),
      "Freeze nights have a minimum temperature at or below 32°F. Compare the past 30-day count with the 1991–2020 average for the same period."),
    "precipitation-percent-normal"=group("Percent of normal","Precipitation",rbind(
      row("precipitation","Precipitation","30","30 days","pcpn_percent_normal_30day"),
      row("precipitation","Precipitation","90","90 days","pcpn_percent_normal_90day")),
      "Precipitation relative to the corresponding 1991–2020 average: 100% is average and 200% is twice average. This measures the amount relative to normal, rather than its percentile rank."),
    "precipitation-change"=group("Recent precipitation change","Precipitation",
      row("change","Change in rank","map","14-day change","pcpn_percentile_change_30day_14day"),
      "Change in the 30-day precipitation percentile rank over the past 14 days, in percentile points. Positive values indicate a shift toward wetter conditions; this is not a precipitation total."),
    "water-year-temperature"=group("Water-year temperature","Temperature",rbind(
      row("mean","Mean temperature","map","Water year to date","tmean_water_year_mean"),
      row("departure","Departure from normal","map","Water year to date","tmean_water_year_departure"),
      row("rank","Percentile rank","map","Water year to date","tmean_water_year_percentile")),
      "Mean temperature from October 1 through the map date. Departures and percentile ranks compare matching calendar-date periods in water years 1991–2020. Each daily mean is (maximum + minimum)/2; days receive equal weight. This is season-to-date context, not a completed-year rank. February 29 references interpolate the February 28 and March 1 cumulative means; missing daily pairs are not filled."),
    "water-year-precipitation"=group("Water-year precipitation","Precipitation",rbind(
      row("total","Total","map","Water year to date","pcpn_water_year_total"),
      row("normal","Percent of normal","map","Water year to date","pcpn_water_year_percent_normal"),
      row("rank","Percentile rank","map","Water year to date","pcpn_water_year_percentile")),
      "Precipitation accumulated from October 1 through the map date. Percent of normal and percentile rank compare corresponding periods in 1991–2020."),
    "water-year-extremes"=group("Water-year precipitation extremes","Precipitation",rbind(
      row("maximum","Largest 3-day total","map","Water year","pcpn_water_year_max_03day"),
      row("rank","Event percentile","map","Water year","pcpn_water_year_max_percentile_03day"),
      row("concentration","Precipitation concentration","map","Water year","pcpn_water_year_concentration_03day")),
      "The largest three-day precipitation total since October 1, its historical context, and its share of water-year precipitation.",
      tab_notes=list(rank="Provisional comparison: the current maximum is compared with maxima from completed 1991–2020 water years. This is not a date-matched season-to-date rank; the current water year is incomplete until September 30."))
  )
}

current_map_group_key <- function(id) {
  groups <- current_site_groups()
  found <- names(groups)[vapply(groups, function(g) id %in% g$ids, logical(1))]
  if (length(found)) found[1] else NA_character_
}

current_map_group_write <- function(text, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(path) && identical(readLines(path, warn = FALSE), text)) return(invisible(FALSE))
  temporary <- tempfile(tmpdir = dirname(path)); on.exit(unlink(temporary), add = TRUE)
  writeLines(text, temporary, useBytes = TRUE)
  replace_file_atomically(temporary, path)
  invisible(TRUE)
}

stage_current_map_groups <- function(site_dir = "site", config_path = "config/map-products.yml", expected_data_dates = NULL) {
  config <- yaml::read_yaml(config_path)
  catalog <- lapply(config$products, function(p) utils::modifyList(if(is.null(config$defaults)) list() else config$defaults, p))
  products <- c(catalog, current_preview_snow_products())
  groups <- current_site_groups()
  assets <- c("temperature-tabs.js", "precipitation-periods.js", "current-map-groups.js", "temperature-tabs.css")
  for (asset in assets) {
    text <- readLines(file.path(current_map_group_assets(), asset), warn = FALSE)
    current_map_group_write(text, file.path(site_dir, "assets/current-map-groups", asset))
  }
  asset_manifest <- data.frame(file=assets,md5=unname(tools::md5sum(file.path(site_dir,"assets/current-map-groups",assets))))
  current_map_group_write(as.character(jsonlite::toJSON(asset_manifest,dataframe="rows",auto_unbox=TRUE,pretty=TRUE)),
    file.path(site_dir,"assets/current-map-groups/assets.json"))
  snow_page <- file.path(site_dir, "pages/current-snow.qmd")
  snow_text <- if (file.exists(snow_page)) readLines(snow_page, warn = FALSE) else character()
  rows <- list()
  for (key in names(groups)) {
    g <- groups[[key]]
    # Honor product enable/disable settings; omit groups with no enabled maps.
    ids <- g$ids[vapply(g$ids, function(id) startsWith(id, "snow_") ||
      (!is.null(products[[id]]) && !identical(products[[id]]$enabled, FALSE)), logical(1))]
    if (!length(ids)) next
    available <- setNames(vapply(ids, function(id) {
      path <- file.path(site_dir, "maps/generated", products[[id]]$image)
      file.exists(path) && (!startsWith(id, "snow_") || any(grepl(basename(path), snow_text, fixed = TRUE)))
    }, logical(1)), ids)
    waiting <- map_product_early_water_year_three_day(data.frame(id=ids,enabled=TRUE),expected_data_dates)
    available[waiting] <- FALSE
    if (any(waiting)) g$unavailable_notes <- setNames(rep(
      paste0("A complete three-day period is not available until October 3, ", format(as.Date(expected_data_dates[["Precipitation"]]), "%Y"), "."),sum(waiting)),ids[waiting])
    # The shared renderer receives explicit combinations, including base pages.
    if (g$kind == "values") {
      g$rows <- do.call(rbind, lapply(ids, function(id) data.frame(tab = sub("_value$", "", id),
        label = c(maxt="Maximum",tmean="Mean",mint="Minimum")[[sub("_value$","",id)]], variant="map",option="Daily value",product=id)))
    } else if (g$kind == "departures") {
      g$rows <- do.call(rbind, lapply(ids, function(id) data.frame(tab = sub("_departure_.*$", "", id),
        label = c(maxt="Maximum",tmean="Mean",mint="Minimum")[[sub("_departure_.*$","",id)]],
        variant=sub("^.*_departure_","",id),option=if(grepl("30day$",id)) "30-day mean" else "Daily",product=id)))
    } else if (g$kind %in% c("totals", "ranks")) {
      g$rows <- do.call(rbind, lapply(ids, function(id) {
        days <- as.integer(sub("^.*_([0-9]+)day$","\\1",id))
        data.frame(tab="precipitation",label="Precipitation",variant=as.character(days),
          option=paste(days,if(days==1) "day" else "days"),product=id)
      }))
    } else g$rows <- g$rows[g$rows$product %in% ids, , drop = FALSE]
    if (is.null(g$all_maps)) g$all_maps <- FALSE
    text <- current_group_preview_page(key, g, products, available)
    text <- text[!grepl("Local layout review", text, fixed = TRUE)]
    text <- sub(' · <a href="individual/[^\"]+">Original individual map page</a>', '', text)
    text <- sub('This map is not available in the laptop’s current cached set. No map from a different date has been substituted.',
      'This map is currently unavailable. No map from a different date has been substituted.', text, fixed = TRUE)
    if (key == "snow-conditions") {
      status <- snow_text[grepl("^\\*\\*Latest map date:|^Seven-day SWE change unavailable|^Current-season snow maps are waiting", snow_text)]
      if (length(status)) text <- append(text, paste0('<p>', temperature_preview_escape(gsub("\\*\\*", "", status)), '</p>'),
        after = grep('class="current-group-preview"', text)[1])
    }
    if (key %in% c("temperature-departures", "precipitation-totals", "precipitation-ranks", "temperature-rolling-ranks", "precipitation-percent-normal"))
      text <- sub('for="group-variant">Display', 'for="group-variant">Time period', text, fixed = TRUE)
    for (id in ids) {
      text <- gsub(paste0('maps/',basename(products[[id]]$image)), paste0('../maps/generated/',products[[id]]$image), text, fixed = TRUE)
      source <- file.path(site_dir, "maps/generated", products[[id]]$image)
      rows[[length(rows)+1L]] <- data.frame(page=paste0(key,".html"),product=id,image=products[[id]]$image,
        available=available[[id]],md5=if(available[[id]]) unname(tools::md5sum(source)) else NA_character_)
    }
    text <- sub('src="current-map-groups.js"', 'src="../assets/current-map-groups/current-map-groups.js"', text, fixed = TRUE)
    current_map_group_write(text, file.path(site_dir, "pages", paste0(key,".qmd")))
  }
  manifest <- do.call(rbind, rows)
  path <- file.path(site_dir, "assets/current-map-groups/manifest.json")
  json <- jsonlite::toJSON(manifest, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE, na = "null")
  current_map_group_write(as.character(json), path)
  invisible(manifest)
}

validate_current_map_groups <- function(site_dir="site", rendered_dir=NULL,
    report_dir="data/diagnostics/current-map-groups") {
  root <- if(is.null(rendered_dir)) site_dir else rendered_dir
  source_manifest <- file.path(site_dir,"assets/current-map-groups/manifest.json")
  manifest_path <- file.path(root,"assets/current-map-groups/manifest.json")
  if (!file.exists(manifest_path)) stop("Grouped Current Maps manifest missing; stage the groups before publication.")
  if (!identical(unname(tools::md5sum(manifest_path)),unname(tools::md5sum(source_manifest)))) stop("Rendered grouped-map manifest differs from source.")
  manifest <- jsonlite::read_json(manifest_path,simplifyVector=TRUE)
  assets <- jsonlite::read_json(file.path(site_dir,"assets/current-map-groups/assets.json"),simplifyVector=TRUE)
  asset_paths <- file.path(root,"assets/current-map-groups",assets$file)
  if(!all(file.exists(asset_paths)) || !identical(unname(tools::md5sum(asset_paths)),assets$md5)) stop("Grouped controls/style checksum failed; sync stopped.")
  navigation <- readLines(file.path(site_dir,"_quarto.yml"),warn=FALSE)
  if(any(grepl("Original individual pages",navigation,fixed=TRUE))) stop("Preview-only navigation must not be published.")
  records <- list()
  for(page in unique(manifest$page)) {
    if(!any(grepl(paste0("pages/",sub("html$","qmd",page)),navigation,fixed=TRUE))) stop("Grouped page missing from navigation: ",page)
    path <- file.path(root,"pages",if(is.null(rendered_dir)) sub("html$","qmd",page) else page)
    doc <- xml2::read_html(path)
    nodes <- xml2::xml_find_all(doc,'//*[@data-product]')
    rows <- manifest[manifest$page==page,]
    if(length(nodes)!=nrow(rows)||!setequal(xml2::xml_attr(nodes,"data-product"),rows$product)) stop("Incomplete grouped page: ",page)
    if(any(grepl("Original individual",xml2::xml_text(doc),fixed=TRUE))) stop("Preview-only links remain on grouped page: ",page)
    for(node in nodes) {
      id <- xml2::xml_attr(node,"data-product"); row <- rows[rows$product==id,]
      image <- xml2::xml_find_all(node,".//img")
      if(row$available) {
        target <- file.path(root,"maps/generated",row$image)
        source <- file.path(site_dir,"maps/generated",row$image)
        good <- length(image)==1L && identical(xml2::xml_attr(image,"src"),paste0("../maps/generated/",row$image)) &&
          identical(xml2::xml_attr(xml2::xml_parent(image),"href"),paste0("../maps/generated/",row$image)) &&
          file.exists(target) && identical(unname(tools::md5sum(target)),row$md5) &&
          identical(unname(tools::md5sum(source)),row$md5)
      } else good <- !length(image) && length(xml2::xml_find_all(node,'.//*[contains(@class,"group-unavailable")]'))==1L
      records[[length(records)+1L]] <- data.frame(page=page,product=id,status=if(good) "PASS" else "FAIL",available=row$available)
    }
    script <- xml2::xml_find_first(doc,'//script[contains(@src,"current-map-groups.js")]')
    if(inherits(script,"xml_missing") || !file.exists(file.path(root,"assets/current-map-groups/current-map-groups.js"))) stop("Grouped controls missing: ",page)
  }
  result <- do.call(rbind,records)
  dir.create(report_dir,recursive=TRUE,showWarnings=FALSE)
  write.csv(result,file.path(report_dir,"publication.csv"),row.names=FALSE)
  if(any(result$status!="PASS")) stop("Grouped Current Maps validation failed; sync stopped.")
  message("Grouped Current Maps: PASS; ",nrow(result)," views, ",sum(!result$available)," unavailable notices.")
  invisible(result)
}
