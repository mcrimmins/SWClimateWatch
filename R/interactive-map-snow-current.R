# Bind the automatic viewer to the verified Current Snow release.
interactive_snow_current_release <- function(site_dir = "site",
    publication_path = "data/diagnostics/snodas-current-site/publication.csv",
    .signature = snodas_current_site_source_signature) {
  row <- snodas_current_site_manifest(publication_path)
  if (is.null(row)) stop("Current Snow publication report missing or invalid; run the normal snow updater first.")
  date <- as.Date(row$date[[1L]])
  signature <- .signature(date)
  maps <- file.path(site_dir, "maps/generated/snodas/current")
  paths <- setNames(file.path(maps, c("swe-observed.png", "swe-departure.png", "swe-percent-median.png")),
    c("observed", "departure", "percent"))
  if (!snodas_current_site_is_current(row$water_year[[1L]], date, signature, paths,
      file.path(site_dir, "pages/current-snow.qmd"), publication_path))
    stop("Snow cache or images differ from the verified Current Snow release. Run the normal snow updater before staging the viewer.")
  image_names <- c("swe-observed.png", "swe-departure.png", "swe-percent-median.png",
    if (isTRUE(row$change_available[[1L]])) "swe-change-7day.png")
  list(date = as.character(date), source_signature = signature,
    publication_md5 = unname(tools::md5sum(publication_path)),
    change_available = isTRUE(row$change_available[[1L]]),
    images = lapply(image_names, function(name) list(file = paste0("maps/generated/snodas/current/", name),
      md5 = unname(tools::md5sum(file.path(maps, name))))))
}

prepare_interactive_snow_current <- function(site_dir = "site", today = Sys.Date(),
    publication_path = "data/diagnostics/snodas-current-site/publication.csv",
    .get = interactive_snow_current_release, .update = update_snodas_current_site,
    .season = snodas_update_season) {
  row <- snodas_current_site_manifest(publication_path)
  season <- .season(today)
  if (is.null(row) || (!is.null(season) && row$water_year[[1L]] != season$water_year))
    return(list(status = "WAITING", release = NULL))
  release <- tryCatch(.get(site_dir, publication_path), error = function(e) e)
  if (inherits(release, "error")) {
    # A release checkout can reset the generated page; code/input revisions can
    # invalidate its signature. Rebuild the SAME verified date, without fetches.
    date <- as.Date(row$date[[1L]])
    message("Reconciling cached Current Snow release for ", date, ": ", conditionMessage(release))
    updated <- .update(plan = data.frame(date = date, processed = TRUE), today = date,
      site_map_dir = file.path(site_dir, "maps/generated/snodas/current"),
      page_path = file.path(site_dir, "pages/current-snow.qmd"), diagnostics_dir = dirname(publication_path))
    if (!updated$status %in% c("STAGED", "UNCHANGED"))
      stop("Cached Current Snow reconciliation did not pass its quality gate: ", updated$status)
    release <- .get(site_dir, publication_path)
  }
  list(status = "READY", release = release)
}

interactive_snow_refresh_signature <- function(release, base_dir) {
  paths <- c(file.path(base_dir, "manifest.json"), "R/interactive-map-snow-current.R",
    "R/interactive-map-snow-pilot.R", "R/interactive-map-site.R",
    file.path("scripts/interactive-map-assets", c("index.html", "pilot.js", "pilot.css")))
  if (any(!file.exists(paths))) stop("Snow viewer refresh inputs are incomplete.")
  digest::digest(list(policy = "snow-auto-v1", release = release,
    hashes = unname(tools::md5sum(paths))), algo = "sha256")
}

stage_interactive_snow_current <- function(site_dir = "site",
    base_dir = "data/diagnostics/interactive-map-pilot",
    output_dir = "data/diagnostics/interactive-map-snow-current", release = NULL,
    .get = interactive_snow_current_release, .build = build_interactive_map_snow_pilot,
    .stage = stage_interactive_map_site, .validate = validate_interactive_map_site,
    .signature = interactive_snow_refresh_signature) {
  started <- proc.time()[["elapsed"]]
  if (is.null(release)) release <- .get(site_dir)
  signature <- .signature(release, base_dir)
  state_path <- file.path(output_dir, "refresh-state.rds")
  state <- if (file.exists(state_path)) tryCatch(readRDS(state_path), error = function(e) NULL) else NULL
  current_site <- function() {
    .validate(site_dir)
    manifest <- jsonlite::read_json(file.path(site_dir, "interactive-maps/manifest.json"))
    identical(manifest$snow_mode, "verified_current") && identical(manifest$snow_release, release)
  }
  reused <- identical(state$signature, signature)
  if (reused && !isTRUE(tryCatch(current_site(), error = function(e) FALSE))) {
    cache_manifest <- file.path(output_dir, "manifest.json")
    reused <- file.exists(cache_manifest) && identical(unname(tools::md5sum(cache_manifest)), state$manifest_md5) &&
      isTRUE(tryCatch({.stage(output_dir, site_dir); TRUE}, error = function(e) FALSE))
  }
  if (!reused) {
    built <- .build(output_dir = output_dir, base_dir = base_dir, published_only = TRUE)
    layer <- built$manifest$layers[[paste0("snow-", release$date)]]
    if (!identical(layer$source_signature, release$source_signature) ||
        !identical(layer$change_available, release$change_available)) stop("Viewer snow comparisons do not match Current Snow.")
    built$manifest$snow_release <- release
    interactive_write_manifest(built$manifest, output_dir)
    .stage(output_dir, site_dir)
    saveRDS(list(signature = signature, manifest_md5 = unname(tools::md5sum(file.path(output_dir, "manifest.json")))), state_path)
  }
  if (!identical(release, .get(site_dir))) stop("Current Snow changed during the viewer refresh.")
  result <- list(status = if (reused) "REUSED" else "READY", date = release$date,
    change_available = release$change_available, snow_snapshots = 1L, snow_metrics = 4L,
    elapsed_seconds = round(proc.time()[["elapsed"]] - started, 3))
  write.csv(as.data.frame(result), file.path(output_dir, "workflow-status.csv"), row.names = FALSE)
  message("Snow viewer: ", result$status, "; ", release$date, "; seven-day change ",
    if (release$change_available) "available" else "unavailable", "; ", result$elapsed_seconds, "s.")
  invisible(result)
}

refresh_interactive_snow_workflow <- function(base_result, enabled = TRUE, today = Sys.Date(),
    site_dir = "site", base_dir = "data/diagnostics/interactive-map-pilot",
    .prepare = prepare_interactive_snow_current, .refresh = stage_interactive_snow_current,
    .stage_base = stage_interactive_map_site) {
  prepared <- if (enabled) .prepare(site_dir, today) else list(status = "DISABLED", release = NULL)
  if (identical(prepared$status, "READY")) {
    snow <- .refresh(site_dir = site_dir, base_dir = base_dir, release = prepared$release)
    base_result$current_products <- base_result$current_products + 4L
    base_result$current_unavailable <- base_result$current_unavailable + as.integer(!snow$change_available)
  } else {
    # Remove a retained previous-season/explicitly disabled Snow selection.
    manifest <- jsonlite::read_json(file.path(site_dir, "interactive-maps/manifest.json"))
    if (!is.null(manifest$current$variables$snow)) .stage_base(base_dir, site_dir)
    snow <- list(status = prepared$status, date = NA_character_, change_available = FALSE, elapsed_seconds = 0)
    message("Snow viewer: ", prepared$status, "; no prior-season snapshot substituted.")
  }
  base_result$snow_status <- snow$status
  base_result$snow_date <- snow$date
  base_result$snow_change_available <- snow$change_available
  base_result$elapsed_seconds <- base_result$elapsed_seconds + snow$elapsed_seconds
  write.csv(as.data.frame(base_result), file.path(base_dir, "workflow-status.csv"), row.names = FALSE)
  invisible(base_result)
}
