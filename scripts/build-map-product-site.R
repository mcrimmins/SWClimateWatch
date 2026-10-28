source(file.path("R", "config.R"))
source(file.path("R", "acis-prism.R"))
source(file.path("R", "process-prism.R"))
source(file.path("R", "build-current-prism-maps.R"))
source(file.path("R", "map-product-site.R"))

invisible(swc_read_dashboard_roni(refresh = TRUE))
invisible(swc_read_enso_status(refresh = TRUE))

products <- build_map_product_site(
  expected_data_dates = map_product_expected_data_dates()
)
message(
  "Generated ", sum(products$enabled), " enabled map-product pages from ",
  nrow(products), " configured products."
)
