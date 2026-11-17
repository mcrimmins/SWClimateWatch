# Staging opt-in: bind the viewer to the VM's verified Current Snow release.
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

stage_interactive_snow_current <- function(site_dir = "site",
    base_dir = "data/diagnostics/interactive-map-pilot",
    output_dir = "data/diagnostics/interactive-map-snow-current") {
  release <- interactive_snow_current_release(site_dir)
  built <- build_interactive_map_snow_pilot(output_dir = output_dir, base_dir = base_dir, published_only = TRUE)
  if (!identical(release, interactive_snow_current_release(site_dir))) stop("Current Snow changed during the viewer build.")
  layer <- built$manifest$layers[[paste0("snow-", release$date)]]
  if (!identical(layer$source_signature, release$source_signature) ||
      !identical(layer$change_available, release$change_available)) stop("Viewer snow comparisons do not match Current Snow.")
  built$manifest$snow_release <- release
  interactive_write_manifest(built$manifest, output_dir)
  result <- stage_interactive_map_site(output_dir, site_dir)
  write.csv(data.frame(status = "READY", date = release$date, change_available = release$change_available,
    snow_snapshots = 1L, snow_metrics = 4L), file.path(output_dir, "workflow-status.csv"), row.names = FALSE)
  message("Snow viewer staged: ", release$date, "; exact verified Current Snow release; no historical examples.")
  invisible(result)
}
