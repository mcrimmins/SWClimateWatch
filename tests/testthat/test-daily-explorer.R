source(file.path(project_root, "R", "daily-explorer.R"))

testthat::test_that("mean temperature uses paired cells and matching geometry", {
  maximum <- terra::rast(nrows = 1, ncols = 3, xmin = 0, xmax = 3, ymin = 0, ymax = 1)
  terra::values(maximum) <- c(80, NA, 90)
  minimum <- maximum
  terra::values(minimum) <- c(40, 50, NA)
  result <- daily_explorer_mean_temperature(maximum, minimum)
  testthat::expect_equal(terra::values(result, mat = FALSE), c(60, NA, NA))
  shifted <- terra::shift(minimum, dx = 1)
  testthat::expect_error(daily_explorer_mean_temperature(maximum, shifted))
})

testthat::test_that("plain city labels are optional and public boxed labels remain the default", {
  raster <- terra::rast(nrows = 2, ncols = 2, xmin = -115, xmax = -109,
    ymin = 31, ymax = 37, crs = "EPSG:4326")
  terra::values(raster) <- 1
  cities <- data.frame(city = c("Phoenix", "Tucson"),
    longitude = c(-112.074, -110.9747), latitude = c(33.4484, 32.2226))
  arguments <- list(raster = raster, states = southwest_state_boundaries("arizona"),
    title = "Label test", cities = cities, tribal_areas = NULL, rivers = NULL,
    interstates = NULL, scale_type = "continuous")
  boxed <- do.call(southwest_raster_map, arguments)
  plain <- do.call(southwest_raster_map, c(arguments, list(city_label_style = "text")))
  geoms <- function(plot) vapply(plot$layers, function(layer) class(layer$geom)[[1L]], character(1))
  testthat::expect_true(all(c("GeomLabelRepel", "GeomLabel") %in% geoms(boxed)))
  testthat::expect_true(all(c("GeomTextRepel", "GeomText") %in% geoms(plain)))
  testthat::expect_false(any(grepl("Label", geoms(plain))))
})

testthat::test_that("water years follow the October boundary including leap days", {
  testthat::expect_equal(daily_explorer_water_year(c("2026-09-30", "2026-10-01", "2024-02-29")),
    c(2026L, 2027L, 2024L))
})

testthat::test_that("summaries use cell area and suppress incomplete values", {
  rain <- daily_explorer_summary(c(0, 1, NA), c(1, 3, 0), "pcpn")
  testthat::expect_equal(rain$mean, 0.75)
  testthat::expect_equal(rain$rain010, 75)
  testthat::expect_equal(rain$rain100, 75)
  testthat::expect_equal(rain$spatial_p99, 1)
  testthat::expect_equal(rain$coverage, 1)
  missing <- daily_explorer_summary(c(0, NA), c(1, 3), "pcpn")
  testthat::expect_equal(missing$coverage, 0.25)
  testthat::expect_true(is.na(missing$mean))
  testthat::expect_true(is.na(missing$rain010))
  dry <- daily_explorer_summary(c(0, 0), c(1, 3), "pcpn")
  testthat::expect_equal(dry$mean, 0)
  testthat::expect_equal(dry$rain010, 0)
})

testthat::test_that("reference gaps are not zero anomalies and freezing includes 32F", {
  temperature <- daily_explorer_summary(c(32, 40), c(1, 3), "mint",
    normal = c(30, 30), p10 = c(33, 35), p90 = c(35, 39))
  testthat::expect_equal(temperature$departure, 8)
  testthat::expect_equal(temperature$freeze, 25)
  testthat::expect_equal(temperature$warm, 75)
  testthat::expect_equal(temperature$cold, 25)
  incomplete <- daily_explorer_summary(c(32, 40), c(1, 3), "mint",
    normal = c(NA, 30), p90 = c(NA, 39))
  testthat::expect_true(is.na(incomplete$departure))
  testthat::expect_true(is.na(incomplete$warm))
  testthat::expect_equal(incomplete$mean, 38)
  testthat::expect_equal(incomplete$freeze, 25)
})

testthat::test_that("spatial quantiles exclude missing and outside-region cells", {
  testthat::expect_equal(daily_explorer_weighted_quantile(c(1, 2, 999, NA), c(99, 1, 0, 8)), 1)
  testthat::expect_true(is.na(daily_explorer_weighted_quantile(c(NA, 1), c(1, 0))))
  # Float32 values at a rainfall threshold retain their intended classification.
  rounded <- daily_explorer_summary(c(0.99999998, 0), c(1, 1), "pcpn")
  testthat::expect_equal(rounded$rain100, 50)
})

testthat::test_that("exact coverage threshold is accepted without filling missing cells", {
  summary <- daily_explorer_summary(c(1, NA), c(19, 1), "pcpn")
  testthat::expect_equal(summary$coverage, 0.95)
  testthat::expect_equal(summary$mean, 1)
  testthat::expect_equal(summary$rain100, 100)
})

testthat::test_that("source indexing preserves date gaps and rejects overlapping inputs", {
  raster <- terra::rast(nrows = 2, ncols = 2, nlyrs = 2,
    xmin = -112, xmax = -111, ymin = 33, ymax = 34, crs = "EPSG:4326")
  terra::values(raster) <- 1
  terra::time(raster) <- as.Date(c("2026-10-01", "2026-10-03"))
  path <- tempfile(fileext = ".tif")
  second_path <- tempfile(fileext = ".tif")
  on.exit(unlink(c(path, second_path)), add = TRUE)
  terra::writeRaster(raster, path)
  manifest <- data.frame(product = "daily", aoi_id = swc_prism$aoi_id,
    variable = "pcpn", start_date = as.Date("2026-10-01"),
    end_date = as.Date("2026-10-03"), path = path)
  index <- daily_explorer_index(as.Date("2026-10-01"), as.Date("2026-10-03"), manifest)
  testthat::expect_equal(index$date, c("2026-10-01", "2026-10-03"))
  testthat::expect_equal(index$layer, 1:2)
  file.copy(path, second_path)
  manifest <- rbind(manifest, transform(manifest, path = second_path))
  testthat::expect_error(daily_explorer_index(as.Date("2026-10-01"),
    as.Date("2026-10-03"), manifest), "overlapping")
})

testthat::test_that("daily references select leap day and preserve missing references", {
  raster <- terra::rast(nrows = 2, ncols = 2, nlyrs = 2,
    xmin = -112, xmax = -111, ymin = 33, ymax = 34, crs = "EPSG:4326")
  terra::values(raster) <- cbind(rep(1, 4), rep(2, 4))
  terra::time(raster) <- as.Date(c("2000-02-28", "2000-02-29"))
  path <- tempfile(fileext = ".tif")
  on.exit(unlink(path), add = TRUE)
  terra::writeRaster(raster, path)
  reference <- daily_explorer_reference(path, "2024-02-29", raster[[1L]])
  testthat::expect_equal(as.numeric(terra::values(reference)), rep(2, 4))
  testthat::expect_null(daily_explorer_reference(path, "2026-03-01", raster[[1L]]))
  testthat::expect_null(daily_explorer_reference(paste0(path, "-absent"), "2026-03-01", raster[[1L]]))
})

testthat::test_that("recent daily revisions take priority over overlapping catchup grids", {
  root <- tempfile(); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  raster <- terra::rast(nrows = 1, ncols = 1, nlyrs = 2,
    xmin = -112, xmax = -111, ymin = 33, ymax = 34)
  terra::values(raster) <- matrix(c(1, 2), nrow = 1)
  terra::time(raster) <- as.Date(c("2026-08-01", "2026-08-02"))
  monthly <- file.path(root, "catchup.tif")
  daily <- file.path(root, "daily", "recent", "pcpn", "2026-08-01.tif")
  dir.create(dirname(daily), recursive = TRUE)
  terra::writeRaster(raster, monthly)
  terra::writeRaster(raster[[1L]], daily)
  manifest <- data.frame(product = "daily", aoi_id = swc_prism$aoi_id,
    variable = "pcpn", start_date = as.Date(c("2026-08-01", "2026-08-01")),
    end_date = as.Date(c("2026-08-02", "2026-08-01")), path = c(monthly, daily))
  index <- daily_explorer_index(as.Date("2026-08-01"), as.Date("2026-08-02"), manifest)
  testthat::expect_identical(index$path[index$date == "2026-08-01"], daily)
  testthat::expect_identical(index$path[index$date == "2026-08-02"], monthly)
})
