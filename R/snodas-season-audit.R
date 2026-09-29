# Offline, resumable quality audit of a complete SNODAS cool season.
# Source config.R, snodas.R, audit-snodas.R, snodas-inventory.R,
# snodas-bootstrap.R, and snodas-quality-pilot.R first.

snodas_audit_processed_pair <- function(
    date, processed_dir = swc_paths$processed,
    repair_mask_path = file.path(swc_paths$raw, "snodas", "reference",
                                 "SNODAS_Zero_Repair_Mask.tif")) {
  date <- snodas_date(date)
  paths <- vapply(swc_snodas$variables, function(variable) {
    snodas_processed_path(date, variable, processed_dir)
  }, character(1))
  names(paths) <- swc_snodas$variables
  if (any(!file.exists(paths))) {
    stop("Missing processed SNODAS pair for ", date, call. = FALSE)
  }
  grids <- lapply(paths, terra::rast)
  for (grid in grids) {
    if (terra::nlyr(grid) != 1L ||
        length(terra::time(grid)) != 1L ||
        is.na(terra::time(grid)) ||
        as.Date(terra::time(grid)) != date) {
      stop("SNODAS raster has unexpected layers or date for ", date,
           call. = FALSE)
    }
  }
  result <- snodas_pair_quality(grids[["swe"]], grids[["depth"]], date,
                                repair_mask_path)
  footprint <- terra::ext(grids[["swe"]])
  result$source_rows <- terra::nrow(grids[["swe"]])
  result$source_cols <- terra::ncol(grids[["swe"]])
  result$source_xmin <- unname(footprint$xmin)
  result$source_ymax <- unname(footprint$ymax)
  result$res_x <- terra::res(grids[["swe"]])[1L]
  result$res_y <- terra::res(grids[["swe"]])[2L]
  result$swe_md5 <- unname(tools::md5sum(paths[["swe"]]))
  result$depth_md5 <- unname(tools::md5sum(paths[["depth"]]))
  result
}

read_snodas_season_audit <- function(path) {
  if (!file.exists(path)) return(data.frame())
  rows <- utils::read.csv(path, stringsAsFactors = FALSE)
  required <- c("date", "variable", "swe_md5", "depth_md5")
  if (!all(required %in% names(rows)) ||
      anyNA(rows[, required, drop = FALSE]) ||
      anyDuplicated(paste(rows$date, rows$variable)) ||
      any(!rows$variable %in% swc_snodas$variables)) {
    stop("Invalid SNODAS season-audit cache: ", path, call. = FALSE)
  }
  rows
}

snodas_geometry_variant_count <- function(report,
                                          tolerance_degrees = 1e-9) {
  columns <- c("source_rows", "source_cols", "source_xmin",
               "source_ymax", "res_x", "res_y")
  if (!all(columns %in% names(report))) {
    stop("SNODAS audit report lacks geometry columns.", call. = FALSE)
  }
  if (!nrow(report)) return(0L)
  geometry <- unique(report[, columns, drop = FALSE])
  if (anyNA(geometry) || any(!is.finite(as.matrix(geometry)))) {
    stop("SNODAS audit report has invalid geometry.", call. = FALSE)
  }
  representatives <- integer()
  for (index in seq_len(nrow(geometry))) {
    same <- vapply(representatives, function(other) {
      geometry$source_rows[index] == geometry$source_rows[other] &&
        geometry$source_cols[index] == geometry$source_cols[other] &&
        all(abs(as.numeric(geometry[index, c("source_xmin", "source_ymax",
                                              "res_x", "res_y")]) -
                as.numeric(geometry[other, c("source_xmin", "source_ymax",
                                              "res_x", "res_y")])) <=
              tolerance_degrees)
    }, logical(1))
    if (!any(same)) representatives <- c(representatives, index)
  }
  length(representatives)
}

audit_snodas_cool_season <- function(
    water_year = 2024L,
    inventory_path = file.path("data", "diagnostics", "snodas-audit",
                               "monthly-directory-inventory.csv"),
    raw_dir = swc_paths$raw,
    processed_dir = swc_paths$processed,
    report_path = file.path("data", "diagnostics", "snodas-audit",
                            sprintf("wy%d-grid-quality.csv", water_year)),
    max_dates = 244L) {
  if (length(max_dates) != 1L || !is.numeric(max_dates) ||
      is.na(max_dates) || max_dates < 0L || max_dates != floor(max_dates)) {
    stop("`max_dates` must be a nonnegative whole number.", call. = FALSE)
  }
  plan <- plan_snodas_cool_season(water_year, inventory_path, raw_dir)
  complete <- snodas_cool_season_processed(plan, processed_dir)$complete
  if (any(!complete)) {
    stop("SNODAS cool season still has ", sum(!complete),
         " unprocessed listed dates.", call. = FALSE)
  }
  report <- read_snodas_season_audit(report_path)
  if (nrow(report) && any(!report$date %in% as.character(plan$date))) {
    stop("SNODAS audit cache contains dates outside water year ", water_year,
         call. = FALSE)
  }
  pending <- vapply(plan$date, function(date) {
    rows <- report[report$date == as.character(date), , drop = FALSE]
    if (nrow(rows) != length(swc_snodas$variables) ||
        !setequal(rows$variable, swc_snodas$variables)) return(TRUE)
    paths <- vapply(swc_snodas$variables, function(variable) {
      snodas_processed_path(date, variable, processed_dir)
    }, character(1))
    checksums <- stats::setNames(unname(tools::md5sum(paths)),
                                 swc_snodas$variables)
    stale <- rows$swe_md5 != checksums[["swe"]] |
      rows$depth_md5 != checksums[["depth"]]
    any(is.na(stale) | stale)
  }, logical(1))
  selected <- head(plan$date[pending], max_dates)
  for (index in seq_along(selected)) {
    date <- selected[index]
    quality <- snodas_audit_processed_pair(
      date, processed_dir,
      file.path(raw_dir, "snodas", "reference",
                "SNODAS_Zero_Repair_Mask.tif")
    )
    report <- report[report$date != as.character(date), , drop = FALSE]
    report <- rbind(report, quality)
    report <- report[order(report$date, report$variable), , drop = FALSE]
    dir.create(dirname(report_path), recursive = TRUE, showWarnings = FALSE)
    temporary <- tempfile("snodas-audit-", tmpdir = dirname(report_path),
                          fileext = ".csv")
    utils::write.csv(report, temporary, row.names = FALSE)
    if (!file.copy(temporary, report_path, overwrite = TRUE)) {
      unlink(temporary)
      stop("Could not checkpoint SNODAS season audit: ", report_path,
           call. = FALSE)
    }
    unlink(temporary)
    if (index %% 25L == 0L || index == length(selected)) {
      message(sprintf("SNODAS season quality: %d/%d new dates checked.",
                      index, length(selected)))
    }
  }
  checked <- as.character(plan$date[!pending | plan$date %in% selected])
  report_current <- report[report$date %in% checked, , drop = FALSE]
  swe <- report_current[report_current$variable == "swe", , drop = FALSE]
  flags <- report_current[report_current$negative_cells > 0 |
                            report_current$saturated_cells > 0 |
                            report_current$swe_exceeds_depth_cells > 0 |
                            (!is.na(report_current$repair_zero_cells) &
                               report_current$repair_zero_cells > 0), , drop = FALSE]
  geometry_variants <- snodas_geometry_variant_count(report_current)
  list(
    report = report,
    summary = data.frame(
      water_year = water_year, listed_dates = nrow(plan),
      audited_dates = sum(as.character(plan$date) %in% checked),
      pending_dates = sum(!as.character(plan$date) %in% checked),
      flagged_dates = length(unique(flags$date)),
      geometry_variants = geometry_variants,
      min_valid_fraction = if (nrow(report_current)) {
        min(report_current$valid_fraction)
      } else NA_real_,
      max_swe_inches = if (nrow(swe)) max(swe$max_inches, na.rm = TRUE) else NA_real_,
      max_depth_inches = if (nrow(report_current)) max(
        report_current$max_inches[report_current$variable == "depth"],
        na.rm = TRUE
      ) else NA_real_
    ),
    flags = flags
  )
}
