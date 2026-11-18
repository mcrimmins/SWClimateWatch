source(file.path(project_root,'R/regional-seasonal-reference.R'))
source(file.path(project_root,'R/regional-climate-site.R'))
source(file.path(project_root,'R/regional-climate-release.R'))
source(file.path(project_root,'R/map-hotlinks.R'))

regional_release_fixture <- function(root) {
  dir.create(root,recursive=TRUE)
  jobs <- regional_climate_site_jobs('a','s','p','d')
  for(file in jobs$file) writeBin(as.raw(c(137,80,78,71,13,10,26,10,0)),file.path(root,file))
  jobs$md5 <- unname(tools::md5sum(file.path(root,jobs$file)))
  manifest <- list(schema_version=1L,start_year=1991L,end_year=2020L,required_complete_periods=30L,
    precipitation_share_enabled=TRUE,daily_reference_enabled=TRUE,layout_version=2L,
    products=jobs[c('id','period','variable','file','md5')])
  jsonlite::write_json(manifest,file.path(root,'manifest.json'),auto_unbox=TRUE,dataframe='rows')
  proofs <- c('monthly-sources.csv','daily-sources.csv','annual-methods.csv','seasonal-methods.csv','share-methods.csv','daily-methods.csv')
  for(file in proofs) writeLines('verified provenance fixture',file.path(root,file))
  files <- data.frame(file=c(jobs$file,'manifest.json',proofs))
  files$md5 <- unname(tools::md5sum(file.path(root,files$file)))
  jsonlite::write_json(list(schema_version=1L,release_id=regional_climate_release_signature(files),files=files),file.path(root,'release.json'),auto_unbox=TRUE,dataframe='rows')
  jobs
}

testthat::test_that('portable references verify without original climate grids and catch damage', {
  root <- tempfile(); on.exit(unlink(root,recursive=TRUE),add=TRUE)
  jobs <- regional_release_fixture(root)
  testthat::expect_silent(verify_regional_climate_release(root))
  writeLines('damage',file.path(root,jobs$file[1]))
  testthat::expect_error(verify_regional_climate_release(root),'missing or changed')
  testthat::expect_error(verify_regional_climate_release(file.path(root,'missing')),'transfer')
})

testthat::test_that('portable staging uses the bundle and registers 39 stable reference links', {
  withr::local_dir(project_root)
  root <- tempfile(); on.exit(unlink(root,recursive=TRUE),add=TRUE)
  release <- file.path(root,'release'); jobs <- regional_release_fixture(release)
  site <- file.path(root,'site'); dir.create(file.path(site,'pages'),recursive=TRUE); dir.create(file.path(site,'assets'))
  writeLines(c('project:','  resources:','    - maps/generated/prism/monthly/**','website:','  sidebar:','    contents:',
    '      - href: pages/methods.qmd','        text: About'),file.path(site,'_quarto.yml'))
  staged <- stage_cached_regional_climate_site(release,site)
  testthat::expect_equal(nrow(staged),39L)
  testthat::expect_equal(validate_regional_climate_reference_site(site,rendered=FALSE,report_dir=file.path(root,'checks'))$status,'PASS')
  # Build a minimal rendered fixture for the hotlink reader.
  page <- regional_climate_page_text(jobs)
  writeLines(page,file.path(site,'pages/climate-of-region.html'))
  links <- map_hotlink_regional_rows(site)
  testthat::expect_equal(nrow(links),39L)
  testthat::expect_equal(anyDuplicated(links$alias),0L)
  testthat::expect_true('maps/latest/climate-region/winter-wet-days.png' %in% links$alias)
  testthat::expect_true('maps/latest/climate-region/annual-mean-temperature.png' %in% links$alias)
  writeLines('changed',file.path(site,'maps/generated/prism/regional-reference/1991-2020',jobs$file[1]))
  testthat::expect_error(map_hotlink_regional_rows(site),'differs')
})

testthat::test_that('deploy stages and validates regional references before S3 upload', {
  script <- readLines(file.path(project_root,'scripts/deploy-site-s3.R'))
  stage <- grep('"scripts/stage-cached-climate-of-region.R"',script,fixed=TRUE)
  render <- grep('c("render", "site")',script,fixed=TRUE)
  check <- grep('"scripts/check-climate-of-region-publication.R"',script,fixed=TRUE)
  upload <- grep('"Upload stable map links"',script,fixed=TRUE)
  testthat::expect_true(length(stage)==1L && stage<render)
  testthat::expect_true(length(check)==1L && render<check && check<upload)
})
