# Resumable October-May SNODAS daily reference grids. Source the centered
# window pilot and its dependencies first. This reads processed regional grids
# only: it neither downloads SNODAS nor publishes map products.

snodas_climatology_month_days <- function() {
  format(seq(as.Date("1999-10-01"), as.Date("2000-05-31"), by = "day"),
         "%m-%d")
}

validate_snodas_climatology_days <- function(month_days) {
  calendar <- snodas_climatology_month_days()
  if (!is.character(month_days) || !length(month_days) ||
      anyNA(month_days) || any(!month_days %in% calendar)) {
    stop("Choose one or more October-May month-days (including 02-29).",
         call. = FALSE)
  }
  # Build February 29 last so both reference neighbors can be validated.
  order <- c(calendar[calendar != "02-29"], "02-29")
  order[order %in% unique(month_days)]
}

snodas_climatology_output_root <- function(
    years = 2005:2025, processed_dir = swc_paths$processed) {
  years <- validate_snodas_baseline_years(years)
  if (!identical(years, seq.int(min(years), max(years)))) {
    stop("Daily SNODAS reference requires consecutive water years.",
         call. = FALSE)
  }
  file.path(processed_dir, "snodas", swc_snodas$aoi_id, "climatology",
            sprintf("wy%d-wy%d", min(years), max(years)), "daily",
            "centered-05day")
}

snodas_climatology_day_paths <- function(output_root, month_day) {
  folder <- file.path(output_root, month_day)
  paths <- file.path(folder, c("median_swe.tif", "snow_frequency.tif",
                               "sample_years.tif", "qc-summary.csv",
                               "complete.csv"))
  names(paths) <- c("median_swe", "snow_frequency", "sample_years",
                    "qc", "complete")
  paths
}

snodas_climatology_spec <- function(
    month_day, years, snow_threshold_inches, min_valid_days, min_years) {
  years <- validate_snodas_baseline_years(years)
  if (!identical(years, seq.int(min(years), max(years))) ||
      !is.character(month_day) || length(month_day) != 1L ||
      is.na(month_day) || !month_day %in% snodas_climatology_month_days() ||
      !is.numeric(snow_threshold_inches) ||
      length(snow_threshold_inches) != 1L ||
      !is.finite(snow_threshold_inches) || snow_threshold_inches <= 0 ||
      !is.numeric(min_valid_days) || length(min_valid_days) != 1L ||
      !is.finite(min_valid_days) || min_valid_days != floor(min_valid_days) ||
      min_valid_days < 1L || min_valid_days > 3L ||
      !is.numeric(min_years) || length(min_years) != 1L ||
      !is.finite(min_years) || min_years != floor(min_years) ||
      min_years < 1L || min_years > length(years)) {
    stop("Invalid SNODAS daily reference parameters.", call. = FALSE)
  }
  data.frame(
    method_version = "centered-05day-yearly-v1",
    month_day = month_day,
    reference_years = paste(years, collapse = ","),
    snow_threshold_inches = snow_threshold_inches,
    min_valid_days = as.integer(min_valid_days),
    min_years = as.integer(min_years),
    leap_day_method = if (month_day == "02-29") {
      "interpolate-adjacent-reference-days"
    } else "daily-observations",
    stringsAsFactors = FALSE
  )
}

snodas_climatology_day_complete <- function(paths, spec) {
  if (!all(file.exists(paths)) ||
      anyNA(file.info(paths)$size) || any(file.info(paths)$size <= 0)) {
    return(FALSE)
  }
  marker <- tryCatch(utils::read.csv(paths[["complete"]],
                                     stringsAsFactors = FALSE),
                     error = function(e) NULL)
  expected <- c(names(spec), paste0(names(paths)[names(paths) != "complete"],
                                    "_md5"))
  if (is.null(marker) || nrow(marker) != 1L ||
      !all(expected %in% names(marker))) return(FALSE)
  for (name in names(spec)) {
    if (is.na(marker[[name]][1L]) ||
        as.character(marker[[name]][1L]) != as.character(spec[[name]][1L])) {
      return(FALSE)
    }
  }
  products <- paths[names(paths) != "complete"]
  actual_md5 <- unname(tools::md5sum(products))
  recorded_md5 <- unname(unlist(marker[1L, paste0(names(products), "_md5")]))
  !anyNA(actual_md5) && identical(actual_md5, recorded_md5)
}

write_snodas_climatology_completion <- function(paths, spec) {
  products <- paths[names(paths) != "complete"]
  md5 <- unname(tools::md5sum(products))
  if (anyNA(md5)) stop("Could not checksum SNODAS reference outputs.",
                       call. = FALSE)
  for (index in seq_along(products)) {
    spec[[paste0(names(products)[index], "_md5")]] <- md5[index]
  }
  temporary <- tempfile("snodas-complete-", tmpdir = dirname(paths[["complete"]]),
                        fileext = ".csv")
  on.exit(if (file.exists(temporary)) unlink(temporary), add = TRUE)
  utils::write.csv(spec, temporary, row.names = FALSE)
  if (!file.copy(temporary, paths[["complete"]], overwrite = TRUE)) {
    stop("Could not write SNODAS completion marker: ", paths[["complete"]],
         call. = FALSE)
  }
  invisible(paths[["complete"]])
}

plan_snodas_daily_climatology <- function(
    month_days = snodas_climatology_month_days(),
    years = 2005:2025, snow_threshold_inches = 0.1,
    min_valid_days = 3L, min_years = 15L,
    processed_dir = swc_paths$processed, output_root = NULL) {
  days <- validate_snodas_climatology_days(month_days)
  if (is.null(output_root)) {
    output_root <- snodas_climatology_output_root(years, processed_dir)
  }
  rows <- lapply(days, function(day) {
    spec <- snodas_climatology_spec(
      day, years, snow_threshold_inches, min_valid_days, min_years
    )
    paths <- snodas_climatology_day_paths(output_root, day)
    data.frame(month_day = day, complete =
                 snodas_climatology_day_complete(paths, spec),
               path = paths[["median_swe"]], stringsAsFactors = FALSE)
  })
  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result
}

build_snodas_climatology_leap_day <- function(
    output_root, spec, overwrite = TRUE) {
  if (spec$month_day != "02-29") {
    stop("Leap-day interpolation requires 02-29.", call. = FALSE)
  }
  left <- snodas_climatology_day_paths(output_root, "02-28")
  right <- snodas_climatology_day_paths(output_root, "03-01")
  neighbor_spec <- spec
  neighbor_spec$leap_day_method <- "daily-observations"
  for (day in c("02-28", "03-01")) {
    neighbor_spec$month_day <- day
    neighbor_paths <- if (day == "02-28") left else right
    if (!snodas_climatology_day_complete(neighbor_paths, neighbor_spec)) {
      stop("Build both current February 28 and March 1 reference grids ",
           "before February 29.", call. = FALSE)
    }
  }
  outputs <- list()
  for (name in c("median_swe", "snow_frequency")) {
    a <- terra::rast(left[[name]])
    b <- terra::rast(right[[name]])
    if (!terra::compareGeom(a, b, stopOnError = FALSE)) {
      stop("Adjacent SNODAS reference grids have different geometry.",
           call. = FALSE)
    }
    outputs[[name]] <- (a + b) / 2
  }
  a_count <- terra::rast(left[["sample_years"]])
  b_count <- terra::rast(right[["sample_years"]])
  outputs$sample_years <- terra::app(c(a_count, b_count), fun = "min")
  paths <- snodas_climatology_day_paths(output_root, "02-29")
  dir.create(dirname(paths[["complete"]]), recursive = TRUE,
             showWarnings = FALSE)
  for (name in names(outputs)) {
    names(outputs[[name]]) <- paste0("snodas_", name, "_02-29")
    terra::time(outputs[[name]]) <- as.Date("2000-02-29")
    terra::writeRaster(outputs[[name]], paths[[name]], overwrite = overwrite,
                       datatype = "FLT4S", gdal = c("COMPRESS=DEFLATE"))
  }
  utils::write.csv(data.frame(
    water_year = NA_integer_, date = "2000-02-29",
    offset_days = NA_integer_, one_sided_missing_cells = NA_integer_,
    swe_exceeds_depth_cells = NA_integer_,
    invalid_range_cells = NA_integer_, excluded_cells = NA_integer_,
    availability = "interpolated", method = spec$leap_day_method,
    snow_threshold_inches = spec$snow_threshold_inches,
    min_valid_days = spec$min_valid_days, min_years = spec$min_years,
    source_days = "02-28,03-01"
  ), paths[["qc"]], row.names = FALSE)
  write_snodas_climatology_completion(paths, spec)
  invisible(paths)
}

run_snodas_daily_climatology <- function(
    month_days = snodas_climatology_month_days(),
    years = 2005:2025, snow_threshold_inches = 0.1,
    min_valid_days = 3L, min_years = 15L,
    processed_dir = swc_paths$processed, output_root = NULL,
    template = snodas_common_grid(),
    known_missing_dates = snodas_window_known_missing_dates(),
    max_days = 5L, dry_run = FALSE) {
  if (!is.numeric(max_days) || length(max_days) != 1L ||
      is.na(max_days) || max_days < 1L || max_days != floor(max_days) ||
      !is.logical(dry_run) || length(dry_run) != 1L || is.na(dry_run)) {
    stop("Choose a positive whole `max_days` (or Inf) and TRUE/FALSE ",
         "`dry_run`.", call. = FALSE)
  }
  if (is.null(output_root)) {
    output_root <- snodas_climatology_output_root(years, processed_dir)
  }
  before <- plan_snodas_daily_climatology(
    month_days, years, snow_threshold_inches, min_valid_days, min_years,
    processed_dir, output_root
  )
  pending <- before$month_day[!before$complete]
  scheduled <- head(pending, max_days)
  message(sprintf("SNODAS daily reference: %d total; %d complete; %d scheduled; %d deferred.",
                  nrow(before), sum(before$complete), length(scheduled),
                  length(pending) - length(scheduled)))
  if (dry_run) {
    message("Preview only: no SNODAS reference grids were built.")
    return(list(before = before, after = before,
                built = character(), scheduled = scheduled))
  }
  built <- character()
  for (index in seq_along(scheduled)) {
    day <- scheduled[index]
    message(sprintf("[%d/%d] Building SNODAS daily reference %s",
                    index, length(scheduled), day))
    spec <- snodas_climatology_spec(
      day, years, snow_threshold_inches, min_valid_days, min_years
    )
    paths <- snodas_climatology_day_paths(output_root, day)
    if (day == "02-29") {
      build_snodas_climatology_leap_day(output_root, spec)
    } else {
      build_snodas_window_baseline_day(
        day, years, snow_threshold_inches, min_valid_days, min_years,
        processed_dir, template, output_dir = dirname(paths[["complete"]]),
        overwrite = TRUE, known_missing_dates = known_missing_dates,
        progress_label = "daily reference"
      )
      write_snodas_climatology_completion(paths, spec)
    }
    if (!snodas_climatology_day_complete(paths, spec)) {
      stop("SNODAS daily reference did not validate after writing: ", day,
           call. = FALSE)
    }
    built <- c(built, day)
  }
  after <- plan_snodas_daily_climatology(
    month_days, years, snow_threshold_inches, min_valid_days, min_years,
    processed_dir, output_root
  )
  list(before = before, after = after, built = built,
       scheduled = scheduled)
}
