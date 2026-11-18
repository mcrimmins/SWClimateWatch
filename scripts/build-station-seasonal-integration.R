# Local Station Conditions review, using existing summaries and cached daily records.
# Does not alter staged/public site files or the daily publication workflow.
source("R/config.R")
source("R/acis-station-inventory.R")
source("R/acis-station-current-prototype.R")
source("R/acis-station-cumulative-pilot.R")
source("R/acis-station-seasonal-pilot.R")

build_station_seasonal_integration <- function(
    source_dir="data/diagnostics/acis-stations/station-explorer-prototype",
    output_dir="data/diagnostics/station-seasonal-integration") {
  source_dir <- normalizePath(source_dir,mustWork=TRUE,winslash="/")
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  output_dir <- normalizePath(output_dir,mustWork=TRUE,winslash="/")
  if (identical(source_dir,output_dir)) stop("Use a separate local review directory.")
  required <- c("index.html","explorer.js","explorer.css","station-explorer-data.csv","station-details")
  if (!all(file.exists(file.path(source_dir,required)))) stop("Build the existing station explorer first.")
  rows <- read.csv(file.path(source_dir,"station-explorer-data.csv"),stringsAsFactors=FALSE)
  dates <- unique(rows$as_of)
  if (length(dates)!=1L || is.na(as.Date(dates))) stop("Invalid station explorer date.")
  # Copy only browser assets, summaries and detail records; omit old cumulative files.
  items <- list.files(source_dir,full.names=TRUE)
  items <- items[!basename(items) %in% c("cumulative","seasonal")]
  for (item in items) if (!file.copy(item,output_dir,recursive=TRUE,overwrite=TRUE))
    stop("Could not copy preview asset: ",item)
  js_path <- file.path(output_dir,"explorer.js")
  js <- paste(readLines(js_path,warn=FALSE,encoding="UTF-8"),collapse="\n")
  old <- "Water-year cumulative precipitation"
  if (!grepl("seasonal/index.html?",js,fixed=TRUE) &&
      (!grepl(old,js,fixed=TRUE) || !grepl("cumulative/index.html?",js,fixed=TRUE)))
    stop("Station detail integration point changed; review before replacing.")
  js <- gsub(old,"Seasonal precipitation and historical comparisons",js,fixed=TRUE)
  js <- gsub("October 1\u2013September 30; independent of the summary period above.",
    "Choose water year, cool season or monsoon below; independent of the summary period above.",js,fixed=TRUE)
  js <- gsub("Historical comparisons use complete water years.",
    "Rankings compare matching dates; full-season bars and cumulative curves use their labeled samples.",js,fixed=TRUE)
  js <- gsub("cumulative/index.html?","seasonal/index.html?",js,fixed=TRUE)
  writeLines(js,js_path,useBytes=TRUE)
  summary <- build_acis_station_seasonal_pilot(uids=unique(rows$uid),as_of=as.Date(dates),
    output_dir=file.path(output_dir,"seasonal"),
    result_cache_dir="data/diagnostics/station-seasonal-integration-cache")
  validate_station_seasonal_integration(output_dir)
  message("Combined Station Conditions preview ready: ",output_dir,
    "\nOpen a station detail panel to review its seasonal plots. No downloads or publication.")
  invisible(summary)
}

station_seasonal_integration <- build_station_seasonal_integration()
