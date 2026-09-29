archive_validation_fixture <- function() {
  root <- tempfile("archive-validation-")
  site_dir <- file.path(root, "site")
  page_dir <- file.path(site_dir, "pages", "archive")
  dir.create(page_dir, recursive = TRUE)
  config <- file.path(site_dir, "_quarto.yml")
  writeLines(c(
    "website:", "  sidebar:", "    contents:",
    "      # BEGIN GENERATED HISTORIC YEARS",
    "      # END GENERATED HISTORIC YEARS"
  ), config)
  years <- c(1982L, 1998L)
  products <- c("cool_total", "water_total")
  roni <- data.frame(water_year = years, djf_roni = c(0.1, 2.1))
  for (year in years) {
    write_prism_archive_page(
      year, roni$djf_roni[match(year, roni$water_year)], page_dir
    )
    rendered_page <- file.path(site_dir, "_site", "pages", "archive",
                               sprintf("wy%04d.html", year))
    dir.create(dirname(rendered_page), recursive = TRUE, showWarnings = FALSE)
    html <- c("<html><body>")
    for (product in products) {
      relative <- sprintf("prism/seasonal-archive/wy%04d/%s.png", year, product)
      image <- file.path(site_dir, "maps", "generated", relative)
      rendered_image <- file.path(site_dir, "_site", "maps", "generated", relative)
      dir.create(dirname(image), recursive = TRUE, showWarnings = FALSE)
      dir.create(dirname(rendered_image), recursive = TRUE, showWarnings = FALSE)
      magick::image_write(magick::image_blank(40, 20, "#4f8fb5"), image)
      file.copy(image, rendered_image)
      href <- paste0("../../maps/generated/", relative)
      html <- c(html, paste0('<img src="', href, '">'),
                paste0('<a href="', href, '">Open full-resolution PNG</a>'))
    }
    writeLines(c(html, "</body></html>"), rendered_page)
  }
  write_prism_archive_navigation(page_dir, config)
  list(root = root, site_dir = site_dir, years = years,
       products = products, roni = roni)
}

testthat::test_that("Historic Years validation checks every source and rendered map", {
  fixture <- archive_validation_fixture()
  result <- validate_prism_archive_publication(
    site_dir = fixture$site_dir, expected_years = fixture$years,
    products = fixture$products, roni = fixture$roni,
    expected_dimensions = c(40L, 20L), minimum_image_bytes = 1,
    require_rendered = TRUE, report_path = file.path(fixture$root, "status.csv")
  )
  testthat::expect_equal(result$summary$maps, 4L)
  testthat::expect_equal(result$summary$failed, 0L)
  testthat::expect_true(file.exists(result$report_path))
})

testthat::test_that("Historic Years validation catches missing published images", {
  fixture <- archive_validation_fixture()
  missing <- file.path(
    fixture$site_dir, "_site", "maps", "generated", "prism",
    "seasonal-archive", "wy1982", "cool_total.png"
  )
  file.remove(missing)
  result <- validate_prism_archive_publication(
    site_dir = fixture$site_dir, expected_years = fixture$years,
    products = fixture$products, roni = fixture$roni,
    expected_dimensions = c(40L, 20L), minimum_image_bytes = 1,
    require_rendered = TRUE, report_path = NULL, fail = FALSE
  )
  failed <- result$status[result$status$validation_status == "FAIL", ]
  testthat::expect_equal(nrow(failed), 1L)
  testthat::expect_match(failed$problems, "rendered PNG is missing")
})

testthat::test_that("Historic Years validation checks layout and copied content", {
  fixture <- archive_validation_fixture()
  source_image <- file.path(
    fixture$site_dir, "maps", "generated", "prism",
    "seasonal-archive", "wy1998", "cool_total.png"
  )
  rendered_image <- file.path(
    fixture$site_dir, "_site", "maps", "generated", "prism",
    "seasonal-archive", "wy1998", "cool_total.png"
  )
  magick::image_write(magick::image_blank(41, 20, "#4f8fb5"), source_image)
  file.copy(source_image, rendered_image, overwrite = TRUE)
  accepted <- validate_prism_archive_publication(
    site_dir = fixture$site_dir, expected_years = fixture$years,
    products = fixture$products, roni = fixture$roni,
    expected_dimensions = c(40L, 20L),
    legacy_dimensions = list(`1998` = c(41L, 20L)),
    minimum_image_bytes = 1, require_rendered = TRUE,
    report_path = NULL
  )
  testthat::expect_equal(accepted$summary$legacy_layout_maps, 1L)
  magick::image_write(magick::image_blank(42, 20, "#4f8fb5"), source_image)
  broken <- validate_prism_archive_publication(
    site_dir = fixture$site_dir, expected_years = fixture$years,
    products = fixture$products, roni = fixture$roni,
    expected_dimensions = c(40L, 20L),
    legacy_dimensions = list(`1998` = c(41L, 20L)),
    minimum_image_bytes = 1, require_rendered = TRUE,
    report_path = NULL, fail = FALSE
  )
  testthat::expect_true(any(grepl(
    "source PNG dimensions are incorrect", broken$status$problems, fixed = TRUE
  )))
  testthat::expect_true(any(grepl(
    "rendered PNG differs from source", broken$status$problems, fixed = TRUE
  )))
})

testthat::test_that("Historic Years validation catches missing years and stale badges", {
  fixture <- archive_validation_fixture()
  page <- file.path(fixture$site_dir, "pages", "archive", "wy1998.qmd")
  lines <- readLines(page, warn = FALSE)
  writeLines(sub("RONI +2.1", "RONI +1.1", lines, fixed = TRUE), page)
  result <- validate_prism_archive_publication(
    site_dir = fixture$site_dir, expected_years = c(fixture$years, 2011L),
    products = fixture$products,
    roni = rbind(fixture$roni, data.frame(water_year = 2011L, djf_roni = -1.4)),
    expected_dimensions = c(40L, 20L), minimum_image_bytes = 1,
    report_path = NULL, fail = FALSE
  )
  testthat::expect_true(any(grepl("RONI badge disagrees", result$status$problems)))
  missing_year <- result$status[result$status$water_year == 2011L, ]
  testthat::expect_true(all(grepl("source page is missing", missing_year$problems)))
  testthat::expect_true(all(grepl("navigation entry is missing", missing_year$problems)))
})
