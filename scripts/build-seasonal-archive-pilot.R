# Run from the project root in RStudio or with Rscript.
# Uses already processed PRISM grids; makes no RCC-ACIS requests.
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

check_swc_packages()
archive_pilot <- build_prism_archive_pilot_maps()
write_prism_archive_pilot_page(1998L, 2.1)
write_prism_archive_pilot_page(2011L, -1.4)
message("Built ", nrow(archive_pilot), " seasonal archive pilot maps and two pages.")
