source(file.path("R", "config.R"))
source(file.path("R", "acis-prism.R"))
source(file.path("R", "process-prism.R"))
source(file.path("R", "build-current-prism-maps.R"))
source(file.path("R", "map-product-site.R"))

products <- build_map_product_site(
  expected_data_dates = map_product_expected_data_dates()
)
message(
  "Generated ", sum(products$enabled), " enabled map-product pages from ",
  nrow(products), " configured products."
)
