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

swc_deploy_run <- function(command, args, label) {
  message(label, "...")
  status <- system2(command, args = args, stdout = "", stderr = "")
  if (!identical(as.integer(status), 0L)) {
    stop(label, " failed (exit status ", status, "); S3 upload stopped.", call. = FALSE)
  }
  invisible(status)
}

deploy_swc_site <- function(
    destination,
    region = "us-west-2",
    dry_run = TRUE,
    delete = FALSE,
    render = TRUE) {
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
    quarto <- swc_deploy_quarto()
    swc_deploy_run(rscript, "scripts/build-map-product-site.R", "Build and validate map catalog")
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
  output_dir <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)
  swc_deploy_run(
    aws,
    swc_deploy_sync_args(output_dir, destination, region, dry_run, delete),
    if (dry_run) "Preview S3 sync" else "Upload site to S3"
  )
  if (dry_run) {
    message("Dry run complete; no S3 objects were changed.")
  } else {
    message("Site sync complete: ", destination)
  }
  invisible(list(destination = destination, dry_run = dry_run, delete = delete))
}
