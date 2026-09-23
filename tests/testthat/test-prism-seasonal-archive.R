testthat::test_that("archive periods use complete October-September water years", {
  period <- prism_archive_periods(1998)
  testthat::expect_equal(period$cool_start, as.Date("1997-10-01"))
  testthat::expect_equal(period$cool_end, as.Date("1998-03-31"))
  testthat::expect_equal(period$water_end, as.Date("1998-09-30"))
  testthat::expect_error(prism_archive_periods(1981), "1982")
})

testthat::test_that("seasonal summaries keep precipitation and wet-day units", {
  dates <- seq(as.Date("1997-10-01"), as.Date("1998-09-30"), by = "day")
  daily <- terra::rast(nrows = 1, ncols = 2, nlyrs = length(dates))
  terra::values(daily) <- rbind(rep(0.10, length(dates)), rep(0.02, length(dates)))
  terra::time(daily) <- dates
  summary <- prism_archive_summary_from_daily(daily, 1998)
  cool_days <- length(seq(as.Date("1997-10-01"), as.Date("1998-03-31"), by = "day"))
  testthat::expect_identical(names(summary), c("cool_total", "cool_wet_count", "water_total"))
  testthat::expect_equal(as.numeric(terra::values(summary[["cool_total"]]))[1], cool_days * 0.10)
  testthat::expect_equal(as.numeric(terra::values(summary[["cool_wet_count"]]))[1], cool_days)
  testthat::expect_equal(as.numeric(terra::values(summary[["cool_wet_count"]]))[2], 0)
  testthat::expect_equal(as.numeric(terra::values(summary[["water_total"]]))[1], length(dates) * 0.10)
  testthat::expect_error(
    prism_archive_summary_from_daily(daily[[seq_len(length(dates) - 1L)]], 1998),
    "every ordered daily layer"
  )
})

testthat::test_that("archive ranks compare a season against the fixed year sample", {
  reference <- terra::rast(nrows = 1, ncols = 1, nlyrs = 3)
  terra::values(reference) <- matrix(c(1, 2, 3), nrow = 1)
  rank <- prism_archive_percentile_rank(reference[[2]], reference, "rank", as.Date("1998-03-31"))
  testthat::expect_equal(as.numeric(terra::values(rank)), 50)
  testthat::expect_equal(as.Date(terra::time(rank)), as.Date("1998-03-31"))
})

testthat::test_that("pilot pages present exactly eight documented map products", {
  specs <- prism_archive_product_specs()
  testthat::expect_equal(nrow(specs), 8L)
  testthat::expect_equal(length(unique(specs$id)), 8L)
  page_dir <- tempfile("archive-pages-")
  page <- write_prism_archive_pilot_page(1998, 2.1, page_dir)
  text <- readLines(page, warn = FALSE)
  testthat::expect_equal(sum(grepl("Open full-resolution PNG", text, fixed = TRUE)), 8L)
  testthat::expect_equal(sum(grepl("archive-map-description", text, fixed = TRUE)), 8L)
  testthat::expect_true(any(grepl("archive-roni-el-nino", text, fixed = TRUE)))
  testthat::expect_true(any(grepl("RONI +2.1", text, fixed = TRUE)))
  testthat::expect_true(any(grepl("archive-roni-badge", text, fixed = TRUE)))
  testthat::expect_true(any(grepl("Relative Oceanic", text, fixed = TRUE)))
  testthat::expect_false(any(grepl("The color describes this three-month value", text, fixed = TRUE)))
  testthat::expect_true(any(grepl("toc: false", text, fixed = TRUE)))
  testthat::expect_true(any(grepl("bread-crumbs: false", text, fixed = TRUE)))
  testthat::expect_true(any(grepl("page-layout: full", text, fixed = TRUE)))
  testthat::expect_false(any(grepl("1997-98 El Niño", text, fixed = TRUE)))
})

testthat::test_that("RONI badges cover warm, neutral, and cold ranges", {
  testthat::expect_identical(prism_archive_roni_category(0.5)$class, "archive-roni-el-nino")
  testthat::expect_identical(prism_archive_roni_category(-0.5)$class, "archive-roni-la-nina")
  testthat::expect_identical(prism_archive_roni_category(0)$class, "archive-roni-neutral")
  testthat::expect_error(prism_archive_roni_category(NA_real_), "finite numeric")
  page_dir <- tempfile("archive-pages-")
  cold_page <- write_prism_archive_pilot_page(2011, -1.4, page_dir)
  testthat::expect_true(any(grepl("archive-roni-la-nina", readLines(cold_page), fixed = TRUE)))
  neutral_page <- write_prism_archive_pilot_page(2000, 0.1, page_dir)
  testthat::expect_true(any(grepl("[Neutral", readLines(neutral_page), fixed = TRUE)))
})
