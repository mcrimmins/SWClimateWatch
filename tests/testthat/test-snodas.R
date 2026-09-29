source(file.path(project_root, "R", "snodas.R"))

make_test_snodas_tar <- function(directory, date = as.Date("2025-02-15")) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  stamp <- format(date, "%Y%m%d")
  stem <- paste0("us_ssmv11034tS__T0001TTNATS", stamp, "05HP001")
  header_file <- paste0(stem, ".txt.gz")
  data_file <- paste0(stem, ".dat.gz")
  header <- c(
    "Data units: Meters / 1000.000000",
    "Data bytes per pixel: 2",
    "Number of columns: 3", "Number of rows: 2",
    "Minimum x-axis coordinate: -112", "Maximum y-axis coordinate: 33",
    "X-axis resolution: 1", "Y-axis resolution: 1",
    "No data value: -9999",
    paste0("Start year: ", format(date, "%Y")),
    paste0("Start month: ", as.integer(format(date, "%m"))),
    paste0("Start day: ", as.integer(format(date, "%d"))),
    "Start hour: 6", "Start minute: 0"
  )
  header_connection <- gzfile(file.path(directory, header_file), "wt")
  writeLines(header, header_connection)
  close(header_connection)
  data_connection <- gzfile(file.path(directory, data_file), "wb")
  writeBin(as.integer(c(0, 25, 50, -9999, 100, 200)),
           data_connection, size = 2L, endian = "big")
  close(data_connection)
  archive <- file.path(directory, paste0("SNODAS_", stamp, ".tar"))
  old <- setwd(directory)
  on.exit(setwd(old), add = TRUE)
  utils::tar(archive, files = c(header_file, data_file),
             compression = "none", tar = "internal")
  archive
}

testthat::test_that("SNODAS URL and plans enforce a single-day request cap", {
  testthat::expect_equal(
    snodas_archive_url(as.Date("2025-02-15")),
    "https://noaadata.apps.nsidc.org/NOAA/G02158/masked/2025/02_Feb/SNODAS_20250215.tar"
  )
  plan <- plan_snodas_download(as.Date(c("2025-02-15", "2025-02-16")),
                               raw_dir = tempfile("snodas-plan-"))
  testthat::expect_equal(nrow(plan), 2L)
  testthat::expect_equal(preview_snodas_download(plan, 1L)$deferred, 1)
  testthat::expect_error(preview_snodas_download(plan, 6L), "configured SNODAS cap")
})

testthat::test_that("SNODAS download resumes and processing preserves the no-data mask", {
  date <- as.Date("2025-02-15")
  root <- tempfile("snodas-test-")
  source_dir <- file.path(root, "source")
  raw_dir <- file.path(root, "raw")
  processed_dir <- file.path(root, "processed")
  archive <- make_test_snodas_tar(source_dir, date)
  plan <- plan_snodas_download(date, raw_dir = raw_dir)
  fetched <- download_snodas_plan(
    plan, max_requests = 1L, delay_seconds = 0, jitter_seconds = 0,
    raw_dir = raw_dir,
    fetch = function(url, destination) {
      file.copy(archive, destination)
      0L
    }
  )
  testthat::expect_equal(nrow(fetched), 1L)
  testthat::expect_equal(nrow(read_snodas_manifest(
    snodas_manifest_path("raw", raw_dir))), 1L)
  testthat::expect_true(plan_snodas_download(date, raw_dir = raw_dir)$complete)

  output <- process_snodas_date(
    date, archive = snodas_archive_path(date, raw_dir),
    bbox = c(west = -112, south = 31, east = -109, north = 33),
    processed_dir = processed_dir
  )
  testthat::expect_true(output$refreshed)
  raster <- terra::rast(output$path)
  testthat::expect_equal(dim(raster)[1:2], c(2L, 3L))
  testthat::expect_equal(as.vector(terra::values(raster)),
                         c(0, 25, 50, NA, 100, 200) / 25.4,
                         tolerance = 1e-5)
  manifest <- read_snodas_manifest(snodas_manifest_path("processed", processed_dir))
  testthat::expect_equal(manifest$valid_utc, "2025-02-15 06:00 UTC")
  testthat::expect_equal(manifest$valid_fraction, 5 / 6)
  testthat::expect_false(process_snodas_date(
    date, archive = snodas_archive_path(date, raw_dir),
    bbox = c(west = -112, south = 31, east = -109, north = 33),
    processed_dir = processed_dir
  )$refreshed)
})

testthat::test_that("SNODAS processing repairs documented 2014-2019 false zeros", {
  date <- as.Date("2017-02-15")
  root <- tempfile("snodas-repair-")
  archive <- make_test_snodas_tar(file.path(root, "source"), date)
  mask <- terra::rast(nrows = 2, ncols = 3, xmin = -112, xmax = -109,
                      ymin = 31, ymax = 33, crs = "EPSG:4326")
  terra::values(mask) <- c(1, 0, 0, 0, 0, 0)
  mask_path <- file.path(root, "repair.tif")
  terra::writeRaster(mask, mask_path)
  testthat::expect_error(process_snodas_date(
    date, archive = archive,
    bbox = c(west = -112, south = 31, east = -109, north = 33),
    processed_dir = file.path(root, "processed"),
    repair_mask_path = file.path(root, "missing.tif")
  ), "zero-repair mask is required")
  output <- process_snodas_date(
    date, archive = archive,
    bbox = c(west = -112, south = 31, east = -109, north = 33),
    processed_dir = file.path(root, "processed"),
    repair_mask_path = mask_path
  )
  values <- as.vector(terra::values(terra::rast(output$path)))
  testthat::expect_true(is.na(values[1L]))
  manifest <- read_snodas_manifest(snodas_manifest_path(
    "processed", file.path(root, "processed")
  ))
  testthat::expect_equal(manifest$repaired_cells, 1)
  testthat::expect_equal(manifest$repaired_zero_cells, 1)
  testthat::expect_equal(manifest$valid_fraction, 4 / 6)
})
