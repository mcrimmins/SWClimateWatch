# LIVE deployment entry point for the Southwest Climate Watch website.
# Source this file from the project root in RStudio to render, validate, and
# upload site/_site/ to its dedicated S3 prefix. This changes remote objects.
# It does not download or process new PRISM data, and it does not delete remote
# objects that are absent locally.

source(file.path("scripts", "deploy-site-s3.R"))
source(file.path("scripts", "load-daily-publish.R"))

swc_ntfy_send_safe("started", "Site-only publication started.")
swc_publish_result <- tryCatch({
  swc_ntfy_send_safe("progress", "Rendering and validating the site, then syncing it to S3.")
  result <- deploy_swc_site(
    destination = "s3://cales-climate-reports/climate/watch/",
    region = "us-west-2",
    dry_run = FALSE,
    delete = FALSE,
    render = TRUE,
    extra_validation = swc_daily_publish_validate_snow
  )
  swc_ntfy_send_safe("success", "Southwest Climate Watch published successfully: https://cales.arizona.edu/climate/watch/")
  result
}, error = function(error) {
  swc_ntfy_send_safe("error", "Site-only publication failed. Check the RStudio console for details.")
  stop(error)
})
