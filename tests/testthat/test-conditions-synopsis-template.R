source(file.path(project_root, "R/conditions-synopsis-evidence.R"))
synopsis_template_config <- function() synopsis_config(file.path(project_root, "config/conditions-synopsis.yml"))
source(file.path(project_root, "R/conditions-synopsis-template.R"))

synopsis_extreme_fixture <- function(root) {
  dir.create(file.path(root, "site/stations/station-details"), recursive = TRUE)
  dir.create(file.path(root, "data/diagnostics/acis-stations/publication-audit"), recursive = TRUE)
  days <- as.character(seq(as.Date("2026-10-01"), as.Date("2026-11-03"), by = "day"))
  daily <- data.frame(date = days, pcpn = c(rep(0, 31), 1, 2, 3), pcpn_status = "AVAILABLE",
    maxt = 70 + seq_along(days), maxt_status = "AVAILABLE", mint = 20 + seq_along(days), mint_status = "AVAILABLE")
  rows <- data.frame(uid = 1:2, name = c("Station A", "Station B"), state = c("AZ", "NM"),
    role = "fixed", as_of = "2026-11-03", cache_as_of = "2026-11-03", period = "30day", period_start = "2026-10-05",
    max_daily_pcpn = 3, max_daily_pcpn_date = "2026-11-03", max_3day_pcpn = 6,
    max_3day_pcpn_start_date = "2026-11-01", max_3day_pcpn_end_date = "2026-11-03",
    hottest_day = 104, hottest_day_date = "2026-11-03", coldest_night = 25, coldest_night_date = "2026-10-05",
    freeze_season_start = "2026-10-01", freeze_season_end = "2026-11-03",
    freeze_nights = 12, freeze_nights_normal = 8, freeze_nights_anomaly = 4, freeze_normal_years = 20)
  for (uid in 1:2) jsonlite::write_json(list(uid = uid, as_of = "2026-11-03", daily = daily),
    file.path(root, "site/stations/station-details", paste0(uid, ".json")), dataframe = "rows", auto_unbox = TRUE)
  audit <- expand.grid(uid = 1:2, metric = c("pcpn_value", "tmean_value"), stringsAsFactors = FALSE)
  audit$period <- "30day"; audit$page_date <- "2026-11-03"; audit$publication_status <- "DISPLAY"; audit$caution_codes <- ""
  utils::write.csv(rows, file.path(root, "site/stations/station-explorer-data.csv"), row.names = FALSE)
  utils::write.csv(audit, file.path(root, "data/diagnostics/acis-stations/publication-audit/product-readiness.csv"), row.names = FALSE)
  list(rows = rows, audit = audit, daily = daily)
}

testthat::test_that("station highlights verify observations and select complementary families and states", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  fixture <- synopsis_extreme_fixture(root)
  result <- synopsis_station_extremes(root, as.Date("2026-11-03"), synopsis_template_config())
  testthat::expect_equal(nrow(result$candidates), 10L)
  testthat::expect_equal(result$selected$metric, c("freeze_nights_anomaly", "max_daily_pcpn"))
  testthat::expect_equal(result$selected$state, c("AZ", "NM"))
  testthat::expect_equal(length(unique(result$selected$uid)), 2L)
  testthat::expect_match(synopsis_station_sentence(result$selected[1, ]), "4.0 more")
  testthat::expect_match(synopsis_station_sentence(result$selected[2, ]), "selected 30 days")
  config <- synopsis_template_config(); config$maximum_station_examples <- 0
  testthat::expect_equal(nrow(synopsis_station_extremes(root, as.Date("2026-11-03"), config)$selected), 0L)
})

testthat::test_that("flags, publication exclusion, inconsistent dates and unsupported normals are withheld", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  f <- synopsis_extreme_fixture(root)
  f$daily$pcpn_status[34] <- "FLAGGED"
  jsonlite::write_json(list(uid = 1L, as_of = "2026-11-03", daily = f$daily),
    file.path(root, "site/stations/station-details/1.json"), dataframe = "rows", auto_unbox = TRUE)
  f$audit$publication_status[f$audit$uid == 2 & f$audit$metric == "pcpn_value"] <- "HIDE_EXCLUDED"
  utils::write.csv(f$audit, file.path(root, "data/diagnostics/acis-stations/publication-audit/product-readiness.csv"), row.names = FALSE)
  f$rows$freeze_normal_years <- NA
  f$rows$coldest_night_date <- "2026-10-04"  # Outside the selected 30 days.
  utils::write.csv(f$rows, file.path(root, "site/stations/station-explorer-data.csv"), row.names = FALSE)
  result <- synopsis_station_extremes(root, as.Date("2026-11-03"), synopsis_template_config())
  testthat::expect_equal(unique(result$candidates$metric), "hottest_day")
  testthat::expect_equal(nrow(result$selected), 2L)
  f$rows$hottest_day <- 105  # Does not match usable daily values.
  utils::write.csv(f$rows, file.path(root, "site/stations/station-explorer-data.csv"), row.names = FALSE)
  testthat::expect_equal(nrow(synopsis_station_extremes(root, as.Date("2026-11-03"), synopsis_template_config())$selected), 0L)
})

testthat::test_that("template retains supporting IDs and does not invent missing comparisons", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  config <- synopsis_template_config()
  specs <- synopsis_grid_specs(root, "2026-11-03")
  facts <- synopsis_grid_facts(specs, config) # Explicitly unavailable fixtures.
  e <- list(snapshot_date = "2026-11-03", generated_utc = "test time", snapshot_age_days = 1,
    signature = "test", configuration = config, season = synopsis_season("2026-11-03", config),
    facts = facts, snow = list(active = TRUE), station_extremes = synopsis_station_extremes(root, as.Date("2026-11-03"), config))
  absent <- build_conditions_synopsis_draft(e, root, file.path(root, "output"))
  prose <- paste(vapply(absent$blocks, function(b) b$text, character(1)), collapse = " ")
  testthat::expect_match(prose, "unavailable")
  testthat::expect_match(paste(readLines(file.path(root, "output/synopsis.md")), collapse = " "), "comparison is not yet available")
  testthat::expect_false(grepl("recorded|averaged|highest|lowest", prose))
  idx <- which(facts$product == "pcpn_total_30day" & facts$region == "AZNM" & facts$metric == "mean")
  e$facts$value[idx] <- 1.25; e$facts$status[idx] <- "AVAILABLE_CACHED"
  present <- build_conditions_synopsis_draft(e, root, file.path(root, "output"))
  testthat::expect_true(any(vapply(present$blocks, function(b) e$facts$fact_id[idx] %in% b$fact_ids, logical(1))))
  testthat::expect_true(file.exists(present$path))
  testthat::expect_null(jsonlite::read_json(file.path(root, "output/draft-evidence.json"))$previous_published_snapshot)
})

testthat::test_that("highest-temperature ordering works when all maxima are below zero", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  f <- synopsis_extreme_fixture(root)
  for (uid in 1:2) {
    d <- f$daily
    d$maxt <- -30 + seq_len(nrow(d))/10 + (uid - 1L)*20
    d$mint <- d$maxt - 10
    f$rows$hottest_day[uid] <- max(d$maxt)
    jsonlite::write_json(list(uid = uid, as_of = "2026-11-03", daily = d),
      file.path(root, "site/stations/station-details", paste0(uid, ".json")), dataframe = "rows", auto_unbox = TRUE)
  }
  utils::write.csv(f$rows, file.path(root, "site/stations/station-explorer-data.csv"), row.names = FALSE)
  config <- synopsis_template_config(); config$maximum_station_examples <- 1
  config$station_metric_order$fall <- "hottest_day"
  testthat::expect_equal(synopsis_station_extremes(root, as.Date("2026-11-03"), config)$selected$uid, 2L)
})

synopsis_week_fixture <- function(root) {
  f <- synopsis_extreme_fixture(root)
  week <- f$rows; week$period <- "7day"; week$period_start <- "2026-10-28"
  week$coldest_night <- 48; week$coldest_night_date <- "2026-10-28"
  audit <- f$audit; audit$period <- "7day"
  utils::write.csv(rbind(f$rows, week), file.path(root, "site/stations/station-explorer-data.csv"), row.names = FALSE)
  utils::write.csv(rbind(f$audit, audit), file.path(root, "data/diagnostics/acis-stations/publication-audit/product-readiness.csv"), row.names = FALSE)
  packet <- synopsis_station_extremes(root, as.Date("2026-11-03"), synopsis_template_config(), period_days = 7L)
  # Explicit synthetic historical support for selection-only tests.
  packet$candidates$context_status <- "SUPPORTED"
  packet$candidates$unusual_percentile <- 97.5
  packet$candidates$historical_n <- 40
  packet$candidates$historical_rank <- 1
  packet$candidates$historical_ties <- 3
  packet$candidates$historical_first_year <- 1980
  packet$candidates$historical_last_year <- 2025
  packet$candidates$rank_direction <- ifelse(packet$candidates$metric == "coldest_night", "lowest", "highest")
  packet$candidates$peak_anomaly <- NA_real_
  packet$candidates$context_normal_years <- 20
  packet
}

testthat::test_that("weekly extremes use seven-day summaries and never borrow an older thirty-day extreme", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  week <- synopsis_week_fixture(root)
  testthat::expect_equal(nrow(week$candidates), 8L)
  testthat::expect_true(all(week$candidates$period_start == "2026-10-28"))
  testthat::expect_true(all(week$candidates$event_start >= "2026-10-28"))
  testthat::expect_false(any(week$candidates$metric == "freeze_nights_anomaly"))
  cold <- week$candidates[week$candidates$metric == "coldest_night", ]
  testthat::expect_true(all(cold$value == 48)) # Thirty-day minimum is 25.
  testthat::expect_match(synopsis_station_sentence(cold[1, ]), "matching 7-day periods")
})

testthat::test_that("event novelty suppresses repeats while retaining a separate seasonal context", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  week <- synopsis_week_fixture(root)
  e <- list(configuration = synopsis_template_config(), station_week = week,
    station_extremes = list(candidates = data.frame()), season = synopsis_season("2026-11-03", synopsis_template_config()))
  comparison <- list(week_candidates = week$candidates)
  testthat::expect_equal(nrow(synopsis_select_highlights(e, comparison)$week), 0L)
  i <- which(e$station_week$candidates$uid == 2 & e$station_week$candidates$metric == "max_daily_pcpn")
  e$station_week$candidates$event_start[i] <- e$station_week$candidates$event_end[i] <- "2026-11-04"
  new <- synopsis_select_highlights(e, comparison)$week
  testthat::expect_equal(nrow(new), 1L)
  testthat::expect_equal(new$uid, 2L)
  testthat::expect_equal(new$event_end, "2026-11-04")
  e$station_extremes <- synopsis_station_extremes(root, as.Date("2026-11-03"), e$configuration)
  selected <- synopsis_select_highlights(e)
  testthat::expect_equal(nrow(selected$week) + nrow(selected$seasonal), 2L)
  testthat::expect_false(any(selected$week$uid %in% selected$seasonal$uid))
})

synopsis_bullet_fixture <- function(root) {
  config <- synopsis_template_config()
  facts <- synopsis_grid_facts(synopsis_grid_specs(root, "2026-11-03"), config)
  facts$status <- "AVAILABLE_CACHED"; facts$value <- 1
  facts$value[facts$metric == "area_above_upper_percentile"] <- 30
  facts$value[facts$metric == "area_below_lower_percentile"] <- 20
  recent <- facts[facts$product %in% c("pcpn_total_30day", "tmean_departure_30day"), ]
  recent$product <- sub("30day", "07day", recent$product)
  recent$fact_id <- sub("30day", "07day", recent$fact_id); recent$period_start <- "2026-10-28"
  list(snapshot_date = "2026-11-03", generated_utc = "fixture", snapshot_age_days = 1L,
    configuration = config, signature = "fixture", season = synopsis_season("2026-11-03", config),
    facts = facts, recent = list(facts = recent, days = data.frame()), snow = list(active = TRUE),
    station_extremes = list(candidates = data.frame()), station_week = list(candidates = data.frame()))
}

testthat::test_that("preview comparisons remain stable on reruns and reset safely at rollover", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  e <- synopsis_bullet_fixture(root)
  first <- synopsis_comparison_context(e, NULL)
  testthat::expect_null(first$previous)
  next_day <- e; next_day$snapshot_date <- "2026-11-04"
  next_comparison <- synopsis_comparison_context(next_day, first$state)
  testthat::expect_equal(next_comparison$previous$snapshot_date, "2026-11-03")
  same_day <- synopsis_comparison_context(next_day, next_comparison$state)
  testthat::expect_equal(same_day$previous$snapshot_date, "2026-11-03")
  rewind <- synopsis_comparison_context(e, same_day$state)
  testthat::expect_false(rewind$write)
  rollover <- next_day; rollover$snapshot_date <- "2027-10-01"
  testthat::expect_null(synopsis_comparison_context(rollover, same_day$state)$previous)
  changed <- next_day; changed$configuration$lower_percentile <- 25
  testthat::expect_null(synopsis_comparison_context(changed, same_day$state)$previous)
})

testthat::test_that("bullets keep three period sections and support material changes with prior facts", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  e <- synopsis_bullet_fixture(root)
  previous <- synopsis_comparison_context(e, NULL)$state$latest
  previous$snapshot_date <- "2026-11-02"
  low <- e$facts$product == "pcpn_percentile_30day" & e$facts$region == "AZNM" & e$facts$metric == "area_below_lower_percentile"
  high <- e$facts$product == "pcpn_percentile_30day" & e$facts$region == "AZNM" & e$facts$metric == "area_above_upper_percentile"
  e$facts$value[high] <- previous$facts$value[high] <- 60
  e$facts$value[low] <- 35 # Lower tail changed more than the upper tail.
  blocks <- synopsis_template_blocks(e, e$station_extremes, previous)
  prose <- paste(vapply(blocks, function(b) b$text, character(1)), collapse = " ")
  testthat::expect_match(prose, "area below percentile 33 is 15.0 percentage points higher")
  changes <- unlist(lapply(blocks, function(b) b$changes), recursive = FALSE)
  testthat::expect_equal(changes[[1]]$previous_value, 20)
  draft <- build_conditions_synopsis_draft(e, root, file.path(root, "output"), track_preview = TRUE)
  testthat::expect_setequal(unique(vapply(draft$blocks, function(b) b$section, character(1))), c("Past 7 days", "Past 30 days", "Water year so far"))
  html <- paste(readLines(draft$path), collapse = " ")
  testthat::expect_match(html, "<ul>")
  testthat::expect_false(grepl("Station highlights</h2>|Changes since previous update</h2>", html))
  state <- readRDS(file.path(root, "output/preview-state.rds"))
  bad <- e; bad$snapshot_date <- "2026-11-04"; bad$facts$status <- "UNAVAILABLE"
  build_conditions_synopsis_draft(bad, root, file.path(root, "output"), track_preview = TRUE)
  testthat::expect_identical(readRDS(file.path(root, "output/preview-state.rds")), state)
})

testthat::test_that("new broad rainfall is preferred to an older larger day and quiet indicators are stated precisely", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  e <- synopsis_bullet_fixture(root)
  previous <- synopsis_comparison_context(e, NULL)$state$latest
  previous$snapshot_date <- "2026-11-02"
  e$recent$days <- data.frame(fact_id = c("older-day", "newer-day"), date = c("2026-11-01", "2026-11-03"),
    region = "AZNM", mean_inches = c(2, .2), rain_area_percent = c(90, 40), rain_threshold_inches = .1,
    status = "AVAILABLE_CACHED", link = "pages/daily-explorer.html")
  blocks <- synopsis_template_blocks(e, e$station_extremes, previous)
  weekly <- Filter(function(b) b$section == "Past 7 days", blocks)[[1]]
  testthat::expect_match(weekly$text, "newly available days since Nov 2, 2026")
  testthat::expect_match(weekly$text, "0.20 inches on November 3")
  testthat::expect_true("newer-day" %in% weekly$fact_ids)
  e$recent$days <- e$recent$days[2, ]
  e$recent$days$mean_inches <- e$recent$days$rain_area_percent <- 0
  quiet <- synopsis_template_blocks(e, e$station_extremes, previous)
  testthat::expect_true(any(vapply(quiet, function(b) grepl("indicators changed little", b$text), logical(1))))
  e$recent$days$status <- "LOW_COVERAGE"
  incomplete <- synopsis_template_blocks(e, e$station_extremes, previous)
  testthat::expect_false(any(vapply(incomplete, function(b) grepl("indicators changed little", b$text), logical(1))))
})

testthat::test_that("quiet weeks can emphasize a supported dry spell without exceeding section limits", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  e <- synopsis_bullet_fixture(root)
  e$recent$facts$value[e$recent$facts$product == "pcpn_total_07day"] <- .01
  e$recent$facts$value[e$recent$facts$product == "tmean_departure_07day"] <- 0
  e$station_extremes$candidates <- data.frame(fact_id = "dry-fixture", uid = 3L, window_days = 30L,
    name = "Dry station", state = "NM", metric = "longest_dry_spell", family = "dryness", value = 20,
    event_start = "2026-10-12", event_end = "2026-10-31", period_end = "2026-11-03",
    context_status = "SUPPORTED", unusual_percentile = 97.5, historical_n = 40, historical_rank = 1,
    historical_ties = 3, historical_first_year = 1980, historical_last_year = 2025,
    rank_direction = "highest", peak_anomaly = NA_real_, context_normal_years = 20,
    caution_codes = "", link = "pages/station-conditions.html")
  highlights <- synopsis_select_highlights(e)
  testthat::expect_equal(highlights$profile$mode, "longer_term")
  testthat::expect_equal(highlights$seasonal$metric, "longest_dry_spell")
  blocks <- synopsis_template_blocks(e, e$station_extremes)
  dry <- Filter(function(b) "dry-fixture" %in% b$fact_ids, blocks)[[1]]
  testthat::expect_equal(dry$section, "Past 30 days")
  testthat::expect_match(dry$text, "longest such run within the past 30 days")
  testthat::expect_lte(sum(vapply(blocks, function(b) b$section == "Past 30 days", logical(1))), 2L)
  testthat::expect_false(grepl("ongoing|all-time|flood", dry$text))
})
