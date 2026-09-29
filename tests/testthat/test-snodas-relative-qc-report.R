source(file.path(project_root, "R", "snodas-relative-qc-report.R"))

testthat::test_that("review neighborhood retains row and column orientation", {
  template <- terra::rast(nrows = 7L, ncols = 7L, xmin = 0,
                          xmax = 7, ymin = 0, ymax = 7,
                          crs = "EPSG:4326")
  grid <- snodas_relative_review_neighborhood(template, 25L)
  testthat::expect_equal(grid$cell[grid$tile_row == 1L &
                                     grid$tile_col == 1L], 9L)
  testthat::expect_equal(grid$cell[grid$tile_row == 3L &
                                     grid$tile_col == 3L], 25L)
  testthat::expect_equal(grid$cell[grid$tile_row == 5L &
                                     grid$tile_col == 5L], 41L)
  edge <- snodas_relative_review_neighborhood(template, 1L)
  testthat::expect_true(anyNA(edge$cell))
  testthat::expect_equal(sum(!is.na(edge$cell)), 9L)
})

testthat::test_that("review history retains zero-snow neighbors and peak day", {
  template <- terra::rast(nrows = 5L, ncols = 5L, xmin = 0,
                          xmax = 5, ymin = 0, ymax = 5,
                          crs = "EPSG:4326")
  grid <- snodas_relative_review_neighborhood(template, 13L)
  peak <- as.Date("2016-03-01")
  reader <- function(date, points) {
    swe <- rep(0, nrow(points))
    depth <- rep(0, nrow(points))
    center <- which(points[, 1L] == 2.5 & points[, 2L] == 2.5)
    swe[center] <- if (date == peak) 20 else 10
    depth[center] <- swe[center] * 2
    list(swe = swe, depth = depth)
  }
  detail <- snodas_relative_review_history(peak, grid, reader)
  testthat::expect_equal(nrow(detail$history), 15L)
  testthat::expect_equal(detail$history$date[8L], "2016-03-01")
  testthat::expect_equal(detail$history$focal_swe_inches[8L], 20)
  testthat::expect_equal(
    detail$history$neighbor_median_swe_inches[8L], 0)
  testthat::expect_equal(detail$history$valid_neighbors[8L], 8L)
  testthat::expect_equal(
    detail$peak_grid$swe_inches[detail$peak_grid$tile_row == 3L &
                                 detail$peak_grid$tile_col == 3L], 20)
})

testthat::test_that("review report labels only a documented known mask", {
  sandbox <- tempfile("snodas-review-test-")
  archive_dir <- file.path(sandbox, "archive")
  output_dir <- file.path(sandbox, "report")
  dir.create(file.path(archive_dir, "wy2016"), recursive = TRUE)
  template <- terra::rast(nrows = 5L, ncols = 5L, xmin = 0,
                          xmax = 5, ymin = 0, ymax = 5,
                          crs = "EPSG:4326")
  terra::writeRaster(terra::setValues(template, rep(1, 25)),
                     file.path(archive_dir, "wy2016", "peak_swe.tif"))
  peaks <- data.frame(
    water_year = c(2016L, 2016L), cell = c(12L, 13L),
    longitude = c(1.5, 2.5), latitude = c(2.5, 2.5),
    peak_date = c("2016-03-01", "2016-03-01"),
    peak_swe_inches = c(12, 20),
    pilot_priority = c("REVIEW_EVENT", "REVIEW_EVENT"),
    strong_spatial_isolation = c(FALSE, TRUE),
    density_contrast = c(FALSE, FALSE),
    weak_temporal_support = c(TRUE, FALSE),
    map_daily_mismatch = c(FALSE, FALSE))
  episodes <- data.frame(
    water_year = 2016L, start_date = "2016-03-01",
    end_date = "2016-03-01", pilot_priority = "REVIEW_EPISODE")
  benchmarks <- data.frame(water_year = 2016L, cell = 13L,
                           rule_id = "known-source-mask",
                           source_matched = TRUE)
  report <- build_snodas_relative_review_report(
    list(peaks = peaks, episodes = episodes, benchmarks = benchmarks),
    output_dir = output_dir, archive_dir = archive_dir,
    read_pair = function(date, points) {
      swe <- ifelse(points[, 1L] == 2.5 & points[, 2L] == 2.5,
                    20, 0)
      list(swe = swe, depth = swe * 2)
    })
  testthat::expect_true(all(file.exists(report$paths)))
  testthat::expect_equal(nrow(report$cells), 2L)
  testthat::expect_equal(nrow(report$history), 30L)
  testthat::expect_equal(sum(!is.na(report$cells$known_rule_id)), 1L)
  html <- paste(readLines(report$paths[["index"]], warn = FALSE),
                collapse = "")
  testthat::expect_match(html, "known-source-mask", fixed = TRUE)
  testthat::expect_match(html, "Unclassified review flag", fixed = TRUE)
  testthat::expect_match(html, "Peak-day SWE", fixed = TRUE)
})
