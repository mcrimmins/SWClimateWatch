# Local cache-only preparation: no source downloads, map rendering or publishing.
for (path in c("R/config.R", "R/acis-prism.R", "R/process-prism.R", "R/build-prism-climatology.R",
    "R/prism-percentile-rank.R", "R/build-current-prism-maps.R", "R/build-current-prism-precipitation-maps.R", "R/prism-accumulation-cache.R",
    "R/conditions-synopsis-evidence.R")) source(path)

prepare_conditions_synopsis_highlight_grids <- function(date = synopsis_latest_date(".")) {
  date <- as.Date(date)
  for (variable in c("maxt", "mint")) calculate_prism_temperature_extreme_frequency(
    variable = variable, statistic = if (variable == "maxt") "p90" else "p10", days = 30L, date = date,
    comparison = if (variable == "maxt") "above" else "below", quiet = TRUE)
  ranks <- lapply(c(date, date - 14L), function(d) {
    d <- as.Date(d, origin = "1970-01-01")
    total <- calculate_prism_accumulation_for_date(accumulation_days = 30L, date = d, overwrite = TRUE)
    calculate_prism_accumulation_percentile_rank(total, accumulation_days = 30L, current_date = d,
      output_path = prism_accumulation_percentile_rank_output_path(30L, d), overwrite = TRUE, quiet = TRUE)
  })
  change <- prism_accumulation_percentile_change_raster(ranks[[1L]], ranks[[2L]], 30L, 14L, date)
  write_prism_processed_raster(change, prism_accumulation_percentile_change_output_path(30L, 14L, date))
  message("Prepared three synopsis highlight grids through ", date, ". No downloads, PNGs or publication.")
  invisible(date)
}
synopsis_highlight_date <- prepare_conditions_synopsis_highlight_grids()
