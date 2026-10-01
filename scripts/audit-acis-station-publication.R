# Local station publication screen. No ACIS requests or public-site publishing.
source(file.path("R", "config.R"))
source(file.path("R", "acis-station-inventory.R"))
source(file.path("R", "map-southwest.R"))
source(file.path("R", "acis-station-explorer-prototype.R"))
source(file.path("R", "acis-station-publication-audit.R"))

explorer_dir <- file.path(swc_acis_station_dir, "station-explorer-prototype")
daily_dir <- file.path(swc_acis_station_dir, "reference-network", "daily-audit")
publication_dir <- file.path(swc_acis_station_dir, "publication-audit")
input_paths <- c(explorer = file.path(explorer_dir, "station-explorer-data.csv"),
                 quality = file.path(daily_dir, "summary.csv"),
                 checks = file.path(daily_dir, "checks.csv"))
missing <- input_paths[!file.exists(input_paths)]
if (length(missing))
  stop("Publication audit needs existing station inputs: ",
       paste(missing, collapse = ", "), call. = FALSE)
read_input <- function(path) read.csv(path, stringsAsFactors = FALSE)
review_path <- file.path("config", "acis-station-publication-reviews.csv")
reviews <- if (file.exists(review_path)) read_input(review_path) else NULL
station_rows <- read_input(input_paths[["explorer"]])
swc_station_publication_audit <- audit_acis_station_publication(
  station_rows, read_input(input_paths[["quality"]]),
  read_input(input_paths[["checks"]]), reviews)
dir.create(publication_dir, recursive = TRUE, showWarnings = FALSE)
paths <- c(products = file.path(publication_dir, "product-readiness.csv"),
           quality_context = file.path(publication_dir, "station-quality-context.csv"),
           summary = file.path(publication_dir, "readiness-summary.csv"),
           threshold_sensitivity = file.path(publication_dir, "threshold-sensitivity.csv"))
for (name in names(paths))
  write.csv(swc_station_publication_audit[[name]], paths[[name]],
            row.names = FALSE, na = "")
preview_page <- write_acis_station_explorer_prototype(
  station_rows, output_dir = explorer_dir,
  publication_products = swc_station_publication_audit$products)
message(sprintf("Station publication audit: %d stations, %d product rows; page date %s.",
                length(unique(swc_station_publication_audit$products$uid)),
                nrow(swc_station_publication_audit$products),
                unique(swc_station_publication_audit$products$page_date)))
message("Quality context: ", paths[["quality_context"]])
message("Screened local preview: ", preview_page)
