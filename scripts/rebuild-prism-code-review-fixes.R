# Explicit migration/review build. Uses cached inputs; rewrites local PRISM maps.
# Run on laptop first, then on staging under its normal lock before publication.
source('scripts/load-prism-review-fixes.R')
products <- read_map_product_config()
prism_review_rebuild <- update_enabled_prism_maps(products=products)
# Fall/winter normally retain completed-season last-freeze maps. Recalculate
# those retained dates too: merely repainting old departure rasters would keep
# the old conditional median after changing the subtitle/description.
families <- list(
  first=list(group='first_freeze',builder=build_current_prism_first_freeze_maps,path=prism_first_freeze_map_path),
  last=list(group='last_freeze',builder=build_current_prism_last_freeze_maps,path=prism_last_freeze_map_path),
  length=list(group='freeze_free',builder=build_current_prism_freeze_free_maps,path=prism_freeze_free_map_path))
for(spec in families) {
  built <- prism_review_rebuild[[spec$group]]
  if(is.null(built) || !is.data.frame(built) || !nrow(built) || any(built$published)) next
  product <- if(spec$group=='freeze_free') 'length' else 'observed-day'
  latest <- spec$path(product)
  if(!file.exists(latest)) next
  image <- map_product_png_info(latest)
  retained <- map_product_dated_companion(latest,image$md5)
  if(is.na(retained$date)) stop('Cannot identify retained freeze map date: ',latest)
  message('Recalculating retained ',spec$group,' comparison for ',retained$date,'.')
  spec$builder(date=retained$date,overwrite=TRUE)
}
build_map_product_site()
message('Local PRISM comparisons and catalog refreshed. No downloads or publication; review before staging.')
