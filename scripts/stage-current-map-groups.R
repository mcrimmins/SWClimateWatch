# Stage existing Current Maps in the reviewed grouping layout; no downloads.
source("R/config.R")
source("R/acis-prism.R")
source("R/process-prism.R")
source("R/build-current-prism-maps.R")
source("R/map-product-site.R")
current_group_manifest <- stage_current_map_groups(expected_data_dates=map_product_expected_data_dates())
update_map_product_navigation(read_map_product_config())
validate_current_map_groups()
