source(file.path(project_root, "R/regional-seasonal-reference.R"))
source(file.path(project_root, "R/regional-climate-site.R"))
source(file.path(project_root, "R/regional-precipitation-share.R"))

testthat::test_that("seasonal shares use matched ratios and retain genuine zeros", {
  x <- regional_precipitation_shares(c(10, 20), rbind(c(0, 2, 3, 5), c(2, 4, 6, 8)))
  testthat::expect_equal(x, rbind(c(0, 20, 30, 50), c(10, 20, 30, 40)))
  testthat::expect_equal(rowSums(x), c(100, 100))
  testthat::expect_equal(regional_precipitation_shares(10.000001, matrix(c(1,2,3,4), 1)),
    matrix(c(10,20,30,40), 1), tolerance = 1e-5)
  testthat::expect_error(regional_precipitation_shares(11, matrix(c(1,2,3,4), 1)), "do not match")
  testthat::expect_error(regional_precipitation_shares(10, matrix(c(-1,2,3,6), 1)), "non-negative")
})
testthat::test_that("unsupported or zero annual references are withheld", {
  x <- regional_precipitation_shares(c(0, NA, 10), rbind(rep(0,4), c(1,2,3,4), c(NA,2,3,5)))
  testthat::expect_true(all(is.na(x)))
})
testthat::test_that("page variants retain every share and three topic tabs", {
  jobs <- regional_climate_site_jobs("annual", "seasonal", "shares")
  text <- regional_climate_page_text(jobs)
  testthat::expect_equal(nrow(jobs), 14L)
  testthat::expect_equal(sum(grepl("^## ", text)), 3L)
  testthat::expect_equal(sum(grepl("data-reference-card=", text)), 14L)
  testthat::expect_equal(sum(grepl('data-metric="precipitation_share"', text)), 4L)
  testthat::expect_equal(sum(grepl(' hidden>', text)), 12L)
  testthat::expect_true(any(grepl('id="climate-precip-mode"', text)))
  testthat::expect_false(any(jobs$period == "annual" & jobs$variable == "precipitation_share"))
})
