# Cache-free fictional editorial review. No operational state or publication changes.
source("R/conditions-synopsis-evidence.R")
source("R/conditions-synopsis-template.R")
source("R/conditions-synopsis-regional-highlights.R")
source("R/conditions-synopsis-seasonal-review.R")
synopsis_seasonal_review <- review_conditions_synopsis_seasons()
print(synopsis_seasonal_review$summary, row.names = FALSE)
if (any(synopsis_seasonal_review$summary$status != "PASS_TEMPLATE"))
  stop("Seasonal template cases need review; see summary.csv.")
