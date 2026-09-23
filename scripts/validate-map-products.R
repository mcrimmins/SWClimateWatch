source(file.path("R", "config.R"))
source(file.path("R", "acis-prism.R"))
source(file.path("R", "process-prism.R"))
source(file.path("R", "build-current-prism-maps.R"))
source(file.path("R", "map-product-site.R"))

arguments <- commandArgs(trailingOnly = TRUE)
unknown <- setdiff(arguments, "--require-rendered")
if (length(unknown) > 0L) {
  stop("Unknown argument(s): ", paste(unknown, collapse = ", "), call. = FALSE)
}

validation <- validate_map_product_publication(
  expected_data_dates = map_product_expected_data_dates(),
  require_rendered = "--require-rendered" %in% arguments
)
print(validation)
