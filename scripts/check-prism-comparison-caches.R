# Verify the migration completed against this machine's existing input cache.
source('scripts/load-prism-review-fixes.R')
checks <- list()
check <- function(family,path,manifest_path,version,method=NULL,datatype=NULL) {
  manifest <- read_prism_manifest(manifest_path)
  row <- if(nrow(manifest) && 'path' %in% names(manifest)) manifest[manifest$path==path,,drop=FALSE] else data.frame()
  issues <- character()
  if(nrow(row)!=1L || !all(c('cache_version','md5','sample_layers') %in% names(row))) issues <- 'missing manifest record' else {
    if(!identical(as.integer(row$cache_version),as.integer(version))) issues <- c(issues,'old cache version')
    if(!file.exists(path) || !identical(unname(tools::md5sum(path)),row$md5)) issues <- c(issues,'missing or changed cache')
    if(!is.null(method) && !identical(row$method,method)) issues <- c(issues,'incorrect comparison method')
    if(file.exists(path)) {
      raster <- terra::rast(path)
      if(terra::nlyr(raster)!=as.integer(row$sample_layers)) issues <- c(issues,'incorrect layer count')
      if(!is.null(datatype) && !all(terra::datatype(raster)==datatype)) issues <- c(issues,'incorrect storage precision')
    }
  }
  checks[[length(checks)+1L]] <<- data.frame(family=family,status=if(length(issues)) 'FAIL' else 'PASS',
    version=version,note=paste(issues,collapse='; '),path=path)
}
check('first freeze',prism_first_freeze_cache_path(),prism_first_freeze_cache_manifest_path(),prism_first_freeze_cache_version)
check('last freeze',prism_last_freeze_cache_path(),prism_last_freeze_cache_manifest_path(),prism_last_freeze_cache_version)
check('freeze-free length',prism_freeze_free_cache_path(),prism_freeze_free_cache_manifest_path(),prism_freeze_free_cache_version)
date <- latest_common_prism_date('pcpn')
if(as.integer(date-prism_water_year_start(date))+1L>=3L) {
  path <- file.path(dirname(prism_water_year_maximum_cache_path()),'calendar-day',paste0(format(date,'%m-%d'),'.tif'))
  check('matched-date maximum',path,prism_water_year_maximum_cache_manifest_path(),
    prism_water_year_to_date_maximum_cache_version,'matched-water-year-to-date','FLT8S')
} else message('Maximum three-day rank is seasonally deferred until October 3.')
prism_comparison_cache_check <- do.call(rbind,checks)
dir.create('data/diagnostics/prism-code-review',recursive=TRUE,showWarnings=FALSE)
write.csv(prism_comparison_cache_check,'data/diagnostics/prism-code-review/cache-validation.csv',row.names=FALSE)
print(prism_comparison_cache_check[c('family','status','version','note')],row.names=FALSE)
if(any(prism_comparison_cache_check$status!='PASS')) stop('Comparison cache migration is incomplete; do not publish yet.')
