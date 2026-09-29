# Local, read-only visual review of flagged SNODAS relative-QC episodes.
# Writes only an HTML report and diagnostic CSVs; never edits snow grids.

snodas_relative_review_neighborhood <- function(template, cell,
                                                radius = 2L) {
  if (!inherits(template, "SpatRaster") || terra::nlyr(template) != 1L ||
      length(cell) != 1L || is.na(cell) || cell != floor(cell) ||
      cell < 1L || cell > terra::ncell(template) ||
      length(radius) != 1L || is.na(radius) ||
      radius != floor(radius) || radius < 1L) {
    stop("Invalid SNODAS review neighborhood.", call. = FALSE)
  }
  offsets <- expand.grid(row_offset = seq.int(-radius, radius),
                         col_offset = seq.int(-radius, radius))
  center_row <- (cell - 1L) %/% terra::ncol(template) + 1L
  center_col <- (cell - 1L) %% terra::ncol(template) + 1L
  row <- center_row + offsets$row_offset
  col <- center_col + offsets$col_offset
  valid <- row >= 1L & row <= terra::nrow(template) &
    col >= 1L & col <= terra::ncol(template)
  cells <- rep(NA_integer_, nrow(offsets))
  cells[valid] <- (row[valid] - 1L) * terra::ncol(template) + col[valid]
  xy <- matrix(NA_real_, nrow(offsets), 2L)
  if (any(valid)) xy[valid, ] <- terra::xyFromCell(template, cells[valid])
  data.frame(tile_row = offsets$row_offset + radius + 1L,
             tile_col = offsets$col_offset + radius + 1L,
             cell = cells, longitude = xy[, 1L], latitude = xy[, 2L])
}

snodas_relative_review_sample <- function(date, grid, read_pair) {
  result <- list(swe = rep(NA_real_, nrow(grid)),
                 depth = rep(NA_real_, nrow(grid)))
  valid_cell <- which(!is.na(grid$cell))
  if (!length(valid_cell)) return(result)
  points <- as.matrix(grid[valid_cell, c("longitude", "latitude")])
  pair <- tryCatch(read_pair(as.Date(date), points),
                   error = function(e) NULL)
  if (is.null(pair) || !is.list(pair) ||
      !all(c("swe", "depth") %in% names(pair)) ||
      !is.numeric(pair$swe) || !is.numeric(pair$depth) ||
      length(pair$swe) != length(valid_cell) ||
      length(pair$depth) != length(valid_cell)) return(result)
  valid_pair <- is.finite(pair$swe) & is.finite(pair$depth) &
    pair$swe >= 0 & pair$depth >= 0 &
    pair$swe <= pair$depth + 1e-6 &
    pair$swe < 32767 / 25.4 & pair$depth < 32767 / 25.4
  result$swe[valid_cell[valid_pair]] <- pair$swe[valid_pair]
  result$depth[valid_cell[valid_pair]] <- pair$depth[valid_pair]
  result
}

snodas_relative_review_history <- function(peak_date, grid, read_pair) {
  peak_date <- as.Date(peak_date)
  if (length(peak_date) != 1L || is.na(peak_date) ||
      !is.function(read_pair)) {
    stop("Choose one peak date and a daily reader.", call. = FALSE)
  }
  dates <- seq(peak_date - 7L, peak_date + 7L, by = "day")
  center <- grid$tile_row == 3L & grid$tile_col == 3L
  neighbors <- abs(grid$tile_row - 3L) <= 1L &
    abs(grid$tile_col - 3L) <= 1L & !center
  if (sum(center) != 1L || sum(neighbors) != 8L) {
    stop("Expected a centered 5-by-5 review grid.", call. = FALSE)
  }
  history <- data.frame(
    date = as.character(dates), focal_swe_inches = NA_real_,
    neighbor_median_swe_inches = NA_real_,
    focal_depth_inches = NA_real_,
    neighbor_median_depth_inches = NA_real_,
    valid_neighbors = integer(length(dates)))
  peak_grid <- NULL
  for (i in seq_along(dates)) {
    sample <- snodas_relative_review_sample(dates[i], grid, read_pair)
    history$focal_swe_inches[i] <- sample$swe[center]
    history$focal_depth_inches[i] <- sample$depth[center]
    valid <- neighbors & is.finite(sample$swe) &
      is.finite(sample$depth)
    history$valid_neighbors[i] <- sum(valid)
    if (any(valid)) {
      history$neighbor_median_swe_inches[i] <-
        stats::median(sample$swe[valid])
      history$neighbor_median_depth_inches[i] <-
        stats::median(sample$depth[valid])
    }
    if (dates[i] == peak_date) {
      peak_grid <- transform(grid, swe_inches = sample$swe,
                             depth_inches = sample$depth)
    }
  }
  list(history = history, peak_grid = peak_grid)
}

snodas_relative_review_escape <- function(value) {
  value <- as.character(value)
  value[is.na(value)] <- ""
  value <- gsub("&", "&amp;", value, fixed = TRUE)
  value <- gsub("<", "&lt;", value, fixed = TRUE)
  value <- gsub(">", "&gt;", value, fixed = TRUE)
  value <- gsub('"', "&quot;", value, fixed = TRUE)
  value
}

snodas_relative_review_format <- function(value, digits = 1L) {
  ifelse(is.finite(value), formatC(value, format = "f", digits = digits),
         "missing")
}

snodas_relative_review_tiles <- function(grid, variable, title) {
  values <- grid[[variable]]
  upper <- max(values, na.rm = TRUE)
  if (!is.finite(upper) || upper <= 0) upper <- 1
  rows <- vapply(seq_len(5L), function(row) {
    cells <- vapply(seq_len(5L), function(col) {
      index <- which(grid$tile_row == row & grid$tile_col == col)
      value <- values[index]
      ratio <- if (is.finite(value)) min(1, value / upper) else NA_real_
      background <- if (is.na(ratio)) "#e9e8e5" else
        grDevices::rgb(
          grDevices::colorRamp(c("#f7fbff", "#6baed6", "#08306b"))(
            ratio) / 255)
      foreground <- if (!is.na(ratio) && ratio >= 0.66) "#ffffff" else
        "#172733"
      focal <- row == 3L && col == 3L
      sprintf('<td class="%s" style="background:%s;color:%s">%s</td>',
              if (focal) "focal" else "", background, foreground,
              if (is.finite(value))
                snodas_relative_review_format(value) else "—")
    }, character(1L))
    paste0("<tr>", paste(cells, collapse = ""), "</tr>")
  }, character(1L))
  paste0("<figure><figcaption>", snodas_relative_review_escape(title),
         " (inches; north at top; colors scaled within panel; ",
         "black outline = flagged cell)</figcaption>",
         '<table class="tiles" aria-label="',
         snodas_relative_review_escape(title), '">',
         paste(rows, collapse = ""), "</table></figure>")
}

snodas_relative_review_svg <- function(history, focal, neighbors, title) {
  width <- 440L
  height <- 165L
  x <- seq(42, width - 12, length.out = nrow(history))
  all_values <- c(history[[focal]], history[[neighbors]])
  ceiling <- max(all_values, na.rm = TRUE)
  if (!is.finite(ceiling) || ceiling <= 0) ceiling <- 1
  ceiling <- ceiling * 1.08
  y <- function(value) 126 - value / ceiling * 104
  lines <- function(values, color, dash = "") {
    valid <- is.finite(values)
    indices <- which(valid[-length(valid)] & valid[-1L])
    if (!length(indices)) return("")
    paste(vapply(indices, function(i) sprintf(
      '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="2.5" %s/>',
      x[i], y(values[i]), x[i + 1L], y(values[i + 1L]), color, dash),
      character(1L)), collapse = "")
  }
  dates <- as.Date(history$date)
  paste0('<figure><figcaption>',
         snodas_relative_review_escape(title),
         ' over 15 days (inches)</figcaption>',
         sprintf('<svg viewBox="0 0 %d %d" role="img" aria-label="%s">',
                 width, height, snodas_relative_review_escape(title)),
         '<line x1="42" y1="126" x2="428" y2="126" stroke="#9ba8b0"/>',
         '<line x1="42" y1="22" x2="42" y2="126" stroke="#9ba8b0"/>',
         sprintf('<text x="4" y="27">%s</text>',
                 snodas_relative_review_format(ceiling, 0L)),
         '<text x="25" y="129">0</text>',
         lines(history[[neighbors]], "#7b8f9d", 'stroke-dasharray="5 4"'),
         lines(history[[focal]], "#12618a"),
         sprintf('<line x1="%.1f" y1="22" x2="%.1f" y2="126" stroke="#b65b2c" stroke-width="1" stroke-dasharray="3 3"/>',
                 x[8L], x[8L]),
         sprintf('<text x="42" y="150">%s</text>', format(dates[1L], "%b %d")),
         sprintf('<text x="%.1f" y="150" text-anchor="middle">%s</text>',
                 x[8L], format(dates[8L], "%b %d")),
         sprintf('<text x="428" y="150" text-anchor="end">%s</text>',
                 format(dates[15L], "%b %d")),
         '</svg><div class="chart-key"><span class="focal-key">Flagged cell</span>',
         '<span class="neighbor-key">Neighbor median</span></div></figure>')
}

snodas_relative_review_history_table <- function(history) {
  rows <- vapply(seq_len(nrow(history)), function(i) {
    paste0("<tr><td>", history$date[i], "</td><td>",
           snodas_relative_review_format(history$focal_swe_inches[i]),
           "</td><td>",
           snodas_relative_review_format(
             history$neighbor_median_swe_inches[i]),
           "</td><td>",
           snodas_relative_review_format(history$focal_depth_inches[i]),
           "</td><td>",
           snodas_relative_review_format(
             history$neighbor_median_depth_inches[i]),
           "</td><td>", history$valid_neighbors[i], "</td></tr>")
  }, character(1L))
  paste0('<details class="daily-table"><summary>Daily values</summary>',
         '<table><thead><tr><th>Date</th><th>Cell SWE</th>',
         '<th>Neighbor SWE</th><th>Cell depth</th>',
         '<th>Neighbor depth</th><th>Valid neighbors</th>',
         '</tr></thead><tbody>', paste(rows, collapse = ""),
         '</tbody></table></details>')
}

snodas_relative_review_cues <- function(peak) {
  cues <- character()
  if (isTRUE(peak$strong_spatial_isolation))
    cues <- c(cues, "strong spatial isolation")
  if (isTRUE(peak$density_contrast))
    cues <- c(cues, "unusual SWE/depth ratio")
  if (isTRUE(peak$weak_temporal_support))
    cues <- c(cues, "weak temporal support")
  if (isTRUE(peak$map_daily_mismatch))
    cues <- c(cues, "seasonal/daily peak mismatch")
  if (!length(cues)) cues <- "spatial review flag"
  paste(cues, collapse = "; ")
}

snodas_relative_review_load <- function(
    triage_dir = file.path("data", "diagnostics", "snodas-relative-qc-triage")) {
  files <- c(peaks = "candidate-evidence.csv", episodes = "episodes.csv",
             benchmarks = "known-mask-benchmarks.csv")
  paths <- stats::setNames(file.path(triage_dir, files), names(files))
  if (!all(file.exists(paths))) {
    stop("Run `build_snodas_relative_qc_triage()` before the review report.",
         call. = FALSE)
  }
  list(peaks = utils::read.csv(paths[["peaks"]]),
       episodes = utils::read.csv(paths[["episodes"]]),
       benchmarks = utils::read.csv(paths[["benchmarks"]]))
}

build_snodas_relative_review_report <- function(
    triage = NULL,
    output_dir = file.path("data", "diagnostics",
                           "snodas-relative-qc-triage", "review-report"),
    archive_dir = file.path("data", "diagnostics", "snodas-seasonal-archive"),
    processed_dir = swc_paths$processed,
    read_pair = function(date, points) snodas_relative_qc_read_points(
      date, points, processed_dir)) {
  if (is.null(triage)) triage <- snodas_relative_review_load()
  if (!is.list(triage) ||
      !all(c("peaks", "episodes", "benchmarks") %in% names(triage)) ||
      !is.function(read_pair)) {
    stop("Supply a SNODAS relative triage result and daily reader.",
         call. = FALSE)
  }
  peaks <- triage$peaks
  episodes <- triage$episodes
  benchmarks <- triage$benchmarks
  required_peak <- c("water_year", "cell", "longitude", "latitude",
                     "peak_date", "peak_swe_inches", "pilot_priority")
  required_episode <- c("water_year", "start_date", "end_date",
                        "pilot_priority")
  if (!is.data.frame(peaks) || !is.data.frame(episodes) ||
      !is.data.frame(benchmarks) ||
      !all(required_peak %in% names(peaks)) ||
      !all(required_episode %in% names(episodes))) {
    stop("SNODAS relative triage tables are incomplete.", call. = FALSE)
  }
  flagged <- peaks$pilot_priority %in% c("REVIEW_EVENT", "NEEDS_EVIDENCE")
  peaks <- peaks[flagged, , drop = FALSE]
  if (!nrow(episodes) || !nrow(peaks)) {
    stop("No flagged SNODAS episodes were found.", call. = FALSE)
  }
  benchmark_keys <- if (nrow(benchmarks))
    paste(benchmarks$water_year[benchmarks$source_matched],
          benchmarks$cell[benchmarks$source_matched]) else character()
  benchmark_rules <- if (nrow(benchmarks))
    benchmarks$rule_id[benchmarks$source_matched] else character()
  names(benchmark_rules) <- benchmark_keys
  cell_rows <- list()
  history_rows <- list()
  episode_html <- character(nrow(episodes))
  for (e in seq_len(nrow(episodes))) {
    episode <- episodes[e, , drop = FALSE]
    dates <- as.Date(peaks$peak_date)
    first <- as.Date(episode$start_date)
    last <- as.Date(episode$end_date)
    member <- peaks$water_year == episode$water_year &
      if (is.na(first) || is.na(last)) is.na(dates) else
        !is.na(dates) & dates >= first & dates <= last
    members <- peaks[member, , drop = FALSE]
    if (!nrow(members)) {
      stop("Review episode has no matching flagged cell: ", e,
           call. = FALSE)
    }
    template_path <- file.path(
      archive_dir, sprintf("wy%04d", episode$water_year), "peak_swe.tif")
    if (!file.exists(template_path)) {
      stop("Missing seasonal peak template: ", template_path,
           call. = FALSE)
    }
    template <- terra::rast(template_path)
    cards <- character(nrow(members))
    for (j in seq_len(nrow(members))) {
      peak <- members[j, , drop = FALSE]
      key <- paste(peak$water_year, peak$cell)
      known_rule <- if (key %in% benchmark_keys)
        benchmark_rules[[key]] else NA_character_
      grid <- snodas_relative_review_neighborhood(template, peak$cell)
      detail <- if (!is.na(peak$peak_date))
        snodas_relative_review_history(
          peak$peak_date, grid, read_pair) else NULL
      peak_depth <- if (!is.null(detail))
        detail$history$focal_depth_inches[8L] else NA_real_
      row <- data.frame(
        episode_id = e, water_year = peak$water_year,
        cell = peak$cell, peak_date = peak$peak_date,
        longitude = peak$longitude, latitude = peak$latitude,
        peak_swe_inches = peak$peak_swe_inches,
        peak_depth_inches = peak_depth,
        known_rule_id = known_rule,
        review_cues = snodas_relative_review_cues(peak),
        pilot_priority = peak$pilot_priority,
        stringsAsFactors = FALSE)
      cell_rows[[length(cell_rows) + 1L]] <- row
      if (!is.null(detail)) {
        daily <- detail$history
        daily$episode_id <- e
        daily$water_year <- peak$water_year
        daily$cell <- peak$cell
        history_rows[[length(history_rows) + 1L]] <- daily
      }
      status <- if (!is.na(known_rule))
        paste0("Documented mask: ", known_rule) else
          "Unclassified review flag"
      figures <- if (is.null(detail))
        '<p>Peak date or local daily evidence is unavailable.</p>' else
        paste0('<div class="figure-grid">',
               snodas_relative_review_tiles(
                 detail$peak_grid, "swe_inches", "Peak-day SWE"),
               snodas_relative_review_tiles(
                 detail$peak_grid, "depth_inches", "Peak-day snow depth"),
               snodas_relative_review_svg(
                 detail$history, "focal_swe_inches",
                 "neighbor_median_swe_inches", "SWE"),
               snodas_relative_review_svg(
                 detail$history, "focal_depth_inches",
                 "neighbor_median_depth_inches", "Snow depth"),
               '</div>', snodas_relative_review_history_table(
                 detail$history))
      cards[j] <- paste0(
        '<article class="cell-card"><h3>Cell ', peak$cell,
        ' <span class="', if (is.na(known_rule)) "unclassified" else "known",
        '">', snodas_relative_review_escape(status), '</span></h3>',
        '<p class="detail">',
        sprintf('%.4f° lon, %.4f° lat · peak %s · SWE %s in · depth %s in',
                peak$longitude, peak$latitude,
                snodas_relative_review_escape(peak$peak_date),
                snodas_relative_review_format(peak$peak_swe_inches),
                snodas_relative_review_format(peak_depth)),
        '</p><p><strong>Review cues:</strong> ',
        snodas_relative_review_escape(row$review_cues),
        '</p>', figures, '</article>')
    }
    episode_html[e] <- paste0(
      '<details class="episode" id="episode-', e, '">',
      '<summary>WY', episode$water_year, ' · ',
      snodas_relative_review_escape(episode$start_date),
      if (!identical(episode$start_date, episode$end_date))
        paste0(' to ', snodas_relative_review_escape(episode$end_date)) else '',
      ' · ', nrow(members), ' flagged cell',
      if (nrow(members) == 1L) '' else 's', '</summary>',
      paste(cards, collapse = ''), '</details>')
    message(sprintf("SNODAS review report: %d/%d episodes.",
                    e, nrow(episodes)))
  }
  cells <- do.call(rbind, cell_rows)
  expected_keys <- paste(peaks$water_year, peaks$cell)
  reported_keys <- paste(cells$water_year, cells$cell)
  if (length(reported_keys) != length(expected_keys) ||
      anyDuplicated(reported_keys) ||
      !setequal(reported_keys, expected_keys)) {
    stop("Each flagged SNODAS cell must appear in exactly one episode.",
         call. = FALSE)
  }
  history <- if (length(history_rows)) do.call(rbind, history_rows) else
    data.frame()
  html <- paste0(
    '<!doctype html><html lang="en"><head><meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width,initial-scale=1">',
    '<title>SNODAS relative-QC episode review</title>',
    '<style>body{font:16px/1.45 system-ui,sans-serif;color:#20313d;',
    'max-width:1100px;margin:0 auto;padding:24px;background:#f5f7f8}',
    'h1{margin-bottom:4px}p{margin:8px 0 14px}.intro{background:white;',
    'padding:18px;border-left:4px solid #b85c38;border-radius:6px}',
    '.episode{background:white;border:1px solid #d3dce2;border-radius:8px;',
    'margin:14px 0;padding:12px 16px}.episode>summary{cursor:pointer;',
    'font-size:1.15rem;font-weight:700}.cell-card{border-top:1px solid #e2e8ed;',
    'margin-top:14px;padding-top:12px}.cell-card h3{margin:0}',
    '.cell-card h3 span{font-size:.78rem;font-weight:600;',
    'padding:3px 7px;border-radius:12px;margin-left:6px}',
    '.known{background:#dcebdc;color:#224b2a}.unclassified{background:#fff0d9;',
    'color:#794812}.detail{color:#526470}.figure-grid{display:grid;',
    'grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:12px}',
    'figure{margin:4px 0;padding:10px;border:1px solid #d9e1e6;',
    'border-radius:5px}figcaption{font-weight:600;margin-bottom:6px}',
    '.tiles{border-collapse:collapse;margin:auto}.tiles td{width:43px;',
    'height:38px;text-align:center;border:1px solid #d4dce1;font-size:.78rem}',
    '.tiles td.focal{outline:3px solid #16252d;outline-offset:-3px}',
    'svg{width:100%;height:auto}svg text{font:11px system-ui,sans-serif;',
    'fill:#526470}.chart-key{display:flex;gap:14px;font-size:.75rem}',
    '.focal-key:before,.neighbor-key:before{content:"";display:inline-block;',
    'width:18px;border-top:3px solid #12618a;margin-right:5px;',
    'vertical-align:middle}.neighbor-key:before{border-color:#7b8f9d;',
    'border-top-style:dashed}.daily-table{margin:10px 0}',
    '.daily-table summary{cursor:pointer}.daily-table table{border-collapse:collapse;',
    'font-size:.84rem}.daily-table th,.daily-table td{border:1px solid #d9e1e6;',
    'padding:3px 7px;text-align:right}.daily-table th:first-child,',
    '.daily-table td:first-child{text-align:left}</style></head><body>',
    '<h1>SNODAS relative-QC episode review</h1>',
    '<div class="intro"><p><strong>', nrow(episodes), ' episodes · ',
    nrow(cells), ' flagged cells · ', sum(!is.na(cells$known_rule_id)),
    ' documented mask references</strong></p>',
    '<p>These are diagnostic flags, not proof of an erroneous snow value. ',
    'The maps, source grids, mask rules, and publication statuses were ',
    'not changed. Peak-day grids show a 5×5 neighborhood; the center cell ',
    'has a black outline. The dashed history line is the median of valid ',
    'adjacent cells. Snow-free neighbors count for SWE and depth context.</p>',
    '</div>', paste(episode_html, collapse = ''), '</body></html>')
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- c(index = file.path(output_dir, "index.html"),
             cells = file.path(output_dir, "review-cells.csv"),
             history = file.path(output_dir, "daily-history.csv"))
  writeLines(html, paths[["index"]], useBytes = TRUE)
  utils::write.csv(cells, paths[["cells"]], row.names = FALSE)
  utils::write.csv(history, paths[["history"]], row.names = FALSE)
  message("Wrote local SNODAS episode report: ", paths[["index"]])
  list(paths = paths, cells = cells, history = history,
       episodes = episodes)
}
