testthat::test_that("default update plan includes every configured map", {
  products <- read_map_product_config(file.path(project_root, "config", "map-products.yml"))
  plan <- plan_enabled_prism_map_updates(products)
  testthat::expect_equal(plan$temperature_values, c("maxt", "mint", "tmean"))
  testthat::expect_equal(plan$temperature_rolling_percentiles, c(7L, 30L, 90L))
  testthat::expect_equal(plan$precipitation_totals, c(1L, 7L, 30L, 90L))
  testthat::expect_equal(plan$precipitation_accumulations, c(1L, 7L, 30L, 90L))
  testthat::expect_equal(
    plan$water_year,
    c("total", "percent-normal", "percentile-rank")
  )
  testthat::expect_true(plan$water_year_concentration)
  testthat::expect_true(plan$water_year_work)
  testthat::expect_true(plan$water_year_maximum_work)
})

testthat::test_that("update plan removes only disabled products", {
  products <- read_map_product_config(file.path(project_root, "config", "map-products.yml"))
  products$enabled[products$id %in% c(
    "tmean_value", "pcpn_total_30day", "mint_first_freeze_departure"
  )] <- FALSE
  plan <- plan_enabled_prism_map_updates(products)

  testthat::expect_equal(plan$temperature_values, c("maxt", "mint"))
  testthat::expect_equal(plan$precipitation_totals, c(1L, 7L, 90L))
  testthat::expect_equal(plan$precipitation_accumulations, c(1L, 7L, 30L, 90L))
  testthat::expect_equal(plan$first_freeze, "observed-day")
})

testthat::test_that("shared water-year work remains when only concentration is enabled", {
  products <- read_map_product_config(file.path(project_root, "config", "map-products.yml"))
  products$enabled <- products$id == "pcpn_water_year_concentration_03day"

  plan <- plan_enabled_prism_map_updates(products)

  testthat::expect_length(plan$water_year, 0L)
  testthat::expect_length(plan$water_year_maximum, 0L)
  testthat::expect_true(plan$water_year_work)
  testthat::expect_true(plan$water_year_maximum_work)
})

testthat::test_that("paired map builders validate selected outputs", {
  testthat::expect_equal(
    validate_southwest_map_products("departure", c("observed-day", "departure")),
    "departure"
  )
  testthat::expect_error(
    validate_southwest_map_products("unknown", c("observed-day", "departure")),
    "Unsupported map product"
  )
})
