source(file.path(project_root, "R/conditions-synopsis-evidence.R"))
source(file.path(project_root, "R/conditions-synopsis-template.R"))
source(file.path(project_root, "R/conditions-synopsis-seasonal-review.R"))

testthat::test_that("formatting follows supporting metrics and preserves plain prose", {
  config <- synopsis_config(file.path(project_root, "config/conditions-synopsis.yml"))
  settings <- synopsis_format_settings(config)
  cases <- synopsis_seasonal_cases()
  for (id in c("summer-heat", "winter-cold", "winter-quiet", "monsoon-localized", "opposing-states", "missing-support")) {
    e <- synopsis_seasonal_fixture(cases[cases$id == id, ], config)
    blocks <- synopsis_template_blocks(e, e$station_extremes)
    selected <- attr(blocks, "highlights")
    selected <- rbind(selected$week, selected$seasonal)
    spans <- lapply(blocks, synopsis_emphasis, evidence = e, stations = selected, settings = settings)
    testthat::expect_true(all(lengths(spans) <= 2L))
    for (i in seq_along(blocks)) {
      html <- synopsis_format_text(blocks[[i]]$text, spans[[i]])
      parsed <- xml2::read_html(paste0('<html><body><p>', html, '</p></body></html>'))
      testthat::expect_equal(xml2::xml_text(xml2::xml_find_first(parsed, '//p')), enc2utf8(blocks[[i]]$text))
    }
    tones <- unlist(lapply(spans, function(s) vapply(s, function(x) x$tone, character(1))))
    if (id == "opposing-states") {
      weekly <- which(vapply(blocks, function(b) b$section == "Past 7 days", logical(1)))
      testthat::expect_setequal(vapply(spans[[weekly[1L]]], function(x) x$tone, character(1)), c("warm", "cold"))
    }
    if (id == "winter-quiet") testthat::expect_true("warm" %in% tones)
    if (id == "monsoon-localized") testthat::expect_equal(spans[[1]][[1]]$tone, "wet")
  }
})

testthat::test_that("magnitude thresholds affect styling, not claims or selection", {
  config <- synopsis_config(file.path(project_root, "config/conditions-synopsis.yml"))
  cases <- synopsis_seasonal_cases()
  e <- synopsis_seasonal_fixture(cases[cases$id == "summer-heat", ], config)
  blocks <- synopsis_template_blocks(e, e$station_extremes)
  selected <- attr(blocks, "highlights")$week
  blocks <- Filter(function(b) b$section == "Past 7 days", blocks)
  normal <- synopsis_format_settings(config)
  spans <- synopsis_emphasis(blocks[[1]], e, selected, normal)
  testthat::expect_equal(spans[[1]]$tone, "warm")
  testthat::expect_false(spans[[1]]$strong)
  high <- normal; high$temperature_strong_f <- 4
  testthat::expect_true(synopsis_emphasis(blocks[[1]], e, selected, high)[[1]]$strong)
  disabled <- normal; disabled$enabled <- FALSE
  testthat::expect_length(synopsis_emphasis(blocks[[1]], e, selected, disabled), 0L)
  station_block <- Filter(function(b) selected$fact_id[1] %in% b$fact_ids, blocks)[[1]]
  testthat::expect_false(synopsis_emphasis(station_block, e, selected, normal)[[1]]$strong)
  selected$unusual_percentile <- 99
  testthat::expect_true(synopsis_emphasis(station_block, e, selected, normal)[[1]]$strong)
  selected$context_status <- "INSUFFICIENT_REFERENCE"
  testthat::expect_equal(synopsis_emphasis(station_block, e, selected, normal)[[1]]$tone, "neutral")
})

testthat::test_that("change direction and escaping remain correct", {
  config <- synopsis_config(file.path(project_root, "config/conditions-synopsis.yml"))
  e <- synopsis_seasonal_fixture(synopsis_seasonal_cases()[1, ], config)
  b <- list(text = "The dry area is 12.0 percentage points higher.", fact_ids = character(),
    changes = list(list(fact_id = "area_below_lower_percentile", difference = 12, units = "percentage points")))
  spans <- synopsis_emphasis(b, e, data.frame(), synopsis_format_settings(config))
  testthat::expect_equal(spans[[1]]$tone, "dry")
  b$changes[[1]]$difference <- -12; b$text <- sub("higher", "lower", b$text)
  testthat::expect_equal(synopsis_emphasis(b, e, data.frame(), synopsis_format_settings(config))[[1]]$tone, "wet")
  html <- synopsis_format_text('Station <A> & B received 2 inches.', list(list(text = "2 inches", tone = "wet", strong = TRUE)))
  testthat::expect_match(html, "&lt;A&gt; &amp; B")
  testthat::expect_match(html, '<strong class="signal-wet">2 inches</strong>', fixed = TRUE)
  config$formatting$colors$wet <- 'red;display:none'
  testthat::expect_error(synopsis_format_settings(config), "hex colors")
})
