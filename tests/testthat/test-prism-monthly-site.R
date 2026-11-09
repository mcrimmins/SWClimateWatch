for (name in c("prism-monthly", "prism-monthly-audit", "prism-monthly-temperature",
    "prism-monthly-precipitation", "prism-monthly-ranking-pilots", "prism-monthly-spi", "prism-monthly-update")) {
  source(file.path(project_root, "R", paste0(name, ".R")))
}
source(file.path(project_root, "R/prism-monthly-site.R"))

testthat::test_that("monthly release stages all twelve maps and rejects corruption before replacing a page", {
  root <- tempfile("monthly-site-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  ranking <- file.path(root, "rankings"); spi <- file.path(root, "spi"); site <- file.path(root, "site")
  jobs <- monthly_site_products("2026-10", ranking, spi)
  for (i in seq_len(nrow(jobs))) {
    dir.create(jobs$folder[i], recursive = TRUE, showWarnings = FALSE)
    grDevices::png(jobs$source[i], width = 100, height = 100)
    graphics::par(mar = rep(0,4)); graphics::plot.new(); grDevices::dev.off()
    saveRDS(list(signature = "fixture", files = jobs$source[i], md5 = unname(tools::md5sum(jobs$source[i]))), file.path(jobs$folder[i], "complete.rds"))
  }
  dir.create(file.path(site, "assets"), recursive = TRUE)
  file.copy(file.path(project_root, "site/assets/monthly-climate.js"), file.path(site, "assets"))
  staged <- stage_prism_monthly_site("2026-10", site, ranking, spi, .verify_sources = FALSE)
  report <- validate_prism_monthly_publication(site_dir = site, report_dir = file.path(root, "report"))
  testthat::expect_equal(report$summary$status, "PASS")
  testthat::expect_equal(report$summary$maps, 12)
  # A checkout can import a laptop-specific release name without its ignored assets.
  wrong <- gsub(staged$version,"2026-10-0000000000000000",readLines(staged$page),fixed=TRUE)
  writeLines(wrong,staged$page)
  dir.create(file.path(ranking,"2026-11"),recursive=TRUE)
  dir.create(file.path(spi,"2026-11"),recursive=TRUE)
  reconciled <- stage_cached_prism_monthly_site(site,ranking,spi,today=as.Date("2026-12-01"),.verify_sources=FALSE)
  testthat::expect_equal(reconciled$end_month,"2026-10")
  testthat::expect_false(any(grepl("0000000000000000",readLines(staged$page),fixed=TRUE)))
  testthat::expect_equal(validate_prism_monthly_publication(site,report_dir=file.path(root,"report"))$summary$status,"PASS")
  # A matching accepted release needs no expensive source audit or source downloads.
  warm <- stage_cached_prism_monthly_site(site,ranking,spi,today=as.Date("2026-12-01"),.verify_sources=TRUE)
  testthat::expect_true(warm$reused)
  page_hash <- unname(tools::md5sum(staged$page))
  writeLines("corrupt", jobs$source[1])
  testthat::expect_error(stage_prism_monthly_site("2026-10", site, ranking, spi, .verify_sources = FALSE), "Unverified")
  testthat::expect_identical(unname(tools::md5sum(staged$page)), page_hash)
  # Missing/corrupt build inputs must not replace an already verified public release.
  testthat::expect_warning(stage_cached_prism_monthly_site(site,ranking,spi,today=as.Date("2026-12-01"),
    .verify_sources=FALSE,report_dir=file.path(root,"retained")),"retained its verified")
  testthat::expect_identical(unname(tools::md5sum(staged$page)),page_hash)
  # Rendered-style HTML must contain the full release and resolve its assets.
  rendered <- file.path(root, "rendered"); dir.create(file.path(rendered, "pages"), recursive = TRUE)
  file.copy(file.path(site, "maps"), rendered, recursive = TRUE)
  file.copy(file.path(site, "assets"), rendered, recursive = TRUE)
  writeLines(readLines(staged$page), file.path(rendered, "pages/monthly-climate.html"))
  report <- validate_prism_monthly_publication(site_dir = site, rendered_dir = rendered, report_dir = file.path(root, "report"))
  testthat::expect_equal(report$summary$status, "PASS")
  unlink(file.path(rendered, "maps/generated/prism/monthly", staged$version, "spi-12month.png"))
  report <- validate_prism_monthly_publication(site_dir = site, rendered_dir = rendered, report_dir = file.path(root, "report"))
  testthat::expect_equal(report$summary$status, "FAIL")
})


testthat::test_that("cached monthly staging fails closed when neither sources nor a retained release exist", {
  root<-tempfile();dir.create(root);on.exit(unlink(root,recursive=TRUE),add=TRUE)
  testthat::expect_error(suppressWarnings(stage_cached_prism_monthly_site(file.path(root,"site"),file.path(root,"ranking"),
    file.path(root,"spi"),today=as.Date("2026-11-09"),.verify_sources=FALSE,report_dir=file.path(root,"report"))),"no verified staged release")
})
