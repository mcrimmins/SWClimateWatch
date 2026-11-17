# Transfer only the reviewed monthly payloads; rebuild daily/current data on the VM.
copy_interactive_monthly_seed <- function(from, to, verify_only=FALSE) {
  if(!file.exists(file.path(from,"manifest.json"))) stop("Monthly viewer manifest missing: ",from)
  manifest <- jsonlite::read_json(file.path(from,"manifest.json"))
  expected <- names(interactive_pilot_definitions(manifest$end_month))
  if (!all(expected %in% names(manifest$layers))) stop("Monthly viewer seed is incomplete.")
  layers <- manifest$layers[expected]
  for (layer in layers) {
    if (!identical(basename(layer$file),layer$file)) stop("Unsafe monthly seed filename.")
    path <- file.path(from,layer$file); receipt <- paste0(path,".md5")
    if (!file.exists(path) || file.info(path)$size != layer$bytes || !file.exists(receipt) ||
        !identical(readLines(receipt,warn=FALSE),unname(tools::md5sum(path))))
      stop("Unverified monthly seed: ",layer$file)
  }
  if (!file.exists(file.path(from,"boundaries.json"))) stop("Monthly seed boundaries missing.")
  if(isTRUE(verify_only)) return(invisible(list(manifest=manifest)))
  dir.create(to,recursive=TRUE,showWarnings=FALSE)
  for (layer in layers) for (name in c(layer$file,paste0(layer$file,".md5")))
    interactive_pilot_copy(file.path(from,name),file.path(to,name))
  interactive_pilot_copy(file.path(from,"boundaries.json"),file.path(to,"boundaries.json"))
  manifest$layers <- layers; manifest$current <- NULL; manifest$daily <- NULL; manifest$schema <- 2L
  temporary <- tempfile(fileext=".json")
  on.exit(unlink(temporary),add=TRUE)
  jsonlite::write_json(manifest,temporary,auto_unbox=TRUE,pretty=TRUE,digits=16)
  interactive_pilot_copy(temporary,file.path(to,"manifest.json"))
  message("Monthly viewer seed: ",length(layers)," verified bundles; ",manifest$end_month,"; ",to)
  invisible(list(manifest=manifest))
}

stage_cached_interactive_map_site <- function(seed_dir="data/processed/interactive-map-monthly-seed",
    output_dir="data/diagnostics/interactive-map-pilot", days=30L, site_dir="site") {
  pilot <- copy_interactive_monthly_seed(seed_dir,output_dir)
  for (name in c("index.html","pilot.js","pilot.css"))
    interactive_pilot_copy(file.path("scripts/interactive-map-assets",name),file.path(output_dir,name))
  for (name in c("leaflet.js","leaflet.css","leaflet-package-LICENSE"))
    interactive_pilot_copy(file.path("site/stations",name),file.path(output_dir,name))
  pilot <- add_interactive_daily_maps(pilot,output_dir=output_dir,days=days)
  pilot <- add_interactive_current_maps(pilot,output_dir=output_dir)
  stopifnot(all(pilot$checks$passed))
  stage_interactive_map_site(pilot_dir=output_dir,site_dir=site_dir)
  message("Interactive Maps prepared from VM caches. Monthly remains the reviewed October snapshot; no downloads or publication.")
  invisible(pilot)
}
