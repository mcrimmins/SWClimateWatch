testthat::test_that("retained freeze map migration has a precise six-product scope", {
  specs <- retained_prism_freeze_map_specs()
  testthat::expect_equal(nrow(specs), 6L)
  testthat::expect_equal(length(unique(specs$id)), 6L)
  testthat::expect_equal(
    as.integer(table(specs$family)), c(2L, 2L, 2L)
  )
})

testthat::test_that("retained layout refresh leaves unpublished and current-size maps alone", {
  maps_dir <- tempfile("retained-maps-")
  products <- data.frame(
    id = c("mint_first_freeze_date", "mint_first_freeze_departure"),
    enabled = c(TRUE, FALSE), stringsAsFactors = FALSE
  )
  result <- refresh_retained_prism_freeze_maps(products, maps_dir = maps_dir, quiet = TRUE)
  testthat::expect_equal(nrow(result), 0L)

  latest <- prism_first_freeze_map_path("observed-day", maps_dir = maps_dir)
  dir.create(dirname(latest), recursive = TRUE)
  magick::image_write(magick::image_blank(1998, 1533), latest)
  result <- refresh_retained_prism_freeze_maps(products, maps_dir = maps_dir, quiet = TRUE)
  testthat::expect_equal(nrow(result), 0L)
  testthat::expect_true(file.exists(latest))
})

testthat::test_that("retained layout refresh does not guess which historical grid to use", {
  maps_dir <- tempfile("retained-maps-")
  products <- data.frame(
    id = "mint_first_freeze_date", enabled = TRUE, stringsAsFactors = FALSE
  )
  latest <- prism_first_freeze_map_path("observed-day", maps_dir = maps_dir)
  dir.create(dirname(latest), recursive = TRUE)
  magick::image_write(magick::image_blank(20, 20), latest)
  testthat::expect_error(
    refresh_retained_prism_freeze_maps(products, maps_dir = maps_dir, quiet = TRUE),
    "No matching dated image"
  )
})
