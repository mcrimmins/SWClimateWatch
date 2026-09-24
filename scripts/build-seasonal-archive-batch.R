# Source from the project root in RStudio, then call run_prism_archive_batch().
# Historical maps use local processed PRISM grids; no RCC-ACIS download occurs.
for (script in c(
  "R/config.R",
  "R/acis-prism.R",
  "R/process-prism.R",
  "R/build-prism-climatology.R",
  "R/prism-percentile-rank.R",
  "R/map-reference-layers.R",
  "R/map-product-scales.R",
  "R/map-southwest.R",
  "R/build-current-prism-maps.R",
  "R/build-current-prism-precipitation-maps.R",
  "R/prism-wet-day-intensity.R",
  "R/build-current-prism-water-year-maps.R",
  "R/prism-seasonal-archive.R"
)) source(script)

run_prism_archive_batch <- function(years = 1982:1986, overwrite = FALSE) {
  check_swc_packages()
  result <- build_prism_archive_years(years, overwrite = overwrite)
  message(
    "Archive batch complete: ", length(unique(result$water_year)),
    " years, ", sum(result$map_refreshed), " maps rendered; ",
    nrow(result) - sum(result$map_refreshed), " maps reused."
  )
  result
}
