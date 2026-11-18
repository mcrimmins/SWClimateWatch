# Local-only refresh for the synopsis evidence pilot. Run from the project root.
# Downloads PRISM updates and station observations, calculates five derived
# grids, and optionally caches two SNODAS endpoints. No map rendering or S3 sync.
for (path in c("R/config.R", "R/acis-prism.R", "R/process-prism.R",
    "R/build-prism-climatology.R", "R/prism-percentile-rank.R",
    "R/build-current-prism-maps.R", "R/build-current-prism-precipitation-maps.R",
    "R/prism-accumulation-cache.R", "R/prism-water-year-cache.R",
    "R/build-current-prism-water-year-maps.R", "R/daily-update.R",
    "R/conditions-synopsis-evidence.R")) source(path)

refresh_conditions_synopsis_inputs <- function(today = Sys.Date(),
    update_stations = TRUE, update_snow = TRUE) {
  started <- proc.time()[["elapsed"]]
  directory <- file.path("data", "diagnostics", "conditions-synopsis")
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  # Any interrupted/partial refresh must trigger the normal full map rebuild later.
  swc_mark_map_rebuild_pending(file.path("data", "diagnostics", "map-rebuild-pending.txt"),
    paste0("synopsis-local-refresh-", format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")))
  plan <- plan_prism_download("update", today = today)
  # A laptop catching up after several weeks can exceed the normal daily cap.
  downloads <- sync_prism("update", today = today, max_requests = max(100L, nrow(plan) + 3L))
  processed <- process_prism_daily_plan(plan_prism_daily_processing())
  date <- latest_common_prism_date(c("maxt", "mint", "pcpn"))
  message("Calculating the five synopsis grids through ", date, "; maps are not rendered.")
  rain <- read_prism_best_daily_range("pcpn", seq(date - 29L, date, by = "day"))
  total <- prism_accumulation_from_raster(rain$raster, "pcpn", date)
  write_prism_processed_raster(total, prism_accumulation_output_path(30L, date))
  calculate_prism_accumulation_percentile_rank(total, accumulation_days = 30L,
    current_date = date, output_path = prism_accumulation_percentile_rank_output_path(30L, date), overwrite = TRUE)
  calculate_prism_rolling_temperature_departure(variable = "tmean", days = 30L, date = date)
  calculate_current_prism_water_year_products(date = date)

  notes <- character()
  if (update_stations) {
    # Use the PRISM endpoint for the comparison rather than mixing source dates.
    source("scripts/load-daily-publish.R")
    tryCatch(swc_daily_publish_update_stations(today = date + 1L), error = function(e) {
      notes <<- c(notes, paste("Station refresh:", conditionMessage(e)))
      message(tail(notes, 1L))
    })
  }
  if (update_snow && format(date, "%m") %in% c("10", "11", "12", "01", "02", "03", "04", "05")) {
    source("scripts/load-snodas-daily-update.R")
    for (stamp in as.character(c(date, date - 7L))) {
      target <- as.Date(stamp)
      checked <- synopsis_snow_inventory(".", target)
      if (identical(checked$status, "PAIRED_FILES_CHECKSUM_VERIFIED")) next
      # Do not fetch a previous-season September endpoint for an early October check.
      if (target < as.Date(sprintf("%d-10-01", as.integer(format(date, "%Y")) -
          as.integer(format(date, "%m-%d") < "10-01")))) next
      tryCatch({
        plan <- plan_snodas_download(target)
        download_snodas_plan(plan, max_requests = 1L)
        process_snodas_date(target, c("swe", "depth"), overwrite = TRUE)
        snodas_release_archive(target)
      }, error = function(e) {
        notes <<- c(notes, paste("Snow", target, ":", conditionMessage(e)))
        message(tail(notes, 1L))
      })
    }
  }
  evidence <- build_conditions_synopsis_evidence(snapshot_date = date, today = today)
  summary <- data.frame(snapshot_date = as.character(date),
    prism_downloaded = nrow(downloads), prism_processed = nrow(processed),
    regional_facts_available = sum(evidence$facts$status == "AVAILABLE_CACHED"),
    station_status = evidence$stations$status, snow_status = evidence$snow$status,
    elapsed_seconds = round(proc.time()[["elapsed"]] - started, 2),
    notes = paste(notes, collapse = " | "))
  utils::write.csv(summary, file.path(directory, "refresh-summary.csv"), row.names = FALSE)
  print(summary, row.names = FALSE)
  message("Local cache refresh complete. Full-map rebuild marker retained; no site render or upload.")
  invisible(list(summary = summary, evidence = evidence))
}

synopsis_refresh <- refresh_conditions_synopsis_inputs()
