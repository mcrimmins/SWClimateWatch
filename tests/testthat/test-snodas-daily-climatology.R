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

testthat::test_that("October-May calendar validates and builds leap day last", {
  days <- snodas_climatology_month_days()
  testthat::expect_length(days, 244L)
  testthat::expect_equal(days[c(1L, length(days))], c("10-01", "05-31"))
  testthat::expect_true("02-29" %in% days)
  testthat::expect_equal(
    validate_snodas_climatology_days(c("02-29", "03-01", "02-28")),
    c("02-28", "03-01", "02-29")
  )
  testthat::expect_error(validate_snodas_climatology_days("09-30"),
                         "October-May")
  testthat::expect_error(snodas_climatology_spec(
    "10-01", 2019:2020, 0.1, 4L, 2L), "Invalid")
})

testthat::test_that("three-day season edge needs all three valid days", {
  template <- terra::rast(nrows = 1, ncols = 2, xmin = -111, xmax = -110,
                          ymin = 35, ymax = 36, crs = "EPSG:4326")
  layers <- lapply(list(c(0.2, 0), c(0.4, NA), c(0.6, 0)),
                   function(values) {
                     grid <- template
                     terra::values(grid) <- values
                     grid
                   })
  year <- summarize_snodas_window_year(do.call(c, layers),
                                        min_valid_days = 3L)
  testthat::expect_equal(as.vector(terra::values(year$median_swe)),
                         c(0.4, NA), tolerance = 1e-6)
  testthat::expect_equal(as.vector(terra::values(year$snow_fraction)),
                         c(1, NA), tolerance = 1e-6)
})

testthat::test_that("daily reference builds and resumes an October edge", {
  root <- tempfile("snodas-daily-reference-")
  processed_dir <- file.path(root, "processed")
  output_root <- file.path(root, "reference")
  template <- terra::rast(nrows = 1, ncols = 2, xmin = -111, xmax = -110,
                          ymin = 35, ymax = 36, crs = "EPSG:4326")
  dates <- c(seq(as.Date("2018-10-01"), as.Date("2018-10-03"), by = "day"),
             seq(as.Date("2019-10-01"), as.Date("2019-10-03"), by = "day"))
  for (index in seq_along(dates)) {
    for (variable in c("swe", "depth")) {
      path <- snodas_processed_path(dates[index], variable, processed_dir)
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      grid <- template
      swe <- c(if (index <= 3L) c(0, 0.2, 0.4)[index] else
                 c(0.2, 0.4, 0.6)[index - 3L], 0)
      terra::values(grid) <- if (variable == "swe") swe else swe + 0.3
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
  preview <- run_snodas_daily_climatology(
    "10-01", 2019:2020, min_years = 2L,
    processed_dir = processed_dir, output_root = output_root,
    template = template, known_missing_dates = as.Date(character()),
    max_days = 1L, dry_run = TRUE
  )
  testthat::expect_false(preview$before$complete)
  testthat::expect_false(dir.exists(output_root))
  first <- run_snodas_daily_climatology(
    "10-01", 2019:2020, min_years = 2L,
    processed_dir = processed_dir, output_root = output_root,
    template = template, known_missing_dates = as.Date(character()),
    max_days = 1L
  )
  testthat::expect_equal(first$built, "10-01")
  testthat::expect_true(first$after$complete)
  paths <- snodas_climatology_day_paths(output_root, "10-01")
  testthat::expect_true(all(file.exists(paths)))
  testthat::expect_equal(
    as.vector(terra::values(terra::rast(paths[["median_swe"]]))),
    c(0.3, 0), tolerance = 1e-6
  )
  testthat::expect_equal(
    as.vector(terra::values(terra::rast(paths[["snow_frequency"]]))),
    c(5 / 6, 0), tolerance = 1e-6
  )
  again <- run_snodas_daily_climatology(
    "10-01", 2019:2020, min_years = 2L,
    processed_dir = processed_dir, output_root = output_root,
    template = template, known_missing_dates = as.Date(character()),
    max_days = Inf
  )
  testthat::expect_length(again$built, 0L)
  changed_spec <- snodas_climatology_spec("10-01", 2019:2020,
                                          0.2, 3L, 2L)
  testthat::expect_false(snodas_climatology_day_complete(paths,
                                                          changed_spec))
})

testthat::test_that("leap day interpolates validated neighboring references", {
  root <- tempfile("snodas-leap-reference-")
  dir.create(root)
  template <- terra::rast(nrows = 1, ncols = 2, xmin = -111, xmax = -110,
                          ymin = 35, ymax = 36, crs = "EPSG:4326")
  values_by_day <- list(
    `02-28` = list(median_swe = c(0, 2),
                   snow_frequency = c(0, 0.5), sample_years = c(21, 20)),
    `03-01` = list(median_swe = c(2, 4),
                   snow_frequency = c(1, 0.75), sample_years = c(20, 21))
  )
  for (day in names(values_by_day)) {
    paths <- snodas_climatology_day_paths(root, day)
    dir.create(dirname(paths[["complete"]]), recursive = TRUE)
    for (name in names(values_by_day[[day]])) {
      grid <- template
      terra::values(grid) <- values_by_day[[day]][[name]]
      terra::time(grid) <- as.Date(paste0("2000-", day))
      terra::writeRaster(grid, paths[[name]])
    }
    utils::write.csv(data.frame(date = day), paths[["qc"]], row.names = FALSE)
    spec <- snodas_climatology_spec(day, 2005:2025, 0.1, 3L, 15L)
    write_snodas_climatology_completion(paths, spec)
  }
  leap_spec <- snodas_climatology_spec("02-29", 2005:2025, 0.1, 3L, 15L)
  result <- run_snodas_daily_climatology(
    "02-29", 2005:2025, output_root = root, template = template,
    known_missing_dates = as.Date(character()), max_days = 1L
  )
  testthat::expect_equal(result$built, "02-29")
  paths <- snodas_climatology_day_paths(root, "02-29")
  testthat::expect_true(snodas_climatology_day_complete(paths, leap_spec))
  testthat::expect_equal(
    as.vector(terra::values(terra::rast(paths[["median_swe"]]))), c(1, 3))
  testthat::expect_equal(
    as.vector(terra::values(terra::rast(paths[["snow_frequency"]]))),
    c(0.5, 0.625), tolerance = 1e-6)
  testthat::expect_equal(
    as.vector(terra::values(terra::rast(paths[["sample_years"]]))),
    c(20, 20))
  testthat::expect_equal(
    as.Date(terra::time(terra::rast(paths[["median_swe"]]))),
    as.Date("2000-02-29"))
})
