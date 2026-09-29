source(file.path(project_root, "R", "snodas.R"))
source(file.path(project_root, "R", "audit-snodas.R"))
source(file.path(project_root, "R", "snodas-inventory.R"))
source(file.path(project_root, "R", "snodas-bootstrap.R"))
source(file.path(project_root, "R", "snodas-baseline.R"))
source(file.path(project_root, "R", "snodas-grid.R"))
source(file.path(project_root, "R", "snodas-analysis-qc.R"))
source(file.path(project_root, "R", "snodas-climatology-pilot.R"))
source(file.path(project_root, "R", "snodas-climatology-window-pilot.R"))
source(file.path(project_root, "R", "snodas-daily-climatology.R"))
source(file.path(project_root, "R", "snodas-map-quality.R"))
source(file.path(project_root, "R", "snodas-map-pilot.R"))
source(file.path(project_root, "R", "snodas-high-swe-audit.R"))

testthat::test_that("SWE departure requires matching grid and observation date", {
  template <- terra::rast(nrows = 1, ncols = 2, xmin = -111, xmax = -110,
                          ymin = 35, ymax = 36, crs = "EPSG:4326")
  observed <- template
  median <- template
  terra::values(observed) <- c(0, 2)
  terra::values(median) <- c(1, 0.5)
  terra::time(observed) <- as.Date("2025-02-15")
  out <- snodas_swe_departure_raster(observed, median,
                                     as.Date("2025-02-15"))
  testthat::expect_equal(as.vector(terra::values(out)), c(-1, 1.5))
  testthat::expect_equal(as.Date(terra::time(out)), as.Date("2025-02-15"))
  testthat::expect_error(snodas_swe_departure_raster(
    observed, median, as.Date("2025-02-16")), "date")
  shifted <- terra::rast(nrows = 1, ncols = 2, xmin = -110.9,
                         xmax = -109.9, ymin = 35, ymax = 36,
                         crs = "EPSG:4326")
  terra::values(shifted) <- c(1, 0.5)
  testthat::expect_error(snodas_swe_departure_raster(
    observed, shifted, as.Date("2025-02-15")), "same grid")
})

testthat::test_that("map pilot screens observed SWE before departure", {
  root <- tempfile("snodas-map-pilot-")
  processed_dir <- file.path(root, "processed")
  climatology_root <- file.path(root, "reference")
  date <- as.Date("2025-02-15")
  template <- terra::rast(nrows = 1, ncols = 3, xmin = -111, xmax = -110,
                          ymin = 35, ymax = 36, crs = "EPSG:4326")
  for (variable in c("swe", "depth")) {
    path <- snodas_processed_path(date, variable, processed_dir)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    grid <- template
    terra::values(grid) <- if (variable == "swe") {
      c(0, 1, 2)
    } else c(0.2, 1.5, 1)
    terra::time(grid) <- date
    terra::writeRaster(grid, path)
    write_snodas_manifest_row(data.frame(
      date = as.character(date), variable = variable, path = path,
      bytes = file.info(path)$size, md5 = unname(tools::md5sum(path)),
      source_md5 = "sample-source"
    ), snodas_manifest_path("processed", processed_dir),
    c("date", "variable"))
  }
  swe_path <- snodas_processed_path(date, "swe", processed_dir)
  source_md5 <- unname(tools::md5sum(swe_path))
  paths <- snodas_climatology_day_paths(climatology_root, "02-15")
  dir.create(dirname(paths[["complete"]]), recursive = TRUE)
  reference_values <- list(median_swe = c(0, 0.5, 1),
                           snow_frequency = c(0.1, 0.5, 0.7),
                           sample_years = c(21, 21, 21))
  for (name in names(reference_values)) {
    grid <- template
    terra::values(grid) <- reference_values[[name]]
    terra::time(grid) <- as.Date("2000-02-15")
    terra::writeRaster(grid, paths[[name]])
  }
  utils::write.csv(data.frame(date = "2000-02-15"), paths[["qc"]],
                   row.names = FALSE)
  spec <- snodas_climatology_spec("02-15", 2005:2025, 0.1, 3L, 15L)
  write_snodas_climatology_completion(paths, spec)
  result <- load_snodas_swe_map_pilot_inputs(
    date, processed_dir = processed_dir,
    climatology_root = climatology_root, template = template
  )
  testthat::expect_equal(result$qc$excluded_cells, 1)
  testthat::expect_equal(as.vector(terra::values(result$observed)),
                         c(0, 1, NA), tolerance = 1e-6)
  testthat::expect_equal(as.vector(terra::values(result$departure)),
                         c(0, 0.5, NA), tolerance = 1e-6)
  testthat::expect_identical(unname(tools::md5sum(swe_path)), source_md5)
})

testthat::test_that("SNODAS categorical classes retain upper tails", {
  observed <- map_product_categorical_classes(
    "snodas_swe_observed", NULL, c(0, 90)
  )
  departure <- map_product_categorical_classes(
    "snodas_swe_departure", NULL, c(-90, 90)
  )
  testthat::expect_equal(observed$breaks,
                         c(0, 0.1, 1, 2, 4, 8, 12, 20, 30, 90))
  testthat::expect_equal(tail(observed$labels, 1L), ">30")
  testthat::expect_equal(departure$breaks,
                         c(-90, -16, -8, -4, -1, 1, 4, 8, 16, 90))
  testthat::expect_equal(tail(departure$labels, 1L), ">16")
})

testthat::test_that("high-SWE audit distinguishes spatial extent and persistence", {
  anchor <- terra::rast(nrows = 1, ncols = 4, xmin = -111, xmax = -110,
                        ymin = 35, ymax = 36, crs = "EPSG:4326")
  terra::values(anchor) <- c(0, 12, 22, 35)
  days <- list(c(0, 12, 22, 35), c(0, 11, 22, 35),
               c(0, 12, 0, 35))
  result <- snodas_high_swe_window_metrics(
    anchor, days, thresholds = c(12, 20, 30)
  )
  testthat::expect_equal(result$high_cells, c(3L, 2L, 1L))
  testthat::expect_equal(result$persistent_cells, c(1L, 1L, 1L))
  testthat::expect_equal(result$patch_count, c(1L, 1L, 1L))
  testthat::expect_equal(result$largest_patch_percent, c(100, 100, 100))
  testthat::expect_true(all(result$high_area_km2 > 0))
  testthat::expect_error(snodas_high_swe_window_metrics(
    anchor, list(1:2)), "match")
})

testthat::test_that("categorical SWE display is the pilot default", {
  testthat::expect_identical(
    eval(formals(build_snodas_swe_map_pilot)$scale_type),
    c("categorical", "continuous")
  )
  testthat::expect_identical(
    eval(formals(snodas_swe_map_pilot_plot)$scale_type),
    c("categorical", "continuous")
  )
})

testthat::test_that("high-SWE review flags values without modifying them", {
  template <- terra::rast(nrows = 1, ncols = 3, xmin = -111,
                          xmax = -110, ymin = 35, ymax = 36,
                          crs = "EPSG:4326")
  observed <- template
  reference <- template
  terra::values(observed) <- c(0, 35, 55)
  terra::values(reference) <- c(0, 25, 60)
  before <- terra::values(observed, mat = FALSE)
  qc <- data.frame(excluded_cells = 2L)
  review <- snodas_swe_map_review_summary(
    observed, reference, as.Date("2025-02-15"), qc
  )
  testthat::expect_equal(review$screened_excluded_cells, 2L)
  testthat::expect_equal(review$observed_cells_over_30_inches, 2L)
  testthat::expect_equal(review$observed_cells_for_review, 1L)
  testthat::expect_equal(review$reference_cells_for_review, 1L)
  testthat::expect_true(review$high_swe_review_flag)
  testthat::expect_equal(terra::values(observed, mat = FALSE), before)
  testthat::expect_error(snodas_swe_map_review_summary(
    observed, reference, as.Date("2025-02-15"), qc, 25
  ), "threshold")
})

testthat::test_that("publication gate separates failures from manual review", {
  grid <- terra::rast(nrows = 1, ncols = 4, xmin = -111, xmax = -110,
                      ymin = 35, ymax = 36, crs = "EPSG:4326")
  observed <- reference <- samples <- grid
  terra::values(observed) <- c(0, 1, 2, 3)
  terra::values(reference) <- c(0, 1, 2, 3)
  terra::values(samples) <- rep(21, 4)
  inputs <- list(date = as.Date("2025-02-15"), observed = observed,
                 median_swe = reference, sample_years = samples,
                 qc = data.frame(excluded_cells = 0L))
  review <- data.frame(screened_excluded_cells = 0L,
                       high_swe_review_flag = FALSE)
  gate <- assess_snodas_swe_map_quality(inputs, review)
  testthat::expect_equal(gate$status, "PASS")
  testthat::expect_true(require_snodas_swe_map_publishable(gate))
  review$high_swe_review_flag <- TRUE
  gate <- assess_snodas_swe_map_quality(inputs, review)
  testthat::expect_equal(gate$status, "REVIEW")
  testthat::expect_error(require_snodas_swe_map_publishable(gate),
                         "blocked")
  review$high_swe_review_flag <- FALSE
  terra::values(reference) <- rep(NA_real_, 4)
  inputs$median_swe <- reference
  gate <- assess_snodas_swe_map_quality(inputs, review)
  testthat::expect_equal(gate$status, "FAIL")
})
