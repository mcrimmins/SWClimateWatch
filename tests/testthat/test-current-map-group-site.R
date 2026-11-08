testthat::test_that("grouped navigation replaces only the reviewed products", {
  products <- read_map_product_config(file.path(project_root,"config/map-products.yml"))
  navigation <- map_product_navigation_lines(products)
  text <- paste(navigation,collapse="\n")
  for (key in names(current_site_groups())) {
    testthat::expect_equal(sum(grepl(paste0("pages/",key,".qmd"),navigation,fixed=TRUE)),1L)
  }
  testthat::expect_false(grepl("Original individual",text,fixed=TRUE))
  testthat::expect_false(grepl("pages/products/maxt_value.qmd",text,fixed=TRUE))
  testthat::expect_true(grepl("pages/products/maxt_extreme_warm_count_30day.qmd",text,fixed=TRUE))
  testthat::expect_true(grepl("pages/products/pcpn_water_year_total.qmd",text,fixed=TRUE))
})

testthat::test_that("grouped site honors disabled maps and retains unavailable notices", {
  root <- tempfile("grouped-site-"); dir.create(root)
  on.exit(unlink(root,recursive=TRUE),add=TRUE)
  catalog <- file.path(root,"catalog.yml")
  writeLines(c("products:","  maxt_value:","    enabled: true","    label: Maximum temperature",
    "    description: Maximum temperature in degrees F.","    image: prism/temperature/maxt.png",
    "  mint_value:","    enabled: false","    label: Minimum temperature",
    "    description: Minimum temperature in degrees F.","    image: prism/temperature/mint.png"),catalog)
  manifest <- stage_current_map_groups(root,catalog)
  testthat::expect_true("maxt_value" %in% manifest$product)
  testthat::expect_false("mint_value" %in% manifest$product)
  page <- paste(readLines(file.path(root,"pages/temperature-values.qmd")),collapse="\n")
  testthat::expect_true(grepl("currently unavailable",page,fixed=TRUE))
  testthat::expect_false(grepl("Original individual",page,fixed=TRUE))
  testthat::expect_false(grepl("laptop",page,fixed=TRUE))
  writeLines(c("website:","  sidebar:","    contents:","      - href: pages/temperature-values.qmd",
    "      - href: pages/snow-conditions.qmd"),file.path(root,"_quarto.yml"))
  testthat::expect_silent(invisible(suppressMessages(validate_current_map_groups(root,report_dir=file.path(root,"report")))))
  writeLines("corrupt",file.path(root,"assets/current-map-groups/current-map-groups.js"))
  testthat::expect_error(validate_current_map_groups(root,report_dir=file.path(root,"report")),"checksum")
})
