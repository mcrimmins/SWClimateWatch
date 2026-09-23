# Dispatch map builders from the enabled settings in the product catalog.

enabled_map_product_values <- function(products, ids, values) {
  ids <- as.character(ids)
  if (length(ids) != length(values)) {
    stop("Map-product IDs and values must have the same length.", call. = FALSE)
  }
  rows <- match(ids, products$id)
  if (anyNA(rows)) {
    stop("Unknown map-product ID: ", ids[which(is.na(rows))[[1L]]], call. = FALSE)
  }
  values[products$enabled[rows]]
}

plan_enabled_prism_map_updates <- function(
    products = read_map_product_config()) {
  select <- function(ids, values) enabled_map_product_values(products, ids, values)
  plan <- list(
    temperature_values = select(
      c("maxt_value", "mint_value", "tmean_value"),
      c("maxt", "mint", "tmean")
    ),
    temperature_daily_departures = select(
      c("maxt_departure_daily", "mint_departure_daily", "tmean_departure_daily"),
      c("maxt", "mint", "tmean")
    ),
    temperature_30day_departures = select(
      c("maxt_departure_30day", "mint_departure_30day", "tmean_departure_30day"),
      c("maxt", "mint", "tmean")
    ),
    temperature_rolling_percentiles = select(
      c("tmean_percentile_07day", "tmean_percentile_30day", "tmean_percentile_90day"),
      c(7L, 30L, 90L)
    ),
    extreme_warm = select("maxt_extreme_warm_count_30day", TRUE),
    extreme_cold = select("mint_extreme_cold_count_30day", TRUE),
    freeze_count = select("mint_freeze_count_30day", TRUE),
    freeze_anomaly = select("mint_freeze_anomaly_30day", TRUE),
    first_freeze = select(
      c("mint_first_freeze_date", "mint_first_freeze_departure"),
      c("observed-day", "departure")
    ),
    last_freeze = select(
      c("mint_last_freeze_date", "mint_last_freeze_departure"),
      c("observed-day", "departure")
    ),
    freeze_free = select(
      c("mint_freeze_free_length", "mint_freeze_free_departure"),
      c("length", "departure")
    ),
    temperature_daily_percentiles = select(
      c("maxt_percentile_daily", "mint_percentile_daily", "tmean_percentile_daily"),
      c("maxt", "mint", "tmean")
    ),
    precipitation_totals = select(
      c("pcpn_total_01day", "pcpn_total_07day", "pcpn_total_30day", "pcpn_total_90day"),
      c(1L, 7L, 30L, 90L)
    ),
    precipitation_percentiles = select(
      c("pcpn_percentile_07day", "pcpn_percentile_30day", "pcpn_percentile_90day"),
      c(7L, 30L, 90L)
    ),
    precipitation_change = select("pcpn_percentile_change_30day_14day", TRUE),
    precipitation_percent_normal = select(
      c("pcpn_percent_normal_30day", "pcpn_percent_normal_90day"),
      c(30L, 90L)
    ),
    water_year = select(
      c("pcpn_water_year_total", "pcpn_water_year_percent_normal", "pcpn_water_year_percentile"),
      c("total", "percent-normal", "percentile-rank")
    ),
    dry_spell = select(
      c("pcpn_current_dry_spell_length", "pcpn_current_dry_spell_percentile"),
      c("length", "percentile-rank")
    ),
    longest_dry_spell = select(
      c("pcpn_longest_dry_spell_180day", "pcpn_longest_dry_spell_percentile_180day"),
      c("length", "percentile-rank")
    ),
    wet_day_count = select(
      c("pcpn_wet_day_count_90day", "pcpn_wet_day_count_percentile_90day"),
      c("count", "percentile-rank")
    ),
    wet_day_intensity = select(
      c("pcpn_wet_day_intensity_90day", "pcpn_wet_day_intensity_percentile_90day"),
      c("intensity", "percentile-rank")
    ),
    very_wet_contribution = select(
      c("pcpn_very_wet_contribution_90day", "pcpn_very_wet_contribution_percentile_90day"),
      c("contribution", "percentile-rank")
    ),
    water_year_maximum = select(
      c("pcpn_water_year_max_03day", "pcpn_water_year_max_percentile_03day"),
      c("maximum", "percentile-rank")
    ),
    water_year_concentration = select("pcpn_water_year_concentration_03day", TRUE)
  )
  plan$precipitation_accumulations <- sort(unique(c(
    plan$precipitation_totals,
    plan$precipitation_percentiles,
    plan$precipitation_percent_normal,
    if (length(plan$precipitation_change) > 0L) 30L
  )))
  plan$water_year_work <- if (
    length(plan$water_year) > 0L || length(plan$water_year_concentration) > 0L
  ) TRUE else logical()
  plan$water_year_maximum_work <- if (
    length(plan$water_year_maximum) > 0L || length(plan$water_year_concentration) > 0L
  ) TRUE else logical()
  plan
}

update_enabled_prism_maps <- function(
    products = read_map_product_config(),
    overwrite = TRUE,
    quiet = FALSE,
    timing_path = file.path("data", "diagnostics", "map-update-timings.csv")) {
  old_options <- options(
    swc.map.product.scale_modes = stats::setNames(products$scale, products$id)
  )
  on.exit(options(old_options), add = TRUE)
  plan <- plan_enabled_prism_map_updates(products)
  results <- list()
  run_id <- paste0(format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"), "-", Sys.getpid())
  expected_dates <- tryCatch(
    map_product_expected_data_dates(products),
    error = function(error) NULL
  )
  timing_rows <- list()
  record_timing <- function(name, status, started_utc, elapsed_seconds, output_count) {
    row <- data.frame(
      run_id = run_id,
      group = name,
      status = status,
      started_utc = format(started_utc, tz = "UTC", usetz = TRUE),
      elapsed_seconds = round(elapsed_seconds, 3),
      output_count = as.integer(output_count),
      temperature_date = if (!is.null(expected_dates) && "Temperature" %in% names(expected_dates)) {
        expected_dates[["Temperature"]]
      } else {
        NA_character_
      },
      precipitation_date = if (!is.null(expected_dates) && "Precipitation" %in% names(expected_dates)) {
        expected_dates[["Precipitation"]]
      } else {
        NA_character_
      },
      stringsAsFactors = FALSE
    )
    timing_rows[[length(timing_rows) + 1L]] <<- row
    invisible(row)
  }
  run <- function(name, fun, args = list()) {
    if (length(plan[[name]]) == 0L) {
      if (!quiet) message("Skipping disabled map group: ", name, ".")
      record_timing(name, "SKIPPED", Sys.time(), 0, 0L)
      return(invisible(NULL))
    }
    started_utc <- Sys.time()
    started <- proc.time()[["elapsed"]]
    common_args <- list(overwrite = overwrite, quiet = quiet)
    common_args <- common_args[names(common_args) %in% names(formals(fun))]
    value <- tryCatch(
      do.call(fun, c(args, common_args)),
      error = function(error) {
        elapsed <- proc.time()[["elapsed"]] - started
        record_timing(name, "FAILED", started_utc, elapsed, 0L)
        stop(error)
      }
    )
    results[[name]] <<- value
    elapsed <- proc.time()[["elapsed"]] - started
    output_count <- if (is.data.frame(value)) nrow(value) else length(value)
    record_timing(name, "COMPLETE", started_utc, elapsed, output_count)
    if (!quiet) {
      message(
        "Map group `", name, "` completed in ",
        format_map_update_elapsed(elapsed), "."
      )
    }
  }

  run("temperature_values", build_current_temperature_value_maps,
      list(variables = plan$temperature_values))
  run("temperature_daily_departures", build_current_temperature_departure_maps,
      list(variables = plan$temperature_daily_departures))
  run("temperature_30day_departures", build_current_temperature_rolling_departure_maps,
      list(variables = plan$temperature_30day_departures, days = 30L))
  run("temperature_rolling_percentiles", build_current_prism_rolling_temperature_percentile_maps,
      list(days = plan$temperature_rolling_percentiles))
  run("extreme_warm", build_current_extreme_warm_day_frequency_map)
  run("extreme_cold", build_current_extreme_cold_night_frequency_map)
  run("freeze_count", build_current_freeze_day_count_map)
  run("freeze_anomaly", build_current_freeze_day_anomaly_map)
  run("first_freeze", build_current_prism_first_freeze_maps,
      list(map_products = plan$first_freeze))
  run("last_freeze", build_current_prism_last_freeze_maps,
      list(map_products = plan$last_freeze))
  run("freeze_free", build_current_prism_freeze_free_maps,
      list(map_products = plan$freeze_free))
  results$retained_freeze_layout <- refresh_retained_prism_freeze_maps(
    products = products, quiet = quiet
  )
  run("temperature_daily_percentiles", build_current_temperature_percentile_maps,
      list(variables = plan$temperature_daily_percentiles))
  run("precipitation_accumulations", build_current_precipitation_maps,
      list(
        windows = plan$precipitation_accumulations,
        map_windows = plan$precipitation_totals
      ))
  run("precipitation_percentiles", build_current_precipitation_percentile_maps,
      list(windows = plan$precipitation_percentiles))
  run("precipitation_change", build_current_precipitation_percentile_change_map)
  run("precipitation_percent_normal", build_current_precipitation_percent_normal_maps,
      list(windows = plan$precipitation_percent_normal))
  run("water_year_work", build_current_prism_water_year_maps,
      list(map_products = plan$water_year))
  run("dry_spell", build_current_prism_dry_spell_maps,
      list(map_products = plan$dry_spell))
  run("longest_dry_spell", build_current_prism_longest_dry_spell_maps,
      list(map_products = plan$longest_dry_spell))
  run("wet_day_count", build_current_prism_wet_day_count_maps,
      list(map_products = plan$wet_day_count))
  run("wet_day_intensity", build_current_prism_wet_day_intensity_maps,
      list(map_products = plan$wet_day_intensity))
  run("very_wet_contribution", build_current_prism_very_wet_contribution_maps,
      list(map_products = plan$very_wet_contribution))
  run("water_year_maximum_work", build_current_prism_water_year_maximum_maps,
      list(map_products = plan$water_year_maximum))
  run("water_year_concentration", build_current_prism_water_year_concentration_map)
  timings <- do.call(rbind, timing_rows)
  if (!is.null(timing_path)) {
    dir.create(dirname(timing_path), recursive = TRUE, showWarnings = FALSE)
    append <- file.exists(timing_path) && file.info(timing_path)$size > 0
    utils::write.table(
      timings,
      timing_path,
      sep = ",",
      row.names = FALSE,
      col.names = !append,
      append = append,
      qmethod = "double"
    )
  }
  attr(results, "timings") <- timings
  invisible(results)
}

format_map_update_elapsed <- function(seconds) {
  seconds <- max(0, as.numeric(seconds))
  if (seconds >= 3600) {
    return(sprintf("%dh %02dm %02ds", floor(seconds / 3600), floor((seconds %% 3600) / 60), round(seconds %% 60)))
  }
  if (seconds >= 60) {
    return(sprintf("%dm %02ds", floor(seconds / 60), round(seconds %% 60)))
  }
  sprintf("%.1fs", seconds)
}
