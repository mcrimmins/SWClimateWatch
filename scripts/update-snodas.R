# Local October-May SNODAS data and current-map update, separate from PRISM.
source("scripts/load-snodas-current-site.R")
# Clear last water year's public-page content before any network request.
# If the October directory is not available yet, the page still says WAITING.
update_snodas_current_site(data.frame(
  date = as.Date(character()), processed = logical()))
swc_snodas_update_result <- run_snodas_daily_update()
if (!is.null(swc_snodas_update_result$summary)) {
  print(swc_snodas_update_result$summary, row.names = FALSE)
}
swc_snodas_map_result <- update_snodas_current_site(
  swc_snodas_update_result$plan)
message("SNODAS current maps: ", swc_snodas_map_result$status, ".")
