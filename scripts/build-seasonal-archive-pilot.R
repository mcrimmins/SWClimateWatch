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
roni <- read_prism_archive_roni()
for (year in c(1998L, 2011L)) {
  write_prism_archive_page(year, roni$djf_roni[roni$water_year == year])
}
write_prism_archive_navigation()
message("Built ", nrow(archive_pilot), " seasonal archive pilot maps and two pages.")
