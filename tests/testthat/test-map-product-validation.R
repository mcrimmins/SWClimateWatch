write_validation_png <- function(path, date, width = 40L, height = 20L) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  dated <- sub("latest\\.png$", paste0(date, ".png"), path)
  image <- magick::image_blank(width, height, color = "#4f8fb5")
  magick::image_write(image, dated, format = "png")
  file.copy(dated, path, overwrite = TRUE)
  invisible(dated)
}

validation_fixture <- function() {
  root <- tempfile("map-product-validation-")
  site_dir <- file.path(root, "site")
  dir.create(file.path(root, "config"), recursive = TRUE)
  dir.create(file.path(site_dir, "pages", "products"), recursive = TRUE)
  config_path <- file.path(root, "config", "map-products.yml")
  writeLines(c(
    "version: 1",
    "defaults:",
    "  enabled: true",
    "  scale: continuous",
    "dashboard:",
    "  products:",
    "    - current_map",
    "    - extra_map_1",
    "    - extra_map_2",
    "    - mint_first_freeze_date",
    "products:",
    "  current_map:",
    "    section: Temperature",
    "    group: Current values",
    "    label: Current map",
    "    image: prism/temperature/current-latest.png",
    "    description: Shows the latest temperature. Higher values mean warmer conditions.",
    "  mint_first_freeze_date:",
    "    section: Temperature",
    "    group: Freeze monitoring",
    "    label: First freeze",
    "    image: prism/temperature/seasonal-latest.png",
    "    description: Shows the first freeze date. Later dates mean a longer warm season.",
    "  extra_map_1:",
    "    section: Temperature",
    "    group: Current values",
    "    label: Extra map 1",
    "    image: prism/temperature/extra-1-latest.png",
    "    description: Shows a temperature value. Higher values mean warmer conditions.",
    "  extra_map_2:",
    "    section: Temperature",
    "    group: Current values",
    "    label: Extra map 2",
    "    image: prism/temperature/extra-2-latest.png",
    "    description: Shows another temperature value. Higher values mean warmer conditions.",
    "  disabled_map:",
    "    enabled: false",
    "    section: Precipitation",
    "    group: Recent totals",
    "    label: Disabled map",
    "    image: prism/precipitation/disabled-latest.png",
    "    description: Shows a precipitation value. Higher values mean wetter conditions."
  ), config_path)
  writeLines(c(
    "website:",
    "  sidebar:",
    "    contents:",
    "      # BEGIN GENERATED MAP BROWSER",
    "      # END GENERATED MAP BROWSER"
  ), file.path(site_dir, "_quarto.yml"))
  current <- file.path(
    site_dir, "maps", "generated", "prism", "temperature", "current-latest.png"
  )
  seasonal <- file.path(
    site_dir, "maps", "generated", "prism", "temperature", "seasonal-latest.png"
  )
  write_validation_png(current, "2026-09-09")
  write_validation_png(seasonal, "2026-07-31")
  write_validation_png(file.path(
    site_dir, "maps", "generated", "prism", "temperature", "extra-1-latest.png"
  ), "2026-09-09")
  write_validation_png(file.path(
    site_dir, "maps", "generated", "prism", "temperature", "extra-2-latest.png"
  ), "2026-09-09")
  products <- build_map_product_site(
    config_path = config_path,
    site_dir = site_dir,
    expected_data_dates = c(Temperature = "2026-09-09"),
    expected_dimensions = c(40L, 20L),
    minimum_image_bytes = 1,
    status_path = file.path(root, "status.csv")
  )
  list(root = root, site_dir = site_dir, products = products, current = current)
}

testthat::test_that("publication validation checks images, dates, pages, and navigation", {
  fixture <- validation_fixture()
  report <- file.path(fixture$root, "validation.csv")
  validation <- validate_map_product_publication(
    products = fixture$products,
    site_dir = fixture$site_dir,
    expected_data_dates = c(Temperature = "2026-09-09"),
    expected_dimensions = c(40L, 20L),
    minimum_image_bytes = 1,
    report_path = report
  )

  testthat::expect_equal(validation$summary$failed, 0L)
  testthat::expect_true(file.exists(report))
  current <- validation$status[validation$status$id == "current_map", , drop = FALSE]
  seasonal <- validation$status[
    validation$status$id == "mint_first_freeze_date", , drop = FALSE
  ]
  testthat::expect_equal(current$actual_data_date, "2026-09-09")
  testthat::expect_equal(current$freshness_policy, "current")
  testthat::expect_equal(seasonal$actual_data_date, "2026-07-31")
  testthat::expect_equal(seasonal$freshness_policy, "seasonal-retention")
})

testthat::test_that("publication validation rejects stale and unreadable current maps", {
  fixture <- validation_fixture()
  stale <- validate_map_product_publication(
    products = fixture$products,
    site_dir = fixture$site_dir,
    expected_data_dates = c(Temperature = "2026-09-10"),
    expected_dimensions = c(40L, 20L),
    minimum_image_bytes = 1,
    report_path = NULL,
    fail = FALSE
  )
  current <- stale$status[stale$status$id == "current_map", , drop = FALSE]
  testthat::expect_equal(current$validation_status, "FAIL")
  testthat::expect_match(current$problems, "map data date")

  con <- file(fixture$current, open = "wb")
  writeBin(as.raw(1:10), con)
  close(con)
  testthat::expect_error(
    validate_map_product_publication(
      products = fixture$products,
      site_dir = fixture$site_dir,
      expected_data_dates = c(Temperature = "2026-09-09"),
      expected_dimensions = c(40L, 20L),
      minimum_image_bytes = 1,
      report_path = NULL
    ),
    "not a readable PNG"
  )
})

testthat::test_that("publication validation checks rendered pages and download links", {
  fixture <- validation_fixture()
  enabled <- fixture$products[fixture$products$enabled, , drop = FALSE]
  for (index in seq_len(nrow(enabled))) {
    product <- enabled[index, , drop = FALSE]
    path <- file.path(
      fixture$site_dir, "_site", "pages", "products", paste0(product$id, ".html")
    )
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    reference <- paste0("../../maps/generated/", product$image)
    writeLines(c(
      paste0('<img src="', reference, '">'),
      paste0('<a href="', reference, '">Open full-resolution PNG</a>')
    ), path)
  }
  validation <- validate_map_product_publication(
    products = fixture$products,
    site_dir = fixture$site_dir,
    expected_data_dates = c(Temperature = "2026-09-09"),
    expected_dimensions = c(40L, 20L),
    minimum_image_bytes = 1,
    require_rendered = TRUE,
    report_path = NULL
  )
  testthat::expect_equal(validation$summary$failed, 0L)

  broken <- file.path(
    fixture$site_dir, "_site", "pages", "products", "current_map.html"
  )
  writeLines('<img src="../../maps/generated/prism/temperature/current-latest.png">', broken)
  testthat::expect_error(
    validate_map_product_publication(
      products = fixture$products,
      site_dir = fixture$site_dir,
      expected_data_dates = c(Temperature = "2026-09-09"),
      expected_dimensions = c(40L, 20L),
      minimum_image_bytes = 1,
      require_rendered = TRUE,
      report_path = NULL
    ),
    "rendered full-resolution link is missing"
  )
})
