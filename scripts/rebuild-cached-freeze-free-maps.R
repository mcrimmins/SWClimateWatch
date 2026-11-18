# Intended for the VM under its daily lock. Writes the two affected map products only.
source("scripts/load-prism-review-fixes.R")
source("R/rebuild-cached-raster-maps.R")
cached_freeze_free_rebuild <- rebuild_cached_freeze_free_maps()
