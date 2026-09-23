testthat::test_that("versioned Southwest reference layers are readable", {
  layer_names <- c("tribal", "rivers", "interstates")
  reference_dir <- file.path(project_root, "reference", "map-layers")
  paths <- vapply(
    layer_names,
    southwest_reference_layer_path,
    character(1),
    reference_dir = reference_dir
  )

  testthat::expect_true(all(file.exists(paths)))
  layers <- Map(
    function(layer, path) {
      read_southwest_reference_layer(layer, path = path, required = TRUE)
    },
    layer_names,
    paths
  )
  testthat::expect_true(all(vapply(layers, inherits, logical(1), "sf")))
  testthat::expect_gt(nrow(layers[[1L]]), 0L)
  testthat::expect_gt(nrow(layers[[2L]]), 0L)
  testthat::expect_gt(nrow(layers[[3L]]), 0L)
  testthat::expect_equal(nrow(layers[[1L]]), 83L)
  testthat::expect_true(all(
    layers[[1L]][["regional_minimum_component_km2"]] == 25
  ))
})

testthat::test_that("regional tribal generalization retains every entity", {
  full_path <- file.path(
    project_root, "reference", "map-layers",
    "tribal-areas-census-2025-full.gpkg"
  )
  full <- sf::st_read(full_path, quiet = TRUE)
  regional <- generalize_southwest_tribal_boundaries(full, 25)

  full_parts <- suppressWarnings(sf::st_cast(sf::st_make_valid(full), "POLYGON"))
  testthat::expect_equal(nrow(full_parts), 627L)
  testthat::expect_equal(nrow(regional), 83L)
  testthat::expect_setequal(unique(regional[["NAME"]]), unique(full[["NAME"]]))
})

testthat::test_that("reference layers stay within the padded regional context", {
  bbox <- southwest_reference_bbox()
  testthat::expect_equal(unname(bbox[c("xmin", "xmax")]), c(-115.85, -102.20))
  testthat::expect_equal(unname(bbox[c("ymin", "ymax")]), c(30.50, 37.85))
})

testthat::test_that("map context options are explicit and reversible", {
  old <- options()[c("swc.map.tribal", "swc.map.rivers", "swc.map.interstates")]
  on.exit(options(old), add = TRUE)

  result <- configure_southwest_map_context(
    tribal = FALSE,
    rivers = TRUE,
    interstates = TRUE
  )

  testthat::expect_identical(result, list(
    tribal = FALSE,
    rivers = TRUE,
    interstates = TRUE
  ))
  testthat::expect_false(getOption("swc.map.tribal"))
  testthat::expect_true(getOption("swc.map.rivers"))
  testthat::expect_true(getOption("swc.map.interstates"))
})

testthat::test_that("standard precipitation maps request river context", {
  testthat::expect_match(
    paste(deparse(formals(build_prism_accumulation_map)$rivers), collapse = ""),
    "southwest_major_rivers"
  )
  testthat::expect_match(
    paste(deparse(formals(build_prism_accumulation_percentile_rank_map)$rivers), collapse = ""),
    "southwest_major_rivers"
  )
  testthat::expect_match(
    paste(deparse(formals(build_prism_accumulation_percent_normal_map)$rivers), collapse = ""),
    "southwest_major_rivers"
  )
})
