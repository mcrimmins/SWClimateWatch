# Centered five-day SNODAS climatology comparison pilot. Source the calendar-
# day pilot and its dependencies first. This does not download or publish maps.

snodas_window_known_missing_dates <- function(raw_dir = swc_paths$raw) {
  errata <- read_snodas_missing_days(file.path(
    raw_dir, "snodas", "reference", "G02158_missing_files.txt"
  ))
  sort(unique(c(errata$all_missing, errata$bad_swe)))
}

plan_snodas_window_baseline_day <- function(
    month_day, years = 2005:2025,
    processed_dir = swc_paths$processed,
    known_missing_dates = snodas_window_known_missing_dates()) {
  if (!inherits(known_missing_dates, "Date") ||
      anyNA(known_missing_dates)) {
    stop("`known_missing_dates` must be a Date vector.", call. = FALSE)
  }
  centers <- snodas_pilot_calendar_dates(month_day, years)
  offsets <- -2L:2L
  plan <- centers[rep(seq_len(nrow(centers)), each = length(offsets)), ]
  plan$offset_days <- rep(offsets, times = nrow(centers))
  plan$date <- plan$date + plan$offset_days
  first <- as.Date(sprintf("%d-10-01", plan$water_year - 1L))
  last <- as.Date(sprintf("%d-05-31", plan$water_year))
  # At the October/May edges, use the in-season portion of the centered
  # window (three or four days); never pull September/June source days.
  plan <- plan[plan$date >= first & plan$date <= last, , drop = FALSE]
  plan$swe_path <- vapply(plan$date, snodas_processed_path, character(1),
                          variable = "swe", processed_dir = processed_dir)
  plan$depth_path <- vapply(plan$date, snodas_processed_path, character(1),
                            variable = "depth", processed_dir = processed_dir)
  plan$ready <- snodas_cool_season_processed(data.frame(
    date = plan$date, path = plan$swe_path, complete = TRUE
  ), processed_dir)$complete
  plan$known_missing <- plan$date %in% known_missing_dates
  rownames(plan) <- NULL
  plan
}

summarize_snodas_window_year <- function(
    stack, snow_threshold_inches = 0.1, min_valid_days = 3L) {
  if (!inherits(stack, "SpatRaster") ||
      terra::nlyr(stack) < 3L || terra::nlyr(stack) > 5L ||
      !is.numeric(snow_threshold_inches) ||
      length(snow_threshold_inches) != 1L ||
      !is.finite(snow_threshold_inches) || snow_threshold_inches <= 0 ||
      !is.numeric(min_valid_days) || length(min_valid_days) != 1L ||
      !is.finite(min_valid_days) || min_valid_days != floor(min_valid_days) ||
      min_valid_days < 1L || min_valid_days > terra::nlyr(stack)) {
    stop("Invalid five-day SNODAS stack or window parameters.",
         call. = FALSE)
  }
  valid_days <- terra::app(!is.na(stack), fun = "sum")
  eligible <- valid_days >= min_valid_days
  median_swe <- terra::ifel(
    eligible, terra::app(stack, fun = "median", na.rm = TRUE), NA
  )
  snow_days <- terra::app(stack >= snow_threshold_inches,
                          fun = "sum", na.rm = TRUE)
  snow_fraction <- terra::ifel(eligible, snow_days / valid_days, NA)
  list(median_swe = median_swe, snow_fraction = snow_fraction)
}

summarize_snodas_window_years <- function(
    yearly_medians, yearly_snow_fractions, min_years = 15L) {
  if (!inherits(yearly_medians, "SpatRaster") ||
      !inherits(yearly_snow_fractions, "SpatRaster") ||
      terra::nlyr(yearly_medians) != terra::nlyr(yearly_snow_fractions) ||
      !terra::compareGeom(yearly_medians, yearly_snow_fractions,
                          stopOnError = FALSE) ||
      !is.numeric(min_years) || length(min_years) != 1L ||
      !is.finite(min_years) || min_years != floor(min_years) ||
      min_years < 1L || min_years > terra::nlyr(yearly_medians)) {
    stop("Invalid yearly SNODAS summaries or minimum years.",
         call. = FALSE)
  }
  sample_years <- terra::app(!is.na(yearly_medians), fun = "sum")
  eligible <- sample_years >= min_years
  median_swe <- terra::ifel(
    eligible, terra::app(yearly_medians, fun = "median", na.rm = TRUE), NA
  )
  # Average within-year snow fractions: each year has equal weight even when
  # one year has fewer valid days in the centered window.
  snow_frequency <- terra::ifel(
    eligible, terra::app(yearly_snow_fractions, fun = "mean", na.rm = TRUE), NA
  )
  list(median_swe = median_swe, snow_frequency = snow_frequency,
       sample_years = sample_years)
}

build_snodas_window_baseline_day <- function(
    month_day, years = 2005:2025,
    snow_threshold_inches = 0.1, min_valid_days = 3L, min_years = 15L,
    processed_dir = swc_paths$processed,
    template = snodas_common_grid(), output_dir = NULL,
    overwrite = FALSE,
    known_missing_dates = snodas_window_known_missing_dates(),
    progress_label = "five-day pilot") {
  if (!is.character(progress_label) || length(progress_label) != 1L ||
      is.na(progress_label) || !nzchar(progress_label)) {
    stop("`progress_label` must be nonempty text.", call. = FALSE)
  }
  plan <- plan_snodas_window_baseline_day(
    month_day, years, processed_dir, known_missing_dates
  )
  unexpected_missing <- !plan$ready & !plan$known_missing
  if (any(unexpected_missing)) {
    stop("Missing or unverified processed SNODAS pair(s): ",
         paste(plan$date[unexpected_missing], collapse = ", "),
         call. = FALSE)
  }
  water_years <- sort(unique(plan$water_year))
  if (!identical(water_years,
                 seq.int(min(water_years), max(water_years)))) {
    stop("Pilot output requires consecutive water years.", call. = FALSE)
  }
  if (!is.numeric(min_years) || length(min_years) != 1L ||
      !is.finite(min_years) || min_years != floor(min_years) ||
      min_years < 1L || min_years > length(water_years)) {
    stop("`min_years` must be between 1 and the number of water years.",
         call. = FALSE)
  }
  if (!is.numeric(snow_threshold_inches) ||
      length(snow_threshold_inches) != 1L ||
      !is.finite(snow_threshold_inches) || snow_threshold_inches <= 0 ||
      !is.numeric(min_valid_days) || length(min_valid_days) != 1L ||
      !is.finite(min_valid_days) ||
      min_valid_days != floor(min_valid_days) ||
      min_valid_days < 1L || min_valid_days > 5L) {
    stop("Invalid snow threshold or minimum valid days.", call. = FALSE)
  }
  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite)) {
    stop("`overwrite` must be TRUE or FALSE.", call. = FALSE)
  }
  if (is.null(output_dir)) {
    output_dir <- file.path(
      processed_dir, "snodas", swc_snodas$aoi_id, "climatology",
      sprintf("wy%d-wy%d", min(water_years), max(water_years)),
      "pilot-centered-05day", month_day
    )
  }
  paths <- file.path(output_dir, c("median_swe.tif", "snow_frequency.tif",
                                   "sample_years.tif", "qc-summary.csv"))
  names(paths) <- c("median_swe", "snow_frequency", "sample_years", "qc")
  if (!overwrite && any(file.exists(paths))) {
    stop("SNODAS window pilot output already exists; inspect it or use ",
         "overwrite=TRUE.", call. = FALSE)
  }
  yearly_medians <- vector("list", length(water_years))
  yearly_fractions <- vector("list", length(water_years))
  qc <- vector("list", nrow(plan))
  for (year_index in seq_along(water_years)) {
    rows <- which(plan$water_year == water_years[year_index])
    aligned <- vector("list", length(rows))
    for (day_index in seq_along(rows)) {
      row <- rows[day_index]
      if (!plan$ready[row]) {
        aligned[[day_index]] <- terra::setValues(template, NA_real_)
        qc[[row]] <- data.frame(
          water_year = plan$water_year[row], date = plan$date[row],
          offset_days = plan$offset_days[row],
          one_sided_missing_cells = NA_integer_,
          swe_exceeds_depth_cells = NA_integer_,
          invalid_range_cells = NA_integer_, excluded_cells = NA_integer_,
          availability = "known_missing"
        )
        next
      }
      screened <- screen_snodas_analysis_pair(
        terra::rast(plan$swe_path[row]),
        terra::rast(plan$depth_path[row])
      )
      aligned[[day_index]] <- snodas_align_common_grid(screened$swe,
                                                        template)
      qc[[row]] <- cbind(
        plan[row, c("water_year", "date", "offset_days")],
        screened$summary[, -1L, drop = FALSE],
        availability = "processed"
      )
    }
    year_product <- summarize_snodas_window_year(
      do.call(c, aligned), snow_threshold_inches, min_valid_days
    )
    yearly_medians[[year_index]] <- year_product$median_swe
    yearly_fractions[[year_index]] <- year_product$snow_fraction
    if (year_index %% 5L == 0L || year_index == length(water_years)) {
      message(sprintf("SNODAS %s %s: %d/%d years summarized.",
                      month_day, progress_label, year_index,
                      length(water_years)))
    }
  }
  products <- summarize_snodas_window_years(
    do.call(c, yearly_medians), do.call(c, yearly_fractions), min_years
  )
  reference_date <- as.Date(paste0("2000-", month_day))
  for (name in names(products)) {
    names(products[[name]]) <- paste0("snodas_", name, "_", month_day)
    terra::time(products[[name]]) <- reference_date
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  for (name in names(products)) {
    terra::writeRaster(products[[name]], paths[[name]], overwrite = overwrite,
                       datatype = "FLT4S", gdal = c("COMPRESS=DEFLATE"))
  }
  qc <- do.call(rbind, qc)
  qc$method <- "centered-05day-one-effective-sample-per-water-year"
  qc$snow_threshold_inches <- snow_threshold_inches
  qc$min_valid_days <- as.integer(min_valid_days)
  qc$min_years <- as.integer(min_years)
  utils::write.csv(qc, paths[["qc"]], row.names = FALSE)
  message("Wrote SNODAS ", progress_label, ": ", output_dir)
  list(paths = paths, qc = qc, month_day = month_day, years = water_years,
       snow_threshold_inches = snow_threshold_inches,
       min_valid_days = min_valid_days, min_years = min_years)
}
