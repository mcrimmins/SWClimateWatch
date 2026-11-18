# Local fictional seasonal review only; no downloads, APIs or publication.
source("R/conditions-synopsis-evidence.R")
source("R/conditions-synopsis-template.R")
source("R/conditions-synopsis-regional-highlights.R")
source("R/conditions-synopsis-seasonal-review.R")
synopsis_snow_review <- review_conditions_synopsis_snow()
print(synopsis_snow_review$summary,row.names=FALSE)
stopifnot(all(synopsis_snow_review$summary$status=="PASS"))
if(interactive())browseURL(normalizePath(synopsis_snow_review$path))
