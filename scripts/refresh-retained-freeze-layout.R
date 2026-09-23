# One-time layout migration for freeze-season maps retained from earlier dates.
# Uses existing processed grids; no RCC-ACIS requests or climate calculations.
source(file.path("R", "config.R"))
source(file.path("R", "acis-prism.R"))
source(file.path("R", "process-prism.R"))
source(file.path("R", "map-reference-layers.R"))
source(file.path("R", "map-product-scales.R"))
source(file.path("R", "map-southwest.R"))
source(file.path("R", "build-current-prism-maps.R"))
source(file.path("R", "prism-first-freeze.R"))
source(file.path("R", "prism-last-freeze.R"))
source(file.path("R", "prism-freeze-free-season.R"))
source(file.path("R", "map-product-site.R"))
source(file.path("R", "refresh-retained-freeze-maps.R"))

refreshed_retained_maps <- refresh_retained_prism_freeze_maps()
message("Refreshed ", nrow(refreshed_retained_maps), " retained freeze maps.")
build_map_product_site(
  expected_data_dates = map_product_expected_data_dates()
)
map_status <- read.csv(file.path("data", "diagnostics", "map-product-status.csv"))
print(table(map_status$validation_status))
