source(file.path(project_root, "R/interactive-map-site.R"))

testthat::test_that("compressed site payloads preserve masks and reject invalid bytes or values", {
  folder <- tempfile("snow-site-"); dir.create(folder)
  on.exit(unlink(folder, recursive = TRUE), add = TRUE)
  values <- list(observed = c(0,2,2,2,NA,0,4,1), median = c(2,0,.5,1,2,0,2,NA),
    departure = c(-2,2,1.5,1,NA,0,2,NA), percent = c(0,NA,NA,NA,NA,NA,200,NA),
    change = rep(NA_real_, 8), years = c(21,21,21,17,21,21,18,NA),
    percent_status = c(1,2,2,3,3,2,1,3), departure_status = c(1,2,2,1,3,2,1,3))
  entry <- list(file = "snow-fixture.bin.gz", compression = "gzip", bytes = 8*43,
    grid = list(rows = 2, cols = 4, west = -112, east = -110, north = 34, south = 33, dx = .5, dy = .5),
    date = "2025-02-15", change_start_date = "2025-02-08", change_available = FALSE, fields = list())
  offset <- 0L
  for (j in seq_along(values)) {
    entry$fields[[names(values)[j]]] <- list(type = if (j <= 5) "float64" else "uint8", offset = offset)
    offset <- offset + 8 * if (j <= 5) 8 else 1
  }
  write_fixture <- function(values, truncate = FALSE) {
    raw <- rawConnection(raw(), "wb")
    for (j in seq_along(values)) {
      v <- values[[j]]
      if (j <= 5) writeBin(as.double(v), raw, size = 8L, endian = "little") else {
        v[is.na(v)] <- 255; writeBin(as.raw(v), raw)
      }
    }
    bytes <- rawConnectionValue(raw); close(raw)
    if (truncate) bytes <- head(bytes, -1)
    con <- gzfile(file.path(folder, entry$file), "wb"); writeBin(bytes, con); close(con)
    result <- entry
    result$md5 <- unname(tools::md5sum(file.path(folder, entry$file)))
    result$transfer_bytes <- file.info(file.path(folder, entry$file))$size
    result
  }
  good <- write_fixture(values)
  testthat::expect_true(validate_interactive_snow_payload(good, folder))
  bad <- good; bad$change_start_date <- "2025-02-09"
  testthat::expect_error(validate_interactive_snow_payload(bad, folder), "Unverified")
  bad <- good; bad$fields$percent$offset <- 0
  testthat::expect_error(validate_interactive_snow_payload(bad, folder), "Unverified")
  bad <- good; bad$grid$east <- -109
  testthat::expect_error(validate_interactive_snow_payload(bad, folder), "Unverified")
  bad <- write_fixture(values, truncate = TRUE)
  testthat::expect_error(validate_interactive_snow_payload(bad, folder), "Unverified")
  wrong <- values; wrong$percent[1] <- 100
  bad <- write_fixture(wrong)
  testthat::expect_error(validate_interactive_snow_payload(bad, folder), "Unverified")
  wrong <- values; wrong$percent_status[4] <- 1; wrong$percent[4] <- 200
  bad <- write_fixture(wrong)
  testthat::expect_error(validate_interactive_snow_payload(bad, folder), "Unverified")
  wrong <- values; wrong$change[1] <- 0
  bad <- write_fixture(wrong)
  testthat::expect_error(validate_interactive_snow_payload(bad, folder), "Unverified")
  bad <- good; bad$file <- "../snow-fixture.bin.gz"
  testthat::expect_error(validate_interactive_snow_payload(bad, folder), "Unverified")
})
