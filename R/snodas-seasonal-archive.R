# Unpublished October-May SNODAS archive summaries. Source the SNODAS
# bootstrap, grid, paired-screening, and Southwest map modules first.

snodas_seasonal_summary <- function(
    dates, template, read_day, expected_days,
    snow_threshold_inches = 0.1, minimum_coverage = 0.90,
    progress_every = 25L) {
  dates <- sort(unique(as.Date(dates)))
  if (!length(dates) || anyNA(dates) ||
      !inherits(template, "SpatRaster") || terra::nlyr(template) != 1L ||
      !is.function(read_day) ||
      length(expected_days) != 1L || !is.numeric(expected_days) ||
      !is.finite(expected_days) || expected_days != floor(expected_days) ||
      expected_days < length(dates) ||
      length(snow_threshold_inches) != 1L ||
      !is.numeric(snow_threshold_inches) ||
      !is.finite(snow_threshold_inches) || snow_threshold_inches <= 0 ||
      length(minimum_coverage) != 1L ||
      !is.numeric(minimum_coverage) ||
      !is.finite(minimum_coverage) ||
      minimum_coverage <= 0 || minimum_coverage > 1 ||
      length(progress_every) != 1L || !is.numeric(progress_every) ||
      !is.finite(progress_every) || progress_every != floor(progress_every) ||
      progress_every < 1L) {
    stop("Invalid SNODAS seasonal summary inputs.", call. = FALSE)
  }
  cells <- terra::ncell(template)
  peak <- rep(-Inf, cells)
  snow_days <- integer(cells)
  valid_days <- integer(cells)
  excluded_days <- 0L
  excluded_cells <- 0L
  for (index in seq_along(dates)) {
    day <- read_day(dates[index])
    if (!is.list(day) ||
        !all(c("swe", "excluded_cells") %in% names(day)) ||
        !inherits(day$swe, "SpatRaster") ||
        terra::nlyr(day$swe) != 1L ||
        !terra::compareGeom(day$swe, template, stopOnError = FALSE) ||
        length(day$excluded_cells) != 1L ||
        is.na(day$excluded_cells) || day$excluded_cells < 0) {
      stop("Invalid aligned SNODAS SWE for ", dates[index], call. = FALSE)
    }
    values <- terra::values(day$swe, mat = FALSE)
    valid <- is.finite(values)
    peak[valid] <- pmax(peak[valid], values[valid])
    snow_days[valid] <- snow_days[valid] +
      as.integer(values[valid] >= snow_threshold_inches)
    valid_days[valid] <- valid_days[valid] + 1L
    if (day$excluded_cells > 0L) {
      excluded_days <- excluded_days + 1L
      excluded_cells <- excluded_cells + day$excluded_cells
    }
    if (index %% progress_every == 0L || index == length(dates)) {
      message(sprintf("SNODAS seasonal summary: %d/%d days.",
                      index, length(dates)))
    }
  }
  adequate <- valid_days >= ceiling(minimum_coverage * expected_days)
  peak[!adequate] <- NA_real_
  snow_days <- as.numeric(snow_days)
  snow_days[!adequate] <- NA_real_
  make_grid <- function(values, name) {
    result <- terra::setValues(template, values)
    names(result) <- name
    result
  }
  list(
    peak_swe = make_grid(peak, "seasonal_peak_swe"),
    snow_days = make_grid(snow_days, "seasonal_snow_days"),
    coverage = make_grid(valid_days / expected_days, "seasonal_coverage"),
    metrics = data.frame(
      expected_days = expected_days, listed_days = length(dates),
      known_missing_days = expected_days - length(dates),
      sufficient_coverage_cells = sum(adequate),
      peak_max_inches = if (any(adequate)) max(peak, na.rm = TRUE)
                        else NA_real_,
      peak_cells_for_review = sum(peak >= 50, na.rm = TRUE),
      days_with_pairwise_exclusions = excluded_days,
      pairwise_excluded_cells = excluded_cells,
      snow_threshold_inches = snow_threshold_inches,
      minimum_coverage = minimum_coverage,
      stringsAsFactors = FALSE
    )
  )
}

snodas_seasonal_peak_qc_rules <- function(water_year) {
  # Reviewed source-level exceptions, corroborated against nearby SNOTEL
  # observations and the eight surrounding SNODAS cells. Never alter the
  # source daily grids or apply a blanket high-SWE cutoff.
  # Keep each year's rule frame independent: its serialized form is part of
  # the completion signature, so adding another year must not stale WY2016.
  rules <- list(
    `2014` = data.frame(
      water_year = 2014L,
      rule_id = "wy2014-wolf-creek-peak-swe",
      longitude = -106.7875,
      latitude = 37.4875,
      expected_peak_inches = 72.87402,
      tolerance_inches = 0.01,
      stringsAsFactors = FALSE
    ),
    `2016` = data.frame(
      water_year = 2016L,
      rule_id = "wy2016-promontory-peak-swe",
      longitude = -111.0042,
      latitude = 34.3708,
      expected_peak_inches = 53.50394,
      tolerance_inches = 0.01,
      stringsAsFactors = FALSE
    )
  )
  key <- as.character(water_year)
  if (!key %in% names(rules)) {
    return(rules[["2016"]][FALSE, , drop = FALSE])
  }
  selected <- rules[[key]]
  selected[selected$water_year == water_year, , drop = FALSE]
}

snodas_seasonal_source_signature <- function(dates, source_md5,
                                             template, water_year) {
  qc_rules <- snodas_seasonal_peak_qc_rules(water_year)
  digest::digest(c(
    as.character(dates), source_md5,
    as.character(terra::ext(template)), as.character(terra::res(template)),
    as.character(c(terra::nrow(template), terra::ncol(template))),
    "seasonal-peak-snowdays-v1", "threshold=0.1", "coverage=0.9",
    if (nrow(qc_rules)) digest::digest(qc_rules, algo = "sha256")
  ), algo = "sha256")
}

snodas_apply_seasonal_peak_qc <- function(raster, rules) {
  if (!inherits(raster, "SpatRaster") || terra::nlyr(raster) != 1L ||
      !is.data.frame(rules) ||
      !all(c("rule_id", "longitude", "latitude", "expected_peak_inches",
             "tolerance_inches") %in% names(rules))) {
    stop("Invalid SNODAS seasonal peak QC inputs.", call. = FALSE)
  }
  if (!nrow(rules)) {
    return(list(raster = raster, masked_cells = 0L,
                original_inches = numeric()))
  }
  values <- terra::values(raster, mat = FALSE)
  original <- numeric(nrow(rules))
  selected <- integer(nrow(rules))
  for (index in seq_len(nrow(rules))) {
    point <- matrix(c(rules$longitude[index], rules$latitude[index]), ncol = 2L)
    cell <- terra::cellFromXY(raster, point)
    if (length(cell) != 1L || is.na(cell) || cell %in% selected ||
        any(abs(terra::xyFromCell(raster, cell) - point) > 1e-4)) {
      stop("SNODAS seasonal QC cell geometry changed for ",
           rules$rule_id[index], call. = FALSE)
    }
    value <- values[cell]
    if (!is.finite(value) ||
        abs(value - rules$expected_peak_inches[index]) >
          rules$tolerance_inches[index]) {
      stop("SNODAS seasonal QC source value changed for ",
           rules$rule_id[index], "; review before masking.",
           call. = FALSE)
    }
    selected[index] <- cell
    original[index] <- value
  }
  values[selected] <- NA_real_
  list(raster = terra::setValues(raster, values),
       masked_cells = length(selected), original_inches = original)
}

snodas_seasonal_quality_gate <- function(metrics) {
  if (!is.data.frame(metrics) || nrow(metrics) != 1L ||
      !all(c("sufficient_coverage_cells", "peak_cells_for_review",
             "days_with_pairwise_exclusions", "known_missing_days") %in%
           names(metrics))) {
    stop("Invalid SNODAS seasonal quality metrics.", call. = FALSE)
  }
  failures <- character()
  reviews <- character()
  if (metrics$sufficient_coverage_cells[[1L]] == 0L) {
    failures <- c(failures, "no cells meet seasonal coverage requirement")
  }
  if (metrics$peak_cells_for_review[[1L]] > 0L) {
    reviews <- c(reviews, "peak SWE at or above 50 inches")
  }
  if (metrics$days_with_pairwise_exclusions[[1L]] > 0L) {
    reviews <- c(reviews, "paired SWE/depth cells excluded")
  }
  if (metrics$known_missing_days[[1L]] > 0L) {
    reviews <- c(reviews, "some dates absent from the source inventory")
  }
  if ("peak_qc_masked_cells" %in% names(metrics) &&
      metrics$peak_qc_masked_cells[[1L]] > 0L) {
    reviews <- c(reviews, "documented peak SWE source cell masked")
  }
  data.frame(
    status = if (length(failures)) "FAIL" else if (length(reviews)) {
      "REVIEW"
    } else "PASS",
    reasons = paste(c(failures, reviews), collapse = "; "),
    stringsAsFactors = FALSE
  )
}

snodas_seasonal_map_key <- function(product) {
  switch(product, peak_swe = "peak_map",
         snow_days = "snow_days_map",
         stop("Unknown SNODAS seasonal map product: ", product,
              call. = FALSE))
}

plot_snodas_seasonal_archive <- function(
    raster, water_year, product = c("peak_swe", "snow_days"),
    states = southwest_state_boundaries(),
    counties = southwest_county_boundaries(),
    countries = southwest_country_boundaries(),
    cities = southwest_reference_cities()) {
  product <- match.arg(product)
  common <- list(
    raster = raster, states = states, counties = counties,
    countries = countries, cities = cities, caption = NULL,
    mask_to_states = FALSE, scale_type = "categorical",
    subtitle = sprintf("October %d-May %d", water_year - 1L, water_year)
  )
  if (product == "peak_swe") {
    return(do.call(southwest_raster_map, c(common, list(
      title = sprintf("Peak snow water equivalent - WY%d", water_year),
      fill_label = "Peak SWE (inches)",
      product_id = "snodas_swe_observed",
      palette = c("#f7f7f4", "#d7e9f1", "#a6cfe2", "#6baed6",
                  "#3182bd", "#225ea8", "#253494", "#54278f",
                  "#8b176a", "#67104f"),
      palette_values = c(0, 0.1, 1, 2, 4, 8, 12, 20, 30, 90),
      limits = c(0, 90)
    ))))
  }
  do.call(southwest_raster_map, c(common, list(
    title = sprintf("Snow-covered days - WY%d", water_year),
    fill_label = "Days with SWE >=0.1 inch",
    product_id = "snodas_snow_days",
    palette = c("#f7f7f4", "#d9edf4", "#a9d5e8", "#74b8d8",
                "#4796c2", "#2776b0", "#34569d", "#57398d",
                "#7a216b"),
    palette_values = c(0, 1, 7, 30, 60, 90, 120, 180, 244),
    limits = c(0, 244)
  )))
}

snodas_resume_seasonal_grids <- function(
    water_year, plan, template, paths, inputs, source_md5,
    expected_days,
    audit_path = file.path("data", "diagnostics", "snodas-audit",
                           sprintf("wy%d-grid-quality.csv", water_year))) {
  grids <- paths[c("peak_swe", "snow_days", "coverage")]
  if (!all(file.exists(grids)) ||
      any(file.info(grids)$size <= 0) ||
      any(file.info(grids)$mtime < max(file.info(inputs)$mtime))) {
    stop("Partial seasonal grids are missing or older than a source grid; ",
         "rerun the full calculation.", call. = FALSE)
  }
  rasters <- lapply(grids, terra::rast)
  if (any(!vapply(rasters, function(x) {
    terra::nlyr(x) == 1L &&
      terra::compareGeom(x, template, stopOnError = FALSE)
  }, logical(1)))) {
    stop("Partial seasonal grid geometry is invalid; rerun the calculation.",
         call. = FALSE)
  }
  peak <- terra::values(rasters$peak_swe, mat = FALSE)
  days <- terra::values(rasters$snow_days, mat = FALSE)
  coverage <- terra::values(rasters$coverage, mat = FALSE)
  if (any(is.finite(peak) & (peak < 0 | !is.finite(days))) ||
      any(is.finite(days) & (days < 0 | days > expected_days |
                            abs(days - round(days)) > 1e-5)) ||
      any(is.finite(coverage) & (coverage < 0 | coverage > 1)) ||
      any(is.finite(peak) &
          (!is.finite(coverage) | coverage < 0.9))) {
    stop("Partial seasonal grid values are invalid; rerun the calculation.",
         call. = FALSE)
  }
  audit <- read_snodas_season_audit(audit_path)
  keys <- paste(rep(as.character(plan$date), 2L),
                rep(swc_snodas$variables, each = nrow(plan)))
  rows <- audit[match(keys, paste(audit$date, audit$variable)), ,
                drop = FALSE]
  required <- c("swe_md5", "depth_md5", "cells", "valid_fraction",
                "both_valid_fraction", "negative_cells", "saturated_cells",
                "swe_exceeds_depth_cells")
  if (!all(required %in% names(audit))) {
    stop("Season audit lacks fields needed to resume partial grids; ",
         "rerun the full calculation.", call. = FALSE)
  }
  if (nrow(rows) != length(keys) ||
      anyNA(rows[, required, drop = FALSE]) ||
      !identical(as.character(rows$date), rep(as.character(plan$date), 2L)) ||
      !identical(as.character(rows$variable),
                 rep(swc_snodas$variables, each = nrow(plan))) ||
      !identical(as.character(rows$swe_md5), rep(
        source_md5[seq_len(nrow(plan))], 2L)) ||
      !identical(as.character(rows$depth_md5), rep(
        source_md5[nrow(plan) + seq_len(nrow(plan))], 2L)) ||
      any(rows$negative_cells > 0L | rows$saturated_cells > 0L)) {
    stop("A complete, matching zero-range-flag season audit is required ",
         "to resume partial grids; rerun the full calculation.",
         call. = FALSE)
  }
  swe <- rows[seq_len(nrow(plan)), , drop = FALSE]
  depth <- rows[nrow(plan) + seq_len(nrow(plan)), , drop = FALSE]
  one_sided <- round(
    (swe$valid_fraction + depth$valid_fraction -
       2 * swe$both_valid_fraction) * swe$cells
  )
  excluded <- one_sided + swe$swe_exceeds_depth_cells
  if (any(one_sided < 0L) ||
      any(abs(one_sided - (swe$valid_fraction + depth$valid_fraction -
                          2 * swe$both_valid_fraction) * swe$cells) > 0.25)) {
    stop("Could not reconstruct paired exclusions from the audit; ",
         "rerun the full calculation.", call. = FALSE)
  }
  list(
    peak_swe = rasters$peak_swe,
    snow_days = rasters$snow_days,
    coverage = rasters$coverage,
    metrics = data.frame(
      expected_days = expected_days, listed_days = nrow(plan),
      known_missing_days = expected_days - nrow(plan),
      sufficient_coverage_cells = sum(is.finite(peak)),
      peak_max_inches = if (any(is.finite(peak))) max(peak, na.rm = TRUE)
                        else NA_real_,
      peak_cells_for_review = sum(peak >= 50, na.rm = TRUE),
      days_with_pairwise_exclusions = sum(excluded > 0L),
      pairwise_excluded_cells = sum(excluded),
      snow_threshold_inches = 0.1, minimum_coverage = 0.9,
      stringsAsFactors = FALSE
    )
  )
}

build_snodas_seasonal_archive_year <- function(
    water_year = 2024L,
    inventory_path = file.path("data", "diagnostics", "snodas-audit",
                               "monthly-directory-inventory.csv"),
    raw_dir = swc_paths$raw,
    processed_dir = swc_paths$processed,
    output_dir = file.path("data", "diagnostics", "snodas-seasonal-archive",
                           sprintf("wy%04d", water_year)),
    template = snodas_common_grid(),
    render_maps = TRUE,
    overwrite = FALSE,
    resume_partial = FALSE) {
  if (length(water_year) != 1L || !is.numeric(water_year) ||
      is.na(water_year) || water_year != floor(water_year) ||
      water_year < 2005L || water_year > 2025L) {
    stop("Choose a complete SNODAS water year from 2005-2025.",
         call. = FALSE)
  }
  if (length(render_maps) != 1L || !is.logical(render_maps) ||
      is.na(render_maps) ||
      length(overwrite) != 1L || !is.logical(overwrite) ||
      is.na(overwrite) ||
      length(resume_partial) != 1L || !is.logical(resume_partial) ||
      is.na(resume_partial) || (overwrite && resume_partial)) {
    stop("render_maps, overwrite, and resume_partial must be logical; ",
         "overwrite and resume_partial cannot both be TRUE.", call. = FALSE)
  }
  plan <- plan_snodas_cool_season(water_year, inventory_path, raw_dir)
  if (any(!snodas_cool_season_processed(plan, processed_dir)$complete)) {
    stop("SNODAS WY", water_year, " has unprocessed listed dates.",
         call. = FALSE)
  }
  start <- as.Date(sprintf("%d-10-01", water_year - 1L))
  end <- as.Date(sprintf("%d-05-31", water_year))
  expected_days <- length(seq(start, end, by = "day"))
  if (nrow(plan) < ceiling(0.9 * expected_days)) {
    stop("Too many missing SNODAS dates for WY", water_year,
         " seasonal maps.", call. = FALSE)
  }
  inputs <- unlist(lapply(swc_snodas$variables, function(variable) {
    vapply(plan$date, snodas_processed_path, character(1),
           variable = variable, processed_dir = processed_dir)
  }), use.names = FALSE)
  source_md5 <- unname(tools::md5sum(inputs))
  if (anyNA(source_md5)) {
    stop("Could not checksum all SNODAS seasonal source grids.",
         call. = FALSE)
  }
  qc_rules <- snodas_seasonal_peak_qc_rules(water_year)
  signature <- snodas_seasonal_source_signature(
    plan$date, source_md5, template, water_year)
  paths <- c(
    peak_swe = file.path(output_dir, "peak_swe.tif"),
    snow_days = file.path(output_dir, "snow_days.tif"),
    coverage = file.path(output_dir, "coverage.tif"),
    peak_map = file.path(output_dir, "peak_swe.png"),
    snow_days_map = file.path(output_dir, "snow_days.png"),
    quality = file.path(output_dir, "quality-summary.csv"),
    complete = file.path(output_dir, "complete.csv")
  )
  if (!overwrite && file.exists(paths[["complete"]])) {
    marker <- tryCatch(utils::read.csv(paths[["complete"]],
                                       stringsAsFactors = FALSE),
                       error = function(e) NULL)
    products <- paths[if (render_maps) {
      names(paths) != "complete"
    } else {
      !names(paths) %in% c("complete", "peak_map", "snow_days_map")
    }]
    if (!is.null(marker) && nrow(marker) == 1L &&
        identical(marker$source_signature, signature) &&
        all(file.exists(products)) &&
        all(paste0(names(products), "_md5") %in% names(marker)) &&
        all(unname(tools::md5sum(products)) ==
            unname(unlist(marker[1L, paste0(names(products), "_md5")])))) {
      message("SNODAS WY", water_year, " seasonal summary is current.")
      return(list(paths = paths, quality = utils::read.csv(
        paths[["quality"]], stringsAsFactors = FALSE), refreshed = FALSE))
    }
  }
  if (resume_partial && nrow(qc_rules)) {
    stop("WY", water_year, " has a peak-SWE QC exception; rerun from the ",
         "daily grids instead of resuming partial seasonal grids.",
         call. = FALSE)
  }
  read_day <- function(date) {
    swe <- terra::rast(snodas_processed_path(date, "swe", processed_dir))
    depth <- terra::rast(snodas_processed_path(date, "depth", processed_dir))
    if (length(terra::time(swe)) != 1L ||
        length(terra::time(depth)) != 1L ||
        is.na(terra::time(swe)) || is.na(terra::time(depth)) ||
        as.Date(terra::time(swe)) != date ||
        as.Date(terra::time(depth)) != date) {
      stop("SNODAS seasonal source date mismatch: ", date, call. = FALSE)
    }
    screened <- screen_snodas_analysis_pair(swe, depth)
    list(swe = snodas_align_common_grid(screened$swe, template),
         excluded_cells = screened$summary$excluded_cells[[1L]])
  }
  if (resume_partial) {
    message("Verifying and reusing existing WY", water_year,
            " seasonal rasters.")
    result <- snodas_resume_seasonal_grids(
      water_year, plan, template, paths, inputs, source_md5,
      expected_days)
  } else {
    result <- snodas_seasonal_summary(plan$date, template, read_day,
                                      expected_days)
  }
  masked <- snodas_apply_seasonal_peak_qc(result$peak_swe, qc_rules)
  result$peak_swe <- masked$raster
  result$metrics$peak_qc_masked_cells <- masked$masked_cells
  result$metrics$peak_qc_rule_ids <- paste(qc_rules$rule_id, collapse = "; ")
  result$metrics$peak_qc_original_inches <- if (masked$masked_cells) {
    paste(format(masked$original_inches, digits = 8L), collapse = "; ")
  } else ""
  if (masked$masked_cells) {
    peak <- terra::values(result$peak_swe, mat = FALSE)
    result$metrics$peak_max_inches <- if (any(is.finite(peak))) {
      max(peak, na.rm = TRUE)
    } else NA_real_
    result$metrics$peak_cells_for_review <- sum(peak >= 50, na.rm = TRUE)
  }
  gate <- snodas_seasonal_quality_gate(result$metrics)
  quality <- cbind(data.frame(water_year = water_year,
                             source_signature = signature),
                   result$metrics, gate)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  if (!resume_partial) {
    for (name in c("peak_swe", "snow_days", "coverage")) {
      terra::writeRaster(result[[name]], paths[[name]], overwrite = TRUE,
                         datatype = "FLT4S", gdal = "COMPRESS=DEFLATE")
    }
  }
  utils::write.csv(quality, paths[["quality"]], row.names = FALSE)
  if (render_maps) {
    states <- southwest_state_boundaries()
    counties <- southwest_county_boundaries()
    countries <- southwest_country_boundaries()
    cities <- southwest_reference_cities()
    for (name in c("peak_swe", "snow_days")) {
      plot <- plot_snodas_seasonal_archive(
        result[[name]], water_year, name,
        states, counties, countries, cities)
      map_key <- snodas_seasonal_map_key(name)
      save_southwest_map(
        plot, paths[[map_key]],
        logo_path = southwest_brand_logo_path(),
        footer_text = paste0("Data source: NOAA/NSIDC SNODAS\n",
                             "Season: October-May, WY", water_year))
    }
  }
  products <- paths[if (render_maps) {
    names(paths) != "complete"
  } else {
    !names(paths) %in% c("complete", "peak_map", "snow_days_map")
  }]
  if (all(file.exists(products))) {
    marker <- data.frame(source_signature = signature)
    for (name in names(products)) {
      marker[[paste0(name, "_md5")]] <-
        unname(tools::md5sum(products[[name]]))
    }
    utils::write.csv(marker, paths[["complete"]], row.names = FALSE)
  }
  list(paths = paths, quality = quality, refreshed = TRUE)
}
