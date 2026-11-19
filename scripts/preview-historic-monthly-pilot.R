root <- "data/diagnostics/historic-monthly-pilot"
if (!file.exists(file.path(root, "index.html"))) stop("Run scripts/build-historic-monthly-pilot.R first.")
source("R/historic-monthly-pilot.R")
preview_summary <- read.csv(file.path(root, "summary.csv"))
if (preview_summary$status != "READY" || preview_summary$products != historic_monthly_products_per_year() * preview_summary$years)
  stop("Rebuild the pilot first to include April-June spring and July-September monsoon.")
if (interactive()) utils::browseURL(normalizePath(file.path(root, "index.html"), winslash = "/", mustWork = TRUE))
message("Local Historic Years preview: ", normalizePath(file.path(root, "index.html"), winslash = "/"))
