# Full-site render refreshes the sidebar across all pages. No S3 sync.
source("R/interactive-map-site.R")
source("scripts/deploy-site-s3.R") # Function definitions only.
validate_interactive_map_site()
interactive_site_quarto <- swc_deploy_quarto()
if (.Platform$OS.type == "windows") interactive_site_quarto <- utils::shortPathName(interactive_site_quarto)
args <- interactive_map_preview_render_args(full_site = getOption("swc.interactive.full_site", TRUE))
message("Rendering local preview in place; existing preview servers can remain open.")
status <- system2(interactive_site_quarto, args, stdin = if (.Platform$OS.type == "windows") "NUL" else "")
if (status != 0L) stop("Interactive Maps local render failed. Nothing published.")
validate_interactive_map_site(rendered = TRUE)
source("scripts/serve-interactive-map-site-preview.R")
