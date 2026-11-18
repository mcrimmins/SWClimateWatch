# Reconcile cached Snow BEFORE catalogs, synopsis and groups record its images.
# No source downloads or upload; normal Snow quality gates remain mandatory.
if (tolower(Sys.getenv("SWC_INTERACTIVE_SNOW", "true")) == "true") {
  source("scripts/load-snodas-current-site.R")
  source("R/interactive-map-snow-current.R")
  interactive_snow_prepared <- prepare_interactive_snow_current()
  message("Cached Snow preparation: ", interactive_snow_prepared$status)
}
