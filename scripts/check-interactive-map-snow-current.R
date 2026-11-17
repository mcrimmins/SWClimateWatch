# Cached-input preflight, or post-render publication check. No downloads/upload.
source("scripts/load-snodas-current-site.R")
source("R/interactive-map-snow-current.R")
source("R/interactive-map-site.R")
release <- interactive_snow_current_release()
message("PASS: verified Current Snow cache and images for ", release$date,
  "; seven-day change ", if (release$change_available) "available" else "explicitly unavailable", ".")
if (!"--preflight" %in% commandArgs(trailingOnly = TRUE)) {
  for (rendered in c(FALSE, TRUE)) {
    validate_interactive_map_site(rendered = rendered)
    root <- if (rendered) "site/_site" else "site"
    manifest <- jsonlite::read_json(file.path(root, "interactive-maps/manifest.json"))
    if (!identical(manifest$snow_mode, "verified_current") || !identical(manifest$snow_release, release))
      stop("Viewer Snow does not match the current verified source release: ", root)
  }
  message("PASS: source and rendered Snow viewer match the VM's verified Current Snow release.")
}
