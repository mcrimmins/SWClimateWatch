root <- "data/diagnostics/historic-monthly-site-preview/_site"
if (!file.exists(file.path(root, "index.html"))) stop("Run scripts/build-historic-monthly-site-preview.R first.")
source("R/historic-monthly-pilot.R")
source("R/historic-monthly-site-preview.R")
print(validate_historic_monthly_site_preview(dirname(root), rendered = TRUE), row.names = FALSE)
if (interactive()) utils::browseURL(normalizePath(file.path(root, "index.html"), winslash = "/", mustWork = TRUE))
message("Historic Years local page review: ", normalizePath(file.path(root, "index.html"), winslash = "/"))
