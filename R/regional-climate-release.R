# Portable, fixed-reference publication cache. No climate computation on the VM.
regional_climate_release_dir <- function() 'data/processed/regional-climate-reference/1991-2020'
regional_climate_release_signature <- function(files) digest::digest(
  paste(paste(files$file,files$md5,sep=':'),collapse='\n'),algo='sha256',serialize=FALSE)

verify_regional_climate_release <- function(release_dir=regional_climate_release_dir()) {
  path <- file.path(release_dir,'release.json')
  if(!file.exists(path)) stop('Climate of the Region release cache is missing; transfer the prepared regional-climate seed before publishing.')
  release <- jsonlite::read_json(path,simplifyVector=TRUE)
  files <- release$files
  if(!identical(release$schema_version,1L) || !is.data.frame(files) || !nrow(files) || anyNA(files) ||
     !all(c('file','md5') %in% names(files)) || anyDuplicated(files$file) ||
     any(!grepl('^[a-zA-Z0-9_-]+[.](png|json|csv)$',files$file)) ||
     !all(file.exists(file.path(release_dir,files$file))) ||
     !identical(unname(tools::md5sum(file.path(release_dir,files$file))),files$md5)) stop('Regional climate release files are missing or changed.')
  if(!identical(regional_climate_release_signature(files),release$release_id)) stop('Regional climate release signature is invalid.')
  manifest <- jsonlite::read_json(file.path(release_dir,'manifest.json'),simplifyVector=TRUE)
  expected <- regional_climate_site_jobs('annual','seasonal','shares','daily')
  jobs <- manifest$products; rows <- match(expected$id,jobs$id)
  if(!is.data.frame(jobs) || nrow(jobs)!=39L || anyNA(rows) || anyDuplicated(jobs$id) || anyDuplicated(jobs$file) ||
     !isTRUE(manifest$start_year==1991L && manifest$end_year==2020L && manifest$required_complete_periods==30L) ||
     !isTRUE(manifest$daily_reference_enabled) || !isTRUE(manifest$precipitation_share_enabled) ||
     any(as.matrix(jobs[rows,c('period','variable','file')]) != as.matrix(expected[c('period','variable','file')])))
    stop('Regional climate release must contain the 39 accepted reference maps.')
  required <- c(expected$file,'manifest.json','monthly-sources.csv','daily-sources.csv','annual-methods.csv',
    'seasonal-methods.csv','share-methods.csv','daily-methods.csv')
  if(!setequal(files$file,required)) stop('Regional climate release is missing its required provenance records.')
  for(i in seq_len(nrow(jobs))) {
    file <- file.path(release_dir,jobs$file[i])
    if(!identical(unname(tools::md5sum(file)),jobs$md5[i]) ||
       !identical(readBin(file,'raw',n=8),as.raw(c(137,80,78,71,13,10,26,10)))) stop('Invalid reference PNG: ',jobs$file[i])
  }
  invisible(list(release=release,manifest=manifest))
}

prepare_regional_climate_release <- function(release_dir=regional_climate_release_dir()) {
  # Reverify the original reference caches and their source inventories once,
  # before making a portable release. Publishing only verifies the release.
  stage_regional_climate_reference_site()
  validate_regional_climate_reference_site(rendered=FALSE)
  source_dir <- 'site/maps/generated/prism/regional-reference/1991-2020'
  manifest <- jsonlite::read_json(file.path(source_dir,'manifest.json'),simplifyVector=TRUE)
  dir.create(release_dir,recursive=TRUE,showWarnings=FALSE)
  sources <- c(stats::setNames(file.path(source_dir,c(manifest$products$file,'manifest.json')),c(manifest$products$file,'manifest.json')),
    'monthly-sources.csv'='data/diagnostics/regional-climate-reference-pilot/source-inventory.csv',
    'daily-sources.csv'='data/diagnostics/regional-daily-reference-pilot/input-plan.csv',
    'annual-methods.csv'='data/diagnostics/regional-climate-reference-pilot/methods.csv',
    'seasonal-methods.csv'='data/diagnostics/regional-seasonal-reference-pilot/methods.csv',
    'share-methods.csv'='data/diagnostics/regional-precipitation-share-pilot/methods.csv',
    'daily-methods.csv'='data/diagnostics/regional-daily-reference-pilot/methods.csv')
  for(name in names(sources)) if(!file.copy(sources[[name]],file.path(release_dir,name),overwrite=TRUE)) stop('Could not prepare ',name)
  files <- data.frame(file=names(sources),md5=unname(tools::md5sum(file.path(release_dir,names(sources)))))
  jsonlite::write_json(list(schema_version=1L,release_id=regional_climate_release_signature(files),
    reference='1991-2020',maps=39L,files=files),file.path(release_dir,'release.json'),auto_unbox=TRUE,dataframe='rows',pretty=TRUE)
  verify_regional_climate_release(release_dir)
  message('Portable Climate of the Region release ready: 39 PNGs plus source/method/checksum records. No raw grids or year caches required on the VM.')
  invisible(release_dir)
}

stage_cached_regional_climate_site <- function(release_dir=regional_climate_release_dir(),site_dir='site') {
  release <- verify_regional_climate_release(release_dir)
  jobs <- release$manifest$products
  destination <- file.path(site_dir,'maps/generated/prism/regional-reference/1991-2020')
  dir.create(destination,recursive=TRUE,showWarnings=FALSE)
  for(file in c(jobs$file,'manifest.json')) {
    source <- file.path(release_dir,file); target <- file.path(destination,file)
    if(!file.exists(target) || !identical(unname(tools::md5sum(source)),unname(tools::md5sum(target))))
      if(!file.copy(source,target,overwrite=TRUE)) stop('Could not stage reference map ',file)
  }
  writeLines(regional_climate_page_text(jobs),file.path(site_dir,'pages/climate-of-region.qmd'),useBytes=TRUE)
  if(!file.copy('scripts/climate-reference-assets/climate-reference.js',file.path(site_dir,'assets/climate-reference.js'),overwrite=TRUE)) stop('Could not stage regional controls.')
  regional_climate_navigation(file.path(site_dir,'_quarto.yml'))
  print(validate_regional_climate_reference_site(site_dir,rendered=FALSE))
  message('Climate of the Region: 39 cached reference maps staged; no downloads or recalculation.')
  invisible(jobs)
}
