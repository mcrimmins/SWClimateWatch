source("R/historic-monthly-pilot.R")
source("R/historic-monthly-archive.R")
source("R/historic-monthly-site-preview.R")
root <- "data/diagnostics/historic-monthly-archive-site"
if (!file.exists(file.path(root, "_site/index.html"))) stop("Build the monthly archive maps and pages first.")
print(validate_historic_monthly_site_preview(root, TRUE, expected_years = historic_monthly_archive_years()), row.names = FALSE)
page <- normalizePath(file.path(root, "_site/index.html"), winslash = "/", mustWork = TRUE)
if (interactive()) utils::browseURL(page)
message("Full existing-year local review: ", page)
