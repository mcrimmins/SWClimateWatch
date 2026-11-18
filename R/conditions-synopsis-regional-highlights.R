# Optional cache-only adapters: no downloading, rendering or climatology builds.
synopsis_highlight_config <- function(config) {
  defaults <- list(extreme_count_days = 6, minimum_area_percent = 20, rank_change_points = 20,
    station_tail_low = 10, station_tail_high = 90, minimum_stations = 10,
    minimum_state_stations = 5, minimum_station_fraction_percent = 30)
  x <- utils::modifyList(defaults, if (is.null(config$regional_highlights)) list() else config$regional_highlights)
  if (any(!vapply(x, function(v) is.numeric(v) && length(v) == 1L && is.finite(v) && v > 0, logical(1))) ||
      x$extreme_count_days > 30 || x$extreme_count_days != floor(x$extreme_count_days) ||
      x$minimum_area_percent > 100 || x$rank_change_points > 100 || x$minimum_station_fraction_percent > 100 ||
      x$station_tail_low >= 50 || x$station_tail_high <= 50 || x$station_tail_high >= 100 ||
      any(unlist(x[c("minimum_stations", "minimum_state_stations")]) %% 1 != 0)) stop("Invalid regional synopsis highlight thresholds.")
  x
}

synopsis_highlight_specs <- function(root, date) {
  base <- file.path(root, "data/processed/prism/az-nm-pad050/daily")
  data.frame(product = c("maxt_extreme_warm_count_30day", "mint_extreme_cold_count_30day", "pcpn_percentile_change_30day_14day"),
    path = file.path(base, c("extreme-frequency/maxt/above-p90/030day", "extreme-frequency/mint/below-p10/030day",
      "percentile-rank-change/pcpn/30day/14day-change"), paste0(date, ".tif")), stringsAsFactors = FALSE)
}

synopsis_highlight_stats <- function(values, weights, kind, config) {
  if (length(values) != length(weights) || any(weights < 0, na.rm = TRUE)) stop("Invalid highlight area weights.")
  h <- synopsis_highlight_config(config)
  inside <- is.finite(weights) & weights > 0; valid <- inside & is.finite(values)
  total <- sum(weights[inside]); coverage <- if (total > 0) sum(weights[valid])/total else 0
  invalid <- any(!is.na(values[inside]) & !is.finite(values[inside])) || if (kind == "change")
    any(abs(values[valid]) > 100) else any(values[valid] < 0 | values[valid] > 30 | abs(values[valid] - round(values[valid])) > 1e-6)
  status <- if (invalid) "INVALID_RANGE" else if (coverage < config$minimum_area_coverage || total <= 0) "LOW_COVERAGE" else "AVAILABLE_CACHED"
  metrics <- if (kind == "change") c("area_rank_increased", "area_rank_decreased") else c("mean_days", "area_extreme_days")
  value <- setNames(rep(NA_real_, 2L), metrics)
  if (status == "AVAILABLE_CACHED") {
    area <- function(test) 100 * sum(weights[valid & test])/sum(weights[valid])
    value <- if (kind == "change") c(area_rank_increased = area(values >= h$rank_change_points),
      area_rank_decreased = area(values <= -h$rank_change_points)) else
      c(mean_days = stats::weighted.mean(values[valid], weights[valid]), area_extreme_days = area(values >= h$extreme_count_days))
  }
  list(value = value, status = status, coverage = coverage)
}

synopsis_highlight_grid_inventory <- function(root, date, config) {
  specs <- synopsis_highlight_specs(root, date); result <- list(); weights <- NULL; geometry <- NULL
  for (i in seq_len(nrow(specs))) {
    s <- specs[i, ]; kind <- if (grepl("change", s$product)) "change" else "count"
    note <- ""; r <- NULL
    if (file.exists(s$path)) tryCatch({
      r <- terra::rast(s$path)
      if (terra::nlyr(r) != 1L || !identical(as.Date(terra::time(r)), as.Date(date))) stop("Grid date/layers do not match snapshot.")
      if (is.null(weights)) {weights <- synopsis_area_weights(r); geometry <- r} else terra::compareGeom(geometry, r, stopOnError = TRUE)
    }, error = function(e) {note <<- conditionMessage(e); r <<- NULL}) else note <- "Matching-date grid is not cached."
    for (region in c("AZNM", "AZ", "NM")) {
      metrics <- if (kind == "change") c("area_rank_increased", "area_rank_decreased") else c("mean_days", "area_extreme_days")
      stats <- if (!is.null(r)) synopsis_highlight_stats(terra::values(r, mat = FALSE), weights[[region]], kind, config) else
        list(value = setNames(rep(NA_real_, 2), metrics), status = "UNAVAILABLE", coverage = NA_real_)
      for (metric in metrics) result[[length(result) + 1L]] <- data.frame(fact_id = paste(s$product, region, metric, sep = ":"),
        product = s$product, region = region, metric = metric, value = stats$value[[metric]], status = stats$status, coverage = stats$coverage,
        period_start = as.character(as.Date(date) - 29L), period_end = as.character(date),
        comparison_date = if (kind == "change") as.character(as.Date(date) - 14L) else "",
        source_path = s$path, source_md5 = if (file.exists(s$path)) unname(tools::md5sum(s$path)) else "",
        link = paste0("pages/products/", s$product, ".html"), note = note, stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, result)
}

synopsis_station_network_counts <- function(root, date, config, periods = c("7day", "30day", "90day")) {
  path <- file.path(root, "site/stations/station-explorer-data.csv")
  audit_path <- file.path(root, "data/diagnostics/acis-stations/publication-audit/product-readiness.csv")
  empty <- list(facts = data.frame(), members = data.frame(), status = "UNAVAILABLE")
  if (!file.exists(path) || !file.exists(audit_path)) return(empty)
  rows <- utils::read.csv(path, stringsAsFactors = FALSE); audit <- utils::read.csv(audit_path, stringsAsFactors = FALSE)
  base <- c("uid", "sid", "role", "state", "as_of", "cache_as_of", "period", "period_start", "period_days")
  if (!all(base %in% names(rows)) || !all(c("uid", "period", "page_date", "metric", "publication_status") %in% names(audit))) return(empty)
  h <- synopsis_highlight_config(config); members <- list(); facts <- list()
  for (period in periods) for (variable in c("pcpn", "tmean")) {
    fields <- paste0(variable, c("_percentile", "_reference_years", "_status", "_missing_days", "_flagged_days"))
    if (!all(fields %in% names(rows))) next
    x <- rows[which(rows$role == "fixed" & rows$state %in% c("AZ", "NM") & rows$as_of == as.character(date) &
      rows$cache_as_of >= as.character(date) & rows$period == period), , drop = FALSE]
    if (!nrow(x)) next
    # Ambiguous duplicate records are excluded, never counted twice.
    x <- x[!duplicated(x$uid) & !duplicated(x$uid, fromLast = TRUE) &
      !duplicated(x$sid) & !duplicated(x$sid, fromLast = TRUE), , drop = FALSE]
    good <- x[[fields[3]]] == "AVAILABLE" & x[[fields[4]]] == 0 & x[[fields[5]]] == 0 &
      is.finite(x[[fields[1]]]) & x[[fields[1]]] >= 0 & x[[fields[1]]] <= 100 &
      x[[fields[2]]] >= config$minimum_extreme_rank_years &
      x$period_days == as.integer(sub("day", "", period)) &
      x$period_start == as.character(as.Date(date) - as.integer(sub("day", "", period)) + 1L)
    x <- x[which(good), , drop = FALSE]
    eligible <- vapply(seq_len(nrow(x)), function(i) {
      a <- audit[which(audit$uid == x$uid[i] & audit$period == period & audit$page_date == as.character(date) &
        audit$metric == paste0(variable, "_percentile")), , drop = FALSE]
      if (nrow(a) != 1L || !a$publication_status %in% c("DISPLAY", "DISPLAY_CAUTION")) return(FALSE)
      if ("display_value" %in% names(a) && (!is.finite(a$display_value) || abs(a$display_value - x[[fields[1]]][i]) > 1e-6)) return(FALSE)
      # Recheck complete current daily observations, independently of the summary.
      p <- file.path(root, "site/stations/station-details", paste0(x$uid[i], ".json"))
      d <- tryCatch(jsonlite::read_json(p, simplifyVector = TRUE), error = function(e) NULL)
      if (is.null(d) || !identical(as.character(d$uid), as.character(x$uid[i])) || !identical(d$as_of, as.character(date)) || !is.data.frame(d$daily)) return(FALSE)
      days <- as.character(seq(as.Date(x$period_start[i]), as.Date(date), by = "day"))
      d <- d$daily; d <- d[d$date %in% days, , drop = FALSE]; d <- d[order(d$date), , drop = FALSE]
      vars <- if (variable == "pcpn") "pcpn" else c("maxt", "mint")
      if (!identical(as.character(d$date), days) || !all(c(vars, paste0(vars, "_status")) %in% names(d))) return(FALSE)
      for (v in vars) if (!is.numeric(d[[v]]) || any(!is.finite(d[[v]])) || anyNA(d[[paste0(v, "_status")]]) ||
        any(d[[paste0(v, "_status")]] != "AVAILABLE") || any(d[[v]] < if (v == "pcpn") 0 else -150) ||
        any(d[[v]] > if (v == "pcpn") 100 else 150)) return(FALSE)
      variable != "tmean" || all(d$maxt >= d$mint)
    }, logical(1))
    x <- x[eligible, , drop = FALSE]
    if (nrow(x)) {
      detail_paths <- file.path(root, "site/stations/station-details", paste0(x$uid, ".json"))
      members[[length(members) + 1L]] <- data.frame(uid = x$uid, sid = x$sid, state = x$state,
        period = period, variable = variable, percentile = x[[fields[1]]], reference_years = x[[fields[2]]],
        detail_path = detail_paths, detail_md5 = unname(tools::md5sum(detail_paths)), stringsAsFactors = FALSE)
    }
    for (region in c("AZNM", "AZ", "NM")) {
      z <- x[if (region == "AZNM") rep(TRUE, nrow(x)) else x$state == region, , drop = FALSE]
      for (tail in c("high", "low")) {
        count <- sum(if (tail == "high") z[[fields[1]]] > h$station_tail_high else z[[fields[1]]] < h$station_tail_low)
        facts[[length(facts) + 1L]] <- data.frame(fact_id = paste("station-network", region, period, variable, tail, sep = ":"),
          region = region, period = period, variable = variable, tail = tail, count = count, eligible = nrow(z),
          percent = if (nrow(z)) 100 * count/nrow(z) else NA_real_,
          status = if (nrow(z) >= if (region == "AZNM") h$minimum_stations else h$minimum_state_stations) "AVAILABLE_CACHED" else "INSUFFICIENT_STATIONS",
          period_start = as.character(as.Date(date) - as.integer(sub("day", "", period)) + 1L), period_end = as.character(date),
          link = "pages/station-conditions.html", source_path = path, source_md5 = unname(tools::md5sum(path)), stringsAsFactors = FALSE)
      }
    }
  }
  list(facts = if (length(facts)) do.call(rbind, facts) else data.frame(),
    members = if (length(members)) do.call(rbind, members) else data.frame(), status = "CHECKED",
    audit_path = audit_path, audit_md5 = unname(tools::md5sum(audit_path)))
}

synopsis_regional_candidates <- function(evidence) {
  packet <- evidence$regional_highlights
  if (is.null(packet)) return(list())
  h <- synopsis_highlight_config(evidence$configuration); candidates <- list()
  add <- function(text, ids, links, score, phrase, tone, kind) {
    candidates[[length(candidates) + 1L]] <<- list(section = "Past 30 days", text = text, fact_ids = ids, links = links,
      score = score, kind = kind, emphasis = list(list(text = phrase, tone = tone, strong = FALSE)))
  }
  grids <- packet$grids
  if (nrow(grids)) for (i in seq_len(nrow(grids))) {
    x <- grids[i, ]; if (x$status != "AVAILABLE_CACHED" || !is.finite(x$value) || x$value < h$minimum_area_percent || x$metric == "mean_days") next
    region <- switch(x$region, AZNM = "Arizona and New Mexico", AZ = "Arizona", NM = "New Mexico")
    if (x$metric == "area_extreme_days") {
      warm <- grepl("warm", x$product); phrase <- sprintf("%.0f%% of %s had at least %d %s", x$value, region, h$extreme_count_days, if (warm) "warm days" else "cold nights")
      text <- paste0("During ", synopsis_date_range(x$period_start, x$period_end), ", ", phrase,
        if (warm) " with maximum temperatures above" else " with minimum temperatures below", " their date-specific ",
        if (warm) "90th" else "10th", " percentile thresholds (", packet$normal_reference, "; centered ", packet$centered_window_days,
        "-day reference). This counts threshold exceedances, not the historical rank of the 30-day count.")
      add(text, x$fact_id, x$link, x$value/100, phrase, if (warm) "warm" else "cold", "persistence")
    } else {
      up <- x$metric == "area_rank_increased"; phrase <- sprintf("%.0f%% of %s", x$value, region)
      text <- sprintf("The 30-day precipitation percentile rank %s by at least %g percentile points across %s between %s. This rolling-window shift includes new precipitation, older days leaving the window and possible source revisions.",
        if (up) "increased" else "decreased", h$rank_change_points, phrase, synopsis_date_range(x$comparison_date, x$period_end))
      add(text, x$fact_id, x$link, x$value/100, phrase, if (up) "wet" else "dry", "transition")
    }
  }
  network <- packet$stations$facts
  if (nrow(network)) for (i in seq_len(nrow(network))) {
    x <- network[i, ]; if (x$period != "30day" || x$status != "AVAILABLE_CACHED" || !is.finite(x$percent) || x$percent < h$minimum_station_fraction_percent) next
    region <- switch(x$region, AZNM = "AZ and NM", AZ = "Arizona", NM = "New Mexico")
    high <- x$tail == "high"; phrase <- sprintf("%d of %d eligible fixed stations", x$count, x$eligible)
    text <- sprintf("During %s, %s in %s (%.0f%%) had %s %s the %gth percentile for their matching historical periods. ThreadEx series are excluded; station counts are not regional land-area percentages.",
      synopsis_date_range(x$period_start, x$period_end), phrase, region, x$percent,
      if (x$variable == "pcpn") "precipitation totals" else "mean temperatures", if (high) "above" else "below",
      if (high) h$station_tail_high else h$station_tail_low)
    tone <- if (x$variable == "pcpn") if (high) "wet" else "dry" else if (high) "warm" else "cold"
    add(text, x$fact_id, x$link, x$percent/100, phrase, tone, "corroboration")
  }
  # Prefer broad combined-area evidence on equal scores; state signals can win
  # when stronger. Scores measure spatial/network breadth, not impact severity.
  candidates[order(-vapply(candidates, function(x) x$score, numeric(1)))]
}
