# LIVE deployment entry point for the Southwest Climate Watch website.
# Source this file from the project root in RStudio to render, validate, and
# upload site/_site/ to its dedicated S3 prefix. This changes remote objects.
# It does not download or process new PRISM data, and it does not delete remote
# objects that are absent locally.

source(file.path("scripts", "deploy-site-s3.R"))

swc_publish_result <- deploy_swc_site(
  destination = "s3://cales-climate-reports/climate/watch/",
  region = "us-west-2",
  dry_run = FALSE,
  delete = FALSE,
  render = TRUE
)
