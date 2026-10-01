# Research prototype for current RCC-ACIS station conditions. Not part of the
# daily publishing workflow. Source config.R, acis-station-inventory.R,
# acis-station-daily-pilot.R, and map-southwest.R first.

acis_reference_station_table <- function(
    path = file.path(swc_acis_station_dir, "reference-network", "daily-audit",
                     "stations.csv")) {
  if (!file.exists(path)) stop("Complete the reference-network daily audit first.")
  stations <- read.csv(path, stringsAsFactors = FALSE)
  required <- c("uid", "sid", "name", "state", "role", "longitude", "latitude",
                "daily_status", "maxt_start", "mint_start", "pcpn_start")
  if (!all(required %in% names(stations)) || anyDuplicated(stations$uid)) {
    stop("Invalid reference-network station table.")
  }
  stations <- stations[stations$daily_status == "AUDITED", , drop = FALSE]
  if (!nrow(stations)) stop("No daily-audited reference stations are available.")
  if (any(stations$role == "fixed" &
          (!is.finite(stations$longitude) | !is.finite(stations$latitude)))) {
    stop("A fixed station lacks map coordinates.")
  }
  stations
}

acis_station_daily_cache_path <- function(uid, cache_dir = file.path(
    "data", "processed", "acis-stations", "reference-network", "daily")) {
  file.path(cache_dir, paste0(as.integer(uid), ".rds"))
}

acis_station_read_daily_cache <- function(path, uid) {
  if (!file.exists(path)) return(NULL)
  value <- tryCatch(readRDS(path), error = function(e) NULL)
  if (!is.list(value) || !identical(value$schema_version, 1L) ||
      !identical(as.integer(value$uid), as.integer(uid)) ||
      !inherits(value$as_of, "Date") || length(value$as_of) != 1L ||
      is.na(value$as_of) ||
      !is.data.frame(value$daily) ||
      !all(c("date", "variable", "numeric_value", "observed", "flag",
             "source", "trace", "accumulated") %in% names(value$daily)) ||
      !inherits(value$daily$date, "Date") ||
      anyDuplicated(value$daily[c("date", "variable")])) return(NULL)
  value
}

update_acis_station_daily_cache <- function(
    station, as_of = Sys.Date() - 1L, refresh_days = 45L,
    cache_dir = file.path("data", "processed", "acis-stations",
                          "reference-network", "daily"),
    fetch = acis_station_fetch, force_full = FALSE) {
  as_of <- as.Date(as_of)
  if (length(as_of) != 1L || is.na(as_of) || length(refresh_days) != 1L ||
      is.na(refresh_days) || refresh_days < 1L) stop("Invalid cache update dates.")
  path <- acis_station_daily_cache_path(station$uid, cache_dir)
  old <- if (force_full) NULL else acis_station_read_daily_cache(path, station$uid)
  if (!is.null(old) && as.Date(old$as_of) >= as_of) {
    return(list(path = path, refreshed = FALSE, as_of = as_of))
  }
  starts <- as.Date(unlist(station[c("maxt_start", "mint_start", "pcpn_start")],
                           use.names = FALSE))
  first_date <- min(starts, na.rm = TRUE)
  if (is.na(first_date) || first_date > as_of) stop("Invalid station date range.")
  start_date <- if (is.null(old)) first_date else
    max(first_date, as_of - as.integer(refresh_days) + 1L)
  if (!is.null(old) && as.Date(old$as_of) < start_date - 1L) {
    # A stale cache must fill the gap, not jump to the latest refresh window.
    start_date <- as.Date(old$as_of) + 1L
  }
  if (!is.null(old) && start_date > as_of) {
    return(list(path = path, refreshed = FALSE, as_of = as.Date(old$as_of)))
  }
  fresh <- acis_station_daily_values(station, today = as_of + 1L,
                                     fetch = fetch, start_date = start_date,
                                     end_date = as_of)
  keep <- c("date", "variable", "numeric_value", "observed", "flag",
            "source", "trace", "accumulated")
  fresh <- fresh[, keep, drop = FALSE]
  daily <- if (is.null(old)) fresh else
    rbind(old$daily[old$daily$date < start_date, keep, drop = FALSE], fresh)
  daily <- daily[order(daily$variable, daily$date), , drop = FALSE]
  rownames(daily) <- NULL
  expected <- seq.Date(first_date, as_of, by = "day")
  for (variable in swc_acis_station_variables) {
    dates <- daily$date[daily$variable == variable]
    if (length(dates) != length(expected) || anyNA(dates) ||
        !all(dates == expected)) {
      stop("Incomplete daily cache for ", station$sid, " / ", variable)
    }
  }
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(list(schema_version = 1L, uid = as.integer(station$uid),
               sid = station$sid, as_of = as_of, daily = daily),
          path, compress = "xz")
  list(path = path, refreshed = TRUE, as_of = as_of)
}

acis_station_window_metric <- function(daily, variable, as_of, days = 30L) {
  as_of <- as.Date(as_of)
  dates <- seq.Date(as_of - as.integer(days) + 1L, as_of, by = "day")
  variables <- if (variable == "tmean") c("maxt", "mint") else variable
  rows <- daily[daily$variable %in% variables & daily$date %in% dates, , drop = FALSE]
  expected <- expand.grid(date = dates, variable = variables,
                          KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  match_rows <- match(paste(expected$date, expected$variable),
                      paste(rows$date, rows$variable))
  aligned <- rows[match_rows, , drop = FALSE]
  missing <- is.na(match_rows) | is.na(aligned$observed) | !aligned$observed |
    !is.finite(aligned$numeric_value)
  flagged <- !is.na(aligned$flag) & nzchar(aligned$flag) &
    if (variable == "pcpn") aligned$flag != "T" else TRUE
  if (variable == "pcpn") {
    flagged <- flagged | (!is.na(aligned$accumulated) & aligned$accumulated)
    flagged <- flagged | (!is.na(aligned$numeric_value) &
                            (aligned$numeric_value < 0 | aligned$numeric_value > 100))
  } else {
    flagged <- flagged | (!is.na(aligned$numeric_value) &
                            abs(aligned$numeric_value) > 150)
  }
  flagged[is.na(flagged)] <- FALSE
  # Missing observations can carry ACIS's M flag. Report these as missing,
  # not as both missing and a separate quality-flagged day.
  flagged[missing] <- FALSE
  inversion <- FALSE
  if (variable == "tmean") {
    maximum <- aligned$numeric_value[expected$variable == "maxt"]
    minimum <- aligned$numeric_value[expected$variable == "mint"]
    inversion <- any(maximum < minimum, na.rm = TRUE)
  }
  missing_days <- if (variable == "tmean")
    sum(rowSums(matrix(missing, ncol = 2L)) > 0L) else sum(missing)
  flagged_days <- if (variable == "tmean")
    sum(rowSums(matrix(flagged, ncol = 2L)) > 0L) + as.integer(inversion) else
      sum(flagged)
  valid <- if (variable == "tmean")
    !rowSums(matrix(missing | flagged, ncol = 2L)) & maximum >= minimum else
      !missing & !flagged
  valid[is.na(valid)] <- FALSE
  trailing_missing <- if (variable == "pcpn") {
    tail_run <- rle(rev(missing))
    if (length(tail_run$values) && isTRUE(tail_run$values[[1L]]))
      tail_run$lengths[[1L]] else 0L
  } else 0L
  max_gap <- if (variable == "tmean" && any(!valid))
    max(rle(!valid)$lengths[rle(!valid)$values]) else 0L
  status <- if (flagged_days > 0L) "FLAGGED" else if (!missing_days)
    "AVAILABLE" else if (variable == "pcpn" &&
      missing_days == trailing_missing &&
      missing_days <= if (days <= 7L) 1L else 2L) "PROVISIONAL" else if (
        variable == "tmean" && sum(valid) / days >= 0.98 && max_gap <= 2L)
          "NEAR_COMPLETE" else if (variable == "tmean" &&
            sum(valid) / days >= 0.95 && max_gap <= 2L)
              "PARTIAL" else "INCOMPLETE"
  value <- if (!status %in% c("AVAILABLE", "PROVISIONAL", "NEAR_COMPLETE",
                            "PARTIAL"))
    NA_real_ else if (variable == "pcpn")
      sum(aligned$numeric_value[valid]) else if (variable == "tmean")
        mean(((maximum + minimum) / 2)[valid]) else
          mean(aligned$numeric_value[valid])
  list(value = value, status = status, missing_days = missing_days,
       flagged_days = flagged_days, trailing_missing_days = trailing_missing)
}

acis_reference_current_rows <- function(
    stations, as_of = Sys.Date() - 1L,
    cache_dir = file.path("data", "processed", "acis-stations",
                          "reference-network", "daily"),
    caches = NULL) {
  as_of <- as.Date(as_of)
  rows <- lapply(seq_len(nrow(stations)), function(index) {
    station <- stations[index, , drop = FALSE]
    cache <- if (is.null(caches)) acis_station_read_daily_cache(
      acis_station_daily_cache_path(station$uid, cache_dir), station$uid) else
        caches[[index]]
    metrics <- lapply(c("pcpn", "tmean"), function(variable) {
      if (is.null(cache) || as.Date(cache$as_of) < as_of) {
        return(list(value = NA_real_, status = "STALE",
                    missing_days = NA_integer_, flagged_days = NA_integer_))
      }
      acis_station_window_metric(cache$daily, variable, as_of)
    })
    data.frame(uid = station$uid, name = station$name, state = station$state,
               role = station$role, longitude = station$longitude,
               latitude = station$latitude, as_of = as.character(as_of),
               pcpn_30day_inches = metrics[[1L]]$value,
               pcpn_status = metrics[[1L]]$status,
               pcpn_missing_days = metrics[[1L]]$missing_days,
               pcpn_flagged_days = metrics[[1L]]$flagged_days,
               tmean_30day_f = metrics[[2L]]$value,
               tmean_status = metrics[[2L]]$status,
               tmean_missing_days = metrics[[2L]]$missing_days,
               tmean_flagged_days = metrics[[2L]]$flagged_days,
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

acis_station_current_map <- function(rows, variable = c("pcpn", "tmean"),
                                     states = southwest_state_boundaries(),
                                     counties = southwest_county_boundaries()) {
  variable <- match.arg(variable)
  value_col <- if (variable == "pcpn") "pcpn_30day_inches" else "tmean_30day_f"
  status_col <- paste0(variable, "_status")
  fixed <- rows[rows$role == "fixed" & is.finite(rows$longitude) &
                  is.finite(rows$latitude), , drop = FALSE]
  usable <- fixed[fixed[[status_col]] %in%
                    c("AVAILABLE", "PROVISIONAL", "NEAR_COMPLETE", "PARTIAL"), , drop = FALSE]
  cautioned <- usable[usable[[status_col]] %in%
                       c("PROVISIONAL", "PARTIAL"), , drop = FALSE]
  unavailable <- fixed[!fixed[[status_col]] %in%
                         c("AVAILABLE", "PROVISIONAL", "NEAR_COMPLETE",
                           "PARTIAL"), , drop = FALSE]
  label <- if (variable == "pcpn") "30-day precipitation (inches)" else
    "30-day mean temperature (°F)"
  palette <- if (variable == "pcpn")
    c("#e8f4f8", "#89c5df", "#2b83ba", "#194b79") else
      c("#335e9a", "#93bad4", "#f0d5a4", "#db7848", "#9e2f28")
  ggplot2::ggplot() +
    ggplot2::geom_sf(data = states, fill = "#f7f7f4", color = NA) +
    ggplot2::geom_sf(data = counties, fill = NA, color = "#c4cbd0",
                     linewidth = 0.18) +
    ggplot2::geom_sf(data = states, fill = NA, color = "#28343b",
                     linewidth = 0.6) +
    ggplot2::geom_point(data = unavailable,
                        ggplot2::aes(x = longitude, y = latitude),
                        shape = 21, size = 2.8, fill = "white", color = "#87919a",
                        stroke = 0.7) +
    ggplot2::geom_point(data = usable,
                        ggplot2::aes(x = longitude, y = latitude,
                                     color = .data[[value_col]]),
                        size = 3.4) +
    ggplot2::geom_point(data = cautioned,
                        ggplot2::aes(x = longitude, y = latitude),
                        shape = 21, size = 5, fill = NA,
                        color = "#8a4b12", stroke = 0.8) +
    ggplot2::scale_color_gradientn(colors = palette, name = label) +
    ggplot2::coord_sf(xlim = unname(swc_region$bbox[c("west", "east")]),
                      ylim = unname(swc_region$bbox[c("south", "north")]),
                      expand = FALSE) +
    ggplot2::labs(title = label,
                  subtitle = paste0(as.character(as.Date(rows$as_of[[1L]]) - 29L),
                                    " to ", rows$as_of[[1L]]),
                  caption = "RCC-ACIS | ochre ring = provisional precipitation or partial temperature; hollow = unavailable; ThreadEx not mapped") +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(panel.grid.major = ggplot2::element_blank(),
                   plot.title = ggplot2::element_text(face = "bold"),
                   legend.position = "bottom")
}

acis_station_html_escape <- function(x) {
  x <- ifelse(is.na(x), "", as.character(x))
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub('"', "&quot;", x, fixed = TRUE)
}

write_acis_station_current_prototype <- function(
    rows, output_dir = file.path(swc_acis_station_dir, "current-prototype"),
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries()) {
  if (!nrow(rows) || length(unique(rows$as_of)) != 1L) {
    stop("Prototype rows need one common as-of date.")
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  write.csv(rows, file.path(output_dir, "station-status.csv"), row.names = FALSE)
  for (variable in c("pcpn", "tmean")) {
    ggplot2::ggsave(file.path(output_dir, paste0(variable, "-30day.png")),
                    plot = acis_station_current_map(rows, variable, states, counties),
                    width = 10, height = 6.8, dpi = 160, bg = "white")
  }
  display <- rows[order(rows$state, rows$name), , drop = FALSE]
  format_metric <- function(value, status, digits) {
    formatted <- format(round(value, digits), nsmall = digits, trim = TRUE)
    ifelse(status == "PROVISIONAL", paste0("≥", formatted),
           ifelse(status == "PARTIAL", paste0(formatted, "*"),
                  ifelse(status %in% c("AVAILABLE", "NEAR_COMPLETE"),
                         formatted, status)))
  }
  cells <- data.frame(
    Station = display$name, State = display$state,
    Type = ifelse(display$role == "fixed", "Station", "ThreadEx area"),
    `30-day precipitation (in.)` = format_metric(display$pcpn_30day_inches,
                                                 display$pcpn_status, 2L),
    `30-day mean temperature (°F)` = format_metric(display$tmean_30day_f,
                                                   display$tmean_status, 1L),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  header <- paste0("<th tabindex='0'>", acis_station_html_escape(names(cells)),
                   "</th>", collapse = "")
  body <- paste(apply(cells, 1L, function(row) paste0(
    "<tr>", paste0("<td>", acis_station_html_escape(row), "</td>",
                     collapse = ""), "</tr>")), collapse = "\n")
  html <- c(
    "<!doctype html><html lang='en'><head><meta charset='utf-8'>",
    "<meta name='viewport' content='width=device-width,initial-scale=1'>",
    "<title>ACIS station conditions prototype</title>",
    "<style>body{font:16px system-ui,sans-serif;max-width:1450px;margin:auto;padding:1.2rem;color:#23323c}h1{margin-bottom:.25rem}.note{color:#50636e}.maps{display:grid;grid-template-columns:repeat(auto-fit,minmax(400px,1fr));gap:1rem}.maps img{width:100%;height:auto}table{border-collapse:collapse;width:100%;margin-top:1rem}th,td{border-bottom:1px solid #d8dfe2;padding:.45rem;text-align:left}th{background:#edf2f4;cursor:pointer;position:sticky;top:0}tr:hover{background:#f5f8f9}.table-wrap{overflow:auto}td:nth-child(n+4){font-variant-numeric:tabular-nums}@media(max-width:600px){.maps{grid-template-columns:1fr}}</style>",
    "</head><body>",
    paste0("<h1>Current station conditions</h1><p class='note'>",
           acis_station_html_escape(as.character(as.Date(rows$as_of[[1L]]) - 29L)),
           " to ", acis_station_html_escape(rows$as_of[[1L]]),
           " · RCC-ACIS · research prototype, not part of the public site</p>"),
    "<p>≥ marks a provisional precipitation lower bound when only the most recent one or two reporting days are missing. A temperature mean with at least 98% valid paired days displays normally; * and an ochre ring mark 95–&lt;98% coverage with no gap longer than two days. An ochre ring also marks provisional precipitation; a hollow symbol is unavailable. Trace precipitation counts as zero; accumulated or other flagged days are excluded. ThreadEx area composites are in the table, not mapped.</p>",
    "<div class='maps'><img src='pcpn-30day.png' alt='Map of 30-day station precipitation'><img src='tmean-30day.png' alt='Map of 30-day station mean temperature'></div>",
    "<p class='note'>Select a column heading to sort the table. PROVISIONAL is an observed precipitation lower bound, NEAR_COMPLETE is a temperature mean with at least 98% valid paired days, PARTIAL is a 95–&lt;98% observed-days temperature mean, INCOMPLETE means too many or interior missing days, FLAGGED means a non-trace quality flag or invalid value, and STALE means the daily cache has not been updated through the displayed date.</p>",
    paste0("<div class='table-wrap'><table id='stations'><thead><tr>", header,
           "</tr></thead><tbody>", body, "</tbody></table></div>"),
    "<script>document.querySelectorAll('#stations th').forEach((th,i)=>{let up=true;const sort=()=>{const body=document.querySelector('#stations tbody');const rows=[...body.rows];rows.sort((a,b)=>{const x=a.cells[i].textContent,y=b.cells[i].textContent;const nx=Number(x),ny=Number(y);const cmp=x!==''&&y!==''&&!Number.isNaN(nx)&&!Number.isNaN(ny)?nx-ny:x.localeCompare(y,undefined,{numeric:true});return up?cmp:-cmp});rows.forEach(r=>body.appendChild(r));up=!up};th.addEventListener('click',sort);th.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();sort()}})});</script>",
    "</body></html>"
  )
  path <- file.path(output_dir, "index.html")
  writeLines(html, path, useBytes = TRUE)
  path
}

run_acis_station_current_prototype <- function(
    max_stations = 5L, as_of = Sys.Date() - 1L, refresh_days = 45L,
    fetch = acis_station_fetch,
    stations_path = file.path(swc_acis_station_dir, "reference-network",
                              "daily-audit", "stations.csv"),
    cache_dir = file.path("data", "processed", "acis-stations",
                          "reference-network", "daily"),
    output_dir = file.path(swc_acis_station_dir, "current-prototype")) {
  if (length(max_stations) != 1L || !is.finite(max_stations) ||
      max_stations < 0L) {
    stop("Invalid station batch size.")
  }
  stations <- acis_reference_station_table(stations_path)
  current <- vapply(seq_len(nrow(stations)), function(i) {
    cache <- acis_station_read_daily_cache(
      acis_station_daily_cache_path(stations$uid[[i]], cache_dir),
      stations$uid[[i]])
    !is.null(cache) && as.Date(cache$as_of) >= as.Date(as_of)
  }, logical(1))
  pending <- which(!current)
  scheduled <- head(pending, as.integer(max_stations))
  message(sprintf("ACIS current prototype: %d records; %d cached; %d scheduled.",
                  nrow(stations), sum(current), length(scheduled)))
  failures <- character()
  for (index in scheduled) {
    station <- stations[index, , drop = FALSE]
    message(sprintf("Caching %s (%s).", station$name, station$sid))
    tryCatch(update_acis_station_daily_cache(station, as_of, refresh_days,
                                              cache_dir, fetch), error = function(e) {
      failures <<- c(failures, paste(station$sid, conditionMessage(e), sep = ": "))
      message("  Cache failed: ", conditionMessage(e))
    })
  }
  rows <- acis_reference_current_rows(stations, as_of, cache_dir)
  remaining <- sum(rows$pcpn_status == "STALE")
  page <- if (remaining == 0L) write_acis_station_current_prototype(
    rows, output_dir) else NA_character_
  if (remaining > 0L) message("Rerun to complete ", remaining,
                              " station caches before drawing the prototype.")
  list(pending = remaining, failures = failures, rows = rows,
       page = page, output_dir = output_dir)
}
