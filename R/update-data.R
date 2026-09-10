# Entry point for climate-data processing. Product modules will be added here.
source(file.path("R", "config.R"))
source(file.path("R", "acis-prism.R"))
source(file.path("R", "process-prism.R"))
source(file.path("R", "build-prism-climatology.R"))
source(file.path("R", "prism-percentile-rank.R"))
source(file.path("R", "prism-workflow.R"))
source(file.path("R", "build-overview-map.R"))

check_swc_packages()
initialize_swc_directories()

if (identical(tolower(Sys.getenv("SWC_UPDATE_PRISM", "false")), "true")) {
  sync_prism("update")
  processing_plan <- plan_prism_daily_processing()
  process_prism_daily_plan(processing_plan)
} else {
  message("PRISM update skipped; set SWC_UPDATE_PRISM=true to enable it.")
}

build_overview_map()

message("No automated climate products are configured yet.")
