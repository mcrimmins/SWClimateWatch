source(file.path(project_root, "R", "snodas-seasonal-anomaly.R"))

testthat::test_that("percent of median is guarded, uncapped and separates low snow from unavailable", {
  template <- terra::rast(nrows = 1, ncols = 8, xmin = -112, xmax = -111,
    ymin = 34, ymax = 35, crs = "EPSG:4326")
  make <- function(x) terra::setValues(template, x)
  peak <- make(c(0, 2, 50, 3, NA, 8, 1, 5))
  coverage <- make(c(1, 1, 1, 1, 1, 1, .94, 1))
  median <- make(c(1, 1, 2, 0, .5, .5, 2, NA))
  result <- snodas_peak_percent_median(peak, coverage, median)
  testthat::expect_equal(terra::values(result$percent_of_median, mat = FALSE),
    c(0, 200, 2500, NA, NA, NA, NA, NA))
  testthat::expect_equal(terra::values(result$display_status, mat = FALSE), c(1, 1, 1, 2, 3, 2, 3, 3))
  testthat::expect_error(snodas_peak_percent_median(peak, coverage, median, minimum_median_inches = 0), "positive")
  relaxed <- snodas_peak_percent_median(peak, coverage, median, minimum_median_inches = .5)
  testthat::expect_equal(terra::values(relaxed$percent_of_median, mat = FALSE)[6], 1600)
  testthat::expect_error(snodas_peak_percent_median(peak, coverage, terra::shift(median, dx = .1)), "aligned")
  testthat::expect_error(snodas_peak_percent_median(peak, coverage, make(rep(-1, 8))), "negative")
  classes <- snodas_peak_percent_classes(c(0, 50, 75, 90, 110, 125, 150, 200, 2500, NA, NA),
    c(rep(1, 9), 2, 3))
  testthat::expect_equal(as.character(classes), c("<50%", "50-75%", "75-90%", "90-110%",
    "110-125%", "125-150%", "150-200%", ">=200%", ">=200%", "Typical peak\n<1 inch", "Unavailable"))
})

testthat::test_that("seasonal peak reference weights years equally and preserves zero/NA", {
  template <- terra::rast(nrows = 1, ncols = 4, xmin = -112, xmax = -111,
    ymin = 34, ymax = 35, crs = "EPSG:4326")
  make <- function(x) terra::setValues(template, x)
  peaks <- lapply(list(c(0, 5, NA, 100), c(0, 9, NA, 7), c(4, 13, NA, 9)), make)
  coverage <- lapply(list(c(1, 1, 0, .94), c(1, .94, 0, 1), c(1, 1, 0, 1)), make)
  reference <- snodas_peak_anomaly_reference(peaks, coverage, min_years = 2L)
  testthat::expect_equal(terra::values(reference$median_peak_swe, mat = FALSE), c(0, 9, NA, 8))
  testthat::expect_equal(terra::values(reference$sample_years, mat = FALSE), c(3, 2, 0, 2))
  departure <- snodas_peak_anomaly_departure(peaks[[3]], coverage[[3]], reference$median_peak_swe)
  testthat::expect_equal(terra::values(departure, mat = FALSE), c(4, 4, NA, 1))
  strict <- snodas_peak_anomaly_reference(peaks, coverage, min_years = 3L)
  testthat::expect_equal(terra::values(strict$median_peak_swe, mat = FALSE), c(0, NA, NA, NA))
  # A target cannot recover a documented/missing peak cell or a low-coverage cell.
  target <- snodas_peak_anomaly_departure(make(c(NA, 20, 0, 30)), make(c(1, .94, 1, 1)),
    reference$median_peak_swe)
  testthat::expect_equal(terra::values(target, mat = FALSE), c(NA, NA, NA, 22))
  testthat::expect_error(snodas_peak_anomaly_reference(peaks, coverage, min_years = 4L), "minimum")
  testthat::expect_error(snodas_peak_anomaly_screen(make(c(-1, 0, 0, 0)), make(rep(1, 4))), "Invalid peak")
  testthat::expect_error(snodas_peak_anomaly_screen(peaks[[1]], make(rep(2, 4))), "coverage values")
  testthat::expect_error(snodas_peak_anomaly_screen(peaks[[1]], terra::shift(coverage[[1]], dx = .1)), "aligned")
})

snodas_anomaly_archive_fixture <- function(root, year, values) {
  directory <- file.path(root, paste0("wy", year)); dir.create(directory)
  grid <- terra::rast(nrows = 1, ncols = 2, xmin = -112, xmax = -111,
    ymin = 34, ymax = 35, crs = "EPSG:4326")
  paths <- file.path(directory, c("peak_swe.tif", "coverage.tif", "quality-summary.csv"))
  terra::writeRaster(terra::setValues(grid, values), paths[1L])
  terra::writeRaster(terra::setValues(grid, c(1, 1)), paths[2L])
  utils::write.csv(data.frame(water_year = year, source_signature = paste0("source-", year),
    status = "REVIEW", known_missing_days = 1L, reasons = "documented missing date"), paths[3L], row.names = FALSE)
  hashes <- unname(tools::md5sum(paths))
  utils::write.csv(data.frame(source_signature = paste0("source-", year),
    peak_swe_md5 = hashes[1L], coverage_md5 = hashes[2L], quality_md5 = hashes[3L]),
    file.path(directory, "complete.csv"), row.names = FALSE)
}

testthat::test_that("pilot uses verified archives without changing their files", {
  root <- tempfile(); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  for (year in 2005:2007) snodas_anomaly_archive_fixture(root, year, c(0, year - 2000))
  files <- list.files(root, recursive = TRUE, full.names = TRUE)
  before <- tools::md5sum(files)
  result <- build_snodas_seasonal_anomaly_pilot(target_years = 2005L,
    years = 2005:2007, min_years = 2L, archive_dir = root,
    output_dir = file.path(root, "pilot"), render_maps = FALSE)
  testthat::expect_identical(before, tools::md5sum(files))
  testthat::expect_equal(result$inventory$quality_status, rep("REVIEW", 3))
  testthat::expect_equal(result$summary$zero_median_cells, 1)
  testthat::expect_equal(terra::values(terra::rast(result$summary$path), mat = FALSE), c(0, -1))
  testthat::expect_equal(terra::values(terra::rast(result$summary$percent_path), mat = FALSE),
    c(NA, 100 * 5 / 6), tolerance = 1e-4)
  testthat::expect_equal(terra::values(terra::rast(result$summary$percent_status_path), mat = FALSE), c(2, 1))
  testthat::expect_equal(result$summary$percent_low_median_cells, 1)
  # Completion checksums prevent stale or edited seasonal rasters entering a baseline.
  changed <- file.path(root, "wy2005", "peak_swe.tif")
  writeBin(as.raw(1:4), changed)
  testthat::expect_error(snodas_peak_anomaly_inventory(2005:2007, root), "checksums changed")
  testthat::expect_error(snodas_peak_anomaly_inventory(c(2005, 2005), root), "unique")
})
