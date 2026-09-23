make_rank_test_raster <- function(values, dates) {
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

testthat::test_that("type 8 percentile ranks use median-unbiased plotting positions", {
  baseline <- 1:5

  testthat::expect_equal(prism_type8_percentile_rank(3, baseline), 50)
  testthat::expect_equal(prism_type8_percentile_rank(0, baseline), 0)
  testthat::expect_equal(prism_type8_percentile_rank(6, baseline), 100)
  testthat::expect_true(is.na(prism_type8_percentile_rank(NA_real_, baseline)))
  testthat::expect_true(is.na(prism_type8_percentile_rank(3, NA_real_)))
})

testthat::test_that("reference windows are centered, circular, and exclude leap day", {
  january <- prism_reference_window_dates(
    "2026-01-01", "2019-01-01", "2020-12-31", window_days = 5L
  )[[1L]]
  keys <- unique(format(january, "%m-%d"))

  testthat::expect_setequal(keys, c("12-30", "12-31", "01-01", "01-02", "01-03"))
  testthat::expect_false(any(format(january, "%m-%d") == "02-29"))

  leap <- prism_reference_window_dates(
    "2024-02-29", "2019-01-01", "2020-12-31", window_days = 1L
  )
  testthat::expect_length(leap, 2L)
  testthat::expect_setequal(unique(format(leap[[1L]], "%m-%d")), "02-28")
  testthat::expect_setequal(unique(format(leap[[2L]], "%m-%d")), "03-01")
})

testthat::test_that("percentile-rank rasters retain geometry and current date", {
  baseline <- make_rank_test_raster(
    c(10, 20, 30),
    c("2018-07-01", "2019-07-01", "2020-07-01")
  )
  current <- make_rank_test_raster(20, "2026-07-01")

  result <- prism_percentile_rank_raster(current, baseline, "maxt", "2026-07-01")

  testthat::expect_equal(as.numeric(terra::values(result)), 50)
  testthat::expect_equal(names(result), "maxt_percentile_rank_2026-07-01")
  testthat::expect_equal(as.Date(terra::time(result)), as.Date("2026-07-01"))
  testthat::expect_error(
    prism_percentile_rank_raster(current, baseline, "pcpn", "2026-07-01"),
    "accumulation-based"
  )
})

testthat::test_that("daily subsets read only requested processed dates", {
  processed_dir <- tempfile("rank-subset-")
  dir.create(processed_dir, recursive = TRUE)
  dates <- as.Date(c("2018-07-01", "2019-07-01", "2020-07-01"))
  paths <- file.path(processed_dir, paste0(format(dates), ".tif"))
  for (index in seq_along(paths)) {
    terra::writeRaster(
      make_rank_test_raster(index * 10, dates[[index]]),
      paths[[index]],
      overwrite = TRUE
    )
  }
  manifest <- data.frame(
    product = "daily",
    aoi_id = "az-nm-pad050",
    variable = "maxt",
    native_units = "degreeF",
    start_date = dates,
    end_date = dates,
    md5 = unname(tools::md5sum(paths)),
    path = paths,
    stringsAsFactors = FALSE
  )

  subset <- read_prism_daily_subset(
    "maxt",
    dates[c(1, 3)],
    processed_manifest = manifest
  )

  testthat::expect_equal(subset$dates, dates[c(1, 3)])
  testthat::expect_equal(as.numeric(terra::values(subset$raster)), c(10, 30))
})

testthat::test_that("high-level percentile ranks use the requested baseline window", {
  processed_dir <- tempfile("rank-calculate-")
  dir.create(processed_dir, recursive = TRUE)
  dates <- as.Date(c("2018-07-01", "2019-07-01", "2020-07-01"))
  paths <- file.path(processed_dir, paste0(format(dates), ".tif"))
  for (index in seq_along(paths)) {
    terra::writeRaster(
      make_rank_test_raster(index * 10, dates[[index]]),
      paths[[index]],
      overwrite = TRUE
    )
  }
  manifest <- data.frame(
    product = "daily",
    aoi_id = "az-nm-pad050",
    variable = "maxt",
    native_units = "degreeF",
    start_date = dates,
    end_date = dates,
    md5 = unname(tools::md5sum(paths)),
    path = paths,
    stringsAsFactors = FALSE
  )
  current <- make_rank_test_raster(20, "2026-07-01")

  result <- calculate_prism_percentile_rank(
    current,
    "maxt",
    current_date = "2026-07-01",
    baseline_start = "2018-07-01",
    baseline_end = "2020-07-01",
    window_days = 1L,
    processed_manifest = manifest,
    quiet = TRUE
  )

  testthat::expect_equal(as.numeric(terra::values(result)), 50)
})

testthat::test_that("mean-temperature percentile ranks use paired historical samples", {
  processed_dir <- tempfile("tmean-rank-")
  dir.create(processed_dir, recursive = TRUE)
  dates <- as.Date(c("2018-07-01", "2019-07-01", "2020-07-01"))
  records <- list()
  record_index <- 0L
  for (variable in c("maxt", "mint")) {
    values <- if (variable == "maxt") c(20, 30, 40) else c(10, 20, 30)
    for (index in seq_along(dates)) {
      path <- file.path(processed_dir, variable, paste0(format(dates[[index]]), ".tif"))
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      terra::writeRaster(
        make_rank_test_raster(values[[index]], dates[[index]]),
        path,
        overwrite = TRUE
      )
      record_index <- record_index + 1L
      records[[record_index]] <- data.frame(
        product = "daily", aoi_id = "az-nm-pad050", variable = variable,
        native_units = "degreeF", start_date = dates[[index]], end_date = dates[[index]],
        md5 = unname(tools::md5sum(path)), path = path, stringsAsFactors = FALSE
      )
    }
  }
  manifest <- do.call(rbind, records)
  current <- make_rank_test_raster(25, "2026-07-01")

  result <- calculate_prism_percentile_rank(
    current, "tmean", current_date = "2026-07-01",
    baseline_start = "2018-07-01", baseline_end = "2020-07-01",
    window_days = 1L, processed_manifest = manifest, quiet = TRUE
  )

  testthat::expect_equal(as.numeric(terra::values(result)), 50)
  testthat::expect_equal(names(result), "tmean_percentile_rank_2026-07-01")
})
