source(file.path(project_root, "R/conditions-synopsis-evidence.R"))
source(file.path(project_root, "R/conditions-synopsis-template.R"))
source(file.path(project_root, "R/conditions-synopsis-seasonal-review.R"))
source(file.path(project_root, "R/conditions-synopsis-regional-highlights.R"))

testthat::test_that("highlight grids use area weights, bounded ranges and matching dates", {
  config <- synopsis_config(file.path(project_root, "config/conditions-synopsis.yml"))
  stat <- synopsis_highlight_stats(c(6,5,8), c(1,2,1), "count", config)
  testthat::expect_equal(stat$value[["area_extreme_days"]], 50)
  testthat::expect_equal(stat$value[["mean_days"]], 6)
  testthat::expect_equal(synopsis_highlight_stats(c(20,-20,0), c(1,2,1), "change", config)$value,
    c(area_rank_increased = 25, area_rank_decreased = 50))
  testthat::expect_equal(synopsis_highlight_stats(c(31,0), c(1,1), "count", config)$status, "INVALID_RANGE")
  testthat::expect_equal(synopsis_highlight_stats(c(1.5,0), c(1,1), "count", config)$status, "INVALID_RANGE")
  testthat::expect_equal(synopsis_highlight_stats(c(1,NA), c(1,1), "count", config)$status, "LOW_COVERAGE")
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  specs <- synopsis_highlight_specs(root, "2026-11-03")
  dir.create(dirname(specs$path[1L]), recursive = TRUE)
  r <- terra::rast(nrows = 2, ncols = 2); terra::values(r) <- 6; terra::time(r) <- as.Date("2026-11-02")
  terra::writeRaster(r, specs$path[1L])
  facts <- synopsis_highlight_grid_inventory(root, as.Date("2026-11-03"), config)
  testthat::expect_true(all(facts$status == "UNAVAILABLE"))
  testthat::expect_match(facts$note[1L], "do not match")
})

testthat::test_that("station counts exclude ThreadEx, partial/stale/flagged and duplicate records", {
  config <- synopsis_config(file.path(project_root, "config/conditions-synopsis.yml"))
  config$regional_highlights$minimum_stations <- 2; config$regional_highlights$minimum_state_stations <- 1
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  dir.create(file.path(root, "site/stations/station-details"), recursive = TRUE)
  dir.create(file.path(root, "data/diagnostics/acis-stations/publication-audit"), recursive = TRUE)
  x <- data.frame(uid = 1:8, sid = paste0("fixed-", 1:8), role = "fixed", state = rep(c("AZ","NM"), 4),
    as_of = "2026-11-03", cache_as_of = "2026-11-03", period = "30day", period_start = "2026-10-05", period_days = 30,
    pcpn_percentile = c(95,90,99,99,99,99,99,99), pcpn_reference_years = 40, pcpn_status = "AVAILABLE", pcpn_missing_days = 0, pcpn_flagged_days = 0)
  x$role[3] <- "threadex"; x$pcpn_missing_days[4] <- 1; x$as_of[5] <- "2026-11-02"
  x$sid[7:8] <- "duplicate-record"
  a <- data.frame(uid = 1:8, period = "30day", page_date = "2026-11-03", metric = "pcpn_percentile", publication_status = "DISPLAY")
  for (i in 1:8) {
    d <- data.frame(date = as.character(seq(as.Date("2026-10-05"), as.Date("2026-11-03"), by = "day")), pcpn = 0, pcpn_status = "AVAILABLE")
    if (i == 6) d$pcpn_status[1] <- "FLAGGED"
    jsonlite::write_json(list(uid = i, as_of = "2026-11-03", daily = d), file.path(root, "site/stations/station-details", paste0(i, ".json")), auto_unbox = TRUE, dataframe = "rows")
  }
  utils::write.csv(x, file.path(root, "site/stations/station-explorer-data.csv"), row.names = FALSE)
  utils::write.csv(a, file.path(root, "data/diagnostics/acis-stations/publication-audit/product-readiness.csv"), row.names = FALSE)
  packet <- synopsis_station_network_counts(root, as.Date("2026-11-03"), config, "30day")
  high <- packet$facts[packet$facts$region == "AZNM" & packet$facts$tail == "high", ]
  testthat::expect_equal(high$eligible, 2L)
  testthat::expect_equal(high$count, 1L) # Exactly percentile 90 is outside the strict upper tail.
  testthat::expect_equal(high$percent, 50)
  testthat::expect_setequal(packet$members$uid, 1:2)
  a$publication_status[1] <- "HIDE_EXCLUDED"
  utils::write.csv(a, file.path(root, "data/diagnostics/acis-stations/publication-audit/product-readiness.csv"), row.names = FALSE)
  withheld <- synopsis_station_network_counts(root, as.Date("2026-11-03"), config, "30day")
  testthat::expect_equal(withheld$facts$status[withheld$facts$region == "AZNM"], rep("INSUFFICIENT_STATIONS", 2))
})

testthat::test_that("supplemental highlights compete within the monthly budget and retain evidence", {
  config <- synopsis_config(file.path(project_root, "config/conditions-synopsis.yml"))
  e <- synopsis_seasonal_fixture(synopsis_seasonal_cases()[1, ], config)
  e$regional_highlights <- list(normal_reference = "1991-2020", centered_window_days = 5,
    grids = data.frame(fact_id = "warm:AZNM", product = "maxt_extreme_warm_count_30day", region = "AZNM", metric = "area_extreme_days",
      value = 75, status = "AVAILABLE_CACHED", period_start = "2026-01-17", period_end = "2026-02-15", comparison_date = "",
      link = "pages/products/maxt_extreme_warm_count_30day.html"), stations = list(facts = data.frame()))
  candidates <- synopsis_regional_candidates(e)
  testthat::expect_length(candidates, 1L)
  testthat::expect_match(candidates[[1]]$text, "75% of Arizona and New Mexico had at least 6 warm days", fixed = TRUE)
  testthat::expect_match(candidates[[1]]$text, "not the historical rank")
  blocks <- synopsis_template_blocks(e, e$station_extremes, regional_candidates = candidates)
  monthly <- Filter(function(b) b$section == "Past 30 days", blocks)
  testthat::expect_length(monthly, 2L)
  testthat::expect_equal(monthly[[2]]$fact_ids, "warm:AZNM")
  testthat::expect_equal(synopsis_emphasis(monthly[[2]], e, data.frame(), synopsis_format_settings(config))[[1]]$tone, "warm")
  output <- tempfile(); on.exit(unlink(output, recursive = TRUE), add = TRUE)
  draft <- build_conditions_synopsis_draft(e, project_root, output)
  html <- xml2::read_html(draft$path)
  testthat::expect_false(any(grepl("Additional regional highlights", xml2::xml_text(xml2::xml_find_all(html, '//summary')))))
  testthat::expect_length(jsonlite::read_json(file.path(output, "draft-evidence.json"))$regional_candidates, 1L)
  selected_before <- draft$blocks
  draft <- build_conditions_synopsis_draft(e, project_root, output, show_review_candidates = TRUE)
  testthat::expect_identical(draft$blocks, selected_before)
  html <- xml2::read_html(draft$path)
  testthat::expect_true(any(grepl("Additional regional highlights", xml2::xml_text(xml2::xml_find_all(html, '//summary')))))
  testthat::expect_false(any(xml2::xml_has_attr(xml2::xml_find_all(html, '//details'), 'open')))
  testthat::expect_length(jsonlite::read_json(file.path(output, "draft-evidence.json"))$regional_candidates, 1L)
  e$regional_highlights$grids$value <- 19
  testthat::expect_length(synopsis_regional_candidates(e), 0L)
})

testthat::test_that("a third monthly bullet is distinct and respects the configured limit", {
  config <- synopsis_config(file.path(project_root, "config/conditions-synopsis.yml"))
  cases <- synopsis_seasonal_cases()
  e <- synopsis_seasonal_fixture(cases[cases$id == "competing-highlights", ], config)
  candidates <- synopsis_regional_candidates(e)
  monthly <- function(e) Filter(function(b) b$section == "Past 30 days",
    synopsis_template_blocks(e, e$station_extremes, regional_candidates = candidates))
  full <- monthly(e)
  testthat::expect_length(full, 3L)
  testthat::expect_equal(vapply(full[-1L], function(b) b$kind, character(1)), c("corroboration", "transition"))
  e$configuration$maximum_section_bullets <- 2
  testthat::expect_length(monthly(e), 2L)
})
