source(file.path(project_root, "scripts", "deploy-site-s3.R"), local = TRUE)

testthat::test_that("deployment requires an explicit dedicated S3 prefix", {
  destination <- "s3://cales-climate-reports/climate/sw-climate-watch/"
  testthat::expect_equal(swc_deploy_destination(destination), destination)
  testthat::expect_error(swc_deploy_destination("s3://cales-climate-reports/"), "dedicated site prefix")
  testthat::expect_error(swc_deploy_destination("s3://cales-climate-reports/climate/"), "dedicated site prefix")
  testthat::expect_error(swc_deploy_destination("s3://cales-climate-reports/climate//"), "dedicated site prefix")
  testthat::expect_error(swc_deploy_destination("s3://cales-climate-reports/climate/../"), "unsafe prefix")
})

testthat::test_that("S3 sync previews by default and deletion is opt-in", {
  destination <- "s3://cales-climate-reports/climate/sw-climate-watch/"
  preview <- swc_deploy_sync_args("C:/tmp/site/_site", destination, "us-west-2", TRUE, FALSE)
  testthat::expect_true("--dryrun" %in% preview)
  testthat::expect_false("--delete" %in% preview)
  testthat::expect_true("--region" %in% preview)
  mirror_preview <- swc_deploy_sync_args("C:/tmp/site/_site", destination, "us-west-2", TRUE, TRUE)
  testthat::expect_true(all(c("--dryrun", "--delete") %in% mirror_preview))
  live <- swc_deploy_sync_args("C:/tmp/site/_site", destination, "us-west-2", FALSE, FALSE)
  testthat::expect_false("--dryrun" %in% live)
  testthat::expect_false("--delete" %in% live)
})

testthat::test_that("live publish entry point uses the dedicated confirmed prefix", {
  path <- file.path(project_root, "scripts", "publish-site-s3.R")
  testthat::expect_silent(parse(file = path))
  script <- paste(readLines(path, warn = FALSE), collapse = "\n")
  testthat::expect_match(
    script, "swc_site_destination <- swc_daily_publish_destination()", fixed = TRUE
  )
  testthat::expect_match(script, "destination = swc_site_destination", fixed = TRUE)
  testthat::expect_match(script, "region = \"us-west-2\"", fixed = TRUE)
  testthat::expect_match(script, "dry_run = FALSE", fixed = TRUE)
  testthat::expect_match(script, "delete = FALSE", fixed = TRUE)
  testthat::expect_match(script, "render = TRUE", fixed = TRUE)
})


testthat::test_that("site renders reconcile monthly pages from cached local releases first", {
  script<-readLines(file.path(project_root,"scripts/deploy-site-s3.R"))
  stage<-grep('swc_deploy_run(rscript, "scripts/stage-cached-prism-monthly-site.R"',script,fixed=TRUE)
  render<-grep('swc_deploy_run(quarto, c("render", "site")',script,fixed=TRUE)
  testthat::expect_length(stage,1L)
  testthat::expect_true(stage<render)
  helper<-paste(readLines(file.path(project_root,"scripts/stage-cached-prism-monthly-site.R")),collapse="\n")
  testthat::expect_false(grepl("run_prism_monthly_update(",helper,fixed=TRUE))
})


testthat::test_that("stable images are uploaded separately with short caching and without deletion", {
  args<-swc_deploy_hotlink_sync_args("/tmp/site","s3://bucket/climate/watch/","us-west-2",TRUE)
  testthat::expect_true("--dryrun" %in% args)
  testthat::expect_false("--delete" %in% args)
  testthat::expect_true("--cache-control" %in% args)
  testthat::expect_true(any(grepl("public,max-age=300,must-revalidate",args,fixed=TRUE)))
  testthat::expect_true(any(grepl("s3://bucket/climate/watch/maps/latest/",args,fixed=TRUE)))
  script<-readLines(file.path(project_root,"scripts/deploy-site-s3.R"))
  create<-grep("map_hotlinks <- stage_map_hotlinks",script,fixed=TRUE)
  optional<-grep("extra_validation(output_dir)",script,fixed=TRUE)
  upload<-grep("Upload stable map links",script,fixed=TRUE)
  testthat::expect_true(optional<create&&create<upload)
  testthat::expect_true(any(grepl('shQuote("maps/latest/*")',script,fixed=TRUE)))
})

testthat::test_that("mutable uploads revalidate and metadata migration avoids historical bulk copies",{
  args<-swc_deploy_mutable_args("/tmp/site","s3://bucket/climate/watch/","us-west-2",TRUE)
  testthat::expect_true(all(c("sync","--dryrun","--cache-control")%in%args))
  testthat::expect_true(any(grepl("no-cache,max-age=0,must-revalidate",args,fixed=TRUE)))
  for(pattern in c("*.html","*.js","*.css","*.json"))testthat::expect_true(shQuote(pattern)%in%args)
  force<-swc_deploy_mutable_args("/tmp/site","s3://bucket/climate/watch/","us-west-2",TRUE,force=TRUE)
  testthat::expect_true(all(c("cp","--recursive","--dryrun")%in%force))
  testthat::expect_false("--delete"%in%force)
  testthat::expect_true(shQuote("*/history/*")%in%force)
  testthat::expect_true(shQuote("assets/cache-policy.json")%in%args)
  testthat::expect_error(swc_deploy_cache_policy_current("aws","s3://bucket/climate/watch/","us-west-2",
    capture=function(args)structure("AccessDenied",status=1L)),"AWS access")
  testthat::expect_false(swc_deploy_cache_policy_current("aws","s3://bucket/climate/watch/","us-west-2",
    capture=function(args)structure("404 Not Found",status=1L)))
  testthat::expect_true(swc_deploy_cache_policy_current("aws","s3://bucket/climate/watch/","us-west-2",
    capture=function(args)jsonlite::toJSON(list(version=swc_deploy_cache_policy_version()),auto_unbox=TRUE)))
  script<-readLines(file.path(project_root,"scripts/deploy-site-s3.R"))
  testthat::expect_true(grep('"Apply cache headers',script)<grep('"Record completed cache-policy upgrade"',script))
  testthat::expect_true(grep('swc_cache_version_app(file.path("site","daily-explorer"))',script,fixed=TRUE)<grep('c("render", "site")',script,fixed=TRUE))
})
