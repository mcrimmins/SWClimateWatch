# Site-only deployment entry point for the Southwest Climate Watch website.
# Source this file from the project root in RStudio to render, validate, and
# upload site/_site/ to the confirmed live S3 prefix by default, or to the
# SWC_S3_DESTINATION staging prefix when that is set. This changes remote objects.
# It does not download or process new PRISM data, and it does not delete remote
# objects that are absent locally.

source(file.path("scripts", "deploy-site-s3.R"))
source(file.path("scripts", "load-daily-publish.R"))

swc_site_publish_started <- Sys.time()
swc_site_destination <- swc_daily_publish_destination()
swc_ntfy_send_safe("started", paste0("Site-only publication started: ",
                                     swc_site_destination))
swc_publish_result <- tryCatch({
  swc_ntfy_send_safe("progress", "Rendering and validating the site, then syncing it to S3.")
  result <- deploy_swc_site(
    destination = swc_site_destination,
    region = "us-west-2",
    dry_run = FALSE,
    delete = FALSE,
    render = TRUE,
    extra_validation = function(output_dir) {
      swc_daily_publish_validate_snow(output_dir)
      swc_daily_publish_validate_stations(output_dir)
    }
  )
  result$elapsed_seconds <- round(as.numeric(difftime(
    Sys.time(), swc_site_publish_started, units = "secs")), 3)
  lines <- c(paste0("Site-only publication complete in ",
                    swc_publish_elapsed(result$elapsed_seconds), "."),
             sprintf("Validated maps: %d/%d current, %d/%d historic passed.",
                     result$validation$current_passed,
                     result$validation$current_total,
                     result$validation$archive_passed,
                     result$validation$archive_total),
             if (identical(swc_site_destination,
                           swc_daily_publish_live_destination()))
               "https://cales.arizona.edu/climate/watch/"
             else paste0("S3 destination: ", swc_site_destination))
  message(paste(lines, collapse = "\n"))
  swc_ntfy_send_safe("success", paste(lines, collapse = "\n"))
  result
}, error = function(error) {
  duration <- swc_publish_elapsed(as.numeric(difftime(
    Sys.time(), swc_site_publish_started, units = "secs")))
  message("Site-only publication failed after ", duration, ".")
  swc_ntfy_send_safe("error", paste0(
    "Site-only publication failed after ", duration,
    ". Check the RStudio console for details."))
  stop(error)
})
