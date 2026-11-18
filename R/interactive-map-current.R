# Latest Current Maps snapshots. Never recalculate or choose a different date.
interactive_current_definitions <- function() {
  rows <- list()
  add <- function(id, variable, metric, period, folder, period_label, measure = if (variable == "temperature") "mean" else "amount") {
    rows[[length(rows) + 1L]] <<- data.frame(id, variable, measure, metric, period, folder, period_label)
  }
  for (n in c(1L, 7L, 30L, 90L)) add(sprintf("pcpn_total_%02dday", n), "precipitation", "total", paste0(n, "day"),
    file.path("accumulation/pcpn", sprintf("%02dday", n)), paste(n, if (n == 1) "day" else "days"))
  for (n in c(7L, 30L, 90L)) add(sprintf("pcpn_percentile_%02dday", n), "precipitation", "ranking", paste0(n, "day"),
    file.path("percentile-rank/pcpn", sprintf("%02dday", n)), paste(n, "days"))
  for (n in c(30L, 90L)) add(sprintf("pcpn_percent_normal_%02dday", n), "precipitation", "percent_normal", paste0(n, "day"),
    file.path("percent-normal/pcpn", sprintf("%02dday", n)), paste(n, "days"))
  for (metric in c("total", "percent_normal", "ranking")) add(paste0("pcpn_water_year_", switch(metric, ranking = "percentile", metric)),
    "precipitation", metric, "water_year", file.path("water-year/pcpn", switch(metric, percent_normal = "percent-normal", ranking = "percentile-rank", metric)), "Water year to date")
  for (metric in c("mean", "departure", "ranking")) add(paste0("tmean_water_year_", switch(metric, ranking = "percentile", metric)),
    "temperature", metric, "water_year", file.path("water-year/tmean", switch(metric, ranking = "percentile", metric)), "Water year to date")
  for (n in c(7L, 30L, 90L)) add(sprintf("tmean_percentile_%02dday", n), "temperature", "ranking", paste0(n,"day"),
    file.path("rolling-percentile-rank/tmean",sprintf("%03dday",n)),paste(n,"days"))
  for (family in c("maxt","tmean","mint")) add(paste0(family,"_departure_30day"),"temperature","departure","30day",
    file.path("rolling-departure",family,"030day"),"30 days",switch(family,maxt="high",tmean="mean",mint="low"))
  add("pcpn_percentile_change_30day_14day","precipitation","change","30day",
    "percentile-rank-change/pcpn/30day/14day-change","30-day totals · 14-day change","rank_change")
  for (metric in c("length","ranking")) {
    add(paste0("pcpn_current_dry_spell_",if(metric=="ranking")"percentile" else "length"),"precipitation",metric,"current",
      file.path("dry-spell/pcpn",if(metric=="ranking")"percentile-rank" else "length"),"Ongoing","dry_spell")
    add(if(metric=="ranking")"pcpn_longest_dry_spell_percentile_180day" else "pcpn_longest_dry_spell_180day","precipitation",metric,"180day",
      file.path("longest-dry-spell/pcpn/180day",if(metric=="ranking")"percentile-rank" else "length"),"180 days","longest_dry_spell")
  }
  add("maxt_extreme_warm_count_30day","temperature","count","30day","extreme-frequency/maxt/above-p90/030day","30 days","warm_days")
  add("mint_extreme_cold_count_30day","temperature","count","30day","extreme-frequency/mint/below-p10/030day","30 days","cold_nights")
  add("mint_freeze_count_30day","temperature","count","30day","threshold-count/mint/at-or-below-32F/030day","30 days","freeze_nights")
  add("mint_freeze_anomaly_30day","temperature","anomaly","30day","freeze-count-anomaly/mint/030day","30 days","freeze_nights")
  for (metric in c("count","ranking")) add(if(metric=="count")"pcpn_wet_day_count_90day" else "pcpn_wet_day_count_percentile_90day",
    "precipitation",metric,"90day",file.path("wet-day-count/pcpn/090day",if(metric=="count")"count" else "percentile-rank"),"90 days","wet_frequency")
  for (metric in c("intensity","ranking")) add(if(metric=="intensity")"pcpn_wet_day_intensity_90day" else "pcpn_wet_day_intensity_percentile_90day",
    "precipitation",metric,"90day",file.path("wet-day-intensity/pcpn/090day",if(metric=="intensity")"intensity" else "percentile-rank"),"90 days","wet_intensity")
  for (metric in c("share","ranking")) add(if(metric=="share")"pcpn_very_wet_contribution_90day" else "pcpn_very_wet_contribution_percentile_90day",
    "precipitation",metric,"90day",file.path("very-wet-contribution/pcpn/090day",if(metric=="share")"contribution" else "percentile-rank"),"90 days","very_wet_share")
  for (metric in c("maximum","ranking","share")) add(switch(metric,maximum="pcpn_water_year_max_03day",ranking="pcpn_water_year_max_percentile_03day",share="pcpn_water_year_concentration_03day"),
    "precipitation",metric,"water_year",file.path("water-year-maximum/pcpn/003day",switch(metric,maximum="maximum",ranking="percentile-rank",share="concentration")),"Water year to date","wy_extremes")
  do.call(rbind, rows)
}

interactive_current_snapshot <- function(spec, status, config, root = "data/processed/prism/az-nm-pad050/daily", maps_root = "site/maps/generated") {
  id <- spec$id; product <- config$products[[id]]
  if (is.null(product)) stop("Product not configured: ", id)
  row <- status[status$id == id, , drop = FALSE]
  if (nrow(row) != 1 || !isTRUE(row$enabled) || row$validation_status != "PASS") stop("No passing Current Maps publication record")
  date <- as.Date(row$actual_data_date)
  if (is.na(date)) stop("Current Maps date unavailable")
  image <- file.path(maps_root, product$image)
  if (!file.exists(image) || !identical(unname(tools::md5sum(image)), as.character(row$image_md5))) stop("Current Maps image/status fingerprint mismatch; refresh map validation first")
  path <- file.path(root, spec$folder, paste0(date, ".tif"))
  if (!file.exists(path)) stop("Exact dated numerical grid missing")
  r <- terra::rast(path)
  if (terra::nlyr(r) != 1L || !terra::is.lonlat(r) || !grepl("4326", terra::crs(r))) stop("Current grid geometry unsupported")
  time <- terra::time(r)
  if (length(time) != 1L || is.na(time) || as.character(as.Date(time)) != as.character(date)) stop("Numerical grid date differs from the displayed product")
  values <- terra::values(r, mat = FALSE)
  if (!any(is.finite(values)) || any(is.infinite(values))) stop("Current grid has no supported finite values")
  if (spec$metric == "ranking" && any(values < 0 | values > 100, na.rm = TRUE)) stop("Invalid percentile values; category codes are not percentiles")
  if (spec$metric %in% c("percent_normal", "total", "length") && any(values < 0, na.rm = TRUE)) stop("Invalid negative amount, duration or percentage")
  if (spec$metric == "change" && any(abs(values) > 100,na.rm=TRUE)) stop("Invalid percentile-point change")
  if (spec$metric == "share" && any(values < 0 | values > 100,na.rm=TRUE)) stop("Invalid precipitation share")
  if (spec$metric %in% c("maximum","intensity") && any(values < 0,na.rm=TRUE)) stop("Invalid negative precipitation amount")
  if (spec$metric == "count") {
    days <- as.integer(sub("day$","",spec$period))
    if (any(values < 0 | values > days | values != round(values),na.rm=TRUE)) stop("Invalid day/night count")
  }
  start <- if (spec$period == "current") date else if (spec$period == "water_year") as.Date(sprintf("%d-10-01", as.integer(format(date, "%Y")) - as.integer(format(date, "%m") < "10"))) else
    date - as.integer(sub("day$", "", spec$period)) + 1L
  list(raster = r, values = values, date = date, start = start, path = path,
    grid_md5 = unname(tools::md5sum(path)), image_md5 = unname(tools::md5sum(image)))
}

interactive_current_export <- function(id, snapshot, output_dir) {
  r <- snapshot$raster; v <- snapshot$values; bytes <- length(v) * 8L
  signature <- digest::digest(list(policy = "current-snapshot-native-v1", id = id, date = snapshot$date,
    grid = snapshot$grid_md5, image = snapshot$image_md5), algo = "sha256")
  filename <- paste0("current-", id, "-", substr(signature, 1, 16), ".bin")
  path <- file.path(output_dir, filename); receipt <- paste0(path, ".md5")
  reused <- file.exists(path) && file.info(path)$size == bytes && file.exists(receipt) &&
    identical(readLines(receipt), unname(tools::md5sum(path)))
  if (!reused) {
    con <- file(path, "wb"); tryCatch(writeBin(as.numeric(v), con, size = 8, endian = "little"), finally = close(con))
    writeLines(unname(tools::md5sum(path)), receipt)
  }
  con <- file(path, "rb"); decoded <- tryCatch(readBin(con, "numeric", n = length(v), size = 8, endian = "little"), finally = close(con))
  passed <- length(decoded) == length(v) && identical(is.na(decoded), is.na(v)) && all(decoded[!is.na(v)] == v[!is.na(v)])
  if (!passed) stop("Current payload does not match its exact source grid")
  list(entry = list(frequency = "current", product = id, date = as.character(snapshot$date),
    start_date = as.character(snapshot$start), period = paste(format(snapshot$start, "%b %d, %Y"), "to", format(snapshot$date, "%b %d, %Y")),
    file = filename, bytes = bytes, fields = list(value = list(type = "float64", offset = 0L)),
    grid = list(west = terra::xmin(r), east = terra::xmax(r), south = terra::ymin(r), north = terra::ymax(r),
      dx = terra::res(r)[1], dy = terra::res(r)[2], rows = terra::nrow(r), cols = terra::ncol(r)),
    source_md5 = list(grid = snapshot$grid_md5, image = snapshot$image_md5)),
    summary = data.frame(layer = paste0("current-", id), bytes = bytes, reused = reused),
    checks = data.frame(layer = paste0("current-", id), field = "value", cells = length(v), passed = passed))
}

add_interactive_current_maps <- function(pilot, output_dir = "data/diagnostics/interactive-map-pilot",
    status_path = "data/diagnostics/map-product-status.csv", config_path = "config/map-products.yml") {
  config <- yaml::read_yaml(config_path)
  status <- if (file.exists(status_path)) read.csv(status_path, stringsAsFactors = FALSE) else data.frame(id = character())
  specs <- interactive_current_definitions()
  enabled <- vapply(specs$id, function(id) {
    p <- config$products[[id]]
    !is.null(p) && isTRUE(if (is.null(p$enabled)) if (is.null(config$defaults$enabled)) TRUE else config$defaults$enabled else p$enabled)
  }, logical(1))
  specs <- specs[enabled, , drop = FALSE]
  # Replacing the current catalog must also remove previously enabled/stale layers.
  pilot$manifest$layers <- pilot$manifest$layers[!startsWith(names(pilot$manifest$layers),"current-")]
  variables <- list(); products <- list(); summaries <- list(); checks <- list(); report <- list()
  labels <- list(precipitation = c(total = "Total", ranking = "Percentile rank", percent_normal = "Percent of normal",change="Change in percentile",length="Length",count="Wet-day count",intensity="Inches per wet day",share="Share of precipitation",maximum="Maximum 3-day total"),
    temperature = c(mean = "Mean temperature", departure = "Departure from normal", ranking = "Percentile rank",count="Day/night count",anomaly="Count anomaly"))
  measure_labels <- c(amount="Precipitation totals",rank_change="Precipitation change",dry_spell="Current dry spell",longest_dry_spell="Longest dry spell",mean="Mean temperature",high="High temperature",low="Low temperature",
    warm_days="Unusually warm days",cold_nights="Unusually cold nights",freeze_nights="Freeze nights",wet_frequency="Wet-day frequency",wet_intensity="Wet-day intensity",very_wet_share="Very-wet-day contribution",wy_extremes="Water-year 3-day extremes")
  for (i in seq_len(nrow(specs))) {
    s <- specs[i, ]; id <- s$id; p <- config$products[[id]]
    if (is.null(variables[[s$variable]])) variables[[s$variable]] <- list(label = if (s$variable == "temperature") "Temperature" else "Precipitation", measures = list())
    if (is.null(variables[[s$variable]]$measures[[s$measure]])) variables[[s$variable]]$measures[[s$measure]] <- list(label=unname(measure_labels[s$measure]),metrics=list(),periods=list())
    variables[[s$variable]]$measures[[s$measure]]$metrics[[s$metric]] <- unname(labels[[s$variable]][s$metric])
    variables[[s$variable]]$measures[[s$measure]]$periods[[s$metric]][[s$period]] <- s$period_label
    descriptor <- list(variable = s$variable, measure=s$measure, metric = s$metric, period = s$period, period_label = s$period_label,
      title = p$label, description = p$description,
      product_page = paste0("../pages/products/", id, ".html"), public_url = paste0("https://cales.arizona.edu/climate/watch/pages/products/", id, ".html"))
    result <- tryCatch({
      snapshot <- interactive_current_snapshot(s, status, config)
      exported <- interactive_current_export(id, snapshot, output_dir)
      exported$entry$reference <- p$description
      exported$entry$product_page <- descriptor$product_page; exported$entry$public_url <- descriptor$public_url
      pilot$manifest$layers[[paste0("current-", id)]] <- exported$entry
      summaries[[id]] <- exported$summary; checks[[id]] <- exported$checks
      descriptor$date <- as.character(snapshot$date)
      list(status = "PASS", note = "", date = as.character(snapshot$date))
    }, error = function(e) list(status = "UNAVAILABLE", note = conditionMessage(e), date = NA_character_))
    descriptor$available <- result$status == "PASS"; descriptor$note <- result$note
    products[[id]] <- descriptor
    report[[id]] <- data.frame(product = id, date = result$date, status = result$status, note = result$note)
    message("Interactive Current Conditions: ", id, "; ", result$status)
  }
  if (!length(products)) stop("None of the supported Current Maps products are enabled in the YAML configuration.")
  pilot$manifest$schema <- 5L
  pilot$manifest$current <- list(variables = variables, products = products)
  temp <- tempfile(fileext = ".json")
  jsonlite::write_json(pilot$manifest, temp, auto_unbox = TRUE, pretty = TRUE, digits = 16)
  interactive_pilot_copy(temp, file.path(output_dir, "manifest.json")); unlink(temp)
  if (length(summaries)) pilot$summary <- rbind(pilot$summary, do.call(rbind, summaries))
  if (length(checks)) pilot$checks <- rbind(pilot$checks, do.call(rbind, checks))
  write.csv(do.call(rbind, report), file.path(dirname(output_dir), "interactive-current-status.csv"), row.names = FALSE)
  if (length(checks)) write.csv(do.call(rbind, checks), file.path(dirname(output_dir), "interactive-current-checks.csv"), row.names = FALSE)
  pilot
}
