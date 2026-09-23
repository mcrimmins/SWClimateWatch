testthat::test_that("complete map catalog covers every published current map", {
  products <- read_map_product_config(file.path(project_root, "config", "map-products.yml"))

  testthat::expect_equal(nrow(products), 51L)
  testthat::expect_equal(sum(products$enabled), 51L)
  testthat::expect_setequal(unique(products$section), c("Temperature", "Precipitation"))
  testthat::expect_equal(length(unique(products$id)), 51L)
  testthat::expect_equal(length(unique(products$image)), 51L)
  testthat::expect_true(all(grepl("-latest\\.png$", products$image)))
  testthat::expect_true(all(nzchar(products$description)))
  sentence_count <- lengths(regmatches(
    products$description,
    gregexpr("[.!?]( |$)", products$description)
  ))
  testthat::expect_true(all(sentence_count == 2L))
  percentile_products <- grepl("percentile", products$id)
  testthat::expect_true(all(products$scale[percentile_products] == "categorical"))
  testthat::expect_true(all(products$scale[!percentile_products] == "continuous"))

  dashboard <- read_map_dashboard_config(
    file.path(project_root, "config", "map-products.yml"),
    products
  )
  testthat::expect_equal(nrow(dashboard), 6L)
  testthat::expect_equal(
    dashboard$id,
    c(
      "tmean_percentile_07day",
      "tmean_percentile_30day",
      "pcpn_percentile_30day",
      "pcpn_percentile_90day",
      "pcpn_current_dry_spell_percentile",
      "pcpn_water_year_percentile"
    )
  )
  testthat::expect_true(all(dashboard$enabled))
  generated_homepage <- map_dashboard_page_text(dashboard)
  testthat::expect_true(any(grepl("https://www.climas.arizona.edu/", generated_homepage, fixed = TRUE)))
  testthat::expect_true(any(grepl("https://cales.arizona.edu/climate/", generated_homepage, fixed = TRUE)))
  testthat::expect_true(any(grepl("https://extension.arizona.edu/topics/climate", generated_homepage, fixed = TRUE)))
  testthat::expect_true(any(grepl("mailto:crimmins@arizona.edu", generated_homepage, fixed = TRUE)))
})

testthat::test_that("redundant map landing pages are absent", {
  site_dir <- file.path(project_root, "site")
  testthat::expect_false(file.exists(file.path(site_dir, "pages", "current-conditions.qmd")))
  testthat::expect_false(file.exists(file.path(site_dir, "pages", "map-browser.qmd")))
  navigation <- readLines(file.path(site_dir, "_quarto.yml"), warn = FALSE)
  homepage <- readLines(file.path(site_dir, "index.qmd"), warn = FALSE)
  testthat::expect_true(any(grepl("draft-mode: gone", navigation, fixed = TRUE)))
  for (draft_page in c("atmosphere", "forecasts", "el-nino")) {
    testthat::expect_true(any(grepl(paste0("- pages/", draft_page, ".qmd"), navigation, fixed = TRUE)))
    testthat::expect_false(any(grepl(paste0("- href: pages/", draft_page, ".qmd"), navigation, fixed = TRUE)))
    testthat::expect_true(file.exists(file.path(site_dir, "pages", paste0(draft_page, ".qmd"))))
  }
  testthat::expect_true(any(grepl("logo: assets/branding/southwest-climate-watch-mark-transparent.png", navigation, fixed = TRUE)))
  testthat::expect_true(file.exists(file.path(site_dir, "assets", "branding", "southwest-climate-watch-mark-transparent.png")))
  testthat::expect_false(any(grepl("current-conditions.qmd|map-browser.qmd", c(navigation, homepage))))
  testthat::expect_true(any(grepl("Explore all maps from Map Browser", homepage, fixed = TRUE)))
  testthat::expect_true(any(grepl("[Climate Assessment for the Southwest](https://www.climas.arizona.edu/)", homepage, fixed = TRUE)))
  testthat::expect_true(any(grepl("[Climate Science Applications Program](https://cales.arizona.edu/climate/)", homepage, fixed = TRUE)))
  testthat::expect_true(any(grepl("[University of Arizona Cooperative Extension](https://extension.arizona.edu/topics/climate)", homepage, fixed = TRUE)))
  testthat::expect_true(any(grepl("![](assets/branding/ua-csap-climas-logos-horizontal.png)", homepage, fixed = TRUE)))
  testthat::expect_true(any(grepl("Mike Crimmins", homepage, fixed = TRUE)))
  testthat::expect_true(any(grepl("[crimmins@arizona.edu](mailto:crimmins@arizona.edu)", homepage, fixed = TRUE)))
})

testthat::test_that("map site generation honors enabled products", {
  root <- tempfile("map-product-site-")
  dir.create(file.path(root, "config"), recursive = TRUE)
  dir.create(file.path(root, "site", "pages", "products"), recursive = TRUE)
  config_path <- file.path(root, "config", "map-products.yml")
  quarto_path <- file.path(root, "site", "_quarto.yml")
  writeLines(c(
    "version: 1",
    "defaults:",
    "  enabled: true",
    "  scale: continuous",
    "dashboard:",
    "  products:",
    "    - enabled_map",
    "    - dashboard_map_2",
    "    - dashboard_map_3",
    "    - dashboard_map_4",
    "products:",
    "  enabled_map:",
    "    section: Temperature",
    "    group: Current values",
    "    label: Enabled map",
    "    image: prism/temperature/enabled.png",
    "    description: Shows the latest value. Higher values mean warmer conditions.",
    "  disabled_map:",
    "    enabled: false",
    "    scale: categorical",
    "    section: Precipitation",
    "    group: Recent totals",
    "    label: Disabled map",
    "    image: prism/precipitation/disabled.png",
    "    description: Shows a precipitation total. Higher values mean wetter conditions.",
    "  dashboard_map_2:",
    "    section: Temperature",
    "    group: Current values",
    "    label: Dashboard map 2",
    "    image: prism/temperature/dashboard-2.png",
    "    description: Shows a second temperature value. Higher values mean warmer conditions.",
    "  dashboard_map_3:",
    "    section: Precipitation",
    "    group: Recent totals",
    "    label: Dashboard map 3",
    "    image: prism/precipitation/dashboard-3.png",
    "    description: Shows a third map value. Higher values mean wetter conditions.",
    "  dashboard_map_4:",
    "    section: Precipitation",
    "    group: Recent totals",
    "    label: Dashboard map 4",
    "    image: prism/precipitation/dashboard-4.png",
    "    description: Shows a fourth map value. Higher values mean wetter conditions."
  ), config_path)
  writeLines(c(
    "website:",
    "  sidebar:",
    "    contents:",
    "      # BEGIN GENERATED MAP BROWSER",
    "      # END GENERATED MAP BROWSER"
  ), quarto_path)
  stale <- file.path(root, "site", "pages", "products", "disabled_map.qmd")
  writeLines("stale", stale)

  products <- build_map_product_site(
    config_path = config_path,
    site_dir = file.path(root, "site"),
    require_images = FALSE
  )
  navigation <- readLines(quarto_path, warn = FALSE)

  testthat::expect_equal(nrow(products), 5L)
  testthat::expect_true(file.exists(file.path(
    root, "site", "pages", "products", "enabled_map.qmd"
  )))
  testthat::expect_false(file.exists(stale))
  testthat::expect_true(any(grepl("enabled_map.qmd", navigation, fixed = TRUE)))
  testthat::expect_false(any(grepl("disabled_map.qmd", navigation, fixed = TRUE)))
  testthat::expect_false(any(grepl("map-browser.qmd|text: Overview", navigation)))
  homepage <- readLines(file.path(root, "site", "index.qmd"), warn = FALSE)
  testthat::expect_true(any(grepl("dashboard-map-grid", homepage, fixed = TRUE)))
  testthat::expect_equal(sum(grepl("dashboard-map-card", homepage, fixed = TRUE)), 4L)
  testthat::expect_true(any(grepl("enabled_map.qmd", homepage, fixed = TRUE)))
  testthat::expect_true(any(grepl("Explore all maps from Map Browser", homepage, fixed = TRUE)))
})

testthat::test_that("dashboard rejects unknown, duplicate, and disabled products", {
  path <- tempfile(fileext = ".yml")
  base <- c(
    "version: 1",
    "defaults:",
    "  enabled: true",
    "  scale: continuous",
    "dashboard:",
    "  products:",
    "    - map_1",
    "    - map_2",
    "    - map_3",
    "    - map_4",
    "products:"
  )
  product_lines <- unlist(lapply(1:4, function(index) c(
    paste0("  map_", index, ":"),
    "    section: Temperature",
    "    group: Current values",
    paste0("    label: Map ", index),
    paste0("    image: map-", index, ".png"),
    "    description: Shows a test value. Higher values mean more."
  )), use.names = FALSE)
  writeLines(c(base, product_lines), path)
  products <- read_map_product_config(path)
  testthat::expect_equal(nrow(read_map_dashboard_config(path, products)), 4L)

  text <- readLines(path, warn = FALSE)
  writeLines(sub("    - map_4", "    - missing_map", text, fixed = TRUE), path)
  testthat::expect_error(read_map_dashboard_config(path), "Unknown.*missing_map")

  writeLines(sub("    - missing_map", "    - map_1", readLines(path), fixed = TRUE), path)
  testthat::expect_error(read_map_dashboard_config(path), "non-empty and unique")

  disabled_product_lines <- append(
    product_lines,
    "    enabled: false",
    after = grep("^  map_4:$", product_lines)
  )
  writeLines(c(base, disabled_product_lines), path)
  testthat::expect_error(read_map_dashboard_config(path), "must be enabled.*map_4")
})

testthat::test_that("map catalog rejects unsupported scale modes", {
  path <- tempfile(fileext = ".yml")
  writeLines(c(
    "version: 1",
    "products:",
    "  bad_scale:",
    "    enabled: true",
    "    scale: rainbow",
    "    section: Temperature",
    "    group: Current values",
    "    label: Bad scale",
    "    image: bad.png",
    "    description: Shows a test value. Higher values mean more."
  ), path)
  testthat::expect_error(
    read_map_product_config(path),
    "continuous.*categorical"
  )
})

testthat::test_that("product pages place the map before supporting text", {
  products <- read_map_product_config(file.path(project_root, "config", "map-products.yml"))
  page <- map_product_page_text(products[products$id == "tmean_percentile_daily", , drop = FALSE])

  testthat::expect_true(any(grepl('^title: "Mean temperature"$', page)))
  testthat::expect_true("body-classes: product-page" %in% page)
  testthat::expect_true(any(grepl("latest daily mean temperature", page, fixed = TRUE)))
  testthat::expect_false(any(grepl("product-breadcrumb|product-summary|product-badge", page)))
  testthat::expect_false(any(grepl("^Daily update$|color scale$", page)))
  testthat::expect_lt(
    grep("product-map-card", page, fixed = TRUE),
    grep("product-interpretation", page, fixed = TRUE)
  )
  testthat::expect_lt(
    grep("product-interpretation", page, fixed = TRUE),
    grep("Open full-resolution PNG", page, fixed = TRUE)
  )
})

testthat::test_that("Methods page documents data timing and every map family", {
  page <- paste(
    readLines(file.path(project_root, "site", "pages", "methods.qmd"), warn = FALSE),
    collapse = "\n"
  )

  for (source in c(
    "https://prism.oregonstate.edu/data/",
    "https://prism.oregonstate.edu/calendar/",
    "https://www.rcc-acis.org/docs_webservices.html",
    "https://github.com/mcrimmins/SWClimateWatch"
  )) {
    testthat::expect_true(grepl(source, page, fixed = TRUE))
  }
  for (section in c("## Temperature maps", "## Precipitation maps", "## Historic Years")) {
    testthat::expect_true(grepl(section, page, fixed = TRUE))
  }
  testthat::expect_true(grepl("preliminary data", page, fixed = TRUE))
  testthat::expect_true(grepl("1991", page, fixed = TRUE))
  testthat::expect_true(grepl("1982", page, fixed = TRUE))
  testthat::expect_false(grepl("terra|ggplot2|lubridate|S3 deployment", page))
})
