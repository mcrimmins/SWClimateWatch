# Historical comparisons from local station caches only. One complete matching
# window per earlier endpoint year; never use current-year or future samples.
synopsis_station_window_statistics <- function(daily, endpoints, days) {
  if (!inherits(daily$date, "Date") || anyDuplicated(daily[c("date", "variable")])) stop("Invalid daily station history.")
  endpoints <- as.Date(endpoints)
  dates <- outer(as.numeric(endpoints), seq.int(-days + 1L, 0L), "+")
  matrices <- list()
  for (variable in c("pcpn", "maxt", "mint")) {
    x <- daily[daily$variable == variable, , drop = FALSE]
    index <- match(as.vector(dates), as.numeric(x$date))
    good <- !is.na(x$observed) & x$observed & is.finite(x$numeric_value) &
      (is.na(x$flag) | x$flag == "" | (variable == "pcpn" & x$flag == "T"))
    if (variable == "pcpn") good <- good & (is.na(x$accumulated) | !x$accumulated) &
      x$numeric_value >= 0 & x$numeric_value <= 100 else good <- good & abs(x$numeric_value) <= 150
    values <- x$numeric_value[index]
    values[is.na(index) | is.na(good[index]) | !good[index]] <- NA_real_
    matrices[[variable]] <- matrix(values, nrow = length(endpoints), ncol = days)
  }
  inversion <- is.finite(matrices$maxt) & is.finite(matrices$mint) & matrices$maxt < matrices$mint
  matrices$maxt[inversion] <- matrices$mint[inversion] <- NA_real_
  result <- data.frame(end_date = as.character(endpoints), year = as.integer(format(endpoints, "%Y")))
  complete <- function(m, fun) {
    ok <- rowSums(is.finite(m)) == days
    output <- rep(NA_real_, nrow(m))
    if (any(ok)) output[ok] <- apply(m[ok, , drop = FALSE], 1L, fun)
    output
  }
  result$max_daily_pcpn <- complete(matrices$pcpn, max)
  result$max_3day_pcpn <- complete(matrices$pcpn, function(x) max(x[-c(1, 2)] +
    x[-c(1, length(x))] + x[-c(length(x)-1L, length(x))]))
  result$hottest_day <- complete(matrices$maxt, max)
  result$coldest_night <- complete(matrices$mint, min)
  result$longest_dry_spell <- complete(matrices$pcpn, function(x) {
    run <- rle(x < 0.04)
    if (any(run$values)) max(run$lengths[run$values]) else 0
  })
  result
}

synopsis_context_statistics <- function(current, historical, metric, config) {
  valid <- historical[is.finite(historical[[metric]]), , drop = FALSE]
  values <- valid[[metric]]
  n <- length(values)
  normal_values <- values[valid$year %in% 1991:2020]
  normal <- if (length(normal_values) >= config$minimum_extreme_normal_years) mean(normal_values) else NA_real_
  rank <- percentile <- unusual <- NA_real_
  direction <- if (metric == "coldest_night") "lowest" else "highest"
  if (is.finite(current) && n >= config$minimum_extreme_rank_years) {
    equal <- abs(values - current) < 1e-7
    percentile <- 100 * (sum(values < current & !equal) + .5*sum(equal))/n
    unusual <- if (metric == "coldest_night") 100 - percentile else percentile
    rank <- 1L + if (metric == "coldest_night") sum(values < current & !equal) else sum(values > current & !equal)
  }
  list(context_status = if (is.finite(rank)) "SUPPORTED" else "INSUFFICIENT_REFERENCE",
    historical_rank = rank, historical_n = n,
    historical_first_year = if (n) min(valid$year) else NA_real_,
    historical_last_year = if (n) max(valid$year) else NA_real_,
    historical_ties = if (is.finite(current)) 1L + sum(abs(values - current) < 1e-7) else NA_real_,
    rank_direction = direction, historical_percentile = percentile, unusual_percentile = unusual,
    context_normal = normal, context_normal_years = length(normal_values),
    peak_anomaly = if (is.finite(current) && is.finite(normal)) current - normal else NA_real_)
}

synopsis_add_station_context <- function(packet, root, date, config, cache_dir) {
  if (!nrow(packet$candidates)) return(packet)
  paths <- file.path(root, "data/processed/acis-stations/reference-network/daily",
    paste0(sort(unique(packet$candidates$uid)), ".rds"))
  signature <- digest::digest(list(version = 2L, packet = packet, date = date,
    raw_paths = paths, raw_md5 = unname(tools::md5sum(paths)),
    min_rank = config$minimum_extreme_rank_years, min_normal = config$minimum_extreme_normal_years))
  packet_path <- file.path(cache_dir, paste0("packet-", paste(unique(packet$candidates$window_days), collapse = "-"), ".rds"))
  previous_packet <- if (file.exists(packet_path)) tryCatch(readRDS(packet_path), error = function(e) NULL) else NULL
  if (identical(previous_packet$signature, signature)) return(previous_packet$packet)
  packet_signature <- signature
  required <- c("date", "variable", "numeric_value", "observed", "flag", "accumulated")
  defaults <- synopsis_context_statistics(NA_real_, data.frame(year = integer(), value = numeric()), "value", config)
  for (field in names(defaults)) packet$candidates[[field]] <- defaults[[field]]
  packet$candidates$reference_signature <- NA_character_
  packet$candidates$context_reason <- "Historical station cache unavailable."
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  year <- as.integer(format(date, "%Y"))
  for (uid in unique(packet$candidates$uid)) {
    indices <- which(packet$candidates$uid == uid)
    archive <- file.path(root, "data/processed/acis-stations/reference-network/daily", paste0(uid, ".rds"))
    raw <- if (file.exists(archive)) tryCatch(readRDS(archive), error = function(e) NULL) else NULL
    if (is.null(raw) || !identical(raw$schema_version, 1L) || !identical(as.integer(raw$uid), as.integer(uid)) ||
        !inherits(raw$as_of, "Date") || length(raw$as_of) != 1L || is.na(raw$as_of) || raw$as_of < date || !is.data.frame(raw$daily) ||
        !all(required %in% names(raw$daily)) || !inherits(raw$daily$date, "Date")) next
    for (days in unique(packet$candidates$window_days[indices])) {
      ix <- indices[packet$candidates$window_days[indices] == days & packet$candidates$metric[indices] != "freeze_nights_anomaly"]
      if (!length(ix)) next
      historic <- raw$daily[raw$daily$date < as.Date(sprintf("%d-01-01", year)), , drop = FALSE]
      signature <- digest::digest(list(version = 1L, uid = uid, sid = raw$sid, year = year,
        month_day = format(date, "%m-%d"), days = days, daily = historic,
        min_rank = config$minimum_extreme_rank_years, min_normal = config$minimum_extreme_normal_years))
      path <- file.path(cache_dir, paste0(uid, "-", days, "day.rds"))
      previous <- if (file.exists(path)) tryCatch(readRDS(path), error = function(e) NULL) else NULL
      history <- tryCatch({
        if (identical(previous$signature, signature)) previous$history else {
          first_year <- as.integer(format(min(raw$daily$date), "%Y"))
          years <- if (first_year < year) seq.int(first_year, year - 1L) else integer()
          ends <- as.Date(sprintf("%04d-%s", years, format(date, "%m-%d")), format = "%Y-%m-%d")
          # No fabricated February 29 in non-leap reference years.
          ends <- ends[!is.na(ends)]
          result <- synopsis_station_window_statistics(raw$daily, ends, days)
          saveRDS(list(signature = signature, history = result), path)
          result
        }
      }, error = function(e) NULL)
      current <- tryCatch(synopsis_station_window_statistics(raw$daily, date, days), error = function(e) NULL)
      if (is.null(history) || is.null(current)) next
      for (i in ix) {
        metric <- packet$candidates$metric[i]
        if (!is.finite(current[[metric]]) || abs(current[[metric]] - packet$candidates$value[i]) > 1e-6) {
          packet$candidates$context_reason[i] <- "Current daily cache does not match the screened summary."
          next
        }
        stats <- synopsis_context_statistics(packet$candidates$value[i], history, metric, config)
        for (field in names(stats)) packet$candidates[[field]][i] <- stats[[field]]
        packet$candidates$reference_signature[i] <- signature
        packet$candidates$context_reason[i] <- if (stats$context_status == "SUPPORTED")
          "Complete matching windows from earlier endpoint years; current period counted once in displayed rank." else
          "Too few complete historical windows for an extreme ranking."
      }
    }
  }
  freeze <- packet$candidates$metric == "freeze_nights_anomaly"
  packet$candidates$context_status[freeze] <- "SEASONAL_DEPARTURE"
  packet$candidates$context_normal[freeze] <- packet$candidates$normal[freeze]
  packet$candidates$context_normal_years[freeze] <- packet$candidates$sample_years[freeze]
  packet$candidates$peak_anomaly[freeze] <- packet$candidates$value[freeze]
  packet$candidates$context_reason[freeze] <- "Existing screened seasonal comparison, with stated complete-year support."
  packet$selected <- packet$candidates[match(packet$selected$fact_id, packet$candidates$fact_id), , drop = FALSE]
  saveRDS(list(signature = packet_signature, packet = packet), packet_path)
  packet
}
