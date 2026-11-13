# Render and deploy Southwest Climate Watch from the project root in RStudio.
# Sourcing this file defines functions only; it never uploads by itself.

swc_deploy_destination <- function(destination) {
  if (length(destination) != 1L || is.na(destination) ||
      !grepl("^s3://[^/[:space:]]+/[^/[:space:]]+(/[^/[:space:]]+)+/$", destination)) {
    stop(
      "Use an exact S3 bucket and dedicated site prefix beneath a parent folder, ending in '/'; ",
      "for example, s3://bucket/climate/sw-climate-watch/.",
      call. = FALSE
    )
  }
  prefix <- sub("^s3://[^/]+/", "", destination)
  if (grepl("(^|/)(\\.|\\.\\.)(/|$)|[?*]", prefix)) {
    stop("The S3 destination contains an unsafe prefix component.", call. = FALSE)
  }
  destination
}

swc_deploy_quarto <- function() {
  candidates <- c(
    Sys.which("quarto"),
    Sys.getenv("SWC_QUARTO", ""),
    "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.cmd",
    "C:/Program Files/Quarto/bin/quarto.cmd"
  )
  candidates <- candidates[nzchar(candidates)]
  found <- candidates[file.exists(candidates)]
  if (length(found) == 0L) {
    stop(
      "Quarto was not found. Put it on PATH or set SWC_QUARTO to quarto.cmd.",
      call. = FALSE
    )
  }
  found[[1L]]
}

swc_deploy_sync_args <- function(output_dir, destination, region, dry_run, delete) {
  c(
    "s3", "sync", shQuote(paste0(output_dir, "/")),
    shQuote(swc_deploy_destination(destination)),
    "--region", region,
    if (isTRUE(delete)) "--delete",
    if (isTRUE(dry_run)) "--dryrun"
  )
}

swc_deploy_hotlink_sync_args <- function(output_dir,destination,region,dry_run) {
  destination<-swc_deploy_destination(destination)
  c(swc_deploy_sync_args(file.path(output_dir,"maps/latest"),paste0(destination,"maps/latest/"),region,dry_run,FALSE),
    "--cache-control",shQuote("public,max-age=300,must-revalidate"))
}

swc_deploy_mutable_patterns <- function()c("*.html","*.htm","*.js","*.css","*.json","*.csv","*.xml",
  "maps/generated/prism/temperature/*-latest.png","maps/generated/prism/precipitation/*-latest.png",
  "maps/generated/snodas/current/*.png","daily-explorer/maps/*.png","daily-explorer/circulation/maps/*.png",
  "daily-explorer/circulation/means/*.png")
swc_deploy_cache_control <- function()"no-cache,max-age=0,must-revalidate"
swc_deploy_cache_policy_version <- function()"20261112-1"

swc_deploy_mutable_args <- function(output_dir,destination,region,dry_run,delete=FALSE,force=FALSE) {
  args<-if(force)c("s3","cp",shQuote(paste0(output_dir,"/")),shQuote(swc_deploy_destination(destination)),
    "--recursive","--region",region,if(dry_run)"--dryrun") else swc_deploy_sync_args(output_dir,destination,region,dry_run,delete)
  args<-c(args,"--exclude",shQuote("*"),unlist(lapply(swc_deploy_mutable_patterns(),function(p)c("--include",shQuote(p)))),
    "--exclude",shQuote("maps/latest/*"),"--exclude",shQuote("assets/cache-policy.json"),
    "--cache-control",shQuote(swc_deploy_cache_control()))
  # The one-time metadata repair need not resend the thousands of unchanged
  # historical station curves. Future changed JSONs get the policy via sync.
  if(force)args<-c(args,"--exclude",shQuote("*/history/*"),"--exclude",shQuote("daily-explorer/maps/*.png"),
    "--exclude",shQuote("daily-explorer/circulation/maps/*.png"),"--exclude",shQuote("daily-explorer/circulation/means/*.png"))
  args
}

swc_deploy_cache_policy_current <- function(aws,destination,region,capture=NULL) {
  if(is.null(capture))capture<-function(args)suppressWarnings(system2(aws,args,stdout=TRUE,stderr=TRUE))
  result<-capture(c("s3","cp",shQuote(paste0(swc_deploy_destination(destination),"assets/cache-policy.json")),"-",
    "--only-show-errors","--region",region))
  status<-attr(result,"status");if(is.null(status))status<-0L
  if(status!=0L) {
    if(any(grepl("404|NoSuchKey|Not Found|does not exist",result,ignore.case=TRUE)))return(FALSE)
    stop("Could not check the S3 cache-policy marker; inspect AWS access/connectivity.")
  }
  marker<-tryCatch(jsonlite::fromJSON(paste(result,collapse="\n")),error=function(e)NULL)
  is.list(marker)&&identical(marker$version,swc_deploy_cache_policy_version())
}

swc_deploy_write_cache_policy <- function(output_dir) {
  path<-file.path(output_dir,"assets","cache-policy.json");dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
  value<-as.character(jsonlite::toJSON(list(version=swc_deploy_cache_policy_version(),cache_control=swc_deploy_cache_control()),auto_unbox=TRUE))
  if(!file.exists(path)||!identical(paste(readLines(path,warn=FALSE),collapse="\n"),value))writeLines(value,path)
  path
}

swc_deploy_run <- function(command, args, label) {
  message(label, "...")
  status <- system2(command, args = args, stdout = "", stderr = "")
  if (!identical(as.integer(status), 0L)) {
    stop(label, " failed (exit status ", status, "); S3 upload stopped.", call. = FALSE)
  }
  invisible(status)
}

swc_deploy_validation_summary <- function(
    current_path = file.path("data", "diagnostics", "map-product-status.csv"),
    archive_path = file.path("data", "diagnostics", "archive-publication-status.csv")) {
  if (!file.exists(current_path) || !file.exists(archive_path)) {
    stop("Rendered map validation reports are missing; S3 upload stopped.",
         call. = FALSE)
  }
  current <- utils::read.csv(current_path, stringsAsFactors = FALSE)
  archive <- utils::read.csv(archive_path, stringsAsFactors = FALSE)
  if (!nrow(current) || !nrow(archive) ||
      !all(c("enabled", "validation_status") %in% names(current)) ||
      !all(c("water_year", "validation_status", "legacy_layout") %in%
             names(archive)) || anyNA(current$enabled) ||
      anyNA(current$validation_status) || anyNA(archive$validation_status)) {
    stop("Rendered map validation reports are invalid; S3 upload stopped.",
         call. = FALSE)
  }
  enabled <- current[current$enabled, , drop = FALSE]
  result <- list(
    current_passed = sum(enabled$validation_status == "PASS"),
    current_total = nrow(enabled),
    archive_passed = sum(archive$validation_status == "PASS"),
    archive_total = nrow(archive),
    archive_years = length(unique(archive$water_year)),
    legacy_layout_maps = sum(archive$legacy_layout, na.rm = TRUE))
  if (result$current_passed != result$current_total ||
      result$archive_passed != result$archive_total) {
    stop("Rendered map validation reports contain failures; S3 upload stopped.",
         call. = FALSE)
  }
  result
}

deploy_swc_site <- function(
    destination,
    region = "us-west-2",
    dry_run = TRUE,
    delete = FALSE,
    render = TRUE,
    extra_validation = NULL) {
  destination <- swc_deploy_destination(destination)
  if (length(region) != 1L || is.na(region) ||
      !grepl("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", region)) {
    stop("Specify a valid AWS region, such as us-west-2.", call. = FALSE)
  }
  if (!is.logical(dry_run) || length(dry_run) != 1L || is.na(dry_run) ||
      !is.logical(delete) || length(delete) != 1L || is.na(delete) ||
      !is.logical(render) || length(render) != 1L || is.na(render)) {
    stop("`dry_run`, `delete`, and `render` must each be TRUE or FALSE.", call. = FALSE)
  }
  if (!is.null(extra_validation) && !is.function(extra_validation)) {
    stop("`extra_validation` must be a function or NULL.", call. = FALSE)
  }
  project_dir <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  if (!file.exists(file.path(project_dir, "site", "_quarto.yml")) ||
      !file.exists(file.path(project_dir, "scripts", "build-map-product-site.R"))) {
    stop("Run this from the SWClimateWatch project root.", call. = FALSE)
  }
  aws <- Sys.which("aws")
  if (!nzchar(aws)) stop("AWS CLI was not found on PATH.", call. = FALSE)
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  if (!file.exists(rscript)) stop("Rscript was not found: ", rscript, call. = FALSE)

  message("S3 destination: ", destination)
  message("Sync mode: ", if (dry_run) "DRY RUN" else "LIVE",
          if (delete) " with deletion inside this prefix" else " without deletion")
  if (render) {
    source(file.path("R","site-cache.R"),local=TRUE)
    quarto <- swc_deploy_quarto()
    swc_deploy_run(rscript, "scripts/build-map-product-site.R", "Build and validate map catalog")
    swc_deploy_run(rscript, "scripts/stage-daily-explorer.R", "Stage cached Daily Explorer")
    swc_deploy_run(rscript, c("scripts/stage-conditions-synopsis.R", destination), "Stage cached template synopsis")
    swc_deploy_run(rscript, "scripts/stage-current-map-groups.R", "Stage grouped Current Maps")
    swc_deploy_run(rscript, "scripts/stage-cached-prism-monthly-site.R", "Stage cached Monthly Climate")
    swc_cache_version_app(file.path("site","daily-explorer"))
    swc_cache_version_app(file.path("site","stations"))
    swc_deploy_run(quarto, c("render", "site"), "Render Quarto site")
  }
  output_dir <- file.path(project_dir, "site", "_site")
  if (!file.exists(file.path(output_dir, "index.html"))) {
    stop("Rendered site/index.html is missing; nothing was uploaded.", call. = FALSE)
  }
  swc_deploy_run(
    rscript,
    c("scripts/validate-map-products.R", "--require-rendered"),
    "Validate rendered maps and pages"
  )
  validation <- swc_deploy_validation_summary()
  swc_deploy_run(rscript, "scripts/check-current-map-groups.R", "Validate grouped Current Maps")
  swc_deploy_run(rscript, "scripts/check-prism-monthly-publication.R", "Validate Monthly Climate")
  source(file.path("R", "daily-publish.R"), local = TRUE)
  swc_daily_publish_validate_explorer(output_dir)
  source(file.path("R", "conditions-synopsis-site.R"), local = TRUE)
  validate_conditions_synopsis_publication(output_dir, destination)
  output_dir <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)
  if (!is.null(extra_validation)) extra_validation(output_dir)
  # Derive hotlinks from the fully validated rendered output, including any
  # optional weather quarantine applied above. No climate processing occurs.
  for(file in c("config.R","acis-prism.R","process-prism.R","map-product-site.R","map-hotlinks.R"))
    source(file.path("R",file),local=TRUE)
  map_hotlinks <- stage_map_hotlinks(output_dir,destination)
  validate_map_hotlinks(output_dir)
  cache_policy_path<-swc_deploy_write_cache_policy(output_dir)
  migrate_cache<-isTRUE(dry_run)||!swc_deploy_cache_policy_current(aws,destination,region)
  swc_deploy_run(aws,
    swc_deploy_hotlink_sync_args(output_dir,destination,region,dry_run),
    if(dry_run)"Preview stable map links" else "Upload stable map links")
  swc_deploy_run(
    aws,
    c(swc_deploy_sync_args(output_dir, destination, region, dry_run, delete),"--exclude",shQuote("maps/latest/*"),
      unlist(lapply(swc_deploy_mutable_patterns(),function(p)c("--exclude",shQuote(p))))),
    if (dry_run) "Preview S3 sync" else "Upload site to S3"
  )
  swc_deploy_run(aws,swc_deploy_mutable_args(output_dir,destination,region,dry_run,delete),
    "Upload pages, application assets and data with revalidation")
  if(migrate_cache) {
    swc_deploy_run(aws,swc_deploy_mutable_args(output_dir,destination,region,dry_run,force=TRUE),
      "Apply cache headers to existing pages and current data (one-time per destination)")
    # Publish the marker last: interruption retries the metadata repair.
    swc_deploy_run(aws,c("s3","cp",shQuote(cache_policy_path),shQuote(paste0(destination,"assets/cache-policy.json")),
      "--region",region,"--content-type","application/json","--cache-control",shQuote(swc_deploy_cache_control()),if(dry_run)"--dryrun"),
      "Record completed cache-policy upgrade")
  }
  if (dry_run) {
    message("Dry run complete; no S3 objects were changed.")
  } else {
    commit_conditions_synopsis_publication(destination)
    message("Site sync complete: ", destination)
  }
  invisible(list(destination = destination, dry_run = dry_run, delete = delete,
                 validation = validation,hotlinks=nrow(map_hotlinks)))
}
