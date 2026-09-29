source(file.path(project_root, "R", "snodas.R"))
source(file.path(project_root, "R", "audit-snodas.R"))
source(file.path(project_root, "R", "snodas-inventory.R"))
source(file.path(project_root, "R", "snodas-bootstrap.R"))
source(file.path(project_root, "R", "snodas-baseline.R"))
source(file.path(project_root, "R", "snodas-grid.R"))
source(file.path(project_root, "R", "snodas-analysis-qc.R"))
source(file.path(project_root, "R", "snodas-climatology-pilot.R"))

testthat::test_that("pilot dates follow water years and reject unsupported days", {
  dates <- snodas_pilot_calendar_dates("12-15", 2019:2020)
  testthat::expect_equal(dates$date,
                         as.Date(c("2018-12-15", "2019-12-15")))
  testthat::expect_equal(
    snodas_pilot_calendar_dates("02-15", 2019:2020)$date,
    as.Date(c("2019-02-15", "2020-02-15"))
  )
  testthat::expect_error(snodas_pilot_calendar_dates("02-29"), "leap day")
  testthat::expect_error(snodas_pilot_calendar_dates("07-15"),
                         "October-May")
})

testthat::test_that("pilot summaries use one screened sample per year", {
  template <- terra::rast(nrows = 2, ncols = 2, xmin = -111, xmax = -110,
                          ymin = 35, ymax = 36, crs = "EPSG:4326")
  first <- template
  second <- template
  third <- template
  terra::values(first) <- c(0, 0.2, NA, 1)
  terra::values(second) <- c(0, 0.5, NA, 1.2)
  terra::values(third) <- c(0.2, NA, NA, 1.4)
  product <- summarize_snodas_baseline_stack(
    c(first, second, third), snow_threshold_inches = 0.1,
    min_years = 2L
  )
  testthat::expect_equal(as.vector(terra::values(product$sample_years)),
                         c(3, 2, 0, 3))
  testthat::expect_equal(as.vector(terra::values(product$snow_frequency)),
                         c(1 / 3, 1, NA, 1), tolerance = 1e-6)
  testthat::expect_equal(as.vector(terra::values(product$median_swe)),
                         c(0, 0.35, NA, 1.2), tolerance = 1e-6)
})

testthat::test_that("pilot build writes regional outputs without changing sources", {
  root <- tempfile("snodas-climo-pilot-")
  processed_dir <- file.path(root, "processed")
  output_dir <- file.path(root, "pilot")
  template <- terra::rast(nrows = 2, ncols = 2, xmin = -111, xmax = -110,
                          ymin = 35, ymax = 36, crs = "EPSG:4326")
  dates <- as.Date(c("2019-02-15", "2020-02-15"))
  swe_values <- list(c(0, 0.2, NA, 1), c(0.2, 0.6, NA, 1.2))
  depth_values <- list(c(0, 0.4, NA, 1.5), c(0.3, 0, NA, 1.6))
  for (index in seq_along(dates)) {
    for (variable in c("swe", "depth")) {
      path <- snodas_processed_path(dates[index], variable, processed_dir)
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      grid <- template
      terra::values(grid) <- if (variable == "swe") {
        swe_values[[index]]
      } else depth_values[[index]]
      terra::time(grid) <- dates[index]
      terra::writeRaster(grid, path)
      write_snodas_manifest_row(data.frame(
        date = as.character(dates[index]), variable = variable,
        path = path, bytes = file.info(path)$size,
        md5 = unname(tools::md5sum(path)), source_md5 = "sample-source"
      ), snodas_manifest_path("processed", processed_dir),
      c("date", "variable"))
    }
  }
  source_path <- snodas_processed_path(dates[2L], "depth", processed_dir)
  source_md5 <- unname(tools::md5sum(source_path))
  plan <- plan_snodas_baseline_day("02-15", 2019:2020, processed_dir)
  testthat::expect_true(all(plan$ready))
  result <- build_snodas_baseline_day(
    "02-15", 2019:2020, min_years = 2L,
    processed_dir = processed_dir, template = template,
    output_dir = output_dir
  )
  testthat::expect_true(all(file.exists(result$paths)))
  testthat::expect_equal(result$qc$excluded_cells, c(0, 1))
  testthat::expect_identical(unname(tools::md5sum(source_path)), source_md5)
  sample_years <- terra::rast(result$paths[["sample_years"]])
  median_swe <- terra::rast(result$paths[["median_swe"]])
  frequency <- terra::rast(result$paths[["snow_frequency"]])
  testthat::expect_equal(as.vector(terra::values(sample_years)),
                         c(2, 1, 0, 2))
  testthat::expect_equal(as.vector(terra::values(median_swe)),
                         c(0.1, NA, NA, 1.1), tolerance = 1e-6)
  testthat::expect_equal(as.vector(terra::values(frequency)),
                         c(0.5, NA, NA, 1), tolerance = 1e-6)
  testthat::expect_equal(as.Date(terra::time(median_swe)),
                         as.Date("2000-02-15"))
  testthat::expect_error(build_snodas_baseline_day(
    "02-15", 2019:2020, min_years = 2L,
    processed_dir = processed_dir, template = template,
    output_dir = output_dir
  ), "already exists")
})
