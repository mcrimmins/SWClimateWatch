# Isolated new-page render: avoids touching unrelated station output during local review.
source("scripts/load-prism-monthly.R")
source("R/regional-seasonal-reference.R")
source("R/regional-climate-site.R")
source("scripts/deploy-site-s3.R")
root <- "data/diagnostics/climate-of-region-render-check/site"
paths <- c("pages/climate-of-region.qmd", "styles.css", "assets/climate-reference.js",
  "assets/current-map-groups/temperature-tabs.css", "_includes/google-analytics.html",
  "assets/site-analytics.js", "assets/branding/southwest-climate-watch-mark-transparent.png")
manifest_root <- "maps/generated/prism/regional-reference/1991-2020"
manifest <- jsonlite::read_json(file.path("site", manifest_root, "manifest.json"), simplifyVector = TRUE)
paths <- c(paths, file.path(manifest_root, c(manifest$products$file, "manifest.json")))
for (path in paths) {
  destination <- file.path(root, path)
  dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
  stopifnot(file.copy(file.path("site", path), destination, overwrite = TRUE))
}
config <- yaml::yaml.load(paste(readLines("site/_quarto.yml", encoding = "UTF-8", warn = FALSE), collapse = "\n"))
config$project$resources <- c(paste0(manifest_root, "/**"), "assets/climate-reference.js", "assets/site-analytics.js")
config$project$render <- list("pages/climate-of-region.qmd")
config_text <- yaml::as.yaml(config)
# R yaml emits YAML 1.1 yes/no; Quarto reads strict YAML 1.2 booleans.
config_text <- gsub(": yes(\\n|$)", ": true\\1", config_text)
config_text <- gsub(": no(\\n|$)", ": false\\1", config_text)
writeLines(config_text, file.path(root, "_quarto.yml"), useBytes = TRUE)
quarto <- swc_deploy_quarto()
if (.Platform$OS.type == "windows") quarto <- utils::shortPathName(quarto)
status <- system2(quarto, c("render", root), stdin = if (.Platform$OS.type == "windows") "NUL" else "")
if (status != 0L) stop("Isolated reference-page render failed.")
print(validate_regional_climate_reference_site(site_dir = root, rendered = TRUE))
