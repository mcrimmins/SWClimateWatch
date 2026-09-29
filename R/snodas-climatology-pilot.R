# Calendar-day SNODAS climatology pilot. Source the SNODAS baseline, grid, and
# analysis-QC modules first. This does not download or publish snow maps.

snodas_pilot_calendar_dates <- function(month_day, years = 2005:2025) {
  years <- validate_snodas_baseline_years(years)
  if (!is.character(month_day) || length(month_day) != 1L ||
      is.na(month_day) || !grepl("^[0-9]{2}-[0-9]{2}$", month_day) ||
      is.na(as.Date(paste0("2000-", month_day))) ||
      month_day == "02-29") {
    stop("Choose one October-May month-day such as '02-15'; ",
         "leap day needs a separate policy.", call. = FALSE)
  }
  month <- as.integer(substr(month_day, 1L, 2L))
  if (!month %in% c(10L, 11L, 12L, 1L, 2L, 3L, 4L, 5L)) {
    stop("The SNODAS baseline pilot covers October-May only.", call. = FALSE)
  }
  calendar_year <- years - as.integer(month >= 10L)
  dates <- as.Date(sprintf("%d-%s", calendar_year, month_day))
  if (anyNA(dates)) stop("Invalid calendar day for selected years.",
                         call. = FALSE)
  data.frame(water_year = years, date = dates)
}

plan_snodas_baseline_day <- function(month_day, years = 2005:2025,
                                     processed_dir = swc_paths$processed) {
  dates <- snodas_pilot_calendar_dates(month_day, years)
  swe_paths <- vapply(dates$date, snodas_processed_path, character(1),
                      variable = "swe", processed_dir = processed_dir)
  depth_paths <- vapply(dates$date, snodas_processed_path, character(1),
                        variable = "depth", processed_dir = processed_dir)
  verified <- snodas_cool_season_processed(data.frame(
    date = dates$date, path = swe_paths, complete = TRUE
  ), processed_dir)$complete
  data.frame(dates, swe_path = swe_paths, depth_path = depth_paths,
             ready = verified)
}

summarize_snodas_baseline_stack <- function(stack,
                                             snow_threshold_inches = 0.1,
                                             min_years = 15L) {
  if (!inherits(stack, "SpatRaster") || terra::nlyr(stack) < 1L ||
      !is.numeric(snow_threshold_inches) ||
      length(snow_threshold_inches) != 1L ||
      !is.finite(snow_threshold_inches) || snow_threshold_inches <= 0 ||
      !is.numeric(min_years) || length(min_years) != 1L ||
      !is.finite(min_years) || min_years != floor(min_years) ||
      min_years < 1L || min_years > terra::nlyr(stack)) {
    stop("Invalid SNODAS baseline stack, snow threshold, or minimum years.",
         call. = FALSE)
  }
  # One date per water year: adjacent days are not treated as extra years.
  sample_years <- terra::app(!is.na(stack), fun = "sum")
  snow_years <- terra::app(stack >= snow_threshold_inches,
                           fun = "sum", na.rm = TRUE)
  median_swe <- terra::app(stack, fun = "median", na.rm = TRUE)
  eligible <- sample_years >= min_years
  median_swe <- terra::ifel(eligible, median_swe, NA)
  snow_frequency <- terra::ifel(eligible, snow_years / sample_years, NA)
  list(median_swe = median_swe,
       snow_frequency = snow_frequency,
       sample_years = sample_years)
}

build_snodas_baseline_day <- function(
    month_day, years = 2005:2025,
    snow_threshold_inches = 0.1, min_years = 15L,
    processed_dir = swc_paths$processed,
    template = snodas_common_grid(), output_dir = NULL,
    overwrite = FALSE) {
  plan <- plan_snodas_baseline_day(month_day, years, processed_dir)
  if (!all(plan$ready)) {
    stop("Missing or unverified processed SNODAS pair(s): ",
         paste(plan$date[!plan$ready], collapse = ", "), call. = FALSE)
  }
  if (!identical(plan$water_year,
                 seq.int(min(plan$water_year), max(plan$water_year)))) {
    stop("Pilot output requires consecutive water years.", call. = FALSE)
  }
  if (is.null(output_dir)) {
    output_dir <- file.path(
      processed_dir, "snodas", swc_snodas$aoi_id, "climatology",
      sprintf("wy%d-wy%d", min(plan$water_year), max(plan$water_year)),
      "pilot-calendar-day", month_day
    )
  }
  paths <- file.path(output_dir, c("median_swe.tif", "snow_frequency.tif",
                                   "sample_years.tif", "qc-summary.csv"))
  names(paths) <- c("median_swe", "snow_frequency", "sample_years", "qc")
  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite)) {
    stop("`overwrite` must be TRUE or FALSE.", call. = FALSE)
  }
  if (!overwrite && any(file.exists(paths))) {
    stop("SNODAS pilot output already exists; inspect it or use ",
         "overwrite=TRUE.", call. = FALSE)
  }
  # Validate output parameters before reading the complete raster set.
  if (!is.numeric(min_years) || length(min_years) != 1L ||
      !is.finite(min_years) || min_years != floor(min_years) ||
      min_years < 1L || min_years > nrow(plan) ||
      !is.numeric(snow_threshold_inches) ||
      length(snow_threshold_inches) != 1L ||
      !is.finite(snow_threshold_inches) ||
      snow_threshold_inches <= 0) {
    stop("Invalid snow threshold or minimum sample years.", call. = FALSE)
  }
  aligned <- vector("list", nrow(plan))
  qc <- vector("list", nrow(plan))
  for (index in seq_len(nrow(plan))) {
    screened <- screen_snodas_analysis_pair(
      terra::rast(plan$swe_path[index]),
      terra::rast(plan$depth_path[index])
    )
    aligned[[index]] <- snodas_align_common_grid(screened$swe, template)
    qc[[index]] <- cbind(plan[index, c("water_year", "date")],
                         screened$summary[, -1L, drop = FALSE])
    if (index %% 5L == 0L || index == nrow(plan)) {
      message(sprintf("SNODAS %s pilot: %d/%d years screened and aligned.",
                      month_day, index, nrow(plan)))
    }
  }
  stack <- do.call(c, aligned)
  products <- summarize_snodas_baseline_stack(
    stack, snow_threshold_inches, min_years
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
  qc$method <- "calendar-day-one-sample-per-water-year"
  qc$snow_threshold_inches <- snow_threshold_inches
  qc$min_years <- as.integer(min_years)
  utils::write.csv(qc, paths[["qc"]], row.names = FALSE)
  message("Wrote SNODAS calendar-day pilot: ", output_dir)
  list(paths = paths, qc = qc, month_day = month_day,
       years = plan$water_year,
       snow_threshold_inches = snow_threshold_inches,
       min_years = min_years)
}
