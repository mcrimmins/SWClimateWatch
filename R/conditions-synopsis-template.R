# Deterministic synopsis. Claims carry evidence identifiers and dated support.
.synopsis_source_files <- Filter(function(x)is.character(x)&&length(x)==1L&&grepl("conditions-synopsis-template[.]R$",x),
  lapply(sys.frames(),function(frame)if(!is.null(frame$ofile))frame$ofile else frame$file))
.synopsis_module_dir <- dirname(tail(.synopsis_source_files,1)[[1]])
source(file.path(.synopsis_module_dir,"conditions-synopsis-snow.R"),local=TRUE)
source(file.path(.synopsis_module_dir,"conditions-synopsis-support.R"),local=TRUE)
rm(.synopsis_source_files,.synopsis_module_dir)

synopsis_format_settings <- function(config) {
  defaults <- list(enabled = TRUE, temperature_color_f = 3, temperature_strong_f = 6,
    exceptional_station_percentile = 98, freeze_strong_departure_nights = 10,
    colors = list(wet = "#11685D", dry = "#87501C", warm = "#A34618", cold = "#235FA0"))
  x <- utils::modifyList(defaults, config$formatting %||synopsis% list())
  if (!is.logical(x$enabled) || length(x$enabled) != 1L || is.na(x$enabled)) stop("Invalid synopsis formatting enabled setting.")
  for (field in c("temperature_color_f", "temperature_strong_f", "exceptional_station_percentile", "freeze_strong_departure_nights"))
    if (!is.numeric(x[[field]]) || length(x[[field]]) != 1L || !is.finite(x[[field]]) || x[[field]] <= 0) stop("Invalid synopsis formatting threshold: ", field)
  if (x$temperature_strong_f < x$temperature_color_f || x$exceptional_station_percentile > 100 ||
      x$exceptional_station_percentile < config$unusual_station_percentile) stop("Invalid synopsis formatting threshold order.")
  if (any(!vapply(x$colors, function(color) is.character(color) && length(color) == 1L && grepl("^#[0-9A-Fa-f]{6}$", color), logical(1))))
    stop("Synopsis colors must be six-digit hex colors.")
  x
}

`%||synopsis%` <- function(x, y) if (is.null(x)) y else x

synopsis_escape_html <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE); x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE); gsub('"', "&quot;", x, fixed = TRUE)
}

# Presentation is derived from the exact supporting facts, never from a keyword's
# direction alone. Plain prose and evidence identifiers remain unchanged.
synopsis_emphasis <- function(block, evidence, stations, settings) {
  spans <- list()
  add <- function(text, tone = "neutral", strong = FALSE) {
    if (length(text) == 1L && nzchar(text) && grepl(text, block$text, fixed = TRUE))
      spans[[length(spans) + 1L]] <<- list(text = text, tone = tone, strong = strong)
  }
  if (!settings$enabled) return(spans)
  if (!is.null(block$kind) && (block$kind %in% c("persistence", "transition", "corroboration") || startsWith(block$kind,"snow_"))) return(block$emphasis)
  station <- stations[stations$fact_id %in% block$fact_ids, , drop = FALSE]
  if (nrow(station)) {
    x <- station[1L, ]
    tone <- switch(x$metric, max_daily_pcpn = "wet", max_3day_pcpn = "wet", longest_dry_spell = "dry",
      hottest_day = "warm", coldest_night = "cold", freeze_nights_anomaly = if (x$value < 0) "warm" else "cold")
    supported <- "context_status" %in% names(x) && x$context_status == "SUPPORTED" &&
      is.finite(x$unusual_percentile) && x$unusual_percentile >= evidence$configuration$unusual_station_percentile
    strong <- supported && x$unusual_percentile >= settings$exceptional_station_percentile
    if (x$metric == "freeze_nights_anomaly") {
      supported <- x$context_status == "SEASONAL_DEPARTURE" && x$sample_years >= evidence$configuration$minimum_freeze_normal_years
      strong <- supported && abs(x$value) >= settings$freeze_strong_departure_nights
      add(sprintf("%.0f freeze nights", x$observed))
      add(sprintf("%.1f %s", abs(x$value), if (x$value < 0) "fewer" else "more"), if (supported) tone else "neutral", strong)
    } else {
      amount <- switch(x$metric, max_daily_pcpn = sprintf("%.2f inches", x$value), max_3day_pcpn = sprintf("%.2f inches", x$value),
        longest_dry_spell = sprintf("%.0f consecutive days", x$value), sprintf("%.0f\u00b0F", x$value))
      add(amount, if (supported) tone else "neutral", strong)
      rank <- regmatches(block$text, regexpr("(is (tied for )?the |ranks (tied for )?[0-9]+(st|nd|rd|th) )(highest|lowest|longest) among [0-9]+ matching [0-9]+-day periods", block$text))
      if (length(rank)) add(rank, if (supported) tone else "neutral", strong)
    }
  } else {
    facts <- rbind(evidence$facts, evidence$recent$facts)
    facts <- facts[facts$fact_id %in% block$fact_ids & facts$status == "AVAILABLE_CACHED", , drop = FALSE]
    temps <- facts[facts$metric == "mean_departure", , drop = FALSE]
    if (nrow(temps)) {
      contrast <- grepl("Mean temperatures contrasted", block$text, fixed = TRUE)
      temps <- temps[temps$region %in% if (contrast) c("AZ", "NM") else "AZNM", , drop = FALSE]
      for (i in seq_len(nrow(temps))) {
        v <- temps$value[i]
        if (abs(v) >= .05) add(sprintf("%.1f\u00b0F %s", abs(v), if (v < 0) "below" else "above"),
          if (abs(v) >= settings$temperature_color_f) if (v < 0) "cold" else "warm" else "neutral",
          abs(v) >= settings$temperature_strong_f)
      }
    } else {
      for (metric in c("area_above_upper_percentile", "area_below_lower_percentile")) {
        x <- facts[facts$region == "AZNM" & facts$metric == metric, , drop = FALSE]
        if (nrow(x) == 1L) {
          v <- x$value; pct <- if (v > 0 && v < 1) "<1%" else if (v > 99 && v < 100) ">99%" else sprintf("%.0f%%", v)
          add(sprintf("%s %s percentile %g", pct, if (grepl("above", metric)) "of the area was above" else "below", x$threshold),
            if (v > 0) if (grepl("above", metric)) "wet" else "dry" else "neutral")
        }
      }
      if (!length(spans)) {
        x <- facts[facts$region == "AZNM" & facts$metric == "mean", , drop = FALSE]
        if (nrow(x) == 1L) add(sprintf("%.2f inches", x$value))
      }
    }
    # Changes describe a separate comparison, with a direction-specific tone.
    changes <- block$changes
    if (length(changes)) {
      x <- changes[[1L]]
      tone <- if (x$units == "degreeF") if (x$difference < 0) "cold" else "warm" else {
        wetter <- grepl("above", x$fact_id) == (x$difference > 0)
        if (wetter) "wet" else "dry"
      }
      phrase <- sprintf("%.1f %s %s", abs(x$difference), if (x$units == "degreeF") "\u00b0F" else "percentage points", if (x$difference > 0) "higher" else "lower")
      if (x$units == "degreeF") phrase <- sub(" ", "", phrase, fixed = TRUE)
      if (length(spans) > 1L) spans <- spans[1L]
      add(phrase, tone, TRUE)
    }
  }
  head(spans, 2L)
}

synopsis_format_text <- function(text, spans, html = TRUE) {
  if (!length(spans)) return(if (html) synopsis_escape_html(text) else text)
  # Insert markup into escaped fragments once, avoiding nested replacements.
  positions <- lapply(spans, function(s) {p <- regexpr(s$text, text, fixed = TRUE); c(start = as.integer(p), end = as.integer(p) + attr(p, "match.length") - 1L)})
  ordering <- order(vapply(positions, function(p) p[["start"]], integer(1)))
  result <- ""; cursor <- 1L
  esc <- if (html) synopsis_escape_html else identity
  for (i in ordering) {
    p <- positions[[i]]; s <- spans[[i]]
    if (p[["start"]] < cursor) next
    prefix <- if (p[["start"]] > cursor) substr(text, cursor, p[["start"]] - 1L) else ""
    value <- esc(substr(text, p[["start"]], p[["end"]]))
    mark <- if (!html) paste0("**", value, "**") else if (s$tone == "neutral" || s$strong)
      paste0('<strong class="signal-', s$tone, '">', value, '</strong>') else paste0('<span class="signal-', s$tone, '">', value, '</span>')
    result <- paste0(result, esc(prefix), mark); cursor <- p[["end"]] + 1L
  }
  paste0(result, esc(substr(text, cursor, nchar(text))))
}

synopsis_date_text <- function(date, year = TRUE, short = FALSE) {
  date <- as.Date(date)
  months <- if (short) month.abb else month.name
  paste0(months[as.integer(format(date, "%m"))], " ", as.integer(format(date, "%d")),
    if (year) paste0(", ", format(date, "%Y")) else "")
}

synopsis_date_range <- function(start, end) {
  start <- as.Date(start); end <- as.Date(end)
  if (start == end) return(synopsis_date_text(end))
  if (format(start, "%Y-%m") == format(end, "%Y-%m"))
    return(paste0(synopsis_date_text(start, year = FALSE, short = TRUE), "\u2013",
      as.integer(format(end, "%d")), ", ", format(end, "%Y")))
  paste0(synopsis_date_text(start, year = format(start, "%Y") != format(end, "%Y"), short = TRUE),
    "\u2013", synopsis_date_text(end, short = TRUE))
}

synopsis_ordinal <- function(n) {
  suffix <- if (n %% 100 %in% 11:13) "th" else switch(as.character(n %% 10), "1" = "st", "2" = "nd", "3" = "rd", "th")
  paste0(n, suffix)
}

synopsis_generated_text <- function(stamp) {
  time <- as.POSIXct(stamp, format = "%Y-%m-%d %H:%M:%S UTC", tz = "UTC")
  if (length(time) != 1L || is.na(time)) return(stamp)
  paste0(synopsis_date_text(as.Date(time, tz = "America/Phoenix"), short = TRUE), " at ",
    sub("^0", "", format(time, "%I:%M %p", tz = "America/Phoenix")), " Arizona time")
}

synopsis_station_sentence <- function(x) {
  same_year <- format(as.Date(x$event_end), "%Y") == format(as.Date(x$period_end), "%Y")
  event <- if (x$event_start == x$event_end) synopsis_date_text(x$event_end, year = !same_year) else synopsis_date_range(x$event_start, x$event_end)
  label <- paste0(x$name, " (", x$state, ")")
  window <- if ("window_days" %in% names(x)) x$window_days else 30L
  text <- switch(x$metric,
    max_daily_pcpn = sprintf("%s recorded %.2f inches on %s, its largest daily total within the selected %d days.", label, x$value, event, window),
    max_3day_pcpn = sprintf("%s recorded %.2f inches during %s, its largest three-day total within the selected %d days.", label, x$value, event, window),
    hottest_day = sprintf("%s reached %.0f\u00b0F on %s, its highest daily maximum within the selected %d days.", label, x$value, event, window),
    coldest_night = sprintf("%s fell to %.0f\u00b0F on %s, its lowest daily minimum within the selected %d days.", label, x$value, event, window),
    longest_dry_spell = sprintf("%s had %.0f consecutive days with less than 0.04 inch of daily precipitation during %s, its longest such run within the past %d days.", label, x$value, event, window),
    freeze_nights_anomaly = sprintf("%s had %.0f freeze nights during %s: %.1f %s than its 1991\u20132020 mean of %.1f nights (%d usable reference years).", label,
      x$observed, event, abs(x$value), if (x$value < 0) "fewer" else "more", x$normal, x$sample_years))
  if ("context_status" %in% names(x) && x$context_status == "SUPPORTED") {
    if (x$metric != "longest_dry_spell") text <- switch(x$metric,
      max_daily_pcpn = sprintf("%s received %.2f inches of precipitation on %s.", label, x$value, event),
      max_3day_pcpn = sprintf("%s received %.2f inches of precipitation during %s.", label, x$value, event),
      hottest_day = sprintf("%s reached %.0f\u00b0F on %s.", label, x$value, event),
      coldest_night = sprintf("%s fell to %.0f\u00b0F on %s.", label, x$value, event))
    label_metric <- switch(x$metric, max_daily_pcpn = "The weekly wettest-day amount", max_3day_pcpn = "The weekly three-day maximum",
      hottest_day = "The weekly high", coldest_night = "The weekly low", longest_dry_spell = "The within-window dry spell")
    # Rank denominator includes the current observation exactly once.
    direction <- if (x$metric == "longest_dry_spell") "longest" else x$rank_direction
    ranking <- if (x$historical_rank == 1) paste0("is ", if (x$historical_ties > 1) "tied for " else "", "the ", direction) else
      paste0("ranks ", if (x$historical_ties > 1) "tied for " else "", synopsis_ordinal(x$historical_rank), " ", direction)
    text <- paste0(text, sprintf(" %s %s among %d matching %d-day periods (%d\u2013%d, plus this period).",
      label_metric, ranking,
      x$historical_n + 1L, window, x$historical_first_year, x$historical_last_year))
    if (x$metric %in% c("hottest_day", "coldest_night") && is.finite(x$peak_anomaly) && abs(x$peak_anomaly) >= .05)
      text <- paste0(text, sprintf(" It was %.1f\u00b0F %s the 1991\u20132020 average for the %s (%d complete reference years).",
        abs(x$peak_anomaly), if (x$peak_anomaly < 0) "below" else "above",
        if (x$metric == "hottest_day") "weekly high" else "weekly low", x$context_normal_years))
  }
  text
}

synopsis_event_keys <- function(candidates) {
  if (is.null(candidates) || !nrow(candidates)) return(character())
  paste(candidates$uid, candidates$metric, candidates$event_start, candidates$event_end, sep = ":")
}

synopsis_unusual_candidates <- function(x, config) {
  if (is.null(x) || !nrow(x) || !all(c("context_status", "unusual_percentile") %in% names(x))) return(data.frame())
  keep <- x$context_status == "SUPPORTED" & is.finite(x$unusual_percentile) & x$unusual_percentile >= config$unusual_station_percentile
  keep <- keep & (x$metric != "max_daily_pcpn" | x$value >= config$minimum_impact_daily_rain_inches) &
    (x$metric != "max_3day_pcpn" | x$value >= config$minimum_impact_three_day_rain_inches) &
    (x$metric != "longest_dry_spell" | x$value >= config$minimum_dry_spell_days)
  x[which(keep), , drop = FALSE]
}

synopsis_week_profile <- function(evidence) {
  config <- evidence$configuration
  recent <- evidence$recent
  facts <- if (!is.null(recent)) recent$facts else data.frame()
  value <- function(product, region) {
    if (!nrow(facts)) return(NA_real_)
    x <- facts[facts$product == product & facts$region == region & facts$status == "AVAILABLE_CACHED" &
      facts$metric %in% c("mean", "mean_departure"), , drop = FALSE]
    if (nrow(x) == 1L) x$value else NA_real_
  }
  rain <- value("pcpn_total_07day", "AZNM")
  temperatures <- vapply(c("AZNM", "AZ", "NM"), function(r) value("tmean_departure_07day", r), numeric(1))
  unusual <- synopsis_unusual_candidates(evidence$station_week$candidates, config)
  metrics <- unusual$metric
  rainy <- any(metrics %in% c("max_daily_pcpn", "max_3day_pcpn")) || (is.finite(rain) && rain >= .25)
  hot <- any(temperatures >= config$active_week_temperature_departure_f, na.rm = TRUE) || any(metrics == "hottest_day")
  cold <- any(temperatures <= -config$active_week_temperature_departure_f, na.rm = TRUE) || any(metrics == "coldest_night")
  mode <- if (sum(c(rainy, hot, cold)) > 1L) "mixed" else if (rainy) "rainfall" else if (hot) "heat" else if (cold) "cold" else
    if (is.finite(rain) && is.finite(temperatures[["AZNM"]]) && rain < .1 && abs(temperatures[["AZNM"]]) < config$quiet_week_temperature_departure_f) "longer_term" else "uncertain"
  list(mode = mode, rainfall = rainy, heat = hot, cold = cold,
    station_precipitation_focus = is.finite(rain) && rain < .25 && any(metrics %in% c("max_daily_pcpn", "max_3day_pcpn")),
    note = "Editorial focus from supported regional signals and unusual station comparisons; not a hazard or impact classification.")
}

synopsis_select_highlights <- function(evidence, comparison = NULL) {
  config <- evidence$configuration
  profile <- synopsis_week_profile(evidence)
  limit <- config$maximum_station_examples
  week <- synopsis_unusual_candidates(evidence$station_week$candidates, config)
  previous <- if (!is.null(comparison)) synopsis_unusual_candidates(comparison$week_candidates, config) else data.frame()
  if (nrow(week)) {
    if (profile$mode == "rainfall") week <- week[week$family == "rainfall", , drop = FALSE]
    if (profile$mode == "heat") week <- week[week$metric == "hottest_day", , drop = FALSE]
    if (profile$mode == "cold") week <- week[week$metric == "coldest_night", , drop = FALSE]
    if (!is.null(comparison)) week <- week[!synopsis_event_keys(week) %in% synopsis_event_keys(previous), , drop = FALSE]
    order_ids <- unlist(config$station_metric_order[[evidence$season$id]])
    magnitude <- ifelse(week$metric == "coldest_night", week$value, -week$value)
    week <- week[order(-week$unusual_percentile, match(week$metric, order_ids), magnitude, -week$historical_n, week$uid), , drop = FALSE]
  }
  selected <- week[FALSE, , drop = FALSE]
  budget <- if (profile$mode == "mixed") min(1L, limit) else limit
  choose <- function(pool, used) {
    if (!nrow(pool)) return(pool)
    if (nrow(used)) {
      pool <- pool[!pool$uid %in% used$uid, , drop = FALSE]
      if (!nrow(pool)) return(pool)
      # Geography/family preferences break near-ties, not large rarity differences.
      near <- pool
      if ("unusual_percentile" %in% names(pool) && any(is.finite(pool$unusual_percentile))) {
        cutoff <- max(pool$unusual_percentile, na.rm = TRUE) - 5
        near <- pool[which(pool$unusual_percentile >= cutoff), , drop = FALSE]
      }
      if (any(!near$family %in% used$family)) near <- near[!near$family %in% used$family, , drop = FALSE]
      if (any(!near$state %in% used$state)) near <- near[!near$state %in% used$state, , drop = FALSE]
      pool <- near
    }
    pool[1L, , drop = FALSE]
  }
  for (i in seq_len(budget)) {
    pick <- choose(week, selected)
    if (!nrow(pick)) break
    selected <- rbind(selected, pick)
  }
  seasonal <- evidence$station_extremes$candidates
  dry <- synopsis_unusual_candidates(seasonal, config)
  if (nrow(dry)) dry <- dry[dry$metric == "longest_dry_spell", , drop = FALSE]
  freeze <- if (nrow(seasonal)) seasonal[seasonal$metric == "freeze_nights_anomaly", , drop = FALSE] else data.frame()
  if (nrow(freeze)) freeze <- freeze[order(-abs(freeze$value), freeze$uid), , drop = FALSE]
  if (nrow(dry)) dry <- dry[order(-dry$unusual_percentile, dry$uid), , drop = FALSE]
  pool <- if (evidence$season$id %in% c("winter", "fall")) rbind(freeze, dry) else rbind(dry, freeze)
  long <- pool[FALSE, , drop = FALSE]
  for (i in seq_len(max(0L, limit - nrow(selected)))) {
    used <- rbind(selected, long)
    pick <- choose(pool[!pool$metric %in% long$metric, , drop = FALSE], used)
    if (!nrow(pick)) break
    long <- rbind(long, pick)
  }
  list(week = selected, seasonal = long, profile = profile)
}

synopsis_comparison_context <- function(evidence, state) {
  # Local preview history is never a successful-publication marker.
  date <- evidence$snapshot_date
  policy <- digest::digest(list(version = 2L, evidence$configuration))
  snapshot <- list(snapshot_date = date, policy = policy, facts = evidence$facts,
    week_candidates = if (!is.null(evidence$station_week)) evidence$station_week$candidates else data.frame())
  valid <- is.list(state) && identical(state$kind, "local_preview") && is.list(state$latest) &&
    is.data.frame(state$latest$facts) && is.character(state$latest$snapshot_date) && length(state$latest$snapshot_date) == 1L &&
    !is.na(state$latest$snapshot_date)
  if (valid && date < state$latest$snapshot_date) return(list(previous = NULL, state = state, write = FALSE))
  if (!valid || !identical(state$latest$policy, policy))
    return(list(previous = NULL, state = list(kind = "local_preview", latest = snapshot, previous = NULL), write = TRUE))
  if (date < state$latest$snapshot_date) return(list(previous = NULL, state = state, write = FALSE))
  previous <- if (date == state$latest$snapshot_date) state$previous else state$latest
  if (!is.null(previous)) {
    wy <- function(d) paste0(as.integer(substr(d, 1, 4)) + as.integer(substr(d, 6, 10) >= "10-01"))
    if (wy(previous$snapshot_date) != wy(date)) previous <- NULL
  }
  list(previous = previous, state = list(kind = "local_preview", latest = snapshot, previous = previous), write = TRUE)
}

synopsis_template_blocks <- function(evidence, extremes, comparison = NULL, regional_candidates = list()) {
  facts <- evidence$facts
  if (!is.null(evidence$recent) && nrow(evidence$recent$facts)) facts <- rbind(facts, evidence$recent$facts)
  fact <- function(product, region, metric, source = facts) {
    x <- source[source$product == product & source$region == region & source$metric == metric &
      source$status == "AVAILABLE_CACHED" & is.finite(source$value), , drop = FALSE]
    if (nrow(x) == 1L) x else NULL
  }
  blocks <- list()
  percent <- function(value) {
    if (value > 0 && value < 1) "<1%" else if (value > 99 && value < 100) ">99%" else sprintf("%.0f%%", value)
  }
  add <- function(section, text, sources = list(), ids = character()) {
    sources <- Filter(Negate(is.null), sources)
    blocks[[length(blocks) + 1L]] <<- list(section = section, text = text,
      fact_ids = unique(c(ids, unlist(lapply(sources, function(x) x$fact_id)))),
      links = unique(unlist(lapply(sources, function(x) x$link))))
  }
  changes <- list()
  change <- function(current) {
    if (is.null(current) || is.null(comparison)) return("")
    prior <- fact(current$product, current$region, current$metric, comparison$facts)
    if (is.null(prior) || !identical(current$reference, prior$reference) ||
        !identical(current$units, prior$units) || !identical(current$mask_version, prior$mask_version) ||
        !identical(current$threshold, prior$threshold)) return("")
    delta <- current$value - prior$value
    area <- grepl("^area_", current$metric)
    minimum <- if (area) evidence$configuration$material_area_change_points else evidence$configuration$material_temperature_change_f
    if (abs(delta) < minimum) return("")
    changes[[length(changes) + 1L]] <<- list(fact_id = current$fact_id, prior_date = comparison$snapshot_date,
      previous_value = prior$value, value = current$value, difference = delta,
      units = if (area) "percentage points" else "degreeF", previous_fact = prior)
    if (area) sprintf(" The area %s percentile %g is %.1f percentage points %s than in the local comparison dated %s.",
      if (grepl("above", current$metric)) "above" else "below", current$threshold, abs(delta),
      if (delta > 0) "higher" else "lower", synopsis_date_text(comparison$snapshot_date, short = TRUE)) else
      sprintf(" The departure is %.1f\u00b0F %s than in the local comparison dated %s.", abs(delta),
        if (delta > 0) "higher" else "lower", synopsis_date_text(comparison$snapshot_date, short = TRUE))
  }
  highlights <- synopsis_select_highlights(evidence, comparison)
  for (product in c("pcpn_total_07day", "pcpn_total_30day", "pcpn_water_year_total")) {
    if (product == "pcpn_total_07day" && !highlights$profile$rainfall && (highlights$profile$heat || highlights$profile$cold) &&
        !is.null(fact("tmean_departure_07day", "AZNM", "mean_departure"))) next
    section <- switch(product, pcpn_total_07day = "Past 7 days", pcpn_total_30day = "Past 30 days", "Water year so far")
    amount <- fact(product, "AZNM", "mean")
    az <- fact(product, "AZ", "mean"); nm <- fact(product, "NM", "mean")
    if (!is.null(amount)) {
      text <- sprintf("During %s, precipitation averaged %.2f inches across Arizona and New Mexico", synopsis_date_range(amount$period_start, amount$period_end), amount$value)
      if (!is.null(az) && !is.null(nm)) text <- paste0(text, sprintf(" (Arizona %.2f; New Mexico %.2f)", az$value, nm$value))
      text <- paste0(text, ".")
      sources <- list(amount, az, nm)
      if (product == "pcpn_total_07day") {
        days <- evidence$recent$days
        if (nrow(days)) {
          days <- days[which(days$region == "AZNM" & days$status == "AVAILABLE_CACHED" &
            is.finite(days$mean_inches) & days$mean_inches > 0), , drop = FALSE]
          if (nrow(days)) {
            newly_available <- FALSE
            if (!is.null(comparison)) {
              new_days <- days[which(days$date > comparison$snapshot_date &
                (days$mean_inches >= evidence$configuration$minimum_weekly_daily_rain_inches |
                 days$rain_area_percent >= evidence$configuration$minimum_recent_rain_area_percent)), , drop = FALSE]
              if (nrow(new_days)) {days <- new_days; newly_available <- TRUE}
            }
            day <- days[order(-days$mean_inches, days$date), , drop = FALSE][1L, ]
            label <- if (newly_available) paste0("Among newly available days since ", synopsis_date_text(comparison$snapshot_date, short = TRUE), ", the largest daily regional mean") else "The largest daily regional mean in this seven-day window"
            text <- paste0(text, sprintf(" %s was %.2f inches on %s; %s of the area received at least %.2f inch that day.", label,
              day$mean_inches, synopsis_date_text(day$date, year = FALSE), percent(day$rain_area_percent), day$rain_threshold_inches))
            sources <- c(sources, list(day))
          }
        }
      } else {
        percentile <- if (product == "pcpn_total_30day") "pcpn_percentile_30day" else "pcpn_water_year_percentile"
        low <- fact(percentile, "AZNM", "area_below_lower_percentile")
        high <- fact(percentile, "AZNM", "area_above_upper_percentile")
        if (!is.null(low) && !is.null(high)) {
          changed <- if (high$value >= low$value) high else low
          if (!is.null(comparison)) {
            magnitude <- vapply(list(low, high), function(x) {
              prior <- fact(x$product, x$region, x$metric, comparison$facts)
              if (is.null(prior)) -Inf else abs(x$value - prior$value)
            }, numeric(1))
            changed <- list(low, high)[[which.max(magnitude)]]
          }
          text <- paste0(text, sprintf(" %s of the area was above percentile %g and %s below percentile %g for the matching period.", percent(high$value), high$threshold, percent(low$value), low$threshold), change(changed))
        }
        sources <- c(sources, list(low, high))
        if (product == "pcpn_water_year_total" && as.integer(as.Date(amount$period_end) - as.Date(amount$period_start)) < 60L)
          text <- paste0(text, " These early-water-year comparisons do not predict the full-year outcome.")
      }
      add(section, text, sources)
    } else add(section, "Matching regional precipitation evidence is unavailable for this snapshot.")
  }
  for (product in c("tmean_departure_30day", "tmean_departure_07day")) {
    if (product == "tmean_departure_30day" && nrow(highlights$seasonal) && any(highlights$seasonal$metric == "longest_dry_spell")) next
    temp <- fact(product, "AZNM", "mean_departure")
    if (is.null(temp)) next
    az <- fact(product, "AZ", "mean_departure"); nm <- fact(product, "NM", "mean_departure")
    text <- if (abs(temp$value) < .05) sprintf("Mean temperature during %s was close to the %s average", synopsis_date_range(temp$period_start, temp$period_end), temp$reference) else
      sprintf("Mean temperature during %s was %.1f\u00b0F %s the %s average", synopsis_date_range(temp$period_start, temp$period_end),
        abs(temp$value), if (temp$value < 0) "below" else "above", temp$reference)
    if (!is.null(az) && !is.null(nm)) text <- paste0(text, sprintf(" (Arizona %+.1f\u00b0F; New Mexico %+.1f\u00b0F)", az$value, nm$value))
    if (!is.null(az) && !is.null(nm) && az$value * nm$value < 0 &&
        abs(az$value - nm$value) >= evidence$configuration$active_week_temperature_departure_f) {
      text <- sprintf("Mean temperatures contrasted during %s: Arizona was %.1f\u00b0F %s average while New Mexico was %.1f\u00b0F %s average (reference: %s)",
        synopsis_date_range(temp$period_start, temp$period_end), abs(az$value), if (az$value < 0) "below" else "above",
        abs(nm$value), if (nm$value < 0) "below" else "above", temp$reference)
    }
    if (product == "tmean_departure_30day") add("Past 30 days", paste0(text, ".", change(temp)), list(temp, az, nm)) else {
      # Keep the lead section at three bullets, including selected station facts.
      if (nrow(highlights$week) < 2L || highlights$profile$mode %in% c("heat", "cold", "mixed")) add("Past 7 days", paste0(text, "."), list(temp, az, nm))
    }
  }
  for (section in c("Past 7 days", "Water year so far")) {
    selected <- if (section == "Past 7 days") highlights$week else highlights$seasonal
    if (nrow(selected)) for (i in seq_len(nrow(selected))) {
      target <- if (selected$metric[i] == "longest_dry_spell") "Past 30 days" else section
      add(target, synopsis_station_sentence(selected[i, ]), list(selected[i, ]))
    }
  }
  if (!is.null(comparison) && !length(changes) && !nrow(highlights$week) && !is.null(evidence$recent)) {
    current <- evidence$facts[evidence$facts$product %in% c("pcpn_percentile_30day", "pcpn_water_year_percentile", "tmean_departure_30day"), , drop = FALSE]
    previous <- comparison$facts[match(current$fact_id, comparison$facts$fact_id), , drop = FALSE]
    days <- evidence$recent$days
    if (nrow(days)) days <- days[which(days$region == "AZNM" & days$date > comparison$snapshot_date), , drop = FALSE]
    compatible <- nrow(current) > 0L && all(current$status %in% "AVAILABLE_CACHED") && all(previous$status %in% "AVAILABLE_CACHED") &&
      all(is.finite(current$value)) && all(is.finite(previous$value)) &&
      all(vapply(c("reference", "units", "threshold", "mask_version"), function(field) identical(current[[field]], previous[[field]]), logical(1)))
    if (compatible && nrow(days) && all(days$status == "AVAILABLE_CACHED") &&
        all(days$mean_inches < evidence$configuration$minimum_weekly_daily_rain_inches) &&
        all(days$rain_area_percent < evidence$configuration$minimum_recent_rain_area_percent)) {
      thresholds <- ifelse(current$product == "tmean_departure_30day", evidence$configuration$material_temperature_change_f, evidence$configuration$material_area_change_points)
      if (all(abs(current$value - previous$value) < thresholds)) {
        idx <- which(vapply(blocks, function(b) b$section == "Past 30 days", logical(1)))[1L]
        blocks[[idx]]$text <- paste0(blocks[[idx]]$text, " The regional percentile-area and temperature indicators changed little since the local comparison dated ", synopsis_date_text(comparison$snapshot_date, short = TRUE), ".")
        blocks[[idx]]$fact_ids <- unique(c(blocks[[idx]]$fact_ids, current$fact_id))
        blocks[[idx]]$comparison_facts <- previous
      }
    }
  }
  # Attach quantitative change evidence to the same paragraphs instead of a fourth section.
  if (length(changes)) for (i in seq_along(blocks)) {
    matched <- Filter(function(x) x$fact_id %in% blocks[[i]]$fact_ids, changes)
    blocks[[i]]$changes <- matched
  }
  if (highlights$profile$station_precipitation_focus && nrow(highlights$week)) {
    station_ids <- highlights$week$fact_id[highlights$week$family == "rainfall"]
    first <- which(vapply(blocks, function(b) b$section == "Past 7 days" && any(b$fact_ids %in% station_ids), logical(1)))
    blocks <- c(blocks[first], blocks[setdiff(seq_along(blocks), first)])
  }
  if (!is.null(evidence$regional_highlights)) {
    candidates <- regional_candidates
    if (length(candidates)) {
      best <- candidates[[1L]]
      monthly <- which(vapply(blocks, function(b) b$section == "Past 30 days", logical(1)))
      # Keep precipitation context and allow one additional, distinct signal.
      prior_companion <- if (length(monthly) > 1L) blocks[[monthly[2L]]] else NULL
      existing_dry <- nrow(highlights$seasonal) && any(highlights$seasonal$metric == "longest_dry_spell")
      if (length(monthly) && (!existing_dry || best$score > .65)) {
        if (length(monthly) > 1L) blocks[[monthly[2L]]] <- best else blocks <- append(blocks, list(best), after = monthly[1L])
        limit <- evidence$configuration$maximum_section_bullets %||synopsis% 3L
        if (!is.numeric(limit) || length(limit) != 1L || !limit %in% 2:3) stop("Synopsis section limit must be two or three.")
        third <- NULL
        if (limit == 3L) {
          warm_cold <- best$emphasis[[1L]]$tone %in% c("warm", "cold")
          temp <- evidence$facts[evidence$facts$product == "tmean_departure_30day" & evidence$facts$metric == "mean_departure", ]
          strong_temp <- any(temp$status == "AVAILABLE_CACHED" & abs(temp$value) >= evidence$configuration$active_week_temperature_departure_f, na.rm = TRUE)
          if (!is.null(prior_companion) && (existing_dry || (!warm_cold && strong_temp))) third <- prior_companion
          if (is.null(third) && length(candidates) > 1L) for (candidate in candidates[-1L]) {
            if (candidate$kind == best$kind || (warm_cold && candidate$emphasis[[1L]]$tone %in% c("warm", "cold"))) next
            third <- candidate; break
          }
          if (!is.null(third)) blocks <- append(blocks, list(third), after = if (length(monthly) > 1L) monthly[2L] else monthly[1L] + 1L)
        }
        if (existing_dry && is.null(third)) highlights$seasonal <- highlights$seasonal[highlights$seasonal$metric != "longest_dry_spell", , drop = FALSE]
      }
    }
    attr(blocks, "regional_candidates") <- candidates
  }
  if (!is.null(evidence$snow_context)) {
    snow_blocks <- synopsis_snow_blocks(evidence)
    for (b in snow_blocks) {
      indices <- which(vapply(blocks,function(x)x$section==b$section,logical(1)))
      after <- if(length(indices)) indices[1L] else length(blocks)
      blocks <- append(blocks,list(b),after=after)
    }
  }
  limit <- evidence$configuration$maximum_section_bullets %||synopsis% 3L
  keep <- unlist(lapply(c("Past 7 days","Past 30 days","Water year so far"),function(section) {
    indices <- which(vapply(blocks,function(b)b$section==section,logical(1)))
    if(section=="Past 7 days" && length(indices)>limit && any(vapply(blocks[indices],function(b)identical(b$kind,"snow_change"),logical(1)))) {
      lead <- indices[1L]
      snow <- indices[vapply(blocks[indices],function(b)identical(b$kind,"snow_change"),logical(1))][1L]
      others <- setdiff(indices,c(lead,snow))
      candidates <- rbind(highlights$week,highlights$seasonal)
      score <- vapply(others,function(i) {
        b<-blocks[[i]];stations<-candidates[candidates$fact_id %in% b$fact_ids,,drop=FALSE]
        if(nrow(stations)&&any(is.finite(stations$unusual_percentile)))return(max(stations$unusual_percentile,na.rm=TRUE)/50)
        temps<-facts[facts$fact_id %in% b$fact_ids & facts$metric=="mean_departure",,drop=FALSE]
        if(nrow(temps))return(max(abs(temps$value),na.rm=TRUE)/evidence$configuration$active_week_temperature_departure_f)
        0
      },numeric(1))
      return(head(c(lead,snow,others[order(-score)]),limit))
    }
    head(indices,limit)
  }))
  candidates <- attr(blocks,"regional_candidates")
  blocks <- blocks[sort(keep)]
  attr(blocks,"regional_candidates") <- candidates
  attr(blocks, "highlights") <- highlights
  blocks
}

build_conditions_synopsis_draft <- function(evidence, root = ".",
    output_dir = file.path(root, "data/diagnostics/conditions-synopsis"),
    track_preview = FALSE, preview_state_path = file.path(output_dir, "preview-state.rds"),
    show_review_candidates = FALSE, publication_snapshot = NULL,
    comparison_origin = c("local_preview", "successful_publication")) {
  comparison_origin <- match.arg(comparison_origin)
  extremes <- evidence$station_extremes
  if (!is.null(evidence$regional_highlights) && !exists("synopsis_regional_candidates", mode = "function"))
    source(file.path(root, "R/conditions-synopsis-regional-highlights.R"), local = TRUE)
  if (is.null(extremes)) stop("Rebuild evidence with the station-extreme adapter before creating a draft.")
  synthetic <- identical(evidence$data_kind, "synthetic_validation")
  if (synthetic && track_preview) stop("Synthetic validation cannot advance preview history.")
  state <- if (track_preview && file.exists(preview_state_path)) tryCatch(readRDS(preview_state_path), error = function(e) NULL) else NULL
  comparison <- synopsis_comparison_context(evidence, state)
  if (comparison_origin == "successful_publication") {
    current <- synopsis_comparison_context(evidence, NULL)$state$latest
    prior <- publication_snapshot$latest
    wy <- function(d) as.integer(substr(d, 1, 4)) + as.integer(substr(d, 6, 10) >= "10-01")
    compatible <- is.list(publication_snapshot) && identical(publication_snapshot$kind, "successful_publication") &&
      is.list(prior) && is.character(prior$snapshot_date) && length(prior$snapshot_date) == 1L && !is.na(prior$snapshot_date) &&
      prior$snapshot_date <= evidence$snapshot_date && identical(prior$policy, current$policy) &&
      wy(prior$snapshot_date) == wy(evidence$snapshot_date) && is.data.frame(prior$facts)
    comparison <- list(previous = if (compatible) prior else NULL, write = FALSE)
  }
  if (!nrow(evidence$facts) || !all(evidence$facts$status %in% "AVAILABLE_CACHED")) comparison$write <- FALSE
  regional_candidates <- if (!is.null(evidence$regional_highlights)) synopsis_regional_candidates(evidence) else list()
  blocks <- synopsis_template_blocks(evidence, extremes, comparison$previous, regional_candidates)
  if (comparison_origin == "successful_publication") for (i in seq_along(blocks))
    blocks[[i]]$text <- gsub("local comparison dated", "last successful publication dated", blocks[[i]]$text, fixed = TRUE)
  blocks <- synopsis_attach_support(blocks,evidence,root,output_dir)
  highlights <- attr(blocks, "highlights")
  regional_options <- attr(blocks,"regional_candidates")
  for(section in c("Past 7 days","Past 30 days","Water year so far")) if(!any(vapply(blocks,function(b)b$section==section,logical(1))))
    blocks[[length(blocks)+1L]] <- list(section=section,text="Matching supported highlights are unavailable for this period; use the dated source products for current conditions.",fact_ids=character(),links=character())
  attr(blocks,"highlights") <- highlights
  attr(blocks,"regional_candidates") <- regional_options
  extremes$selected <- rbind(highlights$week, highlights$seasonal)
  shown_ids <- unlist(lapply(blocks,function(b)b$fact_ids))
  extremes$selected <- extremes$selected[extremes$selected$fact_id %in% shown_ids,,drop=FALSE]
  formatting <- synopsis_format_settings(evidence$configuration)
  for (i in seq_along(blocks)) blocks[[i]]$emphasis <- synopsis_emphasis(blocks[[i]], evidence, extremes$selected, formatting)
  extremes$candidates <- extremes$candidates[extremes$candidates$metric %in% c("freeze_nights_anomaly", "longest_dry_spell"), , drop = FALSE]
  if (!is.null(evidence$station_week)) extremes$candidates <- rbind(extremes$candidates, evidence$station_week$candidates)
  sections <- c("Past 7 days", "Past 30 days", "Water year so far")
  limitations <- c("Reference periods are retained with each fact in the evidence file. Regional amounts and temperature departures are area-weighted grid summaries; station values describe individual locations.",
    sprintf("Station peak rankings compare complete windows of the same length ending on the same calendar date in earlier years, with the current period included once in the rank count. They are not rankings of all calendar days or all weeks. At least %d earlier complete windows are required; gaps and ties are retained. Peak anomalies compare matching window extrema with at least %d complete 1991\u20132020 windows.", evidence$configuration$minimum_extreme_rank_years, evidence$configuration$minimum_extreme_normal_years),
    "Precipitation includes rain and the liquid equivalent of snow. A freeze night has a daily minimum at or below 32\u00b0F. Dry-spell lengths use precipitation below 0.04 inch and are limited to their stated window; they are not necessarily ongoing spells. Public links may display a newer date than this local draft.",
    "Editorial focus follows supported rainfall, heat/cold and longer-term signals; no flood, damage or other impact is inferred from observations alone.")
  if (nrow(extremes$selected) && any(nzchar(extremes$selected$caution_codes)))
    limitations <- c(limitations, "Some selected stations carry historical-record cautions. Current extremes require complete, usable daily observations; historical cautions remain attached in the evidence file.")
  limitations <- c(limitations, if (evidence$snow$active)
    if(!is.null(evidence$snow_context)&&nrow(evidence$snow_context$facts))
      "Snow statistics cover eligible AZ/NM cells, not the padded surrounding states. Storage ratios require a date-specific median of at least 1 inch and 18 reference years. Changes require exact seven-day endpoints and describe net modeled SWE change, not snowfall or melt alone." else
      "Regional snow context is unavailable at this cutoff or lacks sufficient reference area and coverage; this is not evidence of snow-free conditions."
    else "Current snow monitoring is inactive for this snapshot's season; a retained winter map is not a current snow observation.")
  limitations <- c(limitations, if (comparison_origin == "successful_publication") {
    if (is.null(comparison$previous)) "No compatible prior successful publication is available for comparison; no change since the previous publication is claimed."
    else paste0("Changes and event novelty are compared with the last successful publication snapshot dated ", synopsis_date_text(comparison$previous$snapshot_date, short = TRUE),
      ". Rolling-window shifts and source revisions can contribute; changed summaries do not establish a newly occurring event.")
  } else if (is.null(comparison$previous))
    "Day-to-day comparison is not yet available for this local preview; no change since a previous publication is claimed." else
    paste0("Changes and event novelty are compared with the local preview dated ", synopsis_date_text(comparison$previous$snapshot_date, short = TRUE),
      ", not a published update. Rolling-window shifts and source revisions can contribute; a changed summary does not establish a new weather event."))
  limitations <- c(limitations, "PRISM, station and snow products have different reporting-time conventions. A shared cutoff date does not make their daily observation intervals identical.")
  if (!is.null(evidence$regional_highlights)) limitations <- c(limitations,
    "Station network fractions use eligible fixed stations in AZ/NM, with complete current observations, publication screening and supported historical percentiles. ThreadEx series and ambiguous duplicate records are excluded. Comparison records differ among stations; these fractions are not land-area coverage. Day-to-day network-count changes are not interpreted without a matched station set.",
    "Warm-day/cold-night counts use daily percentile thresholds; the frequency count itself is not historically ranked. A 14-day change in a rolling 30-day precipitation rank is not a precipitation amount or a change since yesterday.")
  markdown <- c("# Conditions synopsis", "", paste0("**Local draft \u00b7 Data through ", synopsis_date_text(evidence$snapshot_date), "**"), "",
    paste0("Generated ", synopsis_generated_text(evidence$generated_utc), "; snapshot age ", evidence$snapshot_age_days, " day(s). Editorial season: ", evidence$season$id, "."), "")
  if (synthetic) markdown <- c("**SYNTHETIC VALIDATION: fictional inputs, not observations.**", evidence$scenario_label, "", markdown)
  for (section in sections) {
    selected <- Filter(function(x) x$section == section, blocks)
    if (!length(selected)) next
    markdown <- c(markdown, paste0("## ", section), "", unlist(lapply(selected, function(x) {
      if(!is.null(x$support_link)) x$links <- c(x$support_link,x$links)
      links <- if (length(x$links)) paste0("[", vapply(x$links,synopsis_support_label,character(1)),
        "](", vapply(x$links,synopsis_support_href,character(1)), ")", collapse = " \u00b7 ") else ""
      c(paste0("- ", synopsis_format_text(x$text, x$emphasis, html = FALSE), if (nzchar(links)) paste0(" ", links) else ""), "")
    })))
  }
  markdown <- c(markdown, "## Context and limitations", "", paste0("- ", limitations))
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(markdown, file.path(output_dir, "synopsis.md"), useBytes = TRUE)
  escape <- function(x) {
    x <- gsub("&", "&amp;", x, fixed = TRUE); x <- gsub("<", "&lt;", x, fixed = TRUE)
    x <- gsub(">", "&gt;", x, fixed = TRUE); gsub('"', "&quot;", x, fixed = TRUE)
  }
  html <- c('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
    '<title>Conditions synopsis \u2014 local draft</title><style>body{font:17px/1.6 system-ui,sans-serif;color:#26383f;background:#f2f5f5;margin:0}main{max-width:900px;margin:30px auto;padding:28px;background:white;border-radius:10px}h1,h2{line-height:1.25}h2{font-size:1.2rem;margin-top:1.8rem}a{color:#08718b}small,.note{color:#566b75}.badge{border-left:4px solid #ba542b;padding:8px 14px;background:#fff5ec}li{margin-bottom:8px}</style><main>',
    '<h1>Conditions synopsis</h1>', paste0('<p class="badge">Local draft \u00b7 Data through ', escape(synopsis_date_text(evidence$snapshot_date)), '</p>'),
    paste0('<small>Generated ', escape(synopsis_generated_text(evidence$generated_utc)), '; snapshot age ', evidence$snapshot_age_days, ' day(s).</small>'))
  if (synthetic) html <- c(html, paste0('<p class="badge"><strong>SYNTHETIC VALIDATION: fictional inputs, not observations.</strong><br>', escape(evidence$scenario_label), '</p>'))
  if (formatting$enabled) html <- c(html, paste0('<style>', paste0('.signal-', names(formatting$colors), '{color:', unlist(formatting$colors), ';}', collapse = ''),
    '.signal-neutral{color:inherit}.color-key{font-size:.85rem;color:#566b75}span[class^="signal-"]{font-weight:550}</style>'),
    '<details class="color-key"><summary>Color and emphasis key</summary><p><span class="signal-wet">Wetter</span> \u00b7 <span class="signal-dry">drier</span> \u00b7 <span class="signal-warm">warmer / fewer freezes</span> \u00b7 <span class="signal-cold">colder / more freezes</span>. Words retain the meaning without color. Bold highlights key values, exceptional station comparisons or material changes; it is not an impact rating.</p></details>')
  for (section in sections) {
    selected <- Filter(function(x) x$section == section, blocks)
    if (!length(selected)) next
    selected <- lapply(selected,function(x){if(!is.null(x$support_link))x$links<-c(x$support_link,x$links);x})
    html <- c(html, paste0("<h2>", escape(section), "</h2><ul>"), unlist(lapply(selected, function(x) c(
      paste0("<li>", synopsis_format_text(x$text, x$emphasis)),
      if (length(x$links)) paste0('<br><small>', paste0('<a href="', escape(vapply(x$links,synopsis_support_href,character(1))), '">',
        vapply(x$links,synopsis_support_label,character(1)), '</a>', collapse = " \u00b7 "), '</small>') else character(), "</li>"))), "</ul>")
  }
  candidates <- attr(blocks, "regional_candidates")
  if (isTRUE(show_review_candidates) && length(candidates)) {
    # Local review panel: one strongest supported option per kind. The main
    # monthly section contains at most three complementary bullets.
    kinds <- vapply(candidates, function(x) x$kind, character(1))
    candidates <- candidates[!duplicated(kinds)]
    html <- c(html, '<details class="note"><summary>Additional regional highlights \u2014 review candidates</summary><p>Strongest qualifying option in each category. These compete for up to two monthly companion bullets; they are not additional required statements.</p><ul>',
      vapply(candidates, function(x) paste0('<li>', synopsis_format_text(x$text, if (formatting$enabled) x$emphasis else list()),
        '<br><small><a href="https://cales.arizona.edu/climate/watch/', escape(x$links[1L]), '">Supporting product</a></small></li>'), character(1)), '</ul></details>')
  }
  html <- c(html, '<details class="note"><summary>Reading this synopsis</summary><ul>', paste0("<li>", escape(limitations), "</li>"), "</ul></details></main></html>")
  writeLines(html, file.path(output_dir, "synopsis.html"), useBytes = TRUE)
  jsonlite::write_json(list(schema_version = 1L, evidence_signature = evidence$signature,
    data_kind = if (synthetic) "synthetic_validation" else "observational_cache", formatting = formatting,
    draft_signature = digest::digest(list(version = 3L, evidence$signature, evidence$recent$signature,
      evidence$recent$facts, evidence$recent$days, extremes, blocks, comparison$previous)),
    snapshot_date = evidence$snapshot_date, blocks = blocks, limitations = limitations,
    comparison_kind = if (is.null(comparison$previous)) "none" else comparison_origin,
    comparison_date = if (is.null(comparison$previous)) NULL else comparison$previous$snapshot_date,
    comparison_snapshot = comparison$previous,
    focus = highlights$profile, regional_candidates = attr(blocks, "regional_candidates"),
    station_extremes = extremes), file.path(output_dir, "draft-evidence.json"), dataframe = "rows", auto_unbox = TRUE, na = "null", pretty = TRUE)
  utils::write.csv(extremes$candidates, file.path(output_dir, "station-extreme-candidates.csv"), row.names = FALSE, na = "")
  utils::write.csv(extremes$selected, file.path(output_dir, "station-examples.csv"), row.names = FALSE, na = "")
  if (track_preview && comparison$write) saveRDS(comparison$state, preview_state_path)
  message("Local synopsis draft: ", file.path(output_dir, "synopsis.html"), "; ", nrow(extremes$selected), " station highlights. No requests or publication.")
  invisible(list(blocks = blocks, station_extremes = extremes, comparison_date = if (!is.null(comparison$previous)) comparison$previous$snapshot_date else NULL,
    path = file.path(output_dir, "synopsis.html")))
}
