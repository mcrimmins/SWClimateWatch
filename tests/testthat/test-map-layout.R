testthat::test_that("balanced map export matches publication dimensions", {
  path <- tempfile(fileext = ".png")
  plot <- ggplot2::ggplot(data.frame(x = 0, y = 0), ggplot2::aes(x, y)) +
    ggplot2::geom_point()

  save_southwest_map(
    plot,
    path,
    logo_path = file.path(project_root, southwest_brand_logo_path()),
    footer_text = "Data source: PRISM Climate Group via RCC-ACIS"
  )

  size <- magick::image_info(magick::image_read(path))[1L, c("width", "height")]
  expected <- c(width = 1998L, height = 1533L)
  testthat::expect_equal(unlist(size, use.names = TRUE), expected)
  testthat::expect_equal(
    eval(formals(validate_map_product_publication)$expected_dimensions),
    expected
  )
  testthat::expect_equal(
    eval(formals(build_map_product_site)$expected_dimensions),
    expected
  )
})
