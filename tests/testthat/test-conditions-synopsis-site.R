source(file.path(project_root, "R/conditions-synopsis-evidence.R"))
source(file.path(project_root, "R/conditions-synopsis-template.R"))
source(file.path(project_root, "R/conditions-synopsis-seasonal-review.R"))
source(file.path(project_root, "R/conditions-synopsis-site.R"))

synopsis_site_test_context <- function(root) {
  e <- new.env()
  for (name in c("build_conditions_synopsis_draft", "synopsis_escape_html", "synopsis_format_settings", "synopsis_date_text",
      "synopsis_format_text", "synopsis_comparison_context")) e[[name]] <- get(name, envir = .GlobalEnv)
  e
}

synopsis_site_render_fixture <- function(root) {
  if(dir.exists(file.path(root,"site/synopsis-evidence"))) {
    dir.create(file.path(root,"site/_site"),recursive=TRUE,showWarnings=FALSE)
    file.copy(file.path(root,"site/synopsis-evidence"),file.path(root,"site/_site"),recursive=TRUE)
  }
  content <- readLines(file.path(root, "site/pages/_synopsis-content.qmd"))
  content <- content[-c(1L, length(content))]
  dir.create(file.path(root, "site/_site/pages"), recursive = TRUE, showWarnings = FALSE)
  writeLines(c('<html><body><div role="tab" aria-selected="true">Maps</div><div role="tab" aria-selected="false">Synopsis</div>', content, '</body></html>'), file.path(root, "site/_site/index.html"))
  writeLines(c('<html><body>', content, '</body></html>'), file.path(root, "site/_site/pages/synopsis.html"))
}

testthat::test_that("template staging is destination-specific and success state advances only on commit", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  config <- synopsis_config(file.path(project_root, "config/conditions-synopsis.yml"))
  evidence <- synopsis_seasonal_fixture(synopsis_seasonal_cases()[1L, ], config)
  evidence$data_kind <- NULL # Unit fixture, never a real site deployment.
  destination <- "s3://cales-climate-reports/climate/watch-staging/"
  live <- "s3://cales-climate-reports/climate/watch/"
  paths <- synopsis_publication_paths(destination, root)
  staged <- stage_conditions_synopsis(root, destination, builder = function() evidence, context_loader = synopsis_site_test_context)
  testthat::expect_equal(staged$status, "READY")
  testthat::expect_false(file.exists(paths$success))
  testthat::expect_false(identical(paths$success, synopsis_publication_paths(live, root)$success))
  synopsis_site_render_fixture(root)
  testthat::expect_invisible(validate_conditions_synopsis_publication(file.path(root, "site/_site"), destination, root))
  testthat::expect_true(nrow(staged$support_manifest)>0)
  proof <- file.path(root,"site/_site",staged$support_manifest$path[1L])
  original <- readBin(proof,"raw",n=file.info(proof)$size)
  writeLines("changed supporting evidence",proof)
  testthat::expect_error(validate_conditions_synopsis_publication(file.path(root,"site/_site"),destination,root),"supporting evidence")
  writeBin(original,proof)

  commit_conditions_synopsis_publication(destination, root, dry_run = TRUE)
  testthat::expect_false(file.exists(paths$success))
  commit_conditions_synopsis_publication(destination, root)
  before <- tools::md5sum(paths$success)
  testthat::expect_equal(readRDS(paths$success)$kind, "successful_publication")
  # Failed build replaces the visible text with a waiting notice, not stale claims.
  waiting <- stage_conditions_synopsis(root, destination, builder = function() stop("incomplete inputs"), context_loader = synopsis_site_test_context)
  testthat::expect_equal(waiting$status, "WAITING")
  synopsis_site_render_fixture(root)
  testthat::expect_invisible(validate_conditions_synopsis_publication(file.path(root, "site/_site"), destination, root))
  commit_conditions_synopsis_publication(destination, root)
  testthat::expect_identical(tools::md5sum(paths$success), before)
  write("changed", file.path(root, "site/pages/_synopsis-content.qmd"), append = TRUE)
  testthat::expect_error(validate_conditions_synopsis_publication(file.path(root, "site/_site"), destination, root), "changed")
})

testthat::test_that("synthetic evidence cannot reach staged publication", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  config <- synopsis_config(file.path(project_root, "config/conditions-synopsis.yml"))
  e <- synopsis_seasonal_fixture(synopsis_seasonal_cases()[1L, ], config)
  result <- stage_conditions_synopsis(root, builder = function() e, context_loader = synopsis_site_test_context)
  testthat::expect_equal(result$status, "WAITING")
  testthat::expect_match(result$note, "Synthetic evidence")
})

testthat::test_that("published comparisons use the prior successful snapshot even on same-date revisions", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  config <- synopsis_config(file.path(project_root, "config/conditions-synopsis.yml"))
  e <- synopsis_seasonal_fixture(synopsis_seasonal_cases()[1L, ], config)
  prior <- list(kind = "successful_publication", latest = synopsis_comparison_context(e, NULL)$state$latest)
  e$facts$value[e$facts$metric == "area_below_lower_percentile"] <- 45
  draft <- build_conditions_synopsis_draft(e, project_root, file.path(root, "draft"), publication_snapshot = prior, comparison_origin = "successful_publication")
  text <- paste(vapply(draft$blocks, function(b) b$text, character(1)), collapse = " ")
  testthat::expect_match(text, "last successful publication dated")
  testthat::expect_false(grepl("local comparison dated", text))
  testthat::expect_equal(jsonlite::read_json(file.path(root, "draft/draft-evidence.json"))$comparison_kind, "successful_publication")
  testthat::expect_false(file.exists(file.path(root, "draft/preview-state.rds")))
})

testthat::test_that("all deploy paths stage and validate synopsis before upload and commit afterward", {
  script <- paste(readLines(file.path(project_root, "scripts/deploy-site-s3.R")), collapse = "\n")
  stage <- regexpr('scripts/stage-conditions-synopsis.R', script, fixed = TRUE)[[1L]]
  render <- regexpr('c("render", "site")', script, fixed = TRUE)[[1L]]
  validate <- regexpr('validate_conditions_synopsis_publication(output_dir, destination)', script, fixed = TRUE)[[1L]]
  upload <- regexpr('swc_deploy_sync_args(output_dir', script, fixed = TRUE)[[1L]]
  commit <- regexpr('commit_conditions_synopsis_publication(destination)', script, fixed = TRUE)[[1L]]
  testthat::expect_true(stage > 0 && stage < render && render < validate && validate < upload && upload < commit)
  testthat::expect_false(grepl("OPENAI|conditions-synopsis-ai", paste(readLines(file.path(project_root, "R/conditions-synopsis-site.R")), collapse = "\n")))
})


testthat::test_that("the real synopsis module loader includes snow and support helpers", {
  context <- synopsis_site_context(project_root)
  testthat::expect_true(is.function(context$synopsis_snow_evidence))
  testthat::expect_true(is.function(context$synopsis_attach_support))
})
