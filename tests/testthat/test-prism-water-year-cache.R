make_water_year_cache_fixture <- function() {
  processed_dir <- tempfile("water-year-cache-")
  dates <- as.Date(c(
    "2018-10-01", "2018-10-02", "2018-10-03",
    "2019-10-01", "2019-10-02", "2019-10-03"
  ))
  values <- c(1, 2, 3, 10, 20, 30)
  paths <- file.path(
    processed_dir, "prism", "az-nm-pad050", "daily", "archive", "pcpn",
    paste0(format(dates), ".tif")
  )
  for (index in seq_along(paths)) {
    dir.create(dirname(paths[[index]]), recursive = TRUE, showWarnings = FALSE)
    raster <- terra::rast(
      ncols = 1, nrows = 1,
      xmin = -112, xmax = -111.9583333333,
      ymin = 33, ymax = 33.0416666667,
      crs = "EPSG:4326"
    )
    terra::values(raster) <- values[[index]]
    terra::time(raster) <- dates[[index]]
    names(raster) <- paste("pcpn", format(dates[[index]]), sep = "_")
    terra::writeRaster(
      raster, paths[[index]], overwrite = TRUE
    )
  }
  manifest <- data.frame(
    product = "daily",
    aoi_id = "az-nm-pad050",
    variable = "pcpn",
    native_units = "inch",
    start_date = dates,
    end_date = dates,
    processed_at = rep("2026-09-13 12:00:00 UTC", length(dates)),
    md5 = unname(tools::md5sum(paths)),
    path = paths,
    stringsAsFactors = FALSE
  )
  list(processed_dir = processed_dir, manifest = manifest)
}

testthat::test_that("water-year labels and starts cross October correctly", {
  dates <- as.Date(c("2026-09-30", "2026-10-01", "2027-01-15"))
  testthat::expect_equal(prism_water_year(dates), c(2026L, 2027L, 2027L))
  testthat::expect_equal(
    prism_water_year_start(dates),
    as.Date(c("2025-10-01", "2026-10-01", "2026-10-01"))
  )
})

testthat::test_that("reference periods interpret 1991-2020 as water-year labels", {
  periods <- prism_water_year_reference_periods(
    "2026-09-09", "1991-01-01", "2020-12-31"
  )
  testthat::expect_equal(nrow(periods), 30L)
  testthat::expect_equal(range(periods$water_year), c(1991L, 2020L))
  testthat::expect_equal(periods$start_date[[1L]], as.Date("1990-10-01"))
  testthat::expect_equal(periods$end_date[[1L]], as.Date("1991-09-09"))
  testthat::expect_equal(tail(periods$end_date, 1L), as.Date("2020-09-09"))
})

testthat::test_that("February 29 uses the documented 30-member interpolation", {
  periods <- prism_water_year_reference_periods(
    "2028-02-29", "2019-01-01", "2020-12-31"
  )
  testthat::expect_equal(periods$end_date, as.Date(c("2019-02-28", "2020-02-28")))
  testthat::expect_equal(
    periods$interpolation_end_date,
    as.Date(c("2019-03-01", "2020-03-01"))
  )
  testthat::expect_true(all(periods$leap_day_method == "interpolate-feb28-mar01"))
})

testthat::test_that("water-year cache resets, increments, and reuses safely", {
  fixture <- make_water_year_cache_fixture()
  cache_manifest <- file.path(fixture$processed_dir, "water-year-manifest.csv")
  october_first <- build_prism_water_year_cache(
    "2026-10-01", "2019-01-01", "2020-12-31",
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = cache_manifest,
    quiet = TRUE
  )
  october_second <- build_prism_water_year_cache(
    "2026-10-02", "2019-01-01", "2020-12-31",
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = cache_manifest,
    quiet = TRUE
  )
  october_third <- build_prism_water_year_cache(
    "2026-10-03", "2019-01-01", "2020-12-31",
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = cache_manifest,
    quiet = TRUE
  )
  direct_dir <- tempfile("direct-water-year-cache-")
  direct_third <- build_prism_water_year_cache(
    "2026-10-03", "2019-01-01", "2020-12-31",
    processed_dir = direct_dir,
    processed_manifest = fixture$manifest,
    manifest_path = file.path(direct_dir, "direct-water-year-manifest.csv"),
    overwrite = TRUE,
    allow_incremental = FALSE,
    quiet = TRUE
  )
  reused <- build_prism_water_year_cache(
    "2026-10-03", "2019-01-01", "2020-12-31",
    processed_dir = fixture$processed_dir,
    processed_manifest = fixture$manifest,
    manifest_path = cache_manifest,
    quiet = TRUE
  )

  testthat::expect_equal(as.numeric(terra::values(october_first$raster)), c(1, 10))
  testthat::expect_equal(as.numeric(terra::values(october_second$raster)), c(3, 30))
  testthat::expect_equal(as.numeric(terra::values(october_third$raster)), c(6, 60))
  testthat::expect_identical(
    as.numeric(terra::values(october_third$raster)),
    as.numeric(terra::values(direct_third$raster))
  )
  testthat::expect_equal(october_first$build_method, "direct")
  testthat::expect_equal(october_second$build_method, "incremental")
  testthat::expect_equal(october_third$build_method, "incremental")
  testthat::expect_false(reused$refreshed)
  testthat::expect_equal(reused$build_method, "reuse")
  testthat::expect_equal(unique(terra::datatype(reused$raster)), "FLT8S")

  manifest <- read_prism_manifest(cache_manifest)
  testthat::expect_equal(nrow(manifest), 3L)
  testthat::expect_true(all(manifest$sample_layers == 2L))
  first_row <- match("10-01", manifest$target_calendar_day)
  later_rows <- match(c("10-02", "10-03"), manifest$target_calendar_day)
  testthat::expect_equal(manifest$build_method[[first_row]], "direct")
  testthat::expect_true(all(manifest$build_method[later_rows] == "incremental"))
  testthat::expect_true(
    is.na(manifest$parent_path[[first_row]]) || !nzchar(manifest$parent_path[[first_row]])
  )
  testthat::expect_true(all(nzchar(manifest$parent_md5[later_rows])))
})
