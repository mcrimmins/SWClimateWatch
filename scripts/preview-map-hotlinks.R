# Preview only: inspect maps already rendered locally; no downloads or S3 sync.
source("R/config.R")
source("R/acis-prism.R")
source("R/process-prism.R")
source("R/map-product-site.R")
source("R/map-hotlinks.R")
map_hotlink_preview <- stage_map_hotlinks("site/_site", "s3://cales-climate-reports/climate/watch/")
if(interactive())browseURL(normalizePath("site/_site/maps/catalog.html"))
