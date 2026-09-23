make_current_map_test_raster <- function(values, dates) {
  raster <- terra::rast(
    ncols = 1, nrows = 1, nlyrs = length(dates),
    xmin = -112, xmax = -111.9583333333,
    ymin = 33, ymax = 33.0416666667,
    crs = "EPSG:4326"
  )
  terra::values(raster) <- values
  terra::time(raster) <- as.Date(dates)
  raster
}

testthat::test_that("latest common date uses recent single-day products", {
  manifest <- data.frame(
    product = "daily",
    aoi_id = "az-nm-pad050",
    variable = c("maxt", "mint", "maxt", "mint", "pcpn"),
    start_date = as.Date(c("2026-09-08", "2026-09-08", "2026-09-09", "2026-09-09", "2026-09-10")),
    end_date = as.Date(c("2026-09-08", "2026-09-08", "2026-09-09", "2026-09-09", "2026-09-10")),
    path = file.path(
      "data", "processed", "prism", "az-nm-pad050", "daily", "recent",
      c("maxt", "mint", "maxt", "mint", "pcpn"),
      paste0(c("2026-09-08", "2026-09-08", "2026-09-09", "2026-09-09", "2026-09-10"), ".tif")
    ),
    stringsAsFactors = FALSE
  )

  testthat::expect_equal(
    latest_common_prism_date(processed_manifest = manifest),
    as.Date("2026-09-09")
  )
  testthat::expect_equal(
    latest_common_prism_date("pcpn", processed_manifest = manifest),
    as.Date("2026-09-10")
  )
})

testthat::test_that("operational percentile map paths are stable", {
  testthat::expect_match(
    prism_percentile_map_path("maxt", "2026-09-09"),
    "maxt-percentile-rank-2026-09-09.png",
    fixed = TRUE
  )
  testthat::expect_match(
    prism_percentile_map_path("mint"),
    "mint-percentile-rank-latest.png",
    fixed = TRUE
  )
  testthat::expect_match(
    prism_percentile_map_path("tmean"),
    "tmean-percentile-rank-latest.png",
    fixed = TRUE
  )
  testthat::expect_match(
    prism_temperature_map_path("tmean", "value"),
    "tmean-value-latest.png",
    fixed = TRUE
  )
  testthat::expect_match(
    prism_temperature_map_path("tmean", "departure", "2026-09-09"),
    "tmean-departure-2026-09-09.png",
    fixed = TRUE
  )
  testthat::expect_match(
    prism_temperature_rolling_departure_map_path("tmean", 30L),
    "tmean-departure-30day-latest.png",
    fixed = TRUE
  )
  testthat::expect_match(
    prism_temperature_rolling_departure_map_path("maxt", 30L),
    "maxt-departure-30day-latest.png",
    fixed = TRUE
  )
  testthat::expect_match(
    prism_temperature_rolling_departure_map_path("mint", 30L),
    "mint-departure-30day-latest.png",
    fixed = TRUE
  )
  testthat::expect_match(
    prism_temperature_rolling_departure_output_path("tmean", 30L, "2026-09-09"),
    file.path("rolling-departure", "tmean", "030day", "2026-09-09.tif"),
    fixed = TRUE
  )
  testthat::expect_match(
    prism_temperature_extreme_frequency_map_path("maxt", "p90", 30L),
    "maxt-above-p90-count-30day-latest.png",
    fixed = TRUE
  )
  testthat::expect_match(
    prism_temperature_extreme_frequency_output_path("maxt", "p90", 30L, "2026-09-09"),
    file.path("extreme-frequency", "maxt", "above-p90", "030day", "2026-09-09.tif"),
    fixed = TRUE
  )
  testthat::expect_match(
    prism_temperature_extreme_frequency_map_path(
      "mint", "p10", 30L, comparison = "below"
    ),
    "mint-below-p10-count-30day-latest.png",
    fixed = TRUE
  )
  testthat::expect_match(
    prism_temperature_extreme_frequency_output_path(
      "mint", "p10", 30L, "2026-09-09", comparison = "below"
    ),
    file.path("extreme-frequency", "mint", "below-p10", "030day", "2026-09-09.tif"),
    fixed = TRUE
  )
  testthat::expect_match(
    prism_freeze_day_count_map_path(30L),
    "mint-freeze-day-count-30day-latest.png",
    fixed = TRUE
  )
  testthat::expect_match(
    prism_freeze_day_count_output_path(30L, "2026-09-09"),
    file.path("threshold-count", "mint", "at-or-below-32F", "030day", "2026-09-09.tif"),
    fixed = TRUE
  )
  testthat::expect_match(
    prism_freeze_day_anomaly_map_path(30L),
    "mint-freeze-day-anomaly-30day-latest.png",
    fixed = TRUE
  )
  testthat::expect_match(
    prism_freeze_day_anomaly_output_path(30L, "2026-09-09"),
    file.path("freeze-count-anomaly", "mint", "030day", "2026-09-09.tif"),
    fixed = TRUE
  )
  testthat::expect_equal(format_prism_map_date("2026-09-09"), "September 9, 2026")
  testthat::expect_equal(
    prism_map_footer_text(),
    paste(
      "Data source: PRISM Climate Group via RCC-ACIS",
      "Reference period: 1991-2020",
      sep = "\n"
    )
  )
})

testthat::test_that("mean temperature is derived from paired maximum and minimum layers", {
  dates <- as.Date(c("2026-09-08", "2026-09-09"))
  maxt <- make_current_map_test_raster(c(90, 94), dates)
  mint <- make_current_map_test_raster(c(60, 64), dates)
  result <- prism_mean_temperature_raster(maxt, mint)

  testthat::expect_equal(as.numeric(terra::values(result)), c(75, 79))
  testthat::expect_equal(as.Date(terra::time(result)), dates)
  testthat::expect_equal(names(result), c("tmean_2026-09-08", "tmean_2026-09-09"))
})

testthat::test_that("mean-temperature normals derive from maximum and minimum normals", {
  processed_dir <- tempfile("temperature-normal-")
  date <- as.Date("2026-09-09")
  reference_date <- as.Date("2000-09-09")
  for (variable in c("maxt", "mint")) {
    value <- if (variable == "maxt") 90 else 60
    raster <- make_current_map_test_raster(value, reference_date)
    names(raster) <- paste(variable, "mean", "09-09", sep = "_")
    path <- prism_climatology_path(
      variable, "mean", swc_prism$normal_start, swc_prism$normal_end,
      aoi_id = swc_prism$aoi_id, processed_dir = processed_dir
    )
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(raster, path, overwrite = TRUE)
  }

  normal <- prism_temperature_normal_layer(
    "tmean", date, processed_dir = processed_dir
  )
  testthat::expect_equal(as.numeric(terra::values(normal)), 75)
  testthat::expect_equal(as.Date(terra::time(normal)), reference_date)
})

testthat::test_that("temperature normals select several calendar days in request order", {
  processed_dir <- tempfile("temperature-normal-range-")
  reference_dates <- as.Date(c("2000-01-01", "2000-12-31"))
  requested_dates <- as.Date(c("2025-12-31", "2026-01-01"))
  for (variable in c("maxt", "mint")) {
    offset <- if (variable == "maxt") 30 else 10
    raster <- make_current_map_test_raster(offset + c(1, 2), reference_dates)
    names(raster) <- paste(variable, "mean", format(reference_dates, "%m-%d"), sep = "_")
    path <- prism_climatology_path(
      variable, "mean", swc_prism$normal_start, swc_prism$normal_end,
      aoi_id = swc_prism$aoi_id, processed_dir = processed_dir
    )
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(raster, path, overwrite = TRUE)
  }

  normal <- prism_temperature_normal_raster(
    "tmean", requested_dates, processed_dir = processed_dir
  )
  testthat::expect_equal(as.numeric(terra::values(normal)), c(22, 21))
  testthat::expect_equal(
    as.Date(terra::time(normal)),
    as.Date(c("2000-12-31", "2000-01-01"))
  )
})

testthat::test_that("rolling temperature departure averages matching observed and normal days", {
  dates <- as.Date(c("2026-09-07", "2026-09-08", "2026-09-09"))
  observed <- make_current_map_test_raster(c(70, 76, 82), dates)
  normal <- make_current_map_test_raster(
    c(68, 70, 72),
    as.Date(c("2000-09-07", "2000-09-08", "2000-09-09"))
  )
  result <- prism_rolling_temperature_departure_raster(
    observed, normal, "tmean", 3L, "2026-09-09"
  )

  testthat::expect_equal(as.numeric(terra::values(result)), 6)
  testthat::expect_equal(as.Date(terra::time(result)), as.Date("2026-09-09"))
  testthat::expect_equal(names(result), "tmean_departure_003day_2026-09-09")
})

testthat::test_that("temperature threshold rasters select matching calendar days", {
  processed_dir <- tempfile("temperature-threshold-")
  reference_dates <- as.Date(c("2000-08-31", "2000-09-01"))
  raster <- make_current_map_test_raster(c(91, 92), reference_dates)
  names(raster) <- paste("maxt", "p90", format(reference_dates, "%m-%d"), sep = "_")
  path <- prism_climatology_path(
    "maxt", "p90", swc_prism$normal_start, swc_prism$normal_end,
    aoi_id = swc_prism$aoi_id, processed_dir = processed_dir
  )
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  terra::writeRaster(raster, path, overwrite = TRUE)

  threshold <- prism_temperature_threshold_raster(
    "maxt", "p90", as.Date(c("2026-09-01", "2026-08-31")),
    processed_dir = processed_dir
  )
  testthat::expect_equal(as.numeric(terra::values(threshold)), c(92, 91))
  testthat::expect_equal(
    as.Date(terra::time(threshold)),
    as.Date(c("2000-09-01", "2000-08-31"))
  )
})

testthat::test_that("extreme warm-day frequency counts strict p90 exceedances", {
  dates <- as.Date(c("2026-09-07", "2026-09-08", "2026-09-09"))
  observed <- make_current_map_test_raster(c(90, 91, 95), dates)
  threshold <- make_current_map_test_raster(
    c(90, 90, 96),
    as.Date(c("2000-09-07", "2000-09-08", "2000-09-09"))
  )
  result <- prism_temperature_exceedance_count_raster(
    observed, threshold, "maxt", "p90", 3L, "2026-09-09"
  )

  testthat::expect_equal(as.numeric(terra::values(result)), 1)
  testthat::expect_equal(as.Date(terra::time(result)), as.Date("2026-09-09"))
  testthat::expect_equal(names(result), "maxt_above_p90_count_003day_2026-09-09")
})

testthat::test_that("extreme cold-night frequency counts strict p10 undershoots", {
  dates <- as.Date(c("2026-09-07", "2026-09-08", "2026-09-09"))
  observed <- make_current_map_test_raster(c(50, 49, 45), dates)
  threshold <- make_current_map_test_raster(
    c(50, 50, 44),
    as.Date(c("2000-09-07", "2000-09-08", "2000-09-09"))
  )
  result <- prism_temperature_exceedance_count_raster(
    observed, threshold, "mint", "p10", 3L, "2026-09-09", "below"
  )

  testthat::expect_equal(as.numeric(terra::values(result)), 1)
  testthat::expect_equal(as.Date(terra::time(result)), as.Date("2026-09-09"))
  testthat::expect_equal(names(result), "mint_below_p10_count_003day_2026-09-09")
})

testthat::test_that("freeze-day frequency includes minimum temperatures equal to 32 F", {
  dates <- as.Date(c("2026-09-07", "2026-09-08", "2026-09-09"))
  observed <- make_current_map_test_raster(c(33, 32, 31), dates)
  result <- prism_freeze_day_count_raster(
    observed, 3L, "2026-09-09", threshold_f = 32
  )

  testthat::expect_equal(as.numeric(terra::values(result)), 2)
  testthat::expect_equal(as.Date(terra::time(result)), as.Date("2026-09-09"))
  testthat::expect_equal(names(result), "mint_at_or_below_32F_count_003day_2026-09-09")
})

testthat::test_that("freeze-day anomaly subtracts the matching reference mean", {
  current <- make_current_map_test_raster(1, as.Date("2026-09-09"))
  reference_dates <- as.Date(c("2019-09-09", "2020-09-09"))
  reference <- make_current_map_test_raster(c(2, 4), reference_dates)
  result <- prism_freeze_day_anomaly_raster(
    current,
    reference,
    list(reference_dates),
    30L,
    "2026-09-09"
  )

  testthat::expect_equal(as.numeric(terra::values(result)), -2)
  testthat::expect_equal(as.Date(terra::time(result)), as.Date("2026-09-09"))
  testthat::expect_equal(names(result), "mint_freeze_count_anomaly_030day_2026-09-09")
})

testthat::test_that("temperature value and departure maps use fixed Fahrenheit scales", {
  raster <- terra::rast(
    ncols = 2, nrows = 2, xmin = -115, xmax = -103,
    ymin = 31, ymax = 37, crs = "EPSG:4326"
  )
  terra::values(raster) <- c(55, 65, 75, 85)
  terra::time(raster) <- as.Date("2026-09-09")

  value_plot <- build_prism_temperature_value_map(raster, "tmean")
  departure_plot <- build_prism_temperature_departure_map(raster - 70, "tmean")
  rolling_plot <- build_prism_rolling_temperature_departure_map(
    raster - 70, "tmean", 30L, "2026-09-09"
  )
  rolling_maxt_plot <- build_prism_rolling_temperature_departure_map(
    raster - 70, "maxt", 30L, "2026-09-09"
  )
  rolling_mint_plot <- build_prism_rolling_temperature_departure_map(
    raster - 70, "mint", 30L, "2026-09-09"
  )
  frequency_plot <- build_prism_extreme_warm_day_frequency_map(
    raster / 10, 30L, "2026-09-09"
  )
  cold_frequency_plot <- build_prism_extreme_cold_night_frequency_map(
    raster / 10, 30L, "2026-09-09"
  )
  freeze_plot <- build_prism_freeze_day_count_map(
    raster / 10, 30L, "2026-09-09"
  )
  zero_freeze_plot <- build_prism_freeze_day_count_map(
    raster * 0, 30L, "2026-09-09"
  )
  freeze_anomaly_plot <- build_prism_freeze_day_anomaly_map(
    raster / 10 - 7, 30L, "2026-09-09"
  )
  testthat::expect_equal(value_plot$scales$scales[[1L]]$limits, c(-30, 110))
  testthat::expect_equal(departure_plot$scales$scales[[1L]]$limits, c(-30, 30))
  testthat::expect_equal(rolling_plot$scales$scales[[1L]]$limits, c(-15, 15))
  testthat::expect_equal(rolling_plot$labels$title, "30-day mean temperature departure")
  testthat::expect_equal(rolling_maxt_plot$labels$title, "30-day maximum temperature departure")
  testthat::expect_equal(rolling_mint_plot$labels$title, "30-day minimum temperature departure")
  testthat::expect_equal(frequency_plot$scales$scales[[1L]]$limits, c(0, 30))
  testthat::expect_equal(frequency_plot$labels$title, "Extreme warm days in the past 30 days")
  testthat::expect_equal(cold_frequency_plot$scales$scales[[1L]]$limits, c(0, 30))
  testthat::expect_equal(cold_frequency_plot$labels$title, "Extreme cold nights in the past 30 days")
  testthat::expect_equal(freeze_plot$scales$scales[[1L]]$limits, c(0, 30))
  testthat::expect_equal(freeze_plot$labels$title, "Nights at or below freezing in the past 30 days")
  testthat::expect_gt(length(zero_freeze_plot$layers), length(freeze_plot$layers))
  testthat::expect_equal(freeze_anomaly_plot$scales$scales[[1L]]$limits, c(-10, 10))
  testthat::expect_equal(freeze_anomaly_plot$labels$title, "30-day freeze-night anomaly")
})

testthat::test_that("percentile rank map uses a fixed 0 to 100 scale", {
  raster <- terra::rast(
    ncols = 2, nrows = 2,
    xmin = -115, xmax = -103,
    ymin = 31, ymax = 37,
    crs = "EPSG:4326"
  )
  terra::values(raster) <- c(10, 40, 70, 95)
  terra::time(raster) <- as.Date("2026-09-09")
  plot <- build_prism_percentile_rank_map(
    raster,
    "maxt",
    "2026-09-09"
  )

  testthat::expect_s3_class(plot, "ggplot")
  testthat::expect_equal(plot$scales$scales[[1L]]$limits, c(0, 100))
  testthat::expect_null(plot$labels$x)
  testthat::expect_null(plot$labels$y)
})

testthat::test_that("Southwest raster maps retain the complete raster footprint", {
  raster <- terra::rast(
    ncols = 2, nrows = 2,
    xmin = -116, xmax = -102,
    ymin = 30, ymax = 38,
    crs = "EPSG:4326"
  )
  terra::values(raster) <- 1:4
  small_state <- sf::st_as_sf(
    maps::map("state", regions = "arizona", fill = TRUE, plot = FALSE)
  )
  if (is.na(sf::st_crs(small_state))) {
    sf::st_crs(small_state) <- 4326
  }

  plot <- southwest_raster_map(
    raster = raster,
    states = small_state,
    title = "Footprint test"
  )

  raster_layer <- ggplot2::layer_data(plot, 1L)
  testthat::expect_equal(nrow(raster_layer), 4L)
  testthat::expect_equal(range(raster_layer$x), c(-112.5, -105.5))
  testthat::expect_equal(range(raster_layer$y), c(32, 36))
})

testthat::test_that("map reference layers are available locally", {
  testthat::expect_s3_class(southwest_state_boundaries(), "sf")
  testthat::expect_s3_class(southwest_county_boundaries(), "sf")
  testthat::expect_s3_class(southwest_country_boundaries(), "sf")
  cities <- southwest_reference_cities()
  testthat::expect_true(all(c("Phoenix", "Albuquerque") %in% cities$city))
  testthat::expect_true(all(cities$priority <= 2L))
})

testthat::test_that("the institutional map logo is stored with site assets", {
  testthat::expect_equal(
    southwest_brand_logo_path(),
    file.path(
      "site", "assets", "branding",
      "ua-csap-climas-logos-horizontal.png"
    )
  )
  testthat::expect_true(
    file.exists(file.path(project_root, southwest_brand_logo_path()))
  )
})
