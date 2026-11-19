for (module in c("prism-monthly", "prism-monthly-audit", "prism-monthly-temperature",
    "prism-monthly-precipitation", "prism-monthly-ranking-pilots", "prism-monthly-spi"))
  source(file.path(project_root, "R", paste0(module, ".R")))
source(file.path(project_root, "R/historic-monthly-pilot.R"))

testthat::test_that("historic windows use complete cross-year seasons and actual leap-day weights", {
  w <- historic_monthly_windows(c(2000L, 2002L, 2020L))
  testthat::expect_equal(w$start[1:4], c("1999-10", "1999-10", "2000-04", "2000-07"))
  testthat::expect_equal(w$end[1:4], c("2000-09", "2000-03", "2000-06", "2000-09"))
  testthat::expect_equal(w$duration[1:4], c(12L, 6L, 3L, 3L))
  months <- unlist(lapply(2:4, function(i) format(prism_monthly_window(w$end[i], w$duration[i]), "%Y-%m")))
  testthat::expect_identical(months, format(prism_monthly_window("2000-09", 12), "%Y-%m"))
  testthat::expect_false(anyDuplicated(months) > 0L)
  testthat::expect_equal(historic_monthly_products_per_year(), 21L)
  testthat::expect_equal(sum(prism_monthly_day_weights(prism_monthly_window("2000-09", 12))), 366)
  testthat::expect_equal(sum(prism_monthly_day_weights(prism_monthly_window("2001-09", 12))), 365)
  testthat::expect_error(historic_monthly_windows(c(2000, 2000)), "unique")
  testthat::expect_error(historic_monthly_windows(1895), "WY1896")
  testthat::expect_error(historic_monthly_windows(2000.5), "unique")
})

testthat::test_that("retrospective ranks include later years and fixed normals retain support guards", {
  years <- 1896:2026
  p <- matrix(rep(seq_along(years), each = 4L), nrow = 4)
  t <- p / 10 + 40
  p[2, ] <- 0
  p[3, years %in% 1896:1910] <- NA
  t[4, years %in% 1991:1994] <- NA
  reference <- list(years = years, precipitation = p, temperature = t)
  value <- historic_monthly_statistics(reference, 2002L)
  target <- match(2002, years)
  expected <- 100 * (target - .5) / length(years)
  testthat::expect_equal(unname(value[1, "precipitation_rank"]), expected)
  testthat::expect_equal(unname(value[1, "temperature_rank"]), expected)
  testthat::expect_equal(unname(value[1, "temperature_record_high"]), 0)
  testthat::expect_equal(unname(value[2, c("precipitation_rank", "precipitation_record_low")]), c(50, 0))
  testthat::expect_true(is.na(value[3, "precipitation_rank"]))
  testthat::expect_true(is.na(value[4, "temperature_departure"]))
  testthat::expect_equal(unname(value[1, "temperature_departure"]), t[1, target] - mean(t[1, years %in% 1991:2020]))
  testthat::expect_equal(unname(value[1, "temperature_normal_years"]), 30)
})

testthat::test_that("precipitation colours stay distinct at the actual unequal-width legend bins", {
  style <- historic_monthly_style("precipitation_total")
  testthat::expect_equal(style$breaks, c(0, .5, 1, 2, 4, 8, 12, 16, 24, 40, 64))
  classes <- map_product_categorical_classes(style$product_id, style$breaks, style$limits)
  midpoints <- (head(classes$breaks, -1L) + tail(classes$breaks, -1L)) / 2
  testthat::expect_equal(style$palette_values, midpoints)
  colours <- scales::gradient_n_pal(style$palette,
    values = (style$palette_values - style$limits[1]) / diff(style$limits))(
      (midpoints - style$limits[1]) / diff(style$limits))
  testthat::expect_identical(toupper(colours), toupper(style$palette))
  lab <- grDevices::convertColor(t(grDevices::col2rgb(colours[1:5])) / 255,
    from = "sRGB", to = "Lab", scale.in = 1)
  differences <- sqrt(rowSums((lab[-1, , drop = FALSE] - lab[-5, , drop = FALSE])^2))
  testthat::expect_true(all(differences > 10))
  testthat::expect_true(all(diff(lab[, 1]) < 0))
})

testthat::test_that("cached reference windows resume, detect damaged outputs and invalidate revised inputs", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  plan <- expand.grid(variable = c("pcpn", "maxt", "mint"),
    month = unlist(lapply(2000:2002, function(y) sprintf("%d-%02d", y, 6:9))), stringsAsFactors = FALSE)
  plan$complete <- TRUE; plan$request_signature <- "fixture"
  plan$path <- file.path(root, paste0(plan$variable, "-", plan$month, ".tif"))
  template <- terra::rast(nrows = 1, ncols = 2, xmin = -112, xmax = -111.9, ymin = 33, ymax = 33.05)
  for (i in seq_len(nrow(plan))) {
    v <- switch(plan$variable[i], pcpn = if (substr(plan$month[i], 6, 7) == "06") 100 else 1, maxt = 80, mint = 40)
    terra::writeRaster(terra::setValues(template, c(v, if (plan$month[i] == "2000-07") NA else v)), plan$path[i])
  }
  plan$md5 <- unname(tools::md5sum(plan$path)); audit <- list(plan = plan)
  a <- historic_monthly_reference(audit, 2000:2002, "monsoon", root, FALSE, "fixture")
  testthat::expect_equal(a$precipitation[1, ], rep(3, 3))
  testthat::expect_true(is.na(a$precipitation[2, 1]))
  testthat::expect_equal(a$temperature[1, ], rep(60, 3))
  b <- historic_monthly_reference(audit, 2000:2002, "monsoon", root, FALSE, "fixture")
  testthat::expect_identical(a, b)
  writeLines("damaged", file.path(root, "reference/monsoon/windows.rds"))
  c <- historic_monthly_reference(audit, 2000:2002, "monsoon", root, FALSE, "fixture")
  testthat::expect_identical(a, c)
  i <- which(plan$variable == "pcpn" & plan$month == "2002-09")
  terra::writeRaster(terra::setValues(template, c(3, 3)), plan$path[i], overwrite = TRUE)
  audit$plan$md5 <- unname(tools::md5sum(plan$path))
  revised <- historic_monthly_reference(audit, 2000:2002, "monsoon", root, FALSE, "fixture")
  testthat::expect_equal(revised$precipitation[1, ], c(3, 3, 5))
  testthat::expect_false(identical(a$signature, revised$signature))
})

testthat::test_that("archive cache seeding is verified, independent and rewrites output record paths", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  original <- file.path(root, "pilot"); expanded <- file.path(root, "archive")
  dir.create(original); dir.create(expanded)
  files <- file.path(original, c("summary.tif", "map.png"))
  writeLines("unit numeric cache", files[1]); writeLines("unit image cache", files[2])
  marker <- file.path(original, "complete.rds"); target <- file.path(expanded, "complete.rds")
  saveRDS(list(signature = "verified", files = files, md5 = unname(tools::md5sum(files)),
    records = data.frame(grid = files[1], map = files[2])), marker)
  before <- tools::md5sum(c(marker, files))
  testthat::expect_false(historic_monthly_seed_cache(marker, target, "wrong-inputs"))
  testthat::expect_false(file.exists(target))
  testthat::expect_true(historic_monthly_seed_cache(marker, target, "verified"))
  copied <- readRDS(target)
  testthat::expect_equal(copied$records$grid, normalizePath(file.path(expanded, "summary.tif"), winslash = "/"))
  testthat::expect_equal(copied$records$map, normalizePath(file.path(expanded, "map.png"), winslash = "/"))
  testthat::expect_true(prism_monthly_ranking_complete(target, "verified"))
  testthat::expect_identical(tools::md5sum(c(marker, files)), before)
  writeLines("damaged copied image", copied$records$map)
  testthat::expect_false(prism_monthly_ranking_complete(target, "verified"))
  testthat::expect_true(historic_monthly_seed_cache(marker, target, "verified"))
  testthat::expect_true(prism_monthly_ranking_complete(target, "verified"))
  writeLines("source changed after verification", files[2])
  testthat::expect_false(historic_monthly_seed_cache(marker, target, "verified"))
  testthat::expect_true(prism_monthly_ranking_complete(target, "verified"))
})
